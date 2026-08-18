// Contract Form UI module

const escapeContractHTML = (value) => String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');

window.renderContractForm = async function() {
    // We expect window.currentContractEmployeeId to be set
    const employeeId = window.currentContractEmployeeId;
    
    // Fetch employee data
    const employee = await db.getUserProfile(employeeId);
    if (!employee) {
        return '<div class="card" style="padding:2rem">Employee not found.</div>';
    }
    // Fetch establishment settings
    const estSettings = await db.fetchEstablishmentSettings() || {
        employer_name_ar: 'اسم المنشأة',
        employer_name_en: 'Establishment Name',
        commercial_registration: '0000000000',
        unified_establishment_number: '7000000000'
    };
    const contractSettings = await db.fetchContractSettings() || {
        max_probation_days: 180
    };
    const isNonSaudi = Boolean(employee.nationality && employee.nationality !== 'Saudi');

    // Calculate Dynamic values
    const today = new Date().toISOString().split('T')[0];

    return `
    <div class="contract-form-container">
        <div class="contract-header">
            <h2>Create Employment Contract</h2>
            <p>Employee: ${escapeContractHTML(employee.full_name || 'Employee')}</p>
        </div>

        <form id="saudiContractForm" class="saudi-contract-form">
            <input type="hidden" id="contract_employee_id" value="${escapeContractHTML(employeeId)}">
            
            <div class="contract-section">
                <h3>1. Employer Details</h3>
                <div class="form-grid">
                    <div class="form-group">
                        <label>Employer Name (Arabic)</label>
                        <input type="text" id="employer_name_ar" value="${escapeContractHTML(estSettings.employer_name_ar)}" required>
                    </div>
                    <div class="form-group">
                        <label>Employer Name (English)</label>
                        <input type="text" id="employer_name_en" value="${escapeContractHTML(estSettings.employer_name_en)}" required>
                    </div>
                    <div class="form-group">
                        <label>CR Number</label>
                        <input type="text" id="cr_number" value="${escapeContractHTML(estSettings.commercial_registration)}" required>
                    </div>
                </div>
            </div>

            <div class="contract-section">
                <h3>2. Employee Details</h3>
                <div class="form-grid">
                    <div class="form-group">
                        <label>Employee Name</label>
                        <input type="text" id="emp_name" value="${escapeContractHTML(employee.full_name)}" required>
                    </div>
                    <div class="form-group">
                        <label>Nationality</label>
                        <select id="emp_nationality" onchange="window.handleNationalityChange(this.value)">
                            <option value="SA" ${!isNonSaudi ? 'selected' : ''}>Saudi</option>
                            <option value="NON_SA" ${isNonSaudi ? 'selected' : ''}>Non-Saudi</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>Identity (Iqama/National ID)</label>
                        <input type="text" id="emp_identity" value="${escapeContractHTML(employee.iqama_number)}" required>
                    </div>
                </div>
            </div>

            <div class="contract-section">
                <h3>3. Job Details</h3>
                <div class="form-grid">
                    <div class="form-group">
                        <label>Job Title</label>
                        <input type="text" id="job_title" value="${escapeContractHTML(employee.job_title)}" required>
                    </div>
                    <div class="form-group">
                        <label>Work Arrangement</label>
                        <select id="work_arrangement">
                            <option value="On-site">On-site</option>
                            <option value="Remote">Remote</option>
                            <option value="Hybrid">Hybrid</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>Commencement Date</label>
                        <input type="date" id="commencement_date" value="${today}" required>
                    </div>
                </div>
            </div>

            <div class="contract-section">
                <h3>4. Contract Terms</h3>
                <div class="form-grid">
                    <div class="form-group">
                        <label>Contract Type</label>
                        <select id="contract_type" onchange="window.handleContractTypeChange(this.value)" ${isNonSaudi ? 'disabled' : ''}>
                            <option value="Indefinite-term" ${!isNonSaudi ? 'selected' : ''}>Indefinite-term</option>
                            <option value="Fixed-term" ${isNonSaudi ? 'selected' : ''}>Fixed-term</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>End Date</label>
                        <input type="date" id="end_date" ${isNonSaudi ? 'required' : ''}>
                        <small class="hint" id="endDateHint">Required for Fixed-term</small>
                    </div>
                </div>
            </div>

            <div class="contract-section">
                <h3>5. Probation Period</h3>
                <div class="form-grid">
                    <div class="form-group" style="justify-content: center;">
                        <label>
                            <input type="checkbox" id="probation_enabled" onchange="window.toggleProbation(this.checked)"> 
                            Include Probation Period
                        </label>
                    </div>
                    <div class="form-group">
                        <label>Probation Days</label>
                        <input type="number" id="probation_days" min="1" max="${Number(contractSettings.max_probation_days) || 180}" disabled>
                    </div>
                </div>
            </div>

            <div class="contract-section">
                <h3>6. Financial Terms</h3>
                <div class="form-grid">
                    <div class="form-group">
                        <label>Basic Wage (SAR)</label>
                        <input type="number" id="basic_wage" min="0" step="0.01" value="${Number(employee.base_salary) || 0}" oninput="window.calculateTotalSalary()" required>
                    </div>
                    <div class="form-group">
                        <label>Housing Allowance (SAR)</label>
                        <input type="number" id="housing_allowance" min="0" step="0.01" value="0" oninput="window.calculateTotalSalary()">
                    </div>
                    <div class="form-group">
                        <label>Transport Allowance (SAR)</label>
                        <input type="number" id="transport_allowance" min="0" step="0.01" value="0" oninput="window.calculateTotalSalary()">
                    </div>
                    <div class="form-group total-wage">
                        <label>Total Monthly Wage:</label>
                        <span id="total_wage_display" style="font-weight: bold; font-size: 1.2em;">0 SAR</span>
                    </div>
                </div>
            </div>

            <div class="contract-actions" style="margin-top: 2rem; display: flex; gap: 1rem; justify-content: flex-end;">
                <button type="button" class="btn btn-secondary" onclick="window.saveContractDraft()">Save Draft</button>
                <button type="button" class="btn btn-primary" onclick="window.submitContract()">Create Contract</button>
            </div>
        </form>
    </div>
    
    <style>
        .contract-form-container { max-width: 800px; margin: 0 auto; padding: 2rem; background: var(--color-bg-surface); border-radius: var(--radius-md); box-shadow: var(--shadow-sm); }
        .contract-section { margin-bottom: 2rem; padding-bottom: 1rem; border-bottom: 1px solid var(--color-border); }
        .contract-section h3 { margin-bottom: 1rem; color: var(--color-primary); }
        .form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; }
        .form-group { display: flex; flex-direction: column; gap: 0.5rem; }
        .form-group input, .form-group select { padding: 0.5rem; border: 1px solid var(--color-border); border-radius: var(--radius-sm); }
        .total-wage { align-items: flex-end; justify-content: flex-end; }
        .hint { font-size: 0.8rem; color: var(--color-text-muted); }
    </style>
    `;
};

