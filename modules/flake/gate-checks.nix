# The repo's own gate scripts, as flake checks.
#
# Separate from checks.nix deliberately: that file's checks boot real VMs to
# catch what only breaks at runtime, and these do not. They run the scripts
# that guard every commit -- the plan-file and workflow gates -- against
# their own fixtures. Keeping them apart also means one `checks` key per
# file rather than a repeated one.
#
# 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#D2
# chose this home over a GitHub Actions step: a check runs on any machine,
# in any CI, and locally, and the enforcement stays in the flake.
{ config, inputs, ... }:
let
  gateCheck =
    script:
    import ../../tests/gate-script-check.nix {
      pkgs = config.flake.pkgsUnstable;
      src = inputs.self;
      inherit script;
    };
in
{
  perSystem = _: {
    checks = {
      # The fast tier. Also called directly by verify-ladder before every
      # non-trivial commit -- not a double run, see the note there.
      gate-tests = gateCheck "scripts/gate-tests";

      # The slow tier: one whole run of the suite per catalogue entry.
      # Never in verify-ladder's pre-commit path.
      # 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#G13
      gate-mutants = gateCheck "scripts/gate-mutants";
    };
  };
}
