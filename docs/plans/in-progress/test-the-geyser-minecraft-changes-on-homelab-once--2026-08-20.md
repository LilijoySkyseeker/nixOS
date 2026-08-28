---
slug: test-the-geyser-minecraft-changes-on-homelab-once-
created: 2026-08-20
status: in-progress
frozen: false
---

# test the Geyser/Minecraft changes on homelab once deployed

## Original plan

- [ ] **2026-08-20: test the Geyser/Minecraft changes on homelab once
      deployed.** `services/minecraft.nix` (merged to master at
      `3270eae`, **not yet deployed**) now sets Geyser's
      `above-bedrock-nether-building: true` (fixes Bedrock players
      softlocking above the Nether roof — confirm with a live Bedrock
      client), `ENABLE_AUTOPAUSE`/`MAX_TICK_TIME=-1`/`--cap-add=NET_RAW`
      (confirm the container actually pauses when empty and resumes
      cleanly on the next connection, and that the watchdog doesn't
      fire on resume), and `VERSION = "LATEST"` instead of a pinned
      `26.2` (confirm the modded stack — Geyser, Floodgate,
      DistantHorizons, etc. — still starts cleanly on whatever version
      resolves, since none of `MODRINTH_PROJECTS` pins a mod version).
      None of this has been tested against the running container yet.

      **Confirmed deployed 2026-08-25** via live inspection: the
      container (now named `minecraft-vanilla-plus`, up 21h, `healthy`)
      has `ENABLE_AUTOPAUSE=TRUE`, `MAX_TICK_TIME=-1`, `VERSION=LATEST`,
      and `CAP_NET_RAW` all present — the config-level rollout is done.
      Still unverified: the actual Bedrock-client/nether-roof behavior.

      **2026-08-26: autopause confirmed broken**, surfaced for free by a
      full homelab reboot (done to verify the tailscale0-only firewall
      re-scoping survives a real boot, see the security-audit items
      above). Container logs on fresh start:
      `could not open eth0: ... Operation not permitted`,
      `[Autopause loop] Failed to start knockd daemon`. Docker itself
      does grant the capability (`docker inspect
      minecraft-vanilla-plus --format '{{.HostConfig.CapAdd}}'` →
      `[CAP_NET_RAW CAP_SETGID CAP_SETUID]`), but it doesn't survive the
      entrypoint's privilege drop from root to the unprivileged
      `minecraft` user — plain `setuid` clears effective capabilities
      unless something explicitly keeps them (ambient caps / `prctl
      PR_SET_KEEPCAPS` / file capabilities), none of which this image's
      entrypoint appears to do for knockd. So autopause has likely never
      actually worked since it was deployed 2026-08-20 — the container's
      been running continuously since then, so this is the first fresh
      start to reveal it. Needs a real fix, not just more testing: either
      get `CAP_NET_RAW` into knockd's effective set post-setuid (image-side
      fix, not something this repo controls) or use the workaround the
      log itself suggests — `AUTOPAUSE_KNOCK_INTERFACE` env var — if that
      routes around the packet-capture path entirely rather than hitting
      the same capability wall.

      **2026-08-26: root-caused and fixed in code (not yet deployed).**
      The image *does* have a post-setuid mechanism for this — itzg's
      Dockerfile runs `setcap cap_net_raw=ep /usr/local/sbin/knockd` at
      build time (added in itzg/docker-minecraft-server#2625, closing
      #2421, specifically so knockd regains `NET_RAW` after gosu's setuid
      drop to the unprivileged `minecraft` user without needing `sudo`).
      File capabilities granted on `execve()` are exactly what Docker's
      `--security-opt=no-new-privileges:true` disables by design (that's
      the flag's entire purpose) — `modules/services/minecraft.nix` had
      that flag set, so it was silently blocking the very mechanism the
      image relies on. `AUTOPAUSE_KNOCK_INTERFACE` (interface-name
      selection, default `eth0`) was a dead end, unrelated to this
      permission failure. `--security-opt=no-new-privileges:true` removed
      from `minecraft-vanilla-plus`'s `extraOptions`
      (`modules/services/minecraft.nix`); `factorio.nix` keeps it
      unchanged since factorio has no autopause/knockd. Accepted
      trade-off documented inline: `--cap-drop=ALL` already limits the
      bounding set to `SETUID`/`SETGID`/`NET_RAW`, so removing
      no-new-privileges only lets those three already-granted
      capabilities be exercised via setuid/file-cap binaries inside the
      container — nothing beyond what `--cap-add` already grants.
      `nixos-rebuild build --flake .#homelab` confirmed clean, and the
      built unit's `ExecStart` was inspected directly in the nix store to
      confirm `--security-opt=no-new-privileges` is gone while
      `--cap-drop=ALL`/`--cap-add=SETUID`/`--cap-add=SETGID`/
      `--cap-add=NET_RAW` are unchanged. **Not yet deployed** — needs
      `nixos-rebuild switch` on homelab (will restart the container,
      disrupting any players currently online) and then a real fresh
      container start to confirm knockd actually launches this time and
      autopause survives a full pause/knock/resume cycle without the
      watchdog firing.

      **2026-08-26: deployed, tested live, then autopause deliberately
      disabled again — resolved, differently than planned.** Deployed
      the no-new-privileges fix to homelab
      (`nixos-rebuild switch --flake .#homelab --target-host root@homelab`,
      PR #20 branch `worktree-minecraft-autopause-fix`) and confirmed the
      fix itself worked: fresh container starts showed knockd launching
      cleanly (no more `Operation not permitted`), the JVM paused via
      SIGSTOP repeatedly with no errors, and a real player join
      (LilijoySkyseeker, over Tailscale) triggered a clean knock-triggered
      resume with no watchdog kill — the root-caused bug is genuinely
      fixed. But live testing surfaced a bigger problem with keeping
      autopause on at all: this port is public (DNAT'd through vps for
      friends without Tailscale), and it gets knocked by internet
      background scanners every ~2-3 minutes regardless of real players
      — confirmed via `conntrack -L` on vps mid-cycle, both source IPs
      were Oracle Public Cloud, not the user. Under knockd's default 120s
      `AUTOPAUSE_TIMEOUT_KN` re-pause window, that noise alone kept the
      JVM resumed roughly 65-75% of "idle" time. Since pausing only ever
      saves CPU (a SIGSTOP'd JVM keeps its full heap resident — homelab
      has just 3.4GB RAM available with `MEMORY=4G` already pinned by
      this container alone, unaffected either way), most of autopause's
      actual benefit was already gone under real conditions. Considered
      shrinking `AUTOPAUSE_TIMEOUT_KN` to ~20-30s to reclaim most of that
      CPU-saving benefit cheaply, but the user chose the simpler option:
      **disable autopause entirely.** `modules/services/minecraft.nix`
      now drops `ENABLE_AUTOPAUSE`/`MAX_TICK_TIME`/`AUTOPAUSE_TIMEOUT_*`/
      `AUTOPAUSE_PERIOD` (letting the image's own tick watchdog apply
      again, no longer needing to be disabled) and `--cap-add=NET_RAW`,
      restoring `--security-opt=no-new-privileges:true` — now safe to
      restore since knockd's file-capability escalation is no longer
      exercised, leaving this container's bounding capability set
      *tighter* than before this whole investigation started
      (`SETUID`/`SETGID` only, vs. the original `SETUID`/`SETGID`/
      `NET_RAW`). Redeployed and confirmed live: `docker inspect` shows
      `CapAdd=[SETGID SETUID]`/`SecurityOpt=[no-new-privileges:true]`,
      container reaches `healthy`, clean startup logs with zero
      autopause/knockd references. `VERSION = "LATEST"` was also
      incidentally re-confirmed multiple times during this session's
      repeated fresh-container-start testing — Geyser/Floodgate/
      DistantHorizons/C2ME all load cleanly every time. **Still
      unconfirmed**: the Bedrock-client/nether-roof behavior — every
      live test this session connected over Java Edition, not Bedrock/
      Geyser, so `above-bedrock-nether-building: true` remains untested
      against a real Bedrock client.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
