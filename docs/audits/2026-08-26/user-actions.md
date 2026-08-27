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

- [x] **`chmod 600 ~/.config/sops/age/keys.txt`** on the daily driver.
      Was **0644**, i.e. world-readable. This file is the editing
      identity that decrypts all 31 secrets. **Done 2026-08-27 (user).**
      *(F-P8-03)*

- [x] **`passwd -S lilijoy` on thinkpad.** **Resolved 2026-08-27 — the
      user confirms the password is not the published one.** Removing
      `initialPassword = "123456"` in `ba8cd4e` does not change an
      already-set password, so this was the one verification the audit
      still owed; `F-P1-03` is now closed on the live side as well as
      the config side. *(F-P1-03)*

- [ ] **Test the Wooting keyboard after deploying `d6236cb`.** That
      commit removed `users.users.lilijoy.extraGroups = [ "input" ]` from
      `modules/nixos/wooting.nix`. The reasoning says it should be a
      no-op: `hardware.wooting.enable`'s only access mechanism is
      `services.udev.packages = [ pkgs.wooting-udev-rules ]`, and every
      rule in that package is `TAG+="uaccess"`, which grants the
      logged-in user access through a logind ACL rather than a group —
      checked against the pinned nixpkgs module and the rules package
      itself. But that is source-reading, not a keyboard.

      Worth a minute after the first switch: confirm the keyboard still
      types, and open **wootility** and confirm it still detects the
      device and can read/write profiles — the analog/rapid-trigger
      configuration path is the part that talks to `hidraw` directly and
      so the part most likely to notice a permissions change. If it
      breaks, `getfacl` on the relevant `/dev/hidraw*` will say whether
      the uaccess ACL is present; the fix would be a `uaccess`-scoped
      grant, not putting `input` back. *(F-P1-01, F-P8-09)*

- [x] **Check GitHub branch protection** on the public repo. **Done
      2026-08-27.** Checked: `master` had **no branch protection and no
      rulesets at all**. There are no deploy keys and the user is the
      sole collaborator, and repo-level auto-merge is off. A ruleset
      named `master` now targets the default branch with **restrict
      deletions** + **block force pushes**, enforcement `active`, and an
      empty bypass list (`current_user_can_bypass: never`).
      **Signed commits deliberately not enabled** — that is D2, and it
      needs a signing key set up first. *(D3, H1)*

- [x] **Delete `/srv/factorio/new` on homelab.** **Done 2026-08-27**, on
      the user's explicit authorisation — the one live-host mutation this
      audit has made. Sequence: stopped `docker-factorio-new.service`
      (container removed, `factorio-main` untouched and still up),
      deleted the contents, stopped `srv-factorio-new.mount`, then
      `rmdir`'d both `/srv/factorio/new` and its persist source
      `/nix/state/srv/factorio/new`. Verified after: only `main` remains
      in both paths, `docker-factorio-main.service` and
      `srv-factorio-main.mount` still active. `systemctl reset-failed`
      cleared the stopped unit so it does not sit in `systemctl --failed`
      masking real failures.

      **The world was provably unused**, which is what made this safe:
      the only save was a single `_autosave1.zip` dated 2026-08-21 11:39
      — deployment day — with `player-data.json` from the same minute and
      nothing since. Factorio autosaves continuously while a player is
      connected, so one autosave means nobody ever joined.

      **The credential exposure is not retracted by this.**
      `config/server-settings.json` held the factorio.com account token
      and game password, and those are still in every ZFS snapshot and
      restic backup taken while the directory existed; they age out on
      normal retention. It is the *same* credential
      `factorio-main` still uses, so treat it as exposed until rotated at
      factorio.com — and rotating means updating sops too. *(F-P4-04)*

- [ ] **After deploying, confirm the deploy path actually recovers.**
      As of 2026-08-27 **the fleet is not deploying at all**: both
      `auto-switch.service` and `push-deploy-vps.service` on homelab have
      failed on every run since 2026-08-25 with `could not lock config
      file /root/.config/git/config: Read-only file system`, because the
      guards wrote to a path home-manager owns as a store symlink. Fixed
      on this branch and covered by `tests/deploy-guards.nix`, but the
      fix only takes effect once the branch is deployed — and it cannot
      deploy itself, precisely because the deploy path is what is broken.
      **The first switch has to be run by hand.**

      Afterwards, on homelab: `systemctl start auto-switch.service` and
      check it reaches its guards instead of dying on line one, and
      confirm `systemctl --failed` is empty. Note the guards
      intentionally `exit 0` when they skip, so "no failure" is not the
      same as "it deployed" — check
      `stat -c %y /nix/var/nix/profiles/system` to see whether a switch
      actually happened. *(F-P7-09)*

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

