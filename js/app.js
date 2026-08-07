// App State
let currentLang = 'en';
let currentTheme = 'dark';
let currentView = 'login';
let currentUser = null;
let currentUserRole = null;

// DOM Elements
const htmlElement = document.documentElement;
const themeToggle = document.getElementById('themeToggle');
const themeIcon = document.getElementById('themeIcon');
const langToggle = document.getElementById('langToggle');
const langText = document.getElementById('langText');
const viewContainer = document.getElementById('viewContainer');
const navItems = document.querySelectorAll('.nav-item');

// Initialize Icons
lucide.createIcons();

// --- THEME MANAGEMENT ---
function toggleTheme() {
    currentTheme = currentTheme === 'light' ? 'dark' : 'light';
    htmlElement.setAttribute('data-theme', currentTheme);
    
    if (currentTheme === 'dark') {
        themeIcon.setAttribute('data-lucide', 'sun');
    } else {
        themeIcon.setAttribute('data-lucide', 'moon');
    }
    lucide.createIcons(); // Re-render icon
}

themeToggle.addEventListener('click', toggleTheme);

// --- LANGUAGE MANAGEMENT ---
function toggleLanguage() {
    currentLang = currentLang === 'en' ? 'ar' : 'en';
    htmlElement.setAttribute('dir', currentLang === 'ar' ? 'rtl' : 'ltr');
    htmlElement.setAttribute('lang', currentLang);
    langText.textContent = currentLang === 'en' ? 'AR' : 'EN';
    
    updateTranslations();
    renderView(currentView); // Re-render view for updated strings inside
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

langToggle.addEventListener('click', toggleLanguage);

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
window.handleClockIn = async function() {
    if(!currentUser) return;
    const success = await db.clockIn(currentUser.id);
    if (success) {
        showToast(t('toast_clock_in') + ' ' + new Date().toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}), 'success');
        renderView(currentView);
    } else {
        showToast("Error clocking in. Check DB connection.", "danger");
    }
}

window.handleClockOut = async function() {
    if(!currentUser) return;
    const success = await db.clockOut(currentUser.id);
    if (success) {
        showToast("Clocked out successfully.", 'success');
        renderView(currentView);
    } else {
        showToast("Error clocking out.", "danger");
    }
}

window.handleLogout = async function() {
    await db.logout();
    if(notificationsInterval) clearInterval(notificationsInterval);
    currentUser = null;
    currentUserRole = null;
    currentView = 'login';
    renderView('login');
}

