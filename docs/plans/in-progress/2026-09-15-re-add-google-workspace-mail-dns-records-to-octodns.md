---
slug: re-add-google-workspace-mail-dns-records-to-octodns
created: 2026-09-15
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---

# Re-add Google Workspace mail DNS records to octoDNS

## State

**2026-09-15, records declared and verified at eval level; not yet
deployed.** Google Workspace mail for `skyseekerlabs.net` was set up by
hand in the Cloudflare dashboard and worked. `octodns-sync` deleted all
three records on 2026-09-12 17:47 (G4) -- it is authoritative over the
whole zone, so anything not declared in `modules/services/octodns.nix`
gets pruned on the next hourly run. The fix is to declare them, which
this change does, plus a DMARC record that never existed.

All three deleted values were recovered verbatim from homelab's
`octodns-sync` journal (G5), so nothing had to be re-fetched from the
Admin console. Verified beyond reading the source: the rendered zone YAML
was inspected in the store, `octodns-validate` passes on it, a negative
control with the semicolons unescaped fails with exactly the
`unescaped ;` error (proving the G1 escaping is load-bearing and not
cargo-culted), and the DKIM record was pushed through octoDNS's own
chunker to confirm it splits into 253- and 155-byte DNS strings that
reassemble to the original 408 characters. Full `verify-ladder` passes.

Nothing here is secret. Every value is published in public DNS; the DKIM
key is the public half and the private half never leaves Google. No sops
involvement, which is why the values sit in plain Nix in a public repo.

Verified to rung 3 (ran it locally, output inspected). Rung 4+ is not
reachable without a real deploy: the records only exist in Cloudflare
once `octodns-sync` runs on homelab. Deliberately left in `in-progress/`
until that happens and the four remaining Progress items are done. D1
(the `p=none` policy level) still wants an explicit sign-off.

## Original plan

Declare the Google Workspace mail records in
`modules/services/octodns.nix` so octoDNS stops pruning them:

- `MX` at the apex -- priority 1, `smtp.google.com.` (the modern
  single-record form; the five `aspmx.l.google.com` records are the
  pre-2023 shape)
- `TXT` at the apex -- SPF plus the `google-site-verification` token,
  as one record with two values (G2)
- `TXT` at `google._domainkey` -- the 2048-bit DKIM public key
- `TXT` at `_dmarc` -- new, starting at `p=none`

## Progress

- [x] Declare MX + apex TXT (SPF, site-verification)
- [x] Declare DKIM TXT at `google._domainkey`
- [x] Declare DMARC TXT at `_dmarc` (D1, D2)
- [x] `verify-ladder` clean
- [x] Review of the diff -- inline only, subagents not run (see Findings)
- [ ] Deploy to homelab and confirm the records are back in Cloudflare
- [ ] Create the `postmaster@` Group in the Admin console (D2)
- [ ] Confirm DKIM still reads *Authenticating* in Gmail > Authenticate email
- [ ] Confirm the domain is still verified in Account > Domains

## Decisions (D)

### D1 -- DMARC starting policy

No DMARC record has ever existed for this domain. Google's guidance is
to start at `p=none` (monitor only, deliver everything), then tighten to
`quarantine` and then `reject` once aggregate reports come back clean.
Proposing `p=none`.


**DISCUSSED 2026-09-15:** Proposed p=none and the user accepted the record as written when answering D2, but has not separately signed off on the policy level. Confirm before the plan closes.

### D2 -- DMARC `rua` reporting address

`rua=` needs a mailbox that actually exists in Workspace to receive the
aggregate reports. Proposing `postmaster@skyseekerlabs.net`, which is
the conventional choice, but it has to be a real mailbox or alias or the
reports bounce.


**ANSWERED 2026-09-15:** User chose to create postmaster@ as a Group in the Admin console (2026-09-15), so the record keeps rua=mailto:postmaster@skyseekerlabs.net as written. postmaster is a Google Workspace reserved word — it cannot be a user or alias, only a Group, and the Admin console reports 'Settings weren't saved because an error occurred' while still creating the group. Same-domain rua also avoids needing an external-reporting authorization record.

