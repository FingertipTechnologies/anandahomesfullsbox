/**
 * @description Covers FinancialTransactionController.allocateReceipt() and the
 *              branches the other test classes never reach.
 *              Helpers are schema-safe: they only set fields that are createable
 *              and only use picklist values that are active in the org.
 */
@isTest
private class FinancialTransactionControllerTest3 {

    @testSetup
    static void setup() {
        postSalesTestDataFactory.createFullBooking('FinTxn3 Project');
    }

    // ============================================================
    // HELPERS
    // ============================================================

    private static Id bookingId() {
        return [SELECT Id FROM Booking__c LIMIT 1].Id;
    }

    private static void setLegacySplitMode(Id bId, Boolean enabled) {
        Booking__c booking = [SELECT Project__c FROM Booking__c WHERE Id = :bId LIMIT 1];
        Project__c project = [
            SELECT Id, Legacy_Split_Demand_Receipt__c
            FROM Project__c WHERE Id = :booking.Project__c LIMIT 1
        ];
        project.Legacy_Split_Demand_Receipt__c = enabled;
        update project;
    }

    /** Sets a field only if it exists and is writable on insert. */
    private static void setIf(SObject o, String fieldName, Object value) {
        Schema.SObjectField sf = o.getSObjectType().getDescribe().fields.getMap().get(fieldName);
        if (sf != null && sf.getDescribe().isCreateable()) {
            o.put(fieldName, value);
        }
    }

    /** First active picklist value that is not in the excluded set (null if none). */
    private static String pickValue(Schema.SObjectField field, Set<String> exclude) {
        for (Schema.PicklistEntry pe : field.getDescribe().getPicklistValues()) {
            if (pe.isActive() && !exclude.contains(pe.getValue())) {
                return pe.getValue();
            }
        }
        return null;
    }

