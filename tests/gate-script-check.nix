# Runs one of the repo's own gate scripts as a flake check, so the gates are
# enforced by the repo rather than by an agent remembering to run them.
# 2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#D2
# chose this home over a GitHub Actions step: a check runs on any machine, in
# any CI, and locally, and the enforcement stays in the flake.
#
# Note what this does *not* replace. `verify-ladder` runs
# `nix flake check --no-build`, and `--no-build` is documented as "Do not
# build checks" -- it evaluates them and stops. So a check here does not run
# before a commit, and `verify-ladder` keeps its own direct call to
# `scripts/gate-tests` for that. The two are not a double run.
#
# The scripts are hermetic by construction -- they build their own git
# fixtures under $TMPDIR and touch nothing outside them -- which is what lets
# them run in the sandbox unchanged.
{
  pkgs,
  src,
  script,
}:
pkgs.runCommand "check-${baseNameOf script}"
  {
    # git, because every gate under test shells out to it, and the sabotage
    # sweep needs a real one to shim. The rest are what the scripts and the
    # gates they exercise actually call.
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      diffutils
      findutils
      gawk
      git
      gnugrep
      gnused
    ];
  }
  ''
    cp -r ${src} repo
    chmod -R u+w repo
    # The sandbox has no /usr/bin/env, and the gates invoke each other by
    # path, so their `#!/usr/bin/env bash` lines must be resolved first.
    patchShebangs repo/scripts repo/docs/skills
    # git refuses to identify itself without one.
    export HOME="$NIX_BUILD_TOP/home"
    mkdir -p "$HOME"
    cd repo
    bash ${script}
    touch $out
  ''
