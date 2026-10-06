---
paths:
  - "hosts/**"
  - "modules/**"
  - ".sops.yaml"
---

# Hardening

Before adding a service, opening a port, wiring a secret or adding a
container, read the standing rules in `docs/hardening.md`. The short form:

1. Rotating a sops recipient is not rotating the secret values (the repo is public).
2. Give each host only the secrets it consumes (per-path `creation_rules`).
3. Never generate key material on a snapshotted or replicated filesystem.
4. Docker-published ports bypass the NixOS firewall; bind them to an address.
5. Scope every firewall rule to an interface.
6. Put privilege on the unit (`SupplementaryGroups`), not the user.
7. Never point a root service at a user-writable path.
8. Keep one backup copy outside the authority of any single root.
9. Verify config actually takes effect (`sshd -T`, `nix eval`), not that it rendered.
10. Containers: publish to an address, pin by digest, drop caps, no-new-privileges, read-only, memory and pids limits.
11. A guard that declines to act must be watched by its outcome, not its attempt; never hang `OnSuccess=` off a unit that can skip.

A change that touches firewall rules, open ports, secrets wiring,
authentication, or adds or exposes a service gets `/security-review`
before the PR opens.
