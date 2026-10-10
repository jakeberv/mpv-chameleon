# mpv-chameleon design

Your video adapts to your display.

Build a small macOS utility using a compiled Swift/AppKit helper and one mpv Lua
script. The user-supplied task is the product specification; this document
records implementation choices. Build in this new, empty repository. Implement
inline as requested. No changes to the user's installed configuration without
approval. GPL-3.0-or-later and public GitHub publication were approved by the
project owner on 2026-10-10. The Lua architecture is unchanged.

## Boundaries

Target mpv 0.41+, gpu-next / vulkan / macvk, macOS 10.15+ APIs; availability of
an mpv distribution may impose a higher OS floor. No network in runtime or
installer, no daemon, IPC, bundled shaders, binaries, or private media. Only
source-built helpers and chameleon.lua are installed. No mpv.conf edits.

## Identity and helper

`helpers/DisplayModel.swift` owns pure validation/serialization and selection.
`helpers/display-edr.swift` enumerates fresh NSScreen instances once and exits.
The installed executable is `helpers/mpv-chameleon`. JSON schema 1 includes
local display IDs, names, geometry, potential/current/reference EDR, and a
selection result when called with `--display NAME`. The helper reconstructs
mpv 0.41's name plus CGDisplaySerialNumber identity internally; it does not
print serials. Exact unique identity wins. A name without a serial can match
only one screen. Duplicate identities, absent displays, invalid capabilities,
and malformed data are SDR. Do not guess using unrelated display IDs.

## Controller

`scripts/chameleon.lua` owns async requests, a generation counter, debounce,
one in-flight helper, a deadline, and a slow capability refresh. Observe
native display-names, vo-configured, fullscreen, and playback lifecycle.
Discard stale callbacks and immediately query the latest display. Repeated
observations/unchanged modes do not rewrite properties. Retry failures with
bounded polling and deduplicate diagnostics. Stop helper work while idle.

Snapshot options before changes and use SDR at startup/on-load. Override only
color options needed for a consistent SDR output, and restore original target
primaries, transfer, gamut, peak and tone mapping for the HDR-capable branch.
Source signaling on HDR-capable screens does not force SDR into HDR. Preserve
strict signaling; unsupported backends, ICC overrides, inverse tone mapping,
and strict=no are outside the supported automatic policy. Refuse clearly and
leave their configuration alone. Restore only still-owned settings on disable
or shutdown. Runtime profiles changing owned settings need explicit rebaseline.

Native validation selected hint=yes, mode=target, prim=bt.709, trc=srgb,
peak=auto. The no-hint experimental route failed a playlist restoration
verification and is not shipped. Potential EDR is a
capability threshold, never converted to invented nits. A Lua hook reduces
startup risk but cannot prove a frame-atomic surface change.

## Installation

Bash 3.2, explicit --config-dir plus mpv path precedence, --dry-run, --verbose,
--help. Build and validate before touching existing files. Serialize installs
with a directory lock. Check symlinks and permissions. Transactionally install
fixed paths with hashes in a manifest; backup replaced files. Recognized legacy
auto-hdr.lua is disabled via backup on migration so only chameleon.lua autoloads.
Unknown legacy scripts require an explicit migration flag. Uninstall removes
only hash-matching owned files, preserves edits and all backups, and does not
automatically reactivate the legacy prototype. Document deliberate rollback.

## Verification and release

Lua mock tests exercise real script callbacks/properties. Swift tests cover
selection/serialization without hardware. Installer tests use temporary paths
and injected executable fixtures via PATH. Compile/run native helper locally;
real playback tests use isolated configs, legitimate local video/synthetic
fixtures, private logs. Inspect actual swapchain/Metal output, source matrix,
transitions, fullscreen and counters; distinguish observed from untested.
CI runs syntax/static checks, Lua and shell tests, macOS build and pure tests.
Prepare v0.1.0 release notes and local git history; ask final account/visibility/
license/publication confirmation only once the result is reviewable.

## Source-aware addition and acceptance gates

User clarification makes the four source/display combinations and live transitions
release-blocking. Display capability is independent of `video-params` source
classification. Only PQ+BT.2020 with a uniquely capable display selects HDR10;
SDR stays SDR even if the original config contains HDR-specific targets. HLG and
unknown/contradictory metadata use SDR in this version. SDR tone-mapping preference
is preserved. Test actual Metal output for HDR→SDR→HDR moves, SDR→HDR-capable→SDR
moves, direct startup on both screens, same-instance file changes and metadata
fallbacks. The installed prototype remains untouched until separate approval.
