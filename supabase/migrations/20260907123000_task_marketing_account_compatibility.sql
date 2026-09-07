BEGIN;

-- The current UI labels the two legacy marketing accounts as Main and Party.
-- Keep the stored legacy identifiers valid and temporarily accept the labels
-- sent by older cached clients so task creation is not interrupted during rollout.
ALTER TABLE public.tasks
    DROP CONSTRAINT IF EXISTS tasks_marketing_department_check;

ALTER TABLE public.tasks
    ADD CONSTRAINT tasks_marketing_department_check
    CHECK (
        marketing_department IS NULL
        OR marketing_department IN (
            'Muqamsa',
            'Muqam.party',
            'Coffee Corner',
            'Main',
            'Party'
        )
    );

NOTIFY pgrst, 'reload schema';

COMMIT;
