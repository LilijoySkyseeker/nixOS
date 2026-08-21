# Backup restore

Placeholder — restore procedures aren't written yet. See
`docs/architecture.md`'s "Backups (homelab)" section for what's
currently documented about the backup mechanisms themselves (restic
-> Backblaze, sanoid/syncoid -> `zbackup`). Restore steps for each path
need to be architected once the in-flight `zbackup` restructuring
(see `TODO.md`) lands, so they document the actual dataset layout
rather than one about to change.
