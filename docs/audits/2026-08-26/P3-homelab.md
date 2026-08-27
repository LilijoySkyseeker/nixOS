# P3 — homelab host configuration

Part 3 of the 2026-08-26 fleet-wide security audit. Scope:
`hosts/homelab/configuration.nix`, `hosts/homelab/disko.nix`,
`hosts/homelab/hardware-configuration.nix`, plus homelab's own call-site
settings for the shared modules (`myAutoUpdate`, `myPushDeploy`,
`myZrepl`, `myHealthAlerts`) and its restic jobs.

Rated against [`00-threat-model.md`](00-threat-model.md) §6, including
§4.7 (the repository is public). Schema per
[`P0-findings.md`](P0-findings.md).

**Counts:** 3 HIGH, 7 MEDIUM, 7 LOW, 7 INFO.

---

## 1. Scope and method

### Files read in full

- `hosts/homelab/configuration.nix` (494 lines)
- `hosts/homelab/disko.nix`
- `hosts/homelab/hardware-configuration.nix`
- `docs/audits/2026-08-26/00-threat-model.md` (including §4.7)
- `docs/audits/2026-08-26/P0-findings.md`
- `docs/hardening.md`, `hosts/homelab/README.md`
- `.sops.yaml`, `modules/flake/deploy-guards.nix`,
  `modules/flake/hosts.nix`, `modules/nixos/health-alerts.nix:230-280`,
  `modules/services/octodns.nix:155-210`, `modules/nixos/zrepl.nix`
  (mount/authorized-keys sections), `docs/backups.md` offsite section,
  `TODO.md:220-240` — read only far enough to settle questions this
  part owns.

### Claims verified, and how

Everything below was read out of the **evaluated** configuration, not
the source text, unless stated otherwise. Because `nix eval` is
unavailable in this sandbox, values were extracted by building a
`writeText` derivation over `nixosConfigurations.homelab.config` and
reading the resulting JSON — equivalent, and it forces the same option
merge.

| Claim | How verified |
|---|---|
| Complete effective firewall (host-wide + per-interface) | built `config.networking.firewall` in full to JSON |
| sshd directive precedence | read the pinned module `nixos/modules/services/networking/ssh/sshd.nix` — `sshconf = cat ${configFile} - <<EOL ${cfg.extraConfig} EOL`, i.e. `settings` first, `extraConfig` last; then built `config.environment.etc."ssh/sshd_config".source` and **ran the pinned `openssh-10.4p1` `sshd -T`** against it, and again against mutated copies, to prove which lines win |
| `d /srv 0770 - root root -` is rejected | ran the **pinned** `systemd-260.2`'s `systemd-tmpfiles --dry-run --create` on the exact line → `Invalid age 'root'`, exit 65 |
| `A` tmpfiles ACL semantics (recursive, replacing) | ran pinned `systemd-tmpfiles --create` on a scratch tree with a pre-existing named ACL; the pre-existing entry was removed and the new entry propagated into a subdirectory |
| `/boot` mount options | `config.fileSystems."/boot".options == [ "defaults" ]`; traced to disko's `filesystem.nix:28-32` `mountOptions` default and its `_config` mapping to `fileSystems.<mp>.options` |
| Docker firewall integration is compiled in and enabled | `strings` on the real `moby-29.6.2/libexec/docker/dockerd` shows `DOCKER-USER`, `DOCKER-FORWARD`, `DOCKER-BRIDGE`, `DOCKER-CT`, `DOCKER-INGRESS`; merged `daemon.settings` contains no `"iptables": false`; `networking.firewall.filterForward == false`; `extraCommands` adds no `DOCKER-USER` rules |
| Container port publishing | `config.virtualisation.oci-containers.containers.*.ports` — `25565:25565`, `19132:19132/udp`, `34197:34197/udp`, `34198:34198/udp`, none with a bind address |
| root's password is locked | pinned `nixos/modules/config/update-users-groups.pl:299` — `$sp_pwdp = "!" if !$spec->{mutableUsers}` |
| `networkd-dispatcher` cannot fire | `config.systemd.network.enable == false`, NetworkManager is the network stack; the daemon's only trigger is `bus.add_signal_receiver(bus_name='org.freedesktop.network1')` (read in the packaged script), and its unit has no dependency that would start networkd |
| `security.protectKernelImage` default | pinned `nixos/modules/security/misc.nix:44-50` → `default = false` |
| `networking.firewall.logRefusedConnections` default | pinned `nixos/modules/services/networking/firewall.nix:119-125` → `default = false` |
| sops recipients | `.sops.yaml` — one `creation_rules` entry covering `secrets/*.yaml`, all seven age recipients on every secret |
| homelab's sops identity | `config.sops.age.sshKeyPaths == [ "/etc/ssh/ssh_host_ed25519_key" ]`, `age.keyFile == null`, `gnupg.sshKeyPaths == []` |
| zrepl sends no ZFS properties | built `config.environment.etc."zrepl/zrepl.yml".source` — no `send: properties:` key anywhere, so zrepl's default (`false`) applies and received datasets inherit `mountpoint=none`/`canmount=off`/`devices=off` from `zbackup/backup/<host>` |

### What I could not verify

- **Live iptables/nftables state — resolved by the coordinator, not by
  me.** The brief forbids touching homelab, so I derived the Docker
  bypass statically (chain names in the shipped `moby-29.6.2` binary,
  merged `daemon.settings` with no `"iptables": false`,
  `filterForward = false`, no `DOCKER-USER` rules in `extraCommands`)
  and rated it PLAUSIBLE as to runtime. P4 reached the same conclusion
  independently from `oci-containers.nix:180-183`, and the coordinator
  then ran the live `iptables`/`ip6tables`/`ss` capture. It is now
  CONFIRMED, including the negative result that there are no IPv6 DNAT
  rules. The capture is quoted verbatim in F-P3-04. I did not run it.
- **Whether `/etc/nixos`'s `origin` remote on homelab is SSH or
  HTTPS.** The worktree's own remote is `git@github.com:...`, and
  `/etc/nixos` is an imperatively-created checkout that nothing in the
  flake defines. F-P3-05 is written to hold either way but its severity
  differs; the branch is flagged.
- **Whether the tailnet has actually *approved* homelab's advertised
  subnet route and exit node.** That is console state, not Nix state
  (same drift class as F-P0-04).
- **Whether anyone ever uses SFTP/SCP against homelab** (F-P3-15) —
  behavioural, not readable from config.
- **The contents of any secret.** Never decrypted; only recipients,
  modes, owners and paths were examined, per `docs/procedures/secrets.md`.
- **Whether `homelab3` in `.sops.yaml` is literally the age key derived
  from homelab's SSH host key.** It is by elimination (no other identity
  mechanism is configured), but the public host key is not in the repo,
  so `ssh-to-age` could not confirm it. Marked PLAUSIBLE where it
  matters.

---

## 2. Findings

### F-P3-01 — homelab's SSH host key is the age key for the *entire* public secrets file, and it exists in more places than that tolerates

- **File:** `hosts/homelab/configuration.nix:387-392,490-491`,
  `hosts/homelab/disko.nix:14-44,177-211`,
  `hosts/homelab/configuration.nix:96-149` (restic paths),
  `.sops.yaml:1-25`
- **Severity:** HIGH
- **Confidence:** CONFIRMED for the mechanism and every copy listed;
  PLAUSIBLE only for the identification of the `homelab3` recipient
  with the derived key.
- **Axis:** hardening
- **Reachability:** A8 (physical/drive disposal — four 12TB drives and
  an SSD, none encrypted, in a USB enclosure that unplugs), A9/A2 (the
  offsite B2 copy), and A7-equivalent-on-homelab via the `disk` group
  (F-P3-02). Under §4.7 the ciphertext is already in the attacker's
  hands; only the key is missing.
- **Rule:** new-rule candidate — `docs/hardening.md` covers swap and
  secrets but says nothing about the age key's own storage.
- **Finding:** `config.sops.age.sshKeyPaths = [
  "/etc/ssh/ssh_host_ed25519_key" ]` with `age.keyFile = null`, so
  homelab's sops identity *is* its SSH host key. `.sops.yaml` has a
  single `creation_rules` entry for `secrets/*.yaml` listing all seven
  recipients, so that one key decrypts **every secret in the file** —
  not just homelab's: the vps-deploy key, both laptops' zrepl keys,
  every tailscale auth key, the wireguard PSK, the Cloudflare octoDNS
  token, the Discord webhook, the Samba password, the Backblaze
  credentials. §4.7 makes this historical rather than momentary: the
  ciphertext and all 72 of its revisions are public and permanent, and
  rotation is not retroactive, so obtaining this key at any future date
  decrypts every secret the file has ever held. (The recipient is named
  `homelab3`, implying two prior host-key generations whose ciphertext
  is likewise still public.)

  That key currently exists, in plaintext, in at least four places:

  1. `/nix/state/etc/ssh/ssh_host_ed25519_key` on `zroot`, which has
     **no ZFS native encryption** and sits on an unencrypted SATA SSD.
  2. Paged-out copies in the **8 GiB unencrypted swap partition**
     (`disko.nix:29-34`) — see F-P3-06.
  3. Readable via the raw block device by anything in the `disk`
     group — see F-P3-02.
  4. **Inside the offsite Backblaze restic repository.** The restic job
     backs up `zroot/local/state` (`configuration.nix:110`), and
     `/nix/state` is where impermanence stores the persisted
     `/etc/ssh/ssh_host_ed25519_key` (`configuration.nix:490`). So the
     age key that decrypts the world-readable ciphertext is sitting in
     a third-party bucket whose name (`restic21029709384`) is also
     published in this repo.
- **Proposed fix:** decision required; these compose rather than
  compete.
  - (a) Stop using the host key as the age identity. Give homelab a
    dedicated age key (`sops.age.keyFile`) that is *not* in any backup
    path and not derivable from a file the SSH daemon serves. Note this
    does not undo past exposure — the old ciphertext stays public — so
    it must be paired with rotating every secret.
  - (b) Enable ZFS native encryption on `zroot` (and see F-P3-08 for
    `zdata`/`zbackup`). Kills copies 1–3 at once for an attacker who
    only has the disks.
  - (c) Narrow `.sops.yaml` from one blanket rule to per-secret
    recipient sets, so homelab's key stops being a fleet-wide master
    key. This is the highest-value change and the cheapest to reason
    about.
  - (d) Exclude `/nix/state/etc/ssh` from the restic path set, or
    accept and document why the key belongs in the offsite copy.
- **Fix risk:** (a) and (c) both require re-encrypting
  `secrets/secrets.yaml`, which is exactly the operation
  `docs/procedures/secrets.md` reserves for the user — no agent may do
  it. (b) is a pool-level change: `zroot` cannot be encrypted in place,
  so it means a reinstall, and the initrd rollback service plus
  `neededForBoot` on `/nix` and `/nix/state` all interact with key
  loading. (d) silently changes what a bare-metal restore can recover;
  the restore procedure doc would need updating in the same change.
- **Owner:** P3 for the homelab-side copies; P1/P8 for `.sops.yaml`'s
  recipient structure; user decision on rotation.

### F-P3-02 — the `health-check` service user permanently holds the `disk` group, which is read/write on every raw block device

