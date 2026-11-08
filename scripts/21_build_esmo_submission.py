#!/usr/bin/env python3
"""Build the configured journal-submission package.

File: 21_build_esmo_submission.py
Purpose: Assemble the manuscript and supplementary appendix from versioned
    section files and locked analysis outputs, validate journal limits, and
    invoke the portable DOCX generator.
Author: Project authors
Created: 2026-10-15
Inputs:
    manuscript/source/*.md, manuscript/source/references_verified_pubmed.json,
    config/submission_profile.json, config/reference_overrides.json,
    config/analysis.yml, config/manuscript_claims.json, results/tables/**,
    and results/figures/**.
Runtime parameters:
    Journal limits and output names from config/submission_profile.json;
    CRNCR_RESULTS_DIR overrides the repository-relative results directory.
Outputs:
    Configured Markdown, DOCX, highlights, and supplementary-appendix files
    under manuscript/submission/.
"""
import csv
import importlib
import math
import pathlib
import re
import struct
import subprocess
from decimal import Decimal

# importlib supports the numbered helper filename without changing sys.path.
utilities = importlib.import_module("28_submission_utilities")
ROOT = utilities.repository_root(__file__)
SOURCE = ROOT / "manuscript" / "source"
OUTPUT = ROOT / "manuscript" / "submission"
RESULTS = utilities.results_directory(ROOT)
PROFILE = utilities.read_json(ROOT / "config" / "submission_profile.json")
ANALYSIS = utilities.read_yaml(ROOT / "config" / "analysis.yml")
OUTPUT_PREFIX = PROFILE["output_prefix"]
OUTPUT.mkdir(parents=True, exist_ok=True)
# PubMed metadata still comes from the verified source JSON, never a new lookup.
pub = utilities.read_json(SOURCE / "references_verified_pubmed.json")
reference_overrides = utilities.read_json(
    ROOT / "config" / "reference_overrides.json",
    required_keys=("crossref", "notes", "doi_overrides"),
)
# Preserve the complete verified strings, including retraction punctuation and
# DOIs registered in Crossref but absent from the original PubMed record.
crossref = reference_overrides["crossref"]
notes = reference_overrides["notes"]
doi_overrides = reference_overrides["doi_overrides"]

# Journal limits are versioned separately from the build implementation.
profile_limits = PROFILE["limits"]
LIMITS = dict(
    main_words=profile_limits["main_words"],
    abstract_words=profile_limits["abstract_words"],
    refs=profile_limits["references"],
    display_items=profile_limits["display_items"],
    highlights=(profile_limits["highlights_minimum"], profile_limits["highlights_maximum"]),
    highlight_chars=profile_limits["highlight_characters"],
    keywords=profile_limits["keywords"],
)


def ama_pages(pages):
    """Give page ranges in full, as in AMA Manual of Style 11th ed. (3194-200 -> 3194-3200).

    PubMed stores elided ranges; article numbers and e-suffixed pages are returned unchanged.
    """
    m = re.fullmatch(r"([A-Za-z]?)(\d+)-([A-Za-z]?)(\d+)", pages)
    if not m or (m.group(3) and m.group(3) != m.group(1)):
        return pages
    first, last = m.group(2), m.group(4)
    if len(last) < len(first):
        last = first[: len(first) - len(last)] + last
    if int(last) < int(first):
        raise SystemExit(f"Invalid page range: {pages}")
    return f"{m.group(1)}{first}-{m.group(3)}{last}"


def ama_authors(au):
    """AMA 11th ed.: list all authors when six or fewer; otherwise the first three and et al.

    A work without named authors begins with its title; no placeholder author
    segment is printed.
    """
    if not au:
        return ""
    return ", ".join(au[:3]) + ", et al" if len(au) > 6 else ", ".join(au)


def vancouver(k):
    """Format a verified reference, applying only versioned local overrides.

    Journal abbreviations and book titles are italicized as in AMA 11th ed.;
    emphasis markers are consumed by the DOCX and LaTeX renderers.
    """
    if k in crossref:
        return crossref[k]
    x = pub[k]
    a = ama_authors(x["authors"])
    lead = f"{a}. " if a else ""
    iss = f"({x['issue']})" if x["issue"] and "Suppl" not in x["vol"] else ""
    pages = f":{ama_pages(x['pages'])}" if x["pages"] else ""
    doi_value = x["doi"] or doi_overrides.get(k, "")
    doi = f" doi:{doi_value}" if doi_value else ""
    return f"{lead}{x['title'].rstrip('.')}. *{x['journal']}*. {x['date'][:4]};{x['vol']}{iss}{pages}.{doi}{notes.get(k, '')}"


def compress(ns, prefix=""):
    """Compress citation runs of at least three numbers into en-dash ranges."""
    ns = sorted(set(ns))
    out = []
    i = 0
    while i < len(ns):
        j = i
        while j + 1 < len(ns) and ns[j + 1] == ns[j] + 1:
            j += 1
        if j - i >= 2:
            out.append(f"{prefix}{ns[i]}–{prefix}{ns[j]}")
        else:
            out.append(",".join(f"{prefix}{n}" for n in ns[i:j + 1]))
        i = j + 1
    return ",".join(out)


CITE = re.compile(r"\s*\[(@[^\]]+)\]([.,]?)")


def number_citations(text, prefix=""):
    """Superscript numbers in order of first appearance, placed outside
    periods and commas using the configured citation style. Supplementary
    citations use an S prefix so that they cannot be confused with the
    independently numbered main reference list."""
    order = []
    for m in CITE.finditer(text):
        for k in re.findall(r"@([A-Za-z0-9_]+)", m.group(1)):
            if k not in order:
                order.append(k)
    bad = [k for k in order if k not in pub and k not in crossref]
    if bad:
        raise SystemExit(f"Unverified citation keys: {bad}")
    num = {k: i + 1 for i, k in enumerate(order)}
    out = CITE.sub(lambda m: f"{m.group(2)}^{compress([num[k] for k in re.findall(r'@([A-Za-z0-9_]+)', m.group(1))], prefix)}^", text)
    # Main references form a Pandoc ordered list (one line each). The S prefix
    # prevents list recognition, so supplement entries are separated by blank
    # lines to remain distinct paragraphs rather than one run-in block.
    separator = "\n\n" if prefix else "\n"
    refs = separator.join(f"{prefix}{num[k]}. {vancouver(k)}" for k in order)
    return out, order, refs


def words(t):
    """Count prose words, excluding citation markers, headings and table rows."""
    t = CITE.sub(lambda m: m.group(2), t)
    t = "\n".join(l for l in t.splitlines() if not l.lstrip().startswith(("|", "#")))
    return len(re.findall(r"[A-Za-z0-9][A-Za-z0-9'’.\-–/×⁻]*", t))


P_TOKEN = re.compile(r"(?<![A-Za-z*])P(?![A-Za-z])")
P_OPERATOR = re.compile(r"\*P\*\s*(=|≤|≥|<|>)\s*")


def journal_p(text):
    """Typeset the statistical symbol as italic capital P with spaced operators.

    Applied to prose, legends and tables only, never to the reference list, so
    that published ESMO Open style is matched without touching citation text.
    Non-breaking spaces keep the symbol, operator and estimate on one line.
    """
    text = P_TOKEN.sub("*P*", text)
    return P_OPERATOR.sub("*P*\u00A0\\1\u00A0", text)


# ---------- formatting helpers for tables ----------
SUP = str.maketrans("-0123456789", "⁻⁰¹²³⁴⁵⁶⁷⁸⁹")


def fp(p):
    """Render P values with the existing decimal/scientific display rules."""
    p = float(p)
    if p < 0.001:
        m, e = f"{p:.1e}".split("e")
        return f"{m}×10{str(int(e)).translate(SUP)}"
    return f"{p:.3f}" if p < 0.01 else f"{p:.2f}"


def fp_t1(p):
    """Render Table 1 P values, reporting the Monte Carlo floor as a bound.

    The residual-disease Fisher test reaches the 100,000-replicate floor, so
    "<0.001" is the honest display instead of a scientific-notation value that
    implies more precision than the simulation supports. Other tables keep fp.
    """
    if p.startswith("<"):
        return p
    p = float(p)
    if p < 0.001:
        return "<0.001"
    return f"{p:.3f}" if p < 0.01 else f"{p:.2f}"


def pct_t1(cell):
    """Show a nonzero count below 0.5% as "<1%" rather than a rounded 0%."""
    m = re.fullmatch(r"([1-9]\d*) \(0%\)", cell)
    return f"{m.group(1)} (<1%)" if m else cell


def fp3(p):
    """Render Table S2 P values with three decimals below 0.1.

    The HGSOC constraint tests are reported to three decimals in the
    Supplementary Results; this local rule keeps the table and the text
    identical without changing the shared formatter used by other tables.
    """
    p = float(p)
    if p < 0.001:
        return fp(p)
    return f"{p:.3f}" if p < 0.1 else f"{p:.2f}"


def hr(x, lo, hi):
    """Render a hazard ratio and interval to the locked two-decimal precision."""
    return f"{float(x):.2f} ({float(lo):.2f}–{float(hi):.2f})"


def sdiff(x, lo, hi):
    """Render a signed difference and interval without dash collisions.

    Negative bounds use the Unicode minus sign and the interval is joined by
    "to", so LaTeX cannot absorb a minus sign into an en dash. One decimal
    matches the adjacent RMST columns.
    """
    minus = "\u2212"
    fmt = lambda v: f"{float(v):.1f}".replace("-", minus)
    return f"{fmt(x)} ({fmt(lo)} to {fmt(hi)})"


def sdiff2(x, lo, hi):
    """Render a two-decimal signed difference and interval without dash collisions.

    Table S6 reports standardised mean differences; the same Unicode minus and
    "to" join used by sdiff keep the sign of a lower bound distinct from the
    interval separator in LaTeX.
    """
    minus = "\u2212"
    fmt = lambda v: f"{float(v):.2f}".replace("-", minus)
    return f"{fmt(x)} ({fmt(lo)} to {fmt(hi)})"


def srange(lo, hi):
    """Render a two-decimal interval with a signed, dash-safe lower bound."""
    minus = "\u2212"
    fmt = lambda v: f"{float(v):.2f}".replace("-", minus)
    return f"{fmt(lo)} to {fmt(hi)}"


def dash(s):
    """Normalize numeric ranges and exponents without changing table values."""
    s = re.sub(r"(?<=\d)-(?=\d)", "–", s)
    return re.sub(r"(\d(?:\.\d+)?)e-0?(\d+)", lambda m: f"{m.group(1)}×10{('-' + m.group(2)).translate(SUP)}", s)


