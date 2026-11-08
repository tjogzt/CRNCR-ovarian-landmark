#!/usr/bin/env python3
"""Prepare a verified upload snapshot without deleting or editing the source.

File: 29_prepare_release_snapshot.py
Purpose: Apply the versioned physical release policy, copy valid project files,
    verify their hashes and regenerate the destination checksum inventory.
Author: Project authors
Created: 2026-10-23
Inputs: Source repository and config/release_policy.json; optional destination.
Outputs: English dry-run diagnostics, or a new verified snapshot with SHA256SUMS.
Runtime parameters: --source, --destination and --write. Dry-run is the default;
    --write requires a nonexistent destination outside the source repository.
Notes: This is packaging, not analysis, deletion, Git submission or publication.
"""

from __future__ import annotations

import argparse
import fnmatch
import importlib
import json
import os
from pathlib import Path
import shutil
import sys


# Share the same bounded-memory hash implementation as reconciliation/audits.
sha256 = importlib.import_module("28_submission_utilities").sha256


def load_policy(source: Path) -> dict:
    """Read a required release policy; malformed or missing fields fail early."""
    with (source / "config" / "release_policy.json").open(encoding="utf-8") as handle:
        policy = json.load(handle)
    for key in ("excluded_directories", "excluded_paths", "excluded_names",
                "excluded_patterns", "required_paths"):
        if not isinstance(policy.get(key), list) or not all(
            isinstance(item, str) and item for item in policy[key]
        ):
            raise ValueError(f"Release policy field must be a string list: {key}")
    maximum = policy.get("maximum_file_bytes")
    if isinstance(maximum, bool) or not isinstance(maximum, int) or maximum <= 0:
        raise ValueError("maximum_file_bytes must be a positive integer")
    checksum = policy.get("checksum_path")
    if not isinstance(checksum, str) or not checksum:
        raise ValueError("checksum_path must be a nonempty relative path")
    configured_paths = policy["excluded_paths"] + policy["required_paths"] + [checksum]
    if any(Path(value).is_absolute() or ".." in Path(value).parts for value in configured_paths):
        raise ValueError("Release-policy paths must stay inside the repository")
    return policy


def excluded(relative: Path, policy: dict) -> bool:
    """Apply configured cache/private exclusions without dropping evidence."""
    if any(part in policy["excluded_directories"] for part in relative.parts):
        return True
    for value in policy["excluded_paths"]:
        if relative == Path(value) or Path(value) in relative.parents:
            return True
    return relative.name in policy["excluded_names"] or any(
        fnmatch.fnmatchcase(relative.name, pattern) for pattern in policy["excluded_patterns"]
    )


def selected_files(source: Path, policy: dict) -> tuple[list[Path], int]:
    """Select physical files and reject symlinks or oversized upload candidates."""
    selected = []
    omitted = 0
    # Prune excluded directories before traversal so large dependency caches
    # never become input candidates or exhaust the inventory's memory.
    for current, directories, names in os.walk(source, followlinks=False):
        parent = Path(current)
        retained = []
        for name in sorted(directories):
            path = parent / name
            if excluded(path.relative_to(source), policy):
                omitted += 1
            elif path.is_symlink():
                raise ValueError(f"Review symbolic-link directory before packaging: {path}")
            else:
                retained.append(name)
        directories[:] = retained
        for name in sorted(names):
            path = parent / name
            relative = path.relative_to(source)
            if excluded(relative, policy) or relative == Path(policy["checksum_path"]):
                omitted += 1
                continue
            if path.is_symlink():
                raise ValueError(f"Review symbolic-link file before packaging: {relative}")
            if path.stat().st_size > policy["maximum_file_bytes"]:
                raise ValueError(f"File exceeds the configured upload limit: {relative}")
            selected.append(relative)
    for relative in policy["required_paths"]:
        required = Path(relative)
        if not any(path == required or required in path.parents for path in selected):
            raise ValueError(f"Required upload path has no retained file: {relative}")
    return sorted(selected), omitted


def main() -> int:
    """Dry-run by default; create only a new, independent destination on request."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--destination", type=Path)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    source = args.source.expanduser().resolve()
    policy = load_policy(source)
    paths, omitted = selected_files(source, policy)
    print(f"Selected {len(paths)} upload files; excluded {omitted} cache/private entries.")
    if not args.write:
        print("Dry-run only: source files were not modified and no destination was created.")
        return 0
    if args.destination is None:
        parser.error("--write requires --destination")
    destination = args.destination.expanduser().resolve()
    if destination == source or destination.is_relative_to(source):
        raise ValueError("Destination must be outside the source repository")
    if destination.exists():
        raise ValueError("Destination already exists; refusing to overwrite")
    if not destination.parent.is_dir():
        raise ValueError("Destination parent does not exist")
    destination.mkdir()
    hashes = []
    for relative in paths:
        source_file = source / relative
        target = destination / relative
        before = sha256(source_file)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_file, target)
        if sha256(source_file) != before or sha256(target) != before:
            raise ValueError(f"File changed during verified copy: {relative}")
        hashes.append(f"{before}  ./{relative.as_posix()}")
    manifest = destination / policy["checksum_path"]
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text("\n".join(hashes) + "\n", encoding="utf-8")
    print(f"Verified {len(hashes)} copied files and wrote the destination checksum inventory.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"Release preparation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
