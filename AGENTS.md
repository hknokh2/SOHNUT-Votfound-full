0. For this repository `https://github.com/hknokh2/SOHNUT-Votfound-full`, always work only with the connected Salesforce org alias `SOHNUT-Votfound-full`.
Never access, authenticate to, deploy to, retrieve from, or otherwise interact with any other Salesforce org under any circumstances.
For access to this repository, always use the access token already stored in `.git` and do not use any other credentials, tokens, or accounts.


1. Scope: all rules in this file apply only to files/components/classes where header contains `@author: Haim Knokh`.
2. In this repository context, phrases "my files", "my components", "my classes" mean files/components/classes with `@author: Haim Knokh`.
2.1. It is strictly forbidden to modify, compile, or deploy any Apex class/trigger/LWC/Aura component where header `@author` is NOT `Haim Knokh` or there is no @aurhor header at all.
2.2. Strict rule: it is allowed to modify, compile, and deploy only Apex classes/triggers/LWC/Aura components where header `@author` is `Haim Knokh`.

3. For every new Apex class/trigger/LWC/Aura component, add header:
   /**
   @author: Haim Knokh
   @date: <creation date>
   @modified: <modification date>
   @description: <short description>
   **/

4. For every modified Apex class/trigger/LWC/Aura component with `@author: Haim Knokh`, always update `@modified` to current date.

5. Use meaningful names for classes, methods, variables and properties.
6. Keep code concise and readable; avoid unnecessary lines and intermediate variables.
7. Do not create proxy alias variables for existing objects/properties unless real transformation is needed.
8. Remove dead code: unused imports, variables, methods, constants.
9. Add comments only where logic is non-trivial or important for maintainability.
10. Follow Salesforce best practices for readability, limits and performance.
11. Keep consistent indentation and spacing.
12. Apply VS Code default document formatting before save.

13. Apex class/trigger section separators must be:
    // -------------------------------
    // Section Name
    // -------------------------------

14. Apex section order must be:

- Constants
- Instance Variables
- Constructors
- Public Methods
- Private Methods
- Public helper classes
- Private helper classes

15. Do not keep empty sections in Apex/LWC JS.
16. Apex constants must be `static final` with UPPER_CASE_WITH_UNDERSCORES names.
16.1. Strict rule: all globally reusable Apex constants must be declared only in `GlobalConstantsAndEnums`. If a constant is reusable across more than one Apex class/component context, do not duplicate it locally; move it to `GlobalConstantsAndEnums` and reference it from there.
17. Every Apex field/property must have explicit access modifier and camelCase naming.
18. Every Apex public method name must start with a verb and use camelCase.
19. Every Apex private method name must start with `m_` and use camelCase.

20. Add JDoc/JsDoc annotations for all classes, methods and properties (public and private).
21. Method annotations must describe behavior, inputs, outputs and key logic.
22. If method receives JSON string, annotation must include valid JSON example and explain each JSON field.
22.1. In JDoc/JsDoc of every method, explicitly list what the method returns in practice, and document only fields/properties that this exact method actually populates.
22.2. In JDoc/JsDoc of every method, always place `@example` before `@return`.

23. After changes in Apex/triggers/LWC/Aura, run deploy and fix any compilation/deploy errors.
23.1. If the changed/deployed metadata belongs to a file/component/class with `@author: Haim Knokh`, you may deploy it without additional user confirmation.
23.2. If the metadata to deploy does not belong to `@author: Haim Knokh` scope, you must ask the user for explicit confirmation before any deploy action that touches it. Retrieve and compile actions are allowed without additional confirmation.
24. Put `System.debug` in critical points for flow and key values troubleshooting.

25. `@AuraEnabled` methods with input must use Request/Response pattern with signature parameter `String request`.
26. In such methods, deserialize `request` into Apex wrapper class named `Request`.
27. In such methods, add debug at method start exactly in this pattern:
    `<currentAuraMethodName> started - request=` + JSON.serializePretty(JSON.deserializeUntyped(request))
28. `@AuraEnabled` response wrapper class must be named `Response`.
29. `Response` must always contain `Boolean isSuccess` and `String errorMessage`.
30. Never throw exceptions from `@AuraEnabled`; catch and return `Response` with `isSuccess = false` and `errorMessage`.
31. In LWC after Apex call, always check `isSuccess`; if false, throw `new Error(response.errorMessage)`.
32. For `@AuraEnabled` methods that do not require parameters, do not force Request creation/sending from LWC.
33. For such no-request methods, still add debug at method start in this pattern:
    `<currentAuraMethodName> started`

