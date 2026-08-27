{ ... }:
{
  flake.modules.nixos."docker-publish-guard" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myDockerPublishGuard;

      # One `-p` publish is one DNAT rule in nat/PREROUTING, applied
      # *before* the routing decision, so the packet is forwarded and
      # never reaches INPUT where nixos-fw lives. Filtering it therefore
      # has to happen in FORWARD, and DOCKER-USER is the one chain in
      # FORWARD that docker guarantees it will not rewrite: it creates
      # the chain and the jump to it, then leaves the contents alone.
      chain = "docker-publish-guard";

      portRules = lib.concatMapStringsSep "\n" (
        p:
        let
          match = "-p ${p.protocol} --dport ${toString p.port}";
        in
        ''
          # ${p.comment}
          ${lib.concatMapStringsSep "\n" (
            iface: "iptables -A ${chain} -i ${iface} ${match} -j RETURN"
          ) cfg.allowedInterfaces}
          iptables -A ${chain} ${match} -j DROP''
      ) cfg.ports;
    in
    {
      options.myDockerPublishGuard = {
        enable = lib.mkEnableOption ''
          a DOCKER-USER allowlist restricting docker-published ports to a
          set of interfaces.

          This exists because a published port has no firewall in front of
          it. `virtualisation.oci-containers`' own option documentation
          says so ("Publishing a port bypasses the NixOS firewall"), and
          `networking.firewall.interfaces.<name>.allowed*Ports` cannot fix
          it: those render INPUT rules, and a DNAT'd packet is forwarded
          rather than delivered locally, so it never traverses INPUT at
          all. Such rules look like they scope a published port and
          constrain nothing (F-P4-02)
        '';

        allowedInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "wg0"
            "tailscale0"
          ];
          description = ''
            Interfaces a published port may legitimately be reached on.
            Everything else is dropped.

            Matched on the *input* interface rather than on a destination
            address, deliberately: the tailnet address is assigned by
            tailscale rather than declared here, so an address-based rule
            would need a hardcoded 100.64.0.0/10 address that this repo
            otherwise never hardcodes, and that would break silently if
            the node were ever re-registered.
          '';
        };

        ports = lib.mkOption {
          default = [ ];
          description = ''
            The published ports to guard. Only these are filtered; every
            other forwarded packet falls through untouched, so this does
            not disturb inter-container traffic or any other container.
          '';
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                port = lib.mkOption {
                  type = lib.types.port;
                  description = "Published host port.";
                };
                protocol = lib.mkOption {
                  type = lib.types.enum [
                    "tcp"
                    "udp"
                  ];
                  default = "tcp";
                  description = "Protocol the port is published with.";
                };
                comment = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "What this port is, for the generated script.";
                };
              };
            }
          );
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.ports == [ ] || cfg.allowedInterfaces != [ ];
            message = ''
              myDockerPublishGuard: ports are guarded but allowedInterfaces
              is empty, which would drop every packet to them from
              everywhere. If that is genuinely intended, stop publishing
              the port instead.
            '';
          }
        ];

        systemd.services.docker-publish-guard = {
          description = "Restrict docker-published ports to specific interfaces (DOCKER-USER)";

          # Must run after dockerd, because dockerd owns the creation of
          # DOCKER-USER and of the FORWARD jump into it. Re-run on docker
          # restart via PartOf: docker recreates the jump on every start,
          # and while it does not flush DOCKER-USER's contents, our own
          # chain is ours to keep correct rather than something to assume
          # about.
          after = [
            "docker.service"
            "firewall.service"
          ];
          requires = [ "docker.service" ];
          partOf = [ "docker.service" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };

          path = [ pkgs.iptables ];

          # Deliberately NOT sandboxed beyond NoNewPrivileges: this
          # manipulates the host's netfilter tables, which needs
          # CAP_NET_ADMIN in the host network namespace. See
          # docs/hardening.md on not sandboxing around a functional need.
          script = ''
            set -euo pipefail

            # Idempotent: own a private chain, rebuild it from scratch
            # every run, and jump into it from DOCKER-USER exactly once.
            # Rebuilding rather than appending is what makes a re-run after
            # a config change converge instead of accumulating.
            iptables -N ${chain} 2>/dev/null || true
            iptables -F ${chain}

            ${portRules}

            # DOCKER-USER is created by dockerd. It exists by the time this
            # runs (After=docker.service), but create it defensively so a
            # docker that has not yet touched iptables cannot make this
            # unit fail and leave the ports unguarded.
            iptables -N DOCKER-USER 2>/dev/null || true
            while iptables -D DOCKER-USER -j ${chain} 2>/dev/null; do :; done
            iptables -I DOCKER-USER 1 -j ${chain}
          '';

          preStop = ''
            ${pkgs.iptables}/bin/iptables -D DOCKER-USER -j ${chain} 2>/dev/null || true
            ${pkgs.iptables}/bin/iptables -F ${chain} 2>/dev/null || true
            ${pkgs.iptables}/bin/iptables -X ${chain} 2>/dev/null || true
          '';
        };
      };
    };
}
