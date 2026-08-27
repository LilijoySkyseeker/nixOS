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
| 2.1 | **Done** (`myDockerPublishGuard`) — D13 answered "never from the LAN", so the publishes are filtered in FORWARD via DOCKER-USER, allowing only wg0 and tailscale0. **VM-tested with a real container and a real client, both directions.** See the note | H3 (`F-P4-02` `F-P3-04`) | changes the packet path for four live game servers; get it wrong and either they are unreachable or still exposed |
| 2.2 | **Blocked on D14** — pinning changes what runs and the finding requires a start-and-play check, which is not an agent's to do | H3 (`F-P4-03`) | changes what actually runs; needs a start-and-play check |
| 2.3 | **Done** — both laptops brought up to the baseline as structured `settings`, `allowSFTP = false`, and the `AllowTcpForwarding` claim in `docs/hardening.md` corrected. The homelab/vps `extraConfig`→`settings` move is **not** included; see the note | MEDIUM cluster (`F-P5-07` `F-P2-09` `F-P3-18` `F-P6-10`) | verified with `sshd -T`, before *and* after — see the note |
| 2.4 | **Done, and better than planned** — plover was declared unused by the user (2026-08-27), so the grant is *removed* rather than narrowed. No `hardware.uinput.enable` needed. See the note | C2 (`F-P1-01` `F-P8-09`), also `F-P8-21` | the functional dependency turned out not to exist |
| 2.5 | **Done** — added `nosuid` and `nodev` to the NFS client mounts. `noexec` **declined**, per the finding rather than this row; see the note | MEDIUM (`F-P6-05`) | verified live on torrent and through `systemd-fstab-generator` — see the note |
| 2.6 | **Two of three done.** `zfs-emergency-prune` sandboxed and VM-tested; `crowdsec-allowlist-tailnet` sandboxed and dropped from root to the `crowdsec` user. **`push-deploy-vps` deferred** — comment corrected, sandbox not applied; see the note | MEDIUM (`F-P2-08` `F-P6-06` `F-P7-06`) | `push-deploy-vps` does no local activation, so the carve-out does not apply to it |
| 2.7 | **Done** — all four parts of the proposed fix, VM-tested including the drift scenario itself | MEDIUM (`F-P2-02`) | touches vps's firewall start path — the one host where a mistake is internet-facing |
| 2.8 | **Done** — both halves, and `tests/zrepl-replication.nix` extended to cover them (it now does). One correction to `F-P6-03`'s text; see the note | C3/H8 (`F-P6-04` `F-P6-03`) | changes replication behaviour; the existing VM tests do not cover it (`F-P6-14`) |
| 2.9 | **Done** — Steam remote play disabled outright, KDE Connect scoped to `tailscale0`, avahi already removed. **No per-host LAN-interface option was needed**, and it resolved D10 as a side effect. See the note | H4 (`F-P1-04` `F-P5-06`) | needed a `mkForce` of the host-wide lists; the LAN-interface option and the thinkpad test both turned out unnecessary |

**Note on the deploy-guards `safe.directory` fix (found 2026-08-27,
outside the wave plan).** Discovered incidentally while clearing a
stopped unit's failed state on homelab: **both halves of the deploy path
were failing, and had been since 2026-08-25.**

```
auto-switch.service       failed
push-deploy-vps.service   failed
error: could not lock config file /root/.config/git/config: Read-only file system
```

`require_clean_master()` opened with
`git config --global --add safe.directory "$(pwd)"`. Root's
`~/.config/git/config` is a **home-manager symlink into the nix store**;
git creates its lockfile beside the config it is writing; the store is
read-only. So the guard aborted on its first line, before any of its
actual checks, and took every scheduled deploy with it. Last successful
`auto-switch`: 2026-08-25 13:18.

**This is `F-P7-09` demonstrated rather than argued.** The audit rated
"nothing notices a failed deploy" and half-fixed it in wave 1 item 1.9;
here is the other half happening for real — two days of no deploys on
homelab *and* no pushes to vps, with nothing raising a hand. It also
sharpens the finding: the failure was visible in `systemctl --failed`
the whole time, so the gap is not detection but *notification*.

