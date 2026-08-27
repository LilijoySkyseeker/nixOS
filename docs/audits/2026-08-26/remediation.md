# Remediation plan

Phase 3 of the 2026-08-26 audit. Sequenced into waves rather than one
branch, because the fixes have very different risk profiles and the
shared-profile ones move every host at once.

**Gates every wave passes**, per the repo's own rules:
`nixos-rebuild build --flake .#<host>` for each affected host
(`feedback_build_before_commit`), a VM test where *behaviour* changes
rather than just config, and **no `switch` without being asked**
(`feedback_test_dont_switch`). Build-only is free; switching changes a
running machine.

**What an agent may not do here.** Anything touching `secrets/*` is
manual (`docs/procedures/secrets.md`). Anything in §5 of
[`findings.md`](findings.md) is a user decision. Wave 3 is therefore a
checklist for the user, not work to be done unattended.

---

## Wave 0 — immediate, outside the repo

Not config changes; live state. Listed with exact commands so they can
be run without re-deriving anything.

| # | Action | Command |
|---|---|---|
| 0.1 | Close the world-readable age identity (N3) | `chmod 600 ~/.config/sops/age/keys.txt` |
| 0.2 | Remove the leaked zrepl key from `/tmp` (N1) — **after** rotating, since deleting does not retract the snapshot copies | `shred -u /tmp/homelab_zrepl_key` |
| 0.3 | Settle the last open verification (H9) when thinkpad is next up | `passwd -S lilijoy` |
| 0.4 | Check GitHub branch protection (D3) | web UI — with no CI, this is the only remaining control on fleet root |

0.1 is free and reversible and should not wait. 0.2 must follow the
rotation in Wave 3, not precede it.

---

## Wave 1 — zero-decision config fixes

Everything here is unambiguous, needs no judgement call from the user,
and is verifiable by a build. This is the wave to land first.

| # | Fix | Finding | Files | Risk |
|---|---|---|---|---|
| 1.1 | Move the `disk` grant from the `health-check` *user* to the one unit that needs it, via `serviceConfig.SupplementaryGroups` | H2 (`F-P3-02` `F-P2-05` `F-P7-05`) | `modules/nixos/health-alerts.nix` | low — narrows only |
| 1.2 | Fix the arithmetic injection: quote and validate the remote-supplied timestamp before arithmetic | H5 (`F-P7-03`) | `modules/flake/deploy-guards.nix:61` | low |
| 1.3 | Invert the routing default: `"client"` in the shared profile, `mkForce "both"` on homelab only, drop vps's now-redundant override, and remove homelab's redundant explicit sysctls **in the same change** | H4 (`F-P0-06` `F-P1-06` `F-P5-08` `F-P3-20`) | `modules/profiles/default.nix`, `hosts/{homelab,vps}/configuration.nix` | medium — see note |
| ~~1.4~~ | **Moved to wave 2** — interface-scoping the desktop profile's host-wide openings. See the note below; this is not a zero-decision fix. | H4 (`F-P1-04` `F-P5-06`) | `modules/profiles/PC.nix` | — |
| 1.5 | Remove `initialPassword = "123456"` | H9 (`F-P1-03`) | `modules/profiles/PC.nix:306` | low — but confirm 0.3 first for thinkpad |
| 1.6 | Delete the inert `ssh` block from the tailnet ACL reference copy, and from the console | H10 (`F-P0-05` `F-P8-12`) | `docs/tailscale-acl.json` | none — nothing uses it |
| 1.7 | **Done** — but the row was wrong; see the note below. Repo-side: dropped `sops.secrets.vps_caddy_env`, the one declared-but-unconsumed declaration. The nine `F-P8-11` orphans are **user-only** and moved to [`user-actions.md`](user-actions.md) §3 | C1 (`F-P8-11`), `F-P2-13`/`F-P8-18` | `hosts/vps/configuration.nix` | low |
| 1.8 | Add `programs.ssh.knownHosts` for `github.com` and `vps` so the deploy path stops re-TOFUing every boot | H1 (`F-P7-04` `F-P3-05` `F-P0-07`) | `modules/profiles/default.nix` | low — a stale pin blocks updates, so pair with 1.9 |
| 1.9 | **Done** — enabled `myHealthAlerts` on both laptops, so a *failed* deploy is visible at all. A **skipped** deploy still is not; see the note below | H1 (`F-P7-09`) | `hosts/{torrent,thinkpad}/configuration.nix`, `modules/flake/hosts.nix` | low |

