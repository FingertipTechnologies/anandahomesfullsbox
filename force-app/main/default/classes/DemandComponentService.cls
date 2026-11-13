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

    public static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }
}