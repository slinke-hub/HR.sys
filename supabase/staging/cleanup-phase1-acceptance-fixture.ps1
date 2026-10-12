[CmdletBinding()]
param()

# Deletes only the explicitly identified Phase 1 acceptance fixture in staging.
# All mutations use existing authenticated application RPCs; no service role or
# direct table write is used.
$ErrorActionPreference = 'Stop'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$StagingOrigin = "https://$TargetRef.supabase.co"
$ProjectId = '622e3754-1299-4476-a49d-7b8d265325cc'
$TaskIds = @(
  '8e0d6455-4a77-41bb-aa14-228b924872c0',
  '90964021-d3e1-4510-a66f-798ae6d5e141',
  '6baaf0ce-36bf-43e7-880c-31debfa4fd72'
)
$DependencyId = '6867f78b-14d9-42c0-9720-c35c50a575be'
$ManagerEmail = 'test.manager@hrsys-staging.invalid'
$Root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$LinkPath = Join-Path $PSScriptRoot '..\.temp\project-ref'
$script:Tokens = @{ Access = $null; Refresh = $null }
$script:ManagerUserId = $null
$script:AnonKey = $null
$script:PlainPassword = $null
$script:SecurePassword = $null

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
  throw 'A valid staging public anon key is unavailable. No key value is displayed.'
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

function Protect-Diagnostic([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  $safe = ($Value -replace '\s+', ' ').Trim()
  $safe = $safe -replace '(?i)Bearer\s+\S+', 'Bearer [REDACTED]'
  $safe = $safe -replace '\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b', '[REDACTED TOKEN]'
  $safe = $safe -replace '(?i)(service[_ -]?role|anon[_ -]?key|access[_ -]?token|refresh[_ -]?token|password)\s*[:=]\s*[^ ,;]+', '$1=[REDACTED]'
  return $safe
}

function Invoke-Http([string]$Method, [string]$Path, $Body = $null, [switch]$Anonymous) {
  $headers = @{ apikey = $script:AnonKey; 'Content-Type' = 'application/json' }
  if ($Anonymous) { $headers.Authorization = "Bearer $script:AnonKey" }
  else { $headers.Authorization = "Bearer $($script:Tokens.Access)" }
  $parameters = @{ Method = $Method; Uri = ($StagingOrigin + $Path); Headers = $headers; UseBasicParsing = $true; ErrorAction = 'Stop' }
  if ($null -ne $Body) { $parameters.Body = ($Body | ConvertTo-Json -Depth 20 -Compress) }
  try {
    $response = Invoke-WebRequest @parameters
    $data = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$response.Content)) { try { $data = $response.Content | ConvertFrom-Json } catch { } }
    return [pscustomobject]@{ Status = [int]$response.StatusCode; Data = $data; Code = ''; Message = '' }
  } catch {
    $status = 0; $data = $null
    if ($_.Exception.Response) {
      try { $status = [int]$_.Exception.Response.StatusCode } catch { }
      try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $content = $reader.ReadToEnd(); $reader.Dispose()
        if ($content) { $data = $content | ConvertFrom-Json }
      } catch { }
    }
    $code = if ($data -and $data.code) { Protect-Diagnostic ([string]$data.code) } else { '' }
    $message = if ($data -and $data.message) { Protect-Diagnostic ([string]$data.message) } else { 'Request failed; response details unavailable.' }
    return [pscustomobject]@{ Status = $status; Data = $data; Code = $code; Message = $message }
  }
}

function Test-ManagerSession([string]$AccessToken, [string]$UserId) {
  $oldAccess = $script:Tokens.Access
  $script:Tokens.Access = $AccessToken
  try {
    $profile = Invoke-Http 'GET' '/rest/v1/profiles?employee_id=eq.TEST-MANAGER&select=id,employee_id,role,is_active'
    $rows = @($profile.Data)
    return ($profile.Status -ge 200 -and $profile.Status -lt 300 -and $rows.Count -eq 1 -and
      [string]$rows[0].id -ceq $UserId -and [string]$rows[0].employee_id -ceq 'TEST-MANAGER' -and
      [string]$rows[0].role -ceq 'MANAGER' -and $rows[0].is_active -eq $true)
  } finally { $script:Tokens.Access = $oldAccess }
}

