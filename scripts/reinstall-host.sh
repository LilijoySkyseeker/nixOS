#!/usr/bin/env bash
# Phase 2 reinstall orchestrator (TODO.md: LUKS + TPM2 + Secure Boot +
# impermanence rollout). Template script, driven by scripts/hosts/<host>.conf
# — copy scripts/hosts/thinkpad.conf to add a new host.
#
# Boot the host straight to the recovery ISO ONCE (no need to boot the
# old install first) and everything that can possibly happen over ssh
# to that one ISO session does — backup, install, and restore. Only
# what genuinely requires physical/local presence is left local:
#
#   backup      REMOTE, from your admin machine, ssh to the booted
#               ISO. Imports the host's CURRENT (pre-reinstall) pool
#               read-write (forced — hostid won't match the ISO's) and
#               syncoid-sends the data off before anything is wiped.
#   install     REMOTE, same ISO session. disko-install wipes the
#               disk(s) and lays down the new LUKS+ZFS config.
#   restore     REMOTE, same ISO session, before ever booting the new
#               install. Receives the backed-up data straight into the
#               freshly disko-installed pool, then exports it and
#               offers to reboot the host into the real install.
#   secureboot  LOCAL, on the booted new install — pauses for the BIOS
#               Setup Mode step, which nothing can automate.
#   tpm2        LOCAL, on the booted new install, after Secure Boot is
#               confirmed working — must run post-reboot, since PCR7
#               has to reflect the real signed boot chain, not the ISO's.
#
# Full sequence for a given host:
#   1. Boot the recovery ISO on the host (USB/Ventoy), note its IP.
#   2. From your admin machine: ./reinstall-host.sh backup     thinkpad <iso-ip>
#   3. From your admin machine: ./reinstall-host.sh install    thinkpad <iso-ip>
#   4. From your admin machine: ./reinstall-host.sh restore    thinkpad <iso-ip>
#      (this stage ends by offering to reboot the host for you)
#   5. On the host, after it boots the new install:
#                                ./reinstall-host.sh secureboot thinkpad
#   6. On the host:              ./reinstall-host.sh tpm2       thinkpad
#   7. On your dotfiles checkout: flip myPhase2.reinstalled = true for
#      this host, nixos-rebuild build to confirm, commit, push.
#
# backup/install/restore all use ssh -A (agent forwarding) to the ISO,
# so syncoid running there can reach homelab using YOUR forwarded
# agent — no private key ever touches the ISO. See
# hosts/isoimage/configuration.nix's AllowAgentForwarding.
#
# TEMPORARY: the backup/restore stages are a stand-in for real automated
# backups (being built separately — see TODO.md). Once thinkpad/torrent
# are covered by that system, delete these two stages here and restore
# from there instead.
#
# --dry-run: run any stage without touching disk state, ssh'ing
# anywhere, or requiring physical presence — for testing the script's
# plumbing (arg parsing, host-conf loading, command construction)
# before trusting it against a real host. Logs every command it would
# run instead of running it; auto-answers confirm/pause prompts; skips
# the hostname self-check so you can dry-run any stage from your admin
# machine. NOT a substitute for the real thing — it never contacts an
# ISO, homelab, or a LUKS/TPM2 device, so it can't catch e.g. a wrong
# IP, a stale ssh key, or a real disko failure.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPTS_DIR/lib/common.sh"

usage() {
  cat <<EOF
Usage: $0 [--dry-run] <stage> <host> [args...]

Stages:
  backup     <host> <iso-ip>       run from your admin machine
  install    <host> <iso-ip>       run from your admin machine
  restore    <host> <iso-ip>       run from your admin machine
  secureboot <host>                run on the freshly-installed host
  tpm2       <host>                run on the freshly-installed host

--dry-run logs what each stage would do instead of doing it. See the
header comment in this file for the full sequence and dry-run caveats.
EOF
  exit 1
}

require_local_host() {
  local host="$1"
  local actual
  actual="$(hostname)"
  if [ "$actual" != "$host" ]; then
    if dry; then
      warn "[dry-run] this stage would normally require running on '$host' (this machine is '$actual') — continuing anyway."
      return 0
    fi
    die "This stage must run locally on '$host', but this machine is '$actual'."
  fi
}

stage_backup() {
  local host="$1"
  local iso_ip="$2"
  local target="root@${iso_ip}"

  log "Importing $host's current pool '$SOURCE_POOL' read-write on the ISO (forced — hostid won't match) to read data out before it's wiped."
  confirm "About to import '$SOURCE_POOL' on $target and send ${DATA_DATASETS[*]} -> ${HOMELAB_SSH}:${BACKUP_DATASET}/<leaf>. Read-write import so syncoid can snapshot, but nothing here writes application data — this pool is about to be wiped by the 'install' stage regardless. TEMPORARY pre-reinstall safety net, not the real backup system."

  ssh_to "$target" zpool import -f -N "$SOURCE_POOL"

  for ds in "${DATA_DATASETS[@]}"; do
    local leaf="${ds##*/}"
    ssh_to "$target" syncoid "$ds" "${HOMELAB_SSH}:${BACKUP_DATASET}/${leaf}"
  done

  ssh_to "$target" zpool export "$SOURCE_POOL"

  ok "Backup complete. Verify on homelab with: zfs list -r ${BACKUP_DATASET}"
  ok "Next: ./reinstall-host.sh install $host $iso_ip"
}

