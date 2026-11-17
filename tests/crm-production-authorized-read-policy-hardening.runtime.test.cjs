const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const runtime = require('./helpers/postgres-docker-runtime.cjs');

const migration = path.resolve(__dirname, '../supabase/migrations/20261113100000_crm_production_authorized_read_policy_hardening.sql');
const setup = String.raw`
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
CREATE FUNCTION public.can_access_crm(uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT $1 = '10000000-0000-0000-0000-000000000001'::uuid
$$;

CREATE TABLE public.crm_deal_activity (id integer PRIMARY KEY, actor_id uuid, note text);
CREATE TABLE public.crm_deal_approval_steps (id integer PRIMARY KEY, note text);
CREATE TABLE public.crm_deal_attachments (
  id integer PRIMARY KEY,
  deal_id uuid,
  uploaded_by uuid,
  is_archived boolean,
  visible_to_project_assignee boolean
);
CREATE TABLE public.tasks (
  id uuid PRIMARY KEY,
  crm_deal_id uuid,
  crm_workflow_kind text,
  assignee_id uuid,
  created_by uuid,
  project_id uuid
);
CREATE TABLE public.projects (id uuid PRIMARY KEY, deal_id uuid, assigned_people uuid[]);
CREATE TABLE public.profiles (id uuid PRIMARY KEY, role text);

ALTER TABLE public.crm_deal_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deal_approval_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deal_attachments ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.crm_deal_activity, public.crm_deal_attachments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_deal_approval_steps TO authenticated;
GRANT SELECT ON public.crm_deal_approval_steps TO anon;
GRANT SELECT ON public.tasks, public.projects TO authenticated;

CREATE POLICY "Authenticated users can view deal activity" ON public.crm_deal_activity FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can add deal activity" ON public.crm_deal_activity FOR INSERT TO authenticated WITH CHECK (actor_id = auth.uid());
CREATE POLICY crm_authorized_activity_select ON public.crm_deal_activity FOR SELECT TO authenticated USING (public.can_access_crm(auth.uid()));
CREATE POLICY crm_authorized_activity_insert ON public.crm_deal_activity FOR INSERT TO authenticated WITH CHECK (public.can_access_crm(auth.uid()));

CREATE POLICY "Authenticated users can view deal approvals" ON public.crm_deal_approval_steps FOR SELECT TO authenticated USING (true);
CREATE POLICY crm_authorized_approval_steps_select ON public.crm_deal_approval_steps FOR SELECT TO authenticated USING (public.can_access_crm(auth.uid()));

CREATE POLICY "Authenticated users can view deal attachments" ON public.crm_deal_attachments FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can add deal attachments" ON public.crm_deal_attachments FOR INSERT TO authenticated WITH CHECK (uploaded_by = auth.uid());
CREATE POLICY "Owners and admins can delete deal attachments" ON public.crm_deal_attachments FOR DELETE TO authenticated USING (false);
CREATE POLICY crm_authorized_attachments_delete ON public.crm_deal_attachments FOR DELETE TO authenticated USING (public.can_access_crm(auth.uid()));
CREATE POLICY crm_authorized_attachments_insert ON public.crm_deal_attachments FOR INSERT TO authenticated WITH CHECK (public.can_access_crm(auth.uid()));
CREATE POLICY crm_authorized_attachments_select ON public.crm_deal_attachments FOR SELECT TO authenticated USING (
  public.can_access_crm(auth.uid()) OR EXISTS (
    SELECT 1 FROM public.tasks task
    WHERE task.crm_deal_id = crm_deal_attachments.deal_id
      AND task.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'
      AND auth.uid() IN (task.assignee_id, task.created_by)
  )
);
CREATE POLICY crm_project_shared_attachments_select ON public.crm_deal_attachments FOR SELECT TO authenticated USING (
  is_archived = FALSE AND visible_to_project_assignee = TRUE AND EXISTS (
    SELECT 1 FROM public.projects project
    WHERE project.deal_id = crm_deal_attachments.deal_id
      AND auth.uid() = ANY(COALESCE(project.assigned_people, ARRAY[]::UUID[]))
  )
);

INSERT INTO public.crm_deal_activity VALUES (1, '10000000-0000-0000-0000-000000000001', 'synthetic protected activity');
INSERT INTO public.crm_deal_approval_steps VALUES (1, 'synthetic approval');
INSERT INTO public.crm_deal_attachments VALUES
  (1, '20000000-0000-0000-0000-000000000001', NULL, false, false),
  (2, '20000000-0000-0000-0000-000000000002', NULL, false, true);
INSERT INTO public.projects VALUES
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', ARRAY['10000000-0000-0000-0000-000000000003'::uuid]);
INSERT INTO public.tasks VALUES
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'QUOTE_PROPOSAL_DESIGN', '10000000-0000-0000-0000-000000000003', NULL, NULL);
`;

