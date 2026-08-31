const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

// Replace all known corrupted characters with standard ones
app = app.replace(/â€”/g, '-');
app = app.replace(/â€“/g, '-');
app = app.replace(/â€œ/g, '"');
app = app.replace(/â€ /g, '"'); // careful, this might match other things if there is trailing space? The character is actually â€ followed by a space? No, it's usually â€ followed by nothing. Wait, the single right quote is â€™
app = app.replace(/â€¦/g, '...');
app = app.replace(/Â·/g, '·');
app = app.replace(/â€¢/g, '•');

// Also explicitly fix the rejection reason empty state to just use '-'
// Actually, with the above replacements, 'â€”' becomes '-', so the rejection reason will become:
// <td>${request.rejection_reason ? escapeHTML(request.rejection_reason) : '-'}</td>
// Which is perfectly fine and standard for both English and Arabic!

fs.writeFileSync('e:/HR.sys/js/app.js', app, 'utf8');
console.log('Fixed text encodings in app.js');

// Bump cache
let html = fs.readFileSync('e:/HR.sys/index.html', 'utf8');
html = html.replace(/v=\d+/g, 'v=' + Date.now());
fs.writeFileSync('e:/HR.sys/index.html', html, 'utf8');
console.log('Bumped cache');
