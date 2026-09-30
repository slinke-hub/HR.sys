$ErrorActionPreference = 'Stop'
$env:SUPABASE_TELEMETRY_DISABLED = '1'

$ProductionRef = 'bbbetcdioiaozdjkvwxu'
$StagingRef = 'jcfyyxsuspukcmybyhjj'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LinkedRefPath = Join-Path $Root 'supabase/.temp/project-ref'
$SqlPath = Join-Path $env:TEMP ('hrsys-production-forensics-' + [guid]::NewGuid().ToString('N') + '.sql')

function Quote-ProcessArgument([string]$Value) {
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Sanitize-Diagnostic([string]$Text) {
  if ($null -eq $Text) { return '' }
  $safe = $Text -replace '(?i)(access[_ -]?token|service[_ -]?role|password|secret|api[_ -]?key|authorization)\s*[:=]\s*[^\s,;]+', '$1=[REDACTED]'
  if ($safe.Length -gt 2000) { return $safe.Substring(0, 2000) + '…' }
  return $safe.Trim()
}

function Invoke-SupabaseCli([string[]]$Arguments, [string]$Operation) {
  $command = Get-Command supabase -CommandType Application -ErrorAction Stop
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = if ($command.Path) { $command.Path } else { $command.Source }
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.EnvironmentVariables['SUPABASE_TELEMETRY_DISABLED'] = '1'
  $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw "Unable to start Supabase CLI for $Operation." }
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  if ($process.ExitCode -ne 0) {
    $safeOut = Sanitize-Diagnostic $stdout
    $safeErr = Sanitize-Diagnostic $stderr
    throw "Read-only Supabase operation '$Operation' failed with exit code $($process.ExitCode). stdout=$safeOut stderr=$safeErr"
  }
  return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

if (-not (Test-Path -LiteralPath $LinkedRefPath)) { throw 'Missing local Supabase project reference.' }
$linked = (Get-Content -Raw -LiteralPath $LinkedRefPath).Trim()
if ($linked -ceq $ProductionRef) { throw "ABORTED: repository is linked to production '$ProductionRef'." }
if ($linked -cne $StagingRef) { throw "ABORTED: repository link '$linked' is not the required staging project '$StagingRef'." }

# Each row is a required fingerprint. Classification is based on the complete
# fingerprint set for a migration, not on a single representative object.
$sql = @"
WITH fingerprints AS (
  SELECT 'notification.fn.list_my_notifications' AS key, EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='list_my_notifications' AND pg_get_function_identity_arguments(p.oid)='p_limit integer, p_before timestamp with time zone, p_unread_only boolean') AS present
  UNION ALL SELECT 'notification.fn.register_notification_device', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='register_notification_device')
  UNION ALL SELECT 'notification.fn.mark_notification_read', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='mark_notification_read')
  UNION ALL SELECT 'notification.column.push_platform', EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='push_subscriptions' AND column_name='platform')
  UNION ALL SELECT 'notification.column.push_token', EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='push_subscriptions' AND column_name='push_token')
  UNION ALL SELECT 'notification.policy.notifications_read', EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND policyname='Users can read their own notifications')
  UNION ALL SELECT 'auth.fn.admin_reset_user_password', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin_reset_user_password')
  UNION ALL SELECT 'auth.fn.admin_set_user_lock', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin_set_user_lock')
  UNION ALL SELECT 'auth.fn.admin_update_user_credentials', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin_update_user_credentials')
  UNION ALL SELECT 'auth.fn.admin_get_user_email', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin_get_user_email')
  UNION ALL SELECT 'client.fn.list_crm_clients_secure', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='list_crm_clients_secure')
  UNION ALL SELECT 'client.fn.create_crm_client_secure', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='create_crm_client_secure')
  UNION ALL SELECT 'client.fn.update_crm_client_secure', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='update_crm_client_secure')
  UNION ALL SELECT 'client.fn.delete_crm_client_secure', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='delete_crm_client_secure')
  UNION ALL SELECT 'client.revocation.crm_clients_insert', CASE WHEN to_regclass('public.crm_clients') IS NULL THEN false ELSE NOT has_table_privilege('authenticated','public.crm_clients','INSERT') END
  UNION ALL SELECT 'client.revocation.crm_clients_update', CASE WHEN to_regclass('public.crm_clients') IS NULL THEN false ELSE NOT has_table_privilege('authenticated','public.crm_clients','UPDATE') END
  UNION ALL SELECT 'client.revocation.crm_clients_delete', CASE WHEN to_regclass('public.crm_clients') IS NULL THEN false ELSE NOT has_table_privilege('authenticated','public.crm_clients','DELETE') END
  UNION ALL SELECT 'deal.fn.get_crm_deal_secure', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='get_crm_deal_secure')
  UNION ALL SELECT 'deal.fn.create_crm_deal_secure', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='create_crm_deal_secure')
  UNION ALL SELECT 'deal.fn.create_project_from_won_deal_v2', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='create_project_from_won_deal_v2')
  UNION ALL SELECT 'deal.policy.deal_files', EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND policyname='sensitive_crm_deal_files_read')
  UNION ALL SELECT 'deal.revocation.crm_deals_insert', CASE WHEN to_regclass('public.crm_deals') IS NULL THEN false ELSE NOT has_table_privilege('authenticated','public.crm_deals','INSERT') END
  UNION ALL SELECT 'deal.revocation.crm_deals_update', CASE WHEN to_regclass('public.crm_deals') IS NULL THEN false ELSE NOT has_table_privilege('authenticated','public.crm_deals','UPDATE') END
  UNION ALL SELECT 'deal.revocation.crm_deals_delete', CASE WHEN to_regclass('public.crm_deals') IS NULL THEN false ELSE NOT has_table_privilege('authenticated','public.crm_deals','DELETE') END
  UNION ALL SELECT 'file.fn.storage_object_metadata_allowed', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='storage_object_metadata_allowed')
  UNION ALL SELECT 'file.fn.contract_read_authorizer', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='can_read_contract_document_file')
  UNION ALL SELECT 'file.fn.hr_read_authorizer', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='can_read_hr_document_file')
  UNION ALL SELECT 'file.fn.list_contract_documents_secure', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='list_contract_documents_secure')
  UNION ALL SELECT 'file.policy.hr_documents', EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND policyname='sensitive_hr_documents_read')
  UNION ALL SELECT 'file.policy.contract_documents', EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND policyname='sensitive_contract_documents_read')
  UNION ALL SELECT 'phase_a.table.task_waiting_history', to_regclass('public.task_waiting_history') IS NOT NULL
  UNION ALL SELECT 'phase_a.table.task_blocker_history', to_regclass('public.task_blocker_history') IS NOT NULL
  UNION ALL SELECT 'phase_a.column.tasks_work_state', EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='tasks' AND column_name='work_state')
  UNION ALL SELECT 'phase_a.index.task_my_day_state', to_regclass('public.task_my_day_state_idx') IS NOT NULL
  UNION ALL SELECT 'phase_a.fn.start_task', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='start_task')
  UNION ALL SELECT 'phase_a.fn.mark_task_waiting', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='mark_task_waiting')
  UNION ALL SELECT 'phase_a.fn.complete_task_productivity', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='complete_task_productivity')
  UNION ALL SELECT 'phase_b.table.task_dependencies', to_regclass('public.task_dependencies') IS NOT NULL
  UNION ALL SELECT 'phase_b.fn.create_task_dependency', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='create_task_dependency')
  UNION ALL SELECT 'phase_b.fn.complete_task_and_handoff', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='complete_task_and_handoff')
  UNION ALL SELECT 'phase_b.trigger.dependency_context_guard', EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relnamespace='public'::regnamespace AND c.relname='task_dependencies' AND t.tgname='task_dependency_context_guard')
  UNION ALL SELECT 'phase_b.index.active_pair', to_regclass('public.task_dependencies_active_pair_idx') IS NOT NULL
  UNION ALL SELECT 'phase_b.index.predecessor', to_regclass('public.task_dependencies_predecessor_idx') IS NOT NULL
  UNION ALL SELECT 'phase_c.fn.list_project_command_center', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='list_project_command_center')
  UNION ALL SELECT 'phase_c.fn.list_attention_needed', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='list_attention_needed')
  UNION ALL SELECT 'phase_c.fn.list_upcoming_events', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='list_upcoming_events')
  UNION ALL SELECT 'phase_c.fn.get_project_health', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='get_project_health')
  UNION ALL SELECT 'phase_c.fn.get_project_operational_summary', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='get_project_operational_summary')
)
SELECT 'HRFORENSIC|' || key || '|' || present::text AS marker FROM fingerprints ORDER BY key;
"@

