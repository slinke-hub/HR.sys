const fs = require('fs');
let content = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const updateRolePatch = `
    const roleSpan = document.getElementById('currentUserRole');
    if (roleSpan && typeof currentUserRole !== 'undefined') {
        let displayRole = currentUserRole.charAt(0).toUpperCase() + currentUserRole.slice(1);
        if (currentUserRole === 'admin') displayRole = t('role_system_admin') || 'System Admin';
        else if (currentUserRole === 'manager') displayRole = t('role_manager') || 'Manager';
        else if (currentUserRole === 'employee') displayRole = t('role_employee') || 'Employee';
        roleSpan.textContent = displayRole;
    }
`;

content = content.replace(
    "const texts = document.querySelectorAll('[data-i18n]');",
    updateRolePatch + "\n    const texts = document.querySelectorAll('[data-i18n]');"
);

fs.writeFileSync('e:/HR.sys/js/app.js', content, 'utf8');
console.log('Patched updateTranslations successfully');
