/**
 * @description A booking at the Cancellation stage is read-only for users: no field (stage included)
 *              can be changed. The refund process keeps working - creating / approving a Refund only
 *              touches the booking through the financial recalculation (totals below), and roll-up
 *              summaries and formulas are not editable fields, so they never trip the lock.
 *              System Administrators, scheduled / batch / queueable / future jobs and code that sets
 *              {@code bypass} are let through.
 */
public with sharing class BookingCancellationLockService {

    public static final String CANCELLATION_STAGE = 'Cancellation';
    public static final String LOCK_MESSAGE =
        'This booking is cancelled and cannot be edited. Refunds can still be created from Financial Transactions.';

    /** Set by trusted system code that must change a cancelled booking. */
    public static Boolean bypass = false;

    /** Totals kept up to date by BookingFinancialRecalcService (receipts / refunds). */
    @TestVisible
    private static final Set<String> SYSTEM_EDITABLE_FIELDS = new Set<String>{
        'pending_amount__c',
        'total_receipt_amount__c',
        'total_base_amount__c',
        'total_base_paid__c',
        'total_gst_paid__c',
        'total_base_pending__c',
        'total_gst_pending__c',
        'total_refunded_amount__c',
        'lastmodifieddate', 'lastmodifiedbyid', 'systemmodstamp'
    };

    public static void validateCancelledBookingEdits(List<Booking__c> newList, Map<Id, Booking__c> oldMap) {
        if (bypass || newList == null || oldMap == null) return;
        if (System.isBatch() || System.isFuture() || System.isQueueable() || System.isScheduled()) return;
        if (isSystemAdministrator()) return;

        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Booking__c.fields.getMap();
        List<Schema.DescribeFieldResult> editable;

        for (Booking__c booking : newList) {
            Booking__c oldBooking = oldMap.get(booking.Id);
            if (oldBooking == null || oldBooking.Status__c != CANCELLATION_STAGE) continue;

            if (editable == null) {
                editable = new List<Schema.DescribeFieldResult>();
                for (String fieldName : fieldMap.keySet()) {
                    if (SYSTEM_EDITABLE_FIELDS.contains(fieldName.toLowerCase())) continue;
                    Schema.DescribeFieldResult describe = fieldMap.get(fieldName).getDescribe();
                    if (describe.isUpdateable()) editable.add(describe);
                }
            }

            for (Schema.DescribeFieldResult describe : editable) {
                String name = describe.getName();
                if (valuesDiffer(oldBooking.get(name), booking.get(name))) {
                    booking.addError(LOCK_MESSAGE + ' (Changed field: ' + describe.getLabel() + ')');
                    break;
                }
            }
        }
    }

    public static final String ADMIN_PROFILE = 'System Administrator';

    /** Set in tests to act as (true) / not as (false) a System Administrator. */
    @TestVisible
    private static Boolean adminOverride;
    private static Boolean isAdminCache;

    /** System Administrators keep the option to correct a cancelled booking. */
    @TestVisible
    private static Boolean isSystemAdministrator() {
        if (adminOverride != null) return adminOverride;
        if (isAdminCache == null) {
            List<Profile> profiles = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId() WITH SYSTEM_MODE LIMIT 1];
            isAdminCache = !profiles.isEmpty() && profiles[0].Name == ADMIN_PROFILE;
        }
        return isAdminCache;
    }

    private static Boolean valuesDiffer(Object oldValue, Object newValue) {
        if (oldValue == null && newValue == null) return false;
        if (oldValue == null || newValue == null) return true;
        return JSON.serialize(oldValue) != JSON.serialize(newValue);
    }
}