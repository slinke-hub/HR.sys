import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import {
  Activity, BarChart3, BriefcaseBusiness, Building2, CalendarDays,
  CheckCircle2, CircleDollarSign, GripVertical, MoreHorizontal, Plus,
  Search, Target, Users
} from 'lucide-react';

const COPY = {
  en: {
    dashboard: 'Dashboard', employees: 'Employees', payroll: 'Payroll', time: 'Time & Attendance', crm: 'CRM',
    search: 'Search where in CRM', role: 'HR & Operations Manager', title: 'Client Relationship Management (CRM)',
    subtitle: 'Manage client relationships, active opportunities, and team follow-up from one workspace.',
    addClient: 'Add Client', newDeal: 'New Deal', pipeline: 'Deals Pipeline', pipelineHint: 'Drag cards to update the relationship stage.',
    lead: 'Lead', contacted: 'Contacted', proposal: 'Proposal', negotiation: 'Negotiation', won: 'Won',
    noDeals: 'No deals in this stage', tasks: 'My Assigned Tasks', interactions: 'Client Interaction Logs',
    assignments: 'Employee Assignments', analytics: 'Key Client Analytics', due: 'Due', linkedClient: 'Client',
    noTasks: 'No assigned CRM tasks', noActivity: 'No client activity yet', noAssignments: 'No assignments yet',
    acquisition: 'New Client Acquisition', revenue: 'Revenue by Client Industry', totalPipeline: 'Pipeline value',
    activeClients: 'Active clients', wonDeals: 'Won deals', openDeals: 'Open deals',
    activityLabel: 'Client activity', noAnalytics: 'No client analytics yet',
    account: 'account', accounts: 'accounts', today: 'Today', daysAgo: 'days ago', viewDeal: 'View deal', editDeal: 'Edit deal'
  },
  ar: {
    dashboard: 'لوحة القيادة', employees: 'الموظفين', payroll: 'الرواتب', time: 'الوقت والحضور', crm: 'إدارة علاقات العملاء',
    search: 'ابحث في إدارة علاقات العملاء', role: 'مدير الموارد البشرية والعمليات', title: 'إدارة علاقات العملاء',
    subtitle: 'إدارة علاقات العملاء والفرص النشطة ومتابعة الفريق من مساحة عمل واحدة.',
    addClient: 'إضافة عميل', newDeal: 'صفقة جديدة', pipeline: 'مسار الصفقات', pipelineHint: 'اسحب البطاقات لتحديث مرحلة العلاقة.',
    lead: 'إشارة', contacted: 'تم الاتصال', proposal: 'اقتراح', negotiation: 'تفاوض', won: 'فائز',
    noDeals: 'لا توجد صفقات في هذه المرحلة', tasks: 'المهام المعينة لي', interactions: 'سجلات تفاعل العملاء',
    assignments: 'تعيينات الموظفين', analytics: 'تحليلات العملاء الرئيسية', due: 'الاستحقاق', linkedClient: 'العميل',
    noTasks: 'لا توجد مهام CRM معيّنة', noActivity: 'لا يوجد نشاط للعملاء بعد', noAssignments: 'لا توجد تعيينات بعد',
    acquisition: 'اكتساب عملاء جدد', revenue: 'الإيرادات حسب قطاع العميل', totalPipeline: 'قيمة مسار الصفقات',
    activeClients: 'العملاء النشطون', wonDeals: 'الصفقات الفائزة', openDeals: 'الصفقات المفتوحة',
    activityLabel: 'نشاط العميل', noAnalytics: 'لا توجد تحليلات للعملاء بعد',
    account: 'حساب', accounts: 'حسابات', today: 'اليوم', daysAgo: 'أيام مضت', viewDeal: 'عرض الصفقة', editDeal: 'تعديل الصفقة'
  }
};

