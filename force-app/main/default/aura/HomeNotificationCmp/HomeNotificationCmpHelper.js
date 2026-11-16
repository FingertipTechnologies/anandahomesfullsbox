({
    
    getFollowUpDetails: function(component, event) {
        let action = component.get("c.getFollowUpInformation");
        action.setCallback(this, function(response) {
            
            let state = response.getState();
            
            if (state == "SUCCESS") {
                var result = response.getReturnValue();
                component.set("v.DuefollowUpDetails",JSON.parse(JSON.stringify(result)));
                console.log('FOL modfif=====>');
                console.log(component.get("v.DuefollowUpDetails"));
                result.forEach(ele => {
                    
                    var scheduledTime = new Date(
                    ele.Scheduled_Date__c
                    ).toLocaleTimeString("en-US");
                    ele.Scheduled_Date__c = scheduledTime;
                });
                component.set("v.followUpDetails", result);
                component.set("v.todaysFollowupCount", result.length); 
                var todaycount= component.get('v.todayssitevistCount') + component.get('v.todaysFollowupCount');;
                var tabLabel = component.find("Agenda").get("v.label");
                var miss = "Today's Agendas("+todaycount+")";
                tabLabel[0].set("v.value", miss);
                
            }
        });
        $A.enqueueAction(action);
    },
    getSiteVisitDetails: function(component, event) {
        let action = component.get("c.getSiteVistInformation");
        action.setCallback(this, function(response) {
            let state = response.getState();
            
            if (state == "SUCCESS") {
                let result = response.getReturnValue();
                component.set("v.DuesiteVisitDetails", JSON.parse(JSON.stringify(result)));
                result.forEach(ele => {
                    
                    console.log(ele);
                    var scheduledTime = new Date(ele.Date__c).toLocaleTimeString("en-US");
                    ele.Date__c = scheduledTime;
                });
                component.set("v.siteVisitDetails", result);
                component.set("v.todayssitevistCount", result.length); 
                var todaycount= component.get('v.todayssitevistCount') + component.get('v.todaysFollowupCount');;
                var tabLabel = component.find("Agenda").get("v.label");
                var miss = "Today's Agendas("+todaycount+")";
                tabLabel[0].set("v.value", miss);
                
            }
        });
        $A.enqueueAction(action);
    },
    getPendingFollowUpDetails: function(component, event) {
        let action = component.get("c.getPendingFollowUpInformation");
        action.setCallback(this, function(response) {
            let state = response.getState();
            if (state == "SUCCESS") {
                let result = response.getReturnValue();
                let check=[];
                result.forEach(ele => {
                    
                    var scheduledTime = new Date(
                    ele.Scheduled_Date__c
                    ).toLocaleTimeString("en-US");
                    ele.Scheduled_Date__c = scheduledTime;
                });
                component.set("v.pendingFollowUpDetails", result);
                component.set("v.pendingFollowupCount", result.length); 
                var pendingcount= component.get('v.pendingsitevistCount') + component.get('v.pendingFollowupCount');;
                var tabLabel = component.find("pending").get("v.label");
                var miss = "Pending items("+pendingcount+")";
                tabLabel[0].set("v.value", miss);
            }
        });
        $A.enqueueAction(action);
    },
    getPendingSiteVisitDetails: function(component, event) {
        let action = component.get("c.getPendingSiteVistInformation");
        action.setCallback(this, function(response) {
            let state = response.getState();
            
            if (state == "SUCCESS") {
                let result = response.getReturnValue();
                result.forEach(ele => {
                    console.log(ele);
                    var scheduledTime = new Date(ele.Date__c).toLocaleTimeString("en-US");
                    ele.Date__c = scheduledTime;
                });
                component.set("v.pendingSiteVisitDetails", result);
                component.set("v.pendingsitevistCount", result.length);
                var pendingcount= component.get('v.pendingsitevistCount') + component.get('v.pendingFollowupCount');;
                var tabLabel = component.find("pending").get("v.label");
                var miss = "Pending items("+pendingcount+")";
                tabLabel[0].set("v.value", miss);
            }
        });
        $A.enqueueAction(action);
    },
    updateSvDetails:function(component, event,status,updateValue,helper) {
        alert('helper');
        var conductedDate=component.get("v.conductedDate");
        alert(conductedDate);
        if(conductedDate!=null && conductedDate!='')
            conductedDate= new Date(conductedDate).toLocaleString('en-GB');
        var svrecID = component.get("v.SvleadRecID");
        let action = component.get("c.updateSvDetils");
        action.setParams({ 
            recID:svrecID,
            svStatus: status,
            updateValue: updateValue,
            conducatedDate: conductedDate
        });
        action.setCallback(this, function(response) {
            let state = response.getState();
            if (state == "SUCCESS") {
                let result = response.getReturnValue();
                if(result!=null)
                { 
                    helper.displayMessage(component,"Site Visit Updated successfully", "SUCCESS");
                    $A.get('e.force:refreshView').fire();
                }
                else
                {
                    helper.displayMessage(component,"Something went wrong. Message-", "error");
                }
            }
        });
        $A.enqueueAction(action);
        
    },
    // Sends recID, status and (for Completed) the Completed Date to Apex
    UpdateflsDetails:function(component, event, status, completedDate, helper) {
        var svrecID1 = component.get("v.FlsleadRecId");
        let action = component.get("c.updateFollowupDetails");
        action.setParams({ 
            recID: svrecID1,
            FLStatus: status,
            completedDate: completedDate
        });
        action.setCallback(this, function(response) {
            let state = response.getState();
            if (state == "SUCCESS") {
                let result = response.getReturnValue();
                if(result!=null)
                {
                    helper.displayMessage(component,"Follow-Up Updated successfully", "SUCCESS");
                    $A.get('e.force:refreshView').fire();
                }
                else
                {
                    helper.displayMessage(component,"Something went wrong. Message-", "error");
                }
            }
            else if (state == "ERROR") {
                let errors = response.getError();
                let msg = (errors && errors[0] && errors[0].message) ? errors[0].message : "Unknown error";
                helper.displayMessage(component, msg, "error");
            }
        });
        $A.enqueueAction(action);
        
    },
    // Lead's For The Day: leads assigned to me in the selected period, with counts
    loadRecords: function (component) {
        var pageNumber = component.get("v.currentPage");
        var pageSize = component.get("v.pageSize");
        var helper = this;

        var action = component.get("c.getLeadsForPeriod");
        action.setParams({
            period: component.get("v.period"),
            startDate: component.get("v.startDate"),
            endDate: component.get("v.endDate"),
            statusFilter: component.get("v.statusFilter"),
            pageSize: pageSize,
            pageNumber: pageNumber
        });
        action.setCallback(this, function (response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var result = response.getReturnValue();
                if (result.error) {
                    helper.displayMessage(component, result.error, "error");
                    return;
                }
                var newStatuses = { "new enquiry": true, "new sales enquiry": true };
                // Period bounds as local times, to tag leads re-engaged / re-opened inside the period
                var sp = (result.startDate || "").split("-"), ep = (result.endDate || "").split("-");
                var periodFrom = sp.length === 3 ? new Date(parseInt(sp[0], 10), parseInt(sp[1], 10) - 1, parseInt(sp[2], 10)).getTime() : null;
                var periodTo = ep.length === 3 ? new Date(parseInt(ep[0], 10), parseInt(ep[1], 10) - 1, parseInt(ep[2], 10) + 1).getTime() : null;
                var inPeriod = function (iso) {
                    if (!iso || periodFrom === null || periodTo === null) return false;
                    var t = new Date(iso).getTime();
                    return t >= periodFrom && t < periodTo;
                };
                var records = (result.records || []).map(function (ld) {
                    var status = (ld.Lead_Status__c || "").toLowerCase();
                    ld.isWorked = !newStatuses[status];
                    ld.assignedText = helper.formatDateTime(ld.CreatedDate);
                    ld.reEngagedText = inPeriod(ld.Last_Re_Engaged_Date__c) ? helper.formatDateTime(ld.Last_Re_Engaged_Date__c) : "";
                    ld.reOpenedText = inPeriod(ld.Last_Re_Opened_Date__c) ? helper.formatDateTime(ld.Last_Re_Opened_Date__c) : "";
                    ld.workedText = (ld.isWorked && ld.Status_Change_Date__c) ? helper.formatDateTime(ld.Status_Change_Date__c) : "";
                    return ld;
                });
                component.set("v.recordList", records);
                component.set("v.leadCounts", {
                    total: result.total, pending: result.pending, worked: result.worked,
                    newEnquiry: result.newEnquiry, newSalesEnquiry: result.newSalesEnquiry,
                    reEngaged: result.reEngaged, reOpened: result.reOpened
                });
                component.set("v.Todayscount", result.total);
                component.set("v.workedPct", result.total ? Math.round(result.worked * 100 / result.total) : 0);
                var from = helper.formatDate(result.startDate), to = helper.formatDate(result.endDate);
                component.set("v.rangeText", "Showing leads received " + from + (from === to ? "" : " to " + to));
                component.set("v.isPreviousDisabled", pageNumber === 1);
                component.set("v.isNextDisabled", pageNumber * pageSize >= result.filteredTotal);
            } else if (state === "ERROR") {
                var errors = response.getError();
                var msg = (errors && errors[0] && errors[0].message) ? errors[0].message : "Unable to load leads";
                helper.displayMessage(component, msg, "error");
            }
        });
        $A.enqueueAction(action);
    },
    // "2025-11-03" -> "03 Nov 2025" (date-only values are parsed as local dates)
    formatDate: function (iso) {
        if (!iso) return "";
        var p = iso.split("-");
        var d = new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10));
        return d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" });
    },
    formatDateTime: function (iso) {
        if (!iso) return "";
        var d = new Date(iso);
        return d.toLocaleDateString("en-GB", { day: "2-digit", month: "short" }) + " " +
               d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
    },
    previousPage: function (component) {
        var currentPage = component.get("v.currentPage");
        component.set("v.currentPage", currentPage - 1);
        this.loadRecords(component);
    }, 
    nextPage: function (component) {
        var currentPage = component.get("v.currentPage");
        component.set("v.currentPage", currentPage + 1);
        this.loadRecords(component);
    },
    
    displayMessage : function(component,message,type){
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "type": type,
            "message": message
        });
        toastEvent.fire();
    },
    renderEveryMin :function(component, event, helper){
        window.setTimeout(
            $A.getCallback(function() {    
                console.log('setTimeOut');
                self.doneRendering(component, event);
            }), 2000
        );  
        
        //execute callApexMethod() again after 5 sec each
        var self=  this; 
        
        window.setInterval(
            $A.getCallback(function() {    
                console.log('setInterval');
                self.doneRendering(component, event);
            }), 30000
        );  
        
    },
    doneRendering: function(cmp, event){
        console.log('here');
        var Followup = cmp.get("v.DuefollowUpDetails");
        var sv = cmp.get("v.DuesiteVisitDetails");
        console.log(sv);
        var today = new Date();
        var curTime=today;
        var indexList;
        //Followup Render
        if(Followup.length>0)
        {	indexList=[];
         Followup.forEach((e,index)=>{
             var fDate= new Date(e.Scheduled_Date__c);
             if( fDate.getTime()< curTime.valueOf() )
             indexList.push(index);
         });
         
         var changeID=(cmp.find('OverTimeFollow'));
         
         if(changeID!=undefined && changeID.length==undefined && indexList.length>0)
         {
             $A.util.addClass(changeID,'overDue');     
         }	
         else if(changeID.length>0){
             
             changeID.forEach((e,index)=>{
                 if(indexList.includes(index))
                 $A.util.addClass(e,'overDue'); 
             });
             
         }
        }
        
        //SV Render 
        if(sv.length>0)
        {
            indexList=[];
            sv.forEach((e,index)=>{ 
                var svDate= new Date(e.Date__c);
                if(svDate.getTime() < curTime.valueOf() )
                indexList.push(index);
            });
            
            var changeSV=(cmp.find('OverTimeSV'));  
            
            if(changeSV!=undefined && changeSV.length==undefined && indexList.length>0)
            {
                $A.util.addClass(changeSV,'overDue');     
            }
            else if(changeSV.length>0)
            {
                
                changeSV.forEach((e,index)=>{        
                    if(indexList.includes(index))
                    $A.util.addClass(e,'overDue'); 
                }); 
            }
        }
    },
                                    
});