def pipe_table(header, rows):
    """Serialize a Markdown pipe table with escaped literal cell separators."""
    esc = lambda c: str(c).replace("|", "\\|")
    lines = ["| " + " | ".join(map(esc, header)) + " |", "|" + "|".join("---" for _ in header) + "|"]
    lines += ["| " + " | ".join(esc(c) for c in r) + " |" for r in rows]
    return "\n".join(lines)


read_csv = utilities.read_csv_rows


def percentage_claim_checks(configuration):
    """Check descriptive percentages against locked fractions without changing CSVs.

    Script 24 compares numbers directly and cannot scale a displayed percentage;
    these separately declared claims use an explicit division by 100 here.
    """
    claims = configuration["percentage_claims"]
    if not isinstance(claims, list) or not claims:
        raise ValueError("Descriptive percentage claims must be a non-empty list")
    checks = {}
    for claim in claims:
        text = (ROOT / claim["manuscript_file"]).read_text(encoding="utf-8")
        if text.count(claim["anchor"]) != 1:
            raise ValueError(f"Percentage claim anchor must occur once: {claim['claim_id']}")
        position = text.index(claim["anchor"])
        start, end = text.rfind("\n\n", 0, position), text.find("\n\n", position)
        scope = text[start + 2 if start >= 0 else 0:end if end >= 0 else len(text)]
        matches = list(re.finditer(claim["pattern"], scope, re.UNICODE))
        if len(matches) != 1:
            raise ValueError(f"Percentage claim must match once: {claim['claim_id']}")
        row = utilities.read_unique_csv_row(RESULTS / claim["source_file"], claim["row_filter"])
        for field, group in claim["field_map"].items():
            displayed = Decimal(matches[0].group(group)) / Decimal(100)
            source = Decimal(row[field])
            tolerance = Decimal(str(claim["tolerance"][field]))
            if (not displayed.is_finite() or not source.is_finite() or not tolerance.is_finite()
                    or not Decimal(0) <= displayed <= Decimal(1)
                    or not Decimal(0) <= source <= Decimal(1) or tolerance < 0):
                raise ValueError(f"Invalid percentage claim value: {claim['claim_id']}:{field}")
            key = f"percentage claim {claim['claim_id']}:{field} matches locked fraction"
            if key in checks:
                raise ValueError(f"Duplicate percentage claim: {claim['claim_id']}:{field}")
            checks[key] = abs(displayed - source) <= tolerance
    return checks


def count_word(value):
    """Spell small counts to preserve the approved prose, not scientific values."""
    names = ("zero", "one", "two", "three", "four", "five", "six", "seven",
             "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
             "fifteen", "sixteen", "seventeen", "eighteen", "nineteen")
    if value < 0:
        raise ValueError("A prose count cannot be negative")
    return names[value] if value < len(names) else str(value)


def tipping_transition(rows, configured_days):
    """Read counts at the first configured adjacent dates with PD attrition."""
    if (not isinstance(configured_days, list) or len(configured_days) < 2
            or any(type(day) is not int or day <= 0 for day in configured_days)
            or configured_days != sorted(set(configured_days))):
        raise ValueError("landmark.tipping_days must be increasing, unique positive integer dates")
    if sorted(int(row["imputed_end_days"]) for row in rows) != configured_days:
        raise ValueError("Locked tipping dates do not match landmark.tipping_days")
    ordered = [utilities.unique_csv_row(rows, {"imputed_end_days": day}) for day in configured_days]
    # The approved caption describes the first loss of PD patients between
    # evaluated dates; never substitute invented counts or interpolate fits.
    for before, after in zip(ordered, ordered[1:]):
        pd_loss = int(before["PD"]) - int(after["PD"])
        if pd_loss > 0:
            cr_loss = int(before["CR"]) - int(after["CR"])
            if (cr_loss < 0 or before["PR"] != after["PR"] or before["SD"] != after["SD"]
                    or int(before["n"]) - int(after["n"]) != pd_loss + cr_loss):
                raise ValueError("Tipping counts cannot support the approved CR/PD attrition sentence")
            return before, after, pd_loss, cr_loss
    raise ValueError("No configured tipping interval supports the PD attrition caption")


parameter_rows = read_csv(RESULTS / "tables/manuscript/manuscript_parameters.csv")
PARAMETERS = {row["key"]: float(row["value"]) for row in parameter_rows}


# ---------- Table 1 ----------
t1 = list(csv.reader(open(RESULTS / "tables/manuscript/Table1_baseline_main_cohort.csv")))
# Display terminology only; the locked numerical input stays untouched. The
# locked CSV label says "chemotherapy", but the recorded interval can include
# non-chemotherapy systemic agents, so the manuscript uses "first-line therapy".
# "Not assessable" is replaced by the grade categories behind GB/GX, a nonzero
# count below 0.5% is shown as "<1%", and the Monte Carlo floor is shown as a
# bound, so the displayed cells match the caption and table notes.
t1_rows = []
for r in t1[1:]:
    row = [dash(c) if 0 < i < 7 else c for i, c in enumerate(r)]
    if row[0] == "First-line chemotherapy duration, days":
        row[0] = "First-line therapy duration, days"
    if row[1] == "Not assessable (GB/GX)":
        row[1] = "Borderline/unknown (GB/GX)"
    for i in range(2, 7):
        row[i] = pct_t1(row[i])
    t1_rows.append(row)
table1 = pipe_table(["Characteristic", "Level", "CR", "PR", "SD", "PD", "Excluded", "P"],
                    [[r[0], r[1], *r[2:7], fp_t1(r[7]) if r[7] else ""] for r in t1_rows])
# Table notes sit directly below the table body in both PDF and DOCX, so the
# table is self-contained even though its full legend is on the preceding page.
TABLE1_NOTES = (
    "Percentages are column percentages and include missing values in the denominator; "
    "they may not sum to 100 because of rounding. P values are from Fisher's exact tests (Monte Carlo, "
    "B=100,000) for categorical variables and Kruskal–Wallis tests for continuous variables; they are "
    "unadjusted for multiple comparisons and exclude missing values and excluded patients; inclusion "
    "comparisons between excluded and included patients are reported in the Results. Therapy-end dates "
    "were available for 26 of the 82 excluded patients; the therapy-duration and therapy-end "
    "medians in the Excluded column are calculated among these 26, and 35 had no first-line "
    "regimen record. Response labels are defined in Methods. "
    "Follow-up after the landmark is the median observed time to last contact among survivors "
    "(CR 133, PR 6, SD 8, PD 5), not a reverse Kaplan–Meier estimate; the reverse Kaplan–Meier median "
    "for the cohort was 73 months. Death percentages are not survival estimates; follow-up among "
    "survivors differed by response. The final row gives the numbers of excluded patients with CR/PR/SD/PD "
    "labels (46/13/12/11). CR, complete response; FIGO, International Federation of Gynecology and "
    "Obstetrics; GB, borderline; GDC, Genomic Data Commons; GX, unknown grade; IQR, interquartile range; "
    "OS, overall survival; PD, progressive disease; PR, partial response; R0, no macroscopic residual "
    "disease; SD, stable disease; TCGA-CDR, TCGA Clinical Data Resource; TCGA-OV, The Cancer Genome "
    "Atlas ovarian cancer cohort."
)
table1 = table1 + "\n\n" + TABLE1_NOTES

# ---------- Table 2 (all rows, including the post hoc HGSOC row, come from script 20) ----------
t2 = read_csv(RESULTS / "tables/manuscript/Table2_model_comparison_formatted.csv")
# The formatted table rounds ΔAIC to one decimal and keeps only the M3
# bootstrap share. Read the locked model-comparison table for full precision
# and the M_PD share so near-ties remain visible; nothing is re-fitted here.
t2_src = [r for r in read_csv(RESULTS / "tables/main/Table2_model_comparison.csv")
          if "imputed" not in r["time_origin"]]
if len(t2_src) != len(t2):
    raise SystemExit("Table 2 source and formatted rows disagree")

# Short row labels keep a 190 mm, 13-column table legible at 8 pt. The cohort
# prefix is retained only where the study population changes.
T2_LABELS = [
    "TCGA-OV: all labelled with OS (453/454)",
    "TCGA-OV: fixed 6-month landmark",
    "TCGA-OV: diagnosis, main cohort (372)",
    "TCGA-OV: therapy end (main)",
    "TCGA-OV: therapy end, adjusted",
    "TCGA-OV: platinum–taxane doublet",
    "TCGA-OV: HGSOC, therapy end (post hoc)",
    "GSE63885: diagnosis, no landmark",
    "GSE63885: fixed 6-month landmark",
    "TCGA-OV: therapy end, IPW",
    "TCGA-OV: therapy end, IPW, adjusted",
]
if len(T2_LABELS) != len(t2):
    raise SystemExit("Table 2 label map is out of date")


def t2_p(cell):
    """Render a Table 2 P value without scientific notation.

    IPW cells mix robust Wald and likelihood-ratio statistics, and the original
    exponential strings are too wide for an 8 pt table; the smallest values
    carry no more information as <0.001.
    """
    if not cell or cell == "NA":
        return "—"
    try:
        value = float(cell)
    except ValueError:
        return cell
    if value < 0.001:
        return "<0.001"
    if value < 0.01:
        return f"{value:.3f}"
    return f"{value:.2f}"


def t2_daic(r):
    """Format ΔAIC, keeping two decimals when two codings are within 0.05.

    The HGSOC row has a 0.03 gap between M3 and M_PD; one decimal would print
    two 0.0 cells and hide the near-tie.
    """
    cells = [r[k] for k in ("dAIC_M1", "dAIC_M2", "dAIC_M3", "dAIC_M_PD")]
    if any(cell in {"", "NA"} for cell in cells):
        return "—"
    values = [float(cell) for cell in cells]
    tight = sorted(values)[1] < 0.05
    return "/".join(f"{v:.2f}" if tight and v < 1 else f"{v:.1f}" for v in values)


def t2_boot(r):
    """Return the M3 and M_PD bootstrap shares side by side."""
    m3, mpd = r.get("boot_M3_best", ""), r.get("boot_M_PD_best", "")
    if not m3 or not mpd or "NA" in (m3, mpd):
        return "—"
    return f"{100 * float(m3):.0f} / {100 * float(mpd):.0f}"


