const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261002090000_project_operations_phase_1.sql'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js/db.js'), 'utf8');
const contracts = fs.readFileSync(path.join(root, 'src/shared/productivity-phase-c-contract.ts'), 'utf8');
const services = fs.readFileSync(path.join(root, 'src/shared/domain-services.ts'), 'utf8');
const dto = fs.readFileSync(path.join(root, 'src/shared/domain-dto.ts'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const phaseB = fs.readFileSync(path.join(root, 'supabase/migrations/20260930105000_productivity_phase_b.sql'), 'utf8');

assert.match(migration, /^-- Project Operations Phase 1[\s\S]*?\nBEGIN;/);
assert.match(migration, /COMMIT;\s*$/);
assert.match(migration, /public\.project_operational_snapshot\(p_project_id, auth\.uid\(\)\)/);
assert.match(migration, /p_user_id IS DISTINCT FROM auth\.uid\(\)/);
assert.match(migration, /SECURITY DEFINER/);

// Project members receive a deterministic shared aggregate; Task DTO rows
// remain separately protected by can_access_task.
const snapshot = migration.slice(migration.indexOf('CREATE OR REPLACE FUNCTION public.project_operational_snapshot'), migration.indexOf('-- The Client detail façade'));
assert.match(snapshot, /WHERE task\.project_id = p_project_id\s+AND task\.archived_at IS NULL/);
assert.doesNotMatch(snapshot, /AND\s+public\.can_access_task/);
assert.match(snapshot, /IF p_user_id IS NULL OR p_user_id IS DISTINCT FROM auth\.uid\(\)[\s\S]*?NOT public\.can_access_project\(p_project_id, p_user_id\)/);
assert.match(snapshot, /COUNT\(\*\) FILTER \(WHERE task\.status = 'completed'\)/);
assert.match(snapshot, /IF task_count > 0 THEN\s+progress := ROUND\(100\.0 \* completed_task_count \/ task_count\)::integer;\s+END IF;/);
assert.match(snapshot, /'progress_percent', progress/);
assert.match(snapshot, /'health', health_state/);

// Client Project DTOs use the same snapshot while preserving financial redaction.
assert.match(migration, /to_regprocedure\('public\.get_crm_client_secure_project_ops_base\(uuid\)'\) IS NULL/);
assert.match(migration, /ALTER FUNCTION public\.get_crm_client_secure\(uuid\) RENAME TO get_crm_client_secure_project_ops_base/);
assert.match(migration, /get_crm_client_secure_project_ops_base\(p_client_id\)/);
assert.match(migration, /'health_status', snapshot\.item->>'health'/);
assert.match(migration, /'progress_percent', \(snapshot\.item->>'progress_percent'\)::integer/);
assert.match(migration, /'reason_codes', snapshot\.item->'reason_codes'/);
assert.match(migration, /CASE WHEN v_has_financial_access THEN project\.budget_amount END/);
assert.match(migration, /get_project_detail_secure\(p_project_id uuid\)[\s\S]*?public\.can_access_project\(p_project_id, v_user\)[\s\S]*?v_snapshot := public\.project_operational_snapshot/);
assert.match(migration, /CASE WHEN v_can_financial THEN to_jsonb\(v_project\.budget_amount\) ELSE 'null'::jsonb END/);

// Project summary has only authorized detail DTOs and never exposes financials
// or Phase B dependency-edge metadata beyond the existing dependency contract.
const summary = migration.slice(migration.indexOf('CREATE OR REPLACE FUNCTION public.get_project_operational_summary'), migration.indexOf('CREATE OR REPLACE FUNCTION public.get_project_health'));
assert.match(summary, /public\.can_access_project\(p_project_id, v_user\)/);
assert.match(summary, /public\.can_access_task\(task\.id, v_user\)/);
assert.match(summary, /'financials_included', false/);
assert.doesNotMatch(summary, /'dependency_blocked'/);
assert.doesNotMatch(summary, /'assignee_id'|'assignee_ids'|'created_by'|'department'/);
assert.match(migration, /list_project_command_center\([\s\S]*?public\.is_project_portfolio_admin\(v_user\)/);
assert.match(migration, /get_project_health\(p_project_id uuid\)[\s\S]*?public\.can_access_project\(p_project_id, auth\.uid\(\)\)/);

// Phase B edge/detail authorization is preserved without redefining its RPC.
assert.match(phaseB, /CREATE OR REPLACE FUNCTION public\.list_task_dependencies_secure\(p_task_id uuid\)/);
assert.match(phaseB, /AND public\.can_access_task\(p_task_id, auth\.uid\(\)\)/);
assert.match(phaseB, /public\.can_access_task\(predecessor_task_id, auth\.uid\(\)\)\s+OR public\.can_access_task\(successor_task_id, auth\.uid\(\)\)/);
assert.doesNotMatch(migration, /CREATE OR REPLACE FUNCTION public\.list_task_dependencies_secure/);

// Completion is leadership-only, Task-derived and requires at least one Task.
assert.match(migration, /get_project_completion_readiness\(p_project_id uuid\)[\s\S]*?NO_TASKS[\s\S]*?INCOMPLETE_TASKS[\s\S]*?BLOCKED_TASKS[\s\S]*?WAITING_TASKS[\s\S]*?UNRESOLVED_DEPENDENCY_CHAIN/);
assert.match(migration, /'ready', total_tasks > 0 AND incomplete_tasks = 0/);
assert.match(migration, /'zero_task_project_closure_ready', false/);
assert.match(migration, /IF v_readiness->'ready' = 'false'::jsonb THEN[\s\S]*?'completion_readiness', v_readiness/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.get_project_completion_readiness\(uuid\) FROM PUBLIC, anon/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.get_project_completion_readiness\(uuid\) TO authenticated/);
assert.match(migration, /task\.status = 'completed'/);
assert.match(migration, /task\.status IS DISTINCT FROM 'completed'/);

// Creation cannot create a terminal Project; old caller-status Deal RPC retired.
assert.match(migration, /v_lifecycle_status NOT IN \('PLANNING', 'ACTIVE', 'ON_HOLD'\)/);
assert.match(migration, /v_patch := p_changes - ARRAY\[[^;]*'lifecycle_status','health_status','progress_percent'/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.create_project_from_won_deal\(uuid, date, date, date, date, text, numeric, numeric, text, text\) FROM PUBLIC, anon, authenticated/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.change_project_status\(uuid, text\) TO authenticated/);

assert.doesNotMatch(migration, /\b(ALTER TABLE|DELETE FROM|TRUNCATE|DROP TABLE)\b/i);
assert.doesNotMatch(html, /id="(?:new|edit)Project(?:Health|Progress)"/);
const createStatus = html.match(/<select id="newProjectStatus"[\s\S]*?<\/select>/)?.[0] || '';
assert.doesNotMatch(createStatus, /value="(?:COMPLETED|CANCELLED)"/);
assert.doesNotMatch(app, /health_status:\s*'AT_RISK'|health_status:\s*'ON_TRACK'/);
assert.match(app, /UNKNOWN: projectText\('healthUnavailable'\)/);
assert.match(app, /healthUnavailable: \['Health unavailable', 'حالة الصحة غير متاحة'\]/);
assert.match(app, /noTasksReason: \['projects must have at least one Task before completion', 'يجب أن يحتوي المشروع على مهمة واحدة على الأقل قبل إكماله'\]/);
assert.match(app, /const detailResult = await db\.fetchProjectDetails\(id\)/);
assert.match(app, /projectDetailUnavailable/);
assert.doesNotMatch(app, /project\?\.health \|\| 'ON_TRACK'/);
assert.match(app, /NO_TASKS: 'noTasksReason'/);
assert.match(db, /get_project_completion_readiness/);
assert.match(db, /completion_readiness\?\.ready === false/);
assert.match(contracts, /interface ProjectCompletionReadiness/);
assert.match(contracts, /zero_task_project_closure_ready: false/);
assert.match(services, /completionReadiness: \(id: string\)/);
assert.match(dto, /operationalState: ProjectOperationalState/);
assert.doesNotMatch(dto, /operationalState: [^,]+ = \{\}/);
assert.match(dto, /health_status: health/);
assert.match(dto, /progress_percent: progress/);
assert.match(dto, /Authoritative Project progress is unavailable/);
assert.doesNotMatch(dto, /health_status: project\.health_status|progress_percent: project\.progress_percent/);

console.log('Project Operations Phase 1 contract tests passed.');
