/**
 * @description Generic Invocable Apex class for sending emails from Flow.
 * Works with any object type. Takes a list of record IDs and an email template name.
 * Resolves merge fields, recipients, and attachments from the Email_Template_Config__c.
 */
public with sharing class EmailSenderInvocable {

    /**
     * Problems building a mail. Not AuraHandledException: this class runs from flows, where an
     * AuraHandledException cannot be caught and silently drops the whole send.
     */
    public class EmailSenderException extends Exception {}

    public class EmailRequest {
        @InvocableVariable(label='Record IDs' description='Comma-separated record IDs or a single ID' required=true)
        public String recordIds;

        @InvocableVariable(label='Template Name' description='Name of the Email_Template_Config__c template' required=true)
        public String templateName;

        @InvocableVariable(label='Additional To Addresses' description='Comma-separated additional TO email addresses')
        public String additionalToAddresses;

        @InvocableVariable(label='Additional CC Addresses' description='Comma-separated additional CC email addresses')
        public String additionalCcAddresses;

        @InvocableVariable(label='Subject Override' description='Override the template subject (merge fields supported)')
        public String subjectOverride;

        @InvocableVariable(label='Body Override' description='Override the template body HTML (merge fields supported)')
        public String bodyOverride;

        @InvocableVariable(label='Skip Attachments' description='Set to true to skip generating attachments')
        public Boolean skipAttachments;
    }

    public class EmailResponse {
        @InvocableVariable(label='Success' description='Whether all emails were sent successfully')
        public Boolean success;

        @InvocableVariable(label='Message' description='Result message with details')
        public String message;

        @InvocableVariable(label='Sent Count' description='Number of emails successfully sent')
        public Integer sentCount;

        @InvocableVariable(label='Failed Count' description='Number of emails that failed')
        public Integer failedCount;

        @InvocableVariable(label='Error Details' description='Detailed error information if any')
        public String errorDetails;
    }

    @InvocableMethod(
        label='Send Email from Template'
        description='Sends emails using an Email_Template_Config__c template for one or more records. Works with any object.'
        category='Email'
    )
    public static List<EmailResponse> sendEmails(List<EmailRequest> requests) {
        List<EmailResponse> responses = new List<EmailResponse>();
        List<Messaging.SingleEmailMessage> allMessages = new List<Messaging.SingleEmailMessage>();
        List<RequestBuild> builds = new List<RequestBuild>();

        // 1) Build the emails for every request (no sending yet).
        List<Id> recordIdPerMessage = new List<Id>();
        for (EmailRequest request : requests) {
            RequestBuild rb = buildRequest(request);
            rb.startIndex = allMessages.size();
            allMessages.addAll(rb.messages);
            for (Integer j = 0; j < rb.messages.size(); j++) {
                recordIdPerMessage.add(j < rb.recordIds.size() ? rb.recordIds[j] : null);
            }
            builds.add(rb);
        }

        // 1b) Customer mails (receipt, demand, welcome, ...) also go to the booking's co-applicants.
        try {
            addCoApplicantCc(allMessages, bookingIdsFor(recordIdPerMessage));
        } catch (Exception ce) {
            System.debug(LoggingLevel.WARN, 'Co-applicant CC skipped: ' + ce.getMessage());
        }

        // 2) Send them ALL in a SINGLE Messaging.sendEmail call. Messaging.sendEmail counts once
        //    against the per-transaction email limit no matter how many messages it carries, so
        //    this avoids "Too many Email Invocations" when many records are processed at once
        //    (e.g. Bulk Raise Demand creating 27 demands) - BUG-0642.
        Messaging.SendEmailResult[] sendResults = allMessages.isEmpty()
            ? new List<Messaging.SendEmailResult>()
            : Messaging.sendEmail(allMessages, false);

        // 3) Map the send results back to each request and apply its field updates.
        for (RequestBuild rb : builds) {
            if (rb.buildFailed) {
                responses.add(rb.response);
                continue;
            }
            EmailResponse response = rb.response;
            Set<Id> sentRecordIds = new Set<Id>();
            for (Integer j = 0; j < rb.messages.size(); j++) {
                Messaging.SendEmailResult sr = sendResults[rb.startIndex + j];
                if (sr.isSuccess()) {
                    response.sentCount++;
                    sentRecordIds.add(rb.recordIds[j]);
                } else {
                    response.failedCount++;
                    for (Messaging.SendEmailError err : sr.getErrors()) rb.errors.add(err.getMessage());
                }
            }
            if (!sentRecordIds.isEmpty() && String.isNotBlank(rb.fieldUpdatesJson)) {
                try {
                    applyFieldUpdatesOnSend(rb.fieldUpdatesJson, rb.objectApiName, sentRecordIds);
                } catch (Exception fe) {
                    rb.errors.add('Field updates on send failed: ' + fe.getMessage());
                }
            }
            response.success = rb.errors.isEmpty();
            response.message = rb.errors.isEmpty()
                ? 'Successfully sent ' + response.sentCount + ' email(s)'
                : 'Sent ' + response.sentCount + ', Failed ' + response.failedCount;
            if (!rb.errors.isEmpty()) response.errorDetails = String.join(rb.errors, '; ');
            responses.add(response);
        }

        return responses;
    }

    /** Holds the emails built for one request until they are all sent together. */
    private class RequestBuild {
        EmailResponse response = new EmailResponse();
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Id> recordIds = new List<Id>();
        List<String> errors = new List<String>();
        String fieldUpdatesJson;
        String objectApiName;
        Integer startIndex = 0;
        Boolean buildFailed = false;
    }

    /** Builds (but does NOT send) the emails for a single request. */
    private static RequestBuild buildRequest(EmailRequest request) {
        RequestBuild rb = new RequestBuild();
        rb.response.sentCount = 0;
        rb.response.failedCount = 0;

        try {
            if (String.isBlank(request.recordIds)) {
                throw new EmailSenderException('Record IDs are required');
            }
            if (String.isBlank(request.templateName)) {
                throw new EmailSenderException('Template Name is required');
            }

            List<Email_Template_Config__c> templates = [
                SELECT Id, Name, Template_Name__c, Object_API_Name__c, Subject__c,
                       Email_Body__c, From_Address__c, Reply_To__c,
                       Recipients_Config__c, Attachments_Config__c,
                       Allow_Additional_Recipients__c, Allow_File_Upload__c,
                       Is_Active__c, Field_Updates_JSON__c
                FROM Email_Template_Config__c
                WHERE (Template_Name__c = :request.templateName OR Name = :request.templateName)
                  AND Is_Active__c = true
                LIMIT 1
            ];

            if (templates.isEmpty()) {
                throw new EmailSenderException('No active email template found with name: ' + request.templateName);
            }

            Email_Template_Config__c template = templates[0];
            String objectApiName = template.Object_API_Name__c;
            rb.fieldUpdatesJson = template.Field_Updates_JSON__c;

            List<Id> recordIds = parseRecordIds(request.recordIds);
            if (recordIds.isEmpty()) {
                throw new EmailSenderException('No valid record IDs provided');
            }

            List<String> additionalTo = parseEmails(request.additionalToAddresses);
            List<String> additionalCc = parseEmails(request.additionalCcAddresses);

            for (Id recordId : recordIds) {
                try {
                    String objApi = String.isNotBlank(objectApiName)
                        ? objectApiName
                        : recordId.getSObjectType().getDescribe().getName();
                    if (rb.objectApiName == null) rb.objectApiName = objApi;

                    Messaging.SingleEmailMessage email = buildEmail(
                        template, recordId, objApi,
                        additionalTo, additionalCc,
                        request.subjectOverride, request.bodyOverride,
                        request.skipAttachments == true
                    );

                    if (email != null) {
                        rb.messages.add(email);
                        rb.recordIds.add(recordId);
                    }
                } catch (Exception e) {
                    rb.errors.add('Record ' + recordId + ': ' + e.getMessage());
                }
            }
        } catch (EmailSenderException e) {
            rb.buildFailed = true;
            rb.response.success = false;
            rb.response.message = e.getMessage();
            rb.response.errorDetails = e.getMessage();
        } catch (Exception e) {
            rb.buildFailed = true;
            rb.response.success = false;
            rb.response.message = 'Unexpected error: ' + e.getMessage();
            rb.response.errorDetails = e.getMessage() + ' at line ' + e.getLineNumber();
        }
        return rb;
    }

    /**
     * @description Applies the template's configured "on send" field updates to the records the
     *              email was sent for. Each JSON entry is {field, type, value}; value supports
     *              the tokens NOW (datetime) and TODAY (date), true/false for checkboxes, or a
     *              literal for picklist/text/number.
     */
    @TestVisible
    public static void applyFieldUpdatesOnSend(String fieldUpdatesJson, String objectApiName, Set<Id> recordIds) {
        if (String.isBlank(fieldUpdatesJson) || recordIds == null || recordIds.isEmpty()) return;

        List<Object> entries;
        try {
            entries = (List<Object>) JSON.deserializeUntyped(fieldUpdatesJson);
        } catch (Exception e) {
            return;
        }
        if (entries == null || entries.isEmpty()) return;

        String objApi = String.isNotBlank(objectApiName)
            ? objectApiName
            : (new List<Id>(recordIds))[0].getSObjectType().getDescribe().getName();
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objApi);
        if (sot == null) return;
        Map<String, Schema.SObjectField> fieldMap = sot.getDescribe().fields.getMap();

        List<SObject> toUpdate = new List<SObject>();
        for (Id recId : recordIds) {
            SObject rec = sot.newSObject(recId);
            Boolean anySet = false;
            for (Object o : entries) {
                Map<String, Object> entry = (Map<String, Object>) o;
                String field = (String) entry.get('field');
                String fType = (String) entry.get('type');
                Object rawValue = entry.get('value');
                if (String.isBlank(field) || !fieldMap.containsKey(field.toLowerCase())) continue;
                try {
                    rec.put(field, coerceValue(fType, rawValue));
                    anySet = true;
                } catch (Exception e) {
                    // skip a value that does not fit the field
                }
            }
            if (anySet) toUpdate.add(rec);
        }
        if (!toUpdate.isEmpty()) {
            // The sender may be allowed to email the record without being able to edit it
            // (e.g. a CRM user on a booking owned by someone else). The configured "on send"
            // stamp is part of sending the template, so it is saved without sharing.
            new FieldUpdateWriter().save(toUpdate);
        }
    }

    /**
     * @description Saves the template's "Field Updates on Send" regardless of the sender's
     *              record access. Only the fields listed in the template config are set.
     */
    @TestVisible
    private static List<String> lastFieldUpdateErrors = new List<String>();

    @TestVisible
    private without sharing class FieldUpdateWriter {
        public void save(List<SObject> records) {
            lastFieldUpdateErrors = new List<String>();
            List<Database.SaveResult> results = Database.update(records, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    String msg = 'Field update on send failed for ' + records[i].Id + ': '
                        + results[i].getErrors()[0].getMessage();
                    lastFieldUpdateErrors.add(msg);
                    System.debug(LoggingLevel.WARN, msg);
                }
            }
        }
    }

    private static Object coerceValue(String type, Object rawValue) {
        String v = rawValue == null ? null : String.valueOf(rawValue);
        String t = type == null ? '' : type.toLowerCase();
        if (t == 'datetime') {
            if (String.isBlank(v) || v.equalsIgnoreCase('NOW')) return System.now();
            try { return DateTime.valueOf(v.replace('T', ' ').replace('Z', '')); }
            catch (Exception e) { return System.now(); }
        } else if (t == 'date') {
            if (String.isBlank(v) || v.equalsIgnoreCase('TODAY')) return Date.today();
            try { return Date.valueOf(v); } catch (Exception e) { return Date.today(); }
        } else if (t == 'checkbox' || t == 'boolean') {
            if (String.isBlank(v)) return true;
            return v.equalsIgnoreCase('true') || v == '1';
        } else if (t == 'number' || t == 'currency' || t == 'decimal' || t == 'percent') {
            try { return Decimal.valueOf(v); } catch (Exception e) { return null; }
        }
        return v; // picklist / text / default
    }

    private static Messaging.SingleEmailMessage buildEmail(
        Email_Template_Config__c template,
        Id recordId,
        String objectApiName,
        List<String> additionalTo,
        List<String> additionalCc,
        String subjectOverride,
        String bodyOverride,
        Boolean skipAttachments
    ) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

        // Resolve recipients from config
        List<String> toAddresses = new List<String>();
        List<String> ccAddresses = new List<String>();
        List<String> bccAddresses = new List<String>();

        if (String.isNotBlank(template.Recipients_Config__c)) {
            resolveRecipients(template.Recipients_Config__c, recordId, objectApiName,
                              toAddresses, ccAddresses, bccAddresses);
        }

        // Add additional recipients
        toAddresses.addAll(additionalTo);
        ccAddresses.addAll(additionalCc);

        // BRD (booking flow 132-136, receipt approval 184): the receipt PDF is emailed to the
        // applicants with the Booking Owner in CC. A Receipt has no owner of its own (it is a child
        // of the Booking), so a template's "Record Owner" CC resolves to nothing - add the booking
        // owner here, whatever the template says.
        if ('Receipt__c'.equalsIgnoreCase(objectApiName)) {
            addBookingOwnerToReceiptCc(recordId, toAddresses, ccAddresses, bccAddresses);
        }

        // Must have at least one TO address
        if (toAddresses.isEmpty()) {
            throw new EmailSenderException('No TO recipients resolved for record ' + recordId);
        }

        email.setToAddresses(toAddresses);
        if (!ccAddresses.isEmpty()) email.setCcAddresses(ccAddresses);
        if (!bccAddresses.isEmpty()) email.setBccAddresses(bccAddresses);

        // From address
        if (String.isNotBlank(template.From_Address__c)) {
            try {
                email.setOrgWideEmailAddressId(template.From_Address__c);
            } catch (Exception e) {
                // Ignore - will send from running user
            }
        }

        // Reply-To
        if (String.isNotBlank(template.Reply_To__c)) {
            email.setReplyTo(template.Reply_To__c);
        }

        // Subject
        String subject = String.isNotBlank(subjectOverride)
            ? subjectOverride
            : template.Subject__c;
        if (String.isNotBlank(subject)) {
            subject = EmailMergeFieldResolver.resolveMergeFields(subject, recordId, objectApiName);
        }
        email.setSubject(subject);

        // Body
        String body = String.isNotBlank(bodyOverride)
            ? bodyOverride
            : template.Email_Body__c;
        if (String.isNotBlank(body)) {
            body = EmailMergeFieldResolver.resolveMergeFields(body, recordId, objectApiName);
        }
        email.setHtmlBody(body);

        // Activity tracking
        if (PostSalesConstants.isWhatIdSupported(objectApiName)) {
            email.setWhatId(recordId);
        }
        email.setSaveAsActivity(true);

        // Attachments
        if (!skipAttachments && String.isNotBlank(template.Attachments_Config__c)) {
            List<Messaging.EmailFileAttachment> attachments = generateAttachments(
                template.Attachments_Config__c, recordId, objectApiName
            );
            if (!attachments.isEmpty()) {
                email.setFileAttachments(attachments);
            }
        }

        return email;
    }

    private static void resolveRecipients(
        String recipientsConfigJson,
        Id recordId,
        String objectApiName,
        List<String> toAddresses,
        List<String> ccAddresses,
        List<String> bccAddresses
    ) {
        try {
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(recipientsConfigJson);

            resolveRecipientList(config, 'to', recordId, objectApiName, toAddresses);
            resolveRecipientList(config, 'cc', recordId, objectApiName, ccAddresses);
            resolveRecipientList(config, 'bcc', recordId, objectApiName, bccAddresses);

        } catch (Exception e) {
            System.debug('Error resolving recipients: ' + e.getMessage());
        }
    }

    private static void resolveRecipientList(
        Map<String, Object> config,
        String type,
        Id recordId,
        String objectApiName,
        List<String> addresses
    ) {
        List<Object> recipientList = (List<Object>) config.get(type);
        if (recipientList == null) return;

        for (Object rec : recipientList) {
            Map<String, Object> recMap = (Map<String, Object>) rec;
            String sourceType = (String) recMap.get('sourceType');
            String fieldApiName = (String) recMap.get('fieldApiName');
            String staticEmail = (String) recMap.get('staticEmail');

            String email = EmailMergeFieldResolver.resolveRecipientEmail(
                sourceType, fieldApiName, staticEmail, recordId, objectApiName
            );

            if (String.isNotBlank(email) && isValidEmail(email)) {
                addresses.add(email);
            }
        }
    }

    private static List<Messaging.EmailFileAttachment> generateAttachments(
        String attachmentsConfigJson,
        Id recordId,
        String objectApiName
    ) {
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();

        try {
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(attachmentsConfigJson);
            List<Object> attList = (List<Object>) config.get('attachments');
            if (attList == null) return attachments;

            for (Object attObj : attList) {
                Map<String, Object> attMap = (Map<String, Object>) attObj;
                String attType = (String) attMap.get('type');
                Boolean isDefault = attMap.get('isDefaultChecked') == true;
                Boolean isRequired = attMap.get('isRequired') == true;

                // Only generate default/required attachments for flow
                if (!isDefault && !isRequired) continue;

                try {
                    if (attType == PostSalesConstants.ATTACHMENT_TYPE_VF_PAGE) {
                        String vfPageName = (String) attMap.get('vfPageName');
                        String docTemplateId = (String) attMap.get('documentTemplateId');
                        String fileNamePattern = (String) attMap.get('fileNamePattern');
                        String attName = (String) attMap.get('name');

                        String fileName = String.isNotBlank(fileNamePattern)
                            ? EmailMergeFieldResolver.resolveMergeFields(fileNamePattern, recordId, objectApiName)
                            : (String.isNotBlank(attName) ? attName + '.pdf' : 'Document.pdf');

                        Map<String, String> extraParams = new Map<String, String>();
                        if (String.isNotBlank(docTemplateId)) {
                            extraParams.put('templateId', docTemplateId);
                        }

                        Messaging.EmailFileAttachment fileAtt = EmailPdfGenerator.generatePdfAttachment(
                            vfPageName, recordId, fileName, 'id', extraParams
                        );
                        if (fileAtt != null) {
                            attachments.add(fileAtt);
                        }
                    } else if (attType == PostSalesConstants.ATTACHMENT_TYPE_STATIC_DOC) {
                        String docId = (String) attMap.get('documentId');
                        if (String.isNotBlank(docId)) {
                            Messaging.EmailFileAttachment fileAtt = EmailPdfGenerator.getStaticDocumentAttachment(docId);
                            if (fileAtt != null) {
                                attachments.add(fileAtt);
                            }
                        }
                    } else if (attType == 'UploadedFile') {
                        // Attach the uploaded file(s) of the configured Document Type (and
                        // Category) that are linked to this record (from the Document Manager).
                        String docCategory = (String) attMap.get('documentCategory');
                        String docType = (String) attMap.get('documentType');
                        attachments.addAll(getUploadedFileAttachments(
                            recordId, docCategory, docType, (String) attMap.get('name')));
                    }
                } catch (Exception e) {
                    System.debug('Error generating attachment: ' + e.getMessage());
                }
            }
        } catch (Exception e) {
            System.debug('Error processing attachments config: ' + e.getMessage());
        }

        return attachments;
    }

    /**
     * @description Returns email attachments for ALL uploaded files (Document Manager /
     *              ContentVersion) linked to the record whose Document Type matches the configured
     *              Document Type (and Category, when set). When no Document Type is configured on
     *              the attachment, the attachment name is used as the Document Type. Matching is on
     *              the Document Type only (never the file name); '_' is treated as a space. Every
     *              file under that Document Type is attached.
     */
    @TestVisible
    public static List<Messaging.EmailFileAttachment> getUploadedFileAttachments(
        Id recordId, String docCategory, String docType, String nameHint
    ) {
        List<Messaging.EmailFileAttachment> result = new List<Messaging.EmailFileAttachment>();
        if (recordId == null) return result;

        // The Document Type to attach. Falls back to the attachment name when not configured.
        String typeSelector = String.isNotBlank(docType) ? docType : nameHint;
        if (String.isBlank(typeSelector)) return result;
        String typeNorm = typeSelector.replace('_', ' ').trim();

        Set<Id> contentDocIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :recordId
        ]) {
            contentDocIds.add(link.ContentDocumentId);
        }
        if (contentDocIds.isEmpty()) return result;

        // Match on Document Type only (metadata first, no VersionData, to keep heap small).
        Set<Id> matchedCvIds = new Set<Id>();
        for (ContentVersion cv : [
            SELECT Id, Document_Type__c, Document_Category__c
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocIds AND IsLatest = true
        ]) {
            if (String.isNotBlank(docCategory) && String.isNotBlank(cv.Document_Category__c)
                && !cv.Document_Category__c.equalsIgnoreCase(docCategory)) {
                continue;
            }
            if (matchesSelector(cv.Document_Type__c, typeSelector, typeNorm)) {
                matchedCvIds.add(cv.Id);
            }
        }
        if (matchedCvIds.isEmpty()) return result;

        for (ContentVersion cv : [
            SELECT Title, FileExtension, VersionData FROM ContentVersion WHERE Id IN :matchedCvIds
        ]) {
            Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
            String ext = String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '';
            efa.setFileName(cv.Title + ext);
            efa.setBody(cv.VersionData);
            result.add(efa);
        }
        return result;
    }

    /** Loose match: exact, normalized (underscores→spaces), or with the value's own underscores normalized. */
    private static Boolean matchesSelector(String value, String selector, String selNorm) {
        if (String.isBlank(value)) return false;
        return value.equalsIgnoreCase(selector)
            || value.equalsIgnoreCase(selNorm)
            || value.replace('_', ' ').trim().equalsIgnoreCase(selNorm);
    }

    /**
     * @description Adds the email of the user who owns the Receipt's Booking to CC (BRD: receipt
     *              mails go to the applicants, CC Booking Owner). Skipped when that address already
     *              receives the mail (e.g. the owner's email is also the customer's own) or when the
     *              owner is a queue / has no email.
     */
    @TestVisible
    private static void addBookingOwnerToReceiptCc(
        Id receiptId,
        List<String> toAddresses,
        List<String> ccAddresses,
        List<String> bccAddresses
    ) {
        if (receiptId == null) return;
        try {
            List<Receipt__c> receipts = [
                SELECT Booking__r.OwnerId, Booking__r.Email__c
                FROM Receipt__c
                WHERE Id = :receiptId
                LIMIT 1
            ];
            if (receipts.isEmpty() || receipts[0].Booking__r == null) return;

            // Owner is polymorphic (User or Queue): read the user's email directly.
            Id ownerId = receipts[0].Booking__r.OwnerId;
            String ownerEmail;
            if (ownerId != null && ownerId.getSObjectType() == User.SObjectType) {
                for (User u : [SELECT Email FROM User WHERE Id = :ownerId LIMIT 1]) {
                    ownerEmail = u.Email;
                }
            }
            if (String.isBlank(ownerEmail)) return;

            if (!isValidEmail(ownerEmail)) return;
            if (containsAddress(toAddresses, ownerEmail) || containsAddress(ccAddresses, ownerEmail)
                || containsAddress(bccAddresses, ownerEmail)) {
                return;
            }
            ccAddresses.add(ownerEmail);
        } catch (Exception e) {
            System.debug('addBookingOwnerToReceiptCc failed: ' + e.getMessage());
        }
    }


    // ============ CO-APPLICANTS ============

    /**
     * @description Copies the booking's co-applicants (Co_Applicant__c records with an email) on
     *              every mail that goes to that booking's primary applicant (Booking Email). Mails
     *              not addressed to the applicant - internal, bank, Capri - are left alone.
     * @param emails             the mails about to be sent
     * @param bookingIdPerEmail  the booking each mail is about, same order as emails (null = none)
     */
    public static void addCoApplicantCc(List<Messaging.SingleEmailMessage> emails, List<Id> bookingIdPerEmail) {
        if (emails == null || emails.isEmpty() || bookingIdPerEmail == null) return;
        Set<Id> bookingIds = new Set<Id>();
        for (Id bookingId : bookingIdPerEmail) {
            if (bookingId != null) bookingIds.add(bookingId);
        }
        if (bookingIds.isEmpty()) return;

        Map<Id, String> primaryEmail = new Map<Id, String>();
        for (Booking__c b : [SELECT Id, Email__c FROM Booking__c WHERE Id IN :bookingIds WITH SYSTEM_MODE]) {
            primaryEmail.put(b.Id, b.Email__c);
        }
        Map<Id, List<String>> coEmails = new Map<Id, List<String>>();
        for (Co_Applicant__c c : [
            SELECT Booking__c, Email__c FROM Co_Applicant__c
            WHERE Booking__c IN :bookingIds AND Email__c != null
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
        ]) {
            String address = c.Email__c.trim();
            if (!isValidEmail(address)) continue;
            if (!coEmails.containsKey(c.Booking__c)) coEmails.put(c.Booking__c, new List<String>());
            coEmails.get(c.Booking__c).add(address);
        }
        if (coEmails.isEmpty()) return;

        for (Integer i = 0; i < emails.size() && i < bookingIdPerEmail.size(); i++) {
            Id bookingId = bookingIdPerEmail[i];
            if (bookingId == null || !coEmails.containsKey(bookingId)) continue;
            Messaging.SingleEmailMessage email = emails[i];
            List<String> toList = email.getToAddresses() == null ? new List<String>() : email.getToAddresses();
            List<String> ccList = email.getCcAddresses() == null ? new List<String>() : email.getCcAddresses().clone();
            List<String> bccList = email.getBccAddresses() == null ? new List<String>() : email.getBccAddresses();
            String primary = primaryEmail.get(bookingId);
            if (String.isBlank(primary) || !(containsAddress(toList, primary) || containsAddress(ccList, primary))) {
                continue;
            }
            Boolean added = false;
            for (String address : coEmails.get(bookingId)) {
                if (containsAddress(toList, address) || containsAddress(ccList, address)
                    || containsAddress(bccList, address)) {
                    continue;
                }
                ccList.add(address);
                added = true;
            }
            if (added) email.setCcAddresses(ccList);
        }
    }

    /** The booking each record belongs to: a Booking itself, or the record's Booking__c lookup. */
    @TestVisible
    private static List<Id> bookingIdsFor(List<Id> recordIds) {
        Map<String, Set<Id>> idsByObject = new Map<String, Set<Id>>();
        Map<Id, Id> bookingByRecord = new Map<Id, Id>();
        for (Id recordId : recordIds) {
            if (recordId == null) continue;
            Schema.SObjectType sot = recordId.getSObjectType();
            if (sot == Booking__c.SObjectType) {
                bookingByRecord.put(recordId, recordId);
                continue;
            }
            Schema.SObjectField bookingField = sot.getDescribe().fields.getMap().get('booking__c');
            if (bookingField == null
                || !bookingField.getDescribe().getReferenceTo().contains(Booking__c.SObjectType)) {
                continue;
            }
            String objectName = sot.getDescribe().getName();
            if (!idsByObject.containsKey(objectName)) idsByObject.put(objectName, new Set<Id>());
            idsByObject.get(objectName).add(recordId);
        }
        for (String objectName : idsByObject.keySet()) {
            Set<Id> ids = idsByObject.get(objectName);
            for (SObject r : Database.query(
                'SELECT Id, Booking__c FROM ' + objectName + ' WHERE Id IN :ids WITH SYSTEM_MODE'
            )) {
                if (r.get('Booking__c') != null) bookingByRecord.put(r.Id, (Id) r.get('Booking__c'));
            }
        }
        List<Id> result = new List<Id>();
        for (Id recordId : recordIds) {
            result.add(recordId == null ? null : bookingByRecord.get(recordId));
        }
        return result;
    }

    private static Boolean containsAddress(List<String> addresses, String address) {
        if (addresses == null || String.isBlank(address)) return false;
        for (String a : addresses) {
            if (a != null && a.trim().equalsIgnoreCase(address.trim())) return true;
        }
        return false;
    }

    // ============ UTILITY METHODS ============

    private static List<Id> parseRecordIds(String recordIdsStr) {
        List<Id> ids = new List<Id>();
        if (String.isBlank(recordIdsStr)) return ids;

        for (String idStr : recordIdsStr.split('[,;\\s]+')) {
            String trimmed = idStr.trim();
            if (String.isNotBlank(trimmed)) {
                try {
                    ids.add(Id.valueOf(trimmed));
                } catch (Exception e) {
                    System.debug('Invalid ID: ' + trimmed);
                }
            }
        }
        return ids;
    }

    private static List<String> parseEmails(String emailsStr) {
        List<String> emails = new List<String>();
        if (String.isBlank(emailsStr)) return emails;

        for (String email : emailsStr.split('[,;]+')) {
            String trimmed = email.trim();
            if (String.isNotBlank(trimmed) && isValidEmail(trimmed)) {
                emails.add(trimmed);
            }
        }
        return emails;
    }

    private static Boolean isValidEmail(String email) {
        if (String.isBlank(email)) return false;
        String emailRegex = '^[a-zA-Z0-9._|\\\\%#~`=?&/$^*!}{+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,4}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        Matcher matcher = emailPattern.matcher(email);
        return matcher.matches();
    }
}