---
slug: fix-srv-permissions-stop-three-systems-fighting-ov
created: 2026-08-28
status: in-progress
frozen: false
---

# fix /srv permissions: stop three systems fighting over the same paths

## Original plan

Found 2026-08-28 while diagnosing why `jellyfin.service` was failing on
homelab with `Failed at step CHDIR ... Permission denied`. Initially
suspected the USB/UAS enclosure change
(`d32e2a9`) — it is **not** that: all pools are healthy and imported, and
that fix works.

**The actual cause.** `/srv` is `0770 root:root`. jellyfin runs as uid 999
group `multimedia` — neither root nor in group root — so it has no `x`
(traverse) bit on `/srv` and cannot `chdir` into `/srv/jellyfin/data`,
even though that directory is correctly owned `jellyfin:multimedia`.
Proven directly:

```
# setpriv --reuid=999 --regid=999 --clear-groups ls /srv/jellyfin/data
ls: cannot access '/srv/jellyfin/data': Permission denied
```

**Three systems manage these paths and disagree:**

| source | rule | mode |
|---|---|---|
| this repo, `hosts/homelab/configuration.nix:174` | `d /srv 0770 root root -` | 0770 |
| systemd upstream, `home.conf` | `q /srv 0755 - - -` | 0755 |
| impermanence `create-directories` | `/srv root root 0755` | 0755 |
| this repo, `modules/services/jellyfin.nix:81-86` | `d /srv/jellyfin/* 0770 jellyfin - - -` | 0770 |
| **pinned nixpkgs jellyfin module**, `jellyfinDirs.conf` | `'d' '/srv/jellyfin/*' '700' 'jellyfin' 'multimedia'` | 0700 |

