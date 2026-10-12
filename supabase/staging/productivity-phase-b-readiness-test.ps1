$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$refPath = Join-Path $PSScriptRoot '..\.temp\project-ref'
if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing linked Supabase project reference.' }
$linkedRef = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linkedRef -cne $TargetRef -or $linkedRef -ceq $ProductionRef) { throw "ABORTED: linked project is '$linkedRef', not staging '$TargetRef'." }
$base = "https://$TargetRef.supabase.co"

function Quote-ProcessArgument([string]$Value) {
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}
function Invoke-SupabaseCliJson([string[]]$Arguments) {
  $command = Get-Command supabase -CommandType Application -ErrorAction Stop
  $info = New-Object System.Diagnostics.ProcessStartInfo
  $info.FileName = if ($command.Path) { $command.Path } else { $command.Source }
  $info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
  $info.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
  $process = New-Object System.Diagnostics.Process; $process.StartInfo = $info
  if (-not $process.Start()) { throw 'Unable to start Supabase CLI.' }
  $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync(); $process.WaitForExit()
  $out = $outTask.GetAwaiter().GetResult(); $err = $errTask.GetAwaiter().GetResult()
  if ($process.ExitCode -ne 0) { throw "Supabase CLI failed with exit code $($process.ExitCode)." }
  try { return ($out | ConvertFrom-Json) } catch {
    $start = @($out.IndexOf('['), $out.IndexOf('{')) | Where-Object { $_ -ge 0 } | Measure-Object -Minimum
    $end = @($out.LastIndexOf(']'), $out.LastIndexOf('}')) | Where-Object { $_ -ge 0 } | Measure-Object -Maximum
    if ($null -eq $start.Minimum -or $null -eq $end.Maximum) { throw 'Supabase CLI returned no JSON payload.' }
    return ($out.Substring($start.Minimum, $end.Maximum - $start.Minimum + 1) | ConvertFrom-Json)
  }
}
function Headers($key, $token = $null) {
  $h = @{ apikey=$key; Authorization="Bearer $key"; 'Content-Type'='application/json'; Prefer='return=representation' }
  if ($token) { $h.Authorization = "Bearer $token" }
  return $h
}
function Raw($method, $url, $headers, $body = $null) {
  try {
    $p = @{ Method=$method; Uri=$url; Headers=$headers; ErrorAction='Stop'; UseBasicParsing=$true }
    if ($null -ne $body) { $p.Body = ($body | ConvertTo-Json -Depth 30 -Compress) }
    $r = Invoke-WebRequest @p
    return [pscustomobject]@{ status=[int]$r.StatusCode; body=$r.Content }
  } catch {
    $status = 0; if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode.value__ }
    $bodyText = $_.ErrorDetails.Message; if ([string]::IsNullOrWhiteSpace($bodyText)) { $bodyText = $_.Exception.Message }
    return [pscustomobject]@{ status=$status; body=$bodyText }
  }
}
function Json($raw) { try { return ($raw.body | ConvertFrom-Json) } catch { return $null } }
function Rpc($name, $payload, $token) { Raw POST "$base/rest/v1/rpc/$name" (Headers $anonKey $token) $payload }
function Denied($raw) { return $raw.status -in @(400,401,403,404,409,422) }
function New-Password { $bytes=New-Object byte[] 24; $rng=[Security.Cryptography.RandomNumberGenerator]::Create(); try {$rng.GetBytes($bytes)} finally {$rng.Dispose()}; return ([Convert]::ToBase64String($bytes)+'Aa9!') }
function SignIn($email, $password) { Json (Raw POST "$base/auth/v1/token?grant_type=password" (Headers $anonKey) @{email=$email;password=$password}) }
function Mark($name, $value) { $script:results[$name] = [bool]$value }
function Row($raw) { @((Json $raw))[0] }
function ResponseDetails($raw) {
  $payload = Json $raw; $code=''; $message=''
  if ($payload) { $code=[string]$payload.code; $message=[string]$payload.message; if ([string]::IsNullOrWhiteSpace($message)) { $message=[string]$payload.error_description } }
  if ([string]::IsNullOrWhiteSpace($message)) { $message=[string]$raw.body }
  return [pscustomobject]@{ code=$code; message=(($message -replace '\s+', ' ').Trim()) }
}
function TaskSnapshot($taskId, $token) {
  if (-not $taskId) { return $null }
  $raw = Rpc 'get_task_secure' @{p_task_id=$taskId} $token
  $row = Row $raw
  return [pscustomobject]@{ raw=$raw; row=$row }
}
function Diagnostic($operation, $identity, $rpcName, $raw, $before=$null, $after=$null) {
  $details = ResponseDetails $raw
  $beforeState = if ($before -and $before.row) { "status=$($before.row.status),work_state=$($before.row.work_state),dependency_blocked=$($before.row.dependency_blocked)" } else { 'unavailable' }
  $afterState = if ($after -and $after.row) { "status=$($after.row.status),work_state=$($after.row.work_state),dependency_blocked=$($after.row.dependency_blocked)" } else { 'unavailable' }
  Write-Output "phase_b_diagnostic=operation:$operation;identity:$identity;rpc:$rpcName;http_status:$($raw.status);pg_code:$($details.code);message:$($details.message);before:$beforeState;after:$afterState"
}

