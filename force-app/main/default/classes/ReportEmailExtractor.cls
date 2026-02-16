public class ReportEmailExtractor {
    
    /**
     * Invocable method that can be called from Flow
     * Runs a report and extracts email addresses from the results
     */
    @InvocableMethod(label='Extract Emails from Report' description='Runs a report and returns all email addresses found in Email type columns')
    public static List<List<String>> extractEmailsFromReport(List<ReportRequest> requests) {
        List<List<String>> results = new List<List<String>>();
        
        for (ReportRequest request : requests) {
            try {
                List<String> emails = runReportAndExtractEmails(request.reportId);
                results.add(emails);
            } catch (Exception e) {
                System.debug('Error processing report ' + request.reportId + ': ' + e.getMessage());
                // Return empty list in case of error
                results.add(new List<String>());
            }
        }
        
        return results;
    }
    
    /**
     * Helper method to run the report and extract email addresses
     */
    private static List<String> runReportAndExtractEmails(String reportId) {
        List<String> emailList = new List<String>();
        Set<String> uniqueEmails = new Set<String>();
        
        // Validate reportId
        if (String.isBlank(reportId)) {
            throw new IllegalArgumentException('Report ID cannot be blank');
        }
        
        try {
            // Run the report with predefined filters
            Reports.ReportResults results = Reports.ReportManager.runReport(reportId, true);
            
            // Get the report metadata to find email columns
            Reports.ReportMetadata metadata = results.getReportMetadata();
            List<String> detailColumns = metadata.getDetailColumns();
            
            // Add field metadata debugging
            debugFieldMetadata(metadata);
            
            // Find email column indices based on field type
            List<Integer> emailColumnIndices = findEmailColumnsByType(detailColumns, metadata);
            
            if (emailColumnIndices.isEmpty()) {
                System.debug('No Email type columns found in report: ' + reportId);
                System.debug('Available columns (' + detailColumns.size() + '): ' + detailColumns);
                return emailList;
            } else {
                System.debug('Found ' + emailColumnIndices.size() + ' Email type columns at indices: ' + emailColumnIndices);
            }
            
            // Extract data from report results - handle both grouped and ungrouped reports
            Map<String, Reports.ReportFact> factMap = results.getFactMap();
            System.debug('Report fact map keys: ' + factMap.keySet());
            
            // Check if report has groupings
            Reports.ReportMetadata reportMetadata = results.getReportMetadata();
            List<Reports.GroupingInfo> groupingsDown = reportMetadata.getGroupingsDown();
            List<Reports.GroupingInfo> groupingsAcross = reportMetadata.getGroupingsAcross();
            
            Boolean hasGroupings = (groupingsDown != null && !groupingsDown.isEmpty()) || 
                                 (groupingsAcross != null && !groupingsAcross.isEmpty());
            
            System.debug('Report has groupings: ' + hasGroupings);
            if (hasGroupings) {
                System.debug('Groupings Down count: ' + (groupingsDown != null ? groupingsDown.size() : 0));
                System.debug('Groupings Across count: ' + (groupingsAcross != null ? groupingsAcross.size() : 0));
            }
            
            Integer totalDetailRows = 0;
            
            if (hasGroupings) {
                // Handle grouped reports - iterate through all fact keys to find detail rows
                for (String factKey : factMap.keySet()) {
                    Reports.ReportFact fact = factMap.get(factKey);
                    
                    if (fact instanceof Reports.ReportFactWithDetails) {
                        Reports.ReportFactWithDetails factWithDetails = (Reports.ReportFactWithDetails) fact;
                        
                        if (factWithDetails.getRows() != null) {
                            List<Reports.ReportDetailRow> detailRows = factWithDetails.getRows();
                            totalDetailRows += detailRows.size();
                            System.debug('Found ' + detailRows.size() + ' detail rows in fact key: ' + factKey);
                            
                            // Process each detail row
                            for (Reports.ReportDetailRow row : detailRows) {
                                processDetailRow(row, emailColumnIndices, uniqueEmails);
                            }
                        } else {
                            System.debug('No detail rows found in fact key: ' + factKey);
                        }
                    }
                }
            } else {
                // Handle ungrouped reports - standard approach
                Reports.ReportFactWithDetails factWithDetails = (Reports.ReportFactWithDetails) factMap.get('T!T');
                
                if (factWithDetails != null && factWithDetails.getRows() != null) {
                    List<Reports.ReportDetailRow> detailRows = factWithDetails.getRows();
                    totalDetailRows = detailRows.size();
                    System.debug('Found ' + detailRows.size() + ' detail rows in ungrouped report');
                    
                    // Process each detail row
                    for (Reports.ReportDetailRow row : detailRows) {
                        processDetailRow(row, emailColumnIndices, uniqueEmails);
                    }
                } else {
                    System.debug('Ungrouped report returned no data rows or factWithDetails is null');
                }
            }
            
            System.debug('Total detail rows processed: ' + totalDetailRows);
            
            // Convert set to list
            emailList.addAll(uniqueEmails);
            System.debug('Extracted ' + emailList.size() + ' unique emails from ' + uniqueEmails.size() + ' total found');
            
        
        } catch (Exception ex) {
            throw new ReportProcessingException('Unexpected error while processing report: ' + ex.getMessage());
        }
        
        return emailList;
    }
    
    /**
     * Process a single detail row to extract emails
     */
    private static void processDetailRow(Reports.ReportDetailRow row, List<Integer> emailColumnIndices, Set<String> uniqueEmails) {
        List<Reports.ReportDataCell> dataCells = row.getDataCells();
        
        // Extract emails from each email column
        for (Integer emailIndex : emailColumnIndices) {
            if (emailIndex < dataCells.size()) {
                Reports.ReportDataCell emailCell = dataCells[emailIndex];
                String email = extractEmailFromCell(emailCell);
                
                if (String.isNotBlank(email) && isValidEmail(email)) {
                    uniqueEmails.add(email.toLowerCase());
                }
            }
        }
    }
    
    /**
     * Debug field metadata to show field sources and relationships
     */
    private static void debugFieldMetadata(Reports.ReportMetadata metadata) {
        System.debug('=== REPORT FIELD METADATA ===');
        
        List<String> detailColumns = metadata.getDetailColumns();
        String baseObjectName = getReportBaseObject(metadata);
        
        System.debug('Total fields in report: ' + detailColumns.size());
        System.debug('Report base object: ' + baseObjectName);
        
        for (Integer i = 0; i < detailColumns.size(); i++) {
            String fieldApiName = detailColumns[i];
            
            System.debug('Field [' + i + ']: ' + fieldApiName);
            
            // Check field type
            String fieldType = getFieldTypeFromSchema(fieldApiName, baseObjectName);
            System.debug('  - Field Type: ' + fieldType);
            
            // Check if this is a lookup field by analyzing the API name
            if (fieldApiName.contains('.')) {
                String[] parts = fieldApiName.split('\\.');
                if (parts.size() >= 2) {
                    String relationshipName = parts[0];
                    String relatedField = parts[1];
                    
                    System.debug('  - ** LOOKUP FIELD **');
                    System.debug('  - Relationship: ' + relationshipName);
                    System.debug('  - Related Field: ' + relatedField);
                    System.debug('  - Source Object: ' + getSourceObjectFromRelationship(relationshipName));
                } else {
                    System.debug('  - Complex lookup field');
                }
            } else {
                System.debug('  - ** DIRECT FIELD **');
                System.debug('  - Field Name: ' + fieldApiName);
                System.debug('  - Source Object: ' + baseObjectName);
            }
            
            System.debug('  ---');
        }
        
        System.debug('=== END FIELD METADATA ===');
    }
    
    /**
     * Find columns that are Email type fields
     */
    private static List<Integer> findEmailColumnsByType(List<String> columns, Reports.ReportMetadata metadata) {
        List<Integer> emailIndices = new List<Integer>();
        String baseObjectName = getReportBaseObjectName(metadata);
        
        System.debug('Checking field types for base object: ' + baseObjectName);
        
        for (Integer i = 0; i < columns.size(); i++) {
            String fieldApiName = columns[i];
            Boolean isEmailField = false;
            String detectionMethod = '';
            
            try {
                String fieldType = getFieldTypeFromSchema(fieldApiName, baseObjectName);
                System.debug('Field [' + i + '] ' + fieldApiName + ' - Type: ' + fieldType);
                
                if ('Email'.equalsIgnoreCase(fieldType)) {
                    isEmailField = true;
                    detectionMethod = 'Schema Type';
                } else if (fieldType.contains('Unknown') || fieldType.contains('Error')) {
                    // Schema lookup failed, use enhanced name-based detection
                    isEmailField = isEmailFieldByName(fieldApiName);
                    if (isEmailField) {
                        detectionMethod = 'Name Pattern (Schema Failed)';
                    }
                }
            } catch (Exception e) {
                System.debug('Could not determine field type for ' + fieldApiName + ': ' + e.getMessage());
                
                // Fallback to enhanced name-based detection
                isEmailField = isEmailFieldByName(fieldApiName);
                if (isEmailField) {  detectionMethod = 'Name Pattern (Exception)'; }
            }
            
            if (isEmailField) {
                emailIndices.add(i);
                System.debug('  *** EMAIL FIELD FOUND at index ' + i + ' *** (Method: ' + detectionMethod + ')');
            }
        }
        
        return emailIndices;
    }
    
    /**
     * Get field type from Salesforce schema with improved error handling
     */
    private static String getFieldTypeFromSchema(String fieldApiName, String baseObjectName) {
        try {
            // Handle lookup fields (contain dots)
            if (fieldApiName.contains('.')) {
                String[] parts = fieldApiName.split('\\.');
                if (parts.size() >= 2) {
                    String relationshipName = parts[0];
                    String relatedFieldName = parts[1];
                    
                    // Get the related object name
                    String relatedObjectName = getRelatedObjectName(relationshipName, baseObjectName);
                    
                    if (String.isNotBlank(relatedObjectName)) {
                        return getDirectFieldType(relatedFieldName, relatedObjectName);
                    } else {
                        System.debug('Could not resolve related object for relationship: ' + relationshipName);
                        return 'Unknown Relationship';
                    }
                }
                return 'Unknown (Complex Lookup)';
            } else {
                // Check if this might be a report-specific field name that doesn't exist on the object
                if (isReportSpecificField(fieldApiName)) {
                    System.debug('Detected report-specific field: ' + fieldApiName);
                    // For report-specific fields, determine type by name pattern
                    if (isEmailFieldByName(fieldApiName)) { return 'Email'; } else { return 'Report Specific Field'; }
                }
                
                // Direct field on base object
                return getDirectFieldType(fieldApiName, baseObjectName);
            }
        } catch (Exception e) {
            System.debug('Error determining field type for ' + fieldApiName + ': ' + e.getMessage());
            return 'Error: ' + e.getMessage();
        }
    }
    
    /**
     * Check if field name indicates a report-specific field (like kf_cntc_email)
     */
    private static Boolean isReportSpecificField(String fieldApiName) {
        String lowerFieldName = fieldApiName.toLowerCase();
        
        // Common report field prefixes that don't correspond to actual object fields
        return lowerFieldName.startsWith('kf_') ||    // Key fields
               lowerFieldName.startsWith('fk_') ||    // Foreign key fields
               lowerFieldName.startsWith('rf_') ||    // Report fields
               lowerFieldName.startsWith('calc_') ||  // Calculated fields
               lowerFieldName.startsWith('formula_'); // Formula fields
    }
    
    /**
     * Get field type for a direct field on an object with better error handling
     */
    private static String getDirectFieldType(String fieldName, String objectName) {
        try {
            // Validate inputs
            if (String.isBlank(fieldName) || String.isBlank(objectName)) {
                return 'Invalid Input';
            }
            
            // Get SObject type
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            if (objectType == null) {
                System.debug('Object not found in schema: ' + objectName);
                return 'Unknown Object: ' + objectName;
            }
            
            // Get field map
            Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
            Schema.SObjectField field = fieldMap.get(fieldName);
            
            if (field == null) {
                System.debug('Field not found on object ' + objectName + ': ' + fieldName);
                System.debug('Available fields: ' + fieldMap.keySet());
                return 'Unknown Field: ' + fieldName + ' on ' + objectName;
            }
            
            // Get field describe
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            Schema.DisplayType fieldType = fieldDescribe.getType();
            
            System.debug('Successfully found field type for ' + objectName + '.' + fieldName + ': ' + fieldType);
            return String.valueOf(fieldType);
            
        } catch (Exception e) {
            System.debug('Error describing field ' + fieldName + ' on ' + objectName + ': ' + e.getMessage());
            System.debug('Exception type: ' + e.getTypeName());
            return 'Error: ' + e.getMessage();
        }
    }
    
    /**
     * Get the related object name from a relationship field
     */
    private static String getRelatedObjectName(String relationshipName, String baseObjectName) {
        try {
            // Get SObject type
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(baseObjectName);
            if (objectType == null) {
                return null;
            }
            
            // Get field map
            Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
            
            // Try to find the relationship field
            // For custom relationships, convert __r to __c
            String relationshipFieldName = relationshipName;
            if (relationshipName.endsWith('__r')) { relationshipFieldName = relationshipName.replace('__r', '__c'); }
            
            Schema.SObjectField relationshipField = fieldMap.get(relationshipFieldName);
            if (relationshipField != null) { 
                Schema.DescribeFieldResult fieldDescribe = relationshipField.getDescribe();
                List<Schema.sObjectType> referenceTo = fieldDescribe.getReferenceTo();
                
                if (!referenceTo.isEmpty()) { return referenceTo[0].getDescribe().getName(); }
            }
            
            return null;
            
        } catch (Exception e) {
            System.debug('Error getting related object for relationship ' + relationshipName + ': ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Get the base object name from report metadata
     */
    private static String getReportBaseObjectName(Reports.ReportMetadata metadata) {
        try {
            Reports.ReportType reportType = metadata.getReportType();
            if (reportType != null) {
                String reportTypeStr = String.valueOf(reportType);
                return extractBaseObjectNameFromReportType(reportTypeStr);
            }
        } catch (Exception e) {
            System.debug('Could not determine base object name: ' + e.getMessage());
        }
        return 'Contact'; // Default fallback
    }
    
    /**
     * Extract base object name from report type string
     */
    private static String extractBaseObjectNameFromReportType(String reportTypeStr) {
        // Handle custom entity relationships like: CustomEntityCustomEntity$Program__c$Program_Participation__c@Program_Participation__c.Payer__c
        if (reportTypeStr.contains('CustomEntityCustomEntity$')) {
            String remaining = reportTypeStr.substring(reportTypeStr.indexOf('CustomEntityCustomEntity$') + 'CustomEntityCustomEntity$'.length());
            if (remaining.contains('$')) { String firstObject = remaining.split('\\$')[0]; return firstObject; } else if (remaining.contains('@')) { String firstObject = remaining.split('@')[0]; return firstObject; }
        }
        
        // Handle standard objects
        if (reportTypeStr.contains('Contact')) { return 'Contact'; } else if (reportTypeStr.contains('Account')) { return 'Account'; } else if (reportTypeStr.contains('Lead')) { return 'Lead'; } else if (reportTypeStr.contains('Opportunity')) { return 'Opportunity'; } else if (reportTypeStr.contains('Case')) { return 'Case'; } else if (reportTypeStr.contains('Campaign')) { return 'Campaign'; } else if (reportTypeStr.contains('User')) {  return 'User'; } else if (reportTypeStr.contains('Task')) { return 'Task'; } else if (reportTypeStr.contains('Event')) { return 'Event'; }   
        return 'Contact'; // Default fallback
    }
    
    /**
     * Get the base object of the report from report type
     */
    private static String getReportBaseObject(Reports.ReportMetadata metadata) {
        try {
            Reports.ReportType reportType = metadata.getReportType();
            if (reportType != null) {
                String reportTypeStr = String.valueOf(reportType);
                System.debug('Full Report Type: ' + reportTypeStr);
                
                // Parse the complex report type structure
                return parseReportTypeForBaseObject(reportTypeStr);
            }
        } catch (Exception e) {
            System.debug('Could not determine base object: ' + e.getMessage());
        }
        return 'Unknown Object';
    }
    
    /**
     * Parse complex report type string to extract base object
     */
    private static String parseReportTypeForBaseObject(String reportTypeStr) {
        // Extract label if available
        String label = '';
        if (reportTypeStr.contains('label=')) {
            Integer labelStart = reportTypeStr.indexOf('label=') + 6;
            Integer labelEnd = reportTypeStr.indexOf(',', labelStart);
            if (labelEnd == -1) labelEnd = reportTypeStr.indexOf(']', labelStart);
            if (labelEnd > labelStart) {
                label = reportTypeStr.substring(labelStart, labelEnd);
            }
        }
        
        // Extract type information
        String typeInfo = '';
        if (reportTypeStr.contains('type=')) {
            Integer typeStart = reportTypeStr.indexOf('type=') + 5;
            Integer typeEnd = reportTypeStr.indexOf(']', typeStart);
            if (typeEnd > typeStart) {
                typeInfo = reportTypeStr.substring(typeStart, typeEnd);
            }
        }
        
        System.debug('Parsed Label: ' + label);
        System.debug('Parsed Type: ' + typeInfo);
        
        // Determine base object from type information
        String baseObject = extractBaseObjectFromType(typeInfo);
        
        if (String.isNotBlank(label)) {
            return baseObject + ' (Report: "' + label + '")';
        } else {
            return baseObject;
        }
    }
    
    /**
     * Extract base object from type string
     */
    private static String extractBaseObjectFromType(String typeInfo) {
        if (String.isBlank(typeInfo)) {
            return 'Unknown Object';
        }
        
        // Handle custom entity relationships like: CustomEntityCustomEntity$Program__c$Program_Participation__c@Program_Participation__c.Payer__c
        if (typeInfo.startsWith('CustomEntityCustomEntity$')) {
            // Extract the first custom object mentioned
            String remaining = typeInfo.substring('CustomEntityCustomEntity$'.length());
            
            if (remaining.contains('$')) { String firstObject = remaining.split('\\$')[0]; return firstObject + ' (Custom Object)'; } else if (remaining.contains('@')) { String firstObject = remaining.split('@')[0]; return firstObject + ' (Custom Object)'; }
        }
        
        // Handle standard object patterns
        if (typeInfo.contains('Contact')) { return 'Contact'; } else if (typeInfo.contains('Account')) { return 'Account'; } else if (typeInfo.contains('Lead')) { return 'Lead'; } else if (typeInfo.contains('Opportunity')) { return 'Opportunity'; } else if (typeInfo.contains('Case')) { return 'Case'; } else if (typeInfo.contains('Campaign')) { return 'Campaign'; } else if (typeInfo.contains('User')) { return 'User'; } else if (typeInfo.contains('Task')) { return 'Task'; } else if (typeInfo.contains('Event')) { return 'Event'; }
        
        // If it contains custom object indicators // Try to extract the first custom object name
        if (typeInfo.contains('__c')) { String[] parts = typeInfo.split('\\$|@|\\.'); for (String part : parts) { if (part.endsWith('__c')) { return part + ' (Custom Object)'; }}
        }
        
        return 'Complex Report Type: ' + typeInfo;
    }
    
    /**
     * Enhanced email field detection by name patterns
     */
    private static Boolean isEmailFieldByName(String fieldApiName) {
        String lowerFieldName = fieldApiName.toLowerCase();
        
        // Direct email field patterns
        if (lowerFieldName.equals('email') || lowerFieldName.equals('emailaddress') || lowerFieldName.equals('email_address') || lowerFieldName.equals('email__c')) { return true; }
        
        // Common email field name patterns
        if (lowerFieldName.contains('email')) { 
            // Include patterns like: kf_cntc_email, fk_cntc_email, contact_email, etc.
            return true;
        }
        
        // Specific patterns for report fields
        if (lowerFieldName.contains('_email') || lowerFieldName.startsWith('email_') || lowerFieldName.endsWith('_email')) { return true; }
        
        // Handle specific prefixes that might indicate email fields
        if (lowerFieldName.startsWith('kf_') && lowerFieldName.contains('email')) { return true;} // Key field patterns like kf_cntc_email 
        
       if (lowerFieldName.startsWith('fk_') && lowerFieldName.contains('email')) { return true;} // Foreign key patterns like fk_cntc_email 
        
        // Contact-specific email patterns
       if (lowerFieldName.contains('cntc') && lowerFieldName.contains('email')) { return true; }// Contact email patterns like kf_cntc_email 
        
       if (lowerFieldName.contains('contact') && lowerFieldName.contains('email')) { return true;} // Full contact email patterns 
        
        return false;
    }
    
    /**
     * Attempt to determine source object from relationship name
     */
    private static String getSourceObjectFromRelationship(String relationshipName) {
        // Common relationship patterns
        if (relationshipName.toLowerCase().contains('account')) { return 'Account'; } else if (relationshipName.toLowerCase().contains('contact')) { return 'Contact'; } else if (relationshipName.toLowerCase().contains('user')) { return 'User';} else if (relationshipName.toLowerCase().contains('lead')) { return 'Lead'; } else if (relationshipName.toLowerCase().contains('opportunity')) { return 'Opportunity'; } else if (relationshipName.toLowerCase().contains('case')) { return 'Case'; } else if (relationshipName.toLowerCase().contains('campaign')) { return 'Campaign'; } else if (relationshipName.toLowerCase().endsWith('__r')) {           
            String objectName = relationshipName.replace('__r', '__c'); return objectName + ' (Custom Object)'; } else if (relationshipName.toLowerCase().contains('owner')) { return 'User (Owner)';        } else if (relationshipName.toLowerCase().contains('createdby')) {return 'User (Created By)'; } else if (relationshipName.toLowerCase().contains('lastmodifiedby')) { return 'User (Last Modified By)'; }        
        return 'Unknown - ' + relationshipName;
    }
    
    /**
     * Extract email string from report data cell
     */
    private static String extractEmailFromCell(Reports.ReportDataCell cell) {
        if (cell == null || cell.getValue() == null) {
            return null;
        }
        
        String cellValue = String.valueOf(cell.getValue()).trim();
        
        // Handle cases where cell might contain multiple emails or additional text
        if (cellValue.contains(';')) {
            // Multiple emails separated by semicolon
            List<String> emails = cellValue.split(';');
            return emails[0].trim(); // Return first email
        } else if (cellValue.contains(',')) {
            // Multiple emails separated by comma
            List<String> emails = cellValue.split(',');
            return emails[0].trim(); // Return first email
        }
        
        return cellValue;
    }
    
    /**
     * Basic email validation
     */
    private static Boolean isValidEmail(String email) {
        if (String.isBlank(email)) {
            return false;
        }
        
        // Basic email pattern validation
        String emailPattern = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
        Pattern pattern = Pattern.compile(emailPattern);
        Matcher matcher = pattern.matcher(email);
        
        return matcher.matches();
    }
    
    /**
     * Input wrapper class for Flow
     */
    public class ReportRequest {
        @InvocableVariable(label='Report ID' description='The ID of the report to run' required=true)
        public String reportId;
    }
    
    /**
     * Custom exception for report processing errors
     */
    public class ReportProcessingException extends Exception {}
}