const fs = require('fs');
const path = require('path');

const targetFile = path.join(__dirname, 'js', 'app.js');
let content = fs.readFileSync(targetFile, 'utf8');

// 1. Replace the task list rendering HTML
const targetHTML = `            <li class="\${selectedProject === 'list_' + String(list.id) ? 'active' : ''}" onclick="window.selectTaskV2Project('list_\${list.id}')">
                <span class="task-list-name">\${escapeHTML(list.name)}</span>
                <div style="margin-left: auto; display: flex; gap: 4px; align-items: center;">
                    \${currentUserRole === 'ADMIN' ? \`<button class="icon-btn" onclick="event.stopPropagation(); window.openTaskListModal('\${list.id}')" style="padding: 2px;" title="Edit List"><i data-lucide="settings" style="width:14px;height:14px;"></i></button>\` : ''}
                    <button class="icon-btn" onclick="event.stopPropagation(); window.handleDeleteTaskList('\${list.id}')" style="padding: 2px; color: var(--color-danger);" title="Delete List"><i data-lucide="trash-2" style="width:14px;height:14px;"></i></button>
                    <span class="badge task-count-badge" style="background: var(--color-surface); color: var(--color-text-secondary); border-radius: 4px; padding: 0.15rem 0.4rem; font-size: 0.75rem; margin-left: 4px;">\${listTasksCount}</span>
                </div>
            </li>`;

const replacementHTML = `            <li class="\${selectedProject === 'list_' + String(list.id) ? 'active' : ''}" onclick="window.selectTaskV2Project('list_\${list.id}')" oncontextmenu="window.showTaskListContextMenu(event, '\${list.id}', \${currentUserRole === 'ADMIN'})">
                <span class="task-list-name">\${escapeHTML(list.name)}</span>
                <div style="margin-left: auto; display: flex; gap: 4px; align-items: center;">
                    <span class="badge task-count-badge" style="background: var(--color-surface); color: var(--color-text-secondary); border-radius: 4px; padding: 0.15rem 0.4rem; font-size: 0.75rem; margin-left: 4px;">\${listTasksCount}</span>
                </div>
            </li>`;

content = content.replace(targetHTML, replacementHTML);

// 2. Add the context menu function at the end of the file if not already added
if (!content.includes('window.showTaskListContextMenu')) {
    const contextMenuFunc = `
window.showTaskListContextMenu = function(e, listId, isAdmin) {
    e.preventDefault();
    let menu = document.getElementById('taskListContextMenu');
    if (!menu) {
        menu = document.createElement('div');
        menu.id = 'taskListContextMenu';
        menu.className = 'context-menu';
        menu.style.cssText = 'display: none; position: fixed; z-index: 10000; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: 6px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); min-width: 160px; padding: 4px 0;';
        document.body.appendChild(menu);
        document.addEventListener('click', (ev) => {
            if (!ev.target.closest('#taskListContextMenu')) {
                menu.style.display = 'none';
            }
        });
    }

    let buttonsHtml = '';
    if (isAdmin) {
        buttonsHtml += \`<button onclick="window.openTaskListModal('\${listId}'); document.getElementById('taskListContextMenu').style.display='none';" style="display:flex; align-items:center; width:100%; padding:8px 16px; background:none; border:none; text-align:left; cursor:pointer; color:var(--color-text); font-size:0.85rem;"><i data-lucide="settings" style="width:16px;height:16px;margin-right:8px;"></i> Edit List</button>\`;
    }
    buttonsHtml += \`<button onclick="window.handleDeleteTaskList('\${listId}'); document.getElementById('taskListContextMenu').style.display='none';" style="display:flex; align-items:center; width:100%; padding:8px 16px; background:none; border:none; text-align:left; cursor:pointer; color:var(--color-danger); font-size:0.85rem;"><i data-lucide="trash-2" style="width:16px;height:16px;margin-right:8px;"></i> Delete List</button>\`;

    menu.innerHTML = buttonsHtml;
    
    menu.style.display = 'block';
    
    let left = e.clientX;
    let top = e.clientY;
    
    const rect = menu.getBoundingClientRect();
    if (left + rect.width > window.innerWidth) left = window.innerWidth - rect.width - 5;
    if (top + rect.height > window.innerHeight) top = window.innerHeight - rect.height - 5;
    
    menu.style.left = left + 'px';
    menu.style.top = top + 'px';
    
    if (window.lucide) window.lucide.createIcons();
};
`;
    content += contextMenuFunc;
}

fs.writeFileSync(targetFile, content, 'utf8');
console.log("Successfully patched app.js for task list context menu");
