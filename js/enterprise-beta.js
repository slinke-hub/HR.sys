// Enterprise Beta Features UI Placeholders

function renderEnterpriseBetaPlaceholder(moduleName, icon, description) {
    const isAr = window.currentLang === 'ar';
    return `
    <section class="page" style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 70vh; text-align: center; padding: 2rem;">
        <i data-lucide="${icon}" style="width: 64px; height: 64px; color: var(--color-primary); margin-bottom: 1.5rem; opacity: 0.8;"></i>
        <h1 style="font-size: 2rem; margin-bottom: 1rem; color: var(--color-text);">${moduleName} <span class="nav-beta-badge" style="vertical-align: middle; margin-left: 10px;">BETA</span></h1>
        <p style="font-size: 1.1rem; color: var(--color-text-secondary); max-width: 600px; line-height: 1.6; margin-bottom: 2rem;">
            ${description}
        </p>
        <div class="card" style="max-width: 500px; text-align: ${isAr ? 'right' : 'left'};">
            <h3 style="margin-bottom: 1rem; border-bottom: 1px solid var(--color-border); padding-bottom: 0.5rem;">Database Schema Ready</h3>
            <p style="color: var(--color-text-secondary); font-size: 0.95rem;">
                The underlying database schema for this module has been successfully migrated. We are currently building out the frontend data visualization and interaction layers.
            </p>
        </div>
    </section>
    `;
}

window.renderAtsBeta = () => renderEnterpriseBetaPlaceholder(
    'Recruitment & ATS', 
    'users', 
    'Manage job postings, applicant pipelines, and interview scheduling all in one place. Streamline your hiring process from open role to final offer.'
);

window.renderLmsBeta = () => renderEnterpriseBetaPlaceholder(
    'Training & LMS', 
    'graduation-cap', 
    'Assign mandatory training, track course completions, and help your employees grow with internal learning resources.'
);

window.renderAppraisalsBeta = () => renderEnterpriseBetaPlaceholder(
    'Performance & Appraisals', 
    'target', 
    'Conduct 360-degree reviews, track employee OKRs, and manage continuous feedback loops.'
);

window.renderSurveysBeta = () => renderEnterpriseBetaPlaceholder(
    'Employee Surveys', 
    'bar-chart-3', 
    'Gauge company culture and employee satisfaction with anonymous pulse surveys and peer-to-peer recognitions.'
);

window.renderShiftsBeta = () => renderEnterpriseBetaPlaceholder(
    'Shift Planner', 
    'calendar-days', 
    'Visually manage employee shifts, handle shift-swap requests, and optimize your team coverage.'
);

window.renderExpensesBeta = () => renderEnterpriseBetaPlaceholder(
    'Expense Management', 
    'receipt', 
    'Allow employees to upload receipts and submit expense claims for manager and finance approval.'
);
