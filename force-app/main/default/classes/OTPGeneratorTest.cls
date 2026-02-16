@isTest
private class OTPGeneratorTest {

    @isTest
    static void testGenerateOtp() {
        // Call the generateOtp method
        List<String> result = OTPGenerator.generateOtp();

        // Verify the result
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Result should contain only one OTP');

        String otp = result[0];
        System.assertNotEquals(null, otp, 'Generated OTP should not be null');
        System.assertEquals(6, otp.length(), 'Generated OTP should have a length of 6 characters');

        // You can add more assertions based on your specific requirements
        // For example, you might want to ensure that the OTP consists only of digits, etc.
    }
}