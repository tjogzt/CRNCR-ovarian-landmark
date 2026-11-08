#!/usr/bin/env python3
# =============================================================================
# File: 30_render_locked_publication.py
# Purpose: Apply the approved publication policy to locked tables and vectors.
# Author: Project authors
# Created: 2026-10-23
# Inputs: submission_profile.json, locked CSVs, and clean cropped vector PDFs.
# Runtime parameters: --render-only, --check-only, --baseline-dir; the profile's
# publication_policy provides exclusions, source hashes and observed panel layout.
# CRNCR_PYTHON selects the dependency-installed interpreter in the R dispatcher.
# Outputs: filtered formal tables/data, Figures 1/3/S1/S5 and figure provenance.
# Reproducibility: no fitting, hypothesis tests, CI calculation, CV, bootstrap,
# date resampling, quantiles, scientific configuration changes or R imports.
# Only original CSV records are selected. All artwork is original vector content;
# clean regions are genuinely clipped before saving, never covered with white.
# Baseline PDFs are read only to bootstrap missing clean regions, with SHA-256
# verification. Shipped regions permit portable rebuilding without the archive.
# Page dimensions and vector scale remain exactly those of the observed baseline.
# Required unchanged panels also carry ONLY their clean original PNG crop as a
# PDF attachment in the portable region asset. Final PDFs remain wholly vector;
# final PNGs reuse those exact pixels on the original unscaled raster canvas.
# =============================================================================

import argparse
import csv
import hashlib
import importlib
import io
import json
from pathlib import Path
import re
import sys

try:
    import fitz
    from PIL import Image
except ModuleNotFoundError as error:
    raise SystemExit("The selected Python needs PyMuPDF and Pillow from "
                     "environment/python_requirements.txt; set CRNCR_PYTHON "
                     "to the dependency-installed interpreter") from error


ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "config/submission_profile.json"
PANELS = ROOT / "results/figures/manuscript/locked_panels"
TABLES = ROOT / "results/tables"
DATE_ROW = re.compile(r"missing dates imputed|stochastic date imputation", re.I)
FORBIDDEN_FIGURE_TEXT = re.compile(
    r"PMID17290060|retracted|dates imputed|date imputation|pooled all", re.I
)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_records(path):
    """Return parsed rows and the exact original bytes of each CSV record."""
    data = path.read_bytes()
    lines = data.decode("utf-8").splitlines(keepends=True)
    reader = csv.reader(lines)
    fields = next(reader)
    end = reader.line_num
    header = "".join(lines[:end]).encode("utf-8")
    rows, records = [], []
    for values in reader:
        start, end = end, reader.line_num
        if not values:
            continue
        if len(values) != len(fields):
            raise ValueError(f"Malformed locked CSV: {path}")
        rows.append(dict(zip(fields, values)))
        records.append("".join(lines[start:end]).encode("utf-8"))
    return fields, rows, header, records


def selected_bytes(path, predicate):
    """Filter whole records without reformatting a single retained statistic."""
    _, rows, header, records = read_records(path)
    kept = [(row, record) for row, record in zip(rows, records) if predicate(row)]
    if not kept:
        raise ValueError(f"Publication selection is empty: {path}")
    return header + b"".join(record for _, record in kept), [row for row, _ in kept]


def encode_csv(fields, rows):
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode("utf-8")


def write_if_changed(path, data):
    if not path.parent.is_dir():
        raise ValueError(f"Required output parent is absent: {path.parent}")
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)


def has_excluded(row, excluded):
    return any(source in value for source in excluded for value in row.values())


