#!/usr/bin/env python3
"""Validate numeric manuscript claims and formal-figure provenance.

File: 24_validate_manuscript_claims.py
Purpose: Compare displayed manuscript numbers with filtered source CSV rows and
    verify that staged formal figures are byte-identical to their sources.
Author: Project authors
Created: 2026-10-15
Inputs: config/manuscript_claims.json, manuscript files, result CSV files, and
    results/tables/manuscript/figure_provenance.csv.
Runtime parameters: CRNCR_RESULTS_DIR optionally overrides the results directory;
    relative values are resolved against the script's repository root.
Outputs: manuscript_claim_audit.csv and figure_provenance_audit.csv under the
    configured results directory.
"""

import csv
import importlib
import re
import sys
from decimal import Decimal, InvalidOperation


utilities = importlib.import_module("28_submission_utilities")
ROOT = utilities.repository_root(__file__)
RESULTS = utilities.results_directory(ROOT)
read_unique_csv_row = utilities.read_unique_csv_row
sha256 = utilities.sha256
CONFIG = ROOT / "config" / "manuscript_claims.json"
REPORT_DIR = RESULTS / "tables" / "manuscript"
CLAIM_REPORT = REPORT_DIR / "manuscript_claim_audit.csv"
FIGURE_PROVENANCE = REPORT_DIR / "figure_provenance.csv"
FIGURE_REPORT = REPORT_DIR / "figure_provenance_audit.csv"

SUPERSCRIPT_DIGITS = str.maketrans("⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻", "0123456789+-")
CLAIM_COLUMNS = [
    "claim_id",
    "manuscript_file",
    "source_file",
    "source_field",
    "displayed_value",
    "source_value",
    "tolerance",
    "status",
    "detail",
]
FIGURE_COLUMNS = [
    "source",
    "destination",
    "source_sha256",
    "destination_sha256",
    "status",
    "detail",
]


def parse_number(value):
    """Parse decimal, scientific, or multiplication-sign scientific notation."""
    text = str(value).strip().replace(",", "").replace("−", "-")
    multiplied = re.fullmatch(
        r"([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*[×x]\s*10(?:\^)?([⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻+-]+)",
        text,
    )
    if multiplied:
        exponent = int(multiplied.group(2).translate(SUPERSCRIPT_DIGITS))
        return Decimal(multiplied.group(1)) * (Decimal(10) ** exponent)
    try:
        return Decimal(text)
    except InvalidOperation as exc:
        raise ValueError(f"not a supported number: {value!r}") from exc


def paragraph_at(text, position):
    """Return the Markdown paragraph containing a character position."""
    start = text.rfind("\n\n", 0, position)
    end = text.find("\n\n", position)
    return text[start + 2 if start >= 0 else 0 : end if end >= 0 else len(text)]


def failure_row(claim, detail, source_field=""):
    """Create one claim-level failure record."""
    return {
        "claim_id": claim.get("claim_id", ""),
        "manuscript_file": claim.get("manuscript_file", ""),
        "source_file": claim.get("source_file", ""),
        "source_field": source_field,
        "displayed_value": "",
        "source_value": "",
        "tolerance": "",
        "status": "FAIL",
        "detail": detail,
    }


def validate_claim(claim):
    """Validate all mapped fields for one declarative claim."""
    required = {
        "claim_id",
        "manuscript_file",
        "anchor",
        "pattern",
        "source_file",
        "row_filter",
        "field_map",
        "display_precision",
        "tolerance",
        "description",
    }
    missing_keys = sorted(required - set(claim))
    if missing_keys:
        return [failure_row(claim, f"configuration keys missing: {', '.join(missing_keys)}")]

    manuscript_path = ROOT / claim["manuscript_file"]
    source_path = RESULTS / claim["source_file"]
    if not manuscript_path.is_file():
        return [failure_row(claim, "manuscript file is missing")]
    if not source_path.is_file():
        return [failure_row(claim, "source CSV is missing")]

    text = manuscript_path.read_text(encoding="utf-8")
    anchor_count = text.count(claim["anchor"])
    if anchor_count == 0:
        return [failure_row(claim, "anchor is missing")]
    if anchor_count != 1:
        return [failure_row(claim, f"anchor occurs {anchor_count} times instead of once")]
    scope = paragraph_at(text, text.index(claim["anchor"]))

    try:
        pattern = re.compile(claim["pattern"], re.UNICODE)
    except re.error as exc:
        return [failure_row(claim, f"invalid regular expression: {exc}")]
    matches = list(pattern.finditer(scope))
    if len(matches) != 1:
        return [failure_row(claim, f"regular expression matched {len(matches)} times instead of once")]
    match = matches[0]

    try:
        source_row = read_unique_csv_row(source_path, claim["row_filter"])
    except (OSError, ValueError) as exc:
        return [failure_row(claim, str(exc))]

    output = []
    for source_field, group_name in claim["field_map"].items():
        base = {
            "claim_id": claim["claim_id"],
            "manuscript_file": claim["manuscript_file"],
            "source_file": claim["source_file"],
            "source_field": source_field,
            "displayed_value": "",
            "source_value": source_row.get(source_field, ""),
            "tolerance": "",
            "status": "FAIL",
            "detail": "",
        }
        if source_field not in source_row:
            base["detail"] = "source field is missing"
            output.append(base)
            continue
        if group_name not in pattern.groupindex:
            base["detail"] = "mapped named group is missing from the regular expression"
            output.append(base)
            continue
        if source_field not in claim["display_precision"]:
            base["detail"] = "display precision is missing"
            output.append(base)
            continue

        displayed_raw = match.group(group_name)
        source_raw = source_row[source_field]
        base["displayed_value"] = displayed_raw
        try:
            precision = int(claim["display_precision"][source_field])
            if precision < 0:
                raise ValueError("display precision must be non-negative")
            configured_tolerance = claim["tolerance"].get(source_field)
            # Half a displayed unit is a rounding rule, not an assumed
            # scientific result; explicitly configured tolerances take priority.
            tolerance = (
                Decimal(str(configured_tolerance))
                if configured_tolerance is not None
                else Decimal("0.5") * (Decimal(10) ** -precision)
            )
            if tolerance < 0:
                raise ValueError("tolerance must be non-negative")
            displayed = parse_number(displayed_raw)
            source = parse_number(source_raw)
        except (TypeError, ValueError, InvalidOperation) as exc:
            base["detail"] = str(exc)
            output.append(base)
            continue

        difference = abs(displayed - source)
        base["tolerance"] = str(tolerance)
        if difference <= tolerance:
            base["status"] = "PASS"
            base["detail"] = f"absolute difference {difference}"
        else:
            base["detail"] = f"absolute difference {difference} exceeds tolerance"
        output.append(base)
    return output


