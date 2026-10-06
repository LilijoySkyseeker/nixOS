---
slug: package-openrig-and-add-it-to-the-pc-profile
created: 2026-10-05
status: rejected
frozen: true
kind: task
priority: normal
blocked_by:
---

# Package OpenRig and add it to the PC profile

## State

Rejected 2026-10-05, nothing deployed. The package, module, PC.nix import
and docs pass (F8) were built and reviewed on branch `openrig-package`
but never merged; only this plan landed. File paths and line numbers
cited below (`pkgs/openrig/...`, `modules/nixos/openrig.nix`, the
architecture/README edits) refer to that unmerged branch and do not
exist on master.

Why dropped: G5. Claude Code already covers most of OpenRig's useful
core natively, OpenRig's design conflicts with this fleet's threat model
(F1, and G5's note on paste-as-user input), and the remaining gap is
better closed by the planned agent-sandbox work than by adopting or
cloning a ~119k-line single-maintainer daemon.

A malicious-code audit of the deployed build found nothing malicious
(see F7's note). F1, F3, F6 and F7 were left open per D4, not accepted;
with OpenRig dropped they are not live risks on any host, but they are
input for the sandbox design. All OpenRig state was removed from torrent
(`~/.openrig`, `~/.agents`, `~/.codex`, the seeded skill, the trial npm
prefix, workspace trust entries in `~/.claude.json`).

## Original plan

User wants to try OpenRig (github.com/mvschwarz/openrig, npm
`@openrig/cli`), first to learn it in a scratch repo, then to use it on
this dotfiles repo. A first trial ran from a throwaway npm prefix inside
`nix shell nixpkgs#nodejs_22`; its agents could not find `node` or `rig`
(G1). User chose a declarative install at the PC-profile level, so both
torrent and thinkpad get it.

Scope: package `@openrig/cli` 0.6.5, put it and Node 22 in
`profile-pc`'s system packages, keep the daemon off the tailnet (G2).
Out of scope: anything OpenRig writes at runtime (`~/.openrig`,
`~/.claude.json` trust, workspace `.claude/settings.local.json`); that
stays imperative, owned by OpenRig.

## Progress

- [x] G1 -- agents could not find `node`/`rig` from a nix-shell install
- [x] D1 -- where the derivation lives
- [x] D2 -- ship the prebuilt dist and skip install scripts
- [x] G2 -- daemon listens on tailscale0 by default
- [x] D3 -- prune better-sqlite3 down to the linux-x64 prebuild
- [x] G3 -- the TUI has its own daemon-start path
- [x] G4 -- regenerating the lockfile (fixes F2)
- [x] F2 -- lockfile pinned to upstream's v0.6.5 lock
- [x] F4 -- only `node` on PATH
- [x] F5 -- empty bind host no longer falls through
- [x] D4 -- unfixed security findings stay open for the sandbox work
- [ ] F1 -- loopback API reachable from flatpak/distrobox (open, D4)
- [ ] F3 -- out-of-nixpkgs binary, no update path (open, D4)
- [ ] F6 -- prepare the dotfiles repo before pointing openrig at it (open, D4)
- [ ] F7 -- seeded skill pre-approves `rig *` user-wide (open, D4)
- [x] build torrent and thinkpad (verify-ladder, on the unmerged branch)
- [x] G5 -- build-our-own research: Claude Code already covers most of it
- [ ] ~~user switches torrent and reruns the guided first run~~ (rejected, G5)

## Decisions (D)

### D1 -- where the derivation lives

First custom package in the repo. import-tree loads every `.nix` under
`modules/` as a flake-parts module, so a plain `callPackage` file cannot
sit there unprefixed. Put it in a top-level `pkgs/openrig/` (with its
`package-lock.json`) and ~~call it from `modules/profiles/PC.nix` with
`pkgs-unstable.callPackage`~~. User asked for the PC profile, not a
torrent-only or home-manager install.

2026-10-05: the package, `nodejs_22` and the bind pin (G2) now live in
`modules/nixos/openrig.nix`, imported by `profile-pc` like `wooting`.
Adding them inline to PC.nix tripped statix's repeated-keys check (a
third `environment.*` there); one module keeps every openrig concern in
one commented place instead of nesting PC.nix's unrelated blocks.


**ANSWERED 2026-10-05:** User chose the PC profile level (torrent + thinkpad), not a torrent-only install

### D2 -- ship the prebuilt dist and skip install scripts

The tarball carries a compiled `dist/`, `daemon/`, `tui/` and `ui/`, and
better-sqlite3 13 bundles a `linux-x64` prebuild that loads under nixpkgs'
Node 22 (checked in the trial). So `dontNpmBuild` plus `--ignore-scripts`:
the only script is a postinstall ABI self-check. Node pinned to 22, the
version upstream tests on and the one the trial used.

### D3 -- prune better-sqlite3 down to the linux-x64 prebuild

From the /simplify efficiency pass. better-sqlite3 13 loads its addon
through per-platform shims (`lib/<platform>.js` requires
`../prebuilds/<platform>.node`), so on x86_64-linux only
`linux-x64.node` is ever read. `postInstall` deletes the other seven
prebuilds and the `deps/`/`src/` source-build inputs that
`--ignore-scripts` already makes unreachable; the package drops from
100M to 85M. `meta.platforms` is pinned to x86_64-linux to match.
Checked after the change: the addon still loads and opens a database.

### D4 -- security findings that are not easy to fix now stay open, not accepted

All agentic work is meant to move into a sandbox (user: on the todo
list, to be built soon). Until then, a finding here that cannot be fixed
easily now is left **open** and marked for that work. It is not recorded
in `docs/accepted-risks.md`. This applies to F1, F3 and F6, and replaces
the F3 acceptance chosen earlier this session, which was never written.


**ANSWERED 2026-10-05:** User: security issues not easily solvable now are marked open for the upcoming agent-sandbox work, not accepted; includes F3, earlier chosen for accepted-risks

2026-10-05 (docs pass, F8): F7, written after this decision, falls under
the same rule and is marked open per D4 in its own entry.

## Gotchas (G)

### G1 -- agents could not find `node`/`rig` from a nix-shell install

The daemon passes its own PATH into each seat's tmux session, but Claude
Code rebuilds its Bash tool's shell from the user's login snapshot, so a
`nix shell` PATH never reaches the agents. Their `rig whoami` and
OpenRig's `activity-relay.cjs` hooks failed with `node: command not
found`. Fix: both on the system PATH. The package's own bins get a
store-path shebang, but the hooks OpenRig writes into
`.claude/settings.local.json` run bare `node`, so `nodejs_22` goes in the
profile too.

### G2 -- daemon listens on tailscale0 by default

Read from the 0.6.5 source (`daemon/dist/index.js`,
`dist/daemon-lifecycle.js`): with no declared bind intent, the daemon
binds 127.0.0.1 and the detected Tailscale address, and needs no bearer
token on either. The HTTP API can launch agents and send them prompts.
torrent's firewall opens only listed ports on `tailscale0`, so 7433 was
most likely blocked during the trial, but that is defence by accident.
`OPENRIG_BIND_HOST` is read by the daemon itself and by every CLI path
that auto-starts it (`up`, `start`, `daemon start`), so
`environment.sessionVariables.OPENRIG_BIND_HOST = "127.0.0.1"` pins it
for every start path, including the TUI's.

~~`environment.sessionVariables.OPENRIG_BIND_HOST = "127.0.0.1"` pins it
for every start path, including the TUI's.~~ 2026-10-05, after the
/simplify review: moved into the package as `makeWrapperArgs =
[ "--set-default" "OPENRIG_BIND_HOST" "127.0.0.1" ]`. Every CLI start
path runs through the `rig` wrapper, and the daemon child inherits its
env (`buildDaemonEnv` copies `process.env`); the TUI path is covered
separately (G3). A session variable only lands after a re-login, so the
first switch would have left open shells unpinned, and it put the
variable into every process on the box.

Verified on a throwaway daemon (temp `HOME`/`OPENRIG_HOME`, port 7499,
`--no-kernel`): through the wrapper it listens on `127.0.0.1:7499` only;
the same dist run directly without the variable listens on
`127.0.0.1:7499` and `100.110.203.119:7499`.

Caveat: `resolveBindIntent` ranks `OPENRIG_BIND_HOST` above a
file-sourced `daemon.host`, so with the wrapper default a later
`rig config set daemon.host <addr>` is silently ignored. Override per
command with `OPENRIG_BIND_HOST=<addr> rig ...` or `--host` instead.
~~`--set-default` keeps an explicit caller value.~~ 2026-10-05 (docs
pass, F8): since F5 the wrapper uses `--run 'export
OPENRIG_BIND_HOST=${OPENRIG_BIND_HOST:-127.0.0.1}'`, which keeps a
non-empty caller value and replaces an empty one.

### G3 -- the TUI has its own daemon-start path

`tui/dist/crash-cart/start-daemon.js` starts the daemon as
`rig daemon start --no-kernel --host <hostname>` and refuses any daemon
URL whose host is not `127.0.0.1`/`localhost`/`[::1]`. So it is already
loopback-only by explicit `--host`, independent of G2's wrapper.

### G4 -- regenerating the lockfile (fixes F2)

`npm install --package-lock-only` on the bare tarball takes the newest
in-range version of everything that day (F2). Instead, pin to upstream's
monorepo lockfile at the release tag:

1. `gh api 'repos/mvschwarz/openrig/contents/package-lock.json?ref=v<ver>'
   -H 'Accept: application/vnd.github.raw' > upstream-lock.json`
2. Unpack the npm tarball, generate a lock as before, then overwrite every
   entry whose bare package name exists in upstream's lock with
   upstream's whole entry (version, resolved, integrity *and*
   dependencies -- copying only the version leaves stale dependency
   ranges that drag transitive packages forward), keeping the local
   `dev` flag.
