const fs = require('fs');
const path = require('path');

const targetFile = path.join(__dirname, 'js', 'app.js');
let lines = fs.readFileSync(targetFile, 'utf8').split('\n');

let startIndex = -1;
let endIndex = -1;

for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes("// Inactivity Tracker (5 Minutes)")) {
        startIndex = i;
    }
    if (lines[i].includes("// User Management Actions")) {
        endIndex = i;
        break;
    }
}

if (startIndex >= 0 && endIndex > startIndex) {
    const newContent = `// Inactivity Tracker (5 Minutes)
let inactivityTimeout;
function resetInactivityTimeout() {
    clearTimeout(inactivityTimeout);
    if (currentUser && currentView !== 'login') {
        inactivityTimeout = setTimeout(() => {
            showToast(t('timeout_message') || "Logged out due to inactivity", "warning");
            window.handleLogout();
        }, 5 * 60 * 1000); // 5 minutes
    }
}

// ==========================================
// PWA Installation
// ==========================================
let deferredPrompt;

if ('serviceWorker' in navigator) {
    window.addEventListener('load', async () => {
        try {
            const registration = await navigator.serviceWorker.register('/sw.js', { scope: '/' });
            registration.update().catch(() => {});
            console.log('MUQAM HR background service registered.');
        } catch (error) {
            console.warn('Background service registration failed:', error?.message || error);
        }
    });
}

function showInstallBanner() {
    return; // Disabled by user request
}
`;
    
    lines.splice(startIndex, endIndex - startIndex, newContent);
    fs.writeFileSync(targetFile, lines.join('\n'), 'utf8');
    console.log("Successfully repaired app.js");
} else {
    console.log("Could not find bounds!");
}
