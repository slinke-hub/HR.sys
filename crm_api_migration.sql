-- CRM Clients Table
CREATE TABLE IF NOT EXISTS public.crm_clients (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    company TEXT,
    status TEXT DEFAULT 'ACTIVE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    assigned_to UUID REFERENCES public.profiles(id)
);

ALTER TABLE public.crm_clients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view clients" ON public.crm_clients;
DROP POLICY IF EXISTS "Users can insert clients" ON public.crm_clients;
DROP POLICY IF EXISTS "Users can update clients" ON public.crm_clients;
DROP POLICY IF EXISTS "Users can delete clients" ON public.crm_clients;

CREATE POLICY "Users can view clients" ON public.crm_clients FOR SELECT USING (true);
CREATE POLICY "Users can insert clients" ON public.crm_clients FOR INSERT WITH CHECK (true);
CREATE POLICY "Users can update clients" ON public.crm_clients FOR UPDATE USING (true);
CREATE POLICY "Users can delete clients" ON public.crm_clients FOR DELETE USING (true);

-- CRM Deals Table
CREATE TABLE IF NOT EXISTS public.crm_deals (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    client_id UUID REFERENCES public.crm_clients(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    amount DECIMAL(12,2) DEFAULT 0.00,
    stage TEXT DEFAULT 'LEAD', -- LEAD, PITCH, NEGOTIATION, WON, LOST
    closing_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    assigned_to UUID REFERENCES public.profiles(id)
);

ALTER TABLE public.crm_deals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view deals" ON public.crm_deals;
DROP POLICY IF EXISTS "Users can insert deals" ON public.crm_deals;
DROP POLICY IF EXISTS "Users can update deals" ON public.crm_deals;
DROP POLICY IF EXISTS "Users can delete deals" ON public.crm_deals;

CREATE POLICY "Users can view deals" ON public.crm_deals FOR SELECT USING (true);
CREATE POLICY "Users can insert deals" ON public.crm_deals FOR INSERT WITH CHECK (true);
CREATE POLICY "Users can update deals" ON public.crm_deals FOR UPDATE USING (true);
CREATE POLICY "Users can delete deals" ON public.crm_deals FOR DELETE USING (true);

-- API Webhooks (For Integrations)
CREATE TABLE IF NOT EXISTS public.webhooks (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    url TEXT NOT NULL,
    event_type TEXT NOT NULL, -- e.g., 'deal_won', 'new_client', 'new_employee'
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.webhooks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view webhooks" ON public.webhooks;
DROP POLICY IF EXISTS "Admins can insert webhooks" ON public.webhooks;
DROP POLICY IF EXISTS "Admins can update webhooks" ON public.webhooks;
DROP POLICY IF EXISTS "Admins can delete webhooks" ON public.webhooks;

CREATE POLICY "Admins can view webhooks" ON public.webhooks FOR SELECT USING (true);
CREATE POLICY "Admins can insert webhooks" ON public.webhooks FOR INSERT WITH CHECK (true);
CREATE POLICY "Admins can update webhooks" ON public.webhooks FOR UPDATE USING (true);
CREATE POLICY "Admins can delete webhooks" ON public.webhooks FOR DELETE USING (true);
