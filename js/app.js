// App State
let currentLang = 'en';
let currentTheme = 'dark';
let currentView = 'login';
let loginMode = 'login';
let currentUser = null;
let viewHistory = [];

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

window.goBack = function() {
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
let currentUserRole = null;
let currentContractEmployeeId = null;
let currentContractEmployeeName = '';

// Inactivity Tracker (5 Minutes)
let inactivityTimeout;
function resetInactivityTimeout() {
    clearTimeout(inactivityTimeout);
    if (currentUser && currentView !== 'login') {
        inactivityTimeout = setTimeout(() => {
            showToast(t('timeout_message') || "Logged out due to inactivity", "warning");
            window.handleLogout();
        }, 5 * 60 * 1000); // 5 minutes
    }
}

// ==========================================
// PWA Installation
// ==========================================
let deferredPrompt;

if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js')
            .then(registration => {
                console.log('SW registered: ', registration);
            })
            .catch(registrationError => {
                console.log('SW registration failed: ', registrationError);
            });
    });
}

function showInstallBanner() {
    if (localStorage.getItem('pwaPromptDismissed')) return;
    
    // Don't show if already installed (standalone mode)
    if (window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true) {
        return;
    }

    if (!document.getElementById('pwaInstallBanner')) {
        const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream;
        const banner = document.createElement('div');
        banner.id = 'pwaInstallBanner';
        banner.className = 'install-banner';
        
        let contentHtml = `
            <div class="install-banner-content">
                <h4>Install MUQAM HR</h4>
                <p>Add to your home screen for quick access</p>
            </div>
            <button class="install-banner-btn" id="pwaInstallBtn">Install</button>
            <button class="install-banner-close" id="pwaCloseBtn"><i data-lucide="x"></i></button>
        `;

        if (isIOS) {
            contentHtml = `
                <div class="install-banner-content">
                    <h4>Install MUQAM HR</h4>
                    <p>Tap <i data-lucide="share" style="width:16px;height:16px;display:inline-block;vertical-align:middle;"></i> and then "Add to Home Screen"</p>
                </div>
                <button class="install-banner-close" id="pwaCloseBtn"><i data-lucide="x"></i></button>
            `;
        }

        banner.innerHTML = contentHtml;
        document.body.appendChild(banner);
        if (typeof lucide !== 'undefined') 
// User Management Actions
window.showEditUserModal = async (userId) => {
    const user = await db.getUserProfile(userId);
    if (!user) {
        showToast("User not found.", "danger");
        return;
    }
    document.getElementById('editUserId').value = user.id;
    document.getElementById('editFullName').value = user.full_name || '';
    document.getElementById('editIqama').value = user.iqama_number || '';
    document.getElementById('editPhone').value = user.phone_number || '';
    document.getElementById('editJobTitle').value = user.job_title || '';
    document.getElementById('editRole').value = user.role || 'EMPLOYEE';
    
    const mgrSelect = document.getElementById('editManagerId');
    mgrSelect.innerHTML = '<option value="">No Manager</option>';
    const users = await db.fetchUsers();
    users.filter(m => m.role === 'MANAGER' || m.role === 'ADMIN').forEach(m => {
        mgrSelect.innerHTML += `<option value="${m.id}" ${user.manager_id === m.id ? 'selected' : ''}>${m.full_name || 'Mgr'}</option>`;
    });

    document.getElementById('editUserModal').classList.add('active');
};

window.handleUpdateUser = async (e) => {
    e.preventDefault();
    const userId = document.getElementById('editUserId').value;
    const updates = {
        full_name: document.getElementById('editFullName').value,
        iqama_number: document.getElementById('editIqama').value,
        phone_number: document.getElementById('editPhone').value,
        job_title: document.getElementById('editJobTitle').value,
        role: document.getElementById('editRole').value,
        manager_id: document.getElementById('editManagerId').value || null
    };

    const res = await db.updateUserProfile(userId, updates);
    if (res) {
        showToast("User updated successfully", "success");
        document.getElementById('editUserModal').classList.remove('active');
        renderView('users');
    } else {
        showToast("Failed to update user", "danger");
    }
};

window.handleResetUserPassword = async (userId) => {
    if (!confirm("Are you sure you want to reset this user's password and unlock their account?")) return;
    
    // Generate 8 char random alphanumeric password
    const newPassword = Math.random().toString(36).slice(-8);
    
    const user = await db.getUserProfile(userId);
    
    // Attempt password reset
    const success = await db.resetUserPassword(userId, newPassword);
    
    if (success && user?.email) {
        await db.resetLoginLockout(user.email);
        alert(`Password for ${user.email} reset successfully!\nNew Temporary Password: ${newPassword}\n\nPlease share this securely with the user.`);
    } else {
        showToast("Failed to reset password", "danger");
    }
};

window.handleDeleteUser = async (userId) => {
    if (!confirm("Are you sure you want to delete this user? This action cannot be undone.")) return;
    
    const success = await db.deleteUser(userId);
    if (success) {
        showToast("User deleted successfully", "success");
        renderView('users');
    } else {
        showToast("Failed to delete user", "danger");
    }
};

// Requests Page Handlers
window.renderRequests = async () => {
    const isEmployee = currentUserRole === 'EMPLOYEE';
    const requests = await db.fetchRequests(isEmployee ? currentUser?.id : null);
    
    let tableRows = requests.map(r => `
        <tr>
            <td>${new Date(r.created_at).toLocaleDateString()}</td>
            <td>${r.profiles?.full_name || 'Unknown'}</td>
            <td>${r.request_type}</td>
            <td>${r.leave_type || '-'}</td>
            <td><span class="status-badge ${r.status === 'Approved' ? 'success' : (r.status === 'Rejected' ? 'danger' : 'info')}">${r.status}</span></td>
            <td>
                ${!isEmployee && r.status === 'Pending' ? `
                    <button class="btn-primary" style="padding: 0.2rem 0.5rem; font-size:0.8rem" onclick="updateRequestStatus('${r.id}', 'Approved')">Approve</button>
                    <button class="btn-primary" style="background:var(--color-danger); padding: 0.2rem 0.5rem; font-size:0.8rem" onclick="updateRequestStatus('${r.id}', 'Rejected')">Reject</button>
                ` : ''}
            </td>
        </tr>
    `).join('');

    if (requests.length === 0) {
        tableRows = `<tr><td colspan="6" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">No requests found.</td></tr>`;
    }

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">Employee Requests</h1>
                <p class="page-subtitle">Manage leave, loan, IT support, and other requests.</p>
            </div>
            <button class="btn-primary" onclick="showNewRequestModal()">
                <i data-lucide="file-signature"></i> New Request
            </button>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-12">
                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Date</th>
                                <th>Employee Name</th>
                                <th>Request Type</th>
                                <th>Leave Type</th>
                                <th>Status</th>
                                <th>Actions</th>
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
    const isEmployee = currentUserRole === 'EMPLOYEE';
    const users = isEmployee ? [] : await db.fetchUsers();
    
    const empSelect = document.getElementById('requestEmployeeId');
    if (isEmployee) {
        empSelect.innerHTML = `<option value="${currentUser.id}">${currentUser.email}</option>`;
        empSelect.disabled = true;
    } else {
        empSelect.innerHTML = users.map(u => `<option value="${u.id}" ${u.id === currentUser.id ? 'selected' : ''}>${u.full_name || u.email}</option>`).join('');
        empSelect.disabled = false;
    }
    

    document.getElementById('requestModal').classList.add('active');
};

window.handleCreateRequest = async (e) => {
    e.preventDefault();
    if (!currentUser) return;
    const empId = document.getElementById('requestEmployeeId').value;
    const reqType = document.getElementById('requestType').value;
    const leaveType = reqType === 'Leave Request' ? document.getElementById('requestLeaveType').value : null;

    const res = await db.createRequest(empId, reqType, leaveType);
    if (res) {
        showToast("Request submitted successfully", "success");
        document.getElementById('requestModal').classList.remove('active');
        renderView('requests');
    } else {
        showToast("Failed to submit request", "danger");
    }
};

window.updateRequestStatus = async (reqId, status) => {
    if (!supabaseClient) return;
    try {
        const { error } = await supabaseClient.from('requests').update({ status }).eq('id', reqId);
        if (error) throw error;
        showToast(`Request ${status}`, "success");
        renderView('requests');
    } catch (e) {
        showToast("Failed to update status", "danger");
    }
};

lucide.createIcons();
        const installBtn = document.getElementById('pwaInstallBtn');
        if (installBtn) {
            installBtn.addEventListener('click', async () => {
                banner.classList.remove('show');
                setTimeout(() => banner.remove(), 400); // Wait for transition then remove
                if (deferredPrompt) {
                    deferredPrompt.prompt();
                    const { outcome } = await deferredPrompt.userChoice;
                    console.log(`User response to the install prompt: ${outcome}`);
                    deferredPrompt = null;
                } else {
                    alert("To install, open your browser's menu and select 'Add to Home Screen' or 'Install App'.");
                }
                localStorage.setItem('pwaPromptDismissed', 'true');
            });
        }

        const closeBtn = document.getElementById('pwaCloseBtn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                banner.classList.remove('show');
                setTimeout(() => banner.remove(), 400);
                localStorage.setItem('pwaPromptDismissed', 'true');
            });
        }

        // Slight delay to animate in
        setTimeout(() => {
            banner.classList.add('show');
        }, 2000);
    }
}

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
['mousemove', 'keydown', 'mousedown', 'touchstart'].forEach(event => {
    document.addEventListener(event, resetInactivityTimeout);
});

// DOM Elements
const htmlElement = document.documentElement;
const viewContainer = document.getElementById('viewContainer');
const navItems = document.querySelectorAll('.nav-item');

// Initialize Icons
lucide.createIcons();

// --- THEME MANAGEMENT ---
window.toggleTheme = function () {
    currentTheme = currentTheme === 'light' ? 'dark' : 'light';
    htmlElement.setAttribute('data-theme', currentTheme);
    lucide.createIcons();
    const dropdown = document.getElementById('profileDropdown');
    if (dropdown) dropdown.style.display = 'none';
}

// --- LANGUAGE MANAGEMENT ---
window.toggleLanguage = function () {
    currentLang = currentLang === 'en' ? 'ar' : 'en';
    htmlElement.setAttribute('dir', currentLang === 'ar' ? 'rtl' : 'ltr');
    htmlElement.setAttribute('lang', currentLang);

    const langDisplay = document.getElementById('currentLangDisplay');
    if (langDisplay) {
        langDisplay.textContent = currentLang === 'en' ? 'EN' : 'AR';
    }

    updateTranslations();
    renderView(currentView); // Re-render view for updated strings inside
    const dropdown = document.getElementById('profileDropdown');
    if (dropdown) dropdown.style.display = 'none';
}

function updateTranslations() {
    const texts = document.querySelectorAll('[data-i18n]');
    texts.forEach(el => {
        const key = el.getAttribute('data-i18n');
        if (i18n[currentLang][key]) {
            el.textContent = i18n[currentLang][key];
        }
    });

    const placeholders = document.querySelectorAll('[data-i18n-placeholder]');
    placeholders.forEach(el => {
        const key = el.getAttribute('data-i18n-placeholder');
        if (i18n[currentLang][key]) {
            el.setAttribute('placeholder', i18n[currentLang][key]);
        }
    });
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
    return i18n[currentLang][key] || key;
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
function showToast(message, type = 'info') {
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

    if (type === 'success') {
        icon = 'check-circle';
        color = 'var(--color-success)';
    } else if (type === 'warning') {
        icon = 'alert-triangle';
        color = 'var(--color-warning)';
    } else if (type === 'danger') {
        icon = 'x-circle';
        color = '#ef4444';
    }

    toast.style.borderInlineStartColor = color;
    toast.innerHTML = `<i data-lucide="${icon}" style="color: ${color}"></i> <span>${message}</span>`;

    container.appendChild(toast);
    lucide.createIcons();

    setTimeout(() => {
        toast.remove();
    }, 3500);
}

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
                <div style="font-size:0.85rem; font-weight:600; margin-bottom:0.25rem; ${m.user_id === currentUser.id ? 'color:rgba(255,255,255,0.9);' : 'color:var(--color-text-secondary);'}">${m.profiles.full_name}</div>
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
                <p class="page-subtitle">Connect with your colleagues!</p>
            </div>
        </div>
        <div class="dashboard-grid">
            <div class="card col-span-12">
                <div style="max-height:600px; overflow-y:auto; padding-right:1rem; display:flex; flex-direction:column-reverse;" id="communityChatBox">
                    ${chatHTML}
                </div>
                <form onsubmit="handlePostCommunityMessage(event)" style="margin-top:1.5rem; display:flex; gap:1rem;">
                    <input type="text" id="communityMessageInput" class="form-control" placeholder="Type a message..." required style="flex:1;">
                    <button type="submit" class="btn-primary">Post</button>
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

    // Forcefully wipe all local and session storage to guarantee no stale auth tokens remain
    localStorage.clear();
    sessionStorage.clear();

    // A clean reload ensures all intervals, states, and UI elements (like sidebar/topbar) are completely reset
    window.location.reload();
}

