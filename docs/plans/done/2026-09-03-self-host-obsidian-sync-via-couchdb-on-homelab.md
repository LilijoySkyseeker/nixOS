---
slug: self-host-obsidian-sync-via-couchdb-on-homelab
created: 2026-09-03
status: done
frozen: true
---

# Self-host Obsidian sync via CouchDB on homelab

## Original plan

Self-host an Obsidian vault sync server: deploy CouchDB (`services.couchdb`)
on `homelab` for use with Obsidian's "Self-hosted LiveSync" community
plugin on client devices. Tailscale-only exposure (D1) — reachable only
over `tailscale0`, no involvement from vps's public Caddy/CrowdSec/Anubis
stack. Needs admin credentials via sops (never in the Nix store), a
dedicated vault database + a restricted (non-admin) CouchDB user for
client devices to actually authenticate as, firewall scoped to
`tailscale0`, and impermanence persistence for the database directory.
Client-side plugin install/config is manual and out of scope for the Nix
side.

## State

**2026-09-03, research and design done, no code written yet.** Confirmed
`couchdb3` (3.5.1) and the `services.couchdb` module are present, byte-
identical in the relevant sections, in both `nixpkgs` input revs this
repo actually uses (`nixpkgs-stable` @ `a3116115...`, which is what
`homelab` builds against per `modules/flake/hosts.nix`). Read the module
source directly rather than trusting familiarity (G1-G4 below). Verified
the required server-side config against the Self-hosted LiveSync
project's own docs, not assumption (G3). Found and reused directly
relevant prior art: `2026-09-03-add-immich-tailscale-only-to-homelab.md`
landed the *exact* same architecture shape (native NixOS service, bind
broad + firewall-scope to `tailscale0` only, no `wg0`/vps involvement) on
this same host earlier today — its G3 (bind-vs-firewall pattern) and F4
(explicit persistence ownership) apply here directly; its G4/F5 saga (ACL
interaction with a *shared*, multi-tenant `/storage` dataset) does not,
since CouchDB gets its own dedicated, non-shared directory.

Design landed on: a `couchdb-provision-obsidian` oneshot systemd unit that
idempotently creates CouchDB's system databases plus the vault database
and a restricted sync user via the local HTTP API, rather than a manual
one-time step — consistent with this repo's declarative-first bias. Not
run past the user as a formal decision (no real tradeoff serious enough to
block on), but flagged in the final report so they can object.

**2026-09-03, code drafted and mostly verified.** `modules/services/
couchdb.nix` written and registered on `homelab`. `nixfmt` clean, `nix
flake check --no-build` passes fleet-wide. `nixos-rebuild build --flake
.#homelab` builds every derivation this module introduces (the
`couchdb.service`/`couchdb-provision-obsidian.service` units, the
rendered `couchdb.ini`, the sops-templated `couchdb-admins-ini`, the
`/var/lib/couchdb` persistence mount, the firewall unit) and only stops
at activation-manifest time because `homelab_couchdb_admin_password`/
`homelab_couchdb_sync_password` don't exist in `secrets/secrets.yaml`
yet — expected, per this repo's secrets policy agents never add those
themselves. Asked the user for the exact `sops` commands to add them.
Following the trust hierarchy (`docs/procedures/workflow.md`) rather than
stopping at "it built": next is `/simplify` + `security`, then a VM boot
test (`system.build.vm`) once the secrets exist and a real build
succeeds end to end — noting up front that `couchdb.service`/
`couchdb-provision-obsidian.service` are expected to fail inside the VM
regardless (sops-backed, no host key there — `vm-testing.md`'s
documented limitation, not a real bug), so that test's job is confirming
the rest of `homelab` still boots cleanly with this module added, not
exercising the sync path itself.

