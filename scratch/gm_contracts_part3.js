const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const oldStr = `                                    <td data-user-role><span data-user-role-badge class="status-badge \${u.role === 'ADMIN' ? 'success' : (u.role === 'MANAGER' ? 'warning' : 'info')}">\${escapeHTML(u.role || 'EMPLOYEE')}</span></td>
                                    <td>
                                        <div class="directory-actions">`;

const newStr = `                                    <td data-user-role><span data-user-role-badge class="status-badge \${u.role === 'ADMIN' ? 'success' : (u.role === 'MANAGER' ? 'warning' : 'info')}">\${escapeHTML(u.role || 'EMPLOYEE')}</span></td>
                                    <td>\${escapeHTML(u.contract_edited_by || '-')}</td>
                                    <td>
                                        <div class="directory-actions">`;

app = app.replace(oldStr, newStr);

fs.writeFileSync('e:/HR.sys/js/app.js', app, 'utf8');
console.log('Replaced row');
