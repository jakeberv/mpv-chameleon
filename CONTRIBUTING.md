# Contributing

Keep mpv-chameleon small and source/display aware. Runtime code must work with
mpv's Lua 5.1 interface and documented macOS APIs. Avoid shell interpretation of
external data, persistent services, guessed brightness values, and unqualified
color-accuracy claims.

Run `./tools/check.sh` with Lua, luac, ShellCheck, Python 3 and (on macOS) Swift
available. The suite uses no third-party test framework. New state-machine or
installer failure fixes should include a regression test that exercises the
behavior. Native integration is opt-in; see [testing](docs/testing.md).

Keep source-capability and display-capability logic separate. Changes to output
policy need physical swapchain/Metal evidence for all four source/display cases,
live transitions in both directions, file changes, and metadata fallbacks.
Mock tests cannot establish real HDR output or calibrated color accuracy.

Do not submit personal media, raw local logs, generated binaries, third-party
shaders, or machine-specific paths. Use synthetic fixtures and sanitized results.
Pull requests should describe the trigger, resulting behavior, validation, and
remaining limits. Releases require the checklist in [release preparation](docs/releasing.md).

Contributions are accepted under GPL-3.0-or-later, the project license. Submit
only work you have the right to contribute under those terms, and preserve
applicable copyright and license notices. See [LICENSE](LICENSE).