**The fix does not write anything.** The guards now define
`git() { command git -c safe.directory="$PWD" "$@"; }` once, at the top
of the fragment. `-c` is "command" scope, which git-config(1)'s SCOPES
section counts as **protected** configuration — and `safe.directory` is
only honoured in protected scopes, so this genuinely applies where a
repo-local value would be silently ignored. Checked against git's own
documentation, not assumed.

Wrapped rather than added per call site because the consuming modules run
about nineteen git commands between them; patching call sites means a
later addition silently misses the flag and reintroduces the bug.

**The underlying mistake is worth naming**: the guard mutated a dotfile
that another part of the system owns declaratively. Home-manager won that
fight the moment it took over root's git config, and it would have won it
silently on any host. It is also the same `safe.directory` that
`docs/hardening.md` rule 7 warns about suppressing — the fix narrows it
from a persisted global grant to a single command's scope, which is
strictly better on that axis too.

**Verified by `tests/deploy-guards.nix`, six subtests**, two of which
assert the *premise* rather than the fix, so the test cannot quietly stop
testing anything: it proves the global config really is read-only in the
harness, and that git really does refuse the repo for dubious ownership.
Then: the guard completes on a clean master despite both, still skips a
dirty tree, still skips a non-master branch, and leaves the store symlink
untouched with no `config.lock` beside it. Built on all four hosts.

**Not switched, so the fleet is still not deploying.** This lands only
when the branch does.

**Note on 2.9 — three of the four port groups were removed, not
scoped, so the hard part evaporated.** The item was scoped as needing a
new per-host LAN-interface option (thinkpad declares no interface names)
and thinkpad online to test. Neither turned out to be necessary, because
the user's D9 answers deleted rather than narrowed:

- **mDNS/avahi** — removed entirely (D9 option c, static printer address
  instead). Ports gone, no scoping needed.
- **Steam remote play** — `remotePlay.openFirewall` dropped. Ports gone.
- **KDE Connect** — the only one actually scoped, to `tailscale0`.

With nothing left that wants LAN access, there is no LAN interface to
name. The whole item came down to two edits in `modules/profiles/PC.nix`.

**KDE Connect needed `mkForce`, because the module gives you no choice.**
`nixos/modules/programs/kdeconnect.nix` at the pinned rev sets
`networking.firewall.allowedTCPPortRanges` unconditionally inside its own
`mkIf cfg.enable`, with no `openFirewall` option — checked against the
source rather than assumed. So the host-wide lists are forced empty and
the range re-added under
`networking.firewall.interfaces.tailscale0`. That `mkForce` is safe only
because kdeconnect is now the *only* range contributor on these hosts; a
comment at the setting says so, and says how to check.

**2.9 answered D10, which was a separate open decision.** The
unattributable UDP 10400/10401 were **Steam's**:
`programs.steam.remotePlay.openFirewall` opens TCP 27036/27037, UDP
27031-27035 *and* UDP 10400/10401 together, in
`nixos/modules/programs/steam.nix`. Attributed by evaluating
`options.networking.firewall.allowedUDPPorts.definitionsWithLocations`,
which names the defining nixpkgs file for each entry — the reason the
audit's own grep failed is that the numbers appear nowhere as literals in
this repo.

**Why it stayed a mystery is the transferable part.** The wave-2 port
inventory listed TCP 27036/27037 and UDP 10400/10401 as separate line
items and never connected them, so one `openFirewall = true` presented as
two findings — one understood, one unexplained. **Attribute a port to the
option that opens it, not to the port number.**

**Verified in the rendered firewall script**, which is the only check
worth anything for this class of change: the sole surviving port range is
`1714:1764`, both of its rules end in `-i tailscale0`, and `10400`,
`10401` and `2703x` match nothing. Built on torrent and thinkpad. Not
switched.

**Note on 2.1 — the fix had to move chains, not just tighten a rule.**
D13 was answered "never from the LAN — only tailnet or the public
address", so there was no exception to carve out.

