# Credential rotation runbook — `F-P8-02`

Step-by-step for the ten credentials proven exposed by `F-P8-02`, plus
one more (item 11) added later from `F-P8-19`/`F-P8-11`. Written
2026-08-27 to be worked through one at a time, in order.

**Why these ten:** three *retired* vps age keys were recipients of public
revisions of `secrets/secrets.yaml` that hold the **byte-identical,
currently-live** ciphertext for each. Proven by ciphertext comparison, no
decryption needed. The repo is public, so that ciphertext is permanently
downloadable and `updatekeys` cannot un-publish it. **Rotation at the
provider is the only thing that retracts anything.**

**Eight of the ten actually need rotating.** Items 3 and 4 — the two
Tailscale auth keys — were exposed but are **spent single-use enrollment
keys**, so the published plaintext has no remaining power. Exposure is
not the same as impact, and the action follows from impact. See those
items for the evidence. Worth checking each of the remaining eight the
same way rather than rotating on reflex: the point is to retract
something, not to complete a list.

That cuts both ways, which is what **item 11** is doing at the end. A
third Tailscale key — `tailscale_authkey_isoimage` — has *never been
used*, so the "already spent" argument that retires 3 and 4 does not
reach it. Same credential type, opposite conclusion, because impact is
what decides.

## How to use this

Each item lists **You** (things only you can do — providers, sops) and
**Me** (repo edits, deploys, verification). Every item follows
**add-new → verify → remove-old.** Never remove first.

Two standing rules, from `AGENTS.md` and `docs/procedures/secrets.md`:

- **I never edit or decrypt `secrets/*`.** Every `sops secrets/secrets.yaml`
  step is yours. I can tell you the key name and check the result
  indirectly (does the service work), never the value.
- **I never `switch` a host unprompted.** Each deploy step waits for you.

Editing a secret: `nix develop`, then `sops secrets/secrets.yaml`.

## Order and current state

| # | sops key | Risk | Status |
|---|---|---|---|
| 1 | `cloudflare_octodns_token` | low | **[x] 2026-08-27** — new token verified live; old token pending deletion by user |
| 2 | `homelab_discord_webhook` → `discord_webhook` | low | **[x] 2026-08-27** — rotated + consolidated; verified from homelab and vps |
| 3 | `tailscale_authkey_homelab` | low | **[x] not required** — spent single-use key, see item |
| 4 | `tailscale_authkey_torrent` | low | **[x] not required** — spent single-use key, see item |
| 5 | `wireguard_vps_homelab_psk` | med | **[x] 2026-08-27** — deployed and verified live; see item |
| 6 | `homelab_wireguard_private_key` | med | **[x] 2026-08-27** — deployed and verified live; see item |
| 7 | `vps_wireguard_private_key` | med | **[x] 2026-08-27** — deployed and verified live; see item |
| 8 | `homelab_vps_deploy_key` | **high** | **[x] 2026-08-28** — verified by authenticating with it; old key removed |
| 9 | `homelab_zrepl_key` | **high** | [ ] — **blocked**, see item |
| 10 | `homelab_backblaze_restic_password` | **highest** | [ ] |
| 11 | `tailscale_authkey_isoimage` | med | **[x] 2026-08-27** — key revoked at Tailscale, confirmed **never used**; ACL + repo done; sops key deletion pending |
| 12 | `factorio_token`, `factorio_game_password` | **high** | **[x] 2026-08-28** — rotated; container re-authenticated to factorio.com with the new token |

**Access safety note.** My SSH to homelab and vps is over **Tailscale**,
not over wg0, so items 5–7 cannot cut my access to either host. Item 8
touches the `vps-deploy` account, not `root@vps`, so it cannot either.

---

## 1 — `cloudflare_octodns_token`

DNS API token, consumed at `modules/services/octodns.nix:151` as
`CLOUDFLARE_TOKEN`. Controls the DNS records for `skyseekerlabs.net`;
exposure means someone else can repoint your domain.

- **You** — Cloudflare dashboard → My Profile → API Tokens → create a new
  token with the same scope as the current one (Zone:DNS:Edit on that
  zone). **Do not delete the old one yet.**
- **You** — `sops secrets/secrets.yaml`, replace `cloudflare_octodns_token`.
- **Me** — deploy homelab, then run `octodns-sync` and confirm it
  succeeds against Cloudflare with the new token.
- **You** — once verified, delete the old token in Cloudflare.

