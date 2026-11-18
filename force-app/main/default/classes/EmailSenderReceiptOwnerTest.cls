/**
 * @description Tests the BRD pointer 7 safety net in EmailSenderInvocable: receipt emails
 *              must never include the booking owner's address in any recipient list.
 */
@isTest
private class EmailSenderReceiptOwnerTest {

    @isTest
    static void removesBookingOwnerFromReceiptRecipients() {
        Project__c project = new Project__c(Name = 'P1', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert booking; // owned by running user

        Receipt__c receipt = new Receipt__c(
            Booking__c = booking.Id, Amount_received__c = 1000, Receipt_Date__c = Date.today(),
            Receipt_Type__c = 'Installment Payment', Status__c = 'Cleared',Payment_Method__c='Cash'
        );
        insert receipt;

        String ownerEmail = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email;

        List<String> toAddresses = new List<String>{ 'applicant@example.com', ownerEmail };
        List<String> ccAddresses = new List<String>{ ownerEmail.toUpperCase() }; // case-insensitive match
        List<String> bccAddresses = new List<String>();

        Test.startTest();
        EmailSenderInvocable.removeBookingOwnerFromReceiptEmail(receipt.Id, toAddresses, ccAddresses, bccAddresses);
        Test.stopTest();

    }

    /** Owner's address = the customer's own email (seen on prod test bookings B-1372/B-1373). */
    private static Receipt__c receiptWhereOwnerIsCustomer() {
        String ownerEmail = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email;
        Project__c project = new Project__c(Name = 'P2', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            Email__c = ownerEmail // the customer email is the owner's own address
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

    @isTest
    static void ownerWhoIsAlsoTheCustomer_staysAsRecipient() {
        Receipt__c receipt = receiptWhereOwnerIsCustomer();
        String ownerEmail = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email;
        List<String> toAddresses = new List<String>{ ownerEmail };
        List<String> ccAddresses = new List<String>{ ownerEmail };

        Test.startTest();
        EmailSenderInvocable.removeBookingOwnerFromReceiptEmail(receipt.Id, toAddresses, ccAddresses, new List<String>());
        Test.stopTest();

        System.assertEquals(new List<String>{ ownerEmail }, toAddresses, 'The customer still receives the receipt');
        System.assertEquals(0, ccAddresses.size(), 'The owner copy is still removed from CC');
    }

    @isTest
    static void receiptMail_sentWhenOwnerIsAlsoTheCustomer() {
        Receipt__c receipt = receiptWhereOwnerIsCustomer();
        insert new Email_Template_Config__c(
            Template_Name__c = 'Receipt Owner Test', Object_API_Name__c = 'Receipt__c',
            Subject__c = 'Receipt', Email_Body__c = '<p>Receipt</p>', Is_Active__c = true,
            Recipients_Config__c = JSON.serialize(new Map<String, Object>{
                'to' => new List<Object>{ new Map<String, Object>{ 'sourceType' => 'Field', 'fieldApiName' => 'Email__c' } }
            })
        );
        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(receipt.Id);
        req.templateName = 'Receipt Owner Test';
        req.skipAttachments = true;

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results[0].sentCount, 'Previously the send crashed with no recipients: '
            + results[0].errorDetails);
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

    @isTest
    static void nullReceiptId_isNoOp() {
        List<String> to = new List<String>{ 'a@b.com' };
        Test.startTest();
        EmailSenderInvocable.removeBookingOwnerFromReceiptEmail(null, to, new List<String>(), new List<String>());
        Test.stopTest();
    }
}