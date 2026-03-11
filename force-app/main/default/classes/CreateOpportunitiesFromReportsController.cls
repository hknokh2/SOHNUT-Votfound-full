/**
@author: Haim Knokh
@date: 2026-03-08
@modified: 2026-03-11
@description: Standalone wizard controller for the Create Opportunities From Reports modal.
*
* Architecture Role
* =========================
* This controller serves the full Create Opportunities From Reports wizard:
*   - load available reports without expensive bulk report execution
*   - retrieve account counters for one selected report at a time
*   - build preview rows for the selected reports and Accounts before creation
*   - resolve preview lookup field ids into record names before the approval step renders
*   - create Request Opportunities chunk-by-chunk from the final preview selection
*   - refresh just-created Opportunity chunks to read the final Opportunity names and already-created NPSP Payments
*   - update found Payments for ERP-ready Opportunities
*   - return normalized report rows for the modal datatable
*
* Main Object Links And Data Flow
* =========================
* The controller reads:
*   - `Report`
*   - `Account`
*   - `Opportunity`
*   - `npe01__OppPayment__c`
*
* The controller returns:
*   - lazy report rows for the initial table
*   - refreshed per-report row data after one report scan
*
* Runtime Constraints And Why This Implementation Exists
* =========================
* Reports are not executed during the initial list load because some reports exceed Analytics row limits
* or CPU limits when scanned in bulk. The modal therefore loads only report headers first and retrieves
* counters one report at a time after explicit user action. Preview filtering is executed in Apex because
* existing Opportunity checks must be evaluated against org data with the final shared Opportunity field values.
* The supplemental rehabilitation grant ERP-stage block therefore runs only after the user-entered `Fund__c`
* value is known, not during the initial report scan.
* Final creation runs in LWC-driven chunks instead of Batch so the UI can show live progress, allow client-side
* abort of future chunks, keep Opportunity creation and delayed Payment refresh/update in separate client-managed
* queues, and update only the Payments that already exist by the time each created chunk is refreshed.
*
* Important Contract Caveats
* =========================
* All user-facing labels are resolved in LWC constants, not in Apex or Custom Labels.
*
* Final Opportunity Creation Rules
* =========================
* For every selected preview `Account`, this controller creates one `Opportunity` and applies:
*   - shared base field values from the step-3 `preparedOpportunityJson` payload;
*   - one generated Request-style `Name`;
*   - fallback defaults for missing required fields that are not present in the step-3 field set;
*   - `npsp__Primary_Contact__c = Account.npe01__One2OneContact__c`;
*   - `npsp__Requested_Amount__c = Opportunity.Amount` when `Amount` is populated, otherwise `null`.
*
* Supplemental Fund ERP Filter Rules
* =========================
* Existing ERP-stage Request Opportunities are not checked during step 1 report retrieval.
* That duplicate-block rule is evaluated only during preview, after the user-entered shared Opportunity values are known.
* The block is applied only when:
*   - `Fund__c` is present in the configured Request field set;
*   - the user entered a `Fund__c` value on step 3;
*   - the selected Fund has `Fund_type__c = המענק השיקומי המשלים`.
*
* When that condition is met, Accounts that already have a Request Opportunity in either of these stages are removed from preview:
*   - `Ready for transfer to ERP`
*   - `Transferred to ERP`
*
* If `Fund__c` is absent from the field set, blank, or points to any other fund type, this ERP-stage duplicate block is skipped completely.
*
* Payment Refresh And Update Rules
* =========================
* This controller never creates `npe01__OppPayment__c` records itself.
* It only refreshes already-created Payments and updates them when:
*   - the related Payment already exists in org automation output;
*   - the related `Opportunity` exists;
*   - the related `Opportunity.StageName = Ready for transfer to ERP`.
*
* When those conditions are met, the controller updates only:
*   - `npe01__OppPayment__c.ERP_Status__c = Opportunity.StageName`;
*   - `npe01__OppPayment__c.npe01__Payment_Amount__c = Opportunity.Amount`.
*
* If a related Payment does not exist, the controller skips the Payment update without throwing an error.
**/
public with sharing class CreateOpportunitiesFromReportsController {

    // -------------------------------
    // Constants
    // -------------------------------

    /** Account key prefix used to identify Account IDs inside Analytics API row values. */
    private static final String ACCOUNT_KEY_PREFIX = Account.SObjectType.getDescribe().getKeyPrefix();

    /** Report type returned by Analytics API for Account reports. */
    private static final String REPORT_TYPE_ACCOUNT_LIST = 'AccountList';

    /** Strategy API name that creates a new Opportunity only when no matching one exists. */
    private static final String CREATION_STRATEGY_MATCH_SELECTED_FIELDS = 'matchSelectedFields';

    /** Opportunity field set used to render the custom step-3 Request form. */
    private static final String REQUEST_OPPORTUNITY_FIELD_SET_NAME = 'Create_Opportunity_From_Reports_New_Opp';

    /** Maximum number of detailed Opportunity-evaluation samples written to the debug log per preview run. */
    private static final Integer DEBUG_EVALUATION_SAMPLE_LIMIT = 25;

    /** Maximum number of preview Accounts with existing Request Opportunities written to the debug log per run. */
    private static final Integer DEBUG_PREVIEW_ACCOUNT_SAMPLE_LIMIT = 10;

    /** Maximum number of existing Request Opportunities logged per sampled Account. */
    private static final Integer DEBUG_PREVIEW_OPPORTUNITY_SAMPLE_PER_ACCOUNT_LIMIT = 3;

    /** Name prefix used for automatically generated Request Opportunity names. */
    private static final String REQUEST_OPPORTUNITY_NAME_PREFIX = 'Request Opportunity ';

    /** Opportunity field API name populated from Account one-to-one contact during final creation. */
    private static final String PRIMARY_CONTACT_FIELD_API_NAME = 'npsp__Primary_Contact__c';

    /** Opportunity field API name that mirrors the entered Amount during final creation. */
    private static final String REQUESTED_AMOUNT_FIELD_API_NAME = 'npsp__Requested_Amount__c';

    /** Opportunity lookup field API name that stores the selected Fund on the wizard form. */
    private static final String FUND_LOOKUP_FIELD_API_NAME = 'Fund__c';

    /** Opportunity field API name that controls how many NPSP Payments should be generated automatically. */
    private static final String NUMBER_OF_PAYMENTS_FIELD_API_NAME = 'npe01__Number_of_Payments__c';

    /** Opportunity field API name that disables automatic NPSP Payment creation when set to true. */
    private static final String DO_NOT_AUTO_CREATE_PAYMENT_FIELD_API_NAME = 'npe01__Do_Not_Automatically_Create_Payment__c';

    /** Account field API name that stores the NPSP one-to-one contact. */
    private static final String ONE_TO_ONE_CONTACT_FIELD_API_NAME = 'npe01__One2OneContact__c';

    /** Maximum number of recent Request Opportunities sampled when deriving fallback defaults for missing required fields. */
    private static final Integer REQUEST_DEFAULT_SAMPLE_LIMIT = 1;

    /** Maximum number of sampled execution rows written to debug during create/refresh flows. */
    private static final Integer DEBUG_EXECUTION_ROW_SAMPLE_LIMIT = 15;

    /** Maximum number of sampled Opportunity-create input records written to debug per chunk. */
    private static final Integer DEBUG_CREATE_INPUT_SAMPLE_LIMIT = 10;

    /** Maximum number of sampled Payment-update records written to debug per chunk. */
    private static final Integer DEBUG_PAYMENT_UPDATE_SAMPLE_LIMIT = 10;

    /** Successful execution-row status literal used by the final Done table. */
    private static final String EXECUTION_STATUS_SUCCESS = 'success';

    /** Failed Opportunity-create execution-row status literal used by the final Done table. */
    private static final String EXECUTION_STATUS_FAILED_TO_CREATE_OPPORTUNITY = 'failedToCreateOpportunity';

    /** Failed Payment-update execution-row status literal used by the final Done table. */
    private static final String EXECUTION_STATUS_FAILED_TO_UPDATE_PAYMENT = 'failedToUpdatePayment';

    // -------------------------------
    // Instance Variables
    // -------------------------------

    /**
     * Test-only synthetic report definitions keyed by fake Report Id.
     * These stubs are used to cover report-selection and retrieval logic without SeeAllData access to real Analytics reports.
    **/
    @TestVisible
    private static Map<String, TestReportDefinition> testReportDefinitionsById = new Map<String, TestReportDefinition>();

    // -------------------------------
    // Public Methods
    // -------------------------------

    /**
     * Loads the initial report rows for step 1 without calculating account counters.
     *
     * @example
     * No input payload is required.
     *
     * @return Returns `Response` with:
     *   - `isSuccess: Boolean` - true when the report list loaded successfully.
     *   - `errorMessage: String` - load error message when the operation fails.
     *   - `availableReports: List<SelectorOption>` - initial datatable rows with empty counters.
    **/
    @AuraEnabled(cacheable=false)
    public static Response getSelectorData() {
        System.debug('getSelectorData started');
        Response response = new Response();

        try {
            response.availableReports = m_getAvailableReports();
            response.isSuccess = true;
            response.errorMessage = '';
        } catch (Exception ex) {
            System.debug('CreateOpportunitiesFromReportsController.getSelectorData exception=' + ex.getMessage());
            response.isSuccess = false;
            response.errorMessage = ex.getMessage();
        }

        return response;
    }

    /**
     * Loads server-driven modal configuration used by the client wizard.
     *
     * @example
     * No input payload is required.
     *
     * @return Returns `Response` with:
     *   - `isSuccess: Boolean` - true when the config loaded successfully.
     *   - `errorMessage: String` - load error message when the operation fails.
     *   - `config: Config` - server-driven modal config with:
     *     - `requestRecordTypeDeveloperName: String` - Opportunity Request record type developer name.
     *     - `requestRecordTypeId: Id` - Opportunity Request record type Id.
     *     - `additionalStageValues: List<String>` - extra StageName values forced into the LWC form.
     *     - `requestFieldSetFields: List<FieldConfig>` - Opportunity field descriptors rendered on step 3 in field-set order.
     *     - `requestStageOptions: List<OptionConfig>` - StageName options rendered by the custom step-3 combobox.
    **/
    @AuraEnabled(cacheable=false)
    public static Response getConfig() {
        System.debug('getConfig started');
        Response response = new Response();

        try {
            response.config = new Config();
            response.config.requestRecordTypeDeveloperName = GlobalConstantsAndEnums.REQUEST_RECORD_TYPE_DEVELOPER_NAME;
            response.config.requestRecordTypeId = m_getRequestRecordTypeId();
            response.config.additionalStageValues = new List<String>{
                GlobalConstantsAndEnums.STAGE_READY_FOR_TRANSFER_TO_ERP,
                GlobalConstantsAndEnums.STAGE_TRANSFERRED_TO_ERP
            };
            response.config.requestFieldSetFields = m_getRequestFieldSetFields();
            response.config.requestStageOptions = m_getRequestStageOptions();
            response.isSuccess = true;
            response.errorMessage = '';
        } catch (Exception ex) {
            System.debug('CreateOpportunitiesFromReportsController.getConfig exception=' + ex.getMessage());
            response.isSuccess = false;
            response.errorMessage = ex.getMessage();
        }

        return response;
    }

    /**
     * Resolves preview-step lookup ids into record names and target object API names.
     *
     * @param request A valid JSON string in the following format:
     * `{"lookupFieldValueEntriesJson":"[{\"fieldApiName\":\"Fund__c\",\"recordId\":\"a0U...\"},{\"fieldApiName\":\"CampaignId\",\"recordId\":\"701...\"}]"}`
     *
     * request fields:
     *   - `lookupFieldValueEntriesJson: string` - JSON array of preview lookup entries, each containing:
     *     - `fieldApiName: string` - Opportunity lookup field API name rendered in the preview panel.
     *     - `recordId: string` - selected lookup record Id that should be displayed by name.
     *
     * @example
     * `{"lookupFieldValueEntriesJson":"[{\"fieldApiName\":\"Fund__c\",\"recordId\":\"a0Uxx0000000001AAA\"}]"}`
     *
     * @return Returns `Response` with:
     *   - `isSuccess: Boolean` - true when the lookup display values loaded successfully.
     *   - `errorMessage: String` - lookup-load error message when the operation fails.
     *   - `lookupDisplayValues: List<LookupDisplayValue>` - resolved preview lookup values, each containing:
     *     - `fieldApiName: String` - Opportunity lookup field API name.
     *     - `recordId: String` - resolved lookup record Id.
     *     - `recordName: String` - display name shown in the preview panel.
     *     - `recordApiName: String` - target object API name used to build the record URL.
    **/
    @AuraEnabled(cacheable=false)
    public static Response resolvePreviewLookupDisplayValues(String request) {
        System.debug('resolvePreviewLookupDisplayValues started - request=' + JSON.serializePretty(JSON.deserializeUntyped(request)));
        Response response = new Response();

        try {
            Request requestWrapper = (Request)JSON.deserialize(request, Request.class);
            response.lookupDisplayValues = m_resolvePreviewLookupDisplayValues(requestWrapper.lookupFieldValueEntriesJson);
            response.isSuccess = true;
            response.errorMessage = '';
        } catch (Exception ex) {
            System.debug('CreateOpportunitiesFromReportsController.resolvePreviewLookupDisplayValues exception=' + ex.getMessage());
            response.isSuccess = false;
            response.errorMessage = ex.getMessage();
        }

        return response;
    }

    /**
     * Calculates counters for one selected report.
     *
     * @param request A valid JSON string in the following format:
     * `{"reportId":"00Oxx0000000001AAA"}`
     *
     * request fields:
     *   - `reportId: string` - Salesforce Report Id selected in the modal datatable.
     *
     * @example
     * `{"reportId":"00Oxx0000000001AAA"}`
     *
     * @return Returns `Response` with:
     *   - `isSuccess: Boolean` - true when the report scan succeeded.
     *   - `errorMessage: String` - scan error message when the operation fails.
     *   - `isSupportedReport: Boolean` - mirrors `reportData.isSupportedType` for backward compatibility.
     *   - `reportData: SelectorOption` - refreshed datatable row with type and counters for the scanned report.
    **/
    @AuraEnabled(cacheable=false)
    public static Response retrieveReportAccounts(String request) {
        System.debug('retrieveReportAccounts started - request=' + JSON.serializePretty(JSON.deserializeUntyped(request)));
        Response response = new Response();

        try {
            Request requestWrapper = (Request)JSON.deserialize(request, Request.class);
            response.reportData = m_getReportData(requestWrapper.reportId);
            response.isSupportedReport = response.reportData.isSupportedType != false;
            response.isSuccess = true;
            response.errorMessage = '';
        } catch (Exception ex) {
            System.debug('CreateOpportunitiesFromReportsController.retrieveReportAccounts exception=' + ex.getMessage());
            response.isSuccess = false;
            response.errorMessage = ex.getMessage();
            response.isSupportedReport = false;
        }

        return response;
    }

    /**
     * Builds the preview data for the approval step without creating any records.
     *
     * @param request A valid JSON string in the following format:
     * `{"selectedReportRowsJson":"[{\"value\":\"00O...\",\"shortLabel\":\"Open Requests\",\"eligibleAccountIdsJson\":\"[\\\"001...\\\"]\"}]","creationStrategy":"matchSelectedFields","comparisonConditionsJson":"[{\"rowNumber\":1,\"fieldApiName\":\"StageName\",\"operator\":\"equals\",\"value\":\"New\"}]","comparisonFormulaText":"1","opportunityFieldValuesJson":"{\"RecordTypeId\":\"012...\",\"StageName\":\"New\"}"}`
     *
     * request fields:
     *   - `selectedReportRowsJson: string` - JSON array of selected report rows with report ids, names, and eligible Account ids.
     *   - `creationStrategy: string` - selected creation strategy API name.
     *   - `comparisonConditionsJson: string` - JSON array with up to five numbered duplicate-filter conditions.
     *   - `comparisonFormulaText: string` - boolean formula that combines the numbered duplicate-filter conditions.
     *   - `opportunityFieldValuesJson: string` - JSON object with the prepared shared Opportunity field values.
     *
     * @example
     * `{"selectedReportRowsJson":"[{\"value\":\"00O...\",\"shortLabel\":\"Open Requests\",\"eligibleAccountIdsJson\":\"[\\\"001...\\\"]\"}]","creationStrategy":"createAlways","comparisonConditionsJson":"[]","comparisonFormulaText":"","opportunityFieldValuesJson":"{\"RecordTypeId\":\"012...\",\"StageName\":\"New\"}"}`
     *
     * @return Returns `Response` with:
     *   - `isSuccess: Boolean` - true when the preview loaded successfully.
     *   - `errorMessage: String` - preview error message when the operation fails.
     *   - `previewData: PreviewData` - preview payload with:
     *     - `opportunityCount: Integer` - number of Opportunities that would be created.
     *     - `accountCount: Integer` - number of Accounts that would receive Opportunities.
     *     - `accountIdsJson: String` - JSON array of Account ids that remain after preview filtering.
     *     - `previewRows: List<PreviewRow>` - preview rows with report and Account names and ids.
    **/
    @AuraEnabled(cacheable=false)
    public static Response getPreviewData(String request) {
        System.debug('getPreviewData started - request=' + JSON.serializePretty(JSON.deserializeUntyped(request)));
        Response response = new Response();

        try {
            Request requestWrapper = (Request)JSON.deserialize(request, Request.class);
            response.previewData = m_getPreviewData(requestWrapper);
            response.isSuccess = true;
            response.errorMessage = '';
        } catch (Exception ex) {
            System.debug('CreateOpportunitiesFromReportsController.getPreviewData exception=' + ex.getMessage());
            response.isSuccess = false;
            response.errorMessage = ex.getMessage();
        }

        return response;
    }

    /**
     * Creates one chunk of Request Opportunities for the selected preview Accounts.
     *
     * @param request A valid JSON string in the following format:
     * `{"accountIdsJson":"[\"001...\"]","preparedOpportunityJson":"{\"StageName\":\"New\",\"CloseDate\":\"2026-03-31\",\"Amount\":1000}"}`
     *
     * request fields:
     *   - `accountIdsJson: string` - JSON array of Account ids that should receive Opportunities in this chunk.
     *   - `preparedOpportunityJson: string` - JSON object with the shared Opportunity field values collected on step 3.
     *
     * @example
     * `{"accountIdsJson":"[\"001...\"]","preparedOpportunityJson":"{\"StageName\":\"Ready for transfer to ERP\",\"CloseDate\":\"2026-03-31\",\"Amount\":1000}"}`
     *
     * @return Returns `Response` with:
     *   - `isSuccess: Boolean` - true when the chunk was processed successfully at controller level.
     *   - `errorMessage: String` - chunk-level fatal error message when the operation fails before row-level processing completes.
     *   - `creationChunkData: CreationChunkData` - create result payload with:
     *     - `requestedAccountCount: Integer` - number of Account ids received in the chunk.
     *     - `createdOpportunityCount: Integer` - number of Opportunities inserted successfully.
     *     - `failedAccountCount: Integer` - number of Accounts that failed Opportunity creation in this chunk.
     *     - `createdOpportunityIdsJson: String` - JSON array of successfully created Opportunity ids.
     *     - `rows: List<ExecutionRow>` - created rows with Opportunity and Account ids/names.
     *     - `errors: List<String>` - row-level create errors collected for this chunk.
     *
     * Applied field rules:
     *   - shared Opportunity fields come from `preparedOpportunityJson`;
     *   - `Name` is always replaced with one generated Request Opportunity name per created row;
     *   - missing required fields outside the configured field set are filled from org-derived fallback defaults;
     *   - `npsp__Primary_Contact__c` is copied from `Account.npe01__One2OneContact__c`;
     *   - `npsp__Requested_Amount__c` mirrors the final `Amount` value when present, otherwise stays `null`.
    **/
    @AuraEnabled(cacheable=false)
    public static Response createOpportunitiesChunk(String request) {
        System.debug('createOpportunitiesChunk started - request=' + JSON.serializePretty(JSON.deserializeUntyped(request)));
        Response response = new Response();

        try {
            Request requestWrapper = (Request)JSON.deserialize(request, Request.class);
            response.creationChunkData = m_createOpportunitiesChunk(requestWrapper);
            response.isSuccess = true;
            response.errorMessage = '';
            System.debug(
                'createOpportunitiesChunk completed - createdOpportunityCount=' + response.creationChunkData.createdOpportunityCount +
                ', failedAccountCount=' + response.creationChunkData.failedAccountCount +
                ', errorCount=' + response.creationChunkData.errors.size()
            );
        } catch (Exception ex) {
            System.debug('CreateOpportunitiesFromReportsController.createOpportunitiesChunk exception=' + ex.getMessage());
            response.isSuccess = false;
            response.errorMessage = ex.getMessage();
        }

        return response;
    }

    /**
     * Refreshes one set of newly inserted Opportunities and returns their current names and related Payments.
     *
     * @param request A valid JSON string in the following format:
     * `{"opportunityIdsJson":"[\"006...\"]"}`
     *
     * request fields:
     *   - `opportunityIdsJson: string` - JSON array of Opportunity ids whose related Payments should be checked.
     *
     * @example
     * `{"opportunityIdsJson":"[\"006...\",\"006...\"]"}`
     *
     * @return Returns `Response` with:
     *   - `isSuccess: Boolean` - true when the chunk refresh completed successfully.
     *   - `errorMessage: String` - refresh error message when the operation fails.
     *   - `refreshChunkData: RefreshChunkData` - refresh payload with:
     *     - `requestedOpportunityCount: Integer` - number of Opportunity ids refreshed.
     *     - `foundPaymentCount: Integer` - number of related Payments found for the refreshed chunk.
     *     - `foundPaymentIdsJson: String` - JSON array of found Payment ids.
     *     - `rows: List<ExecutionRow>` - execution rows enriched with the latest Opportunity and Payment names.
    **/
    @AuraEnabled(cacheable=false)
    public static Response refreshCreatedOpportunityChunk(String request) {
        System.debug('refreshCreatedOpportunityChunk started - request=' + JSON.serializePretty(JSON.deserializeUntyped(request)));
        Response response = new Response();

        try {
            Request requestWrapper = (Request)JSON.deserialize(request, Request.class);
            response.refreshChunkData = m_refreshCreatedOpportunityChunk(requestWrapper);
            response.isSuccess = true;
            response.errorMessage = '';
            System.debug(
                'refreshCreatedOpportunityChunk completed - foundPaymentCount=' + response.refreshChunkData.foundPaymentCount +
                ', requestedOpportunityCount=' + response.refreshChunkData.requestedOpportunityCount
            );
        } catch (Exception ex) {
            System.debug('CreateOpportunitiesFromReportsController.refreshCreatedOpportunityChunk exception=' + ex.getMessage());
            response.isSuccess = false;
            response.errorMessage = ex.getMessage();
        }

        return response;
    }

    /**
     * Updates one chunk of found Payments from their related Opportunity values.
     *
     * @param request A valid JSON string in the following format:
     * `{"paymentIdsJson":"[\"a01...\"]"}`
     *
     * request fields:
     *   - `paymentIdsJson: string` - JSON array of Payment ids that should receive ERP field updates.
     *
     * @example
     * `{"paymentIdsJson":"[\"a01...\",\"a01...\"]"}`
     *
     * @return Returns `Response` with:
     *   - `isSuccess: Boolean` - true when the payment-update chunk completed successfully.
     *   - `errorMessage: String` - update error message when the operation fails.
     *   - `paymentUpdateData: PaymentUpdateData` - update payload with:
     *     - `requestedPaymentCount: Integer` - number of Payment ids received in the chunk.
     *     - `updatedPaymentCount: Integer` - number of Payments updated successfully.
     *     - `skippedPaymentCount: Integer` - number of requested Payment ids that could not be updated.
     *     - `updatedPaymentIdsJson: String` - JSON array of updated Payment ids.
     *     - `errors: List<String>` - row-level payment update errors for this chunk.
     *
     * Applied field rules:
     *   - only Payments whose related `Opportunity.StageName = Ready for transfer to ERP` are updated;
     *   - `ERP_Status__c` is set from the related `Opportunity.StageName`;
     *   - `npe01__Payment_Amount__c` is set from the related `Opportunity.Amount`;
     *   - when a related Payment does not exist, the controller skips update without creating a Payment.
    **/
    @AuraEnabled(cacheable=false)
    public static Response updatePaymentsChunk(String request) {
        System.debug('updatePaymentsChunk started - request=' + JSON.serializePretty(JSON.deserializeUntyped(request)));
        Response response = new Response();

        try {
            Request requestWrapper = (Request)JSON.deserialize(request, Request.class);
            response.paymentUpdateData = m_updatePaymentsChunk(requestWrapper);
            response.isSuccess = true;
            response.errorMessage = '';
            System.debug(
                'updatePaymentsChunk completed - updatedPaymentCount=' + response.paymentUpdateData.updatedPaymentCount +
                ', skippedPaymentCount=' + response.paymentUpdateData.skippedPaymentCount +
                ', errorCount=' + response.paymentUpdateData.errors.size()
            );
        } catch (Exception ex) {
            System.debug('CreateOpportunitiesFromReportsController.updatePaymentsChunk exception=' + ex.getMessage());
            response.isSuccess = false;
            response.errorMessage = ex.getMessage();
        }

        return response;
    }

    // -------------------------------
    // Private Methods
    // -------------------------------

    /**
     * Loads the initial report rows for the modal datatable.
     *
     * @example
     * No input payload is required.
     *
     * @return Returns report rows with empty counter fields and raw report identifiers only.
    **/
    private static List<SelectorOption> m_getAvailableReports() {
        List<SelectorOption> availableReports = new List<SelectorOption>();

        if (Test.isRunningTest() && !testReportDefinitionsById.isEmpty()) {
            List<String> sortedReportIds = new List<String>(testReportDefinitionsById.keySet());
            sortedReportIds.sort();

            for (String reportId : sortedReportIds) {
                TestReportDefinition reportDefinition = testReportDefinitionsById.get(reportId);

                availableReports.add(new SelectorOption(
                    reportDefinition.reportId,
                    String.isBlank(reportDefinition.folderName)
                        ? reportDefinition.reportName
                        : reportDefinition.reportName + ' (' + reportDefinition.folderName + ')',
                    reportDefinition.reportName,
                    null,
                    null,
                    null,
                    '[]',
                    '[]',
                    null
                ));
            }

            return availableReports;
        }

        for (Report reportRecord : [
            SELECT Id, Name, FolderName, Format
            FROM Report
            WHERE Format != 'MultiBlock'
            ORDER BY Name
        ]) {
            availableReports.add(new SelectorOption(
                reportRecord.Id,
                String.isBlank(reportRecord.FolderName)
                    ? reportRecord.Name
                    : reportRecord.Name + ' (' + reportRecord.FolderName + ')',
                reportRecord.Name,
                null,
                null,
                null,
                '[]',
                '[]',
                null
            ));
        }

        return availableReports;
    }

    /**
     * Retrieves the complete first-step row data for one report.
     *
     * @param reportId Salesforce Report Id selected in the modal.
     *
     * @example
     * `00Oxx0000000001AAA`
     *
     * @return Returns one `SelectorOption` with:
     *   - `value: String` - report Id.
     *   - `label: String` - display label with folder suffix when present.
     *   - `shortLabel: String` - plain report name.
     *   - `reportType: String` - raw report type value.
     *   - `accountCount: Integer` - number of unique Accounts found in the report.
     *   - `eligibleAccountCount: Integer` - number of Accounts that remain eligible after first-step extraction and mailing filtering only.
     *   - `accountIdsJson: String` - JSON array of all unique Account Ids.
     *   - `eligibleAccountIdsJson: String` - JSON array of eligible Account Ids.
     *   - `isSupportedType: Boolean` - false when the report should remain visible but disabled in the modal.
    **/
    private static SelectorOption m_getReportData(String reportId) {
        if (Test.isRunningTest() && testReportDefinitionsById.containsKey(reportId)) {
            TestReportDefinition reportDefinition = testReportDefinitionsById.get(reportId);
            ReportTypeDescriptor reportTypeDescriptor = m_getReportTypeDescriptor(reportDefinition.reportId);
            Set<Id> extractedAccountIds = new Set<Id>();
            Set<Id> eligibleAccountIds = new Set<Id>();

            if (reportTypeDescriptor.isSupportedType) {
                ReportExtractionResult extractionResult = m_extractAccountIdsFromReport(
                    reportDefinition.reportId,
                    reportDefinition.reportName,
                    reportTypeDescriptor.reportType
                );
                Set<Id> mailAllowedAccountIds = new Set<Id>();

                extractedAccountIds.addAll(extractionResult.accountIds);

                if (!extractionResult.accountIds.isEmpty()) {
                    for (Account accountRecord : [
                        SELECT Id, Don_t_send_mailings__c
                        FROM Account
                        WHERE Id IN :extractionResult.accountIds
                    ]) {
                        if (!accountRecord.Don_t_send_mailings__c) {
                            mailAllowedAccountIds.add(accountRecord.Id);
                        }
                    }
                }

                for (Id accountId : extractionResult.accountIds) {
                    if (mailAllowedAccountIds.contains(accountId)) {
                        eligibleAccountIds.add(accountId);
                    }
                }
            }

            return new SelectorOption(
                reportDefinition.reportId,
                String.isBlank(reportDefinition.folderName)
                    ? reportDefinition.reportName
                    : reportDefinition.reportName + ' (' + reportDefinition.folderName + ')',
                reportDefinition.reportName,
                reportTypeDescriptor.reportType,
                extractedAccountIds.size(),
                eligibleAccountIds.size(),
                JSON.serialize(new List<Id>(extractedAccountIds)),
                JSON.serialize(new List<Id>(eligibleAccountIds)),
                reportTypeDescriptor.isSupportedType
            );
        }

        Report reportRecord = [
            SELECT Id, Name, FolderName
            FROM Report
            WHERE Id = :reportId
            LIMIT 1
        ];
        ReportTypeDescriptor reportTypeDescriptor = m_getReportTypeDescriptor(reportRecord.Id);
        Set<Id> extractedAccountIds = new Set<Id>();
        Set<Id> eligibleAccountIds = new Set<Id>();

        if (reportTypeDescriptor.isSupportedType) {
            ReportExtractionResult extractionResult = m_extractAccountIdsFromReport(
                reportRecord.Id,
                reportRecord.Name,
                reportTypeDescriptor.reportType
            );
            Set<Id> mailAllowedAccountIds = new Set<Id>();

            extractedAccountIds.addAll(extractionResult.accountIds);

            if (!extractionResult.accountIds.isEmpty()) {
                for (Account accountRecord : [
                    SELECT Id, Don_t_send_mailings__c
                    FROM Account
                    WHERE Id IN :extractionResult.accountIds
                ]) {
                    if (!accountRecord.Don_t_send_mailings__c) {
                        mailAllowedAccountIds.add(accountRecord.Id);
                    }
                }
            }

            for (Id accountId : extractionResult.accountIds) {
                if (mailAllowedAccountIds.contains(accountId)) {
                    eligibleAccountIds.add(accountId);
                }
            }
        }

        return new SelectorOption(
            reportRecord.Id,
            String.isBlank(reportRecord.FolderName)
                ? reportRecord.Name
                : reportRecord.Name + ' (' + reportRecord.FolderName + ')',
            reportRecord.Name,
            reportTypeDescriptor.reportType,
            extractedAccountIds.size(),
            eligibleAccountIds.size(),
            JSON.serialize(new List<Id>(extractedAccountIds)),
            JSON.serialize(new List<Id>(eligibleAccountIds)),
            reportTypeDescriptor.isSupportedType
        );
    }

    /**
     * Returns Accounts blocked by existing request Opportunities in ERP-related stages.
     *
     * @param accountIds Eligible Account Id candidates.
     *
     * @example
     * `["001xx0000000001AAA","001xx0000000002AAA"]`
     *
     * @return Returns Account Ids that must be excluded later in preview when the supplemental rehabilitation grant rule becomes active.
    **/
    private static Set<Id> m_getAccountsBlockedByExistingErpStage(Set<Id> accountIds) {
        Set<Id> blockedAccountIds = new Set<Id>();
        Id requestRecordTypeId = m_getRequestRecordTypeId();

        for (Opportunity opportunityRecord : [
            SELECT AccountId
            FROM Opportunity
            WHERE AccountId IN :accountIds
                AND RecordTypeId = :requestRecordTypeId
                AND StageName IN :new Set<String>{
                    GlobalConstantsAndEnums.STAGE_READY_FOR_TRANSFER_TO_ERP,
                    GlobalConstantsAndEnums.STAGE_TRANSFERRED_TO_ERP
                }
        ]) {
            blockedAccountIds.add(opportunityRecord.AccountId);
        }

        return blockedAccountIds;
    }

    /**
     * Resolves the Request Opportunity record type Id.
     *
     * @example
     * No input payload is required.
     *
     * @return Returns the `Opportunity` record type Id for developer name `Request`.
    **/
    private static Id m_getRequestRecordTypeId() {
        return Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(GlobalConstantsAndEnums.REQUEST_RECORD_TYPE_DEVELOPER_NAME)
            .getRecordTypeId();
    }

    /**
     * Returns the Opportunity field-set members rendered on the custom step-3 Request form.
     *
     * @example
     * No input payload is required.
     *
     * @return Returns Opportunity field descriptors from the configured field set in the exact admin-defined order.
    **/
    private static List<FieldConfig> m_getRequestFieldSetFields() {
        List<FieldConfig> fieldConfigs = new List<FieldConfig>();
        Schema.FieldSet requestFieldSet = Opportunity.SObjectType.getDescribe().fieldSets.getMap().get(REQUEST_OPPORTUNITY_FIELD_SET_NAME);

        if (requestFieldSet == null) {
            return fieldConfigs;
        }

        for (Schema.FieldSetMember fieldSetMember : requestFieldSet.getFields()) {
            fieldConfigs.add(
                new FieldConfig(
                    fieldSetMember.getFieldPath(),
                    fieldSetMember.getLabel(),
                    fieldSetMember.getRequired() || fieldSetMember.getDbRequired()
                )
            );
        }

        System.debug('m_getRequestFieldSetFields fieldConfigs=' + JSON.serializePretty(fieldConfigs));
        return fieldConfigs;
    }

    /**
     * Returns whether the configured Request field set contains the supplied Opportunity field API name.
     *
     * @param fieldApiName Opportunity field API name to search in the configured Request field set.
     *
     * @example
     * `Fund__c`
     *
     * @return Returns true only when the Request field set contains the supplied field API name.
    **/
    private static Boolean m_requestFieldSetContainsField(String fieldApiName) {
        if (String.isBlank(fieldApiName)) {
            return false;
        }

        Schema.FieldSet requestFieldSet = Opportunity.SObjectType.getDescribe().fieldSets.getMap().get(REQUEST_OPPORTUNITY_FIELD_SET_NAME);

        if (requestFieldSet == null) {
            return false;
        }

        for (Schema.FieldSetMember fieldSetMember : requestFieldSet.getFields()) {
            if (fieldSetMember.getFieldPath() == fieldApiName) {
                return true;
            }
        }

        return false;
    }

    /**
     * Returns whether the supplemental rehabilitation grant ERP-stage duplicate block must be applied.
     *
     * @param opportunityFieldValues Shared Opportunity values entered on step 3.
     *
     * @example
     * `{"Fund__c":"a0uN200000BW5HZIA1","StageName":"New"}`
     *
     * @return Returns true only when `Fund__c` exists in the configured field set, the user entered a Fund, and that Fund has `Fund_type__c = המענק השיקומי המשלים`.
    **/
    private static Boolean m_shouldApplySupplementalRehabilitationGrantErpBlock(Map<String, Object> opportunityFieldValues) {
        if (
            opportunityFieldValues == null ||
            !m_requestFieldSetContainsField(FUND_LOOKUP_FIELD_API_NAME) ||
            !opportunityFieldValues.containsKey(FUND_LOOKUP_FIELD_API_NAME) ||
            opportunityFieldValues.get(FUND_LOOKUP_FIELD_API_NAME) == null
        ) {
            System.debug('m_shouldApplySupplementalRehabilitationGrantErpBlock skipped - fund not configured or not entered');
            return false;
        }

        String fundId = String.valueOf(opportunityFieldValues.get(FUND_LOOKUP_FIELD_API_NAME));

        if (String.isBlank(fundId)) {
            System.debug('m_shouldApplySupplementalRehabilitationGrantErpBlock skipped - blank fund id');
            return false;
        }

        List<SObject> fundRecords = Database.query(
            'SELECT Id,' + GlobalConstantsAndEnums.FUND_TYPE_FIELD_API_NAME +
            ' FROM Fund__c WHERE Id = \'' + String.escapeSingleQuotes(fundId) + '\' LIMIT 1'
        );

        if (fundRecords.isEmpty()) {
            System.debug('m_shouldApplySupplementalRehabilitationGrantErpBlock skipped - fund not found for Id ' + fundId);
            return false;
        }

        String fundTypeValue = String.valueOf(fundRecords[0].get(GlobalConstantsAndEnums.FUND_TYPE_FIELD_API_NAME));
        Boolean shouldApplyBlock = fundTypeValue == GlobalConstantsAndEnums.FUND_TYPE_SUPPLEMENTAL_REHABILITATION_GRANT;

        System.debug(
            'm_shouldApplySupplementalRehabilitationGrantErpBlock fundId=' + fundId +
            ', fundType=' + fundTypeValue +
            ', shouldApplyBlock=' + shouldApplyBlock
        );
        return shouldApplyBlock;
    }

    /**
     * Returns StageName options rendered by the custom step-3 combobox.
     *
     * @example
     * No input payload is required.
     *
     * @return Returns StageName options merged from the Opportunity field describe and forced ERP stage additions.
    **/
    private static List<OptionConfig> m_getRequestStageOptions() {
        List<OptionConfig> stageOptions = new List<OptionConfig>();
        Set<String> existingStageValues = new Set<String>();

        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            stageOptions.add(new OptionConfig(picklistEntry.getLabel(), picklistEntry.getValue()));
            existingStageValues.add(picklistEntry.getValue());
        }

        for (String additionalStageValue : new List<String>{
            GlobalConstantsAndEnums.STAGE_READY_FOR_TRANSFER_TO_ERP,
            GlobalConstantsAndEnums.STAGE_TRANSFERRED_TO_ERP
        }) {
            if (!existingStageValues.contains(additionalStageValue)) {
                stageOptions.add(new OptionConfig(additionalStageValue, additionalStageValue));
            }
        }

        System.debug('m_getRequestStageOptions stageOptions=' + JSON.serializePretty(stageOptions));
        return stageOptions;
    }

    /**
     * Builds preview rows and final creatable Account ids for the approval step.
     *
     * @param requestWrapper Parsed Aura request wrapper.
     *
     * @example
     * A request wrapper may contain selected reports, up to five comparison conditions, one comparison formula, and prepared Opportunity values.
     *
     * @return Returns `PreviewData` with the final Account ids and preview rows that remain after:
     *   - the supplemental rehabilitation grant ERP-stage block, when it applies;
     *   - and the duplicate-filter formula, when that strategy is selected.
    **/
    private static PreviewData m_getPreviewData(Request requestWrapper) {
        List<PreviewSelectionRow> selectedReportRows = m_parsePreviewSelectionRows(requestWrapper.selectedReportRowsJson);
        Map<String, Object> opportunityFieldValues = m_parseUntypedObjectMap(requestWrapper.opportunityFieldValuesJson);
        Map<Id, PreviewSelectionRow> sourceReportByAccountId = new Map<Id, PreviewSelectionRow>();

        System.debug('m_getPreviewData creationStrategy=' + requestWrapper.creationStrategy);
        System.debug('m_getPreviewData comparisonFormulaText=' + requestWrapper.comparisonFormulaText);
        System.debug('m_getPreviewData selectedReportRows.size=' + selectedReportRows.size());
        System.debug('m_getPreviewData opportunityFieldValuesJson=' + requestWrapper.opportunityFieldValuesJson);

        for (PreviewSelectionRow selectedReportRow : selectedReportRows) {
            for (Id accountId : m_parseIdSet(selectedReportRow.eligibleAccountIdsJson)) {
                if (!sourceReportByAccountId.containsKey(accountId)) {
                    sourceReportByAccountId.put(accountId, selectedReportRow);
                }
            }
        }

        Set<Id> creatableAccountIds = new Set<Id>(sourceReportByAccountId.keySet());
        List<ComparisonCondition> comparisonConditions = m_parseComparisonConditions(requestWrapper.comparisonConditionsJson);

        System.debug('m_getPreviewData sourceReportByAccountId.size=' + sourceReportByAccountId.size());
        System.debug('m_getPreviewData opportunityFieldValues=' + opportunityFieldValues);
        System.debug('m_getPreviewData comparisonConditions=' + m_describeComparisonConditions(comparisonConditions));

        if (
            !creatableAccountIds.isEmpty() &&
            m_shouldApplySupplementalRehabilitationGrantErpBlock(opportunityFieldValues)
        ) {
            creatableAccountIds.removeAll(m_getAccountsBlockedByExistingErpStage(creatableAccountIds));
        }

        if (
            requestWrapper.creationStrategy == CREATION_STRATEGY_MATCH_SELECTED_FIELDS &&
            !comparisonConditions.isEmpty() &&
            !creatableAccountIds.isEmpty()
        ) {
            creatableAccountIds.removeAll(
                m_getAccountsBlockedByComparisonFormula(
                    creatableAccountIds,
                    comparisonConditions,
                    requestWrapper.comparisonFormulaText
                )
            );
        }

        Map<Id, Account> accountById = creatableAccountIds.isEmpty()
            ? new Map<Id, Account>()
            : new Map<Id, Account>([
                SELECT Id, Name
                FROM Account
                WHERE Id IN :creatableAccountIds
            ]);
        List<PreviewRow> previewRows = new List<PreviewRow>();

        for (Id accountId : sourceReportByAccountId.keySet()) {
            if (!creatableAccountIds.contains(accountId) || !accountById.containsKey(accountId)) {
                continue;
            }

            PreviewSelectionRow sourceReport = sourceReportByAccountId.get(accountId);
            previewRows.add(new PreviewRow(
                sourceReport.value,
                String.isBlank(sourceReport.shortLabel) ? sourceReport.label : sourceReport.shortLabel,
                accountId,
                accountById.get(accountId).Name
            ));
        }

        previewRows.sort();
        m_logPreviewExistingOpportunitySamples(creatableAccountIds, accountById, sourceReportByAccountId);
        System.debug('m_getPreviewData creatableAccountIds.size=' + creatableAccountIds.size());
        System.debug('m_getPreviewData previewRows.size=' + previewRows.size());

        return new PreviewData(previewRows.size(), creatableAccountIds.size(), JSON.serialize(new List<Id>(creatableAccountIds)), previewRows);
    }

    /**
     * Returns Account ids that already have a matching Opportunity for the configured duplicate-filter formula.
     *
     * @param accountIds Candidate Account ids from the selected reports.
     * @param comparisonConditions Up to five duplicate-filter conditions from step 2.
     * @param comparisonFormulaText Boolean formula that combines the numbered duplicate-filter conditions.
     *
     * @example
     * `accountIds = new Set<Id>{'001...'}`, `comparisonFormulaText = '(1 AND 2) OR 3'`
     *
     * @return Returns Account ids that must be skipped because a matching Request Opportunity already exists.
    **/
    private static Set<Id> m_getAccountsBlockedByComparisonFormula(
        Set<Id> accountIds,
        List<ComparisonCondition> comparisonConditions,
        String comparisonFormulaText
    ) {
        Set<Id> blockedAccountIds = new Set<Id>();
        Map<String, Schema.SObjectField> opportunityFieldMap = Opportunity.SObjectType.getDescribe().fields.getMap();
        List<PreparedComparisonCondition> preparedComparisonConditions = new List<PreparedComparisonCondition>();
        Set<String> queriedFieldApiNames = new Set<String>();
        Integer evaluatedOpportunityCount = 0;
        Integer matchedOpportunityCount = 0;
        List<Map<String, Object>> matchedEvaluationSamples = new List<Map<String, Object>>();
        List<Map<String, Object>> unmatchedEvaluationSamples = new List<Map<String, Object>>();

        System.debug('m_getAccountsBlockedByComparisonFormula accountIds.size=' + accountIds.size());
        System.debug(
            'm_getAccountsBlockedByComparisonFormula comparisonConditions=' +
            m_describeComparisonConditions(comparisonConditions)
        );
        System.debug('m_getAccountsBlockedByComparisonFormula comparisonFormulaText=' + comparisonFormulaText);

        if (comparisonConditions.isEmpty()) {
            return blockedAccountIds;
        }

        for (ComparisonCondition comparisonCondition : comparisonConditions) {
            if (comparisonCondition == null || !opportunityFieldMap.containsKey(comparisonCondition.fieldApiName)) {
                throw new CreateOpportunitiesFromReportsControllerException('Invalid comparison condition field.');
            }

            Schema.DescribeFieldResult fieldDescribe = opportunityFieldMap.get(comparisonCondition.fieldApiName).getDescribe();
            Object castedConditionValue = m_castFieldValue(comparisonCondition.value, fieldDescribe);

            System.debug(
                'm_getAccountsBlockedByComparisonFormula preparedCondition row=' + comparisonCondition.rowNumber +
                ', field=' + comparisonCondition.fieldApiName +
                ', operator=' + comparisonCondition.operator +
                ', rawValue=' + JSON.serialize(comparisonCondition.value) +
                ', castedValue=' + JSON.serialize(castedConditionValue) +
                ', displayType=' + fieldDescribe.getType()
            );

            preparedComparisonConditions.add(new PreparedComparisonCondition(
                comparisonCondition.rowNumber,
                comparisonCondition.fieldApiName,
                comparisonCondition.operator,
                castedConditionValue,
                fieldDescribe.getType()
            ));
            queriedFieldApiNames.add(comparisonCondition.fieldApiName);
        }

        List<String> comparisonFormulaPostfixTokens = m_buildComparisonFormulaPostfix(
            comparisonFormulaText,
            comparisonConditions.size()
        );
        Id requestRecordTypeId = m_getRequestRecordTypeId();
        String queryText =
            'SELECT Id,AccountId,' + String.join(new List<String>(queriedFieldApiNames), ',') +
            ' FROM Opportunity WHERE AccountId IN :accountIds AND RecordTypeId = :requestRecordTypeId';

        System.debug('m_getAccountsBlockedByComparisonFormula comparisonFormulaPostfixTokens=' + comparisonFormulaPostfixTokens);
        System.debug('m_getAccountsBlockedByComparisonFormula queryText=' + queryText);

        for (SObject opportunityRecord : Database.query(queryText)) {
            Map<Integer, Boolean> conditionResultsByNumber = new Map<Integer, Boolean>();
            Map<String, Object> opportunityFieldValues = new Map<String, Object>();
            Map<String, Object> evaluationSample = new Map<String, Object>();

            evaluatedOpportunityCount += 1;
            evaluationSample.put('opportunityId', opportunityRecord.get('Id'));
            evaluationSample.put('accountId', opportunityRecord.get('AccountId'));

            for (PreparedComparisonCondition preparedComparisonCondition : preparedComparisonConditions) {
                Object existingFieldValue = opportunityRecord.get(preparedComparisonCondition.fieldApiName);
                Boolean conditionResult = m_evaluatePreparedComparisonCondition(
                    existingFieldValue,
                    preparedComparisonCondition
                );

                opportunityFieldValues.put(preparedComparisonCondition.fieldApiName, existingFieldValue);
                conditionResultsByNumber.put(
                    preparedComparisonCondition.rowNumber,
                    conditionResult
                );
            }

            Boolean formulaResult = m_evaluateComparisonFormula(comparisonFormulaPostfixTokens, conditionResultsByNumber);
            evaluationSample.put('opportunityFieldValues', opportunityFieldValues);
            evaluationSample.put('conditionResultsByNumber', conditionResultsByNumber);
            evaluationSample.put('formulaResult', formulaResult);

            if (formulaResult) {
                blockedAccountIds.add((Id)opportunityRecord.get('AccountId'));
                matchedOpportunityCount += 1;

                if (matchedEvaluationSamples.size() < DEBUG_EVALUATION_SAMPLE_LIMIT) {
                    matchedEvaluationSamples.add(evaluationSample);
                }
            } else if (unmatchedEvaluationSamples.size() < DEBUG_EVALUATION_SAMPLE_LIMIT) {
                unmatchedEvaluationSamples.add(evaluationSample);
            }
        }

        System.debug('m_getAccountsBlockedByComparisonFormula evaluatedOpportunityCount=' + evaluatedOpportunityCount);
        System.debug('m_getAccountsBlockedByComparisonFormula matchedOpportunityCount=' + matchedOpportunityCount);
        System.debug('m_getAccountsBlockedByComparisonFormula blockedAccountIds.size=' + blockedAccountIds.size());
        System.debug(
            'm_getAccountsBlockedByComparisonFormula matchedEvaluationSamples=' +
            m_describeEvaluationSamples(matchedEvaluationSamples)
        );
        System.debug(
            'm_getAccountsBlockedByComparisonFormula unmatchedEvaluationSamples=' +
            m_describeEvaluationSamples(unmatchedEvaluationSamples)
        );
        System.debug('m_getAccountsBlockedByComparisonFormula blockedAccountIds=' + blockedAccountIds);
        return blockedAccountIds;
    }

    /**
     * Logs sampled preview Accounts that already have existing Request Opportunities.
     *
     * @param creatableAccountIds Final Account ids that remain in the preview after all filters.
     * @param accountById Final preview Accounts keyed by Account id.
     * @param sourceReportByAccountId Source selected-report rows keyed by Account id.
     *
     * @example
     * A preview run may log up to ten Accounts and up to three existing Request Opportunities for each one.
     *
     * @return Returns nothing. Writes debug output only.
    **/
    private static void m_logPreviewExistingOpportunitySamples(
        Set<Id> creatableAccountIds,
        Map<Id, Account> accountById,
        Map<Id, PreviewSelectionRow> sourceReportByAccountId
    ) {
        if (creatableAccountIds.isEmpty()) {
            System.debug('m_logPreviewExistingOpportunitySamples skipped - no creatableAccountIds');
            return;
        }

        Id requestRecordTypeId = m_getRequestRecordTypeId();
        Map<Id, List<Opportunity>> requestOpportunitiesByAccountId = new Map<Id, List<Opportunity>>();
        Integer sampledAccountCount = 0;
        List<Map<String, Object>> previewAccountSamples = new List<Map<String, Object>>();

        for (Opportunity opportunityRecord : [
            SELECT Id, AccountId, Name, StageName, Type, Amount, CloseDate, IsPrivate, LeadSource, Probability
            FROM Opportunity
            WHERE AccountId IN :creatableAccountIds
                AND RecordTypeId = :requestRecordTypeId
            ORDER BY AccountId, LastModifiedDate DESC
        ]) {
            if (!requestOpportunitiesByAccountId.containsKey(opportunityRecord.AccountId)) {
                requestOpportunitiesByAccountId.put(opportunityRecord.AccountId, new List<Opportunity>());
            }

            if (
                requestOpportunitiesByAccountId.get(opportunityRecord.AccountId).size() <
                DEBUG_PREVIEW_OPPORTUNITY_SAMPLE_PER_ACCOUNT_LIMIT
            ) {
                requestOpportunitiesByAccountId.get(opportunityRecord.AccountId).add(opportunityRecord);
            }
        }

        for (Id accountId : requestOpportunitiesByAccountId.keySet()) {
            if (sampledAccountCount >= DEBUG_PREVIEW_ACCOUNT_SAMPLE_LIMIT || !accountById.containsKey(accountId)) {
                break;
            }

            PreviewSelectionRow sourceReport = sourceReportByAccountId.get(accountId);
            List<Map<String, Object>> opportunitySamples = new List<Map<String, Object>>();

            for (Opportunity opportunityRecord : requestOpportunitiesByAccountId.get(accountId)) {
                opportunitySamples.add(new Map<String, Object>{
                    'opportunityId' => opportunityRecord.Id,
                    'name' => opportunityRecord.Name,
                    'stageName' => opportunityRecord.StageName,
                    'type' => opportunityRecord.Type,
                    'amount' => opportunityRecord.Amount,
                    'closeDate' => opportunityRecord.CloseDate,
                    'isPrivate' => opportunityRecord.IsPrivate,
                    'leadSource' => opportunityRecord.LeadSource,
                    'probability' => opportunityRecord.Probability
                });
            }

            previewAccountSamples.add(new Map<String, Object>{
                'accountId' => accountId,
                'accountName' => accountById.get(accountId).Name,
                'sourceReportId' => sourceReport == null ? null : sourceReport.value,
                'sourceReportName' => sourceReport == null
                    ? null
                    : (String.isBlank(sourceReport.shortLabel) ? sourceReport.label : sourceReport.shortLabel),
                'existingRequestOpportunities' => opportunitySamples
            });
            sampledAccountCount += 1;
        }

        System.debug(
            'm_logPreviewExistingOpportunitySamples sampledAccountCount=' + sampledAccountCount +
            ', accountsWithExistingRequestOpportunities=' + requestOpportunitiesByAccountId.size()
        );
        System.debug(
            'm_logPreviewExistingOpportunitySamples previewAccountSamples=' +
            m_describePreviewAccountSamples(previewAccountSamples)
        );
    }

    /**
     * Casts one prepared Opportunity field value to the target Salesforce field type.
     *
     * @param rawValue Raw JSON-deserialized field value.
     * @param fieldDescribe Describe metadata for the target Opportunity field.
     *
     * @example
     * `rawValue = "2026-03-09"` for a Date field returns a `Date` value.
     *
     * @return Returns the same value converted to the field-compatible Apex type, or null when the input is blank.
    **/
    private static Object m_castFieldValue(Object rawValue, Schema.DescribeFieldResult fieldDescribe) {
        if (rawValue == null || fieldDescribe == null) {
            return null;
        }

        String valueText = String.valueOf(rawValue);

        if (String.isBlank(valueText)) {
            return null;
        }

        switch on fieldDescribe.getType() {
            when BOOLEAN {
                return rawValue instanceof Boolean ? rawValue : Boolean.valueOf(valueText);
            }
            when DATE {
                return Date.valueOf(valueText);
            }
            when DATETIME {
                String normalizedValueText = valueText.contains('T')
                    ? valueText.replace('T', ' ').replace('Z', '')
                    : valueText;

                if (normalizedValueText.contains('.')) {
                    normalizedValueText = normalizedValueText.substring(0, normalizedValueText.indexOf('.'));
                }

                return valueText.contains('T')
                    ? Datetime.valueOfGmt(normalizedValueText)
                    : Datetime.valueOf(normalizedValueText);
            }
            when INTEGER {
                return Integer.valueOf(valueText);
            }
            when LONG {
                return Long.valueOf(valueText);
            }
            when CURRENCY, DOUBLE, PERCENT {
                return Decimal.valueOf(valueText);
            }
            when else {
                return valueText;
            }
        }
    }

    /**
     * Parses the selected preview-report rows JSON.
     *
     * @param selectedReportRowsJson JSON array of selected report rows.
     *
     * @example
     * `"[{\"value\":\"00O...\",\"shortLabel\":\"Open Requests\",\"eligibleAccountIdsJson\":\"[\\\"001...\\\"]\"}]"`
     *
     * @return Returns selected preview rows with report ids, names, and eligible Account ids.
    **/
    private static List<PreviewSelectionRow> m_parsePreviewSelectionRows(String selectedReportRowsJson) {
        if (String.isBlank(selectedReportRowsJson)) {
            return new List<PreviewSelectionRow>();
        }

        return (List<PreviewSelectionRow>)JSON.deserialize(selectedReportRowsJson, List<PreviewSelectionRow>.class);
    }

    /**
     * Parses a JSON array of Salesforce ids into a Set.
     *
     * @param idsJson JSON array string with Salesforce ids.
     *
     * @example
     * `"[\"001xx0000000001AAA\",\"001xx0000000002AAA\"]"`
     *
     * @return Returns a Set of valid Salesforce ids parsed from the JSON array.
    **/
    private static Set<Id> m_parseIdSet(String idsJson) {
        Set<Id> parsedIds = new Set<Id>();

        if (String.isBlank(idsJson)) {
            return parsedIds;
        }

        for (Object idValue : (List<Object>)JSON.deserializeUntyped(idsJson)) {
            String idText = String.valueOf(idValue);

            if (!String.isBlank(idText)) {
                parsedIds.add((Id)idText);
            }
        }

        return parsedIds;
    }

    /**
     * Parses the duplicate-filter conditions JSON array into Apex wrappers.
     *
     * @param comparisonConditionsJson JSON array of comparison conditions.
     *
     * @example
     * `"[{\"rowNumber\":1,\"fieldApiName\":\"StageName\",\"operator\":\"equals\",\"value\":\"New\"}]"`
     *
     * @return Returns parsed comparison conditions, or an empty list when the input is blank.
    **/
    private static List<ComparisonCondition> m_parseComparisonConditions(String comparisonConditionsJson) {
        if (String.isBlank(comparisonConditionsJson)) {
            return new List<ComparisonCondition>();
        }

        List<ComparisonCondition> parsedComparisonConditions =
            (List<ComparisonCondition>)JSON.deserialize(comparisonConditionsJson, List<ComparisonCondition>.class);

        System.debug(
            'm_parseComparisonConditions parsedComparisonConditions=' +
            m_describeComparisonConditions(parsedComparisonConditions)
        );
        return parsedComparisonConditions;
    }

    /**
     * Returns a safe debug string for duplicate-filter conditions that may contain generic Object values.
     *
     * @param comparisonConditions Parsed comparison conditions from step 2.
     *
     * @example
     * A condition list may contain text, number, date, boolean, or null values.
     *
     * @return Returns a compact debug string that does not rely on JSON serialization of generic `Object` values.
    **/
    private static String m_describeComparisonConditions(List<ComparisonCondition> comparisonConditions) {
        List<String> conditionDescriptions = new List<String>();

        for (ComparisonCondition comparisonCondition : comparisonConditions) {
            if (comparisonCondition == null) {
                conditionDescriptions.add('{null}');
                continue;
            }

            conditionDescriptions.add(
                '{row=' + comparisonCondition.rowNumber +
                ', field=' + comparisonCondition.fieldApiName +
                ', operator=' + comparisonCondition.operator +
                ', value=' + String.valueOf(comparisonCondition.value) + '}'
            );
        }

        return '[' + String.join(conditionDescriptions, ', ') + ']';
    }

    /**
     * Returns a safe debug description for sampled formula-evaluation rows without serializing raw `Object` values to JSON.
     *
     * @param evaluationSamples Evaluation sample maps collected during preview filtering.
     *
     * @example
     * A sample may contain Opportunity ids, Account ids, compared field values, condition results, and final formula result.
     *
     * @return Returns a plain-text debug string with sample values converted via `String.valueOf`.
    **/
    private static String m_describeEvaluationSamples(List<Map<String, Object>> evaluationSamples) {
        List<String> sampleDescriptions = new List<String>();

        for (Map<String, Object> evaluationSample : evaluationSamples) {
            sampleDescriptions.add(String.valueOf(evaluationSample));
        }

        return '[' + String.join(sampleDescriptions, ', ') + ']';
    }

    /**
     * Returns a safe debug description for sampled preview Accounts without serializing raw `Object` values to JSON.
     *
     * @param previewAccountSamples Preview-account sample maps collected for manual verification.
     *
     * @example
     * A sample may contain one Account, its source report, and up to three existing Request Opportunities.
     *
     * @return Returns a plain-text debug string with sample values converted via `String.valueOf`.
    **/
    private static String m_describePreviewAccountSamples(List<Map<String, Object>> previewAccountSamples) {
        List<String> sampleDescriptions = new List<String>();

        for (Map<String, Object> previewAccountSample : previewAccountSamples) {
            sampleDescriptions.add(String.valueOf(previewAccountSample));
        }

        return '[' + String.join(sampleDescriptions, ', ') + ']';
    }

    /**
     * Converts a comparison formula to postfix notation after validating syntax and row references.
     *
     * @param comparisonFormulaText Boolean formula text entered on step 2.
     * @param maxConditionNumber Highest allowed condition number in the formula.
     *
     * @example
     * `"(1 AND 2) OR 3"`
     *
     * @return Returns postfix tokens ready for efficient evaluation against one Opportunity record.
    **/
    private static List<String> m_buildComparisonFormulaPostfix(String comparisonFormulaText, Integer maxConditionNumber) {
        List<String> formulaTokens = m_tokenizeComparisonFormula(comparisonFormulaText);
        List<String> postfixTokens = new List<String>();
        List<String> operatorStack = new List<String>();
        Boolean expectsOperand = true;
        Set<Integer> referencedConditionNumbers = new Set<Integer>();

        System.debug('m_buildComparisonFormulaPostfix formulaTokens=' + formulaTokens);
        System.debug('m_buildComparisonFormulaPostfix maxConditionNumber=' + maxConditionNumber);

        for (String formulaToken : formulaTokens) {
            if (formulaToken == '(') {
                if (!expectsOperand) {
                    throw new CreateOpportunitiesFromReportsControllerException(
                        'Correct the comparison formula syntax before continuing.'
                    );
                }

                operatorStack.add(formulaToken);
                continue;
            }

            if (formulaToken == ')') {
                if (expectsOperand) {
                    throw new CreateOpportunitiesFromReportsControllerException(
                        'Correct the comparison formula syntax before continuing.'
                    );
                }

                while (!operatorStack.isEmpty() && operatorStack[operatorStack.size() - 1] != '(') {
                    postfixTokens.add(operatorStack.remove(operatorStack.size() - 1));
                }

                if (operatorStack.isEmpty()) {
                    throw new CreateOpportunitiesFromReportsControllerException(
                        'Correct the parentheses in the comparison formula before continuing.'
                    );
                }

                operatorStack.remove(operatorStack.size() - 1);
                expectsOperand = false;
                continue;
            }

            if (formulaToken == 'AND' || formulaToken == 'OR') {
                if (expectsOperand) {
                    throw new CreateOpportunitiesFromReportsControllerException(
                        'Correct the comparison formula syntax before continuing.'
                    );
                }

                while (
                    !operatorStack.isEmpty() &&
                    operatorStack[operatorStack.size() - 1] != '(' &&
                    m_getComparisonFormulaOperatorPrecedence(operatorStack[operatorStack.size() - 1]) >=
                        m_getComparisonFormulaOperatorPrecedence(formulaToken)
                ) {
                    postfixTokens.add(operatorStack.remove(operatorStack.size() - 1));
                }

                operatorStack.add(formulaToken);
                expectsOperand = true;
                continue;
            }

            Integer conditionNumber = Integer.valueOf(formulaToken);

            if (conditionNumber < 1) {
                throw new CreateOpportunitiesFromReportsControllerException(
                    'Correct the comparison formula syntax before continuing.'
                );
            }

            if (conditionNumber > maxConditionNumber) {
                throw new CreateOpportunitiesFromReportsControllerException(
                    'The number of conditions referenced in the formula does not match the number of comparison conditions configured.'
                );
            }

            if (!expectsOperand) {
                throw new CreateOpportunitiesFromReportsControllerException(
                    'Correct the comparison formula syntax before continuing.'
                );
            }

            referencedConditionNumbers.add(conditionNumber);
            postfixTokens.add(formulaToken);
            expectsOperand = false;
        }

        if (expectsOperand) {
            throw new CreateOpportunitiesFromReportsControllerException(
                'Correct the comparison formula syntax before continuing.'
            );
        }

        while (!operatorStack.isEmpty()) {
            String operatorToken = operatorStack.remove(operatorStack.size() - 1);

            if (operatorToken == '(') {
                throw new CreateOpportunitiesFromReportsControllerException(
                    'Correct the parentheses in the comparison formula before continuing.'
                );
            }

            postfixTokens.add(operatorToken);
        }

        for (Integer conditionNumber = 1; conditionNumber <= maxConditionNumber; conditionNumber++) {
            if (!referencedConditionNumbers.contains(conditionNumber)) {
                throw new CreateOpportunitiesFromReportsControllerException(
                    'Reference every comparison condition at least once in the formula.'
                );
            }
        }

        System.debug('m_buildComparisonFormulaPostfix postfixTokens=' + postfixTokens);
        return postfixTokens;
    }

    /**
     * Tokenizes the raw comparison formula text.
     *
     * @param comparisonFormulaText Boolean formula text entered on step 2.
     *
     * @example
     * `"(1 AND 2) OR 3"`
     *
     * @return Returns validated uppercase formula tokens with whitespace removed.
    **/
    private static List<String> m_tokenizeComparisonFormula(String comparisonFormulaText) {
        if (String.isBlank(comparisonFormulaText)) {
            throw new CreateOpportunitiesFromReportsControllerException(
                'Enter a comparison formula before continuing.'
            );
        }

        String normalizedFormulaText = comparisonFormulaText.trim();
        String condensedFormulaText = normalizedFormulaText.replaceAll('\\s+', '').toUpperCase();
        List<String> formulaTokens = new List<String>();
        String matchedFormulaText = '';
        Matcher tokenMatcher = Pattern.compile('(?i)\\d+|&&|\\|\\||AND|OR|\\(|\\)').matcher(normalizedFormulaText);

        while (tokenMatcher.find()) {
            String rawTokenValue = tokenMatcher.group(0);
            String tokenValue = rawTokenValue.toUpperCase();

            if (tokenValue == '&&') {
                tokenValue = 'AND';
            } else if (tokenValue == '||') {
                tokenValue = 'OR';
            }

            formulaTokens.add(tokenValue);
            matchedFormulaText += rawTokenValue.toUpperCase();
        }

        if (formulaTokens.isEmpty() || matchedFormulaText != condensedFormulaText) {
            throw new CreateOpportunitiesFromReportsControllerException(
                'Use only condition numbers, AND/OR, &&/||, and parentheses in the comparison formula.'
            );
        }

        System.debug('m_tokenizeComparisonFormula normalizedFormulaText=' + normalizedFormulaText);
        System.debug('m_tokenizeComparisonFormula condensedFormulaText=' + condensedFormulaText);
        System.debug('m_tokenizeComparisonFormula formulaTokens=' + formulaTokens);
        return formulaTokens;
    }

    /**
     * Returns precedence for one comparison formula operator.
     *
     * @param operatorToken Formula operator token.
     *
     * @example
     * `AND`
     *
     * @return Returns a numeric precedence where `AND` is higher than `OR`.
    **/
    private static Integer m_getComparisonFormulaOperatorPrecedence(String operatorToken) {
        return operatorToken == 'AND' ? 2 : 1;
    }

    /**
     * Evaluates one postfix comparison formula against already computed condition booleans.
     *
     * @param postfixTokens Postfix comparison formula tokens.
     * @param conditionResultsByNumber Boolean results keyed by condition row number.
     *
     * @example
     * `postfixTokens = new List<String>{'1','2','AND'}`
     *
     * @return Returns true when the formula evaluates to true for the current Opportunity record.
    **/
    private static Boolean m_evaluateComparisonFormula(
        List<String> postfixTokens,
        Map<Integer, Boolean> conditionResultsByNumber
    ) {
        List<Boolean> evaluationStack = new List<Boolean>();

        for (String postfixToken : postfixTokens) {
            if (postfixToken == 'AND' || postfixToken == 'OR') {
                if (evaluationStack.size() < 2) {
                    throw new CreateOpportunitiesFromReportsControllerException(
                        'Correct the comparison formula syntax before continuing.'
                    );
                }

                Boolean rightOperand = evaluationStack.remove(evaluationStack.size() - 1);
                Boolean leftOperand = evaluationStack.remove(evaluationStack.size() - 1);
                evaluationStack.add(
                    postfixToken == 'AND'
                        ? leftOperand && rightOperand
                        : leftOperand || rightOperand
                );
                continue;
            }

            evaluationStack.add(conditionResultsByNumber.get(Integer.valueOf(postfixToken)) == true);
        }

        if (evaluationStack.size() != 1) {
            throw new CreateOpportunitiesFromReportsControllerException(
                'Correct the comparison formula syntax before continuing.'
            );
        }

        System.debug(
            'm_evaluateComparisonFormula postfixTokens=' + postfixTokens +
            ', conditionResultsByNumber=' + JSON.serialize(conditionResultsByNumber) +
            ', finalResult=' + evaluationStack[0]
        );
        return evaluationStack[0];
    }

    /**
     * Evaluates one prepared comparison condition against one existing Opportunity field value.
     *
     * @param existingValue Existing Opportunity field value from the queried record.
     * @param preparedComparisonCondition Prepared comparison condition with typed comparison value.
     *
     * @example
     * `operator = "equals", value = "New"`
     *
     * @return Returns true when the current Opportunity satisfies the condition.
    **/
    private static Boolean m_evaluatePreparedComparisonCondition(
        Object existingValue,
        PreparedComparisonCondition preparedComparisonCondition
    ) {
        if (preparedComparisonCondition.operator == 'contains') {
            return preparedComparisonCondition.value != null &&
                existingValue != null &&
                String.valueOf(existingValue).contains(String.valueOf(preparedComparisonCondition.value));
        }

        if (preparedComparisonCondition.operator == 'startsWith') {
            return preparedComparisonCondition.value != null &&
                existingValue != null &&
                String.valueOf(existingValue).startsWith(String.valueOf(preparedComparisonCondition.value));
        }

        Integer comparisonResult = m_compareComparisonValues(
            existingValue,
            preparedComparisonCondition.value,
            preparedComparisonCondition.displayType
        );

        if (preparedComparisonCondition.operator == 'greaterThan') {
            return comparisonResult != null && comparisonResult > 0;
        }

        if (preparedComparisonCondition.operator == 'greaterOrEqual') {
            return comparisonResult != null && comparisonResult >= 0;
        }

        if (preparedComparisonCondition.operator == 'lessThan') {
            return comparisonResult != null && comparisonResult < 0;
        }

        if (preparedComparisonCondition.operator == 'lessOrEqual') {
            return comparisonResult != null && comparisonResult <= 0;
        }

        Boolean isEqual = comparisonResult == 0;
        return preparedComparisonCondition.operator == 'notEquals' ? !isEqual : isEqual;
    }

    /**
     * Compares two field values using the field type expected by the comparison condition.
     *
     * @param existingValue Existing Opportunity field value from the queried record.
     * @param comparisonValue Typed comparison value from the condition row.
     * @param displayType Salesforce display type of the compared Opportunity field.
     *
     * @example
     * `existingValue = "New", comparisonValue = "Approved", displayType = PICKLIST`
     *
     * @return Returns `0` when equal, a positive integer when the existing value is greater, a negative integer when it is lower, or null when ordered comparison is impossible.
    **/
    private static Integer m_compareComparisonValues(
        Object existingValue,
        Object comparisonValue,
        Schema.DisplayType displayType
    ) {
        Object normalizedExistingValue = m_normalizeComparisonValue(existingValue, displayType);
        Object normalizedComparisonValue = m_normalizeComparisonValue(comparisonValue, displayType);

        if (normalizedExistingValue == null && normalizedComparisonValue == null) {
            return 0;
        }

        if (normalizedExistingValue == null || normalizedComparisonValue == null) {
            return null;
        }

        switch on displayType {
            when BOOLEAN {
                Boolean existingBooleanValue = (Boolean)normalizedExistingValue;
                Boolean comparisonBooleanValue = (Boolean)normalizedComparisonValue;

                if (existingBooleanValue == comparisonBooleanValue) {
                    return 0;
                }

                return existingBooleanValue ? 1 : -1;
            }
            when CURRENCY, DOUBLE, INTEGER, LONG, PERCENT {
                Decimal existingNumericValue = Decimal.valueOf(String.valueOf(normalizedExistingValue));
                Decimal comparisonNumericValue = Decimal.valueOf(String.valueOf(normalizedComparisonValue));

                if (existingNumericValue == comparisonNumericValue) {
                    return 0;
                }

                return existingNumericValue > comparisonNumericValue ? 1 : -1;
            }
            when DATE {
                Date existingDateValue = (Date)normalizedExistingValue;
                Date comparisonDateValue = (Date)normalizedComparisonValue;
                Integer dateDelta = existingDateValue.daysBetween(comparisonDateValue);
                return dateDelta == 0 ? 0 : (dateDelta > 0 ? -1 : 1);
            }
            when DATETIME {
                Long existingTimeValue = ((Datetime)normalizedExistingValue).getTime();
                Long comparisonTimeValue = ((Datetime)normalizedComparisonValue).getTime();

                if (existingTimeValue == comparisonTimeValue) {
                    return 0;
                }

                return existingTimeValue > comparisonTimeValue ? 1 : -1;
            }
            when else {
                return String.valueOf(normalizedExistingValue).compareTo(String.valueOf(normalizedComparisonValue));
            }
        }
    }

    /**
     * Normalizes one comparison value before equality or ordering checks.
     *
     * @param rawValue Raw existing or comparison value.
     * @param displayType Salesforce display type of the compared Opportunity field.
     *
     * @example
     * `rawValue = ""`, `displayType = PICKLIST`
     *
     * @return Returns the normalized comparison value, or null when the value should be treated as empty.
    **/
    private static Object m_normalizeComparisonValue(Object rawValue, Schema.DisplayType displayType) {
        if (rawValue == null) {
            return null;
        }

        if (displayType == Schema.DisplayType.BOOLEAN) {
            return rawValue instanceof Boolean ? rawValue : Boolean.valueOf(String.valueOf(rawValue));
        }

        String valueText = String.valueOf(rawValue);
        return String.isBlank(valueText) ? null : rawValue;
    }

    /**
     * Resolves the report type descriptor for one report by describing report metadata.
     *
     * @param reportId Salesforce Report Id.
     *
     * @example
     * `00Oxx0000000001AAA`
     *
     * @return Returns `ReportTypeDescriptor` with the inferred type label and support flag.
    **/
    private static ReportTypeDescriptor m_getReportTypeDescriptor(String reportId) {
        if (Test.isRunningTest() && testReportDefinitionsById.containsKey(reportId)) {
            TestReportDefinition reportDefinition = testReportDefinitionsById.get(reportId);
            String reportType = m_inferReportType(reportDefinition.detailColumns);
            Boolean isSupportedType = String.valueOf(reportDefinition.reportFormat).toUpperCase() != 'MULTI_BLOCK' &&
                m_isSupportedReportType(reportType);

            if (!isSupportedType && String.isBlank(reportType)) {
                reportType = reportDefinition.reportFormat;
            }

            return new ReportTypeDescriptor(reportType, isSupportedType);
        }

        Reports.ReportMetadata reportMetadata = Reports.ReportManager.describeReport(reportId).getReportMetadata();
        String reportType = m_inferReportType(reportMetadata.getDetailColumns());
        Boolean isSupportedType = reportMetadata.getReportFormat() != Reports.ReportFormat.MULTI_BLOCK &&
            m_isSupportedReportType(reportType);

        if (!isSupportedType && String.isBlank(reportType)) {
            reportType = String.valueOf(reportMetadata.getReportFormat());
        }

        return new ReportTypeDescriptor(reportType, isSupportedType);
    }

    /**
     * Infers the report type from the report detail columns.
     *
     * @param detailColumns Report detail column API names.
     *
     * @example
     * `["ACCOUNT.NAME","ACCOUNT.ID"]`
     *
     * @return Returns `AccountList`, `account_contact__c`, or an empty string when the type cannot be inferred.
    **/
    private static String m_inferReportType(List<String> detailColumns) {
        Set<String> normalizedColumns = new Set<String>();

        for (String detailColumn : detailColumns) {
            normalizedColumns.add(String.valueOf(detailColumn).toLowerCase());
        }

        if (normalizedColumns.contains('account.name') || normalizedColumns.contains('account.id')) {
            if (normalizedColumns.contains('contact.name') || normalizedColumns.contains('contact.id')) {
                return GlobalConstantsAndEnums.REPORT_TYPE_ACCOUNT_CONTACT;
            }

            return REPORT_TYPE_ACCOUNT_LIST;
        }

        return '';
    }

    /**
     * Returns true when the report type is supported by the modal.
     *
     * @param reportType Raw report type value.
     *
     * @example
     * `AccountList`
     *
     * @return Returns true only for Account and Contact-and-Account reports.
    **/
    private static Boolean m_isSupportedReportType(String reportType) {
        return reportType == REPORT_TYPE_ACCOUNT_LIST ||
            reportType == GlobalConstantsAndEnums.REPORT_TYPE_ACCOUNT_CONTACT;
    }

    /**
     * Extracts Account Ids from a supported report when report metadata is already known.
     *
     * @param reportId Salesforce Report Id.
     * @param reportName Report name.
     * @param reportType Supported report type value.
     *
     * @example
     * `reportId = "00Oxx0000000001AAA", reportName = "Open Requests", reportType = "AccountList"`
     *
     * @return Returns `ReportExtractionResult` with:
     *   - `reportName: String` - report name.
     *   - `accountIds: Set<Id>` - unique Account Ids extracted from the report rows.
    **/
    private static ReportExtractionResult m_extractAccountIdsFromReport(String reportId, String reportName, String reportType) {
        if (Test.isRunningTest() && testReportDefinitionsById.containsKey(reportId)) {
            TestReportDefinition reportDefinition = testReportDefinitionsById.get(reportId);
            Set<Id> extractedAccountIds = new Set<Id>();

            for (List<Object> rowValues : reportDefinition.rows) {
                extractedAccountIds.addAll(m_extractAccountIdsFromSyntheticRow(rowValues, reportDefinition.detailColumns, reportType));
            }

            return new ReportExtractionResult(reportName, extractedAccountIds);
        }

        Reports.ReportResults reportResults = Reports.ReportManager.runReport(reportId, true);
        List<String> detailColumns = reportResults.getReportMetadata().getDetailColumns();
        Set<Id> extractedAccountIds = new Set<Id>();

        for (String factKey : reportResults.getFactMap().keySet()) {
            Reports.ReportFact reportFact = reportResults.getFactMap().get(factKey);

            if (!(reportFact instanceof Reports.ReportFactWithDetails)) {
                continue;
            }

            Reports.ReportFactWithDetails detailFact = (Reports.ReportFactWithDetails)reportFact;

            if (detailFact.getRows() == null) {
                continue;
            }

            for (Reports.ReportDetailRow detailRow : detailFact.getRows()) {
                extractedAccountIds.addAll(m_extractAccountIdsFromRow(detailRow.getDataCells(), detailColumns, reportType));
            }
        }

        return new ReportExtractionResult(reportName, extractedAccountIds);
    }

    /**
     * Extracts Account Ids from one report detail row.
     *
     * @param dataCells Report row cells.
     * @param detailColumns Report detail column API names.
     * @param reportType Supported report type value.
     *
     * @example
     * `reportType = "account_contact__c"`
     *
     * @return Returns unique Account Ids discovered in the row.
    **/
    private static Set<Id> m_extractAccountIdsFromRow(
        List<Reports.ReportDataCell> dataCells,
        List<String> detailColumns,
        String reportType
    ) {
        Set<Id> accountIds = new Set<Id>();

        for (Integer index = 0; index < dataCells.size(); index++) {
            String normalizedColumn = String.valueOf(detailColumns[index]).toLowerCase();
            Reports.ReportDataCell dataCell = dataCells[index];

            if (reportType == REPORT_TYPE_ACCOUNT_LIST &&
                (normalizedColumn == 'account.id' || normalizedColumn == 'account.name')) {
                Id accountId = m_tryConvertToAccountId(dataCell);

                if (accountId != null) {
                    accountIds.add(accountId);
                }
            }

            if (reportType == GlobalConstantsAndEnums.REPORT_TYPE_ACCOUNT_CONTACT &&
                (normalizedColumn == 'account.id' || normalizedColumn == 'account.name')) {
                Id accountId = m_tryConvertToAccountId(dataCell);

                if (accountId != null) {
                    accountIds.add(accountId);
                }
            }
        }

        return accountIds;
    }

    /**
     * Extracts Account Ids from one synthetic test-report row.
     *
     * @param rowValues Synthetic row values aligned with `detailColumns`.
     * @param detailColumns Synthetic report detail column API names.
     * @param reportType Supported report type value.
     *
     * @example
     * `rowValues = new List<Object>{ 'Account Label', '001xx0000000001AAA' }`
     *
     * @return Returns unique Account Ids discovered in the synthetic row.
    **/
    private static Set<Id> m_extractAccountIdsFromSyntheticRow(
        List<Object> rowValues,
        List<String> detailColumns,
        String reportType
    ) {
        Set<Id> accountIds = new Set<Id>();

        for (Integer index = 0; index < rowValues.size(); index++) {
            String normalizedColumn = String.valueOf(detailColumns[index]).toLowerCase();

            if (reportType == REPORT_TYPE_ACCOUNT_LIST &&
                (normalizedColumn == 'account.id' || normalizedColumn == 'account.name')) {
                Id accountId = m_tryConvertToAccountId(rowValues[index]);

                if (accountId != null) {
                    accountIds.add(accountId);
                }
            }

            if (reportType == GlobalConstantsAndEnums.REPORT_TYPE_ACCOUNT_CONTACT &&
                (normalizedColumn == 'account.id' || normalizedColumn == 'account.name')) {
                Id accountId = m_tryConvertToAccountId(rowValues[index]);

                if (accountId != null) {
                    accountIds.add(accountId);
                }
            }
        }

        return accountIds;
    }

    /**
     * Tries to convert one report cell value to an Account Id.
     *
     * @param dataCell One Analytics report data cell.
     *
     * @example
     * A lookup cell may contain `value = "001xx0000000001AAA"` while the label contains the Account name.
     *
     * @return Returns the Account Id when the cell value contains an Account reference; otherwise returns null.
    **/
    private static Id m_tryConvertToAccountId(Reports.ReportDataCell dataCell) {
        if (dataCell == null || dataCell.getValue() == null) {
            return null;
        }

        return m_tryConvertToAccountId(dataCell.getValue());
    }

    /**
     * Tries to convert one raw report cell value to an Account Id.
     *
     * @param rawValue Raw Analytics or synthetic test-row value.
     *
     * @example
     * `001xx0000000001AAA`
     *
     * @return Returns the Account Id when the raw value contains an Account reference; otherwise returns null.
    **/
    private static Id m_tryConvertToAccountId(Object rawValue) {
        if (rawValue == null) {
            return null;
        }

        String valueText = String.valueOf(rawValue);

        if (valueText.startsWith(ACCOUNT_KEY_PREFIX)) {
            return (Id)valueText;
        }

        return null;
    }

    /**
     * Registers one synthetic report definition for test-only report selector coverage.
     *
     * @param reportId Fake Report Id returned back to the client contract.
     * @param reportName Display report name.
     * @param folderName Optional folder label.
     * @param reportFormat Synthetic format literal.
     * @param detailColumns Synthetic detail columns.
     * @param rows Synthetic row values aligned with `detailColumns`.
     *
     * @example
     * `reportId = "00O000000000001AAA", reportFormat = "TABULAR", detailColumns = new List<String>{ 'ACCOUNT.ID' }, rows = new List<List<Object>>{ new List<Object>{ '001xx0000000001AAA' } }`
     *
     * @return Returns nothing. Stores the synthetic definition in controller test state.
    **/
    @TestVisible
    private static void m_registerTestReportDefinition(
        String reportId,
        String reportName,
        String folderName,
        String reportFormat,
        List<String> detailColumns,
        List<List<Object>> rows
    ) {
        TestReportDefinition reportDefinition = new TestReportDefinition();
        reportDefinition.reportId = reportId;
        reportDefinition.reportName = reportName;
        reportDefinition.folderName = folderName;
        reportDefinition.reportFormat = reportFormat;
        reportDefinition.detailColumns = detailColumns == null ? new List<String>() : new List<String>(detailColumns);
        reportDefinition.rows = new List<List<Object>>();

        if (rows != null) {
            for (List<Object> rowValues : rows) {
                reportDefinition.rows.add(rowValues == null ? new List<Object>() : new List<Object>(rowValues));
            }
        }

        testReportDefinitionsById.put(reportId, reportDefinition);
    }

    /**
     * Clears all synthetic report definitions stored for tests.
     *
     * @example
     * No input payload is required.
     *
     * @return Returns nothing. Removes all synthetic report definitions from controller test state.
    **/
    @TestVisible
    private static void m_clearTestReportDefinitions() {
        testReportDefinitionsById.clear();
    }

    /**
     * Creates one chunk of Request Opportunities from selected preview Accounts.
     *
     * @param requestWrapper Parsed chunk-create request.
     *
     * @example
     * A chunk may contain up to 25 or 50 Account ids and one shared prepared Opportunity payload.
     *
     * @return Returns created rows, created Opportunity ids, ERP-stage Opportunity ids, and collected row-level errors.
    **/
    private static CreationChunkData m_createOpportunitiesChunk(Request requestWrapper) {
        List<Id> accountIds = m_parseIdList(requestWrapper.accountIdsJson);
        Map<String, Object> preparedOpportunityValues = m_parseUntypedObjectMap(requestWrapper.preparedOpportunityJson);
        Map<String, Schema.SObjectField> opportunityFieldsByApiName = Opportunity.SObjectType.getDescribe().fields.getMap();
        Map<String, Object> missingRequiredDefaultValues = m_getMissingRequiredOpportunityDefaultValues(
            preparedOpportunityValues,
            opportunityFieldsByApiName
        );
        Id requestRecordTypeId = m_getRequestRecordTypeId();
        Map<Id, Account> accountById = accountIds.isEmpty()
            ? new Map<Id, Account>()
            : new Map<Id, Account>([
                SELECT Id, Name, npe01__One2OneContact__c
                FROM Account
                WHERE Id IN :accountIds
            ]);
        Schema.DescribeFieldResult amountFieldDescribe = opportunityFieldsByApiName.containsKey('Amount')
            ? opportunityFieldsByApiName.get('Amount').getDescribe()
            : null;
        Decimal requestedAmount = amountFieldDescribe == null
            ? null
            : (Decimal)m_castFieldValue(preparedOpportunityValues.get('Amount'), amountFieldDescribe);
        List<Opportunity> opportunitiesToInsert = new List<Opportunity>();
        List<Id> accountIdsByOpportunityIndex = new List<Id>();
        List<String> rowLevelErrors = new List<String>();
        List<ExecutionRow> createdRows = new List<ExecutionRow>();
        List<Id> createdOpportunityIds = new List<Id>();
        List<String> createInputSamples = new List<String>();
        Integer generatedNameSequence = 0;

        System.debug('m_createOpportunitiesChunk accountIds=' + accountIds);
        System.debug('m_createOpportunitiesChunk preparedOpportunityValues=' + preparedOpportunityValues);
        System.debug('m_createOpportunitiesChunk missingRequiredDefaultValues=' + missingRequiredDefaultValues);

        for (Id accountId : accountIds) {
            if (!accountById.containsKey(accountId)) {
                rowLevelErrors.add('Account not found for Id ' + accountId);
                createdRows.add(new ExecutionRow(
                    null,
                    null,
                    accountId,
                    null,
                    null,
                    null,
                    EXECUTION_STATUS_FAILED_TO_CREATE_OPPORTUNITY,
                    'Account not found for Id ' + accountId
                ));
                continue;
            }

            Account accountRecord = accountById.get(accountId);
            Opportunity opportunityRecord = new Opportunity();

            for (String defaultFieldApiName : missingRequiredDefaultValues.keySet()) {
                m_setOpportunityCreateValue(
                    opportunityRecord,
                    defaultFieldApiName,
                    missingRequiredDefaultValues.get(defaultFieldApiName),
                    opportunityFieldsByApiName
                );
            }

            for (String preparedFieldApiName : preparedOpportunityValues.keySet()) {
                if (preparedFieldApiName == 'Name') {
                    continue;
                }

                m_setOpportunityCreateValue(
                    opportunityRecord,
                    preparedFieldApiName,
                    preparedOpportunityValues.get(preparedFieldApiName),
                    opportunityFieldsByApiName
                );
            }

            generatedNameSequence += 1;
            opportunityRecord.RecordTypeId = requestRecordTypeId;
            opportunityRecord.AccountId = accountId;
            opportunityRecord.Name = m_buildRequestOpportunityName(generatedNameSequence);
            m_setOpportunityCreateValue(
                opportunityRecord,
                PRIMARY_CONTACT_FIELD_API_NAME,
                accountRecord.get(ONE_TO_ONE_CONTACT_FIELD_API_NAME),
                opportunityFieldsByApiName
            );
            m_setOpportunityCreateValue(
                opportunityRecord,
                REQUESTED_AMOUNT_FIELD_API_NAME,
                requestedAmount,
                opportunityFieldsByApiName
            );
            if (createInputSamples.size() < DEBUG_CREATE_INPUT_SAMPLE_LIMIT) {
                createInputSamples.add(
                    'accountId=' + accountId +
                    ', accountName=' + accountRecord.Name +
                    ', generatedName=' + opportunityRecord.Name +
                    ', stageName=' + String.valueOf(opportunityRecord.get('StageName')) +
                    ', amount=' + String.valueOf(opportunityRecord.get('Amount')) +
                    ', primaryContactId=' + String.valueOf(opportunityRecord.get(PRIMARY_CONTACT_FIELD_API_NAME)) +
                    ', requestedAmount=' + String.valueOf(opportunityRecord.get(REQUESTED_AMOUNT_FIELD_API_NAME)) +
                    ', numberOfPayments=' + String.valueOf(opportunityRecord.get(NUMBER_OF_PAYMENTS_FIELD_API_NAME)) +
                    ', doNotAutoCreatePayment=' + String.valueOf(opportunityRecord.get(DO_NOT_AUTO_CREATE_PAYMENT_FIELD_API_NAME))
                );
            }

            opportunitiesToInsert.add(opportunityRecord);
            accountIdsByOpportunityIndex.add(accountId);
        }

        if (!opportunitiesToInsert.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(opportunitiesToInsert, false);

            for (Integer opportunityIndex = 0; opportunityIndex < insertResults.size(); opportunityIndex++) {
                Database.SaveResult insertResult = insertResults[opportunityIndex];
                Id accountId = accountIdsByOpportunityIndex[opportunityIndex];
                Account accountRecord = accountById.get(accountId);
                Opportunity insertedOpportunity = opportunitiesToInsert[opportunityIndex];

                if (insertResult.isSuccess()) {
                    insertedOpportunity.Id = insertResult.getId();
                    createdOpportunityIds.add(insertResult.getId());
                    createdRows.add(new ExecutionRow(
                        insertResult.getId(),
                        String.valueOf(insertedOpportunity.Name),
                        accountId,
                        accountRecord.Name,
                        null,
                        null,
                        EXECUTION_STATUS_SUCCESS,
                        ''
                    ));

                    continue;
                }

                String createErrorMessage = m_getDmlErrorMessage(insertResult.getErrors(), Opportunity.SObjectType);
                rowLevelErrors.add(
                    'Account ' + accountRecord.Name + ' failed Opportunity creation: ' + createErrorMessage
                );
                createdRows.add(new ExecutionRow(
                    null,
                    null,
                    accountId,
                    accountRecord.Name,
                    null,
                    null,
                    EXECUTION_STATUS_FAILED_TO_CREATE_OPPORTUNITY,
                    createErrorMessage
                ));
            }
        }

        System.debug('m_createOpportunitiesChunk createdOpportunityIds=' + createdOpportunityIds);
        System.debug('m_createOpportunitiesChunk rowLevelErrors=' + rowLevelErrors);
        System.debug('m_createOpportunitiesChunk createInputSamples=' + createInputSamples);
        System.debug(
            'm_createOpportunitiesChunk createdRowSamples=' +
            m_describeExecutionRowSamples(createdRows, DEBUG_EXECUTION_ROW_SAMPLE_LIMIT)
        );
        return new CreationChunkData(
            accountIds.size(),
            createdOpportunityIds.size(),
            rowLevelErrors.size(),
            JSON.serialize(createdOpportunityIds),
            createdRows,
            rowLevelErrors
        );
    }

    /**
     * Refreshes one created Opportunity chunk and returns the latest Opportunity names and already-created Payments.
     *
     * @param requestWrapper Parsed created-Opportunity refresh request.
     *
     * @example
     * One refresh reads only the Opportunity ids created by one already-finished chunk.
     *
     * @return Returns found Payment ids and execution rows enriched with the latest Opportunity and Payment names.
    **/
    private static RefreshChunkData m_refreshCreatedOpportunityChunk(Request requestWrapper) {
        List<Id> opportunityIds = m_parseIdList(requestWrapper.opportunityIdsJson);
        Map<Id, Opportunity> opportunityById = opportunityIds.isEmpty()
            ? new Map<Id, Opportunity>()
            : new Map<Id, Opportunity>([
                SELECT Id, Name, AccountId, Account.Name
                FROM Opportunity
                WHERE Id IN :opportunityIds
            ]);
        Map<Id, ExecutionRow> executionRowByOpportunityId = new Map<Id, ExecutionRow>();
        List<Id> foundPaymentIds = new List<Id>();

        for (Opportunity opportunityRecord : opportunityById.values()) {
            executionRowByOpportunityId.put(opportunityRecord.Id, new ExecutionRow(
                opportunityRecord.Id,
                opportunityRecord.Name,
                opportunityRecord.AccountId,
                opportunityRecord.Account == null ? null : opportunityRecord.Account.Name,
                null,
                null,
                EXECUTION_STATUS_SUCCESS,
                ''
            ));
        }

        if (!opportunityById.isEmpty()) {
            for (npe01__OppPayment__c paymentRecord : [
                SELECT Id, Name, npe01__Opportunity__c, npe01__Opportunity__r.Name,
                    npe01__Opportunity__r.AccountId, npe01__Opportunity__r.Account.Name
                FROM npe01__OppPayment__c
                WHERE npe01__Opportunity__c IN :opportunityById.keySet()
                ORDER BY CreatedDate DESC
            ]) {
                Id opportunityId = paymentRecord.npe01__Opportunity__c;

                foundPaymentIds.add(paymentRecord.Id);
                ExecutionRow currentExecutionRow = executionRowByOpportunityId.get(opportunityId);

                executionRowByOpportunityId.put(opportunityId, new ExecutionRow(
                    opportunityId,
                    currentExecutionRow == null ? paymentRecord.npe01__Opportunity__r.Name : currentExecutionRow.opportunityName,
                    currentExecutionRow == null ? paymentRecord.npe01__Opportunity__r.AccountId : currentExecutionRow.accountId,
                    currentExecutionRow == null ? paymentRecord.npe01__Opportunity__r.Account.Name : currentExecutionRow.accountName,
                    paymentRecord.Id,
                    paymentRecord.Name,
                    EXECUTION_STATUS_SUCCESS,
                    ''
                ));
            }
        }

        System.debug('m_refreshCreatedOpportunityChunk opportunityIds=' + opportunityIds);
        System.debug('m_refreshCreatedOpportunityChunk foundPaymentIds=' + foundPaymentIds);
        System.debug(
            'm_refreshCreatedOpportunityChunk foundRowSamples=' +
            m_describeExecutionRowSamples(new List<ExecutionRow>(executionRowByOpportunityId.values()), DEBUG_EXECUTION_ROW_SAMPLE_LIMIT)
        );
        return new RefreshChunkData(
            opportunityIds.size(),
            foundPaymentIds.size(),
            JSON.serialize(foundPaymentIds),
            new List<ExecutionRow>(executionRowByOpportunityId.values())
        );
    }

    /**
     * Updates one chunk of found Payments from the related ERP-ready Opportunity values.
     *
     * @param requestWrapper Parsed payment-update request.
     *
     * @example
     * A chunk may contain Payment ids discovered while refreshing one or more already-created Opportunity chunks.
     *
     * @return Returns updated Payment ids, skipped count, and collected row-level errors.
    **/
    private static PaymentUpdateData m_updatePaymentsChunk(Request requestWrapper) {
        List<Id> paymentIds = m_parseIdList(requestWrapper.paymentIdsJson);
        List<npe01__OppPayment__c> paymentsToUpdate = new List<npe01__OppPayment__c>();
        List<String> rowLevelErrors = new List<String>();
        List<Id> updatedPaymentIds = new List<Id>();
        List<String> paymentUpdateSamples = new List<String>();
        List<ExecutionRow> paymentUpdateRows = new List<ExecutionRow>();

        if (!paymentIds.isEmpty()) {
            for (npe01__OppPayment__c paymentRecord : [
                SELECT Id, Name, ERP_Status__c, npe01__Payment_Amount__c,
                    npe01__Opportunity__c, npe01__Opportunity__r.Name, npe01__Opportunity__r.StageName,
                    npe01__Opportunity__r.Amount, npe01__Opportunity__r.AccountId, npe01__Opportunity__r.Account.Name
                FROM npe01__OppPayment__c
                WHERE Id IN :paymentIds
                    AND npe01__Opportunity__r.StageName = :GlobalConstantsAndEnums.STAGE_READY_FOR_TRANSFER_TO_ERP
            ]) {
                if (paymentUpdateSamples.size() < DEBUG_PAYMENT_UPDATE_SAMPLE_LIMIT) {
                    paymentUpdateSamples.add(
                        'paymentId=' + paymentRecord.Id +
                        ', oldERPStatus=' + String.valueOf(paymentRecord.ERP_Status__c) +
                        ', newERPStatus=' + String.valueOf(paymentRecord.npe01__Opportunity__r.StageName) +
                        ', oldPaymentAmount=' + String.valueOf(paymentRecord.npe01__Payment_Amount__c) +
                        ', newPaymentAmount=' + String.valueOf(paymentRecord.npe01__Opportunity__r.Amount)
                    );
                }

                paymentRecord.ERP_Status__c = paymentRecord.npe01__Opportunity__r.StageName;
                paymentRecord.npe01__Payment_Amount__c = paymentRecord.npe01__Opportunity__r.Amount;
                paymentsToUpdate.add(paymentRecord);
            }
        }

        if (!paymentsToUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(paymentsToUpdate, false);

            for (Integer paymentIndex = 0; paymentIndex < updateResults.size(); paymentIndex++) {
                Database.SaveResult updateResult = updateResults[paymentIndex];
                npe01__OppPayment__c paymentRecord = paymentsToUpdate[paymentIndex];

                if (updateResult.isSuccess()) {
                    updatedPaymentIds.add(paymentRecord.Id);
                    continue;
                }

                String paymentUpdateErrorMessage = m_getDmlErrorMessage(updateResult.getErrors(), npe01__OppPayment__c.SObjectType);
                rowLevelErrors.add('Payment ' + paymentRecord.Id + ' failed update: ' + paymentUpdateErrorMessage);
                paymentUpdateRows.add(new ExecutionRow(
                    paymentRecord.npe01__Opportunity__c,
                    paymentRecord.npe01__Opportunity__r.Name,
                    paymentRecord.npe01__Opportunity__r.AccountId,
                    paymentRecord.npe01__Opportunity__r.Account.Name,
                    paymentRecord.Id,
                    paymentRecord.Name,
                    EXECUTION_STATUS_FAILED_TO_UPDATE_PAYMENT,
                    paymentUpdateErrorMessage
                ));
            }
        }

        Integer skippedPaymentCount = Math.max(0, paymentIds.size() - paymentsToUpdate.size()) +
            Math.max(0, paymentsToUpdate.size() - updatedPaymentIds.size());

        System.debug('m_updatePaymentsChunk paymentIds=' + paymentIds);
        System.debug('m_updatePaymentsChunk updatedPaymentIds=' + updatedPaymentIds);
        System.debug('m_updatePaymentsChunk rowLevelErrors=' + rowLevelErrors);
        System.debug('m_updatePaymentsChunk paymentUpdateSamples=' + paymentUpdateSamples);
        return new PaymentUpdateData(
            paymentIds.size(),
            updatedPaymentIds.size(),
            skippedPaymentCount,
            JSON.serialize(updatedPaymentIds),
            paymentUpdateRows,
            rowLevelErrors
        );
    }

    /**
     * Converts one DML error list into a human-readable message and appends field labels when Salesforce exposes field references.
     *
     * @param databaseErrors DML errors returned by `Database.SaveResult.getErrors()`.
     * @param sObjectType SObject type used to resolve field labels from API names.
     *
     * @example
     * `databaseErrors = insertResult.getErrors(), sObjectType = Opportunity.SObjectType`
     *
     * @return Returns the first DML error message, enriched with related field labels when `getFields()` returns field API names.
    **/
    private static String m_getDmlErrorMessage(List<Database.Error> databaseErrors, Schema.SObjectType sObjectType) {
        if (databaseErrors == null || databaseErrors.isEmpty()) {
            return 'Unknown DML error.';
        }

        Database.Error firstDatabaseError = databaseErrors[0];
        String errorMessage = firstDatabaseError.getMessage();
        List<String> fieldLabels = m_getFieldLabels(firstDatabaseError.getFields(), sObjectType);

        if (fieldLabels.isEmpty()) {
            return errorMessage;
        }

        return errorMessage + ' Field: ' + String.join(fieldLabels, ', ');
    }

    /**
     * Resolves display labels for DML error fields.
     *
     * @param fieldNames Field API names returned by `Database.Error.getFields()`.
     * @param sObjectType SObject type used to resolve field labels from describe metadata.
     *
     * @example
     * `fieldNames = firstDatabaseError.getFields(), sObjectType = Opportunity.SObjectType`
     *
     * @return Returns field labels in the same order as Salesforce returned field API names.
    **/
    private static List<String> m_getFieldLabels(List<String> fieldNames, Schema.SObjectType sObjectType) {
        List<String> fieldLabels = new List<String>();

        if (fieldNames == null || fieldNames.isEmpty() || sObjectType == null) {
            return fieldLabels;
        }

        Map<String, Schema.SObjectField> fieldByApiName = sObjectType.getDescribe().fields.getMap();

        for (String fieldName : fieldNames) {
            Schema.SObjectField sObjectField = fieldByApiName.get(fieldName);
            fieldLabels.add(sObjectField == null ? fieldName : sObjectField.getDescribe().getLabel());
        }

        return fieldLabels;
    }

    /**
     * Resolves preview lookup entries into display names and target object API names.
     *
     * @param lookupFieldValueEntriesJson JSON array of lookup preview entries, for example:
     * `[{"fieldApiName":"Fund__c","recordId":"a0Uxx0000000001AAA"},{"fieldApiName":"CampaignId","recordId":"701xx0000000001AAA"}]`
     *
     * JSON fields:
     *   - `fieldApiName: string` - Opportunity lookup field API name rendered in the preview panel.
     *   - `recordId: string` - selected lookup record Id that should be displayed by name.
     *
     * @example
     * `[{"fieldApiName":"Fund__c","recordId":"a0Uxx0000000001AAA"}]`
     *
     * @return Returns `List<LookupDisplayValue>` where each item contains the original field API name,
     * the lookup record Id, the resolved record name when available, and the target object API name.
    **/
    private static List<LookupDisplayValue> m_resolvePreviewLookupDisplayValues(String lookupFieldValueEntriesJson) {
        List<LookupDisplayValue> lookupDisplayValues = new List<LookupDisplayValue>();

        if (String.isBlank(lookupFieldValueEntriesJson)) {
            return lookupDisplayValues;
        }

        List<Object> rawLookupEntries = (List<Object>)JSON.deserializeUntyped(lookupFieldValueEntriesJson);
        Map<String, Set<Id>> idsByObjectApiName = new Map<String, Set<Id>>();
        Map<String, Schema.SObjectType> sObjectTypeByApiName = new Map<String, Schema.SObjectType>();

        for (Object rawLookupEntry : rawLookupEntries) {
            Map<String, Object> rawLookupEntryMap = (Map<String, Object>)rawLookupEntry;
            String fieldApiName = (String)rawLookupEntryMap.get('fieldApiName');
            String recordId = (String)rawLookupEntryMap.get('recordId');

            if (String.isBlank(fieldApiName) || String.isBlank(recordId)) {
                continue;
            }

            Id lookupRecordId = (Id)recordId;
            Schema.SObjectType sObjectType = lookupRecordId.getSObjectType();
            String objectApiName = sObjectType.getDescribe().getName();

            lookupDisplayValues.add(new LookupDisplayValue(fieldApiName, recordId, recordId, objectApiName));

            if (!idsByObjectApiName.containsKey(objectApiName)) {
                idsByObjectApiName.put(objectApiName, new Set<Id>());
                sObjectTypeByApiName.put(objectApiName, sObjectType);
            }

            idsByObjectApiName.get(objectApiName).add(lookupRecordId);
        }

        Map<Id, String> nameByRecordId = new Map<Id, String>();

        for (String objectApiName : idsByObjectApiName.keySet()) {
            Schema.DescribeSObjectResult sObjectDescribe = sObjectTypeByApiName.get(objectApiName).getDescribe();
            Set<Id> objectRecordIds = idsByObjectApiName.get(objectApiName);
            Map<String, Schema.SObjectField> fieldsByApiName = sObjectDescribe.fields.getMap();
            String nameFieldApiName = fieldsByApiName.containsKey('Name')
                ? 'Name'
                : (fieldsByApiName.containsKey('Subject') ? 'Subject' : null);

            if (String.isBlank(nameFieldApiName)) {
                continue;
            }
            String soqlQuery =
                'SELECT Id, ' +
                nameFieldApiName +
                ' FROM ' +
                objectApiName +
                ' WHERE Id IN :objectRecordIds';

            for (SObject resolvedRecord : Database.query(soqlQuery)) {
                nameByRecordId.put((Id)resolvedRecord.get('Id'), String.valueOf(resolvedRecord.get(nameFieldApiName)));
            }
        }

        for (LookupDisplayValue lookupDisplayValue : lookupDisplayValues) {
            lookupDisplayValue.recordName =
                nameByRecordId.get((Id)lookupDisplayValue.recordId) == null
                    ? lookupDisplayValue.recordId
                    : nameByRecordId.get((Id)lookupDisplayValue.recordId);
        }

        return lookupDisplayValues;
    }

    /**
     * Returns fallback values for required Request Opportunity fields that are missing from the step-3 payload.
     *
     * @param preparedOpportunityValues Shared Opportunity values collected on step 3.
     * @param opportunityFieldsByApiName Describe metadata keyed by Opportunity field API name.
     *
     * @example
     * If one required custom field is not present in the field set, this method samples the latest existing Request Opportunity.
     *
     * @return Returns best-effort fallback values for missing required createable fields.
    **/
    private static Map<String, Object> m_getMissingRequiredOpportunityDefaultValues(
        Map<String, Object> preparedOpportunityValues,
        Map<String, Schema.SObjectField> opportunityFieldsByApiName
    ) {
        Set<String> missingRequiredFieldApiNames = m_getMissingRequiredOpportunityFieldApiNames(
            preparedOpportunityValues,
            opportunityFieldsByApiName
        );
        Map<String, Object> defaultValuesByFieldApiName = new Map<String, Object>();

        if (missingRequiredFieldApiNames.isEmpty()) {
            return defaultValuesByFieldApiName;
        }

        Id requestRecordTypeId = m_getRequestRecordTypeId();
        String queryText =
            'SELECT ' + String.join(new List<String>(missingRequiredFieldApiNames), ',') +
            ' FROM Opportunity WHERE RecordTypeId = :requestRecordTypeId ORDER BY LastModifiedDate DESC LIMIT :REQUEST_DEFAULT_SAMPLE_LIMIT';
        List<SObject> sampleRequestOpportunities = Database.query(queryText);

        if (sampleRequestOpportunities.isEmpty()) {
            System.debug('m_getMissingRequiredOpportunityDefaultValues no sample Request Opportunity found');
            return defaultValuesByFieldApiName;
        }

        SObject sampleRequestOpportunity = sampleRequestOpportunities[0];

        for (String fieldApiName : missingRequiredFieldApiNames) {
            Object fieldValue = sampleRequestOpportunity.get(fieldApiName);

            if (fieldValue != null) {
                defaultValuesByFieldApiName.put(fieldApiName, fieldValue);
            }
        }

        System.debug('m_getMissingRequiredOpportunityDefaultValues missingRequiredFieldApiNames=' + missingRequiredFieldApiNames);
        System.debug('m_getMissingRequiredOpportunityDefaultValues defaultValuesByFieldApiName=' + defaultValuesByFieldApiName);
        return defaultValuesByFieldApiName;
    }

    /**
     * Returns required createable Opportunity field API names that are still missing from the prepared payload.
     *
     * @param preparedOpportunityValues Shared Opportunity values collected on step 3.
     * @param opportunityFieldsByApiName Describe metadata keyed by Opportunity field API name.
     *
     * @example
     * Required custom fields omitted from the field set are returned here so they can be defaulted before insert.
     *
     * @return Returns missing required field API names that should be defaulted before Opportunity creation.
    **/
    private static Set<String> m_getMissingRequiredOpportunityFieldApiNames(
        Map<String, Object> preparedOpportunityValues,
        Map<String, Schema.SObjectField> opportunityFieldsByApiName
    ) {
        Set<String> missingRequiredFieldApiNames = new Set<String>();
        Set<String> ignoredFieldApiNames = new Set<String>{
            'Id',
            'Name',
            'AccountId',
            'RecordTypeId',
            PRIMARY_CONTACT_FIELD_API_NAME,
            REQUESTED_AMOUNT_FIELD_API_NAME
        };

        for (String fieldApiName : opportunityFieldsByApiName.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = opportunityFieldsByApiName.get(fieldApiName).getDescribe();

            if (
                ignoredFieldApiNames.contains(fieldApiName) ||
                preparedOpportunityValues.containsKey(fieldApiName) ||
                !fieldDescribe.isCreateable() ||
                fieldDescribe.isCalculated() ||
                fieldDescribe.isNillable() ||
                fieldDescribe.isDefaultedOnCreate()
            ) {
                continue;
            }

            missingRequiredFieldApiNames.add(fieldApiName);
        }

        return missingRequiredFieldApiNames;
    }

    /**
     * Applies one Opportunity field value when the field exists and is createable.
     *
     * @param opportunityRecord Opportunity record being prepared for insert.
     * @param fieldApiName Target Opportunity field API name.
     * @param rawValue Raw field value before final type-aware casting.
     * @param opportunityFieldsByApiName Describe metadata keyed by Opportunity field API name.
     *
     * @example
     * `fieldApiName = "CloseDate"` and `rawValue = "2026-03-31"` results in a typed `Date` value on the record.
     *
     * @return Returns nothing. Mutates the supplied Opportunity record in place.
    **/
    private static void m_setOpportunityCreateValue(
        Opportunity opportunityRecord,
        String fieldApiName,
        Object rawValue,
        Map<String, Schema.SObjectField> opportunityFieldsByApiName
    ) {
        if (
            opportunityRecord == null ||
            String.isBlank(fieldApiName) ||
            !opportunityFieldsByApiName.containsKey(fieldApiName)
        ) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe = opportunityFieldsByApiName.get(fieldApiName).getDescribe();

        if (!fieldDescribe.isCreateable()) {
            return;
        }

        Object typedFieldValue = m_castFieldValue(rawValue, fieldDescribe);

        if (typedFieldValue == null) {
            return;
        }

        opportunityRecord.put(fieldApiName, typedFieldValue);
    }

    /**
     * Builds one generated Request Opportunity name that is unique enough for chunked creation.
     *
     * @param sequenceNumber Sequence number inside the current create flow.
     *
     * @example
     * `m_buildRequestOpportunityName(12)` may return `Request Opportunity 20260310170201-12`.
     *
     * @return Returns the generated Opportunity Name.
    **/
    private static String m_buildRequestOpportunityName(Integer sequenceNumber) {
        return REQUEST_OPPORTUNITY_NAME_PREFIX +
            Datetime.now().formatGmt('yyyyMMddHHmmss') +
            '-' + String.valueOf(sequenceNumber) +
            '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    /**
     * Parses a JSON object into an untyped map.
     *
     * @param jsonObjectText JSON object string.
     *
     * @example
     * `"{\"StageName\":\"New\",\"Amount\":1000}"`
     *
     * @return Returns an untyped key/value map, or an empty map when the input is blank.
    **/
    private static Map<String, Object> m_parseUntypedObjectMap(String jsonObjectText) {
        if (String.isBlank(jsonObjectText)) {
            return new Map<String, Object>();
        }

        return (Map<String, Object>)JSON.deserializeUntyped(jsonObjectText);
    }

    /**
     * Parses a JSON array of Salesforce ids into a list that preserves incoming order.
     *
     * @param idsJson JSON array string with Salesforce ids.
     *
     * @example
     * `"[\"001xx0000000001AAA\",\"001xx0000000002AAA\"]"`
     *
     * @return Returns a list of valid Salesforce ids parsed from the JSON array in the same order.
    **/
    private static List<Id> m_parseIdList(String idsJson) {
        List<Id> parsedIds = new List<Id>();

        if (String.isBlank(idsJson)) {
            return parsedIds;
        }

        for (Object idValue : (List<Object>)JSON.deserializeUntyped(idsJson)) {
            String idText = String.valueOf(idValue);

            if (!String.isBlank(idText)) {
                parsedIds.add((Id)idText);
            }
        }

        return parsedIds;
    }

    /**
     * Builds one readable debug string with sampled execution rows.
     *
     * @param executionRows Execution rows collected during create or chunk refresh processing.
     * @param sampleLimit Maximum number of rows to include in the returned string.
     *
     * @example
     * `m_describeExecutionRowSamples(new List<ExecutionRow>(), 10)`
     *
     * @return Returns a compact textual sample of Opportunity/Account/Payment row values for debug logs.
    **/
    private static String m_describeExecutionRowSamples(List<ExecutionRow> executionRows, Integer sampleLimit) {
        List<String> rowSamples = new List<String>();

        if (executionRows == null || executionRows.isEmpty()) {
            return '[]';
        }

        Integer normalizedSampleLimit = sampleLimit == null || sampleLimit <= 0
            ? executionRows.size()
            : sampleLimit;

        for (ExecutionRow executionRow : executionRows) {
            if (rowSamples.size() >= normalizedSampleLimit) {
                break;
            }

            rowSamples.add(
                'opportunityId=' + String.valueOf(executionRow.opportunityId) +
                ', opportunityName=' + String.valueOf(executionRow.opportunityName) +
                ', accountId=' + String.valueOf(executionRow.accountId) +
                ', accountName=' + String.valueOf(executionRow.accountName) +
                ', paymentId=' + String.valueOf(executionRow.paymentId) +
                ', paymentName=' + String.valueOf(executionRow.paymentName) +
                ', status=' + String.valueOf(executionRow.status) +
                ', errorMessage=' + String.valueOf(executionRow.errorMessage)
            );
        }

        return '[' + String.join(rowSamples, ' | ') + ']';
    }

    // -------------------------------
    // Public Helper Classes
    // -------------------------------

    /**
     * Selector request wrapper for Aura-enabled methods with input.
    **/
    public class Request {
        /** Report Id selected in the modal. */
        @AuraEnabled public String reportId;

        /** JSON array of selected report rows used by the preview step. */
        @AuraEnabled public String selectedReportRowsJson;

        /** Selected creation strategy API name. */
        @AuraEnabled public String creationStrategy;

        /** JSON array with up to five duplicate-filter conditions. */
        @AuraEnabled public String comparisonConditionsJson;

        /** Boolean formula that combines the numbered duplicate-filter conditions. */
        @AuraEnabled public String comparisonFormulaText;

        /** JSON object with the prepared shared Opportunity field values. */
        @AuraEnabled public String opportunityFieldValuesJson;

        /** JSON object with the final shared Opportunity field values used during chunked creation. */
        @AuraEnabled public String preparedOpportunityJson;

        /** JSON array of Account ids processed by the current create chunk. */
        @AuraEnabled public String accountIdsJson;

        /** JSON array of created Opportunity ids refreshed by the current post-create chunk read. */
        @AuraEnabled public String opportunityIdsJson;

        /** JSON array of Payment ids processed by the current payment-update chunk. */
        @AuraEnabled public String paymentIdsJson;

        /** JSON array of preview lookup entries that should be resolved into record names. */
        @AuraEnabled public String lookupFieldValueEntriesJson;
    }

    /**
     * Selector response wrapper for Aura-enabled modal methods.
    **/
    public class Response {
        /** Indicates whether the operation succeeded. */
        @AuraEnabled public Boolean isSuccess;

        /** Error message returned to the LWC when the operation fails. */
        @AuraEnabled public String errorMessage;

        /** Indicates whether the scanned report remains supported for this feature. */
        @AuraEnabled public Boolean isSupportedReport;

        /** Initial report rows returned to the modal. */
        @AuraEnabled public List<SelectorOption> availableReports;

        /** Refreshed report row returned after one report scan. */
        @AuraEnabled public SelectorOption reportData;

        /** Server-driven modal configuration returned by `getConfig()`. */
        @AuraEnabled public Config config;

        /** Preview payload returned for the approval step. */
        @AuraEnabled public PreviewData previewData;

        /** Create payload returned for one final Opportunity-create chunk. */
        @AuraEnabled public CreationChunkData creationChunkData;

        /** Refresh payload returned for one created-Opportunity refresh cycle. */
        @AuraEnabled public RefreshChunkData refreshChunkData;

        /** Payment-update payload returned for one payment-update chunk. */
        @AuraEnabled public PaymentUpdateData paymentUpdateData;

        /** Resolved preview lookup display values returned for the step-4 read-only panel. */
        @AuraEnabled public List<LookupDisplayValue> lookupDisplayValues;
    }

    /**
     * Server-driven modal configuration returned to the LWC wizard.
    **/
    public class Config {
        /** Opportunity Request record type developer name. */
        @AuraEnabled public String requestRecordTypeDeveloperName;

        /** Opportunity Request record type Id. */
        @AuraEnabled public Id requestRecordTypeId;

        /** Extra StageName values forced into the LWC form even if the record type omits them. */
        @AuraEnabled public List<String> additionalStageValues;

        /** Opportunity field descriptors rendered on step 3 in field-set order. */
        @AuraEnabled public List<FieldConfig> requestFieldSetFields;

        /** StageName options rendered by the custom step-3 combobox. */
        @AuraEnabled public List<OptionConfig> requestStageOptions;
    }

    /**
     * One field descriptor returned by `getConfig()` for the custom step-3 Request form.
    **/
    public class FieldConfig {
        /** Opportunity field API name. */
        @AuraEnabled public String apiName;

        /** Admin-facing field label resolved from the configured field set. */
        @AuraEnabled public String label;

        /** Indicates whether the field should be treated as required on the custom step-3 form. */
        @AuraEnabled public Boolean isRequired;

        /**
         * Creates one field descriptor.
         *
         * @param apiName Opportunity field API name.
         * @param label Admin-facing field label resolved from the configured field set.
         * @param isRequired Indicates whether the field should be treated as required on the custom step-3 form.
         *
         * @example
         * `new FieldConfig('StageName', 'Stage', true)`
         *
         * @return Returns the initialized field descriptor used by the custom step-3 form.
        **/
        public FieldConfig(String apiName, String label, Boolean isRequired) {
            this.apiName = apiName;
            this.label = label;
            this.isRequired = isRequired;
        }
    }

    /**
     * One label/value option returned by `getConfig()` for custom combobox rendering.
    **/
    public class OptionConfig {
        /** Option label shown in the UI. */
        @AuraEnabled public String label;

        /** Option value submitted back by the UI. */
        @AuraEnabled public String value;

        /**
         * Creates one combobox option.
         *
         * @param label Option label shown in the UI.
         * @param value Option value submitted back by the UI.
         *
         * @example
         * `new OptionConfig('Ready for transfer to ERP', 'Ready for transfer to ERP')`
         *
         * @return Returns the initialized combobox option used by the custom step-3 form.
        **/
        public OptionConfig(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /**
     * One resolved preview lookup display value returned for the step-4 read-only panel.
    **/
    public class LookupDisplayValue {
        /** Opportunity lookup field API name. */
        @AuraEnabled public String fieldApiName;

        /** Lookup record Id. */
        @AuraEnabled public String recordId;

        /** Lookup record display name resolved from the target object. */
        @AuraEnabled public String recordName;

        /** Lookup target object API name used to build the record URL in LWC. */
        @AuraEnabled public String recordApiName;

        /**
         * Creates one resolved preview lookup display value.
         *
         * @param fieldApiName Opportunity lookup field API name.
         * @param recordId Lookup record Id.
         * @param recordName Lookup record display name.
         * @param recordApiName Lookup target object API name.
         *
         * @example
         * `new LookupDisplayValue('Fund__c', 'a0Uxx0000000001AAA', 'Education Fund', 'npo02__Fund__c')`
         *
         * @return Returns the initialized preview lookup display value.
        **/
        public LookupDisplayValue(String fieldApiName, String recordId, String recordName, String recordApiName) {
            this.fieldApiName = fieldApiName;
            this.recordId = recordId;
            this.recordName = recordName;
            this.recordApiName = recordApiName;
        }
    }

    /**
     * One modal datatable row returned from Apex.
    **/
    public class SelectorOption {
        /** Report Id. */
        @AuraEnabled public String value;

        /** Display label including the folder name when present. */
        @AuraEnabled public String label;

        /** Plain report name without the folder suffix. */
        @AuraEnabled public String shortLabel;

        /** Raw Analytics report type. */
        @AuraEnabled public String reportType;

        /** Unique Account count found in the report. */
        @AuraEnabled public Integer accountCount;

        /** Eligible Account count after filtering. */
        @AuraEnabled public Integer eligibleAccountCount;

        /** JSON array of all unique Account Ids found in the report. */
        @AuraEnabled public String accountIdsJson;

        /** JSON array of eligible Account Ids found in the report. */
        @AuraEnabled public String eligibleAccountIdsJson;

        /** Indicates whether the report type is supported for Account extraction. */
        @AuraEnabled public Boolean isSupportedType;

        /**
         * Creates one modal datatable row.
         *
         * @param value Report Id.
         * @param label Display label including folder when present.
         * @param shortLabel Plain report name.
         * @param reportType Raw Analytics report type.
         * @param accountCount Unique Account count.
         * @param eligibleAccountCount Eligible Account count.
         * @param accountIdsJson JSON array of all unique Account Ids.
         * @param eligibleAccountIdsJson JSON array of eligible Account Ids.
         * @param isSupportedType Indicates whether the report type is supported for Account extraction.
         *
         * @example
         * `new SelectorOption("00O...","Report Name (Folder)","Report Name","AccountList",12,8,"[\"001...\"]","[\"001...\"]",true)`
         *
         * @return Returns a fully initialized row object for the modal datatable.
        **/
        public SelectorOption(
            String value,
            String label,
            String shortLabel,
            String reportType,
            Integer accountCount,
            Integer eligibleAccountCount,
            String accountIdsJson,
            String eligibleAccountIdsJson,
            Boolean isSupportedType
        ) {
            this.value = value;
            this.label = label;
            this.shortLabel = shortLabel;
            this.reportType = reportType;
            this.accountCount = accountCount;
            this.eligibleAccountCount = eligibleAccountCount;
            this.accountIdsJson = accountIdsJson;
            this.eligibleAccountIdsJson = eligibleAccountIdsJson;
            this.isSupportedType = isSupportedType;
        }
    }

    /**
     * Final preview payload returned for the approval step.
    **/
    public class PreviewData {
        /** Number of Opportunities that would be created. */
        @AuraEnabled public Integer opportunityCount;

        /** Number of Accounts that would receive Opportunities. */
        @AuraEnabled public Integer accountCount;

        /** JSON array of creatable Account ids after preview filtering. */
        @AuraEnabled public String accountIdsJson;

        /** Preview rows shown in the approval table. */
        @AuraEnabled public List<PreviewRow> previewRows;

        /**
         * Creates one preview payload.
         *
         * @param opportunityCount Number of Opportunities that would be created.
         * @param accountCount Number of Accounts that would receive Opportunities.
         * @param accountIdsJson JSON array of creatable Account ids.
         * @param previewRows Preview rows shown in the approval table.
         *
         * @example
         * `new PreviewData(3, 3, "[\"001...\"]", new List<PreviewRow>())`
         *
         * @return Returns the initialized preview payload for the approval step.
        **/
        public PreviewData(
            Integer opportunityCount,
            Integer accountCount,
            String accountIdsJson,
            List<PreviewRow> previewRows
        ) {
            this.opportunityCount = opportunityCount;
            this.accountCount = accountCount;
            this.accountIdsJson = accountIdsJson;
            this.previewRows = previewRows;
        }
    }

    /**
     * One preview row shown in the approval step table.
    **/
    public class PreviewRow implements Comparable {
        /** Source report id. */
        @AuraEnabled public String reportId;

        /** Source report name. */
        @AuraEnabled public String reportName;

        /** Account id that will receive the Opportunity. */
        @AuraEnabled public Id accountId;

        /** Account name that will receive the Opportunity. */
        @AuraEnabled public String accountName;

        /**
         * Creates one preview row.
         *
         * @param reportId Source report id.
         * @param reportName Source report name.
         * @param accountId Account id that will receive the Opportunity.
         * @param accountName Account name that will receive the Opportunity.
         *
         * @example
         * `new PreviewRow('00O...','Open Requests','001...','Acme Foundation')`
         *
         * @return Returns the initialized preview row shown in the approval table.
        **/
        public PreviewRow(String reportId, String reportName, Id accountId, String accountName) {
            this.reportId = reportId;
            this.reportName = reportName;
            this.accountId = accountId;
            this.accountName = accountName;
        }

        /**
         * Compares two preview rows for stable sorting.
         *
         * @param otherObject Another preview row.
         *
         * @example
         * `previewRow.compareTo(otherPreviewRow)`
         *
         * @return Returns the comparison result by report name and then Account name.
        **/
        public Integer compareTo(Object otherObject) {
            PreviewRow otherPreviewRow = (PreviewRow)otherObject;
            Integer reportComparison = String.valueOf(this.reportName).toLowerCase()
                .compareTo(String.valueOf(otherPreviewRow.reportName).toLowerCase());

            if (reportComparison != 0) {
                return reportComparison;
            }

            return String.valueOf(this.accountName).toLowerCase()
                .compareTo(String.valueOf(otherPreviewRow.accountName).toLowerCase());
        }
    }

    /**
     * One execution row used during chunked creation and later rendered on the final Done table.
    **/
    public class ExecutionRow {
        /** Created Opportunity id. */
        @AuraEnabled public Id opportunityId;

        /** Created Opportunity name. */
        @AuraEnabled public String opportunityName;

        /** Related Account id. */
        @AuraEnabled public Id accountId;

        /** Related Account name. */
        @AuraEnabled public String accountName;

        /** Related Payment id when found. */
        @AuraEnabled public Id paymentId;

        /** Related Payment name when found. */
        @AuraEnabled public String paymentName;

        /** Final row status literal consumed by the Done table. */
        @AuraEnabled public String status;

        /** Human-readable row error message for create/payment failures. */
        @AuraEnabled public String errorMessage;

        /**
         * Creates one execution row.
         *
         * @param opportunityId Created Opportunity id.
         * @param opportunityName Created Opportunity name.
         * @param accountId Related Account id.
         * @param accountName Related Account name.
         * @param paymentId Related Payment id when found.
         * @param paymentName Related Payment name when found.
         * @param status Final row status literal consumed by the Done table.
         * @param errorMessage Human-readable row error message for create/payment failures.
         *
         * @example
         * `new ExecutionRow('006...','Request Opportunity 20260310-1','001...','Acme Foundation','a01...','Payment-0001','success','')`
         *
         * @return Returns the initialized execution row used by the final processing flow.
        **/
        public ExecutionRow(
            Id opportunityId,
            String opportunityName,
            Id accountId,
            String accountName,
            Id paymentId,
            String paymentName,
            String status,
            String errorMessage
        ) {
            this.opportunityId = opportunityId;
            this.opportunityName = opportunityName;
            this.accountId = accountId;
            this.accountName = accountName;
            this.paymentId = paymentId;
            this.paymentName = paymentName;
            this.status = status;
            this.errorMessage = errorMessage;
        }
    }

    /**
     * Result payload returned by one create-opportunities chunk.
    **/
    public class CreationChunkData {
        /** Number of Account ids received in the chunk. */
        @AuraEnabled public Integer requestedAccountCount;

        /** Number of Opportunities inserted successfully in the chunk. */
        @AuraEnabled public Integer createdOpportunityCount;

        /** Number of Accounts that failed Opportunity creation in the chunk. */
        @AuraEnabled public Integer failedAccountCount;

        /** JSON array of created Opportunity ids. */
        @AuraEnabled public String createdOpportunityIdsJson;

        /** Created execution rows for the final Done table. */
        @AuraEnabled public List<ExecutionRow> rows;

        /** Row-level Opportunity creation errors. */
        @AuraEnabled public List<String> errors;

        /**
         * Creates one chunk-create payload.
         *
         * @param requestedAccountCount Number of Account ids received in the chunk.
         * @param createdOpportunityCount Number of Opportunities inserted successfully in the chunk.
         * @param failedAccountCount Number of Accounts that failed Opportunity creation in the chunk.
         * @param createdOpportunityIdsJson JSON array of created Opportunity ids.
         * @param rows Created execution rows for the final Done table.
         * @param errors Row-level Opportunity creation errors.
         *
         * @example
         * `new CreationChunkData(25, 24, 1, "[\"006...\"]", new List<ExecutionRow>(), new List<String>())`
         *
         * @return Returns the initialized chunk-create payload for the final Opportunity-create flow.
        **/
        public CreationChunkData(
            Integer requestedAccountCount,
            Integer createdOpportunityCount,
            Integer failedAccountCount,
            String createdOpportunityIdsJson,
            List<ExecutionRow> rows,
            List<String> errors
        ) {
            this.requestedAccountCount = requestedAccountCount;
            this.createdOpportunityCount = createdOpportunityCount;
            this.failedAccountCount = failedAccountCount;
            this.createdOpportunityIdsJson = createdOpportunityIdsJson;
            this.rows = rows;
            this.errors = errors;
        }
    }

    /**
     * Result payload returned by one created-Opportunity refresh cycle.
    **/
    public class RefreshChunkData {
        /** Number of Opportunity ids refreshed in the current chunk. */
        @AuraEnabled public Integer requestedOpportunityCount;

        /** Number of related Payments found in the current refresh. */
        @AuraEnabled public Integer foundPaymentCount;

        /** JSON array of found Payment ids. */
        @AuraEnabled public String foundPaymentIdsJson;

        /** Execution rows enriched with the latest Opportunity and Payment names. */
        @AuraEnabled public List<ExecutionRow> rows;

        /**
         * Creates one refresh payload.
         *
         * @param requestedOpportunityCount Number of Opportunity ids refreshed in the current chunk.
         * @param foundPaymentCount Number of related Payments found in the current refresh.
         * @param foundPaymentIdsJson JSON array of found Payment ids.
         * @param rows Execution rows enriched with the latest Opportunity and Payment names.
         *
         * @example
         * `new RefreshChunkData(10, 7, "[\"a01...\"]", new List<ExecutionRow>())`
         *
         * @return Returns the initialized refresh payload for the final Opportunity-create flow.
        **/
        public RefreshChunkData(
            Integer requestedOpportunityCount,
            Integer foundPaymentCount,
            String foundPaymentIdsJson,
            List<ExecutionRow> rows
        ) {
            this.requestedOpportunityCount = requestedOpportunityCount;
            this.foundPaymentCount = foundPaymentCount;
            this.foundPaymentIdsJson = foundPaymentIdsJson;
            this.rows = rows;
        }
    }

    /**
     * Result payload returned by one payment-update chunk.
    **/
    public class PaymentUpdateData {
        /** Number of Payment ids received in the chunk. */
        @AuraEnabled public Integer requestedPaymentCount;

        /** Number of Payments updated successfully in the chunk. */
        @AuraEnabled public Integer updatedPaymentCount;

        /** Number of Payments skipped or not updated in the chunk. */
        @AuraEnabled public Integer skippedPaymentCount;

        /** JSON array of updated Payment ids. */
        @AuraEnabled public String updatedPaymentIdsJson;

        /** Execution rows enriched with Payment-update failures. */
        @AuraEnabled public List<ExecutionRow> rows;

        /** Row-level Payment update errors. */
        @AuraEnabled public List<String> errors;

        /**
         * Creates one payment-update payload.
         *
         * @param requestedPaymentCount Number of Payment ids received in the chunk.
         * @param updatedPaymentCount Number of Payments updated successfully in the chunk.
         * @param skippedPaymentCount Number of Payments skipped or not updated in the chunk.
         * @param updatedPaymentIdsJson JSON array of updated Payment ids.
         * @param rows Execution rows enriched with Payment-update failures.
         * @param errors Row-level Payment update errors.
         *
         * @example
         * `new PaymentUpdateData(7, 7, 0, "[\"a01...\"]", new List<ExecutionRow>(), new List<String>())`
         *
         * @return Returns the initialized payment-update payload for the final Opportunity-create flow.
        **/
        public PaymentUpdateData(
            Integer requestedPaymentCount,
            Integer updatedPaymentCount,
            Integer skippedPaymentCount,
            String updatedPaymentIdsJson,
            List<ExecutionRow> rows,
            List<String> errors
        ) {
            this.requestedPaymentCount = requestedPaymentCount;
            this.updatedPaymentCount = updatedPaymentCount;
            this.skippedPaymentCount = skippedPaymentCount;
            this.updatedPaymentIdsJson = updatedPaymentIdsJson;
            this.rows = rows;
            this.errors = errors;
        }
    }

    // -------------------------------
    // Private Helper Classes
    // -------------------------------

    /**
     * Internal report extraction result used during one-report scans.
    **/
    private class ReportExtractionResult {
        /** Report name. */
        private String reportName;

        /** Unique Account Ids extracted from the report. */
        private Set<Id> accountIds;

        /**
         * Creates one extraction result.
         *
         * @param reportName Report name.
         * @param accountIds Extracted Account Ids.
         *
         * @example
         * `new ReportExtractionResult("Open Requests", new Set<Id>{})`
         *
         * @return Returns the initialized extraction result used by the controller.
        **/
        private ReportExtractionResult(String reportName, Set<Id> accountIds) {
            this.reportName = reportName;
            this.accountIds = accountIds;
        }
    }

    /**
     * Internal report type descriptor used while deciding whether extraction is supported.
    **/
    private class ReportTypeDescriptor {
        /** Raw report type value inferred from report metadata. */
        private String reportType;

        /** Indicates whether this report type supports Account extraction. */
        private Boolean isSupportedType;

        /**
         * Creates one report type descriptor.
         *
         * @param reportType Raw report type value inferred from report metadata.
         * @param isSupportedType Indicates whether this report type supports Account extraction.
         *
         * @example
         * `new ReportTypeDescriptor("AccountList", true)`
         *
         * @return Returns the initialized report type descriptor used by the controller.
        **/
        private ReportTypeDescriptor(String reportType, Boolean isSupportedType) {
            this.reportType = reportType;
            this.isSupportedType = isSupportedType;
        }
    }

    /**
     * Lightweight selected-report row shape used only by the preview request payload.
    **/
    private class PreviewSelectionRow {
        /** Report id. */
        private String value;

        /** Full display label. */
        private String label;

        /** Short report name. */
        private String shortLabel;

        /** JSON array of eligible Account ids for the report. */
        private String eligibleAccountIdsJson;
    }

    /**
     * Raw duplicate-filter condition parsed from the step-2 LWC payload.
    **/
    private class ComparisonCondition {
        /** Visual row number used by the formula builder. */
        private Integer rowNumber;

        /** Opportunity field API name selected on step 2. */
        private String fieldApiName;

        /** Operator literal selected on step 2. */
        private String operator;

        /** Raw comparison value entered on step 2 as text or null before type-aware casting. */
        private String value;
    }

    /**
     * Prepared duplicate-filter condition with a typed comparison value ready for runtime evaluation.
    **/
    private class PreparedComparisonCondition {
        /** Visual row number used by the formula builder. */
        private Integer rowNumber;

        /** Opportunity field API name selected on step 2. */
        private String fieldApiName;

        /** Operator literal selected on step 2. */
        private String operator;

        /** Typed comparison value ready for field-type-aware comparison. */
        private Object value;

        /** Salesforce display type of the compared Opportunity field. */
        private Schema.DisplayType displayType;

        /**
         * Creates one prepared comparison condition.
         *
         * @param rowNumber Visual row number used by the formula builder.
         * @param fieldApiName Opportunity field API name selected on step 2.
         * @param operator Operator literal selected on step 2.
         * @param value Typed comparison value ready for field-type-aware comparison.
         * @param displayType Salesforce display type of the compared Opportunity field.
         *
         * @example
         * `new PreparedComparisonCondition(1, 'StageName', 'equals', 'New', Schema.DisplayType.PICKLIST)`
         *
         * @return Returns the initialized prepared comparison condition used during preview filtering.
        **/
        private PreparedComparisonCondition(
            Integer rowNumber,
            String fieldApiName,
            String operator,
            Object value,
            Schema.DisplayType displayType
        ) {
            this.rowNumber = rowNumber;
            this.fieldApiName = fieldApiName;
            this.operator = operator;
            this.value = value;
            this.displayType = displayType;
        }
    }

    /**
     * Internal exception used to stop preview evaluation when comparison formula input is invalid.
    **/
    private class CreateOpportunitiesFromReportsControllerException extends Exception {
    }

    /**
     * Test-only synthetic report definition used to cover report-selection logic without org report records.
    **/
    private class TestReportDefinition {
        /** Fake Report Id used by the LWC/controller contract. */
        private String reportId;

        /** Report name shown in the selector. */
        private String reportName;

        /** Optional folder label appended to the report display name. */
        private String folderName;

        /** Synthetic report format literal such as `TABULAR` or `MULTI_BLOCK`. */
        private String reportFormat;

        /** Synthetic detail column API names used by type inference and row parsing. */
        private List<String> detailColumns;

        /** Synthetic row values aligned with `detailColumns`. */
        private List<List<Object>> rows;
    }
}