**2026-09-03, security review found and all four findings fixed; code
verified and ready to deploy.** `security` subagent found F1 (HIGH,
CONFIRMED — sops rotation of the admin password was silently ineffective
after CouchDB's first boot, since CouchDB always persists the currently-
active `[admins]` password's hash into whatever file is *last* in its
`-couch_ini` list, which was `local.ini`, loaded after the sops-templated
`extraConfigFiles`), F2 (MEDIUM, PLAUSIBLE — that same persisted
`local.ini` likely world-readable), F3 (LOW, already fixed pre-emptively
by `/simplify`), F4 (LOW — `couchdb.service` inconsistently missing
`ProtectSystem=strict` that its sibling unit already had). Fixed all
four: `configFile` now points at `/run/couchdb/local.ini` (tmpfs, never
persisted, so the sops-rendered password always wins on every boot —
fixes F1), `UMask = "0077"` added (F2), `ProtectSystem = "strict"` +
`ReadWritePaths` added to `couchdb.service` (F4), F3 was already covered.
Re-verified the full ladder after the fixes: `nixfmt`/`nix flake check`/
`nixos-rebuild build --flake .#homelab` clean, and a fresh VM boot test
confirms `couchdb.service` still starts successfully with the complete
hardening stack applied (the finding's own caution that
`ProtectSystem=strict` failures only surface at runtime, not build time).
Nothing has been deployed to the real `homelab` host yet — build-only per
`AGENTS.md`'s hard-confirm rule; a real `nixos-rebuild switch` needs the
user's explicit go-ahead.

**2026-09-03, docs-updater run, then deployed live on the user's
go-ahead.** `docs-updater` found and fixed F5-F7 (comment bloat, a stale
host-inventory doc, a dead doc reference) — none were behavior changes.
User then asked to deploy: built locally, diffed against the running
system (additions only), switched via `nixos-rebuild switch --target-host
root@homelab`. Verified live, not just build-clean: both new units
active, the provisioning script's own PUTs visible in the journal
(vault db + sync user actually created), auth enforced (401
unauthenticated), firewall rule correctly `-i tailscale0`-scoped,
`systemctl --failed` empty. This plan's Nix-side scope is complete;
client-side plugin setup (deliberately out of scope per Original plan)
is being walked through with the user separately, outside this file.

## Progress
- [x] D1 decided (exposure model) — Tailscale-only
- [x] `modules/services/couchdb.nix` drafted
- [x] registered on `homelab` in `modules/flake/hosts.nix`
- [x] `nixfmt` + `nix flake check --no-build` clean fleet-wide
- [x] `nixos-rebuild build --flake .#homelab` — builds everything this
      module introduces, stops only at the not-yet-created secrets
      (expected)
- [ ] user asked to add `homelab_couchdb_admin_password` /
      `homelab_couchdb_sync_password` via `sops secrets/secrets.yaml`
- [ ] `nixos-rebuild build --flake .#homelab` succeeds end to end once
      secrets exist
- [x] user added `homelab_couchdb_admin_password` /
      `homelab_couchdb_sync_password` via `sops secrets/secrets.yaml`;
      `nixos-rebuild build --flake .#homelab` now succeeds end to end
