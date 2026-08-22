const test = require('node:test');
const assert = require('node:assert/strict');
const { calculate } = require('../js/payroll-beta.js');

test('deducts only the scheduled loan installment', () => {
    const result = calculate({ basicSalary: 10000, payableDays: 30, daysInMonth: 30, loanBalance: 12000, loanInstallment: 1000 });
    assert.equal(result.loanDeduction, 1000);
    assert.equal(result.remainingLoanBalance, 11000);
    assert.equal(result.netPay, 9000);
});

test('applies a raise to contractual and earned basic salary', () => {
    const result = calculate({ basicSalary: 8000, salaryRaise: 500, payableDays: 30, daysInMonth: 30 });
    assert.equal(result.adjustedBasicSalary, 8500);
    assert.equal(result.earnedBasicSalary, 8500);
    assert.equal(result.netPay, 8500);
});

test('adds cash rewards and commissions once', () => {
    const result = calculate({ basicSalary: 7000, payableDays: 30, daysInMonth: 30, cashReward: 750, commission: 1250 });
    assert.equal(result.grossPay, 9000);
    assert.equal(result.netPay, 9000);
});

test('prorates salary by payable days', () => {
    const result = calculate({ basicSalary: 9000, payableDays: 15, daysInMonth: 30 });
    assert.equal(result.earnedBasicSalary, 4500);
});

test('caps deductions so net pay cannot become negative', () => {
    const result = calculate({ basicSalary: 1000, payableDays: 30, daysInMonth: 30, otherDeductions: 900, loanBalance: 5000, loanInstallment: 500 });
    assert.equal(result.loanDeduction, 100);
    assert.equal(result.netPay, 0);
    assert.ok(result.warnings.length > 0);
});

test('supports paying the complete remaining loan balance', () => {
    const result = calculate({ basicSalary: 10000, payableDays: 30, daysInMonth: 30, loanBalance: 3500, loanPaymentMode: 'FULL', loanInstallment: 500 });
    assert.equal(result.loanDeduction, 3500);
    assert.equal(result.remainingLoanBalance, 0);
    assert.equal(result.netPay, 6500);
});

test('net salary combines basic salary and commission then subtracts loan deduction', () => {
    const result = calculate({ basicSalary: 8000, payableDays: 30, daysInMonth: 30, commission: 1500, loanBalance: 5000, loanInstallment: 1000 });
    assert.equal(result.remainingLoanBalance, 4000);
    assert.equal(result.netPay, 8500);
});