Rollback: put the old token back in sops and redeploy; the old token
still works until you delete it.

**Done 2026-08-27.** Deployed as homelab generation **347**; activation
logged `modifying secret: cloudflare_octodns_token` and `modifying
rendered secret: octodns-env`. `octodns-sync` then ran clean with the new
token:

```
CloudflareProvider[cloudflare] populate:   found 6 records, exists=True
CloudflareProvider[cloudflare] plan:   No changes
Manager sync:   0 total changes
```

`populate` succeeding is the proof — it reads the zone through the API,
so an invalid or under-scoped token fails there. `No changes` separately
confirms declared state still matches Cloudflare. Zero failed units after.
**Remaining: delete the old token in the Cloudflare dashboard.**

## 2 — `homelab_discord_webhook`

The alert sink for `myHealthAlerts` on all four hosts. Exposure means
someone can post into that channel — noise, not access. Worth doing
early precisely because it is low-stakes practice for the pattern.

- **You** — Discord → channel → Integrations → Webhooks → create a new
  webhook, copy the URL. Keep the old one for now.
- **You** — `sops secrets/secrets.yaml`, set `discord_webhook`.

  > **The value is not a bare URL.** `myHealthAlerts` runs
  > `curl -sS -K <file>`, and `-K` is *config-file* mode — deliberately,
  > so the URL never appears in argv or the process list. The value must
  > therefore be a curl config line, newline-terminated:
  >
  > ```
  > url = "https://discord.com/api/webhooks/XXXX/YYYY"
  > ```
  >
  > A bare `https://…` makes curl fail with `config file option 'https'
  > is unknown`, exit 2 — and **silently**, because `notify` only runs
  > when something is already wrong and sends curl's output to
  > `/dev/null`. This was hit for real on 2026-08-27 and caught only by
  > the verification step below. See the `TODO.md` entry on the alert
  > sink never being verified.
- **Me** — deploy homelab, run `health-check` by hand, confirm a message
  arrives in the channel.
- **You** — confirm you saw it, then delete the old webhook.

**Folded together with a consolidation, 2026-08-27.** There were two sops
keys holding the same URL — `homelab_discord_webhook` (read by homelab,
torrent *and* thinkpad) and `vps_discord_webhook` — so the host prefix
described nothing real. All four hosts now read one unprefixed
`discord_webhook`, and the rotation supplies its value, so the rename and
the rotation are a single edit.

**Delete the two old keys in the same sops edit.** An earlier draft of
this runbook said to keep them until the laptops were deployed. That was
wrong, for two independent reasons:

- **`secrets/secrets.yaml` is version-controlled and flake-pinned.** A
  running system pins an immutable *store copy* of it (verified on
  torrent: its manifest references
  `/nix/store/2m5yagb…-secrets.yaml`), so deleting a key from git cannot
  affect a host that has not rebuilt. And because git commits are atomic,
  every commit — including an older one rolled back to — carries matching
  references and keys.
- **Neither laptop reads the webhook today anyway.** `myHealthAlerts` was
  enabled on torrent and thinkpad in wave 1 but never deployed, so
  torrent's live manifest contains no discord entry at all. There is no
  host quietly posting to the old webhook.

The one real constraint is the *provider* side, not git: the old
**Discord** webhook should not be deleted until homelab and vps have been
redeployed and verified on the new one.

## 3 and 4 — `tailscale_authkey_homelab`, `tailscale_authkey_torrent`

Consumed at `modules/profiles/default.nix:94` as `authKeyFile`.

