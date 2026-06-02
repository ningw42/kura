#!/usr/bin/env python3
"""Summarize the diff between two flake.lock files for a CI PR.

Compares every non-root node's `locked.rev`, builds a markdown table of the
ones that changed, and writes `changed`, `title`, and `body` to $GITHUB_OUTPUT.

Usage: summarize-flake-input-updates.py <old-lockfile> <new-lockfile>
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import sys
from pathlib import Path


def fmt_locked(node: dict | None) -> str:
    if not node:
        return "—"
    locked = node.get("locked") or {}
    rev = locked.get("rev")
    if rev:
        ts = locked.get("lastModified")
        date = _dt.datetime.fromtimestamp(ts, tz=_dt.timezone.utc).strftime("%Y-%m-%d") if ts else "?"
        return f"{rev[:7]} ({date})"
    return str(locked.get("lastModified", "?"))


def collect_changes(old_path: Path, new_path: Path) -> dict[str, tuple[str, str]]:
    old = json.loads(old_path.read_text())["nodes"]
    new = json.loads(new_path.read_text())["nodes"]
    names = (set(old) | set(new)) - {"root"}
    changes: dict[str, tuple[str, str]] = {}
    for name in sorted(names):
        old_rev = (old.get(name) or {}).get("locked", {}).get("rev")
        new_rev = (new.get(name) or {}).get("locked", {}).get("rev")
        if old_rev != new_rev:
            changes[name] = (fmt_locked(old.get(name)), fmt_locked(new.get(name)))
    return changes


def build_title(names: list[str]) -> str:
    if len(names) <= 4:
        return f"build(flake): bump {', '.join(names)}"
    return f"build(flake): bump {len(names)} inputs: {', '.join(names[:3])}, ..."


def build_body(changes: dict[str, tuple[str, str]]) -> str:
    lines = [
        "Automated flake input updates from `nix flake update`.",
        "",
        "| Input | From | To |",
        "| --- | --- | --- |",
    ]
    for name, (old, new) in changes.items():
        lines.append(f"| {name} | {old} | {new} |")
    return "\n".join(lines) + "\n"


def write_outputs(**values: str) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        print("warning: $GITHUB_OUTPUT not set; skipping output emission", file=sys.stderr)
        return
    with open(path, "a") as f:
        for key, value in values.items():
            if "\n" in value:
                delim = "GH_EOF"
                while delim in value:
                    delim += "_"
                f.write(f"{key}<<{delim}\n{value}\n{delim}\n")
            else:
                f.write(f"{key}={value}\n")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} <old-lockfile> <new-lockfile>", file=sys.stderr)
        return 2
    changes = collect_changes(Path(argv[1]), Path(argv[2]))
    if not changes:
        write_outputs(changed="false")
        print("No flake input changes detected.")
        return 0

    names = list(changes)
    title = build_title(names)
    body = build_body(changes)
    write_outputs(changed="true", title=title, body=body)
    print(f"Title: {title}")
    print("--- Body ---")
    print(body, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
