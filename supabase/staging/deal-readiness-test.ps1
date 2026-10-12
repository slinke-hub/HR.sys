$ErrorActionPreference = 'Stop'
$projectRef = 'jcfyyxsuspukcmybyhjj'
$base = "https://$projectRef.supabase.co"
$linked = (Get-Content -Raw (Join-Path $PSScriptRoot '..\.temp\project-ref')).Trim()
if ($linked -cne $projectRef) { throw "Refuse to test non-staging project: $linked" }

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
function Rpc($name, $payload, $token, $anon) {
  return Invoke-Json Post "$base/rest/v1/rpc/$name" (New-Headers $anon $token) $payload
}
function Rest($method, $path, $payload, $token, $anon, $expectedFailure = $false) {
  return Invoke-Json $method "$base/rest/v1/$path" (New-Headers $anon $token) $payload $expectedFailure
}
function SignedUrl($bucket, $path, $token, $expiresIn = 60) {
  return Invoke-Json Post "$base/functions/v1/file-signed-url" (New-Headers $keys.anon $token) @{ bucket=$bucket; path=$path; expiresIn=$expiresIn }
}

$keys = Get-ApiKeys
if ([string]::IsNullOrWhiteSpace($keys.service) -or [string]::IsNullOrWhiteSpace($keys.anon)) { throw 'Staging API keys unavailable' }
$adminHeaders = New-Headers $keys.service
$users = @{}
$profiles = @{}
$emails = @{
  manager = 'test.manager@hrsys-staging.invalid'
  employee = 'test.employee@hrsys-staging.invalid'
  outsider = 'test.outsider@hrsys-staging.invalid'
}
$passwords = @{}
$originalProfiles = @{}

try {
  $authUsers = Invoke-Json Get "$base/auth/v1/admin/users?per_page=100" $adminHeaders
  foreach ($kind in $emails.Keys) {
    $authUser = @($authUsers.users) | Where-Object { $_.email -eq $emails[$kind] } | Select-Object -First 1
    if (-not $authUser) { throw "Missing staging test user: $($emails[$kind])" }
    $users[$kind] = $authUser.id
    $profile = @(Invoke-Json Get "$base/rest/v1/profiles?id=eq.$($authUser.id)&select=*" $adminHeaders)
    if ($profile.Count -ne 1) { throw "Missing profile for $($emails[$kind])" }
    $profiles[$kind] = $profile[0]
    $originalProfiles[$kind] = @{ job_title=$profile[0].job_title; department_id=$profile[0].department_id; role=$profile[0].role }
    $passwords[$kind] = New-RandomPassword
    Invoke-Json Put "$base/auth/v1/admin/users/$($authUser.id)" $adminHeaders @{ password=$passwords[$kind]; email_confirm=$true } | Out-Null
  }

  # Keep roles unchanged, but temporarily place the two authorized fixtures in
  # a CRM-visible Sales department for authenticated Deal workflow coverage.
  $sales = @(Invoke-Json Get "$base/rest/v1/departments?name=ilike.*sales*&select=id&limit=1" $adminHeaders) | Select-Object -First 1
  if (-not $sales) { $sales = @(Invoke-Json Get "$base/rest/v1/departments?name_ar=ilike.*المبيعات*&select=id&limit=1" $adminHeaders) | Select-Object -First 1 }
  if ($sales) {
    foreach ($kind in @('manager','employee')) {
      $temporaryTitle = 'Sales Employee'
      Rest Patch "profiles?id=eq.$($users[$kind])" @{ department_id=$sales.id; job_title=$temporaryTitle } $null $keys.service | Out-Null
    }
  }

  $tokens = @{}
  foreach ($kind in $emails.Keys) { $tokens[$kind] = Sign-In $emails[$kind] $passwords[$kind] $keys.anon }
  $results = [ordered]@{}
  $results.staging_ref = ($linked -eq $projectRef)

  Write-Output 'STEP=CREATE_CLIENT'
  $client = Rest Post 'crm_clients' @{ name='SECURITY TEST DEAL CLIENT'; company='HR.sys staging only'; email='deal-test@hrsys-staging.invalid'; status='ACTIVE' } $null $keys.service | Select-Object -First 1
  Write-Output ("CLIENT_RESPONSE=" + (($client | ConvertTo-Json -Depth 4 -Compress)))
  $clientId = $client.id
  Write-Output "CLIENT_ID_PRESENT=$([bool]$clientId)"
  $baseDeal = @{ title='SECURITY TEST DEAL'; client_id=$clientId; stage='LEAD'; amount=12345; assigned_to=$users.employee; first_contact_date='2026-09-28'; contact_method='EMAIL'; event_type='STAGING'; lead_source='TEST'; created_by=$users.manager }
  Write-Output 'STEP=CREATE_FIXTURE_DEAL'
  $fixture = Rest Post 'crm_deals' $baseDeal $null $keys.service | Select-Object -First 1
  $fixtureId = $fixture.id

  Write-Output 'STEP=CREATE_DEAL_RPC'
  $created = Rpc 'create_crm_deal_secure' @{ p_deal = @{ title='SECURITY TEST DEAL CREATED'; client_id=$clientId; amount=111; assigned_to=$users.employee; first_contact_date='2026-09-28'; contact_method='EMAIL'; event_type='STAGING' } } $tokens.manager $keys.anon
  $createdId = $created.id
  $results.manager_create = [bool]$createdId
  $results.manager_list = [bool](@(Rpc 'list_crm_deals_secure' @{} $tokens.manager $keys.anon | Where-Object { $_.id -eq $createdId }).Count -eq 1)
  $detail = Rpc 'get_crm_deal_secure' @{ p_deal_id=$createdId } $tokens.manager $keys.anon
  $results.manager_detail = ($detail.id -eq $createdId)
  $updated = Rpc 'update_crm_deal_secure' @{ p_deal_id=$createdId; p_patch=@{ technical_description='Updated by staging manager' } } $tokens.manager $keys.anon
  $results.manager_update = ($updated.technical_description -eq 'Updated by staging manager')
  $assigned = Rpc 'assign_crm_deal_secure' @{ p_deal_id=$createdId; p_assignee_id=$users.employee } $tokens.manager $keys.anon
  $results.manager_assign = ($assigned.assigned_to -eq $users.employee)
  $employeeDetail = Rpc 'get_crm_deal_secure' @{ p_deal_id=$createdId } $tokens.employee $keys.anon
  $results.employee_assigned_detail = ($employeeDetail.id -eq $createdId)
  $stage = Rpc 'change_crm_deal_stage' @{ p_deal_id=$createdId; p_new_stage='QUALIFICATION' } $tokens.employee $keys.anon
  $results.employee_stage_change = ($stage.to_stage -eq 'QUALIFICATION')
  $activity = @(Rpc 'list_crm_deal_activity_secure' @{ p_deal_id=$createdId } $tokens.manager $keys.anon)
  $results.activity = ($activity.Count -ge 3)

  $lost = Rpc 'mark_crm_deal_lost' @{ p_deal_id=$fixtureId; p_reason='Staging security test' } $tokens.employee $keys.anon
  $results.lost = ($lost.to_stage -eq 'LOST')
  $lostEdit = $false
  try { Rpc 'update_crm_deal_secure' @{ p_deal_id=$fixtureId; p_patch=@{ title='Should be rejected' } } $tokens.employee $keys.anon | Out-Null } catch { $lostEdit = $true }
  $results.lost_read_only = $lostEdit

  # Attachment registration/listing/download is tested with a real private
  # storage object, while the row itself is created only through the RPC.
  $attachmentPath = "$createdId/deal-readiness-test.txt"
  Write-Output 'STEP=ATTACHMENT_UPLOAD'
  $storageHeaders = New-Headers $keys.anon $tokens.manager
  $storageHeaders['Content-Type'] = 'text/plain'
  Invoke-RestMethod -Method Post -Uri "$base/storage/v1/object/crm-deal-files/$attachmentPath" -Headers $storageHeaders -Body ([Text.Encoding]::UTF8.GetBytes('HR.sys staging Deal attachment')) -ErrorAction Stop | Out-Null
  $attachment = Rpc 'register_crm_deal_attachment_secure' @{
    p_deal_id=$createdId; p_category='OTHER'; p_file_name='deal-readiness-test.txt'
    p_file_url="storage://crm-deal-files/$attachmentPath"; p_description='Temporary staging attachment'
    p_file_type='text/plain'; p_file_size=31; p_visible_to_project_assignee=$false
  } $tokens.manager $keys.anon
  $attachmentId = $attachment.id
  Write-Output 'STEP=ATTACHMENT_REGISTERED'
  $results.attachment_register = [bool]$attachmentId
  $listedAttachments = @(Rpc 'list_crm_deal_attachments_secure' @{ p_deal_id=$createdId } $tokens.manager $keys.anon)
  $results.attachment_list = [bool](@($listedAttachments | Where-Object { $_.id -eq $attachmentId }).Count -eq 1)
  $signed = SignedUrl 'crm-deal-files' $attachmentPath $tokens.manager 60
  Write-Output 'STEP=ATTACHMENT_SIGNED'
  $results.attachment_signed_url = [bool]$signed
  $outsiderSignedRejected = $false
  try {
    $outsiderSigned = SignedUrl 'crm-deal-files' $attachmentPath $tokens.outsider 60
    $signedUrl = $outsiderSigned.signedUrl
    if ($signedUrl) {
      try { Invoke-RestMethod -Method Get -Uri $signedUrl -ErrorAction Stop | Out-Null } catch { $outsiderSignedRejected = $true }
    } else { $outsiderSignedRejected = $true }
  } catch { $outsiderSignedRejected = $true }
  $results.outsider_attachment_denied = $outsiderSignedRejected
  $archiveCount = Rpc 'archive_crm_deal_attachments' @{ p_deal_id=$createdId; p_categories=@('OTHER'); p_keep_ids=@() } $tokens.manager $keys.anon
  $results.attachment_archive = ([int]$archiveCount -eq 1)

  # Approval unanimity and Deal -> Project conversion use the existing
  # authoritative workflow RPCs; no direct status mutation is used.
  $approvalFixture = Rest Post 'crm_deals' (@{ title='SECURITY TEST APPROVAL DEAL'; client_id=$clientId; stage='LEAD'; amount=500; assigned_to=$users.employee; first_contact_date='2026-09-28'; contact_method='EMAIL'; event_type='STAGING'; created_by=$users.manager } ) $null $keys.service | Select-Object -First 1
  Write-Output 'STEP=APPROVAL_FIXTURE'
  $approvalDealId = $approvalFixture.id
  Rpc 'start_deal_approval' @{ p_deal_id=$approvalDealId; p_marketing_manager=$users.manager; p_general_manager=$users.employee; p_operations_manager=$users.manager } $tokens.manager $keys.anon | Out-Null
  Write-Output 'STEP=APPROVAL_STARTED'
  $approvalSteps = @(Rest Get "crm_deal_approval_steps?deal_id=eq.$approvalDealId&select=id,step_order,approver_id&order=step_order" $null $tokens.manager $keys.anon)
  Write-Output "APPROVAL_STEPS=$($approvalSteps.Count)"
  $results.approval_started = ($approvalSteps.Count -eq 3)
  foreach ($step in $approvalSteps) {
    $actor = if ($step.approver_id -eq $users.employee) { 'employee' } else { 'manager' }
    Rpc 'decide_deal_approval' @{ p_step_id=$step.id; p_decision='APPROVED'; p_note=$null } $tokens[$actor] $keys.anon | Out-Null
  }
  Write-Output 'STEP=APPROVAL_DECISIONS_DONE'
  $approved = Rpc 'get_crm_deal_secure' @{ p_deal_id=$approvalDealId } $tokens.manager $keys.anon
  $results.approval_completed = ($approved.workflow_status -eq 'APPROVED' -and $approved.stage -eq 'NEGOTIATION')
  $order = @{ event_date='2026-10-02'; event_end_date='2026-10-03'; event_start_time='10:00'; client=@{ name='SECURITY TEST DEAL CLIENT'; company='HR.sys staging only'; email='deal-test@hrsys-staging.invalid'; phone='0000000000' }; installation_type='INDOOR'; assigned_people=@($users.employee); location_text='Staging only'; notes='Temporary security verification' }
  $projectId = Rpc 'create_project_from_won_deal_v2' @{ p_deal_id=$approvalDealId; p_order=$order } $tokens.manager $keys.anon
  $results.deal_to_project = [bool]$projectId
  $projectRows = @(Rest Get "projects?id=eq.$projectId&select=id,deal_id,client_id,assigned_people" $null $null $keys.service | Select-Object -First 1)
  $results.project_relationship = ($projectRows.Count -eq 1 -and $projectRows[0].deal_id -eq $approvalDealId -and $projectRows[0].client_id -eq $clientId)
  $projectIdAgain = Rpc 'create_project_from_won_deal_v2' @{ p_deal_id=$approvalDealId; p_order=$order } $tokens.manager $keys.anon
  $projectCount = @(Rest Get "projects?deal_id=eq.$approvalDealId&select=id" $null $null $keys.service)
  $results.project_duplicate_prevented = ($projectIdAgain -eq $projectId -and $projectCount.Count -eq 1)

  $bypassInsert = $false
  try { Rest Post 'crm_deals' @{ title='BYPASS'; client_id=$clientId; first_contact_date='2026-09-28'; contact_method='EMAIL'; assigned_to=$users.employee } $tokens.employee $keys.anon | Out-Null } catch { $bypassInsert = $true }
  $results.direct_insert_rejected = $bypassInsert
  $bypassUpdate = $false
  try { Rest Patch "crm_deals?id=eq.$createdId" @{ title='BYPASS' } $tokens.employee $keys.anon | Out-Null } catch { $bypassUpdate = $true }
  $results.direct_update_rejected = $bypassUpdate
  $outsiderList = @(Rpc 'list_crm_deals_secure' @{} $tokens.outsider $keys.anon)
  $results.outsider_list_empty = ($outsiderList.Count -eq 0)
  $outsiderDetailRejected = $false
  try { Rpc 'get_crm_deal_secure' @{ p_deal_id=$createdId } $tokens.outsider $keys.anon | Out-Null } catch { $outsiderDetailRejected = $true }
  $results.outsider_detail_rejected = $outsiderDetailRejected
  $outsiderUpdateRejected = $false
  try { Rpc 'update_crm_deal_secure' @{ p_deal_id=$createdId; p_patch=@{ title='IDOR' } } $tokens.outsider $keys.anon | Out-Null } catch { $outsiderUpdateRejected = $true }
  $results.outsider_update_rejected = $outsiderUpdateRejected
  $outsiderDirectUpdateRejected = $false
  try { Rest Patch "crm_deals?id=eq.$createdId" @{ title='OUTSIDER BYPASS' } $tokens.outsider $keys.anon | Out-Null } catch { $outsiderDirectUpdateRejected = $true }
  $results.outsider_direct_update_rejected = $outsiderDirectUpdateRejected
  $anonRejected = $false
  try { Invoke-Json Post "$base/rest/v1/rpc/get_crm_deal_secure" (New-Headers $keys.anon) @{p_deal_id=$createdId} $null $false | Out-Null } catch { $anonRejected = $true }
  $results.anonymous_rpc_rejected = $anonRejected

  $deleteRejected = $false
  try { Rpc 'delete_crm_deal' @{ p_deal_id=$createdId } $tokens.employee $keys.anon | Out-Null } catch { $deleteRejected = $true }
  $results.employee_delete_rejected = $deleteRejected

  # Exercise the existing leadership-only deletion path with a temporary title override.
  $privilegedDeleteDeal = Rest Post 'crm_deals' @{ title='SECURITY TEST PRIVILEGED DELETE'; client_id=$clientId; stage='LEAD'; amount=25; assigned_to=$users.employee; created_by=$users.manager; first_contact_date='2026-09-28'; contact_method='EMAIL'; event_type='STAGING'; lead_source='TEST' } $null $keys.service | Select-Object -First 1
  $managerPrivilegedDelete = $false
  try {
    Rest Patch "profiles?id=eq.$($users.manager)" @{ role='ADMIN' } $null $keys.service | Out-Null
    Rpc 'delete_crm_deal' @{ p_deal_id=$privilegedDeleteDeal.id } $tokens.manager $keys.anon | Out-Null
    $managerPrivilegedDelete = $true
  } catch { $managerPrivilegedDelete = $false }
  $results.manager_privileged_delete = $managerPrivilegedDelete
  try { Rest Patch "profiles?id=eq.$($users.manager)" @{ role=$originalProfiles.manager.role } $null $keys.service | Out-Null } catch {}

  [pscustomobject]@{ results = $results; fixture_client_id=$clientId; fixture_deal_ids=@($fixtureId,$createdId) } | ConvertTo-Json -Depth 8
} finally {
  # Service-role cleanup is limited to clearly labelled temporary records.
  if ($clientId) {
    if ($projectId) { try { Rest Delete "projects?id=eq.$projectId" $null $null $keys.service | Out-Null } catch {} }
    if ($attachmentPath) { try { Invoke-RestMethod -Method Delete -Uri "$base/storage/v1/object/crm-deal-files" -Headers (New-Headers $keys.service) -Body (@{ prefixes=@($attachmentPath) } | ConvertTo-Json) -ErrorAction Stop | Out-Null } catch {} }
    try { Rest Delete "crm_deals?client_id=eq.$clientId" $null $null $keys.service | Out-Null } catch {}
    try { Rest Delete "crm_clients?id=eq.$clientId" $null $null $keys.service | Out-Null } catch {}
  }
  foreach ($kind in @('manager','employee')) {
    if ($users[$kind] -and $originalProfiles[$kind]) {
      try { Rest Patch "profiles?id=eq.$($users[$kind])" $originalProfiles[$kind] $null $keys.service | Out-Null } catch {}
    }
  }
}
