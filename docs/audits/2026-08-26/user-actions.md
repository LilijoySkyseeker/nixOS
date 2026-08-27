# Actions only the user can take

Standing checklist for the 2026-08-26 fleet-wide security audit. Every
item here is something an agent **cannot** do — because it needs a
credential, a provider console, a decryption key, physical access, or a
judgement call that is not an agent's to make.

Agents: keep this file current. When remediation work turns up a new
user-only action, add a row here rather than burying it in a finding or
in `RESUME.md` prose. Tick the box only when the user confirms it is
done — never on the agent's own inference.

Provenance is given as a finding ID so each row can be traced back to
the evidence without re-deriving it.

---

## 1. Do these first — free, reversible, no decision needed

- [ ] **`chmod 600 ~/.config/sops/age/keys.txt`** on the daily driver.
      Verified live at **0644**, i.e. world-readable. This file is the
      editing identity that decrypts all 31 secrets. Nothing depends on
      the loose mode. *(F-P8-03)*

- [ ] **`passwd -S lilijoy` on thinkpad** when it is next online. This is
      the one verification the audit still owes. Removing
      `initialPassword = "123456"` in `ba8cd4e` does **not** change an
      already-set password, so if thinkpad was ever installed with it,
      the published password is still live there. *(F-P1-03)*

- [ ] **Check GitHub branch protection** on the public repo. There is no
      CI anywhere and never has been — confirmed by a full-history scan
      — so branch protection is the *only* remaining control on a commit
      that becomes unattended root on four hosts. Not visible from
      inside the repo. *(D3, H1)*

- [ ] **Delete the `ssh` block in the Tailscale console.** `ba8cd4e`
      removed it from `docs/tailscale-acl.json`, but that file is only a
      reference copy — the live policy is console state and must be
      changed there too. *(F-P0-05, F-P8-12)*

---

## 2. Credential rotation — the C1 cluster

The repo is **public**, so every revision of `secrets/secrets.yaml` is
permanently downloadable by anyone, with no account and no trace.
Re-keying `.sops.yaml` does **nothing retroactively**: it re-encrypts
the current value to a new recipient set, while every prior ciphertext
remains published and decryptable by any key that was ever a recipient.
**Rotation at the provider is the only thing that helps.**

- [ ] **Rotate the ten credentials proven exposed by `F-P8-02`**, at
      each provider. That finding shows by ciphertext comparison — with
      no decryption — that three *retired* vps age keys were recipients
      of public revisions holding the byte-identical **currently-live**
      values for all ten:

  | # | Credential | Where to rotate |
  |---|---|---|
  | 1 | Backblaze application key | Backblaze console |
  | 2 | Cloudflare API token | Cloudflare dashboard |
  | 3 | Tailscale auth key(s) | Tailscale admin console |
  | 4 | WireGuard keypair — homelab | regenerate both ends together |
  | 5 | WireGuard keypair — vps | regenerate both ends together |
  | 6 | WireGuard preshared key | regenerate both ends together |
  | 7 | Discord webhook | Discord channel settings |
  | 8 | vps-deploy keypair | regenerate, update `authorized_keys` |
  | 9 | zrepl keypair | see the next item — order matters |
  | 10 | Samba `android-smb` password | reset via `smbpasswd` |

- [ ] **Rotate the zrepl key, and only then delete
      `/tmp/homelab_zrepl_key`.** It is the live private half of
      `vars.zreplPullerKey`, mode 0600, dated 2026-08-23, sitting on the
      ZFS root — so **40 snapshots** plus the offsite copy already
      contain it. Deleting the file does not retract it; rotation is
      what retracts it. Delete second, not first, or replication breaks
      before the new key is in place. *(F-P8-06)*

---

## 3. Secret-file edits — user-only by policy

`docs/procedures/secrets.md` reserves all decryption and editing of
`secrets/*` to the user. Agents must not run `sops` against these files
even when the change is mechanical, so each of these is listed here
rather than done in a branch.

- [ ] **Drop the nine orphan keys from `secrets/secrets.yaml`.** These
      are referenced by no `.nix` file in the repo — verified by exact
      key-name grep across every `.nix` file, and independently by the
      count: 31 keys, 22 consumed (18 declared statically plus the four
      `tailscale_authkey_<host>` declared dynamically at
      `modules/profiles/default.nix:112`), leaving nine. None is
      decrypted to `/run/secrets` on any host, so this is not a live
      exposure — it is dead ciphertext, permanently published, of
      credentials that in several cases are probably **still valid at
      the third party**. *(F-P8-11)*

  | Key | Shape | Why it is dead |
  |---|---|---|
  | `torrent_backup_push_key` | SSH private key | `backup-push.nix` was replaced by zrepl |
  | `thinkpad_backup_push_key` | SSH private key | same |
  | `cloudflare_tunnel_token_01` | Cloudflare Tunnel token | no cloudflared anywhere; superseded by the vps/Caddy edge |
  | `nextcloud_admin_pass` | password | no nextcloud anywhere |
  | `webdav_lilijoy` | password | no webdav service anywhere |
  | `winapps_password` | password | no winapps anywhere |
  | `open_weather_key` | API key | no consumer |
  | `restic` | unclear | `homelab_backblaze_restic_password` is the live one; this looks like its predecessor |
  | `tailscale_authkey_isoimage` | tailnet auth key | isoimage has `services.tailscale.enable = false` and no sops |

  Rotate-or-revoke each at its provider as well as deleting it. A
  Cloudflare Tunnel token and a Nextcloud admin password do not expire
  because you stopped using them, two of the nine are SSH private keys
  that may still sit in an `authorized_keys` this repo no longer
  manages, and an unused tailscale auth key that still exists in the
  console is exactly adversary A5's "over-broad auth key".

