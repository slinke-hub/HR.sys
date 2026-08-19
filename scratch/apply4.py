import re

with open('e:/HR.sys/js/app.js', 'r', encoding='utf-8') as f:
    content = f.read()

# Chunk 1
content = content.replace(
    '<input type="text" autocomplete="off" id="taskTitle" class="form-control" required placeholder="Task title">',
    '<input type="text" autocomplete="off" id="taskTitle" class="form-control" required placeholder="">'
)

# Chunk 2
content = content.replace(
    '<input type="text" id="taskCategory" class="form-control" placeholder="e.g. Design">',
    '<input type="text" id="taskCategory" class="form-control" placeholder="">'
)

# Chunk 3
content = content.replace(
    '<option value="low">Low</option>',
    '<option value="low"></option>'
)
content = content.replace(
    '<option value="medium" selected>Medium</option>',
    '<option value="medium" selected></option>'
)
content = content.replace(
    '<option value="high">High</option>',
    '<option value="high"></option>'
)
content = content.replace(
    '<option value="urgent">Urgent</option>',
    '<option value="urgent"></option>'
)

# Chunk 4
content = content.replace(
    '<option value="">No Project</option>',
    '<option value=""></option>'
)

# Chunk 5
content = content.replace(
    '<option value="">Select Department</option>',
    '<option value=""></option>'
)
content = content.replace(
    '<option value="Marketing">Marketing</option>',
    '<option value="Marketing"></option>'
)
content = content.replace(
    '<option value="HR">HR</option>',
    '<option value="HR"></option>'
)
content = content.replace(
    '<option value="IT">IT</option>',
    '<option value="IT"></option>'
)
content = content.replace(
    '<option value="Finance">Finance</option>',
    '<option value="Finance"></option>'
)
content = content.replace(
    '<option value="Operations">Operations</option>',
    '<option value="Operations"></option>'
)
content = content.replace(
    '<option value="">Select Sub-Type</option>',
    '<option value=""></option>'
)

# Chunk 6 & 7
content = content.replace(
    '<div class="card-title" style="padding: 1rem 1rem 0;">In Progress <span',
    '<div class="card-title" style="padding: 1rem 1rem 0;"> <span'
)
content = content.replace(
    '<div class="card-title" style="padding: 1rem 1rem 0;">Review <span',
    '<div class="card-title" style="padding: 1rem 1rem 0;"> <span'
)

# Chunk 8
content = content.replace(
    'projectSelect.innerHTML = \'<option value="">No Project</option>\' + (window.projectOptionsCache || \'\');',
    'projectSelect.innerHTML = <option value=""></option> + (window.projectOptionsCache || \'\');'
)

# Chunk 9
content = content.replace(
    '<button class="btn btn-primary" onclick="openProjectModal()"><i data-lucide="plus"></i> New Project</button>',
    '<button class="btn btn-primary" onclick="openProjectModal()"><i data-lucide="plus"></i> </button>'
)

# Chunk 10
content = content.replace(
    "roleSpan.textContent = profile.job_title || profile.role;",
    "let rawRole = profile.job_title || profile.role;\n        roleSpan.textContent = t('role_' + rawRole.toLowerCase().replace(/\\s+/g, '_')) || rawRole;"
)

with open('e:/HR.sys/js/app.js', 'w', encoding='utf-8') as f:
    f.write(content)

print('app.js patched')
