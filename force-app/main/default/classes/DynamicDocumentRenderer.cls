/**
 * @description Renders a Document_Template__c JSON definition into HTML.
 * Resolves merge fields from the primary record, parent lookups,
 * and child relationship tables. Used by both the VF PDF page and
 * the LWC preview.
 *
 * Template JSON structure:
 * {
 *   "header":  { "content": "html", "showLogo": true, "logoPosition": "left" },
 *   "footer":  { "content": "html", "showPageNumbers": true },
 *   "sections": [
 *     { "type": "content",   "content": "html with {!Field__c}", "showIfField": "Field__c" },
 *     { "type": "table",     "title": "...", "childObject": "...",
 *       "relationshipField": "...", "columns": [{"label":"...","field":"..."}],
 *       "orderBy": "...", "maxRows": 50, "showRowNumbers": true },
 *     { "type": "separator" }
 *   ],
 *   "styles": { "fontFamily": "...", "fontSize": "12px", "primaryColor": "#333" }
 * }
 *
 * Table sections support two modes:
 *  - Child table:       childObject + relationshipField set -> one row per child record.
 *  - Main-record table: childObject blank -> exactly ONE row sourced from the main
 *    record's own fields (direct like Amount__c or lookup paths like Booking__r.Amount__c).
 */
