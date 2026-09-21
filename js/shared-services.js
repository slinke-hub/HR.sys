/* Shared HR domain service bridge for the current web client. */
(function () {
    'use strict';
    if (typeof db === 'undefined') return;

    const requireId = (value, label) => {
        const id = String(value ?? '').trim();
        if (!id) throw new Error(`${label} is required`);
        return id;
    };

    window.hrDomainServices = Object.freeze({
        tasks: Object.freeze({
            list: (...args) => db.fetchTasksWithProfiles ? db.fetchTasksWithProfiles(...args) : db.fetchTasks(...args),
            details: id => db.fetchTaskDetails
                ? db.fetchTaskDetails(requireId(id, 'Task'))
                : (async () => {
                    const tasks = await (db.fetchTasksWithProfiles ? db.fetchTasksWithProfiles() : db.fetchTasks());
                    return (tasks || []).find(task => String(task.id) === requireId(id, 'Task')) || null;
                })(),
            create: (...args) => db.createTask(...args),
            update: (id, updates) => db.updateTask(requireId(id, 'Task'), updates || {}),
            assign: (id, assigneeIds) => db.assignTask(requireId(id, 'Task'), assigneeIds),
            changeStatus: (id, status) => db.updateTaskStatus(requireId(id, 'Task'), String(status || '').trim()),
            complete: id => db.completeTask(requireId(id, 'Task')),
            reopen: id => db.reopenTask(requireId(id, 'Task')),
            delete: id => db.deleteTask(requireId(id, 'Task')),
            addComment: (...args) => db.addTaskComment(...args),
            updateComment: (...args) => db.updateTaskComment(...args),
            deleteComment: id => db.deleteTaskComment(requireId(id, 'Comment')),
            attachFile: (...args) => db.uploadTaskAttachment(...args),
            archiveAttachments: (id, keepIds) => db.archiveTaskAttachments(requireId(id, 'Task'), keepIds || []),
            removeAttachment: id => db.removeTaskAttachment(requireId(id, 'Attachment')),
            comments: id => db.fetchTaskComments(requireId(id, 'Task')),
            attachments: id => db.fetchTaskAttachments(requireId(id, 'Task')),
            activity: id => db.fetchTaskActivity(requireId(id, 'Task')),
        }),
        deals: Object.freeze({
            list: (...args) => db.fetchDeals(...args),
            workflow: id => db.fetchDealWorkflow(requireId(id, 'Deal')),
            create: payload => db.createDeal(payload || {}),
            update: (id, payload) => db.updateDeal(requireId(id, 'Deal'), payload || {}),
            changeStage: (id, stage) => db.updateDealStage(requireId(id, 'Deal'), String(stage || '').trim()),
            markLost: (id, reason) => db.markDealLost(requireId(id, 'Deal'), String(reason || '').trim()),
            finalizeApproval: id => db.finalizeCrmDealApproval(requireId(id, 'Deal')),
            startPresentationApproval: (id, requestType) => db.startCrmPresentationApproval(requireId(id, 'Deal'), requestType),
            startApproval: (id, approvers) => db.startDealApproval(requireId(id, 'Deal'), approvers || {}),
            decideApproval: (id, decision, note) => db.decideDealApproval(requireId(id, 'Deal'), decision, note),
            decideDesignApproval: (id, decision, note) => db.decideCrmDesignTaskApproval(requireId(id, 'Deal'), decision, note),
            activity: async id => (await db.fetchDealWorkflow(requireId(id, 'Deal')))?.activity || [],
            attachFile: (...args) => db.uploadDealAttachment(...args),
            archiveAttachments: (...args) => db.archiveDealAttachments(...args),
            convertToProject: (dealId, payload) => db.createProjectFromWonDealV2(payload || {}, requireId(dealId, 'Deal')),
        }),
        projects: Object.freeze({
            list: (...args) => db.fetchProjects(...args),
            details: id => db.fetchProjectDetails(requireId(id, 'Project')),
            createFromWonDeal: (dealId, payload) => db.createProjectFromWonDealV2(payload || {}, requireId(dealId, 'Deal')),
            create: payload => db.createProject(payload || {}),
            update: (id, payload) => db.updateProject(requireId(id, 'Project'), payload || {}),
            changeStatus: (id, status) => db.changeProjectStatus(requireId(id, 'Project'), status),
            assignTeam: (id, managerId, assigneeIds) => db.assignProjectTeam(requireId(id, 'Project'), managerId, assigneeIds),
            delete: id => db.deleteProject(requireId(id, 'Project')),
            todos: id => db.fetchProjectTodos(requireId(id, 'Project')),
            addTodo: (...args) => db.addProjectTodo(...args),
            completeTodo: (id, completed) => db.setProjectTodoCompleted(requireId(id, 'Todo'), completed),
            addUpdate: (...args) => (db.createProjectUpdateSecure ? db.createProjectUpdateSecure(...args) : db.createProjectUpdate(...args)),
            attachments: id => db.fetchProjectSharedAttachments(requireId(id, 'Project')),
            updates: id => db.fetchProjectUpdates(requireId(id, 'Project')),
            activity: id => db.fetchProjectUpdates(requireId(id, 'Project')),
        }),
        clients: Object.freeze({
            list: () => db.fetchClients(),
            create: payload => db.createClient(payload || {}),
            update: (id, payload) => db.updateClient(requireId(id, 'Client'), payload || {}),
            delete: id => db.deleteClient(requireId(id, 'Client')),
        }),
        notifications: Object.freeze({
            list: userId => db.fetchNotifications(requireId(userId, 'User')),
            markRead: id => db.markNotificationRead(requireId(id, 'Notification')),
        }),
    });
}());
