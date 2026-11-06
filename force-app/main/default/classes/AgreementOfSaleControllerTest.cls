@IsTest
private class AgreementOfSaleControllerTest {
    private static Booking__c buildBooking(String ownerName) {
        Project__c project = postSalesTestDataFactory.createProject('AOS Test Project');

        Plot__c bookedUnit = new Plot__c(
            Project__c = project.Id,
            Name = 'T1-707',
            Unit_Type__c = 'Apartment',
            Status__c = 'Available',
            Floor__c = '7',
            BHK_Type__c = '3 BHK',
            Facing__c = 'East Facing',
            Carpet_Area__c = 942,
            Balcony_Area__c = 146,
            Built_up_area__c = 1173,
            Common_Area_Allotted_to_Association__c = 347,
            Saleable_Area_Sft__c = 1520,
            UDS__c = 31.9,
            Boundary_North__c = 'OPEN TO SKY',
            Boundary_South__c = 'OPEN TO SKY',
            Boundary_East__c = 'CORRIDOR',
            Boundary_West__c = 'OPEN TO SKY',
            LL_Share_Name__c = ownerName
        );
        Plot__c otherOwnerUnit = new Plot__c(
            Project__c = project.Id,
            Name = 'T2-503',
            Unit_Type__c = 'Apartment',
            Status__c = 'Available',
            Floor__c = '5',
            Facing__c = 'West Facing',
            Saleable_Area_Sft__c = 1720,
            UDS__c = 36.09,
            LL_Share_Name__c = ownerName
        );
        Plot__c unrelatedUnit = new Plot__c(
            Project__c = project.Id,
            Name = 'T3-101',
            Unit_Type__c = 'Apartment',
            Status__c = 'Available',
            Saleable_Area_Sft__c = 999
        );
        insert new List<Plot__c>{ bookedUnit, otherOwnerUnit, unrelatedUnit };

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = bookedUnit.Id,
            // Required by the org's "Booking After Create Handler" flow (runs on
            // booking create): Quote__c as sourceRecordId + the booking-amount receipt.
            Quote__c = postSalesTestDataFactory.createQuote(project.Id).Id,
            Mode_Of_Payment__c = 'UPI',
            Booking_Amount__c = 100000,
            Booking_Date__c = Date.today().addDays(-30),
            Agreement_Date__c = Date.newInstance(2026, 3, 15),
            Status__c = 'New',
            First_Applicant_Name__c = 'Ravi Kumar Sample',
            Second_Applicant_Name__c = 'Sita Devi Sample',
            salutation_Applicant1__c = 'Mr',
            Relation_Details_Applicant1__c = 'S/o',
            Son_Daughter_Wife_of__c = 'Mohan Rao Sample',
            Date_of_Birth1__c = Date.today().addYears(-30),
            Designation__c = 'Private Employee',
            Address__c = 'H.No-1-1, Sample Street, Sample Town',
            Aadhaar_Number__c = '111122223333',
            PAN_Number1__c = 'ABCDE1234F',
            Email__c = 'ravi@example.com',
            Total_Flat_Cost__c = 10513680,
            Base_Price__c = 9513680,
            Price_per_sqft__c = 6259,
            GST_Amount__c = 525684,
            Car_Parking_Selected__c = true,
            Loan_Bank_Name__c = 'INDIAN BANK'
        );
        insert booking;

        insert new Co_Applicant__c(
            Booking__c = booking.Id,
            Full_Name__c = 'Sita Devi Sample',
            Salutation__c = 'Mrs',
            S_o_D_o_W_o__c = 'W/o',
            W_o_S_o_C_o_c__c = 'Ravi Kumar Sample',
            Date_of_Birth__c = Date.today().addYears(-28),
            Address__c = 'H.No-1-1, Sample Street, Sample Town',
            Aadhar_Number__c = '444455556666',
            PAN_Number__c = 'FGHIJ5678K',
            Email__c = 'sita@example.com'
        );

        insert new List<Receipt__c>{
            new Receipt__c(
                Booking__c = booking.Id,
                Receipt_Date__c = Date.newInstance(2024, 9, 24),
                Receipt_Type__c = 'Advance Payment',
                Cheque_Number__c = 'CHQ0001',
                Amount_received__c = 500000,
                Approval_Status__c = 'Approved'
            ),
            new Receipt__c(
                Booking__c = booking.Id,
                Receipt_Date__c = Date.newInstance(2024, 11, 11),
                Receipt_Type__c = 'Installment Payment',
                Payment_Reference_Number__c = 'UTR0002',
                Amount_received__c = 1581709,
                Approval_Status__c = 'Approved by Finance Team'
            ),
            new Receipt__c(
                Booking__c = booking.Id,
                Receipt_Date__c = Date.newInstance(2025, 1, 1),
                Receipt_Type__c = 'Installment Payment',
                Amount_received__c = 99999,
                Approval_Status__c = 'Pending Approval'
            )
        };

