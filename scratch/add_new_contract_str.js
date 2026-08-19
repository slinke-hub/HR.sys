const fs = require('fs');

let dataContent = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

// Insert english
dataContent = dataContent.replace(
    'ui_contract_date: "Date",',
    'ui_contract_date: "Date",\n    ui_new_contract: "Create New Contract",'
);

// Insert arabic
dataContent = dataContent.replace(
    'ui_contract_date: "التاريخ",',
    'ui_contract_date: "التاريخ",\n    ui_new_contract: "إنشاء عقد جديد",'
);

fs.writeFileSync('e:/HR.sys/js/data.js', dataContent, 'utf8');
console.log("Added ui_new_contract");
