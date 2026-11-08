#!/usr/bin/env python3
"""Generate and compile LaTeX versions of the configured submission files.

File: 23_build_submission_latex.py
Purpose: Convert final Markdown files to portable TeX and reviewer-ready PDF.
Author: Project authors
Created: 2026-10-15
Inputs: Configured manuscript Markdown, formal figures, and submission profile.
Outputs: Configured TeX and PDF files (manuscript, supplement and cover
    letter) under manuscript/submission/, plus a
    reviewer-convenience copy of the main manuscript with the formal figures
    appended (not for journal upload; ESMO Open requires separate figure files).
Runtime parameters: Pandoc, XeLaTeX, latexmk, and config/submission_profile.json.
"""
import importlib
import pathlib
import re
import shutil
import subprocess

utilities = importlib.import_module("28_submission_utilities")
ROOT = utilities.repository_root(__file__)
SOURCE = ROOT / "manuscript" / "submission"
OUTPUT = SOURCE
HEADER = ROOT / "manuscript" / "source" / "latex_header.tex"
PROFILE = utilities.read_json(ROOT / "config" / "submission_profile.json")
OUTPUT_PREFIX = PROFILE["output_prefix"]
LATEXMK = shutil.which("latexmk") or "latexmk"
LATEX_STYLE = PROFILE["latex_style"]
TEXT_MARGIN_MM = LATEX_STYLE["text_margin_mm"]
# Approved display settings are shared with the DOCX builder.
MAIN_TABLE_NOTE_FONT = LATEX_STYLE["main_table_note_font"]
S1D_FRACTIONS = LATEX_STYLE["supplementary_table_s1_d_fractions"]
# The figure-page side margin is shared with the DOCX builder so both formats
# place 190 mm artwork at identical native size.
FIGURE_SIDE_MARGIN_MM = PROFILE["document_style"]["figure_page_margin_mm"]
# Wide landscape table pages keep a narrow body margin; the running head and
# page number are moved closer to the body so they stay inside the paper
# (the default headsep/footskip would push them past the page edge).
WIDE_TABLE_GEOMETRY = r"\newgeometry{margin=%smm,headsep=%smm,footskip=%smm}" % (
    LATEX_STYLE["wide_table_margin_mm"], LATEX_STYLE["wide_table_headsep_mm"],
    LATEX_STYLE["wide_table_footskip_mm"])


def text_font(spec):
    """Return the LaTeX font-size command for a configured text block."""
    return r"\fontsize{%s}{%s}\selectfont" % (spec["size_pt"], spec["leading_pt"])


def table_font_spec(spec):
    """Return the LaTeX font-size and column-separation command for one table."""
    return text_font(spec) + r"\setlength{\tabcolsep}{%spt}" % spec["column_separation_pt"]


def table_font(name):
    """Return the LaTeX font-size and column-separation command for a table block."""
    return table_font_spec(LATEX_STYLE[name])
# Figure pages need only the side margins narrowed for 190 mm artwork; top and
# bottom margins match the text pages so the running head and page number keep
# their normal positions.
FIGURE_GEOMETRY = (r"\newgeometry{left=%smm,right=%smm,top=%smm,bottom=%smm}"
                   % (FIGURE_SIDE_MARGIN_MM, FIGURE_SIDE_MARGIN_MM, TEXT_MARGIN_MM, TEXT_MARGIN_MM))


def prepare_markdown(src, out):
    """Extract the H1 title and write the remaining Markdown for Pandoc."""
    text = src.read_text()
    lines = text.splitlines()
    if not lines or not lines[0].startswith("# "):
        raise SystemExit(f"Expected H1 title in {src}")
    title = lines[0][2:].strip()
    out.write_text("\n".join(lines[1:]).lstrip() + "\n")
    return title


def pandoc_tex(md, raw, title, reader="markdown+pipe_tables"):
    """Convert prepared Markdown to standalone TeX using the journal profile.

    A title of None omits the title block (used for the cover letter). The
    manuscript and supplement keep the default reader and an explicit title,
    so their Pandoc command is unchanged.
    """
    font = PROFILE["document_style"]["font_family"]
    mono = PROFILE["document_style"]["monospace_font_family"]
    title_args = ["-M", f"title={title}"] if title is not None else []
    cmd = [
        "pandoc", str(md), "--standalone", f"--from={reader}",
        "--to=latex", "--shift-heading-level-by=-1",
        "-V", "documentclass=article", "-V", f"fontsize={LATEX_STYLE['base_font_size_pt']}pt",
        "-V", "papersize=a4", "-V", f"geometry:margin={TEXT_MARGIN_MM}mm",
        "-V", f"mainfont={font}", "-V", f"sansfont={font}",
        "-V", f"monofont={mono}", *title_args,
        "--include-in-header", str(HEADER), "--resource-path", str(SOURCE),
        "-o", str(raw),
    ]
    subprocess.run(cmd, check=True)


def finish_cover(raw, out):
    """Format the cover letter as a plain letter without the shared running head."""
    t = common_tex(raw)
    # The approved letter flows continuously. Check its opening paragraph rather
    # than retaining an obsolete prose anchor.
    anchor = "We submit this Original Article for consideration"
    if t.count(anchor) != 1:
        raise SystemExit(f"Expected exactly one cover-letter paragraph at {anchor!r}")
    # Keep the shared font, spacing and page number, but drop the
    # shared running head and its rule, which do not belong on a letter.
    # Slightly tighter paragraph spacing keeps the compressed letter compact.
    letter_style = (
        r"\fancyhead[R]{}" + "\n"
        + r"\renewcommand{\headrulewidth}{0pt}" + "\n"
        + r"\geometry{margin=20mm,top=15mm,bottom=15mm}" + "\n"
        + r"\setstretch{1.0}" + "\n"
        + r"\setlength{\parskip}{0.2em}" + "\n"
    )
    if r"\begin{document}" not in t:
        raise SystemExit(f"No document body found in {raw}")
    out.write_text(t.replace(
        r"\begin{document}",
        letter_style + r"\begin{document}" + "\n"
        + r"\fontsize{10.5}{12.8}\selectfont",
        1,
    ))


def common_tex(raw):
    """Normalize superscripts, hyperlinks and DOI breaks for both documents."""
    t = raw.read_text().replace(r"\usepackage{bookmark}", r"\usepackage{hyperref}")
    sup = str.maketrans("⁻⁰¹²³⁴⁵⁶⁷⁸⁹", "-0123456789")
    t = re.sub(r"[⁻⁰¹²³⁴⁵⁶⁷⁸⁹]+", lambda m: r"\textsuperscript{" + m.group().translate(sup) + "}", t)
    # Allow a line break between "doi:" and a long unbreakable identifier.
    t = t.replace("doi:10.", r"doi:\allowbreak 10.")
    # Keep newly cited source paths selectable and verbatim, but permit normal
    # URL-style breaks at slashes and underscores instead of clipping them.
    for path in (
        "results/tables/ov_selection_regimen_power/pd_step_power_tcga.csv",
        "scripts/18_analyze_selection_regimen_power.R",
    ):
        encoded = path.replace("_", r"\_")
        t = t.replace(r"\texttt{" + encoded + "}", r"\nolinkurl{" + path + "}")
    # A PMID immediately followed by a citation superscript would otherwise
    # extract as one number ("PMID1931847634"); a thin space keeps the two
    # tokens distinct without changing the visible citation style.
    t = re.sub(r"(PMID\d+)(\\textsuperscript\{)", r"\1\\,\2", t)
    return t


def protect_reference_journals(t):
    """Keep each journal abbreviation on one line in the reference list.

    Pandoc leaves the spaces inside \\emph{...} breakable, which split
    "N Engl J Med" after the "J", and LaTeX could still hyphenate a protected
    name ("Stat Meth-ods Med Res"). Boxing each word stops hyphenation while
    nonbreaking spaces stop interword breaks; the spaces remain ordinary
    stretchable glue, so justification does not collapse them.
    """
    start = t.index(r"\section{References}\label{references}")
    end = t.index(r"\section{Figure legends}\label{figure-legends}")
    if end <= start:
        raise SystemExit("Reference section boundaries are out of order")
    names = {
        re.sub(r"\s+", " ", record["journal"]).strip()
        for record in utilities.read_json(
            ROOT / "manuscript" / "source" / "references_verified_pubmed.json"
        ).values()
        if record.get("journal")
    }
    # Journals supplied through Crossref overrides are absent from the PubMed
    # cache; list them so their names are protected as well.
    names.update({"Biometrika", "J Stat Softw", "J Am Stat Assoc",
                  "J R Stat Soc Series B Stat Methodol"})
    hits = []

    def keep(match):
        # Pandoc wraps long reference lines inside the emphasis span, so the
        # captured name may contain a newline and indentation.
        name = re.sub(r"\s+", " ", match.group(1)).strip()
        if name not in names:
            return match.group(0)
        hits.append(name)
        return (r"\emph{"
                + "~".join(r"\mbox{" + word + "}" for word in name.split())
                + "}")

    refs = re.sub(r"\\emph\{([^{}]*)\}", keep, t[start:end])
    if len(hits) < 40:
        raise SystemExit(f"Protected only {len(hits)} journal name spans in the reference list")
    return t[:start] + refs + t[end:]