function Sign-InManager {
  $script:SecurePassword = Read-Host 'Enter the existing TEST MANAGER password privately' -AsSecureString
  try {
    $script:PlainPassword = Convert-SecureStringToPlainText $script:SecurePassword
    $response = Invoke-Http 'POST' '/auth/v1/token?grant_type=password' @{ email = $ManagerEmail; password = $script:PlainPassword } -Anonymous
    if ($response.Status -lt 200 -or $response.Status -ge 300 -or -not $response.Data.access_token -or
        [string]$response.Data.user.email -ine $ManagerEmail -or -not $response.Data.refresh_token) {
      throw "TEST MANAGER staging sign-in failed (HTTP $($response.Status); code $($response.Code)). Credentials are not displayed."
    }
    $script:Tokens.Access = [string]$response.Data.access_token
    $script:Tokens.Refresh = [string]$response.Data.refresh_token
    $script:ManagerUserId = [string]$response.Data.user.id
    if (-not (Test-ManagerSession $script:Tokens.Access $script:ManagerUserId)) { throw 'Authenticated identity is not the active existing TEST-MANAGER profile.' }
  } finally {
    $script:PlainPassword = $null
    if ($script:SecurePassword) { $script:SecurePassword.Dispose(); $script:SecurePassword = $null }
  }
}

function Refresh-ManagerSession {
  if ([string]::IsNullOrWhiteSpace([string]$script:Tokens.Refresh)) { return $false }
  $response = Invoke-Http 'POST' '/auth/v1/token?grant_type=refresh_token' @{ refresh_token = $script:Tokens.Refresh } -Anonymous
  if ($response.Status -lt 200 -or $response.Status -ge 300 -or -not $response.Data.access_token -or
      [string]$response.Data.user.email -ine $ManagerEmail -or [string]$response.Data.user.id -cne $script:ManagerUserId -or
      -not $response.Data.refresh_token) { return $false }
  $script:Tokens.Access = [string]$response.Data.access_token
  $script:Tokens.Refresh = [string]$response.Data.refresh_token
  return (Test-ManagerSession $script:Tokens.Access $script:ManagerUserId)
}

function Ensure-ManagerSession([switch]$ForceRefresh) {
  if (-not $ForceRefresh -and -not [string]::IsNullOrWhiteSpace([string]$script:Tokens.Access)) {
    if (Test-ManagerSession $script:Tokens.Access) { return }
  }
  if (Refresh-ManagerSession) { return }
  Sign-InManager
}

function Invoke-Rpc([string]$Name, [hashtable]$Payload) {
  $response = Invoke-Http 'POST' ("/rest/v1/rpc/$Name") $Payload
  if ($response.Status -eq 401) {
    if (-not (Refresh-ManagerSession)) { Sign-InManager }
    $response = Invoke-Http 'POST' ("/rest/v1/rpc/$Name") $Payload
  }
  return $response
}

function Require-Read([string]$Name, [hashtable]$Payload) {
  $response = Invoke-Rpc $Name $Payload
  if ($response.Status -lt 200 -or $response.Status -ge 300) {
    throw "Preflight RPC $Name failed (HTTP $($response.Status); code $($response.Code); message $($response.Message))."
  }
  return $response.Data
}

function Invoke-CleanupRpc([string]$Name, [hashtable]$Payload) {
  $response = Invoke-Rpc $Name $Payload
  Write-Output ("cleanup_rpc=$Name;http_status=$($response.Status);code=$($response.Code);message=$($response.Message)")
  if ($response.Status -lt 200 -or $response.Status -ge 300 -or $response.Data -ne $true) {
    throw "Cleanup stopped after $Name did not confirm success. No later deletion step was attempted."
  }
}

function Clear-SensitiveMemory {
  $script:Tokens.Access = $null
  $script:Tokens.Refresh = $null
  $script:Tokens.Clear()
  $script:ManagerUserId = $null
  $script:AnonKey = $null
  $script:PlainPassword = $null
  if ($script:SecurePassword) { $script:SecurePassword.Dispose(); $script:SecurePassword = $null }
}

