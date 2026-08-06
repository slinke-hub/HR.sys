// App State
let currentLang = 'en';
let currentTheme = 'light';
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
    const success = await db.clockIn();
    const now = new Date().toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
    if (success) {
        showToast(t('toast_clock_in') + ' ' + now, 'success');
    } else {
        showToast("Error clocking in. Check DB connection.", "danger");
    }
}

window.handleLoginSubmit = async function(e) {
    e.preventDefault();
    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;
    
    const { user, error } = await db.login(email, password);
    
    if (error || !user) {
        showToast(t('invalid_credentials'), 'danger');
        return;
    }
    
    currentUser = user;
    const profile = await db.getUserProfile(user.id);
    currentUserRole = profile.role;
    
    // Show sidebar and topbar again
    document.getElementById('sidebar').style.display = 'block';
    document.querySelector('.topbar').style.display = 'flex';
    
    // Route based on role
    if (currentUserRole === 'ADMIN') {
        currentView = 'admin';
    } else {
        currentView = 'dashboard';
    }
    renderView(currentView);
}

// Render Login View
function renderLogin() {
    // Hide sidebar and topbar for full screen login
    const sidebar = document.getElementById('sidebar');
    const topbar = document.querySelector('.topbar');
    if (sidebar) sidebar.style.display = 'none';
    if (topbar) topbar.style.display = 'none';
    
    return `
        <div style="display: flex; height: 100vh; align-items: center; justify-content: center; width: 100vw; position: fixed; top: 0; left: 0; background: var(--color-bg); z-index: 9999;">
            <div class="card" style="width: 100%; max-width: 400px; padding: 2.5rem 2rem; box-shadow: 0 20px 40px rgba(0,0,0,0.1);">
                <div style="text-align: center; margin-bottom: 2rem;">
                    <div style="font-size: 2.5rem; color: var(--color-primary); font-weight: 800; letter-spacing: -1px; margin-bottom: 0.5rem;">MUQAM</div>
                    <h2 style="margin-top: 1rem; font-size: 1.25rem;">${t('login_title')}</h2>
                    <p style="color: var(--color-text-secondary); font-size: 0.875rem;">${t('login_subtitle')}</p>
                </div>
                <form onsubmit="handleLoginSubmit(event)">
                    <div class="form-group">
                        <label class="form-label">${t('email_label')}</label>
                        <input type="email" id="email" class="form-control" placeholder="name@company.com" required>
                    </div>
                    <div class="form-group" style="margin-bottom: 1.5rem;">
                        <label class="form-label">${t('password_label')}</label>
                        <input type="password" id="password" class="form-control" placeholder="••••••••" required>
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
function renderDashboard() {
    const now = new Date().toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('welcome')}</h1>
                <p class="page-subtitle">${t('welcome_sub')}</p>
            </div>
            <button class="btn-primary" onclick="handleClockIn()">${t('clock_in')}</button>
        </div>

        <div class="dashboard-grid">
            <!-- Quick Actions -->
            <div class="card col-span-8">
                <div class="card-title">${t('quick_actions')}</div>
                <div class="quick-action-grid">
                    <button class="action-btn" onclick="showToast(t('toast_leave_applied'), 'info')">
                        <i data-lucide="calendar-plus"></i>
                        <span>${t('apply_leave')}</span>
                    </button>
                    <button class="action-btn" onclick="handleClockIn()">
                        <i data-lucide="clock"></i>
                        <span>${t('clock_in')}</span>
                    </button>
                    <button class="action-btn" onclick="showToast(t('toast_payslip'), 'info')">
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
                    <div class="announcement-item">
                        <div class="announcement-icon">
                            <i data-lucide="megaphone"></i>
                        </div>
                        <div class="announcement-content">
                            <h4>Q3 Townhall Meeting</h4>
                            <p>Join us this Friday for the quarterly company update. Location: Main Auditorium & Zoom.</p>
                        </div>
                    </div>
                    <div class="announcement-item">
                        <div class="announcement-icon" style="background: rgba(16, 185, 129, 0.1); color: var(--color-success);">
                            <i data-lucide="heart-pulse"></i>
                        </div>
                        <div class="announcement-content">
                            <h4>New Wellness Benefits Added</h4>
                            <p>We've added gym memberships to our health coverage. Check your benefits portal.</p>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    `;
}

// Render Time & Attendance
function renderTime() {
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
                        <th>${t('in')}</th>
                        <th>${t('out')}</th>
                        <th>${t('hours')}</th>
                        <th>${t('status')}</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td>Mon, Aug 03</td>
                        <td>09:00 AM</td>
                        <td>05:00 PM</td>
                        <td>8h 00m</td>
                        <td><span class="status-badge success">On Time</span></td>
                    </tr>
                    <tr>
                        <td>Tue, Aug 04</td>
                        <td>09:15 AM</td>
                        <td>05:30 PM</td>
                        <td>8h 15m</td>
                        <td><span class="status-badge warning">Late In</span></td>
                    </tr>
                    <tr>
                        <td>Wed, Aug 05</td>
                        <td>08:50 AM</td>
                        <td>05:00 PM</td>
                        <td>8h 10m</td>
                        <td><span class="status-badge success">On Time</span></td>
                    </tr>
                </tbody>
            </table>
        </div>
    `;
}

// Render Leave Management
function renderLeave() {
    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('nav_leave')}</h1>
                <p class="page-subtitle">${t('leave_req_sub')}</p>
            </div>
        </div>
        <div class="dashboard-grid">
            <div class="card col-span-5">
                <div class="card-title">${t('leave_req')}</div>
                <div class="form-group">
                    <label class="form-label">${t('leave_type')}</label>
                    <select class="form-control">
                        <option>${t('annual_leave')}</option>
                        <option>${t('sick_leave')}</option>
                        <option>${t('unpaid_leave')}</option>
                    </select>
                </div>
                <div class="form-group">
                    <label class="form-label">${t('start_date')}</label>
                    <input type="date" class="form-control">
                </div>
                <div class="form-group">
                    <label class="form-label">${t('end_date')}</label>
                    <input type="date" class="form-control">
                </div>
                <div class="form-group">
                    <label class="form-label">${t('reason')}</label>
                    <textarea class="form-control"></textarea>
                </div>
                <button class="btn-primary" style="width: 100%" onclick="showToast(t('toast_leave_applied'), 'success')">${t('submit')}</button>
            </div>
            
            <div class="card col-span-7">
                <div class="card-title">${t('pending_approvals')}</div>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>${t('leave_type')}</th>
                            <th>${t('start_date')}</th>
                            <th>${t('status')}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>${t('annual_leave')}</td>
                            <td>Sep 10, 2026</td>
                            <td><span class="status-badge info">${t('pending')}</span></td>
                        </tr>
                        <tr>
                            <td>${t('sick_leave')}</td>
                            <td>Jul 15, 2026</td>
                            <td><span class="status-badge success">${t('approved')}</span></td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
    `;
}