$keys = Invoke-SupabaseCliJson @('projects','api-keys','--project-ref',$TargetRef,'--reveal','--output','json')
$serviceKey = ($keys | Where-Object name -eq service_role | Select-Object -First 1).api_key
$anonKey = ($keys | Where-Object name -eq anon | Select-Object -First 1).api_key
if ([string]::IsNullOrWhiteSpace($serviceKey) -or [string]::IsNullOrWhiteSpace($anonKey)) { throw 'Staging API keys unavailable.' }
$serviceHeaders = Headers $serviceKey
$profiles = @{}; $tokens = @{}; $passwords = @{}; $results = [ordered]@{}
$taskIds = New-Object System.Collections.Generic.List[string]
$dependencyIds = New-Object System.Collections.Generic.List[string]
$marker = "PRODUCTIVITY PHASE B SECURITY TEST $([guid]::NewGuid())"
$cleanupFailed = $false

try {
  $profileUrl = "$base/rest/v1/profiles?employee_id=in.(TEST-MANAGER,TEST-EMPLOYEE,TEST-OUTSIDER)&select=id,employee_id,role,is_active"
  foreach ($profile in @(Json (Raw GET $profileUrl $serviceHeaders))) { $profiles[[string]$profile.employee_id] = $profile }
  $authUsers = (Json (Raw GET "$base/auth/v1/admin/users?per_page=100" $serviceHeaders)).users
  foreach ($employeeId in @('TEST-MANAGER','TEST-EMPLOYEE','TEST-OUTSIDER')) {
    $profile = $profiles[$employeeId]; $user = @($authUsers | Where-Object id -eq $profile.id | Select-Object -First 1)
    if (-not $profile -or -not $user) { throw "Missing staging identity for $employeeId" }
    $passwords[$employeeId] = New-Password
    $reset = Raw PUT "$base/auth/v1/admin/users/$($profile.id)" $serviceHeaders @{password=$passwords[$employeeId];email_confirm=$true}
    if ($reset.status -notin 200..299) { throw "Unable to prepare $employeeId" }
    $session = SignIn $user.email $passwords[$employeeId]
    if (-not $session.access_token) { throw "Unable to authenticate $employeeId" }
    $tokens[$employeeId] = $session.access_token
  }
  Mark identities_ready ($profiles.Count -eq 3 -and $profiles['TEST-MANAGER'].role -eq 'MANAGER' -and $profiles['TEST-EMPLOYEE'].role -eq 'EMPLOYEE' -and $profiles['TEST-OUTSIDER'].role -eq 'EMPLOYEE')
  $managerId = $profiles['TEST-MANAGER'].id; $employeeId = $profiles['TEST-EMPLOYEE'].id; $outsiderId = $profiles['TEST-OUTSIDER'].id

  $create = Rpc 'create_task_secure' @{p_payload=@{title="$marker A";description='Temporary dependency predecessor';assignee_id=$employeeId;assignee_ids=@($employeeId);priority='high';status='todo';visibility='private'}} $tokens['TEST-MANAGER']
  $a = [string](Row $create).id; if ($a) { [void]$taskIds.Add($a) }; Mark task_a_create ($create.status -in 200..299 -and [bool]$a)
  $create = Rpc 'create_task_secure' @{p_payload=@{title="$marker B";description='Temporary dependency successor';assignee_id=$employeeId;assignee_ids=@($employeeId);priority='medium';status='todo';visibility='private'}} $tokens['TEST-MANAGER']
  $b = [string](Row $create).id; if ($b) { [void]$taskIds.Add($b) }; Mark task_b_create ($create.status -in 200..299 -and [bool]$b)
  $create = Rpc 'create_task_secure' @{p_payload=@{title="$marker C";description='Temporary multi-predecessor successor';assignee_id=$employeeId;assignee_ids=@($employeeId);priority='medium';status='todo';visibility='private'}} $tokens['TEST-MANAGER']
  $c = [string](Row $create).id; if ($c) { [void]$taskIds.Add($c) }; Mark task_c_create ($create.status -in 200..299 -and [bool]$c)
  if (-not ($a -and $b -and $c)) { throw 'Synthetic Phase B task creation failed.' }

  $depAB = Rpc 'create_task_dependency' @{p_predecessor_task_id=$a;p_successor_task_id=$b} $tokens['TEST-MANAGER']; $depABRow=Row $depAB; $depABId=[string]$depABRow.id; if($depABId){[void]$dependencyIds.Add($depABId)}; Mark dependency_create ($depAB.status -in 200..299 -and [bool]$depABId)
  $depAC = Rpc 'create_task_dependency' @{p_predecessor_task_id=$a;p_successor_task_id=$c} $tokens['TEST-MANAGER']; $depACRow=Row $depAC; $depACId=[string]$depACRow.id; if($depACId){[void]$dependencyIds.Add($depACId)}; Mark dependency_create_second ($depAC.status -in 200..299 -and [bool]$depACId)
  $depBC = Rpc 'create_task_dependency' @{p_predecessor_task_id=$b;p_successor_task_id=$c} $tokens['TEST-MANAGER']; $depBCRow=Row $depBC; $depBCId=[string]$depBCRow.id; if($depBCId){[void]$dependencyIds.Add($depBCId)}; Mark dependency_create_multi ($depBC.status -in 200..299 -and [bool]$depBCId)
  Mark self_cycle_denied (Denied (Rpc 'create_task_dependency' @{p_predecessor_task_id=$a;p_successor_task_id=$a} $tokens['TEST-MANAGER']))
  Mark duplicate_denied (Denied (Rpc 'create_task_dependency' @{p_predecessor_task_id=$a;p_successor_task_id=$b} $tokens['TEST-MANAGER']))
  Mark cycle_denied (Denied (Rpc 'create_task_dependency' @{p_predecessor_task_id=$c;p_successor_task_id=$a} $tokens['TEST-MANAGER']))
  $outsiderDependencyList = Rpc 'list_task_dependencies_secure' @{p_task_id=$b} $tokens['TEST-OUTSIDER']; $outsiderDependencyListRows=@(Json $outsiderDependencyList)
  # The secure list contract may return HTTP 200 with zero rows for an
  # unauthorized viewer. Both that and an explicit denial are safe.
  Mark outsider_dependency_list_denied ((Denied $outsiderDependencyList) -or ($outsiderDependencyList.status -in 200..299 -and $outsiderDependencyListRows.Count -eq 0))
  Diagnostic 'OUTSIDER_DEPENDENCY_LIST' 'TEST-OUTSIDER' 'list_task_dependencies_secure' $outsiderDependencyList
  $outsiderDependencyCreate = Rpc 'create_task_dependency' @{p_predecessor_task_id=$a;p_successor_task_id=$b} $tokens['TEST-OUTSIDER']; Mark outsider_dependency_create_denied (Denied $outsiderDependencyCreate); Diagnostic 'OUTSIDER_DEPENDENCY_CREATE' 'TEST-OUTSIDER' 'create_task_dependency' $outsiderDependencyCreate
  Mark outsider_direct_dependency_write_denied (Denied (Raw POST "$base/rest/v1/task_dependencies" (Headers $anonKey $tokens['TEST-OUTSIDER']) @{predecessor_task_id=$a;successor_task_id=$b}))

  $detail = Rpc 'get_task_secure' @{p_task_id=$b} $tokens['TEST-EMPLOYEE']; $detailRow=Row $detail
  Mark employee_dependency_detail ($detail.status -in 200..299 -and $detailRow.dependency_blocked -eq $true)
  $myDay = Rpc 'get_my_day' @{} $tokens['TEST-EMPLOYEE']; $myDayRows=@(Json $myDay); $bDay=@($myDayRows | Where-Object id -eq $b | Select-Object -First 1)
  Mark employee_dependency_waiting ($myDay.status -in 200..299 -and $bDay.dependency_blocked -eq $true -and $bDay.my_day_section -eq 'WAITING')
  $startBefore = TaskSnapshot $b $tokens['TEST-EMPLOYEE']; $employeeStart = Rpc 'start_task' @{p_task_id=$b} $tokens['TEST-EMPLOYEE']; $startAfter = TaskSnapshot $b $tokens['TEST-EMPLOYEE']
  Mark employee_start_blocked (Denied $employeeStart); Diagnostic 'EMPLOYEE_START_BLOCKED' 'TEST-EMPLOYEE' 'start_task' $employeeStart $startBefore $startAfter
  Mark employee_complete_blocked (Denied (Rpc 'complete_task_productivity' @{p_task_id=$b} $tokens['TEST-EMPLOYEE']))
  $outsiderTask = Rpc 'get_task_secure' @{p_task_id=$b} $tokens['TEST-OUTSIDER']; $outsiderTaskRow=Row $outsiderTask
  Mark outsider_task_dependency_idor_denied ((Denied $outsiderTask) -or ($outsiderTask.status -in 200..299 -and $null -eq $outsiderTaskRow)); Diagnostic 'OUTSIDER_TASK_IDOR' 'TEST-OUTSIDER' 'get_task_secure' $outsiderTask

  $completeA = Rpc 'complete_task_productivity' @{p_task_id=$a} $tokens['TEST-EMPLOYEE']; Mark predecessor_complete ($completeA.status -in 200..299 -and (Row $completeA).status -eq 'completed')
  $bReady = Rpc 'get_task_secure' @{p_task_id=$b} $tokens['TEST-EMPLOYEE']; $bReadyRow=Row $bReady
  Mark successor_ready_after_predecessor ($bReady.status -in 200..299 -and $bReadyRow.dependency_blocked -eq $false)
  $notifications = Rpc 'list_my_notifications' @{p_limit=100} $tokens['TEST-EMPLOYEE']; $notificationRows=@(Json $notifications)
  Mark task_ready_notification ($notifications.status -in 200..299 -and @($notificationRows | Where-Object { [string]($_.event_type) -eq 'task_ready' -or [string]($_.type) -eq 'task_ready' -or [string]($_.message) -match [regex]::Escape("$marker B") }).Count -gt 0)
  # Verify A+B -> C while only A is complete, before completing B.
  $cAfterA = Rpc 'get_task_secure' @{p_task_id=$c} $tokens['TEST-EMPLOYEE']; $cAfterARow=Row $cAfterA
  Mark multi_predecessor_still_blocked ($cAfterA.status -in 200..299 -and $cAfterARow.dependency_blocked -eq $true); Diagnostic 'MULTI_PREDECESSOR_AFTER_A' 'TEST-EMPLOYEE' 'get_task_secure' $cAfterA
  $completeCBlocked = Rpc 'complete_task_productivity' @{p_task_id=$c} $tokens['TEST-EMPLOYEE']; Mark multi_predecessor_requires_all (Denied $completeCBlocked); Diagnostic 'MULTI_PREDECESSOR_COMPLETE_AFTER_A' 'TEST-EMPLOYEE' 'complete_task_productivity' $completeCBlocked
  $completeB = Rpc 'complete_and_hand_off_task' @{p_task_id=$b} $tokens['TEST-EMPLOYEE']; Mark handoff_complete ($completeB.status -in 200..299 -and (Row $completeB).handoff -eq $true)
  $cReady = Rpc 'get_task_secure' @{p_task_id=$c} $tokens['TEST-EMPLOYEE']; Mark successor_ready_after_all_predecessors ($cReady.status -in 200..299 -and (Row $cReady).dependency_blocked -eq $false); Diagnostic 'MULTI_PREDECESSOR_AFTER_B' 'TEST-EMPLOYEE' 'get_task_secure' $cReady
  $history = Rpc 'list_task_dependency_history_secure' @{p_task_id=$b} $tokens['TEST-EMPLOYEE']; Mark dependency_history ($history.status -in 200..299 -and @((Json $history)).Count -gt 0)
  $directDependencyRead = Raw GET "$base/rest/v1/task_dependencies?successor_task_id=eq.$b" (Headers $anonKey $tokens['TEST-OUTSIDER']); $directDependencyRows=@(Json $directDependencyRead)
  Mark direct_dependency_select_denied ((Denied $directDependencyRead) -or ($directDependencyRead.status -in 200..299 -and $directDependencyRows.Count -eq 0)); Diagnostic 'OUTSIDER_DIRECT_DEPENDENCY_READ' 'TEST-OUTSIDER' 'rest_v1_task_dependencies_select' $directDependencyRead
  Mark handoff_free_form_denied (Denied (Raw POST "$base/rest/v1/rpc/complete_and_hand_off_task" (Headers $anonKey $tokens['TEST-EMPLOYEE']) @{p_task_id=$c;p_next_assignee_id=$outsiderId}))
} finally {
  foreach ($taskId in @($taskIds)) {
    if ($taskId) {
      $cleanup = Rpc 'delete_task_secure' @{p_task_id=$taskId} $tokens['TEST-MANAGER']
      if (-not ($cleanup.status -in 200..299) -and $cleanup.status -ne 404) { $cleanupFailed=$true }
    }
  }
}

$results.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
if ($cleanupFailed) { Write-Output 'cleanup_failed=True'; exit 1 }
if (($results.Values | Where-Object { -not $_ }).Count -gt 0) { exit 1 }
Write-Output "PRODUCTIVITY PHASE B READINESS: PASS ($TargetRef)"