- [x] `system.build.vm` boot test — booted clean, reached multi-user
      target. `couchdb.service` itself actually **started successfully**
      (`/var/lib/couchdb` mounted via the persistence path, "Started
      CouchDB Server" in the console log) even with no real admin secret
      decryptable — CouchDB tolerates the missing/empty `extraConfigFiles`
      path rather than crash-looping. Only `couchdb-provision-obsidian`
      failed, exactly the documented sops-backed-unit limitation
      (`vm-testing.md`'s table — no host key in the VM, so its two secret
      reads fail). Every other failed unit in the boot log (impermanence
      rollback, `zbackup` pool import, `myZfsDatasetProperties`, S.M.A.R.T.
      daemon, `samba-user-provision`, `wg0`, the minecraft container) is a
      pre-existing, already-documented VM limitation unrelated to this
      change — no new regression anywhere else on the host.
- [x] `/simplify` run — 4 parallel agents (reuse/simplification/
      efficiency/altitude). Reuse/efficiency/altitude clean. Simplification
      found 3 items: (1) the `enable = true; ... lib.mkIf enable` wrapper
      is redundant on its own, but `modules/services/octodns.nix` already
      uses the identical shape for the same kind of single-host, no-real-
      toggle service module — kept for consistency with that precedent,
      not fixed; (2) `corsOrigins`'s single-use let-binding — agent itself
      called this a defensible judgment call, kept for the explanatory
      comment it carries; (3) the sync-user PUT's two copy-pasted JSON-
      string branches (existing vs. new) — fixed, now builds the payload
      once via `jq -n --arg` instead of manual `\"...\"` string
      interpolation, which also closes a real robustness gap (a
      `sync_pass` containing `"`/`\` could otherwise have produced
      malformed or attacker-shaped JSON). `nixfmt` + `nix flake check`
      re-verified clean after the fix.
- [x] `security` subagent run — F1 (HIGH: sops rotation of the admin
      password was silently ineffective after first boot), F2 (MEDIUM:
      persisted `local.ini` likely world-readable), F3 (LOW: already
      fixed pre-emptively by the `/simplify` pass), F4 (LOW:
      `couchdb.service` missing `ProtectSystem=strict` unlike its sibling
      unit) — all four fixed, re-verified via `nixfmt`/`nix flake check`/
      build/VM-boot (couchdb.service still starts clean with the full
      hardening stack + moved configFile), same VM failure set as
      baseline, no new regressions
- [x] `docs-updater` subagent run — F5 (comments duplicating plan
      narrative, trimmed to citations), F6 (`hosts/homelab/README.md`
      Host Inventory stale — regenerated, also picked up a pre-existing
      immich/postgresql/redis gap from an earlier parallel-worktree
      merge), F7 (`new-service.md` cited a nonexistent
      `modules/services/README.md`, corrected) — all three fixed,
      `nixfmt`/`nix flake check`/build re-verified clean
- [x] deployed + verified live — user explicitly asked to proceed.
      `nixos-rebuild switch --flake .#homelab --target-host root@homelab`
      (built locally, `nix store diff-closures` reviewed first: only
      additions, nothing existing touched). Activation clean. Live on the
      real host: `couchdb.service` and `couchdb-provision-obsidian.service`
      both active; the provisioning script's own journal lines show it
      actually created `_global_changes`, `obsidian` (vault db),
      `_users/org.couchdb.user:obsidian-sync`, and the vault's `_security`
      doc, in that order. `systemctl --failed` empty fleet-host-wide.
      Unauthenticated `GET /obsidian` returns `401` (confirms
      `require_valid_user` is actually enforced, not just rendered).
      `iptables -S` confirms the port-5984 accept rule carries `-i
      tailscale0`, no broader interface. No secret value was read or
      decrypted at any point.

## Decisions (D)

### D1 -- exposure model: Tailscale-only vs. public via vps
CouchDB could be reachable only over the tailnet (simplest, no public
attack surface, but every syncing device — including phone — needs
Tailscale running), or reverse-proxied publicly through vps's existing
Caddy/CrowdSec stack like jellyfin (works from any device/network, more
moving parts and attack surface). Presented to the user with the
tradeoff spelled out.

**ANSWERED 2026-09-03:** user picked Tailscale-only. CouchDB binds broad
on `homelab` but is only firewall-reachable via `tailscale0`; no vps,
Caddy, CrowdSec, or Anubis involvement at all.

## Gotchas (G)

### G1 -- `extraConfigFiles` is the documented no-nix-store-secret mechanism
`services.couchdb.adminPass` is a plain `str` option — anything set there
lands world-readable in the Nix store. The module's own `extraConfigFiles`
option doc says outright: "You can use this to setup the Admin user
without putting the password in your nix store." Confirmed via the actual
module source (`nixos/modules/services/databases/couchdb.nix`, both
pinned nixpkgs revs this repo uses): `configFiles` orders
`[default.ini, module-rendered options, extraConfigFiles..., configFile]`
and passes them to `-couch_ini` in that order — CouchDB's ini parsing is
last-directive-wins, so a later `extraConfigFiles` entry correctly
overrides the base config, not the other way around. Use a
`sops.templates` ini file (owned by the `couchdb` user/group, since the
`couchdb` process itself — not root — reads it via `-couch_ini`) for the
`[admins]` section, exactly the pattern `modules/services/octodns.nix`
already uses for its Cloudflare token.

### G2 -- CouchDB's system databases aren't auto-created by the plain module
The upstream Docker image's entrypoint script does one-time "single node"
cluster setup (creating `_users`, `_replicator`, `_global_changes`) when
`COUCHDB_USER`/`COUCHDB_PASSWORD` are first set — the NixOS module just
execs the raw `couchdb` binary directly with no equivalent step. Without
those three system databases, auth (which needs `_users`) doesn't work at
all. Handled here by folding their creation into the same idempotent
provisioning oneshot that creates the vault database and sync user,
rather than a separate manual Fauxton-wizard step.

### G3 -- required server-side config, verified against the LiveSync project's own docs (not assumption)
Per `docs/setup_flyio.md` and `docs/setup_own_server.md` in
`vrtmrz/obsidian-livesync` (fetched directly, per this repo's "verify
against source/official docs" convention):
`[chttpd] require_valid_user=true`, `enable_cors=true`,
`max_http_request_size=4294967296` (4GiB); `[chttpd_auth]
require_valid_user=true`; `[httpd] enable_cors=true`,
`WWW-Authenticate=Basic realm="couchdb"`; `[cors] credentials=true`,
`origins=app://obsidian.md,capacitor://localhost,http://localhost`,
`headers=accept, authorization, content-type, origin, referer`;
`[couchdb] max_document_size=50000000` (50MB). The nginx-specific bits
in `setup_own_server.md` (`client_max_body_size`, `proxy_buffering off`)
don't apply here — Tailscale-direct means CouchDB serves clients with no
reverse proxy in front at all.

### G4 -- `/var/lib/couchdb` needs an explicit persistence entry (impermanence root)
`homelab`'s `/` is rolled back to a blank ZFS snapshot every boot;
`environment.persistence.${vars.persistRoot}` is what actually survives.
CouchDB's `databaseDir`/`configFile`/`.erlang.cookie` all default under
`/var/lib/couchdb`, which isn't in the existing persistence list — needs
adding, with explicit `user`/`group = "couchdb"` (not a bare string),
matching the fix `2026-09-03-add-immich-tailscale-only-to-homelab.md#F4`
already made for the identical impermanence-default-ownership gap.
`/var/log/couchdb.log` needs no separate entry — the existing bare
`/var/log` persistence entry already covers it. Confirmed
`zroot/local/state` (what `${vars.persistRoot}` bind-mounts from) is
already in `myZrepl.local.datasets`
(`hosts/homelab/configuration.nix:387`), so the vault database gets
5-minute-interval ZFS snapshots and zrepl→zbackup replication for free,
no extra backup wiring needed.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 — sops-driven rotation of the CouchDB admin password is silently ineffective once CouchDB has booted once

- **File:** `modules/services/couchdb.nix:58,93-105` (extraConfigFiles / sops.templates."couchdb-admins-ini"); upstream `nixos/modules/services/databases/couchdb.nix` lines 40-45 (`configFiles` ordering) in nixpkgs-stable @ `a3116115851d68b8952a2a4221cc25a84e56b532`
- **Severity:** HIGH
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** Any principal who at some point obtained the CouchDB admin password (leaked value, a former-recipient sops key per `docs/hardening.md` rule 1, a compromised device that briefly held it, shoulder-surfing, etc.) — a plausible one-time first step already covered by this repo's own secrets-rotation runbook. After the operator "rotates" `homelab_couchdb_admin_password` via `sops secrets/secrets.yaml` and redeploys, believing the old value is now invalid, the old password in fact remains valid indefinitely and grants that principal full CouchDB server-admin access (read/write every database including `_users`, ability to create new admin accounts, delete the vault) over the tailnet on port 5984.
- **Rule:** n/a — not a `docs/hardening.md` line item, but undermines `docs/procedures/secrets.md`'s "Rotating a secret's actual value" runbook, whose stated guarantee ("Anyone who still has decrypt access... gets the new value on their next `sops-install-secrets` run") does not hold for this specific credential.
- **Finding:** the NixOS `services.couchdb` module builds its `-couch_ini` file list as `[default.ini, module-rendered-options] ++ extraConfigFiles ++ [configFile]` (confirmed, upstream module source), i.e. `cfg.configFile` (`/var/lib/couchdb/local.ini` by default, used here since it's never overridden) is loaded after `extraConfigFiles` (the sops-templated `[admins]` ini this module wires up as the G1 no-store-secret mechanism). CouchDB's own config subsystem (confirmed against the exact pinned `couchdb3` 3.5.1 tag: `src/config/src/config.erl` `get_write_file/1` = `lists:last(IniFiles)`) treats the last ini file in that list as the sole writable target for any persisted `config:set/3` call. On every CouchDB startup, `couch_password_hasher:init/1` unconditionally calls `hash_admin_passwords(true)` (confirmed, `src/couch/src/couch_password_hasher.erl`), which reads whatever plaintext value is currently active in `[admins]` (from the sops-templated `extraConfigFiles` ini on first boot), computes a PBKDF2 hash, and persists it via `config:set("admins", User, Hash, true)` — landing in `local.ini`, not back into the sops-rendered file. CouchDB's own docs (docs.couchdb.org/en/stable/api/server/configuration.html#admins) state admin credentials live "in the last `[admins]` section that CouchDB finds when loading its ini files" — which, after that first boot, is `local.ini`, permanently shadowing whatever the sops template renders from then on. `local.ini` is `touch`ed (not truncated) in the upstream module's `preStart` and is inside `config.services.couchdb.databaseDir`, which this module correctly adds to `environment.persistence` (G4) — so the shadow survives every reboot too. The module's own `sops.secrets.homelab_couchdb_admin_password.restartUnits = [ "couchdb.service" ]` will dutifully restart the service on rotation, but the restart re-reads `local.ini` last regardless, so the effective admin credential never changes. The only way to actually rotate it as currently wired is to also delete/edit `/var/lib/couchdb/local.ini`'s `[admins]` line by hand on the host, which isn't documented anywhere in this module or the plan.
- **Fix risk:** the straightforward fix (drop an explicit `[admins]` override into `cfg.configFile` itself instead of / in addition to `extraConfigFiles`, or point `services.couchdb.configFile` at a location CouchDB can't treat as the "last" writable file, or add a provisioning step that explicitly `PUT /_node/{name}/_config/admins/<user>` with the new sops value on every boot before relying on ini order) needs to be tested against an actual rotation end-to-end (change the sops value, redeploy, confirm the old password stops authenticating), not just a build — this class of bug is invisible to `nixos-rebuild build`/`nix flake check` and would have shipped clean through everything already run in this plan's State log.


**FIXED 2026-09-03:** services.couchdb.configFile pointed at /run/couchdb/local.ini (tmpfs, never persisted) instead of the default /var/lib/couchdb/local.ini, so the ini file CouchDB treats as its one writable config target starts blank every boot and the sops-templated extraConfigFiles admin password is always what gets (re)hashed and takes effect -- rotation now works. Verified: nixfmt/flake check/build clean, VM boot test shows couchdb.service still starts successfully.

### F2 — persisted `local.ini` (containing the shadowed admin password hash from F1) is likely world-readable

- **File:** upstream `nixos/modules/services/databases/couchdb.nix` (`tmpfiles.rules` `d` line for `databaseDir`, no explicit mode; `preStart`'s `touch ${cfg.configFile}`, no explicit chmod) in nixpkgs-stable @ `a3116115851d68b8952a2a4221cc25a84e56b532`; `modules/services/couchdb.nix:63-70` (persistence entry, inherits whatever mode the directory/files already have)
- **Severity:** MEDIUM
- **Confidence:** PLAUSIBLE (directory-mode-0755-by-default and CouchDB never chmod'ing the file it writes are CONFIRMED from source; the specific effective UMask applied to `couchdb.service`'s `touch` call could not be verified in this session — `nix eval` against this flake was refused by the sandbox as a worktree-isolation risk, and neither this module nor `modules/profiles/server.nix` sets `UMask=` for `couchdb.service`, so it should inherit systemd's own default of `0022`, but that inheritance chain wasn't directly evaluated)
- **Axis:** hardening
- **Reachability:** any other unprivileged local account already running on `homelab` — this repo's own "dedicated service users" convention (`docs/hardening.md`) means homelab already runs several distinct low-privilege system users (samba, octodns, nfs, jellyfin, immich, and now couchdb). A compromise of any one of those services' processes (e.g. a vulnerability in a network-facing sibling service) gets local read access to `/var/lib/couchdb/local.ini` if it's mode 644 under a mode-0755 directory, exposing the PBKDF2-hashed admin password for offline cracking.
- **Rule:** new-rule candidate — n/a in current `docs/hardening.md`
- **Finding:** `services.couchdb`'s `tmpfiles.rules` creates `databaseDir` with `-` for mode (systemd-tmpfiles default 0755 for directories per systemd.tmpfiles(5)), and `preStart` creates `local.ini` via a bare `touch` with no explicit `chmod` (only `.erlang.cookie` gets an explicit `chmod 600` in the same `preStart`). CouchDB's own `config_writer:save_to_file/2` (confirmed, `src/config/src/config_writer.erl`, pinned 3.5.1) writes via plain `file:write_file/2`, which doesn't alter an existing file's mode. So, absent an explicit UMask= override anywhere in this chain, `local.ini` ends up group/world-readable, directly contradicting CouchDB's own admin guidance that the file holding `[admins]` "should be appropriately secured and readable only by system administrators." This module doesn't tighten either the directory mode or UMask= for `couchdb.service`.
- **Fix risk:** tightening this needs `couchdb.service`'s `UMask = "0077"` (or an explicit tmpfiles/ExecStartPre chmod on `databaseDir`/`local.ini`) — low risk on its own, but should be verified not to break the module's own `preStart` (`.erlang.cookie` generation, `configFile` touch) or `viewIndexDir`, which share the same directory.


**FIXED 2026-09-03:** Added UMask = "0077" to couchdb.service's serviceConfig, so every file the Erlang runtime creates (local.ini including the admin password hash, .couch database files, .erlang.cookie) is created 0600 rather than the default 644 -- closes the content-exposure risk. Directory listing (mode 0755 on databaseDir) remains, a much lower-severity residual (filenames only, no content) accepted rather than risking breaking CouchDB's own internal path assumptions by also tightening the tmpfiles directory mode.

### F3 — provisioning script interpolates secret values unescaped into JSON payloads

- **File:** `modules/services/couchdb.nix:162-175`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** weak/self-inflicted only — the value being interpolated (`$sync_pass`, read from `sops.secrets.homelab_couchdb_sync_password.path`) is set by whoever already has `sops secrets/secrets.yaml` edit access, which is already a highly-trusted principal per `docs/procedures/secrets.md`. Named mainly because the task asked it be checked, not because there's a realistic external adversary: an adversary would need pre-existing sops-write trust to exploit it, at which point far more direct routes to compromise already exist.
- **Rule:** n/a
- **Finding:** `$sync_pass` (and, less critically, `$existing_rev`, which comes from CouchDB's own response) are interpolated directly into double-quoted `-d "{...}"` JSON string literals (e.g. `-d "{\"_rev\":\"$existing_rev\",\"name\":\"${syncUser}\",\"password\":\"$sync_pass\",...}"`) without any JSON escaping. This is safe from shell injection (double-quoted variable expansion doesn't re-parse shell metacharacters), but not from JSON corruption: a password value containing `"` or `\` breaks the payload's JSON structure. Given `set -euo pipefail` and `curl -sf`, the practical failure mode for an accidental (non-malicious) special character in a user-chosen password is the provisioning oneshot failing closed (curl gets a 400, `-f` makes it exit non-zero, the script aborts) rather than a corrupted-but-accepted write — but a deliberately crafted value from a principal who already has sops-write access could inject additional/overriding JSON keys into the `_users` document PUT (e.g. altering `"roles"`) beyond what the script intends to send.
- **Fix risk:** switching to `jq -n --arg` to build the JSON body (rather than string interpolation) removes the injection class entirely and is a small, low-risk change — worth testing that the oneshot still succeeds against a real CouchDB instance since it changes how curl's `-d` payload is constructed.


**FIXED 2026-09-03:** Already fixed during the earlier /simplify pass (before this security review ran): the sync-user PUT payload is built via jq -n --arg rather than manual JSON string interpolation, eliminating the injection class this finding describes.

### F4 — `couchdb.service` omits `ProtectSystem=strict` despite all three paths it writes being already known and enumerable

- **File:** `modules/services/couchdb.nix:77-91`
- **Severity:** LOW
- **Confidence:** PLAUSIBLE
- **Axis:** hardening
- **Reachability:** n/a (defence-in-depth gap, not an exploited path) — reduces blast radius if `couchdb.service` (reachable over the tailnet on port 5984, per D1) is ever compromised via a CouchDB vulnerability; without `ProtectSystem=strict`, a compromised couchdb process retains write access to the rest of the host filesystem it doesn't need.
- **Rule:** `docs/hardening.md` "Custom `systemd.services` sandboxing" — the doc's own carve-out is for units that "perform real system activation" or have "a documented functional need" conflicting with the restriction; `couchdb.service` is neither.
- **Finding:** the module's comment justifies omitting `ProtectSystem=strict` by saying it can't be added "without enumerating every path it touches" — but that enumeration is already fully known from the upstream module source read for this review: `databaseDir`/`viewIndexDir` (`/var/lib/couchdb`, already in this module's own persistence list), `dirOf uriFile` (`/run/couchdb`), and `logFile` (`/var/log/couchdb.log`, already covered by the bare `/var/log` persistence entry per G4). `couchdb-provision-obsidian.service` (the sibling unit in the same file) does take the fuller hardening stack including `ProtectSystem = "strict"`, so the omission here is inconsistent within the same module, not a considered exception.
- **Fix risk:** low — `ProtectSystem = "strict"` with `ReadWritePaths = [ "/var/lib/couchdb" "/run/couchdb" "/var/log" ]` should be safe for the Erlang VM's actual I/O pattern, but must be verified against a real boot (not just `nixos-rebuild build`) since `ProtectSystem=strict` failures typically only surface as a runtime EACCES the first time CouchDB tries to write, not at build/eval time.


**FIXED 2026-09-03:** Added ProtectSystem = "strict" plus ReadWritePaths = [ databaseDir "/run/couchdb" "/var/log" ] to couchdb.service's serviceConfig, matching the sibling couchdb-provision-obsidian unit's hardening level. Verified via a real VM boot (not just build) that couchdb.service still starts successfully with the full stack applied, per the finding's own caution that ProtectSystem=strict failures only surface at runtime.

### Checked and clean

Reviewed `modules/services/couchdb.nix` in full against `modules/flake/hosts.nix`'s
one-line registration, the pinned `nixpkgs-stable` `services.couchdb` module
source (`a3116115851d68b8952a2a4221cc25a84e56b532`), and the pinned `couchdb3`
3.5.1 upstream Erlang source for every claim above. Specifically checked and
found fine, beyond F1-F4:

- **CORS/auth config (G3)** matches LiveSync's documented requirements exactly;
  `require_valid_user = "true"` is set in both `[chttpd]` and `[chttpd_auth]`
  (module source shows both are live options, not shadowed by defaults), so
  there is no anonymous-access path.
- **`[admins]` secret handling (G1)**: the sops-rendered template lands at
  `/run/secrets/rendered/couchdb-admins-ini`, mode `0400` owned `couchdb:couchdb`
  by sops-nix's own default (confirmed against the pinned `sops-nix` rev
  `fbf759290e0cb0a98dfc813a4eb7d53ad1dacb57`), never touches the Nix store, and
  is not world-readable — separate from the F1/F2 issue with where CouchDB
  *itself* later persists the hashed value.
- **Firewall scoping**: `networking.firewall.interfaces.tailscale0.allowedTCPPorts
  = [ port ]` is correctly interface-scoped per `docs/hardening.md` rule 5, with
  no host-wide `allowedTCPPorts` entry for 5984 anywhere else in the repo
  (grepped fleet-wide). The Tailscale ACL (`docs/tailscale-acl.json`) already
  grants full-port (`"ip": ["*"]`) `autogroup:member` ↔ `tag:homelab` access as
  pre-existing, deliberate policy (D1's accepted threat model), so no ACL
  update is needed for this specific service.
- **System-database `_security` defaults**: initially suspected that
  `_replicator`/`_global_changes`, created by the provisioning script without
  an explicit `_security` document, might be left readable/writable by the
  low-privilege `obsidian-sync` user (any authenticated non-admin) — checked
  against CouchDB's own `_security` docs and confirmed this is *not* the case:
  "Since CouchDB 3.x newly created databases have by default the `_admin` role
  to prevent unintentional access," so both system databases are admin-only
  by default the moment they're `PUT`, with no separate `_security` document
  needed. `obsidian-sync`'s access is correctly confined to the `obsidian`
  vault DB via the explicit `_security` document the script does set there.
- **Dedicated service user / systemd hardening baseline**: `couchdb.service`
  runs as the module's own dedicated `couchdb` system user (not root), and
  both units carry `NoNewPrivileges`, `PrivateTmp`, the `Protect*` family,
  `RestrictNamespaces`, and `SystemCallArchitectures = "native"` — consistent
  with `docs/hardening.md`'s baseline modulo F4's `ProtectSystem` gap.
- **Idempotent provisioning logic**: the `existing_rev`/`_rev` handling for
  updating the `obsidian-sync` user document is correct optimistic-concurrency
  usage (fetch-then-PUT-with-`_rev`), and the `set -euo pipefail` + `|| true`
  combination on the lookup step correctly tolerates the expected first-run
  404 without masking later errors in the same command.
- **Impermanence persistence (G4)**: `config.services.couchdb.databaseDir`
  correctly covers `local.ini`, the `.erlang.cookie`, and the actual `.couch`
  data files (all colocated under `/var/lib/couchdb` per the upstream module's
  own option defaults), with explicit `user`/`group = "couchdb"` matching the
  fix pattern from the immich plan this one explicitly reused.

No `secrets/*` file was read or decrypted at any point during this review.

_security finished 2026-09-04T04:21:24Z -- see Findings above._

### F5 — `modules/services/couchdb.nix` comments carried plan-duplicate "why"-prose instead of citations

- **File:** `modules/services/couchdb.nix` — the `configFile` comment (was lines 59-73), the `couchdb.service` hardening-block comment (was lines 88-94), and the `UMask` comment (was lines 115-121)
- **Axis:** docs/style
- **Finding:** after the F1/F2/F4 fixes landed, their explaining comments reproduced the plan's F1/F2/F4 narrative nearly verbatim inline (multi-sentence, full incident/rationale prose — e.g. the `configFile` comment ran 13 lines re-deriving CouchDB's `-couch_ini` last-writer-wins behavior and the rotation-shadowing mechanism already fully documented in F1 above), violating `docs/style-guide.md`'s "Why context: the plan file, not comments" rule (rationale belongs in the plan; inline comments beyond a citation pointer are mechanics/labeling only). The `jq -n --arg` payload-construction comment (near the `existing_rev`/`payload` lines) also explained F3's rationale in prose without a plan citation at all.
- **Fix:** trimmed all four comments to a short technical one-liner (or two) plus a `# plan: 2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md#F<N>` citation, matching the density of this same file's `G1`/`G3`/`G4` comments. Also dropped a stray trailing period after the `#D1` citation on the `bindAddress` comment (style guide: citations don't carry a terminal period) and trimmed that same comment's prose to match. Re-verified `nixfmt --check` and `nix flake check --no-build` clean after the edits.


**FIXED 2026-09-03:** Trimmed the four comments in modules/services/couchdb.nix that had duplicated plan finding narrative down to short technical citations, matching the density of this file's own G1/G3/G4 comments. Re-verified nixfmt/flake check clean.

### F6 — `hosts/homelab/README.md`'s Host Inventory block was stale (predated this change, and also predated a prior merge)

- **File:** `hosts/homelab/README.md` (`<!-- inventory:start -->`/`<!-- inventory:end -->` block)
- **Axis:** docs
- **Finding:** `modules/flake/hosts.nix` registers `nixosModules.couchdb` on `homelab` (this plan's change), which per `docs/agents/docs-updater.md`'s "Host Inventory freshness" section requires re-running `scripts/doc-host.sh homelab`. Doing so surfaced more drift than just the couchdb addition: `immich`/`postgresql`/`redis`/`redis-immich` were also missing from the block. Root cause: `2026-09-03-add-immich-tailscale-only-to-homelab.md`'s work and `8a0740a` (which introduced the machine-generated inventory feature and did the first-ever generation of this block) were developed in parallel worktrees off diverging points of `master`; the inventory-feature worktree branched before immich was merged, so its first generation of `hosts/homelab/README.md` never had immich's services in scope. Neither branch's merge commit (`1d161f3` / `fc2d0bc`) triggered a regeneration, so the gap persisted silently until this pass.
- **Fix:** re-ran `scripts/doc-host.sh homelab` (no script failure — no new upstream compat-shim `abort` case encountered; it excludes `services.frp`/`services.redis`/`services.vmalert` as already-known broken compat shims and retries around them, same as it does for every other host). The regenerated block now includes `couchdb`, `immich`, `postgresql`, `redis` in Services; `couchdb`/`postgresql-and-plugins`/`redis` in Packages; TCP `2283` (immich) and `5984` (couchdb) added to the `tailscale0` firewall line; `immich`/`redis-immich` added to System Users; `homelab_couchdb_admin_password`/`homelab_couchdb_sync_password` added to Secrets in use.


**FIXED 2026-09-03:** Regenerated hosts/homelab/README.md's Host Inventory block via scripts/doc-host.sh homelab -- picked up couchdb plus a pre-existing gap (immich/postgresql/redis missing since a parallel-worktree merge never triggered regeneration).

### F7 — `docs/procedures/new-service.md` cited a `modules/services/README.md` that doesn't exist

- **File:** `docs/procedures/new-service.md` (closing paragraph)
- **Axis:** docs
- **Finding:** the doc said "one-line entries in `modules/services/README.md`'s inventory are enough" — but `docs/procedures/updating-documentation.md` itself states plainly that `modules/`, `profiles/`, `services/`, and `secrets/` have no per-folder READMEs, and no such file exists anywhere in the repo (`find` came up empty). This predates the couchdb change — most likely a leftover from before `8a0740a` replaced the old per-service-folder-README inventory convention with the per-host machine-generated "Host Inventory" block — but nothing had corrected the runbook text since. Falls under `updating-documentation.md`'s own "Discovered a stale reference... fix it immediately if it's a one-line change" rule.
- **Fix:** rewrote the closing paragraph to point at the actual current convention: no per-service README, refresh the affected host's `hosts/<host>/README.md` Host Inventory block via `scripts/doc-host.sh <host>`, and put non-obvious gotchas in that host's README.

_docs-updater finished 2026-09-04T04:33:09Z -- see Findings above._

**FIXED 2026-09-03:** Rewrote docs/procedures/new-service.md's closing paragraph to point at the actual current convention (scripts/doc-host.sh <host>, no per-service README) instead of the nonexistent modules/services/README.md it used to cite.
