#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 mpv-chameleon contributors
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/chameleon-tests.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/config with spaces"
CFG="$TMP/config with spaces"
cat > "$TMP/bin/uname" <<'MOCK'
#!/bin/sh
printf 'Darwin\n'
MOCK
cat > "$TMP/bin/mpv" <<'MOCK'
#!/bin/sh
case "$*" in
 *--version*) echo 'mpv v0.41.0';;
 *--list-options*) printf '%s\n' --target-colorspace-hint-mode --target-colorspace-hint-strict --target-gamut --target-peak;;
 *--gpu-context=help*) echo 'vulkan macvk';;
esac
MOCK
cat > "$TMP/bin/swiftc" <<'MOCK'
#!/bin/sh
if [ "${FAIL_COMPILER:-}" = 1 ]; then exit 1; fi
while [ "$#" -gt 0 ]; do
 if [ "$1" = -o ]; then shift; printf '#!/bin/sh\necho "mpv-chameleon 0.1.0 (schema 1)"\n' > "$1"; exit 0; fi
 shift
done
exit 1
MOCK
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
run() { "$ROOT/install.sh" --config-dir "$CFG" "$@" > "$TMP/output" 2>&1; }
uninstall() { "$ROOT/uninstall.sh" --config-dir "$CFG" "$@" > "$TMP/output" 2>&1; }
fail_run() { if run; then echo 'expected installation failure'; exit 1; fi; }
assert_file() { test -f "$1" || { echo "missing $1"; exit 1; }; }
assert_absent() { test ! -e "$1" || { echo "unexpected $1"; exit 1; }; }
count=0
pass() { count=$((count+1)); echo "ok $1"; }
printf '# user config\nscale=bilinear\n' > "$CFG/mpv.conf"
cp "$CFG/mpv.conf" "$TMP/original.conf"
run --dry-run
assert_absent "$CFG/scripts"
pass 'dry-run leaves existing config untouched'
run
assert_file "$CFG/scripts/chameleon.lua"
assert_file "$CFG/helpers/mpv-chameleon"
assert_file "$CFG/.mpv-chameleon/manifest"
cmp "$CFG/mpv.conf" "$TMP/original.conf"
pass 'fresh installation with spaces preserves config'
run
assert_file "$CFG/scripts/chameleon.lua"
pass 'reinstall succeeds with backups'
printf '\n-- user edit\n' >> "$CFG/scripts/chameleon.lua"
fail_run
run --replace-modified
pass 'modified owned file requires explicit replacement'
mkdir -p "$CFG/shaders"
echo personal > "$CFG/shaders/personal.glsl"
echo 'legacy prototype' > "$CFG/scripts/auto-hdr.lua"
fail_run
run --migrate-legacy
assert_absent "$CFG/scripts/auto-hdr.lua"
LEGACY_BACKUP=$(find "$CFG/.mpv-chameleon-backups" -name auto-hdr.lua -type f)
[[ -n $LEGACY_BACKUP ]]
cmp "$LEGACY_BACKUP" <(echo 'legacy prototype')
pass 'legacy migration backs up and disables duplicate autoload'
FAIL_COMPILER=1 fail_run
assert_file "$CFG/scripts/chameleon.lua"
assert_absent "$CFG/.mpv-chameleon.lock"
pass 'compile failure preserves previous installation'
uninstall --dry-run
assert_file "$CFG/scripts/chameleon.lua"
printf '\n-- preserve edited script\n' >> "$CFG/scripts/chameleon.lua"
uninstall
assert_file "$CFG/scripts/chameleon.lua"
assert_absent "$CFG/helpers/mpv-chameleon"
assert_file "$CFG/shaders/personal.glsl"
cmp "$CFG/mpv.conf" "$TMP/original.conf"
pass 'uninstall preserves edits and unrelated files'
uninstall
pass 'repeated uninstall is safe'
rm "$CFG/scripts/chameleon.lua"
run
uninstall
assert_absent "$CFG/scripts/chameleon.lua"
pass 'clean uninstall removes owned files'
ln -s "$TMP/original.conf" "$CFG/scripts/chameleon.lua"
fail_run
cmp "$TMP/original.conf" "$CFG/mpv.conf"
rm "$CFG/scripts/chameleon.lua"
pass 'symlink destination rejected'
mkdir "$CFG/.mpv-chameleon.lock"
fail_run
rmdir "$CFG/.mpv-chameleon.lock"
pass 'concurrent installer lock rejected'
echo 'not ours' > "$CFG/scripts/chameleon.lua"
fail_run
rm "$CFG/scripts/chameleon.lua"
pass 'unowned destination not overwritten'
run
cp "$CFG/helpers/mpv-chameleon" "$TMP/old-helper"
cp "$CFG/scripts/chameleon.lua" "$TMP/old-script"
# Cause the second destination move to fail, after the first file was replaced.
cat > "$TMP/bin/mv" <<'MOCK'
#!/bin/bash
last=${!#}
if [[ "$last" == */helpers/mpv-chameleon ]] && [[ "$1" == */new/* ]]; then exit 1; fi
exec /bin/mv "$@"
MOCK
chmod +x "$TMP/bin/mv"
fail_run
cmp "$CFG/helpers/mpv-chameleon" "$TMP/old-helper"
cmp "$CFG/scripts/chameleon.lua" "$TMP/old-script"
assert_absent "$CFG/.mpv-chameleon.lock"
rm "$TMP/bin/mv"
pass 'mid-install failure rolls back all owned files'
chmod 777 "$CFG/helpers"
fail_run
chmod 700 "$CFG/helpers"
pass 'world-writable executable directory rejected'
# A missing file can be repaired using the existing manifest.
rm "$CFG/helpers/mpv-chameleon"
run
assert_file "$CFG/helpers/mpv-chameleon"
pass 'partial installation repaired'
# GNU stat can print output for its second file operand even when the first
# unsupported BSD-format operand fails. Discard failed probe stdout.
cat > "$TMP/bin/stat" <<'MOCK'
#!/bin/sh
if [ "$1" = -f ]; then echo 'File: misleading filesystem output'; exit 1; fi
if [ "$1" = -c ]; then echo 700; exit 0; fi
exit 1
MOCK
chmod +x "$TMP/bin/stat"
run
rm "$TMP/bin/stat"
pass 'GNU stat fallback discards failed BSD probe output'
# An unavailable compiler must fail before changing installed files.
cat > "$TMP/bin/swiftc" <<'MOCK'
#!/bin/sh
exit 127
MOCK
fail_run
assert_file "$CFG/scripts/chameleon.lua"
pass 'unavailable compiler leaves installation intact'
cat > "$TMP/bin/mpv" <<'MOCK'
#!/bin/sh
exit 127
MOCK
fail_run
pass 'unavailable mpv is detected'
echo "Shell: $count scenarios passed"
