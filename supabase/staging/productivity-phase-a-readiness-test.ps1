$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$refPath = Join-Path $PSScriptRoot '..\.temp\project-ref'
if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing linked Supabase project reference.' }
$linked = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linked -cne $TargetRef -or $linked -ceq $ProductionRef) { throw "Refusing non-staging target: $linked" }
$base = "https://$TargetRef.supabase.co"

function Quote-ProcessArgument([string]$Value) {
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}
function Invoke-SupabaseCliJson([string[]]$Arguments) {
  $command = Get-Command supabase -CommandType Application -ErrorAction Stop
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = if ($command.Path) { $command.Path } else { $command.Source }
  $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true; $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
  $process = New-Object System.Diagnostics.Process; $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'Unable to start Supabase CLI.' }
  $stdoutTask = $process.StandardOutput.ReadToEndAsync(); $stderrTask = $process.StandardError.ReadToEndAsync(); $process.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult(); $stderr = $stderrTask.GetAwaiter().GetResult()
  if ($process.ExitCode -ne 0) { throw "Supabase CLI failed with exit code $($process.ExitCode)." }
  try { return ($stdout | ConvertFrom-Json) } catch {
    $starts = @($stdout.IndexOf('['), $stdout.IndexOf('{')) | Where-Object { $_ -ge 0 }
    $ends = @($stdout.LastIndexOf(']'), $stdout.LastIndexOf('}')) | Where-Object { $_ -ge 0 }
    if ($starts.Count -eq 0 -or $ends.Count -eq 0) { throw 'Supabase CLI returned no JSON payload.' }
    $start = ($starts | Measure-Object -Minimum).Minimum; $end = ($ends | Measure-Object -Maximum).Maximum
    return ($stdout.Substring($start, $end - $start + 1) | ConvertFrom-Json)
  }
}
function Headers($key, $token = $null) { $h = @{ apikey = $key; Authorization = "Bearer $key"; 'Content-Type' = 'application/json' }; if ($token) { $h.Authorization = "Bearer $token" }; return $h }
function Raw($method, $url, $headers, $body = $null) {
  try { $p = @{ Method=$method; Uri=$url; Headers=$headers; ErrorAction='Stop'; UseBasicParsing=$true }; if ($null -ne $body) { $p.Body = ($body | ConvertTo-Json -Depth 30 -Compress) }; $r = Invoke-WebRequest @p; return [pscustomobject]@{ status=[int]$r.StatusCode; body=$r.Content } }
  catch { $s=0; if ($_.Exception.Response) { $s=[int]$_.Exception.Response.StatusCode.value__ }; $b=$_.ErrorDetails.Message; if ([string]::IsNullOrWhiteSpace($b)) { $b=$_.Exception.Message }; return [pscustomobject]@{ status=$s; body=$b } }
}
function Json($raw) { try { return ($raw.body | ConvertFrom-Json) } catch { return $null } }
function Rpc($name, $payload, $token = $null) { $uri = "$base/rest/v1/rpc/$name"; return Raw POST $uri (Headers $anon $token) $payload }
function Denied($r) { return $r.status -in 400,401,403,404 }
function New-Password { $bytes=New-Object byte[] 24; $rng=[Security.Cryptography.RandomNumberGenerator]::Create(); try {$rng.GetBytes($bytes)} finally {$rng.Dispose()}; return ([Convert]::ToBase64String($bytes)+'Aa9!') }
function SignIn($email, $password) { $uri = "$base/auth/v1/token?grant_type=password"; return Json (Raw POST $uri (Headers $anon) @{email=$email;password=$password}) }
function Mark($name, $value) { $script:results[$name] = [bool]$value }
function GetTaskState($id) {
  if (-not $id) { return $null }
  $uri = "$base/rest/v1/tasks?id=eq.$id&select=id,status,work_state,assignee_id,assignee_ids,created_by,started_at,completed_at,waiting_category,blocked_category"
  $raw = Raw GET $uri $serviceHeaders
  return [pscustomobject]@{ response=$raw; row=@(Json $raw)[0] }
}
function GetResponseDetails($raw) {
  $payload = Json $raw
  $code = ''
  $message = ''
  if ($payload) {
    $code = [string]$payload.code
    $message = [string]$payload.message
    if ([string]::IsNullOrWhiteSpace($message)) { $message = [string]$payload.error_description }
  }
  if ([string]::IsNullOrWhiteSpace($message)) { $message = [string]$raw.body }
  return [pscustomobject]@{ code=$code; message=($message -replace "\s+", ' ').Trim(); payload=$payload }
}
function InvokePhaseRpc($label, $rpcName, $payload, $token, $identity, $beforeState) {
  $raw = Rpc $rpcName $payload $token
  $details = GetResponseDetails $raw
  $result = $details.payload
  $afterState = GetTaskState $taskId
  $beforeStatus = if ($beforeState -and $beforeState.row) { [string]$beforeState.row.status } else { 'unavailable' }
  $beforeWorkState = if ($beforeState -and $beforeState.row) { [string]$beforeState.row.work_state } else { 'unavailable' }
  $afterStatus = if ($afterState -and $afterState.row) { [string]$afterState.row.status } else { 'unavailable' }
  $afterWorkState = if ($afterState -and $afterState.row) { [string]$afterState.row.work_state } else { 'unavailable' }
  $assignee = if ($beforeState -and $beforeState.row) { [string]$beforeState.row.assignee_id } else { 'unavailable' }
  $assignees = if ($beforeState -and $beforeState.row) { [string]$beforeState.row.assignee_ids } else { 'unavailable' }
  $creator = if ($beforeState -and $beforeState.row) { [string]$beforeState.row.created_by } else { 'unavailable' }
  $payloadSummary = ($payload | ConvertTo-Json -Depth 10 -Compress)
  [Console]::WriteLine("phase_diagnostic=operation:$label;identity:$identity;rpc:$rpcName;http_status:$($raw.status);pg_code:$($details.code);message:$($details.message);payload:$payloadSummary;task_status_before:$beforeStatus;task_work_state_before:$beforeWorkState;task_status_after:$afterStatus;task_work_state_after:$afterWorkState;assignee_id:$assignee;assignee_ids:$assignees;created_by:$creator")
  return [pscustomobject]@{ raw=$raw; result=$result; before=$beforeState; after=$afterState; details=$details }
}