window.handleLeaveSubmit = async function (e) {
    e.preventDefault();
    const type = document.getElementById('leaveType').value;
    const start = document.getElementById('leaveStart').value;
    const end = document.getElementById('leaveEnd').value;
    const reason = document.getElementById('leaveReason').value;

    const success = await db.submitLeaveRequest(currentUser.id, {
        leave_type: type,
        start_date: start,
        end_date: end,
        reason: reason
    });

    if (success) {
        showToast(t('toast_leave_applied'), 'success');
        renderView('leave');
    } else {
        showToast("Failed to submit leave", 'danger');
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
    db.updateLastLogin(user.id);

    const profile = await db.getUserProfile(user.id);
    if (profile) {
        currentUserRole = profile.role;
        updateTopbarProfile(profile);
        // Check for Birthday
        if (profile.birth_date) {
            const today = new Date();
            const bday = new Date(profile.birth_date);
            if (today.getMonth() === bday.getMonth() && today.getDate() === bday.getDate()) {
                const bdayMessage = `🎉 ${t('birthday_msg')} ${profile.full_name}! 🎂🎈`;

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

    // Start inactivity tracker
    resetInactivityTimeout();

    // Show sidebar and topbar again
    document.querySelector('.sidebar').style.display = 'block';
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
    if (employeesNav) employeesNav.style.display = (currentUserRole === 'ADMIN' || ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR')) ? 'flex' : 'none';
    
    const isHussain = currentUser.full_name && currentUser.full_name.toLowerCase().includes('hussain') || currentUser.email && currentUser.email.toLowerCase().includes('hussain');
    if (approvalsNav) approvalsNav.style.display = (currentUserRole === 'ADMIN' || isHussain) ? 'flex' : 'none';

    // Route based on role
    currentView = 'dashboard';
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

window.setLoginMode = function(mode) {
    loginMode = mode;
    renderView('login');
}

window.handleForgotPasswordSubmit = async function(e) {
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

window.handleResetPasswordSubmit = async function(e) {
    e.preventDefault();
    const newPassword = document.getElementById('new-password').value;
    const { data, error } = await db.updatePassword(newPassword);
    if (error) {
        showToast(error.message, 'danger');
    } else {
        showToast("Password updated successfully!", 'success');
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
                    <input type="password" autocomplete="new-password" id="new-password" class="form-control" placeholder="••••••••" required style="padding-right: 40px;">
                    <button type="button" class="password-toggle-btn" onclick="togglePasswordVisibility('new-password')" style="color: navy;">
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
                    <input type="password" autocomplete="new-password" id="password" class="form-control" placeholder="••••••••" required style="padding-right: 40px;">
                    <button type="button" class="password-toggle-btn" onclick="togglePasswordVisibility('password')" style="color: navy;">
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
        <div style="display: flex; height: 100vh; align-items: center; justify-content: center; width: 100vw; position: fixed; top: 0; left: 0; background: url('images/login_bg.png') center/cover no-repeat; z-index: 9999;">
            <div class="card" style="width: 100%; max-width: 400px; padding: 2.5rem 2rem; background: rgba(0, 0, 0, 0.4); backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); border: 1px solid rgba(255, 255, 255, 0.2); box-shadow: 0 30px 60px rgba(0,0,0,0.3); color: white;">
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

async function renderDashboard() {
    // Run independent fetches in parallel
    const [todayAttendance, announcements, newsRes] = await Promise.all([
        db.fetchTodayAttendance(currentUser?.id),
        db.fetchAnnouncements(),
        fetch('https://api.rss2json.com/v1/api.json?rss_url=https://feeds.bbci.co.uk/news/world/rss.xml').catch(() => null)
    ]);

    const isClockedIn = todayAttendance != null && !todayAttendance.clock_out_time;
    const announcementsList = announcements || [];

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
                newsHTML = newsData.items.slice(0, 5).map(item => `
                    <div style="margin-bottom: 1rem; border-bottom: 1px solid var(--color-border); padding-bottom: 0.5rem;">
                        <a href="${item.link}" target="_blank" style="color: var(--color-primary); font-weight: 600; text-decoration: none;">${item.title}</a>
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
                    <strong style="color: var(--color-danger);">${t('docs_expiring')}:</strong> ${expiringDocs.length} document(s) expire soon.
                </div>
            `;
        }

        if (currentUserRole === 'ADMIN' && results[1]) {
            const contracts = results[1].data || [];
            const expiringContracts = contracts.filter(c => c.end_date && (new Date(c.end_date) - new Date()) / (1000 * 60 * 60 * 24) < 30);
            if (expiringContracts.length > 0) {
                expirationAlerts += `
                    <div style="background: rgba(245, 158, 11, 0.1); border-left: 4px solid var(--color-warning); padding: 1rem; margin-bottom: 1rem; border-radius: 4px;">
                        <strong style="color: var(--color-warning);">${t('contract_expiring')}:</strong> ${expiringContracts.length} contract(s) expire soon.
                    </div>
                `;
            }
        }
    } catch (e) { }

    let adminWidgets = '';
    if (currentUserRole === 'ADMIN') {
        const allProfiles = await db.fetchAllProfiles();
        const lastLoginsHTML = allProfiles.filter(p => p.last_login).sort((a, b) => new Date(b.last_login) - new Date(a.last_login)).slice(0, 5).map(p => `
            <div style="display:flex; justify-content:space-between; margin-bottom: 0.5rem;">
                <span>${p.full_name}</span>
                <span style="color:var(--color-text-secondary); font-size:0.85rem;">${new Date(p.last_login).toLocaleString()}</span>
            </div>
        `).join('') || '<p>No recent logins.</p>';

        adminWidgets += `
            <div class="card col-span-12 md:col-span-6">
                <div class="card-title">${t('last_login')}</div>
                <div>${lastLoginsHTML}</div>
            </div>
        `;
    }

    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('welcome')}</h1>
                <p class="page-subtitle">${t('welcome_sub')}</p>
            </div>
            ${isClockedIn
            ? `<button class="btn-primary" style="background: var(--color-danger);" onclick="handleClockOutPrompt('${todayAttendance.id}')">${t('attendance_clock_out')}</button>`
            : `<button class="btn-primary" onclick="handleClockIn()">${t('attendance_clock_in')}</button>`
        }
        </div>

        <div class="dashboard-grid">
            ${expirationAlerts ? `<div class="col-span-12">${expirationAlerts}</div>` : ''}
            
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
                        <label class="form-label">Title</label>
                        <input type="text" id="announceTitle" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">Content</label>
                        <textarea id="announceContent" class="form-control" rows="4" required></textarea>
                    </div>
                    <div style="display: flex; gap: 1rem; margin-top: 1.5rem;">
                        <button type="submit" class="btn-primary" style="flex: 1;">Post</button>
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
                    <button class="btn-primary" style="background:var(--color-warning);" onclick="executeClockOut('ORDER')">${t('attendance_location_order')}</button>
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
    await db.postAnnouncement(currentUser.id, title, content);
    closeAnnouncementModal();
    renderView('dashboard');
};

let currentAttendanceId = null;
window.handleClockIn = async () => {
    const fallbackClockIn = async (loc) => {
        try {
            await db.clockIn(currentUser.id, loc);
            showToast("Clocked in successfully!", "success");
            renderView('dashboard');
        } catch (err) {
            console.error(err);
            showToast("Error clocking in.", "danger");
        }
    };

    if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition((position) => {
            const loc = position.coords.latitude + ',' + position.coords.longitude;
            fallbackClockIn(loc);
        }, (error) => {
            console.warn("Geolocation failed or denied, using fallback location.");
            fallbackClockIn("Location Unavailable");
        });
    } else {
        fallbackClockIn("Location Unavailable");
    }
};

window.handleClockOutPrompt = (attendanceId) => {
    currentAttendanceId = attendanceId;
    document.getElementById('clockOutModal').classList.add('show');
};
window.closeClockOutModal = () => document.getElementById('clockOutModal').classList.remove('show');

window.executeClockOut = async (type) => {
    const fallbackClockOut = async (loc) => {
        try {
            const attendance = await db.fetchTodayAttendance(currentUser.id);
            if (!attendance) {
                showToast("No active clock-in found for today.", "danger");
                closeClockOutModal();
                return;
            }
            const inTime = new Date(attendance.clock_in_time);
            const diffHours = (new Date() - inTime) / (1000 * 60 * 60);
            const overtime = Math.max(0, diffHours - 8).toFixed(2);

            await db.clockOut(currentAttendanceId, loc, type, overtime);
            closeClockOutModal();
            showToast("Clocked out successfully!", "success");
            renderView('dashboard');
        } catch (err) {
            console.error(err);
            showToast("Error clocking out.", "danger");
        }
    };

    if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition((position) => {
            const loc = position.coords.latitude + ',' + position.coords.longitude;
            fallbackClockOut(loc);
        }, (error) => {
            console.warn("Geolocation failed or denied, using fallback location.");
            fallbackClockOut("Location Unavailable");
        });
    } else {
        fallbackClockOut("Location Unavailable");
    }
};

// Render Time & Attendance
async function renderTime() {
    const punches = await db.fetchTimePunches(currentUserRole === 'ADMIN' ? null : currentUser?.id);

    let tableRows = punches.map(p => `
        <tr>
            <td>${new Date(p.punch_time).toLocaleDateString()}</td>
            <td>${new Date(p.punch_time).toLocaleTimeString()}</td>
            ${currentUserRole === 'ADMIN' ? `<td><span style="font-size: 0.75rem; color: var(--color-text-secondary);">${p.employee_id.substring(0, 8)}...</span></td>` : ''}
            <td>${p.punch_type}</td>
            <td><span class="status-badge ${p.punch_type === 'IN' ? 'success' : 'info'}">${p.punch_type}</span></td>
        </tr>
    `).join('');

    if (punches.length === 0) {
        tableRows = `<tr><td colspan="4" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">${t('time_no_punches')}</td></tr>`;
    }

    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('nav_time')}</h1>
                <p class="page-subtitle">${t('timesheet_sub')}</p>
            </div>
        </div>
        <div class="card">
            <div class="card-title">${t('timesheet')}</div>
            <div class="table-responsive">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>${t('date')}</th>
                            <th>${t('time')}</th>
                            ${currentUserRole === 'ADMIN' ? `<th>${t('time_emp_id')}</th>` : ''}
                            <th>${t('time_punch_type')}</th>
                            <th>${t('status')}</th>
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

window.openTaskDetailsModal = async function(id) {
    const task = window.taskCache[id];
    if (!task) return;
    
    document.getElementById('detailsTaskId').value = task.id;
    document.getElementById('detailsTaskTitle').textContent = task.displayTitle || task.title;
    document.getElementById('detailsTaskAssignee').textContent = task.assignee?.full_name || 'Unassigned';
    document.getElementById('detailsTaskCreator').textContent = task.creator?.full_name || 'System';
    document.getElementById('detailsTaskStatus').textContent = task.status;
    document.getElementById('detailsTaskPriority').textContent = task.priority;
    document.getElementById('detailsTaskVisibility').textContent = task.visibility || 'public';
    document.getElementById('detailsTaskCategory').textContent = task.category || 'General';
    document.getElementById('detailsTaskStart').textContent = task.start_date || 'Not set';
    document.getElementById('detailsTaskDue').textContent = task.due_date || 'Not set';
    document.getElementById('detailsTaskEnd').textContent = task.end_date || 'Not set';
    document.getElementById('detailsTaskEstimate').textContent = task.estimated_time || 'Not set';
    
    const list = document.getElementById('taskCommentsList');
    list.innerHTML = '<div style="text-align: center; color: var(--color-text-secondary);">Loading comments...</div>';
    
    document.getElementById('taskSidePanel').classList.add('active');
    document.getElementById('taskSidePanelOverlay').classList.add('active');
    
    const comments = await db.fetchTaskComments(task.id);
    if (comments.length === 0) {
        list.innerHTML = '<div style="color: var(--color-text-secondary); font-style: italic;">No comments yet.</div>';
    } else {
        list.innerHTML = comments.map(c => `
            <div style="background: rgba(0,0,0,0.1); padding: 0.75rem; border-radius: 6px; border: 1px solid var(--color-border);">
                <div style="display: flex; justify-content: space-between; margin-bottom: 0.25rem;">
                    <strong>${escapeHTML(c.user?.full_name || 'Unknown User')}</strong>
                    <span style="font-size: 0.75rem; color: var(--color-text-secondary);">${new Date(c.created_at).toLocaleString()}</span>
                </div>
                <div>${escapeHTML(c.content)}</div>
            </div>
        `).join('');
    }
};

window.handleTaskCommentSubmit = async function(e) {
    e.preventDefault();
    const id = document.getElementById('detailsTaskId').value;
    const input = document.getElementById('taskCommentInput');
    const content = input.value;
    if (!content.trim() || !id) return;
    
    input.disabled = true;
    const { success } = await db.addTaskComment(id, currentUser.id, content);
    input.disabled = false;
    
    if (success) {
        input.value = '';
        // Reload comments
        openTaskDetailsModal(id);
    } else {
        showToast("Failed to post comment", "danger");
    }
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
            profilesMap[p.id] = p.full_name || 'Unknown User';
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
                        <select id="leaveType" class="form-control" required>
                            <option value="Annual Leave">${t('annual_leave')}</option>
                            <option value="Sick Leave">${t('sick_leave')}</option>
                            <option value="Unpaid Leave">${t('unpaid_leave')}</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('start_date')}</label>
                        <input id="leaveStart" type="date" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('end_date')}</label>
                        <input id="leaveEnd" type="date" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('reason')}</label>
                        <textarea id="leaveReason" class="form-control" required></textarea>
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
        showToast("Please upload a receipt.", "warning");
        return;
    }

    const file = fileInput.files[0];
    const reader = new FileReader();
    reader.onload = async function (event) {
        const base64Url = event.target.result;
        const { success } = await db.submitExpense(currentUser.id, amount, description, base64Url);
        if (success) {
            showToast("Expense submitted for approval.", "success");
            renderView('expenses');
        } else {
            showToast("Error submitting expense.", "danger");
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
                    <div class="form-group" style="grid-column: 1 / -1;">
                    <label>${t('task_desc')}</label>
                    <textarea id="editTaskDesc" class="form-control" rows="4">${task.description || ''}</textarea>
                </div>
            </div>
            <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 1.5rem;">
                <button type="button" class="btn btn-icon" style="color:var(--color-danger); display:flex; gap:0.5rem; align-items:center;" onclick="handleDeleteTask('${id}')">
                    <i data-lucide="trash-2"></i> ${t('delete') || 'Delete'}
                </button>
                <div style="display: flex; gap: 1rem;">
                    <button type="button" class="btn-secondary" onclick="document.getElementById('editTaskModal').classList.remove('active')">${t('cancel')}</button>
                    <button type="button" class="btn-primary" onclick="handleSaveTask('${id}')">${t('save_task') || 'Save Task'}</button>
                </div>
            </div>
        </form>
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
    alert(`SAP Detailed Payslip for ${month}\n------------------------\nBase Salary: $${(netPay * 0.8).toFixed(2)}\nAllowances: $${(netPay * 0.2).toFixed(2)}\n\nNet Pay: $${netPay.toFixed(2)}`);
}

// Render Payroll
async function renderPayroll() {
    const payrolls = await db.fetchPayroll(currentUser?.id);
    let rowsHTML = payrolls.map(p => `
        <tr style="cursor: pointer;" onclick="handleViewPayslip('${p.month_year}', ${p.net_pay})">
            <td><strong>${p.month_year}</strong></td>
            <td>$${p.net_pay.toFixed(2)}</td>
            <td><span class="status-badge ${p.status === 'PAID' ? 'success' : 'info'}">${p.status}</span></td>
            <td><button class="btn-secondary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem;">${t('pay_view_det')}</button></td>
        </tr>
    `).join('');

    let totalNet = payrolls.length > 0 ? payrolls[0].net_pay.toFixed(2) : '0.00';
    let extras = payrolls.length > 0 ? payrolls[0].overtime_pay.toFixed(2) : '0.00';
    let base = payrolls.length > 0 ? (payrolls[0].net_pay - payrolls[0].overtime_pay).toFixed(2) : '0.00';

    if (payrolls.length === 0) {
        rowsHTML = `<tr><td colspan="4" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">${t('pay_no_slips')}</td></tr>`;
    }

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('nav_payroll')}</h1>
                <p class="page-subtitle">${t('salary_sub')}</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-4" style="background: linear-gradient(135deg, #0b192c, #1a365d); color: white; border: none;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem;">
                    <h3 style="color: rgba(255,255,255,0.8); margin: 0;">${t('pay_latest')}</h3>
                    <i data-lucide="file-text" style="color: rgba(255,255,255,0.5);"></i>
                </div>
                <h1 style="font-size: 3rem; margin-bottom: 0.5rem;">$${totalNet}</h1>
                <div style="display: flex; justify-content: space-between; border-top: 1px solid rgba(255,255,255,0.1); padding-top: 1rem; margin-top: 1rem;">
                    <div>
                        <div style="font-size: 0.75rem; color: rgba(255,255,255,0.6);">${t('pay_base')}</div>
                        <div>$${base}</div>
                    </div>
                    <div style="text-align: right;">
                        <div style="font-size: 0.75rem; color: rgba(255,255,255,0.6);">${t('pay_extras')}</div>
                        <div style="color: var(--color-success);">+$${extras}</div>
                    </div>
                </div>
            </div>
            <div class="card col-span-8">
                <div class="card-title">${t('recent_payslips')}</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>${t('month')}</th>
                                <th>${t('net_pay')}</th>
                                <th>${t('req_status')}</th>
                                <th>${t('pay_actions')}</th>
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

// Render Admin Hub
async function renderAdmin() {
    if (currentUserRole !== 'ADMIN' && currentUserRole !== 'MANAGER') {
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
    const email = document.getElementById('newEmail').value;
    const password = document.getElementById('newPassword').value;
    const role = document.getElementById('newRole').value;
    const jobTitle = document.getElementById('newJobTitle').value;
    const fullName = document.getElementById('newFullName').value;
    const iqama = document.getElementById('newIqama').value;
    const phone = document.getElementById('newPhone').value;

    const { error } = await db.createUser(email, password, role, jobTitle, fullName, iqama, phone);
    if (!error) {
        showToast("User created successfully!", 'success');
        if (typeof closeAddUserModal === 'function') closeAddUserModal();
        renderView('users');
    } else {
        showToast(error.message || "Failed to create user", 'danger');
    }
}

window.handleChangeRole = async function (id, role) {
    const { success } = await db.updateUserRole(id, role);
    if (success) {
        showToast("Role updated", "success");
        renderView('users');
    }
}

window.handleChangeJobTitle = async function (id, jobTitle) {
    const { success } = await db.updateUserJobTitle(id, jobTitle);
    if (success) {
        showToast("Job title updated", "success");
    } else {
        showToast("Failed to update job title", "danger");
    }
}

async function renderUsers() {
    if (currentUserRole !== 'ADMIN') return '<div style="padding: 2rem;">Unauthorized</div>';

    const users = await db.fetchUsers();

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('nav_users')}</h1>
                <p class="page-subtitle">${t('users_sub')}</p>
            </div>
            <button class="btn-primary" onclick="showAddUserModal()">
                <i data-lucide="user-plus"></i> ${t('users_add_new')}
            </button>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-12">
                <div class="card-title">${t('users_dir')}</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>${t('users_details')}</th>
                                <th>${t('users_role')}</th>
                                <th>${t('users_job_title')}</th>
                                <th>${t('users_assign_role')}</th>
                                <th>${t('users_assign_mgr')}</th>
                                <th>${t('users_contract')}</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${users.map(u => `
                                <tr>
                                    <td>
                                        <div style="font-weight: bold; color: var(--primary-color);">EMP-${u.emp_index || 'New'}</div>
                                        <div style="font-weight: bold;">${u.full_name || 'N/A'}</div>
                                        <div style="font-size: 0.8rem; color: var(--text-light);">
                                            ID: <span title="${u.id}">${u.id.substring(0, 8)}...</span><br/>
                                            Iqama: ${u.iqama_number || 'N/A'}<br/>
                                            Phone: ${u.phone_number || 'N/A'}
                                        </div>
                                    </td>
                                    <td><span class="status-badge ${u.role === 'ADMIN' ? 'success' : 'info'}">${u.role}</span></td>
                                    <td>
                                        <input type="text" autocomplete="off" class="form-control" style="width: 160px; padding: 0.25rem; font-size: 0.8rem;" value="${u.job_title || ''}" placeholder="${t('users_job_title')}" onblur="handleChangeJobTitle('${u.id}', this.value)">
                                    </td>
                                    <td>
                                        <select class="form-control" style="width: auto; padding: 0.25rem;" onchange="handleChangeRole('${u.id}', this.value)">
                                            <option value="EMPLOYEE" ${u.role === 'EMPLOYEE' ? 'selected' : ''}>${t('users_role_emp')}</option>
                                            <option value="MANAGER" ${u.role === 'MANAGER' ? 'selected' : ''}>${t('users_role_mgr')}</option>
                                            <option value="ADMIN" ${u.role === 'ADMIN' ? 'selected' : ''}>${t('users_role_admin')}</option>
                                        </select>
                                    </td>
                                    <td>
                                        <select class="form-control" style="width: auto; padding: 0.25rem;" onchange="handleAssignManager('${u.id}', this.value)">
                                            <option value="">${t('users_no_mgr')}</option>
                                            ${users.filter(m => m.role === 'MANAGER' || m.role === 'ADMIN').map(m => `<option value="${m.id}" ${u.manager_id === m.id ? 'selected' : ''}>${m.full_name || 'Mgr'}</option>`).join('')}
                                        </select>
                                    </td>
                                    <td>
                                        <button class="btn-secondary" style="padding: 0.4rem 0.8rem; font-size: 0.8rem;" onclick="navigateToContract('${u.id}', '${(u.full_name || 'Employee').replace(/'/g, "\\'")}')">
                                            <i data-lucide="file-signature" style="width:14px;height:14px;margin-right:4px;"></i> ${t('users_contract')}
                                        </button>
                                    </td>
                                    <td>
                                        <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
                                            <button class="btn-secondary" style="padding: 0.4rem; font-size: 0.8rem;" onclick="showEditUserModal('${u.id}')" title="Edit User">
                                                <i data-lucide="edit" style="width:14px;height:14px;"></i>
                                            </button>
                                            <button class="btn-secondary" style="padding: 0.4rem; font-size: 0.8rem; color: var(--color-warning);" onclick="handleResetUserPassword('${u.id}')" title="Unlock & Reset Password">
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

window.showAddUserModal = () => {
    document.getElementById('addUserForm').reset();
    document.getElementById('addUserModal').classList.add('show');
    if (window.lucide) window.lucide.createIcons();
};

window.closeAddUserModal = () => {
    document.getElementById('addUserModal').classList.remove('show');
};


window.handleAssignManager = async function (id, managerId) {
    const { success } = await db.assignManager(id, managerId);
    if (success) {
        showToast("Manager assigned", "success");
        renderView('users');
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
                    <span><i data-lucide="award" style="margin-right:8px; width:20px; height:20px; vertical-align:middle; color:var(--color-accent);"></i>Employee Performance Report</span>
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

window.generatePerformanceReport = async function() {
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

    // Compute score: (done / total * 100) - (overdue * 5 penalty), clamped 0–100
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
        const medal = i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : `#${i + 1}`;
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
                        <th>Role</th>
                        <th>Total Tasks</th>
                        <th>Completed</th>
                        <th>Overdue</th>
                        <th style="min-width:160px;">Completion Rate</th>
                        <th>Score</th>
                        <th>Rating</th>
                    </tr>
                </thead>
                <tbody>${rows}</tbody>
            </table>
        </div>
        <p style="font-size:0.75rem; color:var(--color-text-secondary); margin-top:1rem; padding-top:0.5rem; border-top:1px solid var(--color-border);">
            <i data-lucide="info" style="width:13px;height:13px;vertical-align:middle;margin-right:4px;"></i>
            Score = Completion Rate − (Overdue Tasks × 5 penalty points). Clamped between 0 and 100.
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
        <h2 style="color: #0000FF; margin-top: 0; text-align: center;">Employee Performance Report</h2>
        <p style="text-align: center; color: #666; margin-bottom: 30px;">
            <small>Generated: ${new Date().toLocaleString()}</small>
        </p>
        ${printNode.innerHTML}
        <br>
        <p style="text-align: right; margin-top: 40px;"><small style="color: #666;">Printed on ${new Date().toLocaleString()}</small></p>
    `;

    window.printWithLetterhead('Employee Performance Report', printContents);
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
        showToast("Document requested", "success");
        renderView('documents');
    }
}

window.handleEmployeeDocUpload = async function (e) {
    e.preventDefault();
    const docType = document.getElementById('empDocType').value;
    const fileInput = document.getElementById('empDocFile');
    if (!fileInput.files || fileInput.files.length === 0) return;

    const file = fileInput.files[0];
    const docName = file.name;
    const reader = new FileReader();
    reader.onload = async function (event) {
        const base64Url = event.target.result;
        const { success } = await db.uploadEmployeeDocument(currentUser.id, docName, docType, base64Url);
        if (success) {
            showToast("Document uploaded successfully!", "success");
            renderView('documents');
        } else {
            showToast("Error uploading document.", "danger");
        }
    };
    reader.readAsDataURL(file);
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

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('nav_documents')}</h1>
                <p class="page-subtitle">${t('doc_sub')}</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <!-- Upload Official Document -->
            <div class="card col-span-4">
                <div class="card-title">${t('doc_upload_title')}</div>
                <form autocomplete="off" onsubmit="handleEmployeeDocUpload(event)">
                    <div class="form-group">
                        <label class="form-label">${t('doc_type')}</label>
                        <select id="empDocType" class="form-control">
                            <option value="Passport">${t('doc_type_passport')}</option>
                            <option value="Iqama">${t('doc_type_iqama')}</option>
                            <option value="Contract">${t('doc_type_contract')}</option>
                            <option value="Certificate">${t('doc_type_cert')}</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('doc_file')}</label>
                        <input type="file" id="empDocFile" accept="image/*,application/pdf" class="form-control" required>
                    </div>
                    <button type="submit" class="btn-primary" style="width: 100%;">${t('doc_upload_btn')}</button>
                </form>
            </div>
            
            <div class="card col-span-8">
                <div class="card-title">${currentUserRole === 'ADMIN' ? t('doc_all_uploaded') : t('doc_my_uploaded')}</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead><tr><th>${t('req_type')}</th><th>${t('doc_file_name')}</th><th>${t('date')}</th><th>${t('pay_actions')}</th></tr></thead>
                        <tbody>
                            ${uploadedDocs.length === 0 ? `<tr><td colspan="4" style="text-align: center; color: var(--color-text-secondary); padding: 1rem;">${t('doc_no_uploaded')}</td></tr>` : uploadedDocs.map(d => `
                                <tr>
                                    <td><span class="status-badge info">${d.doc_type}</span></td>
                                    <td>${d.doc_name}</td>
                                    <td>${new Date(d.created_at).toLocaleDateString()}</td>
                                    <td><a href="${d.doc_base64}" download="${d.doc_name}" class="btn-secondary" style="padding: 0.25rem 0.5rem; text-decoration: none; font-size: 0.75rem;">${t('exp_download')}</a></td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- HR Letter Requests -->
            <div class="card col-span-4">
                <div class="card-title">${t('doc_req_letter')}</div>
                <form autocomplete="off" onsubmit="handleDocSubmit(event)">
                    <div class="form-group">
                        <label class="form-label">${t('doc_type')}</label>
                        <select id="docType" class="form-control">
                            <option value="Salary Certificate">${t('doc_type_salary')}</option>
                            <option value="NOC">${t('doc_type_noc')}</option>
                            <option value="Employment Letter">${t('doc_type_emp')}</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label class="form-label">${t('doc_purpose')}</label>
                        <textarea id="docPurpose" class="form-control" required></textarea>
                    </div>
                    <button type="submit" class="btn-secondary" style="width: 100%;">${t('doc_submit_req')}</button>
                </form>
            </div>
            <div class="card col-span-8">
                <div class="card-title">${currentUserRole === 'ADMIN' ? t('doc_all_reqs') : t('doc_my_reqs')}</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead><tr><th>${t('req_type')}</th><th>${t('doc_purpose')}</th><th>${t('req_status')}</th><th>${t('date')}</th></tr></thead>
                        <tbody>
                            ${docs.length === 0 ? `<tr><td colspan="4" style="text-align: center; color: var(--color-text-secondary); padding: 1rem;">${t('doc_no_reqs')}</td></tr>` : docs.map(d => `
                                <tr>
                                    <td>${d.doc_type}</td>
                                    <td>${d.purpose.substring(0, 30)}...</td>
                                    <td><span class="status-badge ${d.status === 'PENDING' ? 'warning' : (d.status.startsWith('REJECTED') ? 'danger' : 'success')}">${d.status.replace('_ARCHIVED', '')}</span></td>
                                    <td>${new Date(d.created_at).toLocaleDateString()}</td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    `;
}

// --- NEW VIEWS: PROFILE & TASKS ---
// ==========================================
// Messages (New)
// ==========================================
let currentChatUser = null;
let messagePollingInterval = null;

async function renderMessages() {
    const users = await db.fetchAllProfiles();

    // Clear old polling if exists
    if (messagePollingInterval) clearInterval(messagePollingInterval);

    // Build user list (excluding self)
    const otherUsers = users.filter(u => u.id !== currentUser.id);
    let usersHtml = otherUsers.map(u => `
        <div class="chat-user-item" onclick="window.selectChatUser('${u.id}', '${u.full_name}')" style="padding: 1rem; border-bottom: 1px solid var(--color-border); cursor: pointer; display: flex; align-items: center; gap: 10px;">
            <img src="${u.avatar_url || 'https://ui-avatars.com/api/?name=' + encodeURIComponent(u.full_name) + '&background=007AFF&color=fff'}" class="avatar" style="width: 40px; height: 40px;">
            <div>
                <div style="font-weight: 600;">${u.full_name}</div>
                <div style="font-size: 0.75rem; color: var(--color-text-secondary);">${u.role}</div>
            </div>
        </div>
    `).join('');

    if (otherUsers.length === 0) usersHtml = `<div style="padding: 1rem; color: var(--color-text-secondary);">${t('msg_no_other')}</div>`;

    return `
        <div class="page-header">
            <h2>${t('msg_title')}</h2>
        </div>
        <div class="card" style="display: flex; height: 600px; padding: 0; overflow: hidden;">
            <!-- Sidebar -->
            <div style="width: 300px; border-right: 1px solid var(--color-border); overflow-y: auto; background: var(--color-background);">
                ${usersHtml}
            </div>
            <!-- Chat Area -->
            <div style="flex: 1; display: flex; flex-direction: column;" id="chatArea">
                <div style="flex: 1; display: flex; justify-content: center; align-items: center; color: var(--color-text-secondary);">
                    ${t('msg_select')}
                </div>
            </div>
        </div>
    `;
}

window.selectChatUser = async function (userId, userName) {
    currentChatUser = { id: userId, name: userName };
    const chatArea = document.getElementById('chatArea');
    if (!chatArea) return;

    chatArea.innerHTML = `
        <div style="padding: 1rem; border-bottom: 1px solid var(--color-border); font-weight: 600; display: flex; align-items: center; gap: 10px; background: var(--color-surface);">
            <span>${t('msg_chat_with')} ${userName}</span>
            <button class="btn-secondary" style="padding: 0.2rem 0.5rem; font-size: 0.75rem; margin-left: auto;" onclick="window.refreshMessages()">${t('msg_refresh')}</button>
        </div>
        <div id="messageHistory" style="flex: 1; overflow-y: auto; padding: 1rem; display: flex; flex-direction: column; gap: 10px; background: var(--color-background);">
            <div style="text-align:center; color:var(--color-text-secondary);">${t('msg_loading')}</div>
        </div>
        <div style="padding: 1rem; border-top: 1px solid var(--color-border); display: flex; gap: 10px; background: var(--color-surface);">
            <input type="text" id="messageInput" class="form-control" placeholder="${t('msg_type_ph')}" style="flex: 1;" onkeypress="if(event.key === 'Enter') window.sendChatMessage()">
            <button class="btn-primary" onclick="window.sendChatMessage()">${t('msg_send')}</button>
        </div>
    `;

    await window.refreshMessages();

    // Set up basic polling every 10 seconds
    if (messagePollingInterval) clearInterval(messagePollingInterval);
    messagePollingInterval = setInterval(() => window.refreshMessages(true), 10000);
}

window.refreshMessages = async function (isPolling = false) {
    if (!currentChatUser) return;
    const historyContainer = document.getElementById('messageHistory');
    if (!historyContainer) return;

    const messages = await db.fetchMessageHistory(currentUser.id, currentChatUser.id);

    if (messages.length === 0) {
        historyContainer.innerHTML = `<div style="text-align:center; color:var(--color-text-secondary); margin-top: 2rem;">${t('msg_no_msgs')}</div>`;
        return;
    }

    let isAtBottom = historyContainer.scrollHeight - historyContainer.scrollTop <= historyContainer.clientHeight + 50;

    historyContainer.innerHTML = messages.map(m => {
        const isMine = m.sender_id === currentUser.id;
        return `
            <div style="align-self: ${isMine ? 'flex-end' : 'flex-start'}; max-width: 70%; background: ${isMine ? 'var(--color-primary)' : 'var(--color-surface)'}; color: ${isMine ? 'white' : 'var(--color-text)'}; padding: 0.75rem 1rem; border-radius: var(--radius-md); box-shadow: var(--shadow-sm); border: ${isMine ? 'none' : '1px solid var(--color-border)'};">
                <div style="margin-bottom: 0.25rem;">${escapeHTML(m.content)}</div>
                <div style="font-size: 0.7rem; opacity: 0.7; text-align: right;">${new Date(m.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</div>
            </div>
        `;
    }).join('');

    if (!isPolling || isAtBottom) {
        historyContainer.scrollTop = historyContainer.scrollHeight;
    }
}

window.sendChatMessage = async function () {
    if (!currentChatUser) return;
    const input = document.getElementById('messageInput');
    const content = input.value.trim();
    if (!content) return;

    input.value = '';
    const { success, error } = await db.sendMessage(currentUser.id, currentChatUser.id, content);
    if (success) {
        await window.refreshMessages();
    } else {
        showToast("Failed to send message.", "danger");
    }
}

async function renderProfile() {
    const profile = await db.getUserProfile(currentUser.id);
    const avatar = profile.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(currentUser.email.split('@')[0])}&background=007AFF&color=fff`;
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
                <h3 style="font-size: 1.25rem; font-weight: 600; margin-bottom: 0.25rem;">${profile.full_name || currentUser.email.split('@')[0]}</h3>
                <p style="color: var(--color-primary); font-weight: 500; margin-bottom: 1.5rem;">${currentUserRole}</p>
                <form autocomplete="off" onsubmit="handleUpdateProfilePhoto(event)" style="margin-bottom: 1rem; padding-top: 1rem; border-top: 1px solid var(--color-border);">
                    <div class="form-group" style="text-align: left;">
                        <label class="form-label" style="font-size: 0.85rem;">${t('prof_update_pic')}</label>
                        <input type="file" id="avatarFile" accept="image/*" class="form-control" style="font-size: 0.85rem;" required>
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
                                <label class="form-label">${t('prof_fn')}</label>
                                <input type="text" id="profileFullName" class="form-control" value="${profile.full_name || ''}" placeholder="${t('users_fn_ph')}">
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

                <div class="card">
                    <div class="card-title">${t('prof_security')}</div>
                    <form autocomplete="off" onsubmit="handleUpdatePassword(event)" style="display: flex; gap: 1rem; align-items: flex-end;">
                        <div class="form-group" style="flex: 1; margin-bottom: 0; position: relative;">
                            <label class="form-label">${t('prof_new_pass')}</label>
                            <input type="password" autocomplete="new-password" id="newPassword" class="form-control" placeholder="${t('prof_new_pass_ph')}" required minlength="6" style="padding-right: 40px;">
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
        const base64Url = event.target.result;
        const { success, error } = await db.updateProfilePhoto(currentUser.id, base64Url);
        if (success) {
            showToast("Profile photo updated!", "success");
            document.getElementById('topbarAvatar').src = base64Url;
            renderView('profile');
        } else {
            showToast("Error updating photo.", "danger");
        }
    };
    reader.readAsDataURL(file);
}

window.handleUpdatePassword = async function (e) {
    e.preventDefault();
    const newPwd = document.getElementById('newPassword').value;
    const { success, error } = await db.updateUserPassword(newPwd);
    if (success) {
        showToast("Password updated successfully!", "success");
        document.getElementById('newPassword').value = '';
    } else {
        showToast(error?.message || "Error updating password.", "danger");
    }
}

window.handleUpdateProfileDetails = async function (e) {
    e.preventDefault();
    const fullName = document.getElementById('profileFullName').value;
    const iqama = document.getElementById('profileIqama').value;
    const phone = document.getElementById('profilePhone').value;

    const { success, error } = await db.updateUserProfileDetails(currentUser.id, fullName, iqama, phone);
    if (success) {
        showToast("Profile details updated successfully!", "success");
        renderView('profile');

        // Update topbar silently
        const profile = await db.getUserProfile(currentUser.id);
        updateTopbarProfile(profile);
    } else {
        showToast(error?.message || "Error updating profile details.", "danger");
    }
}

window.currentTaskView = window.currentTaskView || 'list';
window.switchTaskView = function(view) {
    window.currentTaskView = view;
    
    // Client-side toggle without re-rendering the whole page
    const listBtn = document.getElementById('btn-view-list');
    const boardBtn = document.getElementById('btn-view-board');
    const listView = document.getElementById('tasks-view-list');
    const boardView = document.getElementById('tasks-view-board');
    
    if (listBtn && boardBtn && listView && boardView) {
        if (view === 'list') {
            listBtn.classList.add('active');
            boardBtn.classList.remove('active');
            listView.style.display = 'block';
            boardView.style.display = 'none';
        } else {
            boardBtn.classList.add('active');
            listBtn.classList.remove('active');
            boardView.style.display = 'block';
            listView.style.display = 'none';
        }
    } else {
        // Fallback just in case
        renderView('tasks');
    }
};

async function renderTasks() {
    console.log("renderTasks: Starting...");
    let tasksPromise;
    if (currentUserRole === 'ADMIN' || ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR')) {
        tasksPromise = db.fetchTasks(); 
    } else {
        tasksPromise = db.fetchTasks(currentUser.id);
    }
    
    console.log("renderTasks: Fetching users and tasks...");
    // Fetch users and tasks in parallel
    const [allUsers, fetchedTasks] = await Promise.all([
        db.fetchUsers(),
        tasksPromise
    ]);
    console.log("renderTasks: Fetched users and tasks.", { usersCount: allUsers.length, tasksCount: fetchedTasks.length });
    let tasks = fetchedTasks;

    if (((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR')) {
        let teamIds = allUsers.filter(u => u.manager_id === currentUser.id).map(u => u.id);
        teamIds.push(currentUser.id);
        tasks = tasks.filter(t => teamIds.includes(t.assignee_id) || t.created_by === currentUser.id);
    }

    window.taskCache = {};
    window.taskAssigneeOptionsCache = ''; // Default empty string

    // Normalize status and add relationships manually
    tasks = tasks.map(t => {
        const assignee = allUsers.find(u => u.id === t.assignee_id);
        const creator = allUsers.find(u => u.id === t.created_by);
        
        let displayTitle = t.title;
        if (t.title_i18n && typeof t.title_i18n === 'object') {
             displayTitle = t.title_i18n[currentLang] || t.title_i18n['en'] || t.title;
        }

        const taskObj = {
            ...t, 
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

    // Filter by visibility
    tasks = tasks.filter(t => {
        if (currentUserRole === 'ADMIN') return true;
        if (t.created_by === currentUser.id || t.assignee_id === currentUser.id) return true;
        if (t.visibility === 'private') return false;
        if (t.visibility === 'team') {
            let teamIds = allUsers.filter(u => u.manager_id === currentUser.id).map(u => u.id);
            teamIds.push(currentUser.id);
            return teamIds.includes(t.assignee_id) || teamIds.includes(t.created_by);
        }
        return true; // public
    });

    const pending = tasks.filter(t => t.status === 'Pending Approval');
    const todo = tasks.filter(t => t.status === 'todo' || t.status === 'Approved' || t.status === 'Rejected');
    const inProgress = tasks.filter(t => t.status === 'in_progress');
    const review = tasks.filter(t => t.status === 'review');
    const done = tasks.filter(t => t.status === 'completed');

    console.log("renderTasks: Fetching projects...");
    const projects = await db.fetchProjects(currentUser.id);
    console.log("renderTasks: Fetched projects.", { projectsCount: projects.length });
    const projectOptions = projects.map(p => `<option value="${p.id}">${p.project_name}</option>`).join('');
    window.projectOptionsCache = projectOptions;
    window.projectsCache = projects;

    let adminForm = '';
    let canCreateTask = true; // Allow all users to create tasks now
    
    let users = allUsers;
    if (((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR')) {
        users = users.filter(u => u.manager_id === currentUser.id || u.id === currentUser.id);
    }
    const userOptions = users.map(u => {
        const label = u.full_name || u.id.substring(0, 8);
        return `<option value="${u.id}">${label} (${u.role})</option>`;
    }).join('');
    window.taskAssigneeOptionsCache = userOptions;

    if (canCreateTask) {
        adminForm = `
            <div class="card col-span-12" style="margin-bottom: 1rem;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                    <div class="card-title" style="margin-bottom: 0;">${t('task_assign_new') || 'Create New Task'}</div>
                    <button class="btn btn-secondary btn-sm" onclick="toggleAITaskMode()"><i data-lucide="bot" style="width:16px; height:16px; margin-right:4px; vertical-align:text-bottom;"></i> AI Assist</button>
                </div>
                
                <!-- Standard Form -->
                <form autocomplete="off" onsubmit="handleCreateTask(event)" id="standardTaskForm" class="task-assign-form" style="display: flex; gap: 1rem; flex-wrap: wrap; align-items: flex-end;">
                    <div class="form-group" style="flex: 2; min-width: 200px; margin-bottom: 0;">
                        <label class="form-label">${t('task_title') || 'Task Title'}</label>
                        <input type="text" autocomplete="off" id="taskTitle" class="form-control" required placeholder="Task title">
                    </div>
                    <div class="form-group" style="flex: 1; min-width: 150px; margin-bottom: 0;">
                        <label class="form-label">Category</label>
                        <input type="text" id="taskCategory" class="form-control" placeholder="e.g. Design">
                    </div>
                    <div class="form-group" style="flex: 1; min-width: 120px; margin-bottom: 0;">
                        <label class="form-label">Priority</label>
                        <select id="taskPriority" class="form-control">
                            <option value="low">Low</option>
                            <option value="medium" selected>Medium</option>
                            <option value="high">High</option>
                            <option value="urgent">Urgent</option>
                        </select>
                    </div>
                    <div class="form-group" style="flex: 1; min-width: 150px; margin-bottom: 0;">
                        <label class="form-label">Project</label>
                        <select id="taskProject" class="form-control" onchange="handleTaskProjectChange('new')">
                            <option value="">No Project</option>
                            ${projectOptions}
                        </select>
                    </div>
                    <div class="form-group" style="flex: 1; min-width: 150px; margin-bottom: 0;">
                        <label class="form-label">${t('task_assign_to') || 'Assign To'}</label>
                        <select id="taskAssignee" class="form-control" onchange="handleTaskAssigneeChange('new')" required>
                            <option value="">${t('task_sel_emp') || 'Select Employee'}</option>
                            ${userOptions}
                        </select>
                    </div>
                    <div class="form-group" style="flex: 1; min-width: 150px; margin-bottom: 0;">
                        <label class="form-label">${t('task_due') || 'Due Date'}</label>
                        <input type="date" id="taskDue" class="form-control" required>
                    </div>
                    <!-- Conditional Designer Fields -->
                    <div id="newDesignFields" style="display: none; width: 100%; gap: 1rem; flex-wrap: wrap; margin-top: 0.5rem;">
                        <div class="form-group" style="flex: 1; min-width: 150px; margin-bottom: 0;">
                            <label class="form-label">Content Type</label>
                            <input type="text" id="taskContentType" class="form-control" placeholder="e.g. Graphic, Video">
                        </div>
                        <div class="form-group" style="flex: 1; min-width: 150px; margin-bottom: 0;">
                            <label class="form-label">Source Link</label>
                            <input type="url" id="taskSourceLink" class="form-control" placeholder="https://...">
                        </div>
                        <div class="form-group" style="flex: 1; min-width: 150px; margin-bottom: 0;">
                            <label class="form-label">Upload Link</label>
                            <input type="url" id="taskUploadLink" class="form-control" placeholder="https://...">
                        </div>
                    </div>
                    <div class="form-group task-assign-btn-group" style="margin-bottom: 0; width: 100%; text-align: right; margin-top: 0.5rem;">
                        <button type="submit" class="btn btn-primary">${t('task_assign_btn') || 'Create Task'}</button>
                    </div>
                </form>

                <!-- AI Form -->
                <form autocomplete="off" onsubmit="handleAICreateTask(event)" id="aiTaskForm" style="display: none; flex-direction: column; gap: 1rem;">
                    <div class="form-group" style="margin-bottom: 0;">
                        <label class="form-label"><i data-lucide="sparkles" style="color: var(--color-primary); width: 14px; height: 14px; margin-right:4px;"></i> Describe task naturally</label>
                        <input type="text" autocomplete="off" id="aiTaskInput" class="form-control" placeholder="e.g. 'Translate the homepage to French by Friday high priority for John'">
                    </div>
                    <button type="submit" class="btn btn-primary" style="align-self: flex-start;"><i data-lucide="zap" style="width:16px; height:16px; margin-right:4px; vertical-align:text-bottom;"></i> Generate & Assign</button>
                </form>
            </div>
        `;
    }

    function renderTaskCard(task) {
        let prioColor = 'var(--color-border)';
        if (task.priority === 'high') prioColor = 'var(--color-warning)';
        if (task.priority === 'urgent') prioColor = 'var(--color-danger)';
        
        return `
            <div class="card task-item-card" id="task-card-${task.id}" data-status="${task.status}" draggable="true" ondragstart="handleTaskDragStart(event, '${task.id}')" onclick="openTaskDetailsModal('${task.id}')" style="padding: 1rem; margin-bottom: 1rem; border-left: 4px solid ${prioColor}; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1); transition: opacity 0.2s; cursor: pointer; background: var(--color-surface); position: relative;">
                <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 0.5rem; padding-right: 2.5rem; gap: 0.5rem;">
                    <h4 style="margin: 0; font-size: 0.95rem; line-height: 1.4; color: var(--color-text); font-weight: 500; word-break: break-word;">${escapeHTML(task.displayTitle)}</h4>
                    ${task.category ? `<span class="badge" style="background: rgba(0,0,0,0.05); color: var(--color-text-secondary); font-size: 0.65rem; position: relative; top: -2px; flex-shrink: 0;">${escapeHTML(task.category)}</span>` : ''}
                </div>
                <button onclick="event.stopPropagation(); openEditTaskModal('${task.id}')" style="position: absolute; top: 1.25rem; right: 1rem; background: none; border: none; cursor: pointer; color: var(--color-text-secondary); padding: 0;" title="Edit Task"><i data-lucide="edit-2" style="width: 14px; height: 14px;"></i></button>
                <div style="font-size: 0.75rem; color: var(--color-text-secondary); margin-bottom: 0; display: flex; flex-direction: column; gap: 0.35rem;">
                    <div style="display: flex; align-items: center;"><i data-lucide="calendar" style="width: 12px; height: 12px; margin-right: 4px;"></i> Due: ${task.due_date || t('task_no_date') || 'No Date'}</div>
                    ${task.start_date ? `<div style="display: flex; align-items: center;"><i data-lucide="play" style="width: 12px; height: 12px; margin-right: 4px;"></i> Start: ${escapeHTML(task.start_date)}</div>` : ''}
                    <div style="display: flex; align-items: center;"><i data-lucide="user" style="width: 12px; height: 12px; margin-right: 4px;"></i> ${task.assignee?.full_name || t('task_unknown') || 'Unassigned'}</div>
                    ${task.estimated_time ? `<div style="display: flex; align-items: center;"><i data-lucide="clock" style="width: 12px; height: 12px; margin-right: 4px;"></i> Est: ${escapeHTML(task.estimated_time)}</div>` : ''}
                </div>
            </div>
        `;
    }

    const viewToggler = `
        <div class="task-view-toggler">
            <button id="btn-view-list" class="${window.currentTaskView === 'list' ? 'active' : ''}" onclick="switchTaskView('list')"><i data-lucide="list"></i> List View</button>
            <button id="btn-view-board" class="${window.currentTaskView === 'board' ? 'active' : ''}" onclick="switchTaskView('board')"><i data-lucide="kanban"></i> Board View</button>
        </div>
    `;

    let boardHTML = `
        <div id="tasks-view-board" class="col-span-12" style="display: ${window.currentTaskView === 'board' ? 'block' : 'none'};">
            <div class="task-board-wrapper" style="width: 100%; overflow-x: auto; padding-bottom: 1rem;">
                <div style="display: flex; gap: 1.5rem; min-width: 1400px;">
                    <div style="flex: 1; min-width: 280px;">
                        <div class="card" style="background: rgba(139, 92, 246, 0.02); height: 100%; border: 1px solid var(--color-border); border-top: 3px solid #8b5cf6;">
                            <div class="card-title" style="padding: 1rem 1rem 0;">Pending Approval <span id="badge-pending" class="badge" style="background: #8b5cf6; color: #fff;">${pending.length}</span></div>
                            <div id="col-pending" class="task-column" ondragover="handleTaskDragOver(event)" ondrop="handleTaskDrop(event, 'Pending Approval')" style="min-height: 400px; padding: 1rem; padding-bottom: 2rem; height: calc(100% - 30px);">
                                ${pending.map(renderTaskCard).join('')}
                            </div>
                        </div>
                    </div>
                    <div style="flex: 1; min-width: 280px;">
                        <div class="card" style="background: rgba(0,0,0,0.02); height: 100%; border: 1px solid var(--color-border); border-top: 3px solid var(--color-text-secondary);">
                            <div class="card-title" style="padding: 1rem 1rem 0;">${t('task_todo') || 'To Do'} <span id="badge-todo" class="badge" style="background: var(--color-text-secondary); color: #fff;">${todo.length}</span></div>
                            <div id="col-todo" class="task-column" ondragover="handleTaskDragOver(event)" ondrop="handleTaskDrop(event, 'todo')" style="min-height: 400px; padding: 1rem; padding-bottom: 2rem; height: calc(100% - 30px);">
                                ${todo.map(renderTaskCard).join('')}
                            </div>
                        </div>
                    </div>
                    <div style="flex: 1; min-width: 280px;">
                        <div class="card" style="background: rgba(59, 130, 246, 0.02); height: 100%; border: 1px solid var(--color-border); border-top: 3px solid var(--color-primary);">
                            <div class="card-title" style="padding: 1rem 1rem 0;">In Progress <span id="badge-in_progress" class="badge" style="background: var(--color-primary); color: #fff;">${inProgress.length}</span></div>
                            <div id="col-in_progress" class="task-column" ondragover="handleTaskDragOver(event)" ondrop="handleTaskDrop(event, 'in_progress')" style="min-height: 400px; padding: 1rem; padding-bottom: 2rem; height: calc(100% - 30px);">
                                ${inProgress.map(renderTaskCard).join('')}
                            </div>
                        </div>
                    </div>
                    <div style="flex: 1; min-width: 280px;">
                        <div class="card" style="background: rgba(245, 158, 11, 0.02); height: 100%; border: 1px solid var(--color-border); border-top: 3px solid var(--color-warning);">
                            <div class="card-title" style="padding: 1rem 1rem 0;">Review <span id="badge-review" class="badge" style="background: var(--color-warning); color: #fff;">${review.length}</span></div>
                            <div id="col-review" class="task-column" ondragover="handleTaskDragOver(event)" ondrop="handleTaskDrop(event, 'review')" style="min-height: 400px; padding: 1rem; padding-bottom: 2rem; height: calc(100% - 30px);">
                                ${review.map(renderTaskCard).join('')}
                            </div>
                        </div>
                    </div>
                    <div style="flex: 1; min-width: 280px;">
                        <div class="card" style="background: rgba(16, 185, 129, 0.02); height: 100%; border: 1px solid var(--color-border); border-top: 3px solid var(--color-success);">
                            <div class="card-title" style="padding: 1rem 1rem 0;">${t('task_done') || 'Done'} <span id="badge-completed" class="badge" style="background: var(--color-success); color: #fff;">${done.length}</span></div>
                            <div id="col-completed" class="task-column" ondragover="handleTaskDragOver(event)" ondrop="handleTaskDrop(event, 'completed')" style="min-height: 400px; padding: 1rem; padding-bottom: 2rem; height: calc(100% - 30px);">
                                ${done.map(renderTaskCard).join('')}
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    `;

    // List View Grouped by Category
    const categories = [...new Set(tasks.map(t => t.category || 'General'))].sort();
    
    let listHTML = `<div id="tasks-view-list" class="col-span-12" style="background: transparent; display: ${window.currentTaskView === 'list' ? 'block' : 'none'};">`;
    categories.forEach(cat => {
        const catTasks = tasks.filter(t => (t.category || 'General') === cat);
        listHTML += `<div class="task-list-group-header">${escapeHTML(cat)} <span class="badge" style="font-size: 0.75rem;">${catTasks.length}</span></div>`;
        
        if (catTasks.length === 0) {
            listHTML += `<div style="padding: 1rem; color: var(--color-text-secondary); font-style: italic;">No tasks</div>`;
        }
        
        catTasks.forEach(task => {
            let prioColor = 'var(--color-text-secondary)';
            if (task.priority === 'high') prioColor = 'var(--color-warning)';
            if (task.priority === 'urgent') prioColor = 'var(--color-danger)';
            
            let statusBadge = '';
            if(task.status === 'in_progress') statusBadge = '<span class="badge" style="background: var(--color-primary); color: white;">In Progress</span>';
            else if(task.status === 'review') statusBadge = '<span class="badge" style="background: var(--color-warning); color: white;">Review</span>';
            else if(task.status === 'completed') statusBadge = '<span class="badge" style="background: var(--color-success); color: white;">Done</span>';
            else if(task.status === 'Pending Approval') statusBadge = '<span class="badge" style="background: #8b5cf6; color: white;">Pending</span>';
            else if(task.status === 'Approved') statusBadge = '<span class="badge" style="background: #10b981; color: white;">Approved</span>';
            else if(task.status === 'Rejected') statusBadge = '<span class="badge" style="background: #ef4444; color: white;">Rejected</span>';
            else statusBadge = '<span class="badge">To Do</span>';
            
            listHTML += `
                <div class="task-list-row" onclick="openTaskDetailsModal('${task.id}')">
                    <div style="color: ${prioColor};" title="Priority: ${task.priority}">
                        <i data-lucide="alert-circle"></i>
                    </div>
                    <div class="task-title">
                        ${escapeHTML(task.displayTitle)}
                    </div>
                    <div class="task-meta">
                        <span style="width: 100px;">${statusBadge}</span>
                        <span style="width: 150px; display:flex; align-items:center; gap:4px;"><i data-lucide="user" style="width:14px;height:14px;"></i> ${task.assignee?.full_name || 'Unassigned'}</span>
                        <span style="width: 120px; display:flex; align-items:center; gap:4px;"><i data-lucide="calendar" style="width:14px;height:14px;"></i> ${task.due_date || 'No Date'}</span>
                        <button onclick="event.stopPropagation(); openEditTaskModal('${task.id}')" style="background:none; border:none; cursor:pointer; color:var(--color-text-secondary);" title="Edit"><i data-lucide="edit-2" style="width:14px;height:14px;"></i></button>
                    </div>
                </div>
            `;
        });
    });
    listHTML += `</div>`;

    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('nav_tasks') || 'Tasks'}</h1>
                <p class="page-subtitle">${t('task_sub') || 'Manage team tasks with AI assistance'}</p>
            </div>
        </div>
        ${viewToggler}
        <div class="dashboard-grid fade-in-up" style="grid-template-columns: repeat(12, 1fr);">
            ${adminForm}
            ${boardHTML}
            ${listHTML}
        </div>
    `;
}

window.toggleAITaskMode = function() {
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

window.handleAICreateTask = async function(e) {
    e.preventDefault();
    const input = document.getElementById('aiTaskInput').value;
    if (!input) return;
    
    // Very basic heuristic parser (mock AI)
    let priority = 'medium';
    if (input.toLowerCase().includes('high priority') || input.toLowerCase().includes('urgent')) priority = 'high';
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
    
    const { success } = await db.createTask(input, '', assigneeId, dueStr, currentUser.id, priority, 'Auto-parsed', {'en': input, 'ar': input + ' (مترجم)'}, {});
    if (success) {
        showToast("AI parsed and created task!", "success");
        await db.triggerWebhooks('task_created', { title: input, assignee_id: assigneeId, due_date: dueStr, priority: priority, is_ai_parsed: true });
        renderView('tasks');
    } else {
        showToast("Failed to create task", "danger");
    }
};

window.handleTaskProjectChange = function (prefix = 'new') {
    // We could filter tags based on the selected project, but for now we'll just log it.
};

window.handleTaskAssigneeChange = async function (prefix = 'new') {
    const assigneeId = document.getElementById('taskAssignee').value;
    const designFields = document.getElementById('newDesignFields');
    if (!assigneeId) {
        designFields.style.display = 'none';
        return;
    }

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

window.handleCreateTask = async function (e) {
    e.preventDefault();
    const title = document.getElementById('taskTitle').value;
    const assignee = document.getElementById('taskAssignee').value;
    const due = document.getElementById('taskDue').value;
    const priority = document.getElementById('taskPriority').value;
    const projectId = document.getElementById('taskProject').value || null;
    
    // Check if assignee is in Designing
    const assigneeObj = allUsers.find(u => u.id === assignee);
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
        contentType = document.getElementById('taskContentType').value || null;
        sourceLink = document.getElementById('taskSourceLink').value || null;
        uploadLink = document.getElementById('taskUploadLink').value || null;
    }

    // Default visibility if project is selected
    let visibleTo = [];
    if (projectId) {
        const proj = window.projectsCache.find(p => p.id === projectId);
        if (proj && proj.visible_to) {
            visibleTo = proj.visible_to;
        }
    }

    // Mock translation for title_i18n
    const titleI18n = {
        'en': title,
        'ar': title + ' (مترجم)' // mock arabic
    };

    const { success, error } = await db.createTask(title, '', assignee, due, currentUser.id, priority, 'General', titleI18n, {}, null, null, null, 'public', projectId, [], visibleTo, contentType, sourceLink, uploadLink, status);
    if (success) {
        showToast("Task created successfully!", "success");
        await db.triggerWebhooks('task_created', { title, assignee_id: assignee, due_date: due, priority, project_id: projectId });
        if (assignee && assignee !== currentUser.id) {
            await db.createNotification(assignee, `You have been assigned a new task: ${title}`);
        }
        if (status === 'Pending Approval') {
            const hussain = allUsers.find(u => u.full_name && u.full_name.toLowerCase().includes('hussain') || u.email && u.email.toLowerCase().includes('hussain'));
            if (hussain) {
                await db.createNotification(hussain.id, `A new task requires your approval: ${title}`);
            }
            showToast("Task sent to Hussain for approval", "info");
        }
        renderView('tasks');
    } else {
        showToast("Failed to create task: " + (error?.message || ''), "danger");
    }
};

window.handleUpdateTaskStatus = async function (id, status) {
    const { error } = await db.updateTaskStatus(id, status);
    if (error) {
        showToast(t('error_update_task') || "Failed to update task", "danger");
    } else {
        showToast(`Task updated`, "success");
        await db.triggerWebhooks('task_status_updated', { task_id: id, status: status });
    }
};

window.handleTaskDragStart = function(e, id) {
    e.dataTransfer.setData('text/plain', id);
    e.currentTarget.style.opacity = '0.5';
};

window.handleTaskDragOver = function(e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
};

window.handleTaskDrop = async function(e, status) {
    e.preventDefault();
    const id = e.dataTransfer.getData('text/plain');
    if (!id) return;
    
    const taskCard = document.getElementById(`task-card-${id}`);
    if (taskCard) {
        const currentStatus = taskCard.getAttribute('data-status');
        taskCard.style.opacity = '1';
        if (currentStatus === status) return; // No change
        
        // Prevent unauthorized dragging from or to Pending Approval
        const isHussain = currentUser.full_name && currentUser.full_name.toLowerCase().includes('hussain') || currentUser.email && currentUser.email.toLowerCase().includes('hussain');
        if ((currentStatus === 'Pending Approval' || status === 'Pending Approval') && currentUserRole !== 'ADMIN' && !isHussain) {
            showToast('You do not have permission to modify pending approval tasks', 'danger');
            return;
        }

        // Optimistic UI update
        const targetCol = document.getElementById(`col-${status}`);
        if (targetCol) {
            targetCol.appendChild(taskCard);
            taskCard.setAttribute('data-status', status);
            
            const oldBadge = document.getElementById(`badge-${currentStatus}`);
            const newBadge = document.getElementById(`badge-${status}`);
            if (oldBadge) oldBadge.textContent = Math.max(0, parseInt(oldBadge.textContent) - 1);
            if (newBadge) newBadge.textContent = parseInt(newBadge.textContent) + 1;
        }
    }
    
    await window.handleUpdateTaskStatus(id, status);
};

window.openEditTaskModal = function(id) {
    try {
        const task = window.taskCache[id];
        if (!task) {
            console.error('Task not found in cache for ID:', id);
            return;
        }
        
        document.getElementById('editTaskId').value = task.id;
        document.getElementById('editTaskTitle').value = task.title || '';
        document.getElementById('editTaskCategory').value = task.category || '';
        document.getElementById('editTaskPriority').value = task.priority || 'medium';
        
        const formatDate = (dateStr) => {
            if (!dateStr) return '';
            try { return new Date(dateStr).toISOString().split('T')[0]; } 
            catch(e) { return ''; }
        };
        
        document.getElementById('editTaskDue').value = formatDate(task.due_date);
        
        document.getElementById('editTaskVisibility').value = task.visibility || 'public';
        document.getElementById('editTaskStart').value = formatDate(task.start_date);
        document.getElementById('editTaskEnd').value = formatDate(task.end_date);
        document.getElementById('editTaskEstimate').value = task.estimated_time || '';
        
        const assigneeSelect = document.getElementById('editTaskAssignee');
        if (assigneeSelect) {
            assigneeSelect.innerHTML = window.taskAssigneeOptionsCache || '';
            assigneeSelect.value = task.assignee_id || '';
        }

        const projectSelect = document.getElementById('editTaskProject');
        if (projectSelect) {
            projectSelect.innerHTML = '<option value="">No Project</option>' + (window.projectOptionsCache || '');
            projectSelect.value = task.project_id || '';
        }

        document.getElementById('editTaskContentType').value = task.content_type || '';
        document.getElementById('editTaskSourceLink').value = task.source_link || '';
        document.getElementById('editTaskUploadLink').value = task.upload_link || '';

        // Trigger change to handle design fields display
        handleTaskAssigneeChange('edit');
        
        const modal = document.getElementById('editTaskModal');
        if (modal) {
            modal.classList.add('active');
        } else {
            console.error('editTaskModal not found in DOM');
            alert('Error: Edit Task Modal missing in HTML.');
        }
    } catch (err) {
        console.error('Error in openEditTaskModal:', err);
        alert('Error opening edit modal. Check console for details.');
    }
};

window.handleEditTaskSubmit = async function(e) {
    e.preventDefault();
    const id = document.getElementById('editTaskId').value;
    const title = document.getElementById('editTaskTitle').value;
    const category = document.getElementById('editTaskCategory').value;
    const priority = document.getElementById('editTaskPriority').value;
    const assigneeId = document.getElementById('editTaskAssignee').value;
    const dueDate = document.getElementById('editTaskDue').value;
    
    const visibility = document.getElementById('editTaskVisibility').value;
    const startDate = document.getElementById('editTaskStart').value;
    const endDate = document.getElementById('editTaskEnd').value;
    const estimate = document.getElementById('editTaskEstimate').value;
    const projectId = document.getElementById('editTaskProject').value || null;
    
    // Check Designer status
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
        category: category,
        priority: priority,
        assignee_id: assigneeId,
        due_date: dueDate,
        visibility: visibility,
        start_date: startDate || null,
        end_date: endDate || null,
        estimated_time: estimate || null,
        project_id: projectId
    };

    if (isDesigner) {
        updates.content_type = document.getElementById('editTaskContentType').value || null;
        updates.source_link = document.getElementById('editTaskSourceLink').value || null;
        updates.upload_link = document.getElementById('editTaskUploadLink').value || null;
    }

    if (projectId) {
        const proj = window.projectsCache.find(p => p.id === projectId);
        if (proj && proj.visible_to) {
            updates.visible_to = proj.visible_to;
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
        showToast("Failed to update task details", "danger");
    } else {
        showToast("Task updated successfully", "success");
        await db.triggerWebhooks('task_updated', { task_id: id, updates: updates });
        document.getElementById('editTaskModal').classList.remove('active');
        renderView('tasks');
    }
};

window.handleDeleteTask = async function(id) {
    if (!confirm(t('confirm_delete') || "Are you sure you want to delete this task?")) return;
    
    const { error } = await db.deleteTask(id);
    if (error) {
        showToast("Failed to delete task", "danger");
    } else {
        showToast("Task deleted successfully", "success");
        await db.triggerWebhooks('task_deleted', { task_id: id });
        document.getElementById('editTaskModal').classList.remove('active');
        renderView('tasks');
    }
};

document.addEventListener('dragend', function(e) {
    if (e.target && e.target.classList && e.target.classList.contains('task-item-card')) {
        e.target.style.opacity = '1';
    }
});

// Router
// ==========================================
// Employees & Contracts (HR View)
// ==========================================
window.navigateToContract = function (employeeId, empName) {
    currentContractEmployeeId = employeeId;
    currentContractEmployeeName = empName;
    currentView = 'contract';
    render();
}

window.handleSaveContract = async function (e) {
    e.preventDefault();
    const contractData = {
        employee_id: currentContractEmployeeId,
        contract_type: document.getElementById('contractType').value,
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
        status: document.getElementById('contractStatus').value
    };

    const { success, error } = await db.upsertContract(contractData);
    if (success) {
        showToast("Contract saved successfully", "success");
        currentView = 'users';
        render();
    } else {
        showToast(error?.message || "Failed to save contract", "danger");
    }
}

async function renderContractPage() {
    if (!currentContractEmployeeId) {
        return `<div class="card">${t('notif_no_found')}</div>`;
    }

    // Fetch existing contract
    const contract = await db.fetchContractByEmployeeId(currentContractEmployeeId);

    // Default values if no contract exists
    const contractType = contract?.contract_type || 'Full-time';
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

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('users_contract')}</h1>
                <p class="page-subtitle">${currentContractEmployeeName}</p>
            </div>
            <button class="btn-secondary" onclick="currentView='users'; render();">
                <i data-lucide="arrow-left" style="width:16px;height:16px;margin-right:4px;"></i> Back to Users
            </button>
        </div>

        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-12 md:col-span-8 md:col-start-3">
                <form autocomplete="off" onsubmit="handleSaveContract(event)">
                    <div class="dashboard-grid">
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_type')}</label>
                            <select id="contractType" class="form-control" required>
                                <option value="Full-time" ${contractType === 'Full-time' ? 'selected' : ''}>${t('contract_ft')}</option>
                                <option value="Part-time" ${contractType === 'Part-time' ? 'selected' : ''}>${t('contract_pt')}</option>
                                <option value="Contractor" ${contractType === 'Contractor' ? 'selected' : ''}>${t('contract_c')}</option>
                                <option value="Freelance" ${contractType === 'Freelance' ? 'selected' : ''}>${t('contract_fl')}</option>
                            </select>
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_status')}</label>
                            <select id="contractStatus" class="form-control" required>
                                <option value="Active" ${status === 'Active' ? 'selected' : ''}>${t('contract_active')}</option>
                                <option value="Terminated" ${status === 'Terminated' ? 'selected' : ''}>${t('contract_term')}</option>
                                <option value="Expired" ${status === 'Expired' ? 'selected' : ''}>${t('contract_exp')}</option>
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

                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_salary')}</label>
                            <input type="number" id="contractSalary" class="form-control" step="0.01" value="${salary}">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_housing')}</label>
                            <input type="number" id="contractHousing" class="form-control" step="0.01" value="${housing}">
                        </div>

                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_transport')}</label>
                            <input type="number" id="contractTransport" class="form-control" step="0.01" value="${transport}">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_other')}</label>
                            <input type="number" id="contractOther" class="form-control" step="0.01" value="${other}">
                        </div>

                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_hours')}</label>
                            <input type="text" id="contractHours" class="form-control" placeholder="e.g. 8 hours/day" value="${hours}">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_probation')}</label>
                            <input type="number" id="contractProbation" class="form-control" value="${probation}">
                        </div>

                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_notice')}</label>
                            <input type="number" id="contractNotice" class="form-control" value="${notice}">
                        </div>
                        <div class="form-group col-span-12 md:col-span-6">
                            <label class="form-label">${t('contract_leave')}</label>
                            <input type="number" id="contractLeave" class="form-control" value="${leave}">
                        </div>
                    </div>

                    <div style="display: flex; justify-content: flex-end; gap: 1rem; margin-top: 1.5rem; border-top: 1px solid var(--color-border); padding-top: 1.5rem;">
                        <button type="button" class="btn-secondary" onclick="currentView='users'; render();">${t('contract_cancel')}</button>
                        <button type="submit" class="btn-primary">${t('contract_save')}</button>
                    </div>
                </form>
            </div>
        </div>
    `;
}

async function renderEmployeesDirectory() {
    const users = await db.fetchUsers();

    // Directory is visible to everyone, but we only show basic info.

    // Only Admins or the Manager themselves can see team members' contracts
    // For now, let's allow ADMIN to see all, Manager to see their team
    let visibleUsers = users;
    if (currentUserRole === 'ADMIN') {
        visibleUsers = users;
    } else if ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR') {
        visibleUsers = users.filter(u => u.manager_id === currentUser.id || u.id === currentUser.id);
    } else {
        // Employees see themselves, their team members, and their manager
        visibleUsers = users.filter(u => 
            u.id === currentUser.id || 
            (currentUser.manager_id && u.manager_id === currentUser.manager_id) || 
            u.id === currentUser.manager_id
        );
    }

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('nav_emp_dir')}</h1>
                <p class="page-subtitle">${t('emp_dir_sub')}</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-12">
                <div class="card-title">${t('emp_dir_company')}</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>${t('time_emp_id')}</th>
                                <th>${t('emp_name')}</th>
                                <th>${t('emp_contact')}</th>
                                <th>${t('emp_role_title')}</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${visibleUsers.map(u => `
                                <tr>
                                    <td style="font-weight: bold; color: var(--color-primary);">EMP-${u.emp_index || '-'}</td>
                                    <td>
                                        <div style="font-weight: 600;">${u.full_name || t('emp_na')}</div>
                                    </td>
                                    <td>
                                        <div style="font-size: 0.85rem;">
                                            <i data-lucide="mail" style="width:12px;height:12px;margin-right:4px;vertical-align:middle;"></i> ${u.id}<br/>
                                            <i data-lucide="phone" style="width:12px;height:12px;margin-right:4px;vertical-align:middle;"></i> ${u.phone_number || t('emp_na')}<br/>
                                            <i data-lucide="credit-card" style="width:12px;height:12px;margin-right:4px;vertical-align:middle;"></i> ${u.iqama_number || t('emp_na')}
                                        </div>
                                    </td>
                                    <td>
                                        <span class="status-badge ${u.role === 'ADMIN' ? 'success' : (u.role === 'MANAGER' ? 'warning' : 'info')}">${u.role}</span><br/>
                                        <span style="font-size: 0.85rem; color: var(--text-light); margin-top: 4px; display: inline-block;">${u.job_title || t('emp_no_title')}</span>
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

window.viewHTMLCache = window.viewHTMLCache || {};

window.renderView = async function(viewId, isBack = false) {
    if (!viewId) return;
    if (viewId === 'null') {
        viewId = 'dashboard';
    }
    currentView = viewId;
    
    if (!currentUser && viewId !== 'login') {
        viewId = 'login';
        currentView = 'login';
    }

    if (viewId !== 'login') {
        localStorage.setItem('muqam_hr_last_view', viewId);
    }

    if (!isBack && viewId !== 'login') {
        if (viewHistory[viewHistory.length - 1] !== viewId) {
            viewHistory.push(viewId);
        }
    }

    // Reset history if we hit root views
    if (viewId === 'dashboard' || viewId === 'admin') {
        viewHistory = [viewId];
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
            case 'community': content = await renderCommunity(); break;
            case 'time': content = await renderTime(); break;
            case 'leave': content = await renderLeave(); break;
            case 'requests': content = await renderRequests(); break;
            case 'archived': content = await renderArchivedRequests(); break;
            case 'payroll': content = await renderPayroll(); break;
            case 'expenses': content = await renderExpenses(); break;
            case 'analytics': content = await renderAnalytics(); break;
            case 'admin': content = await renderAdmin(); break;
            case 'users': content = await renderUsers(); break;
            case 'employees': content = await renderEmployeesDirectory(); break;
            case 'messages': content = await renderMessages(); break;
            case 'notifications': content = await renderNotifications(); break;
            case 'performance': content = await renderPerformance(); break;
            case 'documents': content = await renderDocuments(); break;
            case 'profile': content = await renderProfile(); break;
            case 'projects': content = await renderProjects(); break;
            case 'approvals': content = await renderApprovals(); break;
            case 'tasks': content = await renderTasks(); break;
            case 'departments': content = await renderDepartments(); break;
            case 'clients': content = await renderClients(); break;
            case 'crm': content = await renderCRM(); break;
            case 'orders': content = await renderOrders(); break;
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
        content = `<div class="card" style="color:red; padding: 2rem;"><h3>Error Loading Page</h3><p>${err.message}</p><pre>${err.stack}</pre></div>`;
    }

    if (currentView === viewId || viewId === 'login') {
        window.viewHTMLCache[viewId] = content;
        // Always update the view with the fresh content!
        viewContainer.innerHTML = content;
        lucide.createIcons();
        if (viewId === 'analytics') setTimeout(initCharts, 100);
    } else {
        window.viewHTMLCache[viewId] = content;
    }
    
    // Toggle global back button
    const backBtn = document.getElementById('globalBackButton');
    if (backBtn) {
        if (viewHistory.length > 1 && viewId !== 'login') {
            backBtn.style.display = 'block';
        } else {
            backBtn.style.display = 'none';
        }
    }
}

function updateTopbarProfile(profile) {
    const avatarImg = document.getElementById('topbarAvatar');
    const nameSpan = document.getElementById('topbarName');
    const roleSpan = document.querySelector('.user-role');
    if (avatarImg) {
        avatarImg.src = profile.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(currentUser.email.split('@')[0])}&background=007AFF&color=fff`;
    }
    if (nameSpan) {
        nameSpan.textContent = currentUser.email.split('@')[0];
    }
    if (roleSpan) {
        roleSpan.textContent = profile.job_title || profile.role;
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
            <div class="card fade-in-up" style="margin-bottom: 1rem; ${!n.is_read ? 'border-left: 4px solid var(--color-primary); background: rgba(37,99,235,0.02);' : ''}">
                <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                    <div style="display: flex; gap: 1rem; align-items: center;">
                        <div style="width: 40px; height: 40px; border-radius: 50%; background: var(--color-surface); display: flex; align-items: center; justify-content: center; color: var(--color-primary);">
                            <i data-lucide="bell"></i>
                        </div>
                        <div>
                            <div style="font-weight: 500; font-size: 1rem; color: var(--color-text);">${n.message}</div>
                            <div style="font-size: 0.85rem; color: var(--color-text-secondary); margin-top: 0.25rem;">${new Date(n.created_at).toLocaleString()}</div>
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
                <div class="notification-item ${!n.is_read ? 'unread' : ''}" style="padding: 10px; border-bottom: 1px solid var(--color-border); ${!n.is_read ? 'background: rgba(var(--color-primary-rgb), 0.05); font-weight: 500;' : ''}">
                    <div style="font-size: 0.875rem;">${escapeHTML(n.message)}</div>
                    <div style="font-size: 0.75rem; color: var(--color-text-secondary); margin-top: 4px;">${new Date(n.created_at).toLocaleDateString()}</div>
                </div>
            `).join('');
        }
    }
}

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
        window.closeTaskSidePanel();
    }

    if (!e.target.closest('.profile-dropdown-wrapper')) {
        const dropdown = document.getElementById('profileDropdown');
        if (dropdown) dropdown.style.display = 'none';

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
    const departments = await db.fetchDepartments();
    const profiles = await db.fetchAllProfiles();
    
    let tableRows = departments.length ? departments.map(d => {
        const empCount = profiles.filter(p => p.department_id === d.id).length;
        return `
        <tr id="dept-row-${d.id}">
            <td>${d.name}</td>
            <td>${empCount}</td>
            <td>${profiles.find(p => p.id === d.head_id)?.full_name || '-'}</td>
            <td>
                <button class="btn btn-icon" onclick="editDepartment('${d.id}')"><i data-lucide="edit-2"></i></button>
                <button class="btn btn-icon" style="color:var(--color-danger);" onclick="deleteDepartment('${d.id}')"><i data-lucide="trash-2"></i></button>
            </td>
        </tr>
    `}).join('') : `<tr><td colspan="4" style="text-align:center;">No departments found</td></tr>`;

    return `
        <div class="page-header" style="display:flex; justify-content:space-between; align-items:center;">
            <div>
                <h1 class="page-title">Departments Management</h1>
                <p class="page-subtitle">Manage company departments.</p>
            </div>
            <button class="btn btn-primary" onclick="showDepartmentModal()">
                <i data-lucide="plus"></i> New Department
            </button>
        </div>
        
        <div class="card">
            <div class="table-responsive">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>Description</th>
                            <th>Head</th>
                            <th>Actions</th>
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
    `).join('') : `<tr><td colspan="5" style="text-align:center;">No clients found</td></tr>`;

    return `
        <div class="page-header" style="display:flex; justify-content:space-between; align-items:center;">
            <div>
                <h1 class="page-title">Clients Management</h1>
                <p class="page-subtitle">Manage your CRM clients here.</p>
            </div>
            <button class="btn btn-primary" onclick="showCRMClientModal()">
                <i data-lucide="plus"></i> New Client
            </button>
        </div>
        
        <div class="card">
            <div class="table-responsive">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>Company</th>
                            <th>Email</th>
                            <th>Phone</th>
                            <th>Actions</th>
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
            <h1 class="page-title">Orders</h1>
        </div>
        <div class="card">
            <div style="overflow-x: auto;">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Deal / Client</th>
                            <th>Start Date</th>
                            <th>End Date</th>
                            <th>Location</th>
                            <th>Invoice Amount</th>
                            <th>Project Status</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${tableRows.length > 0 ? tableRows : '<tr><td colspan="7" style="text-align:center;">No orders found</td></tr>'}
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

    const stages = ['LEAD', 'PITCH', 'NEGOTIATION', 'WON', 'LOST'];
    
    let boardHtml = '';
    stages.forEach(stage => {
        const stageDeals = deals.filter(d => d.stage === stage);
        boardHtml += `
            <div class="kanban-col" id="crm-col-${stage}" ondrop="dropDeal(event, '${stage}')" ondragover="allowDrop(event)">
                <h3 id="crm-header-${stage}">${stage} (${stageDeals.length})</h3>
                ${stageDeals.map(d => `
                    <div class="card kanban-card" id="deal-card-${d.id}" draggable="true" ondragstart="dragDeal(event, '${d.id}')" data-stage="${stage}" style="position: relative;">
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
                        ${d.assigned_to ? `<div style="font-size: 0.75rem; color: var(--color-text-secondary); margin-bottom: 0.5rem;"><i data-lucide="user" style="width: 12px; height: 12px;"></i> ${(users.find(u => u.id === d.assigned_to) || {}).full_name || 'User'}</div>` : ''}
                        <div class="status-badge success" style="margin-top: auto;">SAR ${d.amount}</div>
                    </div>
                `).join('')}
            </div>
        `;
    });

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">CRM Pipeline</h1>
                <p class="page-subtitle">Manage clients and deals</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-3" style="grid-column: span 12 / span 12;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 1rem;">
                    <div class="card-title">Deal Pipeline</div>
                    <button class="btn btn-primary" onclick="showCRMDealModal()">
                        <i data-lucide="plus"></i> New Deal
                    </button>
                </div>
                <div class="kanban-board" style="display:flex; gap: 1rem; overflow-x: auto; padding-bottom: 1rem;">
                    ${boardHtml}
                </div>
            </div>

            <div class="card col-span-3" style="grid-column: span 12 / span 12;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 1rem;">
                    <div class="card-title">Client Directory</div>
                    <button class="btn btn-primary" onclick="showCRMClientModal()">
                        <i data-lucide="plus"></i> New Client
                    </button>
                </div>
                <div class="table-responsive">
                    <table class="table">
                        <thead>
                            <tr>
                                <th>Name</th>
                                <th>Company</th>
                                <th>Email</th>
                                <th>Phone</th>
                                <th>Status</th>
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
                            ${clients.length === 0 ? '<tr><td colspan="5" class="text-center">No clients yet</td></tr>' : ''}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    `;
}

// Drag & Drop Deal Logic
window.allowDrop = function(ev) {
    ev.preventDefault();
}

window.dragDeal = function(ev, dealId) {
    ev.dataTransfer.setData("dealId", dealId);
}

window.moveDealCard = function(dealId, newStage) {
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
        document.getElementById('crmOrderModal').classList.add('show');
        if (window.lucide) window.lucide.createIcons();
        return;
    }

    window.moveDealCard(dealId, newStage);
    
    const res = await db.updateDealStage(dealId, newStage);
    if(res.success) {
        if (oldStage === 'WON') {
            await db.deleteOrderByDealId(dealId);
        }
        showToast("Deal moved to " + newStage, "success");
    } else {
        showToast("Failed to move deal", "danger");
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
    if(res.success) {
        if (oldStage === 'WON') {
            await db.deleteOrderByDealId(dealId);
            showToast("Deal marked as lost & order removed", "success");
        } else {
            showToast("Deal marked as lost", "success");
        }
    } else {
        showToast("Failed to update deal", "danger");
    }
};

window.closeCRMOrderModal = () => {
    document.getElementById('crmOrderModal').classList.remove('show');
};

window.handleOrderSubmit = async (e) => {
    e.preventDefault();
    const dealId = document.getElementById('orderDealId').value;
    
    const orderData = {
        start_date: document.getElementById('orderStartDate').value || null,
        end_date: document.getElementById('orderEndDate').value || null,
        event_location: document.getElementById('orderLocation').value || null,
        invoice_amount: parseFloat(document.getElementById('orderInvoiceAmount').value) || 0,
        project_status: document.getElementById('orderProjectStatus').value || 'Not Confirmed',
        notes: document.getElementById('orderNotes').value || null,
    };
    
    closeCRMOrderModal();
    window.moveDealCard(dealId, 'WON');
    
    const res = await db.createOrder(orderData, dealId);
    if (res.success) {
        showToast("Order saved and deal won!", "success");
        await db.triggerWebhooks('deal_won', { deal_id: dealId });
    } else {
        showToast("Failed to save order", "danger");
    }
};

window.showEditOrderModal = async (id) => {
    const orders = await db.fetchOrders();
    const order = orders.find(o => o.id === id);
    if (!order) return showToast("Order not found", "danger");
    
    document.getElementById('editOrderId').value = id;
    document.getElementById('editOrderStartDate').value = order.start_date || '';
    document.getElementById('editOrderEndDate').value = order.end_date || '';
    document.getElementById('editOrderLocation').value = order.event_location || '';
    document.getElementById('editOrderInvoiceAmount').value = order.invoice_amount || '';
    document.getElementById('editOrderProjectStatus').value = order.project_status || 'Not Confirmed';
    document.getElementById('editOrderNotes').value = order.notes || '';
    
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
    };
    
    const res = await db.updateOrder(id, orderData);
    if (res.success) {
        showToast("Order updated successfully", "success");
        closeEditOrderModal();
        if (currentView === 'orders') renderView('orders');
    } else {
        showToast("Failed to update order", "danger");
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
        showToast("Order deleted successfully", "success");
        closeConfirmDeleteOrderModal();
        if (currentView === 'orders') renderView('orders');
    } else {
        showToast("Failed to delete order", "danger");
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
                        <span style="color: #0000FF; display:inline-block; transform:translateY(2px);"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path><circle cx="12" cy="10" r="3"></circle></svg></span> St.Arafat Bn°3113 ,7558 Al Hamra Dist. Jeddah PC. 23323 ,Kingdom of Saudi Arabia
                    </div>
                    <div class="hl-text-right" dir="rtl">
                        <strong style="font-size: 15px; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;">مُقام | لتنظيم المعارض والمؤتمرات</strong><br><br>
                        التسجيل الضريبي VAT : 311460343900003<br>
                        السجل التجاري CR : 7031641660
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
            <h1 style="text-align: center; font-size: 36px; font-weight: bold; margin-bottom: 40px; margin-top: 0;">تأكيد اوردر</h1>
            
            <table style="width: 100%; border-collapse: collapse; margin-bottom: 30px; border: 1px solid #000;">
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">التاريخ :</td>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%;"></td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">الوقت :</td>
                    <td style="border: 1px solid #000; padding: 10px;"></td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">رقم الاوردر :</td>
                    <td style="border: 1px solid #000; padding: 10px;">${order.id || ''}</td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">مسؤول تأكيد الاوردر :</td>
                    <td style="border: 1px solid #000; padding: 10px;"></td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">الموظف :</td>
                    <td style="border: 1px solid #000; padding: 10px;"></td>
                </tr>
            </table>

            <table style="width: 100%; border-collapse: collapse; margin-bottom: 30px; border: 1px solid #000;">
                <tr>
                    <th colspan="2" style="border: 1px solid #000; padding: 10px; text-align: center; background-color: #f9f9f9 !important; font-weight: bold;">بيانات الاوردر</th>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%; text-align: right;">اسم العميل : ${clientName}</td>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%; text-align: right;">رقم هاتف العميل : ${clientPhone}</td>
                </tr>
            </table>

            <table style="width: 100%; border-collapse: collapse; margin-bottom: 30px; border: 1px solid #000;">
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">تاريخ الحفل : ${escapeHTML(order.start_date || '')}</td>
                    <td style="border: 1px solid #000; padding: 10px; width: 50%; text-align: right;">فريق التركيب :</td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">وقت الحفل :</td>
                    <td rowspan="3" style="border: 1px solid #000; padding: 10px; vertical-align: top;"></td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">موعد التركيب :</td>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; font-weight: bold; background-color: #f9f9f9 !important; text-align: right;">موعد الفك :</td>
                </tr>
            </table>
        </div>

        <div style="page-break-before: always; padding-top: 50px;" dir="rtl">
            <h1 style="text-align: center; font-size: 36px; font-weight: bold; margin-bottom: 40px;">تفاصيل اوردر</h1>
            
            <table style="width: 100%; border-collapse: collapse; margin-bottom: 30px; text-align: center; border: 1px solid #000;">
                <tr>
                    <th style="border: 1px solid #000; padding: 10px; width: 5%; background-color: #f9f9f9 !important; text-align: center; font-weight: bold;">#</th>
                    <th style="border: 1px solid #000; padding: 10px; width: 30%; background-color: #f9f9f9 !important; text-align: center; font-weight: bold;">البند</th>
                    <th style="border: 1px solid #000; padding: 10px; width: 25%; background-color: #f9f9f9 !important; text-align: center; font-weight: bold;">الصورة</th>
                    <th style="border: 1px solid #000; padding: 10px; width: 10%; background-color: #f9f9f9 !important; text-align: center; font-weight: bold;">العدد</th>
                    <th style="border: 1px solid #000; padding: 10px; width: 30%; background-color: #f9f9f9 !important; text-align: center; font-weight: bold;">ملاحظات</th>
                </tr>
                <tr><td style="border: 1px solid #000; height: 50px;">١</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
                <tr><td style="border: 1px solid #000; height: 50px;">٢</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
                <tr><td style="border: 1px solid #000; height: 50px;">٣</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
                <tr><td style="border: 1px solid #000; height: 50px;">٤</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
                <tr><td style="border: 1px solid #000; height: 50px;">٥</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
                <tr><td style="border: 1px solid #000; height: 50px;">٦</td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td><td style="border: 1px solid #000;"></td></tr>
            </table>

            <table style="width: 100%; border-collapse: collapse; border: 1px solid #000;">
                <tr>
                    <th style="border: 1px solid #000; padding: 10px; background-color: #f9f9f9 !important; text-align: right; font-weight: bold;">اللوكيشن : ${locationStr}</th>
                </tr>
                <tr>
                    <td style="border: 1px solid #000; padding: 10px; min-height: 100px; vertical-align: top; text-align: right;">
                        <strong>ملاحظات عامة :</strong>
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
    // Populate head dropdown
    try {
        if(db.fetchAllProfiles) {
            const profiles = await db.fetchAllProfiles();
            const headSelect = document.getElementById('departmentHead');
            headSelect.innerHTML = '<option value="">Select a head...</option>' + 
                profiles.map(p => `<option value="${p.id}">${p.full_name}</option>`).join('');
                
            const empSelect = document.getElementById('departmentEmployees');
            empSelect.innerHTML = profiles.map(p => {
                const isSelected = dept && p.department_id === dept.id ? 'selected' : '';
                return `<option value="${p.id}" ${isSelected}>${p.full_name}</option>`;
            }).join('');
        }
    } catch (e) {
        console.error("Error loading profiles for department head:", e);
    }

    if (dept) {
        document.getElementById('departmentId').value = dept.id;
        document.getElementById('departmentName').value = dept.name || '';
        document.getElementById('departmentDescription').value = dept.description || '';
        document.getElementById('departmentHead').value = dept.head_id || '';
        document.getElementById('departmentModalTitle').innerText = 'Edit Department';
        document.getElementById('departmentSubmitBtn').innerText = 'Save Changes';
    } else {
        document.getElementById('departmentId').value = '';
        document.getElementById('departmentName').value = '';
        document.getElementById('departmentDescription').value = '';
        document.getElementById('departmentHead').value = '';
        
        // Clear multi-select manually
        const empSelect = document.getElementById('departmentEmployees');
        for (let i = 0; i < empSelect.options.length; i++) {
            empSelect.options[i].selected = false;
        }

        document.getElementById('departmentModalTitle').innerText = 'New Department';
        document.getElementById('departmentSubmitBtn').innerText = 'Create Department';
    }
    document.getElementById('departmentModal').classList.add('show');
};
window.closeDepartmentModal = () => {
    document.getElementById('departmentModal').classList.remove('show');
};

window.showConfirmModal = (title, message, onConfirm) => {
    const modal = document.getElementById('confirmModal');
    if (!modal) return;
    
    document.getElementById('confirmModalTitle').innerText = title;
    document.getElementById('confirmModalMessage').innerText = message;
    
    const confirmBtn = document.getElementById('confirmModalBtn');
    const newConfirmBtn = confirmBtn.cloneNode(true);
    confirmBtn.parentNode.replaceChild(newConfirmBtn, confirmBtn);
    
    newConfirmBtn.onclick = async () => {
        newConfirmBtn.disabled = true;
        newConfirmBtn.innerHTML = 'Confirming...';
        await onConfirm();
        newConfirmBtn.disabled = false;
        newConfirmBtn.innerHTML = 'Confirm';
        closeConfirmModal();
    };
    
    modal.classList.add('show');
};

window.closeConfirmModal = () => {
    const modal = document.getElementById('confirmModal');
    if (modal) modal.classList.remove('show');
};

window.editDepartment = async (id) => {
    const depts = await db.fetchDepartments();
    const dept = depts.find(d => d.id === id);
    if (dept) {
        showDepartmentModal(dept);
    }
};

window.deleteDepartment = (id) => {
    window.showConfirmModal(
        "Delete Department",
        "Are you sure you want to delete this department?",
        async () => {
            const res = await db.deleteDepartment(id);
            if (res.success) {
                showToast("Department deleted", "success");
                const row = document.getElementById(`dept-row-${id}`);
                if (row) row.remove();
            } else {
                showToast("Failed to delete department.", "danger");
            }
        }
    );
};

window.handleCreateDepartment = async (e) => {
    e.preventDefault();
    const id = document.getElementById('departmentId').value;
    const data = {
        name: document.getElementById('departmentName').value,
        description: document.getElementById('departmentDescription').value,
        head_id: document.getElementById('departmentHead').value || null
    };
    
    const empSelect = document.getElementById('departmentEmployees');
    const selectedEmployeeIds = Array.from(empSelect.selectedOptions).map(opt => opt.value);
    
    let res;
    if (id) {
        res = await db.updateDepartment(id, data, selectedEmployeeIds);
    } else {
        res = await db.createDepartment(data, selectedEmployeeIds);
    }
    
    if (res.success) {
        showToast(id ? "Department updated" : "Department created", "success");
        closeDepartmentModal();
        e.target.reset();
        if(currentView === 'departments') renderView('departments');
    } else {
        showToast("Error saving department", "danger");
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
        document.getElementById('crmClientModalTitle').innerText = 'Edit Client';
        document.getElementById('crmClientSubmitBtn').innerHTML = '<i data-lucide="save" style="margin-right: 6px; width: 18px; height: 18px; vertical-align: middle;"></i> Save Changes';
    } else {
        document.getElementById('crmClientId').value = '';
        document.getElementById('crmClientName').value = '';
        document.getElementById('crmClientCompany').value = '';
        document.getElementById('crmClientEmail').value = '';
        document.getElementById('crmClientPhone').value = '';
        document.getElementById('crmClientModalTitle').innerText = 'New Client';
        document.getElementById('crmClientSubmitBtn').innerHTML = '<i data-lucide="save" style="margin-right: 6px; width: 18px; height: 18px; vertical-align: middle;"></i> Create Client';
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
                showToast("Client deleted", "success");
                const row = document.getElementById(`client-row-${id}`);
                if (row) row.remove();
            } else {
                showToast("Failed to delete client. It might be linked to existing deals.", "danger");
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
        if(currentView === 'crm' || currentView === 'clients') renderView(currentView);
    }
};

window.showCRMDealModal = async (id = null, isViewOnly = false) => {
    const clients = await db.fetchClients();
    const select = document.getElementById('crmDealClient');
    select.innerHTML = '<option value="">Select a client...</option>' + 
        clients.map(c => `<option value="${c.id}">${c.name} (${c.company})</option>`).join('');
        
    const users = await db.fetchUsers();
    const assigneeSelect = document.getElementById('crmDealAssignee');
    if (assigneeSelect) {
        assigneeSelect.innerHTML = '<option value="">Unassigned</option>' + 
            users.map(u => `<option value="${u.id}">${u.full_name} (${u.role})</option>`).join('');
    }
    
    document.getElementById('crmDealId').value = id || '';
    
    const titleEl = document.getElementById('crmDealModalTitle');
    const submitBtn = document.getElementById('crmDealSubmitBtn');
    if (isViewOnly) {
        titleEl.textContent = 'View Deal Details';
        submitBtn.style.display = 'none';
    } else if (id) {
        titleEl.textContent = 'Edit Deal';
        submitBtn.style.display = 'block';
        submitBtn.innerHTML = '<i data-lucide="save" style="margin-right: 6px; width: 18px; height: 18px; vertical-align: middle;"></i> Save Changes';
    } else {
        titleEl.textContent = 'New Deal';
        submitBtn.style.display = 'block';
        submitBtn.innerHTML = '<i data-lucide="save" style="margin-right: 6px; width: 18px; height: 18px; vertical-align: middle;"></i> Create Deal';
    }

    // Toggle disabled state for all inputs
    const inputs = ['crmDealTitle', 'crmDealClient', 'crmDealAmount', 'crmDealClosingDate', 'crmDealAssignee', 'crmDealLostReason', 'crmDealEventType', 'crmDealFirstContactDate', 'crmDealContactMethod', 'crmDealLeadSource'];
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
        assigned_to: assigneeVal ? assigneeVal : currentUser.id
    };
    if (!id) data.stage = 'LEAD'; // Only set stage on creation
    
    const lostReasonGroup = document.getElementById('crmDealLostReasonGroup');
    if (lostReasonGroup && lostReasonGroup.style.display !== 'none') {
        data.lost_reason = document.getElementById('crmDealLostReason').value;
    }
    
    if (!data.client_id) return showToast("Please select a client", "danger");

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
        if(currentView === 'crm') renderView('crm');
    }
};

// ==========================================
// Integrations / Webhooks Features
// ==========================================
async function renderIntegrations() {
    if (currentUserRole !== 'ADMIN') {
        return `<div class="page-header"><h1 class="page-title">Unauthorized</h1></div>`;
    }

    const webhooks = await db.fetchWebhooks();

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">API Integrations (Webhooks)</h1>
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
                                <th>Name</th>
                                <th>Event Type</th>
                                <th>URL</th>
                                <th>Status</th>
                                <th>Actions</th>
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
                    • <code>deal_won</code>: Fires when a CRM deal is dragged to the WON stage.<br/>
                    • <code>new_client</code>: Fires when a new CRM client is added.<br/>
                    • <code>all</code>: Fires on all supported events.
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
        showToast("Webhook created", "success");
        closeWebhookModal();
        e.target.reset();
        if(currentView === 'integrations') renderView('integrations');
    }
};
window.handleDeleteWebhook = (id) => {
    window.showConfirmModal(
        "Delete Webhook",
        "Delete this webhook?",
        async () => {
            const res = await db.deleteWebhook(id);
            if (res.success) {
                showToast("Webhook deleted", "success");
                const row = document.getElementById(`webhook-row-${id}`);
                if (row) row.remove();
            }
        }
    );
};

