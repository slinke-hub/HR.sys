const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const runtime = require('./helpers/postgres-docker-runtime.cjs');

const root = path.resolve(__dirname, '..');
const schemaFile = process.env.HRSYS_PRODUCTION_SCHEMA_FILE;
const workflowCompatibility = path.join(root, 'supabase', 'migrations', '20261111100000_crm_workflow_kind_constraint_compatibility.sql');
const migrations = [
  ['20261112100000_crm_production_release_foundation.sql', 'D9B5934102B646589B2A20B17BC4BC4EF3D03B2CA788D25B7AC88AB57FA308B9'],
  ['20261112110000_mq20_production_release_execution.sql', '43220CFA78B8877F55D288831D1D712D5E96E6F5D16D3147371627DCE21D1294'],
  ['20261112120000_crm_production_security_compatibility.sql', '6A4F642A5FD612F74C77800E1CBECD6FC0FBF179AEBA7BFCC7627F3A5B63B7EB'],
  ['20261113100000_crm_production_authorized_read_policy_hardening.sql', 'B3DF3213109F78D37E0F9E099948204DDD82E270A53CC91ED9535A46D0F7EE26'],
];

function lfSha256(value) {
  return crypto.createHash('sha256').update(value.replace(/\r\n/g, '\n'), 'utf8').digest('hex').toUpperCase();
}

const bootstrap = String.raw`
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
CREATE ROLE authenticator NOLOGIN;
CREATE ROLE supabase_admin NOLOGIN;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT current_setting('request.jwt.claim.role', true)
$$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;
CREATE TABLE auth.users (
  instance_id uuid, id uuid PRIMARY KEY, aud varchar(255), role varchar(255), email varchar(255),
  encrypted_password varchar(255), email_confirmed_at timestamptz, invited_at timestamptz,
  confirmation_token varchar(255), confirmation_sent_at timestamptz, recovery_token varchar(255),
  recovery_sent_at timestamptz, email_change_token_new varchar(255), email_change varchar(255),
  email_change_sent_at timestamptz, last_sign_in_at timestamptz, raw_app_meta_data jsonb,
  raw_user_meta_data jsonb, is_super_admin boolean, created_at timestamptz, updated_at timestamptz,
  phone text, phone_confirmed_at timestamptz, phone_change text, phone_change_token varchar(255),
  phone_change_sent_at timestamptz, confirmed_at timestamptz, email_change_token_current varchar(255),
  email_change_confirm_status smallint, banned_until timestamptz, reauthentication_token varchar(255),
  reauthentication_sent_at timestamptz, is_sso_user boolean, deleted_at timestamptz, is_anonymous boolean
);
CREATE TABLE auth.identities (
  id uuid PRIMARY KEY, user_id uuid, identity_data jsonb, provider text, provider_id text,
  last_sign_in_at timestamptz, created_at timestamptz, updated_at timestamptz, email text
);
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
DROP SCHEMA public CASCADE;
`;

function checkSchemaDump(file) {
  assert.ok(file && fs.existsSync(file), 'Set HRSYS_PRODUCTION_SCHEMA_FILE to the supplied schema-only export.');
  const sql = fs.readFileSync(file, 'utf8');
  assert.match(sql, /PostgreSQL database dump/, 'Input is not a pg_dump SQL file.');
  assert.doesNotMatch(sql, /^\s*COPY\s+.+\s+FROM\s+stdin;/m, 'Dump includes table data; stop and do not import.');
  assert.doesNotMatch(sql, /^-- Data for /m, 'Dump includes table-data sections; stop and do not import.');
  assert.doesNotMatch(sql, /^SELECT pg_catalog\.setval\(/m, 'Dump includes sequence data; stop and do not import.');
  const secretPattern = /(?:service[_ -]?role[_ -]?(?:key|secret)|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|Bearer\s+[A-Za-z0-9._~-]{20,}|(?:password|secret|api[_-]?key|token)\s*[:=]\s*'[^']{12,}'|postgres(?:ql)?:\/\/[^\s'";]+:[^\s'";]+@)/i;
  assert.doesNotMatch(sql, secretPattern, 'Potential credential literal found; do not import/share this dump until reviewed.');
  return sql;
}