## Gotchas (G)

### G1 -- semicolons in TXT values must be escaped as `\;`

octoDNS's chunked-value validator
(`octodns/record/chunked.py`, `_unescaped_semicolon_re = r'\w;'`)
rejects any `;` preceded by a word character, so a raw
`v=DMARC1; p=none` fails validation. The Cloudflare provider unescapes
on push (`_contents_for_TXT`: `chunked.replace('\;', ';')`) and
re-escapes on read (`_data_for_TXT`), so `\;` round-trips and Cloudflare
stores real semicolons. In Nix source that means writing `\;`. Affects
DKIM and DMARC; SPF happens to contain no semicolons.

### G2 -- one TXT record per name, not two entries

`populate_should_replace` defaults to false and is not set in this
repo's octoDNS config, so two separate `{ type = "TXT"; ... }` entries
under the same name raise `DuplicateRecordException`. SPF and the
site-verification token must share a single record using `values = [ ... ]`.

### G3 -- the DKIM record is 408 chars and is chunked automatically

Past the 255-byte DNS string limit, but `_ChunkedValuesMixin` splits it
and avoids breaking on escape characters. No manual splitting needed.

### G4 -- octoDNS is authoritative over the entire zone

Root cause of the wipe. Records added in the Cloudflare dashboard
survive at most one hour (`OnUnitActiveSec = "1h"`). Anything that must
exist in this zone has to be declared in `modules/services/octodns.nix`
-- there is no partial/ignore mode configured.

### G5 -- deleted record values are recoverable from the journal

`journalctl -u octodns-sync | grep Delete` on homelab prints each
deleted record's full rdata. That is what made this restoration possible
without touching the Admin console, and is worth remembering the next
time octoDNS prunes something unexpectedly.

## Findings (F)
*(populated by security/docs-updater when invoked)*

**Note:** the `/simplify`, `security` and `spec-check` subagents named by
`required-agents` were not run -- this session is configured not to spawn
subagents unprompted. F1 and F2 come from an inline review of the diff
instead, and those agent passes are still owed if the user wants them.
F3-F6 are from a `docs-updater` pass run 2026-09-15 over the branch diff.

### F1 -- SPF uses `~all` (softfail) rather than `-all`

Nothing in this fleet sends mail: there is no msmtp, postfix, sendmail or
any other MTA anywhere in `modules/` or `hosts/`. Google is the only
sender, so `-all` (hardfail) would be strictly stronger and would not
break anything known. `~all` is what Google's own documentation
recommends, because a hardfail interacts badly with forwarding and with
some of Google's own relay paths, and DMARC alignment is meant to carry
the enforcement instead. Left as `~all` deliberately; revisit together
with the DMARC policy level, since the two are what actually decide
whether a spoofed message gets rejected.


**ACCEPTED 2026-09-15:** Keeping Google's recommended ~all. Revisit alongside the DMARC policy level, which is what actually enforces.

### F2 -- `p=none` leaves the domain spoofable

This is the intended starting state, not a defect: `p=none` instructs
receivers to take no action, which is what makes the monitoring phase
safe. It does mean that until the policy is tightened, anyone can send
mail claiming to be `@skyseekerlabs.net` and DMARC will not stop them.
The risk is that `p=none` is a temporary state that quietly becomes
permanent. Whoever picks this up should read the aggregate reports and
move to `quarantine`, then `reject`.

**ACCEPTED 2026-09-15:** Intended starting state for the monitoring phase. Tracked as the reason the plan stays open past deploy.

### F3 -- MX history moved out of the module comment

`modules/services/octodns.nix:39-41` carried this verbatim, as an inline
comment above the MX record:

> Google Workspace mail. One MX record, not the five aspmx.l.google.com
> ones -- those are the pre-2023 shape, kept only on domains that already
> had them.

