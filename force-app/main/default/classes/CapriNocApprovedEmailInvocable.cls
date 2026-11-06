/**
 * Sends the approved CAPRI NOC letters to the Capri email stored on the Booking.
 */
public with sharing class CapriNocApprovedEmailInvocable {
    private static final Integer EMAIL_BATCH_SIZE = 10;

    public class Request {
        @InvocableVariable(label='NOC Record Id' description='The approved NOC record' required=true)
        public Id nocId;
    }

    public class Result {
        @InvocableVariable(label='Queued' description='Whether the CAPRI NOC email was queued')
        public Boolean queued;

        @InvocableVariable(label='Async Job Id' description='Queueable job that generates and sends the email')
        public Id asyncJobId;
    }

    @InvocableMethod(
        label='Send Approved CAPRI NOC Email'
        description='Queues the CAPRI loan NOC and any selected swap/cancellation letters for email.'
        category='Email'
    )
    public static List<Result> sendApprovedNocEmails(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<Result>();
        }

        Set<Id> nocIds = new Set<Id>();
        for (Request request : requests) {
            if (request == null || request.nocId == null) {
                throw new AuraHandledException('A NOC record ID is required.');
            }
            if (request.nocId.getSObjectType() != NOC__c.SObjectType) {
                throw new AuraHandledException('The supplied record ID must belong to NOC__c.');
            }
            nocIds.add(request.nocId);
        }

        Map<Id, NOC__c> nocsById = new Map<Id, NOC__c>([
            SELECT Id, Name, Approval_Status__c, Booking__c, Booking__r.Capri_Email__c
            FROM NOC__c
            WHERE Id IN :nocIds
            WITH SYSTEM_MODE
        ]);

        for (Id nocId : nocIds) {
            NOC__c noc = nocsById.get(nocId);
            if (noc == null) {
                throw new AuraHandledException('NOC record not found: ' + nocId);
            }
            if (noc.Approval_Status__c != 'Approved') {
                throw new AuraHandledException('Only an approved NOC can be emailed to Capri.');
            }
            if (noc.Booking__c == null) {
                throw new AuraHandledException('NOC ' + noc.Name + ' is not linked to a Booking.');
            }
            if (String.isBlank(noc.Booking__r.Capri_Email__c)) {
                throw new AuraHandledException(
                    'Enter Capri Email on Booking ' + noc.Booking__c + ' before approving the NOC.'
                );
            }
        }

        List<Id> orderedNocIds = new List<Id>();
        for (Request request : requests) {
            orderedNocIds.add(request.nocId);
        }

        Id jobId = System.enqueueJob(new SendApprovedNocEmailQueueable(orderedNocIds));
        List<Result> results = new List<Result>();
        for (Integer i = 0; i < requests.size(); i++) {
            Result result = new Result();
            result.queued = true;
            result.asyncJobId = jobId;
            results.add(result);
        }
        return results;
    }

    /**
     * The mail always carries the NOC request for the current unit. One swap letter is added for
     * every swap selected on the NOC and one cancellation letter for every cancellation selected;
     * with nothing selected only the current unit's NOC goes out.
     */
    @TestVisible
    private static List<Messaging.EmailFileAttachment> buildAttachments(NOC__c noc) {
        String unitNumber = noc.Booking__r.Unit_NumberFor__c;
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>{
            EmailPdfGenerator.generatePdfAttachment(
                'CAPRI_NOC_FORMAT_LOAN',
                noc.Id,
                buildFileName('CAPRI_NOC_Loan', unitNumber, null),
                'id'
            )
        };

        List<Id> swapIds = CapriNocPdfController.selectedSwapIds(noc);
        for (Integer i = 0; i < swapIds.size(); i++) {
            attachments.add(EmailPdfGenerator.generatePdfAttachment(
                'CAPRI_NOC_FORMAT_SWAP',
                noc.Id,
                buildFileName('CAPRI_NOC_Swap', unitNumber, swapIds.size() > 1 ? i + 1 : null),
                'id',
                new Map<String, String>{ CapriNocPdfController.RELATED_ID_PARAM => swapIds[i] }
            ));
        }

        List<Id> cancellationIds = CapriNocPdfController.selectedCancellationIds(noc);
        for (Integer i = 0; i < cancellationIds.size(); i++) {
            attachments.add(EmailPdfGenerator.generatePdfAttachment(
                'CAPRI_CANCELLATION_LETTER',
                noc.Id,
                buildFileName('CAPRI_Cancellation', unitNumber, cancellationIds.size() > 1 ? i + 1 : null),
                'id',
                new Map<String, String>{ CapriNocPdfController.RELATED_ID_PARAM => cancellationIds[i] }
            ));
        }
        return attachments;
    }

    /** What the "Send Capri NOC Mail" button shows before sending. */
    public class SendPreview {
        @AuraEnabled public String nocName;
        @AuraEnabled public String capriEmail;
        @AuraEnabled public List<String> attachmentNames;
        @AuraEnabled public Datetime lastSentOn;
        /** Filled when the mail cannot be sent; the button then only shows this reason. */
        @AuraEnabled public String blockedReason;
    }

    /**
     * For the "Send Capri NOC Mail" button on the NOC record: who the mail goes to, which letters
     * it will carry, and the reason when it cannot be sent yet.
     */
    @AuraEnabled
    public static SendPreview getSendPreview(Id nocId) {
        List<NOC__c> nocs = [
            SELECT Id, Name, NOC_Type__c, Approval_Status__c, Sent_Date__c, Booking__c,
                   Related_Cancellation_Booking__c, Related_Swap_History__c,
                   Related_Cancellation_Booking_Ids__c, Related_Swap_History_Ids__c,
                   Booking__r.Capri_Email__c, Booking__r.Unit_NumberFor__c
            FROM NOC__c
            WHERE Id = :nocId
            WITH SYSTEM_MODE
        ];
        SendPreview preview = new SendPreview();
        preview.attachmentNames = new List<String>();
        if (nocs.isEmpty()) {
            preview.blockedReason = 'NOC record not found.';
            return preview;
        }
        NOC__c noc = nocs[0];
        preview.nocName = noc.Name;
        preview.lastSentOn = noc.Sent_Date__c;
        preview.capriEmail = noc.Booking__r == null ? null : noc.Booking__r.Capri_Email__c;
        if (noc.NOC_Type__c != 'Capri NOC') {
            preview.blockedReason = 'This is not a Capri NOC, so there is no Capri mail to send.';
        } else if (noc.Approval_Status__c != 'Approved') {
            preview.blockedReason = 'The NOC must be approved before it is mailed to Capri.';
        } else if (noc.Booking__c == null) {
            preview.blockedReason = 'This NOC is not linked to a Booking.';
        } else if (String.isBlank(preview.capriEmail)) {
            preview.blockedReason = 'Enter Capri Email on the Booking before sending the NOC.';
        }

        String unitNumber = noc.Booking__r == null ? null : noc.Booking__r.Unit_NumberFor__c;
        preview.attachmentNames.add(buildFileName('CAPRI_NOC_Loan', unitNumber, null));
        Integer swapCount = CapriNocPdfController.selectedSwapIds(noc).size();
        for (Integer i = 0; i < swapCount; i++) {
            preview.attachmentNames.add(buildFileName('CAPRI_NOC_Swap', unitNumber, swapCount > 1 ? i + 1 : null));
        }
        Integer cancellationCount = CapriNocPdfController.selectedCancellationIds(noc).size();
        for (Integer i = 0; i < cancellationCount; i++) {
            preview.attachmentNames.add(
                buildFileName('CAPRI_Cancellation', unitNumber, cancellationCount > 1 ? i + 1 : null)
            );
        }
        return preview;
    }

    /**
     * Sends the Capri mail for one NOC. Called only from the "Send Capri NOC Mail" button: the mail
     * is never sent automatically on approval.
     */
    @AuraEnabled
    public static void sendNow(Id nocId) {
        SendPreview preview = getSendPreview(nocId);
        if (String.isNotBlank(preview.blockedReason)) {
            AuraHandledException blocked = new AuraHandledException(preview.blockedReason);
            blocked.setMessage(preview.blockedReason);
            throw blocked;
        }
        System.enqueueJob(new SendApprovedNocEmailQueueable(new List<Id>{ nocId }));
    }

    private static String buildFileName(String prefix, String unitNumber, Integer sequence) {
        String fileName = prefix + (String.isBlank(unitNumber) ? '' : '_' + unitNumber)
            + (sequence == null ? '' : '_' + sequence);
        return fileName.replaceAll('[^A-Za-z0-9_-]', '_') + '.pdf';
    }

    public class SendApprovedNocEmailQueueable implements Queueable, Database.AllowsCallouts {
        private final List<Id> nocIds;

        public SendApprovedNocEmailQueueable(List<Id> nocIds) {
            this.nocIds = nocIds == null ? new List<Id>() : new List<Id>(nocIds);
        }

        public void execute(QueueableContext context) {
            if (nocIds.isEmpty()) {
                return;
            }

            Integer batchSize = nocIds.size() > EMAIL_BATCH_SIZE
                ? EMAIL_BATCH_SIZE
                : nocIds.size();
            List<Id> batchIds = new List<Id>();
            for (Integer i = 0; i < batchSize; i++) {
                batchIds.add(nocIds[i]);
            }

            Map<Id, NOC__c> nocsById = new Map<Id, NOC__c>([
                SELECT Id, Name, Approval_Status__c, Related_Cancellation_Booking__c,
                       Related_Swap_History__c, Related_Cancellation_Booking_Ids__c,
                       Related_Swap_History_Ids__c, Booking__c,
                       Booking__r.Capri_Email__c, Booking__r.Unit_NumberFor__c,
                       Booking__r.Project_Name__c, Booking__r.Project__r.Name
                FROM NOC__c
                WHERE Id IN :batchIds
                WITH SYSTEM_MODE
            ]);

            List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
            for (Id nocId : batchIds) {
                NOC__c noc = nocsById.get(nocId);
                if (noc == null || noc.Approval_Status__c != 'Approved') {
                    throw new CapriNocEmailException(
                        'Approved NOC ' + nocId + ' could not be loaded for email.'
                    );
                }
                if (noc.Booking__c == null || String.isBlank(noc.Booking__r.Capri_Email__c)) {
                    throw new CapriNocEmailException(
                        'Booking and Capri Email are required for NOC ' + noc.Name + '.'
                    );
                }

                String unitNumber = noc.Booking__r.Unit_NumberFor__c;
                // Project_Name__c is a formula that can be blank; fall back to the project itself.
                String projectName = String.isNotBlank(noc.Booking__r.Project_Name__c)
                    ? noc.Booking__r.Project_Name__c
                    : (noc.Booking__r.Project__r == null ? null : noc.Booking__r.Project__r.Name);
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ noc.Booking__r.Capri_Email__c });
                email.setSubject(
                    'Request for issue of No objection Certificate for Flat - '
                    + (unitNumber == null ? '' : unitNumber)
                    + ' for Project - '
                    + (projectName == null ? '' : projectName)
                );
                email.setHtmlBody(
                    '<p>Dear Sir</p>'
                    + '<p>Please find the below NOC letters for the above subjected unit no.</p>'
                    + '<p>Thank You,<br/>CRM Team</p>'
                );
                email.setPlainTextBody(
                    'Dear Sir\n\n'
                    + 'Please find the below NOC letters for the above subjected unit no.\n\n'
                    + 'Thank You,\n\nCRM Team'
                );
                email.setWhatId(noc.Id);
                email.setSaveAsActivity(true);
                email.setFileAttachments(CapriNocApprovedEmailInvocable.buildAttachments(noc));
                messages.add(email);
            }

            Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(messages, false);
            List<String> errors = new List<String>();
            for (Integer i = 0; i < sendResults.size(); i++) {
                if (!sendResults[i].isSuccess()) {
                    for (Messaging.SendEmailError sendError : sendResults[i].getErrors()) {
                        errors.add('NOC ' + batchIds[i] + ': ' + sendError.getMessage());
                    }
                }
            }
            if (!errors.isEmpty()) {
                throw new CapriNocEmailException(String.join(errors, '; '));
            }

            // Record when the mail went out; the send button shows this before a re-send.
            List<NOC__c> sent = new List<NOC__c>();
            for (Id sentId : batchIds) {
                sent.add(new NOC__c(Id = sentId, Sent_Date__c = System.now()));
            }
            update as system sent;

            if (nocIds.size() > batchSize) {
                List<Id> remainingIds = new List<Id>();
                for (Integer i = batchSize; i < nocIds.size(); i++) {
                    remainingIds.add(nocIds[i]);
                }
                System.enqueueJob(new SendApprovedNocEmailQueueable(remainingIds));
            }
        }

    }

    public class CapriNocEmailException extends Exception {}
}