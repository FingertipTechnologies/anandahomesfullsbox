@IsTest
private class DemandLetterPDFControllerTest {

    @TestSetup
    static void setup() {
        Project__c project = new Project__c(
            Name = 'Demand Letter Test Project',
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

        Quote__c quote = new Quote__c();
        insert quote;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = unit.Id,
            Quote__c = quote.Id,
            Booking_Date__c = Date.today(),
            Booking_Amount__c = 100000,
            Total_Flat_Cost__c = 1000000,
            GST_Amount__c = 50000,
            Total_Payable_Amount__c = 1050000,
            Mode_Of_Payment__c = 'UPI',
            Status__c = 'New',
            Email__c = 'demandletter@example.com',
            Applicant_Name__c = 'Demand Letter Customer',
            Loan_Bank_Name__c = 'Example Loan Bank',
            Flat_Number__c = 101,
            Block1__c = 'B'
        );
        insert booking;

        Payment_Schedule__c schedule = new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'On Completion of Slab',
            Percentage__c = 10,
            Amount__c = 105000,
            Pending_Amount__c = 105000,
            Amount_Paid__c = 0,
            Due_Date__c = Date.today(),
            Status__c = 'Pending',
            Payment_Schedule_Amount__c = 100000,
            GST_Amount__c = 5000
        );
        insert schedule;

        Demands__c demand = new Demands__c(
            Booking__c = booking.Id,
            Project__c = project.Id,
            Payment_Schedule__c = schedule.Id,
            Demand_Amount__c = 105000,
            Base_Amount__c = 100000,
            Flat_Amount__c = 100000,
            GST_Amount__c = 5000,
            TDS_Amount__c = 5000,
            Pending_Amount__c = 105000,
            Demand_Type__c = 'Bulk Demand',
            Demand_Date__c = Date.newInstance(2026, 11, 2),
            Status__c = 'Raised'
        );
        insert demand;

