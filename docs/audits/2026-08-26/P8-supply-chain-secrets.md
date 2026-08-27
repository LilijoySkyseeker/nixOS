# P8 — supply chain, flake infrastructure, secrets plumbing, user environment

Phase 1, part 8 of the 2026-08-26 fleet-wide security audit. Severity
rubric, adversaries (A1–A9) and trust boundaries are
[`00-threat-model.md`](00-threat-model.md); the finding schema is
[`P0-findings.md`](P0-findings.md). This part owns the follow-up on
**F-P0-04** (flat tailnet ACL), **F-P0-05** (the ACL's inert `ssh`
block) and **F-P0-08** (public, permanent ciphertext), and independently
verifies and owns the remediation for **P6's F-P6-01** (the `.sops.yaml`
recipient set).

> **This report was revised mid-audit** after the repository was
> confirmed **public on GitHub** (threat model §4.7). That single fact
> is decisive for this part: sops/age encryption is the *only* control
> protecting `secrets/secrets.yaml`, there is no rate limit or network
> boundary in front of an offline attack, and **rotation is not
> retroactive**. Every finding below is rated on that basis. Two
> findings are CRITICAL as a result, one of which is a demonstrated,
> currently-live exposure rather than a structural risk.

---

## 1. Scope and method

### No secret was decrypted

**Explicit statement, per `docs/procedures/secrets.md`:** nothing in
this audit decrypted, edited, or read the plaintext of
`secrets/secrets.yaml`, of any of its 72 historical revisions, or of any
path under `/run/secrets`. No `sops -d`, no `sops edit`, no
`sops exec-env`, no `cat` of a decrypted path. `/run/secrets` was
`stat`-ed and its permissions read; no file under it was opened.
`/var/lib/sops-nix/key.txt` was `stat`-ed and never read.
`/home/lilijoy/.ssh/id_ed25519` was `stat`-ed; only its **public** half
was read.

`/home/lilijoy/.config/sops/age/keys.txt` was `stat`-ed, and a
**count-only** `grep -c '^AGE-SECRET-KEY-1'` was run against it, which
emits the integer `1` and no key material. That was the minimum needed
to establish the file is an age identity; its contents were not read and
its public half was therefore not derived (F-P8-03 stays PLAUSIBLE on
attribution as a direct result).

What *was* read from `secrets/secrets.yaml` and its history is material
that sops leaves in plaintext by design: top-level **key names**, the
`sops:` block's **recipient list**, `lastmodified`, `version`, and the
`ENC[AES256_GCM,...]` **ciphertext strings themselves**. Comparing
ciphertext strings across revisions (§F-P8-02) is a byte comparison of
already-public ciphertext and reveals nothing about plaintext beyond
"this value did or did not change".

`ssh-to-age` was run only against **public** SSH keys (`.pub` files,
`known_hosts` entries, and public keys already committed to this repo)
to map age recipients to hosts — a public-to-public transformation
involving no private material.

### Already verified by the coordinator, cited rather than re-run

Per threat model §4.7 and F-P0-08, a history scan was already performed:
all 72 revisions of `secrets/secrets.yaml` carry `ENC[AES256_GCM...]`
markers with no pre-sops plaintext era; no credential-shaped filename
was ever committed among the 202 files ever added; and a content scan of
all 5,109 history blobs for private keys, `tskey-` authkeys,
GitHub/AWS/Slack tokens, Discord webhooks, Cloudflare tokens and
WireGuard private keys returned exactly one match,
`modules/services/octodns.nix:142`'s `env/CLOUDFLARE_TOKEN` indirection
placeholder. **Not re-run here.** My history work is disjoint from it:
recipient-set evolution and ciphertext-identity comparison, neither of
which that scan covers.

### Files read in full

