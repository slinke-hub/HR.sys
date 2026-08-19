-- ========================================================
-- CLEAR TRANSACTIONAL DATA (KEEPING PROFILES & AUTH)
-- ========================================================

DO $$
BEGIN
    -- Delete all task-related data
    DELETE FROM public.task_comments;
    DELETE FROM public.tasks;
    
    -- Delete all leave-related data
    DELETE FROM public.leave_requests;
    
    -- Delete all attendance data
    DELETE FROM public.time_punches;
    DELETE FROM public.attendance;
    
    -- Delete payroll & expenses
    DELETE FROM public.payroll;
    DELETE FROM public.expenses;
    
    -- Delete performance goals
    DELETE FROM public.performance_goals;
    
    -- Delete document data
    DELETE FROM public.document_requests;
    DELETE FROM public.employee_documents;
    DELETE FROM public.document_expiry_notifications;
    
    -- Delete announcements & communications
    DELETE FROM public.announcements;
    DELETE FROM public.notifications;
    DELETE FROM public.community_chat;
    DELETE FROM public.messages;
    
    -- Delete crm and contracts
    DELETE FROM public.crm_orders;
    DELETE FROM public.crm_deals;
    DELETE FROM public.crm_clients;
    DELETE FROM public.contracts;
    
    -- Note: Profiles, Departments, Projects, Settings, Webhooks are preserved.
END;
$$ LANGUAGE plpgsql;
