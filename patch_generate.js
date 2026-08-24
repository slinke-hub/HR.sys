const fs = require('fs');
let code = fs.readFileSync('js/payroll.js', 'utf8');

const regex = /window\.generateAllPayslips = async function\(\) \{[\s\S]*?\};(\s*window\.printPayslip)/;

const newGen = `window.generateAllPayslips = async function() {
    const modal = document.getElementById('payrollProcessingModal');
    const msg = document.getElementById('payrollProcessingMessage');
    if (modal) {
        msg.textContent = "Running calculations and saving...";
        modal.style.display = 'flex';
    }
    
    const today = new Date();
    const currentMonth = \`\${today.getFullYear()}-\${String(today.getMonth() + 1).padStart(2, '0')}\`;

    const employees = await db.fetchAllEmployees();
    const sales = await db.fetchMonthlySales(currentMonth);
    const absences = await db.fetchAbsences(currentMonth);
    const loans = await db.fetchEmployeeLoans();
    const settings = await db.fetchPayrollSettings();
    const adjustments = await db.fetchPayrollAdjustments(currentMonth);

    const generatedPayslips = [];
    
    for (const emp of employees) {
        if(emp.role === 'ADMIN' && (!emp.base_salary || emp.base_salary === 0)) continue; // skip pure admins without salary
        
        const baseSalary = emp.base_salary || 0;
        
        // 1. Commission Calculation
        let commission = 0;
        const empSales = sales.filter(s => s.employee_id === emp.id);
        const actualSales = empSales.reduce((sum, s) => sum + Number(s.amount), 0);
        const targetSales = 10000; // Mock target for now
        
        const percentageAchieved = targetSales > 0 ? (actualSales / targetSales) * 100 : 0;
        if (percentageAchieved > 50 && percentageAchieved <= 100) {
            commission = actualSales * 0.05;
        } else if (percentageAchieved > 100) {
            commission = actualSales * 0.10;
        }
        
        // 2. Overtime
        let overtimePay = 0;
        if (settings.is_overtime_enabled) {
            // Mock OT for now, or check adjustments
            const otHours = 0;
            const hourlyRate = (baseSalary / 30) / 8;
            overtimePay = otHours * (hourlyRate * 1.5);
        }

        // 3. Deductions
        const dailyRate = baseSalary / 30;
        const empAbsences = absences.filter(a => a.employee_id === emp.id && !a.is_excused);
        const absenceDeduction = empAbsences.length * dailyRate;
        
        const empLoans = loans.filter(l => l.employee_id === emp.id && l.remaining_balance > 0);
        let loanDeduction = 0;
        empLoans.forEach(l => {
            loanDeduction += Math.min(Number(l.monthly_installment), Number(l.remaining_balance));
        });
        
        const totalDeductions = absenceDeduction + loanDeduction;
        
        // 4. Adjustments
        const empAdjs = adjustments.filter(a => a.employee_id === emp.id);
        let adjsAmount = 0;
        empAdjs.forEach(a => {
            if(a.type === 'BONUS') commission += Number(a.amount);
            if(a.type === 'DEDUCTION') totalDeductions += Number(a.amount);
        });

        const netPay = baseSalary + commission + overtimePay - totalDeductions;
        
        generatedPayslips.push({
            employee_id: emp.id,
            employee_name: emp.full_name || 'Unknown',
            month_year: currentMonth,
            base_salary: baseSalary,
            commission: commission,
            overtime_pay: overtimePay,
            deductions: totalDeductions,
            net_pay: netPay
        });
    }

    if (generatedPayslips.length > 0) {
        await db.saveReleasedPayslips(generatedPayslips);
    }
    
    if (modal) {
        modal.style.display = 'none';
    }
    
    alert("Payslips generated and saved successfully!");
    switchPayrollTab('released');
};
$1`;

if (code.match(regex)) {
    code = code.replace(regex, newGen);
    fs.writeFileSync('js/payroll.js', code);
    console.log('Success');
} else {
    console.log('Regex failed');
}
