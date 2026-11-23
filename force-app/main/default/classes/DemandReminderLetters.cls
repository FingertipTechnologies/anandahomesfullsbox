/**
 * @description The reminder letters sent by DemandReminderService when no admin email template is
 *              configured (Post_Sales_Configuration 'Demand Reminder 1' / 'Demand Reminder 2'):
 *              - demand reminders 1 and 2: "REMINDER LETTER - 1/2 (FOR DEMAND LETTER).docx"
 *              - Agreement Amount (AOS margin) reminders 1 and 2:
 *                "REMINDER LETTER - 1 (FOR AOS MARGIN AMOUNT) WL+30days.docx",
 *                "REMINDER LETTER - 2 (FOR AOS MARGIN AMOUNT) WL+ 45days.docx"  (2026-11-16)
 */
public with sharing class DemandReminderLetters {

    public class Letter {
        public String subject { get; private set; }
        public String htmlBody { get; private set; }
    }

    /** Days the allottee is given to pay, as written in the letters. */
    @TestVisible private static final Integer DAYS_TO_PAY = 7;

    private static final String P = '<p style="margin:0 0 10px 0; line-height:1.5;">';

    /**
     * @param d          demand with Booking__r (Plot__r.Name, Project__r.Name, Salutation__c,
     *                   First_Applicant_Name__c, Permanent_Address__c, Booking_Date__c, Total_Flat_Cost__c)
     * @param level      1 or 2
     * @param isMargin   true for the Agreement Amount (AOS margin) demand
     * @param owner      booking owner (Name, Email, Phone) - contact line of the margin letter; may be null
     * @return the letter, or null for any other level
     */
    public static Letter build(Demands__c d, Integer level, Boolean isMargin, User owner) {
        return build(d, level, isMargin, owner, null);
    }

    /**
     * @param liveInterest reminders 3/4: the demand's current interest (DemandReminderService.loadLiveInterest);
     *                     null = use the demand's own Interest_Amount__c less its waiver
     */
    public static Letter build(Demands__c d, Integer level, Boolean isMargin, User owner, Decimal liveInterest) {
        if (d == null || level == null || level < 1 || level > 4) {
            return null;
        }
        Letter l = new Letter();
        Booking__c b = d.Booking__r;
        String flat = b != null && b.Plot__r != null ? esc(b.Plot__r.Name) : '__________';
        String project = b != null && b.Project__r != null && String.isNotBlank(b.Project__r.Name)
            ? esc(b.Project__r.Name) : '__________';
        String pending = inr(d.Pending_Amount__c);
        String head = '';

        if ((level == 1 || level == 2) && d.getPopulatedFieldsAsMap().get('Additional_Charge__c') != null) {
            return additionalChargeLetter(d, level, flat, project);
        }

        if (level == 3 || level == 4) {
            // Demand reminders 3 and 4 (2026-11-17): reminder 2 wording + the interest levied;
            // reminder 4 is the final notice / intimation of termination.
            Decimal interest = liveInterest != null ? liveInterest : netInterest(d);
            Decimal open = d.Pending_Amount__c == null ? 0 : d.Pending_Amount__c;
            String interestLine = P + 'Please note that, as per the terms of the Agreement, interest of <b>&#8377; ' + inr(interest)
                + '</b> has been levied on the delayed payment as on date. The total amount now payable by you is <b>&#8377; '
                + inr(open + interest) + '</b> (outstanding amount of &#8377; ' + pending + ' plus interest of &#8377; '
                + inr(interest) + '), and interest will continue to accrue until the date of payment.</p>';
            String earlier = 'our demand notice dated <b>' + fmt(d.Demand_Date__c) + '</b> and reminder letters dated <b>'
                + fmt(reminderDate(d, 1)) + '</b>, <b>' + fmt(reminderDate(d, 2)) + '</b>'
                + (level == 4 ? ' and <b>' + fmt(reminderDate(d, 3)) + '</b>' : '');
            if (level == 3) {
                l.subject = '3rd Reminder for Payment of Outstanding Demand with Interest';
                l.htmlBody = P + 'Dear Sir/Madam,</p>'
                    + P + 'This is in continuation of ' + earlier + ' regarding the outstanding payment towards your allotted '
                        + 'unit bearing No <b>' + flat + '</b> in the project <b>' + project.toUpperCase() + '</b>.</p>'
                    + P + 'Despite repeated requests, we note with concern that the outstanding amount of <b>&#8377; ' + pending
                        + '</b>, which was due for payment on or before <b>' + fmt(d.Due_Date__c) + '</b>, remains unpaid. This '
                        + 'delay is in violation of the terms and conditions agreed under the Allotment Letter/Agreement.</p>'
                    + interestLine
                    + P + 'You are hereby called upon to clear the total amount payable of <b>&#8377; ' + inr(open + interest)
                        + '</b> within ' + DAYS_TO_PAY + ' days from the date of this letter, failing which we shall be '
                        + 'constrained to initiate appropriate action in accordance with the terms of the Agreement, including '
                        + 'cancellation of allotment and/or other legal remedies available under law, entirely at your risk as to '
                        + 'cost and consequences.</p>'
                    + P + 'Kindly treat this matter as most urgent.</p>'
                    + signature(null);
            } else {
                // Reminder 4 = termination intimation only (no further payment window), 2026-11-17.
                l.subject = 'Intimation of Termination of Allotment for Non-Payment';
                l.htmlBody = P + 'Dear Sir/Madam,</p>'
                    + P + 'This is with reference to ' + earlier + ' regarding the outstanding payment towards your allotted '
                        + 'unit bearing No <b>' + flat + '</b> in the project <b>' + project.toUpperCase() + '</b>.</p>'
                    + P + 'In spite of our repeated reminders, the outstanding amount of <b>&#8377; ' + pending + '</b>, which was '
                        + 'due for payment on or before <b>' + fmt(d.Due_Date__c) + '</b>, together with interest of <b>&#8377; '
                        + inr(interest) + '</b> levied on the delayed payment (total <b>&#8377; ' + inr(open + interest)
                        + '</b>), has not been paid till date. This is a breach of the terms and conditions of the Allotment '
                        + 'Letter/Agreement.</p>'
                    + P + 'We hereby intimate you that, owing to the said non-payment, the allotment of the above unit stands '
                        + '<b>terminated</b> in accordance with the terms of the Agreement.</p>'
                    + P + 'The amounts paid by you shall be dealt with, after the applicable deductions, as per the terms of the '
                        + 'Agreement. For the further formalities, please contact our CRM team.</p>'
                    + signature(null);
            }
        } else if (!isMargin && level == 1) {
            l.subject = 'Reminder for Payment of Demand Raised';
            l.htmlBody = 
                //+ P + '<b>Subject: Reminder for Payment of Demand Raised</b></p>'
                + P + 'Dear Sir/Madam,</p>'
                + P + 'This is to kindly remind you regarding the demand raised towards your allotted unit bearing No. <b>'
                    + flat + '</b> in the project <b>' + project.toUpperCase() + '</b>, pursuant to the Agreement executed between us.</p>'
                + P + 'We wish to inform you that an amount of <b>&#8377; ' + pending + '</b> is currently outstanding towards the '
                    + 'said demand issued dated <b>' + fmt(d.Demand_Date__c) + '</b>, which was due for payment on or before <b>'
                    + fmt(d.Due_Date__c) + '</b>. Despite our earlier communication, the said payment is yet to be received.</p>'
                + P + 'You are therefore requested to make the payment of the outstanding amount of <b>&#8377; ' + pending
                    + '</b> within ' + DAYS_TO_PAY + ' days from the date of this letter, to avoid any inconvenience or further '
                    + 'action as per the terms of the Agreement.</p>'
                + P + 'Kindly treat this matter as urgent and ensure compliance within the stipulated time.</p>'
                + P + 'Thanking you,</p>'
                + signature(null);
        } else if (!isMargin && level == 2) {
            l.subject = '2nd Reminder for Payment of Outstanding Demand';
            l.htmlBody = head
                //+ P + '<b>Subject: 2nd Reminder for Payment of Outstanding Demand</b></p>'
                + P + 'Dear Sir/Madam,</p>'
                + P + 'This is in continuation of our earlier demand notice dated <b>' + fmt(d.Demand_Date__c)
                    + '</b> and reminder letter dated <b>' + fmt(firstReminderDate(d)) + '</b> regarding the outstanding payment '
                    + 'towards your allotted unit bearing No <b>' + flat + '</b> in the project <b>' + project.toUpperCase() + '</b>.</p>'
                + P + 'Despite repeated requests, we note with concern that the outstanding amount of <b>&#8377; ' + pending
                    + '</b> remains unpaid beyond the due date. This delay is in violation of the terms and conditions agreed '
                    + 'under the Allotment Letter/Agreement.</p>'
                + P + 'You are hereby called upon to clear the entire outstanding amount of <b>&#8377; ' + pending + '</b> within '
                    + DAYS_TO_PAY + ' days from the date of this letter, failing which we shall be constrained to initiate '
                    + 'appropriate action in accordance with the terms of the Agreement, including but not limited to charging '
                    + 'applicable interest, cancellation of allotment, and/or other legal remedies available under law, entirely '
                    + 'at your risk as to cost and consequences.</p>'
                + P + 'Kindly treat this as the final opportunity to pay the outstanding amount and avoid further action.</p>'
                + signature(null);
        } else if (isMargin && level == 1) {
            Decimal demand = d.Demand_Amount__c == null ? 0 : d.Demand_Amount__c;
            Decimal open = d.Pending_Amount__c == null ? 0 : d.Pending_Amount__c;
            String contact = owner == null ? '' : join(new List<String>{ esc(owner.Email), esc(owner.Phone) }, ' / ');
            l.subject = 'Demand for Payment of Margin Amount for Flat Booking';
            l.htmlBody = head
                //+ P + '<b>Subject: Demand for Payment of Margin Amount for Flat Booking</b></p>'
                + P + 'Dear Sir/Madam,</p>'
                + P + 'With reference to the booking of Flat No. <b>' + flat + '</b> in the project <b>' + project + '</b> dated <b>'
                    + fmt(b == null ? null : b.Booking_Date__c) + '</b>, we wish to inform you that the required margin amount '
                    + 'towards the booking and processing of the flat is pending.</p>'
                + P + 'The payment details are as follows:</p>'
                + '<ul style="margin:0 0 10px 0;">'
                    + '<li>Flat No: <b>' + flat + '</b></li>'
                    + '<li>Project Name: <b>' + project + '</b></li>'
                    + '<li>Total Flat Cost: <b>&#8377; ' + inr(b == null ? null : b.Total_Flat_Cost__c) + '</b></li>'
                    + '<li>Margin Amount Payable: <b>&#8377; ' + inr(demand) + '</b></li>'
                    + '<li>Amount Paid: <b>&#8377; ' + inr(demand - open) + '</b></li>'
                    + '<li>Balance Amount Due: <b>&#8377; ' + inr(open) + '</b></li>'
                + '</ul>'
                + P + 'You are requested to pay the outstanding margin amount on or before <b>' + fmt(d.Due_Date__c)
                    + '</b> to enable further processing of the booking.</p>'
                + P + 'Kindly treat this matter as urgent and arrange payment at the earliest.</p>'
                + P + 'For any clarification, please contact us at <b>' + (String.isBlank(contact) ? '__________' : contact) + '</b>.</p>'
                + P + 'Thanking you.</p>'
                + signature(owner == null ? null : owner.Name);
        } else {
            l.subject = '2nd Reminder for Payment of Margin Amount';
            l.htmlBody = head
                //+ P + '<b>Subject: 2nd Reminder for Payment of Margin Amount</b></p>'
                + P + 'Dear Sir/Madam,</p>'
                + P + 'This is with reference to our earlier reminder dated <b>' + fmt(firstReminderDate(d))
                    + '</b> regarding the pending margin amount for your allotted flat bearing No. <b>' + flat
                    + '</b> in the project <b>“' + project.toUpperCase() + '”</b>.</p>'
                + P + 'As per our records, an amount of <b>&#8377; ' + pending + '</b> is still pending for payment. We request '
                    + 'you to clear the outstanding amount within <b>' + DAYS_TO_PAY + '</b> days from the date of this letter.</p>'
                + P + 'Please note that failure to make the payment within the above time may lead to further action as per the '
                    + 'terms of the Cost Sheet, including applicable charges or cancellation of allotment.</p>'
                + P + 'Kindly treat this as an urgent matter and make the payment at the earliest.</p>'
                + signature(null);
        }
        return l;
    }

    /** "To / The Allottee, / Name / Flat No. / Project / Address" */
    private static String toBlock(Booking__c b, String flat, String project) {
        String name = b == null ? '' : join(new List<String>{ esc(b.Salutation__c), esc(b.First_Applicant_Name__c) }, ' ');
        return P + 'To<br/>The Allottee,<br/><b>' + (String.isBlank(name) ? '__________' : name) + '</b><br/>'
            + 'Flat No. ' + flat + '<br/>' + project
            + (b != null && String.isNotBlank(b.Permanent_Address__c) ? '<br/>' + esc(b.Permanent_Address__c) : '')
            + '</p>';
    }

    private static String signature(String signatoryName) {
        return '<p style="margin:16px 0 0 0; line-height:1.5;">Yours faithfully,<br/>For Ananda Homes<br/><br/>'
            + (String.isBlank(signatoryName) ? '' : '<b>' + esc(signatoryName) + '</b><br/>')
            + 'Authorized Signatory</p>';
    }

    /** The 1st reminder's date: when it was sent, else when it was due. */
    private static Date firstReminderDate(Demands__c d) {
        if (d.Reminder_1_Sent_Date__c != null) {
            return d.Reminder_1_Sent_Date__c.date();
        }
        return d.Reminder_1_Date__c;
    }

    /**
     * Reminders 1 and 2 of an Additional Charge demand (AdditionalChargeDemandService, 2026-11-17):
     * reminder 1 at Demand Date + 15 days, reminder 2 seven days later.
     */
    private static Letter additionalChargeLetter(Demands__c d, Integer level, String flat, String project) {
        Additional_Charge__c ac = (Additional_Charge__c) d.getPopulatedFieldsAsMap().get('Additional_Charge__r');
        String charge = ac == null ? 'Additional Charge'
            : esc(String.isNotBlank(ac.Charge_Name__c) ? ac.Charge_Name__c : ac.Name);
        String pending = inr(d.Pending_Amount__c);
        Letter l = new Letter();
        if (level == 1) {
            l.subject = 'Reminder for Payment of Additional Charge - ' + (ac == null ? '' : ac.Name);
            l.htmlBody = P + 'Dear Sir/Madam,</p>'
                + P + 'This is to kindly remind you regarding the demand raised on <b>' + fmt(d.Demand_Date__c)
                    + '</b> towards the additional charge <b>' + charge + '</b> for your allotted unit bearing No. <b>'
                    + flat + '</b> in the project <b>' + project.toUpperCase() + '</b>.</p>'
                + P + 'As per our records, an amount of <b>&#8377; ' + pending + '</b> is still outstanding towards the said '
                    + 'charge. You are requested to make the payment within ' + DAYS_TO_PAY + ' days from the date of this '
                    + 'letter.</p>'
                + P + 'Kindly ignore this reminder if the payment has already been made.</p>'
                + P + 'Thanking you,</p>'
                + signature(null);
        } else {
            l.subject = '2nd Reminder for Payment of Additional Charge - ' + (ac == null ? '' : ac.Name);
            l.htmlBody = P + 'Dear Sir/Madam,</p>'
                + P + 'This is in continuation of our demand dated <b>' + fmt(d.Demand_Date__c)
                    + '</b> and reminder dated <b>' + fmt(reminderDate(d, 1)) + '</b> regarding the additional charge <b>'
                    + charge + '</b> for your allotted unit bearing No. <b>' + flat + '</b> in the project <b>'
                    + project.toUpperCase() + '</b>.</p>'
                + P + 'We note that the amount of <b>&#8377; ' + pending + '</b> towards the said charge remains unpaid. '
                    + 'You are requested to clear the outstanding amount at the earliest, and in any case within '
                    + DAYS_TO_PAY + ' days from the date of this letter.</p>'
                + P + 'Kindly treat this matter as urgent.</p>'
                + signature(null);
        }
        return l;
    }

    /** Reminder N's date: when it was sent, else when it was due. */
    private static Date reminderDate(Demands__c d, Integer n) {
        Map<String, Object> f = d.getPopulatedFieldsAsMap();
        Object sent = f.get('Reminder_' + n + '_Sent_Date__c');
        if (sent != null) {
            return ((DateTime) sent).date();
        }
        return (Date) f.get('Reminder_' + n + '_Date__c');
    }

    /** Interest levied on the demand less any interest waived; never negative. */
    @TestVisible
    private static Decimal netInterest(Demands__c d) {
        Decimal interest = (d.Interest_Amount__c == null ? 0 : d.Interest_Amount__c)
            - (d.Interest_Waived_Off_Amount__c == null ? 0 : d.Interest_Waived_Off_Amount__c);
        return interest < 0 ? 0 : interest;
    }

    @TestVisible
    private static String fmt(Date d) {
        return d == null ? '__________' : DateTime.newInstance(d.year(), d.month(), d.day()).format('dd/MM/yyyy');
    }

    /** 9455900 -> "94,55,900" (Indian grouping, rounded to the rupee). */
    @TestVisible
    private static String inr(Decimal value) {
        if (value == null) {
            return '0';
        }
        String digits = value.setScale(0, System.RoundingMode.HALF_UP).abs().toPlainString();
        if (digits.length() > 3) {
            String last3 = digits.substring(digits.length() - 3);
            String rest = digits.substring(0, digits.length() - 3);
            String grouped = '';
            while (rest.length() > 2) {
                grouped = ',' + rest.substring(rest.length() - 2) + grouped;
                rest = rest.substring(0, rest.length() - 2);
            }
            digits = rest + grouped + ',' + last3;
        }
        return (value < 0 ? '-' : '') + digits;
    }

    private static String join(List<String> parts, String sep) {
        List<String> kept = new List<String>();
        for (String s : parts) {
            if (String.isNotBlank(s)) {
                kept.add(s.trim());
            }
        }
        return String.join(kept, sep);
    }

    private static String esc(String value) {
        return value == null ? null : value.escapeHtml4();
    }
}