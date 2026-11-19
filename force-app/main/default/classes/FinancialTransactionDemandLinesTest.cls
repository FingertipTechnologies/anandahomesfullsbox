/**
 * @description A demand that covers several milestones (one Demand_Line__c per schedule) must
 *              receive a receipt's money for every one of those schedules, not only for the
 *              demand's own Payment_Schedule__c. Prod B-1391 (2026-11-19): DEM-00477 covered 15
 *              schedules, the receipt paid all 15, but only the last one was tagged to the demand,
 *              so the demand stayed Partially Paid.
 */
@isTest
private class FinancialTransactionDemandLinesTest {

    @testSetup
    static void setup() {
        Booking__c b = postSalesTestDataFactory.createFullBooking('Demand Lines Project');
        List<Payment_Schedule__c> schedules = new List<Payment_Schedule__c>();
        for (Integer i = 1; i <= 2; i++) {
            schedules.add(new Payment_Schedule__c(
                Booking__c = b.Id, Sequence__c = i, S_No__c = i,
                Milestone_Name__c = 'Milestone ' + i,
                Amount__c = 1000, Payment_Schedule_Amount__c = 1000, GST_Amount__c = 0,
                Pending_Amount__c = 1000, Status__c = 'Pending', Due_Date__c = Date.today()
            ));
        }
        insert schedules;
    }

    private static List<Payment_Schedule__c> schedules() {
        return [SELECT Id, Booking__c FROM Payment_Schedule__c WHERE Milestone_Name__c LIKE 'Milestone %' ORDER BY Sequence__c];
    }

    /** One demand on schedule 2, with a demand line for schedule 1 as well. */
    private static Demands__c demandCoveringBoth(List<Payment_Schedule__c> ps) {
        Demands__c d = new Demands__c(
            Booking__c = ps[0].Booking__c, Payment_Schedule__c = ps[1].Id,
            Demand_Amount__c = 2000, Pending_Amount__c = 2000, Status__c = 'Raised',
            Demand_Date__c = Date.today(), Due_Date__c = Date.today().addDays(7),
            Demand_Type__c = 'Individual Demand', Demand_Component__c = 'Flat'
        );
        insert d;
        Set<Id> covered = new Set<Id>();
        for (Demand_Line__c l : [SELECT Payment_Schedule__c FROM Demand_Line__c WHERE Demand__c = :d.Id]) {
            covered.add(l.Payment_Schedule__c);
        }
        List<Demand_Line__c> lines = new List<Demand_Line__c>();
        for (Payment_Schedule__c s : ps) {
            if (!covered.contains(s.Id)) {
                lines.add(new Demand_Line__c(Demand__c = d.Id, Payment_Schedule__c = s.Id,
                    Demand_Component__c = 'Flat', Flat_Amount__c = 1000, Demand_Amount__c = 1000,
                    Sequence__c = ps.indexOf(s) + 1));
            }
        }
        if (!lines.isEmpty()) insert lines;
        return d;
    }

    @isTest
    static void demandLines_putTheDemandUnderEveryCoveredSchedule() {
        List<Payment_Schedule__c> ps = schedules();
        Demands__c d = demandCoveringBoth(ps);

        Map<Id, List<Demands__c>> bySchedule = new Map<Id, List<Demands__c>>{
            ps[1].Id => new List<Demands__c>{ d }
        };
        List<Demands__c> unlinked = new List<Demands__c>();

        Test.startTest();
        FinancialTransactionController.addDemandsByDemandLines(new List<Demands__c>{ d }, bySchedule, unlinked);
        FinancialTransactionController.addDemandsByDemandLines(new List<Demands__c>(), bySchedule, unlinked);
        Test.stopTest();

        System.assert(bySchedule.containsKey(ps[0].Id), 'Schedule 1 is covered by a demand line');
        System.assertEquals(d.Id, bySchedule.get(ps[0].Id)[0].Id);
        System.assertEquals(1, bySchedule.get(ps[1].Id).size(), 'The demand is not listed twice for its own schedule');
        System.assert(bySchedule.get(ps[0].Id)[0] === bySchedule.get(ps[1].Id)[0],
            'Same record under both schedules, so its pending amount is shared');
    }

    @isTest
    static void demandWithoutSchedule_butWithLines_isNoLongerUnlinked() {
        List<Payment_Schedule__c> ps = schedules();
        Demands__c d = demandCoveringBoth(ps);
        Map<Id, List<Demands__c>> bySchedule = new Map<Id, List<Demands__c>>();
        List<Demands__c> unlinked = new List<Demands__c>{ d };

        Test.startTest();
        FinancialTransactionController.addDemandsByDemandLines(new List<Demands__c>{ d }, bySchedule, unlinked);
        Test.stopTest();

        System.assert(unlinked.isEmpty(), 'Allocated per schedule instead of as an unlinked demand');
        System.assertEquals(2, bySchedule.size());
    }

    /** End to end: a receipt for both milestones pays the whole demand. */
    @isTest
    static void receiptForAllMilestones_paysTheDemand() {
        List<Payment_Schedule__c> ps = schedules();
        Demands__c d = demandCoveringBoth(ps);

        FinancialTransactionController.ReceiptWrapper w = new FinancialTransactionController.ReceiptWrapper();
        w.bookingId = ps[0].Booking__c;
        w.receiptDate = Date.today();
        w.amountReceived = 2000;
        w.transactionNumber = 'TXN-DL-' + Math.random();
        w.receiptType = 'Installment Payment';
        w.paymentMode = 'NEFT';
        w.paymentFrom = 'Customer';
        w.useAdvances = false;
        w.useCredits = false;

        Test.startTest();
        String failure;
        try {
            Id receiptId = FinancialTransactionController.createReceipt(JSON.serialize(w)).receiptId;
            FinancialTransactionController.allocateReceipt(receiptId); // what approval runs
        } catch (Exception e) {
            failure = e.getMessage();
        }
        Test.stopTest();

        Decimal tagged = 0;
        for (Receipt_Line_Item__c li : [SELECT Allocated_Amount__c FROM Receipt_Line_Item__c WHERE Demand__c = :d.Id]) {
            tagged += li.Allocated_Amount__c;
        }
        System.assertEquals(null, failure, 'Receipt failed: ' + failure);
        System.assertEquals(2000, tagged, 'Both milestones are tagged to the demand. Lines: ' + [SELECT Demand__c, Payment_Schedule__c, Allocated_Amount__c, Allocation_Type__c, Receipt__r.Approval_Status__c FROM Receipt_Line_Item__c] + ' demand: ' + [SELECT Status__c, Pending_Amount__c, Payment_Schedule__c FROM Demands__c WHERE Id = :d.Id] + ' schedules: ' + [SELECT Pending_Amount__c, Payment_Schedule_Amount_Pending__c FROM Payment_Schedule__c]);
        Demands__c after = [SELECT Status__c, Pending_Amount__c FROM Demands__c WHERE Id = :d.Id];
        System.assertEquals('Paid', after.Status__c);
        System.assertEquals(0, after.Pending_Amount__c);
    }
}
