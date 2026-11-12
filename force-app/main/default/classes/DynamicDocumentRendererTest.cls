/**
 * @description Test class for DynamicDocumentRenderer
 */
@isTest
private class DynamicDocumentRendererTest {

    @testSetup
    static void setup() {
        Account a = new Account(Name = 'Renderer Test Account');
        insert a;
    }

    @isTest
    static void renderDocument_blankTemplate_returnsEmpty() {
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument('', null, null);
        Test.stopTest();
        System.assertEquals('', html, 'Blank template should produce empty string');
    }

    @isTest
    static void renderDocument_simpleTemplate_rendersSections() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        String tmplJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'content' => 'Header for {!Name}',
                'showLogo' => false
            },
            'footer' => new Map<String, Object>{
                'content' => 'Footer',
                'showPageNumbers' => true,
                'pageNumberPosition' => 'right'
            },
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'content',  'content' => 'Hello {!Name}' },
                new Map<String, Object>{ 'type' => 'heading',  'content' => 'My Heading', 'level' => '2' },
                new Map<String, Object>{ 'type' => 'separator' },
                new Map<String, Object>{ 'type' => 'pageBreak' },
                new Map<String, Object>{
                    'type' => 'fieldGrid',
                    'gridColumns' => 2,
                    'fields' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Name', 'field' => 'Name' }
                    }
                }
            },
            'styles' => new Map<String, Object>{
                'fontFamily' => 'Arial',
                'fontSize' => '12px'
            }
        });

        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();

        System.assert(html.contains('Hello'), 'Content should be rendered');
        System.assert(html.contains('My Heading'), 'Heading should be rendered');
    }

    @isTest
    static void renderDocument_conditionalSectionsAndGridFields() {
        Account a = [SELECT Id, Phone FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'content',
                    'content' => 'Optional co-applicant details',
                    'showIfField' => 'Phone'
                },
                new Map<String, Object>{
                    'type' => 'fieldGrid',
                    'gridColumns' => 1,
                    'fields' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Name', 'field' => 'Name' },
                        new Map<String, Object>{
                            'label' => 'Optional phone',
                            'field' => 'Phone',
                            'showIfField' => 'Phone'
                        }
                    }
                }
            }
        });

        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        System.assert(!html.contains('Optional co-applicant details'));
        System.assert(!html.contains('Optional phone'));
        System.assert(html.contains('Renderer Test Account'));

        a.Phone = '555-0100';
        update a;
        html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');

        System.assert(html.contains('Optional co-applicant details'));
        System.assert(html.contains('Optional phone'));
    }

    @isTest
    static void renderDocument_gridAndTableSupportValueTemplatesAndIndianAmounts() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        a.AnnualRevenue = 15129485;
        update a;

        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'fieldGrid',
                    'gridColumns' => 1,
                    'fields' => new List<Object>{
                        new Map<String, Object>{
                            'label' => 'Buyer details',
                            'valueTemplate' => '{!Name} - {!AnnualRevenue}'
                        },
                        new Map<String, Object>{
                            'label' => 'Total',
                            'field' => 'AnnualRevenue',
                            'format' => 'INR'
                        }
                    }
                },
                new Map<String, Object>{
                    'type' => 'table',
                    'columns' => new List<Object>{
                        new Map<String, Object>{
                            'label' => 'Total',
                            'field' => 'AnnualRevenue',
                            'format' => 'INR'
                        }
                    }
                }
            }
        });

        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        System.assert(html.contains('Renderer Test Account - 15129485'));
        System.assertEquals(2, html.split('1,51,29,485').size() - 1);
    }

    @isTest
    static void renderDocument_bookingCoApplicantsUsesChildDataAndBookingAddress() {
        Project__c project = new Project__c(
            Name = 'Co-Applicant Renderer Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Status__c = 'Booked',
            Permanent_Address__c = 'Booking Permanent Address'
        );
        insert booking;

        Co_Applicant__c coApplicant = new Co_Applicant__c(
            Booking__c = booking.Id,
            Salutation__c = 'Mrs',
            Full_Name__c = 'Co Applicant',
            Relalation_Details__c = 'W/o',
            W_o_S_o_C_o_c__c = 'Applicant Spouse',
            Date_of_Birth__c = Date.today().addYears(-32),
            Permenent_Address__c = 'Co-Applicant Own Address',
            Aadhar_Number__c = '123412341234',
            PAN_Number__c = 'COAPP1234A'
        );
        // Occupation__c is set dynamically so the Co_Applicant__c field type can change.
        coApplicant.put('Occupation__c', 'Engineer');
        insert coApplicant;
        insert new Co_Applicant__c(
            Booking__c = booking.Id,
            Salutation__c = 'Mr',
            Full_Name__c = 'Second Co Applicant',
            S_o_D_o_W_o__c = 'S/o',
            W_o_S_o_C_o_c__c = 'Second Father'
        );

        String templateJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'content',
                    'content' => 'Borrowers: {!CO_APPLICANTS}<p>Co-applicant names: {!CO_APPLICANT_NAMES}</p>'
                        + '<p>Joint: First Applicant{!AND_CO_APPLICANT_NAMES}|</p>'
                }
            }
        });

        String html = DynamicDocumentRenderer.renderDocument(
            templateJson,
            booking.Id,
            'Booking__c'
        );

        System.assert(html.contains('Mrs. Co Applicant'));
        System.assert(html.contains('W/o. Applicant Spouse'));
        // relation read from the field the booking form fills
        System.assert(html.contains('Mr. Second Co Applicant, S/o. Second Father'), html);
        // Aadhaar / PAN start on a new line
        System.assert(html.contains('<span style="display:block;text-indent:0;font-weight:bold">(Aadhaar No. 123412341234'), html);
        // "&" only before the last name
        System.assert(html.contains('Joint: First Applicant, Mrs. Co Applicant &amp; Mr. Second Co Applicant|'), html);
        System.assert(html.contains('aged about 32 years'));
        System.assert(html.contains('Occupation: Engineer'));
        // own address when filled, the booking's address for the co-applicant without one
        System.assert(html.contains('Resident of Co-Applicant Own Address'), html);
        System.assert(html.contains('Resident of Booking Permanent Address'), html);
        System.assert(html.contains('Aadhaar No. 123412341234'));
        System.assert(html.contains('PAN No. COAPP1234A'));
        System.assert(html.contains('Co-applicant names: Mrs. Co Applicant, Mr. Second Co Applicant'));
        System.assert(!html.contains('123412341234, Mr Second Co Applicant'));
    }

    @isTest
    static void renderDocument_andCoApplicantNames_oneAndNone() {
        Project__c project = new Project__c(
            Name = 'Joint Names Renderer Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;
        Booking__c single = new Booking__c(Project__c = project.Id, Booking_Date__c = Date.today(), Status__c = 'Booked');
        Booking__c none = new Booking__c(Project__c = project.Id, Booking_Date__c = Date.today(), Status__c = 'Booked');
        insert new List<Booking__c>{ single, none };
        insert new Co_Applicant__c(Booking__c = single.Id, Salutation__c = 'Mrs', Full_Name__c = 'Only Co Applicant');

        String templateJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'content',
                    'content' => 'Joint: First Applicant{!AND_CO_APPLICANT_NAMES}|'
                }
            }
        });

        String one = DynamicDocumentRenderer.renderDocument(templateJson, single.Id, 'Booking__c');
       System.assert(one.contains('Joint: First Applicant &amp; Mrs. Only Co Applicant|'), one);
        String zero = DynamicDocumentRenderer.renderDocument(templateJson, none.Id, 'Booking__c');
      System.assert(zero.contains('Joint: First Applicant|'), zero);
    }

    @isTest
    static void renderDocument_coApplicantsNumberedAndWithoutAge() {
        Project__c project = new Project__c(
            Name = 'Co-Applicant Variants Project',
            Project_Type__c = 'Residential',
            Interest_Rate__c = 18
        );
        insert project;
        Booking__c booking = new Booking__c(
            Project__c = project.Id, Booking_Date__c = Date.today(), Status__c = 'Booked',
            Permanent_Address__c = 'Variant Address'
        );
        insert booking;
        insert new Co_Applicant__c(
            Booking__c = booking.Id, Salutation__c = 'Mr', Full_Name__c = 'First Co',
            S_o_D_o_W_o__c = 'S/o', W_o_S_o_C_o_c__c = 'Father One',
            Date_of_Birth__c = Date.today().addYears(-40)
        );
        insert new Co_Applicant__c(
            Booking__c = booking.Id, Salutation__c = 'Mrs', Full_Name__c = 'Second Co'
        );

        String numberedJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'content', 'content' => 'N:{!CO_APPLICANTS_NUMBERED}' }
            }
        });
        String numbered = DynamicDocumentRenderer.renderDocument(numberedJson, booking.Id, 'Booking__c');
        System.assert(numbered.contains('text-indent:0">2.</span><b>Mr. First Co, S/o. Father One</b>'), numbered);
        System.assert(numbered.contains('text-indent:0">3.</span><b>Mrs. Second Co</b>'), numbered);
        System.assert(numbered.contains('aged about 40 years'), numbered);
        System.assert(!numbered.contains('{!CO_APPLICANTS'), numbered);

        String noAgeJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'content', 'content' => 'A:{!CO_APPLICANTS_NO_AGE}|B:{!CO_APPLICANTS}' }
            }
        });
        String noAge = DynamicDocumentRenderer.renderDocument(noAgeJson, booking.Id, 'Booking__c');
        String partA = noAge.substringBetween('A:', '|B:');
        String partB = noAge.substringAfter('|B:');
        System.assert(!partA.contains('aged about'), partA);
        System.assert(partA.contains('<b>Mr. First Co, S/o. Father One</b>, Resident of Variant Address.'), partA);
        System.assert(partB.contains('aged about 40 years'), partB);
    }

    @isTest
    static void renderDocument_disabledEmptyFooter_isOmitted() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'footer' => new Map<String, Object>{
                'content' => '',
                'showPageNumbers' => false
            }
        });

        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');

        System.assert(!html.contains('border-top:1px solid #ccc'), 'An empty disabled footer should not render');
        System.assert(!html.contains('pagenumber'), 'An empty disabled footer should not render page numbers');
    }

    @isTest
    static void renderDocument_threeColumnHeader_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];

        String tmplJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'left'   => new Map<String, Object>{ 'type' => 'text',  'content' => 'Left' },
                'center' => new Map<String, Object>{ 'type' => 'text',  'content' => 'Center' },
                'right'  => new Map<String, Object>{ 'type' => 'image', 'logoUrl' => 'http://example.com/logo.png' }
            },
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'image',
                    'imageUrl' => 'http://example.com/section.png',
                    'imageCaption' => 'Caption'
                }
            }
        });

        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();

        System.assert(html.contains('Left'), 'Left col should render');
        System.assert(html.contains('Center'), 'Center col should render');
    }

    @isTest
    static void renderDocument_tableSection_missingConfig_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'table' }
            }
        });

        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();

        System.assert(html.contains('missing configuration'), 'Should warn on missing config');
    }

    @isTest
    static void renderDocument_legacyHeaderWithLogo_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'content' => 'Hi',
                'showLogo' => true,
                'logoUrl' => 'http://example.com/x.png',
                'logoPosition' => 'right',
                'fontSize' => '14px',
                'bold' => true,
                'textColor' => '#000'
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('img'), 'Should include image tag');
    }

    @isTest
    static void renderDocument_legacyHeaderWithLogoCenter_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'showLogo' => true,
                'logoUrl' => 'http://example.com/x.png',
                'logoPosition' => 'center'
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('center'), 'Should center logo');
    }

    @isTest
    static void renderDocument_tableSection_withRows_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        // Create child contacts
        Contact c1 = new Contact(LastName = 'C1', AccountId = a.Id);
        Contact c2 = new Contact(LastName = 'C2', AccountId = a.Id);
        insert new List<Contact>{c1, c2};

        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'table',
                    'title' => 'Contacts',
                    'childObject' => 'Contact',
                    'relationshipField' => 'AccountId',
                    'columns' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Name', 'field' => 'LastName' }
                    },
                    'orderBy' => 'LastName',
                    'maxRows' => 50,
                    'showRowNumbers' => true,
                    'alternateRowColors' => true,
                    'alternateRowBackground' => '#eee'
                }
            }
        });

        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('Contacts'), 'Title should be rendered');
        System.assert(html.contains('C1') || html.contains('C2'), 'Children should render');
    }

    @isTest
    static void renderDocument_tableSection_usesColumnLayoutOptions() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'table',
                    'tableLayout' => 'fixed',
                    'fontSize' => '10px',
                    'columns' => new List<Object>{
                        new Map<String, Object>{
                            'label' => 'Name',
                            'field' => 'Name',
                            'width' => '70%',
                            'align' => 'right'
                        },
                        new Map<String, Object>{
                            'label' => 'Industry',
                            'field' => 'Industry',
                            'width' => '30%'
                        }
                    }
                }
            }
        });

        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');

        System.assert(html.contains('table-layout:fixed;'), 'The table layout should be fixed');
        System.assert(html.contains('font-size:10px;'), 'The configured table font size should render');
        System.assert(html.contains('width:70%;'), 'The configured column width should render');
        System.assert(html.contains('text-align:right;'), 'The configured column alignment should render');
        System.assert(html.contains('Industry</th>'), 'The existing table columns should remain');
    }

    @isTest
    static void renderDocument_fieldGrid_usesConfiguredLabelWidth() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'fieldGrid',
                    'gridColumns' => 1,
                    'labelWidth' => 38,
                    'fields' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Account', 'field' => 'Name' }
                    }
                }
            }
        });

        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');

        System.assert(html.contains('width:38.00%;'), 'The configured label width should render');
        System.assert(html.contains('width:62.00%;'), 'The value column should fill the remaining width');
    }

    @isTest
    static void renderDocument_tableSection_noRecords_rendersEmpty() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'table',
                    'childObject' => 'Contact',
                    'relationshipField' => 'AccountId',
                    'columns' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Name', 'field' => 'LastName' }
                    }
                }
            }
        });

        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('No records found'), 'Should render no records msg');
    }

    @isTest
    static void renderDocument_imageSectionWithCaption_renders() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'image',
                    'imageUrl' => 'http://x.com/img.png',
                    'imageCaption' => 'My {!Name}'
                }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('img'), 'Should render image');
        System.assert(html.contains('font-style:italic'), 'Caption styled italic');
    }

    @isTest
    static void renderDocument_imageSection_blankUrl_skips() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'image', 'imageUrl' => '' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assertNotEquals(null, html);
    }

    @isTest
    static void renderDocument_fieldGridOddCount_closesRow() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'fieldGrid',
                    'columns' => 2,
                    'fields' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Name', 'field' => 'Name' },
                        new Map<String, Object>{ 'label' => 'Id', 'field' => 'Id' },
                        new Map<String, Object>{ 'label' => 'X', 'field' => 'Name' }
                    }
                }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('colspan'), 'Should close odd row with colspan');
    }

    @isTest
    static void renderDocument_unknownSectionType_returnsEmpty() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'unknownType' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assertNotEquals(null, html, 'Unknown type should not break');
    }

    @isTest
    static void renderDocument_mergeFieldsResolveTodayNow() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'content', 'content' => 'Today: {!TODAY} Now: {!NOW}' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(!html.contains('{!TODAY}'), 'TODAY token replaced');
        System.assert(!html.contains('{!NOW}'), 'NOW token replaced');
    }

    @isTest
    static void renderDocument_dynamicIndianAmountsAndArithmetic() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        a.AnnualRevenue = 15129485;
        a.NumberOfEmployees = 2215;
        update a;

        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'content',
                    'content' => '{!INR(AnnualRevenue)}|{!INR(MULTIPLY(NumberOfEmployees,7))}|' +
                        '{!INR(SUBTRACT(AnnualRevenue,MULTIPLY(NumberOfEmployees,7)))}|' +
                        '{!INR(ADD(NumberOfEmployees,7))}|{!SUBTRACT(AnnualRevenue,NumberOfEmployees)}'
                }
            }
        });

        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();

        System.assert(html.contains('1,51,29,485'), 'Currency should use Indian digit grouping');
        System.assert(html.contains('15,505'), 'Arithmetic functions should multiply dynamic values');
        System.assert(html.contains('1,51,13,980'), 'Nested arithmetic should resolve before formatting');
        System.assert(html.contains('2,222'), 'Arithmetic functions should add dynamic values');
        System.assert(html.contains('15127270'), 'Unformatted arithmetic merge fields should resolve directly');
        System.assert(!html.contains('{!'), 'All supported amount expressions should be resolved');
    }

    @isTest
    static void renderDocument_blankRecordId_renders() {
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'content', 'content' => 'Static text' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, null, 'Account');
        Test.stopTest();
        System.assert(html.contains('Static text'), 'Should render static');
    }

    @isTest
    static void renderDocument_withObjectPrefixInMergeField() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'content', 'content' => 'Name: {!Account.Name}' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(!html.contains('{!Account.Name}'), 'Object-prefixed merge should resolve');
    }

    @isTest
    static void renderDocument_separatorWithStyle() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{ 'type' => 'separator', 'style' => 'dashed' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('dashed'), 'Should use dashed style');
    }

    @isTest
    static void renderDocument_contentSectionWithStyles() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'content',
                    'content' => 'styled',
                    'backgroundColor' => '#eee',
                    'textAlign' => 'right',
                    'fontSize' => '20px',
                    'bold' => true,
                    'textColor' => '#f00'
                }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('font-weight:bold'), 'Should be bold');
    }

    @isTest
    static void renderDocument_headerColumnTextOnly() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        String tmplJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'left' => new Map<String, Object>{ 'type' => 'none' },
                'center' => null,
                'right' => new Map<String, Object>{ 'type' => 'text', 'content' => 'Right Side' }
            }
        });
        Test.startTest();
        String html = DynamicDocumentRenderer.renderDocument(tmplJson, a.Id, 'Account');
        Test.stopTest();
        System.assert(html.contains('Right Side'));
    }

    @isTest
    static void numberToWords_indianFormat() {
        System.assertEquals('Zero', DynamicDocumentRenderer.numberToWordsIndian(0));
        System.assertEquals('Five Hundred', DynamicDocumentRenderer.numberToWordsIndian(500));
        System.assertEquals('One Thousand', DynamicDocumentRenderer.numberToWordsIndian(1000));
        System.assertEquals('One Lakh Twenty Three Thousand Four Hundred Fifty Six',
            DynamicDocumentRenderer.numberToWordsIndian(123456));
        System.assertEquals('One Crore', DynamicDocumentRenderer.numberToWordsIndian(10000000));
        System.assertEquals('One Hundred and Fifty Paise',
            DynamicDocumentRenderer.numberToWordsIndian(100.50));
    }
}