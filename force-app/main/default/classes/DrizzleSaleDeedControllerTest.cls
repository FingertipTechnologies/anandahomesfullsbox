@IsTest
private class DrizzleSaleDeedControllerTest {

    private static Booking__c buildBooking() {
        Project__c project = new Project__c(
            Name = 'The Drizzle',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;

        Plot__c unit = new Plot__c(
            Name = 'F-309',
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked',
            Tower__c = 'F',
            Floor__c = '3',
            BHK_Type__c = '3 BHK',
            Facing__c = 'West Facing',
            Saleable_Area_Sft__c = 1995,
            Carpet_Area__c = 1200,
            Balcony_Area__c = 158,
            Common_Area_Allotted_to_Association__c = 460,
            UDS__c = 47,
            North_By__c = 'Open to Sky',
            South_By__c = 'Open to Sky',
            East_By__c = 'Open to Sky',
            West_By__c = 'Corridor'
        );
        insert unit;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Booking_Date__c = Date.today(),
            Status__c = 'Booked',
            Total_Flat_Cost__c = 8977500,
            Car_Parking_Selected__c = true,
            Extra_covered_Parking_Slots__c = 1,
            First_Applicant_Name__c = 'Nishant Goel',
            Relation_Details_Applicant1__c = 'S/o',
            Son_Daughter_Wife_of__c = 'Vijay Pal Goel',
            Date_of_Birth1__c = Date.today().addYears(-34),
            Occupation__c = 'Govt. Employee',
            Permanent_Address__c = '266, PUDA Enclave 1, Patiala, Punjab-147001',
            Aadhaar_Number__c = '227955799895',
            PAN_Number1__c = 'awzpg8204d',
            Second_Applicant_Name__c = 'Nancy Goel',
            Relation_Details_Applicant2__c = 'W/o',
            Son_Daughter_Wife_of1__c = 'Nishant Goel',
            Date_of_birth_Applicant2__c = Date.today().addYears(-33).addDays(1),
            Occupation1__c = 'Self-Employed',
            Permanent_Address1__c = '266, PUDA Enclave 1, Patiala, Punjab-147001',
            Aadhaar_Number1__c = '800984806100',
            Pan_Number_Applicant2__c = 'BZLPM9156J'
        );
        insert booking;
        return booking;
    }