**Note on 1.3.** Tailscale sets the forwarding sysctls at
`mkOverride 97`, so a plain `boot.kernel.sysctl` assignment loses
silently — only `mkForce` or changing `useRoutingFeatures` works
(`F-P1-06`). Getting it backwards silently breaks homelab's exit node
and its `192.168.1.0/24` subnet route, which is connectivity-visible
but **not** build-visible. Verify with `tailscale status` after any
eventual deploy.

**Note on 1.7 — the row above was wrong, and the correction matters.**
It read "drop the nine declared-but-unconsumed secret *declarations*"
and pointed at `F-P8-11`. But `F-P8-11` says in terms that **none of the
nine is a `sops.secrets` declaration** — they are keys in
`secrets/secrets.yaml` that no `.nix` file references. Nothing decrypts
them to `/run/secrets` on any host, so there is no repo-side edit that
removes them; removing them means editing the encrypted file, which
`docs/procedures/secrets.md` reserves to the user. They are now tracked
in [`user-actions.md`](user-actions.md) §3, together with the
rotate-or-revoke-at-the-provider step that actually retracts them.

Re-verified independently rather than taken on trust: `secrets.yaml`
holds 31 keys plus the `sops` metadata block; 18 are declared statically
as `sops.secrets.<name>`; four more come from the dynamic
`sops.secrets."tailscale_authkey_${config.networking.hostName}"` at
`modules/profiles/default.nix:112` (homelab, vps, thinkpad, torrent —
**not** isoimage, which has tailscale disabled). 18 + 4 = 22 consumed,
31 − 22 = **nine orphans**, matching `F-P8-11` exactly.

Checking the *other* direction — declared but unconsumed — turned up
exactly one: `sops.secrets.vps_caddy_env` (`F-P2-13`, `F-P8-18`), which
sops decrypted into `/run/secrets` on every vps activation for no
reader. That declaration is deleted. Removing the declaration *before*
the `secrets.yaml` key is the safe order: an undeclared key is inert,
whereas a declaration whose key is missing fails activation. Verified in
the rendered manifest, not just the build — vps's sops manifest now
lists **six** secrets where it listed seven.

**Note on 1.9 — what it does and does not buy.** `myHealthAlerts` is now
enabled on torrent and thinkpad, and `health-alerts` added to both
hosts' module lists in `modules/flake/hosts.nix`. This closes the
*failed* half of `F-P7-09`: `pull-deploy.service` entering `failed`
enters `systemctl --failed`, which the unit already checks. It does
**not** close the *skipped* half — every guard in `deploy-guards.nix`
still ends in `exit 0`, so a skip is recorded as success and never
enters `--failed`. That needs the deploy-marker work in `F-P7-09`'s
proposed fix (a) and is not in wave 1.

Two judgement calls, both deliberate:

- **`checkSmart = false` on both laptops.** It is the one option that
  costs something: the module grants the unit the `disk` group *and*
  `CAP_SYS_RAWIO`, and `/dev/sd*` is `root:disk 0660` — read **and
  write** on every raw block device, i.e. root-equivalent, by the
  module's own comment. homelab pays that because it is headless, where
  smartd's `wall`/`x11` sinks reach nobody. The laptops have graphical
  sessions and `services.smartd` is already enabled fleet-wide in
  `profiles/default.nix` with those sinks, so `checkSmart` would buy a
  duplicate alert at the price of a new root-equivalent grant on two
  more hosts — a bad trade during an audit whose C2 is "the desktop user
  is already fleet root". Verified in the rendered unit on both hosts:
  no `SupplementaryGroups`, no `AmbientCapabilities`, no
  `CapabilityBoundingSet`, and no `smartctl` block in the script.
