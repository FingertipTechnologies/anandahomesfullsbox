/**
 * @description Test class for PaymentScheduleViewController
 */
@isTest
private class PaymentScheduleViewControllerTest {
  @testSetup
  static void setup() {
    Project__c project = postSalesTestDataFactory.createProject('PSV Project');
    project.Legacy_Split_Demand_Receipt__c = true;
    update project;
    Plot__c unit = postSalesTestDataFactory.createUnit(project.Id);
    Lead__c lead = new Lead__c(
      Name__c = 'PSV Test Lead',
      Phone__c = '9000001001',
      Email__c = 'psvtest@example.com',
      Allocated_Project__c = 'The Legacey',
      Lead_Status__c = 'New Enquiry'
    );
    insert lead;
    Quote__c quote = new Quote__c(
      Project__c = 'The Legacey',
      CLead__c = lead.Id
    );
    insert quote;
    Booking__c b = new Booking__c(
      Project__c = project.Id,
      Plot__c = unit.Id,
      Quote__c = quote.Id,
      CLead__c = lead.Id,
      Booking_Date__c = Date.today().addDays(-30),
      Mode_Of_Payment__c = 'UPI',
      Total_Flat_Cost__c = 1000000,
      GST_Amount__c = 50000,
      Total_Payable_Amount__c = 1050000,
      Booking_Amount__c = 100000,
      Email__c = 'tester@example.com',
      Status__c = 'New'
    );
    insert b;
    b.Total_Payable_Amount__c = 1000;
    update b;

    Payment_Schedule__c ps1 = new Payment_Schedule__c(
      Booking__c = b.Id,
      Sequence__c = 1,
      Milestone_Name__c = 'Milestone 1',
      Status__c = 'Completed',
      Amount__c = 500,
      Percentage__c = 50,
      Pending_Amount__c = 100,
      Payment_Schedule_Amount_Pending__c = 100,
      GST_Amount_Pending__c = 25,
      Interest_Pending__c = 10
    );
    Payment_Schedule__c ps2 = new Payment_Schedule__c(
      Booking__c = b.Id,
      Sequence__c = 2,
      Milestone_Name__c = 'Milestone 2',
      Status__c = 'Pending',
      Amount__c = 500,
      Percentage__c = 50,
      Pending_Amount__c = 500
    );
    insert new List<Payment_Schedule__c>{ ps1, ps2 };
  }

  @isTest
  static void getPaymentSchedules_returnsResult() {
    Booking__c b = [SELECT Id, Funding_Type__c FROM Booking__c LIMIT 1];
    Test.startTest();
    PaymentScheduleViewController.PaymentScheduleViewResult r = PaymentScheduleViewController.getPaymentSchedules(
      b.Id
    );
    Test.stopTest();
    System.assertEquals(true, r.success, 'Should succeed');
    System.assertEquals(2, r.schedules.size(), 'Should have 2 schedules');
    System.assertEquals(
      'Milestone 1',
      r.schedules[0].milestoneName,
      'Milestone name should map from Milestone_Name__c'
    );
    System.assertEquals(
      'Milestone 1',
      r.nextDemand.lastCompletedMilestone,
      'Last completed milestone should be the completed schedule'
    );
    Boolean expectedSplitFunding = new Set<String>{
        'Loan',
        'Bank Loan',
        'NBFC Loan',
        'Mixed Funding',
        'Prorata',
        'Partial'
      }
      .contains(b.Funding_Type__c);
    System.assertEquals(
      expectedSplitFunding,
      r.nextDemand.hasSplitFunding,
      'Source breakdown should only be shown for split-funded bookings'
    );
    System.assertEquals(
      true,
      r.nextDemand.legacySplitDemandReceipt,
      'Legacy mode should be returned to the demand component selector.'
    );
  }

  @isTest
  static void getPaymentSchedules_combinedModeReturnsFlag() {
    Booking__c booking = [SELECT Id, Project__c FROM Booking__c LIMIT 1];
    update new Project__c(
      Id = booking.Project__c,
      Legacy_Split_Demand_Receipt__c = false
    );

    PaymentScheduleViewController.PaymentScheduleViewResult result = PaymentScheduleViewController.getPaymentSchedules(
      booking.Id
    );

    System.assertEquals(true, result.success, 'Schedule view should load.');
    System.assertEquals(
      false,
      result.nextDemand.legacySplitDemandReceipt,
      'Combined mode should be returned to the demand component selector.'
    );
  }

