---
slug: add-noexec-to-the-homelab-nfs-share-mounts
created: 2026-09-03
status: done
frozen: true
---

# Add noexec to the homelab NFS share mounts

## Original plan

- [ ] **2026-09-03: add `noexec` to `modules/nixos/nfs-homelab-mounts.nix`'s
      shared `mountOpts`, closing D12 from the 2026-08-26 audit
      (`docs/audits/2026-08-26/user-actions.md`).** Origin: `F-P6-05`.
      Wave 2 item 2.5 already added `nosuid` and `nodev` to both
      `/home/lilijoy/storage` and `/home/lilijoy/storage-bulk` (NFS
      `sec=sys`, so the client trusts homelab's word on every uid/gid/mode
      — those two stop a compromised or malicious *server* from planting
      a setuid-root binary or device node that becomes a privilege path
      on the laptops). `noexec` was declined at the time on the reasoning
      that a media/file share would eventually have something legitimate
      run off it, and a scan found nothing that was actually a program on
      either share.

      Recorded as `accepted-risks.md` AR-6 with `D12` as its own revisit
      trigger: "if the answer is 'nothing will ever be run from those
      shares', noexec is one word and closes the last execution path from
      a homelab-controlled filesystem onto both laptops."

## State

Done. `noexec` added to `modules/nixos/nfs-homelab-mounts.nix`'s shared
`mountOpts`, build-verified clean on `thinkpad` and `torrent`
(`nixos-rebuild build`, exit 0 each, `nix flake check` all 5
configurations pass). Security subagent pass ran clean (1 INFO finding,
a doc-sync gap — fixed: `accepted-risks.md` AR-6 marked superseded and
its D12 row updated, `user-actions.md`'s D12 checkbox closed). Not
deployed/switched anywhere, per standing policy.

## Progress

- [x] D1 answered
- [x] noexec added and build-verified
- [x] security subagent pass — clean, F1 fixed


## Decisions (D)

### D1 — should the NFS shares be noexec too?
Closes the last execution path from a homelab-controlled filesystem onto
both laptops.


**ANSWERED 2026-09-03:** user directly: yes, noexec — closes the last execution path from a homelab-controlled filesystem onto both laptops

## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 — `accepted-risks.md` AR-6/D12 and `user-actions.md`'s D12 checkbox are now stale

- **File:** `docs/accepted-risks.md:140-156,284`, `docs/audits/2026-08-26/user-actions.md:510-518`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** not an external adversary — the next engineer or auditor
  (human or agent) who treats `accepted-risks.md`/`user-actions.md` as
  ground truth for "what's currently accepted" vs. "what's still open."
  AR-6 still reads "`noexec` was considered and declined" and lists that
  as the currently-accepted risk; the D12 row in `accepted-risks.md`'s
  table (line 284, "That the NFS shares stay executable — see AR-6") and
  the D12 checkbox in `user-actions.md` (line 510, still `- [ ]`, "should
  the NFS shares be `noexec` too?") both still describe the shares as
  executable and the decision as open. Both are wrong once this diff
  deploys: the module now sets `noexec` on both mounts on both hosts
  (confirmed via `nix eval
  .#nixosConfigurations.{thinkpad,torrent}.config.fileSystems."/home/lilijoy/storage{,-bulk}".options`
  against the pinned flake — `noexec` is present in the merged option
  list for all four mount/host combinations), and this plan's own D1 is
  marked answered. The same uncommitted diff correctly closes out
  sibling decisions D1/D3/D7/D8 in both of those files with the repo's
  established `~~D#~~ **Answered...**` convention — D12 alone was
  missed.
- **Rule:** n/a — matches the INFO example in
  `docs/agents/security/reference.md` ("documentation that no longer
  matches the config"), not a `docs/hardening.md` rule.
- **Finding:** After this diff deploys, `/home/lilijoy/storage{,-bulk}`
  are `noexec` on both laptops, but `accepted-risks.md` still lists "the
  NFS shares are `nosuid`,`nodev` but not `noexec`" as a live accepted
  risk (AR-6), and the fleet's central open-decisions table still lists
  D12 as unresolved. Left uncorrected, a future pass (including a future
  `security` subagent run) that greps these two files for open items
  will re-surface a question the user already answered, or could report
  `F-P6-05` (rated MEDIUM in `remediation.md`) as still outstanding when
  it is fixed.
- **Fix risk:** None — doc-only. AR-6 needs to either be removed (the
  risk it accepted no longer exists) or rewritten to a closed-decision
  note matching the D7/D8/D9/D10 pattern already used nearby in the same
  file, and the D12 rows in both tables need the same `~~D12~~
  **Answered...**` treatment the diff already gave D1/D3/D7/D8.


**FIXED 2026-09-03:** AR-6 marked superseded, D12 rows in accepted-risks.md and user-actions.md updated to the ~~D#~~ Answered convention matching sibling decisions

## Checked and clean

Reviewed `modules/nixos/nfs-homelab-mounts.nix` in full (not just the
diff hunk) for both the `noexec` addition and the comment-to-plan-file
rewrite. Confirmed via `nix eval` against the pinned flake (not by
reading the file) that `noexec` actually lands in the merged
`fileSystems."/home/lilijoy/storage"`/`"-bulk"`.options` for both
`thinkpad` and `torrent` — hardening.md rule 9 ("verify that config
actually takes effect"), satisfied. Checked for other client-side
mounts of homelab's exports that `noexec` wouldn't cover: Samba
(`modules/services/samba.nix`) is server-side only, no `cifs` client
mount is declared anywhere in the repo, and no other host imports
`nfs-homelab-mounts`, so the two NFS mounts on `thinkpad`/`torrent` are
the only ones affected and the only ones that needed to be. Checked
`modules/profiles/PC.nix`, `hosts/torrent/configuration.nix`,
`hosts/thinkpad/configuration.nix`, `modules/services/jellyfin.nix`, and
`modules/services/nfs.nix` for any Nix-declared execution path off
`/storage`/`/storage-bulk` this change would break — found none;
`qbittorrent` is only an installed package in `PC.nix`, with no
Nix-declared post-download hook pointed at either share, though a
GUI-configured qBittorrent completion script pointed into
`storage-bulk` (invisible to this diff, not Nix-managed) is a plausible,
unverifiable-from-here availability caveat rather than a security
regression — not written up as a finding since it's the expected,
already-user-accepted effect of D12/AR-6, not something this diff
changed. Confirmed the `"noexec" # plan: ...md#D1` citation format
matches existing repo convention exactly (bare filename + `#D<n>`
anchor, no directory — e.g. `modules/profiles/default.nix:269`,
`hosts/torrent/configuration.nix:76`), consistent with
`docs/style-guide.md`'s "citation, not rationale" rule, and that the
same bare-filename pattern already survives plan files moving from
`in-progress/` to `done/` elsewhere in the repo, so it isn't a new
fragility this diff introduces. Did not touch, decrypt, or reference any
`secrets/*` file — nothing in this diff does. Confirmed this plan file's
own frontmatter (`frozen: false`, `status: in-progress`) before writing
to it. The working tree also carries other, unrelated uncommitted
changes (D1/D3/D7/D8 closure edits, a new AR-8 accepting unauthenticated
recovery-ISO filesystem access, a new `docs/plans/todo` IDS design plan)
that are not part of this `noexec` change; per scope these were not
audited here and no findings about them were written to this file.

_security finished 2026-09-03T21:33:44Z -- see Findings above._
