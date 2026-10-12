$ErrorActionPreference = 'Stop'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$Baseline = 'supabase/migrations/20260830000000_initial_schema.sql'
$BaselineSha256 = '39F540A14D4FEFA4CACFAD8D7A1F39FD3DE0A81690D98F3F3BFB075C876BF194'

function Assert-StagingLink {
  $refPath = Join-Path (Get-Location) 'supabase/.temp/project-ref'
  if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing Supabase linked-project reference file' }
  $linked = (Get-Content -Raw -LiteralPath $refPath).Trim()
  if ($linked -cne $TargetRef) { throw "Refusing deployment: linked project is '$linked', expected '$TargetRef'" }
}
function Invoke-StageCommand([string[]]$CliArgs) {
  Assert-StagingLink
  & supabase @CliArgs
  if ($LASTEXITCODE -ne 0) { throw "Supabase command failed (exit $LASTEXITCODE): supabase $($CliArgs -join ' ')" }
}
function Apply-Sql([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "Missing deployment artifact: $Path" }
  Invoke-StageCommand @('db','query','--linked','--file',$Path)
}
function Baseline-IsPresent {
  Assert-StagingLink
  $probe = (& supabase db query --linked "select (select count(*) from pg_class where relkind='r' and relnamespace='public'::regnamespace) as tables, (select count(*) from pg_proc where pronamespace='public'::regnamespace) as funcs;" | Out-String)
  if ($LASTEXITCODE -ne 0) { throw 'Unable to verify staging baseline object counts' }
  return ($probe -match '"tables"\s*:\s*70' -and $probe -match '"funcs"\s*:\s*172')
}

Assert-StagingLink
$actual = (Get-FileHash -LiteralPath $Baseline -Algorithm SHA256).Hash
if ($actual -cne $BaselineSha256) { throw "Baseline SHA-256 mismatch: $actual" }

# The previous failed staging attempt left exactly two equivalent SECURITY
# DEFINER functions behind. Preserve the approved baseline hash, but make only
# those two declarations idempotent for this recovery run.
if (-not (Baseline-IsPresent)) {
  $baselineSql = Get-Content -Raw -LiteralPath $Baseline
  $baselineSql = $baselineSql -replace '(?m)^CREATE FUNCTION public\.(admin_get_user_email|admin_update_user_credentials|rls_auto_enable)\b', 'CREATE OR REPLACE FUNCTION public.$1'
  $baselineSql = $baselineSql -replace '(?m)^\\[^\r\n]*(\r?\n|$)', ''
  $baselineSql = $baselineSql -replace '(?m)^CREATE SCHEMA public;\s*', ''
  $baselineTemp = Join-Path $env:TEMP 'hrsys-staging-baseline-idempotent.sql'
  Set-Content -LiteralPath $baselineTemp -Value $baselineSql -Encoding utf8
  Apply-Sql $baselineTemp
  Remove-Item -LiteralPath $baselineTemp -Force
}
Apply-Sql 'supabase/staging/staging_reference_seed.sql'
Apply-Sql 'supabase/staging/staging_acl_reconciliation.sql'
Apply-Sql 'supabase/staging/staging_realtime_reconciliation.sql'
Apply-Sql 'supabase/staging/staging_storage_reconciliation.sql'
Apply-Sql 'supabase/staging/file_backend_services.sql'
Apply-Sql 'supabase/staging/staging_attachment_policy_reconciliation.sql'

# Mark all repository migrations as applied only after their required effects have
# been represented by the baseline/reconciliation artifacts. No historical SQL is executed.
$versions = @(Get-ChildItem -LiteralPath 'supabase/migrations' -Filter '*.sql' | Sort-Object Name | ForEach-Object { if ($_.BaseName -match '^([0-9]{14})_') { $Matches[1] } })
Invoke-StageCommand (@('migration','repair','--status','applied') + $versions)

Apply-Sql 'supabase/staging/staging_verify.sql'
Assert-StagingLink
Write-Output "STAGING DEPLOYMENT COMPLETE: $TargetRef"
