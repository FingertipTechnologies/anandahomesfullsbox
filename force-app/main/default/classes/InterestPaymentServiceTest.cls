/**
 * @description The Interest Amount entered on a receipt pays only the delay interest, oldest first; the
 *              rest of the receipt is allocated as before, and the instalment side never sees the
 *              interest money. Interest paid / calculated stay clear on the milestones and the booking.
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

    /** Installment receipt from the customer with an interest part. */
    private static Receipt__c receipt(Id bookingId, Decimal amount, Decimal interest) {
        Receipt__c r = new Receipt__c(Booking__c = bookingId, Receipt_Date__c = Date.today(),
            Amount_Received__c = amount, Total_Amount__c = amount, TDS_Deducted__c = 0,
            Transaction_Reference__c = 'INT-' + amount + '-' + interest,
            Receipt_Type__c = 'Installment Payment', Payment_From__c = 'Customer',
            Interest_Amount__c = interest,
            Approval_Status__c = PostSalesConstants.APPROVAL_STATUS_PENDING_APPROVAL);
        insert r;
        return r;
    }

    @isTest
    static void interestPartPaysInterestOldestFirst_restPaysTheInstalment() {
        Booking__c b = booking();
        List<Payment_Schedule__c> rows = schedulesWithInterest(b.Id);
        delete [SELECT Id FROM Payment_Schedule__c WHERE Booking__c = :b.Id AND Id NOT IN :rows];
        // 51,200 received, of which 1,200 interest.
        Receipt__c r = receipt(b.Id, 51200, 1200);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        BookingFinancialRecalcService.recalculateForBookings(new Set<Id>{ b.Id });
        Test.stopTest();

        Map<Id, Payment_Schedule__c> after = new Map<Id, Payment_Schedule__c>([
            SELECT Id, Interest_Pending__c, Interest_Paid__c, Interest_Calculated__c,
                   Pending_Amount__c, Payment_Schedule_Amount_Pending__c
            FROM Payment_Schedule__c WHERE Id IN :rows]);
        System.assertEquals(0, after.get(rows[0].Id).Interest_Pending__c, 'milestone 1 interest paid in full');
        System.assertEquals(1000, after.get(rows[0].Id).Interest_Paid__c);
        System.assertEquals(1000, after.get(rows[0].Id).Interest_Calculated__c, 'calculated = pending + paid');
        System.assertEquals(300, after.get(rows[1].Id).Interest_Pending__c, '200 of milestone 2 paid');
        System.assertEquals(200, after.get(rows[1].Id).Interest_Paid__c);
        System.assertEquals(500, after.get(rows[1].Id).Interest_Calculated__c);
        // The other 50,000 paid the instalment of milestone 1 as before; interest money never counted.
        System.assertEquals(50000, after.get(rows[0].Id).Payment_Schedule_Amount_Pending__c);
        System.assertEquals(50000, after.get(rows[1].Id).Payment_Schedule_Amount_Pending__c);

        Decimal interestLines = 0, otherLines = 0;
        for (Receipt_Line_Item__c l : [SELECT Allocation_Type__c, Payment_Schedule__c, Allocated_Amount__c,
                                              Base_Amount__c, GST_Amount__c, TDS_Amount__c
                                       FROM Receipt_Line_Item__c WHERE Receipt__c = :r.Id]) {
            if (l.Allocation_Type__c == 'Interest') {
                System.assertEquals(null, l.Payment_Schedule__c, 'interest lines are not linked to a milestone');
                System.assertEquals(0, l.Base_Amount__c + l.GST_Amount__c + l.TDS_Amount__c);
                interestLines += l.Allocated_Amount__c;
            } else {
                otherLines += l.Allocated_Amount__c;
            }
        }
        System.assertEquals(1200, interestLines);
        System.assertEquals(50000, otherLines);

        Decimal paid = 0, open = 0;
        for (Interest_Line_Item__c ili : [SELECT Amount__c, Status__c FROM Interest_Line_Item__c WHERE Booking__c = :b.Id]) {
            if (ili.Status__c == 'Paid') paid += ili.Amount__c; else open += ili.Amount__c;
        }
        System.assertEquals(1200, paid);
        System.assertEquals(300, open);
        Booking__c bk = [SELECT Total_Interest__c, Total_Interest_Paid__c, Total_Interest_Calculated__c FROM Booking__c WHERE Id = :b.Id];
        System.assertEquals(300, bk.Total_Interest__c, 'still pending');
        System.assertEquals(1200, bk.Total_Interest_Paid__c);
        System.assertEquals(1500, bk.Total_Interest_Calculated__c);
    }

    @isTest
    static void interestAboveUnpaidStaysUnallocated() {
        Booking__c b = booking();
        schedulesWithInterest(b.Id);
        // 2,000 entered as interest but only 1,500 is unpaid; the instalment side gets nothing.
        Receipt__c r = receipt(b.Id, 2000, 2000);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assertEquals(0, InterestPaymentService.unpaidInterest(b.Id));
        System.assertEquals(0, [SELECT COUNT() FROM Receipt_Line_Item__c WHERE Receipt__c = :r.Id AND Allocation_Type__c != 'Interest']);
        Decimal allocated = 0;
        for (Receipt_Line_Item__c l : [SELECT Allocated_Amount__c FROM Receipt_Line_Item__c WHERE Receipt__c = :r.Id]) {
            allocated += l.Allocated_Amount__c;
        }
        System.assertEquals(1500, allocated, 'the other 500 stays unallocated on the receipt');
    }

    @isTest
    static void receiptWithoutInterestIsUnchanged() {
        Booking__c b = booking();
        schedulesWithInterest(b.Id);
        Receipt__c r = receipt(b.Id, 1000, null);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Receipt_Line_Item__c WHERE Receipt__c = :r.Id AND Allocation_Type__c = 'Interest']);
        System.assertEquals(1500, InterestPaymentService.unpaidInterest(b.Id), 'interest untouched');
    }

    @isTest
    static void interestAmountRules() {
        Booking__c b = booking();
        Map<String, Object> data = new Map<String, Object>{
            'bookingId' => b.Id, 'receiptDate' => String.valueOf(Date.today()), 'receiptType' => 'TDS Payment',
            'paymentFrom' => 'Customer', 'amountReceived' => 100, 'interestAmount' => 10,
            'transactionNumber' => 'INT-RULE-1', 'paymentMode' => 'NEFT'
        };
        String error;
        try { FinancialTransactionController.createReceipt(JSON.serialize(data)); } catch (Exception e) { error = e.getMessage(); }
        System.assert(error != null && error.contains('Installment Payment from the Customer'), error);

        data.put('receiptType', 'Installment Payment');
        data.put('interestAmount', 500);
        error = null;
        try { FinancialTransactionController.createReceipt(JSON.serialize(data)); } catch (Exception e) { error = e.getMessage(); }
        System.assert(error != null && error.contains('more than the Amount Received'), error);
    }

    @isTest
    static void unpaidInterestForTheScreen() {
        Booking__c b = booking();
        schedulesWithInterest(b.Id);
        System.assertEquals(1500, FinancialTransactionController.getUnpaidInterest(b.Id));
        System.assertEquals(0, FinancialTransactionController.getUnpaidInterest(null));
    }
}
