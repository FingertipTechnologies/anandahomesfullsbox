@IsTest
public class BookingTriggerTest {

    private class UnexpectedSuccessfulDmlException extends Exception {}
    
    @TestSetup
    static void setup() {
        // Set up Projects
        Project__c pr = new Project__c(Name = 'Aarya', Project_Type__c = 'Residential');
        insert pr;
        
        Project__c pr1 = new Project__c(Name = 'Arto Helix', Project_Type__c = 'Residential');
        insert pr1;
        
        // Set up Blocks
        Block__c blk1 = new Block__c(Name = 'A', Project__c = pr.Id);
        insert blk1;
        
        // Set up Plots
        Plot__c pl = new Plot__c(Name = '101', Status__c = 'Available', Project__c = pr.Id, Block1__c = blk1.Id);
        insert pl;
        
        Plot__c pl2 = new Plot__c(Name = '202', Status__c = 'Available', Project__c = pr1.Id, Block1__c = blk1.Id);
        insert pl2;

        Plot__c pl3 = new Plot__c(Name = '303', Status__c = 'Available', Project__c = pr.Id, Block1__c = blk1.Id);
        insert pl3;
        
        // Set up Booking records
        Booking__c booking1 = new Booking__c(Followup_Date__c = system.today(), Project1__c = pr.Id, Plot__c = pl.Id, Stage__c = 'New Booking', Status__c = 'Booked');
        insert booking1;
        
        Booking__c booking2 = new Booking__c(Followup_Date__c = system.today(), Project1__c = pr1.Id, Plot__c = pl2.Id, Stage__c = 'New Booking', Is_Swap__c = false, Status__c = 'Booked');
        insert booking2;
    }
    
    @IsTest
    static void testBookingInsert() {
        Plot__c availablePlot = [SELECT Id, Project__c FROM Plot__c WHERE Name = '303' LIMIT 1];
        Booking__c newBooking = new Booking__c(
            Followup_Date__c = system.today(),
            Project1__c = availablePlot.Project__c,
            Plot__c = availablePlot.Id,
            Stage__c = 'New Booking',
            Status__c = 'Booked'
        );
        Test.startTest();
        insert newBooking;
        Test.stopTest();
    }
    
    @IsTest
    static void testBookingUpdate() {
        Booking__c booking = [SELECT Id, Stage__c, Plot__c FROM Booking__c LIMIT 1];
        Plot__c newPlot = [SELECT Id FROM Plot__c WHERE Name = '303' LIMIT 1];

        Test.startTest();
        booking.Plot__c = newPlot.Id;
        booking.Swap_Unit_Status__c = 'Approved';
        update booking;
        Test.stopTest();

        Booking__c after = [SELECT Plot__c, Swap_Unit_Status__c FROM Booking__c WHERE Id = :booking.Id];
    }

    @IsTest
    static void testDuplicateActiveBookingIsRejected() {
        Plot__c occupiedPlot = [SELECT Id, Project__c FROM Plot__c WHERE Name = '101' LIMIT 1];
        Booking__c duplicateBooking = new Booking__c(
            Followup_Date__c = Date.today(),
            Project1__c = occupiedPlot.Project__c,
            Plot__c = occupiedPlot.Id,
            Stage__c = 'New Booking',
            Status__c = 'Booked'
        );

        Test.startTest();
        expectDuplicateBookingError(duplicateBooking);
        Test.stopTest();
    }

    @IsTest
    static void testCancellationAndSwapRecordsDoNotBlockUnit() {
        Plot__c occupiedPlot = [SELECT Id, Project__c FROM Plot__c WHERE Name = '101' LIMIT 1];
        List<Booking__c> inactiveBookings = new List<Booking__c>{
            new Booking__c(
                Followup_Date__c = Date.today(),
                Project1__c = occupiedPlot.Project__c,
                Plot__c = occupiedPlot.Id,
                Stage__c = 'New Booking',
                Status__c = 'Cancellation'
            ),
            new Booking__c(
                Followup_Date__c = Date.today(),
                Project1__c = occupiedPlot.Project__c,
                Plot__c = occupiedPlot.Id,
                Stage__c = 'New Booking',
                Status__c = 'Swapping'
            ),
            new Booking__c(
                Followup_Date__c = Date.today(),
                Project1__c = occupiedPlot.Project__c,
                Plot__c = occupiedPlot.Id,
                Stage__c = 'New Booking',
                Status__c = 'Booked',
                Is_Swapped__c = true
            )
        };

        Test.startTest();
        insert inactiveBookings;
        Test.stopTest();
    }

    @IsTest
    static void testUpdatingUnitToOneWithActiveBookingIsRejected() {
        Booking__c booking = [SELECT Id, Project1__c, Plot__c FROM Booking__c WHERE Plot__r.Name = '101' LIMIT 1];
        Plot__c occupiedPlot = [SELECT Id FROM Plot__c WHERE Name = '202' LIMIT 1];
        booking.Plot__c = occupiedPlot.Id;

        Test.startTest();
        expectDuplicateBookingUpdateError(booking);
        Test.stopTest();
    }

    @IsTest
    static void testBookingCancellation() {
        Booking__c booking = [SELECT Id, Stage__c FROM Booking__c LIMIT 1];
        Test.startTest();
        booking.Stage__c = 'Cancellation';
        update booking;
        Test.stopTest();

        Booking__c after = [SELECT Stage__c FROM Booking__c WHERE Id = :booking.Id];
    }

    private static void expectDuplicateBookingError(Booking__c booking) {
        try {
            insert booking;
        } catch (DmlException error) {
            if (error.getMessage().contains('only one active booking')) {
                return;
            }
            throw error;
        }
        throw new UnexpectedSuccessfulDmlException('Expected duplicate active booking to be rejected.');
    }

    private static void expectDuplicateBookingUpdateError(Booking__c booking) {
        try {
            update booking;
        } catch (DmlException error) {
            if (error.getMessage().contains('only one active booking')) {
                return;
            }
            throw error;
        }
        throw new UnexpectedSuccessfulDmlException('Expected booking update to an occupied unit to be rejected.');
    }
}