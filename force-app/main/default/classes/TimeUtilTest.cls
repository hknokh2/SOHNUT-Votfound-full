@IsTest
public class TimeUtilTest {
    @IsTest
    public static void testGetIsraelTimeFromRecordDate() {
        // Create a list of input dates
        List<Datetime> inputDates = new List<Datetime>{
            Datetime.newInstance(2025, 3, 28, 12, 0, 0), // Before DST starts
            Datetime.newInstance(2025, 3, 29, 12, 0, 0), // DST start date
            Datetime.newInstance(2025, 4, 1, 12, 0, 0),  // During DST
            Datetime.newInstance(2025, 10, 25, 12, 0, 0), // Before DST ends
            Datetime.newInstance(2025, 10, 26, 12, 0, 0), // DST end date
            Datetime.newInstance(2025, 11, 1, 12, 0, 0)  // After DST ends
        };
        
        // Call the static method directly on the class
        List<String> results = TimeUtils.getIsraelTimeFromRecordDate(inputDates);
        
        // Verify the results
        System.assertEquals(6, results.size());
        System.assertEquals('2025-03-28 14:00:00', results[0]); // Standard time
        System.assertEquals('2025-03-29 15:00:00', results[1]); // DST start date
        System.assertEquals('2025-04-01 15:00:00', results[2]); // DST time
        System.assertEquals('2025-10-25 15:00:00', results[3]); // DST time
        System.assertEquals('2025-10-26 15:00:00', results[4]); // DST end date
        System.assertEquals('2025-11-01 14:00:00', results[5]); // Standard time
    }
    
    @IsTest
    public static void testGetLastFridayInMarch() {
        // Test for a specific year
        Date lastFriday = TimeUtils.getLastFridayInMarch(2025);
        System.assertEquals(Date.newInstance(2025, 3, 29), lastFriday);
    }
    
    @IsTest
    public static void testGetLastSundayInOctober() {
        // Test for a specific year
        Date lastSunday = TimeUtils.getLastSundayInOctober(2025);
        System.assertEquals(Date.newInstance(2025, 10, 27), lastSunday);
    }
    
    @IsTest
    public static void testGetDayOfWeek() {
        // Test for a specific date
        Integer dayOfWeek = TimeUtils.getDayOfWeek(Date.newInstance(2025, 2, 4));
        System.assertEquals(2, dayOfWeek); // Tuesday
    }
}