/**
 * @description Allocates the Interest Amount entered on a receipt (Receipt.Interest_Amount__c, part
 *              of its Amount Received) to the booking's unpaid delay interest (user 2026-11-26). The
 *              rest of the receipt is allocated exactly as before. Interest is paid oldest first:
 *              milestones in sequence, and on each
 *              milestone its Interest Line Items oldest first. It never touches Flat / GST / TDS:
 *              - the receipt line items have Allocation Type "Interest" and are linked to the booking
 *                only (no milestone / demand), so payment-schedule and demand recalculation, the
 *                milestone payment gate and the Prorata checks never count them as instalment money;
 *              - the milestone's Interest_Pending__c goes down and Interest_Paid__c goes up (so
 *                Interest_Calculated__c = pending + paid stays the same), the paid Interest Line Items become
 *                Status "Paid" (a partly paid line is split into a Paid part and the unpaid rest), and
 *                Booking.Total_Interest__c is recalculated.
 *              Any interest amount above the unpaid interest is returned to the caller and stays
 *              unallocated on the receipt.
 */
public without sharing class InterestPaymentService {

    public static final String ALLOCATION_TYPE = 'Interest';
    public static final String LINE_STATUS_PAID = 'Paid';
    private static final Set<String> CLOSED_LINE_STATUSES = new Set<String>{ 'Waived', 'Paid' };

    public class Result {
        public List<Receipt_Line_Item__c> lines = new List<Receipt_Line_Item__c>();
        public Decimal remaining = 0;
        public Decimal allocated = 0;
    }

    /** Unpaid interest on the booking (sum of the milestones' Interest Pending). */
    public static Decimal unpaidInterest(Id bookingId) {
        Decimal total = 0;
        for (Payment_Schedule__c ps : [
            SELECT Interest_Pending__c FROM Payment_Schedule__c
            WHERE Booking__c = :bookingId AND Interest_Pending__c > 0
        ]) {
            total += ps.Interest_Pending__c;
        }
        return total;
    }

    /**
     * @param receiptId     the approved Interest Payment receipt
     * @param bookingId     its booking
     * @param amount        money available on the receipt
     * @param firstSequence sequence number for the first receipt line item
     * @return the receipt line items to insert (not inserted here) and the amount left over
     */
    public static Result allocate(Id receiptId, Id bookingId, Decimal amount, Integer firstSequence) {
        Result result = new Result();
        result.remaining = amount == null ? 0 : amount;
        if (result.remaining <= 0 || bookingId == null) return result;

        List<Payment_Schedule__c> schedules = [
            SELECT Id, Name, Milestone_Name__c, Interest_Pending__c, Interest_Paid__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :bookingId AND Interest_Pending__c > 0
            ORDER BY Sequence__c ASC
        ];
        if (schedules.isEmpty()) return result;

        Map<Id, List<Interest_Line_Item__c>> linesBySchedule = new Map<Id, List<Interest_Line_Item__c>>();
        for (Interest_Line_Item__c ili : [
            SELECT Id, Booking__c, Payment_Schedule__c, Component__c, Amount__c, From_Date__c, To_Date__c,
                   Number_of_Days__c, Principal_Amount__c, Interest_Rate__c, Allocation_Type__c,
                   Allocation_Date__c, Description__c, Status__c
            FROM Interest_Line_Item__c
            WHERE Payment_Schedule__c IN :new Map<Id, Payment_Schedule__c>(schedules).keySet()
            AND Status__c NOT IN :CLOSED_LINE_STATUSES
            AND Amount__c > 0
            ORDER BY From_Date__c ASC NULLS FIRST, CreatedDate ASC
        ]) {
            if (!linesBySchedule.containsKey(ili.Payment_Schedule__c)) {
                linesBySchedule.put(ili.Payment_Schedule__c, new List<Interest_Line_Item__c>());
            }
            linesBySchedule.get(ili.Payment_Schedule__c).add(ili);
        }

        List<Payment_Schedule__c> schedulesToUpdate = new List<Payment_Schedule__c>();
        List<Interest_Line_Item__c> linesToUpdate = new List<Interest_Line_Item__c>();
        List<Interest_Line_Item__c> paidParts = new List<Interest_Line_Item__c>();
        Integer sequence = firstSequence;

        for (Payment_Schedule__c ps : schedules) {
            if (result.remaining <= 0) break;
            Decimal pay = Math.min(result.remaining, ps.Interest_Pending__c);
            if (pay <= 0) continue;

            Receipt_Line_Item__c line = new Receipt_Line_Item__c();
            line.Receipt__c = receiptId;
            line.Booking__c = bookingId;
            line.Sequence__c = sequence++;
            line.Allocation_Type__c = ALLOCATION_TYPE;
            line.Line_Item_Type__c = ALLOCATION_TYPE;
            line.Amount__c = pay;
            line.Allocated_Amount__c = pay;
            line.Allocated_Interest_Amount__c = pay;
            line.Base_Amount__c = 0;
            line.GST_Amount__c = 0;
            line.TDS_Amount__c = 0;
            line.Allocation_Date__c = Date.today();
            line.Description__c = 'Interest on ' + ps.Milestone_Name__c + ' (' + ps.Name + ')';
            result.lines.add(line);

            schedulesToUpdate.add(new Payment_Schedule__c(Id = ps.Id,
                Interest_Pending__c = ps.Interest_Pending__c - pay,
                Interest_Paid__c = (ps.Interest_Paid__c == null ? 0 : ps.Interest_Paid__c) + pay));

            // Mark the milestone's interest lines paid, oldest first.
            Decimal left = pay;
            for (Interest_Line_Item__c ili : linesBySchedule.containsKey(ps.Id)
                    ? linesBySchedule.get(ps.Id) : new List<Interest_Line_Item__c>()) {
                if (left <= 0) break;
                if (ili.Amount__c <= left) {
                    left -= ili.Amount__c;
                    linesToUpdate.add(new Interest_Line_Item__c(Id = ili.Id, Status__c = LINE_STATUS_PAID));
                } else {
                    Interest_Line_Item__c paidPart = ili.clone(false, true, false, false);
                    paidPart.Amount__c = left;
                    paidPart.Status__c = LINE_STATUS_PAID;
                    paidPart.Description__c = 'Paid part: ' + (ili.Description__c == null ? '' : ili.Description__c);
                    paidParts.add(paidPart);
                    linesToUpdate.add(new Interest_Line_Item__c(Id = ili.Id, Amount__c = ili.Amount__c - left));
                    left = 0;
                }
            }

            result.remaining -= pay;
            result.allocated += pay;
        }

        if (!schedulesToUpdate.isEmpty()) update schedulesToUpdate;
        if (!linesToUpdate.isEmpty()) update linesToUpdate;
        if (!paidParts.isEmpty()) insert paidParts;

        // Booking Total Interest = what is still unpaid.
        Booking__c booking = new Booking__c(Id = bookingId, Total_Interest__c = unpaidInterest(bookingId).setScale(2));
        InterestCalculationService.saveBookingTotals(new List<Booking__c>{ booking });
        return result;
    }
}