public with sharing class BookingAgreementController {
    public Booking__c booking { get; private set; }
    public List<Receipt__c> receipts { get; private set; }
    public List<Payment_Schedule__c> paymentSchedules { get; private set; }
    public String flatNumber { get; private set; }

    public BookingAgreementController(ApexPages.StandardController standardController) {
        Id bookingId = standardController.getId();
        if (bookingId == null) {
            throw new IllegalArgumentException('A Booking record is required to generate this agreement.');
        }

        booking = [
            SELECT Id, Agreement_Date__c, First_Applicant_Name__c,
                Second_Applicant_Name__c, Applicant_Name__c, Address__c,
                Permanent_Address__c, Email__c, Email1__c, Customer_Email__c,
                Project__r.Name, Project__r.Project_Address__c,
                Plot__r.Name, Plot__r.Tower_Block__c,
                Plot__r.Saleable_Area_Sft__c, Plot__r.BHK_Type__c,
                Plot__r.Facing__c, Plot__r.Carpet_Area__c,
                Plot__r.Balcony_Area__c,
                Plot__r.Common_Area_Allotted_to_Association__c,
                Plot__r.UDS__c, Car_Parking_Selected__c,
                Plot__r.Floor__c, Plot__r.North_By__c, Plot__r.South_By__c,
                Plot__r.East_By__c, Plot__r.West_By__c, Flat_Number__c,
                Tower__c, FloorNo__c, BHK_Type__c,
                Total_Flat_Cost__c, Total_Payable_Amount__c, Grand_Total__c,
                Base_Price__c,
                Booking_Amount__c, Total_Receipt_Amount__c, Pending_Amount__c,
                Loan_Bank_Name__c, Quote__r.Basic_Sale_Price_Rs__c,
                Quote__r.Amenities_Car_Parking__c,
                Quote__r.Total_Other_Charges__c
            FROM Booking__c
            WHERE Id = :bookingId
            LIMIT 1
        ];

        String flatNumberValue = booking.Flat_Number__c == null
            ? null
            : String.valueOf(booking.Flat_Number__c);
        if (flatNumberValue != null && flatNumberValue.endsWith('.0')) {
            flatNumberValue = flatNumberValue.substring(0, flatNumberValue.length() - 2);
        }
        flatNumber = String.isBlank(flatNumberValue) && booking.Plot__r != null
            ? booking.Plot__r.Name
            : flatNumberValue;

        receipts = [
            SELECT Id, Name, Receipt_Name__c, Receipt_Date__c,
                Amount_received__c, Payment_Method__c
            FROM Receipt__c
            WHERE Booking__c = :booking.Id
            ORDER BY Receipt_Date__c DESC, CreatedDate DESC
        ];

        paymentSchedules = [
            SELECT Id, Name, Payment_Schedule_Name__c, Percentage__c,
                Payment_Schedule_Amount__c, Payment_Schedule_Amount_Paid__c,
                Payment_Schedule_Amount_Pending__c, Demand_Date__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id
            ORDER BY CreatedDate ASC
        ];
    }
}