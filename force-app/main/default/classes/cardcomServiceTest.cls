@isTest
public class cardcomServiceTest 
{
        
    @isTest
    static void testDoPost() {
        Test.startTest();

        // Setup test data
        Contact c = new Contact(lastName='test');
        insert c;

        Program__c program = new Program__c();
        program.DetailEvent__c = '11111111111';
        program.ProgramPlace__c = 'North';
        insert program;       

        Fees__c f     = new Fees__c();   
        f.Payer__c    = c.Id;
        f.Program__c  = program.Id;
        insert f;

      
        
        // Simulate the callout request
        RestRequest req = new RestRequest();
        req.requestURI = '/cardcom';
        req.httpMethod = 'POST';
        req.params.put('Custom08', f.Id);
        req.params.put('responsecode', '0');
        RestContext.request = req;

        // Call the method to be tested
        cardcomService.doPost();
        
        Test.stopTest();
    }

}