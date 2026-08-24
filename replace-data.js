const fs = require('fs');
let data = fs.readFileSync('js/data.js', 'utf8');

// The string to look for in Arabic is "الرؤية" (Visibility)
data = data.replace(
    '    html_visibility: "Visibility",',
    '    html_assignee: "Assignee",\n    html_creator: "Creator",\n    html_status: "Status",\n    html_visibility: "Visibility",'
);

data = data.split('    html_visibility: "الرؤية",').join(
    '    html_assignee: "المعين",\n    html_creator: "المنشئ",\n    html_status: "الحالة",\n    html_visibility: "الرؤية",'
);

fs.writeFileSync('js/data.js', data);
console.log('Modified js/data.js');
