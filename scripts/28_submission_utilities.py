#!/usr/bin/env python3
"""Shared, read-only input and path utilities for submission scripts.

File: 28_submission_utilities.py
Purpose: Centralize local JSON/YAML and CSV reads, exact source-row selection,
    repository-relative path resolution and streaming file hashes without
    building manuscripts, modifying results or supplying scientific defaults.
Author: Project authors
Created: 2026-10-23
Inputs: Script paths, local configuration files, locked CSV tables and files
    whose SHA256 digests are requested by the calling submission script.
Outputs: In-memory configuration values, CSV rows, absolute repository/results
    paths, display-path strings and SHA256 digests; no files are written.
Runtime parameters: CRNCR_RESULTS_DIR overrides the results root; relative
    overrides are resolved against the calling script's repository, not cwd.
Dependencies: Python standard library; PyYAML only when reading analysis.yml.
"""

import csv
import hashlib
import json
import os
import pathlib


def repository_root(script_path):
    """Return the repository containing a numbered script in scripts/."""
    return pathlib.Path(script_path).resolve().parent.parent


def results_directory(root):
    """Resolve versioned/default, private and environment paths like the R loader."""
    defaults = read_yaml(root / "config" / "paths.example.yml")
    private_value = os.environ.get("CRNCR_PATHS_CONFIG", "")
    private = pathlib.Path(private_value).expanduser() if private_value else root / "config" / "paths.yml"
    if not private.is_absolute():
        private = root / private
    if private_value and not private.is_file():
        raise ValueError(f"Explicit private paths configuration does not exist: {private}")
    if private.is_file():
        defaults.update(read_yaml(private))
    value = os.environ.get("CRNCR_RESULTS_DIR") or required_value(defaults, "results_dir")
    if not isinstance(value, str) or not value.strip():
        raise ValueError("Configured results_dir must be a nonempty string")
    path = pathlib.Path(value).expanduser()
    return (path if path.is_absolute() else root / path).resolve()


def resolve_project_path(root, value, results=None):
    """Resolve a project path, remapping a leading results/ when requested."""
    path = pathlib.Path(value)
    if path.is_absolute():
        return path
    if results is not None and path.parts and path.parts[0] == "results":
        return results.joinpath(*path.parts[1:])
    return root / path


def project_path_label(root, path, results=None):
    """Keep audit labels project-relative even for an external results root."""
    if results is not None and path.is_relative_to(results):
        return str(pathlib.Path("results") / path.relative_to(results))
    return str(path.relative_to(root)) if path.is_relative_to(root) else str(path)


def relative_resource_path(path, output_directory):
    """Return a portable document-relative resource path, including overrides."""
    return pathlib.Path(os.path.relpath(path, output_directory)).as_posix()


def required_value(mapping, *keys):
    """Read a required nested value; missing or null entries are errors."""
    value = mapping
    for index, key in enumerate(keys):
        if not isinstance(value, dict) or key not in value or value[key] is None:
            raise ValueError(f"Required configuration value missing: {'.'.join(keys[:index + 1])}")
        value = value[key]
    return value


def read_json(path, required_keys=()):
    """Read local UTF-8 JSON and validate explicitly required top-level keys."""
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    for key in required_keys:
        required_value(value, key)
    return value


def read_yaml(path):
    """Read a local YAML mapping safely, without network access or defaults."""
    import yaml

    with path.open(encoding="utf-8") as handle:
        value = yaml.safe_load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"Expected a configuration mapping: {path}")
    return value


def read_csv_rows(path, required_fields=()):
    """Read CSV records and reject absent headers or required source fields."""
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError("CSV has no header")
        missing = sorted(set(required_fields) - set(reader.fieldnames))
        if missing:
            raise ValueError(f"fields missing from CSV: {', '.join(missing)}")
        return list(reader)


def unique_csv_row(rows, row_filter):
    """Select exactly one CSV row using stripped source values and exact keys."""
    matches = [
        row for row in rows
        if all(str(row.get(field, "")).strip() == str(expected)
               for field, expected in row_filter.items())
    ]
    if len(matches) != 1:
        raise ValueError(f"source row filter matched {len(matches)} rows instead of one")
    return matches[0]


def read_unique_csv_row(path, row_filter):
    """Read one locked source row, rejecting missing filter fields or ambiguity."""
    # Validate filters against the header before selection, including empty CSVs.
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError("CSV has no header")
        missing = sorted(set(row_filter) - set(reader.fieldnames))
        if missing:
            raise ValueError(f"filter fields missing from CSV: {', '.join(missing)}")
        return unique_csv_row(reader, row_filter)


def sha256(path):
    """Return a file's SHA256 digest using bounded-memory reads."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()
