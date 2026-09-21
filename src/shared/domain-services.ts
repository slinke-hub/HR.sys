import type {
  Client,
  Deal,
  Project,
  ServiceResult,
  Task,
} from './domain-types';

/**
 * Minimal adapter expected by the shared domain services. The web adapter is
 * backed by db.js; a native adapter can use the same methods over a versioned
 * Edge Function/API without copying business rules into the mobile app.
 */
export interface HrDomainAdapter {
  fetchTasks?: (...args: unknown[]) => Promise<Task[]>;
  fetchTaskDetails?: (id: string) => Promise<Task | null>;
  createTask?: (...args: unknown[]) => Promise<ServiceResult<Task>>;
  updateTask?: (id: string, updates: Record<string, unknown>) => Promise<ServiceResult<Task>>;
  assignTask?: (id: string, assigneeIds: string[]) => Promise<ServiceResult>;
  updateTaskStatus?: (id: string, status: string) => Promise<ServiceResult>;
  completeTask?: (id: string) => Promise<ServiceResult>;
  reopenTask?: (id: string, status?: string) => Promise<ServiceResult>;
  deleteTask?: (id: string) => Promise<ServiceResult>;
  fetchTaskComments?: (id: string) => Promise<unknown[]>;
  fetchTaskAttachments?: (id: string) => Promise<unknown[]>;
  addTaskComment?: (...args: unknown[]) => Promise<ServiceResult>;
  uploadTaskAttachment?: (...args: unknown[]) => Promise<ServiceResult>;
  archiveTaskAttachments?: (id: string, keepIds?: string[]) => Promise<ServiceResult>;
  updateTaskComment?: (...args: unknown[]) => Promise<ServiceResult>;
  deleteTaskComment?: (id: string) => Promise<ServiceResult>;
  removeTaskAttachment?: (id: string) => Promise<ServiceResult>;
  fetchTaskActivity?: (id: string) => Promise<unknown[]>;
  createDeal?: (payload: Record<string, unknown>) => Promise<ServiceResult<Deal>>;
  fetchDeals?: () => Promise<Deal[]>;
  fetchDealWorkflow?: (id: string) => Promise<Record<string, unknown>>;
  fetchDealActivity?: (id: string) => Promise<unknown[]>;
  uploadDealAttachment?: (...args: unknown[]) => Promise<ServiceResult>;
  archiveDealAttachments?: (...args: unknown[]) => Promise<ServiceResult>;
  updateDeal?: (id: string, payload: Record<string, unknown>) => Promise<ServiceResult<Deal>>;
  updateDealStage?: (id: string, stage: string) => Promise<ServiceResult>;
  markDealLost?: (id: string, reason: string) => Promise<ServiceResult>;
  finalizeCrmDealApproval?: (id: string) => Promise<ServiceResult>;
  startCrmPresentationApproval?: (id: string, requestType: string) => Promise<ServiceResult>;
  startDealApproval?: (id: string, approvers: Record<string, string>) => Promise<ServiceResult>;
  decideDealApproval?: (id: string, decision: string, note?: string) => Promise<ServiceResult>;
  decideCrmDesignTaskApproval?: (id: string, decision: string, note?: string) => Promise<ServiceResult>;
  createProjectFromWonDealV2?: (payload: Record<string, unknown>, dealId: string) => Promise<ServiceResult<Project>>;
  fetchProjects?: () => Promise<Project[]>;
  fetchProjectDetails?: (id: string) => Promise<ServiceResult<Record<string, unknown>>>;
  createProject?: (payload: Record<string, unknown>) => Promise<ServiceResult<Project>>;
  updateProject?: (id: string, payload: Record<string, unknown>) => Promise<ServiceResult<Project>>;
  changeProjectStatus?: (id: string, status: string) => Promise<ServiceResult>;
  assignProjectTeam?: (id: string, managerId: string | null, assigneeIds: string[]) => Promise<ServiceResult>;
  deleteProject?: (id: string) => Promise<ServiceResult>;
  fetchProjectTodos?: (id: string) => Promise<unknown[]>;
  addProjectTodo?: (...args: unknown[]) => Promise<ServiceResult>;
  setProjectTodoCompleted?: (id: string, completed: boolean) => Promise<ServiceResult>;
  createProjectUpdate?: (...args: unknown[]) => Promise<ServiceResult>;
  createProjectUpdateSecure?: (...args: unknown[]) => Promise<ServiceResult>;
  fetchProjectUpdates?: (id: string) => Promise<unknown[]>;
  fetchProjectAttachments?: (id: string) => Promise<unknown[]>;
  fetchClients?: () => Promise<Client[]>;
  createClient?: (payload: Record<string, unknown>) => Promise<ServiceResult<Client>>;
  updateClient?: (id: string, payload: Record<string, unknown>) => Promise<ServiceResult<Client>>;
  deleteClient?: (id: string) => Promise<ServiceResult>;
  fetchNotifications?: (userId: string) => Promise<unknown[]>;
  markNotificationRead?: (id: string) => Promise<ServiceResult>;
}