34. Invocable design rules:

- Input class name must be `Request`.
- Output class name must be `Result` (or `Response` if existing contract requires).
- Add `label` and `description` for `@InvocableMethod`.
- Add `label` and `description` for every `@InvocableVariable`.

35. Test class naming: `<ClassName>Test`.
36. Always use `@TestSetup` even if there is only one test method.
37. `@TestSetup` method name must always be `createTestData`.
38. Do not use `SeeAllData=true`.
39. For org runtime dependencies in tests, allowed helpers are `Test.isRunningTest()` and `@TestVisible`.
40. Keep test coverage above required threshold for requested scope.

41. LWC JS section separators must be:
    // -------------------------------
    // Section Name
    // -------------------------------

42. LWC JS sections and order must be exactly:

- Imports
- Constants
- Public Interfaces
- Tracked Properties
- Private Fields
- Wired Members
- Component Lifecycle Events
- Public Getters/Setters
- Event Handlers
- Public Methods
- Private Getters/Setters
- Private Methods

43. `Public Interfaces` section contains all `@api` members, including `@api` properties, methods, getters and setters.
44. Keep all constants under one `CONSTANTS` object.
45. Group LWC constants into nested objects by context/meaning (for example `UI`, `TYPES`, `FILES`, `FILTERS`, `STATUS`, `CSS`, `EVENTS`, `ERRORS`, `TIMERS`).
46. Every constant must have one-line JsDoc directly above it.
46.1. LWC localization defaults must be stored only in `CONSTANTS`, not inline in methods/getters/templates.
46.2. Language for LWC localization must be determined via `import USER_LANGUAGE from "@salesforce/i18n/lang";`.
46.3. Default localized UI labels must be grouped under `CONSTANTS.UI.DEFAULT_LABELS` and split by direction keys `rtl` and `ltr`.
46.4. Supported direction literals must be declared in `CONSTANTS.UI.DIRECTIONS`.
46.5. When translation is missing, component must resolve the label from `CONSTANTS.UI.DEFAULT_LABELS` for the current direction; do not hardcode fallback strings outside `CONSTANTS`.
46.5.1. Strict rule: whenever any English localized resource is added, changed, renamed, or removed in `CONSTANTS.UI.DEFAULT_LABELS.ltr`, the matching Hebrew resource in `CONSTANTS.UI.DEFAULT_LABELS.rtl` must be added, changed, renamed, or removed in the same edit. Leaving English-only changes in localization constants is forbidden.
46.5.2. Strict rule: for LWC modal/screen components that depend on server-driven runtime configuration (for example record type ids, developer names, feature flags, server constants, layout-driving values), use a dedicated Apex `getConfig()` method and load that configuration from the server during component initialization. Do not hardcode such runtime configuration in LWC `CONSTANTS` when it can be sourced from Apex.
46.6. Minimal localization structure example:
```js
import USER_LANGUAGE from "@salesforce/i18n/lang";

const CONSTANTS = {
  /** UI constants. */
  UI: {
    /** Default labels used when translations are missing, grouped by UI direction. */
    DEFAULT_LABELS: {
      /** Hebrew defaults for RTL mode. */
      rtl: {
        modalTitle: "העלה או בחר {type}",
        cancel: "ביטול",
        select: "הוסף נבחרים ({number})"
      },
      /** English defaults for LTR mode. */
      ltr: {
        modalTitle: "Upload or Select {type}",
        cancel: "Cancel",
        select: "Add Selected ({number})"
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
```

47. In LWC, use getters only for computed values.
48. Getters for template/public use must have no underscore prefix.
49. Private getters/setters must start with `_` and be placed in `Private Getters/Setters` section.
50. Setters are allowed when computation/normalization/update is needed before storing value.
51. Any property referenced from LWC template must not start with underscore.

52. In LWC JS async flows, use `async/await`; do not use `.then()` and `.catch()`.
52.1. Every `setTimeout(...)` usage in LWC must have immediate previous line:
      `// eslint-disable-next-line @lwc/lwc/no-async-operation`
