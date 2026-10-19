# Work at the machine: the TOOLBOX stick

Some jobs need the machine itself, not a deploy: a reinstall, disk or
partition work, firmware and Secure Boot, anything that spans reboots or
starts with the installed OS down. For those, the user carries **TOOLBOX**,
a USB stick that puts Claude Code or Codex on the machine, with notes kept
on the stick for each machine. You can hand such a job to that agent by
writing it a runbook. The stick is its own project (`usb-toolbox`, not
in this repo); its handbook is `START HERE.html` at the stick's root.

## The two ways in

- **The Rescue System**: boot the stick (Ventoy's default entry). It's a
  NixOS live desktop built on nixpkgs' graphical installer, so
  `nixos-install`, `nixos-enter`, ZFS, LUKS, `sbctl`, `efibootmgr`,
  `git` and `nix` are there. Claude Code and Codex run in auto mode with
  passwordless sudo. The internal disks are read-only until `disk-rw`
  unlocks one. The user signs in from their phone (**AI Login**) and
  drives the agent through Claude Remote Control.
- **AI Help**, on the running install: `_toolbox/ai/ai-help.sh` from the
  mounted stick (or `AI Help.cmd` on Windows). The agent runs as the
  logged-in user, and its login is deleted when it exits.

Both need the internet (USB tethering from the phone works). The stick
holds no secrets: no sops age keys and no SSH keys, and the logins last
one boot. A step that needs a secret needs the user there.

## Notes that survive reboots

Each machine gets a folder on the stick,
`_toolbox/collected/sessions/<maker>-<model>-<serial>/`, holding the
agent's `NOTES.md` (read first, at every start) and both agents' chat
history. The Rescue System and AI Help use the same folder, so a job can
run across reboots and between the two.

## Handing over a job: runbooks

The agents on the stick read `_toolbox/runbooks/` when they start and
follow the runbook meant for their machine. The stick's
`_toolbox/runbooks/README.md` has the format: name the machine first, by
hostname (`thinkpad`) or by maker, model and serial, then the goal, the
steps, and how to check each one.

- You can't reach the stick from here: write the runbook and ask the user
  to copy it into `_toolbox/runbooks/`.
- This repo is public, so the runbook can live here (in
  `docs/plans/<slug>.md`, say), with a short file on the stick that names
  the machine and says to clone
  `https://github.com/LilijoySkyseeker/nixOS` and follow that path.
- The stick's agent reads this file and `AGENTS.md` only when it works
  inside a clone. Write the rules that matter into the runbook: which
  branch to install, never to touch `secrets/`, what to check after each
  step.
- It tells the user the plan and waits for their yes before its first
  change to a disk or firmware, so plan for the user to be reachable on
  their phone.