`00-nixos.conf` (this repo's raw `.rules`) sorts first, and
systemd-tmpfiles takes the first line per path — so the repo's values win
over both upstream and impermanence.

> **Corrected 2026-08-28 (F6): impermanence does not belong in that table
> as a combatant.** `create-directories.bash` runs
> `chmod --reference="$realSource"` — it *mirrors* the persist copy rather
> than asserting a mode of its own (same inode, verified `dev=33
> ino=181636`). So it follows whatever the persisted directory already is;
> it never fought the repo's rule. Two systems disagreed, not three:
> this repo's `00-nixos.conf` and systemd's `home.conf`.
>
> D1 survives the correction, for a slightly different reason. The
> argument is no longer "three systems disagree" but "the distro default
> is asserted by `home.conf` and mirrored by impermanence, and this repo
> was the lone dissenter — and the dissent was non-functional."

**Why it broke today specifically, having worked before.** `/srv` is on
homelab's wipe-on-boot root, so impermanence recreates it every boot at
0755. `systemd-tmpfiles-resetup.service` ran during the 2026-08-28 11:27
deploy (it is in the activation log) and re-applied the 0770 rule *after*
impermanence had set 0755. So a **switch** flips `/srv` restrictive and
takes jellyfin down, while a **boot** may leave it working. That ordering
dependence, not any particular mode, is the real defect.

**What the 0770 was reaching for, and why it missed.** The comment at
`hosts/homelab/configuration.nix:166-173` explains that the line
previously read `d /srv 0770 - root root -`, which shifts fields and made
systemd reject it ("Invalid age 'root'"), leaving `/srv` at 0755 "for the
entire life of this config" — a real finding, since `/srv` holds
factorio's token/password and jellyfin's config. An earlier session fixed
the syntax. But locking the shared parent **masked** the exposure instead
of fixing it: the leaf directories are still world-readable today.

| path | mode now | holds |
|---|---|---|
| `/srv/factorio/main` | **0755** uid 845 | factorio account token, game password |
| `/srv/minecraft/vanilla-plus` | **0755** uid 1000 | server state |
| `/srv/jellyfin/{config,data,cache,log}` | 0770 `jellyfin:multimedia` | already restrictive |

So the original finding was never actually closed.

> **Amended 2026-08-28 after the security review (F1-F6 below).** It is
> worse than "never closed". The factorio credentials are **already
> disclosed and unretractable by any permission change**: `/nix/state/.zfs`
> is 0777, `snapdir=hidden` only hides it from `readdir` rather than
> blocking traversal, and 57 retained snapshots hold
> `config/server-settings.json` at 0644. Proven live by reading it as
> uid 65534. `jellyfin` (uid 999) is the internet-reachable service on this
> host and its unit sets `ProtectSystem = true`, not `"strict"`, so
> `/nix/state` is readable from inside its sandbox.
>
> **This plan cannot fix that and must not be read as fixing it.** It stops
> the *next* disclosure. Retracting this one means rotating at
> factorio.com — tracked as `F-P4-04` in the rotation runbook, and the
> priority of that item should rise on the strength of F1.

## Progress

- [x] D1 `/srv` back to the distro default — rule deleted
- [x] D2 delete the redundant jellyfin rules — upstream 0700 now in force,
      verified in the built closure
- [x] D3 tighten the two leaf directories, mode only — **0700, not 0750**
      (revised per F3), declared in the service modules (revised per F4/F5)
- [x] ~~rotate the factorio.com token and game password~~ — F1; the only
      step that retracts anything. **Done 2026-08-28, confirmed 2026-09-01**
      — see F1's resolution below and rotation-runbook.md item 12.
- [x] build homelab, deploy, confirm jellyfin starts and survives
      tmpfiles re-running — **verified 2026-08-28, see G3**
- [ ] separate plan for `/nix/state/.zfs` being 0777 — F1's root cause,
      broader than this plan — see
      `2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md`

### G3 — deployed and verified 2026-08-28

Deployed to homelab. The activation restarted
`systemd-tmpfiles-resetup.service`, which is the exact trigger that broke
jellyfin before, so the failure condition was reproduced rather than
avoided. Then re-ran that unit **again** by hand and waited for it to
complete (it takes minutes — it walks the ACL rules on the 2.5 TB
`/storage` and `/storage-bulk`), which is a stronger test than the
"switch twice" this plan originally called for: a second switch of an
unchanged config would not have restarted the unit at all.

Final state, after `systemd-tmpfiles-resetup` completed:

```
drwxr-xr-x  root     root        /srv
drwx------  jellyfin multimedia  /srv/jellyfin/data
drwx------  845      845         /srv/factorio/main
drwx------  1000     1000        /srv/minecraft/vanilla-plus
```

`jellyfin.service` active; `setpriv --reuid=999 --regid=999 ls
/srv/jellyfin/data` succeeds; zero failed units. Both game containers
(`docker-factorio-main`, `docker-minecraft-vanilla-plus`) stayed running
on their now-0700 directories, which is expected — each runs as the uid
that owns its directory, so 0700 costs them nothing. That was the main
risk in tightening from 0755 and it did not materialise.

## Decisions (D)

### D1 — `/srv` returns to 0755 root:root, by deleting the rule

`/srv` is a *namespace*, not a secret. Two other systems (systemd's own
`home.conf`, impermanence) actively assert 0755, so any other value is
permanently fighting them and wins only by file-sort accident. The
service names under it are not the sensitive thing; the data inside is.

`0770 root:root` is not a stricter version of correct — it is
non-functional, because nothing under `/srv` runs as root or group root.

0711 (traverse but no listing) was considered and rejected: it still
fights `home.conf`, and hiding directory *names* buys little when the
names are already in a public repo.

**The fix is deletion, not a different number** — remove the rule and let
the defaults agree.

### D2 — delete this repo's jellyfin tmpfiles rules

`modules/services/jellyfin.nix:81-86` duplicates what the pinned nixpkgs
jellyfin module already does via the typed `systemd.tmpfiles.settings`
API (`jellyfinDirs.conf`), and only serves to *loosen* it from 0700 to
0770 by winning the sort. Letting the module own its own directories
removes the conflict.

### D3 — tighten leaf directories by mode only, never ownership

~~`/srv/factorio/main` and `/srv/minecraft/vanilla-plus` go to **0750**.~~

**Revised 2026-08-28 after the security review: 0700, not 0750** (F3). The
group bit granted nothing — `getent group 845` and `getent group 1000` are
both empty and `mutableUsers = false`, so no group access existed to
preserve. More to the point, D3's own argument (the container image
controls PGID, so do not depend on it) is an argument *for* 0700; 0750 was
half-applying the plan's own reasoning.

**Also revised: the rules live in `modules/services/{factorio,minecraft}.nix`,
not in the host file** (F4, F5). A `z` line silently becomes a no-op if its
path is renamed, so separating mode from path recreates the same
silent-failure shape as the `Invalid age 'root'` bug this plan exists to
remove. Co-locating means a rename breaks both together or neither.

