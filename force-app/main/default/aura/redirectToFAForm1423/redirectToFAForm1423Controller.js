({    navigate  : function(component, event, helper) {
    
    var redirectURL = component.get("v.redirectURL");
    var redirect = $A.get("e.force:navigateToURL");
    var recID =  component.get("v.recordId"); 
    redirect.setParams({
        "url": "https://lln.tfaforms.net/1425?tfa_12=" + recID
    });
    
    redirect.fire();
    var dismissActionPanel = $A.get("e.force:closeQuickAction");
    dismissActionPanel.fire();
}})