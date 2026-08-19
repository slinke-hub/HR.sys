# Updated Implementation Plan: Sub-Tasks & Data Cleanup

This plan addresses your additional requests to:
1. Modify the task manager to allow sub-task creation.
2. Delete all transactional data while keeping the created users.
3. Automatically translate dynamic content when the language is switched without requiring a page reload.

## Open Questions & Review
> [!CAUTION]
> **Data Deletion**: I will create and run a SQL script that uses `DELETE FROM` to completely wipe the following tables: `tasks`, `task_comments`, `requests`, `leave_requests`, `payroll`, `expenses`, `attendance`, `notifications`, `contracts`, `announcements`, etc. 
> I will **KEEP** the data in: `profiles`, `departments`, `projects`, and `auth.users`. **Are you absolutely sure you want to proceed with this deletion?**

> [!NOTE]
> **Sub-Tasks Display**: I plan to show sub-tasks inside the Task Details Modal of their parent task. You will be able to click "Add Sub-Task" from inside a task to create one. Is this workflow acceptable?

## Proposed Changes

### `clear_transactional_data.sql` [NEW]
- Create a SQL script that deletes all rows from transactional tables (tasks, payroll, attendance, etc.) but leaves structural tables (profiles, departments, etc.) intact.

### `sub_tasks_migration.sql` [NEW]
- Run a migration to add `parent_task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE` to the `public.tasks` table.

### `js/db.js`
- **[MODIFY] `createTask`**: Add the `parent_task_id` parameter to the RPC/insert call.
- **[MODIFY] `fetchTasks`**: Fetch tasks including their parent_task_id.

### `index.html`
- **[MODIFY] `createTaskModal`**: Add a hidden `<input type="hidden" id="taskParentId">` to link new tasks to their parent if applicable.
- **[MODIFY] Task Details Modal**: Add a section for "Sub-Tasks" and a button to "Create Sub-Task".

### `js/app.js`
- **[MODIFY] `openTaskDetailsModal`**: 
  - Render existing sub-tasks under the parent task.
  - Set up the "Create Sub-Task" button to populate `taskParentId` and open the task creation modal.
- **[MODIFY] `handleCreateTask`**: Pass `taskParentId.value` to the database call.
- **[MODIFY] `renderView('tasks')`**: Optionally filter out sub-tasks from the main list so they only appear inside their parent task's details.
- **[MODIFY] `toggleLanguage`**: Add logic to re-fetch or re-render data arrays (like tasks and notifications) immediately, so the localized strings (like `title_i18n`) change instantly without page refresh.
