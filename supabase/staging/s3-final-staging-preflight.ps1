[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$expectedProjectRef = 'jcfyyxsuspukcmybyhjj'
$productionProjectRef = 'bbbetcdioiaozdjkvwxu'
$s3Version = '20261005110000'
$expectedS3Hash = '0B5C5877A8CB1392E7F9DE36758C3A9380C595161CF1335A00629A39ABCC48D3'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$projectRefPath = Join-Path $repoRoot 'supabase\.temp\project-ref'
$s3MigrationPath = Join-Path $repoRoot 'supabase\migrations\20261005110000_security_hardening_s3.sql'
$catalogPath = Join-Path $PSScriptRoot 's3-final-staging-preflight-readonly.sql'
$migrationListParserPath = Join-Path $PSScriptRoot 's3-migration-list-parser.ps1'

if (-not (Test-Path -LiteralPath $projectRefPath -PathType Leaf)) {
  throw 'STOP: linked project reference file is missing.'
}
$linkedProjectRef = (Get-Content -Raw -LiteralPath $projectRefPath).Trim()
if ($linkedProjectRef -ceq $productionProjectRef) {
  throw 'STOP: production project is linked; no query was issued.'
}
if ($linkedProjectRef -cne $expectedProjectRef) {
  throw 'STOP: linked project is not the approved staging project; no query was issued.'
}

if (-not (Test-Path -LiteralPath $s3MigrationPath -PathType Leaf)) {
  throw 'STOP: S3 migration file is missing.'
}
$actualS3Hash = (Get-FileHash -LiteralPath $s3MigrationPath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($actualS3Hash -cne $expectedS3Hash) {
  throw 'STOP: S3 migration SHA-256 mismatch; no database query was issued.'
}
if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
  throw 'STOP: read-only S3 catalog diagnostic is missing.'
}
if (-not (Test-Path -LiteralPath $migrationListParserPath -PathType Leaf)) {
  throw 'STOP: local migration-list parser is missing.'
}

# First read-only operation: verify local/remote migration-list state.
$migrationListOutput = @(& supabase migration list --linked --project-ref $expectedProjectRef)
$migrationListExitCode = $LASTEXITCODE
if ($migrationListExitCode -ne 0) {
  Write-Output 'S3_STAGING_PREFLIGHT=FAIL'
  Write-Output 'FAILED_PREDICATES=MIGRATION_LIST_QUERY_FAILED'
  throw 'STOP: read-only migration-list command failed.'
}

. $migrationListParserPath
$parsedMigrationList = ConvertFrom-SupabaseMigrationListOutput -Lines $migrationListOutput
$migrationRows = @($parsedMigrationList.Rows)
$remoteOnlyRows = @($parsedMigrationList.RemoteOnlyRows)
$unparsedMigrationRows = @($parsedMigrationList.UnparsedRows)

$listPending = @($migrationRows | Where-Object { -not $_.Remote })
$listDiverged = @($migrationRows | Where-Object { $_.Remote -and $_.Local -cne $_.Remote })
$unexpectedLocalPending = @($listPending | Where-Object { $_.Local -cne $s3Version })
$exactlyS3Pending = ($migrationRows.Count -gt 0) -and
  ($listPending.Count -eq 1) -and
  ($listPending[0].Local -ceq $s3Version) -and
  ($listDiverged.Count -eq 0) -and
  ($remoteOnlyRows.Count -eq 0) -and
  ($unparsedMigrationRows.Count -eq 0) -and
  ($unexpectedLocalPending.Count -eq 0)

# Run the SELECT-only catalog diagnostic even if list state drifted, so the
# operator receives both read-only evidence sets before stopping.
$catalogOutput = @(& supabase db query --linked --project-ref $expectedProjectRef --file $catalogPath)
$catalogExitCode = $LASTEXITCODE
$catalogText = $catalogOutput -join [Environment]::NewLine
if ($catalogExitCode -ne 0) {
  Write-Output 'S3_STAGING_PREFLIGHT=FAIL'
  Write-Output 'FAILED_PREDICATES=READ_ONLY_CATALOG_QUERY_FAILED'
  throw 'STOP: read-only catalog query failed.'
}

$catalogMarker = [regex]::Match($catalogText, '(?s)S3_STAGING_PREFLIGHT.{0,48}?(PASS|FAIL)')
$catalogPassed = $catalogMarker.Success -and $catalogMarker.Groups[1].Value -ceq 'PASS'
$failed = [System.Collections.Generic.List[string]]::new()
if (-not $exactlyS3Pending) { $failed.Add('MIGRATION_HISTORY_NOT_EXACTLY_S3_PENDING') }
if (-not $catalogMarker.Success) { $failed.Add('CATALOG_RESULT_MARKER_MISSING') }
elseif (-not $catalogPassed) { $failed.Add('CATALOG_PREDICATES_FAILED') }

if ($failed.Count -eq 0) {
  Write-Output 'S3_STAGING_PREFLIGHT=PASS'
  Write-Output 'FAILED_PREDICATES=none'
  return
}

Write-Output 'S3_STAGING_PREFLIGHT=FAIL'
Write-Output ('FAILED_PREDICATES=' + ($failed -join ','))
Write-Output ('ONLY_S3_PENDING=' + $exactlyS3Pending.ToString().ToLowerInvariant())
Write-Output ('PENDING_VERSIONS=' + (@($listPending | ForEach-Object { $_.Local }) -join ','))
Write-Output ('DIVERGED_VERSIONS=' + (@($listDiverged | ForEach-Object { $_.Local + ':' + $_.Remote }) -join ','))
Write-Output ('REMOTE_ONLY_VERSIONS=' + ($remoteOnlyRows -join ','))
Write-Output ('UNPARSED_MIGRATION_ROWS=' + ($unparsedMigrationRows.Count))
if ($catalogText) { Write-Output 'READ_ONLY_CATALOG_OUTPUT_BEGIN'; Write-Output $catalogText; Write-Output 'READ_ONLY_CATALOG_OUTPUT_END' }
throw 'STOP: S3 staging preflight failed; do not apply the migration.'
