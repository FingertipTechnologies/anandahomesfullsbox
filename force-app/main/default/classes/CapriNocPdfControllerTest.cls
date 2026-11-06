@isTest
private class CapriNocPdfControllerTest {
    @isTest
    static void loadsNocBookingAndReceiptTotals() {
        Project__c project = new Project__c(
            Name = 'CAPRI Test Project',
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
            First_Applicant_Name__c = 'CAPRI Test Buyer',
            Total_Flat_Cost__c = 1200000
        );
        insert as system booking;

        NOC__c noc = new NOC__c(
            Booking__c = booking.Id,
            NOC_Type__c = 'Capri NOC'
        );
        insert as system noc;

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

    @isTest
    static void printsTheRequestedSwapAndCancellation() {
        Project__c project = new Project__c(
            Name = 'CAPRI Related Project', Project_Type__c = 'Apartment', Interest_Rate__c = 18
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
                Cancellation_Reason__c = 'Reason ' + i, First_Applicant_Name__c = 'Cancelled ' + i,
                Second_Applicant_Name__c = 'Partner ' + i
            ));
            swaps.add(new Swap_History__c(
                Old_Plot__c = plot.Id, Swap_Date__c = Date.today().addMonths(-3 - i), Swap_Reason__c = 'Swap ' + i
            ));
        }
        insert as system cancelled;
        insert as system swaps;

        Booking__c booking = new Booking__c(
            Project__c = project.Id, Plot__c = plot.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            First_Applicant_Name__c = 'Current Buyer', Total_Flat_Cost__c = 11173800
        );
        insert as system booking;

        NOC__c noc = new NOC__c(
            Booking__c = booking.Id, NOC_Type__c = 'Capri NOC',
            Related_Cancellation_Booking__c = cancelled[0].Id,
            Related_Swap_History__c = swaps[0].Id,
            Related_Cancellation_Booking_Ids__c = cancelled[0].Id + ',' + cancelled[1].Id,
            Related_Swap_History_Ids__c = swaps[0].Id + ',' + swaps[1].Id
        );
        insert as system noc;
        noc = [
            SELECT Id, Related_Cancellation_Booking__c, Related_Swap_History__c,
                   Related_Cancellation_Booking_Ids__c, Related_Swap_History_Ids__c
            FROM NOC__c WHERE Id = :noc.Id
            WITH SYSTEM_MODE
        ];

        System.assertEquals(2, CapriNocPdfController.selectedCancellationIds(noc).size());
        System.assertEquals(2, CapriNocPdfController.selectedSwapIds(noc).size());

        Test.startTest();
        // Without the parameter the first selection is printed.
        Test.setCurrentPage(Page.CAPRI_CANCELLATION_LETTER);
        CapriNocPdfController first = new CapriNocPdfController(new ApexPages.StandardController(noc));
        System.assertEquals(cancelled[0].Id, first.cancellationBooking.Id);
        System.assertEquals(swaps[0].Id, first.swapHistory.Id);
        System.assertEquals('Cancelled 0 & Partner 0', first.cancellationBuyerNames);
        System.assertEquals('Current Buyer', first.buyerNames);
        System.assertEquals('1,11,73,800', first.considerationText);
        System.assertEquals(true, first.hasCancellation);
        System.assertEquals(true, first.showSwapNote, 'The released flat is the unit of this NOC');

        // relatedId chooses the second cancellation ...
        PageReference cancellationPage = Page.CAPRI_CANCELLATION_LETTER;
        cancellationPage.getParameters().put(CapriNocPdfController.RELATED_ID_PARAM, cancelled[1].Id);
        Test.setCurrentPage(cancellationPage);
        CapriNocPdfController second = new CapriNocPdfController(new ApexPages.StandardController(noc));
        System.assertEquals(cancelled[1].Id, second.cancellationBooking.Id);
        System.assertEquals(false, second.hasRefunds);

        // ... or the second swap.
        PageReference swapPage = Page.CAPRI_NOC_FORMAT_SWAP;
        swapPage.getParameters().put(CapriNocPdfController.RELATED_ID_PARAM, swaps[1].Id);
        Test.setCurrentPage(swapPage);
        CapriNocPdfController swapController = new CapriNocPdfController(new ApexPages.StandardController(noc));
        System.assertEquals(swaps[1].Id, swapController.swapHistory.Id);
        System.assertEquals(true, swapController.hasSwap);
        System.assertEquals(false, swapController.swapReceipts.hasReceipts);
        Test.stopTest();
    }

    @isTest
    static void formatsAmountsInIndianGrouping() {
        System.assertEquals('', CapriNocPdfController.formatIndian(null));
        System.assertEquals('100', CapriNocPdfController.formatIndian(100));
        System.assertEquals('5,915', CapriNocPdfController.formatIndian(5915));
        System.assertEquals('5,00,100', CapriNocPdfController.formatIndian(500100));
        System.assertEquals('1,06,73,700', CapriNocPdfController.formatIndian(10673700));
    }

    @isTest
    static void createNocKeepsEverySelection() {
        Project__c project = new Project__c(Name = 'CAPRI Create Project', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert as system project;
        Plot__c plot = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert as system plot;
        List<Booking__c> cancelled = new List<Booking__c>();
        List<Swap_History__c> swaps = new List<Swap_History__c>();
        for (Integer i = 0; i < 2; i++) {
            cancelled.add(new Booking__c(
                Project__c = project.Id, Plot__c = plot.Id, Status__c = 'Cancellation',
                Booking_Date__c = Date.today().addMonths(-6 - i), Cancellation_Date__c = Date.today().addMonths(-5 - i)
            ));
            swaps.add(new Swap_History__c(Old_Plot__c = plot.Id, Swap_Date__c = Date.today().addMonths(-3 - i)));
        }
        insert as system cancelled;
        insert as system swaps;
        Booking__c booking = new Booking__c(
            Project__c = project.Id, Plot__c = plot.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            CRM_Manager__c = UserInfo.getUserId()
        );
        insert as system booking;
        // Booking automation can clear the CRM Manager on insert; set it again so the NOC can be raised.
        update as system new Booking__c(Id = booking.Id, CRM_Manager__c = UserInfo.getUserId());

        Test.startTest();
        Id nocId = NOCController.createNOC(
            booking.Id, 'Capri NOC', 'Body',
            new List<Id>{ cancelled[0].Id, cancelled[1].Id },
            new List<Id>{ swaps[0].Id, swaps[1].Id }
        );
        Test.stopTest();

        NOC__c saved = [
            SELECT Related_Cancellation_Booking__c, Related_Swap_History__c,
                   Related_Cancellation_Booking_Ids__c, Related_Swap_History_Ids__c
            FROM NOC__c WHERE Id = :nocId
            WITH SYSTEM_MODE
        ];
        System.assertEquals(cancelled[0].Id, saved.Related_Cancellation_Booking__c);
        System.assertEquals(2, CapriNocPdfController.selectedCancellationIds(saved).size());
        System.assertEquals(2, CapriNocPdfController.selectedSwapIds(saved).size());
    }
}
