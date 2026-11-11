/* eslint-env node */
const assert = require('node:assert/strict');
const path = require('node:path');
const puppeteer = require('puppeteer-core');

const root = path.join(__dirname, '..');
const bundle = path.join(root, 'js', 'crm-dashboard.bundle.js');
const executablePath = process.env.PUPPETEER_EXECUTABLE_PATH;
assert.ok(executablePath, 'Set PUPPETEER_EXECUTABLE_PATH to the installed Edge executable.');

(async () => {
  const browser = await puppeteer.launch({ headless: true, executablePath, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    await page.setContent('<!doctype html><html><body><div id="root"></div></body></html>');
    await page.addScriptTag({ path: bundle });
    const payload = {
      lang: 'en', role: 'Manager', canInteractCrm: true,
      users: [
        { id: 'employee-1', full_name: 'Synthetic Assignee One' },
        { id: 'employee-2', full_name: 'Synthetic Assignee Two' }
      ],
      deals: [{
        id: 'synthetic-deal-1', title: 'Synthetic Contact Discussion Deal', stage: 'QUALIFICATION',
        assigned_to: 'employee-1', assignee_ids: ['employee-1', 'employee-2'],
        crm_clients: { name: 'Synthetic Client' }
      }],
      clients: [], activity: [], tasks: [], profile: { full_name: 'Synthetic CRM Reviewer' }
    };
    await page.evaluate(data => window.MogamCrmDashboard.mount(document.getElementById('root'), data), payload);
    await page.waitForSelector('#crmDealPipelineBoard');
    const english = await page.$eval('#crmDealPipelineBoard', element => element.innerText);
    assert.match(english, /Synthetic Assignee One/);
    assert.match(english, /Synthetic Assignee Two/);

    await page.evaluate(() => window.MogamCrmDashboard.mount(document.getElementById('root'), {
      lang: 'ar', role: 'Manager', canInteractCrm: true,
      users: [
        { id: 'employee-1', full_name: 'Synthetic Assignee One', display_name_ar: 'الموظف التجريبي الأول' },
        { id: 'employee-2', full_name: 'Synthetic Assignee Two', display_name_ar: 'الموظف التجريبي الثاني' }
      ],
      deals: [{ id: 'synthetic-deal-1', title: 'صفقة تجريبية', stage: 'QUALIFICATION', assigned_to: 'employee-1', assignee_ids: ['employee-1', 'employee-2'] }],
      clients: [], activity: [], tasks: [], profile: { full_name: 'Synthetic CRM Reviewer' }
    }));
    const arabic = await page.$eval('#crmDealPipelineBoard', element => element.innerText);
    assert.match(arabic, /الموظف التجريبي الأول/);
    assert.match(arabic, /الموظف التجريبي الثاني/);
    assert.equal(await page.$eval('#crmDealPipelineBoard', element => element.closest('[dir]')?.getAttribute('dir')), 'rtl');
    console.log('CRM multi-assignee cards rendered correctly in Edge for English LTR and Arabic RTL.');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
