@isTest
private class SwapQuoteServiceTest {

    private static Booking__c makeBookingWithSwapTarget() {
        Project__c project = new Project__c(Name = 'Swap Quote Project', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Block__c tower = new Block__c(Name = 'SQ-T1', Project__c = project.Id);
        insert tower;
        Plot__c oldUnit = new Plot__c(Project__c = project.Id, Status__c = 'Booked', Block1__c = tower.Id,
            Saleable_Area_Sft__c = 1000, Price_Per_Sq_Ft__c = 5000, GST1__c = 5);
        Plot__c newUnit = new Plot__c(Name = 'SQ-102', Project__c = project.Id, Status__c = 'Available', Block1__c = tower.Id,
            Saleable_Area_Sft__c = 1200, Price_Per_Sq_Ft__c = 6000, GST1__c = 5, Amenities_Car_Parking__c = 200000,
            Infrastructure_Charges__c = 100000, Floor_Rise__c = 50);
        insert new List<Plot__c>{ oldUnit, newUnit };
        insert new List<Master_Payment_Schedule__c>{
            new Master_Payment_Schedule__c(Name = 'On Booking', Project__c = project.Id, Tower__c = tower.Id,
                Payment_Percent__c = 20, Percentage__c = 20, Sequence__c = 1, S_No__c = 1, Status__c = 'Pending', Is_Active__c = true),
            new Master_Payment_Schedule__c(Name = 'On Possession', Project__c = project.Id, Tower__c = tower.Id,
                Payment_Percent__c = 80, Percentage__c = 80, Sequence__c = 2, S_No__c = 2, Status__c = 'Pending', Is_Active__c = true)
        };
        Booking__c booking = new Booking__c(Project__c = project.Id, Plot__c = oldUnit.Id, Booking_Date__c = Date.today(),
            Status__c = 'Booked', Total_Flat_Cost__c = 5000000, GST_Amount__c = 250000,
            Swap_To_Plot__c = newUnit.Id, Swap_Extra_Covered_Parking_Charges__c = 150000);
        insert booking;
        return booking;
    }

    @isTest
    static void buildsTheQuoteLikeTheCreateQuoteScreen() {
        Booking__c booking = makeBookingWithSwapTarget();
        Test.startTest();
        Id quoteId = SwapQuoteService.createForSwapRequest(booking.Id);
        Test.stopTest();

        Quote__c q = [SELECT Id, Unit__c, Project1__c, Payment_Type__c, Saleable_Area_Sft__c, Price_Per_Sq_Ft__c,
                             Amenities_Car_Parking__c, Infrastructure_Charges__c, Floor_Rise__c,
                             Extra_Covered_Car_Parking_Charges__c, Apply_Discount__c, Quote_Date__c, Total__c,
                             Swap_For_Booking__c, Quote_status__c
                      FROM Quote__c WHERE Id = :quoteId];
        System.assertEquals('Approved', q.Quote_status__c, 'Swap quote is approved outright; the swap request carries the approval');
        System.assertEquals(booking.Swap_To_Plot__c, q.Unit__c, 'Quote is for the Swap To Unit');
        System.assertEquals('Standard', q.Payment_Type__c);
        System.assertEquals(1200, q.Saleable_Area_Sft__c);
        System.assertEquals(6000, q.Price_Per_Sq_Ft__c);
        System.assertEquals(200000, q.Amenities_Car_Parking__c);
        System.assertEquals(150000, q.Extra_Covered_Car_Parking_Charges__c, 'Extra parking from the swap request');
        System.assertEquals(false, q.Apply_Discount__c, 'No discount on an automatic quote');
        System.assertEquals(Date.today(), q.Quote_Date__c);
        System.assertEquals(booking.Id, q.Swap_For_Booking__c, 'Quote points at the booking being swapped');

        List<Cost_Sheet_Line_Item__c> lines = [SELECT Payment_percent__c, Amount__c, S_No__c, status__c
                                               FROM Cost_Sheet_Line_Item__c WHERE Quote__c = :quoteId ORDER BY S_No__c];
        System.assertEquals(2, lines.size(), 'One cost sheet line per master schedule of the tower');
        System.assertEquals(20, lines[0].Payment_percent__c);
        System.assertEquals('Scheduled', lines[0].status__c);
        Decimal total = q.Total__c == null ? 0 : q.Total__c;
        System.assertEquals((total * 80 / 100).setScale(2), lines[1].Amount__c, 'Line amount is its share of the quote total');
        System.assertEquals('Blocked', [SELECT Status__c FROM Plot__c WHERE Id = :booking.Swap_To_Plot__c].Status__c,
            'The quote blocks the unit, as a manual cost sheet does');
    }

    @isTest
    static void resubmittingReusesTheOpenQuote() {
        Booking__c booking = makeBookingWithSwapTarget();
        Id first = SwapQuoteService.createForSwapRequest(booking.Id);
        Test.startTest();
        Id second = SwapQuoteService.createForSwapRequest(booking.Id);
        Test.stopTest();
        System.assertEquals(first, second, 'Same open quote for the same unit');
        System.assertEquals(1, [SELECT COUNT() FROM Quote__c WHERE Unit__c = :booking.Swap_To_Plot__c]);
    }

    @isTest
    static void rejectedSwapRequestRejectsTheQuoteAndFreesTheUnit() {
        Booking__c booking = makeBookingWithSwapTarget();
        Id quoteId = SwapQuoteService.createForSwapRequest(booking.Id);
        Test.startTest();
        update new Booking__c(Id = booking.Id, Swapping_Approval_Before_Agreement__c = 'Rejected');
        Test.stopTest();
        System.assertEquals('Rejected', [SELECT Quote_status__c FROM Quote__c WHERE Id = :quoteId].Quote_status__c);
        System.assertEquals('Available', [SELECT Status__c FROM Plot__c WHERE Id = :booking.Swap_To_Plot__c].Status__c);
    }

    @isTest
    static void swapRequestWithoutUnitIsRefused() {
        Booking__c booking = makeBookingWithSwapTarget();
        update new Booking__c(Id = booking.Id, Swap_To_Plot__c = null);
        try {
            SwapQuoteService.createForSwapRequest(booking.Id);
            System.assert(false, 'Must fail without a Swap To Unit');
        } catch (SwapQuoteService.SwapQuoteException e) {
            System.assert(e.getMessage().contains('Swap To Unit'));
        }
    }

    @isTest
    static void swappedBookingIsLinkedToTheSwapQuote() {
        Booking__c booking = makeBookingWithSwapTarget();
        Id quoteId = SwapQuoteService.createForSwapRequest(booking.Id);

        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = booking.Id;
        req.newUnitId = booking.Swap_To_Plot__c;
        req.newBookingStatus = 'Booked';
        Test.startTest();
        List<BookingSwapHandler.SwapResult> results = BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        Test.stopTest();

        System.assert(results[0].success, results[0].message);
        Booking__c created = [SELECT Quote__c FROM Booking__c WHERE Id = :results[0].newBookingId];
        System.assertEquals(quoteId, created.Quote__c, 'New booking carries the swap quote');
        System.assertNotEquals('Rejected', [SELECT Quote_status__c FROM Quote__c WHERE Id = :quoteId].Quote_status__c,
            'The quote stays as it is, like a quote a booking was created from manually');
    }
}
