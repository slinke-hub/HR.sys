[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$ProjectRef,
  [Parameter(Mandatory = $true)] [string]$CaFile,
  [switch]$Execute,
  [string]$ApprovalReference,
  [string]$ApprovedCommit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedRef = 'jcfyyxsuspukcmybyhjj'
$expectedHost = 'db.jcfyyxsuspukcmybyhjj.supabase.co'
$expectedBranch = 'codex/production-crm-release-1a'
$expectedHead = '874181273a608aea73d26d20dce379074773e849'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$integrityHelper = Join-Path $PSScriptRoot 'crm-release-1a-integrity.ps1'
if (-not (Test-Path -LiteralPath $integrityHelper -PathType Leaf)) { throw 'STOP: integrity verifier is missing.' }
. $integrityHelper
$migrationDir = Join-Path $root 'supabase\migrations'
$linkFile = Join-Path $root 'supabase\.temp\project-ref'
$preflightSql = Join-Path $root 'docs\CRM_RELEASE_1A_STAGING_PREFLIGHT.sql'
$postcheckSql = Join-Path $root 'docs\CRM_RELEASE_1A_STAGING_POSTCHECKS.sql'
$catalogSql = Join-Path $root 'docs\CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql'

$migrations = @(
  [pscustomobject]@{ Version='20261022100000'; File='20261022100000_crm_release_1a.sql'; Sha256='1F6D6EBE995195A46AC29CD005F652673BB11994512E3A2E206AACFD79F91301' },
  [pscustomobject]@{ Version='20261024100000'; File='20261024100000_crm_mq20_contact_task_visibility.sql'; Sha256='E0232767A24E4FCF0B4A4D20F6E9328F2F3032653C654763CE14B07A600AED6D' },
  [pscustomobject]@{ Version='20261026100000'; File='20261026100000_mq20_task_service_authorization_hardening.sql'; Sha256='BDA9573A6B04BC54E7DE42E1ADA154FEA9B7335A903D41FD4C4DE54B6825A28A' },
  [pscustomobject]@{ Version='20261027100000'; File='20261027100000_task_dependency_visibility_hardening.sql'; Sha256='F33737D78BEFC42D0E0063AB286E749964363B38B64681BE73E00931A14D2445' }
)
$historicalVersions = @('20260830000000','20261001100000','20261005100000','20261005110000')
$releaseVersions = @($migrations | ForEach-Object Version)
$sortedReleaseVersions = @($releaseVersions | Sort-Object)
if (($releaseVersions -join ',') -cne ($sortedReleaseVersions -join ',')) {
  throw 'STOP: Release migration array is not in timestamp order.'
}

function Stop-Release([string]$Message) {
  throw "STOP: $Message"
}

function Confirm-ExactPhrase([string]$Phrase) {
  $typed = Read-Host "Type exactly: $Phrase"
  if ($typed -cne $Phrase) { Stop-Release 'Required explicit confirmation was not provided.' }
}

function Invoke-VerifiedPsql {
  param([string]$Query, [string]$File, [string[]]$Variables = @(), [switch]$TuplesOnly)
  $args = @('-X','-W','-v','ON_ERROR_STOP=1','-d',$script:connInfo)
  foreach ($variable in $Variables) { $args += @('-v',$variable) }
  if ($TuplesOnly) { $args += @('-q','-A','-t') }
  if ($File) { $args += @('-f',$File) } elseif ($Query) { $args += @('-c',$Query) }
  else { Stop-Release 'No SQL query or file supplied.' }
  # Leave stderr attached to the console so libpq's hidden -W prompt remains visible.
  $output = & $script:psqlName @args
  $code = $LASTEXITCODE
  if ($code -ne 0) { Stop-Release "psql failed (exit $code); no retry will be attempted. Recheck database and ledger state before recovery." }
  return @($output | ForEach-Object { $_.ToString() })
}

function Get-LedgerVersions {
  $rows = Invoke-VerifiedPsql -TuplesOnly -Query "SELECT version::text || E'\t' || COALESCE(name, '') FROM supabase_migrations.schema_migrations ORDER BY version;"
  return @($rows | ForEach-Object { $_.TrimEnd("`r", "`n") } | Where-Object { $_.Length -gt 0 })
}

function Test-LedgerHasVersion([string[]]$Entries, [string]$Version) {
  return @($Entries | Where-Object { $_.StartsWith("$Version`t", [StringComparison]::Ordinal) }).Count -gt 0
}

function Assert-LedgerState([string[]]$Baseline, [string[]]$AddedVersions, [string]$Checkpoint) {
  $actual = @(Get-LedgerVersions)
  $baseVersions = @($Baseline | ForEach-Object { ($_ -split "`t",2)[0] })
  $actualBase = @($actual | Where-Object { $baseVersions -contains ($_ -split "`t",2)[0] } | Sort-Object)
  $baselineSorted = @($Baseline | Sort-Object)
  $actualAdded = @($actual | Where-Object { $AddedVersions -contains ($_ -split "`t",2)[0] })
  $unexpected = @($actual | Where-Object {
    $version = ($_ -split "`t",2)[0]
    $baseVersions -notcontains $version -and $AddedVersions -notcontains $version
  })
  $addedCountsOk = $true
  foreach ($version in $AddedVersions) {
    if (@($actualAdded | Where-Object { ($_ -split "`t",2)[0] -ceq $version }).Count -ne 1) { $addedCountsOk = $false }
  }
  if (@(Compare-Object -ReferenceObject $baselineSorted -DifferenceObject $actualBase).Count -gt 0 -or
      $unexpected.Count -gt 0 -or -not $addedCountsOk) {
    Stop-Release "Migration ledger changed unexpectedly at $Checkpoint. Stop and reconcile; do not replay SQL."
  }
}

function Assert-BaselineLedger([string[]]$Versions) {
  foreach ($version in $historicalVersions) {
    if (-not (Test-LedgerHasVersion $Versions $version)) { Stop-Release "Required historical migration $version is absent." }
  }
  foreach ($version in $releaseVersions) {
    if (Test-LedgerHasVersion $Versions $version) { Stop-Release "Release migration $version is already recorded." }
  }
}

if ($ProjectRef -cne $expectedRef) { Stop-Release 'Project reference is not the approved staging project.' }
if (-not (Test-Path -LiteralPath $CaFile -PathType Leaf)) { Stop-Release 'Approved trusted CA file is missing.' }
if (-not (Test-Path -LiteralPath $linkFile -PathType Leaf) -or (Get-Content -Raw -LiteralPath $linkFile).Trim() -cne $expectedRef) {
  Stop-Release 'Local Supabase link does not point to the approved staging project.'
}
foreach ($name in @('PGPASSWORD','PGPASSFILE','PGSERVICE','PGSERVICEFILE')) {
  if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) {
    Stop-Release "$name is set; this runner requires an interactive, non-echoing psql password prompt."
  }
}

