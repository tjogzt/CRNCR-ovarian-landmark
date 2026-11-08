#!/usr/bin/env python3
"""Deterministic case-level audit flags for the TCGA-OV first-line treatment dates.

File: 31_flag_treatment_dates.py
Purpose: Re-derive each labelled TCGA-OV patient's first-line regimen window from
    the archived GDC treatment records with the stage-15 rule, require exact
    agreement with the published Supplementary Data 1 dates, and write
    descriptive flags for record features that could make the recorded
    treatment end an imperfect landmark. No model is fitted, no patient is
    excluded or re-dated, and no random number is drawn.
Author: Project authors
Created: 2026-10-24
Inputs: data/processed/gdc_tcga_treatment_records.csv (GDC /cases treatment
    records, SHA256 listed in config/submission_profile.json); data/supplementary/
    SupplementaryData1_TCGA_OV_cases.csv; config/analysis.yml cohort and landmark
    date rules (start window, regimen join window, plausible end window, standard
    duration and treatment-type groups).
Outputs: data/supplementary/SupplementaryData3_treatment_date_flags.csv (one row
    per labelled patient) and results/tables/supplementary/
    treatment_date_flag_summary.csv (flag counts overall, in the landmark cohort
    and by response category within it).
Runtime parameters: none; paths are repository-relative and the results root
    follows the shared resolver in 28_submission_utilities.py.
Notes: Flags describe uncurated source records. They are not chart review, do
    not identify response-assessment dates and do not alter any locked result.
"""

import csv
import hashlib
import importlib
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
utilities = importlib.import_module("28_submission_utilities")

ROOT = utilities.repository_root(__file__)
RESULTS = utilities.results_directory(ROOT)
ANALYSIS = utilities.read_yaml(ROOT / "config" / "analysis.yml")
PROFILE = utilities.read_json(ROOT / "config" / "submission_profile.json")
RECORDS = ROOT / "data" / "processed" / "gdc_tcga_treatment_records.csv"
CASES = ROOT / "data" / "supplementary" / "SupplementaryData1_TCGA_OV_cases.csv"
FLAGS_OUT = ROOT / "data" / "supplementary" / "SupplementaryData3_treatment_date_flags.csv"
SUMMARY_OUT = RESULTS / "tables" / "supplementary" / "treatment_date_flag_summary.csv"

START_WINDOW = utilities.required_value(ANALYSIS, "cohort", "first_line_start_window_days")
JOIN_DAYS = utilities.required_value(ANALYSIS, "cohort", "regimen_join_window_days")
STANDARD_DURATION = utilities.required_value(ANALYSIS, "cohort", "standard_duration_days")
PLAUSIBLE_END = utilities.required_value(ANALYSIS, "landmark", "plausible_end_days")
TYPE_GROUPS = utilities.required_value(ANALYSIS, "cohort", "treatment_type_groups")
SYSTEMIC, RADIATION = set(TYPE_GROUPS["systemic"]), set(TYPE_GROUPS["radiation"])
RESPONSES = tuple(utilities.required_value(ANALYSIS, "response", "four_levels"))

# Each flag: output column, reader-facing definition. Order is the publication order.
FLAG_DEFINITIONS = [
    ("regimen_end_missing_some", "At least one first-line regimen record lacks an end date"),
    ("duplicate_regimen_records", "Identical type/agent/start/end records within the first-line regimen"),
    ("non_chemotherapy_record_in_regimen", "Hormonal, targeted, immunotherapy or unspecified pharmaceutical record in the regimen"),
    ("bevacizumab_in_regimen", "Bevacizumab recorded within the first-line regimen window"),
    ("bevacizumab_sets_end", "The first-line systemic end is set only by a bevacizumab record"),
    ("radiotherapy_extends_end", "Radiotherapy ends after the systemic regimen and sets the therapy end"),
    ("later_systemic_start", f"Systemic record starting >{JOIN_DAYS} days after the first start, within the start window"),
    ("later_systemic_before_end", "Such a later systemic record starts before the computed first-line end (possible switch)"),
    ("duration_outside_standard", f"First-line regimen duration outside {STANDARD_DURATION[0]}-{STANDARD_DURATION[1]} days"),
    ("start_before_diagnosis", "First-line start recorded before the diagnosis date"),
    ("therapy_end_not_plausible", f"Therapy end missing or outside {PLAUSIBLE_END[0]}-{PLAUSIBLE_END[1]} days"),
]


def number(value):
    """Parse a GDC day value; 'NA' and blanks are missing, never zero."""
    if value is None or value.strip() in ("", "NA"):
        return None
    result = float(value)
    return result if math.isfinite(result) else None


def same_day(a, b):
    """Compare optional day values exactly (both missing counts as equal)."""
    return (a is None and b is None) or (a is not None and b is not None and abs(a - b) < 1e-9)


def verify_input():
    """Lock both the archived GDC bytes and the published case population."""
    for path, key in ((RECORDS, "treatment_records_sha256"), (CASES, "treatment_cases_sha256")):
        expected = utilities.required_value(PROFILE, "publication_policy", key)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != expected:
            raise ValueError(f"Treatment audit input differs from the verified archive ({key}): {digest}")