window.handleNationalityChange = function(val) {
    const typeSelect = document.getElementById('contract_type');
    const endDate = document.getElementById('end_date');
    if (val === 'NON_SA') {
        typeSelect.value = 'Fixed-term';
        typeSelect.disabled = true;
        endDate.required = true;
    } else {
        typeSelect.disabled = false;
        endDate.required = (typeSelect.value === 'Fixed-term');
    }
};

window.handleContractTypeChange = function(val) {
    const endDate = document.getElementById('end_date');
    endDate.required = (val === 'Fixed-term');
};

window.toggleProbation = function(checked) {
    const days = document.getElementById('probation_days');
    days.disabled = !checked;
    if (checked) days.required = true;
    else days.value = '';
};

window.calculateTotalSalary = function() {
    const basic = parseFloat(document.getElementById('basic_wage').value) || 0;
    const housing = parseFloat(document.getElementById('housing_allowance').value) || 0;
    const transport = parseFloat(document.getElementById('transport_allowance').value) || 0;
    document.getElementById('total_wage_display').innerText = (basic + housing + transport) + ' SAR';
};

window.getContractFormData = function(status = 'Draft') {
    const nationality = document.getElementById('emp_nationality').value;
    const contractType = document.getElementById('contract_type').value;
    const basicWage = parseFloat(document.getElementById('basic_wage').value) || 0;
    const housingAllowance = parseFloat(document.getElementById('housing_allowance').value) || 0;
    const transportationAllowance = parseFloat(document.getElementById('transport_allowance').value) || 0;
    const probationDays = document.getElementById('probation_enabled').checked
        ? parseInt(document.getElementById('probation_days').value, 10) || 0
        : 0;
    return {
        employee_id: document.getElementById('contract_employee_id').value,
        employer_name_en: document.getElementById('employer_name_en').value,
        employer_name_ar: document.getElementById('employer_name_ar').value,
        commercial_registration: document.getElementById('cr_number').value,
        
        employee_name_en: document.getElementById('emp_name').value,
        nationality: nationality === 'SA' ? 'Saudi' : 'Non-Saudi',
        is_saudi: nationality === 'SA',
        identity_number: document.getElementById('emp_identity').value,
        
        job_title_en: document.getElementById('job_title').value,
        job_title: document.getElementById('job_title').value,
        work_arrangement: document.getElementById('work_arrangement').value,
        employment_commencement_date: document.getElementById('commencement_date').value,
        start_date: document.getElementById('commencement_date').value,
        
        contract_duration_desc: contractType,
        contract_type: contractType,
        end_date: document.getElementById('end_date').value || null,
        
        probation_enabled: document.getElementById('probation_enabled').checked,
        probation_period_days: probationDays,
        
        basic_monthly_wage: basicWage,
        salary: basicWage,
        housing_benefit: String(housingAllowance),
        housing_allowance: housingAllowance,
        transportation_benefit: String(transportationAllowance),
        transportation_allowance: transportationAllowance,
        contract_language: 'bilingual',
        
        status: status
    };
};