- `flake.nix`, `flake.lock` (via `nix flake metadata --json`)
- `modules/flake/`: `vars.nix`, `hosts.nix`, `systems.nix`, `pkgs.nix`,
  `checks.nix`, `devshell.nix` (`deploy-guards.nix` skipped — P7's)
- `modules/home-manager/`: `claude-code.nix`, `tmux.nix`, `tooling.nix`,
  `tooling-desktop.nix`, `virt-manager.nix`
- `modules/nixos/`: `tooling.nix`, `kde.nix`, `virtual-machines.nix`,
  `wooting.nix`
- `.sops.yaml` (current, plus all 16 historical revisions); every
  `sops.secrets.*` / `sops.templates.*` declaration repo-wide
- `docs/tailscale-acl.json`, `files/README.md` + directory listing
- `.githooks/{pre-commit,pre-push,commit-msg}`, `.envrc`, `.gitignore`
- `docs/hardening.md`, `docs/procedures/secrets.md`,
  `docs/procedures/remote-access.md`, `docs/architecture.md`, `AGENTS.md`
- Supporting reads in `modules/profiles/{default,PC,server}.nix`,
  `modules/services/{octodns,factorio,minecraft,samba}.nix`,
  `hosts/{homelab,vps,isoimage}/configuration.nix` — the sections that
  declare or consume a secret, set a `nix.settings` trust knob, or ship
  a udev rule.

### Claims verified by evaluation (effective merged values)

`nix eval --json .#nixosConfigurations.<host>.config.<option>` for all
five hosts: `sops.secrets` (full attrset with mode/owner/group/path/
neededForUsers/restartUnits), `sops.age`, `nix.settings`,
`services.tailscale.{enable,extraUpFlags,useRoutingFeatures,authKeyFile,
permitCertUid}` (individually — the whole attrset throws on the
unrelated `derper.domain`), `security.wrappers`,
`networking.firewall.{trustedInterfaces,allowedTCPPorts,allowedUDPPorts,
interfaces}`, `services.udev.{packages,extraRules}`,
`hardware.keyboard.qmk.enable`. `isoimage` has **no `sops` option at
all** — the eval fails with "does not provide attribute", which is
itself the confirmation that it never imports sops-nix.

### Claims verified against the pinned nixpkgs

Pinned unstable resolves to
`/nix/store/09g0q2nr523x5inkal66127xmq2z8gw0-…-source`
(`nixos-26.11pre1053317.0e251e24a4f2`). Read directly from it:
`nixos/modules/hardware/wooting.nix`,
`pkgs/by-name/wo/wooting-udev-rules/{package.nix,wooting.rules}`,
`pkgs/by-name/vi/via/package.nix`, `pkgs/by-name/vi/vial/package.nix`,
`nixos/modules/security/run0.nix`. Details in the findings that cite
them.

### Read-only local commands run on `torrent`

`ls`, `stat`, `getfacl`, `getent`, `id`, `ssh-keygen -l`, `ssh-to-age`
(public keys only), `grep -c`, `git log`, `git show`,
`tailscale status`, `tailscale status --json`, `tailscale version`,
`tailscale debug prefs`, `nix eval`, `nix flake metadata`. No SSH to any
host. No `nixos-rebuild`. No writes to any `.nix` file.

### What could not be verified

| Claim | Why not | Marked |
|---|---|---|
| That `&nixos-thinkpad` is the admin's editing identity in `~/.config/sops/age/keys.txt` | Deriving its public half requires reading the private key | PLAUSIBLE (F-P8-03) — strongly supported, see the finding |
| Which age anchor is which laptop's `/var/lib/sops-nix/key.txt` | Same | PLAUSIBLE (F-P8-05) |
| Whether the three retired vps age keys still exist anywhere | DigitalOcean droplet destruction is unobservable from here | the finding is rated on the assumption they *might*, which is the only safe assumption for a public repo (F-P8-02) |
| Plaintext values, or which values are equal to each other | Never attempted | n/a |
| Whether values changed *before* 2026-08-21 | Commit `611704e` re-encrypted every value, changing every IV; ciphertext comparison cannot see past a full re-encrypt | stated as a limit, not a result (F-P8-02) |
| `RunSSH` on thinkpad/homelab/vps directly | No SSH allowed; inferred from evaluated `extraUpFlags` + absent peer `sshHostKeys` | CONFIRMED via two independent signals (F-P8-11) |
| The live Tailscale console ACL | Not readable from here | PLAUSIBLE for live (F-P8-07) |
| Whether any package still needs `electron-39.8.10` | Would require re-evaluating all five closures against a permit-free nixpkgs | PLAUSIBLE (F-P8-20) |
| Modes of the plaintext copies factorio writes to `/srv/factorio/*/config/server-settings.json` | On homelab; no SSH | PLAUSIBLE, handed to P4 |
| Whether `id_ed25519` on torrent is passphrase-protected | Requires reading the private key | not asserted (F-P8-04) |
| Branch protection / PR workflow posture on the public GitHub repo | Not in this repo | out of scope; threat model §8.8 |
| thinkpad's live state | Offline, last seen 1d ago | n/a |

---

## 2. Findings

### F-P8-01 — one flat recipient set over public, permanent ciphertext: any single age key, ever, decrypts every secret the fleet has ever held

- **File:** `.sops.yaml:1-25`, `modules/profiles/default.nix:156`,
  `secrets/secrets.yaml` (all 72 revisions)
- **Severity:** CRITICAL
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A8 — thinkpad roams onto untrusted networks and has
  no FDE (`worktree-fde-secureboot-plan` unmerged, §8.7); physical loss
  yields its age identity and therefore, retroactively, everything.
  A7 — anything running as `lilijoy` reads the editing identity
  (F-P8-03). A6 — anyone at all can archive the ciphertext today, with
  no account and no trace, and wait.
- **Rule:** new-rule candidate. `docs/procedures/secrets.md` documents
  the *mechanics* of adding and removing recipients and states no
  principle about which host should hold which secret.
- **Finding:** independently verifying P6's F-P6-01 and agreeing with
  it. `.sops.yaml` has exactly one `creation_rules` entry
  (`path_regex: secrets/[^/]+\.(yaml|json|env|ini)$`) with one `age` key
  group listing all seven recipients. sops matches `creation_rules` by
  file path, first match wins, so a single rule over a single file means
  a single recipient set for every key in it. Confirmed against the
  `sops:` metadata in `secrets/secrets.yaml`, which carries seven
  `recipient:` entries with a wrapped data key for each.

  Every recipient therefore decrypts all 31 keys. Evaluated per-host
  declarations show how far that overshoots need:

  | host | secrets *declared* (consumed) | secrets it *can decrypt* |
  |---|---|---|
  | thinkpad | 3 | 31 |
  | torrent | 3 | 31 |
  | homelab | 16 | 31 |
  | vps | 7 | 31 |

  On a private repo that is a lateral-movement multiplier. **On a public
  repo it is a permanent, retroactive, fleet-total one.** Three
  properties compound:

  1. **The ciphertext is public and cannot be withdrawn.** Anyone can
     `git clone` all 72 revisions now and keep them forever. There is no
     network boundary, no authentication, no rate limit, and no
     detection in front of an offline attack against them.
  2. **One key opens everything.** Root on *any* host — including
     `vps`, the internet-facing box, whose secret needs are 7 of 31 —
     yields the age identity for that host, which yields all 31 values.
     Root on vps is exactly what F-P0-02 establishes homelab already has
     by design and what A2 is trying to get.
  3. **Rotation does not undo it.** Changing a value re-encrypts it
     going forward; the old ciphertext stays public. An age key obtained
     at any point in the future decrypts every secret the file *ever*
     held. F-P8-02 shows this is not theoretical here.

  One recipient deserves separate mention. `age1758lfex…d7cl8`, anchored
  `&nixos-thinkpad`, is present in **all 72 revisions**, back to the
  first sops commit on 2024-07-05 — through two documented host
  reinstalls and every recipient rotation since. No host key survives
  that; this is almost certainly the human's editing identity
  (F-P8-03), and it is the single highest-value credential in the fleet:
  it decrypts every secret this repository has ever published.

  Also worth stating plainly, because it removes a tempting mitigation:
  the ciphertext being in the repo is not the only copy.
  `sops.defaultSopsFile` is a Nix *path literal*, so `secrets.yaml` is
  copied into `/nix/store` on every host importing `profile-default` —
  confirmed on torrent, where several revisions sit at `0444 root:root`.
  Restricting repo access (were the repo made private tomorrow) would
  not retire what is already published, nor what is already in every
  host's store.
- **Proposed fix:** three steps, and **the order matters more than any
  individual step**. Steps 1 and 2 without step 3 accomplish *nothing*
  for anything already committed.

  **Step 1 — restructure `.sops.yaml` into per-scope files.** sops's
  granularity is per *file*, not per key within a file, so the split has
  to be into multiple files matched by distinct `path_regex` entries.
  sops-nix supports this directly: `sops.secrets.<name>.sopsFile`
  overrides `sops.defaultSopsFile` per secret. Derived from the
  evaluated per-host declarations, the minimum-privilege layout is:

  | file | recipients | keys |
  |---|---|---|
  | `secrets/common.yaml` | admin + thinkpad + torrent + homelab + vps | `git_username`, `git_email` |
  | `secrets/thinkpad.yaml` | admin + thinkpad | `tailscale_authkey_thinkpad` |
  | `secrets/torrent.yaml` | admin + torrent | `tailscale_authkey_torrent` |
  | `secrets/homelab.yaml` | admin + homelab | `tailscale_authkey_homelab`, `homelab_backblaze_rclone_config`, `homelab_backblaze_restic_password`, `homelab_discord_webhook`, `homelab_zrepl_key`, `homelab_vps_deploy_key`, `homelab_wireguard_private_key`, `homelab_samba_android_smb_password`, `minecraft_username`, `factorio_game_password`, `factorio_token`, `factorio_username`, `cloudflare_octodns_token` |
  | `secrets/vps.yaml` | admin + vps | `tailscale_authkey_vps`, `vps_wireguard_private_key`, `vps_discord_webhook` |
  | `secrets/wg-tunnel.yaml` | admin + homelab + vps | `wireguard_vps_homelab_psk` (the only genuinely two-host secret) |

  `vps_caddy_env` is dropped entirely (F-P8-18) and the nine orphans are
  handled by F-P8-17. `creation_rules` are ordered most-specific-first
  with the `common.yaml` rule last, since sops takes the first match.

  What this buys, concretely: root on vps drops from 31 secrets to 4;
  root on either laptop drops from 31 to 3. homelab is barely narrowed
  (16 of 31) and that is correct — homelab genuinely is the fleet's
  centre of gravity, and F-P0-02 already establishes it is trusted with
  root on vps.

  What it cannot buy: **the admin recipient must be in every file**,
  because whoever runs `sops` has to decrypt to edit. So exactly one
  universal decryptor remains, unavoidably. The right response is to
  make that one key hard to steal rather than to pretend it away —
  `config.sops.age.plugins` exists in the pinned sops-nix (evaluated:
  `"plugins":[]` on every host), so an `age-plugin-yubikey` PIV identity
  can be the admin recipient, making the universal key unextractable.
  That is directly analogous to the FIDO2 `sk-ssh-ed25519` already in
  `flake.vars.publicSshKeys`, and the same token can carry both.

  **Step 2 — move the values.** `sops secrets/<file>.yaml` for each new
  file, then `sops updatekeys` on each. User only; an agent must not
  touch plaintext. The Nix half (new `creation_rules`, per-secret
  `sopsFile` attributes) is ordinary code an agent can write.

  **Step 3 — rotate every credential at the far end.** This is the step
  that actually matters and the one easiest to skip.
  **Re-keying does not retire published ciphertext.** Until a credential
  is changed *at the provider*, the value sitting in 72 public revisions
  is the live value, and any of the 14 historical age keys (F-P8-02)
  opens it. Concretely that means: a new Backblaze application key and
  restic repository password; a new Cloudflare API token for octoDNS;
  new Discord webhook URLs for both health-alert channels; all five
  tailscale auth keys revoked and reissued in the console; new WireGuard
  keypairs and PSK on both ends of the tunnel; a new `vps-deploy` SSH
  keypair; a new zrepl puller keypair (which also means updating
  `flake.vars.zreplPullerKey`); a new samba password; a new factorio
  token and game password. Anything not rotated at the provider is
  still exposed no matter how the recipient set is arranged.
- **Fix risk:** step 1 fails loudly and locally — a wrong `sopsFile`
  produces "secret not found" at activation on exactly one host, so
  `nixos-rebuild build` for all five plus a VM test of homelab catches
  it before any switch. Step 3 is the dangerous one and must be
  sequenced per credential, not batched: rotating both WireGuard keys
  requires both ends to switch together or the tunnel drops (and with
  it the DNAT'd game ports); rotating `homelab_vps_deploy_key` breaks
  the only deploy path to vps if the new public half is not in place
  first; rotating the zrepl key breaks replication from both laptops
  until `vars.zreplPullerKey` lands everywhere. Order each as
  add-new → verify → remove-old, never replace-in-place.
- **Owner:** P8 owns the remediation design (above). User owns every
  `sops` invocation and every provider-side rotation. Confirms P6's
  F-P6-01.

### F-P8-02 — three retired vps age keys can decrypt today's live credentials from public history; the reinstall rotated one secret out of thirty-one

- **File:** `.sops.yaml` (history: `e42683c`, `c2a6549`, `a6f4fb0`, all
  2026-08-25; `a9d1071`, 2026-08-17), `secrets/secrets.yaml` (history)
- **Severity:** CRITICAL
- **Confidence:** CONFIRMED for the recipient/ciphertext overlap;
  PLAUSIBLE that any of the three retired keys still exists somewhere.
- **Axis:** hardening
- **Reachability:** A6/A2 — anyone who obtained, or obtains, one of
  three DigitalOcean droplet host keys. The droplet in question was
  "bricked" and then destroyed (per the `.sops.yaml` comment and
  `TODO.md`), which is precisely the circumstance in which a host key's
  disposal is least certain.
- **Rule:** new-rule candidate — recipient rotation must be paired with
  value rotation.
- **Finding:** the vps reinstall of 2026-08-25 rotated the sops
  recipient three times in one day, as the reinstall churned through
  host keys: `e42683c` "rotate sops recipient ahead of reinstall",
  `c2a6549` "sync sops recipient + hardware-config to the current
  on-disk install", `a6f4fb0` "sync sops recipient to the current live
  install's host key". Each intermediate state was committed and pushed
  to a public repository.

  Enumerating every age recipient that has ever appeared in
  `secrets/secrets.yaml`'s `sops:` metadata across all 72 revisions
  gives **14 distinct keys**, of which only **7 are current**. Seven are
  retired:

  | retired recipient | revisions it was a recipient of | era |
  |---|---|---|
  | `age1t8cfzavzm9…we0auz` | 44 | 2024-08 → |
  | `age1t09qgr6xfs…30zl32` | 43 | 2024-08 → |
  | `age1e4a5f20ycn…lk25fx` | 31 | 2024-07 → |
  | `age1p6nhsn2z56…3fl6f8` | 11 | **old vps**, 2026-08-17 → 2026-08-25 |
  | `age1uc86th6cf3…j2lqc4` | 2 | **transient vps**, 2026-08-25 |
  | `age1sc4cn2k4lw…8mt5aw` | 1 | **transient vps**, 2026-08-25 |
  | `age1d29x545ku0…namzz3` | 1 | 2024-07-29 "changed age secretes key for reinstall" |

  The sharp part is what those keys can still open. Comparing
  **ciphertext strings** between historical revisions and today's file
  — sops re-wraps only the data key on `updatekeys`, so an unchanged
  `ENC[...]` string means an unchanged value — each of the three retired
  **vps** keys was a recipient of a public revision that already
  contained the *byte-identical, currently-live* ciphertext for at least
  these ten secrets:

  `homelab_vps_deploy_key`, `homelab_zrepl_key`,
  `homelab_backblaze_restic_password`, `cloudflare_octodns_token`,
  `vps_wireguard_private_key`, `homelab_wireguard_private_key`,
  `wireguard_vps_homelab_psk`, `tailscale_authkey_torrent`,
  `tailscale_authkey_homelab`, `homelab_discord_webhook`.

  That set is fleet-total by the threat model's own boundaries:
  `homelab_vps_deploy_key` is root on vps (§4.2); `homelab_zrepl_key` is
  root SSH to torrent and thinkpad (§4.5); the Backblaze restic password
  reaches asset #1's offsite copy; the tailscale auth keys enroll new
  nodes, which is §4.4. The older four retired keys show `(none)` on the
  same test — they predate the 2026-08-21 re-encrypt and so cannot open
  today's values — but they were recipients of 31–44 public revisions
  each and open whatever those held.

  Meanwhile the reinstall rotated exactly **one** value.
  `507bd11` "security(vps): rotate `tailscale_authkey_vps` for the
  reinstall" changed that one ciphertext; every other key's ciphertext
  has been byte-identical since `611704e` (2026-08-21), which spans the
  entire recipient-rotation series. So the security work done on
  2026-08-25 correctly rotated the recipient and correctly rotated the
  one auth key, and left the other thirty values readable by the keys it
  had just retired.

  **A necessary caveat on method.** `611704e` ("recompute sops mac after
  merge conflict resolution") re-encrypted every value, changing every
  IV. Ciphertext comparison therefore cannot see past 2026-08-21, so I
  can say nothing about whether values changed before then. That is a
  limit of the method, not a finding — and it does not weaken the result
  above, because the three vps keys were all recipients *after*
  2026-08-21.
- **Proposed fix:** treat the three retired vps keys as compromised
  until proven otherwise — which for a public repo is the only defensible
  default, since the cost of being wrong is unbounded and the cost of
  being right is one rotation cycle. That means **step 3 of F-P8-01 is
  not optional and not deferrable**: rotate, at the provider, every one
  of the ten credentials listed above, plus the rest of the live set for
  consistency. Then write the pairing rule into
  `docs/procedures/secrets.md`: *removing or replacing a recipient
  requires rotating every value that recipient could read, because the
  ciphertext it could read is public and permanent.* The existing
  "Removing a recipient" runbook currently warns only about
  already-decrypted plaintext on the removed host, which is the smaller
  half of the problem.

  Also worth adding to `docs/procedures/new-host.md`: a reinstall that
  churns through host keys should do the recipient update **once, at the
  end**, against the final key — not three times against intermediate
  ones. Each intermediate commit permanently widens the historical
  recipient set for no benefit.
- **Fix risk:** as F-P8-01 step 3 — sequence each rotation
  add-new → verify → remove-old. The zrepl and vps-deploy keypairs are
  the two where getting it wrong costs the most (replication and the
  only deploy path to vps respectively), and both should be done with
  console/physical access available.
- **Owner:** P8 for the analysis; **user** for every rotation. Escalate
  to the front of the remediation queue — this is the one finding in
  this part where the exposure is already real rather than conditional.

### F-P8-03 — the age identity that decrypts all 72 public revisions is a mode-0644 file in the user's home

- **File:** `/home/lilijoy/.config/sops/age/keys.txt` (not in the repo);
  referenced by `docs/procedures/secrets.md` and
  `modules/profiles/PC.nix:208-211`
- **Severity:** HIGH
- **Confidence:** CONFIRMED for the file, its mode, and that it is an
  age secret key. PLAUSIBLE — strongly supported — that it is the
  `&nixos-thinkpad` recipient present in all 72 revisions.
- **Axis:** hardening
- **Reachability:** A7 — anything running as `lilijoy` on torrent: a
  browser exploit, a malicious dependency, a bad AI-agent tool call.
  Threat model §5 rates A7 the most likely initial foothold.
- **Rule:** new-rule candidate.
- **Finding:** `/home/lilijoy/.config/sops/age/keys.txt` exists on
  torrent at **mode 0644**, owner `lilijoy:users`, 75 bytes — one bare
  `AGE-SECRET-KEY-1` line with no comment header (confirmed by a
  count-only grep; contents not read). This is the exact default path
  the `sops` CLI searches, and `modules/profiles/PC.nix:208-211` names
  it as such: *"interactive `sops` edits … are driven entirely by the
  `sops` CLI's own identity discovery (`SOPS_AGE_SSH_PRIVATE_KEY_FILE`
  env var or `~/.config/sops/age/keys.txt` on whatever machine runs the
  `sops` CLI)"*. So the repo's own documentation identifies this file as
  the editing identity.

  If it holds `&nixos-thinkpad` — the recipient present in **all 72**
  revisions, surviving two documented host reinstalls, which no host key
  could — then this one file decrypts every secret this public
  repository has ever contained. I did not confirm that, because
  confirming it means deriving its public half, which means reading the
  private key. The circumstantial case is strong enough that it should
  be treated as true until the user checks (`age-keygen -y
  ~/.config/sops/age/keys.txt`, which is theirs to run, not mine).

  Two mitigating and one aggravating detail, stated precisely so the
  rating is not over-read:

  - **Mitigating:** `/home/lilijoy` is mode `0700`, so `other` cannot
    traverse to the file despite its 0644. Present exposure is therefore
    A7 (processes running *as* `lilijoy`) and root, not literally every
    UID. The 0644 is nonetheless wrong: it means the file's own
    protection is entirely borrowed from its parent directory, and any
    future change to that directory's mode, any copy elsewhere, any
    archive extraction, or any tooling that preserves modes silently
    widens it.
  - **Mitigating:** `age` and `sops` do not enforce identity-file
    permissions the way OpenSSH does, so nothing warned about this.
  - **Aggravating:** `/home` on torrent is replicated by zrepl to
    `zbackup/backup/torrent/zroot/local/home` on homelab
    (`hosts/homelab/configuration.nix:230-240`), so the key is
    PLAUSIBLE-present in the backup pool as well. It is *not* in the
    offsite restic set, whose dataset list is
    `zroot/local/state zdata/storage/storage` — verified at
    `hosts/homelab/configuration.nix:110`.

  The file dates from 2025-06-10, matching the `add torrent age key`
  commits of the same day.
- **Proposed fix:** three things, ascending in value.
  1. `chmod 600 ~/.config/sops/age/keys.txt`. Free, immediate, and it
     stops the protection being borrowed from a directory mode.
  2. Have the user run `age-keygen -y` on it and settle the attribution
     — F-P8-05 cannot be closed without knowing which anchors are this
     key and which are host keys, and neither can F-P8-01's step 1.
  3. If it *is* the universal recipient, move it to hardware. `sops`
     supports age plugins and `config.sops.age.plugins` is available
     (evaluated present, currently `[]`), so an `age-plugin-yubikey`
     PIV identity can replace it. The universal decryptor then cannot be
     read off a disk at all, which is the single change that most
     reduces F-P8-01's blast radius, and it pairs naturally with the
     FIDO2 SSH key already in `flake.vars.publicSshKeys`.
- **Fix risk:** (1) none. (3) is a real migration: the new public key
  must be added as a recipient and `sops updatekeys` run *before* the
  old one is removed, and the token must be present to edit secrets
  thereafter — which is the point, but it changes the workflow and needs
  a documented recovery path if the token is lost (a second YubiKey, or
  a sealed offline copy of a backup identity).
- **Owner:** P8; user for the `chmod`, the attribution, and any hardware
  migration.

### F-P8-04 — a fleet-root SSH private key sits in `lilijoy`'s home on the daily driver

- **File:** `modules/flake/vars.nix:5-12`,
  `hosts/homelab/configuration.nix:353`,
  `hosts/vps/configuration.nix:287`,
  `hosts/isoimage/configuration.nix:98`
- **Severity:** HIGH
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A7 — anything running as `lilijoy` on torrent reads
  `/home/lilijoy/.ssh/id_ed25519` directly.
- **Rule:** new-rule candidate.
- **Finding:** `flake.vars.publicSshKeys` holds three keys, installed
  verbatim as `users.users.root.openssh.authorizedKeys.keys` on homelab,
  vps and isoimage, all of which set
  `PermitRootLogin = "prohibit-password"`. The count and shape match
  `docs/procedures/remote-access.md` exactly: two `ssh-ed25519` (thinkpad,
  torrent) and one `sk-ssh-ed25519@openssh.com` (FIDO2 YubiKey).

  The third entry is **byte-identical** to
  `/home/lilijoy/.ssh/id_ed25519.pub` on this machine
  (`SHA256:3LgXwUvoOVCx+OXXwcy5T0rapp/JB44jZZxVNmLDHCA`), whose private
  half is a plain file at mode `0700 lilijoy:users`. So A7 reads one
  file and has **interactive root on homelab, vps and isoimage**
  immediately — no privilege escalation on the laptop, no waiting for a
  timer. That is a strictly shorter path than F-P0-03, and it should be
  rated alongside it rather than folded into it. It then chains onward
  exactly as F-P0-01 describes, since the same key is the GitHub push
  credential.

  The observation is about composition, not count: one of the three
  keys is hardware-backed and unextractable, and two are unprotected
  files on the two machines most exposed to A7 and A8. The YubiKey
  demonstrates the safer form is already available and already in use.
  On a public repo this is worse than it would otherwise be — the
  authorized-key list, the hosts it applies to, and each host's
  `PermitRootLogin` setting are all published, so an attacker who
  obtains the file knows precisely where to use it and needs no
  reconnaissance.
- **Proposed fix:** decision required. (a) Drop the two file-based keys
  and make the YubiKey the sole interactive-root credential — this also
  makes the GitHub push credential hardware-backed, which is the single
  biggest reduction available to F-P0-01. (b) Keep them but actually
  wire the Bitwarden SSH agent that `modules/profiles/PC.nix:165` already
  half-configures: its `SSH_AUTH_SOCK` is the literal broken string
  `/home/<user>/.bitwarden-ssh-agent.sock` (F-P8-22), so the intent
  exists and has never worked. (c) Accept and document that A7 on either
  laptop is fleet-total by design.
- **Fix risk:** (a) locks you out of remote root the moment the YubiKey
  is unavailable. Needs a tested out-of-band recovery path written down
  *before* it lands — DigitalOcean console for vps, physical access for
  homelab — and isoimage's recovery role makes that especially
  load-bearing.
- **Owner:** P8; overlaps P5 and F-P0-01's decision.

### F-P8-05 — five of seven current age recipients cannot be attributed to any live host key

- **File:** `.sops.yaml:2-9`
- **Severity:** HIGH
- **Confidence:** CONFIRMED that they are unattributable from the config
  and that neither laptop's *current* SSH-derived identity is among
  them; PLAUSIBLE that any specific one is stale.
- **Axis:** hardening / needed-used
- **Reachability:** A6/A8 — whoever holds a retired key. Given F-P8-01
  and F-P8-02, that is the whole secret set, permanently.
- **Rule:** new-rule candidate. Nothing requires the anchor set to be
  reconcilable against the live fleet.
- **Finding:** `.sops.yaml` lists seven anchors for a four-host fleet.
  Deriving age identities from **public** SSH host keys attributes
  exactly two:

  | anchor | maps to | evidence |
  |---|---|---|
  | `&homelab3` `age18t8txuc…h73ad` | homelab's current SSH host key | `known_hosts` entries for `homelab`, `100.98.142.41`, `homelab.taila4ae6c.ts.net` |
  | `&vps` `age13y33z6n…qegc8` | vps's current SSH host key | `known_hosts` entries for `vps`, `100.80.252.80`; matches the file's own comment |

  The remaining five — `&nixos-thinkpad`, `&thinkpad-ssh`,
  `&thinkpad-machine`, `&torrent-machine`, `&torrent-age` — cannot be
  attributed from anything readable without opening a private key. Two
  are presumably the laptops' `sops.age.generateKey` machine identities
  at `/var/lib/sops-nix/key.txt`; one is very likely the editing
  identity of F-P8-03.

  What *is* provable is that **neither laptop's current SSH-derived
  identity is a recipient**:
  `ssh-to-age(/etc/ssh/ssh_host_ed25519_key.pub)` on torrent is
  `age1smm5rghe29g6ldnnltg45dnt705xgfavehgm8vqhmfc4cq8ht4ssduhu5v`, and
  the same transform of thinkpad's host key (as pinned in
  `hosts/homelab/configuration.nix:225-227`) is
  `age1dvmf3gsfmtacctqwdcuayjl5mrmk3txlhjl5fgvuct3n202dvyls4873k8`.
  Neither appears in `.sops.yaml`. So the anchor literally named
  `&thinkpad-ssh` is **not** thinkpad's SSH-derived identity today: the
  host key was regenerated after the anchor was added and the anchor was
  never removed. Torrent's `.pub` is dated 2026-08-24, so the same
  history applies there.

  A consequence worth recording: `sops.age.sshKeyPaths =
  ["/etc/ssh/ssh_host_ed25519_key"]` is in force on both laptops (the
  sops-nix default) and contributes nothing on torrent, because the
  derived identity is not a recipient. Decryption there rests solely on
  `/var/lib/sops-nix/key.txt`. That is what `PC.nix:192-215` argues for
  and is fine — but it means a reader cannot tell from `.sops.yaml`
  which anchors are load-bearing and which are inert, which is exactly
  the condition under which stale ones survive.

  Rated HIGH rather than MEDIUM specifically because the repo is public.
  On a private repo an unaccounted-for recipient is a hygiene problem
  with a bounded window. Here it is permanent: F-P8-02 demonstrates that
  a retired recipient keeps decrypting real, current credentials from
  published history indefinitely.
- **Proposed fix:** the user attributes each of the five (this needs
  reading private key files and is not an agent's to do:
  `age-keygen -y` on each candidate path, on each machine). Then, for
  each: either annotate it in `.sops.yaml` with a comment naming the
  machine and file path — the `&vps` anchor already models this well —
  or remove it and `sops updatekeys`. Add the annotation requirement to
  `docs/procedures/secrets.md`'s "Adding a recipient" runbook so new
  anchors arrive documented. Remember F-P8-02's pairing rule: removal
  alone changes nothing about published ciphertext.
- **Fix risk:** removing an anchor that turns out to be a live machine
  identity breaks that host's decryption at the next activation — loud,
  but potentially on a host you are not sitting at, and on thinkpad
  which is frequently offline. One at a time, with a
  `nixos-rebuild build` for the affected host after each `updatekeys`.
- **Owner:** P8 for the analysis; user for attribution and removal.

### F-P8-06 — the tailnet ACL is flat, and on vps nothing narrows it (F-P0-04, part 1)

- **File:** `docs/tailscale-acl.json:34-62`,
  `hosts/vps/configuration.nix:341`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the reference copy and every per-host
  firewall value quoted; PLAUSIBLE for the live console ACL (F-P8-07).
- **Axis:** hardening
- **Reachability:** A5 — a stolen laptop, an over-broad auth key, an
  attacker-enrolled node, or the household Android phone, which is a
  live tailnet member (F-P8-07).
- **Rule:** new-rule candidate; bears on open question §8.1.
- **Finding:** confirming F-P0-04 and sizing it. All four grants use
  `"ip": ["*"]`, with `src = ["autogroup:member", "tag:thinkpad",
  "tag:torrent", "tag:homelab", "tag:isoimage"]` and `dst` covering the
  same tags plus `tag:vps`, `autogroup:internet`, and `192.168.1.0/24`.
  No per-service restriction anywhere.

  What that actually reaches, from the evaluated firewall config:

  | host | reachable from the tailnet |
  |---|---|
  | thinkpad | `tailscale0` tcp **22** only |
  | torrent | `tailscale0` tcp **22** only |
  | homelab | `tailscale0` tcp **22, 445, 2049, 8096, 25565**; udp **19132, 25565, 34197, 34198** |
  | vps | **everything** — `networking.firewall.trustedInterfaces = ["tailscale0"]` bypasses the packet filter wholesale |

  This refines F-P0-04 in a way that changes where the fix belongs. On
  the two laptops the host firewall already narrows better than any ACL
  would — one port, sshd, with `PermitRootLogin =
  "forced-commands-only"` behind it. On homelab the interface-scoped
  rules already state the service list, though NFS (2049, authorised by
  uid/gid, so any tailnet device mounts `/storage` as any uid) and SMB
  (445) are broad things to gate on device authorization alone. On
  **vps** the ACL is doing *all* the work, because `trustedInterfaces`
  leaves no packet filter to fall back on. Plus, per the evaluated
  `extraUpFlags` on homelab
  (`["--advertise-tags=tag:homelab", "--advertise-routes=192.168.1.0/24",
  "--advertise-exit-node"]`), a rogue device also gets the whole home LAN
  and an internet egress path, both explicitly granted.

  Credit where due: `tag:vps` appears in no `src` list, so vps cannot
  *initiate* to any other tailnet node — a deliberate least-privilege
  touch, and the comment at lines 41-44 says so.

  A latent multi-user issue: `autogroup:member` is `src` in all four
  grants. With one user that is "your own devices". The moment anyone is
  invited or a device is shared, they inherit all four grants including
  LAN and exit node.

  Public-repo note: the whole tailnet structure — tags, routes, exit
  node, which services sit on which port — is published. Nothing here
  was ever protected by obscurity, but it means an attacker who obtains
  a node key needs no reconnaissance phase at all.
- **Proposed fix:** decision required; the analysis suggests an order.
  (1) The highest-value change is not in the ACL — replace vps's
  `trustedInterfaces = ["tailscale0"]` with
  `networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ]`,
  matching the pattern every other host uses. Nix-managed,
  build-testable, and it removes the one place the ACL is the sole
  control. (2) Then, if ACL narrowing is still wanted, split homelab's
  grants — `:2049`/`:445` restricted to the devices that actually mount
  the shares, `:22` for admin. (3) Replace `autogroup:member` with the
  explicit tag list plus your own user, so a future member does not
  silently inherit everything.
- **Fix risk:** (1) is the risky one despite being Nix-managed — vps is
  reachable *only* over the tailnet, so a wrong port list locks you out
  and recovery is DigitalOcean's console. VM-test first
  (`system.build.vm`) and keep the console open during the switch.
  (2) and (3) break access in ways no build or VM test catches; stage
  one grant at a time.
- **Owner:** P8 for the ACL; **P2** for vps's `trustedInterfaces`, which
  is the load-bearing part. Open question §8.1.

### F-P8-07 — the ACL is a security control with no version control and no enforcement, and it has already drifted (F-P0-04, part 2)

- **File:** `docs/tailscale-acl.json:1-4`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — the drift is observed live, not inferred.
- **Axis:** documentation / hardening
- **Reachability:** A5 — the gap between what the file says and what the
  tailnet enforces is unbounded in principle and non-zero in fact.
- **Rule:** new-rule candidate. Every control `docs/hardening.md` names
  is Nix-managed; it says nothing about controls that are not.
- **Finding:** the header is honest — *"managed in the Tailscale admin
  console … not applied by Nix. Kept here only as a reference copy;
  update this file whenever the console policy changes so the two don't
  drift."* Nothing enforces that. No CI (`.github/` does not exist), no
  `nix flake check` assertion, no git hook, no sync job — even though
  the repo already demonstrates the pattern it would need
  (`modules/services/octodns.nix` renders zone data from Nix and pushes
  it to Cloudflare via an API token). Per §4.4 the ACL is the *primary*
  access control for most of this fleet, so the widest-reaching control
  is the only one neither versioned nor verified.

  **Drift is already present.** `tailscale status --json` shows five
  nodes:

  | node | tags | in the ACL file? |
  |---|---|---|
  | torrent | `tag:torrent` | yes |
  | thinkpad | `tag:thinkpad` (offline 1d) | yes |
  | homelab | `tag:homelab` | yes |
  | vps | `tag:vps` | yes |
  | **Pixel 6a** (Android) | **none — user-owned** | **no** |

  The phone appears nowhere in this repo, but `autogroup:member` is
  `src` in all four grants, so it holds full IP-level access to all four
  hosts, the `192.168.1.0/24` LAN, and exit-node egress. It is a live A5
  instance and the ACL file gives no hint it exists. Conversely
  `tag:isoimage` appears nine times across `tagOwners`, all four grants
  and both `ssh` rules, for a device that cannot exist (F-P8-19).
- **Proposed fix:** (a) make the reference copy checkable — a
  `nix flake check` or hook step that fetches the live policy via the
  Tailscale API and diffs it against `docs/tailscale-acl.json`. The
  credential pattern already exists (`cloudflare_octodns_token` →
  `sops.templates."octodns-env"` → `EnvironmentFile`); a read-only
  `tailscale_api_key` would mirror it — and per F-P8-01 it should live
  in a scoped secrets file, not the shared one. Actually *applying* the
  policy from Nix is possible with the same API but is a bigger change
  that can lock you out of your own tailnet; checking is the cheap 80%.
  (b) Record the household devices in the file's comment block, so "who
  is `autogroup:member`" is answerable from the repo.
- **Fix risk:** (a) introduces a new fleet credential to hold and rotate
  — scope it read-only. A drift check that fails closed on a Tailscale
  API outage would block `nix flake check`; make it warn, or run it
  separately.
- **Owner:** P8. Feeds open question §8.1.

### F-P8-08 — `via`/`vial` udev rules make every `/dev/hidraw*` world-readable and world-writable

- **File:** `modules/profiles/PC.nix:135-137`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — read from the pinned nixpkgs *and*
  observed live on torrent.
- **Axis:** hardening
- **Reachability:** A7, and importantly *below* A7 — any UID on the
  machine, including a service account, a container, or a browser
  sandbox that escaped only as far as `nobody`.
- **Rule:** new-rule candidate — `docs/hardening.md` covers firewall
  scoping and systemd sandboxing, nothing about udev device permissions.
- **Finding:** `services.udev.packages = [ pkgs-unstable.via
  pkgs-unstable.vial ]`. **Both** packages ship the identical
  `92-viia.rules` containing exactly one line, with no vendor or product
  filter:

  ```
  KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0666", TAG+="uaccess", TAG+="udev-acl"
  ```

  Verified in the pinned nixpkgs at `pkgs/by-name/vi/via/package.nix:33`
  and `pkgs/by-name/vi/vial/package.nix:25`. At `92-` it sorts after
  `50-qmk.rules`, which sets the sane `MODE="0660", GROUP="plugdev"`, so
  the permissive rule wins. Confirmed live: every `/dev/hidraw*` on
  torrent is `crw-rw-rw- root plugdev`.

  A keyboard's `hidraw` node carries its raw HID input reports. World
  **read** is a system-wide keylogger available to any process
  regardless of user — which, under a Wayland session (Plasma 6, SDDM
  Wayland), is precisely the isolation the compositor otherwise
  provides. World **write** lets any process send raw HID feature
  reports to any HID device; for QMK/VIA/Vial keyboards that includes
  firmware-level configuration, i.e. changing what the keyboard sends.

  The contrast within the same file is instructive:
  `modules/nixos/wooting.nix` gets this right by relying on nixpkgs'
  `wooting-udev-rules` (`TAG+="uaccess"`, no `MODE=`, three specific
  vendor IDs), and the 8bitdo rules at `PC.nix:139-143` are correctly
  scoped by VID/PID. Only the packaged `via`/`vial` rule is unscoped,
  and it is unscoped upstream — nixpkgs shipping the vendor's own bad
  rule, not a mistake in this repo. But it is this repo that opts in,
  and because the config is public an attacker can read that it did.
- **Proposed fix:** stop taking the packages' rules and write a scoped
  one. Drop `via` and `vial` from `services.udev.packages` (keep them in
  `environment.systemPackages` if the GUIs are used — the rules are all
  `udev.packages` contributes), and add a `services.udev.extraRules`
  entry with `TAG+="uaccess"` matching only the VID/PIDs actually in use
  — the `.vil` files in `files/` (`doio.vil`, `ffkb.vil`, `sval_*.vil`)
  name the keyboards. Model it on `wooting.rules`: `uaccess`, no
  explicit `MODE=`. As a smaller interim step, a later-sorting `99-`
  rule resetting `MODE="0660" GROUP="input"` for `hidraw*` removes world
  access, though it leaves the grant at group granularity — see F-P8-09.
- **Fix risk:** a wrong VID/PID means VIA/Vial can no longer see the
  keyboard, which presents as a broken tool rather than a permissions
  problem. `hardware.keyboard.qmk.enable = true` already provides
  `50-qmk.rules` (`0660 plugdev`), so QMK flashing keeps working
  regardless. Verify with `ls -l /dev/hidraw*` and by opening Vial.
- **Owner:** P8; the file is `modules/profiles/PC.nix`, so coordinate
  with **P1**.

### F-P8-09 — `lilijoy` is in the `input` group, which is system-wide keylogging, and `wooting.nix` does not need it

- **File:** `modules/nixos/wooting.nix:8-10`, with
  `modules/profiles/PC.nix:139-145`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening / needed-used
- **Reachability:** A7 — anything running as `lilijoy`.
- **Rule:** new-rule candidate.
- **Finding:** `modules/nixos/wooting.nix` enables `hardware.wooting`
  and adds `lilijoy` to `input`. Verified live: `id lilijoy` includes
  `174(input)`, and `/dev/input/event*` are `crw-rw---- root input` with
  no ACL entries (`getfacl`: `user::rw-`, `group::rw-`, `other::---`).
  Any process running as `lilijoy` can read every input device — every
  keystroke into every application, including a polkit/`run0` prompt, a
  browser password field, a `bitwarden-cli` unlock, and a
  `sops secrets/secrets.yaml` editing session (which is where the
  plaintext this whole part is protecting actually appears).

  The grant is not needed for its stated purpose. The Wooting's access
  comes from `pkgs.wooting-udev-rules`, pinned to `TAG+="uaccess"`
  (verified in the pinned tree) — a seat-local ACL, strictly better than
  a persistent group membership, requiring no `extraGroups`. Nothing in
  `hardware.wooting.enable`'s module wants `input`.

  Two other consumers do exist in `PC.nix:139-145` and both are real:
  the 8bitdo rules set `GROUP="input"`, and plover's
  `KERNEL=="uinput", GROUP="input", MODE="0660"` gives the stenography
  engine the *write* access it needs to inject synthetic input. So
  removing `input` outright would break plover and the controller — but
  that means the justification lives in `PC.nix`, and `wooting.nix` is
  claiming a need it does not have.

  Honest calibration: `lilijoy` can already persist as `lilijoy` and
  phish the same password by wrapping `run0`. The marginal capability is
  passive, silent and application-agnostic — a better keylogger, not a
  new privilege class. MEDIUM, not HIGH.
- **Proposed fix:** delete `users.users.lilijoy.extraGroups = [ "input" ]`
  from `modules/nixos/wooting.nix` so the module does only what its name
  says, and move the grant to `modules/profiles/PC.nix` beside the
  plover and 8bitdo rules that require it, with a comment naming them.
  Longer term, narrowing the plover rule to `uaccess` would let the
  group go entirely — separate work, verify against plover's docs first.
- **Fix risk:** none for the move (identical evaluated result — confirm
  with `nix eval
  .#nixosConfigurations.torrent.config.users.users.lilijoy.extraGroups`
  either side). Actually *removing* the group breaks plover's
  `/dev/uinput` access and the 8bitdo pad, both at runtime not at build.
- **Owner:** P8 for `wooting.nix`; **P1** for where it lands in `PC.nix`.

### F-P8-10 — the AI agent's entire permission surface is unmanaged, unversioned, and has no deny policy for secrets

- **File:** `modules/home-manager/claude-code.nix:1-8,126`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the configuration state; PLAUSIBLE for
  the exploitation path, which depends on agent behaviour rather than a
  mechanism I can demonstrate.
- **Axis:** hardening / needed-used
- **Reachability:** A7 — threat model §5 names "a bad AI-agent tool
  call" explicitly and rates A7 the most likely initial foothold.
- **Rule:** new-rule candidate. `docs/procedures/secrets.md` §"How
  agents (LLMs) must interact with secrets" is binding policy enforced
  by nothing but prose.
- **Finding:** `modules/home-manager/claude-code.nix` is 128 lines, 120
  of which are a status-bar shell script. Its only effect is
  `home.file.".claude/statusline.sh".source`. The module comment
  explains why: *"Claude Code's own config lives in ~/.claude and the CLI
  writes to settings.json itself (that's how /model and /effort
  persist), so only the statusLine script is managed here — a store
  symlink over settings.json would make those writes fail."* Correct for
  `settings.json` as a whole; applied to the *entire* surface, including
  the parts that are policy rather than preference.

  Read live from `/home/lilijoy/.claude/settings.json` and
  `/home/lilijoy/.claude.json`:

  - **No `permissions` block anywhere** — no `allow`, no `ask`, and
    critically no **`deny`**. Nothing at the harness level prevents a
    tool call from reading `secrets/secrets.yaml`, `.sops.yaml`,
    `/run/secrets/*`, `/var/lib/sops-nix/key.txt`,
    `~/.config/sops/age/keys.txt` (F-P8-03) or `~/.ssh/id_ed25519`
    (F-P8-04). The last three are, respectively, the universal secrets
    key and a fleet-root SSH credential. The repo's binding rule
    ("Never edit or decrypt `secrets/*` yourself, even to debug",
    `AGENTS.md`) is instruction text with no mechanism behind it, and
    `permissions.deny` is exactly that mechanism.
  - **One `PreToolUse` hook**, matcher `Bash`, running
    `$HOME/.claude/skills/tcr/scripts/tcr-guard-hook` — a script under
    `$HOME` at mode `0755 lilijoy`, in no repository, not Nix-managed.
    Its own header is candid: *"This is a best-effort deterministic
    guard against the obvious forms of the commands it lists… It is not
    a sandbox: a sufficiently indirect command (piped through another
    interpreter, base64-decoded, etc.) can evade it."* The only
    automated control in the loop is self-described as evadable *and* is
    writable by exactly the principal it constrains.
  - **No MCP servers** — `mcpServers` empty at top level and in every
    project entry; no `.mcp.json`.
  - **No plugins enabled** — `enabledPlugins: {}`,
    `installed_plugins.json` is `{"version":2,"plugins":{}}`. One
    marketplace registered, `anthropics/claude-plugins-official`,
    first-party.
  - **No bypass or auto-approval flags** — no `allowedTools`, no
    `dangerouslySkipPermissions`, no managed-settings file at
    `~/.claude/managed-settings.json` or `/etc/claude-code/`.

  So the *current* state is close to the safe default. The finding is
  not that something is switched on; it is that none of it is pinned.
  Every property above is a mutable file in `$HOME` that the agent
  itself can write, that survives no reinstall, that appears in no
  build, and that nobody would notice changing. On a fleet where
  everything else is reproducible from `origin/master`, the component
  the threat model calls the most likely foothold is the one thing that
  is not.

  Public-repo note, because it cuts the way people do not expect:
  publishing a `permissions.deny` list does not weaken it. A deny rule's
  value does not depend on the attacker not knowing it — §4.7's point
  about obscurity applies here too, and the current arrangement (no
  policy at all, therefore nothing to read) is the *worse* of the two
  positions, not the better one.

  In the module's favour: `statusline.sh` *is* correctly pinned —
  `writeShellApplication` with `runtimeInputs = [ jq git coreutils ]`,
  so its `PATH` is closed, and harness JSON reaches only `jq` filters,
  integer comparisons and `printf "%s"`. No `eval`, no unquoted
  expansion into command position, no path built from input. The
  `bashOptions = [ ]` is deliberate and documented. Clean.
- **Proposed fix:** manage the *policy* half without touching the
  preference half. Claude Code merges settings from several layers, so
  the project layer can be pinned while the CLI keeps writing
  `~/.claude/settings.json`:
  1. Add a tracked `.claude/settings.json` at the repo root (`.gitignore`
     currently ignores only `.claude/worktrees/`, so this is trackable
     today) with a `permissions.deny` list covering
     `Read(./secrets/**)`, `Read(/run/secrets/**)`,
     `Read(~/.config/sops/**)`, `Read(/var/lib/sops-nix/**)`,
     `Read(~/.ssh/**)` and `Bash` patterns for `sops -d` /
     `sops exec-env` / `age-keygen -y`. This turns
     `docs/procedures/secrets.md` from a request into a control, and it
     gets reviewed like any other config change.
  2. Move `tcr-guard-hook` into the repo and point the hook at a store
     path (`home.file`, or a `writeShellApplication`, exactly as
     `statusline.sh` already is), so the guard is not writable by the
     principal it guards.
  3. Extend `claude-code.nix`'s comment to say *which* parts are
     deliberately unmanaged and why, so the gap is a recorded decision
     rather than an omission.
- **Fix risk:** an over-broad `deny` makes ordinary work fail confusingly
  — denying `Read(~/.ssh/**)` also blocks `known_hosts` and `.pub`
  files, which is usually fine and occasionally not. Start with the
  `secrets/`, `sops` and `sops-nix` rules, which have zero legitimate
  agent use by policy, and widen from there. Pinning the hook to a store
  path means editing it needs a home-manager switch — the intended
  trade, but it changes the iteration loop.
- **Owner:** P8. Nobody has audited this before.

### F-P8-11 — nine encrypted credentials nobody consumes are published in permanent ciphertext

- **File:** `secrets/secrets.yaml` (key names only)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED that nothing in the repo references them;
  PLAUSIBLE that the underlying third-party credentials are still valid.
- **Axis:** needed-used
- **Reachability:** A6/A8 — by F-P8-01, every recipient; by F-P8-02,
  every one of the 14 historical recipients; by §4.7, forever.
- **Rule:** threat model §7.4 — grants that outlive their reason.
- **Finding:** `secrets/secrets.yaml` holds 31 keys. 22 are declared as
  `sops.secrets.*` somewhere. Nine are referenced by no `.nix` file in
  the repo (grepped by exact key name):

  | key | shape | why it is probably dead |
  |---|---|---|
  | `torrent_backup_push_key` | SSH private key | the `modules/nixos/backup-push.nix` module it served was replaced by zrepl (`docs/architecture.md` §Backups) |
  | `thinkpad_backup_push_key` | SSH private key | same |
  | `cloudflare_tunnel_token_01` | Cloudflare Tunnel token | no cloudflared anywhere; superseded by the vps/Caddy edge |
  | `nextcloud_admin_pass` | password | no nextcloud anywhere |
  | `webdav_lilijoy` | password | no webdav service anywhere |
  | `winapps_password` | password | no winapps anywhere |
  | `open_weather_key` | API key | no consumer |
  | `restic` | unclear | `homelab_backblaze_restic_password` is the live one; looks like its predecessor |
  | `tailscale_authkey_isoimage` | tailnet auth key | isoimage has `services.tailscale.enable = false` and no sops (F-P8-19) |

  None is a `sops.secrets` declaration, so none is decrypted to
  `/run/secrets` on any host — this is *not* "a dead secret sitting
  decrypted on disk". It is narrower and, on a public repo, worse: dead
  ciphertext, permanently downloadable, of credentials that in several
  cases are probably still valid at the third party. A Cloudflare Tunnel
  token and a Nextcloud admin password do not expire because you stopped
  using them; two of the nine are SSH private keys that may still sit in
  an `authorized_keys` the repo no longer manages; and an unused
  tailscale auth key that still exists in the console is literally
  adversary A5's "over-broad auth key".

  Upgraded from INFO to MEDIUM on the public-repo revision: on a private
  repo these are clutter, here they are nine published credentials with
  no owner watching them.
- **Proposed fix:** for each, the user decides "still needed somewhere
  outside this repo" or "dead". For the dead ones the order matters:
  **revoke at the provider first** — delete the Cloudflare tunnel,
  change the Nextcloud password, revoke `tailscale_authkey_isoimage` in
  the console, remove the two backup-push public keys from any lingering
  `authorized_keys` — *then* remove the key with
  `sops secrets/secrets.yaml`. Removing from the file first accomplishes
  nothing except losing the record of what still needs revoking. All of
  it is the user's to run.
- **Fix risk:** deleting a key used by something outside this repo loses
  the value irrecoverably. Check before deleting; the two SSH keys in
  particular should be revoked everywhere before removal.
- **Owner:** user, prompted by P8.

### F-P8-12 — the ACL's `ssh` block is inert, confirmed on every host, and stays a loaded footgun (F-P0-05)

- **File:** `docs/tailscale-acl.json:64-90`,
  `modules/profiles/default.nix:81-96`
- **Severity:** LOW (latent; HIGH if activated)
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** none today. A5 the moment `--ssh` is enabled
  anywhere.
- **Rule:** new-rule candidate.
- **Finding:** F-P0-05 asked P8 to confirm `--ssh` is off on every host,
  not just where the comment lives. It is, by three independent checks:

  1. **Evaluated, per host.** `config.services.tailscale.extraUpFlags`
     contains no `--ssh` on any of the four real hosts:
     thinkpad `["--advertise-tags=tag:thinkpad"]`;
     torrent `["--advertise-tags=tag:torrent"]`;
     homelab `["--advertise-tags=tag:homelab",
     "--advertise-routes=192.168.1.0/24", "--advertise-exit-node"]`;
     vps `["--advertise-tags=tag:vps"]`. `isoimage` evaluates
     `services.tailscale.enable = false`.
  2. **Grepped.** The only `--ssh` occurrences in the repo are the two
     explanatory comments (`modules/profiles/default.nix:81`,
     `docs/tailscale-acl.json:67`). No `tailscale set`, no
     `tailscale up`, no `extraDaemonFlags` anywhere that could
     reintroduce it out of band.
  3. **Live tailnet state**, covering an imperative
     `tailscale set --ssh` the config would not show.
     `tailscale debug prefs` on torrent reports `"RunSSH": false`. More
     usefully, `tailscale status --json` reports `sshHostKeys: null` for
     **every** node including homelab, vps and thinkpad — a node running
     Tailscale SSH publishes its host keys to the coordination server
     and they appear in peer status, so their uniform absence is
     positive evidence across the whole fleet, not just where I can read
     prefs.

  The `ssh` block therefore does nothing today, and the risk F-P0-05
  identifies stands exactly as written: the second rule is
  `"action": "accept"`, `src` and `dst` both the four device tags,
  `"users": ["autogroup:nonroot", "root"]`. Flipping `--ssh` on any one
  of those hosts immediately grants device-to-device **root** SSH
  handled by Tailscale's proxy, bypassing `PermitRootLogin =
  "forced-commands-only"` on thinkpad and torrent and bypassing
  `authorized_keys` ForceCommand generally. The comment at lines 65-75
  records that this already happened once to vps-deploy, confirmed live.

  One aggravating detail: two of the four tags in that `accept` rule are
  `tag:torrent` and `tag:thinkpad` — the two hosts whose entire
  root-login policy is "forced commands only". They are the hosts the
  rule would hurt most and they are in it. And because the ACL is
  public, an attacker who obtains a node key can read that the rule is
  sitting there and knows exactly which single setting would activate it.
- **Proposed fix:** delete the `ssh` block from
  `docs/tailscale-acl.json` **and from the console**, in that order,
  since nothing uses it and nothing can while `--ssh` stays off. Replace
  it with a comment recording that Tailscale SSH is deliberately unused
  and naming `modules/profiles/default.nix:81-96` as where the reasoning
  lives — mirroring the good comment already at lines 65-75. Deleting
  beats annotating: an annotated footgun is still loaded.
- **Fix risk:** none while `--ssh` stays off, which the three checks
  establish. The only way to break something is to delete from the file
  but not the console or vice versa — F-P8-07's drift problem again, and
  the argument for doing F-P8-07 first.
- **Owner:** P8. Discharges F-P0-05.

### F-P8-13 — `vps-deploy` holds two further root-equivalences beyond the ForceCommand allowlist

- **File:** `hosts/vps/configuration.nix:302-313`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** documentation
- **Reachability:** n/a — nothing exploitable that is not already
  granted by design. The risk is a human over-trusting the written claim.
- **Rule:** n/a — reinforces F-P0-02 and §7.5.
- **Finding:** F-P0-02 established that the allowlist bounds shells and
  accidents but not root, via `nix-store --serve --write` plus an
  unconstrained `switch-to-configuration switch`. Two more grants make
  the same point independently, and neither appears in
  `docs/procedures/remote-access.md`:

  - `nix.settings.trusted-users = [ "vps-deploy" ]` (line 313, confirmed
    in the evaluated `nix.settings` for vps:
    `trusted-users: ["root","vps-deploy"]`). A Nix trusted user can
    override daemon settings per connection — including `require-sigs`,
    `sandbox` and `extra-sandbox-paths` — which is root-equivalent by
    construction and entirely outside the SSH allowlist. The inline
    comment is accurate about *why* and silent about what it costs.
  - `security.polkit.extraConfig` returning `polkit.Result.YES` for
    `org.freedesktop.systemd1.manage-units` for `vps-deploy`
    (lines 302-311). Unrestricted unit management is root-equivalent —
    a unit can be written with `ExecStart` as root.

  vps is the only one of the four real hosts with `trusted-users` beyond
  `root` (thinkpad, torrent, homelab: `["root"]`). `isoimage` has
  `["root","nixos"]` with `allowed-users = ["*"]`, the stock installer
  values, consistent with its recovery-media role — noted for P4, not a
  finding here.
- **Proposed fix:** fold into F-P0-02's doc rewrite. When
  `remote-access.md` is reworded to say homelab is trusted with root on
  vps, list all three mechanisms (store write + activation, Nix trusted
  user, polkit manage-units) so a future reader tightening one does not
  believe they have closed the boundary.
- **Fix risk:** none; documentation only. Removing any of the three
  would break push-deploy, the fleet's only deploy path to vps.
- **Owner:** Phase 4 for the doc, with P2.

### F-P8-14 — 21 of 22 secret declarations set no `restartUnits`, so rotation does not reach the running consumer

- **File:** `modules/services/samba.nix:12-14` (the only one that does)
  vs. every other `sops.secrets.*` declaration
- **Severity:** LOW
- **Confidence:** CONFIRMED for the configuration; PLAUSIBLE for
  per-service impact, which varies by how each consumer reads its file.
- **Axis:** hardening / documentation
- **Reachability:** n/a directly — this governs how long a rotated
  credential stays stale, which matters immediately given F-P8-01 step 3
  and F-P8-02 both call for fleet-wide rotation.
- **Rule:** new-rule candidate.
- **Finding:** the evaluated `restartUnits` is empty for every declared
  secret on all four hosts except
  `homelab_samba_android_smb_password`, which correctly lists
  `samba-user-provision.service`. `restartUnits` is what turns "the file
  on disk changed" into "the service is using the new value"; without
  it, the file updates at the next activation and the running process
  keeps what it read at start.

  Impact is uneven, and worth stating per-consumer rather than as a
  blanket claim:

  | secret | when the consumer reads it | rotation takes effect |
  |---|---|---|
  | `homelab_wireguard_private_key`, `vps_wireguard_private_key`, `wireguard_vps_homelab_psk` | once, at `wg setconf` when the interface comes up | **not until reboot or manual restart** |
  | `homelab_vps_deploy_key`, `homelab_zrepl_key` | per invocation (`ssh -i`) | next run — fine |
  | `homelab_backblaze_restic_password`, `homelab_backblaze_rclone_config` | per backup run | next run — fine |
  | `factorio_*` | container `preStart` | next container start |
  | `cloudflare_octodns_token` | `EnvironmentFile` on `octodns-sync` | next run — fine |
  | `homelab_discord_webhook`, `vps_discord_webhook` | `webhookUrlFile`, per alert | PLAUSIBLE next alert; unverified |
  | `tailscale_authkey_*` | only at first `tailscale up` | never, by design — the node key is already issued |

  The sharp edge is the wireguard trio, which is also exactly what
  F-P8-02 says must be rotated: change the tunnel key or PSK, rebuild,
  and the tunnel keeps running on the old material with nothing
  indicating a pending change. `docs/procedures/secrets.md` says
  consumers "get the new value on their next `sops-install-secrets` run
  (typically at next rebuild/switch or next boot)" — true of the *file*,
  and easy to read as a claim about the *service*.
- **Proposed fix:** add `restartUnits` where the consumer caches:
  `wireguard-wg0.service` for the three wireguard secrets on both
  homelab and vps, and the factorio container units for the factorio
  trio. Leave the per-invocation readers alone. Add a sentence to the
  rotation runbook distinguishing "the file is updated" from "the
  service is using it", naming `restartUnits` as the mechanism and the
  tailscale auth keys as a deliberate exception.
- **Fix risk:** `restartUnits` on `wireguard-wg0.service` means any
  `sops-install-secrets` run seeing changed content bounces the tunnel —
  a second of homelab↔vps downtime, and since the DNAT'd game ports ride
  that tunnel, dropped player connections. Correct for a key rotation,
  surprising on an unrelated rebuild; confirm against the pinned
  sops-nix that it restarts only on actual content change before landing
  it on vps.
- **Owner:** P8; touches `hosts/{homelab,vps}/configuration.nix` and
  `modules/services/factorio.nix` — coordinate with P3 and P4.

### F-P8-15 — nixpkgs is referenced through the indirect flake registry, resolved at update time by an unattended root job

- **File:** `flake.nix:6,8`, with `modules/nixos/auto-update.nix`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the reference form; PLAUSIBLE for the
  exploitation path.
- **Axis:** hardening
- **Reachability:** A6 — requires influencing the flake registry used by
  homelab's root at `nix flake update` time, which means the upstream
  registry itself or a local `/etc/nix/registry.json` override that
  would need root already.
- **Rule:** new-rule candidate.
- **Finding:** the two most important inputs are declared as *indirect*
  registry references rather than URLs:

  ```nix
  nixpkgs-stable.url   = "nixpkgs/nixos-26.05";
  nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
  ```

  Every other input in `flake.nix` uses an explicit `github:owner/repo`
  URL. `nix flake metadata --json` shows these resolving to
  `https://releases.nixos.org/nixos/…/nixexprs.tar.xz`, each locked with
  a `rev` and `narHash`.

  Locked, this is safe — the `narHash` pins exact content and every host
  builds from the lock. The exposure is at *update* time: the `nixpkgs`
  shorthand resolves through the flake registry, fetched from the
  network by default. That resolution happens inside homelab's
  `flake-update-test`, which runs `nix flake update` as **root**, on a
  timer, unattended, and per F-P0-01 merges the result to
  `origin/master` if it builds, from which it reaches every host. The
  registry is therefore an unauthenticated input to the fleet's root
  path, one indirection further out than F-P0-01 accounts for.

  Low probability — it needs a hostile upstream registry or a root-level
  local override, and the latter presupposes the compromise it would
  cause. The fix is nearly free and removes a whole category, which is
  worth more than the probability estimate suggests.
- **Proposed fix:** make both explicit —
  `github:NixOS/nixpkgs/nixos-26.05` and
  `github:NixOS/nixpkgs/nixos-unstable` — matching the style every other
  input uses. Optionally also set `nix.settings.flake-registry = ""` in
  `modules/profiles/server.nix` to disable indirect resolution outright
  on the hosts that build unattended, a good fail-closed server default.
- **Fix risk:** switching from the `releases.nixos.org` tarball to the
  GitHub source changes the fetched artifact, so the next
  `nix flake update` produces a different `narHash` and a full rebuild
  of both channels' closures — a long build and a large `nvd diff`; do
  not combine it with anything else. `flake-registry = ""` breaks the
  `ns` fish function (`modules/home-manager/tooling.nix:146-148`) and
  `comma` on any host it is set for — hence server-only.
- **Owner:** P8, with P7 for the `flake-registry` half.

### F-P8-16 — old ciphertext persists in `/nix/store` on every host

- **File:** `modules/profiles/default.nix:156`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A7 — any local user on any host can copy it.
  Decryption still needs a key.
- **Rule:** n/a — a mechanism note supporting F-P8-01.
- **Finding:** `sops.defaultSopsFile` is a Nix *path literal*, so
  `secrets.yaml` is copied into `/nix/store` on every host importing
  `profile-default`, with a new store path per revision. On torrent
  several `…-secrets.yaml` paths sit at `0444 root:root`, retained until
  GC collects the generations referencing them.

  On a **private** repo this would matter a lot: it would mean the
  ciphertext escapes whatever access control the repo has, onto every
  host, world-readable. On a public repo it is largely moot — the same
  bytes are already downloadable by anyone — which is why this is LOW
  rather than the MEDIUM it would otherwise be. It is recorded for two
  reasons. First, it forecloses "make the repo private" as a fix for
  F-P8-01 or F-P8-02: the store copies and every existing clone remain.
  Second, if the repo ever *does* go private, this becomes the live
  version of the same problem and should be re-rated then.
- **Proposed fix:** none needed while the repo is public. Record the
  mechanism in `docs/procedures/secrets.md` alongside F-P8-02's pairing
  rule, so the "just make it private" instinct is answered in writing.
  If it ever becomes relevant, sops-nix supports a string path with
  `sops.validateSopsFiles = false` to keep the file out of the store,
  at the cost of build-time validation — probably not worth it, since
  that validation catches a missing key before a switch on a host you
  are not sitting at.
- **Fix risk:** n/a.
- **Owner:** P8, documentation only.

### F-P8-17 — mistyped commands fetch and execute arbitrary nixpkgs packages

- **File:** `modules/home-manager/tooling.nix:146-148,164-166`,
  `modules/profiles/default.nix` (comma), `:174`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening / needed-used
- **Reachability:** A7 — anything that can put text on the interactive
  shell's stdin, including a pasted command.
- **Rule:** n/a
- **Finding:** two related conveniences in the shared fish config:

  - `__fish_command_not_found_handler.body = "comma $argv[1]"` — every
    unrecognised command becomes a network fetch and execution of a
    nixpkgs package of that name. `programs.command-not-found.enable =
    false` (`default.nix:174`) confirms this is deliberate. A typo, or a
    pasted line whose first token is attacker-chosen, runs a binary that
    was not on the system a moment earlier. nixpkgs is a trusted source
    and the build is sandboxed, so this is arbitrary *nixpkgs*, not
    arbitrary code — which still includes plenty you would not want run.
  - `ns` runs `nix shell 'nixpkgs/nixos-unstable#'{$argv} --impure` — an
    unpinned indirect registry reference (F-P8-15) resolved live, with
    `--impure`, deliberately bypassing the flake lock. That is the
    function's purpose, but it means `ns` runs code from a nixpkgs
    revision no lock file records.

  Both are ergonomic choices, both documented in
  `docs/architecture.md`, and neither is wrong for an interactive
  desktop. They are listed because "what executes code the flake lock
  does not cover" is a question this part must answer, and these are the
  two answers.
- **Proposed fix:** decision required; "accept" is reasonable. If
  tightening is wanted, make the comma handler confirm before running,
  keeping the convenience and removing the silent-execution property.
  Either way, record the decision in `docs/hardening.md`.
- **Fix risk:** a confirming handler is mildly annoying on a machine
  built for speed; if it annoys it will be reverted, which is worse than
  not doing it.
- **Owner:** P8, informational; user decision.

### F-P8-18 — `vps_caddy_env` is declared, decrypted to disk, empty, and consumed by nothing

- **File:** `hosts/vps/configuration.nix:477`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** n/a — the value is empty.
- **Rule:** §7.4.
- **Finding:** `sops.secrets.vps_caddy_env = { }; # TODO: populate with
  DNS provider API token if using DNS-01 challenges`. The only declared
  secret with no consumer: nothing references
  `config.sops.secrets.vps_caddy_env.path`, and Caddy's service has no
  `EnvironmentFile`. It nonetheless evaluates to a real declaration
  (`mode=0400 path=/run/secrets/vps_caddy_env`), so
  `sops-install-secrets` decrypts and writes it on every vps activation.
  Its value is the literal empty string, visible without decryption
  because sops leaves an empty value unencrypted.

  Harmless as it stands, and worth removing because it is the shape that
  hurts later: a placeholder that decrypts on every activation, which
  nobody will remember is a placeholder once it has a value.
- **Proposed fix:** delete the declaration. If DNS-01 is wanted later,
  add it back together with the Caddy `EnvironmentFile` that uses it, so
  the two never exist apart. Drop the key from `secrets/secrets.yaml`
  during F-P8-01's restructure.
- **Fix risk:** none; nothing reads it.
- **Owner:** P8; the line is in `hosts/vps/configuration.nix` —
  coordinate with **P2**.

### F-P8-19 — `isoimage`'s tailnet identity is dead in three places at once

- **File:** `docs/tailscale-acl.json:23,37,38,46,52,58,79,86,87`,
  `secrets/secrets.yaml` (`tailscale_authkey_isoimage`),
  `modules/flake/hosts.nix:88-98`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** n/a.
- **Rule:** §7.4.
- **Finding:** `tag:isoimage` appears in `tagOwners`, in all four grants
  (as both `src` and `dst`) and in both `ssh` rules — nine occurrences.
  A `tailscale_authkey_isoimage` key sits in `secrets/secrets.yaml`. No
  such device can exist: `isoimage`'s module list is
  `[ hosts/isoimage/configuration.nix, copyparty-iso ]` with no
  `profile-default`, so no tailscale and no sops-nix. Evaluated:
  `services.tailscale.enable = false`, and `config.sops` does not exist
  as an option. `tailscale status` confirms no isoimage node.

  The design is right — you do not want an ISO carrying a tailnet auth
  key. The finding is that three places still describe a device the
  architecture deliberately does not create, one of them a security
  policy file where a phantom entry makes the real entries harder to
  audit.
- **Proposed fix:** remove `tag:isoimage` from
  `docs/tailscale-acl.json` and from the console, and remove
  `tailscale_authkey_isoimage` from `secrets/secrets.yaml` — **revoking
  the auth key in the Tailscale console first** (F-P8-11: an unused auth
  key that still exists is adversary A5's "over-broad auth key"). Add a
  note to `hosts/isoimage/README.md` or the ACL comment recording that
  isoimage is deliberately off-tailnet.
- **Fix risk:** none, provided the console tag is removed too and not
  just the file — see F-P8-07.
- **Owner:** P8, with P4 for the doc note.

### F-P8-20 — `permittedInsecurePackages` carries a stale EOL Electron and a nonsense empty entry

- **File:** `modules/flake/pkgs.nix:7-9,16`
- **Severity:** INFO
- **Confidence:** PLAUSIBLE that `electron-39.8.10` now has no consumer;
  CONFIRMED that the entry is fleet-wide and that `[ "" ]` is
  meaningless.
- **Axis:** needed-used
- **Reachability:** A7 — an EOL browser engine rendering untrusted
  content in the user's session, *if* anything still pulls it.
- **Rule:** new-rule candidate.
- **Finding:** `flake.pkgsUnstable` sets
  `permittedInsecurePackages = [ "electron-39.8.10" ]`. Because
  `pkgs.nix` instantiates the single nixpkgs every host draws from, the
  permit applies fleet-wide — servers included — not just to the desktop
  that prompted it.

  The likely original consumer was `obsidian`
  (`modules/home-manager/tooling-desktop.nix:24-28`), but against the
  pinned nixpkgs `obsidian` evaluates cleanly *without* the permit —
  verified by importing the pinned tree with only `allowUnfree` set and
  taking `obsidian.drvPath` successfully. `wootility`, `via`, `vial`,
  `bitwarden-cli`, `gnome-boxes` and `obs-studio` are likewise clean.
  Only `electron_39` itself fails, and nothing tested reaches it. I
  could not prove *no* package in any closure needs it without
  re-evaluating all five against a permit-free nixpkgs, so this stays
  PLAUSIBLE — but the balance of evidence is that the entry outlived the
  upgrade that fixed it and now stands by to permit an EOL Chromium the
  moment anything pulls `electron_39` again.

  Separately, `flake.pkgsStable` sets `permittedInsecurePackages = [ "" ]`
  — an empty string matching no package. Harmless, but it reads
  intentional and will confuse the next reader.
- **Proposed fix:** delete both. Remove `"electron-39.8.10"` and run
  `nixos-rebuild build --flake .#torrent` and `.#thinkpad`; if something
  still needs it the build fails naming the offending package, which is
  exactly the information the entry currently suppresses. Delete
  `[ "" ]` outright. If a permit is genuinely needed, re-add it with a
  comment naming the consumer and the date.
- **Fix risk:** the build fails loudly if a consumer exists — the
  intended outcome, not a regression. No runtime risk either way.
- **Owner:** P8.

### F-P8-21 — supply-chain provenance: five direct inputs are individuals' repos, three transitive nixpkgs revisions are unfollowed

- **File:** `flake.nix:5-45`, `flake.lock`
- **Severity:** INFO
- **Confidence:** CONFIRMED for the inventory; the trust judgements are
  judgements.
- **Axis:** needed-used / hardening
- **Reachability:** A6 — a malicious flake input. Low probability, total
  impact.
- **Rule:** n/a — inventory, for the record.
- **Finding:** full table in §4. Points worth pulling out:

  - **Nothing is unpinned.** All 44 nodes in `flake.lock` carry an
    explicit `rev` and `narHash`. No `path:` inputs, no unlocked refs,
    no `--impure` in the flake itself.
  - **The binary-cache posture is clean, and is the strongest single
    property found in this part.** Every host evaluates to
    `substituters: ["https://cache.nixos.org/"]`, the single official
    `trusted-public-keys` entry, `trusted-substituters: []`,
    `require-sigs: true`, `sandbox: true`. No third-party cache anywhere
    — no cachix, no attic, no per-project `nixConfig` — which closes off
    the most direct "arbitrary binary as root" path entirely.
    `trusted-users` is `["root"]` everywhere except vps (F-P8-13) and
    isoimage (installer default).
  - **Five direct inputs are an individual's personal repository:**
    `stylix` (danth), `sops-nix` (Mic92), `nvf` (notashelf),
    `nix-flatpak` (gmodena), `import-tree` (vic). Two are load-bearing
    in a way worth naming: `sops-nix` runs at activation on every host
    and decrypts every secret, and `import-tree` is how *every* module
    in this repo is discovered. All five are widely used and none is
    suspicious; the point is that "widely used" and "has an organisation
    behind it" are different properties, and the lock file is the only
    thing between a compromised maintainer account and homelab's
    unattended root update (F-P0-01, F-P8-15).
  - **`copyparty` is `github:9001/copyparty`** — an individual, but the
    software's own upstream, which is the right source. Used only by
    isoimage.
  - **Three nixpkgs revisions enter transitively without a `follows`:**
    `impermanence` brings its own `nixpkgs` (`e4bae1bd`) and
    `home-manager` (`c47b2cc6`); `plover-flake` brings `nixpkgs_2`
    (`0e251e24`) and, via `treefmt-nix`, `nixpkgs_3` (`4533d929`).
    `nix-flatpak` has no nixpkgs input. `impermanence`'s is inert (a
    pure module set), but `plover-flake` actually *builds* plover from
    `nixpkgs_2`, so packages from a second nixpkgs land in both PC
    closures. Twelve of the fifteen direct inputs follow correctly.
  - **Two non-GitHub sources:** `flake-compat` from
    `git.lix.systems/lix-project` (via `nvf`) and `gnome-shell` from
    `gitlab.gnome.org` (via `stylix`). Both legitimate, both a different
    availability and trust story.
  - **`nix-community/NUR` is in the tree** via `stylix`. NUR is
    explicitly user-contributed and unreviewed. Whether anything from it
    reaches a host closure is PLAUSIBLE-unknown — stylix's `nur` usage
    appears confined to its own checks, unverified against a build.
  - **`via` is a repackaged AppImage** of an unfree binary whose source
    upstream does not release (`package.nix`: *"Upstream claims to be
    GPL-3 but doesn't release source code"*), fetched by hash from a
    GitHub release, in both PC closures. Pinned, so reproducible;
    opaque, so unreviewable. See F-P8-08 for the actionable half.
  - **Public-repo note:** every pin above is published, so the lag
    between an upstream security fix and this repo's lock bump is
    directly observable by anyone. That is not a reason to stop
    publishing, but it does mean "we are a few weeks behind on input X"
    is public information, and it slightly raises the value of homelab's
    automated `flake-update-test` actually running.
- **Proposed fix:** three cheap ones. (a) Add
  `impermanence.inputs.nixpkgs.follows = "nixpkgs-unstable"` and
  `plover-flake.inputs.nixpkgs.follows = "nixpkgs-unstable"`, collapsing
  three extra nixpkgs instances to zero — smaller closure, one fewer
  revision to reason about. (b) Record in `docs/hardening.md` that no
  substituter other than `cache.nixos.org` may be added without an
  explicit decision, since that is currently true by accident rather
  than by rule. (c) Note in the same place that the flake lock is the
  fleet's only supply-chain control, which is the honest framing given
  F-P0-01.
- **Fix risk:** (a) can break `plover-flake`, which may depend on
  something specific to its own pin — `plover-full` is a large Python
  application and `follows` overrides are exactly where those break.
  Build both PC hosts before landing it, and be ready to revert that one
  line.
- **Owner:** P8.

### F-P8-22 — three small stale artefacts around the SSH key model

- **File:** `modules/flake/vars.nix:7`, `modules/profiles/PC.nix:165`,
  plus `/home/lilijoy/.ssh/id_rsa` (not in the repo)
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used / documentation
- **Reachability:** n/a individually; each is a piece of F-P8-04's
  picture.
- **Rule:** §7.4.
- **Finding:** three things noticed while confirming the
  `publicSshKeys` count:

  1. **`vars.nix:7`** labels the first key `lilijoy@nixos-thinkpad` —
     the host's former hostname. Cosmetic, but the `.sops.yaml` anchor
     `&nixos-thinkpad` carries the same stale name (F-P8-03, F-P8-05),
     so the two are probably the same vintage and knowing that may help
     the attribution work.
  2. **`PC.nix:165`** sets
     `sessionVariables.SSH_AUTH_SOCK = "/home/<user>/.bitwarden-ssh-agent.sock"`
     — a literal `<user>` placeholder never substituted. The path does
     not exist, so `SSH_AUTH_SOCK` points at nothing and every `ssh`
     falls back to on-disk keys. This is the mechanism F-P8-04's option
     (b) depends on, and it has never worked. `vars.username` is already
     available in that file, so the fix is a one-token substitution.
  3. **`/home/lilijoy/.ssh/id_rsa`** — a 3072-bit RSA key
     (`SHA256:vVNQx1bJv9kdpjUKyTD7nI9bZNKEKKS7Ec1d0D9Sego lilijoy@torrent`,
     dated 2025-07-20) in no `authorizedKeys` list in this repo and
     unexplained anywhere in `docs/`. May be a GitHub or third-party
     key; may be dead. Unmanaged either way.
- **Proposed fix:** (1) update the comment to `lilijoy@thinkpad`.
  (2) change the literal to
  `"/home/${vars.username}/.bitwarden-ssh-agent.sock"`, then check
  whether the agent is actually running — if not, remove the variable
  rather than fix it, since a broken `SSH_AUTH_SOCK` and an absent one
  behave alike but read very differently. (3) user identifies `id_rsa`
  and deletes it if dead; 3072-bit RSA is below what you would generate
  today.
- **Fix risk:** (2) if the agent *is* running and the variable starts
  working, `ssh` stops using `~/.ssh/id_ed25519` and starts using
  whatever the agent holds — which presents as sudden authentication
  failure against homelab and vps if the agent lacks that key. Check the
  agent's contents first.
- **Owner:** P8 for (1) and (2); user for (3).

### F-P8-23 — `tmux.nix` claims fleet-wide use; only the server profile imports it

- **File:** `modules/home-manager/tmux.nix:6-8`,
  `modules/profiles/server.nix:56`, `modules/profiles/PC.nix:152-157`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** documentation
- **Reachability:** n/a.
- **Rule:** §7.5 — documentation asserting something the config does not
  implement.
- **Finding:** the module header reads *"Shared by every host (root on
  servers, lilijoy on PCs)…"*. It is not.
  `homeManagerModules.tmux` is imported only by `server.nix:56`, into
  root's home-manager profile on homelab and vps. `PC.nix:152-157`
  imports `tooling`, `tooling-desktop`, `virt-manager`, `claude-code`
  and plover — not `tmux`. So `lilijoy` gets the `tmux` *binary*
  (`default.nix:44`) with no configuration, the opposite of the stated
  intent.

  Not a security issue on its own. Listed because it is the same shape
  as the failure modes that *are*, and because the config it silently
  does not apply includes `continuum` with `@continuum-restore 'on'`,
  which re-executes saved pane command lines from a file in the home
  directory at tmux server start. On root's profile that file is
  root-owned and fine. Someone "fixing" the comment by adding `tmux` to
  `PC.nix` without noticing would be enabling auto-restore of saved
  command lines in `lilijoy`'s home — writable by A7 — a small but real
  new execution path. Better to know before the change than after.
- **Proposed fix:** decide which way it resolves. Either correct the
  comment to "root on server hosts", or add
  `homeManagerModules.tmux` to `PC.nix` — and if the latter, review the
  `continuum` auto-restore setting for a user-writable home first.
- **Fix risk:** adding it to `PC.nix` changes `lilijoy`'s tmux behaviour
  on both laptops (prefix `C-a`, vi keys, auto-restore) — user-visible
  and mildly disruptive, not dangerous.
- **Owner:** P8; the import lives in `modules/profiles/PC.nix` —
  coordinate with **P1**.

---

## 3. Secrets table

All 31 keys in `secrets/secrets.yaml`. "Declared" means a
`sops.secrets.<name>` exists somewhere; only declared secrets are
decrypted to `/run/secrets`. Mode/owner/group are **evaluated** values.

**Every one of the 31 is decryptable by all seven current recipients
(F-P8-01), and the ten marked ✱ are additionally decryptable by three
retired vps age keys from public history (F-P8-02).** The "host" column
is where a secret is *used*, not where it *can* be read.

| # | key | declared by | consumer | mode | owner:group | still used? |
|---|---|---|---|---|---|---|
| 1 | `git_username` | thinkpad, torrent, homelab, vps | `sops.templates."git-identity"` → `programs.git.includes` | 0400 | root:root | yes |
| 2 | `git_email` | thinkpad, torrent, homelab, vps | same | 0400 | root:root | yes |
| 3 | `tailscale_authkey_thinkpad` | thinkpad | `services.tailscale.authKeyFile` | 0400 | root:root | yes |
| 4 | `tailscale_authkey_torrent` ✱ | torrent | same | 0400 | root:root | yes |
| 5 | `tailscale_authkey_homelab` ✱ | homelab | same | 0400 | root:root | yes |
| 6 | `tailscale_authkey_vps` | vps | same | 0400 | root:root | yes — **the one value rotated on 2026-08-25** |
| 7 | `tailscale_authkey_isoimage` | **nobody** | — | n/a | n/a | **no** (F-P8-19) |
| 8 | `homelab_backblaze_rclone_config` | homelab | `restic.backups.backblazeWeekly.rcloneConfigFile`; `rclone backend lifecycle` ExecStartPre | 0400 | root:root | yes |
| 9 | `homelab_backblaze_restic_password` ✱ | homelab | `restic.backups.backblazeWeekly.passwordFile` | 0400 | root:root | yes |
| 10 | `homelab_discord_webhook` ✱ | homelab | `myHealthAlerts.webhookUrlFile` | 0400 | **health-check:health-check** | yes |
| 11 | `homelab_zrepl_key` ✱ | homelab | `myZrepl.pull.remotes.{torrent,thinkpad}.identityFile` | 0400 | root:root | yes |
| 12 | `homelab_vps_deploy_key` ✱ | homelab | `myPushDeploy.identityFile` | 0400 | root:root | yes |
| 13 | `homelab_wireguard_private_key` ✱ | homelab | `wireguard.interfaces.wg0.privateKeyFile` | 0400 | root:root | yes |
| 14 | `wireguard_vps_homelab_psk` ✱ | homelab **and** vps | `peers[].presharedKeyFile`, both ends | 0400 | root:root | yes |
| 15 | `homelab_samba_android_smb_password` | homelab | `samba-user-provision.service` | 0400 | root:root | yes — **only secret with `restartUnits`** |
| 16 | `minecraft_username` | homelab | `sops.templates."minecraft-whitelist"` → container `environmentFiles` | 0400 | root:root | yes |
| 17 | `factorio_game_password` | homelab | `docker-factorio-{main,new}.preStart` | 0400 | root:root | yes |
| 18 | `factorio_token` | homelab | same | 0400 | root:root | yes |
| 19 | `factorio_username` | homelab | same | 0400 | root:root | yes |
| 20 | `cloudflare_octodns_token` ✱ | homelab | `sops.templates."octodns-env"` → `octodns-sync` `EnvironmentFile` | 0400 | **octodns:octodns** | yes |
| 21 | `vps_wireguard_private_key` ✱ | vps | `wireguard.interfaces.wg0.privateKeyFile` | 0400 | root:root | yes |
| 22 | `vps_discord_webhook` | vps | `myHealthAlerts.webhookUrlFile` | 0400 | **health-check:health-check** | yes |
| 23 | `vps_caddy_env` | vps | **nothing** | 0400 | root:root | **no** — empty placeholder (F-P8-18) |
| 24 | `torrent_backup_push_key` | **nobody** | — | n/a | n/a | **no** — pre-zrepl (F-P8-11) |
| 25 | `thinkpad_backup_push_key` | **nobody** | — | n/a | n/a | **no** — pre-zrepl (F-P8-11) |
| 26 | `cloudflare_tunnel_token_01` | **nobody** | — | n/a | n/a | **no** (F-P8-11) |
| 27 | `nextcloud_admin_pass` | **nobody** | — | n/a | n/a | **no** (F-P8-11) |
| 28 | `webdav_lilijoy` | **nobody** | — | n/a | n/a | **no** (F-P8-11) |
| 29 | `winapps_password` | **nobody** | — | n/a | n/a | **no** (F-P8-11) |
| 30 | `open_weather_key` | **nobody** | — | n/a | n/a | **no** (F-P8-11) |
| 31 | `restic` | **nobody** | — | n/a | n/a | **no** — superseded by #9 (F-P8-11) |

Per-host declaration counts: thinkpad 3, torrent 3, homelab 16, vps 7;
22 distinct declared, 9 orphaned.

**Derived files** (`sops.templates`), rendered under
`/run/secrets/rendered/` and symlinked to their `path`:

| template | host(s) | path | owner | consumer |
|---|---|---|---|---|
| `git-identity` | thinkpad, torrent | `/home/lilijoy/.config/git/identity` | lilijoy | `programs.git.includes` |
| `git-identity` | homelab, vps | `/root/.config/git/identity` | root | same, root's profile |
| `minecraft-whitelist` | homelab | default | root | container `environmentFiles` |
| `octodns-env` | homelab | default | octodns | `octodns-sync.service` |

**Per-host decrypt identities:**

| host | `sops.age.keyFile` | `generateKey` | `sshKeyPaths` |
|---|---|---|---|
| thinkpad | `/var/lib/sops-nix/key.txt` | true | `/etc/ssh/ssh_host_ed25519_key` — derived key is **not** a recipient |
| torrent | `/var/lib/sops-nix/key.txt` | true | same — **not** a recipient (F-P8-05) |
| homelab | null | false | `/etc/ssh/ssh_host_ed25519_key` → `&homelab3` ✓ |
| vps | null | false | `/etc/ssh/ssh_host_ed25519_key` → `&vps` ✓ |
| isoimage | — | — | no sops module at all |
| *(editing)* | `~/.config/sops/age/keys.txt` on torrent, **mode 0644** | — | PLAUSIBLY `&nixos-thinkpad` (F-P8-03) |

**Age recipients across all 72 published revisions — 14 total, 7 current:**

| recipient | status | revisions | notes |
|---|---|---|---|
| `age1758lfex…d7cl8` `&nixos-thinkpad` | current | **72 / 72** | in every revision since 2024-07-05; no host key survives that — PLAUSIBLY the editing identity (F-P8-03) |
| `age18t8txuc…h73ad` `&homelab3` | current | 34 | ✓ homelab's live SSH host key |
| `age1zn0nrxa…akg9d` `&thinkpad-ssh` | current | 33 | ✗ **not** thinkpad's current host key (F-P8-05) |
| `age1gsmfmtv…fhu2t` `&torrent-age` | current | 27 | unattributed |
| `age1llhdgjk…43eyq` `&thinkpad-machine` | current | 20 | unattributed |
| `age1nv3rufp…plwas` `&torrent-machine` | current | 15 | unattributed |
| `age13y33z6n…qegc8` `&vps` | current | 1 | ✓ vps's live SSH host key (2026-08-25) |
| `age1t8cfzav…we0auz` | **retired** | 44 | 2024-08 era |
| `age1t09qgr6…30zl32` | **retired** | 43 | 2024-08 era |
| `age1e4a5f20…lk25fx` | **retired** | 31 | 2024-07 era |
| `age1p6nhsn2…3fl6f8` | **retired** | 11 | **old vps** — decrypts 10 current values (F-P8-02) |
| `age1uc86th6…j2lqc4` | **retired** | 2 | **transient vps** — same |
| `age1sc4cn2k…8mt5aw` | **retired** | 1 | **transient vps** — same |
| `age1d29x545…namzz3` | **retired** | 1 | 2024-07-29 "changed age secretes key for reinstall" |

---

## 4. Flake-inputs table

15 direct inputs, all used at least once; 44 nodes in `flake.lock`,
every one locked to an explicit `rev` + `narHash`.

| input | source | pinned rev | follows | trust assessment |
|---|---|---|---|---|
| `nixpkgs-stable` | **indirect** `nixpkgs/nixos-26.05` → `releases.nixos.org` tarball | `02e08985` | n/a | upstream NixOS. Registry-resolved at update time (F-P8-15) |
| `nixpkgs-unstable` | **indirect** `nixpkgs/nixos-unstable` → tarball | `0e251e24` | n/a | same |
| `home-manager` | `github:nix-community/home-manager` | `83b7606d` | → nixpkgs-unstable ✓ | org, standard |
| `home-manager-stable` | `github:nix-community/home-manager` `release-26.05` | `09ae1b85` | → nixpkgs-stable ✓ | org, standard |
| `stylix` | `github:danth/stylix` | `1e6ccade` | → nixpkgs-unstable ✓ | **individual**. Largest transitive fan-out: pulls `nur` (unreviewed), `gnome-shell` from gitlab.gnome.org, 8 theme repos incl. 2 more individuals' |
| `sops-nix` | `github:Mic92/sops-nix` | `a8627b21` | → nixpkgs-unstable ✓ | **individual**, de-facto standard. **Runs at activation on every host and decrypts every secret** — highest-consequence input in the tree |
| `disko` | `github:nix-community/disko` | `ff8702b4` | → nixpkgs-unstable ✓ | org |
| `impermanence` | `github:nix-community/impermanence` | `7b1d382f` | **no follows** — own `nixpkgs` (`e4bae1bd`) + `home-manager` (`c47b2cc6`) | org. Extra nixpkgs inert (pure module set) but adds a revision |
| `nvf` | `github:notashelf/nvf` | `a213644c` | → nixpkgs-unstable ✓ | **individual**. Pulls `flake-compat` from `git.lix.systems`, `mnw` from `Gerg-L` |
| `nix-index-database` | `github:nix-community/nix-index-database` | `14d55b80` | → nixpkgs-unstable ✓ | org. Backs `comma` (F-P8-17) |
| `nix-flatpak` | `github:gmodena/nix-flatpak` | `20d42f0e` | no nixpkgs input | **individual** |
| `plover-flake` | `github:openstenoproject/plover-flake` | `3e7dcc0b` | **no follows** — own `nixpkgs_2` (`0e251e24`), `nixpkgs_3` (`4533d929`) via `treefmt-nix` | org (upstream project). **Actually builds packages** from a second nixpkgs into both PC closures |
| `copyparty` | `github:9001/copyparty` | `18791c57` | → nixpkgs-unstable ✓ | **individual**, but the software's own upstream. Used only by `isoimage` |
| `flake-parts` | `github:hercules-ci/flake-parts` | `427bf4bd` | `nixpkgs-lib` | org, standard |
| `import-tree` | `github:vic/import-tree` | `4ebb10ae` | no inputs | **individual**. **Discovers every module in this repo** — small but structurally load-bearing |

**Substituters and signing, all five hosts** — clean, no exceptions:

| setting | value |
|---|---|
| `substituters` | `["https://cache.nixos.org/"]` |
| `trusted-public-keys` | `["cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="]` |
| `trusted-substituters` | `[]` |
| `require-sigs` | `true` |
| `sandbox` | `true`, `sandbox-fallback: false` |
| `trusted-users` | `["root"]` on thinkpad/torrent/homelab; `["root","vps-deploy"]` on vps (F-P8-13); `["root","nixos"]` on isoimage (installer default) |
| `allowed-users` | `["@wheel"]` on thinkpad/torrent; `["root"]` on homelab/vps; `["*"]` on isoimage |

---

## 5. Checked and clean

Things examined that turned out fine, recorded so the next audit does
not re-derive them.

**Secret file permissions.** All 22 declared secrets evaluate to mode
`0400`. Nineteen are `root:root` and consumed by root-run units; the
three that are not — `homelab_discord_webhook` and `vps_discord_webhook`
(`health-check:health-check`) and `cloudflare_octodns_token`
(`octodns:octodns`) — are narrowed to their dedicated service user,
which is the correct direction. `neededForUsers` is `false` everywhere.
**No secret is readable more widely than its consumer needs at the
filesystem layer.** Every over-broad grant found in this part is at the
`.sops.yaml` recipient layer (F-P8-01), which is a cleaner separation
than it could have been — and it means the fix is concentrated in one
file rather than scattered across twenty declarations.

**`/run/secrets` layout on torrent.** `/run/secrets` →
`/run/secrets.d/21`; `/run/secrets.d` is `0751 root:keys`, so `other`
has `--x` (traverse, not list) and every file inside is `0400`. The
`keys` group is empty (`getent group keys`), so no service account has
listing rights either. Correct.

**The `sops.templates` indirection.** Templates render to
`/run/secrets/rendered/<name>` and are reached via a symlink at the
declared `path` — confirmed live:
`/home/lilijoy/.config/git/identity` → `/run/secrets/rendered/git-identity`.
The raw `git_username`/`git_email` secrets stay `0400 root:root` while
only the *derived* file is owned by `lilijoy`. Right layering: the user
never gets read access to the underlying secret files.

**`security.wrappers` across all five hosts.** No unexpected setuid
binary anywhere. PC hosts carry the expected desktop/virtualisation set
(`mount`/`umount`, `fusermount`, `pkexec`, `su`, `passwd`, `chsh`,
`newgrp`/`sg`, `unix_chkpwd`, `qemu-bridge-helper` from libvirtd,
`mullvad-exclude` from `services.mullvad-vpn`), plus capability-only
wrappers that are correctly capabilities rather than setuid
(`gamemoded` and `kwin_wayland` `cap_sys_nice`, `ksgrd_network_helper`
`cap_net_raw`, `ksystemstats_intel_helper` `cap_perfmon`,
`spice-client-glib-usb-acl-helper` `cap_fowner`, `newuidmap`/`newgidmap`
`cap_setuid`/`cap_setgid`). Servers are narrower. On homelab
`newuidmap`/`newgidmap` are full setuid rather than capability-based —
nixpkgs' choice on the stable channel, not this repo's. `isoimage` is
the only host with real `sudo`/`sudoedit` wrappers, correct for
installer media and consistent with `docs/hardening.md`'s "no real sudo"
rule applying to the managed hosts.

**`modules/nixos/wooting.nix`'s udev rule.** Read from the pinned
nixpkgs: `wooting-udev-rules` ships `TAG+="uaccess"` with no `MODE=` and
no `GROUP=`, scoped to three specific vendor IDs — the minimal correct
form for a HID device. The brief asked whether this rule was
over-permissive; it is not. The problems in that area are `via`/`vial`
(F-P8-08) and the `input` group (F-P8-09), neither of which is this rule.

**`modules/flake/checks.nix`.** Two `runNixOSTest` VM checks
(`zrepl-replication`, `zfs-space-guard`), both taking the module under
test from the flake registry rather than re-importing by path. Nothing
executes at eval time; nothing fetches anything.

**`modules/flake/devshell.nix`.** All standard tooling from the pinned
nixpkgs, with `sops`/`age`/`ssh-to-age` present for the documented
manual-secret workflow and no wrapper or alias around them (matching
`docs/procedures/secrets.md`). The `shellHook` does exactly two things —
`core.hooksPath = .githooks` and `pull.rebase true`, both local-only and
idempotent. Note the consequence rather than a fault: `direnv allow`
(`.envrc` is `use flake`) opts you into running the repo's tracked
hooks, so a hostile `origin/master` reaches the developer machine at the
next commit — F-P0-01's blast radius, not a new hole. On a public repo
this is worth remembering when reviewing an outside PR: `.githooks/`
changes in a PR are code that runs on your machine after merge.

**`.githooks/pre-commit`.** Blocks an unencrypted `secrets.yaml` (no
`sops:` block), private-key PEM headers, `AGE-SECRET-KEY-1…`, and
AWS/Slack/GitHub token shapes. A reasonable backstop, and per §4.7 it
has held — no plaintext has ever been committed. Two observations,
neither a finding: it checks `basename == secrets.yaml`, so a
differently-named file under `secrets/` skips the sops check even though
`.sops.yaml`'s `path_regex` allows `.json`/`.env`/`.ini`; and
`--no-verify` bypasses it entirely, correct for a backstop but meaning
it is not a control. F-P0-08 proposes strengthening it; the extension to
cover the other three allowed extensions is cheap and worth doing at the
same time.

**`.githooks/pre-push`.** Builds every affected host before allowing a
push. Its path filter still lists the pre-dendritic `profiles/` and
`services/` directories, which no longer exist — harmless, `modules/`
covers both.

**`modules/flake/{systems,hosts,vars}.nix`.** `systems.nix` is one line.
`hosts.nix` matches `docs/architecture.md`'s table exactly; per-host
`specialArgs` divergence is explicit and `isoimage`'s narrowing (no
`inputs`) deliberate. `vars.nix` has no stale entries beyond the comment
in F-P8-22: `zreplPullerKey` is consumed by both source hosts, and
`username`, `domain`, both `gids` and `persistRoot` are all live.

