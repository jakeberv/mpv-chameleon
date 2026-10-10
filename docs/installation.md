# Installation, upgrade and rollback

Run `./install.sh --dry-run`, then `./install.sh` from the source directory.
The dry run checks dependencies and paths but does not compile or modify files.
`--verbose` lists installed files. `--help` lists supported flags.

Configuration selection follows `MPV_HOME`, then `${XDG_CONFIG_HOME:-$HOME/.config}/mpv`,
with an existing `~/.mpv` used only if the XDG path is absent. `--config-dir` is the
unambiguous override, including for app bundles or custom launchers. It must be
an absolute path. Configure mpv to use the same directory. Do not run with sudo.

Installed paths relative to that directory:

- `scripts/chameleon.lua`
- `helpers/mpv-chameleon` (compiled on this machine)
- `.mpv-chameleon/manifest` (SHA-256 ownership records)

No renderer/quality settings are silently inserted. Choose gpu-next/vulkan/macvk
in your own config if needed. The optional example is not installed automatically.

## Existing prototype

Use `./install.sh --migrate-legacy`. This is explicit permission to move the
existing `scripts/auto-hdr.lua` out of autoload, after making a backup. The old
`helpers/display-edr` and Swift source are preserved. Only `chameleon.lua` then
autoloads. If both scripts are present, chameleon refuses to compete. Check any
explicit `--script` arguments or `scripts=` settings separately.

## Upgrades and failures

Re-run the installer from the new checkout. A timestamped directory under
`.mpv-chameleon-backups/` preserves replaced owned files and the previous
manifest. An edited owned file requires `--replace-modified`; inspect the diff
before opting in. Unowned files at the intended destinations cause an error.

Build and helper self-identification finish before replacement. A directory lock
serializes operations; each transaction snapshots originals and records absent
files. Command failures and ordinary signals roll back the previous script,
helper, manifest and legacy state. Symlink destinations and world-writable
executable directories are rejected. Use a real path for a symlinked config root.

SIGKILL, power loss, or filesystem failure cannot be made transactional by shell
traps. If the process is definitely gone, inspect `.mpv-chameleon-txn.*` and its
`original/` directory plus `.mpv-chameleon-backups/` before removing a stale
`.mpv-chameleon.lock`. Recover the recorded originals, then rerun the installer.
A missing managed file with an intact manifest is repaired by reinstalling.
Do not discard a transaction directory before saving any needed originals.

## Uninstall and rollback

```sh
./uninstall.sh --dry-run
./uninstall.sh
```

Use the same `--config-dir` override when applicable. Uninstall backs up owned
files, removes hash-matching files, and preserves edited ones and their manifest.
Repeated uninstall is safe. No preferences, shaders, media, or backup directories
are deleted. Symlinks cause a refusal rather than following the link.

To return to a previous chameleon version: close mpv, uninstall the current
version, inspect the selected backup, then restore its `scripts/chameleon.lua`,
`helpers/mpv-chameleon`, and `.mpv-chameleon/manifest` to matching relative paths.
Preserve any newer edits before replacing them.

To return to the prototype: close mpv, uninstall chameleon, ensure no edited
`chameleon.lua` remains in `scripts/`, then copy the selected backup's
`scripts/auto-hdr.lua` into `scripts/`. The legacy helper was never replaced.
Inspect backup contents before restoring; never load both scripts.
