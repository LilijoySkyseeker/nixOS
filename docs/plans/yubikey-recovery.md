# YubiKeys as a way back into everything

## Goal

"i want to make sure the yubikeys are guarenteed ways back into
everything. i have 2, so i just duplicate the setup on both. for
instance, getting back into the sops secretes."

## Your decisions

- 2026-10-19: two YubiKeys, each enrolled separately everywhere. One
  lives plugged into torrent; the other is on your keychain as the
  backup that's always on you.
- 2026-10-19: no break-glass sops file for recovery passwords (disk
  recovery passphrase, BitLocker key, supervisor password, restic).
  Bitwarden is the one chosen weak link for those.

## State

Not started. Facts as of 2026-10-19:

- torrent's key: YubiKey 5C Nano, serial 29680883, firmware 5.7.1, PIV
  enabled, so `age-plugin-yubikey` (nixpkgs 0.5.1) works. Keychain
  key's model not yet known.
- One YubiKey's resident FIDO2 SSH key is already in
  `vars.publicSshKeys` (root on homelab and vps); which of the two is
  unknown.
- sops supports age plugins since 3.10 (nixpkgs has 3.13.3), so
  `age1yubikey…` recipients work in `.sops.yaml`.

## Next

1. Each key: FIDO2 PIN and PIV PIN/PUK set (PIV ships with `123456`).
2. Resident SSH key on the second YubiKey; add it to
   `vars.publicSshKeys`.
3. A PIV age identity on each key; add both as recipients in
   `.sops.yaml` and `sops updatekeys` every file. `/security-review`
   before the PR.
4. Land before the thinkpad reinstall (`thinkpad-disk-encryption.md`),
   so the YubiKeys are a way back in if it goes wrong. The thinkpad's
   LUKS FIDO2 slots for both keys go in that runbook.
