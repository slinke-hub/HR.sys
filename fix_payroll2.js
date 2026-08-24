const fs = require('fs');

let js = `// payroll.js
// Holds logic for Payroll Manager

async function renderPayrollModule() {
    if (!currentUser) return '';
    const isAdmin = currentUserRole === 'ADMIN' || 
                    (currentUserProfile && /accountant manager|finance manager/i.test(currentUserProfile.job_title || ''));

    if (!isAdmin) {
        // Employee View
        return await renderEmployeePayroll();
    }

    // Admin / HR Manager View
    return \`
        <div class="page-header fade-in-up">
            <div>
                <h2>\${t('nav_payroll') || 'Payroll Manager'} <span class="badge" style="background: var(--color-primary-light); color: var(--color-primary);">BETA</span></h2>
                <p class="subtitle">Manage commissions, attendance, loans, and generate payslips.</p>
            </div>
            <div class="header-actions">
                <input type="file" id="bulkPayslipUpload" accept=".xlsx, .xls" style="display: none;" onchange="handleBulkPayslipUpload(event)">
                <button class="btn btn-secondary" onclick="downloadPayrollTemplate()"><i data-lucide="download"></i> Excel Template</button>
                <button class="btn btn-secondary" onclick="document.getElementById('bulkPayslipUpload').click()"><i data-lucide="upload"></i> Upload Excel</button>
                <button class="btn btn-secondary" onclick="window.print()"><i data-lucide="printer"></i> Print</button>
                <button class="btn btn-primary" onclick="generateAllPayslips()"><i data-lucide="calculator"></i> Generate Payslips</button>
            </div>
        </div>
        
        <div style="display:flex;gap:.5rem;margin-bottom:2rem;flex-wrap:wrap;">
            <button class="btn btn-primary" data-payroll-tab="dashboard" onclick="switchPayrollTab('dashboard')">Dashboard</button>
            <button class="btn btn-secondary" data-payroll-tab="attendance" onclick="switchPayrollTab('attendance')">Attendance & Overtime</button>
            <button class="btn btn-secondary" data-payroll-tab="commissions" onclick="switchPayrollTab('commissions')">Sales & Commissions</button>
            <button class="btn btn-secondary" data-payroll-tab="loans" onclick="switchPayrollTab('loans')">Loans & Adjustments</button>
            <button class="btn btn-secondary" data-payroll-tab="settings" onclick="switchPayrollTab('settings')">Settings</button>
            <button class="btn btn-secondary" data-payroll-tab="eos" onclick="switchPayrollTab('eos')" style="background-color: #fee2e2; color: #991b1b; border-color: #fca5a5;">EOS Calculator</button>
        </div>

        <div id="payroll-tab-content">
            <!-- Content loaded dynamically based on tab -->
            \${await renderPayrollDashboardTab()}
        </div>
    \`;
}
`;

let content = fs.readFileSync('e:/HR.sys/js/payroll.js', 'utf8');
let lines = content.split('\n');
// Find where window.currentPayrollTab = 'dashboard'; starts
let splitIndex = lines.findIndex(l => l.includes("window.currentPayrollTab = 'dashboard';"));
if(splitIndex > -1) {
    let restOfFile = lines.slice(splitIndex).join('\n');
    fs.writeFileSync('e:/HR.sys/js/payroll.js', js + '\n' + restOfFile, 'utf8');
    console.log("Fixed payroll.js");
} else {
    console.log("Could not find split index");
}
