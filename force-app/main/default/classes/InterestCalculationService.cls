/**
 * @description Invocable Apex service for calculating interest on overdue Payment Schedules.
 *              Uses the Project's Interest_Rate__c (annual %) to compute simple interest:
 *              Interest = Principal × (Rate / 365) × Days Overdue
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
     * @description Core interest calculation logic for a single Booking.
     *              1. Gets Project's Interest Rate
     *              2. Finds overdue Payment Schedules (past due date with pending amount)
     *              3. For each, calculates: Principal × (Annual Rate / 365) × Days Overdue
     *              4. Creates Interest_Line_Item__c records (history)
     *              5. Updates Payment_Schedule__c.Interest_Pending__c
     */
    public static FlowOutput calculateForBooking(Id bookingId, Date calcDate) {
        FlowOutput output = new FlowOutput();
        output.totalInterest = 0;
        output.schedulesWithInterest = 0;

        if (calcDate == null) {
            calcDate = Date.today();
        }

        // Step 1: Get Booking and Project Interest Rate
        List<Booking__c> bookings = [
            SELECT Id, Name, Project__c, Project__r.Interest_Rate__c, Total_Interest__c,
                   Do_Not_Calculate_Interest__c, Interest_Calculation_Resume_Date__c
            FROM Booking__c
            WHERE Id = :bookingId
            AND Status__c != 'Cancellation' and Status__c != 'Swapping'
            LIMIT 1
        ];

        if (bookings.isEmpty()) return output;

        Booking__c booking = bookings[0];
        Decimal annualRate = booking.Project__r.Interest_Rate__c;

        if (annualRate == null || annualRate <= 0) return output;

        // "Do Not Calculate Interest" on the booking: no interest at all, unless an Interest
        // Calculation Resume Date is set and reached - then interest restarts from that date
        // (the paused days are never charged).
        Date resumeDate = null;
        if (booking.Do_Not_Calculate_Interest__c == true) {
            if (booking.Interest_Calculation_Resume_Date__c == null
                || booking.Interest_Calculation_Resume_Date__c > calcDate) {
                return output;
            }
            resumeDate = booking.Interest_Calculation_Resume_Date__c;
        }

        // Step 2: All the booking's schedules (for the booking total); interest is calculated only
        // on overdue ones with a pending amount that are ticked Include Interest (the milestones
        // below the Agreement milestone - see PaymentScheduleMasterDefaults).
        List<Payment_Schedule__c> allSchedules = [
            SELECT Id, Name, Booking__c, Due_Date__c, Pending_Amount__c,
                   Amount__c, Amount_Paid__c, Interest_Pending__c, Include_Interest__c,
                   Milestone_Name__c, Sequence__c, Status__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :bookingId
            ORDER BY Sequence__c ASC
        ];
        List<Payment_Schedule__c> overdueSchedules = new List<Payment_Schedule__c>();
        for (Payment_Schedule__c ps : allSchedules) {
            if (ps.Include_Interest__c == true
                && ps.Due_Date__c != null && ps.Due_Date__c < calcDate
                && ps.Pending_Amount__c != null && ps.Pending_Amount__c > 0
                && !PostSalesConstants.SCHEDULE_CLOSED_STATUSES.contains(ps.Status__c)) {
                overdueSchedules.add(ps);
            }
        }

        if (overdueSchedules.isEmpty()) {
            storeBookingTotal(booking, allSchedules);
            return output;
        }

        // Step 3: Get existing interest line items to avoid duplicate calculations
        Set<Id> scheduleIds = new Set<Id>();
        for (Payment_Schedule__c ps : overdueSchedules) {
            scheduleIds.add(ps.Id);
        }

        // Find the last calculation date per schedule
        Map<Id, Date> lastCalcDateBySchedule = new Map<Id, Date>();
        for (AggregateResult ar : [
            SELECT Payment_Schedule__c psId, MAX(To_Date__c) lastDate
            FROM Interest_Line_Item__c
            WHERE Payment_Schedule__c IN :scheduleIds
            AND Booking__c = :bookingId
            AND Status__c != 'Waived'
            GROUP BY Payment_Schedule__c
        ]) {
            Id psId = (Id) ar.get('psId');
            Date lastDate = (Date) ar.get('lastDate');
            lastCalcDateBySchedule.put(psId, lastDate);
        }

        // Step 4: Calculate interest and create line items
        List<Interest_Line_Item__c> lineItemsToInsert = new List<Interest_Line_Item__c>();
        List<Payment_Schedule__c> schedulesToUpdate = new List<Payment_Schedule__c>();

        Decimal dailyRate = annualRate / 365;

        for (Payment_Schedule__c ps : overdueSchedules) {
            // Determine the "from" date: either last calculation date or due date
            Date fromDate = ps.Due_Date__c;
            if (lastCalcDateBySchedule.containsKey(ps.Id)) {
                Date lastCalc = lastCalcDateBySchedule.get(ps.Id);
                if (lastCalc != null && lastCalc >= fromDate) {
                    fromDate = lastCalc.addDays(1);
                }
            }
            // Paused booking that has resumed: nothing is charged for the paused days.
            if (resumeDate != null && fromDate < resumeDate) {
                fromDate = resumeDate;
            }

            // Skip if already calculated up to today
            if (fromDate >= calcDate) continue;

            Integer daysOverdue = fromDate.daysBetween(calcDate);
            if (daysOverdue <= 0) continue;

            Decimal principal = ps.Pending_Amount__c;
            Decimal interestAmount = (principal * dailyRate * daysOverdue / 100).setScale(2, System.RoundingMode.HALF_UP);

            if (interestAmount <= 0) continue;

            // Create Interest Line Item (history record)
            Interest_Line_Item__c ili = new Interest_Line_Item__c();
            ili.Booking__c = bookingId;
            ili.Payment_Schedule__c = ps.Id;
            ili.From_Date__c = fromDate;
            ili.To_Date__c = calcDate;
            ili.Number_of_Days__c = daysOverdue;
            ili.Principal_Amount__c = principal;
            ili.Interest_Rate__c = annualRate / 100; // Store as decimal for Percent field
            ili.Amount__c = interestAmount;
            ili.Allocation_Type__c = 'Interest';
            ili.Allocation_Date__c = calcDate;
            ili.Status__c = 'Calculated';
            ili.Description__c = 'Interest on ' + ps.Milestone_Name__c +
                ' (' + ps.Name + ') for ' + daysOverdue + ' days @ ' +
                String.valueOf(annualRate) + '% p.a.';

            lineItemsToInsert.add(ili);

            // Update Interest_Pending on Payment Schedule
            Decimal existingInterest = ps.Interest_Pending__c != null ? ps.Interest_Pending__c : 0;
            ps.Interest_Pending__c = existingInterest + interestAmount;
            ps.Interest_Applicable__c = true;
            schedulesToUpdate.add(ps);

            output.totalInterest += interestAmount;
            output.schedulesWithInterest++;
        }

        // Insert Interest Line Items
        if (!lineItemsToInsert.isEmpty()) {
            insert lineItemsToInsert;
        }

        // Update Payment Schedules
        if (!schedulesToUpdate.isEmpty()) {
            update schedulesToUpdate;
        }

        storeBookingTotal(booking, allSchedules);
        return output;
    }

    /**
     * When true (set by InterestCalculationBatch) booking totals are collected in
     * {@code pendingBookingTotals} and saved once per batch chunk instead of one update per booking.
     */
    public static Boolean collectBookingTotals = false;
    public static Map<Id, Booking__c> pendingBookingTotals = new Map<Id, Booking__c>();

    /** Booking.Total_Interest__c = sum of Interest Pending on all the booking's payment schedules. */
    @TestVisible
    private static void storeBookingTotal(Booking__c booking, List<Payment_Schedule__c> schedules) {
        Decimal total = 0;
        for (Payment_Schedule__c ps : schedules) {
            if (ps.Interest_Pending__c != null) total += ps.Interest_Pending__c;
        }
        total = total.setScale(2, System.RoundingMode.HALF_UP);
        if (booking.Total_Interest__c == total) return;
        Booking__c upd = new Booking__c(Id = booking.Id, Total_Interest__c = total);
        if (collectBookingTotals) {
            pendingBookingTotals.put(upd.Id, upd);
        } else {
            saveBookingTotals(new List<Booking__c>{ upd });
        }
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