    @IsTest
    static void fillsScheduleVendeesConsiderationAndPayments() {
        Booking__c booking = buildBooking();

        Co_Applicant__c coApplicant = new Co_Applicant__c(
            Booking__c = booking.Id,
            Full_Name__c = 'Rahul Goel',
            S_o_D_o_W_o__c = 'S/o',
            W_o_S_o_C_o_c__c = 'Nishant Goel',
            Date_of_Birth__c = Date.today().addYears(-10),
            Aadhar_Number__c = '111122223333',
            PAN_Number__c = 'ABCDE1234F',
            Permenent_Address__c = 'Patiala'
        );
        // Occupation__c is set dynamically so the Co_Applicant__c field type can change.
        coApplicant.put('Occupation__c', 'Student');
        insert coApplicant;

        Receipt__c approvedReceipt = new Receipt__c(
            Booking__c = booking.Id,
            Amount_received__c = 2475000,
            Receipt_Date__c = Date.newInstance(2026, 1, 25),
            Receipt_Type__c = 'Installment Payment',
            Payment_Method__c = 'Cheque',
            Approval_Status__c = 'Approved',
            Receipt_Status__c = 'Received'
        );
        Receipt__c pendingReceipt = new Receipt__c(
            Booking__c = booking.Id,
            Amount_received__c = 20000,
            Receipt_Date__c = Date.newInstance(2026, 2, 1),
            Receipt_Type__c = 'Installment Payment',
            Payment_Method__c = 'Cheque',
            Approval_Status__c = 'Pending',
            Receipt_Status__c = 'Received'
        );
        insert new List<Receipt__c>{ approvedReceipt, pendingReceipt };

        insert new List<Receipt_Line_Item__c>{
            new Receipt_Line_Item__c(
                Receipt__c = approvedReceipt.Id,
                Booking__c = booking.Id,
                Received_Amount__c = 2475000,
                Mode_of_Payment__c = 'Cheque',
                Cheque_no_Transaction_Number__c = '358226',
                Cheque_Date__c = Date.newInstance(2026, 1, 23)
            ),
            new Receipt_Line_Item__c(
                Receipt__c = pendingReceipt.Id,
                Booking__c = booking.Id,
                Received_Amount__c = 20000
            )
        };

        Test.startTest();
        DrizzleSaleDeedController ctrl = new DrizzleSaleDeedController(
            new ApexPages.StandardController(booking)
        );
        Test.stopTest();

        // Flat schedule
        System.assertEquals('THE DRIZZLE', ctrl.projectName);
        System.assertEquals('F', ctrl.blockName);
        System.assertEquals('F-309', ctrl.flatNo);
        System.assertEquals('THIRD', ctrl.floorName);
        System.assertEquals('Third', ctrl.floorTitle);
        System.assertEquals('3 BHK', ctrl.flatType);
        System.assertEquals('3', ctrl.bhkNumber);
        System.assertEquals('WEST', ctrl.facingName);
        System.assertEquals('West', ctrl.facingTitle);
        System.assertEquals('1995 SFT', ctrl.flatSize);
        System.assertEquals('1995', ctrl.flatSizeNumber);
        System.assertEquals('1200 SFT', ctrl.carpetArea);
        System.assertEquals('158 SFT', ctrl.balconyArea);
        System.assertEquals('', ctrl.utilityArea, 'No utility area on the unit renders blank.');
        System.assertEquals('460 SFT', ctrl.commonArea);
        System.assertEquals('', ctrl.externalWall);
        System.assertEquals('TWO', ctrl.carParkingName);
        System.assertEquals('Two', ctrl.carParkingTitle);
        System.assertEquals('47', ctrl.udsNumber);
        System.assertEquals('47 Sq. Yds', ctrl.udsArea);
        System.assertEquals('OPEN TO SKY', ctrl.boundaryNorth);
        System.assertEquals('CORRIDOR', ctrl.boundaryWest);

        // Vendees: primary, second applicant, co-applicant
        System.assertEquals(3, ctrl.vendees.size());
        System.assertEquals('NISHANT GOEL, S/o. VIJAY PAL GOEL', ctrl.vendees[0].nameLine);
        System.assertEquals('aged about 34 years', ctrl.vendees[0].ageText);
        System.assertEquals('Govt. Employee', ctrl.vendees[0].occupation);
        System.assertEquals('2279 5579 9895', ctrl.vendees[0].aadhar);
        System.assertEquals('AWZPG8204D', ctrl.vendees[0].pan);
        System.assert(ctrl.vendees[0].isFirst && !ctrl.vendees[0].isLast);
        System.assertEquals('NANCY GOEL, W/o. NISHANT GOEL', ctrl.vendees[1].nameLine);
        System.assertEquals('aged about 32 years', ctrl.vendees[1].ageText, 'Birthday tomorrow: still 32.');
        System.assertEquals('8009 8480 6100', ctrl.vendees[1].aadhar);
        System.assertEquals('RAHUL GOEL, S/o. NISHANT GOEL', ctrl.vendees[2].nameLine);
        System.assertEquals('aged about 10 years', ctrl.vendees[2].ageText);
        System.assert(!ctrl.vendees[2].isFirst && ctrl.vendees[2].isLast);

        // Consideration
        System.assertEquals('89,77,500', ctrl.considerationAmount);
        System.assert(ctrl.considerationWords.startsWith('Rupees Eighty Nine Lakh'), ctrl.considerationWords);
        System.assert(ctrl.considerationWords.endsWith('Only'), ctrl.considerationWords);

        // Payments: only approved + received lines
        System.assert(ctrl.hasPaymentEntries);
        System.assertEquals(1, ctrl.paymentEntries.size());
        System.assertEquals('23-01-2026', ctrl.paymentEntries[0].dateText, 'Cheque date preferred.');
        System.assertEquals('CHEQUE', ctrl.paymentEntries[0].mode);
        System.assertEquals('358226', ctrl.paymentEntries[0].reference);
        System.assertEquals('24,75,000', ctrl.paymentEntries[0].amountText);
        System.assertEquals('24,75,000/-', ctrl.totalReceived);
    }

