#!/usr/bin/env python3
"""Build a deterministic reporting/navigation bundle from frozen results.

File: 33_build_reporting_bundle.py
Purpose: Select approved existing results, validate reporting schemas and record
    portable provenance without fitting models or changing scientific inputs.
Author: Project authors
Created: 2026-10-24
Inputs: Frozen result and Data 1-4 CSVs, config/submission_profile.json,
    config/external_cohort_reporting.json, config/manuscript_claims.json,
    config/supplementary_data_dictionary.json, script-31 flag declarations and
    config/external_decision_rule_record.json (the byte-verified historical
    section-6 excerpt, shipped locally so builds need no external archive).
Outputs: results/tables/supplementary/TableS5_landmark_OS_results.csv,
    results/tables/supplementary/TableS6_primary_external_scores.csv and
    data/supplementary/SupplementaryData5_reporting_bundle.zip, containing
    selected frozen results, dictionary, reporting index, provenance and hashes.
Runtime parameters: none; build_reporting_bundle() returns output paths, member
    hashes, the bundle SHA256 and a portable summary. Does not consult cwd or
    results-path overrides, so this reporting-only task stays in the release root.
Dependencies: Python standard library and 28_submission_utilities.py.
Notes: No fitting, statistical testing, resampling, new quantiles, weights,
    reconstructed standard errors, software-version claims or retracted pools.
"""

import ast
import csv
import hashlib
import importlib
import io
import json
import math
import pathlib
import re
import sys
import zipfile
from decimal import Decimal, InvalidOperation

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
utilities = importlib.import_module("28_submission_utilities")
ROOT = utilities.repository_root(__file__)
PRIMARY_COHORTS = frozenset(("GSE63885", "GSE23554", "GSE30161"))
S5_PATH = "results/tables/supplementary/TableS5_landmark_OS_results.csv"
S6_PATH = "results/tables/supplementary/TableS6_primary_external_scores.csv"
BUNDLE_PATH = "data/supplementary/SupplementaryData5_reporting_bundle.zip"
S6_FIELDS = (
    "score", "k", "n_total", "cohorts", "negative_direction_k",
    "REML_estimate", "REML_low", "REML_high", "REML_p", "HKSJ_low",
    "HKSJ_high", "HKSJ_p", "I2", "PI_low", "PI_high",
)


DICTIONARY_PATH = "config/supplementary_data_dictionary.json"
PLAN_RECORD_PATH = "config/external_decision_rule_record.json"
AXES = ("general_proliferation", "replication_licensing", "dna_synthesis",
        "atr_checkpoint", "replication_composite")
DATA_FILES = ("SupplementaryData1_TCGA_OV_cases.csv", "SupplementaryData2_external_samples.csv",
              "SupplementaryData3_treatment_date_flags.csv",
              "SupplementaryData4_TCGA_OV_risk_set_audit.csv")
SCRIPT_PREFIXES = {
    "tables/ov_therapy_end_landmark/": "scripts/17_fit_therapy_end_landmark.R",
    "tables/ov_selection_regimen_power/": "scripts/18_analyze_selection_regimen_power.R",
    "tables/ov_hgsoc_sensitivity/": "scripts/19_analyze_hgsoc_sensitivity.R",
    "tables/ov_response_sensitivity/": "scripts/34_response_partition_calibration_sensitivity.R",
    "tables/ov_selection_tipping/": "scripts/35_landmark_selection_tipping.R",
    "tables/phase4_external_validation/": "scripts/14_validate_locked_scores.R",
    "tables/pancancer_topology/": "scripts/16_fit_pancancer_topology.R",
    "tables/manuscript/": "scripts/20_build_manuscript_outputs.R",
    "tables/supplementary/risk_set_audit_summary.csv": "scripts/32_audit_risk_sets.py",
    "tables/supplementary/treatment_date_flag_summary.csv": "scripts/31_flag_treatment_dates.py",
    "tables/supplementary/TableS7_response_partition_scan.csv": "scripts/34_response_partition_calibration_sensitivity.R",
    "tables/supplementary/TableS7_evalues.csv": "scripts/34_response_partition_calibration_sensitivity.R",
}


