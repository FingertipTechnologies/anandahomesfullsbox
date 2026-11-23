/**
 * @description Handles booking swap (unit change) - clones the booking and its transferable
 * child records, generates schedules for the new unit, reallocates approved receipts, and
 * updates unit statuses and files.
 * Called from Flow when Booking Status changes to 'Swapping'.
 *
 * Cloning uses a global old->new Id registry to remap lookups between cloned records.
 * The new booking's schedules are generated from its project master schedule; approved receipts
 * are cloned without old line items or advances, then processed by the standard allocator.
 * BookingFinancialRecalcService is bypassed during cloning and run once at the end
 * for both bookings, so financial totals are rebuilt on fully-linked data.
 */
public with sharing class BookingSwapHandler {

    /** Raised when a swap cannot be completed. Surfaces the reason to the caller/Flow so the
     *  transaction rolls back cleanly instead of leaving the booking half-swapped. */
    public class BookingSwapException extends Exception {}

    // ==================== CHILD CLONE CONFIGURATION ====================

    /**
     * @description Inner class defining which child objects to clone during a booking swap.
     * Each entry specifies the child object API name, the lookup field to Booking,
     * and optionally a child line-item object that should also be cloned.
     * Lookups between cloned records are remapped automatically via the Id registry,
     * so no per-field remap configuration is needed.
     */
    public class ChildCloneConfig {
        public String objectApiName;
        public String bookingLookupField;
        public String lineItemObjectApiName;
        public String lineItemBookingLookupField;
        /** Optional extra SOQL filter for the parent object (e.g. only Approved receipts). */
        public String extraWhere;
        /** Optional extra SOQL filter for the line-item object — MUST mirror the parent
         *  filter (via the parent relationship) so line items of skipped parents are
         *  skipped too, otherwise they would clone still pointing at the OLD parent. */
        public String lineItemExtraWhere;

        public ChildCloneConfig(String objectApiName, String bookingLookupField) {
            this.objectApiName = objectApiName;
            this.bookingLookupField = bookingLookupField;
            this.lineItemObjectApiName = null;
            this.lineItemBookingLookupField = null;
        }

        public ChildCloneConfig(String objectApiName, String bookingLookupField,
                                String lineItemObjectApiName, String lineItemBookingLookupField) {
            this.objectApiName = objectApiName;
            this.bookingLookupField = bookingLookupField;
            this.lineItemObjectApiName = lineItemObjectApiName;
            this.lineItemBookingLookupField = lineItemBookingLookupField;
        }
    }

    /**
     * @description Configuration list defining all child objects that should be cloned
     * when a booking is swapped. ORDER MATTERS: it is the dependency order for lookup
     * remapping. An object must appear AFTER every object it looks up to, so the
     * registry already contains the new Ids when its records are cloned.
     * (Demands before Receipts. Payment schedules are generated before this cloning pass, and
     * receipt line items are recreated by allocating the transferred receipts afterward.)
     */
    private static List<ChildCloneConfig> getChildCloneConfigs() {
        // Only APPROVED receipts are transferred to the new booking. Pending and Rejected
        // receipts stay on the old booking; approved receipts are reallocated after cloning.
        ChildCloneConfig receiptConfig = new ChildCloneConfig('Receipt__c', 'Booking__c');
        receiptConfig.extraWhere =
            'Approval_Status__c = \'' + APPROVAL_STATUS_APPROVED + '\'';

        return new List<ChildCloneConfig>{
            new ChildCloneConfig('Co_Applicant__c',       'Booking__c'),
            new ChildCloneConfig('KYC_Documents__c',      'Booking__c'),
            new ChildCloneConfig('Demands__c',            'Booking__c'),
            receiptConfig,
            new ChildCloneConfig('Interest_Line_Item__c', 'Booking__c'),
            new ChildCloneConfig('Refund__c',             'Booking__c')
        };
    }

    /** Receipt approval status considered transferable during a swap.
     *  Replace with PostSalesConstants.APPROVAL_STATUS_APPROVED if that constant exists. */
    private static final String APPROVAL_STATUS_APPROVED = 'Approved';

    // ==================== INPUT / OUTPUT WRAPPERS ====================

    public class SwapRequest {
        @InvocableVariable(label='Old Booking ID' required=true)
        public Id oldBookingId;

        @InvocableVariable(label='New Unit ID' required=true)
        public Id newUnitId;

        @InvocableVariable(label='New Booking Status' required=true description='Status for the new booking (e.g. Draft, Approved, Active)')
        public String newBookingStatus;
    }

    public class SwapResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;

        @InvocableVariable(label='New Booking ID')
        public Id newBookingId;
    }

    // ==================== INVOCABLE METHOD ====================

    @InvocableMethod(label='Swap Booking to New Unit' description='Clones a booking to a new unit, transfers child records and files, updates unit statuses')
    public static List<SwapResult> swapBookings(List<SwapRequest> requests) {
        List<SwapResult> results = new List<SwapResult>();

        for (SwapRequest request : requests) {
            results.add(processSwap(request));
        }

        return results;
    }

    // ==================== CORE LOGIC ====================

    private static SwapResult processSwap(SwapRequest request) {
        SwapResult result = new SwapResult();
        result.success = false;

        if (request.oldBookingId == null) {
            throw new BookingSwapException('Old Booking ID is required to perform a swap.');
        }
        if (request.newUnitId == null) {
            throw new BookingSwapException('Cannot swap this booking: the "Swap To Unit" field is '
                + 'empty. Select the target unit on the booking before it is swapped.');
        }
        if (String.isBlank(request.newBookingStatus)) {
            throw new BookingSwapException('New Booking Status is required to perform a swap.');
        }

        Boolean priorReceiptGateBypass = ReceiptApprovalGateService.bypass;
        Boolean priorRecalcBypass = BookingFinancialRecalcService.bypass;
        Boolean priorSwapLockBypass = BookingSwapLockService.bypass;

        // Step 1: Query old booking with all fields
        Booking__c oldBooking = queryBookingWithAllFields(request.oldBookingId);
        Id oldUnitId = oldBooking.Plot__c;

        // Step 1a: Swap eligibility (BRD §12) — only before Registration and only within
        // the same project. Validated before any DML so an invalid swap is a clean no-op.
        String eligibilityError = swapEligibilityError(oldBooking, request.newUnitId);
        if (String.isNotBlank(eligibilityError)) {
            throw new BookingSwapException(eligibilityError);
        }

        try {
            // Transfer approved receipts to the new booking; suspend the receipt approval gate
            // for this trusted server-side move.
            ReceiptApprovalGateService.bypass = true;

            // Suppress per-record financial recalculation while cloning; one full
            // recalculation runs at the end on completely linked data.
            BookingFinancialRecalcService.bypass = true;
            BookingSwapLockService.bypass = true;

            // Step 2: Clone the booking for the new unit
            Booking__c newBooking = oldBooking.clone(false, true, false, false);
            newBooking.Plot__c = request.newUnitId;
            newBooking.Status__c = request.newBookingStatus;
            newBooking.Booking_Date__c = Date.today();
            // Clear cancellation/swap fields on new booking
            newBooking.Cancellation_Date__c = null;
            newBooking.Cancellation_Reason__c = null;
            newBooking.Swap_Date__c = null;
            newBooking.Swapped_To_Booking__c = null;
            newBooking.Is_Swapped__c = false;
            // Clear approval statuses for fresh start
            newBooking.Booking_Verification_Approval_Status__c = 'Approved';
            newBooking.Assignment_Approval_Status__c = null;
            newBooking.Sale_Agreement_Approval_Status__c = null;
            newBooking.Cancellation_Approval_Before_Agreement__c = null;
            newBooking.Swapping_Approval_Before_Agreement__c = null;
            // The after-create Flow skips generation and automatic receipt creation for swap
            // bookings; the swap handler generates schedules and reallocates copied receipts.
            newBooking.Payment_Schedules_Created__c = true;
            // The quote built for the Swap To Unit when the swap was requested becomes the new
            // booking's quote; the old booking keeps its original one.
            Quote__c swapQuote = SwapQuoteService.findOpenSwapQuote(oldBooking.Id, request.newUnitId);
            Id swapQuoteId = swapQuote == null ? null : swapQuote.Id;
            if (swapQuoteId != null) {
                newBooking.Quote__c = swapQuoteId;
            }
            insert newBooking;

            // The after-create Flow skips generation for swap bookings; generate the target
            // booking's schedules now, before transferring and reallocating financial records.
            PaymentScheduleGeneratorService.generateForBookings(new Set<Id>{ newBooking.Id });

            // Step 3: Preserve the swap target while child transfer is still in progress.
            // Is_Swapped__c and terminal Status__c are set only after the transfer succeeds.
            oldBooking.Swap_Date__c = Date.today();
            oldBooking.Swapped_To_Booking__c = newBooking.Id;
            update oldBooking;

            // Step 4: Update Unit statuses
            List<Plot__c> unitsToUpdate = new List<Plot__c>();

            // Old unit → Available
            if (oldUnitId != null) {
                unitsToUpdate.add(new Plot__c(
                    Id = oldUnitId,
                    Status__c = PostSalesConstants.UNIT_STATUS_AVAILABLE,
                    Current_Booking__c = null
                ));
            }

            // New unit → Booked
            unitsToUpdate.add(new Plot__c(
                Id = request.newUnitId,
                Status__c = PostSalesConstants.UNIT_STATUS_BOOKED,
                Current_Booking__c = newBooking.Id
            ));

            update unitsToUpdate;

            // Step 5: Clone child records using a global old->new Id registry so every
            // lookup between cloned records is remapped to the new booking's records.
            Map<Id, Id> idRegistry = new Map<Id, Id>();
            idRegistry.put(request.oldBookingId, newBooking.Id);
            mapPaymentScheduleIds(request.oldBookingId, newBooking.Id, idRegistry);

            for (ChildCloneConfig config : getChildCloneConfigs()) {
                cloneChildRecords(request.oldBookingId, newBooking.Id, config, idRegistry);
            }

            // Step 5a: Fix references to objects cloned later in the dependency order.
            fixupStaleReferences(newBooking.Id, idRegistry);

            // Receipt line items and advances are rebuilt by the standard allocator, not copied
            // from the old booking's schedule structure.
            enqueueTransferredReceiptAllocation(newBooking.Id);

            // Step 6: Transfer files (ContentDocumentLinks)
            transferFiles(request.oldBookingId, newBooking.Id);

            // Step 7: Record swap history on both bookings (BRD §12).
            insert new Swap_History__c(
                Old_Booking__c = oldBooking.Id,
                New_Booking__c = newBooking.Id,
                Old_Plot__c    = oldUnitId,
                New_Plot__c    = request.newUnitId,
                Swap_Date__c   = Date.today(),
                Approved_By__c = UserInfo.getUserId(),
                Approved_Date__c = Date.today()
            );

            result.success = true;
            result.newBookingId = newBooking.Id;
            result.message = 'Booking swapped successfully. New Booking ID: ' + newBooking.Id;

            // Apply Post Sales Configuration for Transfer/Swap (auto-send email if configured)
            PostSalesAdminController.ConfigWrapper config = PostSalesAdminController.resolveConfigurationForRecord(
                'Transfer', newBooking.Id, 'Booking__c'
            );
            if (config != null && config.autoSendEmail == true && config.emailTemplateId != null) {
                String templateId = ConfigMatchingService.resolveEmailTemplateForAction(
                    'Transfer', newBooking.Id, 'Booking__c'
                );
                if (templateId != null) {
                    result.message += '. Email template resolved for auto-send.';
                }
            }

            // Step 8: Single financial recalculation for BOTH bookings on fully-linked data.
            // Must run after the bypass is lifted, so restore it first.
            BookingFinancialRecalcService.bypass = priorRecalcBypass;
            BookingFinancialRecalcService.recalculateForBookings(
                new Set<Id>{ request.oldBookingId, newBooking.Id }
            );

            // Step 9: The transfer is complete. The booking entered Swapping through its
            // approved status transition; activate the logical lock only after transfer.
            oldBooking.Is_Swapped__c = true;
            update oldBooking;

            // Step 10: Clean up the old booking (reject its Approved/Pending receipts with a note,
            // zero its schedules' received amounts) in its own transaction. Rejecting receipts
            // fires the receipt flows (recalc + notifications) per receipt; inside the swap's
            // approval transaction that ran past the 100-SOQL limit and the rejection was lost.
            enqueueOldBookingCleanup(request.oldBookingId, newBooking.Id);

            return result;

        } finally {
            // Exception-safe restore: a failure mid-swap must not leave the gates
            // disabled for the remainder of the transaction.
            ReceiptApprovalGateService.bypass = priorReceiptGateBypass;
            BookingFinancialRecalcService.bypass = priorRecalcBypass;
            BookingSwapLockService.bypass = priorSwapLockBypass;
        }
    }

    private static void enqueueTransferredReceiptAllocation(Id newBookingId) {
        List<Id> receiptIds = new List<Id>();
        for (Receipt__c receipt : [
            SELECT Id
            FROM Receipt__c
            WHERE Booking__c = :newBookingId
            AND Approval_Status__c = :APPROVAL_STATUS_APPROVED
            ORDER BY Receipt_Date__c ASC, CreatedDate ASC, Id ASC
        ]) {
            receiptIds.add(receipt.Id);
        }
        if (receiptIds.isEmpty()) return;

        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            throw new BookingSwapException(
                'Cannot complete the swap because receipt allocation could not be scheduled.'
            );
        }
        System.enqueueJob(new TransferredReceiptAllocation(newBookingId, receiptIds));
    }

    public class TransferredReceiptAllocation implements Queueable {
        private Id bookingId;
        private List<Id> receiptIds;

        public TransferredReceiptAllocation(Id bookingId, List<Id> receiptIds) {
            this.bookingId = bookingId;
            this.receiptIds = receiptIds;
        }

        public void execute(QueueableContext context) {
            if (receiptIds == null || receiptIds.isEmpty()) return;

            FinancialTransactionController.allocateReceipt(receiptIds[0]);
            BookingFinancialRecalcService.recalculateForBookings(new Set<Id>{ bookingId });

            if (receiptIds.size() > 1) {
                List<Id> remainingReceiptIds = new List<Id>();
                for (Integer i = 1; i < receiptIds.size(); i++) {
                    remainingReceiptIds.add(receiptIds[i]);
                }
                System.enqueueJob(
                    new TransferredReceiptAllocation(bookingId, remainingReceiptIds)
                );
            }
        }
    }

    // ==================== OLD BOOKING CLEAN-UP (2026-11-17) ====================

    /**
     * @description Runs the old-booking clean-up after the swap commits, with fresh limits.
     *              Public so a swap whose clean-up was missed can be re-run:
     *              System.enqueueJob(new BookingSwapHandler.OldBookingCleanup(oldId, newId));
     */
    public class OldBookingCleanup implements Queueable {
        private Id oldBookingId;
        private Id newBookingId;
        public OldBookingCleanup(Id oldBookingId, Id newBookingId) {
            this.oldBookingId = oldBookingId;
            this.newBookingId = newBookingId;
        }
        public void execute(QueueableContext ctx) {
            runOldBookingCleanup(oldBookingId, newBookingId);
        }
    }

    private static void enqueueOldBookingCleanup(Id oldBookingId, Id newBookingId) {
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new OldBookingCleanup(oldBookingId, newBookingId));
        } else {
            // No queueable slot left (e.g. already inside an async job): do it inline.
            runOldBookingCleanup(oldBookingId, newBookingId);
        }
    }

    @TestVisible
    private static void runOldBookingCleanup(Id oldBookingId, Id newBookingId) {
        Boolean priorRecalcBypass = BookingFinancialRecalcService.bypass;
        Boolean priorReceiptGateBypass = ReceiptApprovalGateService.bypass;
        Boolean priorSwapLockBypass = BookingSwapLockService.bypass;
        try {
            // One recalculation at the end instead of one per rejected receipt.
            BookingFinancialRecalcService.bypass = true;
            ReceiptApprovalGateService.bypass = true;
            BookingSwapLockService.bypass = true;
            rejectOldBookingReceipts(oldBookingId, newBookingId);
            BookingFinancialRecalcService.bypass = priorRecalcBypass;
            BookingFinancialRecalcService.recalculateForBookings(new Set<Id>{ oldBookingId });
            // Nothing is paid on the old booking any more - its schedules show 0 received.
            zeroOldBookingSchedules(oldBookingId);
        } finally {
            BookingFinancialRecalcService.bypass = priorRecalcBypass;
            ReceiptApprovalGateService.bypass = priorReceiptGateBypass;
            BookingSwapLockService.bypass = priorSwapLockBypass;
        }
    }

    @TestVisible
    private static final Set<String> RECEIPT_STATUSES_TO_REJECT = new Set<String>{
        APPROVAL_STATUS_APPROVED, 'Pending Approval', 'Pending For Approval', 'Pending'
    };

    /**
     * @description Rejects every Approved / Pending receipt left on the swapped (old) booking and
     *              notes why. Approved receipts were cloned to the new booking; pending ones are
     *              void. Open approval requests are withdrawn and approval locks released first.
     */
    @TestVisible
    private static void rejectOldBookingReceipts(Id oldBookingId, Id newBookingId) {
        List<Receipt__c> receipts = [
            SELECT Id, Name, Approval_Status__c, Notes__c
            FROM Receipt__c
            WHERE Booking__c = :oldBookingId AND Approval_Status__c IN :RECEIPT_STATUSES_TO_REJECT
        ];
        if (receipts.isEmpty()) return;

        String newBookingName = [SELECT Name FROM Booking__c WHERE Id = :newBookingId].Name;
        Set<Id> receiptIds = new Map<Id, Receipt__c>(receipts).keySet();

        // Withdraw open approval requests (pending receipts) so an approver cannot approve them later.
        List<Approval.ProcessWorkitemRequest> withdrawals = new List<Approval.ProcessWorkitemRequest>();
        for (ProcessInstanceWorkitem wi : [
            SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId IN :receiptIds
        ]) {
            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(wi.Id);
            req.setAction('Removed');
            req.setComments('Booking swapped to ' + newBookingName + ' - receipt rejected automatically.');
            withdrawals.add(req);
        }
        if (!withdrawals.isEmpty()) {
            for (Approval.ProcessResult pr : Approval.process(withdrawals, false)) {
                if (!pr.isSuccess()) System.debug(LoggingLevel.WARN, 'Swap: approval withdrawal failed ' + pr.getErrors());
            }
        }
        // Approved receipts are locked by the approval process. Approval.unlock() is not used: it needs
        // the org setting "Enable record locking and unlocking in Apex" (off in both orgs) and then fails
        // uncatchably. The update below works for users who may edit locked records (admins / Modify All
        // on Receipt__c).

        String stamp = Datetime.now().format('dd/MM/yyyy');
        for (Receipt__c r : receipts) {
            String note = 'Auto-rejected on ' + stamp + ': booking swapped to ' + newBookingName
                + (r.Approval_Status__c == APPROVAL_STATUS_APPROVED
                    ? ' (this approved receipt was transferred to the new booking).'
                    : ' (receipt was pending approval at the time of the swap).');
            r.Notes__c = String.isBlank(r.Notes__c) ? note : r.Notes__c + '\n' + note;
            r.Approval_Status__c = 'Rejected';
        }
        // Partial: a receipt that cannot be changed (locked) must not undo the whole swap.
        for (Database.SaveResult sr : Database.update(receipts, false)) {
            if (!sr.isSuccess()) System.debug(LoggingLevel.ERROR, 'Swap: receipt not rejected ' + sr.getId() + ' ' + sr.getErrors());
        }
    }

    /** @description Sets the received amounts of the swapped (old) booking's payment schedules to 0. */
    @TestVisible
    private static void zeroOldBookingSchedules(Id oldBookingId) {
        List<Payment_Schedule__c> schedules = [
            SELECT Id, Amount_Paid__c, Payment_Schedule_Amount_Paid__c, GST_Amount_Paid__c, TDS_Amount_Paid__c
            FROM Payment_Schedule__c WHERE Booking__c = :oldBookingId
        ];
        List<Payment_Schedule__c> toUpdate = new List<Payment_Schedule__c>();
        for (Payment_Schedule__c ps : schedules) {
            if (nz(ps.Amount_Paid__c) != 0 || nz(ps.Payment_Schedule_Amount_Paid__c) != 0
                || nz(ps.GST_Amount_Paid__c) != 0 || nz(ps.TDS_Amount_Paid__c) != 0) {
                toUpdate.add(new Payment_Schedule__c(Id = ps.Id, Amount_Paid__c = 0,
                    Payment_Schedule_Amount_Paid__c = 0, GST_Amount_Paid__c = 0, TDS_Amount_Paid__c = 0));
            }
        }
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }

    // ==================== SWAP ELIGIBILITY (BRD §12) ====================

    /** Stages at/after Registration — a booking can no longer be swapped from these. */
    private static final Set<String> SWAP_BLOCKED_STATUSES = new Set<String>{
        'Registration', 'Handover', 'Registered', 'Completed', 'Cancellation', 'Cancelled'
    };

    private static String swapEligibilityError(Booking__c oldBooking, Id newUnitId) {
        if (oldBooking == null) return 'Old booking could not be loaded.';

        if (oldBooking.Status__c != null && SWAP_BLOCKED_STATUSES.contains(oldBooking.Status__c)) {
            return 'Swap is allowed only before Registration. This booking is in "'
                + oldBooking.Status__c + '" stage and cannot be swapped.';
        }

        // Block only if a swap actually COMPLETED for this booking. Status__c = 'Swapping'
        // is the expected in-flight state when the approval flow invokes this handler,
        // so it must NOT be treated as already swapped.
        if (oldBooking.Is_Swapped__c == true || oldBooking.Swapped_To_Booking__c != null) {
            return 'This booking has already been swapped.';
        }

        List<Plot__c> newUnits = [SELECT Id, Project__c FROM Plot__c WHERE Id = :newUnitId LIMIT 1];
        if (newUnits.isEmpty()) {
            return 'The selected new unit could not be found.';
        }
        if (oldBooking.Project__c != null && newUnits[0].Project__c != oldBooking.Project__c) {
            return 'Swap is allowed only within the same project. Please select a unit from the '
                + 'same project as the current booking.';
        }
        return null;
    }

    // ==================== QUERY BOOKING WITH ALL FIELDS ====================

    private static Booking__c queryBookingWithAllFields(Id bookingId) {
        // Get all fields from the Booking__c object dynamically
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Booking__c.fields.getMap();
        List<String> fieldNames = new List<String>(fieldMap.keySet());

        String query = 'SELECT ' + String.join(fieldNames, ', ') +
                       ' FROM Booking__c WHERE Id = :bookingId LIMIT 1';

        return Database.query(query);
    }

    // ==================== GENERIC CHILD RECORD CLONING ====================

    /**
     * @description Clone a config entry's child object (and its line-item object, if any),
     * remapping every lookup that points at an already-cloned record via the Id registry.
     */
    private static void cloneChildRecords(Id oldBookingId, Id newBookingId,
                                          ChildCloneConfig config, Map<Id, Id> idRegistry) {
        cloneWithRemap(config.objectApiName, config.bookingLookupField,
                       oldBookingId, newBookingId, idRegistry, config.extraWhere);

        if (config.lineItemObjectApiName != null) {
            cloneWithRemap(config.lineItemObjectApiName, config.lineItemBookingLookupField,
                           oldBookingId, newBookingId, idRegistry, config.lineItemExtraWhere);
        }
    }

    /**
     * Maps old schedule IDs to schedules generated for the new booking. Linked child financial
     * records can then be cloned with their schedule lookups remapped.
     */
    private static void mapPaymentScheduleIds(
        Id oldBookingId,
        Id newBookingId,
        Map<Id, Id> idRegistry
    ) {
        List<Payment_Schedule__c> oldSchedules = [
            SELECT Id, Master_Payment_Schedule__c, Sequence__c, Milestone_Name__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :oldBookingId
        ];
        if (oldSchedules.isEmpty()) return;

        List<Payment_Schedule__c> newSchedules = [
            SELECT Id, Master_Payment_Schedule__c, Sequence__c, Milestone_Name__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :newBookingId
        ];

        Map<Id, List<Payment_Schedule__c>> schedulesByMaster =
            new Map<Id, List<Payment_Schedule__c>>();
        Map<String, List<Payment_Schedule__c>> schedulesByIdentity =
            new Map<String, List<Payment_Schedule__c>>();
        for (Payment_Schedule__c schedule : newSchedules) {
            if (schedule.Master_Payment_Schedule__c != null) {
                if (!schedulesByMaster.containsKey(schedule.Master_Payment_Schedule__c)) {
                    schedulesByMaster.put(
                        schedule.Master_Payment_Schedule__c,
                        new List<Payment_Schedule__c>()
                    );
                }
                schedulesByMaster.get(schedule.Master_Payment_Schedule__c).add(schedule);
            }
            String identity = paymentScheduleIdentity(schedule);
            if (identity != null) {
                if (!schedulesByIdentity.containsKey(identity)) {
                    schedulesByIdentity.put(identity, new List<Payment_Schedule__c>());
                }
                schedulesByIdentity.get(identity).add(schedule);
            }
        }

        Set<Id> unmatchedScheduleIds = new Set<Id>();
        for (Payment_Schedule__c oldSchedule : oldSchedules) {
            List<Payment_Schedule__c> matches = oldSchedule.Master_Payment_Schedule__c == null
                ? null
                : schedulesByMaster.get(oldSchedule.Master_Payment_Schedule__c);
            if (matches == null || matches.size() != 1) {
                String identity = paymentScheduleIdentity(oldSchedule);
                matches = identity == null ? null : schedulesByIdentity.get(identity);
            }
            if (matches != null && matches.size() == 1) {
                idRegistry.put(oldSchedule.Id, matches[0].Id);
            } else {
                unmatchedScheduleIds.add(oldSchedule.Id);
            }
        }

        if (unmatchedScheduleIds.isEmpty()) return;

        Set<Id> referencedScheduleIds = new Set<Id>();
        for (ChildCloneConfig config : getChildCloneConfigs()) {
            collectReferencedSchedules(
                config.objectApiName,
                config.bookingLookupField,
                oldBookingId,
                config.extraWhere,
                unmatchedScheduleIds,
                referencedScheduleIds
            );
            if (config.lineItemObjectApiName != null) {
                collectReferencedSchedules(
                    config.lineItemObjectApiName,
                    config.lineItemBookingLookupField,
                    oldBookingId,
                    config.lineItemExtraWhere,
                    unmatchedScheduleIds,
                    referencedScheduleIds
                );
            }
        }
        if (!referencedScheduleIds.isEmpty()) {
            throw new BookingSwapException(
                'Cannot complete the swap because a payment schedule with linked financial records '
                + 'has no matching schedule generated for the new booking.'
            );
        }
    }

    private static String paymentScheduleIdentity(Payment_Schedule__c schedule) {
        if (schedule.Sequence__c == null && String.isBlank(schedule.Milestone_Name__c)) {
            return null;
        }
        String sequence = schedule.Sequence__c == null
            ? ''
            : String.valueOf(schedule.Sequence__c);
        String milestone = String.isBlank(schedule.Milestone_Name__c)
            ? ''
            : schedule.Milestone_Name__c.trim().toLowerCase();
        return sequence + '|' + milestone;
    }

    private static void collectReferencedSchedules(
        String objectApiName,
        String bookingField,
        Id oldBookingId,
        String extraWhere,
        Set<Id> scheduleIds,
        Set<Id> referencedScheduleIds
    ) {
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        if (sObjectType == null
            || !sObjectType.getDescribe().fields.getMap().containsKey('Payment_Schedule__c')) {
            return;
        }

        String query = 'SELECT Payment_Schedule__c FROM ' + objectApiName
            + ' WHERE ' + bookingField + ' = :oldBookingId'
            + ' AND Payment_Schedule__c IN :scheduleIds';
        if (String.isNotBlank(extraWhere)) {
            query += ' AND (' + extraWhere + ')';
        }
        for (SObject record : Database.query(query)) {
            Id scheduleId = (Id) record.get('Payment_Schedule__c');
            if (scheduleId != null) referencedScheduleIds.add(scheduleId);
        }
    }

    /**
     * @description Generic clone of all records of one object belonging to the old booking.
     * For every writable lookup field on the clone, if its value is a key in the registry
     * (i.e. points at a record cloned earlier in this swap), it is replaced with the new Id.
     * All cloned old->new pairs are added to the registry for objects cloned later.
     */
    private static void cloneWithRemap(String objectApiName, String bookingField,
                                       Id oldBookingId, Id newBookingId, Map<Id, Id> idRegistry,
                                       String extraWhere) {
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        if (sType == null) {
            throw new BookingSwapException(
                'BookingSwapHandler: unknown or null object API name: [' + objectApiName + ']');
        }
        Map<String, Schema.SObjectField> fieldMap = sType.getDescribe().fields.getMap();

        // Writable lookup fields — the only ones that may need remapping
        List<String> refFields = new List<String>();
        for (String f : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(f).getDescribe();
            if (dfr.getType() == Schema.DisplayType.REFERENCE && dfr.isCreateable()) {
                refFields.add(f);
            }
        }

        String query = 'SELECT ' + String.join(new List<String>(fieldMap.keySet()), ', ') +
                       ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                       ' WHERE ' + String.escapeSingleQuotes(bookingField) + ' = :oldBookingId';
        if (String.isNotBlank(extraWhere)) {
            query += ' AND (' + extraWhere + ')';
        }
        List<SObject> fullRecords = Database.query(query);
        if (fullRecords.isEmpty()) return;

        List<SObject> clones = new List<SObject>();
        for (SObject rec : fullRecords) {
            SObject clone = rec.clone(false, true, false, false);
            clone.put(bookingField, newBookingId);
            if (objectApiName == 'Demands__c') {
                String demandStatus = (String) clone.get('Status__c');
                Id additionalChargeId = (Id) clone.get('Additional_Charge__c');
                if (demandStatus != 'Cancelled' && demandStatus != 'On Hold'
                    && additionalChargeId == null) {
                    Decimal demandAmount = (Decimal) clone.get('Demand_Amount__c');
                    clone.put('Paid_Amount__c', 0);
                    clone.put(
                        'Pending_Amount__c',
                        demandAmount == null ? 0 : demandAmount
                    );
                    if (demandStatus == 'Paid' || demandStatus == 'Partially Paid') {
                        clone.put('Status__c', 'Raised');
                    }
                }
            }
            if (objectApiName == 'Receipt__c') {
                clone.put('New_Advance_Created__c', null);
                clone.put('Created_Advance__c', null);
            }
            for (String rf : refFields) {
                Id refVal = (Id) rec.get(rf);
                if (refVal != null && idRegistry.containsKey(refVal)) {
                    clone.put(rf, idRegistry.get(refVal));
                }
            }
            clones.add(clone);
        }
        insert clones;

        // Register old -> new Ids for objects cloned after this one
        for (Integer i = 0; i < fullRecords.size(); i++) {
            idRegistry.put(fullRecords[i].Id, clones[i].Id);
        }
    }

    /**
     * @description Second pass after all cloning: patch lookups on cloned records whose targets
     * were cloned later in the dependency order.
     */
    private static void fixupStaleReferences(Id newBookingId, Map<Id, Id> idRegistry) {
        List<SObject> toUpdate = new List<SObject>();

        for (ChildCloneConfig config : getChildCloneConfigs()) {
            collectStaleReferenceFixes(config.objectApiName, config.bookingLookupField,
                                       newBookingId, idRegistry, toUpdate);
            if (config.lineItemObjectApiName != null) {
                collectStaleReferenceFixes(config.lineItemObjectApiName,
                                           config.lineItemBookingLookupField,
                                           newBookingId, idRegistry, toUpdate);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static void collectStaleReferenceFixes(String objectApiName, String bookingField,
                                                   Id newBookingId, Map<Id, Id> idRegistry,
                                                   List<SObject> toUpdate) {
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        if (sType == null) return;
        Map<String, Schema.SObjectField> fieldMap = sType.getDescribe().fields.getMap();

        List<String> refFields = new List<String>();
        for (String f : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(f).getDescribe();
            if (dfr.getType() == Schema.DisplayType.REFERENCE && dfr.isUpdateable()) {
                refFields.add(f);
            }
        }
        if (refFields.isEmpty()) return;

        String query = 'SELECT Id, ' + String.join(refFields, ', ') +
                       ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                       ' WHERE ' + String.escapeSingleQuotes(bookingField) + ' = :newBookingId';

        for (SObject rec : Database.query(query)) {
            Boolean changed = false;
            for (String rf : refFields) {
                Id refVal = (Id) rec.get(rf);
                if (refVal != null && idRegistry.containsKey(refVal)) {
                    rec.put(rf, idRegistry.get(refVal));
                    changed = true;
                }
            }
            if (changed) {
                toUpdate.add(rec);
            }
        }
    }

    // ==================== TRANSFER FILES ====================

    private static void transferFiles(Id oldBookingId, Id newBookingId) {
        // Get all ContentDocumentLinks for the old booking
        List<ContentDocumentLink> existingLinks = [
            SELECT ContentDocumentId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :oldBookingId
        ];

        if (existingLinks.isEmpty()) return;

        // Create new links for the new booking
        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
        for (ContentDocumentLink link : existingLinks) {
            newLinks.add(new ContentDocumentLink(
                ContentDocumentId = link.ContentDocumentId,
                LinkedEntityId = newBookingId,
                ShareType = link.ShareType,
                Visibility = link.Visibility
            ));
        }
        insert newLinks;
    }
}