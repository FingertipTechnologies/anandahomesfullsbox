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

    /** Include Interest flows from the master, like Is Agreement. */
    @isTest
    static void masterIncludeInterest_flowsToSchedule() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert b;

        Master_Payment_Schedule__c agreement = new Master_Payment_Schedule__c(Project__c = project.Id,
            Sequence__c = 2, Percentage__c = 20, Is_Active__c = true, Is_Agreement__c = true, Include_Interest__c = false);
        Master_Payment_Schedule__c below = new Master_Payment_Schedule__c(Project__c = project.Id,
            Sequence__c = 3, Percentage__c = 20, Is_Active__c = true, Include_Interest__c = true);
        insert new List<Master_Payment_Schedule__c>{ agreement, below };

        Test.startTest();
        Payment_Schedule__c psAgreement = new Payment_Schedule__c(Booking__c = b.Id,
            Master_Payment_Schedule__c = agreement.Id, Sequence__c = 2, Amount__c = 100000, Status__c = 'Pending');
        Payment_Schedule__c psBelow = new Payment_Schedule__c(Booking__c = b.Id,
            Master_Payment_Schedule__c = below.Id, Sequence__c = 3, Amount__c = 100000, Status__c = 'Pending');
        insert new List<Payment_Schedule__c>{ psAgreement, psBelow };
        Test.stopTest();

        Payment_Schedule__c a = [SELECT Is_Agreement__c, Include_Interest__c FROM Payment_Schedule__c WHERE Id = :psAgreement.Id];
        Payment_Schedule__c c = [SELECT Is_Agreement__c, Include_Interest__c FROM Payment_Schedule__c WHERE Id = :psBelow.Id];
        System.assertEquals(true, a.Is_Agreement__c);
        System.assertEquals(false, a.Include_Interest__c, 'master not ticked');
        System.assertEquals(false, c.Is_Agreement__c);
        System.assertEquals(true, c.Include_Interest__c, 'ticked from the master');
    }
}
