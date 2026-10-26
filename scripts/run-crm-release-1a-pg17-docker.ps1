[CmdletBinding()]
param(
  [string]$PostgresClientBin = 'C:\Program Files\PostgreSQL\18\bin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scratchRoot = Join-Path $root 'scratch'
$scratch = Join-Path $scratchRoot ('crm-release-1a-docker-test-' + [Guid]::NewGuid().ToString('N'))
$dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
$docker = if ($dockerCommand -and $dockerCommand.CommandType -eq 'Application') {
  $dockerCommand.Source
} else {
  Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin\docker.exe'
}
if (-not (Test-Path -LiteralPath $docker -PathType Leaf)) { throw 'Docker CLI is unavailable; add docker.exe to PATH or install Docker Desktop for this user.' }
$psql = Join-Path $PostgresClientBin 'psql.exe'
if (-not (Test-Path -LiteralPath $psql -PathType Leaf)) { throw 'PostgreSQL client psql.exe was not found; pass its bin folder with -PostgresClientBin.' }

$envNames = @(
  'POSTGRES_PASSWORD','CRM_TEST_POSTGRES_EXTERNAL','CRM_TEST_POSTGRES_HOST','CRM_TEST_POSTGRES_PORT',
  'CRM_TEST_POSTGRES_CONTAINER_ID','CRM_TEST_POSTGRES_IMAGE_ID','CRM_TEST_POSTGRES_DATABASE',
  'CRM_TEST_POSTGRES_PASSWORD','CRM_TEST_POSTGRES_CA_FILE','CRM_TEST_DOCKER_BIN','CRM_TEST_POSTGRES_BIN','CRM_TEST_SCRATCH_DIR'
)
$saved = @{}
foreach ($name in $envNames) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$containerId = $null
$scratchCreated = $false
$listener = $null

try {
  $branch = (& git -C $root branch --show-current).Trim()
  if ($LASTEXITCODE -ne 0 -or $branch -cne 'codex/production-crm-release-1a') { throw 'STOP: unexpected Git branch.' }
  $head = (& git -C $root rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0) { throw 'STOP: could not verify Git HEAD.' }
  & git -C $root merge-base --is-ancestor '874181273a608aea73d26d20dce379074773e849' $head 2>$null
  if ($LASTEXITCODE -ne 0) { throw 'STOP: current HEAD does not descend from the reviewed release baseline.' }

  $dockerInfo = & $docker info --format '{{.ServerVersion}}|{{.OSType}}|{{.Architecture}}' 2>$null
  if ($LASTEXITCODE -ne 0 -or $dockerInfo -notmatch '^.+\|linux\|.+$') { throw 'STOP: Docker Engine is unavailable or is not using Linux containers.' }
  & $docker pull postgres:17.6 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'STOP: PostgreSQL 17.6 image pull failed.' }
  $imageInfo = & $docker image inspect postgres:17.6 --format '{{.Id}}'
  if ($LASTEXITCODE -ne 0 -or $imageInfo -notmatch '^sha256:[a-f0-9]{64}$') { throw 'STOP: could not verify the exact PostgreSQL image identity.' }

  $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
  $listener.Start()
  $port = $listener.LocalEndpoint.Port
  $listener.Stop()
  $listener = $null

  $secretBytes = [byte[]]::new(36)
  [Security.Cryptography.RandomNumberGenerator]::Fill($secretBytes)
  $password = [Convert]::ToBase64String($secretBytes).TrimEnd('=').Replace('+','A').Replace('/','B')
  [Array]::Clear($secretBytes, 0, $secretBytes.Length)
  $env:POSTGRES_PASSWORD = $password
  New-Item -ItemType Directory -Path $scratch -ErrorAction Stop | Out-Null
  $scratchCreated = $true
  $rsa = [Security.Cryptography.RSA]::Create(2048)
  $certificateRequest = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
    'CN=localhost', $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256,
    [Security.Cryptography.RSASignaturePadding]::Pkcs1)
  $certificateRequest.CertificateExtensions.Add(
    [Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true,$false,0,$true))
  $subjectAlternativeName = [Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
  $subjectAlternativeName.AddIpAddress([Net.IPAddress]::Loopback)
  $certificateRequest.CertificateExtensions.Add($subjectAlternativeName.Build())
  $certificate = $certificateRequest.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1),[DateTimeOffset]::UtcNow.AddDays(1))
  $certificatePath = Join-Path $scratch 'postgres-test.crt'
  $privateKeyPath = Join-Path $scratch 'postgres-test.key'
  [IO.File]::WriteAllText($certificatePath, $certificate.ExportCertificatePem())
  [IO.File]::WriteAllText($privateKeyPath, $rsa.ExportPkcs8PrivateKeyPem())
  $certificate.Dispose()
  $rsa.Dispose()
  if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $privateKeyPath -PathType Leaf) -or
      (Get-Item -LiteralPath $certificatePath).Length -eq 0 -or
      (Get-Item -LiteralPath $privateKeyPath).Length -eq 0) {
    throw 'STOP: synthetic TLS certificate generation did not produce both files.'
  }
  $containerName = 'crm-release-1a-' + [Guid]::NewGuid().ToString('N')
  $containerCert = '/tmp/crm-release-1a-' + [Guid]::NewGuid().ToString('N') + '.crt'
  $containerKey = '/tmp/crm-release-1a-' + [Guid]::NewGuid().ToString('N') + '.key'
  $tlsStartup = @"
