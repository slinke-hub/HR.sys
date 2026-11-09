/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261109100000_crm_contact_discussion_automation.sql'), 'utf8');
const dealRpc = fs.readFileSync(path.join(root, 'supabase/migrations/20260917090000_shared_business_logic_services.sql'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const dashboard = fs.readFileSync(path.join(root, 'src/crm-dashboard.jsx'), 'utf8');
const stages = fs.readFileSync(path.join(root, 'supabase/migrations/20260905130000_crm_pipeline_stages.sql'), 'utf8');

// Deal assignment is backward-compatible and validated against active profiles.
assert.match(migration, /ADD COLUMN IF NOT EXISTS assignee_ids uuid\[\]/);
assert.match(migration, /UPDATE public\.crm_deals[\s\S]*ARRAY\[assigned_to\]/);
assert.match(migration, /v_assigned_to := v_assignees\[1\]/);
assert.match(migration, /Every deal assignee must be an active employee/);
assert.match(migration, /create_crm_deal_secure\(p_deal jsonb\)/);
assert.match(migration, /update_crm_deal_secure\(p_deal_id uuid, p_patch jsonb\)/);
assert.match(migration, /public\.can_access_crm\(auth\.uid\(\)\)/);
assert.match(migration, /can_view_business_financials\(auth\.uid\(\)\)/);

// Qualification automation uses the deal's exact current assignment set, never the actor.
assert.match(migration, /AFTER UPDATE OF stage ON public\.crm_deals/);
assert.match(migration, /NEW\.stage = 'QUALIFICATION' AND OLD\.stage IS DISTINCT FROM 'QUALIFICATION'/);
assert.match(migration, /'assignee_id', v_deal\.assignee_ids\[1\]/);
assert.match(migration, /'assignee_ids', to_jsonb\(v_deal\.assignee_ids\)/);
assert.match(migration, /'visibility', 'private'/);
assert.match(migration, /'visible_to', to_jsonb\(v_deal\.assignee_ids\)/);
assert.doesNotMatch(migration.slice(migration.indexOf('create_crm_contact_discussion_task'), migration.indexOf('CREATE OR REPLACE FUNCTION public.guard_crm_contact_discussion_task')), /'assignee_id'\s*,\s*auth\.uid\(\)/);
assert.match(migration, /Assign an active deal owner before moving this deal to Qualification/);
assert.match(migration, /Every deal assignee must be active before entering Qualification/);

// The task creation path is guarded, linked, and idempotent for the event.
assert.match(migration, /PRIMARY KEY \(deal_id, event_key\)/);
assert.match(migration, /'qualification-entry-v1'/);
assert.match(migration, /ON CONFLICT \(deal_id, event_key\) DO NOTHING/);
assert.match(migration, /Multiple Contact Discussion tasks are already linked/);
assert.match(migration, /crm_workflow_kind = 'CONTACT_DISCUSSION'/);
assert.match(migration, /create_task_secure\(jsonb_build_object/);
assert.match(migration, /crm_contact_discussion_creation/);
assert.match(migration, /CREATE TRIGGER crm_contact_discussion_task_guard/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.create_crm_contact_discussion_task\(uuid\) FROM PUBLIC, anon, authenticated/);
assert.match(migration, /REVOKE ALL ON TABLE public\.crm_generated_tasks FROM PUBLIC, anon, authenticated/);

// Existing workflow retains the distinct Negotiation stage and approval guard.
assert.match(dealRpc, /'NEGOTIATION', 'WON', 'LOST'/);
assert.match(dealRpc, /v_new_stage IN \('NEGOTIATION', 'WON'\)[\s\S]*workflow_status.*'APPROVED'/);
assert.match(stages, /'NEGOTIATION', 'WON', 'LOST'/);
assert.doesNotMatch(migration, /NEGOTIATION[\s\S]{0,80}PRESENTATION|UPDATE public\.crm_deals[\s\S]*stage\s*=\s*'PITCH'/);
assert.doesNotMatch(migration, /create_crm_design_task_for_deal\s*\(/i);

// Web form supports multiple assignments while retaining legacy assigned_to as primary.
assert.match(html, /id="crmDealAssignee"[^>]*multiple/);
assert.match(app, /Array\.from\(assigneeEl\.selectedOptions/);
assert.match(app, /assignee_ids: assigneeIds/);
assert.match(app, /deal\.assignee_ids/);
assert.match(dashboard, /deal\.assignee_ids/);
assert.match(dashboard, /assignees\.map\(person => <EmployeeName/);

console.log('CRM Contact Discussion assignment, idempotency and workflow regression checks passed.');