**`modules/nixos/tooling.nix`.** `environment.shellAliases = lib.mkForce
{ }` clears NixOS' default aliases. Checked specifically because it is
the shape of a §7.2 silent-inertness bug: in the pinned nixpkgs,
`security.run0.enableSudoAlias` installs a `run0-sudo-shim` *package*
into `environment.systemPackages`, not a shell alias, so the
`mkForce {}` does **not** remove the sudo→run0 shim. The rest is editor
and shell configuration with no privilege surface.

**`modules/nixos/kde.nix`.** Plasma 6 + SDDM Wayland, four extra
packages, `programs.partition-manager.enable` (polkit-gated, not
setuid). No group grants, no udev rules, no ports.

**`modules/nixos/virtual-machines.nix`.** Grants `lilijoy` the
`libvirtd` group, root-equivalent-adjacent by design — the system
libvirt socket can define a VM with a raw host block device attached.
Confirmed live (`id lilijoy` includes `67(libvirtd)`). Inherent to using
virt-manager against `qemu:///system`, which
`modules/home-manager/virt-manager.nix` explicitly configures, so it is
the cost of the feature rather than a misconfiguration; §4.3 already
counts `lilijoy` → root on the laptops. `spiceUSBRedirection` correctly
produces a `cap_fowner` wrapper rather than setuid root.

