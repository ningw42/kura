#!/usr/bin/env python3
"""Summarize uncommitted package-version bumps for a CI PR.

Reads the working-tree changes left behind by `nix run .#update -- --skip-prompt`,
extracts `version = "..."` from each modified `pkgs/<name>/default.nix` before
and after the bump, and writes `changed`, `title`, and `body` to $GITHUB_OUTPUT
for peter-evans/create-pull-request to consume.

Run from the repo root with no arguments.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

# Mirrors the regex used by pkgs/_update/run.sh (first `version = "..."` wins),
# so the summary always reflects the same notion of "the version" as the updater.
VERSION_RE = re.compile(r'version\s*=\s*"([^"]+)"')


def first_version(text: str) -> str | None:
    m = VERSION_RE.search(text)
    return m.group(1) if m else None


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], check=True, capture_output=True, text=True
    ).stdout


def collect_bumps() -> tuple[dict[str, tuple[str, str]], list[str]]:
    """Return ({pkg_name: (old, new)}, [other_modified_paths])."""
    changed_paths = git("diff", "--name-only").splitlines()
    bumps: dict[str, tuple[str, str]] = {}
    others: list[str] = []
    for path in changed_paths:
        m = re.fullmatch(r"pkgs/([^/]+)/default\.nix", path)
        if not m:
            if path:
                others.append(path)
            continue
        name = m.group(1)
        try:
            old_text = git("show", f"HEAD:{path}")
        except subprocess.CalledProcessError:
            old_text = ""
        new_text = Path(path).read_text()
        old, new = first_version(old_text), first_version(new_text)
        if old and new and old != new:
            bumps[name] = (old, new)
    return bumps, others


def build_title(names: list[str]) -> str:
    if len(names) <= 4:
        return f"build(deps): update {', '.join(names)}"
    return f"build(deps): update {len(names)} packages: {', '.join(names[:3])}, ..."


def build_body(bumps: dict[str, tuple[str, str]], others: list[str]) -> str:
    lines = [
        "Automated package updates from `nix run .#update -- --skip-prompt`.",
        "",
        "| Package | From | To |",
        "| --- | --- | --- |",
    ]
    for name in sorted(bumps):
        old, new = bumps[name]
        lines.append(f"| {name} | {old} | {new} |")
    if others:
        lines += ["", "Files changed beyond version bumps:", ""]
        lines += [f"- `{p}`" for p in others]
    return "\n".join(lines) + "\n"


def write_outputs(**values: str) -> None:
    """Append key=value (or heredoc for multiline) to $GITHUB_OUTPUT."""
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        print("warning: $GITHUB_OUTPUT not set; skipping output emission", file=sys.stderr)
        return
    with open(path, "a") as f:
        for key, value in values.items():
            if "\n" in value:
                # Pick a delimiter unlikely to appear in the body. GitHub also
                # forbids the delimiter from appearing on its own line in value.
                delim = "GH_EOF"
                while delim in value:
                    delim += "_"
                f.write(f"{key}<<{delim}\n{value}\n{delim}\n")
            else:
                f.write(f"{key}={value}\n")


def main() -> int:
    bumps, others = collect_bumps()
    if not bumps:
        write_outputs(changed="false")
        print("No package version changes detected.")
        return 0

    names = sorted(bumps)
    title = build_title(names)
    body = build_body(bumps, others)
    write_outputs(changed="true", title=title, body=body)
    print(f"Title: {title}")
    print("--- Body ---")
    print(body, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
