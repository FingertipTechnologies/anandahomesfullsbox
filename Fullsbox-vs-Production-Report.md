# Fullsbox vs Production — Quote, Booking, PDFs and Project/Unit fields

Compared on 11 Nov 2026 by retrieving the same components from both orgs (read-only in production) and diffing them.
"Fullsbox" = FullSbox sandbox, "Production" = the live org.

> **Update, 11 Nov 2026 (later the same day):** the Drizzle work was deployed to production after this comparison was made. The sections below describe the orgs *before* that deployment. Now in production: the Drizzle cost sheet and booking form pages, the six logos, the Create Quote and Generate Cost Sheet screens, the co-applicant cards, 15 new fields (5 Unit, 5 Quote, 5 Project), and the Quote Sub total / Total Other Charges and Unit Floor Rise Charge formulas as in fullsbox. Production's booking flow was left unchanged.

## 1. Summary

- **Production cannot produce the Drizzle documents today.** The Drizzle cost sheet page, the Drizzle booking form page and the logos they use exist only in fullsbox.
- **Production's Drizzle quote total leaves out the Drizzle charges.** Lake Premium, East/North Facing, Floor Rise, Extra Car Parking, Piped Gas and Club House are not in production's Sub total formula, and five of the fields behind them do not exist there. Production has 838 Drizzle units.
- **Booking creation works in both, built differently.** Production: one flow that maps the quote, generates schedules and creates the booking-amount receipt. Fullsbox: a different flow that maps and generates schedules but creates no receipt.
- **The Create Booking form differs both ways.** Fullsbox has the new co-applicant cards, Occupation, Company and co-applicant address. Production has a Customer Bank Details section, Booking Account Name and a default Booking Amount that fullsbox does not.
- **Production is ahead in a few places**, so a straight copy from fullsbox would lose things: a Create Quote change for Custom payment schedules, 24 Booking fields, 6 Project fields and 9 Booking Source values.

Of the 50 code files compared: 23 identical, 19 different, 8 only in fullsbox, none only in production.

## 2. Create Quote (component + Apex)

| Item | Fullsbox | Production |
|---|---|---|
| `CreateQuote` screen | Shows different charge fields per project. The Drizzle: PLC, East/North Facing, Floor Rise, Lake Premium, Extra Car Parking, Gas Pipe Line, Club House. The Legacey: East Facing, Hi Rise, Meadow, Court Yard, Outer and the rest. | One set of charge fields for every project (the Legacey set). |
| Total calculation on screen | Adds gas pipe, club house, extra car parking, lake premium, floor rise and east/north facing. | Does not add them. |
| Custom payment type | Still loads the tower's master payment schedule before the next screen. | **Changed in production only:** custom schedules go straight to the next screen; a master schedule on the tower is not required. |
| `CreateQuoteController` (Apex) | Reads the extra unit fields (Piped Gas, Floor Rise Charge, Lake Premium, Extra Car Parking, PLC, East/North Facing, Club House). Master payment schedules: active rows only. | Does not read those fields. Takes all master schedule rows, active or not. |
| `CreateQuoteControllerTest`, helper, CSS | Identical | Identical |
| Lead "Create Quote" button | Identical | Identical |

Last changed: fullsbox 11 Nov 2026, production 21 Oct 2026.

## 3. Quote object fields

| Field | Fullsbox | Production |
|---|---|---|
| Club House, East/North Facing, Lake Premium, PLC, Gas Pipe line (`Piped_Gas__c`) | Exist | **Missing** |
| Swap For Booking (lookup to Booking) | Exists | Missing |
| Sub total (formula) | Legacey charges + East/North Facing, Lake Premium, Floor Rise, Extra Covered Car Parking, Piped Gas, Club House | Legacey charges only |
| Total Other Charges (formula) | Sub total minus Basic Price | Sum of the Legacey premiums + Amenities/Car Parking + Infrastructure |
| Project Company (formula) | Blanked out (returns empty) | Project's Company |
| Tower (label) | "Tower Name" | "Tower" |

Floor Rise and Extra Covered Car Parking Charges exist on the Quote in both orgs, but production's Sub total does not use them.

## 4. Create Booking

### Button and screen

| Item | Fullsbox | Production |
|---|---|---|
| Quote button for the dynamic form | `Create_Booking`, label "Create Booking" | `Create_Bookings`, label "Create Booking" |
| Old Aura booking screen as a button | Not on a button (the same action name now opens the dynamic form) | Still there as `Create_Booking`, label "Create Bookings" |
| `dynamicFormAction` (opens the form) | Identical | Identical |
| `dynamicFormModal` (the form itself) | New today: co-applicants as two-column cards, "Add Co Applicant", component's own two-column grid | Co-applicants as a sideways-scrolling table, "Add Row" |
| `DynamicFormExecutionController` (Apex) | Identical | Identical |

### Form configuration (data record)

