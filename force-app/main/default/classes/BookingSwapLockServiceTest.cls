@isTest
private class BookingSwapLockServiceTest {
    private static Booking__c createBooking(Boolean isSwapped) {
        Project__c project = new Project__c(
            Name = 'Swap Lock Test Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;

        Plot__c unit = new Plot__c(
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked'
        );
        insert unit;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Booking_Date__c = Date.today(),
            Status__c = 'New',
            Is_Swapped__c = isSwapped
        );
        insert booking;
        return booking;
    }

    @isTest
    static void bookingEdits_blockBusinessFieldsButAllowFinancialFields() {
        Id bookingId = Id.valueOf(
            Booking__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
        );
        Booking__c oldBooking = new Booking__c(
            Id = bookingId,
            Is_Swapped__c = true,
            Status__c = 'New'
        );
        Booking__c changedBooking = new Booking__c(
            Id = bookingId,
            Is_Swapped__c = true,
            Status__c = 'Booked'
        );
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>{ bookingId => oldBooking };

        Test.startTest();
        BookingSwapLockService.validateLockedBookingEdits(
            new List<Booking__c>{ changedBooking },
            oldMap
        );
        Test.stopTest();

        System.assertEquals(1, changedBooking.getErrors().size());
        System.assert(
            changedBooking.getErrors()[0].getMessage().contains('has been swapped and is locked')
        );

        Booking__c financialUpdate = new Booking__c(
            Id = bookingId,
            Is_Swapped__c = true,
            Status__c = 'New',
            Pending_Amount__c = 50
        );
        BookingSwapLockService.validateLockedBookingEdits(
            new List<Booking__c>{ financialUpdate },
            oldMap
        );
        System.assertEquals(
            0,
            financialUpdate.getErrors().size(),
            'Financial recalculation fields remain editable.'
        );
    }

    @isTest
    static void bookingEdits_unlockedAndBypassedRecordsAreIgnored() {
        Id bookingId = Id.valueOf(
            Booking__c.SObjectType.getDescribe().getKeyPrefix() + '000000000002'
        );
        Booking__c oldBooking = new Booking__c(
            Id = bookingId,
            Is_Swapped__c = false,
            Status__c = 'New'
        );
        Booking__c changedBooking = new Booking__c(
            Id = bookingId,
            Is_Swapped__c = false,
            Status__c = 'Booked'
        );
        Map<Id, Booking__c> oldMap = new Map<Id, Booking__c>{ bookingId => oldBooking };

        BookingSwapLockService.validateLockedBookingEdits(
            new List<Booking__c>{ changedBooking },
            oldMap
        );
        System.assertEquals(0, changedBooking.getErrors().size());

        changedBooking.Is_Swapped__c = true;
        Boolean previousBypass = BookingSwapLockService.bypass;
        BookingSwapLockService.bypass = true;
        try {
            BookingSwapLockService.validateLockedBookingEdits(
                new List<Booking__c>{ changedBooking },
                oldMap
            );
        } finally {
            BookingSwapLockService.bypass = previousBypass;
        }
        System.assertEquals(0, changedBooking.getErrors().size());

        BookingSwapLockService.validateLockedBookingEdits(null, oldMap);
        BookingSwapLockService.validateLockedBookingEdits(
            new List<Booking__c>{ changedBooking },
            null
        );
    }

    @isTest
    static void relatedRecords_blockSwappedBookingAndAllowActiveBooking() {
        Booking__c swappedBooking = createBooking(true);
        Booking__c activeBooking = createBooking(false);

        Co_Applicant__c blockedApplicant = new Co_Applicant__c(
            Booking__c = swappedBooking.Id
        );
        Co_Applicant__c allowedApplicant = new Co_Applicant__c(
            Booking__c = activeBooking.Id
        );
        Co_Applicant__c noBookingApplicant = new Co_Applicant__c();

        Test.startTest();
        BookingSwapLockService.validateLockedRelatedRecords(
            new List<SObject>{ blockedApplicant, allowedApplicant, noBookingApplicant },
            'co-applicant'
        );
        Test.stopTest();

        System.assertEquals(1, blockedApplicant.getErrors().size());
        System.assert(
            blockedApplicant.getErrors()[0].getMessage().contains('co-applicant')
        );
        System.assertEquals(0, allowedApplicant.getErrors().size());
        System.assertEquals(0, noBookingApplicant.getErrors().size());

        BookingSwapLockService.validateLockedRelatedRecords(
            new List<SObject>(),
            'demand'
        );
        BookingSwapLockService.validateLockedRelatedRecords(
            new List<SObject>{ new Demands__c() },
            'demand'
        );
        BookingSwapLockService.validateLockedRelatedRecords(null, 'demand');

        BookingSwapLockService.validateLockedRelatedRecords(
            new List<SObject>{ allowedApplicant },
            new List<SObject>(),
            'co-applicant'
        );
        System.assertEquals(0, allowedApplicant.getErrors().size());
    }

    @isTest
    static void relatedRecords_reparentingAwayFromSwappedBookingIsBlocked() {
        Booking__c swappedBooking = createBooking(true);
        Booking__c activeBooking = createBooking(false);

        Payment_Schedule__c updatedSchedule = new Payment_Schedule__c(
            Booking__c = activeBooking.Id
        );
        Payment_Schedule__c oldSchedule = new Payment_Schedule__c(
            Booking__c = swappedBooking.Id
        );

        Test.startTest();
        BookingSwapLockService.validateLockedRelatedRecords(
            new List<SObject>{ updatedSchedule },
            new List<SObject>{ oldSchedule },
            'payment schedule'
        );
        Test.stopTest();

        System.assertEquals(1, updatedSchedule.getErrors().size());
        System.assert(
            updatedSchedule.getErrors()[0].getMessage().contains('payment schedule')
        );
    }

    @isTest
    static void relatedRecords_bypassAllowsTrustedTransferAndCleanup() {
        Booking__c swappedBooking = createBooking(true);
        Demands__c demand = new Demands__c(Booking__c = swappedBooking.Id);

        Boolean previousBypass = BookingSwapLockService.bypass;
        BookingSwapLockService.bypass = true;
        try {
            BookingSwapLockService.validateLockedRelatedRecords(
                new List<SObject>{ demand },
                'demand'
            );
            BookingSwapLockService.validateLockedRelatedRecords(
                new List<SObject>{ demand },
                new List<SObject>{ new Demands__c(Booking__c = swappedBooking.Id) },
                'demand'
            );
        } finally {
            BookingSwapLockService.bypass = previousBypass;
        }

        System.assertEquals(0, demand.getErrors().size());
    }
}