def keep_paragraph(text):
    """Disallow breaks inside one paragraph, leaving surrounding blocks free."""
    return "{\\interlinepenalty=10000\n" + text.strip() + "\\par}\n"


def protect_reference_entries(t, supplementary=False):
    """Keep author, journal and DOI together for each entry, never the list."""
    heading = (r"\section{Supplementary References}\label{supplementary-references}"
               if supplementary else r"\section{References}\label{references}")
    start = t.index(heading) + len(heading)
    end = t.index(r"\end{document}" if supplementary
                  else r"\section{Figure legends}\label{figure-legends}", start)
    refs = t[start:end]
    if supplementary:
        pattern = r"^S\d+\.\s+[^\n]+(?:\n(?!\s*\n)[^\n]+)*"
        refs, count = re.subn(pattern, lambda m: keep_paragraph(m.group()), refs, flags=re.M)
    else:
        pattern = r"(\\item\s+)(.*?)(?=\\item\b|\\end\{enumerate\})"
        refs, count = re.subn(pattern, lambda m: m.group(1) + keep_paragraph(m.group(2)),
                             refs, flags=re.S)
    if not count:
        raise SystemExit("No reference entries found for keep-together pagination")
    return t[:start] + refs + t[end:]


def protect_main_figure3(t):
    """Move only Figure 3's complete legend to a fresh page."""
    pattern = r"(\\textbf\{Figure 3\.[^\n]*(?:\n(?!\s*\n)[^\n]+)*)"
    t, count = re.subn(pattern, lambda m: "\\clearpage\n" + keep_paragraph(m.group(1)), t)
    if count != 1:
        raise SystemExit(f"Expected one complete Figure 3 legend; found {count}")
    return t


def finish_main(raw, out):
    """Apply the upload manuscript's page breaks and landscape table layout."""
    t = common_tex(raw)
    t = protect_reference_journals(t)
    t = protect_reference_entries(t)
    t = protect_main_figure3(t)
    # Do not break a page after a hyphen: the Introduction revision left page 3
    # ending in "subse-" and page 4 opening with "quent survival". The penalty
    # only moves the affected line to the next page; line breaking is unchanged.
    t = t.replace(r"\begin{document}", "\\brokenpenalty=10000\n" + r"\begin{document}", 1)
    # Keep the author-contribution block on one page: the draft split
    # "Cheng Xu:" from that author's roles at the page break. \filbreak
    # moves the whole block only when it does not fit.
    ac_head = r"\section{Author contributions}\label{author-contributions}"
    if ac_head not in t:
        raise SystemExit("Author contributions heading not found")
    t = t.replace(ac_head, "\\filbreak\n" + ac_head, 1)
    # Fit the final data-sharing paragraph on the page holding its bullets,
    # so the statement does not spill a single line onto the next page. One
    # extra line of text height is invisible at this margin but avoids the
    # orphaned continuation line before the author-contribution block.
    ds_tail = "De-identified case-level identifiers"
    if ds_tail not in t:
        raise SystemExit("Data sharing tail not found")
    t = t.replace(ds_tail, "\\enlargethispage{\\baselineskip}\n" + ds_tail, 1)
    # Do not hyphenate "writing" in the long generative-AI section heading.
    t = re.sub(
        r"(Declaration of Generative AI and AI-assisted technologies in\s+the\s+)writing(\s+process\})",
        r"\1\\mbox{writing}\2",
        t,
    )
    # Retain the reference-list typography, but allow whole entries to move
    # across pages after additions. Body spacing is restored before legends;
    # neither the entire bibliography nor the legend list is kept together.
    t = t.replace(
        r"\section{References}\label{references}",
        r"\clearpage\section{References}\label{references}\small\emergencystretch=3em"
        r"\setstretch{1.02}",
    )
    t = t.replace(
        r"\section{Figure legends}\label{figure-legends}",
        r"\normalsize\clearpage\setstretch{1.12}\setlength{\parskip}{0.35em}"
        r"\section{Figure legends}\label{figure-legends}",
    )
    # Table legends start on their own page. Table 2 is not split across pages.
    t = t.replace(
        r"\section{Table legends}\label{table-legends}",
        r"\clearpage\section{Table legends}\label{table-legends}",
    )
    marker = r"\section{Tables}\label{tables}"
    if marker not in t:
        raise SystemExit("Main Tables marker not found")
    repl = (
        r"\clearpage" + WIDE_TABLE_GEOMETRY + r"\begin{landscape}\begingroup"
        "\n" + table_font("main_table_font") +
        "\n" + marker
    )
    t = t.replace(marker, repl, 1)
    cut = t.index(marker)
    pre, tables = t[:cut], t[cut:]
    table2 = r"\textbf{Table 2. Comparison of response codings"
    # Table 1: unequal, approved column fractions and a 9 pt note trial directly
    # below the body. Keep every note; final page fit needs visual acceptance.
    fractions = PROFILE["table_layout"]["main_table_fractions"]
    if (len(fractions) != 8 or abs(sum(fractions) - 1.0) > 5e-4
            or any(isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0
                   for value in fractions)):
        raise SystemExit("main_table_fractions must be 8 positive numbers summing to 1")
    pos = tables.index(table2)
    t1_block = tables[:pos]
    if t1_block.count(r"\real{0.1250}") != 8:
        raise SystemExit("Table 1 no longer has eight equal column fractions")
    for value in fractions:
        t1_block = t1_block.replace(r"\real{0.1250}", r"\real{%.5f}" % value, 1)
    note_lead = "Percentages are column percentages"
    if t1_block.count(note_lead) != 1:
        raise SystemExit("Table 1 notes paragraph not found exactly once")
    note_start = t1_block.index(note_lead)
    note_end = t1_block.index("\n\n", note_start)
    note_font = text_font(MAIN_TABLE_NOTE_FONT)
    t1_block = (t1_block[:note_start]
                + keep_paragraph(r"\noindent" + note_font + "{}" + t1_block[note_start:note_end])
                + t1_block[note_end:])
    tables = t1_block + tables[pos:]
    pos = tables.index(table2)
    tables = tables[:pos] + r"\clearpage" + "\n" + tables[pos:]
    pos = tables.index(table2)
    longtable = tables.index(r"\begin{longtable}", pos)
    tables = tables[:longtable] + table_font("main_comparison_table_font") + "\n" + tables[longtable:]
    # Table 2 has 13 narrow numeric columns. Equal fractions starve the hazard
    # ratio and ΔAIC columns at 8 pt, so assign content-driven widths.
    comp = PROFILE["table_layout"]["comparison_table_fractions"]
    if (len(comp) != 13 or abs(sum(comp) - 1.0) > 5e-4
            or any(isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0
                   for value in comp)):
        raise SystemExit("comparison_table_fractions must be 13 positive numbers summing to 1")
    lt_start = tables.index(r"\begin{longtable}", pos)
    lt_end = tables.index(r"\end{longtable}", lt_start)
    fractions_iter = iter(comp)
    segment, replaced = re.subn(
        r"\\real\{0\.\d+\}",
        lambda _: r"\real{%.5f}" % next(fractions_iter),
        tables[lt_start:lt_end])
    if replaced != 13:
        raise SystemExit("Table 2 no longer has 13 fractional columns")
    tables = tables[:lt_start] + segment + tables[lt_end:]
    # Pandoc emits every table cell as a bottom-aligned minipage. In a header
    # row where some headings wrap to two lines, one-line headings then sit on
    # the lower baseline; centre the header cells vertically instead.
    lt_start = tables.index(r"\begin{longtable}", pos)
    head_start = tables.index(r"\toprule\noalign{}", lt_start)
    head_end = tables.index(r"\midrule\noalign{}", head_start)
    head = tables[head_start:head_end]
    if head.count(r"\begin{minipage}[b]") != 13:
        raise SystemExit("Table 2 header no longer has 13 bottom-aligned minipages")
    head = head.replace(r"\begin{minipage}[b]", r"\begin{minipage}[c]")
    tables = tables[:head_start] + head + tables[head_end:]
    # Table 2 notes: the same intact 9 pt trial as Table 1.
    note2_lead = "Values are hazard ratios for death"
    if tables.count(note2_lead) != 1:
        raise SystemExit("Table 2 notes paragraph not found exactly once")
    note2_start = tables.index(note2_lead)
    note2_end = tables.index("\n\n", note2_start)
    tables = (tables[:note2_start]
              + keep_paragraph(r"\noindent" + note_font + "{}" + tables[note2_start:note2_end])
              + tables[note2_end:])
    tables = tables.replace("age+stage+residual", r"age+stage+\allowbreak residual")
    tables = tables.replace("CR/PR/SD/PD", r"CR/\allowbreak PR/\allowbreak SD/\allowbreak PD")
    tables = tables.replace(r"M1/M2/M3/M\_PD", r"M1/\allowbreak M2/\allowbreak M3/\allowbreak M\_PD")
    tables = re.sub(r"(?<=\d)/(?=\d)", r"/\\allowbreak ", tables)
    t = pre + tables
    t = t.replace(r"\end{document}", r"\endgroup\end{landscape}\restoregeometry" + "\n" + r"\end{document}")
    out.write_text(t)


