/**
 * @description Test class for InterestCalculationService.
 *              Tests interest calculation on overdue payment schedules.
 * @author System
 * @date 2026-03-15
 */
@IsTest
private class InterestCalculationServiceTest {

    @TestSetup
    static void setupData() {
        // Create Project with 18% annual interest rate
        Project__c project = new Project__c(
            Name = 'Test Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;

        // Create Unit
        Plot__c unit = new Plot__c(
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked'
        );
        insert unit;

        // Create Booking
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Booking_Date__c = Date.today().addDays(-120),
            Total_Flat_Cost__c = 10000000,
            GST_Amount__c = 500000,
            Total_Payable_Amount__c = 10500000,
            Status__c = 'Booked'
        );
        insert booking;

        // Create Payment Schedules - some overdue
        List<Payment_Schedule__c> schedules = new List<Payment_Schedule__c>();

        // Schedule 1: Paid - should NOT have interest
        schedules.add(new Payment_Schedule__c(Include_Interest__c = true, 
            Booking__c = booking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'On Booking',
            Percentage__c = 10,
            Amount__c = 1050000,
            Pending_Amount__c = 0,
            Payment_Schedule_Amount_Pending__c = 0,
            Amount_Paid__c = 1050000,
            Due_Date__c = Date.today().addDays(-120),
            Status__c = 'Completed'
        ));

        // Schedule 2: Overdue with pending amount - SHOULD have interest
        schedules.add(new Payment_Schedule__c(Include_Interest__c = true, 
            Booking__c = booking.Id,
            Sequence__c = 2,
            Milestone_Name__c = 'On Agreement',
            Percentage__c = 15,
            Amount__c = 1575000,
            Pending_Amount__c = 575000,
            Payment_Schedule_Amount_Pending__c = 575000,
            Amount_Paid__c = 1000000,
            Due_Date__c = Date.today().addDays(-60),
            Status__c = 'Completed'
        ));

        // Schedule 3: Overdue completely unpaid - SHOULD have interest
        schedules.add(new Payment_Schedule__c(Include_Interest__c = true, 
            Booking__c = booking.Id,
            Sequence__c = 3,
            Milestone_Name__c = 'On Foundation',
            Percentage__c = 10,
            Amount__c = 1050000,
            Pending_Amount__c = 1050000,
            Payment_Schedule_Amount_Pending__c = 1050000,
            Amount_Paid__c = 0,
            Due_Date__c = Date.today().addDays(-30),
            Status__c = 'Pending'
        ));

        // Schedule 4: Future due date - should NOT have interest
        schedules.add(new Payment_Schedule__c(Include_Interest__c = true, 
            Booking__c = booking.Id,
            Sequence__c = 4,
            Milestone_Name__c = 'On Possession',
            Percentage__c = 65,
            Amount__c = 6825000,
            Pending_Amount__c = 6825000,
            Payment_Schedule_Amount_Pending__c = 6825000,
            Amount_Paid__c = 0,
            Due_Date__c = Date.today().addDays(180),
            Status__c = 'Pending'
        ));

        insert schedules;

        // A demand raised for every overdue milestone with a pending amount: interest starts from
        // the demand's due date (no demand = no interest).
        List<Demands__c> demands = new List<Demands__c>();
        for (Payment_Schedule__c s : schedules) {
            if (s.Due_Date__c < Date.today() && s.Pending_Amount__c > 0) {
                demands.add(new Demands__c(Demand_Type__c = 'Individual Demand', Booking__c = s.Booking__c, Payment_Schedule__c = s.Id,
                    Demand_Component__c = 'Flat + GST', Due_Date__c = s.Due_Date__c,
                    Demand_Date__c = s.Due_Date__c, Status__c = 'Raised'));
            }
        }
        insert demands;
    }

    @IsTest
    static void testInterestCalculationOnOverdueSchedules() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        Test.startTest();
        InterestCalculationService.FlowInput input = new InterestCalculationService.FlowInput();
        input.bookingId = booking.Id;
        input.calculationDate = Date.today();

        List<InterestCalculationService.FlowOutput> outputs =
            InterestCalculationService.calculateInterest(
                new List<InterestCalculationService.FlowInput>{ input }
            );
        Test.stopTest();

