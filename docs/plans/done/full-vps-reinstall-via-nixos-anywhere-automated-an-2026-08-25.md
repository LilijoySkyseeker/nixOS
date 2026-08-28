---
slug: full-vps-reinstall-via-nixos-anywhere-automated-an
created: 2026-08-25
status: done
frozen: true
---

# full vps reinstall via nixos-anywhere, automated and documented

## Original plan

- [x] **2026-08-25: full vps reinstall via nixos-anywhere, automated and
      documented** (branch `worktree-vps-reinstall`, PR #13). Follow-up
      to the vps-bricked entry below — declared unrecoverable rather
      than chasing the boot race further. Added `scripts/bootstrap-
      host.sh <host> <target-ip|--vm-test>`, generalizing the sops/
      tailscale chicken-and-egg (pre-generate host SSH key outside the
      repo, enroll its age key in `.sops.yaml`, `sops updatekeys`)
      followed by the `nixos-anywhere` invocation itself — see
      `hosts/vps/README.md`'s "Reinstall" section for the worked
      example, including the `--persist-root /persist` flag
      impermanence hosts need (a key written to plain `/etc/ssh`
      vanishes on the first real boot on a tmpfs-root host) and why the
      new tailscale key has to be set *before* the install runs, not
      after (the fresh box needs a working key the moment it boots).
      Tried `--vm-test` before touching the real droplet; hit two hard
      nixos-anywhere limits documented in `docs/procedures/
      vm-testing.md` (hardcoded test-disk size too small for vps's
      fixed 18G `nix` partition, and it rejects `--extra-files`
      outright) — user's call was to proceed to the real install given
      this exact disko layout's track record plus a clean local build
      and `system.build.vm` boot, rather than build a bespoke rehearsal
      harness. Droplet recreated 2026-08-25 (user, DO dashboard — no
      `doctl`/API token in this repo to automate it) — a reserved
      IPv4+IPv6 pair carried over unchanged, so the octodns.nix/
      homelab-wireguard IP references needed no update after all. New
      tailscale key set. First two real `nixos-anywhere` attempts hit
      script bugs (a stray `--` separator token passed straight through
      to `nixos-anywhere`, since fixed) and then `kexec` getting
      OOM-killed on the stock 1GB droplet — twice, once with no swap
      and again with a 1G swapfile added, the second time almost
      instantly (`anon-rss:0kB`), consistent with `kexec_load` needing
      genuinely free kernel-pinned physical RAM that swap can't supply.
      Dropped the swap workaround from the script; the real fix (user's
      call) is a temporary RAM-tier resize before installing, resized
      back down after — documented in `hosts/vps/README.md` and
      `docs/procedures/new-host.md` as a real, recurring step for this
      host, not a one-off. Left before calling this done: user resizes
      the droplet up, retry the install, confirm crowdsec/bouncer/
      tailscaled-autoconnect/caddy/fail2ban are healthy, resize back
      down, and exercise a real reboot to confirm the boot-race fixes
      actually hold against DigitalOcean's real network-arming delay.

      **Landed 2026-08-26:** droplet DO-dashboard-Reset once more, and
      `nixos-anywhere` completed cleanly again — but the box still
      never came up on the network. Root-caused via a rescue-ISO
      journal read to a second, unrelated bug: DigitalOcean's public
      NIC needs the static IP cloud-init reads from its ConfigDrive
      datasource, but NixOS's default scripted `dhcpcd` (from
      `networking.useDHCP = true`) ran its own blind DHCP instead, got
      no lease, and fell back to a self-assigned link-local address —
      cloud-init's own rendered systemd-networkd config was never
      consumed because `services.cloud-init.network.enable` was never
      set. Fixed: `networking.useNetworkd = true` +
      `networking.useDHCP = false` +
      `services.cloud-init.network.enable = true`; confirmed live via
      `networkctl status ens3` showing
      `/etc/systemd/network/10-cloud-init-ens3.network` bound and the
      real public IP routable. Also found and fixed in the same pass:
      cloud-init's own package ships a `05_logging.cfg` default
      (console at WARNING, full DEBUG to the log file) that NixOS's
      cloud-init module doesn't install, so every DEBUG line — hundreds
      per boot — was hitting `StandardOutput=journal+console` on all
      four cloud-init units and flooding the DO recovery console;
      installed the upstream default declaratively. Also confirmed:
      `nixos-anywhere` cannot target DigitalOcean's recovery/rescue
      ISO itself (tested, documented in `hosts/vps/README.md`) — it
      needs the droplet booted to a normal OS. Resized back down to
      `DO-Regular`/1GB, exercised a real reboot: zero failed units, all
      core services active, tailscale reconnected as the same device —
      the boot-race fixes from PR #12 (see the fail2ban entry below)
      confirmed holding on this fresh install too. PR #13 merged.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
