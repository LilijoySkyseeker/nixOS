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
- **AI Help**, on the running install: `sh Tools/ai-help.sh` from the
  mounted stick (or `Tools\AI Help.cmd` on Windows). The agent runs as the
  logged-in user, and its login is deleted when it exits.

Both need the internet (USB tethering from the phone works). The stick
holds no secrets: no sops age keys and no SSH keys, and the logins last
one boot. A step that needs a secret needs the user there.

## Notes that survive reboots

Each machine gets a folder at the stick's top level,
`Machines/<maker>-<model>-<serial>/`, holding the agent's `NOTES.md` (read
first, at every start) and its output in `files/`, the Health Reports in
`reports/`, saved drivers in `drivers/`, and both agents' chat history in
`chat/`. The Rescue System, AI Help and the stick's tools use the same
folder, so a job can run across reboots and between the two.

## Handing over a job: runbooks

The agents on the stick read `Runbooks/` when they start and
follow the runbook meant for their machine. **How to write one** is in the
stick's `Runbooks/README.md` (in the `usb-toolbox` repo at
`stick/Runbooks/README.md`, on torrent `~/work/repos/usb-toolbox`): name
the machine first, say who does each step (agent, a script with the
user's yes or secret, or the user's hands), run every command before the
day, check actual state, gate before anything irreversible, and delete
the runbook from the stick when the job is done. The stick's agents keep
their own rules for working with the user at the machine (windows on the
screen, commands shown before a YubiKey touch, ETAs, notes).

For this repo's hosts:

- You can't reach the stick from here: write the runbook and ask the user
  to copy it into the stick's `Runbooks/`.
- The runbook for a host lives in this repo, beside the config it
  depends on (`docs/procedures/<host>-<job>.md`; `thinkpad-reinstall.md` is
  the worked example), with a short file on the stick that names the
  machine and says to clone `https://github.com/LilijoySkyseeker/nixOS`
  and follow that path.
- Rehearse it here first, as far as it goes: the machine is out of use
  during the job, so the user prefers time spent planning and simulating
  beforehand to working things out on the day. Build the host, and run the VM tests that cover
  the steps (`tests/`, such as `thinkpad-disk` for the disk layout,
  TPM + PIN and hibernation). They don't build the Home Manager session or
  run disko's command line, so a runbook still needs a check for those.
- The stick's agent reads this file and `AGENTS.md` only when it works
  inside a clone. Write the rules that matter into the runbook: which
  branch to install, never to touch `secrets/`, what to check after each
  step.
- It tells the user the plan and waits for their yes before its first
  change to a disk or firmware, so plan for the user to be reachable on
  their phone.
