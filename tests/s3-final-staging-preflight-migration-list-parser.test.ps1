$ErrorActionPreference = 'Stop'
$parserPath = Join-Path $PSScriptRoot '..\supabase\staging\s3-migration-list-parser.ps1'
. (Resolve-Path -LiteralPath $parserPath).Path

# Supabase CLI v2.117.0 ASCII table shape: backtick-wrapped Local/Remote cells
# and a blank Remote cell for the one pending migration.
$fixture = @(
  ''
  ' Local             | Remote            | Time (UTC)'
  ''
  ' ----------------- | ----------------- | -------------------'
  ' `20260928120000`  | `20260928120000`  | 2026-10-06 10:00:00'
  ' `20260930100000`  | `20260930100000`  | 2026-10-06 10:00:00'
  ' `20260930101000`  | `20260930101000`  | 2026-10-06 10:00:00'
  ' `20260930102000`  | `20260930102000`  | 2026-10-06 10:00:00'
  ' `20260930103000`  | `20260930103000`  | 2026-10-06 10:00:00'
  ' `20260930104000`  | `20260930104000`  | 2026-10-06 10:00:00'
  ' `20260930105000`  | `20260930105000`  | 2026-10-06 10:00:00'
  ' `20260930106000`  | `20260930106000`  | 2026-10-06 10:00:00'
  ' `20261001090000`  | `20261001090000`  | 2026-10-06 10:00:00'
  ' `20261001100000`  | `20261001100000`  | 2026-10-06 10:00:00'
  ' `20261002090000`  | `20261002090000`  | 2026-10-06 10:00:00'
  ' `20261005100000`  | `20261005100000`  | 2026-10-06 10:00:00'
  ' `20261005110000`  |                   |'
  ''
)

$parsed = ConvertFrom-SupabaseMigrationListOutput -Lines $fixture
$matched = @($parsed.Rows | Where-Object { $_.Remote -and $_.Local -ceq $_.Remote })
$pending = @($parsed.Rows | Where-Object { -not $_.Remote })
$diverged = @($parsed.Rows | Where-Object { $_.Remote -and $_.Local -cne $_.Remote })
$expectedMatchedVersions = @(
  '20260928120000', '20260930100000', '20260930101000', '20260930102000',
  '20260930103000', '20260930104000', '20260930105000', '20260930106000',
  '20261001090000', '20261001100000', '20261002090000', '20261005100000'
)
$actualMatchedVersions = @($matched | ForEach-Object { $_.Local })
$onlyS3Pending = ($pending.Count -eq 1) -and ($pending[0].Local -ceq '20261005110000') -and
  ($diverged.Count -eq 0) -and ($parsed.RemoteOnlyRows.Count -eq 0) -and ($parsed.UnparsedRows.Count -eq 0)

if ($parsed.Rows.Count -ne 13) { throw "Expected 13 local migration rows; got $($parsed.Rows.Count)." }
if ($matched.Count -ne 12) { throw "Expected 12 matched predecessors; got $($matched.Count)." }
if (Compare-Object -ReferenceObject $expectedMatchedVersions -DifferenceObject $actualMatchedVersions) {
  throw 'Matched predecessor versions did not equal the full expected set.'
}
if ($pending.Count -ne 1 -or $pending[0].Local -cne '20261005110000') {
  throw 'Expected 20261005110000 to be the sole pending version.'
}
if ($diverged.Count -ne 0) { throw "Expected no diverged versions; got $($diverged.Count)." }
if ($parsed.RemoteOnlyRows.Count -ne 0) { throw "Expected no remote-only versions; got $($parsed.RemoteOnlyRows.Count)." }
if ($parsed.UnparsedRows.Count -ne 0) { throw "Expected no unparsed migration rows; got $($parsed.UnparsedRows.Count)." }
if (-not $onlyS3Pending) { throw 'Expected the exact S3-only pending state.' }

$capturedCliText = "`r`n" + ($fixture -join "`r`n") + "`r`n"
$capturedCliLines = [regex]::Split($capturedCliText, '\r?\n')
$capturedParsed = ConvertFrom-SupabaseMigrationListOutput -Lines $capturedCliLines
$capturedPending = @($capturedParsed.Rows | Where-Object { -not $_.Remote })
$capturedDiverged = @($capturedParsed.Rows | Where-Object { $_.Remote -and $_.Local -cne $_.Remote })
if ($capturedParsed.Rows.Count -ne 13 -or $capturedPending.Count -ne 1 -or
    $capturedPending[0].Local -cne '20261005110000' -or $capturedDiverged.Count -ne 0 -or
    $capturedParsed.RemoteOnlyRows.Count -ne 0 -or $capturedParsed.UnparsedRows.Count -ne 0) {
  throw 'Captured multiline CLI output with empty lines did not parse to the exact expected state.'
}

Write-Output 'S3 migration-list parser regression: PASS'
Write-Output 'MATCHED_PREDECESSORS=12'
Write-Output 'ONLY_S3_PENDING=true'
Write-Output 'PENDING_VERSIONS=20261005110000'
Write-Output 'DIVERGED_VERSIONS=[]'
Write-Output 'REMOTE_ONLY_VERSIONS=[]'
Write-Output 'EMPTY_LINE_ARRAY_INPUT=PASS'
Write-Output 'MULTILINE_CLI_OUTPUT_INPUT=PASS'
