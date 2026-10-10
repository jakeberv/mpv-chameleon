# Architecture

The core has two components: `scripts/chameleon.lua` and the executable compiled
from `helpers/DisplayModel.swift` plus `helpers/display-edr.swift`. The installer
names the executable `helpers/mpv-chameleon`. It does not install source inside
mpv's autoload directory or require IPC for normal playback.

## Display identity

In mpv 0.41, `VOCTRL_GET_DISPLAY_NAMES` returns the current NSWindow screen's
unique name. Its suffix comes from **CGDisplaySerialNumber**, not NSScreenNumber.
The helper obtains NSScreenNumber to call CoreGraphics, normalizes a trailing
numeric suffix in the localized name, then compares the resulting name/serial
identity. This is an independent implementation of a data-format contract;
upstream source is referenced, not redistributed.

Sources: [mpv common.swift](https://github.com/mpv-player/mpv/blob/v0.41.0/video/out/mac/common.swift),
[mpv identity formatting](https://github.com/mpv-player/mpv/blob/v0.41.0/osdep/mac/swift_extensions.swift),
[NSWindow.screen](https://developer.apple.com/documentation/appkit/nswindow/screen).

An exact match must be unique. Identical models with distinct serials can be
distinguished. Duplicate or zero serials can remain ambiguous and get SDR.
Bare names match only when unique; a mismatched serial never falls back to a
model-name guess. CoreGraphics IDs are local query metadata, not saved settings.
Screen geometry is emitted for diagnostics, not used to invent a match.
AppKit normally chooses the screen containing most of the window. mpv exposes
one effective screen on macOS, so the script does not blend policies across
monitors. Offscreen/unknown windows use SDR. Mirroring and remote displays need
separate physical validation.

## Helper protocol

The helper takes `--display NAME` as a separate argument. With no arguments it
enumerates displays. It writes one JSON object with `schema_version: 1`,
`displays`, and (when requested) `selection`. Each display has a local `id`,
`name`, `frame`, `potential_edr`, `current_edr`, `reference_edr`, and
`hdr_capable`. Invalid nonfinite values become JSON null. Selection contains
`status` (`exact`, `name`, `unknown`, or `ambiguous`) and an optional `display_id`.
Serial numbers are used internally and omitted from JSON and normal script logs.

Exit codes: 0 for a successful query, including no visible screens; 64 for bad
arguments; 69 for an unsupported OS; 70 for serialization failure. Missing
NSScreenNumber records are skipped. No screens may indicate a headless session
or a sandbox with no WindowServer access; it is not proof that the machine has
no monitors.

## Independent source policy

The Lua controller reads `video-params`, independently of helper output. PQ plus
BT.2020 permits the HDR10 branch only when the matched display's potential EDR
exceeds 1. Recognized SDR transfer functions use SDR; HLG, unrecognized metadata,
and incomplete/contradictory PQ metadata also use SDR in this release. This
classification sees mpv's effective decoder metadata, which may include guesses.
It cannot establish that a file contained mastering metadata or detect every
form of Dolby Vision carried in an HDR10-compatible stream.

## Concurrency and lifecycle

Display/source/fullscreen changes invalidate a generation. A short debounce
coalesces bursts; at most one helper runs. Its callback must still own the
pending request and match both the generation and active display. A→B→A is
therefore distinguishable from an unchanged A. A stale result is discarded and
the latest state is queried. The helper deadline aborts hung queries; late
callbacks cannot apply output. Failures select SDR and retry on the bounded
refresh interval. Repeated identical diagnostics are suppressed.

Display observations plus a two-second property check detect missed events;
a fifteen-second fresh helper query handles capability changes with the same
name. Queries stop when video output is not configured. A fresh helper process
also avoids caching NSScreen capability objects through sleep or reconnection.
Multiple mpv processes have separate controllers. Known legacy autoload files
prevent startup; a per-player user-data owner prevents ordinary duplicate copies.
Arbitrary scripts explicitly loaded elsewhere remain the user's responsibility.

## Property ownership

Capture the seven managed properties before modifying them. SDR sets a coherent
sRGB target, clears HDR-specific gamut/peak overrides, and selects BT.2390 only
for HDR/unknown inputs; ordinary SDR retains the original tone-mapping preference.
The HDR10 branch restores original primaries, transfer, gamut, peak, and tone
mapping, then enables source signaling. Unchanged values are not rewritten.
An external edit to a managed property disables automation and preserves that
edit. Explicit re-enable captures a new baseline. Shutdown/disable restores
only values still owned by the controller.

A synchronous on-load hook applies SDR before decoding. Display confirmation
occurs asynchronously after a window exists. mpv has no atomic multi-property
surface update exposed to Lua. Signaling is disabled before intermediate color
changes and applied last. A setter failure cannot be reported as success; it
leaves signaling disabled and reports an incomplete update. This does not prove
absence of a single transient wrong frame on every mpv/macOS build.
