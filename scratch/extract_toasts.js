const fs = require('fs');
const app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');
const lines = app.split('\n');
const toasts = new Set();
lines.forEach(line => {
    const match = line.match(/showToast\('([^']*)'/);
    if (match && !match[1].includes('${')) {
        toasts.add(match[1]);
    }
});
fs.writeFileSync('e:/HR.sys/scratch/toasts.json', JSON.stringify([...toasts], null, 2));