t2_rows = []
for i, (row, src) in enumerate(zip(t2, t2_src)):
    # The last two rows are the weighted analyses, whose P values are robust
    # Wald statistics rather than likelihood-ratio tests.
    dagger = "†" if i >= len(t2_src) - 2 else ""
    t2_rows.append([
        T2_LABELS[i],
        "No" if row["Adjustment"] == "none" else "Yes",
        row["n (CR/PR/SD/PD)"],
        dash(row["PR vs CR"]), dash(row["SD vs CR"]), dash(row["PD vs CR"]),
        dash(row["NCR vs CR"]), dash(row["PD vs PR+SD"]),
        t2_p(src["plateau_p"]) + dagger,
        t2_p(src["ORR_p"]) + dagger,
        t2_p(src["PD_step_p"]) + dagger,
        t2_daic(src),
        t2_boot(src),
    ])
table2 = pipe_table(["Analysis", "Adj.", "n (CR/PR/SD/PD)", "PR vs CR", "SD vs CR", "PD vs CR",
                     "NCR vs CR", "PD vs PR+SD", "Plateau P", "ORR P", "PD-step P",
                     "ΔAIC (M1/M2/M3/M_PD)", "Bootstrap, % M3 / M_PD"], t2_rows)
# Notes sit directly below the table body in both PDF and DOCX, so the table
# does not depend on the legend page for its abbreviations.
TABLE2_NOTES = (
    "Values are hazard ratios for death (95% CI) from the stated model; rows are unadjusted unless "
    "Adj. is Yes (age, stage and residual disease). Plateau P, objective-response (ORR) constraint P "
    "and PD-step P are likelihood-ratio tests of PR=SD=PD, PR=CR and SD=PD, and PD=PR+SD. ΔAIC is AIC "
    "minus the lowest AIC in the row; 0.00 marks the reference and a gap below 0.05 indicates "
    "indistinguishable codings. BIC selected M3 in every unweighted TCGA-OV row and M_PD in both GSE63885 "
    "rows. Bootstrap gives the percentage of 1000 resamples (500 for the platinum–taxane subset) in which "
    "M3 and M_PD had the lowest AIC. P values are unadjusted for multiplicity; values below 0.001 are "
    "shown as <0.001. †Robust Wald P from exploratory weighted models, not directly comparable with the "
    "likelihood-ratio P values; weights were 0.86–2.24, with effective sample sizes of 357 and 335. "
    "One of two missing-stage patients in the 435-person proxy target was included. Sparse stage–site "
    "patterns and extreme coefficients with large standard errors indicated inclusion-model instability. "
    "Variances treated weights as fixed; proxy eligibility and uncorrected complete-case selection limit "
    "interpretation, and bias removal is not established. Of 454 labelled patients, 453 had OS and 372 formed the "
    "landmark cohort. ΔAIC and bootstrap were not computed for weighted rows, and bootstrap was not "
    "computed for adjusted or external rows; —, not computed. AIC, Akaike information criterion; BIC, "
    "Bayesian information criterion; CI, confidence interval; CR, complete response; FIGO, International "
    "Federation of Gynecology and Obstetrics; HGSOC, high-grade serous ovarian cancer; IPW, inverse "
    "probability of inclusion weighting; NCR, non-complete response; ORR, objective response rate; PD, "
    "progressive disease; PR, partial response; SD, stable disease; TCGA-OV, The Cancer Genome Atlas "
    "ovarian cancer cohort."
)
table2 = table2 + "\n\n" + TABLE2_NOTES

# ---------- main manuscript ----------
body_src = "\n\n".join(open(SOURCE / s).read().strip() for s in ["introduction.md", "methods_results.md", "discussion.md"])
body, order, refs = number_citations(body_src)
legends = open(SOURCE / "legends.md").read().strip()
decl = open(SOURCE / "declarations.md").read().strip()
hl_lines = [l[2:].strip() for l in open(SOURCE / "highlights.md").read().splitlines() if l.startswith("- ")]
title = open(SOURCE / "title_page.md").read().strip()
abstract = title[title.index("## Abstract"):title.index("**Keywords:**")]
keywords = [k.strip() for k in title[title.index("**Keywords:**") + 13:].strip().split(";")]

n_main, n_leg, n_abs = words(body_src), words(legends), words(abstract.replace("## Abstract", ""))
n_display = len(re.findall(r"^\*\*Figure \d", legends, re.M)) + len(re.findall(r"^\*\*Table \d", legends, re.M))
inline_tables = [l for l in body_src.splitlines() if l.lstrip().startswith("|")]

checks = {
    f"main text {n_main} ≤ {LIMITS['main_words']} words": n_main <= LIMITS["main_words"],
    f"main text + legends {n_main + n_leg} ≤ {LIMITS['main_words']} (conservative)": n_main + n_leg <= LIMITS["main_words"],
    f"abstract {n_abs} ≤ {LIMITS['abstract_words']} words": n_abs <= LIMITS["abstract_words"],
    f"references {len(order)} ≤ {LIMITS['refs']}": len(order) <= LIMITS["refs"],
    f"tables+figures {n_display} ≤ {LIMITS['display_items']}": n_display <= LIMITS["display_items"],
    f"no inline tables in main text ({len(inline_tables)} lines)": not inline_tables,
    f"highlights {len(hl_lines)} in {LIMITS['highlights'][0]}–{LIMITS['highlights'][1]}": LIMITS["highlights"][0] <= len(hl_lines) <= LIMITS["highlights"][1],
    f"highlight lengths {[len(x) for x in hl_lines]} ≤ {LIMITS['highlight_chars']}": all(len(x) <= LIMITS["highlight_chars"] for x in hl_lines),
    f"keywords {len(keywords)} ≤ {LIMITS['keywords']}": len(keywords) <= LIMITS["keywords"],
}
percentage_checks = percentage_claim_checks(
    utilities.read_json(ROOT / "config" / "manuscript_claims.json", required_keys=("claims", "percentage_claims")),
)
checks.update(percentage_checks)
if not all(percentage_checks.values()):
    raise ValueError("Descriptive date-scenario percentages do not match the locked summary")

title = (title.replace("{{MAIN_WORDS}}", f"{n_main:,}").replace("{{LEGEND_WORDS}}", f"{n_leg:,}")
         .replace("{{ABSTRACT_WORDS}}", str(n_abs)).replace("{{N_REFS}}", str(len(order)))
         .replace("{{HIGHLIGHTS}}", "\n".join(f"- {x}" for x in hl_lines)))
# Journal typography applies to displayed prose, legends and generated tables;
# the numbered reference list is left untouched.
title = journal_p(title)
body = journal_p(body)
decl = journal_p(decl)
legends = journal_p(legends)
table1 = journal_p(table1)
table2 = journal_p(table2)
tables = (f"## Tables\n\n**Table 1. Characteristics of the TCGA-OV landmark cohort by first-line response, and of excluded patients.**\n\n{table1}\n\n"
          f"**Table 2. Comparison of response codings across time origins, populations, selection handling and the external four-class cohort.**\n\n{table2}\n")
ms = f"{title}\n\n{body}\n\n{decl}\n\n## References\n\n{refs}\n\n{legends}\n\n{tables}"
(OUTPUT / f"{OUTPUT_PREFIX}_manuscript.md").write_text(ms)
(OUTPUT / f"{OUTPUT_PREFIX}_highlights.txt").write_text("\n".join(hl_lines) + "\n")

# ---------- supplementary appendix ----------
# Reporting-only helper validates and selects frozen sources; no model scripts
# are executed. Its outputs stay in the release root, even with a results override.
reporting_bundle = importlib.import_module("33_build_reporting_bundle").build_reporting_bundle()
sup_src = open(SOURCE / "supplementary.md").read()
sup, sorder, srefs = number_citations(sup_src, prefix="S")
# Locked phase-4 outputs retain legacy analyses; formal displays exclude them.
# Resolve cohort membership from the observed primary pool, not a second
# hardcoded cohort list that could drift from the publication policy.
primary_analysis = PROFILE["publication_policy"]["external_pool_analysis"]
primary_pool = utilities.read_unique_csv_row(
    RESULTS / "tables/phase4_external_validation/meta_analysis_noncr_minus_cr.csv",
    {"analysis": primary_analysis, "score": "general_proliferation"},
)
primary_external_cohorts = set(primary_pool["cohorts"].split(";"))
if primary_external_cohorts & set(PROFILE["publication_policy"]["excluded_cohorts"]):
    raise ValueError("The locked primary pool contains a publication-excluded cohort")
s1 = [r for r in read_csv(RESULTS / "tables/manuscript/TableS1_external_cohorts.csv")
      if r["cohort"] in primary_external_cohorts and r["retracted_source"] == "FALSE"]
if len(s1) != len(primary_external_cohorts) or {r["cohort"] for r in s1} != primary_external_cohorts:
    raise ValueError("External cohort display must contain exactly the three primary cohorts")
tS1 = pipe_table(["Cohort", "Platform", "Retracted source", "n", "CR", "NCR", "PR", "SD", "PD", "OS events", "Optimal debulking", "Median recorded OS time, months"],
                 [[r["cohort"], r["platform"], "Yes" if r["retracted_source"] == "TRUE" else "No", r["n"], r["CR"], r["Non_CR"],
                   *((r["PR"], r["SD"], r["PD"]) if int(r["PR"]) + int(r["SD"]) + int(r["PD"]) > 0 else ("–", "–", "–")),
                   r["OS_events"], r["optimal_debulking"], r["median_OS_months"]] for r in s1])
gse30161 = utilities.unique_csv_row(s1, {"cohort": "GSE30161"})
if int(gse30161["SD"]) or int(gse30161["Non_CR"]) != int(gse30161["PR"]) + int(gse30161["PD"]):
    raise ValueError("The GSE30161 caption assumes an NCR group of PR and PD only")
# Keep the locked numeric S1 table unchanged; add provenance and cohort flow
# from the existing observed inventory and primary response-cohort audit.
reporting = utilities.read_json(ROOT / "config/external_cohort_reporting.json", required_keys=("cohorts",))["cohorts"]
if len(reporting) != len(s1) or {r["cohort"] for r in reporting} != primary_external_cohorts:
    raise ValueError("External reporting crosswalk must match the primary cohorts exactly")