def style_supplementary_tables(tab):
    """Set every supplementary table heading and caption to the body size.

    The author asked for the seven table headings and captions to match the
    11.0 pt body text rather than the widely different table body sizes, so
    all fourteen elements use 11.0 pt / 13.2 pt. The printed headings carry an
    optional short title so the contents entries and PDF bookmarks stay at
    the normal subsection size. Column widths are either proportional to the
    line width or set to the measured content width, so a larger table font
    changes wrapping and row height but not the 190 mm block limit. With
    1.0 pt column separation, the tested body maxima are 8.5 pt for both S2
    panels (9.0 pt wraps panel (b)'s Best BIC header or collides with the
    adjacent Setting column), 13.25 pt for S4 on content-driven columns,
    12.0 pt for S6 after the redundant k/n column was removed and the
    remaining headers reflowed, and 14.75 pt for S5 panels (b)-(e) in the
    per-panel layout described below.

    Table S1 was originally twelve equal columns, which left most of each
    numeric column empty and forced the text columns to wrap. The configured
    panel (a) fractions give the seven count columns only the width their
    headers need and assign the remainder to Platform, Optimal debulking and
    Median recorded OS time. With 1.0 pt separation the 10.0 pt body ends at
    173.0 mm, leaving 17 mm inside the block; the shared 11.0 pt heading and
    caption fit in the space above it on the portrait page.

    Table S3 carries six panels. The generated source forces a page break
    before panel (d); stage 23 adds one before panel (b) instead of before
    (c), so the caption and (a) share the first page, (b) and (c) the second,
    and (d)-(f) the third. Breaking before (b) removes the two-row spill that
    an earlier (c)-break layout left at the top of the following page.

    Table S4 had fifteen equal 17.9 mm columns, so the long headers wrapped
    and most numeric columns carried blank space. The configured fractions
    give the table 229.1 mm, of which 229.1 - 28 x 0.3528 = 219.2 mm is
    divided between the p-columns. Six headers are set on two lines ("OS" /
    "events"; "% first-line" / "systemic"; "% non-surgical" / "first-line";
    "% therapy end" / "known"; "% R0" / "in CR"; "% R0" / "in NCR"), while
    the other nine stay on one line and sit on the lower header line. At
    13.25 pt every body row stays on one line, the tightest text gap is
    1.60 mm, and the 228.9 mm table is centred. The heading and caption
    follow the shared 11.0 pt body size; the body leading remains 15.1 pt
    rather than 15.9 pt so the 22 rows stay on one page. A 13.5 pt body trial
    in the same harness ended at 198.3 mm (about 197.6 mm on the page) and
    left under 2.5 mm of headroom, so it is rejected; 13.0 pt ended at
    192.5 mm. The S5 base font is restored before the page break.

    Table S2 panel (a) was seven equal columns, so five short count columns
    each held about 38 mm and left wide blank gaps while Stage and Definition
    wrapped. The configured fractions apply to 277 - 12 x 0.3528 = 272.766 mm
    and give Stage 58.8 mm, Definition 148.2 mm and each count column 13.2 mm.
    At 8.5 pt all three rows stay on one line; 9.0 pt wraps the longest Stage
    label and is not used. Panel (b) originally remained at the 7.2 pt S2 size,
    whose fourteen equal columns forced four-line Setting wraps.

    Table S2 panel (b) had fourteen equal columns, so the repeated Setting
    labels wrapped onto four lines while the numeric strings were cramped.
    The fractions apply to 277 - 26 x 0.3528 = 267.827 mm and give Setting
    44 mm, Adjustment 16 mm, n 7 mm, Events 10 mm, each of the five
    hazard-ratio columns 25 mm, and the five test/model columns 12.3-14.5 mm.
    At 8.5 pt all headers and numeric cells stay on one line; only the longest
    Setting string and the residual adjustment wrap to two lines. A 9.0 pt
    trial either wrapped the BIC header or left no gap between Setting and
    Adjustment, so panel (b) matches the 8.5 pt panel (a). The 7.2 pt base is
    restored after panel (b), on the next page, so the following S3 heading
    keeps its previous size.

    Table S6 originally had ten equal columns, including a k / n column that
    repeated the same total in every row. Removing it leaves nine columns;
    the fractions apply to 277 - 9 x 0.882 = 269.06 mm and give Score 51.1
    mm, Adjustment 44.7 mm, Negative cohorts 22.2 mm, REML difference 45.8
    mm, REML P 16.9 mm, HKSJ 30.8 mm, HKSJ P 16.9 mm, I2 12.1 mm and
    prediction interval 28.6 mm. Score, Adjustment, REML P and HKSJ P stay
    on one line; the other five headers break onto two lines ("Negative" /
    "cohorts, n"; "REML difference" / "(95% CI)"; "HKSJ" / "95% CI"; "I2" /
    "(%)"; "95% prediction" / "interval"). The breaks are inserted into the
    generated LaTeX only, so the pipe-table source and DOCX wording are
    untouched. At 12.0 pt every body cell stays on one line, the smallest
    gap between a cell and the next column is 2.8 mm (REML P to HKSJ), and
    the widest value ends 5.5 mm inside the right rule. The fourteen-line
    caption leaves the table ending 161 mm down the 210 mm block, with 49 mm
    of headroom. The approved 11.5 pt fallback was not needed.

    Table S5 had eleven, six and seven equal columns in panels (a)-(c) and
    plain l-columns in (d)-(e). Panel (a) now gives each column the width its
    header and body need: at 10.4 pt all sixteen rows stay on one line and
    the table fills the 277 mm block, ending at 148.1 mm. Panels (b) and (c)
    share one page, so height rather than width binds. Panel (b)'s ΔAIC and
    ΔBIC headers and panel (c)'s four "months" headers are set on two lines
    in the generated LaTeX only, which allows 14.75 pt with content-driven
    widths of 227.1 and 222.1 mm and 2.8-3.2 mm text gaps; the panels end at
    147.4 and 196.3 mm. Panels (d) and (e) convert their l-columns to
    p-columns of 179.1 and 137.4 mm at the same size and end at 72.7 and
    166.0 mm. A 16.0 pt trial pushed panel (c) onto a fourth page, 15.0 pt
    ended at 199.8 mm, 0.2 mm from the block edge, and one-line headers at
    14.0 pt visually merged; 14.75 pt is the largest setting that keeps
    three pages with 3.7 mm of headroom. The pre-S5 base font is restored
    before the S6 page break.

    Table S7 is a new exploratory table: panel (a) has ten columns (partition,
    contrast, n, deaths, adjusted and unadjusted hazard ratios with P and q
    values) and panel (b) has five columns (estimand, model, hazard ratio and
    the common-outcome and uncorrected E-values). The configured fractions
    distribute the 277 mm block so the contrast and hazard-ratio columns carry
    the long strings while the numeric P and q columns keep their values on one
    line at 8.5 pt; four headers are set on two lines in the generated LaTeX
    only.
    """
    caption_font = text_font(LATEX_STYLE["supplementary_table_caption_font"])
    pattern = re.compile(r"(\\textbf\{Supplementary Table S\d+\.(?:(?!\n\n).)*)\n\n", re.S)
    tab, captions = pattern.subn(
        lambda match: "{" + caption_font + "\n" + match.group(1) + "\n\\par}\n\n",
        tab,
    )
    if captions != 7:
        raise SystemExit(f"Expected seven supplementary table captions; found {captions}")

    s1_start = tab.index(r"\textbf{Supplementary Table S1.")
    s1_stop = tab.index(r"\clearpage", s1_start)
    s1 = tab[s1_start:s1_stop]
    if s1.count(r"\end{longtable}") != 4 or s1.count(r"\textbf{(a)}") != 1:
        raise SystemExit("Table S1 layout markers are not the expected four-part table")

    fractions = LATEX_STYLE["supplementary_table_s1_a_fractions"]
    if (len(fractions) != 12
            or abs(sum(fractions) - 1.0) > 5e-4
            or any(isinstance(value, bool) or not isinstance(value, (int, float))
                   or value <= 0 for value in fractions)):
        raise SystemExit("Table S1 panel (a) fractions must be 12 positive numbers summing to 1")
    a_start = s1.index(r"\textbf{(a)}")
    a_stop = s1.index(r"\end{longtable}", a_start)
    a_block = s1[a_start:a_stop]
    if a_block.count(r"\real{0.0833}") != 12:
        raise SystemExit("Table S1 panel (a) no longer has 12 equal column fractions")
    for value in fractions:
        a_block = a_block.replace(r"\real{0.0833}", r"\real{%.5f}" % value, 1)
    s1 = s1[:a_start] + a_block + s1[a_stop:]

    s1 = s1.replace(
        r"\textbf{(a)}",
        table_font("supplementary_table_s1_font") + "\n" + r"\textbf{(a)}",
        1,
    )
    # S1d used six natural-width l-columns (only about 88 mm in total).
    # Use the full 190 mm portrait block, with independent count/estimate
    # columns and consistently right-aligned numbers; no text or values change.
    d_start = s1.index(r"\textbf{(d)}")
    d_stop = s1.index(r"\end{longtable}", d_start)
    d_block = s1[d_start:d_stop]
    natural = r"\begin{longtable}[]{@{}llllll@{}}"
    if d_block.count(natural) != 1:
        raise SystemExit("Table S1d no longer has six natural-width columns")
    columns = [
        r"  >{\%s\arraybackslash}p{(\linewidth - 10\tabcolsep) * \real{%.5f}}"
        % ("raggedright" if index == 0 else "raggedleft", fraction)
        for index, fraction in enumerate(S1D_FRACTIONS)
    ]
    d_block = d_block.replace(natural, "\\begin{longtable}[]{@{}\n" + "\n".join(columns) + "@{}}", 1)
    s1 = s1[:d_start] + d_block + s1[d_stop:]
    s1 = s1.rstrip("\n") + "\n" + table_font("supplementary_table_font") + "\n\n"
    styled = tab[:s1_start] + s1 + tab[s1_stop:]

    # Panel (d) is short and would otherwise sit alone on the next page after
    # an orphaned label. Start panels (c) and (d) together on a fresh page.
    s1_full_start = styled.index(r"\textbf{Supplementary Table S1.")
    s1_full_stop = styled.index(r"\subsection{Table S2}", s1_full_start)
    s1_full = styled[s1_full_start:s1_full_stop]
    if s1_full.count(r"\textbf{(c)}") != 1:
        raise SystemExit("Table S1 panel (c) marker is not unique")
    s1_full = s1_full.replace(r"\textbf{(c)}", "\\clearpage\n" + r"\textbf{(c)}", 1)
    styled = styled[:s1_full_start] + s1_full + styled[s1_full_stop:]

    fonts = LATEX_STYLE["supplementary_table_fonts"]
    expected = ("S2", "S3", "S4", "S5", "S6", "S7")
    if set(fonts) != set(expected):
        raise SystemExit("supplementary_table_fonts must define exactly S2-S7")
    for table in expected:
        marker = r"\textbf{Supplementary Table %s." % table
        start = styled.index(marker)
        caption_end = styled.index("\\par}\n\n", start) + len("\\par}\n\n")
        styled = (styled[:caption_end] + table_font_spec(fonts[table]) + "\n"
                  + styled[caption_end:])

    s2_start = styled.index(r"\subsection{Table S2}")
    s2_stop = styled.index(r"\subsection{Table S3}")
    s2 = styled[s2_start:s2_stop]
    s2a_fractions = LATEX_STYLE["supplementary_table_s2_a_fractions"]
    if (len(s2a_fractions) != 7
            or abs(sum(s2a_fractions) - 1.0) > 5e-4
            or any(isinstance(value, bool) or not isinstance(value, (int, float))
                   or value <= 0 for value in s2a_fractions)):
        raise SystemExit("Table S2 panel (a) fractions must be 7 positive numbers summing to 1")
    a_start = s2.index(r"\textbf{(a)}")
    a_stop = s2.index(r"\end{longtable}", a_start)
    a_block = s2[a_start:a_stop]
    if a_block.count(r"\real{0.1429}") != 7:
        raise SystemExit("Table S2 panel (a) no longer has 7 equal column fractions")
    for value in s2a_fractions:
        a_block = a_block.replace(r"\real{0.1429}", r"\real{%.5f}" % value, 1)
    s2 = s2[:a_start] + a_block + s2[a_stop:]
    base_font = table_font_spec(fonts["S2"])
    a_font_marker = base_font + "\n" + r"\textbf{(a)}"
    if s2.count(a_font_marker) != 1:
        raise SystemExit("Table S2 panel (a) font marker is not unique")
    s2 = s2.replace(a_font_marker,
                    table_font("supplementary_table_s2_a_font") + "\n" + r"\textbf{(a)}",
                    1)
    s2b_fractions = LATEX_STYLE["supplementary_table_s2_b_fractions"]
    if (len(s2b_fractions) != 14
            or abs(sum(s2b_fractions) - 1.0) > 5e-4
            or any(isinstance(value, bool) or not isinstance(value, (int, float))
                   or value <= 0 for value in s2b_fractions)):
        raise SystemExit("Table S2 panel (b) fractions must be 14 positive numbers summing to 1")
    b_marker = "\\end{longtable}\n\n\\textbf{(b)}"
    if s2.count(b_marker) != 1:
        raise SystemExit("Table S2 panel (b) marker is not unique")
    s2 = s2.replace(b_marker,
                    "\\end{longtable}\n\n"
                    + table_font("supplementary_table_s2_b_font") + "\n\n\\textbf{(b)}",
                    1)
    b_start = s2.index(r"\textbf{(b)}")
    b_stop = s2.index(r"\end{longtable}", b_start)
    b_block = s2[b_start:b_stop]
    if b_block.count(r"\real{0.0714}") != 14:
        raise SystemExit("Table S2 panel (b) no longer has 14 equal column fractions")
    for value in s2b_fractions:
        b_block = b_block.replace(r"\real{0.0714}", r"\real{%.5f}" % value, 1)
    s2 = s2[:b_start] + b_block + s2[b_stop:]
    # The S3 heading inherits the font left after S2; restore the S2 base size
    # so enlarging panel (b) does not move the following table pages.
    s2 = s2.rstrip("\n") + "\n" + base_font + "\n\n"
    styled = styled[:s2_start] + s2 + styled[s2_stop:]

    s3_start = styled.index(r"\subsection{Table S3}")
    s3_stop = styled.index(r"\subsection{Table S4}")
    s3 = styled[s3_start:s3_stop]
    s3_columns = {"a": (10, "0.1000"), "b": (11, "0.0909"), "c": (12, "0.0833"),
                  "d": (8, "0.1250"), "e": (7, "0.1429")}
    missing = [f"supplementary_table_s3_{panel}_fractions" for panel in s3_columns
               if f"supplementary_table_s3_{panel}_fractions" not in LATEX_STYLE]
    if missing:
        raise SystemExit("Missing Table S3 column fractions: " + ", ".join(missing))
    s3_fractions = {panel: LATEX_STYLE[f"supplementary_table_s3_{panel}_fractions"]
                    for panel in s3_columns}
    if set(s3_fractions) != set(s3_columns):
        raise SystemExit("supplementary_table_s3_fractions must define exactly a-e")
    for panel, (n_columns, template) in s3_columns.items():
        fractions = s3_fractions[panel]
        if (len(fractions) != n_columns
                or abs(sum(fractions) - 1.0) > 5e-4
                or any(isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0
                       for value in fractions)):
            raise SystemExit(f"Table S3 panel ({panel}) fractions must be {n_columns} positive numbers summing to 1")
        marker = r"\textbf{(%s)}" % panel
        start = s3.index(marker)
        stop = s3.index(r"\end{longtable}", start)
        block = s3[start:stop]
        expected = r"\real{%s}" % template
        if block.count(expected) != n_columns:
            raise SystemExit(f"Table S3 panel ({panel}) no longer has {n_columns} equal column fractions")
        for value in fractions:
            block = block.replace(expected, r"\real{%.5f}" % value, 1)
        s3 = s3[:start] + block + s3[stop:]
    if s3.count("\\clearpage\n\n\\textbf{(d)}") != 1:
        raise SystemExit("Table S3 has an unexpected page-break layout")
    if s3.count(r"\textbf{(b)}") != 1:
        raise SystemExit("Table S3 panel (b) marker is not unique")
    s3 = s3.replace(r"\textbf{(b)}", "\\clearpage\n" + r"\textbf{(b)}", 1)
    styled = styled[:s3_start] + s3 + styled[s3_stop:]

    s4_start = styled.index(r"\subsection{Table S4}")
    s4_stop = styled.index(r"\subsection{Table S5}")
    s4 = styled[s4_start:s4_stop]
    s4_fractions = LATEX_STYLE["supplementary_table_s4_fractions"]
    if (not isinstance(s4_fractions, list) or len(s4_fractions) != 15
            or abs(sum(s4_fractions) - 1.0) > 5e-4
            or any(isinstance(value, bool) or not isinstance(value, (int, float))
                   or value <= 0 for value in s4_fractions)):
        raise SystemExit("Table S4 fractions must be 15 positive numbers summing to 1")
    s4_width = LATEX_STYLE.get("supplementary_table_s4_width_mm")
    if (isinstance(s4_width, bool) or not isinstance(s4_width, (int, float))
            or s4_width <= 0 or s4_width > 277):
        raise SystemExit(
            "supplementary_table_s4_width_mm must be a positive width "
            "within the 277 mm landscape block")
    if s4.count(r"\real{0.0667}") != 15:
        raise SystemExit("Table S4 no longer has 15 equal column fractions")
    for value in s4_fractions:
        s4 = s4.replace(r"\real{0.0667}", r"\real{%.5f}" % value, 1)
    if s4.count(r"(\linewidth - ") != 15:
        raise SystemExit("Table S4 does not have 15 linewidth column widths")
    s4 = s4.replace(r"(\linewidth - ", "(%.1fmm - " % s4_width)
    # Break the six crowded headers in the generated LaTeX only: the Markdown
    # pipe table also feeds the DOCX build, which must stay unchanged.
    s4_header_breaks = (
        ("OS events", "OS\\newline events"),
        (r"\% first-line systemic", r"\% first-line\newline systemic"),
        (r"\% non-surgical first-line", r"\% non-surgical\newline first-line"),
        (r"\% therapy end known", r"\% therapy end\newline known"),
        (r"\% R0 in CR", r"\% R0\newline in CR"),
        (r"\% R0 in NCR", r"\% R0\newline in NCR"),
    )
    # Apply header breaks to the header row only: the caption now names several
    # of these columns, so a whole-block count would no longer be unique.
    header_start = s4.index(r"\toprule")
    header_stop = s4.index(r"\midrule", header_start)
    header_row = s4[header_start:header_stop]
    for header, broken in s4_header_breaks:
        if header_row.count(header) != 1:
            raise SystemExit(f"Table S4 header not found exactly once: {header}")
        header_row = header_row.replace(header, broken, 1)
    s4 = s4[:header_start] + header_row + s4[header_stop:]

    tail_start = s4.rindex(r"\end{longtable}")
    tail = s4[tail_start:]
    page_break = "\n\n" + r"\clearpage"
    if tail.count(page_break) != 1:
        raise SystemExit("Table S4 does not end with exactly one page break")
    tail = tail.replace(
        page_break,
        "\n" + table_font_spec(fonts["S5"]) + page_break,
        1,
    )
    s4 = s4[:tail_start] + tail
    styled = styled[:s4_start] + s4 + styled[s4_stop:]

    s6_start = styled.index(r"\subsection{Table S6}")
    s6_stop = styled.index(r"\end{longtable}", s6_start)
    s6 = styled[s6_start:s6_stop]
    s6_fractions = LATEX_STYLE["supplementary_table_s6_fractions"]
    if (len(s6_fractions) != 9
            or abs(sum(s6_fractions) - 1.0) > 5e-4
            or any(isinstance(value, bool) or not isinstance(value, (int, float))
                   or value <= 0 for value in s6_fractions)):
        raise SystemExit("Table S6 fractions must be 9 positive numbers summing to 1")
    if s6.count(r"\real{0.1111}") != 9:
        raise SystemExit("Table S6 no longer has 9 equal column fractions")
    for value in s6_fractions:
        s6 = s6.replace(r"\real{0.1111}", r"\real{%.5f}" % value, 1)
    # Break the wide headers in the generated LaTeX only: the Markdown
    # pipe table also feeds the DOCX build, which must stay unchanged.
    s6_header_breaks = (
        ("Negative cohorts, n", "Negative\\newline cohorts, n"),
        ("REML difference (95\\% CI)", "REML difference\\newline (95\\% CI)"),
        ("HKSJ 95\\% CI", "HKSJ\\newline 95\\% CI"),
        ("I\\textsuperscript{2} (\\%)", "I\\textsuperscript{2}\\newline (\\%)"),
        ("95\\% prediction interval", "95\\% prediction\\newline interval"),
    )
    for header, broken in s6_header_breaks:
        if s6.count(header) != 1:
            raise SystemExit(f"Table S6 header not found exactly once: {header}")
        s6 = s6.replace(header, broken, 1)
    styled = styled[:s6_start] + s6 + styled[s6_stop:]

    s7_start = styled.index(r"\subsection{Table S7}")
    # S7 is the last supplementary table, so its block runs to the end of the
    # table segment; the figures section is split off before this function runs.
    s7_stop = len(styled)
    s7 = styled[s7_start:s7_stop]
    s7_panels = (("a", 10, "0.1000", "supplementary_table_s7_a_fractions"),
                 ("b", 5, "0.2000", "supplementary_table_s7_b_fractions"))
    for label, columns, template, key in s7_panels:
        fractions = LATEX_STYLE[key]
        if (not isinstance(fractions, list) or len(fractions) != columns
                or abs(sum(fractions) - 1.0) > 5e-4
                or any(isinstance(value, bool) or not isinstance(value, (int, float))
                       or value <= 0 for value in fractions)):
            raise SystemExit(
                "Table S7 panel (%s) fractions must be %d positive numbers summing to 1"
                % (label, columns))
        start = s7.index(r"\textbf{(%s)}" % label)
        stop = s7.index(r"\end{longtable}", start)
        panel = s7[start:stop]
        equal = r"\real{%s}" % template
        if panel.count(equal) != columns:
            raise SystemExit(
                "Table S7 panel (%s) no longer has %d equal column fractions"
                % (label, columns))
        for value in fractions:
            panel = panel.replace(equal, r"\real{%.5f}" % value, 1)
        s7 = s7[:start] + panel + s7[stop:]
    # Break the wide headers in the generated LaTeX only: the Markdown pipe
    # tables also feed the DOCX build, which must stay unchanged.
    s7_header_breaks = (
        ("Adjusted HR (95\\% CI)", "Adjusted HR\\newline (95\\% CI)"),
        ("Unadjusted HR (95\\% CI)", "Unadjusted HR\\newline (95\\% CI)"),
        ("Common-outcome E-value (point; CI bound)",
         "Common-outcome E-value\\newline (point; CI bound)"),
        ("Uncorrected E-value (point; CI bound)",
         "Uncorrected E-value\\newline (point; CI bound)"),
    )
    for header, broken in s7_header_breaks:
        if s7.count(header) != 1:
            raise SystemExit(f"Table S7 header not found exactly once: {header}")
        s7 = s7.replace(header, broken, 1)
    s7 = s7.rstrip("\n") + "\n" + table_font("supplementary_table_font") + "\n\n"
    styled = styled[:s7_start] + s7 + styled[s7_stop:]

    s5_start = styled.index(r"\subsection{Table S5}")
    s5_stop = styled.index(r"\subsection{Table S6}")
    s5 = styled[s5_start:s5_stop]
    s5_columns = {"a": 11, "b": 6, "c": 7, "d": 6, "e": 6}
    s5_fonts = LATEX_STYLE["supplementary_table_s5_fonts"]
    if set(s5_fonts) != set(s5_columns):
        raise SystemExit("supplementary_table_s5_fonts must define exactly panels a-e")
    s5_widths = {}
    for letter in "bcde":
        width = LATEX_STYLE.get("supplementary_table_s5_%s_width_mm" % letter)
        if (isinstance(width, bool) or not isinstance(width, (int, float))
                or width <= 0 or width > 277):
            raise SystemExit(
                "supplementary_table_s5_%s_width_mm must be a positive width "
                "within the 277 mm landscape block" % letter)
        s5_widths[letter] = width
    s5_header_breaks = (
        ("b", r"ΔAIC M1/M2/M3/M\_PD", "ΔAIC\\newline M1/M2/M3/M\\_PD"),
        ("b", r"ΔBIC M1/M2/M3/M\_PD", "ΔBIC\\newline M1/M2/M3/M\\_PD"),
        ("c", "Horizon, months", "Horizon,\\newline months"),
        ("c", r"RMST CR, months", "RMST CR,\\newline months"),
        ("c", r"RMST NCR, months", "RMST NCR,\\newline months"),
        ("c", r"NCR − CR (95\% CI), months",
         "NCR − CR (95\\% CI),\\newline months"),
    )
    equal_fractions = {"a": "0.0909", "b": "0.1667", "c": "0.1429"}
    for letter in "abcde":
        fractions = LATEX_STYLE.get("supplementary_table_s5_%s_fractions" % letter)
        expected_columns = s5_columns[letter]
        if (not isinstance(fractions, list) or len(fractions) != expected_columns
                or abs(sum(fractions) - 1.0) > 5e-4
                or any(isinstance(value, bool) or not isinstance(value, (int, float))
                       or value <= 0 for value in fractions)):
            raise SystemExit(
                "Table S5 panel (%s) fractions must be %d positive numbers summing to 1"
                % (letter, expected_columns))
        start = s5.index(r"\textbf{(%s)}" % letter)
        stop = s5.index(r"\end{longtable}", start)
        panel = s5[start:stop]
        panel = panel.replace(
            r"\textbf{(%s)}" % letter,
            table_font_spec(s5_fonts[letter]) + "\n" + r"\textbf{(%s)}" % letter,
            1,
        )
        for panel_letter, header, broken in s5_header_breaks:
            if panel_letter != letter:
                continue
            if panel.count(header) != 1:
                raise SystemExit(
                    "Table S5 panel (%s) header not found exactly once: %s"
                    % (letter, header))
            panel = panel.replace(header, broken, 1)
        if letter in equal_fractions:
            equal = equal_fractions[letter]
            if panel.count(r"\real{%s}" % equal) != expected_columns:
                raise SystemExit(
                    "Table S5 panel (%s) no longer has %d equal column fractions"
                    % (letter, expected_columns))
            for value in fractions:
                panel = panel.replace(r"\real{%s}" % equal, r"\real{%.5f}" % value, 1)
            if letter in s5_widths:
                if panel.count(r"(\linewidth - ") != expected_columns:
                    raise SystemExit(
                        "Table S5 panel (%s) does not have %d linewidth column widths"
                        % (letter, expected_columns))
                panel = panel.replace(
                    r"(\linewidth - ", "(%.1fmm - " % s5_widths[letter])
        else:
            if panel.count(r"\begin{longtable}[]{@{}llllll@{}}") != 1:
                raise SystemExit(
                    "Table S5 panel (%s) no longer has six plain l-columns" % letter)
            columns = [
                r"  >{\raggedright\arraybackslash}p{(%.1fmm - 10\tabcolsep) * \real{%.5f}}"
                % (s5_widths[letter], value)
                for value in fractions
            ]
            panel = panel.replace(
                r"\begin{longtable}[]{@{}llllll@{}}",
                "\\begin{longtable}[]{@{}\n" + "\n".join(columns) + "@{}}",
                1,
            )
        s5 = s5[:start] + panel + s5[stop:]
    tail_start = s5.rindex(r"\end{longtable}")
    tail = s5[tail_start:]
    if tail.count(r"\clearpage") != 1:
        raise SystemExit("Table S5 does not end with exactly one page break")
    tail = tail.replace(
        r"\clearpage",
        table_font_spec(fonts["S5"]) + "\n" + r"\clearpage",
        1,
    )
    s5 = s5[:tail_start] + tail
    return styled[:s5_start] + s5 + styled[s5_stop:]


