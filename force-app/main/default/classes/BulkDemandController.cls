public with sharing class BulkDemandController {

    // Funding types that carry a per-milestone Bank/Customer prorata split (BRD §8.1).
    private static final Set<String> SPLIT_FUNDING_TYPES = new Set<String>{
        'Loan', 'Bank Loan', 'NBFC Loan', 'Mixed Funding', 'Prorata', 'Partial'
    };

    // Only payment schedules whose own Status__c is Completed are eligible for a bulk demand.
    private static final String SCHEDULE_STATUS_COMPLETED = 'Completed';

    // ============ WRAPPER CLASSES ============

    public class ProjectContextWrapper {
        @AuraEnabled public Id projectId { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public String projectType { get; set; }
        @AuraEnabled public Boolean legacySplitDemandReceipt { get; set; }
        @AuraEnabled public Decimal interestRate { get; set; }
        @AuraEnabled public Decimal reminderDays { get; set; }
    }

    public class TowerWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
    }

    public class MasterMilestoneWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Decimal sequence { get; set; }
        @AuraEnabled public Decimal percentage { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String paymentType { get; set; }
        @AuraEnabled public Boolean isCompleted { get; set; }
        @AuraEnabled public Boolean demandAlreadyRaised { get; set; }
        @AuraEnabled public Decimal cumulativePercentage { get; set; }
    }

    public class BookingDemandWrapper {
        @AuraEnabled public Id bookingId { get; set; }
        @AuraEnabled public String bookingName { get; set; }
        @AuraEnabled public String unitName { get; set; }
        @AuraEnabled public String applicantName { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public Decimal totalPending { get; set; }
        @AuraEnabled public Decimal totalFlatAmount { get; set; }
        @AuraEnabled public Decimal totalGstAmount { get; set; }
        @AuraEnabled public Decimal totalTdsAmount { get; set; }
        @AuraEnabled public Decimal totalInterest { get; set; }
        @AuraEnabled public Decimal grossInterest { get; set; }
        @AuraEnabled public Decimal interestWaivedOff { get; set; }
        @AuraEnabled public Decimal netDemandAmount { get; set; }
        @AuraEnabled public String formattedPending { get; set; }
        @AuraEnabled public String formattedFlatAmount { get; set; }
        @AuraEnabled public String formattedGstAmount { get; set; }
        @AuraEnabled public String formattedTdsAmount { get; set; }
        @AuraEnabled public String formattedInterest { get; set; }
        @AuraEnabled public String formattedGrossInterest { get; set; }
        @AuraEnabled public String formattedInterestWaivedOff { get; set; }
        @AuraEnabled public String formattedNet { get; set; }
        @AuraEnabled public List<PaymentScheduleLineItem> scheduleItems { get; set; }
        @AuraEnabled public Boolean isSelected { get; set; }
        @AuraEnabled public Decimal currentMilestoneAmount { get; set; }
        @AuraEnabled public Decimal previousMilestonesAmount { get; set; }
        @AuraEnabled public String formattedCurrentAmount { get; set; }
        @AuraEnabled public String formattedPreviousAmount { get; set; }
        // What will actually be demanded now, split by source (mirrors the Bank/Customer split
        // logic in createBulkDemands, shown here up front so the table matches the outcome).
        @AuraEnabled public Decimal bankPayableAmount { get; set; }
        @AuraEnabled public Decimal customerPayableAmount { get; set; }
        @AuraEnabled public String formattedBankPayable { get; set; }
        @AuraEnabled public String formattedCustomerPayable { get; set; }
        // The schedule matching the milestone actually selected in Step 2 — this is what the
        // resulting Demand's Payment_Schedule__c lookup will be linked to.
        @AuraEnabled public Id currentMilestoneScheduleId { get; set; }
    }

    public class PaymentScheduleLineItem {
        @AuraEnabled public Id scheduleId { get; set; }
        @AuraEnabled public String scheduleName { get; set; }
        @AuraEnabled public String milestoneName { get; set; }
        @AuraEnabled public Decimal pendingAmount { get; set; }
        @AuraEnabled public Decimal basePending { get; set; }
        @AuraEnabled public Decimal gstPending { get; set; }
        @AuraEnabled public Decimal tdsAmount { get; set; }
        @AuraEnabled public Decimal interestAmount { get; set; }
        @AuraEnabled public Decimal sequence { get; set; }
        @AuraEnabled public String formattedPending { get; set; }
        @AuraEnabled public String formattedInterest { get; set; }
        @AuraEnabled public Boolean isSelected { get; set; }
        // True for the schedule matching the milestone selected in Step 2.
        @AuraEnabled public Boolean isCurrentMilestone { get; set; }
        // True when this schedule's amount is demanded from the Bank (a real prorata split
        // exists), false when it's demanded from the Customer.
        @AuraEnabled public Boolean isBankPayable { get; set; }
    }

    public class BulkDemandRequest {
        @AuraEnabled public Id projectId { get; set; }
        @AuraEnabled public Id towerId { get; set; }
        @AuraEnabled public Id masterPaymentScheduleId { get; set; }
        @AuraEnabled public String demandComponent { get; set; }
        @AuraEnabled public List<BookingDemandItem> bookings { get; set; }
        @AuraEnabled public Decimal gracePeriodDays { get; set; }
        @AuraEnabled public Decimal dueDateOffsetDays { get; set; }
        @AuraEnabled public Boolean includeInterest { get; set; }
        @AuraEnabled public Boolean includePreviousDues { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public String demandType { get; set; }
    }

    public class BookingDemandItem {
        @AuraEnabled public Id bookingId { get; set; }
        @AuraEnabled public Decimal demandAmount { get; set; }
        @AuraEnabled public Decimal interestAmount { get; set; }
        @AuraEnabled public Decimal previousDues { get; set; }
        @AuraEnabled public List<Id> scheduleIds { get; set; }
        // The schedule matching the milestone selected in Step 2 — takes priority over the
        // highest-sequence fallback when linking the resulting Demand's Payment_Schedule__c.
        @AuraEnabled public Id currentMilestoneScheduleId { get; set; }
    }

    public class BulkDemandResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Integer totalProcessed { get; set; }
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer failureCount { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public List<DemandResultItem> results { get; set; }
    }

    public class DemandResultItem {
        @AuraEnabled public Id bookingId { get; set; }
        @AuraEnabled public String bookingName { get; set; }
        @AuraEnabled public Id demandId { get; set; }
        @AuraEnabled public String demandName { get; set; }
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Boolean emailSent { get; set; }
    }

    // ============ READ METHODS ============

    @AuraEnabled(cacheable=true)
    public static ProjectContextWrapper getProjectContext(Id projectId) {
        List<Project__c> projects = [
            SELECT Id, Name, Project_Type__c, Interest_Rate__c, Reminder_Days__c,
                   Legacy_Split_Demand_Receipt__c
            FROM Project__c
            WHERE Id = :projectId
            LIMIT 1
        ];

        if (projects.isEmpty()) {
            throw new AuraHandledException('Project not found');
        }

        Project__c project = projects[0];
        ProjectContextWrapper wrapper = new ProjectContextWrapper();
        wrapper.projectId = project.Id;
        wrapper.projectName = project.Name;
        wrapper.projectType = project.Project_Type__c;
        wrapper.legacySplitDemandReceipt = project.Legacy_Split_Demand_Receipt__c == true;
        wrapper.interestRate = project.Interest_Rate__c;
        wrapper.reminderDays = project.Reminder_Days__c;
        return wrapper;
    }

    @AuraEnabled(cacheable=true)
    public static List<TowerWrapper> getProjectTowers(Id projectId) {
        if (projectId == null) {
            throw new AuraHandledException('Project is required to load towers.');
        }

        List<TowerWrapper> towers = new List<TowerWrapper>();
        for (Block__c tower : [
            SELECT Id, Name
            FROM Block__c
            WHERE Project__c = :projectId
            ORDER BY Name ASC
        ]) {
            TowerWrapper wrapper = new TowerWrapper();
            wrapper.id = tower.Id;
            wrapper.name = tower.Name;
            towers.add(wrapper);
        }
        return towers;
    }

    @AuraEnabled(cacheable=true)
    public static List<MasterMilestoneWrapper> getCompletedMilestones(Id projectId, Id towerId) {
        List<MasterMilestoneWrapper> wrappers = new List<MasterMilestoneWrapper>();
        if (projectId == null) {
            throw new AuraHandledException('Project is required to load milestones.');
        }

        if (towerId != null && [
            SELECT COUNT()
            FROM Block__c
            WHERE Id = :towerId AND Project__c = :projectId
        ] == 0) {
            throw new AuraHandledException('The selected tower does not belong to this project.');
        }

        // Get ALL active milestones (not just completed)
        List<Master_Payment_Schedule__c> milestones = [
            SELECT Id, Name, Sequence__c, Percentage__c, Status__c, Payment_Type__c
            FROM Master_Payment_Schedule__c
            WHERE Project__c = :projectId
            AND Is_Active__c = true
            ORDER BY Sequence__c ASC
        ];

        Set<Id> milestoneIds = new Set<Id>();
        for (Master_Payment_Schedule__c ms : milestones) {
            milestoneIds.add(ms.Id);
        }

        Set<Id> towerMilestoneIds = new Set<Id>();
        if (towerId != null && !milestoneIds.isEmpty()) {
            for (Payment_Schedule__c ps : [
                SELECT Master_Payment_Schedule__c
                FROM Payment_Schedule__c
                WHERE Master_Payment_Schedule__c IN :milestoneIds
                AND Booking__r.Project__c = :projectId
                AND Booking__r.Plot__r.Block1__c = :towerId
                AND Booking__r.Status__c != 'Cancellation'
                AND Booking__r.Status__c != 'Swapping'
            ]) {
                towerMilestoneIds.add(ps.Master_Payment_Schedule__c);
            }
            milestones = new List<Master_Payment_Schedule__c>();
            if (!towerMilestoneIds.isEmpty()) {
                milestones = [
                    SELECT Id, Name, Sequence__c, Percentage__c, Status__c, Payment_Type__c
                    FROM Master_Payment_Schedule__c
                    WHERE Id IN :towerMilestoneIds
                    AND Project__c = :projectId
                    AND Is_Active__c = true
                    ORDER BY Sequence__c ASC
                ];
            }
        }

        // Check which milestones already have demands raised for all bookings
        milestoneIds.clear();
        for (Master_Payment_Schedule__c ms : milestones) {
            milestoneIds.add(ms.Id);
        }

        // Count schedule rows in-scope per milestone.
        Map<Id, Integer> totalByMilestone = new Map<Id, Integer>();
        Map<Id, Integer> demandedByMilestone = new Map<Id, Integer>();
        List<Payment_Schedule__c> scopedSchedules;
        if (towerId == null) {
            scopedSchedules = [
                SELECT Master_Payment_Schedule__c, Demand_Raised__c
                FROM Payment_Schedule__c
                WHERE Master_Payment_Schedule__c IN :milestoneIds
                AND Booking__r.Status__c != 'Cancellation'
                AND Booking__r.Status__c != 'Swapping'
                AND Booking__r.Project__c = :projectId
            ];
        } else {
            scopedSchedules = [
                SELECT Master_Payment_Schedule__c, Demand_Raised__c
                FROM Payment_Schedule__c
                WHERE Master_Payment_Schedule__c IN :milestoneIds
                AND Booking__r.Status__c != 'Cancellation'
                AND Booking__r.Status__c != 'Swapping'
                AND Booking__r.Project__c = :projectId
                AND Booking__r.Plot__r.Block1__c = :towerId
            ];
        }

        for (Payment_Schedule__c ps : scopedSchedules) {
            Id milestoneId = ps.Master_Payment_Schedule__c;
            Integer total = totalByMilestone.containsKey(milestoneId)
                ? totalByMilestone.get(milestoneId) + 1 : 1;
            totalByMilestone.put(milestoneId, total);
            if (ps.Demand_Raised__c == true) {
                Integer demanded = demandedByMilestone.containsKey(milestoneId)
                    ? demandedByMilestone.get(milestoneId) + 1 : 1;
                demandedByMilestone.put(milestoneId, demanded);
            }
        }

        Map<Id, Boolean> milestoneFullyDemanded = new Map<Id, Boolean>();
        for (Id msId : milestoneIds) {
            Integer total = totalByMilestone.containsKey(msId) ? totalByMilestone.get(msId) : 0;
            Integer demanded = demandedByMilestone.containsKey(msId) ? demandedByMilestone.get(msId) : 0;
            milestoneFullyDemanded.put(msId, demanded >= total && total > 0);
        }

        Decimal cumPct = 0;
        for (Master_Payment_Schedule__c ms : milestones) {
            if (ms.Payment_Type__c == DemandComponentService.TIME_BASED_PAYMENT_TYPE) continue;
            MasterMilestoneWrapper w = new MasterMilestoneWrapper();
            w.id = ms.Id;
            w.name = ms.Name;
            w.sequence = ms.Sequence__c;
            w.percentage = ms.Percentage__c;
            w.status = ms.Status__c;
            w.paymentType = ms.Payment_Type__c;
            w.isCompleted = (ms.Status__c == PostSalesConstants.MILESTONE_STATUS_COMPLETED);
            w.demandAlreadyRaised = milestoneFullyDemanded.containsKey(ms.Id)
                ? milestoneFullyDemanded.get(ms.Id) : false;
            cumPct += (ms.Percentage__c != null ? ms.Percentage__c : 0);
            w.cumulativePercentage = cumPct;
            wrappers.add(w);
        }

        return wrappers;
    }

    @AuraEnabled
    public static List<BookingDemandWrapper> getBookingsForMilestone(
        Id projectId,
        Id towerId,
        Id masterPaymentScheduleId,
        String demandComponent
    ) {
        validateDemandComponent(demandComponent);
        if (projectId == null || masterPaymentScheduleId == null) {
            throw new AuraHandledException('Project and milestone are required.');
        }
        Project__c demandProject = [
            SELECT Legacy_Split_Demand_Receipt__c FROM Project__c WHERE Id = :projectId LIMIT 1
        ];
        validateProjectDemandMode(demandComponent, demandProject.Legacy_Split_Demand_Receipt__c);
        if (towerId != null && [
            SELECT COUNT()
            FROM Block__c
            WHERE Id = :towerId AND Project__c = :projectId
        ] == 0) {
            throw new AuraHandledException('The selected tower does not belong to this project.');
        }

        // Get the selected milestone's sequence
        List<Master_Payment_Schedule__c> selectedMilestones = [
            SELECT Id, Project__c, Sequence__c, Payment_Type__c
            FROM Master_Payment_Schedule__c
            WHERE Id = :masterPaymentScheduleId AND Project__c = :projectId
            LIMIT 1
        ];
        if (selectedMilestones.isEmpty()) {
            throw new AuraHandledException('The selected milestone does not belong to this project.');
        }
        Master_Payment_Schedule__c selectedMilestone = selectedMilestones[0];
        if (selectedMilestone.Payment_Type__c == DemandComponentService.TIME_BASED_PAYMENT_TYPE) {
            throw new AuraHandledException('Time Based schedules cannot be raised as demands.');
        }

        Decimal milestoneSequence = selectedMilestone.Sequence__c;

        // Get active bookings for this project
        List<Booking__c> bookings;
        if (towerId == null) {
            bookings = [
                SELECT Id, Name, Plot__r.Name, First_Applicant_Name__c, Email__c, Funding_Type__c,
                       Project__r.Legacy_Split_Demand_Receipt__c
                FROM Booking__c
                WHERE Project__c = :projectId
                AND Status__c != 'Cancellation' AND Status__c != 'Swapping'
                ORDER BY Name ASC
            ];
        } else {
            bookings = [
                SELECT Id, Name, Plot__r.Name, First_Applicant_Name__c, Email__c, Funding_Type__c,
                       Project__r.Legacy_Split_Demand_Receipt__c
                FROM Booking__c
                WHERE Project__c = :projectId
                AND Plot__r.Block1__c = :towerId
                AND Status__c != 'Cancellation' AND Status__c != 'Swapping'
                ORDER BY Name ASC
            ];
        }

        if (bookings.isEmpty()) {
            return new List<BookingDemandWrapper>();
        }

        Set<Id> bookingIds = new Set<Id>();
        Map<Id, Booking__c> bookingMap = new Map<Id, Booking__c>();
        for (Booking__c b : bookings) {
            bookingIds.add(b.Id);
            bookingMap.put(b.Id, b);
        }
        Map<Id, Decimal> remainingWaivers = InterestWaiverService.getRemainingWaivers(bookingIds);

        // Query payment schedules up to and including the selected milestone. Component flags
        // determine whether the selected component has already been demanded. Only schedules whose own
        // Status__c is Completed are eligible — a booking whose schedules are all still
        // pending simply produces no rows here and drops out of the list below.
        List<Payment_Schedule__c> allSchedules = [
            SELECT Id, Name, Booking__c, Milestone_Name__c,
                   Amount__c, Pending_Amount__c, Interest_Pending__c,
                   Sequence__c, S_No__c, Demand_Raised__c, Status__c,
                   Payment_Schedule_Amount_Pending__c, Payment_Schedule_Amount_Paid__c,
                   GST_Amount_Pending__c, GST_Amount_Paid__c,
                   TDS_Amount_Pending__c,
                   Bank_Flat_Amount__c, Bank_GST_Amount__c,
                   Customer_Flat_Prorata__c, Customer_GST_Prorata__c,
                   Booking__r.Funding_Type__c, Booking__r.Project__r.Legacy_Split_Demand_Receipt__c,
                   Bank_Demand_Raised__c, Customer_Demand_Raised__c,
                   Bank_Flat_Demand_Raised__c, Bank_GST_Demand_Raised__c,
                   Customer_Flat_Demand_Raised__c, Customer_GST_Demand_Raised__c,
                   Master_Payment_Schedule__c, Master_Payment_Schedule__r.Payment_Type__c
            FROM Payment_Schedule__c
            WHERE Booking__c IN :bookingIds
            AND S_No__c <= :milestoneSequence
            AND Status__c = :SCHEDULE_STATUS_COMPLETED
            ORDER BY Sequence__c ASC
        ];

        // Group schedules by booking
        Map<Id, List<Payment_Schedule__c>> allByBooking = new Map<Id, List<Payment_Schedule__c>>();
        for (Payment_Schedule__c ps : allSchedules) {
            if (!allByBooking.containsKey(ps.Booking__c)) {
                allByBooking.put(ps.Booking__c, new List<Payment_Schedule__c>());
            }
            allByBooking.get(ps.Booking__c).add(ps);
        }

        // Build wrappers with cumulative breakdown
        List<BookingDemandWrapper> wrappers = new List<BookingDemandWrapper>();
        for (Id bookingId : bookingIds) {
            List<Payment_Schedule__c> bookingSchedules = allByBooking.get(bookingId);
            if (bookingSchedules == null || bookingSchedules.isEmpty()) continue;

            Booking__c booking = bookingMap.get(bookingId);
            BookingDemandWrapper w = new BookingDemandWrapper();
            w.bookingId = booking.Id;
            w.bookingName = booking.Name;
            w.unitName = booking.Plot__r != null ? booking.Plot__r.Name : '';
            w.applicantName = booking.First_Applicant_Name__c;
            w.email = booking.Email__c;
            w.totalPending = 0;
            w.totalFlatAmount = 0;
            w.totalGstAmount = 0;
            w.totalTdsAmount = 0;
            w.totalInterest = 0;
            w.currentMilestoneAmount = 0;
            w.previousMilestonesAmount = 0;
            w.bankPayableAmount = 0;
            w.customerPayableAmount = 0;
            w.scheduleItems = new List<PaymentScheduleLineItem>();
            w.isSelected = true;

            Boolean isProrata = booking.Project__r.Legacy_Split_Demand_Receipt__c == true
                && booking.Funding_Type__c != null
                && SPLIT_FUNDING_TYPES.contains(booking.Funding_Type__c);
            Boolean hasUnraisedDemand = false;
            // True only if THIS booking has an actual Payment_Schedule__c row (Status__c =
            // Completed, per the allSchedules query above) matching the milestone selected in
            // Step 2. The Step 2 "COMPLETED" badge reflects the master/template flag, which can
            // say Completed project-wide even when this specific booking hasn't reached that
            // milestone yet (data issue) — this flag catches that at the booking level instead.
            Boolean selectedMilestoneCompletedForBooking = false;

            for (Payment_Schedule__c ps : bookingSchedules) {
                if (DemandComponentService.isTimeBasedSchedule(ps)) continue;
                Decimal pending = ps.Pending_Amount__c != null ? ps.Pending_Amount__c : 0;
                Decimal interest = ps.Interest_Pending__c != null ? ps.Interest_Pending__c : 0;
                Boolean isCurrentMilestone = (ps.Master_Payment_Schedule__c == masterPaymentScheduleId);
                Boolean isBankSplit = isProrata
                    && (nz(ps.Bank_Flat_Amount__c) != 0 || nz(ps.Bank_GST_Amount__c) != 0);
                Boolean isBankDemand = isBankSplit;
                Boolean isDemandNotRaised = !DemandComponentService.isComponentRaised(
                    ps, demandComponent, isBankDemand
                );

                // Reaching a current-milestone Completed schedule confirms this booking has
                // actually hit the milestone selected in Step 2 (used for the skip check
                // below), regardless of whether that milestone was already demanded.
                if (isCurrentMilestone) {
                    selectedMilestoneCompletedForBooking = true;
                } else if (demandComponent == DemandComponentService.FLAT && ps.Demand_Raised__c == true) {
                    // True "Previous Dues" (QA item 5): earlier milestones already demanded but
                    // still unpaid. These are NOT part of this demand (never re-demanded) but the
                    // customer still owes them, so they are shown and added into Net Demand.
                    // Earlier milestones never demanded join THIS demand via totalPending below,
                    // so counting them here too would double-count them in the net.
                    w.previousMilestonesAmount += pending;
                }

                // Only schedules whose selected component hasn't been raised count toward the amounts
                // shown and demanded. The Current/Previous breakdown is now gated on the SAME
                // condition as Total Pending / Net Demand, so Previous Dues + Current Milestone
                // always reconciles with Net Demand — and an already-demanded milestone (e.g. the
                // booking-amount demand on milestone #1) is never re-demanded. This also keeps the
                // Bulk flow in agreement with the single Raise Demand flow up to the same milestone.
                if (isDemandNotRaised) {
                    // Raise only the selected Flat or GST component, using the Bank amount when
                    // the schedule has a split and the schedule amount otherwise.
                    Decimal demandable = DemandComponentService.amount(ps, demandComponent, isBankDemand);
                    if (demandable <= 0) continue;
                    Decimal tdsDemandable = DemandComponentService.includesFlat(demandComponent) && !isBankDemand
                        ? nz(ps.TDS_Amount_Pending__c) : 0;
                    Decimal flatDemandable = demandComponent == DemandComponentService.FLAT
                        ? demandable - tdsDemandable
                        : (demandComponent == DemandComponentService.FLAT_AND_GST
                            ? nz(ps.Payment_Schedule_Amount_Pending__c) : 0);
                    Decimal gstDemandable = demandComponent == DemandComponentService.GST
                        ? demandable
                        : (demandComponent == DemandComponentService.FLAT_AND_GST
                            ? nz(ps.GST_Amount_Pending__c) : 0);
                    hasUnraisedDemand = true;

                    // Current Milestone shows the selected milestone's demandable amount. Earlier
                    // not-yet-demanded milestones still flow into Total Pending / Net Demand below;
                    // they are NOT added to Previous Dues, which (per QA item 5) means amounts
                    // already demanded but unpaid — accumulated in the loop above. The schedule
                    // matching the selected milestone is what the Demand's Payment_Schedule__c
                    // lookup links to.
                    if (isCurrentMilestone) {
                        w.currentMilestoneAmount += demandable;
                        w.currentMilestoneScheduleId = ps.Id;
                    }

                    w.totalPending += demandable;
                    w.totalFlatAmount += flatDemandable;
                    w.totalGstAmount += gstDemandable;
                    w.totalTdsAmount += tdsDemandable;
                    if (DemandComponentService.includesFlat(demandComponent)) w.totalInterest += interest;
                    if (isBankDemand) {
                        w.bankPayableAmount += demandable;
                    } else {
                        w.customerPayableAmount += demandable;
                    }

                    PaymentScheduleLineItem item = new PaymentScheduleLineItem();
                    item.scheduleId = ps.Id;
                    item.scheduleName = ps.Name;
                    item.milestoneName = ps.Milestone_Name__c;
                    item.pendingAmount = demandable;
                    item.basePending = flatDemandable;
                    item.gstPending = gstDemandable;
                    item.tdsAmount = tdsDemandable;
                    item.interestAmount = DemandComponentService.includesFlat(demandComponent) ? interest : 0;
                    item.sequence = ps.Sequence__c;
                    item.formattedPending = formatCurrency(demandable);
                    item.formattedInterest = formatCurrency(interest);
                    item.isSelected = true;
                    item.isCurrentMilestone = isCurrentMilestone;
                    item.isBankPayable = isBankDemand;
                    w.scheduleItems.add(item);
                }
            }

            // Skip this booking if the milestone selected in Step 2 is not actually Completed
            // for THIS booking's own schedule — even though the Step 2 badge may show
            // "COMPLETED" (that badge reflects the master/template flag, not this booking).
            if (!selectedMilestoneCompletedForBooking) continue;

            // Skip bookings with no unraised demand schedules
            if (!hasUnraisedDemand) continue;

            // Net = previous dues (already demanded, unpaid) + what this demand raises + interest.
            applyPreviewWaiver(w, remainingWaivers.get(bookingId));
            w.netDemandAmount = w.totalPending + w.totalInterest + w.previousMilestonesAmount;
            w.formattedPending = formatCurrency(w.totalPending);
            w.formattedFlatAmount = formatCurrency(w.totalFlatAmount);
            w.formattedGstAmount = formatCurrency(w.totalGstAmount);
            w.formattedTdsAmount = formatCurrency(w.totalTdsAmount);
            w.formattedInterest = formatCurrency(w.totalInterest);
            w.formattedNet = formatCurrency(w.netDemandAmount);
            w.formattedCurrentAmount = formatCurrency(w.currentMilestoneAmount);
            w.formattedPreviousAmount = formatCurrency(w.previousMilestonesAmount);
            w.formattedBankPayable = formatCurrency(w.bankPayableAmount);
            w.formattedCustomerPayable = formatCurrency(w.customerPayableAmount);
            wrappers.add(w);
        }

        return wrappers;
    }

    @AuraEnabled(cacheable=true)
    public static List<Project__c> getProjects() {
        return [SELECT Id, Name FROM Project__c ORDER BY Name LIMIT 1000];
    }

    @AuraEnabled
    public static List<BookingDemandWrapper> getIndividualCompletedSchedules(Id projectId, String demandComponent) {
        validateDemandComponent(demandComponent);
        if (projectId == null) {
            throw new AuraHandledException('Project is required.');
        }
        Project__c demandProject = [
            SELECT Legacy_Split_Demand_Receipt__c FROM Project__c WHERE Id = :projectId LIMIT 1
        ];
        validateProjectDemandMode(demandComponent, demandProject.Legacy_Split_Demand_Receipt__c);
        // Query payment schedules where the schedule itself is Completed (and its master
        // milestone is completed) and has pending amounts.
        List<Payment_Schedule__c> schedules = [
            SELECT Id, Name, Booking__c, Booking__r.Name, Booking__r.Plot__r.Name,
                   Booking__r.First_Applicant_Name__c, Booking__r.Email__c, Booking__r.Funding_Type__c,
                   Booking__r.Project__r.Legacy_Split_Demand_Receipt__c,
                   Milestone_Name__c, Pending_Amount__c, Interest_Pending__c,
                   Sequence__c, Status__c, Master_Payment_Schedule__r.Status__c,
                   Payment_Schedule_Amount_Pending__c, GST_Amount_Pending__c,
                   Payment_Schedule_Amount_Paid__c, GST_Amount_Paid__c,
                   TDS_Amount_Pending__c,
                   Bank_Flat_Amount__c, Bank_GST_Amount__c,
                   Customer_Flat_Prorata__c, Customer_GST_Prorata__c,
                   Demand_Raised__c, Bank_Demand_Raised__c, Customer_Demand_Raised__c,
                   Bank_Flat_Demand_Raised__c, Bank_GST_Demand_Raised__c,
                   Customer_Flat_Demand_Raised__c, Customer_GST_Demand_Raised__c,
                   Master_Payment_Schedule__r.Payment_Type__c
            FROM Payment_Schedule__c
            WHERE Booking__r.Project__c = :projectId
            AND Booking__r.Status__c != 'Cancellation' and Booking__r.Status__c != 'Swapping'
            AND Status__c = :SCHEDULE_STATUS_COMPLETED
            AND Master_Payment_Schedule__r.Status__c = :PostSalesConstants.MILESTONE_STATUS_COMPLETED
            AND Pending_Amount__c > 0
            ORDER BY Booking__r.Name ASC, Sequence__c ASC
        ];

        // Group by booking
        Map<Id, BookingDemandWrapper> wrapperMap = new Map<Id, BookingDemandWrapper>();

        for (Payment_Schedule__c ps : schedules) {
            if (DemandComponentService.isTimeBasedSchedule(ps)) continue;
            Id bookingId = ps.Booking__c;

            if (!wrapperMap.containsKey(bookingId)) {
                BookingDemandWrapper w = new BookingDemandWrapper();
                w.bookingId = bookingId;
                w.bookingName = ps.Booking__r.Name;
                w.unitName = ps.Booking__r.Plot__r != null ? ps.Booking__r.Plot__r.Name : '';
                w.applicantName = ps.Booking__r.First_Applicant_Name__c;
                w.email = ps.Booking__r.Email__c;
                w.totalPending = 0;
                w.totalFlatAmount = 0;
                w.totalGstAmount = 0;
                w.totalTdsAmount = 0;
                w.totalInterest = 0;
                w.bankPayableAmount = 0;
                w.customerPayableAmount = 0;
                w.scheduleItems = new List<PaymentScheduleLineItem>();
                w.isSelected = false;
                wrapperMap.put(bookingId, w);
            }

            BookingDemandWrapper w = wrapperMap.get(bookingId);
            Decimal interest = ps.Interest_Pending__c != null ? ps.Interest_Pending__c : 0;

            // Same rule as the Apartment flow and the individual Raise Demand view: Bank Flat +
            // Bank GST only when a real split exists, otherwise the full pending amount as
            // Customer. Total Pending / Net Demand derive from this single figure so they
            // always sum to Bank Payable + Customer Payable.
            Boolean isProrata = ps.Booking__r.Project__r.Legacy_Split_Demand_Receipt__c == true
                && ps.Booking__r.Funding_Type__c != null
                && SPLIT_FUNDING_TYPES.contains(ps.Booking__r.Funding_Type__c);
            Boolean thisIsBank = isProrata
                && (nz(ps.Bank_Flat_Amount__c) != 0 || nz(ps.Bank_GST_Amount__c) != 0);
            if (DemandComponentService.isComponentRaised(ps, demandComponent, thisIsBank)) continue;
            Decimal demandable = DemandComponentService.amount(ps, demandComponent, thisIsBank);
            if (demandable <= 0) continue;
            Decimal tdsDemandable = DemandComponentService.includesFlat(demandComponent) && !thisIsBank
                ? nz(ps.TDS_Amount_Pending__c) : 0;
            Decimal flatDemandable = demandComponent == DemandComponentService.FLAT
                ? demandable - tdsDemandable
                : (demandComponent == DemandComponentService.FLAT_AND_GST
                    ? nz(ps.Payment_Schedule_Amount_Pending__c) : 0);
            Decimal gstDemandable = demandComponent == DemandComponentService.GST
                ? demandable
                : (demandComponent == DemandComponentService.FLAT_AND_GST
                    ? nz(ps.GST_Amount_Pending__c) : 0);

            w.totalPending += demandable;
            w.totalFlatAmount += flatDemandable;
            w.totalGstAmount += gstDemandable;
            w.totalTdsAmount += tdsDemandable;
            if (DemandComponentService.includesFlat(demandComponent)) w.totalInterest += interest;
            if (thisIsBank) {
                w.bankPayableAmount += demandable;
            } else {
                w.customerPayableAmount += demandable;
            }

            PaymentScheduleLineItem item = new PaymentScheduleLineItem();
            item.scheduleId = ps.Id;
            item.scheduleName = ps.Name;
            item.milestoneName = ps.Milestone_Name__c;
            item.pendingAmount = demandable;
            item.basePending = flatDemandable;
            item.gstPending = gstDemandable;
            item.tdsAmount = tdsDemandable;
            item.interestAmount = DemandComponentService.includesFlat(demandComponent) ? interest : 0;
            item.sequence = ps.Sequence__c;
            item.formattedPending = formatCurrency(demandable);
            item.formattedInterest = formatCurrency(interest);
            item.isSelected = false;
            item.isBankPayable = thisIsBank;
            w.scheduleItems.add(item);
        }

        // Calculate net amounts
        List<BookingDemandWrapper> wrappers = new List<BookingDemandWrapper>();
        Set<Id> wrapperBookingIds = wrapperMap.keySet();
        Map<Id, Decimal> remainingWaivers = InterestWaiverService.getRemainingWaivers(wrapperBookingIds);
        for (BookingDemandWrapper w : wrapperMap.values()) {
            if (DemandComponentService.includesFlat(demandComponent)) {
                w.grossInterest = w.totalInterest;
            }
            applyPreviewWaiver(w, remainingWaivers.get(w.bookingId));
            w.netDemandAmount = w.totalPending + w.totalInterest;
            w.formattedPending = formatCurrency(w.totalPending);
            w.formattedFlatAmount = formatCurrency(w.totalFlatAmount);
            w.formattedGstAmount = formatCurrency(w.totalGstAmount);
            w.formattedTdsAmount = formatCurrency(w.totalTdsAmount);
            w.formattedInterest = formatCurrency(w.totalInterest);
            w.formattedNet = formatCurrency(w.netDemandAmount);
            w.formattedBankPayable = formatCurrency(w.bankPayableAmount);
            w.formattedCustomerPayable = formatCurrency(w.customerPayableAmount);
            wrappers.add(w);
        }

        return wrappers;
    }

    private static void applyPreviewWaiver(BookingDemandWrapper wrapper, Decimal remainingWaiver) {
        wrapper.grossInterest = wrapper.totalInterest == null ? 0 : wrapper.totalInterest;
        wrapper.interestWaivedOff = InterestWaiverService.getWaiverAmount(
            wrapper.grossInterest,
            remainingWaiver
        );
        wrapper.totalInterest = wrapper.grossInterest - wrapper.interestWaivedOff;
        wrapper.formattedGrossInterest = formatCurrency(wrapper.grossInterest);
        wrapper.formattedInterestWaivedOff = formatCurrency(wrapper.interestWaivedOff);
    }

    // ============ WRITE METHODS ============

    @AuraEnabled
    public static BulkDemandResult createBulkDemands(String requestJson) {
        BulkDemandResult result = new BulkDemandResult();
        result.results = new List<DemandResultItem>();
        result.successCount = 0;
        result.failureCount = 0;

        Savepoint sp = Database.setSavepoint();

        try {
            BulkDemandRequest request = (BulkDemandRequest) JSON.deserialize(requestJson, BulkDemandRequest.class);
            validateDemandComponent(request.demandComponent);

            if (request.bookings == null || request.bookings.isEmpty()) {
                throw new AuraHandledException('No bookings provided for demand creation');
            }
            if (request.towerId != null && (request.projectId == null || request.masterPaymentScheduleId == null)) {
                throw new AuraHandledException('Project and milestone are required when raising a tower demand.');
            }
            if (request.towerId != null && [
                SELECT COUNT()
                FROM Block__c
                WHERE Id = :request.towerId AND Project__c = :request.projectId
            ] == 0) {
                throw new AuraHandledException('The selected tower does not belong to this project.');
            }
            Master_Payment_Schedule__c selectedTowerMilestone;
            if (request.towerId != null) {
                List<Master_Payment_Schedule__c> selectedMilestones = [
                    SELECT Id, Sequence__c, Payment_Type__c
                    FROM Master_Payment_Schedule__c
                    WHERE Id = :request.masterPaymentScheduleId AND Project__c = :request.projectId
                    LIMIT 1
                ];
                if (selectedMilestones.isEmpty()) {
                    throw new AuraHandledException('The selected milestone does not belong to this project.');
                }
                if (selectedMilestones[0].Payment_Type__c
                    == DemandComponentService.TIME_BASED_PAYMENT_TYPE) {
                    throw new AuraHandledException('Time Based schedules cannot be raised as demands.');
                }
                selectedTowerMilestone = selectedMilestones[0];
            }

            // Collect all booking IDs for name lookup
            Set<Id> bookingIds = new Set<Id>();
            for (BookingDemandItem item : request.bookings) {
                bookingIds.add(item.bookingId);
            }

            Map<Id, Booking__c> bookingMap = new Map<Id, Booking__c>([
                SELECT Id, Name, Project__c, Plot__r.Block1__c, Funding_Type__c,
                       Project__r.Legacy_Split_Demand_Receipt__c
                FROM Booking__c WHERE Id IN :bookingIds
            ]);
            Boolean legacyMode;
            for (Booking__c booking : bookingMap.values()) {
                if (request.projectId != null && booking.Project__c != request.projectId) {
                    throw new AuraHandledException('One or more selected bookings do not belong to the selected project.');
                }
                Boolean bookingLegacyMode =
                    booking.Project__r.Legacy_Split_Demand_Receipt__c == true;
                if (legacyMode != null && legacyMode != bookingLegacyMode) {
                    throw new AuraHandledException('A demand request cannot mix legacy split and combined projects.');
                }
                legacyMode = bookingLegacyMode;
            }
            if (legacyMode == true && request.demandComponent == DemandComponentService.FLAT_AND_GST) {
                throw new AuraHandledException('Legacy projects require a separate Flat or GST demand.');
            }
            if (legacyMode == false && request.demandComponent != DemandComponentService.FLAT_AND_GST) {
                throw new AuraHandledException('This project requires a combined Flat + GST demand.');
            }
            Map<Id, Decimal> initialRemainingWaivers =
                InterestWaiverService.getRemainingWaivers(bookingIds, true);
            Map<Id, Decimal> remainingWaivers = new Map<Id, Decimal>(initialRemainingWaivers);
            if (request.towerId != null) {
                for (Id bookingId : bookingIds) {
                    Booking__c booking = bookingMap.get(bookingId);
                    if (booking == null || booking.Project__c != request.projectId
                        || booking.Plot__r == null || booking.Plot__r.Block1__c != request.towerId) {
                        throw new AuraHandledException('One or more selected bookings do not belong to the selected tower.');
                    }
                }
            }

            // Gather the milestone payment-schedule splits so each Demand can be filled with the
            // Base / GST / TDS amounts, and Prorata/Partial bookings demand only the Bank portion
            // (the customer side is reminded via the Master Payment Schedule forecast, BRD §8.5).
            // Sequence__c is also pulled so the demand can link to the latest (highest-sequence)
            // schedule included in it, matching the individual Raise Demand flow. Status__c is
            // pulled so a schedule that is no longer Completed can be rejected server-side.
            Set<Id> allScheduleIds = new Set<Id>();
            for (BookingDemandItem item : request.bookings) {
                if (item.scheduleIds != null) allScheduleIds.addAll(item.scheduleIds);
                if (item.currentMilestoneScheduleId != null) {
                    allScheduleIds.add(item.currentMilestoneScheduleId);
                }
            }
            Map<Id, Payment_Schedule__c> scheduleMap = allScheduleIds.isEmpty()
                ? new Map<Id, Payment_Schedule__c>()
                : new Map<Id, Payment_Schedule__c>([
                    SELECT Id, Booking__c, Master_Payment_Schedule__c, Milestone_Name__c, S_No__c,
                           Payment_Schedule_Amount_Pending__c, GST_Amount_Pending__c,
                           Payment_Schedule_Amount_Paid__c, GST_Amount_Paid__c,
                           Interest_Pending__c,
                           TDS_Amount_Pending__c, Bank_Flat_Amount__c, Bank_GST_Amount__c,
                           Customer_Flat_Prorata__c, Customer_GST_Prorata__c,
                           Sequence__c, Demand_Raised__c, Status__c,
                           Bank_Demand_Raised__c, Customer_Demand_Raised__c,
                           Bank_Flat_Demand_Raised__c, Bank_GST_Demand_Raised__c,
                           Customer_Flat_Demand_Raised__c, Customer_GST_Demand_Raised__c,
                           Booking__r.Funding_Type__c,
                           Booking__r.Project__r.Legacy_Split_Demand_Receipt__c,
                           Master_Payment_Schedule__r.Payment_Type__c
                    FROM Payment_Schedule__c WHERE Id IN :allScheduleIds
                ]);
            for (BookingDemandItem item : request.bookings) {
                if (item.scheduleIds != null) {
                    for (Id scheduleId : item.scheduleIds) {
                        Payment_Schedule__c schedule = scheduleMap.get(scheduleId);
                        if (schedule == null || schedule.Booking__c != item.bookingId) {
                            throw new AuraHandledException(
                                'One or more selected payment schedules do not belong to the selected booking.'
                            );
                        }
                        if (DemandComponentService.isTimeBasedSchedule(schedule)) {
                            throw new AuraHandledException(
                                'Time Based schedules cannot be raised as demands.'
                            );
                        }
                    }
                }
                if (item.currentMilestoneScheduleId != null) {
                    Payment_Schedule__c currentSchedule = scheduleMap.get(item.currentMilestoneScheduleId);
                    if (currentSchedule == null || currentSchedule.Booking__c != item.bookingId) {
                        throw new AuraHandledException(
                            'The selected milestone schedule does not belong to the selected booking.'
                        );
                    }
                    if (DemandComponentService.isTimeBasedSchedule(currentSchedule)) {
                        throw new AuraHandledException(
                            'Time Based schedules cannot be raised as demands.'
                        );
                    }
                }
            }
            if (request.towerId != null) {
                for (BookingDemandItem item : request.bookings) {
                    if (item.scheduleIds != null) {
                        for (Id scheduleId : item.scheduleIds) {
                            Payment_Schedule__c ps = scheduleMap.get(scheduleId);
                            if (ps == null || ps.Booking__c != item.bookingId
                                || ps.S_No__c > selectedTowerMilestone.Sequence__c) {
                                throw new AuraHandledException(
                                    'One or more selected payment schedules are outside the selected booking or milestone range.'
                                );
                            }
                        }
                    }
                    if (item.currentMilestoneScheduleId != null) {
                        Payment_Schedule__c currentSchedule =
                            scheduleMap.get(item.currentMilestoneScheduleId);
                        if (currentSchedule == null
                            || currentSchedule.Booking__c != item.bookingId
                            || currentSchedule.Master_Payment_Schedule__c != request.masterPaymentScheduleId) {
                            throw new AuraHandledException(
                                'The selected milestone schedule does not match the selected booking and tower milestone.'
                            );
                        }
                    }
                }
            }

            // Calculate due date
            Date dueDate = Date.today();
            if (request.gracePeriodDays != null && request.gracePeriodDays > 0) {
                dueDate = dueDate.addDays(Integer.valueOf(request.gracePeriodDays));
            } else {
                dueDate = dueDate.addDays(PostSalesConstants.DEFAULT_GRACE_PERIOD_DAYS);
            }

            String demandType = String.isNotBlank(request.demandType) ? request.demandType : PostSalesConstants.DEMAND_TYPE_BULK;

            // Create Demands
            List<Demands__c> demandsToInsert = new List<Demands__c>();
            Map<Integer, BookingDemandItem> indexToItem = new Map<Integer, BookingDemandItem>();
            // Per-item, per-schedule "was this schedule's amount demanded from the Bank or the
            // Customer" — captured while computing the Base/GST/TDS split below, and consumed
            // later when marking each schedule's Bank_Demand_Raised__c / Customer_Demand_Raised__c.
            Map<Integer, Map<Id, Boolean>> scheduleSourceByIndex = new Map<Integer, Map<Id, Boolean>>();
            Map<Integer, Decimal> grossInterestByIndex = new Map<Integer, Decimal>();
            Integer idx = 0;

            for (BookingDemandItem item : request.bookings) {
                // Guard against double-demanding and against demanding a schedule that is not
                // Completed: drop any schedule that already has a demand raised against it
                // (Demand_Raised__c = true) or whose Status__c is not Completed. Raising a second
                // demand on the same schedule would double Total Demand Raised on the Booking. If
                // every schedule of this item is filtered out, skip the item entirely and report
                // it back to the UI instead of inserting a duplicate or premature demand.
                if (item.scheduleIds != null && !item.scheduleIds.isEmpty()) {
                    List<Id> freshScheduleIds = new List<Id>();
                    Integer alreadyRaised = 0;
                    Integer notCompleted = 0;
                    Integer noComponentAmount = 0;
                    for (Id sid : item.scheduleIds) {
                        Payment_Schedule__c ps = scheduleMap.get(sid);
                        Boolean scheduleIsBank = ps != null
                            && isSplitFunding(bookingMap.get(item.bookingId))
                            && (nz(ps.Bank_Flat_Amount__c) != 0 || nz(ps.Bank_GST_Amount__c) != 0);
                        if (ps != null && DemandComponentService.isComponentRaised(
                                ps, request.demandComponent, scheduleIsBank
                            )) {
                            alreadyRaised++;
                        } else if (ps != null && ps.Status__c != SCHEDULE_STATUS_COMPLETED) {
                            notCompleted++;
                        } else if (ps != null && DemandComponentService.amount(
                                ps, request.demandComponent, scheduleIsBank
                            ) <= 0) {
                            noComponentAmount++;
                        } else {
                            freshScheduleIds.add(sid);
                        }
                    }
                    if (freshScheduleIds.isEmpty()) {
                        DemandResultItem skipped = new DemandResultItem();
                        skipped.bookingId = item.bookingId;
                        skipped.bookingName = bookingMap.containsKey(item.bookingId)
                            ? bookingMap.get(item.bookingId).Name : '';
                        skipped.success = false;
                        skipped.errorMessage = notCompleted > 0 && alreadyRaised == 0
                            ? 'Skipped: the selected payment schedule(s) are not marked Completed.'
                            : noComponentAmount > 0 && alreadyRaised == 0
                                ? 'Skipped: no pending ' + request.demandComponent
                                    + ' amount exists on the selected payment schedule(s).'
                            : 'Skipped: a demand has already been raised for the selected payment schedule(s). Raising it again would duplicate the demand.';
                        result.results.add(skipped);
                        result.failureCount++;
                        continue;
                    }
                    // Demand only the schedules that are Completed and not demanded yet.
                    item.scheduleIds = freshScheduleIds;
                }

                Demands__c demand = new Demands__c();
                demand.Booking__c = item.bookingId;
                Boolean includeFlatExtras = DemandComponentService.includesFlat(request.demandComponent);
                Decimal grossInterest = 0;
                if (includeFlatExtras && request.includeInterest == true) {
                    if (item.scheduleIds != null && !item.scheduleIds.isEmpty()) {
                        for (Id scheduleId : item.scheduleIds) {
                            Payment_Schedule__c schedule = scheduleMap.get(scheduleId);
                            if (schedule != null) grossInterest += nz(schedule.Interest_Pending__c);
                        }
                    }
                }
                Decimal remainingWaiver = remainingWaivers.get(item.bookingId);
                Decimal waiverAmount = InterestWaiverService.getWaiverAmount(grossInterest, remainingWaiver);
                demand.Interest_Amount__c = grossInterest - waiverAmount;
                demand.Interest_Waived_Off_Amount__c = waiverAmount;
                remainingWaivers.put(item.bookingId, nz(remainingWaiver) - waiverAmount);
                demand.Previous_Dues__c = includeFlatExtras && item.previousDues != null
                    ? item.previousDues : 0;
                demand.Demand_Component__c = request.demandComponent;
                demand.Status__c = PostSalesConstants.DEMAND_STATUS_RAISED;
                demand.Demand_Date__c = Date.today();
                demand.Due_Date__c = dueDate;
                demand.Grace_Period_Days__c = request.gracePeriodDays;
                demand.Notes__c = request.notes;
                demand.Reminder_Date__c = dueDate;

                // ---- Amount / GST / TDS breakdown from the milestone schedules ----
                Booking__c booking = bookingMap.get(item.bookingId);
                Boolean isProrata = isSplitFunding(booking);

                Decimal baseAmt = 0, gstAmt = 0, tdsAmt = 0;
                // True only when at least one schedule carries a real Bank/Customer prorata
                // split. If a Prorata/Partial schedule was never split, its Bank amounts are 0,
                // which previously produced a ₹0 demand — we fall back to the pending amounts.
                Boolean hasBankSplit = false;
                Map<Id, Boolean> scheduleIsBank = new Map<Id, Boolean>();
                Id latestScheduleId;        // schedule with the highest Sequence__c in this item
                Decimal latestSequence;
                if (item.scheduleIds != null) {
                    for (Id sid : item.scheduleIds) {
                        Payment_Schedule__c ps = scheduleMap.get(sid);
                        if (ps == null) continue;
                        Decimal bankFlat = ps.Bank_Flat_Amount__c != null ? ps.Bank_Flat_Amount__c : 0;
                        Decimal bankGst  = ps.Bank_GST_Amount__c  != null ? ps.Bank_GST_Amount__c  : 0;
                        Boolean thisIsBank = isProrata && (bankFlat != 0 || bankGst != 0);
                        scheduleIsBank.put(sid, thisIsBank);

                        if (thisIsBank) {
                            hasBankSplit = true;
                            if (DemandComponentService.includesFlat(request.demandComponent)) baseAmt += bankFlat;
                            else gstAmt += bankGst;
                        } else {
                            if (request.demandComponent == DemandComponentService.FLAT) {
                                baseAmt += nz(ps.Payment_Schedule_Amount_Pending__c);
                            } else if (request.demandComponent == DemandComponentService.GST) {
                                gstAmt += nz(ps.GST_Amount_Pending__c);
                            } else {
                                baseAmt += nz(ps.Payment_Schedule_Amount_Pending__c);
                                gstAmt += nz(ps.GST_Amount_Pending__c);
                            }
                            if (DemandComponentService.includesFlat(request.demandComponent)) {
                                tdsAmt += nz(ps.TDS_Amount_Pending__c);
                            }
                        }

                        // Track the latest milestone by sequence (the bigger Sequence__c number)
                        // among the schedules included in this demand.
                        if (ps.Sequence__c != null && (latestSequence == null || ps.Sequence__c > latestSequence)) {
                            latestSequence = ps.Sequence__c;
                            latestScheduleId = sid;
                        }
                    }
                }

                Decimal componentAmount = baseAmt + gstAmt + tdsAmt;
                if (componentAmount <= 0) {
                    DemandResultItem skipped = new DemandResultItem();
                    skipped.bookingId = item.bookingId;
                    skipped.bookingName = booking != null ? booking.Name : '';
                    skipped.success = false;
                    skipped.errorMessage = 'Skipped: no pending ' + request.demandComponent
                        + ' amount exists on the selected payment schedules.';
                    result.results.add(skipped);
                    result.failureCount++;
                    continue;
                }

                demand.Base_Amount__c = baseAmt;
                // Flat_Amount__c is the "Instalment Amount Payable" the Demand Letter table reads
                // (and what the single-demand path in PaymentScheduleViewController populates). Bulk
                // previously set only Base_Amount__c, leaving that column blank on the letter.
                demand.Flat_Amount__c = baseAmt;
                demand.GST_Amount__c = gstAmt;
                demand.TDS_Amount__c = tdsAmt;
                // Link to the schedule matching the milestone selected in Step 2 when the
                // client supplied one; otherwise fall back to the highest-sequence schedule
                // included in this demand, then the first schedule id.
                if (item.currentMilestoneScheduleId != null) {
                    demand.Payment_Schedule__c = item.currentMilestoneScheduleId;
                } else if (latestScheduleId != null) {
                    demand.Payment_Schedule__c = latestScheduleId;
                } else if (item.scheduleIds != null && !item.scheduleIds.isEmpty()) {
                    demand.Payment_Schedule__c = item.scheduleIds[0];
                }

                if (hasBankSplit) {
                    // Prorata / Partial with a real split: raise only the Bank demand. The
                    // customer-payable amount is reminded from the Master Payment Schedule
                    // forecast date (BRD §8.5) and demanded on its due date.
                    demand.Demand_Amount__c = componentAmount;
                    demand.Pending_Amount__c = componentAmount;
                    demand.Demand_Audience__c = 'Bank';
                    demand.Demand_Type__c = 'Bank Demand';
                } else {
                    demand.Demand_Amount__c = componentAmount;
                    demand.Pending_Amount__c = componentAmount;
                    demand.Demand_Audience__c = 'Customer';
                    demand.Demand_Type__c = demandType;
                }

                demandsToInsert.add(demand);
                indexToItem.put(idx, item);
                scheduleSourceByIndex.put(idx, scheduleIsBank);
                grossInterestByIndex.put(idx, grossInterest);
                idx++;
            }

            Database.SaveResult[] insertResults = Database.insert(demandsToInsert, false);

            // Process results and update payment schedules
            List<Payment_Schedule__c> schedulesToUpdate = new List<Payment_Schedule__c>();
            List<Demands__c> waiverAdjustments = new List<Demands__c>();
            Map<Id, Decimal> remainingAfterSuccessfulDemands =
                new Map<Id, Decimal>(initialRemainingWaivers);

            for (Integer i = 0; i < insertResults.size(); i++) {
                DemandResultItem resultItem = new DemandResultItem();
                BookingDemandItem requestItem = indexToItem.get(i);
                resultItem.bookingId = requestItem.bookingId;
                resultItem.bookingName = bookingMap.containsKey(requestItem.bookingId)
                    ? bookingMap.get(requestItem.bookingId).Name : '';

                if (insertResults[i].isSuccess()) {
                    resultItem.demandId = insertResults[i].getId();
                    resultItem.success = true;
                    result.successCount++;

                    Decimal grossInterest = grossInterestByIndex.get(i);
                    Decimal availableWaiver = remainingAfterSuccessfulDemands.get(requestItem.bookingId);
                    Decimal appliedWaiver = InterestWaiverService.getWaiverAmount(grossInterest, availableWaiver);
                    remainingAfterSuccessfulDemands.put(
                        requestItem.bookingId,
                        nz(availableWaiver) - appliedWaiver
                    );
                    if (demandsToInsert[i].Interest_Waived_Off_Amount__c != appliedWaiver) {
                        waiverAdjustments.add(new Demands__c(
                            Id = insertResults[i].getId(),
                            Interest_Amount__c = grossInterest - appliedWaiver,
                            Interest_Waived_Off_Amount__c = appliedWaiver
                        ));
                    }

                    // Mark payment schedules as demand raised — flips the general
                    // Demand_Raised__c flag (which locks the schedule for editing elsewhere)
                    // plus the Bank/Customer-specific flag matching where each schedule's
                    // amount was actually demanded from.
                    if (requestItem.scheduleIds != null) {
                        Map<Id, Boolean> sourceMap = scheduleSourceByIndex.get(i);
                        for (Id schedId : requestItem.scheduleIds) {
                            Payment_Schedule__c ps = new Payment_Schedule__c();
                            ps.Id = schedId;
                            ps.Demand_Date__c = Date.today();
                            Boolean isBank = sourceMap != null && sourceMap.get(schedId) == true;
                            DemandComponentService.markRaised(ps, request.demandComponent, isBank);
                            schedulesToUpdate.add(ps);
                        }
                    }
                } else {
                    resultItem.success = false;
                    resultItem.errorMessage = insertResults[i].getErrors()[0].getMessage();
                    result.failureCount++;
                }

                result.results.add(resultItem);
            }

            // Update payment schedules
            if (!schedulesToUpdate.isEmpty()) {
                Database.update(schedulesToUpdate, false);
            }
            if (!waiverAdjustments.isEmpty()) {
                update waiverAdjustments;
            }

            // Query demand names
            Set<Id> demandIds = new Set<Id>();
            for (DemandResultItem ri : result.results) {
                if (ri.demandId != null) {
                    demandIds.add(ri.demandId);
                }
            }

            if (!demandIds.isEmpty()) {
                Map<Id, Demands__c> demandMap = new Map<Id, Demands__c>(
                    [SELECT Id, Name FROM Demands__c WHERE Id IN :demandIds]
                );
                for (DemandResultItem ri : result.results) {
                    if (ri.demandId != null && demandMap.containsKey(ri.demandId)) {
                        ri.demandName = demandMap.get(ri.demandId).Name;
                    }
                }
            }

            result.totalProcessed = request.bookings.size();
            result.success = result.failureCount == 0;

        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Error creating bulk demands: ' + e.getMessage());
        }

        return result;
    }

    @AuraEnabled
    public static void sendBulkDemandEmails(List<Id> demandIds, String templateId) {
        try {
            if (demandIds == null || demandIds.isEmpty()) {
                throw new AuraHandledException('No demand IDs provided');
            }

            List<Demands__c> demands = [
                SELECT Id, Name, Booking__c, Booking__r.Email__c, Booking__r.Name
                FROM Demands__c
                WHERE Id IN :demandIds
            ];

            // NOTE: the demand email is sent by the record-triggered flow "Send_Demand_Email",
            // which fires on every Demands__c insert and renders the "Demand Raise Mail" template
            // through EmailSenderInvocable against the Demands__c record — so merge fields resolve
            // (Applicant, Project, Milestone, etc.) and the Demand Letter document is attached, for
            // every funding type. This method therefore does NOT send its own email: the previous
            // implementation called prepareEmailFromTemplate with the Booking Id while the template's
            // object is Demands__c, so its query matched nothing and it sent the template RAW with no
            // attachment — a second, broken email on top of the flow's correct one. It now only
            // stamps the email-tracking fields the flow does not maintain.

            // Update demand records
            List<Demands__c> demandsToUpdate = new List<Demands__c>();
            for (Demands__c demand : demands) {
                Demands__c d = new Demands__c();
                d.Id = demand.Id;
                d.Email_Sent__c = true;
                d.Email_Sent_Date__c = DateTime.now();
                d.Email_Sent_To__c = demand.Booking__r.Email__c;
                d.Status__c = PostSalesConstants.DEMAND_STATUS_EMAILED;
                demandsToUpdate.add(d);
            }

            if (!demandsToUpdate.isEmpty()) {
                update demandsToUpdate;
            }

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error sending emails: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void sendDemandEmail(Id demandId, String emailTemplateId, String documentTemplateId) {
        try {
            if (demandId == null) {
                throw new AuraHandledException('Demand ID is required');
            }

            List<Demands__c> demands = [
                SELECT Id, Name, Booking__c, Booking__r.Email__c, Booking__r.Name
                FROM Demands__c
                WHERE Id = :demandId
                LIMIT 1
            ];

            if (demands.isEmpty()) {
                throw new AuraHandledException('Demand not found');
            }

            Demands__c demand = demands[0];
            String recipientEmail = demand.Booking__r != null ? demand.Booking__r.Email__c : null;

            if (String.isBlank(recipientEmail)) {
                throw new AuraHandledException('No email address found on the booking');
            }

            // Resolve email template: use provided ID or fall back to Post Sales Config default
            String resolvedEmailTemplateId = emailTemplateId;
            if (String.isBlank(resolvedEmailTemplateId)) {
                PostSalesAdminController.ConfigWrapper config =
                    PostSalesAdminController.getConfigurationByType('Demand');
                if (config != null && config.emailTemplateId != null) {
                    resolvedEmailTemplateId = config.emailTemplateId;
                }
            }

            if (String.isBlank(resolvedEmailTemplateId)) {
                throw new AuraHandledException('No email template configured. Please select one or configure a default in Post Sales Admin.');
            }

            // Prepare the email from the template against the booking record
            EmailSenderController.PreparedEmailData prepared =
                EmailSenderController.prepareEmailFromTemplate(resolvedEmailTemplateId, demand.Booking__c);

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ recipientEmail });
            email.setSubject(prepared.subject);
            email.setHtmlBody(prepared.body);
            email.setSaveAsActivity(true);
            email.setWhatId(demand.Id);

            Messaging.SendEmailResult[] results =
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

            if (results != null && !results.isEmpty() && !results[0].isSuccess()) {
                String err = results[0].getErrors() != null && !results[0].getErrors().isEmpty()
                    ? results[0].getErrors()[0].getMessage() : 'Unknown error';
                throw new AuraHandledException('Email send failed: ' + err);
            }

            // Update demand email tracking fields
            Demands__c d = new Demands__c();
            d.Id = demand.Id;
            d.Email_Sent__c = true;
            d.Email_Sent_Date__c = DateTime.now();
            d.Email_Sent_To__c = recipientEmail;
            d.Status__c = PostSalesConstants.DEMAND_STATUS_EMAILED;
            update d;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error sending demand email: ' + e.getMessage());
        }
    }

    // ============ DEMAND LETTER CONFIG ============

    public class DemandLetterConfigWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Id projectId { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public Id emailTemplateId { get; set; }
        @AuraEnabled public String emailTemplateName { get; set; }
        @AuraEnabled public Id documentTemplateId { get; set; }
        @AuraEnabled public String documentTemplateName { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Decimal gracePeriodDays { get; set; }
        @AuraEnabled public Boolean includeInterest { get; set; }
        @AuraEnabled public Boolean autoSendEmail { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<DemandLetterConfigWrapper> getDemandLetterConfigs() {
        List<DemandLetterConfigWrapper> wrappers = new List<DemandLetterConfigWrapper>();
        List<Demand_Letter_Config__c> configs = [
            SELECT Id, Project__c, Project__r.Name,
                   Email_Template__c, Email_Template__r.Template_Name__c,
                   Document_Template__c, Document_Template__r.Name,
                   Is_Active__c, Description__c,
                   Grace_Period_Days__c, Include_Interest__c, Auto_Send_Email__c
            FROM Demand_Letter_Config__c
            ORDER BY Project__r.Name ASC
        ];

        for (Demand_Letter_Config__c c : configs) {
            DemandLetterConfigWrapper w = new DemandLetterConfigWrapper();
            w.id = c.Id;
            w.projectId = c.Project__c;
            w.projectName = c.Project__c != null ? c.Project__r.Name : null;
            w.emailTemplateId = c.Email_Template__c;
            w.emailTemplateName = c.Email_Template__c != null ? c.Email_Template__r.Template_Name__c : null;
            w.documentTemplateId = c.Document_Template__c;
            w.documentTemplateName = c.Document_Template__c != null ? c.Document_Template__r.Name : null;
            w.isActive = c.Is_Active__c;
            w.description = c.Description__c;
            w.gracePeriodDays = c.Grace_Period_Days__c;
            w.includeInterest = c.Include_Interest__c;
            w.autoSendEmail = c.Auto_Send_Email__c;
            wrappers.add(w);
        }
        return wrappers;
    }

    @AuraEnabled
    public static Id saveDemandLetterConfig(String configJson) {
        try {
            DemandLetterConfigWrapper w = (DemandLetterConfigWrapper) JSON.deserialize(configJson, DemandLetterConfigWrapper.class);

            Demand_Letter_Config__c config;
            if (w.id != null) {
                config = [SELECT Id FROM Demand_Letter_Config__c WHERE Id = :w.id LIMIT 1];
            } else {
                config = new Demand_Letter_Config__c();
            }

            config.Project__c = w.projectId;
            config.Email_Template__c = w.emailTemplateId;
            config.Document_Template__c = w.documentTemplateId;
            config.Is_Active__c = w.isActive == true;
            config.Description__c = w.description;
            config.Grace_Period_Days__c = w.gracePeriodDays;
            config.Include_Interest__c = w.includeInterest == true;
            config.Auto_Send_Email__c = w.autoSendEmail == true;

            upsert config;
            return config.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving demand letter config: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteDemandLetterConfig(Id configId) {
        try {
            delete [SELECT Id FROM Demand_Letter_Config__c WHERE Id = :configId LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting demand letter config: ' + e.getMessage());
        }
    }

    // ============ UTILITY ============

    private static void validateDemandComponent(String demandComponent) {
        if (demandComponent != DemandComponentService.FLAT
            && demandComponent != DemandComponentService.GST
            && demandComponent != DemandComponentService.FLAT_AND_GST) {
            throw new AuraHandledException('Select Flat, GST, or Flat + GST for the demand component.');
        }
    }

    private static void validateProjectDemandMode(String demandComponent, Boolean legacyMode) {
        if ((legacyMode == true && demandComponent == DemandComponentService.FLAT_AND_GST)
            || (legacyMode != true && demandComponent != DemandComponentService.FLAT_AND_GST)) {
            throw new AuraHandledException(legacyMode == true
                ? 'Legacy projects require a separate Flat or GST demand.'
                : 'This project requires a combined Flat + GST demand.');
        }
    }

    private static Boolean isSplitFunding(Booking__c booking) {
        return booking != null && booking.Project__r != null
            && booking.Project__r.Legacy_Split_Demand_Receipt__c == true
            && booking.Funding_Type__c != null
            && SPLIT_FUNDING_TYPES.contains(booking.Funding_Type__c);
    }

    private static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String formatCurrency(Decimal value) {
        return PostSalesConstants.formatCurrency(value);
    }
}