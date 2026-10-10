# Color handling

Display capability and source format answer different questions. A display can
support HDR while the current video remains SDR. mpv-chameleon requires both a
uniquely matched HDR-capable display and effective PQ/BT.2020 source metadata
before selecting the HDR10 output branch.

## EDR values

Apple's [potential EDR](https://developer.apple.com/documentation/appkit/nsscreen/maximumpotentialextendeddynamicrangecolorcomponentvalue)
is a capability ratio. Greater than 1 indicates EDR support; it is not a measured
peak luminance. [Current EDR](https://developer.apple.com/documentation/appkit/nsscreen/maximumextendeddynamicrangecolorcomponentvalue)
depends on active content and conditions and can be 1 before EDR is requested.
Using current EDR as an enable switch could prevent HDR from ever activating.
[Reference EDR](https://developer.apple.com/documentation/appkit/nsscreen/maximumreferenceextendeddynamicrangecolorcomponentvalue)
describes the reference-rendering range and may be zero when unsupported.

None of these alone establishes active external HDR mode, calibration, black
level, or a usable nits value. The helper reports all three and classifies by
potential only. No hard-coded panel peaks or EDR-to-nits multiplication is used.

## SDR output

The baseline policy is BT.709 primaries, sRGB transfer, automatic target gamut
and peak. HDR input is tone-mapped with BT.2390. Regular SDR input retains the
user's tone-mapping choice and never enables inverse tone mapping. A high custom
HDR target peak/transfer cannot leak into this SDR branch. Wide-gamut SDR is
converted to sRGB, so this version prioritizes consistent standard-gamut output
over preservation of a wider container.

The prototype disabled target color-space hints for this sRGB target. The
validated default is `target-colorspace-hint=yes` with
`target-colorspace-hint-mode=target` and the explicit SDR transfer. The native
test results are recorded in [verification](verification.md).
The no-hint route did not pass the full native playlist restoration check and
is not exposed as an option in v0.1.0.

## HDR10 output

Use `target-colorspace-hint=yes`, `target-colorspace-hint-mode=source`, and restore
the user's original target primaries/transfer/gamut/peak/tone-mapping choices.
With mpv's defaults, the tested path negotiates HDR10/PQ and delegates display
mapping to the compositor/display. Source-based signaling is not a claim of
unmodified pixel passthrough or optimal highlight mapping for all masters.

Target-based HDR mapping could be better when real display luminance/gamut
parameters are known. This helper does not measure those parameters, so it does
not substitute guessed target nits. A user-selected target override still affects
HDR output. In particular an explicit original SDR transfer intentionally
prevents PQ even in the HDR-capable branch; automatic output cannot override
both a deliberate user constraint and promise PQ simultaneously.

`target-colorspace-hint-strict=yes` keeps rendering consistent with the negotiated
swapchain. `target-gamut` constrains color inside the output container;
`target-peak` influences tone mapping and metadata. ICC profiles take precedence
over target metadata; ICC auto/manual profiles and `strict=no` are therefore
outside the supported automatic policy. The script refuses them with a message,
without changing their settings. It also refuses inverse tone mapping.

Sources reviewed: [mpv 0.41 options](https://github.com/mpv-player/mpv/blob/v0.41.0/DOCS/man/options.rst),
[mpv renderer](https://github.com/mpv-player/mpv/blob/v0.41.0/video/out/vo_gpu_next.c),
[libplacebo color-space definitions](https://github.com/haasn/libplacebo/blob/v7.360.1/src/include/libplacebo/colorspace.h).

## Evidence limits

A chosen Vulkan format plus a Metal color-space transition establishes signaling,
not calibrated display reproduction. Subjective gamma, highlight detail,
brightness, gamut mapping, and flashes require visual and preferably instrument
inspection. HLG is deliberately converted to SDR. HDR10+, dynamic metadata,
Dolby Vision and untagged HDR are not verified supported formats. A missing tag
that mpv guesses as ordinary SDR stays SDR; the tool cannot recover lost intent.
