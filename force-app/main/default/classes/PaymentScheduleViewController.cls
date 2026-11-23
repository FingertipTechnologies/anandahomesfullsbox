/**
 * @description Controller for Payment Schedule Viewer LWC
 * @author Arun Kumar N
 * @date 2026-01-29
 * @updated 2026-01-30 - Added last completed milestone tracking
 * @updated 2026-10-18 - Manual demand raising now creates one selected component (Flat or GST)
 *              at a time, with separate payment-schedule tracking so the other component can
 *              be raised later.
 */
public with sharing class PaymentScheduleViewController {
  private static final Set<String> SPLIT_FUNDING_TYPES = new Set<String>{
    'Prorata',
    'Partial'
  };

  /**
   * Wrapper class for Payment Schedule display
   */
  public class PaymentScheduleWrapper {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public Decimal serialNumber { get; set; }
    @AuraEnabled
    public Decimal sequenceNumber { get; set; }
    @AuraEnabled
    public String milestoneName { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public Decimal amount { get; set; }
    @AuraEnabled
    public Decimal percentage { get; set; }
    @AuraEnabled
    public Decimal pendingAmount { get; set; }
    @AuraEnabled
    public Decimal interestPending { get; set; }
    @AuraEnabled
    public Decimal baseAmount { get; set; }
    @AuraEnabled
    public Decimal gstAmount { get; set; }
    @AuraEnabled
    public Decimal tdsAmount { get; set; }
    @AuraEnabled
    public Decimal basePending { get; set; }
    @AuraEnabled
    public Decimal gstPending { get; set; }
    @AuraEnabled
    public Decimal tdsPending { get; set; }
    @AuraEnabled
    public Decimal basePaid { get; set; }
    @AuraEnabled
    public Decimal gstPaid { get; set; }
    @AuraEnabled
    public Decimal tdsPaid { get; set; }
    // The amount this milestone actually contributes to the next demand: Bank Flat + Bank
    // GST when a bank split exists, otherwise the full Base + GST + TDS.
    @AuraEnabled
    public Decimal demandableAmount { get; set; }
    @AuraEnabled
    public Decimal flatDemandableAmount { get; set; }
    @AuraEnabled
    public Decimal gstDemandableAmount { get; set; }
    @AuraEnabled
    public Decimal tdsDemandableAmount { get; set; }
    @AuraEnabled
    public Decimal combinedDemandableAmount { get; set; }
    @AuraEnabled
    public String formattedDemandable { get; set; }
    // Where this milestone's demand comes from: 'Bank' when a bank split exists on the
    // record, 'Customer' otherwise. isBankDemand is the boolean equivalent for templates.
    @AuraEnabled
    public String demandSource { get; set; }
    @AuraEnabled
    public Boolean isBankDemand { get; set; }
    @AuraEnabled
    public String statusColor { get; set; }
    @AuraEnabled
    public String statusIcon { get; set; }
    @AuraEnabled
    public Boolean isPaid { get; set; }
    @AuraEnabled
    public Boolean isCompleted { get; set; }
    @AuraEnabled
    public String formattedAmount { get; set; }
    @AuraEnabled
    public String formattedPending { get; set; }
    @AuraEnabled
    public String formattedInterest { get; set; }
  }

  /**
   * Wrapper class for Next Demand Summary
   */
  public class NextDemandWrapper {
    @AuraEnabled
    public Decimal totalPendingAmount { get; set; }
    @AuraEnabled
    public Decimal totalInterestPending { get; set; }
    @AuraEnabled
    public Decimal availableInterestWaiver { get; set; }
    @AuraEnabled
    public Decimal grandTotal { get; set; }
    @AuraEnabled
    public Boolean hasInterest { get; set; }
    @AuraEnabled
    public Integer completedScheduleCount { get; set; }
    @AuraEnabled
    public String formattedPending { get; set; }
    @AuraEnabled
    public String formattedInterest { get; set; }
    @AuraEnabled
    public String formattedTotal { get; set; }
    @AuraEnabled
    public String lastCompletedMilestone { get; set; }
    // Split of the demand total by source, so the raising UI can show the user how much of
    // the next demand is Bank-funded vs Customer-payable.
    @AuraEnabled
    public Decimal totalBankAmount { get; set; }
    @AuraEnabled
    public Decimal totalCustomerAmount { get; set; }
    @AuraEnabled
    public String formattedBankAmount { get; set; }
    @AuraEnabled
    public String formattedCustomerAmount { get; set; }
    @AuraEnabled
    public Boolean hasSplitFunding { get; set; }
    @AuraEnabled
    public Boolean legacySplitDemandReceipt { get; set; }
    @AuraEnabled
    public Boolean isFirstDemand { get; set; }
    @AuraEnabled
    public Boolean isFirstFlatDemand { get; set; }
    @AuraEnabled
    public Boolean isFirstGstDemand { get; set; }
    @AuraEnabled
    public Boolean isFirstCombinedDemand { get; set; }
    @AuraEnabled
    public Boolean hasAgreementMilestone { get; set; }
    @AuraEnabled
    public Decimal agreementSequence { get; set; }
  }

  /**
   * Result wrapper for the complete view
   */
  public class PaymentScheduleViewResult {
    @AuraEnabled
    public List<PaymentScheduleWrapper> schedules { get; set; }
    @AuraEnabled
    public NextDemandWrapper nextDemand { get; set; }
    @AuraEnabled
    public String bookingName { get; set; }
    @AuraEnabled
    public String projectName { get; set; }
    @AuraEnabled
    public String unitName { get; set; }
    @AuraEnabled
    public Decimal totalPayableAmount { get; set; }
    @AuraEnabled
    public Boolean success { get; set; }
    @AuraEnabled
    public String errorMessage { get; set; }
  }

  /**
   * @description Get all payment schedules for a booking with next demand calculation
   * @param bookingId The ID of the Booking record
   * @return PaymentScheduleViewResult
   */
  @AuraEnabled
  public static PaymentScheduleViewResult getPaymentSchedules(Id bookingId) {
    PaymentScheduleViewResult result = new PaymentScheduleViewResult();
    result.schedules = new List<PaymentScheduleWrapper>();
    result.success = false;

    try {
      // Validate bookingId
      if (bookingId == null) {
        result.errorMessage = 'Booking ID is required';
        return result;
      }

      // Query Booking details with null checks
      List<Booking__c> bookings = [
        SELECT
          Id,
          Name,
          Project__c,
          Project__r.Name,
          Project__r.Legacy_Split_Demand_Receipt__c,
          Plot__c,
          Plot__r.Name,
          Funding_Type__c,
          Total_Payable_Amount__c,
          Grand_Total__c
        FROM Booking__c
        WHERE Id = :bookingId
        LIMIT 1
      ];

      if (bookings.isEmpty()) {
        result.errorMessage = 'Booking record not found';
        return result;
      }

      Booking__c booking = bookings[0];
      result.bookingName = booking.Name;
      result.projectName = booking.Project__c != null
        ? booking.Project__r.Name
        : 'N/A';
      result.unitName = booking.Plot__c != null ? booking.Plot__r.Name : 'N/A';
      result.totalPayableAmount = booking.Total_Payable_Amount__c != null
        ? booking.Total_Payable_Amount__c
        : (booking.Grand_Total__c != null ? booking.Grand_Total__c : 0);

      // Query all Payment Schedules
      List<Payment_Schedule__c> schedules = [
        SELECT
          Id,
          Name,
          S_No__c,
          Sequence__c,
          Milestone_Name__c,
          Master_Payment_Schedule__r.Name,
          Status__c,
          Demand_Raised__c,
          Is_Agreement__c,
          Bank_Demand_Raised__c,
          Customer_Demand_Raised__c,
          Bank_Flat_Demand_Raised__c,
          Bank_GST_Demand_Raised__c,
          Customer_Flat_Demand_Raised__c,
          Customer_GST_Demand_Raised__c,
          Amount__c,
          Percentage__c,
          Pending_Amount__c,
          Interest_Pending__c,
          Payment_Schedule_Amount__c,
          GST_Amount__c,
          TDS_Amount__c,
          Payment_Schedule_Amount_Paid__c,
          GST_Amount_Paid__c,
          TDS_Amount_Paid__c,
          Payment_Schedule_Amount_Pending__c,
          GST_Amount_Pending__c,
          TDS_Amount_Pending__c,
          Bank_Flat_Amount__c,
          Bank_GST_Amount__c,
          Customer_Flat_Prorata__c,
          Customer_GST_Prorata__c,
          Booking__r.Funding_Type__c,
          Booking__r.Project__r.Legacy_Split_Demand_Receipt__c
        FROM Payment_Schedule__c
        WHERE Booking__c = :bookingId
        ORDER BY Sequence__c ASC NULLS LAST, CreatedDate ASC
      ];
      Boolean prorataBankDemand =
        booking.Project__r != null &&
        booking.Project__r.Legacy_Split_Demand_Receipt__c == true &&
        booking.Funding_Type__c != null &&
        SPLIT_FUNDING_TYPES.contains(booking.Funding_Type__c) &&
        hasBankSplit(schedules);
      Set<Id> sourceSplitScheduleIds = new Set<Id>();
      if (prorataBankDemand) {
        for (Payment_Schedule__c schedule : schedules) {
          if (DemandComponentService.hasAudienceSplit(schedule)) {
            sourceSplitScheduleIds.add(schedule.Id);
          }
        }
      }
      Map<Id, Map<String, DemandComponentService.ReceiptSourceTotals>> receiptTotalsBySchedule = DemandComponentService.getReceiptSourceTotals(
        sourceSplitScheduleIds
      );
      Set<Id> demandScheduleIds = new Set<Id>();
      for (Payment_Schedule__c schedule : schedules) {
        if (
          schedule.Status__c == PostSalesConstants.SCHEDULE_STATUS_COMPLETED
        ) {
          demandScheduleIds.add(schedule.Id);
        }
      }
      DemandComponentService.TdsCarryForwardAllocation carryForwardAllocation = prorataBankDemand
        ? DemandComponentService.getTdsCarryForwardAllocation(
            new Set<Id>{ bookingId },
            demandScheduleIds
          )
        : new DemandComponentService.TdsCarryForwardAllocation();

      // Process schedules and calculate next demand
      List<PaymentScheduleWrapper> wrappers = new List<PaymentScheduleWrapper>();
      Decimal totalPendingForNextDemand = 0;
      Decimal totalInterestForNextDemand = 0;
      Decimal totalBankForNextDemand = 0;
      Decimal totalCustomerForNextDemand = 0;
      Integer completedCount = 0;
      String lastCompletedMilestone = 'No completed milestones';
      Decimal agreementSequence;

      for (Payment_Schedule__c schedule : schedules) {
        PaymentScheduleWrapper wrapper = new PaymentScheduleWrapper();
        wrapper.id = schedule.Id;
        wrapper.name = schedule.Name != null ? schedule.Name : '';
        wrapper.serialNumber = schedule.S_No__c != null
          ? schedule.S_No__c
          : schedule.Sequence__c;
        wrapper.sequenceNumber = schedule.Sequence__c;
        if (
          schedule.Is_Agreement__c == true &&
          schedule.Sequence__c != null &&
          (agreementSequence == null ||
          schedule.Sequence__c < agreementSequence)
        ) {
          agreementSequence = schedule.Sequence__c;
        }
        wrapper.milestoneName = String.isNotBlank(schedule.Milestone_Name__c)
          ? schedule.Milestone_Name__c
          : (schedule.Master_Payment_Schedule__r != null &&
              String.isNotBlank(schedule.Master_Payment_Schedule__r.Name)
              ? schedule.Master_Payment_Schedule__r.Name
              : (schedule.Name != null ? schedule.Name : ''));
        wrapper.status = schedule.Status__c != null ? schedule.Status__c : '';
        wrapper.amount = schedule.Amount__c != null ? schedule.Amount__c : 0;
        wrapper.percentage = schedule.Percentage__c != null
          ? schedule.Percentage__c
          : 0;
        wrapper.pendingAmount = schedule.Pending_Amount__c != null
          ? schedule.Pending_Amount__c
          : 0;
        wrapper.interestPending = schedule.Interest_Pending__c != null
          ? schedule.Interest_Pending__c
          : 0;
        wrapper.baseAmount = schedule.Payment_Schedule_Amount__c;
        wrapper.gstAmount = schedule.GST_Amount__c;
        wrapper.tdsAmount = schedule.TDS_Amount__c;
        wrapper.basePending = schedule.Payment_Schedule_Amount_Pending__c;
        wrapper.gstPending = schedule.GST_Amount_Pending__c;
        wrapper.tdsPending = schedule.TDS_Amount_Pending__c;
        wrapper.isBankDemand =
          prorataBankDemand &&
          schedule.Booking__r.Funding_Type__c != null &&
          SPLIT_FUNDING_TYPES.contains(schedule.Booking__r.Funding_Type__c) &&
          (nz(schedule.Bank_Flat_Amount__c) != 0 ||
          nz(schedule.Bank_GST_Amount__c) != 0);
        wrapper.demandSource = wrapper.isBankDemand ? 'Bank' : 'Customer';
        Boolean sourceSpecificSchedule =
          prorataBankDemand &&
          DemandComponentService.hasAudienceSplit(schedule);
        DemandComponentService.ReceiptSourceTotals sourceTotals = sourceSpecificSchedule
          ? DemandComponentService.getReceiptSourceTotals(
              receiptTotalsBySchedule,
              schedule.Id,
              wrapper.isBankDemand
            )
          : null;
        wrapper.basePaid = sourceSpecificSchedule
          ? sourceTotals.flatAmount
          : schedule.Payment_Schedule_Amount_Paid__c;
        wrapper.gstPaid = sourceSpecificSchedule
          ? sourceTotals.gstAmount
          : schedule.GST_Amount_Paid__c;
        wrapper.tdsPaid = sourceSpecificSchedule
          ? sourceTotals.tdsAmount
          : schedule.TDS_Amount_Paid__c;

        Decimal demandable = demandableAmount(
          schedule,
          prorataBankDemand,
          wrapper.isBankDemand,
          sourceSpecificSchedule,
          receiptTotalsBySchedule
        );
        wrapper.flatDemandableAmount = DemandComponentService.isComponentRaised(
            schedule,
            DemandComponentService.FLAT,
            wrapper.isBankDemand
          )
          ? 0
          : DemandComponentService.amountByAudience(
              schedule,
              DemandComponentService.FLAT,
              wrapper.isBankDemand,
              sourceSpecificSchedule,
              receiptTotalsBySchedule
            );
        wrapper.gstDemandableAmount = DemandComponentService.isComponentRaised(
            schedule,
            DemandComponentService.GST,
            wrapper.isBankDemand
          )
          ? 0
          : DemandComponentService.amountByAudience(
              schedule,
              DemandComponentService.GST,
              wrapper.isBankDemand,
              sourceSpecificSchedule,
              receiptTotalsBySchedule
            );
        wrapper.tdsDemandableAmount = 0;
        if (
          !DemandComponentService.isComponentRaised(
            schedule,
            DemandComponentService.FLAT,
            wrapper.isBankDemand
          )
        ) {
          if (
            prorataBankDemand &&
            wrapper.isBankDemand &&
            wrapper.flatDemandableAmount > 0
          ) {
            Decimal currentTds = DemandComponentService.tdsAmountByAudience(
              schedule,
              true,
              sourceSpecificSchedule,
              receiptTotalsBySchedule
            );
            Decimal carryForward = carryForwardAllocation.amountByDemandSchedule.containsKey(
                schedule.Id
              )
              ? carryForwardAllocation.amountByDemandSchedule.get(schedule.Id)
              : 0;
            wrapper.tdsDemandableAmount = currentTds + carryForward;
            wrapper.flatDemandableAmount += wrapper.tdsDemandableAmount;
          } else if (!wrapper.isBankDemand) {
            wrapper.tdsDemandableAmount = DemandComponentService.tdsAmountByAudience(
              schedule,
              false,
              sourceSpecificSchedule,
              receiptTotalsBySchedule
            );
          }
        }
        wrapper.combinedDemandableAmount = DemandComponentService.isComponentRaised(
            schedule,
            DemandComponentService.FLAT_AND_GST,
            wrapper.isBankDemand
          )
          ? 0
          : wrapper.flatDemandableAmount + wrapper.gstDemandableAmount;
        if (wrapper.isBankDemand) {
          demandable += wrapper.tdsDemandableAmount;
        }
        wrapper.demandableAmount = demandable;
        wrapper.formattedDemandable = formatCurrency(demandable);

        // Determine status color and icon
        wrapper.isPaid = (schedule.Status__c ==
        PostSalesConstants.SCHEDULE_STATUS_PAID);
        wrapper.isCompleted = (schedule.Status__c ==
        PostSalesConstants.SCHEDULE_STATUS_COMPLETED);
        wrapper.statusColor = PostSalesConstants.getStatusColor(
          schedule.Status__c
        );
        wrapper.statusIcon = PostSalesConstants.getStatusIcon(
          schedule.Status__c
        );

        if (
          schedule.Status__c == PostSalesConstants.SCHEDULE_STATUS_COMPLETED
        ) {
          completedCount++;
          lastCompletedMilestone = wrapper.milestoneName;

          // Next demand = Bank Flat + Bank GST when a bank split exists on the
          // milestone, otherwise the full schedule amount (Base + GST + TDS).
          // Exclude milestones whose demand has already been raised so the "Next
          // Payment Demand" total never re-demands an existing demand.
          if (
            schedule.Demand_Raised__c != true &&
            (!prorataBankDemand || wrapper.isBankDemand)
          ) {
            totalPendingForNextDemand += demandable;
            if (wrapper.isBankDemand) {
              totalBankForNextDemand += demandable;
            } else {
              totalCustomerForNextDemand += demandable;
            }
            totalInterestForNextDemand += schedule.Interest_Pending__c != null
              ? schedule.Interest_Pending__c
              : 0;
          }
        }

        // Format currency values
        wrapper.formattedAmount = formatCurrency(wrapper.amount);
        wrapper.formattedPending = formatCurrency(wrapper.pendingAmount);
        wrapper.formattedInterest = formatCurrency(wrapper.interestPending);

        wrappers.add(wrapper);
      }

      // Build Next Demand Wrapper
      NextDemandWrapper nextDemand = new NextDemandWrapper();
      nextDemand.totalPendingAmount = totalPendingForNextDemand;
      nextDemand.totalInterestPending = totalInterestForNextDemand;
      nextDemand.availableInterestWaiver = InterestWaiverService.getRemainingWaivers(
          new Set<Id>{ bookingId }
        )
        .get(bookingId);
      nextDemand.grandTotal =
        totalPendingForNextDemand + totalInterestForNextDemand;
      nextDemand.hasInterest = (totalInterestForNextDemand > 0);
      nextDemand.completedScheduleCount = completedCount;
      nextDemand.formattedPending = formatCurrency(
        nextDemand.totalPendingAmount
      );
      nextDemand.formattedInterest = formatCurrency(
        nextDemand.totalInterestPending
      );
      nextDemand.formattedTotal = formatCurrency(nextDemand.grandTotal);
      nextDemand.lastCompletedMilestone = lastCompletedMilestone;
      nextDemand.totalBankAmount = totalBankForNextDemand;
      nextDemand.totalCustomerAmount = totalCustomerForNextDemand;
      nextDemand.formattedBankAmount = formatCurrency(totalBankForNextDemand);
      nextDemand.formattedCustomerAmount = formatCurrency(
        totalCustomerForNextDemand
      );
      nextDemand.hasSplitFunding =
        String.isNotBlank(booking.Funding_Type__c) &&
        SPLIT_FUNDING_TYPES.contains(booking.Funding_Type__c);
      nextDemand.legacySplitDemandReceipt =
        booking.Project__r != null &&
        booking.Project__r.Legacy_Split_Demand_Receipt__c == true;
      List<AggregateResult> existingDemandComponents = [
        SELECT Demand_Component__c componentValue
        FROM Demands__c
        WHERE Booking__c = :bookingId
        GROUP BY Demand_Component__c
      ];
      Set<String> demandedComponents = new Set<String>();
      for (AggregateResult existingDemand : existingDemandComponents) {
        demandedComponents.add((String) existingDemand.get('componentValue'));
      }
      nextDemand.isFirstDemand = existingDemandComponents.isEmpty();
      nextDemand.isFirstFlatDemand = !demandedComponents.contains(
        DemandComponentService.FLAT
      );
      nextDemand.isFirstGstDemand = !demandedComponents.contains(
        DemandComponentService.GST
      );
      nextDemand.isFirstCombinedDemand = !demandedComponents.contains(
        DemandComponentService.FLAT_AND_GST
      );
      nextDemand.hasAgreementMilestone = agreementSequence != null;
      nextDemand.agreementSequence = agreementSequence;

      // Build result
      result.schedules = wrappers;
      result.nextDemand = nextDemand;
      result.success = true;

      return result;
    } catch (Exception e) {
      result.errorMessage =
        'Error: ' +
        e.getMessage() +
        ' (Line: ' +
        e.getLineNumber() +
        ')';
      result.success = false;
      System.debug(
        'Error in getPaymentSchedules: ' +
          e.getMessage() +
          ' - ' +
          e.getStackTraceString()
      );
      return result;
    }
  }

  /**
   * @description Format currency value
   * @param value Decimal value to format
   * @return Formatted currency string
   */
  private static String formatCurrency(Decimal value) {
    return PostSalesConstants.formatCurrency(value);
  }

  /**
   * @description The amount a milestone contributes to the next demand: when a bank split has
   *              been recorded, only Bank Flat + Bank GST are demandable, with Bank TDS added
   *              separately when the Flat component is still outstanding. When no bank split
   *              exists, the full schedule amount (Base + GST + TDS) is used.
   */
  private static Decimal demandableAmount(
    Payment_Schedule__c ps,
    Boolean prorataBankDemand,
    Boolean bankSide,
    Boolean sourceSpecificSchedule,
    Map<Id, Map<String, DemandComponentService.ReceiptSourceTotals>> receiptTotalsBySchedule
  ) {
    if (prorataBankDemand == true && bankSide == true) {
      return DemandComponentService.amountByAudience(
          ps,
          DemandComponentService.FLAT,
          true,
          sourceSpecificSchedule,
          receiptTotalsBySchedule
        ) +
        DemandComponentService.amountByAudience(
          ps,
          DemandComponentService.GST,
          true,
          sourceSpecificSchedule,
          receiptTotalsBySchedule
        );
    }
    return nz(ps.Pending_Amount__c);
  }

  private static Boolean hasBankSplit(List<Payment_Schedule__c> schedules) {
    for (Payment_Schedule__c schedule : schedules) {
      if (
        nz(schedule.Bank_Flat_Amount__c) != 0 ||
        nz(schedule.Bank_GST_Amount__c) != 0
      ) {
        return true;
      }
    }
    return false;
  }

  private static Decimal nz(Decimal v) {
    return v == null ? 0 : v;
  }

  private static void validateDemandComponent(
    String demandComponent,
    Boolean legacySplitDemandReceipt
  ) {
    if (
      demandComponent != DemandComponentService.FLAT &&
      demandComponent != DemandComponentService.GST &&
      demandComponent != DemandComponentService.FLAT_AND_GST
    ) {
      throw new AuraHandledException('Select a valid demand component.');
    }
    if (
      legacySplitDemandReceipt == true &&
      demandComponent == DemandComponentService.FLAT_AND_GST
    ) {
      throw new AuraHandledException(
        'Legacy projects require separate Flat or GST demands.'
      );
    }
    if (
      legacySplitDemandReceipt != true &&
      demandComponent != DemandComponentService.FLAT_AND_GST
    ) {
      throw new AuraHandledException(
        'This project requires a combined Flat + GST demand.'
      );
    }
  }

  /**
   * @description Raise a Demands__c record for the next payment demand on a booking.
   * Aggregates the selected component across completed schedules. Legacy projects raise Flat
   * and GST separately; other projects raise one combined Flat + GST demand. Email-on-insert is
   * left to the downstream record-triggered flow on Demands__c.
   */
  @AuraEnabled
  public static Id raiseDemandForBooking(
    Id bookingId,
    String demandComponent,
    Boolean includeInterest
  ) {
    return raiseDemandForBookingInternal(
      bookingId,
      demandComponent,
      includeInterest,
      null,
      null,
      null,
      false,
      false
    );
  }

  /**
   * Agreement Amount mode is first-demand-only and limits completed milestones to the
   * Agreement sequence, inclusive. Normal mode preserves existing component behavior.
   */
  @AuraEnabled
  public static Id raiseDemandForBookingInMode(
    Id bookingId,
    String demandComponent,
    Boolean includeInterest,
    String demandMode
  ) {
    Boolean agreementOnly = demandMode == 'Agreement Amount';
    if (!agreementOnly && demandMode != 'Normal') {
      throw new AuraHandledException('Select a valid demand mode.');
    }
    return raiseDemandForBookingInternal(
      bookingId,
      demandComponent,
      includeInterest,
      null,
      null,
      null,
      false,
      agreementOnly
    );
  }

  @AuraEnabled
  public static Id raiseDemandForBookingWithAmounts(
    Id bookingId,
    String demandComponent,
    Boolean includeInterest,
    Decimal flatAmount,
    Decimal gstAmount,
    Decimal tdsAmount
  ) {
    if (
      flatAmount == null ||
      gstAmount == null ||
      tdsAmount == null ||
      flatAmount < 0 ||
      gstAmount < 0 ||
      tdsAmount < 0
    ) {
      throw new AuraHandledException(
        'Demand amounts must be provided and cannot be negative.'
      );
    }
    return raiseDemandForBookingInternal(
      bookingId,
      demandComponent,
      includeInterest,
      flatAmount,
      gstAmount,
      tdsAmount,
      true,
      false
    );
  }

  private static Id raiseDemandForBookingInternal(
    Id bookingId,
    String demandComponent,
    Boolean includeInterest,
    Decimal flatAmountOverride,
    Decimal gstAmountOverride,
    Decimal tdsAmountOverride,
    Boolean useAmountOverrides,
    Boolean agreementOnly
  ) {
    if (bookingId == null) {
      throw new AuraHandledException('Booking ID is required');
    }
    List<Booking__c> bookingContexts = [
      SELECT Id, Funding_Type__c, Project__r.Legacy_Split_Demand_Receipt__c
      FROM Booking__c
      WHERE Id = :bookingId
      LIMIT 1
    ];
    if (bookingContexts.isEmpty()) {
      throw new AuraHandledException('Booking not found.');
    }
    Boolean legacySplitDemandReceipt =
      bookingContexts[0].Project__r != null &&
      bookingContexts[0].Project__r.Legacy_Split_Demand_Receipt__c == true;
    validateDemandComponent(demandComponent, legacySplitDemandReceipt);
    if (agreementOnly == true) {
      List<Demands__c> existingComponentDemands = [
        SELECT Id
        FROM Demands__c
        WHERE Booking__c = :bookingId AND Demand_Component__c = :demandComponent
        LIMIT 1
      ];
      if (!existingComponentDemands.isEmpty()) {
        throw new AuraHandledException(
          'Agreement Amount mode is available only for the first demand of this component.'
        );
      }
    }

    Decimal agreementSequence;
    if (agreementOnly == true) {
      List<Payment_Schedule__c> agreementSchedules = [
        SELECT Sequence__c
        FROM Payment_Schedule__c
        WHERE Booking__c = :bookingId AND Is_Agreement__c = TRUE
        ORDER BY Sequence__c ASC NULLS LAST
        LIMIT 1
      ];
      if (
        agreementSchedules.isEmpty() ||
        agreementSchedules[0].Sequence__c == null
      ) {
        throw new AuraHandledException(
          'Cannot raise Agreement Amount: no Agreement milestone with a sequence is configured.'
        );
      }
      agreementSequence = agreementSchedules[0].Sequence__c;
    }

    List<Payment_Schedule__c> schedules = [
      SELECT
        Id,
        Name,
        Milestone_Name__c,
        Is_Agreement__c,
        Status__c,
        Demand_Raised__c,
        Bank_Demand_Raised__c,
        Customer_Demand_Raised__c,
        Bank_Flat_Demand_Raised__c,
        Bank_GST_Demand_Raised__c,
        Customer_Flat_Demand_Raised__c,
        Customer_GST_Demand_Raised__c,
        Pending_Amount__c,
        Interest_Pending__c,
        Due_Date__c,
        Sequence__c,
        Payment_Schedule_Amount__c,
        Payment_Schedule_Amount_Pending__c,
        Payment_Schedule_Amount_Paid__c,
        TDS_Amount_Paid__c,
        GST_Amount__c,
        GST_Amount_Pending__c,
        GST_Amount_Paid__c,
        TDS_Amount__c,
        TDS_Amount_Pending__c,
        Bank_Flat_Amount__c,
        Bank_GST_Amount__c,
        Customer_Flat_Prorata__c,
        Customer_GST_Prorata__c,
        Booking__r.Funding_Type__c,
        Booking__r.Project__r.Legacy_Split_Demand_Receipt__c
      FROM Payment_Schedule__c
      WHERE
        Booking__c = :bookingId
        AND Status__c = :PostSalesConstants.SCHEDULE_STATUS_COMPLETED
      ORDER BY
        Sequence__c ASC NULLS LAST,
        Due_Date__c ASC NULLS LAST,
        CreatedDate ASC
    ];
    if (agreementOnly == true) {
      List<Payment_Schedule__c> agreementSchedules = new List<Payment_Schedule__c>();
      for (Payment_Schedule__c schedule : schedules) {
        if (
          schedule.Sequence__c != null &&
          schedule.Sequence__c <= agreementSequence
        ) {
          agreementSchedules.add(schedule);
        }
      }
      schedules = agreementSchedules;
    }
    Boolean prorataBankDemand =
      legacySplitDemandReceipt &&
      bookingContexts[0].Funding_Type__c != null &&
      SPLIT_FUNDING_TYPES.contains(bookingContexts[0].Funding_Type__c) &&
      hasBankSplit(schedules);
    Set<Id> sourceSplitScheduleIds = new Set<Id>();
    if (prorataBankDemand) {
      for (Payment_Schedule__c schedule : schedules) {
        if (DemandComponentService.hasAudienceSplit(schedule)) {
          sourceSplitScheduleIds.add(schedule.Id);
        }
      }
    }
    Map<Id, Map<String, DemandComponentService.ReceiptSourceTotals>> receiptTotalsBySchedule = DemandComponentService.getReceiptSourceTotals(
      sourceSplitScheduleIds
    );
    Set<Id> demandScheduleIds = new Set<Id>();
    if (
      prorataBankDemand && DemandComponentService.includesFlat(demandComponent)
    ) {
      for (Payment_Schedule__c schedule : schedules) {
        Boolean isBank =
          schedule.Booking__r.Funding_Type__c != null &&
          SPLIT_FUNDING_TYPES.contains(schedule.Booking__r.Funding_Type__c) &&
          (nz(schedule.Bank_Flat_Amount__c) != 0 ||
          nz(schedule.Bank_GST_Amount__c) != 0);
        Boolean sourceSpecificSchedule = DemandComponentService.hasAudienceSplit(
          schedule
        );
        if (
          isBank &&
          !DemandComponentService.isComponentRaised(
            schedule,
            DemandComponentService.FLAT,
            true
          ) &&
          DemandComponentService.amountByAudience(
            schedule,
            DemandComponentService.FLAT,
            true,
            sourceSpecificSchedule,
            receiptTotalsBySchedule
          ) > 0
        ) {
          demandScheduleIds.add(schedule.Id);
        }
      }
    }
    DemandComponentService.TdsCarryForwardAllocation carryForwardAllocation = demandScheduleIds.isEmpty()
      ? new DemandComponentService.TdsCarryForwardAllocation()
      : DemandComponentService.getTdsCarryForwardAllocation(
          new Set<Id>{ bookingId },
          demandScheduleIds
        );

    Decimal totalPending = 0;
    Decimal totalFlatAmount = 0;
    Decimal totalGstAmount = 0;
    Decimal totalTdsAmount = 0;
    Decimal totalInterest = 0;
    Id firstScheduleId;
    Date firstDueDate;
    Id latestScheduleId; // milestone with the highest Sequence__c among those included
    Decimal latestSequence;
    Boolean allBank = true;
    List<Payment_Schedule__c> schedulesToMarkDemanded = new List<Payment_Schedule__c>();
    List<Demand_Line__c> demandLines = new List<Demand_Line__c>();
    Set<Id> schedulesMissingDueDate = new Set<Id>();
    Set<Id> carryForwardDemandScheduleIds = new Set<Id>();
    for (Payment_Schedule__c ps : schedules) {
      Boolean isBank =
        prorataBankDemand &&
        ps.Booking__r.Funding_Type__c != null &&
        SPLIT_FUNDING_TYPES.contains(ps.Booking__r.Funding_Type__c) &&
        (nz(ps.Bank_Flat_Amount__c) != 0 ||
        nz(ps.Bank_GST_Amount__c) != 0);
      if (prorataBankDemand && !isBank)
        continue;
      if (DemandComponentService.isComponentRaised(ps, demandComponent, isBank))
        continue;
      Boolean sourceSpecificSchedule =
        prorataBankDemand && DemandComponentService.hasAudienceSplit(ps);
      Decimal p = DemandComponentService.amountByAudience(
        ps,
        demandComponent,
        isBank,
        sourceSpecificSchedule,
        receiptTotalsBySchedule
      );
      if (p <= 0)
        continue;
      if (!isBank)
        allBank = false;
      Decimal lineFlatAmount = 0;
      Decimal lineGstAmount = 0;
      Decimal lineTdsAmount = 0;
      if (demandComponent == DemandComponentService.FLAT) {
        Decimal tds = DemandComponentService.tdsAmountByAudience(
          ps,
          isBank,
          sourceSpecificSchedule,
          receiptTotalsBySchedule
        );
        if (prorataBankDemand && isBank) {
          Decimal carryForward = carryForwardAllocation.amountByDemandSchedule.containsKey(
              ps.Id
            )
            ? carryForwardAllocation.amountByDemandSchedule.get(ps.Id)
            : 0;
          tds += carryForward;
          if (carryForward > 0)
            carryForwardDemandScheduleIds.add(ps.Id);
          totalPending += p + tds;
          lineFlatAmount = p;
        } else {
          totalPending += p;
          lineFlatAmount = Math.max(0, p - tds);
        }
        lineTdsAmount = tds;
        totalFlatAmount += lineFlatAmount;
        totalTdsAmount += tds;
      } else if (demandComponent == DemandComponentService.GST) {
        totalPending += p;
        lineGstAmount = p;
        totalGstAmount += lineGstAmount;
      } else {
        Decimal flatWithTds = DemandComponentService.amount(
          ps,
          DemandComponentService.FLAT,
          isBank
        );
        Decimal tds = DemandComponentService.tdsAmountByAudience(
          ps,
          isBank,
          sourceSpecificSchedule,
          receiptTotalsBySchedule
        );
        if (prorataBankDemand && isBank) {
          Decimal carryForward = carryForwardAllocation.amountByDemandSchedule.containsKey(
              ps.Id
            )
            ? carryForwardAllocation.amountByDemandSchedule.get(ps.Id)
            : 0;
          flatWithTds += carryForward;
          tds += carryForward;
          if (carryForward > 0)
            carryForwardDemandScheduleIds.add(ps.Id);
        }
        lineFlatAmount = Math.max(0, flatWithTds - tds);
        lineGstAmount = nz(ps.GST_Amount_Pending__c);
        lineTdsAmount = tds;
        totalPending += lineFlatAmount + lineGstAmount + lineTdsAmount;
        totalFlatAmount += lineFlatAmount;
        totalGstAmount += lineGstAmount;
        totalTdsAmount += tds;
      }
      Decimal lineInterestAmount = DemandComponentService.includesFlat(
          demandComponent
        ) && includeInterest == true
        ? nz(ps.Interest_Pending__c)
        : 0;
      totalInterest += lineInterestAmount;
      demandLines.add(
        DemandLineService.createFromSchedule(
          ps,
          demandComponent,
          lineFlatAmount,
          lineGstAmount,
          lineTdsAmount,
          lineInterestAmount
        )
      );

      if (firstScheduleId == null)
        firstScheduleId = ps.Id;
      if (
        ps.Due_Date__c != null &&
        (firstDueDate == null ||
        ps.Due_Date__c < firstDueDate)
      ) {
        firstDueDate = ps.Due_Date__c;
      }
      // Track the latest milestone by sequence (the bigger Sequence__c number) among the
      // schedules actually included in this demand.
      if (
        ps.Sequence__c != null &&
        (latestSequence == null ||
        ps.Sequence__c > latestSequence)
      ) {
        latestSequence = ps.Sequence__c;
        latestScheduleId = ps.Id;
      }

      Payment_Schedule__c upd = new Payment_Schedule__c(Id = ps.Id);
      upd.Demand_Date__c = Date.today();
      DemandComponentService.markRaised(upd, demandComponent, isBank);
      schedulesToMarkDemanded.add(upd);
      if (ps.Due_Date__c == null)
        schedulesMissingDueDate.add(ps.Id);
    }

    if (useAmountOverrides == true) {
      if (
        demandComponent == DemandComponentService.GST &&
        (flatAmountOverride != 0 ||
        tdsAmountOverride != 0)
      ) {
        throw new AuraHandledException(
          'GST demands cannot include Flat or TDS amounts.'
        );
      }
      if (
        demandComponent == DemandComponentService.FLAT &&
        gstAmountOverride != 0
      ) {
        throw new AuraHandledException(
          'Flat demands cannot include a GST amount.'
        );
      }
      totalFlatAmount = flatAmountOverride;
      totalGstAmount = gstAmountOverride;
      totalTdsAmount = tdsAmountOverride;
      totalPending = totalFlatAmount + totalGstAmount + totalTdsAmount;
      DemandLineService.applyAmountOverrides(
        demandLines,
        demandComponent,
        totalFlatAmount,
        totalGstAmount,
        totalTdsAmount
      );
    }

    if (totalPending <= 0) {
      throw new AuraHandledException(
        'Nothing to raise: no completed payment schedule has a pending ' +
          demandComponent +
          ' amount.'
      );
    }

    // Previous dues: milestones on this booking already demanded but still unpaid. These are
    // NOT re-raised here (they stay pending on their original demand); they are surfaced on
    // this demand so Net_Demand_Amount__c (= Demand Amount + Previous Dues + Interest) reflects
    // the customer's full outstanding — matching the Bulk Raise Demand behaviour. Runs before
    // the schedules raised now are marked demanded, so those aren't counted here.
    Decimal previousDues = 0;
    if (DemandComponentService.includesFlat(demandComponent)) {
      for (AggregateResult ar : [
        SELECT SUM(Pending_Amount__c) prev
        FROM Payment_Schedule__c
        WHERE
          Booking__c = :bookingId
          AND Demand_Raised__c = TRUE
          AND Pending_Amount__c > 0
      ]) {
        Object prev = ar.get('prev');
        if (prev != null)
          previousDues = (Decimal) prev;
      }
    }

    Demands__c demand = new Demands__c();
    demand.Booking__c = bookingId;
    // Current demand principal only. Interest goes in Interest_Amount__c and previous dues in
    // Previous_Dues__c; the Net_Demand_Amount__c formula sums all three, so interest must NOT
    // also sit inside Demand_Amount__c or it would be double-counted in the net.
    demand.Demand_Amount__c = totalPending;
    demand.Pending_Amount__c = totalPending;
    demand.Previous_Dues__c = previousDues;
    Decimal waiverAmount = 0;
    if (
      DemandComponentService.includesFlat(demandComponent) &&
      includeInterest == true
    ) {
      Decimal remainingWaiver = InterestWaiverService.getRemainingWaivers(
          new Set<Id>{ bookingId },
          true
        )
        .get(bookingId);
      waiverAmount = InterestWaiverService.getWaiverAmount(
        totalInterest,
        remainingWaiver
      );
    }
    demand.Interest_Amount__c = totalInterest - waiverAmount;
    demand.Interest_Waived_Off_Amount__c = waiverAmount;
    demand.Flat_Amount__c = totalFlatAmount;
    demand.Base_Amount__c = totalFlatAmount;
    demand.GST_Amount__c = totalGstAmount;
    demand.TDS_Amount__c = totalTdsAmount;
    demand.Demand_Component__c = demandComponent;
    demand.Demand_Date__c = Date.today();
    demand.Due_Date__c = firstDueDate != null
      ? firstDueDate
      : Date.today().addDays(30);
    for (Payment_Schedule__c scheduleUpdate : schedulesToMarkDemanded) {
      if (schedulesMissingDueDate.contains(scheduleUpdate.Id)) {
        scheduleUpdate.Due_Date__c = demand.Due_Date__c;
      }
    }
    // 'Individual Demand' is the active picklist value matching a one-off,
    // booking-scoped demand. PostSalesConstants.DEMAND_TYPE_AUTO maps to
    // 'Auto Demand' which is intentionally inactive on the picklist.
    demand.Demand_Type__c = agreementOnly == true
      ? 'Agreement Amount'
      : (allBank ? 'Bank Demand' : 'Individual Demand');
    demand.Demand_Audience__c = allBank ? 'Bank' : 'Customer';
    demand.Status__c = PostSalesConstants.DEMAND_STATUS_RAISED;
    // Link to the latest milestone (highest Sequence__c) included in this demand, falling
    // back to the earliest-due schedule if none of the included rows had a sequence value.
    demand.Payment_Schedule__c = latestScheduleId != null
      ? latestScheduleId
      : firstScheduleId;

    // Insert the demand and mark every included milestone's schedule as demanded together —
    // if either DML fails, roll back both rather than leaving an orphaned demand with
    // schedules that still show as not-yet-demanded.
    Savepoint sp = Database.setSavepoint();
    DemandLineService.stageForInsert(demand, demandLines);
    try {
      insert demand;
      DemandLineService.clearStagedLines();
      Map<Id, Payment_Schedule__c> updatesById = new Map<Id, Payment_Schedule__c>();
      for (Payment_Schedule__c scheduleUpdate : schedulesToMarkDemanded) {
        updatesById.put(scheduleUpdate.Id, scheduleUpdate);
      }
      if (useAmountOverrides != true) {
        DemandComponentService.addTdsCarryForwardDemandedUpdates(
          carryForwardAllocation,
          carryForwardDemandScheduleIds,
          updatesById
        );
      }
      if (!updatesById.isEmpty()) {
        update updatesById.values();
      }
    } catch (DmlException e) {
      Database.rollback(sp);
      throw new AuraHandledException(
        'Could not raise demand: ' + e.getDmlMessage(0)
      );
    }
    return demand.Id;
  }

  /**
   * @description Save edited payment schedule amounts.
   *              Only updates Amount__c, Pending_Amount__c, Payment_Schedule_Amount__c
   *              for schedules where demand has not been raised.
   * @param amountsJson JSON map of scheduleId -> newAmount
   */
  /**
   * @description Save edited payment schedule amounts with validation.
   *              Validates that total of all schedule amounts equals booking's
   *              Total_Payable_Amount__c before saving.
   * @param bookingId The booking these schedules belong to
   * @param amountsJson JSON map of scheduleId -> newAmount
   */
  @AuraEnabled
  public static void saveScheduleAmounts(String bookingId, String amountsJson) {
    try {
      Map<String, Object> amounts = (Map<String, Object>) JSON.deserializeUntyped(
        amountsJson
      );
      if (amounts.isEmpty())
        return;

      // Get booking total
      Booking__c booking = [
        SELECT Id, Total_Payable_Amount__c, Grand_Total__c
        FROM Booking__c
        WHERE Id = :bookingId
        LIMIT 1
      ];

      Decimal bookingTotal = booking.Total_Payable_Amount__c != null
        ? booking.Total_Payable_Amount__c
        : (booking.Grand_Total__c != null ? booking.Grand_Total__c : 0);

      // Get ALL schedules for this booking (not just edited ones)
      List<Payment_Schedule__c> allSchedules = [
        SELECT
          Id,
          Amount__c,
          Pending_Amount__c,
          Amount_Paid__c,
          Payment_Schedule_Amount__c,
          GST_Amount__c,
          Payment_Schedule_Amount_Pending__c,
          GST_Amount_Pending__c,
          Demand_Raised__c,
          Status__c
        FROM Payment_Schedule__c
        WHERE Booking__c = :bookingId
      ];

      // Calculate what the new total would be after applying changes
      Decimal newTotal = 0;
      List<Payment_Schedule__c> toUpdate = new List<Payment_Schedule__c>();

      for (Payment_Schedule__c ps : allSchedules) {
        Object newAmountObj = amounts.get(ps.Id);

        if (newAmountObj != null) {
          // This schedule is being edited
          Boolean anyAmountPaid =
            ps.Amount_Paid__c != null &&
            ps.Amount_Paid__c > 0;
          if (
            ps.Demand_Raised__c == true ||
            anyAmountPaid ||
            ps.Status__c == PostSalesConstants.SCHEDULE_STATUS_PAID ||
            ps.Status__c == PostSalesConstants.SCHEDULE_STATUS_COMPLETED
          ) {
            throw new AuraHandledException(
              'Cannot edit schedule ' +
                ps.Id +
                ' — demand already raised, amount already paid, ' +
                'or schedule is paid/completed.'
            );
          }

          Decimal newAmount = Decimal.valueOf(String.valueOf(newAmountObj));
          if (newAmount < 0) {
            throw new AuraHandledException('Amount cannot be negative.');
          }

          newTotal += newAmount;

          Decimal paid = ps.Amount_Paid__c != null ? ps.Amount_Paid__c : 0;
          ps.Amount__c = newAmount;
          ps.Pending_Amount__c = Math.max(0, newAmount - paid);
          ps.Payment_Schedule_Amount__c = newAmount;
          ps.Payment_Schedule_Amount_Pending__c = Math.max(0, newAmount - paid);
          toUpdate.add(ps);
        } else {
          // Unchanged schedule — use existing amount
          newTotal += (ps.Amount__c != null ? ps.Amount__c : 0);
        }
      }

      // Validate total matches booking total
      if (
        bookingTotal > 0 &&
        newTotal.setScale(2) != bookingTotal.setScale(2)
      ) {
        throw new AuraHandledException(
          'Total of all schedule amounts (₹' +
            newTotal.setScale(2).format() +
            ') must equal the booking total payable amount (₹' +
            bookingTotal.setScale(2).format() +
            '). Difference: ₹' +
            (bookingTotal - newTotal).setScale(2).format()
        );
      }

      if (!toUpdate.isEmpty()) {
        // BRD 8.2: amount edits are staged for approval, not written directly. Build a
        // revision and submit it; values are applied once the revision is approved.
        List<PaymentScheduleRevisionService.RevisionLine> lines = new List<PaymentScheduleRevisionService.RevisionLine>();
        for (Payment_Schedule__c ps : toUpdate) {
          PaymentScheduleRevisionService.RevisionLine line = new PaymentScheduleRevisionService.RevisionLine();
          line.id = ps.Id;
          line.amount = ps.Amount__c;
          line.baseAmount = ps.Payment_Schedule_Amount__c;
          lines.add(line);
        }
        PaymentScheduleRevisionService.stageAndSubmit(
          (Id) bookingId,
          lines,
          null
        );
      }
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException('Error saving amounts: ' + e.getMessage());
    }
  }
}