> ## NOT REQUIRED — resolved 2026-08-27
>
> **These two need no rotation.** Challenged by the user and the
> challenge holds: they are **single-use** enrollment keys that have
> already been consumed, so the exposed plaintext is a credential
> Tailscale will refuse.
>
> The design is internally consistent, which is what makes the argument
> solid rather than hopeful:
>
> - `modules/profiles/default.nix:94` documents each host as using its
>   own **non-reusable** pre-authorized key.
> - `hosts/homelab/configuration.nix:622` persists `/var/lib/tailscale`
>   through impermanence, with the comment *"node identity/state; without
>   this, a non-reusable authKeyFile…"*.
>
> So the key is used exactly once, at enrollment, and every later boot
> reuses the persisted node identity without touching it. Both hosts are
> enrolled. Tailscale auth keys additionally expire (90 days max), which
> is a second, independent reason these are dead.
>
> **This does not contradict `F-P8-02`.** The exposure it proved is
> real — the ciphertext for these two *was* readable by retired keys.
> What does not follow is the *action*: an exposed credential with no
> remaining power needs no rotation. Exposure confirmed, impact nil,
> rotation not required.
>
> **One free confirmation, if you want it:** the Tailscale console lists
> each key with its reusable flag and whether it has been used or
> expired. One glance settles it from the authoritative source rather
> than from this repo's own comments — which is worth doing precisely
> because two other comments in this repo turned out to be wrong during
> this audit.
>
> Optional tidying, not rotation: delete the spent keys from the console
> so the key list reflects reality.
>
> **Correction to an earlier draft of this runbook.** It said to mint
> replacements matching "the existing properties: **reusable**". That was
> wrong twice over — the keys are *non*-reusable, and following it would
> have replaced a spent single-use credential with a **standing** one,
> leaving the fleet worse off than doing nothing. If these are ever
> genuinely reissued (a rebuild, a new host), keep them **non-reusable,
> pre-authorized and tagged** so a leak grants one host's identity rather
> than open enrollment.

Consumed at `modules/profiles/default.nix:94` as `authKeyFile`. They are
used when a node first joins the tailnet; already-enrolled nodes are
unaffected. The risk exposure *would* pose is someone enrolling a node
into the tailnet, which §4.4 of the threat model treats as fleet access —
hence the check above rather than a shrug.

`tailscale_authkey_vps` is **not** in this list — it was already rotated
by `507bd11` during the reinstall.

## 5, 6, 7 — the WireGuard set (do together, one commit)

These three are interlocked and should be a single change:

- `wireguard_vps_homelab_psk` — **one shared value, identical on both
  ends** (`hosts/homelab/configuration.nix:571`,
  `hosts/vps/configuration.nix:358`).
- `homelab_wireguard_private_key` — homelab's identity. vps's peer stanza
  pins the matching **public** key at `hosts/vps/configuration.nix:357`
  (`GH5vw+bR1d28…`).
- `vps_wireguard_private_key` — vps's identity. homelab's peer stanza pins
  its public key at `hosts/homelab/configuration.nix:570`
  (`DIYtQyvp/KWN…`).

The tunnel carries the DNAT'd game traffic from vps to homelab, so
**expect a brief outage** while both ends are redeployed. It does not
affect my access to either host (Tailscale).

- **You** — generate two keypairs and a PSK:
  ```
  wg genkey | tee homelab.key | wg pubkey > homelab.pub
  wg genkey | tee vps.key     | wg pubkey > vps.pub
  wg genpsk > psk
  ```
  (Do this somewhere that is not the repo and not a snapshotted dataset —
  `/dev/shm` is a reasonable choice; see `F-P8-06` for why a stray key
  file on ZFS is its own problem.)
- **You** — `sops secrets/secrets.yaml`: set
  `homelab_wireguard_private_key` = contents of `homelab.key`,
  `vps_wireguard_private_key` = `vps.key`,
  `wireguard_vps_homelab_psk` = `psk`.
- **You** — give me the two **public** keys; they are not secret.
- **Me** — update both peer stanzas in one commit, build both hosts.
- **Me** — deploy **vps first, then homelab** (either order breaks the
  tunnel briefly; vps first means homelab's deploy is the one that
  restores it, and homelab is the easier host to reach if something is
  wrong).
- **Me** — verify: `wg show` on both ends shows a recent handshake, and
  the DNAT'd game port still reaches homelab.
- **You** — shred the temporary key files.


**Done 2026-08-27, and it took one unplanned step.** Deployed vps first,
then homelab, then verified against a baseline captured at 16:25:50
before either deploy.

Verified at 16:38:11, both ends:

```
homelab wg0  public key: d4dZJWJpbExfmmZivueaSAuRItMHUWOAsoZBYt9rHTc=
             peer:       ngxeCJV7bMtJQS1x93UhEuiWdLNXbCAsESrN4bcOrxk=
             latest handshake: 54 seconds ago
vps wg0      public key: ngxeCJV7bMtJQS1x93UhEuiWdLNXbCAsESrN4bcOrxk=
             peer:       d4dZJWJpbExfmmZivueaSAuRItMHUWOAsoZBYt9rHTc=
             latest handshake: 1 minute, 2 seconds ago
```

