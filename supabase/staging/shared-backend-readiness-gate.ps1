$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'

# Staging-only authenticated cross-module gate. No migrations are deployed and
# no Auth identities are created or removed by this script.
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$refPath = Join-Path $PSScriptRoot '..\.temp\project-ref'
if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing linked Supabase project reference.' }
$linkedRef = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linkedRef -cne $TargetRef -or $linkedRef -ceq $ProductionRef) {
  throw "ABORTED: linked project is '$linkedRef', not staging."
}

function Invoke-NativeJson([string]$FilePath, [string[]]$Arguments) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  # Windows PowerShell 5.1/.NET Framework has no ProcessStartInfo.ArgumentList.
  $psi.Arguments = (($Arguments | ForEach-Object { '"' + ([string]$_).Replace('"', '\"') + '"' }) -join ' ')
  $process = New-Object System.Diagnostics.Process; $process.StartInfo = $psi
  [void]$process.Start(); $stdout = $process.StandardOutput.ReadToEnd(); $stderr = $process.StandardError.ReadToEnd(); $process.WaitForExit()
  if ($process.ExitCode -ne 0) { throw "Supabase CLI failed (exit $($process.ExitCode))." }
  if ([string]::IsNullOrWhiteSpace($stdout)) { throw 'Supabase CLI returned no JSON.' }
  return ($stdout | ConvertFrom-Json)
}

function Invoke-Json([string]$Method, [string]$Url, [hashtable]$Headers, $Body = $null, [switch]$ExpectFailure) {
  $script:LastHttpError = $null
  try {
    $params = @{ Method = $Method; Uri = $Url; Headers = $Headers; UseBasicParsing = $true; ErrorAction = 'Stop' }
    if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 25 -Compress) }
    $response = Invoke-WebRequest @params; $content = $response.Content
    if ($ExpectFailure) { throw "Expected authorization failure but request succeeded: $Method $Url" }
    if ([string]::IsNullOrWhiteSpace($content)) { return $null }
    try { return ($content | ConvertFrom-Json) } catch { return $content }
  } catch {
    $status = $null; $errorBody = $null
    if ($_.Exception.Response) {
      try { $status = [int]$_.Exception.Response.StatusCode } catch {}
      try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errorBody = $reader.ReadToEnd(); $reader.Dispose()
      } catch {}
    }
    $parsedError = $null
    if (-not [string]::IsNullOrWhiteSpace($errorBody)) {
      try { $parsedError = $errorBody | ConvertFrom-Json } catch { $parsedError = $errorBody }
    }
    $script:LastHttpError = [pscustomobject]@{
      method = $Method; url = $Url; status = $status; body = $parsedError
      code = if ($parsedError.code) { [string]$parsedError.code } else { $null }
      message = if ($parsedError.message) { [string]$parsedError.message } else { $_.Exception.Message }
    }
    # Expected authorization failures are returned to the caller as a safe
    # null sentinel; the parsed response remains available in LastHttpError.
    if ($ExpectFailure) { return $null }
    $suffix = if ($script:LastHttpError.code) { " code=$($script:LastHttpError.code)" } else { '' }
    throw "HTTP/RPC failure for $Method ${Url}: $($script:LastHttpError.message)$suffix"
  }
}

