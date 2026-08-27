# P5 — thinkpad and torrent (the interactive workstations)

Phase 1 of the 2026-08-26 fleet-wide security audit. Severity, adversary
ids and confidence labels are those of
[`00-threat-model.md`](00-threat-model.md) §5–§6; the finding schema is
[`P0-findings.md`](P0-findings.md)'s.

**Scope.** `hosts/thinkpad/{configuration,nvidia,disko,hardware-configuration}.nix`
and `hosts/torrent/{configuration,disko,hardware-configuration}.nix`, plus
these two hosts' *call-site* settings for shared modules. The shared
profiles themselves (P1), the pull-deploy module (P7), zrepl (P6) and
home-manager (P8) are other parts'; where a shared-profile setting has a
host-specific consequence only this part can size — the roaming case, and
what these two machines actually hold — it is reported here with the
owning part named.

**Headline.** Threat model §5 rates A7 (anything running as `lilijoy`)
the most likely initial foothold in the fleet. On these two hosts A7 does
not need to escalate to reach fleet root: the private half of one of the
three `flake.vars.publicSshKeys` admin keys sits in `lilijoy`'s home as an
unencrypted file (F-P5-01). Separately, the pull-deploy arrangement does
give `lilijoy` → root locally by three independently confirmed mechanisms,
one of which is already pre-configured in the live checkout (F-P5-03).

