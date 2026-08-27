# P1 — shared profiles (`modules/profiles/`)

Part 1 of the 2026-08-26 fleet-wide audit. Scope:
`modules/profiles/default.nix`, `modules/profiles/server.nix`,
`modules/profiles/PC.nix`.

Severity rubric, adversary ids (A1–A9) and failure modes (§7.x) are
[`00-threat-model.md`](00-threat-model.md)'s. Finding schema is
[`P0-findings.md`](P0-findings.md)'s.

**Blast radius reminder.** `profile-default` is on every real host;
`profile-server` on homelab + vps; `profile-pc` on thinkpad + torrent
(and `profile-pc` imports `profile-default`). `isoimage` carries none
of the three. A finding here is a fleet-wide finding and is rated that
way.

**No obscurity is claimed anywhere below.** Per threat model §4.7 this
repository is public, so every default audited here — every group
grant, every open port, every password — is readable by an adversary
who has not yet touched a host. Nothing is discounted on the grounds
that it would be hard to find.

---

## 1. Scope and method

### Files read in full

- `modules/profiles/default.nix` (224 lines)
- `modules/profiles/server.nix` (70 lines)
- `modules/profiles/PC.nix` (341 lines)
- `docs/hardening.md`, `AGENTS.md`, `docs/architecture.md`,
  `00-threat-model.md` (including §4.7, added mid-audit),
  `P0-findings.md`
- `.sops.yaml` — the recipient set and `creation_rules` only. No
  `secrets/*` file was opened, decrypted, or inspected for content.
- Supporting reads, because `profile-pc` imports them and they mutate
  `users.users.lilijoy`: `modules/nixos/virtual-machines.nix`,
  `modules/nixos/wooting.nix`, `modules/nixos/tooling.nix`
- `modules/flake/hosts.nix` (which host gets which profile),
  `hosts/torrent/configuration.nix` and `hosts/thinkpad/configuration.nix`
  (sshd + interface-scoped port 22 only)

### Effective (merged) values

Every claim about a *value* below came from
`nix eval .#nixosConfigurations.<host>.config.<option>`, not from
reading a single file. Hosts queried: `torrent`, `thinkpad`, `homelab`,
`vps`, `isoimage`. This mattered more than once — e.g.
`users.users.lilijoy.extraGroups` in `PC.nix:308-314` lists five
groups, but the merged value is seven, because
`modules/nixos/virtual-machines.nix:11` adds `libvirtd` and
`modules/nixos/wooting.nix:9` re-adds `input`.

### Behaviour verified against the pinned nixpkgs

Pinned trees resolved with
`nix eval --raw .#nixosConfigurations.<host>.pkgs.path`:

| Pin | Store path | Hosts |
|---|---|---|
| unstable | `/nix/store/09g0q2nr…-source` | thinkpad, torrent, vps, isoimage |
| stable | `/nix/store/xk3y420f…-source` | homelab |

Read directly out of those trees, not from memory:

- `nixos/modules/services/networking/tailscale.nix:252-255` —
  `useRoutingFeatures ∈ {server, both}` sets
  `net.ipv{4,6}.conf.all.forwarding` at **`mkOverride 97`**. Priority 97
  beats a plain assignment (100) and `mkDefault` (1000); only `mkForce`
  (50) wins. This is the sysctl-priority interaction `docs/hardening.md`
  warns about, now confirmed rather than assumed. Same file: module
  defaults are `useRoutingFeatures = "none"` and `openFirewall = false`,
  so `default.nix:79` is actively raising it.
- `nixos/modules/services/networking/tailscale.nix:183-234` — the
  auth key is interpolated onto the `tailscale up` **command line**.
- `nixos/modules/services/networking/firewall-iptables.nix:150-208` —
  `allowedTCPPorts`/`allowedUDPPorts` emit
  `ip46tables -A nixos-fw -p tcp --dport N -j nixos-fw-accept` with **no
  interface match**, on both address families. `trustedInterfaces`
  emits `ip46tables -A nixos-fw -i <iface> -j nixos-fw-accept`.
- `nixos/modules/programs/steam.nix:233-256` — `remotePlay.openFirewall`
  opens TCP 27036, 27037 and UDP 10400, 10401, 27036, 27031-27035.
- `nixos/modules/programs/kdeconnect.nix` — `enable` unconditionally
  opens TCP **and** UDP 1714-1764. There is no `openFirewall` toggle to
  turn off.
- `nixos/modules/services/networking/avahi-daemon.nix:447` —
  `openFirewall` opens UDP 5353.
- `nixos/modules/config/users-groups.nix:633-660` — `initialPassword`
  is serialised verbatim into the store-resident `users-groups.json`.
  `nixos/modules/config/update-users-groups.pl:215-232,286-317` — under
  `mutableUsers = true` it is applied **only** when the user has no
  existing `/etc/passwd` entry.
- `nixos/modules/config/users-groups.nix:537-543` —
  `users.groups.<g>.members` is derived from `extraGroups`; an
  `extraGroups` entry naming a group that is not declared anywhere
  produces no group and no membership, and no warning.
- `nixos/modules/security/run0.nix` — **differs between the two pins.**
  Unstable still has `security.run0.enable` and ships the compiled
  `run0-sudo-shim`; stable has dropped `enable` and ships a
  `writeShellScriptBin` alias that refuses any argument starting with
  `-`. `default.nix:53-58`'s `options.security ? run0` /
  `options.security.run0 ? enable` guard handles both correctly
  (verified: `security.run0.enable` evaluates on torrent and does not
  exist on homelab, while `enableSudoAlias = true` on both).
- `nixos/modules/hardware/uinput.nix` — a narrower `uinput` group +
  udev rule exists in the pinned tree and is not used by this repo.
- `nixos/modules/system/boot/resolved.nix:104-120` — `DNSOverTLS` and
  `DNSSEC` both default to `false`.
- `nixos/modules/virtualisation/waydroid.nix:57` — `enable` adds
  `waydroid0` to `networking.firewall.trustedInterfaces`.

### Live state read on `torrent` (this machine)

Read-only, unprivileged, no `sudo`/`run0`:

- `ip -6 addr` — torrent currently holds a **globally-routable IPv6
  address** on the LAN NIC (`2600:1010:a022:496c::/64`, RA-delegated),
  plus a v6 default route. This is the same class of fact as
  threat model §2.1's homelab discovery, and it is what upgrades the
  PC-profile firewall findings from theoretical to live.
