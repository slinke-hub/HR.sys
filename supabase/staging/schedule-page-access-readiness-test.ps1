$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'

# This script is intentionally staging-only. It is prepared for a separately
# approved integration run and must never be used against Production.
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$refPath = Join-Path $PSScriptRoot '..\.temp\project-ref'
if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing linked Supabase project reference.' }
$linked = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linked -cne $TargetRef -or $linked -ceq $ProductionRef) { throw "Refusing non-staging target: $linked" }
$base = "https://$TargetRef.supabase.co"

function Invoke-SupabaseCliJson([string[]]$Arguments) {
  $command = Get-Command supabase -CommandType Application -ErrorAction Stop
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = if ($command.Path) { $command.Path } else { $command.Source }
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = (($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' ')
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'Unable to start Supabase CLI.' }
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $null = $stderrTask.GetAwaiter().GetResult()
  if ($process.ExitCode -ne 0) { throw "Supabase CLI failed with exit code $($process.ExitCode)." }
  try { return ($stdout | ConvertFrom-Json) } catch {
    $starts = @($stdout.IndexOf('['), $stdout.IndexOf('{')) | Where-Object { $_ -ge 0 }
    $ends = @($stdout.LastIndexOf(']'), $stdout.LastIndexOf('}')) | Where-Object { $_ -ge 0 }
    if ($starts.Count -eq 0 -or $ends.Count -eq 0) { throw 'Supabase CLI returned no JSON payload.' }
    $start = ($starts | Measure-Object -Minimum).Minimum
    $end = ($ends | Measure-Object -Maximum).Maximum
    return ($stdout.Substring($start, $end - $start + 1) | ConvertFrom-Json)
  }
}

function Headers($key, $token = $null, [bool]$returnRepresentation = $false) {
  $headers = @{ apikey = $key; Authorization = "Bearer $key"; 'Content-Type' = 'application/json' }
  if ($token) { $headers.Authorization = "Bearer $token" }
  if ($returnRepresentation) { $headers.Prefer = 'return=representation' }
  return $headers
}
function Raw($method, $url, $headers, $body = $null) {
  try {
    $params = @{ Method=$method; Uri=$url; Headers=$headers; ErrorAction='Stop'; UseBasicParsing=$true }
    if ($null -ne $body) { $params.Body = ($body | ConvertTo-Json -Depth 20 -Compress) }
    $response = Invoke-WebRequest @params
    return [pscustomobject]@{ status=[int]$response.StatusCode; body=$response.Content }
  } catch {
    $status = 0
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode.value__ }
    return [pscustomobject]@{ status=$status; body=$_.ErrorDetails.Message }
  }
}
function Json($raw) { try { return ($raw.body | ConvertFrom-Json) } catch { return $null } }
function Rpc($name, $payload, $token = $null) { Raw POST "$base/rest/v1/rpc/$name" (Headers $anon $token) $payload }
function ServiceRpc($name, $payload) { Raw POST "$base/rest/v1/rpc/$name" (Headers $service) $payload }
function Denied($response) { return $response.status -in 400,401,403,404 }
function Mark($name, $value) { $script:results[$name] = [bool]$value }
function New-Password {
  $bytes = New-Object byte[] 24
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  return ([Convert]::ToBase64String($bytes) + 'Aa9!')
}
function SignIn($email, $password) { Json (Raw POST "$base/auth/v1/token?grant_type=password" (Headers $anon) @{email=$email;password=$password}) }
function Without-Schedule($pages) { return @($pages | Where-Object { $_ -ne 'schedule' }) }
function With-Schedule($pages) { return @((Without-Schedule $pages) + 'schedule' | Select-Object -Unique) }

$keys = Invoke-SupabaseCliJson @('projects','api-keys','--project-ref',$TargetRef,'--reveal','--output','json')
$service = ($keys | Where-Object name -eq service_role | Select-Object -First 1).api_key
$anon = ($keys | Where-Object name -eq anon | Select-Object -First 1).api_key
if ([string]::IsNullOrWhiteSpace($service) -or [string]::IsNullOrWhiteSpace($anon)) { throw 'Staging API keys unavailable.' }
$serviceHeaders = Headers $service
$serviceWriteHeaders = Headers $service $null $true
$serviceUpsertHeaders = Headers $service
$serviceUpsertHeaders.Prefer = 'resolution=merge-duplicates,return=representation'
$results = [ordered]@{}
$createdReminderIds = @()
$permissionSnapshots = @{}
$cleanupFailed = $false
$marker = "SCHEDULE AUTH TEST $([guid]::NewGuid())"

