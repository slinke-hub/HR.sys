-- Ensure the approved department-head titles exist.
BEGIN;

WITH manager_titles(department_name,title_name) AS (VALUES
('Executive & Administrative','General Manager'),
('Event Production & Operations','Event Manager'),
('Marketing & Sales','Marketing Manager'),
('IT & Technical Support','IT Administrator')
)
INSERT INTO public.job_titles(department_id,name,is_active)
SELECT department.id,manager_titles.title_name,TRUE
FROM manager_titles JOIN public.departments department ON lower(department.name)=lower(manager_titles.department_name)
ON CONFLICT(department_id,name) DO UPDATE SET is_active=TRUE;

CREATE OR REPLACE FUNCTION public.sync_department_head_from_manager_title()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE department_name TEXT;
BEGIN
    IF NEW.department_id IS NULL OR NEW.job_title IS NULL THEN RETURN NEW; END IF;
    SELECT name INTO department_name FROM public.departments WHERE id=NEW.department_id;
    IF (department_name='Executive & Administrative' AND NEW.job_title='General Manager') OR
       (department_name='Event Production & Operations' AND NEW.job_title IN ('Event Manager','Operations Manager')) OR
       (department_name='Marketing & Sales' AND NEW.job_title='Marketing Manager') OR
       (department_name='IT & Technical Support' AND NEW.job_title='IT Administrator') THEN
        UPDATE public.departments SET head_id=NEW.id WHERE id=NEW.department_id;
    END IF;
    RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS sync_department_head_from_manager_title_trigger ON public.profiles;
CREATE TRIGGER sync_department_head_from_manager_title_trigger
AFTER INSERT OR UPDATE OF job_title,department_id ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.sync_department_head_from_manager_title();

NOTIFY pgrst,'reload schema';
COMMIT;
