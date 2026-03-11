System.debug('BANK_NAME_TYPE=' + Contact.Bank_Name__c.getDescribe().getType());
System.debug('BANK_NAME_PICKLIST=' + JSON.serialize(Contact.Bank_Name__c.getDescribe().getPicklistValues()));
System.debug('BANK_BRANCH_TYPE=' + Contact.Bank_Branch_Number__c.getDescribe().getType());
System.debug('BANK_ACCOUNT_TYPE=' + Contact.Bank_Account_Number__c.getDescribe().getType());
System.debug('ACTUAL_BANK_ACCOUNT_TYPE=' + Contact.Actual_Bank_Account_Number__c.getDescribe().getType());
System.debug('BANK_DETAILS_FLAG_TYPE=' + Contact.Bank_Details_Flag__c.getDescribe().getType());