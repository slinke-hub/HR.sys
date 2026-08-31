const fs = require('fs');
const path = require('path');

const targetFile = path.join(__dirname, 'js', 'app.js');
let content = fs.readFileSync(targetFile, 'utf8');

const lines = content.split('\n');

const startIdx = lines.findIndex(line => line.includes('window.handleUpdateProfilePhoto = async function (e) {'));
const endIdx = lines.findIndex((line, idx) => idx > startIdx && line.includes('window.handleUpdateProfileDetails = async function (e) {'));

if (startIdx !== -1 && endIdx !== -1) {
    const newBlock = `window.handleUpdateProfilePhoto = async function (e) {
    e.preventDefault();
    const fileInput = document.getElementById('avatarFile');
    if (!fileInput.files || fileInput.files.length === 0) return;

    const file = fileInput.files[0];
    const reader = new FileReader();
    reader.onload = async function (event) {
        const rawUrl = event.target.result;

        // Compress image using canvas to ensure lightweight base64 string
        const img = new Image();
        img.onload = async function () {
            const canvas = document.createElement('canvas');
            const maxDim = 250;
            let width = img.width;
            let height = img.height;

            if (width > height) {
                if (width > maxDim) {
                    height = Math.round((height * maxDim) / width);
                    width = maxDim;
                }
            } else {
                if (height > maxDim) {
                    width = Math.round((width * maxDim) / height);
                    height = maxDim;
                }
            }

            canvas.width = width;
            canvas.height = height;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(img, 0, 0, width, height);

            const compressedBase64 = canvas.toDataURL('image/jpeg', 0.85);

            localStorage.setItem('user_avatar_' + currentUser.id, compressedBase64);
            const { success, error } = await db.updateProfilePhoto(currentUser.id, compressedBase64);
            if (success) {
                showToast(t('toast_profile_photo_updated') || 'Profile photo updated successfully!', "success");
                const topAvatar = document.getElementById('topbarAvatar');
                if (topAvatar) topAvatar.src = compressedBase64;

                if (currentUser) currentUser.avatar_url = compressedBase64;
                if (currentUserProfile) currentUserProfile.avatar_url = compressedBase64;

                // Clear view cache so new profile picture immediately reflects on Dashboard Hierarchy
                if (window.viewHTMLCache) {
                    delete window.viewHTMLCache.dashboard;
                    delete window.viewHTMLCache.profile;
                    delete window.viewHTMLCache.users;
                }
                renderView('profile');
            } else {
                localStorage.removeItem('user_avatar_' + currentUser.id);
                showToast(error?.message || t('toast_error_updating_photo') || 'Error updating profile photo', "danger");
            }
        };
        img.src = rawUrl;
    };
    reader.readAsDataURL(file);
}

window.handleUpdatePassword = async function (e) {
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
}
`;

    // Replace everything from startIdx to endIdx - 1
    const newLines = [
        ...lines.slice(0, startIdx),
        newBlock,
        ...lines.slice(endIdx)
    ];
    
    fs.writeFileSync(targetFile, newLines.join('\n'), 'utf8');
    console.log("Successfully restored and updated app.js");
} else {
    console.log("Could not find the target range in app.js");
}
