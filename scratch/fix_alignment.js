const fs = require('fs');
let css = fs.readFileSync('css/components.css', 'utf8');

// The specific selector is: .teamwork-task-detail .task-details-grid
// We want to change `padding: 1rem 0 1.5rem;` to `padding: 1rem 1.5rem 1.5rem;`
css = css.replace(
  /\.teamwork-task-detail \.task-details-grid \{\s*display: grid;\s*grid-template-columns: repeat\(2, minmax\(0, 1fr\)\);\s*gap: 1\.05rem 3rem;\s*padding: 1rem 0 1\.5rem;/g,
  '.teamwork-task-detail .task-details-grid {\n  display: grid;\n  grid-template-columns: repeat(2, minmax(0, 1fr));\n  gap: 1.05rem 3rem;\n  padding: 1rem 1.5rem 1.5rem;'
);

fs.writeFileSync('css/components.css', css);
console.log('Fixed padding');
