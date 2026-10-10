# Troubleshooting

## Helper will not compile

Run `swiftc --version` and `xcode-select -p`. Install/select Xcode Command Line
Tools (`xcode-select --install`) and retry. The installer prints compiler errors
and leaves the previous installation intact. Do not download a random helper
binary or run the installer with sudo.

## Display not detected

Run the installed `helpers/mpv-chameleon` directly. An empty display array may
mean the process cannot access the GUI login session (for example SSH, CI, or a
sandbox). Test in the logged-in desktop session. Unknown/ambiguous identities
use SDR. Two identical model/serial pairs cannot be uniquely resolved. Do not
replace the serial suffix with a hard-coded CoreGraphics ID.

## HDR does not activate

Check `mpv --version`, `mpv --gpu-context=help` and the three required renderer
options. Enable `--script-opts=chameleon-debug=yes`. Confirm both PQ/BT.2020 video
metadata and an EDR-capable matched display. HLG intentionally uses SDR. Check
macOS display mode/preset, brightness and external-display HDR settings.
A capability ratio alone does not establish active HDR mode.

Check for `auto-hdr.lua` in autoload or a duplicate `--script` argument. Use
`--migrate-legacy` only after inspecting the backup procedure. Restart mpv.
ICC profiles, `strict=no` and inverse tone mapping disable automatic handling.
A user-configured SDR `target-trc` is restored in the HDR branch and can prevent PQ.

## Washed-out HDR or an SDR monitor receiving PQ

Inspect actual renderer logs, not only the script label. The required lines are
`Picked surface configuration` and `Metal layer colorspace changed`. An available
formats listing containing PQ is not proof of PQ output. HDR10 on SDR should
show a selected SDR surface and `SRGB`; on an HDR display it should show selected
HDR10/ST2084 and `ITUR_2100_PQ`. SDR films should never select PQ on either display.

Use an isolated minimal configuration to rule out other color scripts, ICC,
LUTs, profiles and forced targets. The older no-hint route is not offered because it did not pass the complete
native restoration gate.
Stop and report a reproducible mismatch with sanitized source metadata and logs.

## Unsupported options or backend

Use mpv 0.41+ with gpu-next/vulkan/macvk. The script checks effective runtime
backend and required properties. The installer verifies build capabilities;
it does not silently rewrite renderer preferences. An incomplete property update
logs an error and disables HDR signaling; do not count it as successful switching.

## Monitoring changes

```sh
mpv --script-opts=chameleon-debug=yes --log-file=/a/private/path/chameleon.log /path/to/video.mkv
```

Try `script-message chameleon-refresh` in the mpv console. Capability changes
with an unchanged name are normally picked up within 15 seconds. The on-load
SDR state and event debounce reduce startup risks but cannot promise a frame-
atomic or flash-free transition. Brief transition-related drops may occur.

## Configuration changed externally

Chameleon yields when a managed option is edited. Disable automation before
applying a profile, then re-enable to capture its effective settings. This avoids
mistaking temporary SDR overrides for the user's original HDR choices.

## Stale lock or rollback

See [installation](installation.md). Never remove a lock while another install
or uninstall is running. Preserve transaction originals after power loss. The
uninstaller deliberately leaves edited scripts and all backups intact; remove
an edited script from autoload yourself before restoring the old prototype.
