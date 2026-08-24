const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

const replacements = [
  ['<strong>Assignee:</strong>', '<strong data-i18n="html_assignee">Assignee</strong>:'],
  ['<strong>Creator:</strong>', '<strong data-i18n="html_creator">Creator</strong>:'],
  ['<strong>Status:</strong>', '<strong data-i18n="html_status">Status</strong>:'],
  ['<strong>Priority:</strong>', '<strong data-i18n="html_priority">Priority</strong>:'],
  ['<strong>Visibility:</strong>', '<strong data-i18n="html_visibility">Visibility</strong>:'],
  ['<strong>Start Date:</strong>', '<strong data-i18n="html_start_date">Start Date</strong>:'],
  ['<strong>Due Date:</strong>', '<strong data-i18n="html_due_date">Due Date</strong>:'],
  ['<strong>End Date:</strong>', '<strong data-i18n="html_end_date">End Date</strong>:'],
  ['<strong>Est. Time:</strong>', '<strong data-i18n="html_est_time">Est. Time</strong>:']
];

for (let [from, to] of replacements) {
    html = html.split(from).join(to);
}

fs.writeFileSync('index.html', html);
console.log('Modified index.html');