**`claude-code.nix`'s statusline script.** A `writeShellApplication`
with `runtimeInputs = [ jq git coreutils ]`, so its `PATH` is pinned
rather than inherited — exactly the problem the header comment says it
solves. Harness JSON reaches only `jq` filters, integer comparisons and
`printf "%s"`; no `eval`, no unquoted expansion into command position,
no path built from input. `bashOptions = [ ]` is deliberate and
explained. No injection surface.

**`modules/home-manager/{tmux,virt-manager}.nix`.** `virt-manager.nix`
is four lines of dconf. `tmux.nix` is configuration only — see F-P8-23
for the comment discrepancy and the `continuum` note.

**`modules/home-manager/tooling.nix` / `tooling-desktop.nix`.** No
secret handling, no credentials, no network services beyond
`services.kdeconnect` — home-manager's version starts the daemon but
does **not** open the firewall (`programs.kdeconnect` is the NixOS
option that would, and it is unused), and the PC hosts' evaluated
firewall has no 1714-1764 range, so it is closed. The `git.includes`
pointing at the sops-rendered identity is correct and host-agnostic.
See F-P8-17 for the two shell functions that execute unpinned code.

**`files/`.** Sixteen static assets, one
(`gruvbox-dark-rainbow.png`) referenced from
`modules/profiles/PC.nix:242` and the rest consumed by external tools,
exactly as `files/README.md` documents. Scanned: no credentials, no
keys, no tokens — which matters more than usual, since the directory is
public. The `.vil` files are Vial keyboard layouts and are the evidence
for which keyboards F-P8-08's narrowed udev rule should name.

