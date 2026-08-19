{
  config,
  lib,
  ...
}:
let
  cfg = config.myBuildSubmitter;
  fleet = import ./build-fleet.nix;
  # Never submit to yourself — a host's own entry in build-fleet.nix
  # describes it as a worker for OTHER submitters, not a target for its
  # own rebuilds.
  workers = lib.filterAttrs (name: _: name != config.networking.hostName) fleet;
in
{
  options.myBuildSubmitter = {
    enable = lib.mkEnableOption "submit this host's rebuilds to the other tailnet build workers listed in build-fleet.nix";
  };

  config = lib.mkIf cfg.enable {
    # One sops secret per worker this host is allowed to submit to —
    # matches modules/nixos/build-worker.nix's per-worker (not
    # per-edge) key convention: every submitter shares the same
    # private key for a given worker.
    sops.secrets = lib.mapAttrs' (
      name: _: lib.nameValuePair "builder_key_${name}" { }
    ) workers;

    nix.distributedBuilds = true;
    nix.buildMachines = lib.mapAttrsToList (
      name: w:
      {
        hostName = name; # tailnet MagicDNS name
        sshUser = "nix-builder";
        sshKey = config.sops.secrets."builder_key_${name}".path;
        protocol = "ssh-ng";
        inherit (w) systems maxJobs speedFactor;
      }
      // lib.optionalAttrs (w.publicHostKey != null) { inherit (w) publicHostKey; }
    ) workers;
  };
}
