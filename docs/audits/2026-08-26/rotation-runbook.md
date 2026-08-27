# Credential rotation runbook — `F-P8-02`

Step-by-step for the ten credentials proven exposed by `F-P8-02`. Written
2026-08-27 to be worked through one at a time, in order.

**Why these ten:** three *retired* vps age keys were recipients of public
revisions of `secrets/secrets.yaml` that hold the **byte-identical,
currently-live** ciphertext for each. Proven by ciphertext comparison, no
decryption needed. The repo is public, so that ciphertext is permanently
downloadable and `updatekeys` cannot un-publish it. **Rotation at the
provider is the only thing that retracts anything.**

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
| 2 | `homelab_discord_webhook` | low | [ ] |
| 3 | `tailscale_authkey_homelab` | low | [ ] |
| 4 | `tailscale_authkey_torrent` | low | [ ] |
| 5 | `wireguard_vps_homelab_psk` | med | [ ] |
| 6 | `homelab_wireguard_private_key` | med | [ ] |
| 7 | `vps_wireguard_private_key` | med | [ ] |
| 8 | `homelab_vps_deploy_key` | **high** | [ ] |
| 9 | `homelab_zrepl_key` | **high** | [ ] — **blocked**, see item |
| 10 | `homelab_backblaze_restic_password` | **highest** | [ ] |

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
- **You** — `sops secrets/secrets.yaml`, replace `homelab_discord_webhook`.
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

**These are *enrollment* keys.** They are used when a node first joins
the tailnet. Already-enrolled nodes are unaffected by revoking one — so
these are much lower-stakes than they look. The risk of exposure is that
someone else enrolls a node into your tailnet, which §4.4 of the threat
model treats as fleet access.

- **You** — Tailscale admin console → Settings → Keys → generate a new
  auth key for each. Match the existing properties: **reusable**,
  **pre-authorized**, and **tagged** (the profile comment says the key is
  already tagged; keep the same tag so ACLs still apply).
- **You** — `sops secrets/secrets.yaml`, replace both keys.
- **Me** — deploy homelab; confirm `tailscale status` still healthy.
  (No re-enrollment happens, so this mostly proves nothing broke.)
- **You** — revoke the old keys in the console.

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
- **You** — afterwards, delete `/tmp/homelab_zrepl_key` on homelab
  (`F-P8-06`). **Delete second, never first** — and note that deleting it
  does not retract it, since 40 ZFS snapshots plus the offsite copy
  already contain it. Rotation is what retracts it.

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

## After all ten

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