**Where an answer goes.** Deciding *toward a fix* turns the row into
work — `TODO.md` or a branch. Deciding *toward acceptance* means writing
it into [`docs/accepted-risks.md`](../../accepted-risks.md) §1 with its
reasoning, and striking it from that file's §2 pending table; an
acceptance that only exists in a commit message will be re-litigated by
the next audit. Phase 4 pre-listed all fourteen in §2 with the exact
risk each one would be accepting, so the write-up is mostly already
drafted.

| # | Decision | Bears on | Done? |
|---|---|---|---|
| D1 | Rotate which credentials, and how far back? | C1 / N2 — the answer is probably "all ten in `F-P8-02`" | [ ] |
| D2 | Accept unsigned unattended `origin/master`, or add signature verification? | H1; if accepting, write it into [`docs/accepted-risks.md`](../../accepted-risks.md) §1 as AR-7 | [ ] |
| D3 | Check GitHub branch protection | H1; with no CI, the only remaining control on fleet root | [ ] |
| D4 | Buy immutability: append-only B2 key + Object Lock? | C3 — the single highest-value change for asset #1 | [ ] |
| D5 | FDE on the laptops? The plan exists on an unmerged branch | H7 | [ ] |
| D6 | Narrow the tailnet ACL, or accept all-or-nothing and document why? | §3 ACL cluster; either way, fix the vps `trustedInterfaces` half | [ ] |
| D7 | Intrusion detection on homelab, or accept? | H8 — evidence says the boundary is not what was assumed | [ ] |
| D8 | Is the recovery ISO's unauthenticated root-filesystem access intended? | H6 — needs a written justification either way | [ ] |

### Decisions blocking specific remediation work

