const fs = require('fs');

// 1. Fix app.js (No requests found hardcoded string)
let appContent = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');
appContent = appContent.replace(
    /<tr><td colspan="6" style="text-align: center; color: var\(--color-text-secondary\); padding: 2rem;">No requests found\.<\/td><\/tr>/g,
    "<tr><td colspan=\"6\" style=\"text-align: center; color: var(--color-text-secondary); padding: 2rem;\">${t('req_no_found') || 'No requests found.'}</td></tr>"
);
fs.writeFileSync('e:/HR.sys/js/app.js', appContent, 'utf8');


// 2. Fix data.js missing translations
let dataContent = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

// A helper function to add a key-value to a block in data.js if it doesn't exist,
// or replace it if it does.
function setKey(blockName, key, val) {
    // Find the block
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

setKey('en', 'ui_manager_view', 'Manager View');
setKey('en', 'ui_employee_view', 'Employee View');
setKey('en', 'search_placeholder', 'Search (Cmd/Ctrl + K)');
setKey('en', 'ui_new_request', 'New Request');
setKey('en', 'ui_date', 'Date');
setKey('en', 'req_no_found', 'No requests found.');

setKey('ar', 'ui_manager_view', 'عرض المدير');
setKey('ar', 'ui_employee_view', 'عرض الموظف');
setKey('ar', 'search_placeholder', 'بحث (Cmd/Ctrl + K)');
setKey('ar', 'ui_new_request', 'طلب جديد');
setKey('ar', 'ui_date', 'التاريخ');
setKey('ar', 'req_no_found', 'لم يتم العثور على طلبات.');

fs.writeFileSync('e:/HR.sys/js/data.js', dataContent, 'utf8');
console.log("Fixed missing translations");
