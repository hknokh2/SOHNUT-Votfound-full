@isTest
public class Lwc_fullCalendarTest {

    @isTest
    static void testGetVisits() {

        Contact c = new Contact(LastName ='aaa');
        insert c;

        // Create test data
        Visit__c visit = new Visit__c(
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addDays(1),
            Contact__c = c.Id 
        );
        insert visit;

        // Call the method being tested
        List<Visit__c> result = Lwc_fullCalendar.getVisits();
       
    }
}