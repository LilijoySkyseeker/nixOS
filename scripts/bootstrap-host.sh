#!/usr/bin/env bash
set -euo pipefail

# Installs or reinstalls a host via nixos-anywhere, breaking the
# sops/tailscale chicken-and-egg described in
# docs/procedures/remote-access.md: pre-generates the host's SSH host
# key, enrolls its age key in .sops.yaml, and re-encrypts secrets
# before the box ever boots, so sops-nix can decrypt on first boot.
#
# Usage: scripts/bootstrap-host.sh <host> <target-ip|--vm-test> [--persist-root <path>] [-- <extra nixos-anywhere args>]
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
# kexec needs genuinely free, kernel-pinned physical RAM for the new
# kernel+initrd -- confirmed live (twice) that a tiny/RAM-constrained
# target can OOM-kill it even with swap added, since swap only helps
# reclaim swappable pages and kexec's own allocation isn't one. This
# script does not work around that; resize the target up for more real
# RAM before installing if it's tight, then back down after. See
# docs/procedures/new-host.md and hosts/vps/README.md.
#
# Example (DigitalOcean, impermanence, needs --kexec-extra-flags -c):
#   scripts/bootstrap-host.sh vps 164.90.1.2 --persist-root /persist -- --kexec-extra-flags -c
#   scripts/bootstrap-host.sh vps --vm-test --persist-root /persist

usage() {
	echo "Usage: $0 <host> <target-ip|--vm-test> [--persist-root <path>] [-- <extra nixos-anywhere args>]" >&2
	exit 1
}

[[ $# -ge 2 ]] || usage
host=$1
target=$2
shift 2
vm_test=false
[[ "$target" == "--vm-test" ]] && vm_test=true

persist_root=""
if [[ "${1:-}" == "--persist-root" ]]; then
	persist_root=$2
	shift 2
fi
[[ "${1:-}" == "--" ]] && shift
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
read -r -p "Continue? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || {
	echo "aborted -- .sops.yaml/secrets.yaml changes above are already committed to disk, revert if unwanted" >&2
	exit 1
}

echo "==> building $host locally and installing to root@$target"
nixos-anywhere \
	--flake "$repo_root#$host" \
	--target-host "root@$target" \
	--generate-hardware-config nixos-generate-config "$host_dir/hardware-configuration.nix" \
	--extra-files "$work_dir" \
	"${extra_args[@]}"

echo "==> install finished. verify live services before trusting this host -- see docs/procedures/new-host.md."
