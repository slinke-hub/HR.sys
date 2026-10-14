[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$StagingProjectRef
)

$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'

# This script is intentionally staging-only. It is prepared for a separately
# approved integration run and must never be used against Production.
$ExpectedStagingRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$TargetRef = $StagingProjectRef.Trim()
if ($TargetRef -ceq $ProductionRef -or $TargetRef -cne $ExpectedStagingRef) {
  throw 'Refusing a project reference that is not the explicitly approved staging project.'
}
$refPath = Join-Path $PSScriptRoot '..\.temp\project-ref'
if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing linked Supabase project reference.' }
$linked = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linked -cne $TargetRef -or $linked -ceq $ProductionRef) { throw 'The linked project is not the explicitly approved staging project.' }
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
function Require-Success($response, [string]$operation) {
  if ($response.status -notin 200..299) { throw "$operation failed in staging." }
}
function Require-SyntheticAccessToken($profile, [string]$environmentVariable) {
  $token = [Environment]::GetEnvironmentVariable($environmentVariable, 'Process')
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw "Missing ephemeral access token for dedicated synthetic identity $($profile.employee_id)."
  }
  $identityResponse = Raw GET "$base/auth/v1/user" (Headers $anon $token.Trim())
  $identity = Json $identityResponse
  if ($identityResponse.status -notin 200..299 -or [string]$identity.id -cne [string]$profile.id) {
    throw "Access token identity verification failed for dedicated synthetic identity $($profile.employee_id)."
  }
  return $token.Trim()
}
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
  $requiredEmployeeIds = @('TEST-ADMIN', 'TEST-EMPLOYEE', 'TEST-OUTSIDER')
  $profiles = @(Json (Raw GET "$base/rest/v1/profiles?employee_id=in.(TEST-ADMIN,TEST-EMPLOYEE,TEST-OUTSIDER)&select=id,employee_id,role,department_id,is_active" $serviceHeaders))
  if ($profiles.Count -ne $requiredEmployeeIds.Count) { throw 'Dedicated synthetic staging profiles are missing or duplicated.' }
  $profilesByEmployeeId = @{}
  foreach ($profile in $profiles) {
    $employeeId = [string]$profile.employee_id
    if ($employeeId -notin $requiredEmployeeIds -or $profilesByEmployeeId.ContainsKey($employeeId)) {
      throw 'Dedicated synthetic staging profile identity verification failed.'
    }
    $profilesByEmployeeId[$employeeId] = $profile
  }
  foreach ($employeeId in $requiredEmployeeIds) {
    if (-not $profilesByEmployeeId.ContainsKey($employeeId)) { throw 'A required dedicated synthetic staging profile is unavailable.' }
  }

  $adminProfile = $profilesByEmployeeId['TEST-ADMIN']
  $subject = $profilesByEmployeeId['TEST-EMPLOYEE']
  $outsider = $profilesByEmployeeId['TEST-OUTSIDER']
  if ([string]$adminProfile.role -cne 'ADMIN' -or [string]$subject.role -cne 'EMPLOYEE' -or [string]$outsider.role -cne 'EMPLOYEE') {
    throw 'Dedicated synthetic staging profile roles do not match the required security matrix.'
  }
  if (@($profiles | Where-Object { $_.is_active -eq $false }).Count -gt 0) { throw 'All dedicated synthetic staging profiles must be active before the test.' }
  if (-not $subject.department_id) { throw 'TEST-EMPLOYEE requires a department for department-grant validation.' }

  $tokens = @{}
  foreach ($requirement in @(
    @{ profile=$adminProfile; variable='HR_SYS_STAGING_TEST_ADMIN_TOKEN' },
    @{ profile=$subject; variable='HR_SYS_STAGING_TEST_EMPLOYEE_TOKEN' },
    @{ profile=$outsider; variable='HR_SYS_STAGING_TEST_OUTSIDER_TOKEN' }
  )) {
    $tokens[[string]$requirement.profile.id] = Require-SyntheticAccessToken $requirement.profile $requirement.variable
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
  Require-Success (Raw POST "$base/rest/v1/user_permissions?on_conflict=user_id" $serviceUpsertHeaders @{user_id=$subjectId;allowed_pages=(Without-Schedule $baselineUserPages)}) 'Preparing the synthetic employee permission fixture'
  Require-Success (Raw POST "$base/rest/v1/role_permissions?on_conflict=role" $serviceUpsertHeaders @{role=$roleKey;allowed_pages=(Without-Schedule $baselineRolePages)}) 'Preparing the synthetic role permission fixture'
  Require-Success (Raw POST "$base/rest/v1/role_permissions?on_conflict=role" $serviceUpsertHeaders @{role=$departmentKey;allowed_pages=(Without-Schedule $baselineDepartmentPages)}) 'Preparing the synthetic department permission fixture'

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

  Require-Success (Raw PATCH $userPermissionUrl $serviceHeaders @{allowed_pages=(With-Schedule $baselineUserPages)}) 'Granting the synthetic employee Schedule access'
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

  Require-Success (Raw PATCH $userPermissionUrl $serviceHeaders @{allowed_pages=(Without-Schedule $baselineUserPages)}) 'Removing the synthetic employee Schedule grant'
  Require-Success (Raw PATCH $rolePermissionUrl $serviceHeaders @{allowed_pages=(With-Schedule $baselineRolePages)}) 'Granting the synthetic role Schedule access'
  Mark role_grant ((Json (Rpc has_my_page_access @{p_page='schedule'} $subjectToken)) -eq $true)
  Require-Success (Raw PATCH $rolePermissionUrl $serviceHeaders @{allowed_pages=(Without-Schedule $baselineRolePages)}) 'Removing the synthetic role Schedule grant'
  Require-Success (Raw PATCH $departmentPermissionUrl $serviceHeaders @{allowed_pages=(With-Schedule $baselineDepartmentPages)}) 'Granting the synthetic department Schedule access'
  Mark department_grant ((Json (Rpc has_my_page_access @{p_page='schedule'} $subjectToken)) -eq $true)
  Require-Success (Raw PATCH $departmentPermissionUrl $serviceHeaders @{allowed_pages=(Without-Schedule $baselineDepartmentPages)}) 'Removing the synthetic department Schedule grant'

  Mark revoked_same_session ((Json (Rpc has_my_page_access @{p_page='schedule'} $subjectToken)) -eq $false)
  $revokedDispatchRows = @(Json (ServiceRpc list_due_schedule_reminders_for_dispatch @{p_limit=500}))
  Mark revoked_reminder_not_dispatchable (@($revokedDispatchRows | Where-Object id -eq $deniedFixture.id).Count -eq 0)
  $revokedRead = @(Json (Raw GET "$base/rest/v1/reminders?id=eq.$($created.id)&select=*" (Headers $anon $subjectToken)))
  $revokedUpdate = Raw PATCH "$base/rest/v1/reminders?id=eq.$($created.id)" (Headers $anon $subjectToken $true) @{status='pending'}
  $revokedDelete = Raw DELETE "$base/rest/v1/reminders?id=eq.$($created.id)" (Headers $anon $subjectToken $true)
  Mark revoked_crud_denied ($revokedRead.Count -eq 0 -and @((Json $revokedUpdate)).Count -eq 0 -and @((Json $revokedDelete)).Count -eq 0)

  Require-Success (Raw PATCH "$base/rest/v1/profiles?id=eq.$subjectId" $serviceHeaders @{is_active=$false}) 'Deactivating the synthetic employee fixture'
  Require-Success (Raw PATCH $userPermissionUrl $serviceHeaders @{allowed_pages=(With-Schedule $baselineUserPages)}) 'Granting the inactive synthetic employee fixture Schedule access'
  Mark inactive_profile_denied ((Json (Rpc has_my_page_access @{p_page='schedule'} $subjectToken)) -eq $false)
  Require-Success (Raw PATCH "$base/rest/v1/profiles?id=eq.$subjectId" $serviceHeaders @{is_active=[bool]$subject.is_active}) 'Restoring the synthetic employee activity state'
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
