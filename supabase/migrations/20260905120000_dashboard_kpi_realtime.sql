-- Publish the four KPI source tables through Supabase Realtime. The checks keep
-- this migration safe on projects where one or more tables are already live.
do $$
declare
    source_table text;
begin
    foreach source_table in array array['profiles', 'attendance', 'tasks', 'requests']
    loop
        if not exists (
            select 1
            from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public'
              and tablename = source_table
        ) then
            execute format('alter publication supabase_realtime add table public.%I', source_table);
        end if;
    end loop;
end
$$;
