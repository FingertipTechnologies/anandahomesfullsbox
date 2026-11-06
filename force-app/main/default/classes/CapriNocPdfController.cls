/**
 * Supplies NOC and booking data to the three CAPRI Visualforce PDFs:
 *   CAPRI_NOC_FORMAT_LOAN      - the NOC request for the current unit
 *   CAPRI_NOC_FORMAT_SWAP      - one letter per selected Swap History
 *   CAPRI_CANCELLATION_LETTER  - one letter per selected cancelled Booking
 *
 * A NOC can carry several swaps / cancellations (NOC__c.Related_Swap_History_Ids__c and
 * Related_Cancellation_Booking_Ids__c). The swap and cancellation pages take the optional
 * page parameter "relatedId" to say which one to print; without it they print the first
 * selection (the lookup on the NOC).
 */
public with sharing class CapriNocPdfController {
    public static final String RELATED_ID_PARAM = 'relatedId';

    public NOC__c noc { get; private set; }
    public Booking__c booking { get; private set; }
    public Booking__c cancellationBooking { get; private set; }
    public Swap_History__c swapHistory { get; private set; }
    public List<Receipt_Line_Item__c> receiptLineItems { get; private set; }
    public List<Receipt_Line_Item__c> cancellationReceiptLineItems { get; private set; }
    public List<Refund__c> refunds { get; private set; }
    public Decimal totalReceived { get; private set; }
    public Decimal balanceReceivable { get; private set; }
    public Decimal cancellationTotalReceived { get; private set; }
    public Decimal cancellationTotalRefunded { get; private set; }
    public String errorMessage { get; private set; }

    // ---- current booking (the unit the NOC is raised for)
    public String buyerNames { get; private set; }
    public String buyerMobile { get; private set; }
    public String bankName { get; private set; }
    public String rateText { get; private set; }
    public String amenitiesText { get; private set; }
    public String considerationText { get; private set; }
    public String totalReceivedText { get; private set; }
    public String balanceText { get; private set; }

    // ---- cancellation letter
    public String cancellationBuyerNames { get; private set; }
    public Date cancellationRequestDate { get; private set; }
    public String cancellationReceivedText { get; private set; }
    public ReceiptSummary cancellationReceipts { get; private set; }
    public Boolean hasRefunds { get; private set; }
    public Date lastRefundDate { get; private set; }
    public String refundReferences { get; private set; }
    public String refundDates { get; private set; }

    // ---- swap letter
    public String swapCustomerNames { get; private set; }
    public ReceiptSummary swapReceipts { get; private set; }
    public Boolean showSwapNote { get; private set; }
    public Boolean hasSwap { get { return swapHistory != null; } }
    public Boolean hasCancellation { get { return cancellationBooking != null; } }

    /** Receipts of one booking, flattened to the phrases the letters use. */
    public class ReceiptSummary {
        public Decimal total { get; private set; }
        public String totalText { get; private set; }
        public String modes { get; private set; }
        public String references { get; private set; }
        public String dates { get; private set; }
        public Boolean hasReceipts { get; private set; }

        public ReceiptSummary(List<Receipt_Line_Item__c> lineItems) {
            total = 0;
            List<String> modeList = new List<String>();
            List<String> refList = new List<String>();
            List<String> dateList = new List<String>();
            for (Receipt_Line_Item__c lineItem : lineItems) {
                total += lineItem.Received_Amount__c == null ? 0 : lineItem.Received_Amount__c;
                addUnique(modeList, lineItem.Mode_of_Payment__c);
                addUnique(refList, lineItem.Cheque_no_Transaction_Number__c);
                Date receiptDate = lineItem.Receipt__r == null ? null : lineItem.Receipt__r.Receipt_Date__c;
                addUnique(dateList, formatDate(receiptDate == null ? lineItem.Cheque_Date__c : receiptDate));
            }
            hasReceipts = !lineItems.isEmpty();
            totalText = formatIndian(total);
            modes = String.join(modeList, ' / ');
            references = String.join(refList, ', ');
            dates = String.join(dateList, '; ');
        }
    }

    public CapriNocPdfController(ApexPages.StandardController standardController) {
        Id nocId = standardController == null ? null : standardController.getId();
        if (nocId == null) {
            errorMessage = 'A NOC record ID is required to generate this document.';
            return;
        }

        List<NOC__c> records = [
            SELECT Id, Name, Booking__c, Related_Cancellation_Booking__c, Related_Swap_History__c,
                   Related_Cancellation_Booking_Ids__c, Related_Swap_History_Ids__c,
                   Booking__r.Id, Booking__r.Name, Booking__r.First_Applicant_Name__c,
                   Booking__r.Second_Applicant_Name__c, Booking__r.Co_Applicant_Name__c,
                   Booking__r.Mobile_Primary__c, Booking__r.Plot__c,
                   Booking__r.Permanent_Address__c, Booking__r.Booking_Date__c,
                   Booking__r.Rate_Per_Sqft__c, Booking__r.Total_Flat_Cost__c,
                   Booking__r.Cancellation_Date__c, Booking__r.Cancellation_Reason__c,
                   Booking__r.Total_Refunded_Amount__c,
                   Booking__r.Bank_Name__c, Booking__r.Loan_Bank_Name__c, Booking__r.Bank_Branch__c,
                   Booking__r.Banker_Contact_Person__c, Booking__r.Banker_Contact_Number__c,
                   Booking__r.Project__r.Name, Booking__r.Project__r.Project_Address__c,
                   Booking__r.Project__r.Project_description__c,
                   Booking__r.Plot__r.Name, Booking__r.Plot__r.Saleable_Area_Sft__c,
                   Booking__r.Plot__r.Block1__r.Name, Booking__r.Plot__r.Tower_Block__c,
                   Booking__r.Cost_Sheet__r.Amenities_Charges__c
            FROM NOC__c
            WHERE Id = :nocId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (records.isEmpty()) {
            errorMessage = 'The requested NOC record could not be found.';
            return;
        }

        noc = records[0];
        booking = noc.Booking__r;
        receiptLineItems = new List<Receipt_Line_Item__c>();
        cancellationReceiptLineItems = new List<Receipt_Line_Item__c>();
        refunds = new List<Refund__c>();
        totalReceived = 0;
        balanceReceivable = 0;
        cancellationTotalReceived = 0;
        cancellationTotalRefunded = 0;
        hasRefunds = false;
        showSwapNote = false;
        cancellationReceipts = new ReceiptSummary(new List<Receipt_Line_Item__c>());
        swapReceipts = new ReceiptSummary(new List<Receipt_Line_Item__c>());

        // Which swap / cancellation to print: the page parameter when it is one of this NOC's
        // selections, otherwise the first selection.
        Id requestedId = requestedRelatedId();
        Id cancellationId = pick(requestedId, selectedCancellationIds(noc));
        Id swapId = pick(requestedId, selectedSwapIds(noc));

        if (cancellationId != null) {
            loadCancellation(cancellationId);
        }
        if (swapId != null) {
            loadSwap(swapId);
        }

        if (booking == null) {
            errorMessage = 'The NOC is not linked to a booking.';
            return;
        }

        buyerNames = joinNames(booking);
        buyerMobile = booking.Mobile_Primary__c;
        bankName = String.isNotBlank(booking.Loan_Bank_Name__c) ? booking.Loan_Bank_Name__c : booking.Bank_Name__c;

        receiptLineItems = receiptsFor(new Set<Id>{ booking.Id });
        for (Receipt_Line_Item__c lineItem : receiptLineItems) {
            totalReceived += lineItem.Received_Amount__c == null ? 0 : lineItem.Received_Amount__c;
        }

        Decimal consideration = booking.Total_Flat_Cost__c == null ? 0 : booking.Total_Flat_Cost__c;
        balanceReceivable = Math.max(0, consideration - totalReceived);

        rateText = formatIndian(booking.Rate_Per_Sqft__c);
        amenitiesText = formatIndian(booking.Cost_Sheet__r == null ? null : booking.Cost_Sheet__r.Amenities_Charges__c);
        considerationText = formatIndian(booking.Total_Flat_Cost__c);
        totalReceivedText = formatIndian(totalReceived);
        balanceText = formatIndian(balanceReceivable);
    }

    private void loadCancellation(Id cancellationId) {
        List<Booking__c> cancellationBookings = [
            SELECT Id, Name, First_Applicant_Name__c, Second_Applicant_Name__c, Co_Applicant_Name__c,
                   Permanent_Address__c, Cancellation_Date__c, Cancellation_Request_Date_Time__c,
                   Cancellation_Reason__c, Total_Refunded_Amount__c,
                   Plot__r.Name, Plot__r.Saleable_Area_Sft__c
            FROM Booking__c
            WHERE Id = :cancellationId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (cancellationBookings.isEmpty()) {
            return;
        }
        cancellationBooking = cancellationBookings[0];
        cancellationBuyerNames = joinNames(cancellationBooking);
        cancellationRequestDate = cancellationBooking.Cancellation_Request_Date_Time__c != null
            ? cancellationBooking.Cancellation_Request_Date_Time__c.date()
            : cancellationBooking.Cancellation_Date__c;

        refunds = [
            SELECT Id, Name, Refund_Amount__c, Refund_Date__c, Refund_Reason__c,
                   Payment_Reference__c, Transaction_Reference__c, Status__c
            FROM Refund__c
            WHERE Booking__c = :cancellationBooking.Id
            AND Status__c = 'Approved'
            WITH SYSTEM_MODE
            ORDER BY Refund_Date__c ASC
            LIMIT 200
        ];
        cancellationReceiptLineItems = receiptsFor(new Set<Id>{ cancellationBooking.Id });
        cancellationReceipts = new ReceiptSummary(cancellationReceiptLineItems);
        cancellationTotalReceived = cancellationReceipts.total;
        cancellationReceivedText = cancellationReceipts.totalText;

        List<String> refList = new List<String>();
        List<String> dateList = new List<String>();
        for (Refund__c refund : refunds) {
            cancellationTotalRefunded += refund.Refund_Amount__c == null ? 0 : refund.Refund_Amount__c;
            addUnique(refList, String.isNotBlank(refund.Transaction_Reference__c)
                ? refund.Transaction_Reference__c : refund.Payment_Reference__c);
            addUnique(dateList, formatDate(refund.Refund_Date__c));
            if (refund.Refund_Date__c != null) {
                lastRefundDate = refund.Refund_Date__c;
            }
        }
        hasRefunds = !refunds.isEmpty();
        refundReferences = String.join(refList, '; ');
        refundDates = String.join(dateList, '; ');
    }

    private void loadSwap(Id swapId) {
        List<Swap_History__c> swapRecords = [
            SELECT Id, Name, Swap_Date__c, Swap_Reason__c, Old_Plot__c, New_Plot__c,
                   Old_Booking__c, New_Booking__c,
                   Old_Plot__r.Name, Old_Plot__r.Saleable_Area_Sft__c,
                   New_Plot__r.Name, New_Plot__r.Saleable_Area_Sft__c,
                   Old_Booking__r.First_Applicant_Name__c, Old_Booking__r.Second_Applicant_Name__c,
                   Old_Booking__r.Co_Applicant_Name__c,
                   New_Booking__r.First_Applicant_Name__c, New_Booking__r.Second_Applicant_Name__c,
                   New_Booking__r.Co_Applicant_Name__c, New_Booking__r.Mobile_Primary__c
            FROM Swap_History__c
            WHERE Id = :swapId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (swapRecords.isEmpty()) {
            return;
        }
        swapHistory = swapRecords[0];

        // The customer who swapped: their booking before the swap, else the one after it.
        swapCustomerNames = joinNames(swapHistory.Old_Booking__r);
        if (String.isBlank(swapCustomerNames)) {
            swapCustomerNames = joinNames(swapHistory.New_Booking__r);
        }

        // Money that customer has paid, on either side of the swap.
        Set<Id> customerBookingIds = new Set<Id>();
        if (swapHistory.Old_Booking__c != null) customerBookingIds.add(swapHistory.Old_Booking__c);
        if (swapHistory.New_Booking__c != null) customerBookingIds.add(swapHistory.New_Booking__c);
        if (!customerBookingIds.isEmpty()) {
            swapReceipts = new ReceiptSummary(receiptsFor(customerBookingIds));
        }

        // "<old flat> was released from <customer> and is allotted as new booking to <buyer>":
        // only true when the released flat is the unit this NOC is raised for, and the buyer is
        // not the customer who swapped out of it.
        showSwapNote = booking != null
            && swapHistory.Old_Plot__c != null
            && swapHistory.Old_Plot__c == booking.Plot__c
            && booking.Id != swapHistory.Old_Booking__c
            && booking.Id != swapHistory.New_Booking__c;
    }

    private static List<Receipt_Line_Item__c> receiptsFor(Set<Id> bookingIds) {
        return [
            SELECT Id, Name, Cheque_Date__c, Receipt__r.Receipt_Date__c, Payment_From__c,
                   Mode_of_Payment__c, Cheque_no_Transaction_Number__c, Received_Amount__c,
                   Receipt__r.Account_Name__r.Name
            FROM Receipt_Line_Item__c
            WHERE Booking__c IN :bookingIds
            AND Receipt__r.Approval_Status__c = 'Approved'
            AND Receipt__r.Receipt_Status__c = 'Received'
            WITH SYSTEM_MODE
            ORDER BY Receipt__r.Receipt_Date__c ASC
            LIMIT 200
        ];
    }

    // ------------------------------------------------------------------ selections

    /** Every cancelled booking selected on the NOC, first selection first, no duplicates. */
    public static List<Id> selectedCancellationIds(NOC__c noc) {
        return selectedIds(
            noc == null ? null : noc.Related_Cancellation_Booking__c,
            noc == null ? null : noc.Related_Cancellation_Booking_Ids__c,
            Booking__c.SObjectType
        );
    }

    /** Every swap history selected on the NOC, first selection first, no duplicates. */
    public static List<Id> selectedSwapIds(NOC__c noc) {
        return selectedIds(
            noc == null ? null : noc.Related_Swap_History__c,
            noc == null ? null : noc.Related_Swap_History_Ids__c,
            Swap_History__c.SObjectType
        );
    }

    private static List<Id> selectedIds(Id primaryId, String idList, Schema.SObjectType expectedType) {
        List<Id> ids = new List<Id>();
        Set<Id> seen = new Set<Id>();
        if (primaryId != null) {
            ids.add(primaryId);
            seen.add(primaryId);
        }
        if (String.isNotBlank(idList)) {
            for (String raw : idList.split('[,;\\s]+')) {
                String candidate = raw.trim();
                if (!(candidate instanceof Id)) {
                    continue;
                }
                Id parsed = (Id) candidate;
                if (parsed.getSObjectType() == expectedType && !seen.contains(parsed)) {
                    ids.add(parsed);
                    seen.add(parsed);
                }
            }
        }
        return ids;
    }

    private static Id requestedRelatedId() {
        PageReference page = ApexPages.currentPage();
        String raw = page == null ? null : page.getParameters().get(RELATED_ID_PARAM);
        return String.isNotBlank(raw) && raw instanceof Id ? (Id) raw : null;
    }

    private static Id pick(Id requestedId, List<Id> selected) {
        if (selected.isEmpty()) {
            return null;
        }
        return requestedId != null && selected.contains(requestedId) ? requestedId : selected[0];
    }

    // ------------------------------------------------------------------ formatting

    private static String joinNames(Booking__c source) {
        if (source == null) {
            return '';
        }
        List<String> names = new List<String>();
        addUnique(names, source.First_Applicant_Name__c);
        addUnique(names, String.isNotBlank(source.Second_Applicant_Name__c)
            ? source.Second_Applicant_Name__c : source.Co_Applicant_Name__c);
        return String.join(names, ' & ');
    }

    private static void addUnique(List<String> values, String value) {
        if (String.isNotBlank(value) && !values.contains(value.trim())) {
            values.add(value.trim());
        }
    }

    private static String formatDate(Date value) {
        return value == null ? null
            : DateTime.newInstance(value.year(), value.month(), value.day()).format('dd-MM-yyyy');
    }

    /** 1117380 -> "11,17,380" (Indian grouping, whole rupees). Blank for null. */
    public static String formatIndian(Decimal amount) {
        if (amount == null) {
            return '';
        }
        Long rupees = amount.setScale(0, RoundingMode.HALF_UP).longValue();
        String digits = String.valueOf(Math.abs(rupees));
        String result;
        if (digits.length() <= 3) {
            result = digits;
        } else {
            result = digits.right(3);
            String rest = digits.left(digits.length() - 3);
            while (rest.length() > 2) {
                result = rest.right(2) + ',' + result;
                rest = rest.left(rest.length() - 2);
            }
            result = rest + ',' + result;
        }
        return (rupees < 0 ? '-' : '') + result;
    }
}
