import re

with open('e:/HR.sys/js/app.js', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Manage your CRM clients here.
content = content.replace(
    '<p class="page-subtitle">Manage your CRM clients here.</p>',
    '<p class="page-subtitle"></p>'
)

# 2. Name
content = content.replace(
    '<th>Name</th>',
    '<th></th>'
)

# 3. No clients found
content = content.replace(
    '<td colspan="5" style="text-align:center;">No clients found</td>',
    '<td colspan="5" style="text-align:center;"></td>'
)

# 4. New Client
content = content.replace(
    '<i data-lucide="plus"></i> New Client',
    '<i data-lucide="plus"></i> '
)
content = content.replace(
    "document.getElementById('crmClientModalTitle').innerText = 'New Client';",
    "document.getElementById('crmClientModalTitle').innerText = t('ui_new_client') || 'New Client';"
)

# 5. Deal Pipeline
content = content.replace(
    '<div class="card-title">Deal Pipeline</div>',
    '<div class="card-title"></div>'
)

# 6. New Deal
content = content.replace(
    '<i data-lucide="plus"></i> New Deal',
    '<i data-lucide="plus"></i> '
)
content = content.replace(
    "titleEl.textContent = 'New Deal';",
    "titleEl.textContent = t('ui_new_deal') || 'New Deal';"
)

# 7. CRM stages
content = content.replace(
    '<h3 id="crm-header-"> ()</h3>',
    '<h3 id="crm-header-"> ()</h3>'
)

with open('e:/HR.sys/js/app.js', 'w', encoding='utf-8') as f:
    f.write(content)

print('app.js patched for CRM')
