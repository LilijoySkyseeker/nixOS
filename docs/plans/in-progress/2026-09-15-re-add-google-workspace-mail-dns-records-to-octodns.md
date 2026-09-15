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

**2026-09-15, review pass run.** `docs-updater` moved the why-context out
of the module comments and caught one real inaccuracy (F5). `security`
returned 0 CRITICAL, 0 HIGH, 3 MEDIUM, 5 LOW, 2 INFO -- nothing blocking.
F16 was fixed here: `octodns-sync`'s sandbox now matches the beets.nix
baseline, moving `systemd-analyze security` from 6.6 MEDIUM to 3.5 OK.
F10, F11, F12 and F13 were carried into their own `todo/` plans rather
than widened into this branch.

**2026-09-15, `postmaster@` and `abuse@` Groups created.** D2's dependency
is satisfied: the `rua` mailbox exists, so reports will be delivered
rather than bounce. F9 stays open on its remaining half -- nothing reads
or alerts on those reports yet -- which is also what D1 now turns on.

One useful correction from the review: adding the MX *reduces* the vps's
exposure rather than adding to it. With no MX, RFC 5321 implicit-MX made
the apex A record the domain's mail exchanger, aiming every sending MTA
at the vps on port 25; mail now goes to Google instead.

Verified to rung 3 (ran it locally, output inspected). Rung 4+ is not
reachable without a real deploy: the records only exist in Cloudflare
once `octodns-sync` runs on homelab. Deliberately left in `in-progress/`
until that happens and the remaining Progress items are done. D1 (the
`p=none` policy level) still wants an explicit sign-off.

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
- [x] Review of the diff: inline, then `docs-updater` and `security`
- [x] Harden the `octodns-sync` sandbox (F16)
- [ ] Deploy to homelab and confirm the records are back in Cloudflare
- [x] Create the `postmaster@` Group in the Admin console (D2)
- [ ] Confirm DKIM still reads *Authenticating* in Gmail > Authenticate email
- [ ] Confirm the domain is still verified in Account > Domains

## Decisions (D)

### D1 -- DMARC starting policy

No DMARC record has ever existed for this domain. Google's guidance is
to start at `p=none` (monitor only, deliver everything), then tighten to
`quarantine` and then `reject` once aggregate reports come back clean.
Proposing `p=none`.


**DISCUSSED 2026-09-15:** Proposed p=none and the user accepted the record as written when answering D2, but has not separately signed off on the policy level. Confirm before the plan closes.


**ANSWERED 2026-09-15:** Ship p=none, then tighten. User signed off 2026-09-15 on the staged path: p=none now; read the aggregate reports landing in the postmaster@ Group for 1-2 weeks; move to p=quarantine once every legitimate sender shows SPF/DKIM passing and aligned; then p=reject after another clean 1-2 weeks. Revisit F1's SPF ~all vs -all at the quarantine step, since the two together are what actually decide whether a forgery is rejected. F9 stays open until something reads or alerts on those reports -- the ladder above depends on someone actually looking.

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

**Note on provenance.** F1-F2 are an inline review of the diff. F3-F7 are
a `docs-updater` pass, F8-F17 a `security` pass, both run 2026-09-15 over
the branch diff at the user's request. `/simplify` was skipped, also at
the user's request. `spec-check` was obliged by `required-agents` but
**does not exist** -- `docs/skills/workflow/reference.md:45` marks it "not
yet" and `docs/skills/plan/scripts/lib.sh:15` says the same. D1 therefore
has no automated spec check behind it.

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

---

_`security` subagent pass, 2026-09-15, cold review of `google-workspace-mail-dns`
(`21d9b3a`, `286a0f6`, `db3a16d`) against `master`. F8-F17 below._

### F8 — the public-repo argument is sound about the *values* and unsound about the *posture*

- **File:** `modules/services/octodns.nix:39-83`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** a commodity phishing/spam operator running GitHub code
  search (or any of the scrapers that mirror public repos) for
  `v=DMARC1`, `p=none`, `~all`, `google-site-verification` — with **no
  prior knowledge of `skyseekerlabs.net`**.
