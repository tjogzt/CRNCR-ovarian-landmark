#!/usr/bin/env python3
"""Compare generated outputs with a reference tree and write a reconciliation table.

File: 25_reconcile_outputs.py
Purpose: Classify byte, schema, numeric, text, row-count and PDF-metadata differences between
    generated outputs and a locked reference without embedding expected values, and report
    reference outputs that are missing from the candidate.
Author: Project authors
Created: 2026-10-15
Inputs: Candidate and reference project roots supplied on the command line.
Runtime parameters: Absolute and relative numeric tolerances.
Outputs: A CSV reconciliation report selected by --report.
"""

import argparse
import csv
import importlib
import math
import pathlib
import re
import zlib
from decimal import Decimal, InvalidOperation


utilities = importlib.import_module("28_submission_utilities")
sha256 = utilities.sha256
SCOPES = ("results", "data/processed", "data/supplementary")
REPORT_COLUMNS = (
    "path",
    "file_type",
    "candidate_bytes",
    "reference_bytes",
    "status",
    "candidate_sha256",
    "reference_sha256",
    "rows_candidate",
    "rows_reference",
    "numeric_differences",
    "text_differences",
    "maximum_absolute_difference",
    "maximum_relative_difference",
    "detail",
)


def decimal_or_none(value):
    """Parse finite numeric cells, leaving missing/non-finite cells as text."""
    text = value.strip()
    if text in {"", "NA", "NaN", "Inf", "-Inf"}:
        return None
    try:
        number = Decimal(text)
    except InvalidOperation:
        return None
    return number if number.is_finite() else None


def compare_csv(candidate, reference, absolute_tolerance, relative_tolerance):
    """Compare matching CSV schemas positionally with absolute/relative limits."""
    with candidate.open(newline="", encoding="utf-8-sig") as handle:
        candidate_rows = list(csv.reader(handle))
    with reference.open(newline="", encoding="utf-8-sig") as handle:
        reference_rows = list(csv.reader(handle))
    result = {
        "rows_candidate": max(0, len(candidate_rows) - 1),
        "rows_reference": max(0, len(reference_rows) - 1),
        "numeric_differences": 0,
        "text_differences": 0,
        "maximum_absolute_difference": 0.0,
        "maximum_relative_difference": 0.0,
        "detail": "",
    }
    if not candidate_rows or not reference_rows:
        result["status"] = "EMPTY_FILE" if candidate_rows != reference_rows else "IDENTICAL"
        return result
    if candidate_rows[0] != reference_rows[0]:
        result["status"] = "SCHEMA_MISMATCH"
        result["detail"] = "CSV headers differ"
        return result
    if len(candidate_rows) != len(reference_rows):
        result["status"] = "ROW_COUNT_MISMATCH"
        result["detail"] = "CSV row counts differ"
        return result
    for candidate_row, reference_row in zip(candidate_rows[1:], reference_rows[1:]):
        if len(candidate_row) != len(reference_row):
            result["status"] = "SCHEMA_MISMATCH"
            result["detail"] = "CSV row widths differ"
            return result
        for candidate_value, reference_value in zip(candidate_row, reference_row):
            if candidate_value == reference_value:
                continue
            candidate_number = decimal_or_none(candidate_value)
            reference_number = decimal_or_none(reference_value)
            if candidate_number is None or reference_number is None:
                result["text_differences"] += 1
                continue
            absolute = abs(float(candidate_number - reference_number))
            denominator = max(abs(float(reference_number)), float(absolute_tolerance))
            relative = absolute / denominator if denominator else math.inf
            result["maximum_absolute_difference"] = max(result["maximum_absolute_difference"], absolute)
            result["maximum_relative_difference"] = max(result["maximum_relative_difference"], relative)
            # A cell differs numerically only if it exceeds both limits; the
            # absolute floor also keeps relative comparisons stable near zero.
            if absolute > float(absolute_tolerance) and relative > float(relative_tolerance):
                result["numeric_differences"] += 1
    if result["text_differences"]:
        result["status"] = "TEXT_DIFFERENCE"
    elif result["numeric_differences"]:
        result["status"] = "NUMERIC_DIFFERENCE"
    else:
        result["status"] = "NUMERICALLY_EQUIVALENT"
    return result


PDF_OBJECT = re.compile(rb"(\d+)\s+(\d+)\s+obj(.*?)endobj", re.S)
PDF_STREAM = re.compile(rb"^(.*?)stream\r?\n(.*?)\r?\nendstream", re.S)
PDF_VOLATILE = re.compile(rb"/(?:CreationDate|ModDate)\s*\([^)]*\)|/Length\s+\d+(?:\s+0\s+R)?")


