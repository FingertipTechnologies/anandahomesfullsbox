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

    /**
     * "Download" in the preview window opens the page with download=1: the PDF is then sent as a
     * file (named by fileName) instead of being shown in the browser.
     */
    private static void applyDownloadHeader() {
        PageReference page = ApexPages.currentPage();
        if (page == null || page.getParameters().get('download') != '1') {
            return;
        }
        String fileName = page.getParameters().get('fileName');
        fileName = String.isBlank(fileName) ? '' : fileName.replaceAll('[^A-Za-z0-9 _.-]', '').trim();
        if (String.isBlank(fileName)) {
            fileName = 'Sale Deed';
        }
        page.getHeaders().put('content-disposition', 'attachment; filename="' + fileName + '.pdf"');
    }

    // =====================================================================
    // Purchaser, flat and amount details
    // =====================================================================
    // Read from the booking, its unit and its applicants, with the same mapping the Drizzle sale
    // deed uses (DrizzleSaleDeedController): first applicant, second applicant and every
    // Co-Applicant record; flat details from the unit; consideration from Total Flat Cost.
    // A value that is missing prints as a dash line, never as nothing.
    private static final String DASH = '________';

    public class Purchaser {
        /** "1. DR. A, S/O. DR. B," - numbered only when there is more than one purchaser. */
        public String nameLine { get; private set; }
        /** " aged about 23 years, Occupation: Doctor, Resident of ... (Aadhar No.... & PAN No....)." */
        public String details { get; private set; }
        public Boolean isLast { get; private set; }
    }

    public List<Purchaser> purchasers { get; private set; }
    /** Names for the VENDEE(S) signature block: "DR. A, S/O. DR. B, SMT. C, W/O. D," */
    public String vendeeNames { get; private set; }
    public String flatNo { get; private set; }               // T8-910
    public String facing { get; private set; }               // East
    public String floor { get; private set; }                // Ninth
    public String tower { get; private set; }                // 8
    public String bhk { get; private set; }                  // 3
    public String area { get; private set; }                 // 2215
    public String considerationAmount { get; private set; }  // 48,73,000
    public String considerationWords { get; private set; }   // Rupees Forty Eight Lakh ... Only
    public String boundaryNorth { get; private set; }
    public String boundarySouth { get; private set; }
    public String boundaryEast { get; private set; }
    public String boundaryWest { get; private set; }

    private static String orDash(String value) {
        return String.isBlank(value) ? DASH : value.trim();
    }

    /** "T8" and "Tower 8" print as "8" (the deed already says "Tower -"); other names stay as they are. */
    @TestVisible
    private static String towerNumber(String towerName) {
        if (String.isBlank(towerName)) {
            return '';
        }
        String stripped = towerName.trim().replaceFirst('(?i)^(TOWER[\\s\\-]*|T(?=\\d))', '').trim();
        return String.isBlank(stripped) ? towerName.trim() : stripped;
    }

    private void loadDeedDetails(ApexPages.StandardController standardController) {
        DrizzleSaleDeedController deed = new DrizzleSaleDeedController(standardController);

        flatNo = orDash(deed.flatNo);
        facing = orDash(deed.facingTitle);
        floor = orDash(deed.floorTitle);
        tower = orDash(towerNumber(deed.blockName));
        bhk = orDash(deed.bhkNumber);
        area = orDash(deed.flatSizeNumber);
        considerationAmount = orDash(deed.considerationAmount);
        considerationWords = orDash(deed.considerationWords);
        boundaryNorth = orDash(deed.boundaryNorth);
        boundarySouth = orDash(deed.boundarySouth);
        boundaryEast = orDash(deed.boundaryEast);
        boundaryWest = orDash(deed.boundaryWest);

        purchasers = new List<Purchaser>();
        List<String> names = new List<String>();
        Integer total = deed.vendees == null ? 0 : deed.vendees.size();
        for (Integer i = 0; i < total; i++) {
            DrizzleSaleDeedController.Vendee v = deed.vendees[i];
            String name = orDash(v.nameLine);
            if (!name.endsWith(',')) {
                name += ',';
            }
            names.add(name);
            Purchaser p = new Purchaser();
            p.nameLine = (total > 1 ? String.valueOf(i + 1) + '. ' : '') + name;
            p.details = ' ' + (String.isBlank(v.ageText) ? 'aged about ____ years' : v.ageText) +
                ', Occupation: ' + orDash(v.occupation) +
                ', Resident of ' + orDash(v.address) +
                '. (Aadhar No.' + orDash(v.aadhar) + ' & PAN No.' + orDash(v.pan) + ').';
            p.isLast = (i == total - 1);
            purchasers.add(p);
        }
        if (purchasers.isEmpty()) {
            Purchaser blank = new Purchaser();
            blank.nameLine = DASH + ',';
            blank.details = ' aged about ____ years, Occupation: ' + DASH + ', Resident of ' + DASH +
                '. (Aadhar No.' + DASH + ' & PAN No.' + DASH + ').';
            blank.isLast = true;
            purchasers.add(blank);
            names.add(DASH + ',');
        }
        vendeeNames = String.join(names, ' ');
    }
    public LegacySaleDeedController(ApexPages.StandardController standardController) {
        paymentEntries = new List<PaymentEntry>();
        totalTdsAmount = 0;
        applyDownloadHeader();
        loadDeedDetails(standardController);
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