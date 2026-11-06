/**
 * Controller extension for the landowner / builder-share "Agreement of Sale"
 * Visualforce PDFs (ARJUN_SINGH_, MAGHAN_SINGH_, SURESH_SINGH_, NAVEEN_SINGH_,
 * NITIN_SINGH_ and BUILDER_SHARE_AGREEMENT_OF_SALE) and for THE DRIZZLE builder
 * agreements (SaleAgreementDrizzil and MortgageAgreementofSaleDrizzle).
 *
 * The landowner whose template is being rendered is derived from the page
 * name. The units that belong to that landowner are identified by the
 * Plot__c.LL_Share_Name__c picklist ("LL Share Name").
 */
public with sharing class AgreementOfSaleController {
    private static final Set<String> APPROVED_RECEIPT_STATUSES = new Set<String>{
        'Approved', 'Approved by Finance Team'
    };

    /**
     * Receipt types that are not flat payments; the same types the
     * Booking__c.Total_Received_Flat_Amount__c roll-up excludes.
     */
    private static final Set<String> NON_FLAT_RECEIPT_TYPES = new Set<String>{
        'GST Amount', 'Additional Charge'
    };

    /** Page-name fragment -> LL_Share_Name__c picklist value. */
    private static final Map<String, String> PAGE_OWNERS = new Map<String, String>{
        'ARJUN_SINGH_AGREEMENT_OF_SALE'  => 'ARJUN SINGH',
        'MAGHAN_SINGH_AGREEMENT_OF_SALE' => 'MAGAN SINGH',
        'SURESH_SINGH_AGREEMENT_OF_SALE' => 'SURESH SINGH',
        'NAVEEN_SINGH_AGREEMENT_OF_SALE' => 'NAVEEN SINGH',
        'NITIN_SINGH_AGREEMENT_OF_SALE'  => 'NITIN SINGH'
    };

    /** LL_Share_Name__c value -> name printed in the vendor unit table. */
    private static final Map<String, String> OWNER_DISPLAY_NAMES = new Map<String, String>{
        'ARJUN SINGH'  => 'Sri.K.Arjun Singh',
        'MAGAN SINGH'  => 'Sri. Magan Singh',
        'SURESH SINGH' => 'Sri.K. Suresh Singh',
        'NAVEEN SINGH' => 'Sri. Naveen Singh',
        'NITIN SINGH'  => 'Sri. Nithin Singh'
    };

    public class ApplicantEntry {
        public Integer sequence { get; private set; }
        public String salutation { get; private set; }
        public String name { get; private set; }
        public String relation { get; private set; }
        public String age { get; private set; }
        public String occupation { get; private set; }
        public String address { get; private set; }
        public String addressPrefix { get; private set; }
        public String aadhaar { get; private set; }
        public String pan { get; private set; }
        public String email { get; private set; }
        /** Salutation exactly as stored on the record (Mr, Mrs., ...). */
        public String rawSalutation { get; private set; }

        // ---- THE DRIZZLE wording: "MR. NAME, S/o. MR. FATHER, aged about 29 years, Occupation: X; R/o: ..."

        /** e.g. "MR. ANIL DEMO JUNIOR" */
        public String getDrizzleName() {
            String upperName = name == null ? '' : name.trim().toUpperCase();
            if (String.isBlank(rawSalutation)) {
                return upperName;
            }
            String prefix = rawSalutation.trim().toUpperCase();
            if (!prefix.endsWith('.')) {
                prefix += '.';
            }
            return prefix + ' ' + upperName;
        }

        /** e.g. "S/o. MR. SURESH DEMO SENIOR" (empty when no relation is recorded). */
        public String getDrizzleRelation() {
            if (String.isBlank(relation)) {
                return '';
            }
            String label = relation.substringBefore(' ');
            String relative = relation.substringAfter(' ');
            Map<String, String> labels = new Map<String, String>{
                'S/O.' => 'S/o.', 'D/O.' => 'D/o.', 'W/O.' => 'W/o.', 'H/O.' => 'H/o.', 'C/O.' => 'C/o.'
            };
            if (labels.containsKey(label)) {
                label = labels.get(label);
            }
            if (relative.startsWith('SRI. ')) {
                relative = 'MR. ' + relative.substring(5);
            }
            return label + ' ' + relative;
        }

        /** e.g. "MR. A, S/o. MR. B," - the bold opening of the allottee paragraph. */
        public String getDrizzleNameLine() {
            String rel = getDrizzleRelation();
            return getDrizzleName() + (String.isBlank(rel) ? ',' : ', ' + rel + ',');
        }

        /** e.g. "aged about 29 years, Occupation: Pvt. Employee; R/o: 1-2-3, ..." */
        public String getDrizzleDetails() {
            List<String> parts = new List<String>();
            if (!String.isBlank(age)) {
                parts.add('aged about ' + age + ' years');
            }
            if (!String.isBlank(occupation)) {
                parts.add('Occupation: ' + occupation.trim());
            }
            String text = String.join(parts, ', ');
            if (!String.isBlank(address)) {
                String addr = address.trim();
                text += (String.isBlank(text) ? '' : '; ') + 'R/o: ' + addr + (addr.endsWith('.') ? '' : '.');
            }
            return text;
        }

        /** e.g. "(AADHAR NO: 1234 1234 1234, PAN NO: PQRST3456U)." */
        public String getDrizzleIds() {
            return '(AADHAR NO: ' + formatAadhaar(aadhaar) + ', PAN NO: ' +
                (pan == null ? '' : pan.trim().toUpperCase()) + ').';
        }

        /** e.g. "SRI. RAVI KUMAR SAMPLE" */
        public String getDisplayName() {
            String upperName = name == null ? '' : name.trim().toUpperCase();
            return String.isBlank(salutation) ? upperName : salutation.toUpperCase() + ' ' + upperName;
        }

        /**
         * e.g. "S/O. SRI. MOHAN RAO SAMPLE, aged about 30 years,
         * Occupation: Private Employee, Resident of ..., (AADHAAR No. X & PAN No. Y)"
         */
        public String getLegalDetails() {
            List<String> details = new List<String>();
            if (!String.isBlank(relation)) {
                details.add(relation);
            }
            if (!String.isBlank(age)) {
                details.add('aged about ' + age + ' years');
            }
            if (!String.isBlank(occupation)) {
                details.add('Occupation: ' + occupation);
            }
            if (!String.isBlank(address)) {
                details.add(addressPrefix + address.trim());
            }
            details.add(
                '(AADHAAR No. ' + (aadhaar == null ? '' : aadhaar.trim()) +
                ' & PAN No. ' + (pan == null ? '' : pan.trim()) + ')'
            );
            return String.join(details, ', ');
        }

        // ---- ARJUN_SINGH_AGREEMENT_OF_SALE wording, split by weight as in the deed:
        // bold "SRI. NAME, S/O. SRI. FATHER, " + regular "aged about .. years,
        // Occupation: .., Resident of ... " + bold "(AADHAAR No. X & PAN No. Y)".

        /** e.g. "SRI. RAVI KUMAR, S/O. SRI. MOHAN RAO, " (bold part). */
        public String getDeedNameLine() {
            String line = getDisplayName();
            if (!String.isBlank(relation)) {
                line += ', ' + relation;
            }
            return line + ', ';
        }

        /**
         * MAGHAN_SINGH_AGREEMENT_OF_SALE wording (no comma before the relation):
         * e.g. "SRI. RAVI KUMAR S/O. SRI. MOHAN RAO, " (bold part).
         */
        public String getDeedNameRelationLine() {
            String line = getDisplayName();
            if (!String.isBlank(relation)) {
                line += ' ' + relation;
            }
            return line + ', ';
        }

        /** e.g. "aged about 30 years, Occupation: Business, Resident of Hyderabad. " */
        public String getDeedDetails() {
            List<String> details = new List<String>();
            if (!String.isBlank(age)) {
                details.add('aged about ' + age + ' years');
            }
            if (!String.isBlank(occupation)) {
                details.add('Occupation: ' + occupation.trim());
            }
            if (!String.isBlank(address)) {
                details.add((addressPrefix == null ? '' : addressPrefix) + address.trim());
            }
            if (details.isEmpty()) {
                return '';
            }
            String text = String.join(details, ', ');
            return text + (text.endsWith('.') ? ' ' : '. ');
        }

        /** e.g. "(AADHAAR No. 1234 5678 9012 & PAN No. ABCDE1234F)" (bold part). */
        public String getDeedIds() {
            return '(AADHAAR No. ' + (aadhaar == null ? '' : aadhaar.trim()) +
                ' & PAN No. ' + (pan == null ? '' : pan.trim()) + ')';
        }

        private ApplicantEntry(
            Integer sequence,
            String salutation,
            String name,
            String relation,
            Date dateOfBirth,
            String occupation,
            String address,
            String addressPrefix,
            String aadhaar,
            String pan,
            String email
        ) {
            this.sequence = sequence;
            this.salutation = salutation;
            this.name = name;
            this.relation = relation;
            this.age = getAge(dateOfBirth);
            this.occupation = occupation;
            this.address = address;
            this.addressPrefix = addressPrefix;
            this.aadhaar = aadhaar;
            this.pan = pan;
            this.email = email;
        }
    }

    public class OwnerUnitRow {
        public Plot__c unit { get; private set; }
        public Integer sequence { get; private set; }

        private OwnerUnitRow(Plot__c unit, Integer sequence) {
            this.unit = unit;
            this.sequence = sequence;
        }

        /**
         * Tower number/label for the unit. The "T1-707" style unit name is the
         * most reliable source, then Tower Block, then the Tower picklist.
         */
        private String rawTower() {
            if (!String.isBlank(unit.Name)) {
                Matcher nameMatch = Pattern.compile('(?i)^T?\\s*(\\d+)\\s*-').matcher(unit.Name.trim());
                if (nameMatch.find()) {
                    return nameMatch.group(1);
                }
            }
            if (!String.isBlank(unit.Tower_Block__c)) {
                return unit.Tower_Block__c;
            }
            return unit.Tower__c;
        }

        /** "T-05" style tower label used in the vendor unit table. */
        public String getTowerDisplay() {
            String tower = rawTower();
            if (String.isBlank(tower)) {
                return '';
            }

            Matcher towerMatch = Pattern.compile('(?i)^(?:T(?:OWER)?)?\\s*-?\\s*(\\d+)$').matcher(tower.trim());
            if (!towerMatch.matches()) {
                return tower.trim();
            }

            String towerNumber = towerMatch.group(1);
            return 'T-' + (towerNumber.length() == 1 ? '0' : '') + towerNumber;
        }

        /** "7th" / "Ground" */
        public String getFloorDisplay() {
            if (String.isBlank(unit.Floor__c)) {
                return '';
            }
            String floorValue = unit.Floor__c.trim();
            if (floorValue.equalsIgnoreCase('G') || floorValue.equalsIgnoreCase('Ground')) {
                return 'Ground';
            }

            Matcher floorMatch = Pattern.compile('^(\\d+)').matcher(floorValue);
            if (!floorMatch.find()) {
                return floorValue;
            }

            Integer floorNumber = Integer.valueOf(floorMatch.group(1));
            Integer lastTwoDigits = Integer.valueOf(Math.mod(floorNumber, 100));
            Integer finalDigit = Integer.valueOf(Math.mod(floorNumber, 10));
            String suffix = lastTwoDigits >= 11 && lastTwoDigits <= 13
                ? 'th'
                : finalDigit == 1
                    ? 'st'
                    : finalDigit == 2
                        ? 'nd'
                        : finalDigit == 3
                            ? 'rd'
                            : 'th';
            return String.valueOf(floorNumber) + suffix;
        }

        /** Flat number without the tower prefix, e.g. "707" for unit "T1-707". */
        public String getFlatNumber() {
            if (!String.isBlank(unit.Plot_Number__c)) {
                return unit.Plot_Number__c.trim();
            }
            if (String.isBlank(unit.Name)) {
                return '';
            }

            Matcher nameMatch = Pattern.compile('(?i)^T?\\s*\\d*\\s*-\\s*(.+)$').matcher(unit.Name.trim());
            return nameMatch.matches() ? nameMatch.group(1).trim() : unit.Name.trim();
        }

        /** "East" (the picklist value without the trailing " Facing"). */
        public String getFacingDisplay() {
            if (String.isBlank(unit.Facing__c)) {
                return '';
            }
            String suffix = ' Facing';
            String facing = unit.Facing__c.trim();
            return facing.toLowerCase().endsWith(suffix.toLowerCase())
                ? facing.substring(0, facing.length() - suffix.length())
                : facing;
        }
    }

    /** One row of THE DRIZZLE price tables: amount, GST and total. */
    public class ChargeLine {
        public String label { get; private set; }
        public String rateText { get; private set; }
        public Decimal amount { get; private set; }
        /** null = GST not applicable to this head. */
        public Decimal gst { get; private set; }

        private ChargeLine(String label, String rateText, Decimal amount, Decimal gst) {
            this.label = label;
            this.rateText = rateText;
            this.amount = amount;
            this.gst = gst;
        }

        public Decimal getTotal() {
            return amount == null ? null : amount + (gst == null ? 0 : gst);
        }

        public String getAmountDisplay() {
            return formatIndianCurrency(amount);
        }

        /** GST column of the price tables ("NA" when GST does not apply). */
        public String getGstDisplay() {
            if (amount == null) {
                return '';
            }
            return gst == null ? 'NA' : formatIndianCurrency(gst);
        }

        /** GST column of Schedule-C ("0" when GST does not apply). */
        public String getGstOrZeroDisplay() {
            if (amount == null) {
                return '';
            }
            return gst == null ? '0' : formatIndianCurrency(gst);
        }

        public String getTotalDisplay() {
            return formatIndianCurrency(getTotal());
        }
    }

    public class ReceiptRow {
        private Receipt__c receipt;

        private ReceiptRow(Receipt__c receipt) {
            this.receipt = receipt;
        }

        public String getMode() {
            if (!String.isBlank(receipt.Mode_of_payment__c)) {
                return receipt.Mode_of_payment__c;
            }
            return receipt.Receipt_Type__c;
        }

        public Date getReceiptDate() {
            return receipt.Receipt_Date__c;
        }

        public String getReferenceId() {
            if (!String.isBlank(receipt.Payment_Reference_Number__c)) {
                return receipt.Payment_Reference_Number__c;
            }
            if (!String.isBlank(receipt.Cheque_Number__c)) {
                return receipt.Cheque_Number__c;
            }
            return receipt.Check_Transaction_Nmber__c;
        }

        public String getAmountDisplay() {
            return formatIndianCurrency(receipt.Amount_received__c);
        }

        public String getReceiptType() {
            return receipt.Receipt_Type__c;
        }

        /** MAGHAN receipts table "Mode": Receipt__c.Payment_Method__c ('' when blank). */
        public String getPaymentMethod() {
            return String.isBlank(receipt.Payment_Method__c) ? '' : receipt.Payment_Method__c;
        }

        public Decimal getAmount() {
            return receipt.Amount_received__c;
        }
    }

    public class PaymentScheduleRow {
        private Payment_Schedule__c schedule;

        private PaymentScheduleRow(Payment_Schedule__c schedule) {
            this.schedule = schedule;
        }

        public String getInstallmentName() {
            if (!String.isBlank(schedule.Milestone_Name__c)) {
                return schedule.Milestone_Name__c;
            }
            return !String.isBlank(schedule.Payment_Schedule_Name__c)
                ? schedule.Payment_Schedule_Name__c
                : schedule.Name;
        }

        public String getDescription() {
            return schedule.Description__c;
        }

        public Decimal getPercentage() {
            return schedule.Percentage__c;
        }

        /** Base amount (+ TDS) excluding GST. */
        public Decimal getFlatCost() {
            return schedule.Flat_Cost__c;
        }

        public Decimal getGstAmount() {
            return schedule.GST_Amount__c;
        }

        /** Net amount including GST. */
        public Decimal getNetAmount() {
            if (schedule.Amount__c != null) {
                return schedule.Amount__c;
            }
            if (schedule.Flat_Cost__c == null) {
                return null;
            }
            return schedule.Flat_Cost__c + (schedule.GST_Amount__c == null ? 0 : schedule.GST_Amount__c);
        }

        public String getFlatCostDisplay() {
            return formatIndianCurrency(getFlatCost());
        }

        public String getGstAmountDisplay() {
            return formatIndianCurrency(getGstAmount());
        }

        public String getNetAmountDisplay() {
            return formatIndianCurrency(getNetAmount());
        }
    }

    public List<OwnerUnitRow> ownerUnits { get; private set; }
    public List<ApplicantEntry> applicants { get; private set; }
    public List<ReceiptRow> receiptRows { get; private set; }
    public List<PaymentScheduleRow> paymentScheduleRows { get; private set; }
    public Booking__c booking { get; private set; }
    public Plot__c selectedUnit { get; private set; }
    public String buyerNames { get; private set; }
    public String ownerName { get; private set; }
    public String ownerDisplayName { get; private set; }
    public Boolean isBuilderSharePage { get; private set; }
    public Decimal totalOwnerSaleableArea { get; private set; }
    public Decimal totalReceiptAmount { get; private set; }
    public Decimal totalScheduleFlatCost { get; private set; }
    public Decimal totalScheduleGst { get; private set; }
    public Decimal totalScheduleNetAmount { get; private set; }
    public Decimal totalSchedulePercentage { get; private set; }

    // THE DRIZZLE price break-up
    public List<ChargeLine> drizzlePriceLines { get; private set; }
    public ChargeLine drizzlePriceTotal { get; private set; }
    public List<ChargeLine> drizzleOtherLines { get; private set; }
    public ChargeLine drizzleOtherTotal { get; private set; }
    public ChargeLine drizzleCorpusLine { get; private set; }
    public ChargeLine drizzleMaintenanceLine { get; private set; }
    public ChargeLine drizzleLegalLine { get; private set; }

    public Boolean getHasApplicants() {
        return applicants != null && !applicants.isEmpty();
    }

    public Boolean getHasSelectedUnit() {
        return selectedUnit != null;
    }

    public Boolean getHasOwnerUnits() {
        return ownerUnits != null && !ownerUnits.isEmpty();
    }

    public Boolean getHasReceipts() {
        return receiptRows != null && !receiptRows.isEmpty();
    }

    public Boolean getHasPaymentSchedules() {
        return paymentScheduleRows != null && !paymentScheduleRows.isEmpty();
    }

    public AgreementOfSaleController(ApexPages.StandardController standardController) {
        ownerUnits = new List<OwnerUnitRow>();
        applicants = new List<ApplicantEntry>();
        receiptRows = new List<ReceiptRow>();
        paymentScheduleRows = new List<PaymentScheduleRow>();
        drizzlePriceLines = new List<ChargeLine>();
        drizzleOtherLines = new List<ChargeLine>();
        drizzlePriceTotal = new ChargeLine('Total', '', null, null);
        drizzleOtherTotal = new ChargeLine('Total', '', null, null);
        drizzleCorpusLine = new ChargeLine('', '', null, null);
        drizzleMaintenanceLine = new ChargeLine('', '', null, null);
        drizzleLegalLine = new ChargeLine('', '', null, null);
        totalOwnerSaleableArea = 0;
        totalReceiptAmount = 0;
        totalScheduleFlatCost = 0;
        totalScheduleGst = 0;
        totalScheduleNetAmount = 0;
        totalSchedulePercentage = 0;
        buyerNames = '';
        ownerDisplayName = '';
        String pageUrl = currentPageUrl();
        // Builder (developer share) templates: the unit must not belong to a landowner.
        isBuilderSharePage = pageUrl.contains('BUILDER_SHARE_AGREEMENT_OF_SALE') ||
            pageUrl.contains('SALEAGREEMENTDRIZZIL') ||
            pageUrl.contains('MORTGAGEAGREEMENTOFSALEDRIZZLE');
        if (standardController == null || standardController.getId() == null) {
            return;
        }

        booking = [
            SELECT Id, Project__c, Plot__c, Car_Parking_Selected__c, No_of_car_parking__c,
                   First_Applicant_Name__c, Second_Applicant_Name__c,
                   // primary applicant (legacy field set)
                   Salutation__c, Date_of_Birth__c, Occupation__c, Permanent_Address__c,
                   Aadhaar__c, PAN_Number__c, Email1__c, S_o_D_o_W_o__c, Son_Daughter_Wife_of__c,
                   Primary_Applicant_Age__c,
                   // primary applicant (booking form field set)
                   salutation_Applicant1__c, Date_of_Birth1__c, Designation__c, Address__c,
                   Communication_address__c, Aadhaar_Number__c, PAN_Number1__c, Email__c,
                   Customer_Email__c, Relation_Details_Applicant1__c,
                   // second applicant (booking form field set)
                   salutation_Applicant2__c, Date_of_birth_Applicant2__c, Occupation1__c,
                   Designation1__c, Permanent_Address1__c, Communication_address1__c,
                   Aadhaar_Number1__c, Pan_Number_Applicant2__c, Email2__c,
                   Relation_Details_Applicant2__c, Son_Daughter_Wife_of1__c,
                   // pricing
                   Price_per_sqft__c, Basic_Price__c, Base_Price__c, Total_Flat_Cost__c,
                   GST_Amount__c, Total_Schedule_GST__c, Loan_Bank_Name__c,
                   Total_Received_Flat_Amount__c, Balance_Flat_Amount__c,
                   Quote__r.Basic_Sale_Price_Rs__c,
                   // THE DRIZZLE price break-up
                   Rate_Per_Sqft__c, GST__c, Covered_Park_Parking__c, Car_Parking_Charges__c,
                   Extra_Covered_Parking_Charges__c,
                   Quote__r.Price_Per_Sq_Ft__c, Quote__r.Infrastructure_Charges__c,
                   Quote__r.Amenities_Car_Parking__c, Quote__r.Extra_Covered_Car_Parking_Charges__c,
                   Quote__r.GST1__c,
                   Project__r.Name, Project__r.GST_Percentage__c, Project__r.GST_Other_Percentage__c,
                   Project__r.Corpus_Charge_Per_Sq_ft__c, Project__r.Maintenance_Per_sq_ft_per_month__c,
                   Project__r.Maintenance_Month__c, Project__r.Document_Charges__c,
                   Plot__r.LL_Share_Name__c
            FROM Booking__c
            WHERE Id = :standardController.getId()
            LIMIT 1
        ];

        addApplicant(
            firstNonBlank(new List<String>{ booking.Salutation__c, booking.salutation_Applicant1__c }),
            booking.First_Applicant_Name__c,
            buildRelation(
                firstNonBlank(new List<String>{ booking.S_o_D_o_W_o__c, booking.Relation_Details_Applicant1__c }),
                booking.Son_Daughter_Wife_of__c
            ),
            booking.Date_of_Birth__c != null ? booking.Date_of_Birth__c : booking.Date_of_Birth1__c,
            firstNonBlank(new List<String>{ booking.Occupation__c, booking.Designation__c }),
            getPrimaryAddress(),
            'Resident of ',
            firstNonBlank(new List<String>{ booking.Aadhaar__c, booking.Aadhaar_Number__c }),
            firstNonBlank(new List<String>{ booking.PAN_Number__c, booking.PAN_Number1__c }),
            getPrimaryEmail()
        );

        // Age typed on the booking is used when no date of birth is recorded.
        if (!applicants.isEmpty() && String.isBlank(applicants[0].age) &&
            booking.Primary_Applicant_Age__c != null && booking.Primary_Applicant_Age__c > 0) {
            applicants[0].age = String.valueOf(booking.Primary_Applicant_Age__c.intValue());
        }

        if (!String.isBlank(booking.Second_Applicant_Name__c)) {
            Co_Applicant__c coApplicant = getCoApplicant(booking.Id, booking.Second_Applicant_Name__c);
            if (coApplicant != null) {
                addApplicant(
                    coApplicant.Salutation__c,
                    coApplicant.Full_Name__c,
                    buildRelation(coApplicant.S_o_D_o_W_o__c, coApplicant.W_o_S_o_C_o_c__c),
                    coApplicant.Date_of_Birth__c,
                    coApplicant.Occupation__c,
                    firstNonBlank(new List<String>{
                        coApplicant.Permenent_Address__c, coApplicant.Address__c, getPrimaryAddress()
                    }),
                    'Resident of ',
                    coApplicant.Aadhar_Number__c,
                    coApplicant.PAN_Number__c,
                    coApplicant.Email__c
                );
            } else {
                addApplicant(
                    booking.salutation_Applicant2__c,
                    booking.Second_Applicant_Name__c,
                    buildRelation(booking.Relation_Details_Applicant2__c, booking.Son_Daughter_Wife_of1__c),
                    booking.Date_of_birth_Applicant2__c,
                    firstNonBlank(new List<String>{ booking.Occupation1__c, booking.Designation1__c }),
                    firstNonBlank(new List<String>{
                        booking.Permanent_Address1__c, booking.Communication_address1__c, getPrimaryAddress()
                    }),
                    'Resident of ',
                    booking.Aadhaar_Number1__c,
                    booking.Pan_Number_Applicant2__c,
                    booking.Email2__c
                );
            }
        }

        List<String> names = new List<String>();
        for (ApplicantEntry applicant : applicants) {
            names.add(applicant.getDisplayName());
        }
        buyerNames = String.join(names, ' & ');

        loadPaymentRecords(booking.Id);

        if (booking.Plot__c != null) {
            selectedUnit = [
                SELECT Id, Name, Project__r.Name, Plot_Number__c, Tower__c, Tower_Block__c,
                       Floor__c, BHK_Type__c, Facing__c, Carpet_Area__c, Balcony_Area__c,
                       Built_up_area__c, Saleable_Area_Sft__c,
                       Common_Area_Allotted_to_Association__c, UDS__c,
                       Boundary_North__c, Boundary_South__c, Boundary_East__c, Boundary_West__c,
                       Covered_Park_Parking__c, LL_Share_Name__c, Share__c,
                       Block1__r.Name, Block__c, Other_Exclusive_Area__c,
                       External_Wall_Area__c, Internal_Wall_Area__c,
                       North_By__c, South_By__c, East_By__c, West_By__c,
                       Mortgaged_to_HMDA__c
                FROM Plot__c
                WHERE Id = :booking.Plot__c
                LIMIT 1
            ];
        }

        buildDrizzleCharges();

        ownerName = getOwnerForCurrentPage();
        ownerDisplayName = getOwnerDisplayName(ownerName);

        if (ownerName == null || booking.Project__c == null) {
            return;
        }

        // Every unit in the project that belongs to this landowner (LL Share Name).
        List<Plot__c> units = [
            SELECT Id, Name, Plot_Number__c, Tower__c, Tower_Block__c, Floor__c,
                   Saleable_Area_Sft__c, UDS__c, Facing__c
            FROM Plot__c
            WHERE Project__c = :booking.Project__c
              AND LL_Share_Name__c = :ownerName
            ORDER BY Tower_Block__c, Tower__c, Name
        ];

        Integer index = 1;
        for (Plot__c unit : units) {
            ownerUnits.add(new OwnerUnitRow(unit, index));
            index++;
            totalOwnerSaleableArea += unit.Saleable_Area_Sft__c == null
                ? 0
                : unit.Saleable_Area_Sft__c;
        }
    }

    private void loadPaymentRecords(Id bookingId) {
        for (Receipt__c receipt : [
            SELECT Id, Receipt_Date__c, Mode_of_payment__c, Payment_Reference_Number__c,
                   Cheque_Number__c, Check_Transaction_Nmber__c, Amount_received__c,
                   Receipt_Type__c, Payment_Method__c
            FROM Receipt__c
            WHERE Booking__c = :bookingId
              AND Approval_Status__c IN :APPROVED_RECEIPT_STATUSES
            ORDER BY Receipt_Date__c ASC, CreatedDate ASC
        ]) {
            receiptRows.add(new ReceiptRow(receipt));
            totalReceiptAmount += receipt.Amount_received__c == null ? 0 : receipt.Amount_received__c;
        }

        for (Payment_Schedule__c schedule : [
            SELECT Id, Name, Milestone_Name__c, Payment_Schedule_Name__c, Description__c,
                   Percentage__c, Flat_Cost__c, GST_Amount__c, Amount__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :bookingId
            ORDER BY Sequence__c ASC NULLS LAST, S_No__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            PaymentScheduleRow row = new PaymentScheduleRow(schedule);
            paymentScheduleRows.add(row);
            totalScheduleFlatCost += row.getFlatCost() == null ? 0 : row.getFlatCost();
            totalScheduleGst += row.getGstAmount() == null ? 0 : row.getGstAmount();
            totalScheduleNetAmount += row.getNetAmount() == null ? 0 : row.getNetAmount();
            totalSchedulePercentage += row.getPercentage() == null ? 0 : row.getPercentage();
        }
    }

    // ---------------------------------------------------------------- applicants

    private String getPrimaryAddress() {
        return firstNonBlank(new List<String>{
            booking.Permanent_Address__c, booking.Address__c, booking.Communication_address__c
        });
    }

    private String getPrimaryEmail() {
        return firstNonBlank(new List<String>{
            booking.Email1__c, booking.Email__c, booking.Customer_Email__c
        });
    }

    /** Address printed in the "notice to the VENDEE" table. */
    public String getBuyerAddress() {
        return booking == null ? '' : getPrimaryAddress();
    }

    /** E-mail printed in the "notice to the VENDEE" table. */
    public String getBuyerEmail() {
        return booking == null ? '' : getPrimaryEmail();
    }

    public String getLoanBankName() {
        return booking == null || String.isBlank(booking.Loan_Bank_Name__c)
            ? '____________'
            : booking.Loan_Bank_Name__c.trim();
    }

    private static String getAge(Date dateOfBirth) {
        if (dateOfBirth == null || dateOfBirth > Date.today()) {
            return '';
        }
        Date today = Date.today();
        Integer age = today.year() - dateOfBirth.year();
        if (today.month() < dateOfBirth.month() ||
            (today.month() == dateOfBirth.month() && today.day() < dateOfBirth.day())) {
            age--;
        }
        return String.valueOf(age);
    }

    /**
     * The Co-Applicant record for the booking's second applicant: an exact
     * (normalised) name match, or the only co-applicant when its name clearly
     * refers to the same person. Returns null otherwise so the booking's own
     * second-applicant fields are used instead of an unrelated record.
     */
    private static Co_Applicant__c getCoApplicant(Id bookingId, String applicantName) {
        String normalizedApplicantName = normalizeApplicantName(applicantName);
        List<Co_Applicant__c> coApplicants = [
            SELECT Full_Name__c, Salutation__c, Date_of_Birth__c, Occupation__c,
                   S_o_D_o_W_o__c, W_o_S_o_C_o_c__c, Address__c, Permenent_Address__c,
                   Aadhar_Number__c, PAN_Number__c, Email__c
            FROM Co_Applicant__c
            WHERE Booking__c = :bookingId
            ORDER BY CreatedDate ASC
        ];
        for (Co_Applicant__c coApplicant : coApplicants) {
            if (!String.isBlank(normalizedApplicantName) &&
                normalizeApplicantName(coApplicant.Full_Name__c) == normalizedApplicantName) {
                return coApplicant;
            }
        }
        if (coApplicants.size() == 1 && !String.isBlank(normalizedApplicantName)) {
            String coName = normalizeApplicantName(coApplicants[0].Full_Name__c);
            if (!String.isBlank(coName) &&
                (coName.contains(normalizedApplicantName) || normalizedApplicantName.contains(coName))) {
                return coApplicants[0];
            }
        }
        return null;
    }

    private static String normalizeApplicantName(String name) {
        return String.isBlank(name) ? '' : name.trim().replaceAll('\\s+', ' ').toUpperCase();
    }

    /** "S/O. SRI. FATHER NAME" from a relation picklist and the relative's name. */
    private static String buildRelation(String relation, String relativeName) {
        if (String.isBlank(relation) || String.isBlank(relativeName)) {
            return '';
        }
        String label = relation.trim().toUpperCase();
        if (!label.endsWith('.')) {
            label += '.';
        }
        String relative = relativeName.trim();
        Boolean hasSalutation = Pattern.compile('(?i)^(sri|smt|late|mr|mrs|ms|dr|kum)\\b').matcher(relative).find();
        return label + ' ' + (hasSalutation ? '' : 'SRI. ') + relative.toUpperCase();
    }

    /** Maps picklist salutations (Mr./Mrs/Ms) onto the SRI./SMT. style used in the deeds. */
    private static String formalSalutation(String salutation) {
        if (String.isBlank(salutation)) {
            return '';
        }
        String key = salutation.trim().replace('.', '').toLowerCase();
        if (key == 'mr') {
            return 'Sri.';
        }
        if (key == 'mrs') {
            return 'Smt.';
        }
        if (key == 'ms' || key == 'miss') {
            return 'Kum.';
        }
        if (key == 'dr') {
            return 'Dr.';
        }
        if (key == 'm/s') {
            return 'M/s.';
        }
        return salutation.trim();
    }

    private void addApplicant(
        String salutation,
        String name,
        String relation,
        Date dateOfBirth,
        String occupation,
        String address,
        String addressPrefix,
        String aadhaar,
        String pan,
        String email
    ) {
        if (!String.isBlank(name)) {
            ApplicantEntry entry = new ApplicantEntry(
                applicants.size() + 1,
                formalSalutation(salutation),
                name,
                relation,
                dateOfBirth,
                occupation,
                address,
                addressPrefix,
                aadhaar,
                pan,
                email
            );
            entry.rawSalutation = salutation;
            applicants.add(entry);
        }
    }

    private static String firstNonBlank(List<String> values) {
        for (String value : values) {
            if (!String.isBlank(value)) {
                return value.trim();
            }
        }
        return null;
    }

    // ------------------------------------------------------------- selected unit

    private OwnerUnitRow selectedRow() {
        return new OwnerUnitRow(selectedUnit, 1);
    }

    /** Tower number only, e.g. "1" for "T-01". */
    public String getSelectedTowerDisplay() {
        if (selectedUnit == null) {
            return '';
        }
        String tower = selectedRow().getTowerDisplay();
        if (!tower.startsWith('T-')) {
            return tower;
        }
        String towerNumber = tower.substring(2);
        return towerNumber.length() > 1 && towerNumber.startsWith('0')
            ? towerNumber.substring(1)
            : towerNumber;
    }

    public String getSelectedFloorDisplay() {
        return selectedUnit == null ? '' : selectedRow().getFloorDisplay();
    }

    public String getSelectedFlatNumber() {
        return selectedUnit == null ? '' : selectedRow().getFlatNumber();
    }

    /** Full flat label e.g. "T1-707" (unit name, or tower + flat number when the name is absent). */
    public String getSelectedFlatLabel() {
        if (selectedUnit == null) {
            return '';
        }
        if (!String.isBlank(selectedUnit.Name)) {
            return selectedUnit.Name.trim();
        }
        String tower = getSelectedTowerDisplay();
        return (String.isBlank(tower) ? '' : 'T' + tower + '-') + getSelectedFlatNumber();
    }

    public String getSelectedFacingDisplay() {
        return selectedUnit == null ? '' : selectedRow().getFacingDisplay();
    }

    /** Upper-case facing used in the schedule tables, e.g. "EAST". */
    public String getSelectedFacingUpper() {
        return getSelectedFacingDisplay().toUpperCase();
    }

    public String getSelectedBhkNumber() {
        if (selectedUnit == null || String.isBlank(selectedUnit.BHK_Type__c)) {
            return '';
        }

        Matcher bhkMatch = Pattern.compile('^\\s*(\\d+(?:\\.\\d+)?)').matcher(selectedUnit.BHK_Type__c);
        return bhkMatch.find() ? bhkMatch.group(1) : selectedUnit.BHK_Type__c;
    }

    /** Wall area = plinth (built-up) - carpet - balcony. */
    public Decimal getSelectedWallArea() {
        if (selectedUnit == null || selectedUnit.Built_up_area__c == null ||
            selectedUnit.Carpet_Area__c == null || selectedUnit.Balcony_Area__c == null) {
            return null;
        }
        return selectedUnit.Built_up_area__c -
            selectedUnit.Carpet_Area__c -
            selectedUnit.Balcony_Area__c;
    }

    /** LL Share Name on the booked unit (may differ from the page's landowner). */
    public String getUnitOwnerName() {
        return selectedUnit == null ? '' : selectedUnit.LL_Share_Name__c;
    }

    /**
     * Warning shown when the booked unit's LL Share Name does not match the
     * landowner this page is for (empty when they match or when not applicable).
     */
    public String getOwnerMismatchMessage() {
        if (selectedUnit == null) {
            return '';
        }
        String unitOwner = selectedUnit.LL_Share_Name__c;
        if (isBuilderSharePage) {
            return String.isBlank(unitOwner)
                ? ''
                : 'Note: the booked unit ' + selectedUnit.Name + ' is tagged with LL Share Name "' +
                    unitOwner + '" (landowner share) but this is the Builder Share agreement template.';
        }
        if (ownerName == null || String.isBlank(unitOwner) || unitOwner.equalsIgnoreCase(ownerName)) {
            return '';
        }
        return 'Note: the booked unit ' + selectedUnit.Name + ' is tagged with LL Share Name "' +
            unitOwner + '" but this agreement template is for "' + ownerName + '".';
    }

    // ------------------------------------- ARJUN_SINGH_AGREEMENT_OF_SALE only
    // Additive getters used only by the ARJUN page, so the other agreement
    // templates keep printing exactly what they print today.

    private String selectedTowerName;
    private List<ApplicantEntry> allApplicants;

    /**
     * Tower name of the booked unit, read from the Plot__c "Tower" lookup
     * (Tower__c). The relationship is resolved from the field's schema at run
     * time, so this works whether the org defines Tower__c as a lookup or not.
     * Falls back to Block1__r.Name, then to the existing name-based tower.
     */
    public String getSelectedTowerName() {
        if (selectedUnit == null) {
            return '';
        }
        if (selectedTowerName == null) {
            String towerName = queryTowerLookupName(selectedUnit.Id);
            if (String.isBlank(towerName) && selectedUnit.Block1__r != null) {
                towerName = selectedUnit.Block1__r.Name;
            }
            selectedTowerName = String.isBlank(towerName)
                ? getSelectedTowerDisplay()
                : towerName.trim();
        }
        return selectedTowerName;
    }

    @TestVisible
    private static String queryTowerLookupName(Id unitId) {
        if (unitId == null) {
            return null;
        }
        Schema.DescribeFieldResult towerField = Plot__c.Tower__c.getDescribe();
        String relationshipName = towerField.getRelationshipName();
        if (towerField.getType() != Schema.DisplayType.REFERENCE || String.isBlank(relationshipName)) {
            return null;
        }
        List<Plot__c> units = Database.query(
            'SELECT ' + relationshipName + '.Name FROM Plot__c WHERE Id = :unitId LIMIT 1'
        );
        if (units.isEmpty()) {
            return null;
        }
        SObject tower = units[0].getSObject(relationshipName);
        Object towerName = tower == null ? null : tower.get('Name');
        return towerName == null ? null : String.valueOf(towerName);
    }

    /**
     * Every purchaser for the IN FAVOUR OF list: the applicants printed today
     * (first applicant and Second Applicant) followed by each Co_Applicant__c
     * record of the booking, oldest first, numbered 1..N. A co-applicant whose
     * name is already printed is not repeated.
     */
    public List<ApplicantEntry> getAllApplicants() {
        if (allApplicants == null) {
            allApplicants = buildAllApplicants();
        }
        return allApplicants;
    }

    /**
     * Names for the "notice to the VENDEE (S)" Attention row: every purchaser
     * from getAllApplicants() joined with " & ", e.g. "SRI. A & SMT. B".
     */
    public String getAllBuyerNames() {
        List<String> names = new List<String>();
        for (ApplicantEntry entry : getAllApplicants()) {
            names.add(entry.getDisplayName());
        }
        return String.join(names, ' & ');
    }

    private List<ApplicantEntry> buildAllApplicants() {
        List<ApplicantEntry> result = new List<ApplicantEntry>(applicants);
        if (booking == null || booking.Id == null) {
            return result;
        }

        Set<String> printedNames = new Set<String>();
        for (ApplicantEntry entry : result) {
            printedNames.add(normalizeApplicantName(entry.name));
        }

        for (Co_Applicant__c coApplicant : [
            SELECT Full_Name__c, First_Name__c, Last_Name__c, Salutation__c, Date_of_Birth__c,
                   Occupation__c, S_o_D_o_W_o__c, W_o_S_o_C_o_c__c, Address__c,
                   Permenent_Address__c, Aadhar_Number__c, PAN_Number__c, Email__c
            FROM Co_Applicant__c
            WHERE Booking__c = :booking.Id
            ORDER BY CreatedDate ASC, Name ASC
        ]) {
            String name = firstNonBlank(new List<String>{
                coApplicant.Full_Name__c,
                joinNames(coApplicant.First_Name__c, coApplicant.Last_Name__c)
            });
            String key = normalizeApplicantName(name);
            if (String.isBlank(key) || printedNames.contains(key)) {
                continue;
            }
            printedNames.add(key);

            ApplicantEntry entry = new ApplicantEntry(
                result.size() + 1,
                formalSalutation(coApplicant.Salutation__c),
                name,
                buildRelation(coApplicant.S_o_D_o_W_o__c, coApplicant.W_o_S_o_C_o_c__c),
                coApplicant.Date_of_Birth__c,
                coApplicant.Occupation__c,
                firstNonBlank(new List<String>{
                    coApplicant.Permenent_Address__c, coApplicant.Address__c, getPrimaryAddress()
                }),
                'Resident of ',
                coApplicant.Aadhar_Number__c,
                coApplicant.PAN_Number__c,
                coApplicant.Email__c
            );
            entry.rawSalutation = coApplicant.Salutation__c;
            result.add(entry);
        }
        return result;
    }

    // Clause 1.11 (flat payments only): the paid / balance amounts come from the
    // Booking roll-up and formula fields; the receipts table lists the approved
    // receipts that are not GST Amount / Additional Charge, totalled by its rows.

    private List<ReceiptRow> flatReceiptRows;

    public List<ReceiptRow> getFlatReceiptRows() {
        if (flatReceiptRows == null) {
            flatReceiptRows = new List<ReceiptRow>();
            for (ReceiptRow row : receiptRows) {
                if (!NON_FLAT_RECEIPT_TYPES.contains(row.getReceiptType())) {
                    flatReceiptRows.add(row);
                }
            }
        }
        return flatReceiptRows;
    }

    public Boolean getHasFlatReceipts() {
        return !getFlatReceiptRows().isEmpty();
    }

    /** TOTAL AMOUNT row: sum of the rows shown in the clause 1.11 table. */
    public String getFormattedFlatReceiptTotal() {
        Decimal total = 0;
        for (ReceiptRow row : getFlatReceiptRows()) {
            total += row.getAmount() == null ? 0 : row.getAmount();
        }
        return formatIndianCurrency(total);
    }

    /** "VENDEE/S has paid a sum of Rs. ..." - Booking__c.Total_Received_Flat_Amount__c. */
    public String getFormattedTotalReceivedFlatAmount() {
        return formatIndianCurrency(booking == null ? null : booking.Total_Received_Flat_Amount__c);
    }

    public String getTotalReceivedFlatAmountInWords() {
        return amountInWords(booking == null ? null : booking.Total_Received_Flat_Amount__c);
    }

    /** "Balance Rs. ..." - Booking__c.Balance_Flat_Amount__c. */
    public String getFormattedBalanceFlatAmount() {
        return formatIndianCurrency(booking == null ? null : booking.Balance_Flat_Amount__c);
    }

    public String getBalanceFlatAmountInWords() {
        return amountInWords(booking == null ? null : booking.Balance_Flat_Amount__c);
    }

    private static String joinNames(String firstName, String lastName) {
        List<String> parts = new List<String>();
        if (!String.isBlank(firstName)) {
            parts.add(firstName.trim());
        }
        if (!String.isBlank(lastName)) {
            parts.add(lastName.trim());
        }
        return String.join(parts, ' ');
    }

    // ------------------------------------------------------------------ amounts

    /**
     * Basic (base) sale price: the booking's Base Price, else the quote's
     * basic sale price, else the Basic_Price__c formula.
     */
    private Decimal getBasicPriceValue() {
        if (booking == null) {
            return null;
        }
        if (booking.Base_Price__c != null && booking.Base_Price__c > 0) {
            return booking.Base_Price__c;
        }
        if (booking.Quote__r != null && booking.Quote__r.Basic_Sale_Price_Rs__c != null &&
            booking.Quote__r.Basic_Sale_Price_Rs__c > 0) {
            return booking.Quote__r.Basic_Sale_Price_Rs__c;
        }
        if (booking.Basic_Price__c != null && booking.Basic_Price__c > 0) {
            return booking.Basic_Price__c;
        }
        return null;
    }

    private Decimal getPricePerSquareFootValue() {
        if (booking == null) {
            return null;
        }
        if (booking.Price_per_sqft__c != null && booking.Price_per_sqft__c > 0) {
            return booking.Price_per_sqft__c;
        }
        Decimal basicPrice = getBasicPriceValue();
        if (basicPrice != null && selectedUnit != null && selectedUnit.Saleable_Area_Sft__c != null &&
            selectedUnit.Saleable_Area_Sft__c > 0) {
            return (basicPrice / selectedUnit.Saleable_Area_Sft__c).setScale(0, System.RoundingMode.HALF_UP);
        }
        return null;
    }

    private Decimal getGstAmountValue() {
        if (booking == null) {
            return null;
        }
        if (booking.GST_Amount__c != null && booking.GST_Amount__c > 0) {
            return booking.GST_Amount__c;
        }
        if (booking.Total_Schedule_GST__c != null && booking.Total_Schedule_GST__c > 0) {
            return booking.Total_Schedule_GST__c;
        }
        return totalScheduleGst > 0 ? totalScheduleGst : null;
    }

    public Decimal getAmenitiesAmount() {
        Decimal basicPrice = getBasicPriceValue();
        if (booking == null || booking.Total_Flat_Cost__c == null || basicPrice == null) {
            return null;
        }
        return booking.Total_Flat_Cost__c - basicPrice;
    }

    public Decimal getBalanceAmount() {
        if (booking == null || booking.Total_Flat_Cost__c == null) {
            return null;
        }
        return booking.Total_Flat_Cost__c - totalReceiptAmount;
    }

    public String getAgreementAmountInWords() {
        return amountInWords(booking == null ? null : booking.Total_Flat_Cost__c);
    }

    public String getTotalReceiptAmountInWords() {
        return amountInWords(totalReceiptAmount);
    }

    public String getBalanceAmountInWords() {
        return amountInWords(getBalanceAmount());
    }

    public String getGstAmountInWords() {
        return amountInWords(getGstAmountValue());
    }

    public String getFormattedPricePerSquareFoot() {
        return formatIndianCurrency(getPricePerSquareFootValue());
    }

    public String getFormattedBasicPrice() {
        return formatIndianCurrency(getBasicPriceValue());
    }

    public String getFormattedAmenitiesAmount() {
        return formatIndianCurrency(getAmenitiesAmount());
    }

    public String getFormattedTotalFlatCost() {
        return formatIndianCurrency(booking == null ? null : booking.Total_Flat_Cost__c);
    }

    public String getFormattedGstAmount() {
        return formatIndianCurrency(getGstAmountValue());
    }

    public String getFormattedTotalReceiptAmount() {
        return formatIndianCurrency(totalReceiptAmount);
    }

    public String getFormattedBalanceAmount() {
        return formatIndianCurrency(getBalanceAmount());
    }

    public String getFormattedTotalScheduleFlatCost() {
        return formatIndianCurrency(totalScheduleFlatCost);
    }

    public String getFormattedTotalScheduleGst() {
        return formatIndianCurrency(totalScheduleGst);
    }

    public String getFormattedTotalScheduleNetAmount() {
        return formatIndianCurrency(totalScheduleNetAmount);
    }

    private Integer carParkingCount() {
        if (booking == null) {
            return 0;
        }
        if (booking.No_of_car_parking__c != null && booking.No_of_car_parking__c > 0) {
            return Integer.valueOf(booking.No_of_car_parking__c);
        }
        return booking.Car_Parking_Selected__c == true ? 1 : 0;
    }

    /** "One" / "Two" / "None" */
    public String getSelectedCarParkingDisplay() {
        Integer count = carParkingCount();
        return count == 0 ? 'None' : underThousand(count);
    }

    /** " and One Car Parking" (empty when no parking). */
    public String getSelectedCarParkingClause() {
        Integer count = carParkingCount();
        if (count == 0) {
            return '';
        }
        return ' and ' + underThousand(count) + ' Car Parking' + (count > 1 ? ' Spaces' : '');
    }

    public String getAmenitiesDescription() {
        Integer count = carParkingCount();
        if (count == 0) {
            return 'Amenities including Infrastructure charges';
        }
        return 'Amenities including ' + underThousand(count) + ' car parking' +
            (count > 1 ? ' spaces' : '') + ' & Infrastructure charges';
    }

    // ============================================================== THE DRIZZLE

    private static final List<String> FLOOR_WORDS = new List<String>{
        'GROUND', 'FIRST', 'SECOND', 'THIRD', 'FOURTH', 'FIFTH', 'SIXTH', 'SEVENTH', 'EIGHTH',
        'NINTH', 'TENTH', 'ELEVENTH', 'TWELFTH', 'THIRTEENTH', 'FOURTEENTH', 'FIFTEENTH',
        'SIXTEENTH', 'SEVENTEENTH', 'EIGHTEENTH', 'NINETEENTH', 'TWENTIETH', 'TWENTY FIRST',
        'TWENTY SECOND', 'TWENTY THIRD', 'TWENTY FOURTH', 'TWENTY FIFTH', 'TWENTY SIXTH',
        'TWENTY SEVENTH', 'TWENTY EIGHTH', 'TWENTY NINTH', 'THIRTIETH'
    };

    private static Decimal positive(Decimal value) {
        return value != null && value > 0 ? value : null;
    }

    private static Decimal firstPositive(List<Decimal> values) {
        for (Decimal value : values) {
            if (value != null && value > 0) {
                return value;
            }
        }
        return null;
    }

    private static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }

    private static Decimal percentOf(Decimal amount, Decimal percent) {
        return amount == null || percent == null
            ? null
            : (amount * percent / 100).setScale(0, System.RoundingMode.HALF_UP);
    }

    /** "824.02", "317.313", "1375" - a number without trailing zeros or separators. */
    private static String plainNumber(Decimal value) {
        if (value == null) {
            return '';
        }
        String text = value.stripTrailingZeros().toPlainString();
        return text;
    }

    /** "1234 1234 1234" for a 12 digit Aadhaar; anything else is returned trimmed. */
    private static String formatAadhaar(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        String digits = value.replaceAll('[^0-9]', '');
        if (digits.length() != 12) {
            return value.trim();
        }
        return digits.substring(0, 4) + ' ' + digits.substring(4, 8) + ' ' + digits.substring(8);
    }

    /**
     * Price break-up of THE DRIZZLE agreements.
     * Table 1: Basic Price, Club House Membership & Infrastructure Charges, Car Parking.
     *   Basic Price is the booking's Total Flat Cost less the other two heads, so the
     *   rows always add up to the agreed consideration.
     * Table 2 (payable at registration / handover): Corpus Fund, Maintenance deposit,
     *   Legal and Documentation charges - rates come from the Project.
     */
    private void buildDrizzleCharges() {
        if (booking == null) {
            return;
        }
        Decimal area = selectedUnit == null ? null : positive(selectedUnit.Saleable_Area_Sft__c);
        Decimal gstPercent = firstPositive(new List<Decimal>{
            booking.Quote__r == null ? null : booking.Quote__r.GST1__c,
            booking.GST__c,
            booking.Project__r == null ? null : booking.Project__r.GST_Percentage__c
        });
        if (gstPercent == null) {
            gstPercent = 5;
        }
        Decimal otherGstPercent = booking.Project__r == null
            ? null
            : positive(booking.Project__r.GST_Other_Percentage__c);
        if (otherGstPercent == null) {
            otherGstPercent = 18;
        }

        Decimal club = booking.Quote__r == null ? null : positive(booking.Quote__r.Infrastructure_Charges__c);
        Decimal parking = firstPositive(new List<Decimal>{
            booking.Quote__r == null ? null : booking.Quote__r.Amenities_Car_Parking__c,
            booking.Covered_Park_Parking__c,
            booking.Car_Parking_Charges__c
        });
        Decimal extraParking = firstPositive(new List<Decimal>{
            booking.Quote__r == null ? null : booking.Quote__r.Extra_Covered_Car_Parking_Charges__c,
            booking.Extra_Covered_Parking_Charges__c
        });
        if (extraParking != null) {
            parking = nz(parking) + extraParking;
        }
        Decimal rate = firstPositive(new List<Decimal>{
            booking.Quote__r == null ? null : booking.Quote__r.Price_Per_Sq_Ft__c,
            booking.Price_per_sqft__c,
            booking.Rate_Per_Sqft__c
        });

        Decimal total = positive(booking.Total_Flat_Cost__c);
        Decimal basic;
        if (total != null) {
            basic = total - nz(club) - nz(parking);
            if (basic <= 0) {
                // the recorded heads exceed the agreed cost: show the agreed cost on its own
                basic = total;
                club = null;
                parking = null;
            }
        } else if (rate != null && area != null) {
            basic = (rate * area).setScale(0, System.RoundingMode.HALF_UP);
        }
        if (basic != null && area != null) {
            rate = (basic / area).setScale(2, System.RoundingMode.HALF_UP);
        }

        Integer parkingCount = carParkingCount();
        drizzlePriceLines.add(new ChargeLine('Basic Price', plainNumber(rate), basic, percentOf(basic, gstPercent)));
        drizzlePriceLines.add(new ChargeLine(
            'Club House Membership & Infrastructure Charges', '', nz(club), percentOf(nz(club), gstPercent)
        ));
        drizzlePriceLines.add(new ChargeLine(
            'Car Parking (' + (parkingCount == 0 ? 'Nil' : String.valueOf(parkingCount) + ' No.') + ')',
            '', nz(parking), percentOf(nz(parking), gstPercent)
        ));
        drizzlePriceTotal = sumLines('Total', drizzlePriceLines);

        Decimal corpusRate = booking.Project__r == null ? null : positive(booking.Project__r.Corpus_Charge_Per_Sq_ft__c);
        Decimal maintRate = booking.Project__r == null ? null : positive(booking.Project__r.Maintenance_Per_sq_ft_per_month__c);
        Decimal maintMonths = booking.Project__r == null ? null : positive(booking.Project__r.Maintenance_Month__c);
        Decimal legal = booking.Project__r == null ? null : positive(booking.Project__r.Document_Charges__c);
        String monthsText = maintMonths == null ? '' : plainNumber(maintMonths);

        Decimal corpus = corpusRate == null || area == null
            ? null
            : (corpusRate * area).setScale(0, System.RoundingMode.HALF_UP);
        Decimal maintenance = maintRate == null || maintMonths == null || area == null
            ? null
            : (maintRate * maintMonths * area).setScale(0, System.RoundingMode.HALF_UP);

        drizzleCorpusLine = new ChargeLine(
            'Corpus Fund (Payable at the time of handover of the Apartment in favour of Association of Allottees)',
            corpusRate == null ? '' : 'Rs. ' + plainNumber(corpusRate) + '/- per SFT',
            corpus, null
        );
        drizzleMaintenanceLine = new ChargeLine(
            'Maintenance Charges Deposit for ' + monthsText + ' months, payable at the time of hand over of ' +
                'the Apartment, in favour of the Association of Allottees.',
            maintRate == null ? '' : 'Rs. ' + maintRate.setScale(2).toPlainString() + 'ps. per SFT per Month for ' +
                monthsText + ' Months',
            maintenance, percentOf(maintenance, otherGstPercent)
        );
        drizzleLegalLine = new ChargeLine(
            'Legal and Documentation charges', 'LS', legal, percentOf(legal, otherGstPercent)
        );
        drizzleOtherLines.add(drizzleCorpusLine);
        drizzleOtherLines.add(drizzleMaintenanceLine);
        drizzleOtherLines.add(drizzleLegalLine);
        drizzleOtherTotal = sumLines('Total', drizzleOtherLines);
    }

    private static ChargeLine sumLines(String label, List<ChargeLine> lines) {
        Decimal amount = null;
        Decimal gst = null;
        for (ChargeLine line : lines) {
            if (line.amount != null) {
                amount = nz(amount) + line.amount;
            }
            if (line.gst != null) {
                gst = nz(gst) + line.gst;
            }
        }
        return new ChargeLine(label, '', amount, amount == null ? null : nz(gst));
    }

    /** Total sale consideration including GST. */
    public Decimal getDrizzleGrandTotal() {
        return drizzlePriceTotal == null ? null : drizzlePriceTotal.getTotal();
    }

    public String getDrizzleGrandTotalDisplay() {
        return formatIndianCurrency(getDrizzleGrandTotal());
    }

    public String getDrizzleGrandTotalInWords() {
        return amountInWords(getDrizzleGrandTotal());
    }

    /** Consideration including GST less the receipts acknowledged in the agreement. */
    public Decimal getDrizzleBalance() {
        Decimal grandTotal = getDrizzleGrandTotal();
        return grandTotal == null ? null : grandTotal - totalReceiptAmount;
    }

    public String getDrizzleBalanceDisplay() {
        return formatIndianCurrency(getDrizzleBalance());
    }

    public String getDrizzleBalanceInWords() {
        return amountInWords(getDrizzleBalance());
    }

    /** "50" - corpus rate per SFT as printed in "Rs.50/- per SFT". */
    public String getDrizzleCorpusRate() {
        return booking == null || booking.Project__r == null
            ? ''
            : plainNumber(positive(booking.Project__r.Corpus_Charge_Per_Sq_ft__c));
    }

    public String getDrizzleCorpusInWords() {
        return amountInWords(drizzleCorpusLine == null ? null : drizzleCorpusLine.amount);
    }

    /** "Maintenance for 24 months @ Rs 3.5 /- per month per Sft" (Schedule-C row label). */
    public String getDrizzleMaintenanceScheduleLabel() {
        if (booking == null || booking.Project__r == null) {
            return 'Maintenance';
        }
        Decimal months = positive(booking.Project__r.Maintenance_Month__c);
        Decimal rate = positive(booking.Project__r.Maintenance_Per_sq_ft_per_month__c);
        return 'Maintenance' + (months == null ? '' : ' for ' + plainNumber(months) + ' months') +
            (rate == null ? '' : ' @ Rs ' + plainNumber(rate) + ' /- per month per Sft');
    }

    /** "Corpus Fund @ Rs. 50 /- per sft" (Schedule-C row label). */
    public String getDrizzleCorpusScheduleLabel() {
        String rate = getDrizzleCorpusRate();
        return 'Corpus Fund' + (String.isBlank(rate) ? '' : ' @ Rs. ' + rate + ' /- per sft');
    }

    /**
     * True when the HMDA mortgage clause must be printed: the booked unit is ticked
     * "Mortgaged to HMDA", or the dedicated mortgage agreement page is being rendered.
     */
    public Boolean getIsMortgagedUnit() {
        if (currentPageUrl().contains('MORTGAGEAGREEMENTOFSALEDRIZZLE')) {
            return true;
        }
        return selectedUnit != null && selectedUnit.Mortgaged_to_HMDA__c == true;
    }

    /** Block letter, e.g. "F": the Tower lookup, else the Block picklist, else the unit name prefix. */
    public String getDrizzleBlock() {
        if (selectedUnit == null) {
            return '';
        }
        if (selectedUnit.Block1__r != null && !String.isBlank(selectedUnit.Block1__r.Name)) {
            return selectedUnit.Block1__r.Name.trim().toUpperCase();
        }
        if (!String.isBlank(selectedUnit.Block__c)) {
            return selectedUnit.Block__c.trim().toUpperCase();
        }
        if (!String.isBlank(selectedUnit.Name) && selectedUnit.Name.contains('-')) {
            String prefix = selectedUnit.Name.substringBefore('-').trim();
            if (prefix.length() <= 3) {
                return prefix.toUpperCase();
            }
        }
        return String.isBlank(selectedUnit.Tower__c) ? '' : selectedUnit.Tower__c.trim().toUpperCase();
    }

    /** "F-306" */
    public String getDrizzleFlatNo() {
        return selectedUnit == null || String.isBlank(selectedUnit.Name) ? '' : selectedUnit.Name.trim().toUpperCase();
    }

    /** "THIRD" / "GROUND" */
    public String getDrizzleFloor() {
        if (selectedUnit == null || String.isBlank(selectedUnit.Floor__c)) {
            return '';
        }
        String floorValue = selectedUnit.Floor__c.trim();
        if (floorValue.equalsIgnoreCase('G') || floorValue.equalsIgnoreCase('Ground')) {
            return 'GROUND';
        }
        if (floorValue.isNumeric()) {
            Integer floorNumber = Integer.valueOf(floorValue);
            if (floorNumber >= 0 && floorNumber < FLOOR_WORDS.size()) {
                return FLOOR_WORDS[floorNumber];
            }
        }
        return floorValue.toUpperCase();
    }

    /** "2BHK" */
    public String getDrizzleFlatType() {
        return selectedUnit == null || String.isBlank(selectedUnit.BHK_Type__c)
            ? ''
            : selectedUnit.BHK_Type__c.trim().toUpperCase().replace(' BHK', 'BHK');
    }

    public String getDrizzleFlatSize() {
        return selectedUnit == null ? '' : plainNumber(selectedUnit.Saleable_Area_Sft__c);
    }

    public String getDrizzleCarpetArea() {
        return selectedUnit == null ? '' : plainNumber(selectedUnit.Carpet_Area__c);
    }

    public String getDrizzleBalconyArea() {
        return selectedUnit == null ? '' : plainNumber(selectedUnit.Balcony_Area__c);
    }

    /** Utility area is held in "Other Exclusive Area" on the unit. */
    public String getDrizzleUtilityArea() {
        return selectedUnit == null ? '' : plainNumber(selectedUnit.Other_Exclusive_Area__c);
    }

    public String getDrizzleCommonArea() {
        return selectedUnit == null ? '' : plainNumber(selectedUnit.Common_Area_Allotted_to_Association__c);
    }

    public String getDrizzleExternalWall() {
        return selectedUnit == null ? '' : plainNumber(selectedUnit.External_Wall_Area__c);
    }

    public String getDrizzleInternalWall() {
        return selectedUnit == null ? '' : plainNumber(selectedUnit.Internal_Wall_Area__c);
    }

    /** "32.60" */
    public String getDrizzleUds() {
        return selectedUnit == null || selectedUnit.UDS__c == null
            ? ''
            : selectedUnit.UDS__c.setScale(2, System.RoundingMode.HALF_UP).toPlainString();
    }

    public String getDrizzleProjectName() {
        if (booking != null && booking.Project__r != null && !String.isBlank(booking.Project__r.Name)) {
            return booking.Project__r.Name.trim().toUpperCase();
        }
        return selectedUnit == null || selectedUnit.Project__r == null || selectedUnit.Project__r.Name == null
            ? ''
            : selectedUnit.Project__r.Name.trim().toUpperCase();
    }

    private static String upperOrBlank(String value) {
        return String.isBlank(value) ? '' : value.trim().toUpperCase();
    }

    public String getDrizzleBoundaryNorth() {
        return selectedUnit == null ? '' : upperOrBlank(firstNonBlank(new List<String>{
            selectedUnit.North_By__c, selectedUnit.Boundary_North__c }));
    }

    public String getDrizzleBoundarySouth() {
        return selectedUnit == null ? '' : upperOrBlank(firstNonBlank(new List<String>{
            selectedUnit.South_By__c, selectedUnit.Boundary_South__c }));
    }

    public String getDrizzleBoundaryEast() {
        return selectedUnit == null ? '' : upperOrBlank(firstNonBlank(new List<String>{
            selectedUnit.East_By__c, selectedUnit.Boundary_East__c }));
    }

    public String getDrizzleBoundaryWest() {
        return selectedUnit == null ? '' : upperOrBlank(firstNonBlank(new List<String>{
            selectedUnit.West_By__c, selectedUnit.Boundary_West__c }));
    }

    /** "MR. A & MR. B" */
    public String getDrizzleBuyerNames() {
        List<String> names = new List<String>();
        for (ApplicantEntry applicant : applicants) {
            names.add(applicant.getDrizzleName());
        }
        return String.join(names, ' & ');
    }

    /** "R/o: 1-2-3, ..." */
    public String getDrizzleBuyerAddress() {
        String address = getBuyerAddress();
        return String.isBlank(address) ? '' : 'R/o: ' + address;
    }

    /** Every allottee's e-mail, "a@x.com & b@y.com". */
    public String getDrizzleBuyerEmails() {
        List<String> emails = new List<String>();
        Set<String> seen = new Set<String>();
        for (ApplicantEntry applicant : applicants) {
            if (!String.isBlank(applicant.email) && !seen.contains(applicant.email.toLowerCase())) {
                seen.add(applicant.email.toLowerCase());
                emails.add(applicant.email.trim());
            }
        }
        if (emails.isEmpty() && !String.isBlank(getBuyerEmail())) {
            emails.add(getBuyerEmail());
        }
        return String.join(emails, ' & ');
    }

    // ---------------------------------------------------------------- formatting

    private static String formatIndianCurrency(Decimal amount) {
        if (amount == null) {
            return '';
        }

        String value = String.valueOf(amount.setScale(0, System.RoundingMode.HALF_UP));
        Boolean isNegative = value.startsWith('-');
        if (isNegative) {
            value = value.substring(1);
        }
        if (value.length() <= 3) {
            return (isNegative ? '-' : '') + value;
        }

        Integer lastThreeIndex = value.length() - 3;
        String formatted = value.substring(lastThreeIndex);
        String leadingDigits = value.substring(0, lastThreeIndex);
        while (leadingDigits.length() > 2) {
            Integer groupStart = leadingDigits.length() - 2;
            formatted = leadingDigits.substring(groupStart) + ',' + formatted;
            leadingDigits = leadingDigits.substring(0, groupStart);
        }
        return (isNegative ? '-' : '') + leadingDigits + ',' + formatted;
    }

    /** "Rupees One Crore Five Lakh Thirteen Thousand Six Hundred Eighty Only" */
    private static String amountInWords(Decimal amount) {
        if (amount == null) {
            return '';
        }

        Long roundedAmount = amount.setScale(0, System.RoundingMode.HALF_UP).longValue();
        Boolean isNegative = roundedAmount < 0;
        String digits = String.valueOf(roundedAmount);
        if (isNegative) {
            digits = digits.substring(1);
        }
        if (digits == '0') {
            return 'Rupees Zero Only';
        }

        List<String> groups = new List<String>();
        List<String> units = new List<String>{ '', 'Thousand', 'Lakh', 'Crore', 'Arab', 'Kharab', 'Neel' };
        Integer endIndex = digits.length();
        Integer groupSize = 3;
        Integer unitIndex = 0;
        while (endIndex > 0) {
            Integer startIndex = Math.max(0, endIndex - groupSize);
            Integer groupValue = Integer.valueOf(digits.substring(startIndex, endIndex));
            if (groupValue > 0) {
                String groupWords = underThousand(groupValue);
                if (unitIndex > 0 && unitIndex < units.size()) {
                    groupWords += ' ' + units[unitIndex];
                }
                groups.add(groupWords);
            }
            endIndex = startIndex;
            groupSize = 2;
            unitIndex++;
        }

        List<String> orderedGroups = new List<String>();
        for (Integer index = groups.size() - 1; index >= 0; index--) {
            orderedGroups.add(groups[index]);
        }
        return 'Rupees ' + (isNegative ? 'Minus ' : '') +
            String.join(orderedGroups, ' ') + ' Only';
    }

    private static String underThousand(Integer value) {
        List<String> belowTwenty = new List<String>{
            'Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
            'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
            'Seventeen', 'Eighteen', 'Nineteen'
        };
        List<String> tens = new List<String>{
            '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
        };

        List<String> words = new List<String>();
        if (value >= 100) {
            words.add(belowTwenty[value / 100] + ' Hundred');
            value = Math.mod(value, 100);
        }
        if (value >= 20) {
            words.add(tens[value / 10]);
            value = Math.mod(value, 10);
        }
        if (value > 0) {
            words.add(belowTwenty[value]);
        }
        return String.join(words, ' ');
    }

    // --------------------------------------------------------------- landowner

    private static String currentPageUrl() {
        return ApexPages.currentPage() == null || ApexPages.currentPage().getUrl() == null
            ? ''
            : ApexPages.currentPage().getUrl().toUpperCase();
    }

    private static String getOwnerForCurrentPage() {
        String pageUrl = currentPageUrl();
        for (String pageKey : PAGE_OWNERS.keySet()) {
            if (pageUrl.contains(pageKey)) {
                return PAGE_OWNERS.get(pageKey);
            }
        }
        return null;
    }

    private static String getOwnerDisplayName(String owner) {
        return owner != null && OWNER_DISPLAY_NAMES.containsKey(owner)
            ? OWNER_DISPLAY_NAMES.get(owner)
            : '';
    }
}