52.2. Strict rule: in LWC JS, never declare unused method/callback parameters. If a parameter is not used in method body, it must be removed.
52.3. For `try/catch`: if error object is not used, use `catch { ... }` (no binding). Only if target runtime/parser explicitly requires a binding, use `catch (_error) { ... }` as compatibility fallback.
53. Event handlers must be named in `handle<Event>` format, for example `handleSave`.
54. Do not create many tiny related getters where a structured computed object is clearer.
55. Do not create standalone method for logic used only once if inline expression is clearer.
56. Keep line breaks readable: avoid deep multi-step "staircase" formatting that harms readability.

57. LWC HTML must be structured with section comments:
    <!-- ------------------------------- -->
    <!-- Section Name -->
    <!-- ------------------------------- -->
58. LWC layout structure must be built with Lightning Component Library layout components (`lightning-layout`, `lightning-layout-item`, `lightning-accordion`, etc.) by default.
59. Using SLDS grid layout utilities (`slds-grid`, `slds-col`, `slds-size_*`, and similar) for component layout is forbidden.
60. `slds-grid`/SLDS grid utilities are allowed only as an exceptional fallback when required behavior is technically impossible via Lightning layout components; keep fallback scope minimal and replace it with Lightning layout at the first feasible opportunity.
61. If more complex layout is required, use Lightning Design System v2 patterns/components.
62. Add component CSS only when necessary; do not keep CSS file if not needed.

63. LWC CSS naming must be kebab-case.
64. Group and sort CSS rules by function/semantic area when it does not break behavior.
65. CSS section headers must be:
    /******\*\*\*\*******\*\*\*******\*\*\*\*******/
    /**\*\*\*** Section Name **\*\*\***/
    /******\*\*\*\*******\*\*\*******\*\*\*\*******/

66. If behavior/style of a standard Lightning base component (Shadow DOM internals) must be overridden, use only this runtime injection pattern:

- query the base component host from template,
- check style marker existence (`style[data-id="..."]`),
- inject one `<style>` block via `insertAdjacentHTML("beforeend", ...)`,
- keep CSS patch text in `CONSTANTS.CSS`,
- inject once per component instance.

66.1. Any Shadow DOM CSS override approach other than this pattern is forbidden.
66.2. Do not use alternative override techniques (direct shadow traversal patch variants, ad-hoc style mutations, non-pattern injection strategies) even as fallback.
66.3. If override is required and this pattern is not applied exactly, the change is considered non-compliant and must be reworked before completion.
66.4. Required implementation example:
```js
const styleId = CONSTANTS.CSS.PATCH_STYLE_ID;
const baseComponentHost = this.template.querySelector('[data-id="targetHost"]');
if (!baseComponentHost || baseComponentHost.querySelector(`style[data-id="${styleId}"]`)) {
  return;
}
baseComponentHost.insertAdjacentHTML(
  "beforeend",
  `<style data-id="${styleId}">${CONSTANTS.CSS.PATCH_CSS_TEXT}</style>`
);
```
66.5. Every `insertAdjacentHTML(...)` usage in LWC must have immediate previous line:
      `// eslint-disable-next-line @lwc/lwc/no-inner-html`

67. JDoc/JsDoc class-level technical documentation format is mandatory for all Apex/LWC classes/components in scope.
68. Split class-level documentation into sections with this exact section-header format:

- one empty line before each section
- section title line
- separator line `=========================`

68.1. JDoc/JsDoc list formatting rule (same for Apex and LWC):

- subsection heading lines (for example `Modal title key:`) must have no extra indentation after `*`
- all list items that belong to that heading must be indented (for example `*   item...`)
- nested list items must use additional indentation levels for clear visual hierarchy

68.2. The same indentation/structure formatting rule is mandatory for all documentation levels:

- class-level JDoc/JsDoc blocks,
- and every member-level block (methods, properties, fields, constructors, helper classes).

68.3. In JDoc/JsDoc (both class-level and member-level), always add one empty `*` line before every subsection heading line that ends with `:`.

68.3.1. In contract sections (`Parent Integration Contract`, `Flow Integration Contract`, `FlexiPage Integration Contract`), each property declaration must keep type and explanation on the same line; do not move property explanation to the next bullet line.

68.3.2. In contract sections, property documentation style is strictly unified:

