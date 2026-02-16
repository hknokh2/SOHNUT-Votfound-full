@restresource(urlMapping='/cardcom/*')
global class cardcomService 
{
   @httpPost
   global static void doPost()
   {
     
    //Recieve a callout request   
     RestRequest restReq = RestContext.request; 
    //  restReq.addHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
     system.debug('Request:'+restReq);
     string paymentInfo;
     
     try
     {
        //Contains the request body- the payment information
        Map<String, String> requestParams = restReq.params;  
        system.debug('Payment information from cardcom:');
        system.debug(requestParams);
        
        //get the fee Id which the payment submmited to
        string feeId = requestParams.get('Custom08');
        system.debug('fee Id : '+ feeId);       

        if(feeId != null)
        {
            //get the response code when 0= payment succeded
            string responsecode =  requestParams.get('responsecode');
            system.debug('Response Code:'+responsecode);            
        
            //get the Last payment record for this particpation
            List<Fees__c> fees = new List<Fees__c>();
            fees = [Select Id, Payment_Status__c  FROM Fees__c WHERE Id =:feeId ORDER BY LastModifiedDate DESC] ;
            if(fees.size() > 0)
            {    
                Fees__c feeToUpdate = fees[0];                                         
                //Update payment record     
                feeToUpdate.Payment_Status__c                 = responsecode =='0'?'Paid':'Error';
                if(responsecode != '0')
                    feeToUpdate.Error_Description__c          = EncodingUtil.urlDecode(EncodingUtil.urlEncode(requestParams.get('responsdescription'), 'ISO_8859_1'), 'UTF8');    
                if(requestParams.get('suminfull')!=null)
                    feeToUpdate.Amount_Paid__c                = Decimal.valueOf(requestParams.get('suminfull'));

                update feeToUpdate;

                // if(requestParams.get('suminfull')!=null)
                //     paymentToUpdate.Actual_Amount__c        = Decimal.valueOf(requestParams.get('suminfull'));
                // paymentToUpdate.Actual_Date__c          = System.today();    
                //paymentToUpdate.Response_Description__c = requestParams.get('responsdescription');             
                //paymentToUpdate.Response_Description__c = EncodingUtil.urlDecode(EncodingUtil.urlEncode(requestParams.get('responsdescription'), 'ISO_8859_1'), 'UTF8');                // paymentToUpdate.Response_Description__c = '';
                // for (String key: requestParams.keyset()){        
                //     paymentToUpdate.Response_Description__c += key+':'+requestParams.get(key);                
                //     }
                // paymentToUpdate.Card_Owner_Name__c      = requestParams.get('CardOwnerName');
                // paymentToUpdate.Card_Owner_ID__c        = requestParams.get('CardOwnerID');
                // String curr = '';
                // if (requestParams.get('cointype') == '1' || requestParams.get('cointype') == '8')
                //     curr = 'ILS';
                // if (requestParams.get('cointype') == '2' || requestParams.get('cointype') == '4')
                //     curr = 'USD';
                // paymentToUpdate.Currency__c             = curr;
                // paymentToUpdate.Deal_Number__c          = requestParams.get('internaldealnumber');
                // paymentToUpdate.Approvel_Number__c      = requestParams.get('ApprovelNumber');
                // if(requestParams.get('NumberOfPaymentsToPrint')!=null)
                //     paymentToUpdate.Number_Of_Payments__c   = Decimal.valueOf(requestParams.get('NumberOfPaymentsToPrint'));               
    
            }
            else 
            {
                system.debug('cardcom service error:'+ 'No Payments found for fee ' + feeId);
            }                       
        }
        else 
        {
            system.debug('cardcom service error:'+ 'No fee ID');
        }  
        Cardcom_Logger__c ccl = new Cardcom_Logger__c();
        //ccl.Response_Description__c = requestParams.get('responsdescription');  
        ccl.Response_Description__c = EncodingUtil.urlDecode(EncodingUtil.urlEncode(requestParams.get('responsdescription'), 'ISO_8859_1'), 'UTF8');               
        ccl.Fee_Id__c               = feeId;
        ccl.Card_owner_name__c      = EncodingUtil.urlDecode(EncodingUtil.urlEncode(requestParams.get('CardOwnerName'), 'ISO_8859_1'), 'UTF8');
        ccl.Card__c                 = requestParams.get('CardOwnerID');
        if(requestParams.get('suminfull')!=null)
            ccl.Amount_Paid__c          = Decimal.valueOf(requestParams.get('suminfull'));
        ccl.Internal_Deal_number__c     = requestParams.get('internaldealnumber');
        insert ccl;     
     }
     catch (Exception ex) 
     {
        system.debug('cardcom service error:'+ex.getMessage());
     }

   }
}