def plan_tables(policy):
    """Plan only publication-layer outputs; all phase4 and t17/t18 sources stay locked."""
    excluded = policy["excluded_cohorts"]
    outputs = {}
    for filename in ("Table2_model_comparison.csv", "Table2_model_comparison_formatted.csv"):
        source = TABLES / "manuscript" / filename
        key = "Analysis" if "formatted" in filename else "time_origin"
        data, rows = selected_bytes(source, lambda row: not DATE_ROW.search(row[key]))
        # This deliberately does not match covariate MI: only missing-date rows go.
        if any("IPW" in row[key] for row in read_records(source)[1]):
            if not any("IPW" in row[key] for row in rows):
                raise ValueError("IPW rows were lost")
        outputs[source] = data
        outputs[TABLES / "main" / filename] = data

    for filename in ("SupplementaryData2_external_samples.csv", "TableS1_external_cohorts.csv"):
        source = TABLES / "manuscript" / filename
        data, _ = selected_bytes(source, lambda row: not has_excluded(row, excluded))
        outputs[source] = data
        destination = (ROOT / "data/supplementary" if filename.startswith("SupplementaryData")
                       else TABLES / "supplementary") / filename
        outputs[destination] = data

    source = TABLES / "manuscript/Figure1_flow_counts.csv"
    outputs[source], _ = selected_bytes(source, lambda row: not has_excluded(row, excluded))
    mapping = {
        "TableS3d_external_leave_one_out.csv": "os_meta_noncr_vs_cr_leave_one_out.csv",
        "TableS3e_external_small_sample.csv": "os_meta_noncr_vs_cr_small_sample.csv",
        "TableS3e_external_firth_by_cohort.csv": "os_cox_noncr_vs_cr_firth.csv",
    }
    # Include any additional existing formal Firth CSV, not just the known copy.
    for directory in (TABLES / "main", TABLES / "manuscript", TABLES / "supplementary"):
        for source in directory.glob("*.csv"):
            if "firth" in source.name.lower():
                outputs[source], _ = selected_bytes(
                    source, lambda row: not has_excluded(row, excluded)
                    and ("analysis" not in row or row["analysis"] == policy["external_pool_analysis"])
                )
    for destination, filename in mapping.items():
        source = TABLES / "phase4_external_validation" / filename
        data, _ = selected_bytes(
            source, lambda row: not has_excluded(row, excluded)
            and ("analysis" not in row or row["analysis"] == policy["external_pool_analysis"])
        )
        outputs[TABLES / "supplementary" / destination] = data

    # An exclusion inventory must never contain sample rows or result values.
    fields = ["source", "excluded_reason", "formal_use"]
    inventory = [{**row, "formal_use": "false"} for row in policy["excluded_inventory"]]
    outputs[TABLES / "supplementary/excluded_cohort_inventory.csv"] = encode_csv(fields, inventory)

    fields = policy["date_descriptive_columns"]
    allowed = {"imputations", "median_n", "median_PD", "median_HR_PD_vs_PRSD",
               "frac_best_AIC_M3", "frac_best_AIC_M_PD"}
    if set(fields) != allowed or policy["date_results_mode"] != "descriptive_scenarios":
        raise ValueError("Date display must contain only the approved locked descriptive columns")
    source = TABLES / "ov_selection_regimen_power/stochastic_date_imputation_summary.csv"
    rows = [{key: row[key] for key in fields} for row in read_records(source)[1]]
    outputs[TABLES / "supplementary/date_descriptive_scenarios.csv"] = encode_csv(fields, rows)
    return outputs


def pixel_hash(page, rect):
    # Integer crop coordinates at 144 dpi provide an exact alignment witness.
    pixmap = page.get_pixmap(matrix=fitz.Matrix(2, 2), clip=rect, alpha=False)
    return sha256(pixmap.samples)


def validate_text(page, profile):
    text = page.get_text()
    if FORBIDDEN_FIGURE_TEXT.search(text):
        raise ValueError("A forbidden source/date inferential row survived vector clipping")
    spec = profile["figure_specification"]
    markers = profile["figure_audit"]["marker_glyphs"]
    for block in page.get_text("dict")["blocks"]:
        for line in block.get("lines", []):
            for span in line["spans"]:
                if spec["font_family"].lower() not in span["font"].lower():
                    raise ValueError(f"Unexpected locked font: {span['font']}")
                if (span["text"].strip() not in markers
                        and span["size"] + profile["figure_audit"]["font_tolerance_pt"] < spec["min_font_pt"]):
                    raise ValueError(f"Locked text below the profile minimum: {span['text']}")


def validate_locked_inputs(policy):
    """Verify source hashes, not handwritten estimates, before reusing vectors.

    Frozen artwork is valid only for its locked scientific inputs. Table 2 is
    checked after the permitted record selection so a legacy row can be removed
    without weakening the guard against any change to retained estimates.
    """
    contracts = policy["locked_source_sha256"]
    if not contracts:
        raise ValueError("No locked scientific-source contracts were supplied")
    for relative, expected in contracts.items():
        path = ROOT / relative
        if not path.is_file():
            raise ValueError(f"Missing locked scientific input: {relative}")
        data = path.read_bytes()
        if path.name in {"Table2_model_comparison.csv", "Table2_model_comparison_formatted.csv"}:
            key = "Analysis" if "formatted" in path.name else "time_origin"
            data, _ = selected_bytes(path, lambda row: not DATE_ROW.search(row[key]))
        elif path.name in {"Figure1_flow_counts.csv", "TableS1_external_cohorts.csv",
                           "SupplementaryData2_external_samples.csv"}:
            data, _ = selected_bytes(path, lambda row: not has_excluded(row, policy["excluded_cohorts"]))
        if sha256(data) != expected:
            raise ValueError(f"Scientific input changed; frozen artwork cannot be reused: {relative}")


