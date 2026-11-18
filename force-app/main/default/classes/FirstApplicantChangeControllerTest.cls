/**
 * @description Tests for FirstApplicantChangeController (BRD §12A).
 */
@isTest
private class FirstApplicantChangeControllerTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            First_Applicant_Name__c = 'Old Name', CRM_Manager__c = UserInfo.getUserId(),
            Admin_MD__c = UserInfo.getUserId()
        );
        insert b;
        // Booking automation can clear the CRM Manager on insert; set it again so the change can be raised.
        update new Booking__c(Id = b.Id, CRM_Manager__c = UserInfo.getUserId(), Admin_MD__c = UserInfo.getUserId());
        return b;
    }

    @isTest
    static void createChange_createsPending() {
        Booking__c b = makeBooking();
        Test.startTest();
        Id facId = FirstApplicantChangeController.createChange(b.Id, 'New Name', 'Marriage');
        Test.stopTest();

        First_Applicant_Change__c fac = [
            SELECT Old_First_Applicant__c, New_First_Applicant_Name__c, Reason__c,
                   Approval_Status__c, Approver_1__c, Approver_2__c
            FROM First_Applicant_Change__c WHERE Id = :facId
        ];
        System.assertEquals('Old Name', fac.Old_First_Applicant__c);
        System.assertEquals('New Name', fac.New_First_Applicant_Name__c);
        System.assertEquals('Pending', fac.Approval_Status__c);
        System.assertEquals(UserInfo.getUserId(), fac.Approver_1__c);
        System.assertEquals(UserInfo.getUserId(), fac.Approver_2__c);
    }

    @isTest
    static void getContext_returnsApplicantAndChanges() {
        Booking__c b = makeBooking();
        FirstApplicantChangeController.createChange(b.Id, 'New Name', 'Reason');

        Test.startTest();
        FirstApplicantChangeController.FACContext ctx = FirstApplicantChangeController.getContext(b.Id);
        Test.stopTest();

        System.assertEquals('Old Name', ctx.currentApplicant);
        System.assertEquals(1, ctx.changes.size());
        System.assertEquals('New Name', ctx.changes[0].newApplicant);
    }

    private static Map<String, Object> allDetails() {
        return new Map<String, Object>{
            'Salutation__c' => 'Mr.', 'S_o_D_o_W_o__c' => 'S/o', 'Son_Daughter_Wife_of__c' => 'Father',
            'Date_of_Birth__c' => '1985-01-02', 'PAN_Number__c' => 'ABCDE1234F', 'Aadhaar__c' => '123412341234',
            'Nationality__c' => 'Indian', 'Residential_Status__c' => 'Resident', 'Marital_Status__c' => 'Married',
            'Passport_PI_no__c' => 'P1234567', 'Occupation__c' => 'Engineer', 'Permanent_Address__c' => 'Addr 1',
            'Correspondence_Address__c' => 'Addr 2', 'Office_Address__c' => 'Addr 3'
        };
    }

    /** From the screen every field is required; a complete request is created, a partial one refused. */
    @isTest
    static void createChangeWithDetails_requiresEveryField() {
        Booking__c b = makeBooking();
        Test.startTest();
        Id facId = FirstApplicantChangeController.createChangeWithDetails(
            b.Id, 'New Name', 'new@example.com', '9876543210', 'Transfer', JSON.serialize(allDetails()));

        Map<String, Object> partial = allDetails();
        partial.remove('PAN_Number__c');
        String message;
        try {
            FirstApplicantChangeController.createChangeWithDetails(
                b.Id, 'Other', '', '9876543210', 'Transfer', JSON.serialize(partial));
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        System.assertNotEquals(null, facId);
        System.assertEquals('ABCDE1234F', [SELECT New_PAN_Number__c FROM First_Applicant_Change__c WHERE Id = :facId].New_PAN_Number__c);
        System.assertNotEquals(null, message, 'A partial request must be refused');
        System.assertEquals(1, [SELECT COUNT() FROM First_Applicant_Change__c WHERE Booking__c = :b.Id]);
    }

    /** The booking's Aadhaar / PAN / Mobile / Date of Birth checks also apply to the requested applicant. */
    @isTest
    static void createChangeWithDetails_appliesBookingFieldChecks() {
        Booking__c b = makeBooking();
        Map<String, Map<String, Object>> badDetails = new Map<String, Map<String, Object>>{
            'aadhaar' => new Map<String, Object>{ 'Aadhaar__c' => '12345' },
            'pan' => new Map<String, Object>{ 'PAN_Number__c' => '12345ABCDE' },
            'dob' => new Map<String, Object>{ 'Date_of_Birth__c' => String.valueOf(Date.today().addDays(1)) }
        };
        Integer refused = 0;
        Test.startTest();
        for (String key : badDetails.keySet()) {
            Map<String, Object> details = allDetails();
            details.putAll(badDetails.get(key));
            try {
                FirstApplicantChangeController.createChangeWithDetails(
                    b.Id, 'New Name', 'new@example.com', '9876543210', 'Transfer', JSON.serialize(details));
            } catch (AuraHandledException e) { refused++; }
        }
        try {
            FirstApplicantChangeController.createChangeWithDetails(
                b.Id, 'New Name', 'new@example.com', '98765-43210', 'Transfer', JSON.serialize(allDetails()));
        } catch (AuraHandledException e) { refused++; }
        Test.stopTest();

        System.assertEquals(4, refused, 'Bad Aadhaar, PAN, future DOB and non-numeric mobile must all be refused');
        System.assertEquals(0, [SELECT COUNT() FROM First_Applicant_Change__c WHERE Booking__c = :b.Id]);
    }

    @isTest
    static void validationErrors() {
        Booking__c b = makeBooking();
        Integer errors = 0;
        Test.startTest();
        try { FirstApplicantChangeController.createChange(null, 'X', 'r'); } catch (Exception e) { errors++; }
        try { FirstApplicantChangeController.createChange(b.Id, '', 'r'); } catch (Exception e) { errors++; }
        try { FirstApplicantChangeController.getContext(null); } catch (Exception e) { errors++; }
        Test.stopTest();
        System.assertEquals(3, errors);
    }
}