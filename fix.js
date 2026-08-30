const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const rx = /renderView\(currentView === 'tasks_v2' \? 'tasks_v2' : 'tasks'\);\r?\n        showToast\(error\?.message \|\| "Failed to save contract", "danger"\);\r?\n    }\r?\n}/;

const fixed = fs.readFileSync('e:/HR.sys/missing_code_fixed.js', 'utf8');

if (rx.test(app)) {
    app = app.replace(rx, "renderView(currentView === 'tasks_v2' ? 'tasks_v2' : 'tasks');\n        }\n    });\n};\n" + fixed + "\n    } else {\n        showToast(error?.message || \"Failed to save contract\", \"danger\");\n    }\n}");
    fs.writeFileSync('e:/HR.sys/js/app.js', app);
    console.log('Fixed app.js successfully!');
} else {
    console.log('Regex did not match.');
    // Let's print out what we see around task_deleted
    const lines = app.split('\n');
    const idx = lines.findIndex(l => l.includes('tasks_v2'));
    console.log(lines.slice(idx-2, idx+6).join('\n'));
}
