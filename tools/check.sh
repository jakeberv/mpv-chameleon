#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 mpv-chameleon contributors
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
for script in install.sh uninstall.sh tools/*.sh tests/*.sh; do bash -n "$script"; done
command -v shellcheck >/dev/null || { echo 'ShellCheck is required for this check' >&2; exit 1; }
shellcheck install.sh uninstall.sh tools/*.sh tests/*.sh
luac -p scripts/chameleon.lua
lua tests/test_chameleon.lua
bash tests/test_install.sh
if [[ $(uname -s) == Darwin ]]; then
    swiftc -module-cache-path .build/module-cache helpers/DisplayModel.swift tests/DisplayModelTests.swift -o .build/test-display-model
    .build/test-display-model
    swiftc -module-cache-path .build/module-cache helpers/DisplayModel.swift helpers/display-edr.swift -o .build/mpv-chameleon
    .build/mpv-chameleon --version
    .build/mpv-chameleon > .build/helper-output.json
    python3 -c 'import json; d=json.load(open(".build/helper-output.json")); assert d["schema_version"] == 1 and isinstance(d["displays"], list)'
    if .build/mpv-chameleon --invalid-option >/dev/null 2>&1; then
        echo 'helper accepted invalid arguments' >&2; exit 1
    fi
fi
python3 tools/check_repository.py