async function main() {
  const schema = checkSchemaDump(schemaFile);
  const localMigrations = migrations.map(([name, expected]) => {
    const file = path.join(root, 'supabase', 'migrations', name);
    assert.ok(fs.existsSync(file), `Missing reviewed migration: ${name}`);
    const sql = fs.readFileSync(file, 'utf8');
    assert.equal(lfSha256(sql), expected, `Approved LF checksum mismatch: ${name}`);
    return { name, sql };
  });
  console.log(`Schema fixture checks PASS (bytes=${Buffer.byteLength(schema)}, sha256=${crypto.createHash('sha256').update(schema).digest('hex').toUpperCase()}, no row-data sections, no credential-pattern hits).`);

  let container;
  try {
    const instance = await runtime.start('hrsys-prod-crm-four-migrations');
    container = instance.name;
    assert.match(instance.version, /17\.6\b/, 'Disposable runtime must be PostgreSQL 17.6.');
    runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', bootstrap], container);
    runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', schemaFile], container);

    const workflowBaseline = runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-At', '-c', `
      SELECT jsonb_build_object(
        'tasks_crm_workflow_kind_check_present', EXISTS (SELECT 1 FROM pg_constraint c
          WHERE c.conrelid='public.tasks'::regclass AND c.conname='tasks_crm_workflow_kind_check'),
        'tasks_crm_workflow_kind_check_allows_contact_discussion', EXISTS (SELECT 1 FROM pg_constraint c
          WHERE c.conrelid='public.tasks'::regclass AND c.conname='tasks_crm_workflow_kind_check'
            AND pg_get_constraintdef(c.oid) ILIKE '%CONTACT_DISCUSSION%'),
        'crm_deals_negotiation_check_exists', EXISTS (SELECT 1 FROM pg_constraint c
          WHERE c.conrelid='public.crm_deals'::regclass AND c.contype='c'
            AND pg_get_constraintdef(c.oid) ILIKE '%NEGOTIATION%'),
        'crm_workflow_kind_column', (SELECT jsonb_build_object('type', format_type(a.atttypid,a.atttypmod), 'not_null', a.attnotnull)
          FROM pg_attribute a WHERE a.attrelid='public.tasks'::regclass AND a.attname='crm_workflow_kind' AND NOT a.attisdropped),
        'related_task_constraints', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name',c.conname,'definition',pg_get_constraintdef(c.oid)) ORDER BY c.conname),'[]'::jsonb)
          FROM pg_constraint c WHERE c.conrelid='public.tasks'::regclass AND c.contype='c'
            AND (c.conname ILIKE '%workflow%kind%' OR pg_get_constraintdef(c.oid) ILIKE '%crm_workflow_kind%'))
      );`], container).trim();
    console.log(`PRODUCTION_WORKFLOW_PREREQUISITES ${workflowBaseline}`);

    assert.ok(fs.existsSync(workflowCompatibility), 'Missing separate workflow-kind compatibility prerequisite.');
    runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', workflowCompatibility], container);
    const expandedWorkflowCheck = runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-At', '-c', `
      SELECT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.tasks'::regclass
        AND c.conname='tasks_crm_workflow_kind_check' AND c.convalidated
        AND pg_get_constraintdef(c.oid) ILIKE '%QUOTE_PROPOSAL_DESIGN%'
        AND pg_get_constraintdef(c.oid) ILIKE '%CONTACT_DISCUSSION%'
        AND pg_get_constraintdef(c.oid) ILIKE '%IS NULL%');`], container).trim();
    assert.equal(expandedWorkflowCheck, 't', 'Separate workflow-kind compatibility migration did not establish the exact required constraint.');
    console.log('WORKFLOW_KIND_COMPATIBILITY=PASS; nullable, Design and Contact Discussion values preserved.');

    for (const migration of localMigrations) {
      const migrationPath = path.join(root, 'supabase', 'migrations', migration.name);
      runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', migrationPath], container);
      console.log(`MIGRATION_PASS ${migration.name}`);
      let intermediate;
      if (migration.name.startsWith('20261112100000')) {
        intermediate = runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-At', '-c', `
          SELECT (SELECT atttypid='uuid[]'::regtype AND attnotnull FROM pg_attribute
            WHERE attrelid='public.crm_deals'::regclass AND attname='assignee_ids' AND NOT attisdropped),
            to_regclass('public.crm_generated_tasks') IS NOT NULL,
            to_regprocedure('public.create_crm_deal_secure(jsonb)') IS NOT NULL,
            to_regprocedure('public.update_crm_deal_secure(uuid,jsonb)') IS NOT NULL,
            to_regprocedure('public.get_crm_deal_secure(uuid)') IS NOT NULL;`], container).trim();
        assert.equal(intermediate, 't|t|t|t|t', 'Migration 1 intermediate CRM compatibility failed.');
      } else if (migration.name.startsWith('20261112110000')) {
        intermediate = runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-At', '-c', `
          SELECT to_regprocedure('public.execute_crm_contact_discussion_task(uuid,text,text,text)') IS NOT NULL,
            has_function_privilege('authenticated','public.execute_crm_contact_discussion_task(uuid,text,text,text)','EXECUTE'),
            NOT has_function_privilege('anon','public.execute_crm_contact_discussion_task(uuid,text,text,text)','EXECUTE');`], container).trim();
        assert.equal(intermediate, 't|t|t', 'Migration 2 intermediate MQ-20 RPC compatibility failed.');
      } else if (migration.name.startsWith('20261112120000')) {
        intermediate = runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-At', '-c', `
          SELECT NOT has_function_privilege('authenticated','public.is_mq20_profile(uuid)','EXECUTE'),
            has_function_privilege('authenticated','public.is_mq20_current_user()','EXECUTE'),
            (SELECT count(*)=13 FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'mq20_%'),
            to_regprocedure('public.can_manage_task_attachments(uuid,uuid)') IS NOT NULL,
            to_regprocedure('public.can_read_task_attachment_file(text,uuid)') IS NOT NULL;`], container).trim();
        assert.equal(intermediate, 't|t|t|t|t', 'Migration 3 intermediate MQ-20/attachment compatibility failed.');
      } else if (migration.name.startsWith('20261113100000')) {
        intermediate = runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-At', '-c', `
          SELECT (SELECT count(*)=0 FROM pg_policies WHERE schemaname='public'
              AND tablename IN ('crm_deal_activity','crm_deal_approval_steps','crm_deal_attachments')
              AND policyname IN ('Authenticated users can view deal activity','Authenticated users can view deal approvals','Authenticated users can view deal attachments')),
            (SELECT count(*)=6 FROM pg_policies WHERE schemaname='public' AND tablename='crm_deal_attachments');`], container).trim();
        assert.equal(intermediate, 't|t', 'Migration 4 intermediate CRM read-policy hardening failed.');
      }
      console.log(`INTERMEDIATE_STATE_PASS ${migration.name}: ${intermediate}`);
    }

    const post = runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-At', '-c', `
      SELECT current_setting('server_version_num')::int BETWEEN 170000 AND 179999,
        to_regclass('public.crm_generated_tasks') IS NOT NULL,
        to_regprocedure('public.execute_crm_contact_discussion_task(uuid,text,text,text)') IS NOT NULL,
        to_regprocedure('public.is_mq20_current_user()') IS NOT NULL,
        to_regprocedure('public.is_mq20_profile(uuid)') IS NOT NULL,
        (SELECT count(*)=13 FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'mq20_%'),
        (SELECT count(*)=0 FROM pg_policies WHERE schemaname='public' AND tablename IN ('crm_deal_activity','crm_deal_approval_steps','crm_deal_attachments') AND policyname IN ('Authenticated users can view deal activity','Authenticated users can view deal approvals','Authenticated users can view deal attachments')),
        (SELECT count(*)=3 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass AND tgname IN ('crm_deals_enforce_workflow_transition','protect_lost_crm_deal_edits_trigger','crm_deal_assignees_sync') AND tgenabled='O'),
        has_function_privilege('authenticated','public.execute_crm_contact_discussion_task(uuid,text,text,text)','EXECUTE'),
        NOT has_function_privilege('anon','public.execute_crm_contact_discussion_task(uuid,text,text,text)','EXECUTE'),
        NOT has_function_privilege('authenticated','public.is_mq20_profile(uuid)','EXECUTE');`], container).trim();
    console.log(`FOUR_MIGRATION_POSTCONDITIONS=${post}`);
    assert.equal(post, 't|t|t|t|t|t|t|t|t|t|t', `Four-migration postcondition mismatch: ${post}`);
    console.log(`FOUR_MIGRATION_POSTCONDITIONS=PASS; PostgreSQL ${instance.version}.`);
  } finally {
    runtime.stop(container);
  }
}

main().catch(error => {
  // Avoid printing schema, credential-like values, or SQL text from errors.
  const raw = String(error && error.message || error);
  const plain = raw.replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, '');
  const message = plain.match(/ERROR:\s*[^\r\n]+/)?.[0]
    || plain.match(/Four-migration postcondition mismatch:\s*[^\r\n]+/)?.[0]
    || plain.split(/\r?\n/).find(line => /psql:.*(?:error|permission|does not exist|failed)/i.test(line))
    || plain.split(/\r?\n/).find(line => /assert|Missing reviewed|checksum|credential|data|postgres|permission|relation|function|role|schema/i.test(line))
    || plain.split(/\r?\n/).slice(-4).join(' | ');
  console.error(`FOUR_MIGRATION_TEST=FAIL: ${message || 'unclassified local fixture failure'}`);
  const diagnostics = plain.split(/\r?\n/).filter(line => /ERROR:|psql: .*error:|does not exist|permission denied|syntax error|Four-migration postcondition mismatch/i.test(line)).slice(0, 4);
  if (diagnostics.length) console.error(`SAFE_DIAGNOSTICS: ${diagnostics.join(' | ')}`);
  process.exitCode = 1;
});