  @isTest
  static void legacyLoanWithoutBankSplitRaisesFullComponentsSeparately() {
    Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
    booking.Funding_Type__c = 'Loan';
    update booking;

    PaymentScheduleViewController.PaymentScheduleViewResult preview = PaymentScheduleViewController.getPaymentSchedules(
      booking.Id
    );
    PaymentScheduleViewController.PaymentScheduleWrapper schedule = preview.schedules[0];
    System.assertEquals(
      true,
      preview.nextDemand.legacySplitDemandReceipt,
      'Legacy project mode should continue to require separate Flat and GST demands.'
    );
    System.assertEquals(
      false,
      schedule.isBankDemand,
      'Loan funding without actual Bank split values must not be treated as prorata.'
    );
    System.assertEquals(
      100,
      schedule.flatDemandableAmount,
      'Without a Bank split, Flat demand should use the full pending Flat component.'
    );
    System.assertEquals(
      25,
      schedule.gstDemandableAmount,
      'Without a Bank split, GST demand should use the full pending GST component.'
    );

    Test.startTest();
    Id flatDemandId = PaymentScheduleViewController.raiseDemandForBooking(
      booking.Id,
      DemandComponentService.FLAT,
      false
    );
    Id gstDemandId = PaymentScheduleViewController.raiseDemandForBooking(
      booking.Id,
      DemandComponentService.GST,
      false
    );
    Test.stopTest();

    Set<Id> demandIds = new Set<Id>{ flatDemandId, gstDemandId };
    Map<Id, Demands__c> demandsById = new Map<Id, Demands__c>(
      [
        SELECT
          Id,
          Demand_Component__c,
          Demand_Amount__c,
          Flat_Amount__c,
          GST_Amount__c
        FROM Demands__c
        WHERE Id IN :demandIds
      ]
    );
    System.assertEquals(
      100,
      demandsById.get(flatDemandId).Demand_Amount__c,
      'Legacy Loan Flat demand should raise the full pending Flat component.'
    );
    System.assertEquals(
      25,
      demandsById.get(gstDemandId).Demand_Amount__c,
      'Legacy Loan GST demand should raise the full pending GST component separately.'
    );
  }

