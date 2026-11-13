public with sharing class DemandLetterPDFController {
    public String errorMessage { get; private set; }
    public String accountHolder { get; private set; }
    public String accountNumber { get; private set; }
    public String bankName { get; private set; }
    public String bankAccountType { get; private set; }
    public String ifscCode { get; private set; }
    public String accountBranch { get; private set; }
    public String branchCity { get; private set; }
    public String accountType { get; private set; }

    public DemandLetterPDFController(ApexPages.StandardController standardController) {
        accountType = resolveAccountType(ApexPages.currentPage().getUrl());
        if (String.isBlank(accountType)) {
            errorMessage = 'Use the Flat, GST, or Full demand-letter page.';
            return;
        }

        try {
            Demands__c pageDemand = (Demands__c) standardController.getRecord();
            if (pageDemand.Id == null) {
                errorMessage = 'A saved demand record is required to generate this letter.';
                return;
            }
            Demands__c demand = [
                SELECT Project__c
                FROM Demands__c
                WHERE Id = :pageDemand.Id
                LIMIT 1
            ];
            if (demand.Project__c == null) {
                errorMessage = 'The demand must be saved and linked to a project.';
                return;
            }
            loadAccount(demand.Project__c);
        } catch (QueryException e) {
            errorMessage = e.getMessage();
        } catch (Exception e) {
            errorMessage = 'Unable to load project account details: ' + e.getMessage();
        }
    }

    private void loadAccount(Id projectId) {
        Map<String, Schema.SObjectField> accountFields =
            Schema.SObjectType.Account_Name__c.fields.getMap();
        List<String> selectedFields = new List<String>{
            'Name', 'Account_No__c', 'Bank_Name__c', 'IFSC_Code__c', 'Branch__c'
        };
        if (accountFields.containsKey('Bank_Account_Type__c')) {
            selectedFields.add('Bank_Account_Type__c');
        }
        if (accountFields.containsKey('Branch_City__c')) {
            selectedFields.add('Branch_City__c');
        }

        String accountQuery = 'SELECT ' + String.join(selectedFields, ', ') +
            ' FROM Account_Name__c WHERE Project__c = :projectId' +
            ' AND Account_Type__c = :accountType ORDER BY LastModifiedDate DESC LIMIT 2';
        Boolean optionalFieldsQueried = selectedFields.size() > 5;
        List<Account_Name__c> matchingAccounts;
        try {
            matchingAccounts = Database.query(accountQuery);
        } catch (QueryException e) {
            if (!optionalFieldsQueried
                || (!e.getMessage().contains('Bank_Account_Type__c')
                    && !e.getMessage().contains('Branch_City__c'))) {
                throw e;
            }
            accountQuery = 'SELECT Name, Account_No__c, Bank_Name__c, IFSC_Code__c, Branch__c' +
                ' FROM Account_Name__c WHERE Project__c = :projectId' +
                ' AND Account_Type__c = :accountType ORDER BY LastModifiedDate DESC LIMIT 2';
            matchingAccounts = Database.query(accountQuery);
            optionalFieldsQueried = false;
        }

        if (matchingAccounts.isEmpty()) {
            errorMessage = 'No ' + accountType + ' Account Name is configured for this project.';
            return;
        }
        if (matchingAccounts.size() > 1) {
            errorMessage = 'More than one ' + accountType +
                ' Account Name is configured for this project.';
            return;
        }

        Account_Name__c selectedAccount = matchingAccounts[0];
        accountHolder = selectedAccount.Name;
        accountNumber = selectedAccount.Account_No__c;
        bankName = selectedAccount.Bank_Name__c;
        bankAccountType = optionalFieldsQueried
            && accountFields.containsKey('Bank_Account_Type__c')
            ? displayValue(selectedAccount.get('Bank_Account_Type__c'))
            : '';
        ifscCode = selectedAccount.IFSC_Code__c;
        accountBranch = selectedAccount.Branch__c;
        branchCity = optionalFieldsQueried
            && accountFields.containsKey('Branch_City__c')
            ? displayValue(selectedAccount.get('Branch_City__c'))
            : '';
    }

    @TestVisible
    private static String resolveAccountType(String pageUrl) {
        if (String.isBlank(pageUrl)) return null;
        if (pageUrl.contains('/DemandLetterFlat')) return 'Flat';
        if (pageUrl.contains('/DemandLetterGST')) return 'GST';
        if (pageUrl.contains('/DemandLetterFull')) return 'Full';
        return null;
    }

    private static String displayValue(Object value) {
        return value == null ? '' : String.valueOf(value);
    }
}