        insert new List<Payment_Schedule__c>{
            new Payment_Schedule__c(
                Booking__c = booking.Id, Status__c = 'Pending', Sequence__c = 1,
                Milestone_Name__c = 'Booking Amount', Percentage__c = 20,
                Payment_Schedule_Amount__c = 500000, TDS_Amount__c = 0,
                GST_Amount__c = 25000, Amount__c = 525000
            ),
            new Payment_Schedule__c(
                Booking__c = booking.Id, Status__c = 'Pending', Sequence__c = 2,
                Milestone_Name__c = 'Handover', Percentage__c = 80,
                Payment_Schedule_Amount__c = 2000000, TDS_Amount__c = 0,
                GST_Amount__c = 100000, Amount__c = 2100000
            )
        };
        return booking;
    }

    private static AgreementOfSaleController load(PageReference page, Booking__c booking) {
        Test.setCurrentPage(page);
        return new AgreementOfSaleController(new ApexPages.StandardController(booking));
    }

    @IsTest
    static void landownerPageLoadsApplicantsUnitsAndAmounts() {
        Booking__c booking = buildBooking('NAVEEN SINGH');

        Test.startTest();
        AgreementOfSaleController controller = load(Page.NAVEEN_SINGH_AGREEMENT_OF_SALE, booking);
        Test.stopTest();

        System.assertEquals('NAVEEN SINGH', controller.ownerName);
        System.assertEquals('Sri. Naveen Singh', controller.ownerDisplayName);
        System.assertEquals('', controller.getOwnerMismatchMessage());

        // applicants: primary from the booking-form field set, second from the co-applicant
        System.assertEquals(2, controller.applicants.size());
        System.assert(controller.getHasApplicants());
        System.assertEquals('SRI. RAVI KUMAR SAMPLE', controller.applicants[0].getDisplayName());
        System.assert(controller.applicants[0].getLegalDetails().startsWith('S/O. SRI. MOHAN RAO SAMPLE, aged about 30 years, Occupation: Private Employee, Resident of H.No-1-1'),
            controller.applicants[0].getLegalDetails());
        System.assert(controller.applicants[0].getLegalDetails().endsWith('(AADHAAR No. 111122223333 & PAN No. ABCDE1234F)'));
        System.assertEquals('SMT. SITA DEVI SAMPLE', controller.applicants[1].getDisplayName());
        System.assert(controller.applicants[1].getLegalDetails().startsWith('W/O. SRI. RAVI KUMAR SAMPLE, aged about 28 years'));
        System.assertEquals('SRI. RAVI KUMAR SAMPLE & SMT. SITA DEVI SAMPLE', controller.buyerNames);
        System.assertEquals('H.No-1-1, Sample Street, Sample Town', controller.getBuyerAddress());
        System.assertEquals('ravi@example.com', controller.getBuyerEmail());

        // selected unit
        System.assert(controller.getHasSelectedUnit());
        System.assertEquals('1', controller.getSelectedTowerDisplay());
        System.assertEquals('707', controller.getSelectedFlatNumber());
        System.assertEquals('T1-707', controller.getSelectedFlatLabel());
        System.assertEquals('7th', controller.getSelectedFloorDisplay());
        System.assertEquals('East', controller.getSelectedFacingDisplay());
        System.assertEquals('EAST', controller.getSelectedFacingUpper());
        System.assertEquals('3', controller.getSelectedBhkNumber());
        System.assertEquals(85, controller.getSelectedWallArea());
        System.assertEquals('One', controller.getSelectedCarParkingDisplay());
        System.assertEquals(' and One Car Parking', controller.getSelectedCarParkingClause());
        System.assertEquals('Amenities including One car parking & Infrastructure charges', controller.getAmenitiesDescription());

        // landowner units (LL Share Name), excluding the unrelated unit
        System.assert(controller.getHasOwnerUnits());
        System.assertEquals(2, controller.ownerUnits.size());
        System.assertEquals(3240, controller.totalOwnerSaleableArea);
        System.assertEquals('T-01', controller.ownerUnits[0].getTowerDisplay());
        System.assertEquals('707', controller.ownerUnits[0].getFlatNumber());
        System.assertEquals('West', controller.ownerUnits[1].getFacingDisplay());
        System.assertEquals('5th', controller.ownerUnits[1].getFloorDisplay());

        // amounts
        System.assertEquals('1,05,13,680', controller.getFormattedTotalFlatCost());
        System.assertEquals('95,13,680', controller.getFormattedBasicPrice());
        System.assertEquals('6,259', controller.getFormattedPricePerSquareFoot());
        System.assertEquals('10,00,000', controller.getFormattedAmenitiesAmount());
        System.assertEquals('5,25,684', controller.getFormattedGstAmount());
        System.assertEquals('Rupees One Crore Five Lakh Thirteen Thousand Six Hundred Eighty Only', controller.getAgreementAmountInWords());
        System.assertEquals('Rupees Five Lakh Twenty Five Thousand Six Hundred Eighty Four Only', controller.getGstAmountInWords());
        System.assertEquals('INDIAN BANK', controller.getLoanBankName());

        // receipts: only approved ones, in date order
        System.assert(controller.getHasReceipts());
        System.assertEquals(2, controller.receiptRows.size());
        System.assertEquals('Advance Payment', controller.receiptRows[0].getMode());
        System.assertEquals('CHQ0001', controller.receiptRows[0].getReferenceId());
        System.assertEquals('UTR0002', controller.receiptRows[1].getReferenceId());
        System.assertEquals('5,00,000', controller.receiptRows[0].getAmountDisplay());
        System.assertEquals(2081709, controller.totalReceiptAmount);
        System.assertEquals('20,81,709', controller.getFormattedTotalReceiptAmount());
        System.assertEquals('84,31,971', controller.getFormattedBalanceAmount());
        System.assertEquals('Rupees Eighty Four Lakh Thirty One Thousand Nine Hundred Seventy One Only', controller.getBalanceAmountInWords());

        // payment schedule incl. GST column
        System.assert(controller.getHasPaymentSchedules());
        System.assertEquals(2, controller.paymentScheduleRows.size());
        System.assertEquals('Booking Amount', controller.paymentScheduleRows[0].getInstallmentName());
        System.assertEquals('5,00,000', controller.paymentScheduleRows[0].getFlatCostDisplay());
        System.assertEquals('25,000', controller.paymentScheduleRows[0].getGstAmountDisplay());
        System.assertEquals('5,25,000', controller.paymentScheduleRows[0].getNetAmountDisplay());
        System.assertEquals(100, controller.totalSchedulePercentage);
        System.assertEquals('25,00,000', controller.getFormattedTotalScheduleFlatCost());
        System.assertEquals('1,25,000', controller.getFormattedTotalScheduleGst());
        System.assertEquals('26,25,000', controller.getFormattedTotalScheduleNetAmount());
    }

    @IsTest
    static void builderSharePageHasNoLandownerAndFlagsLandownerUnits() {
        Booking__c booking = buildBooking('MAGAN SINGH');

        Test.startTest();
        AgreementOfSaleController controller = load(Page.BUILDER_SHARE_AGREEMENT_OF_SALE, booking);
        Test.stopTest();

        System.assertEquals(null, controller.ownerName);
        System.assertEquals('', controller.ownerDisplayName);
        System.assertEquals(0, controller.ownerUnits.size());
        System.assert(controller.isBuilderSharePage);
        System.assert(controller.getOwnerMismatchMessage().contains('Builder Share'));
        System.assert(controller.getOwnerMismatchMessage().contains('MAGAN SINGH'));
        System.assertEquals('MAGAN SINGH', controller.getUnitOwnerName());
    }

    @IsTest
    static void mismatchedLandownerIsReported() {
        Booking__c booking = buildBooking('MAGAN SINGH');

        Test.startTest();
        AgreementOfSaleController controller = load(Page.ARJUN_SINGH_AGREEMENT_OF_SALE, booking);
        Test.stopTest();

        System.assertEquals('ARJUN SINGH', controller.ownerName);
        System.assertEquals(0, controller.ownerUnits.size());
        System.assert(controller.getOwnerMismatchMessage().contains('MAGAN SINGH'));
        System.assert(controller.getOwnerMismatchMessage().contains('ARJUN SINGH'));
    }

    @IsTest
    static void legacyFieldSetAndBookingSecondApplicantFallback() {
        Project__c project = postSalesTestDataFactory.createProject('AOS Legacy');
        Plot__c unit = postSalesTestDataFactory.createUnit(project.Id);
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            // Required by the org's "Booking After Create Handler" flow (runs on
            // booking create): Quote__c as sourceRecordId + the booking-amount receipt.
            Quote__c = postSalesTestDataFactory.createQuote(project.Id).Id,
            Mode_Of_Payment__c = 'UPI',
            Booking_Amount__c = 100000,
            Status__c = 'New',
            First_Applicant_Name__c = 'Arun Sample',
            Salutation__c = 'Mr.',
            S_o_D_o_W_o__c = 'S/o',
            Son_Daughter_Wife_of__c = 'Sri. Kiran Sample',
            Date_of_Birth__c = Date.today().addYears(-45),
            Occupation__c = 'Private Employee',
            Permanent_Address__c = '12-34/5, Sample Nagar, Samplepet',
            Aadhaar__c = '777788889999',
            PAN_Number__c = 'KLMNO9012P',
            Email1__c = 'arun@example.com',
            Second_Applicant_Name__c = 'Second Person',
            salutation_Applicant2__c = 'Ms',
            Occupation1__c = 'Doctor',
            Aadhaar_Number1__c = '111122223333',
            Pan_Number_Applicant2__c = 'ABCDE1234F',
            Total_Flat_Cost__c = 12552000,
            Base_Price__c = 11552000,
            No_of_car_parking__c = 2
        );
        insert booking;

        Test.startTest();
        AgreementOfSaleController controller = load(Page.MAGHAN_SINGH_AGREEMENT_OF_SALE, booking);
        Test.stopTest();

        System.assertEquals(2, controller.applicants.size());
        System.assertEquals('SRI. ARUN SAMPLE', controller.applicants[0].getDisplayName());
        System.assert(controller.applicants[0].getLegalDetails().startsWith('S/O. SRI. KIRAN SAMPLE, aged about 45 years, Occupation: Private Employee, Resident of 12-34/5'),
            controller.applicants[0].getLegalDetails());
        System.assertEquals('KUM. SECOND PERSON', controller.applicants[1].getDisplayName());
        // second applicant with no address of their own inherits the primary address
        System.assert(controller.applicants[1].getLegalDetails().contains('Occupation: Doctor, Resident of 12-34/5'));
        System.assertEquals('arun@example.com', controller.getBuyerEmail());
        System.assertEquals('12-34/5, Sample Nagar, Samplepet', controller.getBuyerAddress());
        System.assertEquals('1,15,52,000', controller.getFormattedBasicPrice());
        System.assertEquals('10,00,000', controller.getFormattedAmenitiesAmount());
        System.assertEquals('Two', controller.getSelectedCarParkingDisplay());
        System.assertEquals(' and Two Car Parking Spaces', controller.getSelectedCarParkingClause());
        System.assertEquals('____________', controller.getLoanBankName());
        System.assertEquals(0, controller.receiptRows.size());
        System.assertEquals('', controller.getFormattedGstAmount());
        System.assertEquals('Rupees One Crore Twenty Five Lakh Fifty Two Thousand Only', controller.getAgreementAmountInWords());
    }

    @IsTest
    static void noBookingIdLeavesControllerEmpty() {
        Test.setCurrentPage(Page.SURESH_SINGH_AGREEMENT_OF_SALE);
        AgreementOfSaleController controller = new AgreementOfSaleController(
            new ApexPages.StandardController(new Booking__c())
        );
        System.assertEquals(null, controller.booking);
        System.assert(!controller.getHasApplicants());
        System.assert(!controller.getHasSelectedUnit());
        System.assertEquals('', controller.getSelectedTowerDisplay());
        System.assertEquals('', controller.getFormattedTotalFlatCost());
        System.assertEquals('', controller.getAgreementAmountInWords());
        System.assertEquals('None', controller.getSelectedCarParkingDisplay());
        System.assertEquals('Amenities including Infrastructure charges', controller.getAmenitiesDescription());
    }

    @IsTest
    static void drizzleBuilderAgreementBuildsPriceBreakUp() {
        Project__c project = postSalesTestDataFactory.createProject('Ananda The Drizzle');
        project.Corpus_Charge_Per_Sq_ft__c = 50;
        project.Maintenance_Per_sq_ft_per_month__c = 3.5;
        project.Maintenance_Month__c = 24;
        project.Document_Charges__c = 25000;
        update project;

        Plot__c unit = new Plot__c(
            Project__c = project.Id,
            Name = 'F-306',
            Unit_Type__c = 'Apartment',
            Status__c = 'Available',
            Floor__c = '3',
            BHK_Type__c = '2 BHK',
            Facing__c = 'East Facing',
            Saleable_Area_Sft__c = 1375,
            Carpet_Area__c = 824.02,
            Balcony_Area__c = 98.59,
            Other_Exclusive_Area__c = 35.48,
            Common_Area_Allotted_to_Association__c = 317.313,
            External_Wall_Area__c = 65.43,
            Internal_Wall_Area__c = 34.19,
            UDS__c = 32.6,
            North_By__c = 'Open to sky',
            East_By__c = 'Corridor'
        );
        insert unit;

        Quote__c quote = new Quote__c(
            Price_Per_Sq_Ft__c = 7850,
            Infrastructure_Charges__c = 625000,
            Amenities_Car_Parking__c = 250000,
            GST1__c = 5
        );
        insert quote;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Quote__c = quote.Id,
            Mode_Of_Payment__c = 'UPI',
            Booking_Amount__c = 100000,
            Status__c = 'New',
            First_Applicant_Name__c = 'Anil Demo Junior',
            salutation_Applicant1__c = 'Mr',
            Relation_Details_Applicant1__c = 'S/o',
            Son_Daughter_Wife_of__c = 'Suresh Demo Senior',
            Primary_Applicant_Age__c = 29,
            Occupation__c = 'Pvt. Employee',
            Permanent_Address__c = '1-2-3, Flat No: 101, Demo Residency, Demo Nagar, Hyderabad',
            Aadhaar_Number__c = '123412341234',
            PAN_Number1__c = 'pqrst3456u',
            Email__c = 'anil@example.com',
            Second_Applicant_Name__c = 'Suresh Demo Senior',
            salutation_Applicant2__c = 'Mr',
            Relation_Details_Applicant2__c = 'S/o',
            Son_Daughter_Wife_of1__c = 'Ramesh Demo Elder',
            Email2__c = 'suresh@example.com',
            Total_Flat_Cost__c = 11668750,
            Car_Parking_Selected__c = true,
            Loan_Bank_Name__c = 'BHFL'
        );
        insert booking;

        insert new Receipt__c(
            Booking__c = booking.Id,
            Receipt_Date__c = Date.newInstance(2026, 3, 14),
            Receipt_Type__c = 'Advance Payment',
            Cheque_Number__c = 'CHQ0003',
            Amount_received__c = 2452188,
            Approval_Status__c = 'Approved'
        );

        Test.startTest();
        AgreementOfSaleController controller = load(Page.SaleAgreementDrizzil, booking);
        Test.stopTest();

        System.assert(controller.isBuilderSharePage);
        System.assertEquals('', controller.getOwnerMismatchMessage());
        // unit not ticked "Mortgaged to HMDA": the sale agreement omits the mortgage clause
        System.assert(!controller.getIsMortgagedUnit());

        // allottees in THE DRIZZLE wording
        System.assertEquals(2, controller.applicants.size());
        AgreementOfSaleController.ApplicantEntry first = controller.applicants[0];
        System.assertEquals('MR. ANIL DEMO JUNIOR', first.getDrizzleName());
        System.assertEquals('MR. ANIL DEMO JUNIOR, S/o. MR. SURESH DEMO SENIOR,', first.getDrizzleNameLine());
        System.assertEquals('aged about 29 years, Occupation: Pvt. Employee; R/o: 1-2-3, Flat No: 101, Demo Residency, Demo Nagar, Hyderabad.',
            first.getDrizzleDetails());
        System.assertEquals('(AADHAR NO: 1234 1234 1234, PAN NO: PQRST3456U).', first.getDrizzleIds());
        System.assertEquals('MR. SURESH DEMO SENIOR, S/o. MR. RAMESH DEMO ELDER,', controller.applicants[1].getDrizzleNameLine());
        System.assertEquals('MR. ANIL DEMO JUNIOR & MR. SURESH DEMO SENIOR', controller.getDrizzleBuyerNames());
        System.assert(controller.getDrizzleBuyerAddress().startsWith('R/o: 1-2-3'));
        System.assertEquals('anil@example.com & suresh@example.com', controller.getDrizzleBuyerEmails());

        // flat schedule
        System.assertEquals('ANANDA THE DRIZZLE', controller.getDrizzleProjectName());
        System.assertEquals('F', controller.getDrizzleBlock());
        System.assertEquals('F-306', controller.getDrizzleFlatNo());
        System.assertEquals('THIRD', controller.getDrizzleFloor());
        System.assertEquals('2BHK', controller.getDrizzleFlatType());
        System.assertEquals('EAST', controller.getSelectedFacingUpper());
        System.assertEquals('1375', controller.getDrizzleFlatSize());
        System.assertEquals('824.02', controller.getDrizzleCarpetArea());
        System.assertEquals('98.59', controller.getDrizzleBalconyArea());
        System.assertEquals('35.48', controller.getDrizzleUtilityArea());
        System.assertEquals('317.313', controller.getDrizzleCommonArea());
        System.assertEquals('65.43', controller.getDrizzleExternalWall());
        System.assertEquals('34.19', controller.getDrizzleInternalWall());
        System.assertEquals('32.60', controller.getDrizzleUds());
        System.assertEquals('OPEN TO SKY', controller.getDrizzleBoundaryNorth());
        System.assertEquals('CORRIDOR', controller.getDrizzleBoundaryEast());
        System.assertEquals('', controller.getDrizzleBoundarySouth());
        System.assertEquals('', controller.getDrizzleBoundaryWest());

        // price table: basic + club house + parking, 5% GST
        System.assertEquals(3, controller.drizzlePriceLines.size());
        AgreementOfSaleController.ChargeLine basic = controller.drizzlePriceLines[0];
        System.assertEquals('Basic Price', basic.label);
        System.assertEquals('7850', basic.rateText);
        System.assertEquals('1,07,93,750', basic.getAmountDisplay());
        System.assertEquals('5,39,688', basic.getGstDisplay());
        System.assertEquals('1,13,33,438', basic.getTotalDisplay());
        System.assertEquals('6,25,000', controller.drizzlePriceLines[1].getAmountDisplay());
        System.assertEquals('6,56,250', controller.drizzlePriceLines[1].getTotalDisplay());
        System.assertEquals('Car Parking (1 No.)', controller.drizzlePriceLines[2].label);
        System.assertEquals('2,62,500', controller.drizzlePriceLines[2].getTotalDisplay());
        System.assertEquals('1,16,68,750', controller.drizzlePriceTotal.getAmountDisplay());
        System.assertEquals('5,83,438', controller.drizzlePriceTotal.getGstDisplay());
        System.assertEquals('1,22,52,188', controller.getDrizzleGrandTotalDisplay());
        System.assertEquals('Rupees One Crore Twenty Two Lakh Fifty Two Thousand One Hundred Eighty Eight Only',
            controller.getDrizzleGrandTotalInWords());

        // charges at registration / handover
        System.assertEquals('Rs. 50/- per SFT', controller.drizzleCorpusLine.rateText);
        System.assertEquals('68,750', controller.drizzleCorpusLine.getAmountDisplay());
        System.assertEquals('NA', controller.drizzleCorpusLine.getGstDisplay());
        System.assertEquals('0', controller.drizzleCorpusLine.getGstOrZeroDisplay());
        System.assertEquals('Rs. 3.50ps. per SFT per Month for 24 Months', controller.drizzleMaintenanceLine.rateText);
        System.assertEquals('1,15,500', controller.drizzleMaintenanceLine.getAmountDisplay());
        System.assertEquals('20,790', controller.drizzleMaintenanceLine.getGstDisplay());
        System.assertEquals('1,36,290', controller.drizzleMaintenanceLine.getTotalDisplay());
        System.assertEquals('29,500', controller.drizzleLegalLine.getTotalDisplay());
        System.assertEquals('2,09,250', controller.drizzleOtherTotal.getAmountDisplay());
        System.assertEquals('25,290', controller.drizzleOtherTotal.getGstDisplay());
        System.assertEquals('2,34,540', controller.drizzleOtherTotal.getTotalDisplay());
        System.assertEquals('50', controller.getDrizzleCorpusRate());
        System.assertEquals('Rupees Sixty Eight Thousand Seven Hundred Fifty Only', controller.getDrizzleCorpusInWords());
        System.assertEquals('Maintenance for 24 months @ Rs 3.5 /- per month per Sft', controller.getDrizzleMaintenanceScheduleLabel());
        System.assertEquals('Corpus Fund @ Rs. 50 /- per sft', controller.getDrizzleCorpusScheduleLabel());

        // receipts and balance (consideration including GST less receipts)
        System.assertEquals('24,52,188', controller.getFormattedTotalReceiptAmount());
        System.assertEquals('98,00,000', controller.getDrizzleBalanceDisplay());
        System.assertEquals('Rupees Ninety Eight Lakh Only', controller.getDrizzleBalanceInWords());
        System.assertEquals('BHFL', controller.getLoanBankName());
    }

    @IsTest
    static void drizzleMortgagePageFlagsLandownerUnitAndSurvivesMissingData() {
        Booking__c booking = buildBooking('MAGAN SINGH');

        Test.startTest();
        AgreementOfSaleController controller = load(Page.MortgageAgreementofSaleDrizzle, booking);
        Test.stopTest();

        System.assert(controller.isBuilderSharePage);
        System.assert(controller.getOwnerMismatchMessage().contains('MAGAN SINGH'));
        // the dedicated mortgage page always prints the clause
        System.assert(controller.getIsMortgagedUnit());
        // no project rates recorded: the registration / handover charges stay blank
        System.assertEquals('', controller.drizzleCorpusLine.getAmountDisplay());
        System.assertEquals('', controller.drizzleCorpusLine.getGstDisplay());
        System.assertEquals('', controller.drizzleOtherTotal.getAmountDisplay());
        System.assertEquals('', controller.getDrizzleCorpusRate());
        System.assertEquals('Corpus Fund', controller.getDrizzleCorpusScheduleLabel());
        // basic price falls out of the agreed cost; schedule names fall back correctly
        System.assertEquals('1,05,13,680', controller.drizzlePriceTotal.getAmountDisplay());
        System.assertEquals('Booking Amount', controller.paymentScheduleRows[0].getInstallmentName());
        System.assertEquals('SEVENTH', controller.getDrizzleFloor());
    }

    @IsTest
    static void saleAgreementPrintsMortgageClauseForMortgagedUnit() {
        Project__c project = postSalesTestDataFactory.createProject('Ananda The Drizzle');
        Plot__c unit = new Plot__c(
            Project__c = project.Id,
            Name = 'F-307',
            Unit_Type__c = 'Apartment',
            Status__c = 'Available',
            Mortgaged_to_HMDA__c = true
        );
        insert unit;
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            // Required by the org's "Booking After Create Handler" flow (runs on
            // booking create): Quote__c as sourceRecordId + the booking-amount receipt.
            Quote__c = postSalesTestDataFactory.createQuote(project.Id).Id,
            Mode_Of_Payment__c = 'UPI',
            Booking_Amount__c = 100000,
            Status__c = 'New',
            First_Applicant_Name__c = 'Anil Demo Junior',
            Total_Flat_Cost__c = 1000000
        );
        insert booking;

        Test.startTest();
        AgreementOfSaleController controller = load(Page.SaleAgreementDrizzil, booking);
        Test.stopTest();

        System.assert(controller.getIsMortgagedUnit());
    }

    // ------------------------------------------- ARJUN_SINGH_AGREEMENT_OF_SALE

    @IsTest
    static void arjunPageListsEveryCoApplicantOnceInDeedFormat() {
        Booking__c booking = buildBooking('ARJUN SINGH');
        insert new List<Co_Applicant__c>{
            new Co_Applicant__c(
                Booking__c = booking.Id,
                Salutation__c = 'Mr',
                Full_Name__c = 'Kiran Extra',
                S_o_D_o_W_o__c = 'S/o',
                W_o_S_o_C_o_c__c = 'Ravi Extra',
                Date_of_Birth__c = Date.today().addYears(-40),
                Occupation__c = 'Business',
                Permenent_Address__c = 'Plot 1, Hyderabad',
                Aadhar_Number__c = '123412341234',
                PAN_Number__c = 'ABCDE1234F'
            ),
            new Co_Applicant__c(
                Booking__c = booking.Id,
                First_Name__c = 'Latha',
                Last_Name__c = 'Rao'
            ),
            // same person as the Second Applicant: must not be printed twice
            new Co_Applicant__c(
                Booking__c = booking.Id,
                Full_Name__c = 'YARRA  THIREESHA'
            )
        };

        Test.startTest();
        AgreementOfSaleController controller = load(Page.ARJUN_SINGH_AGREEMENT_OF_SALE, booking);
        List<AgreementOfSaleController.ApplicantEntry> purchasers = controller.getAllApplicants();
        Test.stopTest();

        System.assertEquals(2, controller.applicants.size(), 'Shared applicant list is unchanged for the other pages');
        System.assertEquals(4, purchasers.size(), 'Applicant, Second Applicant and 2 new co-applicants');
        for (Integer i = 0; i < purchasers.size(); i++) {
            System.assertEquals(i + 1, purchasers[i].sequence, 'Numbered 1..N');
        }
        System.assertEquals(controller.applicants[1].getDisplayName(), purchasers[1].getDisplayName(), 'Second Applicant keeps its place');

        AgreementOfSaleController.ApplicantEntry kiran = purchasers[2];
        System.assertEquals('SRI. KIRAN EXTRA, S/O. SRI. RAVI EXTRA, ', kiran.getDeedNameLine());
        System.assertEquals('aged about 40 years, Occupation: Business, Resident of Plot 1, Hyderabad. ', kiran.getDeedDetails());
        System.assertEquals('(AADHAAR No. 123412341234 & PAN No. ABCDE1234F)', kiran.getDeedIds());

        AgreementOfSaleController.ApplicantEntry latha = purchasers[3];
        System.assertEquals('LATHA RAO, ', latha.getDeedNameLine(), 'First + Last name when Full Name is blank');
        System.assert(latha.getDeedDetails().startsWith('Resident of '), 'Falls back to the primary address');
        System.assertEquals('(AADHAAR No.  & PAN No. )', latha.getDeedIds(), 'Blank ids print empty');
        System.assert(controller.getAllApplicants() === purchasers, 'Built once and cached');

        List<String> names = new List<String>();
        for (AgreementOfSaleController.ApplicantEntry purchaser : purchasers) {
            names.add(purchaser.getDisplayName());
        }
        System.assertEquals(String.join(names, ' & '), controller.getAllBuyerNames(), 'Notice Attention lists every purchaser');
        System.assert(controller.getAllBuyerNames().contains('SRI. KIRAN EXTRA'), 'Co-applicant in the notice names');
        System.assert(!controller.buyerNames.contains('KIRAN EXTRA'), 'Shared buyerNames is unchanged for the other pages');
    }

    @IsTest
    static void arjunPageTowerComesFromTheUnitTowerLookup() {
        Booking__c booking = buildBooking('ARJUN SINGH');
        Schema.DescribeFieldResult towerField = Plot__c.Tower__c.getDescribe();
        Boolean towerIsBlockLookup = towerField.getType() == Schema.DisplayType.REFERENCE &&
            towerField.getReferenceTo().contains(Block__c.SObjectType);
        if (towerIsBlockLookup) {
            Block__c tower = new Block__c(Name = 'Tower 8', Project__c = booking.Project__c);
            insert tower;
            Plot__c unit = new Plot__c(Id = booking.Plot__c);
            unit.put('Tower__c', tower.Id);
            update unit;
        }

        Test.startTest();
        AgreementOfSaleController controller = load(Page.ARJUN_SINGH_AGREEMENT_OF_SALE, booking);
        String towerName = controller.getSelectedTowerName();
        Test.stopTest();

        if (towerIsBlockLookup) {
            System.assertEquals('Tower 8', towerName, 'Name of the unit Tower lookup record');
        } else {
            System.assertEquals(controller.getSelectedTowerDisplay(), towerName, 'Falls back to the existing tower');
        }
        System.assertEquals(towerName, controller.getSelectedTowerName(), 'Cached value');
    }

    @IsTest
    static void arjunPageGettersAreNullSafeWithoutBooking() {
        Test.setCurrentPage(Page.ARJUN_SINGH_AGREEMENT_OF_SALE);
        AgreementOfSaleController controller = new AgreementOfSaleController(
            new ApexPages.StandardController(new Booking__c())
        );

        System.assertEquals('', controller.getSelectedTowerName(), 'No unit, no tower');
        System.assert(controller.getAllApplicants().isEmpty(), 'No booking, no purchasers');
        System.assertEquals('', controller.getAllBuyerNames(), 'No booking, no notice names');
        System.assert(!controller.getHasFlatReceipts(), 'No booking, no receipts');
        System.assertEquals('0', controller.getFormattedFlatReceiptTotal(), 'Empty table totals zero');
        System.assertEquals('', controller.getFormattedTotalReceivedFlatAmount(), 'No booking, blank paid amount');
        System.assertEquals('', controller.getTotalReceivedFlatAmountInWords(), 'No booking, blank words');
        System.assertEquals('', controller.getFormattedBalanceFlatAmount(), 'No booking, blank balance');
        System.assertEquals('', controller.getBalanceFlatAmountInWords(), 'No booking, blank balance words');
        System.assertEquals(null, AgreementOfSaleController.queryTowerLookupName(null), 'Null unit id');
    }

    @IsTest
    static void arjunClause111UsesFlatAmountsAndSkipsGstAndAdditionalCharges() {
        Booking__c booking = buildBooking('ARJUN SINGH');
        insert new List<Receipt__c>{
            new Receipt__c(
                Booking__c = booking.Id,
                Receipt_Date__c = Date.newInstance(2025, 2, 1),
                Receipt_Type__c = 'GST Amount',
                Payment_Reference_Number__c = 'GST0001',
                Amount_received__c = 50000,
                Approval_Status__c = 'Approved'
            ),
            new Receipt__c(
                Booking__c = booking.Id,
                Receipt_Date__c = Date.newInstance(2025, 2, 2),
                Receipt_Type__c = 'Additional Charge',
                Payment_Reference_Number__c = 'ADD0001',
                Amount_received__c = 25000,
                Approval_Status__c = 'Approved'
            )
        };
        Booking__c saved = [
            SELECT Total_Received_Flat_Amount__c, Balance_Flat_Amount__c
            FROM Booking__c
            WHERE Id = :booking.Id
        ];

        Test.startTest();
        AgreementOfSaleController controller = load(Page.ARJUN_SINGH_AGREEMENT_OF_SALE, booking);
        Test.stopTest();

        Decimal expectedTotal = 0;
        for (AgreementOfSaleController.ReceiptRow row : controller.getFlatReceiptRows()) {
            System.assertNotEquals('GST Amount', row.getReceiptType(), 'GST Amount receipts are not listed');
            System.assertNotEquals('Additional Charge', row.getReceiptType(), 'Additional Charge receipts are not listed');
            expectedTotal += row.getAmount() == null ? 0 : row.getAmount();
        }
        System.assertEquals(controller.receiptRows.size() - 2, controller.getFlatReceiptRows().size(),
            'Only the GST Amount and Additional Charge rows are removed');
        System.assert(controller.getHasFlatReceipts(), 'Approved flat receipts are listed');
        System.assertEquals(2081709, expectedTotal, 'Approved Advance + Installment receipts');
        System.assertEquals('20,81,709', controller.getFormattedFlatReceiptTotal(), 'TOTAL AMOUNT = sum of the rows shown');

        System.assertEquals('21,56,709', controller.getFormattedTotalReceiptAmount(),
            'Existing total used by the other pages still includes GST / Additional Charge receipts');

        // Paid and balance amounts come straight from the new Booking fields.
        Decimal paid = saved.Total_Received_Flat_Amount__c;
        Decimal balance = saved.Balance_Flat_Amount__c;
        System.assertEquals(paid, controller.booking.Total_Received_Flat_Amount__c, 'Paid = Total_Received_Flat_Amount__c');
        System.assertEquals(balance, controller.booking.Balance_Flat_Amount__c, 'Balance = Balance_Flat_Amount__c');
        if (paid != null) {
            System.assert(String.isNotBlank(controller.getFormattedTotalReceivedFlatAmount()), 'Paid figure printed');
            System.assert(controller.getTotalReceivedFlatAmountInWords().startsWith('Rupees'), 'Paid amount in words');
        }
        if (balance != null) {
            System.assert(controller.getBalanceFlatAmountInWords().startsWith('Rupees'), 'Balance in words');
            System.assert(String.isNotBlank(controller.getFormattedBalanceFlatAmount()), 'Balance figure printed');
        }
    }
}
