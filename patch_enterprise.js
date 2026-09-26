const fs = require('fs');
const file = 'e:/HR.sys/js/app.js';
let content = fs.readFileSync(file, 'utf8');

// 1. Add to view validation arrays
content = content.replace(/'hr_suite_beta'(, 'whatsapp_inbox')?/g, "'hr_suite_beta', 'ats_beta', 'lms_beta', 'appraisals_beta', 'surveys_beta', 'shifts_beta', 'expenses_beta'$1");

// 2. Add to switch statement
const switchMatch = "case 'hr_suite_beta': content = await window.renderHrSuiteBeta(); break;";
const switchReplacement = `case 'hr_suite_beta': content = await window.renderHrSuiteBeta(); break;
            case 'ats_beta': content = window.renderAtsBeta(); break;
            case 'lms_beta': content = window.renderLmsBeta(); break;
            case 'appraisals_beta': content = window.renderAppraisalsBeta(); break;
            case 'surveys_beta': content = window.renderSurveysBeta(); break;
            case 'shifts_beta': content = window.renderShiftsBeta(); break;
            case 'expenses_beta': content = window.renderExpensesBeta(); break;`;
content = content.replace(switchMatch, switchReplacement);

fs.writeFileSync(file, content);
console.log('Modified app.js successfully!');
