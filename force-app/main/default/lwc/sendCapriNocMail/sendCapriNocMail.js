import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSendPreview from '@salesforce/apex/CapriNocApprovedEmailInvocable.getSendPreview';
import sendNow from '@salesforce/apex/CapriNocApprovedEmailInvocable.sendNow';

/**
 * "Send Capri NOC Mail" button on the NOC record. Shows who the mail goes to and which letters
 * it carries, and sends only when the user confirms.
 */
export default class SendCapriNocMail extends LightningElement {
    preview;
    loadError;
    isSending = false;
    _recordId;
    _loadedFor;

    // In a quick action recordId arrives after connectedCallback, so load from the setter.
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && value !== this._loadedFor) {
            this._loadedFor = value;
            this.loadPreview();
        }
    }

    async loadPreview() {
        try {
            this.preview = await getSendPreview({ nocId: this._recordId });
        } catch (error) {
            this.loadError = this.messageOf(error);
        }
    }

    get isLoading() {
        return !this.preview && !this.loadError;
    }

    get blockedReason() {
        return this.loadError || (this.preview ? this.preview.blockedReason : null);
    }

    get canSend() {
        return this.preview && !this.preview.blockedReason;
    }

    get sendDisabled() {
        return !this.canSend || this.isSending;
    }

    get sendLabel() {
        return this.preview && this.preview.lastSentOn ? 'Send Again' : 'Send';
    }

    get alreadySent() {
        return this.canSend && this.preview.lastSentOn;
    }

    async handleSend() {
        this.isSending = true;
        try {
            await sendNow({ nocId: this._recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Capri NOC mail is being sent',
                    message: 'To ' + this.preview.capriEmail + ' with ' + this.preview.attachmentNames.length + ' attachment(s).',
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Mail not sent', message: this.messageOf(error), variant: 'error', mode: 'sticky' })
            );
        } finally {
            this.isSending = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    messageOf(error) {
        return (error && error.body && error.body.message) || (error && error.message) || 'Something went wrong.';
    }
}