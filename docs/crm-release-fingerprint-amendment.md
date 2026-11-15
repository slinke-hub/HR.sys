# CRM release fingerprint amendment

This change supersedes the earlier Migration 2 file checksum `43220CFA78B8877F55D288831D1D712D5E96E6F5D16D3147371627DCE21D1294`. It requires fresh review. It does not authorize migration execution or deployment.

The canonical function-definition representation is `replace(replace(pg_get_functiondef(oid), E'\r\n', E'\n'), E'\r', E'\n')`. It changes line endings only; whitespace, comments and SQL tokens remain part of the fingerprint. PostgreSQL 17.6 tests verify LF, CRLF and standalone CR equivalence, and verify comment and token changes still differ.

## Proven line-ending-only differences

The compared Production-derived LF and previously reviewed mixed-line-ending definitions were identical after LF normalization. Staging values were measured from the reviewed data-free Staging-derived fixture.

| Definition or check | Previous raw MD5 | Canonical LF MD5 |
|---|---|---|
| Migration 2 post-created record_task_activity | 564aa16803893f7f33c867444367f2ae | 4ecdd7bd9a8d6e30cdff2f3fc5bb7a3e |
| Contact task generator | b910ccd3db38d6d7e3b2ef2b0d085125 | 36ff1ea84a09da820d13f9d94e5a4b93 |
| Qualification trigger function | bbe90a1ecf192a7916c7450850a482bc | f57d221d3d89ca8d4b00ff5ad622cc68 |
| Production Contact guard | 5ae2d19594eed5b5c46b5dfed47d646d | 293cae319b36c4ed98d7e7a265afd04a |
| Staging Contact guard | aa1a170d2d0a492423079af2265147d0 | 3d2487cc0610bee3cbe9615be2fd1750 |
| Production MQ-20 boundary | 17f39621f2b3b73811eaf17368b3c227 | 7a2b93f1e12e3d4ed20fa52ccbb0d972 |
| Staging MQ-20 boundary before change | 74ac3ade746a2630b1365639d458fcf2 | 17a3a44b5e04a47d9503f8a84ec2008e |
| Staging MQ-20 boundary after change | 9bda804219c1a5d97fc471244132bdf6 | 6eeff07ec9f9d30d63e06c341bc0700f |
| Staging private context | 60838a0cb581aec803c2a353e1a3b13d | c33aee8ab568756e35d51715d94a5e35 |
| Production current Contact reader | b73ba5faef448c861cd85b0f3d40476f | f50204fee04d0013efa9f5f94308837a |
| Staging current Contact reader | b2a46adfb6675b000fe5b2416ad92edd | d83f83b48ba2f5b1c2b16b8bb1628a2a |

The Qualification trigger canonical value is `f57d221d3d89ca8d4b00ff5ad622cc68`; it is recorded here separately to avoid confusing it with a different approval-document function.

Marketing review and task-attachment helper postconditions retain their existing LF expected fingerprints, but canonicalize the input because CRLF-only execution generated different raw fingerprints. Full PostgreSQL definitions matched byte-for-byte after LF normalization. Fixed SQL rewrite templates are also normalized before matching/execution so checkout line endings do not break otherwise identical template matches.

## Guard audit

- `20261111100000`: no fingerprint comparisons.
- `20261112100000`: raw `pg_get_functiondef` comparisons pin pre-existing Production catalog definitions; policy-expression hashes use PostgreSQL-deparsed policy expressions.
- `20261112110000`: raw pre-existing function fingerprints remain unchanged; the proven generated `record_task_activity` postcondition is canonicalized.
- `20261112120000`: raw function comparisons pin pre-existing catalog functions; its policy-expression hashes are a separate PostgreSQL-deparsed representation.
- `20261113100000`: policy-expression hashes, not function-body hashes.
- `20261115120000`: proven generated or mixed-line-ending functions are canonicalized; unchanged pre-existing function fingerprints remain raw and fail closed if they drift. Policy hashes are unchanged.
- `20261115130000`: reviewed baseline and postcondition fingerprints remain fail-closed; fixed migration-generated SQL templates are normalized to LF before matching/execution.

Raw function fingerprints remain potentially line-ending-sensitive for a differently represented hosted baseline. The reviewed Production and Staging-derived fixtures satisfy those unchanged guards; no unverified fingerprint value was silently altered. Any hosted preflight mismatch must stop execution.

## Local evidence and limits

`tests/crm-approval-release.runtime.test.cjs` reads staged Git blobs and applies the ordered migrations to reviewed data-free PostgreSQL 17.6 fixtures when their paths are supplied. It explicitly reports a skipped fixture when an input is absent. Separate tests cover canonicalization, decision/Design terminal protections, Task Manager and two-session concurrency. The Storage policy fixture is synthetic; hosted Storage, Preview configuration, backup and authenticated acceptance remain separate gates.