const STAGES = [
  { key: 'LEAD', dbStage: 'LEAD', label: 'lead', tone: 'tw-bg-sky-500', soft: 'tw-bg-sky-50', border: 'tw-border-sky-200' },
  { key: 'CONTACTED', dbStage: 'QUALIFICATION', label: 'contacted', tone: 'tw-bg-cyan-500', soft: 'tw-bg-cyan-50', border: 'tw-border-cyan-200' },
  { key: 'PROPOSAL', dbStage: 'PROPOSAL', label: 'proposal', tone: 'tw-bg-indigo-500', soft: 'tw-bg-indigo-50', border: 'tw-border-indigo-200' },
  { key: 'NEGOTIATION', dbStage: 'NEGOTIATION', label: 'negotiation', tone: 'tw-bg-amber-500', soft: 'tw-bg-amber-50', border: 'tw-border-amber-200' },
  { key: 'WON', dbStage: 'WON', label: 'won', tone: 'tw-bg-emerald-500', soft: 'tw-bg-emerald-50', border: 'tw-border-emerald-200' }
];

const normalizeStage = stage => ['QUALIFICATION', 'PITCH', 'CONTACTED'].includes(String(stage || '').toUpperCase())
  ? 'CONTACTED'
  : String(stage || 'LEAD').toUpperCase();
const money = value => new Intl.NumberFormat('en-SA', { maximumFractionDigits: 0 }).format(Number(value || 0));
const initials = value => String(value || 'M').trim().split(/\s+/).slice(0, 2).map(part => part[0]).join('').toUpperCase();
const dateLabel = (value, locale) => value
  ? new Intl.DateTimeFormat(locale === 'ar' ? 'ar-SA' : 'en-SA', { day: 'numeric', month: 'short' }).format(new Date(value))
  : '—';

function Avatar({ profile, size = 'tw-h-9 tw-w-9' }) {
  const name = profile?.display_name_ar || profile?.full_name || profile?.name || profile?.initials || 'M';
  if (profile?.avatar_url) return <img className={`${size} tw-rounded-full tw-object-cover tw-ring-2 tw-ring-white`} src={profile.avatar_url} alt={name} />;
  return <span className={`${size} tw-inline-flex tw-flex-none tw-items-center tw-justify-center tw-rounded-full tw-bg-gradient-to-br tw-from-blue-600 tw-to-cyan-500 tw-text-[11px] tw-font-bold tw-text-white tw-ring-2 tw-ring-white`}>{profile?.initials || initials(name)}</span>;
}

function Metric({ icon: Icon, label, value, tone }) {
  return <div className="tw-flex tw-items-center tw-gap-3 tw-rounded-2xl tw-border tw-border-slate-200 tw-bg-white tw-p-4 tw-shadow-panel">
    <span className={`tw-grid tw-h-10 tw-w-10 tw-place-items-center tw-rounded-xl ${tone}`}><Icon size={19} /></span>
    <span className="tw-grid"><small className="tw-text-[11px] tw-font-semibold tw-text-slate-500">{label}</small><strong className="tw-mt-0.5 tw-text-lg tw-font-black tw-text-slate-900">{value}</strong></span>
  </div>;
}

