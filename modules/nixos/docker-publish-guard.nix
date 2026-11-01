_: {
  flake.modules.nixos."docker-publish-guard" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myDockerPublishGuard;

      # published ports are DNAT'd before routing and never reach INPUT
      # (nixos-fw); DOCKER-USER is the FORWARD chain docker won't rewrite
      chain = "docker-publish-guard";

      # `-o <bridge>` is load-bearing: dport alone also matches container
      # *outbound* traffic on same-port protocols (factorio's heartbeat,
      # SPT=DPT=34197), silently de-listing the server
      match = p: "-o ${cfg.bridgeInterface} -p ${p.protocol} --dport ${toString p.port}";

      portRules = lib.concatMapStringsSep "\n" (p: ''
        # ${p.comment}
        ${lib.concatMapStringsSep "\n" (
          iface: "iptables -A ${chain} -i ${iface} ${match p} -j RETURN"
        ) cfg.allowedInterfaces}
        iptables -A ${chain} ${match p} -j DROP'') cfg.ports;

      # a compromised container reaches the public internet only: NEW
      # connections out of the bridge to private and special ranges are
      # dropped (website.nix's IPAddressDeny list); replies to players are
      # ESTABLISHED and pass. mangle, not DOCKER-USER: tailscaled inserts
      # an `-o tailscale0 -j ACCEPT` ahead of DOCKER-USER in filter FORWARD
      egressChain = "docker-egress-guard";
      egressRules =
        cmd: ranges:
        lib.concatMapStringsSep "\n" (
          r:
          "${cmd} -t mangle -A ${egressChain} -i ${cfg.bridgeInterface} -m conntrack --ctstate NEW -d ${r} -j DROP"
        ) ranges;
      egressHook = cmd: ranges: ''
        ${cmd} -t mangle -N ${egressChain} 2>/dev/null || true
        ${cmd} -t mangle -F ${egressChain}
        ${egressRules cmd ranges}
        while ${cmd} -t mangle -D FORWARD -j ${egressChain} 2>/dev/null; do :; done
        ${cmd} -t mangle -I FORWARD 1 -j ${egressChain}
      '';
      egressUnhook = cmd: ''
        ${cmd} -t mangle -D FORWARD -j ${egressChain} 2>/dev/null || true
        ${cmd} -t mangle -F ${egressChain} 2>/dev/null || true
        ${cmd} -t mangle -X ${egressChain} 2>/dev/null || true
      '';
    in
    {
      options.myDockerPublishGuard = {
        enable = lib.mkEnableOption ''
          a DOCKER-USER allowlist restricting docker-published ports to a
          set of interfaces.

          A published port bypasses the NixOS firewall, and
          `networking.firewall.interfaces.<name>.allowed*Ports` can't scope
          it: those are INPUT rules, and a DNAT'd packet is forwarded, never
          traversing INPUT
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

            Matched on the input interface, not a destination address:
            the tailnet address is assigned by tailscale and would break
            silently if the node were re-registered.
          '';
        };

        bridgeInterface = lib.mkOption {
          type = lib.types.str;
          default = "docker0";
          description = ''
            The docker bridge published containers sit behind. Every rule
            is pinned to it with `-o`, so the guard only ever sees traffic
            being forwarded *into* the container network.

            Without this the rules match on destination port alone, and a
            protocol that uses the same port at both ends — Factorio's
            server heartbeat is one — has its *outbound* packets matched
            and dropped too. That failure is quiet and asymmetric:
            inbound play keeps working while the server drops off the
            public server list.
          '';
        };

        ports = lib.mkOption {
          default = [ ];
          description = ''
            The published ports to guard. Only these are filtered
            inbound; apart from the egress guard (NEW connections from the
            bridge to private ranges, other containers included, are
            dropped), every other forwarded packet falls through untouched.
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

          # after dockerd, which creates DOCKER-USER and its FORWARD jump;
          # PartOf re-runs this on docker restart
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

          # not sandboxed: needs CAP_NET_ADMIN in the host netns
          # (docs/hardening.md)
          script = ''
            set -euo pipefail

            # idempotent: rebuild the private chain each run, jump to it once
            iptables -N ${chain} 2>/dev/null || true
            iptables -F ${chain}

            ${portRules}

            # create defensively: a missing DOCKER-USER must not fail this
            # unit and leave the ports unguarded
            iptables -N DOCKER-USER 2>/dev/null || true
            while iptables -D DOCKER-USER -j ${chain} 2>/dev/null; do :; done
            iptables -I DOCKER-USER 1 -j ${chain}

            ${egressHook "iptables" [
              "0.0.0.0/8"
              "10.0.0.0/8"
              "100.64.0.0/10"
              "127.0.0.0/8"
              "169.254.0.0/16"
              "172.16.0.0/12"
              "192.168.0.0/16"
              "224.0.0.0/3"
            ]}
            ${egressHook "ip6tables" [
              "::1/128"
              "fc00::/7"
              "fe80::/10"
              "ff00::/8"
            ]}
          '';

          preStop = ''
            ${pkgs.iptables}/bin/iptables -D DOCKER-USER -j ${chain} 2>/dev/null || true
            ${pkgs.iptables}/bin/iptables -F ${chain} 2>/dev/null || true
            ${pkgs.iptables}/bin/iptables -X ${chain} 2>/dev/null || true
            ${egressUnhook "${pkgs.iptables}/bin/iptables"}
            ${egressUnhook "${pkgs.iptables}/bin/ip6tables"}
          '';
        };
      };
    };
}
