import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getContext from '@salesforce/apex/FirstApplicantChangeController.getContext';
import createChangeWithDetails from '@salesforce/apex/FirstApplicantChangeController.createChangeWithDetails';

// Same checks as the booking's validation rules (Aadhaar_Pattern, PAN_Number_Pattern, Date_of_Birth_Validation).
const FIELD_RULES = {
    Aadhaar__c: { pattern: '[0-9]{12}', patternMessage: 'Aadhaar number must be exactly 12 digits.', maxLength: 12 },
    PAN_Number__c: {
        pattern: '[A-Za-z]{5}[0-9]{4}[A-Za-z]{1}',
        patternMessage: 'PAN must be in the format AAAAA9999A (5 letters, 4 digits, 1 letter).',
        maxLength: 10
    },
    Date_of_Birth__c: { maxDate: 'today', rangeMessage: 'Date of Birth cannot be in the future.' }
};

function todayIso() {
    const d = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export default class FirstApplicantChange extends NavigationMixin(LightningElement) {
    @api recordId; // Booking__c

    @track ctx;
    @track changes = [];
    @track newApplicant = '';
    @track newEmail = '';
    @track newMobile = '';
    @track reason = '';
    @track details = [];
    isLoading = false;
    wiredCtx;

    @wire(getContext, { bookingId: '$recordId' })
    wired(result) {
        this.wiredCtx = result;
        if (result.data) {
            this.ctx = result.data;
            this.buildDetails();
            this.buildChangeLinks();
        } else if (result.error) {
            this.showError(result.error);
        }
    }

    get currentApplicant() {
        return this.ctx ? this.ctx.currentApplicant : '';
    }

    get hasChanges() {
        return this.changes.length > 0;
    }

    // Single-line details sit two per row; addresses (textareas) run full width.
    get shortDetails() {
        return this.details.filter((d) => !d.isTextarea);
    }

    get addressDetails() {
        return this.details.filter((d) => d.isTextarea);
    }

    // Other first-applicant details. They start empty: everything is entered for the new applicant.
    buildDetails() {
        const list = (this.ctx && this.ctx.details) ? this.ctx.details : [];
        this.details = list.map((d) => {
            const rule = FIELD_RULES[d.fieldName] || {};
            return {
            ...d,
            pattern: rule.pattern,
            patternMessage: rule.patternMessage,
            maxLength: rule.maxLength,
            maxDate: rule.maxDate === 'today' ? todayIso() : undefined,
            rangeMessage: rule.rangeMessage,
            value: '',
            options: d.options || [],
            isPicklist: d.type === 'picklist',
            isDate: d.type === 'date',
            isTextarea: d.type === 'textarea',
            isText: d.type === 'text'
            };
        });
    }

    handleDetailChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        this.details = this.details.map((d) => (d.fieldName === field ? { ...d, value } : d));
    }

    detailsJson() {
        const values = {};
        this.details.forEach((d) => {
            if (d.value) values[d.fieldName] = d.value;
        });
        return JSON.stringify(values);
    }

    // Builds the row list with a generated record URL for each change,
    // so the Name column can render as a real, right-click-able link.
    buildChangeLinks() {
        const list = (this.ctx && this.ctx.changes) ? this.ctx.changes : [];
        const rows = list.map((c) => ({ ...c, url: '#' }));
        this.changes = rows;

        Promise.all(
            rows.map((c) =>
                this[NavigationMixin.GenerateUrl]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: c.id,
                        objectApiName: 'First_Applicant_Change__c',
                        actionName: 'view'
                    }
                }).then((url) => {
                    c.url = url;
                })
            )
        ).then(() => {
            this.changes = [...rows]; // trigger re-render once urls resolve
        });
    }

    // Keeps navigation inside the Lightning app (no full page reload) while
    // still leaving href set so ctrl/cmd-click "open in new tab" works.
    handleRecordClick(event) {
        event.preventDefault();
        const id = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: id,
                objectApiName: 'First_Applicant_Change__c',
                actionName: 'view'
            }
        });
    }

    handleNewApplicant(event) { this.newApplicant = event.detail.value; }
    handleNewEmail(event) { this.newEmail = event.detail.value; }
    handleNewMobile(event) {
        const mobile = event.detail.value.replace(/\D/g, '');
        event.target.value = mobile;
        this.newMobile = mobile;
    }
    handleReason(event) { this.reason = event.detail.value; }

    async handleSubmit() {
        // Every field is required; show all the missing ones at once.
        const inputs = [...this.template.querySelectorAll('.fac-field')];
        const allValid = inputs.reduce((ok, input) => input.reportValidity() && ok, true);
        if (!allValid) {
            this.showToast('Missing details', 'Fill in all the fields before submitting for approval.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            await createChangeWithDetails({
                bookingId: this.recordId,
                newApplicantName: this.newApplicant,
                newEmail: this.newEmail,
                newMobile: this.newMobile,
                reason: this.reason,
                detailsJson: this.detailsJson()
            });
            this.showToast(
                'Request created',
                'First Applicant Change request created. It will be applied to the booking once approved.',
                'success'
            );
            this.newApplicant = '';
            this.newEmail = '';
            this.newMobile = '';
            this.reason = '';
            this.buildDetails();
            if (this.wiredCtx) await refreshApex(this.wiredCtx);
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        const message =
            (error && error.body && error.body.message) ||
            (error && error.message) ||
            'Unexpected error';
        this.showToast('Error', message, 'error');
    }
}