// Render Payroll
function renderPayroll() {
    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('nav_payroll')}</h1>
                <p class="page-subtitle">${t('salary_sub')}</p>
            </div>
        </div>
        <div class="dashboard-grid">
            <div class="card col-span-4" style="background: linear-gradient(135deg, var(--color-primary), var(--color-primary-hover)); color: white;">
                <h3 style="margin-bottom: 2rem; color: rgba(255,255,255,0.8);">${t('net_pay')}</h3>
                <h1 style="font-size: 3rem; margin-bottom: 0.5rem;">$5,240.00</h1>
                <p style="color: var(--color-success);">+ $120.00 Overtime</p>
            </div>
            <div class="card col-span-8">
                <div class="card-title">${t('recent_payslips')}</div>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>${t('month')}</th>
                            <th>${t('net_pay')}</th>
                            <th></th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>July 2026</td>
                            <td>$5,240.00</td>
                            <td style="text-align: end;"><button class="btn-primary" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;" onclick="showToast(t('toast_payslip'), 'success')">${t('download')}</button></td>
                        </tr>
                        <tr>
                            <td>June 2026</td>
                            <td>$5,120.00</td>
                            <td style="text-align: end;"><button class="btn-primary" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;" onclick="showToast(t('toast_payslip'), 'success')">${t('download')}</button></td>
                        </tr>
                        <tr>
                            <td>May 2026</td>
                            <td>$5,120.00</td>
                            <td style="text-align: end;"><button class="btn-primary" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;" onclick="showToast(t('toast_payslip'), 'success')">${t('download')}</button></td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
    `;
}

// Render Admin Hub
function renderAdmin() {
    return `
        <div class="page-header">
            <div>
                <h1 class="page-title">${t('admin_overview')}</h1>
                <p class="page-subtitle">${t('admin_sub')}</p>
            </div>
        </div>

        <div class="dashboard-grid">
            <div class="card col-span-3">
                <div class="card-title">${t('headcount')} <i data-lucide="users"></i></div>
                <h2 style="font-size: 2.5rem; margin-top: 10px;">1,248</h2>
                <p style="color: var(--color-success); font-size: 0.875rem;">+12% this year</p>
            </div>
            
            <div class="card col-span-3">
                <div class="card-title">${t('turnover_rate')} <i data-lucide="trending-down"></i></div>
                <h2 style="font-size: 2.5rem; margin-top: 10px;">4.2%</h2>
                <p style="color: var(--color-success); font-size: 0.875rem;">-1.5% from last year</p>
            </div>

            <div class="card col-span-3">
                <div class="card-title">${t('open_roles')} <i data-lucide="briefcase"></i></div>
                <h2 style="font-size: 2.5rem; margin-top: 10px;">42</h2>
                <p style="color: var(--color-text-secondary); font-size: 0.875rem;">Active requisitions</p>
            </div>

            <div class="card col-span-3">
                <div class="card-title">${t('diversity')} <i data-lucide="pie-chart"></i></div>
                <h2 style="font-size: 2.5rem; margin-top: 10px;">48/52</h2>
                <p style="color: var(--color-text-secondary); font-size: 0.875rem;">F/M Ratio</p>
            </div>
            
            <!-- Workflow Builder Placeholder -->
            <div class="card col-span-12" style="min-height: 300px; display: flex; flex-direction: column; justify-content: center; align-items: center; background: rgba(0,0,0,0.02); border: 1px dashed var(--color-border);">
                <i data-lucide="workflow" style="width: 48px; height: 48px; color: var(--color-text-secondary); margin-bottom: 1rem;"></i>
                <h3 style="color: var(--color-text-secondary);">Approval Workflow Builder (Prototyping)</h3>
                <p style="color: var(--color-text-secondary); font-size: 0.875rem;">Drag and drop interface will appear here.</p>
            </div>
        </div>
    `;
}

// Router
function renderView(viewId) {
    if (!currentUser && viewId !== 'login') {
        viewId = 'login';
        currentView = 'login';
    }

    let content = '';
    
    switch(viewId) {
        case 'login':
            content = renderLogin();
            break;
        case 'dashboard':
            content = renderDashboard();
            break;
        case 'time':
            content = renderTime();
            break;
        case 'leave':
            content = renderLeave();
            break;
        case 'payroll':
            content = renderPayroll();
            break;
        case 'admin':
            content = renderAdmin();
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
}

// Init
updateTranslations();
renderView(currentView);
