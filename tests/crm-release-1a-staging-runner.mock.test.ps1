$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$runner = Join-Path $PSScriptRoot '..\scripts\crm-release-1a-staging.ps1'
$caMarker = Join-Path ([IO.Path]::GetTempPath()) ("crm-runner-test-ca-" + [Guid]::NewGuid().ToString('N') + '.pem')
$rsa = [System.Security.Cryptography.RSA]::Create(2048)
$request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
  'CN=CRM Runner Synthetic CA', $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
  [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
$request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true,$false,0,$true))
$syntheticCert = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1),[DateTimeOffset]::UtcNow.AddDays(1))
[IO.File]::WriteAllText($caMarker,$syntheticCert.ExportCertificatePem())
$syntheticCert.Dispose()
$rsa.Dispose()
$global:mockLedger = @(
  "20260830000000`tinitial_schema",
  "20261001100000`trevoke_project_profile_directory_public_execute",
  "20261005100000`trevoke_direct_crm_client_dto_execute",
  "20261005110000`tsecurity_hardening_s3",
  "20261020120000`tother_existing_staging_migration"
)
$global:baselineLedger = @($global:mockLedger)
$global:psqlCalls = [System.Collections.Generic.List[object]]::new()
$global:repairCalls = [System.Collections.Generic.List[object]]::new()
$global:postcheckCount = 0
$global:failPostcheckAt = 0
$global:migrationAttemptCount = 0
$global:failMigrationAt = 0
$global:mockDbUrl = $null
$global:savedDbEnv = @{}
foreach ($envName in @('PGPASSWORD','PGPASSFILE','PGSERVICE','PGSERVICEFILE','PGSSLMODE','PGSSLROOTCERT')) {
  $global:savedDbEnv[$envName] = [Environment]::GetEnvironmentVariable($envName)
  Remove-Item "Env:$envName" -ErrorAction SilentlyContinue
}

function Reset-Mocks {
  $global:mockLedger = @($global:baselineLedger)
  $global:psqlCalls.Clear()
  $global:repairCalls.Clear()
  $global:postcheckCount = 0
  $global:failPostcheckAt = 0
  $global:migrationAttemptCount = 0
  $global:failMigrationAt = 0
  $global:mockDbUrl = $null
}

function psql {
  param([Parameter(ValueFromRemainingArguments = $true)][object[]]$PsqlArgs)
  $global:psqlCalls.Add(@($PsqlArgs)) | Out-Null
  $argsText = $PsqlArgs -join ' '
  $fileIndex = [Array]::IndexOf($PsqlArgs, '-f')
  $file = if ($fileIndex -ge 0) { [string]$PsqlArgs[$fileIndex + 1] } else { '' }
  if ($argsText -notmatch 'sslmode=verify-full' -or $argsText -notmatch 'ON_ERROR_STOP=1' -or
      $argsText -notmatch '-X' -or $argsText -notmatch 'db\.jcfyyxsuspukcmybyhjj\.supabase\.co') {
    throw 'psql mock received a connection or failure-mode argument mismatch.'
  }
  if ($argsText -match 'SELECT version::text') {
    $global:mockLedger | ForEach-Object { $_ }
  } elseif ($file -match 'supabase\\migrations\\202610.*\.sql$') {
    $global:migrationAttemptCount++
    if ($global:failMigrationAt -eq $global:migrationAttemptCount) {
      $global:LASTEXITCODE = 2
      'synthetic migration SQL failure'
    } else { 'synthetic exact migration SQL completed' }
  } elseif ($file -match 'STAGING_POSTCHECKS\.sql') {
    $global:postcheckCount++
    if ($global:failPostcheckAt -eq $global:postcheckCount) {
      $global:LASTEXITCODE = 2
      'synthetic post-check failure'
    } else { 'synthetic post-check passed' }
  } else { 'synthetic read-only/exact-file SQL completed' }
  $failedPostcheck = $file -match 'STAGING_POSTCHECKS\.sql' -and $global:failPostcheckAt -eq $global:postcheckCount
  $failedMigration = $file -match 'supabase\\migrations\\202610.*\.sql$' -and $global:failMigrationAt -eq $global:migrationAttemptCount
  if (-not $failedPostcheck -and -not $failedMigration) {
    $global:LASTEXITCODE = 0
  }
}

