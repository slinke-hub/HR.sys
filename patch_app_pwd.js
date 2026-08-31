const fs = require('fs');
const path = require('path');

const targetFile = path.join(__dirname, 'js', 'app.js');
let content = fs.readFileSync(targetFile, 'utf8');

const originalFunc = `window.handleUpdatePassword = async function (e) {
    e.preventDefault();
    const newPwd = document.getElementById('newPassword').value;
    const { success, error } = await db.updateUserPassword(newPwd);
    if (success) {
        showToast(t('toast_password_updated_successfully'), "success");
        document.getElementById('newPassword').value = '';
    } else {
        showToast(error?.message || "Error updating password.", "danger");
    }
}`;

const newFunc = `window.handleUpdatePassword = async function (e) {
    e.preventDefault();
    
    // Check password change limit
    if (currentUserProfile && (currentUserProfile.password_changes_count || 0) >= 3) {
        showToast(t('password_change_limit_reached') || "You have reached the maximum number of password changes (3). Please contact an admin to reset your password.", "warning");
        return;
    }
    
    const newPwd = document.getElementById('newPassword').value;
    const { success, error } = await db.updateUserPassword(newPwd);
    if (success) {
        showToast(t('toast_password_updated_successfully'), "success");
        document.getElementById('newPassword').value = '';
        
        // Increment count
        await db.incrementPasswordChangeCount(currentUser.id);
        if (currentUserProfile) {
            currentUserProfile.password_changes_count = (currentUserProfile.password_changes_count || 0) + 1;
        }
    } else {
        showToast(error?.message || "Error updating password.", "danger");
    }
}`;

if (content.includes(originalFunc)) {
    content = content.replace(originalFunc, newFunc);
    fs.writeFileSync(targetFile, content, 'utf8');
    console.log("Updated app.js for password limits.");
} else {
    console.log("Could not find the target function in app.js");
}