**`docs/tailscale-acl.json`'s `tagOwners` and `autoApprovers`.** All
five tags owned by `autogroup:admin`; `autoApprovers` scoped to
`tag:homelab` for both the exit node and the single `192.168.1.0/24`
route, with a comment explaining why a tag rather than a user (survives
account suspension). Correct, and narrower than it had to be.
`tag:vps` deliberately absent from every `src` — vps cannot initiate to
the tailnet.

**Nix binary-cache posture.** See §4's second table. No third-party
substituter, no extra trusted key, `require-sigs` on, sandbox on, every
host. The strongest single property found in this part.

**`modules/flake/pkgs.nix`'s `allowUnfree = true`.** Fleet-wide on both
channels. Expected for a desktop fleet running Steam, nvidia and
Obsidian; noted rather than raised. The `permittedInsecurePackages`
entries in the same file are F-P8-20.

---

## 6. Severity summary

| severity | count | ids |
|---|---|---|
| CRITICAL | 2 | F-P8-01, F-P8-02 |
| HIGH | 3 | F-P8-03, F-P8-04, F-P8-05 |
| MEDIUM | 6 | F-P8-06, F-P8-07, F-P8-08, F-P8-09, F-P8-10, F-P8-11 |
| LOW | 6 | F-P8-12, F-P8-13, F-P8-14, F-P8-15, F-P8-16, F-P8-17 |
| INFO | 6 | F-P8-18, F-P8-19, F-P8-20, F-P8-21, F-P8-22, F-P8-23 |
| **total** | **23** | |

