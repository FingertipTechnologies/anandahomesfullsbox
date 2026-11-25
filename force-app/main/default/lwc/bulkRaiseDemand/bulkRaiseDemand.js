import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProjectContext from '@salesforce/apex/BulkDemandController.getProjectContext';
import getCompletedMilestones from '@salesforce/apex/BulkDemandController.getCompletedMilestones';
import getBookingsForMilestone from '@salesforce/apex/BulkDemandController.getBookingsForMilestone';
import getIndividualCompletedSchedules from '@salesforce/apex/BulkDemandController.getIndividualCompletedSchedules';
import createBulkDemands from '@salesforce/apex/BulkDemandController.createBulkDemands';
import sendBulkDemandEmails from '@salesforce/apex/BulkDemandController.sendBulkDemandEmails';
import getConfigurationByType from '@salesforce/apex/PostSalesAdminController.getConfigurationByType';
import resolveConfigurationForRecord from '@salesforce/apex/PostSalesAdminController.resolveConfigurationForRecord';
import getEmailTemplateOptions from '@salesforce/apex/PostSalesAdminController.getEmailTemplateOptions';
import getProjects from '@salesforce/apex/BulkDemandController.getProjects';
import getProjectTowers from '@salesforce/apex/BulkDemandController.getProjectTowers';
import getMilestoneImageCount from '@salesforce/apex/ProjectStatusReportController.getMilestoneImageCount';

export default class BulkRaiseDemand extends LightningElement {
    @api recordId;

    // State
    @track isLoading = false;
    @track showModal = false;
    @track currentStep = 1;

    // Project selector (for Tab/AppPage mode)
    @track projectOptions = [];
    @track selectedProjectId = '';

    // Project context
    @track projectContext = {};
    @track demandConfig = {};

    // Step 2: Milestones (Apartment flow)
    @track towerOptions = [];
    @track selectedTowerId = '';
    @track milestones = [];
    @track selectedMilestoneId = null;
    @track demandComponent = 'Flat';

    get demandComponentOptions() {
        return this.projectContext.legacySplitDemandReceipt
            ? [
                { label: 'Flat only', value: 'Flat' },
                { label: 'GST only', value: 'GST' }
            ]
            : [{ label: 'Flat + GST', value: 'Flat + GST' }];
    }

    // Step 3: Bookings
    @track bookings = [];
    @track selectAll = true;

    // Step 4: Review
    @track emailTemplateOptions = [];
    @track selectedTemplateId = '';
    @track gracePeriodDays = 15;
    @track dueDateOffsetDays = 15;
    @track includeInterest = true;
    @track includePreviousDues = false;
    @track autoSendEmail = false;
    @track notes = '';

    // Step 5/6: Results
    @track demandResult = {};
    @track isProcessing = false;

    // Flow type
    get isApartmentFlow() {
        const type = (this.projectContext.projectType || '').toLowerCase();
        return type === 'apartment';
    }

    get isIndividualFlow() {
        const type = (this.projectContext.projectType || '').toLowerCase();
        // Default to individual flow for Plot/Villa AND any other type (Mixed, Commercial, blank)
        // so the component doesn't show an empty screen
        return type !== 'apartment';
    }

    // Project selector (Tab/AppPage mode)
    get showProjectSelector() {
        return !this.recordId;
    }

    get launchDisabled() {
        return !this.recordId && !this.selectedProjectId;
    }

    get effectiveProjectId() {
        return this.recordId || this.selectedProjectId;
    }

    connectedCallback() {
        if (!this.recordId) {
            this.loadProjectList();
        }
    }

    loadProjectList() {
        getProjects()
            .then(result => {
                this.projectOptions = result.map(p => ({
                    label: p.Name,
                    value: p.Id
                }));
            })
            .catch(() => {});
    }

    handleProjectSelect(event) {
        this.selectedProjectId = event.detail.value;
    }

