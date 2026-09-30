import type { ServiceResult } from './domain-types';

export type ProjectHealthState = 'ON_TRACK' | 'NEEDS_ATTENTION' | 'AT_RISK' | 'CRITICAL';
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
  progress_percent?: number | null;
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
  operationalSummary: (projectId: string) => Promise<ServiceResult<Record<string, unknown>>>;
}