try {
  if (-not (Test-Path -LiteralPath $LinkPath -PathType Leaf)) { throw 'Missing supabase/.temp/project-ref; refusing cleanup.' }
  $linked = (Get-Content -Raw -LiteralPath $LinkPath).Trim()
  if ($linked -ceq $ProductionRef) { throw 'Production link detected; refusing cleanup.' }
  if ($linked -cne $TargetRef) { throw 'Linked project is not the required staging project; refusing cleanup.' }
  $script:AnonKey = Read-StagingAnonKey
  Sign-InManager

  # Read-only preflight: every ID and parent/edge relationship must match.
  $project = Require-Read 'get_project_detail_secure' @{ p_project_id = $ProjectId }
  if ([string]$project.project.id -cne $ProjectId) { throw 'The exact synthetic Project was not returned to TEST-MANAGER; refusing cleanup.' }
  foreach ($taskId in $TaskIds) {
    $task = Require-Read 'get_task_secure' @{ p_task_id = $taskId }
    if ($null -eq $task -or [string]$task.id -cne $taskId -or [string]$task.project_id -cne $ProjectId) {
      throw "Task $taskId is absent or belongs to a different Project; refusing cleanup."
    }
  }
  $dependencies = @(Require-Read 'list_task_dependencies_secure' @{ p_task_id = $TaskIds[0] })
  $matching = @($dependencies | Where-Object {
    [string]$_.dependency_id -ceq $DependencyId -and
    [string]$_.predecessor_task_id -ceq $TaskIds[0] -and
    [string]$_.successor_task_id -ceq $TaskIds[1]
  })
  if ($matching.Count -ne 1) { throw 'The exact dependency relationship was not uniquely verified; refusing cleanup.' }

  Write-Output "STAGING_TARGET=$TargetRef"
  Write-Output "FIXTURE_PROJECT=$ProjectId"
  Write-Output ("FIXTURE_TASKS=" + ($TaskIds -join ','))
  Write-Output "FIXTURE_DEPENDENCY=$DependencyId"
  $confirmation = Read-Host 'Type exactly CLEAN UP PHASE 1 ACCEPTANCE FIXTURE to continue'
  if ($confirmation -cne 'CLEAN UP PHASE 1 ACCEPTANCE FIXTURE') { throw 'Confirmation did not match; no fixture mutation was attempted.' }

  Ensure-ManagerSession -ForceRefresh
  Invoke-CleanupRpc 'remove_task_dependency' @{ p_dependency_id = $DependencyId }
  foreach ($taskId in @($TaskIds[2], $TaskIds[1], $TaskIds[0])) {
    Invoke-CleanupRpc 'delete_task_secure' @{ p_task_id = $taskId }
  }
  Invoke-CleanupRpc 'delete_project_secure' @{ p_project_id = $ProjectId }

  foreach ($taskId in $TaskIds) {
    $task = Require-Read 'get_task_secure' @{ p_task_id = $taskId }
    if ($null -ne $task) { throw "Post-cleanup verification found Task $taskId still accessible." }
  }
  $projectRows = @(Require-Read 'list_accessible_projects_secure' @{})
  if (@($projectRows | Where-Object { [string]$_.id -ceq $ProjectId }).Count -ne 0) {
    throw 'Post-cleanup verification found the synthetic Project still accessible.'
  }
  $remainingDependencies = @(Require-Read 'list_task_dependencies_secure' @{ p_task_id = $TaskIds[0] } |
    Where-Object { [string]$_.dependency_id -ceq $DependencyId })
  if ($remainingDependencies.Count -ne 0) { throw 'Post-cleanup verification found the synthetic dependency still accessible.' }
  Write-Output 'TARGETED_FIXTURE_CLEANUP=PASS'
} catch {
  Write-Output ('TARGETED_FIXTURE_CLEANUP=FAIL;message=' + (Protect-Diagnostic $_.Exception.Message))
  exit 1
} finally {
  Clear-SensitiveMemory
}
