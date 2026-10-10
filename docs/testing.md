# Testing

## Automated checks

Install Lua/luac, ShellCheck and Python 3. On macOS, install Xcode Command Line
Tools. Run from the checkout:

```sh
./tools/check.sh
```

Lua tests execute the actual script with an mpv boundary double. They cover
source and display classification, malformed output, helper failure/timeout,
A→B→A races, transient recovery, option restoration, profile conflicts, startup,
idle behavior and error deduplication. The double limits subprocess parameters
to the contract caught by native testing; it does not prove rendering behavior.

Pure Swift tests cover JSON, escaping, invalid EDR, serial-vs-display-ID matching,
duplicate identities, empty screens and Unicode. The native helper is compiled
and exercised on macOS; empty display arrays are valid on headless runners.

Shell tests use private temporary directories and fake dependencies to exercise
fresh install, upgrade, migration, dry-run, edited files, partial recovery,
compiler failure, unavailable mpv, symlinks, locking, rollback and GNU/BSD stat
behavior. The actual Swift compiler/installer combination is checked locally.
Repository checks inspect tracked files for binaries, media, private paths,
credential-shaped strings and broken local documentation links.

CI runs portable checks on Ubuntu and the helper build on macOS. Hosted runners
do **not** establish physical HDR playback. No workflow publishes automatically.

## Release-blocking physical matrix

Connect an HDR-capable display and an SDR display in the logged-in macOS session.
Provide a legitimate HDR10/PQ/BT.2020 clip and an SDR reference film. The harness
uses copies of the new script/helper in a temporary config; it never replaces an
installed prototype. It plays muted audio through the normal audio backend.
Python 3, FFmpeg and the supported mpv/Swift toolchain are required.

```sh
python3 tests/integration.py \
  --hdr-video "/path/to/HDR10.mp4" \
  --sdr-video "/path/to/SDR-film.mp4"
```

The output defaults to ignored `.build/integration/`. Raw logs include private
media paths and possibly display serials from mpv. Never commit or upload them.
The socket exists only inside a private temporary directory. No core feature
requires IPC. The test harness closes only the players it creates.

The harness discovers screen indices from the helper, verifies the active
screen by identity, and checks **actual selected Vulkan and Metal colorspaces**:

1. HDR10: HDR display → SDR display → HDR display, without restarting playback.
2. SDR film: SDR display → HDR display → SDR display, with no PQ surface at any point.
3. Direct startup of SDR and HDR10 on each display.
4. HDR→SDR→HDR file changes within the same mpv process on each display.
5. Synthetic missing metadata, contradictory PQ/BT.709, HLG and wide-gamut SDR,
   tested on both screens. Each intentionally uses SDR in this version.

The live movements use mpv's `fs-screen` option and `native-fs=no` fullscreen
mode. Short waits allow macvk's option cache/window state to settle before the
next command. Tests do not count a requested move as successful unless the
helper-selected active ID and the Metal output both match. Native macOS Space
animation and manual dragging need separate observational checks.

To test a specific revision, run from that checkout. The final implementation
always uses explicit SDR target signaling.
The helper enumeration must agree with mpv's screen-index ordering on the build
being tested; a mismatch causes failure rather than a guessed pass.

## Manual visual and robustness checks

Play normally with debug logging. Drag a partially overlapping window slowly and
rapidly between screens. Repeat fullscreen, unplug/replug, display arrangement
changes, and wake-from-sleep when convenient. Inspect the picture and settled
playback after each change; compare SDR brightness/gamma, clipping and dark
scenes against a trusted reference. Test two independent players.

Watch frame-drop and decoder-drop counts, audio underruns, sustained stutter,
blank video, and excessive pipeline rebuilding. Transition drops must be
reported separately from settled playback. A zero count during a short sample
is not a zero-drop guarantee. Logs do not measure invisible flashes, calibration,
or perceptual color fidelity. Do not approve a release solely from a script's
`output policy applied` log line.
