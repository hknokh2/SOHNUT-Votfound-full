public class TimeUtils {
    @InvocableMethod
    public static List<String> getIsraelTimeFromRecordDate(List<Datetime> inputDates) {
        System.debug(inputDates);
        List<String> results = new List<String>();
        
        for (Datetime recordDate : inputDates) {
            // Define the timezone offset for Israel
            Integer standardOffset = 2 * 3600; // 2 hours in seconds
            Integer dstOffset = 3 * 3600; // 3 hours in seconds
            
            // Get the year from the record date
            Integer recordYear = recordDate.year();
            
            // Calculate the last Friday in March for the record year
            Date dstStart = getLastFridayInMarch(recordYear);
            
            // Calculate the last Sunday in October for the record year
            Date dstEnd = getLastSundayInOctober(recordYear);
            
            // Check if the record date is within the DST period
            boolean isDST = recordDate.date() >= dstStart && recordDate.date() <= dstEnd;
            
            // Calculate the time in Israel for the record date
            Integer offset = isDST ? dstOffset : standardOffset;
            Datetime israelTime = recordDate.addSeconds(offset);
            
            // Format the time in Israel timezone
            String formattedTime = israelTime.format('yyyy-MM-dd HH:mm:ss', 'Asia/Jerusalem');
            
            // Add the result to the list
            results.add(formattedTime);
        }
        
        System.debug(results);
        return results;
    }
    
    public static Date getLastFridayInMarch(Integer year) {
        Date march = Date.newInstance(year, 3, 31); // Last day of March
        Integer dayOfWeek = getDayOfWeek(march); // Get the day of the week for the last day of March
        Integer daysToSubtract = (dayOfWeek >= 6) ? dayOfWeek - 6 : dayOfWeek + 1;
        return march.addDays(-daysToSubtract); // Calculate the last Friday in March
    }
    
    public static Date getLastSundayInOctober(Integer year) {
        Date october = Date.newInstance(year, 10, 31); // Last day of October
        Integer dayOfWeek = getDayOfWeek(october); // Get the day of the week for the last day of October
        Integer daysToSubtract = (dayOfWeek >= 1) ? dayOfWeek - 1 : 6;
        return october.addDays(-daysToSubtract); // Calculate the last Sunday in October
    }
    
    public static Integer getDayOfWeek(Date inputDate) {
        Datetime dt = Datetime.newInstance(inputDate.year(), inputDate.month(), inputDate.day());
        String dayOfWeekStr = dt.format('E'); // Get the day of the week as a string
        Integer dayOfWeek;
        switch on dayOfWeekStr {
            when 'Sun' { dayOfWeek = 0; }
            when 'Mon' { dayOfWeek = 1; }
            when 'Tue' { dayOfWeek = 2; }
            when 'Wed' { dayOfWeek = 3; }
            when 'Thu' { dayOfWeek = 4; }
            when 'Fri' { dayOfWeek = 5; }
            when 'Sat' { dayOfWeek = 6; }
        }
        return dayOfWeek;
    }
}