Both interface keys are new, each end pins the other's new public key, the
handshake is live in both directions, `25565/tcp` is reachable over the
tunnel from vps at ~27ms, and both hosts report zero failed units.

> ### The step that was not in the plan — read before doing item 8
>
> **homelab's deploy reported success and did not apply the key.**
> Activation logged `modifying secrets: homelab_wireguard_private_key,
> wireguard_vps_homelab_psk` and finished with zero failed units, and
> `wg show` still reported the *old* interface public key.
>
> `wireguard-wg0.service` is `Type=oneshot` with `RemainAfterExit=true`:
> it reads `privateKeyFile` once, when the link is created, and never
> re-runs. sops-nix rewrote the file underneath a live interface that had
> already read it. Its last start was the previous day.
>
> What *did* restart was the **peer** unit, whose name is derived from
> the peer's public key — which is exactly why the deploy looked applied.
> Had this rotation changed only the private key and not the peer's, there
> would have been no visible sign at all.
>
> vps had the same latent bug by a different route: its wg0 is a
> systemd-networkd `.netdev`, and networkd restarted only because the peer
> key changed and rewrote `40-wg0.netdev`. Rotating vps's own key alone
> would have left it equally stale. **It worked by luck, not by
> construction.**
>
> Fixed declaratively in `61f55cb` — `restartUnits` on the WireGuard
> secrets on both hosts, verified present in the sops manifest. Note the
> fix could not repair the state that exposed it: `restartUnits` fires
> when `sops-install-secrets` sees the secret *content* change, and that
> change had already happened in the prior activation. wg0 needed one
> `systemctl restart wireguard-wg0.service` to pick up a key it was
> already holding on disk.
>
> **The general lesson, which applies directly to items 8, 9 and 10:**
> a clean activation log is not evidence that a rotated secret reached the
> thing that consumes it. Only exercising the credential is. Item 8
> already says to verify by running `push-deploy-vps` rather than by
> reading the log — that instruction is now known to be load-bearing
> rather than cautious. For item 10, `restic-backblazeWeekly snapshots`
> plays the same role.


## 8 — `homelab_vps_deploy_key`

SSH key from homelab to `vps-deploy@vps`. Via the polkit grant this is
**root on vps** (§4.2). The public half is a literal string in
`hosts/vps/configuration.nix:297`, behind a forced command.

This one is genuinely safe to do incrementally, because
`authorizedKeys.keys` is a **list** — both keys can be valid at once.

- **You** — `ssh-keygen -t ed25519 -f /dev/shm/vps-deploy-new -C
  homelab-vps-deploy -N ""`.
- **You** — give me the **public** half.
- **Me** — add it as a *second* entry alongside the existing one, same
  `command="…",restrict` prefix. Deploy vps. Both keys now work.
- **You** — `sops secrets/secrets.yaml`, replace
  `homelab_vps_deploy_key` with the new **private** half.
- **Me** — deploy homelab, then **verify by actually using it**:
  `systemctl start push-deploy-vps` on homelab and watch it succeed.
  (Its timer is disabled, so nothing races this.)
- **Me** — once that works, remove the old key from the list, deploy vps.
- **You** — shred the temp files.

Rollback at any point: the old key is still authorized until the last
step.

**Done 2026-08-28 — but not the way this item says.**

> ### The prescribed verification does not work, and fails *green*
>
> `systemctl start push-deploy-vps` on homelab did not test anything. The
> unit has a branch guard, and `/etc/nixos` was on
> `worktree-worktree-security-audit-plan` at the time:
>
> ```
> push-deploy-vps-start[30560]: Not on master (on worktree-worktree-security-audit-plan), skipping this scheduled run.
> systemd[1]: push-deploy-vps.service: Deactivated successfully.
> ```
>
> `ActiveState=inactive Result=success ExecMainStatus=0`. The guard is
> correct and worth keeping — it exists so a half-finished branch on
> homelab cannot be pushed to vps, which is exactly the accident that
> reverted vps earlier in this audit. But it means the credential was
> never exercised, while systemd reported success. **This is `F-P7-09`'s
> skipped-deploy-looks-like-success shape, observed live**, and it is
> worth noting that the step designed to avoid trusting an activation log
> was itself trusting an exit code.
>
> ### What actually verified it
>
> Authenticating to the account directly, with only the rotated key
> offered:
>
> ```
> ssh -i /run/secrets/homelab_vps_deploy_key -o IdentitiesOnly=yes vps-deploy@vps "stat -c %Y /run/current-system"
> vps-deploy: rejected command: stat -c %Y /run/current-system
> ```
>
> That rejection **is** the proof. The message comes from the forced
> command dispatcher, so producing it required sshd to accept the key,
> start the dispatcher, and only then have the dispatcher refuse an
> argument outside its allowlist. A bad key fails earlier, at
> authentication, and never reaches the dispatcher.
>
> Fingerprints confirmed on both ends first: homelab's
> `/run/secrets/homelab_vps_deploy_key` is
> `SHA256:2CmD7PN6wnrrXfvGULoLNxiHw8pyb6Ty+Nj9ogaGoXo`, matching the first
> of the two entries then authorised on vps.
>
> **For items 9 and 10, prefer this shape**: use the credential against
> the thing that consumes it and read what comes back. An exit code from a
> wrapper unit can be success-because-skipped.

