const fs = require('fs');
const path = require('path');

const targetFile = path.join(__dirname, 'js', 'app.js');
let lines = fs.readFileSync(targetFile, 'utf8').split('\n');

let startIndex1 = -1;
let endIndex1 = -1;

for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes("const allUsers = isDepartmentEmployee && currentProfile.department_id")) {
        startIndex1 = i;
    }
    if (startIndex1 >= 0 && lines[i].includes(": fetchedUsers;")) {
        endIndex1 = i;
        break;
    }
}

let startIndex2 = -1;
let endIndex2 = -1;

for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes("} else if (isDepartmentEmployee && currentProfile.department_id) {")) {
        startIndex2 = i;
    }
    if (startIndex2 >= 0 && lines[i].includes("if (rootUsers.length === 0) rootUsers = [currentProfile];")) {
        endIndex2 = i + 1; // Include the closing brace block if possible, wait, next line is '} else {'
        if (lines[i + 1].includes("} else {")) {
            endIndex2 = i;
        }
        break;
    }
}

let changed = false;

if (startIndex2 >= 0 && endIndex2 >= startIndex2) {
    const newRootLogic = `    } else if (isDepartmentEmployee) {
        let myMgr = fetchedUsers.find(u => u.id === currentProfile.manager_id);
        if (myMgr) {
            rootUsers = [myMgr];
        } else {
            rootUsers = [currentProfile];
        }`;
    lines.splice(startIndex2, endIndex2 - startIndex2 + 1, newRootLogic);
    changed = true;
} else {
    console.log("Could not find block 2");
}

if (startIndex1 >= 0 && endIndex1 >= startIndex1) {
    const newLogic = `    let allUsers = fetchedUsers;
    if (isDepartmentEmployee) {
        allUsers = fetchedUsers.filter(user => 
            user.id === currentProfile.manager_id || 
            user.manager_id === currentProfile.manager_id || 
            (currentProfile.department_id && user.department_id === currentProfile.department_id) ||
            user.manager_id === currentProfile.id
        );
    }`;
    lines.splice(startIndex1, endIndex1 - startIndex1 + 1, newLogic);
    changed = true;
} else {
    console.log("Could not find block 1");
}

if (changed) {
    fs.writeFileSync(targetFile, lines.join('\n'), 'utf8');
    console.log("Successfully updated Hierarchy logic in app.js");
}
