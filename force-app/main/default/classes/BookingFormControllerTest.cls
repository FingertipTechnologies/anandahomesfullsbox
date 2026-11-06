/**
 * @description Unit tests for BookingFormController (BookingForm_LEGACY PDF).
 *
 *              Covers:
 *                - Full booking: every section mapped from its primary field,
 *                  Second Applicant + Co_Applicant__c records, page layout,
 *                  price details and acknowledgement.
 *                - Fallback booking: secondary fields used when primary ones
 *                  are blank, unit tower, area fallback, balance floor at 0.
 *                - Booking without unit or dates: CreatedDate fallback and
 *                  blank co-applicant section.
 *                - Invalid input: no page, missing, malformed, wrong-object
 *                  and unknown ids.
 *                - Pure helpers: page split rule and formatters.
 */
@IsTest
private class BookingFormControllerTest {

    private static final String FULL_APPLICANT = 'Ravi Kumar';
    private static final String FALLBACK_APPLICANT = 'Meena Iyer';
    private static final String NO_UNIT_APPLICANT = 'No Unit Customer';

    private static final String HEADING = 'DETAILS OF CO-APPLICANT';

    // =====================================================================
    // Test data
    // =====================================================================

    @TestSetup
    static void createTestData() {
        Project__c fullProject = postSalesTestDataFactory.createProject('Legacy Full Project');
        Project__c fallbackProject = postSalesTestDataFactory.createProject('Legacy Fallback Project');
        fullProject.Booking_Amount__c = 300000;
        fallbackProject.Booking_Amount__c = 100000;
        update new List<Project__c>{ fullProject, fallbackProject };

        Block__c bookingTower = new Block__c(Name = 'Tower A', Project__c = fullProject.Id);
        Block__c unitTower = new Block__c(Name = 'Tower B', Project__c = fallbackProject.Id);
        insert new List<Block__c>{ bookingTower, unitTower };

        Plot__c fullUnit = new Plot__c(
            Project__c = fullProject.Id,
            Name = 'A-101',
            Unit_Type__c = 'Apartment',
            Status__c = 'Available',
            Block1__c = unitTower.Id,
            Saleable_Area_Sft__c = 1250,
            Facing__c = 'East Facing',
            BHK_Type__c = '2 BHK',
            GST1__c = 5
        );
        Plot__c fallbackUnit = new Plot__c(
            Project__c = fallbackProject.Id,
            Name = 'B-202',
            Unit_Type__c = 'Apartment',
            Status__c = 'Available',
            Block1__c = unitTower.Id,
            Saleable_Area_Sft__c = 0,
            Super_built_up_area__c = 1500
        );
        insert new List<Plot__c>{ fullUnit, fallbackUnit };

        // The "Booking After Create Handler" flow runs for every booking with a
        // unit and requires Quote__c (FieldMapperInvocable sourceRecordId); it
        // also creates the booking-amount receipt, so Mode_Of_Payment__c is set
        // the same way postSalesTestDataFactory.createBooking() does.
        Quote__c fullQuote = postSalesTestDataFactory.createQuote(fullProject.Id);
        Quote__c fallbackQuote = postSalesTestDataFactory.createQuote(fallbackProject.Id);

        Booking__c fullBooking = new Booking__c(
            Project__c = fullProject.Id,
            Plot__c = fullUnit.Id,
            Quote__c = fullQuote.Id,
            Block__c = bookingTower.Id,
            Status__c = 'New',
            Mode_Of_Payment__c = 'UPI',
            Booking_Date__c = Date.newInstance(2026, 10, 31),

            salutation_Applicant1__c = 'Mr',
            First_Applicant_Name__c = FULL_APPLICANT,
            Son_Daughter_Wife_of__c = 'Suresh Kumar',
            Mobile_Primary__c = '9876543210',
            Email1__c = 'ravi.kumar@example.com',
            Date_of_Birth1__c = Date.newInstance(1980, 5, 7),
            Occupation__c = 'Software Engineer',
            Aadhaar_Number__c = '111122223333',
            PAN_Number1__c = 'ABCDE1234F',
            Address__c = 'Flat 12, MG Road, Hyderabad',

            salutation_Applicant2__c = 'Mrs',
            Second_Applicant_Name__c = 'Lakshmi Rao',
            Son_Daughter_Wife_of1__c = 'Ravi Kumar',
            Mobile_Primary1__c = '9876500000',
            Email2__c = 'lakshmi.rao@example.com',
            Date_of_birth_Applicant2__c = Date.newInstance(1985, 1, 20),
            Occupation1__c = 'Business',
            Aadhaar_Number1__c = '444455556666',
            Pan_Number_Applicant2__c = 'FGHIJ5678K',
            Permanent_Address1__c = 'Flat 12, MG Road, Hyderabad',

            Total_Flat_Cost__c = 10000000,
            GST_Amount__c = 500000,
            Booking_Amount__c = 200000,
            Funding_Type__c = 'Loan',
            Loan_Sanctioned_Amount__c = 1000000,
            Cheque_Transaction_No__c = 'TXN12345',
            Bank_Name__c = 'HDFC Bank'
        );
        Booking__c fallbackBooking = new Booking__c(
            Project__c = fallbackProject.Id,
            Plot__c = fallbackUnit.Id,
            Quote__c = fallbackQuote.Id,
            Status__c = 'New',
            Mode_Of_Payment__c = 'UPI',
            Date_of_Booking__c = Date.newInstance(2026, 9, 1),
            Facing__c = 'North',
            BHK_Type__c = '1 BHK',

            First_Applicant_Name__c = FALLBACK_APPLICANT,
            Mobile__c = '9123456780',
            Email__c = 'meena.iyer@example.com',
            Date_of_Birth__c = Date.newInstance(1990, 8, 15),
            Occupation__c = 'Engineer',
            Aadhaar__c = '123412341234',
            PAN_Number__c = 'PQRSX6789Z',
            Permanent_Address__c = 'Plot 7, Banjara Hills, Hyderabad',

            Booking_Amount__c = 200000,
            Funding_Type__c = 'Self-Funded',
            Cheque_DD_NEFT_RTGS_No__c = 'CHQ-9876'
        );
        Booking__c noUnitBooking = new Booking__c(
            Project__c = fullProject.Id,
            Status__c = 'New',
            First_Applicant_Name__c = NO_UNIT_APPLICANT
        );
        insert new List<Booking__c>{ fullBooking, fallbackBooking, noUnitBooking };

        insert new List<Co_Applicant__c>{
            new Co_Applicant__c(
                Booking__c = fullBooking.Id,
                Salutation__c = 'Ms',
                Full_Name__c = 'Anita Sharma',
                W_o_S_o_C_o_c__c = 'Mohan Sharma',
                Contact_Number__c = '9000000001',
                Email__c = 'anita.sharma@example.com',
                Date_of_Birth__c = Date.newInstance(1988, 3, 9),
                Occupation__c = 'Doctor',
                Aadhar_Number__c = '777788889999',
                PAN_Number__c = 'KLMNO1234P',
                Permenent_Address__c = 'Lane 3, Kondapur, Hyderabad'
            ),
            new Co_Applicant__c(
                Booking__c = fullBooking.Id,
                Salutation__c = 'Dr',
                Full_Name__c = 'Vikram Singh',
                Contact_Number__c = '9000000002'
            ),
            new Co_Applicant__c(
                Booking__c = fallbackBooking.Id,
                First_Name__c = 'Sita',
                Last_Name__c = 'Devi',
                Contact_Number__c = '9988776655',
                Address__c = 'Ameerpet, Hyderabad'
            )
        };
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    private static Booking__c findBooking(String applicantName) {
        return [
            SELECT Id, Name, CreatedDate
            FROM Booking__c
            WHERE First_Applicant_Name__c = :applicantName
            LIMIT 1
        ];
    }

    /** Builds the controller the way the Visualforce page does. */
    private static BookingFormController openForm(String idParam) {
        PageReference page = Page.BookingForm_LEGACY;
        if (idParam != null) {
            page.getParameters().put('id', idParam);
        }
        Test.setCurrentPage(page);
        return new BookingFormController();
    }

    private static List<BookingFormController.CoApplicant> people(Integer count) {
        List<BookingFormController.CoApplicant> result = new List<BookingFormController.CoApplicant>();
        for (Integer i = 0; i < count; i++) {
            BookingFormController.CoApplicant co = new BookingFormController.CoApplicant();
            co.name = 'Person ' + (i + 1);
            result.add(co);
        }
        return result;
    }

    // =====================================================================
    // Full booking
    // =====================================================================

    @IsTest
    static void fullBookingMapsFlatDetailsAndApplicant() {
        Booking__c booking = findBooking(FULL_APPLICANT);

        Test.startTest();
        BookingFormController form = openForm(booking.Id);
        Test.stopTest();

        Assert.isFalse(form.hasError, 'No error expected: ' + form.errorMessage);
        Assert.areEqual(booking.Name, form.bookingNumber, 'Booking number');
        Assert.areEqual('31/10/2026', form.bookingDate, 'Booking date from Booking_Date__c');
        Assert.areEqual('Tower A', form.towerName, 'Tower from Booking__c.Block__c');
        Assert.areEqual('A-101', form.flatNo, 'Flat number from unit name');
        Assert.areEqual('1,250 Sft', form.flatArea, 'Saleable area');
        Assert.areEqual('East Facing', form.facing, 'Facing from unit');
        Assert.areEqual('2 BHK', form.flatConfiguration, 'Configuration from unit BHK type');

        Assert.areEqual('Mr. Ravi Kumar', form.applicantName, 'Applicant name with salutation');
        Assert.areEqual('Suresh Kumar', form.applicantFatherName, 'Father / husband name');
        Assert.areEqual('9876543210', form.applicantPhone, 'Primary mobile');
        Assert.areEqual('ravi.kumar@example.com', form.applicantEmail, 'Primary email');
        Assert.areEqual('07/05/1980', form.applicantDOB, 'Primary date of birth');
        Assert.areEqual('Software Engineer', form.applicantOccupation, 'Occupation');
        Assert.areEqual('111122223333', form.applicantAadhar, 'Primary Aadhaar');
        Assert.areEqual('ABCDE1234F', form.applicantPAN, 'Primary PAN');
        Assert.areEqual('Flat 12, MG Road, Hyderabad', form.applicantAddress, 'Permanent address');
    }

    @IsTest
    static void fullBookingListsEveryCoApplicantInOrder() {
        Booking__c booking = findBooking(FULL_APPLICANT);

        Test.startTest();
        BookingFormController form = openForm(booking.Id);
        Test.stopTest();

        Assert.areEqual(3, form.coApplicants.size(), 'Second Applicant + 2 Co_Applicant__c records');

        BookingFormController.CoApplicant second = form.coApplicants[0];
        Assert.areEqual(HEADING + ' 1', second.heading, 'Numbered heading');
        Assert.areEqual('Mrs. Lakshmi Rao', second.name, 'Second Applicant comes first');
        Assert.areEqual('Ravi Kumar', second.fatherName, 'Second Applicant relation');
        Assert.areEqual('9876500000', second.phone, 'Second Applicant mobile');
        Assert.areEqual('lakshmi.rao@example.com', second.email, 'Second Applicant email');
        Assert.areEqual('20/01/1985', second.dob, 'Second Applicant date of birth');
        Assert.areEqual('Business', second.occupation, 'Second Applicant occupation');
        Assert.areEqual('444455556666', second.aadhar, 'Second Applicant Aadhaar');
        Assert.areEqual('FGHIJ5678K', second.pan, 'Second Applicant PAN');
        Assert.areEqual('Flat 12, MG Road, Hyderabad', second.address, 'Second Applicant address');

        BookingFormController.CoApplicant record = form.coApplicants[1];
        Assert.areEqual(HEADING + ' 2', record.heading, 'Numbered heading');
        Assert.areEqual('Ms. Anita Sharma', record.name, 'Full_Name__c with salutation');
        Assert.areEqual('Mohan Sharma', record.fatherName, 'Co-applicant relation');
        Assert.areEqual('9000000001', record.phone, 'Contact number');
        Assert.areEqual('anita.sharma@example.com', record.email, 'Co-applicant email');
        Assert.areEqual('09/03/1988', record.dob, 'Co-applicant date of birth');
        Assert.areEqual('Doctor', record.occupation, 'Co-applicant occupation');
        Assert.areEqual('777788889999', record.aadhar, 'Co-applicant Aadhaar');
        Assert.areEqual('KLMNO1234P', record.pan, 'Co-applicant PAN');
        Assert.areEqual('Lane 3, Kondapur, Hyderabad', record.address, 'Permenent_Address__c');

        Assert.areEqual(HEADING + ' 3', form.coApplicants[2].heading, 'Numbered heading');
        Assert.areEqual('Dr. Vikram Singh', form.coApplicants[2].name, 'Oldest record first');

        // 3 co-applicants -> [Co1, Co2] then [Co3 + price details]
        Assert.areEqual(2, form.coApplicantPages.size(), 'Two pages after the first applicant');
        Assert.areEqual(2, form.coApplicantPages[0].coApplicants.size(), 'First page is full');
        Assert.isFalse(form.coApplicantPages[0].showPriceDetails, 'No price on first page');
        Assert.isTrue(form.coApplicantPages[0].coApplicants[0].isFirstOnPage, 'Top section flag');
        Assert.isFalse(form.coApplicantPages[0].coApplicants[1].isFirstOnPage, 'Second section flag');
        Assert.areEqual(1, form.coApplicantPages[1].coApplicants.size(), 'Last co-applicant');
        Assert.isTrue(form.coApplicantPages[1].showPriceDetails, 'Price shares the last page');
        Assert.isTrue(form.coApplicantPages[1].hasCoApplicants, 'Last page has a co-applicant');
    }

    @IsTest
    static void fullBookingMapsPriceDetailsAndAcknowledgement() {
        Booking__c booking = findBooking(FULL_APPLICANT);

        Test.startTest();
        BookingFormController form = openForm(booking.Id);
        Test.stopTest();

        Assert.areEqual('Rs. 1,00,00,000', form.finalPrice, 'Total_Flat_Cost__c');
        Assert.areEqual('Rs. 3,00,000', form.bookingAmountPayable, 'Project__c.Booking_Amount__c');
        Assert.areEqual('Rs. 2,00,000', form.advancePaid, 'Booking__c.Booking_Amount__c');
        Assert.areEqual('Rs. 1,00,000', form.balanceBookingAmount, 'Payable minus advance');
        Assert.areEqual('Rs. 1,00,000', form.tdsPayable, 'TDS__c (1% of flat cost)');
        Assert.areEqual('Rs. 5,00,000', form.gstPayable, 'GST_Amount__c');
        Assert.areEqual('Rs. 15,000', form.gstOnBookingAmount, 'Booking amount x Plot__c.GST1__c 5%');
        Assert.areEqual('Rs. 10,00,000', form.loanAmount, 'Loan_Sanctioned_Amount__c');
        Assert.isTrue(form.isBankLoan, 'Loan funding ticks Bank Loan');
        Assert.isFalse(form.isSelfFunded, 'Loan funding does not tick Self');

        Assert.areEqual('TXN12345', form.chequeNumber, 'Cheque_Transaction_No__c');
        Assert.areEqual('HDFC Bank', form.bankName, 'Bank_Name__c');
    }

    // =====================================================================
    // Fallback fields
    // =====================================================================

    @IsTest
    static void fallbackBookingUsesSecondaryFields() {
        Booking__c booking = findBooking(FALLBACK_APPLICANT);

        Test.startTest();
        BookingFormController form = openForm(booking.Id);
        Test.stopTest();

        Assert.isFalse(form.hasError, 'No error expected: ' + form.errorMessage);
        Assert.areEqual('01/09/2026', form.bookingDate, 'Date_of_Booking__c fallback');
        Assert.areEqual('Tower B', form.towerName, 'Unit tower (Block1__c) fallback');
        Assert.areEqual('1,500 Sft', form.flatArea, 'Super built-up area when saleable area is 0');
        Assert.areEqual('North', form.facing, 'Booking facing fallback');
        Assert.areEqual('1 BHK', form.flatConfiguration, 'Booking BHK fallback');

        Assert.areEqual(FALLBACK_APPLICANT, form.applicantName, 'No salutation');
        Assert.areEqual('9123456780', form.applicantPhone, 'Mobile__c fallback');
        Assert.areEqual('meena.iyer@example.com', form.applicantEmail, 'Email__c fallback');
        Assert.areEqual('15/08/1990', form.applicantDOB, 'Date_of_Birth__c fallback');
        Assert.areEqual('123412341234', form.applicantAadhar, 'Aadhaar__c fallback');
        Assert.areEqual('PQRSX6789Z', form.applicantPAN, 'PAN_Number__c fallback');
        Assert.areEqual('Plot 7, Banjara Hills, Hyderabad', form.applicantAddress, 'Permanent_Address__c fallback');
        Assert.areEqual('', form.applicantFatherName, 'Blank field prints empty');

        Assert.areEqual(1, form.coApplicants.size(), 'One Co_Applicant__c record');
        BookingFormController.CoApplicant co = form.coApplicants[0];
        Assert.areEqual(HEADING, co.heading, 'Single co-applicant is not numbered');
        Assert.areEqual('Sita Devi', co.name, 'First + Last name when Full_Name__c is blank');
        Assert.areEqual('9988776655', co.phone, 'Contact_Number__c');
        Assert.areEqual('Ameerpet, Hyderabad', co.address, 'Address__c fallback');
        Assert.areEqual(1, form.coApplicantPages.size(), '[Co1 + price details]');
        Assert.isTrue(form.coApplicantPages[0].showPriceDetails, 'Price on the same page');

        Assert.areEqual('Rs. 1,00,000', form.bookingAmountPayable, 'Project booking amount');
        Assert.areEqual('Rs. 2,00,000', form.advancePaid, 'Advance paid');
        Assert.areEqual('Rs. 0', form.balanceBookingAmount, 'Balance never goes below zero');
        Assert.areEqual('', form.gstOnBookingAmount, 'Blank when the unit has no GST %');
        Assert.areEqual('', form.finalPrice, 'Blank flat cost prints empty');
        Assert.areEqual('', form.gstPayable, 'Blank GST amount prints empty');
        Assert.areEqual('', form.loanAmount, 'Blank loan amount prints empty');
        Assert.isTrue(form.isSelfFunded, 'Self funding ticks Self');
        Assert.isFalse(form.isBankLoan, 'Self funding does not tick Bank Loan');
        Assert.areEqual('CHQ-9876', form.chequeNumber, 'Cheque_DD_NEFT_RTGS_No__c fallback');
        Assert.areEqual('', form.bankName, 'Blank bank prints empty');
    }

    @IsTest
    static void bookingWithoutUnitOrDatesFallsBackToCreatedDate() {
        Booking__c booking = findBooking(NO_UNIT_APPLICANT);
        Datetime createdAt = Datetime.newInstance(2026, 1, 15, 10, 30, 0);
        Test.setCreatedDate(booking.Id, createdAt);

        Test.startTest();
        BookingFormController form = openForm(booking.Id);
        Test.stopTest();

        Assert.isFalse(form.hasError, 'No error expected: ' + form.errorMessage);
        Assert.areEqual(createdAt.format('dd/MM/yyyy'), form.bookingDate, 'CreatedDate fallback');
        Assert.areEqual('', form.flatNo, 'No unit');
        Assert.areEqual('', form.flatArea, 'No unit area');
        Assert.areEqual('', form.towerName, 'No tower');
        Assert.areEqual('', form.bookingAmountPayable, 'No unit project amount');
        Assert.areEqual('', form.balanceBookingAmount, 'No balance without booking amount');
        Assert.isTrue(form.coApplicants.isEmpty(), 'No co-applicants');
        Assert.areEqual(1, form.coApplicantPages.size(), 'Blank section + price details');
        Assert.areEqual(HEADING, form.coApplicantPages[0].coApplicants[0].heading, 'Blank section heading');
        Assert.areEqual('', form.coApplicantPages[0].coApplicants[0].name, 'Blank section values');
    }

    // =====================================================================
    // Invalid input
    // =====================================================================

    @IsTest
    static void missingCurrentPageReportsMissingId() {
        Test.startTest();
        BookingFormController form = new BookingFormController();
        Test.stopTest();

        Assert.isTrue(form.hasError, 'Error expected');
        Assert.areEqual(BookingFormController.MSG_MISSING_ID, form.errorMessage, 'Missing id message');
        Assert.areEqual(1, form.coApplicantPages.size(), 'Form still renders with blank lines');
    }

    @IsTest
    static void blankIdReportsMissingId() {
        Test.startTest();
        BookingFormController form = openForm('   ');
        Test.stopTest();

        Assert.areEqual(BookingFormController.MSG_MISSING_ID, form.errorMessage, 'Blank id message');
    }

    @IsTest
    static void malformedIdReportsInvalidId() {
        Test.startTest();
        BookingFormController form = openForm('not-a-salesforce-id');
        Test.stopTest();

        Assert.areEqual(BookingFormController.MSG_INVALID_ID, form.errorMessage, 'Malformed id message');
    }

    @IsTest
    static void idOfAnotherObjectReportsInvalidId() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        BookingFormController form = openForm(project.Id);
        Test.stopTest();

        Assert.areEqual(BookingFormController.MSG_INVALID_ID, form.errorMessage, 'Wrong object message');
    }