def centre_table_headers(tab):
    """Centre every supplementary table header cell vertically in its row.

    Pandoc wraps each header cell in a bottom-aligned minipage, so a
    single-line header sits level with the second line of its two-line
    neighbours. Switching the header cells to centred minipages keeps the row
    height (height plus depth is unchanged) while centring the short headers.
    Body cells are plain p-columns and contain no minipages, so the rewrite is
    confined to the text between each table's top and header rules.
    """
    bottom = r"\begin{minipage}[b]{\linewidth}\raggedright"
    centre = r"\begin{minipage}[c]{\linewidth}\raggedright"
    pieces = []
    start = 0
    converted = 0
    while True:
        try:
            top = tab.index(r"\toprule", start)
        except ValueError:
            break
        mid = tab.index(r"\midrule", top)
        header = tab[top:mid]
        found = header.count(bottom)
        if found:
            converted += found
        pieces.append(tab[start:top])
        pieces.append(header.replace(bottom, centre))
        start = mid
    pieces.append(tab[start:])
    rewritten = "".join(pieces)
    if converted == 0:
        raise SystemExit("No supplementary table header cells were centred")
    if converted != tab.count(bottom):
        raise SystemExit("Some bottom-aligned minipages sit outside table headers")
    return rewritten


def add_table_continuations(tab):
    """Label explicit and automatic continuation pages, preserving panel headers."""
    heading_font = text_font(LATEX_STYLE["supplementary_table_heading_font"])

    def table_block(match):
        block, table = match.group(1), match.group(2)
        if table not in {"S1", "S3", "S5"}:
            return block

        def page_label(marker):
            # Replace, rather than add a line above, the first panel letter.
            # S5's previously tight pages therefore gain no extra heading row.
            return (marker.group(1) + "{" + heading_font
                    + r"\textbf{Table %s (continued)\quad (%s)}\par}" % (table, marker.group(2)))

        block = re.sub(r"(\\clearpage(?:(?!\\textbf|\\subsection).)*?)\\textbf\{\(([a-f])\)\}",
                       page_label, block, flags=re.S)

        def repeat_header(longtable):
            segment = longtable.group()
            labels = re.findall(r"\\textbf\{(?:Table S\d+ \(continued\)\\quad )?\(([a-f])\)\}",
                                block[:longtable.start()])
            if not labels:
                raise SystemExit(f"No panel letter before {table} longtable")
            top, end = segment.index(r"\toprule"), segment.index(r"\endhead")
            header = segment[top:end]
            columns = header.count("&") + 1
            title = (r"\multicolumn{%d}{@{}l@{}}{%s\textbf{Table %s (continued)\quad (%s)}} \\" + "\n") % (
                columns, heading_font, table, labels[-1])
            # First-page header stays unchanged; only continuation heads gain
            # the total number, while repeating the complete original columns.
            return (segment[:top] + header + "\\endfirsthead\n"
                    + title + header + segment[end:])

        return re.sub(r"\\begin\{longtable\}.*?\\end\{longtable\}", repeat_header, block, flags=re.S)

    return re.sub(r"(\\subsection\{Table (S[1-7])\}.*?)(?=\\subsection\{Table S[1-7]\}|\Z)",
                  table_block, tab, flags=re.S)


