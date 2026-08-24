const fs = require('fs');
let code = `
window.downloadPayrollTemplate = async function() {
    const today = new Date();
    const currentMonth = today.getFullYear() + '-' + String(today.getMonth() + 1).padStart(2, '0');
    
    // Fetch active employees
    const { data: profiles, error } = await supabaseClient
        .from('profiles')
        .select('*')
        .eq('status', 'ACTIVE');
        
    let data = [];
    if (profiles && profiles.length > 0) {
        data = profiles.map(u => ({
            "Employee ID": u.id,
            "Employee Name": u.full_name,
            "Month (YYYY-MM)": currentMonth,
            "Base Salary": u.salary || 0,
            "Commission": 0,
            "Overtime Pay": 0,
            "Deductions": 0
        }));
    } else {
        data.push({
            "Employee ID": "example-uuid-here",
            "Employee Name": "John Doe",
            "Month (YYYY-MM)": currentMonth,
            "Base Salary": 5000,
            "Commission": 0,
            "Overtime Pay": 0,
            "Deductions": 0
        });
    }

    const ws = XLSX.utils.json_to_sheet(data);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "Payroll Template");
    XLSX.writeFile(wb, "Payroll_Template_" + currentMonth + ".xlsx");
};

window.handleBulkPayslipUpload = async function(event) {
    const file = event.target.files[0];
    if (!file) return;

    const modal = document.getElementById('payrollProcessingModal');
    const msg = document.getElementById('payrollProcessingMessage');
    if (modal) {
        if(msg) msg.textContent = "Processing Bulk Excel Upload...";
        modal.classList.add('active', 'show');
        modal.style.display = 'flex';
    }

    const reader = new FileReader();
    reader.onload = async function(e) {
        try {
            const data = new Uint8Array(e.target.result);
            const workbook = XLSX.read(data, { type: 'array' });
            const firstSheetName = workbook.SheetNames[0];
            const worksheet = workbook.Sheets[firstSheetName];
            const json = XLSX.utils.sheet_to_json(worksheet);

            const payslips = [];
            for (const row of json) {
                const empId = row["Employee ID"];
                const empName = row["Employee Name"] || "Unknown";
                const monthYear = row["Month (YYYY-MM)"];
                const baseSalary = parseFloat(row["Base Salary"]) || 0;
                const commission = parseFloat(row["Commission"]) || 0;
                const overtimePay = parseFloat(row["Overtime Pay"]) || 0;
                const deductions = parseFloat(row["Deductions"]) || 0;

                if (!empId || !monthYear) continue;

                const netPay = baseSalary + commission + overtimePay - deductions;

                payslips.push({
                    employee_id: empId,
                    employee_name: empName,
                    month_year: monthYear,
                    base_salary: baseSalary,
                    commission: commission,
                    overtime_pay: overtimePay,
                    deductions: deductions,
                    net_pay: netPay
                });
            }

            if (payslips.length === 0) {
                throw new Error("No valid data found in Excel file.");
            }

            const res = await db.saveReleasedPayslips(payslips);
            
            if (modal) {
                modal.classList.remove('active', 'show');
                modal.style.display = 'none';
            }

            if (res.success) {
                if (document.getElementById('successModal')) {
                    const titleEl = document.getElementById('successModalTitle');
                    const msgEl = document.getElementById('successModalMessage');
                    if (titleEl) titleEl.innerText = (window.t && window.t('success')) || 'Success';
                    if (msgEl) msgEl.innerText = 'Bulk upload complete. ' + payslips.length + ' payslips generated!';
                    
                    document.getElementById('successModal').classList.add('active', 'show');
                    if (window.lucide) { window.lucide.createIcons(); }
                } else {
                    alert('Bulk upload complete. ' + payslips.length + ' payslips generated!');
                }
                switchPayrollTab('released');
            } else {
                alert("Failed to upload payslips.");
            }
        } catch (error) {
            console.error(error);
            if (modal) {
                modal.classList.remove('active', 'show');
                modal.style.display = 'none';
            }
            alert("Error processing Excel file: " + error.message);
        }
        
        event.target.value = ''; // Reset input
    };
    reader.readAsArrayBuffer(file);
};
`;
fs.appendFileSync('e:/HR.sys/js/payroll.js', '\n' + code, 'utf8');
