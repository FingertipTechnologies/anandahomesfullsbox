/**
 * Backfill for leads that were data-loaded with LeadTrigger switched off (Enable_Trigger = FALSE):
 * creates the "New Lead" Related Source that RelatedSourceHandler.afterinsertLogic2 would have
 * created for each of them, with the same field mapping.
 *
 * Run:   Database.executeBatch(new RelatedSourceBackfillBatch('Praveen Kumar'), 2000);
 *
 * - Nothing else fires: RelatedSourceTrigger is bypassed through Utility.runRelatedSourceTrigger
 *   (no Pulse call-out, no CP sharing, no remark sync). There are no flows, workflow rules or
 *   validation rules on Related_Source__c. Lead__c is never updated.
 * - Idempotent: a lead that already has a 'New Lead' Related Source is skipped, so the batch can be
 *   re-run after a partial failure.
 * - Source / Sub Source / Campaign: the data load filled First_Source_Of_Enquiry__c,
 *   First_Sub_Source__c and First_Campaign__c and left Primary_Source__c, Primary_Sub_Source__c and
 *   Campaign__c blank, so the "First" fields are used when the "Primary" ones are empty.
 */
public without sharing class RelatedSourceBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final String LEAD_TYPE_NEW = 'New Lead';
    private static final Integer MAX_ERRORS_KEPT = 200;

    private final String importedBy;
    public Integer created = 0;
    public Integer failed = 0;
    public List<String> errors = new List<String>();

    /** @param importedBy value of Lead__c.Data_Imported_By__c that marks the data-loaded leads */
    public RelatedSourceBackfillBatch(String importedBy) {
        if (String.isBlank(importedBy)) {
            throw new IllegalArgumentException('importedBy is required');
        }
        this.importedBy = importedBy;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String newLeadType = LEAD_TYPE_NEW;
        return Database.getQueryLocator([
            SELECT Id, OwnerId, Name__c, ERP_Id__c,
                   Primary_Source__c, Primary_Sub_Source__c, First_Source_Of_Enquiry__c, First_Sub_Source__c,
                   Source_Type__c, Medium__c,
                   Referring_Customer_Unit__c, Referring_Customer_Project__c,
                   Referring_Vendor_Company_Name__c, Referring_Vendor_Id__c, Referring_Employee_ID__c,
                   Referral_Source__c, Referring_For__c, Existing_Customer_Info__c, Employee_Id__c,
                   Referrer_Name__c, Referrer_Mobile_No__c, Referrer_Alternate_Mobile_No__c,
                   Referrer_Email__c, Referrer_Alternate_Email__c,
                   Country__c, executiveName__c, executivePhone__c, Comments__c, State__c, City__c,
                   Channel_Partner__c,
                   Phone__c, Country_Code__c, Secondary_Phone__c, Secondary_Country_Code__c,
                   Email__c, Secondary_Email__c, Last_Comment__c, Allocated_Project__c,
                   Campaign_Name__c, Campaign__c, First_Campaign__c,
                   Type_of_lead__c, Query_For__c, Query_Type__c, Message__c
            FROM Lead__c
            WHERE Data_Imported_By__c = :importedBy
              AND Id NOT IN (SELECT CLead__c FROM Related_Source__c WHERE Lead_Type__c = :newLeadType)
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Lead__c> leads) {
        Utility.runRelatedSourceTrigger = false;

        List<Related_Source__c> rsList = new List<Related_Source__c>();
        for (Lead__c ld : leads) {
            rsList.add(build(ld));
        }

        Database.SaveResult[] results = Database.insert(rsList, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                created++;
                continue;
            }
            failed++;
            if (errors.size() < MAX_ERRORS_KEPT) {
                String msg = '';
                for (Database.Error e : results[i].getErrors()) {
                    msg += e.getStatusCode() + ' ' + e.getMessage() + ' ' + e.getFields() + '; ';
                }
                errors.add(leads[i].Id + ': ' + msg);
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'RelatedSourceBackfillBatch [' + importedBy + '] created=' + created
            + ' failed=' + failed + (errors.isEmpty() ? '' : ' first errors: ' + String.join(errors, ' | ')));
    }

    /** Same mapping as the "fresh lead" branch of RelatedSourceHandler.afterinsertLogic2. */
    public static Related_Source__c build(Lead__c nld) {
        Related_Source__c rs = new Related_Source__c();
        rs.CLead__c = nld.Id;
        rs.OwnerId = nld.OwnerId;
        rs.Lead_Type__c = LEAD_TYPE_NEW;
        rs.ERP_Id__c = nld.ERP_Id__c;
        rs.Lead_Name__c = nld.Name__c;
        rs.Source__c = String.isNotBlank(nld.Primary_Source__c) ? nld.Primary_Source__c : nld.First_Source_Of_Enquiry__c;
        rs.Sub_Source__c = String.isNotBlank(nld.Primary_Sub_Source__c) ? nld.Primary_Sub_Source__c : nld.First_Sub_Source__c;
        rs.Source_Type__c = nld.Source_Type__c;
        rs.Medium__c = nld.Medium__c;
        rs.Referring_Customer_s_Unit__c = nld.Referring_Customer_Unit__c;
        rs.Referring_Customer_s_Project__c = nld.Referring_Customer_Project__c;
        rs.Referring_Vendor_s_Company_Name__c = nld.Referring_Vendor_Company_Name__c;
        rs.Referring_Vendor_s_Id__c = nld.Referring_Vendor_Id__c;
        rs.Referring_Employee_ID__c = nld.Referring_Employee_ID__c;
        rs.Referral_Source__c = nld.Referral_Source__c;
        rs.Referring_For__c = nld.Referring_For__c;
        rs.Existing_Customer_Info__c = nld.Existing_Customer_Info__c;
        rs.Employee_Id__c = nld.Employee_Id__c;
        rs.Referrer_Name__c = nld.Referrer_Name__c;
        rs.Referrer_Mobile_No__c = nld.Referrer_Mobile_No__c;
        rs.Referrer_Alternate_Mobile_No__c = nld.Referrer_Alternate_Mobile_No__c;
        rs.Referrer_Email__c = nld.Referrer_Email__c;
        rs.Referrer_Alternate_Email__c = nld.Referrer_Alternate_Email__c;
        rs.Country__c = nld.Country__c;
        rs.executiveName__c = cut(nld.executiveName__c, 100);
        rs.executivePhone__c = nld.executivePhone__c;
        rs.comments__c = cut(nld.Comments__c, 255);
        rs.state__c = nld.State__c;
        rs.city__c = nld.City__c;
        rs.Channel_Partner__c = nld.Channel_Partner__c;
        rs.Phone__c = nld.Phone__c;
        rs.Country_Code__c = nld.Country_Code__c;
        rs.Secondary_Phone__c = nld.Secondary_Phone__c;
        rs.Secondary_Contry_Code__c = nld.Secondary_Country_Code__c;
        rs.Email__c = nld.Email__c;
        rs.Secondary_Email__c = nld.Secondary_Email__c;
        rs.Description__c = cut(nld.Last_Comment__c, 255);
        rs.Allocated_Project__c = nld.Allocated_Project__c;
        rs.Campaign__c = nld.Campaign_Name__c;
        rs.Campaign_Text__c = String.isNotBlank(nld.Campaign__c) ? nld.Campaign__c : nld.First_Campaign__c;
        rs.type_of_lead__c = nld.Type_of_lead__c;
        rs.Query_For__c = nld.Query_For__c;
        rs.Query_Type__c = nld.Query_Type__c;
        rs.Message__c = nld.Message__c;
        return rs;
    }

    // Lead long-text fields land in 255 / 100 character Related Source fields.
    private static String cut(String value, Integer max) {
        return value == null ? null : value.abbreviate(max);
    }
}