def freeze_region(source, source_sha, size, region, profile):
    """Remove everything outside a clean region before embedding or saving it."""
    if not hasattr(fitz.Page, "clip_to_rect"):
        raise ValueError("Creating missing regions requires genuine Page.clip_to_rect support; no masking fallback")
    original_png = None
    if "original_png_crop_px" in region:
        layout = next(layout for layout in profile["publication_policy"]["locked_vector_layout"].values()
                      if region["name"] in layout["preserved_panels"])
        png_source = source.with_suffix(".png")
        if sha256(png_source.read_bytes()) != layout["baseline_png_sha256"]:
            raise ValueError(f"Clean raster preservation needs the verified baseline PNG: {png_source}")
        with Image.open(png_source) as image:
            if list(image.size) != layout["raster_size_px"]:
                raise ValueError(f"Unexpected baseline raster size: {png_source}")
            stream = io.BytesIO()
            image.crop(region["original_png_crop_px"]).save(stream, format="PNG", dpi=(600, 600))
            original_png = stream.getvalue()
    if sha256(source.read_bytes()) != source_sha:
        raise ValueError(f"Missing clean region needs the verified baseline PDF: {source}. "
                         "Use --baseline-dir with the read-only baseline root; no refit is allowed.")
    with fitz.open(source) as document:
        page = document[0]
        if len(document) != 1 or list(page.rect[2:]) != size:
            raise ValueError(f"Unexpected baseline MediaBox: {source}")
        crop = fitz.Rect(region["crop_pt"])
        before = pixel_hash(page, crop)
        # clip_to_rect invokes MuPDF's content clipping, not just a CropBox or
        # show_pdf_page clip (both alone would embed the entire old page stream).
        page.clip_to_rect(crop)
        page.set_cropbox(crop)
        clean = document.tobytes(garbage=4, deflate=True, clean=True, no_new_id=True)
    # Copy the already-sanitized crop to a tight MediaBox. There is now no old
    # off-region text/geometry to import into a current publication figure.
    with fitz.open(stream=clean, filetype="pdf") as clipped, fitz.open() as tight:
        page = tight.new_page(width=crop.width, height=crop.height)
        page.show_pdf_page(page.rect, clipped, 0, keep_proportion=False)
        if original_png is not None:
            xref = tight.embfile_add("locked_original_pixels.png", original_png,
                                     desc="Clean unchanged baseline panel pixels; not an entire old figure")
            # PyMuPDF otherwise inserts the current time into attachment metadata.
            tight.xref_set_key(xref, "Params/CreationDate", "null")
            tight.xref_set_key(xref, "Params/ModDate", "null")
        result = tight.tobytes(garbage=4, deflate=True, clean=True, no_new_id=True)
    with fitz.open(stream=result, filetype="pdf") as check:
        validate_text(check[0], profile)
        if pixel_hash(check[0], check[0].rect) != before:
            raise ValueError(f"Clipping changed retained pixels: {region['name']}")
    return result


