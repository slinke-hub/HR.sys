$ErrorActionPreference = 'Stop'

$productionRef = 'bbbetcdioiaozdjkvwxu'
$stagingRef = 'jcfyyxsuspukcmybyhjj'
$migrationName = '20261001090000_fix_project_profile_directory_order.sql'
$root = (Get-Location).Path
$linkedRefPath = Join-Path $root 'supabase\.temp\project-ref'
$migrationPath = Join-Path $root ('supabase\migrations\' + $migrationName)

if (-not (Test-Path -LiteralPath $linkedRefPath -PathType Leaf)) {
    throw 'ABORTED: missing linked Supabase project reference.'
}

$linkedRef = (Get-Content -Raw -LiteralPath $linkedRefPath).Trim()
if ($linkedRef -ne $stagingRef) {
    throw "ABORTED: repository must remain linked to staging $stagingRef; linked project is '$linkedRef'."
}
if ($productionRef -eq $stagingRef) {
    throw 'ABORTED: production and staging references must differ.'
}
if (-not (Test-Path -LiteralPath $migrationPath -PathType Leaf)) {
    throw "ABORTED: migration not found: $migrationName"
}

Write-Host "Target production project: $productionRef"
Write-Host "Migration: $migrationName"
$confirmation = Read-Host 'Type APPLY PROJECT PROFILE HOTFIX to continue'
if ($confirmation -cne 'APPLY PROJECT PROFILE HOTFIX') {
    throw 'Hotfix not applied: explicit confirmation was not provided.'
}

$env:SUPABASE_TELEMETRY_DISABLED = '1'
supabase db query --linked --project-ref $productionRef --file $migrationPath
if ($LASTEXITCODE -ne 0) {
    throw "Project Profile hotfix failed with exit code $LASTEXITCODE."
}

Write-Host "Project Profile hotfix applied to $productionRef."
