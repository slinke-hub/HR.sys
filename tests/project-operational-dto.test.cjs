const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const esbuild = require('esbuild');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const dtoSource = read('src/shared/domain-dto.ts');
const transformed = esbuild.transformSync(dtoSource, { loader: 'ts', format: 'cjs', target: 'es2020' }).code;
const dtoModule = { exports: {} };
vm.runInNewContext(transformed, { module: dtoModule, exports: dtoModule.exports, require });
const toProjectDto = dtoModule.exports.toProjectDto;

const project = { id: 'p-1', project_name: 'Synthetic Project', progress_percent: 88, health_status: 'AT_RISK' };
const operationalState = { progress_percent: 0, health_status: 'ON_TRACK', reason_codes: [] };

assert.equal(toProjectDto(project, false, operationalState).progress_percent, 0, 'server-calculated zero progress must remain zero');
assert.equal(toProjectDto(project, false, operationalState).health_status, 'ON_TRACK');
assert.deepEqual(Array.from(toProjectDto(project, false, operationalState).reason_codes), []);
assert.throws(() => toProjectDto(project, false), /Authoritative Project operational state is unavailable/);
assert.throws(() => toProjectDto(project, false, { health_status: 'ON_TRACK', reason_codes: [] }), /Authoritative Project progress is unavailable/);
assert.throws(() => toProjectDto(project, false, { progress_percent: 0, reason_codes: [] }), /Authoritative Project health is unavailable/);
assert.throws(() => toProjectDto(project, false, { progress_percent: 0, health_status: 'ON_TRACK', reason_codes: null }), /Authoritative Project health reasons are unavailable/);
assert.equal(toProjectDto(project, false, { progress_percent: 0, health_status: 'UNKNOWN', reason_codes: [] }).health_status, 'UNKNOWN');

const app = read('js/app.js');
const functionSource = name => {
  const match = app.match(new RegExp(`function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`));
  assert.ok(match, `missing ${name}`);
  return match[0];
};
const progressValue = vm.runInNewContext(`(${functionSource('projectProgressValue')})`);
assert.equal(progressValue(0), 0, 'authoritative zero must not be treated as missing');
assert.equal(progressValue(undefined), null, 'missing progress must remain unavailable');
assert.equal(progressValue(null), null);
assert.equal(progressValue('0'), null, 'malformed string progress must fail closed');
const health = vm.runInNewContext(`(${functionSource('effectiveProjectHealth')})`);
assert.equal(health({ health_status: 'ON_TRACK' }), 'ON_TRACK');
assert.equal(health({}), 'UNKNOWN', 'missing health must not become ON_TRACK');
assert.equal(health({ health_status: 'invalid' }), 'UNKNOWN');
const snapshotValidator = vm.runInNewContext(`(${functionSource('hasProjectOperationalSnapshot')})`, { projectProgressValue: progressValue });
assert.equal(snapshotValidator({ progress_percent: 0, health: 'ON_TRACK', reason_codes: [] }), true);
assert.equal(snapshotValidator({ progress_percent: null, health: 'ON_TRACK', reason_codes: [] }), false);
assert.equal(snapshotValidator({ progress_percent: 0, reason_codes: [] }), false);
assert.equal(snapshotValidator({ progress_percent: 0, health: 'ON_TRACK', reason_codes: null }), false);
const countLabel = vm.runInNewContext(`(${functionSource('projectOperationalCount')})`);
assert.equal(countLabel(0), '0');
assert.equal(countLabel(undefined), '—', 'missing aggregate counts must not become zero');
const summaryValidator = vm.runInNewContext(`(${functionSource('hasProjectOperationalSummary')})`, { hasProjectOperationalSnapshot: snapshotValidator });
const summary = {
  progress_percent: 0, health_status: 'ON_TRACK', reason_codes: [], event_status: 'NO_EVENT', event_date: null,
  event_countdown_days: null, tasks: [], todos: [], financials_included: false,
  counts: { tasks: 0, completed_tasks: 0, actionable_tasks: 0, overdue_tasks: 0, due_today_tasks: 0, waiting_tasks: 0, blocked_tasks: 0, dependency_blocked_tasks: 0, open_todos: 0, overdue_todos: 0 },
};
assert.equal(summaryValidator(summary), true);
assert.equal(summaryValidator({ ...summary, counts: { ...summary.counts, tasks: undefined } }), false);
assert.equal(summaryValidator({ ...summary, financials_included: true }), false);