class FrozenInputs:
    """Track the exact bytes read and reject any source change during a build."""

    def __init__(self):
        self.records = {}
        self.paths = {}
        self.content = {}
        self.tables = {}

    def bytes(self, logical_path):
        logical = pathlib.PurePosixPath(logical_path)
        if logical.is_absolute() or ".." in logical.parts:
            raise ValueError("Input manifest paths must be portable relative paths")
        if logical_path not in self.records:
            path = ROOT / logical_path
            content = path.read_bytes()
            self.records[logical_path] = {"source_path": logical_path, "bytes": len(content),
                                          "sha256": hashlib.sha256(content).hexdigest()}
            self.paths[logical_path] = path
            self.content[logical_path] = content
        return self.content[logical_path]

    def json(self, logical_path, required_keys=()):
        self.bytes(logical_path)
        return utilities.read_json(self.paths[logical_path], required_keys)

    def csv(self, logical_path, required_fields=()):
        """Use utility 28 for source rows; inspect actual headers, never infer them."""
        if logical_path not in self.tables:
            content = self.bytes(logical_path).decode("utf-8-sig")
            fields = next(csv.reader(io.StringIO(content, newline="")), None)
            if not fields or len(fields) != len(set(fields)):
                raise ValueError(f"Missing or duplicate CSV header: {logical_path}")
            rows = utilities.read_csv_rows(self.paths[logical_path], required_fields)
            if any(None in row or any(value is None for value in row.values()) for row in rows):
                raise ValueError(f"Malformed CSV record: {logical_path}")
            self.tables[logical_path] = fields, rows
        fields, rows = self.tables[logical_path]
        if set(required_fields) - set(fields):
            raise ValueError(f"Required source fields absent: {logical_path}")
        return fields, rows

    def verify(self, profile):
        """Check read consistency and profile-recorded locks without inventing locks."""
        locks = utilities.required_value(profile, "publication_policy", "locked_source_sha256")
        case_lock = utilities.required_value(profile, "publication_policy", "treatment_cases_sha256")
        for logical, record in self.records.items():
            if utilities.sha256(self.paths[logical]) != record["sha256"]:
                raise ValueError(f"Input changed while building: {logical}")
            expected = (case_lock if logical == "data/supplementary/" + DATA_FILES[0]
                        else locks.get(logical))
            if expected is not None and record["sha256"] != expected:
                raise ValueError(f"Input differs from its profile-recorded lock: {logical}")


def csv_bytes(fields, rows):
    """Serialize without numerical conversion, rounding or missing-value edits."""
    handle = io.StringIO(newline="")
    writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows({field: row[field] for field in fields} for row in rows)
    return handle.getvalue().encode("utf-8")


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def primary_pool(inputs):
    """Require the approved pool and the profile's actual primary analysis mode."""
    profile = inputs.json("config/submission_profile.json")
    analysis = utilities.required_value(profile, "publication_policy", "external_pool_analysis")
    if analysis != "primary_external":
        raise ValueError("Profile does not select primary_external")
    crosswalk = inputs.json("config/external_cohort_reporting.json", ("cohorts",))
    names = [row["cohort"] for row in crosswalk["cohorts"]]
    if len(names) != 3 or set(names) != PRIMARY_COHORTS:
        raise ValueError("Reporting crosswalk differs from the approved three-cohort pool")
    excluded = set(utilities.required_value(profile, "publication_policy", "excluded_cohorts"))
    if excluded & PRIMARY_COHORTS:
        raise ValueError("An approved primary cohort is excluded by the profile")
    return analysis, profile, crosswalk["cohorts"]


def landmark_results(inputs):
    source = "results/tables/ov_therapy_end_landmark/topology_by_landmark.csv"
    fields, rows = inputs.csv(source, ("endpoint", "landmark", "adjustment"))
    selected = [row for row in rows if row["endpoint"] == "OS"]
    origins = ("none", "fixed183", "fixed270", "fixed365", "therapy_end",
               "therapy_end_plus30", "therapy_end_any", "therapy_end_imputed")
    expected = {(origin, adjustment) for origin in origins
                for adjustment in ("none", "age+stage+residual")}
    keys = [(row["landmark"], row["adjustment"]) for row in selected]
    if len(keys) != 16 or len(set(keys)) != 16 or set(keys) != expected:
        raise ValueError("OS landmark results must contain all unique 8 x 2 combinations")
    return csv_bytes(fields, selected)