- [ ] **Drop the `vps_caddy_env` key from `secrets/secrets.yaml`.** The
      repo-side half is already done — the `sops.secrets.vps_caddy_env`
      declaration was removed from `hosts/vps/configuration.nix` in this
      branch. Removing the declaration first is the safe order: a key
      with no declaration is inert, whereas a declaration with no key
      fails activation. Its value is the literal empty string, which
      sops leaves **unencrypted**, so there is nothing to rotate.
      *(F-P2-13, F-P8-18)*

- [ ] **Restructure `.sops.yaml` into per-path `creation_rules`**, and
      attribute or retire the five unattributable recipients. Today one
      rule names all seven age recipients, so every host decrypts all 31
      secrets — thinkpad consumes 3 and can read 31; vps, the
      internet-facing box, consumes 7 and can read 31. *(F-P8-01,
      F-P8-05)*

- [ ] **Mint per-host Discord webhook keys for the laptops** — or
      decide the shared one is fine. Wave 1 item 1.9 enabled
      `myHealthAlerts` on torrent and thinkpad pointing at the existing
      `homelab_discord_webhook`, because adding a key is a user-only
      edit and, under the current flat recipient set, both laptops can
      already decrypt that value — so it grants no access they did not
      already have. It does add a name-level coupling the `.sops.yaml`
      restructure above will have to account for. Re-pointing is one
      line per host. *(F-P7-09, follows from F-P8-01)*

---

## 4. Decisions — D1–D8

None of these should be made by an agent. Recorded in `findings.md` §5;
repeated here so this file is the single place to work through.

| # | Decision | Bears on | Done? |
|---|---|---|---|
| D1 | Rotate which credentials, and how far back? | C1 / N2 — the answer is probably "all ten in `F-P8-02`" | [ ] |
| D2 | Accept unsigned unattended `origin/master`, or add signature verification? | H1; if accepting, write it into `docs/hardening.md` as an explicit accepted risk | [ ] |
| D3 | Check GitHub branch protection | H1; with no CI, the only remaining control on fleet root | [ ] |
| D4 | Buy immutability: append-only B2 key + Object Lock? | C3 — the single highest-value change for asset #1 | [ ] |
| D5 | FDE on the laptops? The plan exists on an unmerged branch | H7 | [ ] |
| D6 | Narrow the tailnet ACL, or accept all-or-nothing and document why? | §3 ACL cluster; either way, fix the vps `trustedInterfaces` half | [ ] |
| D7 | Intrusion detection on homelab, or accept? | H8 — evidence says the boundary is not what was assumed | [ ] |
| D8 | Is the recovery ISO's unauthenticated root-filesystem access intended? | H6 — needs a written justification either way | [ ] |

### Decisions blocking specific remediation work

- [ ] **D9 — should KDE Connect, Steam remote play and mDNS keep working
      on the LAN?** Blocks wave 2 item **2.9** (interface-scoping the
      desktop profile's host-wide firewall openings). If yes, they get
      scoped to a host-declared LAN interface; if no, they can go
      `tailscale0`-only or be dropped. Also needs a new per-host
      LAN-interface option — thinkpad declares no interface names at all
      — and thinkpad online to test. *(F-P1-04, F-P5-06)*

- [ ] **D10 — identify what opens UDP 10400/10401.** Evaluated on
      torrent but **not attributable to anything in this repo**. An
      unexplained open port is its own finding, and 2.9 should not scope
      a port set that contains one nobody can account for. *(wave 2
      §2.9 port inventory)*

- [ ] **D11 — should `flake-update-test` be allowed to auto-merge?**
      Commit `3f2c418` repaired a mechanism that had never once
      completed. It now can — and it auto-merges upstream input updates
      to `master` on **build success alone**, where `master` is
      unattended fleet root. Decide before deploying that commit rather
      than inheriting the behaviour. *(F-P7-10)*

---

## 5. Before deploying this branch

Nothing on this branch has ever been switched; everything is
build-verified only. Read `RESUME.md` §"Consequences to know before
deploying any of it" in full first. The three that bite silently:

- [ ] After deploying `5682087`, **check `tailscale status` on
      homelab.** If homelab's `mkForce "both"` is ever lost while the
      advertise flags remain, the exit node and the `192.168.1.0/24`
      subnet route stop working — with a perfectly clean build. This
      failure is connectivity-visible, never build-visible.

- [ ] Decide **D11** above before deploying `3f2c418`.

- [ ] Know that `40255bd` **fails closed**: if GitHub rotates the pinned
      host key, unattended deploys stop until it is updated. That is the
      intended trade, and it is why enabling health alerts on the
      laptops (wave 1 item 1.9) mattered — until that landed, nothing
      anywhere would have told you deploys had stopped.