    // Step visibility
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get isStep5() { return this.currentStep === 5; }
    get isStep6() { return this.currentStep === 6; }

    // Computed
    get hasMilestones() { return this.milestones && this.milestones.length > 0; }
    get hasBookings() { return this.bookings && this.bookings.length > 0; }
    get currentMilestoneLabel() {
        if (this.demandComponent === 'GST') return 'GST at Milestone';
        if (this.demandComponent === 'Flat + GST') return 'Flat + GST at Milestone';
        return 'Flat at Milestone';
    }
    get isLoadBookingsDisabled() {
        return !this.selectedMilestoneId || (this.towerOptions.length > 0 && !this.selectedTowerId);
    }
    get hasTowers() { return this.towerOptions && this.towerOptions.length > 0; }

    get selectedBookings() {
        return this.bookings.filter(b => b.isSelected);
    }

    get selectedCount() {
        return this.selectedBookings.length;
    }

    get totalDemandAmount() {
        return this.selectedBookings.reduce(
            (sum, b) => sum + (Number(b.totalPending) || 0),
            0
        );
    }

    get totalFlatAmount() {
        return this.selectedBookings.reduce((sum, b) => sum + (b.totalFlatAmount || 0), 0);
    }

    get totalGstAmount() {
        return this.selectedBookings.reduce((sum, b) => sum + (b.totalGstAmount || 0), 0);
    }

    get totalTdsAmount() {
        return this.selectedBookings.reduce((sum, b) => sum + (b.totalTdsAmount || 0), 0);
    }

    get totalGrossInterest() {
        return this.selectedBookings.reduce((sum, b) => sum + (Number(b.grossInterest) || 0), 0);
    }

    get totalBankPayable() {
        return this.selectedBookings.reduce((sum, b) => sum + (Number(b.bankPayableAmount) || 0), 0);
    }

    get totalCustomerPayable() {
        return this.selectedBookings.reduce((sum, b) => sum + (Number(b.customerPayableAmount) || 0), 0);
    }

    get totalNetDemand() {
        return this.selectedBookings.reduce((sum, b) => sum + (Number(b.netDemandAmount) || 0), 0);
    }

    get formattedTotalDemand() { return this.formatCurrency(this.totalDemandAmount); }
    get formattedTotalFlatAmount() { return this.formatCurrency(this.totalFlatAmount); }
    get formattedTotalGstAmount() { return this.formatCurrency(this.totalGstAmount); }
    get formattedTotalTdsAmount() { return this.formatCurrency(this.totalTdsAmount); }
    get formattedTotalGrossInterest() { return this.formatCurrency(this.totalGrossInterest); }
    get formattedTotalBankPayable() { return this.formatCurrency(this.totalBankPayable); }
    get formattedTotalCustomerPayable() { return this.formatCurrency(this.totalCustomerPayable); }
    get formattedTotalNetDemand() { return this.formatCurrency(this.totalNetDemand); }

    get canProceedToReview() {
        return this.selectedCount > 0;
    }
    get isReviewDisabled() { return !this.canProceedToReview; }
    get isGstDemand() { return this.demandComponent === 'GST'; }

    get selectedMilestoneName() {
        const ms = this.milestones.find(m => m.id === this.selectedMilestoneId);
        return ms ? ms.name : '';
    }

    get stepIndicator() {
        const steps = ['Init', 'Select', 'Bookings', 'Review', 'Process', 'Results'];
        return steps.map((label, idx) => ({
            label,
            number: idx + 1,
            isCurrent: this.currentStep === idx + 1,
            isComplete: this.currentStep > idx + 1,
            cssClass: this.currentStep === idx + 1 ? 'step-item step-current' :
                      this.currentStep > idx + 1 ? 'step-item step-complete' : 'step-item'
        }));
    }

    get hasResults() {
        return this.demandResult && this.demandResult.results && this.demandResult.results.length > 0;
    }

    // ============ LAUNCH ============