| Item | Fullsbox ("Create Booking Form") | Production ("Create Booking") |
|---|---|---|
| Customer Bank Details section (Account Holder Name, Account Number, Bank Name, Branch, IFSC — all required) | **Missing** | Present |
| Booking Account Name (required) | Missing — the field does not exist in fullsbox | Present |
| Booking Amount default | None | Project's Booking Amount |
| Primary applicant: Occupation, Company Details | Present | Missing |
| Co-applicant: Occupation, Company Details, Complete Address | Present | Missing |
| Co-applicant field order | Follows the booking form PDF | Original order |
| Document upload slots (Aadhaar, PAN) | Same | Same |

### What runs after the booking is saved

| Item | Fullsbox | Production |
|---|---|---|
| Active flow | `Booking_Generate_Payment_Schedules` v2 | `Booking_After_Create_Handler` v4 (a v5 draft also exists) |
| Runs when | Project filled and schedules not yet created | Unit filled and Status = New |
| Copy quote values to booking | Yes | Yes |
| Generate payment schedules | Yes | Yes |
| **Create booking-amount receipt** | **No** | Yes |
| `Booking_After_Create_Handler` in fullsbox | v1, obsolete | — |
| Quote → Booking mapping lines | Same 8 lines | Same 8 lines |
| `FieldMapperInvocable` (Apex) | Identical | Identical |

### Apex

| Class | Fullsbox | Production |
|---|---|---|
| `PaymentScheduleGeneratorService` | Follows the master schedule's S No / Payment Percent when filled; skips bookings that already have schedules; falls back to the unit's tower | Uses Sequence / Percentage only |
| `BookingController` | `createBook` copies Sub total, GST and Total from the quote when the booking has none | Does not. Also reads `Tower_Name__c`, which fullsbox does not have |
| `CreateBooking` Aura screen | "Associated Project" input is active | Same input is commented out |

Master payment schedule data: production has 15 active rows on every Drizzle tower (A–F) and Legacey tower (T1–T12). Fullsbox has test data only (The Drizzle / TW1: 15 rows, The Legacey / Tower A: 5 rows).

## 5. Booking form PDF

| Item | Fullsbox | Production |
|---|---|---|
| `BookingForm_DJV` (Drizzle booking form) | Exists | **Missing** |
| `BookingForm_LEGACY` | Identical | Identical |
| `BookingFormController` | Adds Floor, Series, PLC, applicant and co-applicant Company, Total, Flat Booking Amount Payable, Balance Flat Amount, Loan Bank Name; applicant salutation from the form's field; flat type falls back to the quote | Older version without these |
| `BookingFormControllerTest` | One extra test | — |
| Logos: Ananda Home New, Bay Hills, Ozone, Poetree | Exist | **Missing** |
| Logos: Drizzle, Prosper | Real images (about 19 KB each) | 70-byte placeholders |
| Legacey header/footer images | Identical | Identical |

The Drizzle form also needs unit fields that production lacks: Series and PLC (section 7).

## 6. Quote PDF (cost sheet) and Send Mail

| Item | Fullsbox | Production |
|---|---|---|
| `COST_SHEET_TD` (Drizzle cost sheet) | Exists | **Missing** |
| `IndianAmount` component (used by the Drizzle sheet) | Exists | Missing |
| `COST_SHEET_TL` (Legacey cost sheet) | Identical | Identical |
| `CostSheetController` | Identical | Identical |
| `GenerateQuotePDF` screen | Identical layout | Identical layout |
| Preview for a Drizzle quote | Shows the Drizzle sheet | Screen points at a page that does not exist |
| Send Mail for a Drizzle quote | Sends the Drizzle sheet | Sends nothing ("not configured"), yet the screen says "Email Sent Successfully" |
| Send Mail result message | Shows the real result; error stays on screen | Always shows success |
| `QuoteController` + test | Drizzle branch added, one extra test | Legacey only |
| "Generate Cost Sheet" button | Identical | Identical |

## 7. Unit fields (`Plot__c`)

Fullsbox 158 custom fields, production 145.

**Only in fullsbox (13):**

| Field | Type | Used by |
|---|---|---|
| East/North Facing | Currency | Create Quote, quote total, mortgage agreement |
| Lake Premium | Currency | Create Quote, quote total |
| Extra Car Parking | Currency | Create Quote |
| PLC | Text(220) | Create Quote, booking form |
| Series | Text(50) | Booking form |
| Utility Area | Number(16,3) | Mortgage agreement of sale |
| External Wall Area, Internal Wall Area | Number(16,3) | Unit page |
| Wall Area, Plinth Area | Number | — |
| AGPA | Text(80) | — |
| Mortgaged to HMDA | Checkbox | — |
| Ownership Type | Picklist | — |

**Only in production:** none.

**Different:**

| Field | Fullsbox | Production |
|---|---|---|
| UDS (Sq yards.) | Number with 2 decimals | Number, no decimals |
| Floor Rise Charge (formula) | Rs. 25 per floor above the 4th: (floor − 4) × 25, else 0 | Built-up area × floor number |
| Tower/Block (formula) | Returns the text 'Test' | Tower's name |
| LL Share Name | Picklist (6 names) | Text |
| Share (picklist) | MHPL, LAND OWNER, Ananth, BTN, MA, Company | MHPL, LANDOWNER, Ananth, BTN, MA, BUILDER, LL-RECT, Company |
| Tower (picklist) | A–H plus Tower-1…10 | T1–T12 plus Tower-1…10 |
| Piped Gas (label) | "Gas Pipe line" | "Piped Gas" |

