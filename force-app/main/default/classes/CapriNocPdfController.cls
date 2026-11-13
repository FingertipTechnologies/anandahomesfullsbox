/**
 * Supplies NOC and booking data to the CAPRI NOC Visualforce PDF.
 */
public with sharing class CapriNocPdfController {
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

    public CapriNocPdfController(ApexPages.StandardController standardController) {
        Id nocId = standardController == null ? null : standardController.getId();
        if (nocId == null) {
            errorMessage = 'A NOC record ID is required to generate this document.';
            return;
        }

        List<NOC__c> records = [
            SELECT Id, Name, Booking__c, Related_Cancellation_Booking__c, Related_Swap_History__c,
                   Booking__r.Id, Booking__r.Name, Booking__r.First_Applicant_Name__c,
                   Booking__r.Permanent_Address__c, Booking__r.Booking_Date__c,
                   Booking__r.Rate_Per_Sqft__c, Booking__r.Total_Flat_Cost__c,
                   Booking__r.Cancellation_Date__c, Booking__r.Cancellation_Reason__c,
                   Booking__r.Total_Refunded_Amount__c,
                   Booking__r.Bank_Name__c, Booking__r.Bank_Branch__c,
                   Booking__r.Banker_Contact_Person__c, Booking__r.Banker_Contact_Number__c,
                   Booking__r.Project__r.Name, Booking__r.Project__r.Project_Address__c,
                   Booking__r.Project__r.Project_description__c,
                   Booking__r.Plot__r.Name, Booking__r.Plot__r.Saleable_Area_Sft__c,
                   Booking__r.Plot__r.Block1__r.Name,
                   Booking__r.Cost_Sheet__r.Amenities_Charges__c
            FROM NOC__c
            WHERE Id = :nocId
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

        if (noc.Related_Cancellation_Booking__c != null) {
            List<Booking__c> cancellationBookings = [
                SELECT Id, Name, First_Applicant_Name__c, Permanent_Address__c,
                       Cancellation_Date__c, Cancellation_Reason__c, Total_Refunded_Amount__c,
                       Plot__r.Name, Plot__r.Saleable_Area_Sft__c
                FROM Booking__c
                WHERE Id = :noc.Related_Cancellation_Booking__c
                LIMIT 1
            ];
            if (!cancellationBookings.isEmpty()) {
                cancellationBooking = cancellationBookings[0];
                refunds = [
                    SELECT Id, Name, Refund_Amount__c, Refund_Date__c, Refund_Reason__c,
                           Payment_Reference__c, Transaction_Reference__c, Status__c
                    FROM Refund__c
                    WHERE Booking__c = :cancellationBooking.Id
                    AND Status__c = 'Approved'
                    ORDER BY Refund_Date__c ASC
                    LIMIT 200
                ];
                cancellationReceiptLineItems = [
                    SELECT Id, Name, Cheque_Date__c, Receipt__r.Receipt_Date__c, Payment_From__c,
                           Cheque_no_Transaction_Number__c, Received_Amount__c
                    FROM Receipt_Line_Item__c
                    WHERE Booking__c = :cancellationBooking.Id
                    AND Receipt__r.Approval_Status__c = 'Approved'
                    AND Receipt__r.Receipt_Status__c = 'Received'
                    ORDER BY Receipt__r.Receipt_Date__c ASC
                    LIMIT 200
                ];
                for (Receipt_Line_Item__c lineItem : cancellationReceiptLineItems) {
                    cancellationTotalReceived +=
                        lineItem.Received_Amount__c == null ? 0 : lineItem.Received_Amount__c;
                }
                for (Refund__c refund : refunds) {
                    cancellationTotalRefunded +=
                        refund.Refund_Amount__c == null ? 0 : refund.Refund_Amount__c;
                }
            }
        }

        if (noc.Related_Swap_History__c != null) {
            List<Swap_History__c> swapRecords = [
                SELECT Id, Name, Swap_Date__c, Swap_Reason__c,
                       Old_Plot__r.Name, Old_Plot__r.Saleable_Area_Sft__c,
                       New_Plot__r.Name, New_Plot__r.Saleable_Area_Sft__c,
                       Old_Booking__r.First_Applicant_Name__c,
                       New_Booking__r.First_Applicant_Name__c,
                       New_Booking__r.Mobile_Primary__c
                FROM Swap_History__c
                WHERE Id = :noc.Related_Swap_History__c
                LIMIT 1
            ];
            if (!swapRecords.isEmpty()) {
                swapHistory = swapRecords[0];
            }
        }

        if (booking == null) {
            errorMessage = 'The NOC is not linked to a booking.';
            return;
        }

        receiptLineItems = [
            SELECT Id, Name, Cheque_Date__c, Receipt__r.Receipt_Date__c, Payment_From__c,
                   Cheque_no_Transaction_Number__c, Received_Amount__c,
                   Receipt__r.Account_Name__r.Name
            FROM Receipt_Line_Item__c
            WHERE Booking__c = :booking.Id
            AND Receipt__r.Approval_Status__c = 'Approved'
            AND Receipt__r.Receipt_Status__c = 'Received'
            ORDER BY Receipt__r.Receipt_Date__c ASC
            LIMIT 200
        ];

        for (Receipt_Line_Item__c lineItem : receiptLineItems) {
            totalReceived += lineItem.Received_Amount__c == null ? 0 : lineItem.Received_Amount__c;
        }

        Decimal consideration = booking.Total_Flat_Cost__c == null ? 0 : booking.Total_Flat_Cost__c;
        balanceReceivable = Math.max(0, consideration - totalReceived);
    }
}