function DealCard({ deal, lang, canOpenDetails }) {
  const text = COPY[lang];
  const clientName = deal.clientName || deal.crm_clients?.name || deal.title || (lang === 'ar' ? 'عميل' : 'Client');
  const details = deal.details || deal.technical_description || deal.event_type || deal.title;
  const profile = deal.assignee || {};
  const openDetails = () => {
    if (canOpenDetails) window.openDealWorkflowModal?.(String(deal.id));
  };
  return <article id={`deal-card-${deal.id}`} draggable onDragStart={event => {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('dealId', String(deal.id));
    event.dataTransfer.setData('oldStage', String(deal.stage || 'LEAD'));
    window.dragDeal?.(event.nativeEvent, String(deal.id));
  }} onClick={event => {
    if (!event.target.closest('button, a, input, select, textarea')) openDetails();
  }} onKeyDown={event => {
    if (canOpenDetails && (event.key === 'Enter' || event.key === ' ')) {
      event.preventDefault();
      openDetails();
    }
  }} role={canOpenDetails ? 'button' : undefined} tabIndex={canOpenDetails ? 0 : undefined} aria-label={canOpenDetails ? `${text.viewDeal}: ${clientName}` : undefined} className={`kanban-card tw-group tw-relative tw-mb-3 tw-rounded-2xl tw-border tw-border-slate-200 tw-bg-white tw-p-4 tw-shadow-[0_4px_16px_rgba(15,23,42,.05)] tw-transition hover:-tw-translate-y-0.5 hover:tw-border-blue-200 hover:tw-shadow-float ${canOpenDetails ? 'tw-cursor-pointer focus:tw-outline-none focus:tw-ring-2 focus:tw-ring-blue-400' : ''}`} data-stage={deal.stage} data-workflow-status={deal.workflow_status || 'NOT_STARTED'}>
    <div className="tw-flex tw-items-start tw-gap-2">
      <GripVertical size={16} className="tw-mt-0.5 tw-flex-none tw-cursor-grab tw-text-slate-300 group-hover:tw-text-blue-400" />
      <div className="tw-min-w-0 tw-flex-1">
        <div className="tw-flex tw-items-start tw-justify-between tw-gap-2"><h4 className="tw-m-0 tw-line-clamp-2 tw-text-sm tw-font-extrabold tw-leading-5 tw-text-slate-900">{clientName}</h4></div>
        <p className="tw-mb-3 tw-mt-1.5 tw-line-clamp-2 tw-min-h-9 tw-text-xs tw-leading-[18px] tw-text-slate-500">{details}</p>
        <div className="tw-flex tw-items-center tw-justify-between tw-gap-2 tw-border-t tw-border-slate-100 tw-pt-3">
          <span className="tw-flex tw-items-center tw-gap-1.5 tw-text-[11px] tw-font-semibold tw-text-slate-500"><CalendarDays size={13} />{dateLabel(deal.closing_date || deal.created_at, lang)}</span>
          <Avatar profile={profile} size="tw-h-7 tw-w-7" />
        </div>
        {Number(deal.amount || 0) > 0 && <div className="tw-mt-2 tw-flex tw-items-center tw-gap-1 tw-text-[11px] tw-font-bold tw-text-emerald-700"><CircleDollarSign size={13} />SAR {money(deal.amount)}</div>}
      </div>
      <div className="tw-flex tw-flex-col tw-gap-1 tw-opacity-0 tw-transition group-hover:tw-opacity-100 focus-within:tw-opacity-100">
        <button aria-label={text.viewDeal} title={text.viewDeal} onClick={event => { event.stopPropagation(); window.showCRMDealModal?.(String(deal.id), true); }} className="tw-grid tw-h-7 tw-w-7 tw-place-items-center tw-rounded-lg tw-border-0 tw-bg-slate-50 tw-text-slate-500 hover:tw-bg-blue-50 hover:tw-text-blue-700"><Search size={13} /></button>
        <button aria-label={text.editDeal} title={text.editDeal} onClick={event => { event.stopPropagation(); window.showCRMDealModal?.(String(deal.id)); }} className="tw-grid tw-h-7 tw-w-7 tw-place-items-center tw-rounded-lg tw-border-0 tw-bg-slate-50 tw-text-slate-500 hover:tw-bg-blue-50 hover:tw-text-blue-700"><MoreHorizontal size={14} /></button>
      </div>
    </div>
  </article>;
}

