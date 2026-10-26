Set-StrictMode -Version Latest

function Invoke-CrmIntegrityGit {
  param([string]$Root, [string[]]$GitArgs)
  $result = & git -C $Root @GitArgs 2>$null
  if ($LASTEXITCODE -ne 0) { throw "Integrity check could not run git $($GitArgs -join ' ')." }
  return @($result | ForEach-Object { $_.ToString() })
}

function Get-CrmGitBlobSha1 {
  param([byte[]]$Bytes)
  $header = [Text.Encoding]::ASCII.GetBytes("blob $($Bytes.Length)`0")
  $payload = [byte[]]::new($header.Length + $Bytes.Length)
  [Buffer]::BlockCopy($header, 0, $payload, 0, $header.Length)
  [Buffer]::BlockCopy($Bytes, 0, $payload, $header.Length, $Bytes.Length)
  return [Convert]::ToHexString([Security.Cryptography.SHA1]::HashData($payload)).ToLowerInvariant()
}

function Get-CrmGitBlobBytes {
  param([string]$Root,[string]$BlobObjectId)
  if ($BlobObjectId -notmatch '^[a-f0-9]{40,64}$') { throw 'Invalid approved Git blob object ID.' }
  $psi = [Diagnostics.ProcessStartInfo]::new('git')
  $psi.WorkingDirectory = $Root
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  [void]$psi.ArgumentList.Add('cat-file')
  [void]$psi.ArgumentList.Add('blob')
  [void]$psi.ArgumentList.Add($BlobObjectId)
  $process = [Diagnostics.Process]::Start($psi)
  $memory = [IO.MemoryStream]::new()
  try {
    $process.StandardOutput.BaseStream.CopyTo($memory)
    $errorText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Could not read approved Git blob: $errorText" }
    return ,$memory.ToArray()
  } finally {
    $memory.Dispose()
    $process.Dispose()
  }
}

