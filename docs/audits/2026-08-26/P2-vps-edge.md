# P2 — `vps`, the internet edge

Part 2 of the 2026-08-26 fleet-wide security audit. Scope: `hosts/vps/`
in full. Rated against [`00-threat-model.md`](00-threat-model.md) §6,
schema per [`P0-findings.md`](P0-findings.md).

This host is the only one with a real public IPv4, real public
listeners, and a genuinely adversarial default boundary (§4.6). It is
also the best-defended host in the fleet, and most of what is here is
right. The findings below are therefore weighted toward structural
gaps, controls that do less than their presence implies, and grants
that have outlived their reason — not toward re-litigating settings
that are already correct. Everything examined and found sound is listed
in "Checked and clean" at the end, which is deliberately long.

**§4.7 changes several ratings in this report.** The repository is
public, so no finding here claims obscurity. The dispatcher's parser,
the exact hashlimit thresholds, the failregex, the ban curve, the NAT
map and the WireGuard topology are all readable by an attacker offline,
with unlimited time and no detection. Where that matters, the finding
says so explicitly.

---

## 1. Scope and method

### Files read in full

- `hosts/vps/configuration.nix` (752 lines)
- `hosts/vps/disko.nix`
- `hosts/vps/hardware-configuration.nix`
- `hosts/vps/README.md`

### Supporting files read

- `docs/hardening.md`, `docs/procedures/remote-access.md`
- `docs/audits/2026-08-26/00-threat-model.md` (including §4.7),
  `docs/audits/2026-08-26/P0-findings.md`
- `modules/profiles/server.nix`, `modules/profiles/default.nix` (what
  vps inherits), `modules/nixos/health-alerts.nix`,
  `modules/nixos/push-deploy.nix` (what homelab actually sends to the
  dispatcher), `modules/flake/hosts.nix`, `flake.nix`, `flake.lock`,
  `.sops.yaml`, `TODO.md` (the parked IPv6 item)
- `secrets/secrets.yaml` — **metadata only** (recipient count, top-level
  key names). No value was decrypted or read; per §9 the audit covers
  recipients and plumbing, not plaintext.

### The pinned nixpkgs

vps builds from `nixpkgs-unstable`, locked at rev
`0e251e24a4f24e036a084b6b4b2d2491af4167f4` (`nixos-26.11pre1053317`).
Located it by evaluation, not by assumption:

```
nix eval --raw .#nixosConfigurations.vps.pkgs.path
  -> /nix/store/09g0q2nr523x5inkal66127xmq2z8gw0-yybhs1ybhvk6w56gjywq2x9ipdpx6dd9-source
```

and confirmed `.git-revision` in that tree matches `flake.lock`'s
`nixpkgs-unstable`. Every module claim below cites a path under that
tree.

Modules read there: `services/networking/ssh/sshd.nix`,
`services/networking/firewall-iptables.nix`,
`services/networking/nat-iptables.nix`,
`services/networking/wireguard.nix`,
`services/networking/anubis.nix`,
`services/security/crowdsec.nix`,
`services/security/crowdsec-firewall-bouncer.nix`,
`security/run0.nix`, `system/activation/activation-script.nix`,
`system/boot/loader/grub/grub.nix`, `config/users-groups.nix`.

### Claims verified against the *rendered* output, not the source

Because `nix eval` gives the effective merged value and several of these
differ materially from what the file says, the following were read as
built artefacts:

| What | Store path realised | Why it mattered |
|---|---|---|
| `/etc/ssh/sshd_config` | `…-sshd.conf-final` | §7.2 — which `extraConfig` directives are actually in force |
| `firewall-start` | `…-firewall-start/bin/firewall-start` | rule ordering, `set -e` behaviour, where `extraCommands` is spliced |
| `/etc/fail2ban/jail.local` | `…-jail.local` | effective `ignoreip`, backend, jail parameters |
| `/etc/fail2ban/filter.d/vps-closed-port-scan.conf` | `…-filter.d-vps-closed-port-scan.conf` | the failregex as rendered |
| Caddyfile | `…-Caddyfile-formatted/Caddyfile` | the `:80` catch-all, global log level, header handling |
| `/etc/ssh/authorized_keys.d/vps-deploy` | `…-vps-deploy-authorized_keys` | the actual `command=`/`restrict` line |
| the dispatcher | `…-vps-deploy-dispatcher` | the interpolated `exec` targets |
| `crowdsec` `settings.general` | evaluated to JSON | LAPI bind, CAPI/telemetry flags, paths |

### Third-party binaries inspected

- `ipset` 7.24 — read the pinned man page for `-exist` semantics
  (load-bearing for F-P2-02).
- `crowdsec` 1.7.8 — ran `cscli decisions delete --help`,
  `cscli decisions add --help`, `cscli allowlists --help` from the
  pinned store path (load-bearing for F-P2-04 and for confirming
  allowlists are honoured).
- `cs-firewall-bouncer` 0.0.36 — string-inspected for ipset naming and
  create parameters.
- `openssh` 10.4p1 — read `sshd(8)`'s definition of `restrict`.
- `anubis` 1.27.0 — string-inspected for the socket-mode default.

### What I could not verify, and is marked PLAUSIBLE

- **`xt_hashlimit` behaviour on hash-table exhaustion.** I did not read
  the pinned kernel's `net/netfilter/xt_hashlimit.c`. The claim that
  table exhaustion causes a `hotdrop` (dropping *all* matching traffic,
  not just over-limit traffic) is from memory of upstream and is marked
  PLAUSIBLE in F-P2-06.
- **`cs-firewall-bouncer`'s exact ipset create parameters.** The binary
  contains no `hashsize` string, which is consistent with it relying on
  ipset's default of 1024 (matching the repo's hardcode), and it
  contains `maxelem`/`timeout`/`nethash`. I could not read its Go source
  to confirm the `-0` set-name suffix or the literal `timeout 300`. The
  repo comment says this was confirmed live; I have not re-confirmed it.
  This does not weaken F-P2-02, whose point is precisely that the match
  is unverified-by-construction and load-bearing.
- **cloud-init's boothook handling path.** That DigitalOcean's
  vendor-data boothook executes as root on every boot is CONFIRMED
  empirically (the repo's own comment at `:224-233` documents the
  `noexec` failure that proved it). That it runs via a part-handler
  independent of the emptied `cloud_config_modules`/`cloud_final_modules`
  lists is PLAUSIBLE — I did not read the pinned cloud-init source.
- **journald rate-limiting of kernel-transport messages.** Whether
  `RateLimitBurst=10000/30s` applies to `_TRANSPORT=kernel` as a single
  bucket is PLAUSIBLE, noted in F-P2-03.
- **Nix's daemon allowing `trusted-users` past `allowed-users`.** The
  effective config is `allowed-users = ["root"]`,
  `trusted-users = ["root","vps-deploy"]`. Deploys demonstrably work, so
  the daemon evidently admits `vps-deploy`; I could not read the source
  of the pinned `nix-2.34.8` to confirm the mechanism. PLAUSIBLE, noted
  under "Checked and clean".
- **Anything requiring the live host.** Static audit only. No SSH to
  vps, no `nixos-rebuild` against it, no `switch`, no secret decrypted,
  no `.nix` file edited.

---

## 2. Findings

### F-P2-01 — vps's host key decrypts the entire fleet's secret store, and the ciphertext is public and permanent

- **File:** `.sops.yaml:9-24`, `hosts/vps/configuration.nix:264-265`
  (persisting `/etc/ssh/ssh_host_ed25519_key`),
  `modules/profiles/server.nix:65`
  (`sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]`),
  `secrets/secrets.yaml`
- **Severity:** HIGH
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A1/A2 — root on vps by any means (a caddy, anubis,
  sshd or kernel compromise from the open internet) yields the age key
  at a fixed, published path. Also A6, and anyone who ever obtains a
  copy of the droplet's disk or a DigitalOcean snapshot. Threat model
  §4.7 makes the second half of the chain free: the ciphertext is
  already downloaded.
- **Rule:** new-rule candidate — `docs/hardening.md` says nothing about
  scoping sops recipients per host.
- **Finding:** `.sops.yaml` has exactly one `creation_rule`, matching
  `secrets/[^/]+\.(yaml|json|env|ini)$`, with a single key group listing
  all seven age recipients — including `&vps`. sops encrypts a file to
  every recipient in the group, so vps's host key decrypts the whole of
  `secrets/secrets.yaml`. That file holds 31 secrets (confirmed by
  counting top-level keys; 7 `recipient:` entries in the sops footer
  confirm the recipient set). vps declares and reads seven of them:
  `tailscale_authkey_vps`, `git_username`, `git_email`,
  `vps_wireguard_private_key`, `wireguard_vps_homelab_psk`,
  `vps_discord_webhook`, and `vps_caddy_env` (which nothing consumes —
  see F-P2-13). It holds decryption authority over the other 24,
  including `homelab_vps_deploy_key` (the private half of the key that
  is root on vps), `homelab_zrepl_key`, `torrent_backup_push_key`,
  `thinkpad_backup_push_key`, `homelab_backblaze_restic_password`,
  `homelab_backblaze_rclone_config`, `restic`,
  `cloudflare_octodns_token`, `homelab_wireguard_private_key`, and every
  host's tailscale auth key.

  Mapped onto §1's asset list, root on vps therefore reaches asset #3
  (the secrets) in full, and through it asset #1 (the backup pools, via
  the zrepl and Backblaze credentials), asset #5 (via the tailscale auth
  keys and §4.4), and DNS control of the domain (via the Cloudflare
  token, which is also an ACME DV issuance capability for any name under
  it). This is the exact case §6 names as HIGH: "any secret exposed to a
  principal that should not hold it."

  §4.7 adds two things that make it worse than a private-repo version of
  the same mistake. First, there is no network boundary in front of the
  ciphertext — sops/age is the only control, with no rate limit and no
  detection on an offline attack. Second, **rotation is not
  retroactive**. `.sops.yaml:20-22` records that vps's key was rotated on
  2026-08-25 after the post-brick reinstall; that rotation removed
  nothing, because every prior revision of `secrets/secrets.yaml` is
  still in public history, still encrypted to the old vps key, and still
  contains the un-rotated *values* of those 24 secrets. Recovering the
  destroyed droplet's key at any point in the future decrypts all of
  them.

  This is not a vps-specific design error so much as a repo-wide
  default that lands hardest on vps, because vps is the one host in the
  fleet that an unauthenticated internet attacker is actively trying to
  get root on.