function PipelineBoard({ lang, deals, onDealStageChange, canOpenDetails }) {
  const text = COPY[lang];
  const handleDrop = async (event, stage) => {
    event.preventDefault();
    const dealId = event.dataTransfer.getData('dealId');
    const deal = deals.find(item => String(item.id) === String(dealId));
    if (!deal) return;
    const oldStage = deal.stage;
    if (oldStage === stage.dbStage) return;
    const requiresApproval = ['PROPOSAL', 'NEGOTIATION', 'WON'].includes(stage.dbStage)
      && deal.workflow_status !== 'APPROVED';
    const canMoveImmediately = stage.dbStage !== 'WON' && !requiresApproval;
    if (canMoveImmediately) onDealStageChange(dealId, stage.dbStage);
    const result = await window.dropDeal?.(event.nativeEvent, stage.dbStage);
    if (canMoveImmediately && !result?.success) onDealStageChange(dealId, oldStage);
  };
  return <section className="tw-rounded-3xl tw-border tw-border-slate-200 tw-bg-white tw-p-4 tw-shadow-panel sm:tw-p-5">
    <div className="tw-mb-4 tw-flex tw-flex-wrap tw-items-end tw-justify-between tw-gap-2">
      <div><h2 className="tw-m-0 tw-flex tw-items-center tw-gap-2 tw-text-base tw-font-black tw-text-slate-900"><Target size={19} className="tw-text-blue-600" />{text.pipeline}</h2><p className="tw-mb-0 tw-mt-1 tw-text-xs tw-text-slate-500">{text.pipelineHint}</p></div>
      <span className="tw-rounded-full tw-bg-slate-100 tw-px-3 tw-py-1 tw-text-[11px] tw-font-bold tw-text-slate-600">{deals.length} {lang === 'ar' ? 'صفقة' : 'deals'}</span>
    </div>
    <div className="tw-flex tw-snap-x tw-gap-4 tw-overflow-x-auto tw-pb-2 [scrollbar-width:thin]">
      {STAGES.map(stage => {
        const stageDeals = deals.filter(deal => normalizeStage(deal.stage) === stage.key);
        return <section key={stage.key} id={`crm-col-${stage.dbStage}`} onDragOver={event => event.preventDefault()} onDrop={event => handleDrop(event, stage)} className={`kanban-col tw-min-h-[390px] tw-w-[286px] tw-flex-none tw-snap-start tw-rounded-2xl tw-border tw-p-3 ${stage.soft} ${stage.border}`}>
          <header className="tw-mb-3 tw-flex tw-items-center tw-justify-between tw-gap-2 tw-px-1"><h3 id={`crm-header-${stage.dbStage}`} className="tw-m-0 tw-flex tw-items-center tw-gap-2 tw-text-xs tw-font-black tw-uppercase tw-tracking-[.08em] tw-text-slate-700"><i className={`tw-h-2.5 tw-w-2.5 tw-rounded-full ${stage.tone}`} />{text[stage.label]}</h3><span className="tw-grid tw-h-6 tw-min-w-6 tw-place-items-center tw-rounded-full tw-bg-white tw-px-1.5 tw-text-[10px] tw-font-black tw-text-slate-600 tw-shadow-sm">{stageDeals.length}</span></header>
          <div className="tw-min-h-[320px]">{stageDeals.map(deal => <DealCard key={deal.id} deal={deal} lang={lang} canOpenDetails={canOpenDetails} />)}{!stageDeals.length && <div className="tw-grid tw-min-h-32 tw-place-items-center tw-rounded-2xl tw-border tw-border-dashed tw-border-slate-300 tw-bg-white/50 tw-p-4 tw-text-center tw-text-xs tw-text-slate-400">{text.noDeals}</div>}</div>
        </section>;
      })}
    </div>
  </section>;
}

function WidgetShell({ icon: Icon, title, children, accent = 'tw-bg-blue-50 tw-text-blue-700' }) {
  return <section className="tw-min-w-0 tw-rounded-3xl tw-border tw-border-slate-200 tw-bg-white tw-p-5 tw-shadow-panel">
    <header className="tw-mb-4 tw-flex tw-items-center tw-gap-3"><span className={`tw-grid tw-h-9 tw-w-9 tw-place-items-center tw-rounded-xl ${accent}`}><Icon size={18} /></span><h3 className="tw-m-0 tw-text-sm tw-font-black tw-text-slate-900">{title}</h3></header>{children}
  </section>;
}

