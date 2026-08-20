# TODO / plans & goals

Running log of plans and goals discussed for this repo, so they can be
referenced across sessions. Not a replacement for host-specific docs
(e.g. `hosts/*/README.md`) — this is for higher-level, cross-host
or longer-horizon items.

Convention: add a dated entry when a new plan/goal is agreed on; check
items off or move them to "Done" as they land; prune stale/abandoned
items rather than letting them rot.

## Active

- [ ] **2026-08-18: verify jellyfin is still reachable after the new
      vps base HTTP rate limit deploys** (vps). Added a base
      per-source-IP `iptables` `hashlimit` rule covering caddy's
      80/443 entry point (120/min, burst 60, `vps-ratelimit` raw
      chain in `hosts/vps/configuration.nix`) so every caddy vhost
      gets floor protection, not just jellyfin's anubis PoW. Once
      deployed to the real droplet, confirm a normal browser session
      against `jellyfin.skyseekerlabs.net` (including the anubis PoW
      round-trip) still loads cleanly and isn't tripping the new
      limit under real usage.

      Checked good-crawler impact against source (not just assumption):
      the jellyfin anubis instance has no `policy` customization, so
      per the module's `mkPolicyFile` logic it falls back to Anubis's
      built-in default policy, which imports `crawlers/_allow-good.yaml`
      and `ALLOW`s known-good crawlers (Google/Bing/Apple/DuckDuckGo/
      Qwant/Internet Archive/Kagi/Marginalia/Mojeek) by their verified
      IP ranges — those bypass the PoW challenge entirely. The new
      120/min-burst-60 iptables layer is separate and sits well above
      documented real-world crawl rates from a single source IP, so
      it shouldn't trip either. No code change needed; the live-deploy
      check above still covers real-world confirmation.

- [ ] **2026-08-18: sops-nix `age.keyFile` fallback doesn't actually
      fire when `age.sshKeyPaths` fails during early boot** (torrent).
      `profiles/PC.nix` configures both `sops.age.sshKeyPaths = [
      "/home/lilijoy/.ssh/id_ed25519" ]` and `sops.age.keyFile =
      "/var/lib/sops-nix/key.txt"`, with `keyFile` explicitly intended
      as the early-boot fallback since `/home` isn't mounted yet during
      initrd-stage activation (see the comment there). On a real boot,
      the initrd-stage `sops-install-secrets` run failed entirely
      (`Cannot read ssh key '/home/lilijoy/.ssh/id_ed25519': ... no such
      file or directory` immediately followed by `Error getting data
      key: 0 successful groups required, got 0`) instead of falling
      back to `keyFile` — `/run/secrets` never got populated for the
      rest of that boot (git identity, and presumably other
      home/root-critical secrets, all missing) until manually re-run
      post-boot via `run0 sops-install-secrets ...` (which then
      succeeded immediately, confirming `key.txt` itself and its
      `.sops.yaml` registration were never the problem). Looks like a
      real sops-nix bug/limitation: a failed `sshKeyPaths` entry seems
      to poison the whole identity list rather than gracefully falling
      through to `keyFile`. Needs: check for a known upstream sops-nix
      issue/fix, or restructure so boot-critical secrets don't depend on
      an identity path that's guaranteed to fail during initrd (e.g.
      drop `sshKeyPaths` from the boot-time identity list entirely and
      rely on `keyFile` alone there). Not yet reproduced against a clean
      reboot (holding off per the no-unconfirmed-local-restarts rule).

- [ ] **2026-08-18: add IPv6 support for the vps's forwarded game
      ports** (Minecraft 25565/19132, Factorio 34197). Currently
      IPv4-only: `net.ipv6.conf.all.forwarding` is explicitly off on
      the vps and there are no `ip6tables` DNAT rules for these ports,
      so `minecraft`/`factorio`'s DNS records were made A-only
      (`services/octodns.nix`) after a live bug where the AAAA records
      advertised IPv6 reachability that didn't exist, silently
      breaking any client (confirmed: a Bedrock client) that prefers
      IPv6 when a hostname resolves to both. The apex still has an
      AAAA record since Caddy on the vps itself is native IPv6, no
      forwarding needed — this item is specifically about the DNAT'd
      raw TCP/UDP game ports. Needs: enable IPv6 forwarding for wg0
      egress only (not blanket `net.ipv6.conf.all.forwarding`), add
      matching `ip6tables`/`nat` DNAT + FORWARD-accept rules alongside
      the existing IPv4 ones in `hosts/vps/configuration.nix`, an
      IPv6-capable SNAT equivalent so return traffic survives
      WireGuard's cryptokey routing (mirrors the existing IPv4
      POSTROUTING SNAT rule), then re-add the AAAA records.

