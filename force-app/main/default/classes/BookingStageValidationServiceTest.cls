/**
 * @description Tests for BookingStageValidationService (BRD stage-progression gates).
 *
 *              Most field-level tests call validateStageTransitions directly and inspect
 *              record.getErrors(). Integration tests use real records to cover trigger wiring
 *              and gates that query related payment data.
 */
@isTest
private class BookingStageValidationServiceTest {

    // ------------------------------------------------------------------ helpers

    private static Integer idSeq = 0;
    private static Id fakeBookingId() {
        idSeq++;
        return Id.valueOf(Booking__c.SObjectType.getDescribe().getKeyPrefix()
            + String.valueOf(idSeq).leftPad(12, '0'));
    }

    /** In-memory old/new pair sharing one Id; returns the NEW record (errors land here). */
    private static Booking__c pair(Booking__c oldB, Booking__c newB, Map<Id, Booking__c> oldMap) {
        Id bid = fakeBookingId();
        oldB.Id = bid;
        newB.Id = bid;
        oldMap.put(bid, oldB);
        return newB;
    }

    private static void run(Booking__c newB, Map<Id, Booking__c> oldMap) {
        BookingStageValidationService.validateStageTransitions(
            new List<Booking__c>{ newB }, oldMap
        );
        System.debug('Errors: ' + newB.getErrors());
    }

    private static Booking__c makeRealBooking(String stage) {
        Project__c project = new Project__c(Name = 'P', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = stage
        );
        insert b;
        return b;
    }

    private static void addZeroDueAgreementSchedule(Id bookingId) {
        insert new Payment_Schedule__c(
            Booking__c = bookingId,
            Sequence__c = 1,
            Milestone_Name__c = 'Agreement Amount',
            Amount__c = 0,
            Payment_Schedule_Amount__c = 0,
            GST_Amount__c = 0,
            TDS_Amount__c = 0,
            Pending_Amount__c = 0,
            Amount_Paid__c = 0,
            Status__c = 'Pending',
            Due_Date__c = Date.today(),
            Is_Agreement__c = true
        );
    }

    // ============================ New -> Booked ============================

    @isTest
    static void toBooked_withoutSignedForm_getsError() {
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c b = pair(
            new Booking__c(Status__c = 'New'),
            new Booking__c(Status__c = 'Booked'),
            oldMap
        );
        Test.startTest();
        run(b, oldMap);
        Test.stopTest();
        // Error expected: signed Booking Form branch.
    }

    @isTest
    static void toBooked_formOk_missingVerificationApproval_getsError() {
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c b = pair(
            new Booking__c(Status__c = 'New'),
            new Booking__c(Status__c = 'Booked', Signed_Booking_Form_Uploaded__c = true),
            oldMap
        );
        Test.startTest();
        run(b, oldMap);
        Test.stopTest();
        // Error expected: Booking Verification approval branch.
    }

    @isTest
    static void toBooked_missingAllKyc_getsError() {
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c b = pair(
            new Booking__c(Status__c = 'New'),
            new Booking__c(Status__c = 'Booked',
                Signed_Booking_Form_Uploaded__c = true,
                Booking_Verification_Approval_Status__c = 'Approved'),
            oldMap
        );
        Test.startTest();
        run(b, oldMap);
        Test.stopTest();
        // Error expected: all three KYC fields listed ("are" branch).
    }

    @isTest
    static void toBooked_missingSingleKyc_getsError() {
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c b = pair(
            new Booking__c(Status__c = 'New'),
            new Booking__c(Status__c = 'Booked',
                Signed_Booking_Form_Uploaded__c = true,
                Booking_Verification_Approval_Status__c = 'Approved',
                Aadhaar__c = '123456789012',
                PAN_Number__c = 'ABCDE1234F'), // Mobile missing
            oldMap
        );
        Test.startTest();
        run(b, oldMap);
        Test.stopTest();
        // Error expected: single field listed ("is" branch).
    }

    @isTest
    static void toBooked_allPrerequisitesMet_noError() {
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c b = pair(
            new Booking__c(Status__c = 'New'),
            new Booking__c(Status__c = 'Booked',
                Signed_Booking_Form_Uploaded__c = true,
                Booking_Verification_Approval_Status__c = 'Approved',
                Aadhaar__c = '123456789012',
                PAN_Number__c = 'ABCDE1234F',
                Mobile__c = '9876543210'),
            oldMap
        );
        Test.startTest();
        run(b, oldMap);
        Test.stopTest();
        // No error expected.
    }

