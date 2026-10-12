const assert = require('node:assert/strict');
const { isAllowedSecureLoginOrigin } = require('../supabase/functions/_shared/secure-login-origin.mjs');

const stableBranchOrigin = 'https://hr-sys-git-s3-staging-auth-preview-montis-projects-b7e2f4fe.vercel.app';
const deploymentSpecificOrigin = 'https://hr-h87k87whw-montis-projects-b7e2f4fe.vercel.app';

assert.equal(isAllowedSecureLoginOrigin(stableBranchOrigin, stableBranchOrigin), true,
  'the exact stable URL for the dedicated HR.sys staging branch is allowed');
assert.equal(isAllowedSecureLoginOrigin(deploymentSpecificOrigin, stableBranchOrigin), false,
  'a deployment-specific hash URL is not substituted for the stable branch URL');
assert.equal(isAllowedSecureLoginOrigin('https://hr-sys-git-another-branch-montis-projects-b7e2f4fe.vercel.app', stableBranchOrigin), false,
  'other HR.sys Preview branches remain denied');
assert.equal(isAllowedSecureLoginOrigin('https://other-project-git-s3-staging-auth-preview-montis-projects-b7e2f4fe.vercel.app', stableBranchOrigin), false,
  'other Vercel projects remain denied');
assert.equal(isAllowedSecureLoginOrigin('https://hr-sys-git-s3-staging-auth-preview-other-team.vercel.app', stableBranchOrigin), false,
  'other Vercel teams remain denied');
assert.equal(isAllowedSecureLoginOrigin('https://sys.muqam.net', stableBranchOrigin), true,
  'the exact production application origin remains allowed');
assert.equal(isAllowedSecureLoginOrigin('http://localhost:4173', stableBranchOrigin), true,
  'the existing local development policy remains allowed');
assert.equal(isAllowedSecureLoginOrigin('capacitor://localhost', stableBranchOrigin), true,
  'the existing Capacitor policy remains allowed');

console.log('Secure-login stable Preview-origin checks passed.');