function TasksWidget({ lang, tasks, deals }) {
  const text = COPY[lang];
  const rows = tasks.slice(0, 4).map(task => {
    const linked = deals.find(deal => deal.client_id && deal.client_id === (task.client_id || task.crm_client_id));
    return { ...task, clientName: linked?.clientName || linked?.crm_clients?.name || linked?.title || '—' };
  });
  return <WidgetShell icon={CheckCircle2} title={text.tasks} accent="tw-bg-emerald-50 tw-text-emerald-700"><div className="tw-grid tw-gap-2.5">{rows.length ? rows.map(task => <div key={task.id} className="tw-flex tw-items-start tw-gap-3 tw-rounded-2xl tw-border tw-border-slate-100 tw-bg-slate-50/70 tw-p-3"><button className="tw-mt-0.5 tw-h-4 tw-w-4 tw-flex-none tw-rounded-full tw-border-2 tw-border-emerald-400 tw-bg-white" aria-label={task.title} /><div className="tw-min-w-0 tw-flex-1"><strong className="tw-block tw-truncate tw-text-xs tw-text-slate-800">{task.displayTitle || task.title}</strong><span className="tw-mt-1 tw-flex tw-flex-wrap tw-gap-x-2 tw-gap-y-1 tw-text-[10px] tw-text-slate-500"><em className="tw-not-italic">{text.due}: {dateLabel(task.due_date, lang)}</em><em className="tw-not-italic">{text.linkedClient}: {task.clientName}</em></span></div></div>) : <p className="tw-m-0 tw-py-8 tw-text-center tw-text-xs tw-text-slate-400">{text.noTasks}</p>}</div></WidgetShell>;
}

function ActivityWidget({ lang, activity }) {
  const text = COPY[lang];
  const rows = activity.slice(0, 4);
  return <WidgetShell icon={Activity} title={text.interactions} accent="tw-bg-violet-50 tw-text-violet-700"><div className="tw-relative tw-grid tw-gap-0 before:tw-absolute before:tw-bottom-3 before:tw-start-[7px] before:tw-top-3 before:tw-w-px before:tw-bg-slate-200">{rows.length ? rows.map((item, index) => <div key={item.id || index} className="tw-relative tw-grid tw-grid-cols-[16px_minmax(0,1fr)] tw-gap-3 tw-pb-4 last:tw-pb-0"><i className="tw-relative tw-z-10 tw-mt-1 tw-h-3.5 tw-w-3.5 tw-rounded-full tw-border-[3px] tw-border-white tw-bg-violet-500 tw-ring-1 tw-ring-violet-200" /><div className="tw-min-w-0"><span className="tw-flex tw-items-center tw-justify-between tw-gap-2"><strong className="tw-truncate tw-text-xs tw-text-slate-800">{String(item.action || text.activityLabel).replaceAll('_', ' ')}</strong><small className="tw-flex-none tw-text-[9px] tw-text-slate-400">{dateLabel(item.created_at, lang)}</small></span><p className="tw-mb-0 tw-mt-1 tw-text-[10px] tw-leading-4 tw-text-slate-500">{item.profiles?.full_name || item.profiles?.display_name_ar || (lang === 'ar' ? 'فريق مُقام' : 'Mogam team')} · {item.client || item.crm_deals?.crm_clients?.name || item.crm_deals?.title || 'CRM'}</p></div></div>) : <p className="tw-m-0 tw-py-8 tw-text-center tw-text-xs tw-text-slate-400">{text.noActivity}</p>}</div></WidgetShell>;
}

