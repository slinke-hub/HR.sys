const fs = require('fs');
const content = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');
const match = content.match(/ui_deal_client:\s*["']([^"']+)["']/g);
console.log("Found:", match);
