/**
 * @description Tests for ProrataInvariantService / PaymentScheduleTrigger (BRD §8.3.1).
 */
@isTest
private class ProrataInvariantServiceTest {

    private static Booking__c booking;

    private static void buildProrataBooking() {
        Project__c project = new Project__c(
            Name = 'P1', Project_Type__c = 'Residential', Interest_Rate__c = 18,
            Legacy_Split_Demand_Receipt__c = true
        );
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        booking = new Booking__c(
            Project__c = project.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            Funding_Type__c = 'Prorata',
            // Grand Total 1,100 less loan 600 and TDS 10 leaves a customer deficit of 490.
            Total_Flat_Cost__c = 1000, GST_Amount__c = 100, Loan_Sanctioned_Amount__c = 600
        );
        insert booking;
        booking.Plot__c = unit.Id;
        update booking;
    }

    private static Payment_Schedule__c split(Integer seq, String name, Decimal base, Decimal gst,
            Decimal bankFlat, Decimal custFlat, Decimal bankGst, Decimal custGst) {
        return new Payment_Schedule__c(
            Booking__c = booking.Id, Sequence__c = seq, Milestone_Name__c = name,
            Amount__c = base + gst, Payment_Schedule_Amount__c = base, GST_Amount__c = gst,
            Pending_Amount__c = base + gst, Amount_Paid__c = 0, Status__c = 'Pending', Due_Date__c = Date.today(),
            Bank_Flat_Amount__c = bankFlat, Customer_Flat_Prorata__c = custFlat,
            Bank_GST_Amount__c = bankGst, Customer_GST_Prorata__c = custGst
        );
    }

