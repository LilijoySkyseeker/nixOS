# scripts/

`reinstall-host.sh` — Phase 2 (TODO.md: LUKS + TPM2 + Secure Boot +
impermanence) reinstall orchestrator. Template script driven by a
per-host config file under `hosts/`; copy `hosts/thinkpad.conf` to add
a new host.

Boot the host straight to the recovery ISO once — `backup`, `install`,
and `restore` all run remotely, over ssh to that one ISO session, from
your admin machine. Only what genuinely needs physical presence
(Secure Boot's BIOS Setup Mode, and TPM2 enrollment which must happen
post-reboot on the real signed boot chain) is local, on the host
itself, after it boots into the new install. Read the header comment
in `reinstall-host.sh` for the full rationale and sequence — running a
stage in the wrong place fails loudly via a hostname/target check, not
silently.

```
./reinstall-host.sh backup     thinkpad <iso-ip>   # from your admin machine
./reinstall-host.sh install    thinkpad <iso-ip>   # from your admin machine
./reinstall-host.sh restore    thinkpad <iso-ip>   # from your admin machine (offers to reboot the host at the end)
./reinstall-host.sh secureboot thinkpad             # on thinkpad, after it boots the new install
./reinstall-host.sh tpm2       thinkpad             # on thinkpad
```

Add `--dry-run` (anywhere in the args) to exercise any stage's logic —
arg parsing, host-conf loading, command construction — without
touching real disk state, ssh'ing anywhere, or requiring the target to
exist. Not a substitute for a real dry run; it can't catch a wrong IP,
a stale key, or an actual disko failure.

`backup`/`install`/`restore` ssh to the ISO with agent forwarding
(`-A`), so syncoid running there can reach homelab using your own
forwarded key — no private key is ever baked into the ISO image. See
`hosts/isoimage/configuration.nix`'s `AllowAgentForwarding`.

The `backup`/`restore` stages are a **temporary** stand-in for real
automated backups (being built separately — see TODO.md). Once
thinkpad/torrent are covered by that system, delete those two stages
here and restore from there instead.
