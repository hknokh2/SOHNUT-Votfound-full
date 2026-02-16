public with sharing class Lwc_fullCalendar 
{
   @AuraEnabled(cacheable= true)
   public static List<Visit__c> getVisits()
   {
    List<Visit__c> lstVisit = [Select Name,End_Date__c,Start_Date__c,Contact__c,Mitkan__c From Visit__c];
    return lstVisit;
   }
}