def external_results(inputs, analysis):
    source = "results/tables/phase4_external_validation/meta_analysis_noncr_minus_cr.csv"
    _, rows = inputs.csv(source, ("analysis",) + S6_FIELDS)
    selected = [dict(row) for row in rows if row["analysis"] == analysis]
    if not selected or len({row["score"] for row in selected}) != len(selected):
        raise ValueError("Empty or duplicate primary external score results")
    for row in selected:
        cohorts = row["cohorts"].split(";")
        if len(cohorts) != 3 or set(cohorts) != PRIMARY_COHORTS or row["k"] != "3":
            raise ValueError("Primary external results do not use exactly the approved pool")
        row["adjustment"] = ("general_proliferation" if row["score"] ==
                             "licensing_given_proliferation" else "response_only")
    scores = {row["score"] for row in selected}
    if "licensing_given_proliferation" not in scores:
        raise ValueError("The existing proliferation-adjusted licensing result is absent")
    return csv_bytes(S6_FIELDS + ("adjustment",), selected), scores


def per_cohort_results(inputs, scores):
    source = "results/tables/phase4_external_validation/per_cohort_noncr_minus_cr_estimates.csv"
    required = ("score", "n", "CR", "Non_CR", "estimate", "se", "p_value", "cohort", "set", "adjustment")
    fields, rows = inputs.csv(source, required)
    if set(fields) != set(required):
        raise ValueError("Per-cohort source schema changed; do not export unapproved fields")
    selected = [row for row in rows if row["set"] == "primary" and row["cohort"] in PRIMARY_COHORTS]
    keys = [(row["score"], row["cohort"], row["adjustment"]) for row in selected]
    expected = {(score, cohort, adjustment) for score in scores for cohort in PRIMARY_COHORTS
                for adjustment in ("none", "debulking")}
    if len(keys) != len(set(keys)) or set(keys) != expected:
        raise ValueError("Incomplete or duplicate approved primary per-cohort score estimates")
    return csv_bytes(fields, selected), len(selected)


def external_survival_inputs(inputs, landmark_days):
    """Per-cohort Cox inputs behind the pooled NCR-versus-CR hazard ratio.

    Only the approved three cohorts at the configured landmark are exported.
    The full source table also contains the retracted series and TCGA rows,
    which must not enter the external evidence bundle.
    """
    source = "results/tables/phase4_external_validation/os_cox_noncr_vs_cr.csv"
    required = ("cohort", "landmark_days", "n", "events", "CR", "Non_CR", "log_HR",
                "se", "HR", "HR_low", "HR_high", "p_value")
    fields, rows = inputs.csv(source, required)
    selected = [row for row in rows if row["cohort"] in PRIMARY_COHORTS
                and row["landmark_days"] == str(landmark_days)]
    if len(selected) != 3 or {row["cohort"] for row in selected} != PRIMARY_COHORTS:
        raise ValueError("Per-cohort survival inputs are not exactly the approved three cohorts")
    for row in selected:
        if abs(float(row["HR"]) - math.exp(float(row["log_HR"]))) > 1e-6:
            raise ValueError("Per-cohort hazard ratio disagrees with its log scale")
        if not float(row["HR_low"]) < float(row["HR"]) < float(row["HR_high"]):
            raise ValueError("Per-cohort hazard ratio falls outside its interval")
    return csv_bytes(fields, selected)


def label_source_results(inputs):
    """Locked 307- and 306-patient label-source sensitivity models."""
    members = {}
    for name in ("topology_excluding_cdr_only.csv", "topology_strictly_concordant.csv"):
        fields, rows = inputs.csv("results/tables/ov_therapy_end_landmark/" + name,
                                  ("adjustment", "excluded", "n", "events", "HR_NonCR",
                                   "HR_NonCR_low", "HR_NonCR_high", "plateau_p", "ORR_p",
                                   "best_AIC", "best_BIC"))
        if len(rows) != 2 or {row["adjustment"] for row in rows} != {"none", "age+stage+residual"}:
            raise ValueError(f"Label-source sensitivity rows are incomplete: {name}")
        members[name] = csv_bytes(fields, rows)
    return members


