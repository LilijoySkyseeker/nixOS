{
  config,
  ...
}:

# Aria2 download manager
{
  services.aria2 = {
    enable = true;
    rpcSecretFile = config.sops.secrets."aria2-password".path;
  };
  sops.secrets."aria2-password" = {
    owner = "aria2";
    group = "aria2";
  };
  user.user.aria2.extraGroups = [ "multimedia" ];
}
