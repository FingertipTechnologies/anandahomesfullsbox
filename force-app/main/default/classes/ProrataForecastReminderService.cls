/**
 * @description Forecasting milestone reminder ("Gentle Reminder: Upcoming Instalment") to the customer
 *              (BRD §8.4). When a Master Payment Schedule's Forecast Date is reached, every booking
 *              payment-schedule line of that milestone whose demand is not yet raised gets the reminder.
 *              The wording follows "FORECASTING MILESTONE REMINDER MAIL 1.docx" (2026-11-15): it covers
 *              self-funding, bank-loan and pro-rata cases; it is sent to Prorata and Partial bookings only.
 *              Milestones of one booking that share the same demand date go out as ONE mail
 *              ("... Footings ... & ... Transfer Slab ...").
 *
 *              Runs daily from ForecastReminderSchedulable (forecast reminder only) or
 *              DemandReminderSchedulable (all demand automation).
 * @author System
 */
public with sharing class ProrataForecastReminderService {

    private static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Paid', 'Completed', 'Waived' };
    private static final Set<String> FUNDING_PRORATA = new Set<String>{ 'Prorata', 'Partial' };
    private static final List<String> MONTHS = new List<String>{
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    };

    /**
     * @description Sends due forecast reminders and returns the number of mails sent.
     */
    public static Integer processDueForecastReminders() {
        Date today = Date.today();

        List<Payment_Schedule__c> schedules = [
            SELECT Id, Milestone_Name__c, Master_Payment_Schedule__r.Milestone_Name__c, Forecast_Date__c, Due_Date__c, Demand_Date__c,
                   Master_Payment_Schedule__r.Expected_Demand_Date__c,
                   Booking__c, Booking__r.Name, Booking__r.Email__c, Booking__r.OwnerId,
                   Booking__r.Project__r.Name
            FROM Payment_Schedule__c
            WHERE Forecast_Date__c <= :today
            AND Forecast_Reminder_Sent__c = false
            AND Demand_Raised__c = false
            AND Status__c NOT IN :CLOSED_STATUSES
            AND Booking__r.Funding_Type__c IN :FUNDING_PRORATA
            AND Booking__r.Project__r.Legacy_Split_Demand_Receipt__c = true
            ORDER BY Booking__c, Sequence__c
            LIMIT 500
        ];
        if (schedules.isEmpty()) {
            return 0;
        }

        // One mail per booking and demand date.
        Map<String, List<Payment_Schedule__c>> groups = new Map<String, List<Payment_Schedule__c>>();
        Set<Id> ownerIds = new Set<Id>();
        for (Payment_Schedule__c ps : schedules) {
            if (ps.Booking__r == null || String.isBlank(ps.Booking__r.Email__c)) {
                continue;
            }
            String key = ps.Booking__c + '|' + String.valueOf(demandDate(ps));
            if (!groups.containsKey(key)) {
                groups.put(key, new List<Payment_Schedule__c>());
            }
            groups.get(key).add(ps);
            if (ps.Booking__r.OwnerId != null) {
                ownerIds.add(ps.Booking__r.OwnerId);
            }
        }
        Map<Id, String> ownerEmails = getUserEmails(ownerIds);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Id> emailBookingIds = new List<Id>();
        List<Payment_Schedule__c> toUpdate = new List<Payment_Schedule__c>();
        for (List<Payment_Schedule__c> lines : groups.values()) {
            Booking__c booking = lines[0].Booking__r;
            String ownerEmail = booking.OwnerId != null ? ownerEmails.get(booking.OwnerId) : null;
            emails.add(buildEmail(lines, ownerEmail));
            emailBookingIds.add(lines[0].Booking__c);
            for (Payment_Schedule__c ps : lines) {
                toUpdate.add(new Payment_Schedule__c(
                    Id = ps.Id, Forecast_Reminder_Sent__c = true, Forecast_Reminder_Sent_Date__c = System.now()
                ));
            }
        }

        if (!emails.isEmpty()) {
            // Reminders to the applicant also go to the co-applicants.
            try { EmailSenderInvocable.addCoApplicantCc(emails, emailBookingIds); }
            catch (Exception e) { System.debug('Co-applicant CC skipped: ' + e.getMessage()); }
            try {
                Messaging.sendEmail(emails, false);
            } catch (Exception e) {
                System.debug('ProrataForecastReminderService email error: ' + e.getMessage());
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return emails.size();
    }

    /** The milestone's demand date: Master Expected Demand Date, else the line's Demand Date, else its Due Date. */
    @TestVisible
    private static Date demandDate(Payment_Schedule__c ps) {
        if (ps.Master_Payment_Schedule__r != null && ps.Master_Payment_Schedule__r.Expected_Demand_Date__c != null) {
            return ps.Master_Payment_Schedule__r.Expected_Demand_Date__c;
        }
        return ps.Demand_Date__c != null ? ps.Demand_Date__c : ps.Due_Date__c;
    }

    /** 2026-01-02 -> "2nd January 2026" (blank date -> a hand-fill line). */
    @TestVisible
    private static String dateText(Date d) {
        if (d == null) {
            return '__________';
        }
        Integer day = d.day();
        String suffix = 'th';
        if (day < 11 || day > 13) {
            Integer last = Math.mod(day, 10);
            suffix = last == 1 ? 'st' : (last == 2 ? 'nd' : (last == 3 ? 'rd' : 'th'));
        }
        return day + suffix + ' ' + MONTHS[d.month() - 1] + ' ' + d.year();
    }

    @TestVisible
    private static Messaging.SingleEmailMessage buildEmail(List<Payment_Schedule__c> lines, String ownerEmail) {
        Booking__c booking = lines[0].Booking__r;
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ booking.Email__c });
        if (String.isNotBlank(ownerEmail)) {
            email.setCcAddresses(new List<String>{ ownerEmail });
        }

        List<String> names = new List<String>();
        for (Payment_Schedule__c ps : lines) {
            String n = String.isNotBlank(ps.Milestone_Name__c) ? ps.Milestone_Name__c
                : (ps.Master_Payment_Schedule__r != null && String.isNotBlank(ps.Master_Payment_Schedule__r.Milestone_Name__c)
                    ? ps.Master_Payment_Schedule__r.Milestone_Name__c : 'Upcoming Milestone');
            if (!names.contains(n.trim())) {
                names.add(n.trim());
            }
        }
        String milestones = String.join(names, ' & ');
        String project = booking.Project__r != null && String.isNotBlank(booking.Project__r.Name)
            ? booking.Project__r.Name : 'Ananda Homes';
        String onDate = dateText(demandDate(lines[0]));
        String crmEmail = System.Label.Forecast_Reminder_CRM_Team_Email;

        email.setSubject('Gentle Reminder: Upcoming Instalment – ' + milestones + ' – “' + project + ' Project”');

        String p = '<p style="margin:0 0 10px 0; line-height:1.5;">';
        String body = p + 'Dear Sir / Madam,</p>'
            + p + 'This is a kind reminder that for the next instalment, <b>“' + esc(milestones) + ',”</b> is scheduled for <b>'
                + onDate + '</b>. A demand letter will be raised for your respective flat as per the agreed flat cost and '
                + 'instalment stage. In addition, construction progress images will be uploaded on our official website: '
                + 'on or before <b>' + onDate + '.</b></p>'
            + p + '<b>1. Opted for Self-Funding Disbursement:</b></p>'
            + p + 'For the self-funding category, request to arrange the necessary funds in advance to ensure a smooth '
                + 'transaction. This includes:</p>'
            + '<ul style="margin:0 0 10px 0;">'
                + '<li>Flat Payment as per your Cost sheet, by deducting the 1% TDS on it.</li>'
                + '<li>GST Amount as per your Cost sheet.</li>'
                + '<li>1% TDS Payment, to be paid by you after the flat payment.</li>'
            + '</ul>'
            + p + '<b>2. Opted for Bank Loan Disbursement:</b></p>'
            + p + 'For the clients who opted bank loan, they will be receiving the DEMAND LETTER on <b>' + onDate
                + '</b> from respective SPOC or from our common mail ID. Please ensure that the disbursement should be '
                + 'released within 15 days from the date of the demand letter raised. After the bank disbursement you will '
                + 'be receiving mail from the CRM team, to pay the 1% TDS on the disbursed amount.</p>'
            + '<ul style="margin:0 0 10px 0;">'
                + '<li>Need to pay 1% TDS challan within a week time to avoid penalty mails from Income Tax Dept.</li>'
                + '<li>Submit the challan copy through mail only, for our records.</li>'
            + '</ul>'
            + p + '<b>3. Pro rata Category: -</b></p>'
            + '<ul style="margin:0 0 10px 0;">'
                + '<li>The clients who have the deficit of loan amount, request to please arrange the deficit amounts as per '
                + 'your pro rata proposal schedule agreed by you. The deficit amount needs to be credited before the demand '
                + 'letter issued, which helps us to raise the balance amount of that milestone if any from the bank.</li>'
            + '</ul>'
            + p + '<b>Important Note:</b></p>'
            + '<ul style="margin:0 0 10px 0;">'
                + '<li>Case 1: If anyone has not yet initiated the bank loan process, we request you to please confirm the '
                + 'bank from which the loan has to be opted to ensure a smooth and timely process.</li>'
                + '<li>Case 2: If you have opted for a loan for the flat payment but GST is self-funded, kindly arrange the '
                + 'GST amount in advance.</li>'
                + '<li>Case 3: If any pro-rata amount is applicable, please ensure the funds are to be arranged by '
                + onDate + ' before the demand letter is issued.</li>'
                + '<li>Case 4: We request you to please do intimate to us before <b>' + onDate + '</b>, if you are planning '
                + 'to clear this disbursement either by self-payment mode or part self-payment instead releasing from loan. '
                + 'It helps us to raise the demand letter with correct amount to avoid excess amount disbursements from the '
                + 'bank, who choose to arrange part payment by self and the balance part of disbursement from the loan. This '
                + 'has to be discussed and intimated to the respective SPOC through mail / WhatsApp communication.</li>'
            + '</ul>'
            + p + 'Please treat this as a gentle reminder to facilitate a smooth process. Should you require any '
                + 'clarification or assistance, feel free to reach out.</p>'
            + p + 'Looking forward to your confirmation.</p>'
            + '<p style="margin:0; line-height:1.5;">Warm Regards,<br/><b>TEAM - CRM</b><br/><b>' + esc(project)
                + ' Project</b><br/><b>Email: ' + esc(crmEmail) + '</b><br/><b>Website: www.anandahomes.co.in</b></p>';
        email.setHtmlBody(body);
        // Not tied to one demand, so logged on the Booking's Activity tab.
        email.setWhatId(lines[0].Booking__c);
        email.setSaveAsActivity(true);
        return email;
    }

    private static String esc(String value) {
        return value == null ? '' : value.escapeHtml4();
    }

    private static Map<Id, String> getUserEmails(Set<Id> userIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (userIds == null || userIds.isEmpty()) {
            return result;
        }
        for (User u : [SELECT Id, Email FROM User WHERE Id IN :userIds]) {
            result.put(u.Id, u.Email);
        }
        return result;
    }
}