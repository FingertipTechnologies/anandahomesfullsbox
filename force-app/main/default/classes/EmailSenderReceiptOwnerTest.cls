/**
 * @description Receipt (and other master-detail child) mails get their recipients only from the
 *              Email Template Configurator. "Record Owner" on a child record that has no owner of
 *              its own (Receipt / Demand / NOC under Booking) means the master record's owner.
 */
@isTest
private class EmailSenderReceiptOwnerTest {

    private static Receipt__c makeReceipt(String customerEmail) {
        Project__c project = new Project__c(Name = 'P1', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            Email__c = customerEmail
        );
        insert booking;
        // Booking automation may reassign the owner on insert: make the running user the owner.
        // (The customer email is set on insert: once Booked it is locked to First Applicant Change.)
        update new Booking__c(Id = booking.Id, OwnerId = UserInfo.getUserId());
        Receipt__c receipt = new Receipt__c(
            Booking__c = booking.Id, Amount_received__c = 1000, Receipt_Date__c = Date.today(),
            Receipt_Type__c = 'Installment Payment', Status__c = 'Cleared', Payment_Method__c = 'Cash'
        );
        insert receipt;
        return receipt;
    }

    private static String ownerEmail() {
        return [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email;
    }

    private static void makeTemplate(Boolean ccRecordOwner) {
        Map<String, Object> recipients = new Map<String, Object>{
            'to' => new List<Object>{ new Map<String, Object>{ 'sourceType' => 'Field', 'fieldApiName' => 'Email__c' } }
        };
        if (ccRecordOwner) {
            recipients.put('cc', new List<Object>{ new Map<String, Object>{ 'sourceType' => 'RecordOwner' } });
        }
        insert new Email_Template_Config__c(
            Template_Name__c = 'Receipt Owner Test', Object_API_Name__c = 'Receipt__c',
            Subject__c = 'Receipt', Email_Body__c = '<p>Receipt</p>', Is_Active__c = true,
            Recipients_Config__c = JSON.serialize(recipients)
        );
    }

    private static EmailSenderInvocable.EmailResponse send(Id receiptId) {
        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(receiptId);
        req.templateName = 'Receipt Owner Test';
        req.skipAttachments = true;
        return EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req })[0];
    }

    @isTest
    static void ownerPath_walksUpToTheMasterRecord() {
        System.assertEquals('Owner', EmailMergeFieldResolver.ownerPathFor('Booking__c'));
        System.assertEquals('Booking__r.Owner', EmailMergeFieldResolver.ownerPathFor('Receipt__c'));
        System.assertEquals(null, EmailMergeFieldResolver.ownerPathFor('No_Such_Object__c'));
    }

    @isTest
    static void recordOwner_onReceipt_isTheBookingOwner() {
        Receipt__c receipt = makeReceipt('applicant@example.com');
        Test.startTest();
        String resolved = EmailMergeFieldResolver.resolveRecipientEmail('RecordOwner', null, null, receipt.Id, 'Receipt__c');
        Test.stopTest();
        System.assert(ownerEmail().equalsIgnoreCase(resolved), 'Record Owner of a Receipt = booking owner, got ' + resolved);
    }

    @isTest
    static void receiptMail_ccFollowsTheConfig() {
        Receipt__c receipt = makeReceipt('applicant@example.com');
        makeTemplate(true);
        Test.startTest();
        EmailSenderInvocable.EmailResponse result = send(receipt.Id);
        Test.stopTest();
        System.assertEquals(1, result.sentCount, 'Receipt mail not sent: ' + result.errorDetails);
    }

    /** Owner's address = the customer's own email (seen on prod test bookings B-1372/B-1373). */
    @isTest
    static void receiptMail_sentWhenOwnerIsAlsoTheCustomer() {
        Receipt__c receipt = makeReceipt(ownerEmail());
        makeTemplate(true);
        Test.startTest();
        EmailSenderInvocable.EmailResponse result = send(receipt.Id);
        Test.stopTest();
        System.assertEquals(1, result.sentCount, 'Receipt mail not sent: ' + result.errorDetails);
    }

    @isTest
    static void receiptMail_withoutOwnerInConfig_stillSends() {
        Receipt__c receipt = makeReceipt('applicant@example.com');
        makeTemplate(false);
        Test.startTest();
        EmailSenderInvocable.EmailResponse result = send(receipt.Id);
        Test.stopTest();
        System.assertEquals(1, result.sentCount, 'Receipt mail not sent: ' + result.errorDetails);
    }

    /** The configurator's email field list on Receipt reaches the booking and the booking's owner. */
    @isTest
    static void fieldPicker_offersBookingAndOwnerEmails() {
        Set<String> values = new Set<String>();
        Test.startTest();
        for (EmailFieldPickerController.FieldWrapper f : EmailFieldPickerController.getEmailFieldsForObject('Receipt__c')) {
            values.add(f.value.toLowerCase());
        }
        Test.stopTest();
        System.assert(values.contains('booking__r.email__c'), 'Booking -> Email');
        System.assert(values.contains('booking__r.owner.email'), 'Booking -> Owner -> Email');
        System.assert(values.contains('email__c'), 'Receipt Email (text formula) counts as an email field');
        System.assert(EmailFieldPickerController.isEmailLike(Receipt__c.Email__c.getDescribe()));
    }

    @isTest
    static void fieldPath_bookingOwnerEmail_resolvesAndSends() {
        Receipt__c receipt = makeReceipt('applicant@example.com');
        insert new Email_Template_Config__c(
            Template_Name__c = 'Receipt Owner Test', Object_API_Name__c = 'Receipt__c',
            Subject__c = 'Receipt', Email_Body__c = '<p>Receipt</p>', Is_Active__c = true,
            Recipients_Config__c = JSON.serialize(new Map<String, Object>{
                'to' => new List<Object>{ new Map<String, Object>{ 'sourceType' => 'Field', 'fieldApiName' => 'Email__c' } },
                'cc' => new List<Object>{ new Map<String, Object>{ 'sourceType' => 'Field', 'fieldApiName' => 'Booking__r.Owner.Email' } }
            })
        );
        String resolved = EmailMergeFieldResolver.resolveRecipientEmail(
            'Field', 'Booking__r.Owner.Email', null, receipt.Id, 'Receipt__c');
        Test.startTest();
        EmailSenderInvocable.EmailResponse result = send(receipt.Id);
        Test.stopTest();
        System.assert(ownerEmail().equalsIgnoreCase(resolved), 'Booking -> Owner -> Email, got ' + resolved);
        System.assertEquals(1, result.sentCount, 'Receipt mail not sent: ' + result.errorDetails);
    }

    @isTest
    static void templateProblems_areReportedNotThrown() {
        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(UserInfo.getUserId());
        req.templateName = 'No Such Template';
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorDetails.contains('No active email template'), results[0].errorDetails);
    }
}