try {
  Set-Content -LiteralPath $SqlPath -Value $sql -Encoding UTF8
  $result = Invoke-SupabaseCli @('db','query','--linked','--project-ref',$ProductionRef,'--file',$SqlPath,'--output-format','text') 'production catalog fingerprints'
  $markers = @{}
  foreach ($match in [regex]::Matches($result.StdOut, 'HRFORENSIC\|([A-Za-z0-9_.-]+)\|(true|false)')) { $markers[$match.Groups[1].Value] = ($match.Groups[2].Value -eq 'true') }
  $groups = [ordered]@{
    notification_backend = @($markers.Keys | Where-Object { $_ -like 'notification.*' })
    auth_backend = @($markers.Keys | Where-Object { $_ -like 'auth.*' })
    client_backend = @($markers.Keys | Where-Object { $_ -like 'client.*' })
    deal_backend = @($markers.Keys | Where-Object { $_ -like 'deal.*' })
    file_backend = @($markers.Keys | Where-Object { $_ -like 'file.*' })
    phase_a = @($markers.Keys | Where-Object { $_ -like 'phase_a.*' })
    phase_b = @($markers.Keys | Where-Object { $_ -like 'phase_b.*' })
    phase_c = @($markers.Keys | Where-Object { $_ -like 'phase_c.*' })
  }
  $expectedCounts = @{ notification_backend = 6; auth_backend = 4; client_backend = 7; deal_backend = 6; file_backend = 6; phase_a = 7; phase_b = 6; phase_c = 5 }
  foreach ($name in $groups.Keys) {
    $keys = @($groups[$name]); $present = @($keys | Where-Object { $markers[$_] -eq $true }).Count
    if ($keys.Count -ne $expectedCounts[$name]) { $state = 'INDETERMINATE' } elseif ($present -eq 0) { $state = 'NOT_APPLIED' } elseif ($present -eq $keys.Count) { $state = 'FULLY_APPLIED' } else { $state = 'PARTIALLY_APPLIED' }
    foreach ($key in $keys) { Write-Output ("fingerprint {0} = {1}" -f $key, $(if ($markers[$key]) { 'PRESENT' } else { 'ABSENT' })) }
    Write-Output ("{0} = {1} ({2}/{3} fingerprints)" -f $name,$state,$present,$keys.Count)
  }

  $functionResult = Invoke-SupabaseCli @('functions','list','--project-ref',$ProductionRef,'--output-format','json') 'production Edge Function inventory'
  $functionText = $functionResult.StdOut
  if ($functionText -match 'file-signed-url') { 'file_signed_url = PRESENT' } else { 'file_signed_url = ABSENT' }

  $revocationKeys = @($markers.Keys | Where-Object { $_ -like '*.revocation.*' })
  $revoked = @($revocationKeys | Where-Object { $markers[$_] -eq $true }).Count
  if ($revoked -eq 0) { 'legacy_write_revocations_active = NO'; 'old_web_currently_safe = YES' }
  elseif ($revoked -eq $revocationKeys.Count) { 'legacy_write_revocations_active = YES'; 'old_web_currently_safe = NO' }
  else { 'legacy_write_revocations_active = PARTIAL'; 'old_web_currently_safe = INDETERMINATE' }
  'PRODUCTION FORENSIC INSPECTION: COMPLETE'
}
finally {
  if (Test-Path -LiteralPath $SqlPath) { Remove-Item -LiteralPath $SqlPath -Force -ErrorAction SilentlyContinue }
}
