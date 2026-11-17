# Temporary security risk acceptance

The administrator approved a temporary, release-specific exception for GHSA-fc5q-39xc-vjpf (CVE-2026-112366). The advisory remains unresolved upstream; this is risk acceptance, not a fix. The affected picomatch 2.3.2 and 4.0.7 copies are transitive Tailwind build/development dependencies. No official patched release was available at review.

The Vercel Production output is static and contained no affected package-name matches. The four deployed Edge Function sources had no direct affected-package imports or dynamic imports; a current isolated dependency resolution contained none. Exact historical transitive dependencies in the four deployed Edge ESZIPs could not be proven. Snyk, CodeQL, Vercel, and application security regressions passed when reviewed. This uncertainty is expressly accepted for this release by the administrator.

Owner: HR.sys release/security owner. The exception expires on 24 November 2026 UTC. Review and remove it immediately when an official patched dependency becomes available, affected code becomes runtime-reachable, Edge Function dependency evidence changes, or another finding changes the risk. The audit runs in full, prints its complete report, and fails closed on unrelated high/critical findings, unexpected package versions or paths, invalid policy, expiry, or an unavailable upstream-version check.
