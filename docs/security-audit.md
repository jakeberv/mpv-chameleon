# Security and privacy audit

Reviewed the Swift/Lua core, Bash installer, Python test harness, and proposed
release contents. The security skill has no language-specific reference for
this Swift/Lua/Bash design; this review uses the concrete trust boundaries and
requested checks rather than applying unrelated web-framework guidance.

No unresolved critical or important security issue was identified in this
review. This is a source review and testing record, not a security certification.

## Boundaries checked

- Runtime and installation perform no network I/O and do not require sudo.
- The Lua helper call uses argv and validates output type, size, schema, selection,
  duplicate IDs and numeric capability. No display name is interpolated into shell.
- The helper emits local screen names/IDs/geometry; serials are internal only.
- Installation has fixed owned paths, an inert hash manifest, private mktemp
  staging, a directory lock, preflight/post-lock symlink checks, ownership checks,
  and rejection of world-writable directories.
- A real transaction-failure test verifies script/helper restoration after a
  partially applied upgrade. Uninstall hash-checks ownership and preserves edits.
- Backups remain private and are never automatically deleted. User settings,
  third-party scripts/shaders and media are outside the managed file list.
- IPC is absent from the core. The optional Python integration harness uses a
  random private directory, argv-only subprocesses, and process/socket cleanup.
- Runtime source is small enough to inspect; no opaque binary is distributed.
- CI has read-only repository permissions and a pinned checkout action. It does
  not accept secrets or publish releases from untrusted pull requests.

## Residual limits

The user's own account, local source checkout, compiler, mpv build, and explicitly
trusted writable groups are trusted. This is not a sandbox against malicious
code already running as the same user. Directory checks do not promise to defeat
an active filesystem attacker with equivalent write access. SIGKILL/power loss
requires manual recovery from transaction originals, documented in installation.

mpv's verbose logs can expose filenames and display serials even though the
helper does not. The test logs and downloaded reference sources are git-ignored.
Only sanitized aggregate results belong in a public report. Git uses a no-reply
address locally for this repository; global identity settings were not changed.

The independent code review found a non-security stale-timeout responsiveness
bug. It was reproduced, fixed, and covered by a regression test. Shell portability
review also caught and fixed failed BSD-stat probe output contaminating GNU-stat
fallback; a dedicated installer scenario now covers it.