- use one-line entries in format `` `propertyName: type` - description ``;
- if a nested shape is needed, use dotted form (for example `` `event.detail.file.id: string` - ... ``);
- do not use inline `//` comments inside object-shape snippets to describe properties.

68.3.3. For object-property enumerations in JDoc/JsDoc:

- do not wrap property lists with leading/trailing `` `{` `` and `` `}` `` lines;
- keep the parent object line at base list indentation (for example `*   - ` + `` `context: object` - ... ``);
- nested properties of that object must use one additional indentation level (for example `*     - ...` under `*   - context...`), never the same level as the parent object line.

68.3.4. In any property enumeration (top-level or nested), every property line must start with `-` at its own indentation level.
    Required visual pattern example:
    `*   - \`context: object\` - ...`
    `*     - \`context.type: string|string[]\` - ...`

68.4. For every LWC class-level JsDoc, `Parent Integration Contract` section is mandatory with this exact section header:

- `Parent Integration Contract`
- `=========================`

68.5. `Parent Integration Contract` section must always include only real `@api` surface of the component:

- `@api` properties;
- `@api` methods;
- `@api` getters/setters;
- only those outputs that are exposed through real `@api` members.

68.5.1. Strict rule: `Parent Integration Contract` must contain descriptions only for members that are explicitly declared with `@api`. If a property/method/accessor does not have `@api`, it is forbidden to document it in `Parent Integration Contract`.

68.5.2. `Parent Integration Contract` must not document internal component state, private fields, tracked fields, internal events, internal computed objects, Apex payload internals, template-only values, or any other implementation detail that is not a real `@api` contract.

68.5.3. For every LWC class-level JsDoc, `Internal Component Contract` section is mandatory with this exact section header:

- `Internal Component Contract`
- `=========================`

68.5.4. `Internal Component Contract` section must document only internal component implementation state that is relevant for future maintenance, for example:

- tracked fields;
- private fields;
- internal derived state objects;
- internal event/data flow between template, handlers, and Apex calls;
- important internal runtime invariants.

68.5.5. Every internal LWC property/field/variable that exists as a class member must have its own member-level JsDoc that clearly explains its exact role in the component.

68.6. If an LWC has integration contract with Flow, class-level JsDoc must include mandatory section:

- `Flow Integration Contract`
- `=========================`

and it must follow the same detail level/format requirements as `Parent Integration Contract`
(full inputs, full outputs, nested object properties, input example, output example).

68.7. If an LWC has integration contract with Lightning Page (FlexiPage), class-level JsDoc must include mandatory section:

- `FlexiPage Integration Contract`
- `=========================`

and it must follow the same detail level/format requirements as `Parent Integration Contract`
(full inputs, full outputs, nested object properties, input example, output example).

69. For LWC component class-level documentation, include:

- UI responsibilities and behavior
- parent contract (only real container-facing `@api` contract)
- internal component contract
- Apex contract (called methods and expected payload shapes)
- localization contract (supported translation keys and where they are used)

70. For Apex controller class-level documentation, include:

- architecture role
- main object links and data flow
- runtime constraints and why chosen implementation exists
- any important storage/contract caveats needed by future developers.

71. If component code is changed (Apex/LWC/Aura), compile it immediately (deploy/compile check right after the change).

72. If a test class is changed, immediately:

- compile/deploy the changed test class,
- run tests,
- verify code coverage is `>= 90%` for the required scope.
  If tests fail or coverage is below `90%`, keep fixing and re-running until tests pass and coverage is `>= 90%`.

73. Any code change in a component/class must fully comply with all rules in this `AGENTS.md` (no partial compliance).

74. After each component/class change, run an immediate audit of that changed file against these rules.
    If the change requires documentation alignment, also update JDoc/JsDoc/template section annotations in:

- the changed component/class itself,
- and all directly related components/classes that are affected by the same behavior/contract change,
  to keep annotations and implementation fully synchronized.

75. For any REST call flow initiated from LWC/Apex (including Apex callouts triggered by LWC), access token must be read only from Platform Cache (cached token value); do not use direct session-id fallbacks in runtime REST execution path.

76. LWC components that rely on REST callouts must cache current user session token into Platform Cache during `connectedCallback` (via dedicated Apex method), before REST-dependent logic is executed.
