const fs = require('fs');
const path = require('path');

const targetFile = path.join(__dirname, 'js', 'app.js');
let lines = fs.readFileSync(targetFile, 'utf8').split('\n');

for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes(`onclick="window.selectTaskV2Project('list_\${list.id}')"`)) {
        // Change the line to include oncontextmenu
        if (!lines[i].includes('oncontextmenu')) {
            lines[i] = lines[i].replace('">', `" oncontextmenu="window.showTaskListContextMenu(event, '\${list.id}', \${currentUserRole === 'ADMIN'})">`);
        }
        
        // Remove the button lines below it
        let j = i + 1;
        while (j < i + 10 && !lines[j].includes('</li>')) {
            if (lines[j].includes('<button class="icon-btn"') || lines[j].includes('data-lucide="settings"') || lines[j].includes('data-lucide="trash-2"')) {
                lines[j] = ''; // blank it out
            }
            j++;
        }
    }
}

let newContent = lines.join('\n');

// 2. Add the context menu function at the end of the file if not already added
if (!newContent.includes('window.showTaskListContextMenu')) {
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
    newContent += contextMenuFunc;
}

fs.writeFileSync(targetFile, newContent, 'utf8');
console.log("Successfully patched app.js for task list context menu with robust matching");
