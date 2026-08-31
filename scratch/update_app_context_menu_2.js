const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

// 1. Modify the article tag
const articleTarget = /onclick="openTaskDetailsModal\('\$\{task\.id\}'\)"\s*>/g;
const articleNew = `onclick="openTaskDetailsModal('\${task.id}')" oncontextmenu="window.handleTaskContextMenu(event, '\${task.id}', \${canEditTask}, \${canDeleteTask})">`;
app = app.replace(articleTarget, articleNew);

// 2. Remove the task-pipeline-actions div
const actionsRegex = /<div class="task-pipeline-actions"[\s\S]*?<\/div>\s*<\/div>\s*<div class="task-parent-reference">/g; // wait, let's just do an exact match or close to it
const actionsTargetStr = `            <div class="task-pipeline-actions" onclick="event.stopPropagation();">
                <button type="button" class="task-pipeline-action \${canEditTask ? '' : 'is-disabled'}" \${canEditTask ? \`onclick="event.preventDefault(); event.stopImmediatePropagation(); openEditTaskModal('\${task.id}')"\` : 'disabled'} title="\${canEditTask ? 'Edit task' : 'Only the task creator can edit this task'}" aria-label="\${canEditTask ? 'Edit task' : 'Edit task (creator only)'}"><i data-lucide="pencil"></i></button>
                <button type="button" class="task-pipeline-action task-pipeline-delete \${canDeleteTask ? '' : 'is-disabled'}" \${canDeleteTask ? \`onclick="event.preventDefault(); event.stopImmediatePropagation(); window.handleDeleteTask('\${task.id}')"\` : 'disabled'} title="\${canDeleteTask ? 'Delete task' : 'Only the task creator or an administrator can delete this task'}" aria-label="Delete task"><i data-lucide="trash-2"></i></button>
            </div>`;
app = app.replace(actionsTargetStr, '');

// 3. Add handleTaskContextMenu function at the end of the file
const scriptContext = `
// Context Menu Logic
window.handleTaskContextMenu = function(e, taskId, canEditTask, canDeleteTask) {
    e.preventDefault();
    e.stopPropagation();

    const menu = document.getElementById('task-context-menu');
    const editBtn = document.getElementById('ctx-edit-task');
    const deleteBtn = document.getElementById('ctx-delete-task');

    if (!menu || !editBtn || !deleteBtn) return;

    if (canEditTask) {
        editBtn.style.display = 'flex';
        editBtn.onclick = function(ev) {
            ev.stopPropagation();
            menu.style.display = 'none';
            window.openEditTaskModal(taskId);
        };
    } else {
        editBtn.style.display = 'none';
    }

    if (canDeleteTask) {
        deleteBtn.style.display = 'flex';
        deleteBtn.onclick = function(ev) {
            ev.stopPropagation();
            menu.style.display = 'none';
            window.handleDeleteTask(taskId);
        };
    } else {
        deleteBtn.style.display = 'none';
    }

    if (!canEditTask && !canDeleteTask) {
        menu.style.display = 'none';
        return;
    }

    menu.style.display = 'block';
    
    // Position menu
    let x = e.pageX;
    let y = e.pageY;
    
    if (x + menu.offsetWidth > window.innerWidth) {
        x -= menu.offsetWidth;
    }
    if (y + menu.offsetHeight > window.innerHeight) {
        y -= menu.offsetHeight;
    }
    
    menu.style.left = x + 'px';
    menu.style.top = y + 'px';
    
    lucide.createIcons();
};

document.addEventListener('click', function(e) {
    const menu = document.getElementById('task-context-menu');
    if (menu && menu.style.display === 'block') {
        if (!menu.contains(e.target)) {
            menu.style.display = 'none';
        }
    }
});
`;

if (!app.includes('handleTaskContextMenu')) {
    app += '\n' + scriptContext;
    console.log('Appended context menu function.');
}

fs.writeFileSync('e:/HR.sys/js/app.js', app, 'utf8');
console.log('Modified app.js with context menu logic');