stage_install() {
  local host="$1"
  local iso_ip="$2"
  local target="root@${iso_ip}"

  log "Target: $host"
  log "Disks:"
  for pair in "${DISKO_DISKS[@]}"; do
    echo "    ${pair%%=*} -> ${pair#*=}"
  done

  local disk_args=()
  for pair in "${DISKO_DISKS[@]}"; do
    disk_args+=(--disk "${pair%%=*}" "${pair#*=}")
  done

  confirm "About to WIPE the disk(s) above on $host (via $target) and disko-install the '$host' flake config. This is irreversible."

  # -t (ssh_tty_to): this is interactive — disko-install will prompt
  # for a LUKS passphrase per container and print/pause on the
  # QR-coded enrollRecovery passphrase (see hosts/$host/RECOVERY.md for
  # what to do with those recovery passphrases — escrow, not discard).
  ssh_tty_to "$target" \
    disko-install --write-efi-boot-entries \
    --flake "github:lilijoyskyseeker/nixos#${host}" \
    "${disk_args[@]}"

  ssh_to "$target" zpool export -af

  ok "Install complete. Next: ./reinstall-host.sh restore $host $iso_ip"
}

stage_restore() {
  local host="$1"
  local iso_ip="$2"
  local target="root@${iso_ip}"

  confirm "About to import the freshly disko-installed pool on $target and receive ${HOMELAB_SSH}:${BACKUP_DATASET}/* into ${RESTORE_DATASET}. Verify 'install' really just ran against this ISO session before continuing."

  local new_pool="${RESTORE_DATASET%%/*}"
  ssh_to "$target" zpool import -f -N "$new_pool"

  for ds in "${DATA_DATASETS[@]}"; do
    local leaf="${ds##*/}"
    ssh_to "$target" syncoid "${HOMELAB_SSH}:${BACKUP_DATASET}/${leaf}" "${RESTORE_DATASET}"
  done

  ssh_to "$target" zpool export -af

  ok "Restore complete."
  pause "Remove the installer USB/media from $host now, if it hasn't already been ejected."
  confirm "Reboot $host (via $target) into the new install now?"
  ssh_to "$target" reboot || warn "ssh dropped, as expected once reboot fires — that's fine."

  ok "Once $host has booted the new install, continue locally on it: ./reinstall-host.sh secureboot $host"
}

stage_secureboot() {
  local host="$1"
  require_local_host "$host"

  warn "Secure Boot key enrollment can't be scripted — it requires entering BIOS Setup Mode by hand. Follow the 'Secure Boot setup' section in hosts/${host}/README.md on your admin machine for the exact steps (sbctl create-keys, Setup Mode enrollment, sbctl enroll-keys --microsoft, verification)."
  pause "Once you've completed the BIOS Setup Mode enrollment and rebooted with Secure Boot re-enabled, come back here."

  log "sbctl status:"
  if dry; then
    log "[dry-run] would run: sbctl status"
  else
    sbctl status || true
  fi

  confirm "Does the status above show Secure Boot enabled and your keys enrolled? Only continue if yes."
  ok "Secure Boot confirmed. Next: run 'tpm2 $host' locally on this host."
}

stage_tpm2() {
  local host="$1"
  require_local_host "$host"

  warn "TPM2 enrollment binds to PCR7 (Secure Boot state) — only run this after Secure Boot is confirmed working (the 'secureboot' stage), never before. Sealing against an unverified boot chain defeats the point."
  confirm "Enroll a TPM2 keyslot on this host's root LUKS container? The existing interactive/recovery passphrase slots are kept, not replaced."

  run_cmd run0 systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/disk-nvme-a-zfs

  ok "TPM2 enrolled. Reboot once to confirm auto-unlock works before relying on it."
  ok "Final step: on your dotfiles checkout, set myPhase2.reinstalled = true for $host in hosts/${host}/configuration.nix, nixos-rebuild build to confirm, then commit + push."
}

# --dry-run can appear anywhere in argv; strip it out and set DRY_RUN
# (read by lib/common.sh's dry()) before parsing the positional args.
args=()
for a in "$@"; do
  if [ "$a" = "--dry-run" ]; then
    DRY_RUN=1
  else
    args+=("$a")
  fi
done
set -- "${args[@]}"

[ $# -ge 2 ] || usage
STAGE="$1"
HOST_ARG="$2"
shift 2

dry && warn "--dry-run: no disk, ssh, or hardware state will actually be touched."

require_host_conf "$HOST_ARG"

case "$STAGE" in
backup)
  [ $# -ge 1 ] || die "backup requires <iso-ip>"
  stage_backup "$HOST_ARG" "$1"
  ;;
install)
  [ $# -ge 1 ] || die "install requires <iso-ip>"
  stage_install "$HOST_ARG" "$1"
  ;;
restore)
  [ $# -ge 1 ] || die "restore requires <iso-ip>"
  stage_restore "$HOST_ARG" "$1"
  ;;
secureboot) stage_secureboot "$HOST_ARG" ;;
tpm2) stage_tpm2 "$HOST_ARG" ;;
*) usage ;;
esac