    @IsTest
    static void blankWhenNoBookingOrNoData() {
        DrizzleSaleDeedController empty = new DrizzleSaleDeedController(
            new ApexPages.StandardController(new Booking__c())
        );
        System.assertEquals(0, empty.vendees.size());
        System.assertEquals('', empty.flatNo);
        System.assertEquals('', empty.considerationWords);
        System.assertEquals(false, empty.hasPaymentEntries);

        Project__c project = new Project__c(Name = 'Bare', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Available');
        insert unit;
        Booking__c booking = new Booking__c(Project__c = project.Id, Plot__c = unit.Id,
            Booking_Date__c = Date.today(), Status__c = 'Booked');
        insert booking;

        DrizzleSaleDeedController bare = new DrizzleSaleDeedController(
            new ApexPages.StandardController(booking)
        );
        System.assertEquals(0, bare.vendees.size());
        System.assertEquals('', bare.floorName);
        System.assertEquals('NIL', bare.carParkingName);
        System.assertEquals('', bare.totalReceived);
        System.assertEquals('', bare.considerationAmount);
    }

    @IsTest
    static void formattingHelpers() {
        System.assertEquals('GROUND', DrizzleSaleDeedController.floorWord('G'));
        System.assertEquals('TWENTY-FIRST', DrizzleSaleDeedController.floorWord('21'));
        System.assertEquals('42ND', DrizzleSaleDeedController.floorWord('42'));
        System.assertEquals('111TH', DrizzleSaleDeedController.floorWord('111'));
        System.assertEquals('MEZZANINE', DrizzleSaleDeedController.floorWord('Mezzanine'));
        System.assertEquals('', DrizzleSaleDeedController.floorWord(null));

        System.assertEquals('WEST', DrizzleSaleDeedController.facingWord('West Facing'));
        System.assertEquals('NORTH-EAST', DrizzleSaleDeedController.facingWord('North-East Facing'));
        System.assertEquals('EAST', DrizzleSaleDeedController.facingWord('EAST'));

        System.assertEquals('NIL', DrizzleSaleDeedController.countWord(0));
        System.assertEquals('TWO', DrizzleSaleDeedController.countWord(2));
        System.assertEquals('12', DrizzleSaleDeedController.countWord(12));

        System.assertEquals('3', DrizzleSaleDeedController.firstNumberIn('3 BHK + 2T'));
        System.assertEquals('2.5', DrizzleSaleDeedController.firstNumberIn('2.5 BHK'));
        System.assertEquals('Penthouse', DrizzleSaleDeedController.firstNumberIn('Penthouse'));

        System.assertEquals('460.383', DrizzleSaleDeedController.formatArea(460.383));
        System.assertEquals('47.3', DrizzleSaleDeedController.formatArea(47.30));
        System.assertEquals('1995', DrizzleSaleDeedController.formatArea(1995.000));
        System.assertEquals('448.845', DrizzleSaleDeedController.formatArea(448.84499999999997));

        System.assertEquals('89,77,500', DrizzleSaleDeedController.formatIndianNumber(8977500));
        System.assertEquals('1,00,00,000', DrizzleSaleDeedController.formatIndianNumber(10000000));
        System.assertEquals('999', DrizzleSaleDeedController.formatIndianNumber(999));
        System.assertEquals('12,34,567.50', DrizzleSaleDeedController.formatIndianNumber(1234567.5));
        System.assertEquals('', DrizzleSaleDeedController.formatIndianNumber(null));

        System.assertEquals('2279 5579 9895', DrizzleSaleDeedController.formatAadhaar('2279-5579-9895'));
        System.assertEquals('12345', DrizzleSaleDeedController.formatAadhaar('12345'));

        System.assertEquals('MR. NISHANT GOEL, S/o. VIJAY PAL GOEL',
            DrizzleSaleDeedController.nameLine('Mr', 'Nishant Goel', 'S/o', 'Vijay Pal Goel'));
        System.assertEquals('NISHANT GOEL, VIJAY PAL GOEL',
            DrizzleSaleDeedController.nameLine(null, 'Nishant Goel', null, 'Vijay Pal Goel'));
        System.assertEquals('NISHANT GOEL', DrizzleSaleDeedController.nameLine(null, 'Nishant Goel', 'S/o', null));
        System.assertEquals('', DrizzleSaleDeedController.withSalutation('Mr', ' '));

        System.assertEquals('05-02-2026', DrizzleSaleDeedController.formatDate(Date.newInstance(2026, 2, 5)));
        System.assertEquals(null, DrizzleSaleDeedController.ageFrom(null));
        System.assertEquals(0, DrizzleSaleDeedController.ageFrom(Date.today().addDays(1)));
    }
}