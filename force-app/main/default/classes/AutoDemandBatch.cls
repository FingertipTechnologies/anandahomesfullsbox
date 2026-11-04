/**
 * @description Batchable Apex that automatically raises demands for Payment Schedules
 *              where Auto_Demand_Date__c equals today. Follows the same demand creation
 *              process as BulkDemandController.createBulkDemands():
 *              1. Creates separate Flat and GST Demands__c records per booking
 *              2. Updates Payment_Schedule__c (Demand_Raised__c = true, Demand_Date__c = today)
 *              3. Populates reminder dates via DemandReminderService
 *              4. Auto-applies credit notes via CreditNoteApplicationService
 *
 *              Grace period is resolved from:
 *              1. Post_Sales_Config_Master__c.Grace_Period_Days__c (global config)
 *              2. PostSalesConstants.DEFAULT_GRACE_PERIOD_DAYS (fallback = 15)
 *
 * @author System
 * @date 2026-03-31
 */
public with sharing class AutoDemandBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final Set<String> SPLIT_FUNDING_TYPES = new Set<String>{
        'Loan', 'Bank Loan', 'NBFC Loan', 'Mixed Funding', 'Prorata', 'Partial'
    };
    private Date demandDate;
    private Integer totalDemandsCreated = 0;
    private Integer totalSchedulesProcessed = 0;
    private List<String> errors = new List<String>();

    /**
     * @description Constructor using today's date
     */
    public AutoDemandBatch() {
        this.demandDate = Date.today();
    }

    /**
     * @description Constructor with explicit date (useful for testing)
     * @param demandDate The date to check Auto_Demand_Date__c against
     */
    public AutoDemandBatch(Date demandDate) {
        this.demandDate = demandDate != null ? demandDate : Date.today();
    }

    /**
     * @description Queries Payment Schedules where Auto_Demand_Date__c matches today,
     *              demand has not been raised yet, and there is a pending amount.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Booking__c, Booking__r.Project__c, Booking__r.Name,
                   Booking__r.Funding_Type__c,
                   Booking__r.Project__r.Legacy_Split_Demand_Receipt__c,
                   Pending_Amount__c, Payment_Schedule_Amount_Pending__c,
                   GST_Amount_Pending__c, TDS_Amount_Pending__c,
                   Interest_Pending__c, Milestone_Name__c, Sequence__c
            FROM Payment_Schedule__c
            WHERE Auto_Demand_Date__c = :demandDate
            AND Demand_Raised__c = false
            AND Pending_Amount__c > 0
            AND (
                Booking__r.Project__r.Legacy_Split_Demand_Receipt__c = false
                OR Booking__r.Project__r.Legacy_Split_Demand_Receipt__c = null
                OR Booking__r.Funding_Type__c = null
                OR Booking__r.Funding_Type__c NOT IN :SPLIT_FUNDING_TYPES
            )
            AND Status__c NOT IN :PostSalesConstants.SCHEDULE_CLOSED_STATUSES
        ]);
    }

    /**
     * @description Processes each batch of Payment Schedules by creating demands
     *              following the same process as BulkDemandController.
     */
    public void execute(Database.BatchableContext bc, List<Payment_Schedule__c> scope) {
        if (scope.isEmpty()) return;

        Savepoint sp = Database.setSavepoint();

        try {
            // Resolve grace period from config hierarchy
            Integer graceDays = resolveGracePeriod();
            Date dueDate = demandDate.addDays(graceDays);

            // Group schedules by booking for demand creation
            Map<Id, List<Payment_Schedule__c>> schedulesByBooking = new Map<Id, List<Payment_Schedule__c>>();
            for (Payment_Schedule__c ps : scope) {
                if (!schedulesByBooking.containsKey(ps.Booking__c)) {
                    schedulesByBooking.put(ps.Booking__c, new List<Payment_Schedule__c>());
                }
                schedulesByBooking.get(ps.Booking__c).add(ps);
            }
            Map<Id, Decimal> remainingWaivers =
                InterestWaiverService.getRemainingWaivers(schedulesByBooking.keySet(), true);

            // Legacy projects keep separate component demands; other projects demand Flat + GST together.
            List<Demands__c> demandsToInsert = new List<Demands__c>();
            Map<Integer, Id> indexToBookingId = new Map<Integer, Id>();
            Map<Integer, List<Id>> indexToScheduleIds = new Map<Integer, List<Id>>();
            Map<Integer, String> indexToComponent = new Map<Integer, String>();
            Integer idx = 0;

            for (Id bookingId : schedulesByBooking.keySet()) {
                List<Payment_Schedule__c> schedules = schedulesByBooking.get(bookingId);

                Decimal baseAmount = 0;
                Decimal gstAmount = 0;
                Decimal tdsAmount = 0;
                Decimal interestAmount = 0;
                List<Id> scheduleIds = new List<Id>();
                Id latestScheduleId;
                Decimal latestSequence;

                for (Payment_Schedule__c ps : schedules) {
                    baseAmount += ps.Payment_Schedule_Amount_Pending__c != null ? ps.Payment_Schedule_Amount_Pending__c : 0;
                    gstAmount += ps.GST_Amount_Pending__c != null ? ps.GST_Amount_Pending__c : 0;
                    tdsAmount += ps.TDS_Amount_Pending__c != null ? ps.TDS_Amount_Pending__c : 0;
                    interestAmount += ps.Interest_Pending__c != null ? ps.Interest_Pending__c : 0;
                    scheduleIds.add(ps.Id);
                    if (ps.Sequence__c != null && (latestSequence == null || ps.Sequence__c > latestSequence)) {
                        latestSequence = ps.Sequence__c;
                        latestScheduleId = ps.Id;
                    }
                }

                Boolean legacyMode = schedules[0].Booking__r.Project__r.Legacy_Split_Demand_Receipt__c == true;
                if (legacyMode && baseAmount > 0) {
                    Decimal waiverAmount = InterestWaiverService.getWaiverAmount(
                        interestAmount,
                        remainingWaivers.get(bookingId)
                    );
                    remainingWaivers.put(
                        bookingId,
                        (remainingWaivers.get(bookingId) == null ? 0 : remainingWaivers.get(bookingId))
                            - waiverAmount
                    );
                    addComponentDemand(
                        demandsToInsert, indexToBookingId, indexToScheduleIds, indexToComponent,
                        idx++, bookingId, scheduleIds, latestScheduleId, DemandComponentService.FLAT,
                        baseAmount, tdsAmount, interestAmount - waiverAmount, waiverAmount, dueDate, graceDays
                    );
                }
                if (legacyMode && gstAmount > 0) {
                    addComponentDemand(
                        demandsToInsert, indexToBookingId, indexToScheduleIds, indexToComponent,
                        idx++, bookingId, scheduleIds, latestScheduleId, DemandComponentService.GST,
                        gstAmount, 0, 0, 0, dueDate, graceDays
                    );
                } else if (!legacyMode && baseAmount + gstAmount + tdsAmount > 0) {
                    Decimal waiverAmount = InterestWaiverService.getWaiverAmount(
                        interestAmount,
                        remainingWaivers.get(bookingId)
                    );
                    remainingWaivers.put(
                        bookingId,
                        (remainingWaivers.get(bookingId) == null ? 0 : remainingWaivers.get(bookingId))
                            - waiverAmount
                    );
                    Demands__c combinedDemand = new Demands__c(
                        Booking__c = bookingId,
                        Payment_Schedule__c = latestScheduleId,
                        Demand_Amount__c = baseAmount + gstAmount + tdsAmount,
                        Pending_Amount__c = baseAmount + gstAmount + tdsAmount,
                        Base_Amount__c = baseAmount,
                        Flat_Amount__c = baseAmount,
                        GST_Amount__c = gstAmount,
                        TDS_Amount__c = tdsAmount,
                        Interest_Amount__c = interestAmount - waiverAmount,
                        Interest_Waived_Off_Amount__c = waiverAmount,
                        Demand_Component__c = DemandComponentService.FLAT_AND_GST,
                        Demand_Audience__c = 'Customer',
                        Status__c = PostSalesConstants.DEMAND_STATUS_RAISED,
                        Demand_Type__c = 'Individual Demand',
                        Demand_Date__c = demandDate,
                        Due_Date__c = dueDate,
                        Grace_Period_Days__c = graceDays
                    );
                    demandsToInsert.add(combinedDemand);
                    indexToBookingId.put(idx, bookingId);
                    indexToScheduleIds.put(idx, scheduleIds);
                    indexToComponent.put(idx, DemandComponentService.FLAT_AND_GST);
                    idx++;
                }
            }

            if (demandsToInsert.isEmpty()) return;
            // Insert demands
            Database.SaveResult[] insertResults = Database.insert(demandsToInsert, false);

            // Process results and update payment schedules
            Map<Id, Payment_Schedule__c> schedulesToUpdate = new Map<Id, Payment_Schedule__c>();
            List<Id> successfulDemandIds = new List<Id>();
            List<Demands__c> successfulDemands = new List<Demands__c>();

            for (Integer i = 0; i < insertResults.size(); i++) {
                Id bookingId = indexToBookingId.get(i);

                if (insertResults[i].isSuccess()) {
                    totalDemandsCreated++;
                    successfulDemandIds.add(insertResults[i].getId());
                    successfulDemands.add(demandsToInsert[i]);

                    List<Id> scheduleIds = indexToScheduleIds.get(i);
                    if (scheduleIds != null) {
                        for (Id schedId : scheduleIds) {
                            Payment_Schedule__c ps = schedulesToUpdate.containsKey(schedId)
                                ? schedulesToUpdate.get(schedId)
                                : new Payment_Schedule__c(Id = schedId);
                            ps.Demand_Date__c = demandDate;
                            DemandComponentService.markRaised(ps, indexToComponent.get(i), false);
                            schedulesToUpdate.put(schedId, ps);
                        }
                    }
                } else {
                    errors.add('Booking ' + bookingId + ': ' + insertResults[i].getErrors()[0].getMessage());
                }
            }

            // Update payment schedules
            if (!schedulesToUpdate.isEmpty()) {
                Database.update(schedulesToUpdate.values(), false);
                totalSchedulesProcessed += schedulesToUpdate.size();
            }

            // Populate reminder dates on successfully created demands
            if (!successfulDemands.isEmpty()) {
                DemandReminderService.populateReminderDates(successfulDemands);
                update successfulDemands;
            }

            // Auto-apply credit notes
            if (!successfulDemandIds.isEmpty()) {
                CreditNoteApplicationService.applyCredits(successfulDemandIds);
            }

        } catch (Exception e) {
            Database.rollback(sp);
            errors.add('Batch execute error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    private void addComponentDemand(
        List<Demands__c> demandsToInsert,
        Map<Integer, Id> indexToBookingId,
        Map<Integer, List<Id>> indexToScheduleIds,
        Map<Integer, String> indexToComponent,
        Integer index,
        Id bookingId,
        List<Id> scheduleIds,
        Id latestScheduleId,
        String component,
        Decimal amount,
        Decimal tdsAmount,
        Decimal interestAmount,
        Decimal interestWaivedOffAmount,
        Date dueDate,
        Integer graceDays
    ) {
        Boolean isFlat = component == DemandComponentService.FLAT;
        Decimal demandAmount = amount + tdsAmount;
        demandsToInsert.add(new Demands__c(
            Booking__c = bookingId,
            Payment_Schedule__c = latestScheduleId,
            Demand_Amount__c = demandAmount,
            Pending_Amount__c = demandAmount,
            Base_Amount__c = isFlat ? amount : 0,
            Flat_Amount__c = isFlat ? amount : 0,
            GST_Amount__c = isFlat ? 0 : amount,
            TDS_Amount__c = tdsAmount,
            Interest_Amount__c = isFlat ? interestAmount : 0,
            Interest_Waived_Off_Amount__c = isFlat ? interestWaivedOffAmount : 0,
            Demand_Component__c = component,
            Demand_Audience__c = 'Customer',
            Status__c = PostSalesConstants.DEMAND_STATUS_RAISED,
            // Auto Demand is inactive on the restricted picklist; this is booking-scoped.
            Demand_Type__c = 'Individual Demand',
            Demand_Date__c = demandDate,
            Due_Date__c = dueDate,
            Grace_Period_Days__c = graceDays
        ));
        indexToBookingId.put(index, bookingId);
        indexToScheduleIds.put(index, scheduleIds);
        indexToComponent.put(index, component);
    }

    /**
     * @description Logs the batch execution summary.
     */
    public void finish(Database.BatchableContext bc) {
        String summary = 'AutoDemandBatch completed.\n' +
            'Demand Date: ' + String.valueOf(demandDate) + '\n' +
            'Demands Created: ' + totalDemandsCreated + '\n' +
            'Schedules Processed: ' + totalSchedulesProcessed;

        if (!errors.isEmpty()) {
            summary += '\nErrors (' + errors.size() + '):\n' + String.join(errors, '\n');
        }

        System.debug(summary);
    }

    // ==================== PRIVATE HELPERS ====================

    private Integer resolveGracePeriod() {
        List<Post_Sales_Config_Master__c> masterConfigs = [
            SELECT Grace_Period_Days__c
            FROM Post_Sales_Config_Master__c
            WHERE Is_Active__c = true
            LIMIT 1
        ];
        if (!masterConfigs.isEmpty() && masterConfigs[0].Grace_Period_Days__c != null) {
            return Integer.valueOf(masterConfigs[0].Grace_Period_Days__c);
        }
        return PostSalesConstants.DEFAULT_GRACE_PERIOD_DAYS;
    }

    // ==================== RESULT GETTERS (for testing) ====================

    public Integer getTotalDemandsCreated() { return totalDemandsCreated; }
    public Integer getTotalSchedulesProcessed() { return totalSchedulesProcessed; }
    public List<String> getErrors() { return errors; }
}