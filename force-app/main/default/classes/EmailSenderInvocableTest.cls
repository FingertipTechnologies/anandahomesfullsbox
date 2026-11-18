/**
 * @description Test class for EmailSenderInvocable
 */
@isTest
private class EmailSenderInvocableTest {

    @testSetup
    static void setup() {
        Account a = new Account(Name = 'Email Test Acct');
        insert a;

        Email_Template_Config__c tmpl = new Email_Template_Config__c(
            Template_Name__c = 'TestTemplate',
            Object_API_Name__c = 'Account',
            Subject__c = 'Hello {!Name}',
            Email_Body__c = '<p>Body for {!Name}</p>',
            Recipients_Config__c = JSON.serialize(new Map<String, Object>{
                'to' => new List<Object>{
                    new Map<String, Object>{
                        'sourceType' => 'Static',
                        'staticEmail' => 'test@example.com'
                    }
                }
            }),
            Is_Active__c = true
        );
        insert tmpl;
    }

    // ============ CO-APPLICANT CC ============

    private static Booking__c bookingWithCoApplicants() {
        Project__c project = new Project__c(Name = 'Co-applicant Mail Project', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        Plot__c unit = new Plot__c(Project__c = project.Id, Unit_Type__c = 'Apartment', Status__c = 'Booked');
        insert unit;
        Booking__c b = new Booking__c(
            Project__c = project.Id, Plot__c = unit.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            Email__c = 'primary.applicant@example.com'
        );
        insert b;
        insert new List<Co_Applicant__c>{
            new Co_Applicant__c(Booking__c = b.Id, Email__c = 'co.one@example.com'),
            new Co_Applicant__c(Booking__c = b.Id, Email__c = 'PRIMARY.applicant@example.com'), // same as primary
            new Co_Applicant__c(Booking__c = b.Id),                                          // no email
            new Co_Applicant__c(Booking__c = b.Id, Email__c = 'co.two@example.com')
        };
        return b;
    }

    @isTest
    static void coApplicants_copiedOnlyOnMailsToTheApplicant() {
        Booking__c b = bookingWithCoApplicants();

        Messaging.SingleEmailMessage toApplicant = new Messaging.SingleEmailMessage();
        toApplicant.setToAddresses(new List<String>{ 'primary.applicant@example.com' });
        toApplicant.setCcAddresses(new List<String>{ 'owner@example.com', 'co.two@example.com' });

        Messaging.SingleEmailMessage internalMail = new Messaging.SingleEmailMessage();
        internalMail.setToAddresses(new List<String>{ 'finance@example.com' });

        Messaging.SingleEmailMessage otherBooking = new Messaging.SingleEmailMessage();
        otherBooking.setToAddresses(new List<String>{ 'primary.applicant@example.com' });

        Test.startTest();
        EmailSenderInvocable.addCoApplicantCc(
            new List<Messaging.SingleEmailMessage>{ toApplicant, internalMail, otherBooking },
            new List<Id>{ b.Id, b.Id, null }
        );
        Test.stopTest();

        System.assertEquals(
            new List<String>{ 'owner@example.com', 'co.two@example.com', 'co.one@example.com' },
            toApplicant.getCcAddresses(),
            'Co-applicants are added once, the primary/invalid/blank ones are skipped, existing CC kept'
        );
        System.assertEquals(null, internalMail.getCcAddresses(), 'Mails not to the applicant are untouched');
        System.assertEquals(null, otherBooking.getCcAddresses(), 'No booking, nothing added');

        // Nothing to do / bad input must not fail.
        EmailSenderInvocable.addCoApplicantCc(null, null);
        EmailSenderInvocable.addCoApplicantCc(new List<Messaging.SingleEmailMessage>{ internalMail }, new List<Id>{ null });
    }

    @isTest
    static void coApplicants_bookingResolvedFromRelatedRecords() {
        Booking__c b = bookingWithCoApplicants();
        Co_Applicant__c co = [SELECT Id FROM Co_Applicant__c WHERE Booking__c = :b.Id LIMIT 1];
        Account a = [SELECT Id FROM Account LIMIT 1];

        List<Id> bookings = EmailSenderInvocable.bookingIdsFor(new List<Id>{ b.Id, co.Id, a.Id, null });

        System.assertEquals(b.Id, bookings[0], 'A booking is its own booking');
        System.assertEquals(b.Id, bookings[1], 'A record with a Booking__c lookup resolves to it');
        System.assertEquals(null, bookings[2], 'Objects without a booking lookup are skipped');
        System.assertEquals(null, bookings[3]);
    }

    @isTest
    static void coApplicants_templateMailToApplicantSends() {
        Booking__c b = bookingWithCoApplicants();
        insert new Email_Template_Config__c(
            Template_Name__c = 'CoApplicantTemplate',
            Object_API_Name__c = 'Booking__c',
            Subject__c = 'Booking update',
            Email_Body__c = '<p>Hello</p>',
            Recipients_Config__c = JSON.serialize(new Map<String, Object>{
                'to' => new List<Object>{
                    new Map<String, Object>{ 'sourceType' => 'Field', 'fieldApiName' => 'Email__c' }
                }
            }),
            Is_Active__c = true
        );
        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(b.Id);
        req.templateName = 'CoApplicantTemplate';
        req.skipAttachments = true;

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results[0].sentCount, 'Mail to the applicant (with co-applicants copied) is sent: '
            + results[0].errorDetails);
    }