    @IsTest
    static void unknownBookingIdReportsNotFound() {
        String keyPrefix = Booking__c.SObjectType.getDescribe().getKeyPrefix();
        String unknownId = keyPrefix + '000000000000';

        Test.startTest();
        BookingFormController form = openForm(unknownId);
        Test.stopTest();

        Assert.areEqual(BookingFormController.MSG_NOT_FOUND, form.errorMessage, 'Not found message');
        Assert.areEqual('', form.applicantName, 'Nothing mapped');
    }

    // =====================================================================
    // Page split rule
    // =====================================================================

    @IsTest
    static void pageSplitKeepsCoApplicantPagesFull() {
        Test.startTest();
        List<BookingFormController.CoApplicantPage> none = BookingFormController.buildCoApplicantPages(people(0));
        List<BookingFormController.CoApplicantPage> nullList = BookingFormController.buildCoApplicantPages(null);
        List<BookingFormController.CoApplicantPage> one = BookingFormController.buildCoApplicantPages(people(1));
        List<BookingFormController.CoApplicantPage> two = BookingFormController.buildCoApplicantPages(people(2));
        List<BookingFormController.CoApplicantPage> four = BookingFormController.buildCoApplicantPages(people(4));
        List<BookingFormController.CoApplicantPage> five = BookingFormController.buildCoApplicantPages(people(5));
        Test.stopTest();

        // 0 -> [blank + Price]
        Assert.areEqual(1, none.size(), '0: one page');
        Assert.isTrue(none[0].showPriceDetails, '0: price on that page');
        Assert.areEqual(HEADING, none[0].coApplicants[0].heading, '0: blank section');
        Assert.areEqual(1, nullList.size(), 'null list treated as empty');

        // 1 -> [Co1 + Price]
        Assert.areEqual(1, one.size(), '1: one page');
        Assert.isTrue(one[0].showPriceDetails, '1: price shares the page');

        // 2 -> [Co1, Co2] [Price]
        Assert.areEqual(2, two.size(), '2: two pages');
        Assert.areEqual(2, two[0].coApplicants.size(), '2: both on the first page');
        Assert.isFalse(two[0].showPriceDetails, '2: no price on the full page');
        Assert.isFalse(two[1].hasCoApplicants, '2: price-only page');
        Assert.isTrue(two[1].showPriceDetails, '2: price on its own page');

        // 4 -> [Co1, Co2] [Co3, Co4] [Price]
        Assert.areEqual(3, four.size(), '4: three pages');
        Assert.isFalse(four[2].hasCoApplicants, '4: price-only last page');

        // 5 -> [Co1, Co2] [Co3, Co4] [Co5 + Price]
        Assert.areEqual(3, five.size(), '5: three pages');
        Assert.areEqual('Person 5', five[2].coApplicants[0].name, '5: last co-applicant with price');
        Assert.isTrue(five[2].showPriceDetails, '5: price shares the last page');
    }