def prepare_regions(profile, baseline_dir, check_only):
    layouts = profile["publication_policy"]["locked_vector_layout"]
    regions = {}
    for layout in layouts.values():
        for region in layout["regions"]:
            path = PANELS / f"{region['name']}.pdf"
            if path.exists():
                data = path.read_bytes()
            else:
                source = baseline_dir / layout["source"]
                data = freeze_region(source, layout["baseline_sha256"],
                                     layout["page_size_pt"], region, profile)
            expected = profile["publication_policy"]["locked_region_sha256"][region["name"]]
            if sha256(data) != expected:
                raise ValueError(f"Frozen region differs from the approved vector bytes: {path}")
            with fitz.open(stream=data, filetype="pdf") as document:
                crop = fitz.Rect(region["crop_pt"])
                if len(document) != 1 or document[0].rect != fitz.Rect(0, 0, crop.width, crop.height):
                    raise ValueError(f"Unexpected frozen region size: {path}")
                validate_text(document[0], profile)
                raster_sha = pixel_hash(document[0], document[0].rect)
                original_png = None
                if "original_png_crop_px" in region:
                    original_png = document.embfile_get("locked_original_pixels.png")
                    with Image.open(io.BytesIO(original_png)) as image:
                        left, top, right, bottom = region["original_png_crop_px"]
                        if image.size != (right - left, bottom - top):
                            raise ValueError(f"Unexpected clean raster crop size: {path}")
            regions[region["name"]] = {"path": path, "bytes": data, "original_png": original_png,
                                       "sha256": sha256(data), "pixels_144dpi": raster_sha}
    if not check_only:
        # Parent was checked before this renderer was introduced; additionally
        # require the expected manuscript directory rather than creating a tree.
        if not PANELS.parent.is_dir():
            raise ValueError(f"Required parent is absent: {PANELS.parent}")
        PANELS.mkdir(exist_ok=True)
        for region in regions.values():
            write_if_changed(region["path"], region["bytes"])
    return regions


def render_figure(layout, regions, profile):
    """Recompose clean strips at 1:1 scale; compact only the deleted row bands."""
    with fitz.open() as document:
        page = document.new_page(width=layout["page_size_pt"][0], height=layout["page_size_pt"][1])
        proofs = []
        for region in layout["regions"]:
            locked = regions[region["name"]]
            with fitz.open(stream=locked["bytes"], filetype="pdf") as fragment:
                x, y = region["place_pt"]
                width, height = fragment[0].rect.width, fragment[0].rect.height
                target = fitz.Rect(x, y, x + width, y + height)
                if not page.rect.contains(target):
                    raise ValueError(f"Region exceeds locked page dimensions: {region['name']}")
                page.show_pdf_page(target, fragment, 0, keep_proportion=False)
                if pixel_hash(page, target) != locked["pixels_144dpi"]:
                    raise ValueError(f"Composition changed retained pixels: {region['name']}")
                proofs.append({"region": region["name"], "asset": str(locked["path"].relative_to(ROOT)),
                               "crop_pt": region["crop_pt"], "place_pt": region["place_pt"],
                               "sha256": locked["sha256"], "pixels_144dpi": locked["pixels_144dpi"],
                               "pixel_parity": True})
        validate_text(page, profile)
        spec = profile["figure_specification"]
        if abs(page.rect.width * 25.4 / 72 - spec["width_mm"]) > profile["figure_audit"]["size_tolerance_mm"]:
            raise ValueError("Observed page width falls outside the publication profile tolerance")
        pdf = document.tobytes(garbage=4, deflate=True, clean=True, no_new_id=True)
        raster = page.get_pixmap(dpi=spec["raster_dpi"], alpha=False).tobytes("png")
        # Cairo's original PNG canvas is slightly larger than its rounded PDF
        # MediaBox. Pad rather than scale, then restore only clean native pixels.
        canvas = Image.new("RGB", tuple(layout["raster_size_px"]), "white")
        with Image.open(io.BytesIO(raster)) as image:
            if image.width > canvas.width or image.height > canvas.height:
                raise ValueError("Raster exceeds the observed baseline canvas; no scaling is permitted")
            canvas.paste(image, (0, 0))
        for region, proof in zip(layout["regions"], proofs):
            original = regions[region["name"]]["original_png"]
            if original is not None:
                crop = region["original_png_crop_px"]
                with Image.open(io.BytesIO(original)) as image:
                    canvas.paste(image, tuple(crop[:2]))
                    expected = sha256(image.tobytes())
                if sha256(canvas.crop(crop).tobytes()) != expected:
                    raise ValueError(f"Original PNG pixels changed: {region['name']}")
                proof.update(original_png_crop_px=crop, original_png_pixels_sha256=expected,
                             original_png_pixel_parity=True)
        stream = io.BytesIO()
        canvas.save(stream, format="PNG", dpi=(spec["raster_dpi"], spec["raster_dpi"]))
        return pdf, stream.getvalue(), proofs


