# isoimage

Liveboot ISO image for install and recovery.

## Deliberately off-tailnet

`isoimage`'s module list is `[ hosts/isoimage/configuration.nix,
copyparty-iso ]` (`modules/flake/hosts.nix:91-98`). It does **not**
include `profile-default`, so on this system
`services.tailscale.enable = false` and `config.sops` is not even an
option. That is the design, not an oversight.

An ISO is a bootable artifact that gets copied to USB sticks, shared and
left lying around. Anything baked into it should be assumed public, so it
must not carry a tailnet identity or any sops-encrypted secret. Recovery
access to a host booted from this ISO is over the LAN or the console, not
over the tailnet.

Three things used to contradict that, all removed 2026-08-27 by the
security audit (`F-P8-19`, `F-P8-11`, and item 11 of
`docs/audits/2026-08-26/rotation-runbook.md`):

- `tag:isoimage` in `docs/tailscale-acl.json` — six live occurrences, in
  `tagOwners` and in the `src` of all four grants plus the `dst` of the
  first, describing a device that cannot exist. (The audit counted nine;
  the other three were in the two `ssh` rules, already deleted on
  2026-08-26 for unrelated reasons — see the comment at the bottom of
  that file, which still names the tag as an accurate record of what the
  deleted rule granted.) A phantom entry in a security-policy file makes
  the real entries harder to audit.
- `tailscale_authkey_isoimage` in `secrets/secrets.yaml` — a tailnet auth
  key with no consumer.
- The auth key itself, which had **never been used**. That is what made
  it worth acting on rather than shrugging at: the fleet's other exposed
  enrollment keys were spent single-use credentials Tailscale would
  refuse, but an unused key still has whatever power it was minted with.

If `isoimage` is ever genuinely meant to join the tailnet, that is a
config change first — give it `profile-default` and sops-nix — and a new
key second, **non-reusable, pre-authorized and tagged**. Do not revive
the old one, and do not re-add the tag ahead of the config.
