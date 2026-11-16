({
    doInit: function(component, event, helper) {
        helper.applyDocumentType(component);
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

    // Same PDF in a browser tab of its own.
    openInNewTab: function(component) {
        var url = component.get("v.vfUrl");
        if (url) {
            window.open(url, "_blank");
        }
    },

    // download=1 makes the agreement page send the PDF as a file instead of showing it.
    download: function(component, event, helper) {
        var url = component.get("v.vfUrl");
        if (url) {
            window.open(
                url + "&download=1&fileName=" + encodeURIComponent(helper.downloadFileName(component)),
                "_blank"
            );
        }
    },

    close: function() {
        $A.get("e.force:closeQuickAction").fire();
    }
})