inventory = read_csv(RESULTS / "tables/external_response_inventory/external_response_cohort_inventory.csv")
external_audit = read_csv(RESULTS / "tables/phase4_external_validation/external_cohort_audit.csv")
external_survival = read_csv(RESULTS / "tables/phase4_external_validation/os_cox_noncr_vs_cr.csv")
external_landmark_days = utilities.required_value(ANALYSIS, "external_validation", "landmark_days")
flow_rows, semantic_rows = [], []
for report in reporting:
    raw = utilities.unique_csv_row(inventory, {"dataset": report["inventory_dataset"]})
    labelled = utilities.unique_csv_row(external_audit, {"cohort": report["cohort"], "set": "primary"})
    displayed = utilities.unique_csv_row(s1, {"cohort": report["cohort"]})
    if any(displayed[field] != labelled[field] for field in ("n", "CR", "Non_CR", "PR", "SD", "PD")):
        raise ValueError(f"Pre-landmark characteristics disagree with the cohort audit: {report['cohort']}")
    landmark = utilities.unique_csv_row(external_survival, {"cohort": report["cohort"], "landmark_days": external_landmark_days})
    counts = [int(raw["n_total"]), int(raw["n_serous"]), int(labelled["n"]), int(landmark["n"]), int(landmark["events"])]
    if any(a < b for a, b in zip(counts, counts[1:])):
        raise ValueError(f"External cohort flow is not non-increasing: {report['cohort']}")
    flow_rows.append([report["cohort"], *counts])
    semantic_rows.append([report["cohort"], report["response_field"], report["response_values"], report["death_definition"]])
tS1flow = pipe_table(["Cohort", "Source samples", "Serous", "Serous with response", "Landmark", "Deaths after landmark"], flow_rows)
tS1semantics = pipe_table(["Cohort", "Original response field", "Original response values and mapping", "Death definition"], semantic_rows)
# Per-cohort survival inputs behind the pooled external NCR-versus-CR estimate.
# Values are copied from the locked Cox table; no estimate is recomputed here.
s1_surv_rows = []
for report in reporting:
    surv = utilities.unique_csv_row(external_survival, {"cohort": report["cohort"], "landmark_days": external_landmark_days})
    if abs(float(surv["HR"]) - math.exp(float(surv["log_HR"]))) > 1e-6:
        raise ValueError(f"Per-cohort hazard ratio disagrees with its log scale: {report['cohort']}")
    s1_surv_rows.append([report["cohort"], surv["n"], surv["events"], f"{float(surv['log_HR']):.3f}",
                         f"{float(surv['se']):.3f}", hr(surv["HR"], surv["HR_low"], surv["HR_high"])])
tS1surv = pipe_table(["Cohort", "n", "Deaths", "log HR", "SE", "NCR vs CR (95% CI)"], s1_surv_rows)
pct = lambda v: "–" if v in ("", "NA") else f"{100 * float(v):.0f}"
pan_source = RESULTS / "tables/manuscript/TableS4_pancancer_label_audit.csv"
pan_published = RESULTS / "tables/supplementary/TableS4_pancancer_label_audit.csv"
if pan_source.read_bytes() != pan_published.read_bytes():
    raise SystemExit(f"Table S4 CSV copies differ: {pan_source} and {pan_published}")
pan = read_csv(pan_source)
dich = read_csv(RESULTS / "tables/pancancer_topology/dichotomy_cr_vs_noncr_by_cancer.csv")
dich_diag = [r for r in dich if r["landmark"] == "none"]
dich_treated = {r["cancer"] for r in dich_diag if r["subset"] == "treated"}
dich_missing_rows = sorted(
    [r for r in dich_diag if r["subset"] == "all" and r["cancer"] not in dich_treated],
    key=lambda r: -float(r["HR"]))
dich_missing = [r["cancer"] for r in dich_missing_rows]
dich_meta = read_csv(RESULTS / "tables/pancancer_topology/dichotomy_meta.csv")
dich_meta_end = [r for r in dich_meta if r["subset"] == "all" and r["landmark"] == "therapy_end"]
# Locked display assertions: the S3 caption names the four tumour types without a
# treated row and the pooled therapy-end estimate. Fail the build rather than
# silently publishing a caption that no longer matches the CSV. Treated-subset
# eligibility counts are not recorded for excluded subsets, so the caption states
# the qualitative reason rather than unverifiable numbers.
if dich_missing != ["CESC", "COAD", "UCEC", "LUSC"]:
    raise SystemExit("Figure S3 missing-treated caption no longer matches the locked dichotomy table")
if len(dich_meta_end) != 1 or int(dich_meta_end[0]["k"]) != 6:
    raise SystemExit("Figure S3 pooled therapy-end caption no longer matches the locked meta-analysis")
meta_end = dich_meta_end[0]
# Figure S4 source table. Every number in the S4 caption is taken from this locked
# table; the build fails rather than publish a caption that has drifted from it.
s4 = read_csv(RESULTS / "tables/pancancer_topology/topology_models_by_set.csv")
s4_sel = [r for r in s4 if r["endpoint"] == "OS" and r["adjustment"] == "unadjusted"
          and r["landmark"] in ("none", "therapy_end")]
s4_sets = ["BLCA_all", "BLCA_treated", "LGG_all", "LGG_treated", "OV_all"]
if len(s4_sel) != 10 or sorted({r["set"] for r in s4_sel}) != sorted(s4_sets):
    raise SystemExit("Figure S4 source table no longer contains the locked five sets")
def s4_row(set_name, landmark):
    rows = [r for r in s4_sel if r["set"] == set_name and r["landmark"] == landmark]
    if len(rows) != 1:
        raise SystemExit(f"Figure S4 source row missing or duplicated: {set_name}/{landmark}")
    return rows[0]
s4_ov_none = s4_row("OV_all", "none")
s4_ov_end = s4_row("OV_all", "therapy_end")
if int(s4_ov_none["n"]) != int(PARAMETERS["pancancer_ov_all_n"]):
    raise SystemExit("Figure S4 ovarian diagnosis n no longer matches the locked parameter")
for a, b in (("BLCA_all", "BLCA_treated"), ("LGG_all", "LGG_treated")):
    x, y = s4_row(a, "therapy_end"), s4_row(b, "therapy_end")
    fields = ["n", "events", "HR_PR", "HR_PR_low", "HR_PR_high",
              "HR_SD", "HR_SD_low", "HR_SD_high", "HR_PD", "HR_PD_low", "HR_PD_high"]
    if any(x[f] != y[f] for f in fields):
        raise SystemExit(f"Figure S4 therapy-end duplicate panels diverged: {a}/{b}")
if max(float(r[c]) for r in s4_sel for c in ("HR_PR_high", "HR_SD_high", "HR_PD_high")) >= 30:
    raise SystemExit("Figure S4 CI now exceeds the locked 30 panel limit")
tPan = pipe_table(["Cancer", "n", "CR", "PR", "SD", "PD", "OS events", "% first-line systemic", "% non-surgical first-line", "% therapy end known",
                  "% R0 in CR", "% R0 in NCR", "E1", "E2", "Eligible"],
                 [[r["cancer"], r["n"], r["CR"], r["PR"], r["SD"], r["PD"], r["OS_events"], pct(r["pct_first_line_systemic"]),
                   pct(r["pct_nonsurgical"]), pct(r["pct_therapy_end_known"]), pct(r["pct_R0_CR"]), pct(r["pct_R0_nonCR"]),
                   *("Yes" if r[c] == "TRUE" else "No" for c in ["E1_power", "E2_therapy_defined", "eligible"])] for r in pan])
hg_rows = read_csv(RESULTS / "tables/ov_hgsoc_sensitivity/hgsoc_topology_by_setting.csv")
hg = {(r["setting"], r["adjustment"]): r for r in hg_rows}
flow = read_csv(RESULTS / "tables/ov_hgsoc_sensitivity/hgsoc_cohort_flow.csv")
hgsoc_definition = {"TCGA-OV (serous by study design), grade G2-G4, FIGO III-IV":
                    "TCGA-OV (serous by study design), grade G2–G4, FIGO stage III–IV"}
tHa = pipe_table(["Cohort", "Definition", "Total", "CR", "PR", "SD", "PD"],
                 [[r[c] if c != "definition" else hgsoc_definition.get(r[c], r[c])
                   for c in ["stage", "definition", "total", "CR", "PR", "SD", "PD"]] for r in flow])
tHb = pipe_table(["Setting", "Adjustment", "n", "Events", "PR vs CR", "SD vs CR", "PD vs CR", "NCR vs CR", "PD vs PR+SD", "Plateau P", "ORR P", "PD-step P", "Best AIC", "Best BIC"],
                  [[r["setting"], r["adjustment"], r["n"], r["events"], hr(r["HR_PR"], r["HR_PR_low"], r["HR_PR_high"]),
                    hr(r["HR_SD"], r["HR_SD_low"], r["HR_SD_high"]), hr(r["HR_PD"], r["HR_PD_low"], r["HR_PD_high"]),
                    hr(r["HR_NonCR"], r["HR_NonCR_low"], r["HR_NonCR_high"]), hr(r["HR_PD_vs_PRSD"], r["HR_PD_vs_PRSD_low"], r["HR_PD_vs_PRSD_high"]),
                    fp3(r["plateau_p"]), fp3(r["ORR_p"]), fp3(r["PD_step_p"]), r["best_AIC"], r["best_BIC"]]
                   for r in hg.values()])
rd = read_csv(RESULTS / "tables/ov_therapy_end_landmark/noncr_by_residual_disease.csv")
rdi = {(r["split"], r["adjustment"]): r for r in read_csv(RESULTS / "tables/ov_therapy_end_landmark/noncr_residual_interaction.csv")}
split_label = {"optimal_10mm": "≤10 mm vs >10 mm", "R0": "R0 vs any"}
stratum_label = {"Residual <=10 mm": "≤10 mm", "Residual >10 mm": ">10 mm",
                 "No macroscopic residual": "R0", "Any macroscopic residual": "Any"}
def s4a_row(n, r):
    """Interaction estimates are shown once per split/adjustment, on its second stratum row."""
    i = rdi[(r["split"], r["adjustment"])]
    inter = (hr(i["HR_ratio_interaction"], i["HR_ratio_low"], i["HR_ratio_high"]), fp(i["interaction_LRT_p"])) if n % 2 else ("", "")
    return [split_label[r["split"]], r["adjustment"], stratum_label[r["stratum"]], r["n"], r["events"], r["CR"], r["NCR"],
            hr(r["HR_NonCR"], r["HR_NonCR_low"], r["HR_NonCR_high"]), *inter]
assert all(rd[k]["split"] == rd[k + 1]["split"] and rd[k]["adjustment"] == rd[k + 1]["adjustment"] for k in range(0, len(rd), 2))
tRa = pipe_table(["Residual-disease split", "Adjustment", "Stratum", "n", "Events", "CR", "NCR", "NCR vs CR", "HR ratio (interaction)", "Interaction P"],
                  [s4a_row(n, r) for n, r in enumerate(rd)])
external_landmark_days = utilities.required_value(ANALYSIS, "external_validation", "landmark_days")
loo = [r for r in read_csv(RESULTS / "tables/phase4_external_validation/os_meta_noncr_vs_cr_leave_one_out.csv")
       if r["landmark_days"] == str(external_landmark_days) and r["analysis"] == primary_analysis]
