const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const puppeteer = require('puppeteer');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const foundation = read('css/theme-foundation.css');
const components = read('css/components.css');
const css = [...html.matchAll(/<link\s+rel="stylesheet"\s+href="([^"]+)"/g)]
  .map(([, href]) => href.split('?')[0])
  .filter((href) => href.startsWith('css/'))
  .map(read)
  .join('\n');

const controls = `
  <main>
    <input id="text" type="text" value="Readable value">
    <input id="email" type="email" value="name@example.com">
    <input id="password" type="password" value="secret">
    <input id="number" type="number" value="42">
    <input id="date" type="date" value="2026-10-08">
    <input id="time" type="time" value="11:00">
    <input id="search" type="search" placeholder="Search employees">
    <select id="select"><option>Qualification</option></select>
    <textarea id="textarea">Notes</textarea>
    <input id="disabled" type="text" value="Unavailable" disabled>
    <input id="readonly" type="text" value="Reference" readonly>
    <section class="modal"><div class="modal-content"><input id="modal-input" class="form-control" value="Dialog value"></div></section>
  </main>`;

function markup(theme) {
  return `<!doctype html><html data-theme="${theme}"><head><meta charset="utf-8"><style>body{margin:0;padding:24px}${css}</style></head><body>${controls}</body></html>`;
}

async function snapshot(page) {
  return page.evaluate(() => {
    const normalize = (value) => {
      const hex = value.trim();
      const expanded = hex.length === 4
        ? `#${hex.slice(1).split('').map((part) => part + part).join('')}`
        : hex;
      const channels = expanded.match(/[a-f\d]{2}/gi)?.map((part) => parseInt(part, 16));
      return channels?.length === 3 ? `rgb(${channels.join(', ')})` : value.trim();
    };
    const rootStyle = getComputedStyle(document.documentElement);
    const tokens = Object.fromEntries([
      '--input-bg', '--input-text', '--input-placeholder', '--input-border-focus',
      '--disabled-surface', '--disabled-text', '--bg-subtle', '--text-secondary',
    ].map((token) => [token, normalize(rootStyle.getPropertyValue(token).trim())]));
    const readControl = (id) => {
      const node = document.getElementById(id);
      const style = getComputedStyle(node);
      return {
        background: style.backgroundColor,
        color: style.color,
        fill: style.webkitTextFillColor,
        border: style.borderTopColor,
        colorScheme: style.colorScheme,
        opacity: Number(style.opacity),
      };
    };
    return {
      tokens,
      controls: Object.fromEntries([
        'text', 'email', 'password', 'number', 'date', 'time', 'search',
        'select', 'textarea', 'disabled', 'readonly', 'modal-input',
      ].map((id) => [id, readControl(id)])),
      placeholder: getComputedStyle(document.getElementById('search'), '::placeholder').color,
    };
  });
}

function channels(color) {
  return (color.match(/[\d.]+/g) || []).slice(0, 3).map(Number);
}

function luminance(color) {
  return channels(color).map((channel) => {
    const value = channel / 255;
    return value <= .03928 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
  }).reduce((sum, value, index) => sum + value * [.2126, .7152, .0722][index], 0);
}

function contrast(foreground, background) {
  const a = luminance(foreground);
  const b = luminance(background);
  return (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
}

function assertTheme(state, theme) {
  const editable = ['text', 'email', 'password', 'number', 'date', 'time', 'search', 'select', 'textarea', 'modal-input'];
  for (const id of editable) {
    const control = state.controls[id];
    assert.equal(control.background, state.tokens['--input-bg'], `${theme} ${id} uses the semantic input surface`);
    assert.equal(control.color, state.tokens['--input-text'], `${theme} ${id} uses readable semantic text`);
    assert.equal(control.fill, state.tokens['--input-text'], `${theme} ${id} preserves WebKit text fill`);
    assert.equal(control.colorScheme, theme, `${theme} ${id} exposes the correct native-control color scheme`);
    assert.ok(contrast(control.color, control.background) >= 4.5, `${theme} ${id} text meets WCAG AA contrast`);
  }
  assert.equal(state.placeholder, state.tokens['--input-placeholder'], `${theme} placeholder uses the secondary token`);
  assert.notEqual(state.placeholder, state.tokens['--input-text'], `${theme} placeholder remains visually secondary`);
  assert.equal(state.controls.disabled.background, state.tokens['--disabled-surface'], `${theme} disabled surface is consistent`);
  assert.equal(state.controls.disabled.color, state.tokens['--disabled-text'], `${theme} disabled text is consistent`);
  assert.ok(state.controls.disabled.opacity < 1, `${theme} disabled state remains visibly inactive`);
  assert.equal(state.controls.readonly.background, state.tokens['--bg-subtle'], `${theme} read-only surface is distinct`);
  assert.equal(state.controls.readonly.color, state.tokens['--text-secondary'], `${theme} read-only text remains readable`);
}

assert.doesNotMatch(components, /\[data-theme="dark"\][\s\S]{0,500}background-color:\s*var\(--text-primary\)\s*!important/,
  'Legacy dark inputs must not pair a light text token with a field background');
assert.match(foundation, /input:-webkit-autofill[\s\S]*?-webkit-text-fill-color:\s*var\(--input-text\)\s*!important[\s\S]*?var\(--input-bg\) inset\s*!important/,
  'Autofill must use semantic input text and surface tokens');
assert.match(foundation, /input\[type="number"\]::\-webkit-inner-spin-button/,
  'Number controls retain a themed native spinner treatment');
assert.match(foundation, /input\[type="date"\][\s\S]*?::-webkit-calendar-picker-indicator/,
  'Date and time controls retain a themed native picker treatment');

(async () => {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    for (const theme of ['light', 'dark']) {
      for (const width of [1440, 390]) {
        await page.setViewport({ width, height: 900 });
        await page.setContent(markup(theme));
        assertTheme(await snapshot(page), theme);

        await page.focus('#text');
        await new Promise((resolve) => setTimeout(resolve, 400));
        const focused = await page.$eval('#text', (node) => {
          const style = getComputedStyle(node);
          return {
            background: style.backgroundColor,
            color: style.color,
            fill: style.webkitTextFillColor,
            border: style.borderTopColor,
            shadow: style.boxShadow,
          };
        });
        const state = await snapshot(page);
        assert.equal(focused.background, state.tokens['--input-bg'], `${theme} focused input keeps the correct surface at ${width}px`);
        assert.equal(focused.color, state.tokens['--input-text'], `${theme} focused input keeps readable text at ${width}px`);
        assert.equal(focused.fill, state.tokens['--input-text'], `${theme} focused input keeps readable WebKit text at ${width}px`);
        assert.equal(focused.border, state.tokens['--input-border-focus'], `${theme} focused input uses the focus border at ${width}px`);
        assert.notEqual(focused.shadow, 'none', `${theme} focused input keeps a visible focus indicator at ${width}px`);
      }
    }
    console.log('Shared input theme rendered states: PASS');
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