That is background on Google's record shapes, not mechanics of the line
below it, so it belongs here per `docs/style-guide.md`'s "Why context:
the plan file, not comments". The comment is now
`# Google Workspace mail, single-MX form` plus a citation to this entry.
`smtp.google.com.` at preference 1 is the current single-record form;
the five `aspmx.l.google.com`/`alt1..alt4` records are only kept on
domains that already had them.

### F4 -- DKIM comment carried plan-level prose

`modules/services/octodns.nix:63-68` carried this verbatim above the
`google._domainkey` record:

> DKIM public key, issued by the Workspace admin console (Gmail >
> Authenticate email). Public by definition -- it is published in DNS;
> the private half stays with Google. 408 chars, so octoDNS splits it
> across DNS's 255-byte strings on push. The `\;` escapes are required:
> octoDNS rejects bare semicolons in a TXT value and the Cloudflare
> provider unescapes them again on the way out.

Three separate things, two of which were already written up here: the
escaping is G1, the 408-char chunking is G3, and the third -- why a key
is checked into a public repo -- is the "public half only" point in the
State section. The comment kept the provenance (which console page
reissues the key, which a reader cannot derive from the value) and now
cites G1, G3 and this entry instead of restating them. The 408-char
figure was re-checked against the shipped string and is correct: the
`\;` escapes count as two characters each, so the value octoDNS sees is
408 characters.

### F5 -- the DMARC comment claimed the `postmaster@` Group already exists

`modules/services/octodns.nix:77-82` said, in the present tense, that
`postmaster@` "only exists as a Group, never a user". Creating that Group
is still an open Progress item, so as shipped the `rua=` mailbox does not
exist yet and aggregate reports will bounce until it does. The accurate
version of that sentence is D2's: postmaster is a Workspace reserved word
and therefore *can* only be created as a Group. The rest of the comment
(the p=none-then-quarantine-then-reject ladder, and same-domain `rua`
avoiding an external-reporting authorization record) restated D1 and D2
in full. The comment is now a one-line label plus citations to D1 and D2.

### F6 -- `docs/architecture.md`'s homelab row was stale before this change

Not caused by this change, found while refreshing homelab's Host
Inventory: `scripts/doc-host.sh homelab` pulled in `grafana` (service,
package, port 3000, and the `grafana_admin_password`/`grafana_secret_key`
secrets) and `dockremap`, none of which this branch touches. Those came
from `dd86cf8 feat(homelab): wire grafana, fix factorio under docker
userns-remap`, which wired `nixosModules.grafana` and
`nixosModules."docker-userns-remap"` into homelab without regenerating
the README or updating `docs/architecture.md`. Two fixes applied:
the per-host table's `homelab` row now lists `docker-userns-remap` and
`grafana`, and the `modules/services/` bullet no longer says "grafana is
written but wired to no host yet, see the comment in
`modules/flake/hosts.nix`" -- it is wired to homelab, and there is no
such comment in `hosts.nix` any more.

### F7 -- the 2026-08-26 audit's "domain that sends no mail" premise is now false

`docs/audits/2026-08-26/findings-tail.md:842` (L-09, mirrored as
F-P4-10 in `P4-services.md:922`) argues for `v=spf1 -all` and DMARC
`p=reject` on the grounds that this is "a domain that sends no mail".
That was true when the audit was written; it is not true now that
Workspace mail is declared here. Left unedited on purpose -- the audit is
a dated snapshot and rewriting its premises would falsify the record --
but it is the same question F1 and F2 park, so whoever revisits the SPF
qualifier and the DMARC policy level should read L-09 alongside them
rather than treating the audit's recommendation as still applying to an
unused domain. L-09's other half (no CAA record, and a hand-added one
would be pruned within the hour by G4) is untouched by this change and
still open.

_docs-updater finished 2026-09-15T17:59:13Z (code 1fd137775f513d33) -- see Findings above._
