/* global currentUser, currentUserRole, currentUserProfile, showToast, XLSX */
/* exported renderPayrollModule, openPayrollLogSalesModal, submitPayrollLogSales */
// payroll.js
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
    return `
        <div class="page-header fade-in-up">
            <div>
                <h2>${t('nav_payroll') || 'Payroll Manager'} <span class="badge" style="background: var(--color-primary-light); color: var(--color-primary);">BETA</span></h2>
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
            <button class="btn btn-primary" data-payroll-tab="dashboard" onclick="switchPayrollTab('dashboard')"><span data-i18n="btn_payroll_dashboard">${t('btn_payroll_dashboard') || 'Dashboard'}</span></button>
            <button class="btn btn-secondary" data-payroll-tab="attendance" onclick="switchPayrollTab('attendance')"><span data-i18n="btn_payroll_attendance">${t('btn_payroll_attendance') || 'Attendance & Overtime'}</span></button>
            <button class="btn btn-secondary" data-payroll-tab="commissions" onclick="switchPayrollTab('commissions')"><span data-i18n="btn_payroll_commissions">${t('btn_payroll_commissions') || 'Sales & Commissions'}</span></button>
            <button class="btn btn-secondary" data-payroll-tab="loans" onclick="switchPayrollTab('loans')"><span data-i18n="btn_payroll_loans">${t('btn_payroll_loans') || 'Loans & Adjustments'}</span></button>
            <button class="btn btn-secondary" data-payroll-tab="settings" onclick="switchPayrollTab('settings')"><span data-i18n="btn_payroll_settings">${t('btn_payroll_settings') || 'Settings'}</span></button>
            <button class="btn btn-secondary" data-payroll-tab="eos" onclick="switchPayrollTab('eos')" style="background-color: #fee2e2; color: #991b1b; border-color: #fca5a5;"><span data-i18n="btn_payroll_eos">${t('btn_payroll_eos') || 'EOS Calculator'}</span></button>
        </div>

        <div id="payroll-tab-content">
            <!-- Content loaded dynamically based on tab -->
            ${await renderPayrollDashboardTab()}
        </div>
    `;
}

window.currentPayrollTab = 'dashboard';

window.switchPayrollTab = async function(tabId) {
    document.querySelectorAll('[data-payroll-tab]').forEach(btn => {
        btn.classList.toggle('btn-primary', btn.dataset.payrollTab === tabId);
        btn.classList.toggle('btn-secondary', btn.dataset.payrollTab !== tabId);
    });
    
    window.currentPayrollTab = tabId;
    const contentDiv = document.getElementById('payroll-tab-content');
    contentDiv.innerHTML = '<div class="loading"><div class="spinner"></div></div>';
    
    let html = '';
    switch(tabId) {
        case 'dashboard': html = await renderPayrollDashboardTab(); break;
        case 'attendance': html = await renderAttendanceTab(); break;
        case 'commissions': html = await renderCommissionsTab(); break;
        case 'loans': html = await renderLoansTab(); break;
        case 'settings': html = await renderPayrollSettingsTab(); break;
        case 'eos': html = await renderEOSTab(); break;
    }
    
    contentDiv.innerHTML = html;
    lucide.createIcons();
};