window.handleLeaveSubmit = async function(e) {
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

window.handleLeaveAction = async function(id, status, employeeId) {
    const success = await db.updateLeaveStatus(id, status);
    if (success) {
        showToast(`Leave request ${status.toLowerCase()}`, 'success');
        if(employeeId) await db.createNotification(employeeId, `Your leave request has been ${status}.`);
        renderView(currentView);
    }
}

window.handleLoginSubmit = async function(e) {
    e.preventDefault();
    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;
    
    const { user, error } = await db.login(email, password);
    
    if (error || !user) {
        console.error("Login Error:", error);
        showToast(error?.message || t('invalid_credentials'), 'danger');
        return;
    }
    
    currentUser = user;
    const profile = await db.getUserProfile(user.id);
    currentUserRole = profile.role;
    updateTopbarProfile(profile);
    
    // Show sidebar and topbar again
    document.querySelector('.sidebar').style.display = 'block';
    document.querySelector('.topbar').style.display = 'flex';
    
    // Hide/Show Role-Specific Nav Items
    const adminNav = document.querySelector('.nav-item[data-view="admin"]');
    const usersNav = document.querySelector('.nav-item[data-view="users"]');
    const analyticsNav = document.querySelector('.nav-item[data-view="analytics"]');
    const employeesNav = document.querySelector('.nav-item[data-view="employees"]');
    
    if (adminNav) adminNav.style.display = currentUserRole === 'ADMIN' ? 'flex' : 'none';
    if (usersNav) usersNav.style.display = currentUserRole === 'ADMIN' ? 'flex' : 'none';
    if (analyticsNav) analyticsNav.style.display = (currentUserRole === 'ADMIN' || currentUserRole === 'MANAGER') ? 'flex' : 'none';
    if (employeesNav) employeesNav.style.display = (currentUserRole === 'ADMIN' || currentUserRole === 'MANAGER') ? 'flex' : 'none';
    
    // Route based on role
    if (currentUserRole === 'ADMIN') {
        currentView = 'admin';
    } else if (currentUserRole === 'MANAGER') {
        currentView = 'dashboard';
    } else {
        currentView = 'dashboard';
    }
    renderView(currentView);
}

// Render Login View
window.togglePasswordVisibility = function(inputId) {
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

function renderLogin() {
    // Hide sidebar and topbar for full screen login
    const sidebar = document.querySelector('.sidebar');
    const topbar = document.querySelector('.topbar');
    if (sidebar) sidebar.style.display = 'none';
    if (topbar) topbar.style.display = 'none';
    
    return `
        <div style="display: flex; height: 100vh; align-items: center; justify-content: center; width: 100vw; position: fixed; top: 0; left: 0; background: var(--color-bg); z-index: 9999;">
            <div class="card" style="width: 100%; max-width: 400px; padding: 2.5rem 2rem; box-shadow: 0 20px 40px rgba(0,0,0,0.1);">
                <div style="text-align: center; margin-bottom: 2rem;">
                    <div class="login-logo">MUQAM</div>
                    <h2 style="margin-top: 1rem; font-size: 1.25rem;">${t('login_title')}</h2>
                    <p style="color: var(--color-text-secondary); font-size: 0.875rem;">${t('login_subtitle')}</p>
                </div>
                <form onsubmit="handleLoginSubmit(event)">
                    <div class="form-group">
                        <label class="form-label">${t('email_label')}</label>
                        <input type="email" id="email" class="form-control" placeholder="name@company.com" required>
                    </div>
                    <div class="form-group" style="margin-bottom: 1.5rem; position: relative;">
                        <label class="form-label">${t('password_label')}</label>
                        <input type="password" id="password" class="form-control" placeholder="••••••••" required style="padding-right: 40px;">
                        <button type="button" onclick="togglePasswordVisibility('password')" style="position: absolute; right: 10px; bottom: 8px; background: none; border: none; cursor: pointer; color: var(--color-text-secondary); display: flex; align-items: center; justify-content: center; padding: 4px;">
                            <i data-lucide="eye" id="password-eye-icon" style="width: 20px; height: 20px;"></i>
                        </button>
                    </div>
                    <button type="submit" class="btn-primary" style="width: 100%; padding: 0.875rem; font-size: 1rem;">${t('sign_in')}</button>
                </form>
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

// Render Employee Dashboard
async function renderDashboard() {
    const isClockedIn = await db.checkClockInStatus(currentUser?.id);
    const announcements = await db.fetchAnnouncements() || [];
    
    let announcementsHTML = announcements.map(a => `
        <div class="announcement-item">
            <div class="announcement-icon" style="${a.icon === 'heart-pulse' ? 'background: rgba(16, 185, 129, 0.1); color: var(--color-success);' : ''}">
                <i data-lucide="${a.icon || 'megaphone'}"></i>
            </div>
            <div class="announcement-content">
                <h4>${a.title}</h4>
                <p>${a.content}</p>
            </div>
        </div>
    `).join('');

    if (announcements.length === 0) {
        announcementsHTML = `<p style="color: var(--color-text-secondary); padding: 1rem 0;">No new announcements.</p>`;
    }

    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('welcome')}</h1>
                <p class="page-subtitle">${t('welcome_sub')}</p>
            </div>
            ${isClockedIn 
                ? `<button class="btn-primary" style="background: var(--color-danger);" onclick="handleClockOut()">Clock Out</button>`
                : `<button class="btn-primary" onclick="handleClockIn()">${t('clock_in')}</button>`
            }
        </div>

        <div class="dashboard-grid">
            <!-- Quick Actions -->
            <div class="card col-span-8">
                <div class="card-title">${t('quick_actions')}</div>
                <div class="quick-action-grid">
                    <button class="action-btn" onclick="renderView('leave')">
                        <i data-lucide="calendar-plus"></i>
                        <span>${t('apply_leave')}</span>
                    </button>
                    ${isClockedIn 
                        ? `<button class="action-btn" onclick="handleClockOut()">
                             <i data-lucide="log-out"></i>
                             <span>Clock Out</span>
                           </button>`
                        : `<button class="action-btn" onclick="handleClockIn()">
                             <i data-lucide="clock"></i>
                             <span>${t('clock_in')}</span>
                           </button>`
                    }
                    <button class="action-btn" onclick="renderView('payroll')">
                        <i data-lucide="file-text"></i>
                        <span>${t('view_payslip')}</span>
                    </button>
                    <button class="action-btn" onclick="showToast(t('toast_doc_req'), 'info')">
                        <i data-lucide="folder-plus"></i>
                        <span>${t('req_doc')}</span>
                    </button>
                </div>
            </div>

            <!-- Leave Balances -->
            <div class="card col-span-4">
                <div class="card-title">${t('leave_balances')}</div>
                <div class="ring-container">
                    ${getRingSVG(65, 'var(--color-accent)', 'annual_leave')}
                    ${getRingSVG(80, 'var(--color-success)', 'sick_leave')}
                    ${getRingSVG(20, 'var(--color-warning)', 'unpaid_leave')}
                </div>
            </div>

            <!-- Announcements -->
            <div class="card col-span-12">
                <div class="card-title">${t('announcements')}</div>
                <div class="announcement-list">
                    ${announcementsHTML}
                </div>
            </div>
        </div>
    `;
}

// Render Time & Attendance
async function renderTime() {
    const punches = await db.fetchTimePunches(currentUserRole === 'ADMIN' ? null : currentUser?.id);
    
    let tableRows = punches.map(p => `
        <tr>
            <td>${new Date(p.punch_time).toLocaleDateString()}</td>
            <td>${new Date(p.punch_time).toLocaleTimeString()}</td>
            ${currentUserRole === 'ADMIN' ? `<td><span style="font-size: 0.75rem; color: var(--color-text-secondary);">${p.employee_id.substring(0,8)}...</span></td>` : ''}
            <td>${p.punch_type}</td>
            <td><span class="status-badge ${p.punch_type === 'IN' ? 'success' : 'info'}">${p.punch_type}</span></td>
        </tr>
    `).join('');
    
    if (punches.length === 0) {
        tableRows = `<tr><td colspan="4" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">No recent time punches.</td></tr>`;
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
            <table class="data-table">
                <thead>
                    <tr>
                        <th>${t('date')}</th>
                        <th>Time</th>
                        ${currentUserRole === 'ADMIN' ? '<th>Employee ID</th>' : ''}
                        <th>Punch Type</th>
                        <th>${t('status')}</th>
                    </tr>
                </thead>
                <tbody>
                    ${tableRows}
                </tbody>
            </table>
        </div>
    `;
}

async function renderLeave() {
    const profile = await db.getUserProfile(currentUser?.id);
    const requests = await db.fetchLeaveRequests(currentUser?.id);
    
    const approvedLeaves = requests.filter(r => r.status === 'APPROVED');
    let annualTaken = 0, sickTaken = 0, unpaidTaken = 0;
    
    approvedLeaves.forEach(r => {
        const start = new Date(r.start_date);
        const end = new Date(r.end_date);
        const days = Math.ceil((end - start) / (1000 * 60 * 60 * 24)) + 1;
        if(r.leave_type === 'Annual Leave') annualTaken += days;
        else if(r.leave_type === 'Sick Leave') sickTaken += days;
        else if(r.leave_type === 'Unpaid Leave') unpaidTaken += days;
    });

    const annualAllowance = profile.annual_leave_allowance || 30;
    const sickAllowance = profile.sick_leave_allowance || 10;
    
    let rowsHTML = requests.map(r => {
        let badgeClass = 'info';
        if (r.status === 'APPROVED') badgeClass = 'success';
        if (r.status === 'REJECTED') badgeClass = 'danger';
        
        return `
            <tr>
                <td><strong>${r.leave_type}</strong></td>
                <td>${new Date(r.start_date).toLocaleDateString()} to ${new Date(r.end_date).toLocaleDateString()}</td>
                <td><span class="status-badge ${badgeClass}">${r.status}</span></td>
            </tr>
        `;
    }).join('');
    
    if (requests.length === 0) {
        rowsHTML = `<tr><td colspan="3" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">No leave requests found.</td></tr>`;
    }

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
                <div style="font-size: 0.875rem; color: var(--color-text-secondary); margin-bottom: 0.5rem;">Annual Leave Balance</div>
                <div style="display: flex; justify-content: space-between; align-items: baseline;">
                    <h2 style="font-size: 2.5rem; margin: 0;">${Math.max(0, annualAllowance - annualTaken)} <span style="font-size: 1rem; color: var(--color-text-secondary);">/ ${annualAllowance} Days</span></h2>
                </div>
            </div>
            <div class="card col-span-4" style="border-top: 4px solid var(--color-success);">
                <div style="font-size: 0.875rem; color: var(--color-text-secondary); margin-bottom: 0.5rem;">Sick Leave Balance</div>
                <div style="display: flex; justify-content: space-between; align-items: baseline;">
                    <h2 style="font-size: 2.5rem; margin: 0;">${Math.max(0, sickAllowance - sickTaken)} <span style="font-size: 1rem; color: var(--color-text-secondary);">/ ${sickAllowance} Days</span></h2>
                </div>
            </div>
            <div class="card col-span-4" style="border-top: 4px solid var(--color-warning);">
                <div style="font-size: 0.875rem; color: var(--color-text-secondary); margin-bottom: 0.5rem;">Unpaid Leave Taken</div>
                <div style="display: flex; justify-content: space-between; align-items: baseline;">
                    <h2 style="font-size: 2.5rem; margin: 0;">${unpaidTaken} <span style="font-size: 1rem; color: var(--color-text-secondary);">Days</span></h2>
                </div>
            </div>
        </div>

        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-4">
                <div class="card-title">New Request</div>
                <form onsubmit="handleLeaveSubmit(event)">
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
                <div class="card-title">Request History</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>${t('leave_type')}</th>
                                <th>Dates</th>
                                <th>${t('status')}</th>
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
window.handleExpenseSubmit = async function(e) {
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
    reader.onload = async function(event) {
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

window.handleExpenseAction = async function(id, status, employeeId) {
    const { success } = await db.updateExpenseStatus(id, status);
    if (success) {
        showToast(`Expense ${status.toLowerCase()}`, "success");
        if(employeeId) await db.createNotification(employeeId, `Your expense request has been ${status}.`);
        renderView('expenses');
    }
}

async function renderExpenses() {
    const isManagerOrAdmin = currentUserRole === 'ADMIN' || currentUserRole === 'MANAGER';
    
    let expenses = [];
    if (currentUserRole === 'ADMIN') {
        expenses = await db.fetchExpenses(null);
    } else if (currentUserRole === 'MANAGER') {
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
                <h1 class="page-title">Expenses</h1>
                <p class="page-subtitle">Manage business expenses and reimbursements.</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-4">
                <div class="card-title">Submit New Expense</div>
                <form onsubmit="handleExpenseSubmit(event)">
                    <div class="form-group">
                        <label class="form-label">Amount ($)</label>
                        <input type="number" step="0.01" id="expAmount" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">Description</label>
                        <textarea id="expDesc" class="form-control" required></textarea>
                    </div>
                    <div class="form-group">
                        <label class="form-label">Receipt</label>
                        <input type="file" id="expReceipt" accept="image/*,application/pdf" class="form-control" required>
                    </div>
                    <button type="submit" class="btn-primary" style="width: 100%;">Submit Expense</button>
                </form>
            </div>
            
            <div class="card col-span-8">
                <div class="card-title">My Expenses</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead><tr><th>Description</th><th>Amount</th><th>Status</th><th>Receipt</th></tr></thead>
                        <tbody>
                            ${myExpenses.length === 0 ? '<tr><td colspan="4" style="text-align: center;">No expenses.</td></tr>' : myExpenses.map(e => `
                                <tr>
                                    <td>${e.description}</td>
                                    <td>$${e.amount.toFixed(2)}</td>
                                    <td><span class="status-badge ${e.status === 'APPROVED' ? 'success' : (e.status === 'REJECTED' ? 'danger' : 'warning')}">${e.status}</span></td>
                                    <td><a href="${e.receipt_base64}" download="receipt_${e.id}" class="btn-secondary" style="padding: 0.25rem 0.5rem; text-decoration: none; font-size: 0.75rem;">Download</a></td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
            
            ${isManagerOrAdmin ? `
            <div class="card col-span-12" style="margin-top: 1rem;">
                <div class="card-title">Team Expense Approvals</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead><tr><th>Employee ID</th><th>Description</th><th>Amount</th><th>Receipt</th><th>Actions</th></tr></thead>
                        <tbody>
                            ${pendingExpenses.length === 0 ? '<tr><td colspan="5" style="text-align: center;">No pending approvals.</td></tr>' : pendingExpenses.map(e => `
                                <tr>
                                    <td><span style="font-size: 0.75rem;">${e.employee_id.substring(0,8)}...</span></td>
                                    <td>${e.description}</td>
                                    <td>$${e.amount.toFixed(2)}</td>
                                    <td><a href="${e.receipt_base64}" download="receipt_${e.id}" class="btn-secondary" style="padding: 0.25rem 0.5rem; text-decoration: none; font-size: 0.75rem;">Download</a></td>
                                    <td>
                                        <button class="btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem;" onclick="handleExpenseAction('${e.id}', 'APPROVED', '${e.employee_id}')">Approve</button>
                                        <button class="btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; background: var(--color-danger);" onclick="handleExpenseAction('${e.id}', 'REJECTED', '${e.employee_id}')">Reject</button>
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
        return `<div class="page-header"><h1 class="page-title">Unauthorized</h1></div>`;
    }
    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">Analytics</h1>
                <p class="page-subtitle">Overview of company metrics.</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-6">
                <div class="card-title">Employee Growth</div>
                <canvas id="growthChart" width="400" height="200"></canvas>
            </div>
            <div class="card col-span-6">
                <div class="card-title">Leave Trends</div>
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
window.handleViewPayslip = function(month, netPay) {
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
            <td><button class="btn-secondary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem;">View Details</button></td>
        </tr>
    `).join('');
    
    let totalNet = payrolls.length > 0 ? payrolls[0].net_pay.toFixed(2) : '0.00';
    let extras = payrolls.length > 0 ? payrolls[0].overtime_pay.toFixed(2) : '0.00';
    let base = payrolls.length > 0 ? (payrolls[0].net_pay - payrolls[0].overtime_pay).toFixed(2) : '0.00';
    
    if (payrolls.length === 0) {
        rowsHTML = `<tr><td colspan="4" style="text-align: center; color: var(--color-text-secondary); padding: 2rem;">No payslips available.</td></tr>`;
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
                    <h3 style="color: rgba(255,255,255,0.8); margin: 0;">Latest Payslip</h3>
                    <i data-lucide="file-text" style="color: rgba(255,255,255,0.5);"></i>
                </div>
                <h1 style="font-size: 3rem; margin-bottom: 0.5rem;">$${totalNet}</h1>
                <div style="display: flex; justify-content: space-between; border-top: 1px solid rgba(255,255,255,0.1); padding-top: 1rem; margin-top: 1rem;">
                    <div>
                        <div style="font-size: 0.75rem; color: rgba(255,255,255,0.6);">Base Salary</div>
                        <div>$${base}</div>
                    </div>
                    <div style="text-align: right;">
                        <div style="font-size: 0.75rem; color: rgba(255,255,255,0.6);">Overtime/Bonus</div>
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
                                <th>Status</th>
                                <th>Actions</th>
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
        return `<div class="page-header"><h1 class="page-title">Unauthorized</h1></div>`;
    }
    
    const employees = await db.fetchAllEmployees();
    let pendingLeaves = await db.fetchAllPendingLeaves();
    
    if (currentUserRole === 'MANAGER') {
        const myTeamIds = employees.filter(e => e.manager_id === currentUser.id).map(e => e.id);
        pendingLeaves = pendingLeaves.filter(l => myTeamIds.includes(l.employee_id));
    }
    
    let leaveHTML = pendingLeaves.map(r => `
        <div style="display: flex; justify-content: space-between; align-items: center; padding: 1rem; border-bottom: 1px solid var(--color-border);">
            <div>
                <h4 style="margin-bottom: 4px;">${r.leave_type}</h4>
                <p style="font-size: 0.875rem; color: var(--color-text-secondary);">${new Date(r.start_date).toLocaleDateString()} - ${new Date(r.end_date).toLocaleDateString()}</p>
                <p style="font-size: 0.75rem; color: var(--color-text-secondary); margin-top: 4px;">Employee ID: ${r.employee_id.substring(0,8)}...</p>
            </div>
            <div style="display: flex; gap: 8px;">
                <button class="btn-primary" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;" onclick="handleLeaveAction('${r.id}', 'APPROVED', '${r.employee_id}')">Approve</button>
                <button class="btn-primary" style="padding: 0.25rem 0.75rem; font-size: 0.75rem; background: var(--color-danger);" onclick="handleLeaveAction('${r.id}', 'REJECTED', '${r.employee_id}')">Reject</button>
            </div>
        </div>
    `).join('');

    if (pendingLeaves.length === 0) {
        leaveHTML = `<p style="padding: 1rem; color: var(--color-text-secondary);">No pending leave requests.</p>`;
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
                <h4>Manage Tasks</h4>
            </div>
            <div class="card col-span-3" style="text-align: center; cursor: pointer;" onclick="renderView('time')">
                <i data-lucide="clock" style="margin-bottom: 0.5rem; color: var(--color-primary); width: 24px; height: 24px;"></i>
                <h4>Time Reports</h4>
            </div>
            <div class="card col-span-3" style="text-align: center; cursor: pointer;" onclick="renderView('users')">
                <i data-lucide="users" style="margin-bottom: 0.5rem; color: var(--color-primary); width: 24px; height: 24px;"></i>
                <h4>Employee Directory</h4>
            </div>
            <div class="card col-span-3" style="text-align: center; cursor: pointer;" onclick="renderView('documents')">
                <i data-lucide="file-text" style="margin-bottom: 0.5rem; color: var(--color-primary); width: 24px; height: 24px;"></i>
                <h4>Documents</h4>
            </div>
        </div>

        <div class="dashboard-grid">
            <div class="card col-span-4">
                <div class="card-title">${t('headcount')} <i data-lucide="users"></i></div>
                <h2 style="font-size: 2.5rem; margin-top: 10px;">${employees.length}</h2>
                <p style="color: var(--color-success); font-size: 0.875rem;">Registered Users</p>
            </div>
            
            <div class="card col-span-4">
                <div class="card-title">Pending Approvals <i data-lucide="inbox"></i></div>
                <h2 style="font-size: 2.5rem; margin-top: 10px;">${pendingLeaves.length}</h2>
                <p style="color: var(--color-warning); font-size: 0.875rem;">Requires attention</p>
            </div>
            
            <div class="card col-span-8">
                <div class="card-title">Leave Approvals Inbox</div>
                <div style="max-height: 300px; overflow-y: auto;">
                    ${leaveHTML}
                </div>
            </div>
            
            <div class="card col-span-12">
                <div class="card-title">Employee Directory</div>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>User ID</th>
                            <th>Role</th>
                            <th>Join Date</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${employees.map(e => `
                            <tr>
                                <td>${e.id}</td>
                                <td><span class="status-badge ${e.role === 'ADMIN' ? 'success' : 'info'}">${e.role}</span></td>
                                <td>${new Date(e.created_at).toLocaleDateString()}</td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            </div>
        </div>
    `;
}

// Render User Management (Admin Only)
window.handleCreateUser = async function(e) {
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
        renderView('users');
    } else {
        showToast(error.message || "Failed to create user", 'danger');
    }
}

window.handleChangeRole = async function(id, role) {
    const { success } = await db.updateUserRole(id, role);
    if (success) {
        showToast("Role updated", "success");
        renderView('users');
    }
}

window.handleChangeJobTitle = async function(id, jobTitle) {
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
                <p class="page-subtitle">Manage employee accounts and permissions.</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-4">
                <div class="card-title">Add New Employee <i data-lucide="user-plus"></i></div>
                <form onsubmit="handleCreateUser(event)">
                    <div class="form-group">
                        <label class="form-label">Full Name</label>
                        <input type="text" id="newFullName" class="form-control" placeholder="e.g. John Doe">
                    </div>
                    <div class="form-group">
                        <label class="form-label">Iqama Number</label>
                        <input type="text" id="newIqama" class="form-control" placeholder="e.g. 2xxxxxxxxx">
                    </div>
                    <div class="form-group">
                        <label class="form-label">Phone Number</label>
                        <input type="text" id="newPhone" class="form-control" placeholder="e.g. +9665xxxxxxx">
                    </div>
                    <div class="form-group">
                        <label class="form-label">Email</label>
                        <input type="email" id="newEmail" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">Temporary Password</label>
                        <input type="password" id="newPassword" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">Job Title</label>
                        <input type="text" id="newJobTitle" class="form-control" placeholder="e.g. Software Engineer">
                    </div>
                    <div class="form-group">
                        <label class="form-label">Role</label>
                        <select id="newRole" class="form-control">
                            <option value="EMPLOYEE">Employee</option>
                            <option value="MANAGER">Manager</option>
                            <option value="ADMIN">Admin</option>
                        </select>
                    </div>
                    <button type="submit" class="btn-primary" style="width: 100%;">Create Account</button>
                </form>
            </div>
            <div class="card col-span-8">
                <div class="card-title">Employee Directory</div>
                <div style="overflow-x: auto;">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Employee Details</th>
                                <th>Role</th>
                                <th>Job Title</th>
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
                                            ID: <span title="${u.id}">${u.id.substring(0,8)}...</span><br/>
                                            Iqama: ${u.iqama_number || 'N/A'}<br/>
                                            Phone: ${u.phone_number || 'N/A'}
                                        </div>
                                    </td>
                                    <td><span class="status-badge ${u.role === 'ADMIN' ? 'success' : 'info'}">${u.role}</span></td>
                                    <td>
                                        <input type="text" class="form-control" style="width: 160px; padding: 0.25rem; font-size: 0.8rem;" value="${u.job_title || ''}" placeholder="Job Title" onblur="handleChangeJobTitle('${u.id}', this.value)">
                                    </td>
                                    <td>
                                        <select class="form-control" style="width: auto; padding: 0.25rem;" onchange="handleChangeRole('${u.id}', this.value)">
                                            <option value="EMPLOYEE" ${u.role === 'EMPLOYEE' ? 'selected' : ''}>Employee</option>
                                            <option value="MANAGER" ${u.role === 'MANAGER' ? 'selected' : ''}>Manager</option>
                                            <option value="ADMIN" ${u.role === 'ADMIN' ? 'selected' : ''}>Admin</option>
                                        </select>
                                    </td>
                                    <td>
                                        <select class="form-control" style="width: auto; padding: 0.25rem;" onchange="handleAssignManager('${u.id}', this.value)">
                                            <option value="">No Manager</option>
                                            ${users.filter(m => m.role === 'MANAGER' || m.role === 'ADMIN').map(m => `<option value="${m.id}" ${u.manager_id === m.id ? 'selected' : ''}>${m.job_title || 'Mgr'}</option>`).join('')}
                                        </select>
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

window.handleAssignManager = async function(id, managerId) {
    const { success } = await db.assignManager(id, managerId);
    if (success) {
        showToast("Manager assigned", "success");
        renderView('users');
    }
}

// Render Performance
async function renderPerformance() {
    const goals = await db.fetchGoals(currentUserRole === 'ADMIN' ? null : currentUser.id);
    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('nav_performance')}</h1>
                <p class="page-subtitle">Track your KPIs and goals.</p>
            </div>
        </div>
        <div class="card fade-in-up">
            <div class="card-title">My Goals</div>
            <table class="data-table">
                <thead><tr><th>Title</th><th>Due Date</th><th>Status</th><th>Rating</th></tr></thead>
                <tbody>
                    ${goals.length === 0 ? '<tr><td colspan="4">No goals assigned yet.</td></tr>' : goals.map(g => `
                        <tr>
                            <td>${g.title}</td>
                            <td>${new Date(g.due_date).toLocaleDateString()}</td>
                            <td><span class="status-badge info">${g.status}</span></td>
                            <td>${g.rating || '-'} / 5</td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
    `;
}

// Render Documents
window.handleDocSubmit = async function(e) {
    e.preventDefault();
    const type = document.getElementById('docType').value;
    const purpose = document.getElementById('docPurpose').value;
    const { success } = await db.requestDocument(currentUser.id, type, purpose);
    if(success) {
        showToast("Document requested", "success");
        renderView('documents');
    }
}

window.handleEmployeeDocUpload = async function(e) {
    e.preventDefault();
    const docType = document.getElementById('empDocType').value;
    const fileInput = document.getElementById('empDocFile');
    if (!fileInput.files || fileInput.files.length === 0) return;
    
    const file = fileInput.files[0];
    const docName = file.name;
    const reader = new FileReader();
    reader.onload = async function(event) {
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
    const docs = await db.fetchDocuments(currentUserRole === 'ADMIN' ? null : currentUser.id);
    const uploadedDocs = await db.fetchEmployeeDocuments(currentUserRole === 'ADMIN' ? null : currentUser.id);

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">${t('nav_documents')}</h1>
                <p class="page-subtitle">Upload official documents or request HR letters.</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <!-- Upload Official Document -->
            <div class="card col-span-4">
                <div class="card-title">Upload Official Document</div>
                <form onsubmit="handleEmployeeDocUpload(event)">
                    <div class="form-group">
                        <label class="form-label">Document Type</label>
                        <select id="empDocType" class="form-control">
                            <option value="Passport">Passport</option>
                            <option value="Iqama">Iqama</option>
                            <option value="Contract">Contract</option>
                            <option value="Certificate">Certificate</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label class="form-label">File</label>
                        <input type="file" id="empDocFile" accept="image/*,application/pdf" class="form-control" required>
                    </div>
                    <button type="submit" class="btn-primary" style="width: 100%;">Upload Document</button>
                </form>
            </div>
            
            <div class="card col-span-8">
                <div class="card-title">${currentUserRole === 'ADMIN' ? 'All Uploaded Documents' : 'My Uploaded Documents'}</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead><tr><th>Type</th><th>File Name</th><th>Date</th><th>Actions</th></tr></thead>
                        <tbody>
                            ${uploadedDocs.length === 0 ? '<tr><td colspan="4" style="text-align: center; color: var(--color-text-secondary); padding: 1rem;">No uploaded documents.</td></tr>' : uploadedDocs.map(d => `
                                <tr>
                                    <td><span class="status-badge info">${d.doc_type}</span></td>
                                    <td>${d.doc_name}</td>
                                    <td>${new Date(d.created_at).toLocaleDateString()}</td>
                                    <td><a href="${d.doc_base64}" download="${d.doc_name}" class="btn-secondary" style="padding: 0.25rem 0.5rem; text-decoration: none; font-size: 0.75rem;">Download</a></td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- HR Letter Requests -->
            <div class="card col-span-4">
                <div class="card-title">Request Letter</div>
                <form onsubmit="handleDocSubmit(event)">
                    <div class="form-group">
                        <label class="form-label">Document Type</label>
                        <select id="docType" class="form-control">
                            <option value="Salary Certificate">Salary Certificate</option>
                            <option value="NOC">NOC (No Objection Certificate)</option>
                            <option value="Employment Letter">Employment Letter</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label class="form-label">Purpose</label>
                        <textarea id="docPurpose" class="form-control" required></textarea>
                    </div>
                    <button type="submit" class="btn-secondary" style="width: 100%;">Submit Request</button>
                </form>
            </div>
            <div class="card col-span-8">
                <div class="card-title">${currentUserRole === 'ADMIN' ? 'All Letter Requests' : 'My Requests'}</div>
                <div class="table-responsive">
                    <table class="data-table">
                        <thead><tr><th>Type</th><th>Purpose</th><th>Status</th><th>Date</th></tr></thead>
                        <tbody>
                            ${docs.length === 0 ? '<tr><td colspan="4" style="text-align: center; color: var(--color-text-secondary); padding: 1rem;">No requests found.</td></tr>' : docs.map(d => `
                                <tr>
                                    <td>${d.doc_type}</td>
                                    <td>${d.purpose.substring(0, 30)}...</td>
                                    <td><span class="status-badge ${d.status === 'PENDING' ? 'warning' : 'success'}">${d.status}</span></td>
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
async function renderProfile() {
    const profile = await db.getUserProfile(currentUser.id);
    const avatar = profile.avatar_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(currentUser.email.split('@')[0])}&background=007AFF&color=fff`;
    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('nav_profile')}</h1>
                <p class="page-subtitle">Manage your account settings.</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-4" style="text-align: center;">
                <img src="${avatar}" style="width: 120px; height: 120px; border-radius: 50%; object-fit: cover; margin-bottom: 1rem; border: 4px solid var(--color-border);" />
                <h3>${currentUser.email}</h3>
                <p style="color: var(--color-text-secondary); margin-bottom: 2rem;">${currentUserRole}</p>
                <form onsubmit="handleUpdateProfilePhoto(event)" style="margin-bottom: 2rem;">
                    <input type="file" id="avatarFile" accept="image/*" class="form-control" style="margin-bottom: 1rem;" required>
                    <button type="submit" class="btn-secondary" style="width: 100%;">Upload Photo</button>
                </form>
            </div>
            <div class="card col-span-8">
                <div class="card-title">Change Password</div>
                <form onsubmit="handleUpdatePassword(event)">
                    <div class="form-group">
                        <label class="form-label">New Password</label>
                        <input type="password" id="newPassword" class="form-control" required minlength="6">
                    </div>
                    <button type="submit" class="btn-primary">Update Password</button>
                </form>
            </div>
        </div>
    `;
}

window.handleUpdateProfilePhoto = async function(e) {
    e.preventDefault();
    const fileInput = document.getElementById('avatarFile');
    if (!fileInput.files || fileInput.files.length === 0) return;
    
    const file = fileInput.files[0];
    const reader = new FileReader();
    reader.onload = async function(event) {
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

window.handleUpdatePassword = async function(e) {
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

async function renderTasks() {
    let tasks = [];
    if (currentUserRole === 'ADMIN' || currentUserRole === 'MANAGER') {
        tasks = await db.fetchTasks(); // The manager fetchTasks will rely on RLS policies to restrict, or we filter here
    } else {
        tasks = await db.fetchTasks(currentUser.id);
    }
    
    // In db.js, fetchTasks uses 'or(assignee_id.eq,created_by.eq)' if userId is passed. If null, it gets all visible.
    // Let's filter to just the manager's created tasks + assigned to them just to be safe if RLS doesn't restrict.
    if (currentUserRole === 'MANAGER') {
        let users = await db.fetchUsers();
        let teamIds = users.filter(u => u.manager_id === currentUser.id).map(u => u.id);
        teamIds.push(currentUser.id);
        tasks = tasks.filter(t => teamIds.includes(t.assignee_id) || t.created_by === currentUser.id);
    }

    const todo = tasks.filter(t => t.status === 'TODO');
    const inProgress = tasks.filter(t => t.status === 'IN_PROGRESS');
    const done = tasks.filter(t => t.status === 'DONE');
    
    let adminForm = '';
    if (currentUserRole === 'ADMIN' || currentUserRole === 'MANAGER') {
        let users = await db.fetchUsers();
        if (currentUserRole === 'MANAGER') {
            users = users.filter(u => u.manager_id === currentUser.id || u.id === currentUser.id);
        }
        const userOptions = users.map(u => {
            const label = u.job_title || u.id.substring(0,8);
            return `<option value="${u.id}">${label} (${u.role})</option>`;
        }).join('');
        
        adminForm = `
            <div class="card col-span-12" style="margin-bottom: 1rem;">
                <div class="card-title">Assign New Task</div>
                <form onsubmit="handleCreateTask(event)" style="display: flex; gap: 1rem; align-items: flex-end;">
                    <div class="form-group" style="flex: 2;">
                        <label class="form-label">Task Title</label>
                        <input type="text" id="taskTitle" class="form-control" required>
                    </div>
                    <div class="form-group" style="flex: 2;">
                        <label class="form-label">Assign To</label>
                        <select id="taskAssignee" class="form-control" required>
                            <option value="">Select Employee</option>
                            ${userOptions}
                        </select>
                    </div>
                    <div class="form-group" style="flex: 1;">
                        <label class="form-label">Due Date</label>
                        <input type="date" id="taskDue" class="form-control" required>
                    </div>
                    <button type="submit" class="btn-primary" style="margin-bottom: 1rem;">Assign Task</button>
                </form>
            </div>
        `;
    }
    
    function renderTaskCard(t) {
        return `
            <div class="card" style="padding: 1rem; margin-bottom: 1rem; border-left: 4px solid var(--color-primary); box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);">
                <h4 style="margin-bottom: 0.5rem; font-size: 1rem;">${t.title}</h4>
                <div style="font-size: 0.75rem; color: var(--color-text-secondary); margin-bottom: 1rem;">
                    <i data-lucide="calendar" style="width: 12px; height: 12px; display: inline-block;"></i> Due: ${t.due_date || 'No date'}<br/>
                    <i data-lucide="user" style="width: 12px; height: 12px; display: inline-block;"></i> Assigned: ${t.assignee?.email?.split('@')[0] || 'Unknown'}
                </div>
                <div style="display: flex; gap: 0.5rem; justify-content: flex-end;">
                    ${t.status !== 'TODO' ? `<button class="btn-secondary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem;" onclick="handleUpdateTaskStatus('${t.id}', 'TODO')">To Do</button>` : ''}
                    ${t.status !== 'IN_PROGRESS' ? `<button class="btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; background: var(--color-warning);" onclick="handleUpdateTaskStatus('${t.id}', 'IN_PROGRESS')">Working</button>` : ''}
                    ${t.status !== 'DONE' ? `<button class="btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; background: var(--color-success);" onclick="handleUpdateTaskStatus('${t.id}', 'DONE')">Done</button>` : ''}
                </div>
            </div>
        `;
    }

    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('nav_tasks')}</h1>
                <p class="page-subtitle">Track projects and manage team tasks.</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            ${adminForm}
            <div class="col-span-4">
                <div class="card" style="background: rgba(0,0,0,0.02);">
                    <div class="card-title">To Do <span class="badge" style="float: right;">${todo.length}</span></div>
                    ${todo.map(renderTaskCard).join('')}
                    ${todo.length === 0 ? '<p style="text-align: center; color: var(--color-text-secondary); font-size: 0.875rem;">No tasks in this list</p>' : ''}
                </div>
            </div>
            <div class="col-span-4">
                <div class="card" style="background: rgba(245, 158, 11, 0.05);">
                    <div class="card-title">In Progress <span class="badge" style="float: right; background: var(--color-warning); color: #fff;">${inProgress.length}</span></div>
                    ${inProgress.map(renderTaskCard).join('')}
                    ${inProgress.length === 0 ? '<p style="text-align: center; color: var(--color-text-secondary); font-size: 0.875rem;">No tasks in this list</p>' : ''}
                </div>
            </div>
            <div class="col-span-4">
                <div class="card" style="background: rgba(16, 185, 129, 0.05);">
                    <div class="card-title">Done <span class="badge" style="float: right; background: var(--color-success); color: #fff;">${done.length}</span></div>
                    ${done.map(renderTaskCard).join('')}
                    ${done.length === 0 ? '<p style="text-align: center; color: var(--color-text-secondary); font-size: 0.875rem;">No tasks in this list</p>' : ''}
                </div>
            </div>
        </div>
    `;
}

window.handleCreateTask = async function(e) {
    e.preventDefault();
    const title = document.getElementById('taskTitle').value;
    const assignee = document.getElementById('taskAssignee').value;
    const due = document.getElementById('taskDue').value;
    
    const { success, error } = await db.createTask(title, '', assignee, due, currentUser.id);
    if (success) {
        showToast("Task assigned successfully!", "success");
        renderView('tasks');
    } else {
        showToast("Failed to create task", "danger");
    }
}

window.handleUpdateTaskStatus = async function(taskId, status) {
    const { success } = await db.updateTaskStatus(taskId, status);
    if (success) {
        showToast(`Task moved to ${status}`, "success");
        renderView('tasks');
    }
}

// Router
// ==========================================
// Employees & Contracts (HR View)
// ==========================================
window.showContractModal = async function(employeeId, empName) {
    document.getElementById('contractEmpName').textContent = empName;
    document.getElementById('contractEmployeeId').value = employeeId;
    
    // Clear form
    document.getElementById('contractType').value = 'Full-time';
    document.getElementById('contractStartDate').value = '';
    document.getElementById('contractEndDate').value = '';
    document.getElementById('contractSalary').value = '';
    document.getElementById('contractStatus').value = 'Active';

    // Fetch existing contract
    const contract = await db.fetchContractByEmployeeId(employeeId);
    if (contract) {
        document.getElementById('contractType').value = contract.contract_type || 'Full-time';
        document.getElementById('contractStartDate').value = contract.start_date || '';
        document.getElementById('contractEndDate').value = contract.end_date || '';
        document.getElementById('contractSalary').value = contract.salary || '';
        document.getElementById('contractStatus').value = contract.status || 'Active';
    }

    document.getElementById('contractModal').style.display = 'block';
}

window.closeContractModal = function() {
    document.getElementById('contractModal').style.display = 'none';
}

window.handleSaveContract = async function(e) {
    e.preventDefault();
    const employeeId = document.getElementById('contractEmployeeId').value;
    const contractData = {
        employee_id: employeeId,
        contract_type: document.getElementById('contractType').value,
        start_date: document.getElementById('contractStartDate').value,
        end_date: document.getElementById('contractEndDate').value || null,
        salary: document.getElementById('contractSalary').value || null,
        status: document.getElementById('contractStatus').value
    };

    const { success, error } = await db.upsertContract(contractData);
    if (success) {
        showToast("Contract saved successfully", "success");
        closeContractModal();
        renderView('employees');
    } else {
        showToast(error?.message || "Failed to save contract", "danger");
    }
}

async function renderEmployeesDirectory() {
    if (currentUserRole !== 'ADMIN' && currentUserRole !== 'MANAGER') {
        return '<div style="padding: 2rem;">Unauthorized. Only Admins and Managers can view the Employee Directory.</div>';
    }

    const users = await db.fetchUsers();

    // Only Admins or the Manager themselves can see team members' contracts
    // For now, let's allow ADMIN to see all, Manager to see their team
    let visibleUsers = users;
    if (currentUserRole === 'MANAGER') {
        visibleUsers = users.filter(u => u.manager_id === currentUser.id || u.id === currentUser.id);
    }

    return `
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">Employees & Contracts</h1>
                <p class="page-subtitle">Directory of personnel and their contract details.</p>
            </div>
        </div>
        <div class="dashboard-grid fade-in-up">
            <div class="card col-span-12">
                <div class="card-title">Company Directory</div>
                <div style="overflow-x: auto;">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Employee Name</th>
                                <th>Contact Info</th>
                                <th>Role / Title</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${visibleUsers.map(u => `
                                <tr>
                                    <td>
                                        <div style="font-weight: bold; color: var(--primary-color);">EMP-${u.emp_index || '-'}</div>
                                        <div style="font-weight: 600;">${u.full_name || 'N/A'}</div>
                                    </td>
                                    <td>
                                        <div style="font-size: 0.85rem;">
                                            <i data-lucide="mail" style="width:12px;height:12px;margin-right:4px;vertical-align:middle;"></i> ${u.id}<br/>
                                            <i data-lucide="phone" style="width:12px;height:12px;margin-right:4px;vertical-align:middle;"></i> ${u.phone_number || 'N/A'}<br/>
                                            <i data-lucide="credit-card" style="width:12px;height:12px;margin-right:4px;vertical-align:middle;"></i> ${u.iqama_number || 'N/A'}
                                        </div>
                                    </td>
                                    <td>
                                        <span class="status-badge ${u.role === 'ADMIN' ? 'success' : (u.role === 'MANAGER' ? 'warning' : 'info')}">${u.role}</span><br/>
                                        <span style="font-size: 0.85rem; color: var(--text-light); margin-top: 4px; display: inline-block;">${u.job_title || 'No Title'}</span>
                                    </td>
                                    <td>
                                        <button class="btn-secondary" style="padding: 0.4rem 0.8rem; font-size: 0.8rem;" onclick="showContractModal('${u.id}', '${(u.full_name || 'Employee').replace(/'/g, "\\'")}')">
                                            <i data-lucide="file-signature" style="width:14px;height:14px;margin-right:4px;"></i> Contract
                                        </button>
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <!-- Contract Modal -->
        <div id="contractModal" class="modal">
            <div class="modal-content" style="max-width: 500px;">
                <div class="modal-header">
                    <h2>Contract: <span id="contractEmpName" style="color: var(--primary-color);"></span></h2>
                    <button class="icon-btn" onclick="closeContractModal()"><i data-lucide="x"></i></button>
                </div>
                <form onsubmit="handleSaveContract(event)" style="margin-top: 1.5rem;">
                    <input type="hidden" id="contractEmployeeId">
                    <div class="form-group">
                        <label class="form-label">Contract Type</label>
                        <select id="contractType" class="form-control" required>
                            <option value="Full-time">Full-time</option>
                            <option value="Part-time">Part-time</option>
                            <option value="Contractor">Contractor</option>
                            <option value="Freelance">Freelance</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label class="form-label">Start Date</label>
                        <input type="date" id="contractStartDate" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">End Date (Optional)</label>
                        <input type="date" id="contractEndDate" class="form-control">
                    </div>
                    <div class="form-group">
                        <label class="form-label">Salary (Monthly)</label>
                        <input type="number" id="contractSalary" class="form-control" step="0.01">
                    </div>
                    <div class="form-group">
                        <label class="form-label">Status</label>
                        <select id="contractStatus" class="form-control" required>
                            <option value="Active">Active</option>
                            <option value="Terminated">Terminated</option>
                            <option value="Expired">Expired</option>
                        </select>
                    </div>
                    <div style="display: flex; gap: 1rem; margin-top: 2rem;">
                        <button type="button" class="btn-secondary" style="flex: 1;" onclick="closeContractModal()">Cancel</button>
                        <button type="submit" class="btn-primary" style="flex: 1;">Save Contract</button>
                    </div>
                </form>
            </div>
        </div>
    `;
}

async function renderView(viewId) {
    if (!currentUser && viewId !== 'login') {
        viewId = 'login';
        currentView = 'login';
    }

    let content = '';
    
    // Add loading state
    if (viewId !== 'login') {
        viewContainer.innerHTML = `<div style="display:flex; justify-content:center; padding: 4rem; color: var(--color-primary);"><i data-lucide="loader" class="spin"></i></div>`;
        lucide.createIcons();
    }
    
    switch(viewId) {
        case 'login':
            content = renderLogin();
            break;
        case 'dashboard':
            content = await renderDashboard();
            break;
        case 'time':
            content = await renderTime();
            break;
        case 'leave':
            content = await renderLeave();
            break;
        case 'payroll':
            content = await renderPayroll();
            break;
        case 'expenses':
            content = await renderExpenses();
            break;
        case 'analytics':
            content = await renderAnalytics();
            break;
        case 'admin':
            content = await renderAdmin();
            break;
        case 'users':
            content = await renderUsers();
            break;
        case 'employees':
            content = await renderEmployeesDirectory();
            break;
        case 'performance':
            content = await renderPerformance();
            break;
        case 'documents':
            content = await renderDocuments();
            break;
        case 'profile':
            content = await renderProfile();
            break;
        case 'tasks':
            content = await renderTasks();
            break;
        default:
            content = `
                <div class="page-header">
                    <h1 class="page-title">${t('nav_' + viewId) || 'Coming Soon'}</h1>
                </div>
                <div class="card" style="min-height: 400px; display: flex; align-items: center; justify-content: center;">
                    <div style="text-align: center; color: var(--color-text-secondary);">
                        <i data-lucide="hammer" style="width: 48px; height: 48px; margin-bottom: 1rem;"></i>
                        <h2>Module under construction</h2>
                    </div>
                </div>
            `;
    }
    
    viewContainer.innerHTML = content;
    lucide.createIcons();
    
    if (viewId === 'analytics') {
        setTimeout(initCharts, 100);
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
            dropdown.innerHTML = `<div style="padding: 1rem; text-align: center; color: var(--color-text-secondary);">No notifications</div>`;
        } else {
            dropdown.innerHTML = notifs.map(n => `
                <div class="notification-item ${!n.is_read ? 'unread' : ''}" style="padding: 10px; border-bottom: 1px solid var(--color-border); ${!n.is_read ? 'background: rgba(var(--color-primary-rgb), 0.05); font-weight: 500;' : ''}">
                    <div style="font-size: 0.875rem;">${n.message}</div>
                    <div style="font-size: 0.75rem; color: var(--color-text-secondary); margin-top: 4px;">${new Date(n.created_at).toLocaleDateString()}</div>
                </div>
            `).join('');
        }
    }
}

window.toggleNotifications = async function() {
    const dropdown = document.getElementById('notificationsDropdown');
    if (!dropdown) return;
    dropdown.classList.toggle('show');
    
    if (dropdown.classList.contains('show')) {
        await db.markNotificationsRead(currentUser.id);
        const badge = document.querySelector('.notification-badge');
        if(badge) badge.style.display = 'none';
        pollNotifications(); // Refresh list to show as read
    }
}

// Init
async function initApp() {
    updateTranslations();
    
    // Check for existing session
    const { data: { session } } = await db.getSession();
    
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
        
        if (adminNav) adminNav.style.display = currentUserRole === 'ADMIN' ? 'flex' : 'none';
        if (usersNav) usersNav.style.display = currentUserRole === 'ADMIN' ? 'flex' : 'none';
        if (analyticsNav) analyticsNav.style.display = (currentUserRole === 'ADMIN' || currentUserRole === 'MANAGER') ? 'flex' : 'none';
        if (employeesNav) employeesNav.style.display = (currentUserRole === 'ADMIN' || currentUserRole === 'MANAGER') ? 'flex' : 'none';
        
        currentView = currentUserRole === 'ADMIN' ? 'admin' : 'dashboard';
        
        pollNotifications();
        if(notificationsInterval) clearInterval(notificationsInterval);
        notificationsInterval = setInterval(pollNotifications, 60000);
    } else {
        currentView = 'login';
    }
    
    renderView(currentView);
}

initApp();
