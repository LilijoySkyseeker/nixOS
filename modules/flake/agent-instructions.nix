# the instruction file every session loads, built from one set of sources:
# the owner's goal (copied from their policies at build time, so it can't
# drift from the full text), the owner's working rule, then for the agents
# the shared orientation and the harness's own lines. the policies themselves
# don't load every session: they're installed at policiesPath and read where
# decisions are made (consolidation area 1, K2). consumers capture
# config.flake.agentInstructions in their outer `let`, before an inner
# module's `config` shadows it
{ config, inputs, ... }:
let
  rev = inputs.self.rev or inputs.self.dirtyRev or "unknown";

  policies = ../../agents/owner/policies.md;
  workingRule = ../home-manager/claude-code/user-claude.md;
  orientation = ../nixos/agent-user-AGENTS.md;
  # skills for every session, and the ones that name the agents' own tools
  ownerSkills = ../home-manager/claude-code/skills;
  sandboxSkills = ../nixos/agent-skills;

  # relative to the reader's home: the owner's and the agent's
  policiesPath = ".config/agents/policies.md";
  pointer =
    "The policies: `~/${policiesPath}`. They load where decisions are made: "
    + "the reviewer's rules, the card, design and planning prompts, and the "
    + "`doghouse-review` skill.";

  # the goal, then each layer in order. fails the build when the policies have
  # no Goal section, when the file reaches 20,000 bytes (harnesses truncate
  # long files without telling the agent: Antigravity at 24,000), or when a
  # skill it ships has a name that isn't its folder or a description outside
  # 1-1,024 characters (Agent Skills spec). the 200-line and 500-line
  # targets are only reported
  build =
    pkgs:
    {
      name,
      layers,
      skillDirs,
    }:
    pkgs.runCommand "${name}-instructions.md"
      {
        inherit
          policies
          rev
          pointer
          layers
          skillDirs
          ;
        label = name;
        nativeBuildInputs = [
          pkgs.gawk
          (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
        ];
      }
      ''
        fail() { echo "instructions ($label): $*" >&2; exit 1; }

        # the `## Goal` section, without trailing blank lines
        goal=$(awk '
          /^## / { if (on) exit; on = ($0 == "## Goal") }
          on && /^[[:space:]]*$/ { blank = blank "\n"; next }
          on { printf "%s%s\n", blank, $0; blank = "" }
        ' "$policies")
        [ -n "$goal" ] || fail "agents/owner/policies.md has no '## Goal' section"
        printf '%s\n' "$goal" | tail -n +2 | grep -q '[^[:space:]]' \
          || fail "the Goal section of agents/owner/policies.md is empty"

        {
          printf 'Instructions built from nixOS `%s`\n\n' "$rev"
          printf '%s\n\n%s\n' "$goal" "$pointer"
          for layer in $layers; do
            printf '\n'
            cat "$layer"
          done
        } > "$out"

        bytes=$(wc -c < "$out")
        lines=$(wc -l < "$out")
        [ "$bytes" -lt 20000 ] || fail "$bytes bytes; the cap is under 20,000"
        echo "instructions ($label): $lines lines (target 200), $bytes bytes (cap 20,000)"
        [ "$lines" -le 200 ] || echo "instructions ($label): over the 200-line target" >&2

        for dir in $skillDirs; do
          for md in "$dir"/*/SKILL.md; do
            skillLines=$(wc -l < "$md")
            [ "$skillLines" -le 500 ] || echo "$md: $skillLines lines, over the 500-line target" >&2
          done
        done
        python3 ${./agent-instructions-skills.py} $skillDirs || fail "a skill's frontmatter is invalid"
      '';
in
{
  flake.agentInstructions = {
    inherit
      policies
      policiesPath
      ownerSkills
      sandboxSkills
      ;

    # the owner's own sessions: the goal and their working rule
    forOwner =
      pkgs:
      build pkgs {
        name = "owner";
        layers = [ workingRule ];
        skillDirs = [ ownerSkills ];
      };

    # an agent harness (an entry of agent-user's table): the owner's layers,
    # then the shared orientation and the harness's own lines
    forHarness =
      pkgs: name: harness:
      build pkgs {
        name = "agent-${name}";
        layers = [
          workingRule
          orientation
          (pkgs.writeText "agent-${name}-tail.md" harness.tail)
        ];
        skillDirs = [
          ownerSkills
          sandboxSkills
        ];
      };
  };

  # every variant built, so `nix flake check` fails where a host build would
  perSystem = _: {
    checks.instructions =
      let
        pkgs = config.flake.pkgsUnstable;
        ai = config.flake.agentInstructions;
      in
      pkgs.linkFarm "instructions" (
        [
          {
            name = "owner.md";
            path = ai.forOwner pkgs;
          }
        ]
        ++ pkgs.lib.mapAttrsToList (name: harness: {
          name = "agent-${name}.md";
          path = ai.forHarness pkgs name harness;
        }) config.flake.agentHarnesses
      );
  };
}
