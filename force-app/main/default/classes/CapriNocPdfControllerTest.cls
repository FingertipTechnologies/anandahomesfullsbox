@isTest
private class CapriNocPdfControllerTest {
    @isTest
    static void loadsNocBookingAndReceiptTotals() {
        Project__c project = new Project__c(
            Name = 'CAPRI Test Project',
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
            First_Applicant_Name__c = 'CAPRI Test Buyer',
            Total_Flat_Cost__c = 1200000
        );
        insert booking;

        NOC__c noc = new NOC__c(
            Booking__c = booking.Id,
            NOC_Type__c = 'Capri NOC'
        );
        insert noc;

        Test.startTest();
        CapriNocPdfController controller = new CapriNocPdfController(
            new ApexPages.StandardController(noc)
        );
        Test.stopTest();

        System.assertEquals(noc.Id, controller.noc.Id);
        System.assertEquals(booking.Id, controller.booking.Id);
        System.assertEquals(0, controller.totalReceived);
        System.assertEquals(1200000, controller.balanceReceivable);
        System.assertEquals(0, controller.receiptLineItems.size());
        System.assertEquals(null, controller.errorMessage);
    }

    @isTest
    static void reportsMissingNocId() {
        CapriNocPdfController controller = new CapriNocPdfController(
            new ApexPages.StandardController(new NOC__c())
        );
        System.assertEquals(
            'A NOC record ID is required to generate this document.',
            controller.errorMessage
        );
    }
}