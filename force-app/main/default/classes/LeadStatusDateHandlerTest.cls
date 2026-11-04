@isTest
private class LeadStatusDateHandlerTest {

    @isTest
    static void stampsOnlyWhenStatusChanges() {
        Lead__c a = new Lead__c(Id = fakeId(1), Lead_Status__c = 'Pre Sales RNR');
        Lead__c b = new Lead__c(Id = fakeId(2), Lead_Status__c = 'New Enquiry');
        Map<Id, Lead__c> oldMap = new Map<Id, Lead__c>{
            a.Id => new Lead__c(Id = a.Id, Lead_Status__c = 'New Enquiry'),
            b.Id => new Lead__c(Id = b.Id, Lead_Status__c = 'New Enquiry')
        };

        Test.startTest();
        LeadStatusDateHandler.stampStatusChange(new List<Lead__c>{ a, b }, oldMap);
        LeadStatusDateHandler.stampStatusChange(null, null); // no-op guard
        Test.stopTest();

        System.assertNotEquals(null, a.Status_Change_Date__c, 'Changed status must be stamped');
        System.assertEquals(null, b.Status_Change_Date__c, 'Unchanged status must not be stamped');
    }

    @isTest
    static void stampsThroughTrigger() {
        Utility.runLeadTrigger = false;
        Lead__c ld = new Lead__c(Name__c = 'Stamp Lead', Lead_Status__c = 'New Enquiry', Phone__c = '9876501234');
        insert ld;
        Utility.runLeadTrigger = true;

        Test.startTest();
        ld.Lead_Status__c = 'Pre Sales Follow Up';
        update ld;
        Test.stopTest();

        Lead__c after = [SELECT Status_Change_Date__c FROM Lead__c WHERE Id = :ld.Id];
        if (Label.Enable_Trigger == 'TRUE') {
            System.assertNotEquals(null, after.Status_Change_Date__c, 'Trigger must stamp the status change date');
        }
    }

    private static Id fakeId(Integer n) {
        String s = String.valueOf(n);
        return Id.valueOf(Lead__c.SObjectType.getDescribe().getKeyPrefix() + '0'.repeat(12 - s.length()) + s);
    }
}
