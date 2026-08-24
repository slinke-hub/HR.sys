const fs = require('fs');
let code = fs.readFileSync('js/payroll.js', 'utf8');

// 1. Add tab button
const tabButtonHtml = `<button class="btn-secondary" data-payroll-tab="released" onclick="switchPayrollTab('released')">Released payslips</button>`;
code = code.replace(
    `<button class="btn-secondary" data-payroll-tab="settings" onclick="switchPayrollTab('settings')">Settings</button>`,
    `${tabButtonHtml}\n            <button class="btn-secondary" data-payroll-tab="settings" onclick="switchPayrollTab('settings')">Settings</button>`
);

// 2. Add switch logic
code = code.replace(
    /case 'eos': html = await renderEOSTab\(\); break;/g,
    `case 'eos': html = await renderEOSTab(); break;
        case 'released': html = await renderReleasedPayslipsTab(); break;`
);

// 3. New function renderReleasedPayslipsTab
const renderReleasedTabCode = `
async function renderReleasedPayslipsTab() {
    const today = new Date();
    const currentMonth = \`\${today.getFullYear()}-\${String(today.getMonth() + 1).padStart(2, '0')}\`;
    
    // We can use a global or pass it, for now just use currentMonth as default filter
    const filterMonth = window.payslipFilterMonth || currentMonth;
    const payslips = await db.fetchReleasedPayslips(filterMonth);
    
    let rowsHTML = '';
    if (payslips.length === 0) {
        rowsHTML = \`<tr><td colspan="8" style="text-align: center; padding: 2rem;">No payslips released for this month.</td></tr>\`;
    } else {
        payslips.forEach(p => {
            rowsHTML += \`
                <tr>
                    <td>\${escapeHTML(p.employee_name)}</td>
                    <td>\${escapeHTML(p.month_year)}</td>
                    <td>\${Number(p.base_salary).toFixed(2)} SAR</td>
                    <td style="color: green;">+ \${Number(p.commission).toFixed(2)}</td>
                    <td style="color: green;">+ \${Number(p.overtime_pay).toFixed(2)}</td>
                    <td style="color: red;">- \${Number(p.deductions).toFixed(2)}</td>
                    <td style="font-weight: 600;">\${Number(p.net_pay).toFixed(2)} SAR</td>
                    <td>
                        <button class="btn-icon" title="Print Payslip" onclick="printSavedPayslip('\${p.id}')">
                            <i data-lucide="printer"></i>
                        </button>
                    </td>
                </tr>
            \`;
        });
    }

    return \`
        <div class="card fade-in-up">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                <h3>Released Payslips</h3>
                <div>
                    <input type="month" id="releasedPayslipsMonth" value="\${filterMonth}" onchange="filterReleasedPayslips()" style="background: rgba(255,255,255,0.1); color: #fff; border: 1px solid rgba(255,255,255,0.2); padding: 0.5rem; border-radius: 4px;">
                </div>
            </div>
            <div class="data-table-container">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Employee</th>
                            <th>Month</th>
                            <th>Base Salary</th>
                            <th>Commission</th>
                            <th>Overtime</th>
                            <th>Deductions</th>
                            <th>Net Pay</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        \${rowsHTML}
                    </tbody>
                </table>
            </div>
        </div>
    \`;
}

window.filterReleasedPayslips = function() {
    window.payslipFilterMonth = document.getElementById('releasedPayslipsMonth').value;
    switchPayrollTab('released');
};

window.printSavedPayslip = async function(payslipId) {
    const filterMonth = window.payslipFilterMonth || \`\${new Date().getFullYear()}-\${String(new Date().getMonth() + 1).padStart(2, '0')}\`;
    const payslips = await db.fetchReleasedPayslips(filterMonth);
    const p = payslips.find(x => x.id === payslipId);
    if (!p) return;
    
    const payslipModal = document.getElementById('payslipModal');
    const payslipContent = document.getElementById('payslipContent');
    if (!payslipModal || !payslipContent) return;

    payslipContent.innerHTML = \`
        <div style="text-align: center; margin-bottom: 2rem;">
            <h2>COMPANY NAME</h2>
            <p>Payslip for \${escapeHTML(p.month_year)}</p>
        </div>
        <div style="margin-bottom: 2rem;">
            <strong>Employee:</strong> \${escapeHTML(p.employee_name)}<br>
        </div>
        <table style="width: 100%; border-collapse: collapse; margin-bottom: 2rem;">
            <tr style="border-bottom: 1px solid rgba(0,0,0,0.1);">
                <th style="text-align: left; padding: 0.5rem;">Description</th>
                <th style="text-align: right; padding: 0.5rem;">Amount (SAR)</th>
            </tr>
            <tr style="border-bottom: 1px solid rgba(0,0,0,0.1);">
                <td style="padding: 0.5rem;">Base Salary</td>
                <td style="text-align: right; padding: 0.5rem;">\${Number(p.base_salary).toFixed(2)}</td>
            </tr>
            <tr style="border-bottom: 1px solid rgba(0,0,0,0.1);">
                <td style="padding: 0.5rem;">Commission</td>
                <td style="text-align: right; padding: 0.5rem; color: green;">\${Number(p.commission).toFixed(2)}</td>
            </tr>
            <tr style="border-bottom: 1px solid rgba(0,0,0,0.1);">
                <td style="padding: 0.5rem;">Overtime</td>
                <td style="text-align: right; padding: 0.5rem; color: green;">\${Number(p.overtime_pay).toFixed(2)}</td>
            </tr>
            <tr style="border-bottom: 1px solid rgba(0,0,0,0.1);">
                <td style="padding: 0.5rem;">Deductions</td>
                <td style="text-align: right; padding: 0.5rem; color: red;">\${Number(p.deductions).toFixed(2)}</td>
            </tr>
            <tr>
                <td style="padding: 0.5rem; font-weight: bold;">Net Pay</td>
                <td style="text-align: right; padding: 0.5rem; font-weight: bold;">\${Number(p.net_pay).toFixed(2)}</td>
            </tr>
        </table>
        <div style="text-align: center; margin-top: 3rem; color: #666; font-size: 0.9rem;">
            <p>This is a computer-generated document. No signature is required.</p>
        </div>
    \`;
    
    payslipModal.style.display = 'block';
};
`;

code = code.replace('window.generateAllPayslips = async function() {', renderReleasedTabCode + '\nwindow.generateAllPayslips = async function() {');

// 4. Update generateAllPayslips body
const generateRegex = /window\.generateAllPayslips = async function\(\) \{[\s\S]*?payslipModal\.style\.display = 'block';\n    };\n}/;
// Note: wait, generateAllPayslips has a huge body.
