[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$S3Version = '20261005110000'
$S3Name = '20261005110000_security_hardening_s3.sql'
$S3Hash = '0B5C5877A8CB1392E7F9DE36758C3A9380C595161CF1335A00629A39ABCC48D3'
$ApplyPhrase = 'APPLY SECURITY HARDENING S3 TO STAGING'
$HistoryPhrase = 'RECORD S3 AS APPLIED IN STAGING HISTORY'
$Root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$LinkPath = Join-Path $Root 'supabase\.temp\project-ref'
$MigrationPath = Join-Path $Root ('supabase\migrations\' + $S3Name)
$PreflightPath = Join-Path $PSScriptRoot 's3-final-staging-preflight.ps1'
$PostApplySqlPath = Join-Path $PSScriptRoot 's3-post-application-readonly.sql'
$ParserPath = Join-Path $PSScriptRoot 's3-migration-list-parser.ps1'

function Quote-ProcessArgument([string]$Value) {
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-CapturedProcess([string]$Executable, [string[]]$Arguments) {
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $Executable
  $startInfo.WorkingDirectory = $Root
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw 'Unable to start the required local command.' }
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  $exitCode = $process.ExitCode
  $process.Dispose()
  [pscustomobject]@{ ExitCode = $exitCode; StdOut = $stdout; StdErr = $stderr }
}

function Assert-StagingTargetAndHash {
  if (-not (Test-Path -LiteralPath $LinkPath -PathType Leaf)) { throw 'Staging link marker is missing; no database operation was issued.' }
  $linkedRef = (Get-Content -Raw -LiteralPath $LinkPath).Trim()
  if ($linkedRef -ceq $ProductionRef) { throw 'Production reference detected; this helper refuses production.' }
  if ($linkedRef -cne $TargetRef) { throw 'Repository is not linked to the exact approved staging project.' }
  if (-not (Test-Path -LiteralPath $MigrationPath -PathType Leaf)) { throw 'Frozen S3 migration file is missing.' }
  $actualHash = (Get-FileHash -LiteralPath $MigrationPath -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($actualHash -cne $S3Hash) { throw 'Frozen S3 migration SHA-256 mismatch; no migration was executed.' }
  foreach ($path in @($PreflightPath, $PostApplySqlPath, $ParserPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'A required local S3 preflight, verification, or parser file is missing.' }
  }
}

function Invoke-Preflight([string]$PowerShellExe) {
  $result = Invoke-CapturedProcess $PowerShellExe @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PreflightPath)
  if ($result.ExitCode -ne 0 -or $result.StdOut -notmatch '(?m)^S3_STAGING_PREFLIGHT=PASS\s*$') {
    throw 'Immediate pre-application staging preflight failed; its output is withheld. No S3 SQL was executed.'
  }
}

function Invoke-StagingSql([string]$Label, [string]$SqlPath, [string]$SupabaseExe) {
  $result = Invoke-CapturedProcess $SupabaseExe @('db','query','--linked','--project-ref',$TargetRef,'--file',$SqlPath)
  if ($result.ExitCode -ne 0) {
    throw ($Label + ' failed with Supabase CLI exit code ' + $result.ExitCode + '; CLI output is withheld.')
  }
  return $result.StdOut
}

function Assert-S3IsSolePending([string]$SupabaseExe) {
  . $ParserPath
  $history = Invoke-CapturedProcess $SupabaseExe @('migration','list','--linked','--project-ref',$TargetRef)
  if ($history.ExitCode -ne 0) { throw 'Read-only migration-history check failed; no history repair was issued.' }
  $parsed = ConvertFrom-SupabaseMigrationListOutput -Lines ([regex]::Split($history.StdOut, '\r?\n'))
  $pendingRows = @($parsed.Rows | Where-Object { [string]::IsNullOrWhiteSpace($_.Remote) })
  $divergedRows = @($parsed.Rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Remote) -and $_.Local -cne $_.Remote })
  $s3Pending = @($pendingRows | Where-Object { $_.Local -ceq $S3Version })
  $otherPending = @($pendingRows | Where-Object { $_.Local -cne $S3Version })
  if ($s3Pending.Count -ne 1 -or $otherPending.Count -ne 0 -or $divergedRows.Count -ne 0 -or
      $parsed.RemoteOnlyRows.Count -ne 0 -or $parsed.UnparsedRows.Count -ne 0) {
    throw 'Migration history is no longer exactly S3-pending; do not repair history or reapply S3.'
  }
}

