import type { ProjectOperationalHealth, ServiceResult } from './domain-types';

export type ProjectHealthState = ProjectOperationalHealth;
export type ProjectEventStatus = 'NO_EVENT' | 'PAST' | 'TODAY' | 'TOMORROW' | 'UPCOMING';
export type ProjectAttentionReasonCode =
  | 'BLOCKED_TASKS'
  | 'WAITING_TASKS'
  | 'DEPENDENCY_RISK'
  | 'OVERDUE_TASKS'
  | 'OVERDUE_TODOS'
  | 'EVENT_TODAY'
  | 'EVENT_TOMORROW'
  | 'EVENT_SOON';

export type ProjectCompletionBlockerCode =
  | 'NO_TASKS'
  | 'INCOMPLETE_TASKS'
  | 'BLOCKED_TASKS'
  | 'WAITING_TASKS'
  | 'UNRESOLVED_DEPENDENCY_CHAIN';

export interface ProjectCompletionReadiness {
  project_id: string;
  ready: boolean;
  zero_task_project_closure_ready: false;
  counts: {
    tasks: number;
    completed_tasks: number;
    incomplete_tasks: number;
    blocked_tasks: number;
    waiting_tasks: number;
    dependency_blocked_tasks: number;
  };
  reason_codes: Array<{ code: ProjectCompletionBlockerCode; count: number }>;
  project_todos_enforced: false;
  project_todos_note: string;
}

/** Secure per-Project aggregate returned by the Phase 1 operational summary RPC. */
export interface ProjectOperationalSummary {
  project_id: string;
  project_name: string;
  progress_percent: number;
  health: ProjectHealthState;
  health_status: ProjectHealthState;
  event_date: string | null;
  event_countdown_days: number | null;
  event_status: ProjectEventStatus;
  counts: ProjectCommandCenterCard['counts'];
  reason_codes: Array<{ code: ProjectAttentionReasonCode; count: number }>;
  tasks: Array<Record<string, unknown>>;
  todos: Array<Record<string, unknown>>;
  financials_included: false;
}

export interface ProjectCommandCenterCard {
  project_id: string;
  project_name: string;
  project_type?: string | null;
  project_status?: string | null;
  lifecycle_status?: string | null;
  priority?: string | null;
  event_date?: string | null;
  start_date?: string | null;
  end_date?: string | null;
  event_countdown_days?: number | null;
  event_status: ProjectEventStatus;
  client_name?: string | null;
  progress_percent: number;
  health: ProjectHealthState;
  responsible_employee?: { id: string; full_name?: string | null; display_name?: string | null; display_name_ar?: string | null; employee_id?: string | null } | null;
  counts: {
    tasks: number;
    completed_tasks: number;
    actionable_tasks: number;
    overdue_tasks: number;
    due_today_tasks: number;
    waiting_tasks: number;
    blocked_tasks: number;
    dependency_blocked_tasks: number;
    open_todos: number;
    overdue_todos: number;
  };
  reason_codes: Array<{ code: ProjectAttentionReasonCode; count: number }>;
}

export interface ProjectCommandCenterAdapter {
  list: (options?: { limit?: number; onlyAttention?: boolean; upcomingDays?: number }) => Promise<ServiceResult<ProjectCommandCenterCard[]>>;
  attention: (limit?: number) => Promise<ServiceResult<ProjectCommandCenterCard[]>>;
  upcoming: (days?: number, limit?: number) => Promise<ServiceResult<ProjectCommandCenterCard[]>>;
  health: (projectId: string) => Promise<ServiceResult<ProjectCommandCenterCard>>;
  operationalSummary: (projectId: string) => Promise<ServiceResult<ProjectOperationalSummary>>;
}
