$content = [System.IO.File]::ReadAllText("js\app.js")
$startIndex = $content.IndexOf("window.clearTaskV2Filters = function () {")
$endIndex = $content.IndexOf("window.populateTaskWatcherPicker = function (selectId, options, selectedIds = []) {")

if ($startIndex -eq -1 -or $endIndex -eq -1) {
    Write-Host "Markers not found"
    exit 1
}

$replacement = @'
window.clearTaskV2Filters = function () {
    const search = document.getElementById('taskV2Search');
    const status = document.getElementById('taskV2Status');
    if (search) search.value = '';
    if (status) status.value = '';
    window.taskV2SelectedProject = 'all';
    document.querySelectorAll('.task-v2-list-link').forEach((button, index) => button.classList.toggle('active', index === 0));
    window.filterTasksV2();
};

window.toggleAITaskMode = function () {
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

window.handleAICreateTask = async function (e) {
    e.preventDefault();
    const canCreateTask = !!currentUser;
    if (!canCreateTask) {
        showToast("You do not have permission to create tasks.", "danger");
        return;
    }
    const input = document.getElementById('aiTaskInput').value;
    if (!input) return;

    // Very basic heuristic parser (mock AI)
    let priority = 'medium';
    if (input.toLowerCase().includes('critical') || input.toLowerCase().includes('urgent')) priority = 'urgent';
    if (input.toLowerCase().includes('high priority')) priority = 'high';
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
    const supervisorId = window.taskDepartmentSupervisors?.[0]?.id || null;
    const { success } = await db.createTask(input, '', assigneeId, dueStr, currentUser.id, priority, 'Auto-parsed', { 'en': input, 'ar': input + ' (مترجم)' }, {}, null, null, null, 'public', null, [], [], null, null, null, 'todo', supervisorId);
    if (success) {
        showToast(t('toast_ai_parsed_and_created_task'), "success");
        await db.triggerWebhooks('task_created', { title: input, assignee_id: assigneeId, due_date: dueStr, priority: priority, is_ai_parsed: true });
        renderView(currentView === 'tasks_v2' ? 'tasks_v2' : 'tasks');
    } else {
        showToast(t('toast_failed_to_create_task'), "danger");
    }
};

window.handleTaskProjectChange = function (prefix = 'new') {
    // We could filter tags based on the selected project, but for now we'll just log it.
    requestAnimationFrame(() => document.getElementById('taskTitle')?.focus());
};

window.handleTaskDepartmentChange = function (prefix = 'new', value = '', selectedAssigneeId = '') {
    const selectedDepartment = (window.taskDepartmentsCache || []).find(item => item.id === value || item.name === value);
    const departmentName = selectedDepartment?.name || value;
    updateTaskAssigneeOptions(prefix, departmentName, selectedAssigneeId);
    const subTypeGroup = document.getElementById(prefix === 'new' ? 'taskSubTypeGroup' : 'editTaskSubTypeGroup');
    if (!subTypeGroup) return;

    if (isMarketingTaskDepartment(departmentName)) {
        subTypeGroup.style.display = 'block';
        const select = document.getElementById(prefix === 'new' ? 'taskSubType' : 'editTaskSubType');
        if (select) select.required = true;
    } else {
        subTypeGroup.style.display = 'none';
        const select = document.getElementById(prefix === 'new' ? 'taskSubType' : 'editTaskSubType');
        if (select) { select.value = ''; select.required = false; }
        handleMarketingTaskTypeChange(prefix, '');
    }
};

function updateTaskAssigneeOptions(prefix, departmentName, selectedAssigneeId = '') {
    const select = document.getElementById(prefix === 'new' ? 'taskAssignee' : 'editTaskAssignee');
    if (!select || currentUserRole === 'EMPLOYEE') return;
    const department = (window.taskDepartmentsCache || []).find(item => item.name === departmentName || item.id === departmentName);
    
    let employees = [];
    if (isTaskAdmin()) {
        employees = window.taskAllUsersCache || [];
    } else if (department) {
        employees = (window.taskAllUsersCache || []).filter(user => user.department_id === department.id);
    }

    select.innerHTML = `<option value="">${(department || isTaskAdmin()) ? (t('task_sel_emp') || 'Select Employee') : 'Select a department first'}</option>` + employees.map(user => {
        const label = window.formatEmployeeName(user) || user.id.substring(0, 8);
        return `<option value="${escapeHTML(user.id)}">${escapeHTML(label)} (${escapeHTML(user.role)})</option>`;
    }).join('');
    select.value = employees.some(user => user.id === selectedAssigneeId) ? selectedAssigneeId : '';
    handleTaskAssigneeChange(prefix);
}

function renderTaskWatcherPicker(selectId, options = '') {
    return `<div class="task-watcher-picker" data-watcher-picker="${selectId}">
        <button type="button" class="form-control task-watcher-toggle" onclick="toggleTaskWatcherDropdown('${selectId}')" aria-expanded="false">Select watchers</button>
        <div class="task-watcher-dropdown" hidden>
            <input type="search" class="form-control task-watcher-search" placeholder="Search employees..." aria-label="Search employees" oninput="filterTaskWatchers('${selectId}', this.value)">
            <div class="task-watcher-options"></div>
        </div>
        <select id="${selectId}" multiple hidden>${options}</select>
    </div>`;
}

'@

$newContent = $content.Substring(0, $startIndex) + $replacement + $content.Substring($endIndex)
[System.IO.File]::WriteAllText("js\app.js", $newContent, [System.Text.Encoding]::UTF8)
Write-Host "Success"