## 8. Project fields (`Project__c`)

Fullsbox 113 custom fields, production 114.

**Only in fullsbox (5):** Corpus Charge Per Sq.ft, Document Charges, Maintenance Month, Maintenance Per sq.ft per month, Stamp Duty Percentage.

**Only in production (6):** Demand Account Number, Demand Bank Branch, Demand Company Display Name, Demand Company Website, Demand IFSC Code, Demand Payee Name.

**Different:**

| Field | Fullsbox | Production |
|---|---|---|
| Company | Lookup to Account | Picklist (MAHENDRA ARTO LLP, MAHENDRA HOMES PVT LTD) |
| Location | Geolocation | Text(255) |
| Project Address | Text Area | Long Text Area |
| Total Units | Number | Roll-up summary |

## 9. Tower and Co-Applicant fields

| Object | Field | Fullsbox | Production |
|---|---|---|---|
| Tower (`Block__c`) | Survey Number | Exists (used by the Legacey sale deeds) | Missing |
| Co-Applicant | Occupation | Picklist (6 values) | Text |
| Co-Applicant | Mobile | Exists | Missing |
| Co-Applicant | Marital Status | Missing | Exists |
| Co-Applicant | First Name (label) | "First_Name" | "First Name" |

## 10. Booking fields (`Booking__c`)

Fullsbox 399 custom fields, production 407.

**Only in fullsbox (16):** Associated Project, Associated Unit, Balance Flat Amount, Booking Owner, Booking (lookup), Car Parking, Customer Service Executive, Director, Inspection/Project Person, lead1 (lookup to Contact), Lead (lookup to Lead), NOC Email Recipients, New Booking (Swapped), Booking Swapped From, Total Received Flat Amount, VP.

**Only in production (24):** Booking Account Name, Buyer & Address, Customer Payable (With TDS), Date of Allotment, Expected Date of Registration, Formula (two help-text fields), Handover User, Legal User, Loan User, Maintenance User, Net Receipt Amount, Possession User, Reservation User, Second Applicant Age, Swap to Unit Number, TPA Date, TPA Place, Total Amount Received, Total Receipt, Total TDS Balance, Total TDS Received, Tower Name, Unit Number.

**Different:**

| Field | Fullsbox | Production |
|---|---|---|
| Super Built Up Area | Currency | Number |
| Loan Account Number | Text(50) | Text Area |
| Total Refunded Amount | Currency | Roll-up summary |
| Agreement Cost (formula) | Blanked out (returns 0) | Total × Agreement Percentage |
| Project Name (formula) | Blanked out | Project's name |
| Project Company (formula) | Blanked out | Project's Company |
| Current Payable Balance (formula) | Outstanding Demand Amount | Total Demand Raised − Total Receipt Amount |
| Booking Source (picklist) | 7 values | Same 7 plus 9 more: CHANNEL PARTNER, CHAT BOT, CUSTOMER REFF, EOI, GAK GROUP, IVR, MAGIC BRICKS, PORTAL, RAMIREDDY MARAM |
| Status, Funding Type (picklists) | Same values, different order | — |
| Labels | "Total Flat Cost", "Total Payable Amount", "TDS", "Tower Name" | "Total Flat Cost (Inc. TDS)", "Total Payable Amount (Inc. GST, TDS)", "TDS (Calc.)", "Tower" |

Loan Bank Name is a picklist with the same values in both. Total Other Charges on the Booking now has the same formula in both.

## 11. If the Drizzle work is to go to production

Things that must travel together, in dependency order:

1. **Fields:** Unit — East/North Facing, Lake Premium, Extra Car Parking, PLC, Series; Quote — Club House, East/North Facing, Lake Premium, PLC, Piped Gas; then the Quote Sub total formula.
2. **Images:** the six logos.
3. **Pages and components:** `IndianAmount`, `COST_SHEET_TD`, `BookingForm_DJV`.
4. **Apex with tests:** `QuoteController`, `BookingFormController`, `CreateQuoteController`.
5. **Screens:** `CreateQuote` and `GenerateQuotePDF` — after merging in production's Custom-schedule fix, otherwise it is lost.
6. **Create Booking form:** `dynamicFormModal`, plus adding the five new fields to production's own configuration record (keeping its Customer Bank Details section). Co-Applicant Occupation is Text in production, so it would show as a text box unless the field type is changed too.

Decisions needed before that:

- **Quote Sub total / Total Other Charges:** changing these formulas changes totals on existing production quotes that have values in the Drizzle charge fields.
- **Unit Floor Rise Charge formula:** the two orgs calculate it completely differently.
- **Booking flow:** production's flow already does the mapping and the receipt; fullsbox's flow should not replace it.

## 12. Not compared

Page layouts, Lightning record pages, profiles and field permissions, validation rules, the sale deed and agreement pages, and record data other than the form configuration, mapping lines and master payment schedule counts above.