- [~] **D9 — should KDE Connect, Steam remote play and mDNS keep working
      on the LAN?** Blocks wave 2 item **2.9** (interface-scoping the
      desktop profile's host-wide firewall openings).

      **ANSWERED AND DONE 2026-08-27** — wave 2 item 2.9 is complete,
      and it turned out much smaller than scoped, because two of the four
      port groups were removed rather than narrowed. No per-host
      LAN-interface option was needed after all: nothing is left that
      wants LAN scoping.

      **ANSWERED 2026-08-27:**
      - **KDE Connect → TAILNET ONLY.** TCP/UDP 1714-1764 now carry
        `-i tailscale0` in the rendered firewall. The nixpkgs module
        opens the range unconditionally with no `openFirewall` toggle
        (checked against the pinned source), so this needed `mkForce` on
        the host-wide lists plus a re-add under
        `networking.firewall.interfaces.tailscale0`.
      - **Steam remote play → DISABLED.** `remotePlay.openFirewall`
        dropped outright, closing TCP 27036/27037, UDP 27031-27035 **and
        UDP 10400/10401 — which is D10's mystery port pair**. Steam
        itself stays enabled; only the in-home-streaming listener goes.
      - **mDNS → REMOVED (option c), 2026-08-27.** It was
        `services.avahi.openFirewall` (`PC.nix:275-279`), there for one
        thing: discovering the network printer. The user chose to drop
        avahi entirely and give the printer a static address instead — a
        static address needs no discovery protocol at all, which is
        strictly less surface than firewalling UDP 5353. Verified in the
        built closure: no avahi units, and **no occurrence of `5353`
        anywhere in torrent's system closure**.

        This is bound up with a hardware change: the USB Brother is gone
        and its replacement is a networked **MFC-L2740DW** with no static
        address yet, so `brlaser` was dead config too. `services.printing`
        is now a deliberate placeholder (`drivers = [ ]`, no printer
        declared) and the setup is tracked as its own `TODO.md` entry.

      Built on torrent and thinkpad and verified in the *rendered*
      firewall script, which is the only check that means anything here:
      the sole remaining port range is `1714:1764`, and both its rules
      end in `-i tailscale0`. **Not switched.** *(F-P1-04, F-P5-06)*

- [x] **D10 — identify what opens UDP 10400/10401.** **ANSWERED AND
      CLOSED 2026-08-27. They were Steam's.**

      `programs.steam.remotePlay.openFirewall` opens them, in the pinned
      nixpkgs `nixos/modules/programs/steam.nix`:

      ```nix
      (lib.mkIf cfg.remotePlay.openFirewall {
        allowedTCPPorts = [ 27036 27037 ];
        allowedUDPPorts = [ 10400 10401 ];
        allowedUDPPortRanges = [ { from = 27031; to = 27035; } ];
      })
      ```

      Established by evaluating
      `options.networking.firewall.allowedUDPPorts.definitionsWithLocations`,
      which attributes each entry to its defining nixpkgs file — not by
      grepping, which is why the audit's own search failed: the ports
      appear nowhere as literals in this repo.

      **Why it went unattributed for so long is worth keeping.** The
      audit's wave-2 port inventory listed TCP 27036/27037 and UDP
      10400/10401 as *separate* line items and never connected them, so a
      single `openFirewall = true` read as two unrelated findings — one
      understood, one mysterious. The lesson is to attribute a port to the
      **option that opens it**, not to the port number.

      **Already closed** by the same change that answered D9: dropping
      `remotePlay.openFirewall` removes all of it. Verified in the
      rendered firewall script — no `10400`, `10401` or `2703x` rule
      remains. *(D9, F-P1-04, F-P5-06)*

- [ ] **D13 — should LAN clients reach the game servers directly?**
      Blocks wave 2 item **2.1**. The four published game ports on
      homelab bypass the NixOS firewall completely (docker DNATs before
      the routing decision, so nothing traverses `nixos-fw`), which means
      anything on `192.168.1.0/24` — a guest phone, an IoT device, a
      compromised laptop — can reach them, and does so without passing
      vps's rate limiter, the only control in front of these servers.

      Both candidate fixes (binding the publishes to an address, or a
      `DOCKER-USER` allowlist) close that LAN path.

      **ANSWERED 2026-08-27 — no.** The user never connects from a LAN
      machine: game access is over the tailnet, or over the public
      address through vps. So no LAN-scoped exception is needed and the
      clean fix applies.

      **FIXED the same day — wave 2 item 2.1 is done.** A new
      `myDockerPublishGuard` module filters the four ports in FORWARD via
      DOCKER-USER, allowing only `wg0` (public players, DNAT'd in by vps)
      and `tailscale0`. VM-tested with a real container and a real client
      in both directions, nine subtests. **Not switched**, so the LAN
      path is still open on the live host until this is deployed.

      **After deploying, check from three positions**, per the finding:
      a LAN host (should go from working to **refused**), a tailnet host
      (unchanged), and the public path through vps (unchanged). If public
      play breaks, the guard is the first thing to look at — but note it
      fails *loudly*, since a wrong interface list refuses connections
      rather than silently allowing them. *(F-P4-02, F-P3-04)*

      Already done and needing no decision: the load-bearing dependency
      is now written down in `hosts/homelab/configuration.nix` — the only
      thing keeping these ports off homelab's real public IPv6 is
      docker's IPv6-off default, and nothing had recorded that.

- [x] **D14 — pin the game container images by digest?** **ANSWERED
      2026-08-27 — no, auto-update is kept deliberately, and the risk is
      written up as an accepted risk** in
      [`docs/accepted-risks.md`](../../accepted-risks.md) AR-7.

      The user's goal is that the server tracks the newest *stable*
      Minecraft release automatically and that mods stay current, with
      `alpha` retained because mod development lags game releases. That
      is availability over supply-chain tightness, chosen knowingly.

      What changed while accepting it: the game version no longer leads
      the mod set. `VERSION = "LATEST"` is replaced by upstream's
      `VERSION_FROM_MODRINTH_PROJECTS = "true"`, which resolves the
      newest Minecraft version **every** listed project supports and
      **fails closed** if it cannot. The version-type variable also moved
      off the legacy `MODRINTH_ALLOWED_VERSION_TYPE` name to
      `MODRINTH_PROJECTS_DEFAULT_VERSION_TYPE` — the mod downloader
      accepts both, but the version resolver reads only the new name, so
      the legacy spelling would have had mods resolving at `alpha` while
      the game version resolved at `release`.

      Verified in the evaluated unit on homelab, not just by build.
      Still available if wanted later, without giving up auto-update:
      the `?` optional-project suffix (excludes a lagging mod from the
      version calculation instead of letting it hold the server back),
      and per-project version pins. *(F-P4-03, F-P4-13)*

- [ ] **D12 — should the NFS shares be `noexec` too?** Low stakes, and
      only worth answering if the answer is easy. Wave 2 item 2.5 added
      `nosuid` and `nodev` to `/home/lilijoy/storage{,-bulk}` and
      declined `noexec` on `F-P6-05`'s reasoning that a media share will
      eventually have something run off it. A scan found nothing that is
      actually a program there today, so if you never intend to run
      anything from those shares, `noexec` is one word and closes the
      last execution path from a homelab-controlled filesystem onto both
      laptops. *(F-P6-05)*

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