Old key `SHA256:HKcWtV9Oloo2z4XXma5P9jLJ7i7GyHwDmA6uTFu1+1c` removed from
`hosts/vps/configuration.nix` once the above passed.

## 9 — `homelab_zrepl_key` — **blocked, read first**

SSH key homelab uses to pull ZFS replication from torrent and thinkpad.
It is **root SSH to both laptops** (§4.5). The public half is
`modules/flake/vars.nix:14` (`zreplPullerKey`), consumed by
`hosts/{torrent,thinkpad}/configuration.nix` as
`clients.homelab.publicKey`.

**Prerequisite: torrent and thinkpad must be deployed.** They are
currently build-verified only and still run pre-audit configs. Unlike
item 8, `clients.homelab.publicKey` is a **single value, not a list**, so
there is no both-keys-valid window — the laptops must take the new public
key at the same time homelab takes the new private key. thinkpad also has
to be awake.

If replication does break, it fails safe: it is a *pull*, so it simply
retries. Nothing is lost, but the 336h staleness alarms will eventually
fire.

- **Decision needed from you:** deploy the laptops first, or defer this
  item. I recommend deferring 9 until the laptops are deployed, and doing
  10 before it.
- Then: **You** generate the keypair, put the private half in sops, give
  me the public half; **Me** update `vars.zreplPullerKey`, deploy both
  laptops **then** homelab, and verify a replication run completes.
- **You** — afterwards, delete `/tmp/homelab_zrepl_key` **on torrent**
  (`F-P7-02`), along with its `.pub`. **Delete second, never first** —
  and note that deleting it does not retract it: 61 snapshots on torrent
  hold it as of 2026-08-27, plus 69 in homelab's `zbackup` replica, and
  the count grows every five minutes. Rotation is what retracts it.

  > **Corrected 2026-08-27.** This step previously said "on homelab" and
  > cited `F-P8-06`. Both wrong: the file is on **torrent** (verified
  > live — still present, and readable inside
  > `/.zfs/snapshot/zrepl_20260827_231641_000/tmp/`), and `F-P8-06` is
  > the flat-ACL finding. It also said "plus the offsite copy"; restic
  > never backs up `zbackup/*`, so the replicas are not offsite. Anyone
  > following the old text would have shredded nothing and believed the
  > step done.

  The structural fix — so a key written to a normal temp path stops
  being unretractable — is the ZFS restructure logged in `TODO.md`
  (2026-08-27). It is **not** a prerequisite for this rotation.

## 10 — `homelab_backblaze_restic_password` — **the one that can lose data**

This is restic's `passwordFile` (`hosts/homelab/configuration.nix:182`) —
the password that unlocks the **repository's master key** for the offsite
copy of asset #1.

> **It is not the Backblaze application key.** That is a separate secret,
> `homelab_backblaze_rclone_config` (the `rcloneConfigFile`), and it is
> **not** among `F-P8-02`'s ten. An earlier version of the checklist
> conflated them.

> **Replacing the sops value alone does not rotate it — it locks you out
> of the repository.** Restic supports multiple key slots; you must add
> the new one *to the repo* before removing the old.

The `createWrapper = true` setting puts `restic-backblazeWeekly` on
homelab's PATH with the repo and rclone config already wired up.

- **Me** — first, confirm the current state works:
  `restic-backblazeWeekly snapshots` succeeds, and
  `restic-backblazeWeekly key list` shows the existing key id.
- **You** — on homelab: `restic-backblazeWeekly key add`. It prompts for
  a new password. The old password still works after this.
