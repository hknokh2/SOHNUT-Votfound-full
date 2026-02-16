public class IsraelTimeFromUTC {
    @InvocableMethod
    public static List<String> israelTimeFromRecordCreatedDate(List<Datetime> inputDates) {
        List<String> results = new List<String>();
        for (Datetime recordDate : inputDates) {
            // Automatically applies DST based on actual timezone rules
            String formattedTime = recordDate.format('yyyy-MM-dd HH:mm:ss', 'Asia/Jerusalem');
            results.add(formattedTime);
        }
        return results;
    }
}