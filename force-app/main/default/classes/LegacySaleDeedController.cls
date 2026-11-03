public with sharing class LegacySaleDeedController {
    public class PaymentEntry {
        public Receipt_Line_Item__c lineItem { get; private set; }
        public Date paymentDate { get; private set; }
        public String sequenceLabel { get; private set; }

        private PaymentEntry(Receipt_Line_Item__c source, Integer index) {
            lineItem = source;
            paymentDate = source.Cheque_Date__c != null
                ? source.Cheque_Date__c
                : source.Receipt__r.Receipt_Date__c;
            String alphabet = 'abcdefghijklmnopqrstuvwxyz';
            sequenceLabel = index < alphabet.length()
                ? alphabet.substring(index, index + 1)
                : String.valueOf(index + 1);
        }
    }

    public List<PaymentEntry> paymentEntries { get; private set; }
    public Decimal totalTdsAmount { get; private set; }

    public Boolean getHasPaymentEntries() {
        return paymentEntries != null && !paymentEntries.isEmpty();
    }

    public LegacySaleDeedController(ApexPages.StandardController standardController) {
        paymentEntries = new List<PaymentEntry>();
        totalTdsAmount = 0;
        if (standardController == null || standardController.getId() == null) {
            return;
        }

        Id bookingId = standardController.getId();
        List<Receipt_Line_Item__c> receiptLines = [
            SELECT Id, Received_Amount__c, TDS_Amount__c, Mode_of_Payment__c,
                   Cheque_no_Transaction_Number__c, Cheque_Date__c,
                   Receipt__r.Receipt_Date__c
            FROM Receipt_Line_Item__c
            WHERE Booking__c = :bookingId
              AND Received_Amount__c > 0
              AND Receipt__r.Approval_Status__c = 'Approved'
              AND Receipt__r.Receipt_Status__c = 'Received'
            ORDER BY Receipt__r.Receipt_Date__c ASC, CreatedDate ASC
            LIMIT 200
        ];

        Integer index = 0;
        for (Receipt_Line_Item__c receiptLine : receiptLines) {
            paymentEntries.add(new PaymentEntry(receiptLine, index));
            index++;
            totalTdsAmount += receiptLine.TDS_Amount__c == null
                ? 0
                : receiptLine.TDS_Amount__c;
        }
    }
}