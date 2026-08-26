#!/usr/bin/env bash
set -euo pipefail

# Installs or reinstalls a host via nixos-anywhere, breaking the
# sops/tailscale chicken-and-egg described in
# docs/procedures/remote-access.md: pre-generates the host's SSH host
# key, enrolls its age key in .sops.yaml, and re-encrypts secrets
# before the box ever boots, so sops-nix can decrypt on first boot.
#
# Usage: scripts/bootstrap-host.sh <host> <target-ip> [--persist-root <path>] [-- <extra nixos-anywhere args>]
#
# --persist-root is required for impermanence hosts (e.g. vps's
# /persist): with root on tmpfs, a host key written to plain /etc/ssh
# vanishes on the very first real boot. It must land wherever the
# host's `environment.persistence."<path>"` module reads it from —
# check the host's configuration.nix if unsure.
#
# Example (DigitalOcean, impermanence, needs --kexec-extra-flags -c):
#   scripts/bootstrap-host.sh vps 164.90.1.2 --persist-root /persist -- --kexec-extra-flags -c

usage() {
	echo "Usage: $0 <host> <target-ip> [--persist-root <path>] [-- <extra nixos-anywhere args>]" >&2
	exit 1
}

[[ $# -ge 2 ]] || usage
host=$1
target_ip=$2
shift 2

persist_root=""
if [[ "${1:-}" == "--persist-root" ]]; then
	persist_root=$2
	shift 2
fi
extra_args=("$@")

repo_root=$(git rev-parse --show-toplevel)
host_dir="$repo_root/hosts/$host"
[[ -d "$host_dir" ]] || {
	echo "no such host: $host_dir" >&2
	exit 1
}

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

key_dir="$work_dir${persist_root}/etc/ssh"
echo "==> generating a fresh SSH host key for $host (kept outside the repo checkout)"
mkdir -p "$key_dir"
ssh-keygen -t ed25519 -f "$key_dir/ssh_host_ed25519_key" -N "" \
	-C "$host host key ($(date +%F))" -q
chmod 600 "$key_dir/ssh_host_ed25519_key"
chmod 644 "$key_dir/ssh_host_ed25519_key.pub"

age_key=$(ssh-to-age -i "$key_dir/ssh_host_ed25519_key.pub")
echo "==> new age key: $age_key"

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
sops updatekeys -y "$repo_root/secrets/secrets.yaml"

echo
echo "This will WIPE and reinstall root@$target_ip as '$host'. This cannot be undone."
read -r -p "Continue? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || {
	echo "aborted -- .sops.yaml/secrets.yaml changes above are already committed to disk, revert if unwanted" >&2
	exit 1
}

echo "==> building $host locally and installing to root@$target_ip"
nixos-anywhere \
	--flake "$repo_root#$host" \
	--target-host "root@$target_ip" \
	--generate-hardware-config nixos-generate-config "$host_dir/hardware-configuration.nix" \
	--extra-files "$work_dir" \
	"${extra_args[@]}"

echo "==> install finished. verify live services before trusting this host -- see docs/procedures/new-host.md."
