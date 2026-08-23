const fs = require('fs');
let content = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

// Replace "Active Contracts"
content = content.replace(/> Active Contracts<\/button>/g, '> ${t("active_contracts")}</button>');
// Replace "Archived Contracts"
content = content.replace(/> Archived Contracts<\/button>/g, '> ${t("archived_contracts")}</button>');
content = content.replace(/<h1 class="page-title">Archived Contracts<\/h1>/g, '<h1 class="page-title">${t("archived_contracts")}</h1>');

fs.writeFileSync('e:/HR.sys/js/app.js', content, 'utf8');
