const fs = require('fs');
let css = fs.readFileSync('css/components.css', 'utf8');
css = css.replace(/--color-surface-hover/g, '--color-bg-elevated');
css = css.replace(/--color-surface/g, '--color-bg-surface');
fs.writeFileSync('css/components.css', css);
console.log('Fixed CSS');
