const fs = require('fs');

let html = fs.readFileSync('e:/HR.sys/index.html', 'utf8');

if (!html.includes('xlsx.full.min.js')) {
    html = html.replace('<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>', '<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>\n    <script src="https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js"></script>');
    fs.writeFileSync('e:/HR.sys/index.html', html, 'utf8');
    console.log("Added SheetJS to index.html");
} else {
    console.log("SheetJS already exists");
}
