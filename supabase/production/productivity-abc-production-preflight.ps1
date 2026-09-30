$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'

$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$StagingRef = 'jcfyyxsuspukcmybyhjj'
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
if ([string]$manifest.status -notin @('BLOCKED_PENDING_PRODUCTION_INSPECTION', 'BLOCKED_PENDING_FREEZE_AND_RECOVERY', 'READY_FOR_MANUAL_APPROVAL')) {
  throw 'Unexpected release-manifest status; stop and review it before proceeding.'
}

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
