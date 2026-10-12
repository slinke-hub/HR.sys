$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'

$TargetRef = 'jcfyyxsuspukcmybyhjj'
$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$ExpectedEmployeeId = 'TEST-OUTSIDER'
$root = (Get-Location).Path
$refPath = Join-Path $root 'supabase\.temp\project-ref'

function Quote-ProcessArgument([string]$Value) {
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-SupabaseCliJson([string[]]$Arguments) {
    $command = Get-Command supabase -CommandType Application -ErrorAction Stop | Select-Object -First 1
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
    $null = $stderrTask.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) { throw "Supabase CLI failed with exit code $($process.ExitCode)." }
    try { return ($stdout | ConvertFrom-Json) } catch { throw 'Supabase CLI returned invalid JSON.' }
}

function Get-SanitizedAuthError([System.Management.Automation.ErrorRecord]$ErrorRecord) {
    $response = $ErrorRecord.Exception.Response
    $status = 'unknown'
    $code = 'unknown'
    $message = 'request failed'
    $body = $null
    if ($response) {
        try { $status = [int]$response.StatusCode } catch { }
        try {
            $stream = $response.GetResponseStream()
            if ($stream) {
                $reader = New-Object System.IO.StreamReader($stream)
                try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
            }
        } catch { }
    }
    if (-not [string]::IsNullOrWhiteSpace($body)) {
        try {
            $details = $body | ConvertFrom-Json
            if ($details.code) { $code = [string]$details.code }
            elseif ($details.error_code) { $code = [string]$details.error_code }
            if ($details.message) { $message = [string]$details.message }
            elseif ($details.msg) { $message = [string]$details.msg }
        } catch { }
    }
    $safeMessage = (($message -replace '[\r\n]+', ' ').Trim())
    if ($safeMessage.Length -gt 240) { $safeMessage = $safeMessage.Substring(0, 240) }
    return "HTTP $status; code=$code; message=$safeMessage"
}

function Clear-LocalSecretVariables {
    foreach ($name in @('serviceKey', 'keys', 'headers', 'profileResponse', 'profiles', 'authResponse', 'passwordOne', 'passwordTwo', 'plainPassword', 'confirmedPassword', 'requestBody', 'passwordPtrOne', 'passwordPtrTwo', 'stdout')) {
        Remove-Variable -Name $name -Scope 1 -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $refPath)) { throw 'Missing supabase/.temp/project-ref.' }
$linkedRef = (Get-Content -Raw -LiteralPath $refPath).Trim()
if ($linkedRef -ceq $ProductionRef -or $linkedRef -cne $TargetRef) {
    throw "ABORTED: linked project is '$linkedRef', not staging '$TargetRef'."
}

$baseUrl = "https://$TargetRef.supabase.co"
$serviceKey = $null
$passwordOne = $null
$passwordTwo = $null
$plainPassword = $null
$confirmedPassword = $null
$requestBody = $null
$passwordPtrOne = [IntPtr]::Zero
$passwordPtrTwo = [IntPtr]::Zero

try {
    $keys = Invoke-SupabaseCliJson @('projects', 'api-keys', '--project-ref', $TargetRef, '--reveal', '--output', 'json')
    $serviceKey = [string](($keys | Where-Object name -eq 'service_role' | Select-Object -First 1).api_key)
    if ([string]::IsNullOrWhiteSpace($serviceKey)) { throw 'Staging administrative credential unavailable.' }

    $headers = @{
        apikey = $serviceKey
        Authorization = "Bearer $serviceKey"
        'Content-Type' = 'application/json'
    }
    $profileUri = "$baseUrl/rest/v1/profiles?employee_id=eq.TEST-OUTSIDER&select=id,employee_id"
    $profileResponse = Invoke-RestMethod -UseBasicParsing -Method Get -Uri $profileUri -Headers $headers
    $profiles = @($profileResponse)
    if ($profiles.Count -ne 1 -or [string]$profiles[0].employee_id -cne $ExpectedEmployeeId -or [string]::IsNullOrWhiteSpace([string]$profiles[0].id)) {
        throw 'Staging TEST-OUTSIDER profile was not found uniquely.'
    }
    $outsiderUserId = [string]$profiles[0].id

    try {
        $authResponse = Invoke-RestMethod -UseBasicParsing -Method Get -Uri "$baseUrl/auth/v1/admin/users/$outsiderUserId" -Headers $headers
    }
    catch {
        throw "Existing TEST-OUTSIDER Auth user verification failed: $(Get-SanitizedAuthError $_)"
    }
    if ([string]$authResponse.id -cne $outsiderUserId) {
        throw 'Resolved TEST-OUTSIDER profile does not match an existing staging Auth user.'
    }

    $passwordOne = Read-Host 'Enter temporary TEST OUTSIDER password' -AsSecureString
    $passwordTwo = Read-Host 'Confirm temporary TEST OUTSIDER password' -AsSecureString
    $passwordPtrOne = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordOne)
    $passwordPtrTwo = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordTwo)
    try {
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtrOne)
        $confirmedPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtrTwo)
        if ($plainPassword -cne $confirmedPassword) { throw 'Passwords do not match.' }
        $requestBody = @{ password = $plainPassword } | ConvertTo-Json -Compress
        try {
            Invoke-RestMethod -UseBasicParsing -Method Put -Uri "$baseUrl/auth/v1/admin/users/$outsiderUserId" -Headers $headers -Body $requestBody | Out-Null
        }
        catch {
            throw "Supabase Auth password update rejected: $(Get-SanitizedAuthError $_)"
        }
    }
    finally {
        if ($passwordPtrOne -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtrOne) }
        if ($passwordPtrTwo -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtrTwo) }
    }
    Write-Output 'TEST OUTSIDER staging password updated.'
}
finally {
    Clear-LocalSecretVariables
}