async function renderPayrollDashboardTab() {
    // Current Month Year
    const today = new Date();
    const currentMonth = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`;
    
    return `
        <div class="card fade-in-up">
            <h3>Payroll Overview - ${currentMonth}</h3>
            <p>Run calculations for all active employees.</p>
            <div class="data-table-container">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Employee</th>
                            <th>Base Salary</th>
                            <th>OT/Commissions</th>
                            <th>Deductions (Loans/Abs)</th>
                            <th>Net Pay</th>
                            <th>Status</th>
                            <th>Action</th>
                        </tr>
                    </thead>
                    <tbody id="payroll-dashboard-tbody">
                        <tr><td colspan="7" style="text-align: center;">Click "Generate Payslips" to calculate for this month.</td></tr>
                    </tbody>
                </table>
            </div>
        </div>
    `;
}

window.generateAllPayslips = async function() {
    const modal = document.getElementById('payrollProcessingModal');
    const msg = document.getElementById('payrollProcessingMessage');
    if (modal) {
        msg.textContent = "Running calculations and saving...";
        modal.style.display = 'flex';
    }
    
    const today = new Date();
    const currentMonth = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`;

    const employees = await db.fetchAllEmployees();
    const sales = await db.fetchMonthlySales(currentMonth);
    const absences = await db.fetchAbsences(currentMonth);
    const loans = await db.fetchEmployeeLoans();
    const settings = await db.fetchPayrollSettings();
    const adjustments = await db.fetchPayrollAdjustments(currentMonth);

    const generatedPayslips = [];
    
    for (const emp of employees) {
        if(emp.role === 'ADMIN' && (!emp.base_salary || emp.base_salary === 0)) continue; // skip pure admins without salary
        
        const baseSalary = emp.base_salary || 0;
        
        // 1. Commission Calculation
        let commission = 0;
        const empSales = sales.filter(s => s.employee_id === emp.id);
        const actualSales = empSales.reduce((sum, s) => sum + Number(s.amount), 0);
        const targetSales = 10000; // Mock target for now
        
        const percentageAchieved = targetSales > 0 ? (actualSales / targetSales) * 100 : 0;
        if (percentageAchieved > 50 && percentageAchieved <= 100) {
            commission = actualSales * 0.05;
        } else if (percentageAchieved > 100) {
            commission = actualSales * 0.10;
        }
        
        // 2. Overtime
        let overtimePay = 0;
        if (settings.is_overtime_enabled) {
            // Mock OT for now, or check adjustments
            const otHours = 0;
            const hourlyRate = (baseSalary / 30) / 8;
            overtimePay = otHours * (hourlyRate * 1.5);
        }

        // 3. Deductions
        const dailyRate = baseSalary / 30;
        const empAbsences = absences.filter(a => a.employee_id === emp.id && !a.is_excused);
        const absenceDeduction = empAbsences.length * dailyRate;
        
        const empLoans = loans.filter(l => l.employee_id === emp.id && l.remaining_balance > 0);
        let loanDeduction = 0;
        empLoans.forEach(l => {
            loanDeduction += Math.min(Number(l.monthly_installment), Number(l.remaining_balance));
        });
        
        let totalDeductions = absenceDeduction + loanDeduction;
        
        // 4. Adjustments
        const empAdjs = adjustments.filter(a => a.employee_id === emp.id);
        empAdjs.forEach(a => {
            if(a.type === 'BONUS') commission += Number(a.amount);
            if(a.type === 'DEDUCTION') totalDeductions += Number(a.amount);
        });

        const netPay = baseSalary + commission + overtimePay - totalDeductions;
        
        generatedPayslips.push({
            employee_id: emp.id,
            employee_name: emp.full_name || 'Unknown',
            month_year: currentMonth,
            base_salary: baseSalary,
            commission: commission,
            overtime_pay: overtimePay,
            deductions: totalDeductions,
            net_pay: netPay
        });
    }

    if (generatedPayslips.length > 0) {
        await db.saveReleasedPayslips(generatedPayslips);
    }
    
    if (modal) {
        modal.style.display = 'none';
    }
    
    // Show success modal instead of alert
    if (document.getElementById('successModal')) {
        const titleEl = document.getElementById('successModalTitle');
        const msgEl = document.getElementById('successModalMessage');
        if (titleEl) titleEl.innerText = (window.t && window.t('success')) || 'Success';
        if (msgEl) msgEl.innerText = (window.t && window.t('payslips_generated')) || 'Payslips generated and saved successfully!';
        
        document.getElementById('successModal').classList.add('active', 'show');
        if (window.lucide) {
            window.lucide.createIcons();
        }
    } else {
        window.showAppMessageModal("Payslips generated and saved successfully!");
    }
    window.switchPayrollTab('released');
};