function Get-CrmGitPathBlobId {
  param([string]$Root,[string]$RelativePath,[string]$FullPath)
  $path = $RelativePath.Replace('\','/')
  $result = Invoke-CrmIntegrityGit $Root @('hash-object',"--path=$path",'--',$FullPath)
  $blob = ($result | Select-Object -First 1).ToString().Trim()
  if ($blob -notmatch '^[a-f0-9]{40,64}$') { throw "Git returned an invalid path-filtered object ID for $path." }
  return $blob
}

function Assert-CrmPackageGitState {
  param(
    [string]$Root,
    [string]$ApprovedCommit,
    [string[]]$RelevantUntrackedPatterns
  )
  if ($ApprovedCommit -notmatch '^[a-f0-9]{40}$') { throw 'A full externally reviewed Git commit SHA is required for execution.' }
  $head = (Invoke-CrmIntegrityGit $Root @('rev-parse','HEAD') | Select-Object -First 1).ToString().Trim()
  if ($head -cne $ApprovedCommit) { throw 'HEAD does not equal the externally approved package commit.' }
  $null = Invoke-CrmIntegrityGit $Root @('cat-file','-e',"$ApprovedCommit^{commit}")
  & git -C $Root diff --quiet $ApprovedCommit --
  if ($LASTEXITCODE -ne 0) { throw 'Execution requires a clean tracked working tree.' }
  & git -C $Root diff --cached --quiet $ApprovedCommit --
  if ($LASTEXITCODE -ne 0) { throw 'Execution requires a clean Git index.' }

  $untracked = Invoke-CrmIntegrityGit $Root @('ls-files','--others','--exclude-standard')
  foreach ($entry in $untracked) {
    $path = $entry.Replace('\','/')
    foreach ($pattern in $RelevantUntrackedPatterns) {
      if ($path -like $pattern) { throw "Unexpected untracked execution file: $path" }
    }
  }
  foreach ($pattern in $RelevantUntrackedPatterns) {
    $ignoredMatches = Invoke-CrmIntegrityGit $Root @('ls-files','--others','--ignored','--exclude-standard','--',":(glob)$pattern")
    foreach ($entry in $ignoredMatches) {
      if (-not [string]::IsNullOrWhiteSpace($entry)) {
        throw "Unexpected ignored execution file: $($entry.Replace('\','/'))"
      }
    }
  }
}

function New-CrmPackageIntegritySnapshot {
  param(
    [string]$Root,
    [string]$ApprovedCommit,
    [string[]]$CriticalFiles,
    [string[]]$RelevantUntrackedPatterns,
    [hashtable]$ExpectedSha256 = @{}
  )
  Assert-CrmPackageGitState $Root $ApprovedCommit $RelevantUntrackedPatterns
  $snapshotDirectory = Join-Path ([IO.Path]::GetTempPath()) ('crm-release-1a-verified-' + [Guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($snapshotDirectory) | Out-Null
  $files = @{}
  $streams = [Collections.Generic.List[IO.FileStream]]::new()
  try {
    foreach ($relativePath in $CriticalFiles) {
      if ([IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe integrity path: $relativePath"
      }
      $fullPath = Join-Path $Root ($relativePath.Replace('/',[IO.Path]::DirectorySeparatorChar))
      if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Missing integrity-protected file: $relativePath" }
      $committedBlob = (Invoke-CrmIntegrityGit $Root @('rev-parse',"${ApprovedCommit}:$relativePath") | Select-Object -First 1).ToString().Trim()
      $workingBlob = Get-CrmGitPathBlobId -Root $Root -RelativePath $relativePath -FullPath $fullPath
      if ($workingBlob -cne $committedBlob) { throw "File differs from the approved commit after Git clean filtering: $relativePath" }
      # Execution input comes from the immutable approved tree object, never
      # from the mutable worktree whose line endings may vary by checkout.
      $bytes = Get-CrmGitBlobBytes -Root $Root -BlobObjectId $committedBlob
      $actualBlob = Get-CrmGitBlobSha1 $bytes
      if ($actualBlob -cne $committedBlob) { throw "Approved Git blob snapshot failed object verification: $relativePath" }
      $sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
      if ($ExpectedSha256.ContainsKey($relativePath) -and $sha256 -cne $ExpectedSha256[$relativePath]) {
        throw "Approved SHA-256 mismatch for Git snapshot: $relativePath"
      }
      $snapshotPath = Join-Path $snapshotDirectory ($relativePath.Replace('/',[IO.Path]::DirectorySeparatorChar))
      $snapshotParent = Split-Path -Parent $snapshotPath
      [IO.Directory]::CreateDirectory($snapshotParent) | Out-Null
      # Keep a read-only-shared handle open for the entire execution. PostgreSQL
      # can read this snapshot, while Windows denies writes/deletion until closed.
      $writer = [IO.FileStream]::new($snapshotPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
      try {
        $writer.Write($bytes,0,$bytes.Length)
        $writer.Flush($true)
      } finally { $writer.Dispose() }
      $stream = [IO.FileStream]::new($snapshotPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      $streams.Add($stream)
      $files[$relativePath] = [pscustomobject]@{
        Bytes=$bytes; Blob=$actualBlob; Sha256=$sha256; SnapshotPath=$snapshotPath
      }
    }
    Assert-CrmPackageGitState $Root $ApprovedCommit $RelevantUntrackedPatterns
    foreach ($relativePath in $CriticalFiles) {
      $currentPath = Join-Path $Root ($relativePath.Replace('/',[IO.Path]::DirectorySeparatorChar))
      if ((Get-CrmGitPathBlobId -Root $Root -RelativePath $relativePath -FullPath $currentPath) -cne $files[$relativePath].Blob) {
        throw "Execution-critical file changed during snapshot creation: $relativePath"
      }
    }
    return [pscustomobject]@{
      Root=$Root; ApprovedCommit=$ApprovedCommit; CriticalFiles=$CriticalFiles
    RelevantUntrackedPatterns=$RelevantUntrackedPatterns; ExpectedSha256=$ExpectedSha256; Files=$files
      Streams=$streams; Directory=$snapshotDirectory
    }
  } catch {
    foreach ($stream in $streams) { $stream.Dispose() }
    Remove-Item -LiteralPath $snapshotDirectory -Recurse -Force -ErrorAction SilentlyContinue
    throw
  }
}

function Assert-CrmPackageIntegritySnapshot {
  param([pscustomobject]$Snapshot)
  Assert-CrmPackageGitState $Snapshot.Root $Snapshot.ApprovedCommit $Snapshot.RelevantUntrackedPatterns
  foreach ($relativePath in $Snapshot.CriticalFiles) {
    $fullPath = Join-Path $Snapshot.Root ($relativePath.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Execution-critical file disappeared: $relativePath" }
    if ((Get-CrmGitPathBlobId -Root $Snapshot.Root -RelativePath $relativePath -FullPath $fullPath) -cne $Snapshot.Files[$relativePath].Blob) {
      throw "Execution-critical file changed after validation: $relativePath"
    }
    if (-not (Test-Path -LiteralPath $Snapshot.Files[$relativePath].SnapshotPath -PathType Leaf)) {
      throw "Validated SQL snapshot is missing: $relativePath"
    }
    $snapshotBytes = [IO.File]::ReadAllBytes($Snapshot.Files[$relativePath].SnapshotPath)
    $snapshotSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($snapshotBytes))
    if ($snapshotSha256 -cne $Snapshot.Files[$relativePath].Sha256 -or
        (Get-CrmGitBlobSha1 $snapshotBytes) -cne $Snapshot.Files[$relativePath].Blob) {
      throw "Validated execution snapshot hash mismatch: $relativePath"
    }
    if ($Snapshot.ExpectedSha256.ContainsKey($relativePath) -and $snapshotSha256 -cne $Snapshot.ExpectedSha256[$relativePath]) {
      throw "Approved execution SHA-256 mismatch: $relativePath"
    }
  }
}

function Close-CrmPackageIntegritySnapshot {
  param([pscustomobject]$Snapshot)
  if ($null -eq $Snapshot) { return }
  foreach ($stream in $Snapshot.Streams) { $stream.Dispose() }
  $directory = [IO.Path]::GetFullPath($Snapshot.Directory)
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $directory.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or
      [IO.Path]::GetFileName($directory) -notmatch '^crm-release-1a-verified-[a-f0-9]{32}$') {
    throw 'Refusing to remove a validation snapshot outside its unique temporary directory.'
  }
  Remove-Item -LiteralPath $directory -Recurse -Force
}