- **Proposed fix:** decision required, and the fix has two halves that
  must not be confused.
  1. *Structural.* Split `secrets/secrets.yaml` and add per-path
     `creation_rules`. At minimum: `secrets/vps.yaml`, encrypted to the
     admin/laptop keys plus `*vps` only, holding the six secrets vps
     actually uses; remove `*vps` from the rule covering everything
     else. sops-nix supports a per-secret `sopsFile`, so the Nix side is
     a mechanical change. The same argument applies to every host, and
     the natural end state is one file per host plus one shared file.
  2. *Remedial.* The split is cosmetic on its own. Because the old
     ciphertext is public and permanent, every secret vps could read
     must have its **value** rotated for the exposure to actually close.
     That is 24 secrets and it is user-only work
     (`docs/procedures/secrets.md`) — no agent may do it. It is a real
     cost and it should be an explicit decision, not an implied
     consequence of the split.

  A cheaper interim step, if (2) is deferred: stop the bleeding by
  making the split now, so that *future* revisions are scoped, and
  record the historical exposure as a known, accepted debt with a list
  of which secrets it covers.
- **Fix risk:** splitting the file is a `sops updatekeys` and a set of
  `sopsFile` edits; getting the recipient set wrong on any host silently
  breaks that host's boot-time decryption, which on vps means no
  tailscale auth key and therefore no SSH — a recovery-console
  situation. Stage per host and keep the DO console reachable. Rotating
  values will bounce zrepl, restic, tailscale enrolment and the
  WireGuard tunnel; sequence it so the tunnel and the tailnet are not
  both down at once.
- **Owner:** P2 for the vps-side statement of impact; P7 (or whoever
  owns `.sops.yaml`) for the split mechanism; user decision on the
  rotation.

### F-P2-02 — one unguarded `ipset create` can take the entire packet filter down, fail-open, on the internet-facing host

- **File:** `hosts/vps/configuration.nix:400-401`, `:448-449`,
  `:407`, `:455`; pinned nixpkgs
  `nixos/modules/services/networking/firewall-iptables.nix:50-58`
  (`writeShScript` renders `#! bash -e`), `:234` (`${cfg.extraCommands}`
  spliced), `:237-241` (the final `nixos-fw-log-refuse` rule and
  `INPUT -j nixos-fw`), `:255-278` (`reloadScript` calls `stopScript` on
  failure)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the mechanism; PLAUSIBLE for the
  trigger.
- **Axis:** hardening
- **Reachability:** A1/A2 — if `firewall-start` aborts, the box runs
  with no INPUT filtering at all. `services.openssh.openFirewall = false`
  (`:319`) is not an sshd setting; sshd binds `0.0.0.0:22` and the
  packet filter is the *only* thing keeping it off the public internet
  (`docs/procedures/remote-access.md` says exactly this: "Port 22 is
  never opened on the public interface … restricted to
  `networking.firewall.trustedInterfaces`"). So a failure here converts
  "SSH is tailnet-only, confirmed live" into "OpenSSH pre-auth exposed to
  the internet", together with the loss of the raw-table rate limiter
  and the CrowdSec ipset pre-drop, and the loss of the DNAT rules.
- **Rule:** n/a — new-rule candidate: anything added to
  `networking.firewall.extraCommands` must fail soft, because the
  surrounding script does not.
- **Finding:** the NixOS iptables firewall renders its start script with
  `#! ${runtimeShell} -e` and appends `extraCommands` *immediately
  before* the two rules that actually arm the firewall. Verified against
  the realised script: `extraCommands` occupies lines 114-273 and
  `ip46tables -A INPUT -j nixos-fw` is line 281. Any non-zero exit in
  between means the jump is never installed. On a cold boot nothing
  retries `firewall.service`; on a reload, `reloadScript` explicitly
  falls back to `stopScript`, which deletes the INPUT jump and the
  rpfilter hook — i.e. the documented failure mode is fail-open.

  Two commands in this host's block have no guard:

  ```
  ${pkgs.ipset}/bin/ipset create -exist crowdsec-blacklists-0 hash:net family inet \
    hashsize 1024 maxelem 131072 timeout 300
  ```

  and its IPv6 twin at `:448`, plus the two rules that reference the
  sets (`:407`, `:455`), which fail with "Set … doesn't exist" if the
  create did.

  The comment at `:398-399` says the parameters "match the bouncer's own
  params exactly", and that is the load-bearing assumption. The pinned
  `ipset(8)` man page is explicit that `-exist` only suppresses the
  error "when the same set (setname **and create parameters are
  identical**) already exists". The bouncer's parameters are not pinned
  by anything in this repo: `services.crowdsec-firewall-bouncer` in the
  pinned nixpkgs sets only `blacklists_ipv4 = "crowdsec-blacklists"` /
  `blacklists_ipv6 = "crowdsec6-blacklists"`
  (`crowdsec-firewall-bouncer.nix:160-161`); everything else —
  `ipset_type`, `ipset_size`, `ipset_disable_timeouts`, the `-N` name
  suffix — comes from `cs-firewall-bouncer` 0.0.36's own defaults. A
  nixpkgs bump that moves that package, or any manual `ipset` created
  differently during troubleshooting, turns the next firewall reload
  into a total loss of the firewall.

  This is threat model §7.3 with the arrow reversed: the usual question
  is "is the control up before the thing it protects", and the honest
  answer here is worse — a failure in the *optional* control removes the
  *mandatory* one.
