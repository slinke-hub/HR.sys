[CmdletBinding()]
param([switch]$PauseForBrowserReview)

# Authenticated Project Operations Phase 1 staging acceptance.
# Uses only existing TEST identities, the staging public anon key, and
# authenticated application RPCs for business-data setup and cleanup.

$ErrorActionPreference = 'Stop'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$FrozenMigrationHash = '64c464cca0102a8e784d1610be61bced32535ae30e7bc2a0af1c1424c1bc2037'
$StagingOrigin = "https://$TargetRef.supabase.co"
$Emails = @{
  'TEST-MANAGER' = 'test.manager@hrsys-staging.invalid'
  'TEST-EMPLOYEE' = 'test.employee@hrsys-staging.invalid'
  'TEST-OUTSIDER' = 'test.outsider@hrsys-staging.invalid'
}
$LinkPath = Join-Path $PSScriptRoot '..\.temp\project-ref'
$Root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$SecuritySqlPath = Join-Path $PSScriptRoot 'project-operations-phase-1-security-catalog-check.sql'
$MigrationPath = Join-Path $Root 'supabase\migrations\20261002090000_project_operations_phase_1.sql'
$PreviousTelemetry = $env:SUPABASE_TELEMETRY_DISABLED
$script:Tokens = @{}
$script:RefreshTokens = @{}
$script:Results = [ordered]@{}
$script:ProjectId = $null
$script:ProjectName = $null
$script:TaskIds = New-Object System.Collections.Generic.List[string]
$script:DependencyId = $null
$script:CleanupFailed = $false

function Mark([string]$Name, [bool]$Passed) { $script:Results[$Name] = $Passed }

function Wait-ForBrowserReview([string]$Stage) {
  if (-not $PauseForBrowserReview) { return }
  Write-Output ('BROWSER_REVIEW_STAGE=' + $Stage)
  Write-Output ('BROWSER_FIXTURE_PROJECT=' + $script:ProjectName)
  Write-Output ('BROWSER_FIXTURE_PROJECT_ID=' + $script:ProjectId)
  Write-Output ('BROWSER_FIXTURE_TASKS=' + ($script:TaskIds -join ','))
  [void](Read-Host 'Review the current real staging UI state without changing the fixture, then press Enter to continue')
  $renew = switch ($Stage) {
    'DEPENDENCY_BLOCKED_INITIAL_STATE' { @('TEST-EMPLOYEE', 'TEST-MANAGER') }
    'WAITING_STATE' { @('TEST-EMPLOYEE', 'TEST-MANAGER') }
    'BLOCKED_STATE' { @('TEST-EMPLOYEE', 'TEST-MANAGER') }
    'ALL_TASKS_COMPLETE_BEFORE_EXPLICIT_PROJECT_COMPLETION' { @('TEST-MANAGER') }
    default { @('TEST-MANAGER') }
  }
  foreach ($identity in $renew) { Ensure-IdentitySession $identity }
}

function Read-StagingAnonKey {
  foreach ($name in @('VERCEL_STAGING_ANON_KEY','HR_SYS_STAGING_ANON_KEY','MUQAM_SUPABASE_ANON_KEY')) {
    $candidate = [string][Environment]::GetEnvironmentVariable($name, 'Process')
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    try {
      $parts = $candidate.Split('.')
      if ($parts.Count -ne 3) { continue }
      $payloadText = $parts[1].Replace('-', '+').Replace('_', '/')
      switch ($payloadText.Length % 4) { 2 { $payloadText += '==' } 3 { $payloadText += '=' } }
      $payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloadText)) | ConvertFrom-Json
      if ($payload.ref -ceq $TargetRef -and $payload.role -ceq 'anon') { return $candidate }
    } catch { }
  }
  throw 'Set a valid staging public anon key in VERCEL_STAGING_ANON_KEY, HR_SYS_STAGING_ANON_KEY, or MUQAM_SUPABASE_ANON_KEY. No key value is displayed.'
}

function Convert-SecureStringToPlainText([Security.SecureString]$Value) {
  $pointer = [IntPtr]::Zero
  try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  } finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
  }
}

