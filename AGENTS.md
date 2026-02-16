1. When creating apex classes/triggers/lwc/aura components, put in the header:
/**
@author: Haim Knokh
@date: <creation date>
@modified: <modification date>
@description: <short description>
**/

2. When modifying existing apex classes/triggers/lwc/aura components, having Haim Knokh as the @author, change the @modified date to the current date.

3. The structure of the apex class/trigger should follow the order splitted by named sections in following format:

// -------------------------------
// Section Name
// -------------------------------

The order of the sections should be as follows:
- Constants (as static final variables, names should be in uppercase with underscores)
- Instance Variables (private variables)
- Constructors
- Public Methods
- Private Methods
- Public helper classes (if any)
- Private helper classes (if any)

4. Every private method's name should start with perfix "m_" followed by camel case naming convention.
   Example: private void m_calculateTotalAmount() { ... }
6. Every public method name should start with a verb and follow camel case naming convention.
   Example: public void calculateTotalAmount() { ... }   
7. Every class field or property should have an access modifier (private, public, protected, global) nad should start with lowercase letter and follow camel case naming convention.
   Example: private Integer totalAmount;
8. Use meaningful names for variables, methods, and classes that clearly indicate their purpose.
9. Add comments to explain complex logic or important sections of the code for better readability and maintainability.
10. Follow Salesforce best practices for coding standards and performance optimization.
11. Add JDoc annotations for all members (classes, methods, properties), private and public, to provide clear documentation.
Annotations should contain descriptions of parameters, return values, and any exceptions thrown and example of usage where applicable.
If method get as parameter json string, specify in the annotation that the string should be in valid json format and give na example of valid json string.
And you should explain each property of the json string in the example.
Example:
/**
 * This method processes the input JSON string to extract user information.
 * @param jsonString: A valid JSON string in the following format:
 * {
 *   "name": "John Doe", // String: The full name of the user
 *   "age": 30,          // Integer: The age of the user
 *   "email": "john.doe@example.com" // String: The email address of the user
 * } 
 * @return: A User object containing the extracted information.
 * @throws: JSONException if the input string is not a valid JSON format.
*/
12. Ensure proper indentation and spacing for better readability.
13. The structure of LWC js file should be in the following order:
- Imports
- Constants, as uppercase with underscores, all constatns should be under one CONSTANTS:
const CONSTANTS = { 
    /** The time delay in milliseconds before retrying the operation. */
    DELAY_TIME: 3000,
    /** The maximum number of retries allowed for the operation. */
    MAX_RETRIES: 5
    ....
 };
 and every constant should be documented with JsDoc annotation in one line before the constant.
- @api properties (camel case naming convention) + @api getter and setter methods
- @track properties (camel case naming convention)
- regular properties (should start from "_" followed by camel case naming convention)
- @wire properties and methods
- lifecycle hooks (connectedCallback, renderedCallback, etc.)
- getter and setter methods
- public methods
- private methods (should start with "_" followed by camel case naming convention)

The sections should be splitted and named in following format:
// -------------------------------
// Section Name
// -------------------------------

14. LWC html file should be structured with proper indentation and comments for different sections of the template for better readability.
For example:
<!-- ------------------------------- -->
<!-- Header Section -->
<!-- ------------------------------- -->
<div class="header">
    ...
</div>
<!-- ------------------------------- -->
<!-- Main Content Section -->
<!-- ------------------------------- -->
...
etc.

15. LWC css file should follow proper naming conventions for classes and IDs, using kebab-case (lowercase letters with hyphens) for better readability.
16. Apply vscode default document formatting on all files before saving.
17. for asynchronous operations in LWC js use await and async keywords, dont use then() and catch() methods.
18. When designing @AuraEnable apex methods use Request / Response pattern (send json string from the LWC then deserialize the json string into Request object, always return single object as response), the name of the request class to deserialize should always be Request and the response class to return to LWC should be Response.
Response class should contain isSuccess boolean property and errorMessage string property to indicate the status of the operation.
Never throw exceptions from @AuraEnabled methods, always return Response object with isSuccess = false and errorMessage set to the exception message. 
After calling apex, you should check for isSuccess property in your js code  and display error message to the user if isSuccess = false.
The pattern of exception in js - throw new Error('Error message here coming from the response object'); you should wrap your apex call in try catch block to catch such exceptions. Use finally block if you need to do some cleanup operations or hide spinner etc.
If request isn't used in the method you should still create and send empty Request object from the LWC to the apex method, but don't need to deserialize it to request class in the apex method.
19. When designing Invocable apex methods always name the input class "Request" and the output class "Result". 
Add desctription to the InvocableMethod and InvocableVariable decorators to explain their purpose.
20. When creating test classes, ensure to cover > 90% of the code, and follow the same coding standards as mentioned above.
Always use @TestSetup method to create test data that can be used across multiple test methods even you have one test method.
21. The name of test class should be the name of the class being tested followed by "Test".
22. Always update respective test class when modifying existing class to ensure code coverage and test the new/modified functionality.
But don't necessary to create a test class unless requested. But if the test class is already created you need to maintain it as per the above standards.
23. Always run deploy for apex classes/triggers/lwc/aura components after modification to ensure there are no compilation errors and fix them if any.
24. In apex / js don't create method for the functionality that is used only once, instead put the code directly in place where it is used.
25. Don't put unnecessary validation in methods, for example to check whether this sobject exists in the global describe, just use the object directly and let the exception be thrown if it doesn't exist, unless such validation is specifically required for the business logic.
Don't put validation to check input parameters unless it is required for the business logic.
26. Keep code as short as possible, avoid unnecessary variables and code lines. Dont' create variables just to hold intermediate values that are used only once, instead put the expression directly where it is used.
27. All classes/lwc/aura components should be clean from dead code, always remove any unused variables/methods/imports.
28. Put System.debug statements to log important variable values and execution flow at critical points in the code for easier debugging and troubleshooting.
29. In LWC avoid using getter to just return private property like this:
   get uploadRecordId() {
        return this._uploadRecordId;
    }
Use getter only when you need to perform some computation or transformation on the private property before returning it.
When  any js property is referenced in component template it should NOT start with underscore, only properties (treated as "private") exclusively used in the class should start with underscore.
28. Don't add section header (separator) in class/lwc js  if the section is empty, 
for example all like below are forbidden:
    // -------------------------------
    // Private Helper Classes
    // -------------------------------
    // (none)
29. Use this structure for Invocable Action classes:
- Declare such class public with sharing
- Expose a single @InvocableMethod that accepts List<Request> and returns List<Response>.
- Read inputs only from requests[0] unless multi-row support is explicitly required.
- Put all inputs in an inner Request class with @InvocableVariable fields; mark required inputs with required=true and add labels.
- Avoid hardcoded strings in filters or logic; introduce reusable constants and enums in a shared GlobalConstantsAndEnums class (create it if missing), compile it, and add a test class for it.
- Create Response objects via constructors (do not build them piecemeal); use explicit success/error constructors.
- Always include in Response: Boolean isSuccess and String errorMessage, both exposed to Flow via @InvocableVariable, so the Flow can show status without failing.
- Wrap the invocable method body in try/catch; on exception, return a Response with isSuccess = false and errorMessage = exception message.
- On success, return a Response with isSuccess = true and errorMessage = null (or empty), plus all other output fields.
- Provide Response constructors for:
- - Error: accept Exception (or message) and set failure fields.
- - Success: accept all output values and set success fields.
- Return exactly one Response item: return new List<Response>{ response };
