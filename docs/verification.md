# Verification record — 2026-10-10

This records observed local results, not promises of universal compatibility.
The existing installed `auto-hdr.lua`, helper, mpv.conf and input.conf were
inspected read-only and preserved. New code was compiled/installed in temporary
configurations for testing.

## Automated and native build checks

- Pure Swift model: 24 assertions passed, including JSON escaping, invalid EDR,
  duplicate names/serials, bare-name matching, Unicode and missing displays.
- Lua controller: 36 tests passed, covering source/display policy, async races,
  invalid output, timeout recovery, lifecycle, option ownership and restoration.
- Installer/uninstaller: 18 scenarios passed, including migration backups,
  edited/unowned files, interrupted upgrades, paths with spaces and safe removal.
- Bash syntax, ShellCheck 0.11.0, repository privacy/local-link checks, and
  all nine official external documentation link checks passed.
- Swift 6.2.4 compiled the real helper and the installer produced a working native
  executable in an isolated config directory. Argument errors return status 64.
- Independent read-only code review completed. One stale-timeout responsiveness
  issue was fixed with a failing-then-passing regression test.
- CI covers Ubuntu and macOS. Hosted results are tracked separately from the
  local evidence below; see [release preparation](releasing.md). A public release
  requires successful hosted checks for its exact source commit.

## Physical source/display matrix

Tested on Apple M1 Max / macOS 15.7.9, built-in Liquid Retina XDR plus ASUS VS247,
mpv 0.41.0, libplacebo 7.360.1, FFmpeg 9.0.2, gpu-next/vulkan/macvk.
The helper observed potential EDR ratios of 16 and 1. Test materials were an
existing 4K/60 HEVC HDR10 clip and an existing 1080p H.264 SDR film; neither is
redistributed. Synthetic FFV1 clips exercised metadata edge cases.

The explicit SDR signaling route (hint=yes, mode=target) passed **21 physical stages**:

| Case | Observed renderer result |
| --- | --- |
| HDR10 on XDR → SDR → XDR | ITUR_2100_PQ → SRGB → ITUR_2100_PQ |
| SDR film on SDR → XDR → SDR | SRGB throughout; no selected PQ surface |
| Direct starts: SDR and HDR10 on either screen | SDR stays sRGB; HDR10 uses PQ only on XDR |
| Same-process HDR→SDR→HDR files, XDR screen | PQ → sRGB → PQ |
| Same-process HDR→SDR→HDR files, SDR screen | sRGB throughout |
| Missing source tags, both screens | sRGB (mpv inferred ordinary SDR metadata) |
| Contradictory PQ/BT.709 tags, both screens | sRGB |
| HLG tags, both screens | sRGB conversion, deliberately no HDR claim |
| Wide-gamut SDR tags, both screens | sRGB, with intentional gamut limitation |

HDR stages verified a **selected** `VK_COLOR_SPACE_HDR10_ST2084_EXT` configuration
and `ITUR_2100_PQ` Metal layer. SDR stages verified `SRGB` and an SDR target transfer.
The test checked active display identity, not merely requested screen settings.
Moves used mpv's non-Space fullscreen on continuously playing windows. Direct
startup and playlist tests used windowed playback.

Two complete explicit-signaling runs passed the 21-stage rendering gates. The
first recorded zero frame/decoder drops at every sampling point and no audio
underrun messages. The final exact-candidate run recorded three renderer drops
in one 1.5-second interval following SDR→XDR movement and one CoreAudio underrun
at that transition (two log lines: detection and restart). Decoder drops were
zero. Later stages added no drops. A focused follow-up sampled ten further
seconds after the same move: no frame/decoder drops and no audio underrun logs.
This does not establish a general zero-drop or seamless-audio guarantee.

Audio ran muted through the normal backend; audible playback was not judged.
The test used mpv's default audio buffering. The optional example's larger audio
buffer is not installed automatically. Earlier exploratory software-decoding /
Space-transition attempts recorded up to 18 frame drops and had unreliable test
window movement. No changes to unrelated user playback preferences were made.

Ten native helper invocations measured 45.5 ms median / 59.7 ms maximum elapsed
time in the local GUI session. These are wall-clock measurements, not CPU-use
percentages. Normal capability queries occur every 15 seconds plus display/source
events, with no persistent native process.

## Interpretation and remaining checks

The successful experiment supports making explicit SDR target signaling the
default on this tested stack. The experimental no-hint comparison passed its
first 12 stages but failed the return to HDR after an SDR file on the XDR screen:
the Vulkan surface selected PQ while the log did not confirm a Metal transition
back from sRGB. This is a failed verification, not a calibrated diagnosis of
the compositor. The no-hint option was removed from v0.1.0 rather than shipping
a route that failed a release gate.
Source-based HDR signaling was retained because no calibrated target luminance
was measured. No EDR ratio was turned into guessed nits.

Native Space transitions and manual dragging were not established by the final
harness. Sleep/wake, unplug/replug, duplicate physical monitors, multiple players,
other hardware/OS builds, and visual/instrument color accuracy remain unverified.
A Lua on-load hook reduces startup risk; logs do not prove absence of every
transient wrong frame or visible flash. HLG synthetic metadata tests establish
SDR policy/signaling only, not perceptual HDR compatibility.

Raw logs and numeric source/output snapshots remain in ignored `.build/` output
on the development machine. They may contain private paths and mpv display
serials and must not be included in source releases. The reproducible command
is documented in [testing](testing.md).
