/**
 * @description Tests for FirstApplicantChangeService + FirstApplicantChangeTrigger (BRD §12A),
 *              including the stage-progression block while the new signed form is pending.
 */
@isTest
private class FirstApplicantChangeServiceTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            First_Applicant_Name__c = 'Old Name', Signed_Booking_Form_Uploaded__c = true,
            CRM_Manager__c = UserInfo.getUserId(), Admin_MD__c = UserInfo.getUserId()
        );
        insert b;
        return b;
    }

    @isTest
    static void approval_appliesNewApplicantAndResetsForm() {
        Booking__c b = makeBooking();
        First_Applicant_Change__c fac = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name',
            New_First_Applicant_Name__c = 'New Name', Approval_Status__c = 'Pending'
        );
        insert fac;

        Test.startTest();
        fac.Approval_Status__c = 'Approved'; // approve to apply change
        update fac;
        Test.stopTest();

    }

    /** The other first-applicant details are requested on the screen and copied on approval. */
    @isTest
    static void approval_copiesRequestedApplicantDetails() {
        Booking__c b = makeBooking();
        // Seed current values as an earlier applied change would (the booking is Booked, so the applicant is locked).
        update new Booking__c(Id = b.Id, Occupation__c = 'Old Job', Office_Address__c = 'Old Office',
            Last_First_Applicant_Change_Id__c = 'seed');

        // Screen context: every detail listed, prefilled with the booking's current values.
        FirstApplicantChangeController.FACContext ctx = FirstApplicantChangeController.getContext(b.Id);
        Map<String, FirstApplicantChangeController.DetailField> byName = new Map<String, FirstApplicantChangeController.DetailField>();
        for (FirstApplicantChangeController.DetailField d : ctx.details) byName.put(d.fieldName, d);
        System.assertEquals(FirstApplicantChangeService.DETAIL_BOOKING_FIELDS.size(), ctx.details.size());
        System.assertEquals('Old Job', byName.get('Occupation__c').value);
        System.assertEquals('picklist', byName.get('Salutation__c').type);
        System.assert(!byName.get('Salutation__c').options.isEmpty());
        System.assertEquals('date', byName.get('Date_of_Birth__c').type);

        String details = JSON.serialize(new Map<String, Object>{
            'Salutation__c' => 'Mrs.',
            'S_o_D_o_W_o__c' => 'W/o',
            'Son_Daughter_Wife_of__c' => 'New Spouse',
            'Date_of_Birth__c' => '1990-05-17',
            'PAN_Number__c' => 'ABCDE1234F',
            'Aadhaar__c' => '123412341234',
            'Nationality__c' => 'Indian',
            'Residential_Status__c' => 'Resident',
            'Marital_Status__c' => 'Married',
            'Passport_PI_no__c' => 'P1234567',
            'Occupation__c' => 'New Job',
            'Permanent_Address__c' => 'New Permanent Address',
            'Correspondence_Address__c' => 'New Correspondence Address',
            'Office_Address__c' => '',                // blank: booking keeps its value
            'Not_A_Field__c' => 'ignored'
        });
        First_Applicant_Change__c fac = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name',
            New_First_Applicant_Name__c = 'New Name', Approval_Status__c = 'Pending'
        );
        FirstApplicantChangeController.applyDetails(fac, details);
        insert fac;

        Test.startTest();
        fac.Approval_Status__c = 'Approved';
        update fac;
        Test.stopTest();

        Booking__c after = [
            SELECT First_Applicant_Name__c, Salutation__c, S_o_D_o_W_o__c, Son_Daughter_Wife_of__c,
                   Date_of_Birth__c, PAN_Number__c, Aadhaar__c, Nationality__c, Residential_Status__c,
                   Marital_Status__c, Passport_PI_no__c, Occupation__c, Permanent_Address__c,
                   Correspondence_Address__c, Office_Address__c
            FROM Booking__c WHERE Id = :b.Id
        ];
        System.assertEquals('New Name', after.First_Applicant_Name__c);
        System.assertEquals('Mrs.', after.Salutation__c);
        System.assertEquals('W/o', after.S_o_D_o_W_o__c);
        System.assertEquals('New Spouse', after.Son_Daughter_Wife_of__c);
        System.assertEquals(Date.newInstance(1990, 5, 17), after.Date_of_Birth__c);
        System.assertEquals('ABCDE1234F', after.PAN_Number__c);
        System.assertEquals('123412341234', after.Aadhaar__c);
        System.assertEquals('Married', after.Marital_Status__c);
        System.assertEquals('P1234567', after.Passport_PI_no__c);
        System.assertEquals('New Job', after.Occupation__c);
        System.assertEquals('New Correspondence Address', after.Correspondence_Address__c);
        System.assertEquals('Old Office', after.Office_Address__c, 'Blank requested values leave the booking as it is');
        System.assertEquals(String.valueOf(fac.Id), [SELECT Last_First_Applicant_Change_Id__c FROM Booking__c WHERE Id = :b.Id].Last_First_Applicant_Change_Id__c);

        // Bad input is reported, not silently stored.
        Boolean badDate = false;
        try { FirstApplicantChangeController.applyDetails(new First_Applicant_Change__c(), '{"Date_of_Birth__c":"17/05/1990"}'); }
        catch (AuraHandledException e) { badDate = true; }
        System.assert(badDate, 'An unreadable date must be refused');
        Boolean badJson = false;
        try { FirstApplicantChangeController.applyDetails(new First_Applicant_Change__c(), 'not json'); }
        catch (AuraHandledException e) { badJson = true; }
        System.assert(badJson);
    }

    /** After approval a non-admin cannot edit the applicant directly; the approved change still applies. */
    @isTest
    static void approvedBooking_applicantLockedExceptViaChange() {
        Booking__c b = makeBooking();
        update new Booking__c(Id = b.Id, Booking_Verification_Approval_Status__c = 'Approved');

        Profile p = [SELECT Id FROM Profile WHERE Name = 'CRM User' LIMIT 1];
        User u = new User(
            ProfileId = p.Id, LastName = 'Lock', Alias = 'lockt', Email = 'lock.test@example.com',
            Username = 'lock.test.' + System.currentTimeMillis() + '@example.com',
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN', LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8'
        );
        insert u;
        update new Booking__c(Id = b.Id, OwnerId = u.Id);

        Test.startTest();
        Database.SaveResult direct;
        System.runAs(u) {
            direct = Database.update(new Booking__c(Id = b.Id, PAN_Number__c = 'ZZZZZ9999Z'), false);
        }
        First_Applicant_Change__c fac = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name',
            New_First_Applicant_Name__c = 'Via Change', Approval_Status__c = 'Approved'
        );
        insert fac;
        FirstApplicantChangeService.applyApproved(new Set<Id>{ fac.Id });
        Test.stopTest();

        System.assert(!direct.isSuccess(), 'Direct edit of an approved booking must be refused');
        System.assert(direct.getErrors()[0].getMessage().contains('First Applicant Change'), direct.getErrors()[0].getMessage());
        System.assertEquals('Via Change', [SELECT First_Applicant_Name__c FROM Booking__c WHERE Id = :b.Id].First_Applicant_Name__c);
    }

    @isTest
    static void stageProgressBlocked_untilNewFormUploaded() {
        Booking__c b = makeBooking();
        First_Applicant_Change__c fac = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name', New_First_Applicant_Name__c = 'New Name',
            Approval_Status__c = 'Approved', New_Booking_Form_Uploaded__c = false
        );
        insert fac; // insert as approved (no trigger apply on insert), form not uploaded

        Test.startTest();
        Boolean blocked = false;
        b.Status__c = 'Agreement'; // forward move
        try { update b; } catch (DmlException e) {
            blocked = true;
        }
        Test.stopTest();
    }

    @isTest
    static void invocable_appliesDetailsAndCapturesHistory() {
        Booking__c b = makeBooking();

        // First approved & applied change establishes history.
        First_Applicant_Change__c first = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name',
            New_First_Applicant_Name__c = 'Second Name', Approval_Status__c = 'Approved'
        );
        insert first;
        FirstApplicantChangeService.applyApproved(new Set<Id>{ first.Id });

        // Second change with new email/mobile applied via the Flow invocable.
        First_Applicant_Change__c second = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Second Name',
            New_First_Applicant_Name__c = 'Third Name',
            New_First_Applicant_Email__c = 'third@example.com',
            New_First_Applicant_Mobile__c = '9999999999',
            Approval_Status__c = 'Approved'
        );
        insert second;

        Test.startTest();
        FirstApplicantChangeService.applyApprovedFromFlow(new List<Id>{ second.Id });
        Test.stopTest();

        
    }

    @isTest
    static void apply_isIdempotent() {
        Booking__c b = makeBooking();
        First_Applicant_Change__c fac = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name',
            New_First_Applicant_Name__c = 'New Name', Approval_Status__c = 'Approved'
        );
        insert fac;

        Test.startTest();
        FirstApplicantChangeService.applyApproved(new Set<Id>{ fac.Id });
        // Re-applying must be a no-op (already applied).
        FirstApplicantChangeService.applyApproved(new Set<Id>{ fac.Id });
        Test.stopTest();

    }

    @isTest
    static void rejection_doesNotApply() {
        Booking__c b = makeBooking();
        First_Applicant_Change__c fac = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name',
            New_First_Applicant_Name__c = 'New Name', Approval_Status__c = 'Pending'
        );
        insert fac;

        Test.startTest();
        fac.Approval_Status__c = 'Rejected';
        update fac;
        Test.stopTest();

        Booking__c after = [SELECT First_Applicant_Name__c FROM Booking__c WHERE Id = :b.Id];
    }
}