    handleLaunch() {
        if (!this.effectiveProjectId) {
            this.showToast('Project Required', 'Please select a project first.', 'warning');
            return;
        }
        this.showModal = true;
        this.currentStep = 1;
        this.loadProjectContext();
    }

    handleClose() {
        this.showModal = false;
        this.currentStep = 1;
        this.resetState();
    }

    resetState() {
        this.towerOptions = [];
        this.selectedTowerId = '';
        this.milestones = [];
        this.selectedMilestoneId = null;
        this.bookings = [];
        this.selectAll = true;
        this.selectedTemplateId = '';
        this.gracePeriodDays = 15;
        this.includeInterest = true;
        this.notes = '';
        this.demandResult = {};
        this.isProcessing = false;
    }

    // ============ STEP 1: PROJECT CONTEXT ============

    loadProjectContext() {
        this.isLoading = true;

        // Each promise has its own catch so one failure doesn't break all
        const contextPromise = getProjectContext({ projectId: this.effectiveProjectId })
            .catch(error => {
                this.showToast('Error', 'Failed to load project: ' + this.getErrorMessage(error), 'error');
                return null;
            });

        const configPromise = getConfigurationByType({ configurationType: 'Demand' })
            .catch(() => null);

        const templatesPromise = getEmailTemplateOptions()
            .catch(() => []);

        Promise.all([contextPromise, configPromise, templatesPromise])
            .then(([context, config, templates]) => {
                if (!context) {
                    this.isLoading = false;
                    return;
                }
                this.projectContext = context;
                this.demandComponent = context.legacySplitDemandReceipt ? 'Flat' : 'Flat + GST';

                if (config) {
                    this.demandConfig = config;
                    this.gracePeriodDays = config.gracePeriodDays != null ? config.gracePeriodDays : 15;
                    this.dueDateOffsetDays = config.dueDateOffsetDays != null ? config.dueDateOffsetDays : 15;
                    this.includeInterest = config.includeInterest || false;
                    this.includePreviousDues = config.includePreviousDues || false;
                    this.autoSendEmail = config.autoSendEmail || false;
                    if (config.emailTemplateId) {
                        this.selectedTemplateId = config.emailTemplateId;
                    }
                }

                if (templates) {
                    this.emailTemplateOptions = [
                        { label: '-- No Email --', value: '' },
                        ...templates.map(t => ({ label: t.label, value: t.value }))
                    ];
                }

                // Auto-advance based on project type
                this.currentStep = 2;
                this.loadStep2Data();
            })
            .finally(() => { this.isLoading = false; });
    }

    // ============ STEP 2: MILESTONE SELECTION ============

    loadStep2Data() {
        this.isLoading = true;
        getProjectTowers({ projectId: this.effectiveProjectId })
            .then(towers => {
                this.towerOptions = (towers || []).map(tower => ({
                    label: tower.name,
                    value: tower.id
                }));
                if (this.hasTowers) {
                    this.selectedTowerId = '';
                    this.selectedMilestoneId = null;
                    this.milestones = [];
                    return;
                }
                return this.loadMilestones(null);
            })
            .catch(error => { this.showToast('Error', this.getErrorMessage(error), 'error'); })
            .finally(() => { this.isLoading = false; });
    }

