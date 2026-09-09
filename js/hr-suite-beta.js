/* exported renderHrSuiteBeta */
(() => {
    const categories = ['RECRUITMENT', 'ONBOARDING', 'LEAVE', 'PAYROLL', 'COMPLIANCE', 'OFFBOARDING'];
    const statuses = ['DRAFT', 'OPEN', 'IN_PROGRESS', 'BLOCKED', 'READY', 'COMPLETED', 'ARCHIVED'];
    const priorities = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];
    let betaChannel = null;

    const text = (en, ar) => currentLang === 'ar' ? ar : en;
    const safe = value => escapeHTML(String(value ?? ''));
    const categoryText = category => ({
        RECRUITMENT: text('Recruitment', 'التوظيف'),
        ONBOARDING: text('Onboarding', 'التهيئة الوظيفية'),
        LEAVE: text('Leave & policies', 'الإجازات والسياسات'),
        PAYROLL: text('Payroll & WPS', 'الرواتب وحماية الأجور'),
        COMPLIANCE: text('Compliance', 'الامتثال'),
        OFFBOARDING: text('Offboarding', 'إنهاء الخدمة')
    })[category] || category;
    const statusText = status => ({
        DRAFT: text('Draft', 'مسودة'), OPEN: text('Open', 'مفتوح'), IN_PROGRESS: text('In progress', 'قيد التنفيذ'),
        BLOCKED: text('Blocked', 'متعثر'), READY: text('Ready', 'جاهز'), COMPLETED: text('Completed', 'مكتمل'), ARCHIVED: text('Archived', 'مؤرشف')
    })[status] || status;

    window.canCurrentUserUseHrSuiteBeta = function () {
        const values = [currentUserRole, currentUserProfile?.role, currentUserProfile?.job_title]
            .map(value => String(value || '').trim().toUpperCase().replace(/[_-]+/g, ' '));
        return values.some(value => [
            'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'HR MANAGER',
            'FINANCE MANAGER', 'ACCOUNTANT MANAGER', 'GM', 'GENERAL MANAGER',
            'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'
        ].includes(value));
    };

    function employeeName(employee) {
        return window.formatEmployeeName?.(employee) || employee?.full_name || text('Unassigned', 'غير معين');
    }

    function optionList(selected = '') {
        return `<option value="">${text('Not assigned', 'غير معين')}</option>${(window.hrSuiteBetaEmployees || []).map(employee =>
            `<option value="${safe(employee.id)}" ${String(selected) === String(employee.id) ? 'selected' : ''}>${safe(employeeName(employee))}</option>`
        ).join('')}`;
    }

    function renderMetric(icon, value, label, tone) {
        return `<article class="hr-beta-metric ${tone}"><span><i data-lucide="${icon}"></i></span><div><strong>${value}</strong><small>${safe(label)}</small></div></article>`;
    }

    function renderEmpty(category) {
        return `<div class="hr-beta-empty"><i data-lucide="flask-conical"></i><h3>${text('No beta records yet', 'لا توجد سجلات تجريبية بعد')}</h3><p>${text('Add a test record to validate this workflow without changing production HR data.', 'أضف سجلاً تجريبياً لاختبار سير العمل دون تغيير بيانات الموارد البشرية الفعلية.')}</p><button type="button" class="btn btn-primary" onclick="openHrSuiteBetaItemModal('${category === 'ALL' ? 'RECRUITMENT' : category}')"><i data-lucide="plus"></i>${text('Add test record', 'إضافة سجل تجريبي')}</button></div>`;
    }

    function renderRows(items, employeeMap) {
        return items.map(item => {
            const due = item.due_date ? new Date(`${item.due_date}T00:00:00`).toLocaleDateString() : '—';
            const amount = item.amount == null ? '—' : new Intl.NumberFormat(currentLang === 'ar' ? 'ar-SA' : 'en-SA', { style: 'currency', currency: 'SAR', maximumFractionDigits: 2 }).format(item.amount);
            const displayTitle = currentLang === 'ar' && item.title_ar ? item.title_ar : item.title;
            return `<tr>
                <td><span class="hr-beta-category category-${safe(item.category.toLowerCase())}">${safe(categoryText(item.category))}</span></td>
                <td><strong>${safe(displayTitle)}</strong>${item.notes ? `<small class="hr-beta-row-note">${safe(item.notes)}</small>` : ''}</td>
                <td>${safe(employeeName(employeeMap[item.employee_id]))}</td>
                <td>${safe(employeeName(employeeMap[item.owner_id]))}</td>
                <td>${safe(due)}</td>
                <td>${safe(amount)}</td>
                <td><select class="hr-beta-status status-${safe(item.status.toLowerCase())}" aria-label="${text('Workflow status', 'حالة سير العمل')}" onchange="updateHrSuiteBetaStatus('${safe(item.id)}', this.value)">${statuses.map(status => `<option value="${status}" ${item.status === status ? 'selected' : ''}>${safe(statusText(status))}</option>`).join('')}</select></td>
                <td><button type="button" class="icon-btn" onclick="openHrSuiteBetaItemModal('${safe(item.category)}','${safe(item.id)}')" aria-label="${text('Edit beta record', 'تعديل السجل التجريبي')}"><i data-lucide="pencil"></i></button></td>
            </tr>`;
        }).join('');
    }

    window.renderHrSuiteBeta = async function () {
        if (!window.canCurrentUserUseHrSuiteBeta()) return `<div class="card">${text('You do not have access to this beta.', 'ليس لديك صلاحية للوصول إلى هذه النسخة التجريبية.')}</div>`;
        const [items, employees] = await Promise.all([db.fetchHrSuiteBetaItems(), db.fetchUsers()]);
        window.hrSuiteBetaItems = items || [];
        window.hrSuiteBetaEmployees = employees || [];
        const employeeMap = Object.fromEntries((employees || []).map(employee => [employee.id, employee]));
        const activeCategory = categories.includes(window.hrSuiteBetaActiveCategory) ? window.hrSuiteBetaActiveCategory : 'ALL';
        const visibleItems = activeCategory === 'ALL' ? items : items.filter(item => item.category === activeCategory);
        const open = item => !['COMPLETED', 'ARCHIVED'].includes(item.status);
        const inThirtyDays = new Date();
        inThirtyDays.setDate(inThirtyDays.getDate() + 30);
        const complianceDue = items.filter(item => item.category === 'COMPLIANCE' && open(item) && item.due_date && new Date(`${item.due_date}T23:59:59`) <= inThirtyDays).length;
        const metrics = [
            renderMetric('user-search', items.filter(item => item.category === 'RECRUITMENT' && open(item)).length, text('Open recruitment', 'طلبات توظيف مفتوحة'), 'blue'),
            renderMetric('user-check', items.filter(item => item.category === 'ONBOARDING' && open(item)).length, text('Active onboarding', 'تهيئة وظيفية نشطة'), 'green'),
            renderMetric('shield-alert', complianceDue, text('Compliance due in 30 days', 'امتثال مستحق خلال 30 يوماً'), 'amber'),
            renderMetric('landmark', items.filter(item => item.category === 'PAYROLL' && ['DRAFT', 'OPEN', 'IN_PROGRESS'].includes(item.status)).length, text('Payroll/WPS in preparation', 'رواتب وحماية أجور قيد الإعداد'), 'purple')
        ].join('');
        setTimeout(window.initializeHrSuiteBetaRealtime, 0);
        return `<section class="hr-beta-page">
            <header class="hr-beta-hero"><div><div class="hr-beta-title-line"><span class="hr-beta-icon"><i data-lucide="flask-conical"></i></span><div><span class="hr-beta-badge">BETA</span><h1>${text('HR Suite Beta', 'حزمة الموارد البشرية التجريبية')}</h1></div></div><p>${text('Safely test complete employee-lifecycle and Saudi HR compliance workflows.', 'اختبر بأمان دورة حياة الموظف الكاملة ومسارات امتثال الموارد البشرية السعودية.')}</p></div><button type="button" class="btn btn-primary" onclick="openHrSuiteBetaItemModal('${activeCategory === 'ALL' ? 'RECRUITMENT' : activeCategory}')"><i data-lucide="plus"></i>${text('Add test record', 'إضافة سجل تجريبي')}</button></header>
            <div class="hr-beta-notice"><i data-lucide="shield-check"></i><div><strong>${text('Isolated testing workspace', 'مساحة اختبار معزولة')}</strong><span>${text('Records created here do not alter live payroll, leave balances, contracts, or employee status.', 'السجلات هنا لا تغيّر الرواتب أو أرصدة الإجازات أو العقود أو حالة الموظفين الفعلية.')}</span></div></div>
            <div class="hr-beta-metrics">${metrics}</div>
            <nav class="hr-beta-tabs" aria-label="${text('Beta modules', 'الوحدات التجريبية')}"><button class="${activeCategory === 'ALL' ? 'active' : ''}" onclick="setHrSuiteBetaTab('ALL')">${text('Overview', 'نظرة عامة')}<span>${items.length}</span></button>${categories.map(category => `<button class="${activeCategory === category ? 'active' : ''}" onclick="setHrSuiteBetaTab('${category}')">${safe(categoryText(category))}<span>${items.filter(item => item.category === category).length}</span></button>`).join('')}</nav>
            <article class="card hr-beta-workspace"><div class="hr-beta-workspace-head"><div><h2>${activeCategory === 'ALL' ? text('Employee lifecycle workspace', 'مساحة دورة حياة الموظف') : safe(categoryText(activeCategory))}</h2><p>${text('Real database records with status, ownership, deadlines, amounts, and audit history.', 'سجلات فعلية تشمل الحالة والمسؤول والمواعيد والمبالغ وسجل التدقيق.')}</p></div><span class="employees-radar-live"><i data-lucide="radio"></i>${text('Live', 'مباشر')}</span></div>
                ${visibleItems.length ? `<div class="table-responsive"><table class="data-table hr-beta-table"><thead><tr><th>${text('Module', 'الوحدة')}</th><th>${text('Record', 'السجل')}</th><th>${text('Employee', 'الموظف')}</th><th>${text('Owner', 'المسؤول')}</th><th>${text('Due date', 'تاريخ الاستحقاق')}</th><th>${text('Amount', 'المبلغ')}</th><th>${text('Status', 'الحالة')}</th><th>${text('Actions', 'الإجراءات')}</th></tr></thead><tbody>${renderRows(visibleItems, employeeMap)}</tbody></table></div>` : renderEmpty(activeCategory)}
            </article>
            <div class="hr-beta-capabilities">
                <article><i data-lucide="briefcase-business"></i><h3>${text('Hire to onboard', 'من التوظيف إلى التهيئة')}</h3><p>${text('Track candidates, offers, document collection, probation, and onboarding ownership.', 'تتبّع المرشحين والعروض والمستندات وفترة التجربة ومسؤوليات التهيئة.')}</p></article>
                <article><i data-lucide="calendar-check"></i><h3>${text('Leave policy testing', 'اختبار سياسات الإجازات')}</h3><p>${text('Model policy changes and approvals before connecting them to live balances.', 'نمذجة تغييرات السياسات والموافقات قبل ربطها بالأرصدة الفعلية.')}</p></article>
                <article><i data-lucide="badge-dollar-sign"></i><h3>${text('Payroll and WPS readiness', 'جاهزية الرواتب وحماية الأجور')}</h3><p>${text('Test payroll cycles, reconciliation tasks, and compliance checkpoints.', 'اختبار دورات الرواتب ومهام المطابقة ونقاط تحقق الامتثال.')}</p></article>
                <article><i data-lucide="door-open"></i><h3>${text('Controlled offboarding', 'إنهاء خدمة منضبط')}</h3><p>${text('Coordinate notice, custody, final settlement, access removal, and certificates.', 'تنسيق الإشعار والعهدة والتسوية النهائية وإزالة الصلاحيات والشهادات.')}</p></article>
            </div>
        </section>`;
    };

    window.setHrSuiteBetaTab = function (category) {
        window.hrSuiteBetaActiveCategory = category;
        delete window.viewHTMLCache?.hr_suite_beta;
        renderView('hr_suite_beta');
    };

    window.closeHrSuiteBetaItemModal = function () {
        document.getElementById('hrSuiteBetaItemModal')?.classList.remove('show');
    };

    window.openHrSuiteBetaItemModal = function (category = 'RECRUITMENT', itemId = '') {
        if (!window.canCurrentUserUseHrSuiteBeta()) return;
        const item = (window.hrSuiteBetaItems || []).find(record => String(record.id) === String(itemId)) || {};
        let modal = document.getElementById('hrSuiteBetaItemModal');
        if (!modal) {
            modal = document.createElement('div');
            modal.id = 'hrSuiteBetaItemModal';
            modal.className = 'modal hr-beta-modal';
            modal.innerHTML = `<div class="modal-content hr-beta-modal-content"><div class="modal-header"><div><span class="hr-beta-badge">BETA</span><h3 id="hrBetaModalTitle"></h3></div><button type="button" class="icon-btn" onclick="closeHrSuiteBetaItemModal()" aria-label="Close"><i data-lucide="x"></i></button></div><form id="hrBetaItemForm" onsubmit="saveHrSuiteBetaItem(event)"><input type="hidden" id="hrBetaItemId"><div class="hr-beta-form-grid"><div class="form-group"><label class="form-label" for="hrBetaCategory">${text('Module', 'الوحدة')}</label><select id="hrBetaCategory" class="form-control" required>${categories.map(value => `<option value="${value}">${safe(categoryText(value))}</option>`).join('')}</select></div><div class="form-group"><label class="form-label" for="hrBetaStatus">${text('Status', 'الحالة')}</label><select id="hrBetaStatus" class="form-control">${statuses.map(value => `<option value="${value}">${safe(statusText(value))}</option>`).join('')}</select></div><div class="form-group"><label class="form-label" for="hrBetaTitle">${text('Title (English)', 'العنوان بالإنجليزية')}</label><input id="hrBetaTitle" class="form-control" required maxlength="180"></div><div class="form-group"><label class="form-label" for="hrBetaTitleAr">${text('Title (Arabic)', 'العنوان بالعربية')}</label><input id="hrBetaTitleAr" class="form-control" dir="rtl" maxlength="180"></div><div class="form-group"><label class="form-label" for="hrBetaEmployee">${text('Employee', 'الموظف')}</label><select id="hrBetaEmployee" class="form-control"></select></div><div class="form-group"><label class="form-label" for="hrBetaOwner">${text('Owner', 'المسؤول')}</label><select id="hrBetaOwner" class="form-control"></select></div><div class="form-group"><label class="form-label" for="hrBetaDueDate">${text('Due date', 'تاريخ الاستحقاق')}</label><input id="hrBetaDueDate" type="date" class="form-control"></div><div class="form-group"><label class="form-label" for="hrBetaPriority">${text('Priority', 'الأولوية')}</label><select id="hrBetaPriority" class="form-control">${priorities.map(value => `<option value="${value}">${value}</option>`).join('')}</select></div><div class="form-group"><label class="form-label" for="hrBetaAmount">${text('Estimated amount (SAR)', 'المبلغ التقديري (ر.س)')}</label><input id="hrBetaAmount" type="number" min="0" step="0.01" class="form-control"></div><div class="form-group hr-beta-notes-field"><label class="form-label" for="hrBetaNotes">${text('Notes', 'ملاحظات')}</label><textarea id="hrBetaNotes" class="form-control" rows="3" maxlength="2000"></textarea></div></div><div class="modal-actions"><button type="button" class="btn btn-secondary" onclick="closeHrSuiteBetaItemModal()">${text('Cancel', 'إلغاء')}</button><button type="submit" id="hrBetaSaveButton" class="btn btn-primary"><i data-lucide="save"></i><span>${text('Save test record', 'حفظ السجل التجريبي')}</span></button></div></form></div>`;
            document.body.appendChild(modal);
        }
        document.getElementById('hrBetaModalTitle').textContent = item.id ? text('Edit beta record', 'تعديل السجل التجريبي') : text('Add beta record', 'إضافة سجل تجريبي');
        document.getElementById('hrBetaItemId').value = item.id || '';
        document.getElementById('hrBetaCategory').value = item.category || category;
        document.getElementById('hrBetaStatus').value = item.status || 'DRAFT';
        document.getElementById('hrBetaTitle').value = item.title || '';
        document.getElementById('hrBetaTitleAr').value = item.title_ar || '';
        document.getElementById('hrBetaEmployee').innerHTML = optionList(item.employee_id);
        document.getElementById('hrBetaOwner').innerHTML = optionList(item.owner_id || currentUser?.id);
        document.getElementById('hrBetaDueDate').value = item.due_date || '';
        document.getElementById('hrBetaPriority').value = item.priority || 'MEDIUM';
        document.getElementById('hrBetaAmount').value = item.amount ?? '';
        document.getElementById('hrBetaNotes').value = item.notes || '';
        modal.classList.add('show');
        document.getElementById('hrBetaTitle').focus();
        window.lucide?.createIcons();
    };

    window.saveHrSuiteBetaItem = async function (event) {
        event.preventDefault();
        const button = document.getElementById('hrBetaSaveButton');
        button.disabled = true;
        const itemId = document.getElementById('hrBetaItemId').value;
        const result = await db.saveHrSuiteBetaItem({
            category: document.getElementById('hrBetaCategory').value,
            status: document.getElementById('hrBetaStatus').value,
            title: document.getElementById('hrBetaTitle').value.trim(),
            title_ar: document.getElementById('hrBetaTitleAr').value.trim(),
            employee_id: document.getElementById('hrBetaEmployee').value,
            owner_id: document.getElementById('hrBetaOwner').value,
            due_date: document.getElementById('hrBetaDueDate').value,
            priority: document.getElementById('hrBetaPriority').value,
            amount: document.getElementById('hrBetaAmount').value,
            notes: document.getElementById('hrBetaNotes').value.trim()
        }, itemId || null);
        button.disabled = false;
        if (!result.success) return showToast(result.error?.message || text('Could not save the beta record.', 'تعذر حفظ السجل التجريبي.'), 'danger');
        window.closeHrSuiteBetaItemModal();
        delete window.viewHTMLCache?.hr_suite_beta;
        showToast(text('Beta record saved.', 'تم حفظ السجل التجريبي.'), 'success');
        await renderView('hr_suite_beta');
    };

    window.updateHrSuiteBetaStatus = async function (itemId, status) {
        const result = await db.updateHrSuiteBetaItemStatus(itemId, status);
        if (!result.success) showToast(result.error?.message || text('Could not update status.', 'تعذر تحديث الحالة.'), 'danger');
        delete window.viewHTMLCache?.hr_suite_beta;
        await renderView('hr_suite_beta');
    };

    window.initializeHrSuiteBetaRealtime = function () {
        if (betaChannel && window.supabaseClient) window.supabaseClient.removeChannel(betaChannel);
        betaChannel = db.subscribeToHrSuiteBetaItems(() => {
            if (currentView !== 'hr_suite_beta') return;
            delete window.viewHTMLCache?.hr_suite_beta;
            renderView('hr_suite_beta');
        });
    };
})();
