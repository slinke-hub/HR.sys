const fs = require('fs');

const indexPath = 'e:\\HR.sys\\index.html';
let html = fs.readFileSync(indexPath, 'utf8');

// Find all occurrences of addUserModal
let splitHtml = html.split('<div class="modal" id="addUserModal">');

if (splitHtml.length > 2) {
    // Keep everything before the first one
    let newHtml = splitHtml[0];
    
    // First modal is splitHtml[1], which goes up to the next modal or end.
    // The modal ends at the matching </div> 
    // We will just replace it with the new layout.
    
    const newModal = `<div class="modal" id="addUserModal">
        <div class="modal-content fade-in-up">
            <div class="modal-header">
                <h2><i data-lucide="user-plus"></i> Add New User</h2>
                <button class="icon-btn" onclick="closeAddUserModal()">
                    <i data-lucide="x"></i>
                </button>
            </div>
            <form autocomplete="off" onsubmit="handleCreateUser(event)" id="addUserForm" class="user-modal-form">
                <div class="user-modal-actions" style="display: flex; gap: 1rem; margin-bottom: 1rem;">
                    <button type="button" class="btn btn-secondary w-full" onclick="closeAddUserModal()">Cancel</button>
                    <button type="submit" class="btn btn-primary w-full">Add User</button>
                </div>
                <div class="user-modal-grid">
                    <div class="form-group">
                        <label class="form-label">Employee ID</label>
                        <input type="text" autocomplete="off" id="newEmployeeId" class="form-control" value="MQ-" placeholder="MQ-XXXX" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">Full Name</label>
                        <input type="text" autocomplete="off" id="newFullName" class="form-control" placeholder="Enter full name" required>
                    </div>
                    <div class="form-group">
                        <label class="form-label">Full Name in Arabic</label>
                        <input type="text" autocomplete="off" id="newFullNameAr" class="form-control" placeholder="Enter full name in Arabic">
                    </div>
                    <div class="form-group">
                        <label class="form-label">Email</label>
                        <input type="email" autocomplete="off" id="newEmail" class="form-control" placeholder="Enter email address (Optional)">
                    </div>
                    <div class="form-group">
                        <label class="form-label">Phone</label>
                        <input type="tel" autocomplete="off" id="newPhone" class="form-control" placeholder="Enter phone number (Optional)">
                    </div>
                    <div class="form-group">
                        <label class="form-label">Temp Password</label>
                        <input type="text" autocomplete="off" id="newPassword" class="form-control" placeholder="Enter temporary password" required>
                    </div>
                </div>
            </form>
        </div>
    </div>`;

    // Now we need to append the rest of the file, skipping the original modal(s).
    // Let's use regex to replace both modals.
    
    // Replace first one
    html = html.replace(/<div class="modal" id="addUserModal">[\s\S]*?<\/form>\s*<\/div>\s*<\/div>/, newModal);
    
    // Replace second one (if it still exists in the string after the first replacement)
    html = html.replace(/<div class="modal" id="addUserModal">[\s\S]*?<\/form>\s*<\/div>\s*<\/div>/, '');

    fs.writeFileSync(indexPath, html);
    console.log("Successfully updated index.html");
}
