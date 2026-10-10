# Configuration

Put options in `script-opts/chameleon.conf` in the active mpv config directory.
The installer does not create or overwrite this file. See the commented
[example](../examples/chameleon.conf). Command-line equivalents use
`--script-opts=chameleon-debug=yes` or comma-separated `chameleon-KEY=VALUE`.

| Option | Default | Meaning |
| --- | --- | --- |
| `helper` | `~~/helpers/mpv-chameleon` | Executable path; passed as an argv element |
| `debug` | `no` | Source/capability/query diagnostics |
| `poll_interval` | `2` | Check current display property every 1–60 seconds |
| `refresh_interval` | `15` | Fresh capability query every 5–300 seconds |
| `timeout` | `5` | Abort helper after 1–30 seconds |
| `debounce` | `0.10` | Coalesce events over 0.05–1 second |

In mpv's console:

```text
script-message chameleon-refresh
script-message chameleon-disable
script-message chameleon-enable
```

`disable` restores values still owned by the script. To apply a new color profile,
disable first, change the profile/settings, then enable to capture a new baseline.
If another script changes an owned value while active, chameleon disables itself
and preserves that edit. Automatically fighting other color-management scripts
is not supported. Playlist/file transitions do not redefine your original
baseline from temporary SDR overrides.

Managed options: target primaries, transfer, gamut, peak, hint mode, hint enable,
and tone mapping. The HDR10 branch restores the original rendering options while
using source signaling. The SDR branch enforces a coherent sRGB target and clears
HDR peak/gamut overrides. It restores the original tone mapping for SDR sources;
HDR/unknown sources use BT.2390. Audio, scaling, subtitles, shaders, and other
unrelated preferences are never touched.

ICC auto/manual profiles, inverse tone mapping, unsupported renderers and
`target-colorspace-hint-strict=no` are rejected. Custom LUT/color options beyond
these checks may also invalidate color assumptions; use a minimal config when
diagnosing. `--no-config` changes mpv's `~~/` expansion, so explicitly load the
script and pass an absolute helper path when using it.