function AssignmentsWidget({ lang, deals, users }) {
  const text = COPY[lang];
  const byUser = useMemo(() => {
    const groups = new Map();
    deals.filter(deal => deal.assigned_to || deal.assignee).forEach(deal => {
      const key = String(deal.assigned_to || deal.assignee?.id || deal.assignee?.initials || 'team');
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(deal);
    });
    return [...groups.entries()].slice(0, 6).map(([id, assignedDeals]) => ({ profile: users.find(user => String(user.id) === id) || assignedDeals[0].assignee || { full_name: lang === 'ar' ? 'فريق مُقام' : 'Mogam team' }, deals: assignedDeals }));
  }, [deals, users, lang]);
  return <WidgetShell icon={Users} title={text.assignments} accent="tw-bg-cyan-50 tw-text-cyan-700"><div className="tw-grid tw-grid-cols-2 tw-gap-2.5">{byUser.length ? byUser.map((item, index) => <div key={item.profile.id || index} className="tw-rounded-2xl tw-border tw-border-slate-100 tw-bg-slate-50/70 tw-p-3 tw-text-center"><Avatar profile={item.profile} size="tw-mx-auto tw-h-10 tw-w-10" /><strong className="tw-mt-2 tw-block tw-truncate tw-text-[11px] tw-text-slate-800">{(lang === 'ar' && item.profile.display_name_ar) || item.profile.full_name || item.profile.initials}</strong><small className="tw-mt-1 tw-block tw-text-[9px] tw-font-semibold tw-text-cyan-700">{item.deals.length} {item.deals.length === 1 ? text.account : text.accounts}</small></div>) : <p className="tw-col-span-2 tw-m-0 tw-py-8 tw-text-center tw-text-xs tw-text-slate-400">{text.noAssignments}</p>}</div></WidgetShell>;
}

function AnalyticsWidget({ lang, deals, clients }) {
  const text = COPY[lang];
  const months = Array.from({ length: 6 }, (_, index) => {
    const date = new Date();
    date.setDate(1);
    date.setMonth(date.getMonth() - (5 - index));
    return { key: `${date.getFullYear()}-${date.getMonth()}`, label: new Intl.DateTimeFormat(lang === 'ar' ? 'ar-SA' : 'en', { month: 'short' }).format(date), count: 0 };
  });
  const monthByKey = new Map(months.map(month => [month.key, month]));
  clients.forEach(client => {
    const createdAt = new Date(client.created_at);
    const month = monthByKey.get(`${createdAt.getFullYear()}-${createdAt.getMonth()}`);
    if (!Number.isNaN(createdAt.getTime()) && month) month.count += 1;
  });
  const maxMonthCount = Math.max(0, ...months.map(month => month.count));
  const clientById = new Map(clients.map(client => [String(client.id), client]));
  const industryRevenue = deals.reduce((result, deal) => {
    const client = clientById.get(String(deal.client_id));
    const key = String(client?.industry || '').trim();
    const amount = Number(deal.amount || 0);
    if (key && amount > 0) result[key] = (result[key] || 0) + amount;
    return result;
  }, {});
  const industries = Object.entries(industryRevenue).sort((a, b) => b[1] - a[1]).slice(0, 3);
  const industryTotal = industries.reduce((sum, [, count]) => sum + count, 0);
  let cursor = 0;
  const colors = ['#2563eb', '#10b981', '#f59e0b'];
  const segments = industries.map(([, count], index) => {
    const start = cursor;
    cursor += industryTotal ? (count / industryTotal) * 100 : 0;
    return `${colors[index]} ${start}% ${cursor}%`;
  });
  const doughnutBackground = segments.length ? `conic-gradient(${segments.join(', ')})` : 'var(--color-bg-base)';
  return <WidgetShell icon={BarChart3} title={text.analytics} accent="tw-bg-amber-50 tw-text-amber-700"><div className="tw-grid tw-grid-cols-2 tw-gap-4"><div className="tw-min-w-0"><p className="tw-m-0 tw-text-[10px] tw-font-bold tw-text-slate-500">{text.acquisition}</p><div className="tw-mt-4 tw-flex tw-h-24 tw-items-end tw-gap-1.5">{months.map(month => <span key={month.key} title={`${month.label}: ${month.count}`} className="tw-flex-1 tw-rounded-t-md tw-bg-gradient-to-t tw-from-blue-600 tw-to-cyan-400" style={{ height: maxMonthCount ? `${Math.max(8, (month.count / maxMonthCount) * 100)}%` : '0%' }} />)}</div><div className="tw-mt-2 tw-flex tw-justify-between tw-text-[8px] tw-text-slate-400"><span>{months[0].label}</span><span>{months[5].label}</span></div></div><div className="tw-min-w-0"><p className="tw-m-0 tw-text-[10px] tw-font-bold tw-text-slate-500">{text.revenue}</p>{industries.length ? <><div className="tw-mx-auto tw-mt-3 tw-h-20 tw-w-20 tw-rounded-full" style={{ background: doughnutBackground }}><div className="tw-relative tw-left-1/2 tw-top-1/2 tw-h-11 tw-w-11 -tw-translate-x-1/2 -tw-translate-y-1/2 tw-rounded-full tw-bg-white" /></div><div className="tw-mt-3 tw-grid tw-gap-1">{industries.map(([label, amount], index) => <span key={label} className="tw-flex tw-items-center tw-gap-1.5 tw-text-[8px] tw-text-slate-500"><i className={`tw-h-2 tw-w-2 tw-rounded-full ${['tw-bg-blue-600', 'tw-bg-emerald-500', 'tw-bg-amber-500'][index]}`} />{label} · SAR {money(amount)}</span>)}</div></> : <p className="tw-m-0 tw-py-10 tw-text-center tw-text-[10px] tw-text-slate-400">{text.noAnalytics}</p>}</div></div></WidgetShell>;
}

