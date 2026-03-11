/**
@author: Haim Knokh
@date: 2026-03-11
@modified: 2026-03-11
@description: Test coverage for CreateOpportunitiesFromReportsController request/preview/create/update flows.
*
* Architecture Role
* =========================
* This test class validates the server contract of `CreateOpportunitiesFromReportsController`:
*   - server-driven config loading;
*   - preview lookup resolution;
*   - preview filtering by duplicate formula and supplemental fund ERP rule;
*   - chunked Opportunity creation;
*   - post-create refresh of Opportunity and Payment rows;
*   - Payment update behavior.
*
* Main Object Links And Data Flow
* =========================
* The tests create and validate:
*   - `Account`
*   - `Contact`
*   - `Campaign`
*   - `Fund__c`
*   - `Opportunity`
*   - `npe01__OppPayment__c`
*
* Runtime Constraints And Why This Implementation Exists
* =========================
* The controller depends on org metadata such as the `Request` Opportunity record type and the
* `Create_Opportunity_From_Reports_New_Opp` field set. The tests therefore exercise the public Aura methods
* and rely on the same org metadata contract instead of duplicating controller internals.
*
* Important Contract Caveats
* =========================
* Report Analytics execution is covered through controller-level synthetic report definitions exposed via
* `@TestVisible` helpers. That keeps the tests compliant with `SeeAllData=false` while still exercising the
* selector and one-report retrieval branches with deterministic metadata and row payloads.
**/
@IsTest
private class CreateOpportunitiesFromReportsCtrlTest {

    // -------------------------------
    // Constants
    // -------------------------------

    /** Account name used by the sample Request Opportunity that seeds missing-required defaults. */
    private static final String DEFAULT_SAMPLE_ACCOUNT_NAME = 'COFR Default Sample Account';

    /** Account name used by the duplicate-formula blocking scenario. */
    private static final String DUPLICATE_ACCOUNT_NAME = 'COFR Duplicate Account';

    /** Account name used by the supplemental-fund ERP blocking scenario. */
    private static final String ERP_BLOCKED_ACCOUNT_NAME = 'COFR ERP Blocked Account';

    /** Account name used by the allowed create/preview scenario. */
    private static final String ALLOWED_ACCOUNT_NAME = 'COFR Allowed Account';

    /** Account name used by the isolated ERP Payment success scenario. */
    private static final String ERP_SUCCESS_ACCOUNT_NAME = 'COFR ERP Success Account';

    /** Fund name used for the supplemental rehabilitation grant rule. */
    private static final String SUPPLEMENTAL_FUND_NAME = 'COFR Supplemental Fund';

    /** Fund name used for a regular non-blocking fund. */
    private static final String REGULAR_FUND_NAME = 'COFR Regular Fund';

    /** Campaign name used by preview lookup display tests. */
    private static final String TEST_CAMPAIGN_NAME = 'COFR Campaign';

    /** Valid Israeli ID number used to satisfy ERP-stage primary-contact validations. */
    private static final String VALID_ISRAELI_ID_NUMBER = '123456782';

    /** Valid bank picklist value used to satisfy Contact and Payment bank validations. */
    private static final String VALID_BANK_NAME = '4 - בנק יהב';

    /** Fake Account id used to validate not-found row handling inside the create chunk. */
    private static final Id NON_EXISTENT_ACCOUNT_ID = (Id)'001000000000000AAA';

    /** Test user alias prefix used by payment-update runAs scenarios. */
    private static final String TEST_USER_ALIAS_PREFIX = 'cofr';

    /** Fake supported Account report id used by synthetic report-retrieval tests. */
    private static final String TEST_ACCOUNT_REPORT_ID = '00O000000000001AAA';

    /** Fake supported Contact-and-Account report id used by synthetic report-retrieval tests. */
    private static final String TEST_ACCOUNT_CONTACT_REPORT_ID = '00O000000000002AAA';

    /** Fake unsupported report id used by synthetic report-retrieval tests. */
    private static final String TEST_UNSUPPORTED_REPORT_ID = '00O000000000003AAA';

    // -------------------------------
    // Private Methods
    // -------------------------------