public with sharing class DynamicDocumentRenderer {

    // ============================== PUBLIC ENTRY POINT ==============================

    /**
     * @description Render complete document HTML from template JSON
     * @param templateJsonStr The Template_JSON__c value
     * @param recordId The source record ID
     * @param objectApiName The object API name
     * @return Fully resolved HTML string
     */
    public static String renderDocument(String templateJsonStr, String recordId, String objectApiName) {
        if (String.isBlank(templateJsonStr)) return '';

        Map<String, Object> template = (Map<String, Object>) JSON.deserializeUntyped(templateJsonStr);

        // Resolve styles
        Map<String, Object> styles = template.containsKey('styles')
            ? (Map<String, Object>) template.get('styles')
            : new Map<String, Object>();

        String fontFamily = getStr(styles, 'fontFamily', 'Arial, Helvetica, sans-serif');
        String fontSize   = getStr(styles, 'fontSize', '12px');
        String primaryColor = getStr(styles, 'primaryColor', '#333333');
        // Match the designer preview's typography exactly (preview uses line-height 1.6 and
        // browser-default paragraph spacing). The in-app document view renders this as HTML in
        // the browser, so it looks identical to the preview. Overridable via styles.lineHeight.
        String lineHeight = getStr(styles, 'lineHeight', '1.6');

        // Fetch primary record with all accessible fields + referenced parent fields
        SObject record = null;
        if (String.isNotBlank(recordId)) {
            record = queryRecord(recordId, objectApiName, templateJsonStr);
        }

        StringBuilder html = new StringBuilder();
        html.append('<div style="font-family:' + fontFamily + ';font-size:' + fontSize +
                    ';color:' + primaryColor + ';line-height:' + lineHeight + ';">');

        // ---- HEADER ----
        if (template.containsKey('header')) {
            html.append(renderHeader((Map<String, Object>) template.get('header'), record, objectApiName));
        }

        // ---- SECTIONS ----
        if (template.containsKey('sections')) {
            List<Object> sections = (List<Object>) template.get('sections');
            for (Object sectionObj : sections) {
                Map<String, Object> section = (Map<String, Object>) sectionObj;
                html.append(renderSection(section, record, recordId, objectApiName));
            }
        }

        // ---- FOOTER ----
        if (template.containsKey('footer')) {
            html.append(renderFooter((Map<String, Object>) template.get('footer'), record, objectApiName));
        }

        html.append('</div>');
        return html.toString();
    }

    // ============================== HEADER ==============================

    private static String renderHeader(Map<String, Object> header, SObject record, String objectApiName) {
        StringBuilder html = new StringBuilder();

        // Global header styling
        String hdrFontSize = getStr(header, 'fontSize', '');
        Boolean hdrBold = header.get('bold') == true;
        String hdrColor = getStr(header, 'textColor', '');
        String hdrStyle = 'padding-bottom:10px;margin-bottom:16px;';
        if (String.isNotBlank(hdrFontSize)) hdrStyle += 'font-size:' + hdrFontSize + ';';
        if (hdrBold) hdrStyle += 'font-weight:bold;';
        if (String.isNotBlank(hdrColor)) hdrStyle += 'color:' + hdrColor + ';';

        // Check for new 3-column format (has left/center/right keys)
        if (header.containsKey('left') || header.containsKey('center') || header.containsKey('right')) {
            html.append('<div style="' + hdrStyle + '">');
            html.append('<table style="width:100%;border:none;border-collapse:collapse;"><tr>');

            Map<String, Object> leftCol = header.containsKey('left') ? (Map<String, Object>) header.get('left') : null;
            Map<String, Object> centerCol = header.containsKey('center') ? (Map<String, Object>) header.get('center') : null;
            Map<String, Object> rightCol = header.containsKey('right') ? (Map<String, Object>) header.get('right') : null;

            html.append('<td style="width:33%;text-align:left;vertical-align:top;border:none;padding:0 4px 0 0;">');
            html.append(renderHeaderColumn(leftCol, record, objectApiName));
            html.append('</td>');

            html.append('<td style="width:34%;text-align:center;vertical-align:top;border:none;padding:0 4px;">');
            html.append(renderHeaderColumn(centerCol, record, objectApiName));
            html.append('</td>');

            html.append('<td style="width:33%;text-align:right;vertical-align:top;border:none;padding:0 0 0 4px;">');
            html.append(renderHeaderColumn(rightCol, record, objectApiName));
            html.append('</td>');

            html.append('</tr></table>');
            html.append('</div>');
        } else {
            // Legacy single-column format
            html.append('<div style="' + hdrStyle + '">');

            Boolean showLogo = header.get('showLogo') == true;
            String logoUrl = getStr(header, 'logoUrl', '');
            String logoPosition = getStr(header, 'logoPosition', 'left');

            if (showLogo && String.isNotBlank(logoUrl)) {
                String align = logoPosition == 'center' ? 'center' : (logoPosition == 'right' ? 'right' : 'left');
                Integer size = readLogoSize(header);
                html.append('<div style="text-align:' + align + ';margin-bottom:8px;">');
                html.append('<img src="' + logoUrl + '" width="' + size + '"'
                    + ' style="width:' + size + 'px;height:auto;" />');
                html.append('</div>');
            }

            String content = getStr(header, 'content', '');
            if (String.isNotBlank(content)) {
                content = resolveMergeFields(content, record, objectApiName);
                html.append('<div>' + content + '</div>');
            }

            html.append('</div>');
        }

        return html.toString();
    }

    private static String renderHeaderColumn(Map<String, Object> col, SObject record, String objectApiName) {
        if (col == null) return '';
        String colType = getStr(col, 'type', 'none');
        if (colType == 'none') return '';

        StringBuilder html = new StringBuilder();
        if (colType == 'image') {
            String logoUrl = getStr(col, 'logoUrl', '');
            // Use the URL as-is: for PDF, the controller pre-converts to base64 data URIs;
            // for LWC preview, Salesforce URLs work directly in the browser.
            if (String.isNotBlank(logoUrl)) {
                Integer size = readLogoSize(col);
                // Width pins the box; height auto so Flying Saucer preserves aspect ratio.
                html.append('<img src="' + logoUrl + '" width="' + size + '"'
                    + ' style="width:' + size + 'px;height:auto;" />');
            }
        } else if (colType == 'text') {
            String content = getStr(col, 'content', '');
            if (String.isNotBlank(content)) {
                content = resolveMergeFields(content, record, objectApiName);
                html.append(content);
            }
        }
        return html.toString();
    }

    // ============================== FOOTER ==============================

    private static String renderFooter(Map<String, Object> footer, SObject record, String objectApiName) {
        String content = getStr(footer, 'content', '');
        Boolean showPageNumbers = footer.get('showPageNumbers') == true;
        if (String.isBlank(content) && !showPageNumbers) return '';

        StringBuilder html = new StringBuilder();
        String ftrFontSize = getStr(footer, 'fontSize', '10px');
        String ftrColor = getStr(footer, 'textColor', '#666666');
        html.append('<div style="border-top:1px solid #ccc;padding-top:10px;margin-top:20px;font-size:' +
                    ftrFontSize + ';color:' + ftrColor + ';">');

        if (String.isNotBlank(content)) {
            content = resolveMergeFields(content, record, objectApiName);
            html.append('<div>' + content + '</div>');
        }

        if (showPageNumbers) {
            String pageNumPos = getStr(footer, 'pageNumberPosition', 'center');
            html.append('<div style="text-align:' + pageNumPos + ';margin-top:4px;">Page <span class="pagenumber"/> of <span class="pagecount"/></div>');
        }

        html.append('</div>');
        return html.toString();
    }

    // ============================== SECTIONS ==============================

    private static String renderSection(Map<String, Object> section, SObject record,
                                         String recordId, String objectApiName) {
        String showIfField = getStr(section, 'showIfField', '');
        if (String.isNotBlank(showIfField) &&
            (record == null || String.isBlank(formatFieldValue(getFieldValue(record, showIfField))))) {
            return '';
        }

        String sectionType = getStr(section, 'type', 'content');

        if (sectionType == 'content') {
            return renderContentSection(section, record, objectApiName);
        } else if (sectionType == 'table') {
            return renderTableSection(section, record, recordId, objectApiName);
        } else if (sectionType == 'separator') {
            String style = getStr(section, 'style', 'solid');
            return '<hr style="border:none;border-top:1px ' + style + ' #ccc;margin:16px 0;" />';
        } else if (sectionType == 'heading') {
            return renderHeadingSection(section, record, objectApiName);
        } else if (sectionType == 'fieldGrid') {
            return renderFieldGridSection(section, record, objectApiName);
        } else if (sectionType == 'pageBreak') {
            return '<div style="page-break-after:always;"></div>';
        } else if (sectionType == 'image') {
            return renderImageSection(section, record, objectApiName);
        }

        return '';
    }

    // ---- CONTENT SECTION ----
    private static String renderContentSection(Map<String, Object> section, SObject record, String objectApiName) {
        String content = getStr(section, 'content', '');
        content = resolveMergeFields(content, record, objectApiName);

        // Section-level style overrides
        String bgColor = getStr(section, 'backgroundColor', 'transparent');
        String padding = getStr(section, 'padding', '8px 0');
        String textAlign = getStr(section, 'textAlign', 'left');
        String fontSize = getStr(section, 'fontSize', '');
        Boolean bold = section.get('bold') == true;
        String textColor = getStr(section, 'textColor', '');

        String style = 'background:' + bgColor + ';padding:' + padding + ';text-align:' + textAlign + ';';
        if (String.isNotBlank(fontSize)) style += 'font-size:' + fontSize + ';';
        if (bold) style += 'font-weight:bold;';
        if (String.isNotBlank(textColor)) style += 'color:' + textColor + ';';

        return '<div style="' + style + '">' + content + '</div>';
    }

    // ---- HEADING SECTION ----
    private static String renderHeadingSection(Map<String, Object> section, SObject record, String objectApiName) {
        String content = getStr(section, 'content', '');
        content = resolveMergeFields(content, record, objectApiName);
        String level = getStr(section, 'level', '2');
        String textAlign = getStr(section, 'textAlign', 'left');
        String textColor = getStr(section, 'textColor', '');

        String style = 'text-align:' + textAlign + ';margin:16px 0 8px 0;';
        if (String.isNotBlank(textColor)) style += 'color:' + textColor + ';';

        return '<h' + level + ' style="' + style + '">' + content + '</h' + level + '>';
    }

    // ---- FIELD GRID SECTION ----
    private static String renderFieldGridSection(Map<String, Object> section, SObject record, String objectApiName) {
        List<Object> fields = (List<Object>) section.get('fields');
        if (fields == null || fields.isEmpty()) return '';

        Integer cols = section.containsKey('gridColumns') ? Integer.valueOf(section.get('gridColumns')) :
                       (section.containsKey('columns') ? Integer.valueOf(section.get('columns')) : 2);
        String widthPct = String.valueOf(Math.floor(100 / cols)) + '%';
        String labelWidthPct = '15%';
        String valueWidthPct = widthPct;
        if (section.containsKey('labelWidth')) {
            Integer labelWidth = 38;
            try {
                labelWidth = Integer.valueOf(String.valueOf(section.get('labelWidth')));
            } catch (Exception e) {
                labelWidth = 38;
            }
            if (labelWidth < 20) labelWidth = 20;
            if (labelWidth > 60) labelWidth = 60;
            Decimal pairWidth = 100.0 / cols;
            Decimal labelWidthValue = (pairWidth * labelWidth) / 100;
            labelWidthPct = String.valueOf(labelWidthValue.setScale(2)) + '%';
            valueWidthPct = String.valueOf((pairWidth - labelWidthValue).setScale(2)) + '%';
        }
        String fontSize = getStr(section, 'fontSize', '');
        String borderColor = getStr(section, 'borderColor', '#eee');
        String labelBackground = getStr(section, 'labelBackground', '#f9f9f9');

        StringBuilder html = new StringBuilder();
        html.append('<table style="width:100%;border-collapse:collapse;margin:8px 0;');
        if (String.isNotBlank(fontSize)) html.append('font-size:' + fontSize + ';');
        html.append('">');

        Integer count = 0;
        for (Object fieldObj : fields) {
            Map<String, Object> field = (Map<String, Object>) fieldObj;
            String label = getStr(field, 'label', '');
            String fieldName = getStr(field, 'field', '');
            String showIfField = getStr(field, 'showIfField', '');

            if (String.isNotBlank(showIfField) &&
                (record == null || String.isBlank(formatFieldValue(getFieldValue(record, showIfField))))) {
                continue;
            }

            if (Math.mod(count, cols) == 0) html.append('<tr>');

            String value = '';
            String valueTemplate = getStr(field, 'valueTemplate', '');
            if (record != null && String.isNotBlank(valueTemplate)) {
                value = resolveMergeFields(valueTemplate, record, objectApiName);
            } else if (record != null && String.isNotBlank(fieldName)) {
                value = formatDisplayValue(
                    getFieldValue(record, fieldName),
                    getStr(field, 'format', '')
                );
            }

            html.append('<td style="padding:4px 8px;font-weight:bold;width:' + labelWidthPct +
                ';border:1px solid ' + borderColor + ';background:' + labelBackground + ';">' +
                label + '</td>');
            html.append('<td style="padding:4px 8px;width:' + valueWidthPct +
                ';border:1px solid ' + borderColor + ';">' + value + '</td>');

            count++;
            if (Math.mod(count, cols) == 0) html.append('</tr>');
        }

        if (count == 0) return '';

        // Close final row if needed
        if (Math.mod(count, cols) != 0) {
            Integer remaining = cols - Math.mod(count, cols);
            for (Integer i = 0; i < remaining; i++) {
                html.append('<td colspan="2" style="border:1px solid #eee;">&nbsp;</td>');
            }
            html.append('</tr>');
        }

        html.append('</table>');
        return html.toString();
    }

    // ---- IMAGE SECTION ----
    private static String renderImageSection(Map<String, Object> section, SObject record, String objectApiName) {
        String imageUrl = getStr(section, 'imageUrl', '');
        if (String.isNotBlank(imageUrl)) {
            imageUrl = resolveMergeFields(imageUrl, record, objectApiName);
        }
        if (String.isBlank(imageUrl)) return '';

        String textAlign = getStr(section, 'textAlign', 'center');
        String maxWidth = getStr(section, 'imageMaxWidth', '100%');
        String maxHeight = getStr(section, 'imageMaxHeight', 'auto');
        String caption = getStr(section, 'imageCaption', '');
        if (String.isNotBlank(caption)) {
            caption = resolveMergeFields(caption, record, objectApiName);
        }

        // Image URL is used as-is: for PDF, the controller pre-converts to base64 data URIs;
        // for LWC preview, Salesforce URLs work directly in the browser.

        StringBuilder html = new StringBuilder();
        html.append('<div style="text-align:' + textAlign + ';margin:12px 0;">');
        String dimAttrs = '';
        Integer hPx = pxToInt(maxHeight);
        Integer wPx = pxToInt(maxWidth);
        if (hPx != null) dimAttrs += ' height="' + hPx + '"';
        if (wPx != null) dimAttrs += ' width="' + wPx + '"';
        html.append('<img src="' + imageUrl + '"' + dimAttrs + ' />');
        if (String.isNotBlank(caption)) {
            html.append('<div style="font-size:10px;color:#666;margin-top:4px;font-style:italic;">' + caption + '</div>');
        }
        html.append('</div>');
        return html.toString();
    }

    // ---- TABLE SECTION (Child / Related Records OR Main-Record single row) ----
    // Two modes:
    //  1. Child table: childObject + relationshipField set -> one row per child record.
    //  2. Main-record table: childObject blank -> exactly ONE row whose values come
    //     from the main record itself. Column fields may be direct (Amount__c) or
    //     lookup paths (Booking__r.Amount__c); both resolve via getFieldValue and
    //     are already included in the main record query (all accessible fields +
    //     "field":"Rel.Field" paths scanned by addReferencedParentFields).
    private static String renderTableSection(Map<String, Object> section, SObject record,
                                              String recordId, String objectApiName) {
        String title = getStr(section, 'title', '');
        String childObject = getStr(section, 'childObject', '');
        String relationshipField = getStr(section, 'relationshipField', '');
        Integer maxRows = section.containsKey('maxRows') ? Integer.valueOf(section.get('maxRows')) : 50;
        String orderBy = getStr(section, 'orderBy', '');
        Boolean showRowNumbers = section.get('showRowNumbers') == true;
        List<Object> columns = (List<Object>) section.get('columns');

        // Blank childObject = main-record table (1 row from the parent record itself)
        Boolean isMainRecordTable = String.isBlank(childObject);

        if (columns == null || columns.isEmpty()) {
            return '<p style="color:red;">Table section missing configuration.</p>';
        }
        if (!isMainRecordTable && String.isBlank(relationshipField)) {
            return '<p style="color:red;">Table section missing configuration.</p>';
        }

        // Build column list
        List<String> fieldNames = new List<String>();
        List<String> columnLabels = new List<String>();
        for (Object colObj : columns) {
            Map<String, Object> col = (Map<String, Object>) colObj;
            fieldNames.add(getStr(col, 'field', 'Name'));
            columnLabels.add(getStr(col, 'label', ''));
        }

        // Rows: child records, or the main record itself as a single row
        List<SObject> children;
        if (isMainRecordTable) {
            children = (record != null) ? new List<SObject>{ record } : new List<SObject>();
        } else {
            children = queryChildRecords(
                childObject, relationshipField, recordId, fieldNames, orderBy, maxRows
            );
        }

        // Table styles
        String headerBg = getStr(section, 'headerBackground', '#f5f5f5');
        String headerColor = getStr(section, 'headerColor', '#333');
        String borderColor = getStr(section, 'borderColor', '#ddd');
        String cellPadding = getStr(section, 'cellPadding', '4px 8px');
        String headerPadding = getStr(section, 'headerPadding', '6px 8px');
        String fontSize = getStr(section, 'fontSize', '');
        String rowNumberLabel = getStr(section, 'rowNumberLabel', 'Sl. No');

        StringBuilder html = new StringBuilder();

        if (String.isNotBlank(title)) {
            html.append('<h3 style="margin:16px 0 6px 0;">' + title + '</h3>');
        }

        html.append('<table style="width:100%;border-collapse:collapse;margin-bottom:12px;');
        if (getStr(section, 'tableLayout', '') == 'fixed') html.append('table-layout:fixed;');
        if (String.isNotBlank(fontSize)) html.append('font-size:' + fontSize + ';');
        html.append('">');

        // Header row
        html.append('<thead><tr>');
        if (showRowNumbers) {
            html.append('<th style="background:' + headerBg + ';color:' + headerColor +
                        ';border:1px solid ' + borderColor + ';padding:' + headerPadding +
                        ';text-align:center;">' + rowNumberLabel + '</th>');
        }
        for (Integer i = 0; i < columnLabels.size(); i++) {
            Map<String, Object> col = (Map<String, Object>) columns[i];
            String width = getTableColumnWidth(col);
            String alignment = getTableColumnAlignment(col, 'left');
            html.append('<th style="background:' + headerBg + ';color:' + headerColor +
                        ';border:1px solid ' + borderColor + ';padding:' + headerPadding +
                        ';text-align:' + alignment + ';' + (String.isNotBlank(width) ? 'width:' + width + ';' : '') +
                        'word-wrap:break-word;">' + columnLabels[i] + '</th>');
        }
        html.append('</tr></thead>');

        // Data rows
        html.append('<tbody>');
        if (children.isEmpty()) {
            Integer colSpan = columnLabels.size() + (showRowNumbers ? 1 : 0);
            html.append('<tr><td colspan="' + colSpan + '" style="border:1px solid ' + borderColor +
                        ';padding:8px;text-align:center;color:#999;">No records found</td></tr>');
        } else {
            Boolean alternateRowColors = section.get('alternateRowColors') == true;
            String altRowBg = getStr(section, 'alternateRowBackground', '#f9f9f9');
            Integer rowNum = 0;
            for (SObject child : children) {
                rowNum++;
                String rowBg = (alternateRowColors && Math.mod(rowNum, 2) == 0) ? altRowBg : 'transparent';
                html.append('<tr style="background:' + rowBg + ';">');
                if (showRowNumbers) {
                    html.append('<td style="border:1px solid ' + borderColor +
                                ';padding:' + cellPadding + ';text-align:center;">' + rowNum + '</td>');
                }
                for (Integer i = 0; i < fieldNames.size(); i++) {
                    String fName = fieldNames[i];
                    Object val = getFieldValue(child, fName);
                    Map<String, Object> col = (Map<String, Object>) columns[i];
                    String display = formatDisplayValue(val, getStr(col, 'format', ''));
                    String width = getTableColumnWidth(col);
                    String alignment = getTableColumnAlignment(col, 'left');
                    html.append('<td style="border:1px solid ' + borderColor +
                                ';padding:' + cellPadding + ';text-align:' + alignment + ';' +
                                (String.isNotBlank(width) ? 'width:' + width + ';' : '') +
                                'word-wrap:break-word;">' + display + '</td>');
                }
                html.append('</tr>');
            }
        }
        html.append('</tbody>');

        // ---- TOTALS ROW ----
        // Shown when "Show Totals" is on, or when any column has an aggregate configured.
        // For a main-record table the aggregates run over its single row (sum/min/max =
        // the value itself, count = 1); 'parent' still reads from the main record.
        Boolean anyAggregate = false;
        for (Object colObj : columns) {
            String agg = getStr((Map<String, Object>) colObj, 'total', 'none');
            if (String.isNotBlank(agg) && agg != 'none') { anyAggregate = true; break; }
        }
        if (section.get('showTotals') == true || anyAggregate) {
            String totalsLabel = getStr(section, 'totalsLabel', 'Total');
            html.append('<tfoot><tr style="font-weight:bold;background:' + headerBg + ';">');
            Boolean labelPlaced = false;
            if (showRowNumbers) {
                html.append('<td style="border:1px solid ' + borderColor +
                            ';padding:6px 8px;text-align:center;">' + totalsLabel + '</td>');
                labelPlaced = true;
            }
            for (Integer ci = 0; ci < fieldNames.size(); ci++) {
                Map<String, Object> col = (Map<String, Object>) columns[ci];
                String agg = getStr(col, 'total', 'none');
                String cellVal = '';
                if (agg == 'parent') {
                    String pf = getStr(col, 'totalParentField', '');
                    Object pv = (record != null && String.isNotBlank(pf)) ? getFieldValue(record, pf) : null;
                    cellVal = formatDisplayValue(pv, getStr(col, 'format', ''));
                } else if (agg == 'sum' || agg == 'count' || agg == 'average' || agg == 'min' || agg == 'max') {
                    cellVal = computeAggregate(children, fieldNames[ci], agg);
                    if (String.isNotBlank(cellVal) && getStr(col, 'format', '').equalsIgnoreCase('INR')) {
                        cellVal = formatIndianAmount(Decimal.valueOf(cellVal));
                    }
                } else if (!labelPlaced) {
                    // No aggregate for this column — use the first such cell to carry the label.
                    cellVal = totalsLabel;
                    labelPlaced = true;
                }
                html.append('<td style="border:1px solid ' + borderColor +
                            ';padding:6px 8px;">' + cellVal + '</td>');
            }
            html.append('</tr></tfoot>');
        }

        html.append('</table>');

        return html.toString();
    }

    // ============================== MERGE FIELD RESOLUTION ==============================

    private static String resolveMergeFields(String content, SObject record, String objectApiName) {
        if (record == null || String.isBlank(content)) return content;

        content = content.replace('{!TODAY}', formatFieldValue(Date.today()));
        content = content.replace('{!NOW}', Datetime.now().format('dd/MM/yyyy HH:mm'));
        content = resolveCoApplicantDetails(content, record, objectApiName);
        content = resolveCoApplicantNames(content, record, objectApiName);
        content = resolveAndCoApplicantNames(content, record, objectApiName);
        content = resolveAmountFunctions(content, record, objectApiName);

        // ---- Function: {!INWORDS(Field__c)} -> the field's numeric value in words ----
        // (parentheses keep this from matching the plain {!Field} pattern below)
        Pattern fnP = Pattern.compile('(?i)\\{!\\s*INWORDS\\s*\\(\\s*([A-Za-z0-9_.]+)\\s*\\)\\s*\\}');
        Matcher fnM = fnP.matcher(content);
        Map<String, String> fnReplacements = new Map<String, String>();
        while (fnM.find()) {
            String fullMatch = fnM.group(0);
            String fieldPath = fnM.group(1);
            if (fieldPath.contains('.') && !fieldPath.contains('__r.')) {
                String prefix = fieldPath.substringBefore('.');
                if (prefix.equalsIgnoreCase(objectApiName)) fieldPath = fieldPath.substringAfter('.');
            }
            Object val = getFieldValue(record, fieldPath);
            String words = '';
            if (val != null) {
                try { words = numberToWordsIndian(Decimal.valueOf(String.valueOf(val))); }
                catch (Exception e) { words = ''; }
            }
            fnReplacements.put(fullMatch, words);
        }
        for (String key : fnReplacements.keySet()) {
            content = content.replace(key, fnReplacements.get(key));
        }

        // ---- Function: {!DATEWORDS(Date_Field__c)} -> "19th day of November, 2026" ----
        if (content.containsIgnoreCase('DATEWORDS')) {
            Matcher dwM = Pattern.compile(
                '(?i)\\{!\\s*DATEWORDS\\s*\\(\\s*([A-Za-z0-9_.]+)\\s*\\)\\s*\\}'
            ).matcher(content);
            Map<String, String> dwReplacements = new Map<String, String>();
            while (dwM.find()) {
                String dwPath = dwM.group(1);
                if (dwPath.contains('.') && !dwPath.contains('__r.')
                    && dwPath.substringBefore('.').equalsIgnoreCase(objectApiName)) {
                    dwPath = dwPath.substringAfter('.');
                }
                dwReplacements.put(dwM.group(0), dateInWords(getFieldValue(record, dwPath)));
            }
            for (String key : dwReplacements.keySet()) {
                content = content.replace(key, dwReplacements.get(key));
            }
        }

        // Pattern: {!FieldName__c} or {!Object__c.Field__c} or {!Parent__r.Field__c}
        Pattern p = Pattern.compile('\\{!([A-Za-z0-9_.]+)\\}');
        Matcher m = p.matcher(content);

        Map<String, String> replacements = new Map<String, String>();
        while (m.find()) {
            String fullMatch = m.group(0);
            String fieldPath = m.group(1);

            // Remove object prefix if present  e.g. {!Booking__c.Name} -> Name
            if (fieldPath.contains('.') && !fieldPath.contains('__r.')) {
                String prefix = fieldPath.substringBefore('.');
                // If prefix matches the object api name, strip it
                if (prefix.equalsIgnoreCase(objectApiName)) {
                    fieldPath = fieldPath.substringAfter('.');
                }
            }

            Object val = getFieldValue(record, fieldPath);
            replacements.put(fullMatch, formatFieldValue(val));
        }

        for (String key : replacements.keySet()) {
            content = content.replace(key, replacements.get(key));
        }

        return content;
    }

    /**
     * A date as the agreements write it: "19th day of November, 2026". A blank date gives the
     * line to fill by hand: "________ day of ______________, 20____".
     */
    @TestVisible
    private static String dateInWords(Object value) {
        Date d;
        if (value instanceof Date) {
            d = (Date) value;
        } else if (value instanceof Datetime) {
            d = ((Datetime) value).date();
        }
        if (d == null) {
            return '________ day of ______________, 20____';
        }
        Integer day = d.day();
        Integer lastDigit = Math.mod(day, 10);
        String suffix = (day >= 11 && day <= 13) ? 'th'
            : lastDigit == 1 ? 'st' : lastDigit == 2 ? 'nd' : lastDigit == 3 ? 'rd' : 'th';
        List<String> months = new List<String>{
            'January', 'February', 'March', 'April', 'May', 'June', 'July',
            'August', 'September', 'October', 'November', 'December'
        };
        return day + suffix + ' day of ' + months[d.month() - 1] + ', ' + d.year();
    }

    private static String resolveCoApplicantDetails(
        String content, SObject record, String objectApiName
    ) {
        if (String.isBlank(content) || record == null
            || !'Booking__c'.equalsIgnoreCase(objectApiName)
            || !content.contains('{!CO_APPLICANTS')) {
            return content;
        }

        if (content.contains('{!CO_APPLICANTS}')) {
            content = content.replace(
                '{!CO_APPLICANTS}', buildCoApplicantParagraphs(record, true, false));
        }
        // numbered 2., 3., ... - the first applicant is "1." in the template
        if (content.contains('{!CO_APPLICANTS_NUMBERED}')) {
            content = content.replace(
                '{!CO_APPLICANTS_NUMBERED}', buildCoApplicantParagraphs(record, true, true));
        }
        // without "aged about N years"
        if (content.contains('{!CO_APPLICANTS_NO_AGE}')) {
            content = content.replace(
                '{!CO_APPLICANTS_NO_AGE}', buildCoApplicantParagraphs(record, false, false));
        }
        return content;
    }

    private static String buildCoApplicantParagraphs(
        SObject record, Boolean includeAge, Boolean numbered
    ) {
        List<String> renderedApplicants = new List<String>();
        Integer applicantNumber = 1;
        String permanentAddress = escapeHtmlValue(record.get('Permanent_Address__c'));
        for (Co_Applicant__c applicant : [
            SELECT Salutation__c, Full_Name__c, Relalation_Details__c, S_o_D_o_W_o__c,
                   W_o_S_o_C_o_c__c, Date_of_Birth__c, Occupation__c,
                   Aadhar_Number__c, PAN_Number__c, Permenent_Address__c
            FROM Co_Applicant__c
            WHERE Booking__c = :record.Id
            ORDER BY CreatedDate ASC
        ]) {
            List<String> details = new List<String>();
            List<String> heading = new List<String>();
            String name = coApplicantDisplayName(applicant);
            if (String.isNotBlank(name)) {
                heading.add(name);
            }

            // S_o_D_o_W_o__c is the field in use (the booking form fills it);
            // Relalation_Details__c is the older field, read only when the first is blank.
            String relationType = String.isNotBlank(applicant.S_o_D_o_W_o__c)
                ? applicant.S_o_D_o_W_o__c : applicant.Relalation_Details__c;
            if (String.isNotBlank(applicant.W_o_S_o_C_o_c__c)) {
                heading.add(joinDisplayValues(withFullStop(relationType), applicant.W_o_S_o_C_o_c__c));
            }
            if (!heading.isEmpty()) {
                details.add('<b>' + String.join(heading, ', ') + '</b>');
            }
            if (includeAge && applicant.Date_of_Birth__c != null) {
                details.add(
                    'aged about ' + calculateAge(applicant.Date_of_Birth__c) + ' years'
                );
            }
            if (String.isNotBlank(applicant.Occupation__c)) {
                details.add('Occupation: ' + escapeHtmlValue(applicant.Occupation__c));
            }
            // The co-applicant's own permanent address; the booking's only when theirs is blank.
            String applicantAddress = String.isNotBlank(applicant.Permenent_Address__c)
                ? escapeHtmlValue(applicant.Permenent_Address__c) : permanentAddress;
            details.add('Resident of ' + applicantAddress);
            // Aadhaar and PAN always start on a new line. A block span, not <br/>: the PDF engine
            // stretches (justifies) the short line that ends at a <br/>.
            applicantNumber++;
            String opening = numbered
                ? '<p style="text-align:justify;margin-left:36pt;text-indent:-22.5pt">'
                    + '<span style="display:inline-block;width:22.5pt;text-indent:0">'
                    + applicantNumber + '.</span>'
                : '<p style="text-align:justify">';
            renderedApplicants.add(
                opening + String.join(details, ', ') + '.'
                + '<span style="display:block;text-indent:0;font-weight:bold">(Aadhaar No. '
                + escapeHtmlValue(applicant.Aadhar_Number__c)
                + ' &amp; PAN No. ' + escapeHtmlValue(applicant.PAN_Number__c) + ')</span></p>'
            );
        }

        return String.join(renderedApplicants, '');
    }

    private static String resolveCoApplicantNames(
        String content, SObject record, String objectApiName
    ) {
        if (String.isBlank(content) || record == null
            || !'Booking__c'.equalsIgnoreCase(objectApiName)
            || !content.contains('{!CO_APPLICANT_NAMES}')) {
            return content;
        }

        List<String> names = new List<String>();
        for (Co_Applicant__c applicant : [
            SELECT Salutation__c, Full_Name__c
            FROM Co_Applicant__c
            WHERE Booking__c = :record.Id
            ORDER BY CreatedDate ASC
        ]) {
            String name = coApplicantDisplayName(applicant);
            if (String.isNotBlank(name)) {
                names.add(name);
            }
        }

        return content.replace('{!CO_APPLICANT_NAMES}', String.join(names, ', '));
    }

    /**
     * {!AND_CO_APPLICANT_NAMES} continues the first applicant's name: nothing when there is no
     * co-applicant, " &amp; B" for one, ", B, C &amp; D" for several ("&" only before the last name).
     */
    private static String resolveAndCoApplicantNames(
        String content, SObject record, String objectApiName
    ) {
        if (String.isBlank(content) || record == null
            || !'Booking__c'.equalsIgnoreCase(objectApiName)
            || !content.contains('{!AND_CO_APPLICANT_NAMES}')) {
            return content;
        }

        List<String> names = new List<String>();
        for (Co_Applicant__c applicant : [
            SELECT Salutation__c, Full_Name__c
            FROM Co_Applicant__c
            WHERE Booking__c = :record.Id
            ORDER BY CreatedDate ASC
        ]) {
            String name = coApplicantDisplayName(applicant);
            if (String.isNotBlank(name)) {
                names.add(name);
            }
        }

        String joined = '';
        for (Integer i = 0; i < names.size(); i++) {
            joined += (i == names.size() - 1 ? ' &amp; ' : ', ') + names[i];
        }
        return content.replace('{!AND_CO_APPLICANT_NAMES}', joined);
    }

    private static String coApplicantDisplayName(Co_Applicant__c applicant) {
        return joinDisplayValues(withFullStop(applicant.Salutation__c), applicant.Full_Name__c);
    }

    /** "Mr" -> "Mr.", "S/o" -> "S/o." (values that already end with a full stop are left alone). */
    private static String withFullStop(String value) {
        if (String.isBlank(value)) return value;
        String trimmed = value.trim();
        return trimmed.endsWith('.') ? trimmed : trimmed + '.';
    }

    private static String joinDisplayValues(String firstValue, String secondValue) {
        List<String> values = new List<String>();
        if (String.isNotBlank(firstValue)) values.add(escapeHtmlValue(firstValue));
        if (String.isNotBlank(secondValue)) values.add(escapeHtmlValue(secondValue));
        return String.join(values, ' ');
    }

    private static String escapeHtmlValue(Object value) {
        if (value == null) return '';
        return String.valueOf(value)
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }

    private static Integer calculateAge(Date dateOfBirth) {
        Date today = Date.today();
        Integer age = today.year() - dateOfBirth.year();
        if (today.month() < dateOfBirth.month()
            || (today.month() == dateOfBirth.month() && today.day() < dateOfBirth.day())) {
            age--;
        }
        return age;
    }

    private static String resolveAmountFunctions(String content, SObject record, String objectApiName) {
        content = replaceArithmeticFunction(content, 'MULTIPLY', record, objectApiName);
        content = replaceArithmeticFunction(content, 'ADD', record, objectApiName);
        content = replaceArithmeticFunction(content, 'SUBTRACT', record, objectApiName);

        Pattern amountPattern = Pattern.compile('(?i)\\{!\\s*INR\\s*\\(\\s*([A-Za-z0-9_.-]*)\\s*\\)\\s*\\}');
        Matcher amountMatcher = amountPattern.matcher(content);
        Map<String, String> replacements = new Map<String, String>();
        while (amountMatcher.find()) {
            Decimal amount = getNumericMergeValue(amountMatcher.group(1), record, objectApiName);
            replacements.put(amountMatcher.group(0), formatIndianAmount(amount));
        }
        for (String token : replacements.keySet()) {
            content = content.replace(token, replacements.get(token));
        }

        Pattern rawResultPattern = Pattern.compile('\\{!\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\}');
        Matcher rawResultMatcher = rawResultPattern.matcher(content);
        Map<String, String> rawResultReplacements = new Map<String, String>();
        while (rawResultMatcher.find()) {
            rawResultReplacements.put(rawResultMatcher.group(0), rawResultMatcher.group(1));
        }
        for (String token : rawResultReplacements.keySet()) {
            content = content.replace(token, rawResultReplacements.get(token));
        }
        return content.replace('{!}', '');
    }

    private static String replaceArithmeticFunction(String content, String functionName,
                                                     SObject record, String objectApiName) {
        Pattern functionPattern = Pattern.compile(
            '(?i)' + functionName + '\\s*\\(\\s*([A-Za-z0-9_.-]*)\\s*,\\s*([A-Za-z0-9_.-]*)\\s*\\)'
        );
        Matcher functionMatcher = functionPattern.matcher(content);
        Map<String, String> replacements = new Map<String, String>();
        while (functionMatcher.find()) {
            Decimal left = getNumericMergeValue(functionMatcher.group(1), record, objectApiName);
            Decimal right = getNumericMergeValue(functionMatcher.group(2), record, objectApiName);
            Decimal result;
            if (left != null && right != null) {
                if (functionName == 'MULTIPLY') result = left * right;
                else if (functionName == 'ADD') result = left + right;
                else result = left - right;
            }
            replacements.put(functionMatcher.group(0), formatNumber(result));
        }
        for (String token : replacements.keySet()) {
            content = content.replace(token, replacements.get(token));
        }
        return content;
    }

    private static Decimal getNumericMergeValue(String valueOrField, SObject record, String objectApiName) {
        if (String.isBlank(valueOrField)) return null;
        String operand = valueOrField.trim();
        if (Pattern.matches('^-?\\d+(?:\\.\\d+)?$', operand)) {
            return Decimal.valueOf(operand);
        }

        if (operand.contains('.') && !operand.contains('__r.')) {
            String prefix = operand.substringBefore('.');
            if (prefix.equalsIgnoreCase(objectApiName)) operand = operand.substringAfter('.');
        }

        Object value = getFieldValue(record, operand);
        if (value instanceof Decimal) return (Decimal) value;
        if (value instanceof Integer || value instanceof Long || value instanceof Double) {
            return Decimal.valueOf(String.valueOf(value));
        }
        return null;
    }

    private static String formatIndianAmount(Decimal amount) {
        if (amount == null) return '';
        Boolean negative = amount < 0;
        String raw = formatNumber(amount.abs());
        List<String> parts = raw.split('\\.');
        String integerPart = parts[0];
        Integer position = integerPart.length() - 3;
        String grouped = integerPart.substring(Math.max(0, position));
        while (position > 0) {
            Integer start = Math.max(0, position - 2);
            grouped = integerPart.substring(start, position) + ',' + grouped;
            position = start;
        }
        if (parts.size() > 1) grouped += '.' + parts[1];
        return (negative ? '-' : '') + grouped;
    }

    // ============================== QUERY HELPERS ==============================

    private static SObject queryRecord(String recordId, String objectApiName, String templateJson) {
        if (String.isBlank(objectApiName)) {
            objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
        }

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        if (sType == null) return null;

        Map<String, Schema.SObjectField> fieldMap = sType.getDescribe().fields.getMap();
        // Do NOT pre-populate with 'Id' — fieldMap.keySet() returns lowercase 'id'
        // and Apex Set is case-sensitive, so both 'Id' and 'id' would be added,
        // causing SOQL "Duplicate field selected" error.
        Set<String> fieldSet = new Set<String>();

        for (String fName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fName).getDescribe();
            if (dfr.isAccessible()) {
                // Skip compound fields (ADDRESS, LOCATION) as they cannot be queried directly
                Schema.DisplayType dt = dfr.getType();
                if (dt == Schema.DisplayType.ADDRESS || dt == Schema.DisplayType.LOCATION) {
                    continue;
                }
                fieldSet.add(fName);
            }
        }

        // Also include parent relationship fields for lookup traversals
        for (String fName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fName).getDescribe();
            if (dfr.isAccessible() && dfr.getType() == Schema.DisplayType.REFERENCE && !dfr.getReferenceTo().isEmpty()) {
                String relName = dfr.getRelationshipName();
                if (String.isNotBlank(relName)) {
                    fieldSet.add(relName + '.Name');
                }
            }
        }

        // Add any parent fields referenced in the template
        if (String.isNotBlank(templateJson)) {
            addReferencedParentFields(templateJson, fieldSet, fieldMap);
        }

        // Build clean field list — filter out any blank entries
        List<String> cleanFields = new List<String>();
        for (String f : fieldSet) {
            if (String.isNotBlank(f)) {
                cleanFields.add(f);
            }
        }
        if (cleanFields.isEmpty()) {
            cleanFields.add('Id');
        }

        String query = 'SELECT ' + String.join(cleanFields, ', ') +
                        ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                        ' WHERE Id = :recordId LIMIT 1';

        try {
            List<SObject> records = Database.query(query);
            return records.isEmpty() ? null : records[0];
        } catch (Exception e) {
            // Fallback: query only Id and Name if full query fails
            try {
                String fallbackQuery = 'SELECT Id, Name FROM ' +
                                        String.escapeSingleQuotes(objectApiName) +
                                        ' WHERE Id = :recordId LIMIT 1';
                List<SObject> records = Database.query(fallbackQuery);
                return records.isEmpty() ? null : records[0];
            } catch (Exception e2) {
                return null;
            }
        }
    }

    private static List<SObject> queryChildRecords(String childObject, String relationshipField,
                                                     String parentRecordId, List<String> fieldNames,
                                                     String orderBy, Integer maxRows) {
        if (String.isBlank(childObject) || String.isBlank(relationshipField)) {
            return new List<SObject>();
        }

        // Ensure Id is always included, filter out blank entries
        Set<String> fieldSet = new Set<String>{'Id'};
        for (String f : fieldNames) {
            if (String.isNotBlank(f)) {
                fieldSet.add(String.escapeSingleQuotes(f));
            }
        }

        // Build clean field list
        List<String> cleanFields = new List<String>();
        for (String f : fieldSet) {
            if (String.isNotBlank(f)) {
                cleanFields.add(f);
            }
        }
        if (cleanFields.isEmpty()) {
            cleanFields.add('Id');
        }

        String query = 'SELECT ' + String.join(cleanFields, ', ') +
                        ' FROM ' + String.escapeSingleQuotes(childObject) +
                        ' WHERE ' + String.escapeSingleQuotes(relationshipField) + ' = :parentRecordId';

        if (String.isNotBlank(orderBy)) {
            query += ' ORDER BY ' + String.escapeSingleQuotes(orderBy);
        }

        query += ' LIMIT ' + maxRows;

        try {
            return Database.query(query);
        } catch (Exception e) {
            System.debug('Error querying child records: ' + e.getMessage() + ' | Query: ' + query);
            return new List<SObject>();
        }
    }

    // ============================== FIELD VALUE TRAVERSAL ==============================

    private static Object getFieldValue(SObject record, String fieldPath) {
        if (record == null || String.isBlank(fieldPath)) return null;

        try {
            if (fieldPath.contains('.')) {
                // Relationship traversal  e.g. Plot__r.Name
                String relName = fieldPath.substringBefore('.');
                String remaining = fieldPath.substringAfter('.');
                SObject parent = record.getSObject(relName);
                if (parent != null) {
                    return getFieldValue(parent, remaining);
                }
                return null;
            }
            return record.get(fieldPath);
        } catch (Exception e) {
            return null;
        }
    }

    // ============================== TEMPLATE FIELD SCANNING ==============================

    /**
     * @description Scan the template JSON for parent relationship field references
     * (e.g., Account__r.Phone, Owner.Email, and multi-hop grandparent paths like
     * Booking__r.Unit__r.Name) used in merge fields, fieldGrid sections, or table
     * columns, and add them to the query field set. The "field" scan (pattern 2)
     * also covers main-record TABLE columns that use lookup paths (Booking__r.Amount__c),
     * since table columns store their path under the same "field" key.
     *
     * Supports ANY relationship depth (Booking__r.Unit__r.Name,
     * Booking__r.Project__r.Owner__r.Name, etc.) — each hop is validated against schema
     * so a single bad/renamed field only skips that one merge field instead of throwing
     * and losing the whole query (which would blank out every merge field on the page).
     */
    private static void addReferencedParentFields(String templateJson, Set<String> fieldSet,
                                                    Map<String, Schema.SObjectField> fieldMap) {
        // Each pattern is scanned over overlapping slices of the (potentially very large) template
        // JSON. Running a matcher across a ~300 KB string in one pass can exceed Apex's regex step
        // limit ("Regex too complicated") once the template is merge-field dense, so every scan is
        // windowed; the overlap (larger than any real token) keeps a token that straddles a slice
        // boundary from being missed, and duplicate hits are harmless because fieldSet is a Set.
        //
        // 1. {!Relationship.Relationship....Field} patterns (any depth) in content
        scanReferencedPaths('\\{!([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)\\}', templateJson, fieldSet, fieldMap);
        // 1b. {!INWORDS(...)} calls too — e.g. {!INWORDS(Booking__r.Unit__r.Cost__c)}
        scanReferencedPaths('(?i)\\{!\\s*(?:INWORDS|DATEWORDS)\\s*\\(\\s*([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)\\s*\\)\\s*\\}', templateJson, fieldSet, fieldMap);
        // 1c. Relationship fields used as operands in amount/area expressions.
        scanReferencedPaths('(?i)(?:INR|MULTIPLY|ADD|SUBTRACT)\\s*\\(\\s*([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)', templateJson, fieldSet, fieldMap);
        scanReferencedPaths('(?i)(?:MULTIPLY|ADD|SUBTRACT)\\s*\\(\\s*[A-Za-z0-9_.-]+\\s*,\\s*([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)', templateJson, fieldSet, fieldMap);
        // 2. fieldGrid / table-column fields with dot notation (any depth)
        //    (e.g., "field":"Account__r.Phone" or "field":"Booking__r.Unit__r.Name")
        scanReferencedPaths('"field"\\s*:\\s*"([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)"', templateJson, fieldSet, fieldMap);
        // 3. table-column parent-field totals with dot notation (any depth)
        //    (e.g., "totalParentField":"Booking__r.Unit__r.Total_Flat_Cost__c")
        scanReferencedPaths('"totalParentField"\\s*:\\s*"([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)"', templateJson, fieldSet, fieldMap);
    }

    // Window/overlap for scanReferencedPaths. Overlap must exceed the longest possible merge token
    // so no token is split across a boundary and lost.
    private static final Integer SCAN_WINDOW = 20000;
    private static final Integer SCAN_OVERLAP = 400;

    /**
     * @description Run one capture-group-1 pattern over `text` in overlapping windows and validate +
     * add each captured dotted path. Windowing keeps any single matcher pass well under Apex's regex
     * step limit even when the template JSON is very large and merge-field dense; the overlap ensures
     * a token spanning a window boundary is still matched in the next window (the Set dedupes).
     */
    private static void scanReferencedPaths(String regex, String text,
                                            Set<String> fieldSet,
                                            Map<String, Schema.SObjectField> fieldMap) {
        if (String.isBlank(text)) return;
        Pattern p = Pattern.compile(regex);
        Integer len = text.length();
        Integer start = 0;
        while (start < len) {
            Integer endPos = Math.min(len, start + SCAN_WINDOW);
            Matcher m = p.matcher(text.substring(start, endPos));
            while (m.find()) {
                addValidatedPath(m.group(1), fieldSet, fieldMap);
            }
            if (endPos >= len) break;
            start = endPos - SCAN_OVERLAP;
        }
    }

    /**
     * @description Walk a dotted relationship path (e.g. Booking__r.Unit__r.Name) one hop
     * at a time, validating each relationship segment against the schema of whatever object
     * it points to. If every hop resolves, the full path is added to the SOQL field set. If
     * any hop is invalid (typo'd relationship name, non-reference field, etc.) the path is
     * silently skipped — that single merge field just won't resolve, instead of throwing and
     * falling back to an Id/Name-only query that would blank out every merge field on the page.
     */
    private static void addValidatedPath(String fieldPath, Set<String> fieldSet,
                                          Map<String, Schema.SObjectField> rootFieldMap) {
        List<String> parts = fieldPath.split('\\.');
        if (parts.size() < 2) return; // no relationship hop — nothing extra to query

        Map<String, Schema.SObjectField> currentFieldMap = rootFieldMap;
        // Walk every segment except the last (the last segment is the actual field name)
        for (Integer i = 0; i < parts.size() - 1; i++) {
            Schema.SObjectField relField = findRelationshipField(parts[i], currentFieldMap);
            if (relField == null) return; // unknown relationship hop — bail out safely

            List<Schema.SObjectType> refs = relField.getDescribe().getReferenceTo();
            if (refs.isEmpty()) return; // polymorphic/unresolvable reference — bail out safely
            currentFieldMap = refs[0].getDescribe().fields.getMap();
        }

        fieldSet.add(fieldPath);
    }

    /** Finds the lookup field on fieldMap whose RelationshipName matches relName (case-insensitive). */
    private static Schema.SObjectField findRelationshipField(String relName, Map<String, Schema.SObjectField> fieldMap) {
        for (String fName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fName).getDescribe();
            if (dfr.getType() == Schema.DisplayType.REFERENCE) {
                String lookupRelName = dfr.getRelationshipName();
                if (String.isNotBlank(lookupRelName) && lookupRelName.equalsIgnoreCase(relName)) {
                    return fieldMap.get(fName);
                }
            }
        }
        return null;
    }

    // ============================== UTILITIES ==============================

    // ============================== NUMBER TO WORDS (Indian) ==============================

    private static final List<String> ONES = new List<String>{
        '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
        'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'
    };
    private static final List<String> TENS = new List<String>{
        '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
    };

    /** Converts an amount to words using the Indian numbering system (Crore / Lakh / Thousand).
     *  Returns e.g. "One Lakh Twenty Three Thousand Four Hundred Fifty" (no currency word, so the
     *  template author can wrap it as "Rupees ... Only"). Includes paise when present. */
    @TestVisible
    private static String numberToWordsIndian(Decimal amount) {
        if (amount == null) return '';
        Boolean negative = amount < 0;
        if (negative) amount = amount.abs();

        Long rupees = amount.longValue();
        Decimal fraction = (amount - rupees) * 100;
        Integer paise = fraction.setScale(0, System.RoundingMode.HALF_UP).intValue();
        if (paise >= 100) { rupees += 1; paise -= 100; }

        String result = (rupees == 0) ? 'Zero' : convertToIndianWords(rupees);
        if (paise > 0) {
            result += ' and ' + twoDigits(paise) + ' Paise';
        }
        return (negative ? 'Minus ' : '') + result;
    }

    private static String twoDigits(Integer n) {
        if (n < 20) return ONES[n];
        Integer t = n / 10;
        Integer o = Math.mod(n, 10);
        return TENS[t] + (o > 0 ? ' ' + ONES[o] : '');
    }

    private static String threeDigits(Integer n) {
        Integer h = n / 100;
        Integer rest = Math.mod(n, 100);
        String s = '';
        if (h > 0) s += ONES[h] + ' Hundred';
        if (rest > 0) s += (s != '' ? ' ' : '') + twoDigits(rest);
        return s;
    }

    private static String convertToIndianWords(Long num) {
        if (num == 0) return '';
        String result = '';
        Long crore = num / 10000000;
        Long afterCrore = Math.mod(num, 10000000);
        Integer lakh = Integer.valueOf(String.valueOf(afterCrore / 100000));
        Long afterLakh = Math.mod(afterCrore, 100000);
        Integer thousand = Integer.valueOf(String.valueOf(afterLakh / 1000));
        Integer hundred = Integer.valueOf(String.valueOf(Math.mod(afterLakh, 1000)));

        if (crore > 0) result += convertToIndianWords(crore) + ' Crore ';
        if (lakh > 0) result += twoDigits(lakh) + ' Lakh ';
        if (thousand > 0) result += twoDigits(thousand) + ' Thousand ';
        if (hundred > 0) result += threeDigits(hundred);
        return result.trim();
    }

    // ============================== TABLE AGGREGATES ==============================

    /** Computes an aggregate (sum/count/average/min/max) over a child field. */
    private static String computeAggregate(List<SObject> children, String fieldName, String agg) {
        Decimal sum = 0;
        Integer cnt = 0;
        Decimal minV = null;
        Decimal maxV = null;
        for (SObject child : children) {
            Object v = getFieldValue(child, fieldName);
            if (v == null) continue;
            Decimal d;
            try { d = Decimal.valueOf(String.valueOf(v)); } catch (Exception e) { continue; }
            sum += d;
            cnt++;
            if (minV == null || d < minV) minV = d;
            if (maxV == null || d > maxV) maxV = d;
        }
        if (agg == 'count') return String.valueOf(cnt);
        if (cnt == 0) return '';
        if (agg == 'sum') return formatNumber(sum);
        if (agg == 'average') return formatNumber((sum / cnt).setScale(2));
        if (agg == 'min') return formatNumber(minV);
        if (agg == 'max') return formatNumber(maxV);
        return '';
    }

    /** Trims a trailing ".0" so whole numbers render cleanly. */
    private static String formatNumber(Decimal d) {
        if (d == null) return '';
        if (d == d.round()) return String.valueOf(d.longValue());
        return String.valueOf(d);
    }

    /**
     * @description Renders date values in day/month/year format. DateTime fields show the
     *              calendar date only; non-date values pass through String.valueOf.
     */
    private static String formatFieldValue(Object val) {
        if (val == null) return '';
        if (val instanceof DateTime) {
            return ((DateTime) val).format('dd/MM/yyyy');
        }
        if (val instanceof Date) {
            Date dateValue = (Date) val;
            return DateTime.newInstance(
                dateValue,
                Time.newInstance(0, 0, 0, 0)
            ).format('dd/MM/yyyy');
        }
        return String.valueOf(val);
    }

    private static String formatDisplayValue(Object value, String format) {
        if (String.isBlank(format) || !format.equalsIgnoreCase('INR')) {
            return formatFieldValue(value);
        }

        Decimal amount;
        if (value instanceof Decimal) {
            amount = (Decimal) value;
        } else if (value instanceof Integer || value instanceof Long || value instanceof Double) {
            amount = Decimal.valueOf(String.valueOf(value));
        } else {
            return formatFieldValue(value);
        }
        return formatIndianAmount(amount);
    }

    private static String getStr(Map<String, Object> data, String key, String defaultVal) {
        if (data == null || !data.containsKey(key) || data.get(key) == null) return defaultVal;
        String val = String.valueOf(data.get(key));
        // Return default for empty strings when a non-empty default is provided
        if (String.isBlank(val) && String.isNotBlank(defaultVal)) return defaultVal;
        return val;
    }

    private static String getTableColumnWidth(Map<String, Object> column) {
        String width = getStr(column, 'width', '');
        Matcher matcher = Pattern.compile('^(\\d{1,3})%$').matcher(width);
        if (!matcher.matches()) return '';

        Integer percent = Integer.valueOf(matcher.group(1));
        return percent > 0 && percent <= 100 ? String.valueOf(percent) + '%' : '';
    }

    private static String getTableColumnAlignment(Map<String, Object> column, String defaultAlignment) {
        String alignment = getStr(column, 'align', defaultAlignment);
        return new Set<String>{ 'left', 'center', 'right' }.contains(alignment)
            ? alignment
            : defaultAlignment;
    }

    // Read a numeric logoSize from a header/column map. Defaults to 100, clamped to a
    // sane range (matches the slider in the builder).
    private static Integer readLogoSize(Map<String, Object> col) {
        if (col == null) return 100;
        Object raw = col.get('logoSize');
        if (raw == null) return 100;
        Integer n;
        try {
            if (raw instanceof Integer) n = (Integer) raw;
            else if (raw instanceof Decimal) n = ((Decimal) raw).intValue();
            else if (raw instanceof Double) n = ((Double) raw).intValue();
            else n = Integer.valueOf(String.valueOf(raw));
        } catch (Exception e) { return 100; }
        if (n < 30) n = 30;
        if (n > 500) n = 500;
        return n;
    }

    // Parse "200px" / "200" → 200. Returns null for "auto", "100%", blank, or unparseable.
    private static Integer pxToInt(String s) {
        if (String.isBlank(s)) return null;
        String t = s.trim().toLowerCase();
        if (t == 'auto' || t.endsWith('%')) return null;
        if (t.endsWith('px')) t = t.substring(0, t.length() - 2).trim();
        try { return Integer.valueOf(t); } catch (Exception e) { return null; }
    }

    /**
     * Simple string builder helper (Apex lacks java.lang.StringBuilder)
     */
    public class StringBuilder {
        private List<String> parts = new List<String>();

        public void append(String s) {
            if (s != null) parts.add(s);
        }

        public override String toString() {
            return String.join(parts, '');
        }
    }
}