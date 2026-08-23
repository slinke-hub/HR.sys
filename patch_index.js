const fs = require('fs');
let content = fs.readFileSync('e:/HR.sys/index.html', 'utf8');

// Set lang to ar and data-theme to light
content = content.replace(/<html lang="en" dir="ltr" data-theme="dark">/, '<html lang="ar" dir="rtl" data-theme="light">');

// Add data-i18n to Task Manager and Contracts
content = content.replace(/<span(?: data-i18n="nav_task_manager")?>Task Manager<\/span>/g, '<span data-i18n="nav_task_manager">Task Manager</span>');
content = content.replace(/<span(?: data-i18n="nav_contracts")?>Contracts<\/span>/g, '<span data-i18n="nav_contracts">Contracts</span>');

// Add custom style for Contracts in Dark Mode
if (!content.includes('/* Custom requested style for Contracts in Dark Mode */')) {
    const styleString = `
        /* Custom requested style for Contracts in Dark Mode */
        [data-theme="dark"] .sidebar-nav .nav-item[data-view="employees"] {
            background-color: #FFFFFF !important;
            color: #000000 !important;
        }
        [data-theme="dark"] .sidebar-nav .nav-item[data-view="employees"] span,
        [data-theme="dark"] .sidebar-nav .nav-item[data-view="employees"] i {
            color: #000000 !important;
        }
    </style>`;
    content = content.replace(/<\/style>/, styleString);
}

fs.writeFileSync('e:/HR.sys/index.html', content, 'utf8');