function CrmDashboard({ payload = {} }) {
  const lang = payload.lang === 'en' ? 'en' : 'ar';
  const text = COPY[lang];
  const [query, setQuery] = useState('');
  const accessValues = [payload.role, payload.profile?.role, payload.profile?.job_title]
    .map(value => String(value || '').trim().toUpperCase().replace(/[_-]+/g, ' '));
  const canOpenDetails = accessValues.some(value => ['ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'MANAGER'].includes(value) || /\bMANAGER\b/.test(value));
  const sourceDeals = useMemo(() => (payload.deals || []).map(deal => ({
    ...deal,
    clientName: deal.crm_clients?.name,
    assignee: payload.users?.find(user => user.id === deal.assigned_to)
  })), [payload.deals, payload.users]);
  const [deals, setDeals] = useState(sourceDeals);
  useEffect(() => setDeals(sourceDeals), [sourceDeals]);
  const handleDealStageChange = (dealId, stage) => {
    setDeals(previous => previous.map(deal => String(deal.id) === String(dealId) ? { ...deal, stage } : deal));
  };
  const filteredDeals = useMemo(() => {
    const value = query.trim().toLocaleLowerCase(lang === 'ar' ? 'ar' : 'en');
    if (!value) return deals;
    return deals.filter(deal => [deal.title, deal.clientName, deal.crm_clients?.name, deal.details, deal.technical_description, deal.event_type].filter(Boolean).join(' ').toLocaleLowerCase(lang === 'ar' ? 'ar' : 'en').includes(value));
  }, [deals, query, lang]);
  const openDeals = deals.filter(deal => !['WON', 'LOST'].includes(normalizeStage(deal.stage)));
  const wonDeals = deals.filter(deal => normalizeStage(deal.stage) === 'WON');
  const pipelineValue = openDeals.reduce((sum, deal) => sum + Number(deal.amount || 0), 0);
  return <div dir={lang === 'ar' ? 'rtl' : 'ltr'} lang={lang} className="mogam-crm-react tw-min-w-0 tw-w-full tw-bg-transparent tw-font-sans tw-text-ink">
        <div className="tw-mx-auto tw-w-full tw-max-w-[1800px]">
          <section className="page-header tw-flex-wrap tw-gap-4"><div className="tw-max-w-3xl"><span className="tw-mb-2 tw-inline-flex tw-items-center tw-gap-1.5 tw-rounded-full tw-bg-blue-50 tw-px-3 tw-py-1 tw-text-[10px] tw-font-black tw-uppercase tw-tracking-[.12em] tw-text-blue-700"><BriefcaseBusiness size={13} />Mogam CRM</span><h1 className="page-title tw-m-0">{text.title}</h1><p className="page-subtitle tw-mb-0 tw-mt-2">{text.subtitle}</p></div><div className="tw-flex tw-w-full tw-flex-wrap tw-items-center tw-justify-end tw-gap-3 sm:tw-w-auto"><label className="search-container crm-dashboard-search tw-m-0 tw-min-w-0 tw-flex-1 sm:tw-w-72 sm:tw-flex-none"><Search size={18} className="search-icon tw-m-0 tw-flex-none" /><input value={query} onChange={event => setQuery(event.target.value)} placeholder={text.search} className="search-input" /></label><button type="button" data-crm-new-deal onClick={() => window.showCRMDealModal?.()} className="btn btn-primary tw-inline-flex tw-min-h-10 tw-items-center tw-justify-center tw-gap-2"><Plus size={17} />{text.newDeal}</button><button type="button" onClick={() => window.showCRMClientModal?.()} className="btn btn-secondary tw-inline-flex tw-min-h-10 tw-items-center tw-justify-center tw-gap-2"><Building2 size={17} />{text.addClient}</button></div></section>
          <section className="tw-mb-5 tw-grid tw-grid-cols-1 tw-gap-3 sm:tw-grid-cols-2 xl:tw-grid-cols-4"><Metric icon={CircleDollarSign} label={text.totalPipeline} value={`SAR ${money(pipelineValue)}`} tone="tw-bg-blue-50 tw-text-blue-700" /><Metric icon={Building2} label={text.activeClients} value={payload.clients?.length || new Set(deals.map(deal => deal.clientName)).size} tone="tw-bg-cyan-50 tw-text-cyan-700" /><Metric icon={Target} label={text.openDeals} value={openDeals.length} tone="tw-bg-amber-50 tw-text-amber-700" /><Metric icon={CheckCircle2} label={text.wonDeals} value={wonDeals.length} tone="tw-bg-emerald-50 tw-text-emerald-700" /></section>
          <PipelineBoard lang={lang} deals={filteredDeals} onDealStageChange={handleDealStageChange} canOpenDetails={canOpenDetails} />
          <section className="tw-mt-5 tw-grid tw-grid-cols-1 tw-gap-4 md:tw-grid-cols-2 2xl:tw-grid-cols-4"><TasksWidget lang={lang} tasks={payload.tasks || []} deals={deals} /><ActivityWidget lang={lang} activity={payload.activity || []} /><AssignmentsWidget lang={lang} deals={deals} users={payload.users || []} /><AnalyticsWidget lang={lang} deals={deals} clients={payload.clients || []} /></section>
        </div>
  </div>;
}

let activeRoot = null;
let activeElement = null;

export function mount(element, payload) {
  if (!element) return;
  if (activeRoot && activeElement !== element) activeRoot.unmount();
  if (!activeRoot || activeElement !== element) {
    activeRoot = createRoot(element);
    activeElement = element;
  }
  activeRoot.render(<CrmDashboard payload={payload} />);
}

export function unmount() {
  if (activeRoot) activeRoot.unmount();
  activeRoot = null;
  activeElement = null;
}
