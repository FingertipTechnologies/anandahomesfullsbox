/**
 * @description Tests for EmailSenderInvocable.applyFieldUpdatesOnSend — the "update fields on
 *              send" capability added to the email template config.
 */
@isTest
private class EmailFieldUpdatesTest {

    private static Booking__c makeBooking() {
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert b;
        return b;
    }

    @isTest
    static void appliesDateTimeCheckboxAndText() {
        Booking__c b = makeBooking();
        String json = '['
            + '{"field":"Welcome_Mail_Sent_DateTime__c","type":"DateTime","value":"NOW"},'
            + '{"field":"Disable_Demand_Reminders__c","type":"Checkbox","value":"true"},'
            + '{"field":"Stage_Remarks__c","type":"Text","value":"Welcome sent"}'
            + ']';

        Test.startTest();
        EmailSenderInvocable.applyFieldUpdatesOnSend(json, 'Booking__c', new Set<Id>{ b.Id });
        Test.stopTest();

        Booking__c updated = [
            SELECT Welcome_Mail_Sent_DateTime__c, Disable_Demand_Reminders__c, Stage_Remarks__c
            FROM Booking__c WHERE Id = :b.Id
        ];
        System.assertNotEquals(null, updated.Welcome_Mail_Sent_DateTime__c, 'DateTime NOW should be set');
        System.assertEquals(true, updated.Disable_Demand_Reminders__c, 'Checkbox should be true');
        System.assertEquals('Welcome sent', updated.Stage_Remarks__c, 'Text should be set');
    }

    @isTest
    static void stampsEvenWhenSenderCannotEditBooking() {
        Booking__c b = makeBooking();
        // A CRM User can read bookings and units but cannot edit a booking owned by someone else.
        Profile p = [SELECT Id FROM Profile WHERE Name = 'CRM User' LIMIT 1];
        User sender = new User(
            Alias = 'sndx', Email = 'sender.noedit@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Sender No Edit', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_IN',
            ProfileId = p.Id, TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'sender.noedit.' + System.currentTimeMillis() + '@example.com'
        );
        insert sender;

        Test.startTest();
        System.runAs(sender) {
            EmailSenderInvocable.applyFieldUpdatesOnSend(
                '[{"field":"Welcome_Mail_Sent_DateTime__c","type":"DateTime","value":"NOW"}]',
                'Booking__c', new Set<Id>{ b.Id }
            );
        }
        Test.stopTest();

        System.assertNotEquals(null,
            [SELECT Welcome_Mail_Sent_DateTime__c FROM Booking__c WHERE Id = :b.Id].Welcome_Mail_Sent_DateTime__c,
            'The welcome stamp must not depend on the sender\'s edit access to the booking: '
                + EmailSenderInvocable.lastFieldUpdateErrors);
    }

