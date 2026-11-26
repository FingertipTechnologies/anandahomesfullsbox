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

        insert as system new Co_Applicant__c(Booking__c = booking.Id, Full_Name__c = 'CAPRI Co Buyer');

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

        System.assertEquals('CAPRI Test Buyer & CAPRI Co Buyer', controller.buyerNames);
        System.assertEquals(noc.Id, controller.noc.Id);
        System.assertEquals(booking.Id, controller.booking.Id);
        System.assertEquals(0, controller.totalReceived);
        System.assertEquals(1200000, controller.balanceReceivable);
        System.assertEquals(0, controller.receiptLineItems.size());
        System.assertEquals(null, controller.errorMessage);
    }

    /** The amenities charges come from the cost sheet when there is one, blank otherwise. */
    @isTest
    static void readsAmenitiesFromTheCostSheet() {
        Project__c project = new Project__c(Name = 'CAPRI Cost Sheet Project', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert as system project;
        Plot__c plot = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert as system plot;
        Booking__c booking = new Booking__c(Project__c = project.Id, Plot__c = plot.Id,
            Booking_Date__c = Date.today(), Status__c = 'Booked', First_Applicant_Name__c = 'CAPRI Cost Sheet Buyer');
        insert as system booking;

        Test.startTest();
        Decimal withoutSheet = CapriNocPdfController.amenitiesCharges(booking.Id);
        Decimal noBooking = CapriNocPdfController.amenitiesCharges(null);
        Cost_Sheet__c sheet = new Cost_Sheet__c(Project__c = project.Id, Amenities_Charges__c = 250000);
        insert as system sheet;
        update as system new Booking__c(Id = booking.Id, Cost_Sheet__c = sheet.Id);
        Decimal withSheet = CapriNocPdfController.amenitiesCharges(booking.Id);
        Test.stopTest();

     
    }

    @isTest
    static void listsApprovedReceiptsWithBlankStatus() {
        Project__c project = new Project__c(Name = 'CAPRI Receipt Project', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert as system project;
        Plot__c plot = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert as system plot;
        Booking__c booking = new Booking__c(
            Project__c = project.Id, Plot__c = plot.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            First_Applicant_Name__c = 'Receipt Buyer', Total_Flat_Cost__c = 2000000
        );
        insert as system booking;
        insert as system new List<Receipt__c>{
            // Entered in Salesforce: approved, Receipt Status left blank -> must be listed.
            new Receipt__c(Booking__c = booking.Id, Amount_received__c = 500000,
                Receipt_Date__c = Date.newInstance(2026, 11, 17), Receipt_Type__c = 'Installment Payment',
                Payment_Method__c = 'Cheque', Check_Transaction_Nmber__c = '45678678',
                Cheque_Date__c = Date.newInstance(2026, 11, 16), Approval_Status__c = 'Approved'),
            // Migrated: approved and Received -> listed; no method, so who paid is shown.
            new Receipt__c(Booking__c = booking.Id, Amount_received__c = 100000,
                Receipt_Date__c = Date.newInstance(2026, 11, 18), Receipt_Type__c = 'Installment Payment',
                Payment_From__c = 'Customer', Payment_Reference_Number__c = 'UTR1',
                Approval_Status__c = 'Approved', Receipt_Status__c = 'Received'),
            // Not counted: cancelled, and not yet approved.
            new Receipt__c(Booking__c = booking.Id, Amount_received__c = 7000,
                Receipt_Date__c = Date.newInstance(2026, 11, 18), Receipt_Type__c = 'Installment Payment',
                Approval_Status__c = 'Approved', Receipt_Status__c = 'Cancelled'),
            new Receipt__c(Booking__c = booking.Id, Amount_received__c = 9000,
                Receipt_Date__c = Date.newInstance(2026, 11, 18), Receipt_Type__c = 'Installment Payment',
                Approval_Status__c = 'Pending')
        };
        NOC__c noc = new NOC__c(Booking__c = booking.Id, NOC_Type__c = 'Capri NOC');
        insert as system noc;

        Test.startTest();
        CapriNocPdfController controller = new CapriNocPdfController(new ApexPages.StandardController(noc));
        Test.stopTest();

        System.assertEquals(2, controller.receiptLineItems.size(), 'Approved receipts, blank or Received status');
        System.assertEquals(600000, controller.totalReceived);
        System.assertEquals(1400000, controller.balanceReceivable);
        CapriNocPdfController.ReceiptRow first = controller.receiptLineItems[0];
        System.assertEquals(500000, first.amount);
        System.assertEquals('Cheque', first.mode);
        System.assertEquals('45678678', first.reference);
        System.assertEquals(Date.newInstance(2026, 11, 16), first.chequeDate);
        System.assertEquals(Date.newInstance(2026, 11, 17), first.depositedDate);
        System.assertEquals('Customer', controller.receiptLineItems[1].mode);
        System.assertEquals('UTR1', controller.receiptLineItems[1].reference);
    }

    @isTest
    static void swapAndCancellationLettersCountEachPaymentOnce() {
        Project__c project = new Project__c(Name = 'CAPRI Swap Receipts', Project_Type__c = 'Apartment', Interest_Rate__c = 18);
        insert as system project;
        List<Plot__c> plots = new List<Plot__c>{
            new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked'),
            new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked'),
            new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked')
        };
        insert as system plots;
        Booking__c oldBooking = new Booking__c(Project__c = project.Id, Plot__c = plots[0].Id, Status__c = 'Swapping',
            Booking_Date__c = Date.today().addMonths(-4), First_Applicant_Name__c = 'Swap Customer');
        Booking__c cancelled = new Booking__c(Project__c = project.Id, Plot__c = plots[2].Id, Status__c = 'Cancellation',
            Booking_Date__c = Date.today().addMonths(-6), Cancellation_Date__c = Date.today().addMonths(-1),
            First_Applicant_Name__c = 'Cancelled Customer');
        insert as system new List<Booking__c>{ oldBooking, cancelled };
        Booking__c newBooking = new Booking__c(Project__c = project.Id, Plot__c = plots[1].Id, Status__c = 'Booked',
            Booking_Date__c = Date.today(), First_Applicant_Name__c = 'Swap Customer', Total_Flat_Cost__c = 3000000);
        insert as system newBooking;

        List<Receipt__c> receipts = new List<Receipt__c>();
        for (Booking__c b : new List<Booking__c>{ oldBooking, newBooking }) {
            // The swap copies the old booking's two receipts onto the new booking.
            receipts.add(new Receipt__c(Booking__c = b.Id, Amount_received__c = 500000, Receipt_Date__c = Date.newInstance(2026, 8, 1),
                Receipt_Type__c = 'Installment Payment', Payment_Method__c = 'NEFT', Check_Transaction_Nmber__c = 'UTR-A',
                Approval_Status__c = 'Approved'));
            receipts.add(new Receipt__c(Booking__c = b.Id, Amount_received__c = 250000, Receipt_Date__c = Date.newInstance(2026, 9, 1),
                Receipt_Type__c = 'Installment Payment', Payment_Method__c = 'Cheque', Check_Transaction_Nmber__c = '111222',
                Approval_Status__c = 'Approved', Receipt_Status__c = 'Received'));
        }
        // Paid on the new booking after the swap.
        receipts.add(new Receipt__c(Booking__c = newBooking.Id, Amount_received__c = 100000, Receipt_Date__c = Date.newInstance(2026, 11, 1),
            Receipt_Type__c = 'Installment Payment', Payment_Method__c = 'IMPS', Check_Transaction_Nmber__c = 'UTR-B',
            Approval_Status__c = 'Approved'));
        // Cancelled booking: approved receipt entered in Salesforce (blank Receipt Status).
        receipts.add(new Receipt__c(Booking__c = cancelled.Id, Amount_received__c = 300000, Receipt_Date__c = Date.newInstance(2026, 5, 5),
            Receipt_Type__c = 'Installment Payment', Payment_Method__c = 'RTGS', Check_Transaction_Nmber__c = 'UTR-C',
            Approval_Status__c = 'Approved'));
        insert as system receipts;

        Swap_History__c swap = new Swap_History__c(Old_Plot__c = plots[0].Id, New_Plot__c = plots[1].Id,
            Old_Booking__c = oldBooking.Id, New_Booking__c = newBooking.Id, Swap_Date__c = Date.today().addMonths(-1));
        insert as system swap;
        NOC__c noc = new NOC__c(Booking__c = newBooking.Id, NOC_Type__c = 'Capri NOC',
            Related_Swap_History__c = swap.Id, Related_Cancellation_Booking__c = cancelled.Id);
        insert as system noc;

        Test.startTest();
        CapriNocPdfController controller = new CapriNocPdfController(new ApexPages.StandardController(noc));
        Test.stopTest();

        System.assertEquals(true, controller.swapReceipts.hasReceipts);
        System.assertEquals('8,50,000', controller.swapReceipts.totalText,
            '5,00,000 + 2,50,000 counted once (not again from the copies) + 1,00,000 paid after the swap');
        System.assertEquals('NEFT / Cheque / IMPS', controller.swapReceipts.modes);
        System.assertEquals('UTR-A, 111222, UTR-B', controller.swapReceipts.references);

        System.assertEquals(true, controller.cancellationReceipts.hasReceipts, 'Blank-status receipts count');
        System.assertEquals('3,00,000', controller.cancellationReceipts.totalText);
        System.assertEquals('RTGS', controller.cancellationReceipts.modes);
        System.assertEquals('UTR-C', controller.cancellationReceipts.references);

        // The loan letter of the new booking lists its own receipts (copies included) - 3 rows.
        System.assertEquals(3, controller.receiptLineItems.size());
        System.assertEquals(850000, controller.totalReceived);
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
      
    }
}