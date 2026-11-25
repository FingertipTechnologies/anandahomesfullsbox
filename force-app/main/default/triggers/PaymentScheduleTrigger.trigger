/**
 * @description Trigger on Payment_Schedule__c. Flows master defaults (Is_Agreement) onto new
 *              lines and enforces Prorata / Partial invariants only when split values or their
 *              base/GST capacity are inserted or changed (BRD §8.3.1).
 * @author System
 */
trigger PaymentScheduleTrigger on Payment_Schedule__c (before insert, before update) {
    if (Label.Enable_Payment_Schedule_Trigger == 'true') {
    if (Trigger.isBefore && Trigger.isInsert) {
        PaymentScheduleMasterDefaults.applyAgreementFlag(Trigger.new);
    }
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        ProrataInvariantService.validate(Trigger.new, Trigger.oldMap);
    }
    }
}