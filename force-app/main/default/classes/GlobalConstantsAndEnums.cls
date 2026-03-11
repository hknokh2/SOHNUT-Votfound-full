/**
@author: Haim Knokh
@date: 2026-03-09
@modified: 2026-03-11
@description: Shared reusable global constants and future enum placeholders for Haim-authored Apex components.
*
* Architecture Role
* =========================
* This class centralizes reusable Apex constants that are shared across multiple business components.
*
* Main Object Links And Data Flow
* =========================
* This class does not query or mutate data.
* It only exposes reusable constants for other Apex classes.
*
* Runtime Constraints And Why This Implementation Exists
* =========================
* Reusable runtime values must not be duplicated across controllers or services because duplicated literals
* increase drift risk and make org-wide refactoring harder.
*
* Important Contract Caveats
* =========================
* Only reusable cross-component constants belong here.
* Component-private constants must remain inside the owning class.
**/
public class GlobalConstantsAndEnums {

    // -------------------------------
    // Constants
    // -------------------------------

    /** Opportunity Request record type developer name shared across request-creation flows. */
    public static final String REQUEST_RECORD_TYPE_DEVELOPER_NAME = 'Request';

    /** Report type returned by Analytics API for Contact and Account reports in this org. */
    public static final String REPORT_TYPE_ACCOUNT_CONTACT = 'account_contact__c';

    /** Opportunity stage that indicates the request is ready for ERP transfer. */
    public static final String STAGE_READY_FOR_TRANSFER_TO_ERP = 'Ready for transfer to ERP';

    /** Opportunity stage that indicates the request was already transferred to ERP. */
    public static final String STAGE_TRANSFERRED_TO_ERP = 'Transferred to ERP';

    /** Fund object field API name that stores the business fund type used by the Request-creation grant rule. */
    public static final String FUND_TYPE_FIELD_API_NAME = 'Fund_type__c';

    /** Fund type value that enables the existing-ERP-request duplicate block for the selected Account. */
    public static final String FUND_TYPE_SUPPLEMENTAL_REHABILITATION_GRANT = 'המענק השיקומי המשלים';
}
