/**
 * @description Interest Payment receipts pay only the delay interest, oldest first, and never change
 *              the instalment (Flat / GST / TDS) side of the milestones or demands.
 */
@isTest
private class InterestPaymentServiceTest {

    @testSetup
    static void setup() {
        postSalesTestDataFactory.createFullBooking('Interest Pay Project');
    }

    private static Booking__c booking() {
        return [SELECT Id FROM Booking__c LIMIT 1];
    }

    /** Two milestones with interest: 1000 (two lines 600 + 400) and 500 (one line). */
    private static List<Payment_Schedule__c> schedulesWithInterest(Id bookingId) {
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            new Payment_Schedule__c(Booking__c = bookingId, Milestone_Name__c = 'INT-1', Sequence__c = 91,
                Amount__c = 100000, Pending_Amount__c = 100000, Payment_Schedule_Amount__c = 100000,
                Payment_Schedule_Amount_Pending__c = 100000, Status__c = 'Pending', Interest_Pending__c = 1000),
            new Payment_Schedule__c(Booking__c = bookingId, Milestone_Name__c = 'INT-2', Sequence__c = 92,
                Amount__c = 50000, Pending_Amount__c = 50000, Payment_Schedule_Amount__c = 50000,
                Payment_Schedule_Amount_Pending__c = 50000, Status__c = 'Pending', Interest_Pending__c = 500)
        };
        insert rows;
        insert new List<Interest_Line_Item__c>{
            line(bookingId, rows[0].Id, 600, Date.today().addDays(-20)),
            line(bookingId, rows[0].Id, 400, Date.today().addDays(-10)),
            line(bookingId, rows[1].Id, 500, Date.today().addDays(-5))
        };
        return rows;
    }

    private static Interest_Line_Item__c line(Id bookingId, Id scheduleId, Decimal amount, Date fromDate) {
        return new Interest_Line_Item__c(Booking__c = bookingId, Payment_Schedule__c = scheduleId,
            Component__c = 'Flat', Amount__c = amount, From_Date__c = fromDate, To_Date__c = fromDate.addDays(1),
            Status__c = 'Calculated', Allocation_Type__c = 'Interest', Allocation_Date__c = fromDate);
    }

    private static Receipt__c interestReceipt(Id bookingId, Decimal amount, String paymentFrom) {
        Receipt__c r = new Receipt__c(Booking__c = bookingId, Receipt_Date__c = Date.today(),
            Amount_Received__c = amount, Total_Amount__c = amount, TDS_Deducted__c = 0,
            Transaction_Reference__c = 'INT-' + amount + '-' + paymentFrom,
            Receipt_Type__c = 'Interest Payment', Payment_From__c = paymentFrom,
            Approval_Status__c = PostSalesConstants.APPROVAL_STATUS_PENDING_APPROVAL);
        insert r;
        return r;
    }

    @isTest
    static void paysInterestOldestFirst_neverTheInstalment() {
        Booking__c b = booking();
        List<Payment_Schedule__c> rows = schedulesWithInterest(b.Id);
        Receipt__c r = interestReceipt(b.Id, 1200, 'Customer');

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        BookingFinancialRecalcService.recalculateForBookings(new Set<Id>{ b.Id });
        Test.stopTest();

        Map<Id, Payment_Schedule__c> after = new Map<Id, Payment_Schedule__c>([
            SELECT Id, Interest_Pending__c, Pending_Amount__c, Payment_Schedule_Amount_Pending__c
            FROM Payment_Schedule__c WHERE Id IN :rows]);
        System.assertEquals(0, after.get(rows[0].Id).Interest_Pending__c, 'milestone 1 interest paid in full');
        System.assertEquals(300, after.get(rows[1].Id).Interest_Pending__c, '200 of milestone 2 paid');
        System.assertEquals(100000, after.get(rows[0].Id).Pending_Amount__c, 'instalment untouched');
        System.assertEquals(100000, after.get(rows[0].Id).Payment_Schedule_Amount_Pending__c, 'flat untouched');
        System.assertEquals(50000, after.get(rows[1].Id).Pending_Amount__c, 'instalment untouched');

        List<Receipt_Line_Item__c> lines = [SELECT Allocation_Type__c, Payment_Schedule__c, Demand__c, Allocated_Amount__c,
                                            Base_Amount__c, GST_Amount__c, TDS_Amount__c
                                            FROM Receipt_Line_Item__c WHERE Receipt__c = :r.Id];
        Decimal total = 0;
        for (Receipt_Line_Item__c l : lines) {
            System.assertEquals('Interest', l.Allocation_Type__c);
            System.assertEquals(null, l.Payment_Schedule__c, 'not linked to a milestone');
            System.assertEquals(null, l.Demand__c);
            System.assertEquals(0, l.Base_Amount__c + l.GST_Amount__c + l.TDS_Amount__c);
            total += l.Allocated_Amount__c;
        }
        System.assertEquals(1200, total);

        // Lines: 600 + 400 paid, 500 split into 200 paid + 300 still open.
        Decimal paid = 0, open = 0;
        for (Interest_Line_Item__c ili : [SELECT Amount__c, Status__c FROM Interest_Line_Item__c WHERE Booking__c = :b.Id]) {
            if (ili.Status__c == 'Paid') paid += ili.Amount__c; else open += ili.Amount__c;
        }
        System.assertEquals(1200, paid);
        System.assertEquals(300, open);
        System.assertEquals(300, [SELECT Total_Interest__c FROM Booking__c WHERE Id = :b.Id].Total_Interest__c);
    }

    @isTest
    static void excessOverUnpaidInterestBecomesAdvance() {
        Booking__c b = booking();
        schedulesWithInterest(b.Id);
        Receipt__c r = interestReceipt(b.Id, 2000, 'Customer');

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assertEquals(500, [SELECT New_Advance_Created__c FROM Receipt__c WHERE Id = :r.Id].New_Advance_Created__c,
            '1500 unpaid interest, 500 extra');
        System.assertEquals(0, InterestPaymentService.unpaidInterest(b.Id));
    }

    @isTest
    static void bankCannotPayInterest() {
        Booking__c b = booking();
        schedulesWithInterest(b.Id);
        Receipt__c r = interestReceipt(b.Id, 100, 'Bank');
        String error;
        Test.startTest();
        try {
            FinancialTransactionController.allocateReceipt(r.Id);
        } catch (Exception e) {
            error = e.getMessage();
        }
        Test.stopTest();
        System.assert(error != null && error.contains('Customer'), error);
    }

    @isTest
    static void unpaidInterestForTheScreen() {
        Booking__c b = booking();
        schedulesWithInterest(b.Id);
        System.assertEquals(1500, FinancialTransactionController.getUnpaidInterest(b.Id));
        System.assertEquals(0, FinancialTransactionController.getUnpaidInterest(null));
    }
}