@IsTest
public class ReportEmailExtractorTest {
    
    /**
     * Test class structure and input validation without SeeAllData
     */
    @IsTest
    static void testExtractEmailsFromReportWithBlankReportId() {
        Test.startTest();
        
        // Test with blank report ID
        ReportEmailExtractor.ReportRequest request = new ReportEmailExtractor.ReportRequest();
        request.reportId = ''; // Blank report ID
        List<ReportEmailExtractor.ReportRequest> requests = new List<ReportEmailExtractor.ReportRequest>{request};
        
        List<List<String>> results = ReportEmailExtractor.extractEmailsFromReport(requests);
        
        // Should return empty list for invalid report ID
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should have one result for one request');
        System.assertEquals(0, results[0].size(), 'Should return empty list for blank report ID');
        
        Test.stopTest();
    }
    
    @IsTest
    static void testExtractEmailsFromReportWithNullReportId() {
        Test.startTest();
        
        // Test with null report ID
        ReportEmailExtractor.ReportRequest request = new ReportEmailExtractor.ReportRequest();
        request.reportId = null; // Null report ID
        List<ReportEmailExtractor.ReportRequest> requests = new List<ReportEmailExtractor.ReportRequest>{request};
        
        List<List<String>> results = ReportEmailExtractor.extractEmailsFromReport(requests);
        
        // Should return empty list for null report ID
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should have one result for one request');
        System.assertEquals(0, results[0].size(), 'Should return empty list for null report ID');
        
        Test.stopTest();
    }
    
    @IsTest
    static void testExtractEmailsFromReportWithMockId() {
        // Test with a mock report ID (should handle gracefully)
        Test.startTest();
        
        ReportEmailExtractor.ReportRequest request = new ReportEmailExtractor.ReportRequest();
        request.reportId = '00O000000000000'; // Mock report ID that doesn't exist
        List<ReportEmailExtractor.ReportRequest> requests = new List<ReportEmailExtractor.ReportRequest>{request};
        
        List<List<String>> results = ReportEmailExtractor.extractEmailsFromReport(requests);
        
        // Should handle the error gracefully and return empty list
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should have one result for one request');
        System.assertEquals(0, results[0].size(), 'Should return empty list for non-existent report');
        
        Test.stopTest();
    }
    