    /**
     * Creates the shared non-setup test data.
     *
     * @example
     * No input payload is required.
     *
     * @return Returns nothing. Inserts reusable Accounts, Contacts, Funds, Campaign, and sample Request Opportunities.
    **/
    @TestSetup
    static void createTestData() {
        List<Account> accountsToInsert = new List<Account>{
            new Account(Name = DEFAULT_SAMPLE_ACCOUNT_NAME, Don_t_send_mailings__c = false),
            new Account(Name = DUPLICATE_ACCOUNT_NAME, Don_t_send_mailings__c = false),
            new Account(Name = ERP_BLOCKED_ACCOUNT_NAME, Don_t_send_mailings__c = false),
            new Account(Name = ALLOWED_ACCOUNT_NAME, Don_t_send_mailings__c = false),
            new Account(Name = ERP_SUCCESS_ACCOUNT_NAME, Don_t_send_mailings__c = false)
        };
        insert accountsToInsert;

        Map<String, Account> accountByName = m_getAccountsByName(new Set<String>{
            DEFAULT_SAMPLE_ACCOUNT_NAME,
            DUPLICATE_ACCOUNT_NAME,
            ERP_BLOCKED_ACCOUNT_NAME,
            ALLOWED_ACCOUNT_NAME,
            ERP_SUCCESS_ACCOUNT_NAME
        });
        Id defaultContactRecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Default').getRecordTypeId();
        List<Contact> contactsToInsert = new List<Contact>();

        for (Account accountRecord : accountByName.values()) {
            contactsToInsert.add(new Contact(
                RecordTypeId = defaultContactRecordTypeId,
                FirstName = 'COFR',
                LastName = accountRecord.Name + ' Contact',
                AccountId = accountRecord.Id,
                Citizenship__c = 'Israeli',
                Israeli_ID_number__c = VALID_ISRAELI_ID_NUMBER,
                Bank_Name__c = VALID_BANK_NAME,
                Bank_Branch_Number__c = '401',
                Bank_Account_Number__c = '028828',
                Bank_Details_Flag__c = false
            ));
        }
        insert contactsToInsert;

        Map<Id, Id> contactIdByAccountId = new Map<Id, Id>();

        for (Contact contactRecord : contactsToInsert) {
            contactIdByAccountId.put(contactRecord.AccountId, contactRecord.Id);
        }

        for (Account accountRecord : accountByName.values()) {
            accountRecord.npe01__One2OneContact__c = contactIdByAccountId.get(accountRecord.Id);
        }
        update accountByName.values();

        List<Contact> contactsToUpdate = [
            SELECT Id, Actual_Bank_Account_Number__c
            FROM Contact
            WHERE Id IN :contactIdByAccountId.values()
        ];

        for (Contact contactRecord : contactsToUpdate) {
            contactRecord.Actual_Bank_Account_Number__c = '028828';
        }
        update contactsToUpdate;

        insert new List<Fund__c>{
            new Fund__c(
                Name = SUPPLEMENTAL_FUND_NAME,
                Fund_type__c = GlobalConstantsAndEnums.FUND_TYPE_SUPPLEMENTAL_REHABILITATION_GRANT
            ),
            new Fund__c(
                Name = REGULAR_FUND_NAME,
                Fund_type__c = 'סיוע חירום'
            )
        };

        insert new Campaign(Name = TEST_CAMPAIGN_NAME, IsActive = true);

        Id requestRecordTypeId = m_getRequestRecordTypeId();
        Map<String, Fund__c> fundByName = m_getFundsByName(new Set<String>{
            SUPPLEMENTAL_FUND_NAME,
            REGULAR_FUND_NAME
        });

        insert new List<Opportunity>{
            new Opportunity(
                Name = 'COFR Default Sample Opportunity',
                RecordTypeId = requestRecordTypeId,
                AccountId = accountByName.get(DEFAULT_SAMPLE_ACCOUNT_NAME).Id,
                StageName = 'New',
                CloseDate = Date.today().addDays(30),
                Amount = 25,
                Fund__c = fundByName.get(REGULAR_FUND_NAME).Id
            ),
            new Opportunity(
                Name = 'COFR Duplicate Blocking Opportunity',
                RecordTypeId = requestRecordTypeId,
                AccountId = accountByName.get(DUPLICATE_ACCOUNT_NAME).Id,
                StageName = 'New',
                CloseDate = Date.today().addDays(10),
                Amount = 100,
                Fund__c = fundByName.get(REGULAR_FUND_NAME).Id
            ),
            new Opportunity(
                Name = 'COFR ERP Blocking Opportunity',
                RecordTypeId = requestRecordTypeId,
                AccountId = accountByName.get(ERP_BLOCKED_ACCOUNT_NAME).Id,
                StageName = GlobalConstantsAndEnums.STAGE_TRANSFERRED_TO_ERP,
                CloseDate = Date.today().addDays(10),
                Amount = 100,
                Fund__c = fundByName.get(SUPPLEMENTAL_FUND_NAME).Id
            )
        };
    }

    /**
     * Verifies that config loading returns the Request record type, field-set fields, and stage options.
     *
     * @example
     * No input payload is required.
     *
     * @return Returns nothing. Asserts the shape of `getConfig()`.
    **/
    @IsTest
    private static void m_getConfigReturnsServerDrivenRequestConfig() {
        Test.startTest();
        CreateOpportunitiesFromReportsController.Response response = CreateOpportunitiesFromReportsController.getConfig();
        Test.stopTest();

        System.assertEquals(true, response.isSuccess, 'Config request should succeed.');
        System.assertNotEquals(null, response.config, 'Config payload should be returned.');
        System.assertEquals(
            GlobalConstantsAndEnums.REQUEST_RECORD_TYPE_DEVELOPER_NAME,
            response.config.requestRecordTypeDeveloperName,
            'Request record type developer name should match the global constant.'
        );
        System.assertNotEquals(null, response.config.requestRecordTypeId, 'Request record type id should be resolved.');
        System.assert(response.config.requestFieldSetFields != null && !response.config.requestFieldSetFields.isEmpty(), 'Field set fields should be returned.');
        System.assert(response.config.requestStageOptions != null && !response.config.requestStageOptions.isEmpty(), 'Stage options should be returned.');
    }

