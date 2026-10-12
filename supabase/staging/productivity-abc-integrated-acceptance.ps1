$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'

# Integrated Phase A+B+C acceptance gate. This script is intentionally local-run
# only: it uses the authenticated Supabase CLI and disposable staging records.
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$refPath = Join-Path $PSScriptRoot '..\.temp\project-ref'
if (-not (Test-Path -LiteralPath $refPath)) { throw 'ABORTED: missing linked Supabase project reference.' }
$linkedRef = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linkedRef -cne $TargetRef -or $linkedRef -ceq $ProductionRef) {
  throw "ABORTED: linked project is '$linkedRef', not staging '$TargetRef'."
}

function Invoke-NativeJson([string]$FilePath, [string[]]$Arguments) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.Arguments = (($Arguments | ForEach-Object { '"' + ([string]$_).Replace('"', '\"') + '"' }) -join ' ')
  $process = New-Object System.Diagnostics.Process; $process.StartInfo = $psi
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) { throw "Supabase CLI failed with exit code $($process.ExitCode)." }
  # CLI update notices are harmless when the process succeeded. Parse only the
  # JSON portion of stdout and never echo stdout/stderr (it may contain keys).
  $jsonText = $stdout.Trim()
  $firstObject = $jsonText.IndexOf('{'); $firstArray = $jsonText.IndexOf('[')
  $start = if ($firstObject -ge 0 -and ($firstArray -lt 0 -or $firstObject -lt $firstArray)) { $firstObject } else { $firstArray }
  if ($start -gt 0) { $jsonText = $jsonText.Substring($start) }
  if ([string]::IsNullOrWhiteSpace($jsonText)) { throw 'Supabase CLI returned no JSON.' }
  try { return ($jsonText | ConvertFrom-Json) } catch { throw 'Supabase CLI returned invalid JSON.' }
}

function New-Headers([string]$ApiKey, [string]$Token = $null, [switch]$Service) {
  $bearer = if ($Service -or [string]::IsNullOrWhiteSpace($Token)) { $ApiKey } else { $Token }
  return @{ apikey = $ApiKey; Authorization = "Bearer $bearer"; 'Content-Type' = 'application/json'; Prefer = 'return=representation' }
}
function New-ApiUrl([string]$BaseUrl, [string]$Path, [string]$Query = $null) {
  if ([string]::IsNullOrWhiteSpace($Query)) { return ($BaseUrl + $Path) }
  return ($BaseUrl + $Path + '?' + $Query)
}
function Invoke-Rest([string]$Method, [string]$Url, [hashtable]$Headers, $Body = $null) {
  $script:LastHttpError = $null
  try {
    $p = @{ Method = $Method; Uri = $Url; Headers = $Headers; UseBasicParsing = $true; ErrorAction = 'Stop' }
    if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Depth 40 -Compress) }
    $r = Invoke-WebRequest @p
    $parsed = $null
    if (-not [string]::IsNullOrWhiteSpace($r.Content)) { try { $parsed = $r.Content | ConvertFrom-Json } catch { $parsed = $r.Content } }
    return [pscustomobject]@{ status = [int]$r.StatusCode; body = $r.Content; json = $parsed }
  } catch {
    $status = $null; $content = $null
    if ($_.Exception.Response) {
      try { $status = [int]$_.Exception.Response.StatusCode } catch {}
      try { $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); $content = $reader.ReadToEnd(); $reader.Dispose() } catch {}
    }
    $parsed = $null
    if (-not [string]::IsNullOrWhiteSpace($content)) { try { $parsed = $content | ConvertFrom-Json } catch { $parsed = $content } }
    $message = if ($parsed -and $parsed.message) { [string]$parsed.message } elseif ($parsed -and $parsed.error_description) { [string]$parsed.error_description } else { $_.Exception.Message }
    $code = if ($parsed -and $parsed.code) { [string]$parsed.code } else { $null }
    $script:LastHttpError = [pscustomobject]@{ method = $Method; url = $Url; status = $status; body = $parsed; code = $code; message = (($message -replace '\s+', ' ').Trim()) }
    return [pscustomobject]@{ status = if ($status) { [int]$status } else { 0 }; body = $content; json = $parsed }
  }
}
function Invoke-Rpc([string]$Name, $Payload, [string]$Token, [string]$AnonKey, [string]$BaseUrl) {
  return Invoke-Rest 'POST' (New-ApiUrl $BaseUrl ("/rest/v1/rpc/$Name")) (New-Headers $AnonKey $Token) $Payload
}
function Get-ErrorText($Raw) {
  if ($script:LastHttpError -and $script:LastHttpError.message) { return "code=$($script:LastHttpError.code);message=$($script:LastHttpError.message)" }
  if ($Raw -and $Raw.json -and $Raw.json.message) { return "code=$($Raw.json.code);message=$($Raw.json.message)" }
  return 'no response details'
}
function Require-Success([string]$Step, [string]$Identity, [string]$RpcName, $Raw) {
  if ($null -eq $Raw -or $Raw.status -notin (200..299)) {
    $status = if ($Raw) { $Raw.status } else { 0 }
    throw "INTEGRATED_GATE_FAILURE step=$Step;identity=$Identity;rpc=$RpcName;http_status=$status;$(Get-ErrorText $Raw)"
  }
  return $Raw.json
}
function Diagnostic([string]$Step, [string]$Identity, [string]$RpcName, $Raw, [string]$Expected, [string]$Actual) {
  $status = if ($Raw) { $Raw.status } else { 0 }
  $detail = Get-ErrorText $Raw
  Write-Output "abc_diagnostic=step:$Step;identity:$Identity;rpc:$RpcName;http_status:$status;detail:$detail;expected:$Expected;actual:$Actual"
}
function Is-DeniedOrEmpty($Raw) {
  if ($null -eq $Raw) { return $true }
  if ($Raw.status -in (400,401,403,404,409,422)) { return $true }
  if ($Raw.status -notin (200..299)) { return $false }
  if ($null -eq $Raw.json) { return $true }
  if ($Raw.json -is [System.Array]) { return ($Raw.json.Count -eq 0) }
  return $false
}
function New-RandomPassword {
  $bytes = New-Object byte[] 24; $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  return ([Convert]::ToBase64String($bytes) + 'Aa9!')
}
function Sign-In([string]$Email, [string]$Password, [string]$AnonKey, [string]$BaseUrl) {
  $raw = Invoke-Rest 'POST' (New-ApiUrl $BaseUrl '/auth/v1/token' 'grant_type=password') (New-Headers $AnonKey) @{ email = $Email; password = $Password }
  if ($raw.status -notin (200..299) -or -not $raw.json.access_token) { throw 'Unable to authenticate a staging test identity.' }
  return [string]$raw.json.access_token
}
function Add-Result([hashtable]$Results, [string]$Name, [bool]$Value) { $Results[$Name] = $Value }
function Get-List($Value) { if ($null -eq $Value) { return @() }; if ($Value -is [System.Array]) { return @($Value) }; return @($Value) }
function Run-LocalRegression([string]$FilePath, [string[]]$Arguments) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = (Split-Path -Parent $PSScriptRoot | Split-Path -Parent)
  $psi.Arguments = (($Arguments | ForEach-Object { '"' + ([string]$_).Replace('"', '\"') + '"' }) -join ' ')
  $p = New-Object System.Diagnostics.Process; $p.StartInfo = $psi; [void]$p.Start(); $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "Regression command failed: $FilePath $($Arguments -join ' ')" }
}