def style_table_headings(tab):
    """Set every supplementary table heading at the shared body size.

    The optional short title keeps the contents entries and PDF bookmarks at
    the normal subsection size while the printed headings are set at 11.0 pt.
    This runs after the S1/S2 page-geometry insertion, which locates the
    plain ``\\subsection{Table S2}`` marker.
    """
    heading_font = text_font(LATEX_STYLE["supplementary_table_heading_font"])
    pattern = re.compile(r"\\subsection\{Table S([1-7])\}")
    tab, headings = pattern.subn(
        lambda match: "\\subsection[Table S%s]{%s Table S%s}"
        % (match.group(1), heading_font, match.group(1)),
        tab,
    )
    if headings != 7:
        raise SystemExit(f"Expected seven supplementary table headings; found {headings}")
    return tab


def protect_s1_figure(t):
    """Keep S1 heading, native 190 mm artwork and full caption in one box.

    The source caption is shortened separately in stage 21. Fail visibly at
    compilation if it still cannot fit; never silently shrink the artwork.
    """
    start = t.index(r"\section{Supplementary Figures}\label{supplementary-figures}")
    caption = t.index(r"\textbf{Supplementary Figure S1.", start)
    end = t.index(r"\clearpage", caption)
    block = t[start:end].rstrip()
    # Width is fixed; remove Pandoc's fallback height cap for this artwork.
    block, images = re.subn(
        r"(\\includegraphics\[width=190(?:\.0)?mm),height=\\textheight,keepaspectratio(\])",
        r"\1\2", block)
    if images != 1:
        raise SystemExit("Figure S1 must have one native-width 190 mm image")
    # Use the approved 9.5 pt supplementary caption setting, without changing
    # the native artwork size or any labels inside it.
    block = block.replace(r"\textbf{Supplementary Figure S1.",
                          text_font(LATEX_STYLE["supplementary_figure_s1_caption_font"])
                          + r"\textbf{Supplementary Figure S1.", 1)
    opening = (
        "\\begingroup\n\\newsavebox{\\soneblock}\n"
        "\\begin{lrbox}{\\soneblock}\\begin{minipage}{\\linewidth}\n"
        "\\setstretch{1.0}\\setlength{\\parskip}{0.35em}\n"
    )
    closing = (
        "\n\\par\\end{minipage}\\end{lrbox}\n"
        "\\typeout{S1 block height: \\the\\dimexpr\\ht\\soneblock+\\dp\\soneblock\\relax; available: \\the\\textheight}\n"
        "\\ifdim\\dimexpr\\ht\\soneblock+\\dp\\soneblock\\relax>\\textheight\n"
        "\\PackageError{esmo-layout}{Figure S1 plus caption exceeds one page}"
        "{Shorten the source caption or revise approved spacing; do not scale the 190 mm artwork.}\n"
        "\\fi\n\\noindent\\usebox{\\soneblock}\\par\\endgroup\n\n"
    )
    return t[:start] + opening + block + closing + t[end:]


