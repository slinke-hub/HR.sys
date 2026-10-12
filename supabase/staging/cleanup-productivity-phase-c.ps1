param([string]$RunId = 'be291a9d-090e-43a9-97be-3697f651b25d')
$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'

$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$refPath = Join-Path $root 'supabase/.temp/project-ref'
if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing linked Supabase project reference.' }
$linkedRef = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linkedRef -cne $TargetRef -or $linkedRef -ceq $ProductionRef) { throw "ABORTED: linked project is '$linkedRef', not staging '$TargetRef'." }
if ($TargetRef -ceq $ProductionRef) { throw 'ABORTED: staging and production references must differ.' }
if ($RunId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') { throw 'RunId must be a UUID.' }
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
  $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync(); $process.WaitForExit()
  $out = $stdout.GetAwaiter().GetResult(); $err = $stderr.GetAwaiter().GetResult()
  if ($process.ExitCode -ne 0) { throw "Supabase CLI failed with exit code $($process.ExitCode)." }
  try { return ($out | ConvertFrom-Json) } catch {
    $starts = @($out.IndexOf('['), $out.IndexOf('{')) | Where-Object { $_ -ge 0 }; $ends = @($out.LastIndexOf(']'), $out.LastIndexOf('}')) | Where-Object { $_ -ge 0 }
    if ($starts.Count -eq 0 -or $ends.Count -eq 0) { throw 'Supabase CLI returned no JSON payload.' }
    $start = ($starts | Measure-Object -Minimum).Minimum; $end = ($ends | Measure-Object -Maximum).Maximum
    return ($out.Substring($start, $end - $start + 1) | ConvertFrom-Json)
  }
}
function Headers($key) { return @{apikey=$key;Authorization="Bearer $key";'Content-Type'='application/json';Prefer='return=minimal'} }
function Raw($method,$url,$headers) {
  try { $r=Invoke-WebRequest -UseBasicParsing -Method $method -Uri $url -Headers $headers -ErrorAction Stop; return [pscustomobject]@{status=[int]$r.StatusCode;body=$r.Content} }
  catch { $s=0;if($_.Exception.Response){$s=[int]$_.Exception.Response.StatusCode.value__};$b=$_.ErrorDetails.Message;if([string]::IsNullOrWhiteSpace($b)){$b=$_.Exception.Message};return [pscustomobject]@{status=$s;body=$b} }
}
function Json($raw) { try { return ($raw.body | ConvertFrom-Json) } catch { return $null } }
function DeleteExact($table,$id,$headers) {
  if ($id -notmatch '^[0-9a-fA-F-]{36}$') { throw "Refusing to delete non-UUID $table identifier." }
  $url = "$base/rest/v1/$table`?id=eq.$id"
  $raw = Raw DELETE $url $headers
  if ($raw.status -notin 200..299 -and $raw.status -ne 404) { throw "Cleanup failed for $table/$id (HTTP $($raw.status))." }
}

$serviceKey = $null
try {
  $keys=Invoke-SupabaseCliJson @('projects','api-keys','--project-ref',$TargetRef,'--reveal','--output','json')
  $serviceKey=($keys|Where-Object name -eq service_role|Select-Object -First 1).api_key
  if ([string]::IsNullOrWhiteSpace($serviceKey)) { throw 'Staging service-role credential unavailable.' }
  $headers=Headers $serviceKey
  $marker="PRODUCTIVITY PHASE C SECURITY TEST $RunId"
  $projects=@(Json (Raw GET "$base/rest/v1/projects`?select=id,project_name" $headers)) | Where-Object { ([string]$_.project_name).IndexOf($marker,[StringComparison]::OrdinalIgnoreCase) -ge 0 }
  $projectIds=@($projects|ForEach-Object{[string]$_.id})
  $taskIds=New-Object System.Collections.Generic.List[string]
  foreach($projectId in $projectIds){$rows=@(Json (Raw GET "$base/rest/v1/tasks`?select=id,project_id&project_id=eq.$projectId" $headers));foreach($row in $rows){if($row.id){[void]$taskIds.Add([string]$row.id)}}}
  $taskIdSet=@{};foreach($id in $taskIds){$taskIdSet[$id]=$true}
  $dependencies=@(Json (Raw GET "$base/rest/v1/task_dependencies`?select=id,predecessor_task_id,successor_task_id" $headers)) | Where-Object { $taskIdSet.ContainsKey([string]$_.predecessor_task_id) -or $taskIdSet.ContainsKey([string]$_.successor_task_id) }
  foreach($row in $dependencies){DeleteExact 'task_dependencies' ([string]$row.id) $headers}
  for($index=$taskIds.Count-1;$index-ge 0;$index--){DeleteExact 'tasks' $taskIds[$index] $headers}
  for($index=$projectIds.Count-1;$index-ge 0;$index--){DeleteExact 'projects' $projectIds[$index] $headers}
  Write-Output "PREVIOUS PHASE C SYNTHETIC CLEANUP: PASS"
  Write-Output "run_id=$RunId;projects=$($projectIds.Count);tasks=$($taskIds.Count);dependencies=$(@($dependencies).Count)"
} finally {
  $serviceKey=$null;$headers=$null
}
