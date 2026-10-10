#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 mpv-chameleon contributors
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
ACTION=install
# shellcheck source=tools/install-common.sh
source "$ROOT/tools/install-common.sh"
[[ $(uname -s) == Darwin ]] || fail 'installation requires macOS'
command -v mpv >/dev/null || fail 'mpv is missing; install mpv 0.41+ with Vulkan/macvk support'
command -v swiftc >/dev/null || fail 'Swift compiler missing; install Xcode Command Line Tools with xcode-select --install'
VERSION=$(mpv --no-config --version 2>/dev/null) || fail 'mpv cannot run'
VERSION=${VERSION%%$'\n'*}
[[ $VERSION =~ mpv\ v?([0-9]+)\.([0-9]+) ]] || fail 'cannot determine mpv version'
(( BASH_REMATCH[1] > 0 || BASH_REMATCH[2] >= 41 )) || fail 'mpv 0.41 or newer is required'
CAPABILITIES=$(mpv --no-config --list-options 2>/dev/null) || fail 'cannot inspect mpv options'
for option in target-colorspace-hint-mode target-colorspace-hint-strict target-gamut target-peak; do
    [[ $CAPABILITIES == *"--$option"* ]] || fail "mpv lacks --$option"
done
CONTEXTS=$(mpv --no-config --gpu-context=help 2>/dev/null) || fail 'cannot inspect mpv GPU contexts'
[[ $CONTEXTS == *macvk* ]] || fail 'mpv was built without the macvk Vulkan context'
preflight_paths
validate_manifest
check_existing() {
    local rel old
    for rel in "${FILES[@]}"; do
        if [[ -f $CONFIG/$rel ]]; then
            old=$(manifest_hash "$rel")
            [[ -n $old ]] || fail "unowned file exists: $CONFIG/$rel; move it aside first"
            if [[ $(hash "$CONFIG/$rel") != "$old" && $REPLACE == 0 ]]; then
                fail "edited owned file: $rel; use --replace-modified to back it up and replace it"
            fi
        fi
    done
    if [[ -f $CONFIG/$LEGACY && $MIGRATE == 0 ]]; then
        fail 'legacy auto-hdr.lua found; use --migrate-legacy to back it up and prevent duplicate execution'
    fi
}
check_existing
log "install mpv-chameleon 0.1.0 into $CONFIG"
if [[ $DRY_RUN == 1 ]]; then
    log 'dry-run: compile Swift, back up replaced files, install chameleon.lua and helpers/mpv-chameleon'
    [[ $MIGRATE == 0 ]] || log 'dry-run: disable legacy auto-hdr.lua after backing it up'
    exit 0
fi
lock_installation
check_existing
if [[ -f $CONFIG/$LEGACY ]]; then TRANSACTION_FILES+=("$LEGACY"); fi
make_transaction
mkdir -p "$TXN/new/scripts" "$TXN/new/helpers" "$TXN/new/.mpv-chameleon" "$TXN/module-cache"
log 'compiling native display helper'
if ! swiftc -O -module-cache-path "$TXN/module-cache" "$ROOT/helpers/DisplayModel.swift" \
    "$ROOT/helpers/display-edr.swift" -o "$TXN/new/helpers/mpv-chameleon" > "$TXN/compiler.log" 2>&1; then
    cat "$TXN/compiler.log" >&2
    fail 'Swift build failed; check xcode-select --install and the selected SDK'
fi
chmod 755 "$TXN/new/helpers/mpv-chameleon"
"$TXN/new/helpers/mpv-chameleon" --version
cp "$ROOT/scripts/chameleon.lua" "$TXN/new/scripts/chameleon.lua"
chmod 644 "$TXN/new/scripts/chameleon.lua"
for rel in "${FILES[@]}"; do printf '%s\t%s\n' "$(hash "$TXN/new/$rel")" "$rel"; done > "$TXN/new/$STATE"
backup_originals
mkdir -p "$CONFIG/scripts" "$CONFIG/helpers" "$CONFIG/.mpv-chameleon"
MUTATING=1
for rel in "${FILES[@]}" "$STATE"; do
    [[ $VERBOSE == 0 ]] || log "installing $rel"
    mv "$TXN/new/$rel" "$CONFIG/$rel"
done
if [[ -f $CONFIG/$LEGACY ]]; then rm "$CONFIG/$LEGACY"; fi
COMMITTED=1
log 'installed. Restart mpv. Required renderer: vo=gpu-next, gpu-api=vulkan, gpu-context=macvk'
log 'verify: mpv --script-opts=chameleon-debug=yes /path/to/video.mkv'
