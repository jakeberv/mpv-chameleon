# Security

The core runs with the user's ordinary privileges. It opens no network
connections, sends no telemetry, and does not use mpv IPC. The helper only queries
local display metadata, and display identifiers are passed as subprocess argv
values without a shell. Serial numbers are not included in helper JSON.

The installer compiles local source, uses private staging directories and a
lock, validates fixed manifest paths, refuses symlinks/world-writable executable
directories, and backs up replaced files. Uninstall preserves edited or unowned
files. Review the [security audit](docs/security-audit.md) and
[rollback limitations](docs/installation.md).

The optional physical test harness uses a Unix socket inside a fresh private
`TemporaryDirectory`. It closes the player and removes that socket afterwards.
The harness's raw logs can include media paths and display serials from mpv;
keep them private and sanitize any excerpts.

Report security issues through [GitHub's private vulnerability reporting](https://github.com/jakeberv/mpv-chameleon/security/advisories/new). Do not
post credentials, private logs, or exploitable details in a public issue. Before
the first tagged release, fixes land on `main`; no older branches are supported.
