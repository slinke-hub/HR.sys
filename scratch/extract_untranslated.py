import json
import re

with open('e:/HR.sys/js/data.js', 'r', encoding='utf-8') as f:
    content = f.read()

# Extract en and ar objects
en_match = re.search(r'en:\s*({.*?}),\s*ar:', content, re.DOTALL)
ar_match = re.search(r'ar:\s*({.*?})\s*};', content, re.DOTALL)

if not en_match or not ar_match:
    print("Could not find en or ar objects")
    exit(1)

# A crude parser to extract keys and values
def extract_kv(text):
    kv = {}
    lines = text.split('\n')
    for line in lines:
        match = re.search(r'^\s*([a-zA-Z0-9_]+):\s*"(.*)",?\s*$', line)
        if match:
            kv[match.group(1)] = match.group(2)
    return kv

en_kv = extract_kv(en_match.group(1))
ar_kv = extract_kv(ar_match.group(1))

untranslated = {}
for k, v in en_kv.items():
    if k in ar_kv and ar_kv[k] == v:
        # Check if it actually contains letters (skip things like "10" or empty strings)
        if re.search(r'[a-zA-Z]', v) and not v.startswith('Cmd/Ctrl'):
            untranslated[k] = v

with open('e:/HR.sys/scratch/to_translate.json', 'w', encoding='utf-8') as f:
    json.dump(untranslated, f, indent=4)

print(f"Found {len(untranslated)} untranslated keys.")
