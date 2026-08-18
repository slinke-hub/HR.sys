// IMPORTANT: Replace these with your actual Supabase Project URL and Anon Key
const SUPABASE_URL = 'https://bbbetcdioiaozdjkvwxu.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJiYmV0Y2Rpb2lhb3pkamt2d3h1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMTM0NjQsImV4cCI6MjEwMTU4OTQ2NH0.GhV7HsGnAXA8Zb_IV3hxhwI9qmbM3qhcuWRMSXKUNcw';

// Initialize the Supabase client
// This uses the global supabase object loaded via the CDN in index.html
let supabaseClient = null;

if (SUPABASE_URL !== 'YOUR_SUPABASE_URL' && SUPABASE_ANON_KEY !== 'YOUR_SUPABASE_ANON_KEY') {
    supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    window.supabaseClient = supabaseClient;
    console.log("Supabase client initialized successfully.");
} else {
    console.warn("Supabase credentials not configured. Using mocked data/actions.");
}

// Global DB helper functions for the prototype
const db = {

    // User Management API
    async updateUserProfile(userId, updates) {
        if (!supabaseClient) return null;
        try {
            const { data, error } = await supabaseClient
                .from('profiles')
                .update(updates)
                .eq('id', userId)
                .select();
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error updating user profile:", error);
            return null;
        }
    },
    async deleteUser(userId) {
        if (!supabaseClient) return null;
        try {
            const { data, error } = await supabaseClient.rpc('delete_user', { target_user_id: userId });
            if (error) throw error;
            return true;
        } catch (error) {
            console.error("Error deleting user:", error);
            return false;
        }
    },
    async resetUserPassword(userId, newPassword) {
        if (!supabaseClient) return { success: false, error: new Error('Supabase not initialized') };
        try {
            const { data, error } = await supabaseClient.functions.invoke('admin-set-user-password', {
                body: { targetUserId: userId, newPassword }
            });
            if (error) throw error;
            if (!data?.success) throw new Error(data?.error || 'Password reset failed');
            return { success: true };
        } catch (error) {
            console.error("Error resetting password:", error);
            let message = error?.message || 'Password reset failed';
            if (error?.context && typeof error.context.json === 'function') {
                try {
                    const errorBody = await error.context.json();
                    message = errorBody?.error || message;
                } catch (_) {
                    // Keep the original Functions error when no JSON body is available.
                }
            }
            return { success: false, error: new Error(message) };
        }
    },

    // Request API
    async fetchRequests(userId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('requests').select('*, profiles(full_name)').order('created_at', { ascending: false });
            if (userId) {
                query = query.eq('employee_id', userId);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error fetching requests:", error);
            return [];
        }
    },
    async createRequest(employeeId, requestType, leaveType, notes) {
        if (!supabaseClient) return null;
        try {
            const { data, error } = await supabaseClient.from('requests').insert([{
                employee_id: employeeId,
                request_type: requestType,
                leave_type: leaveType
                // notes could be added to schema if needed, skipping for now
            }]).select();
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error creating request:", error);
            return null;
        }
    },

    // Login Lockout API
    async checkLoginLockout(email) {
        if (!supabaseClient) return null;
        try {
            const { data, error } = await supabaseClient.from('login_attempts').select('*').eq('email', email).maybeSingle();
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error checking login lockout:", error);
            return null;
        }
    },
    async recordFailedLogin(email) {
        if (!supabaseClient) return null;
        try {
            await supabaseClient.rpc('record_failed_login', { user_email: email });
        } catch (error) {
            console.error("Error recording failed login:", error);
        }
    },
    async resetLoginLockout(email) {
        if (!supabaseClient) return null;
        try {
            await supabaseClient.rpc('reset_login_lockout', { user_email: email });
        } catch (error) {
            console.error("Error resetting login lockout:", error);
        }
    },


    async fetchTimePunches(userId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('time_punches').select('*').order('punch_time', { ascending: false }).limit(50);
            if (userId) {
                query = query.eq('employee_id', userId);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error fetching time punches:", error.message);
            return [];
        }
    },

    async checkClockInStatus(userId) {
        if (!supabaseClient) return false;
        try {
            const { data, error } = await supabaseClient
                .from('time_punches')
                .select('punch_type')
                .eq('employee_id', userId)
                .order('punch_time', { ascending: false })
                .limit(1)
                .maybeSingle();
            if (error) throw error;
            return data?.punch_type === 'IN';
        } catch(e) {
            return false;
        }
    },

    async fetchAnnouncements() {
        if (!supabaseClient) {
            return null; // Return null to fallback to mocked data in app.js
        }

        try {
            const { data, error } = await supabaseClient
                .from('announcements')
                .select('*')
                .order('created_at', { ascending: false });

            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error fetching announcements:", error.message);
            return null;
        }
    },

    // --- Authentication ---
    async login(email, password) {
        if (!supabaseClient) {
            console.warn("Mock Login Success");
            return { user: { email }, error: null };
        }
        
        try {
            const { data, error } = await supabaseClient.auth.signInWithPassword({
                email: email,
                password: password
            });
            return { user: data?.user, error };
        } catch (error) {
            return { user: null, error };
        }
    },

    async logout() {
        if (supabaseClient) {
            await supabaseClient.auth.signOut();
        }
    },

    async sendPasswordResetEmail(email) {
        if (!supabaseClient) return { error: { message: "Supabase not initialized." } };
        return await supabaseClient.auth.resetPasswordForEmail(email, {
            redirectTo: window.location.origin + window.location.pathname
        });
    },

    async updatePassword(newPassword) {
        if (!supabaseClient) return { error: { message: "Supabase not initialized." } };
        return await supabaseClient.auth.updateUser({
            password: newPassword
        });
    },

    async getUserProfile(userId) {
        if (!supabaseClient) {
            return { role: 'EMPLOYEE', job_title: '', base_salary: 3000, annual_leave_allowance: 30, sick_leave_allowance: 10, manager_id: null };
        }

        for (let attempt = 1; attempt <= 3; attempt++) {
            try {
                const { data, error } = await supabaseClient
                    .from('profiles')
                    .select('id, role, job_title, manager_id, base_salary, annual_leave_allowance, sick_leave_allowance, full_name, iqama_number, phone_number')
                    .eq('id', userId)
                    .single();
                
                if (error) throw error;
                return data;
            } catch (error) {
                if (error.message && error.message.includes("JWT issued at future") && attempt < 3) {
                    console.warn(`JWT time drift, retrying in 1s (attempt ${attempt})...`);
                    await new Promise(r => setTimeout(r, 1000));
                    continue;
                }
                console.error("Error fetching profile:", error.message);
                return { role: 'EMPLOYEE', job_title: '', base_salary: 3000, annual_leave_allowance: 30, sick_leave_allowance: 10, manager_id: null };
            }
        }
    },

    // --- Leave Management ---
    async submitLeaveRequest(userId, requestData) {
        if (!supabaseClient) return true;
        try {
            const { error } = await supabaseClient
                .from('leave_requests')
                .insert([{ ...requestData, employee_id: userId }]);
            if (error) throw error;
            return true;
        } catch (error) {
            console.error("Error submitting leave request:", error.message);
            return false;
        }
    },

    async fetchLeaveRequests(userId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('leave_requests').select('*').order('created_at', { ascending: false });
            if (userId) {
                query = query.eq('employee_id', userId);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error fetching leave requests:", error.message);
            return [];
        }
    },

    async updateLeaveStatus(requestId, status) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('leave_requests')
                .update({ status })
                .eq('id', requestId)
                .select();
            if (error) throw error;
            if (!data || data.length === 0) throw new Error("No rows updated. You might lack permissions (RLS).");
            return { success: true };
        } catch (error) {
            console.error("Error updating leave request:", error.message);
            return { success: false, error };
        }
    },

    async fetchPayroll(userId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('payroll').select('*').order('created_at', { ascending: false });
            if (userId) {
                query = query.eq('employee_id', userId);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error fetching payroll:", error.message);
            return [];
        }
    },

    // --- Admin Hub ---
    async fetchAllEmployees() {
        if (!supabaseClient) return [];
        try {
            // Join auth.users if possible, or just profiles. 
            // Note: Cannot easily fetch auth.users from client safely without Admin API,
            // so we will rely on profiles and fallback mock data for now.
            const { data, error } = await supabaseClient
                .from('profiles')
                .select('*')
                .eq('is_active', true);
            if (error) throw error;
            return data;
        } catch(e) {
            return [];
        }
    },

    async fetchAllPendingLeaves() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('leave_requests')
                .select('*')
                .eq('status', 'PENDING')
                .order('created_at', { ascending: true });
            if (error) throw error;
            return data;
        } catch(e) {
            return [];
        }
    },


    // USER MANAGEMENT (ADMIN)
    // ==========================================
    async fetchUsers() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('profiles')
                .select('id, emp_index, full_name, iqama_number, phone_number, role, job_title, created_at, manager_id, base_salary, department_id')
                .eq('is_active', true)
                .order('emp_index', { ascending: true });
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchUsers Error:", error);
            return [];
        }
    },
    async createUser(email, password, role, jobTitle = '', fullName = '', iqama = '', phone = '') {
        if (!supabaseClient) {
            console.warn("Mock createUser");
            return { data: 'mock-user-id-1234', error: null };
        }
        try {
            const { data, error } = await supabaseClient.rpc('create_user_by_admin', {
                new_email: email,
                new_password: password,
                new_role: role,
                new_job_title: jobTitle,
                new_full_name: fullName,
                new_iqama: iqama,
                new_phone: phone
            });
            if (error) throw error;
            return { data, error: null };
        } catch (error) {
            console.error("createUser Error:", error);
            return { data: null, error };
        }
    },
    async updateUserRole(userId, newRole) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('profiles')
                .update({ role: newRole })
                .eq('id', userId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateUserRole Error:", error);
            return { success: false, error };
        }
    },
    async assignManager(userId, managerId) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('profiles')
                .update({ manager_id: managerId || null })
                .eq('id', userId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("assignManager Error:", error);
            return { success: false, error };
        }
    },
    async updateUserJobTitle(userId, jobTitle) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('profiles')
                .update({ job_title: jobTitle })
                .eq('id', userId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateUserJobTitle Error:", error);
            return { success: false, error };
        }
    },
    // ==========================================
    // PERFORMANCE GOALS
    // ==========================================
    async fetchGoals(employeeId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('performance_goals').select('*').order('created_at', { ascending: false });
            if (employeeId) {
                query = query.eq('employee_id', employeeId);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchGoals Error:", error);
            return [];
        }
    },
    async createGoal(employeeId, title, description, dueDate) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('performance_goals')
                .insert([{ employee_id: employeeId, title, description, due_date: dueDate }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("createGoal Error:", error);
            return { success: false, error };
        }
    },
    // ==========================================
    // DOCUMENT REQUESTS
    // ==========================================
    async fetchDocuments(employeeId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('document_requests').select('*').order('created_at', { ascending: false });
            if (employeeId) {
                query = query.eq('employee_id', employeeId);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchDocuments Error:", error);
            return [];
        }
    },
    async requestDocument(employeeId, docType, purpose) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('document_requests')
                .insert([{ employee_id: employeeId, doc_type: docType, purpose }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("requestDocument Error:", error);
            return { success: false, error };
        }
    },
    async updateDocumentStatus(docId, status) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('document_requests')
                .update({ status })
                .eq('id', docId)
                .select();
            if (error) throw error;
            if (!data || data.length === 0) throw new Error("No rows updated. You might lack permissions (RLS).");
            return { success: true };
        } catch (error) {
            console.error("updateDocumentStatus Error:", error);
            return { success: false, error };
        }
    },
    // ==========================================
    // PROFILE MANAGEMENT
    // ==========================================
    async getSession() {
        if (!supabaseClient) return { data: { session: null } };
        return await supabaseClient.auth.getSession();
    },

    onAuthStateChange(callback) {
        if (!supabaseClient) return;
        return supabaseClient.auth.onAuthStateChange(callback);
    },

    async updateUserPassword(newPassword) {
        try {
            const { data, error } = await supabaseClient.auth.updateUser({ password: newPassword });
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateUserPassword Error:", error);
            return { success: false, error };
        }
    },
    async updateProfilePhoto(userId, base64Url) {
        if (!supabaseClient) return { success: false, error: new Error('Supabase not initialized') };
        try {
            const { error } = await supabaseClient
                .from('profiles')
                .update({ avatar_url: base64Url })
                .eq('id', userId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateProfilePhoto Error:", error);
            return { success: false, error };
        }
    },

    async updateUserProfileDetails(userId, fullName, iqama, phone) {
        if (!supabaseClient) return { success: false, error: new Error('Supabase not initialized') };
        try {
            const { error } = await supabaseClient
                .from('profiles')
                .update({ 
                    full_name: fullName,
                    iqama_number: iqama,
                    phone_number: phone
                })
                .eq('id', userId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateUserProfileDetails Error:", error);
            return { success: false, error };
        }
    },
    // ==========================================
    // PROJECTS & TASK MANAGER
    // ==========================================
    async fetchProjects(userId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('projects').select('*').order('created_at', { ascending: false });
            // Let RLS handle user-specific project visibility, or we can explicitely filter:
            // if (userId) { ... }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchProjects Error:", error);
            return [];
        }
    },
    async createProject(projectName, projectType, description, assignedPeople, projectCategory, projectTags) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('projects')
                .insert([{
                    project_name: projectName,
                    project_type: projectType,
                    description: description,
                    assigned_people: assignedPeople,
                    project_category: projectCategory,
                    project_tags: projectTags
                }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("createProject Error:", error);
            return { success: false, error };
        }
    },
    async updateProject(projectId, projectName, projectType, description, assignedPeople, projectCategory, projectTags) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('projects')
                .update({
                    project_name: projectName,
                    project_type: projectType,
                    description: description,
                    assigned_people: assignedPeople,
                    project_category: projectCategory,
                    project_tags: projectTags
                })
                .eq('id', projectId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateProject Error:", error);
            return { success: false, error };
        }
    },
    async fetchTasks(userId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('tasks').select('*').order('created_at', { ascending: false });
            if (userId) {
                // PostgREST syntax for arrays: visible_to.cs.{userId} checks if array contains userId
                query = query.or(`assignee_id.eq.${userId},created_by.eq.${userId},visible_to.cs.{${userId}}`);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchTasks Error:", error);
            return [];
        }
    },
    async fetchTasksWithProfiles() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('tasks')
                .select('*, profiles:assignee_id(id, full_name, job_title, role), projects(project_name)')
                .order('created_at', { ascending: false });
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchTasksWithProfiles Error:", error);
            return [];
        }
    },
    async createTask(title, description, assigneeId, dueDate, createdBy, priority = 'medium', category = 'General', titleI18n = {}, descI18n = {}, startDate = null, endDate = null, estimatedTime = null, visibility = 'public', projectId = null, tags = [], visibleTo = [], contentType = null, sourceLink = null, uploadLink = null, status = 'todo') {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('tasks')
                .insert([{ 
                    title, 
                    description, 
                    assignee_id: assigneeId, 
                    due_date: dueDate,
                    created_by: createdBy,
                    status: status,
                    priority: priority,
                    category: category,
                    title_i18n: titleI18n,
                    description_i18n: descI18n,
                    start_date: startDate,
                    end_date: endDate,
                    estimated_time: estimatedTime,
                    visibility: visibility,
                    project_id: projectId,
                    tags: tags,
                    visible_to: visibleTo,
                    content_type: contentType,
                    source_link: sourceLink,
                    upload_link: uploadLink
                }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("createTask Error:", error);
            return { success: false, error };
        }
    },
    async updateTaskStatus(taskId, status) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('tasks')
                .update({ status })
                .eq('id', taskId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateTaskStatus Error:", error);
            return { success: false, error };
        }
    },
    async updateTask(taskId, updates) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('tasks')
                .update(updates)
                .eq('id', taskId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateTask Error:", error);
            return { success: false, error };
        }
    },
    async deleteTask(taskId) {
        if (!supabaseClient) return { success: false, error: { message: "Not connected" } };
        try {
            const { error } = await supabaseClient.from('tasks').delete().eq('id', taskId);
            return { error };
        } catch (error) {
            console.error("deleteTask Error:", error);
            return { success: false, error };
        }
    },
    async fetchTaskComments(taskId) {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('task_comments')
                .select('*, profiles:user_id(id, full_name, role)')
                .eq('task_id', taskId)
                .order('created_at', { ascending: true });
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchTaskComments Error:", error);
            return [];
        }
    },
    async addTaskComment(taskId, userId, content) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('task_comments')
                .insert([{ 
                    task_id: taskId,
                    user_id: userId,
                    content: content
                }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("addTaskComment Error:", error);
            return { success: false, error };
        }
    },
    // ==========================================
    // EMPLOYEE DOCUMENTS UPLOAD
    // ==========================================
    async fetchEmployeeDocuments(employeeId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient
                .from('employee_documents')
                .select('id, document_id, employee_id, doc_name, doc_type, owner_name, owner_email, responsible_name, responsible_email, expiration_date, notified_30_days, owner_phone, status, last_notification_status, last_notified_at, last_notification_error, created_at')
                .order('created_at', { ascending: false });
            if (employeeId) {
                query = query.eq('employee_id', employeeId);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchEmployeeDocuments Error:", error);
            return [];
        }
    },
    async fetchEmployeeDocumentFile(documentId) {
        if (!supabaseClient) return { success: false, error: new Error('Supabase not initialized') };
        try {
            const { data, error } = await supabaseClient
                .from('employee_documents')
                .select('doc_base64, doc_type, doc_name')
                .eq('id', documentId)
                .single();
            if (error) throw error;
            return { success: true, data };
        } catch (error) {
            console.error('fetchEmployeeDocumentFile Error:', error);
            return { success: false, error };
        }
    },
    async uploadEmployeeDocument(employeeId, documentRecord) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('employee_documents')
                .insert([{ 
                    employee_id: employeeId,
                    doc_name: documentRecord.documentName,
                    owner_name: documentRecord.ownerName,
                    owner_email: documentRecord.ownerEmail,
                    responsible_name: documentRecord.responsibleName,
                    responsible_email: documentRecord.responsibleEmail,
                    expiration_date: documentRecord.expirationDate,
                    notified_30_days: true,
                    owner_phone: documentRecord.ownerPhone,
                    doc_type: documentRecord.fileType,
                    doc_base64: documentRecord.fileBase64
                }])
                .select('id')
                .single();
            if (error) throw error;
            return { success: true, data };
        } catch (error) {
            console.error("uploadEmployeeDocument Error:", error);
            return { success: false, error };
        }
    },
    async notifyEmployeeDocumentExpiry(documentId) {
        if (!supabaseClient) return { success: false, error: new Error('Supabase not initialized') };
        try {
            const { data, error } = await supabaseClient.functions.invoke('document-expiry-notifier', {
                body: { documentId }
            });
            if (error) throw error;
            return { success: true, data };
        } catch (error) {
            console.error("notifyEmployeeDocumentExpiry Error:", error);
            return { success: false, error };
        }
    },
    async updateEmployeeDocument(documentId, documentRecord) {
        if (!supabaseClient) return { success: false, error: new Error('Supabase not initialized') };
        try {
            const { data, error } = await supabaseClient
                .from('employee_documents')
                .update({
                    doc_name: documentRecord.documentName,
                    owner_name: documentRecord.ownerName,
                    owner_email: documentRecord.ownerEmail,
                    responsible_name: documentRecord.responsibleName,
                    responsible_email: documentRecord.responsibleEmail,
                    expiration_date: documentRecord.expirationDate,
                    owner_phone: documentRecord.ownerPhone
                })
                .eq('id', documentId)
                .select('id')
                .single();
            if (error) throw error;
            return { success: true, data };
        } catch (error) {
            console.error("updateEmployeeDocument Error:", error);
            return { success: false, error };
        }
    },
    async deleteEmployeeDocument(documentId) {
        if (!supabaseClient) return { success: false, error: new Error('Supabase not initialized') };
        try {
            const { data, error } = await supabaseClient
                .from('employee_documents')
                .delete()
                .eq('id', documentId)
                .select('id')
                .single();
            if (error) throw error;
            return { success: true, data };
        } catch (error) {
            console.error("deleteEmployeeDocument Error:", error);
            return { success: false, error };
        }
    },
    // ==========================================
    // EXPENSES
    // ==========================================
    async fetchExpenses(employeeId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('expenses').select('*').order('created_at', { ascending: false });
            if (employeeId) {
                query = query.eq('employee_id', employeeId);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchExpenses Error:", error);
            return [];
        }
    },
    async submitExpense(employeeId, amount, description, receiptBase64) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient
                .from('expenses')
                .insert([{ employee_id: employeeId, amount, description, receipt_base64: receiptBase64 }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("submitExpense Error:", error);
            return { success: false, error };
        }
    },
    async updateExpenseStatus(expenseId, status) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('expenses')
                .update({ status })
                .eq('id', expenseId)
                .select();
            if (error) throw error;
            if (!data || data.length === 0) throw new Error("No rows updated. You might lack permissions (RLS).");
            return { success: true };
        } catch (error) {
            console.error("updateExpenseStatus Error:", error);
            return { success: false, error };
        }
    },
    // ==========================================
    // NOTIFICATIONS
    // ==========================================
    async fetchNotifications(userId) {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('notifications')
                .select('*')
                .eq('user_id', userId)
                .order('created_at', { ascending: false })
                .limit(20);
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchNotifications Error:", error);
            return [];
        }
    },
    async createNotification(userId, message) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient
                .from('notifications')
                .insert([{ user_id: userId, message }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("createNotification Error:", error);
            return { success: false, error };
        }
    },
    async markNotificationsRead(userId) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient
                .from('notifications')
                .update({ is_read: true })
                .eq('user_id', userId)
                .eq('is_read', false);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("markNotificationsRead Error:", error);
            return { success: false, error };
        }
    },
    // ==========================================
    // ADVANCED PAYROLL
    // ==========================================
    async insertPayroll(employeeId, monthYear, baseSalary, overtimePay, deductions, netPay) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient
                .from('payroll')
                .insert([{ 
                    employee_id: employeeId, 
                    month_year: monthYear,
                    base_salary: baseSalary,
                    overtime_pay: overtimePay,
                    deductions: deductions,
                    net_pay: netPay
                }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("insertPayroll Error:", error);
            return { success: false, error };
        }
    },
    // ==========================================
    // Contracts (New)
    // ==========================================
    async fetchContractByEmployeeId(employeeId) {
        if (!supabaseClient) return null;
        try {
            const { data, error } = await supabaseClient
                .from('contracts')
                .select('*')
                .eq('employee_id', employeeId)
                .limit(1)
                .maybeSingle();
            if (error) throw error;
            return data || null;
        } catch (error) {
            console.error("fetchContractByEmployeeId Error:", error);
            return null;
        }
    },
    async upsertContract(contractData) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient
                .from('contracts')
                .upsert(contractData, { onConflict: 'employee_id' });
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("upsertContract Error:", error);
            return { success: false, error };
        }
    },
    // ==========================================
    // Messaging (New)
    // ==========================================
    async fetchAllProfiles() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('profiles')
                .select('id, full_name, role, avatar_url')
                .eq('is_active', true);
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchAllProfiles Error:", error);
            return [];
        }
    },
    async fetchMessageHistory(userId1, userId2) {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('messages')
                .select('*')
                .or(`and(sender_id.eq.${userId1},receiver_id.eq.${userId2}),and(sender_id.eq.${userId2},receiver_id.eq.${userId1})`)
                .order('created_at', { ascending: true });
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchMessageHistory Error:", error);
            return [];
        }
    },
    async sendMessage(senderId, receiverId, content) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient
                .from('messages')
                .insert([{ sender_id: senderId, receiver_id: receiverId, content }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("sendMessage Error:", error);
            return { success: false, error };
        }
    },
    // ==========================================
    // Phase 2 Features
    // ==========================================
    async updateLastLogin(userId) {
        if (!supabaseClient) return;
        try {
            await supabaseClient.from('profiles').update({ last_login: new Date().toISOString() }).eq('id', userId);
        } catch (error) {
            console.error("updateLastLogin Error:", error);
        }
    },
    async fetchTodayAttendance(employeeId) {
        if (!supabaseClient) return null;
        try {
            const today = new Date().toISOString().split('T')[0];
            const { data, error } = await supabaseClient
                .from('attendance')
                .select('*')
                .eq('employee_id', employeeId)
                .eq('date', today)
                .limit(1)
                .maybeSingle();
            if (error) throw error;
            return data || null;
        } catch (error) {
            console.error("fetchTodayAttendance Error:", error);
            return null;
        }
    },
    async fetchAttendanceByEmployee(employeeId) {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('attendance')
                .select('*')
                .eq('employee_id', employeeId)
                .order('date', { ascending: false });
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchAttendanceByEmployee Error:", error);
            return [];
        }
    },
    async fetchAllAttendance() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('attendance')
                .select('*')
                .order('date', { ascending: false });
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchAllAttendance Error:", error);
            return [];
        }
    },
    async clockIn(employeeId, location) {
        if (!supabaseClient) return { success: false };
        try {
            const today = new Date().toISOString().split('T')[0];
            const { error } = await supabaseClient
                .from('attendance')
                .insert([{ 
                    employee_id: employeeId, 
                    date: today,
                    clock_in_time: new Date().toISOString(),
                    clock_in_location: location
                }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("clockIn Error:", error);
            return { success: false, error };
        }
    },
    async clockOut(attendanceId, location, type, overtimeHours) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient
                .from('attendance')
                .update({ 
                    clock_out_time: new Date().toISOString(),
                    clock_out_location: location,
                    clock_out_type: type,
                    overtime_hours: overtimeHours
                })
                .eq('id', attendanceId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("clockOut Error:", error);
            return { success: false, error };
        }
    },

    async postAnnouncement(adminId, title, content) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient
                .from('announcements')
                .insert([{ admin_id: adminId, title, content }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("postAnnouncement Error:", error);
            return { success: false, error };
        }
    },
    async fetchCommunityChat() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('community_chat')
                .select(`
                    *,
                    profiles:user_id(full_name, avatar_url)
                `)
                .order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchCommunityChat Error:", error);
            return [];
        }
    },
    async postCommunityMessage(userId, message, isBirthdayAlert = false) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient
                .from('community_chat')
                .insert([{ user_id: userId, message, is_birthday_alert: isBirthdayAlert }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("postCommunityMessage Error:", error);
            return { success: false, error };
        }
    },

    // ==========================================
    // Departments API
    // ==========================================
    async fetchDepartments() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient.from('departments').select('*').order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchDepartments Error:", error);
            return [];
        }
    },
    async createDepartment(deptData, employeeIds = []) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient.from('departments').insert([deptData]).select().single();
            if (error) throw error;
            
            if (data && employeeIds && employeeIds.length > 0) {
                const { error: profileError } = await supabaseClient.from('profiles').update({ department_id: data.id }).in('id', employeeIds);
                if (profileError) console.error("Error setting department for employees:", profileError);
            }
            
            return { success: true, data };
        } catch (error) {
            console.error("createDepartment Error:", error);
            return { success: false, error };
        }
    },
    async updateDepartment(id, deptData, employeeIds = null) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('departments').update(deptData).eq('id', id);
            if (error) throw error;
            
            if (employeeIds !== null) {
                // Clear existing assignments for this department
                await supabaseClient.from('profiles').update({ department_id: null }).eq('department_id', id);
                // Assign new employees
                if (employeeIds.length > 0) {
                    const { error: profileError } = await supabaseClient.from('profiles').update({ department_id: id }).in('id', employeeIds);
                    if (profileError) console.error("Error setting department for employees:", profileError);
                }
            }
            
            return { success: true };
        } catch (error) {
            console.error("updateDepartment Error:", error);
            return { success: false, error };
        }
    },
    async deleteDepartment(id) {
        if (!supabaseClient) return { success: false };
        try {
            // Unassign employees from this department first to avoid foreign key constraints
            const { error: profileError } = await supabaseClient.from('profiles').update({ department_id: null }).eq('department_id', id);
            if (profileError) console.error("Error unassigning employees from department:", profileError);

            const { error } = await supabaseClient.from('departments').delete().eq('id', id);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("deleteDepartment Error:", error);
            return { success: false, error };
        }
    },

    // ==========================================
    // CRM API
    // ==========================================
    async fetchClients() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient.from('crm_clients').select('*').order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchClients Error:", error);
            return [];
        }
    },
    async createClient(clientData) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('crm_clients').insert([clientData]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("createClient Error:", error);
            return { success: false, error };
        }
    },
    async updateClient(id, clientData) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('crm_clients').update(clientData).eq('id', id);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateClient Error:", error);
            return { success: false, error };
        }
    },
    async deleteClient(id) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('crm_clients').delete().eq('id', id);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("deleteClient Error:", error);
            return { success: false, error };
        }
    },
    async fetchDeals() {
        if (!supabaseClient) return [];
        try {
            // Join with clients
            const { data, error } = await supabaseClient.from('crm_deals')
                .select('*, crm_clients(name)')
                .order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchDeals Error:", error);
            return [];
        }
    },
    async createDeal(dealData) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('crm_deals').insert([dealData]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("createDeal Error:", error);
            return { success: false, error };
        }
    },
    async updateDeal(id, dealData) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('crm_deals').update(dealData).eq('id', id);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateDeal Error:", error);
            return { success: false, error };
        }
    },
    async updateDealStage(dealId, newStage) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('crm_deals').update({ stage: newStage }).eq('id', dealId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateDealStage Error:", error);
            return { success: false, error };
        }
    },
    async createOrder(orderData, dealId) {
        if (!supabaseClient) return { success: false };
        try {
            // First update deal stage to WON
            const { error: dealError } = await supabaseClient.from('crm_deals').update({ stage: 'WON' }).eq('id', dealId);
            if (dealError) throw dealError;
            
            // Then insert order details
            const { error: orderError } = await supabaseClient.from('crm_orders').insert([{ ...orderData, deal_id: dealId }]);
            if (orderError) throw orderError;
            
            return { success: true };
        } catch (error) {
            console.error("createOrder Error:", error);
            return { success: false, error };
        }
    },
    async fetchOrders() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient.from('crm_orders')
                .select('*, crm_deals(title, crm_clients(name))')
                .order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchOrders Error:", error);
            return [];
        }
    },
    async updateOrder(id, orderData) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('crm_orders').update(orderData).eq('id', id);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateOrder Error:", error);
            return { success: false, error };
        }
    },
    async deleteOrder(id) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('crm_orders').delete().eq('id', id);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("deleteOrder Error:", error);
            return { success: false, error };
        }
    },
    async deleteOrderByDealId(dealId) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('crm_orders').delete().eq('deal_id', dealId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("deleteOrderByDealId Error:", error);
            return { success: false, error };
        }
    },

    // ==========================================
    // Integrations / Webhooks API
    // ==========================================
    async fetchWebhooks() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient.from('webhooks').select('*').order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchWebhooks Error:", error);
            return [];
        }
    },
    async createWebhook(webhookData) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('webhooks').insert([webhookData]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("createWebhook Error:", error);
            return { success: false, error };
        }
    },
    async deleteWebhook(id) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('webhooks').delete().eq('id', id);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("deleteWebhook Error:", error);
            return { success: false, error };
        }
    },
    // Trigger webhooks helper function
    async triggerWebhooks(eventType, payload) {
        if (!supabaseClient) return;
        try {
            const webhooks = await this.fetchWebhooks();
            const activeWebhooks = webhooks.filter(w => w.is_active && (w.event_type === eventType || w.event_type === 'all'));
            
            for (const webhook of activeWebhooks) {
                try {
                    // Send POST request to external API
                    fetch(webhook.url, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            event: eventType,
                            timestamp: new Date().toISOString(),
                            data: payload
                        }),
                        mode: 'no-cors' // Prevent CORS errors when blindly firing webhooks
                    }).catch(err => console.error("Webhook trigger failed for", webhook.url, err));
                } catch (e) {
                    console.error("Failed to fire webhook", e);
                }
            }
        } catch(error) {
            console.error("Error triggering webhooks", error);
        }
    },

    // ==========================================
    // SAUDI LABOR LAW CONTRACTS
    // ==========================================
    async fetchEstablishmentSettings() {
        if (!supabaseClient) return null;
        try {
            const { data, error } = await supabaseClient.from('establishment_settings').select('*').limit(1).maybeSingle();
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchEstablishmentSettings Error:", error);
            return null;
        }
    },
    async fetchContractSettings() {
        if (!supabaseClient) return null;
        try {
            const { data, error } = await supabaseClient.from('contract_settings').select('*').limit(1).maybeSingle();
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchContractSettings Error:", error);
            return null;
        }
    },
    async fetchContracts(employeeId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('contracts').select('*').order('created_at', { ascending: false });
            if (employeeId) {
                query = query.eq('employee_id', employeeId);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchContracts Error:", error);
            return [];
        }
    },
    async createContract(contractData) {
        if (!supabaseClient) {
            console.warn("Mock createContract");
            return { success: true, data: { id: 'mock-contract-id', ...contractData } };
        }
        try {
            const { data, error } = await supabaseClient.from('contracts').insert([contractData]).select().single();
            if (error) throw error;
            await this.logAudit('contract', data.id, 'created', { status: data.status });
            return { success: true, data };
        } catch (error) {
            console.error("createContract Error:", error);
            return { success: false, error };
        }
    },
    async updateContract(contractId, updates) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient.from('contracts').update(updates).eq('id', contractId).select().single();
            if (error) throw error;
            await this.logAudit('contract', contractId, 'updated', updates);
            return { success: true, data };
        } catch (error) {
            console.error("updateContract Error:", error);
            return { success: false, error };
        }
    },
    async logAudit(entityType, entityId, action, details) {
        if (!supabaseClient) return;
        try {
            const { data: { session } } = await supabaseClient.auth.getSession();
            const userId = session?.user?.id;
            await supabaseClient.from('audit_logs').insert([{
                user_id: userId,
                entity_type: entityType,
                entity_id: entityId,
                action: action,
                details: details
            }]);
        } catch (error) {
            console.error("logAudit Error:", error);
        }
    }
};
