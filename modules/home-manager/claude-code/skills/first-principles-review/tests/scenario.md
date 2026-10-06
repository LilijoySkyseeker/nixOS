# Design for review: secure agent sandbox

**Context.** A single developer runs a small NixOS fleet: a desktop
("torrent"), a laptop, a homelab server and a VPS. They use Claude Code
agents heavily for:
- internet research;
- work on their NixOS config repo (which deploys to the machines);
- side projects.

Today the agents run as the developer's own user on the desktop. That user
holds SSH keys that are root on the servers, the age key that decrypts every
secret, and push access to the deploy branch. The developer wants agents to be
"highly autonomous and very secure", and asked for this design.

## Proposed design (v1)

1. **Isolation.** Every agent runs in an ephemeral microvm.nix VM (QEMU),
   drawn from a pool of 5 declarative "slot" VMs, 4–8 GiB RAM each, sharing
   the host /nix/store read-only over virtiofs.
2. **Network.** An isolated bridge with no NAT. A host-side squid HTTP CONNECT
   proxy with per-task hostname allowlist profiles (inference-only, +nix cache,
   +docs, +open-web for research). Denied RFC1918/tailnet destinations.
3. **Credentials.** An inference-only `claude setup-token` passed in as a
   systemd credential via fw_cfg, never on the kernel command line. No SSH,
   gh or sops material in the VM.
4. **Repo access.** Each VM gets its own clone. Work comes back as a `git
   bundle` in an outbox share. A host intake service verifies the bundle with
   `transfer.fsckObjects`, rejects bundles touching `.github/`, and fetches it
   into a branch.
5. **Dispatch.** A polkit rule lets the dispatcher run `systemctl start
   microvm@slot-N`.
6. **Work model** (borrowed from a multi-agent tool):
   - persistent named "seats" (roles), each with a role file and accumulated
     notes;
   - a work queue with mandatory closure reasons;
   - agent-to-agent messaging through a mediated, logged channel;
   - snapshot/restore of seats;
   - compaction handover packets.
7. **Attention.** A dashboard of "needs you" items, with phone-friendly
   multiple-choice decisions, fed by a per-VM state exporter.
8. **Knowledge.** Research notes are written to the developer's notes vault
   with provenance frontmatter (session, model, date) so injected or wrong
   notes can be traced.
9. **Fleet operations.** A separate "ops" VM holds fleet root via per-session
   short-lived SSH certificates issued after the developer approves on their
   phone.
10. **Inner sandbox.** Inside each VM, Claude Code's own bubblewrap Bash
    sandbox is also enabled, with deny rules protecting the token file.
11. **Backups.** The VM credential dataset is excluded from zrepl/restic.

Estimated effort: 4–8 weeks.
