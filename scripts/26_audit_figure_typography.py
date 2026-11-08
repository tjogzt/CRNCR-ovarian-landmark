#!/usr/bin/env python3
"""Audit final-size canvas and minimum text size of every formal figure.

File: 26_audit_figure_typography.py
Purpose: Verify that each staged formal figure is drawn at the configured
    double-column width (no downstream scaling), fits the page height, embeds
    its fonts and contains no text below the configured minimum point size.
Author: Project authors
Created: 2026-10-16
Inputs: config/submission_profile.json (figure_specification) and
    results/tables/manuscript/figure_provenance.csv.
Runtime parameters: CRNCR_RESULTS_DIR optionally overrides the results directory;
    relative values are resolved against the script's repository root.
Outputs: figure_typography_audit.csv under results/tables/manuscript.
Notes: Text sizes are read from the vector PDF companion of each figure. Point
    markers drawn as font glyphs (for example the "|" censoring tick) are
    plotting symbols rather than text and are excluded from the size check.
Dependencies: PyMuPDF (import name fitz).
"""

import csv
import importlib
import struct
import sys

import fitz


utilities = importlib.import_module("28_submission_utilities")
ROOT = utilities.repository_root(__file__)
RESULTS = utilities.results_directory(ROOT)
PROFILE = utilities.read_json(ROOT / "config" / "submission_profile.json")
SPEC = utilities.required_value(PROFILE, "figure_specification")
AUDIT_STYLE = utilities.required_value(PROFILE, "figure_audit")
PROVENANCE = RESULTS / "tables" / "manuscript" / "figure_provenance.csv"
REPORT = RESULTS / "tables" / "manuscript" / "figure_typography_audit.csv"
# PDF points are a standard unit; acceptance tolerances are versioned settings.
MM_PER_PT = 25.4 / 72
MARKER_GLYPHS = set(utilities.required_value(AUDIT_STYLE, "marker_glyphs"))
SIZE_TOLERANCE_MM = utilities.required_value(AUDIT_STYLE, "size_tolerance_mm")
FONT_TOLERANCE_PT = utilities.required_value(AUDIT_STYLE, "font_tolerance_pt")
# Single-panel artwork may be approved at a narrower native width; every other
# figure must occupy the configured double-column width exactly.
NARROW_WIDTH_MM = AUDIT_STYLE.get("narrow_figure_width_mm", {})
if not isinstance(NARROW_WIDTH_MM, dict):
    raise ValueError("Narrow figure widths must map figure stems to widths")
for _stem, _width in NARROW_WIDTH_MM.items():
    if (not isinstance(_stem, str) or not _stem
            or isinstance(_width, bool) or not isinstance(_width, (int, float))
            or not 0 < _width <= SPEC["width_mm"]):
        raise ValueError("Narrow figure widths must be positive and no wider than the page block")
for value in (SIZE_TOLERANCE_MM, FONT_TOLERANCE_PT):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
        raise ValueError("Figure audit tolerances must be nonnegative numbers")
if not MARKER_GLYPHS or not all(isinstance(value, str) and value for value in MARKER_GLYPHS):
    raise ValueError("Figure marker glyphs must be nonempty strings")
COLUMNS = [
    "figure", "file_type", "width_mm", "height_mm", "dpi",
    "min_text_pt", "text_spans", "unembedded_fonts", "status", "detail",
]


