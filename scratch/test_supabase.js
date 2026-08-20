const url = 'https://bbbetcdioiaozdjkvwxu.supabase.co/rest/v1/contracts';
const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJiYmV0Y2Rpb2lhb3pkamt2d3h1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMTM0NjQsImV4cCI6MjEwMTU4OTQ2NH0.GhV7HsGnAXA8Zb_IV3hxhwI9qmbM3qhcuWRMSXKUNcw';

fetch(url, {
    method: 'POST',
    headers: {
        'apikey': key,
        'Authorization': `Bearer ${key}`,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal'
    },
    body: JSON.stringify({
        employee_id: "00000000-0000-0000-0000-000000000000",
        contract_type: "Full-time",
        nationality: "Saudi",
        job_title: "Test",
        job_title_en: "Test",
        start_date: "2023-01-01",
        end_date: "2024-01-01",
        salary: 1000,
        housing_allowance: 100,
        transportation_allowance: 100,
        other_allowances: 100,
        working_hours: "8",
        probation_period_days: 90,
        notice_period_days: 30,
        annual_leave_days: 30,
        status: "Active"
    })
}).then(r => r.json()).then(data => console.log(data)).catch(console.error);
