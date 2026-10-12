[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$FrozenHead = '451e0395b5cc4c7fe2f7ec0608c8e16b725973ba'
$MigrationName = '20261002090000_project_operations_phase_1.sql'
$MigrationHash = '64c464cca0102a8e784d1610be61bced32535ae30e7bc2a0af1c1424c1bc2037'
$ConfirmationPhrase = 'APPLY PROJECT OPERATIONS PHASE 1 TO STAGING'
$Root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$MigrationPath = Join-Path $Root ('supabase\migrations\' + $MigrationName)
$PreflightPath = Join-Path $PSScriptRoot 'project-operations-phase-1-preflight-summary.sql'
$VerifyPath = Join-Path $PSScriptRoot 'project-operations-phase-1-catalog-verification.sql'
$LinkPath = Join-Path $Root 'supabase\.temp\project-ref'
$PreviousTelemetry = $env:SUPABASE_TELEMETRY_DISABLED

function Quote-ProcessArgument([string]$Value) {
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-CapturedProcess([string]$Executable, [string[]]$Arguments, [string]$WorkingDirectory) {
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $Executable
  $startInfo.WorkingDirectory = $WorkingDirectory
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'Unable to start a required local command.' }
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  $exitCode = $process.ExitCode
  $process.Dispose()
  return [pscustomobject]@{ ExitCode = $exitCode; StdOut = $stdout; StdErr = $stderr }
}

function Assert-FrozenTarget {
  if (-not (Test-Path -LiteralPath $MigrationPath -PathType Leaf)) { throw 'Frozen migration file is missing.' }
  if (-not (Test-Path -LiteralPath $PreflightPath -PathType Leaf)) { throw 'Read-only deterministic preflight SQL is missing.' }
  if (-not (Test-Path -LiteralPath $VerifyPath -PathType Leaf)) { throw 'Read-only catalog verification SQL is missing.' }
  if (-not (Test-Path -LiteralPath $LinkPath -PathType Leaf)) { throw 'Linked Supabase project marker is missing; relinking is not permitted.' }
  $linkRef = (Get-Content -Raw -LiteralPath $LinkPath).Trim()
  if ($linkRef -ceq $ProductionRef) { throw 'Production reference detected; staging helper refuses production.' }
  if ($linkRef -cne $TargetRef) { throw 'Repository is not linked to the required staging project.' }

  $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
  $gitExe = if ($gitCommand.Path) { $gitCommand.Path } else { $gitCommand.Source }
  $headResult = Invoke-CapturedProcess $gitExe @('-C', $Root, 'rev-parse', 'HEAD') $Root
  if ($headResult.ExitCode -ne 0 -or $headResult.StdOut.Trim() -cne $FrozenHead) {
    throw 'Repository HEAD does not equal the frozen Phase 1 commit.'
  }
  $hash = (Get-FileHash -LiteralPath $MigrationPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($hash -cne $MigrationHash) { throw 'Frozen Phase 1 migration SHA-256 mismatch.' }
}

function Invoke-StagingQuery([string]$Operation, [string]$SqlPath) {
  $cli = Get-Command supabase -CommandType Application -ErrorAction Stop | Select-Object -First 1
  $cliPath = if ($cli.Path) { $cli.Path } else { $cli.Source }
  $result = Invoke-CapturedProcess $cliPath @('db','query','--linked','--project-ref',$TargetRef,'--file',$SqlPath) $Root
  if ($result.ExitCode -ne 0) {
    throw ($Operation + ' failed; Supabase CLI exit code ' + $result.ExitCode + '. Output is withheld to avoid exposing credentials or sensitive catalog text.')
  }
  return $result.StdOut
}

try {
  $env:SUPABASE_TELEMETRY_DISABLED = '1'
  Assert-FrozenTarget
  Write-Output ('Target staging project: ' + $TargetRef)
  Write-Output ('Migration: ' + $MigrationName)
  $confirmation = Read-Host ('Type exactly: ' + $ConfirmationPhrase)
  if ($confirmation -cne $ConfirmationPhrase) { throw 'Confirmation did not match; no database operation was performed.' }

  # Repeat local guards and run the deterministic read-only catalog preflight
  # immediately before applying the single frozen file.
  Assert-FrozenTarget
  $preflightOutput = Invoke-StagingQuery 'Staging Phase 1 read-only preflight' $PreflightPath
  if ($preflightOutput -notmatch '(?im)MIGRATION ABSENT\s*:\s*PASS' -or
      $preflightOutput -notmatch '(?im)PHASE 1 STAGING PREFLIGHT\s*:\s*PASS' -or
      $preflightOutput -match '(?im)PHASE 1 STAGING PREFLIGHT\s*:\s*FAIL') {
    throw 'Deterministic preflight did not report PASS or migration is already represented; no migration was executed.'
  }

  [void](Invoke-StagingQuery ('Apply ' + $MigrationName) $MigrationPath)
  $verificationOutput = Invoke-StagingQuery 'Read-only post-application catalog verification' $VerifyPath
  if ($verificationOutput -notmatch '(?m)PHASE1CATALOG\|PASS\|[0-9a-f]{32}') {
    throw 'Post-application catalog verification did not report PASS. Do not retry; inspect staging read-only state first.'
  }
  Write-Output ('STAGING PHASE 1 APPLICATION: PASS (' + $TargetRef + ')')
}
catch {
  Write-Error ('STAGING PHASE 1 APPLICATION: FAIL — ' + $_.Exception.Message)
  exit 1
}
finally {
  if ($null -eq $PreviousTelemetry) { Remove-Item Env:\SUPABASE_TELEMETRY_DISABLED -ErrorAction SilentlyContinue }
  else { $env:SUPABASE_TELEMETRY_DISABLED = $PreviousTelemetry }
}
