// Last Modified: 2026-07-02
public class HomeNotificationController {
    
@auraEnabled
    public static list<Follow_Up__c> getFollowUpInformation()
    {
        System.debug(userinfo.getFirstName()+'===>'+userinfo.getUserId());
        List<Follow_Up__c> followUpDetails=[Select Id,Name,Scheduled_Date__c,Comments__c,Status__c,Owner.Name,CLead__c,CLead__r.Name__c,CLead__r.Lead_Status__c,CLead__r.Last_Comment__c,CLead__r.Id from Follow_Up__c  where Status__c='Scheduled' AND Scheduled_Date__c=today AND OwnerId =:userInfo.getUserId() order by Scheduled_Date__c  ];
        System.debug(followUpDetails);
        return followUpDetails;
    }

@auraEnabled
    public static list<Follow_Up__c> getPendingFollowUpInformation()
    {
        List<Follow_Up__c> followUpDetails=[Select Id,Name,Scheduled_Date__c,Status__c,Comments__c,Owner.Name,CLead__c,CLead__r.Last_Comment__c,CLead__r.Name__c,CLead__r.Lead_Status__c,CLead__r.Id from Follow_Up__c  where (Status__c='Scheduled' ) AND Scheduled_Date__c=yesterday AND OwnerId =:userInfo.getUserId() order by Scheduled_Date__c  ];
       System.debug(followUpDetails);
        return followUpDetails;
    }
    
    
    @auraEnabled
    public static list<Site_Visit__c> getPendingSiteVistInformation()
    {
        System.debug('Sv Details');
        List<Site_Visit__c> svDetails=[Select Id,Name,CLead__c,Date__c,Status__c,Feedback__c,Owner.Name,CLead__r.Last_Comment__c,CLead__r.Name__c,CLead__r.Lead_Status__c,CLead__r.Id,Canceled_Reason__c,CLead__r.Requirement_Description__c from Site_Visit__c  where (Status__c='Scheduled' OR Status__c='Reschedule' OR Status__c='Missed' ) AND Date__c=yesterday AND OwnerId =:userInfo.getUserId() order by Date__c ];
        return svDetails;
    }
    
    @auraEnabled
    public static list<Site_Visit__c> getSiteVistInformation()
    {
        System.debug('Sv Details');
        List<Site_Visit__c> svDetails=[Select Id,Name,CLead__c,Date__c,Status__c,Feedback__c,Owner.Name,CLead__r.Name__c,CLead__r.Lead_Status__c,CLead__r.Last_Comment__c,CLead__r.Id,Canceled_Reason__c,CLead__r.Requirement_Description__c from Site_Visit__c  where (Status__c='Scheduled' OR Status__c='Reschedule' ) AND Date__c=today AND OwnerId =:userInfo.getUserId() order by Date__c ];
        return svDetails;
    }
    

