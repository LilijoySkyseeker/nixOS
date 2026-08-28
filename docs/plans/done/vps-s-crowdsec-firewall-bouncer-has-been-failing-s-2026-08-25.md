---
slug: vps-s-crowdsec-firewall-bouncer-has-been-failing-s
created: 2026-08-25
status: done
frozen: true
---

# vps's CrowdSec firewall bouncer has been failing since at least 2026-08-20 — pre-existing, found live while deploying the auto-updater rearchitect, unrelated to it

## Original plan

- [x] **2026-08-25: vps's CrowdSec firewall bouncer has been failing since
      at least 2026-08-20 — pre-existing, found live while deploying the
      auto-updater rearchitect, unrelated to it.** Both
      `crowdsec-firewall-bouncer.service` (`Failed to set up credentials:
      No such file or directory`, step CREDENTIALS) and
      `crowdsec-firewall-bouncer-register.service` (`Bouncer registered
      but API key is not present`) fail on every boot/restart —
      confirmed identical failure text in the journal from 2026-08-20,
      five days before it was noticed. Looks like the bouncer's API key
      credential was never actually provisioned (or was lost/rotated
      out from under it), so `crowdsec-firewall-bouncer-config`'s
      `LoadCredential=`/systemd-creds step has nothing to load. Needs:
      figure out where this bouncer's API key is supposed to come from
      (`crowdsec-firewall-bouncer-register.service`'s own job, a sops
      secret, or a one-time `cscli bouncers add` step) and re-provision
      it. Not currently blocking anything else (the firewall itself
      still runs via `hosts/vps/configuration.nix`'s own iptables rules,
      independent of CrowdSec) but the bouncer's dynamic IP-ban
      enforcement has effectively been off this whole time.
      **Confirmed still failing, unchanged, live-checked 2026-08-25**:
      both services still fail identically (`step CREDENTIALS`/`API key
      is not present`) on vps's current boot.

      **Landed 2026-08-25 (PR #7, plus a live follow-up fix on top):**
      root cause was a persistence split-brain, not a missing/rotated
      key. `crowdsec-firewall-bouncer-register.service`'s state dir
      (`/var/lib/crowdsec-firewall-bouncer-register`, holding
      `api-key.cred`) was never in vps's impermanence persistence list,
      while CrowdSec's own bouncer-registration DB (`/var/lib/crowdsec`)
      was — so every reboot wiped the credential file but left CrowdSec
      still remembering the bouncer as registered, hitting the register
      script's "already registered, but key missing" failure branch
      every time. Fix: add the directory to
      `environment.persistence."/persist".directories`, same
      owner/group/mode pattern as the existing `/var/lib/crowdsec`
      entry. That alone wasn't sufficient, though — the register
      service still declares `StateDirectory =
      "crowdsec-firewall-bouncer-register"`, and systemd's
      `StateDirectory=` mechanism creates `/var/lib/<name>` as a symlink
      into `/var/lib/private/<name>`, which collides with a real bind
      mount at that same path (`mount: not canonical, contains a
      symlink`). Second fix, mirroring the existing workaround already
      in place for `/var/lib/crowdsec`: drop the dir from
      `StateDirectory` entirely and grant write access via
      `ReadWritePaths` instead, so impermanence owns the path outright.

      Verified live end-to-end on vps, not just build-tested: cleared
      the stale `/var/lib/crowdsec-firewall-bouncer-register` symlink +
      its `/var/lib/private` backing dir, cleared the now-orphaned
      bouncer registration from CrowdSec's DB (`cscli bouncers delete`),
      redeployed, and confirmed both
      `crowdsec-firewall-bouncer-register.service` and
      `crowdsec-firewall-bouncer.service` succeed (`systemctl --failed`
      empty), with `api-key.cred` landing in the real `/persist` backing
      store (`/persist/var/lib/crowdsec-firewall-bouncer-register/`,
      confirmed present) — survives the next reboot rather than only
      working until it.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
