public with sharing class DemandComponentService {
    public static final String FLAT = 'Flat';
    public static final String GST = 'GST';
    public static final String FLAT_AND_GST = 'Flat + GST';
    public static final String TIME_BASED_PAYMENT_TYPE = 'Time Based';
    private static final Set<String> SPLIT_FUNDING_TYPES = new Set<String>{
        'Loan', 'Bank Loan', 'NBFC Loan', 'Mixed Funding', 'Prorata', 'Partial'
    };

    public static Boolean isComponentRaised(Payment_Schedule__c schedule, String component, Boolean bankSide) {
        if (component == FLAT_AND_GST) {
            return schedule.Demand_Raised__c == true
                || schedule.Bank_Flat_Demand_Raised__c == true
                || schedule.Bank_GST_Demand_Raised__c == true
                || schedule.Customer_Flat_Demand_Raised__c == true
                || schedule.Customer_GST_Demand_Raised__c == true;
        }

        Boolean bankFlatRaised = schedule.Bank_Flat_Demand_Raised__c == true;
        Boolean bankGstRaised = schedule.Bank_GST_Demand_Raised__c == true;
        Boolean customerFlatRaised = schedule.Customer_Flat_Demand_Raised__c == true;
        Boolean customerGstRaised = schedule.Customer_GST_Demand_Raised__c == true;
        Boolean hasComponentHistory = bankFlatRaised || bankGstRaised || customerFlatRaised || customerGstRaised;

        if (bankSide) {
            if (component == FLAT && bankFlatRaised) return true;
            if (component == GST && bankGstRaised) return true;
            if (hasComponentHistory) return false;
            if (schedule.Bank_Demand_Raised__c == true) return true;
            return schedule.Demand_Raised__c == true
                && schedule.Customer_Demand_Raised__c != true;
        }

        if (component == FLAT && customerFlatRaised) return true;
        if (component == GST && customerGstRaised) return true;
        if (hasComponentHistory) return false;
        if (schedule.Customer_Demand_Raised__c == true) return true;
        return schedule.Demand_Raised__c == true
            && schedule.Bank_Demand_Raised__c != true
            && schedule.Customer_Demand_Raised__c != true;
    }

    public static Boolean isTimeBasedSchedule(Payment_Schedule__c schedule) {
        return schedule != null
            && ((schedule.Master_Payment_Schedule__r != null
                    && schedule.Master_Payment_Schedule__r.Payment_Type__c == TIME_BASED_PAYMENT_TYPE)
                || schedule.Milestone_Name__c == TIME_BASED_PAYMENT_TYPE);
    }

    public static Decimal amount(Payment_Schedule__c schedule, String component, Boolean bankSide) {
        Decimal componentAmount;
        if (component == FLAT_AND_GST) {
            componentAmount = nz(schedule.Payment_Schedule_Amount_Pending__c)
                + nz(schedule.GST_Amount_Pending__c);
        } else if (bankSide) {
            componentAmount = component == FLAT
                ? nz(schedule.Bank_Flat_Amount__c)
                : nz(schedule.Bank_GST_Amount__c);
            componentAmount -= component == FLAT
                ? nz(schedule.Payment_Schedule_Amount_Paid__c)
                : nz(schedule.GST_Amount_Paid__c);
        } else {
            Boolean hasCustomerSplit = schedule.Booking__r != null
                && schedule.Booking__r.Project__r != null
                && schedule.Booking__r.Project__r.Legacy_Split_Demand_Receipt__c == true
                && SPLIT_FUNDING_TYPES.contains(schedule.Booking__r.Funding_Type__c)
                && (schedule.Customer_Flat_Prorata__c != null || schedule.Customer_GST_Prorata__c != null);
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

    public static void markRaised(Payment_Schedule__c scheduleUpdate, String component, Boolean bankSide) {
        scheduleUpdate.Demand_Raised__c = true;
        if (bankSide) {
            scheduleUpdate.Bank_Demand_Raised__c = true;
            if (component == FLAT || component == FLAT_AND_GST) scheduleUpdate.Bank_Flat_Demand_Raised__c = true;
            if (component == GST || component == FLAT_AND_GST) scheduleUpdate.Bank_GST_Demand_Raised__c = true;
        } else {
            scheduleUpdate.Customer_Demand_Raised__c = true;
            if (component == FLAT || component == FLAT_AND_GST) scheduleUpdate.Customer_Flat_Demand_Raised__c = true;
            if (component == GST || component == FLAT_AND_GST) scheduleUpdate.Customer_GST_Demand_Raised__c = true;
        }
    }

    public static Boolean includesFlat(String component) {
        return component == FLAT || component == FLAT_AND_GST;
    }

    public static Boolean isFlatDemandedOnEitherSide(Payment_Schedule__c schedule) {
        return isComponentRaised(schedule, FLAT, true)
            || isComponentRaised(schedule, FLAT, false);
    }

    public static Decimal undemandedTdsFromPaidFlat(Payment_Schedule__c schedule) {
        Decimal paidFlat = nz(schedule.Payment_Schedule_Amount_Paid__c);
        Decimal pendingTds = nz(schedule.TDS_Amount_Pending__c);
        if (paidFlat <= 0 || pendingTds <= 0) return 0;

        Decimal unpaidTdsOnPaidFlat = (paidFlat * 0.01)
            .setScale(2, System.RoundingMode.HALF_UP)
            - nz(schedule.TDS_Amount_Paid__c);
        return Math.min(pendingTds, Math.max(0, unpaidTdsOnPaidFlat));
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
        if (bookingIds == null || bookingIds.isEmpty()
            || demandScheduleIds == null || demandScheduleIds.isEmpty()) {
            return allocation;
        }

        List<Payment_Schedule__c> history = [
            SELECT Id, Booking__c, Sequence__c, Payment_Schedule_Amount_Paid__c,
                   TDS_Amount_Paid__c, TDS_Amount_Pending__c, Bank_Flat_Amount__c,
                   Demand_Raised__c, Bank_Demand_Raised__c, Customer_Demand_Raised__c,
                   Bank_Flat_Demand_Raised__c, Customer_Flat_Demand_Raised__c,
                   Bank_GST_Demand_Raised__c, Customer_GST_Demand_Raised__c
            FROM Payment_Schedule__c
            WHERE Booking__c IN :bookingIds
            ORDER BY Booking__c, Sequence__c ASC, CreatedDate ASC
        ];

        Map<Id, Decimal> carryForwardByBooking = new Map<Id, Decimal>();
        Map<Id, Map<Id, Decimal>> sourcesByBooking = new Map<Id, Map<Id, Decimal>>();
        for (Payment_Schedule__c schedule : history) {
            Decimal carryForward = carryForwardByBooking.containsKey(schedule.Booking__c)
                ? carryForwardByBooking.get(schedule.Booking__c) : 0;
            Map<Id, Decimal> sources = sourcesByBooking.containsKey(schedule.Booking__c)
                ? sourcesByBooking.get(schedule.Booking__c) : new Map<Id, Decimal>();

            Boolean flatDemanded = isFlatDemandedOnEitherSide(schedule);
            if (!flatDemanded) {
                Decimal unpaidTds = undemandedTdsFromPaidFlat(schedule);
                if (unpaidTds > 0) {
                    carryForward += unpaidTds;
                    sources.put(schedule.Id, unpaidTds);
                }
            }

            if (demandScheduleIds.contains(schedule.Id)
                && !flatDemanded
                && amount(schedule, FLAT, true) > 0) {
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
        if (allocation == null || demandScheduleIds == null || updatesById == null) return;
        for (Id demandScheduleId : demandScheduleIds) {
            Map<Id, Decimal> sourceAmounts =
                allocation.sourcesByDemandSchedule.get(demandScheduleId);
            if (sourceAmounts == null) continue;
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