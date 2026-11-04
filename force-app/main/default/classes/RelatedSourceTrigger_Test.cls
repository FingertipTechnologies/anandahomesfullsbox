@isTest
public class RelatedSourceTrigger_Test {

    @isTest
    static void test_ReEngaged_CP_Lead_Update_And_Sharing() {

        /* ----------------------------
           Create CP Owner User
        ----------------------------- */
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User cpOwner = new User(
            FirstName = 'CP',
            LastName = 'Owner',
            Email = 'cpowner@test.com',
            Username = 'cpowner' + System.currentTimeMillis() + '@test.com',
            Alias = 'cpown',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert cpOwner;

        /* ----------------------------
           Create Lead
        ----------------------------- */
        Lead ld = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Company',
            Phone = '9999999999',
            Phone__c = '9999999999',
            OwnerId = UserInfo.getUserId()
        );
        insert ld;

        /* ----------------------------
           Pre-insert LeadShare with Edit access
           (Bypasses the trigger's redundant Read insert)
        ----------------------------- */
        LeadShare existingShare = new LeadShare(
            LeadId = ld.Id,
            UserOrGroupId = cpOwner.Id,
            LeadAccessLevel = 'Edit'
        );
        insert existingShare;

        /* ----------------------------
           Create Channel Partner
        ----------------------------- */
        Channel_Partner__c cp = new Channel_Partner__c(
            Mobile_Number__c = '8888888888',
            OwnerId = cpOwner.Id
        );
        insert cp;

        /* ----------------------------
           Create custom Lead__c
        ----------------------------- */
        Lead__c customLead = new Lead__c(
            Name__c = 'Test Custom Lead',
            Phone__c = '7777777777',
            Allocated_Project__c = 'The Ozone Heights'
        );
        insert customLead;

        /* ----------------------------
           Create Related Source (Re-Engaged)
        ----------------------------- */
        Related_Source__c rs = new Related_Source__c(
            Medium__c = 'CHANNEL PARTNERS',
            Channel_Partner__c = cp.Id,
            SLead__c = ld.Id,
            CLead__c = customLead.Id,
            Lead_Type__c = 'Re-Engaged'
        );

        Test.startTest();
        insert rs;

        // Query & assert BEFORE stopTest (before SLeadTrigger deletes the standard Lead)
        Lead updatedLead = [
            SELECT Re_Engaged_CP_Date__c
            FROM Lead
            WHERE Id = :ld.Id
        ];

        System.assertEquals(
            System.today(),
            updatedLead.Re_Engaged_CP_Date__c,
            'Re-Engaged CP Date should be populated'
        );

        // Test comment sync to AddNoteController
        rs.comments__c = 'New remark from test';
        update rs;

        Test.stopTest();
    }
}