def audit_members(inputs, crosswalk):
    source = "results/tables/phase4_external_validation/external_cohort_audit.csv"
    fields, rows = inputs.csv(source, ("cohort", "set", "retracted_source"))
    selected = [row for row in rows if row["set"] == "primary" and row["cohort"] in PRIMARY_COHORTS]
    if len(selected) != 3 or {row["cohort"] for row in selected} != PRIMARY_COHORTS:
        raise ValueError("Primary external cohort audit is not exactly the approved three cohorts")
    if any(row["retracted_source"] != "FALSE" for row in selected):
        raise ValueError("Retracted source cannot enter the reporting audit")
    members = {"external_cohort_audit.csv": csv_bytes(fields, selected)}
    coverage = tuple("cov_" + axis for axis in AXES)
    inventory_source = "results/tables/external_response_inventory/external_response_cohort_inventory.csv"
    _, inventory = inputs.csv(inventory_source, ("source", "dataset") + coverage)
    expected_datasets = {"GSE63885", "GSE23554", "GSE30161_eset"}
    if {row["inventory_dataset"] for row in crosswalk} != expected_datasets:
        raise ValueError("Inventory crosswalk differs from the approved dataset identities")
    coverage_rows = []
    for row in crosswalk:
        matched = utilities.unique_csv_row(inventory, {"dataset": row["inventory_dataset"]})
        coverage_rows.append({"cohort": row["cohort"], **matched})
    members["external_inventory_axis_coverage.csv"] = csv_bytes(
        ("cohort", "source", "dataset") + coverage, coverage_rows)
    gene_source = "results/tables/phase3_replication_multiomics/locked_score_gene_audit.csv"
    gene_fields, genes = inputs.csv(gene_source, ("axis", "pathway_members", "measured_gene_n", "measured_genes"))
    if "reporting_role" in gene_fields:
        raise ValueError("Gene audit already has an unexpected reporting_role field")
    if len(genes) != 6 or {row["axis"] for row in genes} != set(AXES) | {"robust_nine_composite"}:
        raise ValueError("Locked gene audit must retain all six existing axes/composites")
    annotated = []
    for row in genes:
        measured = row["measured_genes"].split(";")
        if not all(measured) or len(measured) != len(set(measured)) or len(measured) != int(row["measured_gene_n"]):
            raise ValueError(f"Incomplete measured gene list for {row['axis']}")
        role = "additional exploratory" if row["axis"] == "robust_nine_composite" else "locked axis"
        annotated.append({**row, "reporting_role": role})
    members["locked_score_gene_audit.csv"] = csv_bytes(tuple(gene_fields) + ("reporting_role",), annotated)
    return members


