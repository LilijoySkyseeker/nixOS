#!/usr/bin/env bash
set -euo pipefail

# Regenerates the machine-generated "Host Inventory" block in
# hosts/<host>/README.md from that host's evaluated NixOS config:
# enabled services, packages, oci-containers, ZFS/NFS filesystems,
# per-interface firewall ports, systemd timers, users, and sops secrets
# in use. What's deliberately out of scope (ZFS pool topology, NFS/Samba
# per-share detail):
# plan: 2026-09-03-auto-generated-per-host-inventory-doc-services-packages-containers.md#G1
# plan: 2026-09-03-auto-generated-per-host-inventory-doc-services-packages-containers.md#G2
#
# Usage: scripts/doc-host.sh <host> [<host> ...] | --all
#
# Idempotent: only the <!-- inventory:start/end --> block is touched,
# everything else in the README is left alone. If the markers aren't
# present yet, the block is appended to the end of the file. Requires
# `nix` and `jq` on PATH (both in the devshell).

usage() {
	echo "Usage: $0 <host> [<host> ...] | --all" >&2
	exit 1
}

[[ $# -ge 1 ]] || usage

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

if [[ "$1" == "--all" ]]; then
	hosts=()
	for d in hosts/*/; do
		host=$(basename "$d")
		[[ -f "$d/configuration.nix" ]] && hosts+=("$host")
	done
else
	hosts=("$@")
fi

start_marker="<!-- inventory:start -->"
end_marker="<!-- inventory:end -->"

# Pure-builtins Nix lambda (no `lib` in scope from a bare `nix eval
# --apply`) for everything except `services` -- packages/containers/
# filesystems/timers/firewall/users/secrets are all namespaces this
# repo's own modules define directly, with no known compat-shim traps.
#
# Pulls only the specific leaf fields actually rendered below, not whole
# submodules -- `nix eval --json` force-serializes every field of a
# submodule, including unset ones with no default.
# plan: 2026-09-03-auto-generated-per-host-inventory-doc-services-packages-containers.md#G3
read -r -d '' apply_rest <<'NIX' || true
cfg:
let
  safe =
    default: v:
    let
      r = builtins.tryEval v;
    in
    if r.success then r.value else default;
  # nixbld1..N and `nobody` are boilerplate every host gets purely from
  # having Nix builds/an idle daemon UID -- not a "this host runs X"
  # signal, so they're dropped rather than drowning out the handful of
  # actually-dedicated service users (e.g. health-check, android-smb).
  # Everything else with isSystemUser is kept even though some of it is
  # still auto-created by whichever service module needed it (sshd,
  # rtkit, ...), not hand-declared by this repo -- there's no mechanical
  # way to tell those apart from evaluated config alone.
  # plan: 2026-09-03-auto-generated-per-host-inventory-doc-services-packages-containers.md#G3
  isBoilerplateSystemUser = n: (builtins.match "nixbld[0-9]+" n != null) || n == "nobody";
in
{
  packages = map (p: p.pname or p.name or "?") cfg.environment.systemPackages;
  containers = builtins.attrNames (cfg.virtualisation.oci-containers.containers or { });
  filesystems = builtins.mapAttrs (n: fs: {
    device = safe null (fs.device or null);
    fsType = safe null (fs.fsType or null);
  }) cfg.fileSystems;
  timers = builtins.mapAttrs (n: t: {
    # confirmed live: this comes through as either a bare string or a
    # list depending on how the defining module set it -- not
    # normalized to one shape, so the jq side has to branch on type.
    onCalendar = safe [ ] (t.timerConfig.OnCalendar or [ ]);
  }) cfg.systemd.timers;
  firewallInterfaces = builtins.mapAttrs (n: i: {
    tcp = safe [ ] (i.allowedTCPPorts or [ ]);
    udp = safe [ ] (i.allowedUDPPorts or [ ]);
  }) cfg.networking.firewall.interfaces;
  # host-wide (not interface-scoped) ports -- this repo's convention is
  # interface-scoped (see firewallInterfaces above), but the option
  # exists and a host could still use it.
  firewallAllTCP = safe [ ] (cfg.networking.firewall.allowedTCPPorts or [ ]);
  firewallAllUDP = safe [ ] (cfg.networking.firewall.allowedUDPPorts or [ ]);
  # extraCommands/extraStopCommands are raw iptables shell script, not
  # structured data -- not parsed for actual ports, just flagged as
  # present so a reader knows to go read them directly rather than
  # assuming the structured fields above are the whole picture.
  firewallHasExtraCommands = safe false (
    (builtins.stringLength (cfg.networking.firewall.extraCommands or "")) > 0
  );
  usersHuman = builtins.filter (
    n: safe false (cfg.users.users.${n}.isNormalUser or false)
  ) (builtins.attrNames cfg.users.users);
  usersSystem = builtins.filter (
    n:
    !(isBoilerplateSystemUser n) && safe false (cfg.users.users.${n}.isSystemUser or false)
  ) (builtins.attrNames cfg.users.users);
  secrets = builtins.attrNames (cfg.sops.secrets or { });
}
NIX

# fetch_services <host> -- prints a JSON array of enabled service names.
#
# Some nixpkgs option-compat shims call `builtins.abort` (uncatchable by
# `tryEval`) instead of `throw` on read, crashing a batch probe of
# `cfg.services`. Retries the probe, parsing the offending top-level
# service name out of nix's error trace and excluding it, rather than
# hardcoding a list that would rot as nixpkgs adds more of these.
# plan: 2026-09-03-auto-generated-per-host-inventory-doc-services-packages-containers.md#G3
fetch_services() {
	local host=$1
	local excluded=()
	local max_retries=20
	local exclude_nix errfile bad services_json e

	while true; do
		exclude_nix="[ "
		for e in "${excluded[@]}"; do
			exclude_nix+="\"$e\" "
		done
		exclude_nix+="]"

		errfile=$(mktemp)
		if services_json=$(nix eval --json ".#nixosConfigurations.$host.config.services" --apply "
cfg:
let
  excluded = $exclude_nix;
  safeEnable = n: let r = builtins.tryEval (cfg.\${n}.enable or false); in r.success && r.value;
in
builtins.filter (n: !(builtins.elem n excluded) && safeEnable n) (builtins.attrNames cfg)
" 2>"$errfile"); then
			rm -f "$errfile"
			echo "$services_json"
			return 0
		fi

		if ((${#excluded[@]} >= max_retries)); then
			echo "==> $host: giving up after excluding $max_retries broken services.* options" >&2
			cat "$errfile" >&2
			rm -f "$errfile"
			return 1
		fi

		bad=$(grep -oP "while evaluating the option \`services\.\K[^.']+" "$errfile" | head -1)
		if [[ -z "$bad" ]]; then
			echo "==> $host: services probe failed and the offending option name couldn't be extracted from nix's error output:" >&2
			cat "$errfile" >&2
			rm -f "$errfile"
			return 1
		fi
		# plan: 2026-09-03-auto-generated-per-host-inventory-doc-services-packages-containers.md#F3
		# $bad gets spliced into evaluated Nix source above (`excluded =
		# [ "$e" ... ]`) -- require a plain identifier rather than
		# escaping arbitrary content, so nothing nix's stderr could ever
		# contain can break out of that string literal.
		if [[ ! "$bad" =~ ^[A-Za-z0-9_-]+$ ]]; then
			echo "==> $host: extracted option name '$bad' isn't a plain identifier -- refusing to splice it into evaluated Nix source, giving up" >&2
			cat "$errfile" >&2
			rm -f "$errfile"
			return 1
		fi

		echo "==> $host: excluding services.$bad (broken rename/removal compat shim upstream, not something this repo can fix) and retrying" >&2
		excluded+=("$bad")
		rm -f "$errfile"
	done
}

# jq helper prepended to every rendering call below, collapsing the
# repeated "empty list -> _none_, else render" branch each section needs.
or_none='def orNone(f): if length == 0 then "_none_" else f end;'

# Every mktemp'd path across every host, removed on exit -- matches
# scripts/bootstrap-host.sh's trap-cleanup convention.
# plan: 2026-09-03-auto-generated-per-host-inventory-doc-services-packages-containers.md#F1
tmpfiles=()
trap 'rm -f "${tmpfiles[@]}"' EXIT

for host in "${hosts[@]}"; do
	readme="hosts/$host/README.md"
	[[ -f "$readme" ]] || {
		echo "no README.md for host '$host' at $readme" >&2
		exit 1
	}

	echo "==> evaluating $host" >&2
	# apply_rest and fetch_services each do their own full evaluation of
	# the host's config and don't depend on each other's output -- run
	# them concurrently rather than paying nix's eval cost twice in a row.
	rest_file=$(mktemp)
	services_file=$(mktemp)
	blockfile=$(mktemp)
	tmp=$(mktemp)
	tmpfiles+=("$rest_file" "$services_file" "$blockfile" "$tmp")

	nix eval --json ".#nixosConfigurations.$host.config" --apply "$apply_rest" >"$rest_file" &
	rest_pid=$!
	fetch_services "$host" >"$services_file" &
	services_pid=$!
	wait "$rest_pid"
	wait "$services_pid"

	json=$(jq -n --argjson rest "$(<"$rest_file")" --argjson services "$(<"$services_file")" '$rest + { services: $services }')

	{
		echo "## Host Inventory"
		echo
		echo "_Auto-generated from \`nixosConfigurations.$host\`. Regenerate with"
		echo "\`scripts/doc-host.sh $host\` -- do not hand-edit between the markers._"
		echo
		echo "### Services (enabled)"
		echo
		jq -r "$or_none"' .services | orNone(sort | join(", "))' <<<"$json"
		echo
		echo "### Packages"
		echo
		jq -r "$or_none"' .packages | orNone(unique | join(", "))' <<<"$json"
		echo
		echo "### Containers"
		echo
		jq -r "$or_none"' .containers | orNone(sort | map("- `" + . + "`") | join("\n"))' <<<"$json"
		echo
		echo "### Storage (ZFS / network filesystems)"
		echo
		jq -r "$or_none"'
			.filesystems
			| to_entries
			| map(select(.value.fsType == "zfs" or ((.value.fsType // "") | test("^nfs"))))
			| sort_by(.key)
			| orNone(map("- `" + .key + "` <- `" + (.value.device // "-") + "` (" + .value.fsType + ")") | join("\n"))
		' <<<"$json"
		echo
		echo "### Firewall"
		echo
		jq -r "$or_none"'
			def portList(p): (((p // []) | map(tostring) | join(",")) as $s | if $s == "" then "-" else $s end);
			[
				(if ((.firewallAllTCP // []) | length) > 0 or ((.firewallAllUDP // []) | length) > 0 then
					["- (all interfaces): TCP " + portList(.firewallAllTCP) + " / UDP " + portList(.firewallAllUDP)]
				 else [] end),
				(
					.firewallInterfaces
					| to_entries
					| sort_by(.key)
					| map("- `" + .key + "`: TCP " + portList(.value.tcp) + " / UDP " + portList(.value.udp))
				),
				(if (.firewallHasExtraCommands // false) then
					["- plus custom `networking.firewall.extraCommands` iptables rules -- see the host'"'"'s configuration.nix, not captured here"]
				 else [] end)
			]
			| add
			| orNone(join("\n"))
		' <<<"$json"
		echo
		echo "### Scheduled jobs (systemd timers)"
		echo
		jq -r "$or_none"'
			.timers
			| to_entries
			| sort_by(.key)
			| orNone(map(
				"- `" + .key + "`: "
				+ (
					(.value.onCalendar | if (type == "array") then (map(select(. != "")) | join(", ")) else . end) as $oc
					| if $oc == "" then "-" else $oc end
				)
			  ) | join("\n"))
		' <<<"$json"
		echo
		echo "### Users"
		echo
		echo "Human:"
		jq -r "$or_none"' .usersHuman | orNone(sort | map("`" + . + "`") | join(", "))' <<<"$json"
		echo
		echo "System (excludes nixbld*/nobody; may include accounts a service"
		echo "module auto-creates, not just ones this repo hand-declares):"
		jq -r "$or_none"' .usersSystem | orNone(sort | map("`" + . + "`") | join(", "))' <<<"$json"
		echo
		echo "### Secrets in use"
		echo
		jq -r "$or_none"' .secrets | orNone(sort | map("`" + . + "`") | join(", "))' <<<"$json"
	} >"$blockfile"

	# Single pass: replace the block in place if the markers already
	# exist, otherwise append a fresh one at EOF -- the END block only
	# fires when the start marker was never seen. plan:
	# 2026-09-03-auto-generated-per-host-inventory-doc-services-packages-containers.md#F4
	# -- error out instead of silently truncating everything after an
	# unpaired start marker (no matching end before EOF); $tmp is left
	# with the partial write but $readme is never overwritten, since the
	# `mv` below doesn't run once this fails under `set -e`.
	awk -v start="$start_marker" -v end="$end_marker" -v blockfile="$blockfile" -v readme="$readme" '
		$0 == start {
			print
			while ((getline line < blockfile) > 0) print line
			skipping = 1
			found = 1
			next
		}
		$0 == end && skipping { print; skipping = 0; next }
		skipping { next }
		{ print }
		END {
			if (!found) {
				print ""
				print start
				while ((getline line < blockfile) > 0) print line
				print end
			} else if (skipping) {
				print "unpaired " start " in " readme " (no matching " end " before EOF) -- refusing to write" > "/dev/stderr"
				exit 1
			}
		}
	' "$readme" >"$tmp"
	mv "$tmp" "$readme"

	echo "==> updated $readme" >&2
done
