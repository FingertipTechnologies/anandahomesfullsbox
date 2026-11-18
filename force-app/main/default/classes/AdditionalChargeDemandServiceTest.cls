/**
 * @description Tests for AdditionalChargeDemandService and the additional-charge reminder letters.
 */
@isTest
private class AdditionalChargeDemandServiceTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        // No Plot__c: the booking after-create flow needs a Quote when a unit is set.
        Booking__c b = new Booking__c(
            Project__c = project.Id, Booking_Date__c = Date.today(), Status__c = 'New',
            Email__c = 'cust@example.com', First_Applicant_Name__c = 'Jane'
        );
        insert b;
        return b;
    }

    private static Additional_Charge__c makeCharge(Id bookingId) {
        Additional_Charge__c c = new Additional_Charge__c(
            Booking__c = bookingId, Charge_Name__c = 'Extra Parking', Charge_Type__c = 'Additional Car Parking',
            Amount__c = 10000, GST_Amount__c = 1800, Amount_Paid__c = 0, Status__c = 'Draft'
        );
        insert c;
        return c;
    }

    private static List<Demands__c> demandsOf(Id chargeId) {
        return [
            SELECT Id, Demand_Type__c, Base_Amount__c, Demand_Amount__c, Paid_Amount__c, Pending_Amount__c, Status__c,
                   Demand_Date__c, Due_Date__c, Reminder_1_Date__c, Reminder_2_Date__c, Reminder_3_Date__c,
                   Reminder_4_Date__c, Termination_Mail_Date__c, Unit_Unblocking_Date__c, Project__c
            FROM Demands__c WHERE Additional_Charge__c = :chargeId
        ];
    }

    @isTest
    static void sendingDemandEmail_raisesDemandWith15And7DayReminders() {
        Booking__c b = makeBooking();
        Additional_Charge__c c = makeCharge(b.Id);
        System.assertEquals(0, demandsOf(c.Id).size(), 'no demand before the demand email');

        Date today = Date.today();
        Test.startTest();
        c.Demand_Date__c = today; // what the "Additional Charge Demand Email" field update does
        update c;
        Test.stopTest();

        List<Demands__c> ds = demandsOf(c.Id);
        System.assertEquals(1, ds.size());
        Demands__c d = ds[0];
        System.assertEquals('Additional Charge', d.Demand_Type__c);
        System.assertEquals(11800, d.Demand_Amount__c);
        System.assertEquals(10000, d.Base_Amount__c);
        System.assertEquals(11800, d.Pending_Amount__c);
        System.assertEquals('Emailed', d.Status__c);
        System.assertEquals(today.addDays(15), d.Reminder_1_Date__c);
        System.assertEquals(today.addDays(22), d.Reminder_2_Date__c);
        System.assertEquals(null, d.Reminder_3_Date__c);
        System.assertEquals(null, d.Reminder_4_Date__c);
        System.assertEquals(null, d.Termination_Mail_Date__c);
        System.assertEquals(null, d.Unit_Unblocking_Date__c);
        System.assertEquals(b.Project__c, d.Project__c);
        System.assertEquals('Demanded', [SELECT Status__c FROM Additional_Charge__c WHERE Id = :c.Id].Status__c);

        // Sending the email again does not raise a second demand.
        c.Demand_Date__c = today.addDays(1);
        update c;
        System.assertEquals(1, demandsOf(c.Id).size());
    }

    @isTest
    static void paymentsAndCancellation_syncToDemand() {
        Booking__c b = makeBooking();
        Additional_Charge__c c = makeCharge(b.Id);
        c.Demand_Date__c = Date.today();
        update c;

        Test.startTest();
        c.Amount_Paid__c = 5000;
        update c;
        System.assertEquals('Partially Paid', demandsOf(c.Id)[0].Status__c);
        System.assertEquals(6800, demandsOf(c.Id)[0].Pending_Amount__c);

        c.Amount_Paid__c = 11800;
        update c;
        System.assertEquals('Paid', demandsOf(c.Id)[0].Status__c);

        c.Amount_Paid__c = 0;
        update c;
        System.assertEquals('Emailed', demandsOf(c.Id)[0].Status__c);

        c.Status__c = 'Cancelled';
        update c;
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Demands__c WHERE Additional_Charge__c = :c.Id AND Status__c != 'Cancelled']);
    }

    @isTest
    static void insertWithDemandDate_andBypass() {
        Booking__c b = makeBooking();
        Additional_Charge__c c = new Additional_Charge__c(
            Booking__c = b.Id, Charge_Name__c = 'Club', Charge_Type__c = 'Additional Car Parking',
            Amount__c = 1000, Demand_Date__c = Date.today()
        );
        insert c;
        System.assertEquals(1, demandsOf(c.Id).size());

        AdditionalChargeDemandService.bypass = true;
        Additional_Charge__c c2 = makeCharge(b.Id);
        c2.Demand_Date__c = Date.today();
        update c2;
        System.assertEquals(0, demandsOf(c2.Id).size());
    }

    @isTest
    static void bulkDemand() {
        Booking__c b = makeBooking();
        List<Additional_Charge__c> charges = new List<Additional_Charge__c>();
        for (Integer i = 0; i < 20; i++) {
            charges.add(new Additional_Charge__c(
                Booking__c = b.Id, Charge_Name__c = 'C' + i, Charge_Type__c = 'Additional Car Parking',
                Amount__c = 100, Status__c = 'Draft'
            ));
        }
        insert charges;
        Test.startTest();
        for (Additional_Charge__c c : charges) {
            c.Demand_Date__c = Date.today();
        }
        update charges;
        Test.stopTest();
        System.assertEquals(20, [SELECT COUNT() FROM Demands__c WHERE Booking__c = :b.Id AND Demand_Type__c = 'Additional Charge']);
    }

    @isTest
    static void reminderLetters_forAdditionalCharge() {
        Booking__c b = new Booking__c();
        b.Plot__r = new Plot__c(Name = 'T1-1307');
        b.Project__r = new Project__c(Name = 'The Legacey');
        Demands__c d = new Demands__c(
            Additional_Charge__c = fakeChargeId(),
            Pending_Amount__c = 11800, Demand_Date__c = Date.newInstance(2026, 11, 1),
            Reminder_1_Date__c = Date.newInstance(2026, 11, 16)
        );
        d.Booking__r = b;
        d.Additional_Charge__r = new Additional_Charge__c(Charge_Name__c = 'Extra Parking');

        DemandReminderLetters.Letter l1 = DemandReminderLetters.build(d, 1, false, null);
        

        DemandReminderLetters.Letter l2 = DemandReminderLetters.build(d, 2, false, null);
        
    }

    private static Id fakeChargeId() {
        String prefix = Additional_Charge__c.SObjectType.getDescribe().getKeyPrefix();
        return Id.valueOf(prefix + '000000000001');
    }
}