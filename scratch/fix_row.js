const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const targetRowStart = `                                    <td data-user-role><span data-user-role-badge class="status-badge \${u.role === 'ADMIN' ? 'success' : (u.role === 'MANAGER' ? 'warning' : 'info')}">\${escapeHTML(u.role || 'EMPLOYEE')}</span></td>
                                    <td>
                                        <div class="directory-actions">`;
                                        
const newRowStart = `                                    <td data-user-role><span data-user-role-badge class="status-badge \${u.role === 'ADMIN' ? 'success' : (u.role === 'MANAGER' ? 'warning' : 'info')}">\${escapeHTML(u.role || 'EMPLOYEE')}</span></td>
                                    <td>\${escapeHTML(u.contract_edited_by || '-')}</td>
                                    <td>
                                        <div class="directory-actions">`;

if (app.includes(targetRowStart)) {
    app = app.replace(targetRowStart, newRowStart);
    fs.writeFileSync('e:/HR.sys/js/app.js', app, 'utf8');
    console.log('Fixed row in renderEmployeesDirectory');
} else {
    // If exact match fails, let's use a regex
    const regex = /(<td data-user-role>[\s\S]*?<\/td>)\s*<td>\s*<div class="directory-actions">/;
    if (regex.test(app)) {
        app = app.replace(regex, `$1\n                                    <td>\${escapeHTML(u.contract_edited_by || '-')}</td>\n                                    <td>\n                                        <div class="directory-actions">`);
        fs.writeFileSync('e:/HR.sys/js/app.js', app, 'utf8');
        console.log('Fixed row in renderEmployeesDirectory using regex');
    } else {
        console.log('Target not found!');
    }
}