- **`checkZfs` stays on**, and costs nothing. `/dev/zfs` is `0666` and
  `runuser -u health-check -- zpool status -x` was confirmed live on
  homelab to return "all pools are healthy" with exit 0. Worth recording
  because the unit exiting 0 proves nothing here — the script runs under
  `set -uo pipefail` with no `-e`, so a broken `zpool status` would fire
  a `zfs-error` alert and *still* exit 0.

The webhook is the existing `homelab_discord_webhook` rather than a new
per-host key, because minting a key is a user-only sops edit and, under
`.sops.yaml`'s single `creation_rules` entry, both laptops already
decrypt that value — so it grants no access they did not already have.
It does add a coupling the `.sops.yaml` restructure must account for;
logged as a user decision in [`user-actions.md`](user-actions.md) §3,
and re-pointing is one line per host.

**Note on 1.4 — why it moved to wave 2.** Investigating it turned up
three things that disqualify it from a wave whose defining property is
"needs no judgement call":

- **KDE Connect's range is opened by the nixpkgs module itself,
  unconditionally.** There is no `openFirewall` toggle to flip:
  `programs/kdeconnect.nix` adds 1714-1764 to
  `networking.firewall.allowedTCPPortRanges`/`allowedUDPPortRanges`
  directly. Scoping it means `lib.mkForce`-ing the host-wide lists empty
  and re-declaring *everything* per interface — which silently drops any
  future contributor to those lists too. That is a real trade-off, not a
  mechanical edit.
- **The interface names have to come from the hosts, and thinkpad has
  none.** `hosts/thinkpad/` declares no interface names at all; it is
  NetworkManager-managed with dynamic interfaces. `docs/hardening.md`
  already warns that host-specific interface names must not live in a
  shared profile because they silently break on hosts without that
  interface — so this needs a new per-host option, not a hardcoded NIC.
- **thinkpad is offline and cannot be verified.** Getting this wrong
  breaks LAN discovery, printing and device pairing on a machine that
  cannot currently be tested. The live probe (see
  `live-verification.md`) showed these ports are not presently reachable
  from the internet, so there is no urgency that justifies guessing.

It also needs an actual decision the user has to make: should KDE
Connect, Steam remote play and mDNS keep working on the LAN at all? If
yes, they get scoped to a host-declared LAN interface; if no, they can
go to `tailscale0` only, or be dropped. The full port inventory is in
the wave 2 entry.

The rest of the wave-1 note still holds: the mechanism is proven on
these hosts, since port 22 *is* interface-qualified on torrent while
nothing else is.

---

## Wave 2 — needs a VM test or careful staging

Behaviour changes, not just config. Each needs
`docs/procedures/vm-testing.md` treatment before it is trusted.

