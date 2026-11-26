@isTest
private class BookingCancellationLockServiceTest {

    private static Booking__c cancelledBooking() {
        BookingCancellationLockService.adminOverride = false; // act as a normal user
        return bookingAt('Cancellation');
    }

    private static Booking__c bookingAt(String stage) {
        Project__c project = new Project__c(Name = 'Cancel Lock', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert as system project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Available');
        insert as system unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today().addMonths(-2),
            Status__c = stage, Finance_Approver__c = UserInfo.getUserId()
        );
        insert as system b;
        return b;
    }

    @isTest
    static void userEditOfCancelledBookingIsBlocked() {
        Booking__c b = cancelledBooking();
        String error;
        Test.startTest();
        try {
            update as system new Booking__c(Id = b.Id, Cancellation_Reason__c = 'Changed');
        } catch (DmlException e) {
            error = e.getDmlMessage(0);
        }
        Test.stopTest();
        System.assert(error != null && error.startsWith(BookingCancellationLockService.LOCK_MESSAGE), error);
        System.assert(error.contains('Cancellation Reason'), error);
    }

    @isTest
    static void stageCannotLeaveCancellation() {
        Booking__c b = cancelledBooking();
        String error;
        try {
            update as system new Booking__c(Id = b.Id, Status__c = 'Booked');
        } catch (DmlException e) {
            error = e.getDmlMessage(0);
        }
        // Blocked (by this lock or by the stage rules in BookingStageValidationService).
        System.assertNotEquals(null, error);
    }

    @isTest
    static void refundTotalsAndBypassStillSave() {
        Booking__c b = cancelledBooking();
        Test.startTest();
        // What the refund recalculation writes.
        update as system new Booking__c(Id = b.Id, Total_Base_Paid__c = 100, Pending_Amount__c = 0);
        // Trusted system code.
        BookingCancellationLockService.bypass = true;
        update as system new Booking__c(Id = b.Id, Cancellation_Reason__c = 'System');
        BookingCancellationLockService.bypass = false;
        Test.stopTest();
        Booking__c after = [SELECT Total_Base_Paid__c, Cancellation_Reason__c FROM Booking__c WHERE Id = :b.Id WITH SYSTEM_MODE];
        System.assertEquals(100, after.Total_Base_Paid__c);
        System.assertEquals('System', after.Cancellation_Reason__c);
    }

    @isTest
    static void refundCanBeCreatedOnCancelledBooking() {
        Booking__c b = cancelledBooking();
        ContentVersion cv = new ContentVersion(Title = 'Cancellation letter', PathOnClient = 'letter.pdf',
            VersionData = Blob.valueOf('x'), FirstPublishLocationId = b.Id);
        cv.put('Document_Category__c', 'Cancellation');
        insert as system cv;

        Test.startTest();
        insert as system new Refund__c(
            Booking__c = b.Id, Refund_Date__c = Date.today(), Refund_Amount__c = 50,
            Refund_Type__c = 'Cancellation Refund', Status__c = 'Approved',
            Refund_Reason__c = 'Cancellation', Requested_Date__c = Date.today()
        );
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Refund__c WHERE Booking__c = :b.Id WITH SYSTEM_MODE]);
    }

    @isTest
    static void otherStagesAreNotLocked() {
        Booking__c b = bookingAt('Booked');
        update as system new Booking__c(Id = b.Id, Cancellation_Reason__c = 'Editable');
        System.assertEquals('Editable', [SELECT Cancellation_Reason__c FROM Booking__c WHERE Id = :b.Id WITH SYSTEM_MODE].Cancellation_Reason__c);
    }

    @isTest
    static void systemAdministratorCanStillEdit() {
        Booking__c b = cancelledBooking();
        BookingCancellationLockService.adminOverride = true;
        update as system new Booking__c(Id = b.Id, Cancellation_Reason__c = 'Admin fix');
        System.assertEquals('Admin fix', [SELECT Cancellation_Reason__c FROM Booking__c WHERE Id = :b.Id WITH SYSTEM_MODE].Cancellation_Reason__c);

        // The real profile check (the test runs as the deploying admin or another profile).
        BookingCancellationLockService.adminOverride = null;
        String profileName = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId()].Name;
        System.assertEquals(profileName == BookingCancellationLockService.ADMIN_PROFILE,
            BookingCancellationLockService.isSystemAdministrator());
    }
}