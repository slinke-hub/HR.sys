$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$refPath = Join-Path (Get-Location) 'supabase/.temp/project-ref'
if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing linked Supabase project reference.' }
$linkedRef = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linkedRef -cne $TargetRef -or $linkedRef -ceq $ProductionRef) { throw "Refusing non-staging target: $linkedRef" }
$sqlPath = Join-Path (Get-Location) 'supabase/migrations/20260928120000_notification_backend_services.sql'
if (-not (Test-Path -LiteralPath $sqlPath)) { throw "Missing notification deployment artifact: $sqlPath" }

function Quote-ProcessArgument([string]$Value) {
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-SupabaseCli([string[]]$Arguments) {
  $command = Get-Command supabase -CommandType Application -ErrorAction Stop
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = if ($command.Path) { $command.Path } else { $command.Source }
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'Unable to start the Supabase CLI.' }
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  if ($process.ExitCode -ne 0) {
    throw "Notification staging deployment failed with exit code $($process.ExitCode)."
  }
  # Supabase update/version notices may be written to stderr on a successful
  # run. They are intentionally ignored; the native exit code is authoritative.
  return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

[void](Invoke-SupabaseCli @('db', 'query', '--linked', '--file', $sqlPath))
Write-Output "NOTIFICATION BACKEND STAGING DEPLOYED: $TargetRef"