try {
  $profiles = @(Json (Raw GET "$base/rest/v1/profiles?employee_id=in.(TEST-EMPLOYEE,TEST-OUTSIDER)&select=id,employee_id,role,department_id,is_active" $serviceHeaders))
  $subject = $profiles | Where-Object employee_id -eq 'TEST-EMPLOYEE' | Select-Object -First 1
  $outsider = $profiles | Where-Object employee_id -eq 'TEST-OUTSIDER' | Select-Object -First 1
  $adminProfile = @(Json (Raw GET "$base/rest/v1/profiles?role=eq.ADMIN&is_active=is.true&select=id,employee_id,role,department_id,is_active&limit=1" $serviceHeaders))[0]
  if (-not $subject -or -not $outsider -or -not $adminProfile) { throw 'Required staging employee, outsider, or administrator profile is missing.' }
  if (-not $subject.department_id) { throw 'TEST-EMPLOYEE requires a department for department-grant validation.' }

  $authList = Json (Raw GET "$base/auth/v1/admin/users?per_page=1000" $serviceHeaders)
  $tokens = @{}
  foreach ($profile in @($subject, $outsider, $adminProfile)) {
    $user = @($authList.users) | Where-Object id -eq $profile.id | Select-Object -First 1
    if (-not $user) { throw "Missing Auth identity for $($profile.id)" }
    $password = New-Password
    $reset = Raw PUT "$base/auth/v1/admin/users/$($profile.id)" $serviceHeaders @{password=$password;email_confirm=$true}
    if ($reset.status -notin 200..299) { throw "Unable to prepare Auth identity $($profile.id)" }
    $session = SignIn ([string]$user.email) $password
    if (-not $session.access_token) { throw "Unable to authenticate $($profile.id)" }
    $tokens[[string]$profile.id] = $session.access_token
  }
  Mark identities_ready ($tokens.Count -eq 3)

  $subjectId = [string]$subject.id
  $outsiderId = [string]$outsider.id
  $adminId = [string]$adminProfile.id
  $roleKey = ([string]$subject.role).Trim().ToUpperInvariant()
  $departmentKey = "DEPT_$($subject.department_id)"
  $userPermissionUrl = "$base/rest/v1/user_permissions?user_id=eq.$subjectId"
  $rolePermissionUrl = "$base/rest/v1/role_permissions?role=eq.$([uri]::EscapeDataString($roleKey))"
  $departmentPermissionUrl = "$base/rest/v1/role_permissions?role=eq.$([uri]::EscapeDataString($departmentKey))"
  $permissionSnapshots.user = @(Json (Raw GET "$userPermissionUrl&select=*" $serviceHeaders))
  $permissionSnapshots.role = @(Json (Raw GET "$rolePermissionUrl&select=*" $serviceHeaders))
  $permissionSnapshots.department = @(Json (Raw GET "$departmentPermissionUrl&select=*" $serviceHeaders))

  $baselineUserPages = if ($permissionSnapshots.user.Count) { @($permissionSnapshots.user[0].allowed_pages) } else { @() }
  $baselineRolePages = if ($permissionSnapshots.role.Count) { @($permissionSnapshots.role[0].allowed_pages) } else { @() }
  $baselineDepartmentPages = if ($permissionSnapshots.department.Count) { @($permissionSnapshots.department[0].allowed_pages) } else { @() }
  $null = Raw POST "$base/rest/v1/user_permissions?on_conflict=user_id" $serviceUpsertHeaders @{user_id=$subjectId;allowed_pages=(Without-Schedule $baselineUserPages)}
  $null = Raw POST "$base/rest/v1/role_permissions?on_conflict=role" $serviceUpsertHeaders @{role=$roleKey;allowed_pages=(Without-Schedule $baselineRolePages)}
  $null = Raw POST "$base/rest/v1/role_permissions?on_conflict=role" $serviceUpsertHeaders @{role=$departmentKey;allowed_pages=(Without-Schedule $baselineDepartmentPages)}

  $subjectToken = $tokens[$subjectId]
  $outsiderToken = $tokens[$outsiderId]
  $adminToken = $tokens[$adminId]
  Mark default_deny ((Json (Rpc has_my_page_access @{p_page='schedule'} $subjectToken)) -eq $false)
  Mark administrator_bypass ((Json (Rpc has_my_page_access @{p_page='schedule'} $adminToken)) -eq $true)
  Mark anonymous_denied (Denied (Rpc has_my_page_access @{p_page='schedule'}))
  Mark internal_evaluator_denied (Denied (Rpc has_effective_page_access_internal @{p_user_id=$subjectId;p_page='schedule'} $subjectToken))
  Mark dispatcher_list_denied (Denied (Rpc list_due_schedule_reminders_for_dispatch @{p_limit=10} $subjectToken))

  $deniedInsert = Raw POST "$base/rest/v1/reminders" (Headers $anon $subjectToken $true) @{user_id=$subjectId;title=$marker;due_date=(Get-Date).ToUniversalTime().AddMinutes(5).ToString('o');status='pending';recurrence_type='NONE';recurrence_interval=1}
  Mark insert_without_grant_denied (($deniedInsert.status -in 200..299 -and @((Json $deniedInsert)).Count -eq 0) -or (Denied $deniedInsert))

  $deniedFixture = @(Json (Raw POST "$base/rest/v1/reminders" $serviceWriteHeaders @{user_id=$subjectId;title="$marker DENIED";due_date=(Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o');status='pending';recurrence_type='NONE';recurrence_interval=1}))[0]
  if ($deniedFixture.id) { $createdReminderIds += $deniedFixture.id }
  $deniedDispatchRows = @(Json (ServiceRpc list_due_schedule_reminders_for_dispatch @{p_limit=500}))
  Mark denied_reminder_not_dispatchable (@($deniedDispatchRows | Where-Object id -eq $deniedFixture.id).Count -eq 0)

  $null = Raw PATCH $userPermissionUrl $serviceHeaders @{allowed_pages=(With-Schedule $baselineUserPages)}
  Mark individual_grant ((Json (Rpc has_my_page_access @{p_page='schedule'} $subjectToken)) -eq $true)
  $authorizedDispatchRows = @(Json (ServiceRpc list_due_schedule_reminders_for_dispatch @{p_limit=500}))
  Mark authorized_reminder_dispatchable (@($authorizedDispatchRows | Where-Object id -eq $deniedFixture.id).Count -eq 1)
  $created = @(Json (Raw POST "$base/rest/v1/reminders" (Headers $anon $subjectToken $true) @{user_id=$subjectId;title=$marker;description='integration fixture';due_date=(Get-Date).ToUniversalTime().AddMinutes(5).ToString('o');status='pending';recurrence_type='DAILY';recurrence_interval=1}))[0]
  if ($created.id) { $createdReminderIds += $created.id }
  Mark insert_with_grant ([bool]$created.id)
  $ownRead = @(Json (Raw GET "$base/rest/v1/reminders?id=eq.$($created.id)&select=*" (Headers $anon $subjectToken)))
  Mark select_own_with_grant ($ownRead.Count -eq 1 -and $ownRead[0].user_id -eq $subjectId)
  $update = Raw PATCH "$base/rest/v1/reminders?id=eq.$($created.id)" (Headers $anon $subjectToken $true) @{status='completed'}
  Mark update_own_with_grant (@((Json $update)).Count -eq 1)
  $deleteFixture = @(Json (Raw POST "$base/rest/v1/reminders" (Headers $anon $subjectToken $true) @{user_id=$subjectId;title="$marker DELETE";due_date=(Get-Date).ToUniversalTime().AddMinutes(10).ToString('o');status='pending';recurrence_type='NONE';recurrence_interval=1}))[0]
  if ($deleteFixture.id) { $createdReminderIds += $deleteFixture.id }
  $deleteOwn = Raw DELETE "$base/rest/v1/reminders?id=eq.$($deleteFixture.id)" (Headers $anon $subjectToken $true)
  Mark delete_own_with_grant ($deleteOwn.status -in 200..299 -and @((Json $deleteOwn)).Count -eq 1)
  $crossRead = @(Json (Raw GET "$base/rest/v1/reminders?id=eq.$($created.id)&select=*" (Headers $anon $outsiderToken)))
  $crossUpdate = Raw PATCH "$base/rest/v1/reminders?id=eq.$($created.id)" (Headers $anon $outsiderToken $true) @{status='pending'}
  $crossDelete = Raw DELETE "$base/rest/v1/reminders?id=eq.$($created.id)" (Headers $anon $outsiderToken $true)
  Mark cross_employee_denied ($crossRead.Count -eq 0 -and @((Json $crossUpdate)).Count -eq 0 -and @((Json $crossDelete)).Count -eq 0)

  $null = Raw PATCH $userPermissionUrl $serviceHeaders @{allowed_pages=(Without-Schedule $baselineUserPages)}
  $null = Raw PATCH $rolePermissionUrl $serviceHeaders @{allowed_pages=(With-Schedule $baselineRolePages)}
  Mark role_grant ((Json (Rpc has_my_page_access @{p_page='schedule'} $subjectToken)) -eq $true)
  $null = Raw PATCH $rolePermissionUrl $serviceHeaders @{allowed_pages=(Without-Schedule $baselineRolePages)}
  $null = Raw PATCH $departmentPermissionUrl $serviceHeaders @{allowed_pages=(With-Schedule $baselineDepartmentPages)}
  Mark department_grant ((Json (Rpc has_my_page_access @{p_page='schedule'} $subjectToken)) -eq $true)
  $null = Raw PATCH $departmentPermissionUrl $serviceHeaders @{allowed_pages=(Without-Schedule $baselineDepartmentPages)}

  Mark revoked_same_session ((Json (Rpc has_my_page_access @{p_page='schedule'} $subjectToken)) -eq $false)
  $revokedDispatchRows = @(Json (ServiceRpc list_due_schedule_reminders_for_dispatch @{p_limit=500}))
  Mark revoked_reminder_not_dispatchable (@($revokedDispatchRows | Where-Object id -eq $deniedFixture.id).Count -eq 0)
  $revokedRead = @(Json (Raw GET "$base/rest/v1/reminders?id=eq.$($created.id)&select=*" (Headers $anon $subjectToken)))
  $revokedUpdate = Raw PATCH "$base/rest/v1/reminders?id=eq.$($created.id)" (Headers $anon $subjectToken $true) @{status='pending'}
  $revokedDelete = Raw DELETE "$base/rest/v1/reminders?id=eq.$($created.id)" (Headers $anon $subjectToken $true)
  Mark revoked_crud_denied ($revokedRead.Count -eq 0 -and @((Json $revokedUpdate)).Count -eq 0 -and @((Json $revokedDelete)).Count -eq 0)

  $null = Raw PATCH "$base/rest/v1/profiles?id=eq.$subjectId" $serviceHeaders @{is_active=$false}
  $null = Raw PATCH $userPermissionUrl $serviceHeaders @{allowed_pages=(With-Schedule $baselineUserPages)}
  Mark inactive_profile_denied ((Json (Rpc has_my_page_access @{p_page='schedule'} $subjectToken)) -eq $false)
  $null = Raw PATCH "$base/rest/v1/profiles?id=eq.$subjectId" $serviceHeaders @{is_active=[bool]$subject.is_active}
} finally {
  if ($subject) {
    $subjectId = [string]$subject.id
    foreach ($entry in @(
      @{ rows=$permissionSnapshots.user; url="$base/rest/v1/user_permissions?user_id=eq.$subjectId"; table='user_permissions'; key='user_id'; value=$subjectId },
      @{ rows=$permissionSnapshots.role; url="$base/rest/v1/role_permissions?role=eq.$([uri]::EscapeDataString($roleKey))"; table='role_permissions'; key='role'; value=$roleKey },
      @{ rows=$permissionSnapshots.department; url="$base/rest/v1/role_permissions?role=eq.$([uri]::EscapeDataString($departmentKey))"; table='role_permissions'; key='role'; value=$departmentKey }
    )) {
      if (@($entry.rows).Count) {
        $restore = Raw PATCH $entry.url $serviceHeaders @{allowed_pages=@($entry.rows[0].allowed_pages)}
      } else {
        $restore = Raw DELETE $entry.url $serviceHeaders
      }
      if ($restore.status -notin 200..299 -and $restore.status -ne 404) { $cleanupFailed = $true }
    }
    $profileRestore = Raw PATCH "$base/rest/v1/profiles?id=eq.$subjectId" $serviceHeaders @{is_active=[bool]$subject.is_active}
    if ($profileRestore.status -notin 200..299) { $cleanupFailed = $true }
  }
  foreach ($id in $createdReminderIds) {
    $cleanup = Raw DELETE "$base/rest/v1/reminders?id=eq.$id" $serviceHeaders
    if ($cleanup.status -notin 200..299 -and $cleanup.status -ne 404) { $cleanupFailed = $true }
  }
}

$results.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
if ($cleanupFailed) { Write-Output 'cleanup_failed=True'; exit 1 }
if (($results.Values | Where-Object { -not $_ }).Count -gt 0) { exit 1 }
