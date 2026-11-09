/**
 * @description Creates the quote (cost sheet) for a unit swap.
 *
 *              When a "Request For Swap Unit" approval is submitted on a booking, a quote is built
 *              for the Swap To Unit exactly as the Create Quote screen would build it by hand:
 *              unit details and charges copied from the unit, Standard payment type, and one cost
 *              sheet line per master payment schedule of the unit's tower. The quote points back at
 *              the booking through Quote__c.Swap_For_Booking__c and, once the swap is approved and
 *              executed, becomes the Quote__c of the new booking (see BookingSwapHandler). If the swap request is
 *              rejected the quote is rejected too, which releases the unit again (QuoteTrigger).
 */
public without sharing class SwapQuoteService {

    /** Approval configuration Process_Type__c that raises a swap request. */
    public static final String SWAP_REQUEST_PROCESS_TYPE = 'Request_For_Swap_Unit';
    /** Quote statuses that no longer hold the unit; a request with such a quote gets a new one. */
    private static final Set<String> CLOSED_QUOTE_STATUSES = new Set<String>{
        'Rejected', 'Denied by Customer', 'Converted'
    };

    public class SwapQuoteException extends Exception {}

    /**
     * @description Builds the quote for the booking's Swap To Unit and stores it on the booking.
     *              Reuses the booking's existing swap quote when it is for the same unit and still
     *              open, so a re-submitted request does not create a second cost sheet.
     * @return the quote linked to the booking
     */
    public static Id createForSwapRequest(Id bookingId) {
        if (bookingId == null) {
            throw new SwapQuoteException('Booking is required to create the swap quote.');
        }
        Booking__c booking = [
            SELECT Id, Name, Project__c, CLead__c, Swap_To_Plot__c,
                   Swap_Extra_Covered_Parking_Charges__c,
                   CLead__r.Old_Owner_Name__r.Name
            FROM Booking__c
            WHERE Id = :bookingId
            LIMIT 1
        ];
        if (booking.Swap_To_Plot__c == null) {
            throw new SwapQuoteException('Select the Swap To Unit before requesting the swap.');
        }
        Quote__c existing = findOpenSwapQuote(booking.Id, booking.Swap_To_Plot__c);
        if (existing != null) {
            return existing.Id;
        }

        Plot__c unit = loadUnit(booking.Swap_To_Plot__c);
        if (unit.Status__c != PostSalesConstants.UNIT_STATUS_AVAILABLE) {
            throw new SwapQuoteException('Unit ' + unit.Name + ' is not available (' + unit.Status__c
                + '), so a cost sheet cannot be created for the swap.');
        }

        Quote__c quote = buildQuote(booking, unit);
        insert quote;   // QuoteTrigger: approval routing, unit -> Blocked, block history

        insertCostSheetLines(quote, unit);
        return quote.Id;
    }

    /**
     * @description The open quote created for this booking's swap to the given unit, newest first;
     *              null when there is none (or it was rejected / denied / already converted).
     */
    public static Quote__c findOpenSwapQuote(Id bookingId, Id unitId) {
        if (bookingId == null || unitId == null) return null;
        List<Quote__c> quotes = [
            SELECT Id, Unit__c, Quote_status__c
            FROM Quote__c
            WHERE Swap_For_Booking__c = :bookingId AND Unit__c = :unitId
              AND Quote_status__c NOT IN :CLOSED_QUOTE_STATUSES
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return quotes.isEmpty() ? null : quotes[0];
    }

    /**
     * @description Booking trigger (after update): when a swap request is rejected, reject the swap
     *              quote too so the unit it blocked becomes available again.
     */
    public static void handleBookingUpdate(List<Booking__c> newList, Map<Id, Booking__c> oldMap) {
        if (newList == null || oldMap == null) return;
        Set<Id> rejectedBookingIds = new Set<Id>();
        for (Booking__c b : newList) {
            Booking__c old = oldMap.get(b.Id);
            if (old != null
                && b.Swapping_Approval_Before_Agreement__c == 'Rejected'
                && old.Swapping_Approval_Before_Agreement__c != 'Rejected') {
                rejectedBookingIds.add(b.Id);
            }
        }
        if (rejectedBookingIds.isEmpty()) return;
        List<Quote__c> toReject = new List<Quote__c>();
        for (Quote__c q : [
            SELECT Id FROM Quote__c
            WHERE Swap_For_Booking__c IN :rejectedBookingIds
              AND Quote_status__c NOT IN :CLOSED_QUOTE_STATUSES
        ]) {
            toReject.add(new Quote__c(Id = q.Id, Quote_status__c = 'Rejected'));
        }
        if (!toReject.isEmpty()) {
            update toReject;
        }
    }

    // ------------------------------------------------------------------ building blocks

    private static Plot__c loadUnit(Id unitId) {
        List<Plot__c> units = [
            SELECT Id, Name, Status__c, Project__c, Project__r.Project__c, Project__r.Name,
                   Plot_Number__c, Unit_Facing_Direction__c, BHK_Type__c, Plot_Type__c,
                   Block1__c, Block__c, UDS__c, Super_built_up_area__c, Carpet_Area__c, Balcony_Area__c,
                   Premium_Status__c, Common_Area_Allotted_to_Association__c, Category__c,
                   Price_Per_Sq_Ft__c, Solar_Charges__c, Floor_Rise__c, Premium_Charge__c,
                   Covered_Park_Parking__c, GST1__c, Floor__c, Saleable_Area_Sft__c,
                   East_Facing_Charges__c, Corner_Charges__c, Hi_Rise_Charges__c,
                   Central_Court_Yard_Premium__c, Meadow_Premium__c, Roadside_Premium__c,
                   Court_Yard_Premium__c, Outer_Premium__c, Amenities_Car_Parking__c,
                   Infrastructure_Charges__c, Miscellaneous_Charges__c, Lake_Premium__c,
                   East_North_Facing__c, Piped_Gas__c, PLC__c
            FROM Plot__c
            WHERE Id = :unitId
            LIMIT 1
        ];
        if (units.isEmpty()) {
            throw new SwapQuoteException('The Swap To Unit could not be found.');
        }
        return units[0];
    }

    /** Same field mapping as the Create Quote screen when a unit is picked (no discounts). */
    @TestVisible
    private static Quote__c buildQuote(Booking__c booking, Plot__c unit) {
        Quote__c q = new Quote__c();
        q.Swap_For_Booking__c = booking.Id;
        q.CLead__c = booking.CLead__c;
        q.Unit__c = unit.Id;
        q.Project__c = unit.Project__r.Project__c;
        q.Project1__c = unit.Project__c;
        q.Quote_Date__c = Date.today();
        q.Flat_Number__c = unit.Plot_Number__c;
        q.Facing__c = unit.Unit_Facing_Direction__c;
        q.BHK_Type__c = unit.BHK_Type__c;
        q.Unit_Type__c = unit.Plot_Type__c;
        q.Tower_Lookup__c = unit.Block1__c;
        q.UDS_Area__c = unit.UDS__c;
        q.Super_Built_UpArea__c = unit.Super_built_up_area__c;
        q.Carpet_Area__c = unit.Carpet_Area__c;
        q.Balcony_Area__c = unit.Balcony_Area__c;
        q.Premium_Status__c = unit.Premium_Status__c;
        q.Common_Area_Allotted_to_Association__c = unit.Common_Area_Allotted_to_Association__c;
        q.Category__c = unit.Category__c;
        q.Price_Per_Sq_Ft__c = unit.Price_Per_Sq_Ft__c;
        q.Solar_Charges__c = unit.Solar_Charges__c;
        q.Floor_Rise__c = unit.Floor_Rise__c;
        q.Premium_Charge__c = unit.Premium_Charge__c;
        q.Covered_Park_Parking__c = unit.Covered_Park_Parking__c;
        q.Extra_Covered_Car_Parking_Charges__c = booking.Swap_Extra_Covered_Parking_Charges__c != null
            ? booking.Swap_Extra_Covered_Parking_Charges__c : 0;
        q.GST1__c = unit.GST1__c;
        q.Floor__c = unit.Floor__c;
        q.Saleable_Area_Sft__c = unit.Saleable_Area_Sft__c;
        q.East_Facing_Charges__c = unit.East_Facing_Charges__c;
        q.Corner_Charges__c = unit.Corner_Charges__c;
        q.Hi_Rise_Charges__c = unit.Hi_Rise_Charges__c;
        q.Central_Court_Yard_Premium__c = unit.Central_Court_Yard_Premium__c;
        q.Meadow_Premium__c = unit.Meadow_Premium__c;
        q.Roadside_Premium__c = unit.Roadside_Premium__c;
        q.Court_Yard_Premium__c = unit.Court_Yard_Premium__c;
        q.Outer_Premium__c = unit.Outer_Premium__c;
        q.Amenities_Car_Parking__c = unit.Amenities_Car_Parking__c;
        q.Infrastructure_Charges__c = unit.Infrastructure_Charges__c;
        q.Miscellaneous_Charges__c = unit.Miscellaneous_Charges__c;
        q.Lake_Premium__c = unit.Lake_Premium__c;
        q.East_North_Facing__c = unit.East_North_Facing__c;
        q.Piped_Gas__c = unit.Piped_Gas__c;
        q.PLC__c = unit.PLC__c;
        q.Apply_Discount__c = false;
        q.Additional_Car_Parking_Required__c = false;
        q.Payment_Type__c = 'Standard';
        q.Pre_Sale_User_Name__c = booking.CLead__r == null || booking.CLead__r.Old_Owner_Name__r == null
            ? null : booking.CLead__r.Old_Owner_Name__r.Name;
        return q;
    }

    /**
     * Standard payment plan: one cost sheet line per master payment schedule of the unit's tower,
     * amounts as a share of the quote total (same as CreateQuoteController.getPaymentSchedules).
     */
    private static void insertCostSheetLines(Quote__c inserted, Plot__c unit) {
        Quote__c quote = [SELECT Id, Total__c, Project__c FROM Quote__c WHERE Id = :inserted.Id];
        Decimal total = quote.Total__c == null ? 0 : quote.Total__c;
        List<Master_Payment_Schedule__c> masters = [
            SELECT Id, Name, S_No__c, Sequence__c, Payment_Percent__c, Tentative_TimeLine__c,
                   Status__c, Due_Date__c
            FROM Master_Payment_Schedule__c
            WHERE Project__c = :unit.Project__c AND Tower__c = :unit.Block1__c
            ORDER BY S_No__c ASC, Sequence__c ASC
        ];
        if (masters.isEmpty()) {
            return; // the unit's tower has no payment plan yet; the quote stands without lines
        }
        List<Cost_Sheet_Line_Item__c> lines = new List<Cost_Sheet_Line_Item__c>();
        for (Master_Payment_Schedule__c ms : masters) {
            Decimal pct = ms.Payment_Percent__c == null ? 0 : ms.Payment_Percent__c;
            lines.add(new Cost_Sheet_Line_Item__c(
                Quote__c = quote.Id,
                Master_Payment_Schedule__c = ms.Id,
                Payment_Schedule_Name__c = ms.Name,
                Payment_percent__c = pct,
                S_No__c = ms.S_No__c != null ? ms.S_No__c : ms.Sequence__c,
                Amount__c = (total * pct / 100).setScale(2),
                Tentative_TimeLine__c = ms.Tentative_TimeLine__c,
                status__c = normalizeLineItemStatus(ms.Status__c),
                Payment_Due_Date__c = ms.Due_Date__c
            ));
        }
        insert lines;
    }

    /** Mirrors CreateQuoteController.normalizeLineItemStatus (restricted picklist on the line). */
    private static String normalizeLineItemStatus(String s) {
        if (s == 'Scheduled' || s == 'Demanded' || s == 'Paid' || s == 'Completed') return s;
        if (s == 'In Progress') return 'Demanded';
        return 'Scheduled';
    }
}