3. Re-run `npm install --package-lock-only --ignore-scripts
   --before=<release publish time>` so npm fixes up the tree without
   reaching past the release.
4. Diff every non-dev entry against upstream (version and integrity);
   hand-pin any stragglers from upstream's nested entries.

For 0.6.5 (published 2026-10-04T10:36:55Z): all 110 runtime packages
match a version and integrity upstream's lock carries;
`@modelcontextprotocol/sdk` 1.28.0, `hono` 4.12.8, `ws` 8.20.0,
`ip-address` 10.1.0, `iconv-lite` 0.7.2 (from upstream's nested
`body-parser` entry). Dev-only entries (vitest's esbuild/rollup) still
differ; they are pruned from `$out` and never run.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### G5 -- build-our-own research: Claude Code already covers most of it

Research pass 2026-10-05 (read-only; Claude Code docs checked that day,
OpenRig 0.6.5 sized from its compiled JS):

- OpenRig's daemon is ~119k lines (89k domain, 67 route files, 93 SQLite
  migrations), CLI 38k, TUI 11k, plus a 929 KB web bundle. For one user
  running a few agents on their own repos, the useful 20% is: a
  declarative team spec, persistent attachable seats, messaging, a small
  owned-work queue, compaction/handover recovery and a status view.
- Claude Code 2.1.x already has most of that natively: background
  sessions and agent view (`claude agents`), cross-session messaging
  over a per-user unix socket (messages labelled as from another
  session, cannot approve prompts), worktrees (`claude -w`), compaction
  and lifecycle hooks, `claude -p` / the Agent SDK, and a bubblewrap
  sandbox (shell commands only). Agent teams exist but are experimental.
  Not native: a durable work queue, a spec that launches N persistent
  seats, and an outer sandbox around the whole `claude` process.
