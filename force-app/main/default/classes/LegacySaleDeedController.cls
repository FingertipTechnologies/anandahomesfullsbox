public with sharing class LegacySaleDeedController {
    /**
     * One approved receipt of the booking, as the deed lists it:
     * "a. Rs. 50,000/- paid through NEFT vide Reference No. 4227..., Dated: 14/08/2024."
     * The money, method, reference and date live on the Receipt itself; its Receipt Line Items are
     * allocations to the payment schedule and carry no amounts (user, 2026-11-13).
     */
    public class PaymentEntry {
        public Receipt__c receipt { get; private set; }
        /** "94,55,900" - Indian grouping, no decimals. */
        public String amountDisplay { get; private set; }
        /** "Rupees Fifty Thousand Only" */
        public String amountWords { get; private set; }
        /** NEFT / RTGS / Cheque / UPI ... */
        public String mode { get; private set; }
        /** Transaction reference, else cheque / transaction number, else cheque number. */
        public String reference { get; private set; }
        public Date paymentDate { get; private set; }
        public String sequenceLabel { get; private set; }

        private PaymentEntry(Receipt__c source, Integer index) {
            receipt = source;
            amountDisplay = indianNumber(source.Amount_received__c);
            amountWords = source.Amount_received__c == null ? ''
                : 'Rupees ' + new NumberTOWordConvertion().getNumberTOWordConvertion(source.Amount_received__c);
            mode = String.isNotBlank(source.Payment_Method__c) ? source.Payment_Method__c : source.Mode_of_payment__c;
            reference = String.isNotBlank(source.Transaction_Reference__c) ? source.Transaction_Reference__c
                : String.isNotBlank(source.Check_Transaction_Nmber__c) ? source.Check_Transaction_Nmber__c
                : source.Cheque_Number__c;
            paymentDate = source.Cheque_Date__c != null ? source.Cheque_Date__c : source.Receipt_Date__c;
            String alphabet = 'abcdefghijklmnopqrstuvwxyz';
            sequenceLabel = index < alphabet.length()
                ? alphabet.substring(index, index + 1)
                : String.valueOf(index + 1);
        }
    }

    /** 9455900 -> "94,55,900" (Indian digit grouping, rounded to the rupee). */
    @TestVisible
    private static String indianNumber(Decimal value) {
        if (value == null) {
            return '';
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
    // Co-Applicant record; flat details from the unit; consideration from Total Payable Amount.
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

    /**
     * The first applicant's line as the Drizzle deed builds it ("MRS. A, <relation> B"), with the relation
     * taken from the booking's S/o,D/o,W/o field (Primary Applicant Relation Details when that is blank):
     * "TEST APPLICANT1, EW" becomes "TEST APPLICANT1, W/o. EW". Any other line is returned unchanged.
     */
    @TestVisible
    private static String withPrimaryRelation(String line, Booking__c booking) {
        if (String.isBlank(line) || booking == null || String.isBlank(booking.Son_Daughter_Wife_of__c)
            || (String.isBlank(booking.First_Applicant_Name__c) && String.isBlank(booking.Applicant_Name__c))) {
            return line;
        }
        String parent = booking.Son_Daughter_Wife_of__c.trim().toUpperCase();
        String oldRelation = relationText(booking.Relation_Details_Applicant1__c);
        String oldSuffix = ', ' + (String.isBlank(oldRelation) ? '' : oldRelation + ' ') + parent;
        if (!line.endsWith(oldSuffix)) {
            return line;
        }
        String relation = relationText(String.isNotBlank(booking.S_o_D_o_W_o__c)
            ? booking.S_o_D_o_W_o__c : booking.Relation_Details_Applicant1__c);
        return line.removeEnd(oldSuffix) + ', ' + (String.isBlank(relation) ? '' : relation + ' ') + parent;
    }

    /** "W/o" -> "W/o." (blank stays blank). */
    private static String relationText(String relation) {
        if (String.isBlank(relation)) {
            return '';
        }
        String rel = relation.trim();
        return rel.endsWith('.') ? rel : rel + '.';
    }

    private void loadDeedDetails(ApexPages.StandardController standardController) {
        DrizzleSaleDeedController deed = new DrizzleSaleDeedController(standardController);

        flatNo = orDash(deed.flatNo);
        facing = orDash(deed.facingTitle);
        floor = orDash(deed.floorTitle);
        tower = orDash(towerNumber(deed.blockName));
        bhk = orDash(deed.bhkNumber);
        area = orDash(deed.flatSizeNumber);
        // Legacey deed only (2026-11-14): the consideration is the booking's Total Payable Amount, and the
        // first applicant's relation comes from the booking's "S/o,D/o,W/o" field. The Drizzle deed is unchanged.
        Booking__c legacyBooking = null;
        if (standardController != null && standardController.getId() != null) {
            List<Booking__c> rows = [
                SELECT Total_Payable_Amount__c, S_o_D_o_W_o__c, Relation_Details_Applicant1__c,
                       Son_Daughter_Wife_of__c, First_Applicant_Name__c, Applicant_Name__c
                FROM Booking__c
                WHERE Id = :standardController.getId()
                LIMIT 1
            ];
            legacyBooking = rows.isEmpty() ? null : rows[0];
        }
        Decimal payable = legacyBooking == null ? null : legacyBooking.Total_Payable_Amount__c;
        considerationAmount = orDash(indianNumber(payable));
        considerationWords = payable == null ? DASH
            : 'Rupees ' + new NumberTOWordConvertion().getNumberTOWordConvertion(payable);
        boundaryNorth = orDash(deed.boundaryNorth);
        boundarySouth = orDash(deed.boundarySouth);
        boundaryEast = orDash(deed.boundaryEast);
        boundaryWest = orDash(deed.boundaryWest);

        purchasers = new List<Purchaser>();
        List<String> names = new List<String>();
        Integer total = deed.vendees == null ? 0 : deed.vendees.size();
        for (Integer i = 0; i < total; i++) {
            DrizzleSaleDeedController.Vendee v = deed.vendees[i];
            String name = orDash(i == 0 ? withPrimaryRelation(v.nameLine, legacyBooking) : v.nameLine);
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
        // Approved receipts towards the sale consideration (GST and additional-charge receipts are not
        // part of the consideration and are left out, as in the Agreement of Sale pages).
        List<Receipt__c> receipts = [
            SELECT Id, Amount_received__c, TDS_Deducted__c, Payment_Method__c, Mode_of_payment__c,
                   Transaction_Reference__c, Check_Transaction_Nmber__c, Cheque_Number__c,
                   Cheque_Date__c, Receipt_Date__c, Receipt_Type__c
            FROM Receipt__c
            WHERE Booking__c = :bookingId
              AND Amount_received__c > 0
              AND Approval_Status__c IN ('Approved', 'Approved by Finance Team')
            ORDER BY Receipt_Date__c ASC, CreatedDate ASC
            LIMIT 200
        ];

        Integer index = 0;
        for (Receipt__c receipt : receipts) {
            paymentEntries.add(new PaymentEntry(receipt, index));
            index++;
            totalTdsAmount += receipt.TDS_Deducted__c == null
                ? 0
                : receipt.TDS_Deducted__c;
        }
    }
}