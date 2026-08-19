import json
import re

translations = {
    "ui_manage_requests_subtitle": "إدارة طلبات الإجازات والسلف والدعم التقني والطلبات الأخرى.",
    "ui_new_request": "طلب جديد",
    "ui_connect_colleagues": "تواصل مع زملائك!",
    "ph_type_message": "اكتب رسالة...",
    "ui_no_recent_logins": "لا توجد تسجيلات دخول حديثة.",
    "ui_date": "التاريخ",
    "ui_return_to_admin": "العودة إلى الإدارة"
}

en_translations = {
    "ui_manage_requests_subtitle": "Manage leave, loan, IT support, and other requests.",
    "ui_new_request": "New Request",
    "ui_connect_colleagues": "Connect with your colleagues!",
    "ph_type_message": "Type a message...",
    "ui_no_recent_logins": "No recent logins.",
    "ui_date": "Date",
    "ui_return_to_admin": "Return to Admin"
}

with open('e:/HR.sys/js/data.js', 'r', encoding='utf-8') as f:
    content = f.read()

# Add to English dictionary
en_idx = content.find('en: {')
if en_idx != -1:
    en_end_idx = content.find('},', en_idx)
    en_content = content[en_idx:en_end_idx]
    
    # insert at the end of en object
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
    
    # insert at the end of ar object
    new_ar_lines = []
    for k, v in translations.items():
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

print(f"Added new translations to data.js")
