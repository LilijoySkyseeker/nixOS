# scripts/

`reinstall-host.sh` — Phase 2 (TODO.md: LUKS + TPM2 + Secure Boot +
impermanence) reinstall orchestrator. Template script driven by a
per-host config file under `hosts/`; copy `hosts/thinkpad.conf` to add
a new host.

Read the header comment in `reinstall-host.sh` for the full stage
sequence and where each stage runs (some are local-on-the-host, some
are remote-from-your-admin-machine — mixing them up will fail loudly
via the hostname check, not silently).

```
./reinstall-host.sh backup thinkpad                # on thinkpad, before wiping it
./reinstall-host.sh install thinkpad <iso-ip>       # from your admin machine
./reinstall-host.sh restore thinkpad                # on thinkpad, after first boot
./reinstall-host.sh secureboot thinkpad             # on thinkpad
./reinstall-host.sh tpm2 thinkpad                   # on thinkpad
```

The `backup`/`restore` stages are a **temporary** stand-in for real
automated backups (being built separately — see TODO.md). Once
thinkpad/torrent are covered by that system, delete those two stages
here and restore from there instead.
