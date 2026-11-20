/**
 * @description Tests for SignedBookingFormGate: after an approved First Applicant Change the booking
 *              is on hold (no stage change, demand, receipt, NOC, FAC or approval) until a NEW
 *              signed Booking Form file is uploaded.
 */
@isTest
private class SignedBookingFormGateTest {

    @testSetup
    static void setup() {
        Project__c project = new Project__c(Name = 'Gate Project', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            First_Applicant_Name__c = 'Old Name', Signed_Booking_Form_Uploaded__c = true,
            CRM_Manager__c = UserInfo.getUserId(), Admin_MD__c = UserInfo.getUserId(),
            Email__c = 'gate.applicant@example.com'
        );
        insert b;
    }

    private static Booking__c booking() {
        return [SELECT Id, Project__c, Status__c, Signed_Booking_Form_Uploaded__c FROM Booking__c
                WHERE Email__c = 'gate.applicant@example.com' LIMIT 1];
    }

    /** Raises and approves a FAC: the booking goes on hold. */
    private static First_Applicant_Change__c approvedChange(Booking__c b) {
        First_Applicant_Change__c fac = new First_Applicant_Change__c(
            Booking__c = b.Id, Old_First_Applicant__c = 'Old Name',
            New_First_Applicant_Name__c = 'New Name', Approval_Status__c = 'Pending'
        );
        insert as system fac;
        fac.Approval_Status__c = 'Approved';
        update as system fac;
        return [SELECT Id, Name, Applied__c, Applied_Date__c, New_Booking_Form_Uploaded__c
                FROM First_Applicant_Change__c WHERE Id = :fac.Id WITH SYSTEM_MODE];
    }

    private static ContentVersion signedForm(Id bookingId, String title) {
        ContentVersion cv = new ContentVersion(
            Title = title, PathOnClient = title + '.pdf', VersionData = Blob.valueOf('signed'),
            FirstPublishLocationId = bookingId, Document_Type__c = SignedBookingFormGate.SIGNED_FORM_TYPE
        );
        insert as system cv;
        return cv;
    }

    /** True when saving the record was refused with the hold message. */
    private static Boolean refusedAsOnHold(SObject record) {
        Database.SaveResult r = Database.insert(record, false, AccessLevel.SYSTEM_MODE);
        if (r.isSuccess()) return false;
        for (Database.Error e : r.getErrors()) {
            if (e.getMessage().contains('on hold after First Applicant Change')) return true;
        }
        return false;
    }

    @isTest
    static void approvedChange_putsTheBookingOnHold() {
        Booking__c b = booking();
        First_Applicant_Change__c fac = approvedChange(b);
        System.assert(fac.Applied__c, 'Approval applies the change');
        System.assertEquals(false, booking().Signed_Booking_Form_Uploaded__c, 'Approval asks for a new signed form');

        Test.startTest();
        Boolean demandRefused = refusedAsOnHold(new Demands__c(
            Booking__c = b.Id, Project__c = b.Project__c, Demand_Component__c = 'Flat',
            Demand_Amount__c = 1000, Flat_Amount__c = 1000, Pending_Amount__c = 1000,
            Demand_Type__c = 'Individual Demand', Demand_Date__c = Date.today(), Status__c = 'Raised'));
        Boolean receiptRefused = refusedAsOnHold(new Receipt__c(Booking__c = b.Id));
        Boolean nocRefused = refusedAsOnHold(new NOC__c(Booking__c = b.Id, NOC_Type__c = 'Capri NOC'));
        Boolean facRefused = refusedAsOnHold(new First_Applicant_Change__c(
            Booking__c = b.Id, New_First_Applicant_Name__c = 'Third Name', Approval_Status__c = 'Pending'));
        Database.SaveResult stage = Database.update(new Booking__c(Id = b.Id, Status__c = 'Agreement'), false, AccessLevel.SYSTEM_MODE);
        String approvalError;
        try {
            SignedBookingFormGate.assertNotOnHold(b.Id, 'submitting it for approval');
        } catch (AuraHandledException e) {
            approvalError = e.getMessage();
        }
        Test.stopTest();

        System.assert(demandRefused, 'No demand while on hold');
        System.assert(receiptRefused, 'No receipt while on hold');
        System.assert(nocRefused, 'No NOC while on hold');
        System.assert(facRefused, 'No second First Applicant Change while on hold');
        System.assert(!stage.isSuccess(), 'No stage change while on hold');
        System.assert(stage.getErrors()[0].getMessage().contains(fac.Name), stage.getErrors()[0].getMessage());
        System.assert(approvalError != null && approvalError.contains('signed by New Name'), approvalError);
    }

    @isTest
    static void onlyANewSignedFormLiftsTheHold() {
        Booking__c b = booking();
        ContentVersion oldForm = signedForm(b.Id, 'Old signed form');
        Test.setCreatedDate(oldForm.Id, Datetime.now().addDays(-2));
        First_Applicant_Change__c fac = approvedChange(b);

        Test.startTest();
        // Ticking the box by hand, with only the earlier form on the booking, is refused.
        Database.SaveResult byHand = Database.update(
            new Booking__c(Id = b.Id, Signed_Booking_Form_Uploaded__c = true), false, AccessLevel.SYSTEM_MODE);
        // Upload the form signed by the new applicant, then tick it (what the Document Manager does).
        signedForm(b.Id, 'New signed form');
        update as system new Booking__c(Id = b.Id, Signed_Booking_Form_Uploaded__c = true);
        Test.stopTest();

        System.assert(!byHand.isSuccess(), 'The earlier form does not lift the hold');
        System.assert(byHand.getErrors()[0].getMessage().contains('earlier form does not count'),
            byHand.getErrors()[0].getMessage());
        System.assertEquals(true, [SELECT New_Booking_Form_Uploaded__c FROM First_Applicant_Change__c
            WHERE Id = :fac.Id WITH SYSTEM_MODE].New_Booking_Form_Uploaded__c, 'The change is marked done');
        System.assert(SignedBookingFormGate.holdingChanges(new Set<Id>{ b.Id }).isEmpty(), 'Hold lifted');
        // The stage may move again: any refusal now comes from the other stage rules, not the hold.
        Database.SaveResult stage = Database.update(new Booking__c(Id = b.Id, Status__c = 'Agreement'), false, AccessLevel.SYSTEM_MODE);
        for (Database.Error e : stage.getErrors()) {
            System.assert(!e.getMessage().contains('on hold'), e.getMessage());
        }
    }

    @isTest
    static void bookingsWithoutAChange_areNotHeld() {
        Booking__c b = booking();
        update as system new Booking__c(Id = b.Id, Signed_Booking_Form_Uploaded__c = false);
        Test.startTest();
        SignedBookingFormGate.assertNotOnHold(b.Id, 'anything');
        SignedBookingFormGate.assertNotOnHold(null, 'anything');
        Test.stopTest();
        System.assert(SignedBookingFormGate.holdingChanges(new Set<Id>{ b.Id }).isEmpty());
        System.assertEquals(null, SignedBookingFormGate.bookingOf(UserInfo.getUserId()), 'Objects without a booking are skipped');
        System.assertEquals(b.Id, SignedBookingFormGate.bookingOf(b.Id));
    }
}
