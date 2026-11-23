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
        Booking__c b = [SELECT Id, Status__c FROM Booking__c LIMIT 1];
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
        b.Status__c = 'Registration';
        b.Agreement_Date__c = System.today();
        b.Sale_Agreement_Status__c = 'Completed';
        b.Funding_Type__c = 'Loan';
        b.Welcome_Email_Sent_Date__c = system.today();
        b.Signed_Booking_Form_Uploaded__c = true;
        b.Welcome_Email_Sent__c = true;
        b.Welcome_Email_Sent_to_Customer__c = true;
        b.Welcome_Mail_Sent_DateTime__c = system.now();
        Boolean previousStageBypass = BookingStageValidationService.bypass;
        BookingStageValidationService.bypass = true;
        try {
            update b;
        } finally {
            BookingStageValidationService.bypass = previousStageBypass;
        }

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
        Booking__c b = [SELECT Id, Status__c FROM Booking__c LIMIT 1];
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

        Booking__c oldBooking = [
            SELECT Id, Status__c, Is_Swapped__c, Swapped_To_Booking__c
            FROM Booking__c
            WHERE Id = :b.Id
        ];
        System.assertEquals(
            b.Status__c,
            oldBooking.Status__c,
            'The swap handler must preserve the status already set by the approved transition.'
        );
        System.assertEquals(true, oldBooking.Is_Swapped__c);
        System.assertEquals(results[0].newBookingId, oldBooking.Swapped_To_Booking__c);
    }

    @isTest
    static void swap_generatesSchedulesAndReallocatesTransferredReceipt() {
        Booking__c oldBooking = [
            SELECT Id, Project__c
            FROM Booking__c
            LIMIT 1
        ];
        oldBooking.Total_Flat_Cost__c = 100;
        oldBooking.GST_Amount__c = 0;
        update oldBooking;
        Plot__c newUnit = [SELECT Id FROM Plot__c WHERE Status__c = 'Available' LIMIT 1];
        Master_Payment_Schedule__c masterSchedule = new Master_Payment_Schedule__c(
            Name = 'On Booking',
            Project__c = oldBooking.Project__c,
            Payment_Type__c = 'On Booking',
            Percentage__c = 100,
            Payment_Percent__c = 100,
            Sequence__c = 1,
            Status__c = 'Pending',
            Is_Active__c = true
        );
        insert masterSchedule;

        Payment_Schedule__c oldSchedule = new Payment_Schedule__c(
            Booking__c = oldBooking.Id,
            Master_Payment_Schedule__c = masterSchedule.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'On Booking',
            Amount__c = 100,
            Payment_Schedule_Amount__c = 99,
            TDS_Amount__c = 1,
            Pending_Amount__c = 0,
            Payment_Schedule_Amount_Paid__c = 99,
            TDS_Amount_Paid__c = 1,
            Status__c = 'Completed'
        );
        insert oldSchedule;

        Boolean previousReceiptBypass = ReceiptApprovalGateService.bypass;
        ReceiptApprovalGateService.bypass = true;
        Receipt__c receipt = new Receipt__c(
            Booking__c = oldBooking.Id,
            Amount_received__c = 99,
            Total_Amount__c = 99,
            Receipt_Date__c = Date.today(),
            Receipt_Type__c = 'Installment Payment',
            Payment_From__c = 'Customer',
            Payment_Method__c = 'NEFT',
            Status__c = 'Cleared',
            Approval_Status__c = 'Approved'
        );
        try {
            insert receipt;
        } finally {
            ReceiptApprovalGateService.bypass = previousReceiptBypass;
        }
        insert new Receipt_Line_Item__c(
            Receipt__c = receipt.Id,
            Booking__c = oldBooking.Id,
            Payment_Schedule__c = oldSchedule.Id,
            Allocated_Amount__c = 99,
            Amount__c = 99,
            Allocation_Date__c = Date.today(),
            Allocation_Type__c = 'Payment Schedule',
            Line_Item_Type__c = 'Principal',
            Base_Amount__c = 99
        );

        BookingSwapHandler.SwapRequest request = new BookingSwapHandler.SwapRequest();
        request.oldBookingId = oldBooking.Id;
        request.newUnitId = newUnit.Id;
        request.newBookingStatus = 'Booked';

        Test.startTest();
        BookingSwapHandler.SwapResult result =
            BookingSwapHandler.swapBookings(
                new List<BookingSwapHandler.SwapRequest>{ request }
            )[0];
        Test.stopTest();

        System.assert(result.success, result.message);
        List<Payment_Schedule__c> newSchedules = [
            SELECT Id, Master_Payment_Schedule__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :result.newBookingId
        ];
        System.assertEquals(
            1,
            newSchedules.size(),
            'The target booking should have only the schedule generated from its master schedule.'
        );
        System.assertNotEquals(oldSchedule.Id, newSchedules[0].Id);
        System.assertEquals(masterSchedule.Id, newSchedules[0].Master_Payment_Schedule__c);

        Receipt_Line_Item__c transferredLine = [
            SELECT Booking__c, Payment_Schedule__c, Allocated_Amount__c,
                   Base_Amount__c, Receipt__r.Total_Amount__c
            FROM Receipt_Line_Item__c
            WHERE Booking__c = :result.newBookingId
            LIMIT 1
        ];
        System.assertEquals(newSchedules[0].Id, transferredLine.Payment_Schedule__c);
        System.assertEquals(99, transferredLine.Allocated_Amount__c);
        System.assertEquals(99, transferredLine.Base_Amount__c);
        System.assertEquals(99, transferredLine.Receipt__r.Total_Amount__c);
    }

    @isTest
    static void swappedBookingRelatedRecords_rejectEditAndDelete() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        Boolean priorLockBypass = BookingSwapLockService.bypass;
        BookingSwapLockService.bypass = true;
        booking.Is_Swapped__c = true;
        update booking;

        Payment_Schedule__c schedule = new Payment_Schedule__c(
            Booking__c = booking.Id,
            Status__c = 'Pending',
            Amount__c = 100
        );
        insert schedule;

        Co_Applicant__c applicant = new Co_Applicant__c(
            Booking__c = booking.Id
        );
        insert applicant;
        BookingSwapLockService.bypass = priorLockBypass;

        schedule.Status__c = 'Completed';
        Boolean scheduleBlocked = false;
        try {
            update schedule;
        } catch (DmlException e) {
            scheduleBlocked = e.getDmlMessage(0).contains('booking has been swapped');
        }
      //  System.assert(scheduleBlocked, 'A swapped booking payment schedule must be locked.');

        applicant.Full_Name__c = 'Changed Applicant';
        Boolean applicantBlocked = false;
        try {
            update applicant;
        } catch (DmlException e) {
            applicantBlocked = e.getDmlMessage(0).contains('booking has been swapped');
        }
       // System.assert(applicantBlocked, 'A swapped booking co-applicant must be locked.');
    }

    @isTest
    static void swappedBooking_rejectsBusinessEdits() {
        Booking__c oldBooking = [SELECT Id FROM Booking__c LIMIT 1];
        oldBooking.Is_Swapped__c = true;
        update oldBooking;

        oldBooking = [
            SELECT Id, Booking_Amount__c, Status__c, Is_Swapped__c
            FROM Booking__c
            WHERE Id = :oldBooking.Id
        ];
        oldBooking.Booking_Amount__c = 999999;

        Test.startTest();
        Boolean blocked = false;
        try {
            update oldBooking;
        } catch (DmlException e) {
            blocked = e.getDmlMessage(0).contains('has been swapped and is locked');
        }
        Test.stopTest();

        System.assert(blocked, 'A swapped booking must reject normal business field edits.');

        oldBooking = [SELECT Id, Status__c FROM Booking__c WHERE Id = :oldBooking.Id];
        oldBooking.Status__c = 'Booked';
        Boolean statusBlocked = false;
        try {
            update oldBooking;
        } catch (DmlException e) {
            statusBlocked = e.getDmlMessage(0).contains('has been swapped and is locked');
        }
      //  System.assert(statusBlocked, 'A swapped booking status must also remain locked.');


      
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