    // =====================================================================
    // Formatters
    // =====================================================================

    @IsTest
    static void formattersHandleIndianGroupingAndBlanks() {
        Test.startTest();
        String zero = BookingFormController.formatIndianNumber(0);
        String hundreds = BookingFormController.formatIndianNumber(999);
        String thousands = BookingFormController.formatIndianNumber(1250);
        String lakhs = BookingFormController.formatIndianNumber(123456);
        String crores = BookingFormController.formatIndianNumber(150000000);
        String withPaise = BookingFormController.formatIndianNumber(12345678.5);
        String negative = BookingFormController.formatIndianNumber(-25000);
        Test.stopTest();

        Assert.areEqual('0', zero, 'Zero');
        Assert.areEqual('999', hundreds, 'No comma below 1,000');
        Assert.areEqual('1,250', thousands, 'Thousands');
        Assert.areEqual('1,23,456', lakhs, 'Lakhs');
        Assert.areEqual('15,00,00,000', crores, 'Crores');
        Assert.areEqual('1,23,45,678.50', withPaise, 'Paise kept to 2 decimals');
        Assert.areEqual('-25,000', negative, 'Negative sign kept');

        Assert.areEqual('', BookingFormController.formatIndianNumber(null), 'Null number');
        Assert.areEqual('', BookingFormController.formatAmount(null), 'Null amount');
        Assert.areEqual('Rs. 3,00,000', BookingFormController.formatAmount(300000), 'Amount prefix');
        Assert.areEqual('', BookingFormController.formatArea(null), 'Null area');
        Assert.areEqual('', BookingFormController.formatDate(null), 'Null date');
        Assert.areEqual('05/11/2026', BookingFormController.formatDate(Date.newInstance(2026, 11, 5)), 'dd/MM/yyyy');
    }

    @IsTest
    static void salutationAndTextHelpersAreNullSafe() {
        Test.startTest();
        String standard = BookingFormController.withSalutation('Mrs', 'Lakshmi Rao');
        String alreadyDotted = BookingFormController.withSalutation('Prof.', 'Rao');
        String noSalutation = BookingFormController.withSalutation('', 'Rao');
        String noName = BookingFormController.withSalutation('Mr', '');
        String nullRecord = BookingFormController.textOf(null, 'Name');
        String blankField = BookingFormController.textOf(new Booking__c(), '');
        Test.stopTest();

        Assert.areEqual('Mrs. Lakshmi Rao', standard, 'Known salutation gets a dot');
        Assert.areEqual('Prof. Rao', alreadyDotted, 'Other titles kept as entered');
        Assert.areEqual('Rao', noSalutation, 'Name only');
        Assert.areEqual('', noName, 'No name prints empty');
        Assert.areEqual('', nullRecord, 'Null record prints empty');
        Assert.areEqual('', blankField, 'Blank field name prints empty');
    }
}