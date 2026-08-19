const fs = require('fs');

let dataContent = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

const missingKeysEn = {
    'status_review': 'Review',
    'status_in_progress': 'In Progress',
    'ui_no_clients': 'No clients',
    'ui_new_client': 'New Client',
    'ui_name': 'Name',
    'ui_deal_pipeline': 'Deal Pipeline',
    'ui_client_directory': 'Client Directory',
    'ui_new_deal': 'New Deal',
    'ui_no_clients_yet': 'No clients yet',
    'ui_no_orders_found': 'No orders found',
    'ui_deal_client': 'Deal / Client',
    'ui_print_contract': 'Print Contract',
    'actions': 'Actions',
    'search': 'Search',
    'ui_manager_view': 'Manager View',
    'ui_employee_view': 'Employee View',
    'search_placeholder': 'Search (Cmd/Ctrl + K)',
    'ui_new_request': 'New Request',
    'ui_date': 'Date',
    'req_no_found': 'No requests found.'
};

const missingKeysAr = {
    'status_review': 'مراجعة',
    'status_in_progress': 'قيد التنفيذ',
    'ui_no_clients': 'لا يوجد عملاء',
    'ui_new_client': 'عميل جديد',
    'ui_name': 'الاسم',
    'ui_deal_pipeline': 'مسار الصفقات',
    'ui_client_directory': 'دليل العملاء',
    'ui_new_deal': 'صفقة جديدة',
    'ui_no_clients_yet': 'لا يوجد عملاء حتى الآن',
    'ui_no_orders_found': 'لم يتم العثور على طلبات',
    'ui_deal_client': 'الصفقة / العميل',
    'ui_print_contract': 'طباعة العقد',
    'actions': 'إجراءات',
    'search': 'بحث',
    'ui_manager_view': 'عرض المدير',
    'ui_employee_view': 'عرض الموظف',
    'search_placeholder': 'بحث (Cmd/Ctrl + K)',
    'ui_new_request': 'طلب جديد',
    'ui_date': 'التاريخ',
    'req_no_found': 'لم يتم العثور على طلبات.'
};

// We will explicitly replace any `????` garbled text and add the keys if missing.
// A simpler way is to find the exact start of `en: {` and `ar: {` and then insert our keys right after it.
// If the key is already somewhere in the block, we remove it to avoid duplicates.

function injectKeys(blockName, keysMap) {
    // find `blockName: {`
    let startIdx = dataContent.indexOf(`${blockName}: {`);
    if (startIdx === -1) return;
    
    // find the end of this block by counting braces
    let i = startIdx + blockName.length + 2;
    let braceCount = 0;
    while (i < dataContent.length) {
        if (dataContent[i] === '{') braceCount++;
        if (dataContent[i] === '}') {
            braceCount--;
            if (braceCount === 0) break;
        }
        i++;
    }
    let endIdx = i;
    
    let innerContent = dataContent.substring(startIdx + blockName.length + 3, endIdx);
    
    // For each key, we remove its existing line in innerContent (to override)
    for (const [k, v] of Object.entries(keysMap)) {
        let regex = new RegExp(`^\\s*${k}\\s*:.*(?:,\\s*$|$)`, 'gm');
        innerContent = innerContent.replace(regex, '');
    }
    
    // Now prepend all the keys at the top of the block
    let newEntries = '';
    for (const [k, v] of Object.entries(keysMap)) {
        newEntries += `\n    ${k}: "${v}",`;
    }
    
    innerContent = newEntries + innerContent;
    
    dataContent = dataContent.substring(0, startIdx + blockName.length + 3) + innerContent + dataContent.substring(endIdx);
}

injectKeys('en', missingKeysEn);
injectKeys('ar', missingKeysAr);

fs.writeFileSync('e:/HR.sys/js/data.js', dataContent, 'utf8');
console.log("Successfully injected all translations to EN and AR blocks in data.js");

// Now let's fix `app.js` "Print Contract" which doesn't have a t() call yet.
let appContent = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

// The line is: <button class="btn-secondary btn-sm" onclick="handlePrintContract('${u.id}')" title="Print Contract">
appContent = appContent.replace(
    /title="Print Contract">/g,
    'title="${t(\'ui_print_contract\') || \'Print Contract\'}">'
);
// And the inner text: <i data-lucide="printer"></i> Print Contract
appContent = appContent.replace(
    /<i data-lucide="printer"><\/i>\s*Print Contract/g,
    '<i data-lucide="printer"></i> ${t(\'ui_print_contract\') || \'Print Contract\'}'
);

fs.writeFileSync('e:/HR.sys/js/app.js', appContent, 'utf8');
console.log("Patched Print Contract in app.js");

