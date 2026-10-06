# S3 rollback guidance

`20261005110000_security_hardening_s3.sql` is an atomic forward-only security migration. If it fails before `COMMIT`, PostgreSQL rolls the transaction back and no partial policy, ACL, or function changes remain.

After a successful commit, do not replay the prior public `login_attempts` policy or restore broad `record_failed_login(text)` execution as an automatic rollback. Those are the vulnerabilities this migration removes. If a production-impacting issue is found during staging, stop and prepare a separately reviewed compensating migration from a fresh catalog snapshot. That migration must preserve least privilege and must not restore public/authenticated table reads or arbitrary-email lockout writes. No rollback SQL is authorized or executed by this document.
