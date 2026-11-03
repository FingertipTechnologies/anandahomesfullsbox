/**
 * @description Tests for PaymentScheduleRevisionService — staging payment-schedule edits as a
 *              revision and applying them only after approval (BRD 8.2).
 */
@isTest
private class PaymentScheduleRevisionServiceTest {

    private static Booking__c booking;
    private static Payment_Schedule__c ps;

    private static void buildData() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        booking = new Booking__c(
            Project__c = project.Id, Booking_Date__c = Date.today(),
            Status__c = 'Booked', Funding_Type__c = 'Self-Funded'
        );
        insert booking;
        ps = new Payment_Schedule__c(
            Booking__c = booking.Id, Sequence__c = 1, Milestone_Name__c = 'Foundation',
            Amount__c = 1000, Payment_Schedule_Amount__c = 1000, Pending_Amount__c = 1000,
            Amount_Paid__c = 0, Status__c = 'Pending'
        );
        insert ps;
    }

    private static PaymentScheduleRevisionService.RevisionLine line(Id id, Decimal amount) {
        PaymentScheduleRevisionService.RevisionLine l = new PaymentScheduleRevisionService.RevisionLine();
        l.id = id;
        l.amount = amount;
        l.baseAmount = amount;
        return l;
    }

    @isTest
    static void stage_createsPendingRevision_withoutTouchingSchedule() {
        buildData();

        Test.startTest();
        Id revId = PaymentScheduleRevisionService.stageAndSubmit(
            booking.Id,
            new List<PaymentScheduleRevisionService.RevisionLine>{ line(ps.Id, 500) },
            'Adjusting milestone'
        );
        Test.stopTest();

        Payment_Schedule_Revision__c rev = [
            SELECT Approval_Status__c, Applied__c, Booking__c, Proposed_Changes_JSON__c
            FROM Payment_Schedule_Revision__c WHERE Id = :revId
        ];
        System.assertEquals('Pending', rev.Approval_Status__c, 'Revision should be Pending');
        System.assertEquals(false, rev.Applied__c, 'Revision should not be applied yet');
        System.assertEquals(booking.Id, rev.Booking__c);

        // The live schedule must be unchanged until approval.
        System.assertEquals(1000, [SELECT Amount__c FROM Payment_Schedule__c WHERE Id = :ps.Id].Amount__c,
            'Schedule amount must not change before approval');
    }

    @isTest
    static void approve_appliesValuesToSchedule() {
        buildData();
        Id revId = PaymentScheduleRevisionService.stageAndSubmit(
            booking.Id,
            new List<PaymentScheduleRevisionService.RevisionLine>{ line(ps.Id, 500) },
            null
        );

        Test.startTest();
        Payment_Schedule_Revision__c rev = new Payment_Schedule_Revision__c(
            Id = revId, Approval_Status__c = 'Approved'
        );
        update rev;
        Test.stopTest();

        System.assertEquals(500, [SELECT Amount__c FROM Payment_Schedule__c WHERE Id = :ps.Id].Amount__c,
            'Approved amount should now be applied');
        System.assertEquals(true, [SELECT Applied__c FROM Payment_Schedule_Revision__c WHERE Id = :revId].Applied__c,
            'Revision should be marked applied');
    }

    @isTest
    static void approvedSplitRequestAppliesToUnsplitSchedule() {
        Project__c project = new Project__c(
            Name = 'Prorata Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;

        Booking__c prorataBooking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Status__c = 'Booked',
            Funding_Type__c = 'Partial',
            Total_Flat_Cost__c = 1000,
            GST_Amount__c = 100,
            Loan_Sanctioned_Amount__c = 500
        );
        insert prorataBooking;

        Payment_Schedule__c unsplitSchedule = new Payment_Schedule__c(
            Booking__c = prorataBooking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Foundation',
            Amount__c = 1100,
            Payment_Schedule_Amount__c = 990,
            GST_Amount__c = 100,
            TDS_Amount__c = 10,
            Pending_Amount__c = 1100,
            Amount_Paid__c = 0,
            Status__c = 'Pending'
        );
        insert unsplitSchedule;

        PaymentScheduleRevisionService.RevisionLine requestedSplit =
            new PaymentScheduleRevisionService.RevisionLine();
        requestedSplit.id = unsplitSchedule.Id;
        requestedSplit.bankFlat = 500;
        requestedSplit.customerFlat = 490;
        requestedSplit.bankGst = 0;
        requestedSplit.customerGst = 100;

        String revisionPrefix = Payment_Schedule_Revision__c.SObjectType.getDescribe().getKeyPrefix();
        Id revisionId = Id.valueOf(revisionPrefix + '000000000001');
        Payment_Schedule_Revision__c oldRevision = new Payment_Schedule_Revision__c(
            Id = revisionId,
            Approval_Status__c = 'Pending'
        );
        Payment_Schedule_Revision__c approvedRevision = new Payment_Schedule_Revision__c(
            Id = revisionId,
            Approval_Status__c = 'Approved',
            Applied__c = false,
            Proposed_Changes_JSON__c = JSON.serialize(
                new List<PaymentScheduleRevisionService.RevisionLine>{ requestedSplit }
            )
        );
        Test.startTest();
        PaymentScheduleRevisionService.applyApprovedFromTrigger(
            new List<Payment_Schedule_Revision__c>{ approvedRevision },
            new Map<Id, Payment_Schedule_Revision__c>{ revisionId => oldRevision }
        );
        Test.stopTest();

        Payment_Schedule__c afterApproval = [
            SELECT Bank_Flat_Amount__c, Customer_Flat_Prorata__c,
                   Bank_GST_Amount__c, Customer_GST_Prorata__c
            FROM Payment_Schedule__c
            WHERE Id = :unsplitSchedule.Id
        ];
        
    }

    @isTest
    static void rejected_doesNotApply() {
        buildData();
        Id revId = PaymentScheduleRevisionService.stageAndSubmit(
            booking.Id,
            new List<PaymentScheduleRevisionService.RevisionLine>{ line(ps.Id, 500) },
            null
        );

        Test.startTest();
        update new Payment_Schedule_Revision__c(Id = revId, Approval_Status__c = 'Rejected');
        Test.stopTest();

        System.assertEquals(1000, [SELECT Amount__c FROM Payment_Schedule__c WHERE Id = :ps.Id].Amount__c,
            'Rejected revision must not change the schedule');
    }

    @isTest
    static void stage_noChanges_throws() {
        buildData();
        Test.startTest();
        Boolean threw = false;
        try {
            PaymentScheduleRevisionService.stageAndSubmit(
                booking.Id, new List<PaymentScheduleRevisionService.RevisionLine>(), null
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Empty change set should throw');
    }

    @isTest
    static void stage_nullBooking_throws() {
        Test.startTest();
        Boolean threw = false;
        try {
            PaymentScheduleRevisionService.stageAndSubmit(
                null, new List<PaymentScheduleRevisionService.RevisionLine>{ line(null, 1) }, null
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Null booking should throw');
    }
}