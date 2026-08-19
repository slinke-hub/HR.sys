const fs = require('fs');

let dataContent = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

dataContent = dataContent.replace(
    /nav_emp_contracts: "Contracts",/g,
    'nav_emp_contracts: "Contracts",\n    ui_new_contract: "Create New Contract",'
);

dataContent = dataContent.replace(
    /nav_emp_contracts: "العقود",/g,
    'nav_emp_contracts: "العقود",\n    ui_new_contract: "إنشاء عقد جديد",'
);

fs.writeFileSync('e:/HR.sys/js/data.js', dataContent, 'utf8');
console.log("Added ui_new_contract successfully");