def finish_si(raw, out):
    """Lay out supplementary tables and native-size figures on separate pages."""
    t = common_tex(raw).replace("{figures/", "{../figures/")
    t = protect_reference_entries(t, supplementary=True)
    # Data 4 and Data 5 filenames are unbreakable and wider than the remaining
    # measure when set inline with their bold labels. Give each label and
    # filename its own display line; font size and page geometry are unchanged.
    for label, filename in (
        ("Supplementary Data 4", r"SupplementaryData4\_TCGA\_OV\_risk\_set\_audit.csv"),
        ("Supplementary Data 5", r"SupplementaryData5\_reporting\_bundle.zip"),
    ):
        pattern = (re.escape(r"\textbf{" + label + "}")
                   + r"\s*\(\\texttt\{" + re.escape(filename) + r"\}(?P<rest>[^)]*)\)\.?[ ]?")
        if len(re.findall(pattern, t)) != 1:
            raise SystemExit(f"{label} filename display form is not unique")
        t = re.sub(
            pattern,
            lambda m, label=label, filename=filename: (
                r"\textbf{" + label + r"}\\" + "\n"
                + r"(\texttt{" + filename + r"}" + m.group("rest") + r").\\" + "\n"
            ),
            t,
            count=1,
        )
    toc_marker = r"\{\{SUPPLEMENTARY\_TOC\}\}"
    if t.count(toc_marker) != 1:
        raise ValueError("Supplementary contents marker must occur exactly once")
    # Keep the title page free of intra-word breaks (affiliations, ORCID and
    # data-file names); the group closes before the generated contents. The
    # widow and club penalties sit outside that group so they persist across the
    # whole appendix and avoid single-line fragments at page boundaries.
    # Explicit-hyphen breakpoints are enabled in the title paragraph only when
    # the title contains a hyphen; emergency stretch absorbs any remaining slack.
    t = re.sub(
        r"(\\begin\{document\}\s*\\maketitle)",
        r"\1\n\\widowpenalty=10000\\clubpenalty=10000"
        r"\n\\begingroup\\hyphenpenalty=10000\\exhyphenpenalty=10000"
        r"\\emergencystretch=3em",
        t,
        count=1,
    )
    title_start = t.find(r"\maketitle")
    title_open = t.find(r"\textbf{", title_start)
    title_close = t.find("}", title_open)
    if title_start < 0 or title_open < 0 or title_close < 0:
        raise SystemExit("Appendix title paragraph not found")
    title_text = t[title_open:title_close]
    # The current title has no hyphen; when one is present, expose it as a
    # breakpoint so a long title can wrap without overrunning the margin.
    if "-" in title_text and r"-\allowbreak{}" not in title_text:
        t = (t[:title_open] + title_text.replace("-", r"-\allowbreak{}")
             + t[title_close:])
    t = t.replace(toc_marker, r"\endgroup\clearpage\setcounter{tocdepth}{2}\tableofcontents\clearpage", 1)
    t = t.replace(r"\{\{PAGE\_BREAK\}\}", r"\clearpage")
    start = r"\section{Supplementary Tables}\label{supplementary-tables}"
    stop = r"\section{Supplementary Figures}\label{supplementary-figures}"
    if start not in t or stop not in t:
        raise SystemExit("SI table/figure marker not found")
    # S1 is narrow enough to keep its natural reading orientation; the remaining
    # five tables stay on rotated pages. Both branches share the same 10 mm
    # table geometry, so only orientation and the S1 width allocation change.
    orientation = LATEX_STYLE["supplementary_table_s1_orientation"]
    if orientation not in {"portrait", "landscape"}:
        raise SystemExit("supplementary_table_s1_orientation must be portrait or landscape")
    # A portrait S1 keeps the 190 mm table width but the text-page top/bottom
    # margins, so its running head and page number align with the prose pages.
    s1_opening = (r"\clearpage" + FIGURE_GEOMETRY + "\n"
                  + table_font("supplementary_table_font") + "\n")
    if orientation == "landscape":
        s1_opening = (r"\clearpage" + WIDE_TABLE_GEOMETRY + r"\begin{landscape}\begingroup"
                      + "\n" + table_font("supplementary_table_font") + "\n")
    t = t.replace(start, s1_opening + start, 1)
    cut = t.index(start)
    pre, rest = t[:cut], t[cut:]
    tab, post = rest.split(stop, 1)
    tab = tab.replace("age+stage+residual", r"age+stage+\allowbreak residual")
    tab = re.sub(r"(?<=\d)/(?=\d)", r"/\\allowbreak ", tab)
    # Explicit Markdown page-break markers precede each table's navigable
    # subsection heading, so neither the heading nor caption is orphaned.
    if r"\textbf{Supplementary Table S4." not in tab:
        raise ValueError("Supplementary Table S4 caption marker is missing")
    tab = style_supplementary_tables(tab)
    if orientation == "portrait":
        # S1 keeps the portrait block; start the landscape group only at S2.
        boundary = "\\clearpage\n\n\\subsection{Table S2}"
        if tab.count(boundary) != 1:
            raise SystemExit("Table S1/S2 boundary is not unique")
        tab = tab.replace(
            boundary,
            r"\clearpage" + "\n" + WIDE_TABLE_GEOMETRY + r"\begin{landscape}\begingroup" + "\n"
            + table_font("supplementary_table_font") + "\n\n" + r"\subsection{Table S2}",
            1,
        )
    tab = centre_table_headers(tab)
    tab = add_table_continuations(tab)
    tab = style_table_headings(tab)
    figure_number = 0
    # Native artwork narrower than the 190 mm figure block (for example the
    # single-panel Figure S2 at 120 mm) is centred without adding vertical
    # glue; full-width artwork keeps its existing placement.
    figure_block_mm = (PROFILE["document_style"]["page_width_mm"]
                       - 2 * FIGURE_SIDE_MARGIN_MM)

    def separate_figures(match):
        """Centre narrow figures and start each figure on its own supplementary page."""
        nonlocal figure_number
        figure_number += 1
        graphic = match.group(0)
        width = re.search(r"width=([0-9.]+)mm", graphic)
        if width and float(width.group(1)) < figure_block_mm - 0.05:
            graphic = r"\noindent\makebox[\linewidth][c]{%s}" % graphic
        return graphic if figure_number == 1 else r"\clearpage" + "\n" + graphic

    post = re.sub(r"\\includegraphics\[[^\]]+\]\{[^}]+\}", separate_figures, post)
    # Add contents entries for the six figure pages. Each entry is emitted
    # immediately before the graphic so that it points to the page where the
    # figure starts, including narrow figures wrapped in a centred box.
    for figure in range(1, 7):
        caption = r"\textbf{Supplementary Figure S%d." % figure
        if post.count(caption) != 1:
            raise SystemExit(
                "Expected one caption for Supplementary Figure S%d; found %d"
                % (figure, post.count(caption)))
        image = post.rindex(r"\includegraphics", 0, post.index(caption))
        line_start = post.rfind("\n", 0, image) + 1
        post = (post[:line_start]
                + r"\phantomsection\addcontentsline{toc}{subsection}{Figure S%d}" % figure
                + "\n" + post[line_start:])
    # Supplementary figures are final-size double-column artwork; narrow
    # figure-page margins let them be placed at native width without scaling.
    t = (pre + tab + r"\endgroup\end{landscape}\restoregeometry\clearpage\normalsize" + "\n"
         + FIGURE_GEOMETRY + "\n" + stop + post)
    t = t.replace(
        r"\section{Supplementary Data}\label{supplementary-data}",
        r"\clearpage\restoregeometry\section{Supplementary Data}\label{supplementary-data}",
        1,
    )
    t = t.replace(
        r"\section{Supplementary References}\label{supplementary-references}",
        r"\clearpage\restoregeometry\section{Supplementary References}\label{supplementary-references}\small\emergencystretch=3em",
        1,
    )
    t = protect_s1_figure(t)
    out.write_text(t)


