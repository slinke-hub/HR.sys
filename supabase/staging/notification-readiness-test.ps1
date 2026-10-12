$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'
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
  $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true; $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = (($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' ')
  $process = New-Object System.Diagnostics.Process; $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'Unable to start Supabase CLI.' }
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  if ($process.ExitCode -ne 0) { throw "Supabase CLI failed with exit code $($process.ExitCode)." }
  try { return ($stdout | ConvertFrom-Json) } catch {
    $starts = @($stdout.IndexOf('['), $stdout.IndexOf('{')) | Where-Object { $_ -ge 0 }
    $ends = @($stdout.LastIndexOf(']'), $stdout.LastIndexOf('}')) | Where-Object { $_ -ge 0 }
    if ($starts.Count -eq 0 -or $ends.Count -eq 0) { throw 'Supabase CLI returned no JSON payload.' }
    $start = ($starts | Measure-Object -Minimum).Minimum; $end = ($ends | Measure-Object -Maximum).Maximum
    try { return ($stdout.Substring($start, $end - $start + 1) | ConvertFrom-Json) } catch { throw 'Supabase CLI returned an invalid JSON payload.' }
  }
}
function Headers($key, $token = $null) { $h = @{ apikey = $key; Authorization = "Bearer $key"; 'Content-Type' = 'application/json' }; if ($token) { $h.Authorization = "Bearer $token" }; return $h }
function Raw($method, $url, $headers, $body = $null) { try { $p = @{ Method=$method; Uri=$url; Headers=$headers; ErrorAction='Stop'; UseBasicParsing=$true }; if ($null -ne $body) { $p.Body = ($body | ConvertTo-Json -Depth 20 -Compress) }; $r = Invoke-WebRequest @p; return [pscustomobject]@{ status=[int]$r.StatusCode; body=$r.Content } } catch { $s=0; if ($_.Exception.Response) { $s=[int]$_.Exception.Response.StatusCode.value__ }; return [pscustomobject]@{ status=$s; body=$_.ErrorDetails.Message } } }
function Json($raw) { try { return ($raw.body | ConvertFrom-Json) } catch { return $null } }
function Rpc($name, $payload, $token = $null) { Raw POST "$base/rest/v1/rpc/$name" (Headers $anon $token) $payload }
function Mark($name, $value) { $script:results[$name] = [bool]$value }
function Denied($r) { return $r.status -in 400,401,403,404 }
function New-Password { $bytes=New-Object byte[] 24; $rng=[Security.Cryptography.RandomNumberGenerator]::Create(); try {$rng.GetBytes($bytes)} finally {$rng.Dispose()}; return ([Convert]::ToBase64String($bytes)+'Aa9!') }
function SignIn($email, $password) { Json (Raw POST "$base/auth/v1/token?grant_type=password" (Headers $anon) @{email=$email;password=$password}) }

$keys = Invoke-SupabaseCliJson @('projects','api-keys','--project-ref',$TargetRef,'--reveal','--output','json')
$service = ($keys | Where-Object name -eq service_role | Select-Object -First 1).api_key
$anon = ($keys | Where-Object name -eq anon | Select-Object -First 1).api_key
if ([string]::IsNullOrWhiteSpace($service) -or [string]::IsNullOrWhiteSpace($anon)) { throw 'Staging API keys unavailable.' }
$serviceHeaders = Headers $service
$serviceWriteHeaders = @{}
foreach ($key in $serviceHeaders.Keys) { $serviceWriteHeaders[$key] = $serviceHeaders[$key] }
$serviceWriteHeaders['Prefer'] = 'return=representation'
$profiles = @{}; $tokens = @{}; $emails = @{}; $passwords = @{}; $results = [ordered]@{}
$marker = "NOTIFICATION SECURITY TEST $([guid]::NewGuid())"
$createdNotificationIds = @(); $createdDeviceIds = @()
$cleanupFailed = $false