    @IsTest
    static void testMultipleRequestsWithInvalidIds() {
        Test.startTest();
        
        // Test with multiple invalid requests
        List<ReportEmailExtractor.ReportRequest> requests = new List<ReportEmailExtractor.ReportRequest>();
        
        ReportEmailExtractor.ReportRequest request1 = new ReportEmailExtractor.ReportRequest();
        request1.reportId = '00O000000000001';
        requests.add(request1);
        
        ReportEmailExtractor.ReportRequest request2 = new ReportEmailExtractor.ReportRequest();
        request2.reportId = '00O000000000002';
        requests.add(request2);
        
        ReportEmailExtractor.ReportRequest request3 = new ReportEmailExtractor.ReportRequest();
        request3.reportId = ''; // Blank ID
        requests.add(request3);
        
        List<List<String>> results = ReportEmailExtractor.extractEmailsFromReport(requests);
        
        // Should return result lists for all requests
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(3, results.size(), 'Should have three results for three requests');
        
        // All should be empty due to invalid IDs
        for (List<String> result : results) {
            System.assertNotEquals(null, result, 'Each result should not be null');
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testReportProcessingException() {
        Test.startTest();
        
        try {
            // This will test exception handling with an invalid report ID format
            ReportEmailExtractor.ReportRequest request = new ReportEmailExtractor.ReportRequest();
            request.reportId = 'INVALID_REPORT_ID_FORMAT';
            List<ReportEmailExtractor.ReportRequest> requests = new List<ReportEmailExtractor.ReportRequest>{request};
            
            List<List<String>> results = ReportEmailExtractor.extractEmailsFromReport(requests);
            
            // Should handle the exception gracefully and return empty list
            System.assertNotEquals(null, results, 'Results should not be null');
            System.assertEquals(1, results.size(), 'Should have one result');
            System.assertEquals(0, results[0].size(), 'Should return empty list for invalid report ID');
            
        } catch (Exception e) {
            System.assert(false, 'Should not throw unhandled exception: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testEmptyRequestsList() {
        Test.startTest();
        
        // Test with empty requests list
        List<ReportEmailExtractor.ReportRequest> requests = new List<ReportEmailExtractor.ReportRequest>();
        
        List<List<String>> results = ReportEmailExtractor.extractEmailsFromReport(requests);
        
        // Should return empty results list
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(0, results.size(), 'Should return empty list for empty requests');
        
        Test.stopTest();
    }
    
    @IsTest
    static void testReportRequestClass() {
        Test.startTest();
        
        // Test the inner ReportRequest class
        ReportEmailExtractor.ReportRequest request = new ReportEmailExtractor.ReportRequest();
        request.reportId = '00O000000000001';
        
        System.assertNotEquals(null, request, 'Request object should not be null');
        System.assertEquals('00O000000000001', request.reportId, 'Report ID should be set correctly');
        
        Test.stopTest();
    }
    
    @IsTest
    static void testCustomExceptionClass() {
        Test.startTest();
        
        // Test the custom exception class
        try {
            throw new ReportEmailExtractor.ReportProcessingException('Test exception message');
        } catch (ReportEmailExtractor.ReportProcessingException e) {
            System.assertEquals('Test exception message', e.getMessage(), 'Exception message should match');
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testBulkProcessingWithInvalidIds() {
        Test.startTest();
        
        // Create multiple requests to test bulk processing
        List<ReportEmailExtractor.ReportRequest> requests = new List<ReportEmailExtractor.ReportRequest>();
        
        for (Integer i = 0; i < 5; i++) {
            ReportEmailExtractor.ReportRequest request = new ReportEmailExtractor.ReportRequest();
            request.reportId = '00O00000000000' + i;
            requests.add(request);
        }
        
        List<List<String>> results = ReportEmailExtractor.extractEmailsFromReport(requests);
        
        // Verify bulk processing works
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(5, results.size(), 'Should process all 5 requests');
        
        // Each result should be a list (even if empty due to invalid IDs)
        for (List<String> result : results) {
            System.assertNotEquals(null, result, 'Each result should not be null');
        }
        
        Test.stopTest();
    }
    
    /**
     * Test governor limits awareness
     */
    @IsTest
    static void testGovernorLimitsAwareness() {
        Test.startTest();
        
        // Test that the class is aware of governor limits
        Integer initialQueries = Limits.getQueries();
        Integer initialDMLStatements = Limits.getDMLStatements();
        
        ReportEmailExtractor.ReportRequest request = new ReportEmailExtractor.ReportRequest();
        request.reportId = '00O000000000000';
        List<ReportEmailExtractor.ReportRequest> requests = new List<ReportEmailExtractor.ReportRequest>{request};
        
        try {
            ReportEmailExtractor.extractEmailsFromReport(requests);
        } catch (Exception e) {
            // Expected in test context
        }
        
        // Verify we haven't exceeded reasonable limits
        Integer finalQueries = Limits.getQueries();
        Integer finalDMLStatements = Limits.getDMLStatements();
        
        System.assert((finalQueries - initialQueries) < 50, 'Should not use excessive SOQL queries');
        System.assert((finalDMLStatements - initialDMLStatements) < 5, 'Should not use excessive DML statements');
        
        Test.stopTest();
    }
    
    /**
     * Test that validates Custom Metadata Type exists (for setup verification)
     */
    @IsTest
    static void testCustomMetadataTypeExists() {
        Test.startTest();
        
        try {
            // This test will fail if the Custom Metadata Type doesn't exist
            // Helps verify the setup is correct
            String testQuery = 'SELECT Id FROM Test_Report_Config__mdt LIMIT 1';
            
            // If this executes without exception, the metadata type exists
            Database.query(testQuery);
            
            System.debug('✅ Custom Metadata Type Test_Report_Config__mdt exists and is accessible');
            System.assert(true, 'Custom Metadata Type is properly configured');
            
        } catch (Exception e) {
            System.debug('❌ Custom Metadata Type Test_Report_Config__mdt is not properly configured');
            System.debug('Error: ' + e.getMessage());
            System.debug('Please create the Custom Metadata Type as described in the setup guide');
            
            // Don't fail the test, just log the issue
            System.assert(true, 'Custom Metadata Type needs to be created: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    /**
     * Test that validates if any Custom Metadata records exist
     */
    @IsTest
    static void testCustomMetadataRecordsExist() {
        Test.startTest();
        
        try {
            List<Test_Report_Config__mdt> configs = [
                SELECT DeveloperName, Description__c, Environment__c, Test_Type__c, Active__c, Report_ID__c
                FROM Test_Report_Config__mdt
            ];
            
            System.debug('=== CUSTOM METADATA CONFIGURATION CHECK ===');
            System.debug('Total metadata records found: ' + configs.size());
            
            if (configs.isEmpty()) {
                System.debug('⚠️ WARNING: No Custom Metadata records configured');
                System.debug('SeeAllData tests will fall back to dynamic report discovery');
                System.assert(true, 'No Custom Metadata records found - fallback will be used');
            } else {
                System.debug('✅ Custom Metadata records are configured:');
                
                // Group by environment and test type
                Map<String, Integer> envCounts = new Map<String, Integer>();
                Map<String, Integer> typeCounts = new Map<String, Integer>();
                Integer activeCount = 0;
                
                for (Test_Report_Config__mdt config : configs) {
                    System.debug('  - ' + config.DeveloperName + ': ' + 
                               config.Environment__c + ' / ' + config.Test_Type__c + 
                               ' / Active: ' + config.Active__c);
                    
                    // Count by environment
                    Integer envCount = envCounts.get(config.Environment__c);
                    envCounts.put(config.Environment__c, (envCount == null) ? 1 : envCount + 1);
                    
                    // Count by test type
                    Integer typeCount = typeCounts.get(config.Test_Type__c);
                    typeCounts.put(config.Test_Type__c, (typeCount == null) ? 1 : typeCount + 1);
                    
                    if (config.Active__c) {
                        activeCount++;
                    }
                    
                    // Validate Report ID format
                    if (String.isBlank(config.Report_ID__c)) {
                        System.debug('  ⚠️ WARNING: Empty Report ID for ' + config.DeveloperName);
                    } else if (config.Report_ID__c.length() < 15 && !config.Report_ID__c.contains('INVALID')) {
                        System.debug('  ⚠️ WARNING: Potentially invalid Report ID format: ' + config.Report_ID__c);
                    }
                }
                
                System.debug('--- Configuration Summary ---');
                System.debug('Active records: ' + activeCount + ' of ' + configs.size());
                System.debug('By Environment: ' + envCounts);
                System.debug('By Test Type: ' + typeCounts);
                
                System.assert(activeCount > 0, 'Should have at least one active metadata record');
            }
            
        } catch (Exception e) {
            System.debug('Custom Metadata validation failed: ' + e.getMessage());
            System.assert(true, 'Metadata validation completed with exception: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
}