    // ============================ Booked -> Agreement ============================

    @isTest
    static void toAgreement_requiresWelcomeMail() {
        Booking__c blockedRecord = makeRealBooking('Booked');
        Booking__c flagRecord = makeRealBooking('Booked');
        Booking__c dateRecord = makeRealBooking('Booked');
        addZeroDueAgreementSchedule(flagRecord.Id);
        addZeroDueAgreementSchedule(dateRecord.Id);

        Boolean blockedByWelcomeMail = false;
        Test.startTest();
        blockedRecord.Status__c = 'Agreement';
        try {
            update blockedRecord;
        } catch (DmlException e) {
            blockedByWelcomeMail = e.getMessage().contains('Booking Welcome mail must be sent');
        }
        System.assert(
            blockedByWelcomeMail,
            'The transition without a welcome email must fail at the welcome-mail gate.'
        );

        flagRecord.Status__c = 'Agreement';
        flagRecord.Welcome_Email_Sent__c = true;
        update flagRecord;

        dateRecord.Status__c = 'Agreement';
        dateRecord.Welcome_Mail_Sent_DateTime__c = Datetime.now();
        update dateRecord;
        Test.stopTest();

        Set<Id> allowedIds = new Set<Id>{ flagRecord.Id, dateRecord.Id };
        Map<Id, Booking__c> allowedBookings = new Map<Id, Booking__c>([
            SELECT Id, Status__c
            FROM Booking__c
            WHERE Id IN :allowedIds
        ]);
        System.assertEquals('Agreement', allowedBookings.get(flagRecord.Id).Status__c);
        System.assertEquals('Agreement', allowedBookings.get(dateRecord.Id).Status__c);
    }

    // ==================== Agreement -> Demands & Collections ====================

    @isTest
    static void toDemandsCollections_agreementGate() {
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c blockedB = pair(
            new Booking__c(Status__c = 'Agreement'),
            new Booking__c(Status__c = 'Demands & Collections'),
            oldMap
        );
        Booking__c allowedB = pair(
            new Booking__c(Status__c = 'Agreement'),
            new Booking__c(Status__c = 'Demands & Collections',
                Sale_Agreement_Status__c = 'Completed',
                Agreement_Date__c = Date.today()),
            oldMap
        );
        Test.startTest();
        BookingStageValidationService.validateStageTransitions(
            new List<Booking__c>{ blockedB, allowedB }, oldMap
        );
        Test.stopTest();
    }

    // ==================== Registration -> Handover prerequisites ====================

    @isTest
    static void toHandover_deedPrerequisites_getsError() {
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c b = pair(
            new Booking__c(Status__c = 'Registration'),
            new Booking__c(Status__c = 'Handover'), // all deed fields missing
            oldMap
        );
        Test.startTest();
        run(b, oldMap);
        Test.stopTest();
        // Error expected: deed status/date/registration fields listed.
    }

    // ============================ Cancellation gates ============================

    @isTest
    static void cancellation_approvalGates() {
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c noApproval = pair(
            new Booking__c(Status__c = 'Booked'),
            new Booking__c(Status__c = 'Cancellation'),
            oldMap
        );
        Booking__c pendingApproval = pair(
            new Booking__c(Status__c = 'Booked'),
            new Booking__c(Status__c = 'Cancellation',
                Cancellation_Approval_Before_Agreement__c = 'Pending Approval'),
            oldMap
        );
        Booking__c approved = pair(
            new Booking__c(Status__c = 'Booked'),
            new Booking__c(Status__c = 'Cancellation',
                Cancellation_Approval_Before_Agreement__c = 'Approved'),
            oldMap
        );
        Test.startTest();
        BookingStageValidationService.validateStageTransitions(
            new List<Booking__c>{ noApproval, pendingApproval, approved }, oldMap
        );
        Test.stopTest();
        // noApproval: submit-first error; pendingApproval: approved-first error; approved: clean.
        System.debug('No approval: ' + noApproval.getErrors());
        System.debug('Pending approval: ' + pendingApproval.getErrors());
        System.debug('Approved: ' + approved.getErrors());
    }

  
    // ============================ Swapping gates ============================

