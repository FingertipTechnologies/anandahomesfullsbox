public with sharing class AgreementOfSaleController {
    public class ApplicantEntry {
        public Integer sequence { get; private set; }
        public String salutation { get; private set; }
        public String name { get; private set; }
        public String age { get; private set; }
        public String occupation { get; private set; }
        public String address { get; private set; }
        public String addressPrefix { get; private set; }
        public String aadhaar { get; private set; }
        public String pan { get; private set; }
        public String email { get; private set; }

        public String getDisplayName() {
            return String.isBlank(salutation) ? name : salutation + ' ' + name;
        }

        public String getLegalDetails() {
            List<String> details = new List<String>();
            if (!String.isBlank(age)) {
                details.add('aged about ' + age + ' years');
            }
            if (!String.isBlank(occupation)) {
                details.add('Occupation: ' + occupation);
            }
            if (!String.isBlank(address)) {
                details.add(addressPrefix + address);
            }
            details.add(
                '(Aadhaar No. ' + (aadhaar == null ? '' : aadhaar) +
                ' & PAN No. ' + (pan == null ? '' : pan) + ')'
            );
            return String.join(details, ', ');
        }

        private ApplicantEntry(
            Integer sequence,
            String salutation,
            String name,
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

        public String getTowerDisplay() {
            String tower = unit.Tower__c != null ? unit.Tower__c : unit.Tower_Block__c;
            if (String.isBlank(tower)) {
                return '';
            }

            Matcher towerMatch = Pattern.compile('(?i)^T-?(\\d+)$').matcher(tower);
            if (!towerMatch.matches()) {
                return tower;
            }

            String towerNumber = towerMatch.group(1);
            return 'T-' + (towerNumber.length() == 1 ? '0' : '') + towerNumber;
        }

        public String getFloorDisplay() {
            if (String.isBlank(unit.Floor__c)) {
                return '';
            }
            if (unit.Floor__c == 'G') {
                return 'Ground';
            }

            Matcher floorMatch = Pattern.compile('^(\\d+)$').matcher(unit.Floor__c);
            if (!floorMatch.matches()) {
                return unit.Floor__c;
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

        public String getFlatNumber() {
            if (!String.isBlank(unit.Plot_Number__c)) {
                return unit.Plot_Number__c;
            }
            if (String.isBlank(unit.Name)) {
                return '';
            }

            String tower = unit.Tower__c != null ? unit.Tower__c : unit.Tower_Block__c;
            String unitPrefix = String.isBlank(tower) ? null : tower + '-';
            if (unitPrefix != null && unit.Name.toUpperCase().startsWith(unitPrefix.toUpperCase())) {
                return unit.Name.substring(unitPrefix.length());
            }
            return unit.Name;
        }

        public String getFacingDisplay() {
            if (String.isBlank(unit.Facing__c)) {
                return '';
            }
            String suffix = ' Facing';
            return unit.Facing__c.toLowerCase().endsWith(suffix.toLowerCase())
                ? unit.Facing__c.substring(0, unit.Facing__c.length() - suffix.length())
                : unit.Facing__c;
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
    }

    public class PaymentScheduleRow {
        private Payment_Schedule__c schedule;

        private PaymentScheduleRow(Payment_Schedule__c schedule) {
            this.schedule = schedule;
        }

        public String getInstallmentName() {
            return schedule.Milestone_Name__c;
        }

        public String getDescription() {
            return schedule.Description__c;
        }

        public Decimal getPercentage() {
            return schedule.Percentage__c;
        }

        public Decimal getFlatCost() {
            return schedule.Flat_Cost__c;
        }

        public Decimal getNetAmount() {
            return schedule.Amount__c;
        }

        public String getFlatCostDisplay() {
            return formatIndianCurrency(getFlatCost());
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
    public Decimal totalOwnerSaleableArea { get; private set; }
    public Decimal totalReceiptAmount { get; private set; }
    public Decimal totalScheduleFlatCost { get; private set; }
    public Decimal totalScheduleNetAmount { get; private set; }
    public Decimal totalSchedulePercentage { get; private set; }

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
        totalOwnerSaleableArea = 0;
        totalReceiptAmount = 0;
        totalScheduleFlatCost = 0;
        totalScheduleNetAmount = 0;
        totalSchedulePercentage = 0;
        if (standardController == null || standardController.getId() == null) {
            return;
        }

        booking = [
            SELECT Id, Project__c, Plot__c, Car_Parking_Selected__c, No_of_car_parking__c,
                   First_Applicant_Name__c, Second_Applicant_Name__c, Salutation__c,
                   Date_of_Birth__c, Price_per_sqft__c, Basic_Price__c,
                   Total_Flat_Cost__c, Loan_Bank_Name__c,
                   Occupation__c, Address__c, Permanent_Address__c,
                   Aadhaar__c, PAN_Number__c, Email1__c
            FROM Booking__c
            WHERE Id = :standardController.getId()
            LIMIT 1
        ];
        addApplicant(
            booking.Salutation__c,
            booking.First_Applicant_Name__c,
            booking.Date_of_Birth__c,
            booking.Occupation__c,
            booking.Permanent_Address__c,
            'Resident of ',
            booking.Aadhaar__c,
            booking.PAN_Number__c,
            booking.Email1__c
        );
        Co_Applicant__c coApplicant = getCoApplicant(booking.Id, booking.Second_Applicant_Name__c);
        addApplicant(
            coApplicant == null ? null : coApplicant.Salutation__c,
            coApplicant == null ? null : coApplicant.Full_Name__c,
            coApplicant == null ? null : coApplicant.Date_of_Birth__c,
            coApplicant == null ? null : coApplicant.Occupation__c,
            booking.Permanent_Address__c,
            'Resident : ',
            coApplicant == null ? null : coApplicant.Aadhar_Number__c,
            coApplicant == null ? null : coApplicant.PAN_Number__c,
            coApplicant == null ? null : coApplicant.Email__c
        );
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
                       Covered_Park_Parking__c
                FROM Plot__c
                WHERE Id = :booking.Plot__c
                LIMIT 1
            ];
        }

        ownerName = getOwnerForCurrentPage();
        ownerDisplayName = getOwnerDisplayName(ownerName);

        if (ownerName == null || booking.Project__c == null) {
            return;
        }

        List<Plot__c> units = [
            SELECT Id, Name, Plot_Number__c, Tower__c, Tower_Block__c, Floor__c,
                   Saleable_Area_Sft__c, UDS__c, Facing__c
            FROM Plot__c
            WHERE Project__c = :booking.Project__c
              AND Share__c = 'LANDOWNER'
              AND LL_Share_Name__c = :ownerName
            ORDER BY Tower__c, Floor__c, Name
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
                   Receipt_Type__c
            FROM Receipt__c
            WHERE Booking__c = :bookingId
              AND Approval_Status__c = 'Approved'
            ORDER BY Receipt_Date__c ASC, CreatedDate ASC
        ]) {
            receiptRows.add(new ReceiptRow(receipt));
            totalReceiptAmount += receipt.Amount_received__c == null ? 0 : receipt.Amount_received__c;
        }

        for (Payment_Schedule__c schedule : [
            SELECT Id, Milestone_Name__c, Description__c, Percentage__c,
                   Flat_Cost__c, Amount__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :bookingId
            ORDER BY Sequence__c ASC NULLS LAST, S_No__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            PaymentScheduleRow row = new PaymentScheduleRow(schedule);
            paymentScheduleRows.add(row);
            totalScheduleFlatCost += row.getFlatCost() == null ? 0 : row.getFlatCost();
            totalScheduleNetAmount += row.getNetAmount() == null ? 0 : row.getNetAmount();
            totalSchedulePercentage += row.getPercentage() == null ? 0 : row.getPercentage();
        }
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

    private static Co_Applicant__c getCoApplicant(Id bookingId, String applicantName) {
        String normalizedApplicantName = normalizeApplicantName(applicantName);
        for (Co_Applicant__c coApplicant : [
            SELECT Full_Name__c, Salutation__c, Date_of_Birth__c, Occupation__c,
                   Aadhar_Number__c, PAN_Number__c, Email__c
            FROM Co_Applicant__c
            WHERE Booking__c = :bookingId
        ]) {
            if (!String.isBlank(normalizedApplicantName) &&
                normalizeApplicantName(coApplicant.Full_Name__c) == normalizedApplicantName) {
                return coApplicant;
            }
        }
        return null;
    }

    private static String normalizeApplicantName(String name) {
        return String.isBlank(name) ? '' : name.trim().replaceAll('\\s+', ' ').toUpperCase();
    }

    private void addApplicant(
        String salutation,
        String name,
        Date dateOfBirth,
        String occupation,
        String address,
        String addressPrefix,
        String aadhaar,
        String pan,
        String email
    ) {
        if (!String.isBlank(name)) {
            applicants.add(new ApplicantEntry(
                applicants.size() + 1,
                salutation,
                name,
                dateOfBirth,
                occupation,
                address,
                addressPrefix,
                aadhaar,
                pan,
                email
            ));
        }
    }

    public String getSelectedTowerDisplay() {
        if (selectedUnit == null) {
            return '';
        }
        OwnerUnitRow selectedRow = new OwnerUnitRow(selectedUnit, 1);
        String tower = selectedRow.getTowerDisplay();
        if (!tower.startsWith('T-')) {
            return tower;
        }
        String towerNumber = tower.substring(2);
        return towerNumber.length() > 1 && towerNumber.startsWith('0')
            ? towerNumber.substring(1)
            : towerNumber;
    }

    public String getSelectedFloorDisplay() {
        if (selectedUnit == null) {
            return '';
        }
        return new OwnerUnitRow(selectedUnit, 1).getFloorDisplay();
    }

    public String getSelectedFlatNumber() {
        if (selectedUnit == null) {
            return '';
        }
        return new OwnerUnitRow(selectedUnit, 1).getFlatNumber();
    }

    public String getSelectedFacingDisplay() {
        if (selectedUnit == null) {
            return '';
        }
        return new OwnerUnitRow(selectedUnit, 1).getFacingDisplay();
    }

    public String getSelectedBhkNumber() {
        if (selectedUnit == null || String.isBlank(selectedUnit.BHK_Type__c)) {
            return '';
        }

        Matcher bhkMatch = Pattern.compile('^\\s*(\\d+)').matcher(selectedUnit.BHK_Type__c);
        return bhkMatch.find() ? bhkMatch.group(1) : selectedUnit.BHK_Type__c;
    }

    public Decimal getSelectedWallArea() {
        if (selectedUnit == null || selectedUnit.Built_up_area__c == null ||
            selectedUnit.Carpet_Area__c == null || selectedUnit.Balcony_Area__c == null) {
            return null;
        }
        return selectedUnit.Built_up_area__c -
            selectedUnit.Carpet_Area__c -
            selectedUnit.Balcony_Area__c;
    }

    public Decimal getAmenitiesAmount() {
        if (booking == null || booking.Total_Flat_Cost__c == null || booking.Basic_Price__c == null) {
            return null;
        }
        return booking.Total_Flat_Cost__c - booking.Basic_Price__c;
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

    public String getFormattedPricePerSquareFoot() {
        return formatIndianCurrency(booking == null ? null : booking.Price_per_sqft__c);
    }

    public String getFormattedBasicPrice() {
        return formatIndianCurrency(booking == null ? null : booking.Basic_Price__c);
    }

    public String getFormattedAmenitiesAmount() {
        return formatIndianCurrency(getAmenitiesAmount());
    }

    public String getFormattedTotalFlatCost() {
        return formatIndianCurrency(booking == null ? null : booking.Total_Flat_Cost__c);
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

    public String getFormattedTotalScheduleNetAmount() {
        return formatIndianCurrency(totalScheduleNetAmount);
    }

    public String getSelectedCarParkingDisplay() {
        if (booking == null) {
            return '';
        }
        if (booking.No_of_car_parking__c != null && booking.No_of_car_parking__c > 0) {
            return underThousand(Integer.valueOf(booking.No_of_car_parking__c));
        }
        return booking.Car_Parking_Selected__c == true ? 'One' : 'None';
    }

    public String getSelectedCarParkingClause() {
        String parkingDisplay = getSelectedCarParkingDisplay();
        if (String.isBlank(parkingDisplay) || parkingDisplay == 'None') {
            return '';
        }
        String plural = booking.No_of_car_parking__c != null &&
            booking.No_of_car_parking__c > 1 ? ' Spaces' : '';
        return ' and ' + parkingDisplay + ' Car Parking' + plural;
    }

    public String getAmenitiesDescription() {
        String parkingDisplay = getSelectedCarParkingDisplay();
        if (String.isBlank(parkingDisplay) || parkingDisplay == 'None') {
            return 'Amenities including Infrastructure charges';
        }
        String plural = booking.No_of_car_parking__c != null &&
            booking.No_of_car_parking__c > 1 ? ' spaces' : '';
        return 'Amenities including ' + parkingDisplay + ' car parking' + plural +
            ' & Infrastructure charges';
    }

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
            return 'Zero Rupees Only';
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
        return (isNegative ? 'Minus ' : '') +
            String.join(orderedGroups, ' ') + ' Rupees Only';
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

    private static String getOwnerForCurrentPage() {
        String pageUrl = ApexPages.currentPage() == null
            ? ''
            : ApexPages.currentPage().getUrl().toUpperCase();
        if (pageUrl.contains('ARJUN_SINGH_AGREEMENT_OF_SALE')) {
            return 'ARJUN SINGH';
        }
        if (pageUrl.contains('MAGHAN_SINGH_AGREEMENT_OF_SALE')) {
            return 'MAGAN SINGH';
        }
        if (pageUrl.contains('SURESH_SINGH_AGREEMENT_OF_SALE')) {
            return 'SURESH SINGH';
        }
        return null;
    }

    private static String getOwnerDisplayName(String owner) {
        if (owner == 'ARJUN SINGH') {
            return 'Sri.K.Arjun Singh';
        }
        if (owner == 'MAGAN SINGH') {
            return 'Sri. Magan Singh';
        }
        if (owner == 'SURESH SINGH') {
            return 'Sri.K. Suresh Singh';
        }
        return '';
    }
}