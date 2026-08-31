const fs = require('fs');
let code = fs.readFileSync('js/app.js', 'utf8');

const oldFunc = `function companyJobTitleOptions(selected = '', departmentName = '') {
    const jobTitlesMap = db.getJobTitlesMap() || {};
    if (!departmentName) return '<option value="">Select Department first</option>';
    const matchedDepartment = Object.keys(jobTitlesMap).find(name => name.trim().toLowerCase() === departmentName.trim().toLowerCase());
    const titles = matchedDepartment ? jobTitlesMap[matchedDepartment] : [];
    return '<option value="">Select Job Title</option>' + titles.map(title =>
        \`<option value="\${escapeHTML(title)}" \${title === selected ? 'selected' : ''}>\${escapeHTML(title)}</option>\`
    ).join('');
}`;

const newFunc = `function companyJobTitleOptions(selected = '', departmentName = '') {
    const jobTitlesMap = db.getJobTitlesMap() || {};
    if (!departmentName) return '<option value="">Select Department first</option>';
    const matchedDepartment = Object.keys(jobTitlesMap).find(name => name.trim().toLowerCase() === departmentName.trim().toLowerCase());
    let titles = matchedDepartment ? jobTitlesMap[matchedDepartment] : [];
    titles = titles.filter(t => !t.includes('General Manager, Executive Director'));
    return '<option value="">Select Job Title</option>' + titles.map(title =>
        \`<option value="\${escapeHTML(title)}" \${title === selected ? 'selected' : ''}>\${escapeHTML(title)}</option>\`
    ).join('');
}`;

code = code.replace(oldFunc, newFunc);
fs.writeFileSync('js/app.js', code);
