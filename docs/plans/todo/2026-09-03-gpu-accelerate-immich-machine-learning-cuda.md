---
slug: gpu-accelerate-immich-machine-learning-cuda
created: 2026-09-03
status: todo
frozen: false
---

# GPU-accelerate Immich machine learning (CUDA)

## Original plan

Follow-up to `2026-09-03-add-immich-tailscale-only-to-homelab.md`, carried
from that plan's D3. Immich's machine-learning worker (face detection,
CLIP smart search) runs CPU-only in v1. This plan is to add
CUDA-accelerated `onnxruntime` for it using homelab's existing Nvidia GTX
1050 Mobile, once that base service has been live long enough to know
whether real ML latency actually justifies the build cost.

## State

**2026-09-03, not started — background research already done in the
parent plan's F2, reproduced below under Findings.** Blocked on nothing
except priority; the recipe is known and working (per the NixOS Discourse
thread cited in F2). Before starting, re-check current per-photo ML
latency on the live CPU-only install — the whole point of deferring was
to see whether it's actually worth a multi-hour one-time build.

## Progress
- [ ] confirm CPU-only ML latency is actually a problem on the live install (don't build this speculatively)
- [ ] `onnxruntime` overlay with `cudaSupport = true` added, scoped to avoid rebuilding unrelated packages
- [ ] test patch applied (one failing assertion in immich-ml's test suite, per the Discourse recipe)
- [ ] `immich-machine-learning`'s systemd unit updated: `PrivateDevices = lib.mkForce false`, `DeviceAllow` for `/dev/nvidia0`/`nvidiactl`/`nvidia-uvm`, `accelerationDevices`, and the `LD_LIBRARY_PATH` wiring the recipe needed beyond `accelerationDevices` alone
- [ ] confirmed no "Init provider bridge failed" warning at startup, GPU activity visible in `nvtop` during a real ML job
- [ ] `nixos-rebuild build --flake .#homelab` passes (expect a long local build — no binary cache for this variant)

## Decisions (D)
### D1 -- is this worth doing at all, or does CPU-only ML stay good enough?
Not answered — that's the point of the first Progress item above. Revisit
once the base Immich install has run long enough to have a real opinion.

## Gotchas (G)
### G1 -- no binary cache; every relevant nixpkgs bump re-triggers the multi-hour build
Unlike jellyfin's NVENC accel (which just uses the already-cached driver
package), a CUDA-enabled `onnxruntime` has no substituter hit anywhere —
confirmed via the Discourse thread in the parent plan's F2. Bumping
nixpkgs-stable will silently reintroduce a multi-hour local build the
next time `homelab` rebuilds, unless something pins/caches this
explicitly. Worth deciding at implementation time whether that's
acceptable ongoing cost or whether it needs its own cachix-style binary
cache.


## Findings (F)
*(populated by security/docs-updater when invoked)*

Carried from `2026-09-03-add-immich-tailscale-only-to-homelab.md#D3`:

homelab already has both an Nvidia GTX 1050 Mobile (NVENC/NVDEC, used by
jellyfin) and an Intel HD 630 iGPU (VAAPI/QSV) passed through. Immich's ML
worker can use either (CUDA or OpenVINO) but the pinned nixpkgs
`immich-machine-learning` package didn't show an obvious build-time
acceleration variant on a first look (unlike jellyfin, which gets hardware
accel for free via `hardwareAcceleration.device`) — needs a closer look at
whether the nixpkgs package exposes a CUDA/OpenVINO passthru or whether
it'd need a custom override. CPU-only ML works out of the box and is
probably fine for a personal library's initial size. Recommend deferring
GPU accel to a follow-up rather than blocking v1 on it, but flagging as a
decision rather than assuming. Not answered yet.


**DISCUSSED 2026-09-03:** user asked to investigate GPU accel now, before v1. Investigated (see F2): it is real and documented (CUDA/Nvidia only, no OpenVINO path in nixpkgs' onnxruntime), but is a multi-hour from-source build with no binary cache, needing a global onnxruntime overlay override, a test patch, and manual device/LD_LIBRARY_PATH wiring beyond what accelerationDevices alone provides -- and it has to be rebuilt from source again on every relevant nixpkgs bump. Recommendation given to user: ship CPU-only for v1, revisit CUDA as a follow-up once the base service is live and its real ML latency is known. Awaiting final call.


**DEFERRED 2026-09-03:** user picked CPU-only for v1 (F2's cost -- multi-hour from-source CUDA-onnxruntime build, no OpenVINO path, no binary cache, rebuild on every relevant nixpkgs bump -- outweighs building it in speculatively). Spun into its own todo plan for later.
