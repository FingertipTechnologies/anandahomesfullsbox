/**
 * @description Trigger on Refund__c. A refund on a cancelled booking can only be created once the
 *              cancellation letter (a file of the "Cancellation" document category) is uploaded on
 *              the booking - covers the Financial Transactions screen, the New button and imports.
 */
trigger RefundTrigger on Refund__c (before insert) {
    RefundTriggerHandler.requireCancellationLetter(Trigger.new);
}
