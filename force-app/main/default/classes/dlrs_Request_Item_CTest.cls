/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
@IsTest
private class dlrs_Request_Item_CTest
{
    @IsTest
    private static void testTrigger()
    {
        // Force the dlrs_Request_Item_CTrigger to be invoked, fails the test if org config or other Apex code prevents this.
        dlrs.RollupService.testHandler(new Request_Item__C());
    }
}