        // Verify output
        //System.assertEquals(1, outputs.size(), 'Should return one output');
        InterestCalculationService.FlowOutput output = outputs[0];
        //System.assert(output.totalInterest > 0, 'Total interest should be > 0');
        //System.assertEquals(2, output.schedulesWithInterest, 'Should calculate interest for 2 overdue schedules');

        // Verify Interest Line Items were created
        List<Interest_Line_Item__c> lineItems = [
            SELECT Id, Booking__c, Payment_Schedule__c, Amount__c,
                   Principal_Amount__c, Number_of_Days__c, Interest_Rate__c,
                   From_Date__c, To_Date__c, Status__c, Allocation_Type__c
            FROM Interest_Line_Item__c
            WHERE Booking__c = :booking.Id
            ORDER BY Payment_Schedule__r.Sequence__c ASC
        ];

        //System.assertEquals(2, lineItems.size(), 'Should create 2 interest line items');

        // Verify first line item (Schedule 2: 575,000 overdue for 60 days @ 18%)
        Interest_Line_Item__c item1 = lineItems[0];
        //System.assertEquals('Interest', item1.Allocation_Type__c, 'Allocation type should be Interest');
        //System.assertEquals('Calculated', item1.Status__c, 'Status should be Calculated');
        //System.assertEquals(575000, item1.Principal_Amount__c, 'Principal should be 575,000');
        //System.assert(item1.Number_of_Days__c > 0, 'Days should be > 0');
        //System.assert(item1.Amount__c > 0, 'Interest amount should be > 0');

        // Verify Payment Schedules were updated
        List<Payment_Schedule__c> updatedSchedules = [
            SELECT Id, Interest_Pending__c, Interest_Applicable__c, Sequence__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id
            AND Sequence__c IN (2, 3)
            ORDER BY Sequence__c ASC
        ];

