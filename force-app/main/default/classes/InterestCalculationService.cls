/**
 * @description Invocable Apex service for calculating interest on overdue Payment Schedules.
 *              Uses the Project's Interest_Rate__c (annual %) to compute simple interest:
 *              Interest = Principal × (Rate / 365) × Days Overdue
 *              Calculated separately on the Flat pending and the GST pending of each milestone ticked
 *              Include Interest (never on TDS), each from the due date of the demand that raised that
 *              part (Legacey raises Flat and GST separately). Stops when the milestone is Paid /
 *              Waived or nothing is pending.
 *              Creates Interest_Line_Item__c records with full history and updates
 *              Payment_Schedule__c.Interest_Pending__c for each overdue schedule.
 * @author System
 * @date 2026-03-15
 */
public with sharing class InterestCalculationService {

    /**
     * @description Flow input wrapper
     */
    public class FlowInput {
        @InvocableVariable(required=true label='Booking Id')
        public Id bookingId;

        @InvocableVariable(required=false label='Calculation Date')
        public Date calculationDate;
    }

    /**
     * @description Flow output wrapper
     */
    public class FlowOutput {
        @InvocableVariable(label='Total Interest Calculated')
        public Decimal totalInterest;

        @InvocableVariable(label='Number of Schedules with Interest')
        public Integer schedulesWithInterest;
    }

    /**
     * @description Main entry point called from Flows.
     *              Calculates interest for all overdue payment schedules of a Booking.
     */
    @InvocableMethod(label='Calculate Interest for Booking' description='Calculates interest on overdue payment schedules using Project interest rate, creates Interest Line Items, and updates Payment Schedule interest fields' category='Financial')
    public static List<FlowOutput> calculateInterest(List<FlowInput> inputs) {
        List<FlowOutput> outputs = new List<FlowOutput>();

        for (FlowInput input : inputs) {
            FlowOutput output = new FlowOutput();
            output.totalInterest = 0;
            output.schedulesWithInterest = 0;

            if (input.bookingId != null) {
                output = calculateForBooking(input.bookingId, input.calculationDate);
            }

            outputs.add(output);
        }

        return outputs;
    }

    /**
     * @description Interest for a single Booking (Flow entry point / ad-hoc runs).
     */
    public static FlowOutput calculateForBooking(Id bookingId, Date calcDate) {
        FlowOutput output = calculateForBookings(new Set<Id>{ bookingId }, calcDate).get(bookingId);
        return output != null ? output : emptyOutput();
    }

    /**
     * @description Core interest calculation for a set of Bookings - 4 queries and at most 3 saves
     *              however many bookings (the daily batch passes a whole chunk).
     *              1. Project interest rate, Do Not Calculate Interest / Resume Date per booking
     *              2. Milestones ticked Include Interest, not Paid / Waived, with Flat or GST pending
     *              3. Flat and GST each start from the due date of the demand that raised them
     *              4. Principal x (Annual Rate / 365) x Days, one Interest_Line_Item__c per part
     *              5. Payment_Schedule__c.Interest_Pending__c and Booking__c.Total_Interest__c updated
     */
    public static Map<Id, FlowOutput> calculateForBookings(Set<Id> bookingIds, Date calcDate) {
        Map<Id, FlowOutput> outputs = new Map<Id, FlowOutput>();
        if (bookingIds == null || bookingIds.isEmpty()) return outputs;
        if (calcDate == null) calcDate = Date.today();

        // Step 1 + 2: bookings with all their milestones (all of them feed the booking total).
        Map<Id, Decimal> rateByBooking = new Map<Id, Decimal>();
        Map<Id, Date> resumeByBooking = new Map<Id, Date>();
        Map<Id, Payment_Schedule__c> candidates = new Map<Id, Payment_Schedule__c>();
        List<Booking__c> bookings = [
            SELECT Id, Name, Project__r.Interest_Rate__c, Total_Interest__c,
                   Do_Not_Calculate_Interest__c, Interest_Calculation_Resume_Date__c,
                   (SELECT Id, Name, Booking__c, Interest_Pending__c, Include_Interest__c,
                           Payment_Schedule_Amount_Pending__c, GST_Amount_Pending__c,
                           Milestone_Name__c, Sequence__c, Status__c
                    FROM Payment_Schedules__r ORDER BY Sequence__c ASC)
            FROM Booking__c
            WHERE Id IN :bookingIds
            AND Status__c != 'Cancellation' AND Status__c != 'Swapping'
        ];
        for (Booking__c booking : bookings) {
            outputs.put(booking.Id, emptyOutput());
            Decimal annualRate = booking.Project__r == null ? null : booking.Project__r.Interest_Rate__c;
            if (annualRate == null || annualRate <= 0) continue;

            // "Do Not Calculate Interest": no interest, unless an Interest Calculation Resume Date
            // is set and reached - then interest restarts from that date (paused days never charged).
            if (booking.Do_Not_Calculate_Interest__c == true) {
                if (booking.Interest_Calculation_Resume_Date__c == null
                    || booking.Interest_Calculation_Resume_Date__c > calcDate) {
                    continue;
                }
                resumeByBooking.put(booking.Id, booking.Interest_Calculation_Resume_Date__c);
            }
            rateByBooking.put(booking.Id, annualRate);

            // "Completed" only means the construction milestone was reached - it does NOT stop interest.
            for (Payment_Schedule__c ps : booking.Payment_Schedules__r) {
                if (ps.Include_Interest__c == true
                    && !INTEREST_STOP_STATUSES.contains(ps.Status__c)
                    && (nz(ps.Payment_Schedule_Amount_Pending__c) > 0 || nz(ps.GST_Amount_Pending__c) > 0)) {
                    candidates.put(ps.Id, ps);
                }
            }
        }

        List<Interest_Line_Item__c> lineItemsToInsert = new List<Interest_Line_Item__c>();
        Map<Id, Payment_Schedule__c> schedulesToUpdate = new Map<Id, Payment_Schedule__c>();

        if (!candidates.isEmpty()) {
            // Step 3: when each part became payable = earliest due date of a (not cancelled) demand
            // raised for it. Legacey raises Flat and GST separately, so each has its own start date;
            // a "Flat + GST" demand starts both. No demand raised = no interest.
            Map<String, Date> startDates = demandStartDates(candidates.keySet());

            // Last calculated date per milestone and part. Lines from before the split (no
            // Component) covered the whole milestone, so they count for both parts.
            Map<String, Date> lastCalc = new Map<String, Date>();
            for (AggregateResult ar : [
                SELECT Payment_Schedule__c psId, Component__c comp, MAX(To_Date__c) lastDate
                FROM Interest_Line_Item__c
                WHERE Payment_Schedule__c IN :candidates.keySet()
                AND Status__c != 'Waived'
                GROUP BY Payment_Schedule__c, Component__c
            ]) {
                Id psId = (Id) ar.get('psId');
                String comp = (String) ar.get('comp');
                Date lastDate = (Date) ar.get('lastDate');
                for (String part : PARTS) {
                    if (comp != null && comp != part) continue;
                    String key = psId + '|' + part;
                    if (lastDate != null && (!lastCalc.containsKey(key) || lastDate > lastCalc.get(key))) {
                        lastCalc.put(key, lastDate);
                    }
                }
            }

            // Step 4: interest per part
            for (Payment_Schedule__c ps : candidates.values()) {
                Decimal annualRate = rateByBooking.get(ps.Booking__c);
                Date resumeDate = resumeByBooking.get(ps.Booking__c);
                FlowOutput output = outputs.get(ps.Booking__c);
                Decimal dailyRate = annualRate / 365;
                Boolean counted = false;
                for (String part : PARTS) {
                    Decimal principal = part == PART_FLAT
                        ? nz(ps.Payment_Schedule_Amount_Pending__c) : nz(ps.GST_Amount_Pending__c);
                    if (principal <= 0) continue;

                    Date fromDate = startDates.get(ps.Id + '|' + part);
                    if (fromDate == null) continue; // that part has not been demanded yet
                    Date last = lastCalc.get(ps.Id + '|' + part);
                    if (last != null && last >= fromDate) fromDate = last.addDays(1);
                    if (resumeDate != null && fromDate < resumeDate) fromDate = resumeDate;
                    if (fromDate >= calcDate) continue;

                    Integer daysOverdue = fromDate.daysBetween(calcDate);
                    if (daysOverdue <= 0) continue;

                    Decimal interestAmount = (principal * dailyRate * daysOverdue / 100).setScale(2, System.RoundingMode.HALF_UP);
                    if (interestAmount <= 0) continue;

                    Interest_Line_Item__c ili = new Interest_Line_Item__c();
                    ili.Booking__c = ps.Booking__c;
                    ili.Payment_Schedule__c = ps.Id;
                    ili.Component__c = part;
                    ili.From_Date__c = fromDate;
                    ili.To_Date__c = calcDate;
                    ili.Number_of_Days__c = daysOverdue;
                    ili.Principal_Amount__c = principal;
                    ili.Interest_Rate__c = annualRate / 100; // Store as decimal for Percent field
                    ili.Amount__c = interestAmount;
                    ili.Allocation_Type__c = 'Interest';
                    ili.Allocation_Date__c = calcDate;
                    ili.Status__c = 'Calculated';
                    ili.Description__c = 'Interest on ' + part + ' pending of ' + ps.Milestone_Name__c +
                        ' (' + ps.Name + ') for ' + daysOverdue + ' days @ ' +
                        String.valueOf(annualRate) + '% p.a.';
                    lineItemsToInsert.add(ili);

                    ps.Interest_Pending__c = nz(ps.Interest_Pending__c) + interestAmount;
                    ps.Interest_Applicable__c = true;
                    schedulesToUpdate.put(ps.Id, ps);

                    output.totalInterest += interestAmount;
                    counted = true;
                }
                if (counted) output.schedulesWithInterest++;
            }
        }

        if (!lineItemsToInsert.isEmpty()) {
            insert lineItemsToInsert;
        }
        if (!schedulesToUpdate.isEmpty()) {
            update schedulesToUpdate.values();
        }

        // Step 5: Booking Total Interest = sum of Interest Pending on all its milestones.
        List<Booking__c> totals = new List<Booking__c>();
        for (Booking__c booking : bookings) {
            Booking__c upd = bookingTotal(booking, booking.Payment_Schedules__r);
            if (upd != null) totals.add(upd);
        }
        saveBookingTotals(totals);
        return outputs;
    }

    private static FlowOutput emptyOutput() {
        FlowOutput output = new FlowOutput();
        output.totalInterest = 0;
        output.schedulesWithInterest = 0;
        return output;
    }

    public static final String PART_FLAT = 'Flat';
    public static final String PART_GST = 'GST';
    private static final List<String> PARTS = new List<String>{ PART_FLAT, PART_GST };

    /** Milestone statuses that stop interest ("Completed" = construction milestone reached, not paid). */
    public static final Set<String> INTEREST_STOP_STATUSES = new Set<String>{
        PostSalesConstants.SCHEDULE_STATUS_PAID, PostSalesConstants.SCHEDULE_STATUS_WAIVED
    };

    private static final String DEMAND_CANCELLED = 'Cancelled';

    /**
     * Earliest due date of a non-cancelled demand per milestone and part ("<scheduleId>|Flat" /
     * "<scheduleId>|GST"), from demand lines and from demands linked straight to the milestone.
     */
    @TestVisible
    private static Map<String, Date> demandStartDates(Set<Id> scheduleIds) {
        Map<String, Date> starts = new Map<String, Date>();
        for (Demand_Line__c line : [
            SELECT Payment_Schedule__c, Demand_Component__c, Demand__r.Demand_Component__c,
                   Demand__r.Due_Date__c, Demand__r.Status__c
            FROM Demand_Line__c
            WHERE Payment_Schedule__c IN :scheduleIds AND Demand__c != null
        ]) {
            if (line.Demand__r.Status__c == DEMAND_CANCELLED) continue;
            String component = String.isNotBlank(line.Demand_Component__c)
                ? line.Demand_Component__c : line.Demand__r.Demand_Component__c;
            addStart(starts, line.Payment_Schedule__c, component, line.Demand__r.Due_Date__c);
        }
        for (Demands__c d : [
            SELECT Payment_Schedule__c, Demand_Component__c, Due_Date__c, Status__c
            FROM Demands__c
            WHERE Payment_Schedule__c IN :scheduleIds
        ]) {
            if (d.Status__c == DEMAND_CANCELLED) continue;
            addStart(starts, d.Payment_Schedule__c, d.Demand_Component__c, d.Due_Date__c);
        }
        return starts;
    }

    private static void addStart(Map<String, Date> starts, Id scheduleId, String component, Date dueDate) {
        if (scheduleId == null || dueDate == null) return;
        // A demand with no component (older demands) covered the whole milestone.
        Boolean flat = String.isBlank(component) || component == DemandComponentService.FLAT
            || component == DemandComponentService.FLAT_AND_GST;
        Boolean gst = String.isBlank(component) || component == DemandComponentService.GST
            || component == DemandComponentService.FLAT_AND_GST;
        if (flat) keepEarliest(starts, scheduleId + '|' + PART_FLAT, dueDate);
        if (gst) keepEarliest(starts, scheduleId + '|' + PART_GST, dueDate);
    }

    private static void keepEarliest(Map<String, Date> values, String key, Date value) {
        if (!values.containsKey(key) || value < values.get(key)) values.put(key, value);
    }

    private static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }

    /** Booking update carrying the new Total Interest, or null when it has not changed. */
    @TestVisible
    private static Booking__c bookingTotal(Booking__c booking, List<Payment_Schedule__c> schedules) {
        Decimal total = 0;
        for (Payment_Schedule__c ps : schedules) {
            if (ps.Interest_Pending__c != null) total += ps.Interest_Pending__c;
        }
        total = total.setScale(2, System.RoundingMode.HALF_UP);
        if (booking.Total_Interest__c == total) return null;
        return new Booking__c(Id = booking.Id, Total_Interest__c = total);
    }

    /**
     * Saves booking totals as a system update: a booking lock (swapped / cancelled) or a booking
     * validation rule must not stop the interest job. Failures are logged, never thrown.
     */
    public static void saveBookingTotals(List<Booking__c> totals) {
        if (totals == null || totals.isEmpty()) return;
        Boolean priorSwap = BookingSwapLockService.bypass;
        Boolean priorCancel = BookingCancellationLockService.bypass;
        BookingSwapLockService.bypass = true;
        BookingCancellationLockService.bypass = true;
        try {
            for (Database.SaveResult sr : Database.update(totals, false)) {
                if (!sr.isSuccess()) {
                    System.debug(LoggingLevel.WARN, 'Total Interest not saved on ' + sr.getId() + ': ' + sr.getErrors());
                }
            }
        } finally {
            BookingSwapLockService.bypass = priorSwap;
            BookingCancellationLockService.bypass = priorCancel;
        }
    }
}