-- Production-only prerequisite for CRM Release 1A.
-- Extends the existing nullable workflow-kind allowlist without rewriting
-- existing task values or changing the four reviewed release migrations.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
DECLARE
  current_definition text;
BEGIN
  IF current_user <> 'postgres' OR current_database() <> 'postgres'
     OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999 THEN
    RAISE EXCEPTION 'CRM workflow-kind compatibility requires PostgreSQL 17.x, database postgres, role postgres';
  END IF;
  IF to_regclass('public.tasks') IS NULL OR NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'public.tasks'::regclass
      AND attname = 'crm_workflow_kind'
      AND atttypid = 'text'::regtype
      AND NOT attnotnull
      AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'Production tasks.crm_workflow_kind column differs from the reviewed baseline';
  END IF;

  SELECT pg_get_constraintdef(constraint_row.oid)
    INTO current_definition
    FROM pg_constraint constraint_row
   WHERE constraint_row.conrelid = 'public.tasks'::regclass
     AND constraint_row.conname = 'tasks_crm_workflow_kind_check'
     AND constraint_row.contype = 'c';

  IF current_definition IS DISTINCT FROM
     'CHECK (((crm_workflow_kind IS NULL) OR (crm_workflow_kind = ''QUOTE_PROPOSAL_DESIGN''::text)))' THEN
    RAISE EXCEPTION 'Existing task workflow-kind constraint is absent or differs from the reviewed Production baseline';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.tasks
    WHERE crm_workflow_kind IS NOT NULL
      AND crm_workflow_kind NOT IN ('QUOTE_PROPOSAL_DESIGN', 'CONTACT_DISCUSSION')
  ) THEN
    RAISE EXCEPTION 'Existing task workflow-kind values require review before allowlist expansion';
  END IF;
END;
$preflight$;

ALTER TABLE public.tasks
  DROP CONSTRAINT tasks_crm_workflow_kind_check;

ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_crm_workflow_kind_check
  CHECK (
    crm_workflow_kind IS NULL
    OR crm_workflow_kind IN ('QUOTE_PROPOSAL_DESIGN', 'CONTACT_DISCUSSION')
  ) NOT VALID;

ALTER TABLE public.tasks
  VALIDATE CONSTRAINT tasks_crm_workflow_kind_check;

DO $postcheck$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint constraint_row
    WHERE constraint_row.conrelid = 'public.tasks'::regclass
      AND constraint_row.conname = 'tasks_crm_workflow_kind_check'
      AND constraint_row.contype = 'c'
      AND constraint_row.convalidated
      AND pg_get_constraintdef(constraint_row.oid) ILIKE '%QUOTE_PROPOSAL_DESIGN%'
      AND pg_get_constraintdef(constraint_row.oid) ILIKE '%CONTACT_DISCUSSION%'
      AND pg_get_constraintdef(constraint_row.oid) ILIKE '%IS NULL%'
  ) THEN
    RAISE EXCEPTION 'Task workflow-kind allowlist postcondition failed';
  END IF;
END;
$postcheck$;

COMMIT;