- **Rule:** n/a — new-rule candidate ("a public repo is a discovery
  channel, not just a disclosure channel")
- **Finding:** The narrow claim in the State section holds, and I checked
  it rather than assuming it.
  - The DKIM value is a genuine public half: decoded as SPKI it is
    `Public-Key: (2048 bit)` RSA (`openssl pkey -pubin -text`). 2048 bits
    is not factorable, and the private half is not derivable from it.
    Publishing it in git discloses exactly what `dig TXT
    google._domainkey.skyseekerlabs.net` discloses.
  - The `google-site-verification=` token is an opaque per-(site,
    verifying-account) string. Knowing it does not let a third party
    verify anything: verification requires the string to be *published
    under the domain*, which only whoever controls the zone can do. It is
    not a bearer credential and it is not reversible to the account that
    minted it.
  - SPF, MX and DMARC are definitionally public policy statements.

  So on confidentiality of the four values, the reasoning is correct and
  I found nothing to overturn it.

  What the reasoning does not cover is **discoverability**. `dig` is a
  pull: you must already know the name to learn anything. A public repo
  is a push — it hands the same facts to people who have never heard of
  the domain, in a greppable, permanently-archived, search-indexed form.
  And it hands over more than the zone does, as one bundle: that the
  domain is a live Google Workspace tenant (site-verification token +
  Google MX), that its SPF is softfail and its DMARC is `p=none`, that
  `postmaster@` is a real reporting address, that mail is *actively used*
  rather than vestigial, the operator's real name and personal address
  from commit metadata, the vps's public v4 and v6, and every other name
  in the zone. Enumerating a zone from outside normally costs an attacker
  effort and guesswork; this removes both.

  This is not a reason to encrypt the records — encrypting a value that
  is published in DNS is theatre. It is a reason to stop treating "it's
  in public DNS anyway" as closing the question, because it answers
  *confidentiality* and the exposure here is *targeting*. It also means
  F1's and F2's accepted weaknesses are not merely present, they are
  advertised: a `p=none` domain found by search is a cheaper target than
  a `p=none` domain found by luck. Rated LOW because it grants nothing
  and changes only probability — deliberately not inflated.
- **Fix risk:** None available that is worth taking. The only real
  mitigations are to remove the weakness rather than the description of
  it (F9, F1, F2). Do not "fix" this by moving public DNS values into
  sops: that adds a decryption dependency to the deploy path (F11) and
  protects nothing, since `dig` still answers.


**ACCEPTED 2026-09-15:** Values confirmed safe to publish. The discoverability point is real but does not change the disclosure set — the repo already carries the domain and vps IPs.

### F9 — `p=none` is a guard that declines to act, and nothing measures its outcome

- **File:** `modules/services/octodns.nix:77-83`; plan Progress item
  "Create the `postmaster@` Group in the Admin console"; `docs/hardening.md`
  standing rule 11
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any sender on the internet — `p=none` instructs every
  receiver to deliver mail that fails DMARC, so a spoofed
  `From: <anything>@skyseekerlabs.net` lands in the inbox of anyone this
  domain corresponds with, including the operator's own Workspace users.
  The compensating control F1 and F2 were both accepted on is aggregate
  reporting, and as shipped that control does not exist.
- **Rule:** violates `docs/hardening.md` standing rule 11 ("A guard that
  declines to act must be watched by something that measures the
  outcome, not the attempt")
- **Finding:** `p=none` is literally a guard that declines to act. Rule
  11 was written about `deploy-guards.nix`, but its stated principle is
  general, and DMARC monitor mode is the same shape: it succeeds
  silently whether it is working or not.

  Two independent gaps, both live right now:

  1. **The `rua` mailbox does not exist.** Creating the `postmaster@`
     Group is still an unchecked Progress item, and F5 already notes the
     comment wrongly claimed otherwise — but F5 treats it as a docs
     accuracy problem. The security consequence is not documented
     anywhere: shipping `rua=mailto:postmaster@skyseekerlabs.net` against
     a non-existent recipient means every reporting MTA's aggregate
     report bounces, so the monitoring phase collects **nothing**. A
     DMARC record in monitor mode with a dead `rua` is strictly worse
     than no DMARC record, because it creates a documented belief that
     monitoring is underway.
  2. **Nothing reads or alerts on the reports even once the Group
     exists.** Every other guard in this fleet has a watcher —
     `myHealthAlerts` polls `systemctl --failed` every 15 minutes, the
     deploy staleness check watches
     `/nix/var/nix/profiles/system`'s mtime. There is no equivalent for
     DMARC. F2's exit condition is "whoever picks this up should read the
     aggregate reports and move to `quarantine`, then `reject`", with no
     owner, no date, and no trigger. F2 itself names the failure mode —
     "the risk is that `p=none` is a temporary state that quietly becomes
     permanent" — and then ships the arrangement that guarantees it.

  This is the finding I would not close the plan over. F1 and F2 are
  defensible *as accepted risks with a monitoring phase attached*; they
  are not defensible as accepted risks with nothing attached, and that is
  the shipped state.
- **Fix risk:** Creating the Group is a console action (D2 already
  records that `postmaster` is a Workspace reserved word and the console
  misreports success). The real work is deciding what watches the
  reports: a calendar reminder is the minimum honest answer, an alert is
  better. Note the ordering trap — tightening to `p=reject` *before*
  reports have been read is the failure mode in the other direction and
  will silently drop legitimate mail from any forwarder or third-party
  sender not yet in SPF.

**2026-09-15, half of this closed.** The user created the `postmaster@`
and `abuse@` Groups in the Admin console, so the `rua` mailbox now exists
and aggregate reports will land instead of bouncing once the records are
deployed. The second half stands: nothing reads or alerts on those
reports, so `p=none` is still a guard whose outcome no one measures. That
is what keeps this finding open, and it is the remaining substance behind
D1.

### F10 — a silent zone prune is now a silent mail outage, and only *failures* are watched

- **File:** `modules/services/octodns.nix:200-228`;
  `modules/nixos/health-alerts.nix:262-267`; plan G4
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** no adversary required — this has already happened
  once (the 2026-09-12 17:47 wipe that created this plan). Adversarially:
  anyone who lands a change on `master` that drops, renames or
  mis-nests the `zoneRecords` entries — a bad merge, a refactor of
  `modules/services/octodns.nix`, a `lib.mkIf` that evaluates false —
  gets the mail records deleted from authoritative DNS on the next
  deploy, without ever touching a Cloudflare credential.
- **Rule:** violates `docs/hardening.md` standing rule 11 ("Watch the
  result the guard exists to produce")
- **Finding:** `myHealthAlerts` detects a *failed* `octodns-sync`
  (`systemctl --failed --no-legend --plain`, `health-alerts.nix:262`).
  The 2026-09-12 wipe was a **successful** run. Nothing in this fleet
  observes the thing octodns-sync exists to produce — that Cloudflare
  actually holds the declared records — so the exact event this plan was
  written to repair remains undetectable by the same means.

  What changed with this commit is the blast radius of that undetectable
  event. Before, a prune cost jellyfin/minecraft/factorio DNS: loud,
  self-reporting, someone complains within minutes. Now the same event
  additionally deletes the MX (inbound mail to the domain stops — senders
  fall back to implicit MX at the apex A, i.e. the vps, which has only
  80/443/51820 open, so mail queues and then bounces), the DKIM key
  (outbound Workspace mail immediately starts failing DKIM at every
  receiver, degrading the domain's sending reputation), and SPF/DMARC.
  All four records carry `ttl = 300`, so the deletion is globally
  effective in five minutes. Mail outages are the classic silent failure:
  nobody tells you they could not reach you.

  `enforce_order = false` and the absence of any partial/ignore mode
  (G4) mean the generated zone file is the *whole* truth about the zone
  every hour, forever. That is a fine design — it is why the records
  will be restored — but it makes the Nix attrset a single point of
  failure for mail with no independent check.
- **Fix risk:** The obvious watcher (a periodic `dig MX/TXT` against a
  public resolver, alerting via the existing `notify` path in
  `health-alerts.nix`) must not be pointed at Cloudflare's own
  authoritative servers only, or it will confirm what octoDNS just wrote
  rather than what the world sees. It also must tolerate a legitimate
  intentional change to the records without paging — hard-coding the
  expected rdata in a second place creates a new drift surface.


**ACCEPTED 2026-09-15:** Carried to 2026-09-15-alert-on-destructive-octodns-sync-runs-not-just-failed-ones.md. Verified: health-alerts.nix:263 keys on systemctl --failed and the wipe exited 0.

### F11 — the Cloudflare token's blast radius grew from "web/game DNS" to "full mail control of a live Workspace tenant"

- **File:** `modules/services/octodns.nix:188-207`; `.sops.yaml:14-23`;
  `docs/audits/2026-08-26/findings-tail.md:830-848` (L-09)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (mechanism and key distribution);
  PLAUSIBLE (the token's actual Cloudflare scope, which is inside sops
  and was **not** read, per `docs/procedures/secrets.md`)
- **Axis:** hardening
- **Reachability:** two paths. (a) Root on homelab reads
  `/run/secrets/rendered/octodns-env` (mode `0400`, owner `octodns`,
  confirmed by `nix eval`). (b) — the one that matters more — `.sops.yaml`
  has a **single blanket `creation_rules` entry naming all seven
  recipients**, so the age keys resident on `thinkpad` and `torrent`
  can decrypt `cloudflare_octodns_token` straight out of the public
  repo, despite neither host declaring or consuming it. A compromise of
  the daily-driver laptop is therefore a zone-control compromise.
- **Rule:** violates `docs/hardening.md` Secrets rule 2 ("Give each host
  only the secrets it consumes"); relevant to rule 1 (public repo,
  history is permanent)
- **Finding:** L-09 characterised this token by what it could do to a
  *domain that sends no mail*: satisfy ACME DNS-01, repoint the apex to
  satisfy HTTP-01, and thereby MITM `jellyfin.`. F7 correctly notes that
  premise is now false, but only draws the SPF/DMARC conclusion from it.
  The credential conclusion is the bigger one and is not recorded
  anywhere.

  A holder of this token can now: replace the MX to receive **all**
  inbound mail for the domain (including password-reset and account-
  recovery mail for anything registered at an `@skyseekerlabs.net`
  address); replace the `google._domainkey` TXT with a key they hold;
  and add themselves to the SPF `include`. The result is forged mail
  that passes SPF, passes DKIM, and is DMARC-*aligned* — qualitatively
  better forgery than the unauthenticated spoofing F2 already accepts,
  and it survives any future tightening to `p=reject`.

  Window and self-healing, both worth stating precisely: `ttl = 300`
  means an attacker's substituted records propagate in five minutes;
  `OnUnitActiveSec = "1h"` means octoDNS reverts them within the hour.
  So each tick buys roughly fifty-five minutes of fully-propagated,
  fully-authenticated mail control, repeatable, and per F10 **the revert
  is not alerted on** — the attack leaves no signal anyone sees.

  I am rating this MEDIUM, not HIGH, deliberately: this change increases
  the *impact* of the token, not its *reachability*, and the rule-2
  violation predates it. The blanket `.sops.yaml` rule is worth a HIGH in
  its own right — it is the rubric's "any secret exposed to a principal
  that shouldn't hold it" clause, verbatim — but it is not caused by this
  branch and I am not using it to block this merge.
- **Fix risk:** Splitting `.sops.yaml` into per-path `creation_rules` is
  the real fix and is a `sops updatekeys` operation, not a value change —
  but per `docs/procedures/secrets.md`, narrowing the recipient set is
  **not** a revocation until the value is rotated at Cloudflare, and the
  runbook records this token as already rotated once (2026-08-28, old
  token deleted). Getting the regex wrong locks homelab out of the token
  and `octodns-sync` fails closed at the next tick — which, per F10, at
  least *is* alerted on.


**ACCEPTED 2026-09-15:** Carried to 2026-09-15-scope-sops-recipients-per-host-instead-of-one-blanket-rule.md. Verified against .sops.yaml. Re-keying is a user action; agents do not touch secrets/.

### F12 — the MX is now the domain's only mail path and it has no MTA-STS or TLS-RPT

- **File:** `modules/services/octodns.nix:41-48`
- **Severity:** LOW
- **Confidence:** CONFIRMED (the records are absent); PLAUSIBLE (the
  downgrade is exploitable only from a privileged network position)
- **Axis:** hardening
- **Reachability:** an on-path attacker between an arbitrary sending MTA
  and `smtp.google.com` — a BGP hijack of Google's SMTP prefixes, or a
  spoofed DNS answer to a non-validating resolver at the *sender's* side.
  Without a published policy, a sending MTA that offers STARTTLS silently
  accepts a stripped `EHLO` response and delivers in cleartext, with no
  signal to either party.
- **Rule:** n/a — new exposure introduced by this change
- **Finding:** Before this commit the domain had no MX and therefore no
  inbound mail path worth attacking. This commit creates one, and
  declares it with opportunistic TLS as the only protection. Inbound mail
  to `@skyseekerlabs.net` is now readable and modifiable by an attacker
  who can get on-path, which for internet mail is a real if
  resource-intensive capability.

  Two records close it, and neither is a console action, because G4
  prunes anything hand-added:
  - **MTA-STS** — `_mta-sts.skyseekerlabs.net` TXT (`v=STSv1; id=...`)
    plus an `mta-sts.skyseekerlabs.net` A/AAAA, with the policy served
    at `https://mta-sts.skyseekerlabs.net/.well-known/mta-sts.txt`. The
    vps already runs Caddy with a per-host `virtualHosts` attrset
    (`hosts/vps/configuration.nix:654`), so the policy host is cheap to
    add there. Google Workspace supports enforcing MTA-STS for tenants.
  - **TLS-RPT** — `_smtp._tls` TXT (`v=TLSRPTv1; rua=mailto:...`), which
    is the *only* mechanism by which a downgrade would ever be noticed.
    Same watcher problem as F9: worthless without somewhere the reports
    land and someone who reads them.

  DANE is the alternative and is out of reach here — it needs DNSSEC on
  the zone, which octoDNS does not manage.
- **Fix risk:** MTA-STS is the one mail record with a genuine
  self-inflicted-outage mode. Publishing `mode: enforce` while the
  policy host is unreachable, its certificate has expired, or the `id`
  has not been bumped after an edit causes conforming senders to **refuse
  delivery** rather than fall back. Start at `mode: testing`, confirm via
  TLS-RPT that reports come back clean, and only then enforce. The
  `mta-sts` A/AAAA must go in `zoneRecords` in the same change or it is
  pruned within the hour and the policy host vanishes.


**ACCEPTED 2026-09-15:** Carried to 2026-09-15-add-the-zone-hardening-records-caa-mta-sts-and-tls-rpt.md — start at mode testing, not enforce.

### F13 — still no CAA record, in the one change that touches the file where it belongs

- **File:** `modules/services/octodns.nix:27-138`;
  `docs/audits/2026-08-26/findings-tail.md:838-841` (L-09)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** an attacker with a transient DNS or BGP position
  against the domain, or a compromised/coerced public CA, obtaining a
  publicly-trusted certificate for `jellyfin.skyseekerlabs.net` and
  MITMing the one internet-facing service that accepts user passwords.
  With no CAA record, **every** public CA is authorised; with one, the
  set is whatever is listed.
- **Rule:** open item from the 2026-08-26 audit (L-09 / `F-P4-10`)
- **Finding:** F7 acknowledges this half of L-09 is untouched and still
  open, which is accurate — I am recording it as a finding rather than a
  note because L-09 explicitly says the fix has to land *here*
  ("**this is not a 'just add it in the console' situation**":
  `octodns-sync --doit` runs hourly and deletes a hand-added CAA on the
  next tick), and this is the first change since the audit to open that
  file. The cost of adding it in this branch is one attrset entry; the
  cost of not adding it is that the next octoDNS change has the same
  standing invitation and the same outcome.

  Mail does not change this materially — CAA governs certificate
  issuance, not SMTP — so I am keeping it at L-09's own severity rather
  than upgrading it on the strength of the MX.
- **Fix risk:** L-09 already names it and it is the real one: get CAA
  wrong and certificate **renewal** breaks silently, weeks later, not at
  deploy. Caddy's default issuer chain is Let's Encrypt with a ZeroSSL
  fallback, so an `issue` set naming only `letsencrypt.org` will work
  right up until the day the fallback is needed. Check the configured
  issuers on vps first and include the fallback.


**ACCEPTED 2026-09-15:** Carried to the same zone-hardening-records plan. Needs Caddy's actual CA identified before it is safe to declare.

### F14 — `postmaster@` is a new unauthenticated internet-reachable mail drop, advertised in DNS and in this repo

- **File:** `modules/services/octodns.nix:81`; plan D2 and the open
  "Create the `postmaster@` Group" Progress item
- **Severity:** LOW
- **Confidence:** PLAUSIBLE (the Group's Workspace settings are not
  visible from this repo and were not inspected)
- **Reachability:** anyone on the internet. For DMARC aggregate reporting
  to work at all, the Group must accept posts from external, unverified
  senders — that is the whole point of a `rua` address. So the moment
  the Group is created, `postmaster@skyseekerlabs.net` becomes a mailbox
  that any sender can deliver arbitrary attachments to, whose existence
  and exact spelling are published both in DNS and in this file.
- **Axis:** hardening
- **Rule:** n/a — new exposure introduced by this change
- **Finding:** DMARC aggregate reports arrive as gzipped or zipped XML
  from arbitrary reporting MTAs. Nothing authenticates them; a report
  claiming to be from any receiver is indistinguishable from a real one.
  So the content that lands in this mailbox is attacker-chosen
  compressed XML: decompression bombs, entity-expansion and XXE payloads,
  and plain phishing dressed as a report from a name the operator
  expects to see.

  Today the parser is a human, which bounds it. It stops being bounded
  the moment tooling is wired up to close F9 — at which point an
  unauthenticated internet-reachable input is feeding a compressed-XML
  parser running somewhere in this fleet. Worth deciding *now*, while
  choosing how to consume the reports, rather than after.

  Two things to check when the Group is actually created, neither of
  which is derivable from this repo: that external posting is permitted
  (or reports bounce and F9 stays open) **and** that the Group's message
  archive/visibility is not set to anything readable beyond the intended
  members — a Workspace Group's archive setting is independent of its
  posting setting.
- **Fix risk:** Tightening posting permissions to close the spam surface
  will also block the legitimate reports, since they come from senders
  you cannot enumerate in advance. This one is accept-and-scope, not
  fix: treat the mailbox as untrusted input and never auto-parse it
  without bounded decompression and entity expansion disabled.


**ACCEPTED 2026-09-15:** Inherent to postmaster@ being a working RFC-mandated address. Revisit when tooling is pointed at the mailbox to close F9.

### F15 — `sops.secrets.cloudflare_octodns_token` is a second plaintext copy of the zone-control token with no consumer

- **File:** `modules/services/octodns.nix:188-198`
- **Severity:** INFO
- **Confidence:** CONFIRMED (`nix eval
  .#nixosConfigurations.homelab.config.sops.secrets.cloudflare_octodns_token`
  → `mode 0400`, `owner/group octodns`, `path
  /run/secrets/cloudflare_octodns_token`; the unit's `EnvironmentFile` is
  `/run/secrets/rendered/octodns-env`, the template, not this path)
- **Axis:** needed-used
- **Reachability:** the `octodns` service user, and root on homelab. Not
  an escalation — `octodns` can already read the rendered template — but
  it is one more file on disk holding the credential from F11, for
  nothing.
- **Rule:** n/a
- **Finding:** The `sops.secrets.cloudflare_octodns_token` *declaration*
  is required, because `config.sops.placeholder.<name>` only resolves for
  a declared secret. The `owner = "octodns"` / `group = "octodns"` on it
  is not: nothing reads `/run/secrets/cloudflare_octodns_token`. Leaving
  it at the sops-nix default (`root:root`, `0400`) would halve the number
  of paths from which the `octodns` user — and anything that ever
  achieves code execution as it, see F16 — can lift the token, at zero
  functional cost. Pre-existing, not introduced by this branch; surfaced
  because item 5 of the review brief asks about the deployment path.
- **Fix risk:** Minimal, but verify rather than assume: drop the
  `owner`/`group` and confirm `sops.templates."octodns-env"` still
  renders (the template's own `owner` is what matters) and that
  `octodns-sync` still authenticates on the next tick.


**ACCEPTED 2026-09-15:** Minor; the sops-nix template is the consumer. Folded into the F11 follow-up rather than changed mid-branch.

### F16 — `octodns-sync`'s sandbox is the documented baseline only, on the one unit holding the zone-control credential

- **File:** `modules/services/octodns.nix:202-217`
- **Severity:** LOW
- **Confidence:** CONFIRMED (merged `serviceConfig` read via `nix eval
  --json .#nixosConfigurations.homelab.config.systemd.services.octodns-sync.serviceConfig`)
- **Axis:** hardening
- **Reachability:** whatever can achieve code execution inside the
  CPython process — a malicious or MITM'd response from
  `api.cloudflare.com` hitting a bug in `requests`/`urllib3`/
  `octodns_cloudflare`, or a compromised package anywhere in the
  `pkgs-unstable.octodns-providers.cloudflare` dependency closure, which
  runs in full every hour with the token in its environment. Not a
  first-step-free path; rated accordingly.
- **Rule:** conforms to `docs/hardening.md` "Custom `systemd.services`
  sandboxing" as written — flagged as below this repo's own practice
- **Finding:** The merged config is exactly, and only, the baseline the
  hardening doc lists: `NoNewPrivileges`, `ProtectSystem = "strict"`,
  `ProtectHome`, `ProtectKernel{Modules,Tunables,Logs}`,
  `ProtectControlGroups`, `RestrictNamespaces`, `PrivateTmp`, under
  `User`/`Group = octodns`. So it passes the doc.

  It does not match what this repo actually applies to comparable units.
  `modules/services/samba.nix:121-125`, `modules/services/beets.nix:299-303`
  and `modules/nixos/alloy.nix:36` add `ProtectClock`, `RestrictSUIDSGID`
  and `LockPersonality`; `hosts/vps/configuration.nix:871` uses
  `CapabilityBoundingSet = [ "" ]`; `modules/services/immich.nix:73`
  forces `PrivateDevices`. None of those are here, and neither are
  `RestrictAddressFamilies`, `SystemCallArchitectures`,
  `SystemCallFilter`, `ProtectHostname`, `ProtectProc`, `UMask` or
  `PrivateUsers`. This is the unit that holds the credential in F11 and
  reaches the internet every hour; it should be at the top of this
  repo's range, not the bottom of it. Pre-existing, not introduced here.
- **Fix risk:** Two specific traps. `RestrictAddressFamilies` must keep
  `AF_UNIX` alongside `AF_INET`/`AF_INET6` or name resolution through
  nscd/resolved breaks inside the unit. A `SystemCallFilter` that is too
  tight against CPython 3.14 (the pinned interpreter is
  `python3-3.14.7-env`) surfaces as a `SIGSYS` at the **next hourly
  tick**, not at build time — so verify with an on-demand `systemctl
  start octodns-sync` and read the journal, do not deploy and assume.


**FIXED 2026-09-15:** Brought octodns-sync up to the beets.nix baseline. systemd-analyze security --offline: 6.6 MEDIUM -> 3.5 OK.

### F17 — subdomain mail semantics, and the DMARC defaults that become load-bearing when `p` is tightened

- **File:** `modules/services/octodns.nix:41-48`, `:77-83`, `:84-122`
- **Severity:** INFO
- **Confidence:** CONFIRMED (rendered zone YAML read from the store;
  vps firewall confirmed via `nix eval
  .#nixosConfigurations.vps.config.networking.firewall` → TCP `[80, 443]`,
  UDP `[51820]`, no interface-scoped rules)
- **Axis:** hardening
- **Reachability:** n/a today; recorded because each item changes
  behaviour at the moment F1/F2 are revisited.
- **Rule:** n/a
- **Finding:** Answering review item 3 directly first: **adding the MX is
  a net reduction in the vps's mail-related surface, not an increase.**
  Before this commit the zone had no MX, so RFC 5321 §5.1 implicit-MX
  made the apex A/AAAA — the vps — the domain's nominal mail exchanger,
  and every sending MTA on the internet was directed at `137.184.45.18:25`.
  Port 25 is not open there (confirmed above), so those attempts were
  dropped; the MX now sends them to Google instead. Nothing new listens
  on either host, and nothing in the deploy path gained a network
  listener.

  Four residual details, none of them exposures today:

  - `jellyfin` is a `CNAME` to the apex, so an MX or TXT query for
    `jellyfin.skyseekerlabs.net` **follows the CNAME and returns the
    apex's MX and SPF**. Subdomains of this zone are not mail-inert; do
    not assume they are when reasoning about future records.
  - `minecraft` and `factorio` are A records with no MX, so implicit-MX
    still names the vps as their mail exchanger. Harmless (dropped at the
    firewall), but a null MX — `. 0`, RFC 7505 — at those names would
    state it rather than leaving it to a timeout, and would stop them
    being harvested as deliverable.
  - The DMARC record sets only `v`, `p` and `rua`. `sp` defaults to `p`
    (fine), `pct` defaults to 100 (so `none` → `reject` is an
    all-at-once jump with no ramp — use `pct=` to stage it), and
    `adkim`/`aspf` default to **relaxed**, meaning any subdomain of
    `skyseekerlabs.net` satisfies alignment. No `ruf` and no `fo`, so
    there will be no per-message forensic detail to diagnose a
    misalignment with once enforcement starts.
  - All four mail records use `ttl = 300`. That is what lets octoDNS's
    hourly revert take effect quickly (good, see F11), and equally what
    makes a hijack or a prune globally effective in five minutes
    (bad, see F10). It is a defensible choice but it is a choice; a
    longer TTL on the DKIM and MX records would give cached copies a
    grace period that a five-minute TTL does not.
- **Fix risk:** Adding null MX records is safe but must go in
  `zoneRecords` (G4). The DMARC parameters are a single-record edit —
  the risk is entirely in the `p`/`pct` values, not the syntax.


**ACCEPTED 2026-09-15:** Informational. Becomes load-bearing when the DMARC policy is tightened; noted for whoever does that.

## Checked and clean (security pass, 2026-09-15)

Reviewed the full branch diff against `master` — `modules/services/octodns.nix`
in its entirety (not just the changed lines), `docs/architecture.md`,
`hosts/homelab/README.md` — plus the surrounding blast radius:
`.sops.yaml`, `hosts/vps/configuration.nix` (firewall, Caddy vhosts),
`modules/nixos/health-alerts.nix`, `modules/nixos/auto-update.nix`,
`hosts/homelab/configuration.nix`'s `myAutoUpdate`/`myPushDeploy` block,
`docs/hardening.md`, `docs/procedures/secrets.md`, and the 2026-08-26
audit's L-09 and `F-P8-02` material.

Found correct and worth recording as checked:

- **No secret material is committed by this change.** All four values
  were examined and none is a credential: the DKIM string decodes to a
  2048-bit RSA *public* key (verified with `openssl pkey -pubin -text`,
  not assumed), the site-verification token is an opaque non-bearer
  string that is only meaningful when published under the domain, and
  SPF/MX/DMARC are public policy statements. No `secrets/*` file was
  read or decrypted during this review, per `docs/procedures/secrets.md`.
  The only qualification is F8, which is about discoverability rather
  than disclosure.
- **The rendered zone is correct.** Built the branch and read the
  generated zone YAML out of the store
  (`/nix/store/…-skyseekerlabs.net.yaml`): the `\;` escapes survive into
  the file as literal backslash-semicolon (G1 holds), SPF and the
  site-verification token render as two `values` under one apex TXT
  rather than two records (G2 holds), the DKIM value emits as a single
  unbroken plain scalar with no mid-value line folding, and the MX
  renders as `preference: 1` / `exchange: smtp.google.com.`.
- **`domainNoDot` used at `:81` before its `let` binding at `:141`** is
  fine — Nix `let` is recursive, and the same forward reference already
  existed at `:134`.
- **octoDNS rotation history is closed, not open.** The `F-P8-02`
  exposure of `cloudflare_octodns_token` was rotated 2026-08-27 and the
  old token deleted at Cloudflare 2026-08-28
  (`rotation-runbook.md:47,98`), so the historical-ciphertext path is
  genuinely shut. F11 is about the *current* token's widened impact, not
  a stale one.
- **A failing `octodns-sync` does page.** `myHealthAlerts` polls
  `systemctl --failed` every 15 minutes on homelab, so a sync that errors
  is caught. F10 is specifically about a sync that *succeeds* at doing
  the wrong thing.
- **The unattended-deploy chain is currently disarmed.** `scheduleEnable
  = false` on both `myAutoUpdate` and `myPushDeploy`
  (`hosts/homelab/configuration.nix:477,510`), so a commit on `master`
  does not reach homelab without a human running `auto-switch-now`. Worth
  noting for when the new pipeline re-arms it: `auto-switch-now` fetches
  and fast-forwards `origin/master` before switching, so at that point
  anything merged to master reaches authoritative DNS unreviewed within
  the hour (F10's adversarial half).
- **The docs changes in `db3a16d` are accurate.** The regenerated
  homelab inventory (grafana service/package/port 3000/`grafana_*`
  secrets, `dockremap` user) matches the merged config, and the
  `docs/architecture.md` corrections in F6 are correct. No security
  content in that commit.
- **Unit privilege is right.** `octodns-sync` runs as a dedicated
  `isSystemUser` with its own group and no supplementary groups, no
  capabilities, no login shell — conforming to the "dedicated service
  users" and "privilege on the unit, not the user" rules. F16 is about
  sandbox depth, not about privilege.
- **No firewall, capability, group-membership or container change** is
  introduced by this branch, and no new listener on either host.

_security subagent finished 2026-09-15 — F8-F17 above._

_security finished 2026-09-15T18:10:37Z (code 1fd137775f513d33) -- see Findings above._