This is where the confidentiality belongs — but see F1: it protects
against the *next* disclosure, not the one that already happened.

**Set mode, leave user/group as `-`.** Neither container pins
`PUID`/`PGID` — uids 845 and 1000 come from the container images'
defaults (`factoriotools/factorio:2.1.14`, `itzg/minecraft-server`), not
from this repo. Hardcoding them would mean an image bump silently locks a
service out of its own data, which is the same class of bug being fixed
here.

Root-run consumers are unaffected: restic runs as root (bypasses the
mode) and zrepl replicates below the filesystem layer.

### D4 — use `systemd.tmpfiles.settings`, not `.rules`

`.rules` is raw positional strings, which is exactly where the original
field-shift bug came from and sat undetected for the life of the config.
The typed API cannot shift fields.

## Gotchas (G)

### G1 — the better fix is upstream's, and this repo opted out of it

The systemd-blessed mechanism for service-owned state is
`StateDirectory=`/`CacheDirectory=`/`LogsDirectory=`, which makes systemd
create and own the directories from the unit's own `User=`/`Group=` with
no tmpfiles involved at all. That is only available under `/var/lib` etc.
This repo overrides jellyfin's dirs to `/srv/...`, which forfeits it —
live `systemctl show jellyfin.service -p StateDirectory` is empty.

Not changed here, because moving jellyfin's data back to `/var/lib` is a
migration with real risk and no urgency. Recorded so the reason for the
current shape is written down: if there is no strong reason for `/srv`,
moving back deletes this entire problem class rather than fixing one
instance of it.

### G2 — a passing deploy is not evidence; a second switch is

The failure mode only appears when `systemd-tmpfiles-resetup` runs after
impermanence. Verifying this fix means switching **twice** and confirming
jellyfin still starts, not just switching once and seeing green.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 — the leaf-mode fix does not close the exposure it exists to close: the factorio token and game password are readable by any local uid through ZFS snapshots, right now

- **File:** `hosts/homelab/configuration.nix:206-209` (the new `z` rules); exposure lives at `/nix/state/.zfs/snapshot/*/srv/factorio/main/config/server-settings.json`
- **Severity:** HIGH
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any local uid on homelab — proven live, not inferred. `setpriv --reuid=65534 --regid=65534 --clear-groups stat …` succeeded on `/nix/state/.zfs/snapshot/zrepl_20260828_195140_000/srv/factorio/main/config/server-settings.json`. The whole chain is traversable by anyone: `/nix/state` 0755, `/nix/state/.zfs` **0777**, snapshot root 0777, `srv` 0755, `factorio` 0755, `main` **0755 845:845** (the historical mode, frozen in the snapshot), `config` 0755, and the file itself **0644**. `snapdir=hidden` only hides `.zfs` from `readdir`; it is still reachable by explicit path. 57 snapshots of `zroot/local/state` are retained. The named adversary with a plausible first step is `jellyfin` (uid 999): it is the one internet-reachable service on this host (vps Caddy + Anubis → wg0 → 10.100.0.2:8096), and the pinned module's unit uses `ProtectSystem = true`, not `"strict"`, so `/nix/state` is fully readable from inside that sandbox. `octodns`, `health-check`, `android-smb`/`smbd` and the 32 `nixbld*` uids reach it the same way.
- **Rule:** same shape as `docs/hardening.md` standing rule 1 ("recipient rotation is not value rotation") — changing who may read a secret going forward does not un-disclose it. Also rule 8 and rule 10's last bullet: this dataset is snapshotted, replicated to `zbackup` by zrepl, and shipped to Backblaze by `restic-backups-backblazeWeekly` (which backs up a mounted snapshot of `zroot/local/state`).
- **Finding:** the plan's own table says `/srv/factorio/main` has been **0755 for the life of this config**, and D3 treats a chmod as the remediation. It is not. `server-settings.json` carries the factorio.com **account token**, the game password and the username, it is mode 0644, and every retained snapshot preserves both the 0755 directory and the 0644 file. Setting the live directory to 0750 changes nothing about the ~57 snapshots already on disk, the copies zrepl has already replicated into `zbackup`, or the copies restic has already pushed to Backblaze. Those credentials should be treated as disclosed to every local principal on homelab for the whole period, and rotated at factorio.com. Rotation is a user action (`docs/procedures/secrets.md`) — this subagent has not decrypted or read anything. Note the value is also *pushed into* that 0644 file from sops on every container start by `modules/services/factorio.nix`'s `mkServerSettingsPatch`, so the plaintext keeps being re-materialised outside sops's control. The same argument applies, less severely, to `/srv/jellyfin/{config,cache,data,log}`: they are **0770 `jellyfin:multimedia` live right now** (verified), so the tightening to upstream's 0700 is prospective only — every snapshot keeps the 0770, and jellyfin's `config` holds its user database and API keys.
- **Fix risk:** rotating the factorio token/password requires a factorio.com credential change plus a `sops secrets/secrets.yaml` edit and a container restart; the game password change disconnects players. Destroying the affected snapshots would break zrepl's replication cursors and the restic history — do not do that as a first move; rotate the values instead, which is the only thing that actually works given the copies already offsite.