# Review copy: the upload manuscript TeX with only two insertions, graphicx in
# the preamble and native-size figure pages after the last table. Both are
# removable to recover the upload TeX byte for byte, and the shared pages are
# checked page by page after compilation, so text can never diverge.
REVIEW_FIGURES = [
    ROOT / "results" / "figures" / "main" / name
    for name in ["Figure1_study_design.pdf", "Figure2_therapy_end_topology.pdf", "Figure3_external_replication.pdf"]
]
REVIEW_PREAMBLE = r"\usepackage{graphicx}" + "\n"


def review_figure_block():
    """Create unscaled formal-figure pages for the reviewer-only PDF copy."""
    pages = [r"\clearpage" + FIGURE_GEOMETRY]
    for path in REVIEW_FIGURES:
        if not path.is_file():
            raise SystemExit(f"Missing formal figure: {path}")
        rel = pathlib.Path("../..") / path.relative_to(ROOT)
        pages.append(r"\noindent\includegraphics{%s}\clearpage" % rel.as_posix())
    return "\n".join(pages) + "\n"


def write_review_copy(main_tex, review_tex):
    """Append reversible figure insertions without changing upload manuscript TeX."""
    t = main_tex.read_text()
    block = review_figure_block()
    end = "\\end{document}"
    begin = "\\begin{document}"
    if t.count(end) != 1 or t.count(begin) != 1:
        raise SystemExit("Unexpected document markers in main TeX")
    review = t.replace(begin, REVIEW_PREAMBLE + begin).replace(end, block + end)
    if review.replace(REVIEW_PREAMBLE, "", 1).replace(block, "", 1) != t:
        raise SystemExit("Review copy is not the upload TeX plus figure insertions")
    review_tex.write_text(review)