| # | Fix | Finding | Why it needs more than a build |
|---|---|---|---|
| 2.1 | Stop docker publishing past the firewall — bind published ports to a specific address, or add a host-level `DOCKER-USER` allowlist for both v4 and v6 | H3 (`F-P4-02` `F-P3-04`) | changes the packet path for four live game servers; get it wrong and either they are unreachable or still exposed |
| 2.2 | Pin the container images by digest and pin the Modrinth mod set | H3 (`F-P4-03`) | changes what actually runs; needs a start-and-play check |
| 2.3 | **Done** — both laptops brought up to the baseline as structured `settings`, `allowSFTP = false`, and the `AllowTcpForwarding` claim in `docs/hardening.md` corrected. The homelab/vps `extraConfig`→`settings` move is **not** included; see the note | MEDIUM cluster (`F-P5-07` `F-P2-09` `F-P3-18` `F-P6-10`) | verified with `sshd -T`, before *and* after — see the note |
| 2.4 | **Done, and better than planned** — plover was declared unused by the user (2026-08-27), so the grant is *removed* rather than narrowed. No `hardware.uinput.enable` needed. See the note | C2 (`F-P1-01` `F-P8-09`), also `F-P8-21` | the functional dependency turned out not to exist |
| 2.5 | **Done** — added `nosuid` and `nodev` to the NFS client mounts. `noexec` **declined**, per the finding rather than this row; see the note | MEDIUM (`F-P6-05`) | verified live on torrent and through `systemd-fstab-generator` — see the note |
| 2.6 | **Two of three done.** `zfs-emergency-prune` sandboxed and VM-tested; `crowdsec-allowlist-tailnet` sandboxed and dropped from root to the `crowdsec` user. **`push-deploy-vps` deferred** — comment corrected, sandbox not applied; see the note | MEDIUM (`F-P2-08` `F-P6-06` `F-P7-06`) | `push-deploy-vps` does no local activation, so the carve-out does not apply to it |
| 2.7 | **Done** — all four parts of the proposed fix, VM-tested including the drift scenario itself | MEDIUM (`F-P2-02`) | touches vps's firewall start path — the one host where a mistake is internet-facing |
| 2.8 | `zfs hold` on `@blank`, and `recv.properties.override` on the pull jobs | C3/H8 (`F-P6-04` `F-P6-03`) | changes replication behaviour; the existing VM tests do not cover it (`F-P6-14`) |
| 2.9 | Interface-scope the desktop profile's host-wide openings (moved from 1.4) | H4 (`F-P1-04` `F-P5-06`) | needs a new per-host LAN-interface option, a `mkForce` of the host-wide lists, and a user decision on whether LAN discovery keeps working — plus thinkpad online to test |

**Note on 2.4 — the premise changed, so the fix got simpler and
stronger.** The whole item was shaped around "plover must still work;
this is a real functional dependency, not dead config". On 2026-08-27
the user declared plover unused. That removes the constraint the fix was
built around, so instead of swapping `input` for a narrower `uinput`
group, **plover is removed outright and both grants go with it**. No
`hardware.uinput.enable`, no new group, nothing left to narrow later.

Removed: the `programs.plover` home-manager block and its module import,
the hand-written `KERNEL=="uinput"` udev rule, `"dialout"` and `"input"`
from `lilijoy`'s `extraGroups`, and the `plover-flake` flake input.

The duplicate `input` grant in `modules/nixos/wooting.nix` is gone too,
and it had to be: that module merges into the same `extraGroups` list,
so dropping `input` from `PC.nix` alone would have left the grant fully
intact while looking like a fix (`F-P1-15`). Removing it is safe,
checked rather than assumed — `hardware.wooting.enable`'s only access
mechanism is `services.udev.packages = [ pkgs.wooting-udev-rules ]`, and
every rule in that package is `TAG+="uaccess"`, which grants the
logged-in user access through a logind ACL rather than a group.

**A supply-chain win comes free with it.** `plover-flake` was the input
`F-P8-21` singled out as the one that *actually builds packages* from
its own unfollowed nixpkgs into both PC closures. Dropping it removed
**nine lock nodes** — `plover-flake` itself, its `nixpkgs`, its
`treefmt-nix` and that in turn its own `nixpkgs`, plus five plugin
inputs — and the lock diff is **0 insertions, 155 deletions**, so no
other pin moved.

Verified in the evaluated config rather than by build alone: on torrent
the `input` group now has **zero members**, `dialout` likewise, the
`uinput` rule is absent from the rendered `99-local.rules`, and
`nix path-info -r` over the built closure returns **zero** plover paths.

Two things noticed while doing it, neither fixed here:

- **The 8bitdo hidraw rules never took effect.** They set `MODE="0660"
  GROUP="input"`, but live on torrent every `/dev/hidraw*` is `0666
  root:plugdev` with a uaccess ACL, because `50-qmk.rules` (all hidraw,
  `GROUP=plugdev`, `TAG+=uaccess`) and `60-steam-input.rules` (vendor
  `2dc8`, `TAG+=uaccess`) sort after `99-local.rules`. Controller access
  comes from uaccess, not the group, so those rules grant `lilijoy`
  nothing now. Left in place with a comment; dead config worth revisiting
  on its own terms rather than inside a plover change.