assert.match(app, /projectProgressLabel\(item\.progress_percent\)/, 'Command Center must use explicit progress availability');
assert.match(app, /projectProgressLabel\(progress\)/, 'Portfolio must use explicit progress availability');
assert.match(app, /projectProgressLabel\(project\.progress_percent\)/, 'Detail must use explicit progress availability');
assert.doesNotMatch(app, /Number\(item\.progress_percent\s*\|\|\s*0\)|Number\(project\.progress_percent\s*\|\|\s*0\)|Number\(project\.progress_percent\s*\|\|\s*0\)/);
assert.match(app, /healthState === 'ON_TRACK'/, 'Command Center must not infer On Track when health is absent');
assert.match(app, /healthReasonsUnavailable/);
assert.match(app, /hasProjectOperationalSummary\(operationalSummaryResult\.data\)/);
assert.match(app, /projectOperationalCount\(counts\[key\]\)/);
assert.match(app, /projectText\('operationalSummaryUnavailable'\)/);

const contracts = read('src/shared/productivity-phase-c-contract.ts');
const types = read('src/shared/domain-types.ts');
const services = read('src/shared/domain-services.ts');
assert.match(types, /interface ProjectOperationalState[\s\S]*?progress_percent: number[\s\S]*?health_status: ProjectOperationalHealth[\s\S]*?reason_codes: Array/);
assert.match(types, /type AuthoritativeProjectDto = Omit<Project,[\s\S]*?& ProjectOperationalState/);
assert.match(types, /interface ClientDetailsDto[\s\S]*?projects: AuthoritativeProjectDto\[\]/);
assert.match(contracts, /interface ProjectCommandCenterCard[\s\S]*?progress_percent: number/);
assert.match(contracts, /interface ProjectOperationalSummary[\s\S]*?progress_percent: number[\s\S]*?health_status: ProjectHealthState[\s\S]*?reason_codes:/);
assert.match(services, /fetchProjects\?: \(\) => Promise<AuthoritativeProjectDto\[\]>/);
assert.match(services, /fetchProjectDetails\?: \(id: string\) => Promise<ServiceResult<\{ project: AuthoritativeProjectDto/);
assert.match(services, /createProject\?: \(payload: Record<string, unknown>\) => Promise<ServiceResult<AuthoritativeProjectDto>>/);
assert.match(services, /updateProject\?: \(id: string, payload: Record<string, unknown>\) => Promise<ServiceResult<AuthoritativeProjectDto>>/);
assert.match(services, /fetchProjectOperationalSummary\?: \(id: string\) => Promise<ServiceResult<ProjectOperationalSummary>>/);
assert.match(services, /fetchProjectCommandCenter\?:[\s\S]*?Promise<ServiceResult<ProjectCommandCenterCard\[\]>>/);
assert.match(services, /fetchClientDetails\?: \(id: string\) => Promise<ClientDetailsDto \| null>/);

const migration = read('supabase/migrations/20261002090000_project_operations_phase_1.sql');
for (const consumer of ['get_crm_client_secure', 'list_accessible_projects_secure', 'get_project_detail_secure']) {
  assert.ok(migration.includes(`FUNCTION public.${consumer}`), `${consumer} must remain an authoritative source`);
}
assert.match(migration, /'health_status', snapshot\.item->>'health'[\s\S]*?'progress_percent', \(snapshot\.item->>'progress_percent'\)::integer[\s\S]*?'reason_codes', snapshot\.item->'reason_codes'/);
assert.match(migration, /'health_status', v_snapshot->>'health'[\s\S]*?'progress_percent', \(v_snapshot->>'progress_percent'\)::integer[\s\S]*?'reason_codes', v_snapshot->'reason_codes'/);

console.log('Project authoritative operational DTO tests passed.');
