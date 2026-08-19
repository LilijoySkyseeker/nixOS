# thinkpad — recovery runbook

Covers recovery once thinkpad has landed the FDE/Secure Boot/TPM2 +
impermanence plan in `TODO.md`. `hosts/thinkpad/disko.nix` already has
the LUKS layer (single container `zroot-crypt` wrapping the zroot
partition, `enrollRecovery = true`, `settings.allowDiscards = true`).
Phase 1 (lanzaboote Secure Boot), the post-install TPM2 enrollment
step, and the impermanence retrofit for `local/root` have not shipped
yet as of this writing — commands below that assume those exist are
**not yet applicable**.

This is a draft pending a real dry run (spare disk or VM) — verify
each command, don't trust it blind, until that dry run happens and
this note is removed. `systemd-cryptenroll` flag syntax checked
against the installed man page; `enrollRecovery` behavior checked
against disko's source at this flake's pinned rev.

Unlike homelab, thinkpad has **no independent offsite backup of its
own** — its only backup destination is homelab's `zbackup` pool
(`zbackup/backup/thinkpad`, `zbackup/backup/thinkpad/bulk`; dataset
stubs already exist in `hosts/homelab/disko.nix`, the syncoid wiring
to actually populate them is being built separately). That means:

- thinkpad's disaster recovery is only as good as homelab's zbackup
  pool being alive and reachable — if both machines fail at once (or
  homelab's zbackup pool is what died), there's no thinkpad-specific
  fallback.
- Phase 2 should not ship on thinkpad until syncoid is actually
  running and `zbackup/backup/thinkpad` has real, current snapshots —
  confirm with `zfs list -t snapshot -r zbackup/backup/thinkpad` on
  homelab before trusting this runbook.

## 0. Prerequisites

- The recovery passphrase `enrollRecovery` generated for
  `zroot-crypt` at thinkpad's original install is escrowed somewhere
  reachable without needing to decrypt thinkpad itself (see homelab's
  RECOVERY.md "Escrow locations" — same approach applies per-host).
  Only useful for Scenario 1/2 below — a full disk swap (Scenario 3)
  generates a brand-new one.
- sbctl PKI backup for thinkpad exists outside the host.
- thinkpad's SSH host key / sops age identity (`nixos-thinkpad`,
  `thinkpad-ssh`, `thinkpad-machine` in `.sops.yaml`) is backed up
  outside the host.
- On homelab: `zbackup/backup/thinkpad` has a recent snapshot
  (`zfs list -t snapshot -r zbackup/backup/thinkpad`).

## Finding the right device

```
sudo cryptsetup status zroot-crypt | grep device:
```

(`/dev/mapper/zroot-crypt` is only the decrypted view once open —
`systemd-cryptenroll` needs the underlying LUKS-formatted partition
this command reports.)

## 1. Scenario: TPM2 unseal failure

Same procedure as homelab's Scenario 1 — enter the escrowed passphrase
at the boot prompt, confirm the new hardware/firmware state is
trustworthy, then re-enroll+wipe in one command:

```
sudo systemd-cryptenroll <device> --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=0+2+7+11
```

Reboot once to confirm auto-unlock works without a prompt.

Thinkpad-specific note: laptops move between docks/external displays/
BIOS settings more than a stationary server — a BIOS update or Secure
Boot setting toggle is more likely here day-to-day than on homelab.
Expect this scenario to come up more often; re-seal proactively after
any firmware update rather than waiting for a failed boot.

## 2. Scenario: Secure Boot key loss

Same as homelab's Scenario 2:

```
sudo sbctl create-keys
sudo sbctl enroll-keys -m
sudo sbctl sign-all
sudo sbctl verify
sudo systemd-cryptenroll <device> --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=0+2+7+11
```

Confirm sbctl's PKI directory is in thinkpad's
`environment.persistence` and covered by whatever backup thinkpad ends
up with (currently: none independent of homelab's zbackup — see the
note at the top of this file. It should probably ride along in
`zbackup/backup/thinkpad` once that's wired up, same as its state
dataset).