try {
  Assert-StagingTargetAndHash
  $supabaseCommand = Get-Command supabase -CommandType Application -ErrorAction Stop | Select-Object -First 1
  $SupabaseExe = if ($supabaseCommand.Path) { $supabaseCommand.Path } else { $supabaseCommand.Source }
  $PowerShellExe = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source

  Write-Output ('STAGING TARGET: ' + $TargetRef)
  Write-Output ('SINGLE MIGRATION: ' + $S3Name)
  if ((Read-Host ('Type exactly: ' + $ApplyPhrase)) -cne $ApplyPhrase) {
    throw 'Application confirmation did not match; no database mutation was performed.'
  }

  # The preflight independently checks sole-pending-S3 history and live catalog
  # predicates. Repeat target/hash guards immediately before that read-only check.
  Assert-StagingTargetAndHash
  Invoke-Preflight $PowerShellExe

  # Run only the frozen S3 file. Never use db push.
  [void](Invoke-StagingSql ('Apply ' + $S3Name) $MigrationPath $SupabaseExe)

  # Schema/security assertions must pass before any migration-history operation.
  $verificationOutput = Invoke-StagingSql 'Read-only post-S3 security verification' $PostApplySqlPath $SupabaseExe
  if ($verificationOutput -notmatch '(?m)S3_POST_APPLY_VERIFICATION\s*[:=| ]+PASS' -or
      $verificationOutput -notmatch '(?m)FAILED_PREDICATES\s*[:=| ]+none' -or
      $verificationOutput -match '(?m)S3_POST_APPLY_VERIFICATION\s*[:=| ]+FAIL') {
    throw 'Post-S3 catalog/security verification did not report PASS. Do not retry or repair history; inspect read-only state.'
  }
  Write-Output 'S3_POST_APPLY_VERIFICATION=PASS'

  # Confirm the one-version history state again after SQL verification and
  # before offering the separate history-only mutation.
  Assert-StagingTargetAndHash
  Assert-S3IsSolePending $SupabaseExe

  if ((Read-Host ('Type exactly to record only this successfully verified version: ' + $HistoryPhrase)) -cne $HistoryPhrase) {
    throw 'History confirmation did not match. S3 SQL was applied and verified, but migration history was not modified.'
  }

  Assert-StagingTargetAndHash
  Assert-S3IsSolePending $SupabaseExe
  $repair = Invoke-CapturedProcess $SupabaseExe @('migration','repair','--linked','--project-ref',$TargetRef,'--status','applied',$S3Version)
  if ($repair.ExitCode -ne 0) {
    throw ('S3 SQL and catalog verification passed, but single-version migration-history recording failed with CLI exit code ' + $repair.ExitCode + '. Do not reapply S3.')
  }

  $history = Invoke-CapturedProcess $SupabaseExe @('migration','list','--linked','--project-ref',$TargetRef)
  if ($history.ExitCode -ne 0) { throw 'Post-repair migration-list verification failed; do not reapply S3.' }
  $parsed = ConvertFrom-SupabaseMigrationListOutput -Lines ([regex]::Split($history.StdOut, '\r?\n'))
  $pending = @($parsed.Rows | Where-Object { [string]::IsNullOrWhiteSpace($_.Remote) })
  $diverged = @($parsed.Rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Remote) -and $_.Local -cne $_.Remote })
  $s3Matched = @($parsed.Rows | Where-Object { $_.Local -ceq $S3Version -and $_.Remote -ceq $S3Version })
  if ($s3Matched.Count -ne 1 -or $pending.Count -ne 0 -or $diverged.Count -ne 0 -or
      $parsed.RemoteOnlyRows.Count -ne 0 -or $parsed.UnparsedRows.Count -ne 0) {
    throw 'Post-repair history state was unexpected. Do not reapply S3; inspect migration history read-only.'
  }

  Write-Output 'S3_HISTORY_RECORDING=PASS'
  Write-Output 'STAGING_S3_APPLICATION=PASS'
  Write-Output 'STAGING_AUTHENTICATED_ACCEPTANCE_REQUIRED=YES'
}
catch {
  Write-Error ('STAGING S3 APPLICATION: STOP — ' + $_.Exception.Message)
  exit 1
}