- **Proposed fix:** make the whole block fail soft.
  1. Append `|| true` to both `ipset create` lines **and** to the two
     `-m set --match-set … -j DROP` rules that depend on them, so a set
     mismatch degrades the ban layer instead of removing the firewall.
  2. Better: move the pre-creation out of `extraCommands` into a
     `systemd.services.crowdsec-ipset-precreate` oneshot with
     `Before = [ "firewall.service" ]` and `RequiredBy` deliberately
     *unset*, so its failure is visible and independent.
  3. Add `networking.firewall.extraStopCommands` to tear down the raw
     `vps-ratelimit` chain and its PREROUTING jump. Today
     `extraStopCommands` is non-empty (the nat module's `flushNat`) but
     touches only the nat and filter chains, so the raw chain survives a
     `systemctl stop firewall` and can persist across a parameter
     change.
  4. Have `myHealthAlerts` treat a failed `firewall.service` as a
     paging condition — it already watches failed units, so this may
     already be covered; confirm it is not filtered.
- **Fix risk:** (1) trades a loud failure for a silent one — rate
  limiting and the pre-drop would be absent with the box otherwise
  healthy. That is the right trade only if the alerting in (4) is real.
  Test in a VM by deliberately pre-creating the set with the wrong
  `maxelem` and confirming the firewall still comes up.

### F-P2-03 — a single spoofed packet lets any internet host put an arbitrary IP on vps's blocklist for up to 90 days

- **File:** `hosts/vps/configuration.nix:345`
  (`logRefusedConnections = true`), `:678-717` (the
  `vps-closed-port-scan` jail), `:722-726` (the `cscli` action);
  rendered `jail.local` and `filter.d/vps-closed-port-scan.conf`; pinned
  nixpkgs `firewall-iptables.nix:101-103` (the LOG rule) and `:126-146`
  (the rpfilter chain)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the config and the mechanism; PLAUSIBLE
  for how many transit networks will actually forward the spoofed
  packets.
- **Axis:** hardening
- **Reachability:** A1/A2 — one crafted TCP SYN per target, to any
  closed port on vps's public IPv4 or IPv6. No handshake, no
  authentication, no prior state, and under §4.7 the attacker has read
  the failregex, `maxretry = 1` and the escalation table before sending
  it.
- **Rule:** n/a — new-rule candidate.
- **Finding:** the jail's premise (`:704-706`: "any hit here is a probe
  of a port vps doesn't listen on — no legitimate traffic can trigger
  this filter, so ban on the very first match") is sound about
  *legitimate* traffic and silent about *forged* traffic. The trigger is
  the kernel's `refused connection:` LOG line, whose `SRC=` field is
  whatever the sender wrote in the IP header. Confirmed rendered
  failregex: `^refused connection: .*\sSRC=<HOST>\s`.

  Nothing upstream of that filters the source. `checkReversePath`
  evaluates to `"loose"` on this host (set by the tailscale module
  because `useRoutingFeatures != "none"`), so the mangle rpfilter chain
  runs `-m rpfilter --validmark --loose`, which accepts any source
  address that is reachable via *any* interface — for internet-routable
  addresses, all of them, via the default route on `ens3`.

  The consequence chain, all confirmed from the rendered config: one
  spoofed SYN → `maxretry = 1`, `findtime = 1d` → `actionban` runs
  `cscli decisions add --ip <forged> --duration 14400s` → the decision
  enters CrowdSec's list → `crowdsec-firewall-bouncer` puts it in
  `crowdsec-blacklists-0` / `crowdsec6-blacklists-0` → which is matched
  both by the bouncer's `CROWDSEC_CHAIN` in INPUT **and** by this host's
  raw-table `vps-ratelimit` chain at `:407`/`:455`. So a remote,
  unauthenticated attacker can blackhole a chosen third party from both
  the HTTPS entry point *and* the DNAT'd game ports, and with
  `bantime.increment` (`multipliers = "1 4 16 64 256 1024"`,
  `maxtime = "90d"`) can escalate a chosen address to a 90-day ban by
  repeating the packet six times over a day.

  Targets worth naming: Let's Encrypt's HTTP-01 validators (banning them
  breaks certificate renewal at `:80`, which surfaces 60-90 days later
  as an expired cert, far from the cause); DigitalOcean's own
  infrastructure; the game servers' actual player base, which is exactly
  the population §9 says the rate limiting exists to protect; and
  `10.100.0.2`, homelab's tunnel address, which loose rpfilter also
  accepts as a forged source.

  Admin lockout is *not* the risk here: SSH is tailnet-only,
  `crowdsec-allowlist-tailnet` (`:631-648`) exempts `100.64.0.0/10`, and
  `cscli decisions add` honours allowlists by default — confirmed by the
  presence of an explicit `-B, --bypass-allowlist` opt-out in
  `cscli 1.7.8`'s help, which the action does not pass. The risk is
  third-party blackholing and blocklist pollution.

  Two amplifiers, both reachable by the same packet stream. Each ban
  forks a `cscli` Go binary on a 1 vCPU / 1 GB droplet — serialised by
  fail2ban's per-jail action thread, so not an OOM, but a growing
  backlog and sustained CPU burn. And the LOG rule carries no
  `-m limit`, while `services.journald.rateLimitBurst` is 10000 per 30 s
  — so under a real scan the journal starts dropping exactly the
  messages the detector reads (PLAUSIBLE: whether journald buckets
  `_TRANSPORT=kernel` as one unit).
- **Proposed fix:** decision required; there is no clean fix that keeps
  the zero-threshold premise.
  - Cheapest correct step: stop feeding this jail's output into the same
    ipset the game ports consult. Give fail2ban its own decision origin
    and have the raw-table `--match-set` rule reference only
    CrowdSec-scenario-derived bans. This keeps the port-scan signal
    without letting a forged packet reach the game path.
  - Reduce the blast radius of a single packet: `maxretry` above 1
    (a real scanner trips it anyway; a spoofer must now send N packets
    per forged source, still cheap but no longer free), and a much
    shorter `bantime.maxtime` for this jail specifically — 90 days is a
    long time to trust a field an anonymous sender chose.
  - Add `ignoreip` for `10.100.0.0/24` and `100.64.0.0/10` (see also
    F-P2-11).
  - Or accept it and write down why: the reasoning would be that
    blackholing a third party costs the attacker a packet and costs us
    availability only, and availability is asset #6. That is defensible;
    it is just not currently recorded anywhere.
- **Fix risk:** raising `maxretry` weakens the "nothing legitimate lives
  here" premise the jail was built on, and it is the only detector
  watching kernel-level probes — CrowdSec's acquisitions read only the
  sshd and caddy journal units (`:539-552`), never the kernel log.
  Changing the ipset wiring must be tested against the game path
  specifically, since that is the only consumer of the raw-table match.

### F-P2-04 — fail2ban's unban deletes *all* CrowdSec decisions for the IP, including CrowdSec's own longer bans

- **File:** `hosts/vps/configuration.nix:722-726`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A1 — the ordinary case, not an edge case: any
  scanner that both probes closed ports (tripping fail2ban) and hits
  caddy or sshd (tripping CrowdSec) is affected, which describes most
  background noise.
- **Rule:** n/a
- **Finding:** the custom action is

  ```
  actionunban = <crowdsec>/bin/cscli decisions delete --ip <ip>
  ```

  Read from `cscli 1.7.8 decisions delete --help` in the pinned package:
  `--ip` is documented as "shorthand for `--scope ip --value <IP>`", and
  the filters that would narrow it — `--origin`, `--scenario`, `--type`,
  `--id` — are all optional and none is passed. So the command deletes
  every decision matching that IP regardless of who created it.

  The stated design (`:672-677`) is two detectors feeding one unified
  ban list. What actually happens is that the *shorter-lived* detector
  gets to expire the *longer-lived* one's decision. fail2ban's 4 h ban
  ending calls `actionunban`, which removes CrowdSec's concurrently
  running scenario ban for the same IP — and under the
  `duration_expr` at `:594`/`:604`
  (`Sprintf('%dh', int(min(4 ** (GetDecisionsCount(...) + 1), 2160)))`)
  a repeat offender's CrowdSec ban can be days or weeks. The two curves
  were carefully aligned (`:686-691` documents the effort), and this
  quietly resolves the overlap in favour of less protection. It also
  clears any CAPI/blocklist-origin decision for that IP, should the box
  ever be enrolled (see F-P2-15).
- **Proposed fix:** narrow the delete to fail2ban's own decisions:
  `cscli decisions delete --origin cscli --type ban --scope ip --value <ip>`.
  Or drop `actionunban` entirely — `actionban` already passes
  `--duration <bantime>s`, so CrowdSec expires the decision on its own
  timer without fail2ban's help. The second option is simpler and
  removes the interference completely; the cost is that fail2ban's view
  of "currently banned" and CrowdSec's can drift, which matters only for
  reporting.
- **Fix risk:** with `actionunban` removed, a manual `fail2ban-client
  unban` no longer clears the CrowdSec decision — document that
  `cscli decisions delete` is the manual lever. Verify `--origin cscli`
  is the right origin string for cscli-added decisions before choosing
  option one (the help text lists `cscli` among the valid origins).

### F-P2-05 — `health-check` on vps holds `disk` group membership and `CAP_SYS_RAWIO` with both consumers switched off

- **File:** `hosts/vps/configuration.nix:734-737`
  (`checkZfs = false; checkSmart = false`),
  `modules/nixos/health-alerts.nix:250-251` (the capabilities),
  `:275-279` (`extraGroups = [ "disk" ]`)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** needed-used + hardening
- **Reachability:** A1/A2 by chain — anything that achieves code
  execution as `health-check`. That unit runs every 15 minutes, shells
  out to `curl` and `jq`, and processes a response from a network
  endpoint. Membership in `disk` means read/write access to `/dev/vda*`,
  i.e. direct write access to the ext4 filesystems holding `/nix` and
  `/persist` — root, by a slightly longer route. `CAP_SYS_RAWIO` sits on
  top of that.
- **Rule:** violates `docs/hardening.md` "Dedicated service users" in
  spirit — the rule says to grant "only the specific group
  memberships/capabilities … actually needed", and here neither is
  needed at all.
- **Finding:** the module grants `disk` and `CAP_SYS_RAWIO`
  unconditionally, with a comment explaining that `smartctl`'s SG_IO
  ioctls require them. That reasoning is correct on homelab. On vps both
  `checkSmart` and `checkZfs` are `false` — deliberately, and with a
  good comment (`:741`: "this box has no real block devices for smartd
  to monitor", with `services.smartd.enable = lib.mkForce false`). So
  the grants have no consumer on the one host in the fleet that an
  internet attacker is working on. This is threat model §7.4 exactly,
  and §7.6 as well: the host-specific reasoning was applied to `smartd`
  and to the two `check*` flags, and not carried through to the
  privileges those flags exist to justify.
- **Proposed fix:** in `modules/nixos/health-alerts.nix`, gate both on
  the flag that needs them:
  `extraGroups = lib.optional cfg.checkSmart "disk";` and
  `AmbientCapabilities = lib.optional cfg.checkSmart "CAP_SYS_RAWIO";`
  (same for `CapabilityBoundingSet`, which should become `[ "" ]` when
  `checkSmart` is false). That fixes every host that sets the flag, not
  just vps. A host-local `lib.mkForce` in `hosts/vps/configuration.nix`
  is the narrower alternative if the module is out of P2's reach.
- **Fix risk:** none on vps. On homelab the grants stay because
  `checkSmart` is true there — verify that before landing, since a
  wrong-way change silently breaks SMART monitoring on the host that
  holds the backups.
- **Owner:** P2 for the vps instance; whoever owns
  `modules/nixos/health-alerts.nix` for the module fix (this affects
  every host that sets `checkSmart = false`).

### F-P2-06 — the raw-table rate limits are published, calibrated one to two orders of magnitude above legitimate traffic, and keyed on a spoofable field

- **File:** `hosts/vps/configuration.nix:393-460`, esp. `:405-436`;
  `:365-390` (the DNAT map); `docs/hardening.md` "Forwarded/DNAT'd ports
  get zero protection"
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the thresholds, the ordering and the
  spoofability; PLAUSIBLE for the comparison against real game-client
  packet rates and for the `xt_hashlimit` exhaustion behaviour.
- **Axis:** hardening
- **Reachability:** A1/A3 — any internet host. Under §4.7 the exact
  values are readable in this file, so an attacker tunes to sit just
  underneath them rather than discovering them by probing.
- **Rule:** satisfies `docs/hardening.md`'s "add per-source-IP rate
  limiting … as the floor for anything forwarded straight through" in
  letter. The finding is that the rule, as satisfied here, does not
  produce a security boundary — which is a gap in the rule as much as in
  the config.
- **Finding:** the chain is correctly built. It is in the `raw` table so
  it runs before conntrack and before the nat PREROUTING DNAT
  (confirmed against the rendered `firewall-start`: the host's block is
  lines 129-194, `nixos-nat-pre` is appended at line 270); the CrowdSec
  ipset DROP is first in the chain, before any hashlimit budget is
  spent, exactly as the comment claims; it is idempotent
  (`-N … || -F`, `-C … || -I`); and it re-runs on reload, because
  `reloadScript` calls `startScript` and `extraCommands` lives inside
  it. All of that checks out. Three things do not.

  **The thresholds are permissive.** Read as published:

  | Port | Limit | Sustained allowance, per source IP |
  |---|---|---|
  | 25565/tcp (Minecraft) | `15/minute`, burst 10 | 15 new TCP connections per minute, forever |
  | 19132/udp (Geyser/Bedrock) | `1000/second`, burst 500 | 1000 packets/second, forever |
  | 34197/udp, 34198/udp (Factorio) | `2000/second`, burst 1000 | 2000 packets/second, forever |
  | 80,443/tcp | `120/minute`, burst 60 | 2 new connections/second, forever |

  A steady-state Minecraft or Factorio client sits in the tens of
  packets per second. 1000-2000 pps per source is therefore roughly one
  to two orders of magnitude above what a real player generates
  (PLAUSIBLE — protocol rates from general knowledge, not measured).
  A single source can deliver that indefinitely, straight through to
  homelab's game-server protocol parsers, without the rule ever
  matching. From a /24 it is 256 times that.

  **The key is attacker-chosen for the UDP ports.** `--hashlimit-mode
  srcip` and the `--match-set … src` drop both key on the source
  address. 19132, 34197 and 34198 are UDP: no handshake, so an attacker
  who randomises the source address gets a fresh hashlimit bucket per
  packet and never appears in the CrowdSec set at all. `checkReversePath
  = "loose"` does not stop this (see F-P2-03 for the same mechanism).
  So for the three UDP game ports, *both* controls in the chain are
  bypassable at the attacker's option. Only 25565/tcp is protected by
  needing a completed handshake.

  **The HTTP limit counts connections, not requests.** `--syn` means the
  rule sees one packet per TCP connection. HTTP/1.1 keep-alive or HTTP/2
  multiplexing delivers unbounded request volume inside a single
  connection that costs one SYN. "120/minute" therefore reads much
  stronger than it is. The actual request-rate controls on that path are
  anubis's proof-of-work and CrowdSec's caddy scenarios, both of which
  are real — but the raw chain should not be counted as a third.

  Additionally, no `--hashlimit-htable-max` or `--hashlimit-htable-expire`
  is set, so the hash tables grow to the kernel's defaults. On table
  exhaustion `xt_hashlimit` is believed to `hotdrop`, dropping *every*
  packet matching the rule rather than only over-limit ones — i.e. an
  attacker who fills the table with forged sources takes the game port
  down for everyone. PLAUSIBLE; I did not read the pinned kernel source.
- **Proposed fix:** the important part is not the numbers.
  - **Record what this control is.** It is a volumetric floor that keeps
    a single misbehaving client from saturating the tunnel. It is not an
    authentication boundary and it does not survive a source-randomising
    attacker. Threat model §4.6 already says the game servers' own
    hardening is load-bearing for vps's boundary; `docs/hardening.md`'s
    rule should say the same, so that satisfying it is not mistaken for
    closing the gap.
  - Bound the tables explicitly: add `--hashlimit-htable-max` and
    `--hashlimit-htable-expire` to each rule so growth is capped and the
    exhaustion behaviour is not left to defaults.
  - Consider a second, *global* (non-per-source) `-m limit` ceiling per
    UDP port as a backstop that spoofing cannot evade, sized well above
    the expected total player load.
  - Do not lower the per-source numbers without a measurement of what
    real clients actually send; guessing low here breaks play, which is
    the failure mode that gets a control removed entirely.
- **Fix risk:** a global ceiling is shared across all players, so
  sizing it wrong is a self-inflicted outage during a busy session. Any
  change here can only be validated with a real game client on a real
  path — the repo's own TODO notes this class of item tends to linger
  unverified.
- **Owner:** P2 for the vps side; **P4 owns the consequence** — see the
  handoff note at the end of this report.

### F-P2-07 — `trustedInterfaces = [ "tailscale0" ]` bypasses the packet filter wholesale

- **File:** `hosts/vps/configuration.nix:341`; rendered
  `firewall-start` line 70 (`ip46tables -A nixos-fw -i tailscale0 -j
  nixos-fw-accept`, the first rule in the chain)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A5 — any tailnet device. Compounds F-P0-04: the ACL
  is flat (`"ip": ["*"]` device-to-device, including vps), so tailnet
  membership alone reaches every port on this host.
- **Rule:** n/a — new-rule candidate; §2.2's established pattern is
  `openFirewall = false` plus
  `networking.firewall.interfaces.<iface>.allowedTCPPorts`, and this is
  the same class of host-wide grant that pattern exists to replace.
- **Finding:** confirmed from the realised script that the trusted-
  interface accept is emitted before the conntrack rule and before every
  port rule, so it is an unconditional bypass rather than a broad
  allowance. From the tailnet, vps has no packet filter: sshd, caddy on
  80/443, CrowdSec's LAPI on 127.0.0.1:8080 (not reachable — bound to
  loopback), caddy's admin API on 127.0.0.1:2019 (likewise), and
  anything a future service binds to `0.0.0.0` without thinking about
  it. The last is the real cost: the setting silently converts every
  future "bind to all interfaces" default into a tailnet-wide exposure.

  What actually needs to be open on `tailscale0` today is port 22.
  Everything else that matters is either public by design (80/443) or
  loopback-bound.

  Note that this line is also load-bearing for something else: the
  comment at `:618-621` reasons that the CrowdSec tailnet allowlist is
  "not a new trust boundary" *because* `trustedInterfaces` already
  treats tailscale0 as trusted. That reasoning is sound but it means the
  two settings are coupled — narrowing this one changes the allowlist's
  justification and, more concretely, starts producing
  `refused connection:` log lines for tailnet traffic that currently
  produces none.
- **Proposed fix:**
  ```nix
  networking.firewall.trustedInterfaces = lib.mkForce [ ];
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  ```
  (`lo` is added to `trustedInterfaces` by the firewall module itself and
  is unaffected.)
- **Fix risk:** real, and this should be tested in a VM before it goes
  near the live box. Anything currently reaching vps over the tailnet
  that is not port 22 will break, and it will break in a way that is
  invisible until someone tries it. Once tailscale0 is no longer
  trusted, refused connections from the tailnet start hitting the
  `vps-closed-port-scan` jail; the CrowdSec allowlist covers
  `100.64.0.0/10` so no ban should result, but that interaction must be
  confirmed rather than assumed, because the failure mode is banning
  yourself off the only SSH path to the box. Keep the DigitalOcean
  console open.
- **Owner:** P2, with P8 (the ACL) — §8.1 is the same question.

### F-P2-08 — `crowdsec-allowlist-tailnet` is a custom root unit with no sandboxing, against the repo's own baseline

- **File:** `hosts/vps/configuration.nix:631-648`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** no demonstrated exploit. Rated MEDIUM under §6's
  "violations of an existing `docs/hardening.md` rule with no currently
  demonstrable exploit — the rule exists because the class is real".
- **Rule:** violates `docs/hardening.md` "Dedicated service users" (runs
  as root with no `User=` and no recorded justification) **and** "Custom
  `systemd.services` sandboxing" (no `NoNewPrivileges`, no
  `ProtectSystem`, none of the stack).
