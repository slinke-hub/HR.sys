/* eslint-env node */
const assert = require('node:assert/strict');
const path = require('node:path');
const puppeteer = require('puppeteer-core');
const executablePath = process.env.PUPPETEER_EXECUTABLE_PATH;
assert.ok(executablePath, 'Set PUPPETEER_EXECUTABLE_PATH to an installed browser.');

(async () => {
  const browser = await puppeteer.launch({ headless: true, executablePath, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    await page.setContent('<!doctype html><html><body><div id="root"></div></body></html>');
    await page.addScriptTag({ path: path.join(__dirname, '..', 'js', 'crm-dashboard.bundle.js') });
    const deal = { id:'synthetic-deal', title:'Synthetic historical', stage:'PITCH', crm_clients:{name:'Synthetic historical'} };
    for (const lang of ['en','ar']) {
      await page.evaluate(({lang,deal}) => window.MogamCrmDashboard.mount(document.getElementById('root'), {
        lang, role:'Employee', canInteractCrm:true, users:[], clients:[], activity:[], tasks:[], deals:[deal], profile:{}
      }), {lang,deal});
      await page.waitForSelector('#crmDealPipelineBoard');
      const text = await page.$eval('#crmDealPipelineBoard', el => el.innerText);
      for (const value of (lang === 'en' ? ['Lead','Qualification','Discussion','Negotiation','Won','Lost','Historical presentation'] : ['التأهيل','المناقشة','التفاوض','مكتسبة','مفقودة','العروض السابقة']))
        assert.ok(text.toLocaleLowerCase().includes(value.toLocaleLowerCase()), `Missing ${lang} label: ${value}`);
      assert.equal(await page.$$eval('#crm-col-DISCUSSION', els => els.length), 1);
      assert.equal(await page.$$eval('#crm-col-NEGOTIATION', els => els.length), 1);
      assert.equal(await page.$$eval('#crm-col-PITCH [data-crm-stage-cards] article', els => els.length), 1);
      assert.equal(await page.$eval('#crmDealPipelineBoard', el => el.closest('[dir]').getAttribute('dir')), lang === 'ar' ? 'rtl' : 'ltr');
    }
    console.log('SIMPLIFIED_BOARD_EN_AR_HISTORICAL=PASS');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
