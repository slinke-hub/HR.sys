import type {
  ActivityRecord,
  Client,
  Deal,
  FileAttachment,
  Notification,
  Project,
  Task,
  TaskActivity,
  TaskComment,
  UserProfile,
} from './domain-types';

/**
 * Allow-listed DTO mappers shared by web/mobile adapters. These are defense in
 * depth only; the backend must still redact fields before returning records.
 */
export const toTaskDto = (task: Partial<Task> | null | undefined) => task ? ({
  id: task.id,
  title: task.title,
  description: task.description ?? null,
  status: task.status,
  assignee_id: task.assignee_id ?? null,
  assignee_ids: Array.isArray(task.assignee_ids) ? task.assignee_ids : [],
  created_by: task.created_by ?? null,
  supervisor_id: task.supervisor_id ?? null,
  project_id: task.project_id ?? null,
  crm_deal_id: task.crm_deal_id ?? null,
  due_date: task.due_date ?? null,
}) : null;

export const toTaskCommentDto = (comment: Partial<TaskComment> | null | undefined) => comment ? ({
  id: comment.id,
  task_id: comment.task_id,
  user_id: comment.user_id,
  content: comment.content,
  attachments: Array.isArray(comment.attachments) ? comment.attachments : [],
  edited_at: comment.edited_at ?? null,
  created_at: comment.created_at ?? null,
}) : null;

export const toTaskActivityDto = (activity: Partial<TaskActivity> | null | undefined) => activity ? ({
  id: activity.id,
  task_id: activity.task_id,
  actor_id: activity.actor_id ?? null,
  action: activity.action,
  from_status: activity.from_status ?? null,
  to_status: activity.to_status ?? null,
  metadata: activity.metadata ?? {},
  created_at: activity.created_at,
}) : null;

export const toDealDto = (deal: Partial<Deal> | null | undefined, canViewFinancials = false) => {
  if (!deal) return null;
  const dto: Record<string, unknown> = {
    id: deal.id,
    title: deal.title,
    stage: deal.stage,
    client_id: deal.client_id ?? null,
    assigned_to: deal.assigned_to ?? null,
    workflow_status: deal.workflow_status ?? null,
    approval_type: deal.approval_type ?? null,
  };
  if (canViewFinancials && 'amount' in deal) dto.amount = (deal as Record<string, unknown>).amount ?? null;
  return dto;
};

export const toProjectDto = (project: Partial<Project> | null | undefined, canViewFinancials = false) => {
  if (!project) return null;
  const dto: Record<string, unknown> = {
    id: project.id,
    project_name: project.project_name,
    project_type: project.project_type ?? null,
    description: project.description ?? null,
    deal_id: project.deal_id ?? null,
    client_id: project.client_id ?? null,
    assigned_people: Array.isArray(project.assigned_people) ? project.assigned_people : [],
    lifecycle_status: project.lifecycle_status ?? null,
    priority: project.priority ?? null,
    health_status: project.health_status ?? null,
    progress_percent: project.progress_percent ?? null,
    client_name: project.client_name ?? null,
    created_by: project.created_by ?? null,
    project_manager_id: project.project_manager_id ?? null,
    start_date: project.start_date ?? null,
    end_date: project.end_date ?? null,
    milestones: Array.isArray(project.milestones) ? project.milestones : [],
    risks: Array.isArray(project.risks) ? project.risks : [],
  };
  if (canViewFinancials) {
    const source = project as Record<string, unknown>;
    for (const key of ['budget_amount', 'actual_cost', 'project_amount', 'paid_amount']) {
      if (key in source) dto[key] = source[key] ?? null;
    }
  }
  return dto;
};

export const toClientDto = (client: Partial<Client> | null | undefined) => client ? ({
  id: client.id,
  name: client.name,
  company: client.company ?? null,
  email: client.email ?? null,
  phone: client.phone ?? null,
}) : null;

export const toEmployeeDto = (profile: Partial<UserProfile> | null | undefined) => profile ? ({
  id: profile.id,
  emp_index: profile.emp_index ?? null,
  full_name: profile.full_name ?? null,
  display_name_ar: profile.display_name_ar ?? null,
  role: profile.role ?? null,
  job_title: profile.job_title ?? null,
  department_id: profile.department_id ?? null,
  is_active: profile.is_active ?? null,
}) : null;

export const toActivityDto = (activity: Partial<ActivityRecord> | null | undefined) => activity ? ({
  id: activity.id,
  actor_id: activity.actor_id ?? null,
  action: activity.action,
  created_at: activity.created_at,
  note: activity.note ?? null,
}) : null;

export const toNotificationDto = (notification: Partial<Notification> | null | undefined) => notification ? ({
  id: notification.id,
  user_id: notification.user_id,
  message: notification.message,
  event_type: notification.event_type ?? null,
  actor_id: notification.actor_id ?? null,
  action_url: notification.action_url ?? null,
  metadata: notification.metadata ?? {},
}) : null;

export const toFileDto = (file: Partial<FileAttachment> | null | undefined) => file ? ({
  id: file.id,
  owner_type: file.owner_type ?? null,
  owner_id: file.owner_id ?? null,
  file_name: file.file_name,
  file_type: file.file_type ?? null,
  file_size: file.file_size ?? null,
  description: file.description ?? null,
  storage_reference: file.storage_reference ?? null,
  download_url: file.download_url ?? null,
  is_archived: file.is_archived === true,
  visible_to_project_assignee: file.visible_to_project_assignee === true,
  created_at: file.created_at ?? null,
}) : null;
