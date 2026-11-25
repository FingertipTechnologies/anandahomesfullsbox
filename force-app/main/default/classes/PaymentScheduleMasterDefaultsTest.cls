/**
 * @description Tests that the Master Payment Schedule's Is_Agreement flag flows to the booking's
 *              Payment Schedule lines on creation.
 */
@isTest
private class PaymentScheduleMasterDefaultsTest {

    @isTest
    static void masterAgreementFlag_flowsToSchedule() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert b;

        Master_Payment_Schedule__c master = new Master_Payment_Schedule__c(
            Project__c = project.Id, Sequence__c = 1, Percentage__c = 20,
            Is_Active__c = true, Is_Agreement__c = true
        );
        insert master;

        Test.startTest();
        // Created WITHOUT Is_Agreement set — the trigger should copy it from the master.
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = b.Id, Master_Payment_Schedule__c = master.Id, Sequence__c = 1,
            Amount__c = 100000, Status__c = 'Pending'
        );
        insert ps;
        Test.stopTest();

        System.assertEquals(true,
            [SELECT Is_Agreement__c FROM Payment_Schedule__c WHERE Id = :ps.Id].Is_Agreement__c,
            'Is_Agreement should flow from the master payment schedule');
    }

    @isTest
    static void nonAgreementMaster_leavesScheduleFalse() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert b;

        Master_Payment_Schedule__c master = new Master_Payment_Schedule__c(
            Project__c = project.Id, Sequence__c = 2, Percentage__c = 20,
            Is_Active__c = true, Is_Agreement__c = false
        );
        insert master;

        Test.startTest();
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = b.Id, Master_Payment_Schedule__c = master.Id, Sequence__c = 2,
            Amount__c = 100000, Status__c = 'Pending'
        );
        insert ps;
        Test.stopTest();

        System.assertEquals(false,
            [SELECT Is_Agreement__c FROM Payment_Schedule__c WHERE Id = :ps.Id].Is_Agreement__c,
            'A non-agreement master must not flag the schedule');
    }

    /** Include Interest is ticked only on milestones below (after) the Agreement milestone. */
    @isTest
    static void includeInterest_onlyBelowAgreement() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert b;

        List<Payment_Schedule__c> rows = new List<Payment_Schedule__c>();
        for (Integer seq = 1; seq <= 4; seq++) {
            rows.add(new Payment_Schedule__c(Booking__c = b.Id, Sequence__c = seq, Amount__c = 100000,
                Status__c = 'Pending', Is_Agreement__c = seq == 2, Include_Interest__c = seq == 1));
        }
        Test.startTest();
        insert rows;
        Map<Decimal, Boolean> flags = new Map<Decimal, Boolean>();
        for (Payment_Schedule__c ps : [SELECT Sequence__c, Include_Interest__c FROM Payment_Schedule__c WHERE Booking__c = :b.Id]) {
            flags.put(ps.Sequence__c, ps.Include_Interest__c);
        }
        System.assertEquals(false, flags.get(1), 'above the agreement');
        System.assertEquals(false, flags.get(2), 'the agreement milestone itself');
        System.assertEquals(true, flags.get(3), 'below the agreement');
        System.assertEquals(true, flags.get(4), 'below the agreement');

        // A line added later (e.g. a revision) below the agreement is ticked too.
        Payment_Schedule__c extra = new Payment_Schedule__c(Booking__c = b.Id, Sequence__c = 5,
            Amount__c = 100, Status__c = 'Pending');
        insert extra;
        // Moving a line above the agreement clears it.
        update new Payment_Schedule__c(Id = rows[3].Id, Sequence__c = 1.5);
        Test.stopTest();
        System.assertEquals(true, [SELECT Include_Interest__c FROM Payment_Schedule__c WHERE Id = :extra.Id].Include_Interest__c);
        System.assertEquals(false, [SELECT Include_Interest__c FROM Payment_Schedule__c WHERE Id = :rows[3].Id].Include_Interest__c);
    }
}