def pdf_signature(path):
    """Return PDF objects with timestamps, stream lengths and xref offsets removed."""
    objects = []
    for match in PDF_OBJECT.finditer(path.read_bytes()):
        body = match.group(3)
        if body.strip().isdigit():
            # Indirect stream-length objects change with compressed timestamps.
            continue
        stream = PDF_STREAM.match(body)
        if stream:
            dictionary, payload = stream.group(1), stream.group(2)
            if b"/XRef" in dictionary:
                continue
            if b"/FlateDecode" in dictionary:
                try:
                    payload = zlib.decompress(payload)
                except zlib.error:
                    pass
            body = dictionary + b"stream" + payload
        objects.append((match.group(1), PDF_VOLATILE.sub(b"", body)))
    return objects


def compare_file(candidate, reference, absolute_tolerance, relative_tolerance):
    """Classify an output by hashes, CSV values or normalized PDF objects."""
    candidate_hash = sha256(candidate)
    base = {
        "file_type": candidate.suffix.lower().lstrip(".") or "none",
        "candidate_bytes": candidate.stat().st_size,
        "reference_bytes": reference.stat().st_size if reference else "",
        "candidate_sha256": candidate_hash,
        "reference_sha256": sha256(reference) if reference else "",
        "rows_candidate": "",
        "rows_reference": "",
        "numeric_differences": "",
        "text_differences": "",
        "maximum_absolute_difference": "",
        "maximum_relative_difference": "",
        "detail": "",
    }
    if reference is None:
        return {**base, "status": "NEW_OUTPUT"}
    if candidate_hash == base["reference_sha256"]:
        return {**base, "status": "IDENTICAL"}
    if candidate.suffix.lower() == ".csv":
        return {**base, **compare_csv(candidate, reference, absolute_tolerance, relative_tolerance)}
    if candidate.suffix.lower() == ".pdf":
        candidate_objects = pdf_signature(candidate)
        if candidate_objects and candidate_objects == pdf_signature(reference):
            return {
                **base,
                "status": "PDF_METADATA_ONLY",
                "detail": "Objects identical after removing timestamps, stream lengths and xref offsets",
            }
    return {**base, "status": "BINARY_DIFFERENCE"}


def main():
    """Reconcile both output trees, write the chosen report and enforce CLI policy."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True, type=pathlib.Path)
    parser.add_argument("--reference", required=True, type=pathlib.Path)
    parser.add_argument("--report", required=True, type=pathlib.Path)
    parser.add_argument("--absolute-tolerance", default="1e-8", type=Decimal)
    parser.add_argument("--relative-tolerance", default="1e-7", type=Decimal)
    parser.add_argument("--fail-on-difference", action="store_true")
    args = parser.parse_args()
    # Explicit CLI tree paths retain caller-relative semantics; unlike the
    # results environment override, these are not repository configuration.
    candidate_root = args.candidate.resolve()
    reference_root = args.reference.resolve()
    rows = []
    for scope in SCOPES:
        scope_root = candidate_root / scope
        if not scope_root.exists():
            continue
        for candidate in sorted(path for path in scope_root.rglob("*") if path.is_file()):
            relative = candidate.relative_to(candidate_root)
            reference = reference_root / relative
            row = compare_file(
                candidate,
                reference if reference.is_file() else None,
                args.absolute_tolerance,
                args.relative_tolerance,
            )
            rows.append({"path": relative.as_posix(), **row})
    # Reference outputs that the candidate no longer produces are reported, not ignored.
    seen = {row["path"] for row in rows}
    for scope in SCOPES:
        scope_root = reference_root / scope
        if not scope_root.exists():
            continue
        for reference in sorted(path for path in scope_root.rglob("*") if path.is_file()):
            relative = reference.relative_to(reference_root).as_posix()
            if relative in seen:
                continue
            rows.append({column: "" for column in REPORT_COLUMNS} | {
                "path": relative,
                "file_type": reference.suffix.lower().lstrip(".") or "none",
                "reference_bytes": reference.stat().st_size,
                "reference_sha256": sha256(reference),
                "status": "MISSING_IN_CANDIDATE",
            })
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=REPORT_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    counts = {}
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
    print(f"Compared {len(rows)} candidate outputs: {counts}")
    if args.fail_on_difference:
        accepted = {"IDENTICAL", "NUMERICALLY_EQUIVALENT", "PDF_METADATA_ONLY", "NEW_OUTPUT"}
        failures = [row for row in rows if row["status"] not in accepted]
        if failures:
            raise SystemExit(f"Output reconciliation failed for {len(failures)} files")


if __name__ == "__main__":
    main()