def dictionary_member(inputs):
    """Require complete exact headers, missing encodings and real frozen flag definitions."""
    dictionary = inputs.json(DICTIONARY_PATH)
    if set(dictionary) != set(DATA_FILES):
        raise ValueError("The reporting dictionary must describe exactly Data 1-4")
    metadata_keys = {"meaning", "type", "unit", "missing", "base", "reference", "derivation"}
    tables = {}
    for name in DATA_FILES:
        fields, rows = inputs.csv("data/supplementary/" + name)
        if list(dictionary[name]) != fields:
            raise ValueError(f"Dictionary fields/order differ from the actual header: {name}")
        for field, entry in dictionary[name].items():
            if set(entry) != metadata_keys or entry["missing"] != ["", "NA"]:
                raise ValueError(f"Incomplete metadata or incorrect missing encodings: {name}/{field}")
            if any(not isinstance(entry[key], str) or not entry[key].strip()
                   for key in metadata_keys - {"missing"}):
                raise ValueError(f"Empty metadata: {name}/{field}")
            for row in rows:
                value = row[field]
                if value in entry["missing"]:
                    continue
                kind = entry["type"]
                if kind.startswith("boolean") and value not in ("TRUE", "FALSE"):
                    raise ValueError(f"Unexpected boolean encoding: {name}/{field}")
                if kind in ("number", "integer (0/1)", "nonnegative integer"):
                    try:
                        number = Decimal(value)
                    except InvalidOperation as error:
                        raise ValueError(f"Non-numeric source value: {name}/{field}") from error
                    # A descriptive number can retain Inf/-Inf. R complete.cases
                    # does not treat infinite age as missing; endpoint/origin
                    # finite eligibility belongs to script 32, not the dictionary.
                    # NaN is not an approved published missing-value encoding.
                    if number.is_nan() or (not number.is_finite() and kind != "number"):
                        raise ValueError(f"Invalid numeric source value: {name}/{field}")
                    if kind == "integer (0/1)" and value not in ("0", "1"):
                        raise ValueError(f"Unexpected indicator encoding: {name}/{field}")
                    if kind == "nonnegative integer" and (number < 0 or number != number.to_integral_value()):
                        raise ValueError(f"Invalid record count: {name}/{field}")
        tables[name] = fields, rows
    cases = tables[DATA_FILES[0]][1]
    flags = tables[DATA_FILES[2]][1]
    by_patient = {row["patient"]: row for row in cases}
    if len(by_patient) != len(cases) or len({row["patient"] for row in flags}) != len(flags):
        raise ValueError("Duplicate Data 1 or Data 3 patient identity")
    if {row["patient"] for row in flags} != set(by_patient):
        raise ValueError("Data 3 patients differ from Data 1")
    shared = ("response4", "main_landmark_cohort", "fl_start", "fl_end", "therapy_end")
    for row in flags:
        if any(row[field] != by_patient[row["patient"]][field] for field in shared):
            raise ValueError("Data 3 shared values differ from the published Data 1")
    if any(row["cohort"] not in PRIMARY_COHORTS for row in tables[DATA_FILES[1]][1]):
        raise ValueError("Data 2 contains a cohort outside the approved primary inventory")
    risk_cases = tables[DATA_FILES[3]][1]
    if (len(risk_cases) != len(cases) or {row["patient"] for row in risk_cases} != set(by_patient)):
        raise ValueError("Data 4 patients differ from Data 1")
    shared_risk = ("response4", "label_source", "age", "stage_group", "residual_group",
                   "fl_start", "fl_end", "therapy_end", "main_landmark_cohort")
    for row in risk_cases:
        original = by_patient[row["patient"]]
        if (any(row[field] != original[field] for field in shared_risk)
                or any(row[target] != original[source] for target, source in
                       (("os_days", "OS_days"), ("os_event", "OS_event"),
                        ("pfi_days", "PFI_days"), ("pfi_event", "PFI_event")))
                or row["response_assessment_date_provided"] != "FALSE"):
            raise ValueError("Data 4 copied values or response-date declaration changed")
    # AST inspection reads definitions without importing script 31 or its YAML/config setup.
    tree = ast.parse(inputs.bytes("scripts/31_flag_treatment_dates.py").decode("utf-8"))
    definitions = [node.value for node in tree.body if isinstance(node, ast.Assign)
                   and any(isinstance(target, ast.Name) and target.id == "FLAG_DEFINITIONS"
                           for target in node.targets)]
    if len(definitions) != 1 or not isinstance(definitions[0], ast.List):
        raise ValueError("Cannot read the declared script-31 flag interface")
    flag_names = [ast.literal_eval(element.elts[0]) for element in definitions[0].elts]
    if tables[DATA_FILES[2]][0][7:] != flag_names or len(flag_names) != 11:
        raise ValueError("Data 3 header differs from the actual script-31 flags")
    _, summary = inputs.csv("results/tables/supplementary/treatment_date_flag_summary.csv", ("flag", "definition"))
    if len(summary) != 11 or {row["flag"] for row in summary} != set(flag_names):
        raise ValueError("Frozen treatment-date definitions are incomplete")
    for row in summary:
        if dictionary[DATA_FILES[2]][row["flag"]]["meaning"] != row["definition"]:
            raise ValueError(f"Dictionary flag definition differs from the frozen definition: {row['flag']}")
    return inputs.bytes(DICTIONARY_PATH), {name: len(tables[name][0]) for name in DATA_FILES}


def reporting_index(inputs):
    """Navigate every declared claim; do not test manuscript numbers or infer scripts."""
    claims = inputs.json("config/manuscript_claims.json", ("claims",))["claims"]
    if not claims or len({claim["claim_id"] for claim in claims}) != len(claims):
        raise ValueError("Numeric claim declarations must be nonempty and uniquely identified")
    rows = []
    for claim in claims:
        source = claim["source_file"]
        if not source.startswith("tables/") or ".." in pathlib.PurePosixPath(source).parts:
            raise ValueError("Claim sources must be recorded relative to results/")
        source_path = "results/" + source
        fields, source_rows = inputs.csv(source_path, tuple(claim["row_filter"]) + tuple(claim["field_map"]))
        utilities.unique_csv_row(source_rows, claim["row_filter"])
        script = next((value for prefix, value in SCRIPT_PREFIXES.items() if source.startswith(prefix)),
                      "not_recorded")
        if script != "not_recorded":
            inputs.bytes(script)
        rows.append({"claim_id": claim["claim_id"], "manuscript_file": claim["manuscript_file"],
                     "anchor": claim["anchor"], "source_file": source,
                     "row_filter": json.dumps(claim["row_filter"], ensure_ascii=False, sort_keys=True),
                     "field_map": json.dumps(claim["field_map"], ensure_ascii=False, sort_keys=True),
                     "source_digest": inputs.records[source_path]["sha256"], "script": script})
    fields = ("claim_id", "manuscript_file", "anchor", "source_file", "row_filter", "field_map",
              "source_digest", "script")
    return csv_bytes(fields, rows), len(rows), [row["claim_id"] for row in rows if row["script"] == "not_recorded"]


