with open('payroll_manager_migration.sql', 'r', encoding='utf-8') as f:
    content = f.read()

import re

# Find all CREATE POLICY statements
def replace_policy(match):
    full_stmt = match.group(0)
    policy_name = match.group(1)
    table_name = match.group(2)
    return f"DROP POLICY IF EXISTS {policy_name} ON {table_name};\n{full_stmt}"

# Replace CREATE POLICY "..." ON public.table ...
content = re.sub(r'CREATE POLICY ("[^"]+") ON (public\.[a-zA-Z_]+).*?;', replace_policy, content)

with open('payroll_manager_migration.sql', 'w', encoding='utf-8') as f:
    f.write(content)

print("Updated policies in payroll_manager_migration.sql")