function Invoke-Http([string]$Method, [string]$Path, [string]$Identity, $Body = $null, [switch]$Anonymous) {
  $headers = @{ apikey = $script:AnonKey; 'Content-Type' = 'application/json' }
  if ($Anonymous) { $headers.Authorization = "Bearer $script:AnonKey" }
  elseif ($Identity) { $headers.Authorization = "Bearer $($script:Tokens[$Identity])" }
  $parameters = @{ Method = $Method; Uri = ($StagingOrigin + $Path); Headers = $headers; UseBasicParsing = $true; ErrorAction = 'Stop' }
  if ($null -ne $Body) { $parameters.Body = ($Body | ConvertTo-Json -Depth 30 -Compress) }
  try {
    $response = Invoke-WebRequest @parameters
    $parsed = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$response.Content)) { try { $parsed = $response.Content | ConvertFrom-Json } catch { } }
    return [pscustomobject]@{ Status = [int]$response.StatusCode; Data = $parsed; Code = ''; Message = '' }
  } catch {
    $status = 0; $payload = $null
    if ($_.Exception.Response) {
      try { $status = [int]$_.Exception.Response.StatusCode } catch { }
      try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $content = $reader.ReadToEnd(); $reader.Dispose()
        if ($content) { $payload = $content | ConvertFrom-Json }
      } catch { }
    }
    $code = if ($payload -and $payload.code) { [string]$payload.code } else { '' }
    $message = if ($payload -and $payload.message) { [string]$payload.message } else { '' }
    return [pscustomobject]@{ Status = $status; Data = $payload; Code = $code; Message = (($message -replace '\s+', ' ').Trim()) }
  }
}

function Rpc([string]$Name, [hashtable]$Payload, [string]$Identity) {
  $response = Invoke-Http 'POST' ("/rest/v1/rpc/$Name") $Identity $Payload
  if ($response.Status -eq 401) {
    Ensure-IdentitySession $Identity
    $response = Invoke-Http 'POST' ("/rest/v1/rpc/$Name") $Identity $Payload
  }
  return $response
}

function Require-RpcSuccess([string]$Step, [string]$Name, [string]$Identity, $Response) {
  if ($Response.Status -lt 200 -or $Response.Status -ge 300) {
    throw ("step=$Step;identity=$Identity;rpc=$Name;http_status=$($Response.Status);code=$($Response.Code);message=$($Response.Message)")
  }
  return $Response.Data
}

