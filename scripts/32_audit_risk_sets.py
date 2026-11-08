#!/usr/bin/env python3
"""Descriptive, deterministic audit of the existing TCGA-OV landmark risk sets.

File: 32_audit_risk_sets.py
Purpose: Reproduce R17:87-119/144-146 and R18:90-124/368-383 eligibility
    using Supplementary Data 1, including the actual complete-case denominator
    of the existing adjusted NCR model (reported HR 1.52). Build PFI independently
    from all labelled cases, never by restricting first to the OS main cohort.
Author: Project authors
Created: 2026-10-24
Inputs: data/supplementary/SupplementaryData1_TCGA_OV_cases.csv; its SHA256 in
    config/submission_profile.json publication_policy.treatment_cases_sha256;
    config/analysis.yml plausible_end_days and four_levels; the four unique
    therapy_end OS/PFI none/age+stage+residual rows in the existing
    results/tables/ov_therapy_end_landmark/topology_by_landmark.csv.
Outputs: data/supplementary/SupplementaryData4_TCGA_OV_risk_set_audit.csv;
    results/tables/supplementary/risk_set_audit_summary.csv. No scientific
    source, configuration, manuscript or locked result is modified.
Runtime parameters: --check validates existing outputs without writing; the
    results root follows 28_submission_utilities.py. No directory is created.
Notes: No fitting, statistical testing, resampling, quantiles, imputation,
    re-dating or new inclusion rule. Real response-assessment dates were not
    provided. PFI later than OS is descriptive, not an automatic error/exclusion.
    Exclusion reasons are hierarchical (origin, days, event, time relation);
    flags may overlap. Event counts for exclusions describe recorded endpoints,
    not post-landmark events. Age completeness reproduces R complete.cases(age/10),
    not an additional finite-age filter. The power table's shared 99/80 design
    counts are not the adjusted NCR model's effective n/events.
"""

import argparse
import csv
import hashlib
import importlib
import io
import math
import pathlib
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
utilities = importlib.import_module("28_submission_utilities")

ROOT = utilities.repository_root(__file__)
DATA1_LABEL = "data/supplementary/SupplementaryData1_TCGA_OV_cases.csv"
TOPOLOGY_LABEL = "results/tables/ov_therapy_end_landmark/topology_by_landmark.csv"
STAGES = ("I-II", "III", "IV")
RESIDUALS = ("R0", "1-10 mm", "11-20 mm", ">20 mm")
REQUIRED_FIELDS = (
    "patient", "response4", "label_source", "age", "stage_group", "residual_group",
    "OS_days", "OS_event", "PFI_days", "PFI_event", "fl_start", "fl_end",
    "therapy_end", "main_landmark_cohort",
)
EXCLUSION_REASONS = (
    "therapy_end_missing", "therapy_end_nonfinite", "therapy_end_below_plausible_window",
    "therapy_end_above_plausible_window", "endpoint_days_missing", "endpoint_days_nonfinite",
    "endpoint_event_missing", "event_at_or_before_landmark", "censor_at_or_before_landmark",
)
FLAG_DEFINITIONS = (
    ("os_event_at_or_before_landmark", "Recorded OS event on/before plausible therapy-end origin"),
    ("os_censor_at_or_before_landmark", "Recorded OS censoring on/before plausible therapy-end origin"),
    ("pfi_event_at_or_before_landmark", "Recorded PFI event on/before plausible therapy-end origin"),
    ("pfi_censor_at_or_before_landmark", "Recorded PFI censoring on/before plausible therapy-end origin"),
    ("pfi_later_than_os_descriptive", "Finite PFI days exceed finite OS days; descriptive only, not an error rule"),
    ("fl_end_before_fl_start", "Finite recorded first-line end precedes first-line start"),
    ("therapy_end_before_fl_start", "Finite recorded therapy end precedes first-line start"),
    ("therapy_end_before_fl_end", "Finite recorded therapy end precedes first-line systemic end"),
    ("os_days_before_diagnosis", "Finite OS days are negative"),
    ("pfi_days_before_diagnosis", "Finite PFI days are negative"),
)


def number(value):
    """Preserve infinity (nonfinite, but not R NA); map blanks/NA/NaN to missing."""
    if value.strip() in ("", "NA", "NaN"):
        return None
    result = float(value)
    return None if math.isnan(result) else result


