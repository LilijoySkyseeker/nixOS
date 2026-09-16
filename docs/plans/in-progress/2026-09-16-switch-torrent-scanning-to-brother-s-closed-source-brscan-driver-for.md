---
slug: switch-torrent-scanning-to-brother-s-closed-source-brscan-driver-for
created: 2026-09-16
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---

# switch torrent scanning to Brother's closed-source brscan driver for ADF duplex

## State

Verified to rung 3 (ran it locally, output inspected): `verify-ladder`
green including `gate-tests` 108/108, and brscan4 was exercised against
the real printer from the pinned tree before any config was written --
it recognises the model and offers ADF duplex up to 9600 dpi (G1, D1).

Not closeable yet. brscan4 has no VM test in nixpkgs (only brscan5 has
one), so rung 4 is unavailable, and the thing that actually matters --
paper duplexing through the ADF on the deployed host -- needs a switch
and a physical sheet. Stays `in-progress` until then.

`security` run, 0 CRITICAL / 0 HIGH / 1 MEDIUM / 5 INFO; all resolved in
the records rather than the config (G2).

## Original plan

User: *"for the printer, i cant get it to do double sidded scanning, but i
have another pc that works for the closed souce drivers, lets switch to
thoes. make sure to tag closed source in the config next to it."*

So: replace driverless `sane-airscan` (WSD) on `torrent` with Brother's
non-free `brscan` backend, and label the unfree dependency explicitly at
the point of use.

This reverses the original driverless-first decision
(`2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#D1`,
*"no Brother blob (brscan4) needed"*). That decision was not wrong when
made -- it was a reasonable call on the evidence then -- but see G1 for
what it did not know.

## Progress

- [x] Establish the WSD path's actual capability ceiling (G1)
- [x] Confirm `brscan4` and `brscan5` both exist at the pinned rev
- [x] Determine which version covers the MFC-L2740DW -- brscan4 (D1)
- [x] Read the pinned NixOS module's `netDevices` option shape
- [x] Match the repo's existing unfree mechanism -- already set, nothing added
- [x] Drop airscan and its firewall rule (D2)
- [x] Implement, tagged closed-source at the point of use
- [x] `verify-ladder`
- [x] `security` review; findings resolved (G2)
- [x] `docs-updater`, run last so it documents the post-review state (F7-F12)
- [ ] Deploy and scan a real double-sided sheet through the ADF

## Decisions (D)

### D1 -- brscan4, and the unfree concession