window.printPayslip = function(empName, base, comm, ot, abs, loan, net) {
    const today = new Date().toLocaleDateString();
    const printWindow = window.open('', '_blank');
    printWindow.document.write(`
        <html>
        <head>
            <title>Payslip - ${empName}</title>
            <style>
                body { font-family: Arial, sans-serif; padding: 2rem; color: #333; }
                .header { text-align: center; margin-bottom: 2rem; border-bottom: 2px solid #333; padding-bottom: 1rem; }
                .details { width: 100%; border-collapse: collapse; margin-bottom: 2rem; }
                .details th, .details td { border: 1px solid #ddd; padding: 8px; text-align: left; }
                .details th { background-color: #f4f4f4; }
                .totals { font-size: 1.2rem; font-weight: bold; text-align: right; }
            </style>
        </head>
        <body>
            <div class="header">
                <h2>PAYSLIP</h2>
                <p>Employee: <strong>${empName}</strong> | Date: ${today}</p>
            </div>
            <table class="details">
                <tr><th>Earnings</th><th>Amount (SAR)</th></tr>
                <tr><td>Base Salary</td><td>${base.toFixed(2)}</td></tr>
                <tr><td>Commissions</td><td>${comm.toFixed(2)}</td></tr>
                <tr><td>Overtime</td><td>${ot.toFixed(2)}</td></tr>
                <tr><th>Deductions</th><th>Amount (SAR)</th></tr>
                <tr><td>Absences</td><td>${abs.toFixed(2)}</td></tr>
                <tr><td>Loans</td><td>${loan.toFixed(2)}</td></tr>
            </table>
            <div class="totals">
                Net Pay: ${net.toFixed(2)} SAR
            </div>
            <script>
                window.onload = function() { window.print(); window.close(); }
            </script>
        </body>
        </html>
    `);
    printWindow.document.close();
};

