BEGIN;

ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS marketing_department TEXT,
    ADD COLUMN IF NOT EXISTS content_links TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS submission_links TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS delivery_status TEXT;

ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_marketing_department_check;
ALTER TABLE public.tasks ADD CONSTRAINT tasks_marketing_department_check
    CHECK (marketing_department IS NULL OR marketing_department IN ('Muqamsa', 'Muqam.party', 'Coffee Corner'));

ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_delivery_status_check;
ALTER TABLE public.tasks ADD CONSTRAINT tasks_delivery_status_check
    CHECK (delivery_status IS NULL OR delivery_status IN ('Approved', 'Edit needed'));

CREATE OR REPLACE FUNCTION public.is_marketing_department_manager(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.departments department
        WHERE department.name = 'Marketing'
          AND department.head_id = p_user_id
    );
$$;

CREATE OR REPLACE FUNCTION public.enforce_marketing_design_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE is_designing BOOLEAN;
BEGIN
    is_designing := NEW.department = 'Marketing' AND NEW.sub_type = 'Designing Task';
    IF NOT is_designing THEN RETURN NEW; END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.delivery_status IS NOT NULL AND NOT public.is_marketing_department_manager(auth.uid()) THEN
            RAISE EXCEPTION 'Only the Marketing department manager can set Delivery Status' USING ERRCODE = '42501';
        END IF;
        NEW.status := CASE WHEN NEW.delivery_status = 'Approved' THEN 'completed' ELSE 'review' END;
        RETURN NEW;
    END IF;

    IF NEW.delivery_status IS DISTINCT FROM OLD.delivery_status
       AND NOT public.is_marketing_department_manager(auth.uid()) THEN
        RAISE EXCEPTION 'Only the Marketing department manager can change Delivery Status' USING ERRCODE = '42501';
    END IF;

    IF NEW.delivery_status IS DISTINCT FROM OLD.delivery_status THEN
        NEW.status := CASE WHEN NEW.delivery_status = 'Approved' THEN 'completed' ELSE 'review' END;
    ELSIF NEW.status = 'completed' AND COALESCE(NEW.delivery_status, '') <> 'Approved' THEN
        NEW.status := 'review';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_marketing_design_review_trigger ON public.tasks;
CREATE TRIGGER enforce_marketing_design_review_trigger
    BEFORE INSERT OR UPDATE ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION public.enforce_marketing_design_review();

REVOKE ALL ON FUNCTION public.is_marketing_department_manager(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_marketing_department_manager(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
