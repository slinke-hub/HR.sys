const fs = require('fs');
let appContent = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

appContent = appContent.replace(
    /'<tr><td colspan="7" style="text-align:center;">\$\{t\('ui_no_orders_found'\) \|\| 'No orders found'\}<\/td><\/tr>'/g,
    "`<tr><td colspan=\"7\" style=\"text-align:center;\">${t('ui_no_orders_found') || 'No orders found'}</td></tr>`"
);

appContent = appContent.replace(
    /'<tr><td colspan="5" style="text-align:center;">\$\{t\('ui_no_clients'\) \|\| 'No clients found'\}<\/td><\/tr>'/g,
    "`<tr><td colspan=\"5\" style=\"text-align:center;\">${t('ui_no_clients') || 'No clients found'}</td></tr>`"
);

appContent = appContent.replace(
    /'<tr><td colspan="5" class="text-center">\$\{t\('ui_no_clients_yet'\) \|\| 'No clients yet'\}<\/td><\/tr>'/g,
    "`<tr><td colspan=\"5\" class=\"text-center\">${t('ui_no_clients_yet') || 'No clients yet'}</td></tr>`"
);

fs.writeFileSync('e:/HR.sys/js/app.js', appContent, 'utf8');
console.log("Fixed syntax error 2 in app.js");
