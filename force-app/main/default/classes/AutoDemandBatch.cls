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

    private static final Set<String> CUSTOMER_AUTO_DEMAND_FUNDING_TYPES = new Set<String>{
        'Prorata', 'Partial'
    };

    private class CustomerReceiptTotals {
        Decimal flatAmount = 0;
        Decimal gstAmount = 0;
        Decimal tdsAmount = 0;
    }

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
     * @description Queries due Payment Schedules with a pending amount. Legacy Prorata
     *              and Partial schedules remain eligible until both Customer components
     *              are raised, even if a Bank demand raised the general schedule flag.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Booking__c, Booking__r.Project__c, Booking__r.Name,
                   Booking__r.Funding_Type__c,
                   Booking__r.Project__r.Legacy_Split_Demand_Receipt__c,
                   Pending_Amount__c, Payment_Schedule_Amount_Pending__c, Due_Date__c,
                   GST_Amount_Pending__c, TDS_Amount_Pending__c,
                   Interest_Pending__c, Milestone_Name__c, Sequence__c,
                   Bank_Flat_Amount__c, Bank_GST_Amount__c,
                   Customer_Flat_Prorata__c, Customer_GST_Prorata__c,
                   Bank_Demand_Raised__c, Customer_Demand_Raised__c,
                   Bank_Flat_Demand_Raised__c, Bank_GST_Demand_Raised__c,
                   Customer_Flat_Demand_Raised__c, Customer_GST_Demand_Raised__c
            FROM Payment_Schedule__c
            WHERE Auto_Demand_Date__c = :demandDate
            AND Pending_Amount__c > 0
            AND (
                Demand_Raised__c = false
                OR (
                    Booking__r.Project__r.Legacy_Split_Demand_Receipt__c = true
                    AND Booking__r.Funding_Type__c IN :CUSTOMER_AUTO_DEMAND_FUNDING_TYPES
                    AND (
                        Customer_Flat_Demand_Raised__c != true
                        OR Customer_GST_Demand_Raised__c != true
                    )
                )
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
            Post_Sales_Config_Master__c config = resolveActiveConfig();
            Integer graceDays = config != null && config.Grace_Period_Days__c != null
                ? Integer.valueOf(config.Grace_Period_Days__c)
                : PostSalesConstants.DEFAULT_GRACE_PERIOD_DAYS;
            Boolean includeInterest = config == null || config.Include_Interest__c == true;
            Date dueDate = demandDate.addDays(graceDays);

            // Group schedules by booking for demand creation
            Map<Id, List<Payment_Schedule__c>> schedulesByBooking = new Map<Id, List<Payment_Schedule__c>>();
            Map<Id, Payment_Schedule__c> scopeScheduleById = new Map<Id, Payment_Schedule__c>(scope);
            Map<Id, CustomerReceiptTotals> customerPaidBySchedule =
                new Map<Id, CustomerReceiptTotals>();
            Set<Id> scopeScheduleIds = new Set<Id>();
            for (Payment_Schedule__c ps : scope) {
                scopeScheduleIds.add(ps.Id);
                if (!schedulesByBooking.containsKey(ps.Booking__c)) {
                    schedulesByBooking.put(ps.Booking__c, new List<Payment_Schedule__c>());
                }
                schedulesByBooking.get(ps.Booking__c).add(ps);
            }
            Set<Id> scopeBookingIds = schedulesByBooking.keySet();
            // Previous Dues carries only unpaid Customer demands from earlier schedules, not
            // schedule-level balances that may include Bank or not-yet-demanded components.
            Map<Id, Decimal> previousDuesByBooking = new Map<Id, Decimal>();
            for (AggregateResult result : [
                SELECT Booking__c bookingId, SUM(Pending_Amount__c) pendingAmount
                FROM Demands__c
                WHERE Booking__c IN :scopeBookingIds
                AND Payment_Schedule__c != null
                AND Payment_Schedule__c NOT IN :scopeScheduleIds
                AND Demand_Audience__c = 'Customer'
                AND Status__c IN :PostSalesConstants.DEMAND_ALL_OPEN_STATUSES
                AND Pending_Amount__c > 0
                GROUP BY Booking__c
            ]) {
                previousDuesByBooking.put(
                    (Id) result.get('bookingId'),
                    (Decimal) result.get('pendingAmount')
                );
            }
            for (AggregateResult result : [
                SELECT Payment_Schedule__c scheduleId,
                       SUM(Base_Amount__c) flatAmount,
                       SUM(GST_Amount__c) gstAmount,
                       SUM(TDS_Amount__c) tdsAmount
                FROM Receipt_Line_Item__c
                WHERE Payment_Schedule__c IN :scopeScheduleIds
                AND Receipt__r.Payment_From__c = 'Customer'
                AND Receipt__r.Approval_Status__c != 'Rejected'
                GROUP BY Payment_Schedule__c
            ]) {
                CustomerReceiptTotals totals = new CustomerReceiptTotals();
                totals.flatAmount = result.get('flatAmount') == null
                    ? 0
                    : (Decimal) result.get('flatAmount');
                totals.gstAmount = result.get('gstAmount') == null
                    ? 0
                    : (Decimal) result.get('gstAmount');
                totals.tdsAmount = result.get('tdsAmount') == null
                    ? 0
                    : (Decimal) result.get('tdsAmount');
                customerPaidBySchedule.put((Id) result.get('scheduleId'), totals);
            }
            Map<Id, Decimal> remainingWaivers =
                InterestWaiverService.getRemainingWaivers(schedulesByBooking.keySet(), true);

            // Legacy projects keep separate component demands; other projects demand Flat + GST together.
            List<Demands__c> demandsToInsert = new List<Demands__c>();
            Map<Integer, Id> indexToBookingId = new Map<Integer, Id>();
            Map<Integer, List<Id>> indexToScheduleIds = new Map<Integer, List<Id>>();
            Map<Integer, String> indexToComponent = new Map<Integer, String>();
            Map<Id, Decimal> customerFlatPendingBySchedule = new Map<Id, Decimal>();
            Map<Id, Decimal> customerGstPendingBySchedule = new Map<Id, Decimal>();
            Map<Id, Decimal> customerTdsPendingBySchedule = new Map<Id, Decimal>();
            Map<Id, Boolean> customerProrataByBooking = new Map<Id, Boolean>();
            Integer idx = 0;

            for (Id bookingId : schedulesByBooking.keySet()) {
                List<Payment_Schedule__c> schedules = schedulesByBooking.get(bookingId);
                Decimal previousDues = previousDuesByBooking.containsKey(bookingId)
                    ? previousDuesByBooking.get(bookingId)
                    : 0;

                Decimal baseAmount = 0;
                Decimal gstAmount = 0;
                Decimal tdsAmount = 0;
                Decimal interestAmount = 0;
                List<Id> scheduleIds = new List<Id>();
                List<Id> flatScheduleIds = new List<Id>();
                List<Id> gstScheduleIds = new List<Id>();
                Id latestScheduleId;
                Decimal latestSequence;
                Boolean legacyMode = schedules[0].Booking__r.Project__r.Legacy_Split_Demand_Receipt__c == true;
                Boolean customerProrataMode = legacyMode
                    && CUSTOMER_AUTO_DEMAND_FUNDING_TYPES.contains(schedules[0].Booking__r.Funding_Type__c);
                customerProrataByBooking.put(bookingId, customerProrataMode);

                for (Payment_Schedule__c ps : schedules) {
                    Decimal scheduleFlat;
                    Decimal scheduleGst;
                    Decimal scheduleTds;
                    Boolean includeScheduleInterest = true;
                    if (customerProrataMode) {
                        CustomerReceiptTotals customerPaid = customerPaidBySchedule.get(ps.Id);
                        Decimal customerFlatShare = ps.Customer_Flat_Prorata__c == null
                            ? 0
                            : ps.Customer_Flat_Prorata__c;
                        Decimal customerGstShare = ps.Customer_GST_Prorata__c == null
                            ? 0
                            : ps.Customer_GST_Prorata__c;
                        Boolean customerFlatAlreadyRaised = DemandComponentService.isComponentRaised(
                            ps,
                            DemandComponentService.FLAT,
                            false
                        );
                        Boolean customerGstAlreadyRaised = DemandComponentService.isComponentRaised(
                            ps,
                            DemandComponentService.GST,
                            false
                        );
                        Boolean bankFlatAlreadyRaised = DemandComponentService.isComponentRaised(
                            ps,
                            DemandComponentService.FLAT,
                            true
                        );
                        includeScheduleInterest = !customerFlatAlreadyRaised
                            && !bankFlatAlreadyRaised
                            && (ps.Bank_Flat_Amount__c == null || ps.Bank_Flat_Amount__c <= 0);
                        scheduleFlat = customerFlatAlreadyRaised
                            ? 0
                            : Math.max(
                                0,
                                customerFlatShare - (customerPaid == null ? 0 : customerPaid.flatAmount)
                            );
                        scheduleGst = customerGstAlreadyRaised
                            ? 0
                            : Math.max(
                                0,
                                customerGstShare - (customerPaid == null ? 0 : customerPaid.gstAmount)
                            );
                        Decimal customerTdsShare = (scheduleFlat * 0.01)
                            .setScale(2, System.RoundingMode.HALF_UP);
                        scheduleTds = customerFlatAlreadyRaised
                            ? 0
                            : Math.max(
                                0,
                                customerTdsShare - (customerPaid == null ? 0 : customerPaid.tdsAmount)
                            );
                        customerFlatPendingBySchedule.put(ps.Id, scheduleFlat);
                        customerGstPendingBySchedule.put(ps.Id, scheduleGst);
                        customerTdsPendingBySchedule.put(ps.Id, scheduleTds);
                    } else {
                        scheduleFlat = ps.Payment_Schedule_Amount_Pending__c == null
                            ? 0
                            : ps.Payment_Schedule_Amount_Pending__c;
                        scheduleGst = ps.GST_Amount_Pending__c == null
                            ? 0
                            : ps.GST_Amount_Pending__c;
                        scheduleTds = ps.TDS_Amount_Pending__c == null
                            ? 0
                            : ps.TDS_Amount_Pending__c;
                    }
                    baseAmount += scheduleFlat;
                    gstAmount += scheduleGst;
                    tdsAmount += scheduleTds;
                    Boolean hasDemandableAmount = legacyMode
                        ? scheduleFlat + scheduleTds > 0
                        : scheduleFlat + scheduleGst + scheduleTds > 0;
                    if (includeInterest && includeScheduleInterest && hasDemandableAmount) {
                        interestAmount += ps.Interest_Pending__c != null ? ps.Interest_Pending__c : 0;
                    }
                    scheduleIds.add(ps.Id);
                    if (scheduleFlat + scheduleTds > 0) flatScheduleIds.add(ps.Id);
                    if (scheduleGst > 0) gstScheduleIds.add(ps.Id);
                    if (ps.Sequence__c != null && (latestSequence == null || ps.Sequence__c > latestSequence)) {
                        latestSequence = ps.Sequence__c;
                        latestScheduleId = ps.Id;
                    }
                }

                if (legacyMode && baseAmount + tdsAmount > 0) {
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
                        idx++, bookingId,
                        customerProrataMode ? flatScheduleIds : scheduleIds,
                        latestScheduleId, DemandComponentService.FLAT,
                        baseAmount, tdsAmount, interestAmount - waiverAmount, waiverAmount,
                        previousDues, dueDate, graceDays
                    );
                }
                if (legacyMode && gstAmount > 0) {
                    addComponentDemand(
                        demandsToInsert, indexToBookingId, indexToScheduleIds, indexToComponent,
                        idx++, bookingId,
                        customerProrataMode ? gstScheduleIds : scheduleIds,
                        latestScheduleId, DemandComponentService.GST,
                        gstAmount, 0, 0, 0, 0, dueDate, graceDays
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
                        Previous_Dues__c = previousDues,
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
            for (Integer i = 0; i < demandsToInsert.size(); i++) {
                String demandComponent = indexToComponent.get(i);
                List<Demand_Line__c> demandLines = new List<Demand_Line__c>();
                List<Id> scheduleIds = indexToScheduleIds.get(i);
                if (scheduleIds != null) {
                    for (Id schedId : scheduleIds) {
                        Payment_Schedule__c schedule = scopeScheduleById.get(schedId);
                        if (schedule == null) continue;

                        Boolean customerProrataMode = customerProrataByBooking.get(
                            schedule.Booking__c
                        ) == true;
                        Decimal lineFlatAmount = customerProrataMode
                            ? customerFlatPendingBySchedule.get(schedId)
                            : schedule.Payment_Schedule_Amount_Pending__c;
                        Decimal lineGstAmount = customerProrataMode
                            ? customerGstPendingBySchedule.get(schedId)
                            : schedule.GST_Amount_Pending__c;
                        Decimal lineTdsAmount = customerProrataMode
                            ? customerTdsPendingBySchedule.get(schedId)
                            : schedule.TDS_Amount_Pending__c;
                        lineFlatAmount = lineFlatAmount == null ? 0 : lineFlatAmount;
                        lineGstAmount = lineGstAmount == null ? 0 : lineGstAmount;
                        lineTdsAmount = lineTdsAmount == null ? 0 : lineTdsAmount;
                        if (demandComponent == DemandComponentService.FLAT) {
                            lineGstAmount = 0;
                        } else if (demandComponent == DemandComponentService.GST) {
                            lineFlatAmount = 0;
                            lineTdsAmount = 0;
                        }
                        if (lineFlatAmount + lineGstAmount + lineTdsAmount > 0) {
                            demandLines.add(DemandLineService.createFromSchedule(
                                schedule,
                                demandComponent,
                                lineFlatAmount,
                                lineGstAmount,
                                lineTdsAmount,
                                0
                            ));
                        }
                    }
                }
                DemandLineService.stageForInsert(demandsToInsert[i], demandLines);
            }
            Database.SaveResult[] insertResults = Database.insert(demandsToInsert, false);
            DemandLineService.clearStagedLines();

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
                            if (scopeScheduleById.get(schedId).Due_Date__c == null) {
                                ps.Due_Date__c = demandsToInsert[i].Due_Date__c;
                            }
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
        Decimal previousDues,
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
            Previous_Dues__c = isFlat ? previousDues : 0,
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

    private Post_Sales_Config_Master__c resolveActiveConfig() {
        List<Post_Sales_Config_Master__c> masterConfigs = [
            SELECT Grace_Period_Days__c, Include_Interest__c
            FROM Post_Sales_Config_Master__c
            WHERE Is_Active__c = true
            LIMIT 1
        ];
        return masterConfigs.isEmpty() ? null : masterConfigs[0];
    }

    // ==================== RESULT GETTERS (for testing) ====================

    public Integer getTotalDemandsCreated() { return totalDemandsCreated; }
    public Integer getTotalSchedulesProcessed() { return totalSchedulesProcessed; }
    public List<String> getErrors() { return errors; }
}