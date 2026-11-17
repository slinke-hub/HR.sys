"""Two-session test; run only against the named local disposable fixture."""
import subprocess
import time
import os
from pathlib import Path

container = os.environ.get('HRSYS_TEST_PG_CONTAINER', 'hrsys-postm7-fidelity-20261116')
database = os.environ.get('HRSYS_TEST_PG_DATABASE', 'hrsys_simplified_final_local_20261117')
if (container, database) not in {('hrsys-postm7-fidelity-20261116', 'hrsys_simplified_final_local_20261117'),
                                  ('hrsys-postm7-fidelity-20261116', 'hrsys_simplified_staging_clean_20261117'),
                                  ('hrsys-postm7-fidelity-20261116', 'hrsys_simplified_mq20_new_20261117'),
                                  ('hrsys-postm7-fidelity-20261116', 'hrsys_simplified_mq20_reassign_20261117'),
                                  ('hrsys-postm7-fidelity-20261116', 'hrsys_configured_route_20261117'),
                                  ('hrsys-simplified-runtime-check', 'postgres'),
                                  ('hrsys-production-simplified-checkpoint', 'postgres')}:
    raise SystemExit('Refusing an unapproved test target')
BASE = ['docker', 'exec', '-i', container, 'psql', '-X', '-q',
        '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1']
DEAL = 'e0000000-0000-4000-8000-000000000001'
ACTOR = 'a0000000-0000-4000-8000-000000000101'
source = Path(__file__).with_name('crm-simplified-backend-runtime.sql').read_text(encoding='utf-8')
seed = source.split('SET ROLE authenticated;', 1)[0].replace('\\set ON_ERROR_STOP on', '') + "UPDATE public.profiles SET department_id='b0000000-0000-4000-8000-000000000001' WHERE id='a0000000-0000-4000-8000-000000000101'; COMMIT;"
def run(sql):
    return subprocess.run(BASE, input=sql, text=True, capture_output=True, timeout=25)

r = run(seed)
if r.returncode:
    raise RuntimeError('synthetic setup failed: ' + r.stderr)
r = run(f"""BEGIN; SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{ACTOR}',true);
 SELECT public.change_crm_deal_stage('{DEAL}','QUALIFICATION'); SELECT public.change_crm_deal_stage('{DEAL}','DISCUSSION');
 RESET ROLE; INSERT INTO public.crm_deal_attachments(deal_id,category,file_name,file_url,file_type,description) VALUES
 ('{DEAL}','QUOTATION','quote.pdf','storage://crm-deal-files/synthetic/q','application/pdf','synthetic'),
 ('{DEAL}','PROPOSAL','proposal.png','storage://crm-deal-files/synthetic/p','image/png','synthetic'); COMMIT;""")
if r.returncode:
    raise RuntimeError('synthetic workflow setup failed: ' + r.stderr)
def submit(delay):
    return f"BEGIN; SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{ACTOR}',true); SELECT public.start_crm_quote_proposal('{DEAL}'); " + ('SELECT pg_sleep(2); ' if delay else '') + 'COMMIT;'
a = subprocess.Popen(BASE, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
a.stdin.write(submit(True)); a.stdin.close()
time.sleep(0.5)
started = time.monotonic()
b = run(submit(False))
elapsed = time.monotonic() - started
a.wait(timeout=20)
if a.returncode or b.returncode or elapsed < 0.8:
    raise RuntimeError('concurrent submissions did not serialize: ' + b.stderr)
r = run(f"""DO $$ BEGIN
 IF (SELECT count(*) FROM public.crm_generated_tasks WHERE deal_id='{DEAL}' AND kind='QUOTE_PROPOSAL')<>1 THEN RAISE EXCEPTION 'registry mismatch'; END IF;
 IF (SELECT count(*) FROM public.tasks WHERE crm_deal_id='{DEAL}' AND crm_workflow_kind='QUOTE_PROPOSAL')<>1 THEN RAISE EXCEPTION 'task mismatch'; END IF;
END $$;""")
if r.returncode:
    raise RuntimeError('concurrency assertions failed: ' + r.stderr)
print('QUOTE_PROPOSAL_CONCURRENCY=PASS')
