-- ========================================================
-- DANGER: DATA WIPE SCRIPT
-- ========================================================
-- This script will permanently delete all records from the specified tables.
-- Execution of this script is irreversible.

TRUNCATE TABLE 
    requests,
    tasks, 
    task_comments, 
    projects, 
    attendance, 
    time_punches, 
    community_chat, 
    employee_documents,
    document_requests,
    contracts 
CASCADE;

-- If you want to delete all employees (User Profiles) as well, uncomment the following line:
-- TRUNCATE TABLE profiles CASCADE;