**FIXED 2026-09-01:** Rotated at factorio.com 2026-08-28 -- new token + game password in sops, container re-authenticated. See rotation-runbook.md item 12 (marked [x] in the table) for the full record and verification (docker-factorio-main confirmed authenticating with the new token, not just a clean activation log).

### F2 — 0750 on the directory is the single remaining bit protecting a 0755 subdirectory holding a 0644 secret, and nothing re-asserts it between activations

- **File:** `hosts/homelab/configuration.nix:206-209`; `modules/services/factorio.nix:118-141`, `modules/services/factorio.nix:160`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any local uid on homelab (same principal set as F1, e.g. a compromised `jellyfin` uid 999) via the live path `/srv/factorio/main/…` or the identical inode at `/nix/state/srv/factorio/main/…` (verified same `dev=33 ino=181636`), the moment the single 0750 bit is widened by anything.
- **Rule:** new-rule candidate — "don't let one directory bit be the only thing between a service secret and every local uid".
- **Finding:** live state is `/srv/factorio/main/config` 0755 `845:845` and `server-settings.json` 0644 `845:845`. `z` is non-recursive (`Z` is the recursive form), so the change leaves the world bits on the inner directory and on the file itself untouched — the entire confidentiality claim of D3 rests on `main` being 0750. Two things erode that: (a) the factorio container runs its entrypoint as **host uid 0** (no `userns-remap`, per `docs/hardening.md` rule 10) with `--cap-add=CHOWN` and `--cap-add=DAC_OVERRIDE`, and does a `chown -R` over the volume — an image bump that adds a `chmod` on the volume root silently reopens it, which is exactly the "the image controls this, not the repo" risk D3 cites as its reason for not pinning user/group; (b) nothing re-asserts the mode continuously. `systemd-tmpfiles-clean.timer` runs `--clean`, which is age-based deletion only; the mode is applied by `systemd-tmpfiles-setup.service` at boot and by `systemd-tmpfiles-resetup.service` on switch, and nowhere else. So a widened mode persists until the next reboot or deploy. A durable fix has to address the file and the inner directory, not just the volume root.
- **Fix risk:** a recursive `Z` with a fixed mode would fight the container's own `chown -R` and file layout and could strip execute bits from files factorio needs; sizing that correctly needs a container restart test. Tightening `server-settings.json` itself has to survive `mkServerSettingsPatch`, which recreates the file via `jq > "$settings.tmp"; mv` at the unit's umask — that `mv` also silently changes the file's owner to root, so any mode fix must go in that preStart, not only in tmpfiles.

### F3 — the group bit in 0750 is an unused grant; nothing consumes group access to either directory, so 0700 is the correct value

- **File:** `hosts/homelab/configuration.nix:206-209`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** no reachable path *today* — verified on homelab that `getent group 845` and `getent group 1000` both return nothing, and `users.mutableUsers = false` (`hosts/homelab/configuration.nix:399`) with `/var/lib/nixos` persisted, so the id map is stable and no account maps to either gid. The grant becomes reachable the moment an image bump changes `PGID` to a gid that *does* exist on the host — e.g. `users` (100), or a system gid, since NixOS allocates system gids **downward from 999** and would eventually reach 845.
- **Rule:** `docs/hardening.md` "Privilege" (grant only what is actually exercised) — the same principle as standing rule 6, applied to a mode bit instead of a group membership.
- **Finding:** D3 picks 0750 without saying who the group is or why group access is wanted. Nothing in this repo reads these directories as a group: the factorio and minecraft containers reach their data through a bind mount onto `/factorio` and `/data` inside their own mount namespaces (which is precisely why the old `0770 root:root` on `/srv` never broke them and did break host-native jellyfin), restic runs as root, zrepl works below the filesystem layer, and neither Samba nor NFS exports anything under `/srv` (verified: both export only `/storage` and `/storage-bulk`). So the group bit grants read+traverse on a directory holding an account token to a principal set the repo has deliberately chosen not to control. 0700 is strictly better here and costs nothing — and, unlike pinning `user`/`group`, it does not risk locking a service out of its own data on an image bump, so D3's stated reason for leaving ownership unmanaged is not a reason to keep the group bit.
- **Fix risk:** essentially none for these two paths — the container processes access the data as the owning uid through the bind mount, not via group. Confirm by restarting both containers after the change and checking `docker logs` for permission errors.

