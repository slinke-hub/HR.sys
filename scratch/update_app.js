const fs = require('fs');

let appContent = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const target1 = `async function renderEmployeesDirectory() {
    const users = await db.fetchUsers();`;

const replacement1 = `async function renderEmployeesDirectory() {
    const users = await db.fetchUsers();
    const departments = await db.fetchDepartments();
    const myDept = currentUser.department_id ? departments.find(d => d.id === currentUser.department_id) : null;
    const isHR = myDept && myDept.name.toLowerCase().includes('hr');
    const canCreateContract = currentUserRole === 'ADMIN' || currentUserRole === 'MANAGER' || isHR;
`;
appContent = appContent.replace(target1, replacement1);

const target2 = `return \`
        <div class="page-header fade-in-up">
            <div>
                <h1 class="page-title">\${t('nav_emp_dir')}</h1>
                <p class="page-subtitle">\${t('emp_dir_sub')}</p>
            </div>
        </div>`;

const replacement2 = `return \`
        <div class="page-header fade-in-up">
            <div style="flex: 1;">
                <h1 class="page-title">\${t('nav_emp_dir')}</h1>
                <p class="page-subtitle">\${t('emp_dir_sub')}</p>
            </div>
            \${canCreateContract ? \`
            <button class="btn btn-primary" onclick="window.navigateToContract('', '')">
                <i data-lucide="plus" style="width:16px;height:16px;margin-right:4px;"></i> \${t('ui_new_contract') || 'Create New Contract'}
            </button>
            \` : ''}
        </div>`;
appContent = appContent.replace(target2, replacement2);

fs.writeFileSync('e:/HR.sys/js/app.js', appContent, 'utf8');
console.log("Updated app.js for Contracts page");
