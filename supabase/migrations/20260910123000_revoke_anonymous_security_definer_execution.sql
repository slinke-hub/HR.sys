-- Prevent anonymous callers from invoking privileged public-schema functions.
-- PostgreSQL grants EXECUTE to PUBLIC by default for newly created functions.
-- Triggers continue to work after EXECUTE is revoked from client roles.
BEGIN;

DO $hardening$
DECLARE
    function_record record;
BEGIN
    FOR function_record IN
        SELECT procedure.oid::regprocedure AS signature
        FROM pg_proc AS procedure
        JOIN pg_namespace AS namespace ON namespace.oid = procedure.pronamespace
        WHERE namespace.nspname = 'public'
          AND procedure.prosecdef
    LOOP
        EXECUTE format(
            'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon',
            function_record.signature
        );
        EXECUTE format(
            'GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role',
            function_record.signature
        );
    END LOOP;
END
$hardening$;

COMMIT;
