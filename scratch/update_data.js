const fs = require('fs');

let dataContent = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

dataContent = dataContent.replace(/nav_emp_contracts:\s*"Employees & Contracts"/g, 'nav_emp_contracts: "Contracts"');
dataContent = dataContent.replace(/nav_emp_dir:\s*"Employees & Contracts"/g, 'nav_emp_dir: "Contracts"');

// Update Arabic translations
dataContent = dataContent.replace(/nav_emp_contracts:\s*"الموظفين والعقود"/g, 'nav_emp_contracts: "العقود"');
dataContent = dataContent.replace(/nav_emp_dir:\s*"الموظفين والعقود"/g, 'nav_emp_dir: "العقود"');

fs.writeFileSync('e:/HR.sys/js/data.js', dataContent, 'utf8');
console.log("Updated data.js");
