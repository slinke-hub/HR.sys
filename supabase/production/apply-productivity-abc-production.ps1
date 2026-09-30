param([switch]$ConfirmProductionDeployment)

$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$StagingRef = 'jcfyyxsuspukcmybyhjj'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
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
  $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true; $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
  $process = New-Object System.Diagnostics.Process; $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'Unable to start the Supabase CLI.' }
  $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync(); $process.WaitForExit()
  $stdout = $outTask.GetAwaiter().GetResult(); $stderr = $errTask.GetAwaiter().GetResult()
  if ($process.ExitCode -ne 0) { throw "Supabase command failed with exit code $($process.ExitCode)." }
  [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

if (-not (Test-Path -LiteralPath $LinkedRefPath)) { throw 'Missing local Supabase project reference.' }
$linked = (Get-Content -Raw -LiteralPath $LinkedRefPath).Trim()
if ($linked -cne $ProductionRef -or $linked -ceq $StagingRef) {
  throw "ABORTED: local link is '$linked'. This script requires an explicit production link and never relinks automatically."
}
if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Missing release manifest: $ManifestPath" }
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ([string]$manifest.targetProjectRef -cne $ProductionRef) { throw 'Manifest target is not production.' }
if ([string]$manifest.status -ne 'READY_FOR_MANUAL_APPROVAL') { throw 'Release manifest is not approved for a production deployment.' }

$migrationFiles = @($manifest.migrationFiles)
if ($migrationFiles.Count -eq 0) { throw 'No reviewed production migration files are listed; refusing to deploy.' }
foreach ($relative in $migrationFiles) {
  if ([string]$relative -match '(?i)staging|initial_schema|clear_|reset_|purge_|baseline') { throw "Unsafe or staging-only migration in manifest: $relative" }
  $full = Join-Path $Root $relative
  if (-not (Test-Path -LiteralPath $full)) { throw "Manifest migration is missing: $relative" }
}

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
  [void](Invoke-SupabaseCli @('db', 'query', '--linked', '--file', $full))
  Write-Output ("Applied: " + $relative)
}

$functionNames = @($manifest.edgeFunctions)
foreach ($functionName in $functionNames) {
  if ([string]$functionName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid Edge Function name in manifest: $functionName" }
  [void](Invoke-SupabaseCli @('functions', 'deploy', [string]$functionName, '--project-ref', $ProductionRef))
  Write-Output ("Deployed Edge Function: " + $functionName)
}

Write-Output "PRODUCTION DEPLOYMENT COMPLETE: $ProductionRef"
