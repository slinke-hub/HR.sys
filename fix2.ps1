$content = Get-Content -Raw -Path "js\app.js"

$oldStr = @"
if ('serviceWorker' in navigator) {
    if (localStorage.getItem('pwaPromptDismissed')) return;
"@

$newStr = @"
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
    return; // Install modal disabled by user request
    if (localStorage.getItem('pwaPromptDismissed')) return;
"@

if ($content -match [regex]::Escape($oldStr)) {
    $content = $content -replace [regex]::Escape($oldStr), $newStr
    Set-Content -Path "js\app.js" -Value $content -NoNewline
    Write-Output "Successfully fixed app.js"
} else {
    Write-Output "Pattern not found"
}