### F4 — the mode rule is separated from the paths it protects, and `z` fails silently when they drift

- **File:** `hosts/homelab/configuration.nix:206-209` vs `modules/services/factorio.nix:121`, `modules/services/factorio.nix:139`, `modules/services/factorio.nix:160`, `modules/services/minecraft.nix:51`, `modules/services/minecraft.nix:150`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** no adversary today; this is a drift defect that removes protection silently rather than loudly, which is the same failure shape as the original `Invalid age 'root'` bug this plan exists to fix.
- **Finding:** `/srv/factorio/main` is now spelled in four places across two files (persistence entry, preStart `directory` argument, docker `volumes`, and the new tmpfiles rule) with no shared constant, and the tmpfiles rule is the only one living in the *host* file rather than the service module. Two consequences. First, `flake.modules.nixos.factorio` and `.minecraft` are ordinary portable modules (`modules/flake/hosts.nix` only happens to import them on homelab) — enable either elsewhere and its data directory gets no mode at all. Second, `z` "adjusts an existing path and never creates one", which the comment correctly states but does not draw the conclusion from: a rename, or a second server instance, turns the rule into a **no-op that logs nothing and fails nothing**, so the directory quietly reverts to whatever created it. The mode belongs next to the `environment.persistence` entry that creates the path.
- **Fix risk:** moving the rules into the service modules is mechanical; the only thing to check is that nothing else on a future host wants a different mode for the same path (nothing does today).

### F5 — deleting the `/srv` rule replaces a blanket barrier with a two-entry allowlist, and nothing notices when a third thing appears

- **File:** `hosts/homelab/configuration.nix:165-184` (removed rule), `hosts/homelab/configuration.nix:206-209` (replacement)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any local uid on homelab, for any future `/srv/<something>` that is not one of the two enumerated leaves. Verified there is no such thing *today*: `/srv` contains exactly `factorio`, `jellyfin`, `minecraft`, with no orphans left from removed services.
- **Rule:** new-rule candidate — "a per-leaf allowlist needs something that fails when a new leaf appears".
- **Finding:** D1's reasoning that `/srv` is a namespace and not a secret is sound and I agree with it — `q /srv 0755 - - -` really is present in the pinned systemd's `home.conf` (verified in the store) and really does *actively* chmod, so any other value is permanently contested. What the change does not carry over is the property the old rule accidentally had: it covered everything under `/srv`, including things nobody enumerated. `modules/services/factorio.nix` is explicitly written parameterized for a second server ("it was written for two, and the parameters are what a second one would need"); a second instance would get a 0755 data directory and no rule, and neither a build nor a deploy would complain. Worth pairing the leaf modes with something that asserts the set — e.g. deriving the tmpfiles entries from the same list that produces the persistence entries (see F4), so adding a service cannot forget the mode.
- **Fix risk:** none beyond F4's.

### F6 — the plan's "three systems fighting" table misdescribes impermanence, which follows rather than fights

