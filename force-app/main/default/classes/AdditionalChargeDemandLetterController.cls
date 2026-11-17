/**
 * @description Controller for AdditionalChargeDemandLetter (PDF attached to the "Additional Charge
 *              Demand Email", 2026-11-17). Loads the charge with its booking/unit/project and the
 *              project's collection account (Account_Name__c: 'Full', else 'Flat').
 */
public with sharing class AdditionalChargeDemandLetterController {

    public Additional_Charge__c charge { get; private set; }
    public Decimal baseAmount { get; private set; }
    public Decimal gstAmount { get; private set; }
    public Decimal totalAmount { get; private set; }
    public Decimal receivedAmount { get; private set; }
    public Decimal balanceAmount { get; private set; }
    public Date letterDate { get; private set; }
    public String accountHolder { get; private set; }
    public String accountNumber { get; private set; }
    public String bankName { get; private set; }
    public String accountBranch { get; private set; }
    public String ifscCode { get; private set; }
    public String errorMessage { get; private set; }

    @TestVisible
    private static final List<String> ACCOUNT_TYPES = new List<String>{ 'Full', 'Flat' };

    public AdditionalChargeDemandLetterController(ApexPages.StandardController std) {
        Id chargeId = std.getId();
        List<Additional_Charge__c> rows = [
            SELECT Id, Name, Charge_Name__c, Charge_Type__c, Description__c, Amount__c, GST_Amount__c,
                   Amount_Paid__c, Demand_Date__c, Due_Date__c,
                   Booking__r.Name, Booking__r.Applicant_Name__c, Booking__r.Salutation__c,
                   Booking__r.First_Applicant_Name__c, Booking__r.FloorNo__c, Booking__r.Project__c,
                   Booking__r.Plot__r.Name, Booking__r.Plot__r.Tower_Block__c, Booking__r.Project__r.Name
            FROM Additional_Charge__c WHERE Id = :chargeId
        ];
        if (rows.isEmpty()) {
            errorMessage = 'Additional charge not found.';
            return;
        }
        charge = rows[0];
        baseAmount = nz(charge.Amount__c);
        gstAmount = nz(charge.GST_Amount__c);
        totalAmount = baseAmount + gstAmount;
        receivedAmount = Math.min(nz(charge.Amount_Paid__c), totalAmount);
        balanceAmount = totalAmount - receivedAmount;
        letterDate = charge.Demand_Date__c != null ? charge.Demand_Date__c : Date.today();
        loadAccount(charge.Booking__r == null ? null : charge.Booking__r.Project__c);
    }

    /** "Mr. Ravi Kumar" - the applicant name as printed on the demand letters. */
    public String applicantName {
        get {
            if (charge == null || charge.Booking__r == null) return '';
            Booking__c b = charge.Booking__r;
            if (String.isNotBlank(b.Applicant_Name__c)) return b.Applicant_Name__c;
            return ((b.Salutation__c == null ? '' : b.Salutation__c + ' ')
                + (b.First_Applicant_Name__c == null ? '' : b.First_Applicant_Name__c)).trim();
        }
    }

    public String chargeLabel {
        get {
            if (charge == null) return '';
            return String.isNotBlank(charge.Charge_Name__c) ? charge.Charge_Name__c : charge.Charge_Type__c;
        }
    }

    private void loadAccount(Id projectId) {
        if (projectId == null) return;
        Map<String, Account_Name__c> byType = new Map<String, Account_Name__c>();
        for (Account_Name__c a : [
            SELECT Name, Account_No__c, Bank_Name__c, IFSC_Code__c, Branch__c, Account_Type__c
            FROM Account_Name__c
            WHERE Project__c = :projectId AND Account_Type__c IN :ACCOUNT_TYPES
            ORDER BY LastModifiedDate DESC
        ]) {
            if (!byType.containsKey(a.Account_Type__c)) byType.put(a.Account_Type__c, a);
        }
        for (String t : ACCOUNT_TYPES) {
            Account_Name__c a = byType.get(t);
            if (a != null) {
                accountHolder = a.Name;
                accountNumber = a.Account_No__c;
                bankName = a.Bank_Name__c;
                accountBranch = a.Branch__c;
                ifscCode = a.IFSC_Code__c;
                return;
            }
        }
    }

    public Boolean hasAccount { get { return String.isNotBlank(accountNumber); } }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}