function New-Headers([string]$ApiKey, [string]$Token = $null, [switch]$Service) {
  $authorization = if ($Service -or [string]::IsNullOrWhiteSpace($Token)) { "Bearer $ApiKey" } else { "Bearer $Token" }
  return @{ apikey = $ApiKey; Authorization = $authorization; 'Content-Type' = 'application/json'; Prefer = 'return=representation' }
}
function New-RandomPassword {
  $bytes = New-Object byte[] 24
  $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  return ([Convert]::ToBase64String($bytes) + 'Aa9!')
}
function Get-Token([string]$Email, [string]$Password, [string]$AnonKey, [string]$BaseUrl) {
  $tokenUrl = New-ApiUrl $BaseUrl '/auth/v1/token' 'grant_type=password'
  $response = Invoke-Json POST $tokenUrl (New-Headers $AnonKey) @{ email = $Email; password = $Password }
  if ([string]::IsNullOrWhiteSpace($response.access_token)) { throw 'Staging identity sign-in did not return a token.' }
  return $response.access_token
}
function Invoke-Rpc([string]$Name, $Payload, [string]$Token, [string]$AnonKey, [string]$BaseUrl, [switch]$ExpectFailure) {
  return Invoke-Json POST "$BaseUrl/rest/v1/rpc/$Name" (New-Headers $AnonKey $Token) $Payload -ExpectFailure:$ExpectFailure
}
function Mark([hashtable]$Results, [string]$Name, [bool]$Value) { $Results[$Name] = $Value }
function New-ApiUrl([string]$BaseUrl, [string]$Path, [string]$Query = $null) {
  if ([string]::IsNullOrWhiteSpace($Query)) { return ($BaseUrl + $Path) }
  return ($BaseUrl + $Path + '?' + $Query)
}

$base = "https://$TargetRef.supabase.co"
$results = [ordered]@{ staging_ref = ($linkedRef -ceq $TargetRef) }
$clientId = $dealId = $projectId = $taskId = $todoId = $attachmentId = $notificationId = $storagePath = $null
$passwords = @{}; $tokens = @{}; $users = @{}
$originalProfiles = @{}; $temporaryCrmAuthorizationApplied = $false; $restoreFailure = $null; $managerProfileRestored = $false

