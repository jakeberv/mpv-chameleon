#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 mpv-chameleon contributors
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
ACTION=uninstall
# shellcheck source=tools/install-common.sh
source "$ROOT/tools/install-common.sh"
preflight_paths
validate_manifest
if [[ ! -f $CONFIG/$STATE ]]; then log 'no managed installation found; nothing removed'; exit 0; fi
if [[ $DRY_RUN == 0 ]]; then lock_installation; make_transaction; backup_originals; fi
PRESERVED=0
if [[ $DRY_RUN == 0 ]]; then MUTATING=1; fi
for rel in "${FILES[@]}"; do
    if [[ ! -f $CONFIG/$rel ]]; then continue; fi
    if [[ $(hash "$CONFIG/$rel") == "$(manifest_hash "$rel")" ]]; then
        log "remove: $CONFIG/$rel"
        [[ $DRY_RUN == 1 ]] || rm "$CONFIG/$rel"
    else
        log "preserving edited file: $CONFIG/$rel"
        PRESERVED=1
    fi
done
# Retain ownership evidence when a file was edited so it can be recovered later.
if [[ $PRESERVED == 0 && $DRY_RUN == 0 ]]; then rm "$CONFIG/$STATE"; fi
COMMITTED=1
log 'uninstall finished; user settings and backups preserved; legacy auto-hdr.lua remains disabled'
