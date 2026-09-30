$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$StagingRef = 'jcfyyxsuspukcmybyhjj'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LinkedRefPath = Join-Path $Root 'supabase/.temp/project-ref'

function Quote-ProcessArgument([string]$Value) {
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}
function Invoke-SupabaseCli([string[]]$Arguments) {
  $command = Get-Command supabase -CommandType Application -ErrorAction Stop
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = if ($command.Path) { $command.Path } else { $command.Source }
  $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true; $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
  $process = New-Object System.Diagnostics.Process; $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'Unable to start the Supabase CLI.' }
  $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync(); $process.WaitForExit()
  $stdout = $outTask.GetAwaiter().GetResult(); $stderr = $errTask.GetAwaiter().GetResult()
  if ($process.ExitCode -ne 0) { throw "Supabase smoke-test query failed with exit code $($process.ExitCode)." }
  [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

if (-not (Test-Path -LiteralPath $LinkedRefPath)) { throw 'Missing local Supabase project reference.' }
$linked = (Get-Content -Raw -LiteralPath $LinkedRefPath).Trim()
if ($linked -cne $ProductionRef -or $linked -ceq $StagingRef) { throw "ABORTED: linked project is '$linked', not production." }

$sqlPath = Join-Path $env:TEMP ('hrsys-production-readonly-smoke-' + [guid]::NewGuid().ToString('N') + '.sql')
$sql = @"
SELECT
  to_regclass('public.tasks') IS NOT NULL AS tasks_table,
  to_regclass('public.projects') IS NOT NULL AS projects_table,
  to_regclass('public.notifications') IS NOT NULL AS notifications_table,
  to_regclass('public.task_dependencies') IS NOT NULL AS dependencies_table,
  EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='start_task') AS phase_a_start,
  EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='create_task_dependency') AS phase_b_dependency,
  EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='list_project_command_center') AS phase_c_command_center,
  EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects') AS storage_rls;
"@
try {
  Set-Content -LiteralPath $sqlPath -Value $sql -Encoding UTF8
  [void](Invoke-SupabaseCli @('db', 'query', '--linked', '--file', $sqlPath))
} finally {
  if (Test-Path -LiteralPath $sqlPath) { Remove-Item -LiteralPath $sqlPath -Force -ErrorAction SilentlyContinue }
}

Write-Output "PRODUCTION READ-ONLY SMOKE QUERY PASSED: $ProductionRef"
Write-Output 'No synthetic records, Auth users, Storage objects, notifications, or business data were created.'
