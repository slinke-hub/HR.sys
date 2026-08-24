const fs = require('fs');
let html = fs.readFileSync('e:/HR.sys/index.html', 'utf8');

// Replace the specific h2 and p tags in successModal
html = html.replace(
    '<h2 id="successModalTitle" style="margin-bottom: 0.5rem;">', 
    '<h2 id="successModalTitle" style="margin-bottom: 0.5rem; color: #ffffff;">'
);

html = html.replace(
    '<p id="successModalMessage" style="color: var(--color-text-secondary); margin-bottom: 1.5rem;">',
    '<p id="successModalMessage" style="color: rgba(255,255,255,0.8); margin-bottom: 1.5rem;">'
);

// Also add it to the global override just in case
if (html.includes('#payrollProcessingModal .modal-content *,')) {
    html = html.replace(
        '#payrollProcessingModal .modal-content *,',
        '#successModal .modal-content *,\n        #payrollProcessingModal .modal-content *,'
    );
}

fs.writeFileSync('e:/HR.sys/index.html', html, 'utf8');
console.log("Success modal font colors changed to white.");
