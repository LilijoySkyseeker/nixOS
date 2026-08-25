# Connecting to remote hosts

How SSH access is set up across the fleet, and how to actually reach
each host.

## Key model

There's one shared set of admin public keys —
`flake.vars.publicSshKeys` in `modules/flake/vars.nix` — installed as
`users.users.root.openssh.authorizedKeys.keys` on every host that
accepts interactive admin SSH (`homelab`, `vps`, `isoimage`). Currently
three keys: the thinkpad's, torrent's, and a hardware YubIKey
(`sk-ssh-ed25519@openssh.com`, resident/FIDO2). Adding a new admin
machine means appending its public key to that one list in
`modules/flake/vars.nix` — it propagates to every host on next deploy
(each host reads it via `config.flake.vars`, passed through as the
`vars` `specialArg` — see `modules/flake/hosts.nix`), there's no
per-host key list to maintain separately.

Every host disables `PasswordAuthentication` — key-only, no exceptions.
`PermitRootLogin` differs by host, though: `homelab`, `vps`, and
`isoimage` set `prohibit-password` (interactive root login with the
shared admin keys above); `torrent` and `thinkpad` set
`"forced-commands-only"` instead, so **no interactive root login exists
on either of those two, from anywhere** — see "Reaching each host"
below for what that means in practice. Root login itself is intentional
where it's allowed (not a hardening gap): these are single-admin personal
machines, not shared multi-user servers, so there's no separate non-root
account to sudo from.

## Reaching each host

- **`thinkpad` / `torrent`** — desktops. **No interactive root SSH to
  either, from anywhere, by design**: both set `services.openssh.settings
  .PermitRootLogin = "forced-commands-only"` (see each host's
  `configuration.nix`), so the admin key list isn't even installed as a
  general-login `authorizedKeys` there — only forced-command principals
  (e.g. `myZrepl`'s pull key) can connect. Reaching one of these means
  being logged into it directly (physically, or as this machine's own
  session — `torrent` in particular is this repo's usual daily-driver
  machine; run `hostname` if a session isn't sure whether it already *is*
  torrent before trying to SSH to it). `thinkpad` is also a laptop that's
  frequently just offline/asleep — check `tailscale status` before
  assuming a connection failure means something else.
- **`homelab`** — LAN or Tailscale, `ssh root@homelab` (or its Tailscale
  name) works once Tailscale is up — confirmed reachable this way.
- **`vps`** — **Tailscale only.** Port 22 is never opened on the
  public interface (`services.openssh.openFirewall = false`,
  restricted to `networking.firewall.trustedInterfaces` covering
  `tailscale0`) — confirmed live that an external non-tailscale IP
  can't even reach sshd's pre-auth stage. `ssh root@vps` (or its
  Tailscale name) only works if you're on the tailnet. There is no
  public-IP SSH fallback by design; if Tailscale itself is broken, the
  DigitalOcean web console is the recovery path, not a public SSH
  port.
- **`isoimage`** — not a persistent host; it's a bootable ISO. Same
  admin key list is baked in for recovery/rescue use when booted.

## The vps's second SSH identity: `vps-deploy`

Beyond the admin keys above, `vps` has one more SSH principal:
`vps-deploy`, a dedicated unprivileged system account used only by
`homelab`'s automated push-deploy (`myPushDeploy`) to build-and-push
this host's config. Worth knowing about even though you won't
generally use it directly:

- Its key is locked to a forced command
  (`command="...",restrict` in `authorizedKeys`) that allows exactly
  three things: copying a built closure in, activating it via
  `switch-to-configuration switch`, and rebooting if the switch
  changed the kernel. The forced-command allowlist is the actual
  security boundary, not the account's polkit grant (which is
  necessarily coarse — see `hosts/vps/configuration.nix`'s comment on
  why).
- It can never get an interactive shell, regardless of what shell is
  configured for it — the SSH key itself can't request anything other
  than the forced command.
- The private half lives in `sops.secrets.homelab_vps_deploy_key` on
  `homelab`, not anywhere a human types it in.

## Fresh-install chicken-and-egg

A brand-new host can't be reached over Tailscale until sops decrypts
its Tailscale auth key, and sops can't decrypt anything until the
host's age key (usually derived from its SSH host key) is already
registered in `.sops.yaml` — which normally doesn't exist until
*after* install. See `docs/procedures/new-host.md` and
`hosts/vps/README.md` step 1 for how this is broken: pre-generate the
host's SSH key locally, register its age key in `.sops.yaml` and run
`sops updatekeys secrets/secrets.yaml` *before* the install, then pass
the pre-generated key in via `nixos-anywhere --extra-files` so it's in
place before sshd/sops ever run on the new box.