- [ ] **2026-08-18: layer distributed builders across the tailnet**.
      vps's rebuilds are already offloaded off-box — homelab builds and
      pushes vps's closure via `myPushDeploy` (see
      `hosts/homelab/configuration.nix`), vps itself never
      evaluates/builds. This item is the optional
      follow-on, and applies beyond just vps: set
      `nix.distributedBuilds = true` + `nix.buildMachines` (pointing at
      other tailnet hosts, e.g. homelab/thinkpad/torrent as capacity
      allows) so actual compilation — not evaluation, which stays local
      to whichever machine initiates a given host's rebuild — fans out
      across the tailnet instead of always landing on one machine.
      Purely a build-time-distribution optimization, not required for
      any host's correctness.

- [ ] **2026-08-18: caddy hits a permission-denied race against the
      anubis unix socket right after vps reboots.** Found trawling
      vps's logs: from 03:18–03:47 (right after a 23:47 reboot), every
      request to `jellyfin.skyseekerlabs.net` 502'd with `dial unix
      /run/anubis/anubis-jellyfin/anubis.sock: connect: permission
      denied` (36 requests total), then self-resolved and hasn't
      recurred since (0 in the following ~13h). `caddy`'s `id` shows
      it *is* in the `anubis` group (`hosts/vps/configuration.nix`
      already has `users.users.caddy.extraGroups = [ "anubis" ]`,
      added for exactly this failure mode per the comment there) — so
      this looks like a boot-order race, not a missing-permission bug:
      caddy's group membership or the socket itself isn't ready by the
      time caddy starts serving. Needs: add an explicit
      `systemd.services.caddy.after`/`wants` (or similar ordering) on
      the anubis service/socket so caddy doesn't start accepting
      traffic until anubis's socket exists with the right group perms
      already applied.

- [ ] **2026-08-19: `octodns-sync.service` failing on homelab —
      transient DNS resolution error.** Found during a read-only log
      trawl through homelab (checked against exposed services in
      `hosts/homelab/configuration.nix`; no signs of compromise, SSH
      and service access all traced to known keys/tailnet/LAN). Job
      failed with `requests.exceptions.ConnectionError` /
      `NameResolutionError` trying to reach `api.cloudflare.com`
      (`Failed to resolve 'api.cloudflare.com' ... Temporary failure
      in name resolution`). Timer retries hourly so this may self-heal,
      but worth confirming it isn't recurring (e.g. flaky upstream
      resolver, or the service starting before network-online.target).

- [ ] **2026-08-19: `flake-update-test.service` failing on homelab —
      root has no git identity configured.** Found during the same log
      trawl. The update-branch step fails with `fatal: unable to
      auto-detect email address (got 'root@homelab.(none)')` right
      after the flake inputs are bumped, because `git config
      --global user.email`/`user.name` were never set for root on
      homelab. Needs: set a git identity for root declaratively (e.g.
      via `home-manager.users.root.programs.git` in
      `profiles/server.nix`, alongside the existing root home-manager
      block) so `myAutoUpdate`'s commit step succeeds.


## Done

- [x] **2026-08-20: build out comprehensive repo documentation** (docs
      architecture, planned via Q&A — see AskUserQuestion trail in
      session for full rationale). Two prongs: a central `docs/`
      folder for high-level material, and non-obvious "why" comments
      inline in `.nix` configs. Audience is future-me/AI agents, not
      external contributors. Root stays lean (`README.md`,
      `AGENTS.md`, `TODO.md` only, each pointing into `docs/` rather
      than duplicating it); `AGENTS.md` keeps its current fast-load
      entrypoint role and links out for depth rather than being
      merged away. Staleness strategy: folder-level docs live next to
      the code they describe so change-with-code discipline is
      natural; the more narrative `docs/architecture.md` and
      `docs/style-guide.md` need an occasional manual audit instead
      (added as a recurring check, not a one-off). Inline comments
      stay non-obvious-only (workarounds, surprising constraints,
      tradeoffs) — no broad completeness sweep.

      Phase 1 — `docs/` skeleton: `docs/architecture.md` (how
      hosts/profiles/modules/services compose — expands on README's
      structure guide), `docs/style-guide.md` (Nix formatting/idiom
      conventions, naming, when to use a module vs a profile vs a
      service), `docs/agents.md` (AI-agent-specific depth, linked
      from root `AGENTS.md`), `docs/procedures/` directory. Trim
      `AGENTS.md` to point into these rather than re-deriving them.

      Phase 2 — per-folder READMEs for everything that doesn't
      already have one: `modules/nixos/`, `modules/home-manager/`,
      `profiles/`, `services/`, `secrets/`, `custom-packages/`,
      `files/`. **Not** `hosts/*/README.md` — that's a known-issues
      log, a different purpose, left as-is. Shared template recorded
      in `docs/README-template.md`: Purpose, then an Inventory
      section (one-liner per file — detail stays in the file's own
      header comment, not duplicated in the README), then an optional
      Gotchas section for non-obvious cross-cutting things, omitted
      entirely when there's nothing to say.

      Phase 3 — flesh out `docs/procedures/`: adding a new host,
      adding a new service, secret rotation, disaster recovery.
      **Disaster-recovery/reinstall procedures are already being
      written by another session as of 2026-08-20 — leave that one
      file as a placeholder stub (link/short note only) and don't
      duplicate it; everything else in Phase 3 is open to write.**

      Phase 4 — inline why-comment sweep across existing
      modules/services/hosts configs, opportunistic and
      non-obvious-only (not a mechanical every-file pass).

      Phase 5 — root `README.md` rewrite. Deliberately last: do this
      once Phases 1-3 exist so the README can link into real `docs/`
      content instead of being written blind. **Architect this one
      together with the user interactively, don't draft it solo.**

      2026-08-20: confirmed via Q&A that architecture.md,
      style-guide.md, procedures/* (minus disaster-recovery, see
      above), agents.md + the AGENTS.md trim, and all of Phase 2's
      folder READMEs are clear to write now — nothing else flagged as
      in-progress elsewhere. Proceeding with Phases 1–2 plus the
      non-disaster-recovery parts of Phase 3.

      **Phase 1 done (2026-08-20)**: `docs/architecture.md` (import
      chain, per-host composition table, module/service/profile
      boundary), `docs/style-guide.md` (nixfmt, the `my<Name>`
      options-module convention, real why-comment examples), `docs/
      agents.md` (the reasoning behind AGENTS.md's rules), `docs/
      procedures/{new-host,new-service,secret-rotation}.md` written;
      `docs/procedures/disaster-recovery.md` left as the agreed
      placeholder. `AGENTS.md` trimmed to link into all of the above
      rather than duplicating. Next: Phase 2 folder READMEs.

      **Phase 2 done (2026-08-20)**: folder READMEs added for
      `modules/nixos/`, `modules/home-manager/`, `profiles/`,
      `services/`, `secrets/`, `files/`, following
      `docs/README-template.md`'s Purpose/Inventory/Gotchas shape.
      `custom-packages/` skipped — it doesn't exist in the repo (was a
      stale reference in `AGENTS.md`/`README.md`, stripped from
      `AGENTS.md`; `README.md`'s copy is Phase 5's problem). Notable
      gotchas captured: `nfs-homelab-mounts.nix`'s gid must stay in
      sync with `services/jellyfin.nix`'s group (cross-host coupling,
      not Nix-enforced); `server.nix` doesn't import `default.nix`
      itself, so every server host must import both. Next: Phase 3
      remainder is already done (procedures written in Phase 1 except
      disaster-recovery) — Phase 4 (inline why-comment sweep) is next.

      **Phase 4 done (2026-08-20)**: swept `hosts/vps/configuration.nix`
      (crowdsec/caddy `logFormat`, syslog `labels.type`, iptables
      hashlimit, anubis socket group, IPv6 forwarding scoping),
      `services/octodns.nix` (AAAA/A-only split), `profiles/PC.nix`,
      `profiles/server.nix`, `hosts/homelab/configuration.nix`
      (`myPushDeploy`, ZFS snapshot mount/unmount for restic, the
      backblazeDaily/backblazeWeekly rclone-remote-name mismatch), and
      `modules/nixos/*.nix` for non-obvious decisions lacking a
      why-comment, cross-checked against already-resolved TODO.md
      "Done" incidents and git history so nothing speculative got
      added. Result: no gaps found — every non-obvious decision in
      the sampled areas already carries a why-comment from prior
      incident-driven work, so no new comments were added this pass.
      Consistent with the "opportunistic, non-obvious-only" policy —
      not a mechanical every-file sweep, and nothing forced in just to
      have something to show. Revisit opportunistically as new
      non-obvious decisions land, not on a schedule.

      **Phase 5 done (2026-08-20)**: root `README.md` rewritten,
      architected interactively with the user rather than drafted
      solo as planned. Replaced the stale structure-walkthrough
      (referenced a `custom-packages/` folder and module/service files
      that no longer exist, empty "Hosts" and "Interesting Stuff"
      sections) with: a concise intro, a layout summary linking into
      `docs/architecture.md`/`docs/style-guide.md`/`docs/procedures/`,
      a real per-host table, and an "Interesting stuff" highlights
      section (impermanence, the stable/unstable channel split, the
      vps-as-decoy-front design, local-build-not-remote deploys, the
      out-of-band Tailscale ACL). Deliberately written for a human
      audience (not agent-facing) per explicit user direction — no
      agent-safety caveats or reachability-checking instructions,
      those stay in `AGENTS.md`/`docs/agents.md` where they belong.

      **All 5 phases complete.** Documentation plan closed out —
      moving this entry to Done.

      **2026-08-20 follow-up**: the plan never actually documented how
      to keep the docs themselves in sync — a real gap, noticed when
      asked what procedures existed for it and found there weren't
      any. Added `docs/procedures/updating-documentation.md`, covering
      routine per-commit updates (folder README inventory/gotchas,
      inline why-comments, host tables), a periodic opportunistic
      audit for the narrative docs (`architecture.md`/
      `style-guide.md`, no fixed schedule), and a plan for full docs
      rewrites after a structural refactor (re-survey from scratch
      rather than patch piecemeal, same shape as this original
      build-out). Linked from `AGENTS.md`'s docs pointers and
      procedures list.

      **2026-08-20 second follow-up**: added two more pieces on
      request. (1) A "Root `README.md` and `AGENTS.md`" section in
      `docs/procedures/updating-documentation.md` — those two get a
      narrower update trigger than the folder READMEs (front door, not
      general docs), spelling out what actually warrants touching each
      one so they don't bloat over time. (2) A "Flag issues
      immediately" convention: when a documentation issue is noticed
      but not fixed on the spot (out of scope, too big, mid-task), log
      it to `TODO.md`'s Active section right away rather than trusting
      memory — mirrors how real incidents already get logged here.
      Pointed to from `AGENTS.md` directly so it's actionable, not just
      buried in the procedure doc.

- [x] **2026-08-18: confirmed + fixed — crowdsec was never actually
      banning anything on vps.** Root cause found via
      `curl http://127.0.0.1:6060/metrics` (crowdsec's own prometheus
      endpoint) and `cscli explain`: `services.caddy.virtualHosts.
      <host>.logFormat` defaults to `null` in the pinned nixpkgs caddy
      module (confirmed by reading
      `nixos/modules/services/web-servers/caddy/default.nix` directly,
      not just docs), so no `log {}` block was ever emitted for
      `jellyfin.skyseekerlabs.net` — caddy only wrote sparse
      error/tls/acme events to the journal, never real per-request
      access logs. crowdsec's `crowdsecurity/caddy-logs` parser (which
      needs the `request` object only access-log entries carry) had
      **0 hits in its entire runtime**, confirmed both via its
      prometheus counter being entirely absent from `/metrics` and via
      a live test request producing no new parser activity — despite
      heavy leakix.net-style vulnerability-scanner traffic hitting the
      host over the preceding 24h. (Side note while debugging: `sudo
      -u crowdsec cscli ...` silently no-ops with exit 200 and zero
      output on this host, since `sudo` is aliased to `run0` which
      can't switch to `crowdsec`'s `nologin` shell — use
      `runuser -u crowdsec --` instead; my first pass at this
      investigation used the broken `sudo -u crowdsec` form and
      wrongly reported "zero decisions/alerts" as a real empty result
      rather than a broken command.) Fix: added an explicit
      `logFormat = "output stdout\nformat json"` to the jellyfin
      vhost in `hosts/vps/configuration.nix`, verified by inspecting
      the actual rendered `Caddyfile` (`log { output stdout; format
      json }` now present) and by confirming via `cscli explain` that
      a real captured caddy log line parses successfully and matches
      `crowdsecurity/http-crawl-non_statics` once given that JSON
      shape. **Deployed and confirmed live 2026-08-18**: after the
      `logFormat` fix, `crowdsecurity/caddy-logs` still had 0 hits —
      `journalctl -u crowdsec` showed `UnmarshalJSON: invalid
      character 'A' looking for beginning of value` on every caddy
      line. Second root cause: journalctl always prefixes lines with
      the syslog envelope (`Mon DD HH:MM:SS host caddy[pid]: `), and
      only `labels.type = "syslog"` (not `"caddy"`) routes events
      through `crowdsecurity/syslog-logs` to strip that prefix before
      `caddy-logs` sees the JSON — a known crowdsec gotcha
      (crowdsecurity/crowdsec#4098: "Journalctl sources MUST use
      syslog type"). Fixed the acquisition's `labels.type` to
      `"syslog"` in `hosts/vps/configuration.nix`, redeployed, then
      verified end-to-end live: sent real probe requests
      (`.env`, `.git/config`, `wp-login.php`, etc.) through
      `jellyfin.skyseekerlabs.net`, watched `cs_bucket_poured_total`
      increment across five caddy scenarios, and got a real
      `crowdsecurity/http-admin-interface-probing` ban decision back
      from `cscli decisions list` — then deleted that decision since
      it was our own test traffic, not a real attacker. crowdsec now
      genuinely bans scanners hitting jellyfin; before this it never
      had.
