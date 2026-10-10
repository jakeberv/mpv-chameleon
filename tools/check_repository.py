#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 mpv-chameleon contributors
"""Check tracked release files for accidental private artifacts and broken links."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
files = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
problems = []
for name in filter(None, files):
    path = root / name
    if path.suffix.lower() in {".mp4", ".mkv", ".mov", ".webm", ".log", ".dylib", ".o", ".pyc"}:
        problems.append(f"forbidden release artifact: {name}")
    data = path.read_bytes()
    if b"\0" in data:
        problems.append(f"binary file: {name}")
        continue
    text = data.decode()
    # Generic documentation examples are allowed; real user paths aren't.
    if re.search(r"/Users/(?!YOUR_USER(?:/|\b))[A-Za-z0-9_.@-]+/", text):
        problems.append(f"private home path: {name}")
    if re.search(r"(?:gh[pousr]_[A-Za-z0-9]{30,}|sk-proj-[A-Za-z0-9_-]{30,})", text):
        problems.append(f"credential-shaped text: {name}")
    if path.suffix == ".md":
        for target in re.findall(r"\]\(([^)]+)\)", text):
            if "://" in target or target.startswith("#"):
                continue
            relative = target.split("#")[0]
            if relative and not (path.parent / relative).exists():
                problems.append(f"broken local link: {name}: {target}")
if problems:
    raise SystemExit("\n".join(problems))
print(f"Repository: {len(list(filter(None, files)))} tracked files checked")