def pdf_pages(pdf):
    """Read the compiled PDF's page count using pdfinfo."""
    info = subprocess.run(["pdfinfo", str(pdf)], check=True, capture_output=True, text=True).stdout
    return int(re.search(r"^Pages:\s+(\d+)", info, re.M).group(1))


def page_text(pdf, first, last):
    """Extract layout-preserving text for an inclusive PDF page interval."""
    return subprocess.run(["pdftotext", "-layout", "-f", str(first), "-l", str(last), str(pdf), "-"],
                          check=True, capture_output=True, text=True).stdout


def verify_review_copy(main_pdf, review_pdf):
    """Verify that the review PDF adds only figures and keeps shared text identical."""
    n_main, n_review = pdf_pages(main_pdf), pdf_pages(review_pdf)
    if n_review != n_main + len(REVIEW_FIGURES):
        raise SystemExit(f"Review copy has {n_review} pages; expected {n_main} + {len(REVIEW_FIGURES)} figure pages")
    if page_text(main_pdf, 1, n_main) != page_text(review_pdf, 1, n_main):
        raise SystemExit("Review copy text differs from the upload manuscript")
    print(f"Review copy verified: pages 1-{n_main} text-identical to the upload manuscript; {len(REVIEW_FIGURES)} figure pages appended")


def compile_tex(tex):
    """Compile final TeX with XeLaTeX and stop on the first LaTeX error."""
    cmd = [LATEXMK, "-xelatex", "-interaction=nonstopmode", "-halt-on-error",
           "-file-line-error", f"-outdir={OUTPUT}", str(tex)]
    subprocess.run(cmd, check=True, cwd=OUTPUT)


def subscript_model_labels(tex_path):
    """Render M_PD as M with a subscripted PD at the display layer.

    The generated Markdown and the claims audit keep the literal M_PD. Table
    line-break rules run before this step, so they still match M\\_PD.
    """
    text = tex_path.read_text(encoding="utf-8")
    tex_path.write_text(text.replace(r"M\_PD", r"M\textsubscript{PD}"), encoding="utf-8")


jobs = [
    (SOURCE / f"{OUTPUT_PREFIX}_manuscript.md", OUTPUT / "_main.md", OUTPUT / "_main_raw.tex", OUTPUT / f"{OUTPUT_PREFIX}_manuscript.tex", finish_main),
    (SOURCE / f"{OUTPUT_PREFIX}_supplementary_appendix.md", OUTPUT / "_si.md", OUTPUT / "_si_raw.tex", OUTPUT / f"{OUTPUT_PREFIX}_supplementary_appendix.tex", finish_si),
]
for source_file, temporary_markdown, raw_tex, final_tex, formatter in jobs:
    title = prepare_markdown(source_file, temporary_markdown)
    pandoc_tex(temporary_markdown, raw_tex, title)
    formatter(raw_tex, final_tex)
    subscript_model_labels(final_tex)
    compile_tex(final_tex)

main_tex = OUTPUT / f"{OUTPUT_PREFIX}_manuscript.tex"
review_tex = OUTPUT / f"{OUTPUT_PREFIX}_manuscript_review_copy_with_figures.tex"
write_review_copy(main_tex, review_tex)
compile_tex(review_tex)
verify_review_copy(main_tex.with_suffix(".pdf"), review_tex.with_suffix(".pdf"))

# Cover letter: same source as the DOCX (copied by stage 21). It has no H1
# title, and each source line is a separate line of the letter (address,
# signature block), so hard line breaks are preserved.
cover_raw = OUTPUT / "_cover_raw.tex"
cover_tex = OUTPUT / f"{OUTPUT_PREFIX}_cover_letter.tex"
pandoc_tex(OUTPUT / "cover_letter.md", cover_raw, None, reader="markdown+hard_line_breaks")
finish_cover(cover_raw, cover_tex)
compile_tex(cover_tex)

for path in [OUTPUT / "_main.md", OUTPUT / "_si.md", OUTPUT / "_main_raw.tex", OUTPUT / "_si_raw.tex", cover_raw]:
    path.unlink(missing_ok=True)
print("Built:")
for suffix in ["manuscript.tex", "manuscript.pdf", "manuscript_review_copy_with_figures.pdf",
               "supplementary_appendix.tex", "supplementary_appendix.pdf",
               "cover_letter.tex", "cover_letter.pdf"]:
    print(OUTPUT / f"{OUTPUT_PREFIX}_{suffix}")
