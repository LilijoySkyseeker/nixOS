#!/usr/bin/env bash
set -euo pipefail

# Installs or reinstalls a host via nixos-anywhere, breaking the
# sops/tailscale chicken-and-egg described in
# docs/procedures/remote-access.md: pre-generates the host's SSH host
# key, enrolls its age key in .sops.yaml, and re-encrypts secrets
# before the box ever boots, so sops-nix can decrypt on first boot.
#
# Usage: scripts/bootstrap-host.sh <host> <target-ip|--vm-test> [--persist-root <path>] [-y|--yes] [-- <extra nixos-anywhere args>]
#
# --persist-root is required for impermanence hosts (e.g. vps's
# /persist): with root on tmpfs, a host key written to plain /etc/ssh
# vanishes on the very first real boot. It must land wherever the
# host's `environment.persistence."<path>"` module reads it from —
# check the host's configuration.nix if unsure.
#
# Pass --vm-test instead of a target IP to exercise the real disko +
# extra-files/--persist-root placement in a throwaway local VM before
# touching any real target — no SSH, no .sops.yaml/secrets.yaml
# changes, no confirmation prompt.
#
# -y/--yes skips the "this will WIPE ..." confirmation prompt, for
# scripted/backgrounded invocations. Piping a "y" into stdin instead is
# NOT a reliable substitute: backgrounding this script with a trailing
# `&` can leave `read` seeing EOF regardless of what was piped in
# (confirmed live), which aborts the whole script under `set -e`
# without ever showing the prompt.
#
# kexec needs genuinely free, kernel-pinned physical RAM for the new
# kernel+initrd -- confirmed live (twice) that a tiny/RAM-constrained
# target can OOM-kill it even with swap added, since swap only helps
# reclaim swappable pages and kexec's own allocation isn't one. Refuses
# to proceed against a real target with less than MIN_MEM_MB total RAM
# (see below) rather than run headlong into the same OOM again --
# resize the target up for more real RAM before installing if it's
# tight, then back down after. See docs/procedures/new-host.md and
# hosts/vps/README.md.
#
# Example (DigitalOcean, impermanence, needs --kexec-extra-flags -c):
#   scripts/bootstrap-host.sh vps 164.90.1.2 --persist-root /persist -- --kexec-extra-flags -c
#   scripts/bootstrap-host.sh vps --vm-test --persist-root /persist

usage() {
	echo "Usage: $0 <host> <target-ip|--vm-test> [--persist-root <path>] [-y|--yes] [-- <extra nixos-anywhere args>]" >&2
	exit 1
}

[[ $# -ge 2 ]] || usage
host=$1
target=$2
shift 2
vm_test=false
[[ "$target" == "--vm-test" ]] && vm_test=true

persist_root=""
yes=false
while [[ $# -gt 0 ]]; do
	case "$1" in
	--persist-root)
		persist_root=$2
		shift 2
		;;
	-y | --yes)
		yes=true
		shift
		;;
	--)
		shift
		break
		;;
	*)
		break
		;;
	esac
done
extra_args=("$@")

# Resolved from the script's own location, not the caller's cwd -- this
# is meant to be invoked from a scratch directory (see docs/procedures/
# vm-testing.md) so nixos-anywhere's qcow2/log artifacts don't land in
# the repo checkout.
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
host_dir="$repo_root/hosts/$host"
[[ -d "$host_dir" ]] || {
	echo "no such host: $host_dir" >&2
	exit 1
}

