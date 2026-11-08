#!/usr/bin/env python3
"""Verify that the Chinese review edition matches its recorded English sources.

File: 37_check_chinese_sync.py
Purpose: Recompute SHA-256 for every recorded English source, formal figure,
    Chinese source and Chinese PDF, and fail when the Chinese edition is stale.
Author: Project authors
Created: 2026-11-05
Inputs: manuscript/zh/sync_manifest.json and the paths it records.
Outputs: Human-readable status on stdout; stale paths and rebuild instructions
    on stderr. This script never writes the manifest or any PDF.
Runtime parameters: --quiet (print only failures); --manifest (testing override).

Usage:
    python3 scripts/37_check_chinese_sync.py [--quiet]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manuscript" / "zh" / "sync_manifest.json"


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check_entry(label: str, relative: str, expected: str, problems: list[str]) -> None:
    path = ROOT / relative
    if not path.is_file():
        problems.append(f"{label:<28} missing: {relative}")
        return
    actual = sha256(path)
    if actual != expected:
        problems.append(
            f"{label:<28} changed: {relative}\n"
            f"{'':<30}recorded {expected[:12]}  now {actual[:12]}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quiet", action="store_true", help="print only failures")
    parser.add_argument("--manifest", type=pathlib.Path, default=MANIFEST, help="override manifest path (testing)")
    args = parser.parse_args()

    manifest_path = args.manifest if args.manifest.is_absolute() else ROOT / args.manifest
    if not manifest_path.is_file():
        print(
            f"Chinese edition manifest not found: {manifest_path}\n"
            "Run `make zh` to build the Chinese review edition.",
            file=sys.stderr,
        )
        return 2

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    problems: list[str] = []

    for name, entry in manifest.get("english_sources", {}).items():
        check_entry(f"English source [{name}]", entry["path"], entry["sha256"], problems)

    for relative, expected in manifest.get("figures", {}).items():
        check_entry("Formal figure", relative, expected, problems)

    for name, entry in manifest.get("documents", {}).items():
        check_entry(f"Chinese source [{name}]", entry["chinese_source"], entry["chinese_source_sha256"], problems)
        check_entry(f"Chinese PDF [{name}]", entry["pdf"], entry["pdf_sha256"], problems)

    if problems:
        print("Chinese review edition is STALE:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "\nThe English submission or a formal figure changed after the last build.\n"
            "Run `make zh`, review the resulting Chinese sources and PDFs, then re-run\n"
            "`make zh-check`.",
            file=sys.stderr,
        )
        return 1

    if not args.quiet:
        documents = manifest.get("documents", {})
        pages = " / ".join(f"{key} {value.get('pages', '?')}p" for key, value in documents.items())
        print(
            f"Chinese review edition is up to date with all recorded English sources "
            f"({pages}). Manifest generated {manifest.get('generated_at', 'unknown')}."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