- **You** — `sops secrets/secrets.yaml`, replace
  `homelab_backblaze_restic_password` with the new password.
- **Me** — deploy homelab, then **verify**: `restic-backblazeWeekly
  snapshots` succeeds using only the new password from
  `/run/secrets`.
- **You** — only now: `restic-backblazeWeekly key list`, identify the old
  id, `restic-backblazeWeekly key remove <old-id>`.

Do **not** remove the old key before the verify step passes. If it fails,
the old password is still valid and you can put it back in sops.

---

## 11 — `tailscale_authkey_isoimage` — **revoke, do not replace**

Added 2026-08-27 at the user's request. Not one of `F-P8-02`'s ten; it
comes from `F-P8-19` and the orphan-key list in `F-P8-11`.

**Why this one is the opposite case to items 3 and 4.** Those were
dismissed because they are *spent* — single-use keys already consumed at
enrollment, so the published plaintext is a credential Tailscale will
refuse. This key has **never been used**. Nothing consumed it, so
nothing spent it, so whatever power it had it still has. "Exposed but
inert" and "exposed and never touched" look similar in a key list and
are opposites in impact. The user caught this; the reasoning that
retired 3 and 4 does not transfer here.

**What it would grant.** A tailnet auth key enrolls a *new node*. §4.4 of
the threat model treats enrolling into the tailnet as fleet access, and
the ACL is generous to `tag:isoimage` — `docs/tailscale-acl.json` gives
it `src` in all four grants and `dst` in the first. So an unused key plus
a live tag is adversary A5's "over-broad auth key" with the tag already
provisioned to reach everything. (`F-P8-19` counted nine occurrences; the
other three were in the two `ssh` rules, deleted on 2026-08-26 under
`F-P0-05`/`F-P8-12`. Six were live when this item was worked.)

**Confirmed at the console, 2026-08-27.** The user checked the Tailscale
key list before revoking: the key had **not been used**. That settles it
from the authoritative source rather than from this repo's own comments —
worth doing precisely because two other comments in this repo turned out
to be wrong during this audit.

Note what the console did *not* say, and do not fill the gap by
inference: it reported unused, not expired. Tailscale auth keys do expire
(90 days maximum) and this one predates that window comfortably, so it
was very likely refused on age alone — but "very likely" is a default
being assumed, not a fact observed. The key is revoked either way, which
is what makes the question academic rather than load-bearing.

### Revoke rather than mint a replacement

The instinct is to rotate — new key in, old key out. That is wrong here,
and it is worth being explicit about why, because the same shape of
mistake was already made once in this runbook (the item 3/4 draft that
said to mint **reusable** replacements).

**There is no consumer to keep working.** `isoimage`'s module list is
`[ hosts/isoimage/configuration.nix, copyparty-iso ]` — no
`profile-default`, so `services.tailscale.enable = false` and
`config.sops` is not even an option on that system. Nothing reads this
key; nothing ever did. Minting a replacement would create a *fresh,
live, standing* enrollment credential with no consumer — strictly worse
than the situation being fixed. The old key at least had age working
against it; a new one would have nothing working against it at all.

The design is right and deliberate: an ISO is a bootable artifact that
may be copied anywhere, and it should not carry a tailnet identity. The
defect is only that three places still describe a device the
architecture refuses to create.

- **[x] You** — Tailscale console → Settings → Keys. Checked the
  `isoimage` key: **not used**. **Revoked** 2026-08-27.
- **[ ] You** — same console → Access controls: paste the updated
  `docs/tailscale-acl.json` over the console policy. **The console is
  what enforces; the file is only a copy of it** (see `F-P8-07`), so
  until this paste happens the repo claims a restriction that is not
  live. The window is narrow and harmless here — the tag now grants
  access to a device that cannot exist and whose only enrollment key is
  revoked — but it is the wrong direction, and the fix is one paste.
- **[ ] You** — `sops secrets/secrets.yaml`, delete the
  `tailscale_authkey_isoimage` key outright. No replacement value. This
  is cleanup, not retraction: the ciphertext is permanently published in
  the repo's history and deleting it now removes nothing. The revocation
  above is the step that actually took the power away.
- **[x] Me** — removed the six live `tag:isoimage` occurrences from
  `docs/tailscale-acl.json` and added a header note saying why the tag is
  absent, so it does not get re-added; recorded in
  `hosts/isoimage/README.md` that isoimage is deliberately off-tailnet,
  with the reason and what it would take to change that deliberately.
