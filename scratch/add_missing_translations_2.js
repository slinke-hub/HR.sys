const fs = require('fs');

let dataContent = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

function setKey(blockName, key, val) {
    let blockRegex = new RegExp(`(${blockName}\\s*:\\s*\\{)([\\s\\S]*?)(\\n\\s*\\}(?!,))`, 'g');
    dataContent = dataContent.replace(blockRegex, (match, start, inner, end) => {
        let regex = new RegExp(`\\b${key}\\s*:.*?,?\\n`);
        let newEntry = `\n    ${key}: "${val}",\n`;
        if (regex.test(inner)) {
            inner = inner.replace(regex, newEntry);
        } else {
            inner += newEntry;
        }
        return start + inner + end;
    });
}

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
    'ui_no_orders_found': 'No orders found'
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
    'ui_no_orders_found': 'لم يتم العثور على طلبات'
};

for (const [k, v] of Object.entries(missingKeysEn)) {
    setKey('en', k, v);
}
for (const [k, v] of Object.entries(missingKeysAr)) {
    setKey('ar', k, v);
}

fs.writeFileSync('e:/HR.sys/js/data.js', dataContent, 'utf8');
console.log("Added missing translations to data.js");
