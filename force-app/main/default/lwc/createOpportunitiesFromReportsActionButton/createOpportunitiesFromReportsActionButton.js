/**
@author: Haim Knokh
@date: 2026-03-08
@modified: 2026-03-10
@description: App page button that opens the Create Opportunities From Reports modal directly from the page.
*
* UI Responsibilities And Behavior
* =========================
* This component renders a single focused card with a primary button.
* Clicking the button opens the `createOpportunitiesFromReports` modal directly from the App Page.
*
* Parent Integration Contract
* =========================
* Inputs:
*   - None.
*
* Output:
*   - Opens the `createOpportunitiesFromReports` LightningModal.
*
* Input example:
*   - `{}`
*
* Output example:
*   - `{"action":"openModal","component":"c:createOpportunitiesFromReports"}`
*
* Apex Contract
* =========================
* This button does not call Apex directly.
* The opened modal internally calls:
*   - `CreateOpportunitiesFromReportsController.getSelectorData()`
*   - `CreateOpportunitiesFromReportsController.retrieveReportAccounts(request)`
*
* Localization Contract
* =========================
* All default UI text is stored in `CONSTANTS.UI.DEFAULT_LABELS`.
* Direction is resolved from `@salesforce/i18n/lang`.
* No Custom Labels are used by this button.
**/
import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import USER_LANGUAGE from "@salesforce/i18n/lang";
import CreateOpportunitiesFromReports from "c/createOpportunitiesFromReports";

// -------------------------------
// Constants
// -------------------------------

/** Shared button constants. */
const CONSTANTS = {
    /** Modal launch constants. */
    ACTIONS: {
        /** Default modal size used by the page button. */
        MODAL_SIZE: "medium",
        /** Default table height passed into the modal. */
        TABLE_HEIGHT: "400px"
    },
    /** Error constants. */
    ERRORS: {
        /** Separator used to join multiple platform error messages. */
        MESSAGES_SEPARATOR: "; "
    },
    /** UI constants. */
    UI: {
        /** Default labels used when translations are resolved locally. */
        DEFAULT_LABELS: {
            /** Hebrew defaults for RTL mode. */
            rtl: {
                cardTitle: "Create Opportunity From Reports",
                cardDescription: "לחץ על הכפתור כדי לפתוח את מסך יצירת ה-Opportunity מדוחות.",
                buttonLabel: "Open Action",
                launchErrorTitle: "Create Opportunity From Reports",
                launchErrorMessage: "Unable to open the Create Opportunities From Reports modal."
            },
            /** English defaults for LTR mode. */
            ltr: {
                cardTitle: "Create Opportunity From Reports",
                cardDescription: "Click the button to open the Opportunity creation modal from reports.",
                buttonLabel: "Open Action",
                launchErrorTitle: "Create Opportunity From Reports",
                launchErrorMessage: "Unable to open the Create Opportunities From Reports modal."
            }
        },
        /** Supported UI directions. */
        DIRECTIONS: {
            /** RTL direction literal. */
            RTL: "rtl",
            /** LTR direction literal. */
            LTR: "ltr"
        }
    }
};

export default class CreateOpportunitiesFromReportsActionButton extends LightningElement {
    // -------------------------------
    // Public Getters/Setters
    // -------------------------------

    /** Returns the localized card title. */
    get cardTitle() {
        return this._getLabel("cardTitle");
    }

    /** Returns the localized card description. */
    get cardDescription() {
        return this._getLabel("cardDescription");
    }

    /** Returns the localized button label. */
    get buttonLabel() {
        return this._getLabel("buttonLabel");
    }

    // -------------------------------
    // Event Handlers
    // -------------------------------

    /** Opens the Create Opportunities From Reports modal when the user clicks the page button. */
    async handleOpenAction() {
        try {
            await CreateOpportunitiesFromReports.open({
                size: CONSTANTS.ACTIONS.MODAL_SIZE,
                tableHeight: CONSTANTS.ACTIONS.TABLE_HEIGHT
            });
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: this._getLabel("launchErrorTitle"),
                    message: this._formatError(error) || this._getLabel("launchErrorMessage"),
                    variant: "error"
                })
            );
        }
    }

    // -------------------------------
    // Private Methods
    // -------------------------------

    /** Returns the current localization direction. */
    _getDirection() {
        return String(USER_LANGUAGE || "").toLowerCase().startsWith("he")
            ? CONSTANTS.UI.DIRECTIONS.RTL
            : CONSTANTS.UI.DIRECTIONS.LTR;
    }

    /** Returns the localized label for the supplied key. */
    _getLabel(key) {
        return CONSTANTS.UI.DEFAULT_LABELS[this._getDirection()][key] || key;
    }

    /** Formats a platform error into a single user-facing message. */
    _formatError(error) {
        const { body, message } = error ?? {};
        if (Array.isArray(body)) {
            return body.map(({ message: bodyMessage }) => bodyMessage).join(CONSTANTS.ERRORS.MESSAGES_SEPARATOR);
        }

        return body?.message || message || "";
    }
}