def finite(value):
    return value is not None and math.isfinite(value)


def verify_digest(actual, expected, label):
    if actual != expected:
        raise ValueError(f"SHA256 guard failed for {label}: {actual} != {expected}")


def origin_status(end, bounds):
    if end is None:
        return "therapy_end_missing"
    if not finite(end):
        return "therapy_end_nonfinite"
    if end < bounds[0]:
        return "therapy_end_below_plausible_window"
    if end > bounds[1]:
        return "therapy_end_above_plausible_window"
    return "plausible"


def endpoint_reason(status, origin, days, event):
    """R17 landmark_data filters, with mutually exclusive reader-facing reasons."""
    if status != "plausible":
        return status
    if days is None:
        return "endpoint_days_missing"
    if not finite(days):
        return "endpoint_days_nonfinite"
    if event is None:
        return "endpoint_event_missing"
    if days <= origin:
        return "event_at_or_before_landmark" if event == 1 else "censor_at_or_before_landmark"
    return "included"


def before(a, b):
    return finite(a) and finite(b) and a < b


def build_cases(cases, bounds, responses):
    """Keep source strings unchanged and append descriptive/eligibility columns."""
    rows = []
    for case in sorted(cases, key=lambda c: c["patient"]):
        if not case["patient"] or case["response4"] not in responses:
            raise ValueError(f"Invalid labelled patient/response: {case['patient']}")
        if case["main_landmark_cohort"] not in ("TRUE", "FALSE"):
            raise ValueError(f"Invalid Data1 main flag: {case['patient']}")
        age = number(case["age"])
        end = number(case["therapy_end"])
        status = origin_status(end, bounds)
        plausible = status == "plausible"
        origin = end if plausible else None
        stage_complete = case["stage_group"] in STAGES
        residual_complete = case["residual_group"] in RESIDUALS
        missing_covariates = [name for name, complete in (
            ("age_10y", age is not None), ("stage_group", stage_complete),
            ("residual_group", residual_complete),
        ) if not complete]
        row = {
            "patient": case["patient"], "response4": case["response4"],
            "label_source": case["label_source"], "age": case["age"],
            "stage_group": case["stage_group"], "residual_group": case["residual_group"],
            "age_10y": age / 10 if age is not None else "NA",
            "stage_group_r17": case["stage_group"] if stage_complete else "NA",
            "residual_group_r17": case["residual_group"] if residual_complete else "NA",
            "age_complete": age is not None, "stage_complete": stage_complete,
            "residual_complete": residual_complete,
            "covariates_complete": not missing_covariates,
            "missing_covariates": ";".join(missing_covariates) or "none",
            "fl_start": case["fl_start"], "fl_end": case["fl_end"],
            "therapy_end": case["therapy_end"], "therapy_end_status": status,
            "therapy_end_plausible": plausible,
            "origin_days": case["therapy_end"] if plausible else "NA",
            "main_landmark_cohort": case["main_landmark_cohort"],
            "response_assessment_date_provided": False,
        }
        for ep in ("OS", "PFI"):
            days, event = number(case[f"{ep}_days"]), number(case[f"{ep}_event"])
            # This is a source-schema assertion, not a replacement eligibility rule.
            if event is not None and event not in (0, 1):
                raise ValueError(f"Nonbinary {ep} source event: {case['patient']}")
            reason = endpoint_reason(status, origin, days, event)
            eligible = reason == "included"
            key = ep.lower()
            comparable = plausible and finite(days)
            row.update({
                f"{key}_days": case[f"{ep}_days"], f"{key}_event": case[f"{ep}_event"],
                f"{key}_days_finite": finite(days), f"{key}_event_not_missing": event is not None,
                f"{key}_eligible": eligible,
                f"{key}_adjusted_eligible": eligible and not missing_covariates,
                f"{key}_exclusion_reason": reason,
                f"{key}_event_at_or_before_landmark": comparable and event == 1 and days <= origin,
                f"{key}_censor_at_or_before_landmark": comparable and event == 0 and days <= origin,
            })
        row["os_main_flag_matches_data1"] = row["os_eligible"] == (case["main_landmark_cohort"] == "TRUE")
        if not row["os_main_flag_matches_data1"]:
            raise ValueError(f"Reproduced OS main flag differs from Data1: {case['patient']}")
        noncr = case["response4"] != "CR"
        row["ncr_unadjusted_eligible"] = row["os_eligible"] and noncr
        row["ncr_adjusted_eligible"] = row["os_adjusted_eligible"] and noncr
        os_days, pfi_days = number(case["OS_days"]), number(case["PFI_days"])
        start, fl_end = number(case["fl_start"]), number(case["fl_end"])
        row.update({
            "pfi_later_than_os_descriptive": before(os_days, pfi_days),
            "fl_end_before_fl_start": before(fl_end, start),
            "therapy_end_before_fl_start": before(end, start),
            "therapy_end_before_fl_end": before(end, fl_end),
            "os_days_before_diagnosis": finite(os_days) and os_days < 0,
            "pfi_days_before_diagnosis": finite(pfi_days) and pfi_days < 0,
            "pfi_eligible_not_os_eligible": row["pfi_eligible"] and not row["os_eligible"],
            "os_eligible_not_pfi_eligible": row["os_eligible"] and not row["pfi_eligible"],
        })
        rows.append(row)
    if len({r["patient"] for r in rows}) != len(rows):
        raise ValueError("Duplicate Data1 patient IDs")
    return rows