window.saveContractDraft = async function() {
    const data = window.getContractFormData('Draft');
    const res = await db.createContract(data);
    if (res.success) {
        window.showToast(t('contract_saved_draft') || 'Contract saved as draft.', 'success');
        renderView('employees');
    } else {
        window.showToast('Failed to save draft.', 'danger');
    }
};

window.submitContract = async function() {
    const form = document.getElementById('saudiContractForm');
    if (!form.checkValidity()) {
        form.reportValidity();
        return;
    }
    
    // Custom validation
    if (document.getElementById('emp_nationality').value === 'NON_SA' && document.getElementById('contract_type').value !== 'Fixed-term') {
        window.showToast('Non-Saudi employees must have a Fixed-term contract.', 'danger');
        return;
    }
    
    const data = window.getContractFormData('Pending Employee Approval');
    const res = await db.createContract(data);
    if (res.success) {
        window.showToast(t('contract_submitted') || 'Contract submitted successfully.', 'success');
        renderView('employees');
    } else {
        window.showToast('Failed to submit contract.', 'danger');
    }
};

window.renderContractPrintPreview = async function() {
    const contractId = window.currentContractIdToPrint;
    const employeeId = window.currentEmployeeIdToPrint;
    
    if (!contractId || !employeeId) {
        return `<div style="padding: 20px;">Error: No contract selected for printing. <button onclick="renderView('employees')">Back</button></div>`;
    }

    const contracts = await db.fetchContracts(employeeId);
    const contract = contracts.find(c => c.id === contractId);
    const employee = await db.getUserProfile(employeeId);
    const estSettings = await db.fetchEstablishmentSettings() || {
        employer_name_ar: 'شركة تجريبية',
        employer_name_en: 'Demo Company'
    };
    
    if (!contract || !employee) {
        return `<div style="padding: 20px;">Error: Contract or Employee not found. <button onclick="renderView('employees')">Back</button></div>`;
    }

    // Masking Iqama for non-admins
    let iqamaNumber = employee.iqama_number || 'N/A';
    if (contract.identity_number) iqamaNumber = contract.identity_number;
    if (!window.canViewFullContractIdentity && iqamaNumber !== 'N/A') {
        iqamaNumber = iqamaNumber.substring(0, 3) + '*****' + iqamaNumber.substring(iqamaNumber.length - 2);
    }

    // Language handling
    const lang = contract.contract_language || 'arabic';
    const isRTL = lang === 'arabic' || lang === 'bilingual';
    const dir = isRTL ? 'rtl' : 'ltr';

    return `
        <div class="print-preview-container" style="direction: ${dir}; text-align: ${isRTL ? 'right' : 'left'};">
            <!-- Non-printable actions -->
            <div class="print-actions no-print" style="margin-bottom: 20px; display: flex; gap: 10px; justify-content: flex-end; padding: 15px; background: #f8f9fa; border-bottom: 1px solid #ddd;">
                <button class="btn-secondary" onclick="renderView('employees')">Back</button>
                <button class="btn-primary" onclick="window.print()"><i data-lucide="printer"></i> Print Document</button>
            </div>
            
            <!-- Printable A4 Area -->
            <div class="print-page" style="max-width: 210mm; margin: 0 auto; background: white; padding: 20mm; box-shadow: 0 0 10px rgba(0,0,0,0.1); color: #000; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;">
                <div class="print-header" style="text-align: center; margin-bottom: 30px; border-bottom: 2px solid #000; padding-bottom: 10px;">
                    <h1 style="font-size: 24px; margin: 0;">${isRTL ? estSettings.employer_name_ar : estSettings.employer_name_en}</h1>
                    <h2 style="font-size: 18px; margin: 10px 0 0 0;">${lang === 'arabic' ? 'عقد عمل' : 'Employment Contract'}</h2>
                </div>
                
                <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px; font-size: 14px;">
                    <tr>
                        <td style="padding: 5px; font-weight: bold; width: 25%;">${isRTL ? 'رقم العقد' : 'Contract No'}:</td>
                        <td style="padding: 5px;">${contract.id.split('-')[0]}</td>
                        <td style="padding: 5px; font-weight: bold; width: 25%;">${isRTL ? 'التاريخ' : 'Date'}:</td>
                        <td style="padding: 5px;">${new Date(contract.created_at).toLocaleDateString()}</td>
                    </tr>
                    <tr>
                        <td style="padding: 5px; font-weight: bold;">${isRTL ? 'حالة العقد' : 'Status'}:</td>
                        <td style="padding: 5px;">${contract.status}</td>
                    </tr>
                </table>
                
                <div style="margin-bottom: 20px;">
                    <h3 style="border-bottom: 1px solid #ccc; padding-bottom: 5px;">${isRTL ? 'الطرف الأول (صاحب العمل)' : 'First Party (Employer)'}</h3>
                    <p>${isRTL ? estSettings.employer_name_ar : estSettings.employer_name_en}</p>
                </div>
                
                <div style="margin-bottom: 20px;">
                    <h3 style="border-bottom: 1px solid #ccc; padding-bottom: 5px;">${isRTL ? 'الطرف الثاني (العامل)' : 'Second Party (Employee)'}</h3>
                    <table style="width: 100%; font-size: 14px;">
                        <tr><td style="padding: 3px; font-weight:bold; width:30%;">${isRTL ? 'الاسم' : 'Name'}:</td><td>${employee.full_name}</td></tr>
                        <tr><td style="padding: 3px; font-weight:bold;">${isRTL ? 'الجنسية' : 'Nationality'}:</td><td>${employee.nationality || 'N/A'}</td></tr>
                        <tr><td style="padding: 3px; font-weight:bold;">${isRTL ? 'رقم الهوية/الإقامة' : 'ID/Iqama'}:</td><td>${iqamaNumber}</td></tr>
                        <tr><td style="padding: 3px; font-weight:bold;">${isRTL ? 'الرقم الوظيفي' : 'Employee ID'}:</td><td>${employee.id}</td></tr>
                        <tr><td style="padding: 3px; font-weight:bold;">${isRTL ? 'المسمى الوظيفي' : 'Job Title'}:</td><td>${contract.job_title_en || contract.job_title || employee.job_title || 'N/A'}</td></tr>
                    </table>
                </div>

                <div style="margin-bottom: 20px;">
                    <h3 style="border-bottom: 1px solid #ccc; padding-bottom: 5px;">${isRTL ? 'تفاصيل العقد' : 'Contract Details'}</h3>
                    <table style="width: 100%; font-size: 14px;">
                        <tr><td style="padding: 3px; font-weight:bold; width:30%;">${isRTL ? 'نوع العقد' : 'Contract Type'}:</td><td>${contract.contract_duration_desc || contract.contract_type}</td></tr>
                        <tr><td style="padding: 3px; font-weight:bold;">${isRTL ? 'تاريخ المباشرة' : 'Commencing Date'}:</td><td>${contract.employment_commencement_date || contract.start_date}</td></tr>
                        ${contract.end_date ? `<tr><td style="padding: 3px; font-weight:bold;">${isRTL ? 'تاريخ الانتهاء' : 'End Date'}:</td><td>${contract.end_date}</td></tr>` : ''}
                        <tr><td style="padding: 3px; font-weight:bold;">${isRTL ? 'فترة التجربة (أيام)' : 'Probation (Days)'}:</td><td>${contract.probation_days || 0}</td></tr>
                    </table>
                </div>

                <div style="margin-bottom: 20px;">
                    <h3 style="border-bottom: 1px solid #ccc; padding-bottom: 5px;">${isRTL ? 'التعويضات' : 'Compensation'}</h3>
                    <table style="width: 100%; font-size: 14px; border: 1px solid #ddd; border-collapse: collapse;">
                        <tr style="background: #f8f9fa;">
                            <th style="padding: 8px; border: 1px solid #ddd; text-align: ${isRTL ? 'right' : 'left'};">${isRTL ? 'البند' : 'Item'}</th>
                            <th style="padding: 8px; border: 1px solid #ddd; text-align: ${isRTL ? 'right' : 'left'};">${isRTL ? 'المبلغ' : 'Amount'} (SAR)</th>
                        </tr>
                        <tr><td style="padding: 8px; border: 1px solid #ddd;">${isRTL ? 'الأجر الأساسي' : 'Basic Wage'}</td><td style="padding: 8px; border: 1px solid #ddd;">${contract.basic_monthly_wage ?? contract.salary ?? 0}</td></tr>
                        <tr><td style="padding: 8px; border: 1px solid #ddd;">${isRTL ? 'بدل السكن' : 'Housing Allowance'}</td><td style="padding: 8px; border: 1px solid #ddd;">${contract.housing_allowance}</td></tr>
                        <tr><td style="padding: 8px; border: 1px solid #ddd;">${isRTL ? 'بدل النقل' : 'Transport Allowance'}</td><td style="padding: 8px; border: 1px solid #ddd;">${contract.transportation_allowance ?? contract.transportation_benefit ?? 0}</td></tr>
                        <tr style="font-weight: bold; background: #eee;">
                            <td style="padding: 8px; border: 1px solid #ddd;">${isRTL ? 'إجمالي الراتب' : 'Total Compensation'}</td>
                            <td style="padding: 8px; border: 1px solid #ddd;">${Number(contract.basic_monthly_wage ?? contract.salary ?? 0) + Number(contract.housing_allowance || 0) + Number(contract.transportation_allowance || 0)}</td>
                        </tr>
                    </table>
                </div>
                
                <div class="signatures avoid-page-break" style="margin-top: 50px; display: flex; justify-content: space-between;">
                    <div style="width: 45%; text-align: center;">
                        <p style="font-weight: bold;">${isRTL ? 'الطرف الأول' : 'First Party'}</p>
                        <div style="border-bottom: 1px solid #000; margin-top: 40px; height: 30px;"></div>
                        <p style="margin-top: 5px; font-size: 12px;">${isRTL ? 'الختم والتوقيع' : 'Stamp & Signature'}</p>
                    </div>
                    <div style="width: 45%; text-align: center;">
                        <p style="font-weight: bold;">${isRTL ? 'الطرف الثاني' : 'Second Party'}</p>
                        <div style="border-bottom: 1px solid #000; margin-top: 40px; height: 30px;"></div>
                        <p style="margin-top: 5px; font-size: 12px;">${isRTL ? 'التوقيع' : 'Signature'}</p>
                    </div>
                </div>
            </div>
        </div>
    `;
};
