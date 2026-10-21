# Backups for thinkpad's Windows

## Goal

Have backups in place before Windows holds anything worth keeping: "it
might be a good idea to have the backup tooling in place before I actually
need to start putting any important data in there."

## Your decisions

- 2026-10-21: plan only for now. Build it when CAD work is about to start
  (a couple of days' notice is enough).
- 2026-10-21: Windows is for compatibility tools now, Fusion 360 later.
  Recover the data, not the Windows install.
- 2026-10-21: Fusion's cloud isn't trusted to keep designs; an add-in will
  export them locally.

## State

Not started. Risk analysis (2026-10-21): the likely losses are your own
mistakes (deleted or overwritten files, a crash saving a broken file),
then a dead or stolen SSD, then hostile code on Windows encrypting or
deleting files, including any backup it can write. A full-image restore
would bring hostile code back, so: no scheduled images; recovery is a
clean reinstall from the TOOLBOX stick plus the files. Optional: one
manual known-good image once the CAD setup is done.

Planned parts:
- Fusion add-in exporting `.f3d` (keeps the timeline) and STEP (any CAD
  tool) to one folder. Both formats export on the Personal Use licence.
  Candidates: Project-Archiver, Fusion360Exporter, SmartExport,
  Fusion360_ExportIt. They run inside Fusion, so "automatic" means on
  start, on save, or an "export all".
- restic + a scheduled task on Windows (`files/windows/`), hourly while
  booted, catching up when back on the network: the export folder and
  Documents. Repo password in Bitwarden.
- homelab: a dataset on zbackup, shared over the existing tailnet-only
  Samba to a dedicated account that can write only that share (password
  in sops, added by the owner); long-kept ZFS snapshots of it that Windows
  can't touch. Optional: Samba `shadow_copy2`, so they show in Explorer's
  Previous Versions.
- Tailscale ACL: the Windows node reaches only `homelab:445` (a Windows
  machine on the tailnet would otherwise reach nearly everything, D6).

## Next

When CAD is near: pick the Fusion add-in; build the homelab side and the
restic task in one PR (`/security-review` and Codex: Samba, a secret, the
ACL); test a file restore and a restore after a simulated wipe.
