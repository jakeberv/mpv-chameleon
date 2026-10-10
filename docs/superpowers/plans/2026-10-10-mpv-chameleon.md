# mpv-chameleon Implementation Plan

> For agentic workers: use superpowers:executing-plans inline, as the user requested.

**Goal:** Build, test, document and prepare mpv-chameleon v0.1.0 for publication.
**Architecture:** Single short-lived Swift query and an asynchronous Lua controller;
transactional shell installation. No external runtime libraries.
**Tech Stack:** Swift/Foundation/AppKit, Lua 5.1-compatible mpv API, Bash 3.2.
**Spec:** ../specs/2026-10-10-mpv-chameleon-design.md

## Global constraints

Name mpv-chameleon, main script chameleon.lua. macOS 10.15+ API floor, mpv 0.41+
and gpu-next/vulkan/macvk. No persistent user configuration edits. No media,
local logs, third-party source or generated binaries committed. GPL-3.0-or-later
and public GitHub publication were approved by the project owner on 2026-10-10.

## Review focus

- Stale helper results after A→B→A must never overwrite the newest decision.
- Unknown identities and invalid output after HDR must actually apply SDR.
- Failed installation must restore the previous executable/script/manifest.
- Changed or symlinked owned files must not be deleted by uninstall.
- Custom peaks/ICC/profile changes must not produce misleading SDR guarantees.

### Task 1: Display helper

Files: helpers/DisplayModel.swift, helpers/display-edr.swift, tests/DisplayModelTests.swift.
Interface: schema_version=1, displays array, selection status/id; --display NAME.
- [x] Write and run failing pure tests for identity collisions, suffixes, invalid
  values, escaping, empty output, and selection serialization.
- [x] Implement pure model plus AppKit enumeration; compile and run tests.
- [x] Verify actual displays and error exit status on this Mac.

### Task 2: Lua controller

Files: scripts/chameleon.lua, tests/test_chameleon.lua.
Interface: helper argv --display NAME, JSON schema 1; chameleon script options.
- [x] Write failing mocked mpv tests for modes, restoration, invalid results,
  timeout, repeated events, A→B→A stale callback, retries, lifecycle and options.
- [x] Implement controller with generations, debounce, deadline, refresh.
- [x] Run lua tests and luac syntax validation; inspect property order and logs.

### Task 3: Installer

Files: install.sh, uninstall.sh, tools/install-common.sh, tests/test_install.sh.
Interface: --config-dir DIR, --dry-run, --verbose, --migrate-legacy.
- [x] Write/run failing sandbox tests for fresh/reinstall/migration/upgrade,
  missing dependencies, permissions, dry-run, rollback and safe uninstall.
- [x] Implement build staging, lock, manifest hashes, backup transaction.
- [x] Run shell suite, Bash syntax validation and ShellCheck.

### Task 4: Native validation and documentation

Files: tests/integration.py, docs/*.md, README.md, examples/*, maintenance files.
- [x] Use isolated native playback to compare SDR strategies and source matrix.
- [x] Record actual observations and limitations; update default only with evidence.
- [x] Write install/configuration/architecture/color/troubleshooting/testing docs,
  optional quality settings, security/licensing audit and v0.1.0 release notes.
- [x] Add CI for Lua, shell and native helper, repository privacy checks.

### Task 5: Release preparation

- [x] Run full validation, review branch, fix material findings with regression tests.
- [x] Initialize main and create clean local git history; prepare release archive.
- [x] Obtain final publication/license approval after presenting the concrete result.
- [x] Create the public GitHub repository.
- Hosted validation results: [GitHub Actions](https://github.com/jakeberv/mpv-chameleon/actions/workflows/ci.yml).
- Tagged release deferred at the owner's request; retain draft v0.1.0 notes.