- **File:** `modules/nixos/health-alerts.nix:272-279` (grant),
  `hosts/homelab/configuration.nix:315-350` (homelab's call site),
  `hosts/homelab/configuration.nix:89-92` (the same user owns the
  Discord webhook secret)
- **Severity:** HIGH
- **Confidence:** CONFIRMED
- **Axis:** hardening / documentation
- **Reachability:** any code execution as `health-check` — a bug in the
  alert script, a compromised dependency in its `PATH`, or a future
  unit that reuses the user. It is not directly network-reachable
  today, which is why this is HIGH and not CRITICAL.
- **Rule:** violates `docs/hardening.md` "Dedicated service users" —
  "grant only the specific group memberships/capabilities … actually
  needed". Also failure mode §7.5: the code comment describes a
  narrower grant than the one it makes.
- **Finding:** `users.users.health-check.extraGroups = [ "disk" ]`. On
  NixOS `/dev/sd*`, `/dev/nvme*` and friends are `root:disk` mode
  `0660` — the `disk` group is **read *and write***, which makes it
  root-equivalent by construction: raw write to `zroot`'s vdev is
  arbitrary modification of the running system, and raw *read* of it
  yields `/nix/state/etc/ssh/ssh_host_ed25519_key`, i.e. F-P3-01, i.e.
  every secret the fleet has ever held. It also yields the swap
  partition (F-P3-06) and both data pools.

  The module's own comments say "`disk` group gives **read** access to
  the raw block devices smartctl needs" (`:272-273`) and "read/write
  access to the block device via the `disk` group; grant only that, not
  root" (`:249-250`). The second is accurate about the access and
  inaccurate about the conclusion — that *is* root. The unit is
  otherwise carefully built (`AmbientCapabilities`/
  `CapabilityBoundingSet` pinned to `CAP_SYS_RAWIO` alone, full
  sandbox stack, `NoNewPrivileges`), which makes the group the one
  unbounded piece.

  Worth noting the grant is on the **user**, not the unit. Anything
  else that ever runs as `health-check` inherits it — and
  `health-check` is already the owner of
  `sops.secrets.homelab_discord_webhook`.
- **Proposed fix:** two steps, both small.
  1. Move the membership off the user and onto the unit:
     delete `extraGroups = [ "disk" ]` and set
     `serviceConfig.SupplementaryGroups = [ "disk" ]` on
     `systemd.services.health-check`. Same capability while the check
     runs, none outside it. Strictly better with no behaviour change.
  2. Then narrow further if wanted: a udev rule granting a dedicated
     `smart-read` group on just the monitored devices, or
     `DeviceAllow=` entries per device — `CAP_SYS_RAWIO` is already
     scoped by the bounding set, so the file permission is the only
     remaining breadth.
- **Fix risk:** low; if `SupplementaryGroups` is mistyped the check
  fails loudly (smartctl permission errors) rather than silently. VM
  test the unit, and confirm the SMART section of the next Discord
  alert still reports drives rather than errors.
- **Owner:** P3 raises it; the fix lands in `modules/nixos/health-alerts.nix`,
  which vps also imports — coordinate with whoever owns that file so
  vps (`smartd` forced off there, but the module's user is still
  created) gets the same treatment.

### F-P3-03 — both copies of the backups are destroyable from homelab, and the config actively shortens the offsite recovery window to 24 hours

- **File:** `hosts/homelab/configuration.nix:96-170` (esp. `:102`,
  `:104-106`, `:126`, `:139-142`, `:166`), `:183`
- **Severity:** HIGH
- **Confidence:** CONFIRMED for the configuration; PLAUSIBLE for the
  exact B2 application-key scope, which is inside a secret and was not
  read.
- **Axis:** hardening
- **Reachability:** A9 via A6/A5/A2 — anything that gets root on
  homelab. Per §4.1 that includes one commit to `origin/master`, and
  §4.7 makes the whole arrangement (bucket name, retention policy,
  schedule) public reading.
- **Rule:** new-rule candidate — `docs/hardening.md` and
  `docs/backups.md` say nothing about backup immutability.
- **Finding:** Threat model §1 ranks the backup pools as asset #1 and
  notes they are "uniquely vulnerable to an *authorized* actor". Both
  copies are authorized from the same place:

  - `zbackup` is imported at boot and always online
    (`boot.zfs.extraPools = [ "zbackup" ]`, `:183`), and homelab holds
    retention authority over it by design (`:185-203`). Root on homelab
    is `zfs destroy -r zbackup`.
  - The offsite copy is reachable with credentials that live on the
    same host. `restic forget --prune` runs as part of **every** weekly
    run (`pruneOpts = [ "--keep-daily 2" ]`, `:139-142`), which by
    itself keeps only two snapshots.
  - `rcloneOptions.b2-hard-delete = "false"` (`:105`) correctly leaves
    deletions as B2 "hide" markers rather than hard deletes — the
    version history is the safety net. But `ExecStartPre` then calls
    `rclone backend lifecycle … -o daysFromHidingToDeleting=1`
    (`:166`), which reduces that net to **one day**. After 24 hours the
    hidden versions are gone for good.
  - Being able to *set* a bucket lifecycle rule means the B2
    application key holds `writeBucketSettings`, which is well beyond
    what a backup writer needs and strongly implies `deleteFiles` too.

  Net effect: an adversary with root on homelab destroys the local
  consolidated backup immediately and the offsite copy within a day,
  and needs no vulnerability to do it — only the credentials already
  sitting there. There is no append-only endpoint, no B2 Object Lock,
  and no copy anywhere that homelab cannot reach.
- **Proposed fix:** decision required.
  - (a) **B2 Object Lock** on the bucket with a governance/compliance
    retention period longer than the prune cadence. This is the real
    fix and the only one that survives root on homelab.
  - (b) Split the credentials: give the backup job a B2 key without
    `deleteFiles`/`writeBucketSettings`, and run `forget --prune` as a
    separate, differently-credentialed, less frequent job (ideally
    triggered from somewhere that is not homelab).
  - (c) At minimum, raise `daysFromHidingToDeleting` from `1` to
    something that matches how quickly you would actually notice — 30
    is the usual choice — and record the storage-cost reasoning in
    `docs/backups.md`, which currently does not discuss this at all.
  - (d) Independently: record in `docs/backups.md` that both copies
    share a single trust root, so nobody later mistakes zbackup +
    Backblaze for two independent copies. They are two copies with one
    authority.
- **Fix risk:** (a) Object Lock interacts badly with `restic prune`,
  which rewrites pack files — a retention period longer than the prune
  interval will make prune fail rather than silently skip, so it needs
  the health alerting to actually page (it will: the `last-success`
  marker is only touched after `check`, `:168`). (b) means two secrets
  and two rclone remotes. (c) increases B2 storage cost by roughly the
  churn over the retained window. None should be applied without a test
  restore first — `docs/backups.md:387` already notes the restore path
  has never been exercised.

### F-P3-04 — homelab's internet exposure silently depends on Docker's IPv6 default staying off, and nothing anywhere records that

- **File:** `hosts/homelab/configuration.nix:39-44`
  (`virtualisation.docker.daemon.settings`,
  `virtualisation.oci-containers.backend = "docker"`);
  interacts with `configuration.nix:394` and the interface-scoped
  rules in `minecraft.nix:23-36` / `factorio.nix:72-79`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening / documentation
- **Reachability:** none today. A1/A2/A3 directly against homelab's
  three global IPv6 addresses the moment Docker IPv6 is enabled, with
  no rate limiting and no vps in the path.
- **Rule:** failure mode **§7.1 exactly** — a security property resting
  on an unstated assumption about the network. Also §2.1: this is the
  CGNAT illusion with a different mechanism underneath it.
- **Finding:** **This finding is the residue of P4's F-P4-02, not a
  duplicate of it.** P4 owns the bypass itself and has confirmed it
  live; the coordinator's verification on 2026-08-26 reads:

  ```
  # iptables -t nat -S            (no interface match on any rule)
  -A DOCKER -p tcp -m tcp --dport 25565 -j DNAT --to-destination 172.17.0.3:25565
  -A DOCKER -p udp -m udp --dport 19132 -j DNAT --to-destination 172.17.0.3:19132
  -A DOCKER -p udp -m udp --dport 34197 -j DNAT --to-destination 172.17.0.2:34197
  -A DOCKER -p udp -m udp --dport 34198 -j DNAT --to-destination 172.17.0.4:34198

  # ip6tables -t nat -S | grep <game ports>
  (nothing)

  # iptables -S nixos-fw | grep <game ports>
  (all ten interface-scoped rules present, correctly written,
   tailscale0/wg0 only — and in the INPUT path, which DNAT'd
   traffic never reaches)

  # ss -tlnp / ss -ulnp
  (all four bound by dockerd on 0.0.0.0; none on ::)
  ```

  So the present-day exposure is **LAN-wide (A4), not internet-wide**:
  homelab has no public IPv4 (ISP CGNAT), and there are no IPv6 DNAT
  rules. The internet path to those game servers remains solely vps's
  deliberate `wg0` forwarding, which is the intended design. That is
  materially less severe than the worst case and should be read that
  way.

  What is left, and what is homelab's rather than P4's, is *why* that
  is true. It is true only because Docker does not enable IPv6 for the
  default bridge unless told to. Nothing in this configuration, this
  repo's docs, or the threat model records that homelab's freedom from
  internet exposure on four unauthenticated game ports rests on a
  third-party daemon's default value. Concretely:

  - `hosts/homelab/configuration.nix:39-41` sets
    `virtualisation.docker.daemon.settings.userland-proxy = false`
    under the bare comment `# docker settings`. It is a performance
    tweak, unremarked, and it sits in exactly the block where someone
    would later add `"ipv6" = true;` or `"ip6tables" = true;` while
    chasing an unrelated problem.
  - `:44` sets the backend to docker with no comment about what that
    implies for port publishing.
  - The one place the property *is* written down is an incidental
    aside in an unrelated module —
    `modules/services/octodns.nix:49-51` notes the game ports are
    IPv4-only and that "there are no ip6tables DNAT rules for them
    either". A load-bearing security invariant documented only as a
    parenthetical in the DNS module is not documented.

  If Docker IPv6 were ever switched on, four game servers would become
  directly reachable from the internet on homelab's three global IPv6
  addresses, bypassing vps entirely — so bypassing the raw-table
  hashlimit and the crowdsec ipset that §4.6 identifies as the *only*
  controls on that traffic — and the ten `nixos-fw` rules would still
  not stop them, because they are still in `INPUT`. §7.1's whole point
  is that this class of assumption was true when written and stopped
  being true silently. Here it has not stopped being true yet. That is
  the window to write it down in.
- **Proposed fix:** two parts, both host-level and both mine.
  1. **Record the invariant where it can be tripped over.** A comment
     at `:39-44` stating that these four ports are published by Docker
     on every IPv4 address, that the `networking.firewall.interfaces`
     rules do not constrain them, and that the only thing keeping them
     off homelab's public IPv6 is Docker's IPv6 default — so enabling
     `"ipv6"`/`"ip6tables"` in this very block would expose them to the
     internet. Same treatment as the `:357-365` sshd comment, which is
     the model for how this repo records exactly this kind of thing.
  2. **Stop relying on the invariant.** Add a `DOCKER-USER` allowlist
     so the constraint is enforced rather than inherited from a
     default:

     ```nix
     networking.firewall.extraCommands = ''
       iptables  -N DOCKER-USER 2>/dev/null || true
       ip6tables -N DOCKER-USER 2>/dev/null || true
       iptables  -I DOCKER-USER -i wg0        -j RETURN
       iptables  -I DOCKER-USER -i tailscale0 -j RETURN
       iptables  -A DOCKER-USER -j DROP
       ip6tables -A DOCKER-USER -j DROP
     '';
     ```

     Written as an allowlist terminating in DROP, and applied to
     **both** families, so the v6 case is closed pre-emptively rather
     than after someone flips a daemon setting. Note `-I` inserts in
     reverse order; the `RETURN`s must end up above the `DROP`.
- **Fix risk:** getting the chain order wrong silently breaks minecraft
  and factorio for real players over `wg0`, with no build-time signal
  and no VM test that would catch it. `DOCKER-USER` is created by
  dockerd, so `extraCommands` must tolerate it not existing when the
  firewall starts — this is failure mode §7.3, and vps's pre-created
  crowdsec ipset is the established precedent for the shape of the fix.
  Verify after switching with `iptables -S DOCKER-USER` and an actual
  connect both from a LAN host (should fail) and through vps (should
  succeed).
- **Owner:** P3. The bypass itself is P4's F-P4-02; the undocumented
  dependency and the host-level `DOCKER-USER` remediation are here.
  Note also that homelab's `users.groups.docker.members` is empty
  (confirmed by P4), so there is no A7 docker-socket privilege path on
  this host — unlike the laptops (§4.3).

### F-P3-05 — root re-TOFUs GitHub and vps on *every* boot, because impermanence wipes `known_hosts` and only two hosts are pinned declaratively

- **File:** `hosts/homelab/configuration.nix:217-225` (the two pins),
  `:454-465` (the rollback), `:470-493` (persist list),
  `:281-312` (auto-update + push-deploy call sites),
  `:70-76` (DNS); `modules/flake/deploy-guards.nix:37-53`,
  `modules/nixos/push-deploy.nix:114`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the wipe, the missing pins and the
  `accept-new` flags; PLAUSIBLE for the GitHub leg, which depends on
  whether `/etc/nixos`'s `origin` is SSH or HTTPS (see below).
- **Axis:** hardening
- **Reachability:** A4 — an on-path device on `192.168.1.0/24`. DNS is
  the lever: `networking.networkmanager.insertNameservers =
  [ "8.8.8.8" "1.1.1.1" ]` with `services.resolved` settings
  `DNSSEC = false`, `DNSOverTLS = false`, so every name homelab
  resolves — including `github.com` — is answered over plaintext,
  unauthenticated UDP that an A4 attacker can spoof.
- **Rule:** new-rule candidate; extends F-P0-07, which the threat model
  rated LOW on the reasoning that TOFU only happens once.
- **Finding:** F-P0-07 says the first fetch on a fresh host is
  unauthenticated. On homelab it is not the first fetch — it is
  **every** fetch after every reboot. `boot.initrd.systemd.services.rollback`
  runs `zfs rollback -r zroot/local/root@blank` (`:463`), so `/root`
  and with it `/root/.ssh/known_hosts` are destroyed at each boot, and
  `/root` is not in the persist list (`:474-492`). The config already
  knows the right answer to this and applies it to exactly two hosts:
  `programs.ssh.knownHosts.torrent` and `.thinkpad` (`:217-225`), with
  a comment (`:206-216`) explaining precisely why declarative pinning
  beats `accept-new`. That reasoning was never extended to the two
  remaining SSH peers, both of which are on the *deploy* path:

  - **vps.** `myPushDeploy` targets `vps-deploy@vps`
    (`:305`) and `modules/nixos/push-deploy.nix:114` sets
    `NIX_SSHOPTS="-i … -o StrictHostKeyChecking=accept-new"`. There is
    no `programs.ssh.knownHosts.vps`. This leg is the less severe of
    the two: `vps` resolves through MagicDNS to a tailnet address, so
    the transport is already device-authenticated by WireGuard — but
    that safety comes from tailscale, not from the SSH configuration,
    and it evaporates if `vps` ever resolves to a non-tailnet address
    (which the prepended 8.8.8.8/1.1.1.1 makes more likely, not less).
  - **github.com.** `deploy-guards.nix:43` uses
    `StrictHostKeyChecking=accept-new` and there is no pin. If
    `/etc/nixos`'s `origin` is SSH — the worktree's own remote is
    `git@github.com:LilijoySkyseeker/nixOS.git`, so this is the likely
    case — then after every reboot the first `auto-switch` run accepts
    whatever host key answers a spoofable DNS lookup, merges
    `origin/master` and `nixos-rebuild switch`es it as root. That is
    §4.1 reached from the LAN. If `origin` is HTTPS instead, TLS covers
    it and `GIT_SSH_COMMAND` is inert — which would itself be worth
    knowing, since nothing in the repo states which it is.

  The underlying structural point is the same either way: `/etc/nixos`
  is an imperatively-created checkout, and the remote URL that
  ultimately decides what root builds is **not declared anywhere in the
  flake**. (To its credit it is root-owned and root-only — mode `0755
  root:root` in the persist list — so homelab does *not* have
  F-P0-03's user-writable-checkout problem. That part is clean.)
- **Proposed fix:**
  1. Add `programs.ssh.knownHosts.vps` and
     `programs.ssh.knownHosts."github.com"` next to the two existing
     pins, reusing the same comment's reasoning. GitHub publishes its
     host keys at `https://api.github.com/meta`; pin all three types.
     Then the `accept-new` in both deploy paths becomes unreachable and
     can be tightened to `yes` (P7's call).
  2. Turn on `DNSOverTLS` and `DNSSEC` in `services.resolved.settings`,
     or drop `insertNameservers` and let tailscale's DNS handle it —
     see F-P3-17.
  3. Assert the expected `origin` URL in the deploy guard rather than
     trusting whatever `/etc/nixos` happens to have — a one-line
     `git remote get-url origin` comparison that exits non-zero.
- **Fix risk:** a stale pinned GitHub key breaks all unattended updates
  fleet-wide until corrected (F-P0-07 notes GitHub has rotated before);
  health alerting must page on a failed `auto-switch`. Pinning `vps`
  breaks push-deploy if vps is ever rebuilt with a new host key —
  which happened once already (`.sops.yaml` comment: "Rotated
  2026-08-25 for the post-brick reinstall"), so the reinstall runbook
  needs a step to update the pin.
- **Owner:** P3 for homelab's pins; P7 for the guard mechanism and for
  whether `accept-new` should stay anywhere once the pins exist.

### F-P3-06 — an 8 GiB unencrypted disk swap partition on a host that decrypts live secrets, against an explicit hardening rule

- **File:** `hosts/homelab/disko.nix:29-34`;
  `hosts/homelab/configuration.nix:86-93,204,300,417,420` (the secrets)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A8 (drive disposal, RMA, theft) and — via
  F-P3-02 — anything in the `disk` group. Under §4.7 what is recovered
  is not merely "a secret" but the key to permanently-public
  ciphertext.
- **Rule:** **violates an existing `docs/hardening.md` rule** —
  "Secrets + swap": *"prefer `zramSwap.enable = true` over a disk swap
  partition on any host where sops decrypts live secrets (done on
  `vps`) — disk-backed swap risks paging secret material to persistent
  unencrypted storage."*
- **Finding:** `config.swapDevices` resolves to one entry,
  `/dev/disk/by-partlabel/disk-nvme-a-swap`, 8 GiB, with no
  `randomEncryption`; `config.zramSwap.enable` is `false`. homelab
  decrypts nine sops secrets into `/run/secrets` (a tmpfs, and tmpfs
  pages are swappable): the Backblaze rclone config and restic
  password, the zrepl key, the vps-deploy private key, the wireguard
  private key and PSK, the tailscale auth key, the Cloudflare octoDNS
  token, the Discord webhook. The sops-nix activation also reads
  `/etc/ssh/ssh_host_ed25519_key` into memory to derive the age
  identity — i.e. F-P3-01's key. The rule was written for exactly this
  and applied to exactly one host; this is failure mode §7.6.

  The rule is the reason this is MEDIUM rather than LOW even though no
  exploit is demonstrable: the class is real, and the repo already
  decided it was.
- **Proposed fix:** `zramSwap.enable = true;` in
  `hosts/homelab/configuration.nix`, and drop the `swap` partition from
  the `rootSsd` builder in `disko.nix`. If disk swap must stay for
  capacity reasons (16 GiB RAM, and the weekly restic run is
  memory-hungry), the middle option is
  `swapDevices = [ { device = …; randomEncryption.enable = true; } ]` —
  which is compatible with `nohibernate` (already set by the ZFS
  module) since hibernation is what random-key swap breaks.
- **Fix risk:** removing the partition from `disko.nix` does **not**
  remove it from the already-formatted disk — disko only runs at
  install time, so the change is cosmetic on the live host unless
  `swapDevices` is also emptied, which is the part that actually stops
  the paging. Removing swap entirely on a 16 GiB box that builds vps's
  closure and runs restic could turn a slow build into an OOM kill;
  `zramSwap` mitigates but does not fully replace 8 GiB. Test a full
  `nixos-rebuild build` of both homelab and vps under the new
  configuration before switching.

### F-P3-07 — `A /storage` recursively *replaces* the ACL on the whole tree and grants the multimedia group write over everything

- **File:** `hosts/homelab/configuration.nix:79-83`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — semantics verified by running the pinned
  `systemd-tmpfiles` against a scratch tree.
- **Axis:** hardening
- **Reachability:** A5 (tailnet → jellyfin on 8096) and A1/A2 (internet
  → vps:443 → caddy/anubis → wg0 → jellyfin), since `jellyfin` is the
  only member of `multimedia`. A jellyfin compromise becomes write and
  delete over the entire media library.
- **Rule:** new-rule candidate; adjacent to "Dedicated service users"
  and its least-privilege intent.
- **Finding:** the two rules are

  ```
  A /storage      - - - - group:multimedia:rwx
  A /storage-bulk - - - - group:multimedia:rwx
  ```

  Three separate problems, all verified against the pinned systemd
  260.2:

  1. **`A` is recursive.** It walks the entire `/storage` and
     `/storage-bulk` trees — multiple terabytes — and does so on every
     boot *and* every `nixos-rebuild switch`, since
     `systemd-tmpfiles-setup` runs on both.
  2. **`A` without `+` replaces rather than adds.** In the scratch test
     a pre-existing `group:users:rwx` entry was silently removed when
     the rule ran. Any ACL anyone sets by hand on this tree is wiped at
     the next switch, with no warning.
  3. **The grant is `rwx`, and there is no `default:` entry.** Jellyfin
     needs read to scan a library; it is given write and delete over
     everything. And because no inheritable (`default:`) ACL is set,
     newly created directories do not inherit the grant — which is
     presumably *why* the rule is recursive and re-runs forever. The
     recursion is compensating for the missing default entry.

  Samba does need the group to have write (`force group = multimedia`,
  `create mask 0660`, `directory mask 0770`), so the grant itself is
  not gratuitous; it is the *membership* that is too broad, plus the
  replace-and-recurse mechanics.
- **Proposed fix:**
  - Change to `A+` (add rather than replace) and add the inheritable
    counterpart in the same argument, so new directories inherit and
    the recursion stops being load-bearing:
    `A+ /storage - - - - group:multimedia:rwx,default:group:multimedia:rwx`.
    Then a one-off recursive pass is enough and the boot-time rule can
    become non-recursive (`a+`).
  - Separately, take jellyfin out of `multimedia` and give it a
    read-only named entry (`group:jellyfin-ro:r-x`, or
    `user:jellyfin:r-x`) — that half is P4's, since
    `users.users.jellyfin.extraGroups` lives in `jellyfin.nix:49`.
- **Fix risk:** ACL changes on a live media tree are easy to get
  subtly wrong and hard to notice — the failure mode is samba writes
  starting to fail from an Android phone, or jellyfin losing library
  access, neither of which any build or VM test catches. Stage it: set
  the new rule, run `systemd-tmpfiles --dry-run`, then verify with
  `getfacl` on a sample of directories at several depths before
  switching. Note the first `A+` run over multi-TB will be slow.

### F-P3-08 — no encryption at rest on any pool; `zbackup` holds both laptops' entire home and root filesystems on removable USB drives

- **File:** `hosts/homelab/disko.nix:88-211` (all three `rootFsOptions`
  blocks), `hosts/homelab/configuration.nix:230-256`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A8. homelab is stationary, so burglary is the less
  likely path; **drive disposal and warranty RMA are the likely one** —
  four 12 TB HGST enterprise drives will eventually fail and go back to
  a vendor with every byte still on them, and the enclosure is
  USB-attached and unplugs without tools.
- **Rule:** new-rule candidate. `docs/hardening.md` has nothing on
  encryption at rest; the FDE work that exists
  (`worktree-fde-secureboot-plan`, per threat model §8.7) is scoped to
  thinkpad.
- **Finding:** `zroot`, `zdata` and `zbackup` all set `acltype`,
  `xattr`, `atime`, `compression`, `mountpoint`, `canmount`, `devices`
  and `sync` in `rootFsOptions` — and none of them sets `encryption`.
  Threat model §8.7 treats physical loss as a thinkpad problem, but
  `zbackup` is where thinkpad's problem is *duplicated*: zrepl pulls
  `zroot/local/home` and `zroot/local/root` from both torrent and
  thinkpad into `zbackup/backup/<host>/…` (`configuration.nix:230-245`).
  So the drives in the USB enclosure hold complete, unencrypted copies
  of both laptops' home directories and root filesystems, plus
  `/storage`'s personal data, plus (on `zroot`) the age key from
  F-P3-01. The offsite copy at Backblaze *is* encrypted, by restic —
  the local copies are the gap.

  Only `devices = "off"` is set on all three pools, which is a good and
  deliberate control (device nodes in a received root filesystem cannot
  be used) and is worth preserving. See F-P3-14 for its missing
  siblings.
- **Proposed fix:** ZFS native encryption on `zdata` and `zbackup` with
  a key file, unlocked at boot. Neither can be encrypted in place, so
  this is a "recreate the pool and re-replicate" job for `zbackup`
  (feasible — it is derived data) and a "copy 2.9 TB off and back"
  job for `zdata` (painful). `zroot` is the hardest and interacts with
  the initrd rollback; F-P3-01 option (a) — moving the age key off the
  host key — is a cheaper way to get most of `zroot`'s benefit.
  Whatever is decided, record it: an explicitly accepted risk with its
  reasoning is a fine outcome, an unexamined one is not.
- **Fix risk:** substantial. An encrypted `zbackup` that fails to
  unlock at boot silently stops all replication — exactly the
  ~23 h outage class already recorded at `configuration.nix:174-183`,
  and zrepl's failure mode there was "dataset does not exist", which is
  not obviously an unlock problem. `myHealthAlerts.backupStaleness`
  would catch it within 6 h for homelab's own datasets. Also: encrypted
  send/recv interacts with zrepl's `placeholder.encryption = "off"`
  setting (`modules/nixos/zrepl.nix:196-202` documents this precisely) —
  that value would have to change to `"inherit"` for an encrypted
  root, and getting it wrong fails every receive.

### F-P3-09 — the subnet route and exit node hand any tailnet device the whole home LAN and an egress path, and neither is enforced by anything in this repo

- **File:** `hosts/homelab/configuration.nix:404-412`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the advertisement; PLAUSIBLE for
  whether the tailnet has approved either, which is console state.
- **Axis:** hardening / needed-used
- **Reachability:** A5 — one stolen laptop, one over-broad auth key,
  one attacker-enrolled node. §4.4 already establishes the ACL is flat
  (`"ip": ["*"]`), so there is no per-service narrowing in front of
  this.
- **Rule:** n/a directly; this is the homelab half of open questions
  §8.1 and §8.5, and the confirmation F-P0-06 asked P3 for.
- **Finding:** `services.tailscale.extraUpFlags` merges to
  `[ "--advertise-tags=tag:homelab", "--advertise-routes=192.168.1.0/24",
  "--advertise-exit-node" ]`. Two grants:

  - **Subnet router.** Every tailnet device gets layer-3 reachability
    to every device on the home LAN — the router's admin interface,
    IoT devices, printers, phones — none of which is in this repo's
    threat model at all (A4 is described as "mostly unmodelled today").
    homelab does no filtering of this traffic: `filterForward = false`,
    so NixOS installs no `FORWARD` rules, and tailscale's own netfilter
    runner installs ACCEPT rules for approved routes.
  - **Exit node.** Every tailnet device can route arbitrary internet
    traffic out through the household's IP. That is an attribution and
    abuse exposure as much as a technical one.

  Both are almost certainly deliberate and useful. Two things make them
  worth a finding anyway. First, per §7.4 the question "is this still
  used?" has no answer in the config — nothing here records *which*
  device needs the subnet route or the exit node, or whether anything
  still does. Second, whether either grant is live depends on approval
  in the tailscale console, which Nix does not manage — the same drift
  problem as F-P0-04's ACL file, with the same consequence: the config
  cannot tell you the real state.

  **On F-P0-06:** confirmed. Given these two flags, homelab genuinely
  requires `useRoutingFeatures = "both"`; it is the one host in the
  fleet that does. Inverting the shared default to `"client"` and
  `lib.mkForce "both"`-ing it here is correct and safe from homelab's
  side. Note the ordering trap `docs/hardening.md` warns about applies
  in reverse here — homelab also sets `net.ipv4.ip_forward = 1` and
  `net.ipv6.conf.all.forwarding = 1` by hand (`:405-408`), which the
  tailscale module already forces; see F-P3-20.
- **Proposed fix:** decision required, and it is the user's.
  - Confirm both are actually used (`tailscale status --json` on the
    tailnet; check whether any device runs `--exit-node=homelab` or
    `--accept-routes`). Drop whichever is not.
  - If the subnet route stays, write down what the LAN's trust level
    is supposed to be (§8.5 currently records that nothing states it)
    and consider narrowing the advertisement from the whole `/24` to
    the specific hosts that need reaching.
  - If both stay, they belong in the ACL narrowing discussion of
    F-P0-04 — a per-service ACL is much less useful while any device
    can route into the LAN regardless.
- **Fix risk:** removing either is invisible to every build and VM test
  and shows up only as "something on the LAN stopped being reachable
  from my phone". Change one at a time and keep console access.

### F-P3-10 — access to homelab is *not* gated entirely by tailscale, and nothing on the host would notice an attack

- **File:** evidence spread across
  `hosts/homelab/configuration.nix:39-44,394,404-412,414-446`;
  `config.networking.firewall` as evaluated; `TODO.md:230-238`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A1/A3 for the unauthenticated path (internet →
  vps DNAT → wg0 → game servers), A4 for the LAN path (F-P3-04).
- **Rule:** n/a — this finding exists to settle the standing question
  in `TODO.md`, not to assert a rule violation. The decision remains
  the user's.
- **Finding:** the `TODO.md` entry says homelab having no intrusion
  detection is "fine today *if* access really is gated entirely by
  tailscale's own device authorization … which is precisely what Phase
  0 and P3 must confirm rather than assume." It is not. The evidence:

  **What *is* tailscale-gated (and cleanly so):** sshd (22),
  samba (445), nfsd (2049) — all reachable only via
  `networking.firewall.interfaces.tailscale0`, with the host-wide
  `allowedTCPPorts`/`allowedUDPPorts` genuinely empty and
  `trustedInterfaces = [ "lo" ]`. Notably homelab does **not** repeat
  vps's `trustedInterfaces = [ "tailscale0" ]` mistake (§4.4); it opens
  named ports instead. Nothing at all listens on the public IPv6
  address today. That half of the premise holds and is good work.

  **What is not:**

  1. **`wg0` is an unauthenticated path from the open internet.**
     `interfaces.wg0` opens 8096/tcp, 25565/tcp and
     19132+25565+34197+34198/udp. vps DNATs the game ports straight
     through to `10.100.0.2` (§4.6), and jellyfin's 8096 is fronted by
     caddy+anubis. So A1 and A3 reach code on homelab with no tailscale
     device authorization involved at any point. The only controls are
     vps's volumetric raw-table hashlimit and anubis's proof-of-work —
     neither of which authenticates anybody.
  2. **Docker publishes those same ports to every LAN IPv4 host**
     (P4's F-P4-02, confirmed live), bypassing even the interface
     scoping. A4 needs no tailscale identity of any kind.
  3. **Outbound-initiated paths ignore the tailnet entirely:** the
     unsigned auto-update from `origin/master` (§4.1), plaintext
     unvalidated DNS (F-P3-17), the fwupd/LVFS metadata refresh timer,
     and Docker image pulls.
  4. **§4.7 removes the obscurity that was implicitly propping this
     up.** The service inventory, port map, image tags and pinned
     `factoriotools/factorio:2.1.14` are all published. "Nobody knows
     this box exists" was never a strong argument and is now
     definitively not one.

  **And nothing on homelab would see any of it.** There is no
  CrowdSec, no fail2ban, and — verified against the pinned firewall
  module's `default = false` — `networking.firewall.logRefusedConnections`
  is off, where vps explicitly sets it `true`
  (`hosts/vps/configuration.nix:345`). So there is no record of refused
  connections either. What *does* exist is decent: `security.auditd` +
  `security.audit` with an `execve` rule from `profiles/server.nix`,
  `/var/log` correctly in the persist list so the audit trail survives
  reboots (the one thing `docs/hardening.md` explicitly warns about,
  and it is done), journald with `log-driver = journald` for the
  containers, and `myHealthAlerts` paging to Discord on failed units.
  That is forensics after the fact, not detection during.
- **Proposed fix:** decision required. Framing, not a recommendation:
  - The cheapest concrete step is
    `networking.firewall.logRefusedConnections = true;` — matches vps,
    costs nothing, and gives the audit trail something to correlate
    against. It should probably happen regardless of the bigger
    decision. Note it will **not** see the game-port traffic: that is
    class (b) in §3.0 and never enters `INPUT`, so the `DOCKER-USER`
    lockdown in F-P3-04 is the only place a drop for those ports could
    be logged at all.
  - The bigger question splits into two, and they have different
    answers. For the **tailnet-facing** services, a host IDS adds
    little that narrowing the ACL (F-P0-04) would not add more
    directly. For the **wg0-facing** game servers, there is no
    authentication anywhere in the path and no log-based detection is
    possible in principle — the traffic never reaches userspace on vps
    (§4.6) — so anything at all would have to live on homelab.
  - CrowdSec on homelab would have very little to read: sshd is
    tailnet-only, and the game servers log to the container journal in
    formats CrowdSec has no parsers for. fail2ban likewise. The honest
    conclusion is that conventional log-based IDS is a poor fit here,
    and the effort is better spent on (i) the DOCKER-USER lockdown of
    F-P3-04, (ii) ACL narrowing, and (iii) keeping the two game-server
    images current, since they are the only unauthenticated attack
    surface.
- **Fix risk:** `logRefusedConnections = true` on a host with a
  chatty LAN can be noisy in `journalctl -k`; `logRefusedUnicastsOnly`
  is already `true`, which bounds it.

### F-P3-11 — `/boot` is mounted world-readable, and systemd-boot says so on every boot

- **File:** `hosts/homelab/disko.nix:21-28`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any local account on homelab — `jellyfin`,
  `octodns`, `health-check`, `android-smb`, `nobody`. Not remotely
  reachable.
- **Rule:** new-rule candidate.
- **Finding:** the ESP is declared with `content.type = "filesystem"`
  and no `mountOptions`, so disko's default `[ "defaults" ]` applies
  (`lib/types/filesystem.nix:28-32`) and lands verbatim in
  `config.fileSystems."/boot".options`. vfat mounted with defaults uses
  `fmask=0022,dmask=0022`, i.e. everything under `/boot` is `0755` and
  world-readable. This is exactly the `bootctl` warning seen in the
  2026-08-26 reboot journal: the mount point backing
  `loader/random-seed` is world accessible, "which is a security hole".

  The concrete exposure is the systemd-boot random seed, which is
  mixed into the kernel's entropy pool at early boot; a local reader
  learns a value that is supposed to be secret. It is genuinely a
  small thing — but it is a warning the system prints at you on every
  boot, and the fix is one line.
- **Proposed fix:** in `hosts/homelab/disko.nix`, on the `esp`
  partition's `content`:

  ```nix
  content = {
    type = "filesystem";
    format = "vfat";
    mountpoint = …;
    mountOptions = [ "umask=0077" ];
  };
  ```

  `umask=0077` sets both `fmask` and `dmask`, giving `0700`/`0600`
  root-only. systemd-boot and the bootloader installer run as root, so
  nothing legitimate loses access.
- **Fix risk:** low, but note the same caveat as F-P3-06 — disko does
  not re-mount an existing system, so this takes effect at the next
  boot via the regenerated `fileSystems` entry (it does, because the
  option flows into `fileSystems`, not just into the formatter). Verify
  after reboot with `findmnt /boot` and `bootctl status`; the warning
  should be gone. If `boot.loader.efi.canTouchEfiVariables` writes
  ever start failing, check the mask first.

### F-P3-12 — the `/srv` tmpfiles rule is malformed and is silently rejected, so `/srv` stays `0755`

- **File:** `hosts/homelab/configuration.nix:80`
- **Severity:** LOW
- **Confidence:** CONFIRMED — reproduced with the pinned
  `systemd-260.2`.
- **Axis:** hardening
- **Reachability:** any local account on homelab.
- **Rule:** n/a — this is failure mode §7.2 exactly: config that
  renders but never takes effect.
- **Finding:** the rule is

  ```
  "d /srv 0770 - root root -"
  ```

  `tmpfiles.d` fields are `Type Path Mode User Group Age Argument`.
  That line supplies `Mode=0770`, `User=-`, `Group=root`, **`Age=root`**,
  `Argument=-` — one field too many, with `root` landing in the age
  slot. Running the pinned `systemd-tmpfiles --dry-run --create` on
  exactly this line gives:

  ```
  t.conf:1: Invalid age 'root'.
  exit=65
  ```

  systemd skips the bad line and continues with the rest of the file
  (verified: a valid second line in the same file was still processed).
  So `/srv` never gets `0770`. It is instead created implicitly, as a
  parent, by the jellyfin/minecraft/factorio rules and by impermanence's
  bind mounts — at the default `0755 root:root`.

  What that exposes: `/srv/minecraft/vanilla-plus`,
  `/srv/factorio/main`, `/srv/factorio/new` are persisted at `0755
  root:root`, so their contents are world-readable to any local
  account. Game-server data directories routinely hold RCON passwords,
  whitelists and op lists. `/srv/jellyfin/*` is `0755 jellyfin:multimedia`,
  same story. The intended `0770` on the parent was the thing meant to
  stop casual traversal, and it has never been in effect.
- **Proposed fix:** `"d /srv 0770 root root - -"` — five value fields,
  age and argument both `-`. Then re-check the child directories'
  own modes, because `0770` on the parent is only a traversal barrier;
  the per-service directory modes (P4's) are the real control.
- **Fix risk:** none to the mode change itself. But be aware the
  correction *will* newly deny traversal to anything that was relying
  on `/srv` being `0755` — Samba's `android-smb` does not go through
  `/srv`, and the container bind mounts are set up by dockerd as root,
  so nothing obvious breaks. Restart the containers after switching and
  confirm they still start.

### F-P3-13 — the restic job mounts ZFS snapshots into the shared `/tmp` for up to a week, while its own root-only runtime directory sits unused

- **File:** `hosts/homelab/configuration.nix:108-127,150-170`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the configuration; PLAUSIBLE for
  exploitability, which currently depends on there being no
  unsandboxed non-root process on the host.
- **Axis:** hardening
- **Reachability:** any local process that can write the real `/tmp`.
  Today that set looks empty — `jellyfin`, `octodns`, `health-check`,
  `nscd`, `samba-smbd` and `wpa_supplicant` all have `PrivateTmp = true`,
  the containers get their own tmpfs `/tmp`, and nix builds are
  sandboxed. That is a property of every *other* unit's configuration,
  though, not of this one.
- **Rule:** interacts with `docs/hardening.md`'s note that this unit
  legitimately needs `PrivateTmp = false` — that stays true; the
  directory choice is the part that does not have to.
- **Finding:** `backupPrepareCommand` does
  `mkdir -p /tmp/restic/$snapshot` then `mount -t zfs $snapshot
  /tmp/restic/$snapshot` for `zroot/local/state` and
  `zdata/storage/storage`, and `paths = [ "/tmp/restic" ]`. `/tmp` is
  the world-writable sticky shared `/tmp` (`PrivateTmp = lib.mkForce
  false`, `:162`, correctly — a mount made in `ExecStartPre`'s
  namespace would not propagate to `ExecStart`'s otherwise). The run
  has `TimeoutStartSec = "1w"` and the README notes it moves ~2.9 TiB,
  so the window is days, not minutes.

  Two consequences. The mounted snapshots are world-traversable for
  the duration — individual files keep their own modes, so the
  0600 host key stays protected, but the whole persisted-state and
  media trees are enumerable by any local account. And `/tmp/restic`
  can be pre-created by an unprivileged process before the timer
  fires; if created as a symlink, root's `mkdir -p` and `mount` follow
  it, which turns into "an unprivileged user chooses where root mounts
  a filesystem".

  The fix is nearly free because the unit **already has**
  `RuntimeDirectory = "restic-backups-backblazeWeekly"` (`:164`, added
  by the restic module for its `includes` file) — a root-owned
  directory under `/run` that nothing else can write.
- **Proposed fix:** mount under
  `/run/restic-backups-backblazeWeekly/mnt` instead of `/tmp/restic`,
  set `RuntimeDirectoryMode = "0700"`, and change `paths` to match.
  `PrivateTmp = false` still has to stay (the mount-propagation reason
  in `docs/hardening.md` is unchanged), and `rm -rf /tmp/restic` in
  `backupCleanupCommand` can go away entirely, since systemd removes
  `RuntimeDirectory` on stop.

  While in there, two robustness nits worth fixing in the same change:
  `backupCleanupCommand` pipes **every** snapshot on the system into
  `umount` (`zfs list -t snapshot -H -o name | xargs -I {} umount`),
  which on this host is thousands of entries including everything
  received into `zbackup`; and `backupPrepareCommand` picks the
  newest snapshot with `tail -n 1` on a name-sorted list, which is
  correct only as long as the `zrepl_` timestamp prefix keeps sorting
  lexicographically.
- **Fix risk:** `/run` is a tmpfs — mountpoints cost nothing, but
  confirm nothing writes real data there. `RuntimeDirectory` is
  removed when the unit stops, so the cleanup command must still
  unmount *before* that happens (it runs as `ExecStopPost`, which is
  early enough). Test with a manual
  `systemctl start restic-backups-backblazeWeekly` against a small
  dataset before trusting a real weekly run, and watch for the
  1-week timeout masking a hang.

### F-P3-14 — `setuid` and `exec` are not disabled on the data or backup pools, and `/storage` mounts with plain `defaults`

- **File:** `hosts/homelab/disko.nix:92-102,131-141,110-125`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A5 via SMB/NFS write access to `/storage`, or a
  future manual mount of a received dataset from `zbackup`.
- **Rule:** new-rule candidate; the natural sibling of the `devices =
  "off"` that is already there.
- **Finding:** all three pools set `devices = "off"` in
  `rootFsOptions` — good, deliberate, and it is what stops device nodes
  inside a received root filesystem from being usable. Neither
  `setuid = "off"` nor `exec = "off"` is set anywhere, and
  `config.fileSystems."/storage"` and `."/storage-bulk"` resolve to
  `options = [ "defaults" ]` (no `nosuid`, `nodev`, `noexec`) because
  they use `options.mountpoint = "legacy"`.

  Neither is currently exploitable on its own: an SMB or NFS client
  cannot create a setuid-*root* binary without already being root
  (NFS exports use `root_squash`, Samba sets `invalid users = root`).
  It is defence in depth against the case that matters most here —
  `zbackup` receives `zroot/local/root` from torrent and thinkpad, i.e.
  whole root filesystems full of setuid binaries, and while every
  `zbackup` dataset is `mountpoint = none` today, a restore is exactly
  the moment someone mounts one by hand under time pressure.

  Related and checked clean: zrepl transmits **no** ZFS properties
  (the generated `/etc/zrepl/zrepl.yml` has no `send: properties:` key,
  so zrepl's default `false` applies), so received datasets inherit
  `mountpoint=none`, `canmount=off` and `devices=off` from
  `zbackup/backup/<host>` rather than carrying the source's `/` or
  `/home` mountpoint across. That failure mode is not present.
- **Proposed fix:** add `setuid = "off"` and `exec = "off"` to
  `zdata`'s and `zbackup`'s `rootFsOptions` (not `zroot` — the system
  needs both). Belt and braces: add
  `mountOptions = [ "nosuid" "nodev" "noexec" ]` to the
  `storage/storage` and `storage/storage-bulk` datasets, which disko's
  `zfs_fs` type supports and which flows straight into `fileSystems`.
- **Fix risk:** `exec = "off"` on `/storage` breaks anything that runs
  a script or binary from the media tree — check for helper scripts
  before applying. On `zbackup` these are properties on an existing
  pool, so they can be set live with `zfs set` and only affect future
  mounts; on `zdata` a `noexec` remount is immediate and will surface
  any hidden dependency straight away, which is arguably the point.

### F-P3-15 — `allowSFTP = true` with no identified consumer

- **File:** `hosts/homelab/configuration.nix:356`
- **Severity:** LOW
- **Confidence:** CONFIRMED that the subsystem is enabled and that
  nothing in the repo uses it; PLAUSIBLE that nothing uses it in
  practice, which is a behavioural question.
- **Axis:** needed-used
- **Reachability:** A5 — a tailnet device with the admin key. It grants
  no privilege the same key does not already have via a shell, so this
  is attack surface, not escalation.
- **Rule:** **violates an existing `docs/hardening.md` rule** — "SSH:
  … `allowSFTP = false` unless actually used."
- **Finding:** the generated `sshd_config` carries
  `Subsystem sftp …/libexec/sftp-server`, confirmed present in the
  effective config dumped by the pinned `sshd -T`. Searching the repo
  for a consumer turns up nothing: zrepl uses `ssh+stdinserver`,
  push-deploy uses `nix-copy-closure`/`nix-store --serve` over plain
  ssh, factorio's mod sync uses local `rsync`, and nothing invokes
  `sftp` or `scp` against homelab.

  The caveat that keeps this from being a clean cut: OpenSSH 9.0+
  (10.4p1 here) made `scp` use the SFTP protocol by default. If the
  admin ever `scp`s a file to or from homelab interactively, this is
  load-bearing and turning it off will break that with a confusing
  error. That is not answerable from the config.
- **Proposed fix:** decision required, and it is a one-question
  decision: *do you ever `scp` or `sftp` to homelab?* If no,
  `allowSFTP = false;`. If yes, either leave it and add a comment
  saying so (which converts a rule violation into a recorded
  exception), or set it false and use `scp -O` (legacy protocol) or
  `rsync` on the rare occasions it is needed.
- **Fix risk:** the failure is immediate and obvious (`subsystem
  request failed on channel 0`), not silent. Safe to try.

### F-P3-16 — `sync = "disabled"` on `zroot` and `zbackup`

- **File:** `hosts/homelab/disko.nix:100,139,188`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** not adversarial — power loss, kernel panic, or the
  USB link dropping (the enclosure has a documented history of
  `uas_eh_abort_handler` faults, per `hosts/homelab/README.md`, now
  resolved).
- **Rule:** n/a.
- **Finding:** all three pools set `sync = "disabled"`, which tells ZFS
  to ignore `fsync()` and O_SYNC entirely. ZFS stays internally
  consistent — this is not the "corrupt pool" scenario — but up to one
  transaction group (~5 s) of *acknowledged* writes is lost on an
  unclean shutdown, and applications that fsync'd are lied to.

  On `zdata` that is a reasonable performance trade for a media
  library. On `zroot` it means `/nix/state` — every persisted
  `/var/lib`, the tailscale node state, the restic `last-success`
  marker — can silently roll back a few seconds. On **`zbackup`** it
  applies to asset #1: the pool whose whole purpose is to be the copy
  that survives. A received snapshot that ZFS acknowledged may not be
  there after a crash, and the failure is silent — zrepl's cursor
  would simply re-send, so it is self-healing in the common case, but
  it makes "the backup completed" a weaker statement than it reads.
- **Proposed fix:** leave `zdata`. Consider `sync = "standard"` on
  `zbackup` and `zroot`, and measure — with no SLOG device the cost on
  the USB-attached mirror could be significant, which is presumably
  why it was set. If the performance cost is unacceptable, that is a
  fine answer; record it in `docs/backups.md` next to the F-P3-03
  wording, so "two copies" carries its caveats.
- **Fix risk:** a real throughput regression on `zbackup`, on a link
  that was a bottleneck until the 2026-08-23 cable change. Measure a
  full replication cycle before and after; the README documents how to
  confirm the link is still at 5000 Mbps.

### F-P3-17 — all DNS is plaintext and unvalidated, sent to Google and Cloudflare

- **File:** `hosts/homelab/configuration.nix:70-76`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A4 — an on-path LAN device can observe and forge
  every name homelab resolves. This is the enabling half of F-P3-05.
- **Rule:** new-rule candidate.
- **Finding:** `networking.networkmanager.insertNameservers =
  [ "8.8.8.8" "1.1.1.1" ]` *prepends* those servers, and
  `config.services.resolved.settings` resolves to
  `{ Resolve = { DNS = ["8.8.8.8" "1.1.1.1"]; DNSOverTLS = false;
  DNSSEC = false; Domains = []; }; }`. So every lookup that is not
  captured by a tailscale MagicDNS routing domain — including
  `github.com` on the deploy path, the Backblaze endpoint, the Docker
  registry and the LVFS firmware metadata host — goes out in
  cleartext, unauthenticated, over the LAN.

  Secondary: prepending global servers is a blunt instrument next to
  tailscale's own resolved configuration, and is the sort of thing that
  quietly changes how `vps` resolves. That matters for F-P3-05's second
  leg.
- **Proposed fix:** set `DNSOverTLS = "true"` and `DNSSEC = "allow-downgrade"`
  (or `"true"`, which is stricter and occasionally breaks) in
  `services.resolved.settings.Resolve`. Better still, question whether
  `insertNameservers` is needed at all — it predates tailscale here,
  and tailscale's DNS plus the LAN router's resolver may cover it.
  Whatever is chosen, it should be consistent with F-P3-05's host-key
  pinning: pinning removes the need to trust DNS for the SSH hops,
  which is the higher-value half.
- **Fix risk:** DoT to 8.8.8.8/1.1.1.1 fails closed if the network
  blocks 853/tcp, which takes the whole host offline for name
  resolution — including the deploy path. `DNSSEC = "true"` breaks on
  misconfigured zones. Test with `resolvectl query` before switching,
  and prefer `allow-downgrade` on the first pass.

### F-P3-18 — two of the nine sshd `extraConfig` directives are completely inert (§7.2), and one has a syntax oddity

- **File:** `hosts/homelab/configuration.nix:376-386`
- **Severity:** INFO
- **Confidence:** CONFIRMED — verified by running the pinned
  `openssh-10.4p1` `sshd -T` against the generated config and against
  mutated copies.
- **Axis:** documentation / hardening
- **Reachability:** none today. The trap is prospective.
- **Rule:** the block is the repo's implementation of
  `docs/hardening.md`'s SSH rule; seven of nine directives do
  implement it.
- **Finding:** the pinned module builds `sshd_config` as
  `cat ${settings-derived-file} - <<EOL ${extraConfig} EOL`
  (`sshd.nix:80-86`), so the structured `settings` block is emitted
  **first** and, since sshd_config is first-directive-wins, beats
  anything repeated in `extraConfig`. This is the identical mechanism
  that made `PasswordAuthentication` inert, as the comment at `:368-375`
  records.

  Running `sshd -T` on the generated file and on a copy with the
  extraConfig lines flipped to `yes` gives the definitive answer:

  | Directive (`extraConfig` line) | Emitted by `settings`? | In force? |
  |---|---|---|
  | `PermitRootLogin = prohibit-password` (:377) | **yes** (`PermitRootLogin prohibit-password`) | **NO — inert.** Setting it to `yes` changes nothing; effective value stays `prohibit-password` |
  | `AllowTcpForwarding no` (:378) | no | yes |
  | `X11Forwarding no` (:379) | **yes** (`X11Forwarding no`) | **NO — inert.** Setting it to `yes` changes nothing; effective value stays `no` |
  | `AllowAgentForwarding no` (:380) | no | yes |
  | `AllowStreamLocalForwarding no` (:381) | no | yes |
  | `AuthenticationMethods publickey` (:382) | no | yes |
  | `PermitTunnel no` (:383) | no | yes |
  | `ClientAliveInterval 60` (:384) | no | yes |
  | `ClientAliveCountMax 5` (:385) | no | yes |

  So the security posture today is correct — both inert lines happen to
  duplicate the value the module already emits, so nothing is weaker
  than it looks. The finding is that two of them are decorative, and a
  future edit to either would silently do nothing, which is precisely
  the mistake this host already made once.

  Separately, line 377 is written `PermitRootLogin = prohibit-password`
  with a stray `=`. OpenSSH's `strdelim()` treats `=` as a token
  delimiter, so it parses fine (confirmed — `sshd -T` accepts the file
  with no error), but it is not sshd_config style and it is the only
  line in the block written that way.
- **Proposed fix:** move both inert directives to where they take
  effect and delete them from `extraConfig`:
  `settings.PermitRootLogin = "prohibit-password";` and
  `settings.X11Forwarding = false;` (both already the effective
  values, so this is a no-op change to behaviour and a real change to
  clarity). Leave the other seven in `extraConfig` — the module has no
  structured option for them — and add a one-line comment above the
  block noting that anything with a `settings.*` equivalent must go
  there instead, so the next person does not re-add one.
- **Fix risk:** none; the effective config is byte-comparable before
  and after via `sshd -T`, which is how this was verified in the first
  place.
- **Owner:** P3; P5 should apply the same table to vps and the
  laptops (§7.2 explicitly asks for it).

### F-P3-19 — `services.networkd-dispatcher` can never fire on this host

- **File:** `hosts/homelab/configuration.nix:27-36`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** none. Listed because an enabled root daemon with
  no consumer is attack surface nobody is thinking about (§7.4).
- **Rule:** n/a.
- **Finding:** the rule is fine on its own terms — the script lives in
  the Nix store (`writeShellApplication` symlinked into a
  `runCommand` script dir, per the pinned module), so it is
  root-owned, immutable and `0555`; there is no writable script
  directory to hijack. The problem is that it never runs.

  `networkd-dispatcher` is, as its unit description says, the
  "Dispatcher daemon for **systemd-networkd**". Its only trigger is
  `bus.add_signal_receiver(bus_name='org.freedesktop.network1')` —
  read directly in the packaged Python. homelab's network stack is
  NetworkManager (`:70-76`) and `config.systemd.network.enable` is
  `false`, so nothing ever owns `org.freedesktop.network1` and no
  signal is ever delivered. The daemon starts, registers, and idles
  forever.

  Functionally that means the tailscale UDP-GRO-forwarding ethtool
  tweak on `enp3s0` has never been applied — a throughput matter, not a
  security one, but worth knowing given homelab is the exit node and
  subnet router. Security-wise it leaves an unsandboxed root Python
  process running for no reason (the upstream unit has no
  `NoNewPrivileges`, no `Protect*`, nothing).
- **Proposed fix:** replace with something that actually fires under
  NetworkManager. Either a `dispatcher.d` script via
  `networking.networkmanager.dispatcherScripts`, or — simpler and
  order-independent — a `systemd.services` oneshot bound to
  `network-online.target` plus a `udev` rule on the interface, or the
  `ExecStartPost` of `tailscaled` itself. Then drop
  `services.networkd-dispatcher` entirely.
- **Fix risk:** the tweak is a performance optimisation, so getting the
  replacement wrong is invisible. Verify with
  `ethtool -k enp3s0 | grep -E 'rx-udp-gro-forwarding|rx-gro-list'`
  after a reboot, which is also how to confirm the current claim
  (expect `off`/`on`, i.e. the tweak *not* applied, today).

### F-P3-20 — the explicit forwarding sysctls are redundant with what the tailscale module already forces

- **File:** `hosts/homelab/configuration.nix:404-408`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** none.
- **Rule:** adjacent to `docs/hardening.md`'s "Tailscale forwarding
  sysctls" rule, from the other direction.
- **Finding:** the merged `boot.kernel.sysctl` contains both the
  hand-written `net.ipv4.ip_forward = 1` / `net.ipv6.conf.all.forwarding
  = 1` and the tailscale module's own
  `net.ipv4.conf.all.forwarding = true`,
  `net.ipv4.conf.default.forwarding = true`,
  `net.ipv6.conf.all.forwarding = true`. `net.ipv4.ip_forward` and
  `net.ipv4.conf.all.forwarding` are the same kernel knob. Since
  `useRoutingFeatures = "both"` is in effect (correctly — see
  F-P3-09), the tailscale module is already forcing all of this at a
  priority a plain assignment cannot beat, which is exactly what the
  hardening rule warns about.

  So `:405-408` does nothing that is not already done. It is not
  harmful, but it is the kind of duplicate that makes a future reader
  think forwarding is controlled here when it is controlled elsewhere.
- **Proposed fix:** delete `:405-408` and extend the comment at `:404`
  to say that `useRoutingFeatures = "both"` is what enables forwarding.
  Do this **in the same change** as F-P0-06's default inversion, not
  before — if the shared default flips to `"client"` first and this
  block is already gone, homelab silently stops routing.
- **Fix risk:** exactly the ordering hazard above. `sysctl -a | grep
  forwarding` after switching is the check.

### F-P3-21 — `rpcbind` and the NFSv3 helpers listen with no firewall allowance anywhere

- **File:** `hosts/homelab/configuration.nix:394` (the only
  interface rule homelab writes itself); `modules/services/nfs.nix`
  (P4's) is what enables the server
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** none currently — every path to them is closed.
- **Rule:** n/a.
- **Finding:** `config.services.rpcbind.enable` is `true` (pulled in by
  the NFS server module), so `rpcbind` binds 111/tcp and 111/udp on
  `0.0.0.0` and `[::]`, and `rpc.mountd`/`rpc.statd`/`lockd` bind
  ephemeral ports (`mountdPort`, `statdPort`, `lockdPort` are all
  `null`). None of these appears in any `allowedTCPPorts` or
  `allowedUDPPorts`, host-wide or per-interface — only 2049 on
  `tailscale0` is open. So they are unreachable, including on the
  public IPv6 address.

  They are also unnecessary: the export list is NFSv4-shaped
  (`/storage 100.64.0.0/10(rw,sync,no_subtree_check,root_squash)`) and
  NFSv4 needs neither rpcbind nor the v3 helpers. Under §4.7 the
  presence of a listener that is only saved by a firewall rule is worth
  recording even when the firewall is correct — because the inventory
  is public, and because the next person to add an interface rule needs
  to know these are sitting there.
- **Proposed fix:** P4's call, in `nfs.nix`: disable NFSv3
  (`services.nfs.server.extraNfsdConfig = "vers3=n"` or the equivalent
  in the pinned module) and let `rpcbind` go away with it. No change
  needed on homelab's side.
- **Fix risk:** any NFSv3 client breaks. The homelab mounts module
  (`modules/nixos/nfs-homelab-mounts.nix`) is the consumer to check.
- **Owner:** P4.

### F-P3-22 — the commented-out root password line is dead config

- **File:** `hosts/homelab/configuration.nix:272-273`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** none.
- **Rule:** n/a.
- **Finding:** `users.mutableUsers = false` (`:272`) with
  `users.users.root.hashedPassword` left `null` already produces a
  locked account: the pinned `update-users-groups.pl:299` does
  `$sp_pwdp = "!" if !$spec->{mutableUsers}`. So the commented-out
  `#users.users.root.hashedPassword = "!";` on the next line would be a
  no-op even if uncommented. It reads as an unfinished thought about
  something that is already true.

  Related and clean, recorded here so it is not re-litigated: console
  access is reasonably constrained — root's password is `!`,
  `systemd.enableEmergencyMode = false` (`:269`), and
  `boot.loader.systemd-boot.editor = false` (from
  `modules/profiles/default.nix:197`) blocks the
  `init=/bin/sh` route. What is *not* constrained is booting other
  media or removing the drives, which is F-P3-08's territory.
- **Proposed fix:** delete line 273, or replace it with a comment
  saying root is locked by `mutableUsers = false` — the latter is
  probably more useful to the next reader.
- **Fix risk:** none.

### F-P3-23 — `services.fwupd` pulls `udisks2` onto a headless server and runs a weekly LVFS fetch

- **File:** `modules/profiles/default.nix:101` (the enable),
  visible on homelab as `config.services.udisks2.enable == true` and
  a `fwupd-refresh` timer
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** A2 in principle — `fwupd-refresh` fetches metadata
  from LVFS over the network on a timer, and DNS for that fetch is
  plaintext (F-P3-17). udisks2 is a root D-Bus service reachable by
  local principals via polkit.
- **Rule:** n/a; §7.4.
- **Finding:** `services.fwupd.enable = true` in the shared default
  profile sets `services.udisks2.enable = true` (pinned
  `nixos/modules/services/hardware/fwupd.nix:200`), whose own default
  is `false`. On homelab that means a root storage-management daemon
  with an auto-mount role, plus a weekly outbound metadata fetch, on a
  box with no operator present, no removable media workflow, and a
  firmware-update story that nobody is going to execute unattended
  anyway. `polkit.extraConfig` also carries an fwupd-specific rule
  (`get-remotes`/`refresh-remote` for the `fwupd-refresh` user).

  It is not a homelab decision — the enable is in the shared profile —
  but the *consequence* only matters on the server-class hosts, so it
  is recorded here for whoever owns that file.
- **Proposed fix:** P1's call. Options: move `services.fwupd.enable`
  from `profiles/default.nix` to `profiles/PC.nix` where an operator
  actually exists; or keep it and set `services.udisks2.enable =
  lib.mkForce false` on the server profile (fwupd degrades gracefully
  without it, losing only removable-media firmware). Either way the
  server profile is the right place for the override, not homelab's
  own config.
- **Fix risk:** low; fwupd's `get-devices` may report fewer devices.
- **Owner:** P1.

### F-P3-24 — `smartd` runs on homelab with only wall/X11/D-Bus notifications, none of which anyone will see

- **File:** `modules/profiles/default.nix:104-113`; homelab-visible as
  `services.smartd.enable == true` with `devices = []` (autodetect)
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** none — this is an observability gap, not an
  exposure.
- **Rule:** n/a.
- **Finding:** the shared profile enables `smartd` with
  `notifications = { systembus-notify, wall, x11 }`. homelab is
  headless with no logged-in session and no X server
  (`services.xserver.enable == false`), so all three sinks discard
  everything: `wall` writes to ttys nobody reads, `x11` has no
  display, `systembus-notify` needs a desktop session. A failing drive
  produces a journal line and nothing else.

  This is not a hole, because `myHealthAlerts` does the job that
  matters — it runs its own SMART check every 15 minutes and pushes to
  Discord (which is what the `disk` group in F-P3-02 is for). The
  finding is that smartd is then a second, silent SMART poller doing
  the same reads, and vps already recognised the pattern by forcing it
  off (`hosts/vps/configuration.nix:740-741`, for a different reason).
- **Proposed fix:** either give smartd a working sink on server hosts,
  or disable it there and let `myHealthAlerts` own SMART outright. The
  latter is simpler and matches what already happens in practice.
- **Fix risk:** none if disabled — `myHealthAlerts` already polls SMART
  every 15 minutes and is the only path that reaches a human. Confirm
  the next Discord alert still enumerates all five drives before
  removing the second poller.
- **Owner:** P1 for the profile; P3 confirms it is redundant on homelab.

---

## 3. Listening services and firewall rules

All values from the evaluated configuration
(`config.networking.firewall` built in full;
`config.virtualisation.oci-containers.containers.*.ports`;
`config.systemd.sockets`), corroborated for the docker-published ports
by the coordinator's live `iptables`/`ip6tables`/`ss` capture of
2026-08-26 (see F-P3-04 and P4's F-P4-02). Interface names: `enp3s0` is
the LAN NIC — **private IPv4 behind CGNAT *and* three globally-routable
ISP-RA-delegated IPv6 addresses** (§2.1, count confirmed live);
`tailscale0` is the tailnet; `wg0` is the point-to-point tunnel to vps
(`10.100.0.2/24`, peer `10.100.0.1`).

### 3.0 Read this table with three categories, not two

A NixOS firewall rule is not evidence that a port is filtered. On this
host every listener falls into one of three classes, and conflating
them is what makes homelab's posture look better than it is:

- **(a) Filtered.** A native service whose traffic arrives on `INPUT`
  and therefore traverses `nixos-fw`. The
  `networking.firewall.interfaces.<iface>` rule is the real control.
  sshd, jellyfin, nfsd, smbd.
- **(b) Decorative.** A docker-published port. Docker DNATs it in the
  `nat` table and delivers it via `FORWARD`; it never reaches `INPUT`,
  and `filterForward = false` means NixOS manages neither chain. The
  interface-scoped rules exist, are correctly written, and **constrain
  nothing**. All four game ports.
- **(c) Unruled but unreachable.** A listener with no allow rule
  anywhere, closed by the default-deny in `nixos-fw`. `rpcbind`, the
  NFSv3 helpers, `tailscaled`'s 41641.

The distinction matters most where it is least visible: **"binds
`0.0.0.0`" means completely different things in (a) and (b)**. jellyfin
binds `0.0.0.0:8096` and is nonetheless genuinely constrained to
`tailscale0` and `wg0`, because its packets go through `INPUT`. The
game servers also bind `0.0.0.0` and are not constrained at all. The
bind address is not the discriminator; the packet path is.

### 3.1 Firewall, as evaluated

| Setting | Value | Note |
|---|---|---|
| `enable` | `true` | |
| `backend` | `iptables` | |
| `allowedTCPPorts` (host-wide) | **`[ ]`** | genuinely empty — nothing is exposed on the public IPv6 by the packet filter |
| `allowedUDPPorts` (host-wide) | **`[ ]`** | " |
| `allowedTCPPortRanges` / `allowedUDPPortRanges` | `[ ]` / `[ ]` | |
| `trustedInterfaces` | `[ "lo" ]` | **notably not `tailscale0`** — homelab does not repeat vps's blanket-trust pattern (§4.4) |
| `interfaces.tailscale0.allowedTCPPorts` | `22, 445, 2049, 8096, 25565` | sshd, samba, nfsd, jellyfin, minecraft |
| `interfaces.tailscale0.allowedUDPPorts` | `19132, 25565, 34197, 34198` | bedrock/geyser, minecraft, factorio ×2 |
| `interfaces.wg0.allowedTCPPorts` | `8096, 25565` | jellyfin (via caddy/anubis), minecraft |
| `interfaces.wg0.allowedUDPPorts` | `19132, 25565, 34197, 34198` | the DNAT'd game ports from vps |
| `filterForward` | `false` | NixOS installs no `FORWARD` rules; **docker owns that chain** — see F-P3-04 |
| `checkReversePath` | `"loose"` | set by the tailscale module; required for it |
| `logRefusedConnections` | `false` | nixpkgs default; vps sets `true`. See F-P3-10 |
| `logRefusedPackets` / `logRefusedUnicastsOnly` | `false` / `true` | |
| `rejectPackets` | `false` | drop, not reject |
| `allowPing` | `true`, no `pingLimit` | |
| `extraCommands` | only NixOS's own nat-chain teardown | **no `DOCKER-USER` rules** |
| `extraInputRules` / `extraForwardRules` | `""` / `""` | |

### 3.2 Listening services

| Service | Port / socket | Binds | Class | NixOS rule | Effectively reachable from | Owner |
|---|---|---|---|---|---|---|
| `sshd` | 22/tcp | `0.0.0.0` + `[::]` (`AddressFamily any`, no `ListenAddress`) | **(a) filtered** | `interfaces.tailscale0` | tailnet only | P3 |
| `jellyfin` | 8096/tcp | `0.0.0.0` — **irrelevant, traffic traverses `nixos-fw`** | **(a) filtered** | `interfaces.tailscale0` + `interfaces.wg0` | tailnet; internet via vps:443 → caddy → anubis → wg0 | P4 |
| `nfsd` | 2049/tcp | all | **(a) filtered** | `interfaces.tailscale0` | tailnet (exports further limited to `100.64.0.0/10`, `root_squash`) | P4 |
| `smbd` | 445/tcp | all | **(a) filtered** | `interfaces.tailscale0` | tailnet (`hosts allow 100.64.0.0/10`, `hosts deny 0.0.0.0/0`, SMB3 + mandatory signing and encryption, `invalid users = root`) | P4 |
| `minecraft-vanilla-plus` (docker) | 25565/tcp, 19132/udp | dockerd on `0.0.0.0`; **not** on `::` | **(b) DECORATIVE** — `nat` DNAT → `FORWARD`, never reaches `INPUT` | rules exist on tailscale0 + wg0 and **constrain nothing** | tailnet, wg0/internet (intended), **and every LAN IPv4 host** (A4) | P4 (F-P4-02) / P3 (F-P3-04) |
| `factorio-main` (docker) | 34197/udp | dockerd on `0.0.0.0`; not on `::` | **(b) DECORATIVE** | as above | as above | P4 / P3 |
| `factorio-new` (docker) | 34198/udp | dockerd on `0.0.0.0`; not on `::` | **(b) DECORATIVE** | as above | as above | P4 / P3 |
| `rpcbind` | 111/tcp + 111/udp | `0.0.0.0` + `[::]` | **(c) unruled, closed** | none | nothing — and unnecessary for NFSv4 (F-P3-21) | P4 |
| `rpc.mountd` / `rpc.statd` / `lockd` | ephemeral (`*Port = null`) | all | **(c) unruled, closed** | none | nothing | P4 |
| `tailscaled` | 41641/udp (`PORT=41641`) | all | **(c) unruled, closed** | none; works via NAT traversal / DERP | outbound-established only | P1 |
| `wireguard wg0` | no `listenPort` → ephemeral source port | — | outbound only, to `137.184.45.18:51820` | n/a | vps only; homelab always initiates (CGNAT) | P3 |
| `systemd-resolved` stub | `127.0.0.53:53` | loopback | loopback | `trustedInterfaces = [ "lo" ]` | local only | P1 |
| `docker.sock` | unix `/run/docker.sock` | — | unix | `0660 root:docker` | **root only** — `users.groups.docker.members` is empty on homelab, so no A7 path (unlike the laptops, §4.3) | P3 |
| `zrepl` | none | — | — | — | no inbound listener at all: pull jobs dial out over `ssh+stdinserver`, local replication uses the in-process `local` transport | P6 |
| `avahi` | disabled | — | — | — | — | — |

Three things this table is meant to make hard to forget:

- **Nothing on homelab is currently exposed on its public IPv6.** The
  host-wide `allowedTCPPorts`/`allowedUDPPorts` are empty, so every
  class-(a) and class-(c) listener that binds `::` (sshd and rpcbind,
  from `AddressFamily any` and rpcbind's default) is closed by
  `nixos-fw`'s default deny; and the live capture confirms
  `ip6tables -t nat -S` has no DNAT rules for the game ports and that
  none of the four binds `::`. §2.1's trap is shut today. F-P3-04 is
  about the fact that the class-(b) half of that is shut by a Docker
  default nobody wrote down, not by anything in this repo.
- **Ten correctly written firewall rules do nothing.** The rules the
  audit plan called the reference standard are real, are scoped to
  `tailscale0`/`wg0`, and are bypassed. That is worth internalising
  before reading any other host's firewall table: presence of a rule is
  not evidence of filtering, the packet path is.
- **`wg0` is not a private interface.** It is the path the open
  internet takes to the game servers via vps's DNAT. Any rule scoped to
  `wg0` should be read as "internet, one NAT hop away", never as
  "trusted".

---

## 4. Checked and clean

Examined and found correct — recorded so the next pass does not
re-derive it, and so a later regression is visible as a change.

**Firewall and exposure**

- Host-wide `allowedTCPPorts`/`allowedUDPPorts` are both genuinely
  empty. The §2.1 trap is closed for everything the packet filter
  governs.
- `trustedInterfaces = [ "lo" ]`. homelab does **not** blanket-trust
  `tailscale0` the way vps does (§4.4); it opens named ports. This is
  the better pattern and should not be "simplified" later.
- sshd's `openFirewall = false` plus the explicit
  `interfaces.tailscale0.allowedTCPPorts = [ 22 ]` (`:366`, `:394`) is
  exactly the fix pattern §2.2 describes, and the comment at `:357-365`
  documents why.

**SSH**

- Seven of the nine `extraConfig` hardening directives are in force,
  verified by running the pinned `sshd -T`: `AllowTcpForwarding no`,
  `AllowAgentForwarding no`, `AllowStreamLocalForwarding no`,
  `AuthenticationMethods publickey`, `PermitTunnel no`,
  `ClientAliveInterval 60`, `ClientAliveCountMax 5`. The other two are
  F-P3-18 and are inert-but-harmless.
- `settings.PasswordAuthentication = false` and
  `settings.KbdInteractiveAuthentication = false` are set structurally
  and appear in the effective config — the §7.2 bug is genuinely fixed
  here.
- `hostKeys` is ed25519 only; no RSA or ECDSA key is generated.
- Ciphers, KexAlgorithms and Macs are the nixpkgs hardened defaults
  (chacha20-poly1305 / AES-GCM, mlkem768x25519 and sntrup761x25519
  post-quantum KEX first, ETM MACs only).
- Root's `authorizedKeys` is exactly `vars.publicSshKeys` — three keys,
  one of them a FIDO2 `sk-ssh-ed25519`. No stray keys.
- `programs.ssh.knownHosts` pins torrent and thinkpad declaratively,
  with a good comment explaining why that beats `accept-new`. The gap
  is that it stops there (F-P3-05).

**Users and privilege**

- No `lilijoy` account on homelab; no interactive users at all. Root's
  password is `!` (locked) via `mutableUsers = false`.
- The `docker` group has **no members** — the root-equivalence noted in
  §4.3 for the laptops does not apply here.
- `wheel` has no members. `security.sudo.enable = false`;
  `security.run0.wheelNeedsPassword = true`.
- `nix.settings.allowed-users` and `trusted-users` are both
  `[ "root" ]`; `require-sigs = true`; `sandbox = true`.
- Dedicated service users throughout: `jellyfin`, `android-smb`,
  `octodns`, `health-check`, `fwupd-refresh`. All `isSystemUser` with
  `nologin` shells. The one over-broad group grant is F-P3-02.
- `octodns-sync` is properly sandboxed (`NoNewPrivileges`,
  `ProtectSystem = "strict"`, `ProtectHome`, `ProtectKernel*`,
  `ProtectControlGroups`, `RestrictNamespaces`, `PrivateTmp`) and its
  Cloudflare token is delivered by `sops.templates` as an
  `EnvironmentFile` owned `octodns:octodns` `0400`. The secret **is**
  legitimately used on homelab — octodns is in homelab's module list in
  `modules/flake/hosts.nix:67`.
- No `DynamicUser = true` service anywhere on homelab, so the
  `StateDirectory`/impermanence symlink hazard in `docs/hardening.md`
  does not apply here.

**Secrets plumbing** (contents never read)

- Every `sops.secrets` entry resolves to mode `0400` under
  `/run/secrets` (tmpfs). Only `homelab_discord_webhook` sets a
  non-root owner (`health-check:health-check`), which matches its
  single consumer.
- `homelab_samba_android_smb_password` correctly declares
  `restartUnits = [ "samba-user-provision.service" ]`.
- Every declared secret has an identified consumer — no orphans. The
  `cloudflare_octodns_token`, which looked like a candidate, is used.
- The age key material and its storage are F-P3-01; the plumbing
  itself is fine.

**Backups and ZFS**

- The pull-not-push design (`:185-203`) is correct and is the thing
  that keeps retention authority on homelab (§4.5). Do not regress it.
- `boot.zfs.extraPools = [ "zbackup" ]` (`:183`) fixes a real
  23-hour outage and the comment records exactly why nixpkgs did not
  generate the import unit on its own.
- `devices = "off"` on all three pools — a real control against device
  nodes in received root filesystems. Its missing siblings are F-P3-14.
- zrepl transmits no ZFS properties, so received datasets inherit
  `mountpoint = none` / `canmount = off` / `devices = off` from
  `zbackup/backup/<host>` rather than carrying the source's mountpoint
  across. The "received dataset tries to mount over `/`" failure mode
  is not present.
- `services.zfs.autoScrub.enable` and `trim.enable` are on.
- `myHealthAlerts.backupStaleness` covers all seven replication targets
  with thresholds that match each source's realistic uptime, and
  `staleMarkerFiles` covers the restic run with a documented 14-day
  budget. The `Persistent = false` reasoning on the restic timer
  (`:128-137`) is sound and well-explained.
- `restic-backups-backblazeWeekly` carries `NoNewPrivileges = true`,
  `CacheDirectory` at mode `0700`, and `PrivateTmp = false` for the
  documented functional reason `docs/hardening.md` describes. The
  directory *choice* is F-P3-13; the sandbox exception itself is
  correct.

**Deploy path**

- `myAutoUpdate` and `myPushDeploy` both operate on `/etc/nixos`,
  which is persisted **root-owned, mode `0755 root:root`**. homelab
  therefore does **not** have F-P0-03's "root builds from a
  user-writable checkout" problem — that finding is laptop-specific.
- `auto-switch` and `push-deploy-vps` carry `NoNewPrivileges = true`
  and no further sandboxing, which is exactly what
  `docs/hardening.md` prescribes for activation units.
- `protectedUnits = [ "restic-backups-backblazeWeekly.service" ]`
  (`:289`) correctly stops a same-cycle switch from killing a
  multi-day backup — a §7.3-class problem that was anticipated.
- `systemd.services.auto-switch.onSuccess = [ "push-deploy-vps.service" ]`
  (`:312`) reuses the already-vetted master checkout rather than
  racing a second fetch.

**Boot and kernel**

- `boot.loader.systemd-boot.editor = false`, so the console
  `init=/bin/sh` route is closed; `systemd.enableEmergencyMode = false`
  closes the failed-mount shell.
- `hardware.cpu.intel.updateMicrocode = true` — set explicitly at
  `:47` on top of `hardware-configuration.nix:33`'s conditional
  `mkDefault`, which is the more robust of the two.
- `nohibernate` is in `kernelParams` (from the ZFS module), so the
  disk-swap risk in F-P3-06 is paging only, not a hibernation image.
- `audit=1` with `audit_backlog_limit=1024`, `security.auditd.enable`
  and an `execve` audit rule from `profiles/server.nix` — **and
  `/var/log` is in the persist list**, which is the exact pairing
  `docs/hardening.md` warns about and it is done correctly.
- `kernel.kptr_restrict = 1`, `lsm=landlock,yama,bpf`.
  `security.protectKernelImage` is `false` (nixpkgs default in this
  pin), so `kernel.kexec_load_disabled` is unset — a root-only
  defence-in-depth gap, noted rather than filed.
- The initrd `rollback` service is correctly ordered
  (`after = zfs-import-zroot`, `before = sysroot.mount`,
  `DefaultDependencies = no`), and `/nix` and `/nix/state` are both
  `neededForBoot = true`.

**Impermanence persist list**

Every entry is justified and every security-relevant item is present:
`/var/log` (audit trail — required), `/etc/ssh/ssh_host_ed25519_key`
and `.pub` (host identity and the sops age key), `/etc/machine-id`,
`/var/lib/tailscale` (node identity — without it the non-reusable auth
key is consumed once and fails every boot after, as the comment
records), `/var/lib/nixos` (uid/gid stability), `/var/lib/docker`,
`/var/lib/systemd/timers`, `/var/lib/health-alerts`,
`/var/lib/restic-backups-backblazeWeekly` (the staleness marker),
`/etc/nixos`, `/var/lib/samba`, and the `/srv/*` service directories.
Nothing is persisted that need not be. The zrepl comment
(`:483-485`) correctly explains why no zrepl state directory is
needed — cursors, holds and bookmarks live in ZFS itself.

The one gap is `/root/.ssh/known_hosts`, and the right fix for that is
declarative pinning rather than persistence — F-P3-05.

**GPU / hardware**

- The NVIDIA driver is **not** dead config: `jellyfin.nix:18-38`
  configures NVENC on `/dev/dri/renderD128` as the primary transcoder,
  with the Intel iGPU's `renderD129` as the QSV/VAAPI fallback. Both
  `hardware.graphics.extraPackages` entries and
  `services.xserver.videoDrivers = [ "nvidia" ]` are load-bearing.
  `nvidiaSettings = false` and `open = false` are both correct for a
  headless GP107.
- The disk serial numbers in `disko.nix` are inherent to `by-id`
  device paths and are accepted as public (§4.7) rather than treated as
  a finding.

---

## 5. Notes for other parts

- **P4** — F-P4-02 accepted and not duplicated; §3 of this report
  carries the three-class firewall table it implies, and F-P3-04 keeps
  only the residue that is homelab's: the undocumented dependency on
  Docker's IPv6 default, and the host-level `DOCKER-USER` remediation.
  Present-day severity is LAN-wide (A4), not internet-wide — no public
  IPv4, no IPv6 DNAT rules. Separately for you: `jellyfin`'s membership
  in `multimedia` gives it write and delete over the whole media tree
  (F-P3-07), and NFSv3/`rpcbind` is enabled but unused (F-P3-21).
- **P5** — the sshd `extraConfig` precedence table in F-P3-18 was
  derived by running the pinned `sshd -T`; the same method applies
  verbatim to vps and the laptops, and §7.2 asks for it.
- **P6** — zrepl sends no ZFS properties, so the received-mountpoint
  hazard is absent; `devices = off` is inherited from the pool root.
  The `sync = "disabled"` on `zbackup` (F-P3-16) is worth your view on
  whether it weakens "the replication completed".
- **P7** — `push-deploy.nix:114` and `deploy-guards.nix:43` both use
  `StrictHostKeyChecking=accept-new`; on homelab that is re-TOFU on
  *every* boot, not once, because the impermanence rollback wipes
  `/root/.ssh` (F-P3-05). F-P0-07's LOW rating was based on the
  once-only assumption.
- **P8** — F-P3-09 is the homelab half of §8.1 and §8.5: the subnet
  route and exit node are the mechanism by which a flat ACL becomes
  "the whole home LAN plus internet egress", and whether either is
  approved is console state Nix does not manage.
- **P1** — F-P0-06 confirmed from homelab's side: it genuinely needs
  `useRoutingFeatures = "both"`, so inverting the shared default to
  `"client"` is safe, provided F-P3-20's redundant sysctls are removed
  in the same change and not before. Also F-P3-23 (`fwupd` → `udisks2`
  on servers) and F-P3-24 (`smartd` with no reachable notification
  sink) are shared-profile calls.
