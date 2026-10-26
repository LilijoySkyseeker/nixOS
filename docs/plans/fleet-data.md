# Fleet data: where it lives and how it's protected

## Goal

In the owner's words (2026-10-25, after torrent's pool filled):

- "Really taking rule 0 to figure out the purpose of snapshots and backups
  and to see if the current setup is doing its job in that, and rework it
  if necessary to do its job."
- "Extend this idea across the whole fleet. Right now thinkpad and torrent
  are second-class citizens, and I want to make them first class with how
  data is being dealt with."
- "Let's not look at how things are, let's just look at how they should
  be, then we can plan how we need to change things to achieve that goal."
- "Treat the whole concept of storage and space as a shared pool across the
  fleet: stuff should be where it is needed, and things are weighted by
  whether they're needed quickly or not, and on what space is available in
  general across the fleet."
- "This is all a holistic understanding of the problem."

### The spec

Never lose what can't be replaced, never let protecting it get in the way,
and keep everything where it's needed.

1. What rebuilds itself isn't protected. What can be replaced is protected
   at home. Everything else is protected everywhere. If in doubt, it can't be
   replaced.
2. What can't be replaced survives a mistake noticed within a month, the
   loss of any machine, and the loss of the whole house or anything with
   root on it. Each loss costs as little recent work as possible.
3. Protecting data never gets in the way of using a machine.
4. The fleet is one pool: data lives where it's needed, space is used where
   it's free, and every machine is treated the same.
5. Getting data back is easy, and the owner hears when any of this stops
   being true.

### Classifying data

- **Disposable, by rule:** what machines generate and rebuild on their own:
  caches, search indexes, shader caches, thumbnails, build output, scratch.
- **Replaceable:** what can be got again at a cost in time or effort. By
  rule for installed software and games; otherwise the owner's review.
- **Irreplaceable:** documents, projects, notes, pictures, app settings,
  game saves wherever they are, message and mail stores, the agents' work,
  and anything not yet reviewed. Acquired media changes or disappears at
  the source without notice and is often hard or impossible to get again
  legally, so a download being available today doesn't make it
  replaceable.

Two questions guide the owner's review: would it still exist somewhere if
the fleet vanished, and does something on this machine need it fast or
offline?

## Your decisions

- 2026-10-25: the four threats above, and replaceable vs irreplaceable as
  a yes/no axis. homelab's `storage` vs `storage-bulk` was this
  distinction.
- 2026-10-25: history beyond about a month isn't needed; the furthest
  restore ever done was about a week back.
- 2026-10-25: the owner and the agents restore from the last hour, mostly
  the last 15 minutes, fairly often.
- 2026-10-25: extra snapshots are fine as long as they don't kill the PC;
  local snapshots are mostly a detriment if homelab's copies are easy to
  reach with tooling for both the owner and the agents.
- 2026-10-25: keep and expand the idea of storage tiers, and split data
  into more datasets as needed.
- 2026-10-25: the agents get their own dataset.
- 2026-10-26: two kinds of data, replaceable and irreplaceable ("simpler
  and takes a lot of deciding out of things"), after briefly trying three.
- 2026-10-26: the away-from-home wording in item 5.
- 2026-10-26: recent work: as frequent as possible to minimise loss, while
  planning around real limits such as offsite runs taking hours. The worry
  is small, recent things like a new secret added to a repo.
- 2026-10-26: T4 includes something with root deleting data across
  machines.
- 2026-10-26: daily steps are enough in T2's month.
- 2026-10-26: agents may keep data elsewhere in the pool only where it's
  practical and makes sense, erring on no until something actually needs
  it.
- 2026-10-26: vps is fully rebuildable from config, apart from secrets
  provisioned at install, which shouldn't be saved anyway.
- 2026-10-25: keep a restore helper.
- 2026-10-25: the disaster path is built out through the USB toolbox.
- 2026-10-26: keep the spec at the simplified five-line version for now.
- 2026-10-26: acquired media like music isn't safely replaceable: it
  changes at the source without notice and is often hard or impossible to
  get again legally. Much of this project is the owner's own review of
  their files (what to keep, what's needed locally); a few categories can
  be decided by rule.
- 2026-10-26: music is irreplaceable; it has been moved and consolidated
  on homelab's `storage`, so it goes offsite.
- 2026-10-26: thinkpad is lent out and holds almost nothing valuable.
- 2026-10-26: VMs come in two kinds: agents' scratch VMs, and the owner's
  persistent ones for Windows and other distros (compatibility, testing).
- 2026-10-26: three classes after all, defined by what each pays for:
  disposable (nothing), replaceable (snapshots and a copy on homelab, no
  offsite) and irreplaceable (everything, including offsite). Replaceable
  can be a pain to get back, so it keeps snapshots; it gets a copy on
  homelab.
- 2026-10-26: long history proved useful: a session is mining months-old
  snapshots on homelab for Claude transcripts that Claude Code had pruned.
  Open: how long history is kept, by class (ADR decision 7).
- 2026-10-26: decision 7: irreplaceable keeps a year of monthly snapshots
  on homelab; replaceable a month; offsite a month. The owner had already
  raised Claude Code's transcript retention; the pruned transcripts date from
  before that.
- 2026-10-26: decision 2: `storage-bulk` is replaceable. Decision 3: the
  owner's persistent VMs are replaceable (the agents' scratch VMs are
  disposable). Decision 6: the agents get 400 GB of live data.
- 2026-10-26: decision 1: homelab is treated no differently from any other
  machine. The owner wants a separate backup machine later but can't afford
  one now, so homelab's copy stays on its own `zbackup` drives for now.
- 2026-10-26: decision 4: the way back in is kept in the password manager
  plus two YubiKeys. Decision 5: vps and homelab watch each other.
- 2026-10-26: the agents get space on homelab's NAS: their bulk data
  (starting with the USB stick mirror) isn't needed fast locally, which is
  the "something actually needs it" case.
- 2026-10-26: the agents' share on homelab: 1 TB, `replaceable`, mounted at
  `~/work/nas` (the owner's `~/Agent/nas`). The agents' local limit stays
  at 400 GB of live data.

## State

Spec agreed and design accepted (`docs/adr/0002-fleet-data-classes.md`,
2026-10-26), revised after Codex's review. All three unknowns proved in VM
tests; the proof tests wait in the agents' worktree `nixOS-backup-rework`
(`tests/proofs/`) and join the step that uses each: restore-export in
step 2, zrepl-classes in step 3, offsite-lock in step 4. Decision 9 (offsite
lock mode) is open.

Step 1 (relief and alerts) is on branch `feat/backup-relief`, as a draft
PR until the owner's transcript-mining session on homelab is done and the
leftover clones under `zbackup/restore-drill-249027` are destroyed. Nothing
changed on any host yet.

Facts (2026-10-26): torrent's pool is 3.6 TB; homelab's `zbackup` is 78%
full (8.61 of 10.9 TB), 4.94 TB of it torrent's (2.67 TB history), and
homelab's copy of `storage-bulk` is 2.28 TB, 1.84 TB of it history, against
451 GB live; `zdata` holds 1.66 TB with 9.1 TB free; homelab's `zroot` has
138 GB free.

## Next

1. Step 1 merges once the transcript mining is done and the clones are
   destroyed; the owner confirms on homelab after its Tuesday deploy that
   `zbackup` pruned to about a month.
2. Steps 2–5 in the ADR's order, one PR at a time.
3. The owner's review of their files, at their own pace; inventory in the
   agents' `projects/fleet-data/`.