def write_csv(path, columns, rows):
    """Write an audit table with a stable column order."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def resolve_provenance_path(value):
    """Resolve project-relative paths while honoring an overridden results root."""
    return utilities.resolve_project_path(ROOT, value, results=RESULTS)


def validate_figure_provenance():
    """Hash each declared source/destination figure pair and compare digests."""
    if not FIGURE_PROVENANCE.is_file():
        return [
            {
                "source": "",
                "destination": "",
                "source_sha256": "",
                "destination_sha256": "",
                "status": "FAIL",
                "detail": "figure_provenance.csv is missing; run the manuscript-output stage first",
            }
        ]

    rows = []
    try:
        with FIGURE_PROVENANCE.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames is None or not {"source", "destination"}.issubset(reader.fieldnames):
                raise ValueError("figure provenance must contain source and destination columns")
            provenance_rows = list(reader)
    except (OSError, ValueError) as exc:
        return [
            {
                "source": "",
                "destination": "",
                "source_sha256": "",
                "destination_sha256": "",
                "status": "FAIL",
                "detail": str(exc),
            }
        ]

    if not provenance_rows:
        return [
            {
                "source": "",
                "destination": "",
                "source_sha256": "",
                "destination_sha256": "",
                "status": "FAIL",
                "detail": "figure provenance contains no rows",
            }
        ]

    for item in provenance_rows:
        source_text = item.get("source", "").strip()
        destination_text = item.get("destination", "").strip()
        record = {
            "source": source_text,
            "destination": destination_text,
            "source_sha256": "",
            "destination_sha256": "",
            "status": "FAIL",
            "detail": "",
        }
        if not source_text or not destination_text:
            record["detail"] = "source or destination path is empty"
            rows.append(record)
            continue
        source = resolve_provenance_path(source_text)
        destination = resolve_provenance_path(destination_text)
        missing = [label for label, path in (("source", source), ("destination", destination)) if not path.is_file()]
        if missing:
            record["detail"] = f"missing {' and '.join(missing)} file"
            rows.append(record)
            continue
        record["source_sha256"] = sha256(source)
        record["destination_sha256"] = sha256(destination)
        if record["source_sha256"] == record["destination_sha256"]:
            record["status"] = "PASS"
            record["detail"] = "SHA256 digests match"
        else:
            record["detail"] = "SHA256 digests differ"
        rows.append(record)
    return rows


def main():
    """Run claim and figure audits and return a nonzero status on any failure."""
    try:
        configuration = utilities.read_json(CONFIG)
    except (OSError, ValueError) as exc:
        raise SystemExit(f"Unable to read claim configuration: {exc}") from exc

    claims = configuration.get("claims")
    if not isinstance(claims, list) or not claims:
        raise SystemExit("Claim configuration must contain a non-empty claims list")

    claim_rows = []
    seen_ids = set()
    for claim in claims:
        claim_id = claim.get("claim_id", "") if isinstance(claim, dict) else ""
        if not isinstance(claim, dict):
            claim_rows.append(failure_row({}, "claim entry is not an object"))
            continue
        if not claim_id:
            claim_rows.append(failure_row(claim, "claim_id is empty"))
            continue
        if claim_id in seen_ids:
            claim_rows.append(failure_row(claim, "claim_id is duplicated"))
            continue
        seen_ids.add(claim_id)
        claim_rows.extend(validate_claim(claim))

    figure_rows = validate_figure_provenance()
    write_csv(CLAIM_REPORT, CLAIM_COLUMNS, claim_rows)
    write_csv(FIGURE_REPORT, FIGURE_COLUMNS, figure_rows)

    claim_failures = sum(row["status"] != "PASS" for row in claim_rows)
    figure_failures = sum(row["status"] != "PASS" for row in figure_rows)
    figure_entries = sum(bool(row["source"] or row["destination"]) for row in figure_rows)
    print(f"Validated {len(claims)} manuscript claims ({claim_failures} failed fields).")
    print(f"Validated {figure_entries} figure provenance entries ({figure_failures} failed).")
    print(f"Claim audit: {CLAIM_REPORT}")
    print(f"Figure audit: {FIGURE_REPORT}")
    return 1 if claim_failures or figure_failures else 0


if __name__ == "__main__":
    sys.exit(main())