- Minimal secure in-house shape: a repo team file; a Nix-packaged
  launcher that creates a worktree per seat and starts each in an outer
  sandbox (`sandbox-runtime` is in nixpkgs, or `systemd-run --user`);
  queue as files or SQLite in the repo; native messaging only; no daemon,
  no TCP listener, no `~/.claude.json` trust edits, no third-party MCP.
  Estimate 3-6 days minimal, 15-25 days for OpenRig's useful core. Main
  unknown: Claude's own bwrap nested inside an outer sandbox.
- Design not to copy: OpenRig's compaction enforcer tells agents to
  treat a later "normal user message" as operator-authorized, while its
  tmux transport pastes other agents' text in as if typed by the human.
  Its SECURITY.md treats same-account attackers as low severity, the
  opposite of this fleet's threat model.
- Licence: Apache-2.0, no NOTICE file. Ideas and spec formats are free
  to reuse; copied code or skill text keeps the licence and attribution
  in its own file (this repo is Unlicense).
- Existing alternatives seen: Claude Squad (tmux + worktrees, no
  listener), container-use (container per agent, experimental),
  workmux, CCManager, Agent of Empires, Vibe Kanban (HTTP on loopback).

### F1 -- the daemon's loopback API has no auth for any process in the host netns, Flatpak apps included

