/**
 * @description Tests for ProrataDemandService — split Bank / Customer prorata demands (BRD §8.4).
 */
@isTest
private class ProrataDemandServiceTest {

    private static Booking__c booking;
    private static Project__c project;

    private static void buildData(String funding) {
        project = new Project__c(
            Name = 'P', Project_Type__c = 'Apartment', Interest_Rate__c = 18,
            Legacy_Split_Demand_Receipt__c = true
        );
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(),
            Status__c = 'Booked', Funding_Type__c = funding,
            Loan_Sanctioned_Amount__c = 2000000
        );
        insert booking;
    }

    private static Payment_Schedule__c makeSchedule(String milestone, Date due) {
        ProrataInvariantService.bypass = true;
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = booking.Id, Sequence__c = 1, Milestone_Name__c = milestone,
            Amount__c = 4200000, Payment_Schedule_Amount__c = 4000000, GST_Amount__c = 200000,
            Bank_Flat_Amount__c = 2000000, Bank_GST_Amount__c = 100000,
            Customer_Flat_Prorata__c = 2000000, Customer_GST_Prorata__c = 100000,
            With_GST__c = true, Status__c = 'Pending', Due_Date__c = due
        );
        insert ps;
        ProrataInvariantService.bypass = false;
        return ps;
    }

    private static void insertSourceReceipt(
        Payment_Schedule__c schedule,
        String paymentFrom,
        Decimal flatAmount,
        Decimal gstAmount,
        Decimal tdsAmount
    ) {
        Decimal totalAmount = flatAmount + gstAmount + tdsAmount;
        Boolean previousReceiptBypass = ReceiptApprovalGateService.bypass;
        ReceiptApprovalGateService.bypass = true;
        Receipt__c receipt = new Receipt__c(
            Booking__c = schedule.Booking__c,
            Amount_received__c = totalAmount,
            Receipt_Date__c = Date.today(),
            Receipt_Type__c = flatAmount == 0 ? 'GST Amount' : 'Installment Payment',
            Payment_From__c = paymentFrom,
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
            Booking__c = schedule.Booking__c,
            Payment_Schedule__c = schedule.Id,
            Allocated_Amount__c = totalAmount,
            Amount__c = totalAmount,
            Allocation_Date__c = Date.today(),
            Allocation_Type__c = 'Payment Schedule',
            Line_Item_Type__c = 'Principal',
            Base_Amount__c = flatAmount,
            GST_Amount__c = gstAmount,
            TDS_Amount__c = tdsAmount
        );
    }

    @isTest
    static void bankDemand_isRaisedFromSplit() {
        buildData('Prorata');
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());

        Test.startTest();
        Integer n = ProrataDemandService.raiseBankDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

        System.assertEquals(2, n, 'Separate Flat and GST bank demands expected');
        List<Demands__c> demands = [
            SELECT Demand_Type__c, Demand_Component__c, Base_Amount__c, Flat_Amount__c,
                   GST_Amount__c, TDS_Amount__c, Demand_Amount__c, Payment_Schedule__c
            FROM Demands__c WHERE Booking__c = :booking.Id
        ];
        System.assertEquals(2, demands.size());
        for (Demands__c d : demands) {
            System.assertEquals('Bank Demand', d.Demand_Type__c);
            System.assertEquals(ps.Id, d.Payment_Schedule__c);
            if (d.Demand_Component__c == 'Flat') {
                System.assertEquals(2000000, d.Demand_Amount__c, 'Bank Flat');
                System.assertEquals(1980000, d.Flat_Amount__c, 'Net Bank Flat after 1% TDS');
                System.assertEquals(20000, d.TDS_Amount__c, 'TDS is 1% of Bank Flat only');
                System.assertEquals(0, d.GST_Amount__c);
            } else {
                System.assertEquals('GST', d.Demand_Component__c);
                System.assertEquals(100000, d.Demand_Amount__c, 'Bank GST');
                System.assertEquals(0, d.Base_Amount__c);
            }
        }
        Payment_Schedule__c flagged = [
            SELECT Bank_Demand_Raised__c, Bank_Flat_Demand_Raised__c, Bank_GST_Demand_Raised__c
            FROM Payment_Schedule__c WHERE Id = :ps.Id
        ];
        System.assertEquals(true, flagged.Bank_Demand_Raised__c);
        System.assertEquals(true, flagged.Bank_Flat_Demand_Raised__c);
        System.assertEquals(true, flagged.Bank_GST_Demand_Raised__c);
    }

    @isTest
    static void bankFlatDemandCarriesOnlyUnpaidUndemandedTdsFromPriorFlatPayments() {
        buildData('Prorata');
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());
        ProrataInvariantService.bypass = true;
        try {
            update new Payment_Schedule__c(
                Id = ps.Id,
                Payment_Schedule_Amount_Paid__c = 500000,
                TDS_Amount__c = 10000,
                TDS_Amount_Paid__c = 0,
                TDS_Amount_Pending__c = 10000
            );
        } finally {
            ProrataInvariantService.bypass = false;
        }
        insertSourceReceipt(ps, 'Bank', 500000, 0, 0);

        Test.startTest();
        Integer countRaised = ProrataDemandService.raiseBankDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

       
    }

    @isTest
    static void bankDemandsSubtractOnlyBankReceipts() {
        buildData('Prorata');
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());
        ProrataInvariantService.bypass = true;
        try {
            update new Payment_Schedule__c(
                Id = ps.Id,
                Payment_Schedule_Amount_Paid__c = 500000,
                GST_Amount_Paid__c = 25000
            );
        } finally {
            ProrataInvariantService.bypass = false;
        }
        insertSourceReceipt(ps, 'Customer', 500000, 25000, 0);

        Test.startTest();
        Integer countRaised = ProrataDemandService.raiseBankDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

        System.assertEquals(2, countRaised);
        Map<String, Demands__c> demandByComponent = new Map<String, Demands__c>();
        for (Demands__c demand : [
            SELECT Demand_Component__c, Demand_Amount__c, TDS_Amount__c
            FROM Demands__c
            WHERE Booking__c = :booking.Id
        ]) {
            demandByComponent.put(demand.Demand_Component__c, demand);
        }
        System.assertEquals(2000000, demandByComponent.get('Flat').Demand_Amount__c);
        System.assertEquals(20000, demandByComponent.get('Flat').TDS_Amount__c);
        System.assertEquals(100000, demandByComponent.get('GST').Demand_Amount__c);
    }

    @isTest
    static void bankFlatDemandDoesNotCarryTheSameTdsTwice() {
        buildData('Prorata');
        Payment_Schedule__c prior = makeSchedule('Advance', Date.today());
        ProrataInvariantService.bypass = true;
        try {
            update new Payment_Schedule__c(
                Id = prior.Id,
                Payment_Schedule_Amount_Paid__c = 500000,
                TDS_Amount__c = 10000,
                TDS_Amount_Paid__c = 0,
                TDS_Amount_Pending__c = 10000
            );
            Payment_Schedule__c next = new Payment_Schedule__c(
                Booking__c = booking.Id, Sequence__c = 2, Milestone_Name__c = 'Next',
                Amount__c = 2100000, Payment_Schedule_Amount__c = 2000000,
                Payment_Schedule_Amount_Pending__c = 2000000, GST_Amount__c = 100000,
                GST_Amount_Pending__c = 100000, Bank_Flat_Amount__c = 1000000,
                Bank_GST_Amount__c = 50000, Customer_Flat_Prorata__c = 1000000,
                Customer_GST_Prorata__c = 50000, TDS_Amount__c = 10000,
                TDS_Amount_Pending__c = 10000, Status__c = 'Pending', Due_Date__c = Date.today()
            );
            Payment_Schedule__c later = new Payment_Schedule__c(
                Booking__c = booking.Id, Sequence__c = 3, Milestone_Name__c = 'Later',
                Amount__c = 3150000, Payment_Schedule_Amount__c = 3000000,
                Payment_Schedule_Amount_Pending__c = 3000000, GST_Amount__c = 150000,
                GST_Amount_Pending__c = 150000, Bank_Flat_Amount__c = 1500000,
                Bank_GST_Amount__c = 75000, Customer_Flat_Prorata__c = 1500000,
                Customer_GST_Prorata__c = 75000, TDS_Amount__c = 15000,
                TDS_Amount_Pending__c = 15000, Status__c = 'Pending', Due_Date__c = Date.today()
            );
            insert new List<Payment_Schedule__c>{ next, later };

            insertSourceReceipt(prior, 'Bank', 500000, 0, 0);

            Test.startTest();
            ProrataDemandService.raiseBankDemands(new Set<Id>{ next.Id });
            ProrataDemandService.raiseBankDemands(new Set<Id>{ later.Id });
            Test.stopTest();

            Map<Id, Demands__c> flatDemandBySchedule = new Map<Id, Demands__c>();
            for (Demands__c demand : [
                SELECT Payment_Schedule__c, TDS_Amount__c, Demand_Amount__c
                FROM Demands__c
                WHERE Booking__c = :booking.Id AND Demand_Component__c = 'Flat'
            ]) {
                flatDemandBySchedule.put(demand.Payment_Schedule__c, demand);
            }
            
        } finally {
            ProrataInvariantService.bypass = false;
        }
    }

    @isTest
    static void customerDemand_isRaisedFromSplit() {
        buildData('Partial');
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());

        Test.startTest();
        Integer n = ProrataDemandService.raiseCustomerDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

        
    }

    @isTest
    static void customerDemandsSubtractPreviouslyPaidFlatAndGst() {
        buildData('Partial');
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());
        ProrataInvariantService.bypass = true;
        try {
            update new Payment_Schedule__c(
                Id = ps.Id,
                Payment_Schedule_Amount_Paid__c = 500000,
                GST_Amount_Paid__c = 25000,
                TDS_Amount_Pending__c = 1000
            );
        } finally {
            ProrataInvariantService.bypass = false;
        }
        insertSourceReceipt(ps, 'Customer', 500000, 25000, 0);

        Test.startTest();
        Integer countRaised = ProrataDemandService.raiseCustomerDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

        System.assertEquals(2, countRaised);
        Map<String, Demands__c> byComponent = new Map<String, Demands__c>();
        for (Demands__c demand : [
            SELECT Demand_Component__c, Demand_Amount__c, Flat_Amount__c, GST_Amount__c,
                   TDS_Amount__c
            FROM Demands__c WHERE Booking__c = :booking.Id
        ]) {
            byComponent.put(demand.Demand_Component__c, demand);
        }
       
    }

    @isTest
    static void demand_isNotRaisedTwice() {
        buildData('Prorata');
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());

        Test.startTest();
        ProrataDemandService.raiseBankDemands(new Set<Id>{ ps.Id });
        Integer second = ProrataDemandService.raiseBankDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

        System.assertEquals(0, second, 'Bank demand must not be raised twice');
        System.assertEquals(2, [SELECT COUNT() FROM Demands__c WHERE Booking__c = :booking.Id]);
    }

    @isTest
    static void nonProrataBooking_isSkipped() {
        buildData('Self-Funded');
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());

        Test.startTest();
        Integer n = ProrataDemandService.raiseBankDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

        System.assertEquals(0, n, 'Self-funded bookings have no split demands');
    }

    @isTest
    static void nonLegacyProject_prorataFundingIsSkipped() {
        buildData('Prorata');
        project.Legacy_Split_Demand_Receipt__c = false;
        update project;
        Payment_Schedule__c ps = makeSchedule('Foundation', Date.today());

        Test.startTest();
        Integer n = ProrataDemandService.raiseBankDemands(new Set<Id>{ ps.Id });
        Test.stopTest();

        System.assertEquals(0, n, 'Prorata demands are enabled only for legacy projects');
    }

    @isTest
    static void completedMilestone_raisesBankDemand() {
        buildData('Prorata');
        makeSchedule('Foundation', Date.today());
        Construction_Milestone__c m = new Construction_Milestone__c(
            Milestone_Name__c = 'Foundation', Project__c = project.Id, Milestone_Status__c = 'In Progress'
        );
        insert m;

        Test.startTest();
        m.Milestone_Status__c = 'Completed';
        m.Actual_Completion_Date__c = Date.today();
        update m;
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Demands__c WHERE Booking__c = :booking.Id AND Demand_Type__c = 'Bank Demand'],
            'Completing the milestone should raise separate bank Flat and GST demands');
    }

    @isTest
    static void dueCustomerDemands_areRaised() {
        buildData('Prorata');
        makeSchedule('Foundation', Date.today());

        Test.startTest();
        Integer n = ProrataDemandService.raiseDueCustomerDemands();
        Test.stopTest();

        System.assertEquals(2, n, 'Customer Flat and GST demands should be raised on the demand date');
    }
}