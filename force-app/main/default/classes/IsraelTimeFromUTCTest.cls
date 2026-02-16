@IsTest
private class IsraelTimeFromUTCTest {

    @IsTest
    static void israelTimeFromRecordCreatedDate() {
        Datetime summerDate = Datetime.newInstanceGMT(2025, 8, 31, 8, 55, 4); // GMT
        Datetime winterDate = Datetime.newInstanceGMT(2025, 12, 15, 8, 55, 4); // GMT

        List<Datetime> inputDates = new List<Datetime>{ summerDate, winterDate };

        Test.startTest();
        List<String> results = IsraelTimeFromUTC.israelTimeFromRecordCreatedDate(inputDates);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should return two results');

        // Israel is UTC+3 in summer
        System.assertEquals('2025-08-31 11:55:04', results[0], 'Summer date should apply UTC+3');

        // Israel is UTC+2 in winter
        System.assertEquals('2025-12-15 10:55:04', results[1], 'Winter date should apply UTC+2');
    }
}