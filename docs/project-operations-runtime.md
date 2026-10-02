# Project Operations runtime configuration

The application does not infer an environment from the linked Supabase project. Select the local runtime explicitly; missing or unknown modes fail closed.

## Local staging

Keep the staging public anon/publishable key in the ignored local file `supabase/.env.staging.local` as `MUQAM_SUPABASE_ANON_KEY=<staging-public-key>`, or supply it in the current PowerShell process as `HR_SYS_STAGING_ANON_KEY`. Do not use a service-role key or commit the local file.

```powershell
$env:HR_SYS_RUNTIME = 'staging'
npm run dev
```

Open `http://127.0.0.1:4173`. The local server validates the key's project reference and anon role and emits a staging-bound database client; it does not fall back to production.

## Local production-mode verification

Production mode is an explicit local opt-in and uses the production public browser configuration embedded in the production source bundle:

```powershell
$env:HR_SYS_RUNTIME = 'production'
npm run dev
```

Use production mode only for non-mutating local verification when authorized. Clear the process setting when finished:

```powershell
Remove-Item Env:HR_SYS_RUNTIME -ErrorAction SilentlyContinue
```

The dedicated Preview and Production build scripts bind each generated database bundle to exactly one project. Preview requires a valid staging public anon key; Production requires the validated production public anon key. Neither build accepts the other environment's runtime configuration.

## Phase 1 operational-state rules

Project progress is calculated from all non-archived Tasks scoped to that Project. Only the Task backend's exact `completed` status counts as complete; archived Tasks are excluded, physically deleted Tasks do not exist in the set, and cancelled Tasks remain incomplete rather than being silently treated as delivered work. Progress is rounded to the nearest integer using PostgreSQL `ROUND`; a Project with zero Tasks reports `0%`. A zero-Task Project is not ready for closure and returns `NO_TASKS`. Project To-Dos have no required/optional marker, so they are not closure blockers. Managers must use the authorized Project status RPC for explicit completion; creation rejects terminal statuses.
