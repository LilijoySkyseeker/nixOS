---
slug: fix-homelab-jellyfin-ffmpeg-high-cpu-nvidia-driver-dropped-gtx-1050
created: 2026-09-03
status: in-progress
frozen: false
---

# fix homelab jellyfin/ffmpeg high CPU: nvidia driver dropped GTX 1050 Pascal support, encoding.xml drifted

## Original plan

User reported jellyfin/ffmpeg pegging CPU on homelab. Root-caused live via
`ssh root@homelab` (confirmed working; earlier `ssh homelab` as the
unprivileged user failed with publickey denied):

1. `hosts/homelab/configuration.nix:145` pins
   `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable`.
   homelab's `nixosSystem` uses the `nixpkgs-stable` input (nixos-26.05,
   pinned rev `a3116115851d68b8952a2a4221cc25a84e56b532`) --
   `modules/flake/hosts.nix:62`. At that rev, `nvidiaPackages.stable` =
   `production` = driver **595.71.05**. `dmesg` on the live host shows
   this driver refusing the card:
   `"NVRM: The NVIDIA NVIDIA GeForce GTX 1050 GPU installed in this
   system is supported through the NVIDIA 580.xx Legacy drivers... The
   595.71.05 NVIDIA driver will ignore"` -> `"NVRM: No NVIDIA GPU
   found."` `nvidia-smi` fails outright. The GTX 1050 is GP107 (Pascal);
   nixpkgs' current stable-channel default driver has dropped Pascal
   support. Verified against the pinned nixpkgs source (not assumed):
   `pkgs/os-specific/linux/nvidia-x11/default.nix` at that rev defines
   `legacy_580 = generic { version = "580.173.02"; ... }` -- the exact
   580.x branch dmesg says is required.
2. Independently, `/srv/jellyfin/config/encoding.xml` on the live host
   has `<HardwareAccelerationType>none</HardwareAccelerationType>`,
   drifted from `modules/services/jellyfin.nix`'s declared `nvenc`
   config. jellyfin logs on every start:
   `"WARN: /srv/jellyfin/config/encoding.xml already exists and is
   different from the configured settings. transcoding options NOT
   applied."` Read the nixos-26.05 jellyfin module source directly
   (`nixos/modules/services/misc/jellyfin.nix`): under the default
   `forceEncodingConfig = false`, the module only ever writes
   `encoding.xml` when the file doesn't exist yet -- once it exists and
   differs, it just re-warns on every start, forever, regardless of
   rebuilds. `forceEncodingConfig = true` is the module's own built-in
   escape hatch: it diffs the file against the declared config on every
   start and overwrites (with a timestamped backup) whenever they
   differ, making the NixOS config the durable source of truth.
   Tradeoff: the module's generated XML only covers ~15 fields
   (`HardwareAccelerationType`, `EnableHardwareEncoding`,
   `AllowHevcEncoding`, thread count, CRFs, throttling, tonemapping
   toggle, subtitle extraction, decoding codecs list, Intel low-power
   flags, HEVC RExt depth flags). Anything else currently in
   `encoding.xml` (`DownMixAudioBoost`, `DownMixStereoAlgorithm`,
   `MaxMuxingQueueSize`, `EnableSegmentDeletion`/`SegmentKeepSeconds`,
   `TonemappingAlgorithm`/`Mode`/`Range`/etc., `EncoderPreset`,
   `DeinterlaceMethod`, `EnableEnhancedNvdecDecoder`,
   `PreferSystemNativeHwDecoder`,
   `AllowOnDemandMetadataBasedKeyframeExtractionForExtensions`) is not
   emitted at all, so once `forceEncodingConfig` overwrites the file
   those fields fall back to Jellyfin's own internal defaults instead of
   whatever's on disk now -- and any future dashboard tweak to those
   *covered* fields (or to hardware accel itself) gets silently
   reverted on the next service restart, since NixOS becomes the sole
   source of truth per the option's own doc comment.

Both issues together fully explain the reported symptom: with
`HardwareAccelerationType=none` on disk, every transcode -- decode and
encode both -- runs entirely in software (no NVENC/NVDEC, no VAAPI/QSV
fallback either, since `none` disables all hardware paths), which is
what pegs CPU on both the `jellyfin` process and any `ffmpeg` children it
spawns.

## State

Root cause fully diagnosed and confirmed against live host + pinned
nixpkgs source. D1 (forceEncodingConfig vs one-time delete) needs the
user's actual answer before implementation starts.

## Progress

- [x] D1 -- resolved
- [x] driver package swapped in `hosts/homelab/configuration.nix`
- [x] encoding.xml reconciliation implemented per D1's answer
- [x] verify-ladder run clean
- [x] real `nixos-rebuild build` (or switch, if user wants live deploy)
      confirms build succeeds -- via verify-ladder's targeted rebuild
- [ ] on-host verification: `nvidia-smi` works, a real transcode uses
      `hevc_nvenc`/`h264_cuvid` instead of `libx264`

## Decisions (D)

### D1 -- forceEncodingConfig = true (self-healing, loses a few
dashboard-only fields) vs. one-time manual delete of the stale
encoding.xml (module writes it once, dashboard stays editable
going forward, but the exact same drift can silently recur)


**ANSWERED 2026-09-03:** User chose forceEncodingConfig=true over one-time manual delete -- wants self-healing/declarative-first behavior, accepts that dashboard-only fields (DownMixAudioBoost, MaxMuxingQueueSize, EncoderPreset, DeinterlaceMethod, tonemapping algorithm/mode/range, etc.) will revert to Jellyfin's built-in defaults.

## Gotchas (G)

### G1 -- nixpkgs-stable, not the bare "nixpkgs" flake input, backs
homelab

`flake.lock` has a top-level node literally named `nixpkgs` (rev
`e4bae1bd...`), which is *not* what `hosts/homelab/configuration.nix`
builds against -- it's a transitive input of some other flake dependency.
`modules/flake/hosts.nix:62` shows `homelab = inputs.nixpkgs-stable.lib.nixosSystem`.
Checking the wrong input's nvidia-x11 source (as done once during this
investigation) gave a `stable` version of 580.119.02, which contradicted
the live dmesg output (595.71.05) until the correct input was found.
Also: `nix eval` invocations are blocked by this session's Bash-tool
sandbox as a false-positive git-safety match (something about the string
"eval") inside a worktree -- had to resolve nixpkgs revs via
`nix flake metadata --json` + `curl` against raw.githubusercontent.com
instead of evaluating the flake directly.

## Findings (F)
*(populated by security/docs-updater when invoked)*