- **[x] Me** — verified: `tailscale status` lists exactly the four real
  nodes (`homelab`, `vps`, `torrent`, `thinkpad`) plus `pixel-6a`, none
  carrying `tag:isoimage`, and my SSH to homelab and vps still works
  after the revocation. Since nothing consumed the key and no live node
  carries the tag, there was nothing that could break — this confirms
  that claim rather than hoping it.

**Order.** Revoke first, unusually. The standing **add-new → verify →
remove-old** rule protects a credential something depends on; nothing
depends on this one, and the whole point is retraction, so waiting only
extends the window.

Rollback: none needed, and none possible in the useful direction. If
`isoimage` is ever genuinely meant to join the tailnet, that is a design
change — give it `profile-default` and sops-nix and mint a key then,
**non-reusable, pre-authorized and tagged**, rather than reviving this
one.


---

## 12 — `factorio_token` + `factorio_game_password` — **proven disclosed**

Promoted 2026-08-28 from the "after the ten" list below, where it sat as
`F-P4-04` — a rotate-for-consistency item. It is not that. A security
review of the `/srv` permission fix proved the credentials are readable
**right now, by any local uid**, and the priority follows the evidence.

**The proof.** `/nix/state/.zfs` is mode **0777**. `snapdir=hidden` only
hides the directory from `readdir` — it does not block traversal by
path. **57 retained `zroot/local/state` snapshots** hold
`/srv/factorio/main/config/server-settings.json` at mode **0644**, which
carries the factorio.com account token and the game password in
plaintext. Verified live by reading it as uid 65534 (`nobody`) via
`setpriv`.

**Why that is reachable rather than theoretical.** `jellyfin` (uid 999)
is the one internet-reachable service on homelab — vps Caddy + Anubis →
wg0 → 8096 — and its pinned unit sets `ProtectSystem = true`, not
`"strict"`, so `/nix/state` is fully readable from inside its sandbox.
Any code execution in jellyfin reads these credentials.

**The permission fix does not retract this and must not be mistaken for
doing so.** `fix-srv-permissions-stop-three-systems-fighting-ov-2026-08-28.md`
tightened `/srv/factorio/main` to 0700, but that is a *forward* fix: the
snapshots already exist, they are replicated to `zbackup` on homelab, and
`zroot/local/state` is one of the two datasets restic pushes to
Backblaze — so unlike the laptop replicas discussed under `F-P7-02`,
**this one genuinely is offsite**. Deleting snapshots would not help
either, since the copies have already been readable for their whole
retention. Rotation at factorio.com is the only thing that retracts
anything.

- **You** — factorio.com → account settings. Regenerate the account
  token. Change the multiplayer game password while you are there; it is
  in the same file and had the same exposure.
- **You** — `sops secrets/secrets.yaml`, replace `factorio_token` and
  `factorio_game_password`. `factorio_username` is not a credential and
  does not need rotating.
- **Me** — deploy homelab, then **verify by exercising it**: the
  container's start script patches `server-settings.json` from the sops
  values on every start, so confirm `docker-factorio-main` comes up and
  the server authenticates to factorio.com rather than reading an
  activation log. Per items 5-7, a clean log proves nothing.
- **Me** — confirm the rewritten `server-settings.json` is inside a 0700
  directory this time, so the new values do not immediately start
  accumulating readable snapshot copies the way the old ones did.

Rollback: put the old values back in sops and redeploy — but note the old
token is what you are trying to invalidate, so rolling back re-exposes
you. Prefer fixing forward.

**Related, and deliberately not folded in here:** `/nix/state/.zfs` being
0777 is the *mechanism* behind this exposure and affects every secret
that has ever touched a persisted directory, not just factorio's. That
needs its own plan rather than a line in this item.

## After the ten

- Rotate the remaining live secrets too, for consistency — `F-P8-02`'s
  fix says "plus the rest of the live set", since ciphertext comparison
  proves only that these ten were exposed, not that others were not.
- The factorio account token is a separate exposure (`F-P4-04`): it sat
  in `/srv/factorio/new/config/server-settings.json`, is the **same**
  credential `factorio-main` uses, and is still in ZFS snapshots and
  restic backups taken before that directory was deleted. Rotate it at
  factorio.com and update sops.
- Then work `user-actions.md` §3 — dropping the nine orphan keys and
  restructuring `.sops.yaml` into per-path `creation_rules`.
