const fs = require('fs');
let content = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

const ar_translations = {
    "ui_manage_requests_subtitle": "إدارة طلبات الإجازات والسلف والدعم التقني والطلبات الأخرى.",
    "ui_new_request": "طلب جديد",
    "ui_connect_colleagues": "تواصل مع زملائك!",
    "ph_type_message": "اكتب رسالة...",
    "ui_no_recent_logins": "لا توجد تسجيلات دخول حديثة.",
    "ui_date": "التاريخ",
    "ui_return_to_admin": "العودة إلى الإدارة",
    "ph_task_title": "عنوان المهمة",
    "ph_eg_design": "مثال: تصميم",
    "ui_low": "منخفض",
    "ui_medium": "متوسط",
    "ui_high": "عالي",
    "ui_urgent": "عاجل",
    "ui_no_project": "لا يوجد مشروع",
    "ph_select_department": "اختر القسم",
    "dept_marketing": "التسويق",
    "dept_hr": "الموارد البشرية",
    "dept_it": "تقنية المعلومات",
    "dept_finance": "المالية",
    "dept_operations": "العمليات",
    "ph_select_sub_type": "اختر النوع الفرعي",
    "status_in_progress": "قيد التنفيذ",
    "status_review": "مراجعة",
    "ui_new_project_btn": "مشروع جديد +",
    "role_admin": "مدير النظام",
    "role_employee": "موظف",
    "role_manager": "مدير",
    "role_system_admin": "مدير النظام",
    "ui_manage_crm_subtitle": "إدارة عملاء نظام إدارة العلاقات الخاصة بك هنا.",
    "ui_name": "الاسم",
    "ui_no_clients": "لا يوجد عملاء",
    "ui_new_client": "عميل جديد +",
    "ui_deal_pipeline": "مسار الصفقات",
    "ui_new_deal": "صفقة جديدة +",
    "crm_stage_lead": "عميل محتمل",
    "crm_stage_pitch": "عرض",
    "crm_stage_negotiation": "تفاوض",
    "crm_stage_won": "فوز",
    "crm_stage_lost": "خسارة",
    "ui_client_directory": "دليل العملاء",
    "ui_no_clients_yet": "لا يوجد عملاء حتى الآن",
    "ui_deal_client": "الصفقة / العميل",
    "ui_no_orders_found": "لم يتم العثور على طلبات",
    "search_placeholder": "بحث (Cmd/Ctrl + K)",
    "nav_messages": "الرسائل",
    "msg_refresh": "تحديث"
};

const en_translations = {
    "ui_manage_requests_subtitle": "Manage leave, loan, IT support, and other requests.",
    "ui_new_request": "New Request",
    "ui_connect_colleagues": "Connect with your colleagues!",
    "ph_type_message": "Type a message...",
    "ui_no_recent_logins": "No recent logins.",
    "ui_date": "Date",
    "ui_return_to_admin": "Return to Admin",
    "ph_task_title": "Task title",
    "ph_eg_design": "e.g. Design",
    "ui_low": "Low",
    "ui_medium": "Medium",
    "ui_high": "High",
    "ui_urgent": "Urgent",
    "ui_no_project": "No Project",
    "ph_select_department": "Select Department",
    "dept_marketing": "Marketing",
    "dept_hr": "HR",
    "dept_it": "IT",
    "dept_finance": "Finance",
    "dept_operations": "Operations",
    "ph_select_sub_type": "Select Sub-Type",
    "status_in_progress": "In Progress",
    "status_review": "Review",
    "ui_new_project_btn": "New Project +",
    "role_admin": "System Admin",
    "role_employee": "Employee",
    "role_manager": "Manager",
    "role_system_admin": "System Admin",
    "ui_manage_crm_subtitle": "Manage your CRM clients here.",
    "ui_name": "Name",
    "ui_no_clients": "No clients found",
    "ui_new_client": "New Client +",
    "ui_deal_pipeline": "Deal Pipeline",
    "ui_new_deal": "New Deal +",
    "crm_stage_lead": "LEAD",
    "crm_stage_pitch": "PITCH",
    "crm_stage_negotiation": "NEGOTIATION",
    "crm_stage_won": "WON",
    "crm_stage_lost": "LOST",
    "ui_client_directory": "Client Directory",
    "ui_no_clients_yet": "No clients yet",
    "ui_deal_client": "Deal / Client",
    "ui_no_orders_found": "No orders found",
    "search_placeholder": "Search (Cmd/Ctrl + K)",
    "nav_messages": "Messages",
    "msg_refresh": "Refresh"
};

// Replace garbled strings (those containing lots of question marks) first
content = content.replace(/.*ui_new_request:\s*"\?+".*\n/g, '');
content = content.replace(/.*ui_manage_requests_subtitle:\s*"\?+".*\n/g, '');
content = content.replace(/.*ui_connect_colleagues:\s*"\?+".*\n/g, '');
content = content.replace(/.*ph_type_message:\s*"\?+".*\n/g, '');
content = content.replace(/.*ui_no_recent_logins:\s*"\?+".*\n/g, '');
content = content.replace(/.*ui_date:\s*"\?+".*\n/g, '');
content = content.replace(/.*ui_return_to_admin:\s*"\?+".*\n/g, '');

for (const k of Object.keys(ar_translations)) {
    const r = new RegExp(`.*${k}:\\s*"\\?+".*\\n`, 'g');
    content = content.replace(r, '');
}

// Add to English dictionary
const en_idx = content.indexOf('en: {');
if (en_idx !== -1) {
    const en_end_idx = content.indexOf('},', en_idx);
    let en_content = content.substring(en_idx, en_end_idx);
    
    let new_en_lines = [];
    for (const [k, v] of Object.entries(en_translations)) {
        if (!en_content.includes(`"${k}":`) && !en_content.includes(`${k}:`)) {
            new_en_lines.push(`    ${k}: "${v}",`);
        } else {
            // Replace existing
            const regex = new RegExp(`${k}:\\s*".*?"`, 'g');
            en_content = en_content.replace(regex, `${k}: "${v}"`);
        }
    }
    
    if (new_en_lines.length > 0) {
        en_content = en_content.trimRight();
        if (!en_content.endsWith(',')) en_content += ',';
        en_content += '\n' + new_en_lines.join('\n');
    }
    content = content.substring(0, en_idx) + en_content + '\n' + content.substring(en_end_idx);
}

// Add to Arabic dictionary
const ar_idx = content.indexOf('ar: {');
if (ar_idx !== -1) {
    let ar_end_idx = content.indexOf('};', ar_idx);
    if (ar_end_idx === -1) ar_end_idx = content.lastIndexOf('}');
        
    let ar_content = content.substring(ar_idx, ar_end_idx);
    
    let new_ar_lines = [];
    for (const [k, v] of Object.entries(ar_translations)) {
        if (!ar_content.includes(`"${k}":`) && !ar_content.includes(`${k}:`)) {
            new_ar_lines.push(`    ${k}: "${v}",`);
        } else {
             const regex = new RegExp(`${k}:\\s*".*?"`, 'g');
             ar_content = ar_content.replace(regex, `${k}: "${v}"`);
        }
    }
            
    if (new_ar_lines.length > 0) {
        ar_content = ar_content.trimRight();
        if (!ar_content.endsWith(',')) ar_content += ',';
        ar_content += '\n' + new_ar_lines.join('\n');
    }
        
    content = content.substring(0, ar_idx) + ar_content + '\n' + content.substring(ar_end_idx);
}

fs.writeFileSync('e:/HR.sys/js/data.js', content, 'utf8');
console.log("data.js successfully patched with properly encoded strings.");
