/**
@author: Haim Knokh
@date: 2026-03-08
@modified: 2026-03-11
@description: LightningModal that implements the Create Opportunities From Reports wizard as a standalone popup.
*
* UI Responsibilities And Behavior
* =========================
* This modal currently renders the full five-step wizard:
*   - searchable and sortable report-selection table
*   - concurrent account retrieval per selected report
*   - duplicate-check strategy builder with numbered conditions and boolean formula
*   - server-driven Request Opportunity details form based on controller config
*   - preview screen with readonly Opportunity values and Account selection
*   - inline Opportunity creation flow with chunk progress and abort support
*   - final readonly results table for Account, Opportunity, Payment, status, and errors
*   - state restore for steps 1-3 when navigating back
*
* Parent Integration Contract
* =========================
*
* Inputs:
*   - `tableHeight: string` - optional table body height, for example `400px`.
*
* Output:
*   - none; the component does not expose any container-facing `@api` output members.
*
* @example
*   - `{"tableHeight":"400px"}`
*
* @return
*   - no container-facing return payload exists through `@api`; modal close payload is internal modal behavior, not parent `@api` surface.
*
* Internal Component Contract
* =========================
*
* Internal modal close payload:
*   - `action: string` - modal result action, for example `finish` or `cancel`.
*   - `executionRowsJson: string` - JSON array with final Account/Opportunity/Payment execution rows shown on the Done step.
*   - `createdOpportunityCount: number` - number of successfully created Opportunities.
*   - `failedOpportunityCount: number` - number of failed Opportunity creates.
*   - `createdPaymentCount: number` - number of Payments found and treated as created.
*   - `updatedPaymentCount: number` - number of successfully updated Payments.
*   - `failedPaymentCount: number` - number of failed Payment updates.
*
* Internal runtime state:
*   - tracks selected reports, eligible Accounts, preview rows, and final execution rows.
*   - coordinates content-level progress overlay separately from full-modal transition spinner.
*   - keeps step 1-3 state snapshots so Back restores the last user-entered values.
*
* Apex Contract
* =========================
* Called methods:
*   - `CreateOpportunitiesFromReportsController.getConfig()` - loads server-driven config such as the Request record type.
*   - `CreateOpportunitiesFromReportsController.getSelectorData()` - loads initial report rows without counters.
*   - `CreateOpportunitiesFromReportsController.retrieveReportAccounts(request)` - loads report type and counters for one report.
*   - `CreateOpportunitiesFromReportsController.getPreviewData(request)` - builds the preview rows and final creatable Account ids.
*   - `CreateOpportunitiesFromReportsController.resolvePreviewLookupDisplayValues(request)` - resolves preview lookup field ids into record names and target object API names.
*   - `CreateOpportunitiesFromReportsController.createOpportunitiesChunk(request)` - creates one final Opportunity chunk for the preview-step create flow.
*   - `CreateOpportunitiesFromReportsController.refreshCreatedOpportunityChunk(request)` - refreshes one already-created chunk to read the latest Opportunity names and already-created Payments.
*   - `CreateOpportunitiesFromReportsController.updatePaymentsChunk(request)` - updates found Payments from the related Opportunity values.
*   - `lightning/uiObjectInfoApi.getObjectInfo(Opportunity)` - resolves comparison field labels from Opportunity describe metadata.
*
* Localization Contract
* =========================
* All default UI text is stored in `CONSTANTS.UI.DEFAULT_LABELS`.
* Direction is resolved from `@salesforce/i18n/lang`.
* No Custom Labels are used by this modal.
**/
import { api, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import USER_LANGUAGE from '@salesforce/i18n/lang';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import OPPORTUNITY_OBJECT from '@salesforce/schema/Opportunity';
import createOpportunitiesChunk from '@salesforce/apex/CreateOpportunitiesFromReportsController.createOpportunitiesChunk';
import getConfig from '@salesforce/apex/CreateOpportunitiesFromReportsController.getConfig';
import getPreviewData from '@salesforce/apex/CreateOpportunitiesFromReportsController.getPreviewData';
import getSelectorData from '@salesforce/apex/CreateOpportunitiesFromReportsController.getSelectorData';
import refreshCreatedOpportunityChunk from '@salesforce/apex/CreateOpportunitiesFromReportsController.refreshCreatedOpportunityChunk';
import resolvePreviewLookupDisplayValues from '@salesforce/apex/CreateOpportunitiesFromReportsController.resolvePreviewLookupDisplayValues';
import retrieveReportAccounts from '@salesforce/apex/CreateOpportunitiesFromReportsController.retrieveReportAccounts';
import updatePaymentsChunk from '@salesforce/apex/CreateOpportunitiesFromReportsController.updatePaymentsChunk';

// -------------------------------
// Constants
// -------------------------------

/** Shared modal constants. */
const CONSTANTS = {
    /** Error-related constants. */
    ERRORS: {
        /** Separator used to join multiple platform error messages. */
        MESSAGES_SEPARATOR: '; '
    },
    /** CSS patch constants for base component overrides. */
    CSS: {
        /** Datatable style marker id used to avoid duplicate patch injection. */
        DATATABLE_PATCH_STYLE_ID: 'report-datatable-opacity-patch',
        /** Runtime CSS patch text that dims disabled datatable cells and removes report-link behavior. */
        DATATABLE_PATCH_CSS_TEXT: '.report-row-disabled-opacity{opacity:0.6;}.report-row-disabled-opacity a,.report-row-disabled-opacity button{text-decoration:none !important;color:inherit !important;cursor:default !important;}.report-row-disabled-opacity button{background:transparent;border:0;box-shadow:none;padding:0;font:inherit;line-height:inherit;}',
        /** Modal-body style marker id used to avoid duplicate overflow-hidden patch injection. */
        MODAL_BODY_PATCH_STYLE_ID: 'wizard-modal-body-overflow-patch',
        /** Runtime CSS patch text that removes the native lightning-modal-body scroll because the wizard computes all heights itself. */
        MODAL_BODY_PATCH_CSS_TEXT: '.slds-modal__content{overflow:hidden !important;}',
        /** Warning text color used by footer step warnings. */
        STEP_WARNING_TEXT_STYLE: 'color: var(--slds-g-color-warning-base-30, #8c4b02);'
    },
    /** JSON serialization constants. */
    JSON: {
        /** Empty JSON array string reused by the modal state. */
        EMPTY_ARRAY: '[]'
    },
    /** Display placeholder constants. */
    PLACEHOLDERS: {
        /** Default empty string shown when a table value has not been retrieved yet. */
        DASH: ''
    },
    /** Report status constants. */
    STATUS: {
        /** Report type for Account reports. */
        ACCOUNT: 'AccountList',
        /** Report type for Contact and Account reports. */
        CONTACTS_AND_ACCOUNTS: 'account_contact__c'
    },
    /** Table sort constants. */
    SORT: {
        /** Default sort direction. */
        DEFAULT_DIRECTION: 'asc',
        /** Default sort field. */
        DEFAULT_FIELD: 'shortLabel'
    },
    /** Retrieval constants. */
    REQUESTS: {
        /** Maximum number of parallel report retrieval requests. */
        MAX_CONCURRENT_RETRIEVALS: 5,
        /** Number of Account ids processed in one Opportunity-create chunk. */
        CREATE_OPPORTUNITIES_CHUNK_SIZE: 50,
        /** Number of Payment ids processed in one Payment-update chunk. */
        UPDATE_PAYMENTS_CHUNK_SIZE: 50
    },
    /** Opportunity-creation process constants. */
    PROCESS: {
        /** Final row-status literals shared with Apex execution rows. */
        ROW_STATUS: {
            /** Successful end-state row. */
            SUCCESS: 'success',
            /** Opportunity creation failed for the row. */
            FAILED_TO_CREATE_OPPORTUNITY: 'failedToCreateOpportunity',
            /** Payment update failed or was skipped for the row. */
            FAILED_TO_UPDATE_PAYMENT: 'failedToUpdatePayment'
        },
        /** Default sort field used by the final Done table. */
        DONE_DEFAULT_SORT_FIELD: 'opportunityName',
        /** Default sort direction used by the final Done table. */
        DONE_DEFAULT_SORT_DIRECTION: 'asc'
    },
    /** Manual confirmation-dialog constants. */
    CONFIRMATION: {
        /** Supported confirmation actions. */
        ACTIONS: {
            /** Starts the final Opportunity-creation flow from the preview step. */
            START_OPPORTUNITY_CREATION: 'startOpportunityCreation',
            /** Stops scheduling future Opportunity-create chunks while letting already-created rows finish payment processing. */
            ABORT_OPPORTUNITY_CREATION: 'abortOpportunityCreation'
        },
        /** Confirm-button variants keyed by action. */
        VARIANTS: {
            /** Confirm-button variant for starting the creation flow. */
            START_OPPORTUNITY_CREATION: 'brand',
            /** Confirm-button variant for aborting future create chunks. */
            ABORT_OPPORTUNITY_CREATION: 'destructive'
        }
    },
    /** Strategy-screen constants. */
    STRATEGY: {
        /** Strategy API name that always creates new Opportunities. */
        CREATE_ALWAYS: 'createAlways',
        /** Strategy API name that checks existing Opportunities by selected fields. */
        MATCH_SELECTED_FIELDS: 'matchSelectedFields',
        /** Maximum number of duplicate-filter conditions allowed on step 2. */
        MAX_CONDITION_COUNT: 5,
        /** Default comparison formula used when the condition builder starts. */
        DEFAULT_FORMULA: '1',
        /** Comparison-condition operator literals shared with Apex. */
        OPERATORS: {
            /** Equality operator literal. */
            EQUALS: 'equals',
            /** Not-equal operator literal. */
            NOT_EQUALS: 'notEquals',
            /** Greater-than operator literal. */
            GREATER_THAN: 'greaterThan',
            /** Greater-or-equal operator literal. */
            GREATER_OR_EQUAL: 'greaterOrEqual',
            /** Less-than operator literal. */
            LESS_THAN: 'lessThan',
            /** Less-or-equal operator literal. */
            LESS_OR_EQUAL: 'lessOrEqual',
            /** String contains operator literal. */
            CONTAINS: 'contains',
            /** String starts-with operator literal. */
            STARTS_WITH: 'startsWith'
        },
        /** Rendered comparison-value control types keyed by field category. */
        VALUE_TYPES: {
            /** Picklist-style value control. */
            PICKLIST: 'picklist',
            /** Boolean value control. */
            BOOLEAN: 'boolean',
            /** Numeric value control. */
            NUMBER: 'number',
            /** Text value control. */
            TEXT: 'text',
            /** Date value control. */
            DATE: 'date',
            /** Datetime value control. */
            DATETIME: 'datetime'
        }
    },
    /** Field-filter constants for the strategy screen. */
    FIELDS: {
        /** Opportunity Stage field API name overridden by a custom combobox on step 3. */
        STAGE_NAME: 'StageName'
    },
    /** DOM constants used by the transition-spinner polling logic. */
    DOM: {
        /** Template data-id values used by the step render polling mechanism. */
        DATA_IDS: {
            /** Report datatable data-id. */
            REPORT_DATATABLE: 'reportDatatable',
            /** Creation-strategy combobox data-id. */
            CREATION_STRATEGY_INPUT: 'creation-strategy-input',
            /** Comparison formula input data-id. */
            COMPARISON_FORMULA_INPUT: 'comparison-formula-input',
            /** Opportunity input-field data-id. */
            OPPORTUNITY_INPUT_FIELD: 'opportunity-input-field',
            /** Opportunity stage override input data-id. */
            OPPORTUNITY_STAGE_INPUT: 'opportunity-stage-input',
            /** Final Done results table data-id. */
            DONE_RESULTS_TABLE: 'done-results-table',
            /** Preview datatable data-id. */
            PREVIEW_DATATABLE: 'previewDatatable'
        }
    },
    /** Timer constants. */
    TIMERS: {
        /** Search debounce interval in milliseconds. */
        SEARCH_DEBOUNCE_MS: 250,
        /** Short defer used so the active transition spinner can paint before heavier step work starts. */
        TRANSITION_SPINNER_PAINT_MS: 16,
        /** Maximum number of polling cycles allowed while waiting for the target step to finish rendering. */
        MAX_TRANSITION_RENDER_POLL_CYCLES: 50,
        /** Polling interval used while waiting for the target step render targets to appear in DOM. */
        TRANSITION_RENDER_POLL_MS: 500,
        /** Fallback timeout used after all required DOM nodes appear but before the next renderedCallback arrives. */
        TRANSITION_RENDER_NEXT_CALLBACK_TIMEOUT_MS: 1000,
        /** Delay applied before a created Opportunity chunk enters the delayed Payment-refresh queue. */
        PAYMENT_REFRESH_INITIAL_DELAY_MS: 1000,
        /** Delay applied between chunk-local Payment refresh retries. */
        PAYMENT_REFRESH_RETRY_DELAY_MS: 1000,
        /** Maximum number of refresh attempts per created Opportunity chunk while waiting for related Payments. */
        MAX_PAYMENT_REFRESH_ATTEMPTS: 3,
        /** Short idle delay used while the Payment-refresh queue waits for newly finished Opportunity chunks. */
        PAYMENT_REFRESH_QUEUE_IDLE_MS: 100
    },
    /** Universal progress-bar constants. */
    PROGRESS: {
        /** Minimum supported progress percentage. */
        MIN_PERCENT: 0,
        /** Maximum supported progress percentage. */
        MAX_PERCENT: 100,
        /** Default centered progress label. */
        DEFAULT_LABEL: '0%'
    },
    /** Layout measurement constants. */
    LAYOUT: {
        /** Fixed reserved height of the bottom progress section, even when the progress bar itself is hidden. */
        PROGRESS_SECTION_HEIGHT_PX: 40,
        /** Short defer used before recalculating the dynamic content-section height after render or resize. */
        CONTENT_SECTION_MEASUREMENT_DEFER_MS: 0
    },
    /** Step configuration constants shared by step rendering, spinner behavior, and content scrolling. */
    STEP_CONFIG: {
        /** Supported spinner types used by the step-transition mechanism. */
        SPINNER_TYPES: {
            /** Global body-overlay spinner type. */
            GLOBAL: 'global'
        },
        /** Supported scroll modes for the dynamic content scrollable section. */
        SCROLLABLE_SECTION_MODES: {
            /** Outer scrollable section manages its own vertical auto-scroll. */
            AUTO: 'auto',
            /** Outer scrollable section stays non-scrollable because the step uses internal fixed-height panels. */
            INTERNAL: 'internal'
        },
        /** Target-step config that defines the complete per-step render, spinner, and scroll behavior. */
        STEP_CONFIG_BY_TARGET: {
            /** Step 1 transition config. */
            reportSelection: {
                /** Spinner type shown while the Report Selection step is rendering. */
                spinnerType: 'global',
                /** Scroll mode used by the shared scrollable content subsection for this step. */
                scrollableSectionMode: 'internal',
                /** Post-render delay applied after the required Report Selection DOM targets appear. */
                settleDelayMs: 1000,
                /** Render-target contract that marks Report Selection as ready only after its datatable exists in DOM. */
                renderTargetConfig: {
                    /** Template data-id values that must exist before the global spinner may start settling. */
                    requiredDataIds: ['reportDatatable']
                }
            },
            /** Step 2 transition config. */
            opportunityCreationStrategy: {
                /** Spinner type shown while the Opportunity Creation Strategy step is rendering. */
                spinnerType: 'global',
                /** Scroll mode used by the shared scrollable content subsection for this step. */
                scrollableSectionMode: 'auto',
                /** Post-render delay applied after the required strategy-step DOM targets appear. */
                settleDelayMs: 1000,
                /** Render-target contract for the strategy step, including extra builder targets when the condition builder is visible. */
                renderTargetConfig: {
                    /** Template data-id values that must always exist before the strategy step is considered rendered. */
                    requiredDataIds: ['creation-strategy-input'],
                    /** Additional template data-id values that must exist when the comparison-condition builder is visible. */
                    comparisonBuilderRequiredDataIds: ['comparison-formula-input']
                }
            },
            /** Step 3 transition config. */
            newOpportunityDetails: {
                /** Spinner type shown while the New Opportunity Details step is rendering. */
                spinnerType: 'global',
                /** Scroll mode used by the shared scrollable content subsection for this step. */
                scrollableSectionMode: 'internal',
                /** Longer post-render delay applied because lightning-input-field controls hydrate noticeably later than their hosts. */
                settleDelayMs: 3000,
                /** Render-target contract for the dynamic field-set-driven Request form. */
                renderTargetConfig: {
                    /** Data-id keys whose DOM counts are derived from the rendered Request field set before the spinner can settle. */
                    fieldSetDrivenRequiredDataIdCountKeys: {
                        /** Data-id used by all non-stage lightning-input-field controls in the dynamic Request form. */
                        regularInputs: 'opportunity-input-field',
                        /** Data-id used by the custom Stage combobox that replaces the field-set Stage input. */
                        stageInputs: 'opportunity-stage-input'
                    }
                }
            },
            /** Step 4 transition config. */
            previewAndApproval: {
                /** Spinner type shown while the Preview and Approval step is rendering. */
                spinnerType: 'global',
                /** Scroll mode used by the shared scrollable content subsection for this step. */
                scrollableSectionMode: 'internal',
                /** Post-render delay applied after the preview datatable appears in DOM. */
                settleDelayMs: 1000,
                /** Render-target contract that marks Preview and Approval as ready once the preview datatable exists in DOM. */
                renderTargetConfig: {
                    /** Template data-id values that must exist before the preview-step spinner may settle. */
                    requiredDataIds: ['previewDatatable']
                }
            },
            /** Step 5 transition config. */
            done: {
                /** Spinner type shown while the final Done step is rendering. */
                spinnerType: 'global',
                /** Scroll mode used by the shared scrollable content subsection for this step. */
                scrollableSectionMode: 'internal',
                /** Post-render delay applied after the final readonly results table appears in DOM. */
                settleDelayMs: 1000,
                /** Render-target contract that marks Done as ready once the readonly results table exists in DOM. */
                renderTargetConfig: {
                    /** Template data-id values that must exist before the final step spinner may settle. */
                    requiredDataIds: ['done-results-table']
                }
            }
        }
    },
    /** UI constants. */
    UI: {
        /** Supported UI directions. */
        DIRECTIONS: {
            /** RTL direction literal. */
            RTL: 'rtl',
            /** LTR direction literal. */
            LTR: 'ltr'
        },
        /** Path step identifiers used by the stage header. */
        PATH_STEPS: {
            /** First path step for report selection. */
            REPORT_SELECTION: 'reportSelection',
            /** Second path step for creation strategy selection. */
            OPPORTUNITY_CREATION_STRATEGY: 'opportunityCreationStrategy',
            /** Third path step for new Opportunity details. */
            NEW_OPPORTUNITY_DETAILS: 'newOpportunityDetails',
            /** Fourth path step for preview and approval. */
            PREVIEW_AND_APPROVAL: 'previewAndApproval',
            /** Final path step for completion. */
            DONE: 'done'
        },
        /** Default labels used when translations are resolved locally. */
        DEFAULT_LABELS: {
            /** Hebrew defaults for RTL mode. */
            rtl: {
                modalTitle: 'יצירת הזדמנויות מדוחות',
                chooseReports: 'בחירת דוחות',
                availableReports: 'דוחות זמינים',
                chooseReportsCounter: '({0}/{1})',
                progressSummary: '{0}% ({1} מתוך {2})',
                searchReportsPlaceholder: 'הקלד כדי לחפש דוחות...',
                searchAccountsPlaceholder: 'הקלד כדי לחפש חשבונות...',
                pathReportSelection: 'בחירת דוחות',
                pathOpportunityCreationStrategy: 'אסטרטגיית יצירת הזדמנויות',
                pathNewOpportunityDetails: 'פרטי הזדמנות חדשה',
                pathPreviewAndApproval: 'תצוגה מקדימה ואישור',
                pathDone: 'הושלם',
                creationStrategyTitle: 'אסטרטגיית יצירת הזדמנויות',
                previewAndApprovalTitle: 'תצוגה מקדימה ואישור',
                doneTitle: 'הושלם',
                selectedEligibleAccountsSummary: 'נבחרו {0} חשבונות',
                confirmDialogStartTitle: 'אישור יצירת הזדמנויות',
                confirmDialogStartMessage: 'האם ברצונך להפעיל יצירת הזדמנויות עבור {0} חשבונות?',
                confirmDialogAbortTitle: 'אישור עצירת יצירה',
                confirmDialogAbortMessage:
                    'האם ברצונך לעצור את יצירת ההזדמנויות החדשות? הרשומות שכבר נוצרו ימשיכו לעבור סריקת תשלומים ועדכונם.',
                confirmDialogStartButton: 'התחל יצירה',
                confirmDialogAbortButton: 'הפסק יצירה',
                progressAborting: 'מבטל...',
                doneOpportunityColumn: 'הזדמנות',
                doneAccountColumn: 'חשבון',
                donePaymentColumn: 'תשלום',
                doneStatusColumn: 'סטטוס',
                doneErrorMessageColumn: 'הודעת שגיאה',
                doneStatusSuccess: 'הצלחה',
                doneStatusFailedToCreateOpportunity: 'כשל ביצירת הזדמנות',
                doneStatusFailedToUpdatePayment: 'כשל בעדכון תשלום',
                doneSummaryCreatedSuccessLabel: 'יצירות הזדמנויות הצליחו:',
                doneSummaryFailedOpportunityCreationLabel: 'יצירות הזדמנויות נכשלו:',
                doneSummaryPaymentsCreatedLabel: 'יצירות/עדכוני תשלומים הצליחו:',
                doneSummaryFailedPaymentCreationLabel: 'יצירות/עדכוני תשלומים נכשלו:',
                finish: 'סיום',
                createOpportunities: 'צור הזדמנויות',
                creationStrategyInput: 'אסטרטגיית יצירה',
                duplicateStrategyAlwaysCreate: 'צור תמיד',
                duplicateStrategyMatchSelectedFields: 'צור רק אם לא קיימת הזדמנות תואמת',
                comparisonFieldInput: 'שדה',
                comparisonOperatorInput: 'אופרטור',
                comparisonValueInput: 'ערך',
                comparisonFormulaInput: 'נוסחה',
                comparisonFieldPlaceholder: '--- בחר שדה הזדמנות ---',
                addComparisonCondition: 'הוסף תנאי',
                removeComparisonCondition: 'הסר תנאי',
                booleanTrueOption: 'כן',
                booleanFalseOption: 'לא',
                comparisonOperatorEquals: 'שווה ל',
                comparisonOperatorNotEquals: 'לא שווה ל',
                comparisonOperatorGreaterThan: 'גדול מ',
                comparisonOperatorGreaterOrEqual: 'גדול או שווה ל',
                comparisonOperatorLessThan: 'קטן מ',
                comparisonOperatorLessOrEqual: 'קטן או שווה ל',
                comparisonOperatorContains: 'מכיל',
                comparisonOperatorStartsWith: 'מתחיל ב',
                previewOpportunityValuesTitle: 'ערכי הזדמנות חדשה',
                previewAccountsTableTitle: 'בחר חשבונות ליצירת הזדמנויות',
                previewAccountsCounter: '({0}/{1})',
                previewReportColumn: 'שם דוח',
                previewAccountColumn: 'שם החשבון',
                searchReports: 'חיפוש דוחות',
                reportNameColumn: 'שם דוח',
                reportTypeColumn: 'סוג דוח',
                accountCountColumn: 'סה"כ חשבונות',
                statusColumn: 'סטטוס',
                accountReportType: 'חשבונות',
                contactsAndAccountsReportType: 'אנשי קשר וחשבונות',
                loadingReports: 'טוען דוחות',
                notRetrievedStatus: 'לא נשלף',
                loadingStatus: 'טוען',
                successStatus: 'הושלם בהצלחה',
                errorStatus: 'שגיאה',
                unsupportedTypeStatus: 'סוג לא נתמך',
                retrieveAccounts: 'שלוף חשבונות',
                abort: 'בטל',
                back: 'חזור',
                next: 'הבא',
                cancel: 'ביטול',
                errorTitle: 'לא ניתן לטעון דוחות',
                errorLoadReportsMessage: 'אירעה שגיאה בטעינת הדוחות.',
                errorLoadPreviewMessage: 'אירעה שגיאה בהכנת תצוגת האישור.',
                errorSelectReportsToContinue: 'נא לבחור דוחות',
                errorNoEligibleAccountsInSelection: 'לא נמצאו חשבונות מתאימים בדוחות שנבחרו.',
                warningNoEligibleAccountsFound:
                    'לא נמצאו חשבונות מתאימים בדוח שנבחר או שסוג הדוח שגוי.',
                errorWaitForLoading: 'יש להמתין עד לסיום הטעינה.',
                retrieveAccountsToContinue: 'יש להריץ שליפת חשבונות עבור כל הדוחות שנבחרו לפני המעבר לשלב הבא.',
                errorSelectComparisonFields: 'יש להשלים שדה ואופרטור בכל תנאי השוואה לפני שממשיכים.',
                errorComparisonFormulaRequired: 'יש להזין נוסחת השוואה לפני שממשיכים.',
                errorComparisonFormulaMissingFields: 'יש להשתמש בכל תנאי ההשוואה לפחות פעם אחת בנוסחה.',
                errorComparisonFormulaConditionCountMismatch: 'מספר התנאים בנוסחה אינו תואם למספר תנאי ההשוואה שהוגדרו.',
                errorComparisonFormulaInvalidParentheses: 'יש לתקן את הסוגריים בנוסחת ההשוואה.',
                errorComparisonFormulaInvalidSyntax: 'יש לתקן את תחביר נוסחת ההשוואה לפני שממשיכים.',
                errorComparisonFormulaInvalidTokens: 'בנוסחת ההשוואה מותר להשתמש רק במספרי תנאים, AND/OR, &&/|| וסוגריים.',
                errorRequestRecordTypeUnavailable: 'לא ניתן לטעון את סוג הרשומה Request עבור הזדמנות.',
                warningCorrectFormBeforeContinuing: 'יש לתקן את השדות בטופס לפני שממשיכים.'
            },
            /** English defaults for LTR mode. */
            ltr: {
                modalTitle: 'Create Opportunities From Reports',
                chooseReports: 'Report Selection',
                availableReports: 'Available Reports',
                chooseReportsCounter: '({0}/{1})',
                progressSummary: '{0}% ({1} of {2})',
                searchReportsPlaceholder: 'Type to search for reports...',
                searchAccountsPlaceholder: 'Type to search for the accounts...',
                pathReportSelection: 'Report Selection',
                pathOpportunityCreationStrategy: 'Opportunity Creation Strategy',
                pathNewOpportunityDetails: 'New Opportunity Details',
                pathPreviewAndApproval: 'Preview and Approval',
                pathDone: 'Done',
                creationStrategyTitle: 'Opportunity Creation Strategy',
                previewAndApprovalTitle: 'Preview and Approval',
                doneTitle: 'Done',
                selectedEligibleAccountsSummary: 'Selected {0} accounts',
                confirmDialogStartTitle: 'Confirm Opportunity Creation',
                confirmDialogStartMessage: 'Do you want to start creating Opportunities for {0} Accounts?',
                confirmDialogAbortTitle: 'Confirm Creation Abort',
                confirmDialogAbortMessage:
                    'Do you want to interrupt future Opportunity creation? Records that were already created will still finish Payment refresh and update processing.',
                confirmDialogStartButton: 'Start Creation',
                confirmDialogAbortButton: 'Abort Creation',
                progressAborting: 'Aborting...',
                doneOpportunityColumn: 'Opportunity',
                doneAccountColumn: 'Account',
                donePaymentColumn: 'Payment',
                doneStatusColumn: 'Status',
                doneErrorMessageColumn: 'Error Message',
                doneStatusSuccess: 'Success',
                doneStatusFailedToCreateOpportunity: 'Failed to create opportunity',
                doneStatusFailedToUpdatePayment: 'Failed to update payment',
                doneSummaryCreatedSuccessLabel: 'Opportunity creations succeeded:',
                doneSummaryFailedOpportunityCreationLabel: 'Opportunity creations failed:',
                doneSummaryPaymentsCreatedLabel: 'Payment creations/updates succeeded:',
                doneSummaryFailedPaymentCreationLabel: 'Payment creations/updates failed:',
                finish: 'Finish',
                createOpportunities: 'Create Opportunities',
                creationStrategyInput: 'Creation Strategy',
                duplicateStrategyAlwaysCreate: 'Create Always',
                duplicateStrategyMatchSelectedFields: 'Create Only If No Matching Opportunity Exists',
                comparisonFieldInput: 'Field',
                comparisonOperatorInput: 'Operator',
                comparisonValueInput: 'Value',
                comparisonFormulaInput: 'Formula',
                comparisonFieldPlaceholder: '--- Select opportunity field ---',
                addComparisonCondition: 'Add Condition',
                removeComparisonCondition: 'Remove Condition',
                booleanTrueOption: 'True',
                booleanFalseOption: 'False',
                comparisonOperatorEquals: 'Equals',
                comparisonOperatorNotEquals: 'Not Equal To',
                comparisonOperatorGreaterThan: 'Greater Than',
                comparisonOperatorGreaterOrEqual: 'Greater Than Or Equal',
                comparisonOperatorLessThan: 'Less Than',
                comparisonOperatorLessOrEqual: 'Less Than Or Equal',
                comparisonOperatorContains: 'Contains',
                comparisonOperatorStartsWith: 'Starts With',
                previewOpportunityValuesTitle: 'New Opportunity Values',
                previewAccountsTableTitle: 'Select Accounts to Create Opportunities',
                previewAccountsCounter: '({0}/{1})',
                previewReportColumn: 'Report Name',
                previewAccountColumn: 'Account Name',
                searchReports: 'Search Reports',
                reportNameColumn: 'Report Name',
                reportTypeColumn: 'Report Type',
                accountCountColumn: 'Accounts Number',
                statusColumn: 'Status',
                accountReportType: 'Account',
                contactsAndAccountsReportType: 'Contacts & Accounts',
                loadingReports: 'Loading reports',
                notRetrievedStatus: 'Not retrieved',
                loadingStatus: 'Loading',
                successStatus: 'Success',
                errorStatus: 'Error',
                unsupportedTypeStatus: 'Unsupported Type',
                retrieveAccounts: 'Retrieve Accounts',
                abort: 'Abort',
                back: 'Back',
                next: 'Next',
                cancel: 'Cancel',
                errorTitle: 'Unable to load reports',
                errorLoadReportsMessage: 'An error occurred while loading reports.',
                errorLoadPreviewMessage: 'An error occurred while building the approval preview.',
                errorSelectReportsToContinue: 'Select reports before continuing.',
                errorNoEligibleAccountsInSelection: 'No eligible Accounts were found in the selected reports.',
                warningNoEligibleAccountsFound:
                    'No eligible Accounts were found in the selected report or incorrect report type.',
                errorWaitForLoading: 'Wait for loading to finish.',
                retrieveAccountsToContinue: 'Run Retrieve Accounts for all selected reports before continuing.',
                errorSelectComparisonFields: 'Complete the field and operator in every comparison condition before continuing.',
                errorComparisonFormulaRequired: 'Enter a comparison formula before continuing.',
                errorComparisonFormulaMissingFields: 'Reference every comparison condition at least once in the formula.',
                errorComparisonFormulaConditionCountMismatch:
                    'The number of conditions referenced in the formula does not match the number of comparison conditions configured.',
                errorComparisonFormulaInvalidParentheses: 'Correct the parentheses in the comparison formula before continuing.',
                errorComparisonFormulaInvalidSyntax: 'Correct the comparison formula syntax before continuing.',
                errorComparisonFormulaInvalidTokens: 'Use only condition numbers, AND/OR, &&/||, and parentheses in the comparison formula.',
                errorRequestRecordTypeUnavailable: 'Unable to load the Request Opportunity record type.',
                warningCorrectFormBeforeContinuing: 'Correct the form before continuing.'
            }
        }
    }
};

// -------------------------------
// Public Interfaces
// -------------------------------

export default class CreateOpportunitiesFromReports extends LightningModal {
    /** Optional table height used to keep the datatable header fixed. */
    @api tableHeight = '400px';

    // -------------------------------
    // Tracked Properties
    // -------------------------------

    /** Datatable column configuration. */
    columns = [];
    /** Indicates whether the modal is loading the initial report list. */
    isLoading = true;
    /** Indicates whether selected reports are currently being scanned. */
    isRetrievingAccounts = false;
    /** Fatal error message shown in the modal body. */
    errorMessage = '';
    /** Step-level warning message shown in the modal footer. */
    stepWarningMessage = '';
    /** Full report row state used by the modal datatable. */
    reportRows = [];
    /** Selected report Ids. */
    selectedReportIds = [];
    /** Immediate search box value. */
    searchInputValue = '';
    /** Debounced search term applied to the datatable. */
    searchTerm = '';
    /** Live search term applied to the preview Accounts table. */
    previewSearchTerm = '';
    /** Current sort field. */
    sortBy = CONSTANTS.SORT.DEFAULT_FIELD;
    /** Current sort direction. */
    sortDirection = CONSTANTS.SORT.DEFAULT_DIRECTION;
    /** Number of selected reports included in the active retrieval batch. */
    retrievalBatchTotalCount = 0;
    /** Number of selected reports already completed in the active retrieval batch. */
    retrievalBatchCompletedCount = 0;
    /** Current wizard step rendered under the shared progress indicator. */
    currentStep = CONSTANTS.UI.PATH_STEPS.REPORT_SELECTION;
    /** Selected creation strategy from the second wizard screen. */
    selectedCreationStrategy = CONSTANTS.STRATEGY.CREATE_ALWAYS;
    /** Up to five duplicate-filter conditions configured on the second wizard screen. */
    comparisonConditions = this._getInitialComparisonConditions();
    /** Boolean formula that combines the numbered duplicate-filter conditions. */
    comparisonFormulaText = this._getInitialComparisonFormulaText();
    /** Server-driven modal configuration loaded from Apex. */
    config = {};
    /** Shared Opportunity field values collected on the details step. */
    opportunityFieldValues = {};
    /** Prepared Opportunity payload built from step 3 and reused by the preview and create steps. */
    preparedOpportunity = {};
    /** Preview rows shown on the approval step. */
    previewRows = [];
    /** Account ids currently selected in the preview table for final processing. */
    selectedPreviewAccountIds = [];
    /** Number of currently running long async operations that should lock footer navigation. */
    activeAsyncOperationCount = 0;
    /** Indicates that the global overlay spinner should stay visible for the active step transition. */
    isGlobalTransitionPending = false;
    /** Indicates that the universal progress bar above the footer is currently visible. */
    isUniversalProgressBarVisible = false;
    /** Current universal progress bar percentage value. */
    universalProgressBarValue = CONSTANTS.PROGRESS.MIN_PERCENT;
    /** Current universal progress completed-count value. */
    universalProgressCompletedCount = 0;
    /** Current universal progress total-count value. */
    universalProgressTotalCount = 0;
    /** Indicates whether the final Opportunity creation flow is currently running. */
    isOpportunityCreationProcessRunning = false;
    /** Indicates that the user requested abort for future create chunks while already-created chunks still finish refresh/update processing. */
    isOpportunityCreationAbortRequested = false;
    /** Number of preview-selected Accounts submitted into the final create flow. */
    opportunityCreationTotalAccountCount = 0;
    /** Number of preview-selected Accounts already processed by create chunks. */
    opportunityCreationProcessedAccountCount = 0;
    /** Number of Opportunities created successfully. */
    createdOpportunityCount = 0;
    /** Number of Opportunity creates that failed. */
    failedOpportunityCount = 0;
    /** Number of found Payments updated successfully. */
    updatedPaymentCount = 0;
    /** Number of created Opportunities whose Payments were not found by their single chunk refresh. */
    missingPaymentCount = 0;
    /** Final execution rows shown on the Done step. */
    executionRows = [];
    /** Resolved lookup display values keyed by preview field API name for the step-4 read-only panel. */
    previewLookupDisplayValuesByField = {};
    /** Current sort field used by the Done results table. */
    doneSortBy = CONSTANTS.PROCESS.DONE_DEFAULT_SORT_FIELD;
    /** Current sort direction used by the Done results table. */
    doneSortDirection = CONSTANTS.PROCESS.DONE_DEFAULT_SORT_DIRECTION;
    /** Indicates that the create queue has finished enqueuing all delayed Payment-refresh chunks. */
    hasFinishedEnqueuingPaymentRefreshChunks = false;
    /** FIFO queue with created Opportunity chunks that still need delayed Payment refresh and possible Payment update. */
    pendingPaymentRefreshChunks = [];
    /** Indicates whether the shared manual confirmation-dialog is visible. */
    isConfirmationDialogVisible = false;
    /** Pending action requested through the shared manual confirmation-dialog. */
    confirmationDialogAction = '';
    /** Dynamically measured content-section height in pixels, calculated from shell height minus summary and reserved progress heights. */
    contentSectionHeightPx = 0;
    /** Dynamically measured scrollable-section height in pixels, calculated from content height minus fixed static content. */
    scrollableSectionHeightPx = 0;

    // -------------------------------
    // Private Fields
    // -------------------------------

    /** Debounce timer id for report search. */
    searchDebounceTimeoutId;
    /** Explicit wizard cache that stores the latest user-entered state only for steps 1, 2, and 3. */
    stepStateCache = {
        reportSelection: {
            selectedReportIds: [],
            searchInputValue: '',
            searchTerm: '',
            sortBy: CONSTANTS.SORT.DEFAULT_FIELD,
            sortDirection: CONSTANTS.SORT.DEFAULT_DIRECTION
        },
        opportunityCreationStrategy: {
            selectedCreationStrategy: CONSTANTS.STRATEGY.CREATE_ALWAYS,
            comparisonConditions: this._getInitialComparisonConditions(),
            comparisonFormulaText: this._getInitialComparisonFormulaText()
        },
        newOpportunityDetails: {
            opportunityFieldValues: {},
            preparedOpportunity: {}
        }
    };
    /** Indicates that the active retrieval batch should stop scheduling new requests. */
    isAbortRequested = false;
    /** Target wizard step that must finish rendering before the active transition completes. */
    pendingRenderedStep = '';
    /** Delayed completion timer used to keep the overlay spinner visible during late base-component painting. */
    pendingStepTransitionTimeoutId;
    /** Fallback timeout used while waiting for the next renderedCallback after all required DOM nodes already appeared. */
    pendingStepAwaitNextRenderTimeoutId;
    /** Polling timer used to re-check whether the target step finished rendering all required controls. */
    pendingStepRenderPollTimeoutId;
    /** Number of render-poll cycles already spent on the current pending transition. */
    pendingStepRenderPollCycleCount = 0;
    /** Reactive guard token used to force one extra render cycle after all target DOM nodes appear. */
    pendingStepRenderGuardToken = 0;
    /** Indicates that the transition spinner is waiting for the next renderedCallback before starting its settle delay. */
    isPendingStepAwaitingNextRender = false;
    /** Debounced timeout used to recalculate the dynamic content-section height after render or resize. */
    contentSectionMeasurementTimeoutId;
    /** ResizeObserver that watches the dynamic-height summary section. */
    summarySectionResizeObserver;
    /** ResizeObserver that watches the reserved progress section and shell container. */
    layoutSectionResizeObserver;
    /** ResizeObserver that watches the fixed static content section inside the modal body. */
    staticSectionResizeObserver;
    /** ResizeObserver that watches the bottom static content section inside the modal body. */
    bottomStaticSectionResizeObserver;
    /** Bound resize listener reused for window-level resize recalculation. */
    handleWindowResizeBound;
    // -------------------------------
    // Wired Members
    // -------------------------------

    /** Opportunity describe metadata used to resolve step-2 comparison field labels. */
    @wire(getObjectInfo, { objectApiName: OPPORTUNITY_OBJECT })
    opportunityObjectInfo;

    /** Opportunity picklist metadata used to render the custom StageName combobox on step 3. */
    @wire(getPicklistValuesByRecordType, { objectApiName: OPPORTUNITY_OBJECT, recordTypeId: '$requestRecordTypeId' })
    opportunityPicklistValues;

    // -------------------------------
    // Component Lifecycle Events
    // -------------------------------

    /** Initializes columns and loads the initial report list. */
    async connectedCallback() {
        this.columns = this._buildColumns();
        this.handleWindowResizeBound = this._handleWindowResize.bind(this);
        window.addEventListener('resize', this.handleWindowResizeBound);
        await this._loadConfig();

        if (this.errorMessage) {
            this.isLoading = false;
            return;
        }

        await this._loadSelectorData();
    }

    /** Injects one datatable CSS patch after each render when the base component is present. */
    renderedCallback() {
        this._applyModalBodyOverflowHiddenPatch();
        this._applyDatatableCellOpacityPatch();
        this._initializeLayoutObservers();
        this._scheduleContentSectionMeasurement();
        this._completeStepTransitionAfterRender();
    }

    /** Clears active timers when the modal is destroyed. */
    disconnectedCallback() {
        this._clearSearchDebounce();
        this._clearPendingStepTransitionTimeout();
        this._clearPendingStepAwaitNextRenderTimeout();
        this._clearPendingStepRenderPollTimeout();
        this._clearContentSectionMeasurementTimeout();
        this.summarySectionResizeObserver?.disconnect();
        this.layoutSectionResizeObserver?.disconnect();
        this.staticSectionResizeObserver?.disconnect();
        this.bottomStaticSectionResizeObserver?.disconnect();
        window.removeEventListener('resize', this.handleWindowResizeBound);
    }

    // -------------------------------
    // Public Getters/Setters
    // -------------------------------

    /** Returns true when the current language should use RTL labels. */
    get isRtl() {
        return String(USER_LANGUAGE || '').toLowerCase().startsWith('he');
    }

    /** Returns the current localization direction. */
    get direction() {
        return this.isRtl ? CONSTANTS.UI.DIRECTIONS.RTL : CONSTANTS.UI.DIRECTIONS.LTR;
    }

    /** Returns the modal title shown in the header. */
    get modalTitle() {
        return this._getLabel('modalTitle');
    }

    /** Returns the current path step id for the stage header. */
    get currentPathStep() {
        return this.currentStep;
    }

    /** Returns the wrapper style that makes the path read-only for pointer interaction. */
    get pathWrapStyle() {
        return 'pointer-events:none;';
    }

    /** Returns the localized Report Selection path label. */
    get pathReportSelectionLabel() {
        return this._getLabel('pathReportSelection');
    }

    /** Returns the localized Opportunity Creation Strategy path label. */
    get pathOpportunityCreationStrategyLabel() {
        return this._getLabel('pathOpportunityCreationStrategy');
    }

    /** Returns the localized New Opportunity Details path label. */
    get pathNewOpportunityDetailsLabel() {
        return this._getLabel('pathNewOpportunityDetails');
    }

    /** Returns the localized Preview and Approval path label. */
    get pathPreviewAndApprovalLabel() {
        return this._getLabel('pathPreviewAndApproval');
    }

    /** Returns the localized Done path label. */
    get pathDoneLabel() {
        return this._getLabel('pathDone');
    }

    /** Returns true when a fatal error is present. */
    get hasError() {
        return this.errorMessage !== '';
    }

    /** Returns true when the first wizard screen should be shown. */
    get showReportSelectionContent() {
        return !this.isLoading && this.currentStep === CONSTANTS.UI.PATH_STEPS.REPORT_SELECTION;
    }

    /** Returns true when the second wizard screen should be shown. */
    get showOpportunityCreationStrategyContent() {
        return !this.isLoading && this.currentStep === CONSTANTS.UI.PATH_STEPS.OPPORTUNITY_CREATION_STRATEGY;
    }

    /** Returns true when the third wizard screen should be shown. */
    get showNewOpportunityDetailsContent() {
        return !this.isLoading && this.currentStep === CONSTANTS.UI.PATH_STEPS.NEW_OPPORTUNITY_DETAILS;
    }

    /** Returns true when the fourth wizard screen should be shown. */
    get showPreviewAndApprovalContent() {
        return !this.isLoading && this.currentStep === CONSTANTS.UI.PATH_STEPS.PREVIEW_AND_APPROVAL;
    }

    /** Returns true when the final wizard screen should be shown. */
    get showDoneContent() {
        return !this.isLoading && this.currentStep === CONSTANTS.UI.PATH_STEPS.DONE;
    }

    /** Returns true when the active step uses an internal fixed-height table instead of body scrolling. */
    get isTableStep() {
        return this.showReportSelectionContent || this.showPreviewAndApprovalContent;
    }

    /** Returns true when the shared step header should be shown above the active content. */
    get showStepHeader() {
        return this.showReportSelectionContent ||
            this.showOpportunityCreationStrategyContent ||
            this.showNewOpportunityDetailsContent ||
            this.showPreviewAndApprovalContent ||
            this.showDoneContent;
    }

    /** Returns the shared step title shown above the active wizard content. */
    get currentStepTitle() {
        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.NEW_OPPORTUNITY_DETAILS) {
            return this.pathNewOpportunityDetailsLabel;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.PREVIEW_AND_APPROVAL) {
            return this.previewAndApprovalTitle;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.DONE) {
            return this.doneTitle;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.OPPORTUNITY_CREATION_STRATEGY) {
            return this.creationStrategyTitle;
        }

        return this.chooseReportsTitle;
    }

    /** Returns the shared summary items shown under the active step title. */
    get currentStepSummaryItems() {
        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.REPORT_SELECTION) {
            return [
                {
                    text: this.selectedEligibleAccountsSummary
                }
            ];
        }

        if (
            this.currentStep === CONSTANTS.UI.PATH_STEPS.OPPORTUNITY_CREATION_STRATEGY ||
            this.currentStep === CONSTANTS.UI.PATH_STEPS.NEW_OPPORTUNITY_DETAILS
        ) {
            return [
                {
                    text: this.selectedEligibleAccountsSummary
                }
            ];
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.DONE) {
            return [
                {
                    label: this.doneSummaryCreatedSuccessLabel,
                    value: this.createdOpportunityCount
                },
                {
                    label: this.doneSummaryPaymentsCreatedLabel,
                    value: this.successfulPaymentCreationCount
                },
                {
                    label: this.doneSummaryFailedOpportunityCreationLabel,
                    value: this.failedOpportunityCount
                },
                {
                    label: this.doneSummaryFailedPaymentCreationLabel,
                    value: this.failedPaymentUpdateCount
                }
            ];
        }

        return [];
    }

    /** Returns true when the current step has summary text under the shared title. */
    get hasCurrentStepSummary() {
        return this.currentStepSummaryItems.length > 0;
    }

    /** Returns the shared summary lines distributed into two-column rows in the supplied order. */
    get currentStepSummaryRows() {
        const currentStepSummaryRows = [];

        for (let summaryIndex = 0; summaryIndex < this.currentStepSummaryItems.length; summaryIndex += 2) {
            currentStepSummaryRows.push({
                key: `summary-row-${summaryIndex}`,
                items: this.currentStepSummaryItems.slice(summaryIndex, summaryIndex + 2).map((summaryItem, itemIndex) => ({
                    key: `summary-item-${summaryIndex + itemIndex}`,
                    ...summaryItem
                }))
            });
        }

        return currentStepSummaryRows;
    }

    /** Returns the inline style used by the datatable wrapper. */
    get tableWrapStyle() {
        return this.scrollableSectionHeightPx > 0
            ? `height:${this.scrollableSectionHeightPx}px;`
            : `height:${this.tableHeight || '400px'};`;
    }

    /** Returns the inline style for the shared content area below the sticky header. */
    get contentSectionStyle() {
        return this.contentSectionHeightPx > 0
            ? `height:${this.contentSectionHeightPx}px;min-height:0;`
            : 'min-height:0;';
    }

    /** Returns the inline style for the fixed static subsection inside the content area. */
    get staticSectionStyle() {
        return 'flex:0 0 auto;';
    }

    /** Returns the inline style for the fixed bottom static subsection inside the content area. */
    get bottomStaticSectionStyle() {
        return 'flex:0 0 auto;';
    }

    /** Returns the inline style for the dynamic scrollable subsection inside the content area. */
    get scrollableSectionStyle() {
        const baseStyle = this.scrollableSectionHeightPx > 0
            ? `height:${this.scrollableSectionHeightPx}px;min-height:0;padding-top:0.75rem;`
            : 'min-height:0;padding-top:0.75rem;';
        const borderStyle = this.hasScrollableSectionContent
            ? 'border:1px solid var(--lwc-colorBorder, #dddbda);box-sizing:border-box;padding-left:0.5rem;padding-right:0.5rem;padding-bottom:0.5rem;'
            : 'border:0;padding-left:0;padding-right:0;padding-bottom:0;';

        return this._getCurrentStepScrollableSectionMode() === CONSTANTS.STEP_CONFIG.SCROLLABLE_SECTION_MODES.INTERNAL
            ? `${baseStyle}${borderStyle}overflow:hidden;`
            : `${baseStyle}${borderStyle}overflow-y:auto;`;
    }

    /** Returns true when the current step actually renders content inside the scrollable content subsection. */
    get hasScrollableSectionContent() {
        return this.showReportSelectionContent ||
            (this.showOpportunityCreationStrategyContent && this.showComparisonConditionBuilder) ||
            this.showNewOpportunityDetailsContent ||
            this.showPreviewAndApprovalContent ||
            this.showDoneContent;
    }

    /** Returns the report rows after search filtering and sorting. */
    get visibleReportRows() {
        const normalizedSearchTerm = this.searchTerm.trim().toLowerCase();
        const filteredRows = normalizedSearchTerm === ''
            ? [...this.reportRows]
            : this.reportRows.filter((reportRow) =>
                String(reportRow.shortLabel || reportRow.label || '')
                    .toLowerCase()
                    .includes(normalizedSearchTerm)
            );

        return filteredRows.sort((leftRow, rightRow) => this._compareRows(leftRow, rightRow));
    }

    /** Returns selected report rows sorted exactly like the table. */
    get selectedReportRows() {
        return this.reportRows
            .filter((reportRow) => this.selectedReportIds.includes(reportRow.value))
            .sort((leftRow, rightRow) => this._compareRows(leftRow, rightRow));
    }

    /** Returns unique Account Ids across selected reports. */
    get selectedAccountIds() {
        return this._collectUniqueIds('accountIdsJson');
    }

    /** Returns unique eligible Account Ids across selected reports. */
    get selectedEligibleAccountIds() {
        return this._collectUniqueIds('eligibleAccountIdsJson');
    }

    /** Returns true when selected rows still require account retrieval. */
    get hasSelectedRowsPendingRetrieval() {
        return this.selectedReportRows.some((reportRow) => !reportRow.isCountsLoaded);
    }

    /** Returns true when Retrieve Accounts must be disabled. */
    get isRetrieveAccountsDisabled() {
        return this.isLoading ||
            this.isRetrievingAccounts ||
            this.selectedReportIds.length === 0 ||
            !this.hasSelectedRowsPendingRetrieval;
    }

    /** Returns true when the modal cannot continue to the next step. */
    get isNextDisabled() {
        if (this.isStepAsyncRunning) {
            return true;
        }

        if (
            this.currentStep === CONSTANTS.UI.PATH_STEPS.REPORT_SELECTION ||
            this.currentStep === CONSTANTS.UI.PATH_STEPS.OPPORTUNITY_CREATION_STRATEGY
        ) {
            return false;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.NEW_OPPORTUNITY_DETAILS) {
            return !this.requestRecordTypeId;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.PREVIEW_AND_APPROVAL) {
            return this.selectedPreviewAccountIds.length === 0;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.DONE) {
            return false;
        }

        return this.isLoading;
    }

    /** Returns disabled row ids used by lightning-datatable. */
    get disabledReportIds() {
        return this.reportRows.filter((reportRow) => reportRow.isDisabled).map((reportRow) => reportRow.value);
    }

    /** Returns the choose-reports title. */
    get chooseReportsTitle() {
        return this._getLabel('chooseReports');
    }

    /** Returns the Available Reports label shown above the datatable. */
    get availableReportsLabel() {
        return this._getLabel('availableReports');
    }

    /** Returns the localized selection counter text. */
    get chooseReportsCounterText() {
        return this._formatLabel('chooseReportsCounter', this.selectedReportIds.length, this.reportRows.length);
    }

    /** Returns the localized search label. */
    get searchReportsLabel() {
        return this._getLabel('searchReports');
    }

    /** Returns the placeholder for the report search input. */
    get searchReportsPlaceholder() {
        return this._getLabel('searchReportsPlaceholder');
    }

    /** Returns the placeholder used by the live preview Account search input. */
    get searchAccountsPlaceholder() {
        return this._getLabel('searchAccountsPlaceholder');
    }

    /** Returns the localized loading spinner text. */
    get loadingReportsLabel() {
        return this._getLabel('loadingReports');
    }

    /** Returns the localized manual confirmation-dialog title. */
    get confirmationDialogTitle() {
        if (this.confirmationDialogAction === CONSTANTS.CONFIRMATION.ACTIONS.START_OPPORTUNITY_CREATION) {
            return this._getLabel('confirmDialogStartTitle');
        }

        if (this.confirmationDialogAction === CONSTANTS.CONFIRMATION.ACTIONS.ABORT_OPPORTUNITY_CREATION) {
            return this._getLabel('confirmDialogAbortTitle');
        }

        return '';
    }

    /** Returns the localized manual confirmation-dialog message. */
    get confirmationDialogMessage() {
        if (this.confirmationDialogAction === CONSTANTS.CONFIRMATION.ACTIONS.START_OPPORTUNITY_CREATION) {
            return this._formatLabel('confirmDialogStartMessage', this.selectedPreviewAccountIds.length);
        }

        if (this.confirmationDialogAction === CONSTANTS.CONFIRMATION.ACTIONS.ABORT_OPPORTUNITY_CREATION) {
            return this._getLabel('confirmDialogAbortMessage');
        }

        return '';
    }

    /** Returns the localized manual confirmation-dialog confirm button label. */
    get confirmationDialogConfirmButtonLabel() {
        if (this.confirmationDialogAction === CONSTANTS.CONFIRMATION.ACTIONS.START_OPPORTUNITY_CREATION) {
            return this._getLabel('confirmDialogStartButton');
        }

        if (this.confirmationDialogAction === CONSTANTS.CONFIRMATION.ACTIONS.ABORT_OPPORTUNITY_CREATION) {
            return this._getLabel('confirmDialogAbortButton');
        }

        return this._getLabel('cancel');
    }

    /** Returns the localized manual confirmation-dialog cancel button label. */
    get confirmationDialogCancelButtonLabel() {
        return this._getLabel('cancel');
    }

    /** Returns the confirm-button variant used by the manual confirmation-dialog. */
    get confirmationDialogConfirmButtonVariant() {
        if (this.confirmationDialogAction === CONSTANTS.CONFIRMATION.ACTIONS.ABORT_OPPORTUNITY_CREATION) {
            return CONSTANTS.CONFIRMATION.VARIANTS.ABORT_OPPORTUNITY_CREATION;
        }

        return CONSTANTS.CONFIRMATION.VARIANTS.START_OPPORTUNITY_CREATION;
    }

    /** Returns the localized error title. */
    get errorTitle() {
        return this._getLabel('errorTitle');
    }

    /** Returns true when a step-level warning message should be shown in the footer. */
    get hasStepWarning() {
        return this.stepWarningMessage !== '';
    }

    /** Returns true when a long async step operation is currently running. */
    get isStepAsyncRunning() {
        return this.activeAsyncOperationCount > 0;
    }

    /** Returns true when the shared overlay spinner should cover the wizard body. */
    get showGlobalTransitionSpinner() {
        return this.isLoading || this.isGlobalTransitionPending;
    }

    /** Returns true when the universal progress bar should be shown above the modal footer. */
    get showUniversalProgressBar() {
        return this.isUniversalProgressBarVisible;
    }

    /** Returns the current universal progress bar value clamped to the supported range. */
    get universalProgressBarValueDisplay() {
        return Math.max(
            CONSTANTS.PROGRESS.MIN_PERCENT,
            Math.min(CONSTANTS.PROGRESS.MAX_PERCENT, this.universalProgressBarValue)
        );
    }

    /** Returns the inline width style for the filled section of the universal progress line. */
    get universalProgressBarFillStyle() {
        return `width:${this.universalProgressBarValueDisplay}%;`;
    }

    /** Returns the localized progress summary shown to the right of the universal progress line. */
    get universalProgressSummaryText() {
        if (this.isOpportunityCreationAbortRequested && this.isOpportunityCreationProcessRunning) {
            return this._getLabel('progressAborting');
        }

        return this._formatLabel(
            'progressSummary',
            this.universalProgressBarValueDisplay,
            this.universalProgressCompletedCount,
            this.universalProgressTotalCount
        );
    }

    /** Returns true when the shared content section should be blocked by the in-progress overlay spinner. */
    get showContentProgressSpinner() {
        return this.isRetrievingAccounts || this.isOpportunityCreationProcessRunning;
    }

    /** Returns true when the progress area should render the Abort button. */
    get showProgressAbortButton() {
        return this.isRetrievingAccounts || this.isOpportunityCreationProcessRunning;
    }

    /** Returns the warning-text style used in the footer step warning area. */
    get stepWarningTextStyle() {
        return CONSTANTS.CSS.STEP_WARNING_TEXT_STYLE;
    }

    /** Returns the localized retrieve button label. */
    get retrieveAccountsButtonLabel() {
        return this._getLabel('retrieveAccounts');
    }

    /** Returns the localized Abort button label. */
    get abortButtonLabel() {
        return this._getLabel('abort');
    }

    /** Returns true when the progress-area Abort button must be disabled. */
    get isProgressAbortButtonDisabled() {
        if (this.isRetrievingAccounts) {
            return false;
        }

        return !this.isOpportunityCreationProcessRunning || this.isOpportunityCreationAbortRequested;
    }

    /** Returns true when the Back button must be disabled. */
    get isBackDisabled() {
        return this.isStepAsyncRunning || this.currentStep === CONSTANTS.UI.PATH_STEPS.REPORT_SELECTION;
    }

    /** Returns the localized Back button label. */
    get backButtonLabel() {
        return this._getLabel('back');
    }

    /** Returns the localized Next button label. */
    get nextButtonLabel() {
        return this._getLabel('next');
    }

    /** Returns the localized Create Opportunities button label shown on the preview step. */
    get createOpportunitiesButtonLabel() {
        return this._getLabel('createOpportunities');
    }

    /** Returns the localized Done title. */
    get doneTitle() {
        return this._getLabel('doneTitle');
    }

    /** Returns the localized Finish button label. */
    get finishButtonLabel() {
        return this._getLabel('finish');
    }

    /** Returns the selected report Ids as JSON. */
    get selectedReportIdsJson() {
        return JSON.stringify(this.selectedReportIds);
    }

    /** Returns the selected eligible Account Ids as JSON. */
    get eligibleAccountIdsJson() {
        return JSON.stringify(this.selectedEligibleAccountIds);
    }

    /** Returns the selected total Account count. */
    get totalAccountCount() {
        return this.selectedAccountIds.length;
    }

    /** Returns the selected eligible Account count. */
    get eligibleAccountCount() {
        return this.selectedEligibleAccountIds.length;
    }

    /** Returns the number of selected reports. */
    get selectedReportCount() {
        return this.selectedReportRows.length;
    }

    /** Returns the localized strategy screen title. */
    get creationStrategyTitle() {
        return this._getLabel('creationStrategyTitle');
    }

    /** Returns the localized preview-and-approval title. */
    get previewAndApprovalTitle() {
        return this._getLabel('previewAndApprovalTitle');
    }

    /** Returns the localized selected-accounts summary shown on the intermediate wizard steps. */
    get selectedEligibleAccountsSummary() {
        return this._formatLabel('selectedEligibleAccountsSummary', this.selectedEligibleAccountIds.length);
    }

    /** Returns the localized heading shown above the read-only Opportunity preview form. */
    get previewOpportunityValuesTitle() {
        return this._getLabel('previewOpportunityValuesTitle');
    }

    /** Returns the preview-table title shown above the selectable Account list. */
    get previewAccountsTableTitle() {
        return this._getLabel('previewAccountsTableTitle');
    }

    /** Returns the localized preview selection counter shown beside the Accounts title. */
    get previewAccountsCounterText() {
        return this._formatLabel(
            'previewAccountsCounter',
            this.selectedPreviewAccountIds.length,
            this.previewRows.length
        );
    }

    /** Returns the approval-table rows with direct Salesforce navigation URLs. */
    get previewTableRows() {
        const normalizedSearchTerm = this.previewSearchTerm.trim().toLowerCase();
        const filteredPreviewRows = normalizedSearchTerm === ''
            ? [...this.previewRows]
            : this.previewRows.filter((previewRow) =>
                String(previewRow.accountName || '').toLowerCase().includes(normalizedSearchTerm) ||
                String(previewRow.reportName || '').toLowerCase().includes(normalizedSearchTerm)
            );

        return filteredPreviewRows
            .sort((leftRow, rightRow) => {
                const accountComparison = String(leftRow.accountName || '').localeCompare(String(rightRow.accountName || ''));

                if (accountComparison !== 0) {
                    return accountComparison;
                }

                return String(leftRow.reportName || '').localeCompare(String(rightRow.reportName || ''));
            })
            .map((previewRow) => ({
                ...previewRow,
                reportUrl: `/lightning/r/Report/${previewRow.reportId}/view`,
                accountUrl: `/lightning/r/Account/${previewRow.accountId}/view`
            }));
    }

    /** Returns true when the final results table should be shown on the Done step. */
    get hasDoneRows() {
        return this.executionRows.length > 0;
    }

    /** Returns the number of execution rows that ended with a Payment-update failure status. */
    get failedPaymentUpdateCount() {
        return this.executionRows.filter(
            (executionRow) => executionRow.status === CONSTANTS.PROCESS.ROW_STATUS.FAILED_TO_UPDATE_PAYMENT
        ).length;
    }

    /** Returns the number of created Opportunities whose payment side finished without failure. */
    get successfulPaymentCreationCount() {
        return this.executionRows.filter((executionRow) => executionRow.status === CONSTANTS.PROCESS.ROW_STATUS.SUCCESS).length;
    }

    /** Returns the localized summary label for successfully created Opportunities. */
    get doneSummaryCreatedSuccessLabel() {
        return this._getLabel('doneSummaryCreatedSuccessLabel');
    }

    /** Returns the localized summary label for failed Opportunity creations. */
    get doneSummaryFailedOpportunityCreationLabel() {
        return this._getLabel('doneSummaryFailedOpportunityCreationLabel');
    }

    /** Returns the localized summary label for Payments created by org automation. */
    get doneSummaryPaymentsCreatedLabel() {
        return this._getLabel('doneSummaryPaymentsCreatedLabel');
    }

    /** Returns the localized summary label for Payments that were created but failed during update. */
    get doneSummaryFailedPaymentCreationLabel() {
        return this._getLabel('doneSummaryFailedPaymentCreationLabel');
    }

    /** Returns the final results rows enriched with direct Salesforce navigation URLs. */
    get doneTableRows() {
        const sortedRows = [...this.executionRows].sort((leftRow, rightRow) => this._compareDoneRows(leftRow, rightRow));

        return sortedRows.map((executionRow) => ({
            ...executionRow,
            opportunityDisplayName: executionRow.opportunityName || CONSTANTS.PLACEHOLDERS.DASH,
            accountDisplayName: executionRow.accountName || CONSTANTS.PLACEHOLDERS.DASH,
            paymentDisplayName: executionRow.paymentName || CONSTANTS.PLACEHOLDERS.DASH,
            statusLabel: this._getDoneRowStatusLabel(executionRow.status),
            statusToneClass: this._getDoneRowStatusToneClass(executionRow.status),
            errorDisplayValue: executionRow.errorMessage || CONSTANTS.PLACEHOLDERS.DASH,
            opportunityUrl: executionRow.opportunityId
                ? `/lightning/r/Opportunity/${executionRow.opportunityId}/view`
                : '',
            accountUrl: executionRow.accountId
                ? `/lightning/r/Account/${executionRow.accountId}/view`
                : '',
            paymentUrl: executionRow.paymentId
                ? `/lightning/r/npe01__OppPayment__c/${executionRow.paymentId}/view`
                : '',
            isOpportunityLinkDisabled: !executionRow.opportunityId,
            isPaymentLinkDisabled: !executionRow.paymentId
        }));
    }

    /** Returns the readonly sortable Done-table column configuration. */
    get doneColumns() {
        return [
            {
                label: this._getLabel('doneAccountColumn'),
                fieldName: 'accountDisplayName',
                type: 'button',
                sortable: true,
                typeAttributes: {
                    label: { fieldName: 'accountDisplayName' },
                    name: 'openDoneAccount',
                    variant: 'base'
                }
            },
            {
                label: this._getLabel('doneOpportunityColumn'),
                fieldName: 'opportunityDisplayName',
                type: 'button',
                sortable: true,
                typeAttributes: {
                    label: { fieldName: 'opportunityDisplayName' },
                    name: 'openDoneOpportunity',
                    variant: 'base',
                    disabled: { fieldName: 'isOpportunityLinkDisabled' }
                }
            },
            {
                label: this._getLabel('donePaymentColumn'),
                fieldName: 'paymentDisplayName',
                type: 'button',
                sortable: true,
                typeAttributes: {
                    label: { fieldName: 'paymentDisplayName' },
                    name: 'openDonePayment',
                    variant: 'base',
                    disabled: { fieldName: 'isPaymentLinkDisabled' }
                }
            },
            {
                label: this._getLabel('doneStatusColumn'),
                fieldName: 'statusLabel',
                type: 'text',
                sortable: true,
                cellAttributes: {
                    class: { fieldName: 'statusToneClass' }
                }
            },
            {
                label: this._getLabel('doneErrorMessageColumn'),
                fieldName: 'errorDisplayValue',
                type: 'text',
                sortable: true,
                cellAttributes: {
                    class: 'slds-text-color_error'
                }
            }
        ];
    }

    /** Returns the datatable field name that should display the current Done-table sort arrow. */
    get doneSortedByField() {
        if (this.doneSortBy === 'accountName') {
            return 'accountDisplayName';
        }

        if (this.doneSortBy === 'paymentName') {
            return 'paymentDisplayName';
        }

        if (this.doneSortBy === 'status') {
            return 'statusLabel';
        }

        if (this.doneSortBy === 'errorMessage') {
            return 'errorDisplayValue';
        }

        return 'opportunityDisplayName';
    }

    /** Returns true when the footer should render the left-side button. */
    get showFooterLeftButton() {
        return this.currentStep !== CONSTANTS.UI.PATH_STEPS.DONE;
    }

    /** Returns true when the footer should render the right-side button. */
    get showFooterRightButton() {
        return true;
    }

    /** Returns the step-aware left footer button label. */
    get footerLeftButtonLabel() {
        return this.backButtonLabel;
    }

    /** Returns the step-aware right footer button label. */
    get footerRightButtonLabel() {
        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.PREVIEW_AND_APPROVAL) {
            return this.createOpportunitiesButtonLabel;
        }

        return this.currentStep === CONSTANTS.UI.PATH_STEPS.DONE
            ? this.finishButtonLabel
            : this.nextButtonLabel;
    }

    /** Returns true when the left footer button should be disabled. */
    get isFooterLeftButtonDisabled() {
        if (this.isConfirmationDialogVisible || this.showUniversalProgressBar) {
            return true;
        }

        return this.isBackDisabled;
    }

    /** Returns true when the right footer button should be disabled. */
    get isFooterRightButtonDisabled() {
        if (this.isConfirmationDialogVisible || this.showUniversalProgressBar) {
            return true;
        }

        return this.currentStep === CONSTANTS.UI.PATH_STEPS.DONE ? false : this.isNextDisabled;
    }

    /** Returns the approval-table column configuration. */
    get previewColumns() {
        return [
            {
                label: this._getLabel('previewAccountColumn'),
                fieldName: 'accountName',
                type: 'button',
                typeAttributes: {
                    label: { fieldName: 'accountName' },
                    name: 'openPreviewAccount',
                    variant: 'base'
                }
            },
            {
                label: this._getLabel('previewReportColumn'),
                fieldName: 'reportName',
                type: 'button',
                typeAttributes: {
                    label: { fieldName: 'reportName' },
                    name: 'openPreviewReport',
                    variant: 'base'
                }
            }
        ];
    }

    /** Returns preview rows currently selected for final processing. */
    get selectedPreviewRows() {
        return this.previewRows.filter((previewRow) => this.selectedPreviewAccountIds.includes(previewRow.accountId));
    }

    /** Returns selected preview Account ids as JSON for the final payload. */
    get selectedPreviewAccountIdsJson() {
        return JSON.stringify(this.selectedPreviewAccountIds);
    }

    /** Returns the localized creation-strategy input label. */
    get creationStrategyInputLabel() {
        return this._getLabel('creationStrategyInput');
    }

    /** Returns the localized comparison-field input label. */
    get comparisonFieldInputLabel() {
        return this._getLabel('comparisonFieldInput');
    }

    /** Returns the localized comparison-operator input label. */
    get comparisonOperatorInputLabel() {
        return this._getLabel('comparisonOperatorInput');
    }

    /** Returns the localized comparison-value input label. */
    get comparisonValueInputLabel() {
        return this._getLabel('comparisonValueInput');
    }

    /** Returns the localized comparison-formula input label. */
    get comparisonFormulaInputLabel() {
        return this._getLabel('comparisonFormulaInput');
    }

    /** Returns the localized empty-field placeholder option for the field combobox. */
    get comparisonFieldPlaceholderLabel() {
        return this._getLabel('comparisonFieldPlaceholder');
    }

    /** Returns the localized add-condition button label. */
    get addComparisonConditionLabel() {
        return this._getLabel('addComparisonCondition');
    }

    /** Returns the localized remove-condition button label. */
    get removeComparisonConditionLabel() {
        return this._getLabel('removeComparisonCondition');
    }

    /** Returns the inline width limit for the creation-strategy combobox. */
    get creationStrategyComboboxStyle() {
        return 'max-width:400px;';
    }

    /** Returns the inline width limit for the Opportunity details form. */
    get newOpportunityDetailsFormStyle() {
        return 'max-width:900px;';
    }

    /** Returns the inline width limit for the report search input on step 1. */
    get reportSearchInputStyle() {
        return 'width:clamp(180px, 28vw, 350px);';
    }

    /** Returns the Request Opportunity record type Id for the details form. */
    get requestRecordTypeId() {
        return this.config.requestRecordTypeId || '';
    }

    /** Returns extra stage values forced into the StageName dropdown on step 3. */
    get additionalStageValues() {
        return Array.isArray(this.config.additionalStageValues) ? [...this.config.additionalStageValues] : [];
    }

    /** Returns the server-driven step-3 Request field descriptors in field-set order. */
    get requestFieldSetFields() {
        return Array.isArray(this.config.requestFieldSetFields) ? [...this.config.requestFieldSetFields] : [];
    }

    /** Returns the server-driven StageName combobox options for the custom step-3 form. */
    get requestStageOptions() {
        return Array.isArray(this.config.requestStageOptions) ? [...this.config.requestStageOptions] : [];
    }

    /** Returns true when the New Opportunity Details form can be rendered. */
    get showRequestOpportunityForm() {
        return this.requestRecordTypeId !== '';
    }

    /** Returns the localized Request record type unavailable message. */
    get requestRecordTypeUnavailableMessage() {
        return this._getLabel('errorRequestRecordTypeUnavailable');
    }

    /** Returns the merged StageName picklist options for the custom step-3 combobox. */
    get stageNameOptions() {
        return this._sortOptionsByLabel(
            this.requestStageOptions.map((stageOption) => ({
                label: stageOption.label,
                value: stageOption.value
            }))
        );
    }

    /** Returns the current StageName value shown in the custom step-3 combobox. */
    get stageNameValue() {
        return this.opportunityFieldValues[CONSTANTS.FIELDS.STAGE_NAME] ||
            this.stageNameOptions[0]?.value ||
            '';
    }

    /** Returns true when at least one configured Request form field can be rendered on step 3. */
    get hasOpportunityCreateLayout() {
        return this.opportunityFormRows.length > 0;
    }

    /** Returns the step-3 Request form fields in the configured field-set order. */
    get opportunityFormFields() {
        return this.requestFieldSetFields
            .filter((fieldConfig) => fieldConfig?.apiName)
            .map((fieldConfig, fieldIndex) => ({
                key: `opportunity-form-field-${fieldIndex}`,
                fieldApiName: fieldConfig.apiName,
                fieldLabel: fieldConfig.label || fieldConfig.apiName,
                isStageOverride: fieldConfig.apiName === CONSTANTS.FIELDS.STAGE_NAME,
                isRequired: fieldConfig.isRequired === true,
                value: this.opportunityFieldValues[fieldConfig.apiName] || ''
            }));
    }

    /** Returns the step-3 Request form rows rendered in a fixed two-column layout. */
    get opportunityFormRows() {
        const opportunityFormRows = [];

        for (let rowStartIndex = 0; rowStartIndex < this.opportunityFormFields.length; rowStartIndex += 2) {
            opportunityFormRows.push({
                key: `opportunity-form-row-${rowStartIndex}`,
                items: this.opportunityFormFields.slice(rowStartIndex, rowStartIndex + 2)
            });
        }

        return opportunityFormRows;
    }

    /** Returns the read-only preview-form fields shown on step 4 in the same field-set order as step 3. */
    get previewOpportunityFormFields() {
        const previewOpportunityValues = this._collectOpportunityFieldValues();

        return this.requestFieldSetFields
            .filter((fieldConfig) => fieldConfig?.apiName)
            .map((fieldConfig, fieldIndex) => {
                const fieldValue = previewOpportunityValues[fieldConfig.apiName] || '';
                const fieldDataType = this._getOpportunityFieldDataType(fieldConfig.apiName);

                return {
                    key: `preview-opportunity-form-field-${fieldIndex}`,
                    fieldApiName: fieldConfig.apiName,
                    fieldLabel: fieldConfig.label || fieldConfig.apiName,
                    isRequired: fieldConfig.isRequired === true,
                    value: fieldValue,
                    isLookup:
                        fieldValue !== '' &&
                        this._getOpportunityFieldDataType(fieldConfig.apiName) === 'Reference' &&
                        !!this.previewLookupDisplayValuesByField[fieldConfig.apiName]?.recordId,
                    lookupUrl: this._getPreviewLookupUrl(fieldConfig.apiName),
                    lookupDisplayValue: this._getPreviewLookupDisplayValue(fieldConfig.apiName, fieldValue),
                    isFormattedDate:
                        fieldValue !== '' &&
                        (fieldDataType === 'Date' || fieldDataType === 'DateTime'),
                    displayValue: this._getPreviewFieldDisplayValue(fieldConfig.apiName, fieldValue)
                };
            });
    }

    /** Returns the creation-strategy combobox options for the second wizard screen. */
    get creationStrategyOptions() {
        return this._sortOptionsByLabel([
            {
                label: this._getLabel('duplicateStrategyAlwaysCreate'),
                value: CONSTANTS.STRATEGY.CREATE_ALWAYS
            },
            {
                label: this._getLabel('duplicateStrategyMatchSelectedFields'),
                value: CONSTANTS.STRATEGY.MATCH_SELECTED_FIELDS
            }
        ]);
    }

    /** Returns all plain Opportunity field options available for the second wizard screen. */
    get comparisonFieldOptions() {
        const availableFields = this.opportunityObjectInfo.data?.fields || {};

        return this._sortOptionsByLabel([
            {
                label: this.comparisonFieldPlaceholderLabel,
                value: ''
            },
            ...Object.entries(availableFields)
            .filter(([fieldApiName, fieldDescribe]) =>
                fieldDescribe.dataType !== 'Reference' &&
                fieldDescribe.compound !== true
            )
            .map(([fieldApiName, fieldDescribe]) => ({
                label: fieldDescribe.label || fieldApiName,
                value: fieldApiName
            }))
        ]);
    }

    /** Returns true when the duplicate-filter builder should be shown. */
    get showComparisonConditionBuilder() {
        return this.isDuplicateValidationStrategy;
    }

    /** Returns the normalized duplicate-filter condition rows rendered on step 2. */
    get comparisonConditionRows() {
        return this.comparisonConditions.map((comparisonCondition, conditionIndex) => {
            const valueType = this._getComparisonValueType(comparisonCondition.fieldApiName);

            return {
                ...comparisonCondition,
                key: `comparison-condition-${comparisonCondition.rowNumber}`,
                index: conditionIndex,
                isRemoveDisabled: comparisonCondition.rowNumber === 1,
                showAddButton:
                    conditionIndex === this.comparisonConditions.length - 1 &&
                    this.canAddComparisonCondition,
                operatorOptions: this._getComparisonOperatorOptions(comparisonCondition.fieldApiName),
                valueOptions: this._getComparisonValueOptions(comparisonCondition.fieldApiName),
                isValueControlDisabled: !comparisonCondition.fieldApiName,
                isPicklistValue: valueType === CONSTANTS.STRATEGY.VALUE_TYPES.PICKLIST,
                isBooleanValue: valueType === CONSTANTS.STRATEGY.VALUE_TYPES.BOOLEAN,
                isNumberValue: valueType === CONSTANTS.STRATEGY.VALUE_TYPES.NUMBER,
                isDateValue: valueType === CONSTANTS.STRATEGY.VALUE_TYPES.DATE,
                isDateTimeValue: valueType === CONSTANTS.STRATEGY.VALUE_TYPES.DATETIME,
                isTextValue: valueType === CONSTANTS.STRATEGY.VALUE_TYPES.TEXT
            };
        });
    }

    /** Returns true when another duplicate-filter row can be added. */
    get canAddComparisonCondition() {
        return this.comparisonConditions.length < CONSTANTS.STRATEGY.MAX_CONDITION_COUNT;
    }

    /** Returns true when duplicate validation by selected fields is active. */
    get isDuplicateValidationStrategy() {
        return this.selectedCreationStrategy === CONSTANTS.STRATEGY.MATCH_SELECTED_FIELDS;
    }

    // -------------------------------
    // Event Handlers
    // -------------------------------

    /** Handles datatable row selection. */
    handleRowSelection(event) {
        this.selectedReportIds = event.detail.selectedRows.map((reportRow) => reportRow.value);
        this._cacheReportSelectionState();
        this._clearStepWarning();
    }

    /** Handles preview-table row selection. */
    handlePreviewRowSelection(event) {
        this.selectedPreviewAccountIds = event.detail.selectedRows.map((previewRow) => previewRow.accountId);
        this._clearStepWarning();
    }

    /** Handles report search input with debounce. */
    handleSearchInput(event) {
        this.searchInputValue = String(event.target.value || '');
        this._cacheReportSelectionState();
        this._clearSearchDebounce();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchDebounceTimeoutId = setTimeout(() => {
            this.searchTerm = this.searchInputValue;
            this._cacheReportSelectionState();
            this.searchDebounceTimeoutId = null;
        }, CONSTANTS.TIMERS.SEARCH_DEBOUNCE_MS);
    }

    /** Handles live search input for the preview table without affecting Account selection state. */
    handlePreviewSearchInput(event) {
        this.previewSearchTerm = String(event.target.value || '');
    }

    /** Handles datatable sort changes. */
    handleSort(event) {
        this.sortBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
        this._cacheReportSelectionState();
    }

    /** Handles row action clicks. */
    handleRowAction(event) {
        if (event.detail.action.name !== 'openReport') {
            return;
        }

        this._openRecordInNewTab(`/lightning/r/Report/${event.detail.row.value}/view`);
    }

    /** Opens preview-table records in a new browser tab. */
    handlePreviewRowAction(event) {
        if (event.detail.action.name === 'openPreviewAccount') {
            this._openRecordInNewTab(event.detail.row.accountUrl);
            return;
        }

        if (event.detail.action.name === 'openPreviewReport') {
            this._openRecordInNewTab(event.detail.row.reportUrl);
        }
    }

    /** Opens Done-table records in a new browser tab. */
    handleDoneRowAction(event) {
        if (event.detail.action.name === 'openDoneAccount') {
            this._openRecordInNewTab(event.detail.row.accountUrl);
            return;
        }

        if (event.detail.action.name === 'openDoneOpportunity') {
            this._openRecordInNewTab(event.detail.row.opportunityUrl);
            return;
        }

        if (event.detail.action.name === 'openDonePayment') {
            this._openRecordInNewTab(event.detail.row.paymentUrl);
        }
    }

    /** Stops scheduling new report retrieval requests for the active batch. */
    handleAbortClick() {
        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.PREVIEW_AND_APPROVAL && this.isOpportunityCreationProcessRunning) {
            this._openConfirmationDialog(CONSTANTS.CONFIRMATION.ACTIONS.ABORT_OPPORTUNITY_CREATION);
            return;
        }

        this.isAbortRequested = true;

        if (
            this.currentStep === CONSTANTS.UI.PATH_STEPS.REPORT_SELECTION &&
            this.pendingRenderedStep === CONSTANTS.UI.PATH_STEPS.OPPORTUNITY_CREATION_STRATEGY
        ) {
            this._cancelPendingStepTransition();
        }
    }

    /** Closes the shared manual confirmation-dialog without executing the pending action. */
    handleConfirmationDialogCancel() {
        this._closeConfirmationDialog();
    }

    /** Executes the currently pending manual confirmation action. */
    async handleConfirmationDialogConfirm() {
        const confirmationAction = this.confirmationDialogAction;

        this._closeConfirmationDialog();

        if (confirmationAction === CONSTANTS.CONFIRMATION.ACTIONS.START_OPPORTUNITY_CREATION) {
            await this._yieldForTransitionSpinnerPaint();
            await this._runOpportunityCreationProcess();
            return;
        }

        if (confirmationAction === CONSTANTS.CONFIRMATION.ACTIONS.ABORT_OPPORTUNITY_CREATION) {
            this.isOpportunityCreationAbortRequested = true;
        }
    }

    /** Handles creation-strategy changes on the second wizard screen. */
    handleCreationStrategyChange(event) {
        this.selectedCreationStrategy = event.detail.value;
        this._cacheOpportunityCreationStrategyState();
        this._syncComparisonFormulaInputValidity();
        this._clearStepWarning();
    }

    /** Adds one more duplicate-filter condition row when the step limit allows it. */
    handleAddComparisonCondition() {
        if (!this.canAddComparisonCondition) {
            return;
        }

        const previousConditionCount = this.comparisonConditions.length;
        const hadDefaultFormula = this._isDefaultComparisonFormula(this.comparisonFormulaText, previousConditionCount);

        this.comparisonConditions = [
            ...this.comparisonConditions,
            this._createComparisonCondition(previousConditionCount + 1)
        ];

        if (hadDefaultFormula) {
            this.comparisonFormulaText = this._buildDefaultComparisonFormula(this.comparisonConditions.length);
        }

        this._cacheOpportunityCreationStrategyState();
        this._syncComparisonFormulaInputValidity();
        this._clearStepWarning();
    }

    /** Removes one duplicate-filter condition row and renumbers the remaining rows. */
    handleRemoveComparisonCondition(event) {
        const removedConditionIndex = Number(event.currentTarget.dataset.index);

        if (!Number.isInteger(removedConditionIndex) || removedConditionIndex <= 0) {
            return;
        }

        const previousConditions = [...this.comparisonConditions];
        const previousConditionCount = previousConditions.length;
        const removedCondition = previousConditions[removedConditionIndex];
        const nextConditions = this._renumberComparisonConditions(
            previousConditions.filter((_, conditionIndex) => conditionIndex !== removedConditionIndex)
        );
        const hasRemovedFormulaReference = removedCondition &&
            new RegExp(`(^|\\D)${removedCondition.rowNumber}(\\D|$)`).test(this.comparisonFormulaText);

        this.comparisonConditions = nextConditions;

        if (
            hasRemovedFormulaReference ||
            this._isDefaultComparisonFormula(this.comparisonFormulaText, previousConditionCount)
        ) {
            this.comparisonFormulaText = this._buildDefaultComparisonFormula(nextConditions.length);
        } else {
            this.comparisonFormulaText = this._remapComparisonFormula(this.comparisonFormulaText, removedConditionIndex);
        }

        this._cacheOpportunityCreationStrategyState();
        this._syncComparisonFormulaInputValidity();
        this._clearStepWarning();
    }

    /** Handles one duplicate-filter field selection change. */
    handleComparisonConditionFieldChange(event) {
        const conditionIndex = Number(event.target.dataset.index);
        const nextFieldApiName = event.detail.value;
        const nextValueType = this._getComparisonValueType(nextFieldApiName);
        const nextOperatorOptions = this._getComparisonOperatorOptions(nextFieldApiName);

        this.comparisonConditions = this.comparisonConditions.map((comparisonCondition, currentConditionIndex) => {
            if (currentConditionIndex !== conditionIndex) {
                return comparisonCondition;
            }

            return {
                ...comparisonCondition,
                fieldApiName: nextFieldApiName,
                operator: nextOperatorOptions.some(
                    (operatorOption) => operatorOption.value === comparisonCondition.operator
                )
                    ? comparisonCondition.operator
                    : '',
                value: this._normalizeComparisonConditionValue(
                    comparisonCondition.value,
                    nextValueType,
                    nextFieldApiName
                )
            };
        });

        this._cacheOpportunityCreationStrategyState();
        this._syncComparisonFormulaInputValidity();
        this._clearStepWarning();
    }

    /** Handles one duplicate-filter operator change. */
    handleComparisonConditionOperatorChange(event) {
        const conditionIndex = Number(event.target.dataset.index);
        const nextOperator = event.detail.value;

        this.comparisonConditions = this.comparisonConditions.map((comparisonCondition, currentConditionIndex) =>
            currentConditionIndex === conditionIndex
                ? {
                    ...comparisonCondition,
                    operator: nextOperator
                }
                : comparisonCondition
        );
        this._cacheOpportunityCreationStrategyState();
        this._syncComparisonFormulaInputValidity();
        this._clearStepWarning();
    }

    /** Handles one duplicate-filter value change. */
    handleComparisonConditionValueChange(event) {
        const conditionIndex = Number(event.target.dataset.index);
        const nextValue = event.detail?.value ?? event.target.value ?? '';

        this.comparisonConditions = this.comparisonConditions.map((comparisonCondition, currentConditionIndex) =>
            currentConditionIndex === conditionIndex
                ? {
                    ...comparisonCondition,
                    value: nextValue
                }
                : comparisonCondition
        );
        this._cacheOpportunityCreationStrategyState();
        this._syncComparisonFormulaInputValidity();
        this._clearStepWarning();
    }

    /** Stores the current duplicate-filter formula text. */
    handleComparisonFormulaChange(event) {
        this.comparisonFormulaText = String(event.target.value || '');
        this._cacheOpportunityCreationStrategyState();
        this._syncComparisonFormulaInputValidity();
        this._clearStepWarning();
    }

    /** Runs native required validation for one comparison-field combobox on blur. */
    handleComparisonConditionFieldBlur(event) {
        event.target.reportValidity();
    }

    /** Runs native required validation for one comparison-operator combobox on blur. */
    handleComparisonConditionOperatorBlur(event) {
        event.target.reportValidity();
    }

    /** Validates the comparison formula on blur. */
    handleComparisonFormulaBlur() {
        const formulaInput = this.template.querySelector('[data-id="comparison-formula-input"]');

        if (!formulaInput) {
            return;
        }

        this._applyComparisonFormulaInputValidity(formulaInput);
        formulaInput.reportValidity();
    }

    /** Stores one changed Opportunity input value from the details step. */
    handleOpportunityFieldChange(event) {
        const fieldApiName = event.target.fieldName;

        if (!fieldApiName) {
            return;
        }

        this.opportunityFieldValues = {
            ...this.opportunityFieldValues,
            [fieldApiName]: event.target.value
        };
        this._cacheNewOpportunityDetailsState();
    }

    /** Stores the overridden StageName value from the custom step-3 combobox. */
    handleStageNameChange(event) {
        this.opportunityFieldValues = {
            ...this.opportunityFieldValues,
            [CONSTANTS.FIELDS.STAGE_NAME]: event.detail.value
        };
        this._cacheNewOpportunityDetailsState();
    }

    /** Retrieves account counters for selected reports with bounded concurrency. */
    async handleRetrieveAccountsClick() {
        this._clearStepWarning();
        await this._runSelectedReportRetrieval();
    }

    /** Handles the modal Back button. */
    async handleBackClick() {
        this._cacheCurrentStepState();
        this._clearStepWarning();
        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.PREVIEW_AND_APPROVAL) {
            this._restoreNewOpportunityDetailsState();
            await this._runDeferredStepTransition(CONSTANTS.UI.PATH_STEPS.NEW_OPPORTUNITY_DETAILS);
            return;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.NEW_OPPORTUNITY_DETAILS) {
            this._restoreOpportunityCreationStrategyState();
            await this._runDeferredStepTransition(CONSTANTS.UI.PATH_STEPS.OPPORTUNITY_CREATION_STRATEGY);
            return;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.OPPORTUNITY_CREATION_STRATEGY) {
            this._restoreReportSelectionState();
            await this._runDeferredStepTransition(CONSTANTS.UI.PATH_STEPS.REPORT_SELECTION);
            return;
        }

        this.close({ action: 'cancel' });
    }

    /** Routes the left footer button to Back. */
    async handleFooterLeftButtonClick() {
        await this.handleBackClick();
    }

    /** Handles the modal Next button. */
    async handleNextClick() {
        this._cacheCurrentStepState();
        this._clearStepWarning();

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.REPORT_SELECTION) {
            if (this.hasSelectedRowsPendingRetrieval) {
                await this._runSelectedReportRetrieval();
            }

            const reportSelectionValidationResult = this.validateStep();

            if (!reportSelectionValidationResult.isValid) {
                this._cancelPendingStepTransition();
                this._setStepWarning(reportSelectionValidationResult.errorMessage);
                return;
            }

            await this._runDeferredStepTransition(CONSTANTS.UI.PATH_STEPS.OPPORTUNITY_CREATION_STRATEGY);
            return;
        }

        const validationResult = this.validateStep();

        if (!validationResult.isValid) {
            this._setStepWarning(validationResult.errorMessage);
            return;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.OPPORTUNITY_CREATION_STRATEGY) {
            await this._runDeferredStepTransition(CONSTANTS.UI.PATH_STEPS.NEW_OPPORTUNITY_DETAILS);
            return;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.NEW_OPPORTUNITY_DETAILS) {
            this._beginStepTransition(CONSTANTS.UI.PATH_STEPS.PREVIEW_AND_APPROVAL);
            await this._yieldForTransitionSpinnerPaint();
            this.preparedOpportunity = this._buildPreparedOpportunity();
            this._cacheNewOpportunityDetailsState();
            await this._loadPreviewData();

            if (this.errorMessage) {
                this._cancelPendingStepTransition();
                return;
            }

            this.currentStep = CONSTANTS.UI.PATH_STEPS.PREVIEW_AND_APPROVAL;
            return;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.PREVIEW_AND_APPROVAL) {
            this._openConfirmationDialog(CONSTANTS.CONFIRMATION.ACTIONS.START_OPPORTUNITY_CREATION);
            return;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.DONE) {
            this.close({
                action: 'finish',
                selectedReportIdsJson: this.selectedReportIdsJson,
                eligibleAccountIdsJson: this.eligibleAccountIdsJson,
                totalAccountCount: this.totalAccountCount,
                eligibleAccountCount: this.eligibleAccountCount,
                creatableAccountIdsJson: this.selectedPreviewAccountIdsJson,
                previewOpportunityCount: this.selectedPreviewAccountIds.length,
                createdOpportunityCount: this.createdOpportunityCount,
                updatedPaymentCount: this.updatedPaymentCount,
                missingPaymentCount: this.missingPaymentCount,
                failedOpportunityCount: this.failedOpportunityCount,
                executionRowsJson: JSON.stringify(this.executionRows)
            });
            return;
        }

        this.close({
            action: 'next',
            selectedReportIdsJson: this.selectedReportIdsJson,
            eligibleAccountIdsJson: this.eligibleAccountIdsJson,
            totalAccountCount: this.totalAccountCount,
            eligibleAccountCount: this.eligibleAccountCount,
            creatableAccountIdsJson: this.selectedPreviewAccountIdsJson,
            previewOpportunityCount: this.selectedPreviewAccountIds.length,
            selectedReportCount: this.selectedReportCount,
            creationStrategy: this.selectedCreationStrategy,
            comparisonConditionsJson: this._buildComparisonConditionsJson(),
            comparisonFormulaText: this.comparisonFormulaText,
            opportunityFieldValuesJson: JSON.stringify(this._collectOpportunityFieldValues()),
            preparedOpportunityJson: JSON.stringify(this.preparedOpportunity),
            previewRowsJson: JSON.stringify(this.selectedPreviewRows)
        });
    }

    /** Handles Done-table sort changes. */
    handleDoneSort(event) {
        const sortFieldNameByColumnField = {
            accountDisplayName: 'accountName',
            opportunityDisplayName: 'opportunityName',
            paymentDisplayName: 'paymentName',
            statusLabel: 'status',
            errorDisplayValue: 'errorMessage'
        };

        this.doneSortBy = sortFieldNameByColumnField[event.detail.fieldName] || 'opportunityName';
        this.doneSortDirection = event.detail.sortDirection;
    }

    // -------------------------------
    // Public Methods
    // -------------------------------

    /** Validates the current wizard step before moving forward. */
    validateStep() {
        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.PREVIEW_AND_APPROVAL) {
            return { isValid: true, errorMessage: '' };
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.NEW_OPPORTUNITY_DETAILS) {
            return this._validateNewOpportunityDetailsStep();
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.OPPORTUNITY_CREATION_STRATEGY) {
            return this._validateOpportunityCreationStrategyStep();
        }

        return this._validateReportSelectionStep();
    }

    // -------------------------------
    // Private Methods
    // -------------------------------

    /** Runs the full preview-step create/refresh/update flow and then transitions automatically to Done. */
    async _runOpportunityCreationProcess() {
        this._resetOpportunityCreationProcessState();
        this._clearStepWarning();
        this.isOpportunityCreationProcessRunning = true;
        this.isOpportunityCreationAbortRequested = false;
        this.activeAsyncOperationCount += 1;
        this.opportunityCreationTotalAccountCount = this.selectedPreviewAccountIds.length;
        this._showUniversalProgressBar(
            CONSTANTS.PROGRESS.MIN_PERCENT,
            CONSTANTS.PROGRESS.MIN_PERCENT,
            this.opportunityCreationTotalAccountCount
        );

        try {
            await this._runOpportunityCreateChunks(this.selectedPreviewAccountIds);
        } catch (error) {
            this.errorMessage = this._formatError(error) || String(error?.message || error || '');
        } finally {
            this.isOpportunityCreationProcessRunning = false;
            this.isOpportunityCreationAbortRequested = false;
            this._hideUniversalProgressBar();
            this.activeAsyncOperationCount = Math.max(0, this.activeAsyncOperationCount - 1);
        }

        await this._runDeferredStepTransition(CONSTANTS.UI.PATH_STEPS.DONE);
    }

    /** Creates Opportunity chunks sequentially while an independent delayed Payment-refresh queue runs in parallel. */
    async _runOpportunityCreateChunks(selectedAccountIds) {
        const accountIdChunks = this._chunkArray(selectedAccountIds, CONSTANTS.REQUESTS.CREATE_OPPORTUNITIES_CHUNK_SIZE);
        const paymentRefreshQueuePromise = this._runPaymentRefreshQueueProcessor();

        this.hasFinishedEnqueuingPaymentRefreshChunks = false;
        this.pendingPaymentRefreshChunks = [];

        for (const accountIdChunk of accountIdChunks) {
            if (this.isOpportunityCreationAbortRequested) {
                break;
            }

            const createdOpportunityIds = await this._createOpportunityChunk(accountIdChunk);

            if (createdOpportunityIds.length > 0) {
                this.pendingPaymentRefreshChunks = [
                    ...this.pendingPaymentRefreshChunks,
                    {
                        opportunityIds: createdOpportunityIds,
                        notBeforeTime: Date.now() + CONSTANTS.TIMERS.PAYMENT_REFRESH_INITIAL_DELAY_MS
                    }
                ];
            }
        }

        this.hasFinishedEnqueuingPaymentRefreshChunks = true;

        await paymentRefreshQueuePromise;
    }

    /** Creates one final Opportunity chunk and returns the ids that were actually inserted. */
    async _createOpportunityChunk(accountIdChunk) {
        const response = await createOpportunitiesChunk({
            request: JSON.stringify({
                accountIdsJson: JSON.stringify(accountIdChunk),
                preparedOpportunityJson: JSON.stringify(this.preparedOpportunity)
            })
        });

        if (!response.isSuccess) {
            throw new Error(response.errorMessage);
        }

        const creationChunkData = response.creationChunkData || {};

        this.opportunityCreationProcessedAccountCount += Number(
            creationChunkData.requestedAccountCount || accountIdChunk.length
        );
        this.createdOpportunityCount += Number(creationChunkData.createdOpportunityCount || 0);
        this.failedOpportunityCount += Number(creationChunkData.failedAccountCount || 0);
        this._mergeExecutionRows(creationChunkData.rows);
        this._updateOpportunityCreationProgress(
            this.opportunityCreationProcessedAccountCount,
            this.opportunityCreationTotalAccountCount
        );
        return this._parseJsonArray(creationChunkData.createdOpportunityIdsJson);
    }

    /** Processes the delayed Payment-refresh queue independently from the Opportunity-create queue until every already-created chunk is fully drained. */
    async _runPaymentRefreshQueueProcessor() {
        while (true) {
            if (this.pendingPaymentRefreshChunks.length === 0) {
                if (this.hasFinishedEnqueuingPaymentRefreshChunks) {
                    return;
                }

                await this._delayAsync(CONSTANTS.TIMERS.PAYMENT_REFRESH_QUEUE_IDLE_MS);
                continue;
            }

            const nextPaymentRefreshChunk = this.pendingPaymentRefreshChunks[0];
            const remainingInitialDelayMs = Math.max(0, nextPaymentRefreshChunk.notBeforeTime - Date.now());

            if (remainingInitialDelayMs > 0) {
                await this._delayAsync(Math.min(remainingInitialDelayMs, CONSTANTS.TIMERS.PAYMENT_REFRESH_QUEUE_IDLE_MS));
                continue;
            }

            this.pendingPaymentRefreshChunks = this.pendingPaymentRefreshChunks.slice(1);
            await this._processPaymentRefreshChunk(nextPaymentRefreshChunk);
        }
    }

    /** Refreshes one created Opportunity chunk up to the configured retry limit and updates the Payments that appear. */
    async _processPaymentRefreshChunk(paymentRefreshChunk) {
        let refreshChunkData;
        let foundPaymentIds = [];

        for (
            let refreshAttemptNumber = 1;
            refreshAttemptNumber <= CONSTANTS.TIMERS.MAX_PAYMENT_REFRESH_ATTEMPTS;
            refreshAttemptNumber += 1
        ) {
            refreshChunkData = await this._refreshCreatedOpportunityChunk(paymentRefreshChunk.opportunityIds);
            foundPaymentIds = this._parseJsonArray(refreshChunkData.foundPaymentIdsJson);

            if (foundPaymentIds.length > 0 || refreshAttemptNumber === CONSTANTS.TIMERS.MAX_PAYMENT_REFRESH_ATTEMPTS) {
                break;
            }

            await this._delayAsync(CONSTANTS.TIMERS.PAYMENT_REFRESH_RETRY_DELAY_MS);
        }

        this.missingPaymentCount += Math.max(
            0,
            Number(refreshChunkData?.requestedOpportunityCount || paymentRefreshChunk.opportunityIds.length) - foundPaymentIds.length
        );
        this._mergeExecutionRows(refreshChunkData?.rows);

        if (foundPaymentIds.length === 0) {
            return;
        }

        await this._runPaymentUpdatePhase(foundPaymentIds);
    }

    /** Refreshes one created Opportunity chunk and returns the latest Opportunity and Payment data. */
    async _refreshCreatedOpportunityChunk(opportunityIds) {
        const response = await refreshCreatedOpportunityChunk({
            request: JSON.stringify({
                opportunityIdsJson: JSON.stringify(opportunityIds)
            })
        });

        if (!response.isSuccess) {
            throw new Error(response.errorMessage);
        }

        return response.refreshChunkData || {};
    }

    /** Updates found Payments chunk-by-chunk from the related ERP-ready Opportunity values. */
    async _runPaymentUpdatePhase(foundPaymentIds) {
        for (const paymentIdChunk of this._chunkArray(foundPaymentIds, CONSTANTS.REQUESTS.UPDATE_PAYMENTS_CHUNK_SIZE)) {
            const response = await updatePaymentsChunk({
                request: JSON.stringify({
                    paymentIdsJson: JSON.stringify(paymentIdChunk)
                })
            });

            if (!response.isSuccess) {
                throw new Error(response.errorMessage);
            }

            const paymentUpdateData = response.paymentUpdateData || {};

            this.updatedPaymentCount += Number(paymentUpdateData.updatedPaymentCount || 0);
            this._mergeExecutionRows(paymentUpdateData.rows);

        }
    }

    /** Resets the local execution state before a new final processing run starts. */
    _resetOpportunityCreationProcessState() {
        this.opportunityCreationTotalAccountCount = 0;
        this.opportunityCreationProcessedAccountCount = 0;
        this.createdOpportunityCount = 0;
        this.failedOpportunityCount = 0;
        this.updatedPaymentCount = 0;
        this.missingPaymentCount = 0;
        this.executionRows = [];
        this.doneSortBy = CONSTANTS.PROCESS.DONE_DEFAULT_SORT_FIELD;
        this.doneSortDirection = CONSTANTS.PROCESS.DONE_DEFAULT_SORT_DIRECTION;
        this.hasFinishedEnqueuingPaymentRefreshChunks = false;
        this.pendingPaymentRefreshChunks = [];
    }

    /** Updates the universal progress bar for the currently active execution phase. */
    _updateOpportunityCreationProgress(processedCount, totalCount) {
        if (this.isOpportunityCreationAbortRequested) {
            return;
        }

        if (!totalCount || totalCount <= 0) {
            this._hideUniversalProgressBar();
            return;
        }

        const progressPercent = Math.round((processedCount / totalCount) * 100);
        this._showUniversalProgressBar(progressPercent, processedCount, totalCount);
    }

    /** Merges one or more execution rows into the final processing result set keyed by Account Id. */
    _mergeExecutionRows(nextRows) {
        if (!Array.isArray(nextRows) || nextRows.length === 0) {
            return;
        }

        const executionRowByAccountId = new Map(
            this.executionRows
                .filter((executionRow) => executionRow?.accountId)
                .map((executionRow) => [executionRow.accountId, { ...executionRow }])
        );

        nextRows.forEach((nextRow) => {
            if (!nextRow?.accountId) {
                return;
            }

            const currentRow = executionRowByAccountId.get(nextRow.accountId) || {};

            executionRowByAccountId.set(nextRow.accountId, {
                ...currentRow,
                ...nextRow,
                opportunityId: nextRow.opportunityId || currentRow.opportunityId || '',
                opportunityName: nextRow.opportunityName || currentRow.opportunityName || '',
                accountId: nextRow.accountId || currentRow.accountId || '',
                accountName: nextRow.accountName || currentRow.accountName || '',
                paymentId: nextRow.paymentId || currentRow.paymentId || '',
                paymentName: nextRow.paymentName || currentRow.paymentName || '',
                status: nextRow.status || currentRow.status || CONSTANTS.PROCESS.ROW_STATUS.SUCCESS,
                errorMessage: nextRow.errorMessage || currentRow.errorMessage || ''
            });
        });

        this.executionRows = [...executionRowByAccountId.values()];
    }

    /** Opens the shared manual confirmation-dialog for the requested action. */
    _openConfirmationDialog(confirmationAction) {
        this.confirmationDialogAction = confirmationAction;
        this.isConfirmationDialogVisible = true;
    }

    /** Closes the shared manual confirmation-dialog and clears the pending action. */
    _closeConfirmationDialog() {
        this.isConfirmationDialogVisible = false;
        this.confirmationDialogAction = '';
    }

    /** Splits one array into stable chunks of the requested size. */
    _chunkArray(items, chunkSize) {
        const chunks = [];

        for (let itemIndex = 0; itemIndex < items.length; itemIndex += chunkSize) {
            chunks.push(items.slice(itemIndex, itemIndex + chunkSize));
        }

        return chunks;
    }

    /** Waits one async delay used by deferred wizard processing steps. */
    async _delayAsync(delayMs) {
        await new Promise((resolve) => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(resolve, delayMs);
        });
    }

    /** Compares two Done-table rows according to the current local sort state. */
    _compareDoneRows(leftRow, rightRow) {
        const leftValue = String(leftRow?.[this.doneSortBy] || '').toLowerCase();
        const rightValue = String(rightRow?.[this.doneSortBy] || '').toLowerCase();
        const comparisonResult = leftValue.localeCompare(rightValue);

        return this.doneSortDirection === 'asc' ? comparisonResult : comparisonResult * -1;
    }

    /** Returns the localized final-row status label shown in the Done table. */
    _getDoneRowStatusLabel(statusName) {
        if (statusName === CONSTANTS.PROCESS.ROW_STATUS.FAILED_TO_CREATE_OPPORTUNITY) {
            return this._getLabel('doneStatusFailedToCreateOpportunity');
        }

        if (statusName === CONSTANTS.PROCESS.ROW_STATUS.FAILED_TO_UPDATE_PAYMENT) {
            return this._getLabel('doneStatusFailedToUpdatePayment');
        }

        return this._getLabel('doneStatusSuccess');
    }

    /** Returns the SLDS utility class used to color one final-row status value. */
    _getDoneRowStatusToneClass(statusName) {
        return statusName === CONSTANTS.PROCESS.ROW_STATUS.SUCCESS
            ? 'slds-text-color_success'
            : 'slds-text-color_error';
    }

    /** Validates the first wizard screen before moving to the second screen. */
    _validateReportSelectionStep() {
        if (this.isLoading || this.isRetrievingAccounts) {
            return { isValid: false, errorMessage: this._getLabel('errorWaitForLoading') };
        }

        if (this.selectedReportIds.length === 0) {
            return { isValid: false, errorMessage: this._getLabel('errorSelectReportsToContinue') };
        }

        if (this.hasSelectedRowsPendingRetrieval) {
            return { isValid: false, errorMessage: this._getLabel('retrieveAccountsToContinue') };
        }

        if (this.selectedEligibleAccountIds.length === 0) {
            return { isValid: false, errorMessage: this._getLabel('errorNoEligibleAccountsInSelection') };
        }

        return { isValid: true, errorMessage: '' };
    }

    /** Validates the second wizard screen before moving forward. */
    _validateOpportunityCreationStrategyStep() {
        const validationError = this._getOpportunityCreationStrategyValidationError();
        let areRequiredInputsValid = true;

        [...this.template.querySelectorAll('[data-id="comparison-condition-field"]')].forEach((fieldInput) => {
            if (!fieldInput.reportValidity()) {
                areRequiredInputsValid = false;
            }
        });

        [...this.template.querySelectorAll('[data-id="comparison-condition-operator"]')].forEach((operatorInput) => {
            if (!operatorInput.reportValidity()) {
                areRequiredInputsValid = false;
            }
        });

        const formulaInput = this.template.querySelector('[data-id="comparison-formula-input"]');

        if (formulaInput) {
            this._applyComparisonFormulaInputValidity(formulaInput);

            if (!formulaInput.reportValidity()) {
                areRequiredInputsValid = false;
            }
        }

        if (!areRequiredInputsValid || validationError !== '') {
            return {
                isValid: false,
                errorMessage: validationError || this._getLabel('errorSelectComparisonFields')
            };
        }

        return { isValid: true, errorMessage: '' };
    }

    /** Validates the third wizard screen before moving forward. */
    _validateNewOpportunityDetailsStep() {
        if (!this.requestRecordTypeId) {
            return { isValid: false, errorMessage: this._getLabel('errorRequestRecordTypeUnavailable') };
        }

        const inputFields = [...this.template.querySelectorAll('[data-id="opportunity-input-field"]')];
        const stageNameInput = this.template.querySelector('[data-id="opportunity-stage-input"]');
        let isFormValid = true;

        inputFields.forEach((inputField) => {
            if (!inputField.reportValidity()) {
                isFormValid = false;
            }
        });

        if (stageNameInput && !stageNameInput.reportValidity()) {
            isFormValid = false;
        }

        if (!isFormValid) {
            return { isValid: false, errorMessage: this._getLabel('warningCorrectFormBeforeContinuing') };
        }

        return { isValid: true, errorMessage: '' };
    }

    /** Retrieves account counters for selected reports with bounded concurrency. */
    async _runSelectedReportRetrieval() {
        if (this.isRetrieveAccountsDisabled) {
            return;
        }

        const queuedReportRows = this.selectedReportRows.filter((reportRow) => !reportRow.isCountsLoaded);
        const selectedReportCountAtStart = this.selectedReportRows.length;

        if (queuedReportRows.length === 0) {
            if (this.selectedEligibleAccountIds.length === 0) {
                this._setStepWarning(this._getLabel('warningNoEligibleAccountsFound'));
            }
            return;
        }

        this.activeAsyncOperationCount += 1;

        try {
            this.isRetrievingAccounts = true;
            this.isAbortRequested = false;
            this.retrievalBatchTotalCount = selectedReportCountAtStart;
            this.retrievalBatchCompletedCount = selectedReportCountAtStart - queuedReportRows.length;
            this._syncRetrievalProgressBar();

            let queuedReportIndex = 0;
            const workerCount = Math.min(CONSTANTS.REQUESTS.MAX_CONCURRENT_RETRIEVALS, queuedReportRows.length);

            const worker = async () => {
                while (queuedReportIndex < queuedReportRows.length && !this.isAbortRequested) {
                    const selectedReportRow = queuedReportRows[queuedReportIndex];
                    queuedReportIndex += 1;

                    this._updateReportRow(selectedReportRow.value, {
                        isCountsLoaded: false,
                        reportTypeDisplayValue: this._getLabel('loadingStatus'),
                        accountCountDisplayValue: this._getLabel('loadingStatus'),
                        statusLabel: this._getLabel('loadingStatus'),
                        statusToneClass: '',
                        isDisabled: false
                    });

                    try {
                        const response = await retrieveReportAccounts({
                            request: JSON.stringify({ reportId: selectedReportRow.value })
                        });

                        if (!response.isSuccess || !response.reportData) {
                            const responseError = new Error(response.errorMessage || this._getLabel('errorLoadReportsMessage'));
                            responseError.responseBody = response;
                            throw responseError;
                        }

                        this._updateReportRow(
                            selectedReportRow.value,
                            this._normalizeReportRow(response.reportData, {
                                isCountsLoaded: true,
                                statusLabel: response.reportData.isSupportedType === false
                                    ? this._getLabel('unsupportedTypeStatus')
                                    : this._getLabel('successStatus'),
                                statusToneClass: response.reportData.isSupportedType === false
                                    ? ''
                                    : 'slds-text-color_success',
                                isDisabled: response.reportData.isSupportedType === false
                            })
                        );

                        if (response.reportData.isSupportedType === false) {
                            this.selectedReportIds = this.selectedReportIds.filter((reportId) => reportId !== selectedReportRow.value);
                            this._cacheReportSelectionState();
                        }
                    } catch (error) {
                        this._updateReportRow(
                            selectedReportRow.value,
                            {
                                accountCount: null,
                                eligibleAccountCount: null,
                                accountIdsJson: CONSTANTS.JSON.EMPTY_ARRAY,
                                eligibleAccountIdsJson: CONSTANTS.JSON.EMPTY_ARRAY,
                                isCountsLoaded: false,
                                statusLabel: `${this._getLabel('errorStatus')}: ${this._formatError(error) || this._getLabel('errorLoadReportsMessage')}`,
                                statusToneClass: 'slds-text-color_error',
                                isDisabled: true
                            }
                        );
                        this.selectedReportIds = this.selectedReportIds.filter((reportId) => reportId !== selectedReportRow.value);
                        this._cacheReportSelectionState();
                    } finally {
                        this.retrievalBatchCompletedCount += 1;
                        this._syncRetrievalProgressBar();
                    }
                }
            };

            await Promise.all(Array.from({ length: workerCount }, () => worker()));

            if (!this.hasSelectedRowsPendingRetrieval && this.selectedEligibleAccountIds.length === 0) {
                this._setStepWarning(this._getLabel('warningNoEligibleAccountsFound'));
            }

            this._cacheReportSelectionState();
        } finally {
            this.activeAsyncOperationCount = Math.max(0, this.activeAsyncOperationCount - 1);
            this.isRetrievingAccounts = false;
            this.isAbortRequested = false;
            this.retrievalBatchTotalCount = 0;
            this.retrievalBatchCompletedCount = 0;
            this._hideUniversalProgressBar();
        }
    }

    /** Clears the active step-level warning message. */
    _clearStepWarning() {
        this.stepWarningMessage = '';
    }

    /** Sets the active step-level warning message. */
    _setStepWarning(message) {
        this.stepWarningMessage = message || '';
    }

    /** Loads the initial report list without counters. */
    async _loadSelectorData() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            const response = await getSelectorData();

            if (!response.isSuccess) {
                throw new Error(response.errorMessage || this._getLabel('errorLoadReportsMessage'));
            }

            this.reportRows = (response.availableReports || []).map((reportRow) => this._normalizeReportRow(reportRow));
            this._cacheReportSelectionState();
        } catch (error) {
            this.errorMessage = this._formatError(error) || this._getLabel('errorLoadReportsMessage');
        } finally {
            this.isLoading = false;
        }
    }

    /** Loads server-driven modal configuration before the rest of the wizard data. */
    async _loadConfig() {
        this.errorMessage = '';

        try {
            const response = await getConfig();

            if (!response.isSuccess || !response.config) {
                throw new Error(response.errorMessage || this._getLabel('errorRequestRecordTypeUnavailable'));
            }

            this.config = {
                ...response.config
            };
        } catch (error) {
            this.errorMessage = this._formatError(error) || this._getLabel('errorRequestRecordTypeUnavailable');
        }
    }

    /** Loads the preview rows and creatable Account ids for the approval step. */
    async _loadPreviewData() {
        this.activeAsyncOperationCount += 1;
        this.errorMessage = '';
        this.previewRows = [];
        this.selectedPreviewAccountIds = [];
        this.previewLookupDisplayValuesByField = {};

        try {
            const response = await getPreviewData({
                request: JSON.stringify({
                    selectedReportRowsJson: this._buildSelectedPreviewReportRowsJson(),
                    creationStrategy: this.selectedCreationStrategy,
                    comparisonConditionsJson: this._buildComparisonConditionsJson(),
                    comparisonFormulaText: this.comparisonFormulaText,
                    opportunityFieldValuesJson: JSON.stringify(this.preparedOpportunity)
                })
            });

            if (!response.isSuccess || !response.previewData) {
                throw new Error(response.errorMessage || this._getLabel('errorLoadPreviewMessage'));
            }

            this.previewRows = response.previewData.previewRows || [];
            this.selectedPreviewAccountIds = this.previewRows.map((previewRow) => previewRow.accountId);
            await this._loadPreviewLookupDisplayValues();
        } catch (error) {
            this.errorMessage = this._formatError(error) || this._getLabel('errorLoadPreviewMessage');
        } finally {
            this.activeAsyncOperationCount = Math.max(0, this.activeAsyncOperationCount - 1);
        }
    }

    /** Collects unique ids from selected rows for a given JSON field. */
    _collectUniqueIds(jsonFieldName) {
        const uniqueIds = new Set();

        this.selectedReportRows.forEach((reportRow) => {
            this._parseJsonArray(reportRow[jsonFieldName]).forEach((recordId) => uniqueIds.add(recordId));
        });

        return [...uniqueIds].sort();
    }

    /** Collects the current shared Opportunity field values from the details step. */
    _collectOpportunityFieldValues() {
        if (Object.keys(this.preparedOpportunity).length === 0) {
            return { ...this.opportunityFieldValues };
        }

        const opportunityFieldValues = { ...this.preparedOpportunity };
        delete opportunityFieldValues.RecordTypeId;
        return opportunityFieldValues;
    }

    /** Saves the currently active step state into the explicit cache for steps 1, 2, and 3 only. */
    _cacheCurrentStepState() {
        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.REPORT_SELECTION) {
            this._cacheReportSelectionState();
            return;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.OPPORTUNITY_CREATION_STRATEGY) {
            this._cacheOpportunityCreationStrategyState();
            return;
        }

        if (this.currentStep === CONSTANTS.UI.PATH_STEPS.NEW_OPPORTUNITY_DETAILS) {
            this._cacheNewOpportunityDetailsState();
        }
    }

    /** Saves the latest step-1 state so report selection and search inputs can be restored. */
    _cacheReportSelectionState() {
        this.stepStateCache = {
            ...this.stepStateCache,
            reportSelection: {
                selectedReportIds: [...this.selectedReportIds],
                searchInputValue: this.searchInputValue,
                searchTerm: this.searchTerm,
                sortBy: this.sortBy,
                sortDirection: this.sortDirection
            }
        };
    }

    /** Saves the latest step-2 state so duplicate-filter inputs can be restored. */
    _cacheOpportunityCreationStrategyState() {
        this.stepStateCache = {
            ...this.stepStateCache,
            opportunityCreationStrategy: {
                selectedCreationStrategy: this.selectedCreationStrategy,
                comparisonConditions: this.comparisonConditions.map((comparisonCondition) => ({
                    ...comparisonCondition
                })),
                comparisonFormulaText: this.comparisonFormulaText
            }
        };
    }

    /** Saves the latest step-3 state so the shared Opportunity form values can be restored. */
    _cacheNewOpportunityDetailsState() {
        this.stepStateCache = {
            ...this.stepStateCache,
            newOpportunityDetails: {
                opportunityFieldValues: { ...this.opportunityFieldValues },
                preparedOpportunity: { ...this.preparedOpportunity }
            }
        };
    }

    /** Restores the latest cached step-1 state before returning to report selection. */
    _restoreReportSelectionState() {
        const cachedState = this.stepStateCache.reportSelection;
        this.selectedReportIds = [...cachedState.selectedReportIds];
        this.searchInputValue = cachedState.searchInputValue;
        this.searchTerm = cachedState.searchTerm;
        this.sortBy = cachedState.sortBy;
        this.sortDirection = cachedState.sortDirection;
    }

    /** Restores the latest cached step-2 state before returning to the strategy builder. */
    _restoreOpportunityCreationStrategyState() {
        const cachedState = this.stepStateCache.opportunityCreationStrategy;
        this.selectedCreationStrategy = cachedState.selectedCreationStrategy;
        this.comparisonConditions = cachedState.comparisonConditions.map((comparisonCondition) => ({
            ...comparisonCondition
        }));
        this.comparisonFormulaText = cachedState.comparisonFormulaText;
    }

    /** Restores the latest cached step-3 state before returning to the Opportunity details form. */
    _restoreNewOpportunityDetailsState() {
        const cachedState = this.stepStateCache.newOpportunityDetails;
        this.opportunityFieldValues = { ...cachedState.opportunityFieldValues };
        this.preparedOpportunity = { ...cachedState.preparedOpportunity };
    }

    /** Returns the read-only display value rendered in the preview values block. */
    _getPreviewFieldDisplayValue(fieldApiName, fieldValue) {
        if (fieldValue === null || fieldValue === undefined || fieldValue === '') {
            return CONSTANTS.PLACEHOLDERS.DASH;
        }

        if (fieldApiName === CONSTANTS.FIELDS.STAGE_NAME) {
            return this.stageNameOptions.find((stageOption) => stageOption.value === fieldValue)?.label || fieldValue;
        }

        return String(fieldValue);
    }

    /** Returns the read-only preview lookup display value for one field. */
    _getPreviewLookupDisplayValue(fieldApiName, fallbackValue) {
        const resolvedLookupDisplayValue = this.previewLookupDisplayValuesByField[fieldApiName];

        if (!resolvedLookupDisplayValue?.recordName) {
            return this._getPreviewFieldDisplayValue(fieldApiName, fallbackValue);
        }

        return resolvedLookupDisplayValue.recordName;
    }

    /** Returns the record URL for one read-only preview lookup field. */
    _getPreviewLookupUrl(fieldApiName) {
        const resolvedLookupDisplayValue = this.previewLookupDisplayValuesByField[fieldApiName];

        if (!resolvedLookupDisplayValue?.recordId || !resolvedLookupDisplayValue?.recordApiName) {
            return '';
        }

        return `/lightning/r/${resolvedLookupDisplayValue.recordApiName}/${resolvedLookupDisplayValue.recordId}/view`;
    }

    /** Returns the Opportunity field data type from describe metadata for one API name. */
    _getOpportunityFieldDataType(fieldApiName) {
        return String(this.opportunityObjectInfo.data?.fields?.[fieldApiName]?.dataType || '');
    }

    /** Loads preview lookup display values for read-only step-4 fields that currently contain lookup record ids. */
    async _loadPreviewLookupDisplayValues() {
        const previewOpportunityValues = this._collectOpportunityFieldValues();
        const previewLookupFieldValueEntries = this.requestFieldSetFields
            .filter((fieldConfig) =>
                fieldConfig?.apiName &&
                this._getOpportunityFieldDataType(fieldConfig.apiName) === 'Reference'
            )
            .map((fieldConfig) => ({
                fieldApiName: fieldConfig.apiName,
                recordId: previewOpportunityValues[fieldConfig.apiName] || ''
            }))
            .filter((lookupFieldValueEntry) => lookupFieldValueEntry.recordId !== '');

        if (previewLookupFieldValueEntries.length === 0) {
            this.previewLookupDisplayValuesByField = {};
            return;
        }

        const response = await resolvePreviewLookupDisplayValues({
            request: JSON.stringify({
                lookupFieldValueEntriesJson: JSON.stringify(previewLookupFieldValueEntries)
            })
        });

        if (!response.isSuccess) {
            throw new Error(response.errorMessage || this._getLabel('errorLoadPreviewMessage'));
        }

        this.previewLookupDisplayValuesByField = (response.lookupDisplayValues || []).reduce(
            (lookupDisplayValuesByField, lookupDisplayValue) => ({
                ...lookupDisplayValuesByField,
                [lookupDisplayValue.fieldApiName]: { ...lookupDisplayValue }
            }),
            {}
        );
    }

    /** Returns the duplicate-filter validation error for step 2, or an empty string when the step is valid. */
    _getOpportunityCreationStrategyValidationError() {
        if (!this.isDuplicateValidationStrategy) {
            return '';
        }

        if (this.comparisonConditions.some((comparisonCondition) =>
            !comparisonCondition.fieldApiName || !comparisonCondition.operator
        )) {
            return this._getLabel('errorSelectComparisonFields');
        }

        return this._getComparisonFormulaValidationResult(this.comparisonFormulaText, this.comparisonConditions.length)
            .errorMessage;
    }

    /** Applies the current formula validation message to the rendered formula input without reporting it. */
    _syncComparisonFormulaInputValidity() {
        const formulaInput = this.template.querySelector('[data-id="comparison-formula-input"]');

        if (!formulaInput) {
            return;
        }

        this._applyComparisonFormulaInputValidity(formulaInput);
    }

    /** Applies the current formula validation message to one rendered formula input. */
    _applyComparisonFormulaInputValidity(formulaInput) {
        const validationResult = this._getComparisonFormulaValidationResult(
            this.comparisonFormulaText,
            this.comparisonConditions.length
        );

        formulaInput.setCustomValidity(validationResult.isValid ? '' : validationResult.errorMessage);
        return validationResult;
    }

    /** Creates one empty duplicate-filter condition row. */
    _createComparisonCondition(rowNumber) {
        return {
            rowNumber,
            fieldApiName: rowNumber === 1 ? CONSTANTS.FIELDS.STAGE_NAME : '',
            operator: '',
            value: ''
        };
    }

    /** Returns the initial duplicate-filter rows shown when the strategy requires duplicate matching. */
    _getInitialComparisonConditions() {
        return [this._createComparisonCondition(1)];
    }

    /** Returns the initial duplicate-filter formula shown when the strategy requires duplicate matching. */
    _getInitialComparisonFormulaText() {
        return CONSTANTS.STRATEGY.DEFAULT_FORMULA;
    }

    /** Returns the default duplicate-filter formula for a given number of rows. */
    _buildDefaultComparisonFormula(conditionCount) {
        if (conditionCount <= 0) {
            return '';
        }

        return Array.from({ length: conditionCount }, (_, conditionIndex) => String(conditionIndex + 1)).join(' AND ');
    }

    /** Returns true when the supplied formula matches the default formula for the supplied row count. */
    _isDefaultComparisonFormula(formulaText, conditionCount) {
        return String(formulaText || '').trim() === this._buildDefaultComparisonFormula(conditionCount);
    }

    /** Renumbers duplicate-filter conditions sequentially after add or remove operations. */
    _renumberComparisonConditions(comparisonConditions) {
        return comparisonConditions.map((comparisonCondition, conditionIndex) => ({
            ...comparisonCondition,
            rowNumber: conditionIndex + 1
        }));
    }

    /** Returns the rendered value-control type for one Opportunity field. */
    _getComparisonValueType(fieldApiName) {
        const fieldDataType = String(this.opportunityObjectInfo.data?.fields?.[fieldApiName]?.dataType || '');

        if (fieldDataType === 'Picklist' || fieldDataType === 'MultiPicklist') {
            return CONSTANTS.STRATEGY.VALUE_TYPES.PICKLIST;
        }

        if (fieldDataType === 'Boolean') {
            return CONSTANTS.STRATEGY.VALUE_TYPES.BOOLEAN;
        }

        if (
            fieldDataType === 'Currency' ||
            fieldDataType === 'Double' ||
            fieldDataType === 'Int' ||
            fieldDataType === 'Integer' ||
            fieldDataType === 'Long' ||
            fieldDataType === 'Percent'
        ) {
            return CONSTANTS.STRATEGY.VALUE_TYPES.NUMBER;
        }

        if (fieldDataType === 'Date') {
            return CONSTANTS.STRATEGY.VALUE_TYPES.DATE;
        }

        if (fieldDataType === 'DateTime') {
            return CONSTANTS.STRATEGY.VALUE_TYPES.DATETIME;
        }

        return CONSTANTS.STRATEGY.VALUE_TYPES.TEXT;
    }

    /** Returns the supported operator options for one selected duplicate-filter field. */
    _getComparisonOperatorOptions(fieldApiName) {
        const valueType = this._getComparisonValueType(fieldApiName);

        if (!fieldApiName) {
            return [];
        }

        if (
            valueType === CONSTANTS.STRATEGY.VALUE_TYPES.NUMBER ||
            valueType === CONSTANTS.STRATEGY.VALUE_TYPES.DATE ||
            valueType === CONSTANTS.STRATEGY.VALUE_TYPES.DATETIME
        ) {
            return this._sortOptionsByLabel([
                { label: this._getLabel('comparisonOperatorEquals'), value: CONSTANTS.STRATEGY.OPERATORS.EQUALS },
                { label: this._getLabel('comparisonOperatorNotEquals'), value: CONSTANTS.STRATEGY.OPERATORS.NOT_EQUALS },
                { label: this._getLabel('comparisonOperatorGreaterThan'), value: CONSTANTS.STRATEGY.OPERATORS.GREATER_THAN },
                { label: this._getLabel('comparisonOperatorGreaterOrEqual'), value: CONSTANTS.STRATEGY.OPERATORS.GREATER_OR_EQUAL },
                { label: this._getLabel('comparisonOperatorLessThan'), value: CONSTANTS.STRATEGY.OPERATORS.LESS_THAN },
                { label: this._getLabel('comparisonOperatorLessOrEqual'), value: CONSTANTS.STRATEGY.OPERATORS.LESS_OR_EQUAL }
            ]);
        }

        if (valueType === CONSTANTS.STRATEGY.VALUE_TYPES.TEXT) {
            return this._sortOptionsByLabel([
                { label: this._getLabel('comparisonOperatorEquals'), value: CONSTANTS.STRATEGY.OPERATORS.EQUALS },
                { label: this._getLabel('comparisonOperatorNotEquals'), value: CONSTANTS.STRATEGY.OPERATORS.NOT_EQUALS },
                { label: this._getLabel('comparisonOperatorContains'), value: CONSTANTS.STRATEGY.OPERATORS.CONTAINS },
                { label: this._getLabel('comparisonOperatorStartsWith'), value: CONSTANTS.STRATEGY.OPERATORS.STARTS_WITH }
            ]);
        }

        return this._sortOptionsByLabel([
            { label: this._getLabel('comparisonOperatorEquals'), value: CONSTANTS.STRATEGY.OPERATORS.EQUALS },
            { label: this._getLabel('comparisonOperatorNotEquals'), value: CONSTANTS.STRATEGY.OPERATORS.NOT_EQUALS }
        ]);
    }

    /** Returns the allowed picklist-style values for one selected duplicate-filter field. */
    _getComparisonValueOptions(fieldApiName) {
        const valueType = this._getComparisonValueType(fieldApiName);

        if (valueType === CONSTANTS.STRATEGY.VALUE_TYPES.BOOLEAN) {
            return this._sortOptionsByLabel([
                { label: this._getLabel('booleanTrueOption'), value: 'true' },
                { label: this._getLabel('booleanFalseOption'), value: 'false' }
            ]);
        }

        if (valueType !== CONSTANTS.STRATEGY.VALUE_TYPES.PICKLIST) {
            return [];
        }

        const picklistOptions = (this.opportunityPicklistValues.data?.picklistFieldValues?.[fieldApiName]?.values || []).map(
            (picklistValue) => ({
                label: picklistValue.label,
                value: picklistValue.value
            })
        );
        const existingValues = new Set(picklistOptions.map((picklistOption) => picklistOption.value));

        if (fieldApiName === CONSTANTS.FIELDS.STAGE_NAME) {
            this.additionalStageValues.forEach((stageValue) => {
                if (!existingValues.has(stageValue)) {
                    picklistOptions.push({
                        label: stageValue,
                        value: stageValue
                    });
                }
            });
        }

        return this._sortOptionsByLabel(picklistOptions);
    }

    /** Returns one combobox option list sorted alphabetically by localized label. */
    _sortOptionsByLabel(options) {
        return [...options].sort((leftOption, rightOption) =>
            (leftOption?.label || '').localeCompare(rightOption?.label || '', USER_LANGUAGE, { sensitivity: 'base' })
        );
    }

    /** Normalizes one duplicate-filter value after its field type changes. */
    _normalizeComparisonConditionValue(currentValue, valueType, fieldApiName) {
        if (currentValue === '' || currentValue === null || currentValue === undefined) {
            return '';
        }

        if (
            valueType === CONSTANTS.STRATEGY.VALUE_TYPES.PICKLIST ||
            valueType === CONSTANTS.STRATEGY.VALUE_TYPES.BOOLEAN
        ) {
            return this._getComparisonValueOptions(fieldApiName).some(
                (valueOption) => valueOption.value === currentValue
            )
                ? currentValue
                : '';
        }

        return currentValue;
    }

    /** Returns the duplicate-filter conditions serialized for Apex preview evaluation. */
    _buildComparisonConditionsJson() {
        if (!this.isDuplicateValidationStrategy) {
            return CONSTANTS.JSON.EMPTY_ARRAY;
        }

        return JSON.stringify(
            this.comparisonConditions.map((comparisonCondition) => ({
                rowNumber: comparisonCondition.rowNumber,
                fieldApiName: comparisonCondition.fieldApiName,
                operator: comparisonCondition.operator,
                value: comparisonCondition.value === '' ? null : comparisonCondition.value
            }))
        );
    }

    /** Validates the duplicate-filter formula against required rows, parentheses, and supported syntax. */
    _getComparisonFormulaValidationResult(formulaText, maxConditionNumber) {
        const normalizedFormulaText = String(formulaText || '').trim();

        if (normalizedFormulaText === '') {
            return {
                isValid: false,
                errorMessage: this._getLabel('errorComparisonFormulaRequired')
            };
        }

        const rawFormulaTokens = normalizedFormulaText.match(/\d+|&&|\|\||AND|OR|\(|\)/gi) || [];
        const normalizedFormulaTokens = rawFormulaTokens.map((formulaToken) => {
            const uppercaseToken = formulaToken.toUpperCase();

            if (uppercaseToken === '&&') {
                return 'AND';
            }

            if (uppercaseToken === '||') {
                return 'OR';
            }

            return uppercaseToken;
        });

        if (rawFormulaTokens.length === 0) {
            return {
                isValid: false,
                errorMessage: this._getLabel('errorComparisonFormulaInvalidTokens')
            };
        }

        if (
            rawFormulaTokens.join('').toUpperCase() !== normalizedFormulaText.replace(/\s+/g, '').toUpperCase()
        ) {
            return {
                isValid: false,
                errorMessage: this._getLabel('errorComparisonFormulaInvalidTokens')
            };
        }

        let tokenIndex = 0;
        const referencedConditionNumbers = new Set();

        const parseFactor = () => {
            const currentToken = normalizedFormulaTokens[tokenIndex];

            if (currentToken === '(') {
                tokenIndex += 1;

                if (!parseExpression()) {
                    return { isValid: false, errorKey: 'errorComparisonFormulaInvalidSyntax' };
                }

                if (normalizedFormulaTokens[tokenIndex] !== ')') {
                    return { isValid: false, errorKey: 'errorComparisonFormulaInvalidParentheses' };
                }

                tokenIndex += 1;
                return { isValid: true, errorKey: '' };
            }

            const conditionNumber = Number(currentToken);

            if (!Number.isInteger(conditionNumber) || conditionNumber < 1) {
                return { isValid: false, errorKey: 'errorComparisonFormulaInvalidSyntax' };
            }

            if (conditionNumber > maxConditionNumber) {
                return { isValid: false, errorKey: 'errorComparisonFormulaConditionCountMismatch' };
            }

            referencedConditionNumbers.add(conditionNumber);
            tokenIndex += 1;
            return { isValid: true, errorKey: '' };
        };

        const parseTerm = () => {
            const factorResult = parseFactor();

            if (!factorResult.isValid) {
                return factorResult;
            }

            while (normalizedFormulaTokens[tokenIndex] === 'AND') {
                tokenIndex += 1;

                const nextFactorResult = parseFactor();

                if (!nextFactorResult.isValid) {
                    return nextFactorResult;
                }
            }

            return { isValid: true, errorKey: '' };
        };

        const parseExpression = () => {
            const termResult = parseTerm();

            if (!termResult.isValid) {
                return termResult;
            }

            while (normalizedFormulaTokens[tokenIndex] === 'OR') {
                tokenIndex += 1;

                const nextTermResult = parseTerm();

                if (!nextTermResult.isValid) {
                    return nextTermResult;
                }
            }

            return { isValid: true, errorKey: '' };
        };

        const parseResult = parseExpression();

        if (!parseResult.isValid) {
            return {
                isValid: false,
                errorMessage: this._getLabel(parseResult.errorKey)
            };
        }

        if (tokenIndex !== normalizedFormulaTokens.length) {
            return {
                isValid: false,
                errorMessage: this._getLabel('errorComparisonFormulaInvalidSyntax')
            };
        }

        const missingConditionExists = Array.from(
            { length: maxConditionNumber },
            (_, conditionIndex) => conditionIndex + 1
        ).some((conditionNumber) => !referencedConditionNumbers.has(conditionNumber));

        if (missingConditionExists) {
            return {
                isValid: false,
                errorMessage: this._getLabel('errorComparisonFormulaMissingFields')
            };
        }

        return {
            isValid: true,
            errorMessage: ''
        };
    }

    /** Remaps formula row numbers after one condition row is removed. */
    _remapComparisonFormula(formulaText, removedConditionIndex) {
        const removedRowNumber = removedConditionIndex + 1;

        return String(formulaText || '').replace(/\d+/g, (matchedNumberText) => {
            const matchedNumber = Number(matchedNumberText);

            if (matchedNumber <= removedRowNumber) {
                return matchedNumberText;
            }

            return String(matchedNumber - 1);
        });
    }

    /** Builds the final shared Opportunity payload from the rendered form controls. */
    _buildPreparedOpportunity() {
        const preparedOpportunity = {
            RecordTypeId: this.requestRecordTypeId
        };
        const stageNameInput = this.template.querySelector('[data-id="opportunity-stage-input"]');

        [...this.template.querySelectorAll('[data-id="opportunity-input-field"]')].forEach((inputField) => {
            if (inputField.fieldName) {
                preparedOpportunity[inputField.fieldName] = inputField.value;
            }
        });

        if (stageNameInput) {
            preparedOpportunity[CONSTANTS.FIELDS.STAGE_NAME] = stageNameInput.value;
        }

        return preparedOpportunity;
    }

    /** Returns the selected report rows serialized for the preview Apex request. */
    _buildSelectedPreviewReportRowsJson() {
        return JSON.stringify(
            this.selectedReportRows.map((reportRow) => ({
                value: reportRow.value,
                label: reportRow.label,
                shortLabel: reportRow.shortLabel,
                eligibleAccountIdsJson: reportRow.eligibleAccountIdsJson
            }))
        );
    }

    /** Parses a JSON array string into a JavaScript array. */
    _parseJsonArray(value) {
        if (!value) {
            return [];
        }

        try {
            const parsedValue = JSON.parse(value);
            return Array.isArray(parsedValue) ? [...parsedValue] : [];
        } catch {
            return [];
        }
    }

    /** Opens one Salesforce record page in a new browser tab from a direct table-click gesture. */
    _openRecordInNewTab(url) {
        if (!url) {
            return;
        }

        window.open(url, '_blank');
    }

    /** Compares two datatable rows according to the current sort state. */
    _compareRows(leftRow, rightRow) {
        const leftValue = leftRow[this.sortBy];
        const rightValue = rightRow[this.sortBy];
        let result = 0;

        if (typeof leftValue === 'number' || typeof rightValue === 'number') {
            result = (leftValue ?? -1) - (rightValue ?? -1);
        } else {
            result = String(leftValue ?? '').localeCompare(String(rightValue ?? ''));
        }

        return this.sortDirection === 'asc' ? result : result * -1;
    }

    /** Builds the localized datatable columns. */
    _buildColumns() {
        return [
            {
                label: this._getLabel('reportNameColumn'),
                fieldName: 'shortLabel',
                type: 'button',
                sortable: true,
                cellAttributes: {
                    class: { fieldName: 'reportNameCellClass' }
                },
                typeAttributes: {
                    label: { fieldName: 'shortLabel' },
                    name: 'openReport',
                    variant: 'base',
                    disabled: { fieldName: 'isDisabled' }
                }
            },
            {
                label: this._getLabel('reportTypeColumn'),
                fieldName: 'reportTypeDisplayValue',
                type: 'text',
                sortable: true,
                cellAttributes: {
                    class: { fieldName: 'reportTypeCellClass' }
                }
            },
            {
                label: this._getLabel('accountCountColumn'),
                fieldName: 'accountCountDisplayValue',
                type: 'text',
                sortable: true,
                cellAttributes: {
                    alignment: 'left',
                    class: { fieldName: 'accountCountCellClass' }
                }
            },
            {
                label: this._getLabel('statusColumn'),
                fieldName: 'statusLabel',
                type: 'text',
                sortable: true,
                cellAttributes: {
                    class: { fieldName: 'statusCellClass' }
                }
            }
        ];
    }

    /** Normalizes one Apex row for local datatable state. */
    _normalizeReportRow(reportRow, extraValues = {}) {
        return this._decorateReportRow({
            ...reportRow,
            id: reportRow.value,
            shortLabel: reportRow.shortLabel || reportRow.label,
            reportTypeDisplayValue: this._getReportTypeLabel(reportRow.reportType) || CONSTANTS.PLACEHOLDERS.DASH,
            accountCount: Number.isInteger(reportRow.accountCount) ? reportRow.accountCount : null,
            accountCountDisplayValue: Number.isInteger(reportRow.accountCount)
                ? String(reportRow.accountCount)
                : CONSTANTS.PLACEHOLDERS.DASH,
            eligibleAccountCount: Number.isInteger(reportRow.eligibleAccountCount) ? reportRow.eligibleAccountCount : null,
            statusLabel: reportRow.statusLabel || '',
            statusToneClass: reportRow.statusToneClass || '',
            accountIdsJson: reportRow.accountIdsJson || CONSTANTS.JSON.EMPTY_ARRAY,
            eligibleAccountIdsJson: reportRow.eligibleAccountIdsJson || CONSTANTS.JSON.EMPTY_ARRAY,
            isCountsLoaded: Number.isInteger(reportRow.accountCount) && Number.isInteger(reportRow.eligibleAccountCount),
            isDisabled: false,
            isSupportedType: reportRow.isSupportedType !== false,
            ...extraValues
        });
    }

    /** Updates one row in the modal state. */
    _updateReportRow(reportId, updatedValues) {
        this.reportRows = this.reportRows.map((reportRow) =>
            reportRow.value === reportId
                ? this._decorateReportRow({ ...reportRow, ...updatedValues })
                : reportRow
        );
    }

    /** Resolves one localized label from the current direction. */
    _getLabel(key) {
        return CONSTANTS.UI.DEFAULT_LABELS[this.direction][key] || key;
    }

    /** Formats one localized label with positional placeholders. */
    _formatLabel(key, ...values) {
        return values.reduce(
            (formattedLabel, value, index) => formattedLabel.replace(`{${index}}`, value),
            this._getLabel(key)
        );
    }

    /** Formats one platform error into a user-facing string. */
    _formatError(error) {
        const { body, message } = error ?? {};

        if (Array.isArray(body)) {
            return body.map(({ message: bodyMessage }) => bodyMessage).join(CONSTANTS.ERRORS.MESSAGES_SEPARATOR);
        }

        return body?.message || message || '';
    }

    /** Returns the localized report type label. */
    _getReportTypeLabel(reportType) {
        if (reportType === CONSTANTS.STATUS.ACCOUNT) {
            return this._getLabel('accountReportType');
        }

        if (reportType === CONSTANTS.STATUS.CONTACTS_AND_ACCOUNTS) {
            return this._getLabel('contactsAndAccountsReportType');
        }

        return reportType || '';
    }

    /** Applies row-level cell classes according to disabled and status state. */
    _decorateReportRow(reportRow) {
        const resolvedStatusLabel = reportRow.statusLabel || (!reportRow.isCountsLoaded ? this._getLabel('notRetrievedStatus') : '');
        const disabledCellClass = reportRow.isDisabled ? 'report-row-disabled-opacity' : '';
        const statusCellClass = this._joinCellClasses(reportRow.statusToneClass || '', disabledCellClass);

        return {
            ...reportRow,
            statusLabel: resolvedStatusLabel,
            reportNameCellClass: disabledCellClass,
            reportTypeCellClass: disabledCellClass,
            accountCountCellClass: disabledCellClass,
            statusCellClass
        };
    }

    /** Joins multiple cell class fragments into one datatable class string. */
    _joinCellClasses(...classNames) {
        return classNames.filter((className) => className).join(' ');
    }

    /** Injects one CSS patch into the datatable host so custom cell classes can dim text. */
    _applyDatatableCellOpacityPatch() {
        const styleId = CONSTANTS.CSS.DATATABLE_PATCH_STYLE_ID;
        const baseComponentHost = this.template.querySelector('[data-id="reportDatatable"]');

        if (!baseComponentHost || baseComponentHost.querySelector(`style[data-id="${styleId}"]`)) {
            return;
        }

        // eslint-disable-next-line @lwc/lwc/no-inner-html
        baseComponentHost.insertAdjacentHTML(
            'beforeend',
            `<style data-id="${styleId}">${CONSTANTS.CSS.DATATABLE_PATCH_CSS_TEXT}</style>`
        );
    }

    /** Injects one runtime CSS patch into lightning-modal-body so the modal no longer keeps its own native scroll. */
    _applyModalBodyOverflowHiddenPatch() {
        const styleId = CONSTANTS.CSS.MODAL_BODY_PATCH_STYLE_ID;
        const baseComponentHost = this.template.querySelector('lightning-modal-body');

        if (!baseComponentHost || baseComponentHost.querySelector(`style[data-id="${styleId}"]`)) {
            return;
        }

        // eslint-disable-next-line @lwc/lwc/no-inner-html
        baseComponentHost.insertAdjacentHTML(
            'beforeend',
            `<style data-id="${styleId}">${CONSTANTS.CSS.MODAL_BODY_PATCH_CSS_TEXT}</style>`
        );
    }

    /** Clears the active search debounce timer. */
    _clearSearchDebounce() {
        if (!this.searchDebounceTimeoutId) {
            return;
        }

        clearTimeout(this.searchDebounceTimeoutId);
        this.searchDebounceTimeoutId = null;
    }

    /** Starts one step transition, yields one paint frame for the spinner, and only then swaps the active step. */
    async _runDeferredStepTransition(nextStep) {
        this._beginStepTransition(nextStep);
        await this._yieldForTransitionSpinnerPaint();

        if (!this.pendingRenderedStep || this.pendingRenderedStep !== nextStep) {
            return;
        }

        this.currentStep = nextStep;
    }

    /** Starts one configured transition spinner before the target step is assigned after async preloading. */
    _beginStepTransition(nextStep) {
        const transitionConfig = this._getStepConfig(nextStep);

        this._clearPendingStepTransitionTimeout();
        this._clearPendingStepAwaitNextRenderTimeout();
        this._clearPendingStepRenderPollTimeout();
        this.pendingRenderedStep = nextStep;
        this.pendingStepRenderPollCycleCount = 0;
        this.isPendingStepAwaitingNextRender = false;
        this.activeAsyncOperationCount += 1;
        this.isGlobalTransitionPending = transitionConfig.spinnerType === CONSTANTS.STEP_CONFIG.SPINNER_TYPES.GLOBAL;
    }

    /** Cancels the currently pending step transition without changing the shown step. */
    _cancelPendingStepTransition() {
        this._clearPendingStepTransitionTimeout();
        this._clearPendingStepAwaitNextRenderTimeout();
        this._clearPendingStepRenderPollTimeout();
        this.pendingRenderedStep = '';
        this.pendingStepRenderPollCycleCount = 0;
        this.isPendingStepAwaitingNextRender = false;
        this.isGlobalTransitionPending = false;
        this.activeAsyncOperationCount = Math.max(0, this.activeAsyncOperationCount - 1);
    }

    /** Completes the currently pending step transition after the target step DOM is fully rendered. */
    _completeStepTransitionAfterRender() {
        if (!this.pendingRenderedStep || this.pendingRenderedStep !== this.currentStep) {
            return;
        }

        if (!this._isPendingStepRenderComplete()) {
            this._schedulePendingStepRenderPoll();
            return;
        }

        this._clearPendingStepRenderPollTimeout();
        if (!this.isPendingStepAwaitingNextRender) {
            this.isPendingStepAwaitingNextRender = true;
            this.pendingStepRenderGuardToken += 1;
            this._schedulePendingStepAwaitNextRenderTimeout();
            return;
        }

        this._clearPendingStepAwaitNextRenderTimeout();
        const settleDelay = this._getPendingStepTransitionSettleDelay();

        if (settleDelay > 0) {
            if (this.pendingStepTransitionTimeoutId) {
                return;
            }

            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this.pendingStepTransitionTimeoutId = setTimeout(() => {
                this.pendingStepTransitionTimeoutId = null;

                if (!this.pendingRenderedStep || this.pendingRenderedStep !== this.currentStep) {
                    return;
                }

                this._finishPendingStepTransition();
            }, settleDelay);
            return;
        }

        this._finishPendingStepTransition();
    }

    /** Returns true when the target step render targets are available in DOM and the spinner can start settling. */
    _isPendingStepRenderComplete() {
        const renderTargetConfig = this._getPendingStepRenderTargetConfig();

        if (!renderTargetConfig) {
            return true;
        }

        if (
            Array.isArray(renderTargetConfig.requiredSelectors) &&
            renderTargetConfig.requiredSelectors.some((requiredSelector) => !this.template.querySelector(requiredSelector))
        ) {
            return false;
        }

        if (!renderTargetConfig.requiredSelectorCountBySelector) {
            return true;
        }

        return Object.entries(renderTargetConfig.requiredSelectorCountBySelector).every(([selector, expectedCount]) =>
            this.template.querySelectorAll(selector).length === expectedCount
        );
    }

    /** Returns the configured transition behavior for one target step. */
    _getStepConfig(stepName) {
        return CONSTANTS.STEP_CONFIG.STEP_CONFIG_BY_TARGET[stepName] || {
            spinnerType: CONSTANTS.STEP_CONFIG.SPINNER_TYPES.GLOBAL,
            scrollableSectionMode: CONSTANTS.STEP_CONFIG.SCROLLABLE_SECTION_MODES.INTERNAL,
            settleDelayMs: 0,
            renderTargetConfig: null
        };
    }

    /** Returns the scroll mode configured for the currently rendered step content section. */
    _getCurrentStepScrollableSectionMode() {
        return this._getStepConfig(this.currentStep)?.scrollableSectionMode ?? CONSTANTS.STEP_CONFIG.SCROLLABLE_SECTION_MODES.INTERNAL;
    }

    /** Returns the fully configured render-target contract for the pending step transition. */
    _getPendingStepRenderTargetConfig() {
        const transitionConfig = this._getStepConfig(this.pendingRenderedStep);
        const renderTargetConfig = transitionConfig.renderTargetConfig;

        if (!renderTargetConfig) {
            return null;
        }

        if (renderTargetConfig.fieldSetDrivenRequiredDataIdCountKeys) {
            if (!this.showRequestOpportunityForm || !this.hasOpportunityCreateLayout) {
                return null;
            }

            return {
                requiredSelectorCountBySelector: {
                    [this._getDataIdSelector(renderTargetConfig.fieldSetDrivenRequiredDataIdCountKeys.regularInputs)]: this.opportunityFormFields.filter(
                        (fieldConfig) => fieldConfig.isStageOverride !== true
                    ).length,
                    [this._getDataIdSelector(renderTargetConfig.fieldSetDrivenRequiredDataIdCountKeys.stageInputs)]: this.opportunityFormFields.some(
                        (fieldConfig) => fieldConfig.isStageOverride === true
                    )
                        ? 1
                        : 0
                }
            };
        }

        const requiredDataIds = Array.isArray(renderTargetConfig.requiredDataIds)
            ? [...renderTargetConfig.requiredDataIds]
            : [];

        if (this.showComparisonConditionBuilder && Array.isArray(renderTargetConfig.comparisonBuilderRequiredDataIds)) {
            requiredDataIds.push(...renderTargetConfig.comparisonBuilderRequiredDataIds);
        }

        if (requiredDataIds.length === 0) {
            return null;
        }

        return {
            requiredSelectors: requiredDataIds.map((dataId) => this._getDataIdSelector(dataId))
        };
    }

    /** Returns the template selector for one configured data-id. */
    _getDataIdSelector(dataId) {
        return `[data-id="${dataId}"]`;
    }

    /** Returns the per-step settle delay used after the pending step render targets appear in DOM. */
    _getPendingStepTransitionSettleDelay() {
        return this._getStepConfig(this.pendingRenderedStep)?.settleDelayMs ?? 0;
    }

    /** Finishes the active step transition and unlocks the footer buttons. */
    _finishPendingStepTransition() {
        this._clearPendingStepTransitionTimeout();
        this._clearPendingStepAwaitNextRenderTimeout();
        this._clearPendingStepRenderPollTimeout();
        this.pendingRenderedStep = '';
        this.pendingStepRenderPollCycleCount = 0;
        this.isPendingStepAwaitingNextRender = false;
        this.isGlobalTransitionPending = false;
        this.activeAsyncOperationCount = Math.max(0, this.activeAsyncOperationCount - 1);
    }

    /** Clears the delayed pending-transition timeout when it exists. */
    _clearPendingStepTransitionTimeout() {
        if (!this.pendingStepTransitionTimeoutId) {
            return;
        }

        clearTimeout(this.pendingStepTransitionTimeoutId);
        this.pendingStepTransitionTimeoutId = null;
    }

    /** Clears the fallback timeout that waits for the next renderedCallback after all required DOM nodes appear. */
    _clearPendingStepAwaitNextRenderTimeout() {
        if (!this.pendingStepAwaitNextRenderTimeoutId) {
            return;
        }

        clearTimeout(this.pendingStepAwaitNextRenderTimeoutId);
        this.pendingStepAwaitNextRenderTimeoutId = null;
    }

    /** Schedules a fallback that finishes the pending transition if the next renderedCallback does not arrive in time. */
    _schedulePendingStepAwaitNextRenderTimeout() {
        if (this.pendingStepAwaitNextRenderTimeoutId) {
            return;
        }

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.pendingStepAwaitNextRenderTimeoutId = setTimeout(() => {
            this.pendingStepAwaitNextRenderTimeoutId = null;

            if (!this.pendingRenderedStep || !this.isPendingStepAwaitingNextRender) {
                return;
            }

            this._finishPendingStepTransition();
        }, CONSTANTS.TIMERS.TRANSITION_RENDER_NEXT_CALLBACK_TIMEOUT_MS);
    }

    /** Schedules one polling cycle that re-checks whether the target step finished rendering. */
    _schedulePendingStepRenderPoll() {
        if (this.pendingStepRenderPollTimeoutId) {
            return;
        }

        if (this.pendingStepRenderPollCycleCount >= CONSTANTS.TIMERS.MAX_TRANSITION_RENDER_POLL_CYCLES) {
            this._finishPendingStepTransition();
            return;
        }

        this.pendingStepRenderPollCycleCount += 1;

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.pendingStepRenderPollTimeoutId = setTimeout(() => {
            this.pendingStepRenderPollTimeoutId = null;
            this._completeStepTransitionAfterRender();
        }, CONSTANTS.TIMERS.TRANSITION_RENDER_POLL_MS);
    }

    /** Clears the pending render-poll timer when it exists. */
    _clearPendingStepRenderPollTimeout() {
        if (!this.pendingStepRenderPollTimeoutId) {
            return;
        }

        clearTimeout(this.pendingStepRenderPollTimeoutId);
        this.pendingStepRenderPollTimeoutId = null;
    }

    /** Initializes ResizeObserver hooks used by the dynamic content-height measurement logic. */
    _initializeLayoutObservers() {
        if (typeof ResizeObserver !== 'function') {
            return;
        }

        const summarySection = this.template.querySelector('[data-id="summary-section"]');
        const bodyShell = this.template.querySelector('[data-id="body-shell"]');
        const progressSection = this.template.querySelector('[data-id="progress-section"]');

        if (!this.summarySectionResizeObserver && summarySection) {
            this.summarySectionResizeObserver = new ResizeObserver(() => {
                this._scheduleContentSectionMeasurement();
            });
            this.summarySectionResizeObserver.observe(summarySection);
        }

        if (!this.layoutSectionResizeObserver && (bodyShell || progressSection)) {
            this.layoutSectionResizeObserver = new ResizeObserver(() => {
                this._scheduleContentSectionMeasurement();
            });

            if (bodyShell) {
                this.layoutSectionResizeObserver.observe(bodyShell);
            }

            if (progressSection) {
                this.layoutSectionResizeObserver.observe(progressSection);
            }
        }

        const contentStaticSection = this.template.querySelector('[data-id="content-static-section"]');
        const contentBottomStaticSection = this.template.querySelector('[data-id="content-bottom-static-section"]');

        if (!this.staticSectionResizeObserver && contentStaticSection) {
            this.staticSectionResizeObserver = new ResizeObserver(() => {
                this._scheduleContentSectionMeasurement();
            });
            this.staticSectionResizeObserver.observe(contentStaticSection);
        }

        if (!this.bottomStaticSectionResizeObserver && contentBottomStaticSection) {
            this.bottomStaticSectionResizeObserver = new ResizeObserver(() => {
                this._scheduleContentSectionMeasurement();
            });
            this.bottomStaticSectionResizeObserver.observe(contentBottomStaticSection);
        }
    }

    /** Handles browser resize events that can change the modal-body geometry. */
    _handleWindowResize() {
        this._scheduleContentSectionMeasurement();
    }

    /** Schedules one deferred recalculation of the dynamic content-section height. */
    _scheduleContentSectionMeasurement() {
        this._clearContentSectionMeasurementTimeout();

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.contentSectionMeasurementTimeoutId = setTimeout(() => {
            this.contentSectionMeasurementTimeoutId = null;
            this._measureContentSectionHeight();
        }, CONSTANTS.LAYOUT.CONTENT_SECTION_MEASUREMENT_DEFER_MS);
    }

    /** Clears the deferred dynamic-height recalculation timeout when it exists. */
    _clearContentSectionMeasurementTimeout() {
        if (!this.contentSectionMeasurementTimeoutId) {
            return;
        }

        clearTimeout(this.contentSectionMeasurementTimeoutId);
        this.contentSectionMeasurementTimeoutId = null;
    }

    /** Measures the available content-section height as shell height minus summary and reserved progress heights. */
    _measureContentSectionHeight() {
        const bodyShell = this.template.querySelector('[data-id="body-shell"]');
        const summarySection = this.template.querySelector('[data-id="summary-section"]');
        const contentStaticSection = this.template.querySelector('[data-id="content-static-section"]');
        const contentBottomStaticSection = this.template.querySelector('[data-id="content-bottom-static-section"]');

        if (!bodyShell || !summarySection) {
            return;
        }

        const shellHeight = bodyShell.getBoundingClientRect().height;
        const summaryHeight = summarySection.getBoundingClientRect().height;
        const contentSectionHeight = Math.max(
            0,
            Math.floor(shellHeight - summaryHeight - CONSTANTS.LAYOUT.PROGRESS_SECTION_HEIGHT_PX)
        );

        if (contentSectionHeight !== this.contentSectionHeightPx) {
            this.contentSectionHeightPx = contentSectionHeight;
        }

        const staticSectionHeight = contentStaticSection
            ? Math.ceil(contentStaticSection.getBoundingClientRect().height)
            : 0;
        const bottomStaticSectionHeight = contentBottomStaticSection
            ? Math.ceil(contentBottomStaticSection.getBoundingClientRect().height)
            : 0;
        const scrollableSectionHeight = Math.max(0, contentSectionHeight - staticSectionHeight - bottomStaticSectionHeight);

        if (scrollableSectionHeight !== this.scrollableSectionHeightPx) {
            this.scrollableSectionHeightPx = scrollableSectionHeight;
        }
    }

    /** Yields one short async paint window so the active transition spinner becomes visible before heavier work runs. */
    async _yieldForTransitionSpinnerPaint() {
        await new Promise((resolve) => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(resolve, CONSTANTS.TIMERS.TRANSITION_SPINNER_PAINT_MS);
        });
    }

    /** Synchronizes the universal progress bar with the active report-retrieval batch. */
    _syncRetrievalProgressBar() {
        if (!this.isRetrievingAccounts || this.retrievalBatchTotalCount <= 0) {
            this._hideUniversalProgressBar();
            return;
        }

        const completedPercent = Math.round((this.retrievalBatchCompletedCount / this.retrievalBatchTotalCount) * 100);
        this._showUniversalProgressBar(
            completedPercent,
            this.retrievalBatchCompletedCount,
            this.retrievalBatchTotalCount
        );
    }

    /** Shows the universal progress mechanism with the supplied percentage and completed/total counters. */
    _showUniversalProgressBar(progressPercent, completedCount, totalCount) {
        this.isUniversalProgressBarVisible = true;
        this.universalProgressBarValue = Math.max(
            CONSTANTS.PROGRESS.MIN_PERCENT,
            Math.min(CONSTANTS.PROGRESS.MAX_PERCENT, Number(progressPercent) || 0)
        );
        this.universalProgressCompletedCount = Number(completedCount) || 0;
        this.universalProgressTotalCount = Number(totalCount) || 0;
    }

    /** Hides and resets the universal progress bar state. */
    _hideUniversalProgressBar() {
        this.isUniversalProgressBarVisible = false;
        this.universalProgressBarValue = CONSTANTS.PROGRESS.MIN_PERCENT;
        this.universalProgressCompletedCount = 0;
        this.universalProgressTotalCount = 0;
    }

}
