---
slug: investigate-minecraft-server-oom-crash-warning-on-homelab
created: 2026-09-03
status: todo
frozen: false
---

# Investigate Minecraft server OOM-crash warning on homelab

## Original plan

During a 2026-09-03 homelab CPU/log sweep, found recurring warnings in
`docker-minecraft-vanilla-plus-start` and the container's own logs on
2026-08-27 and 2026-08-28:

```
This can cause out of memory crashes.
```

Not investigated further at the time (CPU/fans were the priority and
nothing was actively wrong). Come back and:

- find the full log line/context this warning comes from (JVM flag
  advisory? container memory limit vs `-Xmx`? itzg/minecraft-server
  startup script check?)
- check current `docker-minecraft-vanilla-plus` memory limit vs the
  server's configured heap (`fabric-server-mc.26.2-loader.0.19.3` was
  running with `-Xmx4G -Xms4G` per `hosts/homelab/configuration.nix` /
  `modules/services/minecraft.nix`)
- decide whether it's a real risk (container OOM-killed under load) or
  just a noisy startup-script advisory, and fix or dismiss accordingly

## State

Not started. Logged as a backlog item from an unrelated CPU/log sweep;
no diagnosis done yet.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
