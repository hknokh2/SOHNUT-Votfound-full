public class BankAccountDetailHandler {

    public class AccountDetailsException extends Exception {}
    public static boolean verification (string bankNumber, integer bankBranch, string account)
    {
        boolean validateBankAccount;        
        integer lngRequiredAccountLength ;
        integer bankNumberInteger;
        List<string> accountArray;
        List<string> bankbranchArray;
        string num;
        integer num1; 
        integer num2;
        
        try 
        {
            ///////////////////////////////////////////////////////////////////////////
            // Check first if all arguments are digits
            ///////////////////////////////////////////////////////////////////////////
            System.debug(bankNumber);
            System.debug(bankBranch);
            System.debug(account);                        
            System.debug(bankNumber.isNumeric());
            System.debug((String.valueOf(bankBranch)).isNumeric());
            System.debug(account.isNumeric());                        
            
            boolean b = (bankNumber.isNumeric() && String.valueOf(bankBranch).isNumeric() && account.isNumeric());


            if (!b)
            {
               throw new AccountDetailsException('At least (Bank Number, Bank Branch, Bank Account) is not numeric' );
            }
            
            switch on bankNumber
            {     
                when '10', '13','34'{
                    lngRequiredAccountLength = 8;
                    //if (account.)
                }
                when '12', '04', '20'  {
                    lngRequiredAccountLength = 6;
                }                    
                when '11','17','52','09','22','46','14','18', '31', '26' {
                    lngRequiredAccountLength = 9;
                    if (bankNumber == '26') bankNumber = '31';
                }                
                when else{
                    lngRequiredAccountLength = 9;
                } 
            }
    
            account = pad(account, lngRequiredAccountLength);
            if (account.length() > lngRequiredAccountLength )
                throw new AccountDetailsException('Bank account number can not be more than ' + lngRequiredAccountLength + '  digits' );
                //account.substring(account.length() - 9);  
    
            accountArray= account.split('');
            system.debug(lngRequiredAccountLength) ;
            system.debug(account);
            if(integer.valueOf(bankNumber) == 20 &&  bankbranch > 400)
            {
                bankbranch= bankbranch-400;
            }
            string bankbranchString = pad(string.ValueOf(bankbranch),3);
            bankbranchArray=bankbranchString.split('');
            

            system.debug(bankbranchString);
            switch on bankNumber
            {     
                when '54'{
                    validateBankAccount=true;
                }
                when '18'
                {
                    String bankBranchTemp = String.valueOf(Integer.valueOf(bankbranchString));
                    string bankBranchPlusAccount = bankBranchTemp  + account.left(7);
                    Long result = math.mod(Long.valueOf(bankBranchPlusAccount), 97);
                    validateBankAccount = (98 - result) == Integer.valueOf(account.right(2));
                    
                }
                when '10','13','34'{
                
                    system.debug('-------------------------------------');
                    system.debug('bankNumber: ' + bankNumber);
                    system.debug('bankbranchArray: ' + bankbranchArray);
                    system.debug('accountArray: ' + accountArray);
                    system.debug('-------------------------------------');
                    num = String.valueOf(
                    (
                        Integer.valueOf(bankbranchArray[0]) * 10 +
                        Integer.valueOf(bankbranchArray[1]) * 9 +
                        Integer.valueOf(bankbranchArray[2]) * 8 +
                        Integer.valueOf(accountArray[0]) * 7 +
                        Integer.valueOf(accountArray[1]) * 6 +
                        Integer.valueOf(accountArray[2]) * 5 +
                        Integer.valueOf(accountArray[3]) * 4 +
                        Integer.valueOf(accountArray[4]) * 3 +
                        Integer.valueOf(accountArray[5]) * 2
                    ) + Integer.valueOf(account.substring(account.length() - 2))
                );                
                    
                    
                    num= num.substring(num.length() - 2);
                    system.debug(num);
                    system.debug(num.length());
                    if(num=='90' || num=='72' || num=='70' || num=='60' || num=='20')
                    {
                        validateBankAccount=true;
                    }
                    else
                    {
                        validateBankAccount=false;
                    }
                }
                   
    
                when '12'{
                    integer num3 = integer.ValueOf(bankbranchArray[0]) * 9 +
                        integer.ValueOf(bankbranchArray[1]) * 8 +
                        integer.ValueOf(bankbranchArray[2]) * 7 +
                        integer.ValueOf(accountArray[0]) * 6 +
                        integer.ValueOf(accountArray[1]) * 5 +
                        integer.ValueOf(accountArray[2]) * 4 +
                        integer.ValueOf(accountArray[3]) * 3 +
                        integer.ValueOf(accountArray[4]) * 2 +
                        integer.ValueOf(accountArray[5] ) * 1;
                    
                    num3 = math.mod(num3, 11);
                    if(num3==0 || num3==2 || num3==4 || num3==6 )
                        validateBankAccount=true;
                    else
                        validateBankAccount=false; 
                }
                    
                when '04'{
                
                    integer num3 = integer.ValueOf(bankbranchArray[0]) * 9 +
                        integer.ValueOf(bankbranchArray[1]) * 8 +
                        integer.ValueOf(bankbranchArray[2]) * 7 +
                        integer.ValueOf(accountArray[0]) * 6 +
                        integer.ValueOf(accountArray[1]) * 5 +
                        integer.ValueOf(accountArray[2]) * 4 +
                        integer.ValueOf(accountArray[3]) * 3 +
                        integer.ValueOf(accountArray[4]) * 2 +
                        integer.ValueOf(accountArray[5]) * 1;  
                        system.debug(num3); 
                        system.debug(math.mod(num3, 11));              
                    num3=math.mod(num3, 11);
                    if(num3==0 || num3==2 )
                        validateBankAccount=true;
                    else
                        validateBankAccount=false; 
                }
                when '11', '17' {
                   integer num3 = 
                        integer.valueOf(accountArray[0]) * 9 +
                        integer.valueOf(accountArray[1]) * 8 +
                        integer.valueOf(accountArray[2]) * 7 +
                        integer.valueOf(accountArray[3]) * 6 +
                        integer.valueOf(accountArray[4]) * 5 +
                        integer.valueOf(accountArray[5]) * 4 +
                        integer.valueOf(accountArray[6]) * 3 +
                        integer.valueOf(accountArray[7]) * 2 +
                        integer.valueOf(accountArray[8]) * 1;                
                    num3 = math.mod(num3, 11);
                    if(num3==0 || num3==2  || num3==4)
                        validateBankAccount=true;
                    else
                        validateBankAccount=false; 
                }
                
                    
                when '20' {
                integer num3 = integer.valueOf(bankbranchArray[0])*9+
                    integer.valueOf(bankbranchArray[1]) * 8 +
                    integer.valueOf(bankbranchArray[2]) * 7 +
                    integer.valueOf(accountArray[0]) * 6 +
                    integer.valueOf(accountArray[1]) * 5 +
                    integer.valueOf(accountArray[2]) * 4 +
                    integer.valueOf(accountArray[3]) * 3 +
                    integer.valueOf(accountArray[4]) * 2 +
                    integer.valueOf(accountArray[5]) * 1;
                    num3=math.mod(num3, 11);
                    if(num3==0 || num3==2 || num3==4)
                        validateBankAccount=true;
                    else
                        validateBankAccount=false; 
                }
                when '31', '52' {
                integer num3 = integer.valueOf(accountArray[0]) * 9 +
                    integer.valueOf(accountArray[1]) * 8 +
                    integer.valueOf(accountArray[2]) * 7 +
                    integer.valueOf(accountArray[3]) * 6 +
                    integer.valueOf(accountArray[4]) * 5 +
                    integer.valueOf(accountArray[5]) * 4 +
                    integer.valueOf(accountArray[6]) * 3 +
                    integer.valueOf(accountArray[7]) * 2 +
                    integer.valueOf(accountArray[8]) * 1;                
                    num3= math.mod(num3, 11);         
                    num1=   integer.valueOf(accountArray[3]) * 6 +
                            integer.valueOf(accountArray[4]) * 5 +
                            integer.valueOf(accountArray[5]) * 4 +
                            integer.valueOf(accountArray[6]) * 3 +
                            integer.valueOf(accountArray[7]) * 2 +
                            integer.valueOf(accountArray[8]) * 1;
                    num1= math.mod(num1, 11);
                    if(num3==0 || num1==0 || num3==6 || num1==6  )
                        validateBankAccount=true;
                    else
                        validateBankAccount=false;                 
                }
                    
                when '09'{
                integer num3 = integer.valueOf(accountArray[0]) * 9 +
                    integer.valueOf(accountArray[1]) * 8 +
                    integer.valueOf(accountArray[2]) * 7 +
                    integer.valueOf(accountArray[3]) * 6 +
                    integer.valueOf(accountArray[4]) * 5 +
                    integer.valueOf(accountArray[5]) * 4 +
                    integer.valueOf(accountArray[6]) * 3 +
                    integer.valueOf(accountArray[7]) * 2 +
                    integer.valueOf(accountArray[8]) * 1;                
                    num3 = math.mod(num3, 10);           
                    if(num3==0)
                        validateBankAccount=true;
                    else
                        validateBankAccount=false; 
                    
                }
                    
                when '22'{
                    integer num3 =         integer.valueOf(accountArray[0])*3+
                            integer.valueOf(accountArray[1]) * 2 +
                            integer.valueOf(accountArray[2]) * 7 +
                            integer.valueOf(accountArray[3]) * 6 +
                            integer.valueOf(accountArray[4]) * 5 +
                            integer.valueOf(accountArray[5]) * 4 +
                            integer.valueOf(accountArray[6]) * 3 +
                            integer.valueOf(accountArray[7]) * 2;
    
                    num3= math.mod(num3, 11);         
             
                    if( 11-num3 == integer.valueOf(accountArray[8]))           
                        validateBankAccount=true;
                    else
                        validateBankAccount=false; 
                }
                when '46'{
                        integer num3 = integer.valueOf(bankbranchArray[0])*9+
                        integer.valueOf(bankbranchArray[1]) * 8 +
                        integer.valueOf(bankbranchArray[2]) * 7 +
                        integer.valueOf(accountArray[3]) * 6 +
                        integer.valueOf(accountArray[4]) * 5 +
                        integer.valueOf(accountArray[5]) * 4 +
                        integer.valueOf(accountArray[6]) * 3 +
                        integer.valueOf(accountArray[7]) * 2 +
                        integer.valueOf(accountArray[8]) * 1;
                        num3= math.mod(num3, 11);         
                        num1 = integer.valueOf(accountArray[0])*9+
                            integer.valueOf(accountArray[1]) * 8 +
                            integer.valueOf(accountArray[2]) * 7 +
                            integer.valueOf(accountArray[3]) * 6 +
                            integer.valueOf(accountArray[4]) * 5 +
                            integer.valueOf(accountArray[5]) * 4 +
                            integer.valueOf(accountArray[6]) * 3 +
                            integer.valueOf(accountArray[7]) * 2 +
                            integer.valueOf(accountArray[8]) * 1;
                        num1= math.mod(num1, 11);         
                    
                        num2 = integer.valueOf(accountArray[3]) * 6 +
                        integer.valueOf(accountArray[4]) * 5 +
                        integer.valueOf(accountArray[5]) * 4 +
                        integer.valueOf(accountArray[6]) * 3 +
                        integer.valueOf(accountArray[7]) * 2 +
                        integer.valueOf(accountArray[8]) * 1;
                    num2= math.mod(num2, 11);         
                    if(num3==0  )
                        validateBankAccount=true;
                    else if(num3==2 && (bankbranchString=='154'||bankbranchString=='166'||bankbranchString=='178'||bankbranchString=='181'||bankbranchString=='183'||bankbranchString=='191'||bankbranchString=='192'||bankbranchString=='503'||bankbranchString=='505'||bankbranchString=='507'||bankbranchString=='515'||bankbranchString=='516'||bankbranchString=='527'||bankbranchString=='539'))
                        validateBankAccount=true;
                    else if(num1==0 || num2==0)
                        validateBankAccount=true;
                    else
                        validateBankAccount=false; 
                }
                when '14'{
            integer num3 = 
                integer.valueOf(bankbranchArray[0]) * 9 +
                integer.valueOf(bankbranchArray[1]) * 8 +
                integer.valueOf(bankbranchArray[2]) * 7 +
                integer.valueOf(accountArray[3]) * 6 +
                integer.valueOf(accountArray[4]) * 5 +
                integer.valueOf(accountArray[5]) * 4 +
                integer.valueOf(accountArray[6]) * 3 +
                integer.valueOf(accountArray[7]) * 2 +
                integer.valueOf(accountArray[8]) * 1;               
                        num3= math.mod(num3, 11);         
                num1 = integer.valueOf(accountArray[0]) * 9 +
                integer.valueOf(accountArray[1]) * 8 +
                integer.valueOf(accountArray[2]) * 7 +
                integer.valueOf(accountArray[3]) * 6 +
                integer.valueOf(accountArray[4]) * 5 +
                integer.valueOf(accountArray[5]) * 4 +
                integer.valueOf(accountArray[6]) * 3 +
                integer.valueOf(accountArray[7]) * 2 +
                integer.valueOf(accountArray[8]) * 1;
                num1= math.mod(num1, 11);
                    
                num2 = integer.valueOf(accountArray[3]) * 6 +
                integer.valueOf(accountArray[4]) * 5 +
                integer.valueOf(accountArray[5]) * 4 +
                integer.valueOf(accountArray[6]) * 3 +
                integer.valueOf(accountArray[7]) * 2 +
                integer.valueOf(accountArray[8]) * 1;
                num2= math.mod(num2, 11);
                    if(num3==0 )
                        validateBankAccount=true;
                    else if(num3==2 && (bankbranchString=='347'||bankbranchString=='361'||bankbranchString=='362'||bankbranchString=='363'||bankbranchString=='365' ||bankbranchString=='385') )
                        validateBankAccount=true;
                    else if( num3==4 && (bankbranchString=='361'||bankbranchString=='362'||bankbranchString=='363') )  
                        validateBankAccount=true;
                    else if(num1==0 || num2==0)
                        validateBankAccount=true;
                    else
                        validateBankAccount=false; 
                }
                when else{ 
                        validateBankAccount=false;
                }
            }
    
            system.debug(validateBankAccount);
            system.debug(banknumber);
        }
        catch (exception ex) {
            system.debug(ex);
            validateBankAccount = false;
        }
        return validateBankAccount;
    }
    
    public static string pad (string inputString, integer max) 
    {
        string outputString;
        if (inputString.length() < max)
        {
            outputString = inputString.leftPad(max, '0');
            return outputString;
        }
        else {
            return inputString;
        }
        
    }
        
}