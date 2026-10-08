const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const app = read('js/app.js');
const layout = read('css/layout.css');
const variables = read('css/variables.css');
const serviceWorker = read('sw.js');

assert.match(html, /id="appNavigationToggle"[^>]+onclick="window\.openMobileNavigation\(this\)"[^>]+aria-controls="appNavigationDrawerOverlay"/, 'Header hamburger controls the dedicated shared drawer and supplies its focus-restoration target');
assert.ok(html.indexOf('id="appNavigationToggle"') < html.indexOf('class="header-logo"'), 'Hamburger is adjacent before the logo in the leading header group');
assert.doesNotMatch(html, /<nav class="header-navigation"/, 'The duplicated horizontal module row is removed');
assert.match(html, /id="mobileMoreNav"[^>]+onclick="window\.openMobileNavigation\(this\)"/, 'Mobile More opens the same drawer and supplies its focus-restoration target');
assert.match(html, /js\/app\.js\?v=2026100801/, 'Application script cache key remains current');
assert.match(html, /css\/layout\.css\?v=2026100801/, 'Header and login layout changes receive a fresh stylesheet cache key');
assert.match(html, /css\/components\.css\?v=2026100801/, 'The late component header override retains its current stylesheet cache key');

assert.match(app, /window\.openMobileNavigation\s*=\s*async function/, 'One shared permission-filtered drawer opener exists');
assert.match(app, /\.sidebar-nav > \.nav-item\[data-view\]/, 'Drawer entries come from the existing permission-managed navigation source');
assert.match(app, /item\.style\.display !== 'none' && !item\.hidden/, 'Existing hidden-navigation rules remain respected');
assert.match(app, /canCurrentUserAccessView\(item\.dataset\.view\)/, 'Each candidate is checked with existing route access rules');
assert.match(app, /class="app-navigation-drawer" role="dialog" aria-modal="true" aria-labelledby="navigation-drawer-title"/, 'Dedicated drawer is modal and labelled accessibly');
assert.match(app, /class="navigation-drawer-backdrop" data-drawer-close/, 'Backdrop has the shared close affordance');
assert.match(app, /event\.target\.closest\('\[data-drawer-close\]'\)/, 'Backdrop and close button both close the drawer');
assert.match(app, /event\.key === 'Escape'/, 'Escape closes the drawer');
assert.match(app, /event\.key !== 'Tab'/, 'Drawer traps keyboard focus');
assert.match(app, /app\.inert = true/, 'Background interaction is disabled while drawer is open');
assert.match(app, /app\.inert = false/, 'Background interaction is restored when drawer closes');
assert.match(app, /window\.navigationDrawerOpener = activeOpener/, 'Opening control is retained for focus restoration');
assert.match(app, /opener\.focus\(\)/, 'Focus returns to the hamburger/More opener');
assert.match(app, /window\.closeMobileNavigation\(\{ restoreFocus: false \}\)/, 'Successful route navigation closes without stealing focus');
assert.match(app, /item\.getAttribute\('data-view'\)[\s\S]*?if \(!destination\) return/, 'Non-route More control cannot trigger a dashboard navigation');
assert.match(app, /localized\('Workspace', 'مساحة العمل'\)/, 'Workspace group labels are localized English/Arabic');
assert.match(app, /localized\('People & HR', 'الأفراد والموارد البشرية'\)/, 'People group labels are localized English/Arabic');
assert.match(app, /localized\('Business', 'الأعمال'\)/, 'Business group labels are localized English/Arabic');
assert.match(app, /filter\(group => group\.items\.length\)/, 'Empty navigation groups are omitted');
assert.match(app, /views: new Set\(\['dashboard', 'my-day', 'tasks', 'projects'/, 'Projects remains in Workspace navigation');
assert.match(app, /key: 'people-hr',[^\n]*views: new Set\(\['time', 'requests'/, 'People & HR contains time and requests without misplacing Contracts');
assert.match(app, /key: 'business',[^\n]*views: new Set\(\['employees', 'clients', 'crm', 'documents', 'approvals'/, 'Contracts route is grouped with business destinations');
assert.match(app, /navigation-drawer-brand-logo-light[\s\S]*navigation-drawer-brand-logo-dark/, 'Drawer header includes the approved light/dark brand assets');
assert.match(app, /navigation-drawer-item\$\{active \? ' active' : ''\}/, 'Current route receives selected styling');
assert.match(app, /const active = currentView === item\.dataset\.view/, 'Active route is calculated from the current view');
assert.doesNotMatch(app.slice(app.indexOf('window.openMobileNavigation ='), app.indexOf('window.updateNavigationControlLabels')), /mobile-navigation-sheet|mobile-navigation-panel|mobile-navigation-grid/, 'Active drawer path no longer creates the legacy More sheet');
assert.match(app, /hasParentRoute = viewId !== 'login' && hasHierarchicalProjectRoute/, 'Back is shown only for a hierarchical Project detail route, not root-level view history');
assert.match(app, /sw\.js\?v=2026100801/, 'Service worker registration forces an update check');
assert.match(serviceWorker, /muqam-hr-mobile-v255/, 'New service-worker cache retires stale shell/app bundles');

assert.match(layout, /\.app-navigation-drawer\s*\{[\s\S]*?position: fixed;[\s\S]*?top: 0;[\s\S]*?bottom: 0;[\s\S]*?inset-inline-start: auto;[\s\S]*?inset-inline-end: 0;[\s\S]*?width: 320px;[\s\S]*?height: 100dvh;[\s\S]*?border-start-start-radius: 24px;[\s\S]*?border-end-start-radius: 24px;[\s\S]*?transform: translateX\(calc\(100% \+ 1px\)\)/, 'Drawer attaches to header brand/hamburger inline-end with matching LTR entry direction');
assert.match(layout, /@media \(max-width: 767px\)[\s\S]*?\.app-navigation-drawer \{ width: min\(86vw, 340px\); \}/, 'Mobile drawer uses the specified viewport-relative width');
assert.match(layout, /html\[dir="rtl"\] \.app-navigation-drawer\s*\{\s*transform: translateX\(calc\(-100% - 1px\)\);\s*\}/, 'RTL drawer enters from the left edge, matching the header hamburger');
assert.match(layout, /\.navigation-drawer-item\s*\{[\s\S]*?display: flex;[\s\S]*?min-height: 46px/, 'Drawer navigation is a vertical row list, not a tile grid');
assert.match(layout, /\.navigation-drawer-brand img[\s\S]*?max-height: 36px/, 'Drawer brand mark has compact, bounded sizing');
assert.match(layout, /\.header-logo \.app-logo \{ max-height: 52px/, 'Desktop logo size is visibly increased without setting a fixed width');
assert.match(layout, /\.header-logo \.app-logo \{ max-height: 44px/, 'Mobile logo remains within the approved visual size');
assert.match(layout, /\.header-logo \.app-logo \{[^}]*width: auto;[^}]*max-width:/, 'Logo keeps its native aspect ratio and is not cropped');
assert.match(layout, /\.app-navigation-drawer-overlay\s*\{[\s\S]*?position: fixed;[\s\S]*?inset: 0;/, 'Dedicated drawer overlay spans the viewport');
assert.match(layout, /\.app-navigation-drawer-overlay\.is-open \.app-navigation-drawer \{ transform: translateX\(0\); \}/, 'Open drawer settles without an opposite-edge flash');
assert.match(layout, /backdrop-filter: blur\(18px\) saturate\(130%\)/, 'Drawer uses restrained glassmorphism');
assert.match(layout, /background: var\(--nav-bg\)[\s\S]*?@supports[\s\S]*?background: var\(--nav-drawer-glass\)/, 'Solid semantic fallback is provided without backdrop-filter');
assert.match(variables, /--nav-drawer-glass:\s*rgba\(255, 255, 255, 0\.9\)/, 'Light theme has a translucent elevated drawer surface');
assert.match(variables, /--nav-drawer-glass:\s*rgba\(21, 31, 42, 0\.92\)/, 'Dark theme has a separate navy translucent drawer surface');
assert.match(layout, /prefers-reduced-motion: reduce/, 'Motion respects reduced-motion preference');
assert.match(layout, /\.sidebar-nav > \.nav-item\[data-view="dashboard"\][\s\S]*?#mobileMoreNav\s*\{\s*display: flex !important;/, 'Existing mobile bottom-nav destinations remain preserved');
assert.match(layout, /\.navigation-drawer-item\.active::before[\s\S]*?inset-inline-start/, 'Selected state uses a semantic logical-edge indicator');
assert.match(layout, /navigation-drawer-item\.active > svg[\s\S]*?var\(--brand-primary\)/, 'Selected route icon uses the brand accent');

const components = read('css/components.css');
assert.match(components, /@media \(min-width: 901px\)[\s\S]*?\.topbar\s*\{\s*display: flex !important;\s*justify-content: space-between;/,
  'Late component styles preserve the two-group flex header instead of restoring a centered grid');
assert.doesNotMatch(components, /\.topbar\s*\{[^}]*display:\s*grid\s*!important;/,
  'No later important three-column grid can recenter header groups');

console.log('Stage D.1 navigation drawer checks passed.');