## 3. Scenario: full hardware failure / disk death

Thinkpad has a single-disk `zroot` (`zroot-crypt`) with `local/root`
and `local/home` as separate ZFS datasets (`hosts/thinkpad/disko.nix`)
— once the impermanence retrofit lands, home directories will NOT be
wiped by the root rollback and are the most valuable uniquely-thinkpad
data (root/state becomes reproducible from the flake + homelab's
`zbackup/backup/thinkpad` state snapshots).

1. **Boot the rescue ISO** (`hosts/isoimage`). Same gap as homelab's
   runbook: `sbctl` is not in `hosts/isoimage/configuration.nix`'s
   package list yet — add it before this step is real.
2. **Re-provision via disko.** As configured (no `passwordFile`/
   `keyFile` in `disko.nix`, `askPassword` defaults true), this will
   interactively prompt for a password for `zroot-crypt` and generate
   + display a **brand-new** high-entropy recovery passphrase/QR code,
   once. This is unrelated to whatever was escrowed from the original
   install — the old LUKS header is gone. Capture it on the spot
   (photo the QR / copy the passphrase) — disko will not show it
   again.
   ```
   disko --mode disko /path/to/flake#thinkpad-disko
   ```
   (Confirm the real invocation for this repo's flake layout before
   relying on this in a real emergency — not yet verified against how
   this repo actually re-provisions a host.)
3. **Escrow the newly generated recovery passphrase immediately**,
   replacing the stale entry from the previous install.
4. **Boot once**, confirm `sbctl status` is clean on this hardware (or
   run Scenario 2 first if this is genuinely new/replacement
   hardware).
5. **Enroll the TPM2 slot**:
   ```
   sudo systemd-cryptenroll <device> --tpm2-device=auto --tpm2-pcrs=0+2+7+11
   ```
6. **Repopulate data** — thinkpad has no local backup source, pull
   from homelab:
   ```
   # run from homelab, or from thinkpad over the tailnet against homelab
   zfs send zbackup/backup/thinkpad@<latest-state-snapshot> | zfs receive -F zroot/local/state
   zfs send zbackup/backup/thinkpad/bulk@<latest-home-snapshot> | zfs receive -F zroot/local/home
   ```
   Confirm the actual target dataset names against whatever the
   impermanence retrofit lands as thinkpad's real dataset layout — a
   `local/state` dataset will be added alongside the existing
   `local/root`/`local/home`, and this step needs updating to match
   once that's committed.
7. **Restore sops secrets access** — same chicken-and-egg as homelab's
   Scenario 3 step 7. Preferred: restore thinkpad's actual backed-up
   SSH host key before the first `nixos-rebuild switch` referencing
   secrets. Fallback: enroll a fresh age key from a machine that still
   has access (homelab or torrent), update `.sops.yaml`, `sops
   updatekeys`, rebuild, rotate.
8. **First `nixos-rebuild switch`** should now succeed. Confirm
   sanoid/syncoid resume (syncoid direction here is thinkpad → homelab
   — confirm the push side is running again, not just that homelab's
   pull-side dataset exists).

## Escrow locations

Same recommendation as homelab's RECOVERY.md — password manager entry
for the `zroot-crypt` recovery passphrase, printed fallback copy,
sbctl/host-key backups riding along in the persistence+backup setup
once that's wired for this host. Needs your sign-off and actual setup;
not done by writing this doc.

## Open follow-ups

- Add `sbctl` to `hosts/isoimage/configuration.nix`.
- Confirm the real disko re-provisioning invocation once verified
  against this repo's actual install process.
- Confirm real post-impermanence dataset names once that retrofit
  lands, update Scenario 3 step 6.
- Don't ship Phase 2 on thinkpad until `zbackup/backup/thinkpad` has
  real current snapshots (syncoid wiring is being built separately).
- Do the actual dry run before trusting this on a live disaster.
