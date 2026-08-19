const fs = require('fs');

let appContent = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

// Phase 4: Request Approval Workflow in renderApprovals
const approvalsTarget = `
    const tasks = allTasks.filter(t => t.status === 'Pending Approval');

    if (!tasks || tasks.length === 0) {
        return \`
            <div class="page-header">
                <h1 class="page-title">\${t('ui_approvals_dashboard')}</h1>
            </div>
            <div class="card" style="padding: 2rem; text-align: center; color: var(--color-text-secondary);">
                \${t('task_no_pending_approval') || 'No tasks pending approval.'}
            </div>
        \`;
    }
`;

// I'll replace this to fetch leaves, docs, expenses as well and show them in a second table.
const approvalsReplacement = `
    let leaves = await db.fetchLeaveRequests();
    let docs = await db.fetchDocuments();
    let expenses = await db.fetchExpenses();
    
    leaves = leaves.filter(r => r.status === 'PENDING');
    docs = docs.filter(r => r.status === 'PENDING');
    expenses = expenses.filter(r => r.status === 'PENDING');
    
    let pendingReqs = [];
    leaves.forEach(r => pendingReqs.push({...r, type: 'Leave', details: \`\${r.leave_type}: \${new Date(r.start_date).toLocaleDateString()} to \${new Date(r.end_date).toLocaleDateString()}\`}));
    docs.forEach(r => pendingReqs.push({...r, type: 'Document', details: \`\${r.doc_type} - \${r.purpose}\`}));
    expenses.forEach(r => pendingReqs.push({...r, type: 'Expense', details: \`SAR \${r.amount} - \${r.description}\`}));

    const tasks = allTasks.filter(t => t.status === 'Pending Approval');

    if (tasks.length === 0 && pendingReqs.length === 0) {
        return \`
            <div class="page-header">
                <h1 class="page-title">\${t('ui_approvals_dashboard')}</h1>
            </div>
            <div class="card" style="padding: 2rem; text-align: center; color: var(--color-text-secondary);">
                \${t('task_no_pending_approval') || 'No items pending approval.'}
            </div>
        \`;
    }
`;
appContent = appContent.replace(approvalsTarget, approvalsReplacement);

const tasksTableTarget = `</tbody>
                </table>
            </div>
        </div>
    \`;
}`;

const tasksTableReplacement = `</tbody>
                </table>
            </div>
        </div>
        
        \${pendingReqs.length > 0 ? \`
        <h2 style="margin-top: 2rem; margin-bottom: 1rem; font-size: 1.25rem;">Employee Requests</h2>
        <div class="card">
            <div class="table-responsive">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Date</th>
                            <th>Employee</th>
                            <th>Type</th>
                            <th>Details</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        \${pendingReqs.map(req => {
                            const empName = allUsers.find(u => u.id === req.employee_id)?.full_name || 'Unknown';
                            return \`
                            <tr>
                                <td>\${new Date(req.created_at).toLocaleDateString()}</td>
                                <td>\${empName}</td>
                                <td>\${req.type}</td>
                                <td>\${req.details}</td>
                                <td style="text-align: right; white-space: nowrap;">
                                    <button class="btn btn-primary" style="padding: 0.25rem 0.5rem; font-size: 0.8rem;" onclick="updateRequestStatus('\${req.id}', 'APPROVED')">\${t('ui_approve')}</button>
                                    <button class="btn btn-danger" style="padding: 0.25rem 0.5rem; font-size: 0.8rem;" onclick="updateRequestStatus('\${req.id}', 'REJECTED')">\${t('ui_reject')}</button>
                                </td>
                            </tr>
                            \`;
                        }).join('')}
                    </tbody>
                </table>
            </div>
        </div>
        \` : ''}
    \`;
}`;

// I need to be careful with replace, it might replace the wrong one. Let's use a more precise regex.
appContent = appContent.replace(/<\/tbody>\s*<\/table>\s*<\/div>\s*<\/div>\s*`;\s*}/, tasksTableReplacement);


// Update renderRequests to show visual workflow instead of just a badge
const renderReqsTarget = `<td><span class="status-badge \${badgeClass}">\${r.status}</span></td>
                \${actionsCell}`;
                
const renderReqsReplacement = `<td>
                    <div style="display: flex; align-items: center; gap: 0.5rem; font-size: 0.8rem;">
                        <div style="display: flex; align-items: center; color: \${r.status === 'PENDING' ? 'var(--color-warning)' : (r.status === 'APPROVED' ? 'var(--color-success)' : (r.status === 'REJECTED' ? 'var(--color-danger)' : 'var(--color-text-secondary)'))};">
                            <div style="width: 8px; height: 8px; border-radius: 50%; background-color: currentColor; margin-right: 4px;"></div>
                            <span style="font-weight: 600;">\${r.status}</span>
                        </div>
                    </div>
                </td>
                \${actionsCell}`;
appContent = appContent.replace(renderReqsTarget, renderReqsReplacement);

fs.writeFileSync('e:/HR.sys/js/app.js', appContent, 'utf8');
console.log("Updated Approvals logic and Requests workflow UI");
