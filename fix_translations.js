const fs = require('fs');
let js = fs.readFileSync('e:/HR.sys/js/payroll.js', 'utf8');

js = js.replace(
    /(window\.t && window\.t\('success'\)) \|\| 'Success'/g,
    "(window.t && window.t('ui_success') !== 'ui_success' ? window.t('ui_success') : 'Success')"
);

js = js.replace(
    /(window\.t && window\.t\('payslips_generated'\)) \|\| 'Payslips generated and saved successfully!'/g,
    "(window.t && window.t('ui_payslips_generated') !== 'ui_payslips_generated' ? window.t('ui_payslips_generated') : 'Payslips generated and saved successfully!')"
);

fs.writeFileSync('e:/HR.sys/js/payroll.js', js, 'utf8');
console.log("Fixed translation fallbacks in payroll.js");
