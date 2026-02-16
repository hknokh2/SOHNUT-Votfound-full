public class OTPGenerator {
    
    @InvocableMethod(description='This method will be generating the OTP for users to Login' 
                     label='Generate OTP' 
                     category='OTP')
    public static List<String> generateOtp(){   
       	List<String> responseList = new List<String>();
        String randomIntegerString = string.valueof(Math.abs(Crypto.getRandomInteger()));
        String otp = randomIntegerString.substring(0,6);
        responseList.add(otp);
        return responseList;
    }
}