$branch = (& git -C $root branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -cne $expectedBranch) { Stop-Release 'Unexpected Git branch.' }
$head = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { Stop-Release 'Could not verify Git HEAD.' }
& git -C $root merge-base --is-ancestor $expectedHead $head 2>$null
if ($LASTEXITCODE -ne 0) { Stop-Release 'Current HEAD does not descend from the reviewed release baseline.' }
$allowedPackageChanges = @(
  'docs/CRM_RELEASE_1A_RECOVERY.md',
  'docs/CRM_RELEASE_1A_STAGING_EXECUTION.md',
  'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql',
  'docs/CRM_RELEASE_1A_STAGING_POSTCHECKS.sql',
  'scripts/crm-release-1a-staging.ps1',
  'scripts/run-crm-release-1a-pg17-docker.ps1',
  'tests/crm-release-1a-staging-runner.mock.test.ps1',
  'tests/crm-release-1a-postgres.test.cjs',
  'tests/fixtures/crm-release-1a-baseline.sql',
  'tests/fixtures/crm-release-1a-assertions.sql',
  'scripts/crm-release-1a-integrity.ps1',
  'tests/crm-release-1a-integrity.test.ps1',
  'docs/CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql'
)
$changedPaths = @(& git -C $root diff --name-only $expectedHead $head)
if ($LASTEXITCODE -ne 0) { Stop-Release 'Could not inspect changes since the reviewed baseline.' }
foreach ($statusLine in @(& git -C $root status --porcelain --untracked-files=all)) {
  if ($statusLine.Length -ge 4) { $changedPaths += $statusLine.Substring(3) }
}
$unexpectedPaths = @($changedPaths | Sort-Object -Unique | Where-Object { $allowedPackageChanges -cnotcontains $_.Replace('\','/') })
if ($unexpectedPaths.Count -gt 0) { Stop-Release "Unexpected workspace changes: $($unexpectedPaths -join ', ')" }

foreach ($m in $migrations) {
  $path = Join-Path $migrationDir $m.File
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Release "Missing migration file $($m.File)." }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -cne $m.Sha256) { Stop-Release "Checksum mismatch for $($m.File)." }
  $sql = Get-Content -Raw -LiteralPath $path
  if ([regex]::Matches($sql,'(?im)^\s*BEGIN\s*;').Count -ne 1 -or
      [regex]::Matches($sql,'(?im)^\s*COMMIT\s*;').Count -ne 1) { Stop-Release "Unexpected transaction boundaries in $($m.File)." }
}
foreach ($requiredFile in @($preflightSql,$postcheckSql,$catalogSql)) {
  if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) { Stop-Release "Missing validation file $requiredFile." }
}
$criticalFiles = @(
  'docs/CRM_RELEASE_1A_RECOVERY.md',
  'docs/CRM_RELEASE_1A_STAGING_EXECUTION.md',
  'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql',
  'docs/CRM_RELEASE_1A_STAGING_POSTCHECKS.sql',
  'docs/CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql',
  'scripts/crm-release-1a-staging.ps1',
  'scripts/crm-release-1a-integrity.ps1',
  'scripts/run-crm-release-1a-pg17-docker.ps1',
  'tests/crm-release-1a-postgres.test.cjs',
  'tests/crm-release-1a-staging-runner.mock.test.ps1',
  'tests/crm-release-1a-integrity.test.ps1',
  'tests/fixtures/crm-release-1a-assertions.sql',
  'tests/fixtures/crm-release-1a-baseline.sql',
  'supabase/migrations/20261022100000_crm_release_1a.sql',
  'supabase/migrations/20261024100000_crm_mq20_contact_task_visibility.sql',
  'supabase/migrations/20261026100000_mq20_task_service_authorization_hardening.sql',
  'supabase/migrations/20261027100000_task_dependency_visibility_hardening.sql'
)
$relevantUntrackedPatterns = @(
  'scripts/*crm-release-1a*',
  'docs/CRM_RELEASE_1A_STAGING_*',
  'docs/CRM_RELEASE_1A_RECOVERY.md',
  'docs/CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql',
  'supabase/migrations/202610*.sql',
  'tests/crm-release-1a*',
  'tests/fixtures/crm-release-1a-*'
)
$psqlCommand = Get-Command psql -ErrorAction SilentlyContinue
$supabaseCommand = Get-Command supabase -ErrorAction SilentlyContinue
if ($null -eq $psqlCommand) { Stop-Release 'PostgreSQL psql client is unavailable.' }
if ($Execute -and $null -eq $supabaseCommand) { Stop-Release 'Supabase CLI is required for the approved ledger step.' }
if ($Execute -and [string]::IsNullOrWhiteSpace($ApprovalReference)) { Stop-Release 'Execution mode requires a separate administrator approval reference.' }
if ($Execute -and [string]::IsNullOrWhiteSpace($ApprovedCommit)) { Stop-Release 'Execution mode requires the full independently reviewed package commit SHA.' }

