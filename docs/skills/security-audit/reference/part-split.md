# Splitting the repo into audit parts

## The principle

Split by **blast radius and trust role**, not by directory. A part
should answer a question like "what can run code as root fleet-wide?"
or "what does every host inherit?" — questions a directory listing does
not answer.

Each part must be coherent enough to audit without the others, and
every cross-cutting concern is assigned to exactly one owner so
findings don't arrive eight times.

Aim for parts of roughly comparable weight, but do not force it — the
vps part was 827 lines and the backup part 1,232, and both were right
as single units because splitting either would have cut a trust
boundary in half.

## The 2026-08-26 split

~6.9k lines of Nix across 5 hosts. Eight parts.

| Part | Scope | Lines | Why it is its own part |
|---|---|---|---|
| **P1** | `modules/profiles/{default,server,PC}.nix` | ~635 | Highest blast radius — every host inherits it. A finding here is a fleet-wide finding. |
| **P2** | `hosts/vps/*` | ~827 | The only host with real public listeners. The one genuinely adversarial boundary. |
| **P3** | `hosts/homelab/*` | ~742 | Holds the data and the backups; the host whose environment assumption broke. |
| **P4** | `modules/services/*` | ~625 | The actually-exposed services, incl. two parsing untrusted internet input. |
| **P5** | `hosts/{thinkpad,torrent}/*` | ~550 | Interactive machines — the most likely initial foothold; one roams. |
| **P6** | `modules/nixos/{zrepl,zfs-space-guard,nfs-homelab-mounts}.nix` + `tests/` | ~1232 | Protects asset #1, runs as root everywhere, and its threat is an *authorized* peer. |
| **P7** | `modules/nixos/{auto-update,pull-deploy,push-deploy,iso-autobuild,health-alerts}.nix`, `modules/flake/deploy-guards.nix`, `scripts/`, `.githooks/` | ~899 | "What can cause code to run as root across the fleet." |
| **P8** | `flake.nix`, `flake.lock`, `modules/flake/*`, `modules/home-manager/*`, `modules/nixos/{tooling,kde,virtual-machines,wooting}.nix`, `.sops.yaml`, all `sops.secrets` declarations, `docs/tailscale-acl.json`, `files/` | — | Supply chain and secrets plumbing — how untrusted code and untrusted data enter. |

## What this split got right

**Separating the shared profile (P1) from the hosts.** It made
"inherited by everything" a first-class question, and P1 found the
grants nobody had looked at because they were not in any host file.

**Making the deploy machinery its own part (P7).** It confirmed the
audit's most consequential privilege path with four independent
mechanisms, which no host-scoped part would have assembled.

**Putting secrets *plumbing* in P8 while everyone could observe
symptoms.** Five parts independently reported the `.sops.yaml` problem
from their own angle; P8 owned the remediation design. That redundancy
was a feature — convergence from five directions is far stronger
evidence than one report.

**Giving P8 `claude-code.nix`.** An AI agent running as the desktop
user, on the machine that holds fleet-root credentials, had never been
audited and did not appear in any seed list until it was deliberately
assigned.

## What to watch when re-splitting

- **Things that belong to no part.** `octodns.nix` nearly escaped
  entirely — it holds a DNS credential, and DNS control enables
  certificate issuance. Sweep for files no part claims before
  dispatching.
- **A part that is really two.** If a brief needs more than ~8 priority
  areas, it is probably two parts.
- **Call sites vs. modules.** Say explicitly that a host part owns its
  own `myFoo = { ... }` argument blocks even though the module belongs
  to another part. Without that sentence, both agents skip it.
- **Where live access exists**, note which host each agent is running
  on. It changes what they can prove.
