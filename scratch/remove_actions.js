const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const lines = app.split('\n');
let insideActions = false;
let newLines = [];
for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes('<div class="task-pipeline-actions"')) {
        insideActions = true;
        continue;
    }
    if (insideActions) {
        if (lines[i].includes('</div>')) {
            insideActions = false;
        }
        continue;
    }
    newLines.push(lines[i]);
}

fs.writeFileSync('e:/HR.sys/js/app.js', newLines.join('\n'), 'utf8');
console.log('Removed task actions div');
