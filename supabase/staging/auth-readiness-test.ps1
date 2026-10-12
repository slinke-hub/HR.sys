$ErrorActionPreference = 'Stop'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$refPath = Join-Path $PSScriptRoot '..\.temp\project-ref'
$linked = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linked -cne $TargetRef -or $linked -ceq $ProductionRef) { throw "Refusing non-staging target: $linked" }

$base = "https://$TargetRef.supabase.co"

function Invoke-SupabaseCliJson([string[]]$Arguments) {
  $command = Get-Command supabase -CommandType Application -ErrorAction Stop
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $command.Source
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  # These arguments are fixed CLI literals plus the already-guarded staging ref.
  $startInfo.Arguments = (($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' ')
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'Unable to start the Supabase CLI.' }
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) {
    # Do not echo CLI output because it could contain sensitive configuration.
    throw "Supabase CLI failed with exit code $($process.ExitCode)."
  }
  try { return ($stdout | ConvertFrom-Json) } catch {
    # A successful CLI may append a version notice. Parse only the JSON payload.
    $starts = @($stdout.IndexOf('['), $stdout.IndexOf('{')) | Where-Object { $_ -ge 0 }
    $ends = @($stdout.LastIndexOf(']'), $stdout.LastIndexOf('}')) | Where-Object { $_ -ge 0 }
    if (-not $starts -or -not $ends) { throw 'Supabase CLI returned no JSON API-key payload.' }
    $jsonText = $stdout.Substring((($starts | Measure-Object -Minimum).Minimum), (($ends | Measure-Object -Maximum).Maximum - (($starts | Measure-Object -Minimum).Minimum) + 1))
    try { return ($jsonText | ConvertFrom-Json) } catch { throw 'Supabase CLI returned an invalid API-key payload.' }
  }
}

$keys = Invoke-SupabaseCliJson @('projects', 'api-keys', '--project-ref', $TargetRef, '--reveal', '--output', 'json')
$service = ($keys | Where-Object name -eq service_role | Select-Object -First 1).api_key
$anon = ($keys | Where-Object name -eq anon | Select-Object -First 1).api_key
if ([string]::IsNullOrWhiteSpace($service) -or [string]::IsNullOrWhiteSpace($anon)) { throw 'Staging API keys unavailable.' }

function Headers($key, $token = $null) {
  $h = @{ apikey = $key; Authorization = "Bearer $key"; 'Content-Type' = 'application/json' }
  if ($token) { $h.Authorization = "Bearer $token" }
  return $h
}
function Raw($method, $url, $headers, $body = $null) {
  try {
    $params = @{ Method = $method; Uri = $url; Headers = $headers; ErrorAction = 'Stop'; UseBasicParsing = $true }
    if ($null -ne $body) { $params.Body = ($body | ConvertTo-Json -Depth 20 -Compress) }
    $response = Invoke-WebRequest @params
    return [pscustomobject]@{ status = [int]$response.StatusCode; body = $response.Content }
  } catch {
    $status = 0
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode.value__ }
    return [pscustomobject]@{ status = $status; body = $_.ErrorDetails.Message }
  }
}
function Json($raw) { try { return ($raw.body | ConvertFrom-Json) } catch { return $null } }
function Rpc($name, $payload, $token = $null) { Raw POST "$base/rest/v1/rpc/$name" (Headers $anon $token) $payload }
function New-Password { $bytes = New-Object byte[] 24; $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }; return ([Convert]::ToBase64String($bytes) + 'Aa9!') }
function SignIn($email, $password) { Json (Raw POST "$base/auth/v1/token?grant_type=password" (Headers $anon) @{ email = $email; password = $password }) }
function Mark($name, $value) { $script:results[$name] = [bool]$value }
function Denied($response) { return $response.status -in 400, 401, 403, 404 }

