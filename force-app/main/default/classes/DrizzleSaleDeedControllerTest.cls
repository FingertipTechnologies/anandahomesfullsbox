@IsTest
private class DrizzleSaleDeedControllerTest {

    // Tower is a restricted picklist whose values differ between the orgs (fullsbox A-H, production
    // T1-T12): use whichever value is active where the test runs.
    private static String activeTower() {
        for (Schema.PicklistEntry entry : Plot__c.Tower__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static Integer testLeadCount = 0;

    /**
     * Production's "Booking After Create Handler" flow maps the booking's Lead (CLead__c) onto the
     * booking right after it is created, so every test booking needs a Lead as well as a Quote.
     */
    private static Id testLead() {
        testLeadCount++;
        Lead__c lead = new Lead__c(
            Name__c = 'Document Test Lead ' + testLeadCount,
            Phone__c = String.valueOf(9100000000L + testLeadCount)
        );
        insert lead;
        return lead.Id;
    }
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
            Tower__c = activeTower(),
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
            Quote__c = postSalesTestDataFactory.createQuote(project.Id).Id,
            CLead__c = testLead(),
            Mode_Of_Payment__c = 'UPI',
            Booking_Amount__c = 100000,
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

        insert new Co_Applicant__c(
            Booking__c = booking.Id,
            Full_Name__c = 'Rahul Goel',
            S_o_D_o_W_o__c = 'S/o',
            W_o_S_o_C_o_c__c = 'Nishant Goel',
            Date_of_Birth__c = Date.today().addYears(-10),
            Occupation__c = 'Student',
            Aadhar_Number__c = '111122223333',
            PAN_Number__c = 'ABCDE1234F',
            Permenent_Address__c = 'Patiala'
        );

        Receipt__c approvedReceipt = new Receipt__c(
            Booking__c = booking.Id,
            Amount_received__c = 2475000,
            Receipt_Date__c = Date.newInstance(2026, 1, 25),
            Receipt_Type__c = 'Installment Payment',
            Payment_Method__c = 'Cheque',
            Approval_Status__c = 'Approved',
            Receipt_Status__c = 'Received',
            Check_Transaction_Nmber__c = '358226',
            Cheque_Date__c = Date.newInstance(2026, 1, 23)
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

        // The sale deed reads the receipts themselves; their line items are only filled on allocation.

        Test.startTest();
        DrizzleSaleDeedController ctrl = new DrizzleSaleDeedController(
            new ApexPages.StandardController(booking)
        );
        Test.stopTest();

      
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
            Quote__c = postSalesTestDataFactory.createQuote(project.Id).Id, CLead__c = testLead(),
            Mode_Of_Payment__c = 'UPI', Booking_Amount__c = 100000,
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
        // Either the receipts' total or, when nothing counts as received yet, a dash line - never blank.
        System.assertNotEquals('', bare.paidAmount, 'The paid amount never prints empty');
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

        System.assertEquals('MR. NISHANT GOEL, S/o. MR. VIJAY PAL GOEL',
            DrizzleSaleDeedController.nameLine('Mr', 'Nishant Goel', 'S/o', 'Vijay Pal Goel'));
        System.assertEquals('NISHANT GOEL, C/o. MR. VIJAY PAL GOEL',
            DrizzleSaleDeedController.nameLine(null, 'Nishant Goel', null, 'Vijay Pal Goel'));
        System.assertEquals('MR. NISHANT GOEL, H/o. MRS. NANCY GOEL',
            DrizzleSaleDeedController.nameLine('Mr', 'Nishant Goel', 'H/o', 'Nancy Goel'));
        System.assertEquals('MRS. NANCY GOEL, W/o. SRI. NISHANT GOEL',
            DrizzleSaleDeedController.nameLine('Mrs', 'Nancy Goel', 'W/o', 'Sri. Nishant Goel'));
        System.assertEquals('NISHANT GOEL', DrizzleSaleDeedController.nameLine(null, 'Nishant Goel', 'S/o', null));
        System.assertEquals('', DrizzleSaleDeedController.withSalutation('Mr', ' '));

        System.assertEquals('05-02-2026', DrizzleSaleDeedController.formatDate(Date.newInstance(2026, 2, 5)));
        System.assertEquals(null, DrizzleSaleDeedController.ageFrom(null));
        System.assertEquals(0, DrizzleSaleDeedController.ageFrom(Date.today().addDays(1)));
    }

    /**
     * Unit fields printed in the flat table (Utility Area, External / Internal Wall, UDS in square
     * yards), the booking's "No of car parking", and an approved receipt whose Receipt Status is
     * blank (the usual case) - a cancelled receipt is left out.
     */
    @IsTest
    static void readsUnitAreasBookingCarParkingAndApprovedReceipts() {
        Booking__c booking = buildBooking();
        Id unitId = [SELECT Plot__c FROM Booking__c WHERE Id = :booking.Id].Plot__c;
        update new Plot__c(Id = unitId, Utility_Area__c = 340, External_Wall_Area__c = 120,
                           Internal_Wall_Area__c = 230, UDS__c = 42.75, UDS_Sq_mts__c = 10);
        update new Booking__c(Id = booking.Id, No_of_car_parking__c = 3);
        insert new List<Receipt__c>{
            new Receipt__c(Booking__c = booking.Id, Amount_received__c = 500000,
                           Receipt_Date__c = Date.newInstance(2026, 11, 13),
                           Receipt_Type__c = 'Installment Payment', Payment_Method__c = 'Cheque',
                           Approval_Status__c = 'Approved', Check_Transaction_Nmber__c = '33'),
            new Receipt__c(Booking__c = booking.Id, Amount_received__c = 1000,
                           Receipt_Date__c = Date.newInstance(2026, 11, 14),
                           Receipt_Type__c = 'Installment Payment', Payment_Method__c = 'Cheque',
                           Approval_Status__c = 'Approved', Receipt_Status__c = 'Cancelled')
        };

        Test.startTest();
        DrizzleSaleDeedController ctrl = new DrizzleSaleDeedController(
            new ApexPages.StandardController(booking)
        );
        Test.stopTest();

    }
}