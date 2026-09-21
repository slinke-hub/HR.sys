/**
 * Shared domain contracts for the HR.sys web client and future React Native
 * client. These are intentionally transport-agnostic; authorization and
 * invariants remain server-side in Supabase RLS/RPCs.
 */

export type TaskStatus =
  | 'todo'
  | 'in_progress'
  | 'review'
  | 'completed'
  | 'Pending Approval'
  | 'Approved'
  | 'Rejected'
  | 'late';

export type DealStage =
  | 'LEAD'
  | 'QUALIFICATION'
  | 'PITCH'
  | 'PROPOSAL'
  | 'NEGOTIATION'
  | 'WON'
  | 'LOST';

export type ProjectStatus = 'PLANNING' | 'ACTIVE' | 'ON_HOLD' | 'COMPLETED' | 'CANCELLED';
export type Priority = 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';

export interface UserProfile {
  id: string;
  emp_index?: number | null;
  full_name?: string | null;
  display_name_ar?: string | null;
  role?: string | null;
  job_title?: string | null;
  department_id?: string | null;
  is_active?: boolean | null;
}

export interface Task {
  id: string;
  title: string;
  description?: string | null;
  status: TaskStatus | string;
  assignee_id?: string | null;
  assignee_ids?: string[];
  created_by?: string | null;
  supervisor_id?: string | null;
  project_id?: string | null;
  crm_deal_id?: string | null;
  due_date?: string | null;
}

export interface Deal {
  id: string;
  title: string;
  stage: DealStage | string;
  client_id?: string | null;
  assigned_to?: string | null;
  workflow_status?: string | null;
  approval_type?: string | null;
}

export interface Project {
  id: string;
  project_name: string;
  project_type?: string | null;
  description?: string | null;
  deal_id?: string | null;
  client_id?: string | null;
  assigned_people?: string[];
  lifecycle_status?: ProjectStatus | string;
  priority?: Priority | string;
  health_status?: string | null;
  progress_percent?: number | null;
  client_name?: string | null;
  milestones?: Array<Record<string, unknown>>;
  risks?: Array<Record<string, unknown>>;
  budget_amount?: number | null;
  actual_cost?: number | null;
  project_amount?: number | null;
  paid_amount?: number | null;
  created_by?: string | null;
  project_manager_id?: string | null;
  start_date?: string | null;
  end_date?: string | null;
}

export interface Client {
  id: string;
  name: string;
  company?: string | null;
  email?: string | null;
  phone?: string | null;
}

export interface TaskComment {
  id: string;
  task_id: string;
  user_id: string;
  content: string;
  attachments?: Array<Record<string, unknown>>;
  edited_at?: string | null;
  created_at?: string;
}

export interface TaskActivity {
  id: string;
  task_id: string;
  actor_id?: string | null;
  action: string;
  from_status?: string | null;
  to_status?: string | null;
  metadata?: Record<string, unknown>;
  created_at: string;
}

export interface ActivityRecord {
  id: string;
  actor_id?: string | null;
  action: string;
  created_at: string;
  note?: string | null;
}

export interface Notification {
  id: string;
  user_id: string;
  message: string;
  event_type?: string | null;
  actor_id?: string | null;
  action_url?: string | null;
  metadata?: Record<string, unknown> | null;
}

export interface FileAttachment {
  id: string;
  owner_type?: string | null;
  owner_id?: string | null;
  file_name: string;
  file_type?: string | null;
  file_size?: number | null;
  description?: string | null;
  storage_reference?: string | null;
  download_url?: string | null;
  is_archived?: boolean;
  visible_to_project_assignee?: boolean;
  created_at?: string | null;
}

export interface ServiceResult<T = unknown> {
  success: boolean;
  data?: T;
  error?: unknown;
}