function Assert-StagingLink {
  if (-not (Test-Path -LiteralPath $LinkPath -PathType Leaf)) { throw 'Missing linked project marker; no relinking is permitted.' }
  $linked = (Get-Content -Raw -LiteralPath $LinkPath).Trim()
  if ($linked -ceq $ProductionRef) { throw 'Production link detected; this harness refuses production.' }
  if ($linked -cne $TargetRef) { throw 'The linked project is not the required staging project.' }
  if (-not (Test-Path -LiteralPath $MigrationPath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $MigrationPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $FrozenMigrationHash) {
    throw 'Frozen Project Operations Phase 1 migration is missing or its SHA-256 differs from the staging-verified source.'
  }
}

function Sign-InExistingIdentity([string]$Identity) {
  $secure = Read-Host ("Enter the existing $Identity password privately (input is hidden)") -AsSecureString
  $password = $null
  try {
    $password = Convert-SecureStringToPlainText $secure
    $response = Invoke-Http 'POST' '/auth/v1/token?grant_type=password' $null @{ email = $Emails[$Identity]; password = $password } -Anonymous
    if ($response.Status -lt 200 -or $response.Status -ge 300 -or -not $response.Data.access_token -or
        [string]$response.Data.user.email -ine $Emails[$Identity]) {
      throw ("Existing $Identity login failed; HTTP status $($response.Status), code $($response.Code). No password or token is logged.")
    }
    $script:Tokens[$Identity] = [string]$response.Data.access_token
    $script:RefreshTokens[$Identity] = [string]$response.Data.refresh_token
    $profileResponse = Invoke-Http 'GET' ("/rest/v1/profiles?id=eq.$($response.Data.user.id)&select=id,employee_id,role,is_active") $Identity $null
    if ($profileResponse.Status -lt 200 -or $profileResponse.Status -ge 300 -or @($profileResponse.Data).Count -ne 1) {
      throw ("Could not verify the $Identity profile from its authenticated session; HTTP status $($profileResponse.Status).")
    }
    $profile = @($profileResponse.Data)[0]
    if ([string]$profile.employee_id -cne $Identity -or $profile.is_active -eq $false) { throw "$Identity login did not resolve to the expected active staging profile." }
    $expectedRole = if ($Identity -eq 'TEST-MANAGER') { 'MANAGER' } else { 'EMPLOYEE' }
    if ([string]$profile.role -cne $expectedRole) { throw "$Identity profile role did not match the staging test identity contract." }
    return [string]$profile.id
  } finally {
    $password = $null
    if ($secure) { $secure.Dispose() }
  }
}

function Refresh-ExistingIdentity([string]$Identity) {
  $refresh = [string]$script:RefreshTokens[$Identity]
  if ([string]::IsNullOrWhiteSpace($refresh)) { return $false }
  $response = Invoke-Http 'POST' '/auth/v1/token?grant_type=refresh_token' $null @{ refresh_token = $refresh } -Anonymous
  if ($response.Status -lt 200 -or $response.Status -ge 300 -or -not $response.Data.access_token -or
      [string]$response.Data.user.email -ine $Emails[$Identity] -or -not $response.Data.refresh_token) { return $false }
  $script:Tokens[$Identity] = [string]$response.Data.access_token
  $script:RefreshTokens[$Identity] = [string]$response.Data.refresh_token
  return $true
}

function Ensure-IdentitySession([string]$Identity) {
  if (Refresh-ExistingIdentity $Identity) { return }
  [void](Sign-InExistingIdentity $Identity)
}

function Get-ProjectRow($Value) {
  if ($Value -is [System.Array]) { return $Value | Where-Object { [string]$_.id -eq $script:ProjectId } | Select-Object -First 1 }
  return $null
}

function Get-AggregateSignature($Snapshot) {
  $counts = [ordered]@{}
  if ($Snapshot.counts) { foreach ($property in $Snapshot.counts.PSObject.Properties) { $counts[$property.Name] = $property.Value } }
  return [ordered]@{
    progress_percent = $Snapshot.progress_percent
    health = if ($Snapshot.health) { $Snapshot.health } else { $Snapshot.health_status }
    reason_codes = @($Snapshot.reason_codes)
    counts = $counts
  } | ConvertTo-Json -Depth 20 -Compress
}

function Same-OperationalState($Candidate, $Expected) {
  if ($null -eq $Candidate -or $null -eq $Expected) { return $false }
  $candidateHealth = if ($Candidate.health) { [string]$Candidate.health } else { [string]$Candidate.health_status }
  $expectedHealth = if ($Expected.health) { [string]$Expected.health } else { [string]$Expected.health_status }
  return ([int]$Candidate.progress_percent -eq [int]$Expected.progress_percent) -and
    ($candidateHealth -eq $expectedHealth) -and
    ((ConvertTo-Json -InputObject @($Candidate.reason_codes) -Depth 20 -Compress) -ceq (ConvertTo-Json -InputObject @($Expected.reason_codes) -Depth 20 -Compress))
}

function Mark-ReadinessReason([string]$Reason) {
  $response = Rpc 'get_project_completion_readiness' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER'
  $data = Require-RpcSuccess 'COMPLETION_READINESS' 'get_project_completion_readiness' 'TEST-MANAGER' $response
  $codes = @($data.reason_codes | ForEach-Object { [string]$_.code })
  return [pscustomobject]@{ Data = $data; HasReason = ($codes -contains $Reason) }
}

function Invoke-CatalogCheck {
  $cli = Get-Command supabase -CommandType Application -ErrorAction Stop | Select-Object -First 1
  $exe = if ($cli.Path) { $cli.Path } else { $cli.Source }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe; $psi.WorkingDirectory = $Root; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $quoted = @('db','query','--linked','--project-ref',$TargetRef,'--file',$SecuritySqlPath) | ForEach-Object { '"' + ([string]$_).Replace('"','\"') + '"' }
  $psi.Arguments = $quoted -join ' '
  $process = New-Object System.Diagnostics.Process; $process.StartInfo = $psi
  if (-not $process.Start()) { throw 'Could not start the read-only staging catalog check.' }
  $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync(); $process.WaitForExit()
  $output = $outTask.GetAwaiter().GetResult(); $null = $errTask.GetAwaiter().GetResult(); $exitCode = $process.ExitCode; $process.Dispose()
  if ($exitCode -ne 0 -or $output -notmatch 'PHASE1SECURITY\|PASS\|') {
    throw ("Read-only staging security catalog check failed (CLI exit code $exitCode); output withheld.")
  }
  return $true
}

function Cleanup-SyntheticData {
  if ($script:ProjectId -or $script:TaskIds.Count -gt 0 -or $script:DependencyId) {
    Ensure-IdentitySession 'TEST-MANAGER'
    if ($script:DependencyId) {
      $response = Rpc 'remove_task_dependency' @{ p_dependency_id = $script:DependencyId } 'TEST-MANAGER'
      if ($response.Status -lt 200 -or $response.Status -ge 300) { $script:CleanupFailed = $true }
    }
    for ($i = $script:TaskIds.Count - 1; $i -ge 0; $i--) {
      $response = Rpc 'delete_task_secure' @{ p_task_id = $script:TaskIds[$i] } 'TEST-MANAGER'
      if (($response.Status -lt 200 -or $response.Status -ge 300) -and $response.Status -ne 404) { $script:CleanupFailed = $true }
    }
    if ($script:ProjectId) {
      $response = Rpc 'delete_project_secure' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER'
      if (($response.Status -lt 200 -or $response.Status -ge 300) -and $response.Status -ne 404) { $script:CleanupFailed = $true }
    }
  } elseif ($script:ProjectId -or $script:TaskIds.Count -gt 0) {
    $script:CleanupFailed = $true
  }
}

$exitFailure = $false
try {
  Assert-StagingLink
  if (-not (Test-Path -LiteralPath $SecuritySqlPath -PathType Leaf)) { throw 'Read-only staging security catalog SQL is missing.' }
  $script:AnonKey = Read-StagingAnonKey
  $env:SUPABASE_TELEMETRY_DISABLED = '1'
  $managerId = Sign-InExistingIdentity 'TEST-MANAGER'
  $employeeId = Sign-InExistingIdentity 'TEST-EMPLOYEE'
  $outsiderId = Sign-InExistingIdentity 'TEST-OUTSIDER'
  Mark 'existing_test_identities_verified' ($managerId -and $employeeId -and $outsiderId)

  # Use an isolated Project created only through the authenticated secure RPC.
  $marker = 'PHASE1 ACCEPTANCE ' + [Guid]::NewGuid().ToString('N')
  $script:ProjectName = $marker
  $projectPayload = @{
    project_name = $marker; project_type = 'Staging acceptance'; description = 'Temporary Phase 1 acceptance fixture'
    project_manager_id = $managerId; assigned_people = @($employeeId); lifecycle_status = 'ACTIVE'
    event_date = $null; budget_amount = 12500; actual_cost = 3000
  }
  $createdProject = Require-RpcSuccess 'CREATE_PROJECT' 'create_project_secure' 'TEST-MANAGER' (Rpc 'create_project_secure' @{ p_project = $projectPayload } 'TEST-MANAGER')
  $script:ProjectId = [string]$createdProject.id
  if (-not $script:ProjectId) { throw 'Secure Project creation returned no Project ID.' }
  Mark 'project_created_by_secure_rpc' $true

  $zero = Mark-ReadinessReason 'NO_TASKS'
  Mark 'zero_task_progress_is_zero' ($null -ne $createdProject.progress_percent -and [int]$createdProject.progress_percent -eq 0)
  Mark 'zero_task_project_not_ready' (-not [bool]$zero.Data.ready -and $zero.HasReason)
  $zeroComplete = Rpc 'change_project_status' @{ p_project_id = $script:ProjectId; p_status = 'COMPLETED' } 'TEST-MANAGER'
  Mark 'zero_task_completion_denied' ($zeroComplete.Status -ge 200 -and $zeroComplete.Status -lt 300 -and $zeroComplete.Data.changed -eq $false)
  $zeroDetail = Require-RpcSuccess 'ZERO_TASK_PROJECT_STAYS_ACTIVE' 'get_project_detail_secure' 'TEST-MANAGER' (Rpc 'get_project_detail_secure' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER')
  Mark 'zero_task_project_remains_active' ([string]$zeroDetail.project.lifecycle_status -eq 'ACTIVE')

  function Create-ProjectTask([string]$Title, [string]$AssigneeId) {
    $payload = @{ title = $Title; description = 'Temporary authorized Phase 1 acceptance Task'; project_id = $script:ProjectId
      assignee_id = $AssigneeId; assignee_ids = @($AssigneeId); priority = 'medium'; category = 'General'
      visibility = 'public'; status = 'todo'; due_date = (Get-Date).ToString('yyyy-MM-dd') }
    $result = Require-RpcSuccess 'CREATE_TASK' 'create_task_secure' 'TEST-MANAGER' (Rpc 'create_task_secure' @{ p_payload = $payload } 'TEST-MANAGER')
    $id = [string]$result.id
    if (-not $id) { throw 'Secure Task creation returned no Task ID.' }
    [void]$script:TaskIds.Add($id)
    return $id
  }

  $predecessor = Create-ProjectTask ($marker + ' predecessor') $employeeId
  $successor = Create-ProjectTask ($marker + ' successor') $employeeId
  $managerOnly = Create-ProjectTask ($marker + ' manager-only detail') $managerId
  $dependency = Require-RpcSuccess 'CREATE_DEPENDENCY' 'create_task_dependency' 'TEST-MANAGER' (Rpc 'create_task_dependency' @{ p_predecessor_task_id = $predecessor; p_successor_task_id = $successor } 'TEST-MANAGER')
  $script:DependencyId = [string]$dependency.id
  Mark 'tasks_and_dependency_created_via_secure_rpcs' ($predecessor -and $successor -and $managerOnly -and $script:DependencyId)

  $managerSummary = Require-RpcSuccess 'MANAGER_SUMMARY' 'get_project_operational_summary' 'TEST-MANAGER' (Rpc 'get_project_operational_summary' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER')
  $employeeSummary = Require-RpcSuccess 'EMPLOYEE_SUMMARY' 'get_project_operational_summary' 'TEST-EMPLOYEE' (Rpc 'get_project_operational_summary' @{ p_project_id = $script:ProjectId } 'TEST-EMPLOYEE')
  $managerDetail = Require-RpcSuccess 'MANAGER_DETAIL' 'get_project_detail_secure' 'TEST-MANAGER' (Rpc 'get_project_detail_secure' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER')
  $employeeDetail = Require-RpcSuccess 'EMPLOYEE_DETAIL' 'get_project_detail_secure' 'TEST-EMPLOYEE' (Rpc 'get_project_detail_secure' @{ p_project_id = $script:ProjectId } 'TEST-EMPLOYEE')
  $managerHealth = Require-RpcSuccess 'MANAGER_HEALTH' 'get_project_health' 'TEST-MANAGER' (Rpc 'get_project_health' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER')
  $employeeHealth = Require-RpcSuccess 'EMPLOYEE_HEALTH' 'get_project_health' 'TEST-EMPLOYEE' (Rpc 'get_project_health' @{ p_project_id = $script:ProjectId } 'TEST-EMPLOYEE')
  $managerPortfolio = Require-RpcSuccess 'MANAGER_PORTFOLIO' 'list_accessible_projects_secure' 'TEST-MANAGER' (Rpc 'list_accessible_projects_secure' @{} 'TEST-MANAGER')
  $commandCenter = Require-RpcSuccess 'MANAGER_COMMAND_CENTER' 'list_project_command_center' 'TEST-MANAGER' (Rpc 'list_project_command_center' @{ p_limit = 500; p_only_attention = $false; p_upcoming_days = $null } 'TEST-MANAGER')
  $portfolioRow = Get-ProjectRow $managerPortfolio
  $commandRow = @($commandCenter | Where-Object { [string]$_.project_id -eq $script:ProjectId }) | Select-Object -First 1
  Mark 'manager_employee_same_project_access' ($managerDetail.project.id -eq $script:ProjectId -and $employeeDetail.project.id -eq $script:ProjectId)
  Mark 'portfolio_contains_authoritative_project' ($portfolioRow -and $null -ne $portfolioRow.progress_percent -and $portfolioRow.health_status -and $null -ne $portfolioRow.reason_codes)
  Mark 'command_center_contains_authoritative_project' ($commandRow -and $null -ne $commandRow.progress_percent -and $commandRow.health)
  Mark 'manager_employee_shared_aggregate' ((Get-AggregateSignature $managerSummary) -ceq (Get-AggregateSignature $employeeSummary) -and
      (Get-AggregateSignature $managerHealth) -ceq (Get-AggregateSignature $employeeHealth))
  $expectedHealth = if ($managerSummary.health) { [string]$managerSummary.health } else { [string]$managerSummary.health_status }
  $reasonJson = ConvertTo-Json -InputObject @($managerSummary.reason_codes) -Depth 20 -Compress
  $projectDetailStateMatches = ([int]$managerDetail.project.progress_percent -eq [int]$managerSummary.progress_percent) -and
      (([string]$managerDetail.project.health_status -eq $expectedHealth) -or ([string]$managerDetail.project.health -eq $expectedHealth)) -and
      ((ConvertTo-Json -InputObject @($managerDetail.project.reason_codes) -Depth 20 -Compress) -ceq $reasonJson)
  $portfolioStateMatches = ([int]$portfolioRow.progress_percent -eq [int]$managerSummary.progress_percent) -and
      (([string]$portfolioRow.health_status -eq $expectedHealth) -or ([string]$portfolioRow.health -eq $expectedHealth)) -and
      ((ConvertTo-Json -InputObject @($portfolioRow.reason_codes) -Depth 20 -Compress) -ceq $reasonJson)
  $commandStateMatches = ([int]$commandRow.progress_percent -eq [int]$managerSummary.progress_percent) -and
      (([string]$commandRow.health -eq $expectedHealth) -or ([string]$commandRow.health_status -eq $expectedHealth)) -and
      ((ConvertTo-Json -InputObject @($commandRow.reason_codes) -Depth 20 -Compress) -ceq $reasonJson)
  Mark 'health_consistent_portfolio_detail_command_center' ($projectDetailStateMatches -and $portfolioStateMatches -and $commandStateMatches)
  Mark 'hidden_task_detail_filtered' (@($managerSummary.tasks | Where-Object { [string]$_.id -eq $managerOnly }).Count -eq 1 -and
      @($employeeSummary.tasks | Where-Object { [string]$_.id -eq $managerOnly }).Count -eq 0)
  Mark 'employee_financial_redaction' ($null -eq $employeeDetail.project.budget_amount -and $null -eq $employeeDetail.project.actual_cost)
  Mark 'initial_project_progress_zero' ($null -ne $managerSummary.progress_percent -and [int]$managerSummary.progress_percent -eq 0)
  Mark 'initial_dependency_block_visible_in_aggregate' ([int]$managerSummary.counts.dependency_blocked_tasks -ge 1 -and @($managerSummary.reason_codes | Where-Object code -eq 'DEPENDENCY_RISK').Count -ge 1)
  Mark 'initial_readiness_incomplete_dependency_reasons' ((Mark-ReadinessReason 'INCOMPLETE_TASKS').HasReason -and (Mark-ReadinessReason 'UNRESOLVED_DEPENDENCY_CHAIN').HasReason)
  Wait-ForBrowserReview 'DEPENDENCY_BLOCKED_INITIAL_STATE'

  # Progress increases on authoritative completion and falls when reopened.
  Require-RpcSuccess 'START_PREDECESSOR' 'start_task' 'TEST-EMPLOYEE' (Rpc 'start_task' @{ p_task_id = $predecessor } 'TEST-EMPLOYEE') | Out-Null
  Require-RpcSuccess 'COMPLETE_PREDECESSOR' 'complete_task_productivity' 'TEST-EMPLOYEE' (Rpc 'complete_task_productivity' @{ p_task_id = $predecessor } 'TEST-EMPLOYEE') | Out-Null
  $afterComplete = Require-RpcSuccess 'PROGRESS_AFTER_COMPLETE' 'get_project_health' 'TEST-MANAGER' (Rpc 'get_project_health' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER')
  Mark 'completion_increases_progress' ([int]$afterComplete.progress_percent -eq 33)
  Require-RpcSuccess 'REOPEN_PREDECESSOR' 'change_task_status' 'TEST-EMPLOYEE' (Rpc 'change_task_status' @{ p_task_id = $predecessor; p_status = 'todo' } 'TEST-EMPLOYEE') | Out-Null
  $afterReopen = Require-RpcSuccess 'PROGRESS_AFTER_REOPEN' 'get_project_health' 'TEST-MANAGER' (Rpc 'get_project_health' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER')
  Mark 'reopen_decreases_progress' ([int]$afterReopen.progress_percent -eq 0 -and [int]$afterReopen.progress_percent -lt [int]$afterComplete.progress_percent)

  # Dependency-blocked, Waiting, Blocked, and their structured closure reasons.
  $blockedReadiness = Mark-ReadinessReason 'UNRESOLVED_DEPENDENCY_CHAIN'
  Mark 'dependency_blocked_closure_reason' (-not [bool]$blockedReadiness.Data.ready -and $blockedReadiness.HasReason)
  Require-RpcSuccess 'COMPLETE_PREDECESSOR_AGAIN' 'complete_task_productivity' 'TEST-EMPLOYEE' (Rpc 'complete_task_productivity' @{ p_task_id = $predecessor } 'TEST-EMPLOYEE') | Out-Null
  $progressRestored = Require-RpcSuccess 'PROGRESS_AFTER_RECOMPLETION' 'get_project_health' 'TEST-MANAGER' (Rpc 'get_project_health' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER')
  Mark 'predecessor_recompletion_restores_progress' ([int]$progressRestored.progress_percent -eq 33)
  Require-RpcSuccess 'WAIT_SUCCESSOR' 'mark_task_waiting' 'TEST-EMPLOYEE' (Rpc 'mark_task_waiting' @{ p_task_id = $successor; p_category = 'CLIENT'; p_related_user_id = $null; p_note = 'Synthetic Phase 1 waiting check' } 'TEST-EMPLOYEE') | Out-Null
  $waitingReadiness = Mark-ReadinessReason 'WAITING_TASKS'
  Mark 'waiting_closure_reason' (-not [bool]$waitingReadiness.Data.ready -and $waitingReadiness.HasReason)
  Wait-ForBrowserReview 'WAITING_STATE'
  Require-RpcSuccess 'RESUME_SUCCESSOR_FROM_WAITING' 'resume_task' 'TEST-EMPLOYEE' (Rpc 'resume_task' @{ p_task_id = $successor } 'TEST-EMPLOYEE') | Out-Null
  Require-RpcSuccess 'BLOCK_SUCCESSOR' 'mark_task_blocked' 'TEST-EMPLOYEE' (Rpc 'mark_task_blocked' @{ p_task_id = $successor; p_category = 'TECHNICAL_PROBLEM'; p_related_user_id = $null; p_note = 'Synthetic Phase 1 blocker check' } 'TEST-EMPLOYEE') | Out-Null
  $blockedStateReadiness = Mark-ReadinessReason 'BLOCKED_TASKS'
  Mark 'blocked_closure_reason' (-not [bool]$blockedStateReadiness.Data.ready -and $blockedStateReadiness.HasReason)
  $blockedManagerSummary = Require-RpcSuccess 'BLOCKED_MANAGER_AGGREGATE' 'get_project_operational_summary' 'TEST-MANAGER' (Rpc 'get_project_operational_summary' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER')
  $blockedEmployeeSummary = Require-RpcSuccess 'BLOCKED_EMPLOYEE_AGGREGATE' 'get_project_operational_summary' 'TEST-EMPLOYEE' (Rpc 'get_project_operational_summary' @{ p_project_id = $script:ProjectId } 'TEST-EMPLOYEE')
  $blockedHealth = Require-RpcSuccess 'BLOCKED_AUTHORITATIVE_HEALTH' 'get_project_health' 'TEST-MANAGER' (Rpc 'get_project_health' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER')
  $blockedDetail = Require-RpcSuccess 'BLOCKED_PROJECT_DETAIL' 'get_project_detail_secure' 'TEST-MANAGER' (Rpc 'get_project_detail_secure' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER')
  $blockedPortfolio = Require-RpcSuccess 'BLOCKED_PROJECT_PORTFOLIO' 'list_accessible_projects_secure' 'TEST-MANAGER' (Rpc 'list_accessible_projects_secure' @{} 'TEST-MANAGER')
  $blockedPortfolioRow = Get-ProjectRow $blockedPortfolio
  $blockedCommandCenter = Require-RpcSuccess 'BLOCKED_COMMAND_CENTER' 'list_project_command_center' 'TEST-MANAGER' (Rpc 'list_project_command_center' @{ p_limit = 500; p_only_attention = $false; p_upcoming_days = $null } 'TEST-MANAGER')
  $blockedCommandRow = @($blockedCommandCenter | Where-Object { [string]$_.project_id -eq $script:ProjectId }) | Select-Object -First 1
  Mark 'blocked_aggregate_equal_for_manager_and_employee' ((Get-AggregateSignature $blockedManagerSummary) -ceq (Get-AggregateSignature $blockedEmployeeSummary))
  Mark 'blocked_health_reasons_consistent_across_consumers' ((Same-OperationalState $blockedHealth $blockedManagerSummary) -and
      (Same-OperationalState $blockedPortfolioRow $blockedManagerSummary) -and
      (Same-OperationalState $blockedDetail.project $blockedManagerSummary) -and
      (Same-OperationalState $blockedCommandRow $blockedManagerSummary))
  Wait-ForBrowserReview 'BLOCKED_STATE'
  Require-RpcSuccess 'RESUME_SUCCESSOR_FROM_BLOCKED' 'resume_task' 'TEST-EMPLOYEE' (Rpc 'resume_task' @{ p_task_id = $successor } 'TEST-EMPLOYEE') | Out-Null

  # Complete successor and manager-only Task; Project must
  # remain active until the explicit lifecycle RPC.
  Require-RpcSuccess 'START_SUCCESSOR' 'start_task' 'TEST-EMPLOYEE' (Rpc 'start_task' @{ p_task_id = $successor } 'TEST-EMPLOYEE') | Out-Null
  Require-RpcSuccess 'COMPLETE_SUCCESSOR' 'complete_task_productivity' 'TEST-EMPLOYEE' (Rpc 'complete_task_productivity' @{ p_task_id = $successor } 'TEST-EMPLOYEE') | Out-Null
  Require-RpcSuccess 'COMPLETE_MANAGER_ONLY_TASK' 'complete_task_productivity' 'TEST-MANAGER' (Rpc 'complete_task_productivity' @{ p_task_id = $managerOnly } 'TEST-MANAGER') | Out-Null
  $ready = Mark-ReadinessReason 'NO_TASKS'
  Mark 'closure_ready_after_all_tasks_complete' ([bool]$ready.Data.ready -and -not $ready.HasReason)
  $stillActive = Require-RpcSuccess 'NO_AUTOMATIC_PROJECT_COMPLETION' 'get_project_detail_secure' 'TEST-MANAGER' (Rpc 'get_project_detail_secure' @{ p_project_id = $script:ProjectId } 'TEST-MANAGER')
  Mark 'project_not_auto_completed' ([string]$stillActive.project.lifecycle_status -eq 'ACTIVE')
  Wait-ForBrowserReview 'ALL_TASKS_COMPLETE_BEFORE_EXPLICIT_PROJECT_COMPLETION'
  $explicitComplete = Rpc 'change_project_status' @{ p_project_id = $script:ProjectId; p_status = 'COMPLETED' } 'TEST-MANAGER'
  Mark 'explicit_manager_project_completion' ($explicitComplete.Status -ge 200 -and $explicitComplete.Status -lt 300 -and $explicitComplete.Data.changed -eq $true)

  # Outsider behavior may be a denial or a secure empty result, never disclosure.
  $outsiderList = Rpc 'list_accessible_projects_secure' @{} 'TEST-OUTSIDER'
  $outsiderHealth = Rpc 'get_project_health' @{ p_project_id = $script:ProjectId } 'TEST-OUTSIDER'
  $outsiderSummary = Rpc 'get_project_operational_summary' @{ p_project_id = $script:ProjectId } 'TEST-OUTSIDER'
  $outsiderPortfolioLeaks = @($outsiderList.Data | Where-Object { [string]$_.id -eq $script:ProjectId }).Count -gt 0
  Mark 'outsider_project_list_denied_or_empty' (($outsiderList.Status -ge 400 -and -not $outsiderPortfolioLeaks) -or ($outsiderList.Status -ge 200 -and $outsiderList.Status -lt 300 -and -not $outsiderPortfolioLeaks))
  Mark 'outsider_known_project_health_denied_or_empty' (($outsiderHealth.Status -ge 400) -or ($outsiderHealth.Status -ge 200 -and $outsiderHealth.Status -lt 300 -and $null -eq $outsiderHealth.Data))
  Mark 'outsider_known_project_summary_denied_or_empty' (($outsiderSummary.Status -ge 400) -or ($outsiderSummary.Status -ge 200 -and $outsiderSummary.Status -lt 300 -and $null -eq $outsiderSummary.Data))
  $anonProject = Invoke-Http 'GET' ("/rest/v1/projects?id=eq.$script:ProjectId&select=id") $null $null -Anonymous
  Mark 'anonymous_project_rows_not_visible' (($anonProject.Status -ge 400) -or ($anonProject.Status -ge 200 -and $anonProject.Status -lt 300 -and @($anonProject.Data).Count -eq 0))
  Mark 'direct_table_and_legacy_conversion_catalog_guards' (Invoke-CatalogCheck)

  # Source guard plus existing static regression test cover archived exclusion.
  $migration = Get-Content -Raw -LiteralPath $MigrationPath
  $snapshot = [regex]::Match($migration, 'CREATE OR REPLACE FUNCTION public\.project_operational_snapshot[\s\S]*?-- The Client detail façade').Value
  Mark 'archived_task_exclusion_server_filter' ($snapshot -match 'WHERE task\.project_id = p_project_id[\s\S]*?AND task\.archived_at IS NULL')
}
catch {
  $exitFailure = $true
  Write-Output ('phase1_acceptance_error=' + $_.Exception.Message)
}
finally {
  try { Cleanup-SyntheticData } catch { $script:CleanupFailed = $true }
  if ($script:CleanupFailed) {
    Write-Output ('SYNTHETIC_CLEANUP_PROJECT_ID=' + $script:ProjectId)
    Write-Output ('SYNTHETIC_CLEANUP_TASK_IDS=' + ($script:TaskIds -join ','))
    Write-Output ('SYNTHETIC_CLEANUP_DEPENDENCY_ID=' + $script:DependencyId)
  }
  Mark 'synthetic_cleanup_succeeded' (-not $script:CleanupFailed)
  $script:Tokens.Clear()
  $script:RefreshTokens.Clear()
  $script:AnonKey = $null
  if ($null -eq $PreviousTelemetry) { Remove-Item Env:\SUPABASE_TELEMETRY_DISABLED -ErrorAction SilentlyContinue }
  else { $env:SUPABASE_TELEMETRY_DISABLED = $PreviousTelemetry }
}

foreach ($entry in $script:Results.GetEnumerator()) { Write-Output ($entry.Key + '=' + [bool]$entry.Value) }
Write-Output 'archived_task_exclusion_runtime=NOT_TESTED_NO_AUTHORIZED_PER_TASK_ARCHIVE_RPC'
Write-Output ('synthetic_project_marker=' + $(if ($script:ProjectId) { 'PHASE1 ACCEPTANCE fixture created and cleanup attempted' } else { 'not created' }))
if ($script:CleanupFailed) { Write-Output 'synthetic_cleanup=FAIL; stop and remove only the reported synthetic fixture through secure RPC/UI'; exit 1 }
if ($exitFailure -or @($script:Results.Values | Where-Object { -not $_ }).Count -gt 0) { Write-Output 'PROJECT OPERATIONS PHASE 1 STAGING ACCEPTANCE: FAIL'; exit 1 }
Write-Output ('PROJECT OPERATIONS PHASE 1 STAGING ACCEPTANCE: PASS (' + $TargetRef + ')')
