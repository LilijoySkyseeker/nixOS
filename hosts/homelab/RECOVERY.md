# homelab — recovery runbook

Covers recovery once homelab has landed the FDE/Secure Boot/TPM2 plan
in `TODO.md` ("full-disk encryption + Secure Boot + TPM2 auto-unlock +
impermanence rollout"). `hosts/homelab/disko.nix` already has the LUKS
layer (5 containers: `zroot-crypt` on the root NVMe, `zdata-a-crypt`/
`zdata-b-crypt` on the zdata mirror, `zbackup-c-crypt`/`zbackup-d-crypt`
on the zbackup mirror). Phase 1 (lanzaboote Secure Boot) and the
post-install TPM2 enrollment step have not shipped yet as of this
writing — commands below that assume Secure Boot/TPM2 are configured
are **not yet applicable**.

This runbook is a draft pending a real dry run (spare disk or VM, per
this repo's "test remote deploys in a VM first" convention) — treat
each command as a starting point to verify, not as tested truth, until
that dry run happens and this note is removed. All `systemd-cryptenroll`
flag syntax below was checked against the installed `systemd-cryptenroll(1)`
man page; `enrollRecovery`'s behavior was checked against disko's actual
source at this flake's pinned rev
(`lib/types/luks.nix` @ `ff8702b4de27f72b4c78573dfb89ec74e36abdf1`).

## 0. Prerequisites — must already be true before any of this works

- The recovery passphrase(s) `enrollRecovery` generated for each LUKS
  container **at this host's original install** are escrowed
  somewhere reachable without needing to decrypt this host's own disks
  first (see "Escrow locations" below). These are only useful for
  Scenario 1/2 below (same disks, same LUKS headers) — a full disk
  replacement (Scenario 3) generates brand-new ones, see that section.
- An sbctl PKI backup for this host exists outside the host itself
  (see "Escrow locations").
- This host's SSH host key / sops age identity is backed up outside
  the host itself (not just present on it) — see Scenario 3's sops
  section for why this matters.
- homelab's own `restic-backups-backblazeWeekly` job
  (`hosts/homelab/configuration.nix`) has a recent
  `/var/lib/restic-backups-backblazeWeekly/last-success` timestamp,
  and `zpool status`/sanoid snapshots on `zroot`, `zdata`, `zbackup`
  look healthy. Don't attempt a real recovery believing backups are
  current without checking this first.

## Finding the right device for a given LUKS container

`systemd-cryptenroll` takes the underlying LUKS-formatted block device
(NOT `/dev/mapper/<name>`, which is only the decrypted view once
open). To find it for a given container name (`zroot-crypt`,
`zdata-a-crypt`, `zdata-b-crypt`, `zbackup-c-crypt`, `zbackup-d-crypt`
— see `hosts/homelab/disko.nix`):

```
sudo cryptsetup status <container-name> | grep device:
```

(e.g. `sudo cryptsetup status zroot-crypt | grep device:` while the
container is open/unlocked.) Don't guess the `-partN` suffix — disko
assigns it, and it can differ per disk.

## 1. Scenario: TPM2 unseal failure

(Motherboard replaced, TPM cleared/reset, a BIOS/firmware update
shifted PCR values, or the TPM itself died.) The machine should fall
back to a passphrase prompt automatically at the LUKS unlock stage —
this depends on Phase 1/TPM2 enrollment already being live, and on the
original `enrollRecovery` slot still being intact (it is, by design —
`systemd-cryptenroll --wipe-slot=tpm2` only removes TPM2-type slots,
never the recovery-key slot).

1. At the boot-time LUKS prompt, enter the escrowed recovery
   passphrase from this host's original install (see "Escrow
   locations").
2. Once booted, confirm the new hardware/firmware state is actually
   trustworthy (you intended this change; it isn't sitting there
   because of tampering) before resealing.
3. Re-enroll a fresh TPM2 slot and wipe the stale one in a single
   command (the documented systemd pattern for updating an
   enrollment — enrollment happens first, then the old TPM2 slot(s)
   are wiped, and the *new* slot is never touched by the wipe):
   ```
   sudo systemd-cryptenroll <device> \
     --wipe-slot=tpm2 \
     --tpm2-device=auto \
     --tpm2-pcrs=0+2+7+11
   ```
   Repeat per LUKS container that has a TPM2 slot (zroot at minimum;
   also the zdata/zbackup containers per the "encrypt everything"
   decision in `TODO.md`).
4. Reboot once to confirm TPM2 auto-unlock works again without a
   prompt, for every container.

PCR selection (`0+2+7+11`): 0 = firmware, 2 = option ROMs/plugin
firmware, 7 = Secure Boot state (this is the one that makes TPM
auto-unlock meaningfully depend on Secure Boot, not just "was a TPM
present"), 11 = unified kernel image measurement (systemd's default
for UKI-based boots). This is a starting point, not verified against
this repo's actual lanzaboote config yet since Phase 1 hasn't landed —
revisit once it has.

## 2. Scenario: Secure Boot key loss

(sbctl-generated keys lost/not backed up, or a fresh lanzaboote
signing setup is needed on this hardware.) Recoverable, not a
lockout — but it forces a passphrase-fallback boot in the middle since
PCR7 changes once new keys are enrolled.

1. Regenerate keys:
   ```
   sudo sbctl create-keys
   ```
2. Enroll in firmware (ideally from UEFI Setup Mode):
   ```
   sudo sbctl enroll-keys -m
   ```
3. Re-sign the current boot chain:
   ```
   sudo sbctl sign-all
   sudo sbctl verify
   ```
   (`nixos-rebuild switch`/`boot` should also trigger signing
   automatically via lanzaboote's activation hook once Phase 1 is
   configured — run this explicitly if unsure it happened.)
4. Reseal every TPM2 LUKS slot against the new PCR7 (same command as
   Scenario 1 step 3, one boot in between needs the passphrase
   fallback since the old TPM2 seal is now stale):
   ```
   sudo systemd-cryptenroll <device> --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=0+2+7+11
   ```
5. Confirm the sbctl PKI directory (check which path this repo's
   lanzaboote module actually resolves to once Phase 1 lands — current
   sbctl versions use `/var/lib/sbctl`, older ones `/etc/secureboot`)
   is captured in this host's `environment.persistence` and restic
   backup paths, so this isn't a recurring single point of loss.

## 3. Scenario: full hardware failure / disk death

homelab has three pool roles: `zroot` (OS, on `zroot-crypt`), `zdata`
(bulk storage mirror, on `zdata-a-crypt`/`zdata-b-crypt`), `zbackup`
(local backup mirror, target of syncoid from `zdata`/`zroot`/
thinkpad/torrent, on `zbackup-c-crypt`/`zbackup-d-crypt`). Losing the
`zroot` NVMe is the most common case below; losing one HDD out of a
mirrored `zdata`/`zbackup` pair is a `zpool replace` inside a healthy
pool (open the new disk's LUKS container first, same `enrollRecovery`
dance, then `zpool replace`), not a full host rebuild — not covered in
detail here.

1. **Boot the rescue ISO** (`hosts/isoimage`). Checked its actual
   package list (`hosts/isoimage/configuration.nix`) — it has `disko`,
   `zfs` (via `boot.supportedFilesystems`), `restic`, `rclone`,
   `sanoid` (which also installs `syncoid`), `smartmontools`,
   `ddrescue`. `cryptsetup`/`systemd-cryptenroll` ship with systemd so
   they're present without being listed explicitly. **`sbctl` is not
   in the package list** — add it to
   `hosts/isoimage/configuration.nix`'s `environment.systemPackages`
   before this step is real; this is an open prerequisite, not done by
   writing this doc.

2. **Re-provision via disko.** With `askPassword`/`enrollRecovery` as
   currently configured (no `passwordFile`/`keyFile` set in
   `disko.nix`), running disko interactively will:
   - Prompt for a password per LUKS container (5 containers on
     homelab — same passphrase each run is fine, they're independent
     LUKS headers).
   - Generate and display a **brand-new** high-entropy recovery
     passphrase + QR code per container, once, on screen. This is a
     **fresh** recovery key, unrelated to whatever was escrowed from
     the original install — the old LUKS headers are gone, this is a
     new install. Capture every one of these on the spot (photograph
     the QR, or copy the printed passphrase) before continuing — disko
     does not save them anywhere and will not show them again.
   ```
   disko --mode disko /path/to/flake#homelab-disko
   ```
   (Or whatever the real invocation ends up being for this repo's
   flake layout — confirm the exact disko output/flake attribute name
   against how this repo's other hosts are actually installed, e.g.
   the `disko-install` command already documented at the top of
   `hosts/homelab/disko.nix`, before relying on this in a real
   emergency.)
3. **Escrow the newly generated recovery passphrases immediately**
   (see "Escrow locations") — update the previous entries, don't leave
   stale ones that no longer correspond to any real LUKS header.
4. **Boot once**, confirm Secure Boot enrolled clean on this hardware:
   ```
   sbctl status
   ```
   If this hardware never had sbctl's keys enrolled (new motherboard),
   run Scenario 2 above first.
5. **Only then** enroll a TPM2 slot per container (sealing against a
   confirmed-good state):
   ```
   sudo systemd-cryptenroll <device> --tpm2-device=auto --tpm2-pcrs=0+2+7+11
   ```
6. **Repopulate data.** homelab is its own backup source:
   - Offsite restic-to-B2 for `zroot/local/state` (see
     `services.restic.backups.backblazeWeekly` in
     `hosts/homelab/configuration.nix` for the exact repo/password
     secret paths and the `restic-backblazeWeekly` wrapper it
     generates via `createWrapper`).
   - `zdata`/`zbackup` pools: if only `zroot`'s NVMe died, these pools
     and their LUKS containers are untouched — just re-open them
     (`cryptsetup open` prompts for the original per-disk passphrase,
     or use the container's escrowed recovery key) and `zpool import`.
     If a `zdata`/`zbackup` disk also died, restore that dataset from
     whichever surviving copy is source of truth — check `zpool
     status` on all three pools before assuming.
7. **Restore sops secrets access.** A freshly reprovisioned host
   generates a *new* SSH host key / age identity, which cannot decrypt
   this host's existing `secrets/secrets.yaml` entries — this is the
   same chicken-and-egg problem already documented for vps
   (`hosts/vps/README.md` step 1).
   - Preferred: restore the actual backed-up host SSH private key
     (`/etc/ssh/ssh_host_ed25519_key`) to its impermanence-persisted
     path (check `environment.persistence` in
     `hosts/homelab/configuration.nix`) *before* the first
     `nixos-rebuild switch` that references secrets, so the host's age
     identity matches what's already enrolled in `.sops.yaml`
     (`homelab3` key).
   - Fallback (old key truly gone): from a machine that still has
     access (thinkpad or torrent, both in `.sops.yaml`), generate a
     fresh age identity for the rebuilt homelab, add it to
     `.sops.yaml`'s `creation_rules`, run
     `sops updatekeys secrets/secrets.yaml`, commit, then rebuild.
     Rotate any secrets that were only ever meant to be readable by
     the old, now-lost key.
8. **First `nixos-rebuild switch`** referencing secrets should now
   succeed. Confirm sanoid/syncoid resume on schedule and the restic
   timer's `last-success` marker starts advancing again.

## Escrow locations (RECOMMENDATION — needs your sign-off)

`TODO.md`'s Phase 3 section names the categories (paper backup,
password manager, offline media) but doesn't commit to one. Proposed,
concrete:

- **LUKS recovery passphrases** (one per container — 5 for homelab):
  one entry per container in your password manager (Bitwarden/
  1Password — whichever you already use), named clearly (e.g.
  `homelab-zroot-crypt-luks-recovery`), *plus* a printed copy in a
  fire safe as the non-digital fallback for the scenario where the
  password manager itself is unreachable. Re-escrow (replace the
  stale entry) any time the underlying LUKS header changes — i.e.
  after any real Scenario 3 recovery.
- **sbctl PKI backup**: captured via this host's existing restic/
  persistence setup (add the resolved sbctl key directory to
  `environment.persistence` and the restic backup paths once Phase 1
  lands), so it rides along with the existing offsite backup rather
  than needing a separate escrow mechanism. Lower-stakes than the LUKS
  key (loss is recoverable via regeneration, just annoying), so it
  doesn't need paper/offline escrow.
- **Host SSH/age private key backup**: same treatment as sbctl —
  captured via restic/persistence (this repo already does this for
  vps: `/etc/ssh/ssh_host_ed25519_key` under
  `environment.persistence`). The one thing that must NOT depend on
  this mechanism is the **restic repository password itself** — it's
  a sops secret (`homelab_backblaze_restic_password`) decrypted using
  this host's own age key, which is circular for a disaster-recovery
  restore of this same host. That password needs its own out-of-band
  copy (password manager + paper), same tier as the LUKS recovery
  passphrases.

This needs your actual decision and setup (creating the password
manager entries, printing/storing the paper copies) — an agent can't
create real physical or password-manager escrow. Until this is done,
treat Scenario 1–3 above as unexecutable in a real emergency.

## Open follow-ups

- Add `sbctl` to `hosts/isoimage/configuration.nix`.
- Confirm the real disko re-provisioning invocation for a rescue
  scenario (Scenario 3 step 2) against how this repo actually installs
  hosts — the `disko-install` one-liner at the top of
  `hosts/homelab/disko.nix` may need adjusting once nixos-anywhere
  is/isn't used for a live-disk swap vs. cold rescue-ISO boot.
- Confirm the actual PCR set (`0+2+7+11`) against this host's real
  lanzaboote/boot config once Phase 1 lands — this is a reasonable
  starting point per `systemd-cryptenroll(1)`, not yet verified
  against a live measured-boot chain.
- Do the actual dry run (spare disk or VM) before trusting this
  runbook on a live disaster.
