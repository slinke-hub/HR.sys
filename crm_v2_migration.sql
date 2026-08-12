-- Add new fields to crm_deals
ALTER TABLE public.crm_deals
ADD COLUMN IF NOT EXISTS event_type TEXT,
ADD COLUMN IF NOT EXISTS first_contact_date DATE,
ADD COLUMN IF NOT EXISTS contact_method TEXT,
ADD COLUMN IF NOT EXISTS lead_source TEXT;

-- Create crm_orders table
CREATE TABLE IF NOT EXISTS public.crm_orders (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    deal_id UUID REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    start_date DATE,
    end_date DATE,
    event_location TEXT,
    invoice_amount DECIMAL(12,2) DEFAULT 0.00,
    project_status TEXT DEFAULT 'Not Confirmed',
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS
ALTER TABLE public.crm_orders ENABLE ROW LEVEL SECURITY;

-- Policies for crm_orders
DROP POLICY IF EXISTS "Users can view orders" ON public.crm_orders;
DROP POLICY IF EXISTS "Users can insert orders" ON public.crm_orders;
DROP POLICY IF EXISTS "Users can update orders" ON public.crm_orders;
DROP POLICY IF EXISTS "Users can delete orders" ON public.crm_orders;

CREATE POLICY "Users can view orders" ON public.crm_orders FOR SELECT USING (true);
CREATE POLICY "Users can insert orders" ON public.crm_orders FOR INSERT WITH CHECK (true);
CREATE POLICY "Users can update orders" ON public.crm_orders FOR UPDATE USING (true);
CREATE POLICY "Users can delete orders" ON public.crm_orders FOR DELETE USING (true);