try {
  $keys = Invoke-NativeJson 'supabase' @('projects', 'api-keys', '--project-ref', $TargetRef, '--reveal', '--output', 'json')
  $serviceKey = ($keys | Where-Object { $_.name -eq 'service_role' } | Select-Object -First 1).api_key
  $anonKey = ($keys | Where-Object { $_.name -eq 'anon' } | Select-Object -First 1).api_key
  if ([string]::IsNullOrWhiteSpace($serviceKey) -or [string]::IsNullOrWhiteSpace($anonKey)) { throw 'Staging API keys are unavailable.' }
  $adminHeaders = New-Headers $serviceKey -Service

  # Discover existing synthetic identities by staging profile employee_id and
  # match their Auth UUIDs. No test email address is assumed.
  $amp = [char]38
  $profileQuery = 'employee_id=in.(TEST-MANAGER,TEST-EMPLOYEE,TEST-OUTSIDER)' + $amp + 'select=id,employee_id,is_active,role,job_title,job_title_ar,department_id'
  $profileUrl = New-ApiUrl $base '/rest/v1/profiles' $profileQuery
  $profileRows = @(Invoke-Json GET $profileUrl $adminHeaders)
  $authUsersUrl = New-ApiUrl $base '/auth/v1/admin/users' 'per_page=100'
  $authUsers = @((Invoke-Json GET $authUsersUrl $adminHeaders).users)
  foreach ($kind in @('manager','employee','outsider')) {
    $employeeId = 'TEST-' + $kind.ToUpper()
    $profile = $profileRows | Where-Object { $_.employee_id -eq $employeeId } | Select-Object -First 1
    if (-not $profile -or -not $profile.is_active) { throw "Missing or inactive staging profile: $employeeId" }
    $authUser = $authUsers | Where-Object { $_.id -eq $profile.id } | Select-Object -First 1
    if (-not $authUser -or [string]::IsNullOrWhiteSpace($authUser.email)) { throw "Auth/profile UUID mismatch: $employeeId" }
    $users[$kind] = $authUser; $passwords[$kind] = New-RandomPassword
    # Preserve every authorization-related profile field that this harness may
    # change. The values are restored verbatim in finally, including nulls.
    $originalProfiles[$kind] = @{
      employee_id = $profile.employee_id
      role = $profile.role
      job_title = $profile.job_title
      job_title_ar = $profile.job_title_ar
      department_id = $profile.department_id
      is_active = $profile.is_active
    }
    $authUserUrl = "$base/auth/v1/admin/users/$($authUser.id)"
    Invoke-Json PUT $authUserUrl $adminHeaders @{ password = $passwords[$kind]; email_confirm = $true } | Out-Null
  }
  # Existing HR.sys CRM access is granted by can_access_crm(), which requires
  # an executive/admin role, a Sales/Marketing title, or a Sales/Marketing
  # department. TEST MANAGER is intentionally a plain MANAGER in the synthetic
  # profile. Discover an active Sales department and a compatible active title
  # from the staging catalog, then temporarily assign both fields. No
  # production UUID or job-title value is hardcoded here.
  $salesQuery = 'name=ilike.*sales*' + $amp + 'select=id,name' + $amp + 'limit=1'
  $salesDepartment = @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/departments' $salesQuery) $adminHeaders) | Select-Object -First 1
  if (-not $salesDepartment) {
    $salesArabicQuery = 'name_ar=ilike.*المبيعات*' + $amp + 'select=id,name' + $amp + 'limit=1'
    $salesDepartment = @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/departments' $salesArabicQuery) $adminHeaders) | Select-Object -First 1
  }
  if (-not $salesDepartment) { throw 'No existing Sales department is available for the temporary CRM test authorization.' }
  $salesJobTitleQuery = ('department_id=eq.' + $salesDepartment.id) + $amp + 'is_active=eq.true' + $amp + 'select=id,name,name_ar,department_id,is_active'
  $salesJobTitles = @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/job_titles' $salesJobTitleQuery) $adminHeaders)
  # Any active title whose catalog department is the discovered Sales
  # department is valid for the profile integrity trigger and for
  # can_access_crm(); no title UUID or production title value is assumed.
  $compatibleSalesTitle = $salesJobTitles | Select-Object -First 1
  if (-not $compatibleSalesTitle) {
    throw "No active Sales-compatible job title is available in department $($salesDepartment.id)."
  }
  $managerProfileUrl = New-ApiUrl $base '/rest/v1/profiles' ('id=eq.' + $users.manager.id)
  $temporaryManagerPatch = @{
    department_id = $salesDepartment.id
    job_title = $compatibleSalesTitle.name
  }
  if (($compatibleSalesTitle.PSObject.Properties.Name -contains 'name_ar') -and (-not [string]::IsNullOrWhiteSpace([string]$compatibleSalesTitle.name_ar))) {
    $temporaryManagerPatch.job_title_ar = $compatibleSalesTitle.name_ar
  }
  $managerNeedsTemporaryAuthorization =
    ([string]$originalProfiles.manager.department_id -cne [string]$temporaryManagerPatch.department_id) -or
    ([string]$originalProfiles.manager.job_title -cne [string]$temporaryManagerPatch.job_title) -or
    ($temporaryManagerPatch.ContainsKey('job_title_ar') -and [string]$originalProfiles.manager.job_title_ar -cne [string]$temporaryManagerPatch.job_title_ar)
  if ($managerNeedsTemporaryAuthorization) {
    Invoke-Json PATCH $managerProfileUrl $adminHeaders $temporaryManagerPatch | Out-Null
    $temporaryCrmAuthorizationApplied = $true
  }
  foreach ($kind in @('manager','employee','outsider')) { $tokens[$kind] = Get-Token $users[$kind].email $passwords[$kind] $anonKey $base }
  Mark $results 'identities_ready' ($tokens.Count -eq 3)

  # Verify the temporary profile through the authoritative CRM predicate
  # while authenticated as TEST MANAGER, before starting the workflow.
  $managerCrmAccess = Invoke-Rpc 'can_access_crm' @{} $tokens.manager $anonKey $base
  Mark $results 'manager_crm_authorized' ([bool]$managerCrmAccess)
  if (-not [bool]$managerCrmAccess) { throw 'Temporary TEST MANAGER Sales authorization did not satisfy can_access_crm().' }

  Write-Output 'STEP=CLIENT_DEAL_APPROVAL_PROJECT_TASK_ATTACHMENT_NOTIFICATION'
  $client = Invoke-Rpc 'create_crm_client_secure' @{ p_client = @{ name = 'SECURITY TEST CLIENT'; company = 'HR.sys staging only'; email = 'security-test@hrsys-staging.invalid'; status = 'ACTIVE' } } $tokens.manager $anonKey $base
  $clientId = $client.id; Mark $results 'client_create' (-not [string]::IsNullOrWhiteSpace($clientId))
  $deal = Invoke-Rpc 'create_crm_deal_secure' @{ p_deal = @{ title = 'SECURITY TEST DEAL'; client_id = $clientId; stage = 'LEAD'; amount = 5000; assigned_to = $users.employee.id; first_contact_date = '2026-09-28'; contact_method = 'EMAIL'; event_type = 'STAGING' } } $tokens.manager $anonKey $base
  $dealId = $deal.id; Mark $results 'deal_create' (-not [string]::IsNullOrWhiteSpace($dealId))
  Invoke-Rpc 'start_deal_approval' @{ p_deal_id = $dealId; p_marketing_manager = $users.manager.id; p_general_manager = $users.employee.id; p_operations_manager = $users.manager.id } $tokens.manager $anonKey $base | Out-Null
  $approvalQuery = ('deal_id=eq.' + $dealId) + $amp + 'select=id,approver_id,status'
  $approvalSteps = @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/crm_deal_approval_steps' $approvalQuery) $adminHeaders)
  foreach ($step in $approvalSteps) {
    $approverKind = ($users.GetEnumerator() | Where-Object { $_.Value.id -eq $step.approver_id } | Select-Object -First 1).Key
    if ($approverKind) { Invoke-Rpc 'decide_deal_approval' @{ p_step_id = $step.id; p_decision = 'APPROVED'; p_note = 'Synthetic staging approval' } $tokens[$approverKind] $anonKey $base | Out-Null }
  }
  Mark $results 'approval_cycle' (@($approvalSteps).Count -gt 0)

  $projectPayload = @{ project_name = 'SECURITY TEST PROJECT'; project_type = 'EVENT'; description = 'Temporary shared-gate record'; client_id = $clientId; deal_id = $dealId; assigned_people = @($users.employee.id); project_manager_id = $users.manager.id; project_category = 'Enterprise'; project_tags = @('staging'); budget_amount = 5000; actual_cost = 1000 }
  $project = Invoke-Rpc 'create_project_secure' @{ p_project = $projectPayload } $tokens.manager $anonKey $base
  $projectId = $project.id; Mark $results 'project_create' (-not [string]::IsNullOrWhiteSpace($projectId))
  $task = Invoke-Rpc 'create_task_secure' @{ p_payload = @{ title = 'SECURITY TEST TASK'; description = 'Temporary linked task'; project_id = $projectId; crm_deal_id = $dealId; assignee_ids = @($users.employee.id); priority = 'medium'; category = 'General'; visibility = 'public' } } $tokens.manager $anonKey $base
  $taskId = $task.id; Mark $results 'task_create' (-not [string]::IsNullOrWhiteSpace($taskId))
  $todo = Invoke-Rpc 'add_project_todo' @{ p_project_id = $projectId; p_title = 'SECURITY TEST TODO'; p_assignee_ids = @($users.employee.id); p_due_at = (Get-Date).ToUniversalTime().AddDays(1).ToString('o') } $tokens.manager $anonKey $base
  $todoId = $todo.id; Mark $results 'todo_create' (-not [string]::IsNullOrWhiteSpace($todoId))

  $storagePath = "$taskId/$($users.manager.id)/security-test.txt"
  $storageHeaders = New-Headers $serviceKey -Service
  $storageHeaders['Content-Type'] = 'text/plain'
  Invoke-Json POST "$base/storage/v1/object/task-attachments/$storagePath" $storageHeaders 'synthetic staging attachment' | Out-Null
  # Keep the orchestrator aligned with the authoritative Task/File contract.
  # The deployed RPC uses p_attachment_scope and p_visible (the Web adapter
  # and File readiness harness use these names); p_scope and
  # p_visible_to_project_assignee are not deployed parameters.
  $attachment = Invoke-Rpc 'register_task_attachment' @{ p_task_id = $taskId; p_file_url = "storage://task-attachments/$storagePath"; p_file_name = 'security-test.txt'; p_file_type = 'text/plain'; p_file_size = 28; p_attachment_scope = 'TASK'; p_visible = $true } $tokens.manager $anonKey $base
  $attachmentId = $attachment.id; Mark $results 'attachment_create' (-not [string]::IsNullOrWhiteSpace($attachmentId))
  $notification = Invoke-Rpc 'create_notification_secure' @{ p_recipient_id = $users.employee.id; p_message = 'Synthetic shared-gate notification'; p_task_id = $taskId } $tokens.manager $anonKey $base
  $notificationId = $notification.id; Mark $results 'notification_create' (-not [string]::IsNullOrWhiteSpace($notificationId))
  Mark $results 'cross_module_workflow' ($results.client_create -and $results.deal_create -and $results.approval_cycle -and $results.project_create -and $results.task_create -and $results.attachment_create -and $results.notification_create)

  $managerProject = Invoke-Rpc 'get_project_detail_secure' @{ p_project_id = $projectId } $tokens.manager $anonKey $base
  $employeeProject = Invoke-Rpc 'get_project_detail_secure' @{ p_project_id = $projectId } $tokens.employee $anonKey $base
  $employeeFinancialHidden = ($null -eq $employeeProject.project.budget_amount -and $null -eq $employeeProject.project.actual_cost)
  Mark $results 'manager_project_access' ($null -ne $managerProject); Mark $results 'employee_project_access' ($null -ne $employeeProject)
  Mark $results 'financial_redaction' ($employeeFinancialHidden -and $null -ne $managerProject)

  $outsiderProject = Invoke-Rpc 'get_project_detail_secure' @{ p_project_id = $projectId } $tokens.outsider $anonKey $base -ExpectFailure
  $outsiderTask = Invoke-Rpc 'get_task_secure' @{ p_task_id = $taskId } $tokens.outsider $anonKey $base -ExpectFailure
  $outsiderTodo = Invoke-Rpc 'list_project_todos_secure' @{ p_project_id = $projectId } $tokens.outsider $anonKey $base -ExpectFailure
  $outsiderAttachment = Invoke-Rpc 'list_task_attachments_secure' @{ p_task_id = $taskId; p_scope = 'TASK' } $tokens.outsider $anonKey $base -ExpectFailure
  $outsiderNotification = Invoke-Rpc 'get_my_notification' @{ p_notification_id = $notificationId } $tokens.outsider $anonKey $base -ExpectFailure
  $outsiderSignedUrl = Invoke-Json POST "$base/functions/v1/file-signed-url" (New-Headers $anonKey $tokens.outsider) @{ attachmentId = $attachmentId; bucket = 'task-attachments'; path = $storagePath; expiresIn = 3600 } -ExpectFailure
  $outsiderStorageRead = Invoke-Json GET "$base/storage/v1/object/task-attachments/$storagePath" (New-Headers $anonKey $tokens.outsider) $null -ExpectFailure
  $outsiderClient = Invoke-Rpc 'get_crm_client_secure' @{ p_client_id = $clientId } $tokens.outsider $anonKey $base -ExpectFailure
  $outsiderDeal = Invoke-Rpc 'get_crm_deal_secure' @{ p_deal_id = $dealId } $tokens.outsider $anonKey $base -ExpectFailure
  $outsiderUpdate = Invoke-Rpc 'update_project_secure' @{ p_project_id = $projectId; p_changes = @{ description = 'IDOR' } } $tokens.outsider $anonKey $base -ExpectFailure
  $outsiderAssign = Invoke-Rpc 'assign_project_team' @{ p_project_id = $projectId; p_project_manager_id = $users.outsider.id; p_assignee_ids = @($users.outsider.id) } $tokens.outsider $anonKey $base -ExpectFailure
  $outsiderTaskPatch = Invoke-Rpc 'update_task_secure' @{ p_task_id = $taskId; p_patch = @{ assignee_id = $users.outsider.id; assignee_ids = @($users.outsider.id) } } $tokens.outsider $anonKey $base -ExpectFailure
  $outsiderProfileUrl = New-ApiUrl $base '/rest/v1/profiles' ('id=eq.' + $users.outsider.id)
  $profilePatch = Invoke-Json PATCH $outsiderProfileUrl (New-Headers $anonKey $tokens.outsider) @{ role = 'ADMIN'; department_id = $users.manager.id; employee_id = 'ADMIN-OVERRIDE' } -ExpectFailure
  $directProjectUrl = New-ApiUrl $base '/rest/v1/projects' ('id=eq.' + $projectId)
  $directProject = Invoke-Json PATCH $directProjectUrl (New-Headers $anonKey $tokens.outsider) @{ description = 'IDOR' } -ExpectFailure
  $directDealUrl = New-ApiUrl $base '/rest/v1/crm_deals' ('id=eq.' + $dealId)
  $directDeal = Invoke-Json PATCH $directDealUrl (New-Headers $anonKey $tokens.outsider) @{ assigned_to = $users.outsider.id; client_id = $users.outsider.id } -ExpectFailure
  $directClientUrl = New-ApiUrl $base '/rest/v1/crm_clients' ('id=eq.' + $clientId)
  $directClient = Invoke-Json PATCH $directClientUrl (New-Headers $anonKey $tokens.outsider) @{ assigned_to = $users.outsider.id } -ExpectFailure
  Mark $results 'cross_module_idor_denied' ($null -eq $outsiderProject -and $null -eq $outsiderTask -and $null -eq $outsiderTodo -and $null -eq $outsiderAttachment -and $null -eq $outsiderNotification -and $null -eq $outsiderSignedUrl -and $null -eq $outsiderStorageRead -and $null -eq $outsiderClient -and $null -eq $outsiderDeal -and $null -eq $outsiderUpdate -and $null -eq $outsiderAssign -and $null -eq $outsiderTaskPatch -and $null -eq $directProject -and $null -eq $directDeal -and $null -eq $directClient)
  Mark $results 'privilege_escalation_denied' ($null -eq $profilePatch -and $null -eq $outsiderTaskPatch -and $null -eq $directDeal -and $null -eq $directClient)
} finally {
  if ($temporaryCrmAuthorizationApplied -and $users.manager.id -and $originalProfiles.manager) {
    try {
      Invoke-Json PATCH (New-ApiUrl $base '/rest/v1/profiles' ('id=eq.' + $users.manager.id)) $adminHeaders $originalProfiles.manager | Out-Null
      $restoredProfile = @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/profiles' (('id=eq.' + $users.manager.id) + $amp + 'select=id,employee_id,is_active,role,job_title,job_title_ar,department_id')) $adminHeaders) | Select-Object -First 1
      if (-not $restoredProfile) { throw 'Restored TEST MANAGER profile was not returned.' }
      foreach ($field in @('employee_id','role','job_title','job_title_ar','department_id','is_active')) {
        if ([string]$restoredProfile.$field -cne [string]$originalProfiles.manager[$field]) {
          throw "TEST MANAGER profile restoration mismatch for $field."
        }
      }
      $managerProfileRestored = $true
    } catch { $restoreFailure = $_.Exception.Message }
  } elseif ($users.manager.id -and $originalProfiles.manager) {
    try {
      $currentManagerProfile = @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/profiles' (('id=eq.' + $users.manager.id) + $amp + 'select=id,employee_id,is_active,role,job_title,job_title_ar,department_id')) $adminHeaders) | Select-Object -First 1
      if (-not $currentManagerProfile) { throw 'TEST MANAGER profile was not returned during restoration verification.' }
      foreach ($field in @('employee_id','role','job_title','job_title_ar','department_id','is_active')) {
        if ([string]$currentManagerProfile.$field -cne [string]$originalProfiles.manager[$field]) {
          throw "TEST MANAGER profile changed unexpectedly for $field."
        }
      }
      $managerProfileRestored = $true
    } catch { $restoreFailure = $_.Exception.Message }
  }
  if ($storagePath) { try { Invoke-Json DELETE "$base/storage/v1/object/task-attachments/$storagePath" $adminHeaders | Out-Null } catch {} }
  if ($notificationId) { try { Invoke-Json DELETE (New-ApiUrl $base '/rest/v1/notifications' ('id=eq.' + $notificationId)) $adminHeaders | Out-Null } catch {} }
  if ($attachmentId) { try { Invoke-Json DELETE (New-ApiUrl $base '/rest/v1/task_attachments' ('id=eq.' + $attachmentId)) $adminHeaders | Out-Null } catch {} }
  if ($todoId) { try { Invoke-Json DELETE (New-ApiUrl $base '/rest/v1/project_todos' ('id=eq.' + $todoId)) $adminHeaders | Out-Null } catch {} }
  if ($taskId) { try { Invoke-Json DELETE (New-ApiUrl $base '/rest/v1/tasks' ('id=eq.' + $taskId)) $adminHeaders | Out-Null } catch {} }
  if ($projectId) { try { Invoke-Json DELETE (New-ApiUrl $base '/rest/v1/projects' ('id=eq.' + $projectId)) $adminHeaders | Out-Null } catch {} }
  if ($dealId) { try { Invoke-Json DELETE (New-ApiUrl $base '/rest/v1/crm_deals' ('id=eq.' + $dealId)) $adminHeaders | Out-Null } catch {} }
  if ($clientId) { try { Invoke-Json DELETE (New-ApiUrl $base '/rest/v1/crm_clients' ('id=eq.' + $clientId)) $adminHeaders | Out-Null } catch {} }
}

