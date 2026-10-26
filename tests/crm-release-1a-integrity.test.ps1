$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\scripts\crm-release-1a-integrity.ps1')

$temp = Join-Path ([IO.Path]::GetTempPath()) ('crm-integrity-test-' + [Guid]::NewGuid().ToString('N'))
$root = Join-Path $temp 'repo'
$files = @(
  'scripts/crm-release-1a-staging.ps1',
  'scripts/crm-release-1a-integrity.ps1',
  'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql',
  'docs/CRM_RELEASE_1A_STAGING_POSTCHECKS.sql',
  'docs/CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql',
  'docs/package-manifest.json'
)
$patterns = @('scripts/*crm-release-1a*','docs/CRM_RELEASE_1A_STAGING_*','docs/CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql')
$snapshot = $null

function Invoke-TestGit {
  param([string]$Root,[string[]]$GitArgs)
  $result = & git -C $Root @GitArgs 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Test Git failed: $($GitArgs -join ' ') $result" }
  return @($result)
}
function Assert-Test([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "ASSERTION FAILED: $Message" } }
function Assert-Rejected([scriptblock]$Action,[string]$Message) {
  $rejected = $false
  try { & $Action } catch { $rejected = $true }
  Assert-Test $rejected $Message
}
function Reset-TestRepo([string]$Root,[string[]]$Files) {
  & git -C $Root reset --hard HEAD | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not reset synthetic test repository.' }
  & git -C $Root clean -fdx | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not clean synthetic test repository.' }
  foreach ($path in $Files) { [IO.File]::WriteAllText((Join-Path $Root ($path.Replace('/',[IO.Path]::DirectorySeparatorChar))),"synthetic $path`n") }
}

try {
  [IO.Directory]::CreateDirectory($root) | Out-Null
  & git -C $root init -b test-integrity | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not initialize synthetic Git repository.' }
  & git -C $root -c user.name='CRM Integrity Tests' -c user.email='crm-integrity@example.invalid' config core.autocrlf false
  if ($LASTEXITCODE -ne 0) { throw 'Could not configure synthetic Git repository.' }
  foreach ($path in $files) {
    $full = Join-Path $root ($path.Replace('/',[IO.Path]::DirectorySeparatorChar))
    [IO.Directory]::CreateDirectory((Split-Path -Parent $full)) | Out-Null
    [IO.File]::WriteAllText($full,"synthetic $path`n")
  }
  & git -C $root add -- $files
  if ($LASTEXITCODE -ne 0) { throw 'Could not stage synthetic package.' }
  & git -C $root -c user.name='CRM Integrity Tests' -c user.email='crm-integrity@example.invalid' commit -m 'synthetic integrity package' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not commit synthetic package.' }
  $approved = (Invoke-TestGit $root @('rev-parse','HEAD') | Select-Object -First 1).ToString().Trim()
  $snapshot = New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns
  Assert-CrmPackageIntegritySnapshot $snapshot
  'PASS: clean reviewed package accepted.'
  Close-CrmPackageIntegritySnapshot $snapshot
  $snapshot = $null

  foreach ($path in @('scripts/crm-release-1a-staging.ps1','docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql',
      'docs/CRM_RELEASE_1A_STAGING_POSTCHECKS.sql','docs/CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql')) {
    [IO.File]::AppendAllText((Join-Path $root ($path.Replace('/',[IO.Path]::DirectorySeparatorChar))),'tampered')
    Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns } "Modified $path was accepted."
    Reset-TestRepo $root $files
  }
  [IO.File]::AppendAllText((Join-Path $root 'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql'),'staged change')
  & git -C $root add -- 'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql' | Out-Null
  Assert-Test ($LASTEXITCODE -eq 0) 'Could not stage synthetic dirty file.'
  Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns } 'Dirty Git index was accepted.'
  Reset-TestRepo $root $files
  'PASS: dirty tracked worktree/index and modified runner/preflight/postcheck/metadata files rejected.'

  [IO.File]::WriteAllText((Join-Path $root 'scripts/crm-release-1a-extra.ps1'),'unexpected')
  Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns } 'Unexpected execution-critical untracked file was accepted.'
  Remove-Item -LiteralPath (Join-Path $root 'scripts/crm-release-1a-extra.ps1') -Force
  [IO.File]::WriteAllText((Join-Path $root '.gitignore'),"scripts/crm-release-1a-*.ps1`n")
  [IO.File]::WriteAllText((Join-Path $root 'scripts/crm-release-1a-ignored.ps1'),'ignored unexpected execution file')
  Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns } 'Ignored execution-critical untracked file was accepted.'
  Remove-Item -LiteralPath (Join-Path $root '.gitignore') -Force
  Remove-Item -LiteralPath (Join-Path $root 'scripts/crm-release-1a-ignored.ps1') -Force
  'PASS: unexpected relevant untracked files rejected.'

  # A mutable local manifest cannot bless modified package content: the supplied
  # commit remains the anchor and both tracked modifications are rejected.
  [IO.File]::AppendAllText((Join-Path $root 'docs/package-manifest.json'),'changed file')
  [IO.File]::AppendAllText((Join-Path $root 'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql'),'changed SQL')
  Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns } 'A changed local manifest authorized its own modifications.'
  Reset-TestRepo $root $files
  'PASS: edited manifest cannot authorize itself.'

  $snapshot = New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns
  [IO.File]::AppendAllText((Join-Path $root 'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql'),'changed after validation')
  Assert-Rejected { Assert-CrmPackageIntegritySnapshot $snapshot } 'Change after validation did not trigger a safe stop.'
  $lockRejectedWrite = $false
  try { $probe = [IO.File]::Open($snapshot.Files['docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql'].SnapshotPath,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None); $probe.Dispose() }
  catch { $lockRejectedWrite = $true }
  Assert-Test $lockRejectedWrite 'Validated SQL snapshot was writable while execution lock was held.'
  'PASS: post-validation changes stop execution and snapshot files remain write-locked.'
  'PASS: synthetic integrity test suite.'
} finally {
  if ($null -ne $snapshot) { Close-CrmPackageIntegritySnapshot $snapshot }
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