def plan_excerpt(inputs):
    """Copy the shipped, previously byte-verified section-6 provenance record."""
    record = inputs.json(PLAN_RECORD_PATH, ("excerpt", "source_sha256", "internal_date",
                                         "archive_directory_copy_date", "section",
                                         "public_registration", "notes"))
    if (record["section"] != "6" or record["public_registration"] is not False
            or record["internal_date"] != "2026-10-15"
            or record["archive_directory_copy_date"] != "2026-10-23"
            or not re.fullmatch(r"[0-9a-f]{64}", record["source_sha256"])
            or not record["excerpt"].startswith("## 6.")
            or "## 7." in record["excerpt"]
            or not any("no prespecified numeric threshold" in note for note in record["notes"])
            or not any("superseded" in note and "retracted" in note for note in record["notes"])):
        raise ValueError("Shipped historical provenance record is incomplete or mislabelled")
    return inputs.bytes(PLAN_RECORD_PATH)


def member_records(members):
    return [{"member": name, "bytes": len(members[name]),
             "sha256": hashlib.sha256(members[name]).hexdigest()} for name in sorted(members)]


def build_reporting_bundle():
    """Return absolute outputs, all member hashes and a portable reporting summary.

    Writes only S5, S6 and Data 5. Data 1-4 and the dictionary are read-only inputs.
    All sources, including the verified historical excerpt, are shipped within
    the release root. All validation finishes before any output is written.
    """
    inputs = FrozenInputs()
    analysis, profile, crosswalk = primary_pool(inputs)
    landmark_days = utilities.required_value(utilities.read_yaml(ROOT / "config" / "analysis.yml"),
                                             "external_validation", "landmark_days")
    inputs.bytes("config/analysis.yml")
    s6, scores = external_results(inputs, analysis)
    per_cohort, per_cohort_n = per_cohort_results(inputs, scores)
    dictionary, dictionary_fields = dictionary_member(inputs)
    index, claim_n, unmapped = reporting_index(inputs)
    members = {
        "TableS5_landmark_OS_results.csv": landmark_results(inputs),
        "TableS6_primary_external_scores.csv": s6,
        "per_cohort_noncr_minus_cr_estimates.csv": per_cohort,
        "external_survival_inputs.csv": external_survival_inputs(inputs, landmark_days),
        "supplementary_data_dictionary.json": dictionary,
        "reporting_index.csv": index,
        "plan_excerpt.json": plan_excerpt(inputs),
        **audit_members(inputs, crosswalk),
        **label_source_results(inputs),
    }
    rmst = "results/tables/ov_therapy_end_landmark/rmst_therapy_end.csv"
    _, rmst_rows = inputs.csv(rmst, ("tau_months",))
    if len(rmst_rows) != 2 or {row["tau_months"] for row in rmst_rows} != {"36", "60"}:
        raise ValueError("Existing RMST source must retain both 36- and 60-month horizons")
    risk = "results/tables/ov_therapy_end_landmark/number_at_risk_therapy_end.csv"
    _, risk_rows = inputs.csv(risk, ("group", "months", "at_risk"))
    risk_keys = [(row["group"], row["months"]) for row in risk_rows]
    if not risk_rows or len(risk_keys) != len(set(risk_keys)):
        raise ValueError("Empty or duplicate number-at-risk group/time")
    for group in {row["group"] for row in risk_rows}:
        if not {(group, "36"), (group, "60")} <= set(risk_keys):
            raise ValueError("Existing number-at-risk source is missing 36/60-month coverage")
    s4 = "results/tables/supplementary/TableS4_pancancer_label_audit.csv"
    inputs.csv(s4, ("cancer",))
    risk_summary = "results/tables/supplementary/risk_set_audit_summary.csv"
    inputs.csv(risk_summary, ("metric", "endpoint", "response4", "n", "events"))
    for logical in (rmst, risk, s4, risk_summary):
        members[pathlib.PurePosixPath(logical).name] = inputs.bytes(logical)
    # S3 source data and the pooled therapy-end estimate cited in the main text.
    # Both files are copied byte-for-byte; no estimate is recomputed here.
    dichotomy = "results/tables/pancancer_topology/dichotomy_cr_vs_noncr_by_cancer.csv"
    dichotomy_meta = "results/tables/pancancer_topology/dichotomy_meta.csv"
    inputs.csv(dichotomy, ("cancer", "subset", "landmark", "n", "events", "non_CR",
                           "HR", "HR_low", "HR_high"))
    inputs.csv(dichotomy_meta, ("subset", "landmark", "k", "cancers", "HR", "HR_low",
                                "HR_high", "I2"))
    for logical in (dichotomy, dichotomy_meta):
        members[pathlib.PurePosixPath(logical).name] = inputs.bytes(logical)
    # S4 source data: the locked four-state topology models. Copied byte-for-byte;
    # no estimate is recomputed here.
    topology = "results/tables/pancancer_topology/topology_models_by_set.csv"
    inputs.csv(topology, ("set", "tier", "endpoint", "landmark", "adjustment", "n", "events",
                          "HR_PR", "HR_PR_low", "HR_PR_high",
                          "HR_SD", "HR_SD_low", "HR_SD_high",
                          "HR_PD", "HR_PD_low", "HR_PD_high"))
    members[pathlib.PurePosixPath(topology).name] = inputs.bytes(topology)
    # S7 source data: the response-partition scan and the E-value table. Copied
    # byte-for-byte from the analysis script; no estimate is recomputed here.
    s7_scan = "results/tables/supplementary/TableS7_response_partition_scan.csv"
    s7_evalues = "results/tables/supplementary/TableS7_evalues.csv"
    inputs.csv(s7_scan, ("reference", "comparator", "HR_adjusted", "CI_low_adjusted",
                         "CI_high_adjusted", "q_adjusted", "rank_adjusted",
                         "HR_unadjusted", "q_unadjusted"))
    inputs.csv(s7_evalues, ("estimand", "HR", "CI_low", "CI_high", "source",
                            "E_value_common_point", "E_value_common_CI"))
    for logical in (s7_scan, s7_evalues):
        members[pathlib.PurePosixPath(logical).name] = inputs.bytes(logical)
    # Selection-level tipping bounds cited in the main text and supplement.
    # Both files are copied byte-for-byte from script 35; no bound is refitted.
    tipping = "results/tables/ov_selection_tipping/landmark_selection_tipping.csv"
    tipping_summary = "results/tables/ov_selection_tipping/landmark_selection_tipping_summary.csv"
    inputs.csv(tipping, ("scenario", "description", "n", "events", "HR", "CI_low",
                         "CI_high", "p"))
    inputs.csv(tipping_summary, ("observed_HR", "adverse_extreme_HR",
                                 "favourable_extreme_HR", "excluded_n",
                                 "excluded_CR", "excluded_NCR"))
    for logical in (tipping, tipping_summary):
        members[pathlib.PurePosixPath(logical).name] = inputs.bytes(logical)
    summary = {
        "author": "Project authors", "date": "2026-10-24",
        "outputs": {"table_s5": S5_PATH, "table_s6": S6_PATH, "bundle": BUNDLE_PATH},
        "primary_analysis": analysis, "primary_cohorts": sorted(PRIMARY_COHORTS),
        "primary_pool_definition": "User-approved three cohorts, checked against config/external_cohort_reporting.json; profile records the primary_external analysis mode, not a separate cohort-list key.",
        "table_s5_rows": 16, "table_s6_rows": len(scores), "per_cohort_rows": per_cohort_n,
        "dictionary_field_counts": dictionary_fields, "numeric_claims": claim_n,
        "script_not_recorded_claims": unmapped,
        "processing": "Selection, projection, byte copying, descriptive metadata and navigation only; no statistical computation.",
        "notes": [
            "S5 preserves every original field/value in all 8 OS origins x 2 adjustments, including existing deterministic date scenarios; nothing is re-estimated.",
            "S6 preserves only approved primary external REML/HKSJ/I2/prediction-interval fields. No tau2, fixed-effect results or reconstructed SE are exported.",
            "S6 adjustment is explanatory: licensing_given_proliferation adjusts general_proliferation; all other rows are response_only.",
            "Per-cohort rows retain original set=primary, cohort, adjustment, n/CR/Non_CR and recorded estimate/se/p_value, including existing debulking sensitivity rows. For licensing_given_proliferation, original adjustment=none still includes general_proliferation; debulking additionally includes debulk_optimal.",
            "RMST and number-at-risk files retain existing 36/60-month results byte-for-byte; horizons are not fitted, extended or used to reconstruct SE.",
            "external_survival_inputs.csv contains only the three approved cohorts at the configured external landmark, with the recorded log HR and SE that the pooled estimate used. The retracted series and TCGA rows of the source table are not exported, and no pooled value is recomputed.",
            "topology_excluding_cdr_only.csv and topology_strictly_concordant.csv are the locked 307- and 306-patient label-source sensitivity models, exported with unadjusted and adjusted rows only; they are copies, not refits.",
            "Table S4 is copied in full. The gene audit preserves all six complete measured-gene lists; robust_nine_composite is marked additional exploratory.",
            "The pan-cancer dichotomy tables are copied byte-for-byte; they support Figure S3 and the end-of-therapy pooled estimate cited in the main text.",
            "The pan-cancer four-state topology table is copied byte-for-byte; it supports Figure S4 and the treated-restriction comparisons described in the supplement.",
            "Table S7 and its E-value source are copied byte-for-byte; the partition scan and calibration were fitted by script 34 and are not re-estimated here.",
            "The landmark selection tipping files are copied byte-for-byte from script 35; they are outcome-level worst-case and best-case bounds for the excluded labelled patients, not plausible reconstructed cohorts.",
            "Inventory coverage has exactly the five locked axes and the three matched datasets; it is not a primary sample-count denominator or a gene-level missingness audit.",
            "Data 1-4 dictionary fields/order match actual headers; missing encodings are blank/NA, never zero. Data 4 documents descriptive risk-set membership, not new model fits or verified response-assessment dates.",
            "reporting_index source_file retains the claims configuration spelling, relative to results/. row_filter and field_map are JSON. source_digest is SHA256 of the original CSV; known source prefixes map to scientific scripts, otherwise not_recorded.",
            "Claim navigation validates source filters and field names only; it does not test manuscript numbers, execute source scripts or distribute weight/quantile/resampling result tables.",
            "Historical section 6 is internal provenance, not public registration; no close-to-zero threshold is invented and the superseded retracted secondary pool is not restored.",
        ],
    }
    members["reporting_summary.json"] = json_bytes(summary)
    inputs.bytes("scripts/28_submission_utilities.py")
    inputs.bytes("scripts/33_build_reporting_bundle.py")
    inputs.verify(profile)
    manifest = {
        "inputs": [inputs.records[name] for name in sorted(inputs.records)],
        "members": member_records(members),
        "member_hash_scope": "All payload members. input_manifest.json cannot contain its own SHA256; its actual hash is included in the build_reporting_bundle() return value.",
        "zip_timestamp": "2026-10-24T00:00:00", "zip_order": "Lexicographic member name",
        "zip_compression": "ZIP_STORED (no compressor-version dependency)",
        "notes": "Paths are portable repository-relative labels; the historical source uses a logical archive name. No local archive absolute path or unrecorded software version is included.",
    }
    members["input_manifest.json"] = json_bytes(manifest)
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
        for name in sorted(members):
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 24, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, members[name])
    outputs = ((S5_PATH, members["TableS5_landmark_OS_results.csv"]),
               (S6_PATH, members["TableS6_primary_external_scores.csv"]),
               (BUNDLE_PATH, buffer.getvalue()))
    for logical, _ in outputs:
        if not (ROOT / logical).parent.is_dir():
            raise ValueError(f"Approved output directory is missing: {logical}")
    for logical, content in outputs:
        path = ROOT / logical
        if not path.exists() or path.read_bytes() != content:
            path.write_bytes(content)
    return {"outputs": {key: str(ROOT / value) for key, value in summary["outputs"].items()},
            "members": member_records(members), "summary": summary,
            "bundle_sha256": hashlib.sha256(buffer.getvalue()).hexdigest()}


def main():
    print(json.dumps(build_reporting_bundle(), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print(f"Reporting bundle stopped: {error}", file=sys.stderr)
        sys.exit(1)
