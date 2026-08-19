import re

with open('e:/HR.sys/js/app.js', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Client Directory
content = content.replace(
    '<div class="card-title">Client Directory</div>',
    '<div class="card-title"></div>'
)

# 2. No clients yet
content = content.replace(
    '<tr><td colspan="5" class="text-center">No clients yet</td></tr>',
    '<tr><td colspan="5" class="text-center"></td></tr>'
)

# 3. Deal / Client
content = content.replace(
    '<th>Deal / Client</th>',
    '<th></th>'
)

# 4. No orders found
content = content.replace(
    '<tr><td colspan="7" style="text-align:center;">No orders found</td></tr>',
    '<tr><td colspan="7" style="text-align:center;"></td></tr>'
)

with open('e:/HR.sys/js/app.js', 'w', encoding='utf-8') as f:
    f.write(content)

print('app.js patched for final missing strings')