- **Finding:** the unit's `serviceConfig` is `Type`, `RemainAfterExit`,
  `Restart`, `RestartSec`, `ExecStart` — nothing else. It therefore runs
  as root, unsandboxed, on the internet-facing host. Every other custom
  unit in this repo carries the full stack; `health-check` in
  `modules/nixos/health-alerts.nix:243-261` is the in-repo template.

  Root is not required. The script does two things: read
  `/etc/crowdsec/config.yaml` (a symlink into the world-readable Nix
  store, created by the tmpfiles rule at `:665-669`) and talk to the
  LAPI on `127.0.0.1:8080` using
  `/var/lib/crowdsec/local_api_credentials.yaml`, which tmpfiles creates
  `0750 crowdsec:crowdsec` (pinned `crowdsec.nix:838-856`). Setting
  `User = "crowdsec"; Group = "crowdsec"` covers both, and
  `services.crowdsec.user` resolves to a real static system user
  (`crowdsec.nix:963`), not a name that only exists under `DynamicUser`.

  The `docs/hardening.md` discussion of `runuser` and
  `CapabilityBoundingSet` applies to fail2ban's *action*, which runs
  inside someone else's unit and cannot choose its own UID. It does not
  apply here — this is our own unit and `User=` is available. The script
  already does the right thing on the other half of that rule by calling
  `${config.services.crowdsec.package}/bin/cscli` by absolute store path
  rather than the wrapped `cscli` on `PATH`.
- **Proposed fix:**
  ```nix
  serviceConfig = {
    User = config.services.crowdsec.user;
    Group = config.services.crowdsec.group;
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    PrivateTmp = true;
    CapabilityBoundingSet = [ "" ];
    # …existing Type/RemainAfterExit/Restart/RestartSec/ExecStart
  };
  ```
  `ProtectSystem = "strict"` needs no `ReadWritePaths` — the unit writes
  nothing to disk; the allowlist lives in CrowdSec's own database via
  the LAPI.
- **Fix risk:** if `cscli` turns out to need a writable state or cache
  path, `ProtectSystem = "strict"` will surface it as a failure at unit
  start. That is a VM-testable change; the unit is idempotent
  (`create … || true`, `add` warns and skips on duplicates, per the
  comment at `:626-629`) so re-running it during testing is safe.

### F-P2-09 — the sshd `extraConfig` block contains two inert directives, and the one that matters most is written in the form that cannot take effect

