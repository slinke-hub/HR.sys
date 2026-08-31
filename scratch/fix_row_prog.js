const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

let lines = app.split('\n');
let startIdx = lines.findIndex(l => l.includes('function renderEmployeesDirectory'));
if(startIdx !== -1) {
    let actionIdx = -1;
    for (let i = startIdx + 1; i < lines.length; i++) {
        if (lines[i].includes('<div class="directory-actions">')) {
            actionIdx = i;
            break;
        }
    }
    
    if(actionIdx !== -1) {
        let targetLine = lines[actionIdx - 1];
        if (targetLine.trim() === '<td>') {
             lines[actionIdx - 1] = '                                    <td>${escapeHTML(u.contract_edited_by || \'-\')}</td>\n                                    <td>';
             app = lines.join('\n');
             fs.writeFileSync('e:/HR.sys/js/app.js', app, 'utf8');
             console.log('Fixed renderEmployeesDirectory');
        } else {
             console.log('Target line was not just <td>', targetLine);
        }
    }
}