$base = "https://$TargetRef.supabase.co"
$amp = [char]38
$results = [ordered]@{ staging_target = ($linkedRef -ceq $TargetRef) }
$serviceKey = $anonKey = $null; $tokens = @{}; $passwords = @{}; $users = @{}
$projectId = $taskA = $taskB = $taskC = $taskD = $depAB = $depBC = $depCD = $null
$marker = "INTEGRATED ABC ACCEPTANCE $([guid]::NewGuid())"
$notificationIds = New-Object System.Collections.Generic.List[string]
$cleanupFailed = $false
$gateFailure = $null

try {
  $keys = Invoke-NativeJson 'supabase' @('projects','api-keys','--project-ref',$TargetRef,'--reveal','--output','json')
  $serviceKey = [string](($keys | Where-Object { $_.name -eq 'service_role' } | Select-Object -First 1).api_key)
  $anonKey = [string](($keys | Where-Object { $_.name -eq 'anon' } | Select-Object -First 1).api_key)
  if ([string]::IsNullOrWhiteSpace($serviceKey) -or [string]::IsNullOrWhiteSpace($anonKey)) { throw 'Staging API keys are unavailable.' }
  $adminHeaders = New-Headers $serviceKey -Service

  $profileQuery = 'employee_id=in.(TEST-MANAGER,TEST-EMPLOYEE,TEST-OUTSIDER)' + $amp + 'select=id,employee_id,role,is_active'
  $profileRaw = Invoke-Rest GET (New-ApiUrl $base '/rest/v1/profiles' $profileQuery) $adminHeaders
  if ($profileRaw.status -notin (200..299)) { throw 'Unable to read staging test profiles.' }
  $profiles = Get-List $profileRaw.json
  $authRaw = Invoke-Rest GET (New-ApiUrl $base '/auth/v1/admin/users' 'per_page=100') $adminHeaders
  if ($authRaw.status -notin (200..299)) { throw 'Unable to read staging Auth users.' }
  $authUsers = Get-List $authRaw.json.users
  foreach ($kind in @('manager','employee','outsider')) {
    $key = 'TEST-' + $kind.ToUpper(); $profile = @($profiles | Where-Object { $_.employee_id -eq $key } | Select-Object -First 1)
    $auth = @($authUsers | Where-Object { $_.id -eq $profile.id } | Select-Object -First 1)
    if (-not $profile -or -not $profile.is_active -or -not $auth -or [string]::IsNullOrWhiteSpace($auth.email)) { throw "Missing active staging identity $key or Auth/profile UUID mismatch." }
    $users[$kind] = $auth; $passwords[$kind] = New-RandomPassword
    $reset = Invoke-Rest PUT (New-ApiUrl $base ("/auth/v1/admin/users/$($auth.id)")) $adminHeaders @{ password = $passwords[$kind]; email_confirm = $true }
    if ($reset.status -notin (200..299)) { throw "Unable to prepare staging identity $key." }
  }
  foreach ($kind in @('manager','employee','outsider')) { $tokens[$kind] = Sign-In $users[$kind].email $passwords[$kind] $anonKey $base }
  Add-Result $results 'identities_ready' ($tokens.Count -eq 3)

  $eventDate = (Get-Date).Date.AddDays(5).ToString('yyyy-MM-dd')
  $projectPayload = @{ project_name = "$marker - EVENT PROJECT"; project_type = 'EVENT'; description = 'Temporary integrated Phase A+B+C acceptance record'; assigned_people = @($users.employee.id); project_manager_id = $users.manager.id; lifecycle_status = 'ACTIVE'; health_status = 'ON_TRACK'; priority = 'HIGH'; progress_percent = 0; start_date = (Get-Date).Date.ToString('yyyy-MM-dd'); end_date = $eventDate; client_name = 'Synthetic acceptance client'; budget_amount = 5000; actual_cost = 1000 }
  $projectRaw = Invoke-Rpc 'create_project_secure' @{ p_project = $projectPayload } $tokens.manager $anonKey $base
  $project = Require-Success 'PROJECT_CREATE' 'TEST-MANAGER' 'create_project_secure' $projectRaw; $projectId = [string]$project.id
  $updateProjectRaw = Invoke-Rpc 'update_project_secure' @{ p_project_id = $projectId; p_changes = @{ event_date = $eventDate; end_date = $eventDate } } $tokens.manager $anonKey $base
  Require-Success 'PROJECT_EVENT_DATE' 'TEST-MANAGER' 'update_project_secure' $updateProjectRaw | Out-Null
  Add-Result $results 'project_created' (-not [string]::IsNullOrWhiteSpace($projectId))
  $managerDetailRaw = Invoke-Rpc 'get_project_detail_secure' @{ p_project_id = $projectId } $tokens.manager $anonKey $base
  $employeeDetailRaw = Invoke-Rpc 'get_project_detail_secure' @{ p_project_id = $projectId } $tokens.employee $anonKey $base
  $outsiderDetailRaw = Invoke-Rpc 'get_project_detail_secure' @{ p_project_id = $projectId } $tokens.outsider $anonKey $base
  Add-Result $results 'manager_project_access' ($managerDetailRaw.status -in (200..299) -and $null -ne $managerDetailRaw.json)
  Add-Result $results 'employee_project_access' ($employeeDetailRaw.status -in (200..299) -and $null -ne $employeeDetailRaw.json)
  Add-Result $results 'outsider_project_idor_denied' (Is-DeniedOrEmpty $outsiderDetailRaw)
  Diagnostic 'PROJECT_ACCESS' 'TEST-OUTSIDER' 'get_project_detail_secure' $outsiderDetailRaw 'denied or empty' 'sanitized'

  $due = (Get-Date).Date.AddDays(2).ToString('yyyy-MM-dd')
  function Create-IntegratedTask([string]$Title, [string]$Priority) {
    $payload = @{ title = $Title; description = 'Temporary integrated acceptance task'; project_id = $projectId; assignee_id = $users.employee.id; assignee_ids = @($users.employee.id); priority = $Priority; category = 'General'; status = 'todo'; visibility = 'private'; due_date = $due }
    return Invoke-Rpc 'create_task_secure' @{ p_payload = $payload } $tokens.manager $anonKey $base
  }
  $taskATitle = "$marker - A - Client Approval"; $taskARaw = Create-IntegratedTask $taskATitle 'high'; $taskAJson = Require-Success 'TASK_A_CREATE' 'TEST-MANAGER' 'create_task_secure' $taskARaw; $taskA = [string]$taskAJson.id
  $taskBTitle = "$marker - B - Prepare Final Artwork"; $taskBRaw = Create-IntegratedTask $taskBTitle 'high'; $taskBJson = Require-Success 'TASK_B_CREATE' 'TEST-MANAGER' 'create_task_secure' $taskBRaw; $taskB = [string]$taskBJson.id
  $taskCTitle = "$marker - C - Send to Production"; $taskCRaw = Create-IntegratedTask $taskCTitle 'medium'; $taskCJson = Require-Success 'TASK_C_CREATE' 'TEST-MANAGER' 'create_task_secure' $taskCRaw; $taskC = [string]$taskCJson.id
  $taskDTitle = "$marker - D - Installation"; $taskDRaw = Create-IntegratedTask $taskDTitle 'medium'; $taskDJson = Require-Success 'TASK_D_CREATE' 'TEST-MANAGER' 'create_task_secure' $taskDRaw; $taskD = [string]$taskDJson.id
  Add-Result $results 'tasks_created' ($taskA -and $taskB -and $taskC -and $taskD)

  $depABRaw = Invoke-Rpc 'create_task_dependency' @{ p_predecessor_task_id = $taskA; p_successor_task_id = $taskB } $tokens.manager $anonKey $base; $depAB = [string](Require-Success 'DEPENDENCY_A_B' 'TEST-MANAGER' 'create_task_dependency' $depABRaw).id
  $depBCRaw = Invoke-Rpc 'create_task_dependency' @{ p_predecessor_task_id = $taskB; p_successor_task_id = $taskC } $tokens.manager $anonKey $base; $depBC = [string](Require-Success 'DEPENDENCY_B_C' 'TEST-MANAGER' 'create_task_dependency' $depBCRaw).id
  $depCDRaw = Invoke-Rpc 'create_task_dependency' @{ p_predecessor_task_id = $taskC; p_successor_task_id = $taskD } $tokens.manager $anonKey $base; $depCD = [string](Require-Success 'DEPENDENCY_C_D' 'TEST-MANAGER' 'create_task_dependency' $depCDRaw).id
  Add-Result $results 'dependencies_created' ($depAB -and $depBC -and $depCD)

  $myDayRaw = Invoke-Rpc 'get_my_day' @{} $tokens.employee $anonKey $base; $myDay = Get-List $myDayRaw.json
  $myA = @($myDay | Where-Object { $_.id -eq $taskA } | Select-Object -First 1); $myB = @($myDay | Where-Object { $_.id -eq $taskB } | Select-Object -First 1)
  Add-Result $results 'employee_my_day' ($myDayRaw.status -in (200..299) -and $myA.Count -eq 1 -and $myB.Count -eq 1 -and [bool]$myB[0].dependency_blocked)
  $directTaskRead = Invoke-Rest GET (New-ApiUrl $base '/rest/v1/tasks' ('id=eq.' + $taskA)) (New-Headers $anonKey $tokens.employee)
  Add-Result $results 'employee_direct_task_read_denied' (Is-DeniedOrEmpty $directTaskRead)

  $startARaw = Invoke-Rpc 'start_task' @{ p_task_id = $taskA } $tokens.employee $anonKey $base; $startA = Require-Success 'START_A' 'TEST-EMPLOYEE' 'start_task' $startARaw
  $aAfterStart = (Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskA } $tokens.employee $anonKey $base).json
  Add-Result $results 'start_a' ([string]$startA.status -eq 'in_progress' -and [bool]$startA.changed -and $startA.started_at -and [string]$aAfterStart.status -eq 'in_progress')
  $outsiderStartRaw = Invoke-Rpc 'start_task' @{ p_task_id = $taskA } $tokens.outsider $anonKey $base
  Add-Result $results 'outsider_start_denied' (Is-DeniedOrEmpty $outsiderStartRaw)

  $waitingRaw = Invoke-Rpc 'mark_task_waiting' @{ p_task_id = $taskA; p_category = 'CLIENT'; p_related_user_id = $null; p_note = 'Waiting for client approval' } $tokens.employee $anonKey $base
  Require-Success 'WAITING_A' 'TEST-EMPLOYEE' 'mark_task_waiting' $waitingRaw | Out-Null
  $waitingState = (Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskA } $tokens.employee $anonKey $base).json
  $managerStates = Invoke-Rpc 'list_task_work_states_secure' @{} $tokens.manager $anonKey $base
  $ccWaiting = Invoke-Rpc 'get_project_health' @{ p_project_id = $projectId } $tokens.manager $anonKey $base
  Add-Result $results 'waiting_a' ([string]$waitingState.work_state -eq 'WAITING' -and [string]$waitingState.waiting_note -eq 'Waiting for client approval')
  Add-Result $results 'manager_waiting_visibility' ($managerStates.status -in (200..299) -and (Get-List $managerStates.json | Where-Object { $_.task_id -eq $taskA }).Count -gt 0)
  Add-Result $results 'command_center_waiting' ($ccWaiting.status -in (200..299) -and [int]$ccWaiting.json.counts.waiting_tasks -ge 1)

  Require-Success 'RESUME_A' 'TEST-EMPLOYEE' 'resume_task' (Invoke-Rpc 'resume_task' @{ p_task_id = $taskA } $tokens.employee $anonKey $base) | Out-Null
  $resumeState = (Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskA } $tokens.employee $anonKey $base).json
  Add-Result $results 'resume_a' ([string]$resumeState.work_state -eq 'ACTIVE' -and $null -eq $resumeState.waiting_since)

  Require-Success 'BLOCK_A' 'TEST-EMPLOYEE' 'mark_task_blocked' (Invoke-Rpc 'mark_task_blocked' @{ p_task_id = $taskA; p_category = 'CLIENT'; p_related_user_id = $null; p_note = 'Client requested artwork revision' } $tokens.employee $anonKey $base) | Out-Null
  $blockedState = (Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskA } $tokens.employee $anonKey $base).json
  $ccBlocked = Invoke-Rpc 'get_project_health' @{ p_project_id = $projectId } $tokens.manager $anonKey $base
  Add-Result $results 'blocked_a' ([string]$blockedState.work_state -eq 'BLOCKED' -and [string]$blockedState.blocked_note -eq 'Client requested artwork revision')
  Add-Result $results 'command_center_blocked' ($ccBlocked.status -in (200..299) -and [int]$ccBlocked.json.counts.blocked_tasks -ge 1)
  $commandCenter = Invoke-Rpc 'list_project_command_center' @{ p_limit = 100; p_only_attention = $false; p_upcoming_days = $null } $tokens.manager $anonKey $base
  $attention = Invoke-Rpc 'list_attention_needed' @{ p_limit = 100 } $tokens.manager $anonKey $base
  $upcoming = Invoke-Rpc 'list_upcoming_events' @{ p_days = 30; p_limit = 100 } $tokens.manager $anonKey $base
  Add-Result $results 'command_center_aggregate' ($commandCenter.status -in (200..299) -and (Get-List $commandCenter.json | Where-Object { $_.project_id -eq $projectId }).Count -eq 1)
  Add-Result $results 'attention_needed' ($attention.status -in (200..299) -and (Get-List $attention.json | Where-Object { $_.project_id -eq $projectId }).Count -eq 1)
  Add-Result $results 'event_countdown' ($upcoming.status -in (200..299) -and (Get-List $upcoming.json | Where-Object { $_.project_id -eq $projectId -and $_.event_date -eq $eventDate }).Count -eq 1)
  $appText = Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'js/app.js')
  $commandCenterSection = [regex]::Match($appText, 'async function renderProjectCommandCenter\([\s\S]*?window\.openProjectCommandProject')
  Add-Result $results 'aggregate_contract' ($commandCenterSection.Success -and $commandCenterSection.Value -match 'fetchProjectCommandCenter' -and $commandCenterSection.Value -notmatch 'fetchTasks\(|fetchProjects\(')
  Require-Success 'UNBLOCK_A' 'TEST-EMPLOYEE' 'resume_task' (Invoke-Rpc 'resume_task' @{ p_task_id = $taskA } $tokens.employee $anonKey $base) | Out-Null
  $unblockedState = (Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskA } $tokens.employee $anonKey $base).json
  Add-Result $results 'unblock_a' ([string]$unblockedState.work_state -eq 'ACTIVE' -and $null -eq $unblockedState.blocked_since)

  $detailB = Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskB } $tokens.employee $anonKey $base
  $depsB = Invoke-Rpc 'list_task_dependencies_secure' @{ p_task_id = $taskB } $tokens.employee $anonKey $base
  $bBlocked = $detailB.json
  Add-Result $results 'dependency_blocked_b' ($detailB.status -in (200..299) -and [bool]$bBlocked.dependency_blocked -and (Get-List $depsB.json | Where-Object { $_.relationship -eq 'depends_on' -and $_.predecessor_task_id -eq $taskA }).Count -gt 0)
  $startBRaw = Invoke-Rpc 'start_task' @{ p_task_id = $taskB } $tokens.employee $anonKey $base
  $completeBRaw = Invoke-Rpc 'complete_task_productivity' @{ p_task_id = $taskB } $tokens.employee $anonKey $base
  Add-Result $results 'dependency_workflow_denied' ((Is-DeniedOrEmpty $startBRaw) -and (Is-DeniedOrEmpty $completeBRaw))
  $outsiderDeps = Invoke-Rpc 'list_task_dependencies_secure' @{ p_task_id = $taskB } $tokens.outsider $anonKey $base
  Add-Result $results 'outsider_dependency_idor_denied' (Is-DeniedOrEmpty $outsiderDeps)

  $notificationBefore = Get-List ((Invoke-Rpc 'list_my_notifications' @{ p_limit = 100 } $tokens.employee $anonKey $base).json)
  $handoffA = Require-Success 'HANDOFF_A_B' 'TEST-EMPLOYEE' 'complete_and_hand_off_task' (Invoke-Rpc 'complete_and_hand_off_task' @{ p_task_id = $taskA } $tokens.employee $anonKey $base)
  $bReady = (Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskB } $tokens.employee $anonKey $base).json
  $notificationAfter = Get-List ((Invoke-Rpc 'list_my_notifications' @{ p_limit = 100 } $tokens.employee $anonKey $base).json)
  $newNotices = @($notificationAfter | Where-Object { $_.id -notin @($notificationBefore | ForEach-Object { $_.id }) -and (([string]$_.message) -match [regex]::Escape($taskBTitle) -or [string]$_.event_type -eq 'task_ready') })
  foreach ($notice in $newNotices) { if ($notice.id) { [void]$notificationIds.Add([string]$notice.id) } }
  Add-Result $results 'handoff_a_b' ([bool]$handoffA.handoff -and [string]$handoffA.status -eq 'completed' -and [bool]$bReady -and -not [bool]$bReady.dependency_blocked)
  Add-Result $results 'successor_notification' ($newNotices.Count -gt 0)

  Require-Success 'START_B' 'TEST-EMPLOYEE' 'start_task' (Invoke-Rpc 'start_task' @{ p_task_id = $taskB } $tokens.employee $anonKey $base) | Out-Null
  Require-Success 'HANDOFF_B_C' 'TEST-EMPLOYEE' 'complete_and_hand_off_task' (Invoke-Rpc 'complete_and_hand_off_task' @{ p_task_id = $taskB } $tokens.employee $anonKey $base) | Out-Null
  $cReady = (Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskC } $tokens.employee $anonKey $base).json
  Add-Result $results 'successor_b_c_ready' ($cReady -and -not [bool]$cReady.dependency_blocked)
  Require-Success 'START_C' 'TEST-EMPLOYEE' 'start_task' (Invoke-Rpc 'start_task' @{ p_task_id = $taskC } $tokens.employee $anonKey $base) | Out-Null
  Require-Success 'HANDOFF_C_D' 'TEST-EMPLOYEE' 'complete_and_hand_off_task' (Invoke-Rpc 'complete_and_hand_off_task' @{ p_task_id = $taskC } $tokens.employee $anonKey $base) | Out-Null
  $dReady = (Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskD } $tokens.employee $anonKey $base).json
  Add-Result $results 'successor_c_d_ready' ($dReady -and -not [bool]$dReady.dependency_blocked)
  Require-Success 'START_D' 'TEST-EMPLOYEE' 'start_task' (Invoke-Rpc 'start_task' @{ p_task_id = $taskD } $tokens.employee $anonKey $base) | Out-Null
  Require-Success 'COMPLETE_D' 'TEST-EMPLOYEE' 'complete_task_productivity' (Invoke-Rpc 'complete_task_productivity' @{ p_task_id = $taskD } $tokens.employee $anonKey $base) | Out-Null
  $chainIds = @($taskA, $taskB, $taskC, $taskD)
  $completedStates = @($chainIds | ForEach-Object { (Invoke-Rpc 'get_task_secure' @{ p_task_id = $_ } $tokens.employee $anonKey $base).json } | Where-Object { $_.status -eq 'completed' })
  Add-Result $results 'chain_completed' ($completedStates.Count -eq 4)

  $healthAfter = Invoke-Rpc 'get_project_health' @{ p_project_id = $projectId } $tokens.manager $anonKey $base
  $summary = Invoke-Rpc 'get_project_operational_summary' @{ p_project_id = $projectId } $tokens.manager $anonKey $base
  $completedToday = Invoke-Rpc 'get_my_completed_today' @{} $tokens.employee $anonKey $base
  $activityA = Invoke-Rpc 'list_task_activity_secure' @{ p_task_id = $taskA } $tokens.employee $anonKey $base
  $workHistoryA = Invoke-Rpc 'list_task_work_history_secure' @{ p_task_id = $taskA } $tokens.employee $anonKey $base
  $depHistoryB = Invoke-Rpc 'list_task_dependency_history_secure' @{ p_task_id = $taskB } $tokens.employee $anonKey $base
  $actions = Get-List $activityA.json | ForEach-Object { [string]$_.action }
  $workTypes = Get-List $workHistoryA.json | ForEach-Object { [string]$_.history_type }
  $depActions = Get-List $depHistoryB.json | ForEach-Object { [string]$_.action }
  Add-Result $results 'project_health_recalculated' ($ccBlocked.status -in (200..299) -and $healthAfter.status -in (200..299) -and [int]$healthAfter.json.counts.blocked_tasks -eq 0 -and [int]$healthAfter.json.counts.waiting_tasks -eq 0)
  Add-Result $results 'operational_summary_final' ($summary.status -in (200..299) -and [int]$summary.json.counts.blocked_tasks -eq 0 -and [int]$summary.json.counts.waiting_tasks -eq 0 -and [int]$summary.json.counts.dependency_blocked_tasks -eq 0)
  $completedTodayIds = Get-List $completedToday.json | ForEach-Object { [string]$_.id }
  Add-Result $results 'completed_today' ($completedToday.status -in (200..299) -and @($chainIds | Where-Object { $_ -in $completedTodayIds }).Count -eq 4)
  $missingActivity = @(@('TASK_STARTED','TASK_WAITING','TASK_RESUMED','TASK_BLOCKED','TASK_COMPLETED') | Where-Object { $_ -notin $actions }).Count
  $dependencyActivityCount = @(@('TASK_HANDOFF','TASK_DEPENDENCY_READY') | Where-Object { $_ -in $depActions }).Count
  Add-Result $results 'activity_history' ($missingActivity -eq 0 -and @('WAITING','BLOCKED' | Where-Object { $_ -in $workTypes }).Count -eq 2 -and $dependencyActivityCount -ge 1)
  Add-Result $results 'financial_redaction' ((($employeeDetailRaw.json.project.budget_amount -eq $null) -and ($employeeDetailRaw.json.project.actual_cost -eq $null)) -and (($summary.json | ConvertTo-Json -Depth 30 -Compress) -notmatch '"(budget_amount|actual_cost|project_amount|paid_amount)"\s*:\s*[0-9]'))

  $outsiderTask = Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskA } $tokens.outsider $anonKey $base
  $outsiderHealth = Invoke-Rpc 'get_project_health' @{ p_project_id = $projectId } $tokens.outsider $anonKey $base
  $outsiderSummary = Invoke-Rpc 'get_project_operational_summary' @{ p_project_id = $projectId } $tokens.outsider $anonKey $base
  $outsiderNotification = Invoke-Rpc 'list_my_notifications' @{ p_limit = 100 } $tokens.outsider $anonKey $base
  $outsiderActivity = Invoke-Rpc 'list_task_activity_secure' @{ p_task_id = $taskA } $tokens.outsider $anonKey $base
  $employeeCommandCenter = Invoke-Rpc 'list_project_command_center' @{ p_limit = 100; p_only_attention = $false; p_upcoming_days = $null } $tokens.employee $anonKey $base
  $outsiderCommandCenter = Invoke-Rpc 'list_project_command_center' @{ p_limit = 100; p_only_attention = $false; p_upcoming_days = $null } $tokens.outsider $anonKey $base
  Add-Result $results 'outsider_cross_module_idor_denied' ((Is-DeniedOrEmpty $outsiderTask) -and (Is-DeniedOrEmpty $outsiderHealth) -and (Is-DeniedOrEmpty $outsiderSummary) -and (($outsiderNotification.status -in (200..299) -and (Get-List $outsiderNotification.json).Count -eq 0) -or (Is-DeniedOrEmpty $outsiderNotification)))
  Add-Result $results 'history_idor_denied' (Is-DeniedOrEmpty $outsiderActivity)
  Add-Result $results 'manager_scope_idor_denied' ((Is-DeniedOrEmpty $employeeCommandCenter) -and (Is-DeniedOrEmpty $outsiderCommandCenter))
  $employeePatch = Invoke-Rpc 'update_task_secure' @{ p_task_id = $taskA; p_patch = @{ assignee_id = $users.outsider.id; assignee_ids = @($users.outsider.id) } } $tokens.employee $anonKey $base
  $employeeDirectPatch = Invoke-Rest PATCH (New-ApiUrl $base '/rest/v1/tasks' ('id=eq.' + $taskA)) (New-Headers $anonKey $tokens.employee) @{ assignee_id = $users.outsider.id }
  $employeeProjectPatch = Invoke-Rest PATCH (New-ApiUrl $base '/rest/v1/projects' ('id=eq.' + $projectId)) (New-Headers $anonKey $tokens.employee) @{ health_status = 'CRITICAL' }
  $employeeHealthPatch = Invoke-Rpc 'update_project_secure' @{ p_project_id = $projectId; p_changes = @{ health_status = 'CRITICAL' } } $tokens.employee $anonKey $base
  $employeeDependencyCreate = Invoke-Rpc 'create_task_dependency' @{ p_predecessor_task_id = $taskB; p_successor_task_id = $taskD } $tokens.employee $anonKey $base
  $outsiderDependencyWrite = Invoke-Rest POST (New-ApiUrl $base '/rest/v1/task_dependencies') (New-Headers $anonKey $tokens.outsider) @{ predecessor_task_id = $taskA; successor_task_id = $taskD }
  $employeePatchAfter = (Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskA } $tokens.employee $anonKey $base).json
  $ownershipStillIntact = ($employeePatchAfter.assignee_id -eq $users.employee.id -and $users.outsider.id -notin @($employeePatchAfter.assignee_ids))
  $protectedPatchDenied = (Is-DeniedOrEmpty $employeePatch -or $ownershipStillIntact)
  Add-Result $results 'privilege_escalation_denied' ($protectedPatchDenied -and (Is-DeniedOrEmpty $employeeDirectPatch) -and (Is-DeniedOrEmpty $employeeProjectPatch) -and (Is-DeniedOrEmpty $employeeHealthPatch) -and (Is-DeniedOrEmpty $employeeDependencyCreate) -and (Is-DeniedOrEmpty $outsiderDependencyWrite))
  Diagnostic 'OUTSIDER_CROSS_MODULE_IDOR' 'TEST-OUTSIDER' 'get_task_secure/get_project_health/get_project_operational_summary' $outsiderTask 'denied or empty' 'sanitized'

  Run-LocalRegression 'node' @('tests/productivity-phase-a.test.cjs'); Run-LocalRegression 'node' @('tests/productivity-phase-b.test.cjs'); Run-LocalRegression 'node' @('tests/productivity-phase-c.test.cjs'); Run-LocalRegression 'node' @('tests/backend-task-readiness.test.cjs'); Run-LocalRegression 'node' @('tests/backend-project-readiness.test.cjs'); Run-LocalRegression 'node' @('tests/notification-backend-services.test.cjs'); Run-LocalRegression 'node' @('tests/phase-ab-mobile-ux.test.cjs'); Run-LocalRegression 'node' @('scripts/build-mobile.mjs')
  Add-Result $results 'regressions' $true
} catch {
  $gateFailure = $_.Exception.Message
  Add-Result $results 'workflow_execution' $false
  Write-Output ("abc_failure=message:" + (($gateFailure -replace '\s+', ' ').Trim()))
} finally {
  # Cleanup is intentionally best-effort per record, but any failure makes the
  # gate fail. Delete dependencies before tasks, then project; notifications
  # are removed through the recipient's authoritative RPC.
  try {
    foreach ($noticeId in @($notificationIds)) { $r = Invoke-Rpc 'delete_my_notification' @{ p_notification_id = $noticeId } $tokens.employee $anonKey $base; if ($r.status -notin (200..299,404)) { $cleanupFailed = $true } }
    foreach ($depId in @($depCD,$depBC,$depAB)) { if ($depId) { $r = Invoke-Rpc 'remove_task_dependency' @{ p_dependency_id = $depId } $tokens.manager $anonKey $base; if ($r.status -notin (200..299,404)) { $cleanupFailed = $true } } }
    foreach ($taskId in @($taskD,$taskC,$taskB,$taskA)) { if ($taskId) { $r = Invoke-Rpc 'delete_task_secure' @{ p_task_id = $taskId } $tokens.manager $anonKey $base; if ($r.status -notin (200..299,404)) { $cleanupFailed = $true } } }
    if ($projectId) { $r = Invoke-Rpc 'delete_project_secure' @{ p_project_id = $projectId } $tokens.manager $anonKey $base; if ($r.status -notin (200..299,404)) { $cleanupFailed = $true } }
  } catch { $cleanupFailed = $true }
  try {
    # Waiting/resume/blocked transitions queue notifications as well as the
    # successor-ready notification. Discover only notifications tied to this
    # synthetic marker/tasks, then remove them through the recipient RPC.
    if ($tokens.employee) {
      $allEmployeeNotifications = Get-List ((Invoke-Rpc 'list_my_notifications' @{ p_limit = 200 } $tokens.employee $anonKey $base).json)
      foreach ($notice in $allEmployeeNotifications) {
        $noticeText = [string]$notice.message
        if ($notice.id -and ($noticeText -match [regex]::Escape($marker) -or [string]$notice.task_id -in @($taskA,$taskB,$taskC,$taskD))) { [void]$notificationIds.Add([string]$notice.id) }
      }
      foreach ($noticeId in @($notificationIds | Select-Object -Unique)) { $r = Invoke-Rpc 'delete_my_notification' @{ p_notification_id = $noticeId } $tokens.employee $anonKey $base; if ($r.status -notin (200..299,404)) { $cleanupFailed = $true } }
    }
  } catch { $cleanupFailed = $true }
  try {
    if ($projectId) {
      $markerQuery = 'project_name=like.*' + [uri]::EscapeDataString($marker) + '*' + $amp + 'select=id'
      $left = @(Invoke-Rest GET (New-ApiUrl $base '/rest/v1/projects' $markerQuery) $adminHeaders).json
      if ($left.Count -gt 0) { $cleanupFailed = $true }
    }
  } catch { $cleanupFailed = $true }
  foreach ($name in @('tokens','passwords','users')) { try { Set-Variable -Name $name -Value @{} -Scope Script } catch {} }
  $adminHeaders = $null
  $serviceKey = $anonKey = $null
}

Add-Result $results 'synthetic_cleanup' (-not $cleanupFailed)
foreach ($entry in $results.GetEnumerator()) { Write-Output ('{0}={1}' -f $entry.Key, $entry.Value) }
$failureNames = @($results.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if ($gateFailure) { $failureNames += 'workflow_execution_detail' }
if ($failureNames.Count -gt 0) { throw ('PRODUCTIVITY ABC INTEGRATED ACCEPTANCE FAILED: ' + ($failureNames -join ', ')) }
Write-Output "PRODUCTIVITY ABC INTEGRATED ACCEPTANCE: PASS ($TargetRef)"
