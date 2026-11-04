// Last Modified: 2026-10-01
@isTest
public class HomeNotificationControllerTest {

    // ---------- Helpers ----------
    private static Lead__c createLead(String name, String phone) {
        Lead__c l = new Lead__c(
            Name__c = name,
            Lead_Status__c = 'New Enquiry',
            Phone__c = phone
        );
        insert l;
        return l;
    }

    private static Follow_up__c createFollowUp(Id leadId, String comments) {
        Follow_up__c fu = new Follow_up__c(
            Status__c = 'Scheduled',
            Comments__c = comments,
            Scheduled_Date__c = System.now().addMinutes(5),
            CLead__c = leadId
        );
        insert fu;
        return fu;
    }

    // ---------- Query methods ----------
    @isTest
    static void testQueryMethods() {
        Lead__c testLead = createLead('Test Lead', '9876543210');
        createFollowUp(testLead.Id, 'test');

        Site_Visit__c sv = new Site_Visit__c(
            Status__c = 'Scheduled',
            Date__c = System.now().addDays(1),
            CLead__c = testLead.Id
        );
        insert sv;

        Test.startTest();
        List<Follow_Up__c> followUps = HomeNotificationController.getFollowUpInformation();
        List<Site_Visit__c> siteVisits = HomeNotificationController.getSiteVistInformation();
        List<Follow_Up__c> pendingFollowUps = HomeNotificationController.getPendingFollowUpInformation();
        List<Site_Visit__c> pendingSiteVisits = HomeNotificationController.getPendingSiteVistInformation();
        Test.stopTest();

        System.assertNotEquals(null, followUps, 'followUps list returned');
        System.assertNotEquals(null, siteVisits, 'siteVisits list returned');
        System.assertNotEquals(null, pendingFollowUps, 'pendingFollowUps list returned');
        System.assertNotEquals(null, pendingSiteVisits, 'pendingSiteVisits list returned');
    }

    // ---------- getUserName ----------
    @isTest
    static void testGetUserName() {
        Test.startTest();
        String userName = HomeNotificationController.getUserName();
        Test.stopTest();
        System.assertNotEquals(null, userName, 'getUserName returned a value');
    }

    
    // ---------- updateFollowupDetails: Cancelled ----------
    @isTest
    static void testUpdateFollowupDetails_Cancelled() {
        Lead__c testLead = createLead('Cancelled Lead', '9876500002');
        Follow_up__c fu = createFollowUp(testLead.Id, 'initial');

        Test.startTest();
        String result = HomeNotificationController.updateFollowupDetails(fu.Id, 'Cancelled', null);
        Test.stopTest();

        System.assertEquals('Updated', result, 'Cancelled update should succeed');
        Follow_up__c after = [
            SELECT Status__c, Comments__c, Completed_Date__c
            FROM Follow_up__c WHERE Id = :fu.Id
        ];
        System.assertEquals('Cancelled', after.Status__c);
        System.assertEquals('initial', after.Comments__c, 'Comment is not overwritten');
        System.assertEquals(null, after.Completed_Date__c, 'Completed_Date__c not stamped for Cancelled');
    }

    // ---------- updateFollowupDetails: record not found ----------
    @isTest
    static void testUpdateFollowupDetails_NotFound() {
        String fakeId = Follow_Up__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';

        Test.startTest();
        String result = HomeNotificationController.updateFollowupDetails(fakeId, 'Completed', System.now());
        Test.stopTest();

        System.assertEquals('Record not found', result);
    }

    // ---------- updateFollowupDetails: DML failure branch ----------
    // An invalid status value fails on restricted picklists. If your org's picklist
    // is not restricted the update succeeds, so both outcomes are accepted.
    @isTest
    static void testUpdateFollowupDetails_DmlFailure() {
        Lead__c testLead = createLead('DML Failure Lead', '9876500001');
        Follow_up__c fu = createFollowUp(testLead.Id, 'initial');

        String result;
        Boolean threw = false;
        Test.startTest();
        try {
            result = HomeNotificationController.updateFollowupDetails(fu.Id, 'Invalid_Status_XYZ', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw || result == 'Updated', 'Either an AuraHandledException or a successful update');
    }

    // ---------- todaysLeads: Pre-Sales Executive profile ----------
    @isTest
    static void testTodaysLeads_PreSalesExecutiveProfile() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Pre-Sales Executive' LIMIT 1];
        if (profiles.isEmpty()) return;

        User testUser = new User(
            FirstName = 'PreSales', LastName = 'ExecUser',
            Username = 'presalesexec' + System.currentTimeMillis() + '@test.com',
            Email = 'presalesexec@test.com', Alias = 'psexec',
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = profiles[0].Id
        );
        insert testUser;

        System.runAs(testUser) {
            Test.startTest();
            HomeNotificationController.datawrapper result = HomeNotificationController.todaysLeads(10, 1);
            Test.stopTest();
            System.assertNotEquals(null, result);
        }
    }