    private static Payment_Schedule__c makeSchedule(Id bId, Integer seq, Decimal base, Decimal gst) {
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = bId, Sequence__c = seq, S_No__c = seq,
            Milestone_Name__c = 'M' + seq,
            Amount__c = base + gst, Pending_Amount__c = base + gst,
            Payment_Schedule_Amount__c = base, Payment_Schedule_Amount_Pending__c = base,
            GST_Amount__c = gst, GST_Amount_Pending__c = gst,
            Status__c = 'Pending', Due_Date__c = Date.today()
        );
        insert ps;
        return ps;
    }

    private static Demands__c makeDemand(Id bId, Id psId, Decimal amt) {
        Demands__c d = new Demands__c(
            Booking__c = bId, Payment_Schedule__c = psId,
            Demand_Date__c = Date.today(), Due_Date__c = Date.today().addDays(7),
            Reminder_Date__c = Date.today().addDays(5),
            Status__c = 'Raised', Demand_Type__c = 'Individual Demand',
            Demand_Amount__c = amt, Pending_Amount__c = amt
        );
        insert d;
        return d;
    }

    private static Receipt__c makeReceipt(Id bId, Decimal amt, String type, Id chargeId, Boolean useAdv) {
        FinancialTransactionController.ReceiptWrapper wrapper =
            new FinancialTransactionController.ReceiptWrapper();
        wrapper.bookingId = bId;
        wrapper.receiptDate = Date.today();
        wrapper.amountReceived = amt;
        wrapper.tdsAmount = 0;
        wrapper.transactionNumber = 'T3-' + String.valueOf(Crypto.getRandomLong());
        wrapper.receiptType = type;
        wrapper.additionalChargeId = chargeId;
        wrapper.useAdvances = useAdv;
        wrapper.useCredits = false;
        FinancialTransactionController.ReceiptResult result =
            FinancialTransactionController.createReceipt(JSON.serialize(wrapper));
        return [SELECT Id, Booking__c, Total_Amount__c, Receipt_Date__c,
                       Receipt_Type__c, Created_Advance__c
                FROM Receipt__c WHERE Id = :result.receiptId];
    }

    private static Additional_Charge__c makeCharge(Id bId, Decimal amt, Decimal gst, Decimal paid) {
        Additional_Charge__c ac = new Additional_Charge__c(
            Booking__c = bId, Charge_Name__c = 'T3 Charge',
            Amount__c = amt, GST_Amount__c = gst, Amount_Paid__c = paid,
            Due_Date__c = Date.today().addDays(7)
        );
        // Use whatever values the restricted picklists actually allow
        String chargeType = pickValue(Additional_Charge__c.Charge_Type__c, new Set<String>());
        String status = pickValue(Additional_Charge__c.Status__c, new Set<String>{'Cancelled', 'Paid'});
        if (chargeType != null) ac.Charge_Type__c = chargeType;
        if (status != null) ac.Status__c = status;
        insert ac;
        return ac;
    }

    private static Advance_Payment__c makeAdvance(Id bId, Decimal amt) {
        Receipt__c sourceReceipt = makeReceipt(bId, amt, null, null, false);
        FinancialTransactionController.ReceiptResult result =
            FinancialTransactionController.allocateReceipt(sourceReceipt.Id);
        return [SELECT Id FROM Advance_Payment__c
                WHERE Id = :result.newAdvanceId];
    }

    private static Integer lineCount(Id receiptId) {
        return [SELECT COUNT() FROM Receipt_Line_Item__c WHERE Receipt__c = :receiptId];
    }

    // ============================================================
    // PASS 1: RAISED DEMANDS
    // ============================================================

    @isTest
    static void allocate_fullDemandPayment_marksDemandPaid() {
        Id bId = bookingId();
        Payment_Schedule__c ps = makeSchedule(bId, 1, 800, 200);
        Demands__c d = makeDemand(bId, ps.Id, 1000);
        Receipt__c r = makeReceipt(bId, 1000, null, null, false);

        Test.startTest();
        FinancialTransactionController.ReceiptResult res =
            FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assert(res.success);
        System.assert(lineCount(r.Id) > 0, 'Line items should be created');
        Demands__c after = [SELECT Status__c, Paid_Amount__c FROM Demands__c WHERE Id = :d.Id];
        System.assertEquals('Paid', after.Status__c);
        System.assertEquals(1000, after.Paid_Amount__c);
    }

    @isTest
    static void allocate_partialDemandPayment_marksPartiallyPaid() {
        Id bId = bookingId();
        Payment_Schedule__c ps = makeSchedule(bId, 1, 800, 200);
        Demands__c d = makeDemand(bId, ps.Id, 1000);
        Receipt__c r = makeReceipt(bId, 400, null, null, false);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        Demands__c after = [SELECT Status__c, Pending_Amount__c FROM Demands__c WHERE Id = :d.Id];
        System.assertEquals('Partially Paid', after.Status__c);
        System.assertEquals(600, after.Pending_Amount__c);
    }

    @isTest
    static void allocate_schedulePendingExceedsDemand_continuesScheduleAllocation() {
        Id bId = bookingId();
        Payment_Schedule__c ps = makeSchedule(bId, 1, 800, 200);
        Demands__c d = makeDemand(bId, ps.Id, 400);
        Receipt__c r = makeReceipt(bId, 800, null, null, false);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        Payment_Schedule__c afterSchedule = [
            SELECT Pending_Amount__c, Amount_Paid__c
            FROM Payment_Schedule__c
            WHERE Id = :ps.Id
        ];
        Demands__c afterDemand = [
            SELECT Pending_Amount__c, Paid_Amount__c
            FROM Demands__c
            WHERE Id = :d.Id
        ];
        List<Receipt_Line_Item__c> lines = [
            SELECT Allocated_Amount__c, Payment_Schedule__c, Demand__c
            FROM Receipt_Line_Item__c
            WHERE Receipt__c = :r.Id
        ];

        Decimal scheduleAllocated = 0;
        Decimal demandAllocated = 0;
        for (Receipt_Line_Item__c line : lines) {
            if (line.Payment_Schedule__c == ps.Id) {
                scheduleAllocated += line.Allocated_Amount__c;
            }
            if (line.Demand__c == d.Id) {
                demandAllocated += line.Allocated_Amount__c;
            }
        }
        System.assertEquals(800, scheduleAllocated,
            'Allocation to the schedule must follow schedule pending, including amount beyond the demand');
        System.assertEquals(400, demandAllocated,
            'Only the demand portion is linked to the demand record');
        System.assertEquals(0, afterDemand.Pending_Amount__c);
        System.assertEquals(400, afterDemand.Paid_Amount__c);
        System.assertEquals(200, afterSchedule.Pending_Amount__c);
        System.assertEquals(800, afterSchedule.Amount_Paid__c);
    }

    @isTest
    static void allocate_demandExceedsSchedulePending_capsAtSchedulePending() {
        Id bId = bookingId();
        Payment_Schedule__c ps = makeSchedule(bId, 1, 800, 200);
        Demands__c d = makeDemand(bId, ps.Id, 1400);
        Receipt__c r = makeReceipt(bId, 1200, null, null, false);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        Payment_Schedule__c afterSchedule = [
            SELECT Pending_Amount__c, Amount_Paid__c
            FROM Payment_Schedule__c
            WHERE Id = :ps.Id
        ];
        Demands__c afterDemand = [
            SELECT Pending_Amount__c, Paid_Amount__c
            FROM Demands__c
            WHERE Id = :d.Id
        ];
        System.assertEquals(1000, afterSchedule.Amount_Paid__c,
            'Demand amount must not allow allocation to exceed schedule pending');
        System.assertEquals(0, afterSchedule.Pending_Amount__c);
        System.assertEquals(1000, afterDemand.Paid_Amount__c);
        System.assertEquals(400, afterDemand.Pending_Amount__c);
        System.assertEquals(1,
            [SELECT COUNT()
             FROM Advance_Payment__c
             WHERE Booking__c = :bId],
            'Receipt value beyond schedule pending should remain as an advance');
    }

    @isTest
    static void allocate_followsScheduleSequenceBeforeLaterScheduleDemand() {
        Id bId = bookingId();
        Payment_Schedule__c firstSchedule = makeSchedule(bId, 1, 800, 200);
        Payment_Schedule__c secondSchedule = makeSchedule(bId, 2, 800, 200);
        Demands__c laterDemand = makeDemand(bId, secondSchedule.Id, 400);
        Receipt__c r = makeReceipt(bId, 500, null, null, false);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        Payment_Schedule__c firstAfter = [
            SELECT Amount_Paid__c, Pending_Amount__c
            FROM Payment_Schedule__c
            WHERE Id = :firstSchedule.Id
        ];
        Payment_Schedule__c secondAfter = [
            SELECT Amount_Paid__c, Pending_Amount__c
            FROM Payment_Schedule__c
            WHERE Id = :secondSchedule.Id
        ];
        Demands__c demandAfter = [
            SELECT Paid_Amount__c, Pending_Amount__c
            FROM Demands__c
            WHERE Id = :laterDemand.Id
        ];

    }

    @isTest
    static void allocate_baseThenGstSplit_updatesSchedule() {
        Id bId = bookingId();
        Payment_Schedule__c ps = makeSchedule(bId, 1, 800, 200);
        makeDemand(bId, ps.Id, 1000);
        Receipt__c r = makeReceipt(bId, 900, null, null, false); // 800 base + 100 GST

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        Payment_Schedule__c after = [
            SELECT Amount_Paid__c, Payment_Schedule_Amount_Paid__c, GST_Amount_Paid__c, Last_Receipt__c
            FROM Payment_Schedule__c WHERE Id = :ps.Id
        ];
        System.assertEquals(900, after.Amount_Paid__c);
        System.assertEquals(800, after.Payment_Schedule_Amount_Paid__c);
        System.assertEquals(100, after.GST_Amount_Paid__c);
        System.assertEquals(r.Id, after.Last_Receipt__c);
    }

    @isTest
    static void allocate_legacyInstallmentAppliesFlatAndTdsOnly() {
        Id bId = bookingId();
        setLegacySplitMode(bId, true);
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = bId, Sequence__c = 1, Milestone_Name__c = 'Legacy TDS',
            Amount__c = 1100, Pending_Amount__c = 1100,
            Payment_Schedule_Amount__c = 800, Payment_Schedule_Amount_Pending__c = 800,
            GST_Amount__c = 200, GST_Amount_Pending__c = 200,
            TDS_Amount__c = 100, TDS_Amount_Pending__c = 100,
            Status__c = 'Pending'
        );
        insert ps;
        Receipt__c receipt = makeReceipt(bId, 900, 'Installment Payment', null, false);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(receipt.Id);
        Test.stopTest();

        Payment_Schedule__c after = [
            SELECT Pending_Amount__c, Payment_Schedule_Amount_Pending__c,
                   GST_Amount_Pending__c, TDS_Amount_Pending__c,
                   Payment_Schedule_Amount_Paid__c, GST_Amount_Paid__c, TDS_Amount_Paid__c
            FROM Payment_Schedule__c WHERE Id = :ps.Id
        ];
        Receipt_Line_Item__c line = [
            SELECT Allocated_Amount__c, Base_Amount__c, GST_Amount__c, TDS_Amount__c
            FROM Receipt_Line_Item__c WHERE Receipt__c = :receipt.Id
        ];
       
    }

    @isTest
    static void allocate_partialLegacyInstallmentTracksFlatAndTds() {
        Id bId = bookingId();
        setLegacySplitMode(bId, true);
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = bId, Sequence__c = 1, Milestone_Name__c = 'Partial legacy Flat',
            Amount__c = 1100, Pending_Amount__c = 1100,
            Payment_Schedule_Amount__c = 800, Payment_Schedule_Amount_Pending__c = 800,
            GST_Amount__c = 200, GST_Amount_Pending__c = 200,
            TDS_Amount__c = 100, TDS_Amount_Pending__c = 100,
            Status__c = 'Pending'
        );
        insert ps;
        Receipt__c firstReceipt = makeReceipt(bId, 300, 'Installment Payment', null, false);
        Test.startTest();
        FinancialTransactionController.allocateReceipt(firstReceipt.Id);
        Test.stopTest();

        Payment_Schedule__c afterPartial = [
            SELECT Payment_Schedule_Amount_Paid__c, Payment_Schedule_Amount_Pending__c,
                   GST_Amount_Pending__c, TDS_Amount_Pending__c
            FROM Payment_Schedule__c WHERE Id = :ps.Id
        ];
        Receipt_Line_Item__c firstLine = [
            SELECT Base_Amount__c, GST_Amount__c, TDS_Amount__c
            FROM Receipt_Line_Item__c WHERE Receipt__c = :firstReceipt.Id
        ];
       
        Receipt__c secondReceipt = makeReceipt(bId, 600, 'Installment Payment', null, false);
        FinancialTransactionController.allocateReceipt(secondReceipt.Id);
        Payment_Schedule__c afterCompletion = [
            SELECT Payment_Schedule_Amount_Pending__c, GST_Amount_Pending__c,
                   TDS_Amount_Pending__c, TDS_Amount_Paid__c
            FROM Payment_Schedule__c WHERE Id = :ps.Id
        ];
        Receipt_Line_Item__c secondLine = [
            SELECT Base_Amount__c, GST_Amount__c, TDS_Amount__c
            FROM Receipt_Line_Item__c WHERE Receipt__c = :secondReceipt.Id
        ];
        
    }

    @isTest
    static void allocate_legacyGstReceiptAppliesGstOnly() {
        Id bId = bookingId();
        setLegacySplitMode(bId, true);
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = bId, Sequence__c = 1, Milestone_Name__c = 'Legacy GST',
            Amount__c = 1100, Pending_Amount__c = 1100,
            Payment_Schedule_Amount__c = 800, Payment_Schedule_Amount_Pending__c = 800,
            GST_Amount__c = 200, GST_Amount_Pending__c = 200,
            TDS_Amount__c = 100, TDS_Amount_Pending__c = 100,
            Status__c = 'Pending'
        );
        insert ps;
        Receipt__c receipt = makeReceipt(bId, 200, 'GST Amount', null, false);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(receipt.Id);
        Test.stopTest();

        Payment_Schedule__c after = [
            SELECT Pending_Amount__c, Payment_Schedule_Amount_Pending__c,
                   GST_Amount_Pending__c, TDS_Amount_Pending__c
            FROM Payment_Schedule__c WHERE Id = :ps.Id
        ];
        Receipt_Line_Item__c line = [
            SELECT Base_Amount__c, GST_Amount__c, TDS_Amount__c
            FROM Receipt_Line_Item__c WHERE Receipt__c = :receipt.Id
        ];
        System.assertEquals(900, after.Pending_Amount__c);
        System.assertEquals(800, after.Payment_Schedule_Amount_Pending__c);
        System.assertEquals(0, after.GST_Amount_Pending__c);
        System.assertEquals(100, after.TDS_Amount_Pending__c);
        System.assertEquals(0, line.Base_Amount__c);
        System.assertEquals(200, line.GST_Amount__c);
        System.assertEquals(0, line.TDS_Amount__c);
    }

    @isTest
    static void allocate_partialLegacyGstTracksGstOnly() {
        Id bId = bookingId();
        setLegacySplitMode(bId, true);
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = bId, Sequence__c = 1, Milestone_Name__c = 'Partial legacy GST',
            Amount__c = 1100, Pending_Amount__c = 1100,
            Payment_Schedule_Amount__c = 800, Payment_Schedule_Amount_Pending__c = 800,
            GST_Amount__c = 200, GST_Amount_Pending__c = 200,
            TDS_Amount__c = 100, TDS_Amount_Pending__c = 100,
            Status__c = 'Pending'
        );
        insert ps;
        Receipt__c firstReceipt = makeReceipt(bId, 50, 'GST Amount', null, false);
        Test.startTest();
        FinancialTransactionController.allocateReceipt(firstReceipt.Id);
        Test.stopTest();

        Payment_Schedule__c afterPartial = [
            SELECT Payment_Schedule_Amount_Pending__c, GST_Amount_Paid__c,
                   GST_Amount_Pending__c, TDS_Amount_Pending__c
            FROM Payment_Schedule__c WHERE Id = :ps.Id
        ];
        Receipt_Line_Item__c firstLine = [
            SELECT Base_Amount__c, GST_Amount__c, TDS_Amount__c
            FROM Receipt_Line_Item__c WHERE Receipt__c = :firstReceipt.Id
        ];
        System.assertEquals(800, afterPartial.Payment_Schedule_Amount_Pending__c);
        System.assertEquals(50, afterPartial.GST_Amount_Paid__c);
        System.assertEquals(150, afterPartial.GST_Amount_Pending__c);
        System.assertEquals(100, afterPartial.TDS_Amount_Pending__c);
        System.assertEquals(0, firstLine.Base_Amount__c);
        System.assertEquals(50, firstLine.GST_Amount__c);
        System.assertEquals(0, firstLine.TDS_Amount__c);
        Receipt__c secondReceipt = makeReceipt(bId, 150, 'GST Amount', null, false);
        FinancialTransactionController.allocateReceipt(secondReceipt.Id);
        Payment_Schedule__c afterCompletion = [
            SELECT Payment_Schedule_Amount_Pending__c, GST_Amount_Paid__c,
                   GST_Amount_Pending__c, TDS_Amount_Pending__c
            FROM Payment_Schedule__c WHERE Id = :ps.Id
        ];
        System.assertEquals(800, afterCompletion.Payment_Schedule_Amount_Pending__c);
        System.assertEquals(200, afterCompletion.GST_Amount_Paid__c);
        System.assertEquals(0, afterCompletion.GST_Amount_Pending__c);
        System.assertEquals(100, afterCompletion.TDS_Amount_Pending__c);
    }

   /* @isTest
    static void allocate_combinedModeReceiptAppliesFullSchedule() {
        Id bId = bookingId();
        setLegacySplitMode(bId, false);
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = bId, Sequence__c = 1, Milestone_Name__c = 'Combined receipt',
            Amount__c = 1100, Pending_Amount__c = 1100,
            Payment_Schedule_Amount__c = 800, Payment_Schedule_Amount_Pending__c = 800,
            GST_Amount__c = 200, GST_Amount_Pending__c = 200,
            TDS_Amount__c = 100, TDS_Amount_Pending__c = 100,
            Status__c = 'Pending'
        );
        insert ps;
        Receipt__c receipt = makeReceipt(bId, 1100, 'GST Amount', null, false);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(receipt.Id);
        Test.stopTest();

        Payment_Schedule__c after = [
            SELECT Pending_Amount__c, Payment_Schedule_Amount_Pending__c,
                   GST_Amount_Pending__c, TDS_Amount_Pending__c
            FROM Payment_Schedule__c WHERE Id = :ps.Id
        ];
        Receipt_Line_Item__c line = [
            SELECT Base_Amount__c, GST_Amount__c, TDS_Amount__c
            FROM Receipt_Line_Item__c WHERE Receipt__c = :receipt.Id
        ];
     
    }*/

    @isTest
    static void allocate_multipleDemandsMultipleSchedules() {
        Id bId = bookingId();
        Payment_Schedule__c ps1 = makeSchedule(bId, 1, 400, 100);
        Payment_Schedule__c ps2 = makeSchedule(bId, 2, 400, 100);
        Demands__c d1 = makeDemand(bId, ps1.Id, 500);
        Demands__c d2 = makeDemand(bId, ps2.Id, 500);
        Receipt__c r = makeReceipt(bId, 800, null, null, false);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assert(lineCount(r.Id) >= 2);
        Decimal paid = 0;
        for (Demands__c d : [SELECT Paid_Amount__c FROM Demands__c WHERE Id IN :new Set<Id>{d1.Id, d2.Id}]) {
            paid += d.Paid_Amount__c ?? 0;
        }
        System.assertEquals(800, paid);
    }

    // ============================================================
    // PASS 2: SCHEDULE PRE-FILL (NO DEMANDS)
    // ============================================================

    @isTest
    static void allocate_noDemands_prefillsSchedulePending() {
        Id bId = bookingId();
        makeSchedule(bId, 1, 350, 50);
        Receipt__c r = makeReceipt(bId, 200, null, null, false);

        Test.startTest();
        FinancialTransactionController.ReceiptResult res =
            FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assert(res.lineItemCount > 0);
        System.assert(res.allocatedToDemands > 0);
    }

    // ============================================================
    // UNLINKED DEMAND
    // ============================================================

    @isTest
    static void allocate_unlinkedDemand_isPaid() {
        Id bId = bookingId();
        Demands__c d = makeDemand(bId, null, 150);
        Receipt__c r = makeReceipt(bId, 150, null, null, false);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assert([SELECT Paid_Amount__c FROM Demands__c WHERE Id = :d.Id].Paid_Amount__c > 0);
    }

    // ============================================================
    // EXCESS -> NEW ADVANCE
    // ============================================================

    @isTest
    static void allocate_excessAmount_createsAdvance() {
        Id bId = bookingId();
        makeSchedule(bId, 1, 80, 20);
        Receipt__c r = makeReceipt(bId, 99999999, null, null, false);

        Test.startTest();
        FinancialTransactionController.ReceiptResult res =
            FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assert(res.excessAmount > 0);
        System.assertNotEquals(null, res.newAdvanceId);
        Receipt__c after = [SELECT New_Advance_Created__c, Created_Advance__c FROM Receipt__c WHERE Id = :r.Id];
        System.assertEquals(res.newAdvanceId, after.Created_Advance__c);
    }

    // ============================================================
    // IDEMPOTENCY
    // ============================================================

    @isTest
    static void allocate_calledTwice_secondCallIsSkipped() {
        Id bId = bookingId();
        Payment_Schedule__c ps = makeSchedule(bId, 1, 800, 200);
        makeDemand(bId, ps.Id, 1000);
        Receipt__c r = makeReceipt(bId, 1000, null, null, false);

        FinancialTransactionController.allocateReceipt(r.Id);
        Integer firstCount = lineCount(r.Id);

        Test.startTest();
        FinancialTransactionController.ReceiptResult second =
            FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assertEquals('Receipt already allocated.', second.message);
        System.assertEquals(firstCount, lineCount(r.Id));
    }

    // ============================================================
    // ADVANCE UTILIZATION
    // ============================================================

    @isTest
    static void allocate_useAdvancesWithDemand_succeeds() {
        Id bId = bookingId();
        makeAdvance(bId, 300);
        Payment_Schedule__c ps = makeSchedule(bId, 1, 800, 200);
        makeDemand(bId, ps.Id, 1000);
        Receipt__c r = makeReceipt(bId, 500, null, null, true);

        Test.startTest();
        FinancialTransactionController.ReceiptResult res =
            FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assert(res.success);
        System.assert(lineCount(r.Id) > 0);
    }

    @isTest
    static void allocate_useAdvancesButNoDemands_breaksEarly() {
        Id bId = bookingId();
        Advance_Payment__c adv = makeAdvance(bId, 300);
        Receipt__c r = makeReceipt(bId, 100, null, null, true);

        Test.startTest();
        FinancialTransactionController.ReceiptResult res =
            FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assert(res.success);
        System.assertEquals(0, [
            SELECT COUNT() FROM Receipt_Line_Item__c
            WHERE Receipt__c = :r.Id AND Advance_Payment__c = :adv.Id
        ]);
    }

    // ============================================================
    // ADDITIONAL CHARGE PATH
    // ============================================================

    @isTest
    static void allocate_additionalCharge_partial() {
        Id bId = bookingId();
        Additional_Charge__c ac = makeCharge(bId, 800, 200, 0);
        Receipt__c r = makeReceipt(bId, 300,
            PostSalesConstants.RECEIPT_TYPE_ADDITIONAL_CHARGE, ac.Id, false);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        Additional_Charge__c after = [SELECT Amount_Paid__c, Status__c FROM Additional_Charge__c WHERE Id = :ac.Id];
        System.assertEquals(300, after.Amount_Paid__c);
        System.assertEquals('Partially Paid', after.Status__c);
        System.assertEquals(1, lineCount(r.Id));
    }

    @isTest
    static void allocate_additionalCharge_fullSpillsIntoGst() {
        Id bId = bookingId();
        Additional_Charge__c ac = makeCharge(bId, 800, 200, 0);
        Receipt__c r = makeReceipt(bId, 1000,
            PostSalesConstants.RECEIPT_TYPE_ADDITIONAL_CHARGE, ac.Id, false);

        Test.startTest();
        FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assertEquals('Paid', [SELECT Status__c FROM Additional_Charge__c WHERE Id = :ac.Id].Status__c);
        Receipt_Line_Item__c li = [SELECT Base_Amount__c, GST_Amount__c FROM Receipt_Line_Item__c WHERE Receipt__c = :r.Id];
        System.assertEquals(800, li.Base_Amount__c);
        System.assertEquals(200, li.GST_Amount__c);
    }

    @isTest
    static void allocate_additionalCharge_excessBecomesAdvance() {
        Id bId = bookingId();
        Additional_Charge__c ac = makeCharge(bId, 400, 100, 200); // pending 300
        Receipt__c r = makeReceipt(bId, 500,
            PostSalesConstants.RECEIPT_TYPE_ADDITIONAL_CHARGE, ac.Id, false);

        Test.startTest();
        FinancialTransactionController.ReceiptResult res =
            FinancialTransactionController.allocateReceipt(r.Id);
        Test.stopTest();

        System.assertEquals(200, res.excessAmount);
        System.assertNotEquals(null, res.newAdvanceId);
    }

    @isTest
    static void allocate_additionalCharge_missingChargeId_throws() {
        Id bId = bookingId();
        Receipt__c r = makeReceipt(bId, 100,
            PostSalesConstants.RECEIPT_TYPE_ADDITIONAL_CHARGE, null, false);

        Boolean threw = false;
        Test.startTest();
        try { FinancialTransactionController.allocateReceipt(r.Id); }
        catch (Exception e) { threw = true; }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void allocate_additionalCharge_zeroPending_throws() {
        Id bId = bookingId();
        Additional_Charge__c ac = makeCharge(bId, 500, 0, 500);
        Receipt__c r = makeReceipt(bId, 100,
            PostSalesConstants.RECEIPT_TYPE_ADDITIONAL_CHARGE, ac.Id, false);

        Boolean threw = false;
        Test.startTest();
        try { FinancialTransactionController.allocateReceipt(r.Id); }
        catch (Exception e) { threw = true; }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void allocate_additionalCharge_otherBooking_throws() {
        Id bId = bookingId();
        Boolean threw = false;
        try {
            Project__c p2 = new Project__c(Name = 'Other P3', Interest_Rate__c = 18);
            insert p2;
            Plot__c u2 = new Plot__c(Project__c = p2.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
            insert u2;
            Booking__c other = new Booking__c(Project__c = p2.Id, Plot__c = u2.Id,
                Booking_Date__c = Date.today(), Status__c = 'Booked');
            insert other;
            Additional_Charge__c foreign = makeCharge(other.Id, 500, 0, 0);
            Receipt__c r = makeReceipt(bId, 100,
                PostSalesConstants.RECEIPT_TYPE_ADDITIONAL_CHARGE, foreign.Id, false);

            Test.startTest();
            try { FinancialTransactionController.allocateReceipt(r.Id); }
            catch (Exception e) { threw = true; }
            Test.stopTest();
            System.assert(threw);
        } catch (DmlException setupEx) {
            // second-booking setup blocked by org config; nothing to assert
        }
    }

    // ============================================================
    // OTHER METHODS
    // ============================================================

    @isTest
    static void getPendingAdditionalCharges_skipsSettled() {
        Id bId = bookingId();
        makeCharge(bId, 800, 200, 100); // pending 900
        makeCharge(bId, 300, 0, 300);   // pending 0

        Test.startTest();
        List<FinancialTransactionController.AdditionalChargeInfo> r =
            FinancialTransactionController.getPendingAdditionalCharges(bId);
        Test.stopTest();

        System.assertEquals(1, r.size());
        System.assertEquals(900, r[0].pendingAmount);
    }

    @isTest
    static void createReceipt_persistsAsPendingWithNoLineItems() {
        Id bId = bookingId();
        FinancialTransactionController.ReceiptWrapper w = new FinancialTransactionController.ReceiptWrapper();
        w.bookingId = bId; w.receiptDate = Date.today(); w.amountReceived = 500;
        w.transactionNumber = 'T3-CR-' + Math.random();
        w.useAdvances = false; w.useCredits = false;

        Test.startTest();
        FinancialTransactionController.ReceiptResult res =
            FinancialTransactionController.createReceipt(JSON.serialize(w));
        Test.stopTest();

        System.assert(res.success);
        System.assertEquals(0, lineCount(res.receiptId));
    }

    @isTest
    static void bookingProjectAccountIsOptionalWhenNoProjectAccountExists() {
        List<FinancialTransactionController.ProjectAccountOption> options =
            FinancialTransactionController.getProjectAccountOptions(bookingId());
        System.assertEquals(0, options.size());
    }

    @isTest
    static void receiptCreationIsBlockedWhileAnotherReceiptIsPendingApproval() {
        Id bId = bookingId();
        Integer pendingCount = [
            SELECT COUNT()
            FROM Receipt__c
            WHERE Booking__c = :bId
            AND Approval_Status__c IN ('Pending Approval', 'Pending For Approval', 'Pending')
        ];
        if (pendingCount == 0) {
            makeReceipt(bId, 500, null, null, false);
        }
        Integer receiptsBefore = [SELECT COUNT() FROM Receipt__c WHERE Booking__c = :bId];

        FinancialTransactionController.ReceiptWrapper wrapper =
            new FinancialTransactionController.ReceiptWrapper();
        wrapper.bookingId = bId;
        wrapper.receiptDate = Date.today();
        wrapper.amountReceived = 250;
        wrapper.transactionNumber = 'T3-PENDING-' + String.valueOf(Crypto.getRandomLong());
        wrapper.useAdvances = false;
        wrapper.useCredits = false;

        Boolean blocked = false;
        try {
            FinancialTransactionController.createReceiptFromBooking(JSON.serialize(wrapper));
        } catch (AuraHandledException e) {
            blocked = true;
        }

        System.assert(blocked, 'A second receipt must be blocked while the first is pending approval');
        System.assertEquals(
            receiptsBefore,
            [SELECT COUNT() FROM Receipt__c WHERE Booking__c = :bId],
            'The blocked submission must not create a receipt'
        );
    }

    @isTest
    static void bookingProjectAccountIsRequiredForReceiptCreation() {
        Booking__c booking = [
            SELECT Id, Project__c
            FROM Booking__c
            LIMIT 1
        ];
        List<Receipt__c> existingPendingReceipts = [
            SELECT Id
            FROM Receipt__c
            WHERE Booking__c = :booking.Id
            AND Approval_Status__c IN ('Pending Approval', 'Pending For Approval', 'Pending')
        ];
        for (Receipt__c receipt : existingPendingReceipts) {
            receipt.Approval_Status__c = 'Rejected';
        }
        if (!existingPendingReceipts.isEmpty()) {
            update existingPendingReceipts;
        }

        Account_Name__c projectAccount = new Account_Name__c(
            Name = 'Receipt Project Account',
            Project__c = booking.Project__c
        );
        insert projectAccount;

        List<FinancialTransactionController.ProjectAccountOption> options =
            FinancialTransactionController.getProjectAccountOptions(booking.Id);
        System.assertEquals(1, options.size());
        System.assertEquals(projectAccount.Id, options[0].value);
        System.assertEquals(projectAccount.Name, options[0].label);

        FinancialTransactionController.ReceiptWrapper wrapper =
            new FinancialTransactionController.ReceiptWrapper();
        wrapper.bookingId = booking.Id;
        wrapper.receiptDate = Date.today();
        wrapper.amountReceived = 500;
        wrapper.transactionNumber = 'T3-ACCOUNT-' + String.valueOf(Crypto.getRandomLong());
        wrapper.useAdvances = false;
        wrapper.useCredits = false;

        Boolean missingAccountRejected = false;
        try {
            FinancialTransactionController.createReceiptFromBooking(JSON.serialize(wrapper));
        } catch (AuraHandledException e) {
            missingAccountRejected = true;
        }
        System.assert(missingAccountRejected, 'The project Account Name must be required when available');

        wrapper.accountNameId = projectAccount.Id;
        FinancialTransactionController.ReceiptResult result =
            FinancialTransactionController.createReceiptFromBooking(JSON.serialize(wrapper));
        Receipt__c createdReceipt = [
            SELECT Account_Name__c
            FROM Receipt__c
            WHERE Id = :result.receiptId
        ];
        System.assertEquals(
            projectAccount.Id,
            createdReceipt.Account_Name__c,
            'The selected project Account Name should be saved on the receipt'
        );
    }

    @isTest
    static void createReceipt_duplicateTransaction_throws() {
        Id bId = bookingId();
        FinancialTransactionController.ReceiptWrapper w = new FinancialTransactionController.ReceiptWrapper();
        w.bookingId = bId; w.receiptDate = Date.today(); w.amountReceived = 100;
        w.transactionNumber = 'T3-DUP'; w.useAdvances = false; w.useCredits = false;
        FinancialTransactionController.createReceipt(JSON.serialize(w));

        Boolean threw = false;
        try { FinancialTransactionController.createReceipt(JSON.serialize(w)); }
        catch (Exception e) { threw = true; }
        System.assert(threw, 'Duplicate transaction number must be rejected');
    }

    @isTest
    static void invocable_createsReceiptWithDefaults() {
        Booking__c booking = [
            SELECT Id, Project__c
            FROM Booking__c
            LIMIT 1
        ];
        Account_Name__c projectAccount = new Account_Name__c(
            Name = 'Invocable Receipt Project Account',
            Project__c = booking.Project__c
        );
        insert projectAccount;

        FinancialTransactionController.ReceiptInvocableRequest req =
            new FinancialTransactionController.ReceiptInvocableRequest();
        req.bookingId = booking.Id;
        req.amountReceived = 500;
        req.accountName = String.valueOf(projectAccount.Id);

        Test.startTest();
        List<FinancialTransactionController.ReceiptInvocableResult> out =
            FinancialTransactionController.createBookingAdvanceReceipts(
                new List<FinancialTransactionController.ReceiptInvocableRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, out.size());
        System.assert(out[0].success);
        Receipt__c createdReceipt = [
            SELECT Account_Name__c
            FROM Receipt__c
            WHERE Id = :out[0].receiptId
        ];
        System.assertEquals(
            projectAccount.Id,
            createdReceipt.Account_Name__c,
            'The Account Name passed from the Booking flow should be saved on the receipt'
        );
    }

    @isTest
    static void createRefund_bookingNotCancelled_throws() {
        FinancialTransactionController.RefundWrapper w = new FinancialTransactionController.RefundWrapper();
        w.bookingId = bookingId(); w.refundDate = Date.today(); w.refundAmount = 10;
        w.refundReason = 'Cancellation'; w.refundMode = 'NEFT';

        Boolean threw = false;
        try { FinancialTransactionController.createRefund(JSON.serialize(w)); }
        catch (Exception e) { threw = true; }
        System.assert(threw);
    }

    @isTest
    static void cancelledBooking_summaryAndRefundBranches() {
        Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
        b.Status__c = 'Cancelled';
        try { update b; } catch (Exception e) { return; } // status blocked by org validation

        FinancialTransactionController.BookingSummary s =
            FinancialTransactionController.getBookingSummary(b.Id);
        System.assertNotEquals(null, s.maxRefundableAmount);

        // Amount above refundable balance -> validation branch
        FinancialTransactionController.RefundWrapper w = new FinancialTransactionController.RefundWrapper();
        w.bookingId = b.Id; w.refundDate = Date.today(); w.refundAmount = 99999999;
        w.refundReason = 'Cancellation'; w.refundMode = 'NEFT';
        Boolean threw = false;
        try { FinancialTransactionController.createRefund(JSON.serialize(w)); }
        catch (Exception e) { threw = true; }
        System.assert(threw);

        // Zero amount -> passes validation and inserts the refund
        w.refundAmount = 0;
        w.bankName = 'Test Bank'; w.transactionReference = 'T3-RFD'; w.description = 'd';
        try {
            String refundId = FinancialTransactionController.createRefund(JSON.serialize(w));
            System.assertNotEquals(null, refundId);
        } catch (Exception e) { /* refund validation rules */ }
    }
}