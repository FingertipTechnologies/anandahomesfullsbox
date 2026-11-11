@isTest
private class CapriNocApprovedEmailInvocableTest {
    private static NOC__c makeApprovedNoc(String capriEmail) {
        Project__c project = new Project__c(
            Name = 'CAPRI Email Project',
            Project_Type__c = 'Apartment',
            Interest_Rate__c = 18
        );
        insert as system project;

        Plot__c plot = new Plot__c(
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked'
        );
        insert as system plot;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = plot.Id,
            Booking_Date__c = Date.today(),
            Status__c = 'Booked',
            Capri_Email__c = capriEmail
        );
        insert as system booking;

        NOC__c noc = new NOC__c(
            Booking__c = booking.Id,
            NOC_Type__c = 'Capri NOC',
            Approval_Status__c = 'Approved'
        );
        insert as system noc;
        return noc;
    }

    @isTest
    static void queuesEmailForApprovedNoc() {
        NOC__c noc = makeApprovedNoc('capri@example.com');
        CapriNocApprovedEmailInvocable.Request request =
            new CapriNocApprovedEmailInvocable.Request();
        request.nocId = noc.Id;

        Test.startTest();
        List<CapriNocApprovedEmailInvocable.Result> results =
            CapriNocApprovedEmailInvocable.sendApprovedNocEmails(
                new List<CapriNocApprovedEmailInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].queued);
        System.assertNotEquals(null, results[0].asyncJobId);
        AsyncApexJob job = [
            SELECT Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :results[0].asyncJobId
        ];
        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);
    }

    @isTest
    static void requiresCapriEmailOnBooking() {
        NOC__c noc = makeApprovedNoc(null);
        CapriNocApprovedEmailInvocable.Request request =
            new CapriNocApprovedEmailInvocable.Request();
        request.nocId = noc.Id;

        Boolean rejected = false;
        try {
            CapriNocApprovedEmailInvocable.sendApprovedNocEmails(
                new List<CapriNocApprovedEmailInvocable.Request>{ request }
            );
        } catch (AuraHandledException e) {
            rejected = true;
        }
        System.assertEquals(true, rejected, 'Missing recipient should be surfaced before enqueueing.');
    }

    @isTest
    static void rejectsRequestWithoutNocId() {
        CapriNocApprovedEmailInvocable.Request request =
            new CapriNocApprovedEmailInvocable.Request();
        Boolean rejected = false;
        try {
            CapriNocApprovedEmailInvocable.sendApprovedNocEmails(
                new List<CapriNocApprovedEmailInvocable.Request>{ request }
            );
        } catch (AuraHandledException e) {
            rejected = true;
        }
        System.assertEquals(true, rejected, 'A NOC Id is required.');
    }

    @isTest
    static void rejectsNonNocRecordId() {
        Account account = new Account(Name = 'Not a NOC');
        insert as system account;
        CapriNocApprovedEmailInvocable.Request request =
            new CapriNocApprovedEmailInvocable.Request();
        request.nocId = account.Id;

        Boolean rejected = false;
        try {
            CapriNocApprovedEmailInvocable.sendApprovedNocEmails(
                new List<CapriNocApprovedEmailInvocable.Request>{ request }
            );
        } catch (AuraHandledException e) {
            rejected = true;
        }
        System.assertEquals(true, rejected, 'Only NOC record IDs are accepted.');
    }

    /** A NOC on a unit that has two earlier cancellations and two swaps. */
    private static NOC__c makeNocWithHistory(Integer selections, String status) {
        Project__c project = new Project__c(
            Name = 'CAPRI History Project', Project_Type__c = 'Apartment', Interest_Rate__c = 18
        );
        insert as system project;
        Plot__c plot = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert as system plot;

        List<Booking__c> cancelled = new List<Booking__c>();
        List<Swap_History__c> swaps = new List<Swap_History__c>();
        for (Integer i = 0; i < 2; i++) {
            cancelled.add(new Booking__c(
                Project__c = project.Id, Plot__c = plot.Id, Status__c = 'Cancellation',
                Booking_Date__c = Date.today().addMonths(-6 - i),
                Cancellation_Date__c = Date.today().addMonths(-5 - i),
                Cancellation_Reason__c = 'Test reason ' + i, First_Applicant_Name__c = 'Cancelled Buyer ' + i
            ));
            swaps.add(new Swap_History__c(
                Old_Plot__c = plot.Id, Swap_Date__c = Date.today().addMonths(-3 - i), Swap_Reason__c = 'Test swap ' + i
            ));
        }
        insert as system cancelled;
        insert as system swaps;

        Booking__c booking = new Booking__c(
            Project__c = project.Id, Plot__c = plot.Id, Booking_Date__c = Date.today(),
            Status__c = 'Booked', Capri_Email__c = 'capri@example.com', First_Applicant_Name__c = 'Current Buyer'
        );
        insert as system booking;

        NOC__c noc = new NOC__c(Booking__c = booking.Id, NOC_Type__c = 'Capri NOC', Approval_Status__c = status);
        if (selections > 0) {
            List<Id> cancellationIds = new List<Id>();
            List<Id> swapIds = new List<Id>();
            for (Integer i = 0; i < selections; i++) {
                cancellationIds.add(cancelled[i].Id);
                swapIds.add(swaps[i].Id);
            }
            noc.Related_Cancellation_Booking__c = cancellationIds[0];
            noc.Related_Swap_History__c = swapIds[0];
            noc.Related_Cancellation_Booking_Ids__c = String.join(cancellationIds, ',');
            noc.Related_Swap_History_Ids__c = String.join(swapIds, ',');
        }
        insert as system noc;
        return [
            SELECT Id, Name, Approval_Status__c, Related_Cancellation_Booking__c, Related_Swap_History__c,
                   Related_Cancellation_Booking_Ids__c, Related_Swap_History_Ids__c, Booking__c,
                   Booking__r.Capri_Email__c, Booking__r.Unit_NumberFor__c, Booking__r.Project_Name__c
            FROM NOC__c WHERE Id = :noc.Id
            WITH SYSTEM_MODE
        ];
    }

    @isTest
    static void attachesOnlyCurrentNocWhenNothingSelected() {
        NOC__c noc = makeNocWithHistory(0, 'Approved');
        Test.startTest();
        List<Messaging.EmailFileAttachment> attachments = CapriNocApprovedEmailInvocable.buildAttachments(noc);
        Test.stopTest();
        System.assertEquals(1, attachments.size(), 'Only the current unit NOC is sent');
        System.assert(attachments[0].getFileName().startsWith('CAPRI_NOC_Loan'));
    }

    @isTest
    static void attachesOneLetterForASingleSelection() {
        NOC__c noc = makeNocWithHistory(1, 'Approved');
        Test.startTest();
        List<Messaging.EmailFileAttachment> attachments = CapriNocApprovedEmailInvocable.buildAttachments(noc);
        Test.stopTest();
        System.assertEquals(3, attachments.size(), 'Current NOC + one swap + one cancellation');
    }

    @isTest
    static void attachesOneLetterPerSelectionWhenMultiple() {
        NOC__c noc = makeNocWithHistory(2, 'Approved');
        Test.startTest();
        List<Messaging.EmailFileAttachment> attachments = CapriNocApprovedEmailInvocable.buildAttachments(noc);
        Test.stopTest();
        System.assertEquals(5, attachments.size(), 'Current NOC + two swaps + two cancellations');
        Set<String> names = new Set<String>();
        for (Messaging.EmailFileAttachment attachment : attachments) {
            names.add(attachment.getFileName());
        }
        System.assertEquals(5, names.size(), 'Every attachment has its own file name');
    }

    @isTest
    static void approvalAloneDoesNotSendTheMail() {
        NOC__c noc = makeNocWithHistory(2, 'Pending');
        Test.startTest();
        update as system new NOC__c(Id = noc.Id, Approval_Status__c = 'Approved');
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();
        System.assertEquals(0, queued, 'The Capri mail is sent only from the button');
    }

    @isTest
    static void previewListsEveryLetter() {
        NOC__c noc = makeNocWithHistory(2, 'Approved');
        CapriNocApprovedEmailInvocable.SendPreview preview = CapriNocApprovedEmailInvocable.getSendPreview(noc.Id);
        System.assertEquals(null, preview.blockedReason);
        System.assertEquals(5, preview.attachmentNames.size(), 'Loan NOC + 2 swap + 2 cancellation letters');
        System.assertNotEquals(null, preview.capriEmail);
    }

    @isTest
    static void sendButtonQueuesTheMailAndStampsSentDate() {
        NOC__c noc = makeNocWithHistory(0, 'Approved');
        Test.startTest();
        CapriNocApprovedEmailInvocable.sendNow(noc.Id);
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();
        System.assertEquals(1, queued, 'The button queues the Capri mail');
        System.assertNotEquals(null, [SELECT Sent_Date__c FROM NOC__c WHERE Id = :noc.Id WITH SYSTEM_MODE].Sent_Date__c);
    }

    @isTest
    static void sendButtonIsBlockedUntilApprovedAndEmailPresent() {
        NOC__c noc = makeNocWithHistory(0, 'Pending');
        System.assert(CapriNocApprovedEmailInvocable.getSendPreview(noc.Id).blockedReason.contains('approved'));
        try {
            CapriNocApprovedEmailInvocable.sendNow(noc.Id);
            System.assert(false, 'A pending NOC must not be mailed');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('approved'));
        }
        update as system new NOC__c(Id = noc.Id, Approval_Status__c = 'Approved');
        update as system new Booking__c(Id = noc.Booking__c, Capri_Email__c = null);
        System.assert(CapriNocApprovedEmailInvocable.getSendPreview(noc.Id).blockedReason.contains('Capri Email'));
    }
}