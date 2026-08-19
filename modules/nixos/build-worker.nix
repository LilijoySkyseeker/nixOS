{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myBuildWorker;
in
{
  options.myBuildWorker = {
    enable = lib.mkEnableOption "accept distributed Nix builds submitted by other tailnet hosts";

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        Public half of this worker's shared builder keypair (see
        `.claude/plans/quirky-herding-teapot.md` — one keypair per
        worker, shared by every submitter authorized to use it, not one
        per submitter->worker edge). No forced command is attached:
        unlike `vps-deploy` (hosts/vps/configuration.nix), the SSH
        substituter/build protocol is a full bidirectional nix-store
        protocol, not a small fixed set of operations, so a
        ForceCommand allowlist isn't viable here. The security boundary
        is the dedicated unprivileged nix-builder account plus scoping
        `nix.settings.trusted-users` to exactly that account — and,
        more fundamentally, only ever pointing this at hosts you fully
        control. `trusted-users` membership is effectively
        passwordless-root-equivalent on this host's Nix daemon *and*
        lets this account feed fabricated build results back to
        whichever submitter requested the build, so the unprivileged
        account protects this worker (it isn't root here) but is NOT a
        sandbox against a compromised submitter, or against this
        account attacking a submitter. That only holds because every
        submitter here is also a host you control on your own tailnet.
      '';
    };

    acGated = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Only accept builder connections while on AC power, dropping out
        of rotation on battery. Intended for thinkpad. Implemented via
        `ac-power.target`/`battery-power.target` systemd targets flipped
        by a udev rule on the `power_supply` subsystem (event-driven,
        not polled) — a oneshot service bound to `ac-power.target`
        installs/removes nix-builder's authorized_keys file accordingly.
        Submitters simply see a connection refusal while this host is on
        battery, the same as any transient builder outage.
      '';
    };

    acPowerSupplyName = lib.mkOption {
      type = lib.types.str;
      default = "AC";
      description = ''
        Name of the /sys/class/power_supply/<name> Mains node to watch
        for acGated hosts (commonly "AC", "AC0", or "ADP1" — varies by
        hardware). Confirm the real value via `ls /sys/class/power_supply/`
        on the target host before relying on this default.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.nix-builder = { };
    users.users.nix-builder = {
      isSystemUser = true;
      group = "nix-builder";
      # sshd needs a real shell to exec commands through (see the
      # vps-deploy nologin gotcha documented in
      # hosts/vps/configuration.nix) — this account has no forced
      # command though, so it also just needs a normal login shell for
      # the nix-daemon SSH protocol to run through.
      shell = "${pkgs.bash}/bin/bash";
      home = "/var/lib/nix-builder";
      createHome = true;
      # Static authorized_keys when not power-gated; acGated hosts leave
      # this empty and let the power-gate service manage
      # ~/.ssh/authorized_keys directly instead, so the key is only
      # present while genuinely reachable.
      openssh.authorizedKeys.keys = lib.mkIf (!cfg.acGated) cfg.authorizedKeys;
    };

    # Required for nix-daemon to accept builds submitted by nix-builder
    # without additional signing friction — same rationale as
    # hosts/vps/configuration.nix's `trusted-users = [ "vps-deploy" ]`.
    nix.settings.trusted-users = [ "nix-builder" ];

    # thinkpad/torrent don't currently run sshd at all; homelab/vps
    # already do with their own explicit hardening. mkDefault here so
    # hosts with no existing services.openssh get a tailnet-only
    # baseline, while hosts that already configure it more specifically
    # keep their own settings untouched.
    services.openssh = {
      enable = lib.mkDefault true;
      openFirewall = lib.mkDefault false;
      allowSFTP = lib.mkDefault false;
      settings.PasswordAuthentication = lib.mkDefault false;
      settings.KbdInteractiveAuthentication = lib.mkDefault false;
      extraConfig = lib.mkDefault ''
        PermitRootLogin = prohibit-password
        AllowTcpForwarding no
        X11Forwarding no
        AllowAgentForwarding no
        AllowStreamLocalForwarding no
        AuthenticationMethods publickey
        PermitTunnel no
      '';
    };
    # additive only — never removes an existing firewall rule, just
    # trusts the tailnet interface (mirrors hosts/vps/configuration.nix).
    networking.firewall.trustedInterfaces = [ "tailscale0" ];

    systemd.targets = lib.mkIf cfg.acGated {
      ac-power = {
        description = "Running on AC power";
      };
      battery-power = {
        description = "Running on battery power";
      };
    };

    services.udev.extraRules = lib.mkIf cfg.acGated ''
      SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="${pkgs.systemd}/bin/systemctl start ac-power.target", RUN+="${pkgs.systemd}/bin/systemctl stop battery-power.target"
      SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="${pkgs.systemd}/bin/systemctl stop ac-power.target", RUN+="${pkgs.systemd}/bin/systemctl start battery-power.target"
    '';

    systemd.services.nix-builder-power-gate = lib.mkIf cfg.acGated {
      description = "Gate nix-builder SSH access to AC power only";
      bindsTo = [ "ac-power.target" ];
      partOf = [ "ac-power.target" ];
      path = with pkgs; [ coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "nix-builder-power-gate-start" ''
          set -euo pipefail
          install -Dm600 ${builtins.toFile "nix-builder-authorized-keys" (lib.concatStringsSep "\n" cfg.authorizedKeys)} /var/lib/nix-builder/.ssh/authorized_keys
          chown nix-builder:nix-builder /var/lib/nix-builder/.ssh/authorized_keys
        '';
        ExecStop = pkgs.writeShellScript "nix-builder-power-gate-stop" ''
          set -euo pipefail
          rm -f /var/lib/nix-builder/.ssh/authorized_keys
        '';
      };
    };

    # Seeds initial target state at boot (udev only fires on subsequent
    # transitions/coldplug events) — without this, a host booted while
    # already on AC would never reach ac-power.target until the next
    # plug/unplug edge.
    systemd.services.nix-builder-power-seed = lib.mkIf cfg.acGated {
      description = "Seed ac-power.target/battery-power.target from current power state at boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      path = with pkgs; [ coreutils systemd ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        if [ "$(cat /sys/class/power_supply/${cfg.acPowerSupplyName}/online 2>/dev/null || echo 0)" = "1" ]; then
          systemctl start ac-power.target
        else
          systemctl start battery-power.target
        fi
      '';
    };
  };
}