const requireId = (value: unknown, label: string): string => {
  const id = String(value ?? '').trim();
  if (!id) throw new Error(`${label} is required`);
  return id;
};

const requireAdapter = <K extends keyof HrDomainAdapter>(adapter: HrDomainAdapter, key: K): ((...args: any[]) => any) => {
  const operation = adapter[key];
  if (typeof operation !== 'function') throw new Error(`Shared service operation is unavailable: ${String(key)}`);
  return operation as NonNullable<HrDomainAdapter[K]>;
};

/**
 * Build the shared service inventory. These methods perform input shaping only;
 * the adapter/backend remains responsible for authentication, authorization,
 * validation, transactions, and audit logging.
 */
export const createHrDomainServices = (adapter: HrDomainAdapter) => ({
  tasks: {
    list: (...args: unknown[]) => requireAdapter(adapter, 'fetchTasks')(...args),
    details: (id: string) => requireAdapter(adapter, 'fetchTaskDetails')(requireId(id, 'Task')),
    create: (...args: unknown[]) => requireAdapter(adapter, 'createTask')(...args),
    update: (id: string, updates: Record<string, unknown>) => requireAdapter(adapter, 'updateTask')(requireId(id, 'Task'), updates || {}),
    assign: (id: string, assigneeIds: string[]) => requireAdapter(adapter, 'assignTask')(requireId(id, 'Task'), Array.isArray(assigneeIds) ? assigneeIds : []),
    changeStatus: (id: string, status: string) => requireAdapter(adapter, 'updateTaskStatus')(requireId(id, 'Task'), String(status || '').trim()),
    complete: (id: string) => requireAdapter(adapter, 'completeTask')(requireId(id, 'Task')),
    reopen: (id: string, status = 'todo') => requireAdapter(adapter, 'reopenTask')(requireId(id, 'Task'), status),
    delete: (id: string) => requireAdapter(adapter, 'deleteTask')(requireId(id, 'Task')),
    addComment: (...args: unknown[]) => requireAdapter(adapter, 'addTaskComment')(...args),
    updateComment: (...args: unknown[]) => requireAdapter(adapter, 'updateTaskComment')(...args),
    deleteComment: (id: string) => requireAdapter(adapter, 'deleteTaskComment')(requireId(id, 'Comment')),
    attachFile: (...args: unknown[]) => requireAdapter(adapter, 'uploadTaskAttachment')(...args),
    archiveAttachments: (id: string, keepIds: string[] = []) => requireAdapter(adapter, 'archiveTaskAttachments')(requireId(id, 'Task'), keepIds),
    removeAttachment: (id: string) => requireAdapter(adapter, 'removeTaskAttachment')(requireId(id, 'Attachment')),
    comments: (id: string) => requireAdapter(adapter, 'fetchTaskComments')(requireId(id, 'Task')),
    attachments: (id: string) => requireAdapter(adapter, 'fetchTaskAttachments')(requireId(id, 'Task')),
    activity: (id: string) => requireAdapter(adapter, 'fetchTaskActivity')(requireId(id, 'Task')),
  },
  deals: {
    list: (...args: unknown[]) => requireAdapter(adapter, 'fetchDeals')(...args),
    workflow: (id: string) => requireAdapter(adapter, 'fetchDealWorkflow')(requireId(id, 'Deal')),
    create: (payload: Record<string, unknown>) => requireAdapter(adapter, 'createDeal')(payload || {}),
    update: (id: string, payload: Record<string, unknown>) => requireAdapter(adapter, 'updateDeal')(requireId(id, 'Deal'), payload || {}),
    changeStage: (id: string, stage: string) => requireAdapter(adapter, 'updateDealStage')(requireId(id, 'Deal'), String(stage || '').trim()),
    markLost: (id: string, reason: string) => requireAdapter(adapter, 'markDealLost')(requireId(id, 'Deal'), String(reason || '').trim()),
    finalizeApproval: (id: string) => requireAdapter(adapter, 'finalizeCrmDealApproval')(requireId(id, 'Deal')),
    startPresentationApproval: (id: string, requestType: string) => requireAdapter(adapter, 'startCrmPresentationApproval')(requireId(id, 'Deal'), requestType),
    startApproval: (id: string, approvers: Record<string, string>) => requireAdapter(adapter, 'startDealApproval')(requireId(id, 'Deal'), approvers || {}),
    decideApproval: (id: string, decision: string, note?: string) => requireAdapter(adapter, 'decideDealApproval')(requireId(id, 'Deal'), decision, note),
    decideDesignApproval: (id: string, decision: string, note?: string) => requireAdapter(adapter, 'decideCrmDesignTaskApproval')(requireId(id, 'Deal'), decision, note),
    activity: (id: string) => requireAdapter(adapter, 'fetchDealActivity')(requireId(id, 'Deal')),
    attachFile: (...args: unknown[]) => requireAdapter(adapter, 'uploadDealAttachment')(...args),
    archiveAttachments: (...args: unknown[]) => requireAdapter(adapter, 'archiveDealAttachments')(...args),
    convertToProject: (dealId: string, payload: Record<string, unknown>) => requireAdapter(adapter, 'createProjectFromWonDealV2')(payload || {}, requireId(dealId, 'Deal')),
  },
  projects: {
    list: (...args: unknown[]) => requireAdapter(adapter, 'fetchProjects')(...args),
    details: (id: string) => requireAdapter(adapter, 'fetchProjectDetails')(requireId(id, 'Project')),
    create: (payload: Record<string, unknown>) => requireAdapter(adapter, 'createProject')(payload || {}),
    createFromWonDeal: (dealId: string, payload: Record<string, unknown>) => requireAdapter(adapter, 'createProjectFromWonDealV2')(payload || {}, requireId(dealId, 'Deal')),
    update: (id: string, payload: Record<string, unknown>) => requireAdapter(adapter, 'updateProject')(requireId(id, 'Project'), payload || {}),
    changeStatus: (id: string, status: string) => requireAdapter(adapter, 'changeProjectStatus')(requireId(id, 'Project'), String(status || '').trim()),
    assignTeam: (id: string, managerId: string | null, assigneeIds: string[]) => requireAdapter(adapter, 'assignProjectTeam')(requireId(id, 'Project'), managerId || null, Array.isArray(assigneeIds) ? assigneeIds : []),
    delete: (id: string) => requireAdapter(adapter, 'deleteProject')(requireId(id, 'Project')),
    todos: (id: string) => requireAdapter(adapter, 'fetchProjectTodos')(requireId(id, 'Project')),
    addTodo: (...args: unknown[]) => requireAdapter(adapter, 'addProjectTodo')(...args),
    setTodoCompleted: (id: string, completed: boolean) => requireAdapter(adapter, 'setProjectTodoCompleted')(requireId(id, 'Todo'), completed),
    addUpdate: (...args: unknown[]) => (adapter.createProjectUpdateSecure
      ? adapter.createProjectUpdateSecure(...args)
      : requireAdapter(adapter, 'createProjectUpdate')(...args)),
    updates: (id: string) => requireAdapter(adapter, 'fetchProjectUpdates')(requireId(id, 'Project')),
    activity: (id: string) => requireAdapter(adapter, 'fetchProjectUpdates')(requireId(id, 'Project')),
    attachments: (id: string) => requireAdapter(adapter, 'fetchProjectAttachments')(requireId(id, 'Project')),
  },
  clients: {
    list: () => requireAdapter(adapter, 'fetchClients')(),
    create: (payload: Record<string, unknown>) => requireAdapter(adapter, 'createClient')(payload || {}),
    update: (id: string, payload: Record<string, unknown>) => requireAdapter(adapter, 'updateClient')(requireId(id, 'Client'), payload || {}),
    delete: (id: string) => requireAdapter(adapter, 'deleteClient')(requireId(id, 'Client')),
  },
  notifications: {
    list: (userId: string) => requireAdapter(adapter, 'fetchNotifications')(requireId(userId, 'User')),
    markRead: (id: string) => requireAdapter(adapter, 'markNotificationRead')(requireId(id, 'Notification')),
  },
});