function supabase {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArgs)
  if ($CliArgs.Count -lt 6 -or $CliArgs[0] -cne 'migration' -or $CliArgs[1] -cne 'repair') {
    throw 'Unexpected Supabase CLI operation.'
  }
  if ($CliArgs -contains '--linked' -or $CliArgs -notcontains '--db-url') {
    throw 'Ledger repair did not use the explicit database URL.'
  }
  $version = $CliArgs[2]
  $url = $CliArgs[[Array]::IndexOf($CliArgs, '--db-url') + 1]
  if ($url -notmatch '^postgresql://postgres@db\.jcfyyxsuspukcmybyhjj\.supabase\.co:5432/postgres\?sslmode=verify-full&sslrootcert=') {
    throw 'Ledger repair URL did not pin staging and TLS hostname verification.'
  }
  if ($env:PGSSLMODE -cne 'verify-full' -or [Uri]::UnescapeDataString(($url -split 'sslrootcert=',2)[1]) -cne $caMarker.Replace('\','/')) {
    throw 'Supabase CLI subprocess did not receive explicit verify-full and trusted CA environment settings.'
  }
  if ($url -match 'synthetic|password=|postgresql://[^/@:]+:[^@]+@') { throw 'Password material appeared in CLI arguments.' }
  $global:mockDbUrl = $url
  $global:repairCalls.Add($version) | Out-Null
  $name = switch ($version) {
    '20261022100000' { 'crm_release_1a' }
    '20261024100000' { 'crm_mq20_contact_task_visibility' }
    '20261026100000' { 'mq20_task_service_authorization_hardening' }
    '20261027100000' { 'task_dependency_visibility_hardening' }
    default { throw "Unexpected migration repair version $version" }
  }
  $global:mockLedger += "$version`t$name"
  $global:LASTEXITCODE = 0
  'synthetic exact-version repair completed'
}

# Model a clean reviewed commit for runner integration tests while keeping all
# database and CLI calls mocked. The integrity verifier itself is tested against
# real temporary Git repositories in crm-release-1a-integrity.test.ps1.
function git {
  param([Parameter(ValueFromRemainingArguments = $true)][object[]]$GitArgs)
  $commandIndex = [Array]::IndexOf($GitArgs,'--show-current')
  if ($commandIndex -ge 0) { $global:LASTEXITCODE = 0; return 'codex/production-crm-release-1a' }
  $revIndex = [Array]::IndexOf($GitArgs,'rev-parse')
  if ($revIndex -ge 0) {
    $revision = [string]$GitArgs[$revIndex + 1]
    if ($revision -eq 'HEAD') { $global:LASTEXITCODE = 0; return ('a' * 40) }
    $relative = $revision -replace '^[a-f0-9]{40}:',''
    $full = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
    $bytes = [IO.File]::ReadAllBytes($full)
    $header = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
    $payload = [byte[]]::new($header.Length + $bytes.Length)
    [Buffer]::BlockCopy($header,0,$payload,0,$header.Length)
    [Buffer]::BlockCopy($bytes,0,$payload,$header.Length,$bytes.Length)
    $global:LASTEXITCODE = 0
    return [Convert]::ToHexString([Security.Cryptography.SHA1]::HashData($payload)).ToLowerInvariant()
  }
  if ($GitArgs -contains 'diff' -or $GitArgs -contains 'cat-file' -or $GitArgs -contains 'merge-base') {
    $global:LASTEXITCODE = 0
    return
  }
  if ($GitArgs -contains 'ls-files' -or $GitArgs -contains 'status') { $global:LASTEXITCODE = 0; return }
  throw "Unexpected Git operation in runner mock: $($GitArgs -join ' ')"
}

function Read-Host {
  param([string]$Prompt, [switch]$AsSecureString)
  if ($AsSecureString) { return ConvertTo-SecureString 'synthetic-test-only' -AsPlainText -Force }
  if ($Prompt -match 'Type exactly: (.+)$') { return $Matches[1] }
  throw 'Unexpected prompt in mock execution.'
}

