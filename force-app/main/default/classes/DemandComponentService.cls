public with sharing class DemandComponentService {
  public static final String FLAT = 'Flat';
  public static final String GST = 'GST';
  public static final String FLAT_AND_GST = 'Flat + GST';
  public static final String TIME_BASED_PAYMENT_TYPE = 'Time Based';
  private static final Set<String> SPLIT_FUNDING_TYPES = new Set<String>{
    'Loan',
    'Bank Loan',
    'NBFC Loan',
    'Mixed Funding',
    'Prorata',
    'Partial'
  };

  public class ReceiptSourceTotals {
    public Decimal flatAmount = 0;
    public Decimal gstAmount = 0;
    public Decimal tdsAmount = 0;
  }

  public static Boolean isComponentRaised(
    Payment_Schedule__c schedule,
    String component,
    Boolean bankSide
  ) {
    if (component == FLAT_AND_GST) {
      return schedule.Demand_Raised__c == true ||
        schedule.Bank_Flat_Demand_Raised__c == true ||
        schedule.Bank_GST_Demand_Raised__c == true ||
        schedule.Customer_Flat_Demand_Raised__c == true ||
        schedule.Customer_GST_Demand_Raised__c == true;
    }

    Boolean bankFlatRaised = schedule.Bank_Flat_Demand_Raised__c == true;
    Boolean bankGstRaised = schedule.Bank_GST_Demand_Raised__c == true;
    Boolean customerFlatRaised =
      schedule.Customer_Flat_Demand_Raised__c == true;
    Boolean customerGstRaised = schedule.Customer_GST_Demand_Raised__c == true;
    Boolean hasComponentHistory =
      bankFlatRaised ||
      bankGstRaised ||
      customerFlatRaised ||
      customerGstRaised;

    if (bankSide) {
      if (component == FLAT && bankFlatRaised)
        return true;
      if (component == GST && bankGstRaised)
        return true;
      if (hasComponentHistory)
        return false;
      if (schedule.Bank_Demand_Raised__c == true)
        return true;
      return schedule.Demand_Raised__c == true &&
        schedule.Customer_Demand_Raised__c != true;
    }

    if (component == FLAT && customerFlatRaised)
      return true;
    if (component == GST && customerGstRaised)
      return true;
    if (hasComponentHistory)
      return false;
    if (schedule.Customer_Demand_Raised__c == true)
      return true;
    return schedule.Demand_Raised__c == true &&
      schedule.Bank_Demand_Raised__c != true &&
      schedule.Customer_Demand_Raised__c != true;
  }

  public static Boolean isTimeBasedSchedule(Payment_Schedule__c schedule) {
    return schedule != null &&
      ((schedule.Master_Payment_Schedule__r != null &&
      schedule.Master_Payment_Schedule__r.Payment_Type__c ==
      TIME_BASED_PAYMENT_TYPE) ||
      schedule.Milestone_Name__c == TIME_BASED_PAYMENT_TYPE);
  }

  public static Boolean hasAudienceSplit(Payment_Schedule__c schedule) {
    return schedule != null &&
      (schedule.Bank_Flat_Amount__c != null ||
      schedule.Bank_GST_Amount__c != null ||
      schedule.Customer_Flat_Prorata__c != null ||
      schedule.Customer_GST_Prorata__c != null);
  }

  public static Map<Id, Map<String, ReceiptSourceTotals>> getReceiptSourceTotals(
    Set<Id> scheduleIds
  ) {
    Map<Id, Map<String, ReceiptSourceTotals>> totalsBySchedule = new Map<Id, Map<String, ReceiptSourceTotals>>();
    if (scheduleIds == null || scheduleIds.isEmpty())
      return totalsBySchedule;

    for (AggregateResult result : [
      SELECT
        Payment_Schedule__c scheduleId,
        Receipt__r.Payment_From__c paymentFrom,
        SUM(Base_Amount__c) flatAmount,
        SUM(GST_Amount__c) gstAmount,
        SUM(TDS_Amount__c) tdsAmount
      FROM Receipt_Line_Item__c
      WHERE
        Payment_Schedule__c IN :scheduleIds
        AND Receipt__r.Payment_From__c IN ('Bank', 'Customer')
        AND Receipt__r.Approval_Status__c != 'Rejected'
      GROUP BY Payment_Schedule__c, Receipt__r.Payment_From__c
    ]) {
      Id scheduleId = (Id) result.get('scheduleId');
      String paymentFrom = (String) result.get('paymentFrom');
      ReceiptSourceTotals totals = new ReceiptSourceTotals();
      totals.flatAmount = result.get('flatAmount') == null
        ? 0
        : (Decimal) result.get('flatAmount');
      totals.gstAmount = result.get('gstAmount') == null
        ? 0
        : (Decimal) result.get('gstAmount');
      totals.tdsAmount = result.get('tdsAmount') == null
        ? 0
        : (Decimal) result.get('tdsAmount');
      if (!totalsBySchedule.containsKey(scheduleId)) {
        totalsBySchedule.put(
          scheduleId,
          new Map<String, ReceiptSourceTotals>()
        );
      }
      totalsBySchedule.get(scheduleId).put(paymentFrom, totals);
    }
    return totalsBySchedule;
  }

  public static ReceiptSourceTotals getReceiptSourceTotals(
    Map<Id, Map<String, ReceiptSourceTotals>> totalsBySchedule,
    Id scheduleId,
    Boolean bankSide
  ) {
    String paymentFrom = bankSide == true ? 'Bank' : 'Customer';
    Map<String, ReceiptSourceTotals> totalsBySource = totalsBySchedule.get(
      scheduleId
    );
    return totalsBySource != null && totalsBySource.containsKey(paymentFrom)
      ? totalsBySource.get(paymentFrom)
      : new ReceiptSourceTotals();
  }

  public static Decimal amountByAudience(
    Payment_Schedule__c schedule,
    String component,
    Boolean bankSide,
    Boolean sourceSpecific,
    Map<Id, Map<String, ReceiptSourceTotals>> receiptTotalsBySchedule
  ) {
    if (sourceSpecific != true || !hasAudienceSplit(schedule)) {
      return amount(schedule, component, bankSide);
    }

    if (component == FLAT_AND_GST) {
      return audienceComponentPrincipal(
          schedule,
          FLAT,
          bankSide,
          receiptTotalsBySchedule
        ) +
        audienceComponentPrincipal(
          schedule,
          GST,
          bankSide,
          receiptTotalsBySchedule
        );
    }
    Decimal componentAmount = audienceComponentPrincipal(
      schedule,
      component,
      bankSide,
      receiptTotalsBySchedule
    );
    if (!bankSide && component == FLAT) {
      componentAmount += audienceTdsPending(
        schedule,
        false,
        receiptTotalsBySchedule
      );
    }
    return componentAmount;
  }

  public static Decimal tdsAmountByAudience(
    Payment_Schedule__c schedule,
    Boolean bankSide,
    Boolean sourceSpecific,
    Map<Id, Map<String, ReceiptSourceTotals>> receiptTotalsBySchedule
  ) {
    if (sourceSpecific == true && hasAudienceSplit(schedule)) {
      return audienceTdsPending(schedule, bankSide, receiptTotalsBySchedule);
    }
    if (!bankSide)
      return nz(schedule.TDS_Amount_Pending__c);

    Decimal pendingFlat = amount(schedule, FLAT, true);
    return pendingFlat <= 0
      ? 0
      : (pendingFlat * 0.01).setScale(2, System.RoundingMode.HALF_UP);
  }

  private static Decimal audienceComponentPrincipal(
    Payment_Schedule__c schedule,
    String component,
    Boolean bankSide,
    Map<Id, Map<String, ReceiptSourceTotals>> receiptTotalsBySchedule
  ) {
    Decimal componentShare;
    if (bankSide) {
      componentShare = component == FLAT
        ? nz(schedule.Bank_Flat_Amount__c)
        : nz(schedule.Bank_GST_Amount__c);
    } else {
      componentShare = component == FLAT
        ? nz(schedule.Customer_Flat_Prorata__c)
        : nz(schedule.Customer_GST_Prorata__c);
    }
    ReceiptSourceTotals sourceTotals = getReceiptSourceTotals(
      receiptTotalsBySchedule,
      schedule.Id,
      bankSide
    );
    Decimal received = component == FLAT
      ? sourceTotals.flatAmount
      : sourceTotals.gstAmount;
    return Math.max(0, componentShare - received);
  }

  private static Decimal audienceTdsPending(
    Payment_Schedule__c schedule,
    Boolean bankSide,
    Map<Id, Map<String, ReceiptSourceTotals>> receiptTotalsBySchedule
  ) {
    Decimal bankFlatOutstanding = audienceComponentPrincipal(
      schedule,
      FLAT,
      true,
      receiptTotalsBySchedule
    );
    Decimal customerFlatOutstanding = audienceComponentPrincipal(
      schedule,
      FLAT,
      false,
      receiptTotalsBySchedule
    );
    Decimal bankTdsOutstanding = (bankFlatOutstanding * 0.01)
      .setScale(2, System.RoundingMode.HALF_UP);
    Decimal customerTdsOutstanding = (customerFlatOutstanding * 0.01)
      .setScale(2, System.RoundingMode.HALF_UP);
    Decimal customerTdsPaid = getReceiptSourceTotals(
      receiptTotalsBySchedule,
      schedule.Id,
      false
    ).tdsAmount;

    if (bankSide) {
      Decimal customerTdsExcess = Math.max(
        0,
        customerTdsPaid - customerTdsOutstanding
      );
      return Math.max(0, bankTdsOutstanding - customerTdsExcess);
    }
    return Math.max(0, customerTdsOutstanding - customerTdsPaid);
  }

  public static Decimal amount(
    Payment_Schedule__c schedule,
    String component,
    Boolean bankSide
  ) {
    Decimal componentAmount;
    if (component == FLAT_AND_GST) {
      componentAmount =
        nz(schedule.Payment_Schedule_Amount_Pending__c) +
        nz(schedule.GST_Amount_Pending__c);
    } else if (bankSide) {
      componentAmount = component == FLAT
        ? nz(schedule.Bank_Flat_Amount__c)
        : nz(schedule.Bank_GST_Amount__c);
      componentAmount -= component == FLAT
        ? nz(schedule.Payment_Schedule_Amount_Paid__c)
        : nz(schedule.GST_Amount_Paid__c);
    } else {
      Boolean hasCustomerSplit =
        schedule.Booking__r != null &&
        schedule.Booking__r.Project__r != null &&
        schedule.Booking__r.Project__r.Legacy_Split_Demand_Receipt__c == true &&
        SPLIT_FUNDING_TYPES.contains(schedule.Booking__r.Funding_Type__c) &&
        (schedule.Customer_Flat_Prorata__c != null ||
        schedule.Customer_GST_Prorata__c != null);
      if (hasCustomerSplit) {
        componentAmount = component == FLAT
          ? nz(schedule.Customer_Flat_Prorata__c)
          : nz(schedule.Customer_GST_Prorata__c);
        componentAmount -= component == FLAT
          ? nz(schedule.Payment_Schedule_Amount_Paid__c)
          : nz(schedule.GST_Amount_Paid__c);
      } else {
        componentAmount = component == FLAT
          ? nz(schedule.Payment_Schedule_Amount_Pending__c)
          : nz(schedule.GST_Amount_Pending__c);
      }
    }
    componentAmount = Math.max(0, componentAmount);
    if (!bankSide && includesFlat(component)) {
      componentAmount += nz(schedule.TDS_Amount_Pending__c);
    }
    return componentAmount;
  }

  public static void markRaised(
    Payment_Schedule__c scheduleUpdate,
    String component,
    Boolean bankSide
  ) {
    scheduleUpdate.Demand_Raised__c = true;
    if (bankSide) {
      scheduleUpdate.Bank_Demand_Raised__c = true;
      if (component == FLAT || component == FLAT_AND_GST)
        scheduleUpdate.Bank_Flat_Demand_Raised__c = true;
      if (component == GST || component == FLAT_AND_GST)
        scheduleUpdate.Bank_GST_Demand_Raised__c = true;
    } else {
      scheduleUpdate.Customer_Demand_Raised__c = true;
      if (component == FLAT || component == FLAT_AND_GST)
        scheduleUpdate.Customer_Flat_Demand_Raised__c = true;
      if (component == GST || component == FLAT_AND_GST)
        scheduleUpdate.Customer_GST_Demand_Raised__c = true;
    }
  }

  public static Boolean includesFlat(String component) {
    return component == FLAT || component == FLAT_AND_GST;
  }

  public static Boolean isFlatDemandedOnEitherSide(
    Payment_Schedule__c schedule
  ) {
    return isComponentRaised(schedule, FLAT, true) ||
      isComponentRaised(schedule, FLAT, false);
  }

  public static Decimal undemandedTdsFromPaidFlat(
    Payment_Schedule__c schedule
  ) {
    Decimal paidFlat = nz(schedule.Payment_Schedule_Amount_Paid__c);
    Decimal pendingTds = nz(schedule.TDS_Amount_Pending__c);
    if (paidFlat <= 0 || pendingTds <= 0)
      return 0;

    Decimal unpaidTdsOnPaidFlat =
      (paidFlat * 0.01).setScale(2, System.RoundingMode.HALF_UP) -
      nz(schedule.TDS_Amount_Paid__c);
    return Math.min(pendingTds, Math.max(0, unpaidTdsOnPaidFlat));
  }

  public static Decimal undemandedTdsFromPaidFlatByAudience(
    Payment_Schedule__c schedule,
    Boolean bankSide,
    Boolean sourceSpecific,
    Map<Id, Map<String, ReceiptSourceTotals>> receiptTotalsBySchedule
  ) {
    if (sourceSpecific != true || !hasAudienceSplit(schedule)) {
      return undemandedTdsFromPaidFlat(schedule);
    }
    return 0;
  }

  public class TdsCarryForwardAllocation {
    public Map<Id, Decimal> amountByDemandSchedule = new Map<Id, Decimal>();
    public Map<Id, Map<Id, Decimal>> sourcesByDemandSchedule = new Map<Id, Map<Id, Decimal>>();
  }

  public static TdsCarryForwardAllocation getTdsCarryForwardAllocation(
    Set<Id> bookingIds,
    Set<Id> demandScheduleIds
  ) {
    TdsCarryForwardAllocation allocation = new TdsCarryForwardAllocation();
    if (
      bookingIds == null ||
      bookingIds.isEmpty() ||
      demandScheduleIds == null ||
      demandScheduleIds.isEmpty()
    ) {
      return allocation;
    }

    List<Payment_Schedule__c> history = [
      SELECT
        Id,
        Booking__c,
        Sequence__c,
        Payment_Schedule_Amount_Paid__c,
        TDS_Amount_Paid__c,
        TDS_Amount_Pending__c,
        Bank_Flat_Amount__c,
        Bank_GST_Amount__c,
        Customer_Flat_Prorata__c,
        Customer_GST_Prorata__c,
        Booking__r.Funding_Type__c,
        Booking__r.Project__r.Legacy_Split_Demand_Receipt__c,
        Demand_Raised__c,
        Bank_Demand_Raised__c,
        Customer_Demand_Raised__c,
        Bank_Flat_Demand_Raised__c,
        Customer_Flat_Demand_Raised__c,
        Bank_GST_Demand_Raised__c,
        Customer_GST_Demand_Raised__c
      FROM Payment_Schedule__c
      WHERE Booking__c IN :bookingIds
      ORDER BY Booking__c, Sequence__c ASC, CreatedDate ASC
    ];
    Set<Id> sourceSplitScheduleIds = new Set<Id>();
    for (Payment_Schedule__c schedule : history) {
      if (
        schedule.Booking__r != null &&
        schedule.Booking__r.Project__r != null &&
        schedule.Booking__r.Project__r.Legacy_Split_Demand_Receipt__c == true &&
        SPLIT_FUNDING_TYPES.contains(schedule.Booking__r.Funding_Type__c) &&
        hasAudienceSplit(schedule)
      ) {
        sourceSplitScheduleIds.add(schedule.Id);
      }
    }
    Map<Id, Map<String, ReceiptSourceTotals>> receiptTotalsBySchedule = getReceiptSourceTotals(
      sourceSplitScheduleIds
    );

    Map<Id, Decimal> carryForwardByBooking = new Map<Id, Decimal>();
    Map<Id, Map<Id, Decimal>> sourcesByBooking = new Map<Id, Map<Id, Decimal>>();
    for (Payment_Schedule__c schedule : history) {
      Decimal carryForward = carryForwardByBooking.containsKey(
          schedule.Booking__c
        )
        ? carryForwardByBooking.get(schedule.Booking__c)
        : 0;
      Map<Id, Decimal> sources = sourcesByBooking.containsKey(
          schedule.Booking__c
        )
        ? sourcesByBooking.get(schedule.Booking__c)
        : new Map<Id, Decimal>();

      Boolean sourceSpecificSchedule =
        schedule.Booking__r != null &&
        schedule.Booking__r.Project__r != null &&
        schedule.Booking__r.Project__r.Legacy_Split_Demand_Receipt__c == true &&
        SPLIT_FUNDING_TYPES.contains(schedule.Booking__r.Funding_Type__c) &&
        hasAudienceSplit(schedule);
      Boolean flatDemanded = isFlatDemandedOnEitherSide(schedule);
      if (!flatDemanded) {
        Decimal unpaidTds = undemandedTdsFromPaidFlatByAudience(
          schedule,
          true,
          sourceSpecificSchedule,
          receiptTotalsBySchedule
        );
        if (unpaidTds > 0) {
          carryForward += unpaidTds;
          sources.put(schedule.Id, unpaidTds);
        }
      }

      if (
        demandScheduleIds.contains(schedule.Id) &&
        !flatDemanded &&
        amountByAudience(
          schedule,
          FLAT,
          true,
          sourceSpecificSchedule,
          receiptTotalsBySchedule
        ) > 0
      ) {
        allocation.amountByDemandSchedule.put(schedule.Id, carryForward);
        Map<Id, Decimal> sourcesForDemand = new Map<Id, Decimal>();
        sourcesForDemand.putAll(sources);
        allocation.sourcesByDemandSchedule.put(schedule.Id, sourcesForDemand);
        carryForward = 0;
        sources = new Map<Id, Decimal>();
      }
      carryForwardByBooking.put(schedule.Booking__c, carryForward);
      sourcesByBooking.put(schedule.Booking__c, sources);
    }
    return allocation;
  }

  public static void addTdsCarryForwardDemandedUpdates(
    TdsCarryForwardAllocation allocation,
    Set<Id> demandScheduleIds,
    Map<Id, Payment_Schedule__c> updatesById
  ) {
    if (allocation == null || demandScheduleIds == null || updatesById == null)
      return;
    for (Id demandScheduleId : demandScheduleIds) {
      Map<Id, Decimal> sourceAmounts = allocation.sourcesByDemandSchedule.get(
        demandScheduleId
      );
      if (sourceAmounts == null)
        continue;
      for (Id sourceScheduleId : sourceAmounts.keySet()) {
        Payment_Schedule__c updateRecord = updatesById.get(sourceScheduleId);
        if (updateRecord == null) {
          updateRecord = new Payment_Schedule__c(Id = sourceScheduleId);
          updatesById.put(sourceScheduleId, updateRecord);
        }
        markRaised(updateRecord, FLAT, true);
      }
    }
  }

  public static Decimal nz(Decimal value) {
    return value == null ? 0 : value;
  }
}