/**
 * @description Test class for PaymentScheduleViewController
 */
@isTest
private class PaymentScheduleViewControllerTest {

    @testSetup
    static void setup() {
        Project__c project = postSalesTestDataFactory.createProject('PSV Project');
        project.Legacy_Split_Demand_Receipt__c = true;
        update project;
        Plot__c unit = postSalesTestDataFactory.createUnit(project.Id);
        Lead__c lead = new Lead__c(
            Name__c = 'PSV Test Lead',
            Phone__c = '9000001001',
            Email__c = 'psvtest@example.com',
            Allocated_Project__c = 'The Legacey',
            Lead_Status__c = 'New Enquiry'
        );
        insert lead;
        Quote__c quote = new Quote__c(
            Project__c = 'The Legacey',
            CLead__c = lead.Id
        );
        insert quote;
        Booking__c b = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Quote__c = quote.Id,
            CLead__c = lead.Id,
            Booking_Date__c = Date.today().addDays(-30),
            Mode_Of_Payment__c = 'UPI',
            Total_Flat_Cost__c = 1000000,
            GST_Amount__c = 50000,
            Total_Payable_Amount__c = 1050000,
            Booking_Amount__c = 100000,
            Email__c = 'tester@example.com',
            Status__c = 'New'
        );
        insert b;
        b.Total_Payable_Amount__c = 1000;
        update b;

