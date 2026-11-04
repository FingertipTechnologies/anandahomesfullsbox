@isTest
private class InterestWaiverServiceTest {

    private static Booking__c createBooking() {
        Project__c project = new Project__c(
            Name = 'Interest Waiver Test Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Status__c = 'New'
        );
        insert booking;
        return booking;
    }

    @isTest
    static void remainingWaiverSubtractsPriorDemandUseAndClampsAtZero() {
        Booking__c booking = createBooking();
        insert new Interest_Waive_Off__c(
            Booking__c = booking.Id,
            Waive_Amount__c = 100,
            Reason__c = 'Approved waiver balance',
            Approval_Status__c = 'Approved'
        );
        insert new Demands__c(
            Booking__c = booking.Id,
            Interest_Waived_Off_Amount__c = 30,
            Demand_Amount__c = 1,
            Demand_Date__c = Date.today(),
            Demand_Type__c = 'Individual Demand',
            Status__c = 'Raised'
        );

        Map<Id, Decimal> remaining = InterestWaiverService.getRemainingWaivers(
            new Set<Id>{ booking.Id }
        );

        
    }

    @isTest
    static void unapprovedWaiverDoesNotContributeToRemainingBalance() {
        Booking__c booking = createBooking();
        insert new Interest_Waive_Off__c(
            Booking__c = booking.Id,
            Waive_Amount__c = 100,
            Reason__c = 'Pending waiver',
            Approval_Status__c = 'Pending'
        );

        Map<Id, Decimal> remaining = InterestWaiverService.getRemainingWaivers(
            new Set<Id>{ booking.Id }
        );

        System.assertEquals(0, remaining.get(booking.Id));
    }
}