# Remediation plan

Phase 3 of the 2026-08-26 audit. Sequenced into waves rather than one
branch, because the fixes have very different risk profiles and the
shared-profile ones move every host at once.

**Gates every wave passes**, per the repo's own rules:
`nixos-rebuild build --flake .#<host>` for each affected host
(`feedback_build_before_commit`), a VM test where *behaviour* changes
rather than just config, and **no `switch` without being asked**
(`feedback_test_dont_switch`). Build-only is free; switching changes a
running machine.

**What an agent may not do here.** Anything touching `secrets/*` is
manual (`docs/procedures/secrets.md`). Anything in §5 of
[`findings.md`](findings.md) is a user decision. Wave 3 is therefore a
checklist for the user, not work to be done unattended.

---

## Wave 0 — immediate, outside the repo

Not config changes; live state. Listed with exact commands so they can
be run without re-deriving anything.

| # | Action | Command |
|---|---|---|
| 0.1 | Close the world-readable age identity (N3) | `chmod 600 ~/.config/sops/age/keys.txt` |
| 0.2 | Remove the leaked zrepl key from `/tmp` (N1) — **after** rotating, since deleting does not retract the snapshot copies | `shred -u /tmp/homelab_zrepl_key` |
| 0.3 | Settle the last open verification (H9) when thinkpad is next up | `passwd -S lilijoy` |
| 0.4 | Check GitHub branch protection (D3) | web UI — with no CI, this is the only remaining control on fleet root |

0.1 is free and reversible and should not wait. 0.2 must follow the
rotation in Wave 3, not precede it.

---

## Wave 1 — zero-decision config fixes

Everything here is unambiguous, needs no judgement call from the user,
and is verifiable by a build. This is the wave to land first.

| # | Fix | Finding | Files | Risk |
|---|---|---|---|---|
| 1.1 | Move the `disk` grant from the `health-check` *user* to the one unit that needs it, via `serviceConfig.SupplementaryGroups` | H2 (`F-P3-02` `F-P2-05` `F-P7-05`) | `modules/nixos/health-alerts.nix` | low — narrows only |
| 1.2 | Fix the arithmetic injection: quote and validate the remote-supplied timestamp before arithmetic | H5 (`F-P7-03`) | `modules/flake/deploy-guards.nix:61` | low |
| 1.3 | Invert the routing default: `"client"` in the shared profile, `mkForce "both"` on homelab only, drop vps's now-redundant override, and remove homelab's redundant explicit sysctls **in the same change** | H4 (`F-P0-06` `F-P1-06` `F-P5-08` `F-P3-20`) | `modules/profiles/default.nix`, `hosts/{homelab,vps}/configuration.nix` | medium — see note |
| 1.4 | Interface-scope the desktop profile's host-wide openings (avahi, Steam remote play, KDE Connect) to the LAN interface or tailscale0 | H4 (`F-P1-04` `F-P5-06`) | `modules/profiles/PC.nix` | medium — breaks discovery if scoped wrong |
| 1.5 | Remove `initialPassword = "123456"` | H9 (`F-P1-03`) | `modules/profiles/PC.nix:306` | low — but confirm 0.3 first for thinkpad |
| 1.6 | Delete the inert `ssh` block from the tailnet ACL reference copy, and from the console | H10 (`F-P0-05` `F-P8-12`) | `docs/tailscale-acl.json` | none — nothing uses it |
| 1.7 | Drop the nine declared-but-unconsumed secret declarations | C1 (`F-P8-11`) | per-host `sops.secrets` | low — verify no consumer first |
| 1.8 | Add `programs.ssh.knownHosts` for `github.com` and `vps` so the deploy path stops re-TOFUing every boot | H1 (`F-P7-04` `F-P3-05` `F-P0-07`) | `modules/profiles/default.nix` | low — a stale pin blocks updates, so pair with 1.9 |
| 1.9 | Enable `myHealthAlerts` on both laptops so a failed or skipped deploy is visible at all | H1 (`F-P7-09`) | `hosts/{torrent,thinkpad}/configuration.nix` | low |

**Note on 1.3.** Tailscale sets the forwarding sysctls at
`mkOverride 97`, so a plain `boot.kernel.sysctl` assignment loses
silently — only `mkForce` or changing `useRoutingFeatures` works
(`F-P1-06`). Getting it backwards silently breaks homelab's exit node
and its `192.168.1.0/24` subnet route, which is connectivity-visible
but **not** build-visible. Verify with `tailscale status` after any
eventual deploy.