function Assert-Test([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

try {
  $dockerRunnerPath = Join-Path $PSScriptRoot '..\scripts\run-crm-release-1a-pg17-docker.ps1'
  $dockerRunnerSource = Get-Content -Raw -LiteralPath $dockerRunnerPath
  $postgresHarnessSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'crm-release-1a-postgres.test.cjs')
  $waitForCertsIndex = $dockerRunnerSource.IndexOf('while [ ! -s "$containerCert" ] || [ ! -s "$containerKey" ]')
  $chownCertIndex = $dockerRunnerSource.IndexOf('chown postgres:postgres "$containerCert" "$containerKey"')
  $startPostgresIndex = $dockerRunnerSource.IndexOf('exec /usr/local/bin/docker-entrypoint.sh postgres -c ssl=on')
  $runContainerIndex = $dockerRunnerSource.IndexOf('$docker run --detach')
  $copyCertIndex = $dockerRunnerSource.IndexOf('$docker cp $certificatePath')
  $verifyCertIndex = $dockerRunnerSource.IndexOf('test -s $containerCert')
  $missingCertIndex = $dockerRunnerSource.IndexOf('copied synthetic TLS certificate is missing or empty')
  $readyWaitIndex = $dockerRunnerSource.IndexOf('$ready = $false')
  Assert-Test ($waitForCertsIndex -ge 0 -and $waitForCertsIndex -lt $chownCertIndex -and
    $chownCertIndex -lt $startPostgresIndex) `
    'The container startup wrapper must wait for both TLS files before ownership changes and PostgreSQL startup.'
  Assert-Test ($runContainerIndex -lt $copyCertIndex -and $copyCertIndex -lt $verifyCertIndex -and
    $verifyCertIndex -lt $missingCertIndex -and $missingCertIndex -lt $readyWaitIndex) `
    'The host runner must copy and verify TLS files before waiting for server startup.'
  Assert-Test (
    -not $dockerRunnerSource.Contains('pg_ctl')) `
    'The disposable container must wait for certificate files and start PostgreSQL with TLS enabled, without restarting PID 1.'
  Assert-Test ($dockerRunnerSource.Contains("printenv PGDATA") -and $dockerRunnerSource.Contains("-cne '/var/lib/postgresql/data'")) `
    'TLS files must target the verified PostgreSQL 17 data directory.'
  Assert-Test ($dockerRunnerSource.Contains('docker rm --force $containerId') -and
    $dockerRunnerSource.Contains('Remove-Item -LiteralPath $resolvedScratch -Recurse -Force')) `
    'TLS initialization failures must clean only the disposable container and its own scratch folder.'
  Assert-Test ($postgresHarnessSource.Contains("env.PGSSLMODE = 'verify-full'") -and
    $postgresHarnessSource.Contains('env.PGSSLROOTCERT = externalCaFile')) `
    'Synthetic PostgreSQL test connections must retain certificate and hostname verification.'

  Reset-Mocks
  & $runner -ProjectRef 'jcfyyxsuspukcmybyhjj' -CaFile $caMarker
  Assert-Test ($global:repairCalls.Count -eq 0) 'Preflight-only mode invoked migration repair.'
  Assert-Test (@($global:psqlCalls | Where-Object { $_ -contains '-f' -and $_[([Array]::IndexOf($_,'-f') + 1)] -match '^.*\\supabase\\migrations\\' }).Count -eq 0) 'Preflight-only mode applied a migration.'

  Reset-Mocks
  $caught = $false
  try { & $runner -ProjectRef 'jcfyyxsuspukcmybyhjj' -CaFile $caMarker -Execute }
  catch { $caught = $true }
  Assert-Test $caught 'Execution proceeded without explicit administrator approval and package commit anchor.'
  Assert-Test ($global:psqlCalls.Count -eq 0 -and $global:migrationAttemptCount -eq 0) 'Runner performed database work without explicit approval.'

  Reset-Mocks
  & $runner -ProjectRef 'jcfyyxsuspukcmybyhjj' -CaFile $caMarker -Execute -ApprovalReference 'TEST-APPROVAL-MOCK-ONLY' -ApprovedCommit ('a' * 40)
  $migrationCalls = @($global:psqlCalls | Where-Object {
    $i = [Array]::IndexOf($_, '-f'); $i -ge 0 -and [string]$_[$i + 1] -match 'supabase\\migrations\\202610.*\.sql$'
  })
  Assert-Test ($migrationCalls.Count -eq 4) 'Success path did not execute exactly four migration files.'
  Assert-Test (($global:repairCalls -join ',') -ceq '20261022100000,20261024100000,20261026100000,20261027100000') 'Ledger repair order did not match migration order.'
  Assert-Test ($global:postcheckCount -eq 4) 'Every migration must pass its post-check before ledger recording.'
  $expectedLedger = @($global:baselineLedger + @(
    "20261022100000`tcrm_release_1a",
    "20261024100000`tcrm_mq20_contact_task_visibility",
    "20261026100000`tmq20_task_service_authorization_hardening",
    "20261027100000`ttask_dependency_visibility_hardening"
  )) | Sort-Object
  Assert-Test ((@($global:mockLedger | Sort-Object) -join "`n") -ceq ($expectedLedger -join "`n")) 'Ledger mock did not add exactly the four expected versions while preserving baseline entries.'
  Assert-Test ($global:mockDbUrl -match 'sslmode=verify-full') 'Ledger repair did not retain verify-full.'
  Assert-Test ([string]::IsNullOrEmpty($env:PGSSLMODE) -and [string]::IsNullOrEmpty($env:PGSSLROOTCERT)) 'Runner did not restore TLS environment variables after CLI execution.'

  Reset-Mocks
  $global:failPostcheckAt = 2
  $caught = $false
  try { & $runner -ProjectRef 'jcfyyxsuspukcmybyhjj' -CaFile $caMarker -Execute -ApprovalReference 'TEST-APPROVAL-MOCK-ONLY' -ApprovedCommit ('a' * 40) }
  catch { $caught = $true }
  Assert-Test $caught 'Runner did not stop on a failed post-check.'
  Assert-Test (($global:repairCalls -join ',') -ceq '20261022100000') 'Runner recorded a migration whose post-check failed or continued past it.'
  $attemptedMigrations = @($global:psqlCalls | Where-Object {
    $i = [Array]::IndexOf($_, '-f'); $i -ge 0 -and [string]$_[$i + 1] -match 'supabase\\migrations\\202610.*\.sql$'
  })
  Assert-Test ($attemptedMigrations.Count -eq 2) 'Runner continued to later migrations after a failed post-check.'

  Reset-Mocks
  $caught = $false
  try { & $runner -ProjectRef 'bbbetcdioiaozdjkvwxu' -CaFile $caMarker }
  catch { $caught = $true }
  Assert-Test $caught 'Runner accepted the Production project reference.'
  Assert-Test ($global:psqlCalls.Count -eq 0) 'Runner connected before rejecting a non-staging project.'

  Reset-Mocks
  $global:failMigrationAt = 1
  $caught = $false
  try { & $runner -ProjectRef 'jcfyyxsuspukcmybyhjj' -CaFile $caMarker -Execute -ApprovalReference 'TEST-APPROVAL-MOCK-ONLY' -ApprovedCommit ('a' * 40) }
  catch { $caught = $true }
  Assert-Test $caught 'Runner did not stop on a failed migration SQL command.'
  Assert-Test ($global:migrationAttemptCount -eq 1 -and $global:repairCalls.Count -eq 0) 'Runner recorded a failed migration or continued after its SQL error.'

  Reset-Mocks
  $global:mockLedger += "20261022100000`trcrm_release_1a"
  $caught = $false
  try { & $runner -ProjectRef 'jcfyyxsuspukcmybyhjj' -CaFile $caMarker }
  catch { $caught = $true }
  Assert-Test $caught 'Runner accepted a Release 1A version already present in the migration ledger.'
  Assert-Test ($global:migrationAttemptCount -eq 0 -and $global:repairCalls.Count -eq 0) 'Runner attempted work after detecting an unexpected Release 1A ledger state.'

  $global:LASTEXITCODE = 0
  'PASS: staging runner mock tests (read-only mode, exact four-file order, TLS-pinned repair, post-check stop, Production-ref rejection).'
} finally {
  foreach ($envName in $global:savedDbEnv.Keys) {
    if ($null -eq $global:savedDbEnv[$envName]) { Remove-Item "Env:$envName" -ErrorAction SilentlyContinue }
    else { [Environment]::SetEnvironmentVariable($envName,$global:savedDbEnv[$envName]) }
  }
  Remove-Item -LiteralPath $caMarker -Force -ErrorAction SilentlyContinue
}