- `/proc/sys/net/ipv{4,6}/conf/all/forwarding` — both `1`.
- `id lilijoy`, `getent group docker` — no `docker` group exists;
  lilijoy's real groups are `users wheel dialout networkmanager
  libvirtd input flatpak`.
- `getfacl /dev/input/event0`, `/dev/uinput`, `test -r`/`test -w` —
  lilijoy can read every `/dev/input/event*` and write `/dev/uinput`.
- `passwd -S lilijoy` → `P 2025-10-25`; `/etc/machine-id` ctime
  2024-12-07. Password changed ~11 months after account creation.
- `ss -lnptu`, `lpstat -v`, `systemctl is-active …`, `flatpak list`.
- `grep " /proc " /proc/mounts` — no `hidepid`.
- `/nix/store/*-users-groups.json` — mode `0444`, contains
  `"initialPassword": "123456"`.
- `gh repo view` — **`LilijoySkyseeker/nixOS` is a PUBLIC repository.**
  This was found independently while sizing `initialPassword`, before
  §4.7 was added to the threat model; the two agree. Every rating below
  assumes the adversary has read the configuration in full.
- `ls -l /var/lib/sops-nix/key.txt`, `/etc/ssh/ssh_host_ed25519_key` —
  both `0600 root:root`.

### What I could not verify, and why

- **thinkpad's live password state.** It is a laptop and may be
  offline; it sets `PermitRootLogin = "forced-commands-only"` so there
  is no interactive root SSH, and `/etc/shadow` is not readable
  unprivileged. F-P1-03 is PLAUSIBLE for thinkpad on that account.
- **vps's and homelab's `/etc/shadow`.** An SSH check was blocked by
  the sandbox. F-P1-12 (`mutableUsers` on vps) therefore states the
  configuration fact as CONFIRMED and the console-password consequence
  as PLAUSIBLE.
- **Whether Steam Remote Play and KDE Connect are actually used.** Both
  daemons are running on torrent (`ss` shows `steam` on 27036 and
  `kdeconnectd` on 1716), which proves the software is in use but not
  that the *inbound* holes are needed. Marked as such in F-P1-04.
- **The live IPv6 posture of thinkpad**, which roams. Its config is
  byte-identical to torrent's on every firewall option I queried, so
  the exposure applies wherever it gets a routable address; I could not
  observe it.
- **Tailscale auth-key properties** (reusable? expiring?). The comment
  at `default.nix:72-76` asserts non-reusable, per-host, pre-tagged. I
  did not decrypt `secrets/*`, so that claim is taken on trust.
- **Live nftables/iptables rule dump**, which needs root. Substituted
  the pinned module source, which is deterministic.

---

## 2. Findings

### F-P1-01 — `input` group on `lilijoy` is a raw keylogger on both desktops

- **File:** `modules/profiles/PC.nix:312` (`"input" # for plover`),
  `modules/profiles/PC.nix:139-148` (the udev rules that put `uinput`
  and the 8bitdo hidraw nodes in group `input`),
  `modules/nixos/wooting.nix:9` (re-adds the same group)
- **Severity:** HIGH
- **Confidence:** CONFIRMED for the grant and the device access
  (verified live on torrent); PLAUSIBLE for the final escalation step,
  which is a standard technique I did not execute.
- **Axis:** hardening
- **Reachability:** A7 — anything already running as `lilijoy`: a
  browser exploit, a malicious npm/cargo/flatpak dependency, or a bad
  AI-agent tool call (`claude-code` is in `environment.systemPackages`
  at `PC.nix:75`). Threat model §5 rates A7 the most likely initial
  foothold on this fleet.
- **Rule:** new-rule candidate. `docs/hardening.md` covers dedicated
  *service* users and systemd sandboxing but says nothing about
  interactive-user group grants.
- **Finding:** `lilijoy` is in `input`. `/dev/input/event*` are
  `root:input 0660` with **no** systemd-logind `uaccess` ACL —
  confirmed with `getfacl`, and expected, since systemd deliberately
  does not `uaccess`-tag keyboards. So group membership is the *only*
  thing granting this, and it grants read of every input device on the
  machine: the built-in keyboard, the Wooting, the Gemini PR steno
  machine. Under Wayland, which otherwise blocks X11-style input
  snooping, evdev read is the bypass. A process running as `lilijoy`
  can therefore capture, in plaintext: the password typed into the
  run0/polkit prompt (`security.run0.wheelNeedsPassword` is `true`, so
  every elevation types it), the KDE lock-screen password, the
  Bitwarden desktop master password, and the YubiKey PIN. Having
  captured the first of those, the same process can register its own
  polkit authentication agent and answer its own prompt — no user
  interaction, no further vulnerability, root. Separately, `/dev/uinput`
  is writable (both via the repo's own rule at `PC.nix:147` and via a
  logind `uaccess` ACL), giving synthetic keystroke *injection* into the
  session on top of capture.
  The grant is annotated `# for plover`, and plover is genuinely
  configured (`PC.nix:174-183`, `auto_start = true`). But the machine
  type is `Gemini PR`, a **serial** protocol — that need is served by
  `dialout`, already granted on the line above. What plover actually
  needs from this line is *write* to `/dev/uinput`, not *read* of every
  evdev node.
- **Proposed fix:** replace the blanket `input` grant with the narrower
  primitive the pinned nixpkgs already provides: set
  `hardware.uinput.enable = true` (creates a `uinput` group and its own
  udev rule, `nixos/modules/hardware/uinput.nix`), put `lilijoy` in
  `uinput` instead of `input`, and drop the hand-written `uinput` rule
  at `PC.nix:147`. Then re-point the two 8bitdo `hidraw` rules
  (`PC.nix:142,144`) at a dedicated group rather than `input`, and
  delete the duplicate grant in `modules/nixos/wooting.nix:9`
  (checking first whether `hardware.wooting.enable` already ships its
  own udev rules that make it unnecessary).
- **Fix risk:** breaks plover's keystroke output and the 8bitdo
  configuration tool if the group swap is incomplete — both are
  user-visible immediately but neither is build-visible, so this needs a
  real login and a plover round-trip after switching, not just
  `nixos-rebuild build`. `hardware.wooting.enable` may itself depend on
  `input`; check before removing.
- **Note:** this does not make A7 → root *impossible* — a wheel user
  with an interactive desktop session has other avenues (session-bus
  polkit-agent hijack, `~/.config/fish`, systemd user units). It is
  rated HIGH anyway because §6 asks for reachable impact, and this
  particular grant converts A7 into wholesale credential capture
  (including credentials that are *not* recoverable from the desktop
  session, such as the Bitwarden master password) with no chain and no
  race.

### F-P1-02 — every host holds an age identity that decrypts the whole of a permanently-public ciphertext archive, and two of those hosts have no disk encryption

- **File:** `modules/profiles/PC.nix:215-216`
  (`sops.age.generateKey`/`keyFile`), `modules/profiles/default.nix:155-158`,
  `modules/profiles/server.nix:65`, and the single seven-recipient
  `creation_rule` in `.sops.yaml`
- **Severity:** HIGH
- **Confidence:** CONFIRMED for the recipient set, the key locations
  and their file modes (read live on torrent); CONFIRMED for the
  absence of FDE per threat model §8.7; PLAUSIBLE for the full
  historical-decryption consequence, which follows from §4.7's
  statement that all 72 revisions are public but which I did not
  attempt to demonstrate and could not without decrypting.
- **Axis:** hardening
- **Reachability:** A8 — physical possession of thinkpad, the host the
  threat model singles out as roaming and un-encrypted. Also A7-then-root
  on either desktop, via any of F-P1-01, F-P1-05 or F-P1-03: the key
  files are `0600 root:root`, so this is a second hop rather than a
  first, but every one of those findings supplies the first.
- **Rule:** new-rule candidate. `docs/hardening.md` covers secrets and
  swap (`zramSwap` on hosts that decrypt live secrets) but says nothing
  about recipient scope or about what a host key is worth once the
  ciphertext is public.
- **Finding:** `.sops.yaml` has exactly one `creation_rule`, matching
  `secrets/[^/]+\.(yaml|json|env|ini)$`, with a single `key_groups.age`
  list of **seven** recipients. There is no per-secret or per-host
  scoping anywhere: every recipient decrypts every secret in the file.
  Five of the seven are desktop identities — `nixos-thinkpad`,
  `thinkpad-ssh`, `thinkpad-machine`, `torrent-machine`, `torrent-age`
  — and two of those five (`thinkpad-machine`, `torrent-machine`) exist
  *because* `PC.nix:215-216` sets `sops.age.generateKey = true` with
  `keyFile = /var/lib/sops-nix/key.txt`. The shared profiles are
  therefore what put whole-archive decryption capability onto the
  laptops.
  Per threat model §3, the contents that capability covers include the
  wireguard private key and PSK, the `vps-deploy` private key, the
  zrepl keys, the restic/Backblaze credentials, the Discord webhook,
  and every host's tailscale auth key — i.e. asset #3 in its entirety,
  plus, through `vps-deploy`, a path to root on vps (§4.2). thinkpad
  needs almost none of it; what `profile-default` actually reads there
  is one secret, `tailscale_authkey_thinkpad`, plus `git_username` and
  `git_email`.
  §4.7 is what turns this from "over-broad recipients" into a
  HIGH. The ciphertext is public and permanent, and **rotation is not
  retroactive**: an attacker who archives `secrets/secrets.yaml` today
  — which requires nothing but `git clone` — and later obtains any one
  of these five desktop keys decrypts every secret the file has ever
  held, including secrets rotated years earlier. There is no network
  boundary, no access control and no rate limit in front of that
  offline attack, so the age keys carry the entire weight. And the
  keys sit at `0600 root:root` on `/var/lib/sops-nix/key.txt` and
  `/etc/ssh/ssh_host_ed25519_key` on a **laptop with no full-disk
  encryption** (§8.7: the FDE work is on an unmerged branch). Physical
  possession of thinkpad for a few minutes therefore yields not just
  its own data but the fleet's entire secret history.
  I want to be precise about what is and is not new here. That a
  stolen un-encrypted laptop is bad is not news. What §4.7 changes is
  the *scope and the time axis*: without a public repo, an attacker
  with a stolen host key still has to obtain the ciphertext, and
  rotating a secret after the theft actually helps. With it, neither is
  true.
- **Proposed fix:** two separable pieces, and the second is the cheap
  one.
  1. **Narrow the recipient set.** Split `.sops.yaml` into more than
     one `creation_rule` — at minimum a `secrets/server-*.yaml` whose
     recipients are only homelab and vps, holding the wireguard keys,
     the `vps-deploy` key, the zrepl keys and the restic credentials,
     and a smaller file the laptops can read. The tailscale auth keys
     are per-host already by name; they could be per-host by recipient
     too. Note this only limits *future* exposure — the existing
     ciphertext is already public with the existing recipients, so
     narrowing must be paired with rotating anything a laptop key could
     read. Whoever owns `.sops.yaml` should drive this; P1 raises it
     because the profiles are what create the identities.
  2. **Drop the redundant desktop identity.** `PC.nix:215-216` adds a
     *second* whole-archive key per PC host (`*-machine`) on top of the
     host SSH key that `sops.age.sshKeyPaths` already supplies by
     module default. The comment above it explains why an identity on
     the root filesystem is needed for boot-time decryption — correct —
     but `/etc/ssh/ssh_host_ed25519_key` is also on the root filesystem
     and is already a recipient for both hosts (`thinkpad-ssh`,
     `torrent-age`). If that reasoning holds, one of the two per-host
     identities is redundant and each redundant recipient is another
     permanent decryption key for the public archive. Worth confirming
     before removing, since the two were added at different times for
     different reasons.
  Independently, and this is the real mitigation for A8: FDE on
  thinkpad stops being a nice-to-have. The unmerged
  `worktree-fde-secureboot-plan` branch is the fix for the largest
  single component of this finding.
- **Fix risk:** high, and it must not be rushed. Removing a recipient
  from `.sops.yaml` without re-encrypting leaves that host unable to
  decrypt at next boot, which on a host that needs
  `tailscale_authkey_*` before login means it drops off the tailnet and
  may become unreachable — on vps or homelab that is a recovery
  situation. Any recipient change needs `sops updatekeys`, a
  `nixos-rebuild build` on every host, and a VM boot test of the
  sops-install-secrets activation before it goes near a real machine.
  Rotation of the laptop-readable secrets is separately disruptive
  (tailscale re-enrollment, wireguard re-key on both ends). Sequence
  it, and do the FDE work in parallel rather than instead.
- **Owner:** P1 for the profile-side identity creation; whoever owns
  `.sops.yaml` and `docs/procedures/secrets.md` for the recipient
  split; the FDE branch for the physical component.

### F-P1-03 — `initialPassword = "123456"` is published in a public repository

- **File:** `modules/profiles/PC.nix:306`
- **Severity:** HIGH
- **Confidence:** CONFIRMED that the value is in the config, in the
  world-readable Nix store, and in a public GitHub repository;
  CONFIRMED that it is *not* the live password on torrent; **PLAUSIBLE
  (unverified) for thinkpad**, which is the host that matters.
- **Axis:** hardening
- **Reachability:** A7 — a process as `lilijoy` on thinkpad that wants
  root: `security.run0.wheelNeedsPassword` is `true`, the process can
  register its own polkit authentication agent and supply the answer
  itself, and per threat model §4.7 it knows the answer from reading
  this file. No chain, no waiting for the user to elevate, no
  vulnerability required. Also A8 — a stolen or briefly-unattended
  thinkpad, against the KDE lock screen, typing a credential the
  attacker read off GitHub. Both conditional on the live password
  still being the declared one.
- **Rule:** new-rule candidate — `docs/hardening.md` says nothing about
  user credentials.
- **Finding:** three facts, in increasing order of how much they matter.
  1. It is *mostly* inert on the running machines. Verified against
     `update-users-groups.pl:215-232`: with `users.mutableUsers = true`
     (the merged value on both PC hosts), `initialPassword` is hashed
     into `/etc/shadow` **only** when the user has no existing
     `/etc/passwd` entry. Neither PC host uses impermanence, so
     `/etc/shadow` is ordinary persistent state and is never rebuilt.
     On torrent specifically, `passwd -S lilijoy` reports a last-change
     date of 2025-10-25 against a `/etc/machine-id` created 2024-12-07 —
     the password was changed roughly eleven months after the account
     was created, so it is not `123456` there. **thinkpad was not
     checkable** and remains an open question.
  2. It is not inert for provisioning. Any reinstall, any new PC-class
     host, any recovery that recreates the account, silently gets
     `123456` — on a machine whose user is in `wheel` with
     `wheelNeedsPassword = true`, i.e. one password away from root, and
     from there one SSH key away from fleet root via threat model §4.1.
  3. **It is a publicly documented credential, not an obscure one.**
     `gh repo view` reports `LilijoySkyseeker/nixOS` as `PUBLIC`, which
     threat model §4.7 now records. So this is not "a weak password in
     a private config": it is a specific password, attached to a named
     account (`lilijoy`) on named hosts (`thinkpad`, `torrent`),
     published on the internet next to the network layout — and also
     rendered into `users-groups.json` at mode `0444` inside every
     closure on both machines.
  **On the rating.** My first pass called this MEDIUM on the grounds
  that torrent's password is demonstrably changed and that thinkpad has
  no FDE anyway (§8.7), so against A8-with-possession the password is
  not the control that matters. The second of those two arguments does
  not survive §4.7's instruction not to discount, and more importantly
  it answers the wrong adversary. The one that matters is A7: a process
  running as `lilijoy` on thinkpad, which §5 rates the most likely
  initial foothold, needs no physical access, no FDE bypass and no
  further vulnerability — only a password it can read on GitHub and a
  polkit agent it can register as itself. If that password is
  unchanged, A7 is root, and from root on thinkpad the SSH key in
  `flake.vars.publicSshKeys` reaches `origin/master` and therefore the
  whole fleet (§4.1). That is HIGH by §6, so HIGH is the rating,
  with the conditionality carried honestly in the Confidence field
  rather than by deflating the label.
  **The single action that settles it:** run `passwd -S lilijoy` on
  thinkpad. If the last-change date is at or near its install date, the
  password is still `123456` and this needs fixing the same day. If it
  is not, this drops to INFO — a provisioning default plus a
  permanently-public string — and should be re-rated in Phase 2. I
  could not run it: thinkpad may be offline and sets
  `PermitRootLogin = "forced-commands-only"`.
- **Proposed fix:** delete the line. It has no ongoing function on an
  existing host, and for provisioning the right mechanism is
  `users.users.lilijoy.hashedPasswordFile` pointing at a sops secret,
  or `initialHashedPassword` with a real hash if a bootstrap credential
  is genuinely wanted. Whichever is chosen, run `passwd` on thinkpad
  first and confirm the live state, and treat `123456` as burned. Note
  that removing the line does not scrub git history; the value is
  public permanently.
- **Fix risk:** with `mutableUsers = true` and no existing account,
  removing `initialPassword` and providing nothing else leaves the new
  account with a locked password (`!` in shadow) and no console login —
  fine if provisioning always has physical/root access to run `passwd`,
  a lockout if not. Decide that before deleting, and write it into
  `docs/procedures/new-host.md`.

### F-P1-04 — every host-wide firewall opening in `PC.nix` is live on a globally-routable IPv6 address

- **File:** `modules/profiles/PC.nix:289` (avahi `openFirewall`),
  `modules/profiles/PC.nix:320` (Steam `remotePlay.openFirewall`),
  `modules/profiles/PC.nix:264-266` (`programs.kdeconnect.enable`)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for torrent (ports, rule shape and the
  routable address all read live); CONFIRMED for thinkpad's
  configuration, PLAUSIBLE for thinkpad's live addressing.
- **Axis:** hardening
- **Reachability:** A2 — anything on the internet, directly to
  torrent's `2600:1010:a022:496c::/64` address, with no NAT and no
  edge host in front. Also A4 — any other client on whatever Wi-Fi
  thinkpad is attached to, which is the roaming case, and any LAN
  device. Also A5 — the same ports are open on `tailscale0`, since a
  host-wide rule is exactly that.
  **On address discoverability, per §4.7.** The one input an attacker
  needs that this repo does not publish is the current address itself:
  a SLAAC privacy address inside a /64 is not enumerable by scanning.
  I am not treating that as a mitigation, for three reasons. It is
  obscurity, which §4.7 forbids relying on. It is a rotating value, not
  a secret — anything that has ever seen a connection from these hosts
  has it, as does the ISP, as does any device on the same LAN. And it
  is not needed at all for the A4 and A5 legs, which are the roaming
  laptop and the tailnet. The repo publishes which ports are open and
  what listens behind them; the address is the only piece an attacker
  has to acquire, and acquiring it is cheap.
- **Rule:** violates the interface-scoping pattern established for
  `nfs.nix`, `samba.nix`, `jellyfin.nix`, `minecraft.nix` and
  `factorio.nix` and recorded in threat model §2.2. That pattern is not
  yet written into `docs/hardening.md` — it should be; new-rule
  candidate.
- **Finding:** this is threat model §2.1 and §7.6 landing on the
  desktops. The CGNAT-illusion reasoning was applied to homelab on
  2026-08-26 and the same question was never asked of `profile-pc`.
  torrent holds a real, globally-routable, ISP-RA-delegated IPv6
  address on `enp8s0` right now, and
  `firewall-iptables.nix:150-208` emits every `allowedTCPPorts` /
  `allowedUDPPorts` entry via `ip46tables` with no `-i` match. The
  merged effective openings on **both** PC hosts are:

  | Proto | Ports | Source |
  |---|---|---|
  | TCP | 27036, 27037 | Steam remote play |
  | TCP | 1714-1764 (51 ports) | KDE Connect |
  | UDP | 5353 | avahi |
  | UDP | 10400, 10401, 27036 | Steam remote play |
  | UDP | 27031-27035 | Steam remote play |
  | UDP | 1714-1764 (51 ports) | KDE Connect |

  That is 106 ports reachable from the public IPv6 internet, in front
  of: `kdeconnectd` (confirmed listening on `*:1716`), the Steam client
  (confirmed listening on `0.0.0.0:27036`), and `avahi-daemon`. None of
  these is a service anyone chose to expose to the internet; all three
  are LAN-convenience features.
  Per-service reading:
  - **KDE Connect is the largest and the least visible.** It is 102 of
    the 106 ports, it comes from a bare `programs.kdeconnect.enable`
    that reads like a package install, and the upstream module has **no
    `openFirewall` option** — the range is opened unconditionally, so
    there is nothing to flip off. Pairing needs confirmation, but the
    daemon parses untrusted packets before that point.
  - **Steam remote play** opens 7 ports/ranges. Whether inbound remote
    play is actually used could not be determined; if it is not, the
    whole `remotePlay.openFirewall` line is dead attack surface (§7.4).
  - **avahi** is the one with a demonstrated need: a driverless printer
    is configured on torrent (`implicitclass://Brother_MFC_L2740DW_series`)
    and mDNS resolution requires inbound 5353 because multicast
    responses do not match conntrack. It is also the least dangerous —
    mDNS is link-local by construction, and `publish.enable` evaluates
    to `false`, so avahi is a resolver, not an advertiser. But the
    firewall rule itself is not link-scoped: it accepts unicast 5353
    from any source on any address.
- **Proposed fix:** move all three to the repo's established pattern.
  KDE Connect and Steam have no upstream toggle for the ports, so they
  need `networking.firewall.allowedTCPPorts = lib.mkForce (…)` style
  subtraction or, more cleanly, a `lib.mkForce []` on the host-wide
  lists plus explicit
  `networking.firewall.interfaces.<lan-iface>.allowed{TCP,UDP}Port{s,Ranges}`.
  Scoping by interface name is awkward on a laptop that roams between
  `enp8s0` and `wlp9s0`; the honest options are (a) name both
  interfaces, accepting that the holes follow the laptop onto hostile
  Wi-Fi, or (b) scope them to `tailscale0` only and use KDE Connect /
  remote play over the tailnet, which is strictly better and is what the
  rest of the fleet already does. Independently and cheaply: decide
  whether `remotePlay.openFirewall` is used at all, and delete it if not.
- **Fix risk:** LAN printer discovery, phone pairing and Steam remote
  play all break silently and are not build-visible or VM-testable.
  Stage one service at a time. Note that scoping to `tailscale0` changes
  the *user experience* of KDE Connect (the phone must be on the
  tailnet), which is a product decision, not just a config one.

### F-P1-05 — `libvirtd` on `lilijoy` is the live root-equivalent grant, and it is passwordless

- **File:** `modules/profiles/PC.nix:18` (imports
  `nixosModules."virtual-machines"`), `modules/nixos/virtual-machines.nix:11`,
  and the upstream polkit rule it activates
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the grant, the polkit rule and live
  membership; PLAUSIBLE for the escalation, which is well documented
  upstream but which I did not execute on a live machine.
- **Axis:** hardening
- **Reachability:** A7 — same foothold as F-P1-01, but this path needs
  no captured password at all.
- **Rule:** new-rule candidate (interactive-user group grants).
- **Finding:** the threat model's §4.3 path 1 named `docker` as the
  root-equivalent group on the desktops. That turns out to be dead
  (F-P1-13). The grant that *is* live is `libvirtd`, which
  `PC.nix:18` pulls in transitively — it does not appear in
  `PC.nix`'s own `extraGroups` list at all, which is exactly why it was
  missed. The merged
  `users.users.lilijoy.extraGroups` is
  `["networkmanager" "wheel" "dialout" "input" "docker" "libvirtd" "input"]`,
  and `libvirtd` is present in `/etc/group` on the live host.
  `virtualisation.libvirtd.enable` installs a polkit rule returning
  `YES` (no password, no prompt) for `org.libvirt.unix.manage` to
  anyone in `libvirtd` — confirmed in the merged
  `security.polkit.extraConfig`. The monolithic `libvirtd` runs as root
  and performs storage operations on the client's behalf, so a
  `libvirtd` member can define a storage pool rooted at `/`, create or
  overwrite arbitrary root-owned files, and attach host block devices
  to a guest. This is a well-known root-equivalence, and unlike the
  `wheel`/run0 path it requires no password and produces no prompt.
  `libvirtd` is genuinely in use (the daemon is active on torrent), so
  this is not dead config — it is an accepted cost that has never been
  written down as one.
  Lesser, same shape, also confirmed in the merged polkit config:
  `networkmanager` (granted at `PC.nix:309`) gets `YES` on every
  `org.freedesktop.NetworkManager.*` action, and `wheel` gets `YES` on
  `org.opensuse.cupspkhelper.mechanism.all-edit`. Both are upstream
  defaults, both are lower-yield than libvirt, both are worth knowing
  about when reasoning about §4.3.
- **Proposed fix:** decision required. Options: (a) accept and document
  — record in `docs/hardening.md` that `libvirtd` membership is
  root-equivalent and is deliberately granted to the desktop user, so
  the next reader does not treat `wheel` + run0 as the only elevation
  path; (b) switch to session libvirt (`qemu:///session`) for the
  virt-manager workflow and drop the group, which loses bridged
  networking and USB passthrough; (c) keep the group but remove the
  passwordless polkit rule so libvirt admin at least prompts. (a) is
  probably right for a single-admin desktop; the point of the finding
  is that it is currently neither decided nor recorded, and the threat
  model actively points at the wrong group.
- **Fix risk:** (b) breaks `spiceUSBRedirection` and any bridged guest;
  (c) makes virt-manager prompt constantly and will be reverted in
  annoyance within a week. Prefer (a).

### F-P1-06 — `useRoutingFeatures = "both"` fleet-wide, against the repo's own rule (confirms F-P0-06)

- **File:** `modules/profiles/default.nix:79`;
  `hosts/vps/configuration.nix:463` is the sole override
- **Severity:** MEDIUM — raising P0's LOW; see the note below
- **Confidence:** CONFIRMED for the configuration, the sysctl priority
  mechanism, and the resulting live kernel state on torrent. PLAUSIBLE
  for reachable impact.
- **Axis:** hardening / needed-used
- **Reachability:** A4, A5 — a device on the same LAN or hostile Wi-Fi
  as a laptop, or a rogue tailnet node, using the laptop as a transit
  router into a network segment it should not reach.
- **Rule:** **violates an existing `docs/hardening.md` rule** —
  "Tailscale forwarding sysctls", which says to narrow to `"client"`
  with `lib.mkForce` on hosts that are not an exit node or subnet
  router.
- **Finding:** confirmed as P0 described it, with three additions.
  - The merged values are `"both"` on thinkpad, torrent **and**
    homelab; only vps is `"client"`. homelab legitimately needs
    `"both"` (its `extraUpFlags` are
    `--advertise-routes=192.168.1.0/24 --advertise-exit-node`). Both
    laptops' `extraUpFlags` are just `--advertise-tags=tag:<host>` —
    neither routes anything, so the grant has no consumer at all.
  - Live confirmation on torrent: `/proc/sys/net/ipv4/conf/all/forwarding`
    and the v6 equivalent are both `1`.
  - **The sysctl-priority interaction the rule warns about is real and
    now verified.** `tailscale.nix:252-255` uses `mkOverride 97`. A
    plain `boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = false`
    is priority 100 and would *lose silently*; `lib.mkDefault` (1000)
    loses harder. Anyone "fixing" this with a sysctl assignment instead
    of changing `useRoutingFeatures` will produce a config that reads
    correct, builds clean, and does nothing. Only `lib.mkForce` (50) or
    changing the option itself works.
  - Compounding it: `networking.firewall.filterForward` is `false`
    (the nixpkgs default) on both laptops, so the `FORWARD` chain is
    unfiltered. With forwarding on and `checkReversePath = "loose"`
    (also set by tailscale for `client`/`both`), a laptop with any
    second interface up — `virbr0`, `waydroid0`, a podman bridge — is a
    router between the LAN and those segments for anyone who adds a
    static route. I rate the impact PLAUSIBLE rather than CONFIRMED
    because libvirt and the container runtimes install their own
    `FORWARD` rules, and because none of those bridges was up when I
    looked.
- **Proposed fix:** as P0 proposed — invert the default. Set
  `useRoutingFeatures = "client"` in `modules/profiles/default.nix:79`
  and `lib.mkForce "both"` in `hosts/homelab/configuration.nix`, which
  also lets `hosts/vps/configuration.nix:463`'s override be deleted.
  `"client"` and not `"none"`: `"client"` is what sets
  `checkReversePath = "loose"`, and strict reverse-path filtering
  breaks tailscale. Fail-safe rather than fail-open, and it puts the
  one host that actually routes in the position of having to say so.
- **Fix risk:** getting it backwards silently kills homelab's exit node
  and its `192.168.1.0/24` subnet route. That is connectivity-visible
  but **not** build-visible — `nixos-rebuild build` will pass either
  way. Verify with `tailscale status` and an actual route test from
  another tailnet device after switching homelab, and do homelab before
  the laptops.
- **Why MEDIUM and not P0's LOW:** §6 states that violations of an
  existing `docs/hardening.md` rule with no currently demonstrable
  exploit are MEDIUM, "because the class is real". This is that case
  exactly: a written rule, applied to precisely one host, with the
  shared default still pointing the wrong way for the other three. I am
  flagging the disagreement rather than quietly re-rating; Phase 2
  should pick one.

### F-P1-07 — the Bitwarden SSH-agent socket path is a literal `<user>` placeholder, so `SSH_AUTH_SOCK` is inert

- **File:** `modules/profiles/PC.nix:166`
- **Severity:** LOW
- **Confidence:** CONFIRMED — evaluated and observed in the live
  environment on torrent.
- **Axis:** hardening / documentation
- **Reachability:** n/a directly. It matters because of what it means
  about the key that A7/A8 would actually find.
- **Rule:** n/a — but it is a clean instance of failure mode §7.2,
  config that renders but never takes effect.
- **Finding:** the line reads
  `SSH_AUTH_SOCK = "/home/<user>/.bitwarden-ssh-agent.sock"`. The
  `<user>` is a literal, never substituted. The merged home-manager
  `sessionVariables` carries it verbatim, and `env` in a live session
  confirms `SSH_AUTH_SOCK=/home/<user>/.bitwarden-ssh-agent.sock` —
  while the real socket exists at
  `/home/lilijoy/.bitwarden-ssh-agent.sock`. So the Bitwarden SSH agent
  has never been in the path: every `ssh` invocation falls straight
  through to on-disk key files in `~/.ssh`. That is the key
  `myPullDeploy` reads (`sshKeyPath = /home/lilijoy/.ssh/id_ed25519`,
  see F-P0-03) and, via `flake.vars.publicSshKeys` and threat model
  §4.1, the key that is fleet root. The intended posture — private keys
  held by an unlockable agent rather than sitting on disk — is not the
  posture in force, and nothing anywhere says so.
  `/home` is `root:root 0755`, so no unprivileged user can create the
  `<user>` directory and hijack the path; that part is safe.
- **Proposed fix:** one-character class of fix —
  `"${config.home.homeDirectory}/.bitwarden-ssh-agent.sock"`, or just
  `/home/lilijoy/...` to match the hard-coded paths already used at
  `PC.nix:222` and `PC.nix:233-234`. Then, separately, confirm whether
  the on-disk `~/.ssh/id_ed25519` is passphrase-protected and whether
  it should be migrated into the agent — that part belongs to P5/P7,
  who own the laptop key model.
- **Fix risk:** actually enabling the agent will change which key `ssh`
  offers, which can break `myPullDeploy`'s unattended fetch if the
  agent is locked or not running at the time the timer fires — a root
  service cannot unlock a user's Bitwarden. Fixing the path without
  thinking through the unattended path could convert a cosmetic bug
  into a broken deploy. Fix the typo and the deploy-key story together.

### F-P1-08 — the tailscale auth key transits a world-readable `/proc` command line at enrollment

- **File:** `modules/profiles/default.nix:80,98`; mechanism in the
  pinned `nixos/modules/services/networking/tailscale.nix:183-234`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the mechanism and for the absence of
  `hidepid`; the exploit window is narrow by construction.
- **Reachability:** A7 — any process running as any local user on a PC
  host at the moment of first enrollment or re-enrollment.
- **Rule:** n/a
- **Finding:** `sops.secrets."tailscale_authkey_<host>"` is correctly
  scoped (`mode 0400`, `uid 0`, `/run/secrets/...`) and tailscaled runs
  as root, so the file itself is fine. But the upstream
  `tailscaled-autoconnect` unit does
  `tailscale up --auth-key "$(cat ${cfg.authKeyFile})…"`, putting the
  key into the `tailscale` process's `argv`. `/proc` is mounted without
  `hidepid` (confirmed in `/proc/mounts`), so every local user can read
  `/proc/<pid>/cmdline` for the duration of that call. The window is
  genuinely small: the script only reaches that branch when the backend
  state is `NeedsLogin`/`NeedsMachineAuth`/`Stopped`, so on an
  already-enrolled host the key never touches a command line — a
  `nixos-rebuild switch` re-runs the unit but it exits immediately at
  `Running`. The realistic case is a fresh install or a post-`logout`
  re-enroll on a machine that already has a persistent A7 implant. The
  payoff is worth naming, though: an auth key is A5, the
  single-highest-leverage compromise in threat model §4.4.
- **Proposed fix:** this is upstream's shape, not the repo's, so the
  clean options are narrow. Cheapest real mitigation:
  `security.hideProcessInformation`-style `hidepid=2` on `/proc` for
  the PC hosts, which also blunts a range of other local
  reconnaissance. Alternatively, treat re-enrollment as a manual
  operation and drop `authKeyFile` on the PC hosts, which loses
  declarative bootstrap. Or simply record it as accepted, with the
  observation that the exposed window is first-boot only.
- **Fix risk:** `hidepid=2` breaks tools that expect to see other
  users' processes (some monitoring, `pkill` across users, a few
  desktop bits) and has bitten systemd-logind integration in the past;
  it wants a VM test before it goes near the daily driver.

### F-P1-09 — the two hosts most likely to be compromised have no audit trail

- **File:** `modules/profiles/server.nix:26-28` (where auditd lives),
  by absence from `modules/profiles/default.nix`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** n/a — this is an observability gap, not a
  privilege. It bears on A7: if the most likely foothold lands on a
  desktop, there is no execve record to reconstruct from.
- **Rule:** consistent with `docs/hardening.md` as written (auditd is
  explicitly scoped to the *server* baseline), so this is a proposal to
  revisit the rule, not a violation of it.
- **Finding:** `security.auditd.enable` and `security.audit.enable` are
  `true` on homelab and vps, `false` on thinkpad and torrent (merged
  values). Threat model §5 rates A7 — something running as `lilijoy` on
  a desktop — as **the most likely initial foothold on this fleet**, and
  that is precisely where nothing is recorded. The desktops are also
  where `claude-code` runs, where flatpaks from four remotes run, and
  where a browser runs.
  Two smaller points about the rule as it exists on the servers, both
  worth folding into any revisit: the single rule
  `-a exit,always -F arch=b64 -S execve` covers only 64-bit `execve`,
  so a 32-bit binary executes unaudited; and there is no `-e 2`
  (immutable rules), so root can flush the ruleset at will without the
  configuration noticing. Both are minor on a server that runs no
  32-bit code, and both are cheap to close.
- **Proposed fix:** decide whether the execve audit belongs in
  `profile-default` rather than `profile-server`. It is not free — an
  execve rule on an interactive KDE desktop is high-volume, and
  `/var/log/audit` will need real sizing and rotation on a machine
  nobody is watching. If it goes in, add `-F arch=b32` alongside `b64`,
  and consider `-e 2`. If it stays out, say so in `docs/hardening.md`
  with the reason, so the asymmetry is a decision rather than an
  artefact of which profile the line happened to land in.
- **Fix risk:** log volume and disk pressure on the desktops; both PC
  hosts already run `myZfsSpaceGuard`, so a runaway audit log has a
  blast radius. Size it before enabling.

### F-P1-10 — fleet DNS is plaintext and unvalidated, including on the roaming laptop

- **File:** `modules/profiles/default.nix:203-207`
- **Severity:** LOW
- **Confidence:** CONFIRMED (defaults read from the pinned
  `nixos/modules/system/boot/resolved.nix:104-120`; merged values
  checked on vps)
- **Axis:** hardening
- **Reachability:** A4 — an on-path attacker on hostile Wi-Fi or the
  home LAN, against thinkpad in particular. A2 for anything upstream of
  the resolver.
- **Rule:** new-rule candidate
- **Finding:** `networking.nameservers = [ "8.8.8.8" "1.1.1.1" ]` for
  every host, with `services.resolved.enable = true` and neither
  `DNSOverTLS` nor `DNSSEC` set — both default to `false` in the pinned
  tree, confirmed by reading the module and by evaluating vps. So all
  DNS leaves every host in cleartext to Google and Cloudflare, with no
  validation, and is spoofable by anyone on the path. What actually
  depends on DNS integrity here is thinner than it first looks — Nix
  substitution is signature-checked, flatpak content is hashed, and
  tailscale pins its own coordination endpoints — but two things do
  care: the deploy path's `git fetch` to GitHub, which combines badly
  with `StrictHostKeyChecking=accept-new` (F-P0-07) on a fresh host,
  and ACME/DNS on vps.
- **Proposed fix:** set
  `services.resolved.settings.Resolve.DNSOverTLS = true` and
  `DNSSEC = "allow-downgrade"` (or `true`) in
  `modules/profiles/default.nix`. Both 8.8.8.8 and 1.1.1.1 support DoT.
  Note the option was renamed — the pinned tree warns that
  `services.resolved.dnssec` is obsolete in favour of
  `services.resolved.settings.Resolve.DNSSEC`, so use the new path.
- **Fix risk:** strict `DNSSEC = true` breaks resolution behind captive
  portals and against misconfigured zones, which on a roaming laptop
  means "the coffee shop Wi-Fi no longer works". `allow-downgrade` is
  the safe setting. `DNSOverTLS = true` (strict) fails closed on
  networks that block 853; `opportunistic` is the safe setting. Neither
  is build-visible — test on torrent before thinkpad.

### F-P1-11 — `virtualisation.waydroid.enable` silently exempts `waydroid0` from the firewall

- **File:** `modules/profiles/PC.nix:102`; mechanism in the pinned
  `nixos/modules/virtualisation/waydroid.nix:57`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A7-adjacent — an untrusted Android application
  inside the waydroid container, which is the entire point of running
  waydroid.
- **Rule:** same class as threat model §2.2 — a whole-interface trust
  grant rather than named ports; new-rule candidate.
- **Finding:** the merged `networking.firewall.trustedInterfaces` on
  both PC hosts is `["waydroid0" "lo"]`. `waydroid0` is not something
  this repo asked for — the upstream module adds it as a side effect of
  `enable`, and `firewall-iptables.nix:150` turns that into
  `ip46tables -A nixos-fw -i waydroid0 -j nixos-fw-accept`, i.e. the
  host packet filter is bypassed wholesale for that bridge. Android
  applications running in the container therefore reach every service
  bound to a wildcard address on the host, including `sshd` on 22 and
  `rpcbind` on 111 (both confirmed listening on `0.0.0.0`), regardless
  of the carefully interface-scoped rules at
  `hosts/torrent/configuration.nix:110`. What is reachable is
  reasonably hardened — sshd has `PasswordAuthentication = false` and
  `PermitRootLogin = "forced-commands-only"` — so this is defence in
  depth, not an open door. waydroid is genuinely in use (the container
  is active, `/var/lib/waydroid` is populated), so this is not dead
  config.
  It is listed mainly because it is invisible: nothing in `PC.nix`
  hints that a one-line `enable` disables the firewall for an
  interface, and this is the same "shared module drags in more than its
  name suggests" trap `docs/architecture.md` already records for
  `tooling.nix`.
- **Proposed fix:** override it —
  `networking.firewall.trustedInterfaces = lib.mkForce [ "lo" ]` in
  `PC.nix`, plus explicit
  `networking.firewall.interfaces.waydroid0.allowed*Ports` for whatever
  waydroid actually needs (DNS and DHCP to the host, in practice). At
  minimum, add a comment at `PC.nix:102` naming the side effect.
- **Fix risk:** Android networking inside waydroid breaks in ways that
  present as "apps have no internet" and are annoying to diagnose.
  Worth doing on torrent first with a real app open.

### F-P1-12 — `profile-server` does not pin `users.mutableUsers`, and the two servers disagree

- **File:** `modules/profiles/server.nix` (by absence);
  `hosts/homelab/configuration.nix` sets it, `hosts/vps/configuration.nix`
  does not
- **Severity:** LOW
- **Confidence:** CONFIRMED for the configuration divergence;
  PLAUSIBLE for the consequence — I could not read vps's `/etc/shadow`
  (the SSH check was blocked).
- **Axis:** hardening
- **Reachability:** A2/A8 via DigitalOcean's out-of-band droplet
  console, which is serial and is not gated by sshd's
  `PasswordAuthentication = false`.
- **Rule:** new-rule candidate — `docs/hardening.md`'s "shared server
  baseline" list should include it.
- **Finding:** merged `users.mutableUsers` is `false` on homelab and
  `true` on vps. `profile-server` — the file whose entire job is the
  headless-role security baseline, and which already carries
  `nix.settings.allowed-users`, `security.sudo.enable = false` and the
  auditd stanza — does not set it, so it is left to each host and one
  of them forgot. On vps that means account and password state can be
  changed imperatively and will never be reconciled by a deploy, and
  `users.users.root.hashedPassword` being `null` means any root password
  present in `/etc/shadow` got there out of band. vps is the internet
  edge and the one host with a provider-supplied serial console.
- **Proposed fix:** add `users.mutableUsers = false;` to
  `modules/profiles/server.nix` and drop homelab's now-redundant copy.
  Before doing so, check `passwd -S root` on vps and on homelab, since
  flipping to `false` rewrites `/etc/shadow` password fields for every
  declared user.
- **Fix risk:** real and worth respecting. `mutableUsers = false`
  replaces the shadow password of every declared user with `!` unless
  a `hashedPassword`/`hashedPasswordFile` is provided — on a host whose
  only other access path is SSH, doing this while the SSH key model is
  in any doubt is a lockout. Do vps last, keep the DigitalOcean console
  open, and verify key-based root SSH works immediately before.

### F-P1-13 — the `docker` group grant on `lilijoy` is dead config

- **File:** `modules/profiles/PC.nix:313`
- **Severity:** INFO
- **Confidence:** CONFIRMED, both by evaluation and on the live host.
- **Axis:** needed-used
- **Reachability:** none. This entry **refutes** threat model §4.3
  path 1 and the §7.4 working hypothesis.
- **Rule:** n/a
- **Finding:** the seed hypothesis was that `docker` on `lilijoy` is a
  live root-equivalent grant made redundant by podman. It is redundant,
  but it is also entirely inert. `virtualisation.docker.enable` is
  `false` and `virtualisation.podman.dockerSocket.enable` is `false`,
  so **nothing declares `users.groups.docker`**. Per
  `nixos/modules/config/users-groups.nix:537-543`, membership is
  derived from `users.groups.<g>.members`, so an `extraGroups` entry
  naming an undeclared group creates no group and no membership — and
  emits no warning. Confirmed in the built artefact: the generated
  `users-groups.json` contains no `docker` group. Confirmed live on
  torrent: `getent group docker` returns nothing, `id lilijoy` shows no
  `docker`, and there is no `docker.sock` anywhere. `podman.sock` does
  exist at `/run/podman/podman.sock`, correctly `root:podman 0660`,
  and `lilijoy` is **not** in `podman` — so the rootful podman socket is
  properly closed too.
  The finding is therefore not a privilege but a trap: a line that
  reads as a root-equivalent grant, that a reader (including the threat
  model) will reasonably believe, and that does nothing. If
  `virtualisation.docker.enable` is ever turned on for any reason, it
  becomes live and root-equivalent on the same commit, with no other
  change and no review prompt.
- **Proposed fix:** delete `"docker"` from
  `modules/profiles/PC.nix:313`, and correct threat model §4.3 path 1
  and §7.4 to name `libvirtd` (F-P1-05) as the real instance.
- **Fix risk:** none. The line has no effect today; verify by
  diffing `users-groups.json` before and after, which should be
  identical.

### F-P1-14 — `boot.binfmt.emulatedSystems = ["aarch64-linux"]` has no consumer anywhere in the repo

- **File:** `modules/profiles/default.nix:115-117`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** none demonstrated.
- **Rule:** n/a — §7.4
- **Finding:** `grep -rn aarch64 --include=*.nix .` returns exactly one
  hit: this line. `modules/flake/systems.nix` is
  `systems = [ "x86_64-linux" ]`, no host targets aarch64, and nothing
  cross-compiles. So every host — including vps, the internet edge —
  registers a `binfmt_misc` handler and carries a qemu-user emulator in
  its closure for an architecture nothing builds. Confirmed live on
  torrent: `/proc/sys/fs/binfmt_misc/aarch64-linux` is registered.
  The security cost is small and I will not overstate it: the
  registration uses flags `P` (preserve argv0), **not** `F`, so the
  interpreter is resolved in the caller's mount namespace at exec time
  rather than being pinned open into every namespace — which is the
  variant that would matter for containers. What remains is a large,
  complex emulator auto-invoked by the kernel on any file bearing the
  aarch64 ELF magic, on hosts that will never legitimately see one. The
  audit rule on the servers still catches the `execve` of the
  interpreter, so it is not an evasion of that.
- **Proposed fix:** delete it, or move it to whichever host actually
  needs it if cross-building is a workflow someone uses occasionally.
- **Fix risk:** none unless someone is quietly relying on running
  aarch64 binaries; a `grep` of shell history would settle it. Closure
  size goes down on all four hosts.

### F-P1-15 — dead, duplicated and stale config across the three profiles

- **File:** several, listed below
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used / documentation
- **Reachability:** none individually.
- **Rule:** n/a — §7.4
- **Finding:** collected rather than filed separately, since none has
  reach on its own. Each was checked against the merged config, not
  just read.
  - `modules/profiles/default.nix:60-65` — `security.sudo` sets
    `execWheelOnly = true` and a `package` override
    (`sudo.override { withInsults = true; }`) underneath
    `enable = false`. Both are inert; the `withInsults` build is never
    realised. The `enable = false` itself is load-bearing (the run0
    module asserts on it), the other two lines are decoration that
    reads like policy.
  - `modules/profiles/server.nix:21` duplicates that
    `security.sudo.enable = false`, which `profile-default` already
    sets for every host. Related: `docs/hardening.md` describes it as
    part of the *server* baseline and says "server.nix's
    `security.sudo.enable = false` confirms the real package is
    intentionally absent" — as written that implies servers are where
    sudo is disabled, when in fact it is disabled fleet-wide from
    `default.nix`. Worth one sentence of correction.
  - Also on `sudo`: the two nixpkgs pins ship **different shims**. vps,
    torrent and thinkpad get the compiled `run0-sudo-shim` (which does
    accept flags); homelab gets stable's `writeShellScriptBin` alias,
    which prints an error and exits 1 on any argument beginning with
    `-`. `docs/hardening.md`'s note about run0-aliased sudo "silently
    no-op[ping] with exit 200" describes neither of these exactly, and
    describes homelab's not at all. The `runuser` advice it gives is
    still correct; the parenthetical about exit codes is not portable
    across the fleet.
  - `modules/profiles/server.nix:14-15` — `environment.systemPackages =
    with pkgs; [ ]`, an empty list.
  - `modules/profiles/PC.nix:89-90` — `++ (with pkgs-stable; [ ])`,
    likewise empty.
  - `modules/profiles/PC.nix:293-294` —
    `services.pulseaudio.support32Bit = true` under
    `services.pulseaudio.enable = false`. Inert; the 32-bit audio path
    that Steam actually uses comes from
    `services.pipewire.alsa.support32Bit`, which the Steam module sets
    itself.
  - `modules/profiles/PC.nix:312` and `modules/nixos/wooting.nix:9`
    both add `input`, which is why the merged `extraGroups` list
    contains it twice. Harmless, but it is why a reader of `PC.nix`
    alone would not know removing the line there is insufficient — see
    F-P1-01.
  - `modules/profiles/PC.nix:32` — `gjs # for kdeconnect`. `gjs` is a
    GNOME JavaScript runtime needed by *gsconnect*, the GNOME
    implementation; this fleet runs KDE's `kdeconnect-kde`, which does
    not use it. The comment is wrong and the package is very likely
    unnecessary.
  - `modules/profiles/PC.nix:39` and `:50` — `distrobox` listed twice
    in the same list.
  - `modules/profiles/PC.nix:71` and `:86` — `texliveFull` and
    `texliveSmall` both installed; the former subsumes the latter.
  - `modules/profiles/PC.nix:77` — the comment `# temp copy from
    stable` sits above a block that is entirely `pkgs-unstable`. The
    `pkgs-stable` list it presumably once described is the empty one at
    `:89-90`.
  - `services.fwupd.enable` (`default.nix:101`) is `true` on **vps**, a
    DigitalOcean droplet with no updatable firmware. It is a root
    daemon that periodically fetches metadata over the network.
    `services.smartd` is correctly turned off there by the host, so the
    pattern of "host overrides desktop-oriented defaults from
    `profile-default`" already exists — fwupd just was not included.
  - `nix.nixPath = [ "nixpkgs=${inputs.nixpkgs-unstable}" ]`
    (`default.nix:126`) points homelab's `<nixpkgs>` at **unstable**,
    although homelab is the one host pinned to stable. Not a security
    issue; a reproducibility surprise for anyone using `nix-shell -p`
    there.
- **Proposed fix:** delete or correct each. All are independent
  one-liners; none needs a decision.
- **Fix risk:** negligible individually. `gjs` and `texliveSmall`
  removal should be sanity-checked by actually opening KDE Connect and
  building a document once, since "nothing referenced it in Nix" is not
  the same as "nothing referenced it at runtime".

### F-P1-16 — the declarative flatpak list describes almost none of what is installed

- **File:** `modules/profiles/PC.nix:125-132`
- **Severity:** INFO
- **Confidence:** CONFIRMED on torrent.
- **Axis:** needed-used
- **Reachability:** A6-adjacent — a third-party flatpak remote is a
  software supply chain that nothing in this repo reviews or pins.
- **Rule:** n/a; relevant to the repo's declarative-first posture.
- **Finding:** `services.flatpak.packages` declares two applications
  (`app.grayjay.Grayjay`, `info.beyondallreason.bar`) and
  `uninstallUnmanaged = false`, so nothing reconciles. Live state on
  torrent: ten-plus applications installed from four remotes, and the
  remotes include `vish-repo` added **system-wide** and
  `flathub-beta` per-user, neither of which appears anywhere in the
  repo. Installed-but-undeclared apps include a Wine manager
  (`Bottles`), a budgeting app with financial data, and two
  launchers pulled from vendor-run remotes. This is not a
  vulnerability; it is a statement that the config does not describe
  the machine, which matters because the whole audit is being conducted
  by reading the config.
- **Proposed fix:** decision required. Either bring the real list into
  `services.flatpak.packages` (and `remotes`) and set
  `uninstallUnmanaged = true`, accepting that flatpak becomes a thing
  you edit Nix to change; or drop the declarative list to zero and
  state in a comment that flatpak is deliberately managed
  imperatively, so no future reader mistakes the two-entry list for the
  inventory. The middle ground currently in place is the worst of both.
- **Fix risk:** `uninstallUnmanaged = true` will remove every
  undeclared application on the next activation, including user data
  paths in some cases. Enumerate and declare everything first, then
  flip it, and not on the daily driver first.

---

## 3. Checked and clean

Examined, and either correct or not worth a finding. Listed so a later
reader knows the coverage rather than only the failures.

**`modules/profiles/default.nix`**

- `networking.firewall.enable = true` (`:180`) — on for every host,
  merged value confirmed. `profile-default` itself opens **no** ports;
  every hole in the fleet comes from a host file or a service module.
- `nix.settings.experimental-features` (`:183-186`) — flakes and
  nix-command only.
- Substituters: merged `nix.settings.substituters` is
  `["https://cache.nixos.org/"]` and `trusted-public-keys` is the
  matching single key, on all hosts. No third-party binary cache is
  configured anywhere, despite `comma`/nix-index being enabled — this
  is the single most common way a personal Nix config acquires an
  unaudited A6 path, and this repo does not have it.
- `trusted-users` is `["root"]` on the PC hosts and homelab; vps adds
  `vps-deploy`, which is necessary for `nix-store --serve --write` and
  is P2's to weigh. `nix.settings.sandbox` is `true`.
- The run0 / no-sudo setup (`:50-66`) — the
  `options.security ? run0` / `options.security.run0 ? enable`
  double-guard is correct against **both** pins, verified by evaluating
  `security.run0.enable` on torrent (exists, `true`) and homelab (the
  option does not exist). `security.sudo.enable = false` satisfies the
  upstream assertion in both modules; `wheelNeedsPassword` is `true`
  (no passwordless-wheel rule); `persistentAuth` is off;
  `security.polkit.enable` is `true` on all four real hosts, so the
  elevation path actually functions. No real `sudo` binary is present —
  `/run/current-system/sw/bin/sudo` resolves to `run0-sudo-shim`.
- sops plumbing (`:98`, `:155-158`) — `tailscale_authkey_<hostname>` is
  per-host by interpolation, `mode 0400`, `uid 0`, under
  `/run/secrets`. `defaultSopsFile` resolves correctly after the
  `modules/profiles/` move. No secret in these profiles is granted to a
  non-root owner except the two git-identity templates, which are
  name/email.
- `boot.loader.systemd-boot.editor = false` (`:196`) — correct; the
  boot-menu editor is a trivial `init=/bin/sh` root path when left on.
- `boot.zfs.forceImportRoot = false` (`:69`).
- `environment.defaultPackages = lib.mkForce []` (`:177`).
- `programs.command-not-found.enable = false`, `programs.direnv`,
  `programs.nh.clean`, `services.fstrim`, `i18n.*`,
  `hardware.enableAllFirmware`, `nixpkgs.config.allowUnfree`,
  `system.stateVersion` — reviewed, nothing security-bearing.
- `services.smartd` notification targets (`:104-112`) include `x11`
  on headless hosts; harmless.
- The `--ssh` exclusion comment (`:81-93`) is accurate and is the
  reason F-P0-05 is latent rather than live. `extraUpFlags` carry
  `--advertise-tags=tag:<hostname>` per host, matching the documented
  tag model.

**`modules/profiles/server.nix`**

- `nix.settings.allowed-users = [ "root" ]` (`:19`) — merged value
  confirmed `["root"]` on both servers, matching the
  `docs/hardening.md` baseline exactly. PC hosts are `["@wheel"]`,
  which is the appropriate relaxation for an interactive machine.
- auditd (`:26-28`) — `security.auditd.enable` and
  `security.audit.enable` both `true` on homelab and vps, with the
  execve rule present in the merged value. The `docs/hardening.md`
  requirement that `/var/log` be in the impermanence persistence list
  **holds on both**: `hosts/homelab/configuration.nix:476` and
  `hosts/vps/configuration.nix:252`. (Rule-scope observations are in
  F-P1-09.)
- The git-identity template (`:40-50`) — `mode 0400`, owner `root`,
  rendered to `/root/.config/git/identity`, using
  `sops.templates` rather than putting the values in the store. Same
  pattern as the PC one. Correct.
- The root home-manager profile (`:53-62`) — verified that the
  2026-08-26 `tooling` / `tooling-desktop` split actually took:
  `programs.firefox.enable`, `programs.obs-studio.enable`,
  `programs.obsidian.enable` and `services.kdeconnect.enable` all
  evaluate `false` in vps's root profile. The regression
  `docs/architecture.md` documents is genuinely fixed, not just
  described as fixed.
- `sops.age.sshKeyPaths` (`:65`) — matches the module default given
  `services.openssh.enable`; explicit is fine.
- `programs.nh.flake = "/etc/nixos"` (`:32`) — a root-owned checkout,
  which is the arrangement F-P0-03 wants the laptops to move toward.
- `services.logind.settings.Login.HandleLidSwitch` (`:68`) — the
  `settings` form exists on both pins (it evaluates on homelab's
  stable). Not security-bearing.
- Correctly absent: no host-specific hardware tweaks, per the rule in
  `docs/hardening.md`.

**`modules/profiles/PC.nix`**

- `nix.settings.allowed-users = [ "@wheel" ]` (`:190`) — merged
  `["@wheel"]`, `trusted-users` still `["root"]`. An unprivileged
  non-wheel account could not talk to the nix daemon at all.
- The sops comment block (`:192-216`) — the reasoning about
  `sops.age.sshKeyPaths` being useless for boot-time decryption is
  correct. Note for accuracy: the merged
  `sops.age.sshKeyPaths` on torrent is *not* empty — it is
  `["/etc/ssh/ssh_host_ed25519_key"]`, contributed as a module default
  because `services.openssh.enable` is true. That does not contradict
  the comment (which is about not adding *lilijoy's user* key) but a
  reader checking the merged value will be briefly confused.
- `sops.age.generateKey = true` with `keyFile = /var/lib/sops-nix/key.txt`
  — reproducible from a fresh install, as the comment claims.
- The git-identity template (`:221-229`) — owner `lilijoy`, mode
  `0400`, values kept out of the store.
- `services.printing` (`:279-284`) — `listenAddresses` is
  `["localhost:631"]`, `browsing = false`, `openFirewall = false`.
  CUPS is properly closed; only avahi's 5353 is open (F-P1-04).
- `services.avahi.publish.*` — all `false`, so avahi advertises
  nothing; `reflector = false`; no interface allow/deny list.
- `security.rtkit.enable`, `services.pipewire`, `hardware.bluetooth`,
  `services.pcscd` (used — YubiKey tooling is installed and in use),
  `hardware.keyboard.qmk.enable`, `programs.gamemode`,
  `programs.nix-ld` (empty library list, but the module has its own
  defaults), `programs.appimage.binfmt` (registers `appimage_type_1/2`;
  confirmed live, no privilege implication), `stylix` — reviewed, no
  finding.
- `users.groups.flatpak.gid = vars.gids.flatpak` (`:124`) — the comment
  explaining why it is pinned off 999 is correct and worth keeping.
- `virtualisation.podman` with `dockerCompat = true` (`:111-113`) —
  the rootful `podman.sock` is `root:podman 0660` and `lilijoy` is not
  in `podman`, so `dockerCompat` provides only the rootless CLI alias.
  Correctly done.
- `services.mullvad-vpn` (`:336-339`) — in use (daemon active). It
  installs one setuid-root wrapper, `mullvad-exclude` (the split-tunnel
  helper). Noted rather than filed: it is upstream's design, it is not
  something this profile can turn off while keeping the feature, and I
  have no specific defect to point at. The other setuid-root wrappers
  on these hosts are `mount`, `umount`, `su`, `newgrp`, `sg`, `passwd`,
  `pkexec`, `unix_chkpwd` (all baseline) and `qemu-bridge-helper` (from
  libvirtd, see F-P1-05).
- LLMNR — `systemd-resolved` is listening on `0.0.0.0:5355`, but 5355
  is **not** in any `allowed*Ports` list, so inbound LLMNR (including
  the multicast `224.0.0.252` path) is dropped by `nixos-fw`. The
  classic Responder-style name-poisoning surface is closed by
  accident-of-firewall rather than by configuration, but it is closed.
  Same for `rpcbind` on 111 and CUPS on 631.
- `tailscaled.sock` is mode `0666`, which looks alarming and is
  upstream's default: tailscaled gates state-changing operations on
  peer credentials, not file mode. Confirmed empirically that
  `lilijoy` can run `tailscale status` (read) — information disclosure
  about the tailnet only. Not a repo finding.
- `isoimage` — confirmed to carry **none** of these three profiles
  (`modules/flake/hosts.nix`): no tailscale, no sops, no run0. Its
  `security.sudo.enable` evaluates `true`, i.e. it has real sudo. That
  is P4's to judge, but it does mean `docs/hardening.md`'s "All hosts
  alias `sudo` to `run0`" is literally false for one host — a
  one-sentence doc fix.

---

## 4. Cross-references

- **Confirms** F-P0-06 (see F-P1-06), including the sysctl-priority
  interaction, and proposes the inverted default.
- **Refutes** threat model §4.3 path 1 and the §7.4 working hypothesis:
  `docker` on `lilijoy` is inert (F-P1-13). The live equivalent is
  `libvirtd` (F-P1-05), which reaches `lilijoy` transitively through
  `PC.nix`'s import of `virtual-machines` and is invisible in
  `PC.nix`'s own `extraGroups` list.
- **Extends** threat model §2.1 to torrent, and by configuration to
  thinkpad: the "CGNAT illusion" is not homelab-only. The exposure
  table in §2 should be updated — torrent's "Public v6: unknown /
  varies" is now "yes, observed 2026-08-26", and its "Listens publicly:
  nothing intended" is wrong (F-P1-04).
- **Bears on** F-P0-01: its proposed remediation (a) lists "private
  repo" among the compensating controls for accepting unsigned
  unattended deploys. Per §4.7 the repository is public, so that
  compensating control does not exist and option (a) needs rewriting
  before it can be accepted. §4.7 also raises a second inbound path
  that F-P0-01 does not consider — anyone can open a pull request
  against `origin/master`.
- **Applies §4.7** to the whole of this part. Two findings changed as a
  result: F-P1-03 (`initialPassword`) went from MEDIUM to HIGH once it
  is read as a *published* credential rather than a weak one, and
  F-P1-02 exists at all only because permanent public ciphertext plus a
  whole-archive age key on an un-encrypted laptop is a different
  finding from over-broad recipients in a private repo. Nowhere in this
  report does a rating rest on an adversary not knowing something; the
  one place it might have — F-P1-04's reliance on an IPv6 address that
  is not itself published — is dealt with inside that finding.
- **Hands to P5/P7:** the on-disk SSH key implied by F-P1-07, and
  `passwd -S lilijoy` on thinkpad, which is the single check that
  settles F-P1-03's severity.
- **Hands to whoever owns `.sops.yaml`** (and
  `docs/procedures/secrets.md`): the single seven-recipient
  `creation_rule` in F-P1-02. P1 raises it because the shared profiles
  create two of those recipients, but the split itself is not P1's file
  to change.
