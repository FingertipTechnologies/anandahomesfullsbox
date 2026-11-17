@isTest
private class DemandReminderLettersTest {

    private static Demands__c demand() {
        Booking__c b = new Booking__c(
            Salutation__c = 'Mr.', First_Applicant_Name__c = 'Ravi Kumar',
            Permanent_Address__c = '1-2-3, Hyderabad', Booking_Date__c = Date.newInstance(2026, 1, 5),
            Total_Flat_Cost__c = 9455900
        );
        b.Plot__r = new Plot__c(Name = 'T1-1307');
        b.Project__r = new Project__c(Name = 'The Legacey');
        Demands__c d = new Demands__c(
            Demand_Amount__c = 500000, Pending_Amount__c = 125000,
            Demand_Date__c = Date.newInstance(2026, 2, 1), Due_Date__c = Date.newInstance(2026, 2, 16),
            Reminder_1_Date__c = Date.newInstance(2026, 3, 3)
        );
        d.Booking__r = b;
        return d;
    }

    @isTest
    static void demandReminder1() {
        DemandReminderLetters.Letter l = DemandReminderLetters.build(demand(), 1, false, null);
        System.assertEquals('Reminder for Payment of Demand Raised', l.subject);
        System.assert(l.htmlBody.contains('unit bearing No. <b>T1-1307</b> in the project <b>THE LEGACEY</b>'), l.htmlBody);
        System.assert(l.htmlBody.contains('&#8377; 1,25,000'), l.htmlBody);
        System.assert(l.htmlBody.contains('issued dated <b>01/02/2026</b>'), l.htmlBody);
        System.assert(l.htmlBody.contains('on or before <b>16/02/2026</b>'), l.htmlBody);
    }

    @isTest
    static void demandReminder2() {
        DemandReminderLetters.Letter l = DemandReminderLetters.build(demand(), 2, false, null);
        System.assertEquals('2nd Reminder for Payment of Outstanding Demand', l.subject);
        System.assert(l.htmlBody.contains('reminder letter dated <b>03/03/2026</b>'), l.htmlBody);
        System.assert(l.htmlBody.contains('final opportunity'), l.htmlBody);
    }

    @isTest
    static void marginReminder1() {
        User owner = new User(LastName = 'Owner', Email = 'crm@example.com', Phone = '9999999999');
        DemandReminderLetters.Letter l = DemandReminderLetters.build(demand(), 1, true, owner);
        System.assertEquals('Demand for Payment of Margin Amount for Flat Booking', l.subject);
        System.assert(l.htmlBody.contains('dated <b>05/01/2026</b>'), l.htmlBody);
        System.assert(l.htmlBody.contains('Total Flat Cost: <b>&#8377; 94,55,900</b>'), l.htmlBody);
        System.assert(l.htmlBody.contains('Margin Amount Payable: <b>&#8377; 5,00,000</b>'), l.htmlBody);
        System.assert(l.htmlBody.contains('Amount Paid: <b>&#8377; 3,75,000</b>'), l.htmlBody);
        System.assert(l.htmlBody.contains('Balance Amount Due: <b>&#8377; 1,25,000</b>'), l.htmlBody);
        System.assert(l.htmlBody.contains('crm@example.com / 9999999999'), l.htmlBody);
    }

    @isTest
    static void marginReminder2() {
        Demands__c d = demand();
        d.Reminder_1_Sent_Date__c = DateTime.newInstance(2026, 3, 4, 10, 0, 0);
        DemandReminderLetters.Letter l = DemandReminderLetters.build(d, 2, true, null);
        System.assertEquals('2nd Reminder for Payment of Margin Amount', l.subject);
        System.assert(l.htmlBody.contains('earlier reminder dated <b>04/03/2026</b>'), l.htmlBody);
        System.assert(l.htmlBody.contains('within <b>7</b> days'), l.htmlBody);
    }

    @isTest
    static void demandReminder3_withInterest() {
        Demands__c d = demand();
        d.Reminder_2_Date__c = Date.newInstance(2026, 3, 9);
        d.Interest_Amount__c = 5000;
        d.Interest_Waived_Off_Amount__c = 1000;
        DemandReminderLetters.Letter l = DemandReminderLetters.build(d, 3, false, null);
        System.assertEquals('3rd Reminder for Payment of Outstanding Demand with Interest', l.subject);
        System.assert(l.htmlBody.contains('reminder letters dated <b>03/03/2026</b>, <b>09/03/2026</b> regarding'), l.htmlBody);
        System.assert(l.htmlBody.contains('interest of <b>&#8377; 4,000</b>'), l.htmlBody);
        System.assert(l.htmlBody.contains('total amount now payable by you is <b>&#8377; 1,29,000</b>'), l.htmlBody);
    }

    @isTest
    static void demandReminder4_terminationIntimation() {
        Demands__c d = demand();
        d.Reminder_2_Sent_Date__c = DateTime.newInstance(2026, 3, 10, 9, 0, 0);
        d.Reminder_3_Date__c = Date.newInstance(2026, 3, 18);
        d.Interest_Amount__c = 2500;
        DemandReminderLetters.Letter l = DemandReminderLetters.build(d, 4, true, null);
        System.assertEquals('Final Notice - Intimation of Termination of Allotment for Non-Payment', l.subject);
        System.assert(l.htmlBody.contains('<b>10/03/2026</b> and <b>18/03/2026</b>'), l.htmlBody);
        System.assert(l.htmlBody.contains('final notice and intimation of termination'), l.htmlBody);
        System.assert(l.htmlBody.contains('pay the total amount of <b>&#8377; 1,27,500</b>'), l.htmlBody);
    }

    @isTest
    static void otherLevelsAndHelpers() {
        System.assertEquals(null, DemandReminderLetters.build(demand(), 5, false, null));
        System.assertEquals(0, DemandReminderLetters.netInterest(new Demands__c(Interest_Amount__c = 10, Interest_Waived_Off_Amount__c = 50)));
        System.assertEquals('__________', DemandReminderLetters.fmt(null));
        System.assertEquals('99,28,695', DemandReminderLetters.inr(9928695));
        System.assertEquals('0', DemandReminderLetters.inr(null));
        Demands__c bare = new Demands__c(Pending_Amount__c = 10);
        System.assert(DemandReminderLetters.build(bare, 1, false, null).htmlBody.contains('__________'));
    }
}