if ($restoreFailure) { throw "STOP: failed to restore TEST MANAGER profile: $restoreFailure" }
Mark $results 'manager_profile_restored' $managerProfileRestored

$remainingClients = @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/crm_clients' ('name=eq.SECURITY%20TEST%20CLIENT' + $amp + 'select=id')) $adminHeaders)
$remainingDeals = @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/crm_deals' ('title=eq.SECURITY%20TEST%20DEAL' + $amp + 'select=id')) $adminHeaders)
$remainingProjects = @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/projects' ('project_name=eq.SECURITY%20TEST%20PROJECT' + $amp + 'select=id')) $adminHeaders)
$remainingTasks = @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/tasks' ('title=eq.SECURITY%20TEST%20TASK' + $amp + 'select=id')) $adminHeaders)
$remainingTodos = @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/project_todos' ('title=eq.SECURITY%20TEST%20TODO' + $amp + 'select=id')) $adminHeaders)
$remainingAttachments = if ($taskId) { @(Invoke-Json GET (New-ApiUrl $base '/rest/v1/task_attachments' (('task_id=eq.' + $taskId) + $amp + 'select=id')) $adminHeaders) } else { @() }
# Notification ownership is user_id, and the authoritative read path is
# list_my_notifications/get_my_notification. Cleanup verification uses the
# already-known synthetic notification id through the recipient's secure RPC,
# so it does not depend on a stale recipient column or an unscoped table lookup.
$remainingNotification = if ($notificationId -and $tokens.employee) {
  Invoke-Rpc 'get_my_notification' @{ p_notification_id = $notificationId } $tokens.employee $anonKey $base
} else { $null }
$remainingNotifications = @($remainingNotification | Where-Object { $null -ne $_ })
$remainingStorage = if ($storagePath) { @(Invoke-Json POST "$base/storage/v1/object/list/task-attachments" $adminHeaders @{ prefix = $storagePath; limit = 10 }) } else { @() }
# This cross-module gate does not register a device. Device fixtures belong to
# notification-readiness-test.ps1, which uses the push_subscriptions table and
# authoritative device RPCs.
$remainingDevices = @()
$remainingCount = $remainingClients.Count + $remainingDeals.Count + $remainingProjects.Count + $remainingTasks.Count + $remainingTodos.Count + $remainingAttachments.Count + $remainingNotifications.Count + $remainingStorage.Count + $remainingDevices.Count
Mark $results 'synthetic_cleanup' ($remainingCount -eq 0)
$failed = @($results.GetEnumerator() | Where-Object { -not $_.Value })
foreach ($entry in $results.GetEnumerator()) { Write-Output ("{0}={1}" -f $entry.Key, $entry.Value) }
if ($failed.Count -gt 0) { throw ('SHARED BACKEND GATE FAILED: ' + (($failed | ForEach-Object { $_.Key }) -join ', ')) }
Write-Output "SHARED BACKEND MOBILE READINESS GATE: PASSED ($TargetRef)"