def first_line(records):
    """Apply the stage-15 window rule to one patient's primary, given records."""
    systemic = [r for r in records if r["treatment_type"] in SYSTEMIC and r["start"] is not None
                and START_WINDOW[0] <= r["start"] <= START_WINDOW[1]]
    radiation = [r for r in records if r["treatment_type"] in RADIATION and r["start"] is not None
                 and START_WINDOW[0] <= r["start"] <= START_WINDOW[1]]
    if not systemic:
        regimen, later, s0, fl_end = [], [], None, None
    else:
        s0 = min(r["start"] for r in systemic)
        regimen = [r for r in systemic if r["start"] <= s0 + JOIN_DAYS]
        later = [r for r in systemic if r["start"] > s0 + JOIN_DAYS]
        ends = [r["end"] for r in regimen if r["end"] is not None]
        fl_end = max(ends) if ends else None
    rt_ends = [r["end"] for r in radiation if r["end"] is not None]
    rt_end = max(rt_ends) if rt_ends else None
    candidates = [v for v in (fl_end, rt_end) if v is not None]
    therapy_end = max(candidates) if candidates else None
    return regimen, later, s0, fl_end, rt_end, therapy_end


def flags_for(regimen, later, s0, fl_end, rt_end, therapy_end):
    """Return the descriptive flags; definitions are listed in FLAG_DEFINITIONS."""
    keys = [(r["treatment_type"], r["agents"], r["start"], r["end"]) for r in regimen]
    bev = [r for r in regimen if "bevacizumab" in r["agents"].lower()]
    other_ends = [r["end"] for r in regimen if r not in bev and r["end"] is not None]
    duration = fl_end - s0 if fl_end is not None and s0 is not None else None
    return {
        "regimen_end_missing_some": any(r["end"] is None for r in regimen),
        "duplicate_regimen_records": len(keys) != len(set(keys)),
        "non_chemotherapy_record_in_regimen": any(r["treatment_type"] != "Chemotherapy" for r in regimen),
        "bevacizumab_in_regimen": bool(bev),
        "bevacizumab_sets_end": bool(bev) and fl_end is not None and (not other_ends or max(other_ends) < fl_end),
        "radiotherapy_extends_end": rt_end is not None and fl_end is not None and rt_end > fl_end,
        "later_systemic_start": bool(later),
        "later_systemic_before_end": fl_end is not None and any(r["start"] < fl_end for r in later),
        "duration_outside_standard": duration is not None
            and not STANDARD_DURATION[0] <= duration <= STANDARD_DURATION[1],
        "start_before_diagnosis": s0 is not None and s0 < 0,
        "therapy_end_not_plausible": therapy_end is None
            or not PLAUSIBLE_END[0] <= therapy_end <= PLAUSIBLE_END[1],
    }


def main():
    verify_input()
    cases = utilities.read_csv_rows(CASES, ("patient", "response4", "fl_start", "fl_end",
                                            "therapy_end", "main_landmark_cohort"))
    wanted = {c["patient"] for c in cases}
    by_patient = {p: [] for p in wanted}
    for r in utilities.read_csv_rows(RECORDS, ("patient", "classification_of_tumor", "given",
                                               "treatment_type", "agents", "start", "end")):
        if r["patient"] in wanted and r["classification_of_tumor"] == "primary" and r["given"] == "yes":
            by_patient[r["patient"]].append({"treatment_type": r["treatment_type"],
                                             "agents": "" if r["agents"] == "NA" else r["agents"],
                                             "start": number(r["start"]), "end": number(r["end"])})
    rows, mismatches = [], []
    for case in cases:
        regimen, later, s0, fl_end, rt_end, therapy_end = first_line(by_patient[case["patient"]])
        # The audit is only meaningful if it reproduces the published dates exactly.
        if not (same_day(s0, number(case["fl_start"])) and same_day(fl_end, number(case["fl_end"]))
                and same_day(therapy_end, number(case["therapy_end"]))):
            mismatches.append(case["patient"])
            continue
        flags = flags_for(regimen, later, s0, fl_end, rt_end, therapy_end)
        rows.append({"patient": case["patient"], "response4": case["response4"],
                     "main_landmark_cohort": case["main_landmark_cohort"],
                     "fl_start": case["fl_start"], "fl_end": case["fl_end"], "therapy_end": case["therapy_end"],
                     "regimen_records": len(regimen),
                     **{k: "TRUE" if v else "FALSE" for k, v in flags.items()}})
    if mismatches:
        raise ValueError(f"Re-derived dates differ from Supplementary Data 1 for {len(mismatches)} patients: "
                         + ", ".join(mismatches[:10]))
    fields = list(rows[0])
    with FLAGS_OUT.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    landmark = [r for r in rows if r["main_landmark_cohort"] == "TRUE"]
    summary = []
    for key, definition in FLAG_DEFINITIONS:
        count = lambda subset: sum(r[key] == "TRUE" for r in subset)
        summary.append({"flag": key, "definition": definition,
                        "labelled_n": len(rows), "labelled_flagged": count(rows),
                        "landmark_n": len(landmark), "landmark_flagged": count(landmark),
                        **{f"landmark_{resp}": count([r for r in landmark if r["response4"] == resp])
                           for resp in RESPONSES}})
    with SUMMARY_OUT.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(summary[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(summary)
    print(f"Reproduced first-line dates for all {len(rows)} labelled patients; "
          f"wrote {len(FLAG_DEFINITIONS)} descriptive flags ({len(landmark)} landmark patients).")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print(f"Treatment-date audit stopped: {error}", file=sys.stderr)
        sys.exit(1)
