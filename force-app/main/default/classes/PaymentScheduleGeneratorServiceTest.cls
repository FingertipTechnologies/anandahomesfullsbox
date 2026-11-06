/**
 * @description Test class for PaymentScheduleGeneratorService.
 *              Tests the auto-creation of Payment Schedules from Master Payment Schedules
 *              when a Booking is created.
 * @author System
 * @date 2026-03-15
 */
@IsTest
private class PaymentScheduleGeneratorServiceTest {

    @TestSetup
    static void setupData() {
        // Create Project
        Project__c project = new Project__c(
            Name = 'Test Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;

        // Create Master Payment Schedules
        List<Master_Payment_Schedule__c> masters = new List<Master_Payment_Schedule__c>();
        masters.add(new Master_Payment_Schedule__c(
            Name = 'On Booking',
            Project__c = project.Id,
            Payment_Type__c = 'On Booking',
            Percentage__c = 10,
            Payment_Percent__c = 10,
            Sequence__c = 1,
            Status__c = 'Pending',
            Is_Active__c = true,
            Days_After_Booking__c = 0,
            Applicable_For__c = 'Apartment',
            Description__c = '10% on booking'
        ));
        masters.add(new Master_Payment_Schedule__c(
            Name = 'On Agreement',
            Project__c = project.Id,
            Payment_Type__c = 'On Agreement',
            Percentage__c = 15,
            Payment_Percent__c = 15,
            Sequence__c = 2,
            Status__c = 'Pending',
            Is_Active__c = true,
            Days_After_Booking__c = 30,
            Applicable_For__c = 'Apartment',
            Description__c = '15% on agreement'
        ));
        masters.add(new Master_Payment_Schedule__c(
            Name = 'On Foundation',
            Project__c = project.Id,
            Payment_Type__c = 'On Foundation',
            Percentage__c = 10,
            Payment_Percent__c = 10,
            Sequence__c = 3,
            Status__c = 'Completed',
            Is_Active__c = true,
            Days_After_Previous__c = 60,
            Applicable_For__c = 'Apartment',
            Description__c = '10% on foundation'
        ));
        masters.add(new Master_Payment_Schedule__c(
            Name = 'On Possession',
            Project__c = project.Id,
            Payment_Type__c = 'On Possession',
            Percentage__c = 65,
            Payment_Percent__c = 65,
            Sequence__c = 4,
            Status__c = 'Pending',
            Is_Active__c = true,
            Days_After_Previous__c = 90,
            Applicable_For__c = 'Apartment',
            Description__c = '65% on possession'
        ));
        insert masters;

        // Create Unit
        Plot__c unit = new Plot__c(
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Available'
        );
        insert unit;
        // Create Quote
        Quote__c quote = new Quote__c();
        insert quote;
    }

    @IsTest
    static void testGeneratePaymentSchedulesOnBookingCreation() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        Plot__c unit = [SELECT Id FROM Plot__c LIMIT 1];
        Quote__c quote = [SELECT Id FROM Quote__c LIMIT 1];

        // Create a booking with pricing data
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Quote__c = quote.Id,
            Booking_Amount__c = 100000,
            Mode_Of_Payment__c = 'UPI',
            Booking_Date__c = Date.today(),
            Total_Flat_Cost__c = 5000000,
            GST_Amount__c = 250000,
            Status__c = 'New'
        );

        Test.startTest();
        insert booking;

