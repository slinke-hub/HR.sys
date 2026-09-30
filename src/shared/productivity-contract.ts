/** Shared Task productivity contract for Web and future native adapters. */
export type TaskWorkState = 'ACTIVE' | 'WAITING' | 'BLOCKED';

export type MyDaySection =
  | 'DO_NOW'
  | 'DUE_TODAY'
  | 'WAITING'
  | 'BLOCKED'
  | 'OVERDUE'
  | 'NEXT'
  | 'COMPLETED_TODAY';

export type WaitingCategory =
  | 'CLIENT'
  | 'SUPPLIER'
  | 'MANAGEMENT'
  | 'APPROVAL'
  | 'DESIGN'
  | 'PRODUCTION'
  | 'ANOTHER_EMPLOYEE'
  | 'MISSING_INFORMATION'
  | 'OTHER';

export type BlockerCategory =
  | 'CLIENT'
  | 'SUPPLIER'
  | 'ANOTHER_EMPLOYEE'
  | 'MANAGEMENT'
  | 'APPROVAL'
  | 'MISSING_INFORMATION'
  | 'TECHNICAL_PROBLEM'
  | 'OTHER';

export interface MyDayTask {
  id: string;
  title: string;
  description?: string | null;
  status: string;
  work_state: TaskWorkState;
  my_day_section: MyDaySection;
  my_day_reason: string;
  assignee_id?: string | null;
  due_date?: string | null;
  priority?: string | null;
  project_id?: string | null;
  crm_deal_id?: string | null;
  waiting_category?: WaitingCategory | null;
  blocked_category?: BlockerCategory | null;
  waiting_note?: string | null;
  blocked_note?: string | null;
  dependency_blocked?: boolean;
  blocking_task_title?: string | null;
}

export interface TaskDependency {
  dependency_id: string;
  predecessor_task_id: string;
  successor_task_id: string;
  relationship: 'depends_on' | 'unlocks';
  is_satisfied: boolean;
  is_blocking: boolean;
  created_at?: string | null;
  predecessor?: Record<string, unknown> | null;
  successor?: Record<string, unknown> | null;
}

export interface TaskDependencyBlocker {
  task_id: string;
  title: string;
  status: string;
  assignee_id?: string | null;
  blocking_task_id: string;
  blocking_task_title: string;
  blocking_employee_id?: string | null;
  waiting_since?: string | null;
}

export interface TaskHandoffResult {
  task_id: string;
  status: string;
  handoff: boolean;
  successor_task_ids: string[];
  free_form_handoff_supported: boolean;
  activated_successors?: string[];
}

export interface TaskProductivityAdapter {
  fetchMyDay: () => Promise<MyDayTask[]>;
  fetchMyCompletedToday: () => Promise<MyDayTask[]>;
  startTask: (taskId: string) => Promise<unknown>;
  markTaskWaiting: (taskId: string, category: WaitingCategory, relatedUserId?: string | null, note?: string | null) => Promise<unknown>;
  markTaskBlocked: (taskId: string, category: BlockerCategory, relatedUserId?: string | null, note?: string | null) => Promise<unknown>;
  resumeTask: (taskId: string) => Promise<unknown>;
  completeTaskProductivity: (taskId: string) => Promise<unknown>;
  fetchTaskWorkStates: () => Promise<unknown[]>;
  fetchTaskWorkHistory: (taskId: string) => Promise<unknown[]>;
  fetchTaskDependencies: (taskId: string) => Promise<TaskDependency[]>;
  createTaskDependency: (predecessorTaskId: string, successorTaskId: string) => Promise<TaskDependency>;
  removeTaskDependency: (dependencyId: string) => Promise<boolean>;
  fetchTaskDependencyHistory: (taskId: string) => Promise<unknown[]>;
  fetchTaskDependencyBlockers: () => Promise<TaskDependencyBlocker[]>;
  completeAndHandOffTask: (taskId: string) => Promise<TaskHandoffResult>;
}