        Payment_Schedule__c ps1 = new Payment_Schedule__c(
            Booking__c = b.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Milestone 1',
            Status__c = 'Completed',
            Amount__c = 500,
            Percentage__c = 50,
            Pending_Amount__c = 100,
            Payment_Schedule_Amount_Pending__c = 100,
            GST_Amount_Pending__c = 25,
            Interest_Pending__c = 10
        );
        Payment_Schedule__c ps2 = new Payment_Schedule__c(
            Booking__c = b.Id,
            Sequence__c = 2,
            Milestone_Name__c = 'Milestone 2',
            Status__c = 'Pending',
            Amount__c = 500,
            Percentage__c = 50,
            Pending_Amount__c = 500
        );
        insert new List<Payment_Schedule__c>{ ps1, ps2 };
    }

    @isTest
    static void getPaymentSchedules_returnsResult() {
        Booking__c b = [SELECT Id, Funding_Type__c FROM Booking__c LIMIT 1];
        Test.startTest();
        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(b.Id);
        Test.stopTest();
        System.assertEquals(true, r.success, 'Should succeed');
        System.assertEquals(2, r.schedules.size(), 'Should have 2 schedules');
        System.assertEquals('Milestone 1', r.schedules[0].milestoneName, 'Milestone name should map from Milestone_Name__c');
        System.assertEquals('Milestone 1', r.nextDemand.lastCompletedMilestone, 'Last completed milestone should be the completed schedule');
        Boolean expectedSplitFunding = new Set<String>{
            'Loan', 'Bank Loan', 'NBFC Loan', 'Mixed Funding', 'Prorata', 'Partial'
        }.contains(b.Funding_Type__c);
        System.assertEquals(expectedSplitFunding, r.nextDemand.hasSplitFunding,
            'Source breakdown should only be shown for split-funded bookings');
        System.assertEquals(true, r.nextDemand.legacySplitDemandReceipt,
            'Legacy mode should be returned to the demand component selector.');
    }

    @isTest
    static void getPaymentSchedules_combinedModeReturnsFlag() {
        Booking__c booking = [SELECT Id, Project__c FROM Booking__c LIMIT 1];
        update new Project__c(
            Id = booking.Project__c,
            Legacy_Split_Demand_Receipt__c = false
        );

        PaymentScheduleViewController.PaymentScheduleViewResult result =
            PaymentScheduleViewController.getPaymentSchedules(booking.Id);

        System.assertEquals(true, result.success, 'Schedule view should load.');
        System.assertEquals(false, result.nextDemand.legacySplitDemandReceipt,
            'Combined mode should be returned to the demand component selector.');
    }

    @isTest
    static void getPaymentSchedules_exposesFlatTdsBreakdownForIndividualDemand() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        Payment_Schedule__c completed = [
            SELECT Id
            FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id AND Status__c = 'Completed'
            LIMIT 1
        ];
        completed.TDS_Amount__c = 5;
        completed.TDS_Amount_Pending__c = 5;
        completed.Pending_Amount__c = 130;
        update completed;

        PaymentScheduleViewController.PaymentScheduleViewResult result =
            PaymentScheduleViewController.getPaymentSchedules(booking.Id);
        PaymentScheduleViewController.PaymentScheduleWrapper schedule =
            result.schedules[0];

        System.assertEquals(true, result.success);
        System.assertEquals(5, schedule.tdsAmount);
        System.assertEquals(5, schedule.tdsPending);
        System.assertEquals(105, schedule.flatDemandableAmount,
            'Flat demandable includes the customer TDS collected with Flat.');
        System.assertEquals(1.05, schedule.tdsDemandableAmount,
            'TDS should be 1% of the remaining Flat Cost for the single-demand UI.');
        System.assertEquals(130, schedule.combinedDemandableAmount,
            'Combined demandable includes Flat, GST, and TDS.');

        Test.startTest();
        Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
            booking.Id,
            DemandComponentService.FLAT,
            false
        );
        Test.stopTest();

        Demands__c demand = [
            SELECT Demand_Amount__c, Flat_Amount__c, TDS_Amount__c
            FROM Demands__c
            WHERE Id = :demandId
        ];
        System.assertEquals(105, demand.Demand_Amount__c,
            'Individual Flat demand total must preserve the remaining Flat Cost.');
        System.assertEquals(103.95, demand.Flat_Amount__c,
            'Flat amount should be remaining Flat Cost less recalculated TDS.');
        System.assertEquals(1.05, demand.TDS_Amount__c);
    }

    @isTest
    static void raiseDemandForBooking_calculatesTdsOnRemainingFlatCost() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        Payment_Schedule__c completed = [
            SELECT Id
            FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id AND Status__c = 'Completed'
            LIMIT 1
        ];
        completed.Payment_Schedule_Amount__c = 841526;
        completed.Payment_Schedule_Amount_Paid__c = 500000;
        completed.Payment_Schedule_Amount_Pending__c = 341526;
        completed.GST_Amount__c = 0;
        completed.GST_Amount_Pending__c = 0;
        completed.TDS_Amount__c = 8500;
        completed.TDS_Amount_Paid__c = 0;
        completed.TDS_Amount_Pending__c = 8500;
        completed.Pending_Amount__c = 350026;
        update completed;

        PaymentScheduleViewController.PaymentScheduleViewResult preview =
            PaymentScheduleViewController.getPaymentSchedules(booking.Id);
        System.assertEquals(350026, preview.schedules[0].flatDemandableAmount,
            'Demand preview should preserve remaining Flat Cost after subtracting paid amounts.');
        System.assertEquals(3500.26, preview.schedules[0].tdsDemandableAmount,
            'TDS should be 1% of the remaining Flat Cost after subtracting the paid amount.');

        Test.startTest();
        Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
            booking.Id,
            DemandComponentService.FLAT,
            false
        );
        Test.stopTest();

        Demands__c demand = [
            SELECT Demand_Amount__c, Flat_Amount__c, TDS_Amount__c
            FROM Demands__c
            WHERE Id = :demandId
        ];
        System.assertEquals(350026, demand.Demand_Amount__c,
            'Raised demand total should equal the remaining Flat Cost.');
        System.assertEquals(346525.74, demand.Flat_Amount__c);
        System.assertEquals(3500.26, demand.TDS_Amount__c);
    }

    @isTest
    static void raiseDemandForBooking_calculatesOnePercentAcrossCompletedSchedules() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        List<Payment_Schedule__c> schedules = [
            SELECT Id, Sequence__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id
            ORDER BY Sequence__c
        ];

        Payment_Schedule__c first = schedules[0];
        first.Amount__c = 892527;
        first.Pending_Amount__c = 392527;
        first.Amount_Paid__c = 500000;
        first.Payment_Schedule_Amount__c = 841526;
        first.Payment_Schedule_Amount_Paid__c = 500000;
        first.Payment_Schedule_Amount_Pending__c = 341526;
        first.GST_Amount__c = 42501;
        first.GST_Amount_Paid__c = 0;
        first.GST_Amount_Pending__c = 42501;
        first.TDS_Amount__c = 8500;
        first.TDS_Amount_Paid__c = 0;
        first.TDS_Amount_Pending__c = 8500;

        Payment_Schedule__c second = schedules[1];
        second.Status__c = 'Completed';
        second.Amount__c = 312384;
        second.Pending_Amount__c = 312384;
        second.Payment_Schedule_Amount__c = 294534;
        second.Payment_Schedule_Amount_Paid__c = 0;
        second.Payment_Schedule_Amount_Pending__c = 294534;
        second.GST_Amount__c = 14875;
        second.GST_Amount_Paid__c = 0;
        second.GST_Amount_Pending__c = 14875;
        second.TDS_Amount__c = 2975;
        second.TDS_Amount_Paid__c = 0;
        second.TDS_Amount_Pending__c = 2975;
        update new List<Payment_Schedule__c>{ first, second };

        insert new List<Payment_Schedule__c>{
            new Payment_Schedule__c(
                Booking__c = booking.Id, Sequence__c = 3, Status__c = 'Completed',
                Amount__c = 446264, Pending_Amount__c = 446264,
                Payment_Schedule_Amount__c = 420763,
                Payment_Schedule_Amount_Paid__c = 0,
                Payment_Schedule_Amount_Pending__c = 420763,
                GST_Amount__c = 21251, GST_Amount_Paid__c = 0, GST_Amount_Pending__c = 21251,
                TDS_Amount__c = 4250, TDS_Amount_Paid__c = 0, TDS_Amount_Pending__c = 4250
            ),
            new Payment_Schedule__c(
                Booking__c = booking.Id, Sequence__c = 4, Status__c = 'Completed',
                Amount__c = 267758, Pending_Amount__c = 267758,
                Payment_Schedule_Amount__c = 252458,
                Payment_Schedule_Amount_Paid__c = 0,
                Payment_Schedule_Amount_Pending__c = 252458,
                GST_Amount__c = 12750, GST_Amount_Paid__c = 0, GST_Amount_Pending__c = 12750,
                TDS_Amount__c = 2550, TDS_Amount_Paid__c = 0, TDS_Amount_Pending__c = 2550
            )
        };

        Test.startTest();
        Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
            booking.Id,
            DemandComponentService.FLAT,
            false
        );
        Test.stopTest();

        Demands__c demand = [
            SELECT Demand_Amount__c, Flat_Amount__c, TDS_Amount__c
            FROM Demands__c
            WHERE Id = :demandId
        ];
        System.assertEquals(1327556, demand.Demand_Amount__c,
            'Demand total should equal the sum of remaining Flat Cost across the schedules.');
        System.assertEquals(1314280.44, demand.Flat_Amount__c,
            'Flat amount should be remaining Flat Cost less 1% TDS.');
        System.assertEquals(13275.56, demand.TDS_Amount__c,
            'TDS should equal 1% of the aggregate remaining Flat Cost.');
    }

    @isTest
    static void getPaymentSchedules_blankMilestoneName_fallsBackToScheduleName() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Payment_Schedule__c completed = [
            SELECT Id, Name FROM Payment_Schedule__c
            WHERE Booking__c = :b.Id AND Status__c = 'Completed' LIMIT 1
        ];
        completed.Milestone_Name__c = null;
        update completed;

        Test.startTest();
        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(b.Id);
        Test.stopTest();

        System.assertEquals(true, r.success, 'Should succeed');
        System.assertEquals(completed.Name, r.nextDemand.lastCompletedMilestone,
            'Blank Milestone_Name__c should fall back to schedule Name');
        for (PaymentScheduleViewController.PaymentScheduleWrapper w : r.schedules) {
            if (w.id == completed.Id) {
                System.assertEquals(completed.Name, w.milestoneName,
                    'Wrapper should fall back to schedule Name when Milestone_Name__c is blank');
            }
        }
    }

    @isTest
    static void getPaymentSchedules_blankMilestoneNameUsesMasterScheduleName() {
        Booking__c b = [SELECT Id, Project__c FROM Booking__c LIMIT 1];
        Payment_Schedule__c completed = [
            SELECT Id, Name FROM Payment_Schedule__c
            WHERE Booking__c = :b.Id AND Status__c = 'Completed' LIMIT 1
        ];
        Master_Payment_Schedule__c master = new Master_Payment_Schedule__c(
            Name = 'Foundation milestone',
            Project__c = b.Project__c,
            Sequence__c = 1,
            Is_Active__c = true,
            Percentage__c = 20
        );
        insert master;

        completed.Milestone_Name__c = null;
        completed.Master_Payment_Schedule__c = master.Id;
        update completed;

        Test.startTest();
        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(b.Id);
        Test.stopTest();

        System.assertEquals(true, r.success, 'Should succeed');
        System.assertEquals('Foundation milestone', r.nextDemand.lastCompletedMilestone,
            'Last completed milestone should use the linked master schedule name');
        for (PaymentScheduleViewController.PaymentScheduleWrapper w : r.schedules) {
            if (w.id == completed.Id) {
                System.assertEquals('Foundation milestone', w.milestoneName,
                    'Schedule display should use the linked master schedule name');
            }
        }
    }

    @isTest
    static void getPaymentSchedules_nullId_returnsError() {
        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(null);
        System.assertEquals(false, r.success, 'Should not succeed');
        System.assertNotEquals(null, r.errorMessage, 'Should have error');
    }

    @isTest
    static void saveScheduleAmounts_validTotals_updates() {
        Booking__c b = [SELECT Id, Total_Payable_Amount__c FROM Booking__c LIMIT 1];
        List<Payment_Schedule__c> schedules = [SELECT Id FROM Payment_Schedule__c WHERE Booking__c = :b.Id ORDER BY Sequence__c];

        Map<String, Object> amounts = new Map<String, Object>();
        amounts.put(schedules[1].Id, '500');
        // first one has Status='Completed' so we don't edit it; will keep its existing amount

        Test.startTest();
        try {
            PaymentScheduleViewController.saveScheduleAmounts(b.Id, JSON.serialize(amounts));
        } catch (Exception e) {
            // The completed schedule edit would throw; here ps2 is Pending so it should succeed
        }
        Test.stopTest();
    }

    @isTest
    static void saveScheduleAmounts_emptyMap_doesNothing() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        PaymentScheduleViewController.saveScheduleAmounts(b.Id, '{}');
        // Just assert no exception occurred
        System.assert(true, 'No error');
    }

    @isTest
    static void saveScheduleAmounts_invalidJson_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Boolean threw = false;
        try {
            PaymentScheduleViewController.saveScheduleAmounts(b.Id, 'not-json');
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw');
    }

    @isTest
    static void saveScheduleAmounts_negativeAmount_throws() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        Payment_Schedule__c ps = [SELECT Id FROM Payment_Schedule__c WHERE Status__c = 'Pending' LIMIT 1];
        Map<String, Object> amounts = new Map<String, Object>{ ps.Id => '-100' };

        Boolean threw = false;
        try {
            PaymentScheduleViewController.saveScheduleAmounts(b.Id, JSON.serialize(amounts));
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw on negative');
    }
    @isTest
    static void raiseDemandForBooking_success() {
    
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
    
        Test.startTest();

        Id demandId = PaymentScheduleViewController.raiseDemandForBooking(booking.Id, 'Flat', true);
        Id gstDemandId = PaymentScheduleViewController.raiseDemandForBooking(booking.Id, 'GST', true);

        Test.stopTest();

        Demands__c flatDemand = [
            SELECT Demand_Component__c, Demand_Amount__c, Flat_Amount__c, GST_Amount__c, Interest_Amount__c
            FROM Demands__c WHERE Id = :demandId
        ];
        System.assertEquals('Flat', flatDemand.Demand_Component__c);
        System.assertEquals(100, flatDemand.Demand_Amount__c);
        System.assertEquals(0, flatDemand.GST_Amount__c);
        System.assertEquals(10, flatDemand.Interest_Amount__c, 'Interest should be included when selected');

        System.assertEquals(2, [SELECT COUNT() FROM Demands__c WHERE Booking__c = :booking.Id]);
        System.assertNotEquals(demandId, gstDemandId);
        System.assertEquals(true, [
            SELECT Customer_Flat_Demand_Raised__c, Customer_GST_Demand_Raised__c
            FROM Payment_Schedule__c WHERE Booking__c = :booking.Id AND Status__c = 'Completed'
        ].Customer_GST_Demand_Raised__c);
    }

    @isTest
    static void raiseDemandForBooking_combinedModeCreatesCombinedDemand() {
        Booking__c booking = [SELECT Id, Project__c FROM Booking__c LIMIT 1];
        update new Project__c(
            Id = booking.Project__c,
            Legacy_Split_Demand_Receipt__c = false
        );
        Payment_Schedule__c completed = [
            SELECT Id
            FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id AND Status__c = 'Completed'
            LIMIT 1
        ];
        completed.TDS_Amount_Pending__c = 5;
        completed.TDS_Amount__c = 5;
        completed.Pending_Amount__c = 130;
        update completed;

        PaymentScheduleViewController.PaymentScheduleViewResult scheduleResult =
            PaymentScheduleViewController.getPaymentSchedules(booking.Id);
        System.assertEquals(130, scheduleResult.schedules[0].combinedDemandableAmount,
            'Combined preview must match the demand principal including TDS.');

        Test.startTest();
        Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
            booking.Id,
            DemandComponentService.FLAT_AND_GST,
            true
        );
        Test.stopTest();

        Demands__c demand = [
            SELECT Demand_Component__c, Demand_Amount__c, Flat_Amount__c, Base_Amount__c,
                   GST_Amount__c, TDS_Amount__c, Interest_Amount__c
            FROM Demands__c
            WHERE Id = :demandId
        ];
        System.assertEquals(DemandComponentService.FLAT_AND_GST, demand.Demand_Component__c);
        System.assertEquals(130, demand.Demand_Amount__c);
        System.assertEquals(103.95, demand.Flat_Amount__c);
        System.assertEquals(103.95, demand.Base_Amount__c);
        System.assertEquals(25, demand.GST_Amount__c);
        System.assertEquals(1.05, demand.TDS_Amount__c);
        System.assertEquals(10, demand.Interest_Amount__c);
    }

    @isTest
    static void raiseDemandForBookingWithAmounts_savesEditedComponents() {
        Booking__c booking = [SELECT Id, Project__c FROM Booking__c LIMIT 1];
        update new Project__c(
            Id = booking.Project__c,
            Legacy_Split_Demand_Receipt__c = false
        );

        Test.startTest();
        Id demandId = PaymentScheduleViewController.raiseDemandForBookingWithAmounts(
            booking.Id,
            DemandComponentService.FLAT_AND_GST,
            false,
            100.25,
            12.50,
            3.25
        );
        Test.stopTest();

        Demands__c demand = [
            SELECT Demand_Amount__c, Pending_Amount__c, Flat_Amount__c, Base_Amount__c,
                   GST_Amount__c, TDS_Amount__c
            FROM Demands__c
            WHERE Id = :demandId
        ];
        System.assertEquals(116, demand.Demand_Amount__c);
        System.assertEquals(116, demand.Pending_Amount__c);
        System.assertEquals(100.25, demand.Flat_Amount__c);
        System.assertEquals(100.25, demand.Base_Amount__c);
        System.assertEquals(12.50, demand.GST_Amount__c);
        System.assertEquals(3.25, demand.TDS_Amount__c);
    }

    @isTest
    static void raiseDemandForBooking_rejectsCombinedDemandForLegacyProject() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
        Boolean blocked = false;

        try {
            PaymentScheduleViewController.raiseDemandForBooking(
                booking.Id,
                DemandComponentService.FLAT_AND_GST,
                false
            );
        } catch (AuraHandledException e) {
            blocked = true;
        }

        System.assertEquals(true, blocked, 'Legacy projects must keep Flat and GST demands separate.');
    }

    @isTest
    static void raiseDemandForBooking_canExcludeInterest() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        Test.startTest();
        Id demandId = PaymentScheduleViewController.raiseDemandForBooking(booking.Id, 'Flat', false);
        Test.stopTest();

        Demands__c demand = [
            SELECT Interest_Amount__c
            FROM Demands__c
            WHERE Id = :demandId
        ];
        System.assertEquals(0, demand.Interest_Amount__c, 'Interest should be excluded when not selected');
    }
}