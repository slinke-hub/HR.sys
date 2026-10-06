[CmdletBinding()]
param()

# Disposable, end-to-end S3 acceptance. This script creates only uniquely
# prefixed staging Auth/profile fixtures, emits status labels only, then removes
# its exact fixtures in finally. Never use this against production.
$ErrorActionPreference = 'Stop'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$BaseUrl = "https://$TargetRef.supabase.co"
$Origin = 'https://sys.muqam.net'
$script:AnonKey = $null
$script:ServiceKey = $null
$script:RunId = [Guid]::NewGuid().ToString('N').Substring(0, 12)
$script:Fixtures = @()
$script:ProbeEmails = @()
$script:Passwords = @{}
$script:AccessTokens = @{}
$script:CleanupFailed = $false
$script:AcceptancePassed = $false

function Convert-SecureStringToPlainText([Security.SecureString]$Value) {
  $pointer = [IntPtr]::Zero
  try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  } finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
  }
}

function Read-KeyClaims([string]$Key) {
  try {
    $parts = $Key.Split('.')
    if ($parts.Count -ne 3) { return $null }
    $payloadText = $parts[1].Replace('-', '+').Replace('_', '/')
    switch ($payloadText.Length % 4) { 2 { $payloadText += '==' } 3 { $payloadText += '=' } }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloadText)) | ConvertFrom-Json
  } catch { return $null }
}

function New-RandomPassword {
  $bytes = New-Object byte[] 36
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  return ([Convert]::ToBase64String($bytes) + 'Z9!')
}

function New-Headers([string]$Token = $null, [switch]$Anonymous) {
  $authorization = if ($Anonymous) { $script:AnonKey } elseif ($Token) { $Token } else { $script:ServiceKey }
  $apiKey = if ($Anonymous -or $Token) { $script:AnonKey } else { $script:ServiceKey }
  return @{ apikey = $apiKey; Authorization = "Bearer $authorization"; 'Content-Type' = 'application/json' }
}

function Invoke-Api([string]$Method, [string]$Path, $Body = $null, [string]$Token = $null, [switch]$Anonymous) {
  $headers = New-Headers $Token -Anonymous:$Anonymous
  $params = @{ Method = $Method; Uri = ($BaseUrl + $Path); Headers = $headers; ErrorAction = 'Stop'; UseBasicParsing = $true }
  if ($Path -like '/functions/v1/*') { $params.Headers.Origin = $Origin }
  if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 12 -Compress) }
  try {
    $response = Invoke-WebRequest @params
    $parsed = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$response.Content)) { try { $parsed = $response.Content | ConvertFrom-Json } catch { } }
    return [pscustomobject]@{ Status = [int]$response.StatusCode; Data = $parsed }
  } catch {
    $status = 0; $content = ''
    if ($_.Exception.Response) {
      try { $status = [int]$_.Exception.Response.StatusCode } catch { }
      try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $content = $reader.ReadToEnd(); $reader.Dispose()
      } catch { }
    }
    $parsed = $null
    if ($content) { try { $parsed = $content | ConvertFrom-Json } catch { } }
    return [pscustomobject]@{ Status = $status; Data = $parsed }
  }
}

function Assert-Http([string]$Case, $Response, [int[]]$Expected) {
  if ($Response.Status -eq 0) { throw "INFRASTRUCTURE_FAILURE=$Case" }
  if ($Expected -notcontains $Response.Status) { throw "UNEXPECTED_AUTHORIZATION_RESULT=$Case;HTTP=$($Response.Status)" }
  Write-Output "$Case=PASS"
}

function Assert-Denied([string]$Case, $Response) { Assert-Http $Case $Response @(401, 403) }

function Invoke-Rpc([string]$Name, [hashtable]$Payload, [string]$Token = $null, [switch]$Anonymous) {
  return Invoke-Api 'POST' "/rest/v1/rpc/$Name" $Payload $Token -Anonymous:$Anonymous
}

function New-Fixture([string]$Label, [string]$Role, [bool]$Active) {
  $employeeId = "S3A-$($script:RunId)-$Label"
  $email = "s3a-$($script:RunId)-$($Label.ToLowerInvariant())@hrsys-staging.invalid"
  $password = New-RandomPassword
  $created = Invoke-Api 'POST' '/auth/v1/admin/users' @{ email = $email; password = $password; email_confirm = $true; user_metadata = @{ acceptance_fixture = $true; run_id = $script:RunId } }
  if ($created.Status -notin 200..299 -or -not $created.Data.id) { throw "FIXTURE_SETUP_FAILED=AUTH_$Label" }
  $fixture = [pscustomobject]@{ Label = $Label; Id = [string]$created.Data.id; Email = $email; EmployeeId = $employeeId; Role = $Role; Active = $Active }
  $script:Fixtures += $fixture
  $script:Passwords[$Label] = $password
  $profile = Invoke-Api 'POST' '/rest/v1/profiles' @{ id = $fixture.Id; role = $Role; full_name = "Disposable S3 $Label"; employee_id = $employeeId; is_active = $Active }
  if ($profile.Status -notin 200..299) { throw "FIXTURE_SETUP_FAILED=PROFILE_$Label" }
  return $fixture
}

