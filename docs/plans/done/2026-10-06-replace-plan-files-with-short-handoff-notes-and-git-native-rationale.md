---
slug: replace-plan-files-with-short-handoff-notes-and-git-native-rationale
created: 2026-10-06
status: done
frozen: true
kind: task
priority: normal
blocked_by:
---

# Replace plan files with short handoff notes and git-native rationale

## State

Verified to rung 3 (ran it locally, output inspected).

`verify-ladder` passes: the trimmed `gate-tests` (12 passed; a
deliberate fail-open mutation in `lib.sh` was caught), `nix flake check
--no-build`, and builds of all five hosts. statix/deadnix were not on
PATH; the only .nix change is a comment. `security` review: 0 above
INFO. `docs-updater` pass applied. `/simplify` skipped: the change is
almost entirely deletion. Rung 4 not applicable: nothing here changes a
host.

The plan scripts are deleted in this same PR, after this file closes.

## Original plan

The user asked for a first-principles review of the plan-file system
against its three original goals: keep agent reasoning out of comments,
hand work off between sessions, and keep agents on the user's goal by
recording their decisions. Goals 2 and 3 held; goal 1 did not (the
comment share of added Nix lines rose from 33% to 38% after plans
arrived, and code gained 258 plan citations on top of the reasoning).

This is the last plan written in this format; the PR that closes it
removes the system.

## Progress

- [x] D1 -- notes replace plan files
- [x] D2 -- remove plan-gate
- [x] D3 -- no global comment-density rule

## Decisions (D)

### D1 -- replace plan files with a short per-task note; rationale goes to commits and PRs

Goal / Your decisions / State / Next, only for multi-session work;
reasoning in commit messages and PR descriptions; plan scripts and gates
deleted; existing plans kept as a read-only archive.


**ANSWERED 2026-10-06:** user agreed to items 1-4 of the proposal

### D2 -- remove plan-gate

Its only input is plan-file security findings, so it falls with them.


**ANSWERED 2026-10-06:** user: you may remove plan-gate

### D3 -- no global CLAUDE.md rule against copying verbose comments

The comment-density default is Claude Code's, not the user's file, and
the repo style guide already governs comments here.


**ANSWERED 2026-10-06:** user asked to apply the two rules to it; result was to drop it

## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
