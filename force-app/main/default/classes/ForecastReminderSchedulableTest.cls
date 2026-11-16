@isTest
private class ForecastReminderSchedulableTest {
    @isTest
    static void scheduleAndRun() {
        Test.startTest();
        String jobId = System.schedule('Forecast Reminder Test', '0 0 9 * * ?', new ForecastReminderSchedulable());
        new ForecastReminderSchedulable().execute(null);
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}