- **`/dev/uinput` already carried `user:lilijoy:rw-`** from a logind
  uaccess ACL, independent of the group — so even the narrowing fix would
  have been partly redundant.

**Note on 2.7 — all four parts done, and the drift scenario is tested.**

`F-P2-02`'s fix had four parts and all four landed:

1. **Both `--match-set … -j DROP` rules now end in `|| true`.** They fail
   with "Set … doesn't exist" if the sets are missing, and an unguarded
   failure aborts the firewall script before it arms the filter.
2. **Both `ipset create` calls moved out of `extraCommands`** into
   `systemd.services.crowdsec-ipset-precreate`, ordered `Before =
   [ "firewall.service" ]` with `RequiredBy`/`PartOf` deliberately unset,
   so the firewall can never fail because of it.
3. **`networking.firewall.extraStopCommands` added**, tearing down the
   raw `vps-ratelimit` chain and its PREROUTING jump for both families.
   Every line guarded, because `extraStopCommands` is spliced into a `-e`
   script too and a half-torn-down firewall is worse than a skipped rule.
4. **Confirmed the alerting is real.** `myHealthAlerts` runs
   `systemctl --failed --no-legend --plain` with no filtering, so a
   failed `crowdsec-ipset-precreate` does page. This mattered: it is the
   precondition the finding names for part 1 being the right trade.

**Why a unit rather than just `|| true` on the create lines.** `|| true`
alone would make the firewall *succeed* with the ban layer silently
missing, alerting nobody — trading a fail-open for a fail-silent. As its
own unit the failure is both contained and visible.

`ProtectKernelModules = true` on that unit is only safe because
`boot.kernelModules` now declares `ip_set` and `ip_set_hash_net`
explicitly (names confirmed by `lsmod` on the live host). Otherwise
creating a `hash:net` set relies on the kernel autoloading the module at
create time — an implicit dependency that should not sit between this
host and a working packet filter.

**Verified in a throwaway VM test**, since none of this is build-visible.
Four subtests, all passing: the sandboxed unit succeeds; both sets exist
with the expected parameters; re-running is idempotent as `-exist`
implies; and — the one that matters — after destroying a set and
recreating it with a **different `maxelem`**, exactly the drift `F-P2-02`
describes, `systemctl restart` leaves *that unit* in `failed` while the
firewall is untouched. That is the whole point of the change,
demonstrated rather than argued. The test was deleted afterwards per
`docs/procedures/vm-testing.md` — it verified a one-off migration and
will not be run again.

Live state checked read-only on vps beforehand: the running sets do still
match the repo's parameters exactly (`hash:net`, `hashsize 1024`,
`maxelem 131072`, `timeout 300`), so there is no drift today. The fix is
against the drift that a nixpkgs bump or one hand-made `ipset` would
introduce.

**Note on 2.6 — two units hardened, one deliberately deferred.**

**`zfs-emergency-prune` (`F-P6-06`) — done, and actually VM-tested.**
The full `health-alerts.nix` stack, minus `PrivateDevices` (the unit
needs `/dev/zfs`). It stays root: `zfs destroy` is not delegable to a
service user here, so root is the blast radius being *bounded*, not
removed. `tests/zfs-space-guard.nix` already started the unit for real,
so the finding's instruction — "extend that test rather than trusting
the build" — was followed: a new subtest asserts each sandbox property
is actually in effect (and that `PrivateDevices` stays **off**), and the
pre-existing subtests then start the unit under that sandbox and check
`zfs destroy` still reclaims space. All seven subtests pass. This
matters because the failure mode is "the break-glass service doesn't
work when you need it at 2am", which no build could ever have caught.

**`crowdsec-allowlist-tailnet` (`F-P2-08`) — done, and no longer root.**
`User`/`Group` set to `services.crowdsec.user`/`.group` plus the full
stack and an empty `CapabilityBoundingSet`. Verified in the rendered
unit.

One deliberate departure from the finding's proposed fix: it claimed
`ProtectSystem = "strict"` needs **no** `ReadWritePaths`, because "the
allowlist lives in CrowdSec's own database via the LAPI". Two pieces of
evidence say otherwise, so `ReadWritePaths = [ "/var/lib/crowdsec" ]` is
granted:

- `crowdsec-firewall-bouncer-register`, twenty lines below it in the
  same file, already carries the comment "cscli needs to write
  `/var/lib/crowdsec`" and grants exactly that.
- The live state directory on vps holds a SQLite `crowdsec.db`
  (`/var/lib/crowdsec/state/crowdsec.db`, `0640 crowdsec:crowdsec`),
  checked read-only over SSH — and `cscli` reaches the database directly
  for several subcommands rather than going through the LAPI.

Granting it is strictly safer than omitting it: if `cscli` turns out not
to need the write, nothing is lost, whereas omitting it and being wrong
means the tailnet exemption stops applying and CrowdSec starts banning
the admin's own IP — the exact problem this unit exists to prevent, and
one already observed live on 2026-08-26.

**`push-deploy-vps` (`F-P7-06`) — sandbox deferred, comment fixed.** The
documentation half is the safe half and is done: the comment claimed
"`ReadOnlyPaths` on `${cfg.flakeDir}` plus `NoNewPrivileges` is enough
for now", which was false in both halves — no `ReadOnlyPaths` was ever
set, and none *could* be, because the unit's first action is
`fetch_and_merge_master`, which writes to `flakeDir`. That is §7.5 at
module scope, so it is corrected in place rather than left for a future
reader to budget against.

The sandbox itself is **not** applied, deliberately. `nixos-rebuild
--target-host` shells out to `ssh` and `nix-copy-closure`, and the
finding's own fix risk names two concrete hazards: `PrivateTmp` breaking
the SSH control-master socket path, and `ProtectSystem = "strict"`
breaking nix's fetcher cache under `/root/.cache`. Its stated
requirement is a VM test **with a real remote target** — which means
building a full system closure inside a test VM and pushing it to a
second node, far heavier than the zrepl two-node test and probably
impractical as written. Getting it wrong means vps silently stops
updating, and `F-P7-09`'s skipped-deploy half is still open, so nothing
would say so. Guessing here is the one thing this wave should not do.
The corrected comment now records exactly what is still owed.

**Note on 2.5 — the row said three options; the finding says two.** This
row read "add `nosuid`/`nodev`/`noexec`", but `F-P6-05`'s proposed fix
explicitly *declines* `noexec` — "this is a media/file share and someone
will eventually want to run something off it" — and asks for it to be
recorded as considered and declined, in the same comment. The finding
wins: it is the analysis written against the file, where the table row
is a summary. This is the second time in this wave plan a row has
disagreed with the finding it cites (see 1.7); prefer the finding.

Checked live on torrent rather than reasoned about, since the mounts are
real there:

- The mount is `vers=4.2 … sec=sys` with **no** `nosuid`, `nodev` or
  `noexec` — `suid` and `dev` were in force, exactly as `F-P6-05` says.
- A scan of both shares found **no setuid/setgid regular files and no
  device nodes**, so `nosuid` and `nodev` cost nothing today. The
  setgid *directories* the scan turns up (`drwxrws---`) are the
  multimedia group-inheritance pattern and are unaffected by `nosuid`,
  which only suppresses setuid/setgid on execution.
- The `+x` bit is set indiscriminately across the media files, a
  permissive-umask artifact, so "executables present" carries no signal
  either way on the `noexec` question. Nothing that is actually a
  program lives there today, so `noexec` remains a cheap tightening if
  the share is ever declared data-only — logged as **D12**.

`F-P6-05` warns that a bad option surfaces at first access, not at
build, and verifying the automount properly needs a switch. Short of
that: the rendered `/etc/fstab` carries `nosuid,nodev` on both mounts on
both laptops, and feeding that fstab to the pinned
`systemd-fstab-generator` produces both the `.mount` and the
`.automount` unit for each share with the new options in `Options=`.
Both are generic kernel mount flags rather than NFS-specific spellings,
so there is no filesystem-specific typo risk in these two.