- **File:** `hosts/vps/configuration.nix:321-331`; pinned nixpkgs
  `services/networking/ssh/sshd.nix:82-88` (`configFile` from `settings`
  is `cat`'d *before* `extraConfig`)
- **Severity:** LOW
- **Confidence:** CONFIRMED — read from the realised
  `…-sshd.conf-final`
- **Axis:** hardening
- **Reachability:** none today; the effective configuration is correct.
  The finding is that the highest-value directive on this host is sited
  where changing it would do nothing.
- **Rule:** conforms to `docs/hardening.md` "SSH" in effect. §7.2 is the
  concern.
- **Finding:** the module emits its `settings`-derived block first and
  appends `extraConfig` after it, and `sshd_config` is first-directive-
  wins. Line-by-line against the rendered file (module block = lines
  1-19, `extraConfig` = lines 20-28):

  | Directive | Where | In force? |
  |---|---|---|
  | `PermitRootLogin = prohibit-password` | extraConfig, line 20 | **No** — module already emitted `PermitRootLogin prohibit-password` at line 10 |
  | `AllowTcpForwarding no` | extraConfig, line 21 | Yes — module emits no default |
  | `X11Forwarding no` | extraConfig, line 22 | **No** — module already emitted it at line 15 |
  | `AllowAgentForwarding no` | line 23 | Yes |
  | `AllowStreamLocalForwarding no` | line 24 | Yes |
  | `AuthenticationMethods publickey` | line 25 | Yes |
  | `PermitTunnel no` | line 26 | Yes |
  | `ClientAliveInterval 60` | line 27 | Yes |
  | `ClientAliveCountMax 5` | line 28 | Yes |

  So the behaviour is right: root login is `prohibit-password`,
  X11 forwarding is off, and the six directives that genuinely need
  `extraConfig` are all in force. Two observations remain.

  `PermitRootLogin` is the one directive on this host that controls
  whether an interactive root shell exists at all, and it is written in
  the one place that cannot change it. If someone tightened that line to
  `no` for a maintenance window, the file would say `no`, the rendered
  config would still say `prohibit-password` on line 10, and sshd would
  still permit key-based root login. That is precisely the shape of the
  `PasswordAuthentication` bug that triggered this audit — same file,
  same block, one directive over.

  It is also the only directive written with an `=`. That parses fine
  (`sshd_config(5)`: options "may be separated by whitespace or optional
  whitespace and exactly one `=`"), so it is not a bug today, but it is
  a tell that the line was written in Nix syntax rather than sshd
  syntax, and it makes the whole block harder to read as what it is.
- **Proposed fix:** move `PermitRootLogin` to the structured option,
  where it will actually win, and delete the duplicate `X11Forwarding`:
  ```nix
  settings.PermitRootLogin = "prohibit-password";
  extraConfig = ''
    AllowTcpForwarding no
    AllowAgentForwarding no
    AllowStreamLocalForwarding no
    AuthenticationMethods publickey
    PermitTunnel no
    ClientAliveInterval 60
    ClientAliveCountMax 5
  '';
  ```
- **Fix risk:** none — the rendered value is unchanged. Diff the
  resulting `sshd.conf-final` before and after to prove it.

### F-P2-10 — F-P0-02 confirmed: the dispatcher bounds shells and accidents, not root — and it is public source

- **File:** `hosts/vps/configuration.nix:13-98` (esp. `:34-37`,
  `:62-68`), `:290-301` (the account and its key), `:303-311` (the
  polkit rule), `:313` (`trusted-users`),
  `docs/procedures/remote-access.md`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** documentation
- **Reachability:** n/a — nothing is exploitable here that the design
  does not already grant. Under §4.7 the source is public, so this was
  audited as fully-disclosed hostile-input handling: an attacker reads
  the same 85 lines, offline, with no rate limit.
- **Rule:** new-rule candidate — §7.5.
- **Finding:** P0 asked P2 to confirm the dispatcher reading. Confirmed,
  with the mechanism made explicit and six residual observations.

  **Root is granted, and here is exactly how.** The dispatcher's two
  privileged branches call `/run/current-system/sw/bin/sudo`. There is
  no real sudo on this host — `security.sudo.enable = false`
  (`modules/profiles/server.nix:21`). That binary is the run0 shim:
  `security.run0.enable` and `security.run0.sudo-shim.enable` both
  evaluate to `true`, and `run0-sudo-shim-1.4.2` ships `bin/sudo`. run0
  elevates through systemd's `StartTransientUnit`, gated by the polkit
  action `org.freedesktop.systemd1.manage-units` — which is exactly the
  action the repo's polkit rule at `:303-311` returns `YES` for, for
  `vps-deploy`. That this is the run0 gate is not inference: the pinned
  `nixos/modules/security/run0.nix:76-82` grants the identical action to
  make run0 passwordless for `wheel`. So the polkit rule is not
  "vps-deploy can restart units"; it is "vps-deploy can run anything as
  root", as the comment at `:302` half-concedes. Combined with
  `switch-to-configuration` being executed from a store path the client
  chose, and `nix.settings.trusted-users` letting that client write any
  closure into the store unsigned, F-P0-02's conclusion holds exactly:
  **homelab is trusted with root on vps, by design, and there is no
  boundary between them.**

  **The stated bound does hold.** `docs/procedures/remote-access.md`'s
  claim that the key "can never get an interactive shell" is true, and I
  checked the two ways it could have been false:
  - `restrict` in the rendered `authorized_keys` line. Per the pinned
    `openssh-10.4p1` `sshd(8)`: "Enable all restrictions, i.e. disable
    port, agent and X11 forwarding, as well as disabling PTY allocation
    and execution of `~/.ssh/rc`. If any future restriction capabilities
    are added to authorized_keys files, they will be included in this
    set." No tunnels, no forwarding, no pty.
  - A second key. `authorizedKeysFiles` is
    `["%h/.ssh/authorized_keys", "/etc/ssh/authorized_keys.d/%u"]`;
    vps-deploy's home is `/var/empty` with `createHome = false`, and
    `nixos/modules/system/activation/activation-script.nix:278-279`
    renders `D /var/empty 0555 root root` plus
    `h /var/empty - - - - +i` — mode 0555 *and* the immutable attribute.
    The `/etc/ssh/authorized_keys.d/vps-deploy` file is a root-owned
    `0444` store symlink. vps-deploy cannot install a key.

  **No injection, and `set -eu` is used correctly.** Nothing passes
  `$cmd` to a shell. Every branch `exec`s a fixed argv with
  `"$store_path"` quoted, verified against the realised script. An unset
  `SSH_ORIGINAL_COMMAND` (an interactive attempt) aborts on `set -u`
  before any branch. The `store_path=$( … | grep -oE … | head -n1 ) ||
  store_path=""` idiom is safe: without `pipefail` the pipeline's status
  is `head`'s, so a non-matching `grep` yields an empty string rather
  than the `||` branch — same result either way, and every branch that
  consumes it calls `require_store_path` first.

  **Six residual observations**, none exploitable by this principal, all
  worth recording because the file is public and will be read as the
  reference implementation:

  1. *Path traversal is bounded only incidentally.* The regex tail
     `[0-9A-Za-z._-]+` excludes `/`, so the worst construction is
     `/nix/store/<hash>-nixos-system-vps-../bin/switch-to-configuration`,
     which resolves to `/nix/store/bin/…` and does not exist. The bound
     comes from a character happening to be absent from a class, not
     from an explicit check. Anchoring with `$` or re-validating the
     extracted path with a `case` would make the property intentional.
  2. *The most powerful branch is first, wildcarded on both sides, and
     needs no store path.* `*"nix-store --serve --write"*` matches that
     substring anywhere in the command string. The branch is necessary —
     it is the deploy mechanism — but its position means any command
     that merely mentions the phrase gets a serve session.
  3. *`nix-store --serve --write` grants more than importing closures.*
     The serve protocol's write mode also exposes `BuildPaths` and
     `BuildDerivation`, i.e. remote builds. Those run inside
     nix-daemon's sandbox, so this is not an escape — but on a 1 vCPU /
     1 GB droplet with an 18 GB `/nix`, it is a CPU/disk exhaustion
     channel that has nothing to do with deploying. Marginal, since the
     key holder already has root.
  4. *`*"systemctl reboot"*` also needs no store path* and matches the
     substring anywhere, so a command string that merely contains those
     words reboots the box. Contrast the `minSwitchInterval` branch,
     which is written as an exact match with a comment explaining why —
     the author clearly knew the difference, which suggests the
     wildcards elsewhere were accepted rather than chosen.
  5. *Branch order is otherwise fail-safe.* A string containing both
     `switch-to-configuration switch` and `test -d /run/systemd/system`
     runs only the harmless test, because the test branch is earlier.
     Fine as far as it goes.
  6. *One runtime-resolved path in an otherwise store-pinned script.*
     Every other `exec` target is an absolute store path baked in at
     build time; `sudo` is `/run/current-system/sw/bin/sudo`. Which
     binary runs therefore depends on the *currently activated*
     generation, not on the generation that contains the dispatcher — so
     a deploy that changed the sudo shim would change the elevation
     semantics of the deploy that installs it.

  The value the dispatcher does deliver — no shell, no forwarding, no
  arbitrary command — is real and worth keeping. Observations 2 and 4
  degrade the *other* thing it delivers, which is accident containment,
  and that is unaffected by who else can read the file.
- **Proposed fix:** documentation, per F-P0-02. Reword
  `docs/procedures/remote-access.md` to say the allowlist bounds shells
  and non-deploy commands, and to state plainly that homelab holds root
  on vps via the polkit `manage-units` grant and the run0 sudo alias —
  naming that mechanism, since "the account's polkit grant (which is
  necessarily coarse)" currently understates it. Optionally tighten the
  two unbounded branches to exact matches for accident containment, and
  anchor the store-path regex.
- **Fix risk:** none for the doc. Tightening the `case` patterns risks
  breaking deploys if `nixos-rebuild`'s exact command strings differ
  from what is assumed — `modules/nixos/push-deploy.nix:114-139` shows
  the four commands the repo sends directly, but the ones
  `nixos-rebuild --target-host --sudo` generates internally are not
  pinned by anything and change between nixpkgs releases. That is
  probably why the wildcards are there. Any change needs a real deploy
  test, not a build test.
- **Owner:** P2 (confirmed here); Phase 4 for the doc change.

### F-P2-11 — the WireGuard subnet is exempt from nothing

- **File:** `hosts/vps/configuration.nix:341` (wg0 is *not* a trusted
  interface), `:345`, `:631-648` (allowlist covers only
  `100.64.0.0/10`); rendered `jail.local`
  (`ignoreip = 127.0.0.1/8 ::1`)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** self-inflicted — any TCP connection homelab makes to
  a closed port on vps over the tunnel.
- **Rule:** n/a
- **Finding:** `10.100.0.0/24` appears in neither fail2ban's `ignoreip`
  nor CrowdSec's allowlist, and `wg0` is not in `trustedInterfaces`. So
  a connection from homelab to any port vps does not open on the tunnel
  produces a `refused connection:` kernel log line and bans `10.100.0.2`
  on the first packet, escalating on repeats.

  Impact today is nil, and I checked why rather than assuming: vps opens
  no ports on wg0, and the DNAT'd game traffic returns through FORWARD
  and conntrack, not INPUT, so a ban on `10.100.0.2` does not touch it.
  The WireGuard transport itself runs between the hosts' public
  addresses, so the tunnel stays up too.

  It is still worth fixing, because it is the same self-ban class the
  config already had to work around once — the comment at `:610-617`
  records that rapid diagnostic SSH banned the admin's own IP live on
  2026-08-26 — and because the impact goes from nil to real the moment
  anything is opened on wg0, which is one line of config away.
- **Proposed fix:** add `10.100.0.0/24` to the
  `crowdsec-allowlist-tailnet` unit (renaming it, since it would then
  cover two ranges) and to `services.fail2ban.ignoreip`. The
  justification is the same one already written for the tailnet: this is
  not a new trust boundary, it is a cryptographically authenticated
  peer.
- **Fix risk:** none meaningful — it removes a ban path for a peer that
  is already trusted with root on this host by design (F-P2-10).

### F-P2-12 — the raw rate-limit chain is scoped to `ens3` while the port openings are host-wide

- **File:** `hosts/vps/configuration.nix:744-751` (host-wide
  `allowedTCPPorts`/`allowedUDPPorts`), `:10` and `:409-410`, `:451-452`
  (`-i ens3` on the raw chain), `hosts/vps/README.md` (the interface
  inventory)
- **Severity:** LOW
- **Confidence:** CONFIRMED for the asymmetry; PLAUSIBLE for who can
  actually reach `ens4`.
- **Axis:** hardening
- **Reachability:** A2/A4-shaped — another host on the DigitalOcean
  private network. Modern DO VPCs are account-scoped, which makes this
  narrow, but nothing in this repo establishes or documents that.
- **Rule:** threat model §7.1 — "a rule scoped to the host rather than
  to an interface, justified by a belief about the network".
- **Finding:** `allowedTCPPorts = [ 80 443 ]` and
  `allowedUDPPorts = [ 51820 ]` are host-wide, so they open on every
  address vps holds. Per `README.md` that is the public IPv4, the public
  IPv6, a private DigitalOcean VPC address on `ens3`, and a second
  private network on `ens4`. The raw-table `vps-ratelimit` chain hooks
  only `-i ens3`. So traffic arriving on `ens4` reaches caddy and
  WireGuard with no hashlimit and no CrowdSec ipset pre-drop. The
  bouncer's own `CROWDSEC_CHAIN` in INPUT still applies, so bans are not
  bypassed — only the pre-conntrack burst layer is.

  §2.2 lists these three ports as "the one legitimate use" of the
  host-wide form, and that is right about the *public* address. It was
  written on the assumption that the public address is the only one that
  matters. Nothing in this repo configures `ens4` — cloud-init does —
  so its addressing is not visible from the config, which is the
  §7.1 pattern exactly.
- **Proposed fix:** scope the openings to the interface they are meant
  for:
  ```nix
  networking.firewall.allowedTCPPorts = lib.mkForce [ ];
  networking.firewall.allowedUDPPorts = lib.mkForce [ ];
  networking.firewall.interfaces.ens3.allowedTCPPorts = [ 80 443 ];
  networking.firewall.interfaces.ens3.allowedUDPPorts = [ 51820 ];
  ```
  This also makes the `-i ens3` scoping of the raw chain consistent with
  the port rules instead of accidentally narrower.
- **Fix risk:** if any address vps serves from actually lives on `ens4`
  (the config does not say), this takes it offline. Confirm the live
  interface/address map first — `README.md` describes it but the config
  does not encode it, which is itself part of the problem.

### F-P2-13 — `sops.secrets.vps_caddy_env` is declared, decrypted at every boot, and read by nothing

- **File:** `hosts/vps/configuration.nix:477`
- **Severity:** INFO
- **Confidence:** CONFIRMED — `services.caddy.environmentFile`
  evaluates to `null`
- **Axis:** needed-used
- **Reachability:** none
- **Rule:** threat model §7.4
- **Finding:** the secret is declared with a `# TODO: populate with DNS
  provider API token if using DNS-01 challenges` comment. Nothing
  consumes it: caddy has no `environmentFile`, and the Caddyfile uses no
  DNS-01 challenge. So sops decrypts a key into `/run/secrets` on every
  boot for no reader, and `secrets/secrets.yaml` carries an entry that
  must exist or activation fails. It is also one more thing inside the
  blast radius of F-P2-01.
- **Proposed fix:** delete the declaration and the `vps_caddy_env` key,
  or wire it up. If DNS-01 is genuinely wanted (it would let the apex
  and any future subdomain get certs without exposing `:80`, and would
  make the HTTPS/SNI gap at `:494-498` easier to close), that is a small
  piece of real work rather than a TODO.
- **Fix risk:** none. Removing a sops secret requires the corresponding
  `secrets.yaml` edit, which is user-only.

### F-P2-14 — inherited config with no consumer on a 1 vCPU / 1 GB droplet

- **File:** `modules/profiles/default.nix:115-117` (binfmt), `:101`
  (fwupd), `:123` (`enableAllFirmware`), `:126` (`nix.nixPath`), `:23-48`
  (systemPackages); effective on vps
- **Severity:** INFO
- **Confidence:** CONFIRMED for the effective values; PLAUSIBLE for the
  disk-cost estimates
- **Axis:** needed-used
- **Reachability:** A1/A2 as post-exploitation surface, not as an entry
  point
- **Rule:** threat model §7.4
- **Finding:** vps inherits the shared default profile wholesale. Four
  items have no consumer here, on the host with the tightest resource
  budget and the largest attack surface:
  - `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` — registers a
    root-installed binfmt handler so that any aarch64 ELF on the box
    becomes directly executable via qemu-user. The README says never
    build on vps; nothing cross-compiles here. This is added executable
    surface with zero use.
  - `services.fwupd.enable = true` — a root D-Bus daemon for flashing
    firmware, on a KVM guest with no firmware to flash.
  - `hardware.enableAllFirmware = true` — a large firmware tree on a
    25 GB disk with an 18 GB `/nix`.
  - `nix.nixPath = [ "nixpkgs=${inputs.nixpkgs-unstable}" ]` — pins a
    full nixpkgs source tree into vps's closure for a host that must
    never evaluate anything.
  - `environment.systemPackages` brings `ffmpeg`, `flac`,
    `bitwarden-cli`, `topgrade`, `smartmontools` and `zfs-prune-snapshots`
    to the edge host. `smartmontools` is contradicted two hundred lines
    away by `services.smartd.enable = lib.mkForce false` and by
    `checkSmart = false`; `bitwarden-cli` on the internet-facing box is
    the one worth a second look.

  Also inherited and inert: `services.crowdsec`'s prometheus exporter is
  on at `127.0.0.1:6060` (from the module's defaults) with nothing
  scraping it.
- **Proposed fix:** either `lib.mkForce` these off on vps, or — better —
  move them out of `profile-default` into `profile-pc`, since binfmt,
  fwupd, all-firmware and the media tools are desktop concerns. That is
  a shared-profile change, so it belongs with P1.
- **Fix risk:** low individually, but moving things out of the shared
  profile touches every host; do it as one reviewed change rather than
  four.
- **Owner:** P2 flags the vps effect; P1 owns `profile-default`.

### F-P2-15 — CrowdSec's detection ruleset is fetched from the internet at every service start and is not pinned

- **File:** `hosts/vps/configuration.nix:533-537` (`hub.collections`);
  pinned nixpkgs `services/security/crowdsec.nix:553-562` (the
  `ExecStartPre` setup script), effective
  `settings.general.cscli.hub_branch = "master"`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** hardening / documentation
- **Reachability:** A6 — the CrowdSec hub is an upstream this host
  executes rules from.
- **Rule:** no written rule, but it cuts against the repo's
  declarative-first posture; new-rule candidate for
  `docs/hardening.md`.
- **Finding:** `crowdsec.service`'s `ExecStartPre` runs
  `cscli hub update` followed by
  `cscli collections install crowdsecurity/{linux,sshd,caddy}` on every
  start, against `hub_branch = "master"`. The effective parsers and
  scenarios on the edge host are therefore whatever the hub served at
  boot time, evaluated as `expr` rules inside the crowdsec process, and
  they are not reproducible from this repo. This is also the confirmed
  cause of the boot race the config works around at `:570-579`.

  Two mitigating facts, both real: `autoUpdateService` is off, so there
  is no daily unattended pull, and the crowdsec unit is well sandboxed
  in the pinned module (`DynamicUser`, `CapabilityBoundingSet` reduced
  to `CAP_SYSLOG`, `ProtectSystem = "strict"`, a `SystemCallFilter`).
  So the blast radius of a hostile hub entry is "bad or absent
  detection", not "code execution as root".

  Related, and worth knowing before anyone enrols the box: the effective
  `settings.general.api.server.online_client` has `sharing: true` and
  `pull: { blocklists: true, community: true }`, with
  `credentials_path: null`. That is inert today because vps is not
  registered with the Central API. If anyone runs `cscli capi register`,
  vps starts shipping alert metadata — attacker IPs, scenario names,
  timing — to CrowdSec's cloud, and starts pulling a remote blocklist
  into the same ipset the game ports consult (F-P2-03's path, with a
  third party choosing the entries).
- **Proposed fix:** no pinning mechanism exists upstream, so the honest
  fix is documentation: record in `docs/hardening.md` that the edge
  host's detection rules are fetched at runtime from an unpinned
  upstream, that this is accepted because the alternative is stale
  detection, and that the sandboxing above is the compensating control.
  Separately, note the CAPI flags so enrolling is a decision rather than
  a default.
- **Fix risk:** none; documentation.

### F-P2-16 — caddy's admin API is reachable from anubis

- **File:** rendered Caddyfile (no `admin` directive; `enableReload`
  evaluates to `true`), `hosts/vps/configuration.nix:468-474` (anubis),
  pinned `services/networking/anubis.nix:404-441`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the exposure; PLAUSIBLE for the chain
- **Axis:** hardening
- **Reachability:** A1/A2 by chain — anubis is a Go HTTP service sitting
  directly in the path of untrusted internet traffic (it is the
  outermost thing in front of jellyfin, by design). Its unit is
  well-sandboxed by the pinned module but has
  `RestrictAddressFamilies = [ AF_UNIX AF_INET AF_INET6 ]` and no
  network address restriction, so it can open TCP connections to
  `127.0.0.1`.
- **Rule:** n/a
- **Finding:** caddy's admin API listens on `127.0.0.1:2019` by default
  and neither the global options block nor the module disables it —
  `services.caddy.enableReload = true` depends on it. That API can
  replace caddy's entire running configuration: a compromise of anubis
  becomes control of the TLS terminator, which means arbitrary
  reverse-proxy targets, a `file_server` rooted anywhere caddy can read
  (including `/var/lib/caddy`, where the ACME account key and
  certificates live), and MITM of jellyfin.

  anubis genuinely needs outbound TCP — its `TARGET` is
  `http://10.100.0.2:8096` — so the address families cannot simply be
  dropped. But the destination can be pinned.
- **Proposed fix:** constrain anubis to the one address it needs:
  ```nix
  systemd.services.anubis-jellyfin.serviceConfig = {
    IPAddressDeny = "any";
    IPAddressAllow = [ "10.100.0.2" ];
  };
  ```
  This blocks `127.0.0.1:2019` while leaving the unix socket (AF_UNIX is
  unaffected by `IPAddress*`) and the jellyfin upstream working. An
  alternative or complement is moving caddy's admin endpoint to a unix
  socket via `services.caddy.globalConfig`.
- **Fix risk:** `IPAddressAllow`/`IPAddressDeny` are BPF-based and apply
  to the whole cgroup; if anubis needs DNS or any other egress the unit
  will fail closed with connection errors that are easy to misdiagnose
  as an anubis bug. Test in a VM with a real request through caddy, not
  just a unit start.

### F-P2-17 — the caddy/anubis ordering fix is correct; its stated reason is not

- **File:** `hosts/vps/configuration.nix:480-487`; pinned
  `services/networking/anubis.nix:364-373`
- **Severity:** INFO
- **Confidence:** CONFIRMED for the module behaviour; PLAUSIBLE for the
  real cause of the observed 502s
- **Axis:** documentation
- **Reachability:** none
- **Rule:** §7.3 / §7.5-shaped
- **Finding:** the comment states that anubis's `anubis` group "is
  transient (`DynamicUser = true`): it only exists while
  anubis-jellyfin.service is active". Against the pinned nixpkgs that is
  not true — the module declares `users.users.anubis` and
  `users.groups.anubis` statically when the user and group are left at
  their defaults, which they are here, and the effective config shows
  `users.groups.anubis.members = [ "caddy" ]` with a persistent GID
  (stable across reboots because `/var/lib/nixos` is persisted at
  `:250`).

  The 502s were real and the fix is right; the mechanism was almost
  certainly the unix socket itself. The socket lives under
  `RuntimeDirectory = "anubis/anubis-jellyfin"`, which does not exist
  until the unit starts, so a caddy that started first got
  connection-refused on
  `/run/anubis/anubis-jellyfin/anubis.sock`. `after` + `wants` fixes
  exactly that. Leaving the wrong explanation in place means the next
  person reasons from a false model of how `DynamicUser` and static
  users interact — and that interaction is subtle enough to be worth
  getting right in writing.

  Worth recording alongside it: the socket permissions are sound.
  anubis's `--socket-mode` default is `0770`, the runtime directory is
  `0755` and traversable, and `caddy` is in the `anubis` group — so the
  socket is group-reachable and not world-reachable. And the ordering is
  `wants`, not `requires`, so a failed anubis still lets caddy start and
  serve the `:80` catch-all rather than taking the whole front end down.
  Both are the right calls and neither is currently explained.
- **Proposed fix:** correct the comment to name the socket, not the
  group, as the thing that does not exist yet; keep the ordering; add a
  sentence on why `wants` rather than `requires`.
- **Fix risk:** none; comment only. Do not remove the ordering.

### F-P2-18 — cloud-init keeps a root-code-execution channel from DigitalOcean open on every boot, and it is not recorded as an accepted risk

- **File:** `hosts/vps/configuration.nix:132-143` (the datasource and
  module lists), `:224-243` (the exec-capable tmpfs)
- **Severity:** INFO
- **Confidence:** CONFIRMED that the boothook executes (the repo's own
  comment documents the live `noexec` failure that proved it);
  PLAUSIBLE for the part-handler mechanism
- **Axis:** hardening / documentation
- **Reachability:** DigitalOcean. §9 places the hypervisor out of scope,
  which is why this is INFO and not higher.
- **Rule:** new-rule candidate
- **Finding:** the cloud-init configuration here is unusually tight and
  most of it deserves credit: `datasource_list = [ "ConfigDrive" ]` uses
  the hypervisor-attached local device rather than the
  `169.254.169.254` HTTP metadata service, `cloud_init_modules` is cut
  to `[ "seed_random" ]`, `cloud_config_modules` and
  `cloud_final_modules` are emptied outright, and
  `preserve_hostname = true` stops DO from renaming the host. That
  disables `write-files`, `runcmd`, `users-groups`, `ssh` and the rest.

  What it does not disable is vendor-data *boothooks*, which are handled
  by cloud-init's part-handlers during the init stage independently of
  those module lists — and the config explicitly carves
  `/var/lib/cloud` out of the root tmpfs as its own exec-capable
  filesystem so that they can run, because without it the droplet never
  came up. So DigitalOcean retains the ability to execute an arbitrary
  script as root on this host at every boot, and the config is
  deliberately arranged to permit it.

  The narrowing is well done: the carve-out is one path, `nosuid`,
  `nodev`, root-owned `0755`, 64 MB, rather than loosening the root
  tmpfs. The gap is only that the *why* is documented and the
  *acceptance* is not — a reader of `:224-233` learns that the exec
  tmpfs was needed for boot, not that it constitutes a standing root
  channel from the provider.
- **Proposed fix:** one paragraph in `docs/hardening.md` recording it as
  an accepted risk with its reasoning (the hypervisor is trusted per
  §9; the alternative is a droplet that does not boot), and a sentence
  in the existing comment naming what the carve-out permits. If it ever
  needs to be closed, the lever is cloud-init's
  `vendor_data: { enabled: false }` — which per the comment at `:226-230`
  would break DigitalOcean's network arming, so it is not a free change.
- **Fix risk:** none for the documentation. Do not disable vendor-data
  without a console-recoverable test window.

### F-P2-19 — GRUB has no superuser, and the repo's own bootloader hardening has no GRUB counterpart

- **File:** `hosts/vps/configuration.nix:200-207`,
  `modules/profiles/default.nix:195-198`
  (`boot.loader.systemd-boot.editor = false`), pinned
  `system/boot/loader/grub/grub.nix:211` (`boot.loader.grub.users`)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** whoever has the DigitalOcean web console — which
  `docs/procedures/remote-access.md` names as the recovery path, and
  which already implies DO account compromise.
- **Rule:** §7.6 — hardening applied to the bootloader the other four
  hosts use, and not carried to the fifth.
- **Finding:** the shared profile disables the systemd-boot editor so
  that console access cannot be turned into an edited kernel command
  line. vps `mkForce`s systemd-boot off and uses GRUB, where the
  equivalent control is `boot.loader.grub.users` (a superuser with a
  password hash, which the pinned module supports). Nothing sets it, so
  anyone at the droplet console can press `e`, append
  `init=/bin/sh`, and get root without credentials.

  This is defence-in-depth only — the DO console is behind the DO
  account, and §9 treats the hypervisor as trusted — but the asymmetry
  is worth closing precisely because it is the kind of thing a reactive
  fix misses. Note the interaction with F-P2-01: console-to-root on vps
  yields the host age key, which per §4.7 decrypts the whole public
  ciphertext archive.
- **Proposed fix:** set `boot.loader.grub.users` with a
  `hashedPasswordFile` pointing at a sops secret. Note the module's own
  warning that hashes land in `/boot/grub/grub.cfg`, which is
  acceptable for a password hash but means `password`/`passwordFile`
  (plaintext variants) must not be used.
- **Fix risk:** a GRUB password that is wrong or unavailable turns the
  documented recovery path into a reinstall. Given `README.md` already
  treats "destroy and recreate the droplet" as the recovery story, that
  may be an acceptable trade — but it is a real one, and it argues for
  protecting only the editor (`users` with the default
  `boot.loader.grub.users.<name>` behaviour password-protects all
  non-default entries) rather than locking booting itself.

### F-P2-20 — caddy appends to client-supplied `X-Forwarded-For` rather than replacing it

- **File:** `hosts/vps/configuration.nix:518-522`; rendered Caddyfile
  lines 29-32
- **Severity:** INFO
- **Confidence:** PLAUSIBLE
- **Axis:** hardening
- **Reachability:** A1 — any HTTP client can set the header.
- **Rule:** n/a
- **Finding:** the config gets the important half right:
  `header_up X-Real-Ip {remote_host}` *sets* (replaces) the header, so
  anubis always sees the true peer address regardless of what the client
  sent. caddy's `reverse_proxy` also manages `X-Forwarded-For`, but by
  appending the peer to any chain the client supplied rather than
  resetting it. So a request carrying `X-Forwarded-For: 1.2.3.4` is
  forwarded as `1.2.3.4, <real client>`.

  CrowdSec is unaffected — its caddy parser reads caddy's own JSON
  access log, which records the true `request.remote_ip`. Anubis is
  unaffected — it is told to use `X-Real-Ip`. The exposure is to
  anything further downstream that takes the leftmost `X-Forwarded-For`
  entry, which means jellyfin's own logging and known-proxy handling on
  homelab. That is P4's to judge; from vps's side the fix is one line.
- **Proposed fix:** add `header_up X-Forwarded-For {remote_host}`
  alongside the existing `X-Real-Ip` line, so the chain starts fresh at
  the edge.
- **Fix risk:** none for anubis. Confirm nothing downstream relies on
  seeing a multi-hop chain.
- **Owner:** P2 for the caddy line; P4 to say whether jellyfin cares.

### F-P2-21 — health-check state is not persisted, so alert de-duplication resets every boot

- **File:** `hosts/vps/configuration.nix:248-270` (the persist list),
  `modules/nixos/health-alerts.nix:247`
  (`StateDirectory = "health-alerts"`)
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** none
- **Rule:** n/a
- **Finding:** `/var/lib/health-alerts` holds the cooldown stamps that
  suppress repeat alerts for a still-ongoing problem. It is absent from
  the persistence list, so on a host whose root is a tmpfs it is wiped
  every boot. After a reboot the first run re-alerts for anything still
  broken. Noise rather than risk, but it is a persistence-list gap on a
  host where the persistence list was otherwise thought through
  carefully — and the failure mode of alerting fatigue is that people
  stop reading the alerts.

  The unit is not `DynamicUser`, so the `docs/hardening.md` caveat about
  `StateDirectory` and impermanence bind mounts does not apply; a plain
  directory entry works.
- **Proposed fix:** add
  `{ directory = "/var/lib/health-alerts"; user = "health-check"; group = "health-check"; mode = "0750"; }`
  to `environment.persistence."/persist".directories`.
- **Fix risk:** none.

---

## 3. Checked and clean

Listed because "we looked and it was fine" is part of the audit's
output, and because several of these are the things most likely to be
re-litigated later.

**SSH.** `AuthenticationMethods publickey`, `AllowTcpForwarding no`,
`AllowAgentForwarding no`, `AllowStreamLocalForwarding no`,
`PermitTunnel no`, `ClientAliveInterval 60`/`ClientAliveCountMax 5` all
verified *in force* against the realised `sshd_config`, not just
present in the source. `PasswordAuthentication` and
`KbdInteractiveAuthentication` are set through the structured `settings`
option where they win. `allowSFTP = false` confirmed — no `Subsystem`
line in the output. One ed25519 host key, persisted. Only
`vars.publicSshKeys` for root. The two inert duplicates are F-P2-09 and
change no behaviour.

**The vps-deploy account, beyond F-P2-10.** `isSystemUser`, no password,
home `/var/empty` (mode 0555, immutable — cannot hold a second
`authorized_keys`), `/etc/ssh/authorized_keys.d/vps-deploy` is a
root-owned `0444` store symlink, `restrict` verified against
`openssh 10.4p1`'s own manual. The dispatcher contains no command
injection and no `set -eu` gap. `nix.settings.allowed-users = [ "root" ]`
from `profile-server` does not in fact restrict vps-deploy — Nix's
daemon admits `trusted-users` regardless — but that is upstream
behaviour and the deploy would not work otherwise; PLAUSIBLE, noted so
nobody later reads `allowed-users` as a boundary it is not.

**WireGuard.** `privateKeyFile` and `presharedKeyFile` both used, both
sops-backed; verified against the pinned
`services/networking/wireguard.nix:442-446,506,614` that the module
passes file *paths* to `wg set` rather than interpolating key material
into the store. A PSK is present and correctly paired. `allowedIPs` is
`10.100.0.2/32` — a single host, not a subnet, which is as tight as this
gets. vps listens and homelab dials, correct for a CGNAT'd peer. The
peer public key being in a public repo is fine; public keys are public.

**Impermanence.** The persist list is thorough and each entry has a
reason attached. `/var/log` is present, which is exactly the condition
`docs/hardening.md` attaches to enabling `security.auditd` — verified
that `security.audit.rules` is the execve rule and that the audit trail
therefore survives reboots. Host key, `machine-id`, `/var/lib/nixos`
(GID stability, which F-P2-17's group membership depends on),
`/var/lib/tailscale`, `/var/lib/caddy` (ACME state — avoids
rate-limiting Let's Encrypt on every reboot), and all three CrowdSec
paths including the bouncer's `api-key.cred`, whose absence caused the
split-brain failure `docs/hardening.md` warns about. `/var/lib/fail2ban`
persisted so `bantime-increment` survives reboots. The only gap found is
F-P2-21. Nothing is persisted that need not be.

**Filesystem hardening.** `/` is a tmpfs with `noexec,nosuid,nodev`,
which also covers `/tmp` since `boot.tmp.useTmpfs` is unset. `/persist`
is `noexec,nosuid,nodev` in `disko.nix`, and bind mounts inherit those
per-mount flags. `/var/lib/cloud` is the single deliberate exec
exception and is otherwise `nosuid,nodev`, root-owned, 64 MB.

**Swap.** `zramSwap.enable = true` and `swapDevices` evaluates to `[]` —
`docs/hardening.md`'s "Secrets + swap" rule satisfied, verified rather
than assumed.

**`smartd`.** `lib.mkForce false` with a correct reason. Clean
needed-used call; the grants it should have taken with it are F-P2-05.

**IPv6 forwarding.** `net.ipv6.conf.all.forwarding` evaluates to
`false` and nothing overrides it — checked specifically because
`docs/hardening.md` warns the tailscale module sets forwarding sysctls
at a priority that beats plain assignment. `useRoutingFeatures` is
`lib.mkForce "client"` here, so that priority conflict does not arise;
vps is the one host already compliant with that rule (F-P0-06).

**The v4/v6 asymmetry at `:439-460`.** Verified still accurate: the v6
raw chain covers 80/443 only, `networking.nat.enableIPv6` is `false`,
and the pinned `nat-iptables.nix:160,164-169` filters `forwardPorts` by
whether the destination is IPv6 — all four destinations are IPv4, so no
`ip6tables` DNAT rules are generated. `TODO.md:713-775` confirms the
IPv6 game-port work is parked, not in flight, with a documented
cost/benefit review. **Guard rail for whoever eventually lands it:** the
raw-table chain is the only pre-conntrack control on that path, and the
v6 chain currently has no game-port rules at all. Shipping
`net.ipv6.conf.all.forwarding = true` plus `ip6tables` DNAT without
mirroring the four hashlimit rules and re-checking the
`crowdsec6-blacklists-0` reference ships a silent, complete bypass of
everything in F-P2-06 — and per §4.7 the absence would be visible in
the diff to anyone watching the repo.

**CrowdSec plumbing.** LAPI bound to `127.0.0.1:8080`, prometheus to
`127.0.0.1:6060`, neither exposed. `/etc/crowdsec/config.yaml` is a
store symlink and contains no secret — only the *path* to the
credentials file, which tmpfiles creates `0750 crowdsec:crowdsec`. The
acquisition types (`syslog` for both journal sources) are the standard
recipe for journalctl-sourced caddy logs, and the `crowdsecurity/linux`
collection supplies the `syslog-logs` parser that strips the envelope —
the comment at `:547` is correct. The `Restart = "on-failure"` additions
for `crowdsec` and the bouncer correctly patch a real upstream gap
(verified: `crowdsec.nix:773` sets `RestartSec = 60` and never sets
`Restart=`; the bouncer's unit sets no restart policy at all). The
`StateDirectory = lib.mkForce [ ]` plus `ReadWritePaths` override for
`crowdsec-firewall-bouncer-register` matches `docs/hardening.md`'s
`DynamicUser`/impermanence rule exactly, including extending it to the
unit's own directory.

**The tailnet CrowdSec allowlist actually works.** `cscli decisions add`
honours allowlists by default — confirmed by the presence of an explicit
`-B, --bypass-allowlist` opt-out in `cscli 1.7.8`, which the fail2ban
action does not pass. So the `100.64.0.0/10` exemption covers
fail2ban-originated bans too, not just CrowdSec's own profile pipeline.
The comment at `:582-584` is right that `cscli decisions add` bypasses
*profile* evaluation; it is worth knowing that allowlists are a separate
and still-effective layer.

**fail2ban plumbing.** The `cscli.conf` action calls the raw binary by
absolute store path rather than the wrapped `cscli` on `PATH`, which is
exactly what `docs/hardening.md` requires given
`security.sudo.enable = false`; and it runs as root rather than
`runuser`-ing, which is also correct because fail2ban's unit
`CapabilityBoundingSet` (verified: `CAP_AUDIT_READ`,
`CAP_DAC_READ_SEARCH`, `CAP_NET_ADMIN`, `CAP_NET_RAW`) grants no
`CAP_SETUID`/`CAP_SETGID`. `jails.sshd.enabled = false` avoids two
uncoordinated detectors on the same signal. `backend = systemd` matches
the `journalmatch`. `<bantime>s` renders correctly. The rendered
failregex matches the kernel's actual LOG output format for both IPv4
and IPv6.

**Caddy.** Security headers present on the jellyfin vhost.
`header_up X-Real-Ip {remote_host}` *replaces* rather than appends, so
the value anubis rate-limits and logs on cannot be spoofed by a client
header. The `:80` catch-all does produce logs for host-less bot traffic
that would otherwise be invisible, and ACME HTTP-01 is handled ahead of
site routes so `respond 421` does not break renewal. The acknowledged
HTTPS/SNI gap at `:494-498` is real and correctly described — only
`jellyfin.skyseekerlabs.net` has a certificate, so probes with an
unknown SNI fail the handshake and never reach an access log; note that
the global `log { level ERROR }` likely suppresses caddy's own TLS
warnings about them too, so the gap is slightly wider than the comment
implies. Those probes *are* still covered volumetrically by the raw
chain's 80/443 rule and by the CrowdSec ipset pre-drop.

**Anubis.** Unix socket at mode 0770 in a 0755 runtime directory, with
`caddy` in the `anubis` group — group-reachable, not world-reachable.
The pinned module's sandboxing is thorough (`ProtectSystem = "strict"`,
`PrivateUsers`, `MemoryDenyWriteExecute`, `CapabilityBoundingSet = null`,
a `SystemCallFilter`). The one gap is network egress, F-P2-16.

**Firewall mechanics.** `extraCommands` runs on reload as well as start
(`reloadScript` invokes `startScript`), so the raw chain survives a
`nixos-rebuild switch`. The chain construction is idempotent. The
CrowdSec ipset drop is genuinely first in the chain, before any
hashlimit budget is spent, as the comment claims. The raw table does
run before conntrack and before the nat DNAT. `logRefusedConnections`
gives kernel-level visibility that nothing else on this host provides —
CrowdSec's acquisitions read only the sshd and caddy journal units. All
verified against the realised `firewall-start`.

**GRUB/boot, beyond F-P2-19.** `boot.loader.grub.devices` resolves to
`[ "/dev/vda" ]` via disko, `efiSupport = false` and
`canTouchEfiVariables = lib.mkForce false` match the BIOS-only droplet,
and the EF02 BIOS-boot partition in `disko.nix` is correct for it.

**`hardware-configuration.nix`.** Nothing security-relevant. Its
`networking.useDHCP = lib.mkDefault true` is correctly overridden to
`false` at `:131`, which matters — the long comment at `:110-130`
explains a real dhcpcd/networkd conflict, and the override is what
prevents it.

---

## Handoff to P4 — what the DNAT holes actually expose

P4 owns the two game servers behind vps's forwarded ports. The
conclusion from this side, stated plainly so it can be planned against:

1. **vps provides no security control on that path.** Traffic to
   25565/tcp and 19132, 34197, 34198/udp is DNAT'd to `10.100.0.2` over
   wg0 and never reaches userspace on vps. caddy, anubis and CrowdSec's
   log-based detection cannot see it — CrowdSec's acquisitions read only
   the sshd and caddy journal units. The raw-table hashlimit chain is
   the only thing in the path, and it is volumetric: it paces, it does
   not authenticate.

2. **The limits are looser than they look, and they are published.**
   Per source IP: 15 new TCP connections/minute on 25565; 1000
   packets/second on 19132; 2000 packets/second on each of 34197 and
   34198. Those are roughly one to two orders of magnitude above a real
   client's steady-state rate. An attacker reading
   `hosts/vps/configuration.nix:405-436` — which is public — knows the
   exact values and can sit just underneath them indefinitely, from a
   single address, and reach your protocol parsers with as much
   malformed input as they like.

3. **For the three UDP ports, both controls are bypassable outright.**
   The hashlimit buckets and the CrowdSec ipset drop both key on the
   source IP. UDP has no handshake and `checkReversePath` is `"loose"`
   on vps, so a source-randomising attacker gets a fresh bucket per
   packet and never appears in the ban set. Assume nothing on the vps
   side is filtering UDP by reputation.

4. **Therefore the game servers' own hardening is the boundary**, not a
   second layer behind one. Threat model §4.6 says this; this audit
   confirms it against the config. Whatever P4 concludes about
   container escape, resource limits, plugin/mod trust, and the servers'
   own auth (whitelisting, Factorio's token/password) is carrying the
   full weight of an internet-facing boundary — on a host that also
   holds the backup pools, §1 asset #1.

5. **One thing on the vps side does reach you, in the wrong direction.**
   F-P2-03: any internet host can put an arbitrary IP into
   `crowdsec-blacklists-0` with a single spoofed packet, and that ipset
   is consulted by the raw chain in front of your ports. So an attacker
   can blackhole individual legitimate players from the game servers
   without touching homelab. If players ever report being unable to
   connect from one address while others can, that is the mechanism to
   check first.

6. **IPv6 is not in play today** and the work to add it is parked
   (`TODO.md:713-775`). If it is ever revived, note that the review
   already found the pre-existing exposure: `minecraft.nix` and
   `factorio.nix` open their ports host-wide, and homelab's LAN
   interface already carries a globally-routable IPv6 address. That is
   P4's finding to own, and it is independent of the vps work.
