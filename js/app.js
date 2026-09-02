// App State
let currentLang = localStorage.getItem('app_lang') || 'ar';
window.currentLang = currentLang;
let currentTheme = 'light';
let currentView = 'login';
let loginMode = 'login';
let currentUser = null;
let viewHistory = [];
const defaultTranslationsSnapshot = typeof i18n !== 'undefined' ? JSON.parse(JSON.stringify(i18n)) : { en: {}, ar: {} };
if (typeof i18n !== 'undefined') {
    i18n.en.nav_more = 'More';
    i18n.ar.nav_more = 'المزيد';
}

// XSS Protection Utility
function escapeHTML(str) {
    if (!str) return '';
    if (typeof str !== 'string') return str;
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}
window.escapeHTML = escapeHTML;

function formatEmployeeId(value, fallback = '-') {
    const raw = String(value ?? '').trim().replace(/^MQ[-\s]*/i, '');
    if (!raw) return `MQ-${fallback}`;
    return `MQ-${/^\d+$/.test(raw) ? raw.padStart(2, '0') : raw}`;
}
window.formatEmployeeId = formatEmployeeId;
const isMarketingTaskDepartment = value => {
    const normalized = String(value || '').trim();
    return /^marketing(?:\s*&\s*sales)?$/i.test(normalized) || /التسويق|تسويق/.test(normalized);
};
const getCanonicalDepartmentName = department => {
    if (!department) return '';
    if (department.name_en) return department.name_en;
    const savedLanguage = window.currentLang;
    try {
        window.currentLang = 'en';
        return department.name || '';
    } finally {
        window.currentLang = savedLanguage;
    }
};
const getTaskDepartmentLabel = department => {
    const canonicalName = getCanonicalDepartmentName(department);
    const rawLabel = String(department?.name || department?.name_ar || '');
    if (currentLang === 'ar' && (isMarketingTaskDepartment(canonicalName || department?.name) || /مدير\s*تسويق|مشرف\s*مبيعات|مندوب\s*مبيعات|مصمم\s*جرافيك/.test(rawLabel))) return 'التسويق';
    return department?.name || canonicalName;
};

const taskDetailText = (english, arabic) => currentLang === 'ar' ? arabic : english;
const taskDetailValue = (value, type = '') => {
    const raw = String(value || '').trim();
    if (!raw) return taskDetailText('Not set', 'غير محدد');
    const key = raw.toLowerCase().replace(/[\s-]+/g, '_');
    const maps = {
        status: { todo: 'قيد الانتظار', in_progress: 'قيد التنفيذ', review: 'قيد المراجعة', pending_approval: 'بانتظار الموافقة', completed: 'مكتملة', approved: 'معتمدة', rejected: 'مرفوضة' },
        priority: { low: 'منخفضة', medium: 'متوسطة', high: 'عالية', urgent: 'عاجلة', critical: 'حرجة' },
        visibility: { public: 'عام', private: 'خاص', team: 'الفريق' }
    };
    return currentLang === 'ar' ? (maps[type]?.[key] || raw) : raw;
};
const getLocalizedTaskTitle = task => {
    const localized = task?.title_i18n?.[currentLang] || task?.title_i18n?.en || task?.title || '';
    return currentLang === 'ar' && /(?:Ø|Ù|Ã|Â)/.test(localized) ? (task?.title || localized) : localized;
};

function getProfileDisplayName(profile) {
    const candidates = [
        currentLang === 'ar' ? profile?.display_name_ar : null,
        profile?.full_name,
        profile?.display_name,
        currentUser?.email?.split('@')[0],
        t('role_employee')
    ];
    const selectedName = candidates.find(value => typeof value === 'string' && value.trim());
    return selectedName ? selectedName.trim() : '';
}

window.goBack = function () {
    if (viewHistory.length > 1) {
        viewHistory.pop(); // remove current
        const prevView = viewHistory[viewHistory.length - 1];
        currentView = prevView;
        renderView(prevView, true);
    } else {
        const root = 'dashboard';
        currentView = root;
        renderView(root, true);
    }
};

window.showSupervisorTooltip = function () {
    const tooltip = document.getElementById('supervisorTooltip');
    if (tooltip) {
        tooltip.style.display = 'block';
        if (window.supervisorTooltipTimeout) {
            clearTimeout(window.supervisorTooltipTimeout);
        }
        window.supervisorTooltipTimeout = setTimeout(() => {
            tooltip.style.display = 'none';
        }, 5000);
    }
};

window.hideSupervisorTooltip = function () {
    const tooltip = document.getElementById('supervisorTooltip');
    if (tooltip) {
        tooltip.style.display = 'none';
        if (window.supervisorTooltipTimeout) {
            clearTimeout(window.supervisorTooltipTimeout);
        }
    }
};

let currentUserRole = null;
let currentUserProfile = null;
const isTaskAdmin = () => ['ADMIN', 'OWNER', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(String(currentUserRole || '').trim().toUpperCase());
const canInteractWithTask = task => !!task && (isTaskAdmin() || [task.created_by, task.assignee_id, task.supervisor_id, ...(Array.isArray(task.assignee_ids) ? task.assignee_ids : [])].includes(currentUser?.id) || (task.watchers || []).includes(currentUser?.id));
let currentContractEmployeeId = null;
let currentContractEmployeeName = '';
let recentLoginsChannel = null;
let recentLoginsPollInterval = null;

window.canCurrentUserEditContracts = function (profile = currentUserProfile) {
    return String(currentUserRole || '').toUpperCase() === 'ADMIN' ||
        String(profile?.job_title || '').trim().toUpperCase() === 'HR MANAGER';
};

async function syncLegacyLocalProfilePhoto(profile) {
    if (!profile?.id || profile.avatar_url) return profile;
    const localAvatar = localStorage.getItem('user_avatar_' + profile.id);
    if (!localAvatar) return profile;
    const result = await db.updateProfilePhoto(profile.id, localAvatar);
    if (result.success) profile.avatar_url = localAvatar;
    return profile;
}

// ==========================================
// PWA Installation
// ==========================================
let deferredPrompt;

if ('serviceWorker' in navigator) {
    window.addEventListener('load', async () => {
        try {
            const registration = await navigator.serviceWorker.register('/sw.js', { scope: '/' });
            registration.update().catch(() => {});
            console.log('MUQAM HR background service registered.');
        } catch (error) {
            console.warn('Background service registration failed:', error?.message || error);
        }
    });
}

function showInstallBanner() {
    return; // Disabled by user request
}

// User Management Actions
window.showEditUserModal = async (userId) => {
    const [user, loginEmailResult] = await Promise.all([
        db.getUserProfile(userId),
        db.getUserLoginEmail(userId)
    ]);
    if (!user) {
        showToast(t('toast_user_not_found'), "danger");
        return;
    }
    document.getElementById('editUserId').value = user.id;
    document.getElementById('editFullName').value = user.full_name || '';
    document.getElementById('editFullNameAr').value = user.display_name_ar || '';
    document.getElementById('editIqama').value = user.iqama_number || '';
    document.getElementById('editPhone').value = user.phone_number || '';
    document.getElementById('editEmail').value = loginEmailResult?.success ? loginEmailResult.data : '';
    const [departments] = await Promise.all([db.fetchDepartments(), db.fetchJobTitles(true)]);
    const departmentSelect = document.getElementById('editDepartment');
    departmentSelect.innerHTML = '<option value="">Select Department</option>' + departments.map(department => `<option value="${department.id}" ${department.id === user.department_id ? 'selected' : ''}>${escapeHTML(department.name)}</option>`).join('');
    const selectedDepartment = departments.find(department => department.id === user.department_id)?.name || '';
    const jobTitleSelect = document.getElementById('editJobTitle');
    jobTitleSelect.disabled = !selectedDepartment;
    jobTitleSelect.innerHTML = selectedDepartment
        ? companyJobTitleOptions(user.job_title || '', selectedDepartment)
        : '<option value="">Select Department first</option>';
    const currentAvatar = user.avatar_url || localStorage.getItem('user_avatar_' + user.id) || '';
    const avatarPreview = document.getElementById('editAvatarPreview');
    document.getElementById('editAvatarFile').value = '';
    avatarPreview.src = currentAvatar;
    avatarPreview.hidden = !currentAvatar;
    document.getElementById('editRole').value = user.role || 'EMPLOYEE';

    const mgrSelect = document.getElementById('editManagerId');
    mgrSelect.innerHTML = '<option value="">No Manager</option>';
    const users = await db.fetchUsers();
    users.filter(m => m.role === 'MANAGER' || m.role === 'ADMIN').forEach(m => {
        mgrSelect.innerHTML += `<option value="${m.id}" ${user.manager_id === m.id ? 'selected' : ''}>${window.formatEmployeeName(m) || 'Mgr'}</option>`;
    });

    document.getElementById('editUserModal').classList.add('active');
};

window.refreshUserRowInPlace = async function (userId, knownUpdates = null) {
    const cached = (window.currentAdminUsers || []).find(item => item.id === userId);
    const user = knownUpdates ? { ...cached, ...knownUpdates, id: userId } : await db.getUserProfile(userId);
    if (!user) return;
    const index = (window.currentAdminUsers || []).findIndex(item => item.id === userId);
    if (index >= 0) window.currentAdminUsers[index] = { ...window.currentAdminUsers[index], ...user };

    const row = document.querySelector(`[data-user-row="${userId}"]`);
    if (!row) return;
    const details = row.querySelector('[data-user-details]');
    if (details) details.innerHTML = `<div class="directory-employee-name">${escapeHTML(window.formatEmployeeName(user) || 'N/A')}</div>`;
    const employeeId = row.querySelector('[data-user-id]');
    if (employeeId) employeeId.innerHTML = `<span class="directory-employee-id">${escapeHTML(formatEmployeeId(user.emp_index))}</span>`;
    const badge = row.querySelector('[data-user-role-badge]');
    if (badge) {
        badge.className = `status-badge ${user.role === 'ADMIN' ? 'success' : 'info'}`;
        badge.textContent = user.role || 'EMPLOYEE';
    }
    const roleSelect = row.querySelector('[data-user-role-select]');
    if (roleSelect && user.role) roleSelect.value = user.role;
    const managerSelect = row.querySelector('[data-user-manager-select]');
    if (managerSelect) managerSelect.value = user.manager_id || '';
    const departmentSelect = row.querySelector('[data-directory-department]');
    if (departmentSelect && Object.prototype.hasOwnProperty.call(user, 'department_id')) departmentSelect.value = user.department_id || '';
    const titleSelect = row.querySelector('[data-directory-job-title]');
    if (titleSelect && user.job_title) titleSelect.value = user.job_title;
};

window.handleUpdateUser = async (e) => {
    e.preventDefault();
    const userId = document.getElementById('editUserId').value;
    const email = document.getElementById('editEmail').value.trim().toLowerCase();
    const updates = {
        full_name: document.getElementById('editFullName').value,
        display_name_ar: document.getElementById('editFullNameAr').value,
        iqama_number: document.getElementById('editIqama').value,
        phone_number: document.getElementById('editPhone').value,
        job_title: document.getElementById('editJobTitle').value,
        department_id: document.getElementById('editDepartment').value || null,
        role: document.getElementById('editRole').value,
        manager_id: document.getElementById('editManagerId').value || null
    };

    if (updates.role === 'OWNER') {
        updates.role = 'ADMIN';
        updates.job_title = 'Owner';
    }

    const photoFile = document.getElementById('editAvatarFile')?.files?.[0];
    if (photoFile) {
        try {
            updates.avatar_url = await compressProfileImage(photoFile);
        } catch (error) {
            showToast(error.message || 'Unable to process the selected profile photo.', 'danger');
            return;
        }
    }
    const loginUpdate = await db.updateUserLoginCredentials(userId, email);
    if (!loginUpdate.success) {
        showToast(loginUpdate.error?.message || 'Failed to update the login email.', 'danger');
        return;
    }
    const res = await db.updateUserProfile(userId, updates);
    if (res.success) {
        if (updates.avatar_url) localStorage.setItem('user_avatar_' + userId, updates.avatar_url);
        // Invalidate view cache
        if (window.viewHTMLCache) {
            delete window.viewHTMLCache.dashboard;
            delete window.viewHTMLCache.users;
        }
        showToast(t('toast_user_updated_successfully'), "success");
        document.getElementById('editUserModal').classList.remove('active');
        await window.refreshUserRowInPlace(userId, updates);
    } else {
        showToast(res.error?.message || t('toast_failed_to_update_user'), "danger");
    }
};

window.showAdminPasswordResetModal = (userId) => {
    if (currentUserRole !== 'ADMIN') {
        showToast(t('password_reset_admin_only'), 'danger');
        return;
    }

    const user = (window.currentAdminUsers || []).find(item => item.id === userId);
    if (!user) {
        showToast(t('toast_user_not_found'), 'danger');
        return;
    }

    const form = document.getElementById('adminPasswordResetForm');
    form.reset();
    document.getElementById('adminPasswordResetUserId').value = user.id;
    document.getElementById('adminPasswordResetUserName').textContent = window.formatEmployeeName(user) || formatEmployeeId(user.emp_index, '');
    document.getElementById('adminNewPassword').type = 'password';
    document.getElementById('adminConfirmPassword').type = 'password';
    document.getElementById('adminPasswordResetModal').classList.add('show');
    setTimeout(() => document.getElementById('adminNewPassword').focus(), 0);
    if (window.lucide) window.lucide.createIcons();
};

window.closeAdminPasswordResetModal = () => {
    const modal = document.getElementById('adminPasswordResetModal');
    const form = document.getElementById('adminPasswordResetForm');
    if (form) form.reset();
    if (modal) modal.classList.remove('show');
};

window.toggleAdminPasswordVisibility = (showPasswords) => {
    const inputType = showPasswords ? 'text' : 'password';
    document.getElementById('adminNewPassword').type = inputType;
    document.getElementById('adminConfirmPassword').type = inputType;
};

window.handleAdminPasswordReset = async (event) => {
    event.preventDefault();
    if (currentUserRole !== 'ADMIN') {
        showToast(t('password_reset_admin_only'), 'danger');
        return;
    }

    const userId = document.getElementById('adminPasswordResetUserId').value;
    const newPassword = document.getElementById('adminNewPassword').value;
    const confirmPassword = document.getElementById('adminConfirmPassword').value;

    if (newPassword.length < 8) {
        showToast(t('password_reset_minimum'), 'warning');
        return;
    }
    if (newPassword !== confirmPassword) {
        showToast(t('password_reset_mismatch'), 'warning');
        return;
    }

    const submitButton = document.getElementById('adminPasswordResetSubmit');
    submitButton.disabled = true;
    try {
        const result = await db.resetUserPassword(userId, newPassword);
        if (!result.success) throw result.error || new Error(t('toast_failed_to_reset_password'));
        window.closeAdminPasswordResetModal();
        showToast(t('password_reset_success'), 'success');
    } catch (error) {
        showToast(error?.message || t('toast_failed_to_reset_password'), 'danger');
    } finally {
        submitButton.disabled = false;
    }
};

// Backward-compatible entry point used by older cached markup.
window.handleResetUserPassword = window.showAdminPasswordResetModal;

window.handleDeleteUser = (userId) => {
    window.showConfirmModal(t('modal_title_delete_user'), 'This permanently removes the user and their data. Their contract will be moved to Archived Contracts.', async () => {
        const result = await db.deleteUser(userId);
        if (result.success) {
            const archivedCount = Number(result.data?.archived_contracts || 0);
            showToast(`User deleted successfully. ${archivedCount} contract${archivedCount === 1 ? '' : 's'} archived.`, "success");
            renderView('users');
        } else {
            showToast(result.error?.message || t('toast_failed_to_delete_user'), "danger");
        }
    });
};

// Kept for backward compatibility if called directly
window.closeDeleteUserModal = () => {
    const modal = document.getElementById('deleteUserModal');
    if (modal) modal.classList.remove('active');
};
window.executeDeleteUser = async () => { };

// Requests Page Handlers
window.renderRequests = async () => {
    const isEmployee = currentUserRole === 'EMPLOYEE';
    const requests = await db.fetchRequests(currentUser);

    let tableRows = requests.map(r => {
        let workflowHTML = '';
        let canApprove = false;

        if (r.workflow && r.workflow.steps) {
            const steps = r.workflow.steps;
            const currentStep = r.workflow.current_step;

            // Check if current user is the approver for the active step
            const activeStep = steps.find(s => s.step_order === currentStep);
            if (activeStep && activeStep.approver_id === currentUser?.id && r.workflow.status === 'PENDING') {
                canApprove = true;
            }

            // Build Progress Bar HTML
            let stepsHTML = steps.map((s, idx) => {
                const isActive = s.step_order === currentStep && r.workflow.status === 'PENDING';
                const isPassed = s.step_order < currentStep || r.workflow.status === 'APPROVED';
                const isRejected = r.workflow.status === 'REJECTED' && s.step_order === currentStep;

                let stateClass = '';
                if (isActive) stateClass = 'workflow-step-active';
                if (isPassed) stateClass = 'workflow-step-passed';
                if (isRejected) stateClass = 'workflow-step-rejected';

                const stageName = (s.stage_key || '').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());

                return `
                    <div class="workflow-step ${stateClass}">
                        <div class="workflow-step-indicator" title="${stageName}">
                            ${isPassed ? '<i data-lucide="check" style="width:12px; height:12px;"></i>' : (isRejected ? '<i data-lucide="x" style="width:12px; height:12px;"></i>' : idx + 1)}
                        </div>
                        <div class="workflow-step-label">${stageName}</div>
                    </div>
                `;
            }).join('');

            workflowHTML = `
                <div class="workflow-progress">
                    ${stepsHTML}
                </div>
            `;
        } else {
            // Fallback for legacy requests without workflow
            canApprove = !isEmployee && r.status === 'Pending' && r.employee_id !== currentUser?.id;
        }

        return `
        <tr>
            <td>${new Date(r.created_at).toLocaleDateString()}</td>
            <td>${window.formatEmployeeName(r.profiles) || 'Unknown'}</td>
            <td>
                ${r.request_type}
                ${r.loan_amount ? `<br><small style="color:var(--color-text-secondary)">SAR ${r.loan_amount}</small>` : ''}
                ${workflowHTML}
            </td>
            <td>${r.leave_type || '-'}</td>
            <td><span class="status-badge ${r.status === 'Approved' || r.status === 'APPROVED' ? 'success' : (r.status === 'Rejected' || r.status === 'REJECTED' ? 'danger' : 'info')}">${r.status}</span></td>
            <td>
                ${canApprove ? `
                    <button class="btn-primary" style="padding: 0.2rem 0.5rem; font-size:0.8rem" onclick="updateRequestStatus('${r.id}', 'Approved')">${t('ui_approve')}</button>
                    <button class="btn-primary" style="background:var(--color-danger); padding: 0.2rem 0.5rem; font-size:0.8rem" onclick="updateRequestStatus('${r.id}', 'Rejected')">${t('ui_reject')}</button>
                ` : ''}
            </td>
        </tr>
        `;
    }).join('');

    if (requests.length === 0) {
        tableRows = `<tr><td colspan="6" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">${t('req_no_found') || 'No requests found.'}</td></tr>`;
    }

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('ui_employee_requests')}</h1>
                <p class="page-subtitle">${t('ui_manage_requests_subtitle') || 'Manage leave, loan, IT support, and other requests.'}</p>
            </div>
            <button class="btn-primary" onclick="showNewRequestModal()">
                <i data-lucide="file-signature"></i> ${t('ui_new_request') || 'New Request'}
            </button>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-12">
                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>${t('ui_date') || 'Date'}</th>
                                <th>${t('ui_employee_name')}</th>
                                <th>${t('ui_request_type')}</th>
                                <th>${t('ui_leave_type')}</th>
                                <th>${t('ui_status')}</th>
                                <th>${t('ui_actions')}</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${tableRows}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    `;
};

window.showNewRequestModal = async () => {
    const canEdit = window.canCurrentUserEditContracts(currentUserProfile);
    const users = await db.fetchUsers();
    
    const empSelect = document.getElementById('requestEmployeeId');
    empSelect.innerHTML = users.map(u => `<option value="${u.id}" ${u.id === currentUser.id ? 'selected' : ''}>${window.formatEmployeeName(u) || u.email}</option>`).join('');
    
    if (!canEdit) {
        empSelect.value = currentUser.id;
        empSelect.disabled = true;
    } else {
        empSelect.disabled = false;
    }

    document.getElementById('requestType').value = 'Leave Request';
    document.getElementById('requestLoanAmount').value = '';
    document.getElementById('requestNumberOfDays').value = '';
    document.getElementById('requestLeaveType').value = 'Annual/Vacation';
    document.getElementById('requestShortLeaveReason').value = '';
    document.getElementById('requestShortLeaveDuration').value = '15';
    handleNewRequestTypeChange('Leave Request');
    document.getElementById('requestModal').classList.add('active');
};

function compressProfileImage(file) {
    return new Promise((resolve, reject) => {
        if (!file?.type?.startsWith('image/')) return reject(new Error('Please select a valid image file.'));
        const reader = new FileReader();
        reader.onerror = () => reject(new Error('Unable to read the selected image.'));
        reader.onload = event => {
            const image = new Image();
            image.onerror = () => reject(new Error('The selected image could not be opened.'));
            image.onload = () => {
                const maxDimension = 320;
                const scale = Math.min(1, maxDimension / Math.max(image.width, image.height));
                const canvas = document.createElement('canvas');
                canvas.width = Math.max(1, Math.round(image.width * scale));
                canvas.height = Math.max(1, Math.round(image.height * scale));
                canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
                resolve(canvas.toDataURL('image/jpeg', 0.85));
            };
            image.src = event.target.result;
        };
        reader.readAsDataURL(file);
    });
}

window.previewEditUserPhoto = function (input) {
    const file = input?.files?.[0];
    const preview = document.getElementById('editAvatarPreview');
    if (!file || !preview) return;
    const objectUrl = URL.createObjectURL(file);
    preview.src = objectUrl;
    preview.hidden = false;
    preview.onload = () => URL.revokeObjectURL(objectUrl);
};

window.handleNewRequestTypeChange = function (requestType) {
    const isLeave = requestType === 'Leave Request';
    const isLoan = requestType === 'Loan Request' || requestType === 'Loan';
    document.getElementById('leaveTypeGroup').style.display = isLeave ? 'block' : 'none';
    const daysGroup = document.getElementById('leaveDaysGroup');
    const daysInput = document.getElementById('requestNumberOfDays');
    daysGroup.style.display = isLeave ? 'block' : 'none';
    daysInput.required = isLeave;
    if (!isLeave) daysInput.value = '';
    const amountGroup = document.getElementById('loanAmountGroup');
    const amountInput = document.getElementById('requestLoanAmount');
    amountGroup.style.display = isLoan ? 'block' : 'none';
    amountInput.required = isLoan;
    if (!isLoan) amountInput.value = '';
    handleRequestLeaveTypeChange(isLeave ? document.getElementById('requestLeaveType').value : '');
};

window.handleRequestLeaveTypeChange = function (leaveType) {
    const isLeaveRequest = document.getElementById('requestType')?.value === 'Leave Request';
    const isShortLeave = isLeaveRequest && leaveType === 'Short Leave';
    const shortFields = document.getElementById('requestShortLeaveFields');
    const reasonInput = document.getElementById('requestShortLeaveReason');
    const durationInput = document.getElementById('requestShortLeaveDuration');
    const daysGroup = document.getElementById('leaveDaysGroup');
    const daysInput = document.getElementById('requestNumberOfDays');
    if (shortFields) shortFields.style.display = isShortLeave ? 'block' : 'none';
    if (reasonInput) reasonInput.required = isShortLeave;
    if (durationInput) durationInput.required = isShortLeave;
    if (daysGroup) daysGroup.style.display = isLeaveRequest && !isShortLeave ? 'block' : 'none';
    if (daysInput) {
        daysInput.required = isLeaveRequest && !isShortLeave;
        if (!isLeaveRequest || isShortLeave) daysInput.value = '';
    }
};

window.handleCreateRequest = async (e) => {
    e.preventDefault();
    if (!currentUser) return;
    const empId = document.getElementById('requestEmployeeId').value;
    const reqType = document.getElementById('requestType').value;
    const leaveType = reqType === 'Leave Request' ? document.getElementById('requestLeaveType').value : null;
    const isShortLeave = reqType === 'Leave Request' && leaveType === 'Short Leave';
    const isLoan = reqType === 'Loan Request' || reqType === 'Loan';
    const loanAmount = isLoan ? Number(document.getElementById('requestLoanAmount').value) : null;
    const numberOfDays = reqType === 'Leave Request' && !isShortLeave ? Number(document.getElementById('requestNumberOfDays').value) : null;
    if (isLoan && (!Number.isFinite(loanAmount) || loanAmount <= 0)) {
        showToast(window.t('msg_toast_0') || 'Enter a valid loan amount greater than zero.', 'danger');
        return;
    }
    if (reqType === 'Leave Request' && !isShortLeave && (!Number.isInteger(numberOfDays) || numberOfDays <= 0)) {
        showToast(window.t('msg_toast_1') || 'Enter a valid number of leave days.', 'danger');
        return;
    }

    let res;
    if (isShortLeave) {
        const shortReason = document.getElementById('requestShortLeaveReason').value;
        const shortDuration = Number(document.getElementById('requestShortLeaveDuration').value);
        if (!shortReason) return showToast(window.t('msg_toast_2') || 'Select a reason for the short leave.', 'danger');
        const today = new Date().toISOString().slice(0, 10);
        const success = await db.submitLeaveRequest(empId, {
            leave_type: 'Short Leave', start_date: today, end_date: today,
            reason: shortReason, short_leave_reason: shortReason,
            short_leave_duration_minutes: shortDuration
        });
        res = { success };
    } else {
        res = await db.createRequest(empId, reqType, leaveType, loanAmount, numberOfDays);
    }
    if (res?.success) {
        showToast(t('toast_request_submitted_successfully'), "success");
        document.getElementById('requestModal').classList.remove('active');
        renderView('requests');
    } else {
        showToast(res.error?.message || t('toast_failed_to_submit_request'), "danger");
    }
};

window.updateRequestStatus = async (reqId, status) => {
    if (!supabaseClient) return;
    try {
        const decision = status.toUpperCase();

        // Attempt hierarchical workflow first
        let finalStatus = status;
        const res = await db.decideRequestApproval('requests', reqId, decision);

        if (res.success) {
            // Workflow exists and was processed
            finalStatus = res.data.status; // 'PENDING', 'APPROVED', or 'REJECTED'
        } else {
            // Fallback for legacy / if migration isn't applied yet
            const { error } = await supabaseClient.from('requests').update({ status }).eq('id', reqId);
            if (error) throw error;
        }

        // Auto-log approved loan requests into the Payroll Loans system ONLY if it reached FINAL approval
        if (finalStatus.toUpperCase() === 'APPROVED') {
            const { data: request } = await supabaseClient.from('requests').select('*').eq('id', reqId).single();
            if (request && (request.request_type === 'Loan' || request.request_type === 'Loan Request') && request.loan_amount > 0) {
                // Check if loan already exists to avoid duplicates (naive check based on recent loans)
                const { data: existing } = await supabaseClient.from('employee_loans').select('id')
                    .eq('employee_id', request.employee_id)
                    .eq('requested_amount', request.loan_amount)
                    .order('created_at', { ascending: false }).limit(1);

                if (!existing || existing.length === 0) {
                    const loanPayload = {
                        employee_id: request.employee_id,
                        requested_amount: request.loan_amount,
                        monthly_installment: request.loan_amount,
                        remaining_balance: request.loan_amount,
                        status: 'APPROVED'
                    };
                    if (typeof db !== 'undefined' && typeof db.saveEmployeeLoan === 'function') {
                        await db.saveEmployeeLoan(loanPayload);
                    } else {
                        await supabaseClient.from('employee_loans').insert([loanPayload]);
                    }
                }
            }
        }

        showToast(res.success && finalStatus === 'PENDING' ? `Approved and moved to next stage` : `Request ${finalStatus}`, "success");
        renderView('requests');
    } catch (e) {
        console.error("updateRequestStatus Error:", e);
        showToast(t('toast_failed_to_update_status'), "danger");
    }
};

window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredPrompt = e;
});

window.addEventListener('load', () => {
    if (window.location.hash.includes('type=recovery')) {
        currentView = 'login';
        loginMode = 'reset';
        setTimeout(() => renderView('login'), 100);
    }
    setTimeout(showInstallBanner, 1000); // Check 1s after load
});
// DOM Elements
const htmlElement = document.documentElement;
const viewContainer = document.getElementById('viewContainer');
const navItems = document.querySelectorAll('.nav-item');

// Apply language direction on startup
htmlElement.setAttribute('dir', currentLang === 'ar' ? 'rtl' : 'ltr');
htmlElement.setAttribute('lang', currentLang);

// Initialize Icons
lucide.createIcons();

// --- THEME MANAGEMENT ---
window.toggleTheme = function () {
    currentTheme = currentTheme === 'light' ? 'dark' : 'light';
    htmlElement.setAttribute('data-theme', currentTheme);
    if (currentUser?.id) localStorage.setItem(`muqam_hr_theme_${currentUser.id}`, currentTheme);
    const themeIcon = document.getElementById('themeIcon');
    if (themeIcon) themeIcon.setAttribute('data-lucide', currentTheme === 'light' ? 'moon' : 'sun');
    lucide.createIcons();
    const dropdown = document.getElementById('profileDropdown');
    if (dropdown) { dropdown.style.display = 'none'; dropdown.classList.remove('show'); dropdown.setAttribute('aria-hidden', 'true'); }
}

// --- LANGUAGE MANAGEMENT ---

window.formatEmployeeName = (profile) => {
    if (!profile) return 'Unknown';
    if (typeof profile === 'string') return profile;
    if (typeof currentLang !== 'undefined' && currentLang === 'ar' && profile.display_name_ar) {
        return profile.display_name_ar;
    }
    return profile.full_name || profile.display_name || 'Unknown';
};

window.toggleLanguage = function () {
    currentLang = currentLang === 'en' ? 'ar' : 'en';
    window.currentLang = currentLang;
    localStorage.setItem('app_lang', currentLang);
    htmlElement.setAttribute('dir', currentLang === 'ar' ? 'rtl' : 'ltr');
    htmlElement.setAttribute('lang', currentLang);

    const langDisplay = document.getElementById('currentLangDisplay');
    if (langDisplay) {
        langDisplay.textContent = currentLang === 'en' ? 'EN' : 'AR';
    }

    updateTranslations();
    renderView(currentView); // Re-render view for updated strings inside
    const dropdown = document.getElementById('profileDropdown');
    if (dropdown) { dropdown.style.display = 'none'; dropdown.classList.remove('show'); dropdown.setAttribute('aria-hidden', 'true'); }
}

window.closeMobileNavigation = function () {
    document.getElementById('mobileNavigationSheet')?.remove();
    document.body.classList.remove('mobile-navigation-open');
};

window.openMobileNavigation = async function () {
    window.closeMobileNavigation();
    const candidates = [...document.querySelectorAll('.sidebar-nav > .nav-item[data-view]')]
        .filter(item => item.dataset.view && item.style.display !== 'none' && !['dashboard', 'tasks', 'requests', 'time'].includes(item.dataset.view));
    const accessResults = await Promise.all(candidates.map(item => canCurrentUserAccessView(item.dataset.view)));
    const sourceItems = candidates.filter((item, index) => accessResults[index]);
    const sheet = document.createElement('div');
    sheet.id = 'mobileNavigationSheet';
    sheet.className = 'mobile-navigation-sheet';
    const closeLabel = t('ui_close') || (currentLang === 'ar' ? 'إغلاق' : 'Close');
    const moreLabel = t('nav_more') || (currentLang === 'ar' ? 'المزيد' : 'More');
    sheet.innerHTML = `
        <button type="button" class="mobile-navigation-backdrop" onclick="window.closeMobileNavigation()" aria-label="${escapeHTML(closeLabel)}"></button>
        <section class="mobile-navigation-panel" role="dialog" aria-modal="true" aria-labelledby="mobile-navigation-title">
            <div class="mobile-navigation-handle"></div>
            <div class="mobile-navigation-header">
                <h2 id="mobile-navigation-title">${escapeHTML(moreLabel)}</h2>
                <button type="button" class="icon-btn" onclick="window.closeMobileNavigation()" aria-label="${escapeHTML(closeLabel)}"><i data-lucide="x"></i></button>
            </div>
            <div class="mobile-navigation-grid">
                ${sourceItems.map(item => {
                    const icon = item.querySelector('[data-lucide]')?.getAttribute('data-lucide') || 'circle';
                    const label = item.querySelector('span')?.textContent?.trim() || item.dataset.view;
                    return `<button type="button" class="mobile-navigation-item ${currentView === item.dataset.view ? 'active' : ''}" onclick="window.closeMobileNavigation(); renderView('${escapeHTML(item.dataset.view)}')"><i data-lucide="${escapeHTML(icon)}"></i><span>${escapeHTML(label)}</span></button>`;
                }).join('')}
            </div>
        </section>`;
    document.body.appendChild(sheet);
    document.body.classList.add('mobile-navigation-open');
    if (window.lucide) window.lucide.createIcons();
};

function updateTranslations() {

    const roleSpan = document.getElementById('currentUserRole');
    if (roleSpan && typeof currentUserRole !== 'undefined') {
        let displayRole = currentUserRole.charAt(0).toUpperCase() + currentUserRole.slice(1);
        if (currentUserRole === 'admin') displayRole = t('role_system_admin') || 'System Admin';
        else if (currentUserRole === 'manager') displayRole = t('role_manager') || 'Manager';
        else if (currentUserRole === 'employee') displayRole = t('role_employee') || 'Employee';
        roleSpan.textContent = displayRole;
    }

    const texts = document.querySelectorAll('[data-i18n]');
    texts.forEach(el => {
        const key = el.getAttribute('data-i18n');
        if (i18n[currentLang] && i18n[currentLang][key]) {
            el.textContent = i18n[currentLang][key];
        } else if (key && (key.startsWith('ui_') || key.startsWith('html_ui_'))) {
            let text = key.replace(/^(html_)?ui_/, '').replace(/_/g, ' ');
            el.textContent = text.split(' ').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
        }
    });

    const placeholders = document.querySelectorAll('[data-i18n-placeholder]');
    placeholders.forEach(el => {
        const key = el.getAttribute('data-i18n-placeholder');
        if (i18n[currentLang] && i18n[currentLang][key]) {
            el.setAttribute('placeholder', i18n[currentLang][key]);
        } else if (key && (key.startsWith('ui_') || key.startsWith('html_ui_'))) {
            let text = key.replace(/^(html_)?ui_/, '').replace(/_/g, ' ');
            el.setAttribute('placeholder', text.split(' ').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' '));
        }
    });

    translateArabicInterface(document);
}

// --- NAVIGATION & VIEWS ---
navItems.forEach(item => {
    item.addEventListener('click', (e) => {
        e.preventDefault();
        navItems.forEach(nav => nav.classList.remove('active'));
        item.classList.add('active');

        currentView = item.getAttribute('data-view');
        renderView(currentView);
    });
});

function t(key) {
    if (i18n[currentLang] && i18n[currentLang][key]) {
        return i18n[currentLang][key];
    }
    if (key && (key.startsWith('ui_') || key.startsWith('html_ui_'))) {
        let text = key.replace(/^(html_)?ui_/, '').replace(/_/g, ' ');
        return text.split(' ').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
    }
    return key;
}

// Localize newer or server-generated UI copy that is not yet represented by a
// data-i18n key. This deliberately targets controls, system feedback, modal
// copy and table headings; employee-entered task titles and descriptions are
// left unchanged.
const arabicRuntimeUiText = Object.freeze({
    'Close': 'إغلاق',
    'More': 'المزيد',
    'Confirm': 'تأكيد',
    'Confirming...': 'جارٍ التأكيد...',
    'Cancel': 'إلغاء',
    'Save': 'حفظ',
    'Save changes': 'حفظ التغييرات',
    'Delete': 'حذف',
    'Edit': 'تعديل',
    'View': 'عرض',
    'Send': 'إرسال',
    'OK': 'حسنًا',
    'Notice': 'تنبيه',
    'Input required': 'الإدخال مطلوب',
    'Sign In to MUQAM': 'تسجيل الدخول إلى مُقام',
    'Enter your credentials to access your portal': 'أدخل بياناتك للوصول إلى بوابتك',
    'Email Address': 'البريد الإلكتروني',
    'Password': 'كلمة المرور',
    'Forgot Password?': 'هل نسيت كلمة المرور؟',
    'Sign In': 'تسجيل الدخول',
    'Reset Password': 'إعادة تعيين كلمة المرور',
    'Create Account': 'إنشاء حساب',
    'Back to login': 'العودة إلى تسجيل الدخول',
    'Remember me': 'تذكرني',
    'Loading...': 'جارٍ التحميل...',
    'No data available': 'لا توجد بيانات متاحة',
    'No results found': 'لم يتم العثور على نتائج',
    'Search': 'بحث',
    'Switch language': 'تبديل اللغة',
    'Primary navigation': 'التنقل الرئيسي',
    'Search (Cmd/Ctrl + K)': 'بحث (Cmd/Ctrl + K)',
    'Unknown': 'غير معروف',
    'Unknown user': 'مستخدم غير معروف',
    'Unknown employee': 'موظف غير معروف',
    'Employee': 'موظف',
    'Team Member': 'عضو فريق',
    'You': 'أنت',
    'ADMIN': 'مسؤول النظام',
    'Owner': 'المالك',
    'OWNER': 'المالك',
    'SYSTEM ADMIN': 'مسؤول النظام',
    'ROLE_SYSTEM_ADMIN': 'مسؤول النظام',
    'MANAGER': 'مدير',
    'SUPERVISOR': 'مشرف',
    'EMPLOYEE': 'موظف',
    'CEO': 'الرئيس التنفيذي',
    'GM': 'المدير العام',
    'Marketing Manager': 'مدير التسويق',
    'Operations Manager': 'مدير العمليات',
    'IT Manager': 'مدير تقنية المعلومات',
    'Account Manager': 'مدير حساب',
    'Production Supervisor': 'مشرف الإنتاج',
    'Operations Assistant': 'مساعد عمليات',
    'Sales Representative': 'مندوب مبيعات',
    'Customer Services': 'خدمة العملاء',
    'Graphic Designer': 'مصمم جرافيك',
    'Photographer': 'مصور',
    'Technician': 'فني',
    'Barista': 'باريستا',
    'No profile photo': 'لا توجد صورة شخصية',
    'Profile photo unavailable': 'الصورة الشخصية غير متاحة',
    'Close employee information': 'إغلاق معلومات الموظف',
    'Employee information is unavailable.': 'معلومات الموظف غير متاحة.',
    'Nationality': 'الجنسية',
    'ID/Iqama number': 'رقم الهوية / الإقامة',
    'Phone Number': 'رقم الهاتف',
    'Latest Login': 'آخر تسجيل دخول',
    'Not provided': 'غير متوفر',
    'No login recorded': 'لا يوجد تسجيل دخول مسجل',
    'Marketing': 'التسويق',
    'Sales': 'المبيعات',
    'Designing': 'التصميم',
    'Operations': 'العمليات',
    'Search tasks...': 'ابحث في المهام...',
    'All Status': 'جميع الحالات',
    'Open Tasks': 'المهام المفتوحة',
    'All Priorities': 'جميع الأولويات',
    'Clear Filters': 'مسح عوامل التصفية',
    'Focus': 'التركيز',
    'Pipeline': 'مسار العمل',
    'Pipeline health summary': 'ملخص حالة مسار العمل',
    'Pipeline health': 'حالة مسار العمل',
    'waiting': 'بانتظار البدء',
    'active': 'نشطة',
    'due this week': 'مستحقة هذا الأسبوع',
    'overdue': 'متأخرة',
    'total': 'الإجمالي',
    'New Task': 'مهمة جديدة',
    'Task details': 'تفاصيل المهمة',
    'Start with a clear title and ownership.': 'ابدأ بعنوان واضح وحدد مسؤولية المهمة.',
    'Team and workflow': 'الفريق وسير العمل',
    'Choose where the task belongs and who should follow it.': 'حدد القسم والفريق والمتابعين للمهمة.',
    'Plan the work, choose the team, and share everything needed to begin.': 'خطط للعمل وحدد الفريق وشارك كل ما يلزم للبدء.',
    'Add the outcome, context, and useful instructions.': 'أضف النتيجة المطلوبة والسياق والتعليمات المفيدة.',
    'Needs attention': 'تحتاج إلى اهتمام',
    'NEEDS ATTENTION': 'تحتاج إلى اهتمام',
    'Focus view': 'عرض التركيز',
    'No tasks found.': 'لم يتم العثور على مهام.',
    'No projects found.': 'لم يتم العثور على مشاريع.',
    'Approve': 'اعتماد',
    'Reject': 'رفض',
    'Watcher access · View only': 'صلاحية المتابع · عرض فقط',
    'Completed': 'مكتملة',
    'Rejected': 'مرفوض',
    'Submitted': 'مُرسل',
    'Request pipeline': 'مسار الطلب',
    'Sub-Tasks': 'المهام الفرعية',
    'Edit List': 'تعديل القائمة',
    'Delete List': 'حذف القائمة',
    'View task': 'عرض المهمة',
    'Delete task': 'حذف المهمة',
    'You do not have permission to add tasks to this list.': 'ليس لديك صلاحية لإضافة مهام إلى هذه القائمة.',
    'Created Date': 'تاريخ الإنشاء',
    'Created by': 'أنشأها',
    'Enter task title': 'أدخل عنوان المهمة',
    'Select': 'اختيار',
    'Administrative': 'الإدارة',
    'IT': 'تقنية المعلومات',
    'Operations and Production': 'العمليات والإنتاج',
    'Select Task Type': 'اختر نوع المهمة',
    'Regular Tasks': 'مهام اعتيادية',
    'Regular Task': 'مهمة اعتيادية',
    'Watchers (Optional)': 'المتابعون (اختياري)',
    'Select watchers': 'اختر المتابعين',
    'Change assignee': 'تغيير المعيّن',
    'Change assignees': 'تغيير المعيّنين',
    'Search employees...': 'ابحث عن موظفين...',
    'Task access': 'صلاحية المهمة',
    'Task list access': 'صلاحيات قائمة المهام',
    'Multi-selection': 'اختيار متعدد',
    'Select options': 'اختر الخيارات',
    'Select all': 'اختيار الكل',
    'Search...': 'بحث...',
    'Search employees': 'ابحث عن موظفين',
    'Download Source': 'مصدر التنزيل',
    'Add another URL': 'إضافة رابط آخر',
    'Upload Source': 'مصدر الرفع',
    'Account': 'الحساب',
    'Select Account': 'اختر الحساب',
    'Party': 'بارتي',
    'Main': 'الرئيسي',
    'Coffee Corner': 'كوفي كورنر',
    'Design Type': 'نوع التصميم',
    'Select Design Type': 'اختر نوع التصميم',
    'Post': 'منشور',
    'Reel': 'ريلز',
    'Story': 'قصة',
    'Promo Video': 'فيديو ترويجي',
    'Cover': 'غلاف',
    'Commercial Video': 'فيديو تجاري',
    'Advertisement Video': 'فيديو إعلاني',
    'Proposal': 'مقترح',
    'Delivery Status': 'حالة التسليم',
    'Awaiting manager review': 'بانتظار مراجعة المدير',
    'Approved': 'تمت الموافقة',
    'Edit needed': 'بحاجة إلى تعديل',
    'task_desc': 'وصف المهمة',
    'Describe the task...': 'صف المهمة...',
    'Attachments': 'المرفقات',
    'Attachment option with drag and drop feature to upload multi files, photos, and videos': 'خيار المرفقات مع السحب والإفلات لرفع ملفات وصور وفيديوهات متعددة',
    'Open map': 'فتح الخريطة',
    'Location': 'الموقع',
    'Clocking in...': 'جارٍ تسجيل الحضور...',
    'Waiting for location permission...': 'بانتظار إذن الموقع...',
    'Location received — opening camera...': 'تم استلام الموقع — جارٍ فتح الكاميرا...',
    'Uploading photo…': 'جارٍ رفع الصورة…',
    'Photo received — clocking out…': 'تم استلام الصورة — جارٍ تسجيل الانصراف…',
    'Unassigned': 'غير معيّن',
    'No Manager': 'لا يوجد مدير',
    'No job title': 'لا يوجد مسمى وظيفي',
    'No department': 'لا يوجد قسم',
    'No project': 'لا يوجد مشروع',
    'No Project / Independent': 'لا يوجد مشروع / مستقل',
    'Not set': 'غير محدد',
    'Public': 'عام',
    'public': 'عام',
    'Private': 'خاص',
    'private': 'خاص',
    'General': 'عام',
    'Details': 'التفاصيل',
    'Custom fields': 'الحقول المخصصة',
    'Dependencies': 'التبعيات',
    'Proofs': 'الإثباتات',
    'Priority': 'الأولوية',
    'Status': 'الحالة',
    'Low': 'منخفضة',
    'Medium': 'متوسطة',
    'High': 'عالية',
    'Urgent': 'عاجلة',
    'Critical': 'حرجة',
    'Todo': 'قيد الانتظار',
    'To do': 'قيد الانتظار',
    'In progress': 'قيد التنفيذ',
    'Review': 'المراجعة',
    'Awaiting approval': 'بانتظار الموافقة',
    'Done': 'مكتملة',
    'Add a description': 'أضف وصفًا',
    'Add a description...': 'أضف وصفًا...',
    'Assign task': 'تعيين المهمة',
    'Task assignees': 'الموظفون المعيّنون للمهمة',
    'Select one or more employees.': 'اختر موظفًا واحدًا أو أكثر.',
    'Select at least one employee.': 'اختر موظفًا واحدًا على الأقل.',
    'Save assignment': 'حفظ التعيين',
    'No employees available.': 'لا يوجد موظفون متاحون.',
    'Task assignment updated.': 'تم تحديث تعيين المهمة.',
    'Unable to update assignment.': 'تعذر تحديث تعيين المهمة.',
    'You do not have access to this task.': 'ليس لديك صلاحية للوصول إلى هذه المهمة.',
    'Unable to open task details. Please try again.': 'تعذر فتح تفاصيل المهمة. يرجى المحاولة مرة أخرى.',
    'Only the task creator or an administrator can change assignees.': 'يمكن لمنشئ المهمة أو مسؤول النظام فقط تغيير الموظفين المعيّنين.',
    'Only the task creator or an administrator can edit this task.': 'يمكن لمنشئ المهمة أو مسؤول النظام فقط تعديل هذه المهمة.',
    'Only the task creator or an administrator can delete this task.': 'يمكن لمنشئ المهمة أو مسؤول النظام فقط حذف هذه المهمة.',
    'Task created successfully.': 'تم إنشاء المهمة بنجاح.',
    'Task updated': 'تم تحديث المهمة.',
    'Task approved and moved to Done.': 'تم اعتماد المهمة ونقلها إلى مكتملة.',
    'Task returned to In Progress.': 'تمت إعادة المهمة إلى قيد التنفيذ.',
    'Task not found.': 'المهمة غير موجودة.',
    'Task not found': 'المهمة غير موجودة',
    'Subtask added': 'تمت إضافة المهمة الفرعية',
    'Delete Task': 'حذف المهمة',
    'Delete Task List': 'حذف قائمة المهام',
    'Are you sure you want to delete this task?': 'هل أنت متأكد من حذف هذه المهمة؟',
    'Are you sure you want to delete this task list and all its tasks?': 'هل أنت متأكد من حذف قائمة المهام وجميع مهامها؟',
    'Task list deleted successfully.': 'تم حذف قائمة المهام بنجاح.',
    'Failed to delete task list.': 'تعذر حذف قائمة المهام.',
    'Enter estimated time (e.g., 4h, 1d):': 'أدخل الوقت المقدر (مثال: 4 ساعات أو يوم واحد):',
    'Estimated time': 'الوقت المقدر',
    'Enter tags (comma separated):': 'أدخل الوسوم مفصولة بفواصل:',
    'Task tags': 'وسوم المهمة',
    'Edit task': 'تعديل المهمة',
    'Task list': 'قائمة المهام',
    'List Name': 'اسم القائمة',
    'Advanced options': 'خيارات متقدمة',
    'Task name': 'اسم المهمة',
    'Assignee': 'الموظف المعيّن',
    'Department': 'القسم',
    'ID/Iqama number': 'رقم الهوية / الإقامة',
    'Job Title': 'المسمى الوظيفي',
    'Assigned Manager': 'المدير المعيّن',
    'Employee profile': 'ملف الموظف',
    'Not assigned': 'غير معيّن',
    'Dates': 'التواريخ',
    'Set date': 'تحديد التاريخ',
    'Anyone': 'أي موظف',
    'None': 'لا شيء',
    'Assigned employees': 'الموظفون المعيّنون',
    'Privacy': 'الخصوصية',
    'No privacy': 'بدون خصوصية',
    'Team Only': 'الفريق فقط',
    'Tags': 'الوسوم',
    'No tags': 'لا توجد وسوم',
    'Reminders': 'التذكيرات',
    'No reminders': 'لا توجد تذكيرات',
    'Followers': 'المتابعون',
    'No followers': 'لا يوجد متابعون',
    'Progress': 'التقدم',
    'Set to repeat': 'تعيين التكرار',
    'Does not repeat': 'لا يتكرر',
    'Daily': 'يوميًا',
    'Weekly': 'أسبوعيًا',
    'Monthly': 'شهريًا',
    'Annually': 'سنويًا',
    'Custom days': 'أيام مخصصة',
    'Select repeat pattern': 'اختر نمط التكرار',
    'Task Type': 'نوع المهمة',
    'Select Sub-Type': 'اختر النوع الفرعي',
    'Regular Tasks': 'مهام اعتيادية',
    'Daily Tasks': 'مهام يومية',
    'Designing Task': 'مهمة تصميم',
    'Files': 'الملفات',
    'Drag and drop your files here.': 'اسحب الملفات وأفلتها هنا.',
    'Browse files': 'تصفح الملفات',
    'Select files': 'اختر الملفات',
    'No files selected': 'لم يتم اختيار ملفات',
    'Success': 'تم بنجاح',
    'Action completed successfully.': 'تم تنفيذ الإجراء بنجاح.',
    'Error opening edit modal. Check console for details.': 'تعذر فتح نافذة تعديل المهمة. يرجى المحاولة مرة أخرى.',
    'Date': 'التاريخ',
    'Employee Name': 'اسم الموظف',
    'ID Number': 'رقم الهوية',
    'Search employee name': 'ابحث باسم الموظف',
    'Search Iqama / ID': 'ابحث برقم الإقامة أو الهوية',
    'Clear': 'مسح',
    'Attendance filters': 'مرشحات الحضور',
    'No attendance records match these filters.': 'لا توجد سجلات حضور مطابقة لهذه المرشحات.',
    'Permission Denied': 'تم رفض الإذن',
    'Connection Error': 'خطأ في الاتصال',
    'Session Expired': 'انتهت الجلسة',
    'The camera is not ready yet.': 'الكاميرا غير جاهزة بعد.',
    'Unable to capture the photo. Please try again.': 'تعذر التقاط الصورة. يرجى المحاولة مرة أخرى.',
    'Please capture an image.': 'يرجى التقاط صورة.',
    'Take a photo before continuing.': 'التقط صورة قبل المتابعة.',
    'Location sharing is not supported by this device.': 'هذا الجهاز لا يدعم مشاركة الموقع.',
    'Please fill in all required fields.': 'يرجى تعبئة جميع الحقول المطلوبة.',
    'A required field is missing. Please fill in all required fields.': 'يوجد حقل مطلوب غير مكتمل. يرجى تعبئة جميع الحقول المطلوبة.',
    'This record already exists. Please use a unique value.': 'هذا السجل موجود بالفعل. يرجى استخدام قيمة فريدة.',
    'A database constraint was violated. Please check your input values.': 'تعذر حفظ البيانات بسبب أحد قيود قاعدة البيانات. يرجى التحقق من القيم المدخلة.',
    'Cannot reach the server. Please check your internet connection and try again.': 'تعذر الوصول إلى الخادم. تحقق من اتصال الإنترنت ثم حاول مرة أخرى.',
    'Your session has expired. Please log in again.': 'انتهت جلستك. يرجى تسجيل الدخول مرة أخرى.',
    'You do not have permission to perform this action. Please contact your administrator.': 'ليس لديك صلاحية لتنفيذ هذا الإجراء. يرجى التواصل مع مسؤول النظام.',
    'You do not have permission to create tasks.': 'ليس لديك صلاحية لإنشاء المهام.',
    'Employee information is unavailable.': 'بيانات الموظف غير متاحة.',
    'Excel export is unavailable. Please reload the page and try again.': 'تصدير Excel غير متاح. أعد تحميل الصفحة ثم حاول مرة أخرى.',
    'There are no users to export.': 'لا يوجد مستخدمون للتصدير.',
    'User directory downloaded successfully.': 'تم تنزيل دليل المستخدمين بنجاح.',
    'Failed to update role.': 'تعذر تحديث الدور.',
    'Failed to update department.': 'تعذر تحديث القسم.',
    'Department updated successfully.': 'تم تحديث القسم بنجاح.',
    'Failed to assign manager.': 'تعذر تعيين المدير.',
    'Reminder created!': 'تم إنشاء التذكير!',
    'Error creating reminder.': 'حدث خطأ أثناء إنشاء التذكير.',
    'Error updating reminder.': 'حدث خطأ أثناء تحديث التذكير.',
    'Error deleting reminder.': 'حدث خطأ أثناء حذف التذكير.',
    'Delete Contract': 'حذف العقد',
    'Contract deleted successfully.': 'تم حذف العقد بنجاح.',
    'Failed to delete contract.': 'تعذر حذف العقد.',
    'Employee details could not be loaded.': 'تعذر تحميل تفاصيل الموظف.',
    'No active contract found for this employee.': 'لا يوجد عقد نشط لهذا الموظف.',
    'Only an HR Manager or Administrator can edit contracts.': 'يمكن لمدير الموارد البشرية أو مسؤول النظام فقط تعديل العقود.',
    'Only an HR Manager or Administrator can delete contracts.': 'يمكن لمدير الموارد البشرية أو مسؤول النظام فقط حذف العقود.',
    'You do not have access to this page.': 'ليس لديك صلاحية للوصول إلى هذه الصفحة.',
    'All translations saved successfully': 'تم حفظ جميع الترجمات بنجاح',
    'Some translations could not be saved.': 'تعذر حفظ بعض الترجمات.',
    'Translation key is required': 'مفتاح الترجمة مطلوب',
    'Translation key added successfully!': 'تمت إضافة مفتاح الترجمة بنجاح!',
    'Translation key removed': 'تمت إزالة مفتاح الترجمة',
    'Failed to parse JSON file': 'تعذر قراءة ملف JSON',
    'Translations imported and saved successfully!': 'تم استيراد الترجمات وحفظها بنجاح!',
    'Job title already exists in this department': 'المسمى الوظيفي موجود بالفعل في هذا القسم',
    'Department (EN) is required.': 'اسم القسم باللغة الإنجليزية مطلوب.',
    'A rejection reason is required.': 'سبب الرفض مطلوب.',
    'Failed to update request approval.': 'تعذر تحديث اعتماد الطلب.',
    'Unable to record this approval.': 'تعذر تسجيل هذا الاعتماد.',
    'Unable to return this task.': 'تعذر إعادة هذه المهمة.',
    'Project deleted successfully': 'تم حذف المشروع بنجاح',
    'Failed to delete project': 'تعذر حذف المشروع',
    'Create a new Tasks List': 'إنشاء قائمة مهام جديدة',
    'General': 'عام',
    'Access': 'الوصول',
    'Notification': 'الإشعارات',
    'Custom Fields': 'الحقول المخصصة',
    'Name *': 'الاسم *',
    'Name': 'الاسم',
    'Template *': 'القالب *',
    '-- None --': '-- لا شيء --',
    'Blank list': 'قائمة فارغة',
    'Kanban board': 'لوحة كانبان',
    'Scrum sprint': 'دورة سكرم',
    'Description': 'الوصف',
    'Enter description': 'أدخل الوصف',
    'Visible to department *': 'مرئية للقسم *',
    'Select department': 'اختر القسم',
    'Visible to all departments': 'مرئية لجميع الأقسام',
    'Employees can only see task lists assigned to their own department.': 'يمكن للموظفين رؤية قوائم المهام المخصصة لقسمهم فقط.',
    'Shared With': 'مشاركة مع',
    'Select employees...': 'اختر الموظفين...',
    'Select all employees': 'اختيار جميع الموظفين',
    'Select all followers': 'اختيار جميع المتابعين',
    'Select one or more employees': 'اختر موظفًا واحدًا أو أكثر',
    'All employees': 'جميع الموظفين',
    'Who can add tasks': 'من يمكنه إضافة المهام',
    'Who can delete tasks': 'من يمكنه حذف المهام',
    'Select employees who can view and interact with this task list.': 'اختر الموظفين الذين يمكنهم عرض قائمة المهام والتفاعل معها.',
    'Select employees allowed to add tasks.': 'اختر الموظفين المسموح لهم بإضافة المهام.',
    'Select employees allowed to delete tasks (other than their own).': 'اختر الموظفين المسموح لهم بحذف المهام غير مهامهم.',
    'Notify assignees on new tasks': 'إشعار الموظفين المعيّنين بالمهام الجديدة',
    'Notify me when tasks are completed': 'إشعاري عند اكتمال المهام',
    'Custom fields allow you to add specific metadata to tasks in this list. (Coming soon)': 'تتيح لك الحقول المخصصة إضافة بيانات محددة لمهام هذه القائمة. (قريبًا)',
    'Add Custom Field': 'إضافة حقل مخصص',
    'Save & Create': 'حفظ وإنشاء',
    'Task lists': 'قوائم المهام',
    'All lists': 'جميع القوائم',
    'Add new list': 'إضافة قائمة جديدة'
    ,'1 Hour': 'ساعة واحدة'
    ,'15 Minutes': '15 دقيقة'
    ,'2 Hours': 'ساعتان'
    ,'3 Hours': 'ثلاث ساعات'
    ,'Actual Sales Amount (SAR)': 'مبلغ المبيعات الفعلي (ر.س)'
    ,'Add': 'إضافة'
    ,'Add New User': 'إضافة مستخدم جديد'
    ,'Add User': 'إضافة المستخدم'
    ,'Assign People *': 'تعيين الموظفين *'
    ,'Category': 'الفئة'
    ,'Date of Absence *': 'تاريخ الغياب *'
    ,'Delete Project': 'حذف المشروع'
    ,'Department (AR)': 'القسم (بالعربية)'
    ,'Department (EN) *': 'القسم (بالإنجليزية) *'
    ,'Document Details': 'تفاصيل المستند'
    ,'Duration': 'المدة'
    ,'Edit User': 'تعديل المستخدم'
    ,'Email': 'البريد الإلكتروني'
    ,'Employee *': 'الموظف *'
    ,'Employee ID': 'رقم الموظف'
    ,'Assigned automatically': 'يُعيّن تلقائيًا'
    ,'The next MQ number will be assigned when the user is created.': 'سيتم تعيين رقم MQ التالي عند إنشاء المستخدم.'
    ,'End Date': 'تاريخ الانتهاء'
    ,'Enter email address (Optional)': 'أدخل البريد الإلكتروني (اختياري)'
    ,'Enter full name': 'أدخل الاسم الكامل'
    ,'Enter full name in Arabic': 'أدخل الاسم الكامل بالعربية'
    ,'Enter job title and press Add': 'أدخل المسمى الوظيفي ثم اضغط إضافة'
    ,'Enter number of days': 'أدخل عدد الأيام'
    ,'Enter phone number (Optional)': 'أدخل رقم الهاتف (اختياري)'
    ,"Event's Location (Google Maps URL)": 'موقع الفعالية (رابط خرائط Google)'
    ,'Excused Absence': 'غياب بعذر'
    ,'Full Name': 'الاسم الكامل'
    ,'Full Name (Arabic)': 'الاسم الكامل (بالعربية)'
    ,'Full Name in Arabic': 'الاسم الكامل بالعربية'
    ,'I am running late to the office.': 'سأتأخر عن الوصول إلى المكتب.'
    ,'I need to attend an urgent family matter.': 'لدي ظرف عائلي طارئ.'
    ,'I will be out for a meeting.': 'سأكون خارج المكتب لحضور اجتماع.'
    ,'Initial Tasks (One per line)': 'المهام الأولية (مهمة واحدة في كل سطر)'
    ,'Invoice Amount': 'مبلغ الفاتورة'
    ,'Invoice Amount *': 'مبلغ الفاتورة *'
    ,'Job Titles': 'المسميات الوظيفية'
    ,'Loan Amount (SAR)': 'مبلغ القرض (ر.س)'
    ,'Log Monthly Sales': 'تسجيل المبيعات الشهرية'
    ,'Lost Reason': 'سبب الخسارة'
    ,'Month / Year': 'الشهر / السنة'
    ,'Monthly Installment (SAR) *': 'القسط الشهري (ر.س) *'
    ,'More navigation': 'المزيد من عناصر التنقل'
    ,'Dashboard': 'لوحة التحكم'
    ,'Time and Attendance': 'الحضور والانصراف'
    ,'Employee Requests': 'طلبات الموظفين'
    ,'Task Manager': 'إدارة المهام'
    ,'Documents': 'المستندات'
    ,'Logout': 'تسجيل الخروج'
    ,'Log out': 'تسجيل الخروج'
    ,'Settings': 'الإعدادات'
    ,'Notifications': 'الإشعارات'
    ,'Community': 'المجتمع'
    ,'New Request': 'طلب جديد'
    ,'Note': 'ملاحظة'
    ,'Number of Days': 'عدد الأيام'
    ,'Phone': 'الهاتف'
    ,'Primary navigation': 'التنقل الرئيسي'
    ,'Profile Photo': 'الصورة الشخصية'
    ,'Project Name *': 'اسم المشروع *'
    ,'Project Status': 'حالة المشروع'
    ,'Project Status *': 'حالة المشروع *'
    ,'Project Tags': 'وسوم المشروع'
    ,'Project Type *': 'نوع المشروع *'
    ,'Search': 'بحث'
    ,'Select Department first': 'اختر القسم أولًا'
    ,'Select reason': 'اختر السبب'
    ,'Short Leave': 'استئذان قصير'
    ,'Short Leave Reason': 'سبب الاستئذان القصير'
    ,'Starting Date': 'تاريخ البدء'
    ,'Starting Date *': 'تاريخ البدء *'
    ,'Switch language': 'تبديل اللغة'
    ,'Task 1\nTask 2': 'المهمة 1\nالمهمة 2'
    ,'Temp Password': 'كلمة المرور المؤقتة'
    ,'Total Loan Amount (SAR) *': 'إجمالي مبلغ القرض (ر.س) *'
    ,'Account locked due to multiple failed attempts. Please contact Admin.': 'تم قفل الحساب بسبب تكرار محاولات الدخول الفاشلة. يرجى التواصل مع مسؤول النظام.'
    ,'Announcement published successfully.': 'تم نشر الإعلان بنجاح.'
    ,'Archived contract permanently deleted.': 'تم حذف العقد المؤرشف نهائيًا.'
    ,'Are you sure you want to delete this client?': 'هل أنت متأكد من حذف هذا العميل؟'
    ,'Are you sure you want to delete this department?': 'هل أنت متأكد من حذف هذا القسم؟'
    ,'Are you sure you want to permanently delete this contract? This action cannot be undone.': 'هل أنت متأكد من حذف هذا العقد نهائيًا؟ لا يمكن التراجع عن هذا الإجراء.'
    ,'Delete Client': 'حذف العميل'
    ,'Delete Department': 'حذف القسم'
    ,'Delete Translation Key': 'حذف مفتاح الترجمة'
    ,'Delete Webhook': 'حذف رابط Webhook'
    ,'Delete archived contract': 'حذف العقد المؤرشف'
    ,'Delete this webhook?': 'هل تريد حذف رابط Webhook هذا؟'
    ,'Enter a valid loan amount greater than zero.': 'أدخل مبلغ قرض صحيحًا أكبر من صفر.'
    ,'Enter a valid number of leave days.': 'أدخل عددًا صحيحًا لأيام الإجازة.'
    ,'Error generating template. Please make sure XLSX library is loaded.': 'تعذر إنشاء القالب. تأكد من تحميل مكتبة XLSX.'
    ,'Excel support is unavailable. Please refresh or check your internet connection.': 'دعم Excel غير متاح. حدّث الصفحة أو تحقق من اتصال الإنترنت.'
    ,'Failed to add translation to database': 'تعذرت إضافة الترجمة إلى قاعدة البيانات'
    ,'Failed to remove translation from database': 'تعذرت إزالة الترجمة من قاعدة البيانات'
    ,'Failed to submit short leave request.': 'تعذر إرسال طلب الاستئذان القصير.'
    ,'No contract is available for this employee.': 'لا يوجد عقد متاح لهذا الموظف.'
    ,'No files were successfully uploaded.': 'لم يتم رفع أي ملف بنجاح.'
    ,'Notification sent to assignee.': 'تم إرسال الإشعار إلى الموظف المعيّن.'
    ,'Only an administrator can delete archived contracts.': 'يمكن لمسؤول النظام فقط حذف العقود المؤرشفة.'
    ,'Only this task’s department manager can approve completion.': 'يمكن لمدير قسم هذه المهمة فقط اعتماد اكتمالها.'
    ,'Select a reason for the short leave.': 'اختر سبب الاستئذان القصير.'
    ,'Select the department that can see this task list.': 'اختر القسم الذي يمكنه رؤية قائمة المهام هذه.'
    ,'Short leave request submitted successfully.': 'تم إرسال طلب الاستئذان القصير بنجاح.'
    ,'Task moved to Awaiting Approval. The department manager has been notified.': 'تم نقل المهمة إلى بانتظار الموافقة وإشعار مدير القسم.'
    ,'Task rejected and sent back to In Progress': 'تم رفض المهمة وإعادتها إلى قيد التنفيذ'
    ,'This permanently deletes the archived contract and cannot be undone.': 'سيتم حذف العقد المؤرشف نهائيًا ولا يمكن التراجع عن ذلك.'
    ,'This permanently removes the user and their data. Their contract will be moved to Archived Contracts.': 'سيتم حذف المستخدم وبياناته نهائيًا، ونقل عقده إلى العقود المؤرشفة.'
    ,'This task is no longer available or you do not have access.': 'هذه المهمة لم تعد متاحة أو ليس لديك صلاحية للوصول إليها.'
    ,'Unauthorized: You do not have permission to view this contract.': 'غير مصرح: ليس لديك صلاحية لعرض هذا العقد.'
    ,'Unknown template type': 'نوع القالب غير معروف'
    ,'The database permissions migration has not been applied. Run onboarding_create_user_permission_repair.sql; for task creation, also run tasks_insert_permission_repair.sql, then try again.': 'لم يتم تطبيق ترحيل صلاحيات قاعدة البيانات. شغّل onboarding_create_user_permission_repair.sql، ولإنشاء المهام شغّل أيضًا tasks_insert_permission_repair.sql، ثم حاول مرة أخرى.'
});
const arabicRuntimeUiTextLower = Object.freeze(Object.fromEntries(
    Object.entries(arabicRuntimeUiText).map(([key, value]) => [key.toLocaleLowerCase('en'), value])
));

function localizeRuntimeText(value) {
    const source = String(value ?? '');
    if (currentLang !== 'ar' || !source.trim()) return source;
    const trimmed = source.trim();
    if (arabicRuntimeUiText[trimmed]) return arabicRuntimeUiText[trimmed];
    const caseInsensitiveMatch = arabicRuntimeUiTextLower[trimmed.toLocaleLowerCase('en')];
    if (caseInsensitiveMatch) return caseInsensitiveMatch;

    const normalizedStatus = {
        APPROVED: 'تمت الموافقة على الطلب',
        REJECTED: 'تم رفض الطلب',
        PENDING: 'الطلب قيد الانتظار'
    };
    const requestStatus = trimmed.match(/^Request\s+(APPROVED|REJECTED|PENDING)$/i);
    if (requestStatus) return normalizedStatus[requestStatus[1].toUpperCase()];
    const employeeInfo = trimmed.match(/^View\s+(.+)\s+information$/i);
    if (employeeInfo) return `عرض معلومات ${employeeInfo[1]}`;
    const uploaded = trimmed.match(/^(\d+) file\(s\) uploaded successfully\.$/);
    if (uploaded) return `تم رفع ${uploaded[1]} ملف بنجاح.`;
    const documents = trimmed.match(/^(\d+) document\(s\) saved successfully\.$/);
    if (documents) return `تم حفظ ${documents[1]} مستند بنجاح.`;
    const savedUsers = trimmed.match(/^Saved changes for (\d+) users\.$/);
    if (savedUsers) return `تم حفظ تغييرات ${savedUsers[1]} مستخدم.`;
    const selectedCount = trimmed.match(/^(\d+) (employees|watchers) selected$/i);
    if (selectedCount) return `تم اختيار ${selectedCount[1]} ${selectedCount[2].toLowerCase() === 'watchers' ? 'متابعين' : 'موظفين'}`;
    const initialTasks = trimmed.match(/^(\d+) initial tasks created\.$/);
    if (initialTasks) return `تم إنشاء ${initialTasks[1]} مهمة أولية.`;
    const unableUpload = trimmed.match(/^Unable to upload (.+)\.$/);
    if (unableUpload) return `تعذر رفع ${unableUpload[1]}.`;
    const unknownColumn = trimmed.match(/^Unknown column: (.+)\. The database may need a migration to be run\.$/);
    if (unknownColumn) return `عمود غير معروف: ${unknownColumn[1]}. قد تحتاج قاعدة البيانات إلى تشغيل ملف ترحيل.`;
    return source;
}

function localizeNotificationMessage(value) {
    const source = String(value ?? '');
    if (currentLang !== 'ar' || !source.trim()) return source;
    const rules = [
        [/^Your leave request has been (.+)\.$/i, match => `تم تحديث طلب إجازتك إلى: ${taskDetailValue(match[1], 'status')}.`],
        [/^Your expense request has been (.+)\.$/i, match => `تم تحديث طلب المصروفات إلى: ${taskDetailValue(match[1], 'status')}.`],
        [/^You have been assigned a new task:\s*(.+)$/i, match => `تم تعيين مهمة جديدة لك: ${match[1]}`],
        [/^A new task requires your approval:\s*(.+)$/i, match => `توجد مهمة جديدة تتطلب موافقتك: ${match[1]}`],
        [/^Project created:\s*(.+)$/i, match => `تم إنشاء المشروع: ${match[1]}`],
        [/^Task "(.+)" was returned to In Progress by the department manager\.$/i, match => `أعاد مدير القسم المهمة «${match[1]}» إلى قيد التنفيذ.`],
        [/^Your Designing task "(.+)" was rejected by the manager\. Reason:\s*(.+)$/i, match => `رفض المدير مهمة التصميم «${match[1]}». السبب: ${match[2]}`],
        [/^Your task "(.+)" was rejected and deleted\.$/i, match => `تم رفض مهمتك «${match[1]}» وحذفها.`],
        [/^Your task "(.+)" was approved\.$/i, match => `تمت الموافقة على مهمتك «${match[1]}».`]
    ];
    for (const [pattern, formatter] of rules) {
        const match = source.match(pattern);
        if (match) return formatter(match);
    }
    const localized = localizeRuntimeText(source);
    if (localized === source && /[A-Za-z]{2,}/.test(source) && !/[\u0600-\u06FF]/.test(source)) return 'لديك تحديث جديد.';
    return localized;
}

function translateArabicInterface(root = document) {
    if (currentLang !== 'ar' || !root?.querySelectorAll) return;
    const selectors = [
        'button', 'label', 'legend', 'th', 'dt', 'option', '[role="tab"]',
        '.topbar', '.sidebar-nav', '.page-header', '.page-title', '.section-header',
        '.modal-header', '.modal-footer', '.modal-content > h1', '.modal-content > h2',
        '.modal-content > h3', '.view-container h1', '.view-container h2',
        '.view-container h3', '.view-container h4', '.view-container p',
        '.form-label', '.card-title', '.page-subtitle', '.empty-state',
        '.task-assignee-picker-help', '.task-assignee-picker-empty',
        '.modal-header h2', '.status-badge', '.property-cell > span',
        '.hierarchy-square-title', '.hierarchy-employee-card-header p',
        '.task-health-heading', '.task-health-item', '.task-health-total',
        '.task-health-new-task', '.task-focus-kicker', '.task-focus-header h3',
        '.task-v2-view-toggles', '#taskSidePanel h3',
        '.create-task-attachments-heading', '.create-task-upload-zone span',
        '.employee-details-kicker', '.employee-details-grid > div > span',
        '.edit-task-list-indicator', '.select-ui-value', '.date-ui-value',
        '.estimate-ui-value', '.watchers-ui-value', '.category-ui-value',
        '.file-dropzone p', '.files-section > span', '.floating-input-group label',
        '.edit-task-tabs', '.text-muted', '.alert', '.task-list-name',
        '.task-v2-sidebar-header h3', '.custom-multi-select-header'
    ].join(',');
    root.querySelectorAll(selectors).forEach(element => {
        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
        const nodes = [];
        while (walker.nextNode()) nodes.push(walker.currentNode);
        nodes.forEach(node => {
            const translated = localizeRuntimeText(node.nodeValue);
            if (translated !== node.nodeValue) node.nodeValue = translated;
        });
    });
    root.querySelectorAll('[placeholder], [title], [aria-label]').forEach(element => {
        ['placeholder', 'title', 'aria-label'].forEach(attribute => {
            if (!element.hasAttribute(attribute)) return;
            const value = element.getAttribute(attribute);
            const translated = localizeRuntimeText(value);
            if (translated !== value) element.setAttribute(attribute, translated);
        });
    });
}

// Generate Ring SVG
function getRingSVG(percentage, color, labelKey) {
    return `
        <div class="ring-item">
            <svg viewBox="0 0 36 36" class="circular-chart" style="stroke: ${color}">
                <path class="circle-bg"
                d="M18 2.0845
                    a 15.9155 15.9155 0 0 1 0 31.831
                    a 15.9155 15.9155 0 0 1 0 -31.831"
                />
                <path class="circle"
                stroke-dasharray="${percentage}, 100"
                d="M18 2.0845
                    a 15.9155 15.9155 0 0 1 0 31.831
                    a 15.9155 15.9155 0 0 1 0 -31.831"
                />
                <text x="18" y="20.35" class="ring-text">${percentage}%</text>
            </svg>
            <span class="ring-label">${t(labelKey)}</span>
        </div>
    `;
}

// --- TOAST NOTIFICATIONS ---
function showToast(message, type = 'info', detail = '') {
    if (type === 'error') type = 'danger';
    let container = document.getElementById('toast-container');
    if (!container) {
        container = document.createElement('div');
        container.id = 'toast-container';
        container.className = 'toast-container';
        document.body.appendChild(container);
    }

    const toast = document.createElement('div');
    toast.className = 'toast';

    let icon = 'info';
    let color = 'var(--color-accent)';
    let duration = 4000;

    if (type === 'success') {
        icon = 'check-circle';
        color = 'var(--color-success)';
        duration = 3500;
    } else if (type === 'warning') {
        icon = 'alert-triangle';
        color = 'var(--color-warning)';
        duration = 5000;
    } else if (type === 'danger') {
        icon = 'x-circle';
        color = '#ef4444';
        duration = 6000;
    }

    // Parse Supabase/PostgREST error detail if message looks technical
    let displayMessage = message;
    let displayDetail = detail;
    if (type === 'danger' && !detail) {
        if (message && message.includes('column')) {
            const colMatch = message.match(/column "([^"]+)"/);
            if (colMatch) displayDetail = `Unknown column: "${colMatch[1]}". The database may need a migration to be run.`;
        } else if (message && /row-level security|permission denied|not authorized/i.test(message)) {
            displayMessage = 'Permission Denied';
            displayDetail = 'The database permissions migration has not been applied. Run onboarding_create_user_permission_repair.sql; for task creation, also run tasks_insert_permission_repair.sql, then try again.';
        } else if (message && message.includes('violates')) {
            displayDetail = 'A database constraint was violated. Please check your input values.';
        } else if (message && message.includes('duplicate')) {
            displayDetail = 'This record already exists. Please use a unique value.';
        } else if (message && message.includes('not-null')) {
            displayDetail = 'A required field is missing. Please fill in all required fields.';
        } else if (message && (message.includes('Failed to fetch') || message.includes('NetworkError') || message.includes('ERR_INTERNET'))) {
            displayMessage = 'Connection Error';
            displayDetail = 'Cannot reach the server. Please check your internet connection and try again.';
        } else if (message && message.includes('JWT')) {
            displayMessage = 'Session Expired';
            displayDetail = 'Your session has expired. Please log in again.';
        } else if (message && message.includes('permission denied')) {
            displayMessage = 'Permission Denied';
            displayDetail = 'You do not have permission to perform this action. Please contact your administrator.';
        }
    }

    displayMessage = localizeRuntimeText(displayMessage);
    displayDetail = localizeRuntimeText(displayDetail);
    if (currentLang === 'ar') {
        if (/[A-Za-z]{2,}/.test(displayMessage) && !/[\u0600-\u06FF]/.test(displayMessage)) {
            displayMessage = 'حدث خطأ غير متوقع';
        }
        if (/[A-Za-z]{2,}/.test(displayDetail) && !/[\u0600-\u06FF]/.test(displayDetail)) {
            displayDetail = 'يرجى المحاولة مرة أخرى أو التواصل مع مسؤول النظام.';
        }
    }

    toast.style.borderInlineStartColor = color;
    toast.innerHTML = `
        <div style="display:flex; align-items:flex-start; gap:0.75rem;">
            <i data-lucide="${icon}" style="color: ${color}; flex-shrink:0; margin-top:2px;"></i>
            <div>
                <div style="font-weight:600; font-size:0.9rem;">${displayMessage}</div>
                ${displayDetail ? `<div style="font-size:0.8rem; margin-top:0.25rem; opacity:0.85;">${displayDetail}</div>` : ''}
            </div>
        </div>
    `;

    container.appendChild(toast);
    lucide.createIcons();

    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(110%)';
        setTimeout(() => toast.remove(), 400);
    }, duration);
}

/**
 * Highlight a form field with an error and show an inline message beneath it.
 * @param {string} fieldId - The ID of the input/select element
 * @param {string} message - The error message to display
 */
window.showFieldError = function (fieldId, message) {
    const el = document.getElementById(fieldId);
    if (!el) return;

    // Clear previous error on the field
    clearFieldError(fieldId);

    el.style.borderColor = '#ef4444';
    el.style.boxShadow = '0 0 0 3px rgba(239, 68, 68, 0.2)';
    el.style.transition = 'border-color 0.2s, box-shadow 0.2s';

    const err = document.createElement('div');
    err.className = '__field-error';
    err.dataset.for = fieldId;
    err.style.cssText = 'color:#ef4444; font-size:0.78rem; margin-top:0.3rem; display:flex; align-items:center; gap:0.3rem; animation: fadeIn 0.2s ease;';
    err.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>${localizeRuntimeText(message)}`;

    el.parentNode.insertBefore(err, el.nextSibling);
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    el.focus();

    el.addEventListener('input', () => clearFieldError(fieldId), { once: true });
    el.addEventListener('change', () => clearFieldError(fieldId), { once: true });
};

window.clearFieldError = function (fieldId) {
    const el = document.getElementById(fieldId);
    if (el) {
        el.style.borderColor = '';
        el.style.boxShadow = '';
    }
    document.querySelectorAll(`.__field-error[data-for="${fieldId}"]`).forEach(e => e.remove());
};


// Global Handlers


// Community View
async function renderCommunity() {
    const messages = await db.fetchCommunityChat();

    let chatHTML = messages.map(m => `
        <div style="display:flex; gap:1rem; margin-bottom:1.5rem; ${m.user_id === currentUser.id ? 'flex-direction:row-reverse;' : ''}">
            <div style="width:40px; height:40px; border-radius:50%; background:var(--color-surface-hover); flex-shrink:0; overflow:hidden; display:flex; align-items:center; justify-content:center;">
                ${m.profiles.avatar_url ? `<img src="${m.profiles.avatar_url}" style="width:100%;height:100%;object-fit:cover;">` : `<i data-lucide="user"></i>`}
            </div>
            <div style="max-width:70%; ${m.is_birthday_alert ? 'background: linear-gradient(135deg, #fce7f3, #fbcfe8); border: 1px solid #f9a8d4;' : (m.user_id === currentUser.id ? 'background:var(--color-primary); color:white;' : 'background:var(--color-surface); border:1px solid var(--color-border);')} padding:1rem; border-radius:8px;">
                <div style="font-size:0.85rem; font-weight:600; margin-bottom:0.25rem; ${m.user_id === currentUser.id ? 'color:rgba(255,255,255,0.9);' : 'color:var(--color-text-secondary);'}">${window.formatEmployeeName(m.profiles)}</div>
                <div style="${m.is_birthday_alert ? 'font-weight:bold; font-size:1.1rem; color: #be185d;' : ''}">${m.message}</div>
                <div style="font-size:0.75rem; margin-top:0.5rem; ${m.user_id === currentUser.id ? 'color:rgba(255,255,255,0.7);' : 'color:var(--color-text-tertiary);'}">${new Date(m.created_at).toLocaleString()}</div>
            </div>
        </div>
    `).join('');

    if (messages.length === 0) chatHTML = `<p style="text-align:center; color:var(--color-text-secondary);">No messages yet. Be the first to post!</p>`;

    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('community_chat')}</h1>
                <p class="page-subtitle">${t('ui_connect_colleagues') || 'Connect with your colleagues!'}</p>
            </div>
        </div>
        <div class="dashboard-grid">
            <div class="card col-span-12">
                <div style="max-height:600px; overflow-y:auto; padding-right:1rem; display:flex; flex-direction:column-reverse;" id="communityChatBox">
                    ${chatHTML}
                </div>
                <form onsubmit="handlePostCommunityMessage(event)" style="margin-top:1.5rem; display:flex; gap:1rem;">
                    <input type="text" id="communityMessageInput" class="form-control" placeholder="${t('ph_type_message') || 'Type a message...'}" required style="flex:1;">
                    <button type="submit" class="btn-primary">${t('ui_post')}</button>
                </form>
            </div>
        </div>
    `;
}

window.handlePostCommunityMessage = async (e) => {
    e.preventDefault();
    const input = document.getElementById('communityMessageInput');
    const msg = input.value.trim();
    if (msg) {
        await db.postCommunityMessage(currentUser.id, msg);
        renderView('community');
    }
};

window.handleLogout = async function () {
    try {
        await db.logout();
    } catch (error) {
        console.error("Logout error:", error);
    }

    stopRecentLoginsRealtime();
    if (notificationsInterval) {
        clearInterval(notificationsInterval);
        notificationsInterval = null;
    }
    // Preserve custom translations and other important local preferences across logins
    const customI18n = localStorage.getItem('custom_i18n');
    const pwaPrompt = localStorage.getItem('pwaPromptDismissed');
    const appLang = localStorage.getItem('app_lang');

    localStorage.clear();

    if (customI18n) localStorage.setItem('custom_i18n', customI18n);
    if (pwaPrompt) localStorage.setItem('pwaPromptDismissed', pwaPrompt);
    if (appLang) localStorage.setItem('app_lang', appLang);
    sessionStorage.clear();

    // Clear Payroll Modals and Forms for security
    const payrollForms = ['payrollLogSalesForm', 'payrollLogAbsenceForm', 'payrollNewLoanForm'];
    payrollForms.forEach(id => {
        const form = document.getElementById(id);
        if (form) form.reset();
    });
    const payslipModal = document.getElementById('payslipModal');
    if (payslipModal) {
        const payslipContent = document.getElementById('payslipContent');
        if (payslipContent) payslipContent.innerHTML = '';
    }

    currentUser = null;
    currentUserRole = null;
    currentUserProfile = null;
    currentView = 'login';
    viewHistory = [];
    document.querySelector('.sidebar').style.display = 'none';
    document.querySelector('.topbar').style.display = 'none';
    await renderView('login');
}

window.handleLeaveSubmit = async function (e) {
    e.preventDefault();
    const type = document.getElementById('leaveType').value;
    const isShortLeave = type === 'Short Leave';
    const today = new Date().toISOString().slice(0, 10);
    const start = isShortLeave ? today : document.getElementById('leaveStart').value;
    const end = isShortLeave ? today : document.getElementById('leaveEnd').value;
    const shortReason = isShortLeave ? document.getElementById('leaveShortReason').value : null;
    const shortDuration = isShortLeave ? Number(document.getElementById('leaveShortDuration').value) : null;
    const reason = isShortLeave ? shortReason : document.getElementById('leaveReason').value;

    const success = await db.submitLeaveRequest(currentUser.id, {
        leave_type: type,
        start_date: start,
        end_date: end,
        reason: reason,
        short_leave_reason: shortReason,
        short_leave_duration_minutes: shortDuration
    });

    if (success) {
        showToast(t('toast_leave_applied'), 'success');
        renderView('leave');
    } else {
        showToast(t('toast_failed_to_submit_leave'), 'danger');
    }
}

window.handleLeaveAction = async function (id, status, employeeId) {
    const { success } = await db.updateLeaveStatus(id, status);
    if (success) {
        showToast(`Leave request ${status.toLowerCase()}`, 'success');
        if (employeeId) await db.createNotification(employeeId, `Your leave request has been ${status}.`);
        renderView(currentView);
    }
}


async function getCurrentDepartmentName() {
    const profile = currentUserProfile || currentUser || {};
    if (!profile.department_id) return '';
    window.sidebarDepartmentsCache ||= await db.fetchDepartments();
    return window.sidebarDepartmentsCache.find(department => department.id === profile.department_id)?.name || '';
}

async function canCurrentUserAccessView(viewId) {
    const normalizedRole = String(currentUserRole || currentUserProfile?.role || '').toUpperCase();
    const isAdmin = ['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(normalizedRole);
    if (isAdmin) return true;
    if (viewId === 'leave_calculator') return normalizedRole === 'HR_MANAGER' || /HR\s*MANAGER/i.test(String(currentUserProfile?.job_title || ''));
    if (normalizedRole === 'EMPLOYEE') {
        return new Set(['dashboard', 'requests', 'time', 'tasks', 'documents', 'profile']).has(viewId);
    }
    if (viewId === 'employees') return normalizedRole !== 'EMPLOYEE';
    if (viewId === 'archived_contracts') return normalizedRole !== 'EMPLOYEE' && window.canCurrentUserEditContracts();

    if (viewId === 'projects' || viewId === 'crm' || viewId === 'clients') {
        const dept = (await getCurrentDepartmentName()).trim().toLowerCase();
        return normalizedRole === 'EMPLOYEE' && (dept === 'marketing & sales' || dept === 'sales' || dept === 'marketing');
    }

    return true;
}

window.updateSidebarVisibility = async function () {
    const normalizedRole = String(currentUserRole || currentUserProfile?.role || '').toUpperCase();
    const adminNav = document.querySelector('.nav-item[data-view=\'admin\']');
    const usersNav = document.querySelector('.nav-item[data-view=\'users\']');
    const analyticsNav = document.querySelector('.nav-item[data-view=\'analytics\']');
    const employeesNav = document.querySelector('.nav-item[data-view=\'employees\']');
    const departmentsNav = document.querySelector('.nav-item[data-view=\'departments\']');
    const translationsNav = document.querySelector('.nav-item[data-view=\'translations\']');
    const templatesNav = document.getElementById('navTemplates');
    const approvalsNav = document.getElementById('navApprovals');
    const payrollNav = document.getElementById('navPayroll');
    const projectsNav = document.querySelector('.nav-item[data-view="projects"]');
    const crmNav = document.querySelector('.nav-item[data-view="crm"]');
    const clientsNav = document.querySelector('.nav-item[data-view="clients"]');
    const leaveCalculatorNav = document.getElementById('navLeaveCalculator');

    const isAdmin = ['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(normalizedRole);
    const isHrManager = normalizedRole === 'HR_MANAGER' || /HR\s*MANAGER/i.test(String(currentUserProfile?.job_title || ''));
    const employeeAllowedViews = new Set(['dashboard', 'requests', 'time', 'tasks', 'documents', 'employees']);
    document.querySelectorAll('.sidebar-nav > .nav-item[data-view]').forEach(item => {
        if (normalizedRole === 'EMPLOYEE') {
            item.style.display = employeeAllowedViews.has(item.dataset.view) ? 'flex' : 'none';
        }
    });
    if (adminNav) adminNav.style.display = isAdmin ? 'flex' : 'none';
    if (usersNav) usersNav.style.display = isAdmin ? 'flex' : 'none';
    if (analyticsNav) analyticsNav.style.display = 'none';
    if (employeesNav) employeesNav.style.display = 'flex';
    if (departmentsNav) departmentsNav.style.display = isAdmin ? 'flex' : 'none';
    if (translationsNav) translationsNav.style.display = isAdmin ? 'flex' : 'none';
    if (templatesNav) templatesNav.style.display = isAdmin ? 'flex' : 'none';
    if (leaveCalculatorNav) leaveCalculatorNav.style.display = (isAdmin || isHrManager) ? 'flex' : 'none';
    const custodyHandoverNav = document.getElementById('navCustodyHandover');
    if (custodyHandoverNav) custodyHandoverNav.style.display = (isAdmin || isHrManager) ? 'flex' : 'none';

    const isAccountantManager = currentUserProfile && /accountant manager|finance manager/i.test(currentUserProfile.job_title || '');
    if (payrollNav) payrollNav.style.display = (isAdmin || isAccountantManager) ? 'flex' : 'none';

    const canUseMarketingPages = isAdmin || (normalizedRole === 'EMPLOYEE' && (['marketing & sales', 'sales', 'marketing'].includes((await getCurrentDepartmentName()).trim().toLowerCase())));
    if (projectsNav) projectsNav.style.display = canUseMarketingPages ? 'flex' : 'none';
    if (crmNav) crmNav.style.display = canUseMarketingPages ? 'flex' : 'none';
    if (clientsNav) clientsNav.style.display = canUseMarketingPages ? 'flex' : 'none';

    let isHussain = false;
    if (typeof currentUser !== 'undefined' && currentUser) {
        isHussain = (currentUser.full_name && currentUser.full_name.toLowerCase().includes('hussain')) || (currentUser.email && currentUser.email.toLowerCase().includes('hussain'));
    }
    if (approvalsNav) approvalsNav.style.display = (isAdmin || ['MANAGER', 'SUPERVISOR'].includes(normalizedRole) || isHussain) ? 'flex' : 'none';
};

window.handleLoginSubmit = async function (e) {
    e.preventDefault();
    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;

    const lockoutData = await db.checkLoginLockout(email);
    if (lockoutData && lockoutData.locked_until) {
        const lockedUntil = new Date(lockoutData.locked_until);
        if (lockedUntil > new Date()) {
            showToast(`Account locked due to multiple failed attempts. Please contact Admin.`, 'danger');
            return;
        }
    }

    const loginBtn = e.target.querySelector('button[type="submit"]');
    const originalBtnText = loginBtn.innerHTML;
    loginBtn.innerHTML = `<span class="spinner-sm" style="margin-right: 0.5rem;"></span> ${t('sign_in') || 'Signing in...'}`;
    loginBtn.disabled = true;
    lucide.createIcons();

    const { user, error } = await db.login(email, password);

    loginBtn.innerHTML = originalBtnText;
    loginBtn.disabled = false;

    if (error || !user) {
        console.error("Login Error:", error);
        await db.recordFailedLogin(email);
        showToast(error?.message || t('invalid_credentials'), 'danger');
        return;
    }

    await db.resetLoginLockout(email);

    currentUser = user;

    // Update last_login
    await db.updateLastLogin(user.id);

    const profile = await db.getUserProfile(user.id);
    if (profile) {
        await syncLegacyLocalProfilePhoto(profile);
        currentUserProfile = profile;
        currentUserRole = profile.role;
        applyPreferredTheme(profile);
        updateTopbarProfile(profile);
        // Check for Birthday
        if (profile.birth_date) {
            const today = new Date();
            const bday = new Date(profile.birth_date);
            if (today.getMonth() === bday.getMonth() && today.getDate() === bday.getDate()) {
                const bdayMessage = `ðŸŽ‰ ${t('birthday_msg')} ${window.formatEmployeeName(profile)}! ðŸŽ‚ðŸŽˆ`;

                // Check if we already posted it today to prevent duplicates
                const chat = await db.fetchCommunityChat();
                const alreadyPosted = chat.some(m => m.user_id === user.id && m.is_birthday_alert && new Date(m.created_at).toDateString() === today.toDateString());

                if (!alreadyPosted) {
                    await db.postCommunityMessage(user.id, bdayMessage, true);
                    showToast(t('birthday_msg'), 'success');
                }
            }
        }
    }

    // Show sidebar and topbar again
    document.querySelector('.sidebar').style.display = '';
    document.querySelector('.topbar').style.display = 'flex';

    // Hide/Show Role-Specific Nav Items
    window.updateSidebarVisibility();

    // Route based on role - restore last view or fallback to dashboard
    const _loginRestorableViews = new Set([
        'dashboard', 'time', 'leave', 'requests', 'archived',
        'payroll', 'expenses', 'analytics', 'admin', 'users', 'employees',
        'archived_contracts', 'messages', 'notifications', 'performance',
        'documents', 'profile', 'projects', 'approvals', 'tasks',
        'departments', 'translations', 'clients', 'crm', 'schedule', 'integrations', 'custody_handover'
    ]);
    const _loginRequestedView = new URLSearchParams(window.location.search).get('view');
    const _loginSavedView = _loginRequestedView || (currentUser ? (localStorage.getItem(`muqam_hr_last_view_${currentUser.id}`) || localStorage.getItem('muqam_hr_last_view')) : null);
    currentView = (_loginSavedView && _loginRestorableViews.has(_loginSavedView)) ? _loginSavedView : 'dashboard';
    // Do not restore a sidebar page hidden for this user's role
    const _loginRestoredNav = document.querySelector(`.nav-item[data-view="${currentView}"]`);
    if (_loginRestoredNav && _loginRestoredNav.style.display === 'none') currentView = 'dashboard';
    renderView(currentView);
}

// Render Login View
window.togglePasswordVisibility = function (inputId) {
    const input = document.getElementById(inputId);
    const icon = document.getElementById(inputId + '-eye-icon');
    if (input.type === 'password') {
        input.type = 'text';
        icon.setAttribute('data-lucide', 'eye-off');
    } else {
        input.type = 'password';
        icon.setAttribute('data-lucide', 'eye');
    }
    lucide.createIcons();
}

window.setLoginMode = function (mode) {
    loginMode = mode;
    renderView('login');
}

window.handleForgotPasswordSubmit = async function (e) {
    e.preventDefault();
    const email = document.getElementById('reset-email').value;
    const { error } = await db.sendPasswordResetEmail(email);
    if (error) {
        showToast(error.message, 'danger');
    } else {
        showToast(t('reset_link_sent'), 'success');
        setLoginMode('login');
    }
}

window.handleResetPasswordSubmit = async function (e) {
    e.preventDefault();
    const newPassword = document.getElementById('new-password').value;
    const { data, error } = await db.updatePassword(newPassword);
    if (error) {
        showToast(error.message, 'danger');
    } else {
        showToast(t('toast_password_updated_successfully'), 'success');
        window.location.hash = ''; // Clear hash
        setLoginMode('login');
    }
}

function renderLogin() {
    // Hide sidebar and topbar for full screen login
    const sidebar = document.querySelector('.sidebar');
    const topbar = document.querySelector('.topbar');
    if (sidebar) sidebar.style.display = 'none';
    if (topbar) topbar.style.display = 'none';

    let formHTML = '';

    if (loginMode === 'forgot') {
        formHTML = `
            <div style="text-align: center; margin-bottom: 2rem;">
                <div class="logo" style="justify-content: center; margin-bottom: 2rem;">
                    <img src="/images/logo.png" alt="MUQAM HR Logo" class="app-logo" style="max-height: 60px;">
                </div>
                <h2 style="margin-top: 1rem; font-size: 1.25rem;">${t('reset_password')}</h2>
                <p style="color: var(--color-text-secondary); font-size: 0.875rem;">${t('reset_email_instruction')}</p>
            </div>
            <form autocomplete="off" onsubmit="handleForgotPasswordSubmit(event)">
                <div class="form-group" style="margin-bottom: 1.5rem;">
                    <label class="form-label">${t('email_label')}</label>
                    <input type="email" autocomplete="off" id="reset-email" class="form-control" placeholder="name@company.com" required>
                </div>
                <button type="submit" class="btn-primary" style="width: 100%; padding: 0.875rem; font-size: 1rem;">${t('send_reset_link')}</button>
                <div style="text-align: center; margin-top: 1rem;">
                    <a href="#" onclick="setLoginMode('login')" style="color: var(--color-primary); font-size: 0.875rem;">${t('back_to_login')}</a>
                </div>
            </form>
        `;
    } else if (loginMode === 'reset') {
        formHTML = `
            <div style="text-align: center; margin-bottom: 2rem;">
                <div class="logo" style="justify-content: center; margin-bottom: 2rem;">
                    <img src="/images/logo.png" alt="MUQAM HR Logo" class="app-logo" style="max-height: 60px;">
                </div>
                <h2 style="margin-top: 1rem; font-size: 1.25rem;">${t('set_new_password')}</h2>
            </div>
            <form autocomplete="off" onsubmit="handleResetPasswordSubmit(event)">
                <div class="form-group" style="margin-bottom: 1.5rem; position: relative;">
                    <label class="form-label">${t('new_password_label')}</label>
                    <input type="password" autocomplete="new-password" id="new-password" class="form-control" required style="padding-right: 40px;">
                    <button type="button" class="password-toggle-btn" onclick="togglePasswordVisibility('new-password')" style="color: white;">
                        <i data-lucide="eye" id="new-password-eye-icon" style="width: 20px; height: 20px;"></i>
                    </button>
                </div>
                <button type="submit" class="btn-primary" style="width: 100%; padding: 0.875rem; font-size: 1rem;">${t('set_new_password')}</button>
            </form>
        `;
    } else {
        formHTML = `
            <div style="text-align: center; margin-bottom: 2rem;">
                <div class="logo" style="justify-content: center; margin-bottom: 2rem;">
                    <img src="/images/logo.png" alt="MUQAM HR Logo" class="app-logo" style="max-height: 60px;">
                </div>
                <h2 style="margin-top: 1rem; font-size: 1.25rem;">${t('login_title')}</h2>
                <p style="color: var(--color-text-secondary); font-size: 0.875rem;">${t('login_subtitle')}</p>
            </div>
            <form autocomplete="off" onsubmit="handleLoginSubmit(event)">
                <div class="form-group">
                    <label class="form-label">${t('email_label')}</label>
                    <input type="email" autocomplete="off" id="email" class="form-control" placeholder="name@company.com" required>
                </div>
                <div class="form-group" style="margin-bottom: 0.5rem; position: relative;">
                    <label class="form-label">${t('password_label')}</label>
                    <input type="password" autocomplete="new-password" id="password" class="form-control" required style="padding-right: 40px;">
                    <button type="button" class="password-toggle-btn" onclick="togglePasswordVisibility('password')" style="color: white;">
                        <i data-lucide="eye" id="password-eye-icon" style="width: 20px; height: 20px;"></i>
                    </button>
                </div>
                <div style="text-align: right; margin-bottom: 1.5rem;">
                    <a href="#" onclick="setLoginMode('forgot')" style="color: white; font-size: 0.85rem; text-decoration: none;">${t('forgot_password')}</a>
                </div>
                <button type="submit" class="btn-primary" style="width: 100%; padding: 0.875rem; font-size: 1rem;">${t('sign_in')}</button>
            </form>
        `;
    }

    return `
        <style>
            .login-card-wrapper,
            .login-card-wrapper h2,
            .login-card-wrapper p,
            .login-card-wrapper label,
            .login-card-wrapper a {
                color: #FFFFFF !important;
            }
        </style>
        <div style="display: flex; height: 100vh; align-items: center; justify-content: center; width: 100vw; position: fixed; top: 0; left: 0; background: url('images/login_bg.png') center/cover no-repeat; z-index: 9999;">
            <div class="card login-card-wrapper" style="width: 100%; max-width: 400px; padding: 2.5rem 2rem; background: rgba(0, 0, 0, 0.4); backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); border: 1px solid rgba(255, 255, 255, 0.2); box-shadow: 0 30px 60px rgba(0,0,0,0.3); color: white;">
                ${formHTML}
            </div>
            
            <div style="position: absolute; top: 20px; right: 20px; display: flex; gap: 10px; z-index: 10000;">
                <button class="icon-btn" onclick="toggleLanguage()">
                    <i data-lucide="globe"></i> <span id="langText" style="font-size: 0.875rem; font-weight: 600; margin-inline-start: 4px;">${currentLang === 'en' ? 'AR' : 'EN'}</span>
                </button>
                <button class="icon-btn" onclick="toggleTheme()">
                    <i id="themeIcon" data-lucide="${currentTheme === 'light' ? 'moon' : 'sun'}"></i>
                </button>
            </div>
        </div>
    `;
}

async function renderTeamHierarchyWidget() {
    const fetchedUsers = (await db.fetchUsers()) || [];
    const currentProfile = fetchedUsers.find(user => user.id === currentUser?.id) || currentUser || {};
    const normalizedRole = String(currentUserRole || currentProfile.role || '').toUpperCase();
    const isOwner = normalizedRole === 'OWNER' || /^owner$/i.test(String(currentProfile.job_title || '').trim());
    const isDepartmentEmployee = normalizedRole === 'EMPLOYEE' && !isOwner;
    // Employees receive only their department's profiles. This limits the data
    // used by both the hierarchy renderer and its employee lookup cache.
    let myDeptHeadId = null;
    if (currentProfile.department_id) {
        const departments = (await db.fetchDepartments()) || [];
        const myDept = departments.find(d => d.id === currentProfile.department_id);
        if (myDept && myDept.head_id) {
            myDeptHeadId = myDept.head_id;
        }
    }

    let allUsers = fetchedUsers;
    if (isDepartmentEmployee) {
        allUsers = fetchedUsers.filter(user => 
            user.id === currentProfile.manager_id || 
            user.manager_id === currentProfile.manager_id || 
            (currentProfile.department_id && user.department_id === currentProfile.department_id) ||
            user.manager_id === currentProfile.id ||
            (myDeptHeadId && user.id === myDeptHeadId)
        );
    }
    if (!allUsers || allUsers.length === 0) {
        return `
            <div class="card col-span-12">
                <div class="card-title" style="display: flex; align-items: center; gap: 0.5rem; border-bottom: 1px solid var(--color-border); padding-bottom: 0.75rem; margin-bottom: 1rem;">
                    <i data-lucide="git-fork" style="width: 20px; height: 20px; color: var(--color-accent);"></i>
                    <span>${t('team_hierarchy')}</span>
                </div>
                <p style="color:var(--color-text-secondary); font-size:0.85rem; padding: 1rem 0;">${t('team_no_members')}</p>
            </div>
        `;
    }

    window.hierarchyProfilesById = Object.fromEntries(allUsers.map(user => [user.id, user]));
    const canViewEmployeeInfo = ['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN', 'MANAGER', 'SUPERVISOR'].includes(normalizedRole);
    let rootUsers = [];
    if (['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(normalizedRole)) {
        const owners = allUsers.filter(u => /^owner$/i.test(String(u.job_title || '').trim()) || u.role === 'OWNER');
        const othersNoManager = allUsers.filter(u => !u.manager_id && !owners.some(o => o.id === u.id));
        rootUsers = [...owners, ...othersNoManager];
    } else if (normalizedRole === 'MANAGER') {
        rootUsers = allUsers.filter(u => u.id === currentUser.id);
    } else if (isDepartmentEmployee) {
        let deptUsers = allUsers.filter(u => u.department_id === currentProfile.department_id || (myDeptHeadId && u.id === myDeptHeadId) || u.id === currentProfile.manager_id);
        rootUsers = deptUsers.filter(u => !u.manager_id || !deptUsers.some(d => d.id === u.manager_id));
    } else {
        let myMgr = allUsers.find(u => u.id === currentUser.manager_id);
        if (myMgr) {
            let parentMgr = allUsers.find(u => u.id === myMgr.manager_id);
            rootUsers = parentMgr ? [parentMgr] : [myMgr];
        } else {
            rootUsers = [currentUser];
        }
    }

    rootUsers = Array.from(new Set(rootUsers.map(u => u.id))).map(id => allUsers.find(u => u.id === id)).filter(Boolean);

    function renderNodeSquare(user, visited = new Set()) {
        if (visited.has(user.id)) return '';
        visited.add(user.id);

        const isSelf = user.id === currentUser.id;
        const reports = allUsers.filter(u => u.manager_id === user.id);

        let roleBadgeClass = 'info';
        if (user.role === 'ADMIN') roleBadgeClass = 'danger';
        else if (user.role === 'MANAGER') roleBadgeClass = 'primary';
        else if (user.role === 'SUPERVISOR') roleBadgeClass = 'warning';

        const userAvatar = user.avatar_url || localStorage.getItem('user_avatar_' + user.id) || '';
        const hasCustomAvatar = userAvatar && typeof userAvatar === 'string' && userAvatar.trim().length > 0;
        const avatarContent = hasCustomAvatar
            ? `<img src="${escapeHTML(userAvatar.trim())}" class="hierarchy-square-avatar" alt="${escapeHTML(window.formatEmployeeName(user) || 'Employee')}" onerror="this.hidden=true;this.nextElementSibling.hidden=false;">
               <span class="hierarchy-square-avatar hierarchy-avatar-placeholder" hidden aria-label="Profile photo unavailable"><i data-lucide="user"></i></span>`
            : `<span class="hierarchy-square-avatar hierarchy-avatar-placeholder" aria-label="No profile photo"><i data-lucide="user"></i></span>`;
        const avatarMarkup = canViewEmployeeInfo
            ? `<button type="button" class="hierarchy-avatar-button" aria-label="View ${escapeHTML(window.formatEmployeeName(user) || 'employee')} information" onclick="openHierarchyEmployeeInfo('${user.id}')">${avatarContent}</button>`
            : avatarContent;

        return `
            <div style="display: flex; flex-direction: column; align-items: center;">
                <div class="hierarchy-square-card ${isSelf ? 'is-self-card' : ''}">
                    ${avatarMarkup}
                    <div style="width: 100%;">
                        <div class="hierarchy-square-name" title="${escapeHTML(window.formatEmployeeName(user) || 'Employee')}">${escapeHTML(window.formatEmployeeName(user) || 'Employee')}</div>
                        <div class="hierarchy-square-title" title="${escapeHTML(user.job_title || 'Team Member')}">${escapeHTML(user.job_title || 'Team Member')}</div>
                    </div>
                    <div style="display: flex; align-items: center; gap: 0.3rem; margin-top: auto;">
                        <span class="status-badge ${roleBadgeClass}" style="font-size:0.65rem; text-transform: uppercase;">${user.role}</span>
                        ${isSelf ? '<span class="status-badge success" style="font-size:0.65rem; padding:1px 5px;">You</span>' : ''}
                    </div>
                </div>

                ${reports.length > 0 ? `
                    <div style="width: 2px; height: 16px; background: var(--color-border); margin: 0.2rem 0;"></div>
                    <div class="hierarchy-level-group">
                        ${reports.map(r => renderNodeSquare(r, visited)).join('')}
                    </div>
                ` : ''}
            </div>
        `;
    }

    const globalVisited = new Set();
    const treeHTML = rootUsers.map(u => renderNodeSquare(u, globalVisited)).join('');

    return `
        <div class="card col-span-12">
            <div class="card-title" style="display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid var(--color-border); padding-bottom: 0.75rem; margin-bottom: 1rem;">
                <div style="display: flex; align-items: center; gap: 0.5rem;">
                    <i data-lucide="git-fork" style="width: 20px; height: 20px; color: var(--color-accent);"></i>
                    <span>${t('team_hierarchy')}</span>
                </div>
                <span class="status-badge info" style="font-size: 0.75rem;">${t('team_members')} ${allUsers.length}</span>
            </div>
            <div class="hierarchy-square-tree" style="max-height: 480px; overflow-x: auto; overflow-y: auto;">
                <div style="display: flex; gap: 2rem; justify-content: center; flex-wrap: wrap; width: 100%;">
                    ${treeHTML}
                </div>
            </div>
        </div>
    `;
}

async function translateSaudiNewsTitle(title) {
    if (currentLang !== 'en' || !/[\u0600-\u06FF]/.test(title || '')) return title;
    const cacheKey = `saudi_news_en_${title}`;
    try {
        const cached = localStorage.getItem(cacheKey);
        if (cached) return cached;
        const endpoint = `https://translate.googleapis.com/translate_a/single?client=gtx&sl=ar&tl=en&dt=t&q=${encodeURIComponent(title)}`;
        const response = await fetch(endpoint);
        if (!response.ok) throw new Error(`Translation failed (${response.status})`);
        const payload = await response.json();
        const translated = (payload?.[0] || []).map(part => part?.[0] || '').join('').trim();
        if (translated) {
            localStorage.setItem(cacheKey, translated);
            return translated;
        }
    } catch (error) {
        console.warn('Saudi news title translation unavailable; retaining the approved Arabic headline.', error);
    }
    return title;
}

window.openHierarchyEmployeeInfo = function (userId) {
    if (!['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN', 'MANAGER', 'SUPERVISOR'].includes(String(currentUserRole || '').toUpperCase())) return;
    const employee = window.hierarchyProfilesById?.[userId];
    if (!employee) return showToast(window.t('msg_toast_3') || 'Employee information is unavailable.', 'danger');
    document.getElementById('hierarchyEmployeeInfoModal')?.remove();
    const avatar = employee.avatar_url || localStorage.getItem('user_avatar_' + employee.id) || '';
    const modal = document.createElement('div');
    modal.id = 'hierarchyEmployeeInfoModal';
    modal.className = 'modal active hierarchy-employee-modal';
    modal.setAttribute('role', 'dialog');
    modal.setAttribute('aria-modal', 'true');
    modal.setAttribute('aria-labelledby', 'hierarchyEmployeeInfoTitle');
    modal.innerHTML = `<div class="modal-content hierarchy-employee-card">
        <button type="button" class="close-modal" aria-label="Close employee information" onclick="closeHierarchyEmployeeInfo()">&times;</button>
        <div class="hierarchy-employee-card-header">
            ${avatar ? `<img src="${escapeHTML(avatar)}" alt="${escapeHTML(window.formatEmployeeName(employee) || 'Employee')}" onerror="this.hidden=true;this.nextElementSibling.hidden=false;"><span class="hierarchy-employee-card-avatar hierarchy-avatar-placeholder" hidden><i data-lucide="user"></i></span>` : `<span class="hierarchy-employee-card-avatar hierarchy-avatar-placeholder"><i data-lucide="user"></i></span>`}
            <div><h2 id="hierarchyEmployeeInfoTitle">${escapeHTML(window.formatEmployeeName(employee) || 'Employee')}</h2><p>${escapeHTML(employee.job_title || 'No job title')}</p></div>
        </div>
        <dl class="hierarchy-employee-details">
            <div><dt>Full Name</dt><dd>${escapeHTML(window.formatEmployeeName(employee) || 'Not provided')}</dd></div>
            <div><dt>Nationality</dt><dd>${escapeHTML(employee.nationality || 'Not provided')}</dd></div>
            <div><dt>ID/Iqama number</dt><dd>${escapeHTML(employee.iqama_number || 'Not provided')}</dd></div>
            <div><dt>Phone Number</dt><dd>${escapeHTML(employee.phone_number || 'Not provided')}</dd></div>
            <div><dt>Latest Login</dt><dd>${employee.last_login ? escapeHTML(new Date(employee.last_login).toLocaleString()) : 'No login recorded'}</dd></div>
        </dl>
    </div>`;
    modal.addEventListener('click', event => { if (event.target === modal) closeHierarchyEmployeeInfo(); });
    document.body.appendChild(modal);
    translateArabicInterface(modal);
    if (window.lucide) window.lucide.createIcons();
};

window.closeHierarchyEmployeeInfo = function () {
    document.getElementById('hierarchyEmployeeInfoModal')?.remove();
};

async function renderDashboard() {
    // Always use one approved Saudi-Arabic feed. UI language may translate its
    // headlines, but must never change the underlying topics, sources or URLs.
    const newsQuery = '"السعودية" (أعمال OR "نظام العمل")';
    const newsHl = 'ar';
    const newsGl = 'SA';
    const newsCeid = 'SA:ar';
    const rssUrl = `https://news.google.com/rss/search?q=${encodeURIComponent(newsQuery)}&hl=${newsHl}&gl=${newsGl}&ceid=${newsCeid}`;
    const newsApiUrl = `https://api.rss2json.com/v1/api.json?rss_url=${encodeURIComponent(rssUrl)}`;

    // Run independent fetches in parallel
    const [todayAttendance, announcements, newsRes, profile, dashboardLeaves, dashboardGenericRequests] = await Promise.all([
        db.fetchTodayAttendance(currentUser?.id),
        db.fetchAnnouncements(),
        fetch(newsApiUrl).catch(() => null),
        db.getUserProfile(currentUser?.id),
        db.fetchLeaveRequests(currentUser?.id),
        db.fetchGenericRequests()
    ]);

    const isClockedIn = todayAttendance != null && !todayAttendance.clock_out_time;
    window.currentTodayAttendance = todayAttendance || null;
    const announcementsList = announcements || [];
    const dashboardName = getProfileDisplayName(profile);
    const currentHour = new Date().getHours();
    const greetingKey = currentHour < 12 ? 'welcome_morning' : currentHour < 18 ? 'welcome_afternoon' : 'welcome_evening';
    const welcomeMessage = t(greetingKey).replace('{name}', escapeHTML(dashboardName));
    const currentYear = new Date().getFullYear();
    const configuredAnnualAllowance = Number(profile?.annual_leave_allowance);
    const annualAllowance = Number.isFinite(configuredAnnualAllowance) && configuredAnnualAllowance > 0 ? configuredAnnualAllowance : 30;
    const annualLeaveDays = request => {
        if (!request.start_date || !request.end_date) return 0;
        const start = new Date(`${request.start_date}T00:00:00`);
        const end = new Date(`${request.end_date}T00:00:00`);
        return Math.max(0, Math.floor((end - start) / 86400000) + 1);
    };
    const isAnnualLeaveType = value => ['annual leave', 'annual/vacation', 'annual vacation'].includes(String(value || '').trim().toLowerCase());
    const currentAnnualLeaves = (dashboardLeaves || []).filter(request => {
        const requestDate = request.start_date || request.created_at;
        return isAnnualLeaveType(request.leave_type) && requestDate && new Date(requestDate).getFullYear() === currentYear;
    }).map(request => ({
        status: String(request.status || 'PENDING').toUpperCase(),
        days: annualLeaveDays(request)
    }));
    const currentGenericAnnualLeaves = (dashboardGenericRequests || []).filter(request =>
        request.employee_id === currentUser?.id &&
        request.request_type === 'Leave Request' &&
        isAnnualLeaveType(request.leave_type) &&
        request.created_at && new Date(request.created_at).getFullYear() === currentYear
    ).map(request => ({
        status: String(request.status || 'PENDING').toUpperCase(),
        days: Math.max(0, Number(request.number_of_days) || 0)
    }));
    const annualRequests = [...currentAnnualLeaves, ...currentGenericAnnualLeaves];
    const annualRequested = annualRequests.filter(request => request.status.startsWith('PENDING')).reduce((sum, request) => sum + request.days, 0);
    const annualUtilized = annualRequests.filter(request => request.status.startsWith('APPROVED')).reduce((sum, request) => sum + request.days, 0);
    const now = new Date();
    const yearStart = new Date(currentYear, 0, 1);
    const nextYearStart = new Date(currentYear + 1, 0, 1);
    const daysInYear = Math.round((nextYearStart - yearStart) / 86400000);
    const elapsedDays = Math.min(daysInYear, Math.max(1, Math.floor((now - yearStart) / 86400000) + 1));
    const accruedAnnualLeave = annualAllowance * (elapsedDays / daysInYear);
    const annualAvailable = Math.max(0, accruedAnnualLeave - annualUtilized - annualRequested);
    const annualAvailableByYearEnd = Math.max(0, annualAllowance - annualUtilized - annualRequested);
    const annualBalanceAsOf = now.toLocaleDateString(undefined, { day: '2-digit', month: 'short', year: 'numeric' });
    const canUsePersonalLeaveWidgets = ['EMPLOYEE', 'MANAGER', 'SUPERVISOR'].includes(String(currentUserRole || '').toUpperCase());

    let announcementsHTML = announcementsList.map(a => `
        <div class="announcement-item">
            <div class="announcement-icon" style="background: rgba(16, 185, 129, 0.1); color: var(--color-success);">
                <i data-lucide="megaphone"></i>
            </div>
            <div class="announcement-content">
                <h4>${escapeHTML(a.title)}</h4>
                <p>${escapeHTML(a.content)}</p>
                <small style="color:var(--color-text-secondary);">${new Date(a.created_at).toLocaleDateString()}</small>
            </div>
        </div>
    `).join('');
    if (announcementsList.length === 0) {
        announcementsHTML = `<p style="color: var(--color-text-secondary); padding: 1rem 0;">${t('dash_no_announcements')}</p>`;
    }

    // News Hub
    let newsHTML = '<p>Failed to load news.</p>';
    try {
        if (newsRes && newsRes.ok) {
            const newsData = await newsRes.json();
            if (newsData.status === 'ok') {
                const approvedSaudiItems = newsData.items.slice(0, 5);
                const localizedTitles = await Promise.all(approvedSaudiItems.map(item => translateSaudiNewsTitle(item.title)));
                newsHTML = approvedSaudiItems.map((item, index) => `
                    <div style="margin-bottom: 1rem; border-bottom: 1px solid var(--color-border); padding-bottom: 0.5rem;">
                        <a href="${escapeHTML(item.link)}" target="_blank" rel="noopener noreferrer" style="color: var(--color-primary); font-weight: 600; text-decoration: none;">${escapeHTML(localizedTitles[index])}</a>
                        <div style="font-size: 0.8rem; color: var(--color-text-secondary); margin-top: 0.25rem;">${new Date(item.pubDate).toLocaleDateString()}</div>
                    </div>
                `).join('');
            }
        }
    } catch (e) { }

    // Expiration Alerts
    let expirationAlerts = '';

    // Fetch docs and contracts in parallel
    try {
        const fetchPromises = [
            window.supabaseClient.from('employee_documents').select('*').eq('employee_id', currentUser.id)
        ];

        if (currentUserRole === 'ADMIN') {
            fetchPromises.push(window.supabaseClient.from('contracts').select('*'));
        }

        const results = await Promise.all(fetchPromises);
        const docs = results[0].data || [];

        const expiringDocs = docs.filter(d => d.expiration_date && (new Date(d.expiration_date) - new Date()) / (1000 * 60 * 60 * 24) < 30);
        if (expiringDocs.length > 0) {
            expirationAlerts += `
                <div style="background: rgba(239, 68, 68, 0.1); border-left: 4px solid var(--color-danger); padding: 1rem; margin-bottom: 1rem; border-radius: 4px;">
                    <strong style="color: var(--color-danger);">${t('docs_expiring')}:</strong> ${expiringDocs.length}
                </div>
            `;
        }

        if (currentUserRole === 'ADMIN' && results[1]) {
            const contracts = results[1].data || [];
            const expiringContracts = contracts.filter(c => c.end_date && (new Date(c.end_date) - new Date()) / (1000 * 60 * 60 * 24) < 30);
            if (expiringContracts.length > 0) {
                expirationAlerts += `
                    <div style="background: rgba(245, 158, 11, 0.1); border-left: 4px solid var(--color-warning); padding: 1rem; margin-bottom: 1rem; border-radius: 4px;">
                        <strong style="color: var(--color-warning);">${t('contract_expiring')}:</strong> ${expiringContracts.length}
                    </div>
                `;
            }
        }
    } catch (e) { }

    let adminWidgets = '';
    if (currentUserRole === 'ADMIN') {
        const allProfiles = await db.fetchAllProfiles();
        const lastLoginsHTML = renderRecentLoginsHTML(allProfiles);

        adminWidgets += `
            <div class="card col-span-12 md:col-span-6">
                <div class="card-title">${t('last_login')}</div>
                <div id="recentLoginsList" aria-live="polite">${lastLoginsHTML}</div>
            </div>
        `;
    }

    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${welcomeMessage}</h1>
                <p class="page-subtitle">${t('welcome_sub')}</p>
            </div>
            ${isClockedIn
            ? `<button id="attendanceClockButton" class="btn-primary" style="background: var(--color-danger);" onclick="handleClockOutPrompt('${todayAttendance.id}')">${t('attendance_clock_out')}</button>`
            : `<button id="attendanceClockButton" class="btn-primary" onclick="handleClockIn()">${t('attendance_clock_in')}</button>`
        }
        </div>

        <div class="dashboard-grid">
            ${expirationAlerts ? `<div class="col-span-12">${expirationAlerts}</div>` : ''}
            ${canUsePersonalLeaveWidgets ? `
            <div class="card col-span-12 annual-leave-widget">
                <div class="annual-leave-widget-title"><i data-lucide="plane-takeoff"></i><span>${t('dashboard_annual_leave')}</span></div>
                <div class="annual-leave-widget-balance"><i data-lucide="luggage"></i><strong>${annualAvailable.toFixed(2)}</strong></div>
                <div class="annual-leave-widget-date">${t('dashboard_days_available_as_of')} ${annualBalanceAsOf}</div>
                <div class="annual-leave-widget-breakdown">
                    <span>${annualRequested.toFixed(2)} ${t('dashboard_days_requested')}</span>
                    <span>${annualUtilized.toFixed(2)} ${t('dashboard_days_utilized')}</span>
                    <span>${annualAvailableByYearEnd.toFixed(2)} ${t('dashboard_days_available_year_end')}</span>
                </div>
            </div>` : ''}
            ${canUsePersonalLeaveWidgets ? `
            <div class="card col-span-12 short-leave-card">
                <div class="short-leave-title"><i data-lucide="person-standing"></i><span>${t('dashboard_short_leave')}</span></div>
                <div class="short-leave-reasons">
                    <label><input type="radio" name="dashboardShortLeaveReason" value="I am running late to the office."> ${t('dashboard_short_late')}</label>
                    <label><input type="radio" name="dashboardShortLeaveReason" value="I will be out for a meeting."> ${t('dashboard_short_meeting')}</label>
                    <label><input type="radio" name="dashboardShortLeaveReason" value="I need to attend an urgent family matter."> ${t('dashboard_short_family')}</label>
                </div>
                <div class="short-leave-durations">
                    <button type="button" class="short-leave-duration-button" onclick="submitDashboardShortLeave(15)">${t('dashboard_15_minutes')}</button>
                    <button type="button" class="short-leave-duration-button" onclick="submitDashboardShortLeave(60)">${t('dashboard_1_hour')}</button>
                    <button type="button" class="short-leave-duration-button" onclick="submitDashboardShortLeave(120)">${t('dashboard_2_hours')}</button>
                    <button type="button" class="short-leave-duration-button" onclick="submitDashboardShortLeave(180)">${t('dashboard_3_hours')}</button>
                </div>
            </div>` : ''}
            
            <div class="card col-span-12 md:col-span-8">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 1rem;">
                    <div class="card-title" style="margin:0;">${t('announcements')}</div>
                    ${currentUserRole === 'ADMIN' ? `<button class="btn-primary btn-sm" onclick="showAnnouncementModal()">${t('post_announcement')}</button>` : ''}
                </div>
                <div class="announcement-list" style="max-height: 300px; overflow-y:auto;">
                    ${announcementsHTML}
                </div>
            </div>

            <div class="card col-span-12 md:col-span-4">
                <div class="card-title">${t('news_hub')}</div>
                <div style="max-height: 300px; overflow-y:auto;">
                    ${newsHTML}
                </div>
            </div>
            ${await renderTeamHierarchyWidget()}
            ${adminWidgets}
        </div>

        <!-- Announcement Modal -->
        <div class="modal" id="announcementModal">
            <div class="modal-content" style="max-width: 500px;">
                <div class="modal-header">
                    <h3>${t('post_announcement')}</h3>
                    <button class="close-modal" onclick="closeAnnouncementModal()">&times;</button>
                </div>
                <form onsubmit="handlePostAnnouncement(event)">
                    <div class="form-group">
                        <label class="form-label">${t('ui_title')}</label>
                        <input type="text" id="announceTitle" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('ui_content')}</label>
                        <textarea id="announceContent" class="form-control" rows="4" required></textarea>
                    </div>
                    <div style="display: flex; gap: 1rem; margin-top: 1.5rem;">
                        <button type="submit" class="btn-primary" style="flex: 1;">${t('ui_post')}</button>
                    </div>
                </form>
            </div>
        </div>

        <!-- Clock Out Modal -->
        <div class="modal" id="clockOutModal">
            <div class="modal-content" style="max-width: 400px; text-align:center;">
                <div class="modal-header">
                    <h3>${t('attendance_clock_out')}</h3>
                    <button class="close-modal" onclick="closeClockOutModal()">&times;</button>
                </div>
                <p style="margin-bottom: 1.5rem; color:var(--color-text-secondary);">Please select your logout location:</p>
                <div style="display: flex; flex-direction:column; gap: 1rem;">
                    <button class="btn-primary" onclick="executeClockOut('OFFICE')">${t('attendance_location_office')}</button>
                    <button id="orderLocationClockOutButton" class="btn-primary" style="background:var(--color-warning);" onclick="executeClockOut('ORDER')">${t('attendance_location_order')}</button>
                </div>
            </div>
        </div>

        <div class="modal" id="orderClockOutCameraModal" role="dialog" aria-modal="true" aria-labelledby="orderClockOutCameraTitle">
            <div class="modal-content order-clockout-camera-modal">
                <div class="modal-header">
                    <h3 id="orderClockOutCameraTitle">Order location photo</h3>
                    <button type="button" class="close-modal" onclick="cancelOrderClockOutPhoto()" aria-label="Cancel photo capture">&times;</button>
                </div>
                <p class="order-clockout-camera-help">Take a current photo at the order location to complete clock out.</p>
                <div class="order-clockout-camera-stage">
                    <video id="orderClockOutCameraVideo" autoplay playsinline muted></video>
                    <img id="orderClockOutCameraPreview" alt="Captured order location photo" hidden>
                    <canvas id="orderClockOutCameraCanvas" hidden></canvas>
                </div>
                <p id="orderClockOutCameraStatus" class="text-muted" aria-live="polite">Requesting camera accessâ€¦</p>
                <input id="orderClockOutCameraInput" type="file" accept="image/*" capture="environment" hidden onchange="useOrderClockOutPhotoFile(this.files?.[0])">
                <div class="order-clockout-camera-actions">
                    <button id="orderClockOutCaptureButton" type="button" class="btn-primary" onclick="captureOrderClockOutPhoto()">Take photo</button>
                    <button id="orderClockOutDeviceCameraButton" type="button" class="btn btn-secondary" onclick="document.getElementById('orderClockOutCameraInput').click()">Use device camera</button>
                    <button id="orderClockOutRetakeButton" type="button" class="btn btn-secondary" onclick="retakeOrderClockOutPhoto()" hidden>Retake</button>
                    <button id="orderClockOutConfirmPhotoButton" type="button" class="btn-primary" onclick="confirmOrderClockOutPhoto()" hidden>Use photo</button>
                </div>
            </div>
        </div>
    `;
}

window.showAnnouncementModal = () => document.getElementById('announcementModal').style.display = 'block';
window.closeAnnouncementModal = () => document.getElementById('announcementModal').style.display = 'none';
window.handlePostAnnouncement = async (e) => {
    e.preventDefault();
    const title = document.getElementById('announceTitle').value;
    const content = document.getElementById('announceContent').value;
    const result = await db.postAnnouncement(currentUser.id, title, content);
    if (!result.success) {
        showToast(result.error?.message || 'Failed to publish announcement.', 'danger');
        return;
    }
    showToast(window.t('msg_toast_4') || 'Announcement published successfully.', 'success');
    closeAnnouncementModal();
    renderView('dashboard');
};

let currentAttendanceId = null;
let orderClockOutMediaStream = null;
let orderClockOutPhotoBlob = null;
let orderClockOutPhotoResolve = null;
let orderClockOutPhotoReject = null;
let orderClockOutPreviewUrl = null;

function stopOrderClockOutCamera() {
    orderClockOutMediaStream?.getTracks().forEach(track => track.stop());
    orderClockOutMediaStream = null;
    const video = document.getElementById('orderClockOutCameraVideo');
    if (video) video.srcObject = null;
}

function resetOrderClockOutPhotoUI() {
    orderClockOutPhotoBlob = null;
    if (orderClockOutPreviewUrl) URL.revokeObjectURL(orderClockOutPreviewUrl);
    orderClockOutPreviewUrl = null;
    const video = document.getElementById('orderClockOutCameraVideo');
    const preview = document.getElementById('orderClockOutCameraPreview');
    const capture = document.getElementById('orderClockOutCaptureButton');
    const deviceCamera = document.getElementById('orderClockOutDeviceCameraButton');
    const retake = document.getElementById('orderClockOutRetakeButton');
    const confirm = document.getElementById('orderClockOutConfirmPhotoButton');
    if (video) video.hidden = false;
    if (preview) { preview.hidden = true; preview.removeAttribute('src'); }
    if (capture) capture.hidden = false;
    if (deviceCamera) deviceCamera.hidden = false;
    if (retake) retake.hidden = true;
    if (confirm) confirm.hidden = true;
}

async function startOrderClockOutCamera() {
    const status = document.getElementById('orderClockOutCameraStatus');
    const capture = document.getElementById('orderClockOutCaptureButton');
    if (!navigator.mediaDevices?.getUserMedia) {
        if (status) status.textContent = 'Live camera preview is unavailable. Tap â€œUse device cameraâ€ instead.';
        if (capture) capture.hidden = true;
        return;
    }
    try {
        if (status) status.textContent = 'Please allow camera access.';
        orderClockOutMediaStream = await navigator.mediaDevices.getUserMedia({
            video: { facingMode: { ideal: 'environment' } },
            audio: false
        });
        if (!document.getElementById('orderClockOutCameraModal')?.classList.contains('show')) {
            stopOrderClockOutCamera();
            return;
        }
        const video = document.getElementById('orderClockOutCameraVideo');
        if (video) {
            video.srcObject = orderClockOutMediaStream;
            await video.play();
        }
        if (status) status.textContent = 'Position the order location in the frame, then take the photo.';
    } catch (error) {
        console.warn('Camera access failed:', error);
        if (status) status.textContent = 'Camera permission was not granted. Enable it in browser settings or tap â€œUse device cameraâ€.';
        if (capture) capture.hidden = true;
    }
}

function requestOrderClockOutPhoto() {
    return new Promise((resolve, reject) => {
        orderClockOutPhotoResolve = resolve;
        orderClockOutPhotoReject = reject;
        resetOrderClockOutPhotoUI();
        document.getElementById('orderClockOutCameraModal')?.classList.add('show');
        startOrderClockOutCamera();
    });
}

window.captureOrderClockOutPhoto = function () {
    const video = document.getElementById('orderClockOutCameraVideo');
    const canvas = document.getElementById('orderClockOutCameraCanvas');
    if (!video || !canvas || !video.videoWidth) {
        showToast(window.t('msg_toast_5') || 'The camera is not ready yet.', 'warning');
        return;
    }
    const maxWidth = 1280;
    const scale = Math.min(1, maxWidth / video.videoWidth);
    canvas.width = Math.round(video.videoWidth * scale);
    canvas.height = Math.round(video.videoHeight * scale);
    canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
    canvas.toBlob(blob => {
        if (!blob) return showToast(window.t('msg_toast_6') || 'Unable to capture the photo. Please try again.', 'danger');
        showOrderClockOutPhotoPreview(blob);
    }, 'image/jpeg', 0.82);
};

function showOrderClockOutPhotoPreview(blob) {
    orderClockOutPhotoBlob = blob;
    stopOrderClockOutCamera();
    if (orderClockOutPreviewUrl) URL.revokeObjectURL(orderClockOutPreviewUrl);
    orderClockOutPreviewUrl = URL.createObjectURL(blob);
    const video = document.getElementById('orderClockOutCameraVideo');
    const preview = document.getElementById('orderClockOutCameraPreview');
    if (video) video.hidden = true;
    if (preview) { preview.src = orderClockOutPreviewUrl; preview.hidden = false; }
    document.getElementById('orderClockOutCaptureButton').hidden = true;
    document.getElementById('orderClockOutDeviceCameraButton').hidden = true;
    document.getElementById('orderClockOutRetakeButton').hidden = false;
    document.getElementById('orderClockOutConfirmPhotoButton').hidden = false;
    document.getElementById('orderClockOutCameraStatus').textContent = 'Review the photo before continuing.';
}

window.useOrderClockOutPhotoFile = function (file) {
    if (!file) return;
    if (!file.type.startsWith('image/')) return showToast(window.t('msg_toast_7') || 'Please capture an image.', 'danger');
    showOrderClockOutPhotoPreview(file);
};

window.retakeOrderClockOutPhoto = function () {
    resetOrderClockOutPhotoUI();
    const deviceCamera = document.getElementById('orderClockOutDeviceCameraButton');
    if (deviceCamera) deviceCamera.hidden = false;
    const input = document.getElementById('orderClockOutCameraInput');
    if (input) input.value = '';
    startOrderClockOutCamera();
};

window.confirmOrderClockOutPhoto = function () {
    if (!orderClockOutPhotoBlob) return showToast(window.t('msg_toast_8') || 'Take a photo before continuing.', 'warning');
    const blob = orderClockOutPhotoBlob;
    stopOrderClockOutCamera();
    document.getElementById('orderClockOutCameraModal')?.classList.remove('show');
    const resolve = orderClockOutPhotoResolve;
    orderClockOutPhotoResolve = null;
    orderClockOutPhotoReject = null;
    resolve?.(blob);
};

window.cancelOrderClockOutPhoto = function () {
    stopOrderClockOutCamera();
    document.getElementById('orderClockOutCameraModal')?.classList.remove('show');
    if (orderClockOutPreviewUrl) URL.revokeObjectURL(orderClockOutPreviewUrl);
    orderClockOutPreviewUrl = null;
    orderClockOutPhotoBlob = null;
    const reject = orderClockOutPhotoReject;
    orderClockOutPhotoResolve = null;
    orderClockOutPhotoReject = null;
    reject?.(new Error('Photo capture cancelled'));
};

window.handleClockIn = async () => {
    const fallbackClockIn = async (loc) => {
        const button = document.getElementById('attendanceClockButton');
        if (button?.disabled) return;
        if (button) {
            button.disabled = true;
            button.dataset.originalText = button.textContent;
            button.textContent = 'Clocking in...';
        }
        try {
            const result = await db.clockIn(currentUser.id, loc);
            if (!result.success || !result.data) throw result.error || new Error('Clock in was not saved.');
            showToast(t('toast_clocked_in_successfully'), "success");
            currentAttendanceId = result.data.id;
            window.currentTodayAttendance = result.data;
            if (button) {
                button.disabled = false;
                button.textContent = t('attendance_clock_out');
                button.style.background = 'var(--color-danger)';
                button.setAttribute('onclick', `handleClockOutPrompt('${result.data.id}')`);
                button.setAttribute('aria-label', t('attendance_clock_out'));
            }
        } catch (err) {
            console.error(err);
            showToast(t('toast_error_clocking_in'), "danger");
            if (button) {
                button.disabled = false;
                button.textContent = button.dataset.originalText || t('attendance_clock_in');
            }
        }
    };

    if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition((position) => {
            const loc = position.coords.latitude + ',' + position.coords.longitude;
            fallbackClockIn(loc);
        }, (error) => {
            console.warn("Geolocation failed or denied, using fallback location.");
            fallbackClockIn("Location Unavailable");
        }, { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 });
    } else {
        fallbackClockIn("Location Unavailable");
    }
};

window.handleClockOutPrompt = (attendanceId) => {
    currentAttendanceId = attendanceId;
    document.getElementById('clockOutModal').classList.add('show');
};
window.closeClockOutModal = () => document.getElementById('clockOutModal')?.classList.remove('show');

window.executeClockOut = async (type) => {
    const attendance = window.currentTodayAttendance;
    const attendanceId = currentAttendanceId || attendance?.id;
    if (!attendanceId || !attendance?.clock_in_time) {
        showToast(t('toast_no_active_clock_in_found_for_today'), 'danger');
        closeClockOutModal();
        return;
    }

    let locationDetails = null;
    let orderPhotoPath = null;
    let locationLabel = 'Location Unavailable';
    const locationButton = document.getElementById('orderLocationClockOutButton');
    if (locationButton) {
        locationButton.disabled = true;
        locationButton.dataset.originalText = locationButton.textContent;
        locationButton.textContent = 'Waiting for location permission...';
    }
    try {
        if (!navigator.geolocation) throw Object.assign(new Error('Location sharing is not supported by this device.'), { code: 'UNSUPPORTED' });
        const position = await new Promise((resolve, reject) => navigator.geolocation.getCurrentPosition(resolve, reject, {
            enableHighAccuracy: true,
            timeout: 15000,
            maximumAge: 0
        }));
        locationDetails = {
            latitude: Number(position.coords.latitude.toFixed(7)),
            longitude: Number(position.coords.longitude.toFixed(7)),
            accuracy: Number(position.coords.accuracy.toFixed(2)),
            capturedAt: new Date(position.timestamp || Date.now()).toISOString()
        };
        locationLabel = `${locationDetails.latitude},${locationDetails.longitude}`;
    } catch (error) {
        if (type === 'ORDER') {
            if (locationButton) {
                locationButton.disabled = false;
                locationButton.textContent = locationButton.dataset.originalText || t('attendance_location_order');
            }
            showToast(error?.code === 1 ? 'Location permission is required to clock out from an order location.' : error?.message || 'Unable to get your current location.', 'danger');
            return;
        }
        console.warn('Clock-out location unavailable; saving the punch without coordinates.', error);
    }
    if (type === 'ORDER') {
        try {
            if (locationButton) locationButton.textContent = 'Location received — opening camera...';
            const photoBlob = await requestOrderClockOutPhoto();
            if (locationButton) locationButton.textContent = 'Uploading photo…';
            const uploadResult = await db.uploadAttendanceClockOutPhoto(attendanceId, currentUser.id, photoBlob);
            if (!uploadResult.success || !uploadResult.path) throw uploadResult.error || new Error('The order location photo could not be uploaded.');
            orderPhotoPath = uploadResult.path;
            locationDetails.photoPath = orderPhotoPath;
            if (locationButton) locationButton.textContent = 'Photo received — clocking out…';
        } catch (error) {
            if (locationButton) {
                locationButton.disabled = false;
                locationButton.textContent = locationButton.dataset.originalText || t('attendance_location_order');
            }
            const message = error?.message === 'Photo capture cancelled'
                ? 'A current photo is required to clock out from an order location.'
                : error?.code === 1
                    ? 'Location permission is required to clock out from an order location.'
                    : error?.message || 'Unable to get your current location or photo. Please check permissions and try again.';
            showToast(message, 'danger');
            return;
        }
    }
    const overtime = Math.max(0, (Date.now() - new Date(attendance.clock_in_time).getTime()) / 3600000 - 8).toFixed(2);
    const button = document.getElementById('attendanceClockButton');

    // Optimistic UI: the selected action is reflected immediately while the
    // database request completes in the background.
    closeClockOutModal();
    if (button) {
        button.disabled = false;
        button.textContent = t('attendance_clock_in');
        button.style.background = '';
        button.setAttribute('onclick', 'handleClockIn()');
        button.setAttribute('aria-label', t('attendance_clock_in'));
    }
    currentAttendanceId = null;
    window.currentTodayAttendance = {
        ...attendance, clock_out_time: new Date().toISOString(), clock_out_location: locationLabel, clock_out_type: type, ...(locationDetails ? {
            order_location_latitude: locationDetails.latitude,
            order_location_longitude: locationDetails.longitude,
            order_location_accuracy: locationDetails.accuracy,
            order_location_shared_at: locationDetails.capturedAt,
            order_location_photo_path: orderPhotoPath
        } : {})
    };

    const result = await db.clockOut(attendanceId, locationLabel, type, overtime, locationDetails);
    if (result.success) {
        showToast(t('toast_clocked_out_successfully'), 'success');
        return;
    }

    if (orderPhotoPath) await db.deleteAttendanceClockOutPhoto(orderPhotoPath);

    // Restore the Clock Out state if the database rejects the update.
    window.currentTodayAttendance = attendance;
    currentAttendanceId = attendanceId;
    if (button) {
        button.textContent = t('attendance_clock_out');
        button.style.background = 'var(--color-danger)';
        button.setAttribute('onclick', `handleClockOutPrompt('${attendanceId}')`);
        button.setAttribute('aria-label', t('attendance_clock_out'));
    }
    showToast(result.error?.message || t('toast_error_clocking_out'), 'danger');
};

// Render Time & Attendance
async function renderTime() {
    const viewerProfile = currentUserProfile || await db.getUserProfile(currentUser?.id);
    const normalizedRole = String(currentUserRole || viewerProfile?.role || '').toUpperCase();
    const jobTitle = String(viewerProfile?.job_title || '').trim().toUpperCase();
    const canViewAllAttendance = ['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(normalizedRole) ||
        ['HR MANAGER', 'FINANCE MANAGER', 'ACCOUNTANT MANAGER'].includes(jobTitle);
    const [punches, employees] = await Promise.all([
        db.fetchTimePunches(canViewAllAttendance ? null : currentUser?.id),
        canViewAllAttendance ? db.fetchUsers() : Promise.resolve([viewerProfile || currentUser])
    ]);
    const employeeMap = Object.fromEntries((employees || []).filter(Boolean).map(employee => [employee.id, employee]));
    const dateKey = value => {
        const date = new Date(value);
        return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    };
    const todayKey = dateKey(new Date());
    const initialVisibleCount = canViewAllAttendance ? punches.filter(punch => dateKey(punch.punch_time) === todayKey).length : punches.length;
    const mapLink = location => {
        const match = String(location || '').trim().match(/^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/);
        if (!match) return '<span class="text-muted">—</span>';
        const query = `${match[1]},${match[2]}`;
        const href = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
        return `<a class="attendance-location-link" href="${href}" target="_blank" rel="noopener noreferrer" title="${escapeHTML(localizeRuntimeText('Open map'))}"><i data-lucide="map-pin"></i><span>${escapeHTML(localizeRuntimeText('Open map'))}</span></a>`;
    };

    let tableRows = punches.map(p => `
        <tr class="attendance-record-row" data-attendance-date="${dateKey(p.punch_time)}" data-employee-name="${escapeHTML(String(window.formatEmployeeName(employeeMap[p.employee_id]) || '').toLowerCase())}" data-employee-id="${escapeHTML(String(employeeMap[p.employee_id]?.iqama_number || p.employee_id || '').toLowerCase())}" ${canViewAllAttendance && dateKey(p.punch_time) !== todayKey ? 'hidden' : ''}>
            <td>${new Date(p.punch_time).toLocaleDateString()}</td>
            <td>${new Date(p.punch_time).toLocaleTimeString()}</td>
            ${canViewAllAttendance ? `<td><strong>${escapeHTML(window.formatEmployeeName(employeeMap[p.employee_id]) || 'Unknown employee')}</strong></td><td>${escapeHTML(employeeMap[p.employee_id]?.iqama_number || p.employee_id)}</td>` : ''}
            <td>${p.punch_type}</td>
            <td><span class="status-badge ${p.punch_type === 'IN' ? 'success' : 'info'}">${p.punch_type}</span></td>
            <td>${mapLink(p.location)}</td>
        </tr>
    `).join('');

    if (punches.length === 0) {
        tableRows = `<tr><td colspan="${canViewAllAttendance ? 7 : 5}" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">${t('time_no_punches')}</td></tr>`;
    }

    const empName = window.formatEmployeeName(viewerProfile) || window.formatEmployeeName(currentUser?.user_metadata) || 'Employee';
    const isSystemAdmin = ['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(normalizedRole);
    const pageTitle = isSystemAdmin ? t('nav_time') : `${t('nav_time')} - ${escapeHTML(empName)}`;
    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${pageTitle}</h1>
                <p class="page-subtitle">${t('timesheet_sub')}</p>
            </div>
        </div>
        <div class="card">
            <div class="card-title">${t('timesheet')}</div>
            ${canViewAllAttendance ? `<div class="attendance-filters" aria-label="Attendance filters">
                <div class="form-group"><label class="form-label" for="attendanceFilterDate">Date</label><input type="date" id="attendanceFilterDate" class="form-control" value="${todayKey}" onchange="applyAttendanceFilters()"></div>
                <div class="form-group"><label class="form-label" for="attendanceFilterName">Employee Name</label><input type="search" id="attendanceFilterName" class="form-control" placeholder="Search employee name" oninput="applyAttendanceFilters()"></div>
                <div class="form-group"><label class="form-label" for="attendanceFilterId">ID Number</label><input type="search" id="attendanceFilterId" class="form-control" placeholder="Search Iqama / ID" oninput="applyAttendanceFilters()"></div>
                <button type="button" class="btn btn-secondary attendance-filter-clear" onclick="clearAttendanceFilters()"><i data-lucide="rotate-ccw"></i> Clear</button>
            </div>` : ''}
            <div class="table-responsive">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>${t('date')}</th>
                            <th>${t('time_time')}</th>
                            ${canViewAllAttendance ? '<th>Employee Name</th><th>ID Number</th>' : ''}
                            <th>${t('time_punch_type')}</th>
                            <th>${t('status')}</th>
                            <th>Location</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${tableRows}
                        ${punches.length ? `<tr id="attendanceNoFilterResults" ${initialVisibleCount ? 'hidden' : ''}><td colspan="${canViewAllAttendance ? 7 : 5}" style="text-align:center;padding:2rem;color:var(--color-text-secondary);">No attendance records match these filters.</td></tr>` : ''}
                    </tbody>
                </table>
            </div>
        </div>
    `;
}

window.openTaskDetailsModal = async function (id) {
    let task = window.taskCache?.[id];
    // The action can be clicked before the task cache finishes hydrating.
    // Resolve the task once more instead of silently doing nothing.
    if (!task) {
        const fetchedTasks = await db.fetchTasksWithProfiles();
        task = (fetchedTasks || []).find(item => String(item.id) === String(id));
        if (task) {
            window.taskCache = window.taskCache || {};
            window.taskCache[task.id] = task;
        }
    }
    if (!task) return;
    if (!canInteractWithTask(task)) {
        showToast(window.t('msg_toast_9') || 'You do not have access to this task.', 'warning');
        return;
    }

    // Keep the two task modals mutually exclusive when switching actions.
    document.getElementById('editTaskModal')?.classList.remove('active');

    if (currentView !== 'tasks' && currentView !== 'tasks_v2') {
        await renderView('tasks');
    }

    const taskPanel = document.getElementById('taskSidePanel');
    const taskPanelOverlay = document.getElementById('taskSidePanelOverlay');
    if (taskPanel) taskPanel.hidden = false;
    if (taskPanelOverlay) taskPanelOverlay.hidden = false;

    document.getElementById('detailsTaskId').value = task.id;
    document.getElementById('detailsTaskTitle').textContent = getLocalizedTaskTitle(task);
    document.getElementById('detailsTaskAssignee').textContent = window.formatEmployeeName(task.assignee) || taskDetailText('Unassigned', 'غير معيّن');
    document.getElementById('detailsTaskCreator').textContent = window.formatEmployeeName(task.creator) || taskDetailText('System', 'النظام');
    document.getElementById('detailsTaskStatus').textContent = taskDetailValue(task.status, 'status');
    document.getElementById('detailsTaskPriority').textContent = taskDetailValue(task.priority, 'priority');
    document.getElementById('detailsTaskVisibility').textContent = taskDetailValue(task.visibility || 'public', 'visibility');
    document.getElementById('detailsTaskStart').textContent = task.start_date || taskDetailText('Not set', 'غير محدد');
    document.getElementById('detailsTaskDue').textContent = task.due_date || taskDetailText('Not set', 'غير محدد');
    if(document.getElementById('detailsTaskEnd')) document.getElementById('detailsTaskEnd').textContent = task.end_date || taskDetailText('Not set', 'غير محدد');
    document.getElementById('detailsTaskEstimate').textContent = task.estimated_time || taskDetailText('Not set', 'غير محدد');
    prepareTeamworkTaskDetail(task);

    const list = document.getElementById('taskCommentsList');
    list.innerHTML = `<div style="text-align: center; color: var(--color-text-secondary);">${taskDetailText('Loading comments...', 'جارٍ تحميل التعليقات...')}</div>`;

    document.getElementById('taskSidePanel').classList.add('active');
    document.getElementById('taskSidePanelOverlay').classList.add('active');
    document.getElementById('taskSidePanel').classList.toggle('task-v2-detail', currentView === 'tasks' || currentView === 'tasks_v2');

    // Check permission to create tasks
    const privateList = (window.taskListsCache || []).find(list => list.id === task.task_list_id);
    const viewerDepartmentId = currentUserProfile?.department_id || (window.taskAllUsersCache || []).find(user => user.id === currentUser?.id)?.department_id;
    const canCreateTask = !!currentUser && (!task.task_list_id || privateList?.owner_id === currentUser.id || privateList?.department_id === viewerDepartmentId);
    const btnCreateSubTask = document.getElementById('btnCreateSubTask');
    if (btnCreateSubTask) {
        btnCreateSubTask.style.display = canCreateTask ? 'inline-block' : 'none';
    }
    const subTaskButtons = document.querySelectorAll('[onclick="openInlineSubtaskComposer()"]');
    subTaskButtons.forEach(btn => {
        btn.style.display = canCreateTask ? 'inline-block' : 'none';
    });


    // Load Subtasks
    const subTasksList = document.getElementById('taskSubTasksList');
    if (subTasksList) {
        subTasksList.innerHTML = `<div style="text-align: center; color: var(--color-text-secondary);">${taskDetailText('Loading subtasks...', 'جارٍ تحميل المهام الفرعية...')}</div>`;
        const allTasks = Object.values(window.taskCache || {});
        const subTasks = allTasks.filter(t => t.parent_task_id === task.id);

        if (subTasks.length === 0) {
            subTasksList.innerHTML = `<div style="color: var(--color-text-secondary); font-style: italic;">${taskDetailText('No subtasks yet.', 'لا توجد مهام فرعية بعد.')}</div>`;
        } else {
            subTasksList.innerHTML = subTasks.map(st => `
                <div style="background: var(--color-surface); padding: 0.75rem; border-radius: 6px; border: 1px solid var(--color-border); cursor: pointer;" onclick="openTaskDetailsModal('${st.id}')">
                    <div style="display: flex; justify-content: space-between; align-items: center;">
                        <strong>${escapeHTML(st.title)}</strong>
                        <span class="badge" style="font-size: 0.7rem;">${escapeHTML(taskDetailValue(st.status, 'status'))}</span>
                    </div>
                </div>
            `).join('');
        }
    }

    const comments = await db.fetchTaskComments(task.id);
    if (comments.length === 0) {
        list.innerHTML = `<div style="color: var(--color-text-secondary); font-style: italic;">${taskDetailText('No comments yet.', 'لا توجد تعليقات بعد.')}</div>`;
    } else {
        list.innerHTML = comments.map(c => `
            <div style="background: var(--color-bg-base); padding: 0.75rem; border-radius: 6px; border: 1px solid var(--color-border); margin-bottom: 0.5rem; box-shadow: var(--shadow-sm);">
                <div style="display: flex; justify-content: space-between; margin-bottom: 0.25rem;">
                    <strong>${escapeHTML(window.formatEmployeeName(c.user) || taskDetailText('Unknown user', 'مستخدم غير معروف'))}</strong>
                    <span style="font-size: 0.75rem; color: var(--color-text-secondary);">${new Date(c.created_at).toLocaleString()}</span>
                </div>
                <div>${escapeHTML(c.content)}</div>
            </div>
        `).join('');
    }
};

// Use one explicit action handler for Focus/Pipeline view buttons. Keeping the
// event cancellation here prevents the row click handler from competing with
// the eye button, while the catch makes failures visible instead of leaving a
// seemingly unresponsive control.
window.handleTaskViewClick = function (event, id) {
    event?.preventDefault?.();
    event?.stopPropagation?.();
    const taskId = id || event?.currentTarget?.dataset?.taskId;
    if (!taskId) return;
    Promise.resolve(window.openTaskDetailsModal(taskId)).catch(error => {
        console.error('Unable to open task details:', error);
        showToast(window.t('msg_toast_10') || 'Unable to open task details. Please try again.', 'danger');
    });
};

window.openTaskAssigneePicker = function (taskId) {
    const task = window.taskCache?.[taskId];
    if (!task || (!isTaskAdmin() && task.created_by !== currentUser?.id)) {
        showToast(window.t('msg_toast_11') || 'Only the task creator or an administrator can change assignees.', 'warning');
        return;
    }
    let modal = document.getElementById('taskAssigneePickerModal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'taskAssigneePickerModal';
        modal.className = 'modal';
        modal.style.zIndex = '2147483001';
        modal.innerHTML = `<div class="modal-content task-assignee-picker-content"><div class="modal-header"><h2>Assign task</h2><button type="button" class="close-modal" data-assignee-cancel aria-label="Close">&times;</button></div><p class="task-assignee-picker-help">Select one or more employees.</p><div id="taskAssigneePickerOptions" class="task-assignee-picker-options" role="group" aria-label="Task assignees"></div><div class="modal-actions"><button type="button" class="btn btn-secondary" data-assignee-cancel>Cancel</button><button type="button" class="btn btn-primary" id="taskAssigneePickerSave">Save assignment</button></div></div>`;
        document.body.appendChild(modal);
        modal.querySelectorAll('[data-assignee-cancel]').forEach(button => button.onclick = () => modal.classList.remove('show'));
        modal.querySelector('#taskAssigneePickerSave').onclick = async () => {
            const selected = Array.from(modal.querySelectorAll('#taskAssigneePickerOptions input[type="checkbox"]:checked:not(#taskAssigneeSelectAll)')).map(input => input.value);
            if (!selected.length) return showToast(window.t('msg_toast_12') || 'Select at least one employee.', 'warning');
            const save = await db.updateTask(modal.dataset.taskId, { assignee_id: selected[0], assignee_ids: selected });
            if (!save.success) return showToast(save.error?.message || 'Unable to update assignment.', 'danger');
            const selectedUsers = (window.taskAllUsersCache || []).filter(user => selected.includes(user.id));
            const current = window.taskCache?.[modal.dataset.taskId];
            if (current) {
                current.assignee_id = selected[0];
                current.assignee_ids = selected;
                current.assignee = selectedUsers[0] ? { full_name: selectedUsers[0].full_name } : null;
            }
            modal.classList.remove('show');
            await renderView('tasks');
            showToast(window.t('msg_toast_13') || 'Task assignment updated.', 'success');
        };
    }
    modal.dataset.taskId = taskId;
    const selectedIds = new Set(Array.isArray(task.assignee_ids) && task.assignee_ids.length ? task.assignee_ids : [task.assignee_id].filter(Boolean));
    const options = modal.querySelector('#taskAssigneePickerOptions');
    options.innerHTML = `<label class="picker-select-all task-assignee-picker-option" for="taskAssigneeSelectAll"><input id="taskAssigneeSelectAll" type="checkbox" onchange="window.toggleTaskAssigneePickerAll(this.checked)"><span>Select all employees</span></label>` + (window.taskAllUsersCache || []).map((user, index) => {
        const inputId = `taskAssigneeOption-${index}`;
        return `<label class="task-assignee-picker-option" for="${inputId}"><input id="${inputId}" type="checkbox" value="${escapeHTML(user.id)}" ${selectedIds.has(user.id) ? 'checked' : ''} onchange="window.updateTaskAssigneePickerSelectAll()"><span>${escapeHTML(window.formatEmployeeName(user) || user.id)}</span></label>`;
    }).join('') || '<p class="task-assignee-picker-empty">No employees available.</p>';
    window.updateTaskAssigneePickerSelectAll();
    translateArabicInterface(modal);
    modal.classList.add('show');
};
window.handleTaskAssigneeClick = function (event, taskId) {
    event?.preventDefault?.();
    event?.stopPropagation?.();
    window.openTaskAssigneePicker(taskId);
};

function prepareTeamworkTaskDetail(task) {
    window.activeTaskDetail = task;
    const panel = document.getElementById('taskSidePanel');
    if (!panel) return;
    panel.classList.add('teamwork-task-detail');
    const header = panel.querySelector('.side-panel-header');
    const taskList = (window.taskListsCache || []).find(list => list.id === task.task_list_id);
    const canManagePrivateTask = !task.task_list_id || taskList?.owner_id === currentUser?.id;
    if (header) {
        const canEdit = isTaskAdmin() || task.created_by === currentUser?.id;
        const canApproveCompletion = !task.task_list_id && task.status === 'Pending Approval' && window.taskDepartmentManagerByName?.[task.department] === currentUser?.id;
        let actions = header.querySelector('.task-detail-actions');
        if (!actions) {
            actions = document.createElement('div');
            actions.className = 'task-detail-actions';
            header.appendChild(actions);
        }
        actions.innerHTML = `${canApproveCompletion ? `<button type="button" class="btn btn-primary" onclick="approveTaskCompletion('${task.id}')"><i data-lucide="check-circle"></i> ${taskDetailText('Approve', 'اعتماد')}</button>` : ''}${canEdit ? `<button type="button" class="btn btn-primary task-detail-edit" onclick="openEditTaskModal(document.getElementById('detailsTaskId').value)"><i data-lucide="pencil"></i> ${taskDetailText('Edit', 'تعديل')}</button>` : ''}<button type="button" class="task-detail-close" aria-label="${taskDetailText('Close task', 'إغلاق المهمة')}" onclick="document.getElementById('taskSidePanel').classList.remove('active');document.getElementById('taskSidePanelOverlay').classList.remove('active')">&times;</button>`;
        header.querySelector('.close-modal')?.remove();
    }
    const grid = panel.querySelector('.task-details-grid');
    if (grid) {
        let content = panel.querySelector('.task-detail-reference-content');
        if (!content) {
            content = document.createElement('div');
            content.className = 'task-detail-reference-content';
            grid.insertAdjacentElement('afterend', content);
        }
        const links = [...(task.content_links || []), ...(task.submission_links || [])].filter(Boolean);
        const imageExtensions = /\.(?:png|jpe?g|gif|webp|bmp|svg)(?:[?#].*)?$/i;
        const fileNameFromUrl = link => decodeURIComponent(String(link).split('?')[0].split('/').pop() || 'Attachment');
        const attachmentHTML = links.length ? links.map(link => {
            const safeLink = escapeHTML(link);
            const label = escapeHTML(fileNameFromUrl(link));
            return imageExtensions.test(String(link))
                ? `<a class="task-detail-image-attachment" href="${safeLink}" target="_blank" rel="noopener" title="Open ${label}"><img src="${safeLink}" alt="${label}" loading="lazy"><span>${label}</span></a>`
                : `<a href="${safeLink}" target="_blank" rel="noopener"><i data-lucide="download"></i>${label}</a>`;
        }).join('') : `<div class="task-detail-file-drop"><i data-lucide="cloud-upload"></i><span>${taskDetailText('No files or links have been added', 'لم تتم إضافة ملفات أو روابط')}</span></div>`;
        const canUploadFiles = canInteractWithTask(task);
        content.innerHTML = `
            <section class="task-detail-description"><p>${task.description ? escapeHTML(task.description) : `<span>${taskDetailText('Add a description', 'أضف وصفاً')}</span>`}</p></section>
            <nav class="task-detail-tabs" aria-label="${taskDetailText('Task information', 'معلومات المهمة')}"><button type="button" class="active" data-task-info-tab="details" onclick="setTaskDetailInfoTab('details')">${taskDetailText('Details', 'التفاصيل')}</button><button type="button" data-task-info-tab="proofs" onclick="setTaskDetailInfoTab('proofs')">${taskDetailText('Proofs', 'الإثباتات')}</button></nav>
            <section id="taskDetailInfoPanel" class="task-detail-tab-panel"></section>
            <section class="task-detail-files">
                <div class="task-detail-files-heading"><h3>${taskDetailText('Files & links', 'الملفات والروابط')}</h3>${canUploadFiles ? `<button type="button" class="btn btn-secondary task-file-upload-button" onclick="document.getElementById('taskAttachmentInput').click()"><i data-lucide="paperclip"></i> ${taskDetailText('Upload files', 'رفع الملفات')}</button><input id="taskAttachmentInput" type="file" multiple style="display: none;" onchange="uploadTaskAttachment(this)">` : ''}</div>
                <div id="taskDetailFileList"><div class="task-detail-link-list">${attachmentHTML}</div></div>
            </section>`;
    }
    const commentsHeading = Array.from(panel.querySelectorAll('h3')).find(item => item.textContent.includes('Activity') || item.textContent.includes('Comments'));
    if (commentsHeading) {
        commentsHeading.className = 'task-comment-tabs';
        commentsHeading.innerHTML = `<button type="button" class="active" data-task-activity-tab="comments" onclick="setTaskActivityTab('comments')">${taskDetailText('Comments', 'التعليقات')}</button><button type="button" data-task-activity-tab="activity" onclick="setTaskActivityTab('activity')">${taskDetailText('Activity', 'النشاط')}</button><button type="button" data-task-activity-tab="info" onclick="setTaskActivityTab('info')">${taskDetailText('Info', 'المعلومات')}</button>`;
        let activityPanel = panel.querySelector('#taskActivityPanel');
        if (!activityPanel) {
            activityPanel = document.createElement('div');
            activityPanel.id = 'taskActivityPanel';
            activityPanel.className = 'task-activity-panel';
            commentsHeading.insertAdjacentElement('afterend', activityPanel);
        }
    }
    const legacySubtaskHeading = Array.from(panel.querySelectorAll('h3')).find(item => item.textContent.toLowerCase().includes('sub-task'))?.parentElement;
    if (legacySubtaskHeading) legacySubtaskHeading.style.display = 'none';
    const legacySubtaskList = document.getElementById('taskSubTasksList');
    if (legacySubtaskList) legacySubtaskList.style.display = 'none';
    const commentForm = document.getElementById('taskCommentInput')?.closest('form');
    if (commentForm) commentForm.style.display = canInteractWithTask(task) ? 'flex' : 'none';
    setTaskDetailInfoTab('details');
    setTaskActivityTab('comments');
    if (window.lucide) window.lucide.createIcons();
}

window.applyAttendanceFilters = function () {
    const date = document.getElementById('attendanceFilterDate')?.value || '';
    const name = document.getElementById('attendanceFilterName')?.value.trim().toLowerCase() || '';
    const id = document.getElementById('attendanceFilterId')?.value.trim().toLowerCase() || '';
    let visible = 0;
    document.querySelectorAll('.attendance-record-row').forEach(row => {
        const matches = (!date || row.dataset.attendanceDate === date) &&
            (!name || row.dataset.employeeName.includes(name)) &&
            (!id || row.dataset.employeeId.includes(id));
        row.hidden = !matches;
        if (matches) visible += 1;
    });
    const empty = document.getElementById('attendanceNoFilterResults');
    if (empty) empty.hidden = visible !== 0;
};

window.clearAttendanceFilters = function () {
    ['attendanceFilterDate', 'attendanceFilterName', 'attendanceFilterId'].forEach(id => {
        const field = document.getElementById(id);
        if (field) field.value = '';
    });
    window.applyAttendanceFilters();
};

window.uploadTaskAttachment = async function (input) {
    const files = Array.from(input?.files || []);
    const task = window.activeTaskDetail;
    if (files.length === 0 || !canInteractWithTask(task) || !currentUser?.id) {
        if (files.length && task && !canInteractWithTask(task)) showToast(window.t('msg_toast_9') || 'You do not have access to this task.', 'warning');
        return;
    }
    const button = document.querySelector('.task-file-upload-button');
    const original = button?.innerHTML;
    if (button) {
        button.disabled = true;
        button.innerHTML = '<span class="spinner"></span> Uploading...';
    }

    let successCount = 0;
    const newLinks = [];

    for (const file of files) {
        const upload = await db.uploadTaskAttachment(task.id, currentUser.id, file);
        if (!upload.success) {
            showToast(upload.error?.message || `Unable to upload ${file.name}.`, 'danger');
            continue;
        }
        newLinks.push(upload.url);
        successCount++;
    }

    if (newLinks.length > 0) {
        const links = [...new Set([...(task.submission_links || []), ...newLinks])];
        const update = await db.updateTask(task.id, { submission_links: links, upload_link: links[0] || null });
        if (!update.success) {
            showToast(update.error?.message || 'The files uploaded, but could not be linked to the task.', 'danger');
        } else {
            task.submission_links = links;
            task.upload_link = links[0] || null;
            showToast(`${successCount} file(s) uploaded successfully.`, 'success');
        }
    } else if (files.length > 0) {
        showToast(window.t('msg_toast_14') || 'No files were successfully uploaded.', 'danger');
    }

    if (button) { button.disabled = false; button.innerHTML = original; }
    input.value = '';
    prepareTeamworkTaskDetail(task);
};

function renderRecentLoginsHTML(profiles) {
    return (profiles || []).filter(profile => profile.last_login)
        .sort((a, b) => new Date(b.last_login) - new Date(a.last_login))
        .slice(0, 5)
        .map(profile => `
            <div style="display:flex; justify-content:space-between; gap:1rem; margin-bottom:0.5rem;">
                <span>${escapeHTML(window.formatEmployeeName(profile) || 'Employee')}</span>
                <time datetime="${escapeHTML(profile.last_login)}" style="color:var(--color-text-secondary); font-size:0.85rem; white-space:nowrap;">${new Date(profile.last_login).toLocaleString()}</time>
            </div>
        `).join('') || `<p>${t('ui_no_recent_logins') || 'No recent logins.'}</p>`;
}

async function refreshRecentLoginsWidget() {
    const container = document.getElementById('recentLoginsList');
    if (!container || currentView !== 'dashboard' || currentUserRole !== 'ADMIN') return;
    container.innerHTML = renderRecentLoginsHTML(await db.fetchAllProfiles());
}

function stopRecentLoginsRealtime() {
    if (recentLoginsPollInterval) clearInterval(recentLoginsPollInterval);
    recentLoginsPollInterval = null;
    if (recentLoginsChannel && window.supabaseClient?.removeChannel) {
        window.supabaseClient.removeChannel(recentLoginsChannel);
    }
    recentLoginsChannel = null;
}

function startRecentLoginsRealtime() {
    stopRecentLoginsRealtime();
    if (currentUserRole !== 'ADMIN' || !document.getElementById('recentLoginsList')) return;
    if (window.supabaseClient?.channel) {
        recentLoginsChannel = window.supabaseClient
            .channel('dashboard-recent-logins')
            .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'profiles' }, payload => {
                if (payload.new?.last_login && payload.new.last_login !== payload.old?.last_login) refreshRecentLoginsWidget();
            })
            .subscribe();
    }
    recentLoginsPollInterval = setInterval(refreshRecentLoginsWidget, 15000);
}

window.handleLeaveTypeChange = function (type) {
    const isShortLeave = type === 'Short Leave';
    document.getElementById('leaveStartGroup').style.display = isShortLeave ? 'none' : 'block';
    document.getElementById('leaveEndGroup').style.display = isShortLeave ? 'none' : 'block';
    document.getElementById('leaveReasonGroup').style.display = isShortLeave ? 'none' : 'block';
    document.getElementById('leaveShortFields').style.display = isShortLeave ? 'block' : 'none';
    document.getElementById('leaveStart').required = !isShortLeave;
    document.getElementById('leaveEnd').required = !isShortLeave;
    document.getElementById('leaveReason').required = !isShortLeave;
    document.getElementById('leaveShortReason').required = isShortLeave;
    document.getElementById('leaveShortDuration').required = isShortLeave;
};

window.submitDashboardShortLeave = async function (durationMinutes) {
    const selectedReason = document.querySelector('input[name="dashboardShortLeaveReason"]:checked');
    if (!selectedReason) {
        showToast(window.t('msg_toast_2') || 'Select a reason for the short leave.', 'danger');
        return;
    }
    const buttons = document.querySelectorAll('.short-leave-duration-button');
    buttons.forEach(button => button.disabled = true);
    const today = new Date().toISOString().slice(0, 10);
    const success = await db.submitLeaveRequest(currentUser.id, {
        leave_type: 'Short Leave', start_date: today, end_date: today,
        reason: selectedReason.value, short_leave_reason: selectedReason.value,
        short_leave_duration_minutes: durationMinutes
    });
    buttons.forEach(button => button.disabled = false);
    if (!success) return showToast(window.t('msg_toast_15') || 'Failed to submit short leave request.', 'danger');
    showToast(window.t('msg_toast_16') || 'Short leave request submitted successfully.', 'success');
    renderView('dashboard');
};



function companyJobTitleOptions(selected = '', departmentName = '') {
    const jobTitlesMap = db.getJobTitlesMap() || {};
    if (!departmentName) return '<option value="">Select Department first</option>';
    const matchedDepartment = Object.keys(jobTitlesMap).find(name => name.trim().toLowerCase() === departmentName.trim().toLowerCase());
    let titles = matchedDepartment ? jobTitlesMap[matchedDepartment] : [];
    // Administrative also owns the former IT titles after the department
    // merge. Keep these visible even when an older cached directory response
    // has not refreshed yet.
    if (/administrative|administration/i.test(String(departmentName))) {
        const itTitles = ['IT Manager', 'IT Support Specialist', 'System Administrator', 'Network Administrator', 'Technician'];
        titles = [...new Set([...titles, ...itTitles])];
    }
    titles = titles.filter(t => !t.includes('General Manager, Executive Director'));
    return '<option value="">Select Job Title</option>' + titles.map(title =>
        `<option value="${escapeHTML(title)}" ${title === selected ? 'selected' : ''}>${escapeHTML(title)}</option>`
    ).join('');
}

window.syncJobTitlesWithDepartment = function (departmentSelectId, jobTitleSelectId) {
    const departmentSelect = document.getElementById(departmentSelectId);
    const titleSelect = document.getElementById(jobTitleSelectId);
    if (!departmentSelect || !titleSelect) return;
    const previous = titleSelect.value;
    const departmentName = departmentSelect.options[departmentSelect.selectedIndex]?.text || '';
    const jobTitlesMap = db.getJobTitlesMap() || {};
    const matchedDepartment = Object.keys(jobTitlesMap).find(name => name.trim().toLowerCase() === departmentName.trim().toLowerCase());
    if (!departmentSelect.value || !matchedDepartment) {
        titleSelect.innerHTML = '<option value="">Select Department first</option>';
        titleSelect.value = '';
        titleSelect.disabled = true;
        return;
    }
    titleSelect.disabled = false;
    titleSelect.innerHTML = companyJobTitleOptions(previous, departmentName);
    if (![...titleSelect.options].some(option => option.value === previous)) titleSelect.value = '';
};

window.setTaskDetailInfoTab = function (tab) {
    const task = window.activeTaskDetail;
    const panel = document.getElementById('taskDetailInfoPanel');
    if (!task || !panel) return;
    document.querySelectorAll('[data-task-info-tab]').forEach(button => button.classList.toggle('active', button.dataset.taskInfoTab === tab));
    const allTasks = Object.values(window.taskCache || {});
    const parent = task.parent_task_id ? window.taskCache?.[task.parent_task_id] : null;
    const subtasks = allTasks.filter(item => item.parent_task_id === task.id);
    const contentLinks = task.content_links || (task.source_link ? [task.source_link] : []);
    const proofLinks = task.submission_links || (task.upload_link ? [task.upload_link] : []);
    const privateList = (window.taskListsCache || []).find(list => list.id === task.task_list_id);
    const canManageTask = !task.task_list_id || privateList?.owner_id === currentUser?.id;
    if (tab === 'custom-fields') {
        const fields = [
            [taskDetailText('Department', 'القسم'), task.department], [taskDetailText('Task type', 'نوع المهمة'), task.sub_type], [taskDetailText('Business', 'النشاط'), task.marketing_department],
            [taskDetailText('Content type', 'نوع المحتوى'), task.content_type], [taskDetailText('Delivery status', 'حالة التسليم'), task.delivery_status], [taskDetailText('Category', 'التصنيف'), task.category]
        ].filter(([, value]) => value);
        panel.innerHTML = fields.length ? `<div class="task-detail-data-grid">${fields.map(([label, value]) => `<div><span>${escapeHTML(label)}</span><strong>${escapeHTML(value)}</strong></div>`).join('')}</div>` : `<div class="task-tab-empty">${taskDetailText('No custom fields have been set.', 'لم يتم تعيين حقول مخصصة.')}</div>`;
    } else if (tab === 'dependencies') {
        panel.innerHTML = `<div class="task-detail-data-grid"><div><span>${taskDetailText('Parent task', 'المهمة الرئيسية')}</span><strong>${parent ? escapeHTML(getLocalizedTaskTitle(parent)) : taskDetailText('None', 'لا يوجد')}</strong></div><div><span>${taskDetailText('Subtasks', 'المهام الفرعية')}</span><strong>${subtasks.length}</strong></div><div><span>${taskDetailText('Blocking dependencies', 'التبعيات المانعة')}</span><strong>${taskDetailText('None', 'لا يوجد')}</strong></div></div>`;
    } else if (tab === 'proofs') {
        panel.innerHTML = proofLinks.length ? `<div class="task-detail-link-list">${proofLinks.map(link => `<a href="${escapeHTML(link)}" target="_blank" rel="noopener"><i data-lucide="external-link"></i>${escapeHTML(link)}</a>`).join('')}</div>` : `<div class="task-tab-empty">${taskDetailText('No submission proofs have been added.', 'لم تتم إضافة إثباتات تسليم.')}</div>`;
    } else {
        panel.innerHTML = `<div class="task-detail-data-grid"><div><span>${taskDetailText('Status', 'الحالة')}</span><strong>${escapeHTML(taskDetailValue(task.status, 'status'))}</strong></div><div><span>${taskDetailText('Priority', 'الأولوية')}</span><strong>${escapeHTML(taskDetailValue(task.priority, 'priority'))}</strong></div><div><span>${taskDetailText('Content links', 'روابط المحتوى')}</span><strong>${contentLinks.length}</strong></div><div><span>${taskDetailText('Due date', 'تاريخ الاستحقاق')}</span><strong>${escapeHTML(task.due_date || taskDetailText('Not set', 'غير محدد'))}</strong></div></div>
            <section class="task-detail-inline-subtasks"><div class="task-detail-subtask-heading"><strong>${taskDetailText('Subtasks', 'المهام الفرعية')} <span>${subtasks.length}</span></strong>${canManageTask ? `<button type="button" onclick="openInlineSubtaskComposer()"><i data-lucide="plus"></i> ${taskDetailText('Add a subtask', 'إضافة مهمة فرعية')}</button>` : `<span class="task-private-badge"><i data-lucide="eye"></i>${taskDetailText('View only', 'عرض فقط')}</span>`}</div><div id="taskDetailSubtaskHost">${subtasks.length ? subtasks.map(subtask => {
                const isDone = subtask.status === 'completed' || subtask.status === 'Approved';
                const iconColor = isDone ? '#059669' : 'var(--color-text-secondary)';
                const iconName = isDone ? 'check-circle-2' : 'circle';
                const titleStyle = isDone ? 'text-decoration:line-through;opacity:0.55;' : '';
                return `<button type="button" class="task-detail-subtask-row${isDone ? ' subtask-done' : ''}" data-task-id="${subtask.id}" onclick="openTaskDetailsModal('${subtask.id}')"><span class="subtask-check-btn" onclick="event.stopPropagation();window.toggleSubtaskComplete('${subtask.id}',this)" style="display:flex;align-items:center;flex-shrink:0;cursor:pointer;padding:0 4px 0 0;"><i data-lucide="${iconName}" style="width:18px;height:18px;color:${iconColor};transition:color 0.2s ease;pointer-events:none;"></i></span><span style="${titleStyle}">${escapeHTML(getLocalizedTaskTitle(subtask))}</span><small>${escapeHTML(subtask.due_date || taskDetailText('No due date', 'بدون تاريخ استحقاق'))}</small></button>`;
            }).join('') : `<div class="task-tab-empty">${taskDetailText('No subtasks yet.', 'لا توجد مهام فرعية بعد.')}</div>`}</div></section>`;
    }
    if (window.lucide) window.lucide.createIcons();
};

window.setTaskActivityTab = function (tab) {
    const task = window.activeTaskDetail;
    const panel = document.getElementById('taskSidePanel');
    const activityPanel = document.getElementById('taskActivityPanel');
    const comments = document.getElementById('taskCommentsList');
    const composer = panel?.querySelector('.side-panel-footer');
    if (!task || !activityPanel || !comments) return;
    panel.querySelectorAll('[data-task-activity-tab]').forEach(button => button.classList.toggle('active', button.dataset.taskActivityTab === tab));
    comments.style.display = tab === 'comments' ? 'flex' : 'none';
    const privateList = (window.taskListsCache || []).find(list => list.id === task.task_list_id);
    const canComment = !task.task_list_id || privateList?.owner_id === currentUser?.id;
    if (composer) composer.style.display = tab === 'comments' && canComment ? '' : 'none';
    activityPanel.style.display = tab === 'comments' ? 'none' : 'block';
    if (tab === 'activity') {
        activityPanel.innerHTML = `<div class="task-activity-event"><i data-lucide="circle-plus"></i><div><strong>${taskDetailText('Task created', 'تم إنشاء المهمة')}</strong><span>${task.created_at ? new Date(task.created_at).toLocaleString(currentLang === 'ar' ? 'ar-SA' : undefined) : taskDetailText('Date unavailable', 'التاريخ غير متاح')}</span></div></div><div class="task-activity-event"><i data-lucide="workflow"></i><div><strong>${taskDetailText('Current stage', 'المرحلة الحالية')}: ${escapeHTML(taskDetailValue(task.status, 'status'))}</strong><span>${taskDetailText('Assigned to', 'مُعيّنة إلى')} ${escapeHTML(window.formatEmployeeName(task.assignee) || taskDetailText('Unassigned', 'غير معيّن'))}</span></div></div>`;
    } else if (tab === 'info') {
        activityPanel.innerHTML = `<div class="task-detail-data-grid"><div><span>${taskDetailText('Created by', 'أنشأها')}</span><strong>${escapeHTML(window.formatEmployeeName(task.creator) || taskDetailText('System', 'النظام'))}</strong></div><div><span>${taskDetailText('Assigned to', 'مُعيّنة إلى')}</span><strong>${escapeHTML(window.formatEmployeeName(task.assignee) || taskDetailText('Unassigned', 'غير معيّن'))}</strong></div><div><span>${taskDetailText('Visibility', 'الظهور')}</span><strong>${escapeHTML(taskDetailValue(task.visibility || 'public', 'visibility'))}</strong></div><div><span>${taskDetailText('Estimated time', 'الوقت المقدر')}</span><strong>${escapeHTML(task.estimated_time || taskDetailText('Not set', 'غير محدد'))}</strong></div></div>`;
    }
    if (window.lucide) window.lucide.createIcons();
};

window.closeTaskDetailsModal = function () {
    document.getElementById('taskSidePanel')?.classList.remove('active');
    document.getElementById('taskSidePanelOverlay')?.classList.remove('active');
};

window.approveTaskCompletion = async function (taskId) {
    let task = window.taskCache?.[taskId];
    if (!task) task = (await db.fetchTasks()).find(item => item.id === taskId);
    if (!window.taskDepartmentManagerByName) {
        const departments = await db.fetchDepartments();
        window.taskDepartmentManagerByName = Object.fromEntries(departments.map(department => [department.name, department.head_id || department.manager_id || null]));
    }
    if (!task || window.taskDepartmentManagerByName?.[task.department] !== currentUser?.id) {
        showToast(window.t('msg_toast_17') || 'Only this task’s department manager can approve completion.', 'danger');
        return;
    }
    const result = await db.updateTaskStatus(taskId, 'completed');
    if (!result.success) {
        showToast(result.error?.message || 'Unable to approve task completion.', 'danger');
        return;
    }
    showToast(window.t('msg_toast_18') || 'Task approved and moved to Done.', 'success');
    if (currentView === 'tasks') {
        await renderView('tasks');
        if (window.taskCache?.[taskId]) openTaskDetailsModal(taskId);
    } else if (currentView === 'notifications') {
        await renderView('notifications');
    } else {
        await pollNotifications();
    }
};

window.handleTaskCommentSubmit = async function (e) {
    e.preventDefault();
    const id = document.getElementById('detailsTaskId').value;
    const input = document.getElementById('taskCommentInput');
    const content = input.value;
    if (!content.trim() || !id) return;
    if (!canInteractWithTask(window.activeTaskDetail) || String(window.activeTaskDetail?.id) !== String(id)) {
        showToast(window.t('msg_toast_9') || 'You do not have access to this task.', 'warning');
        return;
    }

    input.disabled = true;
    const { success } = await db.addTaskComment(id, currentUser.id, content);
    input.disabled = false;

    if (success) {
        input.value = '';

        // In-app and email notifications are queued by the database trigger.
        const task = window.taskCache ? window.taskCache[id] : null;
        if (task) {
            await db.triggerWebhooks('task_activity_email', {
                type: 'comment',
                task_id: id,
                task_title: task.title,
                assignee_id: task.assignee_id,
                comment_content: content
            });
        }

        // Reload comments
        openTaskDetailsModal(id);
    } else {
        showToast(t('toast_failed_to_post_comment'), "danger");
    }
};

window.handleCreateSubTaskClick = function () {
    const parentId = document.getElementById('detailsTaskId').value;
    if (!parentId) return;

    document.getElementById('taskSidePanel').classList.remove('active');
    document.getElementById('taskSidePanelOverlay').classList.remove('active');

    if (document.getElementById('taskParentId')) {
        document.getElementById('taskParentId').value = parentId;
    }

    const form = document.getElementById('standardTaskForm');
    if (form) {
        form.scrollIntoView({ behavior: 'smooth' });
        form.style.transition = 'box-shadow 0.3s ease';
        form.style.boxShadow = '0 0 10px 2px var(--color-primary)';
        setTimeout(() => {
            form.style.boxShadow = 'none';
        }, 1500);

        const titleInput = document.getElementById('taskTitle');
        if (titleInput) titleInput.focus();
    }
};

async function renderLeaveCalculator() {
    const role = String(currentUserRole || '').toUpperCase();
    const allowed = ['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN', 'HR_MANAGER'].includes(role) || /HR\s*MANAGER/i.test(String(currentUserProfile?.job_title || ''));
    if (!allowed) return `<div class="card"><h2>${escapeHTML(t('ui_access_denied') || 'Access denied')}</h2></div>`;
    const [profiles, requests, departments] = await Promise.all([db.fetchAllProfiles(true), db.fetchLeaveRequests(null), db.fetchDepartments()]);
    const departmentMap = Object.fromEntries((departments || []).map(d => [d.id, d.name || d.name_en || '—']));
    const year = new Date().getFullYear();
    const days = (start, end) => start && end ? Math.max(0, Math.ceil((new Date(end) - new Date(start)) / 86400000) + 1) : 0;
    const rows = (profiles || []).map(profile => {
        const mine = (requests || []).filter(r => r.employee_id === profile.id && new Date(r.start_date || r.created_at).getFullYear() === year);
        const sum = (type, status) => mine.filter(r => String(r.leave_type || '').toLowerCase() === type && (!status || String(r.status || '').toUpperCase().startsWith(status))).reduce((n, r) => n + days(r.start_date, r.end_date), 0);
        const allowance = Number(profile.annual_leave_allowance) > 0 ? Number(profile.annual_leave_allowance) : 30;
        const requested = mine.filter(r => String(r.status || '').toUpperCase().startsWith('PENDING')).reduce((n, r) => n + days(r.start_date, r.end_date), 0);
        const approved = mine.filter(r => String(r.status || '').toUpperCase().startsWith('APPROVED')).reduce((n, r) => n + days(r.start_date, r.end_date), 0);
        return { name: profile.full_name || '—', department: departmentMap[profile.department_id] || '—', allowance, requested, approved, remaining: Math.max(0, allowance - approved), annual: sum('annual leave'), sick: sum('sick leave') };
    });
    window.leaveCalculatorRows = rows;
    const e = value => escapeHTML(String(value ?? ''));
    return `<section class="page-section leave-calculator-page"><div class="page-header"><div><span class="eyebrow">${e(t('nav_leave_calculator'))}</span><h1 class="page-title">${e(t('leave_report_title') || 'Leave calculator')}</h1><p class="page-subtitle">${e(t('leave_report_subtitle') || 'Detailed leave report for all employees')}</p></div><button class="btn btn-secondary" type="button" onclick="window.downloadLeaveReport()"><i data-lucide="download"></i> ${e(t('download_report') || 'Download report')}</button></div><div class="card leave-calculator-summary"><div><strong>${rows.length}</strong><span>${e(t('employees') || 'Employees')}</span></div><div><strong>${rows.reduce((n,r)=>n+r.approved,0)}</strong><span>${e(t('leave_days_used') || 'Approved days')}</span></div><div><strong>${rows.reduce((n,r)=>n+r.requested,0)}</strong><span>${e(t('leave_days_requested') || 'Requested days')}</span></div></div><div class="card leave-report-card"><div class="table-responsive"><table class="data-table leave-report-table"><thead><tr><th>${e(t('employee_name') || 'Employee')}</th><th>${e(t('department') || 'Department')}</th><th>${e(t('annual_leave') || 'Annual leave')}</th><th>${e(t('leave_days_requested') || 'Requested')}</th><th>${e(t('leave_days_used') || 'Approved')}</th><th>${e(t('leave_remaining') || 'Remaining')}</th><th>${e(t('sick_leave') || 'Sick leave')}</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${e(r.name)}</td><td>${e(r.department)}</td><td>${r.allowance}</td><td>${r.requested}</td><td>${r.approved}</td><td><span class="leave-remaining-badge">${r.remaining}</span></td><td>${r.sick}</td></tr>`).join('') || `<tr><td colspan="7">${e(t('no_data') || 'No data available')}</td></tr>`}</tbody></table></div></div></section>`;
}

window.downloadLeaveReport = function () {
    const rows = window.leaveCalculatorRows || [];
    const csv = [['Employee','Department','Annual allowance','Requested','Approved','Remaining','Sick leave'], ...rows.map(r => [r.name,r.department,r.allowance,r.requested,r.approved,r.remaining,r.sick])].map(row => row.map(v => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\n');
    const url = URL.createObjectURL(new Blob([`\ufeff${csv}`], {type:'text/csv;charset=utf-8'})); const a = document.createElement('a'); a.href = url; a.download = `leave-report-${new Date().getFullYear()}.csv`; a.click(); URL.revokeObjectURL(url);
};

async function renderLeave() {
    const isManagerOrAdmin = currentUserRole === 'ADMIN' || ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR');
    const profile = await db.getUserProfile(currentUser?.id);
    let requests = await db.fetchLeaveRequests(isManagerOrAdmin ? null : currentUser?.id);

    let profilesMap = {};
    if (isManagerOrAdmin) {
        const allProfiles = await db.fetchAllProfiles();
        let teamIds = [currentUser.id];
        allProfiles.forEach(p => {
            profilesMap[p.id] = window.formatEmployeeName(p) || 'Unknown User';
            if (p.manager_id === currentUser.id) teamIds.push(p.id);
        });
        if (currentUserRole !== 'ADMIN') {
            requests = requests.filter(r => teamIds.includes(r.employee_id));
        }
    }

    const approvedLeaves = requests.filter(r => r.status.startsWith('APPROVED'));
    let annualTaken = 0, sickTaken = 0, unpaidTaken = 0;

    // Only calculate allowance balances for the current user's OWN approved leaves
    const myApprovedLeaves = approvedLeaves.filter(r => r.employee_id === currentUser?.id);
    myApprovedLeaves.forEach(r => {
        const start = new Date(r.start_date);
        const end = new Date(r.end_date);
        const days = Math.ceil((end - start) / (1000 * 60 * 60 * 24)) + 1;
        if (r.leave_type === 'Annual Leave') annualTaken += days;
        else if (r.leave_type === 'Sick Leave') sickTaken += days;
        else if (r.leave_type === 'Unpaid Leave') unpaidTaken += days;
    });

    const annualAllowance = profile.annual_leave_allowance || 30;
    const sickAllowance = profile.sick_leave_allowance || 10;

    let rowsHTML = requests.map(r => {
        let badgeClass = 'info';
        if (r.status.startsWith('APPROVED')) badgeClass = 'success';
        if (r.status.startsWith('REJECTED')) badgeClass = 'danger';

        const employeeNameCell = isManagerOrAdmin ? `<td>${profilesMap[r.employee_id] || 'Unknown'}</td>` : '';

        let actionsCell = '';
        if (isManagerOrAdmin) {
            if (r.status === 'PENDING') {
                actionsCell = `
                    <td>
                        <button class="btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem;" onclick="handleLeaveAction('${r.id}', 'APPROVED', '${r.employee_id}')">${t('leave_approve')}</button>
                        <button class="btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; background: var(--color-danger);" onclick="handleLeaveAction('${r.id}', 'REJECTED', '${r.employee_id}')">${t('leave_reject')}</button>
                    </td>
                `;
            } else {
                actionsCell = `<td>-</td>`;
            }
        }

        return `
            <tr>
                ${employeeNameCell}
                <td><strong>${r.leave_type}</strong></td>
                <td>${new Date(r.start_date).toLocaleDateString()} to ${new Date(r.end_date).toLocaleDateString()}</td>
                <td><span class="status-badge ${badgeClass}">${r.status.replace('_ARCHIVED', '')}</span></td>
                ${actionsCell}
            </tr>
        `;
    }).join('');

    if (requests.length === 0) {
        const colSpan = isManagerOrAdmin ? 5 : 3;
        rowsHTML = `<tr><td colspan="${colSpan}" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">${t('leave_no_reqs')}</td></tr>`;
    }

    const employeeHeader = isManagerOrAdmin ? `<th>${t('leave_employee')}</th>` : '';
    const actionsHeader = isManagerOrAdmin ? `<th>${t('leave_actions')}</th>` : '';

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('nav_leave')}</h1>
                <p class="page-subtitle">${t('leave_req_sub')}</p>
            </div>
        </div>
        
        <!-- SAP-like Summary Cards -->
        <div class="dashboard-grid fade-in-up" style="margin-bottom: 2rem;">
            <div class="card col-span-4" style="border-top: 4px solid var(--color-primary);">
                <div style="font-size: 0.875rem; color: var(--color-text-secondary); margin-bottom: 0.5rem;">${t('leave_annual_bal')}</div>
                <div style="display: flex; justify-content: space-between; align-items: baseline;">
                    <h2 style="font-size: 2.5rem; margin: 0;">${Math.max(0, annualAllowance - annualTaken)} <span style="font-size: 1rem; color: var(--color-text-secondary);">/ ${annualAllowance} ${t('leave_days')}</span></h2>
                </div>
            </div>
            <div class="card col-span-4" style="border-top: 4px solid var(--color-success);">
                <div style="font-size: 0.875rem; color: var(--color-text-secondary); margin-bottom: 0.5rem;">${t('leave_sick_bal')}</div>
                <div style="display: flex; justify-content: space-between; align-items: baseline;">
                    <h2 style="font-size: 2.5rem; margin: 0;">${Math.max(0, sickAllowance - sickTaken)} <span style="font-size: 1rem; color: var(--color-text-secondary);">/ ${sickAllowance} ${t('leave_days')}</span></h2>
                </div>
            </div>
            <div class="card col-span-4" style="border-top: 4px solid var(--color-warning);">
                <div style="font-size: 0.875rem; color: var(--color-text-secondary); margin-bottom: 0.5rem;">${t('leave_unpaid_bal')}</div>
                <div style="display: flex; justify-content: space-between; align-items: baseline;">
                    <h2 style="font-size: 2.5rem; margin: 0;">${unpaidTaken} <span style="font-size: 1rem; color: var(--color-text-secondary);">${t('leave_days')}</span></h2>
                </div>
            </div>
        </div>

        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-4">
                <div class="card-title">${t('leave_new_req')}</div>
                <form autocomplete="off" onsubmit="handleLeaveSubmit(event)">
                    <div class="form-group">
                        <label class="form-label">${t('leave_type')}</label>
                        <select id="leaveType" class="form-control" required onchange="handleLeaveTypeChange(this.value)">
                            <option value="Annual Leave">${t('annual_leave')}</option>
                            <option value="Sick Leave">${t('sick_leave')}</option>
                            <option value="Unpaid Leave">${t('unpaid_leave')}</option>
                            <option value="Short Leave">Short Leave</option>
                        </select>
                    </div>
                    <div class="form-group" id="leaveStartGroup">
                        <label class="form-label">${t('start_date')}</label>
                        <input id="leaveStart" type="date" class="form-control" required>
                    </div>
                    <div class="form-group" id="leaveEndGroup">
                        <label class="form-label">${t('end_date')}</label>
                        <input id="leaveEnd" type="date" class="form-control" required>
                    </div>
                    <div class="form-group" id="leaveReasonGroup">
                        <label class="form-label">${t('reason')}</label>
                        <textarea id="leaveReason" class="form-control" required></textarea>
                    </div>
                    <div id="leaveShortFields" style="display:none;">
                        <div class="form-group">
                            <label class="form-label">Short Leave Reason</label>
                            <select id="leaveShortReason" class="form-control">
                                <option value="">Select reason</option>
                                <option value="I am running late to the office.">I am running late to the office.</option>
                                <option value="I will be out for a meeting.">I will be out for a meeting.</option>
                                <option value="I need to attend an urgent family matter.">I need to attend an urgent family matter.</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label class="form-label">Duration</label>
                            <select id="leaveShortDuration" class="form-control">
                                <option value="15">15 Minutes</option><option value="60">1 Hour</option>
                                <option value="120">2 Hours</option><option value="180">3 Hours</option>
                            </select>
                        </div>
                    </div>
                    <button type="submit" class="btn-primary" style="width: 100%;">${t('submit')}</button>
                </form>
            </div>
            
            <div class="card col-span-8">
                <div class="card-title">${t('leave_history')}</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                ${employeeHeader}
                                <th>${t('leave_type')}</th>
                                <th>${t('leave_dates')}</th>
                                <th>${t('status')}</th>
                                ${actionsHeader}
                            </tr>
                        </thead>
                        <tbody>
                            ${rowsHTML}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    `;
}

// ==========================================
// EXPENSES
// ==========================================
window.handleExpenseSubmit = async function (e) {
    e.preventDefault();
    const amount = document.getElementById('expAmount').value;
    const description = document.getElementById('expDesc').value;
    const fileInput = document.getElementById('expReceipt');

    if (!fileInput.files || fileInput.files.length === 0) {
        showToast(t('toast_please_upload_a_receipt'), "warning");
        return;
    }

    const file = fileInput.files[0];
    const reader = new FileReader();
    reader.onload = async function (event) {
        const base64Url = event.target.result;
        const { success } = await db.submitExpense(currentUser.id, amount, description, base64Url);
        if (success) {
            showToast(t('toast_expense_submitted_for_approval'), "success");
            renderView('expenses');
        } else {
            showToast(t('toast_error_submitting_expense'), "danger");
        }
    };
    reader.readAsDataURL(file);
}

window.handleExpenseAction = async function (id, status, employeeId) {
    const { success } = await db.updateExpenseStatus(id, status);
    if (success) {
        showToast(`Expense ${status.toLowerCase()}`, "success");
        if (employeeId) await db.createNotification(employeeId, `Your expense request has been ${status}.`);
        renderView('expenses');
    }
}

async function renderExpenses() {
    const isManagerOrAdmin = currentUserRole === 'ADMIN' || ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR');

    let expenses = [];
    if (currentUserRole === 'ADMIN') {
        expenses = await db.fetchExpenses(null);
    } else if (((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR')) {
        const allExpenses = await db.fetchExpenses(null);
        const users = await db.fetchUsers();
        const myTeamIds = users.filter(u => u.manager_id === currentUser.id).map(u => u.id);
        myTeamIds.push(currentUser.id);
        expenses = allExpenses.filter(e => myTeamIds.includes(e.employee_id));
    } else {
        expenses = await db.fetchExpenses(currentUser.id);
    }

    const pendingExpenses = expenses.filter(e => e.status === 'PENDING' && e.employee_id !== currentUser.id);
    const myExpenses = expenses.filter(e => e.employee_id === currentUser.id);

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('exp_title')}</h1>
                <p class="page-subtitle">${t('exp_sub')}</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-4">
                <div class="card-title">${t('exp_new')}</div>
                <form autocomplete="off" onsubmit="handleExpenseSubmit(event)">
                    <div class="form-group">
                        <label class="form-label">${t('exp_amount')}</label>
                        <input type="number" step="0.01" id="expAmount" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('exp_desc')}</label>
                        <input type="text" id="expDesc" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('exp_receipt')}</label>
                        <input type="file" id="expReceipt" accept="image/*,application/pdf" class="form-control" required>
                    </div>
                    <button type="submit" class="btn-primary" style="width: 100%;">${t('exp_submit')}</button>
                </form>
            </div>
            
            <div class="card col-span-8">
                <div class="card-title">${t('exp_my')}</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead><tr><th>${t('exp_desc')}</th><th>${t('exp_amount')}</th><th>${t('req_status')}</th><th>${t('exp_receipt')}</th></tr></thead>
                        <tbody>
                            ${myExpenses.length === 0 ? `<tr><td colspan="4" style="text-align: center;">${t('exp_no_exp')}</td></tr>` : myExpenses.map(e => `
                                <tr>
                                    <td>${e.description}</td>
                                    <td>$${e.amount.toFixed(2)}</td>
                                    <td><span class="status-badge ${e.status.startsWith('APPROVED') ? 'success' : (e.status.startsWith('REJECTED') ? 'danger' : 'warning')}">${e.status.replace('_ARCHIVED', '')}</span></td>
                                    <td><a href="${e.receipt_base64}" download="receipt_${e.id}" class="btn-secondary" style="padding: 0.25rem 0.5rem; text-decoration: none; font-size: 0.75rem;">${t('exp_download')}</a></td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
            
            ${isManagerOrAdmin ? `
            <div class="card col-span-12" style="margin-top: 1rem;">
                <div class="card-title">${t('exp_team_appr')}</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead><tr><th>${t('leave_employee')} ID</th><th>${t('exp_desc')}</th><th>${t('exp_amount')}</th><th>${t('exp_receipt')}</th><th>${t('leave_actions')}</th></tr></thead>
                        <tbody>
                            ${pendingExpenses.length === 0 ? `<tr><td colspan="5" style="text-align: center;">${t('exp_no_pending')}</td></tr>` : pendingExpenses.map(e => `
                                <tr>
                                    <td><span style="font-size: 0.75rem;">${e.employee_id.substring(0, 8)}...</span></td>
                                    <td>${e.description}</td>
                                    <td>$${e.amount.toFixed(2)}</td>
                                    <td><a href="${e.receipt_base64}" download="receipt_${e.id}" class="btn-secondary" style="padding: 0.25rem 0.5rem; text-decoration: none; font-size: 0.75rem;">${t('exp_download')}</a></td>
                                    <td>
                                        <button class="btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem;" onclick="handleExpenseAction('${e.id}', 'APPROVED', '${e.employee_id}')">${t('leave_approve')}</button>
                                        <button class="btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; background: var(--color-danger);" onclick="handleExpenseAction('${e.id}', 'REJECTED', '${e.employee_id}')">${t('leave_reject')}</button>
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
            ` : ''}
        </div>
    `;
}

// ==========================================
// ANALYTICS
// ==========================================
async function renderAnalytics() {
    if (currentUserRole !== 'ADMIN' && currentUserRole !== 'MANAGER') {
        return `<div class="page-header"><h1 class="page-title">${t('analy_unauth')}</h1></div>`;
    }
    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('analy_title')}</h1>
                <p class="page-subtitle">${t('analy_sub')}</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-6">
                <div class="card-title">${t('analy_growth')}</div>
                <canvas id="growthChart" width="400" height="200"></canvas>
            </div>
            <div class="card col-span-6">
                <div class="card-title">${t('analy_leave')}</div>
                <canvas id="leaveChart" width="400" height="200"></canvas>
            </div>
        </div>
    `;
}

function initCharts() {
    const growthCtx = document.getElementById('growthChart');
    if (growthCtx && typeof Chart !== 'undefined') {
        new Chart(growthCtx, {
            type: 'line',
            data: {
                labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'],
                datasets: [{
                    label: 'Employees',
                    data: [10, 15, 22, 28, 35, 42],
                    borderColor: '#0f3a68',
                    backgroundColor: 'rgba(15, 58, 104, 0.1)',
                    tension: 0.1,
                    fill: true
                }]
            }
        });
    }
    const leaveCtx = document.getElementById('leaveChart');
    if (leaveCtx && typeof Chart !== 'undefined') {
        new Chart(leaveCtx, {
            type: 'bar',
            data: {
                labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'],
                datasets: [{
                    label: 'Leave Days',
                    data: [5, 8, 3, 12, 15, 10],
                    backgroundColor: '#10b981'
                }]
            }
        });
    }
}

// ==========================================
// PAYROLL
// ==========================================
window.handleViewPayslip = function (month, netPay) {
    const modal = document.getElementById('viewPayslipModal');
    if (!modal) {
        window.showAppMessageModal(`SAP Detailed Payslip for ${month}\n------------------------\nBase Salary: $${(netPay * 0.8).toFixed(2)}\nAllowances: $${(netPay * 0.2).toFixed(2)}\n\nNet Pay: $${netPay.toFixed(2)}`);
        return;
    }

    document.getElementById('payslipModalMonth').textContent = `SAP Detailed Payslip for ${month}`;
    document.getElementById('payslipModalBase').textContent = `$${(netPay * 0.8).toFixed(2)}`;
    document.getElementById('payslipModalAllowances').textContent = `$${(netPay * 0.2).toFixed(2)}`;
    document.getElementById('payslipModalNet').textContent = `$${netPay.toFixed(2)}`;

    modal.classList.add('active');
    if (window.lucide) window.lucide.createIcons();
}

// Render Payroll


// Render Admin Hub
window.previewRole = function (role) {
    if (!window.originalUserRole) window.originalUserRole = currentUserRole;
    currentUserRole = role;
    window.updateSidebarVisibility();
    renderView('dashboard');
    showToast(t('toast_viewing_as') ? t('toast_viewing_as') + ' ' + role : 'Viewing as ' + role, 'info');

    if (!document.getElementById('revertRoleBtn')) {
        const btn = document.createElement('button');
        btn.id = 'revertRoleBtn';
        btn.innerHTML = '<i data-lucide="arrow-left" style="width:16px;height:16px;margin-right:8px;vertical-align:middle;"></i>' + (t('ui_return_to_admin') || 'Return to Admin');
        btn.style.position = 'fixed';
        btn.style.bottom = '20px';
        btn.style.right = '20px';
        btn.style.zIndex = '9999';
        btn.style.backgroundColor = 'var(--color-danger)';
        btn.style.color = '#fff';
        btn.style.padding = '10px 20px';
        btn.style.border = 'none';
        btn.style.borderRadius = '5px';
        btn.style.cursor = 'pointer';
        btn.style.boxShadow = '0 4px 6px rgba(0,0,0,0.1)';
        btn.style.display = 'flex';
        btn.style.alignItems = 'center';

        btn.onclick = function () {
            currentUserRole = window.originalUserRole;
            window.originalUserRole = null;
            document.body.removeChild(btn);
            window.updateSidebarVisibility();
            renderView('admin');
        };
        document.body.appendChild(btn);
        lucide.createIcons({ root: btn });
    }
};

async function renderAdmin() {
    if (currentUserRole !== 'ADMIN') {
        return `<div class="page-header"><h1 class="page-title">${t('analy_unauth')}</h1></div>`;
    }

    const employees = await db.fetchAllEmployees();
    let pendingLeaves = await db.fetchAllPendingLeaves();

    if (((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR')) {
        const myTeamIds = employees.filter(e => e.manager_id === currentUser.id).map(e => e.id);
        pendingLeaves = pendingLeaves.filter(l => myTeamIds.includes(l.employee_id));
    }

    let leaveHTML = pendingLeaves.map(r => `
        <div style="display: flex; justify-content: space-between; align-items: center; padding: 1rem; border-bottom: 1px solid var(--color-border);">
            <div>
                <h4 style="margin-bottom: 4px;">${r.leave_type}</h4>
                <p style="font-size: 0.875rem; color: var(--color-text-secondary);">${new Date(r.start_date).toLocaleDateString()} - ${new Date(r.end_date).toLocaleDateString()}</p>
                <p style="font-size: 0.75rem; color: var(--color-text-secondary); margin-top: 4px;">Employee ID: ${r.employee_id.substring(0, 8)}...</p>
            </div>
            <div style="display: flex; gap: 8px;">
                <button class="btn-primary" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;" onclick="handleLeaveAction('${r.id}', 'APPROVED', '${r.employee_id}')">${t('leave_approve')}</button>
                <button class="btn-primary" style="padding: 0.25rem 0.75rem; font-size: 0.75rem; background: var(--color-danger);" onclick="handleLeaveAction('${r.id}', 'REJECTED', '${r.employee_id}')">${t('leave_reject')}</button>
            </div>
        </div>
    `).join('');

    if (pendingLeaves.length === 0) {
        leaveHTML = `<p style="padding: 1rem; color: var(--color-text-secondary);">${t('admin_no_pending')}</p>`;
    }

    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('admin_overview')}</h1>
                <p class="page-subtitle">${t('admin_sub')}</p>
            </div>
        </div>

        <div class="dashboard-grid" style="margin-bottom: 2rem;">
            <div class="card col-span-3" style="text-align: center; cursor: pointer;" onclick="renderView('tasks')">
                <i data-lucide="check-square" style="margin-bottom: 0.5rem; color: var(--color-primary); width: 24px; height: 24px;"></i>
                <h4>${t('admin_manage_tasks')}</h4>
            </div>
            <div class="card col-span-3" style="text-align: center; cursor: pointer;" onclick="renderView('time')">
                <i data-lucide="clock" style="margin-bottom: 0.5rem; color: var(--color-primary); width: 24px; height: 24px;"></i>
                <h4>${t('admin_time_reports')}</h4>
            </div>
            <div class="card col-span-3" style="text-align: center; cursor: pointer;" onclick="renderView('users')">
                <i data-lucide="users" style="margin-bottom: 0.5rem; color: var(--color-primary); width: 24px; height: 24px;"></i>
                <h4>${t('admin_emp_dir')}</h4>
            </div>
            <div class="card col-span-3" style="text-align: center; cursor: pointer;" onclick="renderView('documents')">
                <i data-lucide="file-text" style="margin-bottom: 0.5rem; color: var(--color-primary); width: 24px; height: 24px;"></i>
                <h4>${t('admin_docs')}</h4>
            </div>
        </div>

        <div class="dashboard-grid" style="margin-bottom: 2rem;">
            <div class="card col-span-4" style="text-align: center; cursor: pointer; border: 1px dashed var(--color-primary);" onclick="previewRole('EMPLOYEE')">
                <i data-lucide="eye" style="margin-bottom: 0.5rem; color: var(--color-primary); width: 24px; height: 24px;"></i>
                <h4>${t('ui_employee_view') || 'Employee View'}</h4>
            </div>
            <div class="card col-span-4" style="text-align: center; cursor: pointer; border: 1px dashed var(--color-primary);" onclick="previewRole('SUPERVISOR')">
                <i data-lucide="eye" style="margin-bottom: 0.5rem; color: var(--color-primary); width: 24px; height: 24px;"></i>
                <h4>${t('ui_supervisor_view') || 'Supervisor View'}</h4>
            </div>
            <div class="card col-span-4" style="text-align: center; cursor: pointer; border: 1px dashed var(--color-primary);" onclick="previewRole('MANAGER')">
                <i data-lucide="eye" style="margin-bottom: 0.5rem; color: var(--color-primary); width: 24px; height: 24px;"></i>
                <h4>${t('ui_manager_view') || 'Manager View'}</h4>
            </div>
        </div>

        <div class="dashboard-grid">
            <div class="card col-span-4">
                <div class="card-title">${t('headcount')} <i data-lucide="users"></i></div>
                <h2 style="font-size: 2.5rem; margin-top: 10px;">${employees.length}</h2>
                <p style="color: var(--color-success); font-size: 0.875rem;">${t('admin_reg_users')}</p>
            </div>
            
            <div class="card col-span-4">
                <div class="card-title">${t('admin_pend_appr')} <i data-lucide="inbox"></i></div>
                <h2 style="font-size: 2.5rem; margin-top: 10px;">${pendingLeaves.length}</h2>
                <p style="color: var(--color-warning); font-size: 0.875rem;">${t('admin_req_attn')}</p>
            </div>
            
            <div class="card col-span-8">
                <div class="card-title">${t('admin_leave_inbox')}</div>
                <div style="max-height: 300px; overflow-y: auto;">
                    ${leaveHTML}
                </div>
            </div>
            
        </div>
    `;
}

// Render User Management (Admin Only)
window.handleCreateUser = async function (e) {
    e.preventDefault();
    const employeeId = '';
    const fullName = document.getElementById('newFullName').value;
    const email = document.getElementById('newEmail').value.trim().toLowerCase();
    const password = document.getElementById('newPassword').value;
    const role = 'EMPLOYEE';
    const jobTitle = '';
    const fullNameAr = document.getElementById('newFullNameAr').value;
    const iqama = '';
    const phone = document.getElementById('newPhone').value;
    const departmentId = '';
    const nationality = '';

    const { data, error } = await db.createUser(email, password, role, jobTitle, fullName, iqama, phone, departmentId, nationality, fullNameAr, employeeId);
    if (!error) {
        const assignedEmployeeId = data?.emp_index ? formatEmployeeId(data.emp_index) : '';
        showToast(assignedEmployeeId ? `${t('toast_user_created_successfully')} (${assignedEmployeeId})` : t('toast_user_created_successfully'), 'success');
        if (typeof closeAddUserModal === 'function') closeAddUserModal();
        const createdUserId = data?.id || (typeof data === 'string' ? data : null);
        window.navigateToContract(createdUserId, fullName);
    } else {
        showToast(error.message || "Failed to create user", 'danger');
    }
}

window.handleChangeRole = async function (id, role) {
    const { success } = await db.updateUserRole(id, role);
    if (success) {
        showToast(t('toast_role_updated'), "success");
        await window.refreshUserRowInPlace(id, { role });
    } else {
        showToast(window.t('msg_toast_19') || 'Failed to update role.', 'danger');
        await window.refreshUserRowInPlace(id);
    }
}

window.handleChangeJobTitle = async function (id, jobTitle, selectElement = null) {
    const departmentId = selectElement?.closest('tr')?.querySelector('[data-directory-department]')?.value || null;
    const { success } = await db.updateUserJobTitle(id, jobTitle, departmentId);
    if (success) {
        showToast(t('toast_job_title_updated'), "success");
        await window.refreshUserRowInPlace(id, { job_title: jobTitle, department_id: departmentId });
    } else {
        showToast(t('toast_failed_to_update_job_title'), "danger");
        await window.refreshUserRowInPlace(id);
    }
}

window.handleDirectoryDepartmentChange = async function (userId, departmentId, selectElement) {
    const jobTitleSelect = selectElement.closest('tr')?.querySelector('[data-directory-job-title]');
    if (!departmentId) {
        if (jobTitleSelect) {
            jobTitleSelect.innerHTML = '<option value="">Select Department first</option>';
            jobTitleSelect.disabled = true;
        }
        return;
    }
    const departmentName = selectElement.options[selectElement.selectedIndex]?.text || '';
    const currentTitle = jobTitleSelect?.value || '';
    const jobTitlesMap = db.getJobTitlesMap() || {};
    const matchedDepartment = Object.keys(jobTitlesMap).find(name => name.trim().toLowerCase() === departmentName.trim().toLowerCase());
    if (!matchedDepartment || !jobTitlesMap[matchedDepartment].includes(currentTitle)) {
        if (jobTitleSelect) {
            jobTitleSelect.disabled = false;
            jobTitleSelect.innerHTML = companyJobTitleOptions('', departmentName);
        }
        showToast(`Now select a job title for ${departmentName}. The department will be saved with that title.`, 'info');
        return;
    }
    const result = await db.updateUserProfile(userId, { department_id: departmentId });
    if (!result.success) {
        showToast(window.t('msg_toast_20') || 'Failed to update department.', 'danger');
        await window.refreshUserRowInPlace(userId);
        return;
    }
    await window.refreshUserRowInPlace(userId, { department_id: departmentId });
    showToast(window.t('msg_toast_21') || 'Department updated successfully.', 'success');
};

async function renderUsers() {
    if (currentUserRole !== 'ADMIN') return '<div style="padding: 2rem;">Unauthorized</div>';

    const [users, departments] = await Promise.all([db.fetchUsers(), db.fetchDepartments(), db.fetchJobTitles(true)]);
    window.currentAdminUsers = users;

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('nav_users')}</h1>
                <p class="page-subtitle">${t('users_sub')}</p>
            </div>
            <div style="display: flex; gap: 0.5rem;">
                <button class="btn btn-secondary" type="button" onclick="window.downloadUserDirectoryExcel()" title="Download user directory as Excel">
                    <i data-lucide="download"></i> Download Excel
                </button>
                <input type="file" id="bulkUserUploadUsersPage" accept=".xlsx, .xls" style="display: none;" onchange="handleBulkUpload(event)">
                <button class="btn btn-secondary" onclick="window.triggerSpecificBulkUpload('employees', 'bulkUserUploadUsersPage')">
                    <i data-lucide="upload"></i> ${t('ui_bulk_upload') || 'Bulk Upload'}
                </button>
                <button class="btn-primary" onclick="showAddUserModal()">
                    <i data-lucide="user-plus"></i> ${t('users_add_new')}
                </button>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-12">
                <div class="card-title">${t('users_dir')}</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Employee Details</th>
                                <th>${t('users_role')}</th>
                                <th>${t('ui_actions')}</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${users.map(u => `
                                <tr data-user-row="${u.id}">
                                    <td data-user-id><span class="directory-employee-id">${escapeHTML(formatEmployeeId(u.emp_index))}</span></td>
                                    <td data-user-details><div class="directory-employee-name">${escapeHTML(window.formatEmployeeName(u) || 'N/A')}</div></td>
                                    <td data-user-role><span data-user-role-badge class="status-badge ${u.role === 'ADMIN' ? 'success' : (u.role === 'MANAGER' ? 'warning' : 'info')}">${escapeHTML(u.role || 'EMPLOYEE')}</span></td>
                                    <td>
                                        <div class="directory-actions">
                                            <button type="button" class="btn-secondary btn-sm directory-view-button" onclick="window.showEmployeeDetailsCard('${u.id}')" title="View employee details"><i data-lucide="eye"></i><span>View</span></button>
                                            <button type="button" class="btn-primary btn-sm directory-edit-button" onclick="window.showEditUserModal('${u.id}')" title="Edit user"><i data-lucide="user-pen"></i><span>Edit</span></button>
                                            <button class="btn-secondary" style="padding: 0.4rem;" onclick="navigateToContract('${u.id}', '${(window.formatEmployeeName(u) || 'Employee').replace(/'/g, "\\'")}')" title="${t('users_contract')}">
                                                <i data-lucide="file-signature" style="width:14px;height:14px;"></i>
                                            </button>
                                            <button class="btn-secondary" style="padding: 0.4rem; font-size: 0.8rem; color: var(--color-warning);" onclick="showAdminPasswordResetModal('${u.id}')" title="${t('password_reset_button')}">
                                                <i data-lucide="key" style="width:14px;height:14px;"></i>
                                            </button>
                                            <button class="btn-secondary" style="padding: 0.4rem; font-size: 0.8rem; color: var(--color-danger);" onclick="handleDeleteUser('${u.id}')" title="Remove User">
                                                <i data-lucide="trash-2" style="width:14px;height:14px;"></i>
                                            </button>
                                        </div>
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    `;
}

window.downloadUserDirectoryExcel = function () {
    if (typeof XLSX === 'undefined') {
        showToast(window.t('msg_toast_22') || 'Excel export is unavailable. Please reload the page and try again.', 'danger');
        return;
    }
    const users = Array.isArray(window.currentAdminUsers) ? window.currentAdminUsers : [];
    if (!users.length) {
        showToast(window.t('msg_toast_23') || 'There are no users to export.', 'info');
        return;
    }
    const managerMap = new Map(users.map(user => [user.id, window.formatEmployeeName(user) || '']));
    const rows = users.map(user => ({
        'Employee ID': formatEmployeeId(user.emp_index),
        'Full Name': window.formatEmployeeName(user) || '',
        'Role': user.role || '',
        'Department': user.department_name || user.department || '',
        'Job Title': user.job_title || '',
        'Assigned Manager': managerMap.get(user.manager_id) || 'No Manager',
        'ID/Iqama number': user.iqama_number || '',
        'Phone Number': user.phone_number || '',
        'Email': user.email || ''
    }));
    const worksheet = XLSX.utils.json_to_sheet(rows);
    worksheet['!cols'] = [{ wch: 15 }, { wch: 28 }, { wch: 14 }, { wch: 24 }, { wch: 24 }, { wch: 24 }, { wch: 20 }, { wch: 18 }, { wch: 32 }];
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'User Directory');
    XLSX.writeFile(workbook, `user-directory-${new Date().toISOString().slice(0, 10)}.xlsx`);
    showToast(window.t('msg_toast_24') || 'User directory downloaded successfully.', 'success');
};

window.showAddUserModal = async () => {
    document.getElementById('addUserForm').reset();
    document.getElementById('addUserModal').classList.add('show');

    handleNewUserNationalityChange('Saudi');

    if (window.lucide) window.lucide.createIcons();
};

window.closeAddUserModal = () => {
    document.getElementById('addUserModal').classList.remove('show');
};


window.handleAssignManager = async function (id, managerId) {
    const { success } = await db.assignManager(id, managerId);
    if (success) {
        showToast(t('toast_manager_assigned'), "success");
        await window.refreshUserRowInPlace(id, { manager_id: managerId || null });
    } else {
        showToast(window.t('msg_toast_25') || 'Failed to assign manager.', 'danger');
        await window.refreshUserRowInPlace(id);
    }
}

// Render Performance
async function renderPerformance() {
    const goals = await db.fetchGoals(currentUserRole === 'ADMIN' ? null : currentUser.id);
    const isManager = currentUserRole === 'ADMIN' || (currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR';
    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('nav_performance')}</h1>
                <p class="page-subtitle">${t('perf_sub')}</p>
            </div>
            ${isManager ? `
            <button class="btn btn-primary" id="generatePerfBtn" onclick="generatePerformanceReport()">
                <i data-lucide="bar-chart-2"></i> Generate Performance Report
            </button>` : ''}
        </div>

        <!-- Performance Report Panel (hidden until generated) -->
        <div id="perfReportSection" style="display:none; margin-bottom: 1.5rem;">
            <div class="card fade-in-up">
                <div class="card-title" style="display:flex; justify-content:space-between; align-items:center;">
                    <span><i data-lucide="award" style="margin-right:8px; width:20px; height:20px; vertical-align:middle; color:var(--color-accent);"></i>${t('ui_employee_performance_report')}</span>
                    <div style="display:flex; align-items:center; gap: 1rem;">
                        <span id="perfReportDate" style="font-size:0.8rem; font-weight:400; color:var(--color-text-secondary);"></span>
                        <button class="btn btn-icon" onclick="printPerformanceReport()" title="Print Report" style="padding: 0.25rem;">
                            <i data-lucide="printer" style="width: 16px; height: 16px;"></i>
                        </button>
                    </div>
                </div>
                <div id="perfReportBody"></div>
            </div>
        </div>

        <div class="card fade-in-up">
            <div class="card-title">${t('perf_my_goals')}</div>
            <div class="table-responsive">
                <table class="data-table">
                    <thead><tr><th>${t('perf_title_th')}</th><th>${t('perf_due_date')}</th><th>${t('req_status')}</th><th>${t('perf_rating')}</th></tr></thead>
                    <tbody>
                        ${goals.length === 0 ? `<tr><td colspan="4">${t('perf_no_goals')}</td></tr>` : goals.map(g => `
                            <tr>
                                <td>${g.title}</td>
                                <td>${new Date(g.due_date).toLocaleDateString()}</td>
                                <td><span class="status-badge ${g.status === 'DONE' ? 'success' : 'warning'}">${g.status}</span></td>
                                <td>${g.rating || '-'} / 5</td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            </div>
        </div>
    `;
}

window.generatePerformanceReport = async function () {
    const btn = document.getElementById('generatePerfBtn');
    if (btn) { btn.disabled = true; btn.innerHTML = '<span class="spinner-sm" style="margin-right: 0.5rem;"></span> Generating...'; }
    if (window.lucide) window.lucide.createIcons();

    const tasks = await db.fetchTasksWithProfiles();

    // Group tasks by employee
    const empMap = {};
    tasks.forEach(task => {
        if (!task.assignee_id) return;
        const profile = task.profiles || {};
        const id = task.assignee_id;
        if (!empMap[id]) {
            empMap[id] = {
                id,
                name: profile.full_name || 'Unknown',
                job_title: profile.job_title || '',
                total: 0,
                done: 0,
                inProgress: 0,
                overdue: 0
            };
        }
        empMap[id].total++;
        if (task.status === 'DONE') empMap[id].done++;
        else if (task.status === 'IN_PROGRESS') empMap[id].inProgress++;
        // Check overdue: due_date in the past and not done
        if (task.due_date && task.status !== 'DONE') {
            const due = new Date(task.due_date);
            if (due < new Date()) empMap[id].overdue++;
        }
    });

    const employees = Object.values(empMap);
    if (employees.length === 0) {
        document.getElementById('perfReportBody').innerHTML = `<p style="color:var(--color-text-secondary); text-align:center; padding:2rem;">No task data available to generate a report.</p>`;
        document.getElementById('perfReportSection').style.display = 'block';
        if (btn) { btn.disabled = false; btn.innerHTML = '<i data-lucide="bar-chart-2"></i> Generate Performance Report'; if (window.lucide) window.lucide.createIcons(); }
        return;
    }

    // Compute score: (done / total * 100) - (overdue * 5 penalty), clamped 0â€“100
    employees.forEach(e => {
        const completionRate = e.total > 0 ? (e.done / e.total) * 100 : 0;
        const penalty = e.overdue * 5;
        e.score = Math.max(0, Math.round(completionRate - penalty));
        e.completionRate = Math.round(completionRate);
    });

    // Sort best to worst
    employees.sort((a, b) => b.score - a.score);

    const getRatingLabel = (score) => {
        if (score >= 85) return { label: 'Excellent', cls: 'success' };
        if (score >= 65) return { label: 'Good', cls: 'info' };
        if (score >= 40) return { label: 'Average', cls: 'warning' };
        return { label: 'Needs Improvement', cls: 'danger' };
    };

    const rows = employees.map((e, i) => {
        const { label, cls } = getRatingLabel(e.score);
        const medal = i === 0 ? 'ðŸ¥‡' : i === 1 ? 'ðŸ¥ˆ' : i === 2 ? 'ðŸ¥‰' : `#${i + 1}`;
        return `
        <tr>
            <td style="font-weight:600;">${medal} ${escapeHTML(e.name)}</td>
            <td style="color:var(--color-text-secondary); font-size:0.85rem;">${escapeHTML(e.job_title)}</td>
            <td>${e.total}</td>
            <td><span style="color:var(--color-success); font-weight:600;">${e.done}</span></td>
            <td><span style="color:var(--color-danger);">${e.overdue}</span></td>
            <td>
                <div style="display:flex; align-items:center; gap:8px;">
                    <div style="flex:1; background:var(--color-border); border-radius:999px; height:8px; overflow:hidden;">
                        <div style="width:${e.completionRate}%; height:100%; background:${e.completionRate >= 70 ? 'var(--color-success)' : e.completionRate >= 40 ? 'var(--color-warning)' : 'var(--color-danger)'}; border-radius:999px; transition:width 0.8s ease;"></div>
                    </div>
                    <span style="font-size:0.8rem; min-width:38px;">${e.completionRate}%</span>
                </div>
            </td>
            <td><span style="font-weight:700; font-size:1rem;">${e.score}</span><span style="color:var(--color-text-secondary); font-size:0.75rem;">/100</span></td>
            <td><span class="status-badge ${cls}">${label}</span></td>
        </tr>`;
    }).join('');

    document.getElementById('perfReportBody').innerHTML = `
        <div style="overflow-x:auto;">
            <table class="data-table">
                <thead>
                    <tr>
                        <th>Employee</th>
                        <th>${t('ui_role')}</th>
                        <th>${t('ui_total_tasks')}</th>
                        <th>${t('ui_completed')}</th>
                        <th>${t('ui_overdue')}</th>
                        <th style="min-width:160px;">${t('ui_completion_rate')}</th>
                        <th>${t('ui_score')}</th>
                        <th>${t('ui_rating')}</th>
                    </tr>
                </thead>
                <tbody>${rows}</tbody>
            </table>
        </div>
        <p style="font-size:0.75rem; color:var(--color-text-secondary); margin-top:1rem; padding-top:0.5rem; border-top:1px solid var(--color-border);">
            <i data-lucide="info" style="width:13px;height:13px;vertical-align:middle;margin-right:4px;"></i>
            ${taskDetailText('Score = Completion Rate − (Overdue Tasks × 5 penalty points). Clamped between 0 and 100.', 'النتيجة = معدل الإنجاز − (المهام المتأخرة × 5 نقاط جزائية). وتكون النتيجة بين 0 و100.')}
        </p>`;

    document.getElementById('perfReportDate').textContent = `Generated: ${new Date().toLocaleString()}`;
    document.getElementById('perfReportSection').style.display = 'block';

    if (btn) { btn.disabled = false; btn.innerHTML = '<i data-lucide="refresh-cw"></i> Regenerate Report'; }
    if (window.lucide) window.lucide.createIcons();

    // Smooth scroll to report
    document.getElementById('perfReportSection').scrollIntoView({ behavior: 'smooth', block: 'start' });
};

window.printPerformanceReport = () => {
    const reportBody = document.getElementById('perfReportBody');
    if (!reportBody) return;

    // Clone the node to clean it up for print without affecting the DOM
    const printNode = reportBody.cloneNode(true);

    // Remove lucide icons for cleaner print, or we can just rely on the print CSS to handle it
    const printContents = `
        <h2 style="color: #0000FF; margin-top: 0; text-align: center;">${t('ui_employee_performance_report')}</h2>
        <p style="text-align: center; color: #666; margin-bottom: 30px;">
            <small>Generated: ${new Date().toLocaleString()}</small>
        </p>
        ${printNode.innerHTML}
        <br>
        <p style="text-align: right; margin-top: 40px;"><small style="color: #666;">Printed on ${new Date().toLocaleString()}</small></p>
    `;

    window.printWithLetterhead(t('ui_employee_performance_report') || 'Employee Performance Report', printContents);
};

// Add spin keyframe if not already present
if (!document.getElementById('perfSpinStyle')) {
    const s = document.createElement('style');
    s.id = 'perfSpinStyle';
    s.textContent = '@keyframes spin { to { transform: rotate(360deg); } }';
    document.head.appendChild(s);
}

// Render Documents
window.handleDocSubmit = async function (e) {
    e.preventDefault();
    const type = document.getElementById('docType').value;
    const purpose = document.getElementById('docPurpose').value;
    const { success } = await db.requestDocument(currentUser.id, type, purpose);
    if (success) {
        showToast(t('toast_document_requested'), "success");
        renderView('requests');
    }
}

const EMPLOYEE_DOCUMENT_MAX_FILE_SIZE = 5 * 1024 * 1024;
const EMPLOYEE_DOCUMENT_ALLOWED_FILE_TYPES = new Set([
    'application/pdf',
    'image/jpeg',
    'image/png'
]);

function getEmployeeDocumentFileValidationError(file) {
    if (!file) return 'toast_document_file_required';
    if (file.size > EMPLOYEE_DOCUMENT_MAX_FILE_SIZE) return 'toast_document_file_too_large';

    const hasAllowedType = EMPLOYEE_DOCUMENT_ALLOWED_FILE_TYPES.has(file.type);
    const hasAllowedExtension = /\.(pdf|png|jpe?g)$/i.test(file.name || '');
    const hasConflictingType = file.type && file.type !== 'application/octet-stream' && !hasAllowedType;
    if (!hasAllowedExtension || hasConflictingType) return 'toast_document_file_type_invalid';
    return null;
}

function getEmployeeDocumentFileType(file) {
    if (EMPLOYEE_DOCUMENT_ALLOWED_FILE_TYPES.has(file.type)) return file.type;
    if (/\.pdf$/i.test(file.name || '')) return 'application/pdf';
    if (/\.png$/i.test(file.name || '')) return 'image/png';
    return 'image/jpeg';
}

function readEmployeeDocumentFile(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = event => resolve(event.target.result);
        reader.onerror = () => reject(reader.error || new Error('Unable to read the selected file'));
        reader.readAsDataURL(file);
    });
}

window.openEmployeeDocumentFilePicker = function () {
    document.getElementById('empDocFile')?.click();
};

window.updateEmployeeDocumentFileName = function (event) {
    const fileInput = event.target;
    const fileNameElement = document.getElementById('empDocFileName');
    const files = Array.from(fileInput.files || []);

    // Validate each file
    for (const file of files) {
        const validationError = getEmployeeDocumentFileValidationError(file);
        if (validationError) {
            fileInput.value = '';
            if (fileNameElement) fileNameElement.textContent = t('doc_no_file_selected');
            showToast(t(validationError), 'warning');
            return;
        }
    }

    if (fileNameElement) {
        if (files.length === 0) {
            fileNameElement.textContent = t('doc_no_file_selected');
        } else if (files.length === 1) {
            fileNameElement.textContent = files[0].name;
        } else {
            fileNameElement.textContent = `${files.length} files selected`;
        }
    }
};

window.handleEmployeeDocSave = async function (e) {
    e.preventDefault();
    const fileInput = document.getElementById('empDocFile');
    const files = Array.from(fileInput?.files || []);

    if (files.length === 0) {
        showToast(t('toast_error_saving_document'), 'warning');
        return;
    }

    for (const file of files) {
        const validationError = getEmployeeDocumentFileValidationError(file);
        if (validationError) {
            showToast(t(validationError), 'warning');
            return;
        }
    }

    const saveButton = document.getElementById('empDocSaveButton');
    const uploadButton = document.getElementById('empDocUploadButton');
    if (saveButton) saveButton.disabled = true;
    if (uploadButton) uploadButton.disabled = true;

    try {
        let successCount = 0;
        for (const file of files) {
            const fileType = getEmployeeDocumentFileType(file);
            const rawFileBase64 = await readEmployeeDocumentFile(file);
            const fileBase64 = String(rawFileBase64).replace(/^data:[^;]*;/, `data:${fileType};`);

            // If multiple files, append original filename to documentName to differentiate
            const baseDocName = document.getElementById('empDocName').value.trim();
            const documentName = files.length > 1 ? `${baseDocName} (${file.name})` : baseDocName;

            const documentRecord = {
                documentName,
                ownerName: document.getElementById('empOwnerName').value.trim(),
                ownerEmail: document.getElementById('empOwnerEmail').value.trim(),
                responsibleName: document.getElementById('empResponsibleName').value.trim(),
                responsibleEmail: document.getElementById('empResponsibleEmail').value.trim(),
                expirationDate: document.getElementById('empExpiryDate').value,
                ownerPhone: document.getElementById('empOwnerPhone').value.trim(),
                fileType,
                fileBase64,
                notified30Days: true
            };

            const uploadResult = await db.uploadEmployeeDocument(currentUser.id, documentRecord);
            if (!uploadResult.success) {
                throw uploadResult.error || new Error(t('toast_error_saving_document'));
            }
            const expiryInfo = getDocumentExpiryInfo(documentRecord.expirationDate);
            if (expiryInfo.daysLeft !== null && expiryInfo.daysLeft <= 30) {
                const notificationResult = await db.notifyEmployeeDocumentExpiry(uploadResult.data.id);
                if (notificationResult.success && (notificationResult.data?.failures || 0) === 0) {
                    showToast(t('toast_document_expiry_notification_sent'), "success");
                } else {
                    showToast(t('toast_document_expiry_notification_failed'), "warning");
                }
            }

            successCount++;
        }

        showToast(`${successCount} document(s) saved successfully.`, "success");

        renderView('documents');
    } catch (error) {
        console.error('handleEmployeeDocSave Error:', error);
        showToast(error?.message || t('toast_error_saving_document'), 'danger');
    } finally {
        if (saveButton?.isConnected) saveButton.disabled = false;
        if (uploadButton?.isConnected) uploadButton.disabled = false;
    }
}

// Backward-compatible entry point for older cached markup.
window.handleEmployeeDocUpload = window.handleEmployeeDocSave;

function getDocumentExpiryInfo(expirationDate) {
    if (!expirationDate) return { daysLeft: null, status: '', statusClass: 'info' };

    const [year, month, day] = expirationDate.split('-').map(Number);
    const now = new Date();
    const todayUtc = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
    const expiryUtc = Date.UTC(year, month - 1, day);
    const daysLeft = Math.ceil((expiryUtc - todayUtc) / 86400000);

    if (daysLeft <= 0) {
        return { daysLeft, status: t('doc_status_expired'), statusClass: 'danger' };
    }
    if (daysLeft <= 30) {
        return { daysLeft, status: t('doc_status_expiring_soon'), statusClass: 'warning' };
    }
    return { daysLeft, status: t('doc_status_active'), statusClass: 'success' };
}

window.updateDocumentExpiryPreview = function () {
    const expiryInput = document.getElementById('empExpiryDate');
    const daysLeftInput = document.getElementById('empDaysLeft');
    const statusInput = document.getElementById('empStatus');
    if (!expiryInput || !daysLeftInput || !statusInput) return;

    const expiryInfo = getDocumentExpiryInfo(expiryInput.value);
    daysLeftInput.value = expiryInfo.daysLeft === null ? '' : expiryInfo.daysLeft;
    statusInput.value = expiryInfo.status;
};

function getEmployeeDocumentRecord(documentId) {
    return (window.currentEmployeeDocuments || []).find(documentRecord => documentRecord.id === documentId) || null;
}

function canManageEmployeeDocument(documentRecord) {
    if (!documentRecord || !currentUser) return false;
    if (currentUserRole === 'ADMIN') return true;
    if (documentRecord.employee_id === currentUser.id) return true;
    return currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR';
}

window.updateEmployeeDocumentModalExpiryPreview = () => {
    const expiryDate = document.getElementById('employeeDocumentExpiryDate')?.value;
    const expiryInfo = getDocumentExpiryInfo(expiryDate);
    document.getElementById('employeeDocumentDaysLeft').value = expiryInfo.daysLeft === null ? '' : expiryInfo.daysLeft;
    document.getElementById('employeeDocumentStatus').value = expiryInfo.status;
};

function openEmployeeDocumentModal(documentId, editMode) {
    const documentRecord = getEmployeeDocumentRecord(documentId);
    if (!documentRecord) {
        showToast(t('doc_not_found'), 'danger');
        return;
    }
    if (editMode && !canManageEmployeeDocument(documentRecord)) {
        showToast(t('doc_action_not_allowed'), 'danger');
        return;
    }

    const modal = document.getElementById('employeeDocumentModal');
    const editableInputIds = [
        'employeeDocumentName',
        'employeeDocumentOwnerName',
        'employeeDocumentOwnerEmail',
        'employeeDocumentResponsibleName',
        'employeeDocumentResponsibleEmail',
        'employeeDocumentExpiryDate',
        'employeeDocumentOwnerPhone'
    ];

    document.getElementById('employeeDocumentRecordId').value = documentRecord.id;
    document.getElementById('employeeDocumentDisplayId').value = documentRecord.document_id || '';
    document.getElementById('employeeDocumentName').value = documentRecord.doc_name || '';
    document.getElementById('employeeDocumentOwnerName').value = documentRecord.owner_name || '';
    document.getElementById('employeeDocumentOwnerEmail').value = documentRecord.owner_email || '';
    document.getElementById('employeeDocumentResponsibleName').value = documentRecord.responsible_name || '';
    document.getElementById('employeeDocumentResponsibleEmail').value = documentRecord.responsible_email || '';
    document.getElementById('employeeDocumentExpiryDate').value = documentRecord.expiration_date || '';
    document.getElementById('employeeDocumentNotified').value = t('doc_yes');
    document.getElementById('employeeDocumentOwnerPhone').value = documentRecord.owner_phone || '';
    window.updateEmployeeDocumentModalExpiryPreview();

    editableInputIds.forEach(inputId => {
        document.getElementById(inputId).readOnly = !editMode;
    });
    document.getElementById('employeeDocumentModalTitle').textContent = editMode ? t('doc_edit_title') : t('doc_view_title');
    document.getElementById('employeeDocumentSaveButton').style.display = editMode ? '' : 'none';
    const legacyFileButton = document.getElementById('employeeDocumentLegacyFileButton');
    legacyFileButton.style.display = '';
    modal.classList.add('show');
    if (window.lucide) window.lucide.createIcons();
}

window.viewEmployeeDocument = documentId => openEmployeeDocumentModal(documentId, false);
window.editEmployeeDocument = documentId => openEmployeeDocumentModal(documentId, true);

window.closeEmployeeDocumentModal = () => {
    const modal = document.getElementById('employeeDocumentModal');
    if (modal) modal.classList.remove('show');
};

window.openLegacyEmployeeDocumentFile = async () => {
    const documentId = document.getElementById('employeeDocumentRecordId').value;
    const documentRecord = getEmployeeDocumentRecord(documentId);
    if (!documentRecord) {
        showToast(t('doc_not_found'), 'danger');
        return;
    }

    const fileWindow = window.open('', '_blank');
    if (!fileWindow) {
        showToast(t('doc_popup_blocked'), 'warning');
        return;
    }
    fileWindow.opener = null;

    const result = await db.fetchEmployeeDocumentFile(documentId);
    const dataUrl = result.data?.doc_base64;
    if (!result.success || !dataUrl) {
        fileWindow.close();
        showToast(t('doc_no_stored_file'), 'warning');
        return;
    }

    try {
        const match = String(dataUrl).match(/^data:([^;,]+);base64,([a-z0-9+/=]+)$/i);
        const allowedStoredTypes = new Set([
            'application/pdf',
            'image/jpeg',
            'image/png',
            'image/gif',
            'image/webp'
        ]);
        if (!match || !allowedStoredTypes.has(match[1].toLowerCase())) {
            throw new Error('Unsupported stored file type');
        }

        const binary = atob(match[2]);
        const bytes = new Uint8Array(binary.length);
        for (let index = 0; index < binary.length; index += 1) {
            bytes[index] = binary.charCodeAt(index);
        }
        const fileUrl = URL.createObjectURL(new Blob([bytes], { type: match[1] }));
        fileWindow.location.replace(fileUrl);
        setTimeout(() => URL.revokeObjectURL(fileUrl), 60000);
    } catch (error) {
        fileWindow.close();
        console.error('openLegacyEmployeeDocumentFile Error:', error);
        showToast(t('doc_no_stored_file'), 'warning');
    }
};

window.handleEmployeeDocumentEdit = async event => {
    event.preventDefault();
    const documentId = document.getElementById('employeeDocumentRecordId').value;
    const currentRecord = getEmployeeDocumentRecord(documentId);
    if (!canManageEmployeeDocument(currentRecord)) {
        showToast(t('doc_action_not_allowed'), 'danger');
        return;
    }

    const documentRecord = {
        documentName: document.getElementById('employeeDocumentName').value.trim(),
        ownerName: document.getElementById('employeeDocumentOwnerName').value.trim(),
        ownerEmail: document.getElementById('employeeDocumentOwnerEmail').value.trim(),
        responsibleName: document.getElementById('employeeDocumentResponsibleName').value.trim(),
        responsibleEmail: document.getElementById('employeeDocumentResponsibleEmail').value.trim(),
        expirationDate: document.getElementById('employeeDocumentExpiryDate').value,
        ownerPhone: document.getElementById('employeeDocumentOwnerPhone').value.trim()
    };

    const saveButton = document.getElementById('employeeDocumentSaveButton');
    saveButton.disabled = true;
    try {
        const result = await db.updateEmployeeDocument(documentId, documentRecord);
        if (!result.success) throw result.error || new Error(t('doc_update_failed'));
        window.closeEmployeeDocumentModal();
        showToast(t('doc_update_success'), 'success');
        renderView('documents');
    } catch (error) {
        showToast(error?.message || t('doc_update_failed'), 'danger');
    } finally {
        saveButton.disabled = false;
    }
};

window.deleteEmployeeDocument = documentId => {
    const documentRecord = getEmployeeDocumentRecord(documentId);
    if (!canManageEmployeeDocument(documentRecord)) {
        showToast(t('doc_action_not_allowed'), 'danger');
        return;
    }

    window.showConfirmModal(t('doc_delete_title'), t('doc_delete_confirm'), async () => {
        const result = await db.deleteEmployeeDocument(documentId);
        if (result.success) {
            showToast(t('doc_delete_success'), 'success');
            renderView('documents');
        } else {
            showToast(result.error?.message || t('doc_delete_failed'), 'danger');
        }
    });
};

window.printEmployeeDocument = documentId => {
    const documentRecord = getEmployeeDocumentRecord(documentId);
    if (!documentRecord) {
        showToast(t('doc_not_found'), 'danger');
        return;
    }

    const expiryInfo = getDocumentExpiryInfo(documentRecord.expiration_date);
    const expirationDate = documentRecord.expiration_date
        ? new Date(`${documentRecord.expiration_date}T00:00:00`).toLocaleDateString()
        : '-';
    const rows = [
        [t('doc_document_id'), documentRecord.document_id || '-'],
        [t('doc_document_name'), documentRecord.doc_name || '-'],
        [t('doc_owner_name'), documentRecord.owner_name || '-'],
        [t('doc_owner_email'), documentRecord.owner_email || '-'],
        [t('doc_responsible_name'), documentRecord.responsible_name || '-'],
        [t('doc_responsible_email'), documentRecord.responsible_email || '-'],
        [t('doc_expiry_date'), expirationDate],
        [t('doc_days_left'), expiryInfo.daysLeft === null ? '-' : expiryInfo.daysLeft],
        [t('status'), expiryInfo.status || '-'],
        [t('doc_owner_phone'), documentRecord.owner_phone || '-']
    ];
    const printContent = `
        <h2 style="margin:0 0 24px;">${escapeHTML(t('doc_print_title'))}</h2>
        <table><tbody>${rows.map(([label, value]) => `<tr><th style="width:35%;">${escapeHTML(String(label))}</th><td>${escapeHTML(String(value))}</td></tr>`).join('')}</tbody></table>
    `;
    window.printWithLetterhead(escapeHTML(documentRecord.doc_name || t('doc_print_title')), printContent);
};

function renderEmployeeDocumentRow(documentRecord) {
    const expiryInfo = getDocumentExpiryInfo(documentRecord.expiration_date);
    const expirationDate = documentRecord.expiration_date
        ? new Date(`${documentRecord.expiration_date}T00:00:00`).toLocaleDateString()
        : '-';

    return `
        <tr>
            <td data-label="${escapeHTML(t('doc_document_id'))}">${escapeHTML(String(documentRecord.document_id || '-'))}</td>
            <td data-label="${escapeHTML(t('doc_document_name'))}">${escapeHTML(documentRecord.doc_name || '-')}</td>
            <td data-label="${escapeHTML(t('doc_owner_name'))}">${escapeHTML(documentRecord.owner_name || '-')}</td>
            <td data-label="${escapeHTML(t('doc_owner_email'))}" class="document-email-cell">${escapeHTML(documentRecord.owner_email || '-')}</td>
            <td data-label="${escapeHTML(t('doc_responsible_name'))}">${escapeHTML(documentRecord.responsible_name || '-')}</td>
            <td data-label="${escapeHTML(t('doc_responsible_email'))}" class="document-email-cell">${escapeHTML(documentRecord.responsible_email || '-')}</td>
            <td data-label="${escapeHTML(t('doc_expiry_date'))}">${expirationDate}</td>
            <td data-label="${escapeHTML(t('doc_days_left'))}">${expiryInfo.daysLeft === null ? '-' : expiryInfo.daysLeft}</td>
            <td data-label="${escapeHTML(t('status'))}"><span class="status-badge ${expiryInfo.statusClass}">${escapeHTML(expiryInfo.status || '-')}</span></td>
            <td data-label="${escapeHTML(t('doc_owner_phone'))}">${escapeHTML(documentRecord.owner_phone || '-')}</td>
            <td data-label="${escapeHTML(t('ui_actions'))}" class="employee-document-actions">
                <div class="employee-document-action-buttons">
                    <button type="button" class="btn-secondary" style="padding:0.4rem;" onclick="viewEmployeeDocument('${escapeHTML(documentRecord.id)}')" title="${t('doc_action_view')}" aria-label="${t('doc_action_view')}"><i data-lucide="eye" style="width:14px;height:14px;"></i></button>
                    <button type="button" class="btn-secondary" style="padding:0.4rem;" onclick="editEmployeeDocument('${escapeHTML(documentRecord.id)}')" title="${t('doc_action_edit')}" aria-label="${t('doc_action_edit')}"><i data-lucide="edit-2" style="width:14px;height:14px;"></i></button>
                    <button type="button" class="btn-secondary" style="padding:0.4rem;" onclick="printEmployeeDocument('${escapeHTML(documentRecord.id)}')" title="${t('doc_action_print')}" aria-label="${t('doc_action_print')}"><i data-lucide="printer" style="width:14px;height:14px;"></i></button>
                    <button type="button" class="btn-secondary" style="padding:0.4rem; color:var(--color-danger);" onclick="deleteEmployeeDocument('${escapeHTML(documentRecord.id)}')" title="${t('doc_action_delete')}" aria-label="${t('doc_action_delete')}"><i data-lucide="trash-2" style="width:14px;height:14px;"></i></button>
                </div>
            </td>
        </tr>
    `;
}

async function renderDocuments() {
    const isManagerOrAdmin = currentUserRole === 'ADMIN' || (currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR';
    let docs = await db.fetchDocuments(isManagerOrAdmin ? null : currentUser.id);
    let uploadedDocs = await db.fetchEmployeeDocuments(isManagerOrAdmin ? null : currentUser.id);

    if (isManagerOrAdmin && currentUserRole !== 'ADMIN') {
        const users = await db.fetchUsers();
        const teamIds = users.filter(u => u.manager_id === currentUser.id).map(u => u.id);
        teamIds.push(currentUser.id);
        docs = docs.filter(d => teamIds.includes(d.employee_id));
        uploadedDocs = uploadedDocs.filter(d => teamIds.includes(d.employee_id));
    }

    window.currentEmployeeDocuments = uploadedDocs;

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('nav_documents')}</h1>
                <p class="page-subtitle">${t('doc_sub')}</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-12 document-upload-launcher">
                <button type="button" class="btn-primary" onclick="document.getElementById('employeeDocumentUploadModal').classList.add('active')"><i data-lucide="plus"></i> ${t('doc_add_new') || 'Add New'}</button>
            </div>
            <!-- Upload Official Document -->
            <div class="modal" id="employeeDocumentUploadModal">
              <div class="modal-content document-upload-modal-content">
                <button type="button" class="icon-btn modal-close-btn" aria-label="Close" onclick="document.getElementById('employeeDocumentUploadModal').classList.remove('active')"><i data-lucide="x"></i></button>
                <div class="card-title">${t('doc_upload_title')}</div>
                <form autocomplete="off" onsubmit="handleEmployeeDocSave(event)">
                    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1rem;">
                        <div class="form-group">
                            <label class="form-label">${t('doc_document_id')}</label>
                            <input type="text" class="form-control" value="${t('doc_auto_generated')}" readonly>
                        </div>
                        <div class="form-group">
                            <label class="form-label">${t('doc_document_name')}</label>
                            <input type="text" id="empDocName" class="form-control" required>
                        </div>
                        <div class="form-group">
                            <label class="form-label">${t('doc_owner_name')}</label>
                            <input type="text" id="empOwnerName" class="form-control" required>
                        </div>
                        <div class="form-group">
                            <label class="form-label">${t('doc_owner_email')}</label>
                            <input type="email" id="empOwnerEmail" class="form-control" required>
                        </div>
                        <div class="form-group">
                            <label class="form-label">${t('doc_responsible_name')}</label>
                            <input type="text" id="empResponsibleName" class="form-control" required>
                        </div>
                        <div class="form-group">
                            <label class="form-label">${t('doc_responsible_email')}</label>
                            <input type="email" id="empResponsibleEmail" class="form-control" required>
                        </div>
                        <div class="form-group">
                            <label class="form-label">${t('doc_expiry_date')}</label>
                            <input type="date" id="empExpiryDate" class="form-control" oninput="updateDocumentExpiryPreview()" required>
                        </div>
                        <div class="form-group">
                            <label class="form-label">${t('doc_days_left')}</label>
                            <input type="number" id="empDaysLeft" class="form-control" readonly>
                        </div>
                        <div class="form-group">
                            <label class="form-label">${t('status')}</label>
                            <input type="text" id="empStatus" class="form-control" readonly>
                        </div>
                        <div class="form-group">
                            <label class="form-label">${t('doc_notified_30_days')}</label>
                            <input type="text" class="form-control" value="${t('doc_yes')}" readonly>
                        </div>
                        <div class="form-group">
                            <label class="form-label">${t('doc_owner_phone')}</label>
                            <input type="tel" id="empOwnerPhone" class="form-control" required>
                        </div>
                        <div class="form-group" style="grid-column: 1 / -1;">
                            <label class="form-label">${t('doc_file')}</label>
                            <input type="file" id="empDocFile" accept="application/pdf,image/png,image/jpeg" onchange="updateEmployeeDocumentFileName(event)" style="display: none;" multiple>
                            <div style="display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap;">
                                <button type="button" id="empDocUploadButton" class="btn-secondary" onclick="openEmployeeDocumentFilePicker()">
                                    <i data-lucide="upload"></i> ${t('doc_upload_btn')}
                                </button>
                                <span id="empDocFileName" aria-live="polite" style="color: var(--color-text-secondary);">${t('doc_no_file_selected')}</span>
                            </div>
                            <small style="display: block; margin-top: 0.5rem; color: var(--color-text-secondary);">${t('doc_file_help')}</small>
                        </div>
                    </div>
                    <button type="submit" id="empDocSaveButton" class="btn-primary" style="margin-top: 0.5rem;">
                        <i data-lucide="save"></i> ${t('doc_save_btn')}
                    </button>
                </form>
              </div>
            </div>
            

            <div class="card col-span-12">
                <div class="card-title">${currentUserRole === 'ADMIN' ? t('doc_all_uploaded') : t('doc_my_uploaded')}</div>
                <div class="table-responsive employee-documents-table-wrap">
                    <table class="data-table employee-documents-table">
                        <thead><tr><th>${t('doc_document_id')}</th><th>${t('doc_document_name')}</th><th>${t('doc_owner_name')}</th><th>${t('doc_owner_email')}</th><th>${t('doc_responsible_name')}</th><th>${t('doc_responsible_email')}</th><th>${t('doc_expiry_date')}</th><th>${t('doc_days_left')}</th><th>${t('status')}</th><th>${t('doc_owner_phone')}</th><th>${t('ui_actions')}</th></tr></thead>
                        <tbody>
                            ${uploadedDocs.length === 0 ? `<tr class="employee-documents-empty"><td colspan="11" style="text-align: center; color: var(--color-text-secondary); padding: 1rem;">${t('doc_no_uploaded')}</td></tr>` : uploadedDocs.map(renderEmployeeDocumentRow).join('')}
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- Removed HR Letter Requests (moved to Employee Requests page) -->
        </div>
    `;
}

// ==========================================
// Schedule & Reminders
// ==========================================

async function renderSchedule() {
    const reminders = await db.fetchReminders(currentUser.id);

    // Sort reminders: pending first, then by date.
    const sortedReminders = reminders.sort((a, b) => {
        if (a.status === 'pending' && b.status !== 'pending') return -1;
        if (a.status !== 'pending' && b.status === 'pending') return 1;
        return new Date(a.due_date) - new Date(b.due_date);
    });

    const reminderItems = sortedReminders.length === 0
        ? `<div style="text-align:center; padding: 2rem; color: var(--color-text-secondary);">${t('notif_no_found') || 'No reminders yet.'}</div>`
        : sortedReminders.map(r => {
            const isCompleted = r.status === 'completed';
            const dueDate = new Date(r.due_date);

            // Build Google Calendar Add Link
            const gcalStart = dueDate.toISOString().replace(/-|:|\.\d\d\d/g, "");
            // Assuming 1 hour duration
            const endDate = new Date(dueDate.getTime() + 60 * 60 * 1000);
            const gcalEnd = endDate.toISOString().replace(/-|:|\.\d\d\d/g, "");

            const gcalUrl = `https://calendar.google.com/calendar/render?action=TEMPLATE&text=${encodeURIComponent(r.title)}&details=${encodeURIComponent(r.description || '')}&dates=${gcalStart}/${gcalEnd}`;

            return `
            <div class="card fade-in-up reminder-card ${isCompleted ? 'completed' : ''}">
                <div>
                    <h3 style="margin-bottom: 0.25rem; ${isCompleted ? 'text-decoration: line-through;' : ''}">${escapeHTML(r.title)}</h3>
                    <p style="font-size: 0.85rem; color: var(--color-text-secondary); margin-bottom: 0.5rem;">${escapeHTML(r.description || '')}</p>
                    <div style="font-size: 0.8rem; color: var(--color-text-secondary);">
                        <i data-lucide="calendar" style="width:14px; height:14px; vertical-align:middle;"></i> ${dueDate.toLocaleString()}
                        ${r.recurrence_type && r.recurrence_type !== 'NONE' ? `<span class="reminder-repeat-badge"><i data-lucide="repeat"></i>${t('schedule_repeat_' + r.recurrence_type.toLowerCase())}${r.recurrence_type === 'CUSTOM' ? ` (${r.recurrence_interval} ${t('schedule_days')})` : ''}</span>` : ''}
                    </div>
                </div>
                <div class="reminder-actions">
                    ${!isCompleted ? `<button class="btn btn-secondary btn-icon" title="${t('schedule_mark_completed')}" onclick="window.toggleReminderStatus('${r.id}', 'completed')"><i data-lucide="check"></i></button>` : `<button class="btn btn-secondary btn-icon" title="${t('schedule_mark_pending')}" onclick="window.toggleReminderStatus('${r.id}', 'pending')"><i data-lucide="rotate-ccw"></i></button>`}
                    <a href="${gcalUrl}" target="_blank" rel="noopener" class="btn btn-secondary" title="${t('schedule_add_google')}" style="color:var(--color-text);"><i data-lucide="calendar-plus"></i><span>${t('schedule_add_google')}</span></a>
                    <button class="btn btn-secondary btn-icon" style="color:var(--color-danger);" title="${t('schedule_delete')}" onclick="window.deleteReminder('${r.id}')"><i data-lucide="trash-2"></i></button>
                </div>
            </div>`;
        }).join('');

    return `
        <div class="page-header">
            <div><h1 class="page-title">${t('schedule_title')}</h1><p class="page-subtitle">${t('schedule_subtitle')}</p></div>
            <div class="schedule-header-actions"><button class="btn btn-secondary" onclick="window.enablePushNotifications()"><i data-lucide="bell-ring"></i> ${t('schedule_enable_notifications')}</button><button class="btn btn-primary" onclick="window.showReminderModal()"><i data-lucide="plus"></i> ${t('schedule_add_reminder')}</button></div>
        </div>
        <div class="schedule-google-note"><i data-lucide="info"></i><span>${t('schedule_google_note')}</span></div>
        <div class="card" style="padding: 0; background: transparent; box-shadow: none;">
            ${reminderItems}
        </div>
        
        <!-- Add Reminder Modal -->
        <div class="modal" id="reminderModal">
            <div class="modal-content" style="max-width: 500px;">
                <div class="modal-header">
                    <h2>${t('schedule_new_reminder')}</h2>
                    <button class="btn btn-icon" onclick="document.getElementById('reminderModal').classList.remove('show')"><i data-lucide="x"></i></button>
                </div>
                <form onsubmit="window.handleCreateReminder(event)">
                    <div class="form-group">
                        <label class="form-label">${t('schedule_title_label')} *</label>
                        <input type="text" id="reminderTitle" class="form-control" required placeholder="${t('schedule_title_placeholder')}">
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('schedule_description_label')}</label>
                        <textarea id="reminderDescription" class="form-control" rows="3" placeholder="${t('schedule_description_placeholder')}"></textarea>
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('schedule_due_label')} *</label>
                        <input type="datetime-local" id="reminderDueDate" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('schedule_repeat')}</label>
                        <select id="reminderRecurrence" class="form-control" onchange="window.handleReminderRecurrenceChange()">
                            <option value="NONE">${t('schedule_repeat_none')}</option>
                            <option value="DAILY">${t('schedule_repeat_daily')}</option>
                            <option value="WEEKLY">${t('schedule_repeat_weekly')}</option>
                            <option value="MONTHLY">${t('schedule_repeat_monthly')}</option>
                            <option value="CUSTOM">${t('schedule_repeat_custom')}</option>
                        </select>
                    </div>
                    <div class="form-group" id="reminderCustomIntervalGroup" hidden>
                        <label class="form-label">${t('schedule_repeat_every_days')}</label>
                        <input type="number" id="reminderCustomInterval" class="form-control" min="1" max="365" value="2">
                    </div>
                    <button type="submit" class="btn btn-primary" style="width: 100%;">${t('schedule_create')}</button>
                </form>
            </div>
        </div>
    `;
}

window.showReminderModal = () => {
    document.getElementById('reminderTitle').value = '';
    document.getElementById('reminderDescription').value = '';
    document.getElementById('reminderDueDate').value = '';
    document.getElementById('reminderRecurrence').value = 'NONE';
    document.getElementById('reminderCustomInterval').value = '2';
    document.getElementById('reminderCustomIntervalGroup').hidden = true;
    document.getElementById('reminderModal').classList.add('show');
};

window.handleReminderRecurrenceChange = () => {
    document.getElementById('reminderCustomIntervalGroup').hidden = document.getElementById('reminderRecurrence').value !== 'CUSTOM';
};

function urlBase64ToUint8Array(value) {
    const padding = '='.repeat((4 - value.length % 4) % 4);
    const base64 = (value + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(base64);
    return Uint8Array.from([...raw].map(character => character.charCodeAt(0)));
}

window.enablePushNotifications = async () => {
    if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
        return showToast(t('schedule_push_unsupported'), 'warning');
    }
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') return showToast(t('schedule_push_denied'), 'warning');
    const keyResult = await db.getPushPublicKey();
    if (!keyResult.success) return showToast(keyResult.error?.message || t('schedule_push_not_configured'), 'danger');
    try {
        const registration = await navigator.serviceWorker.ready;
        let subscription = await registration.pushManager.getSubscription();
        if (!subscription) {
            subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlBase64ToUint8Array(keyResult.publicKey) });
        }
        const saved = await db.savePushSubscription(currentUser.id, subscription);
        if (!saved.success) throw saved.error;
        showToast(t('schedule_push_enabled'), 'success');
    } catch (error) {
        showToast(error?.message || t('schedule_push_failed'), 'danger');
    }
};

window.handleCreateReminder = async (e) => {
    e.preventDefault();
    const title = document.getElementById('reminderTitle').value.trim();
    const description = document.getElementById('reminderDescription').value.trim();
    const dueDate = document.getElementById('reminderDueDate').value;

    if (!title || !dueDate) {
        showToast(window.t('msg_toast_26') || 'Please fill in all required fields.', 'danger');
        return;
    }

    const { success, error } = await db.createReminder({
        user_id: currentUser.id,
        title,
        description,
        due_date: new Date(dueDate).toISOString(),
        status: 'pending',
        recurrence_type: document.getElementById('reminderRecurrence').value,
        recurrence_interval: document.getElementById('reminderRecurrence').value === 'CUSTOM'
            ? Math.max(1, parseInt(document.getElementById('reminderCustomInterval').value, 10) || 1)
            : 1
    });

    if (success) {
        showToast(window.t('msg_toast_27') || 'Reminder created!', 'success');
        document.getElementById('reminderModal').classList.remove('show');
        renderView('schedule');
    } else {
        showToast(error?.message || 'Error creating reminder.', 'danger');
    }
};

window.toggleReminderStatus = async (id, status) => {
    const { success, error } = await db.updateReminderStatus(id, status);
    if (success) {
        renderView('schedule');
    } else {
        showToast(error?.message || 'Error updating reminder.', 'danger');
    }
};

window.deleteReminder = async (id) => {
    window.showConfirmModal(t('html_confirm_action'), t('html_are_you_sure') || 'Are you sure you want to delete this reminder?', async () => {
        const { success, error } = await db.deleteReminder(id);
        if (success) renderView('schedule');
        else showToast(error?.message || 'Error deleting reminder.', 'danger');
    });
};

async function renderProfile() {
    const profile = await db.getUserProfile(currentUser.id);
    const [ownContracts, ownPrintRequests] = await Promise.all([
        db.fetchContracts(currentUser.id),
        db.fetchContractPrintRequests({ employeeId: currentUser.id })
    ]);
    const ownContract = (ownContracts || []).find(contract => contract.status === 'Active') || ownContracts?.[0] || null;
    const latestPrintRequest = ownContract ? ownPrintRequests.find(request => request.contract_id === ownContract.id) : null;
    const displayName = getProfileDisplayName(profile);
    const userAvatar = profile.avatar_url || localStorage.getItem('user_avatar_' + currentUser.id);
    const avatar = userAvatar || `https://ui-avatars.com/api/?name=${encodeURIComponent(displayName)}&background=007AFF&color=fff`;
    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('nav_profile')}</h1>
                <p class="page-subtitle">${t('prof_sub')}</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <!-- Profile Photo & Summary -->
            <div class="card col-span-4" style="text-align: center;">
                <div style="position: relative; display: inline-block;">
                    <img src="${avatar}" style="width: 140px; height: 140px; border-radius: 50%; object-fit: cover; margin-bottom: 1rem; border: 4px solid var(--color-background); box-shadow: 0 4px 12px rgba(0,0,0,0.1);" />
                </div>
                <h3 style="font-size: 1.25rem; font-weight: 600; margin-bottom: 0.25rem;">${escapeHTML(displayName)}</h3>
                <p style="color: var(--color-primary); font-weight: 500; margin-bottom: 1.5rem;">${t(`role_${String(currentUserRole || 'employee').toLowerCase()}`) || currentUserRole}</p>
                <form autocomplete="off" onsubmit="handleUpdateProfilePhoto(event)" style="margin-bottom: 1rem; padding-top: 1rem; border-top: 1px solid var(--color-border);">
                    <div class="form-group" style="text-align: left;">
                        <label class="form-label" style="font-size: 0.85rem;">${t('prof_update_pic')}</label>
                        <input type="file" id="avatarFile" accept="image/*" style="display: none;" required onchange="document.getElementById('avatarFileName').textContent=this.files?.[0]?.name || t('prof_no_file_selected')">
                        <label for="avatarFile" class="profile-file-picker"><i data-lucide="image-plus"></i><span>${t('prof_choose_photo')}</span></label>
                        <small id="avatarFileName" class="profile-file-name">${t('prof_no_file_selected')}</small>
                    </div>
                    <button type="submit" class="btn-secondary" style="width: 100%; transition: all 0.2s;">${t('prof_upload_photo')}</button>
                </form>
            </div>

            <!-- Account Details & Password -->
            <div class="col-span-8" style="display: flex; flex-direction: column; gap: 1.5rem;">
                <div class="card">
                    <div class="card-title">${t('prof_acc_details')}</div>
                    <form autocomplete="off" onsubmit="handleUpdateProfileDetails(event)">
                        <div class="dashboard-grid" style="gap: 1rem; margin-bottom: 1rem;">
                            <div class="form-group col-span-6">
                                <label class="form-label">${t('prof_display_name')}</label>
                                <input type="text" id="profileDisplayName" class="form-control" value="${escapeHTML(displayName)}" placeholder="${t('prof_display_name_ph')}" autocomplete="nickname" required maxlength="100">
                                <small style="display: block; margin-top: 0.35rem; color: var(--color-text-secondary);">${t('prof_display_name_help')}</small>
                            </div>
                            
                            <div class="form-group col-span-6">
                                <label class="form-label">${t('prof_email')}</label>
                                <input type="email" class="form-control" value="${currentUser.email}" disabled style="background-color: var(--color-surface); opacity: 0.7; cursor: not-allowed;">
                            </div>
                            <div class="form-group col-span-6">
                                <label class="form-label">${t('prof_iqama')}</label>
                                <input type="text" id="profileIqama" class="form-control" value="${profile.iqama_number || ''}" placeholder="${t('users_iqama_ph')}">
                            </div>
                            <div class="form-group col-span-6">
                                <label class="form-label">${t('prof_phone')}</label>
                                <input type="text" id="profilePhone" class="form-control" value="${profile.phone_number || ''}" placeholder="${t('users_phone_ph')}">
                            </div>
                        </div>
                        <button type="submit" class="btn-primary" style="transition: all 0.2s;">${t('prof_save')}</button>
                    </form>
                </div>

                <div class="card profile-contract-card">
                    <div class="card-title">${t('profile_my_contract')}</div>
                    ${ownContract ? `
                        <div class="profile-contract-grid">
                            <div><span>${t('users_job_title')}</span><strong>${escapeHTML(ownContract.job_title_en || ownContract.job_title || profile.job_title || t('emp_na'))}</strong></div>
                            <div><span>${t('contract_status')}</span><strong>${escapeHTML(ownContract.status || t('emp_na'))}</strong></div>
                            <div><span>${t('contract_start')}</span><strong>${escapeHTML(ownContract.start_date || t('emp_na'))}</strong></div>
                            <div><span>${t('contract_end')}</span><strong>${escapeHTML(ownContract.end_date || t('contract_indefinite'))}</strong></div>
                            <div><span>${t('prof_iqama')}</span><strong>${escapeHTML(ownContract.identity_number || profile.iqama_number || t('emp_na'))}</strong></div>
                            <div><span>${t('prof_phone')}</span><strong>${escapeHTML(ownContract.employee_phone || profile.phone_number || t('emp_na'))}</strong></div>
                        </div>
                        <div class="profile-contract-actions">
                            ${latestPrintRequest?.status === 'APPROVED'
                                ? `<button class="btn btn-primary" onclick="openOwnContractPrint('${ownContract.id}')"><i data-lucide="printer"></i>${t('profile_print_contract')}</button>`
                                : latestPrintRequest?.status === 'PENDING'
                                    ? `<span class="status-badge warning">${t('profile_print_pending')}</span>`
                                    : `<button class="btn btn-secondary" onclick="requestOwnContractPrint('${ownContract.id}')"><i data-lucide="send"></i>${t('profile_request_print')}</button>`}
                        </div>` : `<p class="text-muted">${t('profile_no_contract')}</p>`}
                </div>

                <div class="card">
                    <div class="card-title">${t('prof_security')}</div>
                    <form autocomplete="off" onsubmit="handleUpdatePassword(event)" style="display: flex; gap: 1rem; align-items: flex-end;">
                        <div class="form-group" style="flex: 1; margin-bottom: 0; position: relative;">
                            <label class="form-label">${t('prof_new_pass')}</label>
                            <input type="password" autocomplete="new-password" id="newPassword" class="form-control" required minlength="6" style="padding-right: 40px;">
                            <button type="button" class="password-toggle-btn" onclick="togglePasswordVisibility('newPassword')">
                                <i data-lucide="eye" id="newPassword-eye-icon" style="width: 20px; height: 20px;"></i>
                            </button>
                        </div>
                        <button type="submit" class="btn-secondary" style="transition: all 0.2s;">${t('prof_update_pass')}</button>
                    </form>
                </div>
            </div>
        </div>
    `;
}

window.handleUpdateProfilePhoto = async function (e) {
    e.preventDefault();
    const fileInput = document.getElementById('avatarFile');
    if (!fileInput.files || fileInput.files.length === 0) return;

    const file = fileInput.files[0];
    const reader = new FileReader();
    reader.onload = async function (event) {
        const rawUrl = event.target.result;

        // Compress image using canvas to ensure lightweight base64 string
        const img = new Image();
        img.onload = async function () {
            const canvas = document.createElement('canvas');
            const maxDim = 250;
            let width = img.width;
            let height = img.height;

            if (width > height) {
                if (width > maxDim) {
                    height = Math.round((height * maxDim) / width);
                    width = maxDim;
                }
            } else {
                if (height > maxDim) {
                    width = Math.round((width * maxDim) / height);
                    height = maxDim;
                }
            }

            canvas.width = width;
            canvas.height = height;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(img, 0, 0, width, height);

            const compressedBase64 = canvas.toDataURL('image/jpeg', 0.85);

            localStorage.setItem('user_avatar_' + currentUser.id, compressedBase64);
            const { success, error } = await db.updateProfilePhoto(currentUser.id, compressedBase64);
            if (success) {
                showToast(t('toast_profile_photo_updated') || 'Profile photo updated successfully!', "success");
                const topAvatar = document.getElementById('topbarAvatar');
                if (topAvatar) topAvatar.src = compressedBase64;

                if (currentUser) currentUser.avatar_url = compressedBase64;
                if (currentUserProfile) currentUserProfile.avatar_url = compressedBase64;

                // Clear view cache so new profile picture immediately reflects on Dashboard Hierarchy
                if (window.viewHTMLCache) {
                    delete window.viewHTMLCache.dashboard;
                    delete window.viewHTMLCache.profile;
                    delete window.viewHTMLCache.users;
                }
                renderView('profile');
            } else {
                localStorage.removeItem('user_avatar_' + currentUser.id);
                showToast(error?.message || t('toast_error_updating_photo') || 'Error updating profile photo', "danger");
            }
        };
        img.src = rawUrl;
    };
    reader.readAsDataURL(file);
}

window.handleUpdatePassword = async function (e) {
    e.preventDefault();
    
    // Check password change limit
    if (currentUserProfile && (currentUserProfile.password_changes_count || 0) >= 3) {
        showToast(t('password_change_limit_reached') || "You have reached the maximum number of password changes (3). Please contact an admin to reset your password.", "warning");
        return;
    }
    
    const newPwd = document.getElementById('newPassword').value;
    const { success, error } = await db.updateUserPassword(newPwd);
    if (success) {
        showToast(t('toast_password_updated_successfully'), "success");
        document.getElementById('newPassword').value = '';
        
        // Increment count
        await db.incrementPasswordChangeCount(currentUser.id);
        if (currentUserProfile) {
            currentUserProfile.password_changes_count = (currentUserProfile.password_changes_count || 0) + 1;
        }
    } else {
        showToast(error?.message || "Error updating password.", "danger");
    }
}

window.handleUpdateProfileDetails = async function (e) {
    e.preventDefault();
    const displayName = document.getElementById('profileDisplayName').value.trim();
    const fullName = currentUserProfile?.full_name || '';
    const iqama = document.getElementById('profileIqama').value.trim();
    const phone = document.getElementById('profilePhone').value.trim();

    if (!displayName) {
        showToast(t('toast_display_name_required'), "warning");
        return;
    }
    if (displayName.length > 100) {
        showToast(t('toast_display_name_too_long'), "warning");
        return;
    }

    const { success, data, error } = await db.updateUserProfileDetails(currentUser.id, displayName, fullName, iqama, phone);
    if (success) {
        showToast(t('toast_profile_details_updated_successfully'), "success");
        const profile = data || await db.getUserProfile(currentUser.id);
        updateTopbarProfile(profile);
        delete window.viewHTMLCache.dashboard;
        await renderView('profile');
    } else {
        showToast(error?.message || "Error updating profile details.", "danger");
    }
}



async function renderTasks() {
    console.log("renderTasks: Fetching data for V2...");
    const tasksPromise = db.fetchTasks();
    const [allUsers, fetchedTasks, departmentSupervisors, allDepartments, fetchedTaskLists, watcherDirectory, taskListDirectory] = await Promise.all([
        db.fetchUsers(),
        tasksPromise,
        db.fetchMyDepartmentSupervisors(),
        db.fetchDepartments(),
        db.fetchTaskLists(),
        db.fetchTaskWatcherDirectory(),
        db.fetchTaskListDepartmentDirectory()
    ]);
    
    window.taskDepartmentSupervisors = departmentSupervisors || [];
    const viewerProfile = currentUserProfile || allUsers.find(user => user.id === currentUser?.id);
    const taskLists = (fetchedTaskLists || []).filter(list => {
        if (isTaskAdmin()) return true;
        if (list.owner_id === currentUser?.id) return true;
        if (list.visible_to_all) return true;
        if (!viewerProfile?.department_id || !list.department_id) return false;
        return list.department_id === viewerProfile.department_id;
    });
    const marketingDepartmentRecord = allDepartments.find(department => department.name === 'Marketing & Sales');
    window.isMarketingDepartmentManager = !!currentUser && [marketingDepartmentRecord?.head_id, marketingDepartmentRecord?.manager_id].includes(currentUser.id);
    window.taskDepartmentManagerByName = Object.fromEntries(allDepartments.map(department => [department.name, department.head_id || department.manager_id || null]));
    window.taskCache = {};
    window.taskAssigneeOptionsCache = ''; 
    window.taskAllUsersCache = allUsers;
    window.taskWatcherDirectoryCache = Array.isArray(watcherDirectory) && watcherDirectory.length ? watcherDirectory : allUsers;
    window.taskDepartmentsCache = allDepartments;
    window.taskListsCache = taskLists || [];
    
    let tasks = fetchedTasks.map(t => {
        const assignee = allUsers.find(u => u.id === t.assignee_id);
        const creator = allUsers.find(u => u.id === t.created_by);
        const displayTitle = getLocalizedTaskTitle(t);
        const taskObj = {
            ...t,
            assignee_ids: Array.isArray(t.assignee_ids) && t.assignee_ids.length ? t.assignee_ids : (t.assignee_id ? [t.assignee_id] : []),
            displayTitle,
            status: t.status || 'todo',
            priority: t.priority || 'medium',
            category: t.category || 'General',
            assignee: assignee ? { full_name: assignee.full_name } : null,
            creator: creator ? { full_name: creator.full_name } : null
        };
        window.taskCache[t.id] = taskObj;
        return taskObj;
    });
    
    let teamIds = [currentUser.id];
    if (currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') {
        const directReports = allUsers.filter(u => u.manager_id === currentUser.id).map(u => u.id);
        const indirectReports = allUsers.filter(u => directReports.includes(u.manager_id)).map(u => u.id);
        teamIds = [currentUser.id, ...directReports, ...indirectReports];
    }

    window.visibleTaskIds = tasks.filter(task => {
        if (currentUserRole === 'ADMIN') return true;
        if (task.created_by === currentUser.id) return true;
        if (task.assignee_id === currentUser.id) return true;
        if (Array.isArray(task.assignee_ids) && task.assignee_ids.includes(currentUser.id)) return true;
        if (task.supervisor_id === currentUser.id) return true;
        if (task.watchers && task.watchers.includes(currentUser.id)) return true;
        
        if ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') && (teamIds.includes(task.assignee_id) || (task.assignee_ids || []).some(id => teamIds.includes(id)))) return true;
        
        if (task.task_list_id) {
            const list = taskLists.find(l => l.id === task.task_list_id);
            if (list && (list.owner_id === currentUser.id || list.visible_to_all || list.department_id === viewerProfile?.department_id || (list.shared_with && list.shared_with.includes(currentUser.id)))) {
                return true;
            }
        }
        
        if (task.department === 'Marketing & Sales' && window.isMarketingDepartmentManager) return true;
        
        return false;
    }).map(task => String(task.id));
    
    const projects = await db.fetchProjects(currentUser.id);
    window.projectsCache = projects;
    window.projectOptionsCache = projects.map(p => `<option value="${p.id}">${p.project_name}</option>`).join('');

    let users = allUsers;
    const isRegularEmployee = currentUserRole === 'EMPLOYEE';
    if (currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') {
        users = users.filter(u => teamIds.includes(u.id));
    } else if (isRegularEmployee) {
        users = users.filter(u => u.id === currentUser.id);
    }
    window.taskAssigneeOptionsCache = users.map(u => {
        const label = window.formatEmployeeName(u) || u.id.substring(0, 8);
        const selected = u.id === currentUser.id ? 'selected' : '';
        return `<option value="${escapeHTML(u.id)}" ${selected}>${escapeHTML(label)} (${escapeHTML(localizeRuntimeText(u.role || 'EMPLOYEE'))})</option>`;
    }).join('');

    const ownTaskLists = (taskLists || []).filter(list => list.owner_id === currentUser.id);
    const currentProfile = allUsers.find(user => user.id === currentUser.id) || currentUser;
    // Administrators and department managers may choose a department in the
    // access tab, so keep the full active directory available for filtering.
    const canManageTaskListDepartments = isTaskAdmin();
    window.taskListShareCandidates = (canManageTaskListDepartments ? allUsers : (taskListDirectory || [])).filter(user => user.id !== currentUser.id && user.is_active !== false);
    window.taskWatcherOptionsCache = window.taskWatcherDirectoryCache.map(u => {
        const label = window.formatEmployeeName(u) || u.id.substring(0, 8);
        return `<option value="${escapeHTML(u.id)}">${escapeHTML(label)} (${escapeHTML(localizeRuntimeText(u.role || 'EMPLOYEE'))})</option>`;
    }).join('');
    
    return ''; 
}

function renderTaskCard(task) {
    const taskList = (window.taskListsCache || []).find(list => list.id === task.task_list_id);
    const canManageTask = isTaskAdmin() || (task.task_list_id
        ? taskList?.owner_id === currentUser?.id
        : [task.created_by, task.assignee_id, task.supervisor_id].includes(currentUser?.id) || (task.department === 'Marketing & Sales' && window.isMarketingDepartmentManager));
    const canEditTask = isTaskAdmin() || task.created_by === currentUser?.id;
    const canDeleteTask = isTaskAdmin() || task.created_by === currentUser?.id
        || (taskList?.can_delete_users || []).includes(currentUser?.id);
    const parentTask = task.parent_task_id ? window.taskCache?.[task.parent_task_id] : null;
    const priorityLabel = task.priority === 'urgent' ? 'Urgent' : `${task.priority || 'medium'}`.replace(/^./, value => value.toUpperCase());
    const assigneeIds = Array.isArray(task.assignee_ids) && task.assignee_ids.length ? task.assignee_ids : [task.assignee_id].filter(Boolean);
    const assignedUsers = (window.taskAllUsersCache || []).filter(user => assigneeIds.includes(user.id));
    const assigneeName = window.formatEmployeeName(task.assignee) || (assignedUsers[0] ? window.formatEmployeeName(assignedUsers[0]) : '') || t('task_unknown') || 'Unassigned';
    const assigneeInitials = task.assignee
        ? assigneeName.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join('').toUpperCase()
        : '';
    const isOverdue = task.due_date && !['completed', 'Approved'].includes(task.status) && new Date(`${task.due_date}T23:59:59`) < new Date();
    const dueLabel = task.due_date
        ? new Intl.DateTimeFormat(currentLang === 'ar' ? 'ar-SA' : 'en', { month: 'short', day: 'numeric' }).format(new Date(`${task.due_date}T12:00:00`))
        : (t('task_no_date') || 'No date');
    
    return `
        <article class="task-item-card task-pipeline-card priority-${escapeHTML(task.priority)} ${isOverdue ? 'is-overdue' : ''}" data-task-id="${task.id}" id="task-card-${task.id}" data-project-id="${task.project_id || 'none'}" data-list-id="${task.task_list_id || 'none'}" data-status="${escapeHTML(task.status)}" draggable="${canManageTask}" ${canManageTask ? `ondragstart="handleTaskDragStart(event, '${task.id}')"` : ''} onclick="openTaskDetailsModal('${task.id}')" oncontextmenu="window.handleTaskContextMenu(event, '${task.id}', ${canEditTask}, ${canDeleteTask})">
            <div class="task-pipeline-card-head">
                <h4 onclick="event.stopPropagation(); window.openTaskDetailsModal('${task.id}')" style="cursor:pointer;"><span class="task-relation-badge ${task.parent_task_id ? 'is-subtask' : 'is-parent'}">${task.parent_task_id ? 'Subtask' : 'Task'}</span>${escapeHTML(task.displayTitle)}</h4>
            </div>
            ${task.parent_task_id ? `<div class="task-parent-reference"><i data-lucide="corner-down-right"></i> ${escapeHTML(parentTask?.displayTitle || parentTask?.title || 'Parent task')}</div>` : ''}
            <div class="task-pipeline-card-footer">
                <button type="button" class="task-assignee" title="Change assignees" onclick="window.handleTaskAssigneeClick(event, '${task.id}')">
                    <span class="task-assignee-avatar-stack">${(assignedUsers.length ? assignedUsers : [task.assignee]).filter(Boolean).slice(0, 4).map(user => { const name = window.formatEmployeeName(user) || 'Employee'; return `<span class="task-avatar" title="${escapeHTML(name)}">${escapeHTML(name.split(/\s+/).map(part => part[0]).join('').slice(0, 2).toUpperCase())}</span>`; }).join('') || '<span class="task-avatar"><i data-lucide="user"></i></span>'}</span>
                    <span>${escapeHTML(assigneeIds.length > 1 ? `${assigneeName.split(' ')[0]} +${assigneeIds.length - 1}` : assigneeName.split(' ')[0])}</span>
                </button>
                <div class="task-card-signals">
                    <span class="task-priority-label"><i></i>${escapeHTML(priorityLabel)}</span>
                    <span class="task-due-date ${isOverdue ? 'is-overdue' : ''}"><i data-lucide="calendar"></i>${escapeHTML(dueLabel)}</span>
                </div>
            </div>
        </article>
    `;
}

async function renderTasksV2() {
    console.log("renderTasksV2: Loading tasks natively...");
    await renderTasks();

    const visibleIds = new Set(window.visibleTaskIds || []);
    const tasks = Object.values(window.taskCache || {}).filter(task => visibleIds.has(String(task.id)));
    
    const dueSoonCount = tasks.filter(task => {
        if (!task.due_date || task.status === 'completed' || task.status === 'Approved') return false;
        const days = (new Date(`${task.due_date}T23:59:59`) - new Date()) / 86400000;
        return days >= 0 && days <= 7;
    }).length;
    const overdueCount = tasks.filter(task => task.due_date && task.status !== 'completed' && task.status !== 'Approved' && new Date(`${task.due_date}T23:59:59`) < new Date()).length;
    
    const projects = window.projectsCache || [];
    const taskLists = window.taskListsCache || [];
    const selectedProject = window.taskV2SelectedProject || 'all';
    const taskViewMode = window.taskV2Mode || 'focus';
    
    const viewerDepartmentId = currentUserProfile?.department_id || (window.taskAllUsersCache || []).find(user => user.id === currentUser?.id)?.department_id;
    let canCreateTask = !!currentUser;
    if (selectedProject.startsWith('list_') && !isTaskAdmin()) {
        const listId = selectedProject.substring(5);
        const list = taskLists.find(l => l.id === listId);
        if (list) {
            canCreateTask = false;
            if (list.owner_id === currentUser.id) canCreateTask = true;
            else if (list.can_add_users && list.can_add_users.includes(currentUser.id)) canCreateTask = true;
            else if (list.department_id && viewerDepartmentId && list.department_id === viewerDepartmentId) canCreateTask = true;
        }
    }
    
    const projectItems = projects.map(p => `
        <li class="${selectedProject === String(p.id) ? 'active' : ''}" onclick="window.selectTaskV2Project('${p.id}')">
            <i data-lucide="folder"></i>
            <span>${escapeHTML(p.project_name)}</span>
        </li>
    `).join('');

    const viewerIsTaskAdmin = isTaskAdmin();
    const ownTaskLists = taskLists.filter(list => list.owner_id === currentUser.id);
    const sharedTaskLists = taskLists.filter(list => list.owner_id !== currentUser.id && list.shared_with && list.shared_with.includes(currentUser.id));
    const departmentTaskLists = taskLists.filter(list => {
        const isAlreadyGrouped = list.owner_id === currentUser.id || (list.shared_with || []).includes(currentUser.id);
        return !isAlreadyGrouped && (viewerIsTaskAdmin || list.visible_to_all || (list.department_id && list.department_id === viewerDepartmentId));
    });
    
    let personalListItems = '';
    if (ownTaskLists.length > 0) {
        personalListItems += ownTaskLists.map(list => {
            const listTasksCount = tasks.filter(t => t.task_list_id === list.id).length;
            return `
            <li class="${selectedProject === 'list_' + String(list.id) ? 'active' : ''}" onclick="window.selectTaskV2Project('list_${list.id}')" oncontextmenu="window.showTaskListContextMenu(event, '${list.id}', ${currentUserRole === 'ADMIN'})">
                <span class="task-list-name">${escapeHTML(list.name)}</span>
                <div style="margin-left: auto; display: flex; gap: 4px; align-items: center;">
                    <button class="icon-btn" onclick="event.stopPropagation(); window.openTaskListModal('${list.id}')" style="padding: 2px;" title="Edit List"><i data-lucide="settings" style="width:14px;height:14px;"></i></button>
                    <button class="icon-btn" onclick="event.stopPropagation(); window.handleDeleteTaskList('${list.id}')" style="padding: 2px; color: var(--color-danger);" title="Delete List"><i data-lucide="trash-2" style="width:14px;height:14px;"></i></button>
                    <span class="badge task-count-badge" style="background: var(--color-surface); color: var(--color-text-secondary); border-radius: 4px; padding: 0.15rem 0.4rem; font-size: 0.75rem; margin-left: 4px;">${listTasksCount}</span>
                </div>
            </li>
        `}).join('');
    }
    if (sharedTaskLists.length > 0) {
        personalListItems += sharedTaskLists.map(list => {
            const listTasksCount = tasks.filter(t => t.task_list_id === list.id).length;
            const owner = window.taskAllUsersCache?.find(u => u.id === list.owner_id);
            const ownerName = owner ? owner.full_name.split(' ')[0] : 'Unknown';
            return `
            <li class="${selectedProject === 'list_' + String(list.id) ? 'active' : ''}" onclick="window.selectTaskV2Project('list_${list.id}')" oncontextmenu="window.showTaskListContextMenu(event, '${list.id}', ${currentUserRole === 'ADMIN'})">
                <span class="task-list-name" title="Shared by ${ownerName}">${escapeHTML(list.name)} (Shared)</span>
                <span class="badge task-count-badge" style="margin-left: auto; background: var(--color-surface); color: var(--color-text-secondary); border-radius: 4px; padding: 0.15rem 0.4rem; font-size: 0.75rem;">${listTasksCount}</span>
            </li>
            `;
        }).join('');
    }
    if (departmentTaskLists.length > 0) {
        personalListItems += departmentTaskLists.map(list => {
            const listTasksCount = tasks.filter(task => task.task_list_id === list.id).length;
            return `
            <li class="${selectedProject === 'list_' + String(list.id) ? 'active' : ''}" onclick="window.selectTaskV2Project('list_${list.id}')" oncontextmenu="window.showTaskListContextMenu(event, '${list.id}', ${currentUserRole === 'ADMIN'})">
                <span class="task-list-name" title="Department task list">${escapeHTML(list.name)}</span>
                <span class="badge task-count-badge" style="margin-left:auto;background:var(--color-surface);color:var(--color-text-secondary);border-radius:4px;padding:.15rem .4rem;font-size:.75rem;">${listTasksCount}</span>
            </li>`;
        }).join('');
    }

    const taskRows = tasks.map(task => {
        const canManageTask = isTaskAdmin() || (task.task_list_id
            ? taskLists.find(l => l.id === task.task_list_id)?.owner_id === currentUser?.id
            : [task.created_by, task.assignee_id, task.supervisor_id].includes(currentUser?.id));
        const canEditTask = isTaskAdmin() || task.created_by === currentUser?.id;
        const taskList = taskLists.find(list => list.id === task.task_list_id);
        const canDeleteTask = isTaskAdmin() || task.created_by === currentUser?.id
            || (taskList?.can_delete_users || []).includes(currentUser?.id);
        const prioColor = task.priority === 'high' || task.priority === 'urgent' ? 'var(--color-warning)' : (task.priority === 'critical' ? 'var(--color-danger)' : 'var(--color-text-secondary)');
        const isCompleted = task.status === 'completed';
        const stageCheckColor = {
            in_progress: '#f59e0b',
            review: '#2563eb',
            'Pending Approval': '#7c3aed',
            completed: '#059669',
            Approved: '#059669'
        }[task.status] || 'var(--color-text-secondary)';
        
        const listName = taskList?.name || (task.project_id ? (projects.find(project => project.id === task.project_id)?.project_name || 'Project tasks') : 'Personal tasks');
        const childCount = tasks.filter(child => child.parent_task_id === task.id).length;
        const dueClass = task.due_date && !['completed', 'Approved'].includes(task.status) && new Date(`${task.due_date}T23:59:59`) < new Date() ? ' overdue' : '';
        const daysUntilDue = task.due_date ? (new Date(`${task.due_date}T23:59:59`) - new Date()) / 86400000 : null;
        const isClosedTask = task.status === 'completed' || task.status === 'Approved';
        const isFocusTask = !isClosedTask && (task.status === 'Rejected' || task.priority === 'urgent' || task.priority === 'critical' || (daysUntilDue !== null && daysUntilDue <= 7));
        const rowAssigneeIds = Array.isArray(task.assignee_ids) && task.assignee_ids.length ? task.assignee_ids : [task.assignee_id].filter(Boolean);
        const rowAssignedUsers = (window.taskAllUsersCache || []).filter(user => rowAssigneeIds.includes(user.id));
        const avatarHTML = rowAssignedUsers.length ? `<span class="task-assignee-avatar-stack">${rowAssignedUsers.slice(0, 4).map(user => { const name = window.formatEmployeeName(user) || 'Employee'; return `<span class="avatar-circle" title="${escapeHTML(name)}">${escapeHTML(name.split(/\s+/).map(part => part[0]).join('').slice(0, 2).toUpperCase())}</span>`; }).join('')}</span>` : `<span class="avatar-circle" title="Unassigned"><i data-lucide="user" style="width:14px;height:14px;"></i></span>`;

        return `
            <article class="task-v2-row ${isCompleted ? 'completed' : ''}" data-task-id="${task.id}" data-project-id="${task.project_id || 'none'}" data-list-id="${task.task_list_id || 'none'}" data-status="${escapeHTML(task.status)}" data-focus="${isFocusTask}" onclick="openTaskDetailsModal('${task.id}')" style="cursor:pointer; display: flex; align-items: center; justify-content: space-between; padding: 0.75rem 1rem; border-bottom: 1px solid var(--color-border); background: var(--color-surface); transition: background 0.2s; flex-wrap: wrap; gap: 0.5rem;">
                <div class="task-v2-row-left" style="display: flex; align-items: center; gap: 0.75rem; flex: 1;">
                    <button class="task-v2-check-btn" onclick="event.stopPropagation(); window.taskV2ToggleComplete('${task.id}', event)" ${!canManageTask ? 'disabled' : ''} style="background:none; border:none; cursor:pointer; display:flex; align-items:center; padding:0;">
                        <i data-lucide="check-circle-2" style="width: 20px; height: 20px; color: ${stageCheckColor};"></i>
                    </button>
                    <div class="task-v2-row-content" style="display: flex; flex-direction: column;">
                        <h4 onclick="event.stopPropagation(); window.openTaskDetailsModal('${task.id}')" style="margin: 0; font-size: 0.95rem; font-weight: 500; cursor: pointer; ${isCompleted ? 'text-decoration: line-through; opacity: 0.6;' : 'color: var(--color-text);'}">
                            ${task.parent_task_id ? '<span class="task-relation-badge is-subtask">Subtask</span> ' : ''}
                            ${escapeHTML(task.displayTitle)}
                        </h4>
                    </div>
                </div>
                
                <div class="task-v2-row-actions" style="display: flex; align-items: center; gap: 1rem; flex-shrink: 0;">
                    <button type="button" class="task-assignee task-row-assignee" title="Change assignee" onclick="window.handleTaskAssigneeClick(event, '${task.id}')">${avatarHTML}</button>
                    ${task.due_date ? `<span class="${dueClass}" style="display:flex; align-items: center; gap:4px; font-size:0.8rem; color:var(--color-text-secondary); white-space:nowrap; flex-shrink:0;"><i data-lucide="calendar" style="width:14px;height:14px;"></i> ${task.due_date}</span>` : ''}
                    ${task.category && task.category !== 'General' ? `<span class="badge" style="background: rgba(99, 102, 241, 0.1); color: var(--color-primary); font-size: 0.75rem;">${escapeHTML(task.category)}</span>` : ''}
                    <button class="icon-btn ${canEditTask ? '' : 'is-disabled'}" ${canEditTask ? `onclick="event.stopPropagation(); openEditTaskModal('${task.id}')"` : 'disabled'} title="${canEditTask ? 'Edit task' : 'Only the task creator or an administrator can edit this task'}" style="color:var(--color-text-secondary);"><i data-lucide="pencil" style="width:16px;height:16px;"></i></button>
                    <button class="icon-btn task-pipeline-delete ${canDeleteTask ? '' : 'is-disabled'}" ${canDeleteTask ? `onclick="event.stopPropagation(); window.handleDeleteTask('${task.id}')"` : 'disabled'} title="${canDeleteTask ? 'Delete task' : 'Only the task creator or an administrator can delete this task'}" style="color:var(--color-danger);"><i data-lucide="trash-2" style="width:16px;height:16px;"></i></button>
                </div>
            </article>
        `;
    }).join('');

    const pending = tasks.filter(t => t.status === 'Pending Approval');
    const todo = tasks.filter(t => t.status === 'todo');
    const inProgress = tasks.filter(t => t.status === 'in_progress');
    const review = tasks.filter(t => t.status === 'review');
    const done = tasks.filter(t => t.status === 'completed');
    
    // Add additional statuses like Approved/Rejected if used
    const approved = tasks.filter(t => t.status === 'Approved');
    const rejected = tasks.filter(t => t.status === 'Rejected');

    const stageDefinitions = [
        { status: 'todo', badge: 'todo', label: 'To do', tone: 'slate', tasks: todo },
        { status: 'in_progress', badge: 'in_progress', label: 'In progress', tone: 'blue', tasks: inProgress },
        { status: 'review', badge: 'review', label: 'Review', tone: 'purple', tasks: review },
        { status: 'Pending Approval', badge: 'pending', label: 'Awaiting approval', tone: 'amber', tasks: pending },
        { status: 'completed', badge: 'completed', label: 'Done', tone: 'green', tasks: done }
    ];
    if (approved.length || rejected.length) {
        stageDefinitions.push(
            { status: 'Approved', badge: 'approved', label: 'Approved', tone: 'green', tasks: approved },
            { status: 'Rejected', badge: 'rejected', label: 'Rejected', tone: 'red', tasks: rejected }
        );
    }

    const boardHTML = `
        <div id="tasks-view-board" class="task-pipeline-view" style="display: ${taskViewMode === 'board' ? 'block' : 'none'};">
            <div class="task-board-wrapper">
                <div class="task-board">
                    ${stageDefinitions.map(stage => `
                        <section class="task-board-column task-stage-${stage.tone}" data-stage="${escapeHTML(stage.status)}">
                            <div class="task-stage-panel">
                                <header class="task-stage-header">
                                    <div class="task-stage-title"><span class="task-stage-dot"></span><h3>${stage.label}</h3></div>
                                    <span id="badge-${stage.badge}" class="task-stage-count">${stage.tasks.length}</span>
                                </header>
                                <div id="col-${stage.status}" class="task-column" ondragover="handleTaskDragOver(event)" ondrop="handleTaskDrop(event, '${stage.status}')">
                                    ${stage.tasks.map(renderTaskCard).join('')}
                                    ${stage.tasks.length ? '' : `<div class="task-stage-empty"><i data-lucide="inbox"></i><span>No tasks here</span></div>`}
                                </div>
                            </div>
                        </section>
                    `).join('')}
                </div>
            </div>
        </div>
    `;

    const isRegularEmployee = currentUserRole === 'EMPLOYEE';
    const creatorDepartmentId = currentUserProfile?.department_id || currentUser?.department_id || (window.taskAllUsersCache || []).find(user => user.id === currentUser?.id)?.department_id || '';
    const creatorDepartment = window.taskDepartmentsCache.find(d => d.id === creatorDepartmentId);
    const creatorDepartmentName = getCanonicalDepartmentName(creatorDepartment);
    const creatorDepartmentLabel = getTaskDepartmentLabel(creatorDepartment);
    const departmentOptions = window.taskDepartmentsCache.map(d => `<option value="${escapeHTML(getCanonicalDepartmentName(d))}" ${d.id === creatorDepartmentId ? 'selected' : ''}>${escapeHTML(getTaskDepartmentLabel(d))}</option>`).join('');
    const projectOptions = window.projectOptionsCache || '';
    const taskListOptions = ownTaskLists.map(list => `<option value="${escapeHTML(list.id)}">${escapeHTML(list.name)}</option>`).join('');

    let departmentSelectHTML = '';
    let isMarketing = !!(creatorDepartment && isMarketingTaskDepartment(creatorDepartmentName));

    if (isRegularEmployee) {
        const currentDeptObj = creatorDepartment;
        const deptName = currentDeptObj ? escapeHTML(getCanonicalDepartmentName(currentDeptObj)) : '';
        const deptLabel = currentDeptObj ? escapeHTML(getTaskDepartmentLabel(currentDeptObj)) : '';
        isMarketing = !!(currentDeptObj && isMarketingTaskDepartment(getCanonicalDepartmentName(currentDeptObj)));

        departmentSelectHTML = `
            <div class="form-group" style="flex: 1 1 200px; margin-bottom: 0;">
                <label class="form-label">${t('ui_department') || "Task's Department"}</label>
                <select id="taskDepartment" class="form-control" disabled>
                    <option value="${deptName}" selected>${deptLabel || 'No Department'}</option>
                </select>
            </div>
        `;
    } else {
        departmentSelectHTML = `
            <div class="form-group" style="flex: 1 1 200px; margin-bottom: 0;">
                <label class="form-label">${t('ui_department') || "Task's Department"}</label>
                <select id="taskDepartment" class="form-control" onchange="window.handleTaskDepartmentChange('new', this.value)">
                    <option value="">${t('ui_select') || 'Select'}</option>
                    ${departmentOptions}
                </select>
            </div>
        `;
    }

    const todayDate = new Date().toISOString().split('T')[0];
    const adminForm = canCreateTask ? `
        <!-- Create Task Modal -->
        <div class="modal" id="createTaskModal">
            <div class="modal-content create-task-modal-content">
                <div class="modal-header">
                    <div class="create-task-heading">
                        <span class="create-task-heading-icon"><i data-lucide="sparkles"></i></span>
                        <div>
                            <h2><span id="createTaskModalTitle">${t('add_new_task') || 'Add New Task'}</span></h2>
                            <p>Plan the work, choose the team, and share everything needed to begin.</p>
                        </div>
                    </div>
                    <button type="button" class="icon-btn" onclick="document.getElementById('createTaskModal').classList.remove('active')">
                        <i data-lucide="x"></i>
                    </button>
                </div>
                <form autocomplete="off" onsubmit="handleCreateTask(event)" id="standardTaskForm">
                    <input type="hidden" id="taskParentId" value="">
                    <input type="hidden" id="taskProject" value="">
                    <input type="hidden" id="taskListId" value="">

                    <div class="create-task-body">
                        <section class="create-task-section create-task-section-basics">
                            <div class="create-task-section-heading"><span><i data-lucide="clipboard-list"></i> Task details</span><small>Start with a clear title and ownership.</small></div>
                            <!-- Row 1: Created Date + Title -->
                            <div class="create-task-top-row">
                            <div class="form-group">
                                <label class="form-label">Created by</label>
                                <input type="text" class="form-control" value="${escapeHTML(getProfileDisplayName(currentUserProfile || currentUser) || 'Employee')}" readonly aria-readonly="true">
                            </div>
                            <div class="form-group">
                                <label class="form-label">Created Date</label>
                                <input type="date" id="taskCreatedDate" class="form-control" value="${todayDate}" readonly style="opacity:0.7; cursor:default;">
                            </div>
                            <div class="form-group">
                                <label class="form-label" id="taskTitleLabel">${t('task_title') || 'Task Title'}</label>
                                <input type="text" autocomplete="off" id="taskTitle" class="form-control" required placeholder="Enter task title">
                            </div>
                            </div>
                        </section>

                        <section class="create-task-section create-task-section-team">
                            <div class="create-task-section-heading"><span><i data-lucide="users"></i> Team and workflow</span><small>Choose where the task belongs and who should follow it.</small></div>
                            <!-- Row 2: Inline Dropdowns -->
                            <div class="create-task-fields-row">
                            ${isRegularEmployee ? `
                                <div class="form-group">
                                    <label class="form-label">${t('ui_department') || 'Department'}</label>
                                    <select id="taskDepartment" class="form-control" disabled>
                                        <option value="${escapeHTML(creatorDepartmentName)}" selected>${escapeHTML(creatorDepartmentLabel || 'No Department')}</option>
                                    </select>
                                </div>
                            ` : `
                                <div class="form-group">
                                    <label class="form-label">${t('ui_department') || 'Department'}</label>
                                    <select id="taskDepartment" class="form-control" onchange="window.handleCreateTaskDeptChange(this.value)">
                                        <option value="">${t('ui_select') || 'Select'}</option>
                                        ${departmentOptions}
                                    </select>
                                </div>
                            `}

                            <div class="form-group" id="taskSubTypeGroup" style="display: ${isMarketing ? 'flex' : 'none'}; margin-bottom: 0;">
                                <label class="form-label" for="taskSubType">Task Type</label>
                                <select id="taskSubType" class="form-control" onchange="window.handleCreateTaskTypeChange(this.value)">
                                    <option value="">Select Task Type</option>
                                    <option value="Regular Task">Regular Task</option>
                                    <option value="Designing Task">Designing Task</option>
                                </select>
                            </div>

                            <div class="form-group">
                                <label class="form-label">${t('task_assign_to') || 'Assign To'}</label>
                                <select id="taskAssignee" class="form-control" required ${isRegularEmployee ? 'disabled' : ''}>
                                    ${!isRegularEmployee ? `<option value="">${t('task_sel_emp') || 'Select Employee'}</option>` : ''}
                                    ${window.taskAssigneeOptionsCache}
                                </select>
                            </div>
                            
                            <div class="form-group">
                                <label class="form-label">Watchers (Optional)</label>
                                ${renderTaskWatcherPicker('taskWatchers', window.taskWatcherOptionsCache)}
                            </div>
                            </div>

                            <!-- Marketing Design Fields (hidden by default) -->
                            <div id="newMarketingDesignFields" class="marketing-design-fields" style="display: none;">
                                ${renderMarketingDesignFields('new')}
                            </div>
                        </section>

                        <section class="create-task-section create-task-section-content">
                            <div class="form-group task-repeat-field">
                                <label class="form-label" for="taskRepeatType">Set to repeat</label>
                                <select id="taskRepeatType" class="form-control">
                                    <option value="NONE">Does not repeat</option>
                                    <option value="DAILY">Daily</option>
                                    <option value="WEEKLY">Weekly</option>
                                    <option value="MONTHLY">Monthly</option>
                                </select>
                                <input type="number" id="taskRepeatInterval" class="form-control" min="1" value="1" aria-label="Repeat every" style="max-width:120px; margin-top:.5rem;" title="Repeat every number of periods">
                            </div>
                            <div class="create-task-section-heading"><span><i data-lucide="align-left"></i> Description</span><small>Add the outcome, context, and useful instructions.</small></div>
                            <div class="form-group create-task-desc-group">
                                <label class="form-label">${t('task_desc') || "Task's Description"}</label>
                                <textarea id="taskDesc" class="form-control" rows="5" placeholder="Describe the task..."></textarea>
                            </div>
                        </section>

                        <!-- Attachments -->
                        <section id="createTaskAttachmentsSection" class="create-task-section create-task-section-attachments">
                            <div class="create-task-attachments-heading">
                                <i data-lucide="paperclip"></i>
                                <span id="createTaskCollapseLabel">Attachments</span>
                            </div>
                            <div class="create-task-collapse-body open" id="createTaskCollapseBody" style="display:flex;">
                                <!-- Upload Zone -->
                                <div class="create-task-upload-zone" id="createTaskUploadZone" onclick="document.getElementById('createTaskFileInput').click()">
                                    <i data-lucide="upload-cloud"></i>
                                    <span>Attachment option with drag and drop feature to upload multi files, photos, and videos</span>
                                    <input type="file" id="createTaskFileInput" multiple onchange="window.handleCreateTaskFiles(this)">
                                </div>
                                <div class="create-task-file-list" id="createTaskFileList"></div>
                            </div>
                        </section>
                    </div>

                    <!-- Footer -->
                    <div class="create-task-footer">
                        <button type="submit" class="btn btn-primary"><i data-lucide="check"></i> ${t('save') || 'Save Task'}</button>
                        <button type="button" class="btn btn-secondary" onclick="document.getElementById('createTaskModal').classList.remove('active')">${t('cancel') || 'Cancel'}</button>
                    </div>
                </form>
            </div>
        </div>
        
        <!-- Task List Management Modal -->
        <div class="modal" id="taskListModal">
            <div class="modal-content task-list-modal-content" style="max-width: 600px;">
                <div class="modal-header" style="border-bottom: 1px solid var(--color-border); padding-bottom: 1rem; margin-bottom: 0;">
                    <h2 id="taskListModalTitle" style="font-size: 1.25rem; font-weight: 600; margin: 0;">Create a new Tasks List</h2>
                    <button type="button" class="icon-btn" onclick="window.closeTaskListModal()">
                        <i data-lucide="x"></i>
                    </button>
                </div>
                
                <div class="modal-tabs" style="display: flex; gap: 1.5rem; border-bottom: 1px solid var(--color-border); padding: 0 1.5rem; margin-bottom: 1.5rem;">
                    <button type="button" class="tab-btn active task-list-tab" onclick="window.switchTaskListTab('general')" style="background: none; border: none; padding: 0.75rem 0; font-weight: 500; cursor: pointer;">General</button>
                    <button type="button" class="tab-btn task-list-tab" onclick="window.switchTaskListTab('access')" style="background: none; border: none; padding: 0.75rem 0; font-weight: 500; cursor: pointer;">Access</button>
                    <button type="button" class="tab-btn task-list-tab" onclick="window.switchTaskListTab('notification')" style="background: none; border: none; padding: 0.75rem 0; font-weight: 500; cursor: pointer;">Notification</button>
                    <button type="button" class="tab-btn task-list-tab" onclick="window.switchTaskListTab('customFields')" style="background: none; border: none; padding: 0.75rem 0; font-weight: 500; cursor: pointer;">Custom Fields</button>
                </div>

                <form onsubmit="window.handleSaveTaskList(event)" style="padding: 0 1.5rem;">
                    <input type="hidden" id="taskListEditId">
                    
                    <div id="taskListTabGeneral" class="task-list-tab-content active" style="display: block;">
                        <div class="form-group" style="margin-bottom: 1.25rem;">
                            <label class="form-label" style="font-weight: 500; margin-bottom: 0.5rem;">Name *</label>
                            <input id="taskListName" class="form-control" maxlength="80" required placeholder="Name">
                        </div>
                        
                        <div class="form-group" style="margin-bottom: 1.25rem;">
                            <label class="form-label" style="font-weight: 500; margin-bottom: 0.5rem;">Template *</label>
                            <select id="taskListTemplate" class="form-control" required>
                                <option value="none">-- None --</option>
                                <option value="blank">Blank list</option>
                                <option value="kanban">Kanban board</option>
                                <option value="scrum">Scrum sprint</option>
                            </select>
                        </div>

                        <div class="form-group" style="margin-bottom: 1.5rem;">
                            <label class="form-label" style="font-weight: 500; margin-bottom: 0.5rem;">Description</label>
                            <textarea id="taskListDescription" class="form-control" rows="3" placeholder="Enter description"></textarea>
                        </div>
                    </div>
                    
                    <div id="taskListTabAccess" class="task-list-tab-content" style="display: none;">
                        <div class="form-group" style="margin-bottom: 1.5rem;">
                            <label class="form-label" for="taskListDepartment" style="font-weight: 500; margin-bottom: 0.5rem;">Visible to department *</label>
                            <select id="taskListDepartment" class="form-control" required onchange="window.refreshTaskListDepartmentControls()">
                                <option value="">Select department</option>
                                <option value="all">Visible to all departments</option>
                            </select>
                            <small class="text-muted" style="display: block; margin-top: 0.5rem;">Employees can only see task lists assigned to their own department.</small>
                        </div>
                        <div class="form-group" style="margin-bottom: 1.5rem;">
                            <label class="form-label" style="font-weight: 500; margin-bottom: 0.5rem;">Shared With</label>
                            <div class="custom-multi-select" id="taskListViewersWrapper" onclick="window.openCustomMultiSelectModal('taskListViewersOptions', event)">
                                <div class="custom-multi-select-header">
                                    <span id="taskListViewersText">Select employees...</span>
                                    <i data-lucide="chevron-down" style="width: 14px; height: 14px;"></i>
                                </div>
                                <div class="custom-multi-select-dropdown" id="taskListViewersOptions" onclick="event.stopPropagation()">
                                    <!-- Options injected here -->
                                </div>
                            </div>
                            <small class="text-muted" style="display: block; margin-top: 0.5rem;">Select employees who can view and interact with this task list.</small>
                        </div>
                        <div class="form-group" style="margin-bottom: 1.5rem;">
                            <label class="form-label" style="font-weight: 500; margin-bottom: 0.5rem;">Who can add tasks</label>
                            <div class="custom-multi-select" id="taskListAddUsersWrapper" onclick="window.openCustomMultiSelectModal('taskListAddUsersOptions', event)">
                                <div class="custom-multi-select-header">
                                    <span id="taskListAddUsersText">Select employees...</span>
                                    <i data-lucide="chevron-down" style="width: 14px; height: 14px;"></i>
                                </div>
                                <div class="custom-multi-select-dropdown" id="taskListAddUsersOptions" onclick="event.stopPropagation()">
                                    <!-- Options injected here -->
                                </div>
                            </div>
                            <small class="text-muted" style="display: block; margin-top: 0.5rem;">Select employees allowed to add tasks.</small>
                        </div>
                        <div class="form-group" style="margin-bottom: 1.5rem;">
                            <label class="form-label" style="font-weight: 500; margin-bottom: 0.5rem;">Who can delete tasks</label>
                            <div class="custom-multi-select" id="taskListDeleteUsersWrapper" onclick="window.openCustomMultiSelectModal('taskListDeleteUsersOptions', event)">
                                <div class="custom-multi-select-header">
                                    <span id="taskListDeleteUsersText">Select employees...</span>
                                    <i data-lucide="chevron-down" style="width: 14px; height: 14px;"></i>
                                </div>
                                <div class="custom-multi-select-dropdown" id="taskListDeleteUsersOptions" onclick="event.stopPropagation()">
                                    <!-- Options injected here -->
                                </div>
                            </div>
                            <small class="text-muted" style="display: block; margin-top: 0.5rem;">Select employees allowed to delete tasks (other than their own).</small>
                        </div>
                    </div>
                    
                    <div id="taskListTabNotification" class="task-list-tab-content" style="display: none;">
                        <div class="form-group" style="margin-bottom: 1rem;">
                            <label style="display: flex; align-items: center; gap: 0.5rem; cursor: pointer; font-weight: 500;">
                                <input type="checkbox" id="taskListNotifyAssignee" checked style="width: 16px; height: 16px;">
                                Notify assignees on new tasks
                            </label>
                        </div>
                        <div class="form-group" style="margin-bottom: 1.5rem;">
                            <label style="display: flex; align-items: center; gap: 0.5rem; cursor: pointer; font-weight: 500;">
                                <input type="checkbox" id="taskListNotifyComplete" checked style="width: 16px; height: 16px;">
                                Notify me when tasks are completed
                            </label>
                        </div>
                    </div>
                    
                    <div id="taskListTabCustomFields" class="task-list-tab-content" style="display: none;">
                        <div class="alert alert-info" style="margin-bottom: 1rem; font-size: 0.85rem; background: var(--color-surface); padding: 1rem; border-radius: 6px; border-left: 4px solid var(--color-primary);">
                            Custom fields allow you to add specific metadata to tasks in this list. (Coming soon)
                        </div>
                        <button type="button" class="btn btn-secondary btn-sm" disabled style="background: var(--color-surface); opacity: 0.6;"><i data-lucide="plus" style="width: 14px; height: 14px;"></i> Add Custom Field</button>
                    </div>

                    <!-- Hidden Viewer Picker for backward compatibility -->
                    <div id="taskListViewerPicker" style="display: none;"></div>

                    <div class="modal-actions" style="display: flex; justify-content: flex-end; gap: 0.75rem; border-top: 1px solid var(--color-border); padding-top: 1.25rem; margin-top: 1rem;">
                        <button type="button" class="btn btn-secondary" onclick="window.closeTaskListModal()" style="background: var(--color-surface); border: 1px solid var(--color-border);">Cancel</button>
                        <button class="btn btn-primary" type="submit">Save & Create</button>
                    </div>
                </form>
            </div>
        </div>
    ` : '';

    return `
        <div class="task-v2-shell fade-in-up">
            <div class="task-v2-workspace">
                <aside class="task-v2-lists">
                    <div class="task-v2-sidebar-header" style="display: flex; align-items: center; justify-content: flex-start; gap: 8px;">
                        <button class="icon-btn sidebar-collapse-btn" style="padding: 4px; margin: 0;"><i data-lucide="chevron-left" style="width: 20px; height: 20px;"></i></button>
                        <h3 style="margin: 0; font-size: 1.1rem; font-weight: 600;">Task lists</h3>
                    </div>
                    
                    <ul class="task-lists-nav" style="margin-top: 1rem; list-style: none; padding: 0; display: flex; flex-direction: column; gap: 0.25rem;">
                        <li class="${selectedProject === 'all' ? 'active' : ''}" onclick="window.selectTaskV2Project('all')">
                            <span class="task-list-name">All lists</span>
                            <span class="badge task-count-badge" style="margin-left: auto; background: var(--color-surface); color: var(--color-text-secondary); border-radius: 4px; padding: 0.15rem 0.4rem; font-size: 0.75rem;">${tasks.length}</span>
                        </li>
                        ${personalListItems}
                    </ul>
                    
                    <div style="margin-top: auto; padding-top: 1rem; padding-bottom: 1rem; text-align: center;">
                        <button class="btn btn-secondary btn-sm" style="width: calc(100% - 2rem); margin: 0 auto; justify-content: center; background: none; border: 1px dashed var(--color-border);" onclick="window.openTaskListModal()">
                            <i data-lucide="plus" style="width: 14px; height: 14px; margin-right: 4px;"></i> Add new list
                        </button>
                    </div>
                </aside>
            
            <section class="task-v2-list-pane">
                <header class="task-v2-toolbar">
                    <div class="task-v2-toolbar-left">
                        <div class="task-v2-search">
                            <i data-lucide="search"></i>
                            <input type="text" id="taskV2Search" placeholder="Search tasks..." onkeyup="window.filterTasksV2()">
                        </div>
                        <select id="taskV2StatusFilter" class="form-control" onchange="window.filterTasksV2()">
                            <option value="all">All Status</option>
                            <option value="open">Open Tasks</option>
                            <option value="todo">To Do</option>
                            <option value="in_progress">In Progress</option>
                            <option value="review">Review</option>
                            <option value="Pending Approval">Awaiting Approval</option>
                            <option value="completed">Completed</option>
                        </select>
                        <select id="taskV2PriorityFilter" class="form-control" onchange="window.filterTasksV2()">
                            <option value="all">All Priorities</option>
                            <option value="low">Low</option>
                            <option value="medium">Medium</option>
                            <option value="high">High</option>
                            <option value="urgent">Urgent</option>
                            <option value="critical">Critical</option>
                        </select>
                        <input type="date" id="taskV2DateFilter" class="form-control task-v2-date-filter" onchange="window.filterTasksV2()" aria-label="${taskDetailText('Filter by date', 'تصفية حسب التاريخ')}" title="${taskDetailText('Filter by date', 'تصفية حسب التاريخ')}">
                    </div>
                    <div class="task-v2-toolbar-right">
                        <div class="task-v2-view-toggles">
                            <button class="view-toggle-btn ${taskViewMode === 'focus' ? 'active' : ''}" id="btn-v2-focus" onclick="window.setTaskV2Mode('focus')">
                                <i data-lucide="circle-alert"></i> Focus
                            </button>
                            <button class="view-toggle-btn ${taskViewMode === 'board' ? 'active' : ''}" id="btn-v2-board" onclick="window.setTaskV2Mode('board')">
                                <i data-lucide="kanban"></i> Pipeline
                            </button>
                        </div>
                    </div>
                </header>
                
                <div class="task-pipeline-health" aria-label="Pipeline health summary">
                    <div class="task-health-heading"><i data-lucide="activity"></i><span>Pipeline health</span></div>
                    <div class="task-health-item tone-slate"><span class="task-health-dot"></span><strong>${todo.length + pending.length}</strong><span>waiting</span></div>
                    <div class="task-health-item tone-blue"><span class="task-health-dot"></span><strong>${inProgress.length}</strong><span>active</span></div>
                    <div class="task-health-item tone-amber"><span class="task-health-dot"></span><strong>${dueSoonCount}</strong><span>due this week</span></div>
                    <div class="task-health-item tone-red"><span class="task-health-dot"></span><strong>${overdueCount}</strong><span>overdue</span></div>
                    <div class="task-health-total"><strong>${tasks.length}</strong><span>total</span></div>
                    ${canCreateTask ? `<button class="btn btn-primary task-health-new-task" onclick="window.toggleTaskV2Create()"><i data-lucide="plus"></i><span>New Task</span></button>` : ''}
                </div>

                <div class="task-v2-rows" id="task-v2-rows-container" style="display: ${taskViewMode === 'focus' ? 'block' : 'none'};">
                    <div class="task-focus-header">
                        <div><span class="task-focus-kicker">Needs attention</span><h3>Focus view</h3></div>
                    </div>
                    ${taskRows || '<div class="empty-state">No tasks found.</div>'}
                    
                </div>
                
                ${boardHTML}
                
                ${adminForm}
            </section>
        </div>
    </div>`;
}

window.filterTasksV2 = function () {
    const query = (document.getElementById('taskV2Search')?.value || '').trim().toLowerCase();
    const status = document.getElementById('taskV2StatusFilter')?.value || 'all';
    const priority = document.getElementById('taskV2PriorityFilter')?.value || 'all';
    const dateFilter = document.getElementById('taskV2DateFilter')?.value || '';
    const project = window.taskV2SelectedProject || 'all';
    
    const visibleIds = new Set(window.visibleTaskIds || []);
    
    document.querySelectorAll('.task-v2-row, .task-item-card').forEach(el => {
        const taskId = el.getAttribute('data-task-id');
        const task = window.taskCache[taskId];
        if (!task || !visibleIds.has(taskId)) {
            el.style.display = 'none';
            return;
        }
        
        let matchesSearch = true;
        if (query) {
            const projectObj = (window.projectsCache || []).find(item => item.id === task.project_id);
            const parentTask = task.parent_task_id ? window.taskCache?.[task.parent_task_id] : null;
            const privateList = (window.taskListsCache || []).find(l => l.id === task.task_list_id);
            const searchable = [task.displayTitle, task.title, task.category, task.assignee?.full_name, projectObj?.project_name, privateList?.name, parentTask?.displayTitle].filter(Boolean).join(' ').toLowerCase();
            matchesSearch = searchable.includes(query);
        }
        
        const matchesStatus = (status === 'all') || (status === 'open' && task.status !== 'completed') || (task.status === status);
        const matchesPriority = (priority === 'all') || (task.priority === priority);
        const matchesDate = !dateFilter || String(task.due_date || '').slice(0, 10) === dateFilter;
        
        let matchesProject = true;
        if (project !== 'all') {
            if (project.startsWith('list_')) {
                matchesProject = String(task.task_list_id) === project.substring(5);
            } else {
                matchesProject = String(task.project_id) === project;
            }
        }
        
        const matchesMode = window.taskV2Mode !== 'focus' || el.classList.contains('task-item-card') || el.dataset.focus === 'true';
        if (matchesSearch && matchesStatus && matchesPriority && matchesDate && matchesProject && matchesMode) {
            el.style.display = '';
        } else {
            el.style.display = 'none';
        }
    });
};

window.selectTaskV2Project = function (projectId) {
    window.taskV2SelectedProject = projectId;
    document.querySelectorAll('.task-v2-lists li, .task-lists-nav li').forEach(li => {
        if (li.getAttribute('onclick')?.includes(`'${projectId}'`)) {
            li.classList.add('active');
        } else {
            li.classList.remove('active');
        }
    });
    const taskListInput = document.getElementById('taskListId');
    if (taskListInput) taskListInput.value = String(projectId).startsWith('list_') ? String(projectId).slice(5) : '';
    window.filterTasksV2();
};

// Applies / reverts the completed visual state on all row nodes for a task.
window._applyTaskRowCompleteStyle = function (taskId, completed) {
    document.querySelectorAll(`[data-task-id="${taskId}"]`).forEach(node => {
        // Check button icon
        // Lucide replaces <i data-lucide> with <svg> at runtime, so target svg
        const icon = node.querySelector('.task-v2-check-btn svg');
        if (icon) {
            icon.style.color = completed ? '#059669' : 'var(--color-text-secondary)';
            icon.style.transition = 'color 0.2s ease';
        }
        // Task title
        const title = node.querySelector('h4');
        if (title) {
            title.style.textDecoration = completed ? 'line-through' : '';
            title.style.opacity = completed ? '0.6' : '';
            title.style.transition = 'opacity 0.2s ease';
        }
        // Row article class
        if (node.tagName === 'ARTICLE') {
            node.classList.toggle('completed', completed);
        }
    });
};

const TASK_ACTION_UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function resolveTaskActionId(candidate, event) {
    const supplied = String(candidate || '').trim();
    if (TASK_ACTION_UUID_RE.test(supplied)) return supplied;
    const rowId = String(event?.currentTarget?.closest?.('[data-task-id]')?.dataset?.taskId || '').trim();
    return TASK_ACTION_UUID_RE.test(rowId) ? rowId : null;
}

window.taskV2ToggleComplete = async function (taskId, event) {
    if (event) event.stopPropagation();
    taskId = resolveTaskActionId(taskId, event);
    if (!taskId) {
        console.warn('Task status change skipped because the task ID is invalid.');
        return { error: new Error('Invalid task ID') };
    }
    const task = window.taskCache[taskId];
    if (!task) return;
    const newStatus = task.status === 'completed' ? 'todo' : 'completed';
    const wasCompleted = task.status === 'completed';

    // --- Optimistic update: apply visual state instantly ---
    window._applyTaskRowCompleteStyle(taskId, !wasCompleted);

    const result = await window.taskV2ChangeStage(taskId, newStatus);

    // Revert on failure
    if (result?.error) {
        window._applyTaskRowCompleteStyle(taskId, wasCompleted);
    }
};

// Handles clicking the check icon on a subtask row inside the task detail side panel.
window.toggleSubtaskComplete = async function (subtaskId, iconEl) {
    const subtask = window.taskCache?.[subtaskId];
    if (!subtask) return;

    const isCurrentlyDone = subtask.status === 'completed' || subtask.status === 'Approved';
    const newStatus = isCurrentlyDone ? 'todo' : 'completed';

    // Optimistic DOM update on the icon and its sibling title span
    const row = iconEl.closest('.task-detail-subtask-row');
    if (row) {
        iconEl.style.color = !isCurrentlyDone ? '#059669' : 'var(--color-text-secondary)';
        iconEl.setAttribute('data-lucide', !isCurrentlyDone ? 'check-circle-2' : 'circle');
        if (window.lucide) window.lucide.createIcons({ elements: [iconEl] });
        const titleSpan = row.querySelector('span');
        if (titleSpan) {
            titleSpan.style.textDecoration = !isCurrentlyDone ? 'line-through' : '';
            titleSpan.style.opacity = !isCurrentlyDone ? '0.55' : '';
        }
        row.classList.toggle('subtask-done', !isCurrentlyDone);
    }

    const result = await window.taskV2ChangeStage(subtaskId, newStatus);

    // On failure, revert the optimistic changes and re-render
    if (result?.error) {
        if (row) {
            iconEl.style.color = isCurrentlyDone ? '#059669' : 'var(--color-text-secondary)';
            iconEl.setAttribute('data-lucide', isCurrentlyDone ? 'check-circle-2' : 'circle');
            if (window.lucide) window.lucide.createIcons({ elements: [iconEl] });
            const titleSpan = row.querySelector('span');
            if (titleSpan) {
                titleSpan.style.textDecoration = isCurrentlyDone ? 'line-through' : '';
                titleSpan.style.opacity = isCurrentlyDone ? '0.55' : '';
            }
        }
    } else {
        // Refresh the subtask panel to pick up icon name change (circle ↔ check-circle-2)
        if (window.setTaskDetailInfoTab) window.setTaskDetailInfoTab('overview');
    }
};

window.openInlineSubtaskComposer = function () {
    const task = window.activeTaskDetail;
    const host = document.getElementById('taskDetailSubtaskHost');
    if (!task || !host) return;
    host.innerHTML = `<form class="inline-subtask-form" onsubmit="window.submitInlineSubtask(event)">
        <input class="form-control" id="inlineSubtaskTitle" required maxlength="180" placeholder="Subtask name">
        <input class="form-control inline-subtask-date" id="inlineSubtaskDue" type="date">
        <div class="inline-subtask-actions"><button type="button" class="btn btn-secondary" onclick="setTaskDetailInfoTab('overview')">Cancel</button><button class="btn btn-primary" type="submit">Add subtask</button></div>
    </form>`;
    document.getElementById('inlineSubtaskTitle')?.focus();
};

window.submitInlineSubtask = async function (event) {
    event.preventDefault();
    const parent = window.activeTaskDetail;
    const title = document.getElementById('inlineSubtaskTitle')?.value.trim();
    const due = document.getElementById('inlineSubtaskDue')?.value || null;
    if (!parent || !title) return;
    const submit = event.target.querySelector('button[type="submit"]');
    if (submit) submit.disabled = true;
    const result = await db.createTask(title, '', parent.assignee_id || currentUser.id, due, currentUser.id, parent.priority || 'medium', parent.category || 'General', { en: title, ar: `${title} (مترجم)` }, {}, null, null, null, parent.visibility || 'public', parent.project_id || null, [], parent.visible_to || [], null, null, null, 'todo', parent.supervisor_id || null, parent.department || null, parent.sub_type || null, [], parent.id, parent.marketing_department || null, [], [], null, parent.task_list_id || null);
    if (!result.success) {
        showToast(t('toast_failed_to_create_task') + (result.error?.message || ''), 'danger');
        if (submit) submit.disabled = false;
        return;
    }
    showToast(window.t('msg_toast_28') || 'Subtask added', 'success');
    if (result.data) window.taskCache[result.data.id] = { ...result.data, displayTitle: result.data.title, status: result.data.status || 'todo', priority: result.data.priority || 'medium' };
    setTaskDetailInfoTab('overview');
};

window.taskV2ChangeStage = async function (taskId, requestedStatus) {
    taskId = resolveTaskActionId(taskId);
    if (!taskId) return { error: new Error('Invalid task ID') };
    const task = window.taskCache?.[taskId];
    if (!task || task.status === requestedStatus) return;
    const previousStatus = task.status;
    const result = await window.handleUpdateTaskStatus(taskId, requestedStatus);
    if (result?.error) return;
    const actualStatus = result.status || requestedStatus;
    task.status = actualStatus;
    document.querySelectorAll(`[data-task-id="${taskId}"]`).forEach(node => {
        node.dataset.status = actualStatus;
        const select = node.querySelector('.task-v2-stage-select');
        if (select) select.value = actualStatus;
        if (node.id === `task-card-${taskId}`) {
            const target = document.getElementById(`col-${actualStatus}`);
            if (target) target.appendChild(node);
        }
    });
    if (previousStatus !== actualStatus) {
        const oldBadge = document.getElementById(`badge-${previousStatus === 'Pending Approval' ? 'pending' : previousStatus}`);
        const newBadge = document.getElementById(`badge-${actualStatus === 'Pending Approval' ? 'pending' : actualStatus}`);
        if (oldBadge) oldBadge.textContent = Math.max(0, Number(oldBadge.textContent || 0) - 1);
        if (newBadge) newBadge.textContent = Number(newBadge.textContent || 0) + 1;
    }
    // Sync the check icon colour and title strikethrough for list-view rows
    const isNowCompleted = actualStatus === 'completed' || actualStatus === 'Approved';
    window._applyTaskRowCompleteStyle?.(taskId, isNowCompleted);
    window.syncTaskStageEmptyStates?.();
    return result;
};

window.setTaskV2Mode = function (mode) {
    window.taskV2Mode = mode;
    document.getElementById('btn-v2-focus')?.classList.toggle('active', mode === 'focus');
    document.getElementById('btn-v2-board')?.classList.toggle('active', mode === 'board');
    
    const listContainer = document.getElementById('task-v2-rows-container');
    const boardContainer = document.getElementById('tasks-view-board');
    
    if (mode === 'focus') {
        if (listContainer) listContainer.style.display = '';
        if (boardContainer) boardContainer.style.display = 'none';
    } else {
        if (listContainer) listContainer.style.display = 'none';
        if (boardContainer) boardContainer.style.display = 'block';
    }
    window.filterTasksV2();
};

window.clearTaskV2Filters = function () {
    const search = document.getElementById('taskV2Search');
    const status = document.getElementById('taskV2StatusFilter');
    const priority = document.getElementById('taskV2PriorityFilter');
    const date = document.getElementById('taskV2DateFilter');
    if (search) search.value = '';
    if (status) status.value = 'all';
    if (priority) priority.value = 'all';
    if (date) date.value = '';
    window.taskV2SelectedProject = 'all';
    document.querySelectorAll('.task-v2-list-link').forEach((button, index) => button.classList.toggle('active', index === 0));
    window.filterTasksV2();
};

window.toggleAITaskMode = function () {
    const std = document.getElementById('standardTaskForm');
    const ai = document.getElementById('aiTaskForm');
    if (std.style.display === 'none') {
        std.style.display = 'flex';
        ai.style.display = 'none';
    } else {
        std.style.display = 'none';
        ai.style.display = 'flex';
    }
};

window.handleAICreateTask = async function (e) {
    e.preventDefault();
    const canCreateTask = !!currentUser;
    if (!canCreateTask) {
        showToast("You do not have permission to create tasks.", "danger");
        return;
    }
    const input = document.getElementById('aiTaskInput').value;
    if (!input) return;

    // Very basic heuristic parser (mock AI)
    let priority = 'medium';
    if (input.toLowerCase().includes('critical') || input.toLowerCase().includes('urgent')) priority = 'urgent';
    if (input.toLowerCase().includes('high priority')) priority = 'high';
    if (input.toLowerCase().includes('low priority')) priority = 'low';

    let due = new Date();
    if (input.toLowerCase().includes('tomorrow')) due.setDate(due.getDate() + 1);
    else if (input.toLowerCase().includes('friday')) {
        const day = due.getDay();
        const diff = (5 - day + 7) % 7 || 7;
        due.setDate(due.getDate() + diff);
    } else {
        due.setDate(due.getDate() + 3); // default 3 days
    }
    const dueStr = due.toISOString().split('T')[0];

    // Try to find a user name match
    let assigneeId = currentUser.id;
    const users = await db.fetchUsers();
    for (let u of users) {
        if (u.full_name && input.toLowerCase().includes(u.full_name.split(' ')[0].toLowerCase())) {
            assigneeId = u.id;
            break;
        }
    }
    // Administrators can create tasks in any list and are not constrained to
    // their own department manager as supervisor.
    const supervisorId = isTaskAdmin() ? null : (window.taskDepartmentSupervisors?.[0]?.id || null);
    const { success } = await db.createTask(input, '', assigneeId, dueStr, currentUser.id, priority, 'Auto-parsed', { 'en': input, 'ar': input + ' (مترجم)' }, {}, null, null, null, 'public', null, [], [], null, null, null, 'todo', supervisorId);
    if (success) {
        showToast(t('toast_ai_parsed_and_created_task'), "success");
        await db.triggerWebhooks('task_created', { title: input, assignee_id: assigneeId, due_date: dueStr, priority: priority, is_ai_parsed: true });
        renderView(currentView === 'tasks_v2' ? 'tasks_v2' : 'tasks');
    } else {
        showToast(t('toast_failed_to_create_task'), "danger");
    }
};

window.handleTaskProjectChange = function (prefix = 'new') {
    // We could filter tags based on the selected project, but for now we'll just log it.
    requestAnimationFrame(() => document.getElementById('taskTitle')?.focus());
};

// Open the Task Manager's creation modal and carry the currently selected list
// into the hidden form field. This keeps department task-list creation scoped
// to the list the employee selected instead of silently creating an unlisted
// task.
window.toggleTaskV2Create = function () {
    const modal = document.getElementById('createTaskModal');
    if (!modal) return;
    const selected = String(window.taskV2SelectedProject || 'all');
    const listId = selected.startsWith('list_') ? selected.slice(5) : '';
    const list = (window.taskListsCache || []).find(item => item.id === listId);
    const viewerDepartmentId = currentUserProfile?.department_id || (window.taskAllUsersCache || []).find(user => user.id === currentUser?.id)?.department_id;
    const canUseList = !listId || list?.owner_id === currentUser?.id || list?.can_add_users?.includes(currentUser?.id) || (list?.department_id && list.department_id === viewerDepartmentId) || isTaskAdmin();
    if (!canUseList) {
        showToast(window.t('msg_toast_29') || 'You do not have permission to add tasks to this list.', 'danger');
        return;
    }
    const listInput = document.getElementById('taskListId');
    if (listInput) listInput.value = canUseList ? listId : '';
    modal.classList.add('active');
    translateArabicInterface(modal);
    if (window.lucide) window.lucide.createIcons();
};

window.handleTaskDepartmentChange = function (prefix = 'new', value = '', selectedAssigneeId = '') {
    const selectedDepartment = (window.taskDepartmentsCache || []).find(item => item.id === value || item.name === value || getCanonicalDepartmentName(item) === value);
    const departmentName = getCanonicalDepartmentName(selectedDepartment) || value;
    updateTaskAssigneeOptions(prefix, departmentName, selectedAssigneeId);
    const subTypeGroup = document.getElementById(prefix === 'new' ? 'taskSubTypeGroup' : 'editTaskSubTypeGroup');
    if (!subTypeGroup) return;

    if (isMarketingTaskDepartment(departmentName)) {
        subTypeGroup.style.display = 'block';
        const select = document.getElementById(prefix === 'new' ? 'taskSubType' : 'editTaskSubType');
        if (select) select.required = true;
    } else {
        subTypeGroup.style.display = 'none';
        const select = document.getElementById(prefix === 'new' ? 'taskSubType' : 'editTaskSubType');
        if (select) { select.value = ''; select.required = false; }
        handleMarketingTaskTypeChange(prefix, '');
    }
};

function updateTaskAssigneeOptions(prefix, departmentName, selectedAssigneeId = '') {
    const select = document.getElementById(prefix === 'new' ? 'taskAssignee' : 'editTaskAssignee');
    if (!select || currentUserRole === 'EMPLOYEE') return;
    const department = (window.taskDepartmentsCache || []).find(item => item.name === departmentName || item.id === departmentName || getCanonicalDepartmentName(item) === departmentName);
    
    let employees = [];
    if (department) {
        employees = (window.taskAllUsersCache || []).filter(user => user.department_id === department.id);
    } else if (isTaskAdmin()) {
        employees = window.taskAllUsersCache || [];
    }

    select.innerHTML = `<option value="">${(department || isTaskAdmin()) ? (t('task_sel_emp') || 'Select Employee') : 'Select a department first'}</option>` + employees.map(user => {
        const label = window.formatEmployeeName(user) || user.id.substring(0, 8);
        return `<option value="${escapeHTML(user.id)}">${escapeHTML(label)} (${escapeHTML(localizeRuntimeText(user.role || 'EMPLOYEE'))})</option>`;
    }).join('');
    select.value = employees.some(user => user.id === selectedAssigneeId) ? selectedAssigneeId : '';
    handleTaskAssigneeChange(prefix);
    if (prefix === 'edit') window.filterEditTaskAssigneeOptions(department?.id || departmentName || '');
}

window.filterEditTaskAssigneeOptions = function (departmentIdOrName) {
    const root = document.getElementById('editTaskAssigneeOptions');
    if (!root) return;
    const department = (window.taskDepartmentsCache || []).find(item => item.id === departmentIdOrName || item.name === departmentIdOrName || getCanonicalDepartmentName(item) === departmentIdOrName);
    const users = department ? (window.taskAllUsersCache || []).filter(user => user.department_id === department.id) : [];
    const selected = new Set(Array.from(root.querySelectorAll('input[type="checkbox"]:checked')).map(input => input.value));
    root.innerHTML = `<label class="picker-select-all" for="editTaskAssigneeSelectAll"><input id="editTaskAssigneeSelectAll" type="checkbox" onchange="window.toggleEditTaskAssignees(this.checked)"><span>Select all employees</span></label>` + users.map((user, index) => {
        const inputId = `editTaskAssigneeOption-${index}`;
        return `<label for="${inputId}"><input id="${inputId}" type="checkbox" value="${escapeHTML(user.id)}" ${selected.has(user.id) ? 'checked' : ''} onchange="window.updateEditTaskSelectAllState('assignee')"><span>${escapeHTML(window.formatEmployeeName(user) || user.id)}</span></label>`;
    }).join('');
    window.updateEditTaskSelectAllState('assignee');
};

function renderTaskWatcherPicker(selectId, options = '') {
    return `<div class="task-watcher-picker" data-watcher-picker="${selectId}">
        <button type="button" class="form-control task-watcher-toggle" onclick="toggleTaskWatcherDropdown('${selectId}')" aria-expanded="false">Select watchers</button>
        <div class="task-watcher-dropdown multi-select-modal-layer" data-watcher-modal="${selectId}" hidden role="dialog" aria-modal="true" aria-label="Select watchers">
            <button type="button" class="multi-select-modal-backdrop" onclick="window.closeTaskWatcherDropdown('${selectId}')" aria-label="Close"></button>
            <section class="multi-select-modal-card">
                <header class="multi-select-modal-header"><div><span class="eyebrow">${currentLang === 'ar' ? 'صلاحية المهمة' : 'Task access'}</span><h3>${currentLang === 'ar' ? 'اختر المتابعين' : 'Select watchers'}</h3></div><button type="button" class="icon-btn" onclick="window.closeTaskWatcherDropdown('${selectId}')" aria-label="Close"><i data-lucide="x"></i></button></header>
                <input type="search" class="form-control task-watcher-search" placeholder="Search employees..." aria-label="Search employees" oninput="window.filterTaskWatchers('${selectId}', this.value)">
                <div class="task-watcher-options multi-select-modal-options"></div>
                <footer class="multi-select-modal-footer"><button type="button" class="btn btn-primary" onclick="window.closeTaskWatcherDropdown('${selectId}')">${currentLang === 'ar' ? 'تم' : 'Done'}</button></footer>
            </section>
        </div>
        <select id="${selectId}" multiple hidden>${options}</select>
    </div>`;
}
window.populateTaskWatcherPicker = function (selectId, options, selectedIds = []) {
    const select = document.getElementById(selectId);
    if (!select) return;
    select.innerHTML = options || '';
    Array.from(select.options).forEach(option => { option.selected = selectedIds.includes(option.value); });
    const picker = select.closest('.task-watcher-picker');
    const list = picker?.querySelector('.task-watcher-options');
    if (!list) return;
    list.innerHTML = `<label class="task-watcher-option picker-select-all" for="${selectId}-select-all"><input id="${selectId}-select-all" type="checkbox" onchange="window.toggleTaskWatcherSelectAll('${selectId}', this.checked)"><span>Select all employees</span></label>` + (select.options.length ? Array.from(select.options).map(option => `<label class="task-watcher-option" data-search="${escapeHTML(option.text.toLowerCase())}"><input type="checkbox" value="${escapeHTML(option.value)}" ${option.selected ? 'checked' : ''} onchange="syncTaskWatcherSelection('${selectId}', this)"><span>${escapeHTML(option.text)}</span></label>`).join('') : '<div class="multi-select-empty">No employees are available. Apply the company watcher directory migration and refresh.</div>');
    window.updateTaskWatcherSelectAll(selectId);
    updateTaskWatcherLabel(selectId);
};

window.toggleTaskWatcherDropdown = function (selectId) {
    const select = document.getElementById(selectId);
    const picker = select?.closest('.task-watcher-picker');
    let dropdown = picker?.querySelector('.task-watcher-dropdown') || document.querySelector(`[data-watcher-modal="${CSS.escape(selectId)}"]`);
    const button = picker?.querySelector('.task-watcher-toggle');
    if (!dropdown || !button) return;
    if (!picker.querySelector('.task-watcher-options input[type="checkbox"]')) {
        window.populateTaskWatcherPicker(selectId, select.innerHTML, Array.from(select.selectedOptions).map(option => option.value));
        dropdown = picker.querySelector('.task-watcher-dropdown');
    }
    if (dropdown?.parentElement !== document.body) document.body.appendChild(dropdown);
    dropdown.hidden = false;
    button.setAttribute('aria-expanded', 'true');
    document.body.classList.add('multi-select-modal-open');
    requestAnimationFrame(() => picker.querySelector('.task-watcher-search')?.focus());
};

window.closeTaskWatcherDropdown = function (selectId) {
    const select = document.getElementById(selectId);
    const picker = select?.closest('.task-watcher-picker');
    const dropdown = document.querySelector(`[data-watcher-modal="${CSS.escape(selectId)}"]`) || picker?.querySelector('.task-watcher-dropdown');
    if (dropdown) dropdown.hidden = true;
    if (dropdown && picker && dropdown.parentElement !== picker) picker.appendChild(dropdown);
    picker?.querySelector('.task-watcher-toggle')?.setAttribute('aria-expanded', 'false');
    document.body.classList.remove('multi-select-modal-open');
};

window.filterTaskWatchers = function (selectId, query) {
    const normalized = String(query || '').trim().toLowerCase();
    document.querySelector(`[data-watcher-modal="${CSS.escape(selectId)}"]`)?.querySelectorAll('.task-watcher-option').forEach(option => {
        if (option.classList.contains('picker-select-all')) { option.hidden = false; return; }
        option.hidden = !!normalized && !String(option.dataset.search || option.textContent || '').toLowerCase().includes(normalized);
    });
};

window.syncTaskWatcherSelection = function (selectId, checkbox) {
    const select = document.getElementById(selectId);
    const option = Array.from(select?.options || []).find(item => item.value === checkbox.value);
    if (option) option.selected = checkbox.checked;
    updateTaskWatcherLabel(selectId);
    window.updateTaskWatcherSelectAll(selectId);
};

window.toggleTaskWatcherSelectAll = function (selectId, checked) {
    const select = document.getElementById(selectId);
    const modal = document.querySelector(`[data-watcher-modal="${CSS.escape(selectId)}"]`);
    modal?.querySelectorAll('.task-watcher-options input[type="checkbox"]:not([id$="-select-all"])').forEach(input => {
        input.checked = checked;
        const option = Array.from(select?.options || []).find(item => item.value === input.value);
        if (option) option.selected = checked;
    });
    updateTaskWatcherLabel(selectId);
    window.updateTaskWatcherSelectAll(selectId);
};

window.updateTaskWatcherSelectAll = function (selectId) {
    const modal = document.querySelector(`[data-watcher-modal="${CSS.escape(selectId)}"]`);
    const master = modal?.querySelector(`#${CSS.escape(selectId)}-select-all`);
    const items = Array.from(modal?.querySelectorAll('.task-watcher-options input[type="checkbox"]') || []).filter(input => input !== master);
    if (master) master.checked = items.length > 0 && items.every(input => input.checked);
};

function updateTaskWatcherLabel(selectId) {
    const select = document.getElementById(selectId);
    const button = select?.closest('.task-watcher-picker')?.querySelector('.task-watcher-toggle');
    if (!select || !button) return;
    const selected = Array.from(select.selectedOptions);
    button.textContent = selected.length === 0 ? 'Select watchers' : selected.length === 1 ? selected[0].text : `${selected.length} watchers selected`;
}

function renderMarketingDesignFields(prefix) {
    const id = prefix === 'new' ? 'task' : 'editTask';
    return `
        <div class="marketing-design-grid">
            <div class="form-group"><label class="form-label">Download Source</label><div id="${id}ContentLinks" class="marketing-links-list"></div><button type="button" class="btn btn-secondary marketing-add-link" onclick="window.addMarketingLink('${id}ContentLinks')" disabled><i data-lucide="plus"></i> Add another URL</button></div>
            <div class="form-group"><label class="form-label">Upload Source</label><div id="${id}SubmissionLinks" class="marketing-links-list"></div><button type="button" class="btn btn-secondary marketing-add-link" onclick="window.addMarketingLink('${id}SubmissionLinks')" disabled><i data-lucide="plus"></i> Add another URL</button></div>
            <div class="form-group"><label class="form-label">Account</label><select id="${id}MarketingDepartment" class="form-control" required disabled><option value="">Select Account</option><option value="Party">Party</option><option value="Main">Main</option><option value="Coffee Corner">Coffee Corner</option></select></div>
            <div class="form-group"><label class="form-label">Design Type</label><select id="${id}ContentType" class="form-control" required disabled><option value="">Select Design Type</option><option value="Post">Post</option><option value="Reel">Reel</option><option value="Story">Story</option><option value="Promo Video">Promo Video</option><option value="Cover">Cover</option><option value="Commercial Video">Commercial Video</option><option value="Advertisement Video">Advertisement Video</option><option value="Proposal">Proposal</option></select></div>
        </div>`;
}

window.handleMarketingTaskTypeChange = function (prefix = 'new', value = '') {
    const container = document.getElementById(prefix === 'new' ? 'newMarketingDesignFields' : 'editMarketingDesignFields');
    if (!container) return;
    const active = value === 'Designing Task';
    container.style.display = active ? 'block' : 'none';
    const contentLinks = container.querySelector(`#${prefix === 'new' ? 'taskContentLinks' : 'editTaskContentLinks'}`);
    const submissionLinks = container.querySelector(`#${prefix === 'new' ? 'taskSubmissionLinks' : 'editTaskSubmissionLinks'}`);
    if (active && contentLinks && !contentLinks.children.length) window.addMarketingLink(contentLinks.id);
    if (active && submissionLinks && !submissionLinks.children.length) window.addMarketingLink(submissionLinks.id);
    container.querySelectorAll('input, textarea, select, button.marketing-add-link').forEach(field => {
        field.disabled = !active || (field.dataset.managerOnly === 'true' && !window.isMarketingDepartmentManager);
    });
    translateArabicInterface(container);
};

window.addMarketingLink = function (containerId, value = '') {
    const container = document.getElementById(containerId);
    if (!container) return;
    const row = document.createElement('div');
    row.className = 'marketing-link-row';
    row.innerHTML = `<input type="url" class="form-control" placeholder="https://..." value="${escapeHTML(value)}"><button type="button" class="btn btn-secondary" onclick="this.parentElement.remove()">${taskDetailText('Remove', 'إزالة')}</button>`;
    container.appendChild(row);
    translateArabicInterface(row);
};

function getMarketingLinks(containerId) {
    return Array.from(document.querySelectorAll(`#${containerId} input[type="url"]`)).map(input => input.value.trim()).filter(Boolean);
}

function setMarketingLinks(containerId, values = []) {
    const container = document.getElementById(containerId);
    if (!container) return;
    const links = Array.isArray(values) && values.length ? values : [''];
    container.innerHTML = '';
    links.forEach((value, index) => {
        const row = document.createElement('div'); row.className = 'marketing-link-row';
        row.innerHTML = `<input type="url" class="form-control" placeholder="https://..." value="${escapeHTML(value)}"><button type="button" class="btn btn-secondary" onclick="${index === 0 ? `addMarketingLink('${containerId}')` : 'this.parentElement.remove()'}">${index === 0 ? taskDetailText('Add', 'إضافة') : taskDetailText('Remove', 'إزالة')}</button>`;
        container.appendChild(row);
        translateArabicInterface(row);
    });
}

window.handleTaskAssigneeChange = async function (prefix = 'new') {
    const assigneeId = document.getElementById(prefix === 'new' ? 'taskAssignee' : 'editTaskAssignee').value;
    const designFields = document.getElementById(prefix === 'new' ? 'newDesignFields' : 'editDesignFields');
    if (!designFields) return;

    if (!assigneeId) {
        designFields.style.display = 'none';
        return;
    }

    const allUsers = await db.fetchUsers();
    const assignee = allUsers.find(u => u.id === assigneeId);
    if (!assignee) return;

    // Check if user is in Designing department
    const depts = await db.fetchDepartments();
    const userDept = depts.find(d => d.id === assignee.department_id);
    if (userDept && userDept.name.toLowerCase().includes('designing')) {
        designFields.style.display = 'flex';
    } else {
        designFields.style.display = 'none';
    }
};

window.openQuickAddModal = function(focusTarget) {
    const titleInput = document.getElementById('quickAddTaskInput');
    if (titleInput) {
        document.getElementById('taskTitle').value = titleInput.value;
        titleInput.value = '';
    }
    window.toggleTaskV2Create();
    
    // Focus appropriate field based on action clicked
    requestAnimationFrame(() => {
        if (focusTarget === 'more') document.getElementById('taskTitle')?.focus();
        else if (focusTarget === 'attach') document.getElementById('taskAttachment')?.focus();
        else if (focusTarget === 'tags') document.getElementById('taskTitle')?.focus(); // Tags not explicitly in create form yet
        else if (focusTarget === 'estimate') document.getElementById('taskTitle')?.focus(); // Est not in create form yet
    });
};

window.handleQuickAddTask = async function(e) {
    if (e.key !== 'Enter') return;
    e.preventDefault();

    const title = e.target.value.trim();
    if (!title) return;

    if (!currentUser) {
        showToast("You do not have permission to create tasks.", "danger");
        return;
    }

    const assigneeId = document.getElementById('quickAddAssignee')?.value || currentUser.id;
    const dueStr = document.getElementById('quickAddDate')?.value || null;
    const notify = document.getElementById('quickAddNotify')?.checked || false;
    const priority = document.getElementById('quickAddPriority')?.value || 'medium';
    
    // Disable input while processing
    e.target.disabled = true;
    
    const activeSelection = window.taskV2SelectedProject || 'all';
    const taskListId = activeSelection.startsWith('list_') ? activeSelection.slice(5) : null;
    const projectId = taskListId ? null : (activeSelection === 'all' || activeSelection.startsWith('list_') ? null : activeSelection);
    const supervisorId = window.taskDepartmentSupervisors?.[0]?.id || null;

    const { success, error, data: createdTask } = await db.createTask(
        title, '', assigneeId, dueStr, currentUser.id, priority, 'General', 
        { en: title, ar: title }, {}, null, null, null, 
        taskListId ? 'private' : 'public', 
        projectId, [], [], null, null, null, 'todo', 
        supervisorId, null, null, [], null, null, [], [], null, taskListId
    );

    if (success && createdTask) {
        // Handle estimate
        if (window.quickAddEstimate) {
            await db.updateTask(createdTask.id, { estimated_time: window.quickAddEstimate });
            window.quickAddEstimate = null;
        }

        // Handle files
        const filesInput = document.getElementById('quickAddFiles');
        if (filesInput && filesInput.files && filesInput.files.length > 0) {
            for (let i = 0; i < filesInput.files.length; i++) {
                await db.uploadTaskAttachment(createdTask.id, currentUser.id, filesInput.files[i]);
            }
        }
        showToast("Task created successfully.", "success");
        e.target.value = '';
        if (document.getElementById('quickAddDate')) document.getElementById('quickAddDate').value = '';
        if (document.getElementById('quickAddAssignee')) document.getElementById('quickAddAssignee').value = '';
        
        await db.triggerWebhooks('task_created', { title, assignee_id: assigneeId, due_date: dueStr, priority: 'medium', project_id: projectId, task_list_id: taskListId });
        
        // Notifications
        if (notify && assigneeId && assigneeId !== currentUser.id) {
            await db.createNotification(assigneeId, `You have been assigned a new task: ${title}`, createdTask?.id || null);
            await db.triggerWebhooks('task_activity_email', {
                type: 'assignment',
                task_id: createdTask?.id || null,
                task_title: title,
                assignee_id: assigneeId,
                comment_content: 'You have been assigned a new task.'
            });
            showToast("Notification sent to assignee.", "info");
        }
        
        
        // Refresh view
        renderView(currentView === 'tasks_v2' ? 'tasks_v2' : 'tasks');
    } else {
        showToast(error?.message || "Failed to create task", "danger");
    }
    
    e.target.disabled = false;
    e.target.focus();
};

window.handleCreateTask = async function (e) {
    e.preventDefault();

    const canCreateTask = !!currentUser;
    if (!canCreateTask) {
        showToast("You do not have permission to create tasks.", "danger");
        return;
    }

    const title = document.getElementById('taskTitle').value;
    const assignee = document.getElementById('taskAssignee').value;
    const due = document.getElementById('taskDue')?.value || null;
    const priority = 'medium'; // Default priority
    // Always fall back to the active sidebar selection. This covers modal
    // entry points that do not pass through toggleTaskV2Create first.
    const activeSelection = String(window.taskV2SelectedProject || 'all');
    const taskListId = document.getElementById('taskListId')?.value
        || (activeSelection.startsWith('list_') ? activeSelection.slice(5) : null);
    const projectId = taskListId ? null : (document.getElementById('taskProject')?.value || null);
    const supervisorId = window.taskDepartmentSupervisors?.[0]?.id || null;
    const effectiveAssignee = assignee || currentUser.id;
    const effectiveSupervisor = isTaskAdmin() || taskListId ? null : supervisorId;

    // Check if assignee is in Designing
    const allUsers = await db.fetchUsers();
    const assigneeObj = allUsers.find(u => u.id === effectiveAssignee);
    const depts = await db.fetchDepartments();
    const userDept = assigneeObj ? depts.find(d => d.id === assigneeObj.department_id) : null;
    const isDesigner = userDept && userDept.name.toLowerCase().includes('designing');

    let status = 'todo';
    const isHussain = currentUser.full_name && currentUser.full_name.toLowerCase().includes('hussain') || currentUser.email && currentUser.email.toLowerCase().includes('hussain');
    if (isDesigner && !isHussain) {
        status = 'Pending Approval';
    }

    let contentType = null, sourceLink = null, uploadLink = null;
    if (isDesigner) {
        contentType = document.getElementById('taskContentType')?.value || null;
        sourceLink = document.getElementById('taskSourceLink')?.value || null;
        uploadLink = document.getElementById('taskUploadLink')?.value || null;
    }

    // Default visibility if project is selected
    let visibleTo = [];
    if (projectId) {
        const proj = window.projectsCache.find(p => p.id === projectId);
        if (proj && proj.visible_to) {
            visibleTo = proj.visible_to;
        }
    }

    // Store the entered title without appending a broken placeholder
    // translation. It remains readable in both language modes until an
    // explicit localized title is supplied.
    const titleI18n = {
        'en': title,
        'ar': title
    };

    // Get department, sub-type, and watchers
    const department = document.getElementById('taskDepartment') ? document.getElementById('taskDepartment').value : null;
    const subTypeGroup = document.getElementById('taskSubTypeGroup');
    let subType = null;
    if (subTypeGroup && subTypeGroup.style.display !== 'none') {
        const taskType = document.getElementById('taskSubType');
        if (taskType?.value) subType = taskType.value;
    }
    const isMarketingDesign = isMarketingTaskDepartment(department) && subType === 'Designing Task';
    if (isMarketingDesign) status = 'review';
    const description = document.getElementById('taskDesc')?.value.trim() || '';
    const marketingDepartment = isMarketingDesign ? document.getElementById('taskMarketingDepartment')?.value : null;
    const contentLinks = isMarketingDesign ? getMarketingLinks('taskContentLinks') : [];
    const submissionLinks = isMarketingDesign ? getMarketingLinks('taskSubmissionLinks') : [];
    const deliveryStatus = isMarketingDesign && window.isMarketingDepartmentManager ? document.getElementById('taskDeliveryStatus')?.value || null : null;
    if (isMarketingDesign) {
        contentType = document.getElementById('taskContentType')?.value || null;
        sourceLink = document.getElementById('taskSourceLink')?.value || contentLinks[0] || null;
        uploadLink = document.getElementById('taskUploadLink')?.value || submissionLinks[0] || null;
    }
    const watchersSelect = document.getElementById('taskWatchers');
    let watchers = watchersSelect ? Array.from(watchersSelect.selectedOptions).map(opt => opt.value) : [];
    const parentTaskId = document.getElementById('taskParentId') ? document.getElementById('taskParentId').value || null : null;

    const finalDue = due;
    const repeatType = document.getElementById('taskRepeatType')?.value || 'NONE';
    const repeatInterval = document.getElementById('taskRepeatInterval')?.value || 1;
    const { success, data: createdTask, error } = await db.createTask(title, description, effectiveAssignee, finalDue, currentUser.id, priority, 'General', titleI18n, {}, null, null, null, taskListId ? 'private' : 'public', projectId, [], visibleTo, contentType, sourceLink, uploadLink, status, effectiveSupervisor, department, subType, watchers, parentTaskId, marketingDepartment, contentLinks, submissionLinks, deliveryStatus, taskListId, repeatType, repeatInterval);
    if (success) {
        showToast(t('toast_task_created_successfully'), "success");
        await db.triggerWebhooks('task_created', { title, assignee_id: effectiveAssignee, supervisor_id: effectiveSupervisor, due_date: due, priority, project_id: projectId, task_list_id: taskListId });
        if (status === 'Pending Approval') {
            const hussain = allUsers.find(u => u.full_name && u.full_name.toLowerCase().includes('hussain') || u.email && u.email.toLowerCase().includes('hussain'));
            if (hussain) {
                await db.createNotification(hussain.id, `A new task requires your approval: ${title}`, createdTask?.id || null);
            }
            showToast(t('toast_task_sent_to_hussain_for_approval'), "info");
        }

        const modal = document.getElementById('createTaskModal');
        if (modal) modal.classList.remove('active');

        renderView(currentView === 'tasks_v2' ? 'tasks_v2' : 'tasks');
    } else {
        showToast(t('toast_failed_to_create_task') + (error?.message || ''), "danger");
    }
};

window.handleUpdateTaskStatus = async function (id, status) {
    const task = window.taskCache ? window.taskCache[id] : null;
    let actualStatus = status;
    let needsManagerApproval = false;

    const isDepartmentManager = task && window.taskDepartmentManagerByName?.[task.department] === currentUser?.id;
    if (status === 'completed' && task && !isDepartmentManager) {
        actualStatus = 'Pending Approval';
        needsManagerApproval = true;
    }

    const { error } = await db.updateTaskStatus(id, actualStatus);
    if (error) {
        showToast(t('error_update_task') || "Failed to update task", "danger");
    } else {
        showToast(`Task updated`, "success");
        await db.triggerWebhooks('task_status_updated', { task_id: id, status: actualStatus });

        if (needsManagerApproval) {
            showToast(window.t('msg_toast_30') || 'Task moved to Awaiting Approval. The department manager has been notified.', 'info');
        }
    }
    return { error, status: actualStatus };
};

window.handleTaskDragStart = function (e, id) {
    e.dataTransfer.setData('text/plain', id);
    e.currentTarget.style.opacity = '0.5';
};

window.handleTaskDragOver = function (e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
};

window.syncTaskStageEmptyStates = function () {
    document.querySelectorAll('#tasks-view-board .task-column').forEach(column => {
        const hasTasks = !!column.querySelector('.task-item-card');
        const emptyState = column.querySelector('.task-stage-empty');
        if (hasTasks && emptyState) {
            emptyState.remove();
        } else if (!hasTasks && !emptyState) {
            const placeholder = document.createElement('div');
            placeholder.className = 'task-stage-empty';
            placeholder.innerHTML = '<i data-lucide="inbox"></i><span>No tasks here</span>';
            column.appendChild(placeholder);
        }
    });
    if (window.lucide) window.lucide.createIcons();
};

window.handleTaskDrop = async function (e, status) {
    e.preventDefault();
    const id = String(e.dataTransfer.getData('text/plain') || '').trim();
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
        console.warn('handleTaskDrop: ignored invalid task id', id);
        return;
    }

    const taskCard = document.getElementById(`task-card-${id}`);
    if (taskCard) {
        const currentStatus = taskCard.getAttribute('data-status');
        taskCard.style.opacity = '1';
        if (currentStatus === status) return; // No change

        const task = window.taskCache ? window.taskCache[id] : null;
        const isTaskDepartmentManager = task && window.taskDepartmentManagerByName?.[task.department] === currentUser?.id;
        // Only the department manager (or system admin) can approve a pending task.
        const isHussain = currentUser.full_name && currentUser.full_name.toLowerCase().includes('hussain') || currentUser.email && currentUser.email.toLowerCase().includes('hussain');
        if (currentStatus === 'Pending Approval' && status === 'completed' && currentUserRole !== 'ADMIN' && !isHussain && !isTaskDepartmentManager) {
            showToast(t('toast_you_do_not_have_permission_to_modify_pending_approval_tasks'), 'danger');
            return;
        }

        // Intercept completion requests from non-managers.
        let actualStatus = status;
        const isDepartmentManager = task && window.taskDepartmentManagerByName?.[task.department] === currentUser?.id;
        if (status === 'completed' && task && !isDepartmentManager) {
            actualStatus = 'Pending Approval';
        }

        // Optimistic UI update
        const targetCol = document.getElementById(`col-${actualStatus}`);
        if (targetCol) {
            targetCol.appendChild(taskCard);
            taskCard.setAttribute('data-status', actualStatus);

            const statusId = actualStatus === 'Pending Approval' ? 'pending' : actualStatus;
            const currentStatusId = currentStatus === 'Pending Approval' ? 'pending' : currentStatus;
            const oldBadge = document.getElementById(`badge-${currentStatusId}`);
            const newBadge = document.getElementById(`badge-${statusId}`);
            if (oldBadge) oldBadge.textContent = Math.max(0, parseInt(oldBadge.textContent) - 1);
            if (newBadge) newBadge.textContent = parseInt(newBadge.textContent) + 1;
            window.syncTaskStageEmptyStates();
        }
    }

    const finalStatus = taskCard ? taskCard.getAttribute('data-status') : status;
    const result = await window.handleUpdateTaskStatus(id, finalStatus);
    if (!result?.error && window.taskCache?.[id]) window.taskCache[id].status = result.status || finalStatus;
};

window.openEditTaskModal = async function (id) {
    try {
        const task = window.taskCache[id];
        if (!task) {
            console.error('Task not found in cache for ID:', id);
            return;
        }
        if (!isTaskAdmin() && task.created_by !== currentUser?.id) {
            showToast(window.t('msg_toast_31') || 'Only the task creator or an administrator can edit this task.', 'warning');
            return;
        }
        document.getElementById('taskSidePanel')?.classList.remove('active');
        document.getElementById('taskSidePanelOverlay')?.classList.remove('active');
        const taskPanel = document.getElementById('taskSidePanel');
        const taskPanelOverlay = document.getElementById('taskSidePanelOverlay');
        if (taskPanel) taskPanel.hidden = true;
        if (taskPanelOverlay) taskPanelOverlay.hidden = true;
        
        document.getElementById('editTaskId').value = task.id;
        document.getElementById('editTaskTitle').value = task.title || '';
        document.getElementById('editTaskDescription').value = task.description || '';
        document.getElementById('editTaskCategory').value = task.category || '';
        document.querySelector('.category-ui-value').textContent = task.category || 'No tags';

        document.getElementById('editTaskPriority').value = task.priority || 'medium';

        const formatDate = (dateStr) => {
            if (!dateStr) return '';
            const d = new Date(dateStr);
            if (isNaN(d.getTime())) return '';
            return d.toISOString().split('T')[0];
        };

        const start = formatDate(task.start_date);
        const due = formatDate(task.due_date);
        document.getElementById('editTaskStart').value = start;
        document.getElementById('editTaskDue').value = due;

        const est = task.estimated_time || '';
        document.getElementById('editTaskEstimate').value = est;
        document.querySelector('.estimate-ui-value').textContent = est || 'Not set';

        const vis = task.visibility || 'public';
        document.getElementById('editTaskVisibility').value = vis;

        const assigneeSelect = document.getElementById('editTaskAssignee');
        if (assigneeSelect) {
            assigneeSelect.value = task.assignee_id || '';
        }
        const assigneeIds = new Set(Array.isArray(task.assignee_ids) && task.assignee_ids.length ? task.assignee_ids : [task.assignee_id].filter(Boolean));
        const assigneeOptions = document.getElementById('editTaskAssigneeOptions');
        if (assigneeOptions) {
            assigneeOptions.innerHTML = `<label class="picker-select-all" for="editTaskAssigneeSelectAll"><input id="editTaskAssigneeSelectAll" type="checkbox" onchange="window.toggleEditTaskAssignees(this.checked)"><span>Select all employees</span></label>` + (window.taskAllUsersCache || []).map((user, index) => {
                const inputId = `editTaskAssigneeOption-${index}`;
                return `<label for="${inputId}"><input id="${inputId}" type="checkbox" value="${escapeHTML(user.id)}" ${assigneeIds.has(user.id) ? 'checked' : ''} onchange="window.updateEditTaskSelectAllState('assignee')"><span>${escapeHTML(window.formatEmployeeName(user) || user.id)}</span></label>`;
            }).join('');
            const all = assigneeOptions.querySelector('#editTaskAssigneeSelectAll');
            if (all) all.checked = assigneeOptions.querySelectorAll('input[type="checkbox"]:not(#editTaskAssigneeSelectAll)').length > 0 && assigneeOptions.querySelectorAll('input[type="checkbox"]:not(#editTaskAssigneeSelectAll):checked').length === assigneeOptions.querySelectorAll('input[type="checkbox"]:not(#editTaskAssigneeSelectAll)').length;
        }

        const watchersSelect = document.getElementById('editTaskWatchers');
        if (watchersSelect) {
            const selectedWatchers = new Set(Array.isArray(task.watchers) ? task.watchers : []);
            watchersSelect.innerHTML = (window.taskWatcherDirectoryCache || window.taskAllUsersCache || []).map(user =>
                `<option value="${escapeHTML(user.id)}" ${selectedWatchers.has(user.id) ? 'selected' : ''}>${escapeHTML(window.formatEmployeeName(user) || user.id)}</option>`
            ).join('');
            const watcherOptions = document.getElementById('editTaskWatchersOptions');
            if (watcherOptions) watcherOptions.innerHTML = `<label class="picker-select-all" for="editTaskWatcherSelectAll"><input id="editTaskWatcherSelectAll" type="checkbox" onchange="window.toggleEditTaskWatchers(this.checked)"><span>Select all followers</span></label>` + (window.taskAllUsersCache || []).map((user, index) => {
                const inputId = `editTaskWatcherOption-${index}`;
                return `<label for="${inputId}"><input id="${inputId}" type="checkbox" value="${escapeHTML(user.id)}" ${selectedWatchers.has(user.id) ? 'checked' : ''} onchange="window.syncEditTaskWatcher(this)"><span>${escapeHTML(window.formatEmployeeName(user) || user.id)}</span></label>`;
            }).join('');
            const all = watcherOptions.querySelector('#editTaskWatcherSelectAll');
            if (all) all.checked = watcherOptions.querySelectorAll('input[type="checkbox"]:not(#editTaskWatcherSelectAll)').length > 0 && watcherOptions.querySelectorAll('input[type="checkbox"]:not(#editTaskWatcherSelectAll):checked').length === watcherOptions.querySelectorAll('input[type="checkbox"]:not(#editTaskWatcherSelectAll)').length;
        }

        const progress = Math.max(0, Math.min(100, Number(task.progress ?? 0) || 0));
        const progressInput = document.getElementById('editTaskProgress');
        if (progressInput) progressInput.value = String(progress);
        const progressOutput = document.getElementById('editTaskProgressValue');
        if (progressOutput) progressOutput.value = `${progress}%`;

        // Update project options
        let selectProject = document.getElementById('editTaskProject');
        selectProject.innerHTML = `<option value="">No Project / Independent</option>`;
        (window.taskListsCache || []).forEach(list => {
            if (!list.is_archived) {
                let isSelected = task.task_list_id === list.id ? 'selected' : '';
                selectProject.innerHTML += `<option value="${list.id}" ${isSelected}>${escapeHTML(list.name)}</option>`;
                if (isSelected) {
                    document.getElementById('editTaskListLabel').textContent = list.name;
                }
            }
        });
        if(!task.task_list_id) document.getElementById('editTaskListLabel').textContent = 'No Project';

        // Custom task department
        let customDeptSelect = document.getElementById('editTaskDepartment');
        if (customDeptSelect) {
            customDeptSelect.innerHTML = `<option value="">None</option>`;
            (window.taskDepartmentsCache || window.departmentsCache || []).forEach(d => {
                const isSelected = task.task_department_id === d.id || task.department === d.name ? 'selected' : '';
                customDeptSelect.innerHTML += `<option value="${d.id}" ${isSelected}>${escapeHTML(d.name)}</option>`;
            });
            setTimeout(() => {
                const selectedDepartment = (window.taskDepartmentsCache || []).find(d => d.id === task.task_department_id || d.name === task.department);
                window.handleTaskDepartmentChange('edit', selectedDepartment?.id || '', task.assignee_id || '');
                if (task.task_sub_type) {
                    let subTypeSelect = document.getElementById('editTaskSubType');
                    if (subTypeSelect) {
                        subTypeSelect.value = task.task_sub_type;
                        handleMarketingTaskTypeChange('edit', task.task_sub_type, task.marketing_design_fields);
                    }
                }
                window.updateEditTaskSelectUI(customDeptSelect);
                window.updateEditTaskSelectUI(document.getElementById('editTaskSubType'));
            }, 50);
        }

        // Call UI updaters
        setTimeout(() => {
            window.updateEditTaskSelectUI(document.getElementById('editTaskAssignee'));
            window.updateEditTaskSelectUI(document.getElementById('editTaskVisibility'));
            window.updateEditTaskDateUI(document.getElementById('editTaskDue'));
            window.updateEditTaskPriorityUI(document.getElementById('editTaskPriority'));
            window.updateEditTaskWatchersUI(document.getElementById('editTaskWatchers'));
        }, 50);
            
        // Files - reset
        document.getElementById('editTaskFiles').value = '';
        document.getElementById('editTaskFilesList').innerHTML = '';

        const taskList = (window.taskListsCache || []).find(list => list.id === task.task_list_id);
        const canDeleteTask = isTaskAdmin() || task.created_by === currentUser?.id
            || (taskList?.can_delete_users || []).includes(currentUser?.id);
        const deleteBtn = document.getElementById('editTaskDeleteBtn');
        if (deleteBtn) {
            deleteBtn.style.display = canDeleteTask ? '' : 'none';
        }

        prepareTeamworkEditModal(task);
        const editTaskModal = document.getElementById('editTaskModal');
        translateArabicInterface(editTaskModal);
        editTaskModal.classList.add('active');
        if(window.lucide) window.lucide.createIcons();
    } catch (err) {
        console.error('Error in openEditTaskModal:', err);
        window.showAppMessageModal('Error opening edit modal. Check console for details.');
    }
};

function prepareTeamworkEditModal(task) {
    // Removed old teamwork modal hack, as the new modal design supports tabs natively.
}

window.setEditTaskTab = function (tab) {
    const modal = document.getElementById('editTaskModal');
    if (!modal) return;
    modal.dataset.editTab = tab;
    modal.querySelectorAll('.teamwork-edit-tabs button').forEach((button, index) => button.classList.toggle('active', tab === 'details' ? index === 0 : index === 1));
    modal.querySelectorAll('.edit-task-advanced').forEach(field => field.style.display = tab === 'advanced' ? '' : 'none');
    const marketingFields = document.getElementById('editMarketingDesignFields');
    if (marketingFields && tab === 'advanced') handleMarketingTaskTypeChange('edit', document.getElementById('editTaskSubType')?.value || '');
};

window.handleEditTaskSubmit = async function (e) {
    e.preventDefault();
    const id = document.getElementById('editTaskId').value;
    const taskBeingEdited = window.taskCache?.[id];
    if (!taskBeingEdited || (!isTaskAdmin() && taskBeingEdited.created_by !== currentUser?.id)) {
        showToast(window.t('msg_toast_31') || 'Only the task creator or an administrator can edit this task.', 'warning');
        return;
    }
    const title = document.getElementById('editTaskTitle').value;
    const category = document.getElementById('editTaskCategory').value;

    const priority = document.getElementById('editTaskPriority').value;
    const assigneeId = document.getElementById('editTaskAssignee').value;
    const selectedAssigneeIds = Array.from(document.querySelectorAll('#editTaskAssigneeOptions input[type="checkbox"]:checked:not(#editTaskAssigneeSelectAll)')).map(input => input.value);
    const assigneeIds = selectedAssigneeIds.length ? selectedAssigneeIds : (assigneeId ? [assigneeId] : []);
    const primaryAssigneeId = assigneeIds[0] || assigneeId;
    const dueDate = document.getElementById('editTaskDue').value || null;

    const visibility = document.getElementById('editTaskVisibility').value;
    const startDate = document.getElementById('editTaskStart').value;
    const estimate = document.getElementById('editTaskEstimate').value;
    const projectId = document.getElementById('editTaskProject').value || null;

    // Check Designer status
    const allUsers = await db.fetchUsers();
    const assigneeObj = allUsers.find(u => u.id === assigneeId);
    let isDesigner = false;
    if (assigneeObj) {
        const depts = await db.fetchDepartments();
        const userDept = depts.find(d => d.id === assigneeObj.department_id);
        if (userDept && userDept.name.toLowerCase().includes('designing')) {
            isDesigner = true;
        }
    }

    const updates = {
        title: title,
        description: document.getElementById('editTaskDescription').value.trim(),
        category: category || null,
        priority: priority,
        assignee_id: primaryAssigneeId,
        assignee_ids: assigneeIds,
        due_date: dueDate,
        visibility: visibility,
        start_date: startDate || null,
        estimated_time: estimate || null,
        project_id: projectId
    };

    if (projectId) {
        const proj = window.projectsCache.find(p => p.id === projectId);
        if (proj && proj.visible_to) {
            updates.visible_to = proj.visible_to;
        }
    }

    // Get department, sub-type, and watchers
    const departmentEl = document.getElementById('editTaskDepartment');
    if (departmentEl) updates.task_department_id = departmentEl.value || null;

    const subTypeEl = document.getElementById('editTaskSubType');
    if (subTypeEl && document.getElementById('editTaskSubTypeGroupWrap').style.display !== 'none') {
        updates.task_sub_type = subTypeEl.value || null;
    } else {
        updates.task_sub_type = null;
    }
    
    // In our DB schema, these are task_department_id and task_sub_type 
    // We already mapped them above. Now handle marketing fields.
    const isMarketingDesign = updates.task_sub_type === 'Designing Task';
    if (isMarketingDesign) {
        updates.marketing_department = document.getElementById('editTaskMarketingDepartment')?.value || null;
        updates.content_type = document.getElementById('editTaskContentType')?.value || null;
        updates.description = document.getElementById('editTaskDesignDescription').value.trim();
        updates.content_links = getMarketingLinks('editTaskContentLinks');
        updates.submission_links = getMarketingLinks('editTaskSubmissionLinks');
        updates.source_link = updates.content_links[0] || null;
        updates.upload_link = updates.submission_links[0] || null;
        if (window.isMarketingDepartmentManager) {
            updates.delivery_status = document.getElementById('editTaskDeliveryStatus').value || null;
        }
    } else {
        updates.marketing_department = null;
        updates.content_type = null;
        updates.content_links = null;
        updates.submission_links = null;
        updates.source_link = null;
        updates.delivery_status = null;
    }
    
    const watchersSelect = document.getElementById('editTaskWatchers');
    if (watchersSelect) {
        updates.watchers = Array.from(watchersSelect.selectedOptions).map(opt => opt.value);
    }
    
    // Handle File Uploads
    const filesInput = document.getElementById('editTaskFiles');
    if (filesInput && filesInput.files.length > 0) {
        let uploadedUrls = [];
        try {
            const uploadBtn = document.querySelector('#editTaskModal button[type="submit"]');
            const originalText = uploadBtn.textContent;
            uploadBtn.textContent = 'Uploading...';
            uploadBtn.disabled = true;
            
            for (let i = 0; i < filesInput.files.length; i++) {
                const file = filesInput.files[i];
                const fileExt = file.name.split('.').pop();
                const fileName = `${Math.random().toString(36).substring(2, 15)}_${Date.now()}.${fileExt}`;
                const filePath = `task_attachments/${fileName}`;
                const { error: uploadError } = await window.supabaseClient.storage.from('hr-documents').upload(filePath, file);
                if (!uploadError) {
                    const { data: { publicUrl } } = window.supabaseClient.storage.from('hr-documents').getPublicUrl(filePath);
                    uploadedUrls.push(publicUrl);
                } else {
                    console.error('File upload error:', uploadError);
                }
            }
            
            if (uploadedUrls.length > 0) {
                const task = window.taskCache[id];
                updates.file_links = (task.file_links || []).concat(uploadedUrls);
            }
            
            uploadBtn.textContent = originalText;
            uploadBtn.disabled = false;
        } catch (e) {
            console.error('File upload failed:', e);
        }
    }

    const task = window.taskCache[id];
    let titleI18n = task.title_i18n || {};
    titleI18n['en'] = title;
    if (currentLang !== 'en') {
        titleI18n[currentLang] = title;
    }
    updates.title_i18n = titleI18n;

    const { error } = await db.updateTask(id, updates);

    if (error) {
        showToast(t('toast_failed_to_update_task_details'), "danger");
    } else {
        showToast(t('toast_task_updated_successfully'), "success");
        await db.triggerWebhooks('task_updated', { task_id: id, updates: updates });
        document.getElementById('editTaskModal').classList.remove('active');
        await renderView(currentView === 'tasks_v2' ? 'tasks_v2' : 'tasks');
        if (window.taskCache?.[id]) openTaskDetailsModal(id);
    }
};

window.handleDeleteTask = async function (id) {
    const task = window.taskCache?.[id];
    const taskList = task ? (window.taskListsCache || []).find(list => list.id === task.task_list_id) : null;
    const canDeleteTask = !!task && (isTaskAdmin() || task.created_by === currentUser?.id
        || (taskList?.can_delete_users || []).includes(currentUser?.id));
    if (!canDeleteTask) {
        showToast(window.t('msg_toast_32') || 'Only the task creator or an administrator can delete this task.', 'warning');
        return;
    }
    window.showConfirmModal("Delete Task", t('confirm_delete') || "Are you sure you want to delete this task?", async () => {
        const { error } = await db.deleteTask(id);
        if (error) {
            showToast(t('toast_failed_to_delete_task'), "danger");
        } else {
            showToast(t('toast_task_deleted_successfully'), "success");
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
        if (employeeId === currentUser?.id) {
            window.handlePrintContract(employeeId);
        } else {
            showToast(window.t('msg_toast_33') || 'Only an HR Manager or Administrator can edit contracts.', 'danger');
        }
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
    
    const htmlContent = await renderContractPage();
    
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

window.toggleTaskAssigneePickerAll = function (checked) {
    document.querySelectorAll('#taskAssigneePickerOptions input[type="checkbox"]:not(#taskAssigneeSelectAll)').forEach(input => { input.checked = checked; });
    window.updateTaskAssigneePickerSelectAll();
};
window.updateTaskAssigneePickerSelectAll = function () {
    const root = document.getElementById('taskAssigneePickerOptions');
    const master = root?.querySelector('#taskAssigneeSelectAll');
    if (!root || !master) return;
    const items = Array.from(root.querySelectorAll('input[type="checkbox"]')).filter(input => input !== master);
    master.checked = items.length > 0 && items.every(input => input.checked);
};

window.handleSaveContract = async function (e) {
    e.preventDefault();
    const viewerProfile = await db.getUserProfile(currentUser?.id);
    if (!window.canCurrentUserEditContracts(viewerProfile)) {
        showToast(window.t('msg_toast_33') || 'Only an HR Manager or Administrator can edit contracts.', 'danger');
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
        status: document.getElementById('contractStatus').value,
        edited_by: window.formatEmployeeName(currentUserProfile) || null
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
        if (document.getElementById('contractEditModal') && document.getElementById('contractEditModal').style.display !== 'none') {
            document.getElementById('contractEditModal').style.display = 'none';
            if (currentView === 'users' || currentView === 'employees') {
                renderView(currentView);
            }
        } else {
            currentView = 'users';
            renderView('users');
        }

    } else {
        showToast(error?.message || "Failed to save contract", "danger");
    }
}

async function renderContractPage() {
    const viewerProfile = await db.getUserProfile(currentUser?.id);
    if (!window.canCurrentUserEditContracts(viewerProfile)) {
        return `<div class="card" style="padding:2rem;">Only an HR Manager or Administrator can edit contracts.</div>`;
    }
    if (!currentContractEmployeeId) {
        return `<div class="card">${t('notif_no_found')}</div>`;
    }

    // Fetch existing contract and user profile
    const [contract, userProfile, departments, jobTitles] = await Promise.all([
        db.fetchContractByEmployeeId(currentContractEmployeeId),
        db.getUserProfile(currentContractEmployeeId),
        db.fetchDepartments(),
        db.fetchJobTitles()
    ]);
    window.contractJobTitlesCache = jobTitles || [];

    // Default values if no contract exists
    const contractType = contract?.contract_type || 'Full-time';
    const nationality = contract?.nationality || userProfile?.nationality || 'Saudi';
    const selectedDepartmentId = contract?.department_id || userProfile?.department_id || '';
    const selectedDepartment = departments.find(department => department.id === selectedDepartmentId);
    const jobTitle = contract?.job_title || contract?.job_title_en || userProfile?.job_title || '';
    const displayNameAr = userProfile?.display_name_ar || '';
    const identityNumber = contract?.identity_number || userProfile?.iqama_number || '';
    const employeePhone = contract?.employee_phone || userProfile?.phone_number || '';
    const startDate = contract?.start_date || '';
    const endDate = contract?.end_date || '';
    const salary = contract?.salary || '';
    const housing = contract?.housing_allowance || '';
    const transport = contract?.transportation_allowance || '';
    const other = contract?.other_allowances || '';
    const hours = contract?.working_hours || '8 hours/day';
    const probation = contract?.probation_period_days || 90;
    const notice = contract?.notice_period_days || 30;
    const leave = contract?.annual_leave_days || 30;
    const status = contract?.status || 'Active';
    const workplace = contract?.primary_workplace || contract?.workplace_location || '';
    const restDays = contract?.weekly_rest_day || contract?.rest_days || 'Friday, Saturday';
    const confidentialityPolicyUrl = contract?.confidentiality_policy_url || '';
    const storedContractDocuments = contract?.id ? await db.fetchContractDocuments(contract.id) : [];
    const contractDocuments = [];
    const addContractDocument = (url, label) => {
        if (!url || contractDocuments.some(document => document.url === url)) return;
        let fileName = label;
        try { fileName = decodeURIComponent(new URL(url).pathname.split('/').pop() || label).replace(/^\d+-/, ''); } catch (_) { }
        const separator = String(url).includes('?') ? '&' : '?';
        contractDocuments.push({ url, fileName, downloadUrl: `${url}${separator}download=${encodeURIComponent(fileName)}` });
    };
    addContractDocument(confidentialityPolicyUrl, 'Company Policy and Regulations');
    addContractDocument(contract?.policy_document_url, 'Contract Policy Document');
    (Array.isArray(contract?.attachment_urls) ? contract.attachment_urls : []).forEach((url, index) => addContractDocument(url, `Contract attachment ${index + 1}`));
    storedContractDocuments.forEach(document => addContractDocument(document.file_url, document.file_name || 'Contract document'));
    const departmentOptions = `<option value="">Select Department</option>${departments.map(department => `<option value="${department.id}" ${department.id === selectedDepartmentId ? 'selected' : ''}>${escapeHTML(department.name)}</option>`).join('')}`;
    const contractTitleOptions = `<option value="">Select Job Title</option>${(jobTitles || []).filter(title => title.department_id === selectedDepartmentId).map(title => `<option value="${escapeHTML(title.name)}" ${title.name === jobTitle ? 'selected' : ''}>${escapeHTML(title.name)}</option>`).join('')}`;

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('users_contract') || 'Contract'}</h1>
                <p class="page-subtitle">${currentContractEmployeeName}</p>
            </div>
            <button class="btn-secondary" onclick="currentView='users'; renderView('users');">
                <i data-lucide="arrow-left" style="width:16px;height:16px;margin-right:4px;"></i> Back to Users
            </button>
        </div>

        <div class="fade-in-up" style="max-width: 900px; margin: 0 auto; padding-bottom: 2rem;">
            <form autocomplete="off" onsubmit="handleSaveContract(event)" style="display: flex; flex-direction: column; gap: 1.5rem;">
                
                <!-- Basic Information -->
                <div class="card">
                    <h3 style="margin-top: 0; margin-bottom: 1.5rem; color: var(--color-primary); font-size: 1.1rem; display: flex; align-items: center; gap: 0.5rem; border-bottom: 1px solid var(--color-border); padding-bottom: 0.75rem;">
                        <i data-lucide="file-text" style="width: 18px; height: 18px;"></i>
                        ${t('contract_basic_info') || 'Basic Information'}
                    </h3>
                    <div class="dashboard-grid">
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">Employee Name (Arabic)</label>
                            <input type="text" id="contractEmployeeNameAr" class="form-control" value="${escapeHTML(displayNameAr)}" placeholder="الاسم بالعربية">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('prof_iqama')}</label>
                            <input type="text" id="contractIdentityNumber" class="form-control" value="${escapeHTML(identityNumber)}" required>
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('prof_phone')}</label>
                            <input type="tel" id="contractEmployeePhone" class="form-control" value="${escapeHTML(employeePhone)}" required>
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">Department</label>
                            <select id="contractDepartment" class="form-control" required onchange="handleContractDepartmentChange(this.value)">${departmentOptions}</select>
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('users_job_title') || 'Job Title'}</label>
                            <select id="contractJobTitle" class="form-control" required>${contractTitleOptions}</select>
                        </div>
                        <input type="hidden" id="contractType" value="${escapeHTML(contractType || 'Full-time')}">
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_nationality') || 'Nationality'}</label>
                            <select id="contractNationality" class="form-control" disabled>
                                <option value="Saudi" ${nationality === 'Saudi' ? 'selected' : ''}>Saudi</option>
                                <option value="Non-Saudi" ${nationality === 'Non-Saudi' ? 'selected' : ''}>Non-Saudi</option>
                            </select>
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_status')}</label>
                            <select id="contractStatus" class="form-control" required>
                                <option value="Active" ${status === 'Active' ? 'selected' : ''}>${t('contract_active') || 'Active'}</option>
                                <option value="Terminated" ${status === 'Terminated' ? 'selected' : ''}>${t('contract_term') || 'Terminated'}</option>
                                <option value="Expired" ${status === 'Expired' ? 'selected' : ''}>${t('contract_exp') || 'Expired'}</option>
                            </select>
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_start')}</label>
                            <input type="date" id="contractStartDate" class="form-control" required value="${startDate}">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_end')}</label>
                            <input type="date" id="contractEndDate" class="form-control" value="${endDate}">
                        </div>
                    </div>
                </div>

                <!-- Compensation -->
                <div class="card">
                    <h3 style="margin-top: 0; margin-bottom: 1.5rem; color: var(--color-primary); font-size: 1.1rem; display: flex; align-items: center; gap: 0.5rem; border-bottom: 1px solid var(--color-border); padding-bottom: 0.75rem;">
                        <i data-lucide="banknote" style="width: 18px; height: 18px;"></i>
                        ${t('contract_compensation') || 'Compensation & Allowances'}
                    </h3>
                    <div class="dashboard-grid">
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">Monthly Salary</label>
                            <input type="number" id="contractSalary" class="form-control" step="0.01" value="${salary}" placeholder="0.00">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_housing')}</label>
                            <input type="number" id="contractHousing" class="form-control" step="0.01" value="${housing}" placeholder="0.00">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_transport')}</label>
                            <input type="number" id="contractTransport" class="form-control" step="0.01" value="${transport}" placeholder="0.00">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_other')}</label>
                            <input type="number" id="contractOther" class="form-control" step="0.01" value="${other}" placeholder="0.00">
                        </div>
                    </div>
                </div>

                <!-- Terms & Conditions -->
                <div class="card">
                    <h3 style="margin-top: 0; margin-bottom: 1.5rem; color: var(--color-primary); font-size: 1.1rem; display: flex; align-items: center; gap: 0.5rem; border-bottom: 1px solid var(--color-border); padding-bottom: 0.75rem;">
                        <i data-lucide="scale" style="width: 18px; height: 18px;"></i>
                        ${t('contract_terms') || 'Terms & Conditions'}
                    </h3>
                    <div class="dashboard-grid">
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_hours')}</label>
                            <input type="text" id="contractHours" class="form-control" placeholder="e.g. 8 hours/day" value="${hours}">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_probation')}</label>
                            <input type="number" id="contractProbation" class="form-control" value="${probation}">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_leave')}</label>
                            <input type="number" id="contractLeave" class="form-control" value="${leave}">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">Workplace Location</label>
                            <input type="text" id="contractWorkplace" class="form-control" value="${escapeHTML(workplace)}" placeholder="Office or worksite location">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">Rest Days</label>
                            <input type="text" id="contractRestDays" class="form-control" value="${escapeHTML(restDays)}" placeholder="e.g. Friday, Saturday">
                        </div>
                    </div>
                </div>

                <div class="card">
                    <h3 style="margin-top:0; margin-bottom:1.5rem; border-bottom:1px solid var(--color-border); padding-bottom:.75rem;">Termination &amp; Notice Period</h3>
                    <div class="form-group">
                        <label class="form-label">Notice Period (Days)</label>
                        <input type="number" id="contractNotice" class="form-control" min="0" value="${notice}">
                    </div>
                </div>

                <div class="card">
                    <h3 style="margin-top:0; margin-bottom:1.5rem; border-bottom:1px solid var(--color-border); padding-bottom:.75rem;">Additional / Optional Clauses</h3>
                    <input type="hidden" id="existingContractPolicyUrl" value="${escapeHTML(confidentialityPolicyUrl)}">
                    <div class="form-group">
                        <label class="form-label" for="contractPolicyDocument">Confidentiality Clause â€” Company Policy and Regulations</label>
                        <input type="file" id="contractPolicyDocument" class="form-control" accept=".pdf,.doc,.docx,image/*" multiple>
                        ${confidentialityPolicyUrl ? `<small>Current document: <a href="${escapeHTML(confidentialityPolicyUrl)}" target="_blank" rel="noopener noreferrer">View uploaded policy</a></small>` : '<small>Optional. Accepted formats: PDF, Word, or image.</small>'}
                    </div>
                </div>

                <div class="card contract-documents-card">
                    <h3><i data-lucide="folder-open"></i> Uploaded Contract Files <span class="status-badge info">${contractDocuments.length}</span></h3>
                    ${contractDocuments.length ? `<div class="contract-document-list">${contractDocuments.map(document => `
                        <div class="contract-document-row">
                            <div class="contract-document-info"><i data-lucide="file-text"></i><div><strong>${escapeHTML(document.fileName)}</strong><small>Contract document</small></div></div>
                            <div class="contract-document-actions">
                                <a class="btn btn-secondary" href="${escapeHTML(document.url)}" target="_blank" rel="noopener noreferrer"><i data-lucide="eye"></i> View</a>
                                <a class="btn btn-primary" href="${escapeHTML(document.downloadUrl)}" download="${escapeHTML(document.fileName)}"><i data-lucide="download"></i> Download</a>
                            </div>
                        </div>`).join('')}</div>` : '<div class="contract-document-empty"><i data-lucide="file-x"></i><span>No files have been uploaded for this contract.</span></div>'}
                </div>

                <!-- Action Buttons -->
                <div style="display: flex; justify-content: flex-end; gap: 1rem; margin-top: 0.5rem;">
                    <button type="button" class="btn-secondary" onclick="currentView='users'; renderView('users');">${t('contract_cancel') || 'Cancel'}</button>
                    <button type="submit" class="btn-primary" style="min-width: 150px;">
                        <i data-lucide="save" style="width:16px;height:16px;margin-right:8px;"></i> ${t('contract_save') || 'Save Contract'}
                    </button>
                </div>
            </form>
        </div>
    `;
}

async function renderEmployeesDirectory() {
    const [users, viewerProfile, printRequests] = await Promise.all([
        db.fetchUsers(),
        db.getUserProfile(currentUser?.id),
        db.fetchContractPrintRequests({ managerId: currentUser?.id, status: 'PENDING' })
    ]);
    const canEditContracts = window.canCurrentUserEditContracts(viewerProfile);
    const canApprovePrints = currentUserRole === 'ADMIN' || currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR';
    const pendingPrintRequests = canApprovePrints ? printRequests : [];

    // Directory is visible to everyone, but we only show basic info.

    // Only Admins or the Manager themselves can see team members' contracts
    // For now, let's allow ADMIN to see all, Manager to see their team
    let visibleUsers = users;
    if (canEditContracts) {
        visibleUsers = users;
    } else if ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR') {
        visibleUsers = users.filter(u => u.manager_id === currentUser.id || u.id === currentUser.id);
    } else {
          // Employees see ONLY themselves
          visibleUsers = users.filter(u => u.id === currentUser.id);
      }
    window.currentAdminUsers = visibleUsers;

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('nav_emp_dir')}</h1>
                <p class="page-subtitle">${t('emp_dir_sub')}</p>
            </div>
        </div>
        <div class="card fade-in-up" style="padding: .5rem; margin-bottom: 1rem; display: flex; gap: .5rem;">
            <button class="btn-primary" type="button" aria-current="page"><i data-lucide="users"></i> ${t("active_contracts")}</button>
            <button class="btn-secondary" type="button" onclick="window.downloadUserDirectoryExcel()" title="Download user directory as Excel"><i data-lucide="download"></i> Download Excel</button>
            ${canEditContracts ? `<button class="btn-secondary" type="button" onclick="renderView('archived_contracts')"><i data-lucide="archive"></i> ${t("archived_contracts")}</button>` : ''}
        </div>
        ${pendingPrintRequests.length ? `
        <div class="card fade-in-up contract-print-requests">
            <div class="card-title"><i data-lucide="printer-check"></i> ${t('profile_print_requests')}</div>
            ${pendingPrintRequests.map(request => {
                const employee = users.find(user => user.id === request.employee_id);
                return `<div class="contract-print-request-row">
                    <span>${escapeHTML(window.formatEmployeeName(employee))}</span>
                    <div>
                        <button class="btn btn-primary btn-sm" onclick="handleContractPrintDecision('${request.id}', 'APPROVED')">${t('ui_approve')}</button>
                        <button class="btn btn-secondary btn-sm" onclick="handleContractPrintDecision('${request.id}', 'REJECTED')">${t('ui_reject')}</button>
                    </div>
                </div>`;
            }).join('')}
        </div>` : ''}
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-12">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem; flex-wrap: wrap; gap: 1rem;">
                    <div class="card-title" style="margin-bottom: 0;">${t('emp_dir_company')}</div>
                    <div style="position: relative;">
                        <i data-lucide="search" style="position: absolute; left: 0.75rem; top: 50%; transform: translateY(-50%); width: 16px; height: 16px; color: var(--text-light);"></i>
                        <input type="text" id="employeeSearchInput" class="form-control" placeholder="${t('search') || 'Search employees...'}" style="padding-left: 2.25rem; width: 250px;" onkeyup="filterEmployees()">
                    </div>
                </div>
                <div class="table-responsive">
                    <table class="data-table" id="employeeDirectoryTable">
                        <thead>
                            <tr>
                                <th>ID</th><th>Employee Details</th><th>Role</th><th>${t('edited_by') || 'Edited By'}</th><th>${t('actions') || 'Actions'}</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${visibleUsers.map(u => `
                                <tr data-user-row="${u.id}">
                                    <td data-user-id><span class="directory-employee-id">${escapeHTML(formatEmployeeId(u.emp_index))}</span></td>
                                    <td data-user-details><div class="directory-employee-name">${escapeHTML(window.formatEmployeeName(u) || t('emp_na'))}</div></td>
                                    <td data-user-role><span data-user-role-badge class="status-badge ${u.role === 'ADMIN' ? 'success' : (u.role === 'MANAGER' ? 'warning' : 'info')}">${escapeHTML(u.role || 'EMPLOYEE')}</span></td>
                                    <td>${escapeHTML(u.contract_edited_by || '-')}</td>
                                    <td>
                                        <div class="directory-actions">
                                            <button type="button" class="btn-secondary btn-sm directory-view-button" onclick="window.showEmployeeDetailsCard('${u.id}')" title="View employee details"><i data-lucide="eye"></i><span>View</span></button>
                                            ${canEditContracts ? `<button type="button" class="btn-primary btn-sm directory-edit-button" onclick="window.showEditUserModal('${u.id}')" title="Edit user"><i data-lucide="user-pen"></i><span>Edit</span></button>` : ''}
                                            <button type="button" class="btn-secondary btn-sm" onclick="navigateToContract('${u.id}', '${(window.formatEmployeeName(u) || 'Employee').replace(/'/g, "\\'")}')" title="${canEditContracts ? 'Edit Contract' : 'View Contract'}"><i data-lucide="file-signature"></i><span>${canEditContracts ? 'Edit Contract' : 'View Contract'}</span></button>
                                            ${canEditContracts ? `<button type="button" class="btn-secondary btn-sm" style="color:var(--color-danger)" onclick="handleDeleteContract('${u.id}')" title="Delete Contract"><i data-lucide="trash-2"></i><span>Delete Contract</span></button>` : ''}
                                        </div>
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    `;
}

window.handleDeleteContract = async function(employeeId) {
    const viewerProfile = await db.getUserProfile(currentUser?.id);
    if (!window.canCurrentUserEditContracts(viewerProfile)) {
        showToast(window.t('msg_toast_34') || 'Only an HR Manager or Administrator can delete contracts.', 'danger');
        return;
    }
    const contract = await db.fetchContractByEmployeeId(employeeId);
    if (!contract || !contract.id) {
        showToast("No active contract found for this employee.", "info");
        return;
    }
    window.showConfirmModal('Delete Contract', 'Are you sure you want to permanently delete this contract? This action cannot be undone.', async () => {
        const result = await db.deleteContractByEmployeeId(employeeId);
        if (result.success) {
            showToast(window.t('msg_toast_35') || 'Contract deleted successfully.', 'success');
            delete window.viewHTMLCache.employees;
            renderView('employees');
        } else {
            showToast(result.error?.message || 'Failed to delete contract.', 'danger');
        }
    });
};

window.closeEmployeeDetailsCard = function () {
    document.getElementById('employeeDetailsOverlay')?.remove();
};

window.showEmployeeDetailsCard = async function (userId) {
    const user = (window.currentAdminUsers || []).find(item => item.id === userId) || await db.getUserProfile(userId);
    if (!user) {
        showToast(window.t('msg_toast_36') || 'Employee details could not be loaded.', 'danger');
        return;
    }
    const users = window.currentAdminUsers || await db.fetchUsers();
    const manager = users.find(item => item.id === user.manager_id);
    const departments = await db.fetchDepartments();
    const department = departments.find(item => item.id === user.department_id)?.name || user.department_name || user.department || 'Not assigned';
    window.closeEmployeeDetailsCard();
    const overlay = document.createElement('div');
    overlay.id = 'employeeDetailsOverlay';
    overlay.className = 'employee-details-overlay';
    overlay.innerHTML = `
        <button type="button" class="employee-details-backdrop" aria-label="Close employee details" onclick="window.closeEmployeeDetailsCard()"></button>
        <section class="employee-details-card" role="dialog" aria-modal="true" aria-labelledby="employeeDetailsTitle">
            <button type="button" class="employee-details-close" aria-label="Close" onclick="window.closeEmployeeDetailsCard()"><i data-lucide="x"></i></button>
            <div class="employee-details-avatar"><i data-lucide="user-round"></i></div>
            <p class="employee-details-kicker">Employee profile</p>
            <h2 id="employeeDetailsTitle">${escapeHTML(window.formatEmployeeName(user) || 'Employee')}</h2>
            <div class="employee-details-grid">
                <div><span>Full Name</span><strong>${escapeHTML(user.full_name || 'Not provided')}</strong></div>
                <div><span>Department</span><strong>${escapeHTML(department)}</strong></div>
                <div><span>ID/Iqama number</span><strong>${escapeHTML(user.iqama_number || formatEmployeeId(user.emp_index, 'Not assigned'))}</strong></div>
                <div><span>Job Title</span><strong>${escapeHTML(user.job_title || 'Not assigned')}</strong></div>
                <div><span>Assigned Manager</span><strong>${escapeHTML(manager ? window.formatEmployeeName(manager) : 'No Manager')}</strong></div>
                <div><span>Role</span><strong>${escapeHTML(user.role || 'EMPLOYEE')}</strong></div>
            </div>
        </section>`;
    document.body.appendChild(overlay);
    translateArabicInterface(overlay);
    if (window.lucide) window.lucide.createIcons();
};

window.filterEmployees = () => {
    const input = document.getElementById('employeeSearchInput');
    if (!input) return;
    const filter = input.value.toLowerCase();
    const table = document.getElementById('employeeDirectoryTable');
    if (!table) return;
    const tr = table.getElementsByTagName('tr');

    for (let i = 1; i < tr.length; i++) {
        const textContent = tr[i].textContent || tr[i].innerText;
        if (textContent.toLowerCase().indexOf(filter) > -1) {
            tr[i].style.display = "";
        } else {
            tr[i].style.display = "none";
        }
    }
};

window.handlePrintContract = async (employeeId) => {
    // 0. Permission check
    const employee = await db.getUserProfile(employeeId);
    if (!employee) return;

    const isSelf = employee.id === currentUser?.id;
    const isManager = currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR';
    const isUnderManagement = employee.manager_id === currentUser?.id;
    const isAdmin = currentUserRole === 'ADMIN' || window.canCurrentUserEditContracts(currentUserProfile);
    window.canViewFullContractIdentity = isAdmin;

    if (isSelf && !isAdmin && !window.canCurrentUserEditContracts(currentUserProfile)) {
        const requests = await db.fetchContractPrintRequests({ employeeId, status: 'APPROVED' });
        if (!requests.length) {
            showToast(t('profile_print_approval_required'), 'warning');
            return;
        }
    }

    if (!isAdmin && !isSelf && !(isManager && isUnderManagement)) {
        showToast("Unauthorized: You do not have permission to view this contract.", "error");
        return;
    }

    // 1. Fetch contracts for employee
    const contracts = await db.fetchContracts(employeeId);
    if (!contracts || contracts.length === 0) {
        showToast("No contract is available for this employee.", "error");
        return;
    }

    const activeContract = contracts.find(c => c.status === 'Active' || c.status === 'active');

    if (contracts.length === 1) {
        if (activeContract) {
            // One active contract, print directly
            window.currentContractIdToPrint = contracts[0].id;
            window.currentEmployeeIdToPrint = employeeId;
            renderView('contract_preview');
        } else {
            // One draft/historical, ask to confirm
            window.showConfirmModal(t('html_confirm_action'), `${t('contract_single_print_prompt')} (${contracts[0].status})`, async () => {
                window.currentContractIdToPrint = contracts[0].id;
                window.currentEmployeeIdToPrint = employeeId;
                renderView('contract_preview');
            });
        }
    } else {
        // Multiple contracts
        if (activeContract) {
            // Use current active contract by default
            window.currentContractIdToPrint = activeContract.id;
            window.currentEmployeeIdToPrint = employeeId;
            renderView('contract_preview');
        } else {
            // Show selection dialog
            let optionsHTML = contracts.map(c => `
                <div style="padding: 10px; border: 1px solid var(--border-color); margin-bottom: 5px; border-radius: 4px; display: flex; justify-content: space-between; align-items: center;">
                    <div>
                        <strong>ID:</strong> ${c.id.substring(0, 8)}... | <strong>Status:</strong> ${c.status}<br/>
                        <strong>Dates:</strong> ${c.start_date || 'N/A'} to ${c.end_date || 'N/A'}<br/>
                        <strong>Title:</strong> ${c.job_title || 'N/A'}
                    </div>
                    <button class="btn-primary btn-sm" onclick="window.currentContractIdToPrint='${c.id}'; window.currentEmployeeIdToPrint='${employeeId}'; document.getElementById('contractSelectModal').style.display='none'; renderView('contract_preview');">Select</button>
                </div>
            `).join('');

            const modalHTML = `
                <div id="contractSelectModal" class="modal" style="display: flex;">
                    <div class="modal-content" style="max-width: 600px;">
                        <span class="close" onclick="document.getElementById('contractSelectModal').remove()">&times;</span>
                        <h2>Select Contract to Print</h2>
                        <div style="max-height: 400px; overflow-y: auto; margin-top: 15px;">
                            ${optionsHTML}
                        </div>
                    </div>
                </div>
            `;
            const existingModal = document.getElementById('contractSelectModal');
            if (existingModal) existingModal.remove();
            document.body.insertAdjacentHTML('beforeend', modalHTML);
        }
    }
};

window.handleContractPrintDecision = async (requestId, status) => {
    const result = await db.decideContractPrintRequest(requestId, status);
    if (!result.success) return showToast(result.error?.message || t('profile_print_decision_failed'), 'danger');
    showToast(status === 'APPROVED' ? t('profile_print_approved') : t('profile_print_rejected'), 'success');
    delete window.viewHTMLCache.employees;
    renderView('employees');
};

// ==========================================
// TRANSLATION MANAGEMENT (ADMIN ONLY)
// ==========================================
window.initCustomTranslations = async function () {
    try {
        const saved = await db.fetchSystemTranslations();
        if (saved && Array.isArray(saved)) {
            saved.forEach(t => {
                if (t.trans_en && typeof i18n !== 'undefined' && i18n.en) i18n.en[t.trans_key] = t.trans_en;
                if (t.trans_ar && typeof i18n !== 'undefined' && i18n.ar) i18n.ar[t.trans_key] = t.trans_ar;
            });
        }
    } catch (e) {
        console.error("Error loading system translations:", e);
    }
};

window.filterTranslations = function () {
    const searchInput = document.getElementById('transSearchInput');
    const statusFilter = document.getElementById('transStatusFilter');
    const q = searchInput ? (searchInput.value || '').toLowerCase().trim() : '';
    const status = statusFilter ? statusFilter.value : 'all';

    const rows = document.querySelectorAll('.trans-row');
    let visibleCount = 0;
    rows.forEach(row => {
        const key = row.dataset.key || '';
        const en = row.dataset.en || '';
        const ar = row.dataset.ar || '';

        let matchesSearch = !q || key.includes(q) || en.includes(q) || ar.includes(q);

        let matchesStatus = true;
        if (status === 'translated') {
            matchesStatus = en.trim() !== '' && ar.trim() !== '';
        } else if (status === 'untranslated') {
            matchesStatus = en.trim() === '' || ar.trim() === '';
        }

        if (matchesSearch && matchesStatus) {
            row.style.display = '';
            visibleCount++;
        } else {
            row.style.display = 'none';
        }
    });

    const countEl = document.getElementById('transTotalCount');
    if (countEl) countEl.textContent = visibleCount;
};

window.saveAllTranslations = async function (silent = false) {
    const updates = [];
    const btn = silent ? null : document.querySelector('button[onclick="saveAllTranslations()"]');
    if (btn) {
        btn.disabled = true;
        btn.innerHTML = '<div class="spinner" style="width: 14px; height: 14px; border-width: 2px; margin-right: 4px;"></div> Saving...';
    }

    // 1. UI Strings
    document.querySelectorAll('.trans-row').forEach(row => {
        const key = row.dataset.key;
        const enVal = document.getElementById('trans_en_' + key)?.value || '';
        const arVal = document.getElementById('trans_ar_' + key)?.value || '';

        if (typeof i18n !== 'undefined') {
            if (i18n.en[key] !== enVal || i18n.ar[key] !== arVal) {
                i18n.en[key] = enVal;
                i18n.ar[key] = arVal;
                updates.push({ trans_key: key, trans_en: enVal, trans_ar: arVal });
            }
        } else {
            updates.push({ trans_key: key, trans_en: enVal, trans_ar: arVal });
        }
    });

    // 2. Tags
    document.querySelectorAll('.trans-tag-row').forEach(row => {
        const key = row.dataset.key;
        const enVal = document.getElementById('tag_en_' + key)?.value || '';
        const arVal = document.getElementById('tag_ar_' + key)?.value || '';

        if (typeof i18n !== 'undefined') {
            if (i18n.en[key] !== enVal || i18n.ar[key] !== arVal) {
                i18n.en[key] = enVal;
                i18n.ar[key] = arVal;
                updates.push({ trans_key: key, trans_en: enVal, trans_ar: arVal });
            }
        } else {
            updates.push({ trans_key: key, trans_en: enVal, trans_ar: arVal });
        }
    });

    // Save UI strings and Tags to translations table
    if (updates.length > 0) {
        const res = await db.saveSystemTranslationsBatch(updates);
        if (!res.success) {
            if (!silent) showToast(res.error?.message || 'Failed to save UI/Tag translations', 'danger');
            if (btn) {
                btn.disabled = false;
                btn.innerHTML = '<i data-lucide="save"></i> Save All Changes';
            }
            return;
        }
    }

    // 3. Departments
    let deptPromises = [];
    document.querySelectorAll('.trans-dept-row').forEach(row => {
        const deptId = row.dataset.id;
        const arVal = document.getElementById('dept_ar_' + deptId)?.value || null;
        deptPromises.push(db.updateDepartmentTranslation(deptId, arVal));
    });

    // 4. Employees / Job Titles
    let profilePromises = [];
    document.querySelectorAll('.trans-profile-row').forEach(row => {
        const profId = row.dataset.id;
        const nameAr = document.getElementById('profile_name_ar_' + profId)?.value || null;
        const jobAr = document.getElementById('profile_job_ar_' + profId)?.value || null;
        profilePromises.push(db.updateProfileTranslations(profId, nameAr, jobAr));
    });

    const jobTitlePromises = [];
    document.querySelectorAll('.trans-job-title-row').forEach(row => {
        const titleId = row.dataset.id;
        const nameAr = document.getElementById('job_title_ar_' + titleId)?.value || null;
        jobTitlePromises.push(db.updateJobTitleTranslation(titleId, nameAr));
    });

    // Await all DB updates for departments and profiles
    const entityResults = await Promise.all([...deptPromises, ...profilePromises, ...jobTitlePromises]);
    const entityFailure = entityResults.find(result => result && result.success === false);
    if (entityFailure) {
        if (!silent) showToast(entityFailure.error?.message || 'Some translations could not be saved.', 'danger');
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = '<i data-lucide="save"></i> Save All Changes';
        }
        return;
    }

    // Apply changes to the live UI immediately
    if (typeof updateTranslations === 'function') updateTranslations();

    if (!silent) showToast(window.t('msg_toast_37') || 'All translations saved successfully', 'success');

    if (btn) {
        btn.disabled = false;
        btn.innerHTML = '<i data-lucide="save" style="width:16px;height:16px;margin-right:4px;"></i> Save All Changes';
        lucide.createIcons();
    }
};

window.deleteTranslationKey = function (key) {
    window.showConfirmModal("Delete Translation Key", `Are you sure you want to delete "${key}"?`, async () => {
        if (typeof i18n !== 'undefined') {
            delete i18n.en[key];
            delete i18n.ar[key];
        }
        const res = await db.deleteSystemTranslation(key);
        if (res.success) {
            showToast("Translation key removed", "warning");
        } else {
            showToast("Failed to remove translation from database", "danger");
        }
        renderView('translations');
    });
};

window.handleAddTranslationSubmit = async function (e) {
    e.preventDefault();
    const key = document.getElementById('newTransKey').value.trim().toLowerCase().replace(/\s+/g, '_');
    const enVal = document.getElementById('newTransEn').value.trim();
    const arVal = document.getElementById('newTransAr').value.trim();

    if (!key) {
        showToast("Translation key is required", "danger");
        return;
    }

    if (typeof i18n !== 'undefined') {
        i18n.en[key] = enVal || key;
        i18n.ar[key] = arVal || key;
    }

    const res = await db.saveSystemTranslationsBatch([{ trans_key: key, trans_en: enVal || key, trans_ar: arVal || key }]);
    if (res.success) {
        showToast("Translation key added successfully!", "success");
    } else {
        showToast("Failed to add translation to database", "danger");
    }
    closeAddTranslationModal();
    renderView('translations');
};



window.exportTranslationsJSON = function () {
    const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify({ en: i18n.en, ar: i18n.ar }, null, 2));
    const downloadAnchor = document.createElement('a');
    downloadAnchor.setAttribute("href", dataStr);
    downloadAnchor.setAttribute("download", "system_translations.json");
    document.body.appendChild(downloadAnchor);
    downloadAnchor.click();
    downloadAnchor.remove();
};

window.importTranslationsJSON = function (event) {
    const file = event.target.files[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = async function (e) {
        try {
            const parsed = JSON.parse(e.target.result);
            if (parsed.en && typeof i18n !== 'undefined') Object.assign(i18n.en, parsed.en);
            if (parsed.ar && typeof i18n !== 'undefined') Object.assign(i18n.ar, parsed.ar);
            await renderView('translations');
            await window.saveAllTranslations(true);
            showToast("Translations imported and saved successfully!", "success");
        } catch (err) {
            showToast("Failed to parse JSON file", "danger");
        }
    };
    reader.readAsText(file);
};

window.showAddTranslationModal = function () {
    document.getElementById('addTranslationForm').reset();
    document.getElementById('addTranslationModal').classList.add('show');
};

window.closeAddTranslationModal = function () {
    document.getElementById('addTranslationModal').classList.remove('show');
};

async function renderTemplates() {
    const templates = [
        {
            type: 'employees',
            icon: 'users',
            gradient: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
            titleKey: 'ui_template_employees',
            titleFallback: 'Employees Template',
            desc: 'Import new employees and user accounts in bulk.',
            columns: ['full_name', 'email', 'phone', 'job_title', 'department', 'role', 'salary', 'hire_date', 'national_id', 'address']
        },
        {
            type: 'clients',
            icon: 'building-2',
            gradient: 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)',
            titleKey: 'ui_template_clients',
            titleFallback: 'Clients Template',
            desc: 'Import CRM clients and deal pipelines.',
            columns: ['company_name', 'contact_name', 'email', 'phone', 'industry', 'country', 'city', 'deal_stage', 'deal_value', 'notes']
        },
        {
            type: 'projects',
            icon: 'folder-kanban',
            gradient: 'linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)',
            titleKey: 'ui_template_projects',
            titleFallback: 'Projects Template',
            desc: 'Import projects and associate them with clients.',
            columns: ['project_name', 'project_type', 'category', 'description', 'status', 'assigned_people', 'tags', 'start_date', 'end_date', 'client']
        },
        {
            type: 'tasks',
            icon: 'list-checks',
            gradient: 'linear-gradient(135deg, #43e97b 0%, #38f9d7 100%)',
            titleKey: 'ui_template_tasks',
            titleFallback: 'Tasks Template',
            desc: 'Import tasks across multiple projects in bulk.',
            columns: ['title', 'description', 'assignee_email', 'supervisor_email', 'due_date', 'priority', 'status', 'category', 'project_name', 'tags']
        },
        {
            type: 'departments_jobtitles',
            icon: 'building',
            gradient: 'linear-gradient(135deg, #fa709a 0%, #fee140 100%)',
            titleKey: 'ui_template_dept_jobs',
            titleFallback: 'Departments & Job Titles',
            desc: 'Import translated Departments and Job Titles.',
            columns: ['Department (EN)', 'Department (AR)', 'Job Title (EN)', 'Job Title (AR)']
        }
    ];

    const cards = templates.map(tmpl => `
        <div class="template-card fade-in-up" style="
            background: var(--color-surface);
            border: 1px solid var(--color-border);
            border-radius: 16px;
            overflow: hidden;
            display: flex;
            flex-direction: column;
            transition: transform 0.2s ease, box-shadow 0.2s ease;
            box-shadow: 0 2px 8px rgba(0,0,0,0.06);
        " onmouseover="this.style.transform='translateY(-4px)';this.style.boxShadow='0 12px 32px rgba(0,0,0,0.12)'" onmouseout="this.style.transform='';this.style.boxShadow='0 2px 8px rgba(0,0,0,0.06)'">
            <!-- Gradient top banner with icon -->
            <div style="background: ${tmpl.gradient}; padding: 2rem; display: flex; align-items: center; justify-content: center; min-height: 140px;">
                <div style="width: 64px; height: 64px; background: rgba(255,255,255,0.25); border-radius: 16px; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(8px);">
                    <i data-lucide="${tmpl.icon}" style="width: 32px; height: 32px; color: #fff;"></i>
                </div>
            </div>
            <!-- Card body -->
            <div style="padding: 1.5rem; display: flex; flex-direction: column; flex: 1; gap: 0.75rem;">
                <h3 style="margin: 0; font-size: 1rem; font-weight: 700; color: var(--color-text);">
                    <span data-i18n="${tmpl.titleKey}">${t(tmpl.titleKey) || tmpl.titleFallback}</span>
                </h3>
                <p style="margin: 0; color: var(--color-text-secondary); font-size: 0.825rem; line-height: 1.5; flex: 1;">${tmpl.desc}</p>
                <div style="display: flex; gap: 0.5rem; margin-top: 0.5rem;">
                    <button class="btn btn-secondary" style="flex: 1; font-size: 0.75rem; padding: 0.6rem 0.5rem; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 0.25rem; line-height: 1.2;" onclick="downloadTemplate('${tmpl.type}')">
                        <i data-lucide="download" style="width:16px;height:16px;"></i>
                        <span data-i18n="ui_download">${t('ui_download') || 'Download'}</span>
                    </button>
                    <button class="btn btn-primary" style="flex: 1; font-size: 0.75rem; padding: 0.6rem 0.5rem; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 0.25rem; line-height: 1.2;" onclick="triggerBulkUpload('${tmpl.type}')">
                        <i data-lucide="upload" style="width:16px;height:16px;"></i>
                        <span data-i18n="ui_bulk_upload">${t('ui_bulk_upload') || 'Bulk Upload'}</span>
                    </button>
                </div>
            </div>
        </div>
    `).join('');

    return `
        <style>
            .templates-grid {
                display: grid;
                grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
                gap: 1.25rem;
            }
            @media (max-width: 480px) {
                .templates-grid {
                    grid-template-columns: repeat(2, 1fr);
                    gap: 0.75rem;
                }
            }
        </style>
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title"><span data-i18n="ui_templates_title">${t('ui_templates_title') || 'Excel Templates'}</span></h1>
                <p class="page-subtitle"><span data-i18n="ui_templates_subtitle">${t('ui_templates_subtitle') || 'Download templates for bulk imports'}</span></p>
            </div>
        </div>
        <div class="templates-grid">
            ${cards}
        </div>
        <!-- Hidden input for bulk upload -->
        <input type="file" id="bulkUploadInput" accept=".csv, application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, application/vnd.ms-excel" style="display: none;" onchange="handleBulkUpload(event)">
    `;
}

window.downloadTemplate = function (type) {
    const schemas = {
        employees: ['Employee ID', 'full_name', 'Full Name in Arabic', 'email', 'phone', 'Temp Password'],
        clients: ['company_name', 'contact_name', 'email', 'phone', 'industry', 'country', 'city', 'deal_stage', 'deal_value', 'notes'],
        projects: ['project_name', 'project_type', 'category', 'description', 'status', 'assigned_people', 'tags', 'start_date', 'end_date', 'client'],
        tasks: ['title', 'description', 'assignee_email', 'supervisor_email', 'due_date', 'priority', 'status', 'category', 'project_name', 'tags'],
        departments_jobtitles: ['Department (EN)', 'Department (AR)', 'Job Title (EN)', 'Job Title (AR)', 'Head']
    };





    const examples = {
        employees: ['MQ-0001', 'John Doe', 'Ø¬ÙˆÙ† Ø¯Ùˆ', '', '', 'Pass123!'],
        clients: ['Acme Corp', 'Jane Smith', 'jane@acme.com', '+1234567890', 'Technology', 'Saudi Arabia', 'Riyadh', 'Negotiation', '50000', 'Key account'],
        projects: ['Website Redesign', 'Client', 'Enterprise', 'New website for client', 'active', 'john@example.com', 'Frontend,UI/UX', '2024-01-01', '2024-06-30', 'Acme Corp'],
        tasks: ['Design homepage mockup', 'Create high-fidelity wireframes', 'john@example.com', 'manager@example.com', '2024-03-15', 'high', 'todo', 'Design', 'Website Redesign', 'Frontend,UI/UX'],
        departments_jobtitles: ['Engineering', 'Ø§Ù„Ù‡Ù†Ø¯Ø³Ø©', 'Software Engineer', 'Ù…Ù‡Ù†Ø¯Ø³ Ø¨Ø±Ù…Ø¬ÙŠØ§Øª', 'MQ-0001']
    };

        const cols = schemas[type];
    if (!cols) { showToast(window.t('msg_toast_38') || 'Unknown template type', 'error'); return; }
    
    try {
        const data = [
            cols.reduce((acc, col, i) => { acc[col] = examples[type][i]; return acc; }, {})
        ];
        const ws = XLSX.utils.json_to_sheet(data, { header: cols });
        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, "Import Data");
        XLSX.writeFile(wb, `${type}_template.xlsx`);
        showToast(`${type.charAt(0).toUpperCase() + type.slice(1)} template downloaded!`, 'success');
    } catch (e) {
        console.error(e);
        showToast(window.t('msg_toast_39') || 'Error generating template. Please make sure XLSX library is loaded.', 'error');
    }
};

let currentBulkUploadType = null;
window.triggerBulkUpload = function (type) {
    currentBulkUploadType = type;
    document.getElementById('bulkUploadInput').click();
};
window.triggerSpecificBulkUpload = function (type, inputId) {
    currentBulkUploadType = type;
    document.getElementById(inputId).click();
};

window.handleBulkUpload = async function (event) {
    const file = event.target.files[0];
    event.target.value = '';
    if (!file) return;

    if (typeof XLSX === 'undefined') {
        showToast(window.t('msg_toast_40') || 'Excel support is unavailable. Please refresh or check your internet connection.', 'error');
        return;
    }

    try {
        const workbook = XLSX.read(await file.arrayBuffer(), { type: 'array', cellDates: true });
        const sheet = workbook.Sheets['Import Data'] || workbook.Sheets[workbook.SheetNames[0]];
        const rows = XLSX.utils.sheet_to_json(sheet, { defval: '', raw: false })
            .filter(row => Object.values(row).some(value => String(value).trim()));
            
        if (!rows.length) throw new Error('The workbook contains no data rows.');

        
        if (currentBulkUploadType === 'employees') {
            let successCount = 0;
            let errorCount = 0;
            showToast(`Uploading ${rows.length} users...`, 'info');

            for (const row of rows) {
                const empId = row['Employee ID'] || '';
                const fullName = row['full_name'] || '';
                const fullNameAr = row['Full Name in Arabic'] || '';
                let email = row['email'] || '';
                const phone = row['phone'] || '';
                const password = row['Temp Password'] || 'Default123!';
                
                const jobTitle = '';
                const deptId = '';
                const role = 'EMPLOYEE';
                const nationality = '';
                const iqama = '';

                if (!fullName) {
                    errorCount++;
                    continue; // Skip invalid row
                }
                
                if (!email && empId) {
                    email = `${empId.toLowerCase().replace(/[^a-z0-9]/g, '')}@muqam.local`;
                } else if (!email) {
                    email = `user${Math.floor(Math.random()*10000)}@muqam.local`;
                }

                const res = await db.createUser(email, password, role, jobTitle, fullName, iqama, phone, deptId, nationality, fullNameAr, empId);
                if (res.error) {
                    console.error("Bulk Upload Error:", res.error);
                    errorCount++;
                } else {
                    successCount++;
                }
            }

            showToast(`Bulk upload complete. Success: ${successCount}, Errors: ${errorCount}.`, 'success');
            if (typeof renderView === 'function') renderView('templates');
            return;
        }

        if (currentBulkUploadType === 'departments_jobtitles') {
            const payload = rows.map(r => ({
                dept_en: String(r['Department (EN)'] || '').trim(),
                dept_ar: String(r['Department (AR)'] || '').trim(),
                job_en: String(r['Job Title (EN)'] || '').trim(),
                job_ar: String(r['Job Title (AR)'] || '').trim(),
                head: String(r['Head'] || '').trim()
            })).filter(item => item.dept_en);
            
            if (payload.length > 0) {
                const res = await db.importDepartmentsJobTitles(payload);
                if (!res.success) throw res.error;
                showToast(`Successfully imported ${payload.length} rows for Departments and Job Titles.`, 'success');
                if (typeof renderView === 'function') renderView('templates');
            } else {
                throw new Error('No valid department entries found in the file.');
            }
        } else {
            showToast(`Upload for ${currentBulkUploadType} is not implemented yet.`, 'info');
        }
    } catch (error) {
        console.error('Bulk Upload Error:', error);
        showToast(`Import failed: ${error.message || 'An error occurred'}`, 'error');
    }
};

// ==========================================
// CUSTODY HANDOVER
// ==========================================
async function renderCustodyHandover() {
    const profile = currentUserProfile || await db.getUserProfile(currentUser?.id);
    const isAdmin = String(currentUserRole || '').toUpperCase() === 'ADMIN';
    const isHrManager = String(profile?.job_title || '').trim().toUpperCase() === 'HR MANAGER';
    if (!isAdmin && !isHrManager) return '<div class="page-header"><h1 class="page-title">Unauthorized</h1></div>';
    // Pre-fill employee name and department if available
    const fullName = profile?.full_name || '';
    const department = profile?.department_name || '';
    const idNumber = profile?.national_id || '';
    const today = new Date().toISOString().split('T')[0];

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title"><i data-lucide="package-check" style="width:28px;height:28px;vertical-align:middle;margin-inline-end:0.5rem;"></i>${t('custody_title')}</h1>
                <p class="page-subtitle">${t('custody_subtitle')}</p>
            </div>
            <div style="display:flex;gap:0.75rem;flex-wrap:wrap;">
                <button class="btn btn-secondary" style="white-space: nowrap;" onclick="window.print()">
                    <i data-lucide="printer" style="width:16px;height:16px;"></i> ${t('custody_print')}
                </button>
                <button class="btn btn-primary" style="white-space: nowrap;" onclick="submitCustodyHandover(event)">
                    <i data-lucide="save" style="width:16px;height:16px;"></i> ${t('custody_save')}
                </button>
            </div>
        </div>

        <style>
            .custody-form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 1rem; }
            .custody-items-table { width: 100%; min-width: 850px; border-collapse: collapse; font-size: 0.9rem; }
            .custody-items-table th { background: var(--color-primary); color: #ffffff !important; padding: 0.75rem 1rem; text-align: start; font-weight: 600; }
            .custody-items-table td { padding: 0.65rem 1rem; border-bottom: 1px solid var(--color-border); vertical-align: middle; }
            .custody-items-table tr:hover td { background: var(--color-bg-alt); }
            .custody-items-table input, .custody-items-table select { border: 1px solid var(--color-border); border-radius: 8px; padding: 0.4rem 0.6rem; width: 100%; background: var(--color-surface); color: var(--color-text); font-size: 0.85rem; }
            .custody-radio-group { display: flex; gap: 1rem; align-items: center; }
            .custody-radio-group label { display: flex; align-items: center; gap: 0.35rem; cursor: pointer; font-size: 0.85rem; white-space: nowrap; }
            .declaration-box { background: var(--color-bg-alt); border: 1px solid var(--color-border); border-radius: 12px; padding: 1.75rem 2rem; line-height: 1.85; color: var(--color-text); }
            .declaration-box h3 { margin: 0 0 1rem 0; font-size: 1.1rem; color: var(--color-primary); border-bottom: 2px solid var(--color-primary); padding-bottom: 0.5rem; }
            .declaration-box ul { padding-inline-start: 1.25rem; margin: 0.75rem 0; }
            .declaration-box ul li { margin-bottom: 0.65rem; }
            .signature-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 2rem; }
            .signature-line { border-top: 2px solid var(--color-border); padding-top: 0.5rem; margin-top: 2rem; font-size: 0.85rem; color: var(--color-text-secondary); display:flex; align-items:center; justify-content:space-between; gap:1rem; }
            .signature-line-field { display:inline-flex; align-items:center; gap:0.45rem; }
            .signature-blank { display:inline-block; min-width:8rem; border-bottom:1px dashed currentColor; transform:translateY(-0.15rem); }
            @media (max-width: 640px) { .signature-grid { grid-template-columns: 1fr; } .custody-form-grid { grid-template-columns: 1fr; } }
            @media print {
                .topbar, .sidebar, .page-header > div:last-child, button { display: none !important; }
                .card { box-shadow: none !important; border: 1px solid #ccc !important; }
                body { background: #fff !important; color: #000 !important; }
            }
        </style>

        <form id="custodyHandoverForm" onsubmit="submitCustodyHandover(event)" style="display:flex;flex-direction:column;gap:1.5rem;">

            <!-- Employee Info Card -->
            <div class="card fade-in-up" style="padding: 1.5rem;">
                <h2 style="margin: 0 0 1.25rem 0; font-size: 1rem; font-weight: 700; color: var(--color-primary); display:flex;align-items:center;gap:0.5rem;">
                    <i data-lucide="user" style="width:18px;height:18px;"></i> ${t('custody_employee_info')}
                </h2>
                <div class="custody-form-grid">
                    <div class="form-group" style="margin:0">
                        <label class="form-label">${t('custody_full_name')} *</label>
                        <input type="text" id="chFullName" class="form-control" value="${escapeHTML(fullName)}" placeholder="${t('custody_full_name_placeholder')}" required>
                    </div>
                    <div class="form-group" style="margin:0">
                        <label class="form-label">${t('custody_id_number')} *</label>
                        <input type="text" id="chIdNumber" class="form-control" value="${escapeHTML(idNumber)}" placeholder="${t('custody_id_placeholder')}" required>
                    </div>
                    <div class="form-group" style="margin:0">
                        <label class="form-label">${t('custody_department')} *</label>
                        <input type="text" id="chDepartment" class="form-control" value="${escapeHTML(department)}" placeholder="${t('custody_department_placeholder')}" required>
                    </div>
                    <div class="form-group" style="margin:0">
                        <label class="form-label">${t('custody_handover_date')} *</label>
                        <input type="date" id="chDate" class="form-control" value="${today}" required>
                    </div>
                </div>
            </div>

            <!-- Items Table Card -->
            <div class="card fade-in-up" style="padding: 1.5rem; overflow-x: auto;">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:1.25rem;flex-wrap:wrap;gap:0.75rem;">
                    <h2 style="margin:0;font-size:1rem;font-weight:700;color:var(--color-primary);display:flex;align-items:center;gap:0.5rem;">
                        <i data-lucide="package" style="width:18px;height:18px;"></i> ${t('custody_items')}
                    </h2>
                    <button type="button" class="btn btn-secondary" onclick="addCustodyRow()" style="font-size:0.85rem;padding:0.45rem 1rem;white-space: nowrap;">
                        <i data-lucide="plus" style="width:14px;height:14px;"></i> ${t('custody_add_item')}
                    </button>
                </div>
                <table class="custody-items-table">
                    <thead>
                        <tr>
                            <th style="width:40px;">#</th>
                            <th>${t('custody_item')}</th>
                            <th>${t('custody_model_serial')}</th>
                            <th style="width:80px;">${t('custody_quantity')}</th>
                            <th style="width:130px;">${t('custody_condition')}</th>
                            <th style="width:50px;"></th>
                        </tr>
                    </thead>
                    <tbody id="custodyItemsBody">
                        <tr>
                            <td style="text-align:center;color:var(--color-text-secondary);">1</td>
                            <td><input type="text" placeholder="${t('custody_item_placeholder')}" required></td>
                            <td><input type="text" placeholder="${t('custody_model_placeholder')}"></td>
                            <td><input type="number" value="1" min="1" style="width:70px;"></td>
                            <td>
                                <div class="custody-radio-group">
                                    <label><input type="radio" name="cond_1" value="New" checked> ${t('custody_new')}</label>
                                    <label><input type="radio" name="cond_1" value="Used"> ${t('custody_used')}</label>
                                </div>
                            </td>
                            <td></td>
                        </tr>
                    </tbody>
                </table>
            </div>

            <!-- Declaration Section -->
            <div class="card fade-in-up" style="padding: 1.5rem;">
                <div class="declaration-box">
                    <h3>${t('custody_declaration_title')}</h3>
                    <p>${t('custody_declaration_intro')}</p>
                    <ul>
                        <li><strong>${t('custody_usage_title')}:</strong> ${t('custody_usage_text')}</li>
                        <li><strong>${t('custody_reporting_title')}:</strong> ${t('custody_reporting_text')}</li>
                        <li><strong>${t('custody_liability_title')}:</strong> ${t('custody_liability_text')}</li>
                        <li><strong>${t('custody_return_title')}:</strong> ${t('custody_return_text')}</li>
                    </ul>
                </div>

                <!-- Signature Block -->
                <div class="signature-grid" style="margin-top:2rem;">
                    <div>
                        <div class="form-group" style="margin-bottom:0.75rem;">
                            <label class="form-label">${t('custody_employee_signature_name')}</label>
                            <input type="text" id="chSigEmployeeName" class="form-control" value="${escapeHTML(fullName)}" placeholder="Full name">
                        </div>
                        <div class="signature-line"><span class="signature-line-field">${t('custody_signature')}: <span class="signature-blank"></span></span><span class="signature-line-field">${t('custody_date')}: <span class="signature-blank"></span></span></div>
                    </div>
                    <div>
                        <div class="form-group" style="margin-bottom:0.75rem;">
                            <label class="form-label">${t('custody_manager_hr')}</label>
                            <input type="text" id="chSigManager" class="form-control" placeholder="${t('custody_manager_placeholder')}">
                        </div>
                        <div class="signature-line"><span class="signature-line-field">${t('custody_signature')}: <span class="signature-blank"></span></span><span class="signature-line-field">${t('custody_date')}: <span class="signature-blank"></span></span></div>
                    </div>
                </div>
            </div>

        </form>
    `;
}

let custodyRowCount = 1;
window.addCustodyRow = function () {
    custodyRowCount++;
    const tbody = document.getElementById('custodyItemsBody');
    if (!tbody) return;
    const row = document.createElement('tr');
    row.innerHTML = `
        <td style="text-align:center;color:var(--color-text-secondary);">${custodyRowCount}</td>
        <td><input type="text" placeholder="${t('custody_item_placeholder')}" required></td>
        <td><input type="text" placeholder="${t('custody_model_placeholder')}"></td>
        <td><input type="number" value="1" min="1" style="width:70px;"></td>
        <td>
            <div class="custody-radio-group">
                <label><input type="radio" name="cond_${custodyRowCount}" value="New" checked> ${t('custody_new')}</label>
                <label><input type="radio" name="cond_${custodyRowCount}" value="Used"> ${t('custody_used')}</label>
            </div>
        </td>
        <td><button type="button" onclick="this.closest('tr').remove()" style="background:none;border:none;cursor:pointer;color:var(--color-danger);padding:0.25rem;"><i data-lucide="trash-2" style="width:15px;height:15px;"></i></button></td>
    `;
    tbody.appendChild(row);
    if (window.lucide) lucide.createIcons();
};

window.submitCustodyHandover = function (event) {
    if (event) event.preventDefault();
    const fullName = document.getElementById('chFullName')?.value?.trim();
    const idNumber = document.getElementById('chIdNumber')?.value?.trim();
    const department = document.getElementById('chDepartment')?.value?.trim();
    const date = document.getElementById('chDate')?.value;
    if (!fullName || !idNumber || !department || !date) {
        showToast(t('custody_required_warning'), 'warning');
        return;
    }
    showToast(t('custody_saved_success'), 'success');
};

async function renderTranslationsPage() {
    if (currentUserRole !== 'ADMIN') {
        return `<div class="card" style="padding: 2rem; color: var(--color-danger); font-weight: bold;">Unauthorized. System Admin access required.</div>`;
    }

    const [departments, profiles, jobTitles] = await Promise.all([
        db.fetchDepartments(),
        db.fetchAllProfiles(),
        db.fetchJobTitles(true)
    ]);

    const allKeys = Array.from(new Set([...Object.keys(i18n.en || {}), ...Object.keys(i18n.ar || {})])).sort();
    const uiKeys = allKeys.filter(k => !k.startsWith('tag_'));
    const translatedCount = uiKeys.filter(k => i18n.en[k] && i18n.ar[k]).length;
    const totalCount = uiKeys.length;
    const progressPct = totalCount > 0 ? Math.round((translatedCount / totalCount) * 100) : 0;

    // UI Strings Table
    const uiRowsHTML = uiKeys.map(key => {
        const enVal = escapeHTML(i18n.en[key] || '');
        const arVal = escapeHTML(i18n.ar[key] || '');
        const keyEscaped = escapeHTML(key);
        const keyAttr = escapeHTML(key.toLowerCase());
        const enAttr = enVal.toLowerCase();
        const arAttr = arVal.toLowerCase();
        const isMissing = !i18n.ar[key];

        return `
            <tr class="trans-row" data-key="${keyAttr}" data-en="${enAttr}" data-ar="${arAttr}" style="${isMissing ? 'background: rgba(255,180,0,0.06);' : ''}">
                <td style="font-family: monospace; font-weight: 600; font-size: 0.85rem; color: var(--color-accent); word-break: break-all;">
                    ${keyEscaped}
                    ${isMissing ? '<span style="background:#e67e22;color:#fff;border-radius:4px;padding:1px 5px;font-size:0.7rem;margin-inline-start:4px;">Missing AR</span>' : ''}
                </td>
                <td>
                    <input type="text" id="trans_en_${keyEscaped}" class="form-control" style="font-size:0.85rem;" value="${enVal}" onchange="queueTranslationAutosave()">
                </td>
                <td>
                    <input type="text" id="trans_ar_${keyEscaped}" class="form-control" style="font-size:0.85rem; direction: rtl;" value="${arVal}" placeholder="أدخل الترجمة العربية..." onchange="queueTranslationAutosave()">
                </td>
                <td>
                    <div style="display: flex; gap: 0.4rem; justify-content: center; flex-wrap: nowrap; min-width: 60px;">
                        <button class="btn-secondary" style="padding: 0.35rem 0.65rem; font-size: 0.75rem; color: var(--color-danger); flex-shrink: 0;" onclick="deleteTranslationKey('${keyEscaped}')" title="Delete">
                            <i data-lucide="trash-2" style="width:14px; height:14px;"></i>
                        </button>
                    </div>
                </td>
            </tr>
        `;
    }).join('');

    // Tags Table
    const tagsList = ['Urgent', 'Frontend', 'Backend', 'UI/UX', 'Bug', 'Feature'];
    const tagsRowsHTML = tagsList.map(tag => {
        const key = 'tag_' + tag.toLowerCase().replace(/[/\s-]/g, '_');
        const enVal = escapeHTML(i18n.en[key] || tag);
        const arVal = escapeHTML(i18n.ar[key] || tag);
        return `
            <tr class="trans-tag-row" data-key="${key}">
                <td style="font-weight: 600; font-size: 0.85rem;">${tag}</td>
                <td><input type="text" id="tag_en_${key}" class="form-control" style="font-size:0.85rem;" value="${enVal}" onchange="queueTranslationAutosave()"></td>
                <td><input type="text" id="tag_ar_${key}" class="form-control" style="font-size:0.85rem; direction: rtl;" value="${arVal}" onchange="queueTranslationAutosave()"></td>
            </tr>
        `;
    }).join('');

    // Departments Table
    const deptsRowsHTML = (departments || []).map(d => {
        return `
            <tr class="trans-dept-row" data-id="${d.id}">
                <td style="font-weight: 600; font-size: 0.85rem;">${escapeHTML(d.name)}</td>
                <td><input type="text" class="form-control" style="font-size:0.85rem;" value="${escapeHTML(d.name)}" readonly disabled></td>
                <td><input type="text" id="dept_ar_${d.id}" class="form-control" style="font-size:0.85rem; direction: rtl;" value="${escapeHTML(d.name_ar || '')}" placeholder="Arabic Name" onchange="queueTranslationAutosave()"></td>
            </tr>
        `;
    }).join('');

    const jobTitleRowsHTML = (jobTitles || []).filter(title => title.is_active !== false).map(title => {
        const department = departments.find(item => item.id === title.department_id);
        return `
            <tr class="trans-job-title-row" data-id="${title.id}">
                <td style="font-weight:600;font-size:.85rem;">${escapeHTML(department?.name || 'Unknown department')}</td>
                <td>${escapeHTML(title.name || '')}</td>
                <td><input type="text" id="job_title_ar_${title.id}" class="form-control" style="font-size:.85rem;direction:rtl;" value="${escapeHTML(title.name_ar || '')}" placeholder="Arabic Job Title" onchange="queueTranslationAutosave()"></td>
            </tr>`;
    }).join('');

    // Employees Table
    const profilesRowsHTML = (profiles || []).map(p => {
        return `
            <tr class="trans-profile-row" data-id="${p.id}">
                <td style="font-weight: 600; font-size: 0.85rem; white-space: nowrap;">${escapeHTML(window.formatEmployeeName(p) || '')} <br> <small style="color: var(--color-text-secondary); font-weight: normal;">${escapeHTML(p.job_title || '')}</small></td>
                <td><input type="text" id="profile_name_ar_${p.id}" class="form-control" style="font-size:0.85rem; direction: rtl;" value="${escapeHTML(p.display_name_ar || '')}" placeholder="Arabic Name" onchange="queueTranslationAutosave()"></td>
                <td><input type="text" id="profile_job_ar_${p.id}" class="form-control" style="font-size:0.85rem; direction: rtl;" value="${escapeHTML(p.job_title_ar || '')}" placeholder="Arabic Job Title" onchange="queueTranslationAutosave()"></td>
            </tr>
        `;
    }).join('');

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('trans_title') || 'System Translations'}</h1>
                <p class="page-subtitle">${t('trans_sub') || 'Customize English and Arabic display text for all system views and entities.'}</p>
            </div>
            <div style="display:flex; gap:0.5rem; flex-wrap:wrap;">
                <button class="btn-primary" onclick="saveAllTranslations()" style="background-color: var(--color-success); border-color: var(--color-success);">
                    <i data-lucide="save" style="width:16px;height:16px;margin-right:4px;"></i> Save All Changes
                </button>
                <button class="btn-primary" onclick="showAddTranslationModal()">
                    <i data-lucide="plus" style="width:16px;height:16px;margin-right:4px;"></i> ${t('trans_add_key') || 'Add Translation Key'}
                </button>
                <button class="btn-secondary" onclick="exportTranslationsJSON()">
                    <i data-lucide="download" style="width:16px;height:16px;margin-right:4px;"></i> Export JSON
                </button>
                <label class="btn-secondary" style="cursor:pointer; margin:0; display:inline-flex; align-items:center;">
                    <i data-lucide="upload" style="width:16px;height:16px;margin-right:4px;"></i> Import JSON
                    <input type="file" accept=".json" onchange="importTranslationsJSON(event)" style="display:none;">
                </label>
            </div>
        </div>

        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-12" style="display: flex; flex-direction: column;">
                <div class="task-v2-tabs" style="margin-bottom: 1rem; border-bottom: 1px solid var(--color-border); overflow-x: auto; white-space: nowrap;">
                    <button type="button" class="active" onclick="switchTransTab('ui', this)">UI Strings</button>
                    <button type="button" onclick="switchTransTab('tags', this)">Tags</button>
                    <button type="button" onclick="switchTransTab('departments', this)">Departments</button>
                    <button type="button" onclick="switchTransTab('job-titles', this)">Job Titles</button>
                    <button type="button" onclick="switchTransTab('profiles', this)">Employees</button>
                </div>

                <div id="trans-tab-ui" class="trans-tab-content">
                    <div style="display: flex; justify-content: space-between; align-items: center; gap: 1rem; margin-bottom: 1rem; flex-wrap: wrap;">
                        <div style="display: flex; gap: 0.5rem; flex: 1; min-width: 300px;">
                            <div style="position: relative; flex: 1;">
                                <input type="text" id="transSearchInput" class="form-control" placeholder="Search by key, English, or Arabic text..." oninput="filterTranslations()" style="padding-left: 2.2rem;">
                                <i data-lucide="search" style="position: absolute; left: 0.75rem; top: 50%; transform: translateY(-50%); width: 16px; height: 16px; color: var(--color-text-secondary);"></i>
                            </div>
                            <select id="transStatusFilter" class="form-control" onchange="filterTranslations()" style="width: auto; min-width: 150px;">
                                <option value="all">All Fields</option>
                                <option value="translated">Translated</option>
                                <option value="untranslated">Not Translated</option>
                            </select>
                        </div>
                        <div style="font-size: 0.85rem; color: var(--color-text-secondary); display:flex; align-items:center; gap: 0.75rem; flex-wrap:wrap;">
                            <span>Total: <strong id="transTotalCount">${totalCount}</strong></span>
                            <span style="color: var(--color-success);">Translated: <strong>${translatedCount}</strong></span>
                            <span style="color: var(--color-warning);">Missing AR: <strong>${totalCount - translatedCount}</strong></span>
                            <div style="width: 80px; height: 6px; background: var(--color-border); border-radius: 3px; overflow: hidden;">
                                <div style="width: ${progressPct}%; height: 100%; background: var(--color-success); border-radius: 3px; transition: width 0.3s;"></div>
                            </div>
                            <span style="font-weight:700; color: ${progressPct < 80 ? 'var(--color-warning)' : 'var(--color-success)'}">${progressPct}%</span>
                        </div>
                    </div>
                    <div class="table-responsive" style="max-height: 600px; overflow-y: auto;">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th style="width: 20%;">${t('trans_key_name') || 'Key'}</th>
                                    <th style="width: 35%;">${t('trans_en') || 'English'}</th>
                                    <th style="width: 35%;">${t('trans_ar') || 'Arabic'}</th>
                                    <th style="width: 10%; min-width: 80px; text-align: center;">Actions</th>
                                </tr>
                            </thead>
                            <tbody>${uiRowsHTML}</tbody>
                        </table>
                    </div>
                </div>

                <div id="trans-tab-tags" class="trans-tab-content" style="display: none;">
                    <div class="table-responsive" style="max-height: 600px; overflow-y: auto;">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th style="width: 20%;">Tag Value</th>
                                    <th style="width: 40%;">English</th>
                                    <th style="width: 40%;">Arabic</th>
                                </tr>
                            </thead>
                            <tbody>${tagsRowsHTML}</tbody>
                        </table>
                    </div>
                </div>

                <div id="trans-tab-departments" class="trans-tab-content" style="display: none;">
                    <div class="table-responsive" style="max-height: 600px; overflow-y: auto;">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th style="width: 30%;">Department (English)</th>
                                    <th style="width: 35%;">English (Read-only)</th>
                                    <th style="width: 35%;">Arabic</th>
                                </tr>
                            </thead>
                            <tbody>${deptsRowsHTML}</tbody>
                        </table>
                    </div>
                </div>

                <div id="trans-tab-job-titles" class="trans-tab-content" style="display:none;">
                    <div class="table-responsive" style="max-height:600px;overflow-y:auto;">
                        <table class="data-table">
                            <thead><tr><th>Department</th><th>Job Title (English)</th><th>Job Title (Arabic)</th></tr></thead>
                            <tbody>${jobTitleRowsHTML}</tbody>
                        </table>
                    </div>
                </div>

                <div id="trans-tab-profiles" class="trans-tab-content" style="display: none;">
                    <div class="table-responsive" style="max-height: 600px; overflow-y: auto;">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th style="width: 30%;">Employee (English)</th>
                                    <th style="width: 35%;">Name (Arabic)</th>
                                    <th style="width: 35%;">Job Title (Arabic)</th>
                                </tr>
                            </thead>
                            <tbody>${profilesRowsHTML}</tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>

        <!-- Add Translation Key Modal -->
        <div class="modal" id="addTranslationModal">
            <div class="modal-content" style="max-width: 500px;">
                <div class="modal-header">
                    <h3>${t('trans_add_key') || 'Add Translation Key'}</h3>
                    <button class="close-modal" onclick="closeAddTranslationModal()">&times;</button>
                </div>
                <form id="addTranslationForm" onsubmit="handleAddTranslationSubmit(event)">
                    <div class="form-group">
                        <label class="form-label">${t('trans_key_name') || 'Key Name'} (e.g. custom_button_text)</label>
                        <input type="text" id="newTransKey" class="form-control" required placeholder="e.g. nav_dashboard">
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('trans_en') || 'English Translation'}</label>
                        <input type="text" id="newTransEn" class="form-control" required placeholder="English text">
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('trans_ar') || 'Arabic Translation'}</label>
                        <input type="text" id="newTransAr" class="form-control" required placeholder="النص بالعربية" style="direction: rtl;">
                    </div>
                    <div style="display: flex; gap: 1rem; margin-top: 1.5rem;">
                        <button type="submit" class="btn-primary" style="flex: 1;">${t('ui_save') || 'Save Key'}</button>
                        <button type="button" class="btn-secondary" onclick="closeAddTranslationModal()">${t('ui_cancel') || 'Cancel'}</button>
                    </div>
                </form>
            </div>
        </div>
    `;
}

window.switchTransTab = function (tabId, btn) {
    document.querySelectorAll('.trans-tab-content').forEach(c => c.style.display = 'none');
    document.getElementById('trans-tab-' + tabId).style.display = 'block';
    if (btn) {
        document.querySelectorAll('.task-v2-tabs button').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
    }
};
window.viewHTMLCache = window.viewHTMLCache || {};

window.renderView = async function (viewId, isBack = false) {
    if (!viewId) return;
    if (viewId === 'null') {
        viewId = 'dashboard';
    }
    // Preserve old bookmarks/notification links while keeping Task Manager as
    // the single canonical destination.
    if (viewId === 'tasks_v2') viewId = 'tasks';
    // Community has been retired; send old links/bookmarks to the dashboard.
    if (viewId === 'community') viewId = 'dashboard';
    currentView = viewId;

    if (!currentUser && viewId !== 'login') {
        viewId = 'login';
        currentView = 'login';
    }

    // The mobile shell normally forces its bottom navigation to display.
    // Mark authentication screens explicitly so iPhone/iPad Safari can keep
    // that navigation hidden until the user is signed in.
    document.body.classList.toggle('login-screen', viewId === 'login');

    if (currentUser && viewId !== 'login' && !(await canCurrentUserAccessView(viewId))) {
        showToast(window.t('msg_toast_41') || 'You do not have access to this page.', 'warning');
        viewId = 'dashboard';
        currentView = 'dashboard';
    }

    const isTaskManagerView = viewId === 'tasks';
    const taskPanel = document.getElementById('taskSidePanel');
    const taskPanelOverlay = document.getElementById('taskSidePanelOverlay');
    window.closeTaskDetailsModal?.();
    if (taskPanel) taskPanel.hidden = !isTaskManagerView;
    if (taskPanelOverlay) taskPanelOverlay.hidden = !isTaskManagerView;

    if (viewId !== 'login') {
        localStorage.setItem('muqam_hr_last_view', viewId);
        if (currentUser?.id) localStorage.setItem(`muqam_hr_last_view_${currentUser.id}`, viewId);
        navItems.forEach(nav => nav.classList.toggle('active', nav.getAttribute('data-view') === viewId));
    }

    if (!isBack && viewId !== 'login') {
        if (viewHistory[viewHistory.length - 1] !== viewId) {
            viewHistory.push(viewId);
        }
    }

    if (viewId === 'dashboard' || viewId === 'users' || viewId === 'tasks' || viewId === 'admin') {
        delete window.viewHTMLCache[viewId];
    }

    const hasCache = !!window.viewHTMLCache[viewId];

    // Show cached HTML instantly if available
    if (hasCache && viewId !== 'login') {
        viewContainer.innerHTML = window.viewHTMLCache[viewId];
        lucide.createIcons();
        if (viewId === 'analytics') setTimeout(initCharts, 100);
    } else if (viewId !== 'login') {
        viewContainer.innerHTML = `<div style="display:flex; justify-content:center; padding: 4rem;"><div class="spinner"></div></div>`;
        lucide.createIcons();
    }

    let content = '';

    try {
        switch (viewId) {
            case 'contract': content = await renderContractPage(); break;
            case 'login': content = renderLogin(); break;
            case 'dashboard': content = await renderDashboard(); break;
            case 'time': content = await renderTime(); break;
            case 'leave': content = await renderLeave(); break;
            case 'leave_calculator': content = await renderLeaveCalculator(); break;
            case 'requests': content = String(currentUserRole || '').toUpperCase() === 'EMPLOYEE' ? await renderMyRequestStatuses() : await renderRequests(); break;
            case 'archived': content = await renderArchivedRequests(); break;
            case 'payroll': content = await renderPayrollModule(); break;
            case 'expenses': content = await renderExpenses(); break;
            case 'analytics': content = await renderAnalytics(); break;
            case 'admin': content = await renderAdmin(); break;
            case 'users': content = await renderUsers(); break;
            case 'contract_form': content = await window.renderContractForm(); break;
            case 'contract_preview': content = await window.renderContractPrintPreview(); break;
            case 'employees': content = await renderEmployeesDirectory(); break;
            case 'archived_contracts': content = await renderArchivedContracts(); break;
            case 'schedule': content = await renderSchedule(); break;
            case 'notifications': content = await renderNotifications(); break;
            case 'performance': content = await renderPerformance(); break;
            case 'documents': content = await renderDocuments(); break;
            case 'profile': content = await renderProfile(); break;
            case 'projects': content = await renderProjects(); break;
            case 'approvals': content = await renderApprovals(); break;
            case 'tasks': content = await renderTasksV2(); break;
            case 'tasks_v2': content = await renderTasksV2(); break;
            case 'departments': content = await renderDepartments(); break;
            case 'translations': content = await renderTranslationsPage(); break;
            case 'templates': content = await renderTemplates(); break;
            case 'custody_handover': content = await renderCustodyHandover(); break;
            case 'clients': content = await renderClients(); break;
            case 'crm': content = await renderCRM(); break;
            case 'integrations': content = await renderIntegrations(); break;
            default:
                content = `
                    <div class="page-header">
                        <h1 class="page-title">${t('nav_' + viewId) || t('nav_coming_soon')}</h1>
                    </div>
                    <div class="card" style="min-height: 400px; display: flex; align-items: center; justify-content: center;">
                        <div style="text-align: center; color: var(--color-text-secondary);">
                            <i data-lucide="hammer" style="width: 48px; height: 48px; margin-bottom: 1rem;"></i>
                            <h2>${t('nav_under_const')}</h2>
                            <p>${t('check_back')}</p>
                        </div>
                    </div>
                `;
        }
    } catch (err) {
        console.error("renderView error:", err);
        content = currentLang === 'ar'
            ? `<div class="card" style="color:red; padding: 2rem;"><h3>${t('ui_error_loading_page')}</h3><p>تعذر تحميل الصفحة. يرجى المحاولة مرة أخرى أو التواصل مع مسؤول النظام.</p></div>`
            : `<div class="card" style="color:red; padding: 2rem;"><h3>${t('ui_error_loading_page')}</h3><p>${escapeHTML(err.message || '')}</p><pre>${escapeHTML(err.stack || '')}</pre></div>`;
    }

    console.log("renderView: finished switch for", viewId, "currentView:", currentView, "content length:", content.length);

    if (currentView === viewId || viewId === 'login') {
        console.log("renderView: updating viewContainer.innerHTML for", viewId);
        window.viewHTMLCache[viewId] = content;
        // Always update the view with the fresh content!
        viewContainer.innerHTML = content;
        translateArabicInterface(viewContainer);
        try {
            lucide.createIcons();
        } catch (e) {
            console.error("lucide error:", e);
        }
        if (viewId === 'analytics') setTimeout(initCharts, 100);
        if (viewId === 'dashboard') startRecentLoginsRealtime();
        else stopRecentLoginsRealtime();
        console.log("renderView: done updating DOM.");
    } else {
        console.log("renderView: skipped DOM update because currentView changed.");
        window.viewHTMLCache[viewId] = content;
    }

    // Toggle global back button
    const backBtn = document.getElementById('globalBackButton');
    if (backBtn) {
        if (viewId !== 'login') {
            backBtn.style.display = 'inline-flex';
            backBtn.setAttribute('aria-label', currentLang === 'ar' ? 'العودة إلى الصفحة السابقة' : 'Back to previous page');
            backBtn.setAttribute('title', currentLang === 'ar' ? 'العودة إلى الصفحة السابقة' : 'Back to previous page');
        } else {
            backBtn.style.display = 'none';
        }
    }
}

function updateTopbarProfile(profile) {
    const avatarImg = document.getElementById('topbarAvatar');
    const nameSpan = document.getElementById('topbarName');
    const roleSpan = document.querySelector('.user-role');
    const displayName = getProfileDisplayName(profile);
    if (avatarImg) {
        avatarImg.src = profile.avatar_url || localStorage.getItem('user_avatar_' + profile.id) || `https://ui-avatars.com/api/?name=${encodeURIComponent(displayName)}&background=007AFF&color=fff`;
    }
    if (nameSpan) {
        nameSpan.textContent = displayName;
    }
    if (roleSpan) {
        let rawRole = profile.job_title || profile.role;
        const roleKey = 'role_' + rawRole.toLowerCase().replace(/\s+/g, '_');
        const translatedRole = t(roleKey);
        roleSpan.textContent = translatedRole && translatedRole !== roleKey ? translatedRole : localizeRuntimeText(rawRole);
        roleSpan.removeAttribute('data-i18n'); // prevent i18n from overwriting the job title
    }
}

// ==========================================
// NOTIFICATIONS VIEW
// ==========================================
async function renderNotifications() {
    if (!currentUser) return `<div class="page-header"><h1 class="page-title">${t('notif_title')}</h1></div><div class="card">${t('notif_login')}</div>`;

    const notifs = await db.fetchNotifications(currentUser.id);

    // Mark as read when viewing the page
    await db.markNotificationsRead(currentUser.id);
    const badge = document.querySelector('.notification-badge');
    if (badge) badge.style.display = 'none';

    let listHtml = `<div class="card" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">${t('notif_no_found')}</div>`;

    if (notifs && notifs.length > 0) {
        listHtml = notifs.map(n => `
            <div class="card fade-in-up" ${n.task_id ? `role="button" tabindex="0" onclick="openTaskNotification('${n.task_id}')" onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();openTaskNotification('${n.task_id}')}"` : ''} style="margin-bottom: 1rem; ${n.task_id ? 'cursor: pointer;' : ''} ${!n.is_read ? 'border-left: 4px solid var(--color-primary); background: rgba(37,99,235,0.02);' : ''}">
                <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                    <div style="display: flex; gap: 1rem; align-items: center;">
                        <div style="width: 40px; height: 40px; border-radius: 50%; background: var(--color-surface); display: flex; align-items: center; justify-content: center; color: var(--color-primary);">
                            <i data-lucide="bell"></i>
                        </div>
                        <div>
                            <div style="font-weight: 500; font-size: 1rem; color: var(--color-text);">${escapeHTML(localizeNotificationMessage(n.message))}</div>
                            ${renderNotificationDetails(n)}
                            <div style="font-size: 0.85rem; color: var(--color-text-secondary); margin-top: 0.25rem;">${new Date(n.created_at).toLocaleString()}</div>
                            ${n.event_type === 'task_approval_requested' && n.metadata?.department_manager_id === currentUser.id ? `<button type="button" class="btn btn-primary btn-sm" style="margin-top:.65rem" onclick="event.stopPropagation();approveTaskCompletion('${n.task_id}')"><i data-lucide="check-circle"></i> Approve</button>` : ''}
                        </div>
                    </div>
                    ${!n.is_read ? `<span class="badge" style="background: var(--color-primary); color: white;">${t('notif_new')}</span>` : ''}
                </div>
            </div>
        `).join('');
    }

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('notif_title')}</h1>
                <p class="page-subtitle">${t('notif_sub')}</p>
            </div>
        </div>
        <div class="dashboard-grid">
            <div class="col-span-12">
                ${listHtml}
            </div>
        </div>
    `;
}

function renderNotificationDetails(notification, compact = false) {
    const comment = String(notification?.metadata?.comment_text || '').trim();
    const attachments = Array.isArray(notification?.metadata?.attachment_links) ? notification.metadata.attachment_links.filter(Boolean) : [];
    if (!comment && !attachments.length) return '';
    return `<div class="notification-details ${compact ? 'compact' : ''}" onclick="event.stopPropagation()">
        ${comment ? `<div class="notification-comment"><strong>${taskDetailText('Comment:', 'تعليق:')}</strong><span>${escapeHTML(comment)}</span></div>` : ''}
        ${attachments.length ? `<div class="notification-attachments"><strong>${taskDetailText('Files:', 'الملفات:')}</strong>${attachments.map((url, index) => {
        let name = taskDetailText(`Attachment ${index + 1}`, `مرفق ${index + 1}`);
        try { name = decodeURIComponent(new URL(url).pathname.split('/').pop() || name).replace(/^\d+-/, ''); } catch (_) { }
        return `<a href="${escapeHTML(url)}" target="_blank" rel="noopener" download><i data-lucide="download"></i>${escapeHTML(name)}</a>`;
    }).join('')}</div>` : ''}
    </div>`;
}

// ==========================================
// NOTIFICATIONS POLLING
// ==========================================
let notificationsInterval;
async function pollNotifications() {
    if (!currentUser) return;
    const notifs = await db.fetchNotifications(currentUser.id);
    const unread = notifs.filter(n => !n.is_read);

    const badge = document.querySelector('.notification-badge');
    const dropdown = document.getElementById('notificationsDropdown');

    if (badge) {
        if (unread.length > 0) {
            badge.style.display = 'flex';
            badge.textContent = unread.length;
        } else {
            badge.style.display = 'none';
        }
    }

    if (dropdown) {
        if (notifs.length === 0) {
            dropdown.innerHTML = `<div style="padding: 1rem; text-align: center; color: var(--color-text-secondary);">${t('notif_no_dropdown')}</div>`;
        } else {
            dropdown.innerHTML = notifs.map(n => `
                <div class="notification-item ${!n.is_read ? 'unread' : ''}" ${n.task_id ? `role="button" tabindex="0" onclick="openTaskNotification('${n.task_id}')" onkeydown="if(event.key==='Enter'||event.key===' '){event.preventDefault();openTaskNotification('${n.task_id}')}"` : ''} style="padding: 10px; border-bottom: 1px solid var(--color-border); ${n.task_id ? 'cursor: pointer;' : ''} ${!n.is_read ? 'background: rgba(var(--color-primary-rgb), 0.05); font-weight: 500;' : ''}">
                    <div style="font-size: 0.875rem;">${escapeHTML(localizeNotificationMessage(n.message))}</div>
                    ${renderNotificationDetails(n, true)}
                    <div style="font-size: 0.75rem; color: var(--color-text-secondary); margin-top: 4px;">${new Date(n.created_at).toLocaleDateString()}</div>
                    ${n.event_type === 'task_approval_requested' && n.metadata?.department_manager_id === currentUser.id ? `<button type="button" class="btn btn-primary btn-sm" style="margin-top:.5rem" onclick="event.stopPropagation();approveTaskCompletion('${n.task_id}')">Approve</button>` : ''}
                </div>
            `).join('');
        }
    }
}

async function renderArchivedContracts() {
    const viewerProfile = await db.getUserProfile(currentUser?.id);
    if (!window.canCurrentUserEditContracts(viewerProfile)) {
        return '<div class="card" style="padding:2rem;">You do not have permission to view archived contracts.</div>';
    }
    const contracts = await db.fetchArchivedContracts();
    const isAdmin = currentUserRole === 'ADMIN';
    return `
        <div class="page-header fade-in-up"><div><h1 class="page-title">${t("archived_contracts")}</h1><p class="page-subtitle">Contracts retained after an employee account is removed.</p></div></div>
        <div class="card fade-in-up" style="padding:.5rem;margin-bottom:1rem;display:flex;gap:.5rem;">
            <button class="btn-secondary" type="button" onclick="renderView('employees')"><i data-lucide="users"></i> ${t("active_contracts")}</button>
            <button class="btn-primary" type="button" aria-current="page"><i data-lucide="archive"></i> ${t("archived_contracts")}</button>
        </div>
        <div class="card fade-in-up"><div class="table-responsive"><table class="data-table">
            <thead><tr><th>Former Employee</th><th>Employee No.</th><th>Contract Period</th><th>Status</th><th>Archived On</th><th>Actions</th></tr></thead>
            <tbody>${contracts.length ? contracts.map(contract => `
                <tr>
                    <td><strong>${escapeHTML(contract.former_employee_name || 'Former employee')}</strong><br><small>${escapeHTML(contract.former_employee_email || '')}</small></td>
                    <td>${escapeHTML(contract.former_employee_number ? `MQ-${contract.former_employee_number}` : 'â€”')}</td>
                    <td>${escapeHTML(contract.start_date || 'â€”')} â€“ ${escapeHTML(contract.end_date || 'Open-ended')}</td>
                    <td><span class="status-badge info">${escapeHTML(contract.status || 'Archived')}</span></td>
                    <td>${contract.archived_at ? new Date(contract.archived_at).toLocaleString() : 'â€”'}</td>
                    <td>${isAdmin ? `<button class="btn-secondary" style="color:var(--color-danger)" onclick="handleDeleteArchivedContract('${contract.id}')"><i data-lucide="trash-2"></i> Delete permanently</button>` : '<span class="status-badge info">View only</span>'}</td>
                </tr>`).join('') : '<tr><td colspan="6" style="text-align:center;padding:2rem;">No archived contracts.</td></tr>'}</tbody>
        </table></div></div>`;
}

window.handleDeleteArchivedContract = contractId => {
    if (currentUserRole !== 'ADMIN') {
        showToast(window.t('msg_toast_42') || 'Only an administrator can delete archived contracts.', 'danger');
        return;
    }
    window.showConfirmModal('Delete archived contract', 'This permanently deletes the archived contract and cannot be undone.', async () => {
        const result = await db.deleteArchivedContract(contractId);
        if (!result.success) {
            showToast(result.error?.message || 'Failed to delete the archived contract.', 'danger');
            return;
        }
        showToast(window.t('msg_toast_43') || 'Archived contract permanently deleted.', 'success');
        renderView('archived_contracts');
    });
};

window.handleContractDepartmentChange = function (departmentId) {
    const jobTitleSelect = document.getElementById('contractJobTitle');
    if (!jobTitleSelect) return;
    const titles = (window.contractJobTitlesCache || []).filter(title => title.department_id === departmentId);
    jobTitleSelect.innerHTML = `<option value="">Select Job Title</option>${titles.map(title => `<option value="${escapeHTML(title.name)}">${escapeHTML(title.name)}</option>`).join('')}`;
};

window.openTaskNotification = async function (taskId) {
    const dropdown = document.getElementById('notificationsDropdown');
    if (dropdown) dropdown.classList.remove('show');
    await renderView('tasks');
    if (window.taskCache?.[taskId]) {
        openTaskDetailsModal(taskId);
    } else {
        showToast(window.t('msg_toast_44') || 'This task is no longer available or you do not have access.', 'warning');
    }
};

window.toggleNotifications = async function () {
    const dropdown = document.getElementById('notificationsDropdown');
    if (!dropdown) return;
    dropdown.classList.toggle('show');

    if (dropdown.classList.contains('show') || dropdown.style.display === 'block') {
        await db.markNotificationsRead(currentUser.id);
        const badge = document.querySelector('.notification-badge');
        if (badge) badge.style.display = 'none';

        // Hide profile badge if shown
        const pBadge = document.getElementById('profileNotificationBadge');
        if (pBadge) pBadge.style.display = 'none';

        pollNotifications(); // Refresh list to show as read
    }
}

window.toggleProfileDropdown = function () {
    const dropdown = document.getElementById('profileDropdown');
    const notifDropdown = document.getElementById('notificationsDropdown');

    if (dropdown) {
        const isShowing = dropdown.style.display === 'block';
        dropdown.style.display = isShowing ? 'none' : 'block';

        // Hide notifications dropdown if profile dropdown is closing
        if (isShowing && notifDropdown) {
            notifDropdown.style.display = 'none';
            notifDropdown.classList.remove('show');
        }
    }
}

// Close dropdowns and modals when clicking outside
window.addEventListener('click', function (e) {
    if (e.target.classList.contains('modal')) {
        e.target.classList.remove('show', 'active');
    }
    if (e.target.id === 'taskSidePanelOverlay') {
        window.closeTaskDetailsModal();
    }

    if (!e.target.closest('.profile-dropdown-wrapper')) {
        const dropdown = document.getElementById('profileDropdown');
        if (dropdown) { dropdown.style.display = 'none'; dropdown.classList.remove('show'); dropdown.setAttribute('aria-hidden', 'true'); }

        const notifDropdown = document.getElementById('notificationsDropdown');
        if (notifDropdown) {
            notifDropdown.style.display = 'none';
            notifDropdown.classList.remove('show');
        }
    }
});

// ==========================================
// Departments Features
// ==========================================
async function renderDepartments() {
    const [departments, profiles, databaseTitles] = await Promise.all([
        db.fetchDepartments(), db.fetchAllProfiles(), db.fetchJobTitles()
    ]);
    const catalog = window.departmentManagerCatalog;
    const workbookDepartments = Object.keys(catalog);
    const liveByName = new Map(departments.map(department => [department.name.toLowerCase(), department]));
    const displayDepartments = workbookDepartments.map(name => liveByName.get(name.toLowerCase()) || {
        id: '', name, name_ar: '', head_id: null, catalogOnly: true
    });
    departments.forEach(department => {
        if (!workbookDepartments.some(name => name.toLowerCase() === department.name.toLowerCase())) displayDepartments.push(department);
    });

    const cards = displayDepartments.map((department, index) => {
        const employees = profiles.filter(profile => profile.department_id === department.id);
        const head = profiles.find(profile => profile.id === department.head_id);
        const catalogRoles = catalog[department.name] || [];
        const liveRoles = databaseTitles
            .filter(title => title.department_id === department.id && title.is_active !== false)
            .map(title => ({ title: title.name, level: title.job_level || catalogRoles.find(role => role.title === title.name)?.level || 'Other' }));
        const roles = [...catalogRoles];
        liveRoles.forEach(role => {
            if (!roles.some(existing => existing.title.toLowerCase() === role.title.toLowerCase())) roles.push(role);
        });
        const grouped = ['Entry-Level', 'Mid-Level', 'Leadership', 'Other'].map(level => ({
            level,
            roles: roles.filter(role => role.level === level)
        })).filter(group => group.roles.length);
        const searchText = `${department.name} ${roles.map(role => role.title).join(' ')}`.toLowerCase();
        const editAction = department.id
            ? `editDepartment('${department.id}')`
            : `showDepartmentCatalogModal('${department.name.replace(/'/g, "\\'")}')`;
        return `
            <article class="department-manager-card" data-department-card data-search="${escapeHTML(searchText)}" data-levels="${escapeHTML(grouped.map(group => group.level).join('|'))}">
                <div class="department-manager-card-head">
                    <div class="department-manager-icon"><i data-lucide="${['briefcase-business','megaphone','badge-dollar-sign','monitor-cog','factory'][index % 5]}"></i></div>
                    <div class="department-manager-heading">
                        <div class="department-manager-title-row">
                            <h2>${escapeHTML(department.name)}</h2>
                            ${department.catalogOnly ? '<span class="department-catalog-badge">Workbook catalog</span>' : ''}
                        </div>
                        <p>${currentLang === 'ar' ? `${roles.length} مسمى وظيفي · ${employees.length} موظف` : `${roles.length} job titles · ${employees.length} employees`}</p>
                    </div>
                    <div class="department-manager-actions">
                        <button class="btn btn-icon" aria-label="Edit department" title="Edit department" onclick="${editAction}"><i data-lucide="edit-3"></i></button>
                        ${department.id ? `<button class="btn btn-icon department-delete-button" aria-label="Delete department" title="Delete department" onclick="deleteDepartment('${department.id}')"><i data-lucide="trash-2"></i></button>` : ''}
                    </div>
                </div>
                <div class="department-manager-lead">
                    <span>Department manager</span>
                    <strong>${escapeHTML(window.formatEmployeeName(head) || 'Not assigned')}</strong>
                </div>
                <div class="department-role-groups">
                    ${grouped.map(group => `
                        <section class="department-role-group" data-role-level="${escapeHTML(group.level)}">
                            <div class="department-role-group-title"><span>${escapeHTML(group.level)}</span><small>${group.roles.length}</small></div>
                            <div class="department-role-chips">${group.roles.map(role => `<span>${escapeHTML(role.title)}</span>`).join('')}</div>
                        </section>
                    `).join('') || '<p class="department-empty-roles">No job titles added yet.</p>'}
                </div>
            </article>`;
    }).join('');

    const totalRoles = Object.values(catalog).reduce((total, roles) => total + roles.length, 0);
    const managersAssigned = displayDepartments.filter(department => department.head_id).length;

    return `
        <div class="page-header department-manager-header">
            <div>
                <h1 class="page-title">${t('ui_departments_management')}</h1>
                <p class="page-subtitle">Manage departments, reporting leads, and the job architecture from the company workbook.</p>
            </div>
            <div class="department-manager-header-actions">
                <button class="btn btn-primary" onclick="showDepartmentModal()">
                    <i data-lucide="plus"></i> New Department
                </button>
            </div>
        </div>

        <section class="department-manager-stats" aria-label="Department summary">
            <div><i data-lucide="building-2"></i><span><strong>${displayDepartments.length}</strong><small>Departments</small></span></div>
            <div><i data-lucide="contact-round"></i><span><strong>${totalRoles}</strong><small>Workbook job titles</small></span></div>
            <div><i data-lucide="users"></i><span><strong>${profiles.length}</strong><small>Employees</small></span></div>
            <div><i data-lucide="user-check"></i><span><strong>${managersAssigned}</strong><small>Managers assigned</small></span></div>
        </section>

        <section class="department-manager-toolbar">
            <label class="department-manager-search"><i data-lucide="search"></i><input type="search" placeholder="Search departments or job titles" oninput="filterDepartmentManagerCards()" id="departmentManagerSearch"></label>
            <select class="form-control" id="departmentManagerLevel" onchange="filterDepartmentManagerCards()" aria-label="Filter by job level">
                <option value="">All job levels</option>
                <option value="Entry-Level">Entry-Level</option>
                <option value="Mid-Level">Mid-Level</option>
                <option value="Leadership">Leadership</option>
            </select>
            <span id="departmentManagerResultCount">${displayDepartments.length} departments</span>
        </section>

        <div class="department-manager-grid" id="departmentManagerGrid">
            ${cards}
            <div class="department-manager-empty" id="departmentManagerEmpty" hidden><i data-lucide="search-x"></i><strong>No matching departments</strong><span>Try another name, title, or level.</span></div>
        </div>
    `;
}

function applyPreferredTheme(profile) {
    const savedTheme = profile?.id ? localStorage.getItem(`muqam_hr_theme_${profile.id}`) : null;
    const role = String(profile?.role || currentUserRole || '').toUpperCase();
    currentTheme = savedTheme || (['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(role) ? 'dark' : 'light');
    htmlElement.setAttribute('data-theme', currentTheme);
    const themeIcon = document.getElementById('themeIcon');
    if (themeIcon) themeIcon.setAttribute('data-lucide', currentTheme === 'light' ? 'moon' : 'sun');
}

window.requestOwnContractPrint = async function (contractId) {
    const profile = currentUserProfile || await db.getUserProfile(currentUser.id);
    let managerId = profile.manager_id || null;
    if (!managerId && profile.department_id) {
        const departments = await db.fetchDepartments();
        managerId = departments.find(department => department.id === profile.department_id)?.head_id || null;
    }
    if (!managerId) return showToast(t('profile_no_department_manager'), 'warning');
    const result = await db.requestContractPrint(contractId, currentUser.id, managerId);
    if (!result.success) return showToast(result.error?.message || t('profile_print_request_failed'), 'danger');
    showToast(t('profile_print_requested'), 'success');
    delete window.viewHTMLCache.profile;
    renderView('profile');
};

window.openOwnContractPrint = function (contractId) {
    window.currentContractIdToPrint = contractId;
    window.currentEmployeeIdToPrint = currentUser.id;
    renderView('contract_preview');
};

window.saveAllUserManagementChanges = async function () {
    const rows = [...document.querySelectorAll('[data-user-row]')];
    if (!rows.length) return;
    const changes = rows.map(row => ({
        id: row.dataset.userRow,
        department_id: row.querySelector('[data-directory-department]')?.value || null,
        job_title: row.querySelector('[data-directory-job-title]')?.value || '',
        role: row.querySelector('[data-user-role-select]')?.value || 'EMPLOYEE',
        manager_id: row.querySelector('[data-user-manager-select]')?.value || null
    }));
    const button = document.getElementById('saveAllUsersButton');
    if (button) {
        button.disabled = true;
        button.innerHTML = '<span class="spinner"></span> Saving...';
    }
    const result = await db.saveUserDirectoryChanges(changes);
    if (!result.success) {
        showToast(result.error?.message || 'Failed to save all user changes.', 'danger');
    } else {
        changes.forEach(change => {
            const index = (window.currentAdminUsers || []).findIndex(user => user.id === change.id);
            if (index >= 0) window.currentAdminUsers[index] = { ...window.currentAdminUsers[index], ...change };
        });
        showToast(`Saved changes for ${changes.length} users.`, 'success');
    }
    if (button) {
        button.disabled = false;
        button.innerHTML = '<i data-lucide="save"></i> Save All';
        if (window.lucide) window.lucide.createIcons();
    }
};

window.queueTranslationAutosave = function () {
    clearTimeout(window.translationAutosaveTimer);
    window.translationAutosaveTimer = setTimeout(() => {
        if (currentView === 'translations') window.saveAllTranslations(true);
    }, 700);
};

window.departmentManagerCatalog = {
    'Administrative': [
        ['Receptionist','Entry-Level'], ['Data Entry Clerk','Entry-Level'], ['Administrative Assistant','Entry-Level'],
        ['Office Manager','Mid-Level'], ['Executive Assistant (EA)','Mid-Level'], ['Facilities Coordinator','Mid-Level'],
        ['Director of Administration','Leadership'], ['Chief Administrative Officer (CAO)','Leadership']
    ],
    'Marketing': [
        ['Marketing Coordinator','Entry-Level'], ['Marketing Representative','Entry-Level'], ['Social Media Assistant','Entry-Level'], ['Graphic Designer','Mid-Level'], ['Photographer','Mid-Level'],
        ['Social Media Manager','Mid-Level'], ['SEO/SEM Specialist','Mid-Level'], ['Content Strategist','Mid-Level'],
        ['Product Marketing Manager','Mid-Level'], ['Marketing Manager','Leadership'], ['Director of Marketing','Leadership'],
        ['Chief Marketing Officer (CMO)','Leadership']
    ],
    'Sales': [
        ['Sales Development Representative (SDR)','Entry-Level'], ['Business Development Representative (BDR)','Entry-Level'],
        ['Sales Coordinator','Entry-Level'], ['Sales Representative','Entry-Level'], ['Customer Services','Entry-Level'], ['Account Executive (AE)','Mid-Level'], ['Account Manager','Mid-Level'],
        ['Customer Success Manager','Mid-Level'], ['Sales Manager','Leadership'], ['Regional Sales Director','Leadership'],
        ['Vice President (VP) of Sales','Leadership'], ['Chief Revenue Officer (CRO)','Leadership']
    ],
    'IT': [
        ['Helpdesk Technician','Entry-Level'], ['Desktop Support Analyst','Entry-Level'], ['IT Support Specialist','Entry-Level'],
        ['Systems Administrator','Mid-Level'], ['Network Engineer','Mid-Level'], ['Database Administrator','Mid-Level'],
        ['Cybersecurity Analyst','Mid-Level'], ['Software Developer','Mid-Level'], ['IT Manager','Leadership'],
        ['Director of IT','Leadership'], ['Chief Technology Officer (CTO)','Leadership']
    ],
    'Operations and Production': [
        ['Operations Assistant','Entry-Level'], ['Production Worker','Entry-Level'], ['Logistics Coordinator','Entry-Level'], ['Barista','Entry-Level'],
        ['Operations Analyst','Mid-Level'], ['Quality Assurance (QA) Specialist','Mid-Level'], ['Production Supervisor','Mid-Level'], ['Technician','Mid-Level'],
        ['Supply Chain Manager','Mid-Level'], ['Operations Manager','Leadership'], ['Director of Operations','Leadership'],
        ['Chief Operating Officer (COO)','Leadership']
    ]
};

window.selectTaskV2PrivateList = function (listId) {
    window.taskV2SelectedList = listId;
    window.taskV2SelectedProject = 'all';
    document.querySelectorAll('.task-v2-list-link').forEach(button => button.classList.toggle('active', button.getAttribute('onclick')?.includes(`'${listId}'`)));
    window.filterTasksV2();
};

window.handlePrivateTaskListSelection = function (listId) {
    const isPrivate = !!listId;
    const project = document.getElementById('taskProject');
    const assignee = document.getElementById('taskAssignee');
    const watchers = document.getElementById('enableWatchers');
    const watchersGroup = document.getElementById('taskWatchersGroup');
    if (project) {
        if (isPrivate) project.value = '';
        project.disabled = isPrivate;
    }
    if (assignee) {
        if (isPrivate) assignee.value = currentUser.id;
        assignee.disabled = isPrivate || currentUserRole === 'EMPLOYEE';
    }
    if (watchers) watchers.disabled = false;
    if (watchersGroup && isPrivate && watchers?.checked) watchersGroup.style.display = 'block';
    if (isPrivate && assignee) {
        const list = (window.taskListsCache || []).find(item => item.id === listId);
        assignee.value = list?.owner_id || currentUser.id;
    }
};
window.populateCustomMultiSelect = function(optionsContainerId, textContainerId, selectedSet, optionsCache) {
    const container = document.getElementById(optionsContainerId);
    const textContainer = document.getElementById(textContainerId);
    if (!container || !textContainer) return;

    // Temporary element to parse the HTML options from optionsCache
    const temp = document.createElement('select');
    temp.innerHTML = optionsCache;
    
    let html = '';
    let selectedCount = 0;
    let optionCount = 0;
    
    Array.from(temp.options).forEach(opt => {
        if (opt.value) { // Skip empty option if any
            optionCount++;
            const isChecked = selectedSet.has(opt.value);
            if (isChecked) selectedCount++;
            html += `
                <label class="custom-multi-select-option" onclick="event.stopPropagation()">
                    <input type="checkbox" value="${opt.value}" ${isChecked ? 'checked' : ''} onchange="window.updateCustomMultiSelectText('${optionsContainerId}', '${textContainerId}')">
                    <span>${opt.text}</span>
                </label>
            `;
        }
    });
    if (optionCount > 0) {
        const allSelected = selectedCount === optionCount;
        html = `
            <label class="custom-multi-select-option custom-multi-select-all" onclick="event.stopPropagation()">
                <input type="checkbox" data-select-all ${allSelected ? 'checked' : ''} onchange="window.toggleCustomMultiSelectAll('${optionsContainerId}', '${textContainerId}', this)">
                <span>All employees</span>
            </label>
        ` + html;
    }
    const titles = {
        taskListViewersOptions: 'Shared With',
        taskListAddUsersOptions: 'Who can add tasks',
        taskListDeleteUsersOptions: 'Who can delete tasks'
    };
    const title = localizeRuntimeText(titles[optionsContainerId] || 'Select employees');
    container.innerHTML = `<button type="button" class="multi-select-modal-backdrop" onclick="window.closeCustomMultiSelectModal('${optionsContainerId}', event)" aria-label="Close"></button>
        <section class="multi-select-modal-card">
            <header class="multi-select-modal-header"><div><span class="eyebrow">${escapeHTML(localizeRuntimeText('Task list access'))}</span><h3>${escapeHTML(title)}</h3></div><button type="button" class="icon-btn" onclick="window.closeCustomMultiSelectModal('${optionsContainerId}', event)" aria-label="Close"><i data-lucide="x"></i></button></header>
            <input type="search" class="form-control multi-select-modal-search" placeholder="${escapeHTML(localizeRuntimeText('Search employees...'))}" oninput="window.filterCustomMultiSelect('${optionsContainerId}', this.value)">
            <div class="multi-select-modal-options">${html || `<div class="multi-select-empty">${escapeHTML(localizeRuntimeText('No employees available.'))}</div>`}</div>
            <footer class="multi-select-modal-footer"><button type="button" class="btn btn-primary" onclick="window.closeCustomMultiSelectModal('${optionsContainerId}', event)">${currentLang === 'ar' ? 'تم' : 'Done'}</button></footer>
        </section>`;
    window.updateCustomMultiSelectText(optionsContainerId, textContainerId);
    if (window.lucide) window.lucide.createIcons();
};

window.openCustomMultiSelectModal = function(optionsContainerId, event) {
    event?.preventDefault();
    event?.stopPropagation();
    document.querySelectorAll('.custom-multi-select.open').forEach(item => item.classList.remove('open'));
    const container = document.getElementById(optionsContainerId);
    const owner = container?.closest('.custom-multi-select');
    if (container && owner) {
        container.dataset.modalOwner = owner.id;
        owner.classList.add('open');
        container.classList.add('open');
        document.body.appendChild(container);
    }
    document.body.classList.add('multi-select-modal-open');
    requestAnimationFrame(() => container?.querySelector('.multi-select-modal-search')?.focus());
};

window.closeCustomMultiSelectModal = function(optionsContainerId, event) {
    event?.preventDefault();
    event?.stopPropagation();
    const container = document.getElementById(optionsContainerId);
    const owner = document.getElementById(container?.dataset.modalOwner || '');
    owner?.classList.remove('open');
    container?.classList.remove('open');
    if (container && owner && container.parentElement !== owner) owner.appendChild(container);
    document.body.classList.remove('multi-select-modal-open');
};

window.filterCustomMultiSelect = function(optionsContainerId, query) {
    const normalized = String(query || '').trim().toLowerCase();
    document.getElementById(optionsContainerId)?.querySelectorAll('.custom-multi-select-option:not(.custom-multi-select-all)').forEach(option => {
        option.hidden = !!normalized && !option.textContent.toLowerCase().includes(normalized);
    });
};

window.closeNativeMultiSelectModal = function() {
    document.getElementById('nativeMultiSelectModal')?.remove();
    document.body.classList.remove('multi-select-modal-open');
};

window.openNativeMultiSelectModal = function(select) {
    if (!select?.id) return;
    window.closeNativeMultiSelectModal();
    const label = select.closest('.form-group, .property-cell')?.querySelector('label, .property-label')?.textContent?.trim() || localizeRuntimeText('Select options');
    const options = Array.from(select.options);
    const overlay = document.createElement('div');
    overlay.id = 'nativeMultiSelectModal';
    overlay.className = 'native-multi-select-modal multi-select-modal-layer';
    overlay.innerHTML = `<button type="button" class="multi-select-modal-backdrop" onclick="window.closeNativeMultiSelectModal()" aria-label="Close"></button><section class="multi-select-modal-card" role="dialog" aria-modal="true"><header class="multi-select-modal-header"><div><span class="eyebrow">${escapeHTML(localizeRuntimeText('Multi-selection'))}</span><h3>${escapeHTML(label)}</h3></div><button type="button" class="icon-btn" onclick="window.closeNativeMultiSelectModal()"><i data-lucide="x"></i></button></header><input type="search" class="form-control multi-select-modal-search" placeholder="${escapeHTML(localizeRuntimeText('Search...'))}" oninput="window.filterNativeMultiSelectModal(this.value)"><div class="multi-select-modal-options"><label class="custom-multi-select-option custom-multi-select-all"><input type="checkbox" data-native-select-all onchange="window.toggleNativeMultiSelectAll('${escapeHTML(select.id)}', this.checked)"><span>${escapeHTML(localizeRuntimeText('Select all'))}</span></label>${options.map(option => `<label class="custom-multi-select-option" data-native-search="${escapeHTML(option.text.toLowerCase())}"><input type="checkbox" value="${escapeHTML(option.value)}" ${option.selected ? 'checked' : ''} onchange="window.syncNativeMultiSelectOption('${escapeHTML(select.id)}', this)"><span>${escapeHTML(option.text)}</span></label>`).join('')}</div><footer class="multi-select-modal-footer"><button type="button" class="btn btn-primary" onclick="window.closeNativeMultiSelectModal()">${currentLang === 'ar' ? 'تم' : 'Done'}</button></footer></section>`;
    document.body.appendChild(overlay);
    document.body.classList.add('multi-select-modal-open');
    const master = overlay.querySelector('[data-native-select-all]');
    if (master) master.checked = options.length > 0 && options.every(option => option.selected);
    if (window.lucide) window.lucide.createIcons();
    requestAnimationFrame(() => overlay.querySelector('.multi-select-modal-search')?.focus());
};

window.syncNativeMultiSelectOption = function(selectId, checkbox) {
    const select = document.getElementById(selectId);
    const option = Array.from(select?.options || []).find(item => item.value === checkbox.value);
    if (option) option.selected = checkbox.checked;
    select?.dispatchEvent(new Event('change', { bubbles: true }));
};

window.toggleNativeMultiSelectAll = function(selectId, checked) {
    const select = document.getElementById(selectId);
    Array.from(select?.options || []).forEach(option => { option.selected = checked; });
    document.querySelectorAll('#nativeMultiSelectModal .multi-select-modal-options input[type="checkbox"]:not([data-native-select-all])').forEach(input => { input.checked = checked; });
    select?.dispatchEvent(new Event('change', { bubbles: true }));
};

window.filterNativeMultiSelectModal = function(query) {
    const normalized = String(query || '').trim().toLowerCase();
    document.querySelectorAll('#nativeMultiSelectModal [data-native-search]').forEach(option => { option.hidden = !!normalized && !option.dataset.nativeSearch.includes(normalized); });
};

document.addEventListener('pointerdown', event => {
    const select = event.target.closest?.('select[multiple]');
    if (!select || select.closest('.task-watcher-picker') || select.hidden) return;
    event.preventDefault();
    event.stopPropagation();
    window.openNativeMultiSelectModal(select);
}, true);

window.refreshTaskListDepartmentControls = function(selectedViewers, selectedAdd, selectedDelete) {
    const ownDepartmentId = currentUserProfile?.department_id || (window.taskAllUsersCache || []).find(user => user.id === currentUser?.id)?.department_id || '';
    const departmentId = document.getElementById('taskListDepartment')?.value || ownDepartmentId;
    const currentSelections = (containerId) => new Set(Array.from(document.querySelectorAll(`#${containerId} input[type="checkbox"]:checked:not([data-select-all])`)).map(input => input.value));
    const viewers = selectedViewers instanceof Set ? selectedViewers : currentSelections('taskListViewersOptions');
    const addUsers = selectedAdd instanceof Set ? selectedAdd : currentSelections('taskListAddUsersOptions');
    const deleteUsers = selectedDelete instanceof Set ? selectedDelete : currentSelections('taskListDeleteUsersOptions');
    const departmentUsers = (window.taskListShareCandidates || []).filter(user => user.id !== currentUser?.id && (!departmentId || user.department_id === departmentId));
    const options = departmentUsers.map(user => {
        const label = window.formatEmployeeName(user) || user.id.substring(0, 8);
        return `<option value="${escapeHTML(user.id)}">${escapeHTML(label)} (${escapeHTML(localizeRuntimeText(user.role || 'EMPLOYEE'))})</option>`;
    }).join('');
    window.populateCustomMultiSelect('taskListViewersOptions', 'taskListViewersText', viewers, options);
    window.populateCustomMultiSelect('taskListAddUsersOptions', 'taskListAddUsersText', addUsers, options);
    window.populateCustomMultiSelect('taskListDeleteUsersOptions', 'taskListDeleteUsersText', deleteUsers, options);
};

window.updateCustomMultiSelectText = function(optionsContainerId, textContainerId) {
    const container = document.getElementById(optionsContainerId);
    const textContainer = document.getElementById(textContainerId);
    if (!container || !textContainer) return;
    
    const checked = container.querySelectorAll('input[type="checkbox"]:checked:not([data-select-all])');
    const allCheckbox = container.querySelector('input[type="checkbox"][data-select-all]');
    const total = container.querySelectorAll('input[type="checkbox"]:not([data-select-all])').length;
    if (allCheckbox) {
        allCheckbox.checked = total > 0 && checked.length === total;
        allCheckbox.indeterminate = checked.length > 0 && checked.length < total;
    }
    if (checked.length === 0) {
        textContainer.textContent = localizeRuntimeText('Select employees...');
    } else if (total > 0 && checked.length === total) {
        textContainer.textContent = localizeRuntimeText('All employees');
    } else if (checked.length === 1) {
        textContainer.textContent = checked[0].nextElementSibling.textContent;
    } else {
        textContainer.textContent = currentLang === 'ar' ? `تم اختيار ${checked.length}` : `${checked.length} selected`;
    }
};

window.toggleCustomMultiSelectAll = function(optionsContainerId, textContainerId, source) {
    const container = document.getElementById(optionsContainerId);
    if (!container) return;
    container.querySelectorAll('input[type="checkbox"]:not([data-select-all])').forEach(input => {
        input.checked = !!source.checked;
    });
    window.updateCustomMultiSelectText(optionsContainerId, textContainerId);
};

window.openTaskListModal = function (listId = '') {
    const modal = document.getElementById('taskListModal');
    if (!modal) return;
    const list = (window.taskListsCache || []).find(item => item.id === listId && item.owner_id === currentUser?.id);
    document.getElementById('taskListEditId').value = list?.id || '';
    document.getElementById('taskListName').value = list?.name || '';
    document.getElementById('taskListDescription').value = list?.description || '';
    document.getElementById('taskListModalTitle').textContent = list ? t('task_list_share') : t('task_list_new');

    const departmentSelect = document.getElementById('taskListDepartment');
    if (departmentSelect) {
        const viewerDepartmentId = currentUserProfile?.department_id || (window.taskAllUsersCache || []).find(user => user.id === currentUser?.id)?.department_id || '';
        const ownDepartment = (window.taskDepartmentsCache || []).find(department => department.id === viewerDepartmentId);
        const canManageDepartments = isTaskAdmin();
        const availableDepartments = canManageDepartments ? (window.taskDepartmentsCache || []) : (ownDepartment ? [ownDepartment] : []);
        departmentSelect.innerHTML = availableDepartments.length
            ? availableDepartments.map(department => `<option value="${escapeHTML(department.id)}">${escapeHTML(getTaskDepartmentLabel(department))}</option>`).join('')
            : '<option value="">No department assigned</option>';
        departmentSelect.value = list?.department_id || viewerDepartmentId;
        departmentSelect.disabled = !canManageDepartments;
    }
    
    // Set selected viewers
    const selected = new Set(list?.shared_with || []);
    const selectedAdd = new Set(list?.can_add_users || []);
    const selectedDelete = new Set(list?.can_delete_users || []);
    window.refreshTaskListDepartmentControls(selected, selectedAdd, selectedDelete);
    
    // Set selected template
    const templateSelect = document.getElementById('taskListTemplate');
    if (templateSelect) templateSelect.value = list?.template || 'none';

    // Reset to General tab
    if (window.switchTaskListTab) window.switchTaskListTab('general');

    translateArabicInterface(modal);
    modal.classList.add('active');
    document.getElementById('taskListName').focus();
};

window.closeTaskListModal = function () {
    document.getElementById('taskListModal')?.classList.remove('active');
};

window.handleSaveTaskList = async function (event) {
    event.preventDefault();
    const id = document.getElementById('taskListEditId').value;
    const name = document.getElementById('taskListName').value.trim();
    const description = document.getElementById('taskListDescription').value.trim();
    const template = document.getElementById('taskListTemplate').value;
    const ownDepartmentId = currentUserProfile?.department_id || (window.taskAllUsersCache || []).find(user => user.id === currentUser?.id)?.department_id || '';
    const canManageDepartments = isTaskAdmin();
    const departmentSelection = canManageDepartments
        ? (document.getElementById('taskListDepartment')?.value || ownDepartmentId)
        : ownDepartmentId;
    const departmentId = departmentSelection || null;
    
    const sharedWith = Array.from(document.querySelectorAll('#taskListViewersOptions input[type="checkbox"]:checked:not([data-select-all])')).map(cb => cb.value);
    const canAddUsers = Array.from(document.querySelectorAll('#taskListAddUsersOptions input[type="checkbox"]:checked:not([data-select-all])')).map(cb => cb.value);
    const canDeleteUsers = Array.from(document.querySelectorAll('#taskListDeleteUsersOptions input[type="checkbox"]:checked:not([data-select-all])')).map(cb => cb.value);

    // Also get notifications settings
    const notifyAssignee = document.getElementById('taskListNotifyAssignee')?.checked || false;
    const notifyComplete = document.getElementById('taskListNotifyComplete')?.checked || false;
    
    if (!name || !departmentSelection) {
        showToast(window.t('msg_toast_45') || 'Select the department that can see this task list.', 'warning');
        return;
    }
    const submit = event.currentTarget.querySelector('button[type="submit"]');
    submit.disabled = true;
    
    // Note: description, template, notifyAssignee, notifyComplete are added to the payload but may need backend support to persist.
    const payload = { 
        name, 
        shared_with: sharedWith,
        department_id: departmentId,
        visible_to_all: false,
        can_add_users: canAddUsers,
        can_delete_users: canDeleteUsers,
        description,
        template,
        notify_assignee: notifyAssignee,
        notify_complete: notifyComplete
    };

    const result = id
        ? await db.updateTaskList(id, payload)
        : await db.createTaskList(name, currentUser.id, sharedWith, payload);
        
    submit.disabled = false;
    if (!result.success) {
        const missingDepartmentColumn = result.error?.code === 'PGRST204' || String(result.error?.message || '').includes('department_id');
        showToast(missingDepartmentColumn ? 'Run task_list_department_visibility_migration.sql in Supabase, then try again.' : (result.error?.message || 'Unable to save the private list.'), 'danger');
        return;
    }
    showToast(id ? 'Private list sharing updated.' : 'Private task list created.', 'success');
    window.closeTaskListModal();
    await renderView(currentView === 'tasks_v2' ? 'tasks_v2' : 'tasks');
};

window.handleDeleteTaskList = async function (id) {
    window.showConfirmModal("Delete Task List", "Are you sure you want to delete this task list and all its tasks?", async () => {
        const { error } = await db.deleteTaskList(id);
        if (error) {
            showToast("Failed to delete task list.", "danger");
        } else {
            showToast("Task list deleted successfully.", "success");
            if (window.taskV2SelectedProject === 'list_' + id) {
                window.taskV2SelectedProject = 'all';
            }
            renderView(currentView === 'tasks_v2' ? 'tasks_v2' : 'tasks');
        }
    });
};
Object.keys(window.departmentManagerCatalog).forEach(department => {
    window.departmentManagerCatalog[department] = window.departmentManagerCatalog[department].map(([title, level]) => ({ title, level }));
});

window.filterDepartmentManagerCards = () => {
    const query = (document.getElementById('departmentManagerSearch')?.value || '').trim().toLowerCase();
    const level = document.getElementById('departmentManagerLevel')?.value || '';
    const cards = [...document.querySelectorAll('[data-department-card]')];
    let visible = 0;
    cards.forEach(card => {
        const matches = (!query || card.dataset.search.includes(query)) && (!level || card.dataset.levels.split('|').includes(level));
        card.hidden = !matches;
        if (matches) visible += 1;
    });
    const count = document.getElementById('departmentManagerResultCount');
    if (count) count.textContent = `${visible} department${visible === 1 ? '' : 's'}`;
    const empty = document.getElementById('departmentManagerEmpty');
    if (empty) empty.hidden = visible !== 0;
};

window.showDepartmentCatalogModal = departmentName => {
    const roles = (window.departmentManagerCatalog[departmentName] || []).map(role => role.title);
    window.showDepartmentModal(null).then(() => {
        document.getElementById('departmentNameEn').value = departmentName;
        window.currentDepartmentJobTitles = roles;
        window.renderDepartmentJobTitlesList();
    });
};

// ==========================================
// CRM Features
// ==========================================
async function renderClients() {
    const clients = await db.fetchClients();

    let tableRows = clients.length ? clients.map(c => `
        <tr id="client-row-${c.id}">
            <td>${c.name}</td>
            <td>${c.company || '-'}</td>
            <td>${c.email || '-'}</td>
            <td>${c.phone || '-'}</td>
            <td>
                <button class="btn btn-icon" onclick="editClient('${c.id}')"><i data-lucide="edit-2"></i></button>
                <button class="btn btn-icon" style="color:var(--color-danger);" onclick="deleteClient('${c.id}')"><i data-lucide="trash-2"></i></button>
            </td>
        </tr>
    `).join('') : `<tr><td colspan="5" style="text-align:center;">${t('ui_no_clients') || 'No clients found'}</td></tr>`;

    return `
        <div class="page-header" style="display:flex; justify-content:space-between; align-items:center;">
            <div>
                <h1 class="page-title">${t('ui_clients_management')}</h1>
                <p class="page-subtitle"></p>
            </div>
            <button class="btn btn-primary" onclick="showCRMClientModal()"><i data-lucide="plus"></i> ${t('ui_new_client') || 'New Client'}</button>
        </div>
        
        <div class="card">
            <div class="table-responsive">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>${t('ui_name') || 'Name'}</th>
                            <th>${t('ui_company')}</th>
                            <th>${t('ui_email')}</th>
                            <th>${t('ui_phone')}</th>
                            <th>${t('ui_actions')}</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${tableRows}
                    </tbody>
                </table>
            </div>
        </div>
    `;
}

async function renderOrders() {
    const orders = await db.fetchOrders();
    window.currentOrdersList = orders;

    const tableRows = orders.map(o => {
        let badgeColor = 'gray';
        if (o.project_status === 'In Progress') badgeColor = 'primary';
        if (o.project_status === 'Completed') badgeColor = 'success';

        const dealTitle = (o.crm_deals && o.crm_deals.title) ? escapeHTML(o.crm_deals.title) : 'Unknown Deal';
        const clientName = (o.crm_deals && o.crm_deals.crm_clients && o.crm_deals.crm_clients.name) ? escapeHTML(o.crm_deals.crm_clients.name) : 'Unknown Client';

        const locationStr = o.event_location || '-';
        const locationHtml = locationStr.startsWith('http')
            ? `<a href="${escapeHTML(locationStr)}" target="_blank" style="color: var(--color-primary); text-decoration: underline;"><i data-lucide="map" style="width: 14px; height: 14px; margin-right: 4px; vertical-align: middle;"></i>View Map</a>`
            : escapeHTML(locationStr);

        return `
            <tr>
                <td>${dealTitle}<br><small style="color: var(--color-text-light)">${clientName}</small></td>
                <td>${escapeHTML(o.start_date || '-')}</td>
                <td>${escapeHTML(o.end_date || '-')}</td>
                <td>${locationHtml}</td>
                <td>${escapeHTML(o.invoice_amount || '0')} SAR</td>
                <td><span class="status-badge" style="background: var(--color-${badgeColor}); color: white;">${escapeHTML(o.project_status || 'Unknown')}</span></td>
                <td>
                    <button class="btn btn-icon" style="padding: 4px;" onclick="showEditOrderModal('${o.id}')" title="Edit Order">
                        <i data-lucide="edit-2"></i>
                    </button>
                    <button class="btn btn-icon" style="padding: 4px;" onclick="printOrder('${o.id}')" title="Print Order">
                        <i data-lucide="printer"></i>
                    </button>
                    <button class="btn btn-icon text-danger" style="padding: 4px;" onclick="deleteOrder('${o.id}')" title="Delete Order">
                        <i data-lucide="trash-2"></i>
                    </button>
                </td>
            </tr>
        `;
    }).join('');

    return `
        <div class="page-header">
            <h1 class="page-title">${t('ui_orders')}</h1>
        </div>
        <div class="card">
            <div style="overflow-x: auto;">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>${t('ui_deal_client') || 'Deal / Client'}</th>
                            <th>${t('ui_start_date')}</th>
                            <th>${t('ui_end_date')}</th>
                            <th>${t('ui_location')}</th>
                            <th>${t('ui_invoice_amount')}</th>
                            <th>${t('ui_project_status')}</th>
                            <th>${t('ui_actions')}</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${tableRows.length > 0 ? tableRows : `<tr><td colspan="7" style="text-align:center;">${t('ui_no_orders_found') || 'No orders found'}</td></tr>`}
                    </tbody>
                </table>
            </div>
        </div>
    `;
}

async function renderCRM() {
    const clients = await db.fetchClients();
    const deals = await db.fetchDeals();
    const users = await db.fetchUsers();

    const stages = ['LEAD', 'PITCH', 'QUOTATION', 'TECHNICAL', 'APPROVAL', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST'];

    let boardHtml = '';
    stages.forEach(stage => {
        const stageDeals = deals.filter(d => d.stage === stage);
        boardHtml += `
            <div class="kanban-col" id="crm-col-${stage}" ondrop="dropDeal(event, '${stage}')" ondragover="allowDrop(event)">
                <h3 id="crm-header-${stage}">${t('crm_' + stage.toLowerCase()) || stage} (${stageDeals.length})</h3>
                ${stageDeals.map(d => `
                    <div class="card kanban-card" id="deal-card-${d.id}" draggable="true" ondragstart="dragDeal(event, '${d.id}')" data-stage="${stage}" data-workflow-status="${escapeHTML(d.workflow_status || 'NOT_STARTED')}" style="position: relative;">
                        <div style="position: absolute; top: 5px; right: 5px; display: flex; gap: 4px;">
                            <button class="btn btn-icon" style="padding: 2px;" onclick="showCRMDealModal('${d.id}', true)" title="View Deal">
                                <i data-lucide="eye" style="width: 14px; height: 14px; color: var(--color-text-secondary);"></i>
                            </button>
                            <button class="btn btn-icon" style="padding: 2px;" onclick="showCRMDealModal('${d.id}')" title="Edit Deal">
                                <i data-lucide="edit-2" style="width: 14px; height: 14px; color: var(--color-text-secondary);"></i>
                            </button>
                        </div>
                        <div style="font-weight: 500; margin-bottom: 0.5rem; padding-right: 45px;">${d.title}</div>
                        <div style="color: var(--color-text-secondary); font-size: 0.875rem; margin-bottom: 0.5rem;">
                            <i data-lucide="building-2" style="width: 14px; height: 14px;"></i> 
                            ${d.crm_clients ? d.crm_clients.name : 'Unknown Client'}
                        </div>
                        ${d.closing_date ? `<div style="font-size: 0.75rem; color: var(--color-danger); margin-bottom: 0.5rem;"><i data-lucide="calendar" style="width: 12px; height: 12px;"></i> Close: ${d.closing_date}</div>` : ''}
                        ${d.assigned_to ? `<div style="font-size: 0.75rem; color: var(--color-text-secondary); margin-bottom: 0.5rem;"><i data-lucide="user" style="width: 12px; height: 12px;"></i> ${window.formatEmployeeName(users.find(u => u.id === d.assigned_to) || {}) || 'User'}</div>` : ''}
                        ${stage === 'APPROVAL' ? `<div class="status-badge ${d.workflow_status === 'APPROVED' ? 'success' : (d.workflow_status === 'REJECTED' ? 'danger' : 'warning')}" style="margin-bottom:.5rem;">${t('crm_workflow_' + String(d.workflow_status || 'not_started').toLowerCase()) || String(d.workflow_status || 'NOT_STARTED').replace(/_/g, ' ')}</div>` : ''}
                        <div class="status-badge success" style="margin-top: auto;">SAR ${d.amount}</div>
                        <button type="button" class="btn btn-secondary btn-sm deal-workflow-button" onclick="openDealWorkflowModal('${d.id}')"><i data-lucide="git-branch"></i> ${t('crm_workflow') || 'Workflow'}</button>
                    </div>
                `).join('')}
            </div>
        `;
    });

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('ui_crm_pipeline')}</h1>
                <p class="page-subtitle">Manage clients and deals</p>
            </div>
        </div>

        <div style="display:flex;gap:.5rem;margin-bottom:2rem;flex-wrap:wrap;" class="fade-in-up">
            <button class="btn btn-primary" data-crm-tab="pipeline" onclick="switchCrmTab('pipeline')"><span data-i18n="ui_deal_pipeline">${t('ui_deal_pipeline') || 'Deal Pipeline'}</span></button>
            <button class="btn btn-secondary" data-crm-tab="clients" onclick="switchCrmTab('clients')"><span data-i18n="ui_client_directory">${t('ui_client_directory') || 'Client Directory'}</span></button>
        </div>

        <div id="crm-tab-content" class="dashboard-grid fade-in-up">
            <div id="crm-pipeline" class="card col-span-3" style="grid-column: span 12 / span 12;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 1rem;">
                    <div class="card-title">${t('ui_deal_pipeline') || 'Deal Pipeline'}</div>
                    <button class="btn btn-primary" onclick="showCRMDealModal()"><i data-lucide="plus"></i> ${t('ui_new_deal') || 'New Deal'}</button>
                </div>
                <div class="kanban-board" style="display:flex; gap: 1rem; overflow-x: auto; padding-bottom: 1rem;">
                    ${boardHtml}
                </div>
            </div>

            <div id="crm-clients" class="card col-span-3" style="grid-column: span 12 / span 12; display: none;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 1rem;">
                    <div class="card-title">${t('ui_client_directory') || 'Client Directory'}</div>
                    <button class="btn btn-primary" onclick="showCRMClientModal()"><i data-lucide="plus"></i> ${t('ui_new_client') || 'New Client'}</button>
                </div>
                <div class="table-responsive">
                    <table class="table">
                        <thead>
                            <tr>
                                <th>${t('ui_name') || 'Name'}</th>
                                <th>${t('ui_company')}</th>
                                <th>${t('ui_email')}</th>
                                <th>${t('ui_phone')}</th>
                                <th>${t('ui_status')}</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${clients.map(c => `
                                <tr>
                                    <td>${c.name}</td>
                                    <td>${c.company || '-'}</td>
                                    <td>${c.email || '-'}</td>
                                    <td>${c.phone || '-'}</td>
                                    <td><span class="status-badge ${c.status === 'ACTIVE' ? 'success' : 'danger'}">${c.status}</span></td>
                                </tr>
                            `).join('')}
                            ${clients.length === 0 ? `<tr><td colspan="5" class="text-center">${t('ui_no_clients_yet') || 'No clients yet'}</td></tr>` : ''}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    `;
}

window.switchCrmTab = function (tabId) {
    document.querySelectorAll('[data-crm-tab]').forEach(btn => {
        if (btn.getAttribute('data-crm-tab') === tabId) {
            btn.classList.add('btn-primary');
            btn.classList.remove('btn-secondary');
        } else {
            btn.classList.add('btn-secondary');
            btn.classList.remove('btn-primary');
        }
    });

    const pipelineEl = document.getElementById('crm-pipeline');
    const clientsEl = document.getElementById('crm-clients');
    if (pipelineEl) pipelineEl.style.display = tabId === 'pipeline' ? 'block' : 'none';
    if (clientsEl) clientsEl.style.display = tabId === 'clients' ? 'block' : 'none';
};

const dealApprovalStageLabels = {
    MARKETING_MANAGER: 'crm_marketing_manager',
    GENERAL_MANAGER: 'crm_general_manager',
    OPERATIONS_MANAGER: 'crm_operations_manager'
};

function dealEmployeeName(profile) {
    return currentLang === 'ar' && profile?.display_name_ar
        ? profile.display_name_ar
        : (window.formatEmployeeName(profile));
}

window.openDealWorkflowModal = async function (dealId) {
    const [deals, users, workflow] = await Promise.all([db.fetchDeals(), db.fetchUsers(), db.fetchDealWorkflow(dealId)]);
    const deal = deals.find(item => item.id === dealId);
    if (!deal) return showToast(t('crm_deal_not_found') || 'Deal not found.', 'danger');
    document.getElementById('workflowDealId').value = dealId;
    document.getElementById('dealWorkflowName').textContent = deal.title;
    const options = `<option value="">${t('crm_select_employee') || 'Select employee'}</option>` + users.map(user =>
        `<option value="${user.id}">${escapeHTML(dealEmployeeName(user))}${user.job_title ? ` â€” ${escapeHTML(user.job_title)}` : ''}</option>`
    ).join('');
    ['workflowMarketingManager', 'workflowGeneralManager', 'workflowOperationsManager'].forEach(id => {
        document.getElementById(id).innerHTML = options;
    });
    const titleMatch = (pattern) => users.find(user => pattern.test(String(user.job_title || '')))?.id || '';
    document.getElementById('workflowMarketingManager').value = titleMatch(/marketing.*manager/i);
    document.getElementById('workflowGeneralManager').value = titleMatch(/general manager|\bGM\b/i);
    document.getElementById('workflowOperationsManager').value = titleMatch(/operations?.*manager/i);
    renderDealWorkflowContents(workflow);
    document.getElementById('workflowSetupSection').style.display = workflow.approvals.length ? 'none' : 'block';
    document.getElementById('dealWorkflowModal').classList.add('show');
    updateTranslations();
    if (window.lucide) window.lucide.createIcons();
};

window.closeDealWorkflowModal = function () {
    document.getElementById('dealWorkflowModal').classList.remove('show');
};

function renderDealWorkflowContents(workflow) {
    const approvalsEl = document.getElementById('dealApprovalSteps');
    const nextPending = workflow.approvals.find(step => step.status === 'PENDING');
    approvalsEl.innerHTML = workflow.approvals.length ? workflow.approvals.map(step => {
        const canDecide = step.status === 'PENDING' && step.id === nextPending?.id && (step.approver_id === currentUser?.id || currentUserRole === 'ADMIN');
        const label = t(dealApprovalStageLabels[step.stage_key]) || step.stage_key.replace(/_/g, ' ');
        return `<article class="deal-approval-step ${step.status.toLowerCase()}">
            <div class="deal-approval-index">${step.status === 'APPROVED' ? '✓' : (step.status === 'REJECTED' ? '×' : step.step_order)}</div>
            <div class="deal-approval-copy"><strong>${escapeHTML(label)}</strong><span>${escapeHTML(dealEmployeeName(step.profiles))}</span>${step.decision_note ? `<small>${escapeHTML(step.decision_note)}</small>` : ''}</div>
            ${canDecide ? `<div class="deal-approval-actions"><button class="btn btn-primary btn-sm" onclick="decideDealApproval('${step.id}','APPROVED')">${t('crm_approve') || 'Approve'}</button><button class="btn btn-secondary btn-sm" onclick="decideDealApproval('${step.id}','REJECTED')">${t('crm_reject') || 'Reject'}</button></div>` : `<span class="status-badge ${step.status === 'APPROVED' ? 'success' : (step.status === 'REJECTED' ? 'danger' : 'warning')}">${escapeHTML(t('crm_status_' + step.status.toLowerCase()) || step.status)}</span>`}
        </article>`;
    }).join('') : `<p class="empty-state-inline">${t('crm_approval_not_started') || 'Approval has not started.'}</p>`;

    document.getElementById('dealAttachmentList').innerHTML = workflow.attachments.length ? workflow.attachments.map(file =>
        `<a class="deal-attachment-item" href="${escapeHTML(file.file_url)}" target="_blank" rel="noopener"><i data-lucide="paperclip"></i><span><strong>${escapeHTML(file.file_name)}</strong><small>${escapeHTML(file.description || file.category.replace(/_/g, ' '))}</small></span></a>`
    ).join('') : `<p class="empty-state-inline">${t('crm_no_files') || 'No files uploaded.'}</p>`;

    document.getElementById('dealActivityList').innerHTML = workflow.activity.length ? workflow.activity.map(item =>
        `<div class="deal-activity-item"><span></span><div><strong>${escapeHTML(String(item.action || '').replace(/_/g, ' '))}</strong><small>${escapeHTML(dealEmployeeName(item.profiles))} · ${new Date(item.created_at).toLocaleString(currentLang === 'ar' ? 'ar-SA' : 'en-US')}</small>${item.note ? `<p>${escapeHTML(item.note)}</p>` : ''}</div></div>`
    ).join('') : `<p class="empty-state-inline">${t('crm_no_activity') || 'No activity recorded yet.'}</p>`;
}

window.startDealApprovalWorkflow = async function () {
    const dealId = document.getElementById('workflowDealId').value;
    const approvers = {
        marketingManager: document.getElementById('workflowMarketingManager').value,
        generalManager: document.getElementById('workflowGeneralManager').value,
        operationsManager: document.getElementById('workflowOperationsManager').value
    };
    if (Object.values(approvers).some(value => !value)) return showToast(t('crm_select_all_approvers') || 'Select all three approvers.', 'warning');
    const result = await db.startDealApproval(dealId, approvers);
    if (!result.success) return showToast(result.error?.message || t('crm_approval_start_failed') || 'Could not start approval.', 'danger');
    showToast(t('crm_approval_started') || 'Approval workflow started.', 'success');
    window.closeDealWorkflowModal();
    if (currentView === 'crm') renderView('crm');
};

window.decideDealApproval = async function (stepId, decision) {
    const note = await window.showPromptModal(decision === 'REJECTED' ? (t('crm_rejection_note_prompt') || 'Enter the rejection reason:') : (t('crm_approval_note_prompt') || 'Optional approval note:'), t('crm_approval'));
    if (note === null) return;
    if (decision === 'REJECTED' && !String(note || '').trim()) return showToast(t('crm_rejection_note_required') || 'A rejection reason is required.', 'warning');
    const result = await db.decideDealApproval(stepId, decision, note || '');
    if (!result.success) return showToast(result.error?.message || t('crm_decision_failed') || 'Could not save the decision.', 'danger');
    const dealId = document.getElementById('workflowDealId').value;
    const workflow = await db.fetchDealWorkflow(dealId);
    renderDealWorkflowContents(workflow);
    showToast(decision === 'APPROVED' ? (t('crm_approval_saved') || 'Approval saved.') : (t('crm_rejection_saved') || 'Rejection saved.'), 'success');
    if (window.lucide) window.lucide.createIcons();
};

window.handleDealAttachmentUpload = async function (event) {
    event.preventDefault();
    const dealId = document.getElementById('workflowDealId').value;
    const file = document.getElementById('dealAttachmentFile').files[0];
    if (!file) return;
    if (file.size > 15 * 1024 * 1024) return showToast(t('crm_file_too_large') || 'The maximum file size is 15 MB.', 'warning');
    const result = await db.uploadDealAttachment(dealId, currentUser.id, file, document.getElementById('dealAttachmentCategory').value, document.getElementById('dealAttachmentDescription').value);
    if (!result.success) return showToast(result.error?.message || t('crm_upload_failed') || 'Upload failed.', 'danger');
    event.target.reset();
    renderDealWorkflowContents(await db.fetchDealWorkflow(dealId));
    showToast(t('crm_file_uploaded') || 'File uploaded.', 'success');
    if (window.lucide) window.lucide.createIcons();
};

// Drag & Drop Deal Logic
window.allowDrop = function (ev) {
    ev.preventDefault();
}

window.dragDeal = function (ev, dealId) {
    ev.dataTransfer.setData("dealId", dealId);
}

window.moveDealCard = function (dealId, newStage) {
    const card = document.getElementById(`deal-card-${dealId}`);
    if (card) {
        const oldStage = card.getAttribute('data-stage');
        if (oldStage === newStage) return;

        const targetCol = document.getElementById(`crm-col-${newStage}`);
        if (targetCol) {
            targetCol.appendChild(card);
            card.setAttribute('data-stage', newStage);

            const oldHeader = document.getElementById(`crm-header-${oldStage}`);
            const newHeader = document.getElementById(`crm-header-${newStage}`);

            if (oldHeader) {
                const oldText = oldHeader.innerText;
                const match = oldText.match(/\((\d+)\)/);
                if (match) oldHeader.innerText = oldText.replace(/\(\d+\)/, `(${parseInt(match[1]) - 1})`);
            }
            if (newHeader) {
                const newText = newHeader.innerText;
                const match = newText.match(/\((\d+)\)/);
                if (match) newHeader.innerText = newText.replace(/\(\d+\)/, `(${parseInt(match[1]) + 1})`);
            }
        }
    }
};

window.dropDeal = async (ev, newStage) => {
    ev.preventDefault();
    const dealId = ev.dataTransfer.getData("dealId");
    if (!dealId) return;

    const card = document.getElementById(`deal-card-${dealId}`);
    const oldStage = card ? card.getAttribute('data-stage') : null;
    if (oldStage === newStage) return;

    if (newStage === 'APPROVAL') {
        await window.openDealWorkflowModal(dealId);
        return;
    }

    if ((newStage === 'PROPOSAL' || newStage === 'NEGOTIATION' || newStage === 'WON') && card?.getAttribute('data-workflow-status') !== 'APPROVED') {
        showToast(t('crm_approval_required') || 'Complete all internal approvals before advancing this deal.', 'warning');
        await window.openDealWorkflowModal(dealId);
        return;
    }

    if (newStage === 'LOST') {
        document.getElementById('lostDealId').value = dealId;
        document.getElementById('lostOldStage').value = oldStage || '';
        document.getElementById('lostReasonText').value = '';
        document.getElementById('lostReasonModal').classList.add('show');
        return;
    }

    if (newStage === 'WON') {
        document.getElementById('orderDealId').value = dealId;
        document.getElementById('orderStartDate').value = '';
        document.getElementById('orderEndDate').value = '';
        document.getElementById('orderLocation').value = '';
        document.getElementById('orderInvoiceAmount').value = '';
        document.getElementById('orderProjectStatus').value = 'Not Confirmed';
        document.getElementById('orderNotes').value = '';
        document.getElementById('orderEventDate').value = '';
        document.getElementById('orderPaidAmount').value = '';
        document.getElementById('orderUninstallationDate').value = '';
        document.getElementById('crmOrderModal').classList.add('show');
        if (window.lucide) window.lucide.createIcons();
        return;
    }

    window.moveDealCard(dealId, newStage);

    const res = newStage === 'PROPOSAL'
        ? await db.updateDeal(dealId, { stage: newStage, proposal_sent_at: new Date().toISOString() })
        : await db.updateDealStage(dealId, newStage);
    if (res.success) {
        await db.logDealActivity(dealId, 'STAGE_CHANGED', oldStage, newStage, null);
        showToast(t('toast_deal_moved_to') + newStage, "success");
    } else {
        showToast(t('toast_failed_to_move_deal'), "danger");
    }
};

window.closeLostReasonModal = () => {
    document.getElementById('lostReasonModal').classList.remove('show');
};

window.handleLostReasonSubmit = async (e) => {
    e.preventDefault();
    const dealId = document.getElementById('lostDealId').value;
    const reason = document.getElementById('lostReasonText').value;
    const oldStage = document.getElementById('lostOldStage').value;

    closeLostReasonModal();
    window.moveDealCard(dealId, 'LOST');

    // Instead of updateDealStage, we update the full deal or updateDeal with reason
    const res = await db.updateDeal(dealId, { stage: 'LOST', lost_reason: reason });
    if (res.success) {
        showToast(t('toast_deal_marked_as_lost'), "success");
    } else {
        showToast(t('toast_failed_to_update_deal'), "danger");
    }
};

window.closeCRMOrderModal = () => {
    document.getElementById('crmOrderModal').classList.remove('show');
};

window.handleOrderSubmit = async (e) => {
    e.preventDefault();
    const dealId = document.getElementById('orderDealId').value;

    const projectData = {
        start_date: document.getElementById('orderStartDate').value || null,
        end_date: document.getElementById('orderEndDate').value || null,
        event_location: document.getElementById('orderLocation').value || null,
        invoice_amount: parseFloat(document.getElementById('orderInvoiceAmount').value) || 0,
        project_status: document.getElementById('orderProjectStatus').value || 'Not Confirmed',
        notes: document.getElementById('orderNotes').value || null,
        event_date: document.getElementById('orderEventDate').value || null,
        paid_amount: parseFloat(document.getElementById('orderPaidAmount').value) || 0,
        uninstallation_date: document.getElementById('orderUninstallationDate').value || null,
    };

    closeCRMOrderModal();
    window.moveDealCard(dealId, 'WON');

    const res = await db.createProjectFromWonDeal(projectData, dealId);
    if (res.success) {
        showToast(t('crm_project_created_deal_won') || 'Project created and deal marked as won.', "success");
        await db.triggerWebhooks('deal_won', { deal_id: dealId });
    } else {
        showToast(res.error?.message || t('crm_project_create_failed') || 'Failed to create the project.', "danger");
    }
};

window.showEditOrderModal = async (id) => {
    const orders = await db.fetchOrders();
    const order = orders.find(o => o.id === id);
    if (!order) return showToast(t('toast_order_not_found'), "danger");

    document.getElementById('editOrderId').value = id;
    document.getElementById('editOrderStartDate').value = order.start_date || '';
    document.getElementById('editOrderEndDate').value = order.end_date || '';
    document.getElementById('editOrderLocation').value = order.event_location || '';
    document.getElementById('editOrderInvoiceAmount').value = order.invoice_amount || '';
    document.getElementById('editOrderProjectStatus').value = order.project_status || 'Not Confirmed';
    document.getElementById('editOrderNotes').value = order.notes || '';
    document.getElementById('editOrderEventDate').value = order.event_date || '';
    document.getElementById('editOrderPaidAmount').value = order.paid_amount || '';
    document.getElementById('editOrderUninstallationDate').value = order.uninstallation_date || '';

    document.getElementById('editOrderModal').classList.add('show');
    if (window.lucide) window.lucide.createIcons();
};

window.closeEditOrderModal = () => {
    document.getElementById('editOrderModal').classList.remove('show');
};

window.handleEditOrderSubmit = async (e) => {
    e.preventDefault();
    const id = document.getElementById('editOrderId').value;

    const orderData = {
        start_date: document.getElementById('editOrderStartDate').value || null,
        end_date: document.getElementById('editOrderEndDate').value || null,
        event_location: document.getElementById('editOrderLocation').value || null,
        invoice_amount: parseFloat(document.getElementById('editOrderInvoiceAmount').value) || 0,
        project_status: document.getElementById('editOrderProjectStatus').value || 'Not Confirmed',
        notes: document.getElementById('editOrderNotes').value || null,
        event_date: document.getElementById('editOrderEventDate').value || null,
        paid_amount: parseFloat(document.getElementById('editOrderPaidAmount').value) || 0,
        uninstallation_date: document.getElementById('editOrderUninstallationDate').value || null,
    };

    const res = await db.updateOrder(id, orderData);
    if (res.success) {
        showToast(t('toast_order_updated_successfully'), "success");
        closeEditOrderModal();
        if (currentView === 'orders') renderView('orders');
    } else {
        showToast(t('toast_failed_to_update_order'), "danger");
    }
};

window.deleteOrder = (orderId) => {
    document.getElementById('deleteOrderIdInput').value = orderId;
    document.getElementById('confirmDeleteOrderModal').classList.add('show');
    if (window.lucide) window.lucide.createIcons();
};

window.closeConfirmDeleteOrderModal = () => {
    document.getElementById('confirmDeleteOrderModal').classList.remove('show');
    document.getElementById('deleteOrderIdInput').value = '';
};

window.executeDeleteOrder = async () => {
    const orderId = document.getElementById('deleteOrderIdInput').value;
    if (!orderId) return;

    const res = await db.deleteOrder(orderId);
    if (res.success) {
        showToast(t('toast_order_deleted_successfully'), "success");
        closeConfirmDeleteOrderModal();
        if (currentView === 'orders') renderView('orders');
    } else {
        showToast(t('toast_failed_to_delete_order'), "danger");
    }
};

window.printWithLetterhead = (title, contentHTML) => {
    const printContents = `
        <div class="html-letterhead">
            <div class="hl-header">
                <div class="hl-top-bar"></div>
                <img src="${window.location.origin}/images/logo.png" style="width: 200px; float: right; margin-top: 50px; margin-right: 40px;">
            </div>
            <div class="hl-footer">
                <div class="hl-text-container">
                    <div class="hl-text-left">
                        <strong style="font-size: 13px;">Muqam | Exhibition & Conference Organization</strong><br><br>
                        <span style="color: #0000FF; display:inline-block; transform:translateY(2px);"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"></path></svg></span> +966 50 708 4704 &nbsp;&nbsp; 
                        <span style="color: #0000FF; display:inline-block; transform:translateY(2px);"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"></path><polyline points="22,6 12,13 2,6"></polyline></svg></span> info@muqam.net &nbsp;&nbsp; 
                        <span style="color: #0000FF; display:inline-block; transform:translateY(2px);"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="2" y1="12" x2="22" y2="12"></line><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path></svg></span> www.muqam.net<br>
                        <span style="color: #0000FF; display:inline-block; transform:translateY(2px);"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path><circle cx="12" cy="10" r="3"></circle></svg></span> St.Arafat BnÂ°3113 ,7558 Al Hamra Dist. Jeddah PC. 23323 ,Kingdom of Saudi Arabia
                    </div>
                    <div class="hl-text-right" dir="rtl">
                        <strong style="font-size: 15px; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;">Ù…ÙÙ‚Ø§Ù… | Ù„ØªÙ†Ø¸ÙŠÙ… Ø§Ù„Ù…Ø¹Ø§Ø±Ø¶ ÙˆØ§Ù„Ù…Ø¤ØªÙ…Ø±Ø§Øª</strong><br><br>
                        Ø§Ù„ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¶Ø±ÙŠØ¨ÙŠ VAT : 311460343900003<br>
                        Ø§Ù„Ø³Ø¬Ù„ Ø§Ù„ØªØ¬Ø§Ø±ÙŠ CR : 7031641660
                    </div>
                </div>
                <div class="hl-ribbon-top"></div>
                <div class="hl-ribbon"></div>
            </div>
        </div>
        <div class="print-container">
            ${title ? `
            <div class="print-header">
                <div class="print-title">
                    <h2>${title}</h2>
                    <p>Date: ${new Date().toLocaleDateString()}</p>
                </div>
            </div>` : ''}
            <div class="print-body" style="${!title ? 'padding-top: 150px;' : ''}">
                ${contentHTML}
            </div>
        </div>
    `;

    const printStyles = `
        <style>
            @page {
                size: A4;
                margin: 0;
            }
            body {
                font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                margin: 0;
                padding: 0;
                color: #000;
                background: #fff;
                -webkit-print-color-adjust: exact !important;
                print-color-adjust: exact !important;
                position: relative;
            }
            .html-letterhead {
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                z-index: -1;
                pointer-events: none;
            }
            .hl-header {
                position: absolute;
                top: 0;
                left: 0;
                width: 100%;
            }
            .hl-top-bar {
                height: 12px;
                background: #0000FF;
                width: 100%;
                position: absolute;
                top: 0;
                left: 0;
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            .hl-text-container {
                display: flex;
                justify-content: space-between;
                padding: 0 40px;
                margin-bottom: 40px;
                font-size: 11px;
                line-height: 1.6;
                color: #000;
                font-family: Arial, sans-serif;
            }
            .hl-text-left { text-align: left; }
            .hl-text-right { text-align: right; }
            .hl-ribbon {
                height: 25px;
                background: linear-gradient(90deg, #0000FF, #66b2ff, #0000FF);
                width: 100%;
                position: absolute;
                bottom: 0;
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            .hl-ribbon-top {
                height: 4px;
                background: #E0E0FF;
                width: 100%;
                position: absolute;
                bottom: 27px;
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            .print-container {
                display: flex;
                flex-direction: column;
                min-height: 100vh;
                position: relative;
                z-index: 1;
            }
            .print-title {
                margin-top: 150px;
                padding: 0 40px;
            }
            .print-body {
                flex-grow: 1;
                padding: 10px 50px 20px 50px;
                min-height: 600px;
            }
            
            /* Universal Table Styles for Print */
            table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
            th, td { border: 1px solid #ddd; padding: 10px; text-align: left; font-size: 12px; }
            th { background-color: #f5f5f5 !important; font-weight: 600; }
        </style>
    `;

    let printFrame = document.getElementById('printFrame');
    if (!printFrame) {
        printFrame = document.createElement('iframe');
        printFrame.id = 'printFrame';
        printFrame.style.position = 'absolute';
        printFrame.style.width = '0px';
        printFrame.style.height = '0px';
        printFrame.style.border = 'none';
        document.body.appendChild(printFrame);
    }

    printFrame.contentDocument.open();
    printFrame.contentDocument.write(`
        <!DOCTYPE html>
        <html>
            <head>
                <title>${title}</title>
                ${printStyles}
            </head>
            <body>${printContents}</body>
        </html>
    `);
    printFrame.contentDocument.close();

    // Wait for images to load before printing
    setTimeout(() => {
        printFrame.contentWindow.focus();
        printFrame.contentWindow.print();
    }, 500);
};

window.printOrder = async (orderId) => {
    if (!window.currentOrdersList) return;
    const order = window.currentOrdersList.find(o => o.id === orderId);
    if (!order) return;

    // Fetch full deal to get client phone if available
    let clientPhone = '';
    if (order.crm_deals && order.crm_deals.client_id) {
        const clients = await db.fetchClients();
        const client = clients.find(c => c.id === order.crm_deals.client_id);
        if (client && client.phone) {
            clientPhone = escapeHTML(client.phone);
        }
    }

    const dealTitle = (order.crm_deals && order.crm_deals.title) ? escapeHTML(order.crm_deals.title) : 'Unknown Deal';
    const clientName = (order.crm_deals && order.crm_deals.crm_clients && order.crm_deals.crm_clients.name) ? escapeHTML(order.crm_deals.crm_clients.name) : 'Unknown Client';
    const locationStr = escapeHTML(order.event_location || '-');

    const printContents = `
        <div dir="rtl" style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; font-size: 16px;">
            <div style="height: 12px; background: #0000FF; width: 100%; margin-bottom: 20px;"></div>
            <h1 style="text-align: center; font-size: 36px; font-weight: bold; margin-bottom: 40px; margin-top: 0;">${t('ui_')}</h1>
            
            <table style="width: 100%; border-collapse: collapse; margin-bottom: 30px; border: 1px solid #000;">
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">Ø§Ù„ØªØ§Ø±ÙŠØ® :</td>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%;"></td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">Ø§Ù„ÙˆÙ‚Øª :</td>
                    <td style="border: 1px solid #000; padding: 10px;"></td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">Ø±Ù‚Ù… Ø§Ù„Ø§ÙˆØ±Ø¯Ø± :</td>
                    <td style="border: 1px solid #000; padding: 10px;">${order.id || ''}</td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">Ù…Ø³Ø¤ÙˆÙ„ ØªØ£ÙƒÙŠØ¯ Ø§Ù„Ø§ÙˆØ±Ø¯Ø± :</td>
                    <td style="border: 1px solid #000; padding: 10px;"></td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">Ø§Ù„Ù…ÙˆØ¸Ù :</td>
                    <td style="border: 1px solid #000; padding: 10px;"></td>
                </tr>
            </table>

            <table style="width: 100%; border-collapse: collapse; margin-bottom: 30px; border: 1px solid #000;">
                <tr>
                    <th colspan="2" style="border: 1px solid #000; padding: 10px; text-align: center; background-color: #f9f9f9 !important; font-weight: bold;">${t('ui_')}</th>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%; text-align: right;">Ø§Ø³Ù… Ø§Ù„Ø¹Ù…ÙŠÙ„ : ${clientName}</td>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%; text-align: right;">Ø±Ù‚Ù… Ù‡Ø§ØªÙ Ø§Ù„Ø¹Ù…ÙŠÙ„ : ${clientPhone}</td>
                </tr>
            </table>

            <table style="width: 100%; border-collapse: collapse; margin-bottom: 30px; border: 1px solid #000;">
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">ØªØ§Ø±ÙŠØ® Ø§Ù„Ø­ÙÙ„ : ${escapeHTML(order.start_date || '')}</td>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%; text-align: right;">ÙØ±ÙŠÙ‚ Ø§Ù„ØªØ±ÙƒÙŠØ¨ :</td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">ÙˆÙ‚Øª Ø§Ù„Ø­ÙÙ„ :</td>
                    <td rowspan="3" style="border: 1px solid #000; padding: 10px; vertical-align: top;"></td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">Ù…ÙˆØ¹Ø¯ Ø§Ù„ØªØ±ÙƒÙŠØ¨ :</td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">Ù…ÙˆØ¹Ø¯ Ø§Ù„ÙÙƒ :</td>
                </tr>
            </table>
        </div>

        <div style="page-break-before: always; padding-top: 50px;" dir="rtl">
            <h1 style="text-align: center; font-size: 36px; font-weight: bold; margin-bottom: 40px;">${t('ui_')}</h1>
            
            <table style="width: 100%; border-collapse: collapse; margin-bottom: 30px; text-align: center; border: 1px solid #000;">
                <tr>
                    <th style="border: 1px solid #000; padding: 10px; width: 5%; background-color: #f9f9f9 !important; text-align: center; font-weight: bold;">#</th>
                    <th style="border: 1px solid #000; padding: 10px; width: 30%; background-color: #f9f9f9 !important; text-align: center; font-weight: bold;">${t('ui_')}</th>
                    <th style="border: 1px solid #000; padding: 10px; width: 25%; background-color: #f9f9f9 !important; text-align: center; font-weight: bold;">${t('ui_')}</th>
                    <th style="border: 1px solid #000; padding: 10px; width: 10%; background-color: #f9f9f9 !important; text-align: center; font-weight: bold;">${t('ui_')}</th>
                    <th style="border: 1px solid #000; padding: 10px; width: 30%; background-color: #f9f9f9 !important; text-align: center; font-weight: bold;">${t('ui_')}</th>
                </tr>
                <tr><td style="border: 1px solid #000; height: 50px;">Ù¡</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
                <tr><td style="border: 1px solid #000; height: 50px;">Ù¢</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
                <tr><td style="border: 1px solid #000; height: 50px;">Ù£</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
                <tr><td style="border: 1px solid #000; height: 50px;">Ù¤</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
                <tr><td style="border: 1px solid #000; height: 50px;">Ù¥</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
                <tr><td style="border: 1px solid #000; height: 50px;">Ù¦</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
            </table>

            <table style="width: 100%; border-collapse: collapse; border: 1px solid #000;">
                <tr>
                    <th style="border: 1px solid #000; padding: 10px; background-color: #f9f9f9 !important; text-align: right; font-weight: bold;">Ø§Ù„Ù„ÙˆÙƒÙŠØ´Ù† : ${locationStr}</th>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; min-height: 100px; vertical-align: top; text-align: right;">
                        <strong>Ù…Ù„Ø§Ø­Ø¸Ø§Øª Ø¹Ø§Ù…Ø© :</strong>
                        <br><br>
                        ${escapeHTML(order.notes || '').replace(/\n/g, '<br>')}
                    </td>
                </tr>
            </table>
        </div>
    `;

    window.printWithLetterhead('', printContents);
};



// Department Modals
window.showDepartmentModal = async (dept = null) => {
    try {
        if (db.fetchAllProfiles) {
            const [profiles, departments] = await Promise.all([db.fetchAllProfiles(), db.fetchDepartments()]);
            window.departmentProfilesCache = profiles;
            window.departmentModalDepartmentsCache = departments;
        }
    } catch (e) {
        console.error("Error loading profiles for department head:", e);
    }

    if (dept) {
        document.getElementById('departmentId').value = dept.id;
        document.getElementById('departmentNameEn').value = dept.name || '';
        document.getElementById('departmentNameAr').value = dept.name_ar || '';
        document.getElementById('departmentHead').value = dept.head_id || '';
        document.getElementById('departmentModalTitle').innerText = 'Edit Department';
        document.getElementById('departmentSubmitBtn').innerText = 'Save Changes';
        const map = db.getJobTitlesMap() || {};
        window.currentDepartmentJobTitles = [...(map[dept.name] || [])];
    } else {
        document.getElementById('departmentId').value = '';
        document.getElementById('departmentNameEn').value = '';
        document.getElementById('departmentNameAr').value = '';
        document.getElementById('departmentHead').value = '';
        document.getElementById('departmentModalTitle').innerText = 'New Department';
        document.getElementById('departmentSubmitBtn').innerText = 'Create Department';
        window.currentDepartmentJobTitles = [];
    }

    window.filterDepartmentHeadOptions(dept?.head_id || '');

    if(document.getElementById('departmentJobTitleInput')) document.getElementById('departmentJobTitleInput').value = '';
    window.renderDepartmentJobTitlesList();

    document.getElementById('departmentModal').classList.add('show');
};

window.filterDepartmentHeadOptions = function (selectedHeadId = '') {
    const headSelect = document.getElementById('departmentHead');
    if (!headSelect) return;
    const departmentId = document.getElementById('departmentId')?.value || '';
    const departmentName = document.getElementById('departmentNameEn')?.value.trim().toLowerCase() || '';
    const department = (window.departmentModalDepartmentsCache || []).find(item =>
        item.id === departmentId || (!departmentId && item.name?.trim().toLowerCase() === departmentName)
    );
    const employees = department
        ? (window.departmentProfilesCache || []).filter(profile => profile.department_id === department.id)
        : [];
    headSelect.innerHTML = '<option value="">Select a department employee...</option>' + employees.map(profile =>
        `<option value="${profile.id}">${escapeHTML(window.formatEmployeeName(profile) || 'Employee')} â€” ${escapeHTML(profile.job_title || 'No job title')}</option>`
    ).join('');
    headSelect.disabled = !department || employees.length === 0;
    if (selectedHeadId && employees.some(profile => profile.id === selectedHeadId)) headSelect.value = selectedHeadId;
};
window.closeDepartmentModal = () => {
    document.getElementById('departmentModal').classList.remove('show');
};

window.showConfirmModal = (title, message, onConfirm) => {
    const modal = document.getElementById('confirmModal');
    if (!modal) return;

    document.getElementById('confirmModalTitle').innerText = localizeRuntimeText(title);
    document.getElementById('confirmModalMessage').innerText = localizeRuntimeText(message);

    const confirmBtn = document.getElementById('confirmModalBtn');
    const newConfirmBtn = confirmBtn.cloneNode(true);
    confirmBtn.parentNode.replaceChild(newConfirmBtn, confirmBtn);

    newConfirmBtn.onclick = async () => {
        newConfirmBtn.disabled = true;
        newConfirmBtn.innerHTML = localizeRuntimeText('Confirming...');
        await onConfirm();
        newConfirmBtn.disabled = false;
        newConfirmBtn.innerHTML = localizeRuntimeText('Confirm');
        closeConfirmModal();
    };

    modal.classList.add('show');
};

window.closeConfirmModal = () => {
    const modal = document.getElementById('confirmModal');
    if (modal) modal.classList.remove('show');
};

window.showAppMessageModal = (message, title = t('ui_notice') || 'Notice') => {
    let modal = document.getElementById('appMessageModal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'appMessageModal';
        modal.className = 'modal';
        modal.style.zIndex = '100001';
        modal.innerHTML = `<div class="modal-content" style="max-width:440px;text-align:center"><div class="modal-header"><h2 id="appMessageModalTitle"></h2><button type="button" class="close-modal" onclick="document.getElementById('appMessageModal').classList.remove('show')">&times;</button></div><p id="appMessageModalText" style="white-space:pre-line;color:var(--color-text-secondary);margin:1rem 0 1.5rem"></p><button type="button" class="btn btn-primary" onclick="document.getElementById('appMessageModal').classList.remove('show')">${t('btn_ok') || 'OK'}</button></div>`;
        document.body.appendChild(modal);
    }
    document.getElementById('appMessageModalTitle').textContent = localizeRuntimeText(title);
    document.getElementById('appMessageModalText').textContent = localizeRuntimeText(String(message || ''));
    modal.classList.add('show');
    if (window.lucide) window.lucide.createIcons();
};

window.showPromptModal = (message, title = t('ui_input_required') || 'Input required', options = {}) => new Promise(resolve => {
    let modal = document.getElementById('appPromptModal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'appPromptModal';
        modal.className = 'modal';
        // Prompt modals can be opened from within Edit Task (for example for
        // tags or estimated time). Keep them above the parent modal layer so
        // the prompt is always visible and interactive.
        modal.style.zIndex = '2147483000';
        modal.innerHTML = `<div class="modal-content" style="max-width:500px"><div class="modal-header"><h2 id="appPromptModalTitle"></h2><button type="button" class="close-modal" data-prompt-cancel>&times;</button></div><form id="appPromptModalForm"><label class="form-label" id="appPromptModalMessage"></label><textarea id="appPromptModalInput" class="form-control" rows="3"></textarea><div class="modal-actions"><button type="button" class="btn btn-secondary" data-prompt-cancel>${t('btn_cancel')}</button><button type="submit" class="btn btn-primary">${t('html_confirm') || 'Confirm'}</button></div></form></div>`;
        document.body.appendChild(modal);
    }
    const input = document.getElementById('appPromptModalInput');
    document.getElementById('appPromptModalTitle').textContent = localizeRuntimeText(title);
    document.getElementById('appPromptModalMessage').textContent = localizeRuntimeText(message);
    input.value = options.value || '';
    input.required = !!options.required;
    const finish = value => { modal.classList.remove('show'); resolve(value); };
    modal.querySelectorAll('[data-prompt-cancel]').forEach(button => button.onclick = () => finish(null));
    document.getElementById('appPromptModalForm').onsubmit = event => { event.preventDefault(); finish(input.value); };
    modal.classList.add('show');
    setTimeout(() => input.focus(), 0);
});

// Route legacy informational alerts through the shared in-app modal.
window.alert = message => window.showAppMessageModal(message);

window.editDepartment = async (id) => {
    const depts = await db.fetchDepartments();
    const dept = depts.find(d => d.id === id);
    if (!dept) return;
    window.showDepartmentModal(dept);
};

window.deleteDepartment = (id) => {
    window.showConfirmModal(
        "Delete Department",
        "Are you sure you want to delete this department?",
        async () => {
            const res = await db.deleteDepartment(id);
            if (res.success) {
                showToast(t('toast_department_deleted'), "success");
                const row = document.getElementById(`dept-row-${id}`);
                if (row) row.remove();
            } else {
                showToast(t('toast_failed_to_delete_department'), "danger");
            }
        }
    );
};

window.renderDepartmentJobTitlesList = () => {
    const list = document.getElementById('departmentJobTitlesList');
    if (!list) return;
    list.innerHTML = (window.currentDepartmentJobTitles || []).map((title, idx) => `
        <div style="display:flex; justify-content:space-between; align-items:center; padding:0.5rem; background:rgba(255,255,255,0.05); border-radius:4px; margin-bottom:0.25rem;">
            <span>${escapeHTML(title)}</span>
            <button type="button" class="btn btn-icon" style="color:var(--color-danger); width:24px; height:24px;" onclick="window.removeDepartmentJobTitleDraft(${idx})">
                <i data-lucide="x" style="width:14px; height:14px;"></i>
            </button>
        </div>
    `).join('');
    if (window.lucide) window.lucide.createIcons();
};

window.addDepartmentJobTitleDraft = () => {
    const input = document.getElementById('departmentJobTitleInput');
    const val = input.value.trim();
    if (!val) return;
    if (!window.currentDepartmentJobTitles) window.currentDepartmentJobTitles = [];
    if (window.currentDepartmentJobTitles.includes(val)) {
        showToast(window.t('msg_toast_46') || 'Job title already exists in this department', 'warning');
        return;
    }
    window.currentDepartmentJobTitles.push(val);
    input.value = '';
    window.renderDepartmentJobTitlesList();
};

window.handleDepartmentJobTitleKeydown = (e) => {
    if (e.key === 'Enter') {
        e.preventDefault();
        window.addDepartmentJobTitleDraft();
    }
};

window.removeDepartmentJobTitleDraft = (idx) => {
    if (!window.currentDepartmentJobTitles) return;
    window.currentDepartmentJobTitles.splice(idx, 1);
    window.renderDepartmentJobTitlesList();
};

window.handleCreateDepartment = async (e) => {
    e.preventDefault();
    const id = document.getElementById('departmentId').value;
    const deptEn = document.getElementById('departmentNameEn').value.trim();
    const deptAr = document.getElementById('departmentNameAr').value.trim();
    const jobTitles = window.currentDepartmentJobTitles || [];
    
    if (!deptEn) {
        showToast(window.t('msg_toast_47') || 'Department (EN) is required.', 'danger');
        return;
    }
    const data = {
        name: deptEn,
        name_ar: deptAr,
        head_id: document.getElementById('departmentHead').value || null,
        is_active: true
    };

    const submitBtn = document.getElementById('departmentSubmitBtn');
    submitBtn.disabled = true;

    let res;
    let newDeptId = id;
    try {
        if (id) {
            res = await db.updateDepartment(id, data, null);
            if (res.success) {
                const map = db.getJobTitlesMap() || {};
                const existingTitles = map[deptEn] || [];
                const toAdd = jobTitles.filter(t => !existingTitles.includes(t));
                // We do not delete removed titles here to prevent accidental data loss for existing employees.
                for (const title of toAdd) {
                    await db.createJobTitle({ name: title, name_ar: title, department_id: id, is_active: true });
                }
            }
        } else {
            res = await db.createDepartment(data, []);
            if (res.success && res.data) {
                newDeptId = res.data.id;
                for (const title of jobTitles) {
                    await db.createJobTitle({ name: title, name_ar: title, department_id: res.data.id, is_active: true });
                }
            }
        }

        if (res.success) {
            await db.fetchDepartments(true);
            await db.fetchJobTitles(true); // force refresh
            showToast(id ? "Department updated" : "Department created", "success");
            window.closeDepartmentModal();
            e.target.reset();
            if (typeof currentView !== 'undefined' && currentView === 'departments') {
                if (typeof renderView === 'function') renderView('departments');
            }
            if (typeof updateSelectOptions === 'function') await updateSelectOptions();
        } else {
            throw res.error || new Error('Unknown error');
        }
    } catch (err) {
        console.error(err);
        showToast(err.message || t('toast_error_saving_department'), "danger");
    } finally {
        submitBtn.disabled = false;
    }
};

// CRM Modals
window.showCRMClientModal = (client = null) => {
    if (client) {
        document.getElementById('crmClientId').value = client.id;
        document.getElementById('crmClientName').value = client.name || '';
        document.getElementById('crmClientCompany').value = client.company || '';
        document.getElementById('crmClientEmail').value = client.email || '';
        document.getElementById('crmClientPhone').value = client.phone || '';
        document.getElementById('crmClientModalTitle').innerText = t('ui_edit_client') || 'Edit Client';
        document.getElementById('crmClientSubmitBtn').innerHTML = `<i data-lucide="save" style="margin-right: 6px; width: 18px; height: 18px; vertical-align: middle;"></i> ${t('html_save_changes')}`;
    } else {
        document.getElementById('crmClientId').value = '';
        document.getElementById('crmClientName').value = '';
        document.getElementById('crmClientCompany').value = '';
        document.getElementById('crmClientEmail').value = '';
        document.getElementById('crmClientPhone').value = '';
        document.getElementById('crmClientModalTitle').innerText = t('ui_new_client') || 'New Client';
        document.getElementById('crmClientSubmitBtn').innerHTML = `<i data-lucide="save" style="margin-right: 6px; width: 18px; height: 18px; vertical-align: middle;"></i> ${t('btn_create_client')}`;
    }
    document.getElementById('crmClientModal').classList.add('show');
    if (window.lucide) window.lucide.createIcons();
};
window.closeCRMClientModal = () => {
    document.getElementById('crmClientModal').classList.remove('show');
};

window.editClient = async (id) => {
    const clients = await db.fetchClients();
    const client = clients.find(c => c.id === id);
    if (client) {
        showCRMClientModal(client);
    }
};

window.deleteClient = (id) => {
    window.showConfirmModal(
        "Delete Client",
        "Are you sure you want to delete this client?",
        async () => {
            const res = await db.deleteClient(id);
            if (res.success) {
                showToast(t('toast_client_deleted'), "success");
                const row = document.getElementById(`client-row-${id}`);
                if (row) row.remove();
            } else {
                showToast(t('toast_failed_to_delete_client_it_might_be_linked_to_existing_deals'), "danger");
            }
        }
    );
};

window.handleCreateClient = async (e) => {
    e.preventDefault();
    const id = document.getElementById('crmClientId').value;
    const data = {
        name: document.getElementById('crmClientName').value,
        company: document.getElementById('crmClientCompany').value,
        email: document.getElementById('crmClientEmail').value,
        phone: document.getElementById('crmClientPhone').value
    };

    let res;
    if (id) {
        res = await db.updateClient(id, data);
    } else {
        res = await db.createClient(data);
    }

    if (res.success) {
        showToast(id ? "Client updated" : "Client added", "success");
        closeCRMClientModal();
        e.target.reset();
        if (!id) {
            await db.triggerWebhooks('new_client', data);
        }
        if (currentView === 'crm' || currentView === 'clients') renderView(currentView);
    }
};

window.showCRMDealModal = async (id = null, isViewOnly = false) => {
    const clients = await db.fetchClients();
    const select = document.getElementById('crmDealClient');
    select.innerHTML = `<option value="">${t('crm_select_client')}</option>` +
        clients.map(c => `<option value="${c.id}">${c.name} (${c.company})</option>`).join('');

    const users = await db.fetchUsers();
    const assigneeSelect = document.getElementById('crmDealAssignee');
    if (assigneeSelect) {
        assigneeSelect.innerHTML = `<option value="">${t('crm_unassigned')}</option>` +
            users.map(u => `<option value="${u.id}">${window.formatEmployeeName(u)} (${u.role})</option>`).join('');
    }

    document.getElementById('crmDealId').value = id || '';

    const titleEl = document.getElementById('crmDealModalTitle');
    const submitBtn = document.getElementById('crmDealSubmitBtn');
    if (isViewOnly) {
        titleEl.textContent = t('crm_view_deal');
        submitBtn.style.display = 'none';
    } else if (id) {
        titleEl.textContent = t('crm_edit_deal');
        submitBtn.style.display = 'block';
        submitBtn.innerHTML = `<i data-lucide="save" style="margin-right: 6px; width: 18px; height: 18px; vertical-align: middle;"></i> ${t('html_save_changes')}`;
    } else {
        titleEl.textContent = t('ui_new_deal') || 'New Deal';
        submitBtn.style.display = 'block';
        submitBtn.innerHTML = `<i data-lucide="save" style="margin-right: 6px; width: 18px; height: 18px; vertical-align: middle;"></i> ${t('crm_create_deal')}`;
    }

    // Toggle disabled state for all inputs
    const inputs = ['crmDealTitle', 'crmDealClient', 'crmDealAmount', 'crmDealClosingDate', 'crmDealAssignee', 'crmDealLostReason', 'crmDealEventType', 'crmDealFirstContactDate', 'crmDealContactMethod', 'crmDealLeadSource', 'crmDealTechnicalDescription'];
    inputs.forEach(inputId => {
        const el = document.getElementById(inputId);
        if (el) el.disabled = isViewOnly;
    });

    if (id) {
        const deals = await db.fetchDeals();
        const deal = deals.find(d => d.id === id);
        if (deal) {
            document.getElementById('crmDealTitle').value = deal.title || '';
            document.getElementById('crmDealClient').value = deal.client_id || '';
            document.getElementById('crmDealAmount').value = deal.amount || 0;
            document.getElementById('crmDealClosingDate').value = deal.closing_date || '';

            if (document.getElementById('crmDealEventType')) document.getElementById('crmDealEventType').value = deal.event_type || '';
            if (document.getElementById('crmDealFirstContactDate')) document.getElementById('crmDealFirstContactDate').value = deal.first_contact_date || '';
            if (document.getElementById('crmDealContactMethod')) document.getElementById('crmDealContactMethod').value = deal.contact_method || '';
            if (document.getElementById('crmDealLeadSource')) document.getElementById('crmDealLeadSource').value = deal.lead_source || '';
            document.getElementById('crmDealTechnicalDescription').value = deal.technical_description || '';

            if (assigneeSelect) assigneeSelect.value = deal.assigned_to || '';

            if (deal.stage === 'LOST') {
                document.getElementById('crmDealLostReasonGroup').style.display = 'block';
                document.getElementById('crmDealLostReason').value = deal.lost_reason || '';
            } else {
                document.getElementById('crmDealLostReasonGroup').style.display = 'none';
            }
        }
    } else {
        document.getElementById('crmDealTitle').value = '';
        document.getElementById('crmDealClient').value = '';
        document.getElementById('crmDealAmount').value = '';
        document.getElementById('crmDealClosingDate').value = '';
        if (document.getElementById('crmDealEventType')) document.getElementById('crmDealEventType').value = '';
        if (document.getElementById('crmDealFirstContactDate')) document.getElementById('crmDealFirstContactDate').value = '';
        if (document.getElementById('crmDealContactMethod')) document.getElementById('crmDealContactMethod').value = '';
        if (document.getElementById('crmDealLeadSource')) document.getElementById('crmDealLeadSource').value = '';
        document.getElementById('crmDealTechnicalDescription').value = '';
        if (assigneeSelect) assigneeSelect.value = '';
        document.getElementById('crmDealLostReasonGroup').style.display = 'none';
    }

    document.getElementById('crmDealModal').classList.add('show');
    if (window.lucide) window.lucide.createIcons();
};
window.closeCRMDealModal = () => {
    document.getElementById('crmDealModal').classList.remove('show');
};
window.handleCreateDeal = async (e) => {
    e.preventDefault();
    const id = document.getElementById('crmDealId').value;
    const assigneeEl = document.getElementById('crmDealAssignee');
    const assigneeVal = assigneeEl ? assigneeEl.value : null;
    const closingDateEl = document.getElementById('crmDealClosingDate');

    const eventTypeEl = document.getElementById('crmDealEventType');
    const firstContactDateEl = document.getElementById('crmDealFirstContactDate');
    const contactMethodEl = document.getElementById('crmDealContactMethod');
    const leadSourceEl = document.getElementById('crmDealLeadSource');

    const data = {
        title: document.getElementById('crmDealTitle').value,
        amount: parseFloat(document.getElementById('crmDealAmount').value) || 0,
        client_id: document.getElementById('crmDealClient').value,
        closing_date: (closingDateEl && closingDateEl.value) ? closingDateEl.value : null,
        event_type: (eventTypeEl && eventTypeEl.value) ? eventTypeEl.value : null,
        first_contact_date: (firstContactDateEl && firstContactDateEl.value) ? firstContactDateEl.value : null,
        contact_method: (contactMethodEl && contactMethodEl.value) ? contactMethodEl.value : null,
        lead_source: (leadSourceEl && leadSourceEl.value) ? leadSourceEl.value : null,
        technical_description: document.getElementById('crmDealTechnicalDescription').value || null,
        assigned_to: assigneeVal ? assigneeVal : currentUser.id
    };
    if (!id) data.stage = 'LEAD'; // Only set stage on creation

    const lostReasonGroup = document.getElementById('crmDealLostReasonGroup');
    if (lostReasonGroup && lostReasonGroup.style.display !== 'none') {
        data.lost_reason = document.getElementById('crmDealLostReason').value;
    }

    if (!data.client_id) return showToast(t('toast_please_select_a_client'), "danger");

    let res;
    if (id) {
        res = await db.updateDeal(id, data);
    } else {
        res = await db.createDeal(data);
    }

    if (res.success) {
        showToast(id ? "Deal updated" : "Deal created", "success");
        closeCRMDealModal();
        e.target.reset();
        if (currentView === 'crm') renderView('crm');
    }
};

// ==========================================
// Integrations / Webhooks Features
// ==========================================
async function renderIntegrations() {
    if (currentUserRole !== 'ADMIN') {
        return `<div class="page-header"><h1 class="page-title">${t('ui_unauthorized')}</h1></div>`;
    }

    const webhooks = await db.fetchWebhooks();

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('ui_api_integrations_webhooks')}</h1>
                <p class="page-subtitle">Send real-time data to external services (Slack, Make, Zapier, Custom API)</p>
            </div>
            <button class="btn btn-primary" onclick="showWebhookModal()">
                <i data-lucide="plus"></i> New Webhook
            </button>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card" style="grid-column: span 12 / span 12;">
                <div class="card-title">Configured Webhooks</div>
                <div class="table-responsive">
                    <table class="table">
                        <thead>
                            <tr>
                                <th>${t('ui_name') || 'Name'}</th>
                                <th>${t('ui_event_type')}</th>
                                <th>${t('ui_url')}</th>
                                <th>${t('ui_status')}</th>
                                <th>${t('ui_actions')}</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${webhooks.map(w => `
                                <tr id="webhook-row-${w.id}">
                                    <td style="font-weight:500;">${w.name}</td>
                                    <td><span class="status-badge info">${w.event_type}</span></td>
                                    <td style="max-width: 250px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${w.url}</td>
                                    <td><span class="status-badge ${w.is_active ? 'success' : 'danger'}">${w.is_active ? 'Active' : 'Inactive'}</span></td>
                                    <td>
                                        <button class="btn btn-danger btn-sm" onclick="handleDeleteWebhook('${w.id}')">
                                            <i data-lucide="trash-2"></i>
                                        </button>
                                    </td>
                                </tr>
                            `).join('')}
                            ${webhooks.length === 0 ? '<tr><td colspan="5" class="text-center">No webhooks configured</td></tr>' : ''}
                        </tbody>
                    </table>
                </div>
            </div>
            <div class="card" style="grid-column: span 12 / span 12; background: var(--color-surface-hover);">
                <div class="card-title">How to use Integrations</div>
                <p style="color: var(--color-text-secondary); margin-bottom: 1rem; line-height: 1.5;">
                    Webhooks allow MUQAM HR to push data to other applications in real-time. Whenever an event occurs (like a new client added or a deal won), 
                    we will send an HTTP POST request to your provided URL containing a JSON payload with the event details.
                </p>
                <p style="color: var(--color-text-secondary); margin-bottom: 1rem; line-height: 1.5;">
                    <strong>Available Events:</strong><br/>
                    â€¢ <code>deal_won</code>: Fires when a CRM deal is dragged to the WON stage.<br/>
                    â€¢ <code>new_client</code>: Fires when a new CRM client is added.<br/>
                    â€¢ <code>all</code>: Fires on all supported events.
                </p>
            </div>
        </div>
    `;
}

window.showWebhookModal = () => {
    document.getElementById('webhookModal').classList.add('show');
};
window.closeWebhookModal = () => {
    document.getElementById('webhookModal').classList.remove('show');
};
window.handleCreateWebhook = async (e) => {
    e.preventDefault();
    const data = {
        name: document.getElementById('webhookName').value,
        url: document.getElementById('webhookUrl').value,
        event_type: document.getElementById('webhookEvent').value,
        is_active: true
    };
    const res = await db.createWebhook(data);
    if (res.success) {
        showToast(t('toast_webhook_created'), "success");
        closeWebhookModal();
        e.target.reset();
        if (currentView === 'integrations') renderView('integrations');
    }
};
window.handleDeleteWebhook = (id) => {
    window.showConfirmModal(
        "Delete Webhook",
        "Delete this webhook?",
        async () => {
            const res = await db.deleteWebhook(id);
            if (res.success) {
                showToast(t('toast_webhook_deleted'), "success");
                const row = document.getElementById(`webhook-row-${id}`);
                if (row) row.remove();
            }
        }
    );
};

// Init
async function initApp() {
    await window.initCustomTranslations();
    updateTranslations();

    // Subscribe to realtime updates for translations
    if (typeof db !== 'undefined' && db.subscribeToTranslations) {
        db.subscribeToTranslations(payload => {
            if (payload.eventType === 'INSERT' || payload.eventType === 'UPDATE') {
                const { trans_key, trans_en, trans_ar } = payload.new;
                if (trans_en && typeof i18n !== 'undefined' && i18n.en) i18n.en[trans_key] = trans_en;
                if (trans_ar && typeof i18n !== 'undefined' && i18n.ar) i18n.ar[trans_key] = trans_ar;
            } else if (payload.eventType === 'DELETE') {
                const { trans_key } = payload.old;
                if (typeof i18n !== 'undefined') {
                    delete i18n.en[trans_key];
                    delete i18n.ar[trans_key];
                }
            }
            updateTranslations();
            if (currentView === 'translations') {
                renderView('translations');
            }
        });
    }

    // Check for existing session
    const { data: { session } } = await db.getSession();

    // Listen for session expiration or logout
    db.onAuthStateChange((event, session) => {
        if (event === 'SIGNED_OUT' || !session) {
            currentUser = null;
            currentUserRole = null;
            currentUserProfile = null;
            document.querySelector('.sidebar').style.display = 'none';
            document.querySelector('.topbar').style.display = 'none';
            if (currentView !== 'login') {
                currentView = 'login';
                renderView('login');
            }
        }
    });

    if (session && session.user) {
        currentUser = session.user;
        const profile = await db.getUserProfile(currentUser.id);
        await syncLegacyLocalProfilePhoto(profile);
        currentUserProfile = profile;
        currentUserRole = profile.role;
        applyPreferredTheme(profile);

        // TEMPORARY OVERRIDE: Force Admin role for privatepple@gmail.com in frontend
        if (currentUser.email && currentUser.email.toLowerCase() === 'privatepple@gmail.com') {
            currentUserRole = 'ADMIN';
            profile.role = 'ADMIN';
        }

        updateTopbarProfile(profile);

        // Show navigation
        document.querySelector('.sidebar').style.display = '';
        document.querySelector('.topbar').style.display = 'flex';

        // Hide/Show Role-Specific Nav Items
        const adminNav = document.querySelector('.nav-item[data-view="admin"]');
        const usersNav = document.querySelector('.nav-item[data-view="users"]');
        const analyticsNav = document.querySelector('.nav-item[data-view="analytics"]');
        const employeesNav = document.querySelector('.nav-item[data-view="employees"]');
        const approvalsNav = document.getElementById('navApprovals');

        if (adminNav) adminNav.style.display = (currentUserRole === 'ADMIN' || ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR')) ? 'flex' : 'none';
        if (usersNav) usersNav.style.display = currentUserRole === 'ADMIN' ? 'flex' : 'none';
        if (analyticsNav) analyticsNav.style.display = (currentUserRole === 'ADMIN' || ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR')) ? 'flex' : 'none';
        if (employeesNav) employeesNav.style.display = 'flex';

        const canUseApprovals = currentUserRole === 'ADMIN' || currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR' || /manager|supervisor/i.test(profile?.job_title || '');
        if (approvalsNav) approvalsNav.style.display = canUseApprovals ? 'flex' : 'none';
        await window.updateSidebarVisibility();

        const restorableViews = new Set([
            'dashboard', 'time', 'leave', 'requests', 'archived',
            'payroll', 'expenses', 'analytics', 'admin', 'users', 'employees',
            'archived_contracts', 'messages', 'notifications', 'performance',
            'documents', 'profile', 'projects', 'approvals', 'tasks',
            'departments', 'translations', 'clients', 'crm', 'schedule', 'integrations', 'custody_handover'
        ]);
        const requestedView = new URLSearchParams(window.location.search).get('view');
        const savedView = requestedView || localStorage.getItem(`muqam_hr_last_view_${currentUser.id}`) || localStorage.getItem('muqam_hr_last_view');
        currentView = restorableViews.has(savedView) ? savedView : 'dashboard';

        // Do not restore a sidebar page that is hidden for this user's role.
        const restoredNav = document.querySelector(`.nav-item[data-view="${currentView}"]`);
        if (restoredNav && restoredNav.style.display === 'none') currentView = 'dashboard';

        pollNotifications();
        if (notificationsInterval) clearInterval(notificationsInterval);
        notificationsInterval = setInterval(pollNotifications, 60000);
    } else {
        currentView = 'login';
    }

    renderView(currentView);
}

const REQUEST_STAGE_LABELS = {
    SUPERVISOR_MANAGER: 'Supervisor / Manager',
    DEPARTMENT_MANAGER: 'Department Manager',
    HR_MANAGER: 'HR Manager',
    ACCOUNTANT_MANAGER: 'Accounting Manager',
    GENERAL_MANAGER: 'General Manager',
    ADMIN_FALLBACK: 'System Administrator'
};

function getRequestWorkflowStage(workflow) {
    if (!workflow) return 'Awaiting workflow setup';
    if (workflow.status === 'APPROVED') return 'Final approval completed';
    if (workflow.status === 'REJECTED') return 'Rejected';
    const step = workflow.steps?.find(item => item.step_order === workflow.current_step);
    return `Awaiting ${REQUEST_STAGE_LABELS[step?.stage_key] || 'approval'}`;
}

function renderRequestWorkflowProgress(workflow, approverNames = {}) {
    if (!workflow?.steps?.length) return '';
    const total = workflow.steps.length;
    const completed = workflow.status === 'APPROVED'
        ? total
        : workflow.steps.filter(step => step.status === 'APPROVED').length;
    const progress = workflow.status === 'REJECTED'
        ? Math.round((completed / total) * 100)
        : workflow.status === 'APPROVED'
            ? 100
            : Math.max(8, Math.round(((completed + .35) / total) * 100));
    const stepsMarkup = workflow.steps.map(step => {
        const active = workflow.status === 'PENDING' && step.step_order === workflow.current_step;
        const className = step.status === 'APPROVED' ? 'completed' : (step.status === 'REJECTED' ? 'rejected' : (active ? 'active' : 'upcoming'));
        const approverName = approverNames[step.approver_id] || 'Management';
        return `<span class="request-workflow-step ${className}">
            <span class="request-workflow-stage">${escapeHTML(REQUEST_STAGE_LABELS[step.stage_key] || step.stage_key)}</span>
            <small>${escapeHTML(approverName)}</small>
        </span>`;
    }).join('<i data-lucide="chevron-right"></i>');
    return `<div class="request-workflow-progress ${workflow.status === 'REJECTED' ? 'is-rejected' : ''}">
        <div class="request-workflow-progress-summary"><span>Request pipeline</span><strong>${progress}%</strong></div>
        <div class="request-workflow-progress-track"><span style="width:${progress}%"></span></div>
        <div class="request-workflow-progress-steps">${stepsMarkup}</div>
    </div>`;
}

function renderRequestPipeline(request, approverNames = {}) {
    if (request.workflow?.steps?.length) return renderRequestWorkflowProgress(request.workflow, approverNames);
    const status = String(request.status || 'PENDING').toUpperCase();
    const progress = status === 'APPROVED' ? 100 : status === 'REJECTED' ? 100 : 35;
    const label = status === 'APPROVED' ? 'Completed' : status === 'REJECTED' ? 'Rejected' : 'Submitted';
    return `<div class="request-workflow-progress request-workflow-progress--fallback ${status === 'REJECTED' ? 'is-rejected' : ''}">
        <div class="request-workflow-progress-summary"><span>Request pipeline</span><strong>${progress}%</strong></div>
        <div class="request-workflow-progress-track"><span style="width:${progress}%"></span></div>
        <div class="request-workflow-fallback-label">${escapeHTML(label)}</div>
    </div>`;
}

window.handleRequestAction = async function (sourceTable, id, decision) {
    let note = null;
    if (decision === 'REJECTED') {
        note = await window.showPromptModal(t('approval_rejection_reason_prompt'), t('ui_rejected'), { required: true });
        if (note === null) return;
        if (!note.trim()) return showToast(window.t('msg_toast_48') || 'A rejection reason is required.', 'warning');
    }
    const result = await db.decideRequestApproval(sourceTable, id, decision, note);
    if (result.success) {
        showToast(decision === 'APPROVED' ? 'Approval recorded and request moved to its next stage.' : 'Request rejected and employee notified.', 'success');
        renderView('requests');
    } else {
        showToast(result.error?.message || 'Failed to update request approval.', 'danger');
    }
};

async function renderMyRequestStatuses() {
    const requests = await db.fetchMyRequestStatuses();
    const rows = requests.map(request => {
        const normalizedStatus = String(request.request_status || 'PENDING').toUpperCase().replace('_ARCHIVED', '');
        const badgeClass = normalizedStatus === 'APPROVED' ? 'success' : (normalizedStatus === 'REJECTED' ? 'danger' : 'warning');
        const stageLabel = normalizedStatus === 'APPROVED' ? 'Completed' : normalizedStatus === 'REJECTED' ? 'Rejected' : (REQUEST_STAGE_LABELS[request.current_stage] || 'Awaiting approval');
        const requestDate = new Date(request.created_at).toISOString().slice(0, 10);
        return `<tr class="my-request-status-row" data-request-date="${requestDate}">
            <td>${new Date(request.created_at).toLocaleDateString()}</td>
            <td><strong>${escapeHTML(request.request_type || 'Employee Request')}</strong><br><small>${escapeHTML(request.request_details || '')}</small></td>
            <td><span class="status-badge ${badgeClass}">${escapeHTML(normalizedStatus)}</span></td>
            <td><div class="my-request-current-stage"><strong>${escapeHTML(stageLabel)}</strong>${normalizedStatus === 'PENDING' ? `<small>${escapeHTML(request.current_approver_name || 'Management')}</small>` : ''}</div></td>
            <td>${request.rejection_reason ? escapeHTML(request.rejection_reason) : 'â€”'}</td>
        </tr>`;
    }).join('');

    return `<div class="page-header fade-in-up">
        <div><h1 class="page-title">${t('ui_my_requests')}</h1><p class="page-subtitle">${t('ui_track_request_status')}</p></div>
        <button type="button" class="btn-primary" onclick="showNewRequestModal()"><i data-lucide="plus"></i> ${t('leave_new_req')}</button>
    </div>
    <div class="card fade-in-up" style="margin-bottom:1rem"><div class="form-group" style="max-width:320px;margin:0">
        <label class="form-label" for="myRequestStatusDate">${t('ui_search_by_date')}</label>
        <input type="date" id="myRequestStatusDate" class="form-control" onchange="filterMyRequestStatuses()">
    </div></div>
    <div class="card fade-in-up"><div class="table-responsive"><table class="data-table">
        <thead><tr><th>${t('date')}</th><th>${t('ui_request')}</th><th>${t('status')}</th><th>${t('ui_approval_stage')}</th><th>${t('ui_rejection_reason')}</th></tr></thead>
        <tbody>${rows || `<tr><td colspan="5" style="text-align:center;padding:2rem;color:var(--color-text-secondary)">${t('ui_no_submitted_requests')}</td></tr>`}</tbody>
    </table></div></div>`;
}

window.filterMyRequestStatuses = function () {
    const selectedDate = document.getElementById('myRequestStatusDate')?.value || '';
    document.querySelectorAll('.my-request-status-row').forEach(row => {
        row.hidden = Boolean(selectedDate && row.dataset.requestDate !== selectedDate);
    });
};

// Unified Requests Page
async function renderRequests() {
    const normalizedRole = String(currentUserRole || '').toUpperCase();
    const isAdmin = ['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(normalizedRole);
    const isDepartmentManager = ['MANAGER', 'SUPERVISOR'].includes(normalizedRole);
    const isManagerOrAdmin = isAdmin || isDepartmentManager;

    const [allProfiles, requestDirectory] = await Promise.all([
        db.fetchAllProfiles(),
        db.fetchRequestDirectory()
    ]);
    const currentProfile = allProfiles.find(profile => profile.id === currentUser?.id) || currentUser || {};
    let visibleEmployeeIds = null;
    if (!isAdmin) {
        visibleEmployeeIds = isDepartmentManager
            ? requestDirectory.map(person => person.employee_id)
            : [currentUser?.id].filter(Boolean);
    }

    // Fetch data
    const [leaves, docs, expenses, genericRequests, workflows] = await Promise.all([
        db.fetchLeaveRequests(visibleEmployeeIds),
        db.fetchDocuments(visibleEmployeeIds),
        db.fetchExpenses(visibleEmployeeIds),
        db.fetchGenericRequests(visibleEmployeeIds),
        db.fetchRequestApprovalWorkflows()
    ]);
    const workflowMap = new Map(workflows.map(workflow => [`${workflow.source_table}:${workflow.source_id}`, workflow]));
    const canApproveAny = isAdmin || workflows.some(workflow => workflow.status === 'PENDING' && workflow.steps?.some(step => step.step_order === workflow.current_step && step.approver_id === currentUser?.id));
    const showApprovalColumns = isManagerOrAdmin || canApproveAny;

    const profilesMap = {};
    allProfiles.forEach(profile => {
        profilesMap[profile.id] = window.formatEmployeeName(profile) || 'Unknown User';
    });
    requestDirectory.forEach(person => {
        profilesMap[person.employee_id] = window.formatEmployeeName(person) || profilesMap[person.employee_id] || 'Unknown User';
    });
    const emailMap = Object.fromEntries((requestDirectory || []).map(person => [person.employee_id, person.email || '']));

    // Normalize requests
    let allRequests = [];
    leaves.forEach(r => {
        allRequests.push({
            id: r.id,
            type: 'Leave',
            leaveType: r.leave_type || '',
            employee_id: r.employee_id,
            details: r.leave_type === 'Short Leave'
                ? `Short Leave: ${r.short_leave_reason || r.reason || 'No reason'} â€” ${r.short_leave_duration_minutes || 0} minutes`
                : `${r.leave_type}: ${new Date(r.start_date).toLocaleDateString()} to ${new Date(r.end_date).toLocaleDateString()}`,
            status: r.status,
            created_at: r.created_at,
            source_table: 'leave_requests',
            raw: r
        });
    });

    expenses.forEach(r => {
        allRequests.push({
            id: r.id,
            type: 'Expense',
            employee_id: r.employee_id,
            details: `SAR ${r.amount} - ${r.description}`,
            status: r.status,
            created_at: r.created_at,
            source_table: 'expenses',
            raw: r
        });
    });

    docs.forEach(r => allRequests.push({
        id: r.id,
        type: 'Document',
        employee_id: r.employee_id,
        details: `${r.doc_type} - ${r.purpose || 'No purpose provided'}`,
        status: r.status,
        created_at: r.created_at,
        source_table: 'document_requests',
        raw: r
    }));

    genericRequests.forEach(r => allRequests.push({
        id: r.id,
        type: /^leave\s*request$/i.test(r.request_type || '') ? 'Leave' : (r.request_type || 'Employee Request'),
        leaveType: /^leave\s*request$/i.test(r.request_type || '') ? (r.leave_type || '') : '',
        employee_id: r.employee_id,
        details: /^loan/i.test(r.request_type || '')
            ? `Loan amount: ${Number(r.loan_amount || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} SAR`
            : /^leave\s*request$/i.test(r.request_type || '')
                ? `${r.number_of_days || 0} day${Number(r.number_of_days) === 1 ? '' : 's'}`
                : (r.leave_type || r.request_type || 'Employee Request'),
        status: String(r.status || 'PENDING').toUpperCase(),
        created_at: r.created_at,
        source_table: 'requests',
        raw: r
    }));

    allRequests.forEach(request => {
        request.workflow = workflowMap.get(`${request.source_table}:${request.id}`);
        request.status = request.workflow?.status || request.status;
    });
    allRequests = allRequests.filter(request => !request.raw?.is_archived);

    // Sort by created_at desc
    allRequests.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

    // Render UI
    let rowsHTML = allRequests.map(r => {
        let badgeClass = 'info';
        if (r.status === 'APPROVED') badgeClass = 'success';
        if (r.status === 'REJECTED') badgeClass = 'danger';

        const employeeName = showApprovalColumns ? (profilesMap[r.employee_id] || 'Unknown') : 'Me';
        const isLeaveRequest = r.type === 'Leave' || r.source_table === 'leave_requests';
        const requestTypeLabel = isLeaveRequest ? (t('req_type_leave') || 'Leave Request') : r.type;
        const currentStep = r.workflow?.steps?.find(step => step.step_order === r.workflow.current_step);
        const canApprove = r.workflow?.status === 'PENDING' && (isAdmin || currentStep?.approver_id === currentUser?.id);

        let actionsCell = '';
        if (showApprovalColumns) {
            if (canApprove) {
                actionsCell = `
                    <td>
                        <button class="btn-primary" onclick="handleRequestAction('${r.source_table}', '${r.id}', 'APPROVED')">${t('leave_approve')}</button>
                        <button class="btn-primary request-reject-button" onclick="handleRequestAction('${r.source_table}', '${r.id}', 'REJECTED')">${t('leave_reject')}</button>
                    </td>
                `;
            } else {
                actionsCell = `<td><span class="request-awaiting-label">${r.status === 'PENDING' ? escapeHTML(getRequestWorkflowStage(r.workflow)) : 'â€”'}</span></td>`;
            }
        }

        return `
            <tr class="request-row" data-type="${r.type}" data-status="${r.status}" data-emp="${escapeHTML(employeeName.toLowerCase())}" data-email="${escapeHTML(String(emailMap[r.employee_id] || '').toLowerCase())}" data-request-date="${new Date(r.created_at).toISOString().slice(0, 10)}" data-details="${escapeHTML(r.details.toLowerCase())}">
                <td data-label="${escapeHTML(t('date') || 'Date')}">${new Date(r.created_at).toLocaleDateString()}</td>
                ${showApprovalColumns ? `<td data-label="${escapeHTML(t('leave_employee') || 'Employee')}">${escapeHTML(employeeName)}</td>` : ''}
                <td data-label="${escapeHTML(t('req_type') || 'Request Type')}"><strong>${escapeHTML(requestTypeLabel)}</strong></td>
                <td data-label="${escapeHTML(t('ui_leave_type') || 'Leave Type')}">${isLeaveRequest ? escapeHTML(r.leaveType || '—') : '—'}</td>
                <td class="request-details-cell" data-label="${escapeHTML(t('req_details') || 'Details')}">${escapeHTML(r.details)}${renderRequestPipeline(r, profilesMap)}</td>
                <td data-label="${escapeHTML(t('req_status') || 'Status')}"><span class="status-badge ${badgeClass}">${escapeHTML(getRequestWorkflowStage(r.workflow))}</span></td>
                ${actionsCell}
            </tr>
        `;
    }).join('');

    if (allRequests.length === 0) {
        const colSpan = showApprovalColumns ? 7 : 5;
        rowsHTML = `<tr><td colspan="${colSpan}" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">${t('req_no_found')}</td></tr>`;
    }

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('req_all')}</h1>
                <p class="page-subtitle">${t('req_sub')}</p>
            </div>
        </div>
        
        <div class="dashboard-grid fade-in-up" style="margin-bottom: 2rem;">
            <!-- HR Letter Requests -->
            <div class="card col-span-12">
                <div class="card-title">${t('doc_req_letter')}</div>
                <form autocomplete="off" onsubmit="handleDocSubmit(event)">
                    <div class="form-group">
                        <label class="form-label">${t('doc_type')}</label>
                        <select id="docType" class="form-control">
                            <option value="Salary Certificate">${t('doc_type_salary')}</option>
                            <option value="NOC">${t('doc_type_noc')}</option>
                            <option value="Employment Letter">${t('doc_type_emp')}</option>
                            <option value="Pay Slip">Pay Slip</option>
                            <option value="Loan">Loan</option>
                            <option value="Item Purchase">Item Purchase</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('doc_purpose')}</label>
                        <textarea id="docPurpose" class="form-control" required></textarea>
                    </div>
                    <button type="submit" class="btn-secondary" style="width: 100%;">${t('doc_submit_req')}</button>
                </form>
            </div>
        </div>

        <h2 style="margin-bottom: 1rem; font-size: 1.25rem; display: flex; align-items: center; gap: .6rem;">
            ${isAdmin ? 'All Employee Requests' : (isDepartmentManager ? 'Department Requests' : 'My Requests')}
            <span class="status-badge info" aria-label="${allRequests.length} requests">${allRequests.length}</span>
        </h2>
        <div class="card fade-in-up" style="margin-bottom: 2rem;">
            <div style="display: flex; gap: 1rem; align-items: center; flex-wrap: wrap;">
                ${isManagerOrAdmin ? `<div style="flex: 1; min-width: 220px;">
                    <label class="form-label">${t('req_search')}</label>
                    <input type="search" id="reqSearch" class="form-control" placeholder="Search by full name or email" oninput="filterRequests()">
                </div>` : `<div style="flex: 1; min-width: 220px;">
                    <label class="form-label" for="reqDate">Request Date</label>
                    <input type="date" id="reqDate" class="form-control" onchange="filterRequests()">
                </div>`}
                <div style="width: 150px;">
                    <label class="form-label">${t('req_type')}</label>
                    <select id="reqType" class="form-control" onchange="filterRequests()">
                        <option value="ALL">${t('req_type_all')}</option>
                        <option value="Leave">${t('req_type_leave')}</option>
                        <option value="Expense">${t('req_type_exp')}</option>
                        <option value="Document">Document / Financial</option>
                        <option value="Loan Request">Loan Request</option>
                    </select>
                </div>
                <div style="width: 150px;">
                    <label class="form-label">${t('req_status')}</label>
                    <select id="reqStatus" class="form-control" onchange="filterRequests()">
                        <option value="ALL">${t('req_status_all')}</option>
                        <option value="PENDING">${t('req_pending')}</option>
                        <option value="APPROVED">${t('req_approved')}</option>
                        <option value="REJECTED">${t('req_rejected')}</option>
                    </select>
                </div>
            </div>
        </div>
        
        <div class="card fade-in-up request-directory-card">
            <div class="table-responsive">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>${t('date')}</th>
                            ${showApprovalColumns ? `<th>${t('leave_employee')}</th>` : ''}
                            <th>${t('req_type')}</th>
                            <th>${t('ui_leave_type') || 'Leave Type'}</th>
                            <th>${t('req_details')}</th>
                            <th>${t('req_status')}</th>
                            ${showApprovalColumns ? `<th>${t('leave_actions')}</th>` : ''}
                        </tr>
                    </thead>
                    <tbody id="requestsTableBody">
                        ${rowsHTML}
                    </tbody>
                </table>
            </div>
        </div>
    `;
}

window.filterRequests = function () {
    const searchVal = (document.getElementById('reqSearch')?.value || '').toLowerCase();
    const dateVal = document.getElementById('reqDate')?.value || '';
    const typeVal = document.getElementById('reqType').value;
    const statusVal = document.getElementById('reqStatus').value;

    const rows = document.querySelectorAll('.request-row');
    rows.forEach(row => {
        const t = row.getAttribute('data-type');
        const s = row.getAttribute('data-status');
        const emp = row.getAttribute('data-emp');
        const email = row.getAttribute('data-email') || '';
        const requestDate = row.getAttribute('data-request-date') || '';
        const det = row.getAttribute('data-details');

        const matchSearch = !searchVal || emp.includes(searchVal) || email.includes(searchVal);
        const matchDate = !dateVal || requestDate === dateVal;
        const matchType = typeVal === 'ALL' || t === typeVal;
        const matchStatus = statusVal === 'ALL' || s === statusVal;

        if (matchSearch && matchDate && matchType && matchStatus) {
            row.style.display = '';
        } else {
            row.style.display = 'none';
        }
    });
};

// Render Archived Requests
async function renderArchivedRequests() {
    const isManagerOrAdmin = currentUserRole === 'ADMIN' || ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR');
    if (!isManagerOrAdmin) {
        return `<div style="padding: 2rem;">${t('req_unauthorized')}</div>`;
    }

    // Fetch data
    const [leaves, docs, expenses, genericRequests, workflows] = await Promise.all([
        db.fetchLeaveRequests(), db.fetchDocuments(), db.fetchExpenses(),
        db.fetchGenericRequests(), db.fetchRequestApprovalWorkflows()
    ]);
    const workflowMap = new Map(workflows.map(workflow => [`${workflow.source_table}:${workflow.source_id}`, workflow]));

    let profilesMap = {};
    const allProfiles = await db.fetchAllProfiles();
    allProfiles.forEach(p => {
        profilesMap[p.id] = window.formatEmployeeName(p) || 'Unknown User';
    });

    // Normalize requests
    let allRequests = [];
    const addToRequests = (items, type, sourceTable, getDetails) => {
        items.forEach(r => {
            if (r.is_archived || String(r.status || '').endsWith('_ARCHIVED')) {
                const workflow = workflowMap.get(`${sourceTable}:${r.id}`);
                allRequests.push({
                    id: r.id,
                    type: type,
                    employee_id: r.employee_id,
                    details: getDetails(r),
                    status: String(r.status || 'REJECTED').replace('_ARCHIVED', ''),
                    created_at: r.created_at,
                    rejection_reason: r.rejection_reason || workflow?.rejection_reason || ''
                });
            }
        });
    };

    addToRequests(leaves, 'Leave', 'leave_requests', r => `${r.leave_type}: ${new Date(r.start_date).toLocaleDateString()} to ${new Date(r.end_date).toLocaleDateString()}`);
    addToRequests(docs, 'Document', 'document_requests', r => `${r.doc_type} - ${r.purpose}`);
    addToRequests(expenses, 'Expense', 'expenses', r => `SAR ${r.amount} - ${r.description}`);
    addToRequests(genericRequests, 'Employee Request', 'requests', r => `${r.request_type || 'Request'}${r.loan_amount ? ` - SAR ${Number(r.loan_amount).toLocaleString()}` : ''}`);

    // Sort by created_at desc
    allRequests.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

    // Render UI
    let rowsHTML = allRequests.map(r => {
        let badgeClass = 'info';
        if (r.status === 'APPROVED') badgeClass = 'success';
        if (r.status === 'REJECTED') badgeClass = 'danger';

        const employeeName = profilesMap[r.employee_id] || 'Unknown';

        return `
            <tr>
                <td>${new Date(r.created_at).toLocaleDateString()}</td>
                <td>${employeeName}</td>
                <td><strong>${r.type}</strong></td>
                <td>${escapeHTML(r.details)}${r.rejection_reason ? `<br><strong>${t('ui_rejection_reason')}:</strong> ${escapeHTML(r.rejection_reason)}` : ''}</td>
                <td><span class="status-badge ${badgeClass}">${r.status}</span> <span style="font-size: 0.7rem; color: var(--color-text-secondary);">${t('req_archived_badge')}</span></td>
            </tr>
        `;
    }).join('');

    if (allRequests.length === 0) {
        rowsHTML = `<tr><td colspan="5" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">${t('req_no_archived')}</td></tr>`;
    }

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('req_archived_title')}</h1>
                <p class="page-subtitle">${t('req_archived_sub')}</p>
            </div>
        </div>
        
        <div class="card fade-in-up">
            <div class="table-responsive">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>${t('date')}</th>
                            <th>${t('leave_employee')}</th>
                            <th>${t('req_type')}</th>
                            <th>${t('req_details')}</th>
                            <th>${t('req_orig_status')}</th>
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

// ==========================================
// PROJECTS VIEW (V4 Upgrade)
// ==========================================
async function renderProjects() {
    console.log("renderProjects: Starting...");
    if (!currentUser) return `<div class="page-header"><h1 class="page-title">${t('ui_projects')}</h1></div><div class="card">Please login to view projects.</div>`;

    console.log("renderProjects: Fetching projects from db...");
    const projects = await db.fetchProjects();
    console.log("renderProjects: Fetched projects.", { count: projects ? projects.length : 0 });
    window.projectCache = {};

    let html = `
        <div class="page-header" style="display: flex; justify-content: space-between; align-items: center;">
            <h1 class="page-title">${t('ui_projects')}</h1>
            <button class="btn btn-primary" onclick="openProjectModal()"><i data-lucide="plus"></i> ${t('ui_new_project_btn') || 'New Project'}</button>
        </div>
        <div class="dashboard-grid" style="grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1.5rem;">
    `;

    if (!projects || projects.length === 0) {
        html += `<div class="card" style="grid-column: 1 / -1; text-align: center; color: var(--color-text-secondary);">No projects found.</div>`;
    } else {
        projects.forEach(p => {
            window.projectCache[p.id] = p;
            const tagsHtml = (p.project_tags || []).map(t => `<span class="badge" style="background: var(--color-primary); color: white; padding: 0.25rem 0.5rem; border-radius: 4px; font-weight: 500;">${t}</span>`).join(' ');
            const wonDealDetails = p.source === 'WON_DEAL' ? `
                <div class="project-deal-summary">
                    ${p.crm_clients?.name ? `<span><i data-lucide="building-2"></i>${escapeHTML(p.crm_clients.name)}</span>` : ''}
                    ${p.event_date ? `<span><i data-lucide="calendar"></i>${escapeHTML(p.event_date)}</span>` : ''}
                    ${p.event_location ? `<a href="${escapeHTML(p.event_location)}" target="_blank" rel="noopener"><i data-lucide="map-pin"></i>${t('ui_location') || 'Location'}</a>` : ''}
                    <span><i data-lucide="wallet"></i>${t('crm_project_amount') || 'Project'}: SAR ${Number(p.project_amount || 0).toLocaleString()}</span>
                    <span><i data-lucide="badge-dollar-sign"></i>${t('crm_paid_amount_short') || 'Paid'}: SAR ${Number(p.paid_amount || 0).toLocaleString()}</span>
                </div>` : '';
            html += `
                <div class="card" style="display: flex; flex-direction: column; gap: 0.5rem; position: relative;">
                    <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                        <h3 style="margin: 0; padding-right: 3rem;">${p.project_name}</h3>
                        <div style="display: flex; gap: 0.5rem; align-items: center;">
                            <span class="badge" style="background: var(--color-success);">${p.project_category || 'General'}</span>
                            <button onclick="event.stopPropagation(); openEditProjectModal('${p.id}')" class="btn btn-icon" style="background:none; border:none; color:var(--color-text-secondary); cursor:pointer; padding:0;" title="Edit Project"><i data-lucide="edit-2" style="width:16px;height:16px;"></i></button>
                            <button onclick="event.stopPropagation(); handleDeleteProject('${p.id}')" class="btn btn-icon" style="background:none; border:none; color:var(--color-danger); cursor:pointer; padding:0;" title="Delete Project"><i data-lucide="trash-2" style="width:16px;height:16px;"></i></button>
                        </div>
                    </div>
                    <p style="color: var(--color-text-secondary); margin: 0; font-size: 0.9rem;">${p.project_type}</p>
                    <p style="margin: 0.5rem 0; flex-grow: 1;">${p.description || 'No description provided.'}</p>
                    ${wonDealDetails}
                    <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">${tagsHtml}</div>
                </div>
            `;
        });
    }

    html += `</div>`;
    console.log("renderProjects: Completed. Returning HTML of length", html.length);
    return html;
}

window.openProjectModal = async function () {
    document.getElementById('newProjectName').value = '';
    document.getElementById('newProjectType').value = '';
    document.getElementById('newProjectDesc').value = '';
    document.getElementById('newProjectTags').value = '';

    const assigneesSelect = document.getElementById('newProjectAssignees');
    assigneesSelect.innerHTML = '<option value="">Loading...</option>';

    const profiles = await db.fetchAllProfiles();
    if (profiles && profiles.length > 0) {
        assigneesSelect.innerHTML = profiles.map(p => `<option value="${p.id}">${window.formatEmployeeName(p) || p.id}</option>`).join('');
    } else {
        assigneesSelect.innerHTML = '<option value="">No users found</option>';
    }

    document.getElementById('projectModal').classList.add('active');
}

window.handleCreateProject = async function (event) {
    event.preventDefault();
    const name = document.getElementById('newProjectName').value;
    const type = document.getElementById('newProjectType').value;
    const category = document.getElementById('newProjectCategory').value;
    const desc = document.getElementById('newProjectDesc').value;

    const tagsSelect = document.getElementById('newProjectTags');
    const tags = Array.from(tagsSelect.selectedOptions).map(opt => opt.value);

    const assigneesSelect = document.getElementById('newProjectAssignees');
    const assignedPeople = Array.from(assigneesSelect.selectedOptions).map(opt => opt.value);

    const initialTasksRaw = document.getElementById('newProjectTasks') ? document.getElementById('newProjectTasks').value : '';
    const initialTasks = initialTasksRaw.split('\n').map(t => t.trim()).filter(t => t.length > 0);

    document.getElementById('projectModal').classList.remove('active');
    showToast(t('toast_creating_project'), "info");

    const { success, data } = await db.createProject(name, type, desc, assignedPeople, category, tags);

    if (success) {
        let createdProjectId = data && data.length > 0 ? data[0].id : null;

        // Create initial tasks
        if (createdProjectId && initialTasks.length > 0) {
            for (const taskTitle of initialTasks) {
                // Keep the privacy rule of the task by assigning it to the project assignees explicitly in visibleTo and setting visibility to private if needed, or public with project context.
                // We'll use visibility='public' as that's default, but assigned to the project.
                await db.createTask(
                    taskTitle, `Initial task for project: ${name}`, null, null,
                    currentUser.id, 'medium', category, { en: taskTitle }, {},
                    null, null, null, 'public', createdProjectId, tags, assignedPeople
                );
            }
            showToast(`${initialTasks.length} initial tasks created.`, "success");
        }

        // Webhook simulation via notification
        await db.createNotification(currentUser.id, `Project created: ${name}`);
        showToast(t('toast_project_created_successfully'), "success");
        if (currentView === 'projects') renderView('projects');
    } else {
        showToast(t('toast_failed_to_create_project'), "error");
    }
}

window.handleDeleteProject = function (id) {
    document.getElementById('deleteProjectIdInput').value = id;
    document.getElementById('deleteProjectModal').classList.add('active');
};

window.closeDeleteProjectModal = function () {
    document.getElementById('deleteProjectModal').classList.remove('active');
    document.getElementById('deleteProjectIdInput').value = '';
};

window.executeDeleteProject = async function () {
    const id = document.getElementById('deleteProjectIdInput').value;
    if (!id) return;

    closeDeleteProjectModal();
    const { success } = await db.deleteProject(id);
    if (success) {
        showToast(window.t('msg_toast_49') || 'Project deleted successfully', 'success');
        if (currentView === 'projects') renderView('projects');
    } else {
        showToast(window.t('msg_toast_50') || 'Failed to delete project', 'error');
    }
};

window.openEditProjectModal = async function (id) {
    const project = window.projectCache[id];
    if (!project) return;

    document.getElementById('editProjectId').value = project.id;
    document.getElementById('editProjectName').value = project.project_name || '';
    document.getElementById('editProjectType').value = project.project_type || '';
    document.getElementById('editProjectDesc').value = project.description || '';
    document.getElementById('editProjectCategory').value = project.project_category || 'Startup';

    const tagsSelect = document.getElementById('editProjectTags');
    Array.from(tagsSelect.options).forEach(opt => {
        opt.selected = (project.project_tags || []).includes(opt.value);
    });

    const assigneesSelect = document.getElementById('editProjectAssignees');
    assigneesSelect.innerHTML = '<option value="">Loading...</option>';
    const profiles = await db.fetchAllProfiles();
    if (profiles && profiles.length > 0) {
        assigneesSelect.innerHTML = profiles.map(p =>
            `<option value="${p.id}" ${(project.assigned_people || []).includes(p.id) ? 'selected' : ''}>${window.formatEmployeeName(p) || p.id}</option>`
        ).join('');
    } else {
        assigneesSelect.innerHTML = '<option value="">No users found</option>';
    }

    document.getElementById('editProjectModal').classList.add('active');
    if (window.lucide) window.lucide.createIcons();
}

window.handleUpdateProject = async function (event) {
    event.preventDefault();
    const id = document.getElementById('editProjectId').value;
    const name = document.getElementById('editProjectName').value;
    const type = document.getElementById('editProjectType').value;
    const category = document.getElementById('editProjectCategory').value;
    const desc = document.getElementById('editProjectDesc').value;

    const tagsSelect = document.getElementById('editProjectTags');
    const tags = Array.from(tagsSelect.selectedOptions).map(opt => opt.value);

    const assigneesSelect = document.getElementById('editProjectAssignees');
    const assignedPeople = Array.from(assigneesSelect.selectedOptions).map(opt => opt.value);

    document.getElementById('editProjectModal').classList.remove('active');
    showToast(t('toast_updating_project'), "info");

    const { success } = await db.updateProject(id, name, type, desc, assignedPeople, category, tags);

    if (success) {
        showToast(t('toast_project_updated_successfully'), "success");
        if (currentView === 'projects') renderView('projects');
    } else {
        showToast(t('toast_failed_to_update_project'), "error");
    }
}

// ==========================================
// APPROVALS DASHBOARD
// ==========================================
async function renderApprovals() {
    const profile_auth = currentUserProfile || {};
    const canUseApprovals = currentUserRole === 'ADMIN' || currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR' || /manager|supervisor/i.test(profile_auth?.job_title || '');
    if (!canUseApprovals) {
        return `<div class="empty-state">
                    <i data-lucide="shield-alert"></i>
                    <p data-i18n="unauthorized_access">You are not authorized to view this page.</p>
                </div>`;
    }
    const [allTasks, allUsers, allProjects, departments, workflows, leaves, documents, expenses, genericRequests] = await Promise.all([
        db.fetchTasks(), db.fetchUsers(), db.fetchProjects(), db.fetchDepartments(),
        db.fetchRequestApprovalWorkflows(), db.fetchLeaveRequests(), db.fetchDocuments(),
        db.fetchExpenses(), db.fetchGenericRequests()
    ]);
    const profile = (allUsers || []).find(user => user.id === currentUser?.id) || currentUserProfile || {};
    const normalizedRole = String(currentUserRole || '').toUpperCase();
    const isAdmin = ['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(normalizedRole);
    const managedDepartments = (departments || []).filter(department => department.head_id === currentUser?.id);
    const isManager = isAdmin || ['MANAGER', 'SUPERVISOR'].includes(currentUserRole) || /manager|supervisor/i.test(profile.job_title || '') || managedDepartments.length > 0;
    if (!isManager) return `<div class="page-header"><h1 class="page-title">${t('ui_unauthorized')}</h1></div>`;

    const userMap = new Map((allUsers || []).map(user => [user.id, user]));
    const projectMap = new Map((allProjects || []).map(project => [project.id, project]));
    const sourceMap = new Map();
    (leaves || []).forEach(item => sourceMap.set(`leave_requests:${item.id}`, { details: `${item.leave_type || 'Leave'}${item.start_date ? ` Â· ${item.start_date} â€“ ${item.end_date || ''}` : ''}` }));
    (documents || []).forEach(item => sourceMap.set(`document_requests:${item.id}`, { details: `${item.doc_type || 'Document'} Â· ${item.purpose || 'No purpose provided'}` }));
    (expenses || []).forEach(item => sourceMap.set(`expenses:${item.id}`, { details: `SAR ${Number(item.amount || 0).toLocaleString()} Â· ${item.description || 'Expense'}` }));
    (genericRequests || []).forEach(item => sourceMap.set(`requests:${item.id}`, { details: /^loan/i.test(item.request_type || '') ? `Loan Â· SAR ${Number(item.loan_amount || 0).toLocaleString()}` : `${item.request_type || 'Employee Request'}${item.leave_type ? ` Â· ${item.leave_type}` : ''}` }));

    const pendingRequests = (workflows || []).filter(workflow => {
        if (workflow.status !== 'PENDING') return false;
        const step = workflow.steps?.find(item => item.step_order === workflow.current_step);
        return isAdmin || step?.approver_id === currentUser?.id;
    });
    const requestRows = pendingRequests.map(workflow => {
        const step = workflow.steps?.find(item => item.step_order === workflow.current_step);
        const employee = userMap.get(workflow.employee_id);
        const source = sourceMap.get(`${workflow.source_table}:${workflow.source_id}`);
        const canDecide = isAdmin || step?.approver_id === currentUser?.id;

        let detailsString = (source ?? { details: 'Unknown Request' }).details;
        if (workflow.type === 'MANUAL' && /^loan/i.test(workflow.manual_type || '')) {
            detailsString = `Loan â€” SAR ${Number(workflow.manual_amount || 0).toLocaleString()}`;
        }

        return `<tr><td><strong>${escapeHTML(window.formatEmployeeName(employee) || 'Employee')}</strong></td><td>${escapeHTML(workflow.request_type || 'Employee Request')}</td><td>${escapeHTML(detailsString)}</td><td><span class="status-badge warning">${escapeHTML(REQUEST_STAGE_LABELS[step?.stage_key] || 'Pending approval')}</span></td><td>${workflow.created_at ? new Date(workflow.created_at).toLocaleDateString() : 'â€”'}</td><td>${canDecide ? `<div style="display:flex;gap:.5rem"><button class="btn-primary" onclick="handleApprovalRequestDecision('${workflow.source_table}','${workflow.source_id}','APPROVED')">Approve</button><button class="btn-secondary" style="color:var(--color-danger)" onclick="handleApprovalRequestDecision('${workflow.source_table}','${workflow.source_id}','REJECTED')">Reject</button></div>` : '<span class="status-badge info">Assigned to another approver</span>'}</td></tr>`;
    }).join('');

    const departmentNames = new Set(managedDepartments.map(department => department.name));
    if (profile.department_id) {
        const ownDepartment = (departments || []).find(department => department.id === profile.department_id);
        if (ownDepartment && /manager|supervisor/i.test(profile.job_title || '') || ownDepartment && ['MANAGER', 'SUPERVISOR'].includes(currentUserRole)) departmentNames.add(ownDepartment.name);
    }
    const pendingTasks = (allTasks || []).filter(task => String(task.status || '').trim().toLowerCase() === 'pending approval').filter(task =>
        isAdmin || departmentNames.has(task.department) || (task.watchers || []).includes(currentUser?.id)
    );
    const taskRows = pendingTasks.map(task => {
        const assignee = userMap.get(task.assignee_id);
        const project = projectMap.get(task.project_id);
        const department = (departments || []).find(item => item.name === task.department);
        const canDecide = department?.head_id === currentUser?.id;
        const title = task.title_i18n?.[currentLang] || task.title_i18n?.en || task.title || 'Untitled task';
        return `<tr><td><strong>${escapeHTML(title)}</strong>${task.parent_task_id ? '<br><span class="status-badge info">Subtask</span>' : ''}</td><td>${escapeHTML(task.department || 'No department')}</td><td>${escapeHTML(project?.project_name || 'No project')}</td><td>${escapeHTML(window.formatEmployeeName(assignee) || 'Unassigned')}</td><td>${task.completion_requested_at ? new Date(task.completion_requested_at).toLocaleString() : 'â€”'}</td><td>${canDecide ? `<div style="display:flex;gap:.5rem"><button class="btn-primary" onclick="handleTaskApprovalDecision('${task.id}','APPROVED')">Approve</button><button class="btn-secondary" style="color:var(--color-danger)" onclick="handleTaskApprovalDecision('${task.id}','REJECTED')">Reject</button></div>` : '<span class="status-badge info">Watcher access Â· View only</span>'}</td></tr>`;
    }).join('');

    return `<div class="page-header"><div><h1 class="page-title">${t('ui_approvals_dashboard')}</h1><p class="page-subtitle">${t('approvals_subtitle')}</p></div></div>
        <div class="card" style="padding:.5rem;margin-bottom:1rem;display:flex;gap:.5rem;flex-wrap:wrap">
            <button class="btn-primary" data-approval-tab="requests" onclick="setApprovalsTab('requests')">${t('approvals_employee_requests')} <span class="status-badge">${pendingRequests.length}</span></button>
            <button class="btn-secondary" data-approval-tab="tasks" onclick="setApprovalsTab('tasks')">${t('approvals_tasks')} <span class="status-badge">${pendingTasks.length}</span></button>
        </div>
        <section data-approval-panel="requests" class="card"><div class="table-responsive"><table class="data-table"><thead><tr><th>${t('leave_employee')}</th><th>${t('ui_request')}</th><th>${t('req_details')}</th><th>${t('approvals_current_stage')}</th><th>${t('approvals_submitted')}</th><th>${t('leave_actions')}</th></tr></thead><tbody>${requestRows || `<tr><td colspan="6" style="text-align:center;padding:2rem">${t('approvals_no_employee_requests')}</td></tr>`}</tbody></table></div></section>
        <section data-approval-panel="tasks" class="card" hidden><div class="table-responsive"><table class="data-table"><thead><tr><th>${t('nav_tasks')}</th><th>${t('custody_department')}</th><th>${t('ui_project')}</th><th>${t('task_assign_to')}</th><th>${t('approvals_submitted')}</th><th>${t('leave_actions')}</th></tr></thead><tbody>${taskRows || `<tr><td colspan="6" style="text-align:center;padding:2rem">${t('approvals_no_tasks')}</td></tr>`}</tbody></table></div></section>`;
};

window.setApprovalsTab = function (tab) {
    document.querySelectorAll('[data-approval-panel]').forEach(panel => { panel.hidden = panel.dataset.approvalPanel !== tab; });
    document.querySelectorAll('[data-approval-tab]').forEach(button => {
        button.classList.toggle('btn-primary', button.dataset.approvalTab === tab);
        button.classList.toggle('btn-secondary', button.dataset.approvalTab !== tab);
    });
};

window.handleApprovalRequestDecision = async function (sourceTable, sourceId, decision) {
    let note = null;
    if (decision === 'REJECTED') {
        note = await window.showPromptModal(t('approval_rejection_reason_prompt'), t('ui_rejected'), { required: true });
        if (note === null || !note.trim()) return;
    }
    const result = await db.decideRequestApproval(sourceTable, sourceId, decision, note);
    if (!result.success) return showToast(result.error?.message || 'Unable to record this approval.', 'danger');
    showToast(decision === 'APPROVED' ? 'Request approved and moved to its next stage.' : 'Request rejected and employee notified.', 'success');
    renderView('approvals');
};

window.handleTaskApprovalDecision = async function (taskId, decision) {
    const { data: taskData } = await window.supabaseClient.from('tasks').select('id,title,assignee_id,created_by').eq('id', taskId).single();
    if (!taskData) return showToast(window.t('msg_toast_51') || 'Task not found.', 'danger');
    if (decision === 'APPROVED') {
        await window.approveTaskCompletion(taskId);
        if (currentView === 'approvals') renderView('approvals');
        return;
    }
    const reason = await window.showPromptModal(t('task_return_reason_prompt'), t('approvals_tasks'), { required: true });
    if (reason === null || !reason.trim()) return;
    const result = await db.updateTask(taskId, { status: 'in_progress', completion_requested_by: null, completion_requested_at: null });
    if (!result.success) return showToast(result.error?.message || 'Unable to return this task.', 'danger');
    await db.addTaskComment(taskId, currentUser.id, `Completion rejected: ${reason.trim()}`);
    const recipients = [...new Set([taskData.assignee_id, taskData.created_by].filter(id => id && id !== currentUser.id))];
    await Promise.all(recipients.map(id => db.createNotification(id, `Task "${taskData.title}" was returned to In Progress by the department manager.`, taskId)));
    showToast(window.t('msg_toast_52') || 'Task returned to In Progress.', 'success');
    renderView('approvals');
};

window.handleApprovalAction = async function (taskId, newStatus) {
    const { data: taskData } = await window.supabaseClient.from('tasks').select('*').eq('id', taskId).single();
    if (!taskData) {
        showToast(window.t('msg_toast_53') || 'Task not found', 'danger');
        return;
    }

    const isDesigningTask = taskData.department === 'Marketing & Sales' && taskData.sub_type === 'Designing Task';

    if (newStatus === 'Rejected') {
        if (isDesigningTask) {
            const reason = await window.showPromptModal(t('approval_rejection_reason_prompt'), t('ui_rejected'), { required: true });
            if (reason === null) return; // User cancelled

            const res = await db.updateTask(taskId, { delivery_status: 'Edit needed' });
            if (res.error) {
                showToast(t('toast_failed_to_update_task'), 'danger');
            } else {
                if (taskData.assignee_id) {
                    await db.createNotification(taskData.assignee_id, `Your Designing task "${taskData.title}" was rejected by the manager. Reason: ${reason}`, taskId);
                }
                await db.addTaskComment(taskId, currentUser.id, `${t('ui_rejection_reason')}: ${reason}`);
                showToast(window.t('msg_toast_54') || 'Task rejected and sent back to In Progress', 'success');
                renderView('approvals');
            }
        } else {
            window.showConfirmModal(t('modal_title_task_approval'), t('modal_body_are_you_sure_you_want_to') + 'reject and delete this task?', async () => {
                const res = await window.supabaseClient.from('tasks').delete().eq('id', taskId);
                if (res.error) {
                    showToast(t('toast_failed_to_update_task'), 'danger');
                } else {
                    if (taskData.assignee_id) {
                        await db.createNotification(taskData.assignee_id, `Your task "${taskData.title}" was rejected and deleted.`);
                    }
                    showToast(t('toast_task') + ' rejected and deleted', 'success');
                    renderView('approvals');
                }
            });
        }
    } else { // Approve
        const targetStatus = isDesigningTask ? 'completed' : newStatus;
        window.showConfirmModal(t('modal_title_task_approval'), t('modal_body_are_you_sure_you_want_to') + 'approve this task?', async () => {
            const res = isDesigningTask
                ? await db.updateTask(taskId, { delivery_status: 'Approved' })
                : await db.updateTaskStatus(taskId, targetStatus);
            if (res.error) {
                showToast(t('toast_failed_to_update_task'), 'danger');
            } else {
                if (taskData.assignee_id) {
                    await db.createNotification(taskData.assignee_id, `Your task "${taskData.title}" was approved.`, taskId);
                }
                showToast(t('toast_task') + ' approved', 'success');
                renderView('approvals');
            }
        });
    }
};

// Global Esc Key Handler for Modals and Popups
document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') {
        window.toggleHeaderSearch?.(false);
        const activeModals = document.querySelectorAll('.modal.active, .modal.show, .popup.active, .slide-panel.active');
        activeModals.forEach(modal => {
            modal.classList.remove('active');
            modal.classList.remove('show');
        });
    }
});

// Global Search Logic
const searchInput = document.querySelector('#headerSearchInput, .search-input');
window.toggleHeaderSearch = function (open) {
    const modal = document.getElementById('headerSearchModal');
    const input = document.getElementById('headerSearchInput');
    if (!modal) return;
    modal.hidden = !open;
    if (open) setTimeout(() => input?.focus(), 0);
};
if (searchInput) {
    searchInput.addEventListener('input', function (e) {
        const query = e.target.value.toLowerCase().trim();
        const mainContainer = document.getElementById('viewContainer');
        if (!mainContainer) return;

        // Find elements to filter: table rows, cards
        const filterableElements = mainContainer.querySelectorAll('table.data-table tbody tr, .card, .task-card, .list-group-item, .project-card, .client-card');

        filterableElements.forEach(el => {
            // Ignore empty table rows or special rows
            if (el.tagName === 'TR' && el.cells.length === 1 && el.cells[0].colSpan > 1) return;

            if (!query) {
                el.style.display = '';
            } else {
                const text = el.textContent.toLowerCase();
                el.style.display = text.includes(query) ? '' : 'none';
            }
        });
    });

    // Shortcut Cmd/Ctrl + K
    document.addEventListener('keydown', function (event) {
        if ((event.metaKey || event.ctrlKey) && event.key === 'k') {
            event.preventDefault();
            window.toggleHeaderSearch(true);
        }
    });
}

// Close modals when clicking on the backdrop
document.addEventListener('click', function (e) {
    if (e.target.classList.contains('modal')) {
        e.target.classList.remove('active', 'show');
    }
});

initApp();
window.switchEditTaskTab = function(tab) {
    document.querySelectorAll('.edit-task-tab').forEach(btn => {
        btn.classList.remove('active');
        btn.style.background = 'transparent';
        btn.style.color = 'var(--color-text-secondary)';
    });
    const activeBtn = document.querySelector(`.edit-task-tab[onclick="window.switchEditTaskTab('${tab}')"]`);
    if(activeBtn) {
        activeBtn.classList.add('active');
        activeBtn.style.background = 'var(--color-bg)';
        activeBtn.style.color = 'var(--color-text)';
    }

    document.querySelectorAll('.edit-task-tab-content').forEach(content => {
        content.classList.remove('active');
        content.style.display = 'none';
    });
    const activeContent = document.getElementById(tab === 'details' ? 'editTaskTabDetails' : 'editTaskTabAdvanced');
    if(activeContent) {
        activeContent.classList.add('active');
        activeContent.style.display = 'flex';
    }
};

window.updateEditTaskSelectUI = function(selectElem) {
    if(!selectElem) return;
    const valText = selectElem.options[selectElem.selectedIndex]?.text || 'None';
    const container = selectElem.closest('.property-cell');
    if(container) {
        const span = container.querySelector('.select-ui-value');
        if(span) span.textContent = valText;
    }
};

window.updateEditTaskDateUI = function(dateElem) {
    if(!dateElem) return;
    const container = dateElem.closest('.property-cell');
    if(container) {
        const span = container.querySelector('.date-ui-value');
        if(span) span.textContent = dateElem.value || 'Set date';
    }
};

window.updateEditTaskPriorityUI = function(selectElem) {
    if(!selectElem) return;
    const val = selectElem.value;
    const valText = selectElem.options[selectElem.selectedIndex]?.text || 'None';
    const container = selectElem.closest('.property-cell');
    if(container) {
        const span = container.querySelector('.priority-ui-value');
        if(span) {
            span.textContent = valText;
            if(val === 'urgent') span.style.background = 'rgba(239, 68, 68, 0.15)', span.style.color = 'var(--color-danger)';
            else if(val === 'high') span.style.background = 'rgba(245, 158, 11, 0.15)', span.style.color = 'var(--color-warning)';
            else if(val === 'medium') span.style.background = 'rgba(59, 130, 246, 0.15)', span.style.color = 'var(--color-primary)';
            else span.style.background = 'rgba(107, 114, 128, 0.15)', span.style.color = 'var(--color-text-secondary)';
        }
    }
};

window.updateEditTaskWatchersUI = function(selectElem) {
    if(!selectElem) return;
    const selected = Array.from(selectElem.selectedOptions).map(opt => opt.text);
    const container = selectElem.closest('.property-cell');
    if(container) {
        const span = container.querySelector('.watchers-ui-value');
        if(span) {
            span.textContent = selected.length > 0 ? selected.join(', ') : 'No followers';
            span.title = selected.join(', ');
        }
    }
};

window.syncEditTaskWatcher = function (checkbox) {
    const select = document.getElementById('editTaskWatchers');
    const option = Array.from(select?.options || []).find(item => item.value === checkbox.value);
    if (option) option.selected = checkbox.checked;
    window.updateEditTaskWatchersUI(select);
    window.updateEditTaskSelectAllState('watcher');
};

window.toggleEditTaskAssignees = function (checked) {
    document.querySelectorAll('#editTaskAssigneeOptions input[type="checkbox"]:not(#editTaskAssigneeSelectAll)').forEach(input => { input.checked = checked; });
};

window.toggleEditTaskWatchers = function (checked) {
    const select = document.getElementById('editTaskWatchers');
    document.querySelectorAll('#editTaskWatchersOptions input[type="checkbox"]:not(#editTaskWatcherSelectAll)').forEach(input => {
        input.checked = checked;
        const option = Array.from(select?.options || []).find(item => item.value === input.value);
        if (option) option.selected = checked;
    });
    window.updateEditTaskWatchersUI(select);
};

window.updateEditTaskSelectAllState = function (type) {
    const root = document.getElementById(type === 'assignee' ? 'editTaskAssigneeOptions' : 'editTaskWatchersOptions');
    const master = root?.querySelector(type === 'assignee' ? '#editTaskAssigneeSelectAll' : '#editTaskWatcherSelectAll');
    if (!root || !master) return;
    const items = Array.from(root.querySelectorAll('input[type="checkbox"]')).filter(input => input !== master);
    master.checked = items.length > 0 && items.every(input => input.checked);
};

window.updateEditTaskProgress = function (value) {
    const output = document.getElementById('editTaskProgressValue');
    if (output) output.value = `${Math.max(0, Math.min(100, Number(value) || 0))}%`;
};

window.toggleEditTaskRepeatCustom = function (value) {
    const input = document.getElementById('editTaskRepeatDays');
    if (input) input.hidden = value !== 'CUSTOM';
};

window.editTaskPromptEstimate = async function() {
    const el = document.getElementById('editTaskEstimate');
    const val = await window.showPromptModal('Enter estimated time (e.g., 4h, 1d):', 'Estimated time', { value: el.value });
    if(val !== null) {
        el.value = val;
        document.querySelector('.estimate-ui-value').textContent = val || 'Not set';
    }
};

window.editTaskPromptCategory = async function() {
    const el = document.getElementById('editTaskCategory');
    const val = await window.showPromptModal('Enter tags (comma separated):', 'Task tags', { value: el.value });
    if(val !== null) {
        el.value = val;
        document.querySelector('.category-ui-value').textContent = val || 'No tags';
    }
};

window.handleEditTaskFilesSelect = function(input) {
    const list = document.getElementById('editTaskFilesList');
    list.innerHTML = '';
    if(input.files && input.files.length > 0) {
        Array.from(input.files).forEach(file => {
            const div = document.createElement('div');
            div.style.cssText = 'display: flex; align-items: center; gap: 0.5rem; padding: 0.5rem; background: var(--color-bg); border-radius: 4px; font-size: 0.85rem;';
            div.innerHTML = '<i data-lucide="file" style="width: 14px; height: 14px;"></i> ' + escapeHTML(file.name);
            list.appendChild(div);
        });
        if(window.lucide) window.lucide.createIcons();
    }
};
// --- Create Task Modal: Department Change Handler ---
window.handleCreateTaskDeptChange = function(value) {
    // Update assignee list based on department
    if (window.handleTaskDepartmentChange) {
        window.handleTaskDepartmentChange('new', value);
    }

    // Show/hide task type group
    const subTypeGroup = document.getElementById('taskSubTypeGroup');
    if (subTypeGroup) {
        // Show task type for Marketing & Sales department
        if (isMarketingTaskDepartment(value)) {
            subTypeGroup.style.display = 'flex';
        } else {
            subTypeGroup.style.display = 'none';
            const taskType = document.getElementById('taskSubType');
            if (taskType) {
                taskType.value = '';
                window.handleCreateTaskTypeChange('');
            }
        }
    }
};

// --- Create Task Modal: Task Type Change Handler ---
window.handleCreateTaskTypeChange = function(checked) {
    const collapseLabel = document.getElementById('createTaskCollapseLabel');

    const designing = checked === 'Designing Task' || checked === true;
    if (designing) {
        if (collapseLabel) collapseLabel.textContent = 'Attachments';
        // Show marketing design fields
        if (window.handleMarketingTaskTypeChange) {
            window.handleMarketingTaskTypeChange('new', 'Designing Task');
        }
    } else {
        if (collapseLabel) collapseLabel.textContent = 'Attachments';
        // Hide marketing design fields
        if (window.handleMarketingTaskTypeChange) {
            window.handleMarketingTaskTypeChange('new', '');
        }
    }
};

// --- Create Task Modal: Toggle Collapsible Section ---
window.toggleCreateTaskCollapse = function(btn) {
    btn.classList.toggle('open');
    const body = document.getElementById('createTaskCollapseBody');
    if (body) body.classList.toggle('open');
};

// --- Create Task Modal: File Upload Handler ---
window.handleCreateTaskFiles = function(input) {
    const list = document.getElementById('createTaskFileList');
    if (!list) return;

    if (input.files && input.files.length > 0) {
        Array.from(input.files).forEach(file => {
            const item = document.createElement('div');
            item.className = 'create-task-file-item';
            item.innerHTML = '<i data-lucide="file" style="width:14px;height:14px;"></i> ' + escapeHTML(file.name) + ' <button type="button" onclick="this.parentElement.remove()"><i data-lucide="x" style="width:12px;height:12px;"></i></button>';
            list.appendChild(item);
        });
        if (window.lucide) window.lucide.createIcons();
    }
};

// --- Create Task Modal: Drag and Drop ---
document.addEventListener('DOMContentLoaded', function() {
    document.addEventListener('dragover', function(e) {
        const zone = document.getElementById('createTaskUploadZone');
        if (zone && zone.contains(e.target)) {
            e.preventDefault();
            zone.classList.add('dragover');
        }
    });
    document.addEventListener('dragleave', function(e) {
        const zone = document.getElementById('createTaskUploadZone');
        if (zone && !zone.contains(e.relatedTarget)) {
            zone.classList.remove('dragover');
        }
    });
    document.addEventListener('drop', function(e) {
        const zone = document.getElementById('createTaskUploadZone');
        if (zone && zone.contains(e.target)) {
            e.preventDefault();
            zone.classList.remove('dragover');
            const input = document.getElementById('createTaskFileInput');
            if (input && e.dataTransfer.files.length > 0) {
                input.files = e.dataTransfer.files;
                window.handleCreateTaskFiles(input);
            }
        }
    });
});
// --- Task List Modal: Tab Switcher ---
window.showTaskListContextMenu = function(e, listId, isAdmin) {
    e.preventDefault();
    e.stopPropagation();
    let menu = document.getElementById('taskListContextMenu');
    if (!menu) {
        menu = document.createElement('div');
        menu.id = 'taskListContextMenu';
        menu.style.cssText = 'display:none; position:fixed; z-index:10000; background:var(--color-surface); border:1px solid var(--color-border); border-radius:6px; box-shadow:0 4px 16px rgba(0,0,0,0.18); min-width:160px; padding:4px 0;';
        document.body.appendChild(menu);
        document.addEventListener('click', function(ev) {
            if (!ev.target.closest('#taskListContextMenu')) {
                menu.style.display = 'none';
            }
        }, { capture: true });
    }

    let html = '';
    if (isAdmin) {
        html += `<button onclick="window.openTaskListModal('${listId}'); document.getElementById('taskListContextMenu').style.display='none';" style="display:flex;align-items:center;width:100%;padding:8px 16px;background:none;border:none;text-align:left;cursor:pointer;color:var(--color-text);font-size:0.875rem;gap:8px;"><i data-lucide="settings" style="width:15px;height:15px;flex-shrink:0;"></i>Edit List</button>`;
    }
    html += `<button onclick="window.handleDeleteTaskList('${listId}'); document.getElementById('taskListContextMenu').style.display='none';" style="display:flex;align-items:center;width:100%;padding:8px 16px;background:none;border:none;text-align:left;cursor:pointer;color:var(--color-danger);font-size:0.875rem;gap:8px;"><i data-lucide="trash-2" style="width:15px;height:15px;flex-shrink:0;"></i>Delete List</button>`;
    menu.innerHTML = html;

    menu.style.display = 'block';
    let left = e.clientX, top = e.clientY;
    const r = menu.getBoundingClientRect();
    if (left + r.width > window.innerWidth) left = window.innerWidth - r.width - 8;
    if (top + r.height > window.innerHeight) top = window.innerHeight - r.height - 8;
    menu.style.left = left + 'px';
    menu.style.top = top + 'px';

    if (window.lucide) window.lucide.createIcons({ elements: [menu] });
};

window.switchTaskListTab = function(tabName) {
    document.querySelectorAll('.task-list-tab').forEach(btn => {
        btn.classList.remove('active');
    });
    
    const activeBtn = document.querySelector(`.task-list-tab[onclick="window.switchTaskListTab('${tabName}')"]`);
    if(activeBtn) {
        activeBtn.classList.add('active');
    }

    document.querySelectorAll('.task-list-tab-content').forEach(content => {
        content.classList.remove('active');
        content.style.display = 'none';
    });
    
    const tabMap = {
        'general': 'taskListTabGeneral',
        'access': 'taskListTabAccess',
        'notification': 'taskListTabNotification',
        'customFields': 'taskListTabCustomFields'
    };
    
    const activeContent = document.getElementById(tabMap[tabName]);
    if(activeContent) {
        activeContent.classList.add('active');
        activeContent.style.display = 'block';
    }
};

