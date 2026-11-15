/**
 * @description Tests for ProrataForecastReminderService - forecasting milestone reminder (BRD §8.4).
 *
 *              Payment_Schedule__c.Forecast_Date__c is a cross-object formula
 *              (= Master_Payment_Schedule__r.Forecast_Date__c), so these tests create a
 *              Master Payment Schedule with the desired Forecast Date and link it to the
 *              booking payment-schedule line.
 */
@isTest
private class ProrataForecastReminderServiceTest {

    private static Project__c project;

    private static Booking__c makeBooking(String fundingType, Boolean legacySplit) {
        project = new Project__c(
            Name = 'The Legacey', Project_Type__c = 'Residential', Interest_Rate__c = 18,
            Legacy_Split_Demand_Receipt__c = legacySplit
        );
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            Email__c = 'cust@example.com', First_Applicant_Name__c = 'Jane', Funding_Type__c = fundingType
        );
        insert b;
        return b;
    }

    private static Master_Payment_Schedule__c makeMaster(Date forecastDate, Date demandDate, Integer seq) {
        Master_Payment_Schedule__c m = new Master_Payment_Schedule__c(
            Project__c = project.Id,
            Sequence__c = seq,
            Percentage__c = 10,
            Forecast_Date__c = forecastDate,
            Expected_Demand_Date__c = demandDate,
            Is_Active__c = true
        );
        insert m;
        return m;
    }

    private static Payment_Schedule__c makeSchedule(Id bookingId, Id masterId, String milestone, Integer seq) {
        ProrataInvariantService.bypass = true; // setup data; invariant balance not under test here
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = bookingId, Sequence__c = seq, Milestone_Name__c = milestone,
            Amount__c = 100, Payment_Schedule_Amount__c = 90, GST_Amount__c = 10,
            Pending_Amount__c = 100, Amount_Paid__c = 0, Status__c = 'Pending',
            Master_Payment_Schedule__c = masterId, With_GST__c = false, Demand_Raised__c = false
        );
        insert ps;
        ProrataInvariantService.bypass = false;
        return ps;
    }

    @isTest
    static void forecastDue_prorata_sendsOneMailForSameDateMilestones() {
        Booking__c b = makeBooking('Prorata', true);
        Date demandDate = Date.newInstance(2026, 1, 2);
        Master_Payment_Schedule__c m1 = makeMaster(Date.today(), demandDate, 1);
        Master_Payment_Schedule__c m2 = makeMaster(Date.today(), demandDate, 2);
        Payment_Schedule__c ps1 = makeSchedule(b.Id, m1.Id, 'On Completion of Footings', 1);
        Payment_Schedule__c ps2 = makeSchedule(b.Id, m2.Id, 'On Completion of Transfer Slab', 2);

        Test.startTest();
        Integer sent = ProrataForecastReminderService.processDueForecastReminders();
        Test.stopTest();

        System.assertEquals(1, sent, 'Both milestones share a demand date: one mail');
        for (Payment_Schedule__c after : [SELECT Forecast_Reminder_Sent__c FROM Payment_Schedule__c WHERE Id IN :new List<Id>{ ps1.Id, ps2.Id }]) {
            System.assertEquals(true, after.Forecast_Reminder_Sent__c);
        }
    }

    @isTest
    static void buildEmail_followsTheCoveringLetter() {
        Booking__c b = makeBooking('Partial', true);
        Master_Payment_Schedule__c m = makeMaster(Date.today(), Date.newInstance(2026, 1, 2), 1);
        makeSchedule(b.Id, m.Id, 'On Completion of Footings', 1);
        List<Payment_Schedule__c> lines = [
            SELECT Id, Milestone_Name__c, Master_Payment_Schedule__r.Milestone_Name__c, Due_Date__c, Demand_Date__c,
                   Master_Payment_Schedule__r.Expected_Demand_Date__c,
                   Booking__c, Booking__r.Name, Booking__r.Email__c, Booking__r.OwnerId, Booking__r.Project__r.Name
            FROM Payment_Schedule__c WHERE Booking__c = :b.Id
        ];

        Messaging.SingleEmailMessage mail = ProrataForecastReminderService.buildEmail(lines, 'owner@example.com');

        System.assertEquals('Gentle Reminder: Upcoming Instalment – On Completion of Footings – “The Legacey Project”',
            mail.getSubject());
        String html = mail.getHtmlBody();
        System.assert(html.contains('is scheduled for <b>2nd January 2026</b>'), html);
        System.assert(html.contains('Opted for Bank Loan Disbursement'), html);
        System.assert(html.contains('TEAM - CRM'), html);
        System.assert(html.contains(System.Label.Forecast_Reminder_CRM_Team_Email), html);
        System.assertEquals('owner@example.com', mail.getCcAddresses()[0]);
    }

    @isTest
    static void dateText_ordinals() {
        System.assertEquals('1st January 2026', ProrataForecastReminderService.dateText(Date.newInstance(2026, 1, 1)));
        System.assertEquals('2nd January 2026', ProrataForecastReminderService.dateText(Date.newInstance(2026, 1, 2)));
        System.assertEquals('3rd March 2026', ProrataForecastReminderService.dateText(Date.newInstance(2026, 3, 3)));
        System.assertEquals('11th April 2026', ProrataForecastReminderService.dateText(Date.newInstance(2026, 4, 11)));
        System.assertEquals('22nd July 2026', ProrataForecastReminderService.dateText(Date.newInstance(2026, 7, 22)));
        System.assertEquals('__________', ProrataForecastReminderService.dateText(null));
    }

    @isTest
    static void notDue_noReminder() {
        Booking__c b = makeBooking('Prorata', true);
        Master_Payment_Schedule__c m = makeMaster(Date.today().addDays(10), Date.today().addDays(40), 1);
        makeSchedule(b.Id, m.Id, 'Foundation', 1);

        Test.startTest();
        Integer sent = ProrataForecastReminderService.processDueForecastReminders();
        Test.stopTest();

        System.assertEquals(0, sent, 'Future forecast date should not send');
    }

    @isTest
    static void otherFundingTypes_noReminder() {
        Booking__c b = makeBooking('Loan', true);
        Master_Payment_Schedule__c m = makeMaster(Date.today(), Date.today().addDays(30), 1);
        makeSchedule(b.Id, m.Id, 'Foundation', 1);

        Test.startTest();
        Integer sent = ProrataForecastReminderService.processDueForecastReminders();
        Test.stopTest();

        System.assertEquals(0, sent, 'Only Prorata and Partial bookings get the forecast reminder');
    }

    @isTest
    static void projectWithoutFlag_noReminder() {
        Booking__c b = makeBooking('Prorata', false);
        Master_Payment_Schedule__c m = makeMaster(Date.today(), Date.today().addDays(30), 1);
        makeSchedule(b.Id, m.Id, 'Foundation', 1);

        Test.startTest();
        Integer sent = ProrataForecastReminderService.processDueForecastReminders();
        Test.stopTest();

        System.assertEquals(0, sent, 'Only projects flagged Legacy Split Demand Receipt get the reminder');
    }
}