# Checked against total RAM, not "available" -- total is a fixed
# per-tier number, so it isn't affected by transient cache/buffer
# state the way "available" is. 1900 reliably tells apart DigitalOcean's
# 1GB tier (~956MiB reported) from its 2GB tier (~1950MiB reported)
# without being thrown off by a few MB of reporting variance.
min_mem_mb=1900
if ! $vm_test; then
	echo "==> checking $target has enough RAM for kexec (it needs genuinely free,"
	echo "    kernel-pinned physical memory -- confirmed live that even a 1GB"
	echo "    droplet with a swapfile added still OOM-kills kexec)"
	ssh_check_opts=(-o ConnectTimeout=8 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
	mem_total_kb=$(ssh "${ssh_check_opts[@]}" "root@$target" \
		"awk '/MemTotal/{print \$2}' /proc/meminfo") || {
		echo "couldn't check memory on root@$target -- unreachable, or its SSH host key" >&2
		echo "changed (recreated droplet reusing an old IP?) -- see docs/procedures/new-host.md" >&2
		exit 1
	}
	mem_total_mb=$((mem_total_kb / 1024))
	if ((mem_total_mb < min_mem_mb)); then
		cat >&2 <<-EOF
			$target only has ${mem_total_mb}MB total RAM (want >= ${min_mem_mb}MB).
			kexec needs real headroom beyond what this tier reliably provides -- confirmed
			live that it OOM-kills even with a swapfile added. Resize the target up to a
			bigger RAM tier, then re-run this script; resize back down once install succeeds.
		EOF
		exit 1
	fi
	echo "==> $target has ${mem_total_mb}MB total RAM, proceeding"
fi

work_dir=$(mktemp -d)
cleanup() {
	status=$?
	if [[ $status -ne 0 ]]; then
		echo "==> failed (exit $status) -- preserving $work_dir (has the generated host key) for recovery" >&2
	else
		rm -rf "$work_dir"
	fi
}
trap cleanup EXIT

key_dir="$work_dir${persist_root}/etc/ssh"
echo "==> generating a fresh SSH host key for $host (kept outside the repo checkout)"
mkdir -p "$key_dir"
ssh-keygen -t ed25519 -f "$key_dir/ssh_host_ed25519_key" -N "" \
	-C "$host host key ($(date +%F))" -q
chmod 600 "$key_dir/ssh_host_ed25519_key"
chmod 644 "$key_dir/ssh_host_ed25519_key.pub"

age_key=$(ssh-to-age -i "$key_dir/ssh_host_ed25519_key.pub")
echo "==> new age key: $age_key"

if $vm_test; then
	echo "==> --vm-test: skipping .sops.yaml/secrets.yaml changes and the confirmation prompt"
	echo "==> NOTE: nixos-anywhere's --vm-test rejects --extra-files outright, so this only"
	echo "    exercises disko + basic install/boot -- it cannot validate the persist-root"
	echo "    key placement above. That still only gets a real check during the actual install."
	echo "==> building $host and booting it as a throwaway local VM (own virtual disk; no"
	echo "    --target-host/ssh-host is passed, so nothing outside that VM is touched)"
	nixos-anywhere \
		--flake "$repo_root#$host" \
		--vm-test \
		"${extra_args[@]}"
	echo "==> vm-test finished. this did not touch .sops.yaml, secrets.yaml, or any real target."
	exit 0
fi

sops_file="$repo_root/.sops.yaml"
anchor="&$host "
if grep -qF "$anchor" "$sops_file"; then
	echo "==> rotating existing .sops.yaml anchor for $host"
	sed -i -E "s|(&$host )age1[a-z0-9]+|\1$age_key|" "$sops_file"
else
	cat >&2 <<-EOF
		$host has no .sops.yaml anchor yet. Add one by hand under keys::
		      - &$host $age_key
		    and reference it from the relevant creation_rules entry, then re-run this script.
	EOF
	exit 1
fi

echo "==> re-encrypting secrets/secrets.yaml for the new recipient"
sops --config "$sops_file" updatekeys -y "$repo_root/secrets/secrets.yaml"

echo
echo "This will WIPE and reinstall root@$target as '$host'. This cannot be undone."
if $yes; then
	echo "==> -y/--yes given, skipping the confirmation prompt"
else
	read -r -p "Continue? [y/N] " reply
	[[ "$reply" =~ ^[Yy]$ ]] || {
		echo "aborted -- .sops.yaml/secrets.yaml changes above are already committed to disk, revert if unwanted" >&2
		exit 1
	}
fi

echo "==> building $host locally and installing to root@$target"
nixos-anywhere \
	--flake "$repo_root#$host" \
	--target-host "root@$target" \
	--generate-hardware-config nixos-generate-config "$host_dir/hardware-configuration.nix" \
	--extra-files "$work_dir" \
	"${extra_args[@]}"

echo "==> install finished. verify live services before trusting this host -- see docs/procedures/new-host.md."
echo "==> if you resized $target up temporarily for this install, resize it back down now."
