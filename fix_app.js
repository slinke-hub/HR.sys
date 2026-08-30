const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const rx = /renderView\(currentView === 'tasks_v2' \? 'tasks_v2' : 'tasks'\);\r?\n        showToast\(error\?.message \|\| "Failed to save contract", "danger"\);\r?\n    }\r?\n}/;

let missing = fs.readFileSync('missing_code.js', 'utf8');

missing = missing.replace(
    /window\.navigateToContract = function \(employeeId, empName\) \{[\s\S]*?renderView\('contract'\);\r?\n\}/,
\window.navigateToContract = async function (employeeId, empName) {
    if (!window.canCurrentUserEditContracts()) {
        showToast('Only an HR Manager or Administrator can edit contracts.', 'danger');
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
    
    modal.innerHTML = \\\
        <div class="modal-content" style="max-width: 900px; width: 90%; background: var(--color-bg-surface); padding: 0; max-height: 90vh; overflow-y: auto;">
            <div class="modal-header" style="position: sticky; top: 0; background: var(--color-bg-surface); z-index: 10; padding: 1.5rem; border-bottom: 1px solid var(--color-border); display: flex; justify-content: space-between; align-items: center;">
                <h2 style="margin:0">\ - \</h2>
                <button class="close-modal" onclick="document.getElementById('contractEditModal').style.display = 'none'">&times;</button>
            </div>
            <div class="modal-body contract-modal-body" style="padding: 1.5rem; padding-top: 0.5rem;">
                <style>
                    .contract-modal-body .page-header { display: none !important; }
                    .contract-modal-body { text-align: left; }
                </style>
                \
            </div>
        </div>
    \\\;
    if (window.lucide && lucide.createIcons) lucide.createIcons();
    modal.style.display = 'block';
}\
);

missing = missing.replace(
    /delete window\.viewHTMLCache\.users;\r?\n        delete window\.viewHTMLCache\.employees;\r?\n        showToast\(t\('toast_contract_saved_successfully'\), "success"\);\r?\n        currentView = 'users';\r?\n        renderView\('users'\);/,
\delete window.viewHTMLCache.users;
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
        }\
);

app = app.replace(rx, \enderView(currentView === 'tasks_v2' ? 'tasks_v2' : 'tasks');\n        }\n    });\n};\n\ndocument.addEventListener('dragend', function (e) {\n    if (e.target && e.target.classList && e.target.classList.contains('task-item-card')) {\n        e.target.style.opacity = '1';\n    }\n});\n\n// Router\n// ==========================================\n// Employees & Contracts (HR View)\n// ==========================================\n\ + missing + \\n        showToast(error?.message || "Failed to save contract", "danger");\n    }\n}\);

fs.writeFileSync('e:/HR.sys/js/app.js', app);
console.log('Restored and modified successfully');
