({
	doInit : function(component, event, helper) {
        helper.getFollowUpDetails(component, event);
        helper.getSiteVisitDetails(component, event);
        helper.getPendingFollowUpDetails(component, event);
        helper.getPendingSiteVisitDetails(component, event);
        helper.renderEveryMin(component, event, helper);
        helper.loadRecords(component);
        
	},
    onCallHandler:function(component, event, helper) {
        var leadRecordID=event.getSource().get("v.name");
         component.set("v.leadRecID",leadRecordID);
         component.set("v.isCall",true);
        
	},
    onsvHandler:function(component, event, helper) {
         var svleadRecordID=event.getSource().get("v.name");
         component.set("v.SvleadRecID",svleadRecordID);
         component.set("v.isSv",true);   
	},
    onfollowupHandler:function(component, event, helper) {
        var flsleadRecordID=event.getSource().get("v.name");
        component.set("v.FlsleadRecId",flsleadRecordID);
        component.set("v.isfls",true);   
    },
    
     onChange:function(component,event,helper){
         component.set("v.isCancelled",false);
         component.set("v.isConducted",false);
         component.set("v.isReschedule",false);
          component.set("v.updateValue","");
         
        var StatusValue=component.find('StatusID').get('v.value');
        if(StatusValue=='Cancelled')
            	component.set("v.isCancelled",true);
        else if(StatusValue=='Completed')
            component.set("v.isConducted",true);
        else if(StatusValue=='Rescheduled')
             component.set("v.isReschedule",true);
    },
      onChange1:function(component,event,helper){
          component.set("v.isScheduled1",false);
          component.set("v.isMissed1",false);
          component.set("v.isCompleted1",false);
         
        var StatusValue1=component.find('StatusID1').get('v.value');
        if(StatusValue1=='Scheduled')
            	component.set("v.isScheduled1",true);
        // 'Missed' follow-up status removed
        // else if(StatusValue1=='Missed')
        //     component.set("v.isMissed1",true);
        else if(StatusValue1=='Completed')
             component.set("v.isCompleted1",true);
        
        // Default Completed Date to now when Completed is chosen; clear it otherwise
        if(StatusValue1=='Completed')
            component.set("v.completedDate", new Date().toISOString());
        else
            component.set("v.completedDate", "");
    },
    UpdateSvStatus:function(component,event,helper){
        
        var StatusValue=component.find('StatusID').get('v.value');
        var UpdatedValue=component.get("v.updateValue");
        if(StatusValue=='Rescheduled' && UpdatedValue !='')
            UpdatedValue= new Date(UpdatedValue).toLocaleString('en-GB');
        if(StatusValue!='' && UpdatedValue !='')
        {
         helper.updateSvDetails(component, event,StatusValue,UpdatedValue,helper);
         var closeMethod = component.get('c.closeModel');
          
        	$A.enqueueAction(closeMethod);
        }
    },
    UpdateflsStatus:function(component,event,helper){
        var StatusValue1 = component.find('StatusID1').get('v.value');
        if(!StatusValue1)
        {
            helper.displayMessage(component, "Please select a status", "error");
            return;
        }
        var completedDate = null;
        if(StatusValue1 == 'Completed')
        {
            completedDate = component.get("v.completedDate");
            if(!completedDate)
            {
                helper.displayMessage(component, "Please enter the Completed Date", "error");
                return;
            }
            if(new Date(completedDate) > new Date())
            {
                helper.displayMessage(component, "Completed Date cannot be in the future", "error");
                return;
            }
        }
        helper.UpdateflsDetails(component, event, StatusValue1, completedDate, helper);
        var closeMethod = component.get('c.closeModel');
        $A.enqueueAction(closeMethod);
    },
    closeModel: function(component, event, helper) {
        component.set("v.isCall",false);
        component.set("v.isSv",false);
        component.set("v.isfls",false);
        component.set("v.isCancelled",false);
        component.set("v.isConducted",false);
        component.set("v.isReschedule",false);
        component.set("v.updateValue","");
        
        component.set("v.isScheduled1",false);
        component.set("v.isMissed1",false);
        component.set("v.isCompleted1",false);
        component.set("v.completedDate","");
        
        component.set("v.SvleadRecID","");
        component.set("v.FlsleadRecId","");
        component.set("v.leadRecID","");
	},

     previousPage: function (component, event, helper) {
        // Decrement current page and load previous records
        var currentPage = component.get("v.currentPage");
        component.set("v.currentPage", currentPage - 1);
        helper.loadRecords(component);
    },
    nextPage: function (component, event, helper) {
        // Increment current page and load next records
        var currentPage = component.get("v.currentPage");
        component.set("v.currentPage", currentPage + 1);
        helper.loadRecords(component);
    },
    navigateToLeadRecord: function(component, event, helper) {
        var recordId = event.currentTarget.getAttribute("value");
        var navigateEvent = $A.get("e.force:navigateToSObject");
        navigateEvent.setParams({
            "recordId": recordId,
            "slideDevName": "detail"
        });
        navigateEvent.fire();
    },
    // Lead's For The Day filters
    onPeriodChange: function (component, event, helper) {
        component.set("v.currentPage", 1);
        if (component.get("v.period") === "custom") {
            // wait for Apply; show a hint until both dates are chosen
            component.set("v.rangeText", "Pick a start and end date, then Apply.");
            if (component.get("v.startDate") && component.get("v.endDate")) {
                helper.loadRecords(component);
            }
            return;
        }
        helper.loadRecords(component);
    },
    applyCustomRange: function (component, event, helper) {
        if (!component.get("v.startDate") || !component.get("v.endDate")) {
            helper.displayMessage(component, "Please enter both Start Date and End Date.", "error");
            return;
        }
        component.set("v.currentPage", 1);
        helper.loadRecords(component);
    },
    refreshLeads: function (component, event, helper) {
        helper.loadRecords(component);
    },
    onStatusFilter: function (component, event, helper) {
        var value = event.currentTarget.getAttribute("value");
        component.set("v.statusFilter", value);
        component.set("v.currentPage", 1);
        helper.loadRecords(component);
    },
     addCustomerEvent: function(component, event, helper) {
        component.set('v.isModalOpen',true);
    },
 
})