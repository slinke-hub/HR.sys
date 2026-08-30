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
window.navigateToContract = function (employeeId, empName) {
    if (!window.canCurrentUserEditContracts()) {
        showToast('Only an HR Manager or Administrator can edit contracts.', 'danger');
        return;
    }
    currentContractEmployeeId = employeeId;
    currentContractEmployeeName = empName;
    currentView = 'contract';
    renderView('contract');
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
                showToast(`Unable to upload ${file.name}. ` + (uploadResult.error?.message || ''), 'warning');
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
                if (!documentResult.success) showToast(`Contract saved, but ${doc.name} could not be indexed.`, 'warning');
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
        currentView = 'users';
        renderView('users');