def counts(rows, ep, responses):
    return {"n": len(rows), "events": sum(number(r[f"{ep.lower()}_event"]) == 1 for r in rows),
            **{response: sum(r["response4"] == response for r in rows) for response in responses}}


def validate_topology(rows, topology, responses):
    """All four exact, unique source comparisons must pass before any write."""
    for ep in ("OS", "PFI"):
        for adjusted in (False, True):
            adjustment = "age+stage+residual" if adjusted else "none"
            source = utilities.unique_csv_row(topology, {
                "endpoint": ep, "landmark": "therapy_end", "adjustment": adjustment,
            })
            flag = f"{ep.lower()}_{'adjusted_' if adjusted else ''}eligible"
            actual = counts([r for r in rows if r[flag]], ep, responses)
            for field, value in actual.items():
                if float(source[field]) != value:
                    raise ValueError(f"Topology mismatch {ep}/{adjustment}/{field}: "
                                     f"derived {value}, source {source[field]}")


def build_summary(rows, responses, expected_digest, bounds):
    summary = []

    def add(metric, selected, ep, adjustment="none", reason="not_applicable", definition=""):
        for response in ("ALL", *responses):
            subset = selected if response == "ALL" else [r for r in selected if r["response4"] == response]
            denominator = rows if response == "ALL" else [r for r in rows if r["response4"] == response]
            events = sum(number(r[f"{ep.lower()}_event"]) == 1 for r in subset) if ep else "NA"
            censored = sum(number(r[f"{ep.lower()}_event"]) == 0 for r in subset) if ep else "NA"
            unavailable = sum(not r[f"{ep.lower()}_days_finite"] or not r[f"{ep.lower()}_event_not_missing"]
                              for r in subset) if ep else "NA"
            summary.append({
                "metric": metric, "endpoint": ep or "not_applicable", "landmark": "therapy_end",
                "adjustment": adjustment, "response4": response, "reason": reason,
                "labelled_denominator_n": len(denominator), "n": len(subset),
                "events": events, "censored": censored, "endpoint_unavailable_n": unavailable,
                "definition": definition, "no_fit": True,
                "response_assessment_date_provided": False,
                "data1_input": DATA1_LABEL, "data1_sha256": expected_digest,
                "verification_source": TOPOLOGY_LABEL,
                "plausible_end_min_days": bounds[0], "plausible_end_max_days": bounds[1],
            })

    risk_sets = (
        ("os_main", "os_eligible", "OS", "none", "R17/R18 OS main risk set; Data1 flags reproduced"),
        ("os_adjusted", "os_adjusted_eligible", "OS", "age+stage+residual", "R17 full-response OS common covariate-complete cases"),
        ("ncr_unadjusted", "ncr_unadjusted_eligible", "OS", "none", "R18 NCR-only OS model and shared power-design counts"),
        ("ncr_adjusted", "ncr_adjusted_eligible", "OS", "age+stage+residual", "R18 adjusted NCR model effective denominator (existing reported HR 1.52); not the shared power-design counts"),
        ("pfi_all", "pfi_eligible", "PFI", "none", "R17 PFI risk set built independently from all labelled cases, not restricted to OS"),
        ("pfi_adjusted", "pfi_adjusted_eligible", "PFI", "age+stage+residual", "R17 full-response PFI common covariate-complete cases"),
    )
    for metric, flag, ep, adjustment, definition in risk_sets:
        add(metric, [r for r in rows if r[flag]], ep, adjustment, definition=definition)
    for reason in EXCLUSION_REASONS:
        add("pfi_exclusion", [r for r in rows if r["pfi_exclusion_reason"] == reason], "PFI",
            reason=reason, definition="Hierarchical exclusion from all labelled cases; events/censoring are recorded source statuses, not post-landmark counts")
    add("pfi_excluded_total", [r for r in rows if not r["pfi_eligible"]], "PFI",
        definition="Sum of mutually exclusive PFI reasons; complements independently built PFI risk set")
    for flag, ep in (("pfi_eligible_not_os_eligible", "PFI"), ("os_eligible_not_pfi_eligible", "OS")):
        add(flag, [r for r in rows if r[flag]], ep, definition="Observed risk-set difference; no OS restriction is imposed on PFI construction")
    for flag, definition in FLAG_DEFINITIONS:
        ep = "PFI" if flag.startswith("pfi_") else "OS" if flag.startswith("os_") else ""
        add("date_logic_flag", [r for r in rows if r[flag]], ep, reason=flag, definition=definition)
    # Save the case-level OS flag agreement count, not merely a console assertion.
    add("os_main_flag_matches_data1", [r for r in rows if r["os_main_flag_matches_data1"]], "OS",
        definition="Every labelled patient's recomputed OS main eligibility equals the existing Data1 flag")
    return summary


