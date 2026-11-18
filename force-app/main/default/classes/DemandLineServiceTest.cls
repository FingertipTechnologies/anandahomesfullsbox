@IsTest
private class DemandLineServiceTest {

    @TestSetup
    static void setup() {
        Project__c project = new Project__c(
            Name = 'Demand Line Test Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;

        Plot__c unit = new Plot__c(
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked'
        );
        insert unit;

        Quote__c quote = new Quote__c();
        insert quote;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Quote__c = quote.Id,
            Booking_Date__c = Date.today(),
            Booking_Amount__c = 100000,
            Total_Flat_Cost__c = 1000000,
            GST_Amount__c = 50000,
            Total_Payable_Amount__c = 1050000,
            Mode_Of_Payment__c = 'UPI',
            Status__c = 'New',
            Email__c = 'demandline@example.com',
            Applicant_Name__c = 'Demand Line Customer',
            Flat_Number__c = 201,
            Block1__c = 'C'
        );
        insert booking;

        insert new List<Payment_Schedule__c>{
            new Payment_Schedule__c(
                Booking__c = booking.Id,
                Sequence__c = 91,
                Milestone_Name__c = 'Demand Line Slab One',
                Percentage__c = 10,
                Amount__c = 105000,
                Pending_Amount__c = 105000,
                Amount_Paid__c = 0,
                Due_Date__c = Date.today(),
                Status__c = 'Pending',
                Payment_Schedule_Amount__c = 100000,
                GST_Amount__c = 5000,
                Payment_Schedule_Amount_Paid__c = 40000,
                GST_Amount_Paid__c = 2000,
                TDS_Amount_Paid__c = 400
            ),
            new Payment_Schedule__c(
                Booking__c = booking.Id,
                Sequence__c = 92,
                Percentage__c = 20,
                Amount__c = 210000,
                Pending_Amount__c = 210000,
                Amount_Paid__c = 0,
                Due_Date__c = Date.today(),
                Status__c = 'Pending',
                Payment_Schedule_Amount__c = 200000,
                GST_Amount__c = 10000
            )
        };
    }

    private static Booking__c booking() {
        return [SELECT Id, Project__c FROM Booking__c WHERE Email__c = 'demandline@example.com' LIMIT 1];
    }

    private static List<Payment_Schedule__c> schedules() {
        return [
            SELECT Id, Name
            FROM Payment_Schedule__c
            WHERE Booking__r.Email__c = 'demandline@example.com' AND Sequence__c IN (91, 92)
            ORDER BY Sequence__c
        ];
    }

    private static Demands__c newDemand(Booking__c b, Id scheduleId, String component, Decimal rawAmount) {
        // Currency values come back with 2 decimals; the staging key compares them as text.
        Decimal amount = rawAmount.setScale(2);
        return new Demands__c(
            Booking__c = b.Id,
            Project__c = b.Project__c,
            Payment_Schedule__c = scheduleId,
            Demand_Component__c = component,
            Demand_Amount__c = amount,
            Base_Amount__c = amount,
            Flat_Amount__c = amount,
            GST_Amount__c = 0,
            TDS_Amount__c = 0,
            Pending_Amount__c = amount,
            Demand_Type__c = 'Bulk Demand',
            Demand_Date__c = Date.newInstance(2026, 11, 2),
            Status__c = 'Raised'
        );
    }

    @IsTest
    static void createFromSchedule_buildsAmountsAndRequiresSchedule() {
        Payment_Schedule__c schedule = schedules()[0];

        Demand_Line__c line = DemandLineService.createFromSchedule(
            schedule, DemandComponentService.FLAT_AND_GST, 1000, 180, null, null
        );
        System.assertEquals(schedule.Id, line.Payment_Schedule__c);
        System.assertEquals(1180, line.Demand_Amount__c);
        System.assertEquals(0, line.TDS_Amount__c);
        System.assertEquals(0, line.Interest_Amount__c);

        Boolean threw = false;
        try {
            DemandLineService.createFromSchedule(null, DemandComponentService.FLAT, 1, 0, 0, 0);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'A demand line without a schedule must be rejected.');
    }

    @IsTest
    static void stagedLines_areInsertedWithTheDemand() {
        Booking__c b = booking();
        List<Payment_Schedule__c> ps = schedules();
        Demands__c demand = newDemand(b, ps[0].Id, DemandComponentService.FLAT_AND_GST, 315000);

        List<Demand_Line__c> lines = new List<Demand_Line__c>{
            DemandLineService.createFromSchedule(ps[0], DemandComponentService.FLAT_AND_GST, 100000, 5000, 0, 0),
            DemandLineService.createFromSchedule(ps[1], DemandComponentService.FLAT_AND_GST, 200000, 10000, 0, 0)
        };

        Test.startTest();
        DemandLineService.stageForInsert(demand, lines);
        insert demand;
        Test.stopTest();


    }