By primary axis: hardening 11, needed-used 7, documentation 5.

**Remediation ordering.** F-P8-02 first and out of band — it is the only
finding in this part where the exposure is already real rather than
conditional, and the fix (provider-side rotation) is independent of
every other change. F-P8-03's `chmod 600` is free and should go with it.
Then F-P8-01's restructure, which F-P8-05's attribution work is a
prerequisite for. Everything else can follow the audit's normal
schedule.

## 7. Cross-references for other parts

- **P1** (`modules/profiles/PC.nix`) — owns the file behind F-P8-08
  (`services.udev.packages`), F-P8-09 (where the `input` grant should
  land), F-P8-22(2) (the `SSH_AUTH_SOCK` placeholder) and F-P8-23 (the
  `tmux` import).
- **P2** (vps) — F-P8-06's highest-value fix is vps's
  `networking.firewall.trustedInterfaces = ["tailscale0"]`, not the ACL.
  F-P8-13 adds two more root-equivalences to F-P0-02's picture.
  F-P8-18 deletes a line from `hosts/vps/configuration.nix`. And note
  F-P8-01: root on vps — the internet-facing host — currently decrypts
  all 31 fleet secrets, which materially raises the stakes on everything
  P2 is auditing.
- **P3** (homelab) — F-P8-14's wireguard `restartUnits`, which becomes
  load-bearing once F-P8-02's rotation happens. homelab's tailnet-facing
  surface is `22, 445, 2049, 8096, 25565` tcp; NFS and SMB are
  authorised by uid/gid and a single password, with the tailnet as the
  only other control — bears on the standing intrusion-detection
  question in `TODO.md`.