try {
  $profileRows = Json (Raw GET "$base/rest/v1/profiles?employee_id=in.(TEST-MANAGER,TEST-EMPLOYEE,TEST-OUTSIDER)&select=id,employee_id,role,is_active" $serviceHeaders)
  foreach ($row in @($profileRows)) { $profiles[$row.employee_id] = $row }
  $authList = Json (Raw GET "$base/auth/v1/admin/users?per_page=100" $serviceHeaders)
  foreach ($employeeId in @('TEST-MANAGER','TEST-EMPLOYEE','TEST-OUTSIDER')) {
    $profile = $profiles[$employeeId]; if (-not $profile) { throw "Missing staging profile for $employeeId" }
    $user = @($authList.users) | Where-Object id -eq $profile.id | Select-Object -First 1
    if (-not $user) { throw "Missing Auth identity for $employeeId" }
    $emails[$employeeId] = [string]$user.email; $passwords[$employeeId] = New-Password
    $reset = Raw PUT "$base/auth/v1/admin/users/$($user.id)" $serviceHeaders @{password=$passwords[$employeeId];email_confirm=$true}
    if ($reset.status -notin 200..299) { throw "Unable to prepare $employeeId" }
    $session = SignIn $emails[$employeeId] $passwords[$employeeId]
    if (-not $session.access_token) { throw "Unable to authenticate $employeeId" }
    $tokens[$employeeId] = $session.access_token
  }
  Mark identities_ready ($profiles.Count -eq 3 -and $profiles['TEST-MANAGER'].role -eq 'MANAGER' -and $profiles['TEST-EMPLOYEE'].role -eq 'EMPLOYEE' -and $profiles['TEST-OUTSIDER'].role -eq 'EMPLOYEE')

  $managerId = $profiles['TEST-MANAGER'].id; $employeeId = $profiles['TEST-EMPLOYEE'].id; $outsiderId = $profiles['TEST-OUTSIDER'].id
  $insertM = Raw POST "$base/rest/v1/notifications" $serviceWriteHeaders @{user_id=$managerId;message=$marker;event_type='notification_security_test';metadata=@{target_type='REQUEST';target_id='00000000-0000-0000-0000-000000000001'}}
  $insertE = Raw POST "$base/rest/v1/notifications" $serviceWriteHeaders @{user_id=$employeeId;message=$marker;event_type='notification_security_test';metadata=@{target_type='REQUEST';target_id='00000000-0000-0000-0000-000000000002'}}
  $managerNotification = @((Json $insertM))[0]; $employeeNotification = @((Json $insertE))[0]
  if ($managerNotification.id) { $createdNotificationIds += $managerNotification.id }; if ($employeeNotification.id) { $createdNotificationIds += $employeeNotification.id }

  $managerList = Json (Rpc list_my_notifications @{p_limit=20} $tokens['TEST-MANAGER'])
  $employeeList = Json (Rpc list_my_notifications @{p_limit=20} $tokens['TEST-EMPLOYEE'])
  Mark list_own_only (@($managerList | Where-Object user_id -ne $managerId).Count -eq 0 -and @($employeeList | Where-Object user_id -ne $employeeId).Count -eq 0)
  Mark unread_count ([int](Json (Rpc get_my_unread_notification_count @{} $tokens['TEST-MANAGER'])) -ge 0)
  Mark mark_own_read ((Json (Rpc mark_notification_read @{p_notification_id=$managerNotification.id} $tokens['TEST-MANAGER'])) -eq $true)
  Mark mark_other_read_denied ((Json (Rpc mark_notification_read @{p_notification_id=$employeeNotification.id} $tokens['TEST-MANAGER'])) -eq $false)
  Mark direct_notification_update_denied (Denied (Raw PATCH "$base/rest/v1/notifications?id=eq.$($employeeNotification.id)" (Headers $anon $tokens['TEST-MANAGER']) @{is_read=$true}))
  Mark direct_notification_insert_denied (Denied (Raw POST "$base/rest/v1/notifications" (Headers $anon $tokens['TEST-EMPLOYEE']) @{user_id=$outsiderId;message='blocked'}))

  $device = Json (Rpc register_notification_device @{p_platform='android';p_push_token="synthetic-$([guid]::NewGuid())";p_device_name='Security test';p_app_version='test'} $tokens['TEST-MANAGER'])
  $deviceId = @($device)[0].id; if ($deviceId) { $createdDeviceIds += $deviceId }
  Mark device_register_own ([bool]$deviceId)
  Mark device_idor_delete_denied ((Json (Rpc unregister_notification_device @{p_device_id=$deviceId} $tokens['TEST-OUTSIDER'])) -eq $false)
  Mark device_delete_own ((Json (Rpc unregister_notification_device @{p_device_id=$deviceId} $tokens['TEST-MANAGER'])) -eq $true)

  Mark anonymous_notification_rpc_denied (Denied (Raw POST "$base/rest/v1/rpc/list_my_notifications" (Headers $anon) @{p_limit=20}))
  Mark anonymous_push_function_denied (Denied (Raw POST "$base/functions/v1/push-notification-dispatcher" (Headers $anon) @{action='config'}))
  Mark invalid_push_function_denied (Denied (Raw POST "$base/functions/v1/push-notification-dispatcher" (Headers $anon 'not-a-valid-jwt') @{action='config'}))
} finally {
  foreach ($id in $createdNotificationIds) {
    $cleanup = Raw DELETE "$base/rest/v1/notifications?id=eq.$id" $serviceHeaders
    if ($cleanup.status -notin 200..299 -and $cleanup.status -ne 404) { $cleanupFailed = $true }
  }
  foreach ($id in $createdDeviceIds) {
    $cleanup = Raw DELETE "$base/rest/v1/push_subscriptions?id=eq.$id" $serviceHeaders
    if ($cleanup.status -notin 200..299 -and $cleanup.status -ne 404) { $cleanupFailed = $true }
  }
}

$results.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
if ($cleanupFailed) { Write-Output 'cleanup_failed=True'; exit 1 }
if (($results.Values | Where-Object { -not $_ }).Count -gt 0) { exit 1 }