function Sign-InFixture($Fixture, [string]$Password) {
  $response = Invoke-Api 'POST' '/functions/v1/secure-login' @{ email = $Fixture.Email; password = $Password } -Anonymous
  if ($response.Status -eq 0) { throw "INFRASTRUCTURE_FAILURE=LOGIN_$($Fixture.Label)" }
  if ($response.Status -ne 200 -or -not $response.Data.session.access_token) { throw "LOGIN_FIXTURE_FAILED=$($Fixture.Label);HTTP=$($response.Status)" }
  $token = [string]$response.Data.session.access_token
  $user = Invoke-Api 'GET' '/auth/v1/user' $null $token
  if ($user.Status -ne 200 -or [string]$user.Data.id -cne $Fixture.Id) { throw "SESSION_IDENTITY_MISMATCH=$($Fixture.Label)" }
  $script:AccessTokens[$Fixture.Label] = $token
  return $token
}

function Get-Lockout([string]$Email) {
  $encoded = [Uri]::EscapeDataString($Email)
  return Invoke-Api 'GET' "/rest/v1/login_attempts?email=eq.$encoded&select=email,attempts,locked_until" $null
}

function Cleanup-Fixtures {
  foreach ($probeEmail in @($script:ProbeEmails)) {
    try {
      $encodedProbe = [Uri]::EscapeDataString($probeEmail)
      $probeDelete = Invoke-Api 'DELETE' "/rest/v1/login_attempts?email=eq.$encodedProbe" $null
      if ($probeDelete.Status -notin (200..299)) { $script:CleanupFailed = $true }
    } catch { $script:CleanupFailed = $true }
  }
  foreach ($fixture in @($script:Fixtures)) {
    try {
      $email = [Uri]::EscapeDataString($fixture.Email)
      $attemptDelete = Invoke-Api 'DELETE' "/rest/v1/login_attempts?email=eq.$email" $null
      if ($attemptDelete.Status -notin (200..299)) { $script:CleanupFailed = $true }
      $profileDelete = Invoke-Api 'DELETE' "/rest/v1/profiles?id=eq.$($fixture.Id)&employee_id=eq.$([Uri]::EscapeDataString($fixture.EmployeeId))" $null
      if ($profileDelete.Status -notin (200..299)) { $script:CleanupFailed = $true }
      $deleted = Invoke-Api 'DELETE' "/auth/v1/admin/users/$($fixture.Id)" $null
      if ($deleted.Status -notin (@(200..299) + @(404))) { $script:CleanupFailed = $true }
    } catch { $script:CleanupFailed = $true }
  }
}

# Explicit local link guard: no CLI command can redirect this harness to another project.
$linkPath = Join-Path $PSScriptRoot '..\.temp\project-ref'
$linked = (Get-Content -Raw -LiteralPath $linkPath).Trim()
if ($linked -ceq $ProductionRef -or $linked -cne $TargetRef) { throw 'STOP: linked project is not the approved staging project.' }

$script:AnonKey = [string][Environment]::GetEnvironmentVariable('HR_SYS_STAGING_ANON_KEY', 'Process')
$anonClaims = Read-KeyClaims $script:AnonKey
if (-not $anonClaims -or $anonClaims.ref -cne $TargetRef -or $anonClaims.role -cne 'anon') { throw 'STOP: a verified staging anon key is required in HR_SYS_STAGING_ANON_KEY.' }
$secureServiceKey = Read-Host 'Enter the staging service-role key privately; it will not be displayed or saved' -AsSecureString
try { $script:ServiceKey = Convert-SecureStringToPlainText $secureServiceKey } finally { $secureServiceKey.Dispose() }
$serviceClaims = Read-KeyClaims $script:ServiceKey
if (-not $serviceClaims -or $serviceClaims.ref -cne $TargetRef -or $serviceClaims.role -cne 'service_role') { $script:ServiceKey = $null; throw 'STOP: supplied key is not the staging service-role key.' }

