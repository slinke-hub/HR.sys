const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const data = fs.readFileSync(path.join(root, 'js', 'data.js'), 'utf8');

const contractStart = app.indexOf('async function renderContractPage()');
const contractEnd = app.indexOf('\nasync function renderEmployeesDirectory', contractStart);
assert.ok(contractStart >= 0 && contractEnd > contractStart, 'Employee contract form was not found');
const contract = app.slice(contractStart, contractEnd);

const nationalityIndex = contract.indexOf('id="contractNationality"');
const identityIndex = contract.indexOf('id="contractIdentityNumber"');
assert.ok(nationalityIndex >= 0 && identityIndex > nationalityIndex, 'Nationality must appear before the identity number');
assert.match(contract, /<select id="contractNationality" class="form-control" required>/);
assert.doesNotMatch(contract, /id="contractNationality"[^>]*disabled/);
assert.match(contract, /<option value="Saudi"/);
assert.match(contract, /<option value="Non-Saudi"/);
assert.match(contract, /contract_identity_number'\) \|\| 'Iqama\/ National ID Number'/);

assert.match(contract, /type="url" inputmode="url" autocomplete="url" id="contractWorkplace"/);
assert.match(contract, /https:\/\/maps\.app\.goo\.gl\/\.\.\./);
assert.match(app, /window\.isGoogleMapsLocationLink = function/);
assert.match(app, /host === 'maps\.app\.goo\.gl'/);
assert.match(app, /workplaceInput\?\.reportValidity\(\)/);

assert.match(data, /contract_identity_number: "Iqama\/ National ID Number"/);
assert.match(data, /contract_nationality_saudi: "Saudi"/);
assert.match(data, /contract_nationality_non_saudi: "Non-Saudi"/);
assert.match(data, /contract_google_maps_invalid: "Enter a valid Google Maps location link\."/);

console.log('Contract nationality, identity, and Google Maps location fields are configured.');
