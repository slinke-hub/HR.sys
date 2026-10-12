function ConvertFrom-SupabaseMigrationListOutput {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]$Lines
  )

  $rows = [System.Collections.Generic.List[object]]::new()
  $remoteOnlyRows = [System.Collections.Generic.List[string]]::new()
  $unparsedRows = [System.Collections.Generic.List[string]]::new()

  foreach ($line in $Lines) {
    if ([string]::IsNullOrWhiteSpace([string]$line)) { continue }
    $lineText = [regex]::Replace([string]$line, '\x1B\[[0-?]*[ -/]*[@-~]', '')
    if ($lineText -notmatch '\|') { continue }

    $cells = [System.Collections.Generic.List[string]]::new()
    foreach ($cell in ($lineText -split '\|')) {
      $cells.Add(([string]$cell).Trim().Trim([char]96).Trim())
    }

    # Remove table-frame cells only. Preserve a leading empty Local cell, which
    # is meaningful for Supabase's remote-only migration rows.
    if ($lineText -match '^\s*\|' -and $cells.Count -gt 0 -and [string]::IsNullOrWhiteSpace($cells[0])) {
      $cells.RemoveAt(0)
    }
    if ($lineText -match '\|\s*$' -and $cells.Count -gt 0 -and [string]::IsNullOrWhiteSpace($cells[$cells.Count - 1])) {
      $cells.RemoveAt($cells.Count - 1)
    }
    if ($cells.Count -lt 2) { continue }

    $localVersion = $cells[0].Trim().Trim([char]96).Trim()
    $remoteVersion = $cells[1].Trim().Trim([char]96).Trim()
    if ($localVersion -match '^\d{14}$') {
      # Retain malformed non-empty Remote values so the caller fails closed
      # through the divergence check instead of treating them as pending.
      $rows.Add([pscustomobject]@{ Local = $localVersion; Remote = $remoteVersion })
    } elseif ([string]::IsNullOrWhiteSpace($localVersion) -and $remoteVersion -match '^\d{14}$') {
      $remoteOnlyRows.Add($remoteVersion)
    } elseif (($cells -join ' ') -match '\d{14}') {
      $unparsedRows.Add($lineText.Trim())
    }
  }

  [pscustomobject]@{
    Rows = @($rows.ToArray())
    RemoteOnlyRows = @($remoteOnlyRows.ToArray())
    UnparsedRows = @($unparsedRows.ToArray())
  }
}