try {
  Write-Output "FIXTURE_RUN_ID=$($script:RunId)"
  $ordinary = New-Fixture 'USER' 'EMPLOYEE' $true
  $activeAdmin = New-Fixture 'ACTIVE-ADMIN' 'ADMIN' $true
  $inactiveAdmin = New-Fixture 'INACTIVE-ADMIN' 'ADMIN' $false
  $deleteTarget = New-Fixture 'DELETE-TARGET' 'EMPLOYEE' $true
  Write-Output 'DISPOSABLE_FIXTURES_CREATED=PASS'

  $ordinaryToken = Sign-InFixture $ordinary $script:Passwords.USER
  $adminToken = Sign-InFixture $activeAdmin $script:Passwords['ACTIVE-ADMIN']
  $inactiveToken = Sign-InFixture $inactiveAdmin $script:Passwords['INACTIVE-ADMIN']
  Write-Output 'NORMAL_LOGIN_AND_SESSION=PASS'
  $profileSmoke = Invoke-Api 'GET' "/rest/v1/profiles?id=eq.$($ordinary.Id)&select=id,role,is_active" $null $ordinaryToken
  $taskSmoke = Invoke-Rpc 'list_accessible_tasks_secure' @{} $ordinaryToken
  $projectSmoke = Invoke-Rpc 'list_accessible_projects_secure' @{} $ordinaryToken
  if ($profileSmoke.Status -ne 200 -or @($profileSmoke.Data).Count -ne 1 -or
      $taskSmoke.Status -ne 200 -or $projectSmoke.Status -ne 200) { throw 'APPLICATION_SMOKE=FAIL' }
  Write-Output 'AUTH_PROFILE_TASKS_PROJECTS_SMOKE=PASS'

  $syntheticEmail = "s3a-probe-$($script:RunId)@hrsys-staging.invalid"
  $script:ProbeEmails += $syntheticEmail
  $q = [Uri]::EscapeDataString($syntheticEmail)
  Assert-Denied 'ANON_LOGIN_ATTEMPTS_READ' (Invoke-Api 'GET' "/rest/v1/login_attempts?email=eq.$q&select=email" $null -Anonymous)
  Assert-Denied 'AUTH_LOGIN_ATTEMPTS_READ' (Invoke-Api 'GET' "/rest/v1/login_attempts?email=eq.$q&select=email" $null $ordinaryToken)
  Assert-Denied 'ANON_LOGIN_ATTEMPTS_INSERT' (Invoke-Api 'POST' '/rest/v1/login_attempts' @{ email = $syntheticEmail; attempts = 1 } $null -Anonymous)
  Assert-Denied 'AUTH_LOGIN_ATTEMPTS_INSERT' (Invoke-Api 'POST' '/rest/v1/login_attempts' @{ email = $syntheticEmail; attempts = 1 } $null $ordinaryToken)
  Assert-Denied 'ANON_LOGIN_ATTEMPTS_UPDATE' (Invoke-Api 'PATCH' "/rest/v1/login_attempts?email=eq.$q" @{ attempts = 99 } $null -Anonymous)
  Assert-Denied 'AUTH_LOGIN_ATTEMPTS_UPDATE' (Invoke-Api 'PATCH' "/rest/v1/login_attempts?email=eq.$q" @{ attempts = 99 } $null $ordinaryToken)
  Assert-Denied 'ANON_LOGIN_ATTEMPTS_DELETE' (Invoke-Api 'DELETE' "/rest/v1/login_attempts?email=eq.$q" $null -Anonymous)
  Assert-Denied 'AUTH_LOGIN_ATTEMPTS_DELETE' (Invoke-Api 'DELETE' "/rest/v1/login_attempts?email=eq.$q" $null $ordinaryToken)

  Assert-Denied 'ANON_RECORD_FAILED_LOGIN_RPC' (Invoke-Rpc 'record_failed_login' @{ user_email = $syntheticEmail } $null -Anonymous)
  Assert-Denied 'AUTH_RECORD_FAILED_LOGIN_RPC' (Invoke-Rpc 'record_failed_login' @{ user_email = $syntheticEmail } $ordinaryToken)
  Assert-Denied 'ANON_RESET_LOGIN_LOCKOUT_RPC' (Invoke-Rpc 'reset_login_lockout' @{ user_email = $syntheticEmail } $null -Anonymous)
  Assert-Denied 'ANON_DELETE_USER_RPC' (Invoke-Rpc 'delete_user' @{ target_user_id = $deleteTarget.Id } $null -Anonymous)
  Assert-Denied 'ORDINARY_DELETE_USER_RPC' (Invoke-Rpc 'delete_user' @{ target_user_id = $deleteTarget.Id } $ordinaryToken)
  Assert-Denied 'ORDINARY_RESET_OTHER_USER' (Invoke-Rpc 'reset_login_lockout' @{ user_email = $deleteTarget.Email } $ordinaryToken)
  Assert-Http 'ORDINARY_RESET_SELF' (Invoke-Rpc 'reset_login_lockout' @{ user_email = $ordinary.Email } $ordinaryToken) @(200, 204)

  # Exercise the actual public login route with a wrong password. The Edge
  # Function invokes record_failed_login only after Auth rejects credentials.
  for ($i = 0; $i -lt 3; $i++) {
    $failed = Invoke-Api 'POST' '/functions/v1/secure-login' @{ email = $deleteTarget.Email; password = (New-RandomPassword) } -Anonymous
    if ($failed.Status -eq 0) { throw 'INFRASTRUCTURE_FAILURE=TRUSTED_FAILED_LOGIN_PATH' }
    if ($failed.Status -ne 401) { throw "UNEXPECTED_LOGIN_RESULT=TRUSTED_FAILED_LOGIN_PATH;HTTP=$($failed.Status)" }
  }
  $lockout = Get-Lockout $deleteTarget.Email
  if ($lockout.Status -ne 200 -or @($lockout.Data).Count -ne 1 -or [int]$lockout.Data[0].attempts -lt 3) { throw 'TRUSTED_FAILED_LOGIN_PATH=FAIL' }
  Write-Output 'TRUSTED_FAILED_LOGIN_PATH=PASS'
  $blockedValid = Invoke-Api 'POST' '/functions/v1/secure-login' @{ email = $deleteTarget.Email; password = $script:Passwords['DELETE-TARGET'] } -Anonymous
  if ($blockedValid.Status -ne 401) { throw 'LOGIN_LOCKOUT_ENFORCEMENT=FAIL' }
  Write-Output 'LOGIN_LOCKOUT_ENFORCEMENT=PASS'

  Assert-Http 'ACTIVE_ADMIN_RESET_OTHER' (Invoke-Rpc 'reset_login_lockout' @{ user_email = $deleteTarget.Email } $adminToken) @(200, 204)
  $cleared = Get-Lockout $deleteTarget.Email
  if ($cleared.Status -ne 200 -or @($cleared.Data).Count -ne 1 -or [int]$cleared.Data[0].attempts -ne 0 -or $cleared.Data[0].locked_until) { throw 'ACTIVE_ADMIN_RESET_STATE=FAIL' }
  Write-Output 'ACTIVE_ADMIN_RESET=PASS'
  Assert-Denied 'INACTIVE_ADMIN_RESET' (Invoke-Rpc 'reset_login_lockout' @{ user_email = $deleteTarget.Email } $inactiveToken)
  Assert-Denied 'INACTIVE_ADMIN_DELETE' (Invoke-Rpc 'delete_user' @{ target_user_id = $deleteTarget.Id } $inactiveToken)
  Assert-Http 'ACTIVE_ADMIN_DELETE_DISPOSABLE_TARGET' (Invoke-Rpc 'delete_user' @{ target_user_id = $deleteTarget.Id } $adminToken) @(200, 204)
  $deletedProfile = Invoke-Api 'GET' "/rest/v1/profiles?id=eq.$($deleteTarget.Id)&select=is_active" $null
  if ($deletedProfile.Status -ne 200 -or @($deletedProfile.Data).Count -ne 1 -or $deletedProfile.Data[0].is_active -ne $false) { throw 'ACTIVE_ADMIN_DELETE_EFFECT=FAIL' }
  Write-Output 'ACTIVE_ADMIN_DELETE_DISPOSABLE_TARGET=PASS'

  $confirmNoProbe = Invoke-Api 'GET' "/rest/v1/login_attempts?email=eq.$q&select=email" $null
  if ($confirmNoProbe.Status -ne 200 -or @($confirmNoProbe.Data).Count -ne 0) { throw 'SYNTHETIC_PROBE_CLEANUP=FAIL' }
  $script:AcceptancePassed = $true
} finally {
  Cleanup-Fixtures
  $script:Passwords.Clear(); $script:AccessTokens.Clear()
  $script:AnonKey = $null; $script:ServiceKey = $null
  [GC]::Collect()
  if ($script:CleanupFailed) { throw 'FIXTURE_CLEANUP=FAIL; inspect only this run ID before retrying.' }
}
if (-not $script:AcceptancePassed) { throw 'S3_STAGING_AUTHENTICATED_ACCEPTANCE=FAIL' }
Write-Output 'S3_STAGING_AUTHENTICATED_ACCEPTANCE=PASS'