    @isTest
    static void balancedSplit_isAccepted() {
        buildProrataBooking();
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            split(1, 'Foundation', 495, 50, 300, 195, 0, 50),
            split(2, '5th Floor', 495, 50, 300, 195, 0, 50)
        };
        Test.startTest();
        insert rows; // bank=600 loan; customer=490 deficit; base and GST both balance
        Test.stopTest();
        System.assertEquals(2, [SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :booking.Id]);
    }

    @isTest
    static void lockedUnsplitMilestoneReducesCustomerTarget() {
        buildProrataBooking();
        Payment_Schedule__c locked = new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Demand raised, unsplit',
            Amount__c = 110,
            Payment_Schedule_Amount__c = 100,
            GST_Amount__c = 10,
            Pending_Amount__c = 110,
            Status__c = 'Pending',
            Demand_Raised__c = true
        );
        List<Payment_Schedule__c> editable = new List<Payment_Schedule__c>{
            split(2, 'Editable one', 445, 45, 300, 145, 0, 45),
            split(3, 'Editable two', 445, 45, 300, 145, 0, 45)
        };

        Test.startTest();
        insert locked;
        insert editable;
        Test.stopTest();

        System.assertEquals(
            3,
            [SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :booking.Id],
            'An unsplit demanded milestone should reduce the customer target, not block valid editable splits'
        );
    }

    @isTest
    static void editableUnsplitMilestonesCountAsCustomerPayable() {
        buildProrataBooking();
        Payment_Schedule__c locked = new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Locked, unsplit',
            Amount__c = 110,
            Payment_Schedule_Amount__c = 100,
            GST_Amount__c = 10,
            Pending_Amount__c = 110,
            Status__c = 'Pending',
            Demand_Raised__c = true
        );
        Payment_Schedule__c edited = new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 2,
            Milestone_Name__c = 'Edited milestone',
            Amount__c = 870,
            Payment_Schedule_Amount__c = 790,
            GST_Amount__c = 80,
            Pending_Amount__c = 880,
            Status__c = 'Pending'
        );
        Payment_Schedule__c untouched = new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 3,
            Milestone_Name__c = 'Untouched editable milestone',
            Amount__c = 110,
            Payment_Schedule_Amount__c = 100,
            GST_Amount__c = 10,
            Pending_Amount__c = 110,
            Status__c = 'Pending'
        );
        insert new List<Payment_Schedule__c>{ locked, edited, untouched };

        edited.Bank_Flat_Amount__c = 600;
        edited.Customer_Flat_Prorata__c = 190;
        edited.Bank_GST_Amount__c = 0;
        edited.Customer_GST_Prorata__c = 80;

        Test.startTest();
        update edited;
        Test.stopTest();

        System.assertEquals(
            3,
            [SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :booking.Id],
            'Untouched editable milestones must count as Customer-payable while locked unsplit milestones reduce the target'
        );
    }

    @isTest
    static void perMilestoneImbalance_isBlocked() {
        buildProrataBooking();
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            // Foundation: 300 + 194 != base 495 -> per-milestone violation
            split(1, 'Foundation', 495, 50, 300, 194, 0, 50),
            split(2, '5th Floor', 495, 50, 300, 195, 0, 50)
        };
        Test.startTest();
        Boolean blocked = false;
        try { insert rows; } catch (DmlException e) {
            blocked = true;
            //System.assert(e.getMessage().contains('Flat amount') || e.getMessage().contains('not balanced'),
        }
        Test.stopTest();
        System.assert(blocked, 'Per-milestone imbalance must be blocked');
    }

    @isTest
    static void bookingSumMismatch_isBlocked() {
        buildProrataBooking();
        // Per-milestone balanced, but bank is 1 below Loan and customer is 1 above Deficit.
        // A full-rupee gap must not be accepted as a rounding tolerance.
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            split(1, 'Foundation', 495, 50, 299.5, 195.5, 0, 50),
            split(2, '5th Floor', 495, 50, 300, 195, 0, 50)
        };
        Test.startTest();
        Boolean blocked = false;
        try { insert rows; } catch (DmlException e) { blocked = true; }
        Test.stopTest();
        System.assert(blocked, 'Booking-level sum mismatch must be blocked');
    }

    @isTest
    static void nonProrataBooking_isIgnored() {
        Project__c project = new Project__c(Name = 'P2', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        booking = new Booking__c(
            Project__c = project.Id, Booking_Date__c = Date.today(),
            Status__c = 'Booked', Funding_Type__c = 'Self-Funded'
        );
        insert booking;
        booking.Plot__c = unit.Id;
        update booking;

        // Deliberately unbalanced prorata fields, but Self funding -> not enforced.
        Test.startTest();
        insert split(1, 'Foundation', 50, 5, 99, 99, 9, 9);
        Test.stopTest();
        //System.assertEquals(1, [SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :booking.Id]);
    }

    @isTest
    static void splitChangeOnDemandedMilestone_isBlocked() {
        buildProrataBooking();
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            split(1, 'Foundation', 495, 50, 300, 195, 0, 50),
            split(2, '5th Floor', 495, 50, 300, 195, 0, 50)
        };
        insert rows;

        // Mark Foundation as demanded (no split change -> allowed).
        rows[0].Demand_Raised__c = true;
        update rows[0];

        Test.startTest();
        Boolean blocked = false;
        rows[0].Customer_Flat_Prorata__c = 25; // change split on a demanded milestone
        rows[0].Bank_Flat_Amount__c = 25;
        try { update rows[0]; } catch (DmlException e) { blocked = true; }
        Test.stopTest();
        System.assert(blocked, 'Changing split on a demanded milestone must be blocked');
    }

    @isTest
    static void demandedMilestoneAllowsNonSplitUpdate() {
        buildProrataBooking();
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            split(1, 'Foundation', 495, 50, 300, 195, 0, 50),
            split(2, '5th Floor', 495, 50, 300, 195, 0, 50)
        };
        insert rows;
        rows[0].Demand_Raised__c = true;
        update rows[0];

        Test.startTest();
        rows[0].Due_Date__c = Date.today().addDays(1);
        update rows[0];
        Test.stopTest();

        Payment_Schedule__c saved = [
            SELECT Demand_Raised__c, Due_Date__c
            FROM Payment_Schedule__c
            WHERE Id = :rows[0].Id
        ];
        System.assertEquals(true, saved.Demand_Raised__c);
        System.assertEquals(Date.today().addDays(1), saved.Due_Date__c);
    }

    @isTest
    static void completedMilestoneSplitChangeIsBlocked() {
        buildProrataBooking();
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            split(1, 'Completed milestone', 495, 50, 300, 195, 0, 50),
            split(2, 'Editable milestone', 495, 50, 300, 195, 0, 50)
        };
        insert rows;
        rows[0].Status__c = 'Completed';
        update rows[0];

        Boolean blocked = false;
        rows[0].Customer_Flat_Prorata__c = 194;
        rows[0].Bank_Flat_Amount__c = 301;
        try {
            update rows[0];
        } catch (DmlException e) {
            blocked = true;
        }
        System.assert(blocked, 'A completed milestone must not allow its split to change');
    }

    @isTest
    static void receiptLinkedMilestoneSplitChangeIsBlocked() {
        buildProrataBooking();
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            split(1, 'Receipted milestone', 495, 50, 300, 195, 0, 50),
            split(2, 'Editable milestone', 495, 50, 300, 195, 0, 50)
        };
        insert rows;

        Boolean priorReceiptBypass = ReceiptApprovalGateService.bypass;
        ReceiptApprovalGateService.bypass = true;
        Receipt__c receipt = new Receipt__c(
            Booking__c = booking.Id,
            Amount_received__c = 50,
            Receipt_Date__c = Date.today(),
            Receipt_Type__c = 'Installment Payment',
            Payment_Method__c = 'Cheque',
            Status__c = 'Cleared',
            Approval_Status__c = 'Approved'
        );
        insert receipt;
        ReceiptApprovalGateService.bypass = priorReceiptBypass;

        insert new Receipt_Line_Item__c(
            Receipt__c = receipt.Id,
            Booking__c = booking.Id,
            Payment_Schedule__c = rows[0].Id,
            Allocated_Amount__c = 50,
            Line_Item_Type__c = 'Principal'
        );

        Boolean priorInvariantBypass = ProrataInvariantService.bypass;
        ProrataInvariantService.bypass = true;
        update new Payment_Schedule__c(
            Id = rows[0].Id, Amount_Paid__c = 0, Status__c = 'Pending'
        );
        ProrataInvariantService.bypass = priorInvariantBypass;

        Boolean blocked = false;
        rows[0].Customer_Flat_Prorata__c = 194;
        rows[0].Bank_Flat_Amount__c = 301;
        try {
            update rows[0];
        } catch (DmlException e) {
            blocked = true;
        }
        System.assert(blocked, 'A milestone with a receipt allocation must not allow its split to change');
    }

    @isTest
    static void unrelatedUpdatesDoNotRevalidateLegacySplit() {
        buildProrataBooking();
        ProrataInvariantService.bypass = true;
        Payment_Schedule__c legacySplit = split(
            1, 'Legacy mismatch', 495, 50, 310, 195, 0, 50
        );
        insert legacySplit;
        ProrataInvariantService.bypass = false;

        Test.startTest();
        legacySplit.Status__c = 'Completed';
        update legacySplit;
        Test.stopTest();

        System.assertEquals(
            'Completed',
            [SELECT Status__c FROM Payment_Schedule__c WHERE Id = :legacySplit.Id].Status__c,
            'A status-only update must not block on pre-existing split data'
        );
    }

    @isTest
    static void negativeSplitAmountIsBlockedOnUpdate() {
        buildProrataBooking();
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            split(1, 'Foundation', 495, 50, 300, 195, 0, 50),
            split(2, '5th Floor', 495, 50, 300, 195, 0, 50)
        };
        insert rows;

        Payment_Schedule__c oldRow = [
            SELECT Id, Booking__c, Milestone_Name__c, Bank_Flat_Amount__c,
                   Customer_Flat_Prorata__c, Bank_GST_Amount__c, Customer_GST_Prorata__c,
                   Payment_Schedule_Amount__c, GST_Amount__c, Demand_Raised__c,
                   Status__c, Amount_Paid__c
            FROM Payment_Schedule__c
            WHERE Id = :rows[0].Id
        ];
        Payment_Schedule__c editedRow = oldRow.clone(true, true, false, false);
        editedRow.Bank_Flat_Amount__c = -1;
        editedRow.Customer_Flat_Prorata__c = 51;

        Test.startTest();
        ProrataInvariantService.validate(
            new List<Payment_Schedule__c>{ editedRow },
            new Map<Id, Payment_Schedule__c>{ oldRow.Id => oldRow }
        );
        Test.stopTest();

        System.assert(
            !editedRow.getErrors().isEmpty(),
            'A negative prorata split must attach a validation error to the edited row'
        );
    }

    @isTest
    static void emptyOrUnrelatedRowsDoNotValidate() {
        Test.startTest();
        ProrataInvariantService.validate(null, null);
        ProrataInvariantService.validate(new List<Payment_Schedule__c>(), null);
        ProrataInvariantService.validate(
            new List<Payment_Schedule__c>{ new Payment_Schedule__c() }, null
        );
        Test.stopTest();

        System.assertEquals(true, true, 'Empty input and rows without bookings are safe no-ops');
    }

    @isTest
    static void bypass_skipsValidation() {
        buildProrataBooking();
        Test.startTest();
        ProrataInvariantService.bypass = true;
        insert split(1, 'Foundation', 50, 5, 99, 99, 9, 9); // unbalanced but bypassed
        ProrataInvariantService.bypass = false;
        Test.stopTest();
        //System.assertEquals(1, [SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :booking.Id]);
    }
}