    @isTest
    static void sendEmails_validRequest_succeeds() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(a.Id);
        req.templateName = 'TestTemplate';
        req.skipAttachments = true;

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one response');
        System.assertNotEquals(null, results[0].message, 'Message should be populated');
    }

    @isTest
    static void sendEmails_blankRecordIds_fails() {
        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = '';
        req.templateName = 'TestTemplate';

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Blank record ids should fail');
    }

    @isTest
    static void sendEmails_blankTemplate_fails() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(a.Id);
        req.templateName = '';

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Blank template should fail');
    }

    @isTest
    static void sendEmails_unknownTemplate_fails() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(a.Id);
        req.templateName = 'NoSuchTemplate';

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Unknown template should fail');
    }

    @isTest
    static void sendEmails_withOverridesAndAdditional_handles() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(a.Id);
        req.templateName = 'TestTemplate';
        req.subjectOverride = 'Override Subject {!Name}';
        req.bodyOverride = '<p>Override body</p>';
        req.additionalToAddresses = 'extra@example.com';
        req.additionalCcAddresses = 'cc@example.com';
        req.skipAttachments = true;

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
    }

    @isTest
    static void sendEmails_multipleRecordIds_processesAll() {
        Account a1 = [SELECT Id FROM Account LIMIT 1];
        Account a2 = new Account(Name = 'A2');
        insert a2;

        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = a1.Id + ',' + a2.Id;
        req.templateName = 'TestTemplate';
        req.skipAttachments = true;

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size());
    }

    @isTest
    static void sendEmails_invalidRecordIds_returnsNoValidIds() {
        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = 'not-a-real-id,alsoNotValid';
        req.templateName = 'TestTemplate';

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();
        System.assertEquals(false, results[0].success, 'No valid ids should fail');
    }

    @isTest
    static void sendEmails_additionalEmailInvalidFormat_skipsInvalid() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(a.Id);
        req.templateName = 'TestTemplate';
        req.additionalToAddresses = 'valid@example.com,not-an-email,;another@x.com';
        req.additionalCcAddresses = 'cc@x.com;;';
        req.skipAttachments = true;

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size());
    }

    @isTest
    static void sendEmails_withAttachmentsConfig_skipsWhenNoneDefault() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Email_Template_Config__c attTmpl = new Email_Template_Config__c(
            Template_Name__c = 'AttachedTpl',
            Object_API_Name__c = 'Account',
            Subject__c = 'S',
            Email_Body__c = 'B',
            Recipients_Config__c = JSON.serialize(new Map<String, Object>{
                'to' => new List<Object>{
                    new Map<String, Object>{ 'sourceType' => 'Static', 'staticEmail' => 't@x.com' }
                }
            }),
            Attachments_Config__c = JSON.serialize(new Map<String, Object>{
                'attachments' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'VFPage',
                        'isDefaultChecked' => false,
                        'isRequired' => false,
                        'name' => 'Skip'
                    }
                }
            }),
            Is_Active__c = true
        );
        insert attTmpl;

        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(a.Id);
        req.templateName = 'AttachedTpl';
        req.skipAttachments = false;

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size());
    }

    @isTest
    static void sendEmails_recipientNoToResolved_fails() {
        // Recipients_Config with invalid static email
        Email_Template_Config__c noTo = new Email_Template_Config__c(
            Template_Name__c = 'NoToTpl',
            Object_API_Name__c = 'Account',
            Subject__c = 'S',
            Email_Body__c = 'B',
            Recipients_Config__c = JSON.serialize(new Map<String, Object>{
                'to' => new List<Object>{
                    new Map<String, Object>{ 'sourceType' => 'Static', 'staticEmail' => 'not-valid' }
                }
            }),
            Is_Active__c = true
        );
        insert noTo;

        Account a = [SELECT Id FROM Account LIMIT 1];

        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(a.Id);
        req.templateName = 'NoToTpl';
        req.skipAttachments = true;

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size());
    }

    @isTest
    static void sendEmails_multipleRequests_processesEach() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        EmailSenderInvocable.EmailRequest r1 = new EmailSenderInvocable.EmailRequest();
        r1.recordIds = String.valueOf(a.Id);
        r1.templateName = 'TestTemplate';
        r1.skipAttachments = true;

        EmailSenderInvocable.EmailRequest r2 = new EmailSenderInvocable.EmailRequest();
        r2.recordIds = '';
        r2.templateName = 'TestTemplate';

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ r1, r2 });
        Test.stopTest();
        System.assertEquals(2, results.size());
        System.assertEquals(false, results[1].success, 'Blank record ids second request fails');
    }

    @isTest
    static void sendEmails_templateWithoutObjectApi_derivesFromId() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Email_Template_Config__c derive = new Email_Template_Config__c(
            Template_Name__c = 'DeriveTpl',
            Object_API_Name__c = null,
            Subject__c = 'S',
            Email_Body__c = 'B',
            Recipients_Config__c = JSON.serialize(new Map<String, Object>{
                'to' => new List<Object>{
                    new Map<String, Object>{ 'sourceType' => 'Static', 'staticEmail' => 't@x.com' }
                }
            }),
            Is_Active__c = true
        );
        insert derive;

        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(a.Id);
        req.templateName = 'DeriveTpl';
        req.skipAttachments = true;

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size());
    }

    @isTest
    static void sendEmails_staticDocAttachment_tries() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        Email_Template_Config__c docTmpl = new Email_Template_Config__c(
            Template_Name__c = 'StaticDocTpl',
            Object_API_Name__c = 'Account',
            Subject__c = 'S',
            Email_Body__c = 'B',
            Recipients_Config__c = JSON.serialize(new Map<String, Object>{
                'to' => new List<Object>{
                    new Map<String, Object>{ 'sourceType' => 'Static', 'staticEmail' => 't@x.com' }
                }
            }),
            Attachments_Config__c = JSON.serialize(new Map<String, Object>{
                'attachments' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'StaticDocument',
                        'isDefaultChecked' => true,
                        'documentId' => '069000000000000'
                    }
                }
            }),
            Is_Active__c = true
        );
        insert docTmpl;

        EmailSenderInvocable.EmailRequest req = new EmailSenderInvocable.EmailRequest();
        req.recordIds = String.valueOf(a.Id);
        req.templateName = 'StaticDocTpl';
        req.skipAttachments = false;

        Test.startTest();
        List<EmailSenderInvocable.EmailResponse> results =
            EmailSenderInvocable.sendEmails(new List<EmailSenderInvocable.EmailRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size());
    }
}