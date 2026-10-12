$ErrorActionPreference = 'Stop'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$refPath = Join-Path (Get-Location) 'supabase/.temp/project-ref'
if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing linked Supabase project reference.' }
$linkedRef = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linkedRef -cne $TargetRef -or $linkedRef -ceq $ProductionRef) { throw "Refusing non-staging target: $linkedRef" }
$sqlPath = Join-Path (Get-Location) 'supabase/staging/auth_backend_services.sql'
if (-not (Test-Path -LiteralPath $sqlPath)) { throw "Missing Auth deployment artifact: $sqlPath" }
& supabase db query --linked --file $sqlPath
if ($LASTEXITCODE -ne 0) { throw "Auth staging deployment failed with exit code $LASTEXITCODE" }
Write-Output "AUTH BACKEND STAGING DEPLOYED: $TargetRef"