- **File:** `pkgs/openrig/package.nix:41-47`; `modules/nixos/openrig.nix:12-15`; `modules/profiles/PC.nix:22`; upstream `daemon/dist/middleware/browser-boundary.js`, `daemon/dist/middleware/auth-bearer-token.js:71-78`, `daemon/dist/routes/transport.js`, `daemon/dist/adapters/yolo-mode.js`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (no-auth and reachability read from the 0.6.5 dist, Flatpak permissions read live on torrent). The full escape was not run end to end.
- **Axis:** hardening
- **Reachability:** a compromised Flatpak app (a narrower foothold than A7) -> `127.0.0.1:7433`. `app.grayjay.Grayjay` and `info.beyondallreason.bar`, both declared in `PC.nix`, have `shared=network` (`flatpak info --show-permissions` on torrent), so they share the host network namespace and reach loopback. The same goes for any distrobox container (`--network host`).
- **Rule:** new-rule candidate. Loopback is not an auth boundary when same-uid sandboxes share the netns.
- **Finding:** G2 closes the tailnet, but the loopback listener is still unauthenticated for every non-browser client. When the daemon is bound to a loopback or tailnet host, no bearer token exists (`terminalBearerToken` stays null, `index.js` startServer), and `authBearerTokenMiddleware` passes everything when `expectedToken === null`. `browserBoundary` accepts any IP-literal `Host` and only refuses requests that carry an `Origin` header, so a plain HTTP client gets the whole `/api/*` surface. That surface includes `POST /api/transport/send`, which types arbitrary text into a live seat's pane, plus rig launch/up/import. Seats launch Claude with `--permission-mode acceptEdits` by default, and a per-seat `full_bypass` posture (`--dangerously-skip-permissions`, Codex `-s danger-full-access -a never`) can be selected. So "can reach loopback" becomes "can drive a coding agent running as unsandboxed `lilijoy`". That is an escape from the Flatpak sandbox (Grayjay is restricted to `xdg-download`) into the principal that §4.3 already maps to root and fleet. It applies only while a daemon is running with a live seat, which is why this is MEDIUM rather than HIGH. The browser path is genuinely closed; see the clean note.
- **Fix risk:** there is no clean in-tree fix. `OPENRIG_TERMINAL_BEARER_TOKEN` only gates `/api/transport` and `/api/compaction`, not rig launch or config, and the CLI and seats would need the token as well (unverified). The options are: record it in `accepted-risks.md` with the Flatpak boundary named, or run the daemon only on demand, or add an nftables `socket cgroupv2` rule that drops loopback to :7433 from `app-flatpak-*` scopes. That last one needs a VM test against Flatpak's actual scope naming and must not break the `rig` CLI from a normal terminal.

