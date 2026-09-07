-- Publish CRM client and deal changes so the analytics widget updates for
-- every connected CRM viewer without a page reload.
BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'crm_clients'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.crm_clients;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'crm_deals'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.crm_deals;
    END IF;
END;
$$;

COMMIT;
