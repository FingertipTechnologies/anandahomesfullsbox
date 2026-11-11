({
    DEFAULT_PAGE: "BUILDER_SHARE_AGREEMENT_OF_SALE",

    // Configure each Project__r.Name separately.
    // separationPages optionally maps the Unit's LL_Share_Name__c to a VF page.
    // If the LL share name is blank or has no entry, defaultPage is used.
    // If defaultPage is omitted, DEFAULT_PAGE is used.
    PROJECT_PAGE_MAP: {
        "The Legacey": {
            defaultPage: "BUILDER_SHARE_AGREEMENT_OF_SALE",
            separationPages: {
                "ARJUN SINGH": "ARJUN_SINGH_AGREEMENT_OF_SALE",
                "MAGAN SINGH": "MAGHAN_SINGH_AGREEMENT_OF_SALE",
                "SURESH SINGH": "SURESH_SINGH_AGREEMENT_OF_SALE",
                "NAVEEN SINGH": "NAVEEN_SINGH_AGREEMENT_OF_SALE",
                "NITIN SINGH": "NITIN_SINGH_AGREEMENT_OF_SALE",
                "BUILDER SHARE": "BUILDER_SHARE_AGREEMENT_OF_SALE"
            }
        },
        "The Drizzle": {
            defaultPage: "SaleAgreementDrizzil"
        }
    },

    handleBookingUpdated: function(component, event) {
        var changeType = event.getParams().changeType;

        if (changeType === "ERROR") {
            component.set("v.isLoading", false);
            component.set("v.errorMessage", this.getRecordError(event));
            return;
        }

        if (changeType !== "LOADED" && changeType !== "CHANGED") {
            return;
        }

        var booking = component.get("v.booking") || {};
        component.set("v.projectId", booking.Project__c || "");
        component.set("v.unitId", booking.Plot__c || "");
        component.set("v.bookingLoaded", true);
        component.set("v.projectLoaded", !booking.Project__c);
        component.set("v.unitLoaded", !booking.Plot__c);

        this.resolvePreview(component);
    },

    handleRelatedRecordUpdated: function(component, event, loadedAttribute) {
        var changeType = event.getParams().changeType;
        if (changeType === "ERROR") {
            component.set("v.isLoading", false);
            component.set("v.errorMessage", this.getRecordError(event));
            return;
        }
        if (changeType !== "LOADED" && changeType !== "CHANGED") {
            return;
        }

        component.set("v." + loadedAttribute, true);

        this.resolvePreview(component);
    },

    resolvePreview: function(component) {
        if (!component.get("v.bookingLoaded")
            || !component.get("v.projectLoaded")
            || !component.get("v.unitLoaded")) {
            return;
        }

        var project = component.get("v.project") || {};
        var unit = component.get("v.unit") || {};
        var projectName = (project.Name || "").trim();
        var llShareName = (unit.LL_Share_Name__c || "").trim();
        var route = this.findRoute(this.PROJECT_PAGE_MAP, projectName);
        var pageName = this.resolveProjectPage(route, llShareName);

        if (!this.isValidPageName(pageName)) {
            component.set("v.isLoading", false);
            component.set("v.showPreview", false);
            component.set(
                "v.errorMessage",
                "No valid Visualforce page is configured for this Booking. Check the project and LL share-name routes in AgreementVFQuickActionHelper.js."
            );
            return;
        }

        component.set("v.selectedPage", pageName);
        component.set(
            "v.vfUrl",
            "/apex/" + pageName + "?id=" + encodeURIComponent(component.get("v.recordId"))
        );
        component.set("v.errorMessage", "");
        component.set("v.isLoading", false);
        component.set("v.showPreview", true);
    },

    resolveProjectPage: function(route, llShareName) {
        if (typeof route === "string") {
            return route || this.DEFAULT_PAGE;
        }
        if (!route || typeof route !== "object") {
            return this.DEFAULT_PAGE;
        }

        var defaultPage = route.defaultPage || this.DEFAULT_PAGE;
        var separationPages = route.separationPages || {};
        return this.findRoute(separationPages, llShareName) || defaultPage;
    },

    findRoute: function(routeMap, value) {
        var normalizedValue = (value || "").trim().toLowerCase();
        if (!normalizedValue) {
            return "";
        }

        var routeKeys = Object.keys(routeMap);
        for (var i = 0; i < routeKeys.length; i += 1) {
            if (routeKeys[i].trim().toLowerCase() === normalizedValue) {
                return routeMap[routeKeys[i]];
            }
        }
        return "";
    },

    isValidPageName: function(pageName) {
        return typeof pageName === "string"
            && /^[A-Za-z][A-Za-z0-9_]*$/.test(pageName);
    },

    getRecordError: function(event) {
        var errors = event.getParams().error;
        if (errors && errors.length && errors[0].message) {
            return errors[0].message;
        }
        if (errors && errors.message) {
            return errors.message;
        }
        return "Could not load the Booking, Project, or Unit details.";
    }
})