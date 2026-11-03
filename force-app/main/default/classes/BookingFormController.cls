public with sharing class BookingFormController {

    public String bookingDate { get; private set; }
    public String towerName { get; private set; }
    public String flatNo { get; private set; }
    public String flatArea { get; private set; }
    public String facing { get; private set; }
    public String flatConfiguration { get; private set; }

    public String applicantName { get; private set; }
    public String applicantFatherName { get; private set; }
    public String applicantPhone { get; private set; }
    public String applicantEmail { get; private set; }
    public String applicantDOB { get; private set; }
    public String applicantOccupation { get; private set; }
    public String applicantAadhar { get; private set; }
    public String applicantPAN { get; private set; }
    public String applicantAddress { get; private set; }

    public String coName { get; private set; }
    public String coFatherName { get; private set; }
    public String coPhone { get; private set; }
    public String coEmail { get; private set; }
    public String coDOB { get; private set; }
    public String coOccupation { get; private set; }
    public String coAadhar { get; private set; }
    public String coPAN { get; private set; }
    public String coAddress { get; private set; }

    public String bookingNumber { get; private set; }
    public String errorMessage { get; private set; }

    public BookingFormController() {
        initializeValues();

        String idParam = ApexPages.currentPage()
            .getParameters().get('id');

        if (String.isBlank(idParam)) {
            errorMessage = 'Booking record ID is missing.';
            return;
        }

        try {
            Id bookingId = Id.valueOf(idParam);
            loadBooking(bookingId);
        } catch (Exception ex) {
            errorMessage = 'Unable to load booking: '
                + ex.getMessage();
            System.debug(
                LoggingLevel.ERROR,
                'Booking Form Error: ' + ex.getStackTraceString()
            );
        }
    }

    private void initializeValues() {
        bookingDate = '';
        towerName = '';
        flatNo = '';
        flatArea = '';
        facing = '';
        flatConfiguration = '';

        applicantName = '';
        applicantFatherName = '';
        applicantPhone = '';
        applicantEmail = '';
        applicantDOB = '';
        applicantOccupation = '';
        applicantAadhar = '';
        applicantPAN = '';
        applicantAddress = '';

        coName = '';
        coFatherName = '';
        coPhone = '';
        coEmail = '';
        coDOB = '';
        coOccupation = '';
        coAadhar = '';
        coPAN = '';
        coAddress = '';

        bookingNumber = '';
        errorMessage = '';
    }

    /*
     * Checks actual object fields before querying.
     * This avoids compile errors caused by uncertain
     * API names from screenshots.
     */
    private static SObject queryOne(
        String objectApi,
        Set<String> requestedFields,
        String filterField,
        Id filterId
    ) {
        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (!globalMap.containsKey(objectApi)) {
            return null;
        }

        Schema.DescribeSObjectResult objectDescribe =
            globalMap.get(objectApi).getDescribe();

        Map<String, Schema.SObjectField> fieldMap =
            objectDescribe.fields.getMap();

        if (!fieldMap.containsKey(filterField)) {
            return null;
        }

        Set<String> selected = new Set<String>();
        selected.add('Id');

        for (String fieldName : requestedFields) {
            if (fieldMap.containsKey(fieldName)) {
                selected.add(fieldName);
            }
        }

        List<String> fieldList = new List<String>();
        fieldList.addAll(selected);
        fieldList.sort();

        String soql =
            'SELECT ' + String.join(fieldList, ',') +
            ' FROM ' + objectApi +
            ' WHERE ' + filterField + ' = :filterId' +
            ' LIMIT 1';

        List<SObject> records = Database.query(soql);

        return records.isEmpty() ? null : records[0];
    }

    private static String valueOfField(
        SObject recordValue,
        List<String> candidates
    ) {
        if (recordValue == null) {
            return '';
        }

        Map<String, Schema.SObjectField> fields =
            recordValue.getSObjectType()
            .getDescribe().fields.getMap();

        for (String candidate : candidates) {
            if (!fields.containsKey(candidate)) {
                continue;
            }

            Object rawValue;

            try {
                rawValue = recordValue.get(candidate);
            } catch (Exception ex) {
                continue;
            }

            if (rawValue == null) {
                continue;
            }

            String outputValue = String.valueOf(rawValue);

            if (String.isBlank(outputValue)) {
                continue;
            }

            Schema.DisplayType fieldType =
                fields.get(candidate).getDescribe().getType();

            if (fieldType == Schema.DisplayType.Date) {
                Date d = (Date)rawValue;
                return String.valueOf(d.day()).leftPad(2, '0')
                    + '/' +
                    String.valueOf(d.month()).leftPad(2, '0')
                    + '/' +
                    String.valueOf(d.year());
            }

            if (fieldType == Schema.DisplayType.DateTime) {
                Datetime dt = (Datetime)rawValue;
                return dt.format('dd/MM/yyyy');
            }

            return outputValue;
        }

        return '';
    }

    private static String firstValue(
        SObject recordValue,
        String firstField,
        String secondField
    ) {
        return valueOfField(
            recordValue,
            new List<String>{firstField, secondField}
        );
    }

    private void loadBooking(Id bookingId) {

        Set<String> bookingFields = new Set<String>{
            'Name',
            'Date_of_Booking__c',
            'Booking_Date__c',
            'Plot__c',

            'First_Applicant_Name__c',
            'Salutation__c',
            'Son_Daughter_Wife_of__c',
            'Mobile__c',
            'Email__c',
            'Date_of_Birth__c',
            'Occupation__c',
            'Applicant_Occupation__c',
            'Aadhar__c',
            'Aadhaar__c',
            'PAN_Number__c',
            'Permanent_Address__c',
            'Correspondence_Address__c'
        };

        SObject booking = queryOne(
            'Booking__c',
            bookingFields,
            'Id',
            bookingId
        );

        if (booking == null) {
            errorMessage = 'Booking record was not found or is inaccessible.';
            return;
        }

        bookingNumber = valueOfField(
            booking,
            new List<String>{'Name'}
        );

        bookingDate = firstValue(
            booking,
            'Date_of_Booking__c',
            'Booking_Date__c'
        );

        applicantName = valueOfField(
            booking,
            new List<String>{'First_Applicant_Name__c'}
        );

        applicantFatherName = valueOfField(
            booking,
            new List<String>{
                'Son_Daughter_Wife_of__c',
                'Father_Husband_Name__c'
            }
        );

        applicantPhone = valueOfField(
            booking,
            new List<String>{'Mobile__c'}
        );

        applicantEmail = valueOfField(
            booking,
            new List<String>{'Email__c'}
        );

        applicantDOB = valueOfField(
            booking,
            new List<String>{'Date_of_Birth__c'}
        );

        applicantOccupation = valueOfField(
            booking,
            new List<String>{
                'Occupation__c',
                'Applicant_Occupation__c'
            }
        );

        applicantAadhar = valueOfField(
            booking,
            new List<String>{
                'Aadhar__c',
                'Aadhaar__c'
            }
        );

        applicantPAN = valueOfField(
            booking,
            new List<String>{'PAN_Number__c'}
        );

        applicantAddress = valueOfField(
            booking,
            new List<String>{
                'Permanent_Address__c',
                'Correspondence_Address__c'
            }
        );

        /*
         * Resolve the Unit lookup from Booking.
         * Query the referenced object's real API name.
         */
        Map<String, Schema.SObjectField> bookingFieldMap =
            booking.getSObjectType()
            .getDescribe().fields.getMap();

        if (bookingFieldMap.containsKey('Plot__c')) {

            Object plotValue = booking.get('Plot__c');

            if (plotValue != null) {
                Id plotId = (Id)plotValue;

                List<Schema.SObjectType> plotTypes =
                    bookingFieldMap.get('Plot__c')
                    .getDescribe().getReferenceTo();

                if (!plotTypes.isEmpty()) {
                    loadPlot(
                        plotTypes[0].getDescribe().getName(),
                        plotId
                    );
                }
            }
        }

        loadCoApplicant(bookingId);
    }

    private void loadPlot(String plotObjectApi, Id plotId) {

        Set<String> plotFields = new Set<String>{
            'Name',
            'Tower__c',
            'Saleable_Area_Sft__c',
            'Facing__c',
            'Unit_Configuration_Name__c'
        };

        SObject plotRecord = queryOne(
            plotObjectApi,
            plotFields,
            'Id',
            plotId
        );

        if (plotRecord == null) {
            return;
        }

        flatNo = valueOfField(
            plotRecord,
            new List<String>{'Name'}
        );

        flatArea = valueOfField(
            plotRecord,
            new List<String>{'Saleable_Area_Sft__c'}
        );

        facing = valueOfField(
            plotRecord,
            new List<String>{'Facing__c'}
        );

        flatConfiguration = valueOfField(
            plotRecord,
            new List<String>{'Unit_Configuration_Name__c'}
        );

        Map<String, Schema.SObjectField> plotFieldMap =
            plotRecord.getSObjectType()
            .getDescribe().fields.getMap();

        if (!plotFieldMap.containsKey('Tower__c')) {
            return;
        }

        Object towerValue = plotRecord.get('Tower__c');

        if (towerValue == null) {
            return;
        }

        List<Schema.SObjectType> towerTypes =
            plotFieldMap.get('Tower__c')
            .getDescribe().getReferenceTo();

        if (towerTypes.isEmpty()) {
            return;
        }

        SObject towerRecord = queryOne(
            towerTypes[0].getDescribe().getName(),
            new Set<String>{'Name'},
            'Id',
            (Id)towerValue
        );

        towerName = valueOfField(
            towerRecord,
            new List<String>{'Name'}
        );
    }

    private void loadCoApplicant(Id bookingId) {

        Set<String> coFields = new Set<String>{
            'Name',
            'Booking__c',
            'Salutation__c',
            'Full_Name__c',
            'First_Name__c',

            'W_o_S_o_C_o_c__c',
            'S_o_D_o_W_o__c',
            'Father_Husband_Name__c',

            'Contact_Number__c',
            'Mobile__c',
            'Email__c',
            'Date_of_Birth__c',
            'Occupation__c',

            'Aadhar_Number__c',
            'Aadhaar_Number__c',
            'Passport_Aadhar_number__c',
            'PAN_Number__c',

            'Permanent_Address__c',
            'Correspondence_Address__c',
            'Address__c'
        };

        Map<String, Schema.SObjectType> globalMap =
            Schema.getGlobalDescribe();

        if (!globalMap.containsKey('Co_Applicant__c')) {
            return;
        }

        Map<String, Schema.SObjectField> coFieldMap =
            globalMap.get('Co_Applicant__c')
            .getDescribe().fields.getMap();

        if (!coFieldMap.containsKey('Booking__c')) {
            return;
        }

        Set<String> selectedFields = new Set<String>{
            'Id', 'CreatedDate'
        };

        for (String fieldName : coFields) {
            if (coFieldMap.containsKey(fieldName)) {
                selectedFields.add(fieldName);
            }
        }

        List<String> fieldList = new List<String>();
        fieldList.addAll(selectedFields);
        fieldList.sort();

        String soql =
            'SELECT ' + String.join(fieldList, ',') +
            ' FROM Co_Applicant__c' +
            ' WHERE Booking__c = :bookingId' +
            ' ORDER BY CreatedDate ASC' +
            ' LIMIT 1';

        List<SObject> coRecords = Database.query(soql);

        if (coRecords.isEmpty()) {
            return;
        }

        SObject co = coRecords[0];

        coName = valueOfField(
            co,
            new List<String>{
                'Full_Name__c',
                'First_Name__c'
            }
        );

        coFatherName = valueOfField(
            co,
            new List<String>{
                'W_o_S_o_C_o_c__c',
                'Father_Husband_Name__c',
                'S_o_D_o_W_o__c'
            }
        );

        coPhone = valueOfField(
            co,
            new List<String>{
                'Contact_Number__c',
                'Mobile__c'
            }
        );

        coEmail = valueOfField(
            co,
            new List<String>{'Email__c'}
        );

        coDOB = valueOfField(
            co,
            new List<String>{'Date_of_Birth__c'}
        );

        coOccupation = valueOfField(
            co,
            new List<String>{'Occupation__c'}
        );

        coAadhar = valueOfField(
            co,
            new List<String>{
                'Aadhar_Number__c',
                'Aadhaar_Number__c'
            }
        );

        coPAN = valueOfField(
            co,
            new List<String>{'PAN_Number__c'}
        );

        coAddress = valueOfField(
            co,
            new List<String>{
                'Permanent_Address__c',
                'Correspondence_Address__c',
                'Address__c'
            }
        );
    }
}