const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const puppeteer = require('puppeteer');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const cssFiles = [
  'css/variables.css',
  'css/layout.css',
  'css/components.css',
  'css/theme-foundation.css',
  'css/component-semantic-migration.css',
  'css/ui-02-structural-layout.css',
  'css/cyber-obsidian-theme.css',
];
const styles = cssFiles.map(file => fs.readFileSync(path.join(root, file), 'utf8')).join('\n');

const dashboardStart = app.indexOf('async function renderDashboard() {');
const dashboardEnd = app.indexOf('let employeesRadarChannel = null;', dashboardStart);
assert.ok(dashboardStart >= 0 && dashboardEnd > dashboardStart, 'Dashboard renderer remains available');
const dashboard = app.slice(dashboardStart, dashboardEnd);

const orderedSections = [
  'ui02-dashboard-snapshot-section',
  'ui02-dashboard-announcements',
  'ui02-dashboard-kpi-section',
  'ui02-dashboard-operating-section',
  'ui02-dashboard-news',
  'ui02-dashboard-team-section',
  'ui02-dashboard-top-grid',
];
let previousIndex = -1;
for (const section of orderedSections) {
  const index = dashboard.indexOf(section, previousIndex + 1);
  assert.ok(index > previousIndex, `${section} appears in the requested order`);
  previousIndex = index;
}

assert.match(app, /setInterval\(\(\) => showSlide\(activeIndex \+ 1\), 10000\)/, 'News advances every ten seconds');
assert.match(app, /addEventListener\('pointerenter', stopDashboardNewsCarousel\)/, 'News pauses while hovered');
assert.match(app, /addEventListener\('focusin', stopDashboardNewsCarousel\)/, 'News pauses while keyboard-focused');
assert.match(app, /prefers-reduced-motion:\s*reduce/, 'Reduced-motion preference is respected');
assert.match(dashboard, /data-news-previous[\s\S]*data-news-next/, 'News includes manual previous and next controls');
assert.match(app, /<details class="card col-span-12 ui02-team-hierarchy" open>/, 'Team hierarchy starts expanded and can collapse through native details');
assert.match(app, /<summary class="ui02-team-summary">/, 'Team hierarchy has a summary control');
assert.match(dashboard, /ui02-expiry-card[\s\S]*ui02-quick-actions/, 'Document and quick-action tools remain in the dashboard');
assert.match(dashboard, /ui02-operating-overview/, 'Task work-focus tools remain in the dashboard');

const fixture = direction => `<!doctype html><html lang="${direction === 'rtl' ? 'ar' : 'en'}" dir="${direction}" data-theme="dark"><head><meta charset="utf-8"><style>${styles}</style></head><body><main id="viewContainer">
  <div class="ui02-dashboard-shell"><div class="ui02-dashboard-primary">
    <section class="ui02-dashboard-section ui02-dashboard-snapshot-section"><div class="ui02-command-grid"><article class="card ui02-command-card">Attendance</article><article class="card ui02-command-card">Announcements</article><article class="card ui02-command-card">Requests</article></div></section>
    <section class="card ui02-dashboard-announcements">Announcements panel</section>
    <section class="ui02-dashboard-section ui02-dashboard-kpi-section"><div class="ui02-kpi-announcement-grid ui02-dashboard-kpi-updates"><div class="ui02-dashboard-kpi-slot"><section class="card">KPI</section></div><section class="card ui02-activity-panel">Recent updates</section></div></section>
    <section class="ui02-dashboard-section ui02-dashboard-operating-section"><div class="ui02-operating-grid"><div class="ui02-dashboard-operating-slot"><section class="card">Operating picture</section></div><div class="ui02-dashboard-operating-slot"><section class="card ui02-last-login-card">Last login</section></div></div></section>
    <section class="card ui02-news-panel ui02-dashboard-news"><div class="ui02-news-carousel"><article class="ui02-news-slide">News item</article></div></section>
    <section class="ui02-dashboard-team-section"><div class="ui02-team-widgets"><details class="card ui02-team-hierarchy" open><summary class="ui02-team-summary">Team hierarchy</summary><div>Team content</div></details></div></section>
  </div></div>
</main></body></html>`;

(async () => {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    for (const width of [1440, 1024, 768, 430]) {
      for (const direction of ['ltr', 'rtl']) {
        await page.setViewport({ width, height: 900 });
        await page.setContent(fixture(direction));
        const result = await page.evaluate(() => {
          const primary = document.querySelector('.ui02-dashboard-primary');
          const announcements = document.querySelector('.ui02-dashboard-announcements');
          const news = document.querySelector('.ui02-dashboard-news');
          const pair = document.querySelector('.ui02-dashboard-kpi-updates');
          const operating = document.querySelector('.ui02-operating-grid');
          const metrics = document.querySelector('.ui02-dashboard-snapshot-section .ui02-command-grid');
          const primaryRect = primary.getBoundingClientRect();
          return {
            width: innerWidth,
            scrollWidth: document.documentElement.scrollWidth,
            primaryWidth: primaryRect.width,
            announcementsWidth: announcements.getBoundingClientRect().width,
            newsWidth: news.getBoundingClientRect().width,
            pairColumns: getComputedStyle(pair).gridTemplateColumns.split(' ').length,
            operatingColumns: getComputedStyle(operating).gridTemplateColumns.split(' ').length,
            metricsColumns: getComputedStyle(metrics).gridTemplateColumns.split(' ').length,
            hierarchyOpen: document.querySelector('.ui02-team-hierarchy').open,
          };
        });
        assert.equal(result.scrollWidth, width, `${direction}/${width}: no horizontal overflow`);
        assert.ok(Math.abs(result.primaryWidth - result.announcementsWidth) < 1, `${direction}/${width}: announcements use full dashboard width`);
        assert.ok(Math.abs(result.primaryWidth - result.newsWidth) < 1, `${direction}/${width}: News Hub uses full dashboard width`);
        assert.equal(result.pairColumns, width > 760 ? 2 : 1, `${direction}/${width}: KPI and updates adapt responsively`);
        assert.equal(result.operatingColumns, width > 1180 ? 2 : 1, `${direction}/${width}: operating widgets adapt responsively`);
        assert.equal(result.metricsColumns, width > 760 ? 3 : 2, `${direction}/${width}: attendance metrics use the full row`);
        assert.equal(result.hierarchyOpen, true, `${direction}/${width}: team hierarchy starts expanded`);
      }
    }
    console.log('Dashboard requested layout passed browser geometry checks at desktop, tablet, and mobile widths in LTR and RTL.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
