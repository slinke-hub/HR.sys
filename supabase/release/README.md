# Simplified CRM release paths

The two environments have different database baselines. The staging-specific
forward correction is kept outside `supabase/migrations` so it cannot be
accidentally selected as a Production migration. It is an alternative to the
Production-specific workflow migration, not a prerequisite for it.

Apply neither path with a broad migration command. Select individual reviewed
files only after verifying the target, baseline, prerequisites, recovery plan,
and each file's checksum. The Production path requires the reviewed foundation
and compatibility migrations in their validated order; it does not install the
old approval migration as a prerequisite. The staging correction requires the
post-Migration-7 staging baseline. Both files fail closed on their expected
database state.