set -euo pipefail
while [ ! -s "$containerCert" ] || [ ! -s "$containerKey" ]; do sleep 0.1; done
chown postgres:postgres "$containerCert" "$containerKey"
chmod 644 "$containerCert"
chmod 600 "$containerKey"
exec /usr/local/bin/docker-entrypoint.sh postgres -c ssl=on -c ssl_cert_file="$containerCert" -c ssl_key_file="$containerKey"
"@
  $runOutput = & $docker run --detach --name $containerName --publish "127.0.0.1:${port}:5432" `
    --tmpfs '/var/lib/postgresql/data:rw,nosuid,nodev,size=1g' --env POSTGRES_PASSWORD `
    --env 'POSTGRES_DB=crm_release_1a_test' --entrypoint bash postgres:17.6 -c $tlsStartup
  if ($LASTEXITCODE -ne 0 -or $runOutput -notmatch '^[a-f0-9]{64}$') { throw 'STOP: failed to start the uniquely named disposable test container.' }
  $containerId = $runOutput.Trim()

  $copyOutput = & $docker cp $certificatePath "${containerId}:$containerCert" 2>&1
  if ($LASTEXITCODE -ne 0) { throw "STOP: copying the synthetic TLS certificate failed: $copyOutput" }
  $copyOutput = & $docker cp $privateKeyPath "${containerId}:$containerKey" 2>&1
  if ($LASTEXITCODE -ne 0) { throw "STOP: copying the synthetic TLS key failed: $copyOutput" }
  & $docker exec $containerId test -s $containerCert
  if ($LASTEXITCODE -ne 0) {
    $containerLog = & $docker logs $containerId 2>&1
    throw "STOP: copied synthetic TLS certificate is missing or empty in the container. container: $($containerLog -join ' | ')"
  }
  & $docker exec $containerId test -s $containerKey
  if ($LASTEXITCODE -ne 0) {
    $containerLog = & $docker logs $containerId 2>&1
    throw "STOP: copied synthetic TLS key is missing or empty in the container. container: $($containerLog -join ' | ')"
  }

  $ready = $false
  for ($attempt = 0; $attempt -lt 60; $attempt++) {
    & $docker exec $containerId pg_isready -U postgres -d crm_release_1a_test *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 1
  }
  if (-not $ready) { throw 'STOP: disposable PostgreSQL server did not become ready.' }

  $pgData = (& $docker exec $containerId printenv PGDATA).Trim()
  if ($LASTEXITCODE -ne 0 -or $pgData -cne '/var/lib/postgresql/data') {
    throw "STOP: PostgreSQL 17.6 PGDATA was unexpected: $pgData"
  }
  $env:CRM_TEST_POSTGRES_EXTERNAL = '1'
  $env:CRM_TEST_POSTGRES_HOST = '127.0.0.1'
  $env:CRM_TEST_POSTGRES_PORT = [string]$port
  $env:CRM_TEST_POSTGRES_CONTAINER_ID = $containerId
  $env:CRM_TEST_POSTGRES_IMAGE_ID = $imageInfo.Trim()
  $env:CRM_TEST_POSTGRES_DATABASE = 'crm_release_1a_test'
  $env:CRM_TEST_POSTGRES_PASSWORD = $password
  $env:CRM_TEST_POSTGRES_CA_FILE = $certificatePath
  $env:CRM_TEST_DOCKER_BIN = $docker
  $env:CRM_TEST_POSTGRES_BIN = $PostgresClientBin
  $env:CRM_TEST_SCRATCH_DIR = $scratch
  Push-Location $root
  try {
    & node tests/crm-release-1a-postgres.test.cjs
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL 17.6 runtime regression suite failed.' }
    & npm run test:crm-release-1a
    if ($LASTEXITCODE -ne 0) { throw 'CRM static regression suite failed.' }
    & npm run test:security
    if ($LASTEXITCODE -ne 0) { throw 'Security regression suite failed.' }
    & npm run test:backend-readiness
    if ($LASTEXITCODE -ne 0) { throw 'Backend readiness regression suite failed.' }
    & pwsh -NoProfile -File tests/crm-release-1a-staging-runner.mock.test.ps1
    if ($LASTEXITCODE -ne 0) { throw 'Staging runner mock suite failed.' }
  } finally { Pop-Location }

  'PASS: PostgreSQL 17.6 runtime, exact preflight/postchecks, CRM, security, backend, and runner mock suites.'
} finally {
  if ($listener) { $listener.Stop() }
  if ($containerId) {
    & $docker rm --force $containerId *> $null
  }
  if ($scratchCreated) {
    $resolvedScratch = [IO.Path]::GetFullPath($scratch)
    $resolvedRoot = [IO.Path]::GetFullPath($scratchRoot) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedScratch.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
      throw 'Refusing to remove a test artifact outside the workspace scratch directory.'
    }
    Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
  }
  foreach ($name in $envNames) {
    if ($null -eq $saved[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    else { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
  }
  $password = $null
}
