@isTest
private class RefundTriggerHandlerTest {

    private static Booking__c booking(String status) {
        Project__c project = new Project__c(Name = 'Refund Gate ' + status, Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Available');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today().addMonths(-2),
            Status__c = status, Finance_Approver__c = UserInfo.getUserId()
        );
        insert b;
        // Booking automation maps project users on insert and can clear the Finance Approver; the
        // production flow "Send Refund Notification To Finance User" needs one.
        update new Booking__c(Id = b.Id, Finance_Approver__c = UserInfo.getUserId());
        return b;
    }

    private static Refund__c refund(Id bookingId) {
        return new Refund__c(
            Booking__c = bookingId, Refund_Date__c = Date.today(), Refund_Amount__c = 50,
            Refund_Type__c = 'Cancellation Refund', Status__c = 'Approved',
            Refund_Reason__c = 'Cancellation', Requested_Date__c = Date.today()
        );
    }

    private static void upload(Id bookingId, String category) {
        ContentVersion cv = new ContentVersion(
            Title = category + ' file', PathOnClient = 'file.pdf', VersionData = Blob.valueOf('x'),
            FirstPublishLocationId = bookingId
        );
        cv.put('Document_Category__c', category);
        insert cv;
    }

    @isTest
    static void cancelledBooking_refundBlockedUntilCancellationLetterUploaded() {
        Booking__c b = booking('Cancellation');

        Test.startTest();
        String error;
        try { insert refund(b.Id); } catch (DmlException e) { error = e.getDmlMessage(0); }
        System.assertEquals(RefundTriggerHandler.CANCELLATION_LETTER_REQUIRED, error, 'No file yet');

        upload(b.Id, 'KYC Documents');
        error = null;
        try { insert refund(b.Id); } catch (DmlException e) { error = e.getDmlMessage(0); }
        System.assertEquals(RefundTriggerHandler.CANCELLATION_LETTER_REQUIRED, error, 'Other categories do not count');

        upload(b.Id, 'Cancellation');
        insert refund(b.Id);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Refund__c WHERE Booking__c = :b.Id]);
        System.assert(RefundTriggerHandler.withoutCancellationLetter(new Set<Id>{ b.Id }).isEmpty());
    }

    @isTest
    static void activeBooking_refundNotGated() {
        Booking__c b = booking('Booked');
        Test.startTest();
        insert refund(b.Id);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Refund__c WHERE Booking__c = :b.Id]);
    }

    @isTest
    static void bulkInsert_onlyBookingsWithoutLetterBlocked() {
        Booking__c withLetter = booking('Cancellation');
        upload(withLetter.Id, 'Cancellation');
        Booking__c withoutLetter = booking('Cancellation');

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(
            new List<Refund__c>{ refund(withLetter.Id), refund(withoutLetter.Id), new Refund__c(
                Refund_Date__c = Date.today(), Refund_Amount__c = 1, Refund_Type__c = 'Cancellation Refund',
                Status__c = 'Approved', Refund_Reason__c = 'Cancellation', Requested_Date__c = Date.today()) },
            false
        );
        Test.stopTest();

        System.assert(results[0].isSuccess(), 'Booking with a letter: allowed ' + results[0].getErrors());
        System.assert(!results[1].isSuccess(), 'Booking without a letter: blocked');
        System.assertEquals(RefundTriggerHandler.CANCELLATION_LETTER_REQUIRED, results[1].getErrors()[0].getMessage());
        System.assert(RefundTriggerHandler.withoutCancellationLetter(null).isEmpty());
    }
}