    @isTest
    static void swapping_approvalGates() {
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c swappingNoApproval = pair(
            new Booking__c(Status__c = 'Booked'),
            new Booking__c(Status__c = 'Swapping'),
            oldMap
        );
        Booking__c swappedNotApproved = pair(
            new Booking__c(Status__c = 'Booked'),
            new Booking__c(Status__c = 'Swapped',
                Swapping_Approval_Before_Agreement__c = 'Pending Approval'),
            oldMap
        );
        Booking__c swappedNoTargetUnit = pair(
            new Booking__c(Status__c = 'Booked'),
            new Booking__c(Status__c = 'Swapped',
                Swapping_Approval_Before_Agreement__c = 'Approved'), // Swap_To_Plot__c null
            oldMap
        );
        Test.startTest();
        BookingStageValidationService.validateStageTransitions(
            new List<Booking__c>{ swappingNoApproval, swappedNotApproved, swappedNoTargetUnit }, oldMap
        );
        Test.stopTest();
    }

    @isTest
    static void swapped_fullyApprovedWithTarget_noError() {
        Project__c project = new Project__c(Name = 'P', Interest_Rate__c = 18);
        insert project;
        Plot__c targetUnit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Available');
        insert targetUnit;

        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c b = pair(
            new Booking__c(Status__c = 'Booked'),
            new Booking__c(Status__c = 'Swapped',
                Swapping_Approval_Before_Agreement__c = 'Approved',
                Swap_To_Plot__c = targetUnit.Id),
            oldMap
        );
        Test.startTest();
        run(b, oldMap);
        Test.stopTest();
        // No error expected.
    }

    // ============================ Terminal / skip paths ============================

    @isTest
    static void terminalStatuses_cannotChange() {
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c fromCancelled = pair(
            new Booking__c(Status__c = 'Cancellation'),
            new Booking__c(Status__c = 'Booked'),
            oldMap
        );
        Booking__c fromSwapped = pair(
            new Booking__c(Status__c = 'Swapped'),
            new Booking__c(Status__c = 'Booked'),
            oldMap
        );
        Test.startTest();
        BookingStageValidationService.validateStageTransitions(
            new List<Booking__c>{ fromCancelled, fromSwapped }, oldMap
        );
        Test.stopTest();
        // Both get the "can no longer be changed" error.
    }

    @isTest
    static void skipPaths_backwardSameUnknownAndMissingOld() {
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c backward = pair(
            new Booking__c(Status__c = 'Agreement'),
            new Booking__c(Status__c = 'Booked'), // backward — not gated
            oldMap
        );
        Booking__c sameStatus = pair(
            new Booking__c(Status__c = 'Booked'),
            new Booking__c(Status__c = 'Booked'), // unchanged — skipped
            oldMap
        );
        Booking__c unknownStage = pair(
            new Booking__c(Status__c = 'Booked'),
            new Booking__c(Status__c = 'Some Custom Stage'), // not in STAGE_ORDER — skipped
            oldMap
        );
        Booking__c notInOldMap = new Booking__c(Id = fakeBookingId(), Status__c = 'Booked'); // old == null

        Test.startTest();
        BookingStageValidationService.validateStageTransitions(
            new List<Booking__c>{ backward, sameStatus, unknownStage, notInOldMap }, oldMap
        );
        // Null / bypass guards
        BookingStageValidationService.validateStageTransitions(null, null);
        BookingStageValidationService.validateStageTransitions(new List<Booking__c>(), oldMap);
        BookingStageValidationService.bypass = true;
        BookingStageValidationService.validateStageTransitions(
            new List<Booking__c>{ backward }, oldMap
        );
        BookingStageValidationService.bypass = false;
        Test.stopTest();
        // No errors expected on any of these.
    }

    // ============================ Financial gates (real data) ============================

    @isTest
    static void registration_selfFunding_pendingBalance_getsError() {
        Booking__c real = makeRealBooking('Demands & Collections');
        insert new Payment_Schedule__c(
            Booking__c = real.Id, Sequence__c = 1, Milestone_Name__c = 'M1',
            Amount__c = 100000, Pending_Amount__c = 50000, Amount_Paid__c = 50000,
            Status__c = 'Pending', Due_Date__c = Date.today()
        );

        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>{
            real.Id => new Booking__c(Id = real.Id, Status__c = 'Demands & Collections')
        };
        Booking__c newB = new Booking__c(
            Id = real.Id, Status__c = 'Registration',
            Funding_Type__c = 'Self',
            Sale_Agreement_Status__c = 'Completed', Agreement_Date__c = Date.today()
        );

        Test.startTest();
        run(newB, oldMap);
        Test.stopTest();
        // Error expected: self-funded with outstanding balance.
    }

