/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const expected = [
    [1, 'Mohamed Hassan Abkar'],
    [2, 'Abdullah Hassan Abkar'],
    [3, 'Hussain Ahmed Bhhari'],
    [4, 'Hassan Hussain Hassan'],
    [5, 'Jamal Yousuf'],
    [6, 'Montasir Jafar Ahmed Eltayeb'],
    [7, 'Ghassan Ahmed Bhhari'],
    [8, 'InesMadani'],
    [9, 'Mohamed Afefi'],
    [10, 'Arif Almiri'],
    [11, 'Mohamed Omer'],
    [12, 'Aseil Muneer Saeed'],
    [13, 'Bilal Ahmad Ghous'],
    [14, 'Adel Saad Abdullah Alqardhi'],
    [15, 'Abdulhadi Ahmed'],
    [16, 'Omar Mohamed Makhimer'],
    [17, 'Hanouf Omer'],
    [18, 'Ibrahim Saeed'],
    [19, 'Um Ibrahim'],
    [20, 'Boshra Mohamed Simsim eya'],
    [21, 'Arwah'],
    [22, 'Rayaan Baheis'],
    [23, 'Abdulfatah Mohamed Karawan'],
    [24, 'Abdullah Alselme']
];

const rootMigration = fs.readFileSync(path.join(__dirname, '..', 'employee_directory_ids_migration.sql'), 'utf8');
const trackedMigration = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20260905123000_employee_directory_id_reassignment.sql'), 'utf8');
assert.equal(trackedMigration, rootMigration);

const valuesBlock = rootMigration.match(/INSERT INTO requested_employee_ids[\s\S]*?VALUES([\s\S]*?);/);
assert.ok(valuesBlock, 'Expected employee ID values block');
const actual = [...valuesBlock[1].matchAll(/\((\d+),\s*'([^']+)'\)/g)].map(match => [Number(match[1]), match[2]]);
assert.deepEqual(actual, expected);
assert.equal(new Set(actual.map(([, name]) => name.toLowerCase())).size, 24);

console.log('Employee Directory ID mapping tests passed.');