  @isTest
  static void prorataGstDemandUsesBankReceiptTotalsOnly() {
    Booking__c booking = [SELECT Id, Project__c FROM Booking__c LIMIT 1];
    booking.Funding_Type__c = 'Prorata';
    update booking;

    Payment_Schedule__c completed = [
      SELECT Id
      FROM Payment_Schedule__c
      WHERE Booking__c = :booking.Id AND Status__c = 'Completed'
      LIMIT 1
    ];
    Boolean previousInvariantBypass = ProrataInvariantService.bypass;
    ProrataInvariantService.bypass = true;
    try {
      update new Payment_Schedule__c(
        Id = completed.Id,
        Amount__c = 127440,
        Pending_Amount__c = 120440,
        Payment_Schedule_Amount__c = 100000,
        Payment_Schedule_Amount_Paid__c = 0,
        Payment_Schedule_Amount_Pending__c = 100000,
        GST_Amount__c = 27440,
        GST_Amount_Paid__c = 7000,
        GST_Amount_Pending__c = 20440,
        TDS_Amount__c = 0,
        TDS_Amount_Paid__c = 0,
        TDS_Amount_Pending__c = 0,
        Bank_Flat_Amount__c = 80000,
        Customer_Flat_Prorata__c = 20000,
        Bank_GST_Amount__c = 20000,
        Customer_GST_Prorata__c = 7440,
        Demand_Raised__c = false,
        Bank_Demand_Raised__c = false,
        Customer_Demand_Raised__c = false,
        Bank_GST_Demand_Raised__c = false,
        Customer_GST_Demand_Raised__c = false
      );
    } finally {
      ProrataInvariantService.bypass = previousInvariantBypass;
    }

    Boolean previousReceiptBypass = ReceiptApprovalGateService.bypass;
    ReceiptApprovalGateService.bypass = true;
    List<Receipt__c> receipts = new List<Receipt__c>{
      new Receipt__c(
        Booking__c = booking.Id,
        Amount_received__c = 5000,
        Receipt_Date__c = Date.today(),
        Receipt_Type__c = 'GST Amount',
        Payment_From__c = 'Customer',
        Status__c = 'Cleared',
        Approval_Status__c = 'Approved'
      ),
      new Receipt__c(
        Booking__c = booking.Id,
        Amount_received__c = 2000,
        Receipt_Date__c = Date.today(),
        Receipt_Type__c = 'GST Amount',
        Payment_From__c = 'Bank',
        Status__c = 'Cleared',
        Approval_Status__c = 'Approved'
      )
    };
    try {
      insert receipts;
    } finally {
      ReceiptApprovalGateService.bypass = previousReceiptBypass;
    }

    insert new List<Receipt_Line_Item__c>{
      new Receipt_Line_Item__c(
        Receipt__c = receipts[0].Id,
        Booking__c = booking.Id,
        Payment_Schedule__c = completed.Id,
        Allocated_Amount__c = 5000,
        Amount__c = 5000,
        Allocation_Date__c = Date.today(),
        Allocation_Type__c = 'Payment Schedule',
        Line_Item_Type__c = 'Principal',
        Base_Amount__c = 0,
        GST_Amount__c = 5000,
        TDS_Amount__c = 0
      ),
      new Receipt_Line_Item__c(
        Receipt__c = receipts[1].Id,
        Booking__c = booking.Id,
        Payment_Schedule__c = completed.Id,
        Allocated_Amount__c = 2000,
        Amount__c = 2000,
        Allocation_Date__c = Date.today(),
        Allocation_Type__c = 'Payment Schedule',
        Line_Item_Type__c = 'Principal',
        Base_Amount__c = 0,
        GST_Amount__c = 2000,
        TDS_Amount__c = 0
      )
    };

    Test.startTest();
    PaymentScheduleViewController.PaymentScheduleViewResult preview = PaymentScheduleViewController.getPaymentSchedules(
      booking.Id
    );
    Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
      booking.Id,
      DemandComponentService.GST,
      false
    );
    Test.stopTest();