**On §4.7 (the repository is public).** Nothing in this report claims or
relies on obscurity, and every reachability assessment below treats
"the adversary knows exactly how this host is configured" as given —
because it is: thinkpad's and torrent's complete service inventory, port
map, usernames, tailnet tags, disk layout and deploy mechanism are
published. Three findings change materially as a result, and say so in
place: F-P5-06 (102 KDE Connect ports plus mDNS **confirmed accepted on
torrent's public IPv6 by the running firewall**, with a daemon listening,
and the same set opened on every network thinkpad joins — raised to HIGH),
F-P5-04 (a stolen laptop whose recoverable age key, against the
permanently-public ciphertext of F-P0-08, decrypts every secret the fleet
has *ever* held, not just today's), and **F-P5-02**, which the §4.7
re-check turned up and which was not in the first pass: a world-readable
age identity in `lilijoy`'s home, against a `.sops.yaml` that encrypts
every secret to every recipient.

**One question is deliberately left open, with the command to close it.**
F-P5-06 establishes that torrent's *host* firewall accepts those ports on
its public IPv6 addresses. Whether an off-LAN source actually reaches
them depends on the ISP CPE, which cannot be determined from inside the
network and which was not probed. F-P5-06 names the exact one-line check
and says what each answer means. It is the highest-value outstanding
verification in this part.

---

## 1. Scope and method

### Files read in full

- `hosts/thinkpad/configuration.nix`, `nvidia.nix`, `disko.nix`,
  `hardware-configuration.nix`
- `hosts/torrent/configuration.nix`, `disko.nix`,
  `hardware-configuration.nix`
- For context, not audited: `modules/profiles/default.nix`,
  `modules/profiles/PC.nix`, `modules/nixos/kde.nix`,
  `modules/nixos/pull-deploy.nix`, `modules/nixos/iso-autobuild.nix`,
  `modules/nixos/nfs-homelab-mounts.nix`,
  `modules/nixos/virtual-machines.nix`, `modules/flake/deploy-guards.nix`,
  `modules/flake/vars.nix`, `modules/flake/hosts.nix`,
  `hosts/homelab/configuration.nix` (the IPv6 comment and the restic
  scope), `docs/hardening.md`, `docs/procedures/remote-access.md`,
  `TODO.md`.

### Pinned-nixpkgs verification

The pinned nixpkgs for both hosts is `nixpkgs-unstable`
`0e251e24a4f24e036a084b6b4b2d2491af4167f4`, resolved via
`nix eval --raw .#nixosConfigurations.torrent.pkgs.path` to
`/nix/store/09g0q2nr523x5inkal66127xmq2z8gw0-…-source`. Modules read
directly out of that tree:

| Claim | Source read |
|---|---|
| sshd renders `settings` **before** `extraConfig` (§7.2 mechanism) | `nixos/modules/services/networking/ssh/sshd.nix:82-89`, `:893` (`lib.mkOrder 0`) |
| `allowSFTP` defaults to `true`, emits the sftp subsystem | same, `:273-276`, `:904` |
| no `AllowTcpForwarding` default in the module → OpenSSH's own `yes` applies | same, no occurrence in file; absent from the rendered config |
| Steam `remotePlay.openFirewall` opens 27036/27037 tcp, 10400/10401/27036 udp, 27031-27035 udp | `nixos/modules/programs/steam.nix:235-256` |
| `programs.kdeconnect` opens 1714-1764 tcp **and** udp, unconditionally, with no `openFirewall` toggle | `nixos/modules/programs/kdeconnect.nix:31-38` |
| waydroid adds `waydroid0` to `trustedInterfaces` | `nixos/modules/virtualisation/waydroid.nix:57` |
| tailscale forces the forwarding sysctls at `mkOverride 97` when `useRoutingFeatures` is `server`/`both` | `nixos/modules/services/networking/tailscale.nix:252-255` |
| `nixos-rebuild boot` still executes the **new** config's bootloader installer as root | `pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs:1843-1846`, `:256-276`; `nixos/modules/system/activation/switchable-system.nix:59` |

### Effective (merged) values

Read with `nix eval .#nixosConfigurations.{torrent,thinkpad}.config.<opt>`,
because several of these differ from what any single file says:
`networking.firewall` (whole tree), `boot.kernel.sysctl`,
`services.tailscale.{useRoutingFeatures,extraUpFlags}`,
`environment.etc."ssh/sshd_config".source` (the *rendered* sshd config —
identical store path on both hosts,
`/nix/store/8pd5zk58…-sshd.conf-final`),
`users.users.{root,lilijoy}.openssh.authorizedKeys.keys`,
`users.users.lilijoy.extraGroups`, `sops.secrets`, `swapDevices`,
`zramSwap.enable`, `environment.persistence`, `nix.settings.*`,
`security.pam.services.*.fprintAuth`, `services.resolved.settings`,
`networking.networkmanager.{wifi,ethernet}.macAddress`,
`specialisation.gpu-enabled.configuration.boot.blacklistedKernelModules`,
and the generated `firewall-start` script.

### Confirmed against the live machine

This session runs **on torrent** (`hostname` → `torrent`). Everything
below was read-only; nothing on the machine or in the repo was modified,
no secret was decrypted, and no private key was read.

- `hostname`, `id`, `ip -brief addr`, `ip -6 route show default`
- `ss -tlnp`, `ss -ulnp` — the real listener set
- `tailscale status` — no routes/exit node advertised by either laptop;
  thinkpad offline (last seen 1d ago), as expected
- `cat /proc/sys/net/ipv{4,6}/conf/all/forwarding` → `1`, `1`
- `swapon --show`, `lsblk`, `zfs get encryption` → no FDE anywhere
- `getent group docker`, `ls -la /run/podman/podman.sock`,
  `ls -la /run/wrappers/bin`
- `ls -la` (metadata only) on `/home/lilijoy/.ssh`,
  `/home/lilijoy/dotfiles`, `/home/lilijoy/dotfiles/.git`,
  `/home/lilijoy/dotfiles/.githooks`, `/etc/ssh/authorized_keys.d`
- `cat /home/lilijoy/dotfiles/.git/config` (not a secret; it is the
  attack surface in F-P5-03), `/home/lilijoy/.ssh/id_ed25519.pub`,
  `/etc/ssh/ssh_host_ed25519_key.pub` (and `ssh-to-age` on that *public*
  key, to compare torrent's derived age identity against `.sops.yaml`),
  and `.sops.yaml` itself — recipient plumbing, which threat model §9
  places in scope
- `stat` (metadata only, contents never read) on
  `/home/lilijoy/.config/sops/age/keys.txt` and
  `/var/lib/sops-nix/key.txt`
- `systemctl cat firewall.service` + `systemctl is-active firewall.service`
  + `journalctl -u firewall.service`, then `cat` of the referenced
  `firewall-start` script in the store. This is the method that closes
  the "is the v6 firewall really open?" question **without root**: the
  running unit's `ExecStart` store path is compared for identity against
  the one the evaluated config produces, and the script itself is
  world-readable. Note that `ip6tables -L` as an unprivileged user
  returns an empty chain — that is a permission failure, not an empty
  ruleset, and must not be reported as one.
- `passwd -S lilijoy` → `lilijoy P 2025-10-25 …`, i.e. a usable password
  last changed 2025-10-25, well after the 2024-12-07 install (P1's
  F-P1-03: the published `initialPassword = "123456"` is **not** live on
  torrent)
- `journalctl -u pull-deploy.service`, `-u iso-build.service`,
  `systemctl list-timers`
- `ps -eo comm=` filtered for torrent clients; `virsh list --all`;
  `systemctl is-active {mullvad-daemon,libvirtd,waydroid-container}`
- A **throwaway** git repo under `/tmp/p5hooktest` (deleted-and-recreated,
  touching nothing real) to demonstrate that git 2.55.0 — the version
  actually on this host — runs `core.hooksPath`'s `post-merge` hook on a
  `git merge --ff-only`.

### What could not be verified

- **thinkpad is offline** and was not contacted — re-confirmed at the end
  of this audit: `tailscale status` reports `offline, last seen 1d ago`
  and `tailscale ping thinkpad` times out. Every thinkpad claim is
  static (config + pinned nixpkgs) except where its config is
  byte-identical to torrent's, which is noted per finding. thinkpad's
  rendered sshd config is the *same store path* as torrent's, so that one
  is as good as live.
- **`passwd -S lilijoy` on thinkpad** — the single check that settles
  P1's F-P1-03 (the published `initialPassword = "123456"`). Confirmed
  NOT live on torrent (password last changed 2025-10-25, after the
  2024-12-07 install). thinkpad is offline, so **this is the one
  outstanding check this part could not perform**, and it should be run
  the next time that laptop is up. Until then the published credential
  must be assumed live there.
- **Inbound IPv6 reachability from off-LAN — partially closed.** What
  *is* CONFIRMED, without root: torrent holds public GUAs with a v6
  default route; the running `firewall.service`'s `ExecStart` store path
  is identical to the evaluated config's; and that script installs the
  1714–1764 and 5353 accepts into `ip6tables` with no interface
  qualifier. So the **host** accepts them on the GUA, and A4 (LAN-local)
  reachability follows with no CPE involved. What is **not** verified is
  whether the ISP CPE forwards inbound v6 from off-LAN — that needs an
  external probe, which this audit did not perform. F-P5-06 gives the
  exact commands (a root-level `ip6tables -L` on torrent, and an
  `nc -6 -vz` / `nmap -6` from `vps`) and states what each answer means,
  so the user can settle it in one line rather than this report guessing.
- **Whether `/home/lilijoy/.config/sops/age/keys.txt` is a live
  `.sops.yaml` recipient.** Determining that means deriving the public
  key from the private one, i.e. reading it — out of bounds for this
  audit. F-P5-02 is PLAUSIBLE on that point and gives the user the
  one-line check.
- **Whether the live firewall chain matches the script that installed
  it.** Step 4 above confirms the unit ran and finished cleanly, and
  nothing in this repo mutates `nixos-fw` afterwards, but a direct read
  of the running chain needs root. The inference is strong; it is an
  inference.
- **Whether `nixpkgs.config.allowBroken = true` on torrent is still
  load-bearing.** Its stated reason (r8125) is refuted — `r8125-9.016.01`
  has `meta.broken = false` in the pinned nixpkgs — but proving nothing
  *else* in the closure needs it requires a build with the line removed,
  which is out of scope for a read-only audit.
- **The `docker`/`libvirtd` question for thinkpad** was confirmed live on
  torrent only; thinkpad shares the same profile so the same conclusion
  should hold, but it is PLAUSIBLE there.

---

## 2. Findings

### F-P5-01 — the fleet-root SSH key is an unencrypted file in the interactive user's home, on both laptops

- **File:** `hosts/torrent/configuration.nix:25`,
  `hosts/thinkpad/configuration.nix:27`, `modules/flake/vars.nix:5-9`,
  live: `/home/lilijoy/.ssh/id_ed25519`
- **Severity:** HIGH
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A7 — anything running as `lilijoy` (browser exploit,
  malicious dependency, bad AI-agent tool call) reads one file and is
  done. Also A8 for thinkpad, via F-P5-04 (no FDE).
- **Rule:** new-rule candidate. `docs/hardening.md` says nothing about
  where admin credentials may live.
- **Finding:** `flake.vars.publicSshKeys` contains
  `ssh-ed25519 AAAA…hZ4q9o lilijoy@torrent`, installed as
  `users.users.root.openssh.authorizedKeys.keys` on homelab, vps and
  isoimage (`docs/procedures/remote-access.md`, "Key model"). The private
  half is `/home/lilijoy/.ssh/id_ed25519` — confirmed by comparing
  `~/.ssh/id_ed25519.pub` against `vars.nix` byte-for-byte. It is a plain
  file, `-rwx------ lilijoy users`, inside a directory `lilijoy` owns. The
  same remote is the repo's `origin` (`git@github.com:LilijoySkyseeker/nixOS.git`),
  so the key is also push access to `origin/master` → F-P0-01 → root on
  all four hosts on the next timer.

  **The key has no passphrase.** `pull-deploy.service` — a non-interactive
  systemd unit with no `SSH_ASKPASS`, no agent, and
  `sshKeyPath = /home/lilijoy/.ssh/id_ed25519` — completed a real
  `git fetch origin` + `Fast-forward` on 2026-08-25 13:41 (journal read
  live). A passphrase-protected key could not have done that. Note also
  that `modules/profiles/PC.nix:166` sets
  `SSH_AUTH_SOCK = "/home/<user>/.bitwarden-ssh-agent.sock"` with a
  literal `<user>` placeholder, so the Bitwarden agent that might
  otherwise hold this key is not in the picture (P8's bug, sized here).

  The consequence is that **F-P0-03's escalation is not on the critical
  path**. A7 does not need root on the laptop; it needs `cat`. The same
  is true on thinkpad, whose key `lilijoy@nixos-thinkpad` is the first
  entry in the same list — and thinkpad is the machine that roams and has
  no FDE.

  Per §4.7, none of this is obscure: `modules/flake/vars.nix` publishes
  the three public keys with `# thinkpad` / `# torrent` comments naming
  which machine holds each private half, and
  `hosts/*/configuration.nix`'s `sshKeyPath` publishes the exact path.
  An adversary does not have to search the filesystem — the repo names
  the file.

  Rated HIGH rather than CRITICAL for consistency with F-P0-01, which is
  also fleet-total and also rated HIGH. By the letter of §6 ("anything
  that yields fleet-wide root") this reads CRITICAL; Phase 2 should decide
  once, for both.
- **Proposed fix:** decision required, but the options are well-shaped:
  (a) put the admin key on the YubiKey only — the third entry in
  `publicSshKeys` is already `sk-ssh-ed25519@openssh.com` resident/FIDO2,
  so the model exists; drop the two software keys from `publicSshKeys` and
  the hosts stop trusting anything a file-read can steal. (b) failing
  that, passphrase-protect both laptop keys and drive them from an agent —
  which forces `myPullDeploy.sshKeyPath` onto a *separate*,
  root-owned, non-admin deploy key with read-only repo scope (a GitHub
  deploy key, not an account key). (c) at minimum, separate the two roles
  the key currently plays: fleet-root SSH and repo pull are not the same
  privilege and should not be the same credential.
- **Fix risk:** (a) makes unattended pull-deploy impossible with that key,
  so it must land together with (b)'s dedicated deploy key or
  pull-deploy silently starts failing every Thursday — the failure is
  quiet (`exit 128`, as the journal already shows happened repeatedly on
  2026-08-25) and nothing pages on it. Rotating `publicSshKeys` also
  requires a deploy to every host *before* the old key is removed
  anywhere, or you lock yourself out; keep the YubiKey enrolled
  throughout. Note the old key survives in homelab's `zbackup` snapshots
  of `zroot/local/home` after rotation (F-P5-12).
- **Owner:** P5 (this), with P1 for `vars.nix`/`PC.nix` and P7 for
  `sshKeyPath`; user decision on which option.

### F-P5-02 — a world-readable age identity sits in `lilijoy`'s home, and `.sops.yaml` encrypts every secret to every recipient

- **File:** live `/home/lilijoy/.config/sops/age/keys.txt`; `.sops.yaml`
  (single `creation_rule`, seven recipients); `modules/profiles/PC.nix:202-216`
- **Severity:** HIGH
- **Confidence:** CONFIRMED for the file's existence, size, mode and
  location, for `.sops.yaml`'s single blanket recipient group, and for
  the stale-recipient finding below. **PLAUSIBLE** for the file being a
  currently-valid recipient of `secrets/secrets.yaml` — establishing that
  requires reading the private key, which this audit does not do. One
  command settles it; it is given under Proposed fix.
- **Axis:** hardening
- **Reachability:** A7 — a `cat` of a mode-`644` file. Also A8 via
  F-P5-04, and note that every service running as `lilijoy` can read it
  too, including `iso-build.service` and `iso-copy-to-downloads.service`,
  whose `ProtectHome = "read-only"` sandbox still permits reads.
- **Rule:** new-rule candidate; interacts directly with F-P0-08.
- **Finding:** `/home/lilijoy/.config/sops/age/keys.txt` exists on
  torrent: 75 bytes, `-rw-r--r--`, `lilijoy:users`, dated 2025-06-10.
  That path is the canonical location the `sops` CLI searches for an age
  identity, and `modules/profiles/PC.nix:209-210` names it explicitly as
  the mechanism that drives interactive `sops` edits on these machines —
  so it is there on purpose, and it is an age *private* key. 75 bytes is
  a single bare `AGE-SECRET-KEY-1…` line with no comment header (contrast
  `/var/lib/sops-nix/key.txt`, 189 bytes `-rw------- root:root`, which is
  full `age-keygen` output with its `# public key:` comment).

  Two things make this serious rather than untidy.

  **`.sops.yaml` has exactly one `creation_rule`, matching
  `secrets/[^/]+\.(yaml|json|env|ini)$`, with all seven age recipients in
  a single `key_group`.** There is no per-secret or per-host scoping
  anywhere. So *any* recipient identity decrypts *every* secret in
  `secrets/secrets.yaml` — homelab's WireGuard private key and PSK, the
  `vps-deploy` private key, the zrepl keys, the restic/Backblaze
  credentials, the Discord webhook, and all four tailscale auth keys —
  not merely the three secrets a laptop actually consumes
  (`tailscale_authkey_<host>`, `git_username`, `git_email`). Whatever
  identity `keys.txt` holds, if it is one of the seven, then A7 on
  torrent reads one world-readable file and has the entire secret store.

  **Under §4.7 / F-P0-08 that becomes retroactive and permanent.** The
  ciphertext and all 72 of its historical revisions are publicly
  downloadable by anyone, forever. An identity that decrypts today's file
  decrypts every revision of it, including secrets rotated long ago. So
  this is not "A7 could read the current secrets"; it is "A7 could read
  every secret the fleet has ever had", and nothing done after the fact
  takes that back.

  **Related, and confirmed: at least one recipient in `.sops.yaml` is
  stale.** torrent's current SSH host key
  (`/etc/ssh/ssh_host_ed25519_key.pub`, world-readable) converts via
  `ssh-to-age` to `age1smm5rghe29g6ldnnltg45dnt705xgfavehgm8vqhmfc4cq8ht4ssduhu5v`,
  which does **not** appear in `.sops.yaml`. The file's `&torrent-age`
  entry is therefore derived from some *other* torrent key — an earlier
  host key, or the user identity above — and `&torrent-machine` is the
  `generateKey` machine identity at `/var/lib/sops-nix/key.txt`. The same
  smell is visible on the other side: `.sops.yaml` carries **three**
  thinkpad-ish identities (`&nixos-thinkpad`, `&thinkpad-ssh`,
  `&thinkpad-machine`) where at most one can be the live
  `sops.age.keyFile`. Each surplus recipient is another key that decrypts
  everything, permanently, whose private half is somewhere nobody is
  tracking. The `&homelab3` name implies two predecessors were already
  retired this way, so the pattern is established.
- **Proposed fix:** three steps, in order.
  1. **Settle the PLAUSIBLE, then act.** The user (not an agent — see
     `docs/procedures/secrets.md`) can run
     `age-keygen -y /home/lilijoy/.config/sops/age/keys.txt` and compare
     the output against `.sops.yaml`'s seven anchors. If it matches any of
     them, treat it as an exposed fleet-wide decryption key.
  2. **Fix the mode regardless of the answer** — `chmod 600`. A private
     key at mode 644 is wrong even if it turns out to decrypt nothing.
  3. **Narrow the recipient set** (P8). Split `.sops.yaml` into per-secret
     or per-host `creation_rules` so a laptop identity decrypts only the
     secrets that laptop consumes, and drop the stale anchors. Then
     `sops updatekeys`. This is the change that actually bounds
     F-P0-08's retroactive-disclosure blast radius, and it is the
     highest-value secrets change available — it is worth more than
     rotating any individual secret, because rotation is not retroactive
     and scoping is.
- **Fix risk:** high-consequence and manual. Removing a recipient that a
  host is actually using breaks that host's boot-time secret decryption,
  which on these hosts means tailscale never comes up — and tailscale is
  how you would reach the host to fix it, so a mistake here is a
  physical-access recovery. `docs/procedures/secrets.md` is explicit that
  secret operations are performed by the user, manually, never by an
  agent; that applies to all three steps. Do step 2 first (zero risk),
  then step 1, then stage step 3 one recipient at a time with console
  access available. Note also that `sops updatekeys` re-encrypts the
  *current* file only — the old ciphertext stays public, so removing a
  recipient protects future secrets, not past ones.
- **Owner:** P8 for `.sops.yaml` and the recipient set; P1 for
  `PC.nix`'s sops block; user for anything touching the key material.
  Raised here because it is only visible from the host.

### F-P5-03 — CONFIRMS F-P0-03: `lilijoy` → root on both laptops via the pull-deploy checkout, three ways

- **File:** `hosts/torrent/configuration.nix:15-26`,
  `hosts/thinkpad/configuration.nix:16-28`,
  `modules/nixos/pull-deploy.nix:102-124`,
  `modules/flake/deploy-guards.nix:24,37-54`
- **Severity:** HIGH
- **Confidence:** **CONFIRMED** — F-P0-03 was PLAUSIBLE; the escalation
  is now demonstrated. Mechanism (1) below is not merely possible, it is
  *already configured* in the live checkout.
- **Axis:** hardening
- **Reachability:** A7 — anything running as `lilijoy`. Trigger is the
  `pull-deploy.timer` (`Thu 03:00`, `Persistent = true`), so the wait is
  at most a week and requires no privilege at all; `minSwitchInterval`
  (7d) gates only the *build/switch* step, not the git steps.
- **Rule:** new-rule candidate.
- **Finding:** `pull-deploy.service` runs as `User = root`, `cd`s into
  `/home/lilijoy/dotfiles` — a directory tree `lilijoy` owns outright
  (`drwxr-xr-x lilijoy users`, `.git/config` mode `-rwxr-xr-x lilijoy`) —
  and then runs git and `nixos-rebuild` there. Three independent paths to
  root:

  **(1) `core.hooksPath` → `post-merge`. Already armed.** The live
  `.git/config` contains `[core] hooksPath = /home/lilijoy/dotfiles/.githooks`,
  and `.githooks/` is `drwxr-xr-x lilijoy users` holding three
  user-written scripts. `deploy-guards.nix:53` runs
  `git merge --ff-only origin/master` as root. Verified in a throwaway
  repo with the host's own git (2.55.0) that a `--ff-only` merge executes
  `post-merge` from `core.hooksPath`; writing
  `/home/lilijoy/dotfiles/.githooks/post-merge` therefore yields root
  code execution on the next cycle that actually fast-forwards. No git
  reconfiguration is required — the hook path is pre-existing repo
  workflow. `deploy-guards.nix:24`'s
  `git config --global --add safe.directory "$(pwd)"` is what makes root
  honour this repo's config in the first place; git's "dubious ownership"
  refusal is exactly the protection being suppressed.

  **(2) Repoint `origin`, and root builds and activates attacker Nix.**
  `require_clean_master` only checks that the tree matches HEAD and that
  HEAD is on `master`; it says nothing about *which* remote `origin` is.
  Rewriting `remote.origin.url` in the user-writable `.git/config` to any
  repo `lilijoy` controls makes `git fetch origin; git merge --ff-only
  origin/master` fast-forward onto attacker commits, after which root runs
  `nixos-rebuild build` and then `nixos-rebuild boot` against them.
  `operation = "boot"` is **not** a mitigation: verified against the
  pinned nixpkgs that `switch-to-configuration` runs
  `do_install_bootloader` for `Action::Boot` as well as `Action::Switch`
  (`switch-to-configuration-ng/src/main.rs:1843-1846`), and that the
  command it runs is `INSTALL_BOOTLOADER`, wired to
  `config.system.build.installBootLoader` **of the new configuration**
  (`switchable-system.nix:59`). So the attacker's Nix code executes as
  root immediately, not at next boot. Note this path also defeats any
  future commit-signature check placed on `origin/master` unless the
  remote URL is itself pinned. Related: the same
  `git fetch` honours `remote.origin.url = ext::…`, which runs an
  arbitrary command as root without needing a hook at all.

  **(3) `.git/config`-specified programs git runs.** With
  `safe.directory` set, `core.fsmonitor` is honoured by the very first
  git command in the script (`git status --porcelain`, before any guard
  runs), and `remote.<name>.uploadpack`, `alias.*`, `diff.external` and
  friends are all attacker-controlled. `GIT_SSH_COMMAND` is exported by
  the guard so `core.sshCommand` specifically is *not* a path — the one
  place the design accidentally closes a door.

  Chain: A7 → root on the laptop → `flake.vars.publicSshKeys`'s private
  halves and the deploy path → F-P0-01 → fleet. (Though per F-P5-01, A7
  already had the key.)

  Rated HIGH per open question §8.4, which pre-commits to that label.
- **Proposed fix:** the root service must not operate on a path the
  unprivileged user can write. Concretely, in rough order of preference:
  (a) drop unattended pull-deploy on the laptops — these are interactive
  machines with a human present, and homelab already carries the
  unattended-patching burden for the fleet; this removes the whole class
  including F-P0-07's TOFU window. (b) give root its own checkout
  (`/etc/nixos`, as homelab already does) with `flakeDir` pointing there,
  a dedicated root-owned read-only deploy key, and the user's clone kept
  separate. If (b), also `git -c protocol.ext.allow=never`,
  `-c core.hooksPath=/dev/null`, `-c core.fsmonitor=false` and an
  explicit `git remote set-url` to the expected URL on every run, so the
  service does not trust repo-local config even in its own checkout, and
  drop the `safe.directory` line since it stops being needed.
  (c) if the user-writable `flakeDir` must stay, it is not a root service
  — run the fetch/build as `lilijoy` (the pattern `iso-autobuild` already
  uses correctly) and hand only the final `switch-to-configuration` to a
  narrowly-scoped privileged step against a store path, which does not
  close the hole but shrinks it.
- **Fix risk:** (b) changes the day-to-day edit-and-test loop on the
  daily driver — `NH_FLAKE`/`FLAKE` at `PC.nix:232-234` point at
  `/home/lilijoy/dotfiles`, and the `.githooks` pre-push build hook lives
  in the user's clone, so both keep working, but "the machine deploys
  what I have checked out" stops being true and that will surprise
  someone. The `sshKeyPath` workaround exists because root has no
  home-manager profile; that constraint has to be *solved* (a root-owned
  deploy key) rather than moved. Whatever lands, VM-test the failure path
  — a pull-deploy that silently stops running is invisible today.
- **Owner:** P7 (mechanism) and P5 (host impact), jointly. Confirmed here.

### F-P5-04 — no disk encryption on either laptop; thinkpad is portable and holds a fleet-root key

- **File:** `hosts/thinkpad/disko.nix:1-84`, `hosts/torrent/disko.nix:1-82`
- **Severity:** HIGH (thinkpad), MEDIUM (torrent)
- **Confidence:** CONFIRMED — live on torrent, static on thinkpad
- **Axis:** hardening
- **Reachability:** A8 — physical. Threat model §5 rates a stolen
  thinkpad plausible, and §6 names "a stolen laptop" explicitly as a
  qualifying first step for HIGH.
- **Rule:** n/a today; this is threat model open question §8.7.
- **Finding:** neither disko layout has any encryption layer. No
  `luks`/`luks2` content type, no `zpool.zroot.rootFsOptions.encryption`,
  no `keylocation`/`keyformat`, and the ESP is plain vfat. Confirmed live
  on torrent: `zfs get encryption zroot` → `off`, and `off` on every
  dataset; `lsblk` shows `nvme0n1p1 vfat /boot`, `nvme0n1p2 swap`,
  `nvme0n1p3 zfs_member`, with no `crypt` devices anywhere. thinkpad's
  `disko.nix` is structurally the same file with a different disk id, so
  the same holds there.

  What an A8 who lifts the thinkpad gets, by simply attaching the NVMe to
  another machine: `/home/lilijoy/.ssh/id_ed25519` — an unencrypted
  private key that is fleet root (F-P5-01) *and* `origin/master` push
  (F-P0-01); `/var/lib/sops-nix/key.txt`, the host age identity; the whole
  home directory; and `/boot` with a writable ESP and no Secure Boot, i.e.
  a trivial evil-maid path if the machine is returned rather than kept.

  **The age key is the part §4.7 changes, and it is the reason this
  finding is more load-bearing than "someone reads my files".** Per
  F-P0-08, `secrets/secrets.yaml` and all 72 of its historical revisions
  are permanently, publicly downloadable, and sops/age is the only
  control in front of them — no network boundary, no rate limit, no
  trace. An attacker can archive that ciphertext today at zero cost,
  years before touching any hardware. `/var/lib/sops-nix/key.txt` on the
  unencrypted root dataset is therefore not "the key to thinkpad's three
  secrets"; it is **the key to every secret the file has ever held that
  thinkpad was a recipient for, including ones rotated long ago**,
  because the old ciphertext is already in the attacker's hands.
  Rotation is not retroactive. Two local facts make this worse rather
  than theoretical: `PC.nix:215-216` sets
  `sops.age.keyFile = "/var/lib/sops-nix/key.txt"` with
  `generateKey = true`, so the identity is created once at first
  activation and thereafter simply persists; and `/` is durable on both
  hosts (F-P5-14 — no impermanence, confirmed
  `environment.persistence = {}`), so that key has been sitting on
  unencrypted disk since install and will remain there indefinitely.

  So the honest statement of A8 against thinkpad is: immediate fleet root
  via the SSH key, *plus* retroactive disclosure of the fleet's secret
  history via the age key. Losing the laptop is not a
  rotate-and-move-on event.

  This materially changes how §4.1 reads. The threat model already says
  so ("the laptop holds a key that is fleet root"); this finding is the
  evidence, and it is unambiguous.

  Recording explicitly, because it bounds the damage: homelab's offsite
  restic run backs up only `zroot/local/state` and `zdata/storage/storage`
  (`hosts/homelab/configuration.nix:110-111`), **not** the `zbackup` pool,
  so the laptop keys are not in Backblaze. They are in homelab's local
  `zbackup/backup/{torrent,thinkpad}/zroot/local/home` — see F-P5-12.
- **Proposed fix:** out of scope to implement per the brief; the plan
  exists on the unmerged `worktree-fde-secureboot-plan` branch (19
  commits, last touched 2026-08-20, per `TODO.md:258-274`). Three things
  that are *in* scope now and cut most of the A8 value without touching
  disko: (a) F-P5-01's fix — get the admin key off the disk and onto the
  YubiKey, which is the single highest-value mitigation available and
  needs no reinstall; (b) F-P5-05's fix for the swap image; (c) treat the
  per-host age key as a high-value credential in its own right rather
  than an install-time incidental, per F-P0-08's proposed fix (a).
  On these two hosts that means narrowing `.sops.yaml` — which,
  per F-P5-02, currently encrypts **every** secret to **every** one of
  seven recipients including three thinkpad identities, when thinkpad
  actually consumes three secrets. Scoping the recipient set is the
  single change that most reduces what a stolen laptop's recovered age
  key can decrypt, historically as well as now, and unlike FDE it needs
  no reinstall. See F-P5-02 for the mechanics and the risk.
- **Fix risk:** the FDE branch predates the dendritic restructuring and
  `TODO.md` already flags reviving it as a real project requiring
  re-derivation against current master, plus a
  `scripts/reinstall-host.sh` orchestrator and a user sign-off on the
  LUKS recovery-passphrase escrow scheme. Do not let this finding
  pressure a rushed rebase; the interim mitigations are the right move.
- **Owner:** user decision (§8.7). P5 supplies the evidence.

### F-P5-05 — unencrypted 16 GiB disk swap on both laptops, and thinkpad hibernates the whole of RAM into it on every lid close

- **File:** `hosts/thinkpad/disko.nix:20-25`,
  `hosts/thinkpad/configuration.nix:41-44`,
  `hosts/torrent/disko.nix:20-25`
- **Severity:** HIGH (thinkpad), MEDIUM (torrent)
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A8 — the same physical adversary as F-P5-04, but this
  one is fixable today without FDE, which is why it is separate.
- **Rule:** **violates an existing `docs/hardening.md` rule** — "Secrets +
  swap": *"prefer `zramSwap.enable = true` over a disk swap partition on
  any host where sops decrypts live secrets (done on `vps`) — disk-backed
  swap risks paging secret material to persistent unencrypted storage."*
- **Finding:** both hosts declare a 16 G plain swap partition with
  `randomEncryption.enable = false` (verified via
  `config.swapDevices`) and `zramSwap.enable = false`. Both hosts decrypt
  live sops secrets: `tailscale_authkey_<host>`, `git_username`,
  `git_email`, plus the age identity at `/var/lib/sops-nix/key.txt`
  (`PC.nix:215-216`). The rule was applied to vps and to no PC host —
  threat model §7.6 exactly.

  Confirmed live on torrent: `swapon --show` reports
  `/dev/nvme0n1p2  partition  16G  5.8G  -2` — 5.8 GiB of this machine's
  memory is on unencrypted disk *right now*, on a box with 91 GiB of RAM
  where a swap partition earns very little.

  thinkpad makes this considerably worse.
  `services.logind.settings.Login.HandleLidSwitch = "hybrid-sleep"`
  (`configuration.nix:42`) means every lid close writes a **complete image
  of RAM** to that unencrypted partition — not just whatever the kernel
  chose to page out. That image contains, by construction: the
  sops-decrypted secrets in `/run/secrets` (ramfs pages are still in the
  hibernation image), the age identity once read, `id_ed25519` if any
  process has it in memory, browser session cookies, and every key
  material any running process holds. On a laptop with no FDE, closing the
  lid is a routine action that persists the entire security state of the
  machine to a partition anyone with the hardware can `dd`.
- **Proposed fix:** two independent changes, both cheap:
  1. Swap: either `zramSwap.enable = true` with the disk partition
     dropped (right for torrent — 91 GiB RAM, the partition is nearly
     pointless), or `swapDevices = [{ device = …; randomEncryption.enable
     = true; }]` (right for a host that genuinely needs disk swap).
     Note these are mutually exclusive with hibernation: `randomEncryption`
     re-keys per boot, so the resume image is unreadable by design.
  2. thinkpad's lid action: `hybrid-sleep` → `suspend`, or
     `suspend-then-hibernate` only once the swap is encrypted. Suspend
     alone leaves keys in RAM (a cold-boot concern), which is a strictly
     smaller exposure than writing them to disk.

  Removing the swap partition also needs the disko layout edited, which is
  a reinstall — so the *deployable-today* fix is `randomEncryption` on the
  existing partition plus the lid change, with the partition removal
  folded into the FDE work.
- **Fix risk:** `randomEncryption` breaks hibernate/resume permanently —
  on thinkpad that is the point, but confirm nobody depends on
  hibernate-to-resume for battery life first, since the lid behaviour
  changes visibly. `zramSwap` on torrent trades disk for RAM under memory
  pressure; with 91 GiB and 49 GiB in use it is comfortable, but check
  during a large `nixos-rebuild`. Both changes are activation-visible and
  should be tested with `nixos-rebuild build` then a real reboot, not
  `switch` alone (swap unit changes do not always apply cleanly live).
- **Owner:** P5.

### F-P5-06 — 102 KDE Connect ports and mDNS are accepted on torrent's public IPv6, with a live daemon behind them — and on every network thinkpad joins

- **File:** effective `networking.firewall.allowed{TCP,UDP}Port{s,Ranges}`
  on both hosts, sourced from `modules/profiles/PC.nix:264-266` (kdeconnect),
  `:286-290` (avahi), `:318-321` (Steam remote play). Rendered:
  `/nix/store/8ys54k…-firewall-start/bin/firewall-start:77-95`
- **Severity:** HIGH (raised from MEDIUM on the first pass, after the
  §4.7 re-read and after closing the v6 question below)
- **Confidence:** **CONFIRMED** that the *running* host firewall on
  torrent accepts these ports over IPv6 on all interfaces including the
  public GUA, and that a daemon is listening. **NOT VERIFIED** whether
  the ISP CPE forwards inbound v6 from off-LAN — see "the one thing I
  could not settle" below, which names the exact commands.
- **Axis:** hardening
- **Reachability:** A4 (LAN-local: a guest device, an IoT thing, a
  compromised phone) — CONFIRMED, no CPE involved. A2 (targeted internet
  attacker via the ISP-delegated IPv6) on torrent — host firewall
  confirmed open, CPE unverified. A4/A2 on *whatever network thinkpad is
  currently sitting on* — coffee shop, conference, hotel — where there is
  no CPE assumption to make in the first place.
- **Rule:** violates threat model §7.1 / §2.2's established pattern
  (`openFirewall = false` + `networking.firewall.interfaces.<iface>`),
  which every audited service has already moved to.
- **Finding:** both hosts carry an identical set of **host-wide** (no
  `-i`) firewall accepts:

  | Proto | Ports | Source | Live listener on torrent |
  |---|---|---|---|
  | tcp | 1714–1764 | `programs.kdeconnect` | `kdeconnectd` on `*:1716` (dual-stack) |
  | udp | 1714–1764 | `programs.kdeconnect` | `kdeconnectd` on `*:1716` (dual-stack) |
  | udp | 5353 | `services.avahi.openFirewall` | `avahi-daemon` on `0.0.0.0:5353` and `[::]:5353` |
  | tcp | 27036, 27037 | Steam `remotePlay.openFirewall` | `steam` on `0.0.0.0:27036` (v4 only) |
  | udp | 10400, 10401, 27031–27035, 27036 | Steam `remotePlay.openFirewall` | `steam` on `0.0.0.0:27036` |

  **Closing the "are these actually open on v6?" question, without
  root.** Reading the live ruleset needs root, and a non-root
  `ip6tables -L` returns an empty chain — a silent permission failure
  that must not be mistaken for an empty ruleset. There is an
  unprivileged path to the same answer, and it is conclusive:

  1. `systemctl cat firewall.service` (readable as `lilijoy`) gives
     `ExecStart=@/nix/store/8ys54k46i6xfhm97pyp19kg5l3mj12wy-firewall-start/bin/firewall-start`.
  2. `nix eval .#nixosConfigurations.torrent.config.systemd.services.firewall.serviceConfig.ExecStart`
     returns the **same store path**. So the unit that is actually
     running is byte-identical to the one the evaluated config produces —
     no config/reality gap to argue about.
  3. That script is world-readable in the store. Its contents settle it:
     ```
     ip46tables() { iptables -w "$@"; ip6tables -w "$@"; }
     ...
     ip46tables -A nixos-fw -p tcp --dport 1714:1764 -j nixos-fw-accept
     ip46tables -A nixos-fw -p udp --dport 1714:1764 -j nixos-fw-accept
     ip46tables -A nixos-fw -p udp --dport 5353      -j nixos-fw-accept
     ip46tables -A nixos-fw -p tcp --dport 22        -j nixos-fw-accept -i tailscale0
     ...
     ip46tables -A nixos-fw -j nixos-fw-log-refuse     # default: DROP
     ```
     Every allow rule except port 22 carries **no `-i`**, and every one
     goes through `ip46tables`, i.e. is installed into `ip6tables` as
     well as `iptables`. Port 22 is the only rule that is
     interface-qualified — which is the proof that the scoping mechanism
     works fine here and simply was not applied to the other three.
  4. `systemctl is-active firewall.service` → `active`, and the journal
     shows `Finished Firewall.` at the current boot with no errors, so
     the rules were installed.
  5. The reverse-path filter would not incidentally save us: it is
     `-m rpfilter --validmark --loose -j RETURN`, and a packet arriving
     from the internet to the GUA passes a loose check trivially given
     the default route out `enp8s0`.

  So, stated plainly: **the running host firewall on torrent accepts
  inbound TCP and UDP 1714–1764 and UDP 5353 on its public IPv6
  addresses, and `kdeconnectd` is bound on `*:1716` for both TCP and
  UDP.** Confirmed live: `enp8s0` carries eight globally routable
  addresses in `2600:1010:a022:496c::/64` alongside `192.168.1.162/24`,
  with a default v6 route via RA — the same ISP-delegated public-IPv6
  situation `hosts/homelab/configuration.nix:357-366` confirmed on
  2026-08-26 for this same LAN segment. `kdeconnectd` and `avahi-daemon`
  bind dual-stack and are therefore exposed on those addresses; Steam
  binds v4-only and is not.

  **The one thing I could not settle, and how to settle it.** Everything
  above is the *host's* posture. Whether an off-LAN source actually
  reaches it depends on the ISP CPE's inbound v6 policy, which cannot be
  determined from inside the network and which I did not probe. Three
  commands, in increasing order of decisiveness:
  - As root on torrent, to see the live chain rather than infer it:
    `ip6tables -L nixos-fw -n -v --line-numbers`
    (run as root — as `lilijoy` this returns empty and means nothing).
  - The actual question, from any host **outside** the home network with
    IPv6 — a VPS, a phone on cellular:
    `nc -6 -vz 2600:1010:a022:496c:6bc8:178e:e6b4:4613 1716`
    or `nmap -6 -Pn -p 1714-1764,5353 <that address>`. Use the
    `mngtmpaddr` (stable) address, not one of the privacy-extension
    temporaries, since those rotate.
  - Note `hosts/vps` is exactly such a host and is already on the
    tailnet, so this is a one-line check the user can run today.

  If that probe answers "open", this is a live unauthenticated internet
  exposure of a desktop-session daemon on the fleet's daily driver — the
  same class as the homelab finding that triggered this entire audit, and
  it should be treated at least as urgently. If it answers "filtered",
  the finding does not go away: the CPE is then load-bearing for the
  security of the daily driver, nothing in this repo configures or
  monitors it, and thinkpad's roaming case (below) has no CPE at all. A
  configuration whose safety depends on an untested property of consumer
  network equipment is precisely the §2.1 "CGNAT illusion" pattern in a
  new costume — the belief was true, then quietly stopped being true, and
  nothing warned anyone.

  §2.1's "it is retroactive" point applies exactly: these three rules
  predate the discovery and were all written under an IPv4-plus-NAT
  assumption. The threat model already lists two of them (`PC.nix:289`,
  `:320`) as known remaining host-wide openings, notes them as P1's to
  fix, and — this is the gap this part fills — **it does not list
  kdeconnect at all**. kdeconnect is the largest of the three (102 ports),
  the only one with no `openFirewall` toggle to turn off, and the only one
  whose daemon is confirmed listening on a public address right now.

  **The roaming case (thinkpad), which is what makes this more than
  tidiness.** Every rule above is unconditional, so the moment thinkpad
  associates with a coffee-shop, conference or hotel network, every other
  client on that L2 segment can reach: `kdeconnectd`, a daemon running as
  `lilijoy` that speaks a pairing protocol to unauthenticated peers and
  whose pre-pair surface (identity packet parsing, the TLS handshake, the
  pairing request path) is exposed before any trust decision is made;
  `avahi-daemon`, an mDNS responder; and Steam's peer-discovery listener.
  If that network delegates a GUA prefix — increasingly the default on
  conference and hotel Wi-Fi — the same set is exposed to the internet at
  large, with no NAT and no CPE in the way. And this is the host that,
  per F-P5-01 and F-P5-04, holds an unencrypted fleet-root SSH key on an
  unencrypted disk.

  **Why HIGH.** No pre-auth exploit in `kdeconnectd` is demonstrated
  here, and this report does not claim one — on the first pass that
  argued for MEDIUM. Three things move it. First, the v6 question is now
  closed on the host side: this is not "a rule that would be risky if the
  network changed", it is an accept rule installed into `ip6tables` on a
  globally routable address today, with a listener behind it. Second,
  §4.7 — the exposure is published, so neither A1's scanners nor A2's
  targeting has to discover anything. Third, the hosts behind the
  exposure hold an unencrypted fleet-root SSH key (F-P5-01) and a
  fleet-wide age identity (F-P5-02), so code execution as `lilijoy` here
  is fleet compromise rather than a desktop incident — and per P1's
  F-P1-01 `lilijoy` is in the `input` group, so an attacker at that
  privilege level also has a raw keylogger on `/dev/input/event*` and can
  harvest the run0 password on the way past. Rated by reachable impact
  per §6, that is HIGH. It becomes a candidate for CRITICAL if the
  external probe named above comes back open, because the entry adversary
  is then A1/A2 rather than A4.

  **§4.7 sharpens the roaming case specifically.** This exposure would
  normally be tempered by an attacker on a café network not knowing what
  a given laptop runs — they would have to scan, and scanning is noisy
  and incomplete. That temper does not exist here. The repository is
  public, so the complete inventory above — which ports, from which
  module, on which host, at which nixpkgs pin — is a lookup, not a scan.
  And the laptop identifies itself unprompted: `kdeconnectd` broadcasts a
  device-identity packet on UDP 1716 to announce itself to peers, and
  `networking.networkmanager.wifi.macAddress = "preserve"` (F-P5-16)
  means the same permanent hardware MAC appears on every network it ever
  joins. So an adversary who has seen thinkpad once can recognise it
  anywhere, look up precisely what it exposes, and know from the same
  source what it holds. §4.7's instruction — never discount a finding
  because an attacker would be unlikely to know about it — applies to
  this finding more directly than to any other in this part.

  Mitigating, and worth recording: `services.avahi.publish` is entirely
  false (`addresses`, `domain`, `hinfo`, `userServices`, `workstation` all
  off), so avahi answers but advertises nothing about the host. Note this
  is a smaller mitigation than it looks now that §4.7 applies — what
  avahi would have advertised is published anyway.
- **Proposed fix:** interface-scope all three, per §2.2's established
  pattern. On torrent that is mechanical:
  `networking.firewall.interfaces.enp8s0.allowed{TCP,UDP}Port{s,Ranges}`
  for the kdeconnect range and 5353, with the host-wide forms removed
  (`services.avahi.openFirewall = false`, Steam
  `remotePlay.openFirewall = false`). kdeconnect has no toggle, so its
  host-wide rules need `lib.mkForce [ ]` on
  `networking.firewall.allowed{TCP,UDP}PortRanges` — or, cleaner, drop
  `programs.kdeconnect.enable` from the shared profile and set it per
  host, since the module's *only* config effect besides the package is
  those firewall rules. On thinkpad, interface names are not stable across
  the networks it joins, so it is a real decision: either accept that
  kdeconnect/avahi/Steam-remote-play do not work on this laptop away from
  home (turn them off there), or scope them to a home-network-only
  NetworkManager dispatcher, or accept the roaming exposure explicitly and
  write that down. Given what thinkpad holds, "off on the laptop" is the
  defensible default.
- **Fix risk:** phone↔desktop KDE Connect, mDNS printer discovery
  (`services.printing` with `brlaser` suggests a real network printer),
  and Steam Remote Play all break in ways that surface as "it just doesn't
  find anything" rather than an error, and none is caught by a build or a
  VM test. Change torrent first (where the interface is stable and the
  home LAN is the intended scope), confirm each of the three still works,
  then decide thinkpad separately.
- **Owner:** P1 owns `PC.nix` and the three settings. P5 owns this
  sizing — the roaming and public-IPv6 consequences are host facts P1
  cannot see. Add kdeconnect to the §2.2 known-host-wide-openings list.

### F-P5-07 — sshd on both hosts is missing most of `docs/hardening.md`'s own SSH baseline; TCP forwarding is enabled on both, and the doc says the opposite

- **File:** `hosts/torrent/configuration.nix:101-109`,
  `hosts/thinkpad/configuration.nix:123-131`; rendered
  `/nix/store/8pd5zk58gfzixlir5m593733647hz14s-sshd.conf-final` (the same
  store path on both hosts); `docs/hardening.md` "SSH" bullet
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening / documentation
- **Reachability:** A5 — a rogue tailnet device is the only thing that
  can reach port 22 here (it is scoped to `tailscale0`). Practical reach
  today is nil, because root's only key is `restrict`-pinned and no
  non-root user has an `authorized_keys`. This is the rubric's
  "violation of an existing rule with no currently demonstrable exploit".
- **Rule:** **violates an existing `docs/hardening.md` rule** — the "SSH"
  bullet.
- **Finding:** first, the good news, because the brief asks it directly.
  **Threat model §7.2's trap does not bite on these two hosts.** Neither
  uses `services.openssh.extraConfig` at all; both set `PermitRootLogin`,
  `PasswordAuthentication` and `KbdInteractiveAuthentication` as
  structured `settings`, which land in the `configFile` half that sshd
  reads *first*. Verified by reading the rendered file: line 10 is
  `PermitRootLogin forced-commands-only`, line 9 `PasswordAuthentication no`,
  line 4 `KbdInteractiveAuthentication no`. Verified by reading
  `sshd.nix:82-89` and `:893` that `configFile` precedes `extraConfig`, so
  there is nothing later to override them. And verified that root's
  `authorizedKeys.keys` on both hosts is exactly one entry:
  `command="…zrepl … stdinserver homelab",restrict ssh-ed25519 …
  homelab-zrepl-pull`. **`docs/procedures/remote-access.md`'s claim — "no
  interactive root login exists on either of those two, from anywhere" —
  is accurate**, subject only to the latent §4.4/F-P0-05 caveat that it
  would evaporate the moment `--ssh` is enabled anywhere.

  Now the gap. The same `docs/hardening.md` bullet lists nine directives
  as the baseline. The rendered config has three of them
  (`PasswordAuthentication no`, `X11Forwarding no`, and `PermitRootLogin`,
  though at a *stricter* value than the rule's `prohibit-password`, which
  is correct for these hosts). The other six are simply absent, so
  OpenSSH's own defaults apply. Every "effective" value below was read out
  of the pinned OpenSSH 10.4p1's own `sshd_config.5`
  (`/nix/store/kq1frjydlzhc7nxrh6fbk5ajafnavvnh-openssh-10.4p1-man`),
  not assumed:

  | Rule wants | Rendered | Effective, per OpenSSH 10.4p1 `sshd_config.5` |
  |---|---|---|
  | `AuthenticationMethods publickey` | absent | `any` (a single factor of any enabled type) |
  | `AllowAgentForwarding no` | absent | **`yes`** ("The default is `yes`") |
  | `AllowStreamLocalForwarding no` | absent | **`yes`** ("`yes` (the default)") |
  | `AllowTcpForwarding no` | absent | **`yes`** ("`yes` (the default)") |
  | `PermitTunnel no` | absent | `no` ("The default is `no`") — the one that is fine by accident |
  | `ClientAliveInterval 60` | absent | `0` ("The default is 0, indicating that these messages will not be sent") — no idle timeout at all |
  | `ClientAliveCountMax 5` | absent | `3` ("The default value is 3") |
  | `allowSFTP = false` "unless actually used" | `allowSFTP` left at its `true` default (`sshd.nix:273-276`) | `Subsystem sftp …` present (rendered line 19). zrepl uses `stdinserver`, not sftp; nothing here needs it |

  **`AllowTcpForwarding`, stated plainly per host, because the
  coordinator asked and because the doc is wrong about it.** On
  **torrent**: not set in `settings`, not set in `extraConfig` (this host
  has no `extraConfig` at all), absent from the rendered
  `sshd.conf-final`, and absent from the NixOS module — **so TCP
  forwarding is ENABLED**. On **thinkpad**: identical in every respect,
  down to the same `sshd.conf-final` store path — **so TCP forwarding is
  ENABLED there too**. Note the precise shape of the problem on these two
  hosts: it is *not* an inert `extraConfig` directive (§7.2), because
  neither host writes one; it is that the directive was never written at
  all, and `docs/hardening.md` told the reader it did not need to be.
  The §7.2 inert-directive variant of this question does arise on homelab
  and vps, which *do* carry `AllowTcpForwarding no` in `extraConfig` — P3
  owns that, and the answer there is different from the answer here.

  The documentation error: `docs/hardening.md` states *"`AllowTcpForwarding`
  defaults to `no` — only flip to `yes` for a specific confirmed need."*
  That is false. Confirmed two independent ways — the pinned `sshd.nix`
  defines no such option or default (so nothing renders it), and OpenSSH
  10.4p1's own man page says `yes` is the default. P6 reached the same
  conclusion from the man page independently. Anyone relying on that
  sentence believes forwarding is off fleet-wide when it is on
  everywhere it is not explicitly set. This is threat model §7.5 in a new
  place: the fleet's standing rulebook asserting a default the software
  does not have, which then propagates into every future service written
  against it.

  **Other `docs/hardening.md` default claims, re-checked on the
  coordinator's instruction.** Since one is now known wrong, the rest
  were verified rather than cited. Two that matter and are **correct**:
  the Tailscale bullet's claim that the module sets
  `net.ipv{4,6}.conf.all.forwarding` *"at a priority that beats a plain
  override"* is right — it is `lib.mkOverride 97` at
  `tailscale.nix:253-254`, which does beat both a plain definition (100)
  and `mkDefault` (1000), so the warning is accurate and load-bearing
  (see F-P5-08). And the SSH bullet's implicit claim that `allowSFTP`
  needs turning off is right — `sshd.nix:273-276` defaults it to `true`.
  No further incorrect defaults were found in the parts of the doc this
  part's scope touches; the CrowdSec/`security.sudo` and
  `DynamicUser`/`StateDirectory` bullets are outside it and were not
  re-verified here.

  Everything here is currently un-exploitable because the only key that
  can log in as root carries `restrict`, which independently disables
  every forwarding type — but that is one `authorized_keys` entry away
  from not being true, and `authorizedKeysInHomedir = true` means
  `~lilijoy/.ssh/authorized_keys` is honoured and is user-writable
  (F-P5-11).
- **Proposed fix:** add the missing directives as **structured
  `settings`**, not `extraConfig` — on these hosts there is no reason to
  use the escape hatch at all, and using `settings` is what keeps §7.2
  from ever applying:
  ```
  services.openssh.allowSFTP = false;
  services.openssh.settings = {
    AuthenticationMethods = "publickey";
    AllowAgentForwarding = false;
    AllowStreamLocalForwarding = false;
    AllowTcpForwarding = false;
    PermitTunnel = "no";
    ClientAliveInterval = 60;
    ClientAliveCountMax = 5;
  };
  ```
  Separately, fix `docs/hardening.md`'s `AllowTcpForwarding` sentence, and
  add a line saying these belong in `settings` rather than `extraConfig`
  — homelab and vps currently carry the identical set in `extraConfig`
  (P3's), which works only because nothing emits a default for them, i.e.
  by luck rather than design.
- **Fix risk:** low but not zero. `AllowTcpForwarding no` would break
  `ssh -L`/`-D` through these hosts if anyone does that (nothing in the
  repo does). `AuthenticationMethods publickey` fails closed and must not
  be set on a host where you have no working key — verify key login works
  *before* the switch. `allowSFTP = false` breaks `scp`/`sftp` on modern
  OpenSSH, which defaults `scp` to the SFTP protocol — confirm nothing
  copies files to these two hosts that way (zrepl does not; it uses
  `stdinserver`). Also note `ClientAlive*` will drop idle sessions,
  including a long-running interactive session on the daily driver.
- **Owner:** P5, with P3/Phase 4 for the `docs/hardening.md` correction
  since it affects homelab and vps too.

### F-P5-08 — CONFIRMS F-P0-06: IP forwarding is on for both laptops, and neither routes anything

- **File:** `modules/profiles/default.nix:79`; effective
  `boot.kernel.sysctl` on both hosts
- **Severity:** LOW
- **Confidence:** CONFIRMED — config, effective sysctls, and live kernel
  state
- **Axis:** hardening / needed-used
- **Reachability:** A5, A4 — a device that can reach a laptop's
  `tailscale0` and use it to route onward; on thinkpad, also any device on
  whatever untrusted network it has joined.
- **Rule:** **violates an existing `docs/hardening.md` rule** —
  "Tailscale forwarding sysctls".
- **Finding:** the P0 finding asked P5 to confirm the "neither laptop
  routes" half. Confirmed, three ways:
  - `services.tailscale.useRoutingFeatures` evaluates to `"both"` on both
    hosts (inherited, no host override).
  - `services.tailscale.extraUpFlags` is exactly
    `["--advertise-tags=tag:torrent"]` and
    `["--advertise-tags=tag:thinkpad"]` — no `--advertise-routes`, no
    `--advertise-exit-node`, on either. Neither host sets
    `--accept-routes` either.
  - Live `tailscale status` on torrent lists only **homelab** as
    `offers exit node`, and reports
    `Some peers are advertising routes but --accept-routes is false`.
    Neither laptop offers anything.

  The consequence is real and live: `boot.kernel.sysctl` evaluates to
  `net.ipv4.conf.all.forwarding = true` and
  `net.ipv6.conf.all.forwarding = true` on **both** hosts, and
  `/proc/sys/net/ipv{4,6}/conf/all/forwarding` on torrent both read `1`
  right now. Verified in the pinned nixpkgs
  (`tailscale.nix:252-255`) that these come from the tailscale module at
  `mkOverride 97` — higher priority than a plain assignment, which is
  precisely the interaction the hardening rule warns about, so anyone
  "fixing" this with a plain `boot.kernel.sysctl` entry would silently
  lose.

  So: two machines forward IP with nothing using it, one of which roams.
  Also confirmed that `networking.firewall.checkReversePath` is `"loose"`
  on both — that comes from the same module (`tailscale.nix:259-261`) but
  applies to `"client"` too, so narrowing does not change it.

  LOW, matching F-P0-06: forwarding alone is not a route, and
  `filterForward = false` with an empty `nixos-filter-forward` means there
  is no policy inviting traffic through. It is the needed/used axis with a
  written rule attached.
- **Proposed fix:** as F-P0-06 proposes — invert the default in
  `modules/profiles/default.nix` to `"client"` and `lib.mkForce "both"` on
  homelab, which also retires vps's override. Fail-safe rather than
  fail-open. No host-level change is needed on thinkpad or torrent once
  the default flips.
- **Fix risk:** getting it backwards silently breaks homelab's exit node
  and its `192.168.1.0/24` subnet route — connectivity-visible, not
  build-visible. Verify with `tailscale status` from torrent afterwards
  (homelab should still read `offers exit node`), and re-check
  `/proc/sys/net/ipv4/conf/all/forwarding` on homelab specifically.
- **Owner:** P1 (the default), with P3 confirming homelab still needs
  `"both"`. P5's half is confirmed here.

### F-P5-09 — `virtualisation.waydroid` makes an Android container bridge a fully trusted firewall interface, and the container is running

- **File:** `modules/profiles/PC.nix:102`; effective
  `networking.firewall.trustedInterfaces = [ "waydroid0" "lo" ]` on both
  hosts; pinned `nixos/modules/virtualisation/waydroid.nix:57`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the configuration and that
  `waydroid-container.service` is active on torrent; PLAUSIBLE for
  exploitability
- **Axis:** hardening / needed-used
- **Reachability:** A7 — an Android app installed into waydroid is a
  distinct, lower-trust execution context than the desktop session, and
  it is exactly the kind of thing an "install this APK" attack lands in.
- **Rule:** threat model §7.1 — a trust decision about an interface.
- **Finding:** the waydroid module unconditionally appends `waydroid0` to
  `networking.firewall.trustedInterfaces`, which does not open specific
  ports — it bypasses the packet filter wholesale for that interface, the
  same construct threat model §4.4 flags as a problem on vps. Anything
  inside the Android container therefore reaches every host-local
  listener regardless of the firewall: sshd on `0.0.0.0:22`, `rpcbind` on
  `0.0.0.0:111`, LLMNR on `5355`, and any port a desktop app happens to
  have open. `systemctl is-active waydroid-container` returns `active` on
  torrent, so this is not hypothetical configuration; `ip -brief addr`
  shows no `waydroid0` at the moment, so the bridge only materialises when
  a session starts, which is why the exposure is intermittent rather than
  constant.

  Needed/used question for P1: is waydroid actually in use on **both**
  hosts, or is it a desktop convenience that arrived via the shared PC
  profile? It is enabled unconditionally at `PC.nix:102` alongside
  `wl-clipboard # for waydroid` at `:83`.
- **Proposed fix:** if waydroid is used, override the module's grant —
  `networking.firewall.trustedInterfaces = lib.mkForce [ "lo" ]` — and
  open only what the Android container actually needs on `waydroid0` via
  `networking.firewall.interfaces.waydroid0`. If it is not used on a given
  host, drop `virtualisation.waydroid.enable` there; that removes the
  grant, the bridge and the container runtime together.
- **Fix risk:** waydroid networking is easy to break subtly — the
  container needs DNS and outbound NAT, and losing the trusted-interface
  grant may break app connectivity in ways that look like "the app is
  broken" rather than a firewall drop. Test with an actual app before and
  after, and check `iptables -L nixos-fw -v` for drops.
- **Owner:** P1 (the `PC.nix` toggle), P5 sizing the firewall
  consequence.

### F-P5-10 — the recovery ISO is auto-built into a user-writable directory, and it bakes in the fleet admin keys

- **File:** `hosts/torrent/configuration.nix:28-36`,
  `modules/nixos/iso-autobuild.nix:14,26-36`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the mechanism and the artefact; PLAUSIBLE
  for the chain, which needs a human step
- **Axis:** hardening
- **Reachability:** A7 → A8-by-proxy. `lilijoy` replaces the ISO in
  `~/Downloads`; the admin later copies it to the Ventoy drive by hand
  (which is the documented workflow) and boots it on a host that needs
  rescuing, as root, with no verification step anywhere in between.
- **Rule:** new-rule candidate.
- **Finding:** `myIsoAutobuild` chains off `pull-deploy.service`'s
  `OnSuccess` and drops
  `nixos-recovery-<version>-x86_64-linux.iso` into
  `/home/lilijoy/Downloads`. The services themselves are **well built** —
  both run as `User = lilijoy` rather than root, with the full sandboxing
  stack (`ProtectSystem = "strict"`, `ProtectHome = "read-only"`,
  `NoNewPrivileges`, `RestrictNamespaces`, `MemoryDenyWriteExecute`,
  narrow `ReadWritePaths`), and the module's comments explain honestly why
  a dedicated user was rejected. This finding is not about the units.

  It is about the artefact. The ISO bakes in `flake.vars.publicSshKeys` as
  `isoimage`'s root `authorizedKeys` and ships copyparty with
  unauthenticated `A = [ "*" ]` on `/` host-wide on port 3923
  (threat model §2, §8.6). It lands in a directory the unprivileged user
  can write, is never verified between build and boot, and its purpose is
  to be booted as root on a broken machine. A7 substituting a trojaned ISO
  gets a root shell on whichever host is being recovered — plus,
  independently, whatever `~/Downloads` write access is worth on its own.

  §4.7 removes the one thing that would have made substitution hard: the
  flake is public and pinned, so an attacker can build a legitimate ISO
  from the same inputs and know exactly what the real artefact looks
  like, down to the filename pattern the cleanup `find` matches. There is
  no "they would not know what to fake" here.

  Confirmed live: the current artefact is
  `nixos-recovery-26.11.20260813.0e251e2-x86_64-linux.iso`, dated
  **2026-08-16** — ten days stale, i.e. the last successful `iso-build`
  predates several master commits. So the freshness the module exists to
  provide is not currently being delivered either, which is the
  needed/used half of this.
- **Proposed fix:** cheap and proportionate — have `iso-copy-to-downloads`
  also write a `.sha256` next to the ISO (from the store path, before the
  copy), and document a "verify before writing to Ventoy" step in
  whichever runbook covers the Ventoy workflow. Better still, drop the
  copy step and point the runbook at the `result` symlink in
  `/var/lib/iso-autobuild` (mode 0700, owned by `lilijoy`, but at least
  the store path is content-addressed and immutable). Separately,
  investigate why the last build is from 2026-08-16 — `pull-deploy` has
  not succeeded end-to-end since, which is itself worth knowing.
- **Fix risk:** none for the checksum; changing the documented Ventoy
  workflow risks the runbook and reality diverging, so change both
  together.
- **Owner:** P5, with P4 for the isoimage's own copyparty posture (§8.6).

### F-P5-11 — `~lilijoy/.ssh/authorized_keys` is honoured, giving A7 a tailnet-reachable persistence foothold

- **File:** effective `services.openssh.authorizedKeysFiles`
  (`%h/.ssh/authorized_keys /etc/ssh/authorized_keys.d/%u`, from
  `authorizedKeysInHomedir = true`);
  `hosts/{torrent,thinkpad}/configuration.nix:110`/`:132`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A7 for installation, then A5 for use — a rogue
  tailnet device with the planted key gets a shell as `lilijoy`, hence
  `wheel`, `libvirtd`, and the machine's contents.
- **Rule:** new-rule candidate.
- **Finding:** port 22 is correctly scoped to `tailscale0` on both hosts,
  and the *declarative* key surface is minimal — `users.users.lilijoy
  .openssh.authorizedKeys.keys` evaluates to `[]`, and
  `/etc/ssh/authorized_keys.d/` on torrent contains only `root`. But
  `AuthorizedKeysFile` includes `%h/.ssh/authorized_keys`, a path inside
  a directory `lilijoy` owns, and `~/.ssh` on torrent contains no
  `authorized_keys` today. So A7 can create one, and thereafter re-enter
  from any tailnet device — surviving a reboot, surviving a
  `nixos-rebuild switch` (nothing manages that file), and invisible to
  anyone reading the Nix config. Given F-P5-04, `/` is durable on these
  hosts, so it survives indefinitely.

  Low, because A7 already has everything on the box; this is a
  persistence and re-entry property, not new authority. Worth closing
  because it is the cheapest kind of backdoor to plant and the hardest to
  notice.
- **Proposed fix:** `services.openssh.authorizedKeysInHomedir = false` on
  both hosts, so only `/etc/ssh/authorized_keys.d/%u` (which is
  Nix-managed and root-owned) is trusted. Costs nothing here — no
  home-directory key file is in use on either host.
- **Fix risk:** if anyone *is* relying on a hand-placed
  `~/.ssh/authorized_keys` on either laptop, they lose access with no
  error message beyond a normal auth failure. Check both hosts for the
  file before switching (torrent: verified absent; thinkpad: unverified,
  it is offline).
- **Owner:** P5. Worth considering fleet-wide (P1/P3), but the value is
  highest here because these are the hosts with an interactive user.

### F-P5-12 — the laptop keys and homes replicate to homelab in plaintext, so key rotation does not retire them

- **File:** `hosts/torrent/configuration.nix:82-93`,
  `hosts/thinkpad/configuration.nix:107-118` (the `myZrepl.serve.datasets`
  call-sites), `hosts/homelab/configuration.nix:187-192`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A9/A5 — anyone with root on homelab, who by §4.1
  already has the fleet, so this adds no *reach*. It adds *lifetime*.
- **Rule:** n/a
- **Finding:** both hosts serve `zroot/local/home` and `zroot/local/root`
  to homelab's zrepl puller. Because there is no ZFS-native encryption
  (F-P5-04), those snapshots land on `zbackup` as plaintext, and they
  contain `/home/lilijoy/.ssh/id_ed25519` — the fleet-root key of
  F-P5-01. The transport is fine (SSH, forced-command, `restrict`) and the
  pull direction is the right one (§4.5); the issue is purely at rest.

  The practical consequence is about F-P5-01's remediation: rotating the
  laptop key removes it from the laptop but **not** from homelab's
  retained zbackup snapshots, whose retention is measured in months
  (`hosts/homelab/configuration.nix:340-341` shows 336-hour staleness
  budgets and long keep windows). Anyone modelling "we rotated the key, so
  the old one is dead" would be wrong.

  This is the same shape as F-P0-08's central point, arriving by a
  different route: rotating a credential does not reach the copies of it
  that already exist. There, the copies are public ciphertext plus a key;
  here, they are ZFS snapshots on homelab. Both mean "we rotated it" is
  not the same as "the old one is dead", and both argue for treating the
  laptops' key material as something to *scope* rather than something to
  *rotate*.

  Recording the bound, because it is better than it could be: the offsite
  restic → Backblaze copy backs up only `zroot/local/state` and
  `zdata/storage/storage` (`hosts/homelab/configuration.nix:110-111`),
  **not** the `zbackup` pool. The laptop keys are therefore not offsite.
- **Proposed fix:** no config change is obviously right; the correct
  response is procedural. When F-P5-01's rotation happens, treat the old
  key as compromised-until-snapshots-expire: remove it from
  `publicSshKeys` and from GitHub *first* (which is what actually revokes
  it), and note in `docs/procedures/secrets.md` that credentials living
  under `zroot/local/home` outlive their rotation in backups. If a
  stronger property is wanted later, ZFS-native encryption on the source
  datasets (raw send) is the mechanism, and it belongs with the FDE work.
- **Fix risk:** none for the doc note. Raw-send encryption is a
  significant zrepl change (P6) and would break homelab's ability to
  mount the backups for the restic path if it were ever extended to them.
- **Owner:** P5 to raise; P6 if raw send is ever pursued.

### F-P5-13 — threat model §4.3's `lilijoy` → root paths are wrong in both directions: `docker` is dead, `libvirtd` is unmodelled

- **File:** `modules/profiles/PC.nix:304-315`,
  `modules/nixos/virtual-machines.nix:9-18`
- **Severity:** LOW
- **Confidence:** CONFIRMED live on torrent; PLAUSIBLE on thinkpad
  (offline, same profile)
- **Axis:** needed-used / documentation
- **Reachability:** A7. Not new authority — `wheel` already exists — but
  the threat model's map of *how* should be right.
- **Rule:** threat model §7.4 (grants that outlive their reason) for the
  first half; §7.5 for the second.
- **Finding:** two corrections to §4.3.

  **`docker` is dead config.** `users.users.lilijoy.extraGroups` evaluates
  to `["networkmanager" "wheel" "dialout" "input" "docker" "libvirtd"
  "input"]`, but `virtualisation.docker.enable` is `false` (only
  `virtualisation.podman` with `dockerCompat = true` is configured, at
  `PC.nix:111-113`), so no `docker` group is ever created. Confirmed live:
  `getent group docker` exits 2, `id` for the logged-in `lilijoy` shows
  `users wheel dialout networkmanager libvirtd input flatpak` and **no
  docker**, and `/var/run/docker.sock` does not exist. The podman socket
  that does exist is `srw-rw---- root podman /run/podman/podman.sock`, and
  `lilijoy` is not in `podman`. So threat model §4.3 path 1 — "membership
  in `docker` is root-equivalent by design" — does not currently hold on
  either laptop. It is exactly the pattern §7.4 predicts (the grant
  outlived its reason), just with the teeth already gone. Also note the
  duplicated `"input"` entry, harmless but a sign the list is not
  maintained.

  P1 reached the same conclusion independently and the coordinator has
  since corrected §4.3, so this is recorded as confirmation rather than
  as a new claim.

  **`libvirtd` is a real root-equivalent path §4.3 did not list.**
  `modules/nixos/virtual-machines.nix:11` adds `lilijoy` to `libvirtd`,
  reached transitively via `PC.nix:18`'s import of the
  `virtual-machines` module — so it never appears in `PC.nix`'s own
  `extraGroups` list and is invisible to anyone auditing that list alone,
  which is presumably why the threat model missed it while catching
  `docker`. Membership in that group means the ability to define a domain with
  arbitrary host block devices or filesystem passthrough and start it —
  root-equivalent in the same way `docker` would have been. Confirmed
  live: `libvirtd` is in `id`'s group list, `virsh -c qemu:///system list
  --all` works and shows a defined `win11` domain (shut off), so this is
  in genuine use rather than vestigial. `virtualisation.spiceUSBRedirection`
  additionally installs `/run/wrappers/bin/spice-client-glib-usb-acl-helper`
  — confirmed **capability**-based (`-r-x--x--x`), not setuid, so not an
  added concern — while libvirt's own `qemu-bridge-helper` **is** setuid
  root (`-r-s--x--x`).

  For completeness, the setuid/setcap surface available to A7 on torrent
  is: `chsh fusermount fusermount3 mount mullvad-exclude newgrp passwd
  pkexec qemu-bridge-helper sg su umount unix_chkpwd` (setuid) and
  `gamemoded ksgrd_network_helper ksystemstats_intel_helper kwin_wayland
  newgidmap newuidmap spice-client-glib-usb-acl-helper` (setcap).
  `mullvad-exclude` is the least standard of these and comes from
  `services.mullvad-vpn` at `PC.nix:336-339`; the daemon is `active` but
  `mullvad status` reports `Disconnected`, so whether the VPN is actually
  used is a needed/used question for P1.
- **Proposed fix:** drop `"docker"` (and the duplicate `"input"`) from
  `PC.nix:308-314` — it grants nothing today and only creates a
  root-equivalent group the moment someone enables `virtualisation.docker`
  for an unrelated reason. Add `libvirtd` to threat model §4.3 as a third
  path, replacing `docker` as path 1. Neither is urgent; both keep the map
  honest.
- **Fix risk:** none for the group removal, as long as nobody enables
  `virtualisation.docker` expecting `lilijoy` to have access — if they do,
  it fails visibly with a permission error on the socket, which is the
  right failure.
- **Owner:** P1 for `PC.nix`; Phase 2 for the threat-model correction.

### F-P5-14 — thinkpad carries impermanence scaffolding that nothing uses, so `/` looks ephemeral and is not

- **File:** `hosts/thinkpad/disko.nix:67-80`,
  `hosts/thinkpad/configuration.nix:88-89`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used / documentation
- **Reachability:** n/a — a reasoning hazard, not an exposure.
- **Rule:** threat model §7.4.
- **Finding:** thinkpad's disko creates a `zroot/local/state` dataset
  mounted at `/nix/state`, declares
  `fileSystems."/nix/state".neededForBoot = true`, and takes
  `zroot/local/{root,home}@blank` snapshots via `postCreateHook` — the
  complete impermanence setup homelab uses. But
  `config.environment.persistence` evaluates to `{}` on thinkpad, there is
  no `zfs rollback -r zroot/local/root@blank` anywhere in its initrd (the
  only such line in the repo is `hosts/homelab/configuration.nix:463`),
  and `vars.persistRoot` is consumed only by homelab's services. So `/` is
  durable, the `@blank` snapshots are inert, and `/nix/state` is an empty
  mounted dataset that `neededForBoot` makes the boot depend on for no
  reason.

  This matters because a reader — human or agent — who sees `@blank` and
  `/nix/state` will reasonably conclude root is wiped each boot and reason
  about persistence-of-compromise accordingly. It is not. `TODO.md:298-310`
  confirms the migration is planned and not started, and that Phase 2 of
  the FDE branch folds it in.

  torrent does not even have the scaffolding: its `disko.nix` has no
  `local/state` dataset and no `@blank` hooks, so `myZfsSpaceGuard`'s
  emergency prune there falls into the documented "no `@blank`" path and
  destroys every snapshot on the listed datasets. That is the module's
  intended behaviour (`modules/nixos/zfs-space-guard.nix:63-80`) and
  zrepl's replication cursor is a *bookmark*, not a snapshot, so it
  survives — as `hosts/thinkpad/configuration.nix:98-99` says. No finding
  there, recorded so the asymmetry is not mistaken for a bug later.
- **Proposed fix:** either complete the migration (`TODO.md:298`) or,
  until then, add a one-line comment at `hosts/thinkpad/disko.nix:67`
  saying the `state` dataset and `@blank` snapshots are staged for a
  not-yet-enabled impermanence migration and that `/` is currently
  durable. The comment is the cheap fix and removes the trap.
- **Fix risk:** none for the comment. The migration itself needs a
  per-host persist-path audit and VM testing per `TODO.md`.
- **Owner:** P5 for the comment; the migration is its own `TODO.md` item.

### F-P5-15 — `nixpkgs.config.allowBroken = true` on torrent, for a package that is no longer broken

- **File:** `hosts/torrent/configuration.nix:50`
- **Severity:** INFO
- **Confidence:** PLAUSIBLE — the *stated* reason is confirmed dead; that
  nothing else needs it is not proven
- **Axis:** needed-used
- **Reachability:** A6-adjacent — it disables a guard that exists to stop
  known-broken packages entering the closure. No current exploit.
- **Rule:** threat model §7.4.
- **Finding:** `nixpkgs.config.allowBroken = true` sits immediately below
  the `r8125` ethernet-driver lines with the comment
  `# check on next stable release to see if needed`, which dates it and
  names its owner. Against the pinned nixpkgs, `r8125-9.016.01` evaluates
  to `meta.broken = false` (as does `zfs-kernel-2.4.3-6.18.44`, the other
  entry in `boot.extraModulePackages`), so the stated reason no longer
  applies. The setting is host-global, not scoped to that one package, so
  it silently permits *any* broken package anywhere in torrent's closure —
  a much wider grant than the one it was added for, on the machine that is
  the daily driver and the one agents run on.
- **Proposed fix:** remove the line and run `nixos-rebuild build --flake
  .#torrent`. If something else does need it, the build says exactly what,
  and the right fix is then a scoped
  `nixpkgs.config.permittedInsecurePackages`-style narrowing or a
  per-package `.overrideAttrs (_: { meta.broken = false; })` with a
  comment naming it — not a host-wide flag. This is the one finding here
  whose verification is a single build away and was out of scope for a
  read-only pass.
- **Fix risk:** the build fails and tells you why; nothing is deployed.
  Zero risk if tested with `build` rather than `switch`, per the repo's
  own convention.
- **Owner:** P5.

### F-P5-16 — roaming hygiene: stable MAC on every network, and plaintext unauthenticated DNS

- **File:** effective
  `networking.networkmanager.wifi.macAddress = "preserve"`,
  `ethernet.macAddress = "preserve"`;
  `services.resolved.settings.Resolve` = `{DNS = ["8.8.8.8" "1.1.1.1"];
  DNSSEC = false; DNSOverTLS = false;}` — all from
  `modules/profiles/default.nix:203-207` and `PC.nix:93-99`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A4 — anyone operating or observing an untrusted
  network thinkpad joins.
- **Rule:** new-rule candidate.
- **Finding:** two roaming-specific properties that only apply to
  thinkpad in practice and that P1 cannot judge from the shared profile.

  **MAC.** `wifi.scanRandMacAddress` is `true` (good — scanning is
  randomised), but `wifi.macAddress` and `ethernet.macAddress` are both
  `"preserve"`, so once thinkpad *associates*, it presents its permanent
  hardware MAC. Every network it joins gets a stable, globally unique,
  long-lived identifier for the machine, correlatable across venues.

  **DNS.** `networking.nameservers` and
  `networking.networkmanager.insertNameservers` both pin
  `8.8.8.8`/`1.1.1.1`, and `services.resolved` runs with `DNSSEC = false`
  and `DNSOverTLS = false`. Pinning public resolvers does usefully avoid
  trusting a hostile network's DHCP-supplied DNS, which is the right
  instinct — but the queries then leave in plaintext UDP/53 to a
  well-known address, which any network operator can transparently
  redirect or simply read. With DNSSEC off there is no integrity check
  either. The net effect on an untrusted network is that DNS is both
  observable and forgeable, which is the substrate for most of the other
  attacks a hostile network runs.

  Neither is a compromise on its own; both are the kind of thing that
  makes a targeted attack against this specific laptop meaningfully
  easier, and this laptop is fleet-root-adjacent. §4.7 is what turns the
  MAC half from a privacy nit into a security one: normally, recognising
  a laptop across venues tells an attacker little, because they still do
  not know what it runs. Here, recognising it is the whole problem —
  `thinkpad`'s exposed-port list, its user account, its disk layout and
  the fact that it holds a fleet-root key are all a public lookup away,
  so a stable identifier is the single missing link between "some laptop
  in a café" and "the machine that owns the fleet".
- **Proposed fix:** on thinkpad specifically —
  `networking.networkmanager.wifi.macAddress = "random"` (per-connection
  random) or `"stable"` (per-SSID stable, which keeps captive portals and
  home DHCP reservations working while still preventing cross-venue
  correlation); and
  `services.resolved.settings.Resolve.DNSOverTLS = "opportunistic"` with
  `DNSSEC = "allow-downgrade"`, or `true`/`true` if the pinned resolvers
  are kept (both Google and Cloudflare support DoT, and pinning them is
  what makes strict DoT viable here). Consider whether the pinned
  resolvers should be `fallbackDns` rather than `DNS`, so a network's own
  resolver is used for its internal names.
- **Fix risk:** `macAddress = "random"` breaks MAC-based captive-portal
  sessions (you re-authenticate each time) and any home DHCP reservation
  — `"stable"` avoids both and is the safer default. Strict `DNSOverTLS =
  true` fails closed on networks that block 853, which includes some
  captive portals *before* you have logged in, and produces a
  "no internet" symptom that is annoying to diagnose — `"opportunistic"`
  avoids that at the cost of being downgradeable.
- **Owner:** P5 for thinkpad; P1 if the DNS half moves into the shared
  profile.

### F-P5-17 — `rpcbind` listens on all addresses for NFSv4-only mounts that do not need it

- **File:** `modules/nixos/nfs-homelab-mounts.nix:36-45` (the `nfs4`
  mounts), effective `services.rpcbind.enable = true` on both hosts
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** none from off-host today — 111 is not in any
  `allowedPorts`, so the firewall drops it on every interface. A7 and the
  waydroid container (F-P5-09) reach it.
- **Rule:** threat model §7.4.
- **Finding:** both mounts are `fsType = "nfs4"`, and NFSv4 carries
  everything over port 2049 with no portmapper involved. Nonetheless
  `services.rpcbind` is pulled in and, confirmed live on torrent, listens
  on `0.0.0.0:111` and `[::]:111`, TCP and UDP. rpcbind is a classic UDP
  reflection/amplification source and a service with a long CVE history;
  it is correctly firewalled here, so this is a surface-area note, not an
  exposure.

  Also confirmed clean while looking: CUPS listens on `localhost:631` and
  `[::1]:631` only, with `browsing = false`; `systemd-resolved`'s stub is
  on `127.0.0.53`/`127.0.0.54` only; LLMNR is listening on `0.0.0.0:5355`
  and `[::]:5355` but 5355 is not in any allow rule, so it is firewalled.
- **Proposed fix:** `services.rpcbind.enable = lib.mkForce false` on both
  hosts, and confirm the two automounts still mount. If they do not, the
  mounts are not actually v4-only and that is worth knowing.
- **Fix risk:** if anything ever falls back to NFSv3, the mount fails —
  and because the mounts are `x-systemd.automount` with
  `mount-timeout=10` and `retry=0`, the failure is a quiet empty
  directory rather than a boot problem. Test by touching
  `/home/lilijoy/storage` and `/home/lilijoy/storage-bulk` after the
  change.
- **Owner:** P5.

### F-P5-18 — the host is called `torrent` and runs no torrent anything

- **File:** `hosts/torrent/configuration.nix:59`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used / documentation
- **Reachability:** n/a
- **Rule:** threat model §7.5 (a name asserting something the config does
  not implement).
- **Finding:** the brief asks directly, so: the name is **vestigial**.
  There is no torrent client, tracker, or seedbox service anywhere in
  torrent's configuration — a filter over
  `config.systemd.services` for `torrent|transmission|deluge|rtorrent|
  qbit|aria` returns `[]`, and live `ps -eo comm=` matches nothing. No
  port is opened for peer traffic in either direction. The only
  torrent-adjacent things on the box are two *desktop packages* that
  arrive from the shared PC profile and would be on thinkpad too:
  `qbittorrent` (`PC.nix:85`) and `nicotine-plus` (`:60`, a Soulseek
  client). Both are user-launched GUI applications with no systemd unit,
  and because the host firewall has no rule for their listen ports,
  inbound peer connections are dropped even if the application asks a
  router for a forward — so torrenting from this host is
  outbound/hole-punched only, which is the safe posture by accident rather
  than by design. `~/Downloads` contains three `.iso.torrent` files, i.e.
  the user does download torrents interactively; nothing runs unattended.

  The name is load-bearing in several places (`networking.hostName`,
  `myPullDeploy.hostAttr`, `tag:torrent`, `sops.secrets
  .tailscale_authkey_torrent`, `.sops.yaml`, homelab's
  `zbackup/backup/torrent/…`), so renaming is not free. The finding is
  simply that the name should not be read as a statement about what runs
  here — and, more usefully for this audit, that **this is the daily
  driver**.

  **What "daily driver" means for A7, which is the part worth writing
  down.** This is the machine the user is logged into, the machine that
  runs a web browser (`firefox`, `ungoogled-chromium`), Discord, Spotify
  and Steam, the machine with `claude-code` and `vscode-fhs` installed
  (`PC.nix:53,75`), and — confirmed by this very audit session — the
  machine AI agents execute on. It is therefore *the* A7 surface in the
  fleet, and it is the same machine that holds an unencrypted fleet-root
  SSH key (F-P5-01) and a world-readable age identity against a
  decrypt-everything recipient set (F-P5-02), hosts a user-writable
  root-service working directory (F-P5-03), has firewall accepts for 102
  KDE Connect ports on a public IPv6 address (F-P5-06), and — per P1's
  F-P1-01 — puts `lilijoy` in the `input` group, i.e. gives that same
  privilege level a raw keylogger over `/dev/input/event*`. Those
  findings are individually rated; the point here is that they all land
  on the *same* host, they compose (the keylogger defeats the
  passphrase you might add to the SSH key; the age identity defeats the
  rotation you might do afterwards), and it is the host with the most
  code of unknown provenance running on it. Any remediation ordering
  should treat torrent and thinkpad first for that reason.
- **Proposed fix:** no config change. Add a one-line comment at
  `hosts/torrent/configuration.nix:59` recording that the name is
  historical and that this host is the interactive daily driver, so the
  next reader does not go looking for a seedbox — and so the A7 framing
  above is written down where it will be found.
- **Fix risk:** none.
- **Owner:** P5.

---

## 3. Listening ports and firewall scoping

### torrent — live, from `ss -tlnp` / `ss -ulnp` on 2026-08-26

Addresses held: `enp8s0` `192.168.1.162/24` **+ eight GUAs in
`2600:1010:a022:496c::/64`** (ISP RA-delegated, default v6 route present);
`tailscale0` `100.110.203.119/32`, `fd7a:115c:a1e0::3a01:cb8f/128`.
`enp15s0u1u2` and `wlp9s0` down.

| Port | Proto | Bound to | Process | Firewall scope | Effectively reachable by |
|---|---|---|---|---|---|
| 22 | tcp | `0.0.0.0`, `[::]` | sshd | `interfaces.tailscale0` only | tailnet (A5); waydroid0 when up (F-P5-09) |
| 1716 | tcp+udp | `*` (dual-stack) | `kdeconnectd` | **host-wide 1714–1764** | LAN (A4) **and the public v6 GUAs** — F-P5-06 |
| 5353 | udp | `0.0.0.0`, `[::]` | `avahi-daemon` (+ steam, spotify) | **host-wide** | LAN (A4) **and the public v6 GUAs** — F-P5-06 |
| 27036 | tcp+udp | `0.0.0.0` | `steam` | **host-wide** (also 27037 tcp, 10400/10401/27031-27035 udp) | LAN v4 only (steam binds v4) |
| 111 | tcp+udp | `0.0.0.0`, `[::]` | `rpcbind` | **not opened** — dropped | localhost, waydroid0 — F-P5-17 |
| 5355 | tcp+udp | `0.0.0.0`, `[::]` | `systemd-resolved` (LLMNR) | **not opened** — dropped | localhost, waydroid0 |
| 631 | tcp | `127.0.0.1`, `[::1]` | CUPS | loopback bind | localhost |
| 53 | tcp+udp | `127.0.0.53`, `127.0.0.54` | `systemd-resolved` stub | loopback bind | localhost |
| 41641 | udp | `0.0.0.0`, `[::]` | `tailscaled` | **not opened** (`openFirewall` false) | DERP/NAT-traversal only |
| 54562 / 41745 | tcp | tailnet v4 / v6 addr | `tailscaled` | tailnet-address bind | tailnet |
| 57621, 39705, 54409, 1900 | tcp/udp | `0.0.0.0` | Spotify (Connect, SSDP) | **not opened** — dropped | localhost |
| 6463 | tcp | `127.0.0.1` | Discord RPC | loopback bind | localhost |
| 57343 / 36755 / 43191 | tcp | `127.0.0.1` | steam | loopback bind | localhost |

### thinkpad — derived from the evaluated config (host offline, not contacted)

The firewall tree, the rendered `sshd_config` store path, and every
`services.*` toggle below are byte-identical to torrent's, so the *scoping*
column is CONFIRMED; which user applications happen to be running is not.

| Port | Proto | Source | Firewall scope | Roaming risk |
|---|---|---|---|---|
| 22 | tcp | `services.openssh` (`openFirewall = false`) | `interfaces.tailscale0` only | **None.** Correctly scoped; unreachable from a café LAN. The one thing that is right by construction. |
| 1714–1764 | tcp+udp | `programs.kdeconnect` (no toggle) | **host-wide** | **Highest.** `kdeconnectd` runs as `lilijoy` and its pre-pair surface is exposed to every stranger on the segment, and to the internet if the network delegates a GUA. 102 ports. F-P5-06. |
| 5353 | udp | `services.avahi.openFirewall = true` | **host-wide** | **High.** mDNS responder answering arbitrary queries from a hostile segment. Mitigated by `publish.*` all being false, so it discloses little. |
| 27036/27037 tcp, 10400/10401/27031-27035 udp | | Steam `remotePlay.openFirewall = true` | **host-wide** | **Medium**, and only while Steam is running. Steam binds v4-only, so no v6 exposure; still a listener for strangers on the LAN. |
| 111 | tcp+udp | `services.rpcbind` (NFS client) | not opened | None from the network; F-P5-17 is about surface, not exposure. |
| 5355 | tcp+udp | `systemd-resolved` LLMNR | not opened | None. |
| 631 | tcp | CUPS, `listenAddresses = ["localhost:631"]` | loopback bind | None. |
| 41641 | udp | `tailscaled` | not opened | None inbound. |

**Roaming summary for thinkpad.** Joining an untrusted network exposes
exactly three things — KDE Connect (102 ports), avahi, and Steam Remote
Play — none of which the laptop needs *away from home*, all three of which
are host-wide by inheritance rather than by decision, and all three of
which sit in front of a machine holding an unencrypted fleet-root SSH key
and a fleet-wide age identity on an unencrypted disk. That combination,
not any one port, is the finding. Everything else this host listens on is
either loopback-bound or scoped to `tailscale0`, which is a good
baseline — the fix is to bring these three into line with it, not to
redesign anything.

Two things worth stating explicitly about the roaming case, because they
are what separate it from torrent's. First, the accepts are installed
into `ip6tables` with no interface qualifier (proven for torrent in
F-P5-06; thinkpad's firewall config is identical), so if the network
thinkpad joins delegates a GUA prefix — increasingly the default on
conference and hotel Wi-Fi — the exposure is to the internet directly,
not merely to the local segment. Second, there is no CPE question to
defer here. torrent at least sits behind a home router whose inbound v6
policy is unknown-but-possibly-restrictive; a café network's is unknown
by definition, varies per venue, and is frequently permissive. So the
uncertainty that softens torrent's rating does not apply to thinkpad at
all — for the roaming host, "the host firewall accepts it" is the whole
answer.

---

## 4. Checked and clean

Examined, and found correct. Recorded so a later pass does not re-derive
it, and so anything that regresses is visibly a regression.

**SSH, which was the brief's main "verify rather than trust" item.**
- Neither host uses `services.openssh.extraConfig`, so threat model §7.2's
  first-directive-wins trap **does not apply here**. All three security
  directives are structured `settings` and land in the `configFile` half
  that sshd reads first. Verified by reading the rendered
  `sshd.conf-final` (identical store path on both hosts) *and* the pinned
  `sshd.nix:82-89`/`:893`.
- `PermitRootLogin forced-commands-only` is genuinely in force on both.
- `PasswordAuthentication no` and `KbdInteractiveAuthentication no`
  likewise — no repeat of the homelab/vps password-auth incident here.
- `users.users.root.openssh.authorizedKeys.keys` on both hosts is exactly
  one entry, `command="…zrepl … stdinserver homelab",restrict`. The
  shared admin key list is **not** installed on these two, exactly as
  `docs/procedures/remote-access.md` says.
- Conclusion: **`docs/procedures/remote-access.md`'s claim that "no
  interactive root login exists on either of those two, from anywhere" is
  accurate as written**, with the single caveat already recorded as
  F-P0-05 (it becomes false the instant Tailscale `--ssh` is enabled
  anywhere, because the ACL's `ssh` block already grants device-to-device
  root and bypasses sshd entirely). The doc would be improved by naming
  that dependency; that is P8's finding, not a new one.
- Port 22 is `openFirewall = false` + `interfaces.tailscale0
  .allowedTCPPorts = [22]` on both — the §2.2 pattern, applied correctly.
- No user has declarative `authorizedKeys`; `/etc/ssh/authorized_keys.d/`
  on torrent contains only `root`. (The *writable* home-directory path is
  F-P5-11.)

**Tailscale and routing.**
- Neither host advertises routes or an exit node, in config or live.
  Neither sets `--accept-routes`. Each uses its own non-reusable,
  pre-tagged auth key. `--ssh` is off, per `default.nix:81-93`'s
  well-argued comment.
- `services.tailscale.openFirewall` is false, so UDP 41641 is not opened.

**Secrets plumbing — the *declared* half only** (no secret was decrypted
or read). Note this section is narrower than it was on first pass: the
§4.7 re-check turned up F-P5-02, so the recipient set and the user-held
identity are **not** clean and are excluded here.
- torrent declares exactly `git_email`, `git_username`,
  `tailscale_authkey_torrent`; thinkpad the same with its own authkey. No
  stale per-host secret declared, nothing declared that is not consumed.
  (What each host is *entitled to decrypt* is a different and much larger
  set — F-P5-02.)
- `tailscale_authkey_*` renders `0400 root:root` at
  `/run/secrets/…`; `/run/secrets` and `/run/secrets.d` are unreadable to
  `lilijoy` (confirmed live: permission denied).
- `/var/lib/sops-nix/key.txt`, the machine identity, is `-rw------- root:root`
  — correct. (Its problem is that it lives on an unencrypted disk,
  F-P5-04, not its mode.)
- The `git-identity` template writes to `/home/lilijoy/.config/git/identity`
  owned by `lilijoy`, which is correct — it holds only a name and email,
  and the whole point (per `PC.nix:218`) is keeping them out of the store.
- `PC.nix:202-214`'s long comment on why `sops.age.sshKeyPaths` is
  deliberately *not* set is correct and matches the upstream limitation it
  cites. Worth noting it also means torrent's SSH-host-key-derived age
  identity is not used by `sops-install-secrets` at all, which is what
  made the stale `&torrent-age` recipient in F-P5-02 visible.

**Nix daemon trust.** `nix.settings.trusted-users = ["root"]` on both —
`lilijoy` is *not* a trusted nix user, so the nix daemon is not a privesc
path. `allowed-users = ["@wheel"]` correctly narrows who may talk to it at
all. This is better than the default and worth not regressing.

**Boot.** `boot.loader.systemd-boot.editor = false` on both (no kernel
cmdline editing at the boot menu — meaningful given F-P5-04). No
autologin: `services.displayManager.autoLogin.enable = false`.
`boot.zfs.forceImportRoot = false`.

**thinkpad's `nvidia.nix`.** The specialisation trick is subtle and it
works. `boot.blacklistedKernelModules` evaluates to
`["nouveau" "nvidia" "nvidia_drm" "nvidia_modeset" "usblp"]` on the
default profile and `["nouveau" "nova_core" "nvidiafb" "usblp"]` inside
`specialisation.gpu-enabled` — i.e. the blacklist and the
device-removal udev rules, both guarded by
`lib.mkIf (config.specialisation != {})`, correctly do *not* leak into the
specialisation, because the NixOS specialisation module resets
`specialisation` to `{}` in child configs. Verified by evaluating both.
The guard is self-referential and depends on that upstream behaviour, so
it is worth a comment, but it is not broken. No security concern in the
file: no `nvidia-persistenced`, no `nvidiaSettings` privileged helper
beyond the standard package, no `hardware.nvidia.datacenter`.

**`myIsoAutobuild`'s units** (as distinct from the artefact, F-P5-10).
Both run as `lilijoy` rather than root, with the full sandboxing stack
that `docs/hardening.md` asks for on a build-only job:
`ProtectSystem = "strict"`, `ProtectHome = "read-only"`,
`NoNewPrivileges`, `ProtectKernel{Modules,Tunables,Logs}`,
`ProtectControlGroups`, `RestrictNamespaces`, `LockPersonality`,
`RestrictRealtime`, `MemoryDenyWriteExecute`, `PrivateTmp`, and narrow
`ReadWritePaths`. The module comments explain honestly why a dedicated or
dynamic user was rejected. This is the repo's hardening baseline applied
properly, and it is a useful contrast with `pull-deploy`, which correctly
takes only `NoNewPrivileges` because it performs real activation.

**Backups posture at the call-sites.** Both hosts are `serve`-only
(passive) with `clients.homelab.publicKey = vars.zreplPullerKey`; neither
holds a credential for homelab; retention is homelab's. That is §4.5's
recommended arrangement, and the comments at
`hosts/torrent/configuration.nix:70-81` and
`hosts/thinkpad/configuration.nix:91-106` state the reasoning correctly,
including why thinkpad's on-box snap job matters most. Confirmed the
offsite restic scope excludes `zbackup`, bounding F-P5-12.

**Other host-specific config with no security consequence found.**
`services.keyd` (root daemon, unix-socket control, standard remap config);
`services.fprintd` (see below); `hardware.cpu.intel.updateMicrocode = true`
on thinkpad and the AMD equivalent via
`hardware.enableAllFirmware`/`enableRedistributableFirmware` on torrent —
microcode is current on both; `boot.kernelParams`
(`psmouse.synaptics_intertouch=0`, `intel_pstate=active`) are hardware
workarounds with no security surface; `powerManagement.cpuFreqGovernor =
"performance"` on torrent; both `hardware-configuration.nix` files are
stock generated content with nothing added.

**Noted, not findings, because they are judgement calls someone already
made:**
- thinkpad's `services.fprintd` makes fingerprint auth `sufficient` for
  `polkit-1`, `systemd-run0`, `su` and `login` (confirmed by evaluating
  `security.pam.services.*.fprintAuth`). Fingerprint-as-root-elevation is
  weaker than a passphrase against a determined physical adversary, but on
  a laptop with no FDE (F-P5-04) an attacker with the hardware does not
  need to log in at all, so it changes nothing material. Recorded for when
  FDE lands, at which point it becomes worth revisiting.
- `HandlePowerKey = "poweroff"` on thinkpad — fine, and arguably better
  than suspend for A8.
- thinkpad sets no `time.timeZone` while torrent sets
  `America/Los_Angeles`. Cosmetic; mentioned only because it makes log
  correlation between the two hosts slightly harder during an incident.

---

## 5. For other parts

- **P7 (pull-deploy):** F-P5-03 confirms F-P0-03 — treat it as CONFIRMED,
  not PLAUSIBLE. The three mechanisms are `core.hooksPath` (**already set
  in the live `.git/config`**, pointing at a user-writable `.githooks/`),
  a repointed `origin`, and `.git/config`-specified programs
  (`core.fsmonitor`, `ext::` URLs). Two mechanism-level notes you own:
  `operation = "boot"` is not a mitigation, because
  `switch-to-configuration` runs the *new* config's `installBootLoader` as
  root for `Action::Boot` too; and `GIT_SSH_COMMAND` being exported is the
  one thing that closes `core.sshCommand`, which is worth keeping if you
  rewrite the guard. Also: `deploy-guards.nix:24`'s
  `git config --global --add safe.directory` writes to root's
  `/root/.gitconfig` and accumulates one entry per distinct `$PWD`.
- **P7 (F-P0-07):** the TOFU window is not theoretical — torrent's journal
  literally shows
  `Warning: Permanently added 'github.com' (ED25519) to the list of known hosts`
  on 2026-08-25 13:37, i.e. `accept-new` fired on a real host.
- **P1 (`PC.nix`):** four things. (1) `"docker"` in
  `users.users.lilijoy.extraGroups` is **dead** — no such group exists
  (confirmed live), so threat model §4.3 path 1 is currently false;
  `libvirtd` is the real third path and is genuinely used. (2)
  `programs.kdeconnect` is a host-wide 102-port opening that the threat
  model's §2.2 list does not mention and that has no `openFirewall`
  toggle — it needs `lib.mkForce` or per-host enabling. (3)
  `initialPassword = "123456"` at `PC.nix:306` — with `mutableUsers =
  true` this applied only at user creation so the live value is unknown,
  but if unchanged it is console + `run0` root on both laptops, and the
  derived hash is world-readable in the Nix store either way; worth
  confirming with the user rather than assuming. (4)
  `SSH_AUTH_SOCK = "/home/<user>/.bitwarden-ssh-agent.sock"` at
  `PC.nix:166` has a literal unexpanded `<user>` — probably P8's, but it
  is why the fleet-root key is used as a bare file rather than through an
  agent (F-P5-01).
- **P1 (F-P0-06):** P5's half is confirmed — neither laptop routes, in
  config or live, and forwarding is confirmed `1` on torrent's running
  kernel. Flip the default to `"client"` safely.
- **P1 (F-P1-01, the `input` group) — accepted and used, not
  duplicated.** `getent group input` → `lilijoy`, and
  `/dev/input/event*` being `root:input 0660` makes that a raw keylogger
  for A7. This part does not re-rate it; it uses it. It is what makes
  F-P5-01's "A7 already has the key" argument survive the obvious
  objection that the key might one day be passphrase-protected — a
  keylogger captures the passphrase, and the run0 password, and the
  password-manager master password, from the same position. Note the
  grant is not vestigial: `PC.nix:311-312` comments both `dialout` and
  `input` as "for plover", and `programs.plover` is genuinely configured
  at `PC.nix:174-183` with `uinput` udev rules at `:147`. So the fix is a
  narrower mechanism (a `uaccess`/ACL rule for the specific steno device,
  or `input` membership scoped to what plover needs), not simply dropping
  the group.
- **P1 (F-P1-03, `initialPassword = "123456"`) — half settled.**
  Confirmed **not live on torrent**: `passwd -S lilijoy` reports a usable
  password last changed 2025-10-25, well after the 2024-12-07 install.
  **thinkpad could not be checked** — confirmed offline
  (`tailscale ping thinkpad` times out, last seen 1d ago). Running
  `passwd -S lilijoy` there is the single check that settles it, and it
  is the one outstanding verification this part owes. Until then, treat
  the published credential as live on thinkpad, which matters because
  that host also has fingerprint auth `sufficient` for `polkit-1` and
  `systemd-run0` (see "Checked and clean").
- **P3 / Phase 4 (`docs/hardening.md`):** the SSH bullet's claim
  *"`AllowTcpForwarding` defaults to `no`"* is **wrong** — verified twice
  over, against the pinned `sshd.nix` (no such option or default, so
  nothing renders it) and against OpenSSH 10.4p1's own `sshd_config.5`
  ("`yes` (the default)"). P6 reached the same conclusion independently.
  On thinkpad and torrent this means TCP forwarding is **enabled**, and
  not because of an inert `extraConfig` line — neither host writes one.
  P3 owns the different question for homelab and vps, which *do* put
  `AllowTcpForwarding no` in `extraConfig` and where §7.2's
  first-directive-wins trap therefore genuinely applies. Also worth adding
  to the same bullet: put these directives in `settings`, not
  `extraConfig`, so §7.2 can never apply. Re-checked the doc's other
  default claims within this part's scope on the coordinator's
  instruction — the Tailscale `mkOverride 97` priority claim and the
  implicit `allowSFTP` default are both correct; no further errors found.
- **P8 (`.sops.yaml`) — new, and the most actionable thing this part
  found after the §4.7 re-read:** `.sops.yaml` has a single
  `creation_rule` encrypting every secret to all seven age recipients,
  with no per-host or per-secret scoping, while thinkpad and torrent each
  consume three secrets. At least one recipient is confirmed stale
  (`&torrent-age` does not match torrent's current SSH host key, derived
  live via `ssh-to-age`), and there are three thinkpad-ish anchors where
  at most one can be live. Separately,
  `/home/lilijoy/.config/sops/age/keys.txt` exists at mode **644**. Under
  F-P0-08 the combination is retroactive: any of those identities
  decrypts all 72 public historical revisions. See F-P5-02 — narrowing
  the recipient set bounds F-P0-08's blast radius in a way rotation
  cannot.
- **P4 (isoimage):** the recovery ISO built by torrent lands in a
  user-writable `~/Downloads` with no checksum and no verification step
  before it is written to Ventoy (F-P5-10). Whatever you conclude about
  §8.6's unauthenticated copyparty applies to an artefact A7 can swap.
- **P8 (tailnet):** `tailscale status` on torrent shows a non-tagged
  personal device, `pixel-6a` / `LilijoySkyseeker@`, on the tailnet
  alongside the four hosts. Under the flat ACL (F-P0-04) a phone has the
  same reach as any host, including SSH to `lilijoy` on these two laptops
  if a key were ever placed in `~/.ssh/authorized_keys` (F-P5-11).
- **Phase 2 (severity consistency):** F-P5-01, F-P5-02 and F-P5-03 all
  give A7 — the threat model's most likely foothold — either fleet-wide
  root or the entire secret store, which §6's CRITICAL bullet covers
  literally ("anything that yields fleet-wide root"). All three are rated
  HIGH here, for consistency with F-P0-01 (also fleet-total, also HIGH)
  and with §8.4, which pre-commits F-P0-03 to HIGH. Decide once and apply
  it to all of them, rather than letting the same impact carry two labels.
  If Phase 2 does escalate, note that F-P5-04 (A8 + no FDE) inherits the
  same impact by a different route and should move with them.
- **Phase 2 (remediation ordering), given §4.7:** the three cheapest
  changes with the largest effect are all on these two hosts and none
  needs a reinstall — `chmod 600` on the user age identity (F-P5-02 step
  2, zero risk), getting the admin SSH key onto the already-enrolled
  YubiKey (F-P5-01), and narrowing `.sops.yaml`'s recipient set
  (F-P5-02 step 3). Together they cut most of what A7 and A8 currently
  obtain, and they do so *before* the FDE project that would otherwise
  be the prerequisite for any of it.
