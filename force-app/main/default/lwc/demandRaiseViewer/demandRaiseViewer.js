import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord } from 'lightning/uiRecordApi';
import getPaymentSchedules from '@salesforce/apex/PaymentScheduleViewController.getPaymentSchedules';
import raiseDemandForBookingInMode from '@salesforce/apex/PaymentScheduleViewController.raiseDemandForBookingInMode';

export default class PaymentScheduleViewer extends LightningElement {
    @api recordId; // Booking ID from Quick Action

    @track isLoading = false;
    @track schedules = [];
    @track nextDemand = {};
    @track bookingName = '';
    @track projectName = '';
    @track unitName = '';
    @track errorMessage = '';
    @track hasError = false;

    // Modal states
    @track showMainModal = false;
    @track showNextDemandView = false;

    // Next Demand specific fields
    @track lastCompletedMilestone = '';
    @track totalPaidAmount = 0;
    @track formattedPaidAmount = '₹0.00';
    @track paymentDueDate = '';

    @track isRaisingDemand = false;
    @track demandComponent = 'Flat';
    @track demandMode = 'Normal';
    @track includeInterest = true;

    get demandModeOptions() {
        const options = [{ label: 'Normal', value: 'Normal' }];
        if (this.nextDemand.hasAgreementMilestone === true) {
            options.push({ label: 'Agreement Amount only', value: 'Agreement Amount' });
        }
        return options;
    }

    get demandComponentOptions() {
        return this.nextDemand.legacySplitDemandReceipt
            ? [
                { label: 'Flat only', value: 'Flat' },
                { label: 'GST only', value: 'GST' }
            ]
            : [{ label: 'Flat + GST', value: 'Flat + GST' }];
    }

    // Wire to ensure recordId is available
    @wire(getRecord, { recordId: '$recordId', fields: ['Booking__c.Id'] })
    wiredRecord({ error, data }) {
        if (data) {
            console.log('Record loaded successfully:', this.recordId);
            if (!this.showMainModal && !this.showNextDemandView) {
                this.showMainModal = true;
                this.loadData();
            }
        } else if (error) {
            console.error('Error loading record:', error);
            this.hasError = true;
            this.errorMessage = 'Unable to load booking record';
        }
    }

    // Load data on component initialization
    connectedCallback() {
        console.log('Connected - RecordId:', this.recordId);
        this.addBodyClass();

        setTimeout(() => {
            if (this.recordId) {
                this.showMainModal = true;
                this.loadData();
            } else {
                this.hasError = true;
                this.errorMessage = 'Booking ID is missing. Please ensure this component is launched from a Booking record.';
                this.showMainModal = true;
            }
        }, 100);
    }

    disconnectedCallback() {
        this.removeBodyClass();
    }

    addBodyClass() {
        try {
            document.body.classList.add('modal-open');
        } catch (e) {
            console.error('Error adding body class:', e);
        }
    }

    removeBodyClass() {
        try {
            document.body.classList.remove('modal-open');
        } catch (e) {
            console.error('Error removing body class:', e);
        }
    }

