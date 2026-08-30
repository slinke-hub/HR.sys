            await db.triggerWebhooks('task_deleted', { task_id: id });
            document.getElementById('editTaskModal').classList.remove('active');
            renderView(currentView === 'tasks_v2' ? 'tasks_v2' : 'tasks');
        }
    });
};

document.addEventListener('dragend', function (e) {
    if (e.target && e.target.classList && e.target.classList.contains('task-item-card')) {
        e.target.style.opacity = '1';
    }
});

// Router
// ==========================================
// Employees & Contracts (HR View)
// ==========================================
window.navigateToContract = async function (employeeId, empName) {
    if (!window.canCurrentUserEditContracts()) {
        showToast('Only an HR Manager or Administrator can edit contracts.', 'danger');
        return;
    }
    currentContractEmployeeId = employeeId;
    currentContractEmployeeName = empName;
    
    let modal = document.getElementById('contractEditModal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'contractEditModal';
        modal.className = 'modal';
        document.body.appendChild(modal);
    }
    
    const htmlContent = await window.renderContractPage();
    
    modal.innerHTML = `
        <div class="modal-content" style="max-width: 900px; width: 90%; background: var(--color-bg-surface); padding: 0; max-height: 90vh; overflow-y: auto;">
            <div class="modal-header" style="position: sticky; top: 0; background: var(--color-bg-surface); z-index: 10; padding: 1.5rem; border-bottom: 1px solid var(--color-border); display: flex; justify-content: space-between; align-items: center;">
                <h2 style="margin:0">${t('users_contract') || 'Contract'} - ${empName}</h2>
                <button class="close-modal" onclick="document.getElementById('contractEditModal').style.display = 'none'">&times;</button>
            </div>
            <div class="modal-body contract-modal-body" style="padding: 1.5rem; padding-top: 0.5rem;">
                <style>
                    .contract-modal-body .page-header { display: none !important; }
                    .contract-modal-body { text-align: left; }
                </style>
                ${htmlContent}
            </div>
        </div>
    `;
    if (window.lucide && lucide.createIcons) lucide.createIcons();
    modal.style.display = 'block';
}

window.handleSaveContract = async function (e) {
    e.preventDefault();
    const viewerProfile = await db.getUserProfile(currentUser?.id);
    if (!window.canCurrentUserEditContracts(viewerProfile)) {
        showToast('Only an HR Manager or Administrator can edit contracts.', 'danger');
        return;
    }
    const jobTitle = document.getElementById('contractJobTitle')?.value || '';
    const departmentSelect = document.getElementById('contractDepartment');
    const departmentId = departmentSelect?.value || null;
    const departmentName = departmentSelect?.selectedOptions?.[0]?.textContent || '';
    const policyFiles = Array.from(document.getElementById('contractPolicyDocument')?.files || []);
    let policyUrl = document.getElementById('existingContractPolicyUrl')?.value || null;
    const uploadedDocs = [];

    if (policyFiles.length > 0) {
        for (const file of policyFiles) {
            const uploadResult = await db.uploadContractPolicy(currentContractEmployeeId, file);
            if (!uploadResult.success) {
                showToast(\`Unable to upload \${file.name}. \` + (uploadResult.error?.message || ''), 'warning');
            } else {
                if (!policyUrl) policyUrl = uploadResult.url; // Use the first uploaded one as the main policy url if not set
                uploadedDocs.push({ url: uploadResult.url, name: file.name });
            }
        }
    }
    const contractData = {
        employee_id: currentContractEmployeeId,
        contract_type: document.getElementById('contractType').value,
        nationality: document.getElementById('contractNationality')?.value || 'Saudi',
        department_id: departmentId,
        department: departmentName,
        job_title_ar: jobTitle,
        job_title_en: jobTitle,
        identity_number: document.getElementById('contractIdentityNumber')?.value.trim() || null,
        employee_phone: document.getElementById('contractEmployeePhone')?.value.trim() || null,

        start_date: document.getElementById('contractStartDate').value,
        end_date: document.getElementById('contractEndDate').value || null,
        salary: document.getElementById('contractSalary').value || null,
        housing_allowance: document.getElementById('contractHousing').value || null,
        transportation_allowance: document.getElementById('contractTransport').value || null,
        other_allowances: document.getElementById('contractOther').value || null,
        working_hours: document.getElementById('contractHours').value || null,
        probation_period_days: document.getElementById('contractProbation').value || null,
        notice_period_days: document.getElementById('contractNotice').value || null,
        annual_leave_days: document.getElementById('contractLeave').value || null,
        primary_workplace: document.getElementById('contractWorkplace').value || null,
        weekly_rest_day: document.getElementById('contractRestDays').value || null,
        confidentiality_policy_url: policyUrl,
        status: document.getElementById('contractStatus').value
    };

    const existingContract = await db.fetchContractByEmployeeId(currentContractEmployeeId);
    if (existingContract && existingContract.id) {
        contractData.id = existingContract.id;
    }

    const { success, data: savedContract, error } = await db.upsertContract(contractData);
    if (success) {
        for (const doc of uploadedDocs) {
            if (savedContract?.id) {
                const documentResult = await db.addContractDocument(savedContract.id, currentContractEmployeeId, doc.url, doc.name, 'confidentiality_policy', currentUser?.id || null);
                if (!documentResult.success) showToast(\`Contract saved, but \${doc.name} could not be indexed.\`, 'warning');
            }
        }
        if (jobTitle) {
            const profileSync = await db.updateUserJobTitle(currentContractEmployeeId, jobTitle, departmentId);
            if (!profileSync.success) {
                showToast(profileSync.error?.message || 'Contract saved, but the Employee Directory could not be synchronized.', 'warning');
                return;
            }
            const derivedRole = /supervisor/i.test(jobTitle) ? 'SUPERVISOR' : /manager/i.test(jobTitle) ? 'MANAGER' : 'EMPLOYEE';
            const roleSync = await db.updateUserRole(currentContractEmployeeId, derivedRole);
            if (!roleSync.success) {
                showToast(roleSync.error?.message || 'Contract saved, but the employee role could not be synchronized.', 'warning');
                return;
            }
        }
        await db.updateUserProfile(currentContractEmployeeId, {
            nationality: contractData.nationality,
            base_salary: contractData.salary,
            display_name_ar: document.getElementById('contractEmployeeNameAr')?.value || null,
            iqama_number: contractData.identity_number,
            phone_number: contractData.employee_phone
        });
        delete window.viewHTMLCache.users;
        delete window.viewHTMLCache.employees;
        showToast(t('toast_contract_saved_successfully'), "success");
        if (document.getElementById('contractEditModal') && document.getElementById('contractEditModal').style.display !== 'none') {
            document.getElementById('contractEditModal').style.display = 'none';
            if (currentView === 'users' || currentView === 'employees') {
                renderView(currentView);
            }
        } else {
            currentView = 'users';
            renderView('users');
        }
