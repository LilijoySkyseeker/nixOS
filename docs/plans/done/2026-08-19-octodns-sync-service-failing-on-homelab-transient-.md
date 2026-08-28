---
slug: octodns-sync-service-failing-on-homelab-transient-
created: 2026-08-19
status: done
frozen: true
---

# `octodns-sync.service` failing on homelab — transient DNS resolution error

## Original plan

- [x] **2026-08-19: `octodns-sync.service` failing on homelab —
      transient DNS resolution error.** Found during a log trawl. Job
      failed with `NameResolutionError` trying to reach
      `api.cloudflare.com`. Timer retries hourly so this may self-heal;
      worth confirming it isn't recurring.

      **Confirmed self-healed, 2026-08-25.** Checked the last several
      hours of `octodns-sync.service` runs live: every recent run
      completes cleanly (`INFO Manager sync: 0 total changes`,
      `Deactivated successfully`), no `NameResolutionError` recurrence.
      Whatever the transient resolver hiccup was, it hasn't recurred.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
