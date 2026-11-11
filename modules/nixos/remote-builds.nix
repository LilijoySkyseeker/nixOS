_: {
  # The build host's side: a `nix-builder` account that other hosts' nix
  # daemons log in to over SSH, forced to `nix-daemon --stdio`.
  flake.modules.nixos."build-host" =
    { config, lib, ... }:
    let
      cfg = config.myBuildHost;
    in
    {
      options.myBuildHost.clientKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "SSH public keys (the clients' host keys) allowed to build here.";
      };

      config = {
        users.groups.nix-builder = { };
        users.users.nix-builder = {
          isSystemUser = true;
          group = "nix-builder";
          # sshd runs the forced command through the login shell
          useDefaultShell = true;
          openssh.authorizedKeys.keys = map (
            key: ''command="${config.nix.package}/bin/nix-daemon --stdio",restrict ${key}''
          ) cfg.clientKeys;
        };

        # ssh-ng builds of arbitrary derivations need a trusted user, which
        # is root-equivalent over this host's store
        nix.settings.trusted-users = [ "nix-builder" ];

        # the owner's desktop comes first: every daemon build (remote, the
        # agents' and the host's own) gets only CPU and disk nobody else wants
        nix.daemonCPUSchedPolicy = "idle";
        nix.daemonIOSchedClass = "idle";
      };
    };

  # A client: sends its builds to the build host, and builds locally when
  # that host can't be reached.
  flake.modules.nixos."remote-builds" =
    { config, lib, ... }:
    let
      cfg = config.myRemoteBuilds;
    in
    {
      options.myRemoteBuilds = {
        hostName = lib.mkOption {
          type = lib.types.str;
          description = "SSH host name of the build host.";
        };
        hostKey = lib.mkOption {
          type = lib.types.str;
          description = "The build host's SSH host public key.";
        };
        sshKey = lib.mkOption {
          type = lib.types.str;
          default = "/etc/ssh/ssh_host_ed25519_key";
          description = "Private key the nix daemon logs in with: this host's own host key, so there's no extra secret.";
        };
        maxJobs = lib.mkOption {
          type = lib.types.int;
          # high on purpose: with every slot busy, Nix builds the overflow
          # locally instead of waiting
          default = 16;
          description = "Builds to run on the build host at once.";
        };
      };

      config = {
        nix.distributedBuilds = true;
        nix.buildMachines = [
          {
            inherit (cfg) hostName sshKey maxJobs;
            protocol = "ssh-ng";
            sshUser = "nix-builder";
            system = "x86_64-linux";
            supportedFeatures = [
              "nixos-test"
              "benchmark"
              "big-parallel"
              "kvm"
            ];
          }
        ];
        # the build host fetches cache.nixos.org paths itself instead of
        # getting them uploaded from here
        nix.settings.builders-use-substitutes = true;

        programs.ssh.knownHosts.${cfg.hostName} = {
          hostNames = [ cfg.hostName ];
          publicKey = cfg.hostKey;
        };
        # unreachable: give up fast and build locally; a link that drops
        # mid-build fails that build (no local retry) within a minute
        # instead of hanging
        programs.ssh.extraConfig = ''
          Host ${cfg.hostName}
            ConnectTimeout 5
            ServerAliveInterval 15
            ServerAliveCountMax 4
        '';
      };
    };
}
