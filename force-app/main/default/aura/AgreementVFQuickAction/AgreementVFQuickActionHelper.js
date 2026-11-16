({
    // One entry per document this preview window can show. The quick action picks its entry
    // through the documentType attribute: AgreementVFQuickAction is "agreement" (the default),
    // SaleDeedVFQuickAction extends it and sets "saleDeed".
    //
    //   heading      : title shown in the window header
    //   fileLabel    : start of the downloaded file's name
    //   fallbackPage : page used when the project has no route ("" = show a message instead)
    //   projects     : Project__r.Name -> route. Configure each project separately.
    //                  separationPages optionally maps the Unit's LL_Share_Name__c to a VF page;
    //                  if the LL share name is blank or has no entry, defaultPage is used, and
    //                  if defaultPage is omitted, fallbackPage is used.
    DOCUMENTS: {
        agreement: {
            heading: "Agreement of sale",
            fileLabel: "Agreement of Sale",
            fallbackPage: "BUILDER_SHARE_AGREEMENT_OF_SALE",
            projects: {
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
                // One page for THE DRIZZLE: it prints the HMDA mortgage clause by itself when
                // the booked unit is ticked "Mortgaged to HMDA".
                "The Drizzle": {
                    defaultPage: "SaleAgreementDrizzle"
                }
            }
        },
        saleDeed: {
            heading: "Sale deed",
            fileLabel: "Sale Deed",
            fallbackPage: "",
            projects: {
                "The Drizzle": {
                    defaultPage: "SaleDeedDrizzle"
                },
                "The Legacey": {
                    defaultPage: "T8910_saledeed_Legacy"
                }
            }
        }
    },

    getDocument: function(component) {
        return this.DOCUMENTS[component.get("v.documentType")] || this.DOCUMENTS.agreement;
    },

    applyDocumentType: function(component) {
        component.set("v.heading", this.getDocument(component).heading);
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

        var doc = this.getDocument(component);
        var project = component.get("v.project") || {};
        var unit = component.get("v.unit") || {};
        var projectName = (project.Name || "").trim();
        var llShareName = (unit.LL_Share_Name__c || "").trim();
        var route = this.findRoute(doc.projects, projectName);
        var pageName = this.resolveProjectPage(route, llShareName, doc.fallbackPage);

        if (!pageName) {
            component.set("v.isLoading", false);
            component.set("v.showPreview", false);
            component.set(
                "v.errorMessage",
                "No " + doc.heading.toLowerCase() + " template is set up for "
                    + (projectName || "this booking's project") + " yet."
            );
            return;
        }

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
        component.set("v.subtitle", this.buildSubtitle(component, projectName, llShareName));
        component.set(
            "v.vfUrl",
            "/apex/" + pageName + "?id=" + encodeURIComponent(component.get("v.recordId"))
        );
        component.set("v.errorMessage", "");
        component.set("v.isLoading", false);
        component.set("v.showPreview", true);
    },

    // "The Drizzle · BUILDER SHARE · B-0113 · Unit TW1-1204" - whichever parts are known.
    buildSubtitle: function(component, projectName, llShareName) {
        var booking = component.get("v.booking") || {};
        var unit = component.get("v.unit") || {};
        var parts = [];
        if (projectName) { parts.push(projectName); }
        if (llShareName) { parts.push(llShareName); }
        if (booking.Name) { parts.push(booking.Name); }
        if (unit.Name) { parts.push("Unit " + unit.Name); }
        return parts.join(" · ");
    },

    downloadFileName: function(component) {
        var booking = component.get("v.booking") || {};
        return this.getDocument(component).fileLabel + (booking.Name ? " - " + booking.Name : "");
    },

    resolveProjectPage: function(route, llShareName, fallbackPage) {
        if (typeof route === "string") {
            return route || fallbackPage;
        }
        if (!route || typeof route !== "object") {
            return fallbackPage;
        }

        var defaultPage = route.defaultPage || fallbackPage;
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