if not loo:
    raise ValueError(f"No primary external leave-one-out results for configured landmark: {external_landmark_days}")
analysis_label = {primary_analysis: "Primary external"}
tRd = pipe_table(["Pooled set", "Omitted cohort", "Remaining cohorts", "k", "Events", "NCR vs CR", "P", "I², %"],
                  [[analysis_label[r["analysis"]], r["omitted"], r["cohorts"].replace(";", ", "), r["k"], r["events"],
                    hr(r["HR"], r["HR_low"], r["HR_high"]), fp(r["p_value"]), f"{float(r['I2']):.0f}"] for r in loo])
rt = read_csv(RESULTS / "tables/ov_therapy_end_landmark/topology_by_residual_disease.csv")
na = lambda v: v in ("", "NA")
def topo_cells(r):
    """Format topology estimates, retaining dashes for deliberately untested rows."""
    if na(r.get("plateau_p", "")):
        return ["–"] * 8
    return [hr(r["HR_PR"], r["HR_PR_low"], r["HR_PR_high"]), hr(r["HR_SD"], r["HR_SD_low"], r["HR_SD_high"]),
            hr(r["HR_PD"], r["HR_PD_low"], r["HR_PD_high"]), fp3(r["plateau_p"]), fp3(r["ORR_p"]), fp3(r["PD_step_p"]),
            "/".join(f"{float(r[c]):.1f}" for c in ["dAIC_M1", "dAIC_M2", "dAIC_M3", "dAIC_M_PD"]), r["best_AIC"]]
tRb = pipe_table(["Stratum", "Adjustment", "n (CR/PR/SD/PD)", "PR vs CR", "SD vs CR", "PD vs CR", "Plateau P", "ORR P", "PD-step P",
                  "ΔAIC M1/M2/M3/M_PD", "Best AIC"],
                 [[stratum_label[r["stratum"]], r["adjustment"], f"{r['n']} ({r['CR']}/{r['PR']}/{r['SD']}/{r['PD']})", *topo_cells(r)] for r in rt])
de = read_csv(RESULTS / "tables/ov_therapy_end_landmark/topology_delayed_entry_and_L_adjusted.csv")
tRc = pipe_table(["Model", "Adjustment", "n", "NCR vs CR", "PR vs CR", "SD vs CR", "PD vs CR", "Plateau P", "ORR P", "PD-step P",
                  "ΔAIC M1/M2/M3/M_PD", "Best AIC"],
                 [[r["model"], r["adjustment"] + ("" if r["model"].startswith("Delayed") else " + L"), r["n"],
                   hr(r["HR_NonCR"], r["HR_NonCR_low"], r["HR_NonCR_high"]), *topo_cells(r)[:7], r["best_AIC"]] for r in de])
# (f) Label-source sensitivity: 307 patients with a clinical-matrix label and
# the 306 whose two records agreed. Both CSVs are locked outputs of script 17.
label_source_rows = []
for label, source in (("Clinical-matrix label", "topology_excluding_cdr_only.csv"),
                      ("Concordant labels only", "topology_strictly_concordant.csv")):
    for r in read_csv(RESULTS / "tables/ov_therapy_end_landmark" / source):
        label_source_rows.append([label, r["adjustment"], r["n"], r["events"],
                                  hr(r["HR_NonCR"], r["HR_NonCR_low"], r["HR_NonCR_high"]),
                                  fp3(r["plateau_p"]), fp3(r["ORR_p"]), r["best_AIC"], r["best_BIC"]])
tRf = pipe_table(["Label set", "Adjustment", "n", "Deaths", "NCR vs CR", "Plateau P", "ORR P", "Best AIC", "Best BIC"],
                 label_source_rows)
ss = [r for r in read_csv(RESULTS / "tables/phase4_external_validation/os_meta_noncr_vs_cr_small_sample.csv")
      if r["landmark_days"] == str(external_landmark_days) and r["analysis"] == primary_analysis]
if not ss:
    raise ValueError(f"No primary external small-sample results for configured landmark: {external_landmark_days}")
pool_role = {
    "Cox, REML (Wald CI)": "Primary",
    "Cox, REML (HKSJ CI)": "Sensitivity (small k)",
    "Firth Cox, REML (Wald CI)": "Sensitivity (penalised)",
}
tRe = pipe_table(["Pooled set", "Role", "k", "Estimator", "NCR vs CR", "95% prediction interval", "I², %"],
                 [[analysis_label[r["analysis"]], pool_role[r["estimator"]], r["k"], r["estimator"], hr(r["HR"], r["HR_low"], r["HR_high"]),
                   "–" if na(r["PI_low"]) else f"{float(r['PI_low']):.2f}–{float(r['PI_high']):.2f}", f"{float(r['I2']):.0f}"] for r in ss])
# Eight existing OS origins are split into estimate and information-criterion
# panels for legibility; every original numeric field is retained in the CSV.
s5 = read_csv(pathlib.Path(reporting_bundle["outputs"]["table_s5"]))
origin_labels = {
    "none": "Diagnosis", "fixed183": "Fixed 183 d", "fixed270": "Fixed 270 d",
    "fixed365": "Fixed 365 d", "therapy_end": "Therapy end",
    "therapy_end_plus30": "End + 30 d", "therapy_end_any": "Any recorded end",
    "therapy_end_imputed": "Imputed end",
}
tS5a = pipe_table(
    ["Origin", "Adjustment", "n / deaths", "CR/PR/SD/PD", "PR vs CR", "SD vs CR",
     "PD vs CR", "NCR vs CR", "Plateau P", "ORR P", "PD-step P"],
    [[origin_labels[r["landmark"]], r["adjustment"], f"{r['n']} / {r['events']}",
      "/".join(r[c] for c in ("CR", "PR", "SD", "PD")),
      *(hr(r[c], r[c + "_low"], r[c + "_high"]) for c in ("HR_PR", "HR_SD", "HR_PD", "HR_NonCR")),
      *(fp(r[c]) for c in ("plateau_p", "ORR_p", "PD_step_p"))] for r in s5],
)
tS5b = pipe_table(
    ["Origin", "Adjustment", "ΔAIC M1/M2/M3/M_PD", "ΔBIC M1/M2/M3/M_PD", "Best AIC", "Best BIC"],
    [[origin_labels[r["landmark"]], r["adjustment"],
      *("/".join(f"{float(r[p + m]):.1f}" for m in ("M1", "M2", "M3", "M_PD")) for p in ("dAIC_", "dBIC_")),
      r["best_AIC"], r["best_BIC"]] for r in s5],
)
rmst = read_csv(ROOT / "results/tables/ov_therapy_end_landmark/rmst_therapy_end.csv")
risk = read_csv(ROOT / "results/tables/ov_therapy_end_landmark/number_at_risk_therapy_end.csv")
def risk_at(group, month):
    """Read the recorded tail support; do not recompute survival estimates."""
    return utilities.unique_csv_row(risk, {"group": group, "months": month})["at_risk"]

tS5c = pipe_table(
    ["Horizon, months", "RMST CR, months", "RMST NCR, months", "NCR − CR (95% CI), months", "P", "CR at risk", "NCR at risk"],
    [[r["tau_months"], f"{float(r['RMST_CR']):.1f}", f"{float(r['RMST_NonCR']):.1f}",
      sdiff(r["difference"], r["low"], r["high"]), fp(r["p"]),
      risk_at("CR", r["tau_months"]), risk_at("NCR", r["tau_months"])] for r in rmst],
)
risk_summary = read_csv(ROOT / "results/tables/supplementary/risk_set_audit_summary.csv")
risk_metrics = ("os_main", "os_adjusted", "ncr_unadjusted", "ncr_adjusted", "pfi_all", "pfi_adjusted")
risk_labels = {
    "os_main": "Main analysis", "os_adjusted": "Main analysis",
    "ncr_unadjusted": "NCR only", "ncr_adjusted": "NCR only",
    "pfi_all": "Full PFI", "pfi_adjusted": "Full PFI",
}
tS5d = pipe_table(
    ["Existing model", "Endpoint", "Adjustment", "n", "Events", "CR/PR/SD/PD"],
    [[risk_labels[metric], r["endpoint"], r["adjustment"], r["n"], r["events"],
      "/".join(utilities.unique_csv_row(risk_summary, {"metric": metric, "response4": response})["n"]
               for response in ("CR", "PR", "SD", "PD"))]
     for metric in risk_metrics
     for r in [utilities.unique_csv_row(risk_summary, {"metric": metric, "response4": "ALL"})]],
)
tS5e = pipe_table(
    ["PFI exclusion reason (in order)", "n", "CR", "PR", "SD", "PD"],
    [[r["reason"].replace("_", " "), r["n"],
      *(utilities.unique_csv_row(risk_summary, {"metric": "pfi_exclusion", "reason": r["reason"], "response4": response})["n"]
        for response in ("CR", "PR", "SD", "PD"))]
     for r in risk_summary if r["metric"] == "pfi_exclusion" and r["response4"] == "ALL"],
)
s6 = read_csv(pathlib.Path(reporting_bundle["outputs"]["table_s6"]))
s6_score_labels = {
    "general_proliferation": "General proliferation",
    "replication_composite": "Replication composite",
    "replication_licensing": "Replication licensing",
    "dna_synthesis": "DNA synthesis",
    "atr_checkpoint": "ATR checkpoint",
    "robust_nine_composite": "Nine-pathway composite",
    "MKI67_expression_z": "MKI67 mRNA (z score)",
    "replication_excess": "Replication excess",
    "licensing_given_proliferation": "Replication licensing",
}
s6_adjustment_labels = {
    "response_only": "None",
    "general_proliferation": "General proliferation",
}
unmapped_scores = sorted({r["score"] for r in s6} - set(s6_score_labels))
unmapped_adjustments = sorted({r["adjustment"] for r in s6} - set(s6_adjustment_labels))
if unmapped_scores or unmapped_adjustments:
    raise SystemExit(f"Unmapped Table S6 labels: {unmapped_scores} / {unmapped_adjustments}")
tS6 = pipe_table(
    ["Score", "Adjustment", "Negative cohorts, n", "REML difference (95% CI)", "REML P",
     "HKSJ 95% CI", "HKSJ P", "I² (%)", "95% prediction interval"],
    [[s6_score_labels[r["score"]], s6_adjustment_labels[r["adjustment"]], r["negative_direction_k"],
      sdiff2(r["REML_estimate"], r["REML_low"], r["REML_high"]), fp(r["REML_p"]),
      srange(r["HKSJ_low"], r["HKSJ_high"]), fp(r["HKSJ_p"]), f"{float(r['I2']):.0f}",
      srange(r["PI_low"], r["PI_high"])] for r in s6],
)
s7 = sorted(read_csv(RESULTS / "tables/supplementary/TableS7_response_partition_scan.csv"),
            key=lambda r: int(r["rank_adjusted"]))
