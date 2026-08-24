const fs = require('fs');

function fixFile(filePath) {
    let content = fs.readFileSync(filePath, 'utf8');
    
    // Add btn class to btn-primary and btn-secondary where missing
    content = content.replace(/class="btn-primary"/g, 'class="btn btn-primary"');
    content = content.replace(/class="btn-secondary"/g, 'class="btn btn-secondary"');
    content = content.replace(/class='btn-primary'/g, 'class="btn btn-primary"');
    content = content.replace(/class='btn-secondary'/g, 'class="btn btn-secondary"');

    // Make sure we don't end up with class="btn btn btn-primary" if they already had it but were written like class="btn btn-primary" 
    // Actually the regex above only matches EXACTLY class="btn-primary" (without btn) so we are safe.

    // If this is index.html, inject the modal style override
    if (filePath.includes('index.html') && !content.includes('payroll-modal-color-fix')) {
        const styleBlock = `
    <!-- payroll-modal-color-fix -->
    <style>
        #payrollProcessingModal .modal-content *,
        #payrollLogSalesModal .modal-content *,
        #payrollLogAbsenceModal .modal-content *,
        #payrollNewLoanModal .modal-content * {
            color: #ffffff !important;
        }
    </style>
</head>`;
        content = content.replace('</head>', styleBlock);
    }
    
    fs.writeFileSync(filePath, content, 'utf8');
}

fixFile('e:/HR.sys/index.html');
fixFile('e:/HR.sys/js/payroll.js');
console.log("Fixed files successfully.");