        insert new List<Account_Name__c>{
            new Account_Name__c(
                Name = 'Full Escrow',
                Project__c = project.Id,
                Account_Type__c = 'Full',
                Account_No__c = '111111',
                Bank_Name__c = 'Example Bank',
                IFSC_Code__c = 'EXAM0000001',
                Branch__c = 'Full Branch'
            ),
            new Account_Name__c(
                Name = 'Flat Escrow',
                Project__c = project.Id,
                Account_Type__c = 'Flat',
                Account_No__c = '222222',
                Bank_Name__c = 'Example Bank',
                IFSC_Code__c = 'EXAM0000002',
                Branch__c = 'Flat Branch'
            ),
            new Account_Name__c(
                Name = 'GST Escrow',
                Project__c = project.Id,
                Account_Type__c = 'GST',
                Account_No__c = '333333',
                Bank_Name__c = 'Example Bank',
                IFSC_Code__c = 'EXAM0000003',
                Branch__c = 'GST Branch'
            )
        };
    }

    @IsTest
    static void extension_loadsOnlyTheFlatProjectAccount() {
        Demands__c demand = [
            SELECT Id, Project__c
            FROM Demands__c
            WHERE Booking__r.Email__c = 'demandletter@example.com'
            LIMIT 1
        ];
        Test.setCurrentPage(new PageReference('/apex/DemandLetterFlat?id=' + demand.Id));

        DemandLetterPDFController controller =
            new DemandLetterPDFController(new ApexPages.StandardController(demand));

        System.assertEquals(null, controller.errorMessage);
        System.assertEquals('Flat', controller.accountType);
        System.assertEquals('Flat Escrow', controller.accountHolder);
        System.assertEquals('222222', controller.accountNumber);
    }

    @IsTest
    static void extension_usesGSTAndFullProjectAccountsForTheirPages() {
        Demands__c demand = [
            SELECT Id
            FROM Demands__c
            WHERE Booking__r.Email__c = 'demandletter@example.com'
            LIMIT 1
        ];

        Test.setCurrentPage(new PageReference('/apex/DemandLetterGST?id=' + demand.Id));
        DemandLetterPDFController gstController =
            new DemandLetterPDFController(new ApexPages.StandardController(demand));
        System.assertEquals('GST', gstController.accountType);
        System.assertEquals('GST Escrow', gstController.accountHolder);

        Test.setCurrentPage(new PageReference('/apex/DemandLetterFull?id=' + demand.Id));
        DemandLetterPDFController fullController =
            new DemandLetterPDFController(new ApexPages.StandardController(demand));
        System.assertEquals('Full', fullController.accountType);
        System.assertEquals('Full Escrow', fullController.accountHolder);
    }

    @IsTest
    static void extension_reportsWhenTheProjectHasNoMatchingAccount() {
        Demands__c demand = [
            SELECT Id, Project__c
            FROM Demands__c
            WHERE Booking__r.Email__c = 'demandletter@example.com'
            LIMIT 1
        ];
        delete [
            SELECT Id
            FROM Account_Name__c
            WHERE Project__c = :demand.Project__c
              AND Account_Type__c = 'GST'
        ];

        Test.setCurrentPage(new PageReference('/apex/DemandLetterGST?id=' + demand.Id));
        DemandLetterPDFController controller =
            new DemandLetterPDFController(new ApexPages.StandardController(demand));

        System.assertEquals('GST', controller.accountType);
        System.assert(
            controller.errorMessage.contains('No GST Account Name'),
            'The page should explain that a GST account is not configured.'
        );
    }

    @IsTest
    static void extension_reportsDuplicateProjectAccounts() {
        Demands__c demand = [
            SELECT Id, Project__c
            FROM Demands__c
            WHERE Booking__r.Email__c = 'demandletter@example.com'
            LIMIT 1
        ];
        insert new Account_Name__c(
            Name = 'Duplicate GST Account',
            Project__c = demand.Project__c,
            Account_Type__c = 'GST'
        );

        Test.setCurrentPage(new PageReference('/apex/DemandLetterGST?id=' + demand.Id));
        DemandLetterPDFController controller =
            new DemandLetterPDFController(new ApexPages.StandardController(demand));

        System.assert(
            controller.errorMessage.contains('More than one GST Account Name'),
            'The page should explain that duplicate GST accounts are configured.'
        );
    }

    @IsTest
    static void extension_validatesPageAndDemandBeforeLoadingAccount() {
        Demands__c demand = [
            SELECT Id
            FROM Demands__c
            WHERE Booking__r.Email__c = 'demandletter@example.com'
            LIMIT 1
        ];

        Test.setCurrentPage(new PageReference('/apex/UnsupportedDemandLetter?id=' + demand.Id));
        DemandLetterPDFController unsupportedPage =
            new DemandLetterPDFController(new ApexPages.StandardController(demand));
        System.assertEquals(null, unsupportedPage.accountType);
        System.assert(unsupportedPage.errorMessage.contains('Use the Flat, GST, or Full'));

        Test.setCurrentPage(new PageReference('/apex/DemandLetterFlat'));
        DemandLetterPDFController unsavedDemand =
            new DemandLetterPDFController(
                new ApexPages.StandardController(new Demands__c())
            );
        System.assert(unsavedDemand.errorMessage.contains('A saved demand record'));

        DemandLetterPDFController nullController =
            new DemandLetterPDFController(null);
        System.assert(
            nullController.errorMessage.contains('Unable to load project account details')
        );
    }

    @IsTest
    static void extension_reportsDemandDeletedBeforeAccountLookup() {
        Demands__c demand = [
            SELECT Id
            FROM Demands__c
            WHERE Booking__r.Email__c = 'demandletter@example.com'
            LIMIT 1
        ];
        delete demand;

        Test.setCurrentPage(new PageReference('/apex/DemandLetterFlat?id=' + demand.Id));
        DemandLetterPDFController controller =
            new DemandLetterPDFController(new ApexPages.StandardController(demand));

        System.assert(
            controller.errorMessage.contains('List has no rows'),
            'The extension should return a clear error when the demand no longer exists.'
        );
    }
}