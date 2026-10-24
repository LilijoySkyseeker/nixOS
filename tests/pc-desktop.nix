# VM test: the PCs' desktop session starts whole: profile-pc (with
# lilijoy's Home Manager and Stylix) and kde, logged in through SDDM.
# Plasma's shell, KWin and the polkit agent run and stay up, none of them
# logs a QML module or type it can't load. A build can't show any of this.
{
  pkgs,
  specialArgs,
  profilePcModule,
  kdeModule,
}:
pkgs.testers.runNixOSTest {
  name = "pc-desktop";

  node.specialArgs = specialArgs;
  # the profile sets nixpkgs options of its own
  node.pkgsReadOnly = false;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        profilePcModule
        kdeModule
      ];
      virtualisation.memorySize = 6144;
      virtualisation.cores = 4;
      virtualisation.diskSize = 8192;

      services.displayManager.autoLogin = {
        enable = true;
        user = "lilijoy";
      };
      # no sops key in a test VM, and secrets are named after the real hosts
      sops.age.generateKey = lib.mkForce false;
      sops.validateSopsFiles = false;
    };

  testScript = ''
    import re

    def user_journal(unit_or_comm):
        return machine.succeed(
            f"journalctl -b --no-pager -o cat _UID=1000 {unit_or_comm} || true"
        )

    start_all()

    with subtest("Plasma's shell, KWin and the polkit agent start"):
        machine.wait_until_succeeds("pgrep -u lilijoy plasmashell", timeout=600)
        machine.wait_until_succeeds("pgrep -u lilijoy -f kwin_wayland", timeout=120)
        machine.wait_until_succeeds("pgrep -u lilijoy -f polkit-kde-authentication-agent", timeout=120)

    with subtest("they stay up"):
        machine.sleep(30)
        machine.succeed("pgrep -u lilijoy plasmashell")
        machine.succeed("pgrep -u lilijoy -f polkit-kde-authentication-agent")

    with subtest("no QML module or type failed to load"):
        log = user_journal("")
        bad = [l for l in log.splitlines()
               if re.search(r'module "[^"]+" is not installed|Type \S+ unavailable', l)]
        assert not bad, "QML load errors in the session:\n" + "\n".join(bad[:20])

    machine.screenshot("desktop")
  '';
}
