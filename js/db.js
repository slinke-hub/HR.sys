// IMPORTANT: Replace these with your actual Supabase Project URL and Anon Key
const SUPABASE_URL = 'https://bbbetcdioiaozdjkvwxu.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJiYmV0Y2Rpb2lhb3pkamt2d3h1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMTM0NjQsImV4cCI6MjEwMTU4OTQ2NH0.GhV7HsGnAXA8Zb_IV3hxhwI9qmbM3qhcuWRMSXKUNcw';

// Initialize the Supabase client
// This uses the global supabase object loaded via the CDN in index.html
let supabaseClient = null;

if (SUPABASE_URL !== 'YOUR_SUPABASE_URL' && SUPABASE_ANON_KEY !== 'YOUR_SUPABASE_ANON_KEY') {
    supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    console.log("Supabase client initialized successfully.");
} else {
    console.warn("Supabase credentials not configured. Using mocked data/actions.");
}

// Global DB helper functions for the prototype
const db = {
    async clockIn(userId) {
        if (!supabaseClient) return true;
        try {
            const { error } = await supabaseClient
                .from('time_punches')
                .insert([{ punch_type: 'IN', employee_id: userId }]);
            if (error) throw error;
            return true;
        } catch (error) {
            console.error("Error clocking in:", error.message);
            return false;
        }
    },
    
    async clockOut(userId) {
        if (!supabaseClient) return true;
        try {
            const { error } = await supabaseClient
                .from('time_punches')
                .insert([{ punch_type: 'OUT', employee_id: userId }]);
            if (error) throw error;
            return true;
        } catch (error) {
            console.error("Error clocking out:", error.message);
            return false;
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
                .single();
            if (error && error.code !== 'PGRST116') throw error; // Ignore no rows error
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

    async getUserProfile(userId) {
        if (!supabaseClient) {
            return { role: 'EMPLOYEE', job_title: '', base_salary: 3000, annual_leave_allowance: 30, sick_leave_allowance: 10, manager_id: null };
        }

        try {
            const { data, error } = await supabaseClient
                .from('profiles')
                .select('role, job_title, manager_id, base_salary, annual_leave_allowance, sick_leave_allowance')
                .eq('id', userId)
                .single();
            
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error fetching profile:", error.message);
            return { role: 'EMPLOYEE', job_title: '', base_salary: 3000, annual_leave_allowance: 30, sick_leave_allowance: 10, manager_id: null };
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

    async fetchLeaveRequests(userId) {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('leave_requests')
                .select('*')
                .eq('employee_id', userId)
                .order('created_at', { ascending: false });
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error fetching leave requests:", error.message);
            return [];
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
                .select('*');
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

    async updateLeaveStatus(leaveId, status) {
        if (!supabaseClient) return true;
        try {
            const { error } = await supabaseClient
                .from('leave_requests')
                .update({ status: status })
                .eq('id', leaveId);
            if (error) throw error;
            return true;
        } catch (e) {
            return false;
        }
    },
    // USER MANAGEMENT (ADMIN)
    // ==========================================
    async fetchUsers() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient
                .from('profiles')
                .select('id, emp_index, full_name, iqama_number, phone_number, role, job_title, created_at, manager_id, base_salary')
                .order('emp_index', { ascending: true });
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchUsers Error:", error);
            return [];
        }
    },
    async createUser(email, password, role, jobTitle = '', fullName = '', iqama = '', phone = '') {
        if (!supabaseClient) return { data: null, error: new Error('No DB') };
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
    // ==========================================
    // PROFILE MANAGEMENT
    // ==========================================
    async getSession() {
        if (!supabaseClient) return { data: { session: null } };
        return await supabaseClient.auth.getSession();
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
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
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
    // ==========================================
    // TASK MANAGER
    // ==========================================
    async fetchTasks(userId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('tasks').select('*, assignee:assignee_id(email), creator:created_by(email)').order('created_at', { ascending: false });
            if (userId) {
                query = query.or(`assignee_id.eq.${userId},created_by.eq.${userId}`);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("fetchTasks Error:", error);
            return [];
        }
    },
    async createTask(title, description, assigneeId, dueDate, createdBy) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('tasks')
                .insert([{ 
                    title, 
                    description, 
                    assignee_id: assigneeId, 
                    due_date: dueDate,
                    created_by: createdBy
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
    // ==========================================
    // EMPLOYEE DOCUMENTS UPLOAD
    // ==========================================
    async fetchEmployeeDocuments(employeeId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('employee_documents').select('*').order('created_at', { ascending: false });
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
    async uploadEmployeeDocument(employeeId, docName, docType, docBase64) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('employee_documents')
                .insert([{ 
                    employee_id: employeeId, 
                    doc_name: docName, 
                    doc_type: docType,
                    doc_base64: docBase64
                }]);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("uploadEmployeeDocument Error:", error);
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
                .insert([{ employee_id: employeeId, amount, description, receipt_base64 }]);
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
            const { error } = await supabaseClient
                .from('expenses')
                .update({ status })
                .eq('id', expenseId);
            if (error) throw error;
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
                .single();
            if (error && error.code !== 'PGRST116') throw error; // PGRST116 is "No rows found"
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
    }
};