def csv_bytes(rows):
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=list(rows[0]), lineterminator="\n")
    writer.writeheader()
    writer.writerows({key: ("TRUE" if value else "FALSE") if isinstance(value, bool) else value
                      for key, value in row.items()} for row in rows)
    return buffer.getvalue().encode("utf-8")


def expect_failure(action, label):
    try:
        action()
    except ValueError:
        return
    raise ValueError(f"Negative self-check failed: {label}")


def self_checks(cases, rows, topology, bounds, responses, expected_digest, source_bytes):
    """Only in-memory checks: never mutate active input, results or configuration."""
    changed_bytes = source_bytes + b"\n"
    expect_failure(lambda: verify_digest(hashlib.sha256(changed_bytes).hexdigest(), expected_digest, DATA1_LABEL),
                   "mutated Data1 SHA256 must be rejected")
    modified = [dict(c) for c in cases]
    modified[0]["main_landmark_cohort"] = "FALSE" if modified[0]["main_landmark_cohort"] == "TRUE" else "TRUE"
    expect_failure(lambda: build_cases(modified, bounds, responses), "changed OS main flag")
    source = utilities.unique_csv_row(topology, {"endpoint": "PFI", "landmark": "therapy_end", "adjustment": "none"})
    expect_failure(lambda: validate_topology(rows, [*topology, dict(source)], responses), "duplicate topology row")
    changed_topology = [dict(r) for r in topology]
    for r in changed_topology:
        if r["endpoint"] == "PFI" and r["landmark"] == "therapy_end" and r["adjustment"] == "none":
            r["n"] = str(int(r["n"]) + 1)
    expect_failure(lambda: validate_topology(rows, changed_topology, responses), "changed topology count")
    # Synthetic memory-only sentinel proves PFI is independent even though the
    # observed locked PFI set happens to be a subset of the observed OS set.
    sentinel = dict(cases[0], patient="MEMORY_ONLY_SENTINEL", response4=responses[1],
                    age="NA", stage_group="IIIC", residual_group="invalid", therapy_end=str(bounds[0]),
                    OS_days=str(bounds[0]), OS_event="0", PFI_days=str(bounds[0] + 1), PFI_event="1",
                    main_landmark_cohort="FALSE")
    test = build_cases([sentinel], bounds, responses)[0]
    if not (test["pfi_eligible_not_os_eligible"] and test["pfi_later_than_os_descriptive"]
            and test["os_censor_at_or_before_landmark"] and not test["covariates_complete"]
            and test["stage_group_r17"] == "NA" and test["residual_group_r17"] == "NA"):
        raise ValueError("Independent PFI / factor-level / missing-age self-check failed")
    if origin_status(bounds[1], bounds) != "plausible" or origin_status(bounds[1] + 1, bounds) == "plausible":
        raise ValueError("Inclusive plausible-origin boundary self-check failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate deterministic existing outputs; write nothing")
    args = parser.parse_args()
    results = utilities.results_directory(ROOT)
    analysis = utilities.read_yaml(ROOT / "config" / "analysis.yml")
    profile = utilities.read_json(ROOT / "config" / "submission_profile.json")
    expected = utilities.required_value(profile, "publication_policy", "treatment_cases_sha256")
    bounds = tuple(utilities.required_value(analysis, "landmark", "plausible_end_days"))
    responses = tuple(utilities.required_value(analysis, "response", "four_levels"))
    if len(bounds) != 2 or not all(finite(v) for v in bounds) or bounds[0] > bounds[1]:
        raise ValueError("Invalid configured plausible_end_days")
    if responses != ("CR", "PR", "SD", "PD"):
        raise ValueError("Configured response order differs from R17/R18 factor levels")
    cases_path = ROOT / DATA1_LABEL
    source_bytes = cases_path.read_bytes()
    verify_digest(hashlib.sha256(source_bytes).hexdigest(), expected, DATA1_LABEL)
    cases = utilities.read_csv_rows(cases_path, REQUIRED_FIELDS)
    verify_digest(utilities.sha256(cases_path), expected, DATA1_LABEL)
    if len(cases) != 454:
        raise ValueError(f"Locked labelled-cohort assertion failed: {len(cases)} != 454")
    topology_path = utilities.resolve_project_path(ROOT, TOPOLOGY_LABEL, results)
    topology_digest = utilities.sha256(topology_path)
    topology = utilities.read_csv_rows(topology_path, ("endpoint", "landmark", "adjustment", "n", "events", *responses))
    rows = build_cases(cases, bounds, responses)
    validate_topology(rows, topology, responses)
    self_checks(cases, rows, topology, bounds, responses, expected, source_bytes)
    summary = build_summary(rows, responses, expected, bounds)
    outputs = (
        (ROOT / "data/supplementary/SupplementaryData4_TCGA_OV_risk_set_audit.csv", csv_bytes(rows)),
        (results / "tables/supplementary/risk_set_audit_summary.csv", csv_bytes(summary)),
    )
    repeated_rows = build_cases(cases, bounds, responses)
    if outputs[0][1] != csv_bytes(repeated_rows) or outputs[1][1] != csv_bytes(build_summary(repeated_rows, responses, expected, bounds)):
        raise ValueError("In-memory deterministic rerun differs")
    # Preflight BOTH destinations and recheck sources before the first write.
    # Existing identical audit outputs are left untouched; differing files fail.
    verify_digest(utilities.sha256(cases_path), expected, DATA1_LABEL)
    verify_digest(utilities.sha256(topology_path), topology_digest, TOPOLOGY_LABEL)
    for path, content in outputs:
        if not path.parent.is_dir():
            raise ValueError(f"Output directory must already exist: {path.parent}")
        if path.exists() and path.read_bytes() != content:
            raise ValueError(f"Refusing to modify a differing existing output: {path}")
        if args.check and not path.is_file():
            raise ValueError(f"Missing audit output for --check: {path}")
    if not args.check:
        for path, content in outputs:
            if not path.exists():
                with path.open("xb") as handle:
                    handle.write(content)
    for r in summary:
        if r["response4"] == "ALL" and r["metric"] in (
            "os_main", "os_adjusted", "ncr_unadjusted", "ncr_adjusted", "pfi_all", "pfi_adjusted",
            "pfi_excluded_total", "pfi_eligible_not_os_eligible", "os_eligible_not_pfi_eligible",
        ):
            print(f"{r['metric']}: n={r['n']}, events={r['events']}")
        if r["response4"] == "ALL" and r["metric"] == "pfi_exclusion" and r["n"]:
            print(f"PFI exclusion {r['reason']}: n={r['n']}, recorded_events={r['events']}")
    print("PASS: 454 Data1 OS main flags; four unique topology count rows; "
          "in-memory negative guards and deterministic rerun; noFit.")
    print("Real response-assessment date: not provided. PFI > OS flags are descriptive only.")
    for path, content in outputs:
        print(f"{'Checked' if args.check else 'Created or unchanged'}: {path} "
              f"(SHA256 {hashlib.sha256(content).hexdigest()})")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print(f"Risk-set audit stopped before successful completion: {error}", file=sys.stderr)
        sys.exit(1)