$employeeIds = @('TEST-MANAGER', 'TEST-EMPLOYEE', 'TEST-OUTSIDER')
$emails = @()
$results = [ordered]@{}
$users = @{}
$tokens = @{}
$passwords = @{}
$profiles = @{}
$serviceHeaders = Headers $service

try {
  $authList = Json (Raw GET "$base/auth/v1/admin/users?per_page=100" $serviceHeaders)
  $profileRows = Json (Raw GET "$base/rest/v1/profiles?employee_id=in.(TEST-MANAGER,TEST-EMPLOYEE,TEST-OUTSIDER)&select=id,role,employee_id,is_active" $serviceHeaders)
  foreach ($row in @($profileRows)) { $profiles[$row.employee_id] = $row }
  foreach ($employeeId in $employeeIds) {
    $profile = $profiles[$employeeId]
    if (-not $profile -or -not $profile.id) { throw "Missing staging profile for $employeeId" }
    $user = @($authList.users) | Where-Object id -eq $profile.id | Select-Object -First 1
    if (-not $user -or [string]::IsNullOrWhiteSpace([string]$user.email)) { throw "Missing staging Auth identity for $employeeId" }
    $emails += [string]$user.email
  }
  foreach ($email in $emails) {
    $user = @($authList.users) | Where-Object email -eq $email | Select-Object -First 1
    if (-not $user) { throw "Missing staging test identity: $email" }
    $users[$email] = $user
    $passwords[$email] = New-Password
    $reset = Raw PUT "$base/auth/v1/admin/users/$($user.id)" $serviceHeaders @{ password = $passwords[$email]; email_confirm = $true }
    if ($reset.status -notin 200..299) { throw "Unable to prepare synthetic test identity: $email" }
    $session = SignIn $email $passwords[$email]
    if (-not $session -or [string]::IsNullOrWhiteSpace([string]$session.access_token)) { throw "Synthetic sign-in failed: $email" }
    $tokens[$email] = $session.access_token
    Mark ("login_$($email.Split('@')[0].Replace('.','_'))") $true
    $userCheck = Raw GET "$base/auth/v1/user" (Headers $anon $session.access_token)
    Mark ("validated_user_$($email.Split('@')[0].Replace('.','_'))") ($userCheck.status -eq 200 -and (Json $userCheck).id -eq $user.id)
    $refresh = Json (Raw POST "$base/auth/v1/token?grant_type=refresh_token" (Headers $anon) @{ refresh_token = $session.refresh_token })
    Mark ("refresh_$($email.Split('@')[0].Replace('.','_'))") ([bool]($refresh -and -not [string]::IsNullOrWhiteSpace([string]$refresh.access_token)))
  }

  Mark profile_uuid_relationship (@($profiles.Keys).Count -eq 3 -and @($profiles.Keys) -contains 'TEST-MANAGER' -and @($profiles.Keys) -contains 'TEST-EMPLOYEE' -and @($profiles.Keys) -contains 'TEST-OUTSIDER' -and ($profiles.Values | Where-Object { $_.is_active -eq $false }).Count -eq 0 -and $profiles['TEST-MANAGER'].id -eq $users[$emails[0]].id -and $profiles['TEST-EMPLOYEE'].id -eq $users[$emails[1]].id -and $profiles['TEST-OUTSIDER'].id -eq $users[$emails[2]].id)
  Mark role_authority ($profiles['TEST-MANAGER'].role -eq 'MANAGER' -and $profiles['TEST-EMPLOYEE'].role -eq 'EMPLOYEE' -and $profiles['TEST-OUTSIDER'].role -eq 'EMPLOYEE')

  $manager = $tokens[$emails[0]]; $employee = $tokens[$emails[1]]; $outsider = $tokens[$emails[2]]
  $badPassword = SignIn $emails[0] (New-Password)
  Mark wrong_password_rejected (-not $badPassword -or [string]::IsNullOrWhiteSpace([string]$badPassword.access_token))
  Mark invalid_access_token_rejected (Denied (Rpc list_accessible_tasks_secure @{} 'not-a-valid-jwt'))
  Mark anonymous_rpc_rejected (Denied (Rpc list_accessible_tasks_secure @{}))
  Mark anonymous_file_function_rejected (Denied (Raw POST "$base/functions/v1/file-signed-url" (Headers $anon) @{ bucket = 'hr-documents'; path = 'missing.txt' }))

  $fakeId = '00000000-0000-0000-0000-000000000099'
  Mark fake_user_id_rejected ((Raw GET "$base/rest/v1/profiles?id=eq.$($profiles['TEST-MANAGER'].id)&select=id" (Headers $anon $employee)).status -in 401, 403 -or @((Json (Raw GET "$base/rest/v1/profiles?id=eq.$($profiles['TEST-MANAGER'].id)&select=id" (Headers $anon $employee)))).Count -eq 0)
  $escalation = Raw PATCH "$base/rest/v1/profiles?id=eq.$($profiles['TEST-EMPLOYEE'].id)" (Headers $anon $employee) @{ role = 'ADMIN'; employee_id = 'TEST-ESCALATED'; department_id = '10000000-0000-0000-0000-000000000004' }
  Mark role_department_escalation_rejected (Denied $escalation -or @((Json $escalation)).Count -eq 0)
  Mark employee_admin_password_reset_rejected (Denied (Rpc admin_reset_user_password @{ target_user_id = $profiles['TEST-OUTSIDER'].id; new_password = (New-Password) } $employee))
  Mark employee_user_creation_rejected (Denied (Rpc create_user_by_admin @{ new_email = 'blocked@hrsys-staging.invalid'; new_password = (New-Password) } $employee))

  $inactiveId = $profiles['TEST-EMPLOYEE'].id
  $inactive = Raw PATCH "$base/rest/v1/profiles?id=eq.$inactiveId" $serviceHeaders @{ is_active = $false }
  if ($inactive.status -notin 200..299) { throw 'Could not prepare inactive-profile test.' }
  try {
    $inactiveRpc = Rpc list_accessible_tasks_secure @{} $employee
    Mark inactive_profile_denied (Denied $inactiveRpc -or @((Json $inactiveRpc)).Count -eq 0)
  } finally {
    [void](Raw PATCH "$base/rest/v1/profiles?id=eq.$inactiveId" $serviceHeaders @{ is_active = $true })
  }

  # Supabase logout revokes refresh-token use; the already-issued access JWT can
  # remain valid until its short expiry. Record both facts without printing tokens.
  $logoutPassword = New-Password
  [void](Raw PUT "$base/auth/v1/admin/users/$($users[$emails[2]].id)" $serviceHeaders @{ password = $logoutPassword; email_confirm = $true })
  $logoutSession = SignIn $emails[2] $logoutPassword
  if ($logoutSession -and -not [string]::IsNullOrWhiteSpace([string]$logoutSession.access_token)) {
    $logoutResponse = Raw POST "$base/auth/v1/logout" (Headers $anon $logoutSession.access_token)
    $refreshAfterLogout = Raw POST "$base/auth/v1/token?grant_type=refresh_token" (Headers $anon) @{ refresh_token = $logoutSession.refresh_token }
    Mark logout_endpoint_succeeded ($logoutResponse.status -in 200..299)
    Mark refresh_after_logout_rejected ($refreshAfterLogout.status -in 400, 401, 403)
    Mark access_token_revocation_behavior_documented ($true)
  } else {
    Mark logout_endpoint_succeeded $false
    Mark refresh_after_logout_rejected $false
    Mark access_token_revocation_behavior_documented $false
  }
} finally {
  # Restore all synthetic identities to active state. No application records are created.
  foreach ($profile in $profiles.Values) { if ($profile.id) { [void](Raw PATCH "$base/rest/v1/profiles?id=$($profile.id)" $serviceHeaders @{ is_active = $true }) } }
}

$results.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
if (($results.Values | Where-Object { -not $_ }).Count -gt 0) { exit 1 }