def png_geometry(path):
    """Return pixel size, PNG colour type and pixels-per-metre from the header."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")
    width, height, _, colour_type = struct.unpack(">IIBB", data[16:26])
    at = data.find(b"pHYs")
    if at < 0:
        raise ValueError("missing pHYs physical-size chunk")
    ppm_x, ppm_y, unit = struct.unpack(">IIB", data[at + 4:at + 13])
    if unit != 1 or ppm_x != ppm_y:
        raise ValueError("pHYs chunk is not square pixels per metre")
    return width, height, colour_type, ppm_x


def audit_png(path):
    """Check physical width, resolution and absence of an alpha channel."""
    expected_width = NARROW_WIDTH_MM.get(path.stem, SPEC["width_mm"])
    width, height, colour_type, ppm = png_geometry(path)
    width_mm, height_mm, dpi = width / ppm * 1000, height / ppm * 1000, ppm * 0.0254
    problems = []
    if abs(width_mm - expected_width) > SIZE_TOLERANCE_MM:
        problems.append(f"width {width_mm:.1f} mm != {expected_width:g} mm")
    if height_mm > SPEC["max_height_mm"] + SIZE_TOLERANCE_MM:
        problems.append(f"height {height_mm:.1f} mm > {SPEC['max_height_mm']} mm")
    if round(dpi) < SPEC["raster_dpi"]:
        problems.append(f"{dpi:.0f} dpi < {SPEC['raster_dpi']} dpi")
    if colour_type not in (0, 2):
        problems.append(f"PNG colour type {colour_type} has alpha or a palette")
    return {"width_mm": f"{width_mm:.2f}", "height_mm": f"{height_mm:.2f}", "dpi": f"{dpi:.0f}"}, problems


def audit_pdf(path):
    """Check page size, font embedding and the smallest rendered text span."""
    expected_width = NARROW_WIDTH_MM.get(path.stem, SPEC["width_mm"])
    problems, sizes = [], []
    with fitz.open(path) as doc:
        if doc.page_count != 1:
            problems.append(f"{doc.page_count} pages")
        page = doc[0]
        width_mm, height_mm = page.rect.width * MM_PER_PT, page.rect.height * MM_PER_PT
        unembedded = sorted({f[3] for f in page.get_fonts(full=True) if f[1] == "n/a"})
        for block in page.get_text("dict")["blocks"]:
            for line in block.get("lines", []):
                for span in line["spans"]:
                    text = span["text"].strip()
                    # A span consisting only of plotting symbols is not figure
                    # text; any mixed span still contributes its full text size.
                    if text and not set(text.replace(" ", "")) <= MARKER_GLYPHS:
                        sizes.append(span["size"])
    if abs(width_mm - expected_width) > SIZE_TOLERANCE_MM:
        problems.append(f"width {width_mm:.1f} mm != {expected_width:g} mm")
    if height_mm > SPEC["max_height_mm"] + SIZE_TOLERANCE_MM:
        problems.append(f"height {height_mm:.1f} mm > {SPEC['max_height_mm']} mm")
    if unembedded:
        problems.append("unembedded fonts: " + ";".join(unembedded))
    if not sizes:
        problems.append("no text spans found")
    elif min(sizes) < SPEC["min_font_pt"] - FONT_TOLERANCE_PT:
        problems.append(f"smallest text {min(sizes):.2f} pt < {SPEC['min_font_pt']} pt")
    return {
        "width_mm": f"{width_mm:.2f}", "height_mm": f"{height_mm:.2f}",
        "min_text_pt": f"{min(sizes):.2f}" if sizes else "",
        "text_spans": str(len(sizes)), "unembedded_fonts": ";".join(unembedded),
    }, problems


def main():
    """Audit both companions of every staged figure and fail on any violation."""
    with PROVENANCE.open(newline="") as handle:
        # Provenance uses logical results/ paths even when results live elsewhere.
        destinations = [utilities.resolve_project_path(ROOT, row["destination"], results=RESULTS)
                        for row in csv.DictReader(handle)]
    stems = sorted({path.with_suffix("") for path in destinations})
    rows, failed = [], 0
    for stem in stems:
        for suffix, auditor in ((".png", audit_png), (".pdf", audit_pdf)):
            path = stem.with_suffix(suffix)
            row = {key: "" for key in COLUMNS}
            row.update(figure=utilities.project_path_label(ROOT, path, results=RESULTS), file_type=suffix[1:])
            if not path.exists():
                problems = ["missing staged file"]
            else:
                try:
                    values, problems = auditor(path)
                    row.update(values)
                except ValueError as error:
                    problems = [str(error)]
            row["status"] = "FAIL" if problems else "PASS"
            row["detail"] = "; ".join(problems) if problems else "meets figure specification"
            failed += bool(problems)
            rows.append(row)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    with REPORT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    for row in rows:
        if row["status"] == "FAIL":
            print(f"FAIL {row['figure']}: {row['detail']}", file=sys.stderr)
    print(f"Audited {len(rows)} formal figure files ({failed} failed).")
    print(f"Typography audit: {REPORT}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
