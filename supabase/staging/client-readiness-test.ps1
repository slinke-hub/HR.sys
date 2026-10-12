$ErrorActionPreference = 'Stop'
$projectRef = 'jcfyyxsuspukcmybyhjj'
$base = "https://$projectRef.supabase.co"
$linked = (Get-Content -Raw (Join-Path $PSScriptRoot '..\.temp\project-ref')).Trim()
if ($linked -cne $projectRef) { throw "Refusing to test non-staging project: $linked" }

function Get-ApiKeys {
  $raw = supabase projects api-keys --project-ref $projectRef --reveal --output json 2>$null | Out-String
  $keys = $raw | ConvertFrom-Json
  return @{
    service = ($keys | Where-Object name -eq 'service_role' | Select-Object -First 1).api_key
    anon = ($keys | Where-Object name -eq 'anon' | Select-Object -First 1).api_key
  }
}
function New-Headers($key, $token = $null) {
  $h = @{ apikey = $key; Authorization = "Bearer $key"; 'Content-Type' = 'application/json'; Prefer = 'return=representation' }
  if ($token) { $h.Authorization = "Bearer $token" }
  return $h
}
function Invoke-Json($method, $url, $headers, $body = $null, $expectedFailure = $false) {
  try {
    $params = @{ Method = $method; Uri = $url; Headers = $headers; ErrorAction = 'Stop' }
    if ($null -ne $body) { $params.Body = ($body | ConvertTo-Json -Depth 20 -Compress) }
    $value = Invoke-RestMethod @params
    if ($expectedFailure) { throw "Expected failure but request succeeded: $method $url" }
    return $value
  } catch {
    if ($expectedFailure) { return $null }
    throw
  }
}
function New-RandomPassword {
  $bytes = New-Object byte[] 24
  [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  return ([Convert]::ToBase64String($bytes) + 'Aa9!')
}
function Sign-In($email, $password, $anon) {
  $result = Invoke-RestMethod -Method Post -Uri "$base/auth/v1/token?grant_type=password" -Headers (New-Headers $anon) -Body (@{ email=$email; password=$password } | ConvertTo-Json) -ErrorAction Stop
  return $result.access_token
}
function Rpc($name, $payload, $token, $anon, $expectedFailure = $false) {
  return Invoke-Json Post "$base/rest/v1/rpc/$name" (New-Headers $anon $token) $payload $expectedFailure
}
function Rest($method, $path, $payload, $token, $anon, $expectedFailure = $false) {
  return Invoke-Json $method "$base/rest/v1/$path" (New-Headers $anon $token) $payload $expectedFailure
}

$keys = Get-ApiKeys
if ([string]::IsNullOrWhiteSpace($keys.service) -or [string]::IsNullOrWhiteSpace($keys.anon)) { throw 'Staging API keys unavailable' }
$users = @{}
$emails = @{
  manager = 'test.manager@hrsys-staging.invalid'
  employee = 'test.employee@hrsys-staging.invalid'
  outsider = 'test.outsider@hrsys-staging.invalid'
}
$passwords = @{}
$originalProfiles = @{}
$clientId = $null
$deleteClientId = $null
$dealId = $null
$projectId = $null
$taskId = $null

try {
  $adminHeaders = New-Headers $keys.service
  $authUsers = Invoke-Json Get "$base/auth/v1/admin/users?per_page=100" $adminHeaders
  foreach ($kind in $emails.Keys) {
    $authUser = @($authUsers.users) | Where-Object { $_.email -eq $emails[$kind] } | Select-Object -First 1
    if (-not $authUser) { throw "Missing staging test user: $($emails[$kind])" }
    $users[$kind] = $authUser.id
    $profile = @(Invoke-Json Get "$base/rest/v1/profiles?id=eq.$($authUser.id)&select=*" $adminHeaders)
    if ($profile.Count -ne 1) { throw "Missing profile for $($emails[$kind])" }
    $originalProfiles[$kind] = @{ job_title=$profile[0].job_title; department_id=$profile[0].department_id; role=$profile[0].role }
    $passwords[$kind] = New-RandomPassword
    Invoke-Json Put "$base/auth/v1/admin/users/$($authUser.id)" $adminHeaders @{ password=$passwords[$kind]; email_confirm=$true } | Out-Null
  }

  $sales = @(Invoke-Json Get "$base/rest/v1/departments?name=ilike.*sales*&select=id&limit=1" $adminHeaders) | Select-Object -First 1
  if (-not $sales) { $sales = @(Invoke-Json Get "$base/rest/v1/departments?name_ar=ilike.*المبيعات*&select=id&limit=1" $adminHeaders) | Select-Object -First 1 }
  if (-not $sales) { throw 'No Sales department is available for the CRM-visible staging fixtures' }
  foreach ($kind in @('manager','employee')) {
    Rest Patch "profiles?id=eq.$($users[$kind])" @{ department_id=$sales.id; job_title='Sales Employee' } $null $keys.service | Out-Null
  }

  $tokens = @{}
  foreach ($kind in $emails.Keys) { $tokens[$kind] = Sign-In $emails[$kind] $passwords[$kind] $keys.anon }
  $results = [ordered]@{ staging_ref = ($linked -eq $projectRef) }

  Write-Output 'STEP=CLIENT_CREATE'
  $created = Rpc 'create_crm_client_secure' @{ p_client = @{ name='SECURITY TEST CLIENT'; company='HR.sys staging only'; email='client-test@hrsys-staging.invalid'; phone='0000000000'; status='ACTIVE' } } $tokens.manager $keys.anon
  $clientId = $created.id
  $results.manager_create = [bool]$clientId
  $results.manager_list = (@(Rpc 'list_crm_clients_secure' @{ p_search='SECURITY TEST CLIENT' } $tokens.manager $keys.anon | Where-Object { $_.id -eq $clientId }).Count -eq 1)
  $detail = Rpc 'get_crm_client_secure' @{ p_client_id=$clientId } $tokens.manager $keys.anon
  $results.manager_detail = ($detail.client.id -eq $clientId -and $null -ne $detail.deals -and $null -ne $detail.projects -and $null -ne $detail.tasks -and $null -ne $detail.activity)
  $updated = Rpc 'update_crm_client_secure' @{ p_client_id=$clientId; p_patch=@{ company='Updated staging company'; phone='1111111111' } } $tokens.manager $keys.anon
  $results.manager_update = ($updated.company -eq 'Updated staging company' -and $updated.phone -eq '1111111111')
  $results.manager_direct_insert_rejected = [bool](Rest Post 'crm_clients' @{ name='MANAGER DIRECT BYPASS' } $null $tokens.manager $keys.anon $true) -eq $false
  $results.manager_direct_update_rejected = [bool](Rest Patch "crm_clients?id=eq.$clientId" @{ name='MANAGER DIRECT BYPASS' } $tokens.manager $keys.anon $true) -eq $false
  $results.manager_direct_delete_rejected = [bool](Rest Delete "crm_clients?id=eq.$clientId" $null $tokens.manager $keys.anon $true) -eq $false

  Write-Output 'STEP=RELATED_RECORDS'
  $deal = Rest Post 'crm_deals' @{ title='SECURITY TEST CLIENT DEAL'; client_id=$clientId; stage='LEAD'; amount=321; assigned_to=$users.employee; created_by=$users.manager; first_contact_date='2026-09-28'; contact_method='EMAIL'; event_type='STAGING'; lead_source='TEST' } $null $keys.service | Select-Object -First 1
  $dealId = $deal.id
  $project = Rest Post 'projects' @{ project_name='SECURITY TEST CLIENT PROJECT'; project_type='EVENT'; project_category='Enterprise'; client_id=$clientId; deal_id=$dealId; source='MANUAL'; created_by=$users.manager; assigned_people=@($users.employee); client_name='SECURITY TEST CLIENT' } $null $keys.service | Select-Object -First 1
  $projectId = $project.id
  $task = Rest Post 'tasks' @{ title='SECURITY TEST CLIENT TASK'; created_by=$users.manager; assignee_id=$users.employee; assignee_ids=@($users.employee); project_id=$projectId; crm_deal_id=$dealId; status='TODO'; priority='medium' } $null $keys.service | Select-Object -First 1
  $taskId = $task.id
  Rest Post 'crm_deal_activity' @{ deal_id=$dealId; action='CLIENT_TEST_ACTIVITY'; actor_id=$users.manager; note='Staging-only Client activity' } $null $keys.service | Out-Null
  $detail = Rpc 'get_crm_client_secure' @{ p_client_id=$clientId } $tokens.manager $keys.anon
  $results.related_deal = (@($detail.deals | Where-Object { $_.id -eq $dealId }).Count -eq 1)
  $results.related_project = (@($detail.projects | Where-Object { $_.id -eq $projectId }).Count -eq 1)
  $results.related_task = (@($detail.tasks | Where-Object { $_.id -eq $taskId }).Count -eq 1)
  $results.activity = (@($detail.activity | Where-Object { $_.deal_id -eq $dealId }).Count -ge 1)

  Write-Output 'STEP=EMPLOYEE_ACCESS'
  $employeeDetail = Rpc 'get_crm_client_secure' @{ p_client_id=$clientId } $tokens.employee $keys.anon
  $results.employee_detail = ($employeeDetail.client.id -eq $clientId)
  $employeeUpdated = Rpc 'update_crm_client_secure' @{ p_client_id=$clientId; p_patch=@{ phone='2222222222' } } $tokens.employee $keys.anon
  $results.employee_update_permitted = ($employeeUpdated.phone -eq '2222222222')

  Write-Output 'STEP=OUTSIDER_SECURITY'
  $results.outsider_list_empty = (@(Rpc 'list_crm_clients_secure' @{ p_search='SECURITY TEST CLIENT' } $tokens.outsider $keys.anon | Where-Object { $_.id -eq $clientId }).Count -eq 0)
  $results.outsider_detail_rejected = [bool](Rpc 'get_crm_client_secure' @{ p_client_id=$clientId } $tokens.outsider $keys.anon $true) -eq $false
  $results.outsider_update_rejected = [bool](Rpc 'update_crm_client_secure' @{ p_client_id=$clientId; p_patch=@{ name='IDOR' } } $tokens.outsider $keys.anon $true) -eq $false
  $results.outsider_delete_rejected = [bool](Rpc 'delete_crm_client_secure' @{ p_client_id=$clientId } $tokens.outsider $keys.anon $true) -eq $false
  $directSelect = @(Rest Get "crm_clients?id=eq.$clientId&select=id,name" $null $tokens.outsider $keys.anon)
  $results.outsider_direct_select_empty = ($directSelect.Count -eq 0)
  $results.outsider_direct_insert_rejected = [bool](Rest Post 'crm_clients' @{ name='OUTSIDER BYPASS' } $null $tokens.outsider $keys.anon $true) -eq $false
  $results.outsider_direct_update_rejected = [bool](Rest Patch "crm_clients?id=eq.$clientId" @{ name='OUTSIDER BYPASS' } $tokens.outsider $keys.anon $true) -eq $false
  $results.outsider_direct_delete_rejected = [bool](Rest Delete "crm_clients?id=eq.$clientId" $null $tokens.outsider $keys.anon $true) -eq $false
  $results.outsider_relationship_insert_rejected = [bool](Rest Post 'crm_deals' @{ title='OUTSIDER RELATIONSHIP BYPASS'; client_id=$clientId; first_contact_date='2026-09-28'; contact_method='EMAIL' } $null $tokens.outsider $keys.anon $true) -eq $false

  Write-Output 'STEP=MANAGER_DELETE'
  $deleteClient = Rpc 'create_crm_client_secure' @{ p_client = @{ name='SECURITY TEST CLIENT DELETE'; company='HR.sys staging only' } } $tokens.manager $keys.anon
  $deleteClientId = $deleteClient.id
  $results.manager_delete = (Rpc 'delete_crm_client_secure' @{ p_client_id=$deleteClientId } $tokens.manager $keys.anon) -eq $true

  [pscustomobject]@{ results=$results; fixture_client_id=$clientId; fixture_deal_id=$dealId; fixture_project_id=$projectId; fixture_task_id=$taskId } | ConvertTo-Json -Depth 10
} finally {
  if ($taskId) { try { Rest Delete "tasks?id=eq.$taskId" $null $null $keys.service | Out-Null } catch {} }
  if ($projectId) { try { Rest Delete "projects?id=eq.$projectId" $null $null $keys.service | Out-Null } catch {} }
  if ($dealId) { try { Rest Delete "crm_deals?id=eq.$dealId" $null $null $keys.service | Out-Null } catch {} }
  foreach ($id in @($clientId,$deleteClientId) | Where-Object { $_ }) { try { Rest Delete "crm_clients?id=eq.$id" $null $null $keys.service | Out-Null } catch {} }
  foreach ($kind in @('manager','employee')) {
    if ($users[$kind] -and $originalProfiles[$kind]) {
      try { Rest Patch "profiles?id=eq.$($users[$kind])" $originalProfiles[$kind] $null $keys.service | Out-Null } catch {}
    }
  }
}
