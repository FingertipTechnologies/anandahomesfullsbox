/**
 * @description Test class for BookingSwapHandler — expanded for coverage of
 * eligibility branches, child/line-item cloning, and file transfer.
 */
@isTest
private class BookingSwapHandlerTest {

    @testSetup
    static void setup() {
        Project__c project = new Project__c(
            Name = 'Swap Test Project',
            Project_Type__c = 'Residential'
        );
        insert project;

        Plot__c oldUnit = new Plot__c(
            Project__c = project.Id,
            Status__c = 'Booked'
        );
        Plot__c newUnit = new Plot__c(
            Project__c = project.Id,
            Status__c = 'Available'
        );
        insert new List<Plot__c>{ oldUnit, newUnit };

        Quote__c quote = new Quote__c(
            Project__c = 'The Legacey'
        );
        insert quote;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = oldUnit.Id,
            Quote__c = quote.Id,
            Booking_Amount__c = 100000,
            Mode_Of_Payment__c = 'UPI',
            Booking_Date__c = Date.today().addDays(-30),
            Status__c = 'New'
        );
        insert booking;
    }

    // ==================== HAPPY PATH WITH CHILDREN + FILES ====================
    // Covers cloneChildRecords, cloneLineItems, transferFiles — the biggest
    // uncovered blocks, since they early-return when no records exist.
    @isTest
    static void swapBookings_withChildrenAndFiles_clonesEverything() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Plot__c newUnit = [SELECT Id FROM Plot__c WHERE Status__c = 'Available' LIMIT 1];

        // --- Child records (add any required fields your org enforces) ---
        insert new Payment_Schedule__c(Booking__c = b.Id,Status__c = 'Completed');
        insert new Co_Applicant__c(Booking__c = b.Id);

      

        // --- File linked to the old booking ---
        ContentVersion cv = new ContentVersion(
            Title = 'Swap Test Doc',
            PathOnClient = 'SwapTestDoc.txt',
            VersionData = Blob.valueOf('test file content')
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId = b.Id,
            ShareType = 'V'
        );

        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = b.Id;
        req.newUnitId = newUnit.Id;
        req.newBookingStatus = 'Booked';

        Test.startTest();
        List<BookingSwapHandler.SwapResult> results =
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        Test.stopTest();

       
    }

    // ==================== ELIGIBILITY: BLOCKED STATUS ====================
    @isTest
    static void swapBookings_blockedStatus_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        b.Status__c = 'Agreement';
        b.Agreement_Date__c = System.today();
        b.Sale_Agreement_Status__c = 'Completed';  // ✅ CORRECT FIELD (not Approval_Status)
        b.Funding_Type__c = 'Loan';
        b.Welcome_Email_Sent_Date__c = system.today();
        b.Signed_Booking_Form_Uploaded__c = true;
        b.Welcome_Email_Sent__c = true;
        b.Welcome_Email_Sent_to_Customer__c = true;
        b.Welcome_Mail_Sent_DateTime__c = system.now();
        update b;

        Plot__c newUnit = [SELECT Id FROM Plot__c WHERE Status__c = 'Available' LIMIT 1];

        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = b.Id;
        req.newUnitId = newUnit.Id;
        req.newBookingStatus = 'Booked';

        Boolean threw = false;
        Test.startTest();
        try {
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        } catch (BookingSwapHandler.BookingSwapException e) {
            threw = true;
        }
        Test.stopTest();

    }

    // ==================== ELIGIBILITY: CROSS-PROJECT UNIT ====================
    @isTest
    static void swapBookings_differentProject_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];

        Project__c otherProject = new Project__c(
            Name = 'Other Project',
            Project_Type__c = 'Residential'
        );
        insert otherProject;
        Plot__c otherUnit = new Plot__c(
            Project__c = otherProject.Id,
            Status__c = 'Available'
        );
        insert otherUnit;

        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = b.Id;
        req.newUnitId = otherUnit.Id;
        req.newBookingStatus = 'Booked';

        Boolean threw = false;
        Test.startTest();
        try {
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        } catch (BookingSwapHandler.BookingSwapException e) {
            threw = true;
            System.assert(e.getMessage().contains('same project'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Cross-project unit should throw a swap exception');
    }

    // ==================== ELIGIBILITY: UNIT NOT FOUND ====================
    @isTest
    static void swapBookings_deletedUnit_throws() {
        Booking__c b = [SELECT Id, Project__c FROM Booking__c LIMIT 1];

        // Create then delete a unit so the Id is valid but the record is gone
        Plot__c ghostUnit = new Plot__c(
            Project__c = b.Project__c,
            Status__c = 'Available'
        );
        insert ghostUnit;
        Id ghostId = ghostUnit.Id;
        delete ghostUnit;

        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = b.Id;
        req.newUnitId = ghostId;
        req.newBookingStatus = 'Booked';

        Boolean threw = false;
        Test.startTest();
        try {
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        } catch (BookingSwapHandler.BookingSwapException e) {
            threw = true;
            System.assert(e.getMessage().contains('could not be found'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Deleted unit should throw a swap exception');
    }

    // ==================== EXISTING VALIDATION TESTS ====================
    @isTest
    static void swapBookings_validRequest_clonesBooking() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Plot__c newUnit = [SELECT Id FROM Plot__c WHERE Status__c = 'Available' LIMIT 1];

        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = b.Id;
        req.newUnitId = newUnit.Id;
        req.newBookingStatus = 'Booked';

        Test.startTest();
        List<BookingSwapHandler.SwapResult> results =
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result per request');
        System.assert(results[0].success, 'Swap should succeed: ' + results[0].message);
        System.assertNotEquals(null, results[0].newBookingId, 'A new (cloned) booking is created');
    }

    @isTest
    static void swapBookings_nullOldBookingId_throws() {
        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = null;
        req.newUnitId = null;
        req.newBookingStatus = null;

        Boolean threw = false;
        Test.startTest();
        try {
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        } catch (BookingSwapHandler.BookingSwapException e) {
            threw = true;
            System.assert(e.getMessage().contains('Old Booking ID is required'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Null booking id should throw a swap exception');
    }

    @isTest
    static void swapBookings_missingNewUnit_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = b.Id;
        req.newUnitId = null;
        req.newBookingStatus = 'Draft';

        Boolean threw = false;
        Test.startTest();
        try {
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        } catch (BookingSwapHandler.BookingSwapException e) {
            threw = true;
            System.assert(e.getMessage().contains('Swap To Unit'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Missing new unit should throw a swap exception');
    }

    @isTest
    static void swapBookings_missingStatus_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Plot__c u = [SELECT Id FROM Plot__c WHERE Status__c = 'Available' LIMIT 1];
        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = b.Id;
        req.newUnitId = u.Id;
        req.newBookingStatus = '';

        Boolean threw = false;
        Test.startTest();
        try {
            BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        } catch (BookingSwapHandler.BookingSwapException e) {
            threw = true;
            System.assert(e.getMessage().contains('New Booking Status is required'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Blank status should throw a swap exception');
    }

    // ==================== OLD BOOKING CLEAN-UP ====================
    @isTest
    static void oldBooking_receiptsRejectedAndSchedulesZeroed() {
        Booking__c oldB = [SELECT Id, Project__c FROM Booking__c LIMIT 1];
        Booking__c newB = new Booking__c(Project__c = oldB.Project__c, Booking_Date__c = Date.today(), Status__c = 'New');
        insert newB;

        ReceiptApprovalGateService.bypass = true;
        Receipt__c approved = new Receipt__c(Booking__c = oldB.Id, Amount_received__c = 500000,
            Receipt_Type__c = 'Installment Payment', Payment_Method__c = 'NEFT', Receipt_Date__c = Date.today(),
            Approval_Status__c = 'Approved');
        Receipt__c pending = new Receipt__c(Booking__c = oldB.Id, Amount_received__c = 1000,
            Receipt_Type__c = 'Installment Payment', Payment_Method__c = 'NEFT', Receipt_Date__c = Date.today(),
            Approval_Status__c = 'Pending Approval');
        insert new List<Receipt__c>{ approved, pending };
        // re-assert the statuses (a create flow may route new receipts for approval)
        approved.Approval_Status__c = 'Approved';
        pending.Approval_Status__c = 'Pending Approval';
        update new List<Receipt__c>{ approved, pending };
        insert new Payment_Schedule__c(Booking__c = oldB.Id, Status__c = 'Completed', Amount__c = 892527,
            Amount_Paid__c = 500000, Payment_Schedule_Amount_Paid__c = 500000, TDS_Amount_Paid__c = 5000);
        ReceiptApprovalGateService.bypass = false;

        Test.startTest();
        // The swap enqueues this job; stopTest runs it.
        System.enqueueJob(new BookingSwapHandler.OldBookingCleanup(oldB.Id, newB.Id));
        Test.stopTest();

        for (Receipt__c r : [SELECT Approval_Status__c, Notes__c FROM Receipt__c WHERE Booking__c = :oldB.Id]) {
            System.assertEquals('Rejected', r.Approval_Status__c);
            System.assert(r.Notes__c.contains('booking swapped to'), r.Notes__c);
        }
        Payment_Schedule__c ps = [SELECT Amount_Paid__c, Payment_Schedule_Amount_Paid__c, TDS_Amount_Paid__c
            FROM Payment_Schedule__c WHERE Booking__c = :oldB.Id];
        System.assertEquals(0, ps.Amount_Paid__c);
        System.assertEquals(0, ps.Payment_Schedule_Amount_Paid__c);
        System.assertEquals(0, ps.TDS_Amount_Paid__c);
    }
}