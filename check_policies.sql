-- Let's check policies on contracts table
SELECT pol.polname, pol.polcmd, pol.polpermissive,
       pg_get_expr(pol.polqual, pol.polrelid) AS using_expr,
       pg_get_expr(pol.polwithcheck, pol.polrelid) AS with_check_expr
FROM pg_policy pol
JOIN pg_class cls ON pol.polrelid = cls.oid
WHERE cls.relname = 'contracts';
