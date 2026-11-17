const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const puppeteer = require('puppeteer-core');
const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const start = app.indexOf('function canContinueDealQuoteProposal(');
const end = app.indexOf('\nfunction renderDealWorkflowContents(', start);
assert(start >= 0 && end > start);
(async () => {
  const browser = await puppeteer.launch({headless:true, executablePath:process.env.PUPPETEER_EXECUTABLE_PATH});
  try {
    const page = await browser.newPage();
    const button = html.match(/<button id="dealQuoteProposalContinue"[^>]*>.*?<\/button>/)[0];
    await page.setContent(`<!doctype html><html><head></head><body>${button}</body></html>`);
    for (const name of ['variables.css','layout.css','components.css']) await page.addStyleTag({path:path.join(root,'css',name)});
    await page.evaluate(code => { window.canonicalDealLifecycleStage = x => x; window.eval(code); }, app.slice(start,end));
    const hidden = await page.$eval('#dealQuoteProposalContinue', el => getComputedStyle(el).display);
    assert.equal(hidden,'none','A hidden action must not be displayed');
    const available = await page.evaluate(() => canContinueDealQuoteProposal({deal:{stage:'DISCUSSION',created_by:'sales'},canUseCrm:true},{},{id:'sales'},{is_active:true}));
    assert.equal(available,true);
    await page.$eval('#dealQuoteProposalContinue', el => {el.hidden = false;});
    assert.notEqual(await page.$eval('#dealQuoteProposalContinue', el => getComputedStyle(el).display),'none');
    console.log('DISCUSSION_ACTION_BROWSER=PASS');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
