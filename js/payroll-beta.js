(function (root, factory) {
    const api = factory();
    if (typeof module === 'object' && module.exports) module.exports = api;
    if (root) root.PayrollBeta = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
    const money = value => Math.round((Number(value) || 0) * 100) / 100;
    const nonNegative = value => Math.max(0, money(value));

    function calculate(input = {}) {
        const daysInMonth = Math.max(1, Math.trunc(Number(input.daysInMonth) || 30));
        const payableDays = Math.min(daysInMonth, Math.max(0, Number(input.payableDays) || 0));
        const originalBasicSalary = nonNegative(input.basicSalary);
        const salaryRaise = nonNegative(input.salaryRaise);
        const adjustedBasicSalary = money(originalBasicSalary + salaryRaise);
        const earnedBasicSalary = money(adjustedBasicSalary * (payableDays / daysInMonth));
        const cashReward = nonNegative(input.cashReward);
        const commission = nonNegative(input.commission);
        const grossPay = money(earnedBasicSalary + cashReward + commission);
        const otherDeductions = Math.min(nonNegative(input.otherDeductions), grossPay);
        const loanBalance = nonNegative(input.loanBalance);
        const loanPaymentMode = input.loanPaymentMode === 'FULL' ? 'FULL' : 'INSTALLMENT';
        const requestedLoanInstallment = loanPaymentMode === 'FULL' ? loanBalance : nonNegative(input.loanInstallment);
        const availableAfterOtherDeductions = Math.max(0, money(grossPay - otherDeductions));
        const loanDeduction = money(Math.min(loanBalance, requestedLoanInstallment, availableAfterOtherDeductions));
        const totalDeductions = money(otherDeductions + loanDeduction);
        const netPay = money(grossPay - totalDeductions);
        const remainingLoanBalance = money(Math.max(0, loanBalance - loanDeduction));
        const warnings = [];
        if (requestedLoanInstallment > loanBalance) warnings.push('Loan installment was capped at the remaining loan balance.');
        if (requestedLoanInstallment > availableAfterOtherDeductions) warnings.push('Loan installment was capped to prevent negative net pay.');
        if (nonNegative(input.otherDeductions) > grossPay) warnings.push('Other deductions were capped to prevent negative net pay.');

        return {
            employeeName: String(input.employeeName || 'Employee'),
            payrollMonth: String(input.payrollMonth || ''),
            payableDays,
            daysInMonth,
            originalBasicSalary,
            salaryRaise,
            adjustedBasicSalary,
            earnedBasicSalary,
            otherDeductions,
            deductionDescription: String(input.deductionDescription || ''),
            loanBalance,
            loanPaymentMode,
            loanDeduction,
            remainingLoanBalance,
            cashReward,
            commission,
            grossPay,
            totalDeductions,
            netPay,
            transferMethod: String(input.transferMethod || 'Bank Transfer'),
            iban: String(input.iban || ''),
            warnings
        };
    }

    return { calculate };
});
