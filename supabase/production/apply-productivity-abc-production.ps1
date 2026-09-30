param([switch]$ConfirmProductionDeployment)

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
$LinkedRefPath = Join-Path $Root 'supabase/.temp/project-ref'
$ManifestPath = Join-Path $Root 'supabase/production/productivity-abc-production-manifest.json'

function Quote-ProcessArgument([string]$Value) {
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}
function Sanitize-Diagnostic([string]$Text) {
  if ($null -eq $Text) { return '' }
  $safe = $Text -replace '(?i)(access[_ -]?token|service[_ -]?role|password|secret|api[_ -]?key|authorization)\s*[:=]\s*[^\s,;]+', '$1=[REDACTED]'
  if ($safe.Length -gt 2000) { return $safe.Substring(0, 2000) + '…' }
  return $safe.Trim()
}
function Invoke-SupabaseCli([string[]]$Arguments, [string]$Operation) {
  $command = Get-Command supabase -CommandType Application -ErrorAction Stop
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = if ($command.Path) { $command.Path } else { $command.Source }
  $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true; $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
  $process = New-Object System.Diagnostics.Process; $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'Unable to start the Supabase CLI.' }
  $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync(); $process.WaitForExit()
  $stdout = $outTask.GetAwaiter().GetResult(); $stderr = $errTask.GetAwaiter().GetResult()
  if ($process.ExitCode -ne 0) {
    throw "Supabase operation '$Operation' failed with exit code $($process.ExitCode). stdout=$(Sanitize-Diagnostic $stdout) stderr=$(Sanitize-Diagnostic $stderr)"
  }
  [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

if (-not (Test-Path -LiteralPath $LinkedRefPath)) { throw 'Missing local Supabase project reference.' }
$linked = (Get-Content -Raw -LiteralPath $LinkedRefPath).Trim()
if ($linked -cne $StagingRef -or $linked -ceq $ProductionRef) {
  throw "ABORTED: local link is '$linked'. This production mutator requires the repository to remain linked to staging and never relinks automatically."
}
if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Missing release manifest: $ManifestPath" }
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ([string]$manifest.targetProjectRef -cne $ProductionRef) { throw 'Manifest target is not production.' }
$manifestStagingRef = [string]$manifest.stagingProjectRef
if ($manifestStagingRef -cne $StagingRef) { throw 'Manifest staging reference is not the reviewed staging project.' }
if ([string]$manifest.releaseId -cne $ExpectedReleaseId) { throw 'Manifest release identity is not the reviewed release.' }
if ([string]$manifest.status -ne 'READY_FOR_MANUAL_APPROVAL') { throw 'Release manifest is not approved for a production deployment.' }

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
Write-Output "TARGET PROJECT: $ProductionRef"
Write-Output 'The following reviewed migration files would be executed, in order:'
$migrationFiles | ForEach-Object { Write-Output (" - " + $_) }
Write-Output 'No Auth users, synthetic records, production cleanup, or staging identities will be created.'
if (-not $ConfirmProductionDeployment) {
  $answer = Read-Host "Type DEPLOY PRODUCTION to continue, or anything else to abort"
  if ($answer -cne 'DEPLOY PRODUCTION') { throw 'Deployment cancelled before the first database-changing operation.' }
}

foreach ($relative in $migrationFiles) {
  $full = Join-Path $Root $relative
  [void](Invoke-SupabaseCli -Arguments @('db', 'query', '--linked', '--project-ref', $ProductionRef, '--file', $full) -Operation ("migration $relative"))
  Write-Output ("Applied: " + $relative)
}

$functionNames = $edgeFunctions
foreach ($functionName in $functionNames) {
  if ([string]$functionName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid Edge Function name in manifest: $functionName" }
  [void](Invoke-SupabaseCli -Arguments @('functions', 'deploy', [string]$functionName, '--project-ref', $ProductionRef) -Operation ("Edge Function $functionName"))
  Write-Output ("Deployed Edge Function: " + $functionName)
}

Write-Output "PRODUCTION DEPLOYMENT COMPLETE: $ProductionRef"
