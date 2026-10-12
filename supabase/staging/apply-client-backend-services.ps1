$ErrorActionPreference = 'Stop'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$refPath = Join-Path (Get-Location) 'supabase/.temp/project-ref'
if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing linked Supabase project reference.' }
$linkedRef = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linkedRef -cne $TargetRef) { throw "Refusing non-staging target: $linkedRef" }
$sqlPath = 'supabase/staging/client_backend_services.sql'
if (-not (Test-Path -LiteralPath $sqlPath)) { throw "Missing Client deployment artifact: $sqlPath" }
& supabase db query --linked --file $sqlPath
if ($LASTEXITCODE -ne 0) { throw "Client staging deployment failed with exit code $LASTEXITCODE" }
Write-Output "CLIENT BACKEND STAGING DEPLOYED: $TargetRef"