    @isTest
    static void convertsDateCheckboxAndNumberValues() {
        Booking__c b = makeBooking();
        Booking__c b2 = new Booking__c(
            Project__c = b.Project__c, Booking_Date__c = Date.today(), Status__c = 'Booked'
        );
        insert b2;

        Test.startTest();
        EmailSenderInvocable.applyFieldUpdatesOnSend('['
            + '{"field":"Welcome_Mail_Sent_Time__c","type":"DateTime","value":"2026-11-17T10:30:00Z"},'
            + '{"field":"Welcome_Email_Sent_Date__c","type":"Date","value":"2026-11-17"},'
            + '{"field":"Welcome_Email_Sent__c","type":"Checkbox","value":""},'
            + '{"field":"Booking_Amount__c","type":"Currency","value":"1500"}'
            + ']', 'Booking__c', new Set<Id>{ b.Id });
        EmailSenderInvocable.applyFieldUpdatesOnSend('['
            + '{"field":"Welcome_Mail_Sent_Time__c","type":"DateTime","value":"not-a-date"},'
            + '{"field":"Welcome_Email_Sent_Date__c","type":"Date","value":"TODAY"},'
            + '{"field":"Disable_Demand_Reminders__c","type":"Checkbox","value":"false"},'
            + '{"field":"Booking_Amount__c","type":"Number","value":"abc"}'
            + ']', 'Booking__c', new Set<Id>{ b2.Id });
        EmailSenderInvocable.applyFieldUpdatesOnSend(
            '[{"field":"Welcome_Email_Sent_Date__c","type":"Date","value":"31/31/2026"}]',
            null, new Set<Id>{ b2.Id });
        EmailSenderInvocable.applyFieldUpdatesOnSend('not json', 'Booking__c', new Set<Id>{ b2.Id });
        EmailSenderInvocable.applyFieldUpdatesOnSend(
            '[{"field":"Stage_Remarks__c","value":"x"}]', 'Not_An_Object__c', new Set<Id>{ b2.Id });
        Test.stopTest();

        Booking__c one = [SELECT Welcome_Mail_Sent_Time__c, Welcome_Email_Sent_Date__c, Welcome_Email_Sent__c, Booking_Amount__c FROM Booking__c WHERE Id = :b.Id];
        System.assertEquals(Date.newInstance(2026, 11, 17), one.Welcome_Email_Sent_Date__c);
        System.assertEquals(true, one.Welcome_Email_Sent__c, 'Blank checkbox value means true');
        System.assertEquals(1500, one.Booking_Amount__c);
        System.assertNotEquals(null, one.Welcome_Mail_Sent_Time__c);

        Booking__c two = [SELECT Welcome_Mail_Sent_Time__c, Welcome_Email_Sent_Date__c, Disable_Demand_Reminders__c FROM Booking__c WHERE Id = :b2.Id];
        System.assertNotEquals(null, two.Welcome_Mail_Sent_Time__c, 'An unreadable date-time falls back to now');
        System.assertEquals(Date.today(), two.Welcome_Email_Sent_Date__c);
        System.assertEquals(false, two.Disable_Demand_Reminders__c);
    }

    @isTest
    static void attachesUploadedFilesByDocumentType() {
        Booking__c b = makeBooking();
        ContentVersion cv = new ContentVersion(
            Title = 'Signed Form', PathOnClient = 'signed.pdf', VersionData = Blob.valueOf('pdf'),
            FirstPublishLocationId = b.Id
        );
        cv.put('Document_Type__c', 'Signed Booking Form');
        insert cv;

        Test.startTest();
        List<Messaging.EmailFileAttachment> byType =
            EmailSenderInvocable.getUploadedFileAttachments(b.Id, null, 'Signed_Booking_Form', null);
        List<Messaging.EmailFileAttachment> byName =
            EmailSenderInvocable.getUploadedFileAttachments(b.Id, 'Other Category', null, 'Signed Booking Form');
        List<Messaging.EmailFileAttachment> noMatch =
            EmailSenderInvocable.getUploadedFileAttachments(b.Id, null, 'Aadhaar', null);
        List<Messaging.EmailFileAttachment> none =
            EmailSenderInvocable.getUploadedFileAttachments(null, null, 'x', null);
        Test.stopTest();

        System.assertEquals(1, byType.size(), 'Document type match treats _ as a space');
        System.assertEquals('Signed Form.pdf', byType[0].getFileName());
        System.assertEquals(1, byName.size(), 'Falls back to the attachment name; blank file category is not filtered');
        System.assertEquals(0, noMatch.size());
        System.assertEquals(0, none.size());
    }

    @isTest
    static void ignoresUnknownFieldAndBlankConfig() {
        Booking__c b = makeBooking();

        Test.startTest();
        // Unknown field — must not throw.
        EmailSenderInvocable.applyFieldUpdatesOnSend(
            '[{"field":"Not_A_Real_Field__c","type":"Text","value":"x"}]', 'Booking__c', new Set<Id>{ b.Id }
        );
        // Blank / empty inputs — must not throw.
        EmailSenderInvocable.applyFieldUpdatesOnSend(null, 'Booking__c', new Set<Id>{ b.Id });
        EmailSenderInvocable.applyFieldUpdatesOnSend('[]', 'Booking__c', new Set<Id>{ b.Id });
        EmailSenderInvocable.applyFieldUpdatesOnSend('[{"field":"Stage_Remarks__c"}]', 'Booking__c', null);
        Test.stopTest();

        System.assert(true, 'No exception means the guards work');
    }
}