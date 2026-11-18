@isTest
private class AdditionalChargeDemandLetterCtrlTest {

    @isTest
    static void rendersChargeAmountsAndFlatAccount() {
        AdditionalChargeDemandService.bypass = true;
        Project__c project = new Project__c(Name = 'P', Project_Type__c = 'Residential', Interest_Rate__c = 18);
        insert project;
        insert new Account_Name__c(
            Name = 'COLLECTION A/C', Project__c = project.Id, Account_Type__c = 'Flat',
            Account_No__c = '000111', Bank_Name__c = 'TEST BANK', IFSC_Code__c = 'TEST0000001', Branch__c = 'Main'
        );
        Booking__c b = new Booking__c(
            Project__c = project.Id, Booking_Date__c = Date.today(), Status__c = 'New',
            Email__c = 'cust@example.com', Salutation__c = 'Mr.', First_Applicant_Name__c = 'Jane'
        );
        insert b;
        Additional_Charge__c c = new Additional_Charge__c(
            Booking__c = b.Id, Charge_Name__c = 'Extra Parking', Charge_Type__c = 'Additional Car Parking',
            Amount__c = 10000, GST_Amount__c = 1800, Amount_Paid__c = 800, Demand_Date__c = Date.newInstance(2026, 11, 17)
        );
        insert c;

        Test.setCurrentPage(Page.AdditionalChargeDemandLetter);
        AdditionalChargeDemandLetterController ctrl =
            new AdditionalChargeDemandLetterController(new ApexPages.StandardController(c));

        System.assertEquals(null, ctrl.errorMessage);
        System.assertEquals(10000, ctrl.baseAmount);
        System.assertEquals(1800, ctrl.gstAmount);
        System.assertEquals(11800, ctrl.totalAmount);
        System.assertEquals(800, ctrl.receivedAmount);
        System.assertEquals(11000, ctrl.balanceAmount);
        System.assertEquals(Date.newInstance(2026, 11, 17), ctrl.letterDate);
        System.assertEquals('Extra Parking', ctrl.chargeLabel);
        System.assert(ctrl.applicantName.contains('Jane'), ctrl.applicantName);
        System.assertEquals('000111', ctrl.accountNumber);
        System.assert(ctrl.hasAccount);
    }

    @isTest
    static void missingCharge_showsError() {
        AdditionalChargeDemandService.bypass = true;
        Additional_Charge__c ghost = new Additional_Charge__c();
        AdditionalChargeDemandLetterController ctrl =
            new AdditionalChargeDemandLetterController(new ApexPages.StandardController(ghost));
        System.assertEquals('Additional charge not found.', ctrl.errorMessage);
        System.assertEquals('', ctrl.applicantName);
        System.assertEquals('', ctrl.chargeLabel);
        System.assert(!ctrl.hasAccount);
    }
}