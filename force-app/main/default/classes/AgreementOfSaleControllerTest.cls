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
            Booking_Date__c = Date.today().addDays(-30),
            Agreement_Date__c = Date.newInstance(2026, 3, 15),
            Status__c = 'New',
            First_Applicant_Name__c = 'Pamulapati Mahesh',
            Second_Applicant_Name__c = 'Yarra Thireesha',
            salutation_Applicant1__c = 'Mr',
            Relation_Details_Applicant1__c = 'S/o',
            Son_Daughter_Wife_of1__c = 'Venkateswararao Pamulapati',
            Date_of_Birth1__c = Date.today().addYears(-30),
            Designation__c = 'Private Employee',
            Address__c = 'H.No-1-121, Perecherla, Guntur',
            Aadhaar_Number__c = '623678716036',
            PAN_Number1__c = 'CSGPP7659L',
            Email__c = 'mahesh@example.com',
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
            Full_Name__c = 'Yarra Thireesha',
            Salutation__c = 'Mrs',
            S_o_D_o_W_o__c = 'W/o',
            W_o_S_o_C_o_c__c = 'Pamulapati Mahesh',
            Date_of_Birth__c = Date.today().addYears(-28),
            Address__c = 'H.No-1-121, Perecherla, Guntur',
            Aadhar_Number__c = '230301486240',
            PAN_Number__c = 'AVJPY2857K',
            Email__c = 'thireesha@example.com'
        );

        insert new List<Receipt__c>{
            new Receipt__c(
                Booking__c = booking.Id,
                Receipt_Date__c = Date.newInstance(2024, 9, 24),
                Receipt_Type__c = 'Advance Payment',
                Cheque_Number__c = '000004',
                Amount_received__c = 500000,
                Approval_Status__c = 'Approved'
            ),
            new Receipt__c(
                Booking__c = booking.Id,
                Receipt_Date__c = Date.newInstance(2024, 11, 11),
                Receipt_Type__c = 'Installment Payment',
                Payment_Reference_Number__c = '301069395',
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
        System.assertEquals('SRI. PAMULAPATI MAHESH', controller.applicants[0].getDisplayName());
        System.assert(controller.applicants[0].getLegalDetails().startsWith('S/O. SRI. VENKATESWARARAO PAMULAPATI, aged about 30 years, Occupation: Private Employee, Resident of H.No-1-121'),
            controller.applicants[0].getLegalDetails());
        System.assert(controller.applicants[0].getLegalDetails().endsWith('(AADHAAR No. 623678716036 & PAN No. CSGPP7659L)'));
        System.assertEquals('SMT. YARRA THIREESHA', controller.applicants[1].getDisplayName());
        System.assert(controller.applicants[1].getLegalDetails().startsWith('W/O. SRI. PAMULAPATI MAHESH, aged about 28 years'));
        System.assertEquals('SRI. PAMULAPATI MAHESH & SMT. YARRA THIREESHA', controller.buyerNames);
        System.assertEquals('H.No-1-121, Perecherla, Guntur', controller.getBuyerAddress());
        System.assertEquals('mahesh@example.com', controller.getBuyerEmail());

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
        System.assertEquals('000004', controller.receiptRows[0].getReferenceId());
        System.assertEquals('301069395', controller.receiptRows[1].getReferenceId());
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
            Status__c = 'New',
            First_Applicant_Name__c = 'Nagender Bojjawar',
            Salutation__c = 'Mr.',
            S_o_D_o_W_o__c = 'S/o',
            Son_Daughter_Wife_of1__c = 'Sri. Vijayakumar Bojjawar',
            Date_of_Birth__c = Date.today().addYears(-45),
            Occupation__c = 'Private Employee',
            Permanent_Address__c = '14-176/2, Ganesh Nagar, Meerpet',
            Aadhaar__c = '402585380070',
            PAN_Number__c = 'AENPN6035P',
            Email1__c = 'naagender.b@example.com',
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
        System.assertEquals('SRI. NAGENDER BOJJAWAR', controller.applicants[0].getDisplayName());
        System.assert(controller.applicants[0].getLegalDetails().startsWith('S/O. SRI. VIJAYAKUMAR BOJJAWAR, aged about 45 years, Occupation: Private Employee, Resident of 14-176/2'),
            controller.applicants[0].getLegalDetails());
        System.assertEquals('KUM. SECOND PERSON', controller.applicants[1].getDisplayName());
        // second applicant with no address of their own inherits the primary address
        System.assert(controller.applicants[1].getLegalDetails().contains('Occupation: Doctor, Resident of 14-176/2'));
        System.assertEquals('naagender.b@example.com', controller.getBuyerEmail());
        System.assertEquals('14-176/2, Ganesh Nagar, Meerpet', controller.getBuyerAddress());
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
}