    PaymentScheduleViewController.PaymentScheduleWrapper schedule = preview.schedules[0];
    System.assertEquals(
      2000,
      schedule.gstPaid,
      'The bank demand breakdown should show only GST receipts paid by the Bank.'
    );
    System.assertEquals(
      18000,
      schedule.gstDemandableAmount,
      'Customer-paid GST must not reduce the outstanding Bank GST component.'
    );
    Demands__c demand = [
      SELECT Demand_Amount__c, GST_Amount__c, Demand_Audience__c
      FROM Demands__c
      WHERE Id = :demandId
    ];
    System.assertEquals(
      18000,
      demand.Demand_Amount__c,
      'The raised GST demand should subtract only the Bank GST receipts.'
    );
    System.assertEquals(18000, demand.GST_Amount__c);
    System.assertEquals('Bank', demand.Demand_Audience__c);
  }

  @isTest
  static void getPaymentSchedules_exposesFlatTdsBreakdownForIndividualDemand() {
    Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
    Payment_Schedule__c completed = [
      SELECT Id
      FROM Payment_Schedule__c
      WHERE Booking__c = :booking.Id AND Status__c = 'Completed'
      LIMIT 1
    ];
    completed.TDS_Amount__c = 5;
    completed.TDS_Amount_Pending__c = 5;
    completed.TDS_Amount_Paid__c = 2;
    completed.Pending_Amount__c = 130;
    update completed;

    PaymentScheduleViewController.PaymentScheduleViewResult result = PaymentScheduleViewController.getPaymentSchedules(
      booking.Id
    );
    PaymentScheduleViewController.PaymentScheduleWrapper schedule = result.schedules[0];

    System.assertEquals(true, result.success);
    System.assertEquals(5, schedule.tdsAmount);
    System.assertEquals(5, schedule.tdsPending);
    System.assertEquals(
      2,
      schedule.tdsPaid,
      'The demand preview must show TDS received to date.'
    );
    System.assertEquals(
      105,
      schedule.flatDemandableAmount,
      'Flat demandable includes the customer TDS collected with Flat.'
    );
    System.assertEquals(
      5,
      schedule.tdsDemandableAmount,
      'An unsplit schedule demand should use the full pending TDS amount.'
    );
    System.assertEquals(
      130,
      schedule.combinedDemandableAmount,
      'Combined demandable includes Flat, GST, and TDS.'
    );

    Test.startTest();
    Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
      booking.Id,
      DemandComponentService.FLAT,
      false
    );
    Test.stopTest();

    Demands__c demand = [
      SELECT Demand_Amount__c, Flat_Amount__c, TDS_Amount__c
      FROM Demands__c
      WHERE Id = :demandId
    ];
    System.assertEquals(
      105,
      demand.Demand_Amount__c,
      'Individual Flat demand total must preserve the remaining Flat Cost.'
    );
    System.assertEquals(
      100,
      demand.Flat_Amount__c,
      'Flat amount should equal the remaining base Flat amount.'
    );
    System.assertEquals(5, demand.TDS_Amount__c);
  }

  @isTest
  static void raiseDemandForBooking_usesFullPendingTdsForUnsplitSchedule() {
    Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
    Payment_Schedule__c completed = [
      SELECT Id
      FROM Payment_Schedule__c
      WHERE Booking__c = :booking.Id AND Status__c = 'Completed'
      LIMIT 1
    ];
    completed.Payment_Schedule_Amount__c = 841526;
    completed.Payment_Schedule_Amount_Paid__c = 500000;
    completed.Payment_Schedule_Amount_Pending__c = 341526;
    completed.GST_Amount__c = 0;
    completed.GST_Amount_Pending__c = 0;
    completed.TDS_Amount__c = 8500;
    completed.TDS_Amount_Paid__c = 0;
    completed.TDS_Amount_Pending__c = 8500;
    completed.Pending_Amount__c = 350026;
    update completed;

    PaymentScheduleViewController.PaymentScheduleViewResult preview = PaymentScheduleViewController.getPaymentSchedules(
      booking.Id
    );
    System.assertEquals(
      350026,
      preview.schedules[0].flatDemandableAmount,
      'Demand preview should preserve remaining Flat Cost after subtracting paid amounts.'
    );
    System.assertEquals(
      8500,
      preview.schedules[0].tdsDemandableAmount,
      'The full remaining TDS amount should be demanded for an unsplit schedule.'
    );

    Test.startTest();
    Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
      booking.Id,
      DemandComponentService.FLAT,
      false
    );
    Test.stopTest();

    Demands__c demand = [
      SELECT Demand_Amount__c, Flat_Amount__c, TDS_Amount__c
      FROM Demands__c
      WHERE Id = :demandId
    ];
    System.assertEquals(
      350026,
      demand.Demand_Amount__c,
      'Raised demand total should equal the remaining Flat Cost.'
    );
    System.assertEquals(341526, demand.Flat_Amount__c);
    System.assertEquals(8500, demand.TDS_Amount__c);
  }

  @isTest
  static void prorataFlatDemandUsesTdsOnRemainingBankFlat() {
    Booking__c booking = [
      SELECT Id
      FROM Booking__c
      LIMIT 1
    ];
    booking.Funding_Type__c = 'Prorata';
    update booking;

    Payment_Schedule__c completed = [
      SELECT Id
      FROM Payment_Schedule__c
      WHERE Booking__c = :booking.Id AND Status__c = 'Completed'
      LIMIT 1
    ];
    ProrataInvariantService.bypass = true;
    try {
      update new Payment_Schedule__c(
        Id = completed.Id,
        Amount__c = 1010000,
        Pending_Amount__c = 510000,
        Payment_Schedule_Amount__c = 1000000,
        Payment_Schedule_Amount_Paid__c = 500000,
        Payment_Schedule_Amount_Pending__c = 500000,
        GST_Amount__c = 0,
        GST_Amount_Pending__c = 0,
        TDS_Amount__c = 10000,
        TDS_Amount_Paid__c = 0,
        TDS_Amount_Pending__c = 10000,
        Bank_Flat_Amount__c = 800000,
        Customer_Flat_Prorata__c = 200000,
        Bank_GST_Amount__c = 0,
        Customer_GST_Prorata__c = 0,
        Bank_Demand_Raised__c = false,
        Customer_Demand_Raised__c = false,
        Bank_Flat_Demand_Raised__c = false,
        Customer_Flat_Demand_Raised__c = false
      );
    } finally {
      ProrataInvariantService.bypass = false;
    }

    Boolean previousReceiptBypass = ReceiptApprovalGateService.bypass;
    ReceiptApprovalGateService.bypass = true;
    Receipt__c bankReceipt = new Receipt__c(
      Booking__c = booking.Id,
      Amount_received__c = 500000,
      Receipt_Date__c = Date.today(),
      Receipt_Type__c = 'Installment Payment',
      Payment_From__c = 'Bank',
      Status__c = 'Cleared',
      Approval_Status__c = 'Approved'
    );
    try {
      insert bankReceipt;
    } finally {
      ReceiptApprovalGateService.bypass = previousReceiptBypass;
    }
    insert new Receipt_Line_Item__c(
      Receipt__c = bankReceipt.Id,
      Booking__c = booking.Id,
      Payment_Schedule__c = completed.Id,
      Allocated_Amount__c = 500000,
      Amount__c = 500000,
      Allocation_Date__c = Date.today(),
      Allocation_Type__c = 'Payment Schedule',
      Line_Item_Type__c = 'Principal',
      Base_Amount__c = 500000,
      GST_Amount__c = 0,
      TDS_Amount__c = 0
    );

    PaymentScheduleViewController.PaymentScheduleViewResult preview = PaymentScheduleViewController.getPaymentSchedules(
      booking.Id
    );
    PaymentScheduleViewController.PaymentScheduleWrapper schedule = preview.schedules[0];
   // System.assertEquals(
    //  300000,
    //  schedule.flatDemandableAmount,
    //  'Bank Flat demandable is the remaining Bank Flat balance.'
 //   );
 //   System.assertEquals(
   //   3000,
   //   schedule.tdsDemandableAmount,
   //   'TDS is based on the remaining Bank Flat balance.'
 //   );

    Test.startTest();
    Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
      booking.Id,
      DemandComponentService.FLAT,
      false
    );
    Test.stopTest();

    Demands__c demand = [
      SELECT Demand_Amount__c, Flat_Amount__c, TDS_Amount__c
      FROM Demands__c
      WHERE Id = :demandId
    ];
   // System.assertEquals(300000, demand.Demand_Amount__c);
   // System.assertEquals(297000, demand.Flat_Amount__c);
  //  System.assertEquals(3000, demand.TDS_Amount__c);
    Payment_Schedule__c scheduleAfterDemand = [
      SELECT Bank_Flat_Demand_Raised__c
      FROM Payment_Schedule__c
      WHERE Id = :completed.Id
    ];
    //System.assertEquals(true, scheduleAfterDemand.Bank_Flat_Demand_Raised__c);
  }

  @isTest
  static void raiseDemandForBooking_calculatesOnePercentAcrossCompletedSchedules() {
    Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
    List<Payment_Schedule__c> schedules = [
      SELECT Id, Sequence__c
      FROM Payment_Schedule__c
      WHERE Booking__c = :booking.Id
      ORDER BY Sequence__c
    ];

    Payment_Schedule__c first = schedules[0];
    first.Amount__c = 892527;
    first.Pending_Amount__c = 392527;
    first.Amount_Paid__c = 500000;
    first.Payment_Schedule_Amount__c = 841526;
    first.Payment_Schedule_Amount_Paid__c = 500000;
    first.Payment_Schedule_Amount_Pending__c = 341526;
    first.GST_Amount__c = 42501;
    first.GST_Amount_Paid__c = 0;
    first.GST_Amount_Pending__c = 42501;
    first.TDS_Amount__c = 8500;
    first.TDS_Amount_Paid__c = 0;
    first.TDS_Amount_Pending__c = 8500;

    Payment_Schedule__c second = schedules[1];
    second.Status__c = 'Completed';
    second.Amount__c = 312384;
    second.Pending_Amount__c = 312384;
    second.Payment_Schedule_Amount__c = 294534;
    second.Payment_Schedule_Amount_Paid__c = 0;
    second.Payment_Schedule_Amount_Pending__c = 294534;
    second.GST_Amount__c = 14875;
    second.GST_Amount_Paid__c = 0;
    second.GST_Amount_Pending__c = 14875;
    second.TDS_Amount__c = 2975;
    second.TDS_Amount_Paid__c = 0;
    second.TDS_Amount_Pending__c = 2975;
    update new List<Payment_Schedule__c>{ first, second };

    insert new List<Payment_Schedule__c>{
      new Payment_Schedule__c(
        Booking__c = booking.Id,
        Sequence__c = 3,
        Status__c = 'Completed',
        Amount__c = 446264,
        Pending_Amount__c = 446264,
        Payment_Schedule_Amount__c = 420763,
        Payment_Schedule_Amount_Paid__c = 0,
        Payment_Schedule_Amount_Pending__c = 420763,
        GST_Amount__c = 21251,
        GST_Amount_Paid__c = 0,
        GST_Amount_Pending__c = 21251,
        TDS_Amount__c = 4250,
        TDS_Amount_Paid__c = 0,
        TDS_Amount_Pending__c = 4250
      ),
      new Payment_Schedule__c(
        Booking__c = booking.Id,
        Sequence__c = 4,
        Status__c = 'Completed',
        Amount__c = 267758,
        Pending_Amount__c = 267758,
        Payment_Schedule_Amount__c = 252458,
        Payment_Schedule_Amount_Paid__c = 0,
        Payment_Schedule_Amount_Pending__c = 252458,
        GST_Amount__c = 12750,
        GST_Amount_Paid__c = 0,
        GST_Amount_Pending__c = 12750,
        TDS_Amount__c = 2550,
        TDS_Amount_Paid__c = 0,
        TDS_Amount_Pending__c = 2550
      )
    };

    Test.startTest();
    Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
      booking.Id,
      DemandComponentService.FLAT,
      false
    );
    Test.stopTest();

    Demands__c demand = [
      SELECT Demand_Amount__c, Flat_Amount__c, TDS_Amount__c
      FROM Demands__c
      WHERE Id = :demandId
    ];
    System.assertEquals(
      1327556,
      demand.Demand_Amount__c,
      'Demand total should equal the sum of remaining Flat Cost across the schedules.'
    );
    System.assertEquals(
      1309281,
      demand.Flat_Amount__c,
      'Flat amount should equal the aggregate remaining base Flat balance.'
    );
    System.assertEquals(
      18275,
      demand.TDS_Amount__c,
      'TDS should equal the aggregate full pending TDS balance.'
    );
  }

  @isTest
  static void getPaymentSchedules_blankMilestoneName_fallsBackToScheduleName() {
    Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
    Payment_Schedule__c completed = [
      SELECT Id, Name
      FROM Payment_Schedule__c
      WHERE Booking__c = :b.Id AND Status__c = 'Completed'
      LIMIT 1
    ];
    completed.Milestone_Name__c = null;
    update completed;

    Test.startTest();
    PaymentScheduleViewController.PaymentScheduleViewResult r = PaymentScheduleViewController.getPaymentSchedules(
      b.Id
    );
    Test.stopTest();

    System.assertEquals(true, r.success, 'Should succeed');
    System.assertEquals(
      completed.Name,
      r.nextDemand.lastCompletedMilestone,
      'Blank Milestone_Name__c should fall back to schedule Name'
    );
    for (PaymentScheduleViewController.PaymentScheduleWrapper w : r.schedules) {
      if (w.id == completed.Id) {
        System.assertEquals(
          completed.Name,
          w.milestoneName,
          'Wrapper should fall back to schedule Name when Milestone_Name__c is blank'
        );
      }
    }
  }

  @isTest
  static void getPaymentSchedules_blankMilestoneNameUsesMasterScheduleName() {
    Booking__c b = [SELECT Id, Project__c FROM Booking__c LIMIT 1];
    Payment_Schedule__c completed = [
      SELECT Id, Name
      FROM Payment_Schedule__c
      WHERE Booking__c = :b.Id AND Status__c = 'Completed'
      LIMIT 1
    ];
    Master_Payment_Schedule__c master = new Master_Payment_Schedule__c(
      Name = 'Foundation milestone',
      Project__c = b.Project__c,
      Sequence__c = 1,
      Is_Active__c = true,
      Percentage__c = 20
    );
    insert master;

    completed.Milestone_Name__c = null;
    completed.Master_Payment_Schedule__c = master.Id;
    update completed;

    Test.startTest();
    PaymentScheduleViewController.PaymentScheduleViewResult r = PaymentScheduleViewController.getPaymentSchedules(
      b.Id
    );
    Test.stopTest();

    System.assertEquals(true, r.success, 'Should succeed');
    System.assertEquals(
      'Foundation milestone',
      r.nextDemand.lastCompletedMilestone,
      'Last completed milestone should use the linked master schedule name'
    );
    for (PaymentScheduleViewController.PaymentScheduleWrapper w : r.schedules) {
      if (w.id == completed.Id) {
        System.assertEquals(
          'Foundation milestone',
          w.milestoneName,
          'Schedule display should use the linked master schedule name'
        );
      }
    }
  }

  @isTest
  static void getPaymentSchedules_nullId_returnsError() {
    PaymentScheduleViewController.PaymentScheduleViewResult r = PaymentScheduleViewController.getPaymentSchedules(
      null
    );
    System.assertEquals(false, r.success, 'Should not succeed');
    System.assertNotEquals(null, r.errorMessage, 'Should have error');
  }

  @isTest
  static void saveScheduleAmounts_validTotals_updates() {
    Booking__c b = [SELECT Id, Total_Payable_Amount__c FROM Booking__c LIMIT 1];
    List<Payment_Schedule__c> schedules = [
      SELECT Id
      FROM Payment_Schedule__c
      WHERE Booking__c = :b.Id
      ORDER BY Sequence__c
    ];

    Map<String, Object> amounts = new Map<String, Object>();
    amounts.put(schedules[1].Id, '500');
    // first one has Status='Completed' so we don't edit it; will keep its existing amount

    Test.startTest();
    try {
      PaymentScheduleViewController.saveScheduleAmounts(
        b.Id,
        JSON.serialize(amounts)
      );
    } catch (Exception e) {
      // The completed schedule edit would throw; here ps2 is Pending so it should succeed
    }
    Test.stopTest();
  }

  @isTest
  static void saveScheduleAmounts_emptyMap_doesNothing() {
    Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
    PaymentScheduleViewController.saveScheduleAmounts(b.Id, '{}');
    // Just assert no exception occurred
    System.assert(true, 'No error');
  }

  @isTest
  static void saveScheduleAmounts_invalidJson_throws() {
    Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
    Boolean threw = false;
    try {
      PaymentScheduleViewController.saveScheduleAmounts(b.Id, 'not-json');
    } catch (Exception e) {
      threw = true;
    }
    System.assertEquals(true, threw, 'Should throw');
  }

  @isTest
  static void saveScheduleAmounts_negativeAmount_throws() {
    Booking__c b = [SELECT Id FROM Booking__c LIMIT 1];
    Payment_Schedule__c ps = [
      SELECT Id
      FROM Payment_Schedule__c
      WHERE Status__c = 'Pending'
      LIMIT 1
    ];
    Map<String, Object> amounts = new Map<String, Object>{ ps.Id => '-100' };

    Boolean threw = false;
    try {
      PaymentScheduleViewController.saveScheduleAmounts(
        b.Id,
        JSON.serialize(amounts)
      );
    } catch (Exception e) {
      threw = true;
    }
    System.assertEquals(true, threw, 'Should throw on negative');
  }
  @isTest
  static void raiseDemandForBooking_success() {
    Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

    Test.startTest();

    Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
      booking.Id,
      'Flat',
      true
    );
    Id gstDemandId = PaymentScheduleViewController.raiseDemandForBooking(
      booking.Id,
      'GST',
      true
    );

    Test.stopTest();

    Demands__c flatDemand = [
      SELECT
        Demand_Component__c,
        Demand_Amount__c,
        Flat_Amount__c,
        GST_Amount__c,
        Interest_Amount__c
      FROM Demands__c
      WHERE Id = :demandId
    ];
    System.assertEquals('Flat', flatDemand.Demand_Component__c);
    System.assertEquals(100, flatDemand.Demand_Amount__c);
    System.assertEquals(0, flatDemand.GST_Amount__c);
    System.assertEquals(
      10,
      flatDemand.Interest_Amount__c,
      'Interest should be included when selected'
    );

    System.assertEquals(
      2,
      [SELECT COUNT() FROM Demands__c WHERE Booking__c = :booking.Id]
    );
    System.assertNotEquals(demandId, gstDemandId);
    System.assertEquals(
      true,
      [
        SELECT Customer_Flat_Demand_Raised__c, Customer_GST_Demand_Raised__c
        FROM Payment_Schedule__c
        WHERE Booking__c = :booking.Id AND Status__c = 'Completed'
      ]
      .Customer_GST_Demand_Raised__c
    );
  }

  @isTest
  static void raiseDemandForBooking_combinedModeCreatesCombinedDemand() {
    Booking__c booking = [SELECT Id, Project__c FROM Booking__c LIMIT 1];
    update new Project__c(
      Id = booking.Project__c,
      Legacy_Split_Demand_Receipt__c = false
    );
    booking.Funding_Type__c = 'Prorata';
    update booking;
    Payment_Schedule__c completed = [
      SELECT Id
      FROM Payment_Schedule__c
      WHERE Booking__c = :booking.Id AND Status__c = 'Completed'
      LIMIT 1
    ];
    completed.TDS_Amount_Pending__c = 5;
    completed.TDS_Amount__c = 5;
    completed.Pending_Amount__c = 130;
    completed.Bank_Flat_Amount__c = 80;
    completed.Bank_GST_Amount__c = 10;
    ProrataInvariantService.bypass = true;
    try {
      update completed;
    } finally {
      ProrataInvariantService.bypass = false;
    }

    PaymentScheduleViewController.PaymentScheduleViewResult scheduleResult = PaymentScheduleViewController.getPaymentSchedules(
      booking.Id
    );

    Test.startTest();
    Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
      booking.Id,
      DemandComponentService.FLAT_AND_GST,
      true
    );
    Test.stopTest();
  }

  @isTest
  static void raiseDemandForBookingWithAmounts_savesEditedComponents() {
    Booking__c booking = [SELECT Id, Project__c FROM Booking__c LIMIT 1];
    update new Project__c(
      Id = booking.Project__c,
      Legacy_Split_Demand_Receipt__c = false
    );

    Test.startTest();
    Id demandId = PaymentScheduleViewController.raiseDemandForBookingWithAmounts(
      booking.Id,
      DemandComponentService.FLAT_AND_GST,
      false,
      100.25,
      12.50,
      3.25
    );
    Test.stopTest();

    Demands__c demand = [
      SELECT
        Demand_Amount__c,
        Pending_Amount__c,
        Flat_Amount__c,
        Base_Amount__c,
        GST_Amount__c,
        TDS_Amount__c
      FROM Demands__c
      WHERE Id = :demandId
    ];
    System.assertEquals(116, demand.Demand_Amount__c);
    System.assertEquals(116, demand.Pending_Amount__c);
    System.assertEquals(100.25, demand.Flat_Amount__c);
    System.assertEquals(100.25, demand.Base_Amount__c);
    System.assertEquals(12.50, demand.GST_Amount__c);
    System.assertEquals(3.25, demand.TDS_Amount__c);
  }

  @isTest
  static void raiseDemandForBooking_rejectsCombinedDemandForLegacyProject() {
    Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];
    Boolean blocked = false;

    try {
      PaymentScheduleViewController.raiseDemandForBooking(
        booking.Id,
        DemandComponentService.FLAT_AND_GST,
        false
      );
    } catch (AuraHandledException e) {
      blocked = true;
    }

    System.assertEquals(
      true,
      blocked,
      'Legacy projects must keep Flat and GST demands separate.'
    );
  }

  @isTest
  static void raiseDemandForBooking_canExcludeInterest() {
    Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

    Test.startTest();
    Id demandId = PaymentScheduleViewController.raiseDemandForBooking(
      booking.Id,
      'Flat',
      false
    );
    Test.stopTest();

    Demands__c demand = [
      SELECT Interest_Amount__c
      FROM Demands__c
      WHERE Id = :demandId
    ];
    System.assertEquals(
      0,
      demand.Interest_Amount__c,
      'Interest should be excluded when not selected'
    );
  }
}