$ca = (Resolve-Path -LiteralPath $CaFile).Path.Replace('\','/')
$pemReader = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection].GetMethod('ImportFromPem')
if ($null -eq $pemReader) { Stop-Release 'PowerShell 7/.NET 5 or later is required to validate the PEM CA file.' }
try {
  $caCertificates = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
  $caCertificates.ImportFromPem([IO.File]::ReadAllText($ca))
  if ($caCertificates.Count -eq 0) { throw 'No certificates were found.' }
}
catch { Stop-Release 'The supplied trusted CA file is not a valid PEM certificate.' }
$caFingerprints = @()
foreach ($caCertificate in $caCertificates) {
  $basicConstraints = @($caCertificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' } | Select-Object -First 1)
  if (-not $basicConstraints -or -not ([System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]$basicConstraints[0]).CertificateAuthority) {
    Stop-Release 'Every certificate in the supplied CA bundle must be marked as a certificate authority.'
  }
  $caFingerprints += $caCertificate.GetCertHashString([System.Security.Cryptography.HashAlgorithmName]::SHA256)
  $caCertificate.Dispose()
}
if ($Execute) {
  Confirm-ExactPhrase "CONFIRM TRUSTED STAGING CA SHA256 $($caFingerprints -join ',')"
}
$script:caUri = [Uri]::EscapeDataString($ca)
$script:connInfo = "postgresql://postgres@${expectedHost}:5432/postgres?sslmode=verify-full&sslrootcert=$script:caUri"
$script:psqlName = 'psql'
$script:supabaseName = 'supabase'

$integritySnapshot = $null
if ($Execute) {
  try {
    $integritySnapshot = New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $ApprovedCommit `
      -CriticalFiles $criticalFiles -RelevantUntrackedPatterns $relevantUntrackedPatterns
  } catch { Stop-Release "Execution package integrity validation failed: $($_.Exception.Message)" }
  $preflightSql = $integritySnapshot.Files['docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql'].SnapshotPath
  $postcheckSql = $integritySnapshot.Files['docs/CRM_RELEASE_1A_STAGING_POSTCHECKS.sql'].SnapshotPath
  $catalogSql = $integritySnapshot.Files['docs/CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql'].SnapshotPath
}

try {
  # The fixed host plus verify-full checks both the staging hostname and the
  # server chain against the supplied CA. The SQL preflight asserts TLS is active.
  Invoke-VerifiedPsql -File $preflightSql | ForEach-Object { Write-Host $_ }
  $baselineLedger = @(Get-LedgerVersions)
  Assert-BaselineLedger $baselineLedger
  Write-Host "Preflight passed for staging $expectedRef. Captured $($baselineLedger.Count) ledger version(s) in memory."
  Write-Host 'No ledger snapshot file is written.'

  if (-not $Execute) {
    Write-Host 'Preflight-only mode completed. No migration or ledger writes were attempted.'
    return
  }
  Confirm-ExactPhrase "CONFIRM APPROVED PACKAGE COMMIT $ApprovedCommit"
  Confirm-ExactPhrase "AUTHORIZE CRM RELEASE 1A STAGING EXECUTION $expectedRef"

  $recordedThisRun = @()
  foreach ($m in $migrations) {
    Assert-CrmPackageIntegritySnapshot $integritySnapshot
    Assert-LedgerState $baselineLedger $recordedThisRun "before $($m.Version)"
    $migrationRelative = "supabase/migrations/$($m.File)"
    $migrationPath = $integritySnapshot.Files[$migrationRelative].SnapshotPath
    $migrationBytes = $integritySnapshot.Files[$migrationRelative].Bytes
    $migrationSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($migrationBytes))
    if ($migrationSha -cne $m.Sha256) { Stop-Release "Checksum mismatch for validated snapshot $($m.File)." }
    $migrationText = [Text.Encoding]::UTF8.GetString($migrationBytes)
    if ([regex]::Matches($migrationText,'(?im)^\s*BEGIN\s*;').Count -ne 1 -or
        [regex]::Matches($migrationText,'(?im)^\s*COMMIT\s*;').Count -ne 1) { Stop-Release "Unexpected transaction boundaries in validated snapshot $($m.File)." }
    Confirm-ExactPhrase "APPLY $($m.Version) TO STAGING $expectedRef"
    Assert-CrmPackageIntegritySnapshot $integritySnapshot
    Write-Host "Applying exact file $($m.File)."
    Invoke-VerifiedPsql -File $migrationPath | ForEach-Object { Write-Host $_ }

    # A successful COMMIT is insufficient: the read-only migration-specific
    # assertions must also pass before any history row is recorded.
    Assert-CrmPackageIntegritySnapshot $integritySnapshot
    Invoke-VerifiedPsql -File $postcheckSql -Variables @("migration_version=$($m.Version)") |
      ForEach-Object { Write-Host $_ }
    Assert-LedgerState $baselineLedger $recordedThisRun "after SQL/post-check for $($m.Version), before ledger recording"

    Confirm-ExactPhrase "RECORD $($m.Version) APPLIED IN STAGING LEDGER $expectedRef"
    Assert-CrmPackageIntegritySnapshot $integritySnapshot
    if ((Get-Content -Raw -LiteralPath $linkFile).Trim() -cne $expectedRef) { Stop-Release 'Supabase CLI link changed before ledger recording.' }
  # This is a separate ledger write, gated by a distinct typed confirmation.
  # If it fails, do not retry the SQL; stop and reconcile with the DBA.
  $securePassword = Read-Host 'Enter staging database password for the separately approved ledger recording step' -AsSecureString
  $passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
  $plainPassword = $null
  $passwordOld = $env:PGPASSWORD
  $sslmodeOld = $env:PGSSLMODE
  $sslrootcertOld = $env:PGSSLROOTCERT
  $telemetryOld = $env:SUPABASE_TELEMETRY_DISABLED
  $trackingOld = $env:DO_NOT_TRACK
  $cliLatestFile = Join-Path $root 'supabase\.temp\cli-latest'
  $cliLatestExisted = Test-Path -LiteralPath $cliLatestFile -PathType Leaf
  $cliLatestBytes = if ($cliLatestExisted) { [IO.File]::ReadAllBytes($cliLatestFile) } else { $null }
  try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
    $env:PGPASSWORD = $plainPassword
    # Keep TLS verification enabled even if the CLI reparses/rebuilds --db-url.
    $env:PGSSLMODE = 'verify-full'
    $env:PGSSLROOTCERT = $ca
    $env:SUPABASE_TELEMETRY_DISABLED = '1'
    $env:DO_NOT_TRACK = '1'
    $repairOutput = & $script:supabaseName migration repair $m.Version --status applied --db-url $script:connInfo 2>&1
    $repairCode = $LASTEXITCODE
  } finally {
    if ($null -eq $passwordOld) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue } else { $env:PGPASSWORD = $passwordOld }
    if ($null -eq $sslmodeOld) { Remove-Item Env:PGSSLMODE -ErrorAction SilentlyContinue } else { $env:PGSSLMODE = $sslmodeOld }
    if ($null -eq $sslrootcertOld) { Remove-Item Env:PGSSLROOTCERT -ErrorAction SilentlyContinue } else { $env:PGSSLROOTCERT = $sslrootcertOld }
    if ($null -eq $telemetryOld) { Remove-Item Env:SUPABASE_TELEMETRY_DISABLED -ErrorAction SilentlyContinue } else { $env:SUPABASE_TELEMETRY_DISABLED = $telemetryOld }
    if ($null -eq $trackingOld) { Remove-Item Env:DO_NOT_TRACK -ErrorAction SilentlyContinue } else { $env:DO_NOT_TRACK = $trackingOld }
    if ($passwordPtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr) }
    $plainPassword = $null
    $securePassword.Dispose()
    # Supabase CLI may refresh this generated version marker. Restore the
    # exact pre-run bytes so ledger recording leaves no workspace setting change.
    if ($cliLatestExisted) { [IO.File]::WriteAllBytes($cliLatestFile,$cliLatestBytes) }
    elseif (Test-Path -LiteralPath $cliLatestFile -PathType Leaf) { Remove-Item -LiteralPath $cliLatestFile -Force }
  }
    if ($repairCode -ne 0) { Stop-Release "Ledger recording failed for $($m.Version). Do not rerun SQL; reconcile with the DBA." }
    Write-Host "Ledger recording command completed for $($m.Version)."

    $recordedThisRun += $m.Version
    Assert-LedgerState $baselineLedger $recordedThisRun "after recording $($m.Version)"
    Assert-CrmPackageIntegritySnapshot $integritySnapshot
    Write-Host "Checkpoint passed for $($m.Version); next migration may proceed."
  }

  Assert-CrmPackageIntegritySnapshot $integritySnapshot
  Invoke-VerifiedPsql -File $catalogSql | ForEach-Object { Write-Host $_ }
  Assert-LedgerState $baselineLedger $recordedThisRun 'final verification'
  Write-Host 'All four exact files and per-version ledger checkpoints passed.'
} finally {
  if ($null -ne $integritySnapshot) { Close-CrmPackageIntegritySnapshot $integritySnapshot }
}