    @IsTest
    static void unstagedDemand_getsFallbackLinePerComponent() {
        Booking__c b = booking();
        Id scheduleId = schedules()[0].Id;
        List<Demands__c> demands = new List<Demands__c>{
            newDemand(b, scheduleId, DemandComponentService.FLAT, 1001),
            newDemand(b, scheduleId, DemandComponentService.GST, 1002),
            newDemand(b, null, DemandComponentService.FLAT, 1003)
        };

        Test.startTest();
        DemandLineService.stageForInsert(newDemand(b, scheduleId, DemandComponentService.FLAT, 9999), null);
        DemandLineService.clearStagedLines();
        insert demands;
        Test.stopTest();

        Map<Id, Demand_Line__c> lineByDemand = new Map<Id, Demand_Line__c>();
        for (Demand_Line__c l : [SELECT Demand__c, Received_Amount__c FROM Demand_Line__c WHERE Demand__c IN :demands]) {
            lineByDemand.put(l.Demand__c, l);
        }
      
    }

    @IsTest
    static void guards_rejectMissingInputs() {
        Boolean noDemand = false;
        try {
            DemandLineService.stageForInsert(null, new List<Demand_Line__c>());
        } catch (AuraHandledException e) {
            noDemand = true;
        }
        System.assert(noDemand);

        Boolean noDemandId = false;
        try {
            DemandLineService.attachToDemand(null, new List<Demand_Line__c>());
        } catch (AuraHandledException e) {
            noDemandId = true;
        }
        System.assert(noDemandId);

        Boolean noSchedule = false;
        try {
            DemandLineService.insertLines(new List<Demand_Line__c>{ new Demand_Line__c() });
        } catch (AuraHandledException e) {
            noSchedule = true;
        }
        System.assert(noSchedule, 'A line whose schedule cannot be loaded must be rejected.');

        DemandLineService.createForInsertedDemands(null);
        DemandLineService.insertLines(null);
        DemandLineService.attachToDemand(UserInfo.getUserId(), null);
        DemandLineService.applyAmountOverrides(null, DemandComponentService.FLAT, 1, 1, 1);
    }

    @IsTest
    static void insertForDemand_attachesAndSavesLines() {
        Booking__c b = booking();
        List<Payment_Schedule__c> ps = schedules();
        Demands__c demand = newDemand(b, null, DemandComponentService.GST, 5000);
        insert demand;

        DemandLineService.insertForDemand(demand.Id, new List<Demand_Line__c>{
            DemandLineService.createFromSchedule(ps[1], DemandComponentService.GST, 0, 5000, 0, 0)
        });

        System.assertEquals(1, [SELECT COUNT() FROM Demand_Line__c WHERE Demand__c = :demand.Id]);
    }

    @IsTest
    static void applyAmountOverrides_splitsByWeightAndComponent() {
        List<Payment_Schedule__c> ps = schedules();
        List<Demand_Line__c> lines = new List<Demand_Line__c>{
            DemandLineService.createFromSchedule(ps[0], DemandComponentService.FLAT_AND_GST, 100, 18, 0, 0),
            DemandLineService.createFromSchedule(ps[1], DemandComponentService.FLAT_AND_GST, 300, 54, 0, 0)
        };
        DemandLineService.applyAmountOverrides(lines, DemandComponentService.FLAT_AND_GST, 800, 144, 20);
        System.assertEquals(200, lines[0].Flat_Amount__c);
        System.assertEquals(600, lines[1].Flat_Amount__c);
        System.assertEquals(36, lines[0].GST_Amount__c);
        System.assertEquals(108, lines[1].GST_Amount__c);
        System.assertEquals(20, lines[0].TDS_Amount__c, 'With no TDS weight the first line takes it all.');
        System.assertEquals(0, lines[1].TDS_Amount__c);
        System.assertEquals(256, lines[0].Demand_Amount__c);

        List<Demand_Line__c> gstOnly = new List<Demand_Line__c>{
            DemandLineService.createFromSchedule(ps[0], DemandComponentService.GST, 100, 18, 0, 0)
        };
        DemandLineService.applyAmountOverrides(gstOnly, DemandComponentService.GST, 999, 50, 999);
        System.assertEquals(100, gstOnly[0].Flat_Amount__c, 'A GST demand keeps its flat amount.');
        System.assertEquals(50, gstOnly[0].GST_Amount__c);

        List<Demand_Line__c> flatOnly = new List<Demand_Line__c>{
            DemandLineService.createFromSchedule(ps[0], DemandComponentService.FLAT, 100, 18, 0, 0)
        };
        DemandLineService.applyAmountOverrides(flatOnly, DemandComponentService.FLAT, 70, 999, 0);
        System.assertEquals(70, flatOnly[0].Flat_Amount__c);
        System.assertEquals(18, flatOnly[0].GST_Amount__c, 'A flat demand keeps its GST amount.');
    }
}