The obvious fix, binding each publish to an address, was **rejected**.
The public path is fine that way (vps DNATs all four ports to
`10.100.0.2`, homelab's static wg0 address), but the tailnet path is
not: tailscale assigns that address, this repo hardcodes a
`100.64.0.0/10` address exactly nowhere, and a hardcoded one would break
silently if the node were ever re-registered. So the guard filters on
the **input interface** instead — `wg0` and `tailscale0` — which is also
what `docs/hardening.md` standing rule 5 asks for.

It lives in a new `modules/nixos/docker-publish-guard.nix` rather than
inline in the host, for a specific reason: `modules/flake/checks.nix`
takes a *module*, so making it a module is what makes it testable. It
owns a private `docker-publish-guard` chain, rebuilt from scratch on
every run, with `DOCKER-USER` jumping into it exactly once. Only the
named ports are matched; everything else RETURNs, so inter-container
traffic and every other container are untouched.

**The old rules were left in place, with a correction.**
`modules/services/{minecraft,factorio}.nix` still carry their
`networking.firewall.interfaces.{tailscale0,wg0}` entries. They are
correct for anything that reaches INPUT and they document the intent,
but they never constrained the published ports and the comments now say
so and point at the guard. Do not delete one without the other.

**Verification — nine subtests, `tests/docker-publish-guard.nix`.** The
rule-shape assertions are the weaker half and are deliberately not the
whole test: rules existing is exactly the evidence that was already true
of the INPUT rules this replaces, which existed and did nothing. So the
test also builds a local busybox image (no network), runs it as a real
container publishing 8080, and drives a real second node at it:

- a client on an unlisted interface **cannot** reach the container;
- with the guard stopped the *same* connection succeeds and returns the
  expected payload — so the failure above is the guard, not a broken rig;
- restarting the guard closes it again;
- the guard survives `systemctl restart docker` (docker recreates the
  FORWARD jump, and a guard that vanished there would reopen the ports
  with nothing to report it);
- re-running converges rather than duplicating rules.

**Still IPv4-only, on purpose.** docker's ip6tables chains do not exist
while container IPv6 is off, so an ip6tables rule would have nothing to
attach to. `hosts/homelab/configuration.nix`'s comment now carries this
as the one remaining live warning: enabling `ipv6 = true` or restoring
`userland-proxy` without extending the guard converts a LAN exposure
into an internet one.

**Not switched.** The LAN path is closed only once this is deployed.

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

- **The 8bitdo hidraw rules never took effect — and are now removed
  too.** They set `MODE="0660" GROUP="input"`, but live on torrent every
  `/dev/hidraw*` is `0666 root:plugdev` with a uaccess ACL, because
  `50-qmk.rules` (all hidraw, `GROUP=plugdev`, `TAG+=uaccess`) and
  `60-steam-input.rules` (vendor `2dc8`, `TAG+=uaccess`) sort after
  `99-local.rules`. Controller access came from uaccess the whole time,
  never from the group. The user confirmed the config was unused and had
  never worked, which matches exactly what the live device modes show, so
  it is deleted rather than annotated. That empties
  `services.udev.extraRules` on these hosts entirely — the rendered
  `99-local.rules` is now nothing but NixOS's own defaults, with no
  `GROUP="input"` anywhere in it. Their only real effect had been to make
  the `input` grant look load-bearing when it was not.
- **`/dev/uinput` already carried `user:lilijoy:rw-`** from a logind
  uaccess ACL, independent of the group — so even the narrowing fix would
  have been partly redundant.

**Note on 2.1 — the zero-risk half is done; the rest is a user
decision (D13).**

Both candidate fixes — binding the publishes to an address, or a
`DOCKER-USER` allowlist — close the LAN path to the four game servers.
Whether that is correct depends on something no source file answers: does
anyone connect to minecraft or factorio from a machine on
`192.168.1.0/24`, rather than over the tailnet or through vps? Guessing
wrong makes four live servers unreachable. Logged as **D13**.

What *was* done needs no decision and carries no behavioural risk: the
load-bearing dependency is now written into
`hosts/homelab/configuration.nix` next to the setting it rests on. The
four ports are LAN-reachable because docker DNATs in `nat/PREROUTING`
before the routing decision, so nothing traverses `nixos-fw` — and the
only thing keeping them off this host's real globally-routable IPv6 is
docker's default of not enabling IPv6 for containers, with
`userland-proxy = false` sitting right there as an unremarked
performance tweak. That is exactly threat model §7.1, and the same class
of unstated assumption that triggered this whole audit. Setting
`ipv6 = true` or restoring the userland proxy would silently convert a
LAN exposure into an internet one; now the file says so.

The build output is **the identical store path** before and after, which
is the proof that it is comment-only.

The severity question is settled and does not need re-deriving: the live
probe on 2026-08-26 found **no IPv6 DNAT rules** for any of the four
ports and all four listeners bound on `0.0.0.0` with none on `::`. So
exposure is LAN-wide (A4), not internet-wide.

**Note on 2.8 — both halves landed, and `F-P6-03` has one wrong key
name.**

**`zrepl-protect-blank` (`F-P6-04`).** A new oneshot in
`modules/nixos/zrepl.nix`, active on any host with `serve.enable`,
holding `<dataset>@blank` with the tag `protect`. This is the piece the
finding calls "the highest-value fix", and the reason it works is that
zrepl only recognises and releases its own `zrepl_STEP_J_*` /
`zrepl_last_received_J_*` tags — a foreign tag is invisible to it and
cannot be released over any RPC, while `doDestroySnapshots` tolerates the
resulting failure. It holds `@blank` and nothing else: holding a
`zrepl_`-prefixed snapshot would pin the pool, since those are exactly
the ones retention must be free to destroy.

Worth being precise about what it fixes. `protectRegexes` is the
*puller's pruning policy*, and a policy is not a control:
`Sender.DestroySnapshots` evaluates no keep rules and `config.SourceJob`
has no `Pruning` field at all, so before this a compromised — or merely
mistyped — homelab could destroy `@blank` on both laptops, and `@blank`
is not regenerable without reinstalling.

It is a no-op on torrent today, by design and correctly:
`hosts/torrent/README.md` records that the impermanence migration has not
happened there, so torrent has no `@blank` (confirmed live — 116
snapshots, all `zrepl_`-prefixed, none named `blank`). thinkpad creates
one at install via `disko`'s `postCreateHook`, so the hold applies there
now, and torrent picks it up automatically whenever it migrates.

**`recv.properties` (`F-P6-03`).** `mkRecv` now pins `mountpoint = "none"`
and `canmount = "off"` via `override`, and strips `sharenfs`, `sharesmb`,
`exec`, `setuid`, `devices` via `inherit`. Checked against the pinned
zrepl source rather than the docs: `PropertyRecvOptions` is
`Inherit []zfsprop.Property` + `Override map[zfsprop.Property]string`
(`internal/config/config.go:140-143`), which is exactly this shape. Note
`inherit` has to be quoted in Nix — it is a keyword.

**The correction.** `F-P6-03` says a compromised source "sets
`send.properties: true` in its own `/etc/zrepl/zrepl.yml`". There is no
such key. zrepl 0.7.0's `SendOptions` field is
`SendProperties bool \`yaml:"send_properties"\``
(`internal/config/config.go:95`). This is not a harmless slip: zrepl
unmarshals strictly, so the wrong spelling makes the daemon refuse to
start with `field properties not found in type config.SendOptions` — which
is precisely how the VM test caught it. Anyone reproducing that finding
by hand would hit the same wall.

**Verified in `tests/zrepl-replication.nix`, which now covers both.** All
nine subtests pass. The two new ones:

- `zrepl-protect-blank` is started for real, `@blank` is confirmed to
  carry the `protect` hold, `zfs destroy tank/data@blank` is asserted to
  **fail**, and the unit is re-run to prove it is idempotent (it runs on
  every boot, and an existing hold would otherwise make `zfs hold` error).
- The hostile sender is simulated faithfully rather than approximated:
  the source dataset is poisoned with `mountpoint`, `canmount`, `setuid`,
  `exec`, `devices`, and the source's **own `zrepl.yml` is rewritten** to
  set `send_properties: true` — because the sender alone decides whether
  properties travel, and an attacker with root there would edit that file,
  not go through this module. After a fresh receive, the receiver is
  asserted to still report `mountpoint=none` and `canmount=off`, and the
  `inherit` properties are asserted not to have arrived (`source` is never
  `received`).

**Not covered:** a resumed receive, which the finding also asks for.
`-o` on resume has historically been fussy, and orchestrating an
interrupted send is a separate piece of work. Recorded in the test header
rather than left implied.

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

**Status: done, 2026-08-27.** What landed is recorded at the end of this
section; the scoping and triage below are kept as written so the
reasoning is auditable, not because anything in them is outstanding.

Phase 4 of the audit proper, and its durable output: everything up to
here either fixed a defect or recorded one, while this turns the
recurring patterns into standing rules so the next service written in
this repo does not reintroduce them.

**Four parts.**

1. Fold [`findings.md`](findings.md) §4's eleven systemic rules into
   `docs/hardening.md`.
2. Promote the threat model to a standing doc — it currently lives
   inside a dated audit directory.
3. Write down accepted risks with their reasoning. **No such document
   exists**: the only matches for "accepted risk" anywhere in `docs/`
   are inside `docs/audits/`.
4. Log deferred items to `TODO.md` — largely done already as the waves
   went.

The `AGENTS.md` row pointing at `docs/audits/` was added earlier in the
audit and needs nothing further.

**Phase 4 touches no host configuration.** It is documentation only, so
nothing in it needs a build or a VM test, and nothing changes deploy
behaviour. That is a meaningful difference from waves 1–3 and should
make it fast.

### Rule-by-rule status, checked against `docs/hardening.md` on 2026-08-27

Do not re-derive this. `docs/hardening.md` is 138 lines; these were
grepped against it directly.

| # | Rule (short) | State |
|---|---|---|
| 1 | Recipient rotation is not value rotation | absent |
| 2 | Give each host only the secrets it consumes | absent |
| 3 | Never generate key material on a snapshotted/replicated filesystem | absent |
| 4 | Docker-published ports bypass the NixOS firewall entirely | **partial** |
| 5 | Scope every firewall rule to an interface | absent |
| 6 | Put privilege on the unit, not the user | absent |
| 7 | Never point a root service at a user-writable path | absent |
| 8 | Keep one backup copy outside any single root's authority | absent |
| 9 | Verify that `extraConfig` actually takes effect | **partial** |
| 10 | `AllowTcpForwarding` defaults to `yes`, not `no` | **done** |
| 11 | Container hardening has no rules at all yet | absent |

So **nine are genuinely new**, and two need finishing rather than
writing:

- **Rule 10 is done.** Corrected in `6b623c0` as part of wave 2 item
  2.3. Nothing left.
- **Rule 9 is scoped to SSH only.** `6b623c0` added the
  first-directive-wins / verify-with-`sshd -T` guidance *inside* the SSH
  bullet. The general principle — NixOS modules render their own
  defaults first, and many config formats are first-directive-wins — is
  still not stated as a rule of its own.
- **Rule 4 is on one host, not the fleet.** `bd6db07` wrote it into
  `hosts/homelab/configuration.nix` as a comment beside the setting it
  rests on. `docs/hardening.md` has a related but *different* bullet
  ("Forwarded/DNAT'd ports get zero protection" from CrowdSec/Anubis/
  Caddy), which is about rate limiting, not about the packet never
  reaching `nixos-fw`. The rule still needs stating fleet-wide.

Worth remembering why these are worth writing: most were found
repeatedly *because* the doc did not say them. Rule 6 is the
`health-check` `disk`-group finding; rule 9 is why `PermitRootLogin`
sits inert in `extraConfig` on homelab and vps; rule 4 is why eight
interface-scoped firewall entries on homelab are decorative.

### Three judgement calls, deliberately left to the user

None was decided, and none should be decided silently:

1. **How much reasoning goes inline.** `docs/hardening.md` is currently
   a tight 138-line checklist. Eleven rules with full justification
   could roughly double it and make it less likely to be read — which
   defeats the purpose. The proposal put to the user was: keep each rule
   **short and imperative** in `hardening.md`, and leave the *evidence*
   in this audit directory, linked. Not yet answered.
2. **Where the threat model lives.** Moving `00-threat-model.md` out of
   the dated directory makes it a living document but breaks the audit's
   internal links; copying it duplicates a 
   long file that will drift. A pointer from `docs/` into the audit copy
   may be cleanest.
3. **Accepted risks is a new file, and cannot be finished yet.** Its
   content depends partly on decisions **D1–D14**, which are still open
   (see [`user-actions.md`](user-actions.md)). It can be scaffolded now
   — the structure and the risks whose acceptance is not in question —
   but not completed.

### What landed

| Part | Where | Note |
|---|---|---|
| 1 — eleven rules | `docs/hardening.md`, new **Standing rules** section | Ten written (rule 10 was already applied in wave 2). Existing content untouched below a new `## Conventions in detail` heading. 138 → ~264 lines. |
| 2 — threat model | `docs/threat-model.md` (new) | Stable pointer, not a move or a copy. Carries a supersession table and a "what is in each section" index. |
| 3 — accepted risks | `docs/accepted-risks.md` (new) | §1 has six entries; §2 lists D1–D14 as explicitly **not** accepted. |
| 4 — deferred → `TODO.md` | `TODO.md` | Phase 4 recorded as landed; D-range corrected to D1–D14; two new deferred items added (container resource ceilings, `userns-remap`). |
| — | `AGENTS.md` | Rows for both new docs; `docs/audits/` and `docs/hardening.md` rows updated. |

Three things beyond the four parts, all in scope for a doc harvest:

- **`docs/procedures/remote-access.md` was asserting a boundary that
  does not exist** — it called the `vps-deploy` forced-command allowlist
  "the actual security boundary" when root arrives anyway through the
  polkit `StartTransientUnit` grant beside it (`F-P8-13`, `F-P0-02`).
  Corrected in place. This is failure mode §7.5, and it is the kind of
  thing a doc harvest should be *looking* for, not only rules that are
  missing.
- **`docs/skills/security-audit/SKILL.md`'s own Phase 4 guidance** now
  names the destinations this run established, so the next audit
  inherits the layout instead of re-deciding it.
- **`user-actions.md` §4 now says where an answer goes** — accepting a
  decision means writing it into `docs/accepted-risks.md` §1 and
  striking it from §2, not leaving it in a commit message.

The container rule is the one that is more than a restatement: nothing
in `docs/hardening.md` covered `oci-containers` at all, and the systemd
sandboxing rule does not reach them, because such a unit's
`serviceConfig` is a `docker run` wrapper. The three live containers
were re-checked while writing it — `--cap-drop=ALL`,
`--security-opt=no-new-privileges:true` and factorio's written reason
for declining `--read-only` are all genuinely present, so the rule
describes what the repo already does *plus* the two dimensions it does
not (resource ceilings, user namespaces), both now in `TODO.md`.

### The three judgement calls — decided by the agent, reversibly

They were left open on purpose, and none was decided silently: each is
recorded here and in `TODO.md`. They were decided rather than blocked on
because Phase 4 is documentation-only and every one is cheap to undo.

1. **How much reasoning goes inline.** Went with the proposal as put:
   short imperative rules, `file:line` evidence linked into this
   directory rather than inlined. The section is ~126 lines for ten
   rules and reads as a checklist, which was the property worth
   protecting.
2. **Where the threat model lives.** It stays in this directory. Moving
   it breaks the section-level citations in eight part reports;
   copying it creates a second copy that drifts. `docs/threat-model.md`
   is a thin stable path to link instead — a future audit repoints one
   line rather than chasing every reference.
3. **Accepted risks: scaffolded, as predicted.** §1 could be completed
   for six risks whose acceptance is genuinely not in question. §2 is
   the honest half — D1–D14 written as "what you would be accepting",
   which is more useful than an empty template and makes the eventual
   write-up mostly a matter of choosing rows.
