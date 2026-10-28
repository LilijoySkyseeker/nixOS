---
paths:
  - "**/*.nix"
---

# Nix conventions

Conventions actually in use in this repo, not aspirational ones. See
`docs/architecture.md` for the dendritic module-organization boundary.

## Formatting

Separate, clearly commented top-level statements (`systemd.foo = …;`,
`systemd.bar = …;`) beat one deeply nested block, which is why
`statix.toml` turns off `repeated_keys`. Don't restructure code just to
silence a purely stylistic finding. The user on the immich module: "as
long as things are organized and have the correct comment info next to
them they are fine."

## Custom options modules: the `my<Name>` convention

Reach for this pattern only when the config is genuinely parameterized
(multiple hosts want it with different settings, or it needs an
enable/disable toggle). If a host is the config's only consumer and
there's nothing to parameterize, a plain `modules/*/*.nix` file
is simpler — see `docs/architecture.md`'s module-organization section.

## Inline comments

- A temporary workaround (a patch, an override, a stopgap until an
  upstream fix reaches a channel) says when it goes:
  `# TODO: drop when NixOS/nixpkgs#576063 is in nixos-unstable`. The
  weekly agent jobs `git grep "TODO: drop when"` and remove the ones whose
  condition is met.