- **File:** `docs/plans/todo/2026-08-28-fix-srv-permissions-stop-three-systems-fighting-ov.md:29-42`; behaviour in the pinned impermanence input's `create-directories.bash`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used (documentation that does not match the code it describes)
- **Reachability:** n/a — this matters because the table is the justification future readers will trust.
- **Finding:** impermanence's `create-directories.bash` only uses the declared mode (`defaultPerms.mode = "0755"`) at `mkdir` time when the *persist-store* directory is missing; on every subsequent activation it runs `chown --reference="$realSource" "$target"` and `chmod --reference="$realSource" "$target"`, i.e. it **mirrors whatever mode the persistent copy has**. Since the persistent copy and the mount point are the same inode (verified: `/srv/factorio/main` and `/nix/state/srv/factorio/main` are both `dev=33 ino=181636`), a tmpfiles chmod through the mount point changes the source too, and impermanence then copies 0750 → 0750 forever. So for the leaf directories there is no ongoing fight and no recurring window; the one window is the *first* creation of a persist directory (fresh install, or a restore that loses it), where impermanence's `mkdir --mode=0755` runs and the directory sits at 0755 until the same activation's tmpfiles pass. Ordering is safe there: `systemd-tmpfiles-setup.service` is `After=local-fs.target` so the bind mounts are up, and on a switch `systemd-tmpfiles-resetup.service` runs after the activation scripts. This is worth correcting because the stated reason for D1 ("permanently fighting them") is only true of `/srv` itself, and D1 is right for a different reason: systemd's `q /srv 0755` actively re-asserts, and lexicographic file precedence made whether the repo's rule applied depend on which file sorted first.
- **Fix risk:** none, it is a plan/comment text change.

### Checked and clean (security subagent, 2026-08-28)

Reviewed the full current content of `hosts/homelab/configuration.nix` and `modules/services/jellyfin.nix`, not only the diff hunks, plus `modules/services/{factorio,minecraft,samba,nfs}.nix` and `modules/flake/hosts.nix` for anything else bound to these paths.

Verified against the pinned source, not from memory (homelab builds from `nixpkgs-stable`, `nixos-26.05`):

- **D2 is correct and is a real tightening.** The pinned stable `nixos/modules/services/misc/jellyfin.nix` emits `systemd.tmpfiles.settings.jellyfinDirs` for all four directories at `mode = "700"` with `inherit (cfg) user group`, unconditionally under `mkIf cfg.enable`. `tmpfiles.d(5)` states: "All configuration files are sorted by their filename in lexicographic order, regardless of which of the directories they reside in. If multiple files specify the same path, the entry in the file with the lexicographically earliest name will be applied" — and the NixOS tmpfiles module writes `systemd.tmpfiles.rules` to `00-nixos.conf` and each `settings.<name>` to `<name>.conf`, so `00-nixos.conf` did beat `jellyfinDirs.conf`. Confirmed live: the four directories are **0770 `jellyfin:multimedia`** today, i.e. the repo's rules really were loosening upstream. After removal nothing else in the merged config declares those paths, so 0700 takes effect; there is no ordering case that leaves them unset. (Prospective only — see F1.)
- **Mode-only `z` does not chown.** `tmpfiles.d(5)`, User/Group section: "For `z` and `Z` lines, when omitted or when set to `-`, the file ownership will not be modified." The NixOS option documentation says the opposite ("the user and group of the user who invokes systemd-tmpfiles is used") because it copies the generic wording; the `z`-specific carve-out is what applies. So D3's "mode only, ownership unmanaged" works as intended and will not chown the volumes to root. The typed API renders correctly quoted positional fields, so D4's claim that field-shift is impossible holds.
- **D1's premise checked.** `q /srv 0755 - - -` is genuinely present in the pinned systemd's `example/tmpfiles.d/home.conf`, and that file is genuinely linked into `/etc/tmpfiles.d` by the `systemd-default-tmpfiles` derivation in `systemd.tmpfiles.packages`. `q` behaves as `d` on non-btrfs and does adjust the mode of an existing directory, so `/srv` will be actively held at 0755 rather than merely defaulting there.
- **No other host uses `/srv`.** Grepped `hosts/torrent`, `hosts/thinkpad`, `hosts/vps`, `hosts/isoimage`, `modules/profiles` and `modules/nixos`: zero references. Nothing depended on the removed rule. Samba and NFS export only `/storage` and `/storage-bulk`.
- **The `/srv` 0770 → 0755 relaxation, in isolation, exposes only names.** `/srv` holds no files, only the three service directories, whose names are already public in this repo. The real regression is not the parent's mode but that the parent is no longer a second barrier — covered in F2 and F5.
- **`z`'s never-create semantics introduce no boot-time window in practice** — see F6 for the ordering analysis. The residual window is first-creation only.
- **No secret was decrypted or read.** All checks on homelab were `stat`, `getent`, `zfs list` and `ls` only. `secrets/*` was not touched; `secrets/secrets.yaml` shows as modified in the working tree but is outside this change's scope and was not inspected.

_security finished 2026-08-28T19:58:22Z -- see Findings above._