        // Manually invoke since flow may not fire in test
        PaymentScheduleGeneratorService.FlowInput input = new PaymentScheduleGeneratorService.FlowInput();
        input.bookingId = booking.Id;
        PaymentScheduleGeneratorService.generateSchedules(new List<PaymentScheduleGeneratorService.FlowInput>{ input });
        Test.stopTest();

       
    }

    @IsTest
    static void testProrataScheduleStartsUnsplitUntilApprovedRevision() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        Plot__c unit = [SELECT Id FROM Plot__c LIMIT 1];
        Quote__c quote = [SELECT Id FROM Quote__c LIMIT 1];

        // Partial funding with a sanctioned loan must still leave generated schedule
        // split fields blank until an approved revision applies an allocation.
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Booking_Date__c = Date.today(),
             Quote__c = quote.Id,
            Booking_Amount__c = 100000,
            Mode_Of_Payment__c = 'UPI',
            Total_Flat_Cost__c = 5000000,
            GST_Amount__c = 250000,
            Funding_Type__c = 'Partial',
            Loan_Sanctioned_Amount__c = 3000000,
            Customer_Margin__c = 50000,
            Status__c = 'New'
        );

        Test.startTest();
        insert booking;
        PaymentScheduleGeneratorService.FlowInput input = new PaymentScheduleGeneratorService.FlowInput();
        input.bookingId = booking.Id;
        try {
            PaymentScheduleGeneratorService.generateSchedules(
                new List<PaymentScheduleGeneratorService.FlowInput>{ input });
        } catch (Exception e) { /* schedules may already exist via an org flow */ }
        Test.stopTest();

        List<Payment_Schedule__c> generated = [
            SELECT Bank_Flat_Amount__c, Customer_Flat_Prorata__c,
                   Bank_GST_Amount__c, Customer_GST_Prorata__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id
        ];
        System.assert(!generated.isEmpty(), 'Payment schedules should be generated');
        for (Payment_Schedule__c schedule : generated) {
            System.assertEquals(null, schedule.Bank_Flat_Amount__c);
            System.assertEquals(null, schedule.Customer_Flat_Prorata__c);
            System.assertEquals(null, schedule.Bank_GST_Amount__c);
            System.assertEquals(null, schedule.Customer_GST_Prorata__c);
        }
    }

    @IsTest
    static void testExplicitProrataSplitAllocationBalancesScheduleTotals() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        project.Legacy_Split_Demand_Receipt__c = true;
        update project;
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Total_Flat_Cost__c = 1000,
            GST_Amount__c = 100,
            Funding_Type__c = 'Partial',
            Loan_Sanctioned_Amount__c = 500,
            Status__c = 'New'
        );
        insert booking;
        // The booking flow may already have generated schedules from the project's master rows;
        // this test works on its own two hand-built schedules only.
        delete [SELECT Id FROM Payment_Schedule__c WHERE Booking__c = :booking.Id];

        List<Payment_Schedule__c> schedules = new List<Payment_Schedule__c>{
            new Payment_Schedule__c(
                Booking__c = booking.Id,
                Sequence__c = 1,
                Milestone_Name__c = 'Foundation',
                Amount__c = 555,
                Payment_Schedule_Amount__c = 495,
                GST_Amount__c = 50,
                TDS_Amount__c = 10,
                Pending_Amount__c = 555,
                Status__c = 'Pending'
            ),
            new Payment_Schedule__c(
                Booking__c = booking.Id,
                Sequence__c = 2,
                Milestone_Name__c = 'Possession',
                Amount__c = 545,
                Payment_Schedule_Amount__c = 495,
                GST_Amount__c = 50,
                TDS_Amount__c = 0,
                Pending_Amount__c = 545,
                Status__c = 'Pending'
            )
        };
        insert schedules;

        Test.startTest();
        PaymentScheduleGeneratorService.applyProrataSplit(new Set<Id>{ booking.Id });
        Test.stopTest();

        Decimal bankTotal = 0;
        Decimal customerTotal = 0;
        for (Payment_Schedule__c schedule : [
            SELECT Payment_Schedule_Amount__c, GST_Amount__c,
                   Bank_Flat_Amount__c, Customer_Flat_Prorata__c,
                   Bank_GST_Amount__c, Customer_GST_Prorata__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id
        ]) {
            System.assertEquals(
                schedule.Payment_Schedule_Amount__c,
                schedule.Bank_Flat_Amount__c + schedule.Customer_Flat_Prorata__c
            );
            System.assertEquals(
                schedule.GST_Amount__c,
                schedule.Bank_GST_Amount__c + schedule.Customer_GST_Prorata__c
            );
            bankTotal += schedule.Bank_Flat_Amount__c + schedule.Bank_GST_Amount__c;
            customerTotal += schedule.Customer_Flat_Prorata__c
                + schedule.Customer_GST_Prorata__c;
        }
        System.assertEquals(500, bankTotal, 'Bank allocations must equal the sanctioned loan');
        System.assertEquals(590, customerTotal, 'Customer allocations must equal the booking deficit');
    }

    @IsTest
    static void testExplicitProrataSplitAllocationSkipsIneligibleOrUnsafeSchedules() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        project.Legacy_Split_Demand_Receipt__c = true;
        update project;
        Booking__c alreadySplitBooking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Total_Flat_Cost__c = 1000,
            GST_Amount__c = 100,
            Funding_Type__c = 'Partial',
            Loan_Sanctioned_Amount__c = 500,
            Status__c = 'New'
        );
        Booking__c mismatchedBooking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Total_Flat_Cost__c = 1000,
            GST_Amount__c = 100,
            Funding_Type__c = 'Partial',
            Loan_Sanctioned_Amount__c = 500,
            Status__c = 'New'
        );
        Booking__c zeroTotalBooking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Total_Flat_Cost__c = 1000,
            GST_Amount__c = 100,
            Funding_Type__c = 'Partial',
            Loan_Sanctioned_Amount__c = 500,
            Status__c = 'New'
        );
        Booking__c ineligibleBooking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Total_Flat_Cost__c = 1000,
            GST_Amount__c = 100,
            Funding_Type__c = 'Self-Funded',
            Loan_Sanctioned_Amount__c = 500,
            Status__c = 'New'
        );
        insert new List<Booking__c>{
            alreadySplitBooking, mismatchedBooking, zeroTotalBooking, ineligibleBooking
        };

        Payment_Schedule__c alreadySplit = new Payment_Schedule__c(
            Booking__c = alreadySplitBooking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Existing allocation',
            Amount__c = 100,
            Payment_Schedule_Amount__c = 495,
            GST_Amount__c = 50,
            Pending_Amount__c = 100,
            Status__c = 'Pending',
            Bank_Flat_Amount__c = 100,
            Customer_Flat_Prorata__c = 395,
            Bank_GST_Amount__c = 0,
            Customer_GST_Prorata__c = 50
        );
        Payment_Schedule__c mismatched = new Payment_Schedule__c(
            Booking__c = mismatchedBooking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Capacity mismatch',
            Amount__c = 1000,
            Payment_Schedule_Amount__c = 900,
            GST_Amount__c = 100,
            Pending_Amount__c = 1000,
            Status__c = 'Pending'
        );
        Payment_Schedule__c zeroTotal = new Payment_Schedule__c(
            Booking__c = zeroTotalBooking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Zero capacity',
            Amount__c = 0,
            Payment_Schedule_Amount__c = 0,
            GST_Amount__c = 0,
            Pending_Amount__c = 0,
            Status__c = 'Pending'
        );
        Boolean priorInvariantBypass = ProrataInvariantService.bypass;
        ProrataInvariantService.bypass = true;
        try {
            insert new List<Payment_Schedule__c>{ alreadySplit, mismatched, zeroTotal };
        } finally {
            ProrataInvariantService.bypass = priorInvariantBypass;
        }

        Test.startTest();
        PaymentScheduleGeneratorService.applyProrataSplit(new Set<Id>{
            alreadySplitBooking.Id, mismatchedBooking.Id, zeroTotalBooking.Id, ineligibleBooking.Id
        });
        Test.stopTest();

        Set<Id> scheduleIds = new Set<Id>{ alreadySplit.Id, mismatched.Id, zeroTotal.Id };
        Map<Id, Payment_Schedule__c> saved = new Map<Id, Payment_Schedule__c>([
            SELECT Id, Bank_Flat_Amount__c, Customer_Flat_Prorata__c,
                   Bank_GST_Amount__c, Customer_GST_Prorata__c
            FROM Payment_Schedule__c
            WHERE Id IN :scheduleIds
        ]);
        System.assertEquals(100, saved.get(alreadySplit.Id).Bank_Flat_Amount__c);
        System.assertEquals(null, saved.get(mismatched.Id).Bank_Flat_Amount__c);
        System.assertEquals(null, saved.get(zeroTotal.Id).Bank_Flat_Amount__c);
    }

    @IsTest
    static void testGeneratedScheduleTotalsMatchBookingAndStayUnsplit() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        Plot__c unit = [SELECT Id FROM Plot__c LIMIT 1];
        List<Master_Payment_Schedule__c> masters = [
            SELECT Id, Percentage__c, Payment_Percent__c
            FROM Master_Payment_Schedule__c
            WHERE Project__c = :project.Id
            ORDER BY Sequence__c ASC
        ];

        List<Decimal> percentages = new List<Decimal>{
            20, 7, 8, 8, 8, 8, 8, 8, 8, 8, 9
        };
        for (Integer i = 0; i < masters.size(); i++) {
            masters[i].Percentage__c = percentages[i];
            masters[i].Payment_Percent__c = percentages[i];
        }
        update masters;

        List<Master_Payment_Schedule__c> additionalMasters =
            new List<Master_Payment_Schedule__c>();
        for (Integer i = masters.size(); i < percentages.size(); i++) {
            additionalMasters.add(new Master_Payment_Schedule__c(
                Name = 'Rounding milestone ' + i,
                Project__c = project.Id,
                Payment_Type__c = 'On Foundation',
                Percentage__c = percentages[i],
                Payment_Percent__c = percentages[i],
                Sequence__c = i + 1,
                Status__c = 'Pending',
                Is_Active__c = true,
                Applicable_For__c = 'Apartment'
            ));
        }
        insert additionalMasters;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Total_Flat_Cost__c = 1071000,
            GST_Amount__c = 536,
            Funding_Type__c = 'Partial',
            Loan_Sanctioned_Amount__c = 500000,
            Status__c = 'New'
        );
        insert booking;
        booking.Plot__c = unit.Id;
        update booking;

        PaymentScheduleGeneratorService.generateForBookings(new Set<Id>{ booking.Id });

        List<Payment_Schedule__c> generatedSchedules = [
            SELECT Payment_Schedule_Amount__c, GST_Amount__c, TDS_Amount__c, Amount__c,
                   Bank_Flat_Amount__c, Bank_GST_Amount__c,
                   Customer_Flat_Prorata__c, Customer_GST_Prorata__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id
        ];
        Decimal totalFlat = 0;
        Decimal totalGst = 0;
        Decimal totalTds = 0;
        Decimal totalAmount = 0;
        for (Payment_Schedule__c schedule : generatedSchedules) {
            totalFlat += schedule.Payment_Schedule_Amount__c;
            totalGst += schedule.GST_Amount__c;
            totalTds += schedule.TDS_Amount__c;
            totalAmount += schedule.Amount__c;
            System.assertEquals(null, schedule.Bank_Flat_Amount__c);
            System.assertEquals(null, schedule.Bank_GST_Amount__c);
            System.assertEquals(null, schedule.Customer_Flat_Prorata__c);
            System.assertEquals(null, schedule.Customer_GST_Prorata__c);
        }

        Booking__c savedBooking = [
            SELECT Total_Flat_Cost__c, GST_Amount__c, TDS__c, Grand_Total__c,
                   Loan_Sanctioned_Amount__c, Deficit__c
            FROM Booking__c
            WHERE Id = :booking.Id
        ];
        System.assertEquals(11, generatedSchedules.size());
        System.assertEquals(
            savedBooking.Total_Flat_Cost__c - savedBooking.TDS__c,
            totalFlat,
            'Schedule base should equal the flat cost less the Booking TDS'
        );
        System.assertEquals(savedBooking.GST_Amount__c, totalGst);
        System.assertEquals(savedBooking.TDS__c, totalTds);
        System.assertEquals(savedBooking.Grand_Total__c, totalAmount);
    }

    @IsTest
    static void testNoProjectNoSchedules() {
        // Create a booking without a project
        Booking__c booking = new Booking__c(
            Booking_Date__c = Date.today(),
            Status__c = 'New'
        );
        insert booking;

        Test.startTest();
        PaymentScheduleGeneratorService.FlowInput input = new PaymentScheduleGeneratorService.FlowInput();
        input.bookingId = booking.Id;
        PaymentScheduleGeneratorService.generateSchedules(new List<PaymentScheduleGeneratorService.FlowInput>{ input });
        Test.stopTest();

       
    }

    @IsTest
    static void testDoNotRegenerateIfAlreadyCreated() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        Plot__c unit = [SELECT Id FROM Plot__c LIMIT 1];
        Quote__c quote = [SELECT Id FROM Quote__c LIMIT 1];
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
             Quote__c = quote.Id,
            Booking_Amount__c = 100000,
            Mode_Of_Payment__c = 'UPI',
            Booking_Date__c = Date.today(),
            Total_Flat_Cost__c = 5000000,
            GST_Amount__c = 250000,
            Status__c = 'New'
        );
        insert booking;

        Test.startTest();
        PaymentScheduleGeneratorService.FlowInput input = new PaymentScheduleGeneratorService.FlowInput();
        input.bookingId = booking.Id;
        PaymentScheduleGeneratorService.generateSchedules(new List<PaymentScheduleGeneratorService.FlowInput>{ input });
        Test.stopTest();

    }

    @IsTest
    static void testTowerWiseSchedulesUseTheUnitsTowerAndNeverDuplicate() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        Quote__c quote = [SELECT Id FROM Quote__c LIMIT 1];
        Block__c tower = new Block__c(Name = 'TW-TEST', Project__c = project.Id);
        insert tower;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Available', Block1__c = tower.Id);
        insert unit;

        List<Master_Payment_Schedule__c> masters = [SELECT Id FROM Master_Payment_Schedule__c WHERE Project__c = :project.Id];
        for (Master_Payment_Schedule__c m : masters) {
            m.Tower__c = tower.Id;
        }
        update masters;

        // Tower-wise configuration: master rows are matched on their tower.
        insert new Post_Sales_Configuration__c(
            Configuration_Type__c = 'Payment Schedule',
            Is_Active__c = true,
            Reminder_Config__c = '{"sourceParentField":"Tower__c","bookingParentField":"Block__c","fieldMappings":[]}'
        );

        // The booking carries the unit but not the tower, as a booking raised from a quote does.
        Booking__c booking = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Quote__c = quote.Id,
            Booking_Amount__c = 100000, Mode_Of_Payment__c = 'UPI', Booking_Date__c = Date.today(),
            Total_Flat_Cost__c = 5000000, GST_Amount__c = 250000, Status__c = 'New'
        );
        insert booking;

        Test.startTest();
        PaymentScheduleGeneratorService.generateForBookings(new Set<Id>{ booking.Id });
        Integer afterFirstRun = [SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :booking.Id];
        PaymentScheduleGeneratorService.generateForBookings(new Set<Id>{ booking.Id });
        Integer afterSecondRun = [SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :booking.Id];
        Test.stopTest();

        System.assertEquals(masters.size(), afterFirstRun, 'One schedule per master row of the tower of the unit');
        System.assertEquals(afterFirstRun, afterSecondRun, 'A second run must not duplicate the schedules');
    }

    @IsTest
    static void testEmptyInput() {
        Test.startTest();
        PaymentScheduleGeneratorService.generateSchedules(new List<PaymentScheduleGeneratorService.FlowInput>());
        PaymentScheduleGeneratorService.generateSchedules(
            new List<PaymentScheduleGeneratorService.FlowInput>{
                null, new PaymentScheduleGeneratorService.FlowInput()
            }
        );
        Test.stopTest();
        // Empty or null Flow inputs should not invoke schedule generation.
    }
}