// Init
async function initApp() {
    updateTranslations();

    // Check for existing session
    const { data: { session } } = await db.getSession();

    // Listen for session expiration or logout
    db.onAuthStateChange((event, session) => {
        if (event === 'SIGNED_OUT' || !session) {
            currentUser = null;
            currentUserRole = null;
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
        currentUserRole = profile.role;
        updateTopbarProfile(profile);

        // Show navigation
        document.querySelector('.sidebar').style.display = 'block';
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
        if (employeesNav) employeesNav.style.display = (currentUserRole === 'ADMIN' || ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR')) ? 'flex' : 'none';
        
        const isHussain = currentUser.full_name && currentUser.full_name.toLowerCase().includes('hussain') || currentUser.email && currentUser.email.toLowerCase().includes('hussain');
        if (approvalsNav) approvalsNav.style.display = (currentUserRole === 'ADMIN' || isHussain) ? 'flex' : 'none';

        currentView = 'dashboard';

        pollNotifications();
        if (notificationsInterval) clearInterval(notificationsInterval);
        notificationsInterval = setInterval(pollNotifications, 60000);
    } else {
        currentView = 'login';
    }

    renderView(currentView);
}

window.handleRequestAction = async function (type, id, status, employeeId) {
    let success = false;
    if (type === 'Leave') {
        const res = await db.updateLeaveStatus(id, status);
        success = res.success;
    } else if (type === 'Document') {
        const res = await db.updateDocumentStatus(id, status);
        success = res.success;
    } else if (type === 'Expense') {
        const res = await db.updateExpenseStatus(id, status);
        success = res.success;
    }

    if (success) {
        const displayStatus = status.includes('_ARCHIVED') ? 'archived' : status.toLowerCase();
        showToast(`${type} request ${displayStatus}`, "success");
        if (employeeId && !status.includes('_ARCHIVED')) await db.createNotification(employeeId, `Your ${type.toLowerCase()} request has been ${status.toLowerCase()}.`);
        renderView('requests');
    } else {
        showToast(`Failed to update ${type} request`, "danger");
    }
}

// Unified Requests Page
async function renderRequests() {
    const isManagerOrAdmin = currentUserRole === 'ADMIN' || ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR');

    // Fetch data
    let leaves = await db.fetchLeaveRequests(isManagerOrAdmin ? null : currentUser?.id);
    let docs = await db.fetchDocuments(isManagerOrAdmin ? null : currentUser?.id);
    let expenses = await db.fetchExpenses(isManagerOrAdmin ? null : currentUser?.id);

    let profilesMap = {};
    if (isManagerOrAdmin) {
        const allProfiles = await db.fetchAllProfiles();
        let teamIds = [currentUser.id];
        allProfiles.forEach(p => {
            profilesMap[p.id] = p.full_name || 'Unknown User';
            if (p.manager_id === currentUser.id) teamIds.push(p.id);
        });
        
        if (currentUserRole !== 'ADMIN') {
            leaves = leaves.filter(r => teamIds.includes(r.employee_id));
            docs = docs.filter(r => teamIds.includes(r.employee_id));
            expenses = expenses.filter(r => teamIds.includes(r.employee_id));
        }
    }

    // Normalize requests
    let allRequests = [];
    leaves.forEach(r => {
        allRequests.push({
            id: r.id,
            type: 'Leave',
            employee_id: r.employee_id,
            details: `${r.leave_type}: ${new Date(r.start_date).toLocaleDateString()} to ${new Date(r.end_date).toLocaleDateString()}`,
            status: r.status,
            created_at: r.created_at,
            raw: r
        });
    });

    docs.forEach(r => {
        allRequests.push({
            id: r.id,
            type: 'Document',
            employee_id: r.employee_id,
            details: `${r.doc_type} - ${r.purpose}`,
            status: r.status,
            created_at: r.created_at,
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
            raw: r
        });
    });

    // Sort by created_at desc
    allRequests.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));

    // Filter out archived
    allRequests = allRequests.filter(r => r.status === 'PENDING');

    // Render UI
    let rowsHTML = allRequests.map(r => {
        let badgeClass = 'info';
        if (r.status === 'APPROVED') badgeClass = 'success';
        if (r.status === 'REJECTED') badgeClass = 'danger';

        const employeeName = isManagerOrAdmin ? (profilesMap[r.employee_id] || 'Unknown') : 'Me';

        let actionsCell = '';
        if (isManagerOrAdmin) {
            if (r.status === 'PENDING') {
                actionsCell = `
                    <td>
                        <button class="btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem;" onclick="handleRequestAction('${r.type}', '${r.id}', 'APPROVED', '${r.employee_id}')">${t('leave_approve')}</button>
                        <button class="btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; background: var(--color-danger);" onclick="handleRequestAction('${r.type}', '${r.id}', 'REJECTED', '${r.employee_id}')">${t('leave_reject')}</button>
                    </td>
                `;
            } else if (r.status === 'APPROVED' || r.status === 'REJECTED') {
                actionsCell = `
                    <td>
                        <button class="btn-secondary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem;" onclick="handleRequestAction('${r.type}', '${r.id}', '${r.status}_ARCHIVED', '${r.employee_id}')">
                            <i data-lucide="archive" style="width:12px;height:12px;"></i> ${t('req_archive_btn')}
                        </button>
                    </td>
                `;
            } else {
                actionsCell = `<td>-</td>`;
            }
        }

        return `
            <tr class="request-row" data-type="${r.type}" data-status="${r.status}" data-emp="${employeeName.toLowerCase()}" data-details="${r.details.toLowerCase()}">
                <td>${new Date(r.created_at).toLocaleDateString()}</td>
                ${isManagerOrAdmin ? `<td>${employeeName}</td>` : ''}
                <td><strong>${r.type}</strong></td>
                <td>${r.details}</td>
                <td><span class="status-badge ${badgeClass}">${r.status}</span></td>
                ${actionsCell}
            </tr>
        `;
    }).join('');

    if (allRequests.length === 0) {
        const colSpan = isManagerOrAdmin ? 6 : 4;
        rowsHTML = `<tr><td colspan="${colSpan}" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">${t('req_no_found')}</td></tr>`;
    }

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('req_all')}</h1>
                <p class="page-subtitle">${t('req_sub')}</p>
            </div>
        </div>
        
        <div class="card fade-in-up" style="margin-bottom: 2rem;">
            <div style="display: flex; gap: 1rem; align-items: center; flex-wrap: wrap;">
                <div style="flex: 1; min-width: 200px;">
                    <label class="form-label">${t('req_search')}</label>
                    <input type="text" id="reqSearch" class="form-control" placeholder="${t('req_search_ph')}" onkeyup="filterRequests()">
                </div>
                <div style="width: 150px;">
                    <label class="form-label">${t('req_type')}</label>
                    <select id="reqType" class="form-control" onchange="filterRequests()">
                        <option value="ALL">${t('req_type_all')}</option>
                        <option value="Leave">${t('req_type_leave')}</option>
                        <option value="Document">${t('req_type_doc')}</option>
                        <option value="Expense">${t('req_type_exp')}</option>
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
        
        <div class="card fade-in-up">
            <div class="table-responsive">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>${t('date')}</th>
                            ${isManagerOrAdmin ? `<th>${t('leave_employee')}</th>` : ''}
                            <th>${t('req_type')}</th>
                            <th>${t('req_details')}</th>
                            <th>${t('req_status')}</th>
                            ${isManagerOrAdmin ? `<th>${t('leave_actions')}</th>` : ''}
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
    const searchVal = document.getElementById('reqSearch').value.toLowerCase();
    const typeVal = document.getElementById('reqType').value;
    const statusVal = document.getElementById('reqStatus').value;

    const rows = document.querySelectorAll('.request-row');
    rows.forEach(row => {
        const t = row.getAttribute('data-type');
        const s = row.getAttribute('data-status');
        const emp = row.getAttribute('data-emp');
        const det = row.getAttribute('data-details');

        const matchSearch = emp.includes(searchVal) || det.includes(searchVal);
        const matchType = typeVal === 'ALL' || t === typeVal;
        const matchStatus = statusVal === 'ALL' || s === statusVal;

        if (matchSearch && matchType && matchStatus) {
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
    const leaves = await db.fetchLeaveRequests();
    const docs = await db.fetchDocuments();
    const expenses = await db.fetchExpenses();

    let profilesMap = {};
    const allProfiles = await db.fetchAllProfiles();
    allProfiles.forEach(p => {
        profilesMap[p.id] = p.full_name || 'Unknown User';
    });

    // Normalize requests
    let allRequests = [];
    const addToRequests = (items, type, getDetails) => {
        items.forEach(r => {
            if (r.status.endsWith('_ARCHIVED')) {
                allRequests.push({
                    id: r.id,
                    type: type,
                    employee_id: r.employee_id,
                    details: getDetails(r),
                    status: r.status.replace('_ARCHIVED', ''), // Show original status
                    created_at: r.created_at
                });
            }
        });
    };

    addToRequests(leaves, 'Leave', r => `${r.leave_type}: ${new Date(r.start_date).toLocaleDateString()} to ${new Date(r.end_date).toLocaleDateString()}`);
    addToRequests(docs, 'Document', r => `${r.doc_type} - ${r.purpose}`);
    addToRequests(expenses, 'Expense', r => `SAR ${r.amount} - ${r.description}`);

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
                <td>${r.details}</td>
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
    if (!currentUser) return `<div class="page-header"><h1 class="page-title">Projects</h1></div><div class="card">Please login to view projects.</div>`;

    console.log("renderProjects: Fetching projects from db...");
    const projects = await db.fetchProjects();
    console.log("renderProjects: Fetched projects.", { count: projects ? projects.length : 0 });
    window.projectCache = {};

    let html = `
        <div class="page-header" style="display: flex; justify-content: space-between; align-items: center;">
            <h1 class="page-title">Projects</h1>
            <button class="btn btn-primary" onclick="openProjectModal()"><i data-lucide="plus"></i> New Project</button>
        </div>
        <div class="dashboard-grid" style="grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1.5rem;">
    `;

    if (!projects || projects.length === 0) {
        html += `<div class="card" style="grid-column: 1 / -1; text-align: center; color: var(--color-text-secondary);">No projects found.</div>`;
    } else {
        projects.forEach(p => {
            window.projectCache[p.id] = p;
            const tagsHtml = (p.project_tags || []).map(t => `<span class="badge" style="background: var(--color-primary);">${t}</span>`).join(' ');
            html += `
                <div class="card" style="display: flex; flex-direction: column; gap: 0.5rem; position: relative;">
                    <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                        <h3 style="margin: 0; padding-right: 3rem;">${p.project_name}</h3>
                        <div style="display: flex; gap: 0.5rem; align-items: center;">
                            <span class="badge" style="background: var(--color-success);">${p.project_category || 'General'}</span>
                            <button onclick="event.stopPropagation(); openEditProjectModal('${p.id}')" class="btn btn-icon" style="background:none; border:none; color:var(--color-text-secondary); cursor:pointer; padding:0;" title="Edit Project"><i data-lucide="edit-2" style="width:16px;height:16px;"></i></button>
                        </div>
                    </div>
                    <p style="color: var(--color-text-secondary); margin: 0; font-size: 0.9rem;">${p.project_type}</p>
                    <p style="margin: 0.5rem 0; flex-grow: 1;">${p.description || 'No description provided.'}</p>
                    <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">${tagsHtml}</div>
                </div>
            `;
        });
    }

    html += `</div>`;
    return html;
}

window.openProjectModal = async function() {
    document.getElementById('newProjectName').value = '';
    document.getElementById('newProjectType').value = '';
    document.getElementById('newProjectDesc').value = '';
    document.getElementById('newProjectTags').value = '';
    
    const assigneesSelect = document.getElementById('newProjectAssignees');
    assigneesSelect.innerHTML = '<option value="">Loading...</option>';
    
    const profiles = await db.fetchAllProfiles();
    if (profiles && profiles.length > 0) {
        assigneesSelect.innerHTML = profiles.map(p => `<option value="${p.id}">${p.full_name || p.id}</option>`).join('');
    } else {
        assigneesSelect.innerHTML = '<option value="">No users found</option>';
    }

    document.getElementById('projectModal').classList.add('active');
}

window.handleCreateProject = async function(event) {
    event.preventDefault();
    const name = document.getElementById('newProjectName').value;
    const type = document.getElementById('newProjectType').value;
    const category = document.getElementById('newProjectCategory').value;
    const desc = document.getElementById('newProjectDesc').value;
    
    const tagsSelect = document.getElementById('newProjectTags');
    const tags = Array.from(tagsSelect.selectedOptions).map(opt => opt.value);

    const assigneesSelect = document.getElementById('newProjectAssignees');
    const assignedPeople = Array.from(assigneesSelect.selectedOptions).map(opt => opt.value);

    document.getElementById('projectModal').classList.remove('active');
    showToast("Creating project...", "info");

    const { success } = await db.createProject(name, type, desc, assignedPeople, category, tags);

    if (success) {
        // Webhook simulation via notification
        await db.createNotification(currentUser.id, `Project created: ${name}`);
        showToast("Project created successfully!", "success");
        if (currentView === 'projects') renderView('projects');
    } else {
        showToast("Failed to create project", "error");
    }
}

window.openEditProjectModal = async function(id) {
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
            `<option value="${p.id}" ${(project.assigned_people || []).includes(p.id) ? 'selected' : ''}>${p.full_name || p.id}</option>`
        ).join('');
    } else {
        assigneesSelect.innerHTML = '<option value="">No users found</option>';
    }

    document.getElementById('editProjectModal').classList.add('active');
    if (window.lucide) window.lucide.createIcons();
}

window.handleUpdateProject = async function(event) {
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
    showToast("Updating project...", "info");

    const { success } = await db.updateProject(id, name, type, desc, assignedPeople, category, tags);

    if (success) {
        showToast("Project updated successfully!", "success");
        if (currentView === 'projects') renderView('projects');
    } else {
        showToast("Failed to update project", "error");
    }
}

// ==========================================
// APPROVALS DASHBOARD
// ==========================================
window.renderApprovals = async function() {
    const isHussain = currentUser.full_name && currentUser.full_name.toLowerCase().includes('hussain') || currentUser.email && currentUser.email.toLowerCase().includes('hussain');
    if (currentUserRole !== 'ADMIN' && !isHussain) {
        return `<div class="page-header"><h1 class="page-title">Unauthorized</h1></div>`;
    }

    const { data: tasks, error } = await window.supabaseClient
        .from('tasks')
        .select('*, user:assignee_id(full_name, role), project:project_id(name)')
        .eq('status', 'Pending Approval')
        .order('created_at', { ascending: false });

    if (error) {
        console.error('Error fetching approvals:', error);
        return `<div class="page-header"><h1 class="page-title">Error loading approvals</h1></div>`;
    }

    if (!tasks || tasks.length === 0) {
        return `
            <div class="page-header">
                <h1 class="page-title">Approvals Dashboard</h1>
            </div>
            <div class="card" style="padding: 2rem; text-align: center; color: var(--color-text-secondary);">
                No tasks pending approval.
            </div>
        `;
    }

    let rows = tasks.map(t => {
        const title = t.title_i18n ? (t.title_i18n[currentLang] || t.title_i18n['en'] || t.title) : t.title;
        return `
            <tr>
                <td>${title}</td>
                <td>${t.project ? t.project.name : 'No Project'}</td>
                <td>${t.user ? t.user.full_name : 'Unassigned'}</td>
                <td>${t.content_type || '-'}</td>
                <td>
                    ${t.source_link ? `<a href="${t.source_link}" target="_blank">Source</a>` : '-'}
                    ${t.upload_link ? ` | <a href="${t.upload_link}" target="_blank">Upload</a>` : ''}
                </td>
                <td style="text-align: right; white-space: nowrap;">
                    <button class="btn btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.8rem;" onclick="handleApprovalAction('${t.id}', 'todo')">Approve</button>
                    <button class="btn btn-danger" style="padding: 0.25rem 0.5rem; font-size: 0.8rem;" onclick="handleApprovalAction('${t.id}', 'Rejected')">Reject</button>
                </td>
            </tr>
        `;
    }).join('');

    return `
        <div class="page-header">
            <h1 class="page-title">Approvals Dashboard</h1>
        </div>
        <div class="card">
            <table class="table">
                <thead>
                    <tr>
                        <th>Task</th>
                        <th>Project</th>
                        <th>Assignee</th>
                        <th>Content Type</th>
                        <th>Links</th>
                        <th style="text-align: right;">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    ${rows}
                </tbody>
            </table>
        </div>
    `;
};

window.handleApprovalAction = async function(taskId, newStatus) {
    if (!confirm('Are you sure you want to ' + (newStatus === 'todo' ? 'approve' : 'reject') + ' this task?')) return;
    const { error } = await db.updateTaskStatus(taskId, newStatus);
    if (error) {
        showToast('Failed to update task', 'danger');
    } else {
        const { data: taskData } = await window.supabaseClient.from('tasks').select('title, assignee_id').eq('id', taskId).single();
        if (taskData && taskData.assignee_id) {
            await db.createNotification(taskData.assignee_id, `Your task "${taskData.title}" was ${newStatus === 'todo' ? 'approved' : 'rejected'}.`);
        }
        showToast('Task ' + (newStatus === 'todo' ? 'approved' : 'rejected'), 'success');
        renderView('approvals');
    }
};

// Global Esc Key Handler for Modals and Popups
document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
        const activeModals = document.querySelectorAll('.modal.active, .popup.active, .slide-panel.active');
        activeModals.forEach(modal => {
            modal.classList.remove('active');
        });
    }
});

// Global Search Logic
const searchInput = document.querySelector('.search-input');
if (searchInput) {
    searchInput.addEventListener('input', function(e) {
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
    document.addEventListener('keydown', function(event) {
        if ((event.metaKey || event.ctrlKey) && event.key === 'k') {
            event.preventDefault();
            searchInput.focus();
        }
    });
}

// Close modals when clicking on the backdrop
document.addEventListener('click', function(e) {
    if (e.target.classList.contains('modal')) {
        e.target.classList.remove('active', 'show');
    }
});

initApp();
