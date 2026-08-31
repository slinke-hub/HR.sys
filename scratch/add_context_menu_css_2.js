const fs = require('fs');
let css = fs.readFileSync('e:/HR.sys/css/components.css', 'utf8');

const contextMenuCss = `
/* Task Context Menu */
.custom-context-menu {
    position: absolute;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -4px rgba(0, 0, 0, 0.1);
    min-width: 160px;
    z-index: 9999;
    padding: 0.5rem 0;
    font-size: 0.875rem;
}

.custom-context-menu .context-menu-item {
    padding: 0.5rem 1rem;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    cursor: pointer;
    color: var(--text);
    transition: background-color 0.2s, color 0.2s;
}

.custom-context-menu .context-menu-item:hover {
    background: var(--surface-hover);
}

.custom-context-menu .context-menu-item i {
    width: 1rem;
    height: 1rem;
}

.custom-context-menu .context-menu-danger {
    color: var(--danger);
}

.custom-context-menu .context-menu-danger:hover {
    background: var(--danger-bg, #fee2e2);
    color: var(--danger);
}

/* Hide the old action buttons */
.task-pipeline-actions {
    display: none !important;
}
`;

if (!css.includes('.custom-context-menu')) {
    css += '\n' + contextMenuCss;
    fs.writeFileSync('e:/HR.sys/css/components.css', css, 'utf8');
    console.log('Added context menu css to components.css');
} else {
    console.log('Context menu css already exists');
}