if [int(r["rank_adjusted"]) for r in s7] != list(range(1, len(s7) + 1)):
    raise SystemExit("Table S7 must have one row per ranked bipartition")
tS7a = pipe_table(
    ["Partition", "Contrast", "n", "Deaths", "Adjusted HR (95% CI)", "P", "q",
     "Unadjusted HR (95% CI)", "P", "q"],
    [[r["rank_adjusted"], f"{r['reference']} vs {r['comparator']}", r["n_adjusted"],
      r["events_adjusted"], hr(r["HR_adjusted"], r["CI_low_adjusted"], r["CI_high_adjusted"]),
      fp(r["p_adjusted"]), fp(r["q_adjusted"]),
      hr(r["HR_unadjusted"], r["CI_low_unadjusted"], r["CI_high_unadjusted"]),
      fp(r["p_unadjusted"]), fp(r["q_unadjusted"])] for r in s7],
)
s7e = read_csv(RESULTS / "tables/supplementary/TableS7_evalues.csv")
s7e_model = {
    "M3, age+stage+residual, n=343": "M3, adjusted, n=343",
    "M3, unadjusted, n=372": "M3, unadjusted, n=372",
    "M1 PR coefficient, age+stage+residual, n=343": "M1, adjusted, n=343",
}
unmapped_s7e = sorted({r["source"] for r in s7e} - set(s7e_model))
if unmapped_s7e:
    raise SystemExit(f"Unmapped Table S7 E-value sources: {unmapped_s7e}")
tS7b = pipe_table(
    ["Estimand", "Model", "HR (95% CI)", "Common-outcome E-value (point; CI bound)",
     "Uncorrected E-value (point; CI bound)"],
    [[r["estimand"], s7e_model[r["source"]], hr(r["HR"], r["CI_low"], r["CI_high"]),
      f"{float(r['E_value_common_point']):.2f} ({float(r['E_value_common_CI']):.2f})",
      f"{float(r['E_value_point']):.2f} ({float(r['E_value_CI']):.2f})"] for r in s7e],
)
S_TABLES = {
    "{{TABLE_S1}}":  ("**Supplementary Table S1. External cohorts (serous histology).** (a) Response-defined cohort characteristics and OS events counted from diagnosis. (b) Source-sample-to-landmark counts at the 183-day landmark. (c) Original response fields, mappings and death definitions. (d) Per-cohort inputs to the pooled NCR-versus-CR estimate: patients and deaths after the 183-day landmark, the natural-log hazard ratio and its standard error from the cohort-specific Cox model, and the corresponding hazard ratio (95% CI). The pooled estimate is computed from the log HR and SE columns; no estimate is recomputed for this table, and n and deaths agree with (b). "
                     f"The CR-versus-NCR contrast is CR versus PR+SD+PD (GSE63885), CR versus incomplete response (GSE23554), and CR versus PR+PD (GSE30161, whose NCR group comprised {gse30161['PR']} PR and {gse30161['PD']} PD before the landmark); the pooled HR combines these cohort-specific definitions, and separate PR, SD and PD categories were unavailable for GSE23554. "
                     "GSE23554 remains in the locked primary pool, but six tumours share identifiers with excluded PMID19318476; independence of their clinical annotation could not be verified. The existing pool omitting GSE23554 is shown in Table S3. "
                     f"Median recorded OS time is the median time from diagnosis to recorded death or last follow-up, not a Kaplan–Meier median survival. Deaths in (b) are counted after the landmark. Optimal debulking is n/N among patients with a recorded debulking status, and a dash (–) marks a category that was not recorded. DOD, death of disease; AWD, alive with disease; NED, no evidence of disease.\n\n(a)\n\n{tS1}\n\n(b)\n\n{tS1flow}\n\n(c)\n\n{tS1semantics}\n\n(d)\n\n{tS1surv}"),
    "{{TABLE_S2}}": ("**Supplementary Table S2. Operational high-grade serous ovarian cancer (HGSOC) sensitivity analysis (post hoc).** "
                     "(a) Nested cohort flow and response composition: 454 labelled TCGA-OV patients, 402 meeting the operational HGSOC definition "
                     "(401 with an OS time), and 334 of these beyond the patient-specific therapy-end landmark. "
                     "(b) Death hazard ratios (95% CI), constraint tests and information criteria by eligibility, time origin and adjustment. "
                     "The two Main TCGA-OV rows and the unadjusted HGSOC therapy-end row repeat Table 2; the main therapy-end landmark cohort "
                     "comprises 372 patients (Figure 1A). HGSOC settings differ in eligibility and origin: diagnosis in all eligible patients; "
                     "diagnosis restricted to patients who reached the therapy-end landmark; a fixed 183-day landmark; and the recorded end of "
                     "first-line therapy, accepted 60–365 days after diagnosis. The two n=334 settings contain the same patients; the diagnosis-origin "
                     "setting retains pre-landmark person-time, whereas the landmark setting starts follow-up at the landmark. n and Events are patients "
                     "and deaths in each model; adjusted models are complete-case for age (per 10 years), stage and residual disease. PR, SD and PD versus "
                     "CR come from the four-category model (M1); NCR versus CR from the CR-versus-NCR model (M3); PD versus PR+SD from the CR | PR+SD | PD "
                     "model (M_PD). Plateau P, ORR P and PD-step P are likelihood-ratio tests of PR=SD=PD (2 df), PR=CR and SD=PD jointly (2 df), and "
                     "PD=PR+SD (1 df); ORR P is the objective-response constraint, not a test of the response rate. Best AIC and Best BIC identify the "
                     "coding with the lowest criterion in that row; differences below 1 do not distinguish models.\n\n(a)\n\n" + tHa + "\n\n(b)\n\n" + tHb),
    "{{TABLE_S3}}": ("**Supplementary Table S3. Post hoc robustness analyses (TCGA-OV therapy-end landmark and external pooling).** "
                     "(a) Hazard ratios (95% CI) for death, NCR versus CR, within residual-disease strata. The two partitions overlap: "
                     "≤10 mm includes the 77 patients with no macroscopic residual (246+98=344; 77+267=344), and Any comprises 1–10 mm and >10 mm. "
                     "Of 372 landmark patients, 344 had a recorded residual category (343 complete-case for age and stage); the 28 without one enter "
                     "only (c), whose adjusted n is 343 (one further patient lacks stage). The HR ratio is the NCR × stratum interaction (second versus "
                     "first stratum) from a common-baseline model, not the ratio of the separately fitted stratum HRs (1.82 versus 3.54/1.54=2.30); "
                     "its P value is from a 1-df likelihood-ratio test. "
                     "(b) Four-category topology within the same strata; strata with fewer than three patients in any response category are not tested. "
                     "Model codes, constraint tests and ΔAIC are defined in Table S2; P values are unadjusted, and Best BIC agreed with Best AIC in every tested row. "
                     "(c) Delayed entry at the landmark on the diagnosis time scale, and on the landmark time scale with L (months from diagnosis to the end "
                     "of first-line therapy) as a covariate; these models address left truncation only. "
                     "(d) Leave-one-out REML re-pooling of the primary external NCR versus CR hazard ratio at the 6-month landmark: each row omits one "
                     "cohort and pools the remaining k, Events counts deaths in the remaining cohorts (so cohorts recur across rows), and P is from the "
                     "re-pooled estimate. Omitting GSE23554 also removes six tumours sharing identifiers with PMID19318476 (Table S1). "
                     "(e) Pooled estimates: REML with Wald or HKSJ confidence intervals, the REML 95% prediction interval, and a pooled Firth-penalised "
                     "Cox estimate, not per-cohort Firth estimates. Role marks the predefined primary pooled estimator; the HKSJ and Firth rows are "
                     "small-sample sensitivity analyses. PMID17290060 is not among the three pooled cohorts; it is excluded because its source "
                     "publication was retracted. "
                     "(f) Label-source sensitivity: the 307 patients with an available clinical-matrix response label "
                     "(65 exclusions) and the 306 with concordant labels only (66 exclusions, also removing the one discordant label). "
                     "These are source-label checks, not independent response re-adjudication. "
                     "All four codings were refitted on each shared complete-case set, so hazard ratios, constraint tests and information "
                     "criteria remain comparable within a row; adjusted models lose a further 18 patients without complete covariates. "
                     "Both label sets are locked outputs of the therapy-end analysis.\n\n(a)\n\n" + tRa + "\n\n(b)\n\n" + tRb + "\n\n(c)\n\n" + tRc
                     + "\n\n{{PAGE_BREAK}}\n\n(d)\n\n" + tRd + "\n\n(e)\n\n" + tRe + "\n\n(f)\n\n" + tRf),
    "{{TABLE_S4}}": f"**Supplementary Table S4. Pan-cancer label-semantics audit of TCGA first-course response.** Cancer, TCGA tumour-type abbreviation; n, patients with a first-course response label; percentages use these labelled patients as denominator, except the two R0 columns, which come from the UCSC Xena clinical matrices, are restricted to patients with a recorded R status (counts in the CSV) and group CR versus NCR by the Xena response field. OS events, deaths; % therapy end known, a recorded end of first-line systemic therapy or radiotherapy; % non-surgical first-line, systemic therapy or radiotherapy starting between 120 days before and 365 days after diagnosis, the E2 criterion; E1, power rule; Eligible, both rules met; –, not recorded. Agreement between first-course and regimen-level labels and all further columns are in TableS4_pancancer_label_audit.csv (Supplementary Data 5).\n\n{tPan}",
    "{{TABLE_S5}}": (
        "**Supplementary Table S5. Existing overall-survival, RMST and risk-set results across eight "
        "time origins (TCGA-OV).** (a) Model denominators (n, deaths and CR/PR/SD/PD counts), death "
        "hazard ratios (95% CI) and likelihood-ratio constraint tests. (b) ΔAIC and ΔBIC relative to "
        "the lowest-criterion model in each row, with the best AIC and BIC codings. (c) Unadjusted "
        "RMST and tail support at the main therapy-end landmark. (d) Denominators of the existing "
        "models; no model was refitted. (e) Hierarchical PFI exclusions, applied in the order shown.\n\n"
        "Diagnosis rows use 453 of the 454 labelled patients, those with a recorded OS time, and "
        "retain pre-landmark follow-up; fixed-origin rows use the 426, 404 and 386 patients whose "
        "follow-up reached 183, 270 and 365 days; therapy-end rows use the 372-patient main cohort "
        "(Table 2). Fixed origins are days from diagnosis. Therapy end accepts a recorded end "
        "60–365 days after diagnosis; End + 30 d adds 30 days; Any recorded end applies no window; "
        "Imputed end uses the existing deterministic scenario for unusable dates. None means "
        "unadjusted; adjusted models include age (per 10 years), stage and residual disease and are "
        "complete-case. M1–M3, M_PD and the plateau, ORR and PD-step tests are defined in Table S2; "
        "all P values are unadjusted.\n\n"
        "In (c), differences are NCR minus CR in months from the landmark; negative values "
        "indicate shorter RMST in NCR, P is from the asymptotic RMST test, and at 60 months only "
        "80 CR and 1 NCR patient remain at risk, so this difference should be interpreted "
        "cautiously. In (d), Events counts deaths for OS and progression or death for PFI; "
        "NCR-only rows exclude CR by design, the unadjusted count is the power-design denominator "
        "and the adjusted count the complete-case set for within-NCR comparisons. The 90 "
        "exclusions in (e) reduce the 454 labelled patients to the 364 unadjusted Full PFI "
        "patients in (d); the adjusted row is the 337-patient subset. No estimate, interval or "
        "P value was recalculated; unrounded fields are in TableS5_landmark_OS_results.csv "
        "(Supplementary Data 5).\n\n(a)\n\n" + tS5a
        + "\n\n{{PAGE_BREAK}}\n\n(b)\n\n" + tS5b + "\n\n(c)\n\n" + tS5c
        + "\n\n{{PAGE_BREAK}}\n\n(d)\n\n" + tS5d + "\n\n(e)\n\n" + tS5e),
    "{{TABLE_S6}}": (
        "**Supplementary Table S6. Locked proliferation and replication scores versus clinical "
        "response in three external ovarian cancer cohorts (five prespecified scores and four "
        "exploratory rows).** Differences are non-complete response (NCR) "
        "minus complete response (CR); negative values indicate a lower score in NCR, and higher scores "
        "indicate higher expression of the corresponding genes. Scores were standardised within each "
        "cohort, so units are within-cohort standard deviations (SD). The five locked scores (general "
        "proliferation, replication composite, replication licensing, DNA synthesis and ATR checkpoint) "
        "were defined before the external data were examined. The four remaining rows are exploratory: a "
        "composite of the genes in nine replication and cell-cycle pathways, MKI67 mRNA expression, the "
        "replication composite after removing its association with general proliferation, and the locked "
        "replication licensing score adjusted for general proliferation. Each cohort contributed one "
        "estimate, and cohort estimates were pooled by inverse-variance REML random-effects meta-analysis. "
        "All rows use GSE63885, GSE23554 and GSE30161 (k=3 cohorts) and the same 143 patients with a "
        "pretreatment score and a response label (70, 28 and 45); 138 of these patients were also in the "
        "landmark survival analyses, so the score and survival denominators differ. Response was recorded "
        "after first-line therapy, and definitions differed across cohorts (Table S1); no survival outcome "
        "is used in this table. None denotes an unadjusted score–response comparison, and no model "
        "included age, stage or residual disease. REML, restricted maximum likelihood; HKSJ, "
        "Hartung–Knapp–Sidik–Jonkman interval, a sensitivity interval whose width can differ substantially "
        "from the REML interval with three cohorts; I², proportion of variability attributable to "
        "between-cohort heterogeneity; PI, prediction interval. Estimated heterogeneity was zero in every "
        "row, so each PI equals its REML confidence interval. Negative cohorts counts cohorts with a "
        "difference below zero and is descriptive. P values are unadjusted for the nine comparisons, and "
        "every interval includes zero. Per-cohort estimates are in Supplementary Data 5.\n\n" + tS6),
    "{{TABLE_S7}}": (
        "**Supplementary Table S7. Exploratory response-partition scan and E-values for unmeasured "
        "confounding.** (a) All 15 non-empty subsets of the four response categories were scanned; 14 had a "
        "non-empty complement and defined a directed contrast, and opposite directions of the same split "
        "collapsed to seven bipartitions, each shown once with the CR-containing side as the reference. Death "
        "hazard ratios (95% CI) come from Cox models at the therapy-end landmark, unadjusted (n=372; 220 deaths) "
        "or adjusted for age (per 10 years), stage and residual disease in the 343 covariate-complete patients "
        "(207 deaths). P values are two-sided Wald tests; q values are Benjamini–Hochberg adjusted across the "
        "seven bipartitions within each adjustment. Partitions are ordered by adjusted q. The CR-versus-NCR "
        "contrast had the smallest P value before and after correction, but every bipartition separated survival "
        "(all q≤0.007). The scan was undertaken after the main analysis and no partition was pre-specified, so it "
        "is descriptive. (b) E-values for the NCR-versus-CR hazard ratio, adjusted and unadjusted, and for the "
        "adjusted PR-versus-CR hazard ratio from Table 2 as context. The E-value is the minimum risk-ratio "
        "association that an unmeasured confounder would need with both response and death to explain the "
        "observed association; the value in parentheses is the E-value for the 95% CI bound nearest the null. "
        "Because death was common (33.2% by 36 months and 51.9% by 60 months), the primary E-values convert "
        "the hazard ratio to a risk ratio for a common outcome; the uncorrected values apply the formula "
        "directly to the hazard ratio and are shown only for comparison. "
        "The PR row is contextual and was not tested for confounding.\n\n(a)\n\n" + tS7a + "\n\n(b)\n\n" + tS7b),
}
for k, v in S_TABLES.items():
    number = re.fullmatch(r"\{\{TABLE_S(\d+)\}\}", k).group(1)
    # Bare (a)/(b) lines are interpreted as ordered lists by Pandoc and can
    # leave an empty list label across a forced page break. Use explicit text.
    v = re.sub(r"(?m)^\(([a-f])\)$", r"**(\1)**", v)
    page_break = "" if number == "1" else "{{PAGE_BREAK}}\n\n"
    sup = sup.replace(k, page_break + "### Table S" + number + "\n\n" + v)