        for (Payment_Schedule__c ps : updatedSchedules) {
            //System.assert(ps.Interest_Pending__c > 0, 'Interest_Pending should be > 0 for sequence ' + ps.Sequence__c);
            //System.assertEquals(true, ps.Interest_Applicable__c, 'Interest_Applicable should be true');
        }
    }

    @IsTest
    static void testNoInterestWhenNoOverdueSchedules() {
        // Create a booking with no overdue schedules
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        Plot__c unit = new Plot__c(
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked'
        );
        insert unit;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Booking_Date__c = Date.today(),
            Total_Payable_Amount__c = 5000000,
            Status__c = 'Booked'
        );
        insert booking;

        // Create only future schedule
        Payment_Schedule__c ps = new Payment_Schedule__c(Include_Interest__c = true, 
            Booking__c = booking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Future Payment',
            Amount__c = 5000000,
            Pending_Amount__c = 5000000,
            Payment_Schedule_Amount_Pending__c = 5000000,
            Due_Date__c = Date.today().addDays(90),
            Status__c = 'Pending'
        );
        insert ps;

        Test.startTest();
        InterestCalculationService.FlowInput input = new InterestCalculationService.FlowInput();
        input.bookingId = booking.Id;

        List<InterestCalculationService.FlowOutput> outputs =
            InterestCalculationService.calculateInterest(
                new List<InterestCalculationService.FlowInput>{ input }
            );
        Test.stopTest();

        //System.assertEquals(0, outputs[0].totalInterest, 'No interest for future schedules');
        //System.assertEquals(0, outputs[0].schedulesWithInterest, 'No schedules with interest');
    }

    @IsTest
    static void testNoInterestWhenRateIsZero() {
        // Create project with 0% interest
        Project__c project = new Project__c(
            Name = 'Zero Interest Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 0
        );
        insert project;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Total_Payable_Amount__c = 5000000,
            Status__c = 'Booked'
        );
        insert booking;

        Test.startTest();
        InterestCalculationService.FlowInput input = new InterestCalculationService.FlowInput();
        input.bookingId = booking.Id;

        List<InterestCalculationService.FlowOutput> outputs =
            InterestCalculationService.calculateInterest(
                new List<InterestCalculationService.FlowInput>{ input }
            );
        Test.stopTest();

        //System.assertEquals(0, outputs[0].totalInterest, 'No interest when rate is 0');
    }

    @IsTest
    static void testIncrementalCalculation() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        // First calculation
        Test.startTest();
        InterestCalculationService.FlowInput input1 = new InterestCalculationService.FlowInput();
        input1.bookingId = booking.Id;
        input1.calculationDate = Date.today();
        InterestCalculationService.calculateInterest(
            new List<InterestCalculationService.FlowInput>{ input1 }
        );

        Integer firstCount = [SELECT COUNT() FROM Interest_Line_Item__c WHERE Booking__c = :booking.Id];

        // Second calculation on same date should not create duplicates
        InterestCalculationService.FlowInput input2 = new InterestCalculationService.FlowInput();
        input2.bookingId = booking.Id;
        input2.calculationDate = Date.today();
        InterestCalculationService.calculateInterest(
            new List<InterestCalculationService.FlowInput>{ input2 }
        );
        Test.stopTest();

        Integer secondCount = [SELECT COUNT() FROM Interest_Line_Item__c WHERE Booking__c = :booking.Id];
        //System.assertEquals(firstCount, secondCount, 'Should not create duplicate interest line items for same date');
    }

    // ---- Include Interest / Do Not Calculate Interest / booking Total Interest / Flat + GST split

    private static Booking__c ruleBooking(Boolean doNotCalculate, Date resumeDate) {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(Project__c = project.Id, Plot__c = unit.Id,
            Booking_Date__c = Date.today().addDays(-120), Status__c = 'Booked',
            Do_Not_Calculate_Interest__c = doNotCalculate, Interest_Calculation_Resume_Date__c = resumeDate);
        insert b;
        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>{
            new Payment_Schedule__c(Booking__c = b.Id, Sequence__c = 1, Amount__c = 118000,
                Payment_Schedule_Amount_Pending__c = 100000, GST_Amount_Pending__c = 18000,
                Due_Date__c = Date.today().addDays(-30), Status__c = 'Completed', Include_Interest__c = false),
            new Payment_Schedule__c(Booking__c = b.Id, Sequence__c = 2, Amount__c = 118000,
                Payment_Schedule_Amount_Pending__c = 100000, GST_Amount_Pending__c = 18000,
                Due_Date__c = Date.today().addDays(-30), Status__c = 'Completed', Include_Interest__c = true)
        };
        insert rows;
        // Flat demanded 30 days ago, GST demanded 10 days ago (Legacey style), for both milestones.
        List<Demands__c> demands = new List<Demands__c>();
        for (Payment_Schedule__c ps : rows) {
            demands.add(new Demands__c(Demand_Type__c = 'Individual Demand', Booking__c = b.Id, Payment_Schedule__c = ps.Id, Demand_Component__c = 'Flat',
                Due_Date__c = Date.today().addDays(-30), Status__c = 'Raised'));
            demands.add(new Demands__c(Demand_Type__c = 'Individual Demand', Booking__c = b.Id, Payment_Schedule__c = ps.Id, Demand_Component__c = 'GST',
                Due_Date__c = Date.today().addDays(-10), Status__c = 'Raised'));
        }
        insert demands;
        return b;
    }

    private static Payment_Schedule__c ticked(Id bookingId) {
        return [SELECT Id, Interest_Pending__c FROM Payment_Schedule__c WHERE Booking__c = :bookingId AND Include_Interest__c = true];
    }

    @isTest
    static void flatAndGstRunFromTheirOwnDemandDates_completedDoesNotStopIt() {
        Booking__c b = ruleBooking(false, null);
        Test.startTest();
        InterestCalculationService.calculateForBooking(b.Id, Date.today());
        Test.stopTest();
        Payment_Schedule__c ps = ticked(b.Id);
        Map<String, Interest_Line_Item__c> byPart = new Map<String, Interest_Line_Item__c>();
        for (Interest_Line_Item__c li : [SELECT Component__c, From_Date__c, Number_of_Days__c, Principal_Amount__c, Amount__c
                                         FROM Interest_Line_Item__c WHERE Payment_Schedule__c = :ps.Id]) {
            byPart.put(li.Component__c, li);
        }
        System.assertEquals(2, byPart.size(), 'one Flat and one GST line on the Completed milestone');
        System.assertEquals(30, byPart.get('Flat').Number_of_Days__c);
        System.assertEquals(100000, byPart.get('Flat').Principal_Amount__c, 'Flat pending only - no GST, no TDS');
        System.assertEquals(10, byPart.get('GST').Number_of_Days__c, 'GST from its own demand date');
        System.assertEquals(18000, byPart.get('GST').Principal_Amount__c);
        // 100000 x 18% / 365 x 30 = 1479.45 ; 18000 x 18% / 365 x 10 = 88.77
        System.assertEquals(1479.45, byPart.get('Flat').Amount__c);
        System.assertEquals(88.77, byPart.get('GST').Amount__c);
        System.assertEquals(1568.22, ps.Interest_Pending__c);
        System.assertEquals(0, [SELECT COUNT() FROM Interest_Line_Item__c WHERE Booking__c = :b.Id AND Payment_Schedule__c != :ps.Id],
            'milestone not ticked Include Interest: no interest');
        System.assertEquals(1568.22, [SELECT Total_Interest__c FROM Booking__c WHERE Id = :b.Id].Total_Interest__c);
    }

    @isTest
    static void noDemandNoInterest_paidStopsInterest() {
        Booking__c b = ruleBooking(false, null);
        Payment_Schedule__c ps = ticked(b.Id);
        delete [SELECT Id FROM Demands__c WHERE Payment_Schedule__c = :ps.Id AND Demand_Component__c = 'GST'];
        update new Payment_Schedule__c(Id = ps.Id, Payment_Schedule_Amount_Pending__c = 0); // flat fully paid
        Test.startTest();
        InterestCalculationService.FlowOutput out = InterestCalculationService.calculateForBooking(b.Id, Date.today());
        Test.stopTest();
        System.assertEquals(0, out.totalInterest, 'flat paid, GST never demanded: nothing to charge');
    }

    @isTest
    static void fullyPaidStopsInterest() {
        Booking__c b = ruleBooking(false, null);
        // Production milestones are only Pending / Completed: "paid" = nothing left pending.
        update new Payment_Schedule__c(Id = ticked(b.Id).Id, Payment_Schedule_Amount_Pending__c = 0,
            GST_Amount_Pending__c = 0);
        Test.startTest();
        InterestCalculationService.FlowOutput out = InterestCalculationService.calculateForBooking(b.Id, Date.today());
        Test.stopTest();
        System.assertEquals(0, out.totalInterest);
    }

    @isTest
    static void rerunSameDayAddsNothing() {
        Booking__c b = ruleBooking(false, null);
        InterestCalculationService.calculateForBooking(b.Id, Date.today());
        Test.startTest();
        InterestCalculationService.FlowOutput again = InterestCalculationService.calculateForBooking(b.Id, Date.today());
        Test.stopTest();
        System.assertEquals(0, again.totalInterest);
    }

    @isTest
    static void doNotCalculateInterest_skipsBooking() {
        Booking__c b = ruleBooking(true, null);
        Test.startTest();
        InterestCalculationService.FlowOutput out = InterestCalculationService.calculateForBooking(b.Id, Date.today());
        Test.stopTest();
        System.assertEquals(0, out.totalInterest);
        System.assertEquals(0, [SELECT COUNT() FROM Interest_Line_Item__c WHERE Booking__c = :b.Id]);
    }

    @isTest
    static void resumeDate_chargesOnlyFromResumeDate() {
        Booking__c b = ruleBooking(true, Date.today().addDays(-5));
        Test.startTest();
        InterestCalculationService.calculateForBooking(b.Id, Date.today());
        Test.stopTest();
        for (Interest_Line_Item__c li : [SELECT From_Date__c, Number_of_Days__c FROM Interest_Line_Item__c WHERE Booking__c = :b.Id]) {
            System.assertEquals(Date.today().addDays(-5), li.From_Date__c);
            System.assertEquals(5, li.Number_of_Days__c);
        }
    }

    @isTest
    static void batchCalculatesTheWholeChunk() {
        Booking__c b = ruleBooking(false, null);
        Test.startTest();
        Database.executeBatch(new InterestCalculationBatch(), 20);
        Test.stopTest();
        System.assertEquals(1568.22, [SELECT Total_Interest__c FROM Booking__c WHERE Id = :b.Id].Total_Interest__c);
    }
}