**Note on 1.4.** The mechanism is already proven on these hosts — port
22 is interface-qualified on torrent while everything else is not, so
this is applying an existing pattern rather than inventing one. KDE
Connect has no upstream `openFirewall` toggle, so the range is written
by hand and must be rewritten by hand.

---

## Wave 2 — needs a VM test or careful staging

Behaviour changes, not just config. Each needs
`docs/procedures/vm-testing.md` treatment before it is trusted.

| # | Fix | Finding | Why it needs more than a build |
|---|---|---|---|
| 2.1 | Stop docker publishing past the firewall — bind published ports to a specific address, or add a host-level `DOCKER-USER` allowlist for both v4 and v6 | H3 (`F-P4-02` `F-P3-04`) | changes the packet path for four live game servers; get it wrong and either they are unreachable or still exposed |
| 2.2 | Pin the container images by digest and pin the Modrinth mod set | H3 (`F-P4-03`) | changes what actually runs; needs a start-and-play check |
| 2.3 | Bring both laptops' sshd up to the repo's own baseline, and correct the `AllowTcpForwarding` default claim in the doc | MEDIUM cluster (`F-P5-07` `F-P2-09` `F-P3-18` `F-P6-10`) | verify with `sshd -T` against the pinned module, per P3's method — do not assume a directive takes effect |
| 2.4 | Replace the `input` group grant with `hardware.uinput.enable` | C2 (`F-P1-01` `F-P8-09`) | plover must still work; this is a real functional dependency, not dead config |
| 2.5 | Add `nosuid`/`nodev`/`noexec` to the NFS client mounts | MEDIUM (`F-P6-05`) | could break execution from `/storage` if anything relies on it |
| 2.6 | Sandbox the three under-hardened root units | MEDIUM (`F-P2-08` `F-P6-06` `F-P7-06`) | `push-deploy-vps` does no local activation, so the carve-out does not apply to it |
| 2.7 | Guard the `ipset create` calls so a parameter drift cannot take the whole packet filter down fail-open | MEDIUM (`F-P2-02`) | touches vps's firewall start path — the one host where a mistake is internet-facing |
| 2.8 | `zfs hold` on `@blank`, and `recv.properties.override` on the pull jobs | C3/H8 (`F-P6-04` `F-P6-03`) | changes replication behaviour; the existing VM tests do not cover it (`F-P6-14`) |

---

## Wave 3 — user decisions and manual secret work

Not agent work. Ordered by value.

1. **Rotate the ten credentials** exposed by `F-P8-02`, at each
   provider: Backblaze, Cloudflare, tailscale, both WireGuard keypairs
   and the PSK, the Discord webhook, the vps-deploy keypair, the zrepl
   keypair. Re-keying `.sops.yaml` does nothing retroactively. (D1)
2. **Restructure `.sops.yaml` into per-path `creation_rules`** so each
   host holds only what it consumes — the only change that bounds
   future exposure. (C1)
3. **Attribute or retire the five unattributable recipients**
   (`F-P8-05`).
4. **Buy immutability**: an append-only Backblaze key plus Object Lock
   — the single highest-value change for asset #1. (D4)
5. **Decide on unsigned `origin/master`** (D2): accept and write it into
   `docs/hardening.md` as an explicit risk, or add `git verify-commit`
   against an allowed-signers file, failing closed. Note `F-P7-07`
   auto-merges upstream input updates on build success alone, which
   should probably stop regardless.
6. **Decide on the tailnet ACL** (D6) — and fix the vps half
   (`trustedInterfaces`) either way, since that is where the blast
   radius is actually unbounded.
7. **Decide on FDE** (D5), intrusion detection (D7), and the recovery
   ISO's access model (D8).

Also here, because it changes key handling rather than config:
`bootstrap-host.sh` should generate into a tmpfs and scrub on failure
rather than preserving (`F-P7-08`).

---

## Wave 4 — documentation harvest

Phase 4 of the audit proper. The eleven systemic rules in
[`findings.md`](findings.md) §4 go into `docs/hardening.md`, the threat
model becomes a standing doc, accepted risks get written down with
their reasoning, and deferred items land in `TODO.md`. Tracked
separately.
