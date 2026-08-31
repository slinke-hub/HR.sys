$lines = Get-Content "js\app.js"
$startIndex = -1
$endIndex = -1

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "// Inactivity Tracker \(5 Minutes\)") {
        $startIndex = $i
    }
    if ($lines[$i] -match "// User Management Actions") {
        $endIndex = $i
        break
    }
}

if ($startIndex -ge 0 -and $endIndex -gt $startIndex) {
    $newContent = @"
// Inactivity Tracker (5 Minutes)
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

"@

    $outLines = @()
    for ($i = 0; $i -lt $startIndex; $i++) { $outLines += $lines[$i] }
    $outLines += $newContent
    for ($i = $endIndex; $i -lt $lines.Count; $i++) { $outLines += $lines[$i] }
    
    $success = $false
    while (-not $success) {
        try {
            Set-Content -Path "js\app.js" -Value ($outLines -join "`n") -NoNewline -ErrorAction Stop
            $success = $true
            Write-Output "Successfully repaired app.js"
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
} else {
    Write-Output "Could not find bounds!"
}
