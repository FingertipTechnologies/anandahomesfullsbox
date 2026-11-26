/**
 * @description Project Status Report (VF page ProjectStatusReport, PDF): for one tower, every master
 *              payment-schedule milestone in sequence with its construction status and the photos
 *              uploaded to that Master Payment Schedule's Files ("No image" when there is none).
 *              Attached to the demand emails (user 2026-11-25).
 *
 *              The page is opened with ?id= a Demand, a Booking or a Tower (Block__c):
 *              Demand -> Booking -> Unit (Plot__c.Block1__c) -> Tower. Milestones are the masters of the
 *              booking's project for that tower; when the project has no tower-wise masters, its
 *              project-level masters (no tower) are used.
 */
public without sharing class ProjectStatusReportController {

    /** Image file types shown on the report. */
    public static final Set<String> IMAGE_TYPES = new Set<String>{ 'PNG', 'JPG', 'JPEG', 'GIF', 'BMP' };
    /** Most recent photos shown per milestone. */
    public static final Integer MAX_IMAGES_PER_MILESTONE = 3;

    public String projectName { get; private set; }
    public String towerName { get; private set; }
    public String unitName { get; private set; }
    public String customerName { get; private set; }
    public String reportDate { get; private set; }
    public String errorMessage { get; private set; }
    public List<MilestoneRow> rows { get; private set; }

    public Boolean hasRows { get { return rows != null && !rows.isEmpty(); } }

    public class MilestoneRow {
        public Integer serialNo { get; set; }
        public String milestone { get; set; }
        public String status { get; set; }
        public String statusDate { get; set; }
        public String remarks { get; set; }
        public List<String> imageUrls { get; set; }
        public Boolean hasImage { get { return imageUrls != null && !imageUrls.isEmpty(); } }
        public Boolean isCompleted { get { return status == 'Completed'; } }
    }

    public ProjectStatusReportController() {
        rows = new List<MilestoneRow>();
        reportDate = formatDate(Date.today());
        String rawId = ApexPages.currentPage() == null ? null : ApexPages.currentPage().getParameters().get('id');
        try {
            load(String.isBlank(rawId) ? null : Id.valueOf(rawId));
        } catch (Exception e) {
            errorMessage = 'Unable to build the project status report: ' + e.getMessage();
        }
    }

    private void load(Id recordId) {
        if (recordId == null) {
            errorMessage = 'A Demand, Booking or Tower id is required.';
            return;
        }
        Id projectId;
        Id towerId;
        Schema.SObjectType type = recordId.getSObjectType();

        Id bookingId;
        if (type == Demands__c.SObjectType) {
            List<Demands__c> demands = [SELECT Booking__c FROM Demands__c WHERE Id = :recordId LIMIT 1];
            bookingId = demands.isEmpty() ? null : demands[0].Booking__c;
        } else if (type == Booking__c.SObjectType) {
            bookingId = recordId;
        } else if (type == Block__c.SObjectType) {
            Block__c tower = [SELECT Id, Name, Project__c, Project__r.Name FROM Block__c WHERE Id = :recordId LIMIT 1];
            towerId = tower.Id;
            towerName = tower.Name;
            projectId = tower.Project__c;
            projectName = tower.Project__r == null ? null : tower.Project__r.Name;
        }

        if (bookingId != null) {
            Booking__c b = [
                SELECT Project__c, Project__r.Name, First_Applicant_Name__c,
                       Plot__r.Name, Plot__r.Block1__c, Plot__r.Block1__r.Name
                FROM Booking__c WHERE Id = :bookingId LIMIT 1
            ];
            projectId = b.Project__c;
            projectName = b.Project__r == null ? null : b.Project__r.Name;
            unitName = b.Plot__r == null ? null : b.Plot__r.Name;
            customerName = b.First_Applicant_Name__c;
            if (b.Plot__r != null) {
                towerId = b.Plot__r.Block1__c;
                towerName = b.Plot__r.Block1__r == null ? null : b.Plot__r.Block1__r.Name;
            }
        }
        if (projectId == null) {
            errorMessage = 'The record is not linked to a project.';
            return;
        }

        List<Master_Payment_Schedule__c> masters = mastersFor(projectId, towerId);
        Map<Id, List<String>> images = imageUrlsFor(new Map<Id, Master_Payment_Schedule__c>(masters).keySet());

        Integer n = 1;
        for (Master_Payment_Schedule__c ms : masters) {
            MilestoneRow row = new MilestoneRow();
            row.serialNo = n++;
            row.milestone = String.isNotBlank(ms.Milestone_Name__c) ? ms.Milestone_Name__c
                : (String.isNotBlank(ms.Payment_Type__c) ? ms.Payment_Type__c : ms.Name);
            row.status = String.isBlank(ms.Status__c) ? 'Not Started' : ms.Status__c;
            Date done = ms.Completed_Date__c != null ? ms.Completed_Date__c : ms.Completion_Date__c;
            row.statusDate = formatDate(done);
            row.remarks = ms.Remarks__c;
            row.imageUrls = images.containsKey(ms.Id) ? images.get(ms.Id) : new List<String>();
            rows.add(row);
        }
    }

    /** The tower's active masters; the project-level ones when the project has none for the tower. */
    @TestVisible
    private static List<Master_Payment_Schedule__c> mastersFor(Id projectId, Id towerId) {
        List<Master_Payment_Schedule__c> masters = new List<Master_Payment_Schedule__c>();
        if (towerId != null) {
            masters = [
                SELECT Id, Name, Milestone_Name__c, Payment_Type__c, Sequence__c, Status__c,
                       Completed_Date__c, Completion_Date__c, Remarks__c
                FROM Master_Payment_Schedule__c
                WHERE Project__c = :projectId AND Tower__c = :towerId AND Is_Active__c = true
                ORDER BY Sequence__c ASC NULLS LAST, Name ASC
            ];
        }
        if (masters.isEmpty()) {
            masters = [
                SELECT Id, Name, Milestone_Name__c, Payment_Type__c, Sequence__c, Status__c,
                       Completed_Date__c, Completion_Date__c, Remarks__c
                FROM Master_Payment_Schedule__c
                WHERE Project__c = :projectId AND Tower__c = null AND Is_Active__c = true
                ORDER BY Sequence__c ASC NULLS LAST, Name ASC
            ];
        }
        return masters;
    }

    /** Master id -> download URLs of its latest image files (newest first, at most 3). */
    @TestVisible
    private static Map<Id, List<String>> imageUrlsFor(Set<Id> masterIds) {
        Map<Id, List<String>> result = new Map<Id, List<String>>();
        if (masterIds == null || masterIds.isEmpty()) return result;
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId, ContentDocument.LatestPublishedVersionId, ContentDocument.FileType
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :masterIds
            ORDER BY ContentDocument.CreatedDate DESC
        ]) {
            String fileType = link.ContentDocument.FileType == null ? '' : link.ContentDocument.FileType.toUpperCase();
            if (!IMAGE_TYPES.contains(fileType)) continue;
            if (!result.containsKey(link.LinkedEntityId)) result.put(link.LinkedEntityId, new List<String>());
            List<String> urls = result.get(link.LinkedEntityId);
            if (urls.size() < MAX_IMAGES_PER_MILESTONE) {
                urls.add('/sfc/servlet.shepherd/version/download/' + link.ContentDocument.LatestPublishedVersionId);
            }
        }
        return result;
    }

    /** Number of image files on a Master Payment Schedule (Bulk Raise Demand upload prompt). */
    @AuraEnabled
    public static Integer getMilestoneImageCount(Id masterId) {
        if (masterId == null) return 0;
        Integer count = 0;
        for (ContentDocumentLink link : [
            SELECT ContentDocument.FileType FROM ContentDocumentLink WHERE LinkedEntityId = :masterId
        ]) {
            String fileType = link.ContentDocument.FileType == null ? '' : link.ContentDocument.FileType.toUpperCase();
            if (IMAGE_TYPES.contains(fileType)) count++;
        }
        return count;
    }

    private static String formatDate(Date value) {
        return value == null ? '' : DateTime.newInstance(value.year(), value.month(), value.day()).format('dd-MM-yyyy');
    }
}