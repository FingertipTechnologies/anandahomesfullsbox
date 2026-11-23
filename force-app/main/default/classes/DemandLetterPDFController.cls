public with sharing class DemandLetterPDFController {
    public class DemandLetterLineRow {
        public Demand_Line__c demandLine { get; private set; }
        public Decimal flatInstallmentAmount { get; private set; }
        public Decimal gstInstallmentAmount { get; private set; }

        public DemandLetterLineRow(
            Demand_Line__c demandLine,
            Decimal flatInstallmentAmount,
            Decimal gstInstallmentAmount
        ) {
            this.demandLine = demandLine;
            this.flatInstallmentAmount = flatInstallmentAmount;
            this.gstInstallmentAmount = gstInstallmentAmount;
        }

        // Amounts in Indian format (12,34,567) for the letters.
        public String flatInstallmentText { get { return formatIndian(flatInstallmentAmount); } }
        public String gstInstallmentText { get { return formatIndian(gstInstallmentAmount); } }
        public String tdsText { get { return formatIndian(demandLine.TDS_Amount__c); } }
        public String receivedText { get { return formatIndian(demandLine.Received_Amount__c); } }
        public String flatText { get { return formatIndian(demandLine.Flat_Amount__c); } }
        /** Full letter: the whole schedule amount including GST, before anything received. */
        public String schedulePayableText {
            get { return formatIndian(nz(demandLine.Flat_Amount__c) + nz(demandLine.GST_Amount__c) + nz(demandLine.Received_Amount__c)); }
        }
        /** Full letter: what is still to pay on the line (schedule amount less received). */
        public String netPayableText {
            get { return formatIndian(nz(demandLine.Flat_Amount__c) + nz(demandLine.GST_Amount__c)); }
        }
    }

    public String errorMessage { get; private set; }
    public String accountHolder { get; private set; }
    public String accountNumber { get; private set; }
    public String bankName { get; private set; }
    public String bankAccountType { get; private set; }
    public String ifscCode { get; private set; }
    public String accountBranch { get; private set; }
    public String branchCity { get; private set; }
    public String accountType { get; private set; }
    public List<Demand_Line__c> demandLines { get; private set; }
    public List<DemandLetterLineRow> demandLetterLineRows { get; private set; }

    /** "To," line: first applicant and co-applicants, e.g. "MR. A, MRS. B & MR. C" (client's demand letters). */
    public String addresseeNames { get; private set; }

    /** Sign-off company: "THE DRIZZLE JV" for The Drizzle (client's Drizzle demand letter), else ANANDA HOMES. */
    public String signatoryName { get; private set; }
    /** Demand total in Indian format and in words, e.g. "11,06,206" / "Rupees Eleven Lakh ... Only". */
    public String demandedAmountText { get; private set; }
    public String demandedAmountWords { get; private set; }
    public String gstAmountText { get; private set; }

    public DemandLetterPDFController(ApexPages.StandardController standardController) {
        accountType = resolveAccountType(ApexPages.currentPage().getUrl());
        if (String.isBlank(accountType)) {
            errorMessage = 'Use the Flat, GST, or Full demand-letter page.';
            return;
        }

        try {
            Demands__c pageDemand = (Demands__c) standardController.getRecord();
            if (pageDemand.Id == null) {
                errorMessage = 'A saved demand record is required to generate this letter.';
                return;
            }
            Demands__c demand = [
                SELECT Project__c, Project__r.Name, Demanded_Amount__c, GST_Amount__c
                FROM Demands__c
                WHERE Id = :pageDemand.Id
                LIMIT 1
            ];
            if (demand.Project__c == null) {
                errorMessage = 'The demand must be saved and linked to a project.';
                return;
            }
            signatoryName = signatoryFor(demand.Project__r == null ? null : demand.Project__r.Name);
            demandedAmountText = formatIndian(nz(demand.Demanded_Amount__c));
            demandedAmountWords = amountInWords(demand.Demanded_Amount__c);
            gstAmountText = formatIndian(nz(demand.GST_Amount__c));
            addresseeNames = buildAddresseeNames(pageDemand.Id);
            loadAccount(demand.Project__c);
            loadDemandLines(pageDemand.Id);
        } catch (QueryException e) {
            errorMessage = e.getMessage();
        } catch (Exception e) {
            errorMessage = 'Unable to load project account details: ' + e.getMessage();
        }
    }

    @TestVisible
    private static String buildAddresseeNames(Id demandId) {
        List<Demands__c> rows = [
            SELECT Booking__c, Booking__r.Salutation__c, Booking__r.First_Applicant_Name__c
            FROM Demands__c WHERE Id = :demandId LIMIT 1
        ];
        if (rows.isEmpty() || rows[0].Booking__c == null) return '';
        List<String> names = new List<String>();
        String first = joinName(rows[0].Booking__r.Salutation__c, rows[0].Booking__r.First_Applicant_Name__c);
        if (String.isNotBlank(first)) names.add(first);
        for (Co_Applicant__c c : [
            SELECT Salutation__c, Full_Name__c FROM Co_Applicant__c
            WHERE Booking__c = :rows[0].Booking__c ORDER BY CreatedDate ASC
        ]) {
            String name = joinName(c.Salutation__c, c.Full_Name__c);
            if (String.isNotBlank(name)) names.add(name);
        }
        String joined = '';
        for (Integer i = 0; i < names.size(); i++) {
            joined += (i == 0 ? '' : (i == names.size() - 1 ? ' & ' : ', ')) + names[i];
        }
        return joined.toUpperCase();
    }

    /** "Mr" + "A" -> "Mr. A" (a salutation that already ends with a full stop is left alone). */
    private static String joinName(String salutation, String name) {
        if (String.isBlank(name)) return '';
        if (String.isBlank(salutation)) return name.trim();
        String s = salutation.trim();
        return (s.endsWith('.') ? s : s + '.') + ' ' + name.trim();
    }

    private void loadDemandLines(Id demandId) {
        demandLines = [
            SELECT Id, Milestone_Name__c, Sequence__c, Percentage__c,
                   Demand_Component__c, Flat_Amount__c, GST_Amount__c,
                   TDS_Amount__c, Demand_Amount__c,
                   Received_Amount__c, Payment_Schedule__r.Payment_Schedule_Amount__c,
                   Payment_Schedule__r.TDS_Amount__c, Payment_Schedule__r.GST_Amount__c,
                   Payment_Schedule__r.Bank_Flat_Amount__c,
                   Payment_Schedule__r.Bank_GST_Amount__c,
                   Payment_Schedule__r.Customer_Flat_Prorata__c,
                   Payment_Schedule__r.Customer_GST_Prorata__c,
                   Demand__r.Demand_Audience__c,
                   Demand__r.Booking__r.Funding_Type__c,
                   Demand__r.Booking__r.Project__r.Legacy_Split_Demand_Receipt__c
            FROM Demand_Line__c
            WHERE Demand__c = :demandId
            ORDER BY Sequence__c ASC NULLS LAST, CreatedDate ASC
        ];
        demandLetterLineRows = new List<DemandLetterLineRow>();
        if (demandLines.isEmpty()) {
            Demands__c demand = [
                SELECT Demand_Component__c, Flat_Amount__c, GST_Amount__c,
                       TDS_Amount__c, Payment_Schedule__c,
                       Demand_Audience__c,
                       Booking__r.Funding_Type__c,
                       Booking__r.Project__r.Legacy_Split_Demand_Receipt__c,
                       Payment_Schedule__r.Name, Payment_Schedule__r.Milestone_Name__c,
                       Payment_Schedule__r.Sequence__c, Payment_Schedule__r.Percentage__c,
                       Payment_Schedule__r.Payment_Schedule_Amount__c,
                       Payment_Schedule__r.TDS_Amount__c,
                       Payment_Schedule__r.GST_Amount__c,
                       Payment_Schedule__r.Bank_Flat_Amount__c,
                       Payment_Schedule__r.Bank_GST_Amount__c,
                       Payment_Schedule__r.Customer_Flat_Prorata__c,
                       Payment_Schedule__r.Customer_GST_Prorata__c,
                       Payment_Schedule__r.Payment_Schedule_Amount_Paid__c,
                       Payment_Schedule__r.GST_Amount_Paid__c,
                       Payment_Schedule__r.TDS_Amount_Paid__c
                FROM Demands__c
                WHERE Id = :demandId
                LIMIT 1
            ];
            Payment_Schedule__c schedule = demand.Payment_Schedule__r;
            Decimal flatReceived = schedule == null
                || schedule.Payment_Schedule_Amount_Paid__c == null
                ? 0
                : schedule.Payment_Schedule_Amount_Paid__c;
            Decimal gstReceived = schedule == null || schedule.GST_Amount_Paid__c == null
                ? 0
                : schedule.GST_Amount_Paid__c;
            Decimal tdsReceived = schedule == null || schedule.TDS_Amount_Paid__c == null
                ? 0
                : schedule.TDS_Amount_Paid__c;
            Decimal receivedAmount = demand.Demand_Component__c == DemandComponentService.FLAT
                ? flatReceived + tdsReceived
                : demand.Demand_Component__c == DemandComponentService.GST
                    ? gstReceived
                    : flatReceived + gstReceived + tdsReceived;
            Decimal flatAmount = demand.Flat_Amount__c == null ? 0 : demand.Flat_Amount__c;
            Decimal gstAmount = demand.GST_Amount__c == null ? 0 : demand.GST_Amount__c;
            Decimal tdsAmount = demand.TDS_Amount__c == null ? 0 : demand.TDS_Amount__c;
            Demand_Line__c fallbackLine = new Demand_Line__c(
                Milestone_Name__c = schedule == null
                    ? ''
                    : (String.isNotBlank(schedule.Milestone_Name__c)
                        ? schedule.Milestone_Name__c
                        : schedule.Name),
                Sequence__c = schedule == null ? null : schedule.Sequence__c,
                Percentage__c = schedule == null ? null : schedule.Percentage__c,
                Demand_Component__c = demand.Demand_Component__c,
                Flat_Amount__c = flatAmount,
                GST_Amount__c = gstAmount,
                TDS_Amount__c = tdsAmount,
                Demand_Amount__c = flatAmount + gstAmount + tdsAmount,
                Received_Amount__c = receivedAmount
            );
            demandLines.add(fallbackLine);
            demandLetterLineRows.add(new DemandLetterLineRow(
                fallbackLine,
                flatInstallmentAmount(
                    fallbackLine,
                    schedule,
                    demand.Booking__r == null ? null : demand.Booking__r.Funding_Type__c,
                    demand.Booking__r != null
                        && demand.Booking__r.Project__r != null
                        && demand.Booking__r.Project__r.Legacy_Split_Demand_Receipt__c == true,
                    demand.Demand_Audience__c
                ),
                gstInstallmentAmount(
                    fallbackLine,
                    schedule,
                    demand.Booking__r == null ? null : demand.Booking__r.Funding_Type__c,
                    demand.Booking__r != null
                        && demand.Booking__r.Project__r != null
                        && demand.Booking__r.Project__r.Legacy_Split_Demand_Receipt__c == true,
                    demand.Demand_Audience__c
                )
            ));
        } else {
            for (Demand_Line__c demandLine : demandLines) {
                Demands__c demand = demandLine.Demand__r;
                Booking__c booking = demand == null ? null : demand.Booking__r;
                String fundingType = booking == null ? null : booking.Funding_Type__c;
                Boolean legacySplit = booking != null
                    && booking.Project__r != null
                    && booking.Project__r.Legacy_Split_Demand_Receipt__c == true;
                String audience = demand == null ? null : demand.Demand_Audience__c;
                demandLetterLineRows.add(new DemandLetterLineRow(
                    demandLine,
                    flatInstallmentAmount(
                        demandLine,
                        demandLine.Payment_Schedule__r,
                        fundingType,
                        legacySplit,
                        audience
                    ),
                    gstInstallmentAmount(
                        demandLine,
                        demandLine.Payment_Schedule__r,
                        fundingType,
                        legacySplit,
                        audience
                    )
                ));
            }
        }

    }

    @TestVisible
    private static Decimal flatInstallmentAmount(
        Demand_Line__c demandLine,
        Payment_Schedule__c schedule,
        String fundingType,
        Boolean legacySplitDemandReceipt,
        String demandAudience
    ) {
        if (isProrataOrPartial(legacySplitDemandReceipt, fundingType)) {
            if (demandLine.Demand_Component__c == DemandComponentService.GST
                && schedule != null) {
                Decimal componentFlat = demandAudience == 'Bank'
                    ? schedule.Bank_Flat_Amount__c
                    : schedule.Customer_Flat_Prorata__c;
                if (componentFlat != null) return componentFlat;
            }
            return nz(demandLine.Flat_Amount__c) + nz(demandLine.TDS_Amount__c);
        }
        if (schedule == null || schedule.Payment_Schedule_Amount__c == null) {
            return nz(demandLine.Flat_Amount__c) + nz(demandLine.TDS_Amount__c);
        }
        return schedule.Payment_Schedule_Amount__c + nz(schedule.TDS_Amount__c);
    }

    @TestVisible
    private static Decimal gstInstallmentAmount(
        Demand_Line__c demandLine,
        Payment_Schedule__c schedule,
        String fundingType,
        Boolean legacySplitDemandReceipt,
        String demandAudience
    ) {
        if (isProrataOrPartial(legacySplitDemandReceipt, fundingType) && schedule != null) {
            Decimal componentGst = demandAudience == 'Bank'
                ? schedule.Bank_GST_Amount__c
                : schedule.Customer_GST_Prorata__c;
            if (componentGst != null) return componentGst;
        }
        if (schedule != null && schedule.GST_Amount__c != null) {
            return schedule.GST_Amount__c;
        }
        return nz(demandLine.GST_Amount__c);
    }

    private static Boolean isProrataOrPartial(Boolean legacySplitDemandReceipt, String fundingType) {
        return legacySplitDemandReceipt == true
            && (fundingType == 'Prorata' || fundingType == 'Partial');
    }

    private static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }

    @TestVisible
    private static String signatoryFor(String projectName) {
        return projectName != null && projectName.containsIgnoreCase('Drizzle')
            ? 'THE DRIZZLE JV'
            : 'ANANDA HOMES';
    }

    /**
     * Indian digit grouping: 1106206 -> "11,06,206", 188165.62 -> "1,88,165.62" (paise shown only
     * when there are any). Blank for null.
     */
    @TestVisible
    private static String formatIndian(Decimal value) {
        if (value == null) return '';
        Decimal rounded = value.setScale(2, RoundingMode.HALF_UP);
        Boolean negative = rounded < 0;
        Decimal absolute = rounded.abs();
        Long rupees = absolute.round(System.RoundingMode.DOWN);
        Integer paise = ((absolute - rupees) * 100).intValue();
        String digits = String.valueOf(rupees);
        String grouped = digits;
        if (digits.length() > 3) {
            String head = digits.substring(0, digits.length() - 3);
            grouped = digits.substring(digits.length() - 3);
            while (head.length() > 2) {
                grouped = head.substring(head.length() - 2) + ',' + grouped;
                head = head.substring(0, head.length() - 2);
            }
            grouped = head + ',' + grouped;
        }
        if (paise > 0) grouped += '.' + String.valueOf(paise).leftPad(2, '0');
        return (negative ? '-' : '') + grouped;
    }

    /** "Rupees Eleven Lakh Six Thousand Two Hundred Six Only" (paise as "and Fifty Paise"). */
    @TestVisible
    private static String amountInWords(Decimal value) {
        Decimal rounded = nz(value).abs().setScale(2, RoundingMode.HALF_UP);
        Long rupees = rounded.round(System.RoundingMode.DOWN);
        Integer paise = ((rounded - rupees) * 100).intValue();
        NumberTOWordConvertion converter = new NumberTOWordConvertion();
        String words = converter.getNumberTOWordConvertion(rupees);
        if (paise > 0) {
            words = (rupees > 0 ? words.removeEnd(' Only') + ' and ' : '')
                + converter.getNumberTOWordConvertion(paise).removeEnd(' Only') + ' Paise Only';
        }
        return 'Rupees ' + words;
    }

    private void loadAccount(Id projectId) {
        Map<String, Schema.SObjectField> accountFields =
            Schema.SObjectType.Account_Name__c.fields.getMap();
        List<String> selectedFields = new List<String>{
            'Name', 'Account_No__c', 'Bank_Name__c', 'IFSC_Code__c', 'Branch__c'
        };
        if (accountFields.containsKey('Bank_Account_Type__c')) {
            selectedFields.add('Bank_Account_Type__c');
        }
        if (accountFields.containsKey('Branch_City__c')) {
            selectedFields.add('Branch_City__c');
        }

        String accountQuery = 'SELECT ' + String.join(selectedFields, ', ') +
            ' FROM Account_Name__c WHERE Project__c = :projectId' +
            ' AND Account_Type__c = :accountType ORDER BY LastModifiedDate DESC LIMIT 2';
        Boolean optionalFieldsQueried = selectedFields.size() > 5;
        List<Account_Name__c> matchingAccounts;
        try {
            matchingAccounts = Database.query(accountQuery);
        } catch (QueryException e) {
            if (!optionalFieldsQueried
                || (!e.getMessage().contains('Bank_Account_Type__c')
                    && !e.getMessage().contains('Branch_City__c'))) {
                throw e;
            }
            accountQuery = 'SELECT Name, Account_No__c, Bank_Name__c, IFSC_Code__c, Branch__c' +
                ' FROM Account_Name__c WHERE Project__c = :projectId' +
                ' AND Account_Type__c = :accountType ORDER BY LastModifiedDate DESC LIMIT 2';
            matchingAccounts = Database.query(accountQuery);
            optionalFieldsQueried = false;
        }

        if (matchingAccounts.isEmpty()) {
            errorMessage = 'No ' + accountType + ' Account Name is configured for this project.';
            return;
        }
        if (matchingAccounts.size() > 1) {
            errorMessage = 'More than one ' + accountType +
                ' Account Name is configured for this project.';
            return;
        }

        Account_Name__c selectedAccount = matchingAccounts[0];
        accountHolder = selectedAccount.Name;
        accountNumber = selectedAccount.Account_No__c;
        bankName = selectedAccount.Bank_Name__c;
        bankAccountType = optionalFieldsQueried
            && accountFields.containsKey('Bank_Account_Type__c')
            ? displayValue(selectedAccount.get('Bank_Account_Type__c'))
            : '';
        ifscCode = selectedAccount.IFSC_Code__c;
        accountBranch = selectedAccount.Branch__c;
        branchCity = optionalFieldsQueried
            && accountFields.containsKey('Branch_City__c')
            ? displayValue(selectedAccount.get('Branch_City__c'))
            : '';
    }

    @TestVisible
    private static String resolveAccountType(String pageUrl) {
        if (String.isBlank(pageUrl)) return null;
        if (pageUrl.contains('/DemandLetterFlat')) return 'Flat';
        if (pageUrl.contains('/DemandLetterGST')) return 'GST';
        if (pageUrl.contains('/DemandLetterFull')) return 'Full';
        return null;
    }

    private static String displayValue(Object value) {
        return value == null ? '' : String.valueOf(value);
    }
}