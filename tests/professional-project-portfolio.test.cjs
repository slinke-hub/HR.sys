const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260909120000_professional_project_portfolio.sql'), 'utf8');

assert.match(app, /PROJECT PORTFOLIO MANAGER/);
assert.match(app, /projectPortfolioFilters/);
assert.match(app, /project-kpi-grid/);
assert.match(app, /project-portfolio-grid/);
assert.match(app, /openProjectDetail/);
assert.match(app, /addProjectMilestone/);
assert.match(app, /addProjectRisk/);
assert.match(app, /addProjectUpdate/);
assert.match(app, /startProjectPortfolioRealtime/);
assert.match(app, /table: 'project_updates'/);
assert.doesNotMatch(app.slice(app.indexOf('window.handleCreateProject'), app.indexOf('window.handleDeleteProject')), /createTask|Initial task/);

assert.equal((html.match(/id="projectModal"/g) || []).length, 1, 'New Project modal must be unique');
assert.equal((html.match(/id="editProjectModal"/g) || []).length, 1, 'Edit Project modal must be unique');
assert.match(html, /id="projectDetailModal"/);
assert.doesNotMatch(html, /newProjectTasks|Initial Tasks/);
assert.match(html, /pm_separation_note/);

assert.match(db, /async createProject\(projectData\)/);
assert.match(db, /async updateProjectPortfolioItems/);
assert.match(db, /async fetchProjectUpdates/);
assert.match(db, /async createProjectUpdate/);
assert.equal((db.match(/async createProject\(projectData\)/g) || []).length, 1, 'Project DB methods must not be duplicated');

for (const column of ['project_manager_id', 'lifecycle_status', 'health_status', 'progress_percent', 'budget_amount', 'actual_cost', 'milestones', 'risks']) {
  assert.ok(migration.includes(column), `Missing project portfolio column: ${column}`);
}
assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.project_updates/);
assert.match(migration, /CREATE POLICY project_portfolio_select/);
assert.match(migration, /CREATE POLICY project_updates_insert/);
assert.match(migration, /ALTER PUBLICATION supabase_realtime ADD TABLE public\.project_updates/);
assert.match(css, /Professional project portfolio/);
assert.match(css, /\.project-card-meta \{ direction:ltr; \}/);
assert.match(css, /@media \(max-width:430px\)/);
assert.match(css, /container-type:inline-size/);
assert.match(css, /max-width:min\(1080px,calc\(100vw - 2rem\)\)/);
assert.match(css, /@container \(max-width:560px\)/);
assert.match(css, /\.project-inline-form>\* \{ min-width:0; max-width:100%; \}/);
assert.match(html, /css\/components\.css\?v=2026091016/);

console.log('Professional project portfolio is independent, responsive, governed, and activity-aware.');
