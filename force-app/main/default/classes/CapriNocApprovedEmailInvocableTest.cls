@isTest
private class CapriNocApprovedEmailInvocableTest {
    private static NOC__c makeApprovedNoc(String capriEmail) {
        Project__c project = new Project__c(
            Name = 'CAPRI Email Project',
            Project_Type__c = 'Apartment',
            Interest_Rate__c = 18
        );
        insert project;

        Plot__c plot = new Plot__c(
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked'
        );
        insert plot;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = plot.Id,
            Booking_Date__c = Date.today(),
            Status__c = 'Booked',
            Capri_Email__c = capriEmail
        );
        insert booking;

        NOC__c noc = new NOC__c(
            Booking__c = booking.Id,
            NOC_Type__c = 'Capri NOC',
            Approval_Status__c = 'Approved'
        );
        insert noc;
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
        insert account;
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
}