const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const replaceTarget1 = `window.canCurrentUserEditContracts = function (profile = currentUserProfile) {
    if (!profile) return false;
    const role = String(profile.role || '').toUpperCase();
    if (['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(role)) return true;
    if (role === 'HR_MANAGER' || /HR\\s*MANAGER/i.test(String(profile.job_title || ''))) return true;
    return false;
};`;

const newCode1 = `window.canCurrentUserEditContracts = function (profile = currentUserProfile) {
    if (!profile) return false;
    const role = String(profile.role || '').toUpperCase();
    if (['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(role)) return true;
    if (role === 'HR_MANAGER' || /HR\\s*MANAGER/i.test(String(profile.job_title || ''))) return true;
    if (/gm|ceo|owner|general\\s*manager|chief\\s*executive/i.test(String(profile.job_title || ''))) return true;
    return false;
};`;

app = app.replace(replaceTarget1, newCode1);

const contractDataTarget = `        confidentiality_policy_url: policyUrl,
        status: document.getElementById('contractStatus').value
    };`;
const contractDataNew = `        confidentiality_policy_url: policyUrl,
        status: document.getElementById('contractStatus').value,
        edited_by: window.formatEmployeeName(currentUserProfile) || null
    };`;

app = app.replace(contractDataTarget, contractDataNew);

// Add 'Edited by' to Employee Directory (Contracts) table
const headerTarget = `<th>ID</th><th>Employee Details</th><th>Role</th><th>\${t('actions') || 'Actions'}</th>`;
const headerNew = `<th>ID</th><th>Employee Details</th><th>Role</th><th>\${t('edited_by') || 'Edited By'}</th><th>\${t('actions') || 'Actions'}</th>`;
app = app.replace(headerTarget, headerNew);

const rowTarget = `<td data-user-role><span data-user-role-badge class="status-badge \${u.role === 'ADMIN' ? 'success' : (u.role === 'MANAGER' ? 'warning' : 'info')}">\${escapeHTML(u.role || 'EMPLOYEE')}</span></td>
                                    <td>`;
const rowNew = `<td data-user-role><span data-user-role-badge class="status-badge \${u.role === 'ADMIN' ? 'success' : (u.role === 'MANAGER' ? 'warning' : 'info')}">\${escapeHTML(u.role || 'EMPLOYEE')}</span></td>
                                    <td>\${escapeHTML(u.contract_edited_by || '-')}</td>
                                    <td>`;
app = app.replace(rowTarget, rowNew);

// Also we need to inject the contract edited_by into the users array so that we can show it!
// Inside renderEmployeesDirectory:
const usersTarget = `    const [users, viewerProfile, printRequests] = await Promise.all([
        db.fetchUsers(),
        db.getUserProfile(currentUser?.id),
        db.fetchContractPrintRequests({ managerId: currentUser?.id, status: 'PENDING' })
    ]);`;
const usersNew = `    const [users, viewerProfile, printRequests, allContracts] = await Promise.all([
        db.fetchUsers(),
        db.getUserProfile(currentUser?.id),
        db.fetchContractPrintRequests({ managerId: currentUser?.id, status: 'PENDING' }),
        db.fetchContracts() // fetch all contracts
    ]);
    
    // Map edited_by to users
    users.forEach(u => {
        const contract = (allContracts || []).find(c => c.employee_id === u.id);
        if (contract && contract.edited_by) {
            u.contract_edited_by = contract.edited_by;
        }
    });
`;
app = app.replace(usersTarget, usersNew);

fs.writeFileSync('e:/HR.sys/js/app.js', app, 'utf8');
console.log('Updated app.js for Contracts');

// Update data.js translations
let data = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');
const dataTarget = `    'profile_print_requests': {
        en: 'Print Requests',
        ar: 'طلبات الطباعة'
    },`;
const dataNew = `    'profile_print_requests': {
        en: 'Print Requests',
        ar: 'طلبات الطباعة'
    },
    'edited_by': {
        en: 'Edited By',
        ar: 'تم التعديل بواسطة'
    },`;
if (!data.includes("'edited_by': {")) {
    data = data.replace(dataTarget, dataNew);
    fs.writeFileSync('e:/HR.sys/js/data.js', data, 'utf8');
}

// Bump html cache
let html = fs.readFileSync('e:/HR.sys/index.html', 'utf8');
html = html.replace(/v=\\d+/g, 'v=' + Date.now());
fs.writeFileSync('e:/HR.sys/index.html', html, 'utf8');

