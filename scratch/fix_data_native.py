import json
import codecs

ar_translations = {
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
}

with codecs.open('e:/HR.sys/js/data.js', 'r', 'utf-8') as f:
    content = f.read()

import re
# Strip out all garbled ??? or O U... stuff
for k in ar_translations:
    content = re.sub(r'\s*' + k + r':\s*".*?",?', '', content)

# Now inject it into the ar block
ar_idx = content.find('ar: {')
if ar_idx != -1:
    ar_end_idx = content.find('};', ar_idx)
    if ar_end_idx == -1:
        ar_end_idx = content.rfind('}')
        
    ar_content = content[ar_idx:ar_end_idx]
    
    lines = []
    for k, v in ar_translations.items():
        lines.append(f'    {k}: "{v}",')
        
    ar_content = ar_content.rstrip()
    if not ar_content.endswith(','):
        ar_content += ','
    ar_content += '\n' + '\n'.join(lines)
    
    content = content[:ar_idx] + ar_content + '\n' + content[ar_end_idx:]

with codecs.open('e:/HR.sys/js/data.js', 'w', 'utf-8') as f:
    f.write(content)

print("data.js rewritten natively in python to avoid Powershell UTF-8 clobbering.")