# Sample/event counts and pooling sizes come from the exact locked analysis
# rows used by the figures, not from prose literals or configuration defaults.
tipping_days = utilities.required_value(ANALYSIS, "landmark", "tipping_days")
tipping_rows = read_csv(RESULTS / "tables/ov_selection_regimen_power/tipping_imputed_end_date.csv",
                        required_fields=("imputed_end_days", "n", "CR", "PR", "SD", "PD"))
tip_before, tip_after, pd_loss, cr_loss = tipping_transition(tipping_rows, tipping_days)
pd_patients = "patient" if pd_loss == 1 else "patients"
cr_patients = "patient" if cr_loss == 1 else "patients"
hgsoc_caption_row = utilities.unique_csv_row(
    hg_rows, {"setting": "HGSOC therapy-end landmark", "adjustment": "none"},
)
proliferation_caption_row = primary_pool
# The restriction range and observed NCR set are counted from the same locked
# rows that generated Figure S1, so the legend cannot drift from the artwork.
restriction_rows = [
    row for row in read_csv(
        RESULTS / "tables/ov_selection_regimen_power/regimen_restriction_topology.csv",
        required_fields=("restriction", "adjustment", "n", "PD"),
    )
    if row["adjustment"] == "none" and row["restriction"] != "All (main analysis)"
]
if len(restriction_rows) != 7:
    raise SystemExit("Supplementary Figure S1 expects seven displayed restriction rows")
restriction_n = [int(row["n"]) for row in restriction_rows]
restriction_pd = [int(row["PD"]) for row in restriction_rows]
ncr_power_row = utilities.unique_csv_row(
    read_csv(RESULTS / "tables/ov_selection_regimen_power/pd_step_power_tcga.csv",
             required_fields=("setting", "n_nonCR", "n_PD")),
    {"setting": "TCGA therapy-end landmark, NCR patients"},
)

# ---------- Supplementary Figure S1 caption ----------
# The main forest row, the model-based Table 2 interval and the panel C grid are
# read from the same locked outputs as the artwork, so the caption cannot drift.
s1_main_row = utilities.unique_csv_row(
    read_csv(RESULTS / "tables/ov_selection_regimen_power/ipw_topology.csv",
             required_fields=("adjustment", "weighting", "n", "HR_PD_vs_PRSD",
                              "HR_PD_vs_PRSD_low", "HR_PD_vs_PRSD_high")),
    {"adjustment": "none", "weighting": "unweighted"},
)
t2_main_row = utilities.unique_csv_row(
    read_csv(RESULTS / "tables/manuscript/Table2_model_comparison_formatted.csv",
             required_fields=("Analysis", "Adjustment", "PD vs PR+SD")),
    {"Analysis": "TCGA-OV: End of first-line therapy (main)", "Adjustment": "none"},
)
t2_ci = re.search(r"\(\s*(\d+\.\d+)\s*[-\u2013]\s*(\d+\.\d+)\s*\)", t2_main_row["PD vs PR+SD"])
if not t2_ci:
    raise SystemExit("Table 2 main row lacks the model-based PD-vs-PR/SD interval")
power_grid = read_csv(RESULTS / "tables/ov_selection_regimen_power/pd_step_required_sample_size.csv",
                      required_fields=("HR", "PD_share"))
grid_hrs = sorted({round(float(row["HR"]), 3) for row in power_grid})
grid_shares = sorted({round(float(row["PD_share"]), 3) for row in power_grid})
if ([float(x) for x in utilities.required_value(ANALYSIS, "power", "future_hazard_ratios")] != grid_hrs
        or [float(x) for x in utilities.required_value(ANALYSIS, "power", "future_pd_fractions")] != grid_shares):
    raise SystemExit("Panel C caption grid does not match the locked power configuration")


def decimal_text(value):
    """Keep at least one decimal so target HR 2.0 does not print as 2."""
    text = f"{value:.2f}".rstrip("0")
    return text + "0" if text.endswith(".") else text


def prose_list(values):
    """Join short numeric values as the approved caption prose."""
    items = [decimal_text(value) for value in values]
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def name_list(values):
    """Join short names as the approved caption prose."""
    return values[0] if len(values) == 1 else ", ".join(values[:-1]) + " and " + values[-1]


