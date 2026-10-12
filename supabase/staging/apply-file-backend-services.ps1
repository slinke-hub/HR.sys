$ErrorActionPreference = 'Stop'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$refPath = Join-Path (Get-Location) 'supabase/.temp/project-ref'
if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing linked Supabase project reference.' }
$linkedRef = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linkedRef -cne $TargetRef -or $linkedRef -ceq $ProductionRef) {
  throw "Refusing non-staging target: $linkedRef"
}
$sqlPath = Join-Path (Get-Location) 'supabase/staging/file_backend_services.sql'
if (-not (Test-Path -LiteralPath $sqlPath)) { throw "Missing Files deployment artifact: $sqlPath" }
& supabase db query --linked --file $sqlPath
if ($LASTEXITCODE -ne 0) { throw "Files staging deployment failed with exit code $LASTEXITCODE" }
Write-Output "FILE BACKEND STAGING DEPLOYED: $TargetRef"