async function renderAttendanceTab() {
    const today = new Date();
    const currentMonth = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`;
    const absences = await db.fetchAbsences(currentMonth) || [];
    
    return `
        <div class="card fade-in-up">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                <h3>Attendance & Absences Ledger</h3>
                <button class="btn btn-primary" onclick="openPayrollLogAbsenceModal()"><i data-lucide="plus"></i> <span data-i18n="btn_payroll_log_absence">${t('btn_payroll_log_absence') || 'Log Absence'}</span></button>
            </div>
            <p>Track unexcused absences for deductions.</p>
            
            <table class="data-table">
                <thead>
                    <tr>
                        <th>Employee ID</th>
                        <th>Date of Absence</th>
                        <th>Type</th>
                    </tr>
                </thead>
                <tbody>
                    ${absences.length === 0 ? `<tr><td colspan="3" style="text-align:center;">No absences logged this month.</td></tr>` : absences.map(a => `
                        <tr>
                            <td>${a.employee_id}</td>
                            <td>${a.date_of_absence}</td>
                            <td>${a.is_excused ? '<span class="status-badge success">Excused</span>' : '<span class="status-badge error">Unexcused</span>'}</td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
    `;
}

async function renderCommissionsTab() {
    const tiers = await db.fetchCommissionTiers();
    const currentMonth = new Date().toISOString().substring(0, 7);
    const sales = await db.fetchMonthlySales(currentMonth) || [];
    
    return `
        <div class="grid-2">
            <div class="card fade-in-up">
                <h3>Commission Tiers</h3>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Min Target %</th>
                            <th>Max Target %</th>
                            <th>Commission %</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${tiers.map(t => `
                            <tr>
                                <td>${t.min_target_percentage}%</td>
                                <td>${t.max_target_percentage ? t.max_target_percentage + '%' : 'Infinity'}</td>
                                <td>${t.commission_percentage}%</td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            </div>
            
            <div class="card fade-in-up">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                    <h3>Monthly Sales Tracker (${currentMonth})</h3>
                    <button class="btn btn-primary" onclick="openPayrollLogSalesModal()"><i data-lucide="plus"></i> <span data-i18n="btn_payroll_log_sales">${t('btn_payroll_log_sales') || 'Log Sales'}</span></button>
                </div>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Employee</th>
                            <th>Actual Sales</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${sales.length === 0 ? `<tr><td colspan="2" style="text-align:center;">No sales logged.</td></tr>` : sales.map(s => `
                            <tr>
                                <td>${s.profiles?.full_name || s.employee_id}</td>
                                <td>${s.actual_sales_amount} SAR</td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            </div>
        </div>
    `;
}

async function renderLoansTab() {
    const loans = await db.fetchEmployeeLoans() || [];
    return `
        <div class="card fade-in-up">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                <h3>Active Employee Loans</h3>
                <button class="btn btn-primary" onclick="openPayrollNewLoanModal()"><i data-lucide="plus"></i> <span data-i18n="btn_payroll_new_loan">${t('btn_payroll_new_loan') || 'New Loan'}</span></button>
            </div>
            <table class="data-table">
                <thead>
                    <tr>
                        <th>Employee</th>
                        <th>Requested</th>
                        <th>Remaining</th>
                        <th>Monthly Installment</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    ${loans.length === 0 ? `<tr><td colspan="5" style="text-align:center;">No active loans.</td></tr>` : loans.map(l => `
                        <tr>
                            <td>${l.profiles?.full_name || l.employee_id}</td>
                            <td>${l.requested_amount} SAR</td>
                            <td>${l.remaining_balance} SAR</td>
                            <td>${l.monthly_installment} SAR</td>
                            <td><span class="status-badge ${l.status === 'APPROVED' ? 'success' : 'info'}">${l.status}</span></td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
    `;
}

async function renderPayrollSettingsTab() {
    const settings = await db.fetchPayrollSettings();
    return `
        <div class="card fade-in-up">
            <h3>HR Payroll Settings</h3>
            <div class="form-group" style="margin-top: 1.5rem;">
                <label style="display: flex; align-items: center; gap: 0.5rem; cursor: pointer;">
                    <input type="checkbox" id="ot-toggle" ${settings.is_overtime_enabled ? 'checked' : ''} onchange="toggleOvertime(this.checked)" style="width: 1.2rem; height: 1.2rem;">
                    <strong>Enable Overtime Calculations System-wide</strong>
                </label>
                <p style="font-size: 0.85rem; color: var(--color-text-secondary); margin-top: 0.5rem;">
                    If disabled, overtime inputs will be hidden and not calculated in payslips.
                </p>
            </div>
        </div>
    `;
}

window.toggleOvertime = async function(isChecked) {
    const res = await db.updatePayrollSettings({ is_overtime_enabled: isChecked });
    if(res.success) {
        showToast(`Overtime calculations ${isChecked ? 'enabled' : 'disabled'}.`, 'success');
    } else {
        showToast('Failed to update settings.', 'error');
    }
};

async function renderEOSTab() {
    return `
        <div class="card fade-in-up">
            <h3>End-of-Service (EOS) Calculator</h3>
            <p style="margin-bottom: 1.5rem; color: var(--color-text-secondary);">Calculates gratuity based on Saudi Labor Law.</p>
            
            <div class="grid-2">
                <div class="form-group">
                    <label>Hire Date</label>
                    <input type="date" id="eos-hire-date" class="form-input">
                </div>
                <div class="form-group">
                    <label>Final Date</label>
                    <input type="date" id="eos-final-date" class="form-input">
                </div>
                <div class="form-group">
                    <label>Base Salary (SAR)</label>
                    <input type="number" id="eos-base-salary" class="form-input" value="3400">
                </div>
                <div class="form-group">
                    <label>Termination Reason</label>
                    <select id="eos-reason" class="form-input">
                        <option value="resignation">Resignation</option>
                        <option value="termination">Termination (Employer)</option>
                    </select>
                </div>
            </div>
            <button class="btn btn-primary" onclick="calculateAndShowEOS()" style="margin-top: 1rem;"><span data-i18n="btn_payroll_calculate_eos">${t('btn_payroll_calculate_eos') || 'Calculate EOS'}</span></button>
            
            <div id="eos-result" style="margin-top: 2rem; padding: 1.5rem; background: var(--color-bg-alt); border-radius: 8px; display: none;">
                <!-- Results shown here -->
            </div>
        </div>
    `;
}

window.calculateAndShowEOS = function() {
    const hireDateStr = document.getElementById('eos-hire-date').value;
    const finalDateStr = document.getElementById('eos-final-date').value;
    const baseSalary = parseFloat(document.getElementById('eos-base-salary').value);
    const reason = document.getElementById('eos-reason').value;
    
    if(!hireDateStr || !finalDateStr || isNaN(baseSalary)) {
        window.showAppMessageModal("Please fill all fields.");
        return;
    }
    
    const hireDate = new Date(hireDateStr);
    const finalDate = new Date(finalDateStr);
    const diffTime = Math.abs(finalDate - hireDate);
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    const yearsOfService = diffDays / 365.25;
    
    let eosAmount = 0;
    
    // Basic Saudi Labor Law calculation
    // Half month wage for first 5 years, full month for years beyond 5.
    let fullAward = 0;
    if(yearsOfService <= 5) {
        fullAward = yearsOfService * (baseSalary / 2);
    } else {
        fullAward = (5 * (baseSalary / 2)) + ((yearsOfService - 5) * baseSalary);
    }
    
    if (reason === 'resignation') {
        if (yearsOfService < 2) {
            eosAmount = 0;
        } else if (yearsOfService >= 2 && yearsOfService < 5) {
            eosAmount = fullAward * 0.3333; // One third
        } else if (yearsOfService >= 5 && yearsOfService < 10) {
            eosAmount = fullAward * 0.6667; // Two thirds
        } else {
            eosAmount = fullAward; // Full
        }
    } else {
        // Employer termination or contract end
        eosAmount = fullAward;
    }
    
    const resDiv = document.getElementById('eos-result');
    resDiv.style.display = 'block';
    resDiv.innerHTML = `
        <h4 style="margin-bottom: 0.5rem;">EOS Calculation Result</h4>
        <p><strong>Years of Service:</strong> ${yearsOfService.toFixed(2)} years</p>
        <p><strong>Calculated Gratuity:</strong> <span style="color: var(--color-primary); font-size: 1.25rem; font-weight: bold;">${eosAmount.toFixed(2)} SAR</span></p>
        <p style="font-size: 0.85rem; color: var(--color-text-secondary); margin-top: 1rem;">Note: Any outstanding loans should be deducted from this final settlement amount.</p>
    `;
};

// Original employee payroll view
async function renderEmployeePayroll() {
    // Mock for beta
    let rowsHTML = `<tr><td colspan="4" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">No payslips generated yet.</td></tr>`;
    
    return `
        <div class="page-header fade-in-up">
            <div>
                <h2>${t('nav_payroll') || 'My Payroll'}</h2>
                <p class="subtitle">View your monthly payslips and history.</p>
            </div>
        </div>
        <div class="card fade-in-up">
            <div class="data-table-container">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Month</th>
                            <th>Net Pay</th>
                            <th>Status</th>
                            <th>Action</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${rowsHTML}
                    </tbody>
                </table>
            </div>
        </div>
    `;
}


// -- LOG SALES MODAL FUNCTIONS --
async function openPayrollLogSalesModal() {
    const modal = document.getElementById('payrollLogSalesModal');
    if (!modal) return;
    
    // Set default month to currently viewed month
    const monthInput = document.getElementById('payrollMonth');
    let currentMonthStr = '';
    if (monthInput && monthInput.value) {
        currentMonthStr = monthInput.value;
    } else {
        const today = new Date();
        currentMonthStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`;
    }
    document.getElementById('payrollSalesMonthYear').value = currentMonthStr;
    document.getElementById('payrollSalesAmount').value = '';
    
    // Populate employees dropdown
    const select = document.getElementById('payrollSalesEmployeeId');
    select.innerHTML = '<option value="">Select Employee...</option>';
    
    try {
        const employees = await db.fetchAllEmployees();
        employees.forEach(emp => {
            const opt = document.createElement('option');
            opt.value = emp.id;
            opt.textContent = emp.full_name + (emp.display_name_ar ? ` - ${emp.display_name_ar}` : '');
            select.appendChild(opt);
        });
    } catch(e) {
        console.error(e);
    }
    
    modal.style.display = 'flex';
    if (window.lucide) {
        lucide.createIcons();
    }
}

function closePayrollLogSalesModal() {
    const modal = document.getElementById('payrollLogSalesModal');
    if (modal) modal.style.display = 'none';
}

async function submitPayrollLogSales(e) {
    e.preventDefault();
    const btn = document.getElementById('payrollSalesSubmitBtn');
    btn.disabled = true;
    btn.textContent = 'Saving...';
    
    try {
        const payload = {
            employee_id: document.getElementById('payrollSalesEmployeeId').value,
            month_year: document.getElementById('payrollSalesMonthYear').value,
            actual_sales_amount: parseFloat(document.getElementById('payrollSalesAmount').value)
        };
        
        const res = await db.saveMonthlySales(payload);
        if (res.success) {
            showToast('Sales logged successfully!', 'success');
            closePayrollLogSalesModal();
            // Refresh payroll UI
            if (window.currentPayrollTab === 'commissions') {
                window.switchPayrollTab('commissions');
            } else if (typeof renderView === 'function') {
                renderView('payroll');
            }
        } else {
            showToast('Error saving sales.', 'error');
            console.error(res.error);
        }
    } catch(err) {
        showToast('Error: ' + err.message, 'error');
    } finally {
        btn.disabled = false;
        btn.textContent = 'Save Sales';
    }
}


// -- LOG ABSENCE MODAL FUNCTIONS --
window.openPayrollLogAbsenceModal = async function() {
    const modal = document.getElementById('payrollLogAbsenceModal');
    if (!modal) return;
    
    document.getElementById('payrollAbsenceDate').value = new Date().toISOString().split('T')[0];
    document.getElementById('payrollAbsenceIsExcused').checked = false;
    
    const select = document.getElementById('payrollAbsenceEmployeeId');
    select.innerHTML = '<option value="">Select Employee...</option>';
    
    try {
        const employees = await db.fetchAllEmployees();
        employees.forEach(emp => {
            const opt = document.createElement('option');
            opt.value = emp.id;
            opt.textContent = emp.full_name + (emp.display_name_ar ? ` - ${emp.display_name_ar}` : '');
            select.appendChild(opt);
        });
    } catch (e) {
        console.error('Error fetching employees:', e);
    }
    
    modal.classList.add('active', 'show');
    lucide.createIcons();
};

window.submitPayrollLogAbsence = async function(e) {
    e.preventDefault();
    const btn = e.target.querySelector('button[type="submit"]');
    const originalText = btn.innerHTML;
    btn.innerHTML = 'Saving...';
    btn.disabled = true;
    
    const employee_id = document.getElementById('payrollAbsenceEmployeeId').value;
    const date_of_absence = document.getElementById('payrollAbsenceDate').value;
    const is_excused = document.getElementById('payrollAbsenceIsExcused').checked;
    
    const res = await db.saveAbsence({ employee_id, date_of_absence, is_excused });
    
    btn.innerHTML = originalText;
    btn.disabled = false;
    
    if (res.success) {
        showToast('Absence logged successfully', 'success');
        document.getElementById('payrollLogAbsenceModal').classList.remove('active', 'show');
        if (window.currentPayrollTab === 'attendance') {
            window.switchPayrollTab('attendance');
        }
    } else {
        showToast(res.error?.message || 'Error logging absence', 'danger');
    }
};

// -- NEW LOAN MODAL FUNCTIONS --
window.openPayrollNewLoanModal = async function() {
    const modal = document.getElementById('payrollNewLoanModal');
    if (!modal) return;
    
    document.getElementById('payrollLoanAmount').value = '';
    document.getElementById('payrollLoanInstallment').value = '';
    
    const select = document.getElementById('payrollLoanEmployeeId');
    select.innerHTML = '<option value="">Select Employee...</option>';
    
    try {
        const employees = await db.fetchAllEmployees();
        employees.forEach(emp => {
            const opt = document.createElement('option');
            opt.value = emp.id;
            opt.textContent = emp.full_name + (emp.display_name_ar ? ` - ${emp.display_name_ar}` : '');
            select.appendChild(opt);
        });
    } catch (e) {
        console.error('Error fetching employees:', e);
    }
    
    modal.classList.add('active', 'show');
    lucide.createIcons();
};

window.submitPayrollNewLoan = async function(e) {
    e.preventDefault();
    const btn = e.target.querySelector('button[type="submit"]');
    const originalText = btn.innerHTML;
    btn.innerHTML = 'Saving...';
    btn.disabled = true;
    
    const employee_id = document.getElementById('payrollLoanEmployeeId').value;
    const requested_amount = parseFloat(document.getElementById('payrollLoanAmount').value);
    const monthly_installment = parseFloat(document.getElementById('payrollLoanInstallment').value);
    
    const res = await db.saveEmployeeLoan({
        employee_id,
        requested_amount,
        monthly_installment,
        remaining_balance: requested_amount,
        status: 'APPROVED'
    });
    
    btn.innerHTML = originalText;
    btn.disabled = false;
    
    if (res.success) {
        showToast('Loan added successfully', 'success');
        document.getElementById('payrollNewLoanModal').classList.remove('active', 'show');
        if (window.currentPayrollTab === 'loans') {
            window.switchPayrollTab('loans');
        }
    } else {
        showToast(res.error?.message || 'Error adding loan', 'danger');
    }
};


window.downloadPayrollTemplate = async function() {
    const today = new Date();
    const currentMonth = today.getFullYear() + '-' + String(today.getMonth() + 1).padStart(2, '0');
    
    // Fetch active employees
    const { data: profiles, error } = await supabaseClient
        .from('profiles')
        .select('*')
        .eq('status', 'ACTIVE');

    if (error) {
        showToast(error.message || 'Unable to load employees for the payroll template.', 'error');
        return;
    }
        
    let data = [];
    if (profiles && profiles.length > 0) {
        data = profiles.map(u => ({
            "Employee ID": u.id,
            "Employee Name": u.full_name,
            "Month (YYYY-MM)": currentMonth,
            "Base Salary": u.salary || 0,
            "Commission": 0,
            "Overtime Pay": 0,
            "Deductions": 0
        }));
    } else {
        data.push({
            "Employee ID": "example-uuid-here",
            "Employee Name": "John Doe",
            "Month (YYYY-MM)": currentMonth,
            "Base Salary": 5000,
            "Commission": 0,
            "Overtime Pay": 0,
            "Deductions": 0
        });
    }

    const ws = XLSX.utils.json_to_sheet(data);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "Payroll Template");
    XLSX.writeFile(wb, "Payroll_Template_" + currentMonth + ".xlsx");
};

window.handleBulkPayslipUpload = async function(event) {
    const file = event.target.files[0];
    if (!file) return;

    const modal = document.getElementById('payrollProcessingModal');
    const msg = document.getElementById('payrollProcessingMessage');
    if (modal) {
        if(msg) msg.textContent = "Processing Bulk Excel Upload...";
        modal.classList.add('active', 'show');
        modal.style.display = 'flex';
    }

    const reader = new FileReader();
    reader.onload = async function(e) {
        try {
            const data = new Uint8Array(e.target.result);
            const workbook = XLSX.read(data, { type: 'array' });
            const firstSheetName = workbook.SheetNames[0];
            const worksheet = workbook.Sheets[firstSheetName];
            const json = XLSX.utils.sheet_to_json(worksheet);

            const payslips = [];
            for (const row of json) {
                const empId = row["Employee ID"];
                const empName = row["Employee Name"] || "Unknown";
                const monthYear = row["Month (YYYY-MM)"];
                const baseSalary = parseFloat(row["Base Salary"]) || 0;
                const commission = parseFloat(row["Commission"]) || 0;
                const overtimePay = parseFloat(row["Overtime Pay"]) || 0;
                const deductions = parseFloat(row["Deductions"]) || 0;

                if (!empId || !monthYear) continue;

                const netPay = baseSalary + commission + overtimePay - deductions;

                payslips.push({
                    employee_id: empId,
                    employee_name: empName,
                    month_year: monthYear,
                    base_salary: baseSalary,
                    commission: commission,
                    overtime_pay: overtimePay,
                    deductions: deductions,
                    net_pay: netPay
                });
            }

            if (payslips.length === 0) {
                throw new Error("No valid data found in Excel file.");
            }

            const res = await db.saveReleasedPayslips(payslips);
            
            if (modal) {
                modal.classList.remove('active', 'show');
                modal.style.display = 'none';
            }

            if (res.success) {
                if (document.getElementById('successModal')) {
                    const titleEl = document.getElementById('successModalTitle');
                    const msgEl = document.getElementById('successModalMessage');
                    if (titleEl) titleEl.innerText = (window.t && window.t('success')) || 'Success';
                    if (msgEl) msgEl.innerText = 'Bulk upload complete. ' + payslips.length + ' payslips generated!';
                    
                    document.getElementById('successModal').classList.add('active', 'show');
                    if (window.lucide) { window.lucide.createIcons(); }
                } else {
                    window.showAppMessageModal('Bulk upload complete. ' + payslips.length + ' payslips generated!');
                }
                window.switchPayrollTab('released');
            } else {
                window.showAppMessageModal("Failed to upload payslips.");
            }
        } catch (error) {
            console.error(error);
            if (modal) {
                modal.classList.remove('active', 'show');
                modal.style.display = 'none';
            }
            window.showAppMessageModal("Error processing Excel file: " + error.message);
        }
        
        event.target.value = ''; // Reset input
    };
    reader.readAsArrayBuffer(file);
};
