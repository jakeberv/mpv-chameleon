# Compatibility

## Locally verified

- Apple M1 Max MacBook Pro, built-in Liquid Retina XDR display.
- ASUS VS247 external SDR display.
- macOS 15.7.9; mpv 0.41.0; libplacebo 7.360.1; FFmpeg 9.0.2.
- `vo=gpu-next`, `gpu-api=vulkan`, `gpu-context=macvk`.
- VideoToolbox for the real H.264 SDR film and HEVC HDR10 clip.
- Live moves via mpv non-Space fullscreen between physical screens, direct starts,
  and same-process source changes; actual Metal/swapchain validation.

See [verification](verification.md) for observed results and precise limits.
The installed prototype was inspected but not replaced during development.

## API and build requirements

The potential/reference EDR APIs and localized display names require macOS
10.15+. This is an **API floor**, not a tested oldest OS. The helper's source uses
Swift 5.3+ (`@main`); use a working Xcode Command Line Tools compiler and SDK.
Your chosen mpv distribution can require a newer OS. Build the helper on the Mac
where it will run. The installer detects mpv 0.41+ and a macvk-capable build.
The 0.41 display-identity format was verified against pinned upstream source.
Newer mpv builds are expected to work only while the documented contracts hold.

## Unverified or outside the supported policy

- Intel Macs, other Apple Silicon models, other macOS versions or mpv distributions.
- Different monitors, docks, cables, mirroring, eGPUs and remote/virtual screens.
- `vo=gpu`, OpenGL, displayvk, libmpv embedding and non-macOS systems.
- ICC auto/manual profiles, inverse tone mapping and strict=no.
- HLG HDR output, HDR10+ and Dolby Vision fidelity/dynamic metadata.
- Reference-preset changes, unplug/replug, display rearrangement, sleep/wake,
  manual dragging/straddling responsiveness and native macOS Space fullscreen.
- Calibrated gamma, luminance, gamut/white-point fidelity and flash-free transitions.

The architecture handles events, ambiguity, periodic refresh and conservative
fallbacks for these situations where possible, but that is not hardware evidence.
A potential EDR ratio does not establish an external display's active HDR mode.
Duplicate model+serial identifiers cannot always be distinguished. Unknown
identity or metadata defaults to SDR, which can reduce highlights until resolved.
