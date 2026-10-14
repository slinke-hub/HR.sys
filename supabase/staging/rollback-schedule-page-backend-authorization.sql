-- MANUAL STAGING ROLLBACK ONLY.
--
-- Required dispatcher order:
--   1. Pause every push-notification-dispatcher invocation.
--   2. Apply this rollback with the approved staging migration role.
--   3. Deploy the dispatcher version from immediately before the Schedule
--      authorization change.
--   4. Verify reminder ownership isolation, then resume dispatch invocations.
--
-- Do not deploy the previous dispatcher before pausing invocations: that
-- version reads reminders with the service role and does not enforce the
-- Schedule grant. This rollback intentionally changes no reminder or
-- permission records and touches no unrelated database objects.

BEGIN;

DROP POLICY IF EXISTS "Users can view their reminders" ON public.reminders;
CREATE POLICY "Users can view their reminders"
    ON public.reminders FOR SELECT TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can create their reminders" ON public.reminders;
CREATE POLICY "Users can create their reminders"
    ON public.reminders FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their reminders" ON public.reminders;
CREATE POLICY "Users can update their reminders"
    ON public.reminders FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete their reminders" ON public.reminders;
CREATE POLICY "Users can delete their reminders"
    ON public.reminders FOR DELETE TO authenticated
    USING (user_id = auth.uid());

-- Policies no longer depend on has_my_page_access. Remove the dispatcher list
-- and authenticated wrapper before their shared internal evaluator.
DROP FUNCTION IF EXISTS public.list_due_schedule_reminders_for_dispatch(integer);
DROP FUNCTION IF EXISTS public.has_my_page_access(text);
DROP FUNCTION IF EXISTS public.has_effective_page_access_internal(uuid, text);

COMMIT;