$keys = Invoke-SupabaseCliJson @('projects','api-keys','--project-ref',$TargetRef,'--reveal','--output','json')
$service = ($keys | Where-Object name -eq service_role | Select-Object -First 1).api_key
$anon = ($keys | Where-Object name -eq anon | Select-Object -First 1).api_key
if ([string]::IsNullOrWhiteSpace($service) -or [string]::IsNullOrWhiteSpace($anon)) { throw 'Staging API keys unavailable.' }
$serviceHeaders = Headers $service
$profiles = @{}; $tokens = @{}; $emails = @{}; $passwords = @{}; $results = [ordered]@{}
$marker = "PRODUCTIVITY PHASE A SECURITY TEST $([guid]::NewGuid())"; $taskId = $null; $cleanupFailed = $false

try {
  $profileUri = "$base/rest/v1/profiles?employee_id=in.(TEST-MANAGER,TEST-EMPLOYEE,TEST-OUTSIDER)&select=id,employee_id,role,is_active"
  $profileRows = Json (Raw GET $profileUri $serviceHeaders)
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
  $employeeId = $profiles['TEST-EMPLOYEE'].id; $outsiderId = $profiles['TEST-OUTSIDER'].id
  $createPayload = @{title=$marker;description='Temporary Phase A readiness task';assignee_id=$employeeId;assignee_ids=@($employeeId);due_date=((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'));priority='high';status='todo';visibility='private'}
  $created = Json (Rpc create_task_secure @{p_payload=$createPayload} $tokens['TEST-MANAGER']); $taskId = @($created)[0].id
  Mark task_create ([bool]$taskId)
  if (-not $taskId) { throw 'Synthetic task creation failed.' }
  Mark task_visible_to_assignee ([bool]((Json (Rpc get_task_secure @{p_task_id=$taskId} $tokens['TEST-EMPLOYEE']))))
  Mark outsider_task_denied (-not [bool]((Json (Rpc get_task_secure @{p_task_id=$taskId} $tokens['TEST-OUTSIDER']))))
  $directUri = "$base/rest/v1/tasks?id=eq.$taskId"
  $outsiderRows = Json (Raw GET $directUri (Headers $anon $tokens['TEST-OUTSIDER']))
  Mark direct_read_denied (@($outsiderRows).Count -eq 0)
  $schemaProbe = GetTaskState $taskId; $schemaDetails = GetResponseDetails $schemaProbe.response
  [Console]::WriteLine("phase_diagnostic=operation:TASK_STATE_PRECHECK;identity:TEST-MANAGER;rpc:rest_v1_tasks_select;http_status:$($schemaProbe.response.status);pg_code:$($schemaDetails.code);message:$($schemaDetails.message);task_id:$taskId")
  $startPayload = @{p_task_id=$taskId}; $startBefore = $schemaProbe
  $startResult = InvokePhaseRpc 'START' 'start_task' $startPayload $tokens['TEST-EMPLOYEE'] 'TEST-EMPLOYEE' $startBefore
  # start_task returns status/in_progress and started_at; work_state is
  # verified from the persisted row rather than expected in the RPC payload.
  $startOk = ($startResult.raw.status -in 200..299 -and [string]$startResult.result.status -eq 'in_progress' -and [bool]$startResult.result.changed -and $startResult.after.response.status -in 200..299 -and [string]$startResult.after.row.status -eq 'in_progress' -and [string]$startResult.after.row.work_state -eq 'ACTIVE')
  Mark start $startOk
  if (-not $startOk) {
    [Console]::WriteLine('phase_dependency_cascade=START_FAILED;waiting,resume,blocked,resume_after_blocked,history_access,complete,completed_today were not executed because the first transition failed.')
    Mark waiting $false; Mark manager_waiting_visibility $false; Mark resume $false; Mark blocked $false; Mark resume_after_blocked $false; Mark history_access $false; Mark complete $false; Mark completed_today $false
  } else {
    $waitingPayload = @{p_task_id=$taskId;p_category='CLIENT';p_related_user_id=$null;p_note='Synthetic waiting test'}; $waitingBefore = GetTaskState $taskId
    $waitingResult = InvokePhaseRpc 'WAITING' 'mark_task_waiting' $waitingPayload $tokens['TEST-EMPLOYEE'] 'TEST-EMPLOYEE' $waitingBefore
    Mark waiting ($waitingResult.raw.status -in 200..299 -and [string]$waitingResult.result.work_state -eq 'WAITING' -and $waitingResult.after.response.status -in 200..299 -and [string]$waitingResult.after.row.work_state -eq 'WAITING')
    $managerRaw = Rpc list_task_work_states_secure @{} $tokens['TEST-MANAGER']; $managerStates = Json $managerRaw; $managerDetails = GetResponseDetails $managerRaw
    [Console]::WriteLine("phase_diagnostic=operation:MANAGER_WAITING_VISIBILITY;identity:TEST-MANAGER;rpc:list_task_work_states_secure;http_status:$($managerRaw.status);pg_code:$($managerDetails.code);message:$($managerDetails.message);task_id:$taskId")
    Mark manager_waiting_visibility ($managerRaw.status -in 200..299 -and @($managerStates | Where-Object id -eq $taskId).Count -eq 1)
    $resumePayload = @{p_task_id=$taskId}; $resumeBefore = GetTaskState $taskId
    $resumeResult = InvokePhaseRpc 'RESUME' 'resume_task' $resumePayload $tokens['TEST-EMPLOYEE'] 'TEST-EMPLOYEE' $resumeBefore
    Mark resume ($resumeResult.raw.status -in 200..299 -and [string]$resumeResult.result.work_state -eq 'ACTIVE' -and $resumeResult.after.response.status -in 200..299 -and [string]$resumeResult.after.row.work_state -eq 'ACTIVE')
    $blockedPayload = @{p_task_id=$taskId;p_category='TECHNICAL_PROBLEM';p_related_user_id=$null;p_note='Synthetic blocker test'}; $blockedBefore = GetTaskState $taskId
    $blockedResult = InvokePhaseRpc 'BLOCKED' 'mark_task_blocked' $blockedPayload $tokens['TEST-EMPLOYEE'] 'TEST-EMPLOYEE' $blockedBefore
    Mark blocked ($blockedResult.raw.status -in 200..299 -and [string]$blockedResult.result.work_state -eq 'BLOCKED' -and $blockedResult.after.response.status -in 200..299 -and [string]$blockedResult.after.row.work_state -eq 'BLOCKED')
    Mark outsider_start_denied (Denied (Rpc start_task @{p_task_id=$taskId} $tokens['TEST-OUTSIDER']))
    Mark outsider_waiting_denied (Denied (Rpc mark_task_waiting @{p_task_id=$taskId;p_category='CLIENT';p_related_user_id=$null;p_note='IDOR'} $tokens['TEST-OUTSIDER']))
    Mark outsider_blocked_denied (Denied (Rpc mark_task_blocked @{p_task_id=$taskId;p_category='TECHNICAL_PROBLEM';p_related_user_id=$null;p_note='IDOR'} $tokens['TEST-OUTSIDER']))
    Mark outsider_resume_denied (Denied (Rpc resume_task @{p_task_id=$taskId} $tokens['TEST-OUTSIDER']))
    Mark outsider_complete_denied (Denied (Rpc complete_task_productivity @{p_task_id=$taskId} $tokens['TEST-OUTSIDER']))
    Mark outsider_mutation_denied ($results['outsider_start_denied'] -and $results['outsider_waiting_denied'] -and $results['outsider_blocked_denied'] -and $results['outsider_resume_denied'] -and $results['outsider_complete_denied'])
    $resumeBlockedPayload = @{p_task_id=$taskId}; $resumeBlockedBefore = GetTaskState $taskId
    $resumeBlockedResult = InvokePhaseRpc 'RESUME_AFTER_BLOCKED' 'resume_task' $resumeBlockedPayload $tokens['TEST-EMPLOYEE'] 'TEST-EMPLOYEE' $resumeBlockedBefore
    Mark resume_after_blocked ($resumeBlockedResult.raw.status -in 200..299 -and [string]$resumeBlockedResult.result.work_state -eq 'ACTIVE' -and $resumeBlockedResult.after.response.status -in 200..299 -and [string]$resumeBlockedResult.after.row.work_state -eq 'ACTIVE')
    $historyRaw = Rpc list_task_work_history_secure @{p_task_id=$taskId} $tokens['TEST-EMPLOYEE']; $historyDetails = GetResponseDetails $historyRaw
    [Console]::WriteLine("phase_diagnostic=operation:HISTORY;identity:TEST-EMPLOYEE;rpc:list_task_work_history_secure;http_status:$($historyRaw.status);pg_code:$($historyDetails.code);message:$($historyDetails.message);task_id:$taskId")
    Mark history_access ($historyRaw.status -in 200..299 -and @((Json $historyRaw)).Count -ge 2)
    $completePayload = @{p_task_id=$taskId}; $completeBefore = GetTaskState $taskId
    $completeResult = InvokePhaseRpc 'COMPLETE' 'complete_task_productivity' $completePayload $tokens['TEST-EMPLOYEE'] 'TEST-EMPLOYEE' $completeBefore
    Mark complete ($completeResult.raw.status -in 200..299 -and [string]$completeResult.result.status -eq 'completed' -and $completeResult.after.response.status -in 200..299 -and [string]$completeResult.after.row.status -eq 'completed' -and -not [string]::IsNullOrWhiteSpace([string]$completeResult.after.row.completed_at))
    $completedRaw = Rpc get_my_completed_today @{} $tokens['TEST-EMPLOYEE']; $completedDetails = GetResponseDetails $completedRaw
    [Console]::WriteLine("phase_diagnostic=operation:COMPLETED_TODAY;identity:TEST-EMPLOYEE;rpc:get_my_completed_today;http_status:$($completedRaw.status);pg_code:$($completedDetails.code);message:$($completedDetails.message);task_id:$taskId")
    Mark completed_today ($completedRaw.status -in 200..299 -and @((Json $completedRaw) | Where-Object id -eq $taskId).Count -eq 1)
  }
  Mark direct_update_denied (Denied (Raw PATCH $directUri (Headers $anon $tokens['TEST-OUTSIDER']) @{title='IDOR'}))
  Mark employee_protected_update_denied (Denied (Raw PATCH $directUri (Headers $anon $tokens['TEST-EMPLOYEE']) @{assignee_id=$outsiderId;created_by=$outsiderId}))
  Mark employee_reassign_denied (Denied (Rpc assign_task @{p_task_id=$taskId;p_assignee_ids=@($outsiderId)} $tokens['TEST-EMPLOYEE']))
  Mark direct_insert_denied (Denied (Raw POST "$base/rest/v1/tasks" (Headers $anon $tokens['TEST-OUTSIDER']) @{title='DIRECT BYPASS';created_by=$outsiderId;status='todo'}))
} finally {
  if ($taskId) {
    $cleanupUri = "$base/rest/v1/tasks?id=eq.$taskId"
    $cleanup = Raw DELETE $cleanupUri $serviceHeaders
    if ($cleanup.status -notin 200..299 -and $cleanup.status -ne 404) { $cleanupFailed = $true }
  }
}

$results.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
if ($cleanupFailed) { Write-Output 'cleanup_failed=True'; exit 1 }
if (($results.Values | Where-Object { -not $_ }).Count -gt 0) { exit 1 }
Write-Output "PRODUCTIVITY PHASE A READINESS: PASS ($TargetRef)"
