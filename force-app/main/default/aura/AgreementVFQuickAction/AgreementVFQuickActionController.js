({
    doInit: function(component, event, helper) {
        if (!component.get("v.recordId")) {
            component.set("v.isLoading", false);
            component.set("v.errorMessage", "Open this action from a Booking record.");
        }
    },

    handleBookingUpdated: function(component, event, helper) {
        helper.handleBookingUpdated(component, event);
    },

    handleProjectUpdated: function(component, event, helper) {
        helper.handleRelatedRecordUpdated(component, event, "projectLoaded");
    },

    handleUnitUpdated: function(component, event, helper) {
        helper.handleRelatedRecordUpdated(component, event, "unitLoaded");
    },

    close: function() {
        $A.get("e.force:closeQuickAction").fire();
    }
})