const fs = require('fs');
let content = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

// 1. Kanban
content = content.replace(
    '<div class="card-title" style="padding: 1rem 1rem 0;"> <span id="badge-in_progress"',
    '<div class="card-title" style="padding: 1rem 1rem 0;">${t(\'status_in_progress\') || \'In Progress\'} <span id="badge-in_progress"'
);
content = content.replace(
    '<div class="card-title" style="padding: 1rem 1rem 0;"> <span id="badge-review"',
    '<div class="card-title" style="padding: 1rem 1rem 0;">${t(\'status_review\') || \'Review\'} <span id="badge-review"'
);

// 2. Table Headers "Name"
content = content.replace(
    /<th><\/th>(\s*)<th>\$\{t\('ui_description'\)\}<\/th>/g,
    '<th>${t(\'ui_name\') || \'Name\'}</th>$1<th>${t(\'ui_description\')}</th>'
);
content = content.replace(
    /<th><\/th>(\s*)<th>\$\{t\('ui_company'\)\}<\/th>/g,
    '<th>${t(\'ui_name\') || \'Name\'}</th>$1<th>${t(\'ui_company\')}</th>'
);
content = content.replace(
    /<th><\/th>(\s*)<th>\$\{t\('ui_event_type'\)\}<\/th>/g,
    '<th>${t(\'ui_name\') || \'Name\'}</th>$1<th>${t(\'ui_event_type\')}</th>'
);

// 3. Table Headers "Deal / Client"
content = content.replace(
    /<th><\/th>(\s*)<th>\$\{t\('ui_start_date'\)\}<\/th>/g,
    '<th>${t(\'ui_deal_client\') || \'Deal / Client\'}</th>$1<th>${t(\'ui_start_date\')}</th>'
);

// 4. Empty state tables
content = content.replace(
    '<tr><td colspan="7" style="text-align:center;"></td></tr>',
    '<tr><td colspan="7" style="text-align:center;">${t(\'ui_no_orders_found\') || \'No orders found\'}</td></tr>'
);
content = content.replace(
    '<tr><td colspan="5" style="text-align:center;"></td></tr>',
    '<tr><td colspan="5" style="text-align:center;">${t(\'ui_no_clients\') || \'No clients found\'}</td></tr>'
);
content = content.replace(
    '<tr><td colspan="5" class="text-center"></td></tr>',
    '<tr><td colspan="5" class="text-center">${t(\'ui_no_clients_yet\') || \'No clients yet\'}</td></tr>'
);

// 5. Buttons
content = content.replace(
    /<button class="btn btn-primary" onclick="showCRMClientModal\(\)">\s*<i data-lucide="plus"><\/i> \s*<\/button>/g,
    '<button class="btn btn-primary" onclick="showCRMClientModal()"><i data-lucide="plus"></i> ${t(\'ui_new_client\') || \'New Client\'}</button>'
);
content = content.replace(
    /<button class="btn btn-primary" onclick="showCRMDealModal\(\)">\s*<i data-lucide="plus"><\/i> \s*<\/button>/g,
    '<button class="btn btn-primary" onclick="showCRMDealModal()"><i data-lucide="plus"></i> ${t(\'ui_new_deal\') || \'New Deal\'}</button>'
);
content = content.replace(
    '<button class="btn btn-primary" onclick="openProjectModal()"><i data-lucide="plus"></i> </button>',
    '<button class="btn btn-primary" onclick="openProjectModal()"><i data-lucide="plus"></i> ${t(\'ui_new_project_btn\') || \'New Project\'}</button>'
);

// 6. Card Titles
content = content.replace(
    /<div class="card-title"><\/div>(\s*)<button class="btn btn-primary" onclick="showCRMDealModal\(\)">/g,
    '<div class="card-title">${t(\'ui_deal_pipeline\') || \'Deal Pipeline\'}</div>$1<button class="btn btn-primary" onclick="showCRMDealModal()">'
);
content = content.replace(
    /<div class="card-title"><\/div>(\s*)<button class="btn btn-primary" onclick="showCRMClientModal\(\)">/g,
    '<div class="card-title">${t(\'ui_client_directory\') || \'Client Directory\'}</div>$1<button class="btn btn-primary" onclick="showCRMClientModal()">'
);

fs.writeFileSync('e:/HR.sys/js/app.js', content, 'utf8');
console.log("Fixed corrupted template strings in app.js");
