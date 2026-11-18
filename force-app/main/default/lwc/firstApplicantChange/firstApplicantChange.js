import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getContext from '@salesforce/apex/FirstApplicantChangeController.getContext';
import createChangeWithDetails from '@salesforce/apex/FirstApplicantChangeController.createChangeWithDetails';

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

    get hasDetails() {
        return this.details.length > 0;
    }

    // Other first-applicant details, prefilled with the booking's current values.
    buildDetails() {
        const list = (this.ctx && this.ctx.details) ? this.ctx.details : [];
        this.details = list.map((d) => ({
            ...d,
            value: d.value || '',
            options: d.options || [],
            isPicklist: d.type === 'picklist',
            isDate: d.type === 'date',
            isTextarea: d.type === 'textarea',
            isText: d.type === 'text'
        }));
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

    get submitDisabled() {
        return this.isLoading || !this.newApplicant;
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
        const mobileInput = this.template.querySelector('[data-id="new-mobile"]');
        if (mobileInput && !mobileInput.reportValidity()) {
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