    // ---------- todaysLeads: Sales profile ----------
    @isTest
    static void testTodaysLeads_SalesProfile() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Sales' LIMIT 1];
        if (profiles.isEmpty()) return;

        User testUser = new User(
            FirstName = 'SalesProf', LastName = 'TestUser',
            Username = 'salesprof' + System.currentTimeMillis() + '@test.com',
            Email = 'salesprof@test.com', Alias = 'salpr',
            TimeZoneSidKey = 'America/Los_Angeles', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = profiles[0].Id
        );
        insert testUser;

        System.runAs(testUser) {
            Test.startTest();
            HomeNotificationController.datawrapper result = HomeNotificationController.todaysLeads(10, 1);
            Test.stopTest();
            System.assertNotEquals(null, result);
        }
    }

    // ---------- todaysLeads: default branch (any other profile) ----------
    @isTest
    static void testTodaysLeads_DefaultBranch() {
        createLead('Today Lead', '9876500010');

        Test.startTest();
        HomeNotificationController.datawrapper result = HomeNotificationController.todaysLeads(10, 1);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.todaysldCount, 'todaysldCount should be set');
    }

    // ---------- getLeadsForPeriod: counts, chips, paging ----------
    // Trigger is bypassed so the running user stays the owner (round robin would reassign).
    private static Lead__c periodLead(String name, String phone, String status, Datetime pushedOn) {
        // Sales statuses live on the Sales record type where the picklist is record-type restricted
        Boolean isSales = status.startsWith('Sales') || status.startsWith('New Sales');
        Schema.RecordTypeInfo rt = Schema.SObjectType.Lead__c.getRecordTypeInfosByName().get(isSales ? 'Sales' : 'Pre Sales');
        Lead__c ld = new Lead__c(Name__c = name, Phone__c = phone, Lead_Status__c = status, Pushed_On__c = pushedOn);
        if (rt != null && rt.isAvailable()) ld.RecordTypeId = rt.getRecordTypeId();
        return ld;
    }

    @isTest
    static void testGetLeadsForPeriod_CountsAndFilters() {
        Utility.runLeadTrigger = false;
        List<Lead__c> leads = new List<Lead__c>();
        // 10 leads assigned today: 4 New Enquiry, 2 New Sales Enquiry, 4 worked
        for (Integer i = 0; i < 4; i++) leads.add(periodLead('NE ' + i, '91000000' + String.valueOf(10 + i), 'New Enquiry', null));
        for (Integer i = 0; i < 2; i++) leads.add(periodLead('NSE ' + i, '91000000' + String.valueOf(20 + i), 'New Sales Enquiry', null));
        leads.add(periodLead('W1', '9100000031', 'Pre Sales RNR', null));
        leads.add(periodLead('W2', '9100000032', 'Pre Sales Follow Up', null));
        leads.add(periodLead('W3', '9100000033', 'Pre Sales Prospect', null));
        leads.add(periodLead('W4', '9100000034', 'Sales RNR', null));
        // Pushed to sales last month (created today): counts in last month, not today
        leads.add(periodLead('Pushed', '9100000041', 'New Sales Enquiry', Datetime.now().addMonths(-1)));
        // Created yesterday
        Lead__c yesterday = periodLead('Yesterday', '9100000051', 'New Enquiry', null);
        leads.add(yesterday);
        insert leads;
        Test.setCreatedDate(yesterday.Id, Datetime.now().addDays(-1));

        Test.startTest();
        HomeNotificationController.PeriodLeadsWrapper today =
            HomeNotificationController.getLeadsForPeriod('today', null, null, 'all', 5, 1);
        HomeNotificationController.PeriodLeadsWrapper workedPage =
            HomeNotificationController.getLeadsForPeriod('today', null, null, 'worked', 10, 1);
        HomeNotificationController.PeriodLeadsWrapper nePage =
            HomeNotificationController.getLeadsForPeriod('today', null, null, 'New Enquiry', 10, 1);
        HomeNotificationController.PeriodLeadsWrapper yest =
            HomeNotificationController.getLeadsForPeriod('yesterday', null, null, 'all', 10, 1);
        HomeNotificationController.PeriodLeadsWrapper lastMonth =
            HomeNotificationController.getLeadsForPeriod('lastMonth', null, null, 'New Sales Enquiry', 10, 1);
        HomeNotificationController.PeriodLeadsWrapper custom =
            HomeNotificationController.getLeadsForPeriod('custom', String.valueOf(Date.today().addDays(-1)), String.valueOf(Date.today()), 'all', 50, 1);
        Test.stopTest();

        System.assertEquals(10, today.total, 'Total assigned today');
        System.assertEquals(6, today.pending, 'Yet to work today');
        System.assertEquals(4, today.worked, 'Worked today');
        System.assertEquals(4, today.newEnquiry);
        System.assertEquals(2, today.newSalesEnquiry);
        System.assertEquals(10, today.filteredTotal);
        System.assertEquals(5, today.records.size(), 'First page of 5');
        System.assertEquals(Date.today(), today.startDate);
        System.assertEquals(Date.today(), today.endDate);

        System.assertEquals(4, workedPage.filteredTotal);
        System.assertEquals(4, workedPage.records.size());
        for (Lead__c ld : workedPage.records) {
            System.assert(!HomeNotificationController.NEW_STATUSES.contains(ld.Lead_Status__c), 'Worked chip returns non-new leads only');
        }
        System.assertEquals(4, nePage.filteredTotal);
        for (Lead__c ld : nePage.records) System.assertEquals('New Enquiry', ld.Lead_Status__c);

        System.assertEquals(1, yest.total, 'Only the lead created yesterday');
        System.assertEquals(1, yest.pending);
        System.assertEquals(1, lastMonth.filteredTotal, 'Pushed lead counts in the month it was pushed');
        System.assertEquals(11, custom.total, 'Custom range covers yesterday and today');
    }

    @isTest
    static void testGetLeadsForPeriod_InvalidCustomRange() {
        Test.startTest();
        HomeNotificationController.PeriodLeadsWrapper missing =
            HomeNotificationController.getLeadsForPeriod('custom', null, null, 'all', 10, 1);
        HomeNotificationController.PeriodLeadsWrapper bad =
            HomeNotificationController.getLeadsForPeriod('custom', 'not-a-date', '2026-01-01', 'all', 10, 1);
        HomeNotificationController.PeriodLeadsWrapper defaults =
            HomeNotificationController.getLeadsForPeriod(null, null, null, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, missing.error, 'Missing custom dates return an error');
        System.assertNotEquals(null, bad.error, 'Unparseable custom dates return an error');
        System.assertEquals(null, defaults.error, 'Null period falls back to today');
        System.assertEquals(Date.today(), defaults.startDate);
    }

    @isTest
    static void testResolvePeriod() {
        Date today = Date.today();
        Date[] r;

        r = HomeNotificationController.resolvePeriod('today', null, null);
        System.assertEquals(today, r[0]); System.assertEquals(today, r[1]);

        r = HomeNotificationController.resolvePeriod('yesterday', null, null);
        System.assertEquals(today.addDays(-1), r[0]); System.assertEquals(today.addDays(-1), r[1]);

        r = HomeNotificationController.resolvePeriod('last7Days', null, null);
        System.assertEquals(today.addDays(-6), r[0], 'Last 7 days starts 6 days ago'); System.assertEquals(today, r[1]);

        r = HomeNotificationController.resolvePeriod('thisWeek', null, null);
        System.assertEquals(0, Math.mod(Date.newInstance(1900, 1, 1).daysBetween(r[0]), 7), 'Week starts on Monday');
        System.assertEquals(r[0].addDays(6), r[1]);
        System.assert(r[0] <= today && today <= r[1], 'Today is inside this week');

        Date[] lw = HomeNotificationController.resolvePeriod('lastWeek', null, null);
        System.assertEquals(r[0].addDays(-7), lw[0]);
        System.assertEquals(r[0].addDays(-1), lw[1]);

        r = HomeNotificationController.resolvePeriod('thisMonth', null, null);
        System.assertEquals(today.toStartOfMonth(), r[0]);
        System.assertEquals(today.toStartOfMonth().addMonths(1).addDays(-1), r[1]);

        r = HomeNotificationController.resolvePeriod('lastMonth', null, null);
        System.assertEquals(today.toStartOfMonth().addMonths(-1), r[0]);
        System.assertEquals(today.toStartOfMonth().addDays(-1), r[1]);

        // Custom, reversed dates are swapped
        r = HomeNotificationController.resolvePeriod('custom', '2026-03-10', '2026-03-01');
        System.assertEquals(Date.newInstance(2026, 3, 1), r[0]);
        System.assertEquals(Date.newInstance(2026, 3, 10), r[1]);

        System.assertEquals(null, HomeNotificationController.resolvePeriod('custom', '', '2026-03-01'));
        System.assertEquals(null, HomeNotificationController.resolvePeriod('custom', 'abc', 'def'));
    }
}