async function main() {
  assert.ok(fs.existsSync(migration), 'Security migration is present.');
  const { name, version } = await runtime.start('hrsys-crm-policy-hardening');
  try {
    runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', setup], name);
    // Confirm the disposable fixture reproduces the expected normalized policy fingerprints.
    const fingerprints = runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-At', '-c', `
      SELECT tablename || ':' || policyname || ':' || md5(qual)
      FROM pg_policies WHERE schemaname='public' AND qual IS NOT NULL
      ORDER BY tablename, policyname`], name);
    for (const expected of [
      'crm_deal_activity:Authenticated users can view deal activity:b326b5062b2f0e69046810717534cb09',
      'crm_deal_activity:crm_authorized_activity_select:eb8c3613925a4ec015c5b577a9f8f737',
      'crm_deal_approval_steps:crm_authorized_approval_steps_select:eb8c3613925a4ec015c5b577a9f8f737',
      'crm_deal_attachments:crm_authorized_attachments_select:62764aebd28b1ac38c5f3b11558e7bf2',
      'crm_deal_attachments:crm_project_shared_attachments_select:d365bd9a306d4684348c68de08c83cc3',
    ]) assert.ok(fingerprints.includes(expected), `Fixture policy fingerprint mismatch: ${expected}`);

    runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', migration], name);
    const check = runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-At', '-c', `
      BEGIN;
      SET LOCAL ROLE authenticated;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002', true);
      SELECT 'unauthorized_counts=' ||
        (SELECT count(*) FROM public.crm_deal_activity) || ',' ||
        (SELECT count(*) FROM public.crm_deal_approval_steps) || ',' ||
        (SELECT count(*) FROM public.crm_deal_attachments);
      SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001', true);
      SELECT 'authorized_counts=' ||
        (SELECT count(*) FROM public.crm_deal_activity) || ',' ||
        (SELECT count(*) FROM public.crm_deal_approval_steps);
      SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003', true);
      SELECT 'design_and_project_attachments=' || (SELECT count(*) FROM public.crm_deal_attachments);
      ROLLBACK;`], name);
    assert.match(check, /unauthorized_counts=0,0,0/, 'Unprofiled user can no longer read CRM rows.');
    assert.match(check, /authorized_counts=1,1/, 'Authorized CRM employee retains activity and approval reads.');
    assert.match(check, /design_and_project_attachments=2/, 'Design-task and project-shared attachment access remain available.');

    const anonRead = runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-At', '-c', `
      BEGIN; SET LOCAL ROLE anon;
      SELECT 'anon_approval_count=' || count(*) FROM public.crm_deal_approval_steps;
      ROLLBACK;`], name);
    assert.match(anonRead, /anon_approval_count=0/, 'Anonymous approval reads are denied by RLS.');

    const writeCheck = runtime.run('psql', ['-U', 'postgres', '-d', 'postgres', '-At', '-c', `
      BEGIN; SET LOCAL ROLE authenticated;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001', true);
      DO $$ BEGIN
        BEGIN INSERT INTO public.crm_deal_approval_steps VALUES (2, 'unauthorized synthetic write');
          RAISE EXCEPTION 'approval INSERT unexpectedly succeeded';
        EXCEPTION WHEN insufficient_privilege THEN NULL; END;
      END $$;
      DO $$ DECLARE affected integer; BEGIN
        UPDATE public.crm_deal_approval_steps SET note='changed' WHERE id=1;
        GET DIAGNOSTICS affected = ROW_COUNT;
        IF affected <> 0 THEN RAISE EXCEPTION 'approval UPDATE unexpectedly affected rows'; END IF;
        DELETE FROM public.crm_deal_approval_steps WHERE id=1;
        GET DIAGNOSTICS affected = ROW_COUNT;
        IF affected <> 0 THEN RAISE EXCEPTION 'approval DELETE unexpectedly affected rows'; END IF;
      END $$;
      SELECT 'approval_writes_denied=pass';
      ROLLBACK;`], name);
    assert.match(writeCheck, /approval_writes_denied=pass/, 'Approval INSERT, UPDATE, and DELETE are denied by RLS.');
    console.log(`PASS PostgreSQL runtime: ${version}; broad CRM reads removed; scoped CRM, Design, and project reads preserved; anon and approval writes denied.`);
  } finally {
    runtime.stop(name);
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