    // The modal captures Status and, for Completed, the Completed Date
    @auraEnabled
    public static String updateFollowupDetails(String recID, String FLStatus, Datetime completedDate) {
        List<Follow_Up__c> svData = [
            SELECT Id, Status__c, Comments__c, Completed_Date__c, Call_Duration_In_Mins__c
            FROM Follow_Up__c
            WHERE Id = :recID
            LIMIT 1
        ];

        if (svData.isEmpty()) {
            return 'Record not found';
        }

        svData[0].Status__c = FLStatus;

        // Follow_up__c has three Completed-gated validation rules:
        //   Follow_ups_Completed_Date    -> requires Completed_Date__c
        //   Follow_Ups_Remarks_Mandatory -> requires Comments__c
        //   Call_Duration_Mandatory      -> requires Call_Duration_In_Mins__c
        // The modal only captures Status now, so default the other fields.
        // Existing values are preserved.
        if (FLStatus == 'Completed') {
            // Use the date entered by the user; fall back to now if none was passed
            svData[0].Completed_Date__c = (completedDate != null) ? completedDate : System.now();
            if (svData[0].Call_Duration_In_Mins__c == null) {
                svData[0].Call_Duration_In_Mins__c = 0;
            }
            if (String.isBlank(svData[0].Comments__c)) {
                svData[0].Comments__c = 'Completed';
            }
        }

        try {
            update svData[0];
            return 'Updated';
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }
    
    @AuraEnabled
    public static datawrapper todaysLeads(Integer pageSize, Integer pageNumber) {
        datawrapper dw = new datawrapper();
        Integer offset = (pageNumber - 1) * pageSize;
        
        String userProfile = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId()].Profile.Name;
        
        List<Lead__c> lstld;
        Integer leadCount;

        if (userProfile == 'Pre-Sales Executive') {
            lstld = [SELECT Id, Name, Name__c, Projects__c, Lead_Status__c, Lead_Type__c,
                     Allocated_Project__c, Secondary_Email__c, Phone__c, Secondary_Phone__c,
                     CreatedDate
                     FROM Lead__c
                     WHERE CreatedDate = TODAY AND OwnerId = :UserInfo.getUserId()
                     ORDER BY CreatedDate DESC
                     LIMIT :pageSize OFFSET :offset];

            leadCount = [SELECT COUNT() FROM Lead__c WHERE CreatedDate = TODAY AND OwnerId = :UserInfo.getUserId() ];

        } else if (userProfile == 'Sales') {
            lstld = [SELECT Id, Name, Name__c, Projects__c, Lead_Status__c, Lead_Type__c, Lead_source__c,
                     Allocated_Project__c, Secondary_Email__c, Phone__c, Secondary_Phone__c,
                      CreatedDate
                     FROM Lead__c
                     WHERE Pushed_On__c = TODAY AND OwnerId = :UserInfo.getUserId()
                     ORDER BY Pushed_On__c DESC
                     LIMIT :pageSize OFFSET :offset];

            leadCount = [SELECT COUNT() FROM Lead__c WHERE Pushed_On__c = TODAY AND OwnerId = :UserInfo.getUserId() ];
        }else {
        // Default: show leads created today for any other profile
        lstld = [
            SELECT Id, Name, Name__c, Projects__c, Lead_Status__c, Lead_Type__c,
                   Allocated_Project__c, Secondary_Email__c, Phone__c, Secondary_Phone__c,
                   CreatedDate
            FROM Lead__c
            WHERE CreatedDate = TODAY AND OwnerId = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
            LIMIT :pageSize OFFSET :offset
        ];

        leadCount = [
            SELECT COUNT()
            FROM Lead__c
            WHERE CreatedDate = TODAY
        ];
    }
    
    dw.ldListtodays = lstld;
    dw.todaysldCount = leadCount;
    return dw;
}
    
    public class datawrapper{
        @AuraEnabled
        public Decimal todaysldCount {get; set;}
        @AuraEnabled
        public List<Lead__c> ldListtodays {get; set;}
    }
    
    // ---------------------------------------------------------------------
    // Lead's For The Day (period view)
    // Every lead the running user RECEIVED in the period, whatever its current
    // stage, status or source:
    //   - new leads        : CreatedDate
    //   - re-engaged leads : Last_Re_Engaged_Date__c
    //   - re-opened leads  : Last_Re_Opened_Date__c
    // "Yet to work" = still in New Enquiry / New Sales Enquiry; "Worked" = any other status.
    // period: today (default in the component) | yesterday | last7Days | thisWeek | lastWeek | thisMonth | lastMonth | custom
    // statusFilter: all | New Enquiry | New Sales Enquiry | worked | reEngaged | reOpened
    // ---------------------------------------------------------------------
    public static final Set<String> NEW_STATUSES = new Set<String>{ 'New Enquiry', 'New Sales Enquiry' };

