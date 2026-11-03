/**
 * @description Controller for the BookingForm_LEGACY Visualforce page, which
 *              renders the THE LEGACEY booking form as a PDF for one
 *              Booking__c record (page parameter "id").
 *
 *              Field mapping follows the CreateBooking Aura component, which
 *              is where these fields are captured:
 *                - Flat details     : Booking__c.Plot__c (Unit) and Booking__c.Block__c (Tower)
 *                - First applicant  : Booking__c "Primary Applicant" fields
 *                - Co-applicant     : Booking__c "Second Applicant" fields, otherwise
 *                                     the first Co_Applicant__c record of the booking
 *                - Price details    : Booking__c Financial Summary / New Stage fields
 *
 *              All reads are null safe and respect field-level security
 *              (Security.stripInaccessible), so a blank, missing or hidden field
 *              renders as an empty line instead of failing the PDF.
 */
public with sharing class BookingFormController {

    @TestVisible private static final String PARAM_BOOKING_ID = 'id';
    @TestVisible private static final String MSG_MISSING_ID = 'Booking record ID is missing.';
    @TestVisible private static final String MSG_INVALID_ID = 'Booking record ID is invalid.';
    @TestVisible private static final String MSG_NOT_FOUND = 'Booking record was not found or is not accessible.';
    @TestVisible private static final String MSG_UNEXPECTED = 'Unable to load the booking form. Please contact your administrator.';

    private static final String DATE_FORMAT = 'dd/MM/yyyy';
    private static final String AREA_SUFFIX = ' Sft';
    private static final String CURRENCY_PREFIX = 'Rs. ';
    private static final Decimal ONE_LAKH = 100000;
    /** Amount in a Plot__c.Booking_Amount__c label, e.g. "3" in "3bhk – 3 lakhs". */
    private static final Pattern LAKH_AMOUNT = Pattern.compile('(?i)(\\d+(?:\\.\\d+)?)\\s*(?:lakh|lac)');
    private static final Pattern PLAIN_AMOUNT = Pattern.compile('^\\d+(?:\\.\\d+)?$');

    private static final Set<String> SALUTATIONS = new Set<String>{ 'mr', 'mrs', 'ms', 'dr' };
    private static final Set<String> SELF_FUNDING_TYPES = new Set<String>{ 'self', 'self-funded' };
    private static final Set<String> LOAN_FUNDING_TYPES = new Set<String>{
        'loan', 'nbfc loan', 'mixed funding', 'partial', 'prorata'
    };

    // ---------------------------------------------------------------------
    // Flat details
    // ---------------------------------------------------------------------
    public String bookingNumber { get; private set; }
    public String bookingDate { get; private set; }
    public String towerName { get; private set; }
    public String flatNo { get; private set; }
    public String flatArea { get; private set; }
    public String facing { get; private set; }
    public String flatConfiguration { get; private set; }

    // ---------------------------------------------------------------------
    // First applicant
    // ---------------------------------------------------------------------
    public String applicantName { get; private set; }
    public String applicantFatherName { get; private set; }
    public String applicantPhone { get; private set; }
    public String applicantEmail { get; private set; }
    public String applicantDOB { get; private set; }
    public String applicantOccupation { get; private set; }
    public String applicantAadhar { get; private set; }
    public String applicantPAN { get; private set; }
    public String applicantAddress { get; private set; }

    // ---------------------------------------------------------------------
    // Co-applicant
    // ---------------------------------------------------------------------
    public String coName { get; private set; }
    public String coFatherName { get; private set; }
    public String coPhone { get; private set; }
    public String coEmail { get; private set; }
    public String coDOB { get; private set; }
    public String coOccupation { get; private set; }
    public String coAadhar { get; private set; }
    public String coPAN { get; private set; }
    public String coAddress { get; private set; }

    // ---------------------------------------------------------------------
    // Price details
    // ---------------------------------------------------------------------
    public String finalPrice { get; private set; }
    public String bookingAmountPayable { get; private set; }
    public String advancePaid { get; private set; }
    public String balanceBookingAmount { get; private set; }
    public String tdsPayable { get; private set; }
    public String gstPayable { get; private set; }
    public String gstOnBookingAmount { get; private set; }
    public String loanAmount { get; private set; }
    public Boolean isSelfFunded { get; private set; }
    public Boolean isBankLoan { get; private set; }

    // ---------------------------------------------------------------------
    // Acknowledgement
    // ---------------------------------------------------------------------
    public String chequeNumber { get; private set; }
    public String bankName { get; private set; }

    public String errorMessage { get; private set; }

    public Boolean hasError {
        get { return String.isNotBlank(errorMessage); }
    }

    /**
     * @description Reads the booking id from the page and loads every value
     *              shown on the form. Never throws: any problem is reported
     *              through errorMessage and the form renders with blank lines.
     */
    public BookingFormController() {
        initializeValues();

        Id bookingId = resolveBookingId();
        if (bookingId == null) {
            return;
        }

        try {
            loadForm(bookingId);
        } catch (Exception ex) {
            errorMessage = MSG_UNEXPECTED + ' (' + ex.getTypeName() + ': ' + ex.getMessage()
                + ', line ' + ex.getLineNumber() + ')';
            System.debug(LoggingLevel.ERROR,
                'BookingFormController failed for ' + bookingId + ': '
                + ex.getMessage() + '\n' + ex.getStackTraceString());
        }
    }

    // =====================================================================
    // Loading
    // =====================================================================

    private void initializeValues() {
        bookingNumber = '';
        bookingDate = '';
        towerName = '';
        flatNo = '';
        flatArea = '';
        facing = '';
        flatConfiguration = '';

        applicantName = '';
        applicantFatherName = '';
        applicantPhone = '';
        applicantEmail = '';
        applicantDOB = '';
        applicantOccupation = '';
        applicantAadhar = '';
        applicantPAN = '';
        applicantAddress = '';

        coName = '';
        coFatherName = '';
        coPhone = '';
        coEmail = '';
        coDOB = '';
        coOccupation = '';
        coAadhar = '';
        coPAN = '';
        coAddress = '';

        finalPrice = '';
        bookingAmountPayable = '';
        advancePaid = '';
        balanceBookingAmount = '';
        tdsPayable = '';
        gstPayable = '';
        gstOnBookingAmount = '';
        loanAmount = '';
        isSelfFunded = false;
        isBankLoan = false;

        chequeNumber = '';
        bankName = '';

        errorMessage = '';
    }

    /**
     * @description Validates the "id" page parameter.
     * @return the Booking__c id, or null (with errorMessage set) when invalid
     */
    private Id resolveBookingId() {
        PageReference currentPage = ApexPages.currentPage();
        String idParam = currentPage == null
            ? null
            : currentPage.getParameters().get(PARAM_BOOKING_ID);

        if (String.isBlank(idParam)) {
            errorMessage = MSG_MISSING_ID;
            return null;
        }

        Id bookingId;
        try {
            bookingId = Id.valueOf(idParam.trim());
        } catch (StringException ex) {
            errorMessage = MSG_INVALID_ID;
            return null;
        }

        if (bookingId.getSObjectType() != Booking__c.SObjectType) {
            errorMessage = MSG_INVALID_ID;
            return null;
        }
        return bookingId;
    }

    private void loadForm(Id bookingId) {
        Booking__c booking = queryBooking(bookingId);
        if (booking == null) {
            errorMessage = MSG_NOT_FOUND;
            return;
        }

        mapFlatDetails(booking);
        mapApplicant(booking);
        mapCoApplicant(booking);
        mapPriceDetails(booking);
        mapAcknowledgement(booking);
    }

    private static Booking__c queryBooking(Id bookingId) {
        List<Booking__c> bookings = [
            SELECT Id, Name, Booking_Date__c, Date_of_Booking__c, CreatedDate,
                   Facing__c, BHK_Type__c,
                   Block__r.Name,
                   Plot__r.Name, Plot__r.Booking_Amount__c,
                   Plot__r.Saleable_Area_Sft__c, Plot__r.Super_built_up_area__c,
                   Plot__r.Built_up_area__c, Plot__r.Facing__c,
                   Plot__r.BHK_Type__c, Plot__r.Tower__c, Plot__r.Block1__r.Name,

                   salutation_Applicant1__c, First_Applicant_Name__c,
                   Son_Daughter_Wife_of__c, Mobile_Primary__c, Mobile__c,
                   Email1__c, Email__c, Customer_Email__c,
                   Date_of_Birth1__c, Date_of_Birth__c, Occupation__c,
                   Aadhaar_Number__c, Aadhaar__c, PAN_Number1__c, PAN_Number__c,
                   Address__c, Permanent_Address__c,
                   Communication_address__c, Correspondence_Address__c,

                   salutation_Applicant2__c, Second_Applicant_Name__c,
                   Son_Daughter_Wife_of1__c, Mobile_Primary1__c, Email2__c,
                   Date_of_birth_Applicant2__c, Occupation1__c,
                   Aadhaar_Number1__c, Pan_Number_Applicant2__c,
                   Permanent_Address1__c, Communication_address1__c,

                   Total_Flat_Cost__c, GST_Amount__c, GST__c,
                   Booking_Amount__c, TDS__c,
                   Funding_Type__c, Loan_Sanctioned_Amount__c,
                   Cheque_Transaction_No__c, Cheque_DD_NEFT_RTGS_No__c,
                   Bank_Name__c
            FROM Booking__c
            WHERE Id = :bookingId
            LIMIT 1
        ];

        List<SObject> readable = stripInaccessible(bookings);
        return readable.isEmpty() ? null : (Booking__c) readable[0];
    }

    private static Co_Applicant__c queryFirstCoApplicant(Id bookingId) {
        List<Co_Applicant__c> coApplicants = [
            SELECT Id, Salutation__c, Full_Name__c, First_Name__c, Last_Name__c,
                   W_o_S_o_C_o_c__c, Contact_Number__c, Mobile__c, Email__c,
                   Date_of_Birth__c, Occupation__c, Aadhar_Number__c,
                   PAN_Number__c, Permenent_Address__c, Address__c
            FROM Co_Applicant__c
            WHERE Booking__c = :bookingId
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        List<SObject> readable = stripInaccessible(coApplicants);
        return readable.isEmpty() ? null : (Co_Applicant__c) readable[0];
    }

    // =====================================================================
    // Field mapping
    // =====================================================================

    private void mapFlatDetails(Booking__c booking) {
        SObject unit = parentOf(booking, 'Plot__r');
        SObject bookingTower = parentOf(booking, 'Block__r');
        SObject unitTower = parentOf(unit, 'Block1__r');

        bookingNumber = textOf(booking, 'Name');
        bookingDate = firstNonBlank(new List<String>{
            textOf(booking, 'Booking_Date__c'),
            textOf(booking, 'Date_of_Booking__c'),
            textOf(booking, 'CreatedDate')
        });
        towerName = firstNonBlank(new List<String>{
            textOf(bookingTower, 'Name'),
            textOf(unitTower, 'Name'),
            textOf(unit, 'Tower__c')
        });
        flatNo = textOf(unit, 'Name');
        flatArea = formatArea(firstPositive(new List<Decimal>{
            decimalOf(unit, 'Saleable_Area_Sft__c'),
            decimalOf(unit, 'Super_built_up_area__c'),
            decimalOf(unit, 'Built_up_area__c')
        }));
        facing = firstNonBlank(new List<String>{
            textOf(unit, 'Facing__c'),
            textOf(booking, 'Facing__c')
        });
        flatConfiguration = firstNonBlank(new List<String>{
            textOf(unit, 'BHK_Type__c'),
            textOf(booking, 'BHK_Type__c')
        });
    }

    private void mapApplicant(Booking__c booking) {
        applicantName = withSalutation(
            textOf(booking, 'salutation_Applicant1__c'),
            textOf(booking, 'First_Applicant_Name__c')
        );
        applicantFatherName = textOf(booking, 'Son_Daughter_Wife_of__c');
        applicantPhone = firstText(booking, new List<String>{ 'Mobile_Primary__c', 'Mobile__c' });
        applicantEmail = firstText(booking, new List<String>{ 'Email1__c', 'Email__c', 'Customer_Email__c' });
        applicantDOB = firstText(booking, new List<String>{ 'Date_of_Birth1__c', 'Date_of_Birth__c' });
        applicantOccupation = textOf(booking, 'Occupation__c');
        applicantAadhar = firstText(booking, new List<String>{ 'Aadhaar_Number__c', 'Aadhaar__c' });
        applicantPAN = firstText(booking, new List<String>{ 'PAN_Number1__c', 'PAN_Number__c' });
        applicantAddress = firstText(booking, new List<String>{
            'Address__c', 'Permanent_Address__c',
            'Communication_address__c', 'Correspondence_Address__c'
        });
    }

    /**
     * @description Uses the Second Applicant captured on the booking; when it
     *              is blank, falls back to the first Co_Applicant__c record.
     */
    private void mapCoApplicant(Booking__c booking) {
        String secondApplicantName = textOf(booking, 'Second_Applicant_Name__c');

        if (String.isNotBlank(secondApplicantName)) {
            coName = withSalutation(textOf(booking, 'salutation_Applicant2__c'), secondApplicantName);
            coFatherName = textOf(booking, 'Son_Daughter_Wife_of1__c');
            coPhone = textOf(booking, 'Mobile_Primary1__c');
            coEmail = textOf(booking, 'Email2__c');
            coDOB = textOf(booking, 'Date_of_birth_Applicant2__c');
            coOccupation = textOf(booking, 'Occupation1__c');
            coAadhar = textOf(booking, 'Aadhaar_Number1__c');
            coPAN = textOf(booking, 'Pan_Number_Applicant2__c');
            coAddress = firstText(booking, new List<String>{
                'Permanent_Address1__c', 'Communication_address1__c'
            });
            return;
        }

        Co_Applicant__c coApplicant = queryFirstCoApplicant(booking.Id);
        if (coApplicant == null) {
            return;
        }

        String fullName = firstNonBlank(new List<String>{
            textOf(coApplicant, 'Full_Name__c'),
            joinNonBlank(new List<String>{
                textOf(coApplicant, 'First_Name__c'),
                textOf(coApplicant, 'Last_Name__c')
            })
        });

        coName = withSalutation(textOf(coApplicant, 'Salutation__c'), fullName);
        coFatherName = textOf(coApplicant, 'W_o_S_o_C_o_c__c');
        coPhone = firstText(coApplicant, new List<String>{ 'Contact_Number__c', 'Mobile__c' });
        coEmail = textOf(coApplicant, 'Email__c');
        coDOB = textOf(coApplicant, 'Date_of_Birth__c');
        coOccupation = textOf(coApplicant, 'Occupation__c');
        coAadhar = textOf(coApplicant, 'Aadhar_Number__c');
        coPAN = textOf(coApplicant, 'PAN_Number__c');
        coAddress = firstText(coApplicant, new List<String>{ 'Permenent_Address__c', 'Address__c' });
    }

    /**
     * @description Price details are read straight from the records:
     *                - Booking Amount Payable : Plot__c.Booking_Amount__c (picklist,
     *                                           e.g. "3bhk – 3 lakhs" = Rs. 3,00,000)
     *                - Everything else        : Booking__c Financial Summary /
     *                                           New Stage fields
     *              Only the two lines that have no field are derived:
     *                - Balance Booking Amount = Booking Amount Payable - Advance Paid
     *                - GST On Booking Amount  = Booking Amount Payable x GST %
     */
    private void mapPriceDetails(Booking__c booking) {
        Decimal flatCost = decimalOf(booking, 'Total_Flat_Cost__c');
        Decimal gstAmount = decimalOf(booking, 'GST_Amount__c');
        String plotBookingAmount = textOf(parentOf(booking, 'Plot__r'), 'Booking_Amount__c');
        Decimal bookingAmount = parseLakhAmount(plotBookingAmount);
        Decimal advance = decimalOf(booking, 'Booking_Amount__c');

        Decimal balance = null;
        if (bookingAmount != null) {
            Decimal remaining = bookingAmount - (advance == null ? 0 : advance);
            balance = remaining > 0 ? remaining : 0;
        }

        finalPrice = formatAmount(flatCost);
        // Shows the picklist label as-is if it holds no recognisable amount.
        bookingAmountPayable = bookingAmount != null
            ? formatAmount(bookingAmount)
            : plotBookingAmount;
        advancePaid = formatAmount(advance);
        balanceBookingAmount = formatAmount(balance);
        tdsPayable = formatAmount(decimalOf(booking, 'TDS__c'));
        gstPayable = formatAmount(gstAmount);
        gstOnBookingAmount = formatAmount(
            percentOf(bookingAmount, gstPercentOf(booking, flatCost, gstAmount))
        );
        loanAmount = formatAmount(decimalOf(booking, 'Loan_Sanctioned_Amount__c'));

        String fundingType = textOf(booking, 'Funding_Type__c').toLowerCase();
        isSelfFunded = SELF_FUNDING_TYPES.contains(fundingType);
        isBankLoan = LOAN_FUNDING_TYPES.contains(fundingType);
    }

    /**
     * @description GST % from Booking__c.GST__c; when blank, the booking's own
     *              rate GST_Amount__c / Total_Flat_Cost__c x 100.
     */
    private static Decimal gstPercentOf(Booking__c booking, Decimal flatCost, Decimal gstAmount) {
        Decimal gstPercent = decimalOf(booking, 'GST__c');
        if (gstPercent != null) {
            return gstPercent;
        }
        if (flatCost == null || flatCost == 0 || gstAmount == null) {
            return null;
        }
        return gstAmount * 100 / flatCost;
    }

    private void mapAcknowledgement(Booking__c booking) {
        chequeNumber = firstText(booking, new List<String>{
            'Cheque_Transaction_No__c', 'Cheque_DD_NEFT_RTGS_No__c'
        });
        bankName = textOf(booking, 'Bank_Name__c');
    }

    // =====================================================================
    // Null-safe helpers
    // =====================================================================

    /**
     * @description Removes fields the running user cannot read. Fields that
     *              are removed simply come back blank through valueOf().
     */
    private static List<SObject> stripInaccessible(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return new List<SObject>();
        }
        return Security.stripInaccessible(AccessType.READABLE, records).getRecords();
    }

    /**
     * @description Reads a queried field without ever throwing: null record,
     *              stripped field or blank value all return null.
     */
    private static Object valueOf(SObject record, String fieldName) {
        if (record == null || String.isBlank(fieldName)) {
            return null;
        }
        Map<String, Object> populated = record.getPopulatedFieldsAsMap();
        return populated.containsKey(fieldName) ? populated.get(fieldName) : null;
    }

    private static SObject parentOf(SObject record, String relationshipName) {
        Object parent = valueOf(record, relationshipName);
        return parent instanceof SObject ? (SObject) parent : null;
    }

    @TestVisible
    private static String textOf(SObject record, String fieldName) {
        Object rawValue = valueOf(record, fieldName);

        if (rawValue == null) {
            return '';
        }
        // Apex treats Date and Datetime as instanceof each other, so the
        // field's schema type decides how the value is formatted.
        if (rawValue instanceof Date || rawValue instanceof Datetime) {
            Schema.DisplayType fieldType = fieldTypeOf(record, fieldName);
            if (fieldType == Schema.DisplayType.DATE) {
                return formatDate((Date) rawValue);
            }
            if (fieldType == Schema.DisplayType.DATETIME) {
                return ((Datetime) rawValue).format(DATE_FORMAT);
            }
        }
        return String.valueOf(rawValue).trim();
    }

    /** Field maps per object, so each object is described only once per request. */
    private static final Map<Schema.SObjectType, Map<String, Schema.SObjectField>> FIELD_MAP_CACHE =
        new Map<Schema.SObjectType, Map<String, Schema.SObjectField>>();

    private static Schema.DisplayType fieldTypeOf(SObject record, String fieldName) {
        Schema.SObjectType objectType = record.getSObjectType();
        if (!FIELD_MAP_CACHE.containsKey(objectType)) {
            FIELD_MAP_CACHE.put(objectType, objectType.getDescribe().fields.getMap());
        }
        Schema.SObjectField field = FIELD_MAP_CACHE.get(objectType).get(fieldName);
        return field == null ? null : field.getDescribe().getType();
    }

    private static Decimal decimalOf(SObject record, String fieldName) {
        Object rawValue = valueOf(record, fieldName);
        return rawValue instanceof Decimal ? (Decimal) rawValue : null;
    }

    private static String firstText(SObject record, List<String> fieldNames) {
        for (String fieldName : fieldNames) {
            String value = textOf(record, fieldName);
            if (String.isNotBlank(value)) {
                return value;
            }
        }
        return '';
    }

    private static String firstNonBlank(List<String> values) {
        for (String value : values) {
            if (String.isNotBlank(value)) {
                return value;
            }
        }
        return '';
    }

    private static Decimal firstPositive(List<Decimal> values) {
        for (Decimal value : values) {
            if (value != null && value > 0) {
                return value;
            }
        }
        return null;
    }

    private static String joinNonBlank(List<String> values) {
        List<String> parts = new List<String>();
        for (String value : values) {
            if (String.isNotBlank(value)) {
                parts.add(value);
            }
        }
        return String.join(parts, ' ');
    }

    private static Decimal percentOf(Decimal amount, Decimal percent) {
        if (amount == null || percent == null) {
            return null;
        }
        return amount * percent / 100;
    }

    // =====================================================================
    // Formatting
    // =====================================================================

    @TestVisible
    private static String withSalutation(String salutation, String name) {
        if (String.isBlank(name)) {
            return '';
        }
        if (String.isBlank(salutation)) {
            return name;
        }
        String title = salutation.trim();
        if (SALUTATIONS.contains(title.toLowerCase())) {
            title += '.';
        }
        return title + ' ' + name;
    }

    @TestVisible
    private static String formatDate(Date value) {
        if (value == null) {
            return '';
        }
        return String.valueOf(value.day()).leftPad(2, '0') + '/'
            + String.valueOf(value.month()).leftPad(2, '0') + '/'
            + String.valueOf(value.year());
    }

    /**
     * @description Converts a Plot__c.Booking_Amount__c picklist label to rupees:
     *              "3bhk – 3 lakhs" -> 300000, "2.5 lakh" -> 250000,
     *              "300000" -> 300000. Returns null when no amount is found.
     */
    @TestVisible
    private static Decimal parseLakhAmount(String label) {
        if (String.isBlank(label)) {
            return null;
        }
        Matcher lakhMatch = LAKH_AMOUNT.matcher(label);
        if (lakhMatch.find()) {
            return Decimal.valueOf(lakhMatch.group(1)) * ONE_LAKH;
        }
        String digits = label.replaceAll('[,\\s]', '');
        return PLAIN_AMOUNT.matcher(digits).matches() ? Decimal.valueOf(digits) : null;
    }

    @TestVisible
    private static String formatArea(Decimal area) {
        if (area == null) {
            return '';
        }
        return formatIndianNumber(area) + AREA_SUFFIX;
    }

    @TestVisible
    private static String formatAmount(Decimal amount) {
        if (amount == null) {
            return '';
        }
        return CURRENCY_PREFIX + formatIndianNumber(amount);
    }

    /**
     * @description Formats a number with Indian digit grouping
     *              (e.g. 1234567.5 -> "12,34,567.50"); whole numbers have no decimals.
     */
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
            // Indian grouping: last 3 digits, then groups of 2 (12,34,567).
            // Built left to right with add() only; Apex List.add(0, x) on an
            // empty list throws "List index out of bounds: 0".
            String head = digits.left(digits.length() - 3);
            Integer firstGroupLength = Math.mod(head.length(), 2) == 0 ? 2 : 1;

            List<String> groups = new List<String>{ head.left(firstGroupLength) };
            for (Integer i = firstGroupLength; i < head.length(); i += 2) {
                groups.add(head.substring(i, i + 2));
            }
            groups.add(digits.right(3));
            grouped = String.join(groups, ',');
        }

        String result = paise > 0
            ? grouped + '.' + String.valueOf(paise).leftPad(2, '0')
            : grouped;
        return isNegative ? '-' + result : result;
    }
}