    // Load payment schedules
    loadData() {
        if (!this.recordId) {
            console.error('No recordId available');
            this.hasError = true;
            this.errorMessage = 'Booking ID is required';
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        this.hasError = false;
        this.errorMessage = '';

        getPaymentSchedules({ bookingId: this.recordId })
            .then(result => {
                if (result.success) {
                    this.processData(result);
                } else {
                    this.hasError = true;
                    this.errorMessage = result.errorMessage || 'Unknown error occurred';
                    this.showToast('Error', this.errorMessage, 'error');
                }
            })
            .catch(error => {
                this.hasError = true;
                this.errorMessage = this.getErrorMessage(error);
                this.showToast('Error', this.errorMessage, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    processData(result) {
        this.schedules = (result.schedules || []).map(schedule => ({
            ...schedule,
            formattedBasePending: this.formatCurrency(schedule.basePending),
            formattedGstPending: this.formatCurrency(schedule.gstPending),
            formattedTdsPending: this.formatCurrency(schedule.tdsPending)
        }));
        this.nextDemand = result.nextDemand || {};
        this.demandComponent = this.nextDemand.legacySplitDemandReceipt ? 'Flat' : 'Flat + GST';
        this.demandMode = 'Normal';
        this.bookingName = result.bookingName || '';
        this.projectName = result.projectName || 'N/A';
        this.unitName = result.unitName || 'N/A';
        this.calculateNextDemandDetails();
    }

    calculateNextDemandDetails() {
        let lastCompleted = null;
        for (let i = this.schedules.length - 1; i >= 0; i--) {
            if (this.schedules[i].isCompleted) {
                lastCompleted = this.schedules[i];
                break;
            }
        }

        // Prefer the server-computed value (it falls back to the schedule Name when
        // Milestone_Name__c is blank); recompute locally only if it is missing.
        this.lastCompletedMilestone =
            (this.nextDemand && this.nextDemand.lastCompletedMilestone) ||
            (lastCompleted && (lastCompleted.milestoneName || lastCompleted.name)) ||
            'No completed milestones';

        let totalScheduleAmount = 0;
        let totalPendingAmount = 0;

        this.schedules.forEach(schedule => {
            totalScheduleAmount += schedule.amount || 0;
            totalPendingAmount += schedule.pendingAmount || 0;
        });

        this.totalPaidAmount = totalScheduleAmount - totalPendingAmount;
        this.formattedPaidAmount = this.formatCurrency(this.totalPaidAmount);

        const today = new Date();
        const dueDate = new Date(today);
        dueDate.setDate(dueDate.getDate() + 15);
        this.paymentDueDate = this.formatDate(dueDate);
    }

    formatCurrency(value) {
        if (value === null || value === undefined) {
            return '₹0.00';
        }
        return '₹' + value.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    formatDate(date) {
        const options = { year: 'numeric', month: 'long', day: 'numeric' };
        return date.toLocaleDateString('en-IN', options);
    }

    // ==================== NAVIGATION ====================

    handleNext() {
        this.showMainModal = false;
        this.showNextDemandView = true;
    }

    handleBack() {
        this.showNextDemandView = false;
        this.showMainModal = true;
    }

    handleRaiseDemand() {
        if (this.isRaisingDemand) return;
        if (this.selectedDemand.totalAmount <= 0) {
            this.showToast('Cannot Raise Demand', 'Zero amount demand cannot be raised.', 'error');
            return;
        }

        this.isRaisingDemand = true;
        raiseDemandForBookingInMode({
            bookingId: this.recordId,
            demandComponent: this.demandComponent,
            includeInterest: this.demandComponent !== 'GST' && this.includeInterest,
            demandMode: this.demandMode
        })
            .then(() => {
                this.showToast('Success',
                    'Demand raised. The email-on-create flow will pick it up.', 'success');
                this.handleClose();
            })
            .catch(error => {
                const msg = (error && error.body && error.body.message)
                    ? error.body.message
                    : (error && error.message) || 'Could not raise demand';
                this.showToast('Error', msg, 'error');
            })
            .finally(() => {
                this.isRaisingDemand = false;
            });
    }

    handleRefresh() {
        this.loadData();
    }

    handleDemandComponentChange(event) {
        this.demandComponent = event.detail.value;
        if (!this.isFirstDemand) {
            this.demandMode = 'Normal';
        }
    }

    handleDemandModeChange(event) {
        this.demandMode = event.detail.value;
    }

    handleInterestChange(event) {
        this.includeInterest = event.target.checked;
    }

    handleClose() {
        this.removeBodyClass();
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleBackdropClick(event) {
        if (event.target.classList.contains('modal-container')) {
            // Optionally close on backdrop click
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        } else if (error.body && error.body.message) {
            return error.body.message;
        } else if (error.message) {
            return error.message;
        }
        return 'Unknown error occurred';
    }

    // ==================== COMPUTED PROPERTIES ====================

    get hasSchedules() {
        return this.demandEligibleSchedules.length > 0;
    }

    get demandEligibleSchedules() {
        return (this.schedules || []).filter(schedule => !schedule.isTimeBased);
    }

    get hasNextDemand() {
        return this.selectedDemand.totalAmount > 0;
    }

    get isFirstDemand() {
        if (!this.nextDemand) return false;
        if (this.nextDemand.legacySplitDemandReceipt === true) {
            return this.demandComponent === 'Flat'
                ? this.nextDemand.isFirstFlatDemand === true
                : this.demandComponent === 'GST'
                    && this.nextDemand.isFirstGstDemand === true;
        }
        return this.nextDemand.isFirstCombinedDemand === true;
    }

    get isAgreementAmountOnly() {
        return this.demandMode === 'Agreement Amount';
    }

    get showSourceBreakdown() {
        return this.nextDemand
            && this.nextDemand.hasSplitFunding === true
            && this.nextDemand.legacySplitDemandReceipt === true
            && this.completedSchedules.some(schedule => schedule.isBankDemand);
    }

    get isFlatOnlyDemand() {
        return this.demandComponent === 'Flat';
    }

    get isGstOnlyDemand() {
        return this.demandComponent === 'GST';
    }

    get isCombinedDemand() {
        return this.demandComponent === 'Flat + GST';
    }

    get selectedDemand() {
        const amounts = this.calculatedDemandAmounts;
        const flatAmount = amounts.flatAmount;
        const gstAmount = amounts.gstAmount;
        const tdsAmount = amounts.tdsAmount;
        const totalAmount = flatAmount + gstAmount + tdsAmount;
        let bankAmount = 0;
        let customerAmount = 0;
        let interestAmount = 0;
        let fullScheduleWithTdsAmount = 0;
        let fullScheduleFlatAmount = 0;
        let fullScheduleGstAmount = 0;
        let receivedFlatAmount = 0;
        let receivedGstAmount = 0;
        let receivedTdsAmount = 0;
        this.demandLines.forEach(line => {
            if (line.isBankDemand) bankAmount += line.selectedDemandAmount;
            else customerAmount += line.selectedDemandAmount;
            fullScheduleWithTdsAmount += line.fullScheduleWithTdsAmount;
            fullScheduleFlatAmount += line.fullScheduleFlatAmount;
            fullScheduleGstAmount += line.fullScheduleGstAmount;
            receivedFlatAmount += line.receivedFlatAmount;
            receivedGstAmount += line.receivedGstAmount;
            receivedTdsAmount += line.receivedTdsAmount;
            if (this.demandComponent !== 'GST') interestAmount += line.interestPending || 0;
        });
        const includedInterest = this.demandComponent !== 'GST' && this.includeInterest
            ? interestAmount
            : 0;
        const availableWaiver = Number(this.nextDemand.availableInterestWaiver) || 0;
        const waivedInterest = Math.min(includedInterest, availableWaiver);
        const netInterest = includedInterest - waivedInterest;
        const netAmount = totalAmount + netInterest;
        return {
            totalAmount,
            flatAmount,
            gstAmount,
            tdsAmount,
            hasTdsAmount: tdsAmount > 0,
            interestAmount: netInterest,
            interestWaivedOff: waivedInterest,
            netAmount,
            fullScheduleWithTdsAmount,
            fullScheduleFlatAmount,
            fullScheduleGstAmount,
            receivedFlatAmount,
            receivedGstAmount,
            receivedTdsAmount,
            formattedTotal: this.formatCurrency(netAmount),
            formattedComponentAmount: this.formatCurrency(totalAmount),
            formattedFlatAmount: this.formatCurrency(flatAmount),
            formattedDemandFlatWithTdsAmount: this.formatCurrency(flatAmount + tdsAmount),
            formattedInstallmentPayable: this.formatCurrency(totalAmount - tdsAmount),
            formattedGstAmount: this.formatCurrency(gstAmount),
            formattedTdsAmount: this.formatCurrency(tdsAmount),
            formattedFullScheduleWithTdsAmount: this.formatCurrency(fullScheduleWithTdsAmount),
            formattedFullScheduleFlatAmount: this.formatCurrency(fullScheduleFlatAmount),
            formattedFullScheduleGstAmount: this.formatCurrency(fullScheduleGstAmount),
            formattedReceivedFlatAmount: this.formatCurrency(receivedFlatAmount),
            formattedReceivedGstAmount: this.formatCurrency(receivedGstAmount),
            formattedReceivedTdsAmount: this.formatCurrency(receivedTdsAmount),
            formattedGrossInterest: this.formatCurrency(interestAmount),
            formattedInterestWaivedOff: this.formatCurrency(waivedInterest),
            formattedInterest: this.formatCurrency(netInterest),
            formattedBankAmount: this.formatCurrency(bankAmount),
            formattedCustomerAmount: this.formatCurrency(customerAmount),
        };
    }

    get calculatedDemandAmounts() {
        const amounts = this.demandLines.reduce((totals, line) => {
            totals.flatAmount += line.selectedFlatDemandAmount;
            totals.gstAmount += line.selectedGstDemandAmount;
            totals.tdsAmount += line.selectedDemandTdsAmount;
            totals.demandAmount += line.selectedDemandAmount;
            return totals;
        }, { flatAmount: 0, gstAmount: 0, tdsAmount: 0, demandAmount: 0 });

        if (this.demandComponent !== 'GST') {
            amounts.tdsAmount = Number(amounts.tdsAmount.toFixed(2));
            amounts.flatAmount = Number(Math.max(
                0,
                amounts.demandAmount - amounts.gstAmount - amounts.tdsAmount
            ).toFixed(2));
        }
        return amounts;
    }

    get nextDemandTitle() {
        return 'Next Demand Summary';
    }

    get completedSchedulesText() {
        const count = this.nextDemand.completedScheduleCount || 0;
        return `${count} Completed Schedule${count !== 1 ? 's' : ''}`;
    }

    // Step indicator computed
    get stepIndicatorClasses() {
        if (this.showMainModal) return { step1: 'step-dot active', step2: 'step-dot' };
        if (this.showNextDemandView) return { step1: 'step-dot done', step2: 'step-dot active' };
        return { step1: 'step-dot', step2: 'step-dot' };
    }

    get step1DotClass() { return this.stepIndicatorClasses.step1; }
    get step2DotClass() { return this.stepIndicatorClasses.step2; }

    // Expanded detail calculation values
    get isFlatDemand() {
        return this.demandComponent === 'Flat' || this.demandComponent === 'Flat + GST';
    }

    get isGstDemand() {
        return this.demandComponent === 'GST' || this.demandComponent === 'Flat + GST';
    }

    get totalBaseAmount() {
        let total = 0;
        this.schedules.forEach(s => { total += s.baseAmount || 0; });
        return this.formatCurrency(total);
    }

    get totalGstAmount() {
        let total = 0;
        this.schedules.forEach(s => { total += s.gstAmount || 0; });
        return this.formatCurrency(total);
    }

    get totalTdsScheduleAmount() {
        let total = 0;
        this.schedules.forEach(s => { total += s.tdsAmount || 0; });
        return this.formatCurrency(total);
    }

    get totalInterest() {
        let total = 0;
        this.demandLines.forEach(line => { total += line.interestPending || 0; });
        return this.formatCurrency(total);
    }

    get hasAnyInterest() {
        return this.demandComponent !== 'GST'
            && this.demandLines.some(line => (line.interestPending || 0) > 0);
    }

    get completedSchedules() {
        return this.demandEligibleSchedules.filter(s => s.isCompleted);
    }

    get paidSchedules() {
        return this.demandEligibleSchedules.filter(s => s.isPaid);
    }

    get pendingSchedules() {
        return this.demandEligibleSchedules.filter(s => !s.isPaid && !s.isCompleted);
    }

    get completedCount() {
        return this.completedSchedules.length;
    }

    get paidCount() {
        return this.paidSchedules.length;
    }

    get pendingCount() {
        return this.pendingSchedules.length;
    }

    get totalCount() {
        return this.demandEligibleSchedules.length;
    }

    get progressPercent() {
        if (!this.totalCount) return 0;
        return Math.round(((this.paidCount + this.completedCount) / this.totalCount) * 100);
    }

    get progressStyle() {
        return `width: ${this.progressPercent}%`;
    }

    // The milestones actually contributing to the next demand, each tagged with its source
    // (Bank or Customer) so the raising UI can show the user where the money is coming from.
    get demandLines() {
        const schedules = this.completedSchedules.filter(schedule => {
            if (!this.isAgreementAmountOnly) return true;
            const agreementSequence = Number(this.nextDemand.agreementSequence);
            return Number.isFinite(agreementSequence)
                && schedule.sequenceNumber !== null
                && schedule.sequenceNumber !== undefined
                && Number(schedule.sequenceNumber) <= agreementSequence;
        });
        return schedules
            .map(schedule => {
                const fullScheduleWithTdsAmount =
                    (Number(schedule.baseAmount) || 0) + (Number(schedule.tdsAmount) || 0);
                const fullScheduleFlatAmount = Number(schedule.baseAmount) || 0;
                const fullScheduleGstAmount = Number(schedule.gstAmount) || 0;
                const receivedFlatAmount = Number(schedule.basePaid) || 0;
                const receivedGstAmount = Number(schedule.gstPaid) || 0;
                const receivedTdsAmount = Number(schedule.tdsPaid) || 0;
                const selectedDemandAmount = this.isCombinedDemand
                    ? (schedule.combinedDemandableAmount || 0)
                    : (this.isFlatOnlyDemand
                        ? (schedule.flatDemandableAmount || 0)
                        : (schedule.gstDemandableAmount || 0));
                const selectedGstDemandAmount = this.isFlatOnlyDemand
                    ? 0
                    : (schedule.gstDemandableAmount || 0);
                const selectedDemandTdsAmount = this.isGstOnlyDemand
                    ? 0
                    : (schedule.tdsDemandableAmount || 0);
                const selectedFlatDemandAmount = Math.max(
                    0,
                    selectedDemandAmount - selectedGstDemandAmount - selectedDemandTdsAmount
                );

                return {
                    ...schedule,
                    selectedDemandAmount,
                    selectedFlatDemandAmount,
                    selectedGstDemandAmount,
                    selectedDemandTdsAmount,
                    fullScheduleWithTdsAmount,
                    fullScheduleFlatAmount,
                    fullScheduleGstAmount,
                    receivedFlatAmount,
                    receivedGstAmount,
                    receivedTdsAmount,
                    formattedAmountA: this.formatCurrency(selectedDemandAmount),
                    formattedTds: this.formatCurrency(selectedDemandTdsAmount),
                    formattedFlatAmount: this.formatCurrency(selectedFlatDemandAmount),
                    formattedGstAmount: this.formatCurrency(selectedGstDemandAmount),
                    formattedDemandFlatWithTds: this.formatCurrency(
                        selectedFlatDemandAmount + selectedDemandTdsAmount
                    ),
                    formattedDemandPayable: this.formatCurrency(
                        Math.max(0, selectedDemandAmount - selectedDemandTdsAmount)
                    ),
                    formattedFullScheduleWithTdsAmount: this.formatCurrency(fullScheduleWithTdsAmount),
                    formattedFullScheduleFlatAmount: this.formatCurrency(fullScheduleFlatAmount),
                    formattedFullScheduleGstAmount: this.formatCurrency(fullScheduleGstAmount),
                    formattedReceivedFlatAmount: this.formatCurrency(receivedFlatAmount),
                    formattedReceivedGstAmount: this.formatCurrency(receivedGstAmount),
                    formattedReceivedTdsAmount: this.formatCurrency(receivedTdsAmount),
                    formattedNetAmount: this.formatCurrency(
                        Math.max(0, selectedDemandAmount - selectedDemandTdsAmount)
                    ),
                    formattedSelectedDemand: this.formatCurrency(selectedDemandAmount)
                };
            })
            .filter(s => !(
                this.showSourceBreakdown
                && this.nextDemand.legacySplitDemandReceipt
                && !s.isBankDemand
            ))
            .filter(s => s.selectedDemandAmount > 0);
    }

    get hasDemandLines() {
        return this.demandLines.length > 0;
    }
}