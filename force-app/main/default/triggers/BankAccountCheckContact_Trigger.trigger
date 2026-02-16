////////////////////////////////////////////////////////////
//
/////////////////////////////////////////////////////////////
trigger BankAccountCheckContact_Trigger on Contact (before insert, before update) {
    for (Contact curr : Trigger.New) {
        try 
        {
            // Trigger Insert
            if (Trigger.isInsert) 
            {
                if (!curr.Bank_Details_Flag__c == true)
                {
                    // Check if Bank data is not empty
                    if (!String.isEmpty(curr.Bank_Account_Number__c) && !String.isEmpty(curr.Bank_Branch_Number__c) && !String.isEmpty(curr.Bank_Name__c)) 
                    {    
                        String bankNumber = curr.Bank_Name__c.left(2).trim().leftPad(2, '0');
                        Integer bankBrachNumber = Integer.valueOf(curr.Bank_Branch_Number__c);
                        String bankAccountNumber = curr.Bank_Account_Number__c;
                        // perform bank detail checking
                        Boolean success = BankAccountDetailHandler.verification (bankNumber, bankBrachNumber , bankAccountNumber);
                        if (!success) {
                            curr.addError('פרטי חשבון בנק לא תקינים');
                        }
                    }
                }
            }
            // Trigger Update
            if (Trigger.isUpdate)
            {
                Contact old = Trigger.oldMap.get(curr.Id);
                System.debug(curr.Bank_Details_Flag__c);
                if (curr.Bank_Details_Flag__c == false) //  && (old.Bank_Details_Flag__c == false || old.Bank_Details_Flag__c == null)
                {
                    system.debug('Actual_Bank_Account_Number__c');
                    system.debug(curr.Actual_Bank_Account_Number__c);
                    // Check if Bank data is not empty
                    
                    
                    
                    System.debug(!String.isEmpty(curr.Bank_Account_Number__c) && !String.isEmpty(curr.Bank_Branch_Number__c) && !String.isEmpty(curr.Bank_Name__c));
                    System.debug((curr.Bank_Account_Number__c != old.Bank_Account_Number__c  || curr.Bank_Branch_Number__c != old.Bank_Branch_Number__c || curr.Bank_Name__c != old.Bank_Name__c));
                    System.debug((!String.isEmpty(curr.Bank_Account_Number__c) && !String.isEmpty(curr.Bank_Branch_Number__c) && !String.isEmpty(curr.Bank_Name__c) &&
                        (curr.Bank_Account_Number__c != old.Bank_Account_Number__c  || curr.Bank_Branch_Number__c != old.Bank_Branch_Number__c || curr.Bank_Name__c != old.Bank_Name__c)));
                    System.debug(curr.ForceBankDetailsCheck__c == true && (old.ForceBankDetailsCheck__c == false || old.ForceBankDetailsCheck__c == null));
                    
                    if (
                        (!String.isEmpty(curr.Bank_Account_Number__c) && !String.isEmpty(curr.Bank_Branch_Number__c) && !String.isEmpty(curr.Bank_Name__c) &&
                        (curr.Bank_Account_Number__c != old.Bank_Account_Number__c  || curr.Bank_Branch_Number__c != old.Bank_Branch_Number__c || curr.Bank_Name__c != old.Bank_Name__c))
                        || (curr.ForceBankDetailsCheck__c == true && (old.ForceBankDetailsCheck__c == false || old.ForceBankDetailsCheck__c == null))
                       ) 
                    {
                        String bankNumber = curr.Bank_Name__c.left(2).trim().leftPad(2, '0');
                        Integer bankBrachNumber = Integer.valueOf(curr.Bank_Branch_Number__c);
                        String bankAccountNumber = curr.Bank_Account_Number__c;
                        
                        System.debug(bankNumber);
                        System.debug(bankBrachNumber);
                        System.debug(bankAccountNumber);
                        
                        // perform bank detail checking
                        Boolean success = BankAccountDetailHandler.verification (bankNumber, bankBrachNumber , bankAccountNumber);
                        if (!success) {
                            curr.addError('פרטי חשבון בנק לא תקינים');
                        }
                    }
                }
                
                if (curr.Actual_Bank_Account_Number__c != old.Actual_Bank_Account_Number__c)
                {
                    system.debug('NEWWWWWWWWWWWWWWWWWWWWWWWWW BANK FIELD');
                    if (
                        (!String.isEmpty(curr.Actual_Bank_Account_Number__c ) && !String.isEmpty(curr.Bank_Branch_Number__c) && !String.isEmpty(curr.Bank_Name__c) &&
                        (curr.Actual_Bank_Account_Number__c != old.Bank_Account_Number__c  || curr.Bank_Branch_Number__c != old.Bank_Branch_Number__c || curr.Bank_Name__c != old.Bank_Name__c))
                        || (curr.ForceBankDetailsCheck__c == true && (old.ForceBankDetailsCheck__c == false || old.ForceBankDetailsCheck__c == null))
                       ) 
                    {
                        String bankNumber = curr.Bank_Name__c.left(2).trim().leftPad(2, '0');
                        Integer bankBrachNumber = Integer.valueOf(curr.Bank_Branch_Number__c);
                        String bankAccountNumber = curr.Actual_Bank_Account_Number__c ;
                        
                        System.debug(bankNumber);
                        System.debug(bankBrachNumber);
                        System.debug(bankAccountNumber);
                        
                        // perform bank detail checking
                        Boolean success = BankAccountDetailHandler.verification (bankNumber, bankBrachNumber , bankAccountNumber);
                        if (!success) {
                            curr.Bank_Details_Flag__c = true;
                        }
                    }
                }
                
                
             }
         }
         catch (Exception ex)
         {
             curr.addError('פרטי חשבון בנק לא תקינים');
         }
    }
}