def provenance_bytes(profile, figure_outputs):
    path = TABLES / "manuscript/figure_provenance.csv"
    fields, rows, _, _ = read_records(path)
    additions = ["renderer", "publication_policy", "baseline_sha256", "source_sha256",
                 "destination_sha256", "locked_region_proofs"]
    fields += [field for field in additions if field not in fields]
    layouts = profile["publication_policy"]["locked_vector_layout"]
    for row in rows:
        for name, layout in layouts.items():
            if row["source"] in {layout["source"], str(Path(layout["source"]).with_suffix(".png"))}:
                source, destination = ROOT / row["source"], ROOT / row["destination"]
                pdf, png, proofs = figure_outputs[name]
                data = png if source.suffix == ".png" else pdf
                row.update(renderer="30_render_locked_publication.py (vector selection only)",
                           publication_policy=("excluded=" + ",".join(profile["publication_policy"]["excluded_cohorts"])
                                               + ";pool=" + profile["publication_policy"]["external_pool_analysis"]
                                               + ";dates=" + profile["publication_policy"]["date_results_mode"]),
                           baseline_sha256=layout["baseline_sha256"], source_sha256=sha256(data),
                           destination_sha256=sha256(data),
                           locked_region_proofs=json.dumps(proofs, separators=(",", ":")))
                if destination != ROOT / layout["destination"] and destination != (ROOT / layout["destination"]).with_suffix(".png"):
                    raise ValueError("Figure provenance destination disagrees with the locked profile")
        for field in fields:
            row.setdefault(field, "")
    return encode_csv(fields, rows)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__ or "Render approved locked publication outputs without analysis")
    parser.add_argument("--render-only", action="store_true", help="Explicit alias for the default pure renderer")
    parser.add_argument("--check-only", action="store_true", help="Validate locked inputs/regions without writing outputs")
    parser.add_argument("--baseline-dir", type=Path, default=ROOT,
                        help="Read-only root containing the verified baseline PDFs, needed only for missing clean regions")
    args = parser.parse_args(argv)
    utilities = importlib.import_module("28_submission_utilities")
    # These shipped vector assets are bound to the repository result bundle.
    # Reject incompatible private/environment overrides instead of silently
    # reading a different tree from the other submission builders.
    if utilities.results_directory(ROOT) != ROOT / "results":
        raise ValueError("Frozen publication assets require the shipped repository results bundle; "
                         "custom results-path overrides are not supported by this renderer")
    profile = json.loads(PROFILE.read_text())
    policy = profile["publication_policy"]
    if not policy["excluded_cohorts"] or not policy["external_pool_analysis"]:
        raise ValueError("An explicit exclusion list and primary-pool policy are required")
    validate_locked_inputs(policy)
    table_outputs = plan_tables(policy)
    regions = prepare_regions(profile, args.baseline_dir.resolve(), args.check_only)
    # Protect every other table and every untouched figure, including all locked
    # TCGA HR/CV/MI, t18 date draws, phase4 estimates and Figures 2/S2/S3/S4.
    figure_paths = set()
    for layout in policy["locked_vector_layout"].values():
        for key in ("source", "destination"):
            path = ROOT / layout[key]
            figure_paths.update((path, path.with_suffix(".png")))
    provenance = TABLES / "manuscript/figure_provenance.csv"
    protected = {path: sha256(path.read_bytes()) for directory in (TABLES, ROOT / "results/figures")
                 for path in directory.rglob("*") if path.is_file() and path not in table_outputs
                 and path not in figure_paths and path != provenance and PANELS not in path.parents}
    figure_outputs = {name: render_figure(layout, regions, profile)
                      for name, layout in policy["locked_vector_layout"].items()}
    if not args.check_only:
        for path, data in table_outputs.items():
            write_if_changed(path, data)
        for name, layout in policy["locked_vector_layout"].items():
            pdf, png, _ = figure_outputs[name]
            for key in ("source", "destination"):
                path = ROOT / layout[key]
                write_if_changed(path, pdf)
                write_if_changed(path.with_suffix(".png"), png)
        write_if_changed(provenance, provenance_bytes(profile, figure_outputs))
    for path, expected in protected.items():
        if sha256(path.read_bytes()) != expected:
            raise ValueError(f"Protected locked output changed: {path}")
    for name, (_, _, proofs) in figure_outputs.items():
        print(f"{name}: original page size; {len(proofs)} clean vector regions; exact 144-dpi pixel parity")
    print(f"{'Checked' if args.check_only else 'Rendered'} locked publication only; "
          f"{len(protected)} protected files unchanged; no fitting/tests/resampling. "
          "Downstream manuscript/claim/typography audits were not run.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print(f"Locked publication renderer stopped: {error}", file=sys.stderr)
        sys.exit(1)
