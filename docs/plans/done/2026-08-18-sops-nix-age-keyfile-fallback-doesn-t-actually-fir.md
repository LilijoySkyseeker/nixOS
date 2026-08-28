---
slug: sops-nix-age-keyfile-fallback-doesn-t-actually-fir
created: 2026-08-18
status: done
frozen: true
---

# sops-nix `age.keyFile` fallback doesn't actually fire when `age.sshKeyPaths` fails during early boot

## Original plan

- [x] **2026-08-18: sops-nix `age.keyFile` fallback doesn't actually
      fire when `age.sshKeyPaths` fails during early boot** (torrent).
      `profiles/PC.nix` configures both `sops.age.sshKeyPaths = [
      "/home/lilijoy/.ssh/id_ed25519" ]` and `sops.age.keyFile =
      "/var/lib/sops-nix/key.txt"`, with `keyFile` explicitly intended
      as the early-boot fallback since `/home` isn't mounted yet during
      initrd-stage activation (see the comment there). On a real boot,
      the initrd-stage `sops-install-secrets` run failed entirely
      (`Cannot read ssh key '/home/lilijoy/.ssh/id_ed25519': ... no such
      file or directory` immediately followed by `Error getting data
      key: 0 successful groups required, got 0`) instead of falling
      back to `keyFile` — `/run/secrets` never got populated for the
      rest of that boot (git identity, and presumably other
      home/root-critical secrets, all missing) until manually re-run
      post-boot via `run0 sops-install-secrets ...` (which then
      succeeded immediately, confirming `key.txt` itself and its
      `.sops.yaml` registration were never the problem). Looks like a
      real sops-nix bug/limitation: a failed `sshKeyPaths` entry seems
      to poison the whole identity list rather than gracefully falling
      through to `keyFile`. Needs: check for a known upstream sops-nix
      issue/fix, or restructure so boot-critical secrets don't depend on
      an identity path that's guaranteed to fail during initrd (e.g.
      drop `sshKeyPaths` from the boot-time identity list entirely and
      rely on `keyFile` alone there). Not yet reproduced against a clean
      reboot (holding off per the no-unconfirmed-local-restarts rule).

      **Confirmed still present in code, 2026-08-25** (path moved to
      `modules/profiles/PC.nix` post-dendritic, same content): both
      `sops.age.sshKeyPaths` and `sops.age.keyFile` are still configured
      in the same vulnerable order, unchanged. Still open, still
      unreproduced against a clean reboot.

      **Root cause identified and landed 2026-08-26.** Checked against
      the pinned sops-nix source (`Mic92/sops-nix` rev
      `a8627b21b9107c5711c96b84f32a9a4b3d45295f`, per `flake.lock`):
      `sops.age.sshKeyPaths` is a NixOS module option that *only* feeds
      `sops-install-secrets`' boot-time manifest (`importAgeSSHKeys` in
      `pkgs/sops-install-secrets/main.go`) — it has zero effect on
      interactive `sops` CLI editing, which is driven entirely by the
      `sops` binary's own identity discovery
      (`SOPS_AGE_SSH_PRIVATE_KEY_FILE` env var or
      `~/.config/sops/age/keys.txt`, confirmed as a native
      `getsops/sops` feature in `age/keysource.go`, independent of this
      NixOS module). PC.nix's own comment had assumed the option
      enabled interactive edits as lilijoy; it never did. Since `/home`
      is never mounted at the point `sops-install-secrets` actually
      runs, this identity was always guaranteed to fail there — pure
      downside, no upside. The general failure class ("a configured
      ssh key path missing at activation time breaks
      `sops-install-secrets`") is also a known, still-open upstream
      limitation (`Mic92/sops-nix#167`), whose community-standard
      workaround is exactly what this item already proposed: drop the
      ssh key path from the boot-time identity list and rely on
      `keyFile`+`generateKey` alone. Removed `sops.age.sshKeyPaths`
      from `modules/profiles/PC.nix` (shared by both torrent and
      thinkpad) and rewrote the comment to explain why. `nixos-rebuild
      dry-build` confirmed clean for both `torrent` and `thinkpad`.
      Not yet deployed/switched to either host — a plain config
      cleanup with no functional secret-decryption change at boot (the
      ssh key path never worked there), so no urgency to switch ahead
      of each host's normal rebuild cadence.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
