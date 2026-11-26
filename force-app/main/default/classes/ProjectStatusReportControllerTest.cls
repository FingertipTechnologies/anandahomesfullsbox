@isTest
private class ProjectStatusReportControllerTest {

    private class Fixture {
        Project__c project;
        Block__c tower;
        Booking__c booking;
        Demands__c demand;
        Master_Payment_Schedule__c withPhoto;
        Master_Payment_Schedule__c withoutPhoto;
    }

    private static Fixture build() {
        Fixture f = new Fixture();
        f.project = new Project__c(Name = 'Status Report Project', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert f.project;
        f.tower = new Block__c(Name = 'Tower-9', Project__c = f.project.Id);
        insert f.tower;
        Plot__c unit = new Plot__c(Project__c = f.project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked', Block1__c = f.tower.Id);
        insert unit;
        f.booking = new Booking__c(Project__c = f.project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(),
            Status__c = 'Booked', First_Applicant_Name__c = 'Report Buyer');
        insert f.booking;

        f.withPhoto = new Master_Payment_Schedule__c(Project__c = f.project.Id, Tower__c = f.tower.Id, Sequence__c = 1,
            Percentage__c = 10, Is_Active__c = true, Status__c = 'Completed', Name = 'Foundation', Milestone_Name__c = 'Unused text',
            Completed_Date__c = Date.newInstance(2026, 11, 1), Remarks__c = 'Done');
        f.withoutPhoto = new Master_Payment_Schedule__c(Project__c = f.project.Id, Tower__c = f.tower.Id, Sequence__c = 2,
            Percentage__c = 10, Is_Active__c = true, Status__c = 'In Progress', Name = 'Slab 1');
        insert new List<Master_Payment_Schedule__c>{ f.withPhoto, f.withoutPhoto };

        insert new ContentVersion(Title = 'Foundation photo', PathOnClient = 'foundation.png',
            VersionData = Blob.valueOf('png'), FirstPublishLocationId = f.withPhoto.Id);
        insert new ContentVersion(Title = 'Notes', PathOnClient = 'notes.txt',
            VersionData = Blob.valueOf('text'), FirstPublishLocationId = f.withoutPhoto.Id);

        f.demand = new Demands__c(Booking__c = f.booking.Id, Demand_Type__c = 'Individual Demand',
            Demand_Amount__c = 1000, Pending_Amount__c = 1000, Status__c = 'Raised',
            Demand_Date__c = Date.today(), Due_Date__c = Date.today().addDays(15));
        insert f.demand;
        return f;
    }

    private static ProjectStatusReportController open(Id recordId) {
        PageReference page = Page.ProjectStatusReport;
        if (recordId != null) page.getParameters().put('id', recordId);
        Test.setCurrentPage(page);
        return new ProjectStatusReportController();
    }

    @isTest
    static void fromDemand_listsTowerMilestonesWithPhotos() {
        Fixture f = build();
        Test.startTest();
        ProjectStatusReportController c = open(f.demand.Id);
        Test.stopTest();

        System.assertEquals(null, c.errorMessage);
        System.assertEquals('Status Report Project', c.projectName);
        System.assertEquals('Tower-9', c.towerName);
        System.assertEquals('Report Buyer', c.customerName);
        System.assertEquals(2, c.rows.size());
        System.assertEquals('Foundation', c.rows[0].milestone, 'the master payment schedule name');
        System.assertEquals('Completed', c.rows[0].status);
        System.assert(c.rows[0].isCompleted);
        System.assertEquals('01-11-2026', c.rows[0].statusDate);
        System.assertEquals(true, c.rows[0].hasImage, 'png on the master');
        System.assert(c.rows[0].imageUrls[0].startsWith('/sfc/servlet.shepherd/version/download/'));
        System.assertEquals(false, c.rows[1].hasImage, 'a text file is not an image');
    }

    @isTest
    static void fromBookingAndTower_andErrors() {
        Fixture f = build();
        System.assertEquals(2, open(f.booking.Id).rows.size());
        System.assertEquals(2, open(f.tower.Id).rows.size());
        System.assertNotEquals(null, open(null).errorMessage);
        System.assert(open(f.booking.Id).hasRows);
    }

    @isTest
    static void projectLevelMastersWhenTowerHasNone() {
        Fixture f = build();
        delete [SELECT Id FROM Master_Payment_Schedule__c WHERE Tower__c = :f.tower.Id];
        insert new Master_Payment_Schedule__c(Project__c = f.project.Id, Sequence__c = 1, Percentage__c = 10,
            Is_Active__c = true, Name = 'Project level');
        ProjectStatusReportController c = open(f.demand.Id);
        System.assertEquals(1, c.rows.size());
        System.assertEquals('Pending', c.rows[0].status, 'the master default status');
    }

    @isTest
    static void imageCountForTheUploadPrompt() {
        Fixture f = build();
        System.assertEquals(1, ProjectStatusReportController.getMilestoneImageCount(f.withPhoto.Id));
        System.assertEquals(0, ProjectStatusReportController.getMilestoneImageCount(f.withoutPhoto.Id));
        System.assertEquals(0, ProjectStatusReportController.getMilestoneImageCount(null));
    }
}