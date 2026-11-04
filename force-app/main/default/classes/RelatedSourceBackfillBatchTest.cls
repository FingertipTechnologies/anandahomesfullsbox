@isTest
private class RelatedSourceBackfillBatchTest {

    private static final String IMPORT_TAG = 'Backfill Test';

    @TestSetup
    static void makeData() {
        // Leads are data-loaded with LeadTrigger switched off, exactly like the real import,
        // so no Related Source exists for them yet.
        Utility.runLeadTrigger = false;
        insert new List<Lead__c>{
            new Lead__c(Name__c = 'Imported One', Phone__c = '9000000001', Country_Code__c = '91',
                        Country__c = 'India', Email__c = 'one@example.invalid',
                        First_Source_Of_Enquiry__c = '99acres', First_Campaign__c = 'Campaign A',
                        Allocated_Project__c = 'The Drizzle', Data_Imported_By__c = IMPORT_TAG,
                        Comments__c = 'remark that must not sync'),
            new Lead__c(Name__c = 'Imported Two', Phone__c = '9000000002',
                        First_Source_Of_Enquiry__c = 'IVR', Data_Imported_By__c = IMPORT_TAG),
            new Lead__c(Name__c = 'Not Imported', Phone__c = '9000000003',
                        First_Source_Of_Enquiry__c = 'IVR')
        };
    }

    @isTest
    static void createsOneNewLeadSourcePerImportedLead() {
        Test.startTest();
        Database.executeBatch(new RelatedSourceBackfillBatch(IMPORT_TAG), 200);
        Test.stopTest();

        Map<Id, Lead__c> leads = new Map<Id, Lead__c>([SELECT Id, OwnerId, Name__c, Data_Imported_By__c, Last_Note__c FROM Lead__c]);
        List<Related_Source__c> sources = [
            SELECT CLead__c, OwnerId, Lead_Type__c, Lead_Name__c, Source__c, Sub_Source__c, Campaign_Text__c,
                   Phone__c, Country_Code__c, Country__c, Email__c, Allocated_Project__c
            FROM Related_Source__c
        ];
        System.assertEquals(2, sources.size(), 'one Related Source per imported lead, none for the other lead');

        Map<Id, Related_Source__c> byLead = new Map<Id, Related_Source__c>();
        for (Related_Source__c rs : sources) {
            byLead.put(rs.CLead__c, rs);
        }
        for (Lead__c ld : leads.values()) {
            if (ld.Data_Imported_By__c != IMPORT_TAG) {
                System.assert(!byLead.containsKey(ld.Id), 'lead that was not imported must be untouched');
                continue;
            }
            Related_Source__c rs = byLead.get(ld.Id);
            System.assertNotEquals(null, rs, 'missing Related Source for ' + ld.Name__c);
            System.assertEquals('New Lead', rs.Lead_Type__c);
            System.assertEquals(ld.OwnerId, rs.OwnerId, 'Related Source is owned by the lead owner');
            System.assertEquals(ld.Name__c, rs.Lead_Name__c);
            if (ld.Name__c == 'Imported One') {
                System.assertEquals('99acres', rs.Source__c, 'Source comes from First_Source_Of_Enquiry__c');
                System.assertEquals(null, rs.Sub_Source__c);
                System.assertEquals('Campaign A', rs.Campaign_Text__c, 'Campaign text comes from First_Campaign__c');
                System.assertEquals('9000000001', rs.Phone__c);
                System.assertEquals('91', rs.Country_Code__c);
                System.assertEquals('India', rs.Country__c);
                System.assertEquals('one@example.invalid', rs.Email__c);
                System.assertEquals('The Drizzle', rs.Allocated_Project__c);
                // Had RelatedSourceTrigger fired inside the batch, the remark would have been
                // copied to the lead through AddNoteController.updateLastNote.
                System.assertEquals(null, ld.Last_Note__c, 'trigger must not run during the backfill');
            }
        }
    }

    @isTest
    static void skipsLeadsThatAlreadyHaveANewLeadSource() {
        Lead__c one = [SELECT Id FROM Lead__c WHERE Name__c = 'Imported One'];
        Utility.runRelatedSourceTrigger = false;
        insert new Related_Source__c(CLead__c = one.Id, Lead_Type__c = 'New Lead', Source__c = 'Existing');

        Test.startTest();
        Database.executeBatch(new RelatedSourceBackfillBatch(IMPORT_TAG), 200);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Related_Source__c WHERE CLead__c = :one.Id],
            'an existing New Lead source must not be duplicated');
        System.assertEquals(2, [SELECT COUNT() FROM Related_Source__c], 'only the other imported lead gets a new source');
    }

    @isTest
    static void primaryFieldsWinOverFirstFieldsWhenPresent() {
        Lead__c ld = new Lead__c(Id = [SELECT Id FROM Lead__c WHERE Name__c = 'Imported Two'].Id,
                                 Name__c = 'Imported Two', First_Source_Of_Enquiry__c = 'IVR',
                                 Primary_Source__c = 'Digital', First_Campaign__c = 'First',
                                 Campaign__c = 'Primary', Comments__c = 'x'.repeat(300));
        Related_Source__c rs = RelatedSourceBackfillBatch.build(ld);
        System.assertEquals('Digital', rs.Source__c);
        System.assertEquals('Primary', rs.Campaign_Text__c);
        System.assertEquals(255, rs.comments__c.length(), 'long lead comment is cut to the Related Source field size');
    }

    @isTest
    static void bypassFlagSkipsRelatedSourceTrigger() {
        Lead__c one = [SELECT Id FROM Lead__c WHERE Name__c = 'Imported One'];

        Test.startTest();
        Utility.runRelatedSourceTrigger = false;
        insert new Related_Source__c(CLead__c = one.Id, Lead_Type__c = 'New Lead', comments__c = 'remark that must not sync');
        Test.stopTest();
        // With the trigger active this insert would copy the remark to the lead through
        // AddNoteController.updateLastNote (and queue the Pulse call-out).

        System.assertEquals(null, [SELECT Last_Note__c FROM Lead__c WHERE Id = :one.Id].Last_Note__c,
            'remark sync must not run when the trigger is bypassed');
    }
}
