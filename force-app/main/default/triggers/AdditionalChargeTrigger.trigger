/**
 * @description Trigger on Additional_Charge__c. Seeds 1st/2nd reminder dates when a charge
 *              is demanded (BRD §13.1), and raises / syncs the charge's Demands__c record
 *              once the demand email has stamped its Demand Date (AdditionalChargeDemandService).
 * @author System
 */
trigger AdditionalChargeTrigger on Additional_Charge__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        AdditionalChargeReminderService.populateReminderDates(Trigger.new, Trigger.oldMap);
        AdditionalChargeDemandService.markDemanded(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        AdditionalChargeDemandService.handleAfterSave(Trigger.new, Trigger.oldMap);
    }
}