- **P4** (isoimage, game servers) — F-P8-19 (isoimage is deliberately
  off-tailnet; the ACL and secrets file do not know that). Factorio's
  `preStart` writes three secret values in plaintext into
  `/srv/factorio/*/config/server-settings.json`; that file's mode is
  unverified from here and worth checking.
- **P5** (laptops) — F-P8-04 is a shorter A7 → fleet-root path than
  F-P0-03 and needs no privilege escalation on the laptop; please
  confirm independently. F-P8-03 is a second, worse one: a mode-0644 age
  identity in the same home directory. F-P8-01 makes root on either
  laptop equivalent to every secret the fleet has ever held.
- **P6** (backups) — F-P8-01 independently confirms your F-P6-01; the
  remediation design lives here. Note F-P8-02: `homelab_zrepl_key` and
  `homelab_backblaze_restic_password` are both in the set of ten
  currently-live values decryptable by three retired vps keys from
  public history. That is a path to your delete-authority concern that
  does not go through zrepl at all, and it is the strongest argument
  available for rotating both.
- **P7** (deploy path) — F-P8-15: `nix flake update` in
  `flake-update-test` resolves `nixpkgs` through the flake registry over
  the network, as root, unattended — one indirection further out than
  F-P0-01 accounts for. Also F-P0-08's proposed `.githooks/` secret scan
  is yours; F-P8's note in §5 suggests extending the existing
  `pre-commit` check to the other three extensions `.sops.yaml` allows.