2026-10-05, open per D4 (agent sandbox work). The nftables/iptables
`cgroup` route is not feasible here: checked live on torrent, Konsole
terminals sit at `app.slice/app-org.kde.konsole-<pid>.scope` beside
Flatpak's `app.slice/app-flatpak-<app>-<pid>.scope`, both per-launch
names. The firewall is iptables (`networking.nftables.enable = false`),
and `-m cgroup --path` matches one fixed subtree, with no wildcard on
scope names. The only static path covering Flatpaks (`app.slice`) also
covers every terminal and the agents' own `rig` calls. Same uid
everywhere, so owner matches do not separate them either. Real fix is
network separation, which is what the sandbox work provides.

### F2 -- the in-tree lockfile re-resolved deps to versions upstream never shipped, one published hours before

- **File:** `pkgs/openrig/package-lock.json`; `pkgs/openrig/package.nix:2-5` (the regeneration recipe)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (registry `time` metadata and upstream's tagged lockfile, fetched 2026-10-05)
- **Axis:** hardening
- **Reachability:** A6 (npm supply chain) -> code that runs as `lilijoy` on torrent and thinkpad every time `rig` or the daemon runs -> §4.3 -> fleet.
- **Rule:** new-rule candidate (pin npm deps to upstream's tested lockfile, or apply a publish-age cooldown)
- **Finding:** the integrity mechanics are sound. All 216 entries carry sha512 `integrity`, all resolve from `registry.npmjs.org`, and the fetched tarball matches the registry's sha512 for 0.6.5. The problem is *what* got pinned. The recipe (`npm install --package-lock-only` against the bare tarball) took the newest in-range version of every dep on the day it ran. Upstream's `package-lock.json` at tag `v0.6.5` (the comment says "no lockfile", but that is only true of the tarball; the GitHub repo has one) pins `@modelcontextprotocol/sdk` 1.28.0, `hono` 4.12.8, `ip-address` 10.1.0 and `ws` 8.20.0. The in-tree file has 1.32.1, published **2026-10-05T11:47Z, the same day**, plus 4.13.13 (one day old), 10.7.3 (four days) and 8.22.0. Same-day versions fall inside the window where compromised npm publishes are usually caught and yanked. This combination was never tested upstream, and the documented recipe repeats the same thing on every bump.
- **Fix risk:** derive the lock from upstream's tagged workspace lockfile, pruned to `packages/cli`, or regenerate with `npm install --package-lock-only --before=<0.6.5 publish date minus a cooldown>`. Either way `npmDepsHash` changes, so rebuild and re-run the D3 sqlite load check and a throwaway-daemon start like the one in G2.


**FIXED 2026-10-05:** lockfile rebuilt from upstream's v0.6.5 lock (G4); all 110 runtime entries match upstream version+integrity; npmDepsHash updated, rebuilt, sqlite + daemon start re-checked

### F3 -- an unreviewed single-maintainer binary sits outside nixpkgs with no update path, and no accepted risk records it

- **File:** `pkgs/openrig/package.nix:16-19,28-31`
- **Severity:** LOW
- **Confidence:** CONFIRMED (registry metadata)
- **Axis:** hardening
- **Reachability:** A6 -> `@openrig/cli` maintainer account or registry -> code as `lilijoy` on both PCs.
- **Rule:** n/a. This is the AR-4 class ("what executes code the lock does not cover"), but AR-4 does not cover it.
- **Finding:** what runs is the publisher's prebuilt `dist/`, `daemon/` and `tui/`, plus better-sqlite3's prebuilt `linux-x64.node`. Nothing is built from source. The npm metadata has no provenance attestation (`dist.attestations` is absent), one maintainer, 55 versions, and 0.6.5 was published 2026-10-04, a day before packaging. Because the package is in-tree rather than in nixpkgs, `nix flake update` never moves it and nothing tracks advisories against it, so a security release upstream reaches these hosts only when someone remembers to bump it. Both points may be acceptable for a tool the user chose, but they belong in `accepted-risks.md` next to AR-4, not only in a code comment.
- **Fix risk:** documentation only.

2026-10-05, open per D4 (agent sandbox work), not accepted.

### F4 -- the module puts npm, npx and corepack on every PC host's PATH, but G1 only needs `node`

- **File:** `modules/nixos/openrig.nix:14`
- **Severity:** LOW
- **Confidence:** CONFIRMED (`nix eval` of torrent's systemPackages shows `nodejs-22.23.3` coming from this change only; the store path's `bin/` has `corepack node npm npx`)
- **Axis:** needed-used
- **Reachability:** A7 (a bad AI-agent tool call, which is exactly what this change exists to run) -> `npx -y <pkg>` -> unpinned registry code.
- **Rule:** n/a (widens AR-4)
- **Finding:** G1's justification is that OpenRig's hooks run bare `node`. Installing `openrig.nodejs` also brings, for the first time on these hosts, `npx`, which fetches and executes arbitrary unpinned npm packages, along with `npm` and `corepack`. Agents and MCP configs reach for `npx -y` by habit. OpenRig itself only mentions npm in help strings (`setup.js`, `doctor.js`) and never calls it.
- **Fix risk:** expose only `node`, either through `nodejs-slim_22` (present in the pinned unstable at 22.23.3; confirm its `bin/` has no npm or npx) or through a `runCommand` that symlinks just `${openrig.nodejs}/bin/node`. Then re-run a seat and confirm `activity-relay.cjs` still fires.


**FIXED 2026-10-05:** module installs openrig.node = nodejs-slim_22 (bin/ has only node; same build nodejs_22's node links to, so no closure growth)

### F5 -- the G2 pin is a soft default: an empty `OPENRIG_BIND_HOST` or a non-wrapper start falls back to the tailnet bind

- **File:** `pkgs/openrig/package.nix:43-47`; upstream `daemon/dist/domain/bind-plan.js:11-17`
- **Severity:** LOW
- **Confidence:** PLAUSIBLE. The mechanism is confirmed: the wrapper renders `${OPENRIG_BIND_HOST-'127.0.0.1'}`, and `resolveBindPlan` does `trim() || undefined`. The Waydroid path below has not been tested.
- **Axis:** hardening
- **Reachability:** an Android app in Waydroid -> `waydroid0`, which is in `trustedInterfaces` on both PCs (`nix eval`) -> the host's own `100.x` address on :7433, accepted under the weak-host model. This is reachable only when the pin has been defeated.
- **Rule:** violates `docs/hardening.md` rule 5 in spirit (a control that relies on belief rather than enforcement)
- **Finding:** `--set-default` uses `${VAR-…}` rather than `${VAR:-…}`, so `OPENRIG_BIND_HOST=` (set but empty, for example someone "clearing" it) passes through, and the daemon treats empty as unset. It then multi-binds loopback plus the Tailscale IP, the exact G2 default. Running `node …/daemon/dist/index.js` directly skips the wrapper altogether. From the tailnet itself, the real control is the firewall: 7433 is not open on `tailscale0` (`nix eval` shows only 22 and 1714-1764 there on both hosts). That layer is fine, but G2's "every start path" holds only with that firewall caveat attached.
- **Fix risk:** small. Pass `--set` instead of `--set-default` (an override would then need `--host`, which G2 already recommends), or a `--run` guard that rejects empty values. Re-check with the G2 throwaway-daemon method.


**FIXED 2026-10-05:** wrapper now --run 'export OPENRIG_BIND_HOST=${OPENRIG_BIND_HOST:-127.0.0.1}'; live-checked unset and empty: 127.0.0.1 only

### F6 -- what OpenRig writes at runtime conflicts with the plan's stated next step of running it on this repo

- **File:** n/a in this diff; upstream `daemon/specs/agents/shared/runtime/{claude-settings,claude-mcp}.fragment.json`, `daemon/dist/adapters/claude-code-adapter.js:514-536,670-684`. Repo side: `.gitignore:14`.
- **Severity:** LOW
- **Confidence:** CONFIRMED (dist and spec files read; `git check-ignore` run)
- **Axis:** hardening
- **Reachability:** A7 / A6 -> third-party MCP output (exa, context7) or a cloned repo's committed `.claude` hooks -> an agent with `acceptEdits` in the `myPullDeploy` checkout -> §4.3 path 3 / rule 7.
- **Rule:** related to `docs/hardening.md` rule 7 (root operates on this user-writable checkout)
- **Finding:** for every seat, OpenRig merges `permissions.defaultMode: acceptEdits` plus `enabledMcpjsonServers: [exa, context7]` into `<cwd>/.claude/settings.local.json`, and writes `<cwd>/.mcp.json` pointing at `mcp.exa.ai` and `mcp.context7.com`. It also writes `.claude/{skills,plugins,agents}`, managed blocks in guidance files, and `hasTrustDialogAccepted: true` for the workspace in `~/.claude.json`. Pointed at `/home/lilijoy/dotfiles`, as the plan intends, this does three things. First, it feeds remote third-party tool output to auto-edit agents inside the checkout root deploys from. Second, it creates `.mcp.json`, which is **not** gitignored here (only `.claude/settings.local.json` is), in a public repo. Third, auto-accepting trust removes Claude Code's prompt against a cloned repo's committed hooks or MCP servers in any other workspace a rig is pointed at. The plan scopes these writes out as "imperative, owned by OpenRig", which is fine for config ownership but should not be read as "no security impact".
- **Fix risk:** before first use on this repo, gitignore `.mcp.json`, decide whether exa and context7 stay (in the rig spec, not in Nix), and prefer running seats in a worktree rather than the deploy checkout. Codex is not installed here, so the `~/.codex/config.toml` hook and MCP writes are inert for now.

2026-10-05, open per D4: deferred to the dotfiles step and to the
agent sandbox work.

### F7 -- the globally seeded openrig-skills skill pre-approves every `rig` command

- **File:** upstream `daemon/assets/plugins/openrig-core/skills/openrig-skills/SKILL.md:4`; `daemon/dist/startup.js` (`ensureSkillGlobally`, ~L795)
- **Severity:** LOW
- **Confidence:** CONFIRMED (static read, 2026-10-05 malicious-code audit of the deployed build)
- **Axis:** hardening
- **Reachability:** any Claude Code session on the host that loads the skill -> `rig *` without a permission prompt (start/stop agents, config changes, process launch).
- **Finding:** the skill's frontmatter sets `allowed-tools: Bash(rig:*)`, and daemon startup copies it into `~/.claude/skills` and `~/.agents/skills`. So the allowance is user-wide, not limited to OpenRig workspaces, and the README does not mention it. It is a narrower grant than it sounds (only `rig`), but it bypasses the per-project scope OpenRig's own permission skill asks the user to choose.
- **Fix risk:** not easy from Nix. The daemon rewrites the file at runtime under its own version ownership, so a home-manager copy would fight it.

2026-10-05, open per D4 (agent sandbox work).

The same audit's verdict, for the record: no malicious or covert
behaviour. The deployed dist maps back via source maps to the v0.6.5
source with no extra URLs, imports or exec/fetch calls; the sqlite
prebuild is byte-identical to the registry tarball; credentials appear
only in a deny-list; no persistence, eval or encoded blobs. Network
egress is local, disclosed or opt-in, except the web UI (off by default)
loading Google Fonts.

**Checked and clean.** Read `pkgs/openrig/package.nix`, `modules/nixos/openrig.nix`, the `PC.nix` import, the lockfile (programmatically) and the built output `dg1ij6m9…-openrig-0.6.5`. Things found fine:
- **Both bins are wrapped.** `rig` and `openrig-tui` each carry the bind default. `bin-wrapper.js`'s sibling-node re-exec finds no `node` in `dist/`, and the daemon child inherits the env through `buildDaemonEnv`, which does not scrub `OPENRIG_BIND_HOST`.
- **Nothing outside the wrapper starts the daemon.** No systemd, launchd or cron unit is installed, there is no self-update or registry phone-home, and the TUI start path is loopback-only by explicit `--host` (G3).
- **A persisted config value cannot widen the bind.** Because the env var outranks the config file, a `rig config set daemon.host` written through the API stays inert.
- **The browser path to the API is closed.** `Host` must be an IP, `localhost` or the machine's own name, which defeats DNS rebinding. Any request carrying `Origin` is refused unless the web UI is on and the request is same-origin. There are no CORS headers, and the GET routes are read-only.
- **The web UI does not leak a token by default.** `ui.enabled` defaults off, and no terminal bearer exists on a loopback bind, so the UI injects nothing.
- **Firewall.** `tailscale0` opens only 22 and 1714-1764 on both PCs. No host-wide TCP ports are open, and neither `tailscale0` nor `podman0` is trusted.
- **Supply-chain mechanics.** The tarball matches the registry sha512. `fetchurl` and `npmDepsHash` pin everything as fixed-output derivations, devDependencies are pruned from `$out`, `--ignore-scripts` holds (only esbuild and fsevents, both dev, have install scripts), and there are no setuid/setgid files in `$out`.
- **No new principal.** The change adds no systemd unit, firewall hole, group grant or secret reference, so the sandboxing, dedicated-user and per-host-secrets rules have nothing to apply to. Only `profile-pc` (torrent, thinkpad) imports the module.

_security finished 2026-10-06T02:15:14Z (code 01c66db73a63a1f4) -- see Findings above._

### F8 -- docs pass: stale and missing docs for the first `pkgs/` derivation

- **Files:** `pkgs/openrig/package.nix:1-5`; `docs/architecture.md`
  (Profiles, Module-organization boundary, Gotchas); `README.md` Layout;
  `hosts/{torrent,thinkpad}/README.md` Host Inventory; this plan's G2 and D4.
- **Finding:** what the docs pass found and changed:
  - `package.nix`'s header ended in a period and said "regenerate per
    F2", but the regeneration recipe is G4 (F2 is the finding it fixed).
    Header now cites `#G4`; kept at five lines so F1/F3/F5's
    `package.nix:<line>` references still point at the same code.
    `passthru.node`'s comment said nodejs_22 "wraps" the slim build; in
    the pinned nixpkgs `nodejs_22` is `symlink.nix` over `nodejs-slim_22`,
    so it now says "symlinks".
  - `docs/architecture.md` listed `profile-pc`'s imports without
    `openrig`, and nothing said where a custom derivation goes or why it
    can't sit under `modules/`. Added `openrig` to the list, a
    `pkgs/<name>/package.nix` bullet to the module-organization boundary
    (citing D1), and the inverse case to the import-tree scan-root gotcha.
  - `README.md`'s Layout block predates the new top-level `pkgs/`; added
    a line (updating-documentation.md: Layout changes when the top-level
    structure does).
  - `scripts/doc-host.sh torrent thinkpad` re-run; both inventories now
    list `openrig` and `nodejs-slim`.
  - G2's caveat still said `--set-default` keeps an explicit caller
    value; F5 replaced that with `--run ... :-`. Struck through with a
    dated note. D4 names F1, F3, F6 but not F7, which was written later
    and cites D4; added a dated note under D4.
  - Not changed: `AGENTS.md` (its "Where things live" is a docs table,
    no doc was added), `docs/style-guide.md` (the placement rule is
    architecture, now covered there).

**FIXED 2026-10-05:** docs pass edits in the working tree on openrig-package (uncommitted)

_docs-updater finished 2026-10-06T02:34:19Z (code 820748c34971e045) -- see Findings above._

**REJECTED 2026-10-05:** User dropped OpenRig after review: Claude Code natively covers most of its useful core and its design conflicts with this fleet's threat model; agent orchestration folds into the planned agent-sandbox work (G5). Package never merged; only this record lands.
