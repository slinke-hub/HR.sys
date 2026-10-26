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
  'docs/package-manifest.json',
  'supabase/migrations/20261022100000_crm_release_1a.sql'
)
$patterns = @('scripts/*crm-release-1a*','docs/CRM_RELEASE_1A_STAGING_*','docs/CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql','supabase/migrations/202610*.sql')
$snapshot = $null
$expectedSha256 = @{}

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
  & git -C $root config core.autocrlf true
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
  $migrationRelative = 'supabase/migrations/20261022100000_crm_release_1a.sql'
  $expectedSha256[$migrationRelative] = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes((Join-Path $root $migrationRelative))))
  $snapshot = New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 $expectedSha256
  Assert-CrmPackageIntegritySnapshot $snapshot
  'PASS: clean reviewed package accepted.'
  Close-CrmPackageIntegritySnapshot $snapshot
  $snapshot = $null

  # Model a Windows autocrlf checkout. Git sees the clean-filtered file as the
  # approved blob, while the immutable snapshot must still contain blob bytes.
  $migrationFile = Join-Path $root $migrationRelative
  $migrationText = [IO.File]::ReadAllText($migrationFile)
  [IO.File]::WriteAllText($migrationFile,($migrationText -replace "(?<!`r)`n","`r`n"))
  & git -C $root diff --quiet $approved --
  Assert-Test ($LASTEXITCODE -eq 0) 'Synthetic CRLF checkout did not match the approved commit after Git clean filtering.'
  $snapshot = New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 $expectedSha256
  $approvedMigration = Get-CrmGitBlobBytes -Root $root -BlobObjectId $snapshot.Files[$migrationRelative].Blob
  Assert-Test ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($approvedMigration)) -ceq $expectedSha256[$migrationRelative]) 'Snapshot did not preserve the approved migration SHA-256.'
  Assert-Test ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($snapshot.Files[$migrationRelative].SnapshotPath))) -ceq $expectedSha256[$migrationRelative]) 'Snapshot bytes were sourced from the normalized worktree instead of the approved blob.'
  Assert-CrmPackageIntegritySnapshot $snapshot
  Close-CrmPackageIntegritySnapshot $snapshot
  $snapshot = $null
  'PASS: clean Windows autocrlf checkout accepted; Git-blob execution snapshot used.'

  foreach ($path in @('scripts/crm-release-1a-staging.ps1','docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql',
      'docs/CRM_RELEASE_1A_STAGING_POSTCHECKS.sql','docs/CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql')) {
    [IO.File]::AppendAllText((Join-Path $root ($path.Replace('/',[IO.Path]::DirectorySeparatorChar))),'tampered')
    Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 $expectedSha256 } "Modified $path was accepted."
    Reset-TestRepo $root $files
  }
  [IO.File]::AppendAllText((Join-Path $root $migrationRelative),"`n-- genuine migration content change")
  Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 $expectedSha256 } 'A genuine SQL migration edit was accepted.'
  Reset-TestRepo $root $files
  'PASS: genuine SQL migration modifications rejected.'
  [IO.File]::AppendAllText((Join-Path $root 'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql'),'staged change')
  & git -C $root add -- 'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql' | Out-Null
  Assert-Test ($LASTEXITCODE -eq 0) 'Could not stage synthetic dirty file.'
  Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 $expectedSha256 } 'Dirty Git index was accepted.'
  Reset-TestRepo $root $files
  'PASS: dirty tracked worktree/index and modified runner/preflight/postcheck/metadata files rejected.'

  [IO.File]::WriteAllText((Join-Path $root 'scripts/crm-release-1a-extra.ps1'),'unexpected')
  Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 $expectedSha256 } 'Unexpected execution-critical untracked file was accepted.'
  Remove-Item -LiteralPath (Join-Path $root 'scripts/crm-release-1a-extra.ps1') -Force
  [IO.File]::WriteAllText((Join-Path $root '.gitignore'),"scripts/crm-release-1a-*.ps1`n")
  [IO.File]::WriteAllText((Join-Path $root 'scripts/crm-release-1a-ignored.ps1'),'ignored unexpected execution file')
  Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 $expectedSha256 } 'Ignored execution-critical untracked file was accepted.'
  Remove-Item -LiteralPath (Join-Path $root '.gitignore') -Force
  Remove-Item -LiteralPath (Join-Path $root 'scripts/crm-release-1a-ignored.ps1') -Force
  'PASS: unexpected relevant untracked files rejected.'

  # A mutable local manifest cannot bless modified package content: the supplied
  # commit remains the anchor and both tracked modifications are rejected.
  [IO.File]::AppendAllText((Join-Path $root 'docs/package-manifest.json'),'changed file')
  [IO.File]::AppendAllText((Join-Path $root 'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql'),'changed SQL')
  Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 $expectedSha256 } 'A changed local manifest authorized its own modifications.'
  Reset-TestRepo $root $files
  'PASS: edited manifest cannot authorize itself.'

  $snapshot = New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 $expectedSha256
  $tamperRelative = 'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql'
  $tamperIndex = [Array]::IndexOf($files,$tamperRelative)
  $snapshot.Streams[$tamperIndex].Dispose()
  [IO.File]::AppendAllText($snapshot.Files[$tamperRelative].SnapshotPath,'tampered snapshot')
  Assert-Rejected { Assert-CrmPackageIntegritySnapshot $snapshot } 'Modified execution snapshot passed its recorded SHA-256 check.'
  Close-CrmPackageIntegritySnapshot $snapshot
  $snapshot = $null
  'PASS: modified snapshot hash rejected.'

  $snapshot = New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 $expectedSha256
  [IO.File]::AppendAllText((Join-Path $root 'docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql'),'changed after validation')
  Assert-Rejected { Assert-CrmPackageIntegritySnapshot $snapshot } 'Change after validation did not trigger a safe stop.'
  $lockRejectedWrite = $false
  try { $probe = [IO.File]::Open($snapshot.Files['docs/CRM_RELEASE_1A_STAGING_PREFLIGHT.sql'].SnapshotPath,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None); $probe.Dispose() }
  catch { $lockRejectedWrite = $true }
  Assert-Test $lockRejectedWrite 'Validated SQL snapshot was writable while execution lock was held.'
  'PASS: post-validation changes stop execution and snapshot files remain write-locked.'

  # A valid but different commit cannot be substituted for the externally
  # reviewed anchor, even when its worktree is clean.
  Close-CrmPackageIntegritySnapshot $snapshot
  $snapshot = $null
  [IO.File]::AppendAllText((Join-Path $root 'docs/package-manifest.json'),'new commit')
  & git -C $root add -- 'docs/package-manifest.json' | Out-Null
  & git -C $root -c user.name='CRM Integrity Tests' -c user.email='crm-integrity@example.invalid' commit -m 'unapproved synthetic commit' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not create alternate synthetic commit.' }
  $alternateCommit = (Invoke-TestGit $root @('rev-parse','HEAD') | Select-Object -First 1).ToString().Trim()
  Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $approved -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 $expectedSha256 } 'Unapproved older commit was accepted after HEAD changed.'
  Assert-Rejected { New-CrmPackageIntegritySnapshot -Root $root -ApprovedCommit $alternateCommit -CriticalFiles $files -RelevantUntrackedPatterns $patterns -ExpectedSha256 @{ $migrationRelative='00' } } 'Snapshot with a mismatched approved migration SHA-256 was accepted.'
  'PASS: unapproved commits and snapshot SHA-256 mismatches rejected.'
  'PASS: synthetic integrity test suite.'
} finally {
  if ($null -ne $snapshot) { Close-CrmPackageIntegritySnapshot $snapshot }
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