**Note on 2.3 — verified by `sshd -T`, and the doc error is confirmed
empirically.** The rendered `sshd_config` was extracted from each host's
built closure, its `HostKey` lines swapped for a throwaway key, and the
pinned OpenSSH 10.4p1 `sshd` asked for its *effective* configuration —
before and after. thinkpad's and torrent's rendered configs are
byte-identical, as `F-P5-07` observed.

| Directive | Before | After |
|---|---|---|
| `AllowTcpForwarding` | **yes** | `no` |
| `AllowAgentForwarding` | **yes** | `no` |
| `AllowStreamLocalForwarding` | **yes** | `no` |
| `AuthenticationMethods` | **any** | `publickey` |
| `ClientAliveInterval` | **0** — no idle timeout at all | `60` |
| `ClientAliveCountMax` | `3` | `5` |
| `PermitTunnel` | `no` | `no` — already correct, by accident |
| sftp subsystem | **present** | gone |

The "before" column is the direct disproof of `docs/hardening.md`'s old
sentence "`AllowTcpForwarding` defaults to `no`". It defaults to **yes**,
and so do the two other forwarding directives. That sentence is now
corrected, and the doc additionally says to write these as `settings`
rather than `extraConfig` and to verify with `sshd -T`.

`allowSFTP = false` is safe on these two specifically, checked rather
than assumed: zrepl uses `ssh+stdinserver` rather than sftp, root is
`forced-commands-only`, and `/home/lilijoy/.ssh/` on torrent contains no
`authorized_keys` — so no interactive login exists to scp *from*. The
same question is still open for homelab, where it stays a needs-check.

**Not included, deliberately:** homelab and vps carry the identical
directive set in `extraConfig`, where it is inert (`F-P2-09`,
`F-P3-18`). Moving it to `settings` is byte-identical in output and a
real change in safety, but it touches the two server hosts and belongs
with 2.6's sandboxing pass rather than being smuggled into a laptop
change.

**2.9 port inventory**, as evaluated on torrent, so it does not have to
be re-derived: TCP ranges 1714-1764; UDP ranges 27031-27035 and
1714-1764; TCP ports 27036, 27037; UDP ports 5353, 10400, 10401, 27036.
Note 10400/10401 are opened by something outside this repo and were not
attributed during the audit — identify them before scoping, since an
unexplained open port is its own finding.

---

## Wave 3 — user decisions and manual secret work

Not agent work. Ordered by value.

1. **Rotate the ten credentials** exposed by `F-P8-02`, at each
   provider: Backblaze, Cloudflare, tailscale, both WireGuard keypairs
   and the PSK, the Discord webhook, the vps-deploy keypair, the zrepl
   keypair. Re-keying `.sops.yaml` does nothing retroactively. (D1)
2. **Restructure `.sops.yaml` into per-path `creation_rules`** so each
   host holds only what it consumes — the only change that bounds
   future exposure. (C1)
3. **Attribute or retire the five unattributable recipients**
   (`F-P8-05`).
4. **Buy immutability**: an append-only Backblaze key plus Object Lock
   — the single highest-value change for asset #1. (D4)
5. **Decide on unsigned `origin/master`** (D2): accept and write it into
   `docs/hardening.md` as an explicit risk, or add `git verify-commit`
   against an allowed-signers file, failing closed. Note `F-P7-07`
   auto-merges upstream input updates on build success alone, which
   should probably stop regardless.
6. **Decide on the tailnet ACL** (D6) — and fix the vps half
   (`trustedInterfaces`) either way, since that is where the blast
   radius is actually unbounded.
7. **Decide on FDE** (D5), intrusion detection (D7), and the recovery
   ISO's access model (D8).

Also here, because it changes key handling rather than config:
`bootstrap-host.sh` should generate into a tmpfs and scrub on failure
rather than preserving (`F-P7-08`).

---

## Wave 4 — documentation harvest

Phase 4 of the audit proper. The eleven systemic rules in
[`findings.md`](findings.md) §4 go into `docs/hardening.md`, the threat
model becomes a standing doc, accepted risks get written down with
their reasoning, and deferred items land in `TODO.md`. Tracked
separately.
