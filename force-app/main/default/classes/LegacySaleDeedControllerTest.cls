@IsTest
private class LegacySaleDeedControllerTest {
    @IsTest
    static void loadsApprovedReceivedPaymentLinesAndTotals() {
        Project__c project = new Project__c(
            Name = 'Legacy Deed Test Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;

        Plot__c plot = new Plot__c(
            Project__c = project.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked'
        );
        insert plot;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Plot__c = plot.Id,
            Booking_Date__c = Date.today(),
            Status__c = 'Booked',
            First_Applicant_Name__c = 'Legacy Deed Customer',
            Salutation__c = 'Mrs.',
            S_o_D_o_W_o__c = 'W/o',
            Son_Daughter_Wife_of__c = 'Deed Spouse',
            Total_Flat_Cost__c = 1000000,
            Total_Payable_Amount__c = 1050000
        );
        insert booking;

        Receipt__c approvedReceipt = new Receipt__c(
            Booking__c = booking.Id,
            Amount_received__c = 50000,
            Receipt_Date__c = Date.newInstance(2026, 10, 10),
            Receipt_Type__c = 'Installment Payment',
            Payment_Method__c = 'Cheque',
            Cheque_Number__c = 'CHQ-100',
            Cheque_Date__c = Date.newInstance(2026, 10, 9),
            TDS_Deducted__c = 500,
            Approval_Status__c = 'Approved',
            Receipt_Status__c = 'Received'
        );
        Receipt__c pendingReceipt = new Receipt__c(
            Booking__c = booking.Id,
            Amount_received__c = 20000,
            Receipt_Date__c = Date.newInstance(2026, 10, 11),
            Receipt_Type__c = 'Installment Payment',
            Payment_Method__c = 'Cheque',
            Approval_Status__c = 'Pending',
            Receipt_Status__c = 'Received'
        );
        insert new List<Receipt__c>{ approvedReceipt, pendingReceipt };

        Receipt_Line_Item__c approvedLine = new Receipt_Line_Item__c(
            Receipt__c = approvedReceipt.Id,
            Booking__c = booking.Id,
            Received_Amount__c = 50000,
            TDS_Amount__c = 500,
            Mode_of_Payment__c = 'Cheque',
            Cheque_no_Transaction_Number__c = 'CHQ-100',
            Cheque_Date__c = Date.newInstance(2026, 10, 9)
        );
        Receipt_Line_Item__c pendingLine = new Receipt_Line_Item__c(
            Receipt__c = pendingReceipt.Id,
            Booking__c = booking.Id,
            Received_Amount__c = 20000
        );
        insert new List<Receipt_Line_Item__c>{ approvedLine, pendingLine };

        LegacySaleDeedController controller = new LegacySaleDeedController(
            new ApexPages.StandardController(booking)
        );

        System.assertEquals(1, controller.paymentEntries.size());
        System.assertEquals('a', controller.paymentEntries[0].sequenceLabel);
        System.assertEquals(approvedReceipt.Id, controller.paymentEntries[0].receipt.Id);
        System.assertEquals('50,000', controller.paymentEntries[0].amountDisplay);
        System.assertEquals('Cheque', controller.paymentEntries[0].mode);
        System.assertEquals('CHQ-100', controller.paymentEntries[0].reference);
        System.assertEquals('94,55,900', LegacySaleDeedController.indianNumber(9455900));
        System.assertEquals(
            Date.newInstance(2026, 10, 9),
            controller.paymentEntries[0].paymentDate,
            'The cheque date should be preferred for cheque payments.'
        );
        System.assertEquals(500, controller.totalTdsAmount);
        System.assert(controller.getHasPaymentEntries());
        // consideration from Total Payable Amount, first applicant's relation from S/o,D/o,W/o
        System.assertEquals('10,50,000', controller.considerationAmount);
        System.assert(controller.considerationWords.startsWith('Rupees '), controller.considerationWords);
        System.assert(controller.purchasers[0].nameLine.contains('SMT. LEGACY DEED CUSTOMER, W/O. SRI. DEED SPOUSE'),
            controller.purchasers[0].nameLine);
        // SRI./SMT. wording of the Legacey sale agreements
        System.assertEquals('Sri.', LegacySaleDeedController.formalSalutation('Mr'));
        System.assertEquals('Kum.', LegacySaleDeedController.formalSalutation('Ms.'));
        System.assertEquals('Dr.', LegacySaleDeedController.formalSalutation('Dr'));
        System.assertEquals('S/O. SRI. B', LegacySaleDeedController.buildRelation('S/o', 'B'));
        System.assertEquals('D/O. LATE B', LegacySaleDeedController.buildRelation('D/o', 'Late B'));
        System.assertEquals('', LegacySaleDeedController.buildRelation('S/o', ''));
        System.assertEquals('SRI. A, S/O. SRI. B', LegacySaleDeedController.deedNameLine('Mr.', 'a', 'S/O. SRI. B'));
        System.assertEquals('A', LegacySaleDeedController.deedNameLine('', 'a', ''));
    }
}