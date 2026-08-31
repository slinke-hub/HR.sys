const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

app = app.replace(
    '${r.rejection_reason ? `<br><strong>Rejection reason:</strong> ${escapeHTML(r.rejection_reason)}` : \'\'}',
    '${r.rejection_reason ? `<br><strong>${t(\'ui_rejection_reason\')}:</strong> ${escapeHTML(r.rejection_reason)}` : \'\'}'
);

app = app.replace(
    '`Manager Rejection Reason: ${reason}`',
    '`${t(\'ui_rejection_reason\')}: ${reason}`'
);

fs.writeFileSync('e:/HR.sys/js/app.js', app, 'utf8');
console.log('Rejection reason translated');
