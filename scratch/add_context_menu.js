const fs = require('fs');
let html = fs.readFileSync('e:/HR.sys/index.html', 'utf8');

const contextMenuHtml = `
    <!-- Task Context Menu -->
    <div id="task-context-menu" class="custom-context-menu" style="display: none;">
        <div class="context-menu-item" id="ctx-edit-task">
            <i data-lucide="pencil"></i> <span>Edit Task</span>
        </div>
        <div class="context-menu-item context-menu-danger" id="ctx-delete-task">
            <i data-lucide="trash-2"></i> <span>Delete Task</span>
        </div>
    </div>
`;

if (!html.includes('id="task-context-menu"')) {
    html = html.replace('</body>', contextMenuHtml + '\n</body>');
    fs.writeFileSync('e:/HR.sys/index.html', html, 'utf8');
    console.log('Added context menu to index.html');
} else {
    console.log('Context menu already exists');
}
