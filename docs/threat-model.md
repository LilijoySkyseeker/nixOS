# Threat model

Who and what can hurt this fleet, what crossing each trust boundary buys
them, and how to rate a finding. Rewritten 2026-10-25 from the 2026-08-26
audit's model (in git history: `git show
0aa27a5:docs/audits/2026-08-26/00-threat-model.md`), which still described
a vps with Caddy, Anubis and CrowdSec and missed the agent.

## 1. What we protect

In order of how bad losing it would be:

1. **The backups.** `zbackup` on homelab is the only consolidated copy of
   every host's data, and the restic copy on Backblaze B2 is made from it.
   Destroying backups turns every other incident into permanent loss.
2. **Root on any host**, because root on one converts into root on others
   (§3).
3. **The secrets** in `secrets/` and the age keys that decrypt them.
4. **`master` on GitHub**, which is root on every host (B1).
5. **Personal data at rest**: `/storage`, `/storage-bulk`, home
   directories.
6. **Availability** of what people use: Jellyfin, Immich, the game
   servers, the shares, the website. Real, but recoverable in a way the
   others aren't.

## 2. What is exposed

| From | Reaches |
|---|---|
| The internet | vps: WireGuard 51820/udp, and DNAT to homelab over wg0 for Minecraft (25565/tcp, 19132/udp), Hytale (5520/udp) and the website (80, 443 to a sandboxed Caddy). Per-source-IP hashlimits on vps are the only control in front of them, and they rate-limit, not authenticate. |
| The internet, IPv6 | homelab's LAN NIC has a public IPv6 with nothing open on it. Docker's IPv6 and userland-proxy are off, which keeps the docker-published game ports off it. |
| The LAN | homelab's docker-published game ports. Everything else is scoped to `tailscale0` or `wg0`. |
| The tailnet | nearly everything: the ACL (`docs/tailscale-acl.json`) is flat, homelab advertises the LAN route and an exit node, and vps trusts `tailscale0` outright. |
| GitHub | every host pulls `master` over HTTPS and deploys it (B1). |

homelab is behind CGNAT on IPv4; vps is its only public front door.

## 3. Trust boundaries, and what crossing one buys

**B1 — `master` is root on every host.** homelab switches to `master`
Tue 03:00, torrent and thinkpad stage it for their next boot Thu 03:00,
and homelab pushes its own revision to vps Wed 03:00
(`docs/architecture.md`, "Updates & deploy"). Nothing checks a signature.
The gate is the owner's merge: agent PRs from `LilijoySkyseeker-agent`
(write role) show as review-required, though the `master` ruleset lists 0
required approvals, so which setting blocks a self-merge is unverified.
Anyone who can merge, or who controls a flake input (about 15 direct, all
effectively unreviewable in a lock bump), has the fleet.

**B2 — homelab is root on vps, by design.** homelab is vps's deployer;
the `vps-deploy` ForceCommand dispatcher bounds shells and accidents, not
privilege (AR-2). Treat the two as one blast radius.

**B3 — `lilijoy` reaches far.** On the PCs, `wheel` plus run0 is root
after a password prompt. The user-owned SSH keys on torrent and thinkpad
are in `publicSshKeys`, so anything running as `lilijoy` (a browser
exploit, a bad npm package) gets root on homelab and vps, and homelab
holds the backups. The user-level age keys (`torrent-age`,
`thinkpad-ssh`) decrypt every secret in `secrets/secrets.yaml`.

**B4 — any tailnet device reaches nearly everything** (§2). The ACL's
`ssh` rules are inert only because no host runs `tailscale up --ssh`;
turning that on anywhere would grant root SSH past
`forced-commands-only`. Open decision D6.

**B5 — backups answer to root on homelab.** Sources can't hurt their own
history: homelab pulls, and each zrepl key is pinned to one
`stdinserver` identity (AR-3). But root on homelab can destroy `zbackup`
and, with its B2 key, the offsite copy too (open decision D4). torrent's
and thinkpad's homes have no offsite copy.

**B6 — the internet reaches code on homelab.** The game servers parse
untrusted input and update themselves: Minecraft's mods resolve at every
start, Hytale replaces its own server binaries (AR-7). Caddy serves the
website. What bounds a compromise: userns-remap and resource limits on
the Minecraft container, the systemd sandbox on Hytale, and Caddy's
sandbox (no LAN, tailnet or loopback services, `tests/website.nix`).

**B7 — the configuration is public.** No control may rely on an attacker
not knowing it exists. The encrypted secrets are public ciphertext
forever, so a host or user key compromised at any time decrypts every
secret that key could ever read, and removing a recipient protects
nothing without rotating the values (`hardening.md` rule 1). Anyone can
open a PR (AR-1, AR-5).

**B8 — the `agent` user on torrent.** AI agents run there with no
permission prompts, so treat it as prompt-injectable. It reaches the
internet, `~agent`, the research vault through bindfs, the nix daemon,
the GPU, and GitHub as `LilijoySkyseeker-agent` (PRs; B1 holds the
merge). It does not reach the LAN, the tailnet, `/run/tailscale` or
`lilijoy`'s home: the Unix user, the `agent-egress` chain and the socket
hiding are the boundary (`hardening.md`, "The `agent` user"). Changes to
`agent-user.nix` and `agent-jobs/` change this boundary.

## 4. The realistic threats, ranked

1. **Ordinary mistakes.** A bad merge deploys itself unattended (B1), a
   lost YubiKey or host key, a dead disk, an alert that never fires.
   Most likely by far; the backups, rollback, the recovery YubiKeys and
   the health alerts are the controls.
2. **Code running as `lilijoy` or `agent`.** A browser exploit, a
   malicious package, an injected agent. For `lilijoy` it leads to the
   SSH keys and age keys (B3); for the agent to a PR the owner merges
   (B1, B8).
3. **A game-server or Caddy compromise** through vps's DNAT (B6), landing
   on homelab next to the data.

Rare but total: a malicious flake input or nixpkgs commit (B1).

## 5. Rating a finding

Rate by **reachable impact**: who can actually reach it (name the
threat and the path), not how alarming the setting looks.

- **Critical**: unauthenticated remote root or code execution, root on
  every host, or destruction of the backups.
- **High**: root or full data access after a plausible first step
  (code as `lilijoy` or `agent`, a tailnet device, a stolen laptop), or a
  secret readable by a principal that shouldn't hold it.
- **Medium**: more reach than a principal needs, behind a chain or a
  non-default condition; a broken `hardening.md` rule.
- **Low**: defence-in-depth gaps, observability holes.
- **Info**: dead config, docs that no longer match the code.

State confidence: confirmed (read and checked against the pinned
nixpkgs) or plausible (inferred).

## 6. Non-goals

- Nation-state or targeted-APT resistance.
- Multi-user separation beyond `agent`: these are one person's machines,
  and root login where allowed is intentional.
- Tailscale's coordination server and DigitalOcean's hypervisor are
  trusted.
- Surviving a determined flood: rate limits keep the game servers usable,
  nothing more.
- The secrets' plaintext: agents never decrypt `secrets/*`; only the
  plumbing (recipients, modes, who reads which path) is in scope.

## Using it

- **Before exposing anything new**, find the boundary it sits on in §3
  and whether it moves one.
- **Before accepting a risk**, write it into
  [`accepted-risks.md`](accepted-risks.md) with its boundary.