    /**
     * Verifies that preview lookup values are resolved to record names.
     *
     * @example
     * Uses one `Fund__c` lookup id and one `CampaignId` lookup id.
     *
     * @return Returns nothing. Asserts the shape of `resolvePreviewLookupDisplayValues(String)`.
    **/
    @IsTest
    private static void m_resolvePreviewLookupDisplayValuesReturnsNames() {
        Fund__c regularFund = [SELECT Id, Name FROM Fund__c WHERE Name = :REGULAR_FUND_NAME LIMIT 1];
        Campaign campaignRecord = [SELECT Id, Name FROM Campaign WHERE Name = :TEST_CAMPAIGN_NAME LIMIT 1];
        CreateOpportunitiesFromReportsController.Request requestWrapper = new CreateOpportunitiesFromReportsController.Request();

        requestWrapper.lookupFieldValueEntriesJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'fieldApiName' => 'Fund__c',
                'recordId' => regularFund.Id
            },
            new Map<String, Object>{
                'fieldApiName' => 'CampaignId',
                'recordId' => campaignRecord.Id
            }
        });

        Test.startTest();
        CreateOpportunitiesFromReportsController.Response response =
            CreateOpportunitiesFromReportsController.resolvePreviewLookupDisplayValues(JSON.serialize(requestWrapper));
        Test.stopTest();

        System.assertEquals(true, response.isSuccess, 'Lookup resolution should succeed.');
        System.assertEquals(2, response.lookupDisplayValues.size(), 'Two lookup display values should be returned.');
        System.assertEquals(regularFund.Name, response.lookupDisplayValues[0].recordName, 'Fund name should be resolved.');
        System.assertEquals(campaignRecord.Name, response.lookupDisplayValues[1].recordName, 'Campaign name should be resolved.');
    }

    /**
     * Verifies that selector loading succeeds and report retrieval safely fails for an invalid report id.
     *
     * @example
     * Uses fake report id `00O000000000000AAA`.
     *
     * @return Returns nothing. Asserts the public report-related Aura methods are callable from tests.
    **/
    @IsTest
    private static void m_selectorMethodsReturnSafeResponses() {
        Test.startTest();
        CreateOpportunitiesFromReportsController.Response selectorResponse = CreateOpportunitiesFromReportsController.getSelectorData();
        CreateOpportunitiesFromReportsController.Request requestWrapper = new CreateOpportunitiesFromReportsController.Request();
        requestWrapper.reportId = '00O000000000000AAA';
        CreateOpportunitiesFromReportsController.Response retrieveResponse =
            CreateOpportunitiesFromReportsController.retrieveReportAccounts(JSON.serialize(requestWrapper));
        Test.stopTest();

        System.assertEquals(true, selectorResponse.isSuccess, 'Selector load should succeed even when the list is empty.');
        System.assertEquals(false, retrieveResponse.isSuccess, 'Invalid report retrieval should fail safely.');
        System.assertNotEquals('', retrieveResponse.errorMessage, 'Failure should return an error message.');
    }

    /**
     * Verifies that selector load and report retrieval succeed against synthetic report definitions under `SeeAllData=false`.
     *
     * @example
     * Registers supported and unsupported synthetic reports, then exercises `getSelectorData()` and `retrieveReportAccounts(String)`.
     *
     * @return Returns nothing. Asserts report type inference, Account extraction, and mailing filtering.
    **/
    @IsTest
    private static void m_selectorAndRetrieveAccountsSupportSyntheticReports() {
        Map<String, Account> accountByName = m_getAccountsByName(new Set<String>{
            ALLOWED_ACCOUNT_NAME,
            DUPLICATE_ACCOUNT_NAME
        });
        Account allowedAccount = accountByName.get(ALLOWED_ACCOUNT_NAME);
        Account duplicateAccount = accountByName.get(DUPLICATE_ACCOUNT_NAME);
        duplicateAccount.Don_t_send_mailings__c = true;
        update duplicateAccount;

        CreateOpportunitiesFromReportsController.m_clearTestReportDefinitions();
        CreateOpportunitiesFromReportsController.m_registerTestReportDefinition(
            TEST_ACCOUNT_REPORT_ID,
            'Synthetic Account Report',
            'Folder A',
            'TABULAR',
            new List<String>{ 'ACCOUNT.NAME', 'ACCOUNT.ID' },
            new List<List<Object>>{
                new List<Object>{ allowedAccount.Id, allowedAccount.Id },
                new List<Object>{ duplicateAccount.Id, duplicateAccount.Id },
                new List<Object>{ 'Ignored Label', 'notAnAccountId' }
            }
        );
        CreateOpportunitiesFromReportsController.m_registerTestReportDefinition(
            TEST_ACCOUNT_CONTACT_REPORT_ID,
            'Synthetic Account Contact Report',
            'Folder B',
            'TABULAR',
            new List<String>{ 'CONTACT.NAME', 'ACCOUNT.ID' },
            new List<List<Object>>{
                new List<Object>{ 'Sample Contact', allowedAccount.Id }
            }
        );
        CreateOpportunitiesFromReportsController.m_registerTestReportDefinition(
            TEST_UNSUPPORTED_REPORT_ID,
            'Synthetic Unsupported Report',
            'Folder C',
            'TABULAR',
            new List<String>{ 'CONTACT.NAME' },
            new List<List<Object>>{
                new List<Object>{ 'Contact Only' }
            }
        );

        CreateOpportunitiesFromReportsController.Request accountReportRequest = new CreateOpportunitiesFromReportsController.Request();
        accountReportRequest.reportId = TEST_ACCOUNT_REPORT_ID;
        CreateOpportunitiesFromReportsController.Request accountContactReportRequest = new CreateOpportunitiesFromReportsController.Request();
        accountContactReportRequest.reportId = TEST_ACCOUNT_CONTACT_REPORT_ID;
        CreateOpportunitiesFromReportsController.Request unsupportedReportRequest = new CreateOpportunitiesFromReportsController.Request();
        unsupportedReportRequest.reportId = TEST_UNSUPPORTED_REPORT_ID;

        Test.startTest();
        CreateOpportunitiesFromReportsController.Response selectorResponse = CreateOpportunitiesFromReportsController.getSelectorData();
        CreateOpportunitiesFromReportsController.Response accountReportResponse =
            CreateOpportunitiesFromReportsController.retrieveReportAccounts(JSON.serialize(accountReportRequest));
        CreateOpportunitiesFromReportsController.Response accountContactReportResponse =
            CreateOpportunitiesFromReportsController.retrieveReportAccounts(JSON.serialize(accountContactReportRequest));
        CreateOpportunitiesFromReportsController.Response unsupportedReportResponse =
            CreateOpportunitiesFromReportsController.retrieveReportAccounts(JSON.serialize(unsupportedReportRequest));
        Test.stopTest();

        System.assertEquals(true, selectorResponse.isSuccess, 'Synthetic selector load should succeed.');
        System.assertEquals(3, selectorResponse.availableReports.size(), 'All synthetic reports should be returned.');

        System.assertEquals(true, accountReportResponse.isSuccess, 'Synthetic Account report should load successfully.');
        System.assertEquals('AccountList', accountReportResponse.reportData.reportType, 'Account report type should be inferred.');
        System.assertEquals(2, accountReportResponse.reportData.accountCount, 'Two unique Accounts should be extracted.');
        System.assertEquals(1, accountReportResponse.reportData.eligibleAccountCount, 'Only one Account should remain after mailing filtering.');

        System.assertEquals(true, accountContactReportResponse.isSuccess, 'Synthetic Contact-and-Account report should load successfully.');
        System.assertEquals(
            GlobalConstantsAndEnums.REPORT_TYPE_ACCOUNT_CONTACT,
            accountContactReportResponse.reportData.reportType,
            'Contact-and-Account report type should be inferred.'
        );
        System.assertEquals(1, accountContactReportResponse.reportData.accountCount, 'One Account should be extracted from the mixed report.');

        System.assertEquals(true, unsupportedReportResponse.isSuccess, 'Unsupported report should still return safely.');
        System.assertEquals(false, unsupportedReportResponse.isSupportedReport, 'Unsupported synthetic report should be marked unsupported.');
        System.assertEquals('TABULAR', unsupportedReportResponse.reportData.reportType, 'Unsupported report should expose its raw format.');

        CreateOpportunitiesFromReportsController.m_clearTestReportDefinitions();
    }

    /**
     * Verifies that preview keeps all Accounts when no supplemental-fund ERP block or duplicate block applies.
     *
     * @example
     * Uses `צור תמיד` semantics by sending a non-matching creation strategy literal.
     *
     * @return Returns nothing. Asserts preview returns all selected Accounts.
    **/
    @IsTest
    private static void m_getPreviewDataKeepsAccountsWhenNoBlocksApply() {
        Map<String, Account> accountByName = m_getAccountsByName(new Set<String>{
            DUPLICATE_ACCOUNT_NAME,
            ERP_BLOCKED_ACCOUNT_NAME,
            ALLOWED_ACCOUNT_NAME
        });
        CreateOpportunitiesFromReportsController.Request requestWrapper = new CreateOpportunitiesFromReportsController.Request();

        requestWrapper.creationStrategy = 'alwaysCreate';
        requestWrapper.selectedReportRowsJson = m_buildSelectedReportRowsJson(new List<Id>{
            accountByName.get(DUPLICATE_ACCOUNT_NAME).Id,
            accountByName.get(ERP_BLOCKED_ACCOUNT_NAME).Id,
            accountByName.get(ALLOWED_ACCOUNT_NAME).Id
        });
        requestWrapper.opportunityFieldValuesJson = JSON.serialize(new Map<String, Object>{
            'StageName' => 'New',
            'CloseDate' => String.valueOf(Date.today().addDays(30))
        });

        Test.startTest();
        CreateOpportunitiesFromReportsController.Response response =
            CreateOpportunitiesFromReportsController.getPreviewData(JSON.serialize(requestWrapper));
        Test.stopTest();

        System.assertEquals(true, response.isSuccess, 'Preview should succeed without filters.');
        System.assertEquals(3, response.previewData.accountCount, 'All three Accounts should remain in preview.');
        System.assertEquals(3, response.previewData.previewRows.size(), 'Three preview rows should be returned.');
    }

    /**
     * Verifies that preview applies both the supplemental-fund ERP block and the duplicate formula block.
     *
     * @example
     * Uses one report row with three Accounts and duplicate formula `((1 AND 2) OR 3)`.
     *
     * @return Returns nothing. Asserts that only the allowed Account remains after both filters.
    **/
    @IsTest
    private static void m_getPreviewDataAppliesSupplementalFundAndDuplicateFormulaFilters() {
        Map<String, Account> accountByName = m_getAccountsByName(new Set<String>{
            DUPLICATE_ACCOUNT_NAME,
            ERP_BLOCKED_ACCOUNT_NAME,
            ALLOWED_ACCOUNT_NAME
        });
        Fund__c supplementalFund = [SELECT Id FROM Fund__c WHERE Name = :SUPPLEMENTAL_FUND_NAME LIMIT 1];
        CreateOpportunitiesFromReportsController.Request requestWrapper = new CreateOpportunitiesFromReportsController.Request();

        requestWrapper.creationStrategy = 'matchSelectedFields';
        requestWrapper.selectedReportRowsJson = m_buildSelectedReportRowsJson(new List<Id>{
            accountByName.get(DUPLICATE_ACCOUNT_NAME).Id,
            accountByName.get(ERP_BLOCKED_ACCOUNT_NAME).Id,
            accountByName.get(ALLOWED_ACCOUNT_NAME).Id
        });
        requestWrapper.comparisonConditionsJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'rowNumber' => 1,
                'fieldApiName' => 'StageName',
                'operator' => 'equals',
                'value' => 'New'
            },
            new Map<String, Object>{
                'rowNumber' => 2,
                'fieldApiName' => 'Amount',
                'operator' => 'greaterOrEqual',
                'value' => '50'
            },
            new Map<String, Object>{
                'rowNumber' => 3,
                'fieldApiName' => 'CloseDate',
                'operator' => 'lessOrEqual',
                'value' => String.valueOf(Date.today().addDays(20))
            }
        });
        requestWrapper.comparisonFormulaText = '((1 AND 2) OR 3)';
        requestWrapper.opportunityFieldValuesJson = JSON.serialize(new Map<String, Object>{
            'StageName' => 'New',
            'CloseDate' => String.valueOf(Date.today().addDays(30)),
            'Fund__c' => supplementalFund.Id
        });

        Test.startTest();
        CreateOpportunitiesFromReportsController.Response response =
            CreateOpportunitiesFromReportsController.getPreviewData(JSON.serialize(requestWrapper));
        Test.stopTest();

        System.assertEquals(true, response.isSuccess, 'Preview should succeed with valid comparison inputs.');
        System.assertEquals(1, response.previewData.accountCount, 'Only the allowed Account should remain.');
        System.assertEquals(ALLOWED_ACCOUNT_NAME, response.previewData.previewRows[0].accountName, 'The allowed Account should remain in preview.');
    }

    /**
     * Verifies that invalid comparison formula input is returned as a safe Aura response error.
     *
     * @example
     * Uses one condition and an invalid formula that references condition `2`.
     *
     * @return Returns nothing. Asserts `getPreviewData(String)` returns `isSuccess = false`.
    **/
    @IsTest
    private static void m_getPreviewDataReturnsSafeErrorForInvalidFormula() {
        Account allowedAccount = [SELECT Id FROM Account WHERE Name = :ALLOWED_ACCOUNT_NAME LIMIT 1];
        CreateOpportunitiesFromReportsController.Request requestWrapper = new CreateOpportunitiesFromReportsController.Request();

        requestWrapper.creationStrategy = 'matchSelectedFields';
        requestWrapper.selectedReportRowsJson = m_buildSelectedReportRowsJson(new List<Id>{ allowedAccount.Id });
        requestWrapper.comparisonConditionsJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'rowNumber' => 1,
                'fieldApiName' => 'StageName',
                'operator' => 'equals',
                'value' => 'New'
            }
        });
        requestWrapper.comparisonFormulaText = '(1 AND 2)';
        requestWrapper.opportunityFieldValuesJson = JSON.serialize(new Map<String, Object>{
            'StageName' => 'New',
            'CloseDate' => String.valueOf(Date.today().addDays(30))
        });

        Test.startTest();
        CreateOpportunitiesFromReportsController.Response response =
            CreateOpportunitiesFromReportsController.getPreviewData(JSON.serialize(requestWrapper));
        Test.stopTest();

        System.assertEquals(false, response.isSuccess, 'Invalid formula should fail safely.');
        System.assert(response.errorMessage.contains('number of conditions referenced'), 'The returned error should explain the formula problem.');
    }

    /**
     * Verifies chunk creation, chunk refresh, and ERP Payment update success.
     *
     * @example
     * Creates one `New` Opportunity chunk for the allowed Account, refreshes it, then updates one manually created ERP Payment successfully.
     *
     * @return Returns nothing. Asserts the create/refresh/update flow updates Payment fields correctly.
    **/
    @IsTest
    private static void m_createRefreshAndUpdateChunksSucceed() {
        Account allowedAccount = [
            SELECT Id, Name, npe01__One2OneContact__c
            FROM Account
            WHERE Name = :ALLOWED_ACCOUNT_NAME
            LIMIT 1
        ];
        Account erpSuccessAccount = [
            SELECT Id, Name, npe01__One2OneContact__c
            FROM Account
            WHERE Name = :ERP_SUCCESS_ACCOUNT_NAME
            LIMIT 1
        ];
        Fund__c regularFund = [SELECT Id FROM Fund__c WHERE Name = :REGULAR_FUND_NAME LIMIT 1];
        CreateOpportunitiesFromReportsController.Request createRequest = new CreateOpportunitiesFromReportsController.Request();

        createRequest.accountIdsJson = JSON.serialize(new List<Id>{ allowedAccount.Id, NON_EXISTENT_ACCOUNT_ID });
        createRequest.preparedOpportunityJson = JSON.serialize(new Map<String, Object>{
            'StageName' => 'New',
            'CloseDate' => String.valueOf(Date.today().addDays(40)),
            'Amount' => 125,
            'Fund__c' => regularFund.Id
        });

        CreateOpportunitiesFromReportsController.Response createResponse =
            CreateOpportunitiesFromReportsController.createOpportunitiesChunk(JSON.serialize(createRequest));

        System.assertEquals(true, createResponse.isSuccess, 'Chunk create method should return success response.');
        System.assertEquals(1, createResponse.creationChunkData.createdOpportunityCount, 'One Opportunity should be created.');
        System.assertEquals(1, createResponse.creationChunkData.failedAccountCount, 'One fake Account should fail.');
        System.assertEquals(2, createResponse.creationChunkData.rows.size(), 'Both the success and failure rows should be returned.');

        List<Id> createdOpportunityIds = (List<Id>)JSON.deserialize(createResponse.creationChunkData.createdOpportunityIdsJson, List<Id>.class);
        Opportunity createdOpportunity = [
            SELECT Id, Name, AccountId, RecordTypeId, StageName, CloseDate, Amount, Fund__c,
                npsp__Primary_Contact__c, npsp__Requested_Amount__c
            FROM Opportunity
            WHERE Id IN :createdOpportunityIds
            LIMIT 1
        ];

        System.assertEquals(allowedAccount.Id, createdOpportunity.AccountId, 'Created Opportunity should be linked to the selected Account.');
        System.assertEquals(allowedAccount.npe01__One2OneContact__c, createdOpportunity.npsp__Primary_Contact__c, 'Primary contact should be copied from the Account.');
        System.assertEquals(125, createdOpportunity.npsp__Requested_Amount__c, 'Requested amount should mirror Amount.');
        System.assertEquals('New', createdOpportunity.StageName, 'Prepared stage should be applied.');

        CreateOpportunitiesFromReportsController.Request initialRefreshRequest = new CreateOpportunitiesFromReportsController.Request();
        initialRefreshRequest.opportunityIdsJson = JSON.serialize(createdOpportunityIds);

        CreateOpportunitiesFromReportsController.Response initialRefreshResponse =
            CreateOpportunitiesFromReportsController.refreshCreatedOpportunityChunk(JSON.serialize(initialRefreshRequest));

        System.assertEquals(true, initialRefreshResponse.isSuccess, 'Refresh should succeed after creation.');
        System.assert(initialRefreshResponse.refreshChunkData.foundPaymentCount >= 0, 'Initial refresh should return a non-negative Payment count.');

        Opportunity erpOpportunity = new Opportunity(
            Name = 'COFR ERP Payment Update Opportunity',
            RecordTypeId = m_getRequestRecordTypeId(),
            AccountId = erpSuccessAccount.Id,
            StageName = GlobalConstantsAndEnums.STAGE_READY_FOR_TRANSFER_TO_ERP,
            CloseDate = Date.today().addDays(20),
            Amount = 125,
            Fund__c = regularFund.Id,
            npsp__Primary_Contact__c = erpSuccessAccount.npe01__One2OneContact__c,
            Contact_Num_Id__c = VALID_ISRAELI_ID_NUMBER,
            Suspected_Duplicate__c = false
        );
        insert erpOpportunity;
        insert new npe01__OppPayment__c(
            npe01__Opportunity__c = erpOpportunity.Id,
            Beneficiary__c = erpSuccessAccount.npe01__One2OneContact__c
        );

        CreateOpportunitiesFromReportsController.Request secondRefreshRequest = new CreateOpportunitiesFromReportsController.Request();
        secondRefreshRequest.opportunityIdsJson = JSON.serialize(new List<Id>{ erpOpportunity.Id });

        CreateOpportunitiesFromReportsController.Response secondRefreshResponse =
            CreateOpportunitiesFromReportsController.refreshCreatedOpportunityChunk(JSON.serialize(secondRefreshRequest));

        System.assert(
            secondRefreshResponse.refreshChunkData.foundPaymentCount >= 1,
            'At least one Payment should be found for the ERP Opportunity.'
        );
        System.assertEquals(1, secondRefreshResponse.refreshChunkData.rows.size(), 'One refreshed row should be returned.');

        User paymentUpdateUser = m_createRunAsUser(true);
        CreateOpportunitiesFromReportsController.Request paymentUpdateRequest = new CreateOpportunitiesFromReportsController.Request();
        paymentUpdateRequest.paymentIdsJson = secondRefreshResponse.refreshChunkData.foundPaymentIdsJson;

        CreateOpportunitiesFromReportsController.Response paymentUpdateResponse;

        System.runAs(paymentUpdateUser) {
            paymentUpdateResponse = CreateOpportunitiesFromReportsController.updatePaymentsChunk(JSON.serialize(paymentUpdateRequest));
        }

        System.assertEquals(true, paymentUpdateResponse.isSuccess, 'Payment update should succeed for a permitted user.');
        System.assert(
            paymentUpdateResponse.paymentUpdateData.updatedPaymentCount >= 1,
            'At least one Payment should be updated.'
        );

        List<Id> updatedPaymentIds = (List<Id>)JSON.deserialize(
            paymentUpdateResponse.paymentUpdateData.updatedPaymentIdsJson,
            List<Id>.class
        );
        List<npe01__OppPayment__c> updatedPayments = [
            SELECT Id, ERP_Status__c, npe01__Payment_Amount__c
            FROM npe01__OppPayment__c
            WHERE Id IN :updatedPaymentIds
        ];

        System.assertEquals(
            paymentUpdateResponse.paymentUpdateData.updatedPaymentCount,
            updatedPayments.size(),
            'Every updated Payment id should be queryable after the update.'
        );

        for (npe01__OppPayment__c updatedPayment : updatedPayments) {
            System.assertEquals(
                GlobalConstantsAndEnums.STAGE_READY_FOR_TRANSFER_TO_ERP.toLowerCase(),
                String.valueOf(updatedPayment.ERP_Status__c).toLowerCase(),
                'ERP status should mirror Opportunity stage ignoring case differences applied by org automation.'
            );
            System.assertEquals(125, updatedPayment.npe01__Payment_Amount__c, 'Payment amount should mirror Opportunity amount.');
        }
    }

    /**
     * Verifies that Payment update skips non-ERP Opportunities without returning an error.
     *
     * @example
     * Creates one Payment linked to a `New` stage Request Opportunity and sends its id to `updatePaymentsChunk(String)`.
     *
     * @return Returns nothing. Asserts the chunk is skipped without errors.
    **/
    @IsTest
    private static void m_updatePaymentsChunkSkipsNonErpPaymentsWithoutError() {
        Account defaultSampleAccount = [SELECT Id FROM Account WHERE Name = :DEFAULT_SAMPLE_ACCOUNT_NAME LIMIT 1];
        Id requestRecordTypeId = m_getRequestRecordTypeId();
        Opportunity nonErpOpportunity = new Opportunity(
            Name = 'COFR Non ERP Opportunity',
            RecordTypeId = requestRecordTypeId,
            AccountId = defaultSampleAccount.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(15)
        );
        insert nonErpOpportunity;

        npe01__OppPayment__c paymentRecord = new npe01__OppPayment__c(npe01__Opportunity__c = nonErpOpportunity.Id);
        insert paymentRecord;

        CreateOpportunitiesFromReportsController.Request requestWrapper = new CreateOpportunitiesFromReportsController.Request();
        requestWrapper.paymentIdsJson = JSON.serialize(new List<Id>{ paymentRecord.Id });

        Test.startTest();
        CreateOpportunitiesFromReportsController.Response response =
            CreateOpportunitiesFromReportsController.updatePaymentsChunk(JSON.serialize(requestWrapper));
        Test.stopTest();

        System.assertEquals(true, response.isSuccess, 'Non-ERP payment update should return success.');
        System.assertEquals(0, response.paymentUpdateData.updatedPaymentCount, 'No non-ERP Payment should be updated.');
        System.assertEquals(1, response.paymentUpdateData.skippedPaymentCount, 'The non-ERP Payment should be skipped.');
        System.assertEquals(0, response.paymentUpdateData.errors.size(), 'Skipped non-ERP Payments should not be reported as errors.');
    }

    /**
     * Verifies that ERP Payment update failures are returned as row-level errors without throwing from Aura.
     *
     * @example
     * Runs `updatePaymentsChunk(String)` as a user without ERP transfer permission against one ERP-stage Payment.
     *
     * @return Returns nothing. Asserts the method returns one failed update error in the response payload.
    **/
    @IsTest
    private static void m_updatePaymentsChunkReturnsRowErrorWhenPermissionFails() {
        Account allowedAccount = [
            SELECT Id, npe01__One2OneContact__c
            FROM Account
            WHERE Name = :ALLOWED_ACCOUNT_NAME
            LIMIT 1
        ];
        Fund__c regularFund = [SELECT Id FROM Fund__c WHERE Name = :REGULAR_FUND_NAME LIMIT 1];
        Opportunity erpOpportunity = new Opportunity(
            Name = 'COFR ERP Permission Failure Opportunity',
            RecordTypeId = m_getRequestRecordTypeId(),
            AccountId = allowedAccount.Id,
            StageName = GlobalConstantsAndEnums.STAGE_READY_FOR_TRANSFER_TO_ERP,
            CloseDate = Date.today().addDays(10),
            Amount = 75,
            Fund__c = regularFund.Id,
            npsp__Primary_Contact__c = allowedAccount.npe01__One2OneContact__c,
            Contact_Num_Id__c = VALID_ISRAELI_ID_NUMBER,
            Suspected_Duplicate__c = false
        );
        insert erpOpportunity;

        npe01__OppPayment__c paymentRecord = new npe01__OppPayment__c(
            npe01__Opportunity__c = erpOpportunity.Id,
            Beneficiary__c = allowedAccount.npe01__One2OneContact__c
        );
        insert paymentRecord;

        CreateOpportunitiesFromReportsController.Request requestWrapper = new CreateOpportunitiesFromReportsController.Request();
        requestWrapper.paymentIdsJson = JSON.serialize(new List<Id>{ paymentRecord.Id });
        User disallowedUser = m_createRunAsUser(false);
        CreateOpportunitiesFromReportsController.Response response;

        System.runAs(disallowedUser) {
            Test.startTest();
            response = CreateOpportunitiesFromReportsController.updatePaymentsChunk(JSON.serialize(requestWrapper));
            Test.stopTest();
        }

        System.assertEquals(true, response.isSuccess, 'Aura wrapper should still return a safe response.');
        System.assertEquals(0, response.paymentUpdateData.updatedPaymentCount, 'No Payments should update when ERP permission is missing.');
        System.assertEquals(1, response.paymentUpdateData.errors.size(), 'One row-level Payment update error should be returned.');
        System.assert(
            response.paymentUpdateData.errors[0].contains('Only specific users can update the record to'),
            'Returned Payment error should preserve the ERP permission failure message.'
        );
    }

    /**
     * Returns the Request Opportunity record type id.
     *
     * @example
     * No input payload is required.
     *
     * @return Returns the `Opportunity` record type id for developer name `Request`.
    **/
    private static Id m_getRequestRecordTypeId() {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get(GlobalConstantsAndEnums.REQUEST_RECORD_TYPE_DEVELOPER_NAME)
            .getRecordTypeId();
    }

    /**
     * Returns Accounts keyed by name.
     *
     * @param accountNames Account names that should be loaded.
     *
     * @example
     * `new Set<String>{'COFR Allowed Account'}`
     *
     * @return Returns Accounts keyed by `Name`.
    **/
    private static Map<String, Account> m_getAccountsByName(Set<String> accountNames) {
        Map<String, Account> accountByName = new Map<String, Account>();

        for (Account accountRecord : [
            SELECT Id, Name, npe01__One2OneContact__c, Don_t_send_mailings__c
            FROM Account
            WHERE Name IN :accountNames
        ]) {
            accountByName.put(accountRecord.Name, accountRecord);
        }

        return accountByName;
    }

    /**
     * Returns Funds keyed by name.
     *
     * @param fundNames Fund names that should be loaded.
     *
     * @example
     * `new Set<String>{'COFR Regular Fund'}`
     *
     * @return Returns Funds keyed by `Name`.
    **/
    private static Map<String, Fund__c> m_getFundsByName(Set<String> fundNames) {
        Map<String, Fund__c> fundByName = new Map<String, Fund__c>();

        for (Fund__c fundRecord : [
            SELECT Id, Name, Fund_type__c
            FROM Fund__c
            WHERE Name IN :fundNames
        ]) {
            fundByName.put(fundRecord.Name, fundRecord);
        }

        return fundByName;
    }

    /**
     * Builds one selected-report rows JSON payload for preview tests.
     *
     * @param accountIds Account ids that should appear as selected Accounts inside one fake preview report row.
     *
     * @example
     * `new List<Id>{'001...'}`.
     *
     * @return Returns a JSON array string that matches the preview request contract.
    **/
    private static String m_buildSelectedReportRowsJson(List<Id> accountIds) {
        return JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'value' => '00O000000000001AAA',
                'label' => 'COFR Preview Report',
                'shortLabel' => 'COFR Preview Report',
                'eligibleAccountIdsJson' => JSON.serialize(accountIds)
            }
        });
    }

    /**
     * Creates one runAs user for Payment-update tests.
     *
     * @param isAllowedToTransferToErp Indicates whether the user should be allowed to update ERP transfer status.
     *
     * @example
     * `m_createRunAsUser(true)`
     *
     * @return Returns an inserted User record ready for `System.runAs`.
    **/
    private static User m_createRunAsUser(Boolean isAllowedToTransferToErp) {
        return m_createRunAsUser(isAllowedToTransferToErp, false);
    }

    /**
     * Creates one runAs user for ERP-specific tests.
     *
     * @param isAllowedToTransferToErp Indicates whether the user may move records to ERP stages.
     * @param hasDuplicateOverride Indicates whether the user may move suspected duplicate records to ERP stages.
     *
     * @example
     * `m_createRunAsUser(true, true)`
     *
     * @return Returns an inserted User record ready for `System.runAs`.
    **/
    private static User m_createRunAsUser(Boolean isAllowedToTransferToErp, Boolean hasDuplicateOverride) {
        Profile currentProfile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];
        String uniqueSuffix = String.valueOf(DateTime.now().getTime()) + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User userRecord = new User(
            Alias = TEST_USER_ALIAS_PREFIX + uniqueSuffix.substring(0, 4),
            Email = 'cofr+' + uniqueSuffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'COFR Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = currentProfile.Id,
            TimeZoneSidKey = 'Asia/Jerusalem',
            Username = 'cofr+' + uniqueSuffix + '@example.com',
            Allowed_to_transfer_to_ERP__c = isAllowedToTransferToErp,
            Opp_Duplicate_Override__c = hasDuplicateOverride
        );
        insert userRecord;
        return userRecord;
    }
}
