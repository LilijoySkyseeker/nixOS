---
slug: doc-host-sh-reports-custom-firewall-rules-when-only-networking-nat-s
created: 2026-09-16
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# doc-host.sh reports custom firewall rules when only networking.nat's preamble is present

## State

Not started. Spotted and logged, not fixed.

## Original plan

`scripts/doc-host.sh` decides whether to print "plus custom
`networking.firewall.extraCommands` iptables rules -- see the host's
configuration.nix" in a host README's Firewall block by testing
`stringLength extraCommands > 0`.

That test cannot distinguish a real rule from boilerplate. The
`networking.nat` module contributes its own teardown preamble to
`extraCommands`, so the string is non-empty on any host with NAT even
when nothing hand-written is there.

Found by `docs-updater` while reviewing
`2026-09-16-switch-torrent-scanning-to-brother-s-closed-source-brscan-driver-for.md`
(its F10). That change deleted torrent's only hand-written
`extraCommands` rule, and `hosts/torrent/README.md` still advertises
custom firewall rules -- now pointing a reader at
`hosts/torrent/configuration.nix`, which never held the rule in the first
place (it lived in `modules/nixos/brother-mfc-l2740dw.nix`).

So the line is wrong twice over on torrent: it claims rules that no
longer exist, and names the wrong file to look in.

Worth fixing rather than ignoring because host READMEs are generated and
therefore trusted -- a stale hand-written doc invites scepticism, a stale
*generated* one does not.

Possible shapes, not yet chosen:

- Compare against the NAT preamble and print only the remainder.
- Have the module that owns a rule declare it, rather than inferring from
  a concatenated string.
- Drop the "see configuration.nix" pointer, which is wrong for any rule
  defined in a module rather than a host file.

## Progress

- [ ] Decide which shape
- [ ] Fix `scripts/doc-host.sh`, regenerate affected host READMEs


## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*