s1_caption = (
    "**Supplementary Figure S1. Selection, treatment and power sensitivity analyses for the PD step (TCGA-OV).** "
    "(A) Unadjusted death hazard ratios (95% CI), PD versus PR+SD, and plateau P in the main therapy-end cohort "
    f"and inverse probability of inclusion weighting (IPW; each n={int(s1_main_row['n'])}), plus "
    f"{count_word(len(restriction_rows) - 1)} restriction subsets and their intersection "
    f"({count_word(len(restriction_rows))} restriction rows; {min(restriction_n)}\u2013{max(restriction_n)} patients; "
    f"{min(restriction_pd)}\u2013{max(restriction_pd)} with PD; criteria in Supplementary Methods). "
    "HR>1 indicates higher PD mortality. Plateau P tests PR=SD=PD (M3 versus M1, 2 df; Table 2). "
    "Main/IPW use robust intervals and Wald tests; restrictions use model-based intervals and likelihood-ratio tests. "
    f"Main CI: {float(s1_main_row['HR_PD_vs_PRSD_low']):.2f}\u2013"
    f"{float(s1_main_row['HR_PD_vs_PRSD_high']):.2f} robust versus "
    f"{t2_ci.group(1)}\u2013{t2_ci.group(2)} model-based (Table 2; Figure 3C). "
    "IPW is exploratory: one of two missing-stage patients in the 435-person proxy target was included; "
    "sparse stage–site patterns and extreme coefficients with large standard errors indicated instability. "
    "Weights are treated as fixed; proxy eligibility and uncorrected complete-case selection preclude claims of bias removal. "
    "The dashed line marks HR=1 (log scale). "
    f"(B) Likelihood-ratio plateau P over {count_word(len(tipping_rows))} fixed imputed end dates "
    f"({int(PARAMETERS['tipping_day_minimum'])}\u2013{int(PARAMETERS['tipping_day_maximum'])} days) for unusable dates; "
    "recorded plausible dates remain unchanged. "
    f"The rise beyond {int(tip_before['imputed_end_days'])} days coincides with PD n "
    f"{int(tip_before['PD'])}\u2192{int(tip_after['PD'])} and loss of {count_word(cr_loss)} CR {cr_patients} "
    f"at {int(tip_after['imputed_end_days'])} days. Dashed line: P={PARAMETERS['alpha']:.2f}. "
    f"(C) Total NCR (PR+SD+PD) patients required for {int(100 * PARAMETERS['target_power'])}% power "
    f"(two-sided \u03b1={PARAMETERS['alpha']:.2f}; Schoenfeld's formula), assuming PD shares "
    f"{prose_list(grid_shares)}, target PD-versus-PR+SD HRs {prose_list(grid_hrs)}, and the "
    f"observed NCR event fraction {PARAMETERS['pd_event_fraction']:.2f}. "
    f"The y axis is logarithmic; the observed NCR set comprised {int(ncr_power_row['n_nonCR'])} patients "
    f"({int(ncr_power_row['n_PD'])} with PD)."
)
assert "\n" not in s1_caption

calibration = read_csv(RESULTS / "tables/ov_response_sensitivity/calibration_summary.csv")
cal_36 = utilities.unique_csv_row(calibration, {"horizon_months": "36"})
cal_60 = utilities.unique_csv_row(calibration, {"horizon_months": "60"})
s7_events = int(s7[0]["events_adjusted"])
s6_figure_caption = (
    "**Supplementary Figure S6. Calibration of the adjusted NCR-versus-CR Cox model.** "
    f"Predicted and observed death risk at 36 and 60 months after the therapy-end landmark in the "
    f"{int(cal_36['n'])} covariate-complete development-set patients ({s7_events} deaths). (A, B) By four-category response "
    "at 36 months (A) and 60 months (B); each point is the mean predicted risk and the Kaplan–Meier observed "
    "risk in that category, and vertical bars show the 95% CI of the observed risk. (C, D) By decile of "
    "predicted risk at 36 months (C) and 60 months (D). The diagonal is the line of identity. Inset values are "
    "the calibration-in-the-large (CITL; a logit-scale intercept, negative values indicate overprediction), the "
    "observed-to-expected (O:E) ratio and the optimism-corrected calibration slope from 1,000 case-resampling "
    f"bootstrap samples ({int(cal_36['boot_valid'])} and {int(cal_60['boot_valid'])} valid at 36 and 60 months). "
    "CITL, O:E and grouped points are apparent development-set checks; only the reported slope is optimism-corrected. "
    "Apparent overall calibration was close to ideal at both horizons. At 36 months, overprediction in PR and "
    "underprediction in PD were imprecise subgroup deviations; both predictions lie within the observed-risk CIs. "
    "At 60 months, tail support was sparse and the Kaplan–Meier estimate was 100% in PR and SD, so no interval "
    "is shown for these groups. Predictions use the fitted model and baseline hazard; no model was refitted "
    "for this figure."
)
sfigs = [
    ("FigureS1_selection_regimen_power.png",
     s1_caption),
    ("FigureS2_hgsoc_four_state.png",
     f"**Supplementary Figure S2. Operational HGSOC sensitivity analysis.** Unadjusted hazard ratios (95% CI, log scale) for death with PR, SD and PD versus CR at the therapy-end landmark in TCGA-OV patients with grade G2–G4, FIGO III–IV disease (n={int(hgsoc_caption_row['n'])}; {int(hgsoc_caption_row['events'])} deaths; post hoc). Adjusted estimates and other time origins are given in Supplementary Table S2."),
    ("FigureS3_pancancer_dichotomy.png",
     "**Supplementary Figure S3. NCR versus CR across TCGA tumour types.** "
     "Unadjusted hazard ratios (95% CI, log scale) for death, NCR versus CR, from diagnosis, "
     "in all labelled patients with evaluable overall survival (OS) and in the subset who received "
     "first-line systemic therapy or radiotherapy. "
     f"Across the {len(pan)} labelled tumour types, estimates are shown where the analysed subset had "
     f"at least {int(PARAMETERS['pancancer_minimum_noncr'])} NCR patients, at least "
     f"{int(PARAMETERS['pancancer_minimum_cr'])} CR patients and at least "
     f"{int(PARAMETERS['pancancer_minimum_os_events'])} OS events; thresholds were applied separately "
     "to each subset. "
     f"{name_list(dich_missing)} therefore have no treated estimate because their treated subsets did "
     "not meet the same NCR, CR or event thresholds, although treated patients were present. "
     "n is the number of patients with evaluable OS in each subset. "
     "Rows are ordered by the all-patient hazard ratio, highest at the top. "
     f"No pooled estimate is shown; the {count_word(int(meta_end['k']))}-tumour pooled estimate at the "
     "end of first-line therapy "
     f"(HR {float(meta_end['HR']):.2f}, 95% CI {float(meta_end['HR_low']):.2f}\u2013"
     f"{float(meta_end['HR_high']):.2f}) is reported in the main text and Supplementary Data 5. "
     "CR, complete response; NCR, non-complete response; TCGA, The Cancer Genome Atlas."),
    ("FigureS4_pancancer_four_state.png",
     "**Supplementary Figure S4. Four-category response topology in ovarian, glioma and bladder cancer.** "
     "Unadjusted hazard ratios (95% CI, log scale) for overall survival (OS) with PR, SD and PD versus CR "
     "at diagnosis and at the end of first-line therapy. Ovarian cancer and lower-grade glioma (LGG) met both "
     "pre-specified four-state eligibility rules; bladder cancer met them only after restriction to patients who "
     "received first-line systemic therapy or radiotherapy, and the unrestricted bladder set, which includes "
     "surgical response labels, is shown for comparison. For bladder cancer and LGG, the therapy-end "
     "all-patient and treated panels are identical because the therapy-end landmark is defined only for patients "
     "with first-line non-surgical therapy. The ovarian panel uses TCGA-CDR labels for all labelled patients "
     f"(n={int(s4_ov_none['n'])} at diagnosis and {int(s4_ov_end['n'])} at the end of therapy) and is a secondary "
     "label-source comparison; the primary ovarian estimates are in Table 2 and Figure 2. n and deaths are shown "
     "for each panel. Each panel is a separate unadjusted Cox model with CR as the reference; no pooled estimate "
     "or test across tumour types is shown. CR, complete response; PR, partial response; SD, stable disease; "
     "PD, progressive disease; TCGA, The Cancer Genome Atlas; TCGA-CDR, TCGA Clinical Data Resource."),
    ("FigureS5_external_proliferation.png",
     f"**Supplementary Figure S5. External validation of the locked proliferation score.** NCR minus CR difference in the general proliferation score (SD units, 95% CI) in the {count_word(int(proliferation_caption_row['k']))} primary external cohorts and, separately, TCGA-OV. The REML random-effects pooled estimate includes only the primary external cohorts (pre-specified primary analysis). Because the score uses pretreatment primary-tumour expression and does not require landmark eligibility, the TCGA-OV row includes all 454 response-labelled patients rather than the 372-patient landmark subset."),
    ("FigureS6_calibration.png",
     s6_figure_caption),
]
def png_width_mm(path):
    """Return the printed width encoded in the PNG pHYs chunk (pixels per metre)."""
    data = path.read_bytes()
    at = data.find(b"pHYs")
    if at < 0:
        raise SystemExit(f"Missing pHYs physical-size chunk: {path}")
    return struct.unpack(">I", data[16:20])[0] / struct.unpack(">I", data[at + 4:at + 8])[0] * 1000


# Embed each supplementary figure at its native printed width so the
# document never rescales the final-size artwork or its text.
fig_md = [
    f"![]({utilities.relative_resource_path(RESULTS / 'figures' / 'supplementary' / filename, OUTPUT)})"
    f"{{width={png_width_mm(RESULTS / 'figures' / 'supplementary' / filename):.1f}mm}}\n\n{legend}"
    for filename, legend in sfigs
]
sup = sup.replace("{{FIGURES}}", "\n\n".join(fig_md))
# Apply journal P typography before the reference list is appended.
sup = journal_p(sup)
sup += f"\n\n## Supplementary References\n\n{srefs}\n"
(OUTPUT / f"{OUTPUT_PREFIX}_supplementary_appendix.md").write_text(sup)

# ---------- Cover letter and Word outputs ----------
(OUTPUT / "cover_letter.md").write_text((SOURCE / "cover_letter.md").read_text())
subprocess.run(
    ["node", str(ROOT / "scripts" / "22_generate_submission_docx.js")],
    check=True,
    cwd=ROOT,
)

all_keys = set(pub) | set(crossref)
print(f"main refs {len(order)}, supplement refs {len(sorder)}, verified keys never cited: {sorted(all_keys - set(order) - set(sorder))}")
for k, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + k)
if not all(v for k, v in checks.items() if "conservative" not in k):
    raise SystemExit("Journal submission limit check failed")
