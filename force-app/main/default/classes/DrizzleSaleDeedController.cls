/**
 * @description Extension for the SaleDeedDrizzle Visualforce page (THE DRIZZLE sale deed PDF).
 *              Fills every yellow-marked value of the deed draft from one Booking__c record:
 *                - Vendees        : primary applicant, second applicant (when filled) and every
 *                                   Co_Applicant__c record, oldest first
 *                - Flat schedule  : Booking__c.Plot__c (Unit) and its Tower (Block1__c), areas,
 *                                   UDS and boundaries
 *                - Consideration  : Booking__c.Total_Flat_Cost__c, in figures and words
 *                - Payments       : approved and received Receipt_Line_Item__c records
 *              Every value is a pre-formatted string so the page only prints it. Blank or missing
 *              data renders as an empty value instead of failing the PDF.
 */
public with sharing class DrizzleSaleDeedController {

    private static final String[] ORDINALS = new String[]{
        'GROUND', 'FIRST', 'SECOND', 'THIRD', 'FOURTH', 'FIFTH', 'SIXTH', 'SEVENTH', 'EIGHTH', 'NINTH', 'TENTH',
        'ELEVENTH', 'TWELFTH', 'THIRTEENTH', 'FOURTEENTH', 'FIFTEENTH', 'SIXTEENTH', 'SEVENTEENTH', 'EIGHTEENTH',
        'NINETEENTH', 'TWENTIETH', 'TWENTY-FIRST', 'TWENTY-SECOND', 'TWENTY-THIRD', 'TWENTY-FOURTH', 'TWENTY-FIFTH',
        'TWENTY-SIXTH', 'TWENTY-SEVENTH', 'TWENTY-EIGHTH', 'TWENTY-NINTH', 'THIRTIETH'
    };
    private static final String[] COUNT_WORDS = new String[]{
        'NIL', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE', 'TEN'
    };
    private static final Set<String> SALUTATIONS = new Set<String>{ 'mr', 'mrs', 'ms', 'dr', 'smt', 'sri', 'kum' };
    private static final Pattern FIRST_NUMBER = Pattern.compile('(\\d+(?:\\.\\d+)?)');
    private static final String AREA_SUFFIX = ' SFT';
    private static final String UDS_SUFFIX = ' Sq. Yds';

    public Booking__c booking { get; private set; }
    public List<Vendee> vendees { get; private set; }
    public List<PaymentEntry> paymentEntries { get; private set; }

    // Flat schedule (tables and annexure)
    public String projectName { get; private set; }
    public String blockName { get; private set; }
    public String flatNo { get; private set; }
    public String floorName { get; private set; }      // THIRD
    public String floorTitle { get; private set; }     // Third
    public String flatType { get; private set; }       // 3 BHK
    public String bhkNumber { get; private set; }      // 3
    public String facingName { get; private set; }     // WEST
    public String facingTitle { get; private set; }    // West
    public String flatSize { get; private set; }       // 1995 SFT
    public String flatSizeNumber { get; private set; } // 1995
    public String carpetArea { get; private set; }
    public String balconyArea { get; private set; }
    public String utilityArea { get; private set; }
    public String commonArea { get; private set; }
    public String externalWall { get; private set; }
    public String internalWall { get; private set; }
    public String carParkingName { get; private set; }  // TWO
    public String carParkingTitle { get; private set; } // Two
    public String udsNumber { get; private set; }       // 47.30
    public String udsArea { get; private set; }         // 47.30 Sq. Yds
    public String boundaryNorth { get; private set; }
    public String boundarySouth { get; private set; }
    public String boundaryEast { get; private set; }
    public String boundaryWest { get; private set; }

    // Consideration and payments
    public String considerationAmount { get; private set; } // 89,77,500
    public String considerationWords { get; private set; }  // Rupees Eighty Nine Lakh ... Only
    public String totalReceived { get; private set; }       // 89,77,500/-
    public String paidAmount { get; private set; }          // amount the VENDEE(S) has paid, e.g. 27,98,754
    public String paidWords { get; private set; }

    public Boolean hasPaymentEntries {
        get { return paymentEntries != null && !paymentEntries.isEmpty(); }
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

    public DrizzleSaleDeedController(ApexPages.StandardController standardController) {
        initializeValues();
        applyDownloadHeader();

        Id bookingId = standardController == null ? null : standardController.getId();
        if (bookingId == null) {
            return;
        }

        List<Booking__c> rows = [
            SELECT Id, Name, Project__r.Name, Flat_Number__c, Tower__c,S_o_D_o_W_o__c,
                   Car_Parking_Selected__c, Extra_covered_Parking_Slots__c, No_of_car_parking__c, Total_Flat_Cost__c,
                   Total_Payable_Amount__c, Total_Receipt_Amount__c, Salutation__c,
                   salutation_Applicant1__c, First_Applicant_Name__c, Applicant_Name__c,
                   Relation_Details_Applicant1__c, Son_Daughter_Wife_of__c,
                   Date_of_Birth1__c, Date_of_Birth__c, Primary_Applicant_Age__c, Occupation__c,
                   Permanent_Address__c, Address__c, Aadhaar_Number__c, Aadhaar__c,
                   PAN_Number1__c, PAN_Number__c,
                   salutation_Applicant2__c, Second_Applicant_Name__c, Relation_Details_Applicant2__c,
                   Son_Daughter_Wife_of1__c, Date_of_birth_Applicant2__c, Occupation1__c,
                   Permanent_Address1__c, Communication_address1__c, Aadhaar_Number1__c,
                   Pan_Number_Applicant2__c,
                   Plot__r.Name, Plot__r.Block1__r.Name, Plot__r.Tower__c,
                   Plot__r.Floor__c, Plot__r.BHK_Type__c, Plot__r.Facing__c,
                   Plot__r.Saleable_Area_Sft__c, Plot__r.Carpet_Area__c, Plot__r.Balcony_Area__c,
                   Plot__r.Other_Exclusive_Area__c, Plot__r.Common_Area_Allotted_to_Association__c,
                   Plot__r.UDS__c, Plot__r.Undivided_Share_of_Land__c, Plot__r.UDS_Sq_mts__c,
                   Plot__r.Utility_Area__c, Plot__r.External_Wall_Area__c, Plot__r.Internal_Wall_Area__c,
                   Plot__r.North_By__c, Plot__r.South_By__c, Plot__r.East_By__c, Plot__r.West_By__c
            FROM Booking__c
            WHERE Id = :bookingId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return;
        }
        booking = rows[0];

        mapFlatSchedule();
        mapVendees();
        mapConsideration();
        mapPayments();
    }

    // =====================================================================
    // Mapping
    // =====================================================================

    private void initializeValues() {
        vendees = new List<Vendee>();
        paymentEntries = new List<PaymentEntry>();
        projectName = ''; blockName = ''; flatNo = ''; floorName = ''; floorTitle = '';
        flatType = ''; bhkNumber = ''; facingName = ''; facingTitle = '';
        flatSize = ''; flatSizeNumber = ''; carpetArea = ''; balconyArea = ''; utilityArea = '';
        commonArea = ''; externalWall = ''; internalWall = '';
        carParkingName = ''; carParkingTitle = ''; udsNumber = ''; udsArea = '';
        boundaryNorth = ''; boundarySouth = ''; boundaryEast = ''; boundaryWest = '';
        considerationAmount = ''; considerationWords = ''; totalReceived = '';
        paidAmount = ''; paidWords = '';
    }

    private void mapFlatSchedule() {
        Plot__c unit = booking.Plot__r;

        projectName = upper(booking.Project__r == null ? '' : booking.Project__r.Name);

        String flatNumberValue = booking.Flat_Number__c == null ? '' : String.valueOf(booking.Flat_Number__c);
        if (flatNumberValue.endsWith('.0')) {
            flatNumberValue = flatNumberValue.substring(0, flatNumberValue.length() - 2);
        }
        flatNo = upper(firstNonBlank(new List<String>{ unit == null ? '' : unit.Name, flatNumberValue }));

        if (unit != null) {
            // Tower (Block1__c lookup) is the block letter in production, e.g. "F"
            blockName = upper(firstNonBlank(new List<String>{
                unit.Block1__r == null ? '' : unit.Block1__r.Name,
                unit.Tower__c,
                booking.Tower__c
            }));
            floorName = floorWord(unit.Floor__c);
            flatType = upper(unit.BHK_Type__c);
            bhkNumber = firstNumberIn(unit.BHK_Type__c);
            facingName = facingWord(unit.Facing__c);
            flatSizeNumber = formatArea(unit.Saleable_Area_Sft__c);
            carpetArea = withSuffix(formatArea(unit.Carpet_Area__c), AREA_SUFFIX);
            balconyArea = withSuffix(formatArea(unit.Balcony_Area__c), AREA_SUFFIX);
            // Utility Area on the unit; units entered earlier hold it in Other Exclusive Area.
            utilityArea = withSuffix(formatArea(unit.Utility_Area__c != null
                ? unit.Utility_Area__c
                : unit.Other_Exclusive_Area__c), AREA_SUFFIX);
            externalWall = withSuffix(formatArea(unit.External_Wall_Area__c), AREA_SUFFIX);
            internalWall = withSuffix(formatArea(unit.Internal_Wall_Area__c), AREA_SUFFIX);
            commonArea = withSuffix(formatArea(unit.Common_Area_Allotted_to_Association__c), AREA_SUFFIX);
            // "UDS Area (Sq Yards)" (UDS__c). UDS_Sq_mts__c is square metres, never printed as yards.
            udsNumber = formatArea(unit.UDS__c != null && unit.UDS__c > 0
                ? unit.UDS__c
                : unit.Undivided_Share_of_Land__c);
            boundaryNorth = upper(unit.North_By__c);
            boundarySouth = upper(unit.South_By__c);
            boundaryEast = upper(unit.East_By__c);
            boundaryWest = upper(unit.West_By__c);
        } else {
            blockName = upper(booking.Tower__c);
        }

        floorTitle = titleCase(floorName);
        facingTitle = titleCase(facingName);
        flatSize = withSuffix(flatSizeNumber, AREA_SUFFIX);
        udsArea = withSuffix(udsNumber, UDS_SUFFIX);

        // The booking's "No of car parking"; older bookings only have the tick box + extra slots.
        Integer parkingCount = booking.No_of_car_parking__c != null
            ? booking.No_of_car_parking__c.intValue()
            : (booking.Car_Parking_Selected__c == true ? 1 : 0)
                + (booking.Extra_covered_Parking_Slots__c == null ? 0 : booking.Extra_covered_Parking_Slots__c.intValue());
        carParkingName = countWord(parkingCount);
        carParkingTitle = titleCase(carParkingName);
    }

    private void mapVendees() {
        vendees = new List<Vendee>();

        String primaryName = firstNonBlank(new List<String>{
            booking.First_Applicant_Name__c, booking.Applicant_Name__c
        });
        if (String.isNotBlank(primaryName)) {
            Vendee v = new Vendee();
            v.nameLine = nameLine(
                firstNonBlank(new List<String>{ booking.salutation_Applicant1__c, booking.Salutation__c }),
                primaryName,
                booking.S_o_D_o_W_o__c, booking.Son_Daughter_Wife_of__c);
            Integer age = booking.Primary_Applicant_Age__c != null
                ? booking.Primary_Applicant_Age__c.intValue()
                : ageFrom(booking.Date_of_Birth1__c != null ? booking.Date_of_Birth1__c : booking.Date_of_Birth__c);
            v.ageText = ageText(age);
            v.occupation = clean(booking.Occupation__c);
            v.address = clean(firstNonBlank(new List<String>{ booking.Permanent_Address__c, booking.Address__c }));
            v.aadhar = formatAadhaar(firstNonBlank(new List<String>{ booking.Aadhaar_Number__c, booking.Aadhaar__c }));
            v.pan = upper(firstNonBlank(new List<String>{ booking.PAN_Number1__c, booking.PAN_Number__c }));
            vendees.add(v);
        }

        if (String.isNotBlank(booking.Second_Applicant_Name__c)) {
            Vendee v = new Vendee();
            v.nameLine = nameLine(booking.salutation_Applicant2__c, booking.Second_Applicant_Name__c,
                booking.Relation_Details_Applicant2__c, booking.Son_Daughter_Wife_of1__c);
            v.ageText = ageText(ageFrom(booking.Date_of_birth_Applicant2__c));
            v.occupation = clean(booking.Occupation1__c);
            v.address = clean(firstNonBlank(new List<String>{ booking.Permanent_Address1__c, booking.Communication_address1__c }));
            v.aadhar = formatAadhaar(booking.Aadhaar_Number1__c);
            v.pan = upper(booking.Pan_Number_Applicant2__c);
            vendees.add(v);
        }

        for (Co_Applicant__c co : [
            SELECT Salutation__c, Full_Name__c, First_Name__c, Last_Name__c,
                   Relalation_Details__c, S_o_D_o_W_o__c, W_o_S_o_C_o_c__c,
                   Date_of_Birth__c, Occupation__c, Aadhar_Number__c, PAN_Number__c,
                   Permenent_Address__c, Address__c
            FROM Co_Applicant__c
            WHERE Booking__c = :booking.Id
            ORDER BY CreatedDate ASC, Name ASC
        ]) {
            String fullName = firstNonBlank(new List<String>{
                co.Full_Name__c,
                (clean(co.First_Name__c) + ' ' + clean(co.Last_Name__c)).trim()
            });
            if (String.isBlank(fullName)) {
                continue;
            }
            Vendee v = new Vendee();
            v.nameLine = nameLine(co.Salutation__c, fullName,
                firstNonBlank(new List<String>{ co.Relalation_Details__c, co.S_o_D_o_W_o__c }),
                co.W_o_S_o_C_o_c__c);
            v.ageText = ageText(ageFrom(co.Date_of_Birth__c));
            v.occupation = clean(co.Occupation__c);
            v.address = clean(firstNonBlank(new List<String>{ co.Permenent_Address__c, co.Address__c }));
            v.aadhar = formatAadhaar(co.Aadhar_Number__c);
            v.pan = upper(co.PAN_Number__c);
            vendees.add(v);
        }

        for (Integer i = 0; i < vendees.size(); i++) {
            vendees[i].isFirst = (i == 0);
            vendees[i].isLast = (i == vendees.size() - 1);
        }
    }

    private void mapConsideration() {
        // Total sale consideration = the booking's Total Payable Amount (flat cost + GST);
        // older bookings without it fall back to Total Flat Cost.
        Decimal amount = booking.Total_Payable_Amount__c != null && booking.Total_Payable_Amount__c > 0
            ? booking.Total_Payable_Amount__c
            : booking.Total_Flat_Cost__c;
        considerationAmount = formatIndianNumber(amount);
        considerationWords = amount == null
            ? ''
            : 'Rupees ' + new NumberTOWordConvertion().getNumberTOWordConvertion(amount);
    }

    private void mapPayments() {
        paymentEntries = new List<PaymentEntry>();
        Decimal total = 0;

        // Every approved receipt of the booking that has not been cancelled or reversed. Receipt Status
        // is usually left blank (only Cancelled / Reversed are ever set), and the receipt's own fields
        // hold the amount, mode and reference - its line items are filled only on allocation.
        for (Receipt__c receipt : [
            SELECT Amount_received__c, Total_Amount__c, Payment_Method__c, Mode_of_payment__c,
                   Check_Transaction_Nmber__c, Transaction_Reference__c, Cheque_Number__c,
                   Cheque_Date__c, Receipt_Date__c
            FROM Receipt__c
            WHERE Booking__c = :booking.Id
              AND Approval_Status__c = 'Approved'
              AND (Receipt_Status__c = null OR Receipt_Status__c NOT IN ('Cancelled', 'Reversed'))
            ORDER BY Receipt_Date__c ASC NULLS LAST, CreatedDate ASC
            LIMIT 200
        ]) {
            Decimal amount = receipt.Amount_received__c != null && receipt.Amount_received__c > 0
                ? receipt.Amount_received__c
                : receipt.Total_Amount__c;
            if (amount == null || amount <= 0) {
                continue;
            }
            PaymentEntry entry = new PaymentEntry();
            entry.dateText = formatDate(receipt.Cheque_Date__c != null ? receipt.Cheque_Date__c : receipt.Receipt_Date__c);
            entry.mode = upper(firstNonBlank(new List<String>{ receipt.Payment_Method__c, receipt.Mode_of_payment__c }));
            entry.reference = clean(firstNonBlank(new List<String>{
                receipt.Check_Transaction_Nmber__c, receipt.Transaction_Reference__c, receipt.Cheque_Number__c
            }));
            entry.amountText = formatIndianNumber(amount);
            paymentEntries.add(entry);
            total += amount;
        }

        totalReceived = paymentEntries.isEmpty() ? '' : formatIndianNumber(total) + '/-';

        // "has paid the entire sale consideration of Rs. ...": the booking's Total Receipt Amount,
        // or the receipts listed when that roll-up is empty.
        Decimal paid = booking.Total_Receipt_Amount__c != null && booking.Total_Receipt_Amount__c > 0
            ? booking.Total_Receipt_Amount__c
            : (paymentEntries.isEmpty() ? null : total);
        // Nothing received yet: a dash line to fill in by hand, never "Rs./- ()".
        paidAmount = paid == null ? '________' : formatIndianNumber(paid);
        paidWords = paid == null ? '________' : 'Rupees ' + new NumberTOWordConvertion().getNumberTOWordConvertion(paid);
    }

    // =====================================================================
    // Formatting helpers
    // =====================================================================

    /** "MR. NISHANT GOEL, S/o. MR. VIJAY PAL GOEL" */
    @TestVisible
    private static String nameLine(String salutation, String name, String relation, String parentName) {
        String line = upper(withSalutation(salutation, name));
        if (String.isNotBlank(parentName)) {
            // No relation recorded: "C/o." (care of).
            String rel = String.isBlank(relation) ? 'C/o' : clean(relation);
            if (!rel.endsWith('.')) {
                rel += '.';
            }
            line += ', ' + rel + ' ' + upper(parentTitle(rel, parentName));
        }
        return line;
    }

    /**
     * "MR. VIJAY PAL GOEL": the father / husband named after S/o, D/o, W/o or C/o gets "MR.",
     * the wife named after H/o gets "MRS." - unless the name already starts with a title.
     */
    @TestVisible
    private static String parentTitle(String relation, String parentName) {
        String name = clean(parentName);
        String firstWord = name.split('[\\s.]+')[0].toLowerCase();
        if (SALUTATIONS.contains(firstWord) || firstWord == 'sri' || firstWord == 'smt' || firstWord == 'late') {
            return name;
        }
        return (clean(relation).toLowerCase().startsWith('h') ? 'Mrs. ' : 'Mr. ') + name;
    }

    @TestVisible
    private static String withSalutation(String salutation, String name) {
        if (String.isBlank(name)) {
            return '';
        }
        if (String.isBlank(salutation)) {
            return name.trim();
        }
        String title = salutation.trim();
        if (SALUTATIONS.contains(title.toLowerCase())) {
            title += '.';
        }
        return title + ' ' + name.trim();
    }

    @TestVisible
    private static Integer ageFrom(Date dob) {
        if (dob == null) {
            return null;
        }
        Date today = Date.today();
        Integer age = today.year() - dob.year();
        if (today.month() < dob.month() || (today.month() == dob.month() && today.day() < dob.day())) {
            age--;
        }
        return age < 0 ? 0 : age;
    }

    private static String ageText(Integer age) {
        return 'aged about ' + (age == null ? '____' : String.valueOf(age)) + ' years';
    }

    /** 12-digit Aadhaar printed as "2279 5579 9895". */
    @TestVisible
    private static String formatAadhaar(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        String digits = value.replaceAll('[^0-9]', '');
        if (digits.length() != 12) {
            return value.trim();
        }
        return digits.substring(0, 4) + ' ' + digits.substring(4, 8) + ' ' + digits.substring(8, 12);
    }

    /** Plot__c.Floor__c picklist ("G", "3") to "GROUND", "THIRD"; unknown values pass through. */
    @TestVisible
    private static String floorWord(String floorValue) {
        String value = clean(floorValue);
        if (String.isBlank(value)) {
            return '';
        }
        if (value.equalsIgnoreCase('G') || value.equalsIgnoreCase('Ground')) {
            return ORDINALS[0];
        }
        if (!value.isNumeric()) {
            return upper(value);
        }
        Integer n = Integer.valueOf(value);
        if (n >= 0 && n < ORDINALS.size()) {
            return ORDINALS[n];
        }
        Integer lastTwo = Math.mod(n, 100);
        Integer lastOne = Math.mod(n, 10);
        String suffix = (lastTwo >= 11 && lastTwo <= 13) ? 'TH'
            : lastOne == 1 ? 'ST' : lastOne == 2 ? 'ND' : lastOne == 3 ? 'RD' : 'TH';
        return n + suffix;
    }

    /** "West Facing" / "WEST" to "WEST". */
    @TestVisible
    private static String facingWord(String facing) {
        String value = clean(facing);
        if (String.isBlank(value)) {
            return '';
        }
        return upper(value.replaceAll('(?i)\\s*facing\\s*', ' ').trim());
    }

    @TestVisible
    private static String countWord(Integer count) {
        if (count == null || count < 0) {
            return '';
        }
        return count < COUNT_WORDS.size() ? COUNT_WORDS[count] : String.valueOf(count);
    }

    /** "3 BHK" to "3"; text without a number passes through. */
    @TestVisible
    private static String firstNumberIn(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        Matcher m = FIRST_NUMBER.matcher(value);
        return m.find() ? m.group(1) : value.trim();
    }

    /** Up to 3 decimals, trailing zeros removed: 1995 -> "1995", 460.383 -> "460.383", 47.30 -> "47.3". */
    @TestVisible
    private static String formatArea(Decimal value) {
        if (value == null) {
            return '';
        }
        String text = value.setScale(3, RoundingMode.HALF_UP).toPlainString();
        if (text.contains('.')) {
            text = text.replaceAll('0+$', '').replaceAll('\\.$', '');
        }
        return text;
    }

    @TestVisible
    private static String formatDate(Date value) {
        if (value == null) {
            return '';
        }
        return String.valueOf(value.day()).leftPad(2, '0') + '-'
            + String.valueOf(value.month()).leftPad(2, '0') + '-'
            + String.valueOf(value.year());
    }

    /** Indian digit grouping: 8977500 -> "89,77,500"; 1234.5 -> "1,234.50". */
    @TestVisible
    private static String formatIndianNumber(Decimal value) {
        if (value == null) {
            return '';
        }
        Decimal rounded = value.setScale(2, RoundingMode.HALF_UP);
        Boolean isNegative = rounded < 0;
        Decimal absolute = rounded.abs();
        Long wholePart = absolute.longValue();
        Integer paise = ((absolute - wholePart) * 100).intValue();

        String digits = String.valueOf(wholePart);
        String grouped = digits;
        if (digits.length() > 3) {
            String head = digits.left(digits.length() - 3);
            Integer firstGroupLength = Math.mod(head.length(), 2) == 0 ? 2 : 1;
            List<String> groups = new List<String>{ head.left(firstGroupLength) };
            for (Integer i = firstGroupLength; i < head.length(); i += 2) {
                groups.add(head.substring(i, i + 2));
            }
            groups.add(digits.right(3));
            grouped = String.join(groups, ',');
        }
        String result = paise > 0 ? grouped + '.' + String.valueOf(paise).leftPad(2, '0') : grouped;
        return isNegative ? '-' + result : result;
    }

    private static String withSuffix(String value, String suffix) {
        return String.isBlank(value) ? '' : value + suffix;
    }

    private static String titleCase(String upperWord) {
        if (String.isBlank(upperWord)) {
            return '';
        }
        List<String> parts = new List<String>();
        for (String part : upperWord.split(' ')) {
            parts.add(part.length() > 1 ? part.left(1) + part.substring(1).toLowerCase() : part);
        }
        return String.join(parts, ' ');
    }

    private static String clean(String value) {
        return value == null ? '' : value.trim();
    }

    private static String upper(String value) {
        return clean(value).toUpperCase();
    }

    private static String firstNonBlank(List<String> values) {
        for (String value : values) {
            if (String.isNotBlank(value)) {
                return value.trim();
            }
        }
        return '';
    }

    // =====================================================================
    // View models
    // =====================================================================

    public class Vendee {
        public String nameLine { get; set; }
        public String ageText { get; set; }
        public String occupation { get; set; }
        public String address { get; set; }
        public String aadhar { get; set; }
        public String pan { get; set; }
        public Boolean isFirst { get; set; }
        public Boolean isLast { get; set; }

        public Vendee() {
            nameLine = ''; ageText = ''; occupation = ''; address = ''; aadhar = ''; pan = '';
            isFirst = false; isLast = false;
        }
    }

    public class PaymentEntry {
        public String dateText { get; set; }
        public String mode { get; set; }
        public String reference { get; set; }
        public String amountText { get; set; }

        public PaymentEntry() {
            dateText = ''; mode = ''; reference = ''; amountText = '';
        }
    }
}