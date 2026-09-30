$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'

$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$StagingRef = 'jcfyyxsuspukcmybyhjj'
$ExpectedReleaseId = 'productivity-abc-2026-09-30'
$ExpectedReleaseFingerprint = '8a19ff52239be3550299460536aac9dfa2394d5dfe1eaad21e2a90d4635274c0'
$ExpectedMigrationFiles = @(
  'supabase/migrations/20260928120000_notification_backend_services.sql',
  'supabase/migrations/20260930100000_auth_backend_services.sql',
  'supabase/migrations/20260930101000_client_backend_services.sql',
  'supabase/migrations/20260930102000_deal_backend_services.sql',
  'supabase/migrations/20260930103000_file_backend_services.sql',
  'supabase/migrations/20260930104000_productivity_phase_a.sql',
  'supabase/migrations/20260930105000_productivity_phase_b.sql',
  'supabase/migrations/20260930106000_productivity_phase_c.sql'
)
$ExpectedEdgeFunctions = @('file-signed-url')
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ProductionBuildRoot = Join-Path $Root 'www-production'
$LinkedRefPath = Join-Path $Root 'supabase/.temp/project-ref'
$ManifestPath = Join-Path $Root 'supabase/production/productivity-abc-production-manifest.json'

function Quote-ProcessArgument([string]$Value) {
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-SupabaseCli([string[]]$Arguments) {
  $command = Get-Command supabase -CommandType Application -ErrorAction Stop
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = if ($command.Path) { $command.Path } else { $command.Source }
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'Unable to start the Supabase CLI.' }
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

if (Test-Path -LiteralPath $LinkedRefPath) {
  $linked = (Get-Content -Raw -LiteralPath $LinkedRefPath).Trim()
  if ($linked -ceq $StagingRef) {
    Write-Warning "Repository remains linked to staging ($StagingRef). This read-only preflight uses explicit production project selection and does not relink the repository."
  } elseif ($linked -ceq $ProductionRef) {
    Write-Output 'Local link is production; no relink performed.'
  } else {
    Write-Warning "Local link is '$linked'. It will not be used by this preflight."
  }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Missing release manifest: $ManifestPath" }
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ([string]$manifest.targetProjectRef -cne $ProductionRef) { throw 'Release manifest target is not production.' }
$manifestStagingRef = [string]$manifest.stagingProjectRef
if ($manifestStagingRef -cne $StagingRef) { throw 'Manifest staging reference is not the reviewed staging project.' }
if ([string]$manifest.releaseId -cne $ExpectedReleaseId) { throw 'Manifest release identity is not the reviewed release.' }
if ([string]$manifest.status -notin @('BLOCKED_PENDING_PRODUCTION_INSPECTION', 'BLOCKED_PENDING_FREEZE_AND_RECOVERY', 'READY_FOR_MANUAL_APPROVAL')) {
  throw 'Unexpected release-manifest status; stop and review it before proceeding.'
}
$migrationFiles = @($manifest.migrationFiles)
if (($migrationFiles -join '|') -cne ($ExpectedMigrationFiles -join '|')) { throw 'Manifest migration inventory does not exactly match the reviewed 8-migration release.' }
$edgeFunctions = @($manifest.edgeFunctions)
if (($edgeFunctions -join '|') -cne ($ExpectedEdgeFunctions -join '|')) { throw 'Manifest Edge Function inventory does not match the reviewed release.' }
$migrationParts = @()
foreach ($relative in $migrationFiles) {
  if ([string]$relative -match '(?i)staging|initial_schema|clear_|reset_|purge_|baseline') { throw "Unsafe or staging-only migration in manifest: $relative" }
  $full = Join-Path $Root $relative
  if (-not (Test-Path -LiteralPath $full)) { throw "Manifest migration is missing: $relative" }
  $migrationParts += ($relative + '=' + (Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToLowerInvariant())
}
$canonical = [string]$manifest.releaseId + '|' + [string]$manifest.targetProjectRef + '|' + $manifestStagingRef + '|' + ($edgeFunctions -join ',') + '|' + ($migrationParts -join '|')
$sha = [System.Security.Cryptography.SHA256]::Create()
$actualFingerprint = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).Replace('-', '').ToLowerInvariant()
if ($actualFingerprint -cne [string]$manifest.releaseFingerprint -or $actualFingerprint -cne $ExpectedReleaseFingerprint) { throw 'Manifest release fingerprint does not match the reviewed release.' }
$gitCommand = @(Get-Command git -CommandType Application -ErrorAction Stop)[0]
$gitPath = if ($gitCommand.Path) { $gitCommand.Path } else { $gitCommand.Source }
$dirtyFiles = @(& $gitPath -C $Root diff --name-only HEAD 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Unable to verify the working tree release state.' }
$releaseDirtyFiles = @($dirtyFiles | Where-Object { $_ -and $_ -ne 'supabase/.temp/cli-latest' -and ($_ -match '^(supabase/production/|supabase/migrations/|supabase/functions/|js/|src/|css/|scripts/|package\.json$|vercel\.json$|index\.html$)') })
if ($releaseDirtyFiles.Count -gt 0) { throw ('ABORTED: tracked runtime/release modifications are present: ' + ($releaseDirtyFiles -join ', ')) }

if (-not (Test-Path -LiteralPath $ProductionBuildRoot)) {
  throw "Missing explicit production browser artifact: $ProductionBuildRoot. Run the production build first."
}

$migrationResult = Invoke-SupabaseCli @('migration', 'list', '--project-ref', $ProductionRef)
if ($migrationResult.ExitCode -ne 0) {
  throw 'Production migration inspection failed. Authenticate Supabase locally and rerun this read-only preflight.'
}

$requiredAssets = @(
  'index.html',
  'js/app.js',
  'js/db.js',
  'js/shared-services.js',
  'css/layout.css',
  'css/components.css',
  'css/task-manager-mobile-final.css'
)
foreach ($asset in $requiredAssets) {
  $assetPath = Join-Path $ProductionBuildRoot $asset
  if (-not (Test-Path -LiteralPath $assetPath)) { throw "Missing production build asset: $asset" }
}

$runtimeText = (($requiredAssets | ForEach-Object { Get-Content -Raw -LiteralPath (Join-Path $ProductionBuildRoot $_) }) -join "`n")
$secretPatterns = @('service_role', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEY', 'SUPABASE_ACCESS_TOKEN', 'VAPID_PRIVATE_KEY', 'PUSH_DISPATCH_SECRET', 'postgresql://')
foreach ($pattern in $secretPatterns) {
  if ($runtimeText -match [regex]::Escape($pattern)) { throw "Privileged or secret material marker found in production build: $pattern" }
}

# The explicit production artifact must not contain the staging runtime or
# staging project reference. The local staging bundle in www/ is intentionally
# excluded from this production-only inspection.
if ($runtimeText -match [regex]::Escape($StagingRef)) {
  throw 'Staging project reference is present in production browser assets.'
}

$productionOrigin = "https://$ProductionRef.supabase.co"
if ($runtimeText -notmatch [regex]::Escape($productionOrigin)) {
  throw 'Production Supabase origin is missing from the production browser artifact.'
}

Write-Output "PRODUCTION PREFLIGHT: READ-ONLY CHECKS PASSED FOR $ProductionRef"
Write-Output 'Migration state was queried without changing the project; review the exact pending set manually before approval.'
Write-Output 'No production migration, function deployment, data change, Auth change, or relink was performed.'
