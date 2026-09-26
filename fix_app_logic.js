const fs = require('fs');
const file = 'e:/HR.sys/js/app.js';
let content = fs.readFileSync(file, 'utf8');

// Fix the corrupted case statement
const badCase = "case 'hr_suite_beta', 'ats_beta', 'lms_beta', 'appraisals_beta', 'surveys_beta', 'shifts_beta', 'expenses_beta': content = await window.renderHrSuiteBeta(); break;";
const goodCases = `case 'hr_suite_beta': content = await window.renderHrSuiteBeta(); break;
            case 'ats_beta': content = window.renderAtsBeta(); break;
            case 'lms_beta': content = window.renderLmsBeta(); break;
            case 'appraisals_beta': content = window.renderAppraisalsBeta(); break;
            case 'surveys_beta': content = window.renderSurveysBeta(); break;
            case 'shifts_beta': content = window.renderShiftsBeta(); break;
            case 'expenses_beta': content = window.renderExpensesBeta(); break;`;

content = content.replace(badCase, goodCases);

// Also fix the corrupted if statement at line 2349
const badIf = "if (viewId === 'hr_suite_beta', 'ats_beta', 'lms_beta', 'appraisals_beta', 'surveys_beta', 'shifts_beta', 'expenses_beta') return window.canCurrentUserUseHrSuiteBeta?.() === true;";
const goodIf = "if (['hr_suite_beta', 'ats_beta', 'lms_beta', 'appraisals_beta', 'surveys_beta', 'shifts_beta', 'expenses_beta'].includes(viewId)) return window.canCurrentUserUseHrSuiteBeta?.() === true;";

content = content.replace(badIf, goodIf);

fs.writeFileSync(file, content);
console.log('Fixed app.js successfully!');
