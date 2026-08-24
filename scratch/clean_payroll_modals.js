const fs = require('fs');

let html = fs.readFileSync('index.html', 'utf8');

// payrollLogSalesModal
html = html.replace(/<div class="modal-content" style="max-width: 500px; background: rgba[^>]+>/, '<div class="modal-content" style="max-width: 500px;">');
html = html.replace(/<h2 style="color: #ffffff;">Log Monthly Sales<\/h2>/, '<h2>Log Monthly Sales</h2>');
html = html.replace(/<label style="color: #ffffff;">Employee<\/label>/, '<label class="form-label">Employee</label>');
html = html.replace(/<select id="payrollSalesEmployeeId" required style="width: 100%;[^>]+><\/select>/, '<select id="payrollSalesEmployeeId" class="form-control" required></select>');
html = html.replace(/<label style="color: #ffffff;">Month \/ Year<\/label>/, '<label class="form-label">Month / Year</label>');
html = html.replace(/<input type="month" id="payrollSalesMonthYear" required style="width: 100%;[^>]+>/, '<input type="month" id="payrollSalesMonthYear" class="form-control" required>');
html = html.replace(/<label style="color: #ffffff;">Actual Sales Amount \(SAR\)<\/label>/, '<label class="form-label">Actual Sales Amount (SAR)</label>');
html = html.replace(/<input type="number" step="0.01" min="0" id="payrollSalesAmount" required style="width: 100%;[^>]+>/, '<input type="number" step="0.01" min="0" id="payrollSalesAmount" class="form-control" required>');

// payrollLogAbsenceModal
html = html.replace(/<div class="modal-content" style="max-width: 450px; background: rgba[^>]+>/, '<div class="modal-content" style="max-width: 450px;">');
html = html.replace(/<h3 style="color: #ffffff;">Log Absence<\/h3>/, '<h3>Log Absence</h3>');
html = html.replace(/<label for="payrollAbsenceEmployeeId" style="color: #ffffff;">Employee \*<\/label>/, '<label for="payrollAbsenceEmployeeId" class="form-label">Employee *</label>');
html = html.replace(/<select id="payrollAbsenceEmployeeId" style="width: 100%;[^>]+required><\/select>/, '<select id="payrollAbsenceEmployeeId" class="form-control" required></select>');
html = html.replace(/<label for="payrollAbsenceDate" style="color: #ffffff;">Date of Absence \*<\/label>/, '<label for="payrollAbsenceDate" class="form-label">Date of Absence *</label>');
html = html.replace(/<input type="date" id="payrollAbsenceDate" style="width: 100%;[^>]+required>/, '<input type="date" id="payrollAbsenceDate" class="form-control" required>');
html = html.replace(/<strong style="color: #ffffff;">Excused Absence<\/strong>/, '<strong>Excused Absence</strong>');

// payrollNewLoanModal
html = html.replace(/<div class="modal-content" style="max-width: 450px; background: rgba[^>]+>/, '<div class="modal-content" style="max-width: 450px;">');
html = html.replace(/<h3 style="color: #ffffff;">Request\/Add Employee Loan<\/h3>/, '<h3>Request/Add Employee Loan</h3>');
html = html.replace(/<label for="payrollLoanEmployeeId" style="color: #ffffff;">Employee \*<\/label>/, '<label for="payrollLoanEmployeeId" class="form-label">Employee *</label>');
html = html.replace(/<select id="payrollLoanEmployeeId" style="width: 100%;[^>]+required><\/select>/, '<select id="payrollLoanEmployeeId" class="form-control" required></select>');
html = html.replace(/<label for="payrollLoanAmount" style="color: #ffffff;">Total Loan Amount \(SAR\) \*<\/label>/, '<label for="payrollLoanAmount" class="form-label">Total Loan Amount (SAR) *</label>');
html = html.replace(/<input type="number" step="0.01" id="payrollLoanAmount" style="width: 100%;[^>]+placeholder="e.g. 5000" required>/, '<input type="number" step="0.01" id="payrollLoanAmount" class="form-control" placeholder="e.g. 5000" required>');
html = html.replace(/<label for="payrollLoanInstallment" style="color: #ffffff;">Monthly Installment \(SAR\) \*<\/label>/, '<label for="payrollLoanInstallment" class="form-label">Monthly Installment (SAR) *</label>');
html = html.replace(/<input type="number" step="0.01" id="payrollLoanInstallment" style="width: 100%;[^>]+placeholder="e.g. 500" required>/, '<input type="number" step="0.01" id="payrollLoanInstallment" class="form-control" placeholder="e.g. 500" required>');

fs.writeFileSync('index.html', html);
console.log('Cleaned up payroll modals inline CSS');
