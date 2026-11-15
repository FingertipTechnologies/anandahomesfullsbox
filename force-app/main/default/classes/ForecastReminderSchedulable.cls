/**
 * @description Daily job that sends ONLY the forecasting milestone reminder
 *              (ProrataForecastReminderService). Use it instead of DemandReminderSchedulable when the
 *              other demand automation (demand reminders, additional-charge reminders, prorata customer
 *              demands) must stay off.
 *
 *              Schedule (Developer Console > Execute Anonymous), daily at 9 AM:
 *              System.schedule('Forecast Reminder Daily', '0 0 9 * * ?', new ForecastReminderSchedulable());
 */
public with sharing class ForecastReminderSchedulable implements Schedulable {
    public void execute(SchedulableContext sc) {
        try {
            Integer sent = ProrataForecastReminderService.processDueForecastReminders();
            System.debug('Forecast reminders sent: ' + sent);
        } catch (Exception e) {
            System.debug('ForecastReminderSchedulable error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }
}