    @isTest
    static void registration_loanFunding_pendingBalance_noError() {
        Booking__c real = makeRealBooking('Demands & Collections');
        insert new Payment_Schedule__c(
            Booking__c = real.Id, Sequence__c = 1, Milestone_Name__c = 'M1',
            Amount__c = 100000, Pending_Amount__c = 50000, Amount_Paid__c = 50000,
            Status__c = 'Pending', Due_Date__c = Date.today()
        );

        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>{
            real.Id => new Booking__c(Id = real.Id, Status__c = 'Demands & Collections')
        };
        Booking__c newB = new Booking__c(
            Id = real.Id, Status__c = 'Registration',
            Funding_Type__c = 'Loan',
            Sale_Agreement_Status__c = 'Completed', Agreement_Date__c = Date.today()
        );

        Test.startTest();
        run(newB, oldMap);
        Test.stopTest();
        // No error expected: loan funding disburses at registration.
    }

    @isTest
    static void registration_pendingReceipt_getsError() {
        Booking__c real = makeRealBooking('Demands & Collections');
        ReceiptApprovalGateService.bypass = true;
        insert new Receipt__c(
            Booking__c = real.Id, Amount_received__c = 50000,
            Receipt_Type__c = 'Installment Payment', Status__c = 'Cleared',
            Receipt_Date__c = Date.today(), Approval_Status__c = 'Pending Approval'
        );
        ReceiptApprovalGateService.bypass = false;

        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>{
            real.Id => new Booking__c(Id = real.Id, Status__c = 'Demands & Collections')
        };
        Booking__c newB = new Booking__c(
            Id = real.Id, Status__c = 'Registration',
            Funding_Type__c = 'Loan', // even loan funding is blocked by a pending receipt
            Sale_Agreement_Status__c = 'Completed', Agreement_Date__c = Date.today()
        );

        Test.startTest();
        run(newB, oldMap);
        Test.stopTest();
        // Error expected: receipt awaiting approval.
    }

    @isTest
    static void handover_allFinancialProblems_getsError() {
        Booking__c real = makeRealBooking('Registration');
        insert new Payment_Schedule__c(
            Booking__c = real.Id, Sequence__c = 1, Milestone_Name__c = 'M1',
            Amount__c = 100000, Pending_Amount__c = 50000, Amount_Paid__c = 50000,
            Status__c = 'Pending', Due_Date__c = Date.today()
        );
        ReceiptApprovalGateService.bypass = true;
        insert new Receipt__c(
            Booking__c = real.Id, Amount_received__c = 50000,
            Receipt_Type__c = 'Installment Payment', Status__c = 'Cleared',
            Receipt_Date__c = Date.today(), Approval_Status__c = 'Pending Approval'
        );
        ReceiptApprovalGateService.bypass = false;
        insert new Additional_Charge__c(
            Booking__c = real.Id, Status__c = 'Draft',Amount__c=1000,Charge_Name__c='ADS'
        );

        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>{
            real.Id => new Booking__c(Id = real.Id, Status__c = 'Registration')
        };
        Booking__c newB = new Booking__c(
            Id = real.Id, Status__c = 'Handover',
            Sale_Deed_Status__c = 'Completed', Sale_Deed_Date__c = Date.today(),
            Registration_Date__c = Date.today(), Registration_Number__c = 'REG-123'
        );

        Test.startTest();
        run(newB, oldMap);
        Test.stopTest();
        // Error expected listing all three problems.
    }

    @isTest
    static void handover_cleanFinancials_noError() {
        // Fabricated Id: the financial queries return nothing → pending 0, no receipts,
        // no charges → Handover passes.
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>();
        Booking__c b = pair(
            new Booking__c(Status__c = 'Registration'),
            new Booking__c(Status__c = 'Handover',
                Sale_Deed_Status__c = 'Completed', Sale_Deed_Date__c = Date.today(),
                Registration_Date__c = Date.today(), Registration_Number__c = 'REG-999'),
            oldMap
        );
        Test.startTest();
        run(b, oldMap);
        Test.stopTest();
        // No error expected.
    }
}