The decision itself is **ADR-0003**; not restating it here per
`docs/adr/README.md` ("Do not restate an ADR's content in the plan --
cite it"). It records why brscan4 rather than brscan5, why not stay
driverless, and what the blob costs.

User asked for this explicitly, including the labelling: *"make sure to
tag closed source in the config next to it"* and *"lets write down using
the unfree blob as a decission."* The tag is a `>>> CLOSED SOURCE <<<`
block at the point of use in `modules/nixos/brother-mfc-l2740dw.nix`,
pointing at the ADR.

Implementation notes that are *not* ADR material:

- `hardware.sane.brscan4.netDevices."mfc-l2740dw" = { model; ip; }`.
  `model` is the only required attribute; exactly one of `ip`/`nodename`
  may be set (assertion in the pinned module). Used `ip` -- `nodename`
  resolves via mDNS, and avahi is gone fleet-wide (D9).
- No `extraBackends` entry: the module wires `pkgs.brscan4` itself.
- No unfree plumbing: `nixpkgs.config.allowUnfree` is already set in
  `modules/profiles/default.nix` and reaches torrent through
  profile-pc -> profile-default.
- No manual `imports`: the brscan4 module is in nixpkgs'
  `module-list.nix`. The NixOS wiki's import-by-path snippet is stale.
- Dropping `pkgs-unstable.sane-airscan` left the module's `pkgs-unstable`
  argument unused, so the signature became `{ ... }:` -- otherwise
  deadnix fails `verify-ladder`.

### D2 -- drop sane-airscan and its firewall rule rather than keep a fallback

User: *"lets drop it if nothing consumes it."* Verified nothing does.
Grepped the repo: the only non-comment use of `sane-airscan` was the
`extraBackends` line now removed, and the `networking.firewall.
extraCommands` rule in this module is the only one outside `hosts/vps/`
and `tests/`, which are unrelated.

The rule existed solely for WSD's multicast-probe/unicast-reply pattern,
which conntrack cannot match. brscan4 uses plain outbound TCP to the
printer's 54921 -- measured during a live scan as the only port dialled,
with no inbound accept present -- so `ESTABLISHED` covers it.

Deleting it is a net security improvement rather than a neutral cleanup:
that rule accepted UDP from a bare, on-link-claimable source IP across
the entire ephemeral range, which is the accepted risk recorded as
`2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#F3`.
It also ends WS-Discovery multicast from this host, closing the residual
half of `...#F1` that host-scoping only mitigated.

## Gotchas (G)

### G1 -- WSD exposes duplex but caps at 300 dpi; the duplex complaint is probably Skanpage

Measured before switching, since "driverless cannot do it" would have
been the cleanest justification and turns out not to be true:

```
$ scanimage -d 'airscan:w0:Brother MFC-L2740DW series' --help
    --resolution 100|200|300dpi [300]
    --source Flatbed|ADF|ADF Duplex [Flatbed]
```

`ADF Duplex` is offered, and a real acquisition through it succeeds --
`--source 'ADF Duplex' --resolution 200` returned a 1700x2800 PNG, exit
0. So the WSD backend does duplex at the protocol level, and the
double-sided failure the user hit is most likely in Skanpage's UI rather
than in the driver.

What *is* a genuine WSD ceiling is **resolution: 100/200/300 dpi only**.
Brother's own driver exposes higher. That is the durable argument for
this change; "duplex is impossible over WSD" would not have been.

Recording this because it is the kind of thing that gets rediscovered
later as "why did we take on an unfree blob when driverless did duplex
fine?" -- the answer is the dpi ceiling plus a user with a known-good
reference machine, not a duplex impossibility.

### G2 -- how the security findings were resolved

All six landed as writing problems in ADR-0003 and the module comment,
not as defects in the config. The Nix is unchanged since `verify-ladder`
first went green; every fix below is to a record.

- **F2 (MEDIUM)** -- rewrote the ADR's main Consequence. It said the blob
  was "bounded by being one host, one non-root backend". That understated
  it badly: SANE backends are `dlopen`ed in-process, the desktop user is
  in `wheel`/`docker`/`libvirtd`, and the measured binary has no RELRO,
  no stack protector, no FORTIFY, and imports `popen`. The ADR now states
  the route to root explicitly and says what would change the answer.
- **F1** -- deleted the "only unfree blob in the fleet" claim from both
  the ADR and the module comment. It was simply false: `spotify`,
  `discord`, `claude-code` and others are unfree `binaryNativeCode` on
  both PC hosts already. The ADR now distinguishes *exposure* (network
  input into a `dlopen`ed library) from unfree-ness, which is the real
  point. Also fixed the claim that `allowUnfree` was set "for firmware" --
  it is a general setting, with `hardware.enableAllFirmware` separate.
- **F5** -- "removes the last inbound accept" narrowed to "on `enp8s0`";
  `tailscale0` still accepts 22 and 1714-1764 and `allowPing` is true.
  Also corrected "retiring the accepted risk `#F3`": F3 was **fixed**,
  not accepted, and `docs/accepted-risks.md` has no printer entry.
- **F3** -- added the udev rule and `brsaneconfig4`-on-PATH to the ADR's
  Consequences instead of leaving them unmentioned.
- **F6** -- cut the module's ~20-line rationale comment to five lines
  plus pointers, per `docs/style-guide.md` ("why" belongs in the plan).
  Kept the explicit `>>> CLOSED SOURCE <<<` tag, which the user asked for
  by name; the trim was of the reasoning around it, not the label.
- **F4** -- no change. Build-time execution of the vendor binary is real
  but bounded by `nix.settings.sandbox = true` and a non-fixed-output
  derivation, and the generated config holds only a model string and a
  LAN IP.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 -- ADR-0003's load-bearing "only unfree blob in the fleet" claim is false; four unfree packages, three of them `binaryNativeCode`, already ship on both PC hosts

- **File:** `docs/adr/0003-unfree-brscan4-blob-for-scanning-on-torrent.md:13-14` ("This is the only unfree blob anything in the fleet depends on for a *function*, as distinct from firmware"), `:94-98` ("`allowUnfree` ... has been set fleet-wide ... for firmware"); `modules/nixos/brother-mfc-l2740dw.nix:35-36` ("Nothing else in the fleet depends on an unfree blob; keep it that way"); contradicted by `modules/profiles/PC.nix:52,72-74,80,381-383`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used (documentation that does not match the config)
- **Reachability:** No adversary -- this is a decision-hygiene defect. The reader it misleads is the next person deciding whether to take on a blob: an ADR that says "this is the only one" sets a bar the fleet has not actually been holding, so the guard it writes ("should not spread to a second host without revisiting this record") reads as a standing invariant when it is in fact a new and stricter rule than anything currently enforced.
- **Rule:** n/a (accuracy of a record that ADR-0002 makes gating)
- **Finding:** Evaluated against the pinned nixpkgs-unstable `e4bae1b` via `nixosConfigurations.torrent.pkgs.<pkg>.meta`: `spotify` (unfree, `binaryNativeCode`), `discord` (unfree, `binaryNativeCode`), `claude-code` (unfree, `binaryNativeCode`) and `vscode-fhs` (unfree) are all in `modules/profiles/PC.nix`'s `environment.systemPackages` -- and `PC.nix:72` already labels that block `# closed source`. `programs.steam.enable = true` (`PC.nix:381`) pulls `steam` (`unfreeRedistributable`), whose udev rules are live in torrent's rendered `services.udev.packages`. All of these reach **both** PC hosts, not one. `obsidian` (unfree) comes in via home-manager (`modules/home-manager/tooling-desktop.nix:26`). So brscan4 is not the fleet's only unfree functional dependency, not the only `binaryNativeCode` one, and not the only one parsing network input. The honest distinguishing properties are narrower: it is the only blob loaded **in-process by a system library** (`libsane` dlopens it via `/etc/sane-libs`; `dll.conf:102` reads `brother4`), and the only one whose input comes from an unauthenticated device on the LAN. The related claim that `allowUnfree` was set "for firmware" is also wrong on its face -- `modules/profiles/default.nix:188` sets `allowUnfree` and `:190` sets `hardware.enableAllFirmware` as two separate settings, and the unfree *applications* above have been relying on the former all along.
- **Fix risk:** None technically; the fix is editing the ADR and the module comment. The risk of leaving it is that the next blob decision cites this ADR as precedent for a standard the fleet was never actually holding.

### F2 -- the brscan4 backend is an unhardened closed-source native parser fed by a bare-IP LAN peer, loaded in-process into the desktop user's session (which holds `wheel` and `libvirtd`)

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:49-60`; `docs/adr/0003-unfree-brscan4-blob-for-scanning-on-torrent.md:68-71` (the "bounded by ... one non-root backend" framing); `modules/profiles/PC.nix:373-377` and `modules/nixos/virtual-machines.nix:9-11` (the principal's groups)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the binary-hardening facts, the load path and the principal's group memberships (read from the pinned store path and from evaluated config). PLAUSIBLE for the end-to-end chain -- no memory-safety defect in the blob was demonstrated, and none can be, since the library is stripped and unauditable.
- **Axis:** hardening
- **Reachability:** An adversary on torrent's LAN segment who can answer at `192.168.1.166:54921` -- either by compromising the printer (a consumer MFP running vendor firmware with its own HTTP admin console) or by claiming/spoofing that address, which the 2026-08-27 plan's `#F3` already established as a low bar here (DHCP reservation lapse, printer powered off, ARP spoofing). The trigger is the user opening a scan application or running `scanimage`; the backend then connects outbound and parses whatever comes back, inside the address space of the calling process. That process is the interactive desktop session of `lilijoy`, whose evaluated `extraGroups` on torrent are `[networkmanager wheel docker libvirtd]`. `virtualisation.libvirtd.enable = true` on torrent, and `libvirtd` membership is root-equivalent (define a domain backed by a host block device or host path). So the chain ends at host root without needing to beat the `wheel`/run0 password prompt.
- **Rule:** new-rule candidate -- "a closed-source native parser given attacker-influenceable input must not run in a session that holds root-equivalent group membership." Also sharpens `docs/hardening.md` rule 5 from interface-trust to *peer-identity* trust: `ip = "192.168.1.166"` is a belief about the network with no authentication behind it, which is exactly the argument `#F2`/`#F3` of the 2026-08-27 plan made about the print queue.
- **Finding:** Read from the pinned store path (`.../brscan4-0.4.10-1/lib/sane/libsane-brother4.so.1.0.7`): the library is `stripped`, has **no `GNU_RELRO` segment at all**, **no stack protector** (`__stack_chk_*` symbol count is 0), **no `_FORTIFY_SOURCE` `*_chk` imports**, and imports `strcpy`, `strcat`, `sprintf` and `popen` from glibc. `GNU_STACK` is `RW`, so NX is present, and it is a shared object so it inherits ASLR -- but every other compiler mitigation this fleet gets for free is absent, since the object was built by the vendor and `dontStrip`/`dontPatchELF` preserve it verbatim. The imported `popen` means the library can spawn a shell on its own, so a parsing bug would not even need a ROP chain to matter. This is materially more exposure than the ADR's "one non-root backend" conveys: the backend is not a separate principal at all, it is a `dlopen`ed library inside whatever process called `sane_init()`, and nothing in this repo sandboxes desktop scanning applications. The thing it replaces is not equivalent either -- `sane-airscan` is open source, built from source in nixpkgs with the standard hardening flags. The accurate statement is "the blob is confined to the desktop user's session", plus the fact that this session is root-adjacent.
- **Fix risk:** No cheap fix keeps the feature. In rough order of cost: (a) state this residual plainly in ADR-0003's Consequences instead of "one non-root backend" -- zero risk and probably the right call; (b) drop `libvirtd` from `users.users.lilijoy.extraGroups` in favour of a per-invocation grant, which is `docs/hardening.md` rule 6 territory anyway -- risks breaking `virt-manager` for the user and needs testing that VMs still start; (c) confine scanning under `bwrap`/`systemd-run` with network access limited to `192.168.1.166:54921` -- needs the scan application's file-save path punched through, and is a project rather than a tweak. Do not "fix" this by re-adding a firewall rule; it is an outbound-parsing problem, not an inbound one.

### F3 -- "no daemon, no listener" verified; "no udev rule" is not -- enabling brscan4 installs a vendor udev rule and puts the vendor binary on every user's PATH

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:51-59`; pinned nixpkgs `nixos/modules/services/hardware/sane.nix` (`services.udev.packages = backends`, `environment.systemPackages = backends`) and `pkgs/by-name/br/brscan4/{package.nix,udev_rules_type1.nix}`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** hardening / needed-used
- **Reachability:** Local only, and inert as configured. The installed rule (`49-brother-libsane-type1.rules`) matches `SUBSYSTEM=="usb"`, `ATTR{idVendor}=="04f9"` with vendor-specific interface class/subclass/protocol, and its only effect is `ENV{libsane_matched}="yes"`, which then triggers `sane.nix`'s own `setfacl -m g:scanner:rw` on that device node. Evaluated `users.groups.scanner.members` on torrent is `[]` and no user holds the group, so that ACL grants nobody anything; the printer here is on the network, not USB, so the rule never fires in normal operation.
- **Rule:** n/a
- **Finding:** Confirming the parts of the pre-review assumption that hold and correcting the one that does not. **Holds:** `services.saned.enable` evaluates `false`, so there is no `saned@` unit and no `systemd.sockets.saned` on `0.0.0.0:6566`; `hardware.sane.openFirewall` is `false`, so no UDP 8612; `connectionTrackingModules` is `[]`; the brscan4 NixOS module's entire `config` block is `hardware.sane.extraBackends`, one `environment.etc` entry and an assertion -- no unit, no socket, no setuid wrapper, no new user or group (the `scanner` group and the `/var/lock/sane` tmpfiles rule predate this change, since `hardware.sane.enable` was already `true` for airscan). **Does not hold:** `brscan4-0.4.10-1` appears in torrent's evaluated `services.udev.packages`, because `sane.nix` feeds `extraBackends` straight into it, and the package ships `etc/udev/rules.d/49-brother-libsane-type1.rules`. The same mechanism also puts the package into `environment.systemPackages`, so `brsaneconfig4` -- the vendor binary, wrapped with `LD_PRELOAD=libpreload.so` -- is on `PATH` for every user on the host. Neither is dangerous as configured, but both are facts the ADR's "bounded by" list asserts away rather than covers. Separately verified clean: the blob's `.so` is the only new file in `/etc/sane-libs`, a directory already on every session's `LD_LIBRARY_PATH` via `sane.nix`'s `environment.sessionVariables`; soname `libsane-brother4.so.1` collides with nothing, so that pre-existing global `LD_LIBRARY_PATH` does not become a library-shadowing vector.
- **Fix risk:** Nothing to fix in config. Suppressing the udev rule would mean abandoning `hardware.sane.brscan4` for a hand-rolled `extraBackends` + `environment.etc` pair, which is strictly worse.

### F4 -- `/etc/opt/brother` is produced by executing the vendor binary at build time; bounded by the nix sandbox, and the generated file holds nothing sensitive

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:56-59`; pinned nixpkgs `nixos/modules/services/hardware/sane_extra_backends/brscan4_etc_files.nix`, `pkgs/by-name/br/brscan4/preload.c`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A supply-chain adversary would have to have compromised the specific Brother `.deb` *before* its hash was pinned in nixpkgs -- the fetch is a fixed-output derivation pinned to `sha256-Gpr5456MCNpyam3g2qPo7S3aEZFMaUGR8bu7YmRY8xk=`, so substituting content after the fact is not available to them (the sibling `brother-udev-rule-type1` fetch is over plain `http://`, but is equally hash-pinned, so that is not a gap either). Given that, the build-time execution runs as a `nixbld` user inside the nix sandbox.
- **Rule:** n/a
- **Finding:** `brscan4-etc-files`'s `buildPhase` does genuinely execute the vendor's `brsaneconfig4` binary -- patchelf'd, and wrapped in an `LD_PRELOAD` shim that rewrites `open`/`open64`/`fopen`/`opendir`/`execvp`/`system` away from `/etc/opt/brother/...` into the store -- once per configured `netDevice`, to generate `brsanenetdevice4.cfg`. So vendor code runs on every machine that builds torrent's closure, not only when someone scans; that is a second execution context the ADR does not mention. It is well bounded: `nix.settings.sandbox` evaluates `true` on torrent and `brscan4-etc-files` is an ordinary (non-fixed-output) derivation, so the execution gets no network and no view of the host filesystem beyond its declared inputs. Worth one line in the ADR, not a reason to reject the change. The output is a single world-readable store path symlinked at `/etc/opt/brother/scanner/brscan4`, whose `brsanenetdevice4.cfg` reads `DEVICE=mfc-l2740dw , "MFC-L2740DW" , 0x4f9:0x320 , IP-ADDRESS=192.168.1.166` -- model and LAN IP, both already public in this repo. Nothing secret, so world-readability is correct here and no `mode`/`sops` treatment is warranted.
- **Fix risk:** n/a -- reporting only. If the ADR is amended, it should say build time *and* run time, not run time alone.

### F5 -- the firewall deletion is sound, but "removes the last inbound accept" and "retiring the accepted risk" are both overstated

- **File:** `docs/adr/0003-unfree-brscan4-blob-for-scanning-on-torrent.md:79-85`; `modules/nixos/brother-mfc-l2740dw.nix:76-84`; D2 above
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used (documentation accuracy)
- **Reachability:** n/a. Recorded because the ADR is what a future reader will consult to decide whether torrent's LAN NIC is closed, and the unqualified phrasing invites the belief that torrent accepts nothing inbound at all, which is a different and false statement.
- **Rule:** n/a
- **Finding:** The deletion itself verifies clean and the mechanism claims hold -- evidence in the checked-and-clean note below. Two wording defects. (1) "removes the last inbound accept" is true **of `enp8s0` only**: evaluated `networking.firewall.interfaces` on torrent still carries `tailscale0` with TCP 22 and TCP+UDP `1714-1764` (kdeconnect, deliberately tailnet-scoped by D9), `trustedInterfaces = ["waydroid0" "lo"]`, and `allowPing = true` applies host-wide, so ICMP echo is still accepted on the LAN NIC. The accurate claim is "nothing but conntrack `ESTABLISHED`/`RELATED` and ICMP echo is accepted on the LAN interface". (2) "retiring the accepted risk recorded as `...brother-mfc.md#F3`" implies a registry entry that does not exist: `docs/accepted-risks.md` has no printer/WSD/scanner entry at all, and `#F3` was a security finding marked **FIXED** on 2026-09-02 by narrowing the rule to the ephemeral range -- that plan's own docs-updater explicitly decided it was not accepted-risk material. The deletion retires a residual, not a registered accepted risk.
- **Fix risk:** n/a -- wording only.

### F6 -- the new comment block puts ~20 lines of rationale prose back into the module, reversing a trim made for the same reason on 2026-09-02

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:28-48` and `:76-84`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** n/a
- **Rule:** violates `docs/style-guide.md` "Why context: the plan file, not comments" ("Inline comments (beyond a citation pointer) are for mechanics/labeling only")
- **Finding:** The `>>> CLOSED SOURCE <<<` block carries the brscan4-vs-brscan5 evidence, the "deliberate, not an oversight" justification, the `models4/ext_11.ini` citation and the fleet-uniqueness claim -- all of which already live in ADR-0003 and are reached by the `# adr:` pointer a few lines below. The closing block at `:76-84` spends eight lines of prose explaining a rule that is no longer in the file. The style guide's own remedy is the shape already present: a terse label plus `# adr:`/`# plan:` citations. This matters past style for two reasons -- duplicated rationale is exactly how F1's false claim came to exist in two files instead of one, and the previous docs-updater pass on this same file (2026-09-02) trimmed an 18-line comment for precisely this rule, so the file is drifting back to where it was. The user's explicit request, "make sure to tag closed source in the config next to it", is satisfied by the banner plus the licence/provenance line alone.
- **Fix risk:** None, beyond losing at-a-glance context for a reader who will not open the ADR -- the tradeoff the style guide has already made.

**Checked and clean:** Reviewed the full working-tree diff (`modules/nixos/brother-mfc-l2740dw.nix`, `modules/profiles/PC.nix`, `modules/flake/hosts.nix`) plus the untracked `docs/adr/0003-*.md`, against the pinned `nixpkgs-unstable` rev `e4bae1bd10c9c57b2cf517953ab70060a828ee6f` -- reading `nixos/modules/services/hardware/sane.nix`, `.../sane_extra_backends/brscan4.nix`, `.../brscan4_etc_files.nix`, `pkgs/by-name/br/brscan4/{package.nix,udev_rules_type1.nix,preload.c}`, the realised store paths, and torrent's and thinkpad's merged config via `nix-instantiate --eval` on `builtins.getFlake`. **The firewall deletion is safe on the evidence, not on the claim:** torrent's rendered `networking.firewall.extraCommands` after the change contains only the `networking.nat` module's own `nixos-nat-*`/`nixos-filter-forward` teardown preamble, so nothing else in torrent's config contributed to the deleted block and removing it cannot orphan another service's rule; `networking.firewall.extraStopCommands` evaluates to the empty string on torrent both before and after, so there is no dangling stop-path counterpart and the stop path is unchanged; `allowedTCPPorts`/`allowedUDPPorts` and both `*PortRanges` on the default interface are `[]`, `hardware.sane.openFirewall` is `false` (so no UDP 8612 appears), and `connectionTrackingModules` is `[]`. `hosts/vps/configuration.nix:415` and `tests/vps-refused-connection-logging.nix:49` are a different host and a VM test for that host; they are untouched by this diff and share no option definition with torrent -- confirmed by a repo-wide grep that found no other `extraCommands`/`extraStopCommands` definition anywhere. The configuration still instantiates: `system.build.toplevel.drvPath` resolves, the brscan4 module's one-of-`ip`/`nodename` assertion passes, and the only warning is the pre-existing impermanence `/var/lib/nixos` uid/gid notice -- `scanner` is not among the affected groups, since it takes fixed gid 59 from `ids.gids`. **Containment holds:** thinkpad evaluates `hardware.sane.enable = false`, `brscan4.enable = false`, no `/etc/opt/brother` entry and no `enp8s0` rule, so blob and printer both stay on torrent. `services.avahi.enable` is `false` and no `services.avahi` definition exists repo-wide, so D9 is not undone, and the surface claim checks out: `sane-airscan` was the last thing on this host emitting WS-Discovery multicast, since its `airscan-wsdd.c` prober is avahi-independent, which is why D9's avahi removal had not already stopped it. **Dead-config sweep:** no `sane-airscan`/`airscan` reference survives anywhere in the repo outside one comment; `hardware.sane.extraBackends` is correctly left unset because the brscan4 module supplies it; the now-unused `pkgs-unstable` module argument was correctly dropped to `_:`; the rendered `dll.conf` contains `brother4` and no `airscan`; no secret, `sops.secrets` entry, capability grant or group membership is added, removed or left dangling by this change; no test or other module references this printer module. ADR-0003's remaining verifiable claims check out: brscan4's `models4/ext_11.ini` does contain `0x0320,313,1,"MFC-L2740DW",133,4`; nixpkgs pins brscan5 at `1.3.1-0`; `nixos/tests/brscan5.nix` and brscan5's `passthru.tests` both exist while brscan4 has neither; `meta.platforms` is `["i686-linux" "x86_64-linux"]`; `nixpkgs.config.allowUnfree` evaluates `true` on torrent both at `config.nixpkgs.config` and on the actual `pkgs` instance, so nothing was loosened to permit this. The dpi-ceiling and port-54921 measurements are hardware observations that cannot be reproduced from the repo -- they stand as the plan states them. Two things deliberately not claimed either way: whether the blob opens any socket of its own at runtime (it is stripped, so inspection cannot answer it -- the *config-level* "no daemon, no listening socket" claim is confirmed, the runtime one is not), and whether `brsaneconfig4 -q`-style network discovery still works after the deletion (it would not, if it broadcasts, since conntrack cannot match a unicast reply to a broadcast request -- but nothing in this config depends on it). Did not decrypt, open or otherwise touch any file under `secrets/`. Housekeeping, not a finding: this plan file carries a duplicated empty `## Progress` / `## Decisions (D)` / `## Gotchas (G)` trio at lines 125-132, below the populated ones.

_security finished 2026-09-16 -- see Findings above._

_security finished 2026-09-16T22:20:18Z (code 1f8d6c05beb6e632) -- see Findings above._

### F7 -- the `# adr:` citation form in the module comment was invented; the repo's existing form is the full `docs/adr/NNNN-slug.md` path

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:31` (was `# adr: 0003-unfree-brscan4-blob-for-scanning-on-torrent.md`)
- **Finding:** Bare-filename citation is a *plan-file* convention with a specific reason -- plans move between `todo`/`in-progress`/`done`, so a path form goes stale (`docs/skills/plan/reference.md`, "Why bare-filename citations"). ADRs never move, so the bare form buys nothing there, and it is worse in one respect: `plan-citations`' matcher only recognises a `YYYY-MM-DD-slug.md` shape, so `0003-...md` is invisible to it and a renamed or mistyped ADR citation is never reported. The only existing precedent in Nix is `modules/nixos/datasets.nix:4,66,129`, which writes `docs/adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md` in full, alongside the short inline `(ADR-0001)` form used at `datasets.nix:11,24`. Docs use a relative markdown link (`docs/architecture.md:324`, `docs/backups.md:11`).
- **What I changed:** kept the `# adr:` label (self-describing, and distinct from `# plan:`) but made the target the full path, so the citation matches `datasets.nix` and is greppable as a path. `modules/flake/hosts.nix` and `modules/profiles/PC.nix` keep the short `(ADR-0003)` inline form, which also matches `datasets.nix`.
- **Open, for the user:** neither form is written down anywhere. `docs/style-guide.md`'s "Why context: the plan file, not comments" section defines `# plan:` and says nothing about ADRs. One sentence there would settle it -- deliberately not added here, since choosing the fleet's citation convention is not a docs-pass call.

### F8 -- `docs/accepted-risks.md` has no printer entry, and the brscan4 residual is the first thing about this device that fits the file's own admission test

- **File:** `docs/accepted-risks.md` (section 1, AR-1..AR-8); F2 above; `docs/adr/0003-unfree-brscan4-blob-for-scanning-on-torrent.md` ("Consequences", first bullet)
- **Finding:** F5 established that `...brother-mfc.md#F3` was **fixed**, not accepted, and the 2026-09-02 docs-updater pass explicitly decided the WSD firewall rule was "a separate, already-fixed, narrowly-scoped rule tracked entirely in this plan, not a fleet-wide accepted risk". That reasoning does not carry over to this change. F2 is a MEDIUM that was resolved by **writing it down**, not by changing config -- the exposure is still there and is meant to be. That is exactly this file's stated admission test: "a risk that was found, understood, and left in place on purpose", recorded so a later pass "can tell 'decided against' apart from 'never noticed'". Today it lives in an ADR's Consequences and in a plan that will freeze, and neither is where a future audit looks for the fleet's live acceptances. `docs/threat-model.md` says the same under "Using it": before accepting a risk, write it into `accepted-risks.md` with the boundary it sits on -- not in a commit message, and not only in an audit report.
- **Why I did not just add it:** every AR in section 1 is an acceptance the *user* made (AR-8: "confirmed by the user 2026-09-03"), and section 2's whole design makes an answered decision the gate for moving into section 1. The user chose brscan4, but chose it before F2's binary-hardening measurements existed, so "the user has accepted this residual" is not something this pass can assert on their behalf. Draft below, in the shape the file already uses (it has no severity scheme; severity stays with the finding). Add as `AR-9` if the user confirms.

```markdown
### AR-9 -- Scanning on torrent loads an unhardened closed-source parser into the desktop session

**Sits on:** [threat model](threat-model.md) 4.3, adversary A4 ·
**Evidence:** [`adr/0003-unfree-brscan4-blob-for-scanning-on-torrent.md`](adr/0003-unfree-brscan4-blob-for-scanning-on-torrent.md);
`2026-09-16-switch-torrent-scanning-to-brother-s-closed-source-brscan-driver-for.md#F2`

`hardware.sane.brscan4` puts Brother's `libsane-brother4.so` -- unfree,
binary-only, stripped, no RELRO, no stack protector, no FORTIFY, and
importing `strcpy`/`sprintf`/`popen` -- into whatever process calls
`sane_init()`. SANE backends are `dlopen`ed in-process, so on torrent that
is a scan application inside `lilijoy`'s desktop session, and `lilijoy`
holds `wheel`, `docker` and `libvirtd`. Its input is whatever answers at
`192.168.1.166:54921`, which nothing authenticates.

**Why accepted:** the driverless backend it replaces caps at 300 dpi, and
the higher resolutions are the reason the change was made. The decision,
the rejected alternatives and the full cost list are ADR-0003.

**What bounds it today:** reachability, not the blob. brscan4 dials out
and nothing listens -- no daemon, no socket, no setuid wrapper -- so an
adversary needs to already be on torrent's LAN segment, answering at the
printer's address, while the user scans. `users.groups.scanner.members`
is empty, and thinkpad enables none of this.

**What would change the answer:** torrent handling untrusted network
neighbours, scanning moving to a service account or a second host, or
this becoming the path through which the `libvirtd`/`wheel` grants matter
(they are `hardening.md` rule 6 territory in their own right). The
mitigation then is confining the scan application -- `bwrap`/`systemd-run`
with egress limited to the printer -- not a firewall rule: this is
outbound parsing, not an inbound hole.
```

### F9 -- the `netDevices` comment claimed the attribute name is what `scanimage -L` shows, contradicting ADR-0003's own device-name consequence

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:37-40`
- **Finding:** The comment read "attr name becomes the device's `name=` field and is what `scanimage -L` shows". Read from the pinned module: `brscan4.nix`'s `netDeviceOpts` defaults the submodule's `name` to the attribute name, and `brscan4_etc_files.nix` feeds it to `brsaneconfig4 -a name="..."`, which writes that friendly name into `brsanenetdevice4.cfg`. Nothing on that path sets the SANE device string -- and ADR-0003's own Consequences say the device string is `brother4:net1;dev0`. The two records disagreed, and the ADR is the one backed by a live measurement.
- **What I changed:** the comment now says the attr name becomes `brsaneconfig4`'s `name=` in `brsanenetdevice4.cfg`, and explicitly *not* the `scanimage -L` device string. The `ip=` vs `nodename=` half was already correct and is unchanged.

### F10 -- torrent's generated inventory still advertises custom firewall rules that are now only nixpkgs' own NAT teardown preamble

- **File:** `hosts/torrent/README.md` (inventory block, Firewall section); `scripts/doc-host.sh:94-100,257-259`
- **Finding:** Re-ran `scripts/doc-host.sh torrent`; the block updated (`sane-airscan` out, `brscan4` in, plus an unrelated `openssl` that had already drifted in). The generator still emits "plus custom `networking.firewall.extraCommands` iptables rules -- see the host's configuration.nix, not captured here", because it flags on a non-empty rendered `extraCommands`, and torrent's is non-empty even with this repo's only rule deleted: `networking.nat` contributes its own `nixos-nat-*`/`nixos-filter-forward` teardown preamble. The line now sends a reader to `hosts/torrent/configuration.nix` for a rule that no longer exists and was never in that file -- it lived in `modules/nixos/brother-mfc-l2740dw.nix`. Not hand-fixable: the text is inside the generated block. It is a `doc-host.sh` defect rather than a defect in this change, and it will read the same on any host that enables NAT.
- **Not fixed here:** tightening the predicate (flag only when the rendered value carries something beyond the NAT preamble) is a script change, and this pass is comments and docs only.

### F11 -- removed the ADR's account of its own drafting

- **File:** `docs/adr/0003-unfree-brscan4-blob-for-scanning-on-torrent.md:18-19` (was "It is *not* the fleet's first unfree package, **and an earlier draft of this ADR wrongly said so**"), and the last Consequence bullet (was "It is a general setting, **not a firmware one** -- `hardware.enableAllFirmware` is a separate option two lines below it")
- **Finding:** Both phrasings only parse as corrections of the pre-F1 draft. An ADR is the permanent statement of a decision; that a draft of it once claimed otherwise is review history, and that history already lives in F1 and G2 of this plan. Leaving it in means the next reader spends attention on a claim nobody is making. Same for "not a firmware one" -- the useful fact is that `allowUnfree` and `hardware.enableAllFirmware` are separate settings, not that a draft conflated them.
- **What I changed:** both sentences trimmed to the fact they carry, nothing substantive dropped. `modules/profiles/default.nix:188` re-verified as the `allowUnfree` line (`hardware.enableAllFirmware` is at `:191`).

### F12 -- the `## Progress` list cited a plan file that does not exist, breaking `plan-citations`

- **File:** this plan, `## Progress` (was "`docs-updater` (runs last now -- see `<2026-09-16>-run-docs-updater-last-so-it-documents-the-post-review-final-state.md`)" -- the date deliberately mangled here so `plan-citations` does not re-report the dead citation from this finding)
- **Finding:** No such file exists under `docs/plans/todo|in-progress|done|rejected/`, and nothing else in the repo references that slug, so it is a citation to a plan that was never created rather than one that moved. `plan-citations` fails on it -- exit 1, "no such plan file under docs/plans/*/" -- and `verify-ladder` runs `plan-citations` on every pass, so this was the one thing in the tree that would have reported red. Caught only because this pass re-ran the checker; the ordering claim the citation was carrying ("docs-updater runs last") is a workflow convention, not something that needed a plan file behind it.
- **What I changed:** dropped the citation and stated the ordering inline, and ticked the box now that this pass has run. `plan-citations` is green afterwards, with every other citation in the tree resolving.

**Checked and clean (docs-updater):** Swept the repo for surviving assertions that torrent scans over sane-airscan/WSD/eSCL, or that the `enp8s0` ephemeral-range accept is live. `docs/hardening.md`, `docs/threat-model.md` and `docs/accepted-risks.md` contain no printer, scanner, WSD, airscan or sane reference at all (grepped for each term separately). `docs/architecture.md:50` lists `brother-mfc-l2740dw` among torrent's modules, still exactly true, and nothing else in that file touches the printer. `AGENTS.md` needs no change: its docs table already describes `docs/adr/` as "*why* a shape was chosen and which alternatives were rejected", which covers a hardware/driver decision without enumerating categories, and `docs/procedures/updating-documentation.md` reserves AGENTS.md edits for a doc moving, a command changing, or a new hard-confirm rule -- none of which happened. That procedure doc itself needed no edit; its host-inventory clause is what drove the `doc-host.sh` re-run above. The only stale string found repo-wide outside frozen plans was `sane-airscan` in torrent's generated package list, now regenerated. `docs/audits/2026-08-26/` describes the *pre-2026-08-27* printer (`implicitclass://Brother_MFC_L2740DW_series`, `brlaser`, avahi still present) and is a dated point-in-time record by design -- untouched, and not misleading read as one. Two frozen plans under `docs/plans/done/` read as live where they are not: `2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md` (D1's "no Brother blob (brscan4) needed", and F3's narrowed firewall rule, now deleted); `2026-09-03-ensure-printers-service-boot-race-on-torrent-order-after-network.md` is unaffected in substance, since the `ensure-printers` ordering it added is untouched by this change. Neither was edited (ADR-0002); the supersession is recorded here in "Original plan" and in ADR-0003's "The problem this solves", which is the intended direction of reference. The module's two surviving `...brother-mfc.md#F1`/`#F2` citations still describe what they are attached to -- host-scoping and network-supplied identity -- and both anchors resolve. `hosts/torrent/README.md`'s hand-written prose (Hardware, Backups) says nothing about the printer or scanner; the printer is absent from that Hardware list, which predates this change and was left alone rather than expanded on the user's behalf.

_docs-updater finished 2026-09-16 -- see Findings above._

_docs-updater finished 2026-09-16T22:36:07Z (code cac0bcb3505c5370) -- see Findings above._
