import json

ar_translations = {
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
    "crm_stage_lost": "خسارة"
}

en_translations = {
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
    "crm_stage_lost": "LOST"
}

with open('e:/HR.sys/js/data.js', 'r', encoding='utf-8') as f:
    content = f.read()

# Add to English dictionary
en_idx = content.find('en: {')
if en_idx != -1:
    en_end_idx = content.find('},', en_idx)
    en_content = content[en_idx:en_end_idx]
    
    new_en_lines = []
    for k, v in en_translations.items():
        if f'"{k}":' not in en_content and f'{k}:' not in en_content:
            new_en_lines.append(f'    {k}: "{v}",')
    
    if new_en_lines:
        en_content = en_content.rstrip()
        if not en_content.endswith(','):
            en_content += ','
        en_content += '\n' + '\n'.join(new_en_lines)
    
    content = content[:en_idx] + en_content + '\n' + content[en_end_idx:]

# Add to Arabic dictionary
ar_idx = content.find('ar: {')
if ar_idx != -1:
    ar_end_idx = content.find('};', ar_idx)
    if ar_end_idx == -1:
        ar_end_idx = content.rfind('}')
        
    ar_content = content[ar_idx:ar_end_idx]
    
    new_ar_lines = []
    for k, v in ar_translations.items():
        if f'"{k}":' not in ar_content and f'{k}:' not in ar_content:
            new_ar_lines.append(f'    {k}: "{v}",')
            
    if new_ar_lines:
        ar_content = ar_content.rstrip()
        if not ar_content.endswith(','):
            ar_content += ','
        ar_content += '\n' + '\n'.join(new_ar_lines)
        
    content = content[:ar_idx] + ar_content + '\n' + content[ar_end_idx:]

with open('e:/HR.sys/js/data.js', 'w', encoding='utf-8') as f:
    f.write(content)

print("data.js updated with new strings")
