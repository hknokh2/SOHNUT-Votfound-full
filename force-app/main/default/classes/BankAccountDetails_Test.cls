@isTest
private class BankAccountDetails_Test {

    @testSetup static void setup() {
        // Create common test for BankAccountDetails / Payment
        Account acc = new Account();
        acc.Name = 'Test';
        insert acc;
        
        Contact con = new Contact();
        //try
        //{
            Id defaultContactRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Default').getRecordTypeId();
            
            con.recordTypeId = defaultContactRecordTypeId;
            con.FirstName = 'Test';
            con.LastName = 'Test';
            con.AccountId = acc.Id;
            
            con.Bank_Account_Number__c = '028828';
            con.Bank_Branch_Number__c = '401';
            con.Bank_Name__c = '4 - בנק יהב';
            
            insert con;
      //  }
       // catch (Exception ex)
       // {
        //    system.debug(ex);
        //}
       // finally 
       // {
            System.debug('Contact insert success, Id is : ' + con.Id);
       // }
        
       /* Id requestOpportunityRecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Request').getRecordTypeId();
        Opportunity opp = new Opportunity();
        opp.Name = 'Test';
        opp.RecordTypeId = requestOpportunityRecordTypeId;
        opp.AccountId = acc.Id;
        opp.StageName = 'New';
        opp.CloseDate = System.Today();
        insert opp;
        
        npe01__OppPayment__c payment = new npe01__OppPayment__c();
        try {
            payment.npe01__Opportunity__c = opp.Id;
            payment.Bank_Account_Number__c = '028828';
            payment.Bank_Branch_Number__c = '401';
            payment.Bank_Name__c = '04 - בנק יהב';
            insert payment;
        }
        catch (Exception ex)
        {
            System.debug('Failure 1');
        }*/
        
      
        
          
    }
    
    
    @isTest static void testUpdateContact() {
        
        contact  con  = [SELECT Id FROM Contact Limit 1];
        try
        {  
            con.Bank_Account_Number__c = '001638';
            con.Bank_Branch_Number__c = '139';
            con.Bank_Name__c = '12 - בנק הפועלים';
            update con;
        }
        catch (Exception ex) 
        {
            System.debug('Failure 4');        
        }
        
        try
        {  
            con.Bank_Account_Number__c = '001638';
            con.Bank_Branch_Number__c = '139';
            con.Bank_Name__c = '20 - בנק מזרחי';
            update con;
        }
        catch (Exception ex) 
        {
            System.debug('Failure 2');
        }
        
        try
        {  
            con.Bank_Account_Number__c = '001638';
            con.Bank_Branch_Number__c = '139';
            con.Bank_Name__c = '10 - בנק לאומי';
            update con;
        }
        catch (Exception ex) 
        {
            System.debug('Failure 3');        
        }
        
       
        
        try
        {  
            con.Bank_Account_Number__c = '000001638';
            con.Bank_Branch_Number__c = '139';
            con.Bank_Name__c = '17 - בנק מרכנתיל דיסקונט';
            update con;
        }
        catch (Exception ex) 
        {
            System.debug('Failure 5');        
        }
        
        try
        {  
            con.Bank_Account_Number__c = '000001638';
            con.Bank_Branch_Number__c = '139';
            con.Bank_Name__c = '31 - בנק הבינלאומי';
            update con;
        }
        catch (Exception ex) 
        {
            System.debug('Failure 6');        
        }
        
        try
        {  
            con.Bank_Account_Number__c = '000001638';
            con.Bank_Branch_Number__c = '139';
            con.Bank_Name__c = '9 - בנק הדואר';
            update con;
        }
        catch (Exception ex) 
        {
            System.debug('Failure 7');        
        }
        
        try
        {  
            con.Bank_Account_Number__c = '000001638';
            con.Bank_Branch_Number__c = '139';
            con.Bank_Name__c = '22 - סיטי בנק (Citibank)';
            update con;
        }
        catch (Exception ex) 
        {
            System.debug('Failure 8');        
        }
        
        try
        {  
            con.Bank_Account_Number__c = '000001638';
            con.Bank_Branch_Number__c = '139';
            con.Bank_Name__c = '46 - בנק מסד';
            update con;
        }
        catch (Exception ex) 
        {
            System.debug('Failure 9');        
        }
        
        try
        {  
            con.Bank_Account_Number__c = '000001638';
            con.Bank_Branch_Number__c = '139';
            con.Bank_Name__c = '14 - בנק הבינלאומי';
            update con;
        }
        catch (Exception ex) 
        {
            System.debug('Failure 10');        
        }
        
        try
        {  
            con.Bank_Account_Number__c = '000001638';
            con.Bank_Branch_Number__c = '139';
            con.Bank_Name__c = '18 - הבנק הדיגיטלי הראשון';
            update con;
        }
        catch (Exception ex) 
        {
            System.debug('Failure 11');        
        }
        
        
    }

}