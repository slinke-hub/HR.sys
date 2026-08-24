const fs = require('fs');

let appJs = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

// 1. Fix Job Title select width
appJs = appJs.replace(
    'style="width: 210px; padding: 0.25rem; font-size: 0.8rem;"',
    'style="width: 100%; min-width: 130px; max-width: 200px; padding: 0.25rem; font-size: 0.8rem;"'
);

// 2. Fix Department select width
appJs = appJs.replace(
    'style="width: 230px; padding: 0.25rem;"',
    'style="width: 100%; min-width: 130px; max-width: 200px; padding: 0.25rem;"'
);

// 3. Fix Role select width
appJs = appJs.replace(
    '<select data-user-role-select class="form-control" style="width: auto; padding: 0.25rem;"',
    '<select data-user-role-select class="form-control" style="width: 100%; min-width: 100px; max-width: 150px; padding: 0.25rem;"'
);

// Fix Manager select width
appJs = appJs.replace(
    '<select data-user-manager-select class="form-control" style="width: auto; padding: 0.25rem;"',
    '<select data-user-manager-select class="form-control" style="width: 100%; min-width: 120px; max-width: 180px; padding: 0.25rem;"'
);

// 4. Fix Action buttons flex-wrap
appJs = appJs.replace(
    '<div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">\n                                            <button class="btn-secondary" style="padding: 0.4rem; font-size: 0.8rem;" onclick="showEditUserModal(\'${u.id}\')" title="Edit User">',
    '<div style="display: flex; gap: 0.5rem; flex-wrap: nowrap;">\n                                            <button class="btn-secondary" style="padding: 0.4rem; font-size: 0.8rem;" onclick="showEditUserModal(\'${u.id}\')" title="Edit User">'
);
// Also for CRLF just in case
appJs = appJs.replace(
    '<div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">\r\n                                            <button class="btn-secondary" style="padding: 0.4rem; font-size: 0.8rem;" onclick="showEditUserModal(\'${u.id}\')" title="Edit User">',
    '<div style="display: flex; gap: 0.5rem; flex-wrap: nowrap;">\r\n                                            <button class="btn-secondary" style="padding: 0.4rem; font-size: 0.8rem;" onclick="showEditUserModal(\'${u.id}\')" title="Edit User">'
);

// 5. Ensure Contract button doesn't wrap its text
appJs = appJs.replace(
    '<button class="btn-secondary" style="padding: 0.4rem 0.8rem; font-size: 0.8rem;" onclick="navigateToContract',
    '<button class="btn-secondary" style="padding: 0.4rem 0.8rem; font-size: 0.8rem; white-space: nowrap;" onclick="navigateToContract'
);

fs.writeFileSync('e:/HR.sys/js/app.js', appJs);

let dataJs = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

// Add users_department to EN
dataJs = dataJs.replace(
    'users_job_ph: "e.g. Software Engineer",\r\n    users_role: "Role",',
    'users_job_ph: "e.g. Software Engineer",\r\n    users_role: "Role",\r\n    users_department: "Department",'
);
dataJs = dataJs.replace(
    'users_job_ph: "e.g. Software Engineer",\n    users_role: "Role",',
    'users_job_ph: "e.g. Software Engineer",\n    users_role: "Role",\n    users_department: "Department",'
);

// Add users_department to AR
dataJs = dataJs.replace(
    'users_role: "الدور",\r\n    users_role_emp: "موظف",',
    'users_role: "الدور",\r\n    users_department: "القسم",\r\n    users_role_emp: "موظف",'
);
dataJs = dataJs.replace(
    'users_role: "الدور",\n    users_role_emp: "موظف",',
    'users_role: "الدور",\n    users_department: "القسم",\n    users_role_emp: "موظف",'
);

fs.writeFileSync('e:/HR.sys/js/data.js', dataJs);

console.log("Done");
