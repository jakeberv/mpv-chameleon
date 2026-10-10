#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 mpv-chameleon contributors
# shellcheck disable=SC2034 # Variables are consumed by the sourcing installers.
# Shared by install.sh and uninstall.sh. Requires Bash 3.2 or newer.
set -euo pipefail
umask 077
fail() { printf 'mpv-chameleon: %s\n' "$*" >&2; exit 1; }
log() { printf 'mpv-chameleon: %s\n' "$*"; }
usage() {
    cat <<EOF_HELP
Usage: $ACTION.sh [--config-dir DIR] [--dry-run] [--verbose] [--help]
Install only: --migrate-legacy (back up and disable scripts/auto-hdr.lua)
              --replace-modified (back up and replace edited owned files)
Default: MPV_HOME, then XDG_CONFIG_HOME/mpv or ~/.config/mpv; existing ~/.mpv
is used only when the XDG directory does not exist. Use --config-dir for bundles.
No mpv.conf, input.conf, shaders, or unrelated settings are changed.
EOF_HELP
}
DRY_RUN=0
VERBOSE=0
MIGRATE=0
REPLACE=0
CONFIG=${MPV_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/mpv}
if [[ -z ${MPV_HOME:-} && ! -d "$CONFIG" && -d "$HOME/.mpv" ]]; then CONFIG="$HOME/.mpv"; fi
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config-dir) [[ $# -ge 2 && -n $2 ]] || fail '--config-dir needs a path'; CONFIG=$2; shift;;
        --dry-run) DRY_RUN=1;;
        --verbose) VERBOSE=1;;
        --migrate-legacy) [[ $ACTION == install ]] || fail 'installation option'; MIGRATE=1;;
        --replace-modified) [[ $ACTION == install ]] || fail 'installation option'; REPLACE=1;;
        --help|-h) usage; exit 0;;
        *) fail "unknown argument: $1";;
    esac
    shift
done
[[ $CONFIG == /* && $CONFIG != / && $CONFIG != "$HOME" ]] || fail 'config path must be an absolute, dedicated mpv directory'
[[ $CONFIG != *$'\n'* && $CONFIG != *$'\t'* ]] || fail 'config path must not contain tabs or newlines'
CONFIG=${CONFIG%/}
[[ ! -L $CONFIG ]] || fail 'config directory is a symlink; use its real path explicitly'
if [[ -d $CONFIG ]]; then CONFIG=$(cd "$CONFIG" && pwd -P); fi
FILES=(scripts/chameleon.lua helpers/mpv-chameleon)
STATE=.mpv-chameleon/manifest
LEGACY=scripts/auto-hdr.lua
LOCK="$CONFIG/.mpv-chameleon.lock"
TXN=
LOCKED=0
MUTATING=0
COMMITTED=0
BACKUP=
TRANSACTION_FILES=("${FILES[@]}" "$STATE")

hash() { shasum -a 256 "$1" | awk '{print $1}'; }
mode_of() {
    local detected
    if detected=$(stat -f '%Lp' "$1" 2>/dev/null); then printf '%s\n' "$detected"
    else stat -c '%a' "$1"; fi
}
safe_directory() {
    local p=$1 mode
    [[ ! -L $p ]] || fail "refusing symlink directory: $p"
    if [[ -e $p ]]; then
        [[ -d $p && -O $p ]] || fail "directory must be owned by the current user: $p"
        mode=$(mode_of "$p")
        [[ $mode =~ ^[0-7]+$ ]] || fail "cannot inspect permissions: $p"
        (( (8#$mode & 2) == 0 )) || fail "world-writable directory: $p"
    fi
}
safe_file() {
    local p=$1
    [[ ! -L $p ]] || fail "refusing symlink file: $p"
    if [[ -e $p ]]; then [[ -f $p && -O $p ]] || fail "not an owned regular file: $p"; fi
}
preflight_paths() {
    safe_directory "$CONFIG"
    local d f
    for d in scripts helpers .mpv-chameleon .mpv-chameleon-backups; do safe_directory "$CONFIG/$d"; done
    for f in "${FILES[@]}" "$STATE" "$LEGACY"; do safe_file "$CONFIG/$f"; done
}
manifest_hash() {
    [[ -f $CONFIG/$STATE ]] || return 0
    awk -F '\t' -v name="$1" '$2 == name {print $1}' "$CONFIG/$STATE"
}
validate_manifest() {
    [[ -f $CONFIG/$STATE ]] || return 0
    local digest relative extra count=0 seen=' '
    while IFS=$'\t' read -r digest relative extra; do
        [[ $digest =~ ^[0-9a-f]{64}$ && -z $extra ]] || fail 'invalid installation manifest; restore a backup before retrying'
        case "$relative" in scripts/chameleon.lua|helpers/mpv-chameleon) ;; *) fail 'invalid manifest path';; esac
        [[ $seen != *" $relative "* ]] || fail 'duplicate manifest entry'
        seen="$seen$relative "
        count=$((count+1))
    done < "$CONFIG/$STATE"
    [[ $count == 2 ]] || fail 'incomplete manifest; restore a backup before retrying'
}
cleanup() {
    local result=$? rel rollback_failed=0
    trap - EXIT INT TERM HUP
    if [[ $MUTATING == 1 && $COMMITTED == 0 ]]; then
        log 'restoring previous installation after failure' >&2
        for rel in "${TRANSACTION_FILES[@]}"; do
            if [[ -f $TXN/original/$rel ]]; then
                cp -p "$TXN/original/$rel" "$CONFIG/$rel" || rollback_failed=1
            elif [[ -f $TXN/absent/$rel ]]; then
                rm -f "$CONFIG/$rel" || rollback_failed=1
            fi
        done
    fi
    if [[ -n $TXN && -d $TXN ]]; then
        if [[ $rollback_failed == 0 ]]; then rm -rf "$TXN"
        else log "rollback incomplete; recover originals from $TXN/original" >&2; fi
    fi
    if [[ $LOCKED == 1 ]]; then rmdir "$LOCK" || true; fi
    exit "$result"
}
lock_installation() {
    mkdir -p "$CONFIG"
    mkdir "$LOCK" 2>/dev/null || fail 'installation lock exists; another operation may be running (see troubleshooting)'
    LOCKED=1
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    # Recheck after acquiring the lock. Never source the manifest as shell code.
    preflight_paths
    validate_manifest
}
make_transaction() {
    TXN=$(mktemp -d "$CONFIG/.mpv-chameleon-txn.XXXXXX")
    local rel
    for rel in "${TRANSACTION_FILES[@]}"; do
        mkdir -p "$TXN/original/$(dirname "$rel")" "$TXN/absent/$(dirname "$rel")"
        if [[ -f $CONFIG/$rel ]]; then cp -p "$CONFIG/$rel" "$TXN/original/$rel"
        else : > "$TXN/absent/$rel"; fi
    done
}
backup_originals() {
    local rel has_original=0
    for rel in "${TRANSACTION_FILES[@]}"; do [[ ! -f $TXN/original/$rel ]] || has_original=1; done
    if [[ $has_original == 1 ]]; then
        mkdir -p "$CONFIG/.mpv-chameleon-backups"
        BACKUP=$(mktemp -d "$CONFIG/.mpv-chameleon-backups/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")
        cp -Rp "$TXN/original/." "$BACKUP/"
        log "backup: $BACKUP"
    fi
}