    loadMilestones(towerId) {
        this.isLoading = true;
        return getCompletedMilestones({
            projectId: this.effectiveProjectId,
            towerId: towerId || null
        })
            .then(result => {
                this.milestones = (result || []).map(ms => ({
                    ...ms,
                    cardClass: 'ms-card' + (ms.demandAlreadyRaised ? ' ms-card-raised' : ''),
                    radioClass: 'ms-radio'
                }));
            })
            .catch(error => {
                this.milestones = [];
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    handleTowerSelect(event) {
        this.selectedTowerId = event.detail.value;
        this.selectedMilestoneId = null;
        this.bookings = [];
        this.loadMilestones(this.selectedTowerId);
    }

    // Site photos of the selected milestone (Files on its Master Payment Schedule). They go on the
    // Project Status Report attached to the demand email; when there is none, the user is asked
    // to upload one here (user 2026-11-25).
    @track milestoneImageCount = null;

    get showMilestonePhotoPanel() {
        return !!this.selectedMilestoneId && this.milestoneImageCount !== null;
    }

    get milestoneHasNoPhoto() {
        return this.milestoneImageCount === 0;
    }

    get milestonePhotoMessage() {
        return this.milestoneImageCount === 1
            ? '1 site photo is on file for this milestone. It will appear on the Project Status Report sent with the demand.'
            : this.milestoneImageCount + ' site photos are on file for this milestone. The latest 3 will appear on the Project Status Report sent with the demand.';
    }

    get photoAcceptedFormats() {
        return ['.png', '.jpg', '.jpeg', '.gif'];
    }

    loadMilestoneImageCount() {
        const msId = this.selectedMilestoneId;
        this.milestoneImageCount = null;
        if (!msId) return;
        getMilestoneImageCount({ masterId: msId })
            .then(count => {
                if (this.selectedMilestoneId === msId) this.milestoneImageCount = count || 0;
            })
            .catch(() => {
                this.milestoneImageCount = null;
            });
    }

    handleMilestonePhotoUploaded(event) {
        const files = (event.detail && event.detail.files) || [];
        this.showToast('Success', files.length + ' photo(s) saved to the milestone.', 'success');
        this.loadMilestoneImageCount();
    }

    handleMilestoneSelect(event) {
        const msId = event.currentTarget.dataset.id;
        this.selectedMilestoneId = msId;
        this.loadMilestoneImageCount();
        // Update card styling
        this.milestones = this.milestones.map(ms => ({
            ...ms,
            cardClass: 'ms-card' + (ms.id === msId ? ' ms-card-selected' : '') + (ms.demandAlreadyRaised ? ' ms-card-raised' : ''),
            radioClass: ms.id === msId ? 'ms-radio ms-radio-selected' : 'ms-radio'
        }));
    }

    handleDemandComponentChange(event) {
        this.demandComponent = event.detail.value;
    }

    handleLoadBookings() {
        if (!this.selectedMilestoneId) {
            this.showToast('Warning', 'Please select a milestone', 'warning');
            return;
        }
        if (!this.demandComponent) {
            this.showToast('Warning', 'Please select the demand component', 'warning');
            return;
        }

        this.isLoading = true;
        getBookingsForMilestone({
            projectId: this.effectiveProjectId,
            towerId: this.selectedTowerId || null,
            masterPaymentScheduleId: this.selectedMilestoneId,
            demandComponent: this.demandComponent
        })
        .then(result => {
            this.bookings = result.map(b => ({
                ...b,
                isSelected: true
            }));
            this.currentStep = 3;
        })
        .catch(error => { this.showToast('Error', this.getErrorMessage(error), 'error'); })
        .finally(() => { this.isLoading = false; });
    }

    // For individual flow, go directly to step 3
    handleProceedIndividual() {
        const hasSelection = this.bookings.some(b => b.isSelected);
        if (!hasSelection) {
            this.showToast('Warning', 'Please select at least one booking', 'warning');
            return;
        }
        this.currentStep = 3;
    }

    // ============ STEP 3: BOOKING SELECTION ============

    handleSelectAll(event) {
        this.selectAll = event.target.checked;
        this.bookings = this.bookings.map(b => ({ ...b, isSelected: this.selectAll }));
    }

    handleBookingSelect(event) {
        const bookingId = event.currentTarget.dataset.id;
        this.bookings = this.bookings.map(b => {
            if (b.bookingId === bookingId) {
                return { ...b, isSelected: event.target.checked };
            }
            return b;
        });
        this.selectAll = this.bookings.every(b => b.isSelected);
    }

    handleGoToReview() {
        if (this.selectedCount === 0) {
            this.showToast('Warning', 'Please select at least one booking', 'warning');
            return;
        }
        this.currentStep = 4;
    }

    // ============ STEP 4: REVIEW & CONFIGURE ============

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
    }

    handleGracePeriodChange(event) {
        this.gracePeriodDays = event.detail.value;
    }

    handleInterestToggle(event) {
        this.includeInterest = event.target.checked;
    }

    handleNotesChange(event) {
        this.notes = event.detail.value;
    }

    handleRaiseDemands() {
        const demandAmount = this.selectedBookings.reduce(
            (total, booking) => total + (Number(booking.totalPending) || 0),
            0
        );
        if (demandAmount <= 0) {
            this.showToast('Cannot Raise Demand', 'Zero amount demand cannot be raised.', 'error');
            return;
        }

        this.currentStep = 5;
        this.isProcessing = true;

        const request = {
            projectId: this.effectiveProjectId,
            towerId: this.selectedTowerId || null,
            masterPaymentScheduleId: this.selectedMilestoneId,
            demandComponent: this.demandComponent,
            bookings: this.selectedBookings.map(b => ({
                bookingId: b.bookingId,
                demandAmount: b.totalPending,
                interestAmount: b.totalInterest,
                // Previously-demanded-but-unpaid amount from Step 3 — stored on the Demand so
                // Net_Demand_Amount__c (= Demand + Previous Dues + Interest) matches the preview.
                previousDues: b.previousMilestonesAmount || 0,
                scheduleIds: b.scheduleItems ? b.scheduleItems.filter(s => s.isSelected !== false).map(s => s.scheduleId) : [],
                // The schedule matching the milestone actually selected in Step 2 — Apex links
                // the resulting Demand's Payment_Schedule__c lookup to this specifically.
                currentMilestoneScheduleId: b.currentMilestoneScheduleId
            })),
            gracePeriodDays: this.gracePeriodDays,
            dueDateOffsetDays: this.dueDateOffsetDays,
            includeInterest: this.includeInterest,
            includePreviousDues: this.includePreviousDues,
            notes: this.notes,
            demandType: 'Bulk Demand'
        };

        createBulkDemands({ requestJson: JSON.stringify(request) })
            .then(result => {
                this.demandResult = result;

                // Send emails if template selected or autoSendEmail is enabled
                if ((this.selectedTemplateId || this.autoSendEmail) && result.success) {
                    const demandIds = result.results
                        .filter(r => r.success && r.demandId)
                        .map(r => r.demandId);

                    if (demandIds.length > 0) {
                        return sendBulkDemandEmails({
                            demandIds: demandIds,
                            templateId: this.selectedTemplateId
                        });
                    }
                }
            })
            .then(() => {
                this.currentStep = 6;
                const variant = this.demandResult.failureCount === 0 ? 'success' : 'warning';
                const msg = `${this.demandResult.successCount} of ${this.demandResult.totalProcessed} demands created successfully`;
                this.showToast(variant === 'success' ? 'Success' : 'Partial Success', msg, variant);
            })
            .catch(error => {
                this.demandResult = { success: false, errorMessage: this.getErrorMessage(error), results: [] };
                this.currentStep = 6;
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => { this.isProcessing = false; });
    }

    // ============ NAVIGATION ============

    handleBack() {
        if (this.currentStep > 1) {
            if (this.currentStep === 3 && this.isApartmentFlow) {
                this.currentStep = 2;
            } else if (this.currentStep === 3 && this.isIndividualFlow) {
                this.currentStep = 2;
            } else if (this.currentStep === 4) {
                this.currentStep = 3;
            } else {
                this.currentStep--;
            }
        }
    }

    // ============ UTILITIES ============

    formatCurrency(value) {
        if (value === null || value === undefined) return '₹0.00';
        return '₹' + value.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
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
        return 'Unknown error';
    }
}