    @AuraEnabled
    public static PeriodLeadsWrapper getLeadsForPeriod(String period, String startDate, String endDate,
                                                       String statusFilter, Integer pageSize, Integer pageNumber) {
        PeriodLeadsWrapper w = new PeriodLeadsWrapper();
        Date[] range = resolvePeriod(period, startDate, endDate);
        if (range == null) {
            w.error = 'Please enter a valid start date and end date.';
            return w;
        }
        w.startDate = range[0];
        w.endDate = range[1];
        if (pageSize == null || pageSize <= 0) pageSize = 10;
        if (pageNumber == null || pageNumber <= 0) pageNumber = 1;
        Integer offset = (pageNumber - 1) * pageSize;

        Datetime fromDt = Datetime.newInstance(range[0], Time.newInstance(0, 0, 0, 0));
        Datetime toDt = Datetime.newInstance(range[1].addDays(1), Time.newInstance(0, 0, 0, 0));
        Id me = UserInfo.getUserId();
        Set<String> newStatuses = NEW_STATUSES;

        String reEngagedClause = '(Last_Re_Engaged_Date__c >= :fromDt AND Last_Re_Engaged_Date__c < :toDt)';
        String reOpenedClause = '(Last_Re_Opened_Date__c >= :fromDt AND Last_Re_Opened_Date__c < :toDt)';
        String assignedClause = ' OwnerId = :me AND ((CreatedDate >= :fromDt AND CreatedDate < :toDt)'
                              + ' OR ' + reEngagedClause
                              + ' OR ' + reOpenedClause + ') ';

        // Re-engaged / re-opened in the period (a lead can be both, and is still counted once in the total)
        w.reEngaged = Database.countQuery('SELECT COUNT() FROM Lead__c WHERE OwnerId = :me AND ' + reEngagedClause);
        w.reOpened = Database.countQuery('SELECT COUNT() FROM Lead__c WHERE OwnerId = :me AND ' + reOpenedClause);

        // Counts by status for the whole period
        for (AggregateResult ar : Database.query('SELECT Lead_Status__c st, COUNT(Id) n FROM Lead__c WHERE' + assignedClause + 'GROUP BY Lead_Status__c')) {
            String st = (String) ar.get('st');
            Integer n = (Integer) ar.get('n');
            w.total += n;
            if (st == 'New Enquiry') { w.newEnquiry += n; w.pending += n; }
            else if (st == 'New Sales Enquiry') { w.newSalesEnquiry += n; w.pending += n; }
            else { w.worked += n; }
        }

        // Page of records for the selected chip
        String filterClause = '';
        if (statusFilter == 'New Enquiry' || statusFilter == 'New Sales Enquiry') {
            filterClause = ' AND Lead_Status__c = :statusFilter';
        } else if (statusFilter == 'worked') {
            filterClause = ' AND Lead_Status__c NOT IN :newStatuses';
        } else if (statusFilter == 'reEngaged') {
            filterClause = ' AND ' + reEngagedClause;
        } else if (statusFilter == 'reOpened') {
            filterClause = ' AND ' + reOpenedClause;
        }
        w.filteredTotal = Database.countQuery('SELECT COUNT() FROM Lead__c WHERE' + assignedClause + filterClause);
        // Latest re-engaged / re-opened first, then the newest leads
        w.records = Database.query(
            'SELECT Id, Name, Name__c, Allocated_Project__c, Phone__c, Lead_Status__c, Lead_Type__c, '
            + 'CreatedDate, Pushed_On__c, Status_Change_Date__c, Last_Re_Engaged_Date__c, Last_Re_Opened_Date__c '
            + 'FROM Lead__c WHERE' + assignedClause + filterClause
            + ' ORDER BY Last_Re_Engaged_Date__c DESC NULLS LAST, Last_Re_Opened_Date__c DESC NULLS LAST, CreatedDate DESC'
            + ' LIMIT :pageSize OFFSET :offset');
        return w;
    }

    // Returns {start, end} dates in the running user's time zone, or null when custom dates are invalid.
    public static Date[] resolvePeriod(String period, String startDate, String endDate) {
        Date today = Date.today();
        Date s; Date e;
        if (period == 'last7Days') { s = today.addDays(-6); e = today; } // today and the 6 days before
        else if (period == 'yesterday') { s = today.addDays(-1); e = s; }
        else if (period == 'thisWeek') { s = startOfWeek(today); e = s.addDays(6); }
        else if (period == 'lastWeek') { s = startOfWeek(today).addDays(-7); e = s.addDays(6); }
        else if (period == 'thisMonth') { s = today.toStartOfMonth(); e = s.addMonths(1).addDays(-1); }
        else if (period == 'lastMonth') { s = today.toStartOfMonth().addMonths(-1); e = today.toStartOfMonth().addDays(-1); }
        else if (period == 'custom') {
            if (String.isBlank(startDate) || String.isBlank(endDate)) return null;
            try { s = Date.valueOf(startDate); e = Date.valueOf(endDate); } catch (Exception ex) { return null; }
            if (e < s) { Date t = s; s = e; e = t; }
        }
        else { s = today; e = today; } // today (default)
        return new Date[]{ s, e };
    }

    // Monday-based week
    private static Date startOfWeek(Date d) {
        Integer daysSinceMonday = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(d), 7); // 1900-01-01 was a Monday
        return d.addDays(-daysSinceMonday);
    }

    public class PeriodLeadsWrapper {
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Integer pending = 0;
        @AuraEnabled public Integer worked = 0;
        @AuraEnabled public Integer newEnquiry = 0;
        @AuraEnabled public Integer newSalesEnquiry = 0;
        @AuraEnabled public Integer reEngaged = 0;
        @AuraEnabled public Integer reOpened = 0;
        @AuraEnabled public Integer filteredTotal = 0;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String error;
        @AuraEnabled public List<Lead__c> records = new List<Lead__c>();
    }

    @AuraEnabled
    public static String getUserName() {
        String userId = UserInfo.getUserId();
        User currentUser = [SELECT Name FROM User WHERE Id = :userId];
        return currentUser.Name;
    }

}