$ErrorActionPreference = 'Stop'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$linked = (Get-Content -Raw (Join-Path $PSScriptRoot '..\.temp\project-ref')).Trim()
if ($linked -cne $TargetRef -or $linked -ceq $ProductionRef) { throw "Refusing non-staging target: $linked" }

function Get-Keys {
  $raw = supabase projects api-keys --project-ref $TargetRef --reveal --output json 2>$null | Out-String
  $keys = $raw | ConvertFrom-Json
  return @{ service = ($keys | Where-Object name -eq service_role | Select-Object -First 1).api_key; anon = ($keys | Where-Object name -eq anon | Select-Object -First 1).api_key }
}
function Headers($key, $token = $null) {
  $h = @{ apikey=$key; Authorization="Bearer $key"; 'Content-Type'='application/json'; Prefer='return=representation' }
  if ($token) { $h.Authorization = "Bearer $token" }
  return $h
}
function Call($method, $url, $headers, $body = $null, $expectFailure = $false) {
  try {
    $params = @{ Method=$method; Uri=$url; Headers=$headers; ErrorAction='Stop' }
    if ($null -ne $body) { $params.Body = ($body | ConvertTo-Json -Depth 20 -Compress) }
    $result = Invoke-RestMethod @params
    if ($expectFailure) { throw "Expected failure but request succeeded: $method $url" }
    return $result
  } catch {
    if ($expectFailure) { return $null }
    throw "Request failed: $method $url :: $($_.ErrorDetails.Message)"
  }
}
function Rpc($name, $payload, $token, $anon) { Call POST "https://$TargetRef.supabase.co/rest/v1/rpc/$name" (Headers $anon $token) $payload }
function Signed-Url($bucket, $path, $token, $expiresIn = 60, $expectFailure = $false) {
  Call POST "$base/functions/v1/file-signed-url" (Headers $keys.anon $token) @{bucket=$bucket;path=$path;expiresIn=$expiresIn} $expectFailure
}
function New-Password { $b=New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Fill($b); return ([Convert]::ToBase64String($b)+'Aa9!') }
function Sign-In($email, $password, $anon) { (Call POST "https://$TargetRef.supabase.co/auth/v1/token?grant_type=password" (Headers $anon) @{email=$email;password=$password}).access_token }
function Signed-UrlWithinCap($response) {
  try {
    $item = @($response) | Select-Object -First 1
    $url = $item.signedURL
    if (-not $url) { $url = $item.signedUrl }
    if (-not $url) { return $false }
    if ($url.StartsWith('/')) { $url = "$base$url" }
    $token = ([Uri]$url).Query -replace '^.*[?&]token=', ''
    $token = ($token -split '&')[0]
    $payload = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
    while (($payload.Length % 4) -ne 0) { $payload += '=' }
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    return ([int64]$claims.exp - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -le 301
  } catch { return $false }
}

$base = "https://$TargetRef.supabase.co"
$keys = Get-Keys
if ([string]::IsNullOrWhiteSpace($keys.service) -or [string]::IsNullOrWhiteSpace($keys.anon)) { throw 'Staging API keys unavailable.' }
$admin = Headers $keys.service
$emails = @('test.manager@hrsys-staging.invalid','test.employee@hrsys-staging.invalid','test.outsider@hrsys-staging.invalid')
$tokens = @{}
$ids = @{}
$passwords = @{}
$tempProject = $tempTask = $tempContract = $null
$tempObjectPaths = @()
$results = [ordered]@{}
function Mark($name, $value) { $script:results[$name] = [bool]$value }

try {
  $auth = Call GET "$base/auth/v1/admin/users?per_page=100" $admin
  foreach ($email in $emails) {
    $u = @($auth.users) | Where-Object email -eq $email | Select-Object -First 1
    if (-not $u) { throw "Missing staging test identity: $email" }
    $ids[$email] = $u.id
    $passwords[$email] = New-Password
    Call PUT "$base/auth/v1/admin/users/$($u.id)" $admin @{password=$passwords[$email];email_confirm=$true}|Out-Null
    $tokens[$email] = Sign-In $email $passwords[$email] $keys.anon
  }
  Mark authenticated_test_logins ($tokens.Count -eq 3)

  $manager = $tokens[$emails[0]]; $employee = $tokens[$emails[1]]; $outsider = $tokens[$emails[2]]
  $project = Rpc 'create_project_secure' @{p_project=@{project_name='SECURITY TEST FILE PROJECT';project_type='EVENT';description='Temporary Files readiness fixture';assigned_people=@($ids[$emails[1]]);project_manager_id=$ids[$emails[0]];project_category='Enterprise'}} $manager $keys.anon
  $tempProject = $project.id
  $task = Rpc 'create_task_secure' @{p_payload=@{title='SECURITY TEST FILE TASK';description='Temporary Files readiness fixture';project_id=$tempProject;assignee_ids=@($ids[$emails[1]]);priority='medium';category='General';visibility='public'}} $manager $keys.anon
  $tempTask = $task.id
  Mark synthetic_task_project_created ([bool]$tempTask -and [bool]$tempProject)

  $taskPath = "$tempTask/$($ids[$emails[0]])/file-readiness.txt"; $tempObjectPaths += @{bucket='task-attachments';path=$taskPath}
  $bytes = [Text.Encoding]::UTF8.GetBytes('synthetic staging file')
  $taskUploadHeaders = Headers $keys.anon $manager; $taskUploadHeaders['Content-Type'] = 'text/plain'
  $taskUpload = Call POST "$base/storage/v1/object/task-attachments/$taskPath" $taskUploadHeaders $bytes
  $registered = Rpc 'register_task_attachment' @{p_task_id=$tempTask;p_file_url="storage://task-attachments/$taskPath";p_file_name='file-readiness.txt';p_file_type='text/plain';p_file_size=$bytes.Length;p_attachment_scope='TASK';p_visible=$true} $manager $keys.anon
  Mark manager_upload_register ([bool]$registered)
  $managerSigned = Signed-Url 'task-attachments' $taskPath $manager 3600
  Mark signed_url_max_lifetime (Signed-UrlWithinCap $managerSigned)
  $largeSigned = Signed-Url 'task-attachments' $taskPath $manager 2147483647
  Mark signed_url_large_expiration_capped (Signed-UrlWithinCap $largeSigned)
  Signed-Url 'task-attachments' $taskPath $null 60 $true | Out-Null
  Mark signed_url_missing_auth_rejected $true
  Signed-Url 'contract-documents' $taskPath $manager 60 $true | Out-Null
  Mark signed_url_parent_bucket_mismatch_rejected $true
  Mark employee_task_attachment_list (@(Rpc 'list_task_attachments_secure' @{p_task_id=$tempTask;p_scope='TASK'} $employee $keys.anon).Count -gt 0)
  $outsiderStorage = Signed-Url 'task-attachments' $taskPath $outsider 60 $true
  Mark outsider_signed_url_rejected ($null -eq $outsiderStorage)
  $outsiderRpc = Call POST "$base/rest/v1/rpc/list_task_attachments_secure" (Headers $keys.anon $outsider) @{p_task_id=$tempTask;p_scope='TASK'} $null $true
  Mark outsider_task_attachment_rejected ($null -eq $outsiderRpc)
  $blockedUploadHeaders = Headers $keys.anon $outsider; $blockedUploadHeaders['Content-Type'] = 'application/x-msdownload'
  Call POST "$base/storage/v1/object/task-attachments/$tempTask/$($ids[$emails[2]])/blocked.exe" $blockedUploadHeaders ([Text.Encoding]::UTF8.GetBytes('blocked')) $true | Out-Null
  Mark outsider_storage_upload_rejected $true
  $outsiderStorageHeaders = Headers $keys.anon $outsider; $outsiderStorageHeaders['Content-Type'] = 'text/plain'
  Call PUT "$base/storage/v1/object/task-attachments/$taskPath" $outsiderStorageHeaders $bytes $true | Out-Null
  Call DELETE "$base/storage/v1/object/task-attachments/$taskPath" (Headers $keys.anon $outsider) $null $true | Out-Null
  Mark outsider_storage_update_delete_rejected $true
  Call POST "$base/rest/v1/rpc/register_task_attachment" (Headers $keys.anon $manager) @{p_task_id=$tempTask;p_file_url="storage://task-attachments/$taskPath";p_file_name='blocked.exe';p_file_type='application/x-msdownload';p_file_size=1;p_attachment_scope='TASK';p_visible=$false} $true | Out-Null
  Mark malicious_metadata_rejected $true
  Call POST "$base/rest/v1/task_attachments" (Headers $keys.anon $outsider) @{task_id=$tempTask;user_id=$ids[$emails[2]];file_url="storage://task-attachments/$taskPath";file_name='idor.txt';file_type='text/plain';file_size=1} $true | Out-Null
  Mark outsider_direct_table_write_rejected $true

  # Contract and HR bucket checks use a service-seeded synthetic object only;
  # no real employee data is touched and the objects are removed in finally.
  $contract = Call POST "$base/rest/v1/contracts" $admin @{employee_id=$ids[$emails[1]];contract_type='staging-test';status='Active'}
  $tempContract = $contract.id
  $contractPath = "$($ids[$emails[1]])/file-readiness-contract.pdf"; $tempObjectPaths += @{bucket='contract-documents';path=$contractPath}
  $contractUploadHeaders = Headers $keys.service; $contractUploadHeaders['Content-Type'] = 'application/pdf'; $contractUploadHeaders['x-upsert'] = 'true'
  Call POST "$base/storage/v1/object/contract-documents/$contractPath" $contractUploadHeaders ([Text.Encoding]::UTF8.GetBytes('synthetic contract object')) | Out-Null
  Call POST "$base/rest/v1/contract_documents" $admin @{contract_id=$tempContract;employee_id=$ids[$emails[1]];file_name='file-readiness-contract.pdf';file_url="storage://contract-documents/$contractPath"}|Out-Null
  $employeeContractUrl = Signed-Url 'contract-documents' $contractPath $employee 60
  Mark employee_contract_file_access ([bool]$employeeContractUrl)
  Signed-Url 'contract-documents' $contractPath $outsider 60 $true | Out-Null
  Mark outsider_contract_file_rejected $true
  $hrPath = "$($ids[$emails[1]])/file-readiness-hr.pdf"; $tempObjectPaths += @{bucket='hr-documents';path=$hrPath}
  $hrUploadHeaders = Headers $keys.service; $hrUploadHeaders['Content-Type'] = 'application/pdf'; $hrUploadHeaders['x-upsert'] = 'true'
  Call POST "$base/storage/v1/object/hr-documents/$hrPath" $hrUploadHeaders ([Text.Encoding]::UTF8.GetBytes('synthetic HR object')) | Out-Null
  $employeeHrUrl = Signed-Url 'hr-documents' $hrPath $employee 60
  Mark employee_hr_file_access ([bool]$employeeHrUrl)
  Signed-Url 'hr-documents' $hrPath $outsider 60 $true | Out-Null
  Mark outsider_hr_file_rejected $true
} finally {
  foreach ($object in $tempObjectPaths) { try { Call DELETE "$base/storage/v1/object/$($object.bucket)/$($object.path)" $admin $null | Out-Null } catch {} }
  if ($tempContract) { try { Call DELETE "$base/rest/v1/contract_documents?contract_id=eq.$tempContract" $admin $null | Out-Null } catch {}; try { Call DELETE "$base/rest/v1/contracts?id=eq.$tempContract" $admin $null | Out-Null } catch {} }
  if ($tempTask) { try { Call DELETE "$base/rest/v1/task_attachments?task_id=eq.$tempTask" $admin $null | Out-Null } catch {}; try { Call DELETE "$base/rest/v1/tasks?id=eq.$tempTask" $admin $null | Out-Null } catch {} }
  if ($tempProject) { try { Call DELETE "$base/rest/v1/projects?id=eq.$tempProject" $admin $null | Out-Null } catch {} }
  $passwords.Clear()
}

$results.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
if ($results.Values -contains $false) { exit 2 }
