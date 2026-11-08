#!/usr/bin/env python3
"""Build the Chinese review editions of the manuscript, supplement and letter.

File: 36_build_chinese_review.py
Purpose: Convert the Chinese review Markdown sources to print-ready PDFs and
    record the English-source hashes used for each build.
Author: Project authors
Created: 2026-11-05
Inputs: manuscript/zh/source/{main_zh,supplementary_zh,cover_letter_zh}.md,
    the canonical English submission files and the formal figure PNGs.
Outputs: manuscript/zh/ESMO_Open_manuscript_zh.pdf,
    manuscript/zh/ESMO_Open_supplementary_appendix_zh.pdf,
    manuscript/zh/ESMO_Open_cover_letter_zh.pdf and
    manuscript/zh/sync_manifest.json.
Runtime parameters: Pandoc, XeLaTeX, Songti SC/Heiti SC (macOS system fonts).
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "manuscript" / "zh" / "source"
BUILD = ROOT / "manuscript" / "zh" / "build"
OUTPUT = ROOT / "manuscript" / "zh"
MANIFEST = OUTPUT / "sync_manifest.json"

PANDOC = shutil.which("pandoc")
XELATEX = shutil.which("xelatex")

# English sources that the Chinese editions mirror.  The figure list keeps the
# copied review artwork tied to the canonical files under results/figures/.
ENGLISH_SOURCES = {
    "manuscript": ROOT / "manuscript" / "submission" / "ESMO_Open_manuscript.md",
    "supplementary": ROOT / "manuscript" / "submission" / "ESMO_Open_supplementary_appendix.md",
    "cover_letter": ROOT / "manuscript" / "source" / "cover_letter.md",
}
FIGURE_SOURCES = [
    ROOT / "results" / "figures" / "main" / "Figure1_study_design.png",
    ROOT / "results" / "figures" / "main" / "Figure2_therapy_end_topology.png",
    ROOT / "results" / "figures" / "main" / "Figure3_external_replication.png",
    ROOT / "results" / "figures" / "supplementary" / "FigureS1_selection_regimen_power.png",
    ROOT / "results" / "figures" / "supplementary" / "FigureS2_hgsoc_four_state.png",
    ROOT / "results" / "figures" / "supplementary" / "FigureS3_pancancer_dichotomy.png",
    ROOT / "results" / "figures" / "supplementary" / "FigureS4_pancancer_four_state.png",
    ROOT / "results" / "figures" / "supplementary" / "FigureS5_external_proliferation.png",
    ROOT / "results" / "figures" / "supplementary" / "FigureS6_calibration.png",
]

# (document key, Chinese Markdown, output PDF name, running-head label)
DOCUMENTS = [
    ("manuscript", "main_zh.md", "ESMO_Open_manuscript_zh.pdf", "主稿"),
    ("supplementary", "supplementary_zh.md", "ESMO_Open_supplementary_appendix_zh.pdf", "补充附录"),
    ("cover_letter", "cover_letter_zh.md", "ESMO_Open_cover_letter_zh.pdf", "投稿信"),
]

# Landscape table pages: table font size in points.  Wide Chinese tables need
# more room than their English counterparts because full-width glyphs are twice
# as wide; the values below keep every cell on one line where the source allows.
SUPPLEMENT_TABLES = [
    ("表 S1", 7.0),
    ("表 S2", 6.0),
    ("表 S3", 6.3),
    ("表 S4", 5.8),
    ("表 S5", 6.0),
    ("表 S6", 7.0),
    ("表 S7", 6.3),
]

TEXT_MARGIN_MM = 20
LANDSCAPE_MARGIN_MM = 14

# Chinese body setting: Songti SC at 10.5 pt with 1.30 leading reads like a
# 1.5-spaced Chinese manuscript without inflating the page count.  Tables and
# cover letter use their own leading (see insert_table_fonts / common_tex).
BODY_STRETCH = 1.30
COVER_STRETCH = 1.20
BODY_BASELINESKIP = "13.65pt"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def display_width(text):
    """Approximate typeset width: CJK/full-width glyphs count twice."""
    return sum(2 if unicodedata.east_asian_width(ch) in {"W", "F"} else 1 for ch in text)


def split_row(line):
    body = line.strip()
    if body.startswith("|"):
        body = body[1:]
    if body.endswith("|"):
        body = body[:-1]
    return [cell.strip() for cell in body.split("|")]


def is_separator(cells):
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells)


def reflow_tables(markdown):
    """Give every pipe table proportional column widths.

    Pandoc derives LaTeX column widths from the relative number of dashes in
    the separator row.  The Chinese sources use uniform dashes, which would
    split a thirteen-column table into thirteen equal slivers; here the dashes
    are weighted by the longest cell in each column (with a mild power
    compression so short numeric columns keep usable widths).
    """
    lines = markdown.splitlines()
    output = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.lstrip().startswith("|") and index + 1 < len(lines):
            header = split_row(line)
            separator = split_row(lines[index + 1])
            if len(header) == len(separator) and is_separator(separator):
                rows = [header]
                cursor = index + 2
                while cursor < len(lines) and lines[cursor].lstrip().startswith("|"):
                    cells = split_row(lines[cursor])
                    if len(cells) != len(header):
                        break
                    rows.append(cells)
                    cursor += 1
                widths = []
                for column in range(len(header)):
                    longest = max(display_width(re.sub(r"[*`\\]", "", row[column])) for row in rows)
                    widths.append(max(longest, 4) ** 0.9)
                total = sum(widths)
                target = max(40, 5 * len(header))
                counts = [max(3, round(target * value / total)) for value in widths]
                rebuilt = []
                for cell, count in zip(separator, counts):
                    left = cell.startswith(":")
                    right = cell.endswith(":")
                    dashes = "-" * count
                    rebuilt.append((":" if left else "") + dashes + (":" if right else ""))
                output.append(line)
                output.append("|" + "|".join(rebuilt) + "|")
                output.extend(lines[index + 2:cursor])
                index = cursor
                continue
        output.append(line)
        index += 1
    return "\n".join(output) + ("\n" if markdown.endswith("\n") else "")


def copy_figures():
    destination = SOURCE / "figures"
    destination.mkdir(parents=True, exist_ok=True)
    for figure in FIGURE_SOURCES:
        shutil.copy2(figure, destination / figure.name)


def pandoc_tex(markdown_path, tex_path, resource_path, cover=False):
    command = [
        PANDOC,
        str(markdown_path),
        "-o",
        str(tex_path),
        "--standalone",
        "--pdf-engine=xelatex",
        "-V", "documentclass=extarticle",
        "-V", "fontsize=10.5pt",
        "-V", "papersize=a4",
        "-V", f"geometry:margin={TEXT_MARGIN_MM}mm",
        "-V", "CJKmainfont=Songti SC",
        "-V", "CJKoptions=BoldFont=Heiti SC Medium",
        "-V", "mainfont=Times New Roman",
        "--resource-path", str(resource_path),
    ]
    if cover:
        command.insert(3, "--from=markdown+hard_line_breaks")
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        raise SystemExit(f"pandoc failed for {markdown_path.name}")


def table_font(size_pt):
    return r"\fontsize{%s}{%s}\selectfont" % (size_pt, round(size_pt * 1.24, 1))


def insert_table_fonts(block, size_pt):
    """Set a compact leading inside table blocks.

    The body is typeset with 1.30 line spread; longtables must reset the
    stretch before \fontsize, otherwise their leading grows with the body and
    the widest landscape tables overflow the page.
    """
    font = "\\linespread{1.0}\\selectfont\n" + table_font(size_pt)
    block = block.replace(
        r"\begin{longtable}",
        r"\setlength{\tabcolsep}{3pt}" + "\n" + font + "\n" + r"\begin{longtable}",
    )
    block = block.replace(
        r"\end{longtable}",
        r"\end{longtable}"
        + "\n" + r"\normalsize\linespread{%s}\selectfont" % BODY_STRETCH
        + "\n" + r"\setlength{\tabcolsep}{6pt}",
    )
    return block


def wrap_landscape(block, size_pt):
    block = insert_table_fonts(block, size_pt)
    return (
        "\n\\clearpage\n"
        "\\pdfpagewidth=297mm\n"
        "\\pdfpageheight=210mm\n"
        f"\\newgeometry{{margin={LANDSCAPE_MARGIN_MM}mm,headsep=6mm,footskip=12mm}}\n"
        # \newgeometry still measures the sheet as A4 portrait, so \textheight
        # would stay at 269 mm while the landscape page is only 210 mm high.
        # Without this override the page builder happily runs past the page
        # edge and every row below 210 mm is silently clipped away.
        "\\setlength{\\textheight}{182mm}\n"
        "\\setlength{\\vsize}{182mm}\n"
        "\\setlength{\\textwidth}{269mm}\n"
        "\\setlength{\\linewidth}{269mm}\n"
        "\\setlength{\\hsize}{269mm}\n"
        "\\setlength{\\headwidth}{\\textwidth}\n"
        + block
        + "\n\\clearpage\n"
        "\\pdfpagewidth=210mm\n"
        "\\pdfpageheight=297mm\n"
        "\\restoregeometry\n"
        "\\setlength{\\vsize}{\\textheight}\n"
        "\\setlength{\\headwidth}{\\textwidth}\n"
    )


def common_tex(tex, label, cover=False):
    if r"\usepackage{bookmark}" not in tex:
        raise SystemExit("pandoc preamble no longer contains the bookmark package")
    # TinyTeX's bookmark/hyperref pair fails on the first Chinese section
    # heading; loading hyperref directly provides the same links without the
    # failing bookmark driver.
    tex = tex.replace(r"\usepackage{bookmark}", r"\usepackage{hyperref}")

    stretch = COVER_STRETCH if cover else BODY_STRETCH
    indent = "0pt" if cover else "2em"
    parskip = "0.50em plus 0.12em minus 0.05em" if cover else "0.35em plus 0.12em minus 0.05em"
    header = [
        r"\usepackage{fancyhdr}",
        r"\usepackage{setspace}",
        r"\usepackage{titlesec}",
        r"\usepackage{needspace}",
        r"\usepackage{indentfirst}",
        r"\linespread{%s}" % stretch,
        r"\setlength{\parindent}{%s}" % indent,
        r"\setlength{\parskip}{%s}" % parskip,
        r"\setlength{\headheight}{14pt}",
        r"\widowpenalty=10000",
        r"\clubpenalty=10000",
        r"\raggedbottom",
        r"\sloppy",
        # Heading faces.  The "Heiti SC" family default is its Light weight, so
        # \bfseries on CJK used to select STHeitiSC-Light: lighter and visually
        # smaller than the Songti body.  Headings now use the W6 (bold) face of
        # Hiragino Sans GB, which has real stroke weight against the Songti body.
        r"\setCJKfamilyfont{zhhead}[BoldFont=Hiragino Sans GB W6]{Hiragino Sans GB}",
        r"\newcommand{\headface}{\CJKfamily{zhhead}\bfseries}",
        # Hierarchy: 19 pt rule-marked title > 17 pt section > 14.5 pt
        # subsection > 10.5 pt run-in paragraph = 10.5 pt body.
        r"\titleformat{\section}{\centering\headface}{}{0pt}"
        r"{\linespread{1}\fontsize{19}{22.5}\selectfont}"
        r"[{\vspace{0.42em}\titlerule[0.4pt]}]",
        r"\titlespacing*{\section}{0pt}{0.9em plus 0.2em minus 0.1em}{0.9em}",
        r"\titleformat{\subsection}{\headface}{}{0pt}"
        r"{\linespread{1}\fontsize{17}{20}\selectfont}",
        r"\titlespacing*{\subsection}{0pt}{1.45em plus 0.25em minus 0.10em}{0.60em}",
        r"\titleformat{\subsubsection}{\headface}{}{0pt}"
        r"{\linespread{1}\fontsize{14.5}{17.2}\selectfont}",
        r"\titlespacing*{\subsubsection}{0pt}{1.15em plus 0.20em minus 0.10em}{0.50em}",
        r"\titleformat{\paragraph}[runin]{\headface}{}{0pt}"
        r"{\linespread{1}\fontsize{10.5}{12.6}\selectfont}",
        r"\titlespacing*{\paragraph}{2em}{0.65em}{0.65em}",
        r"\pagestyle{fancy}",
        r"\fancyhf{}",
        r"\fancyhead[L]{\footnotesize 中文审阅稿 · 非投稿文件}",
        r"\fancyhead[R]{\footnotesize %s}" % label,
        r"\fancyfoot[C]{\footnotesize \thepage}",
        r"\renewcommand{\headrulewidth}{0.4pt}",
        r"\fancypagestyle{plain}{\fancyhf{}\fancyfoot[C]{\footnotesize\thepage}"
        r"\renewcommand{\headrulewidth}{0pt}}",
    ]
    tex = tex.replace(r"\begin{document}", "\n".join(header) + "\n\n" + r"\begin{document}", 1)
    return tex


def add_needspace(tex):
    """Keep a heading with at least a few lines of its following text."""
    # A 19 pt section heading that lands on the last line of a page (observed
    # for the Patients and methods heading on page 2) is a widow heading.
    tex = tex.replace("\n\\section{", "\n\\needspace{6\\baselineskip}\n\\section{")
    tex = tex.replace("\n\\subsection{", "\n\\needspace{7\\baselineskip}\n\\subsection{")
    tex = tex.replace("\n\\subsubsection{", "\n\\needspace{4\\baselineskip}\n\\subsubsection{")
    return tex


def page_break_before(tex, heading):
    needle = "\\subsection{%s}" % heading
    return tex.replace(needle, "\\clearpage\n" + needle, 1)


def tidy_figures(tex, max_height="0.80", page_break=True):
    """Turn each Pandoc float into a page-anchored review figure.

    Figure sections are later wrapped in a 190 mm measure (see
    wrap_wide_figures), so the artwork keeps its designed size instead of
    overflowing the 170 mm text block.
    """
    pattern = re.compile(r"\\begin\{figure\}(.*?)\\end\{figure\}", re.S)

    def replace(match):
        body = match.group(1)
        caption = re.search(r"\\caption\{(.+?)\}", body, re.S)
        graphic = re.search(r"\\includegraphics\[(.*?)\]\{(.*?)\}", body, re.S)
        if not caption or not graphic:
            return match.group(0)
        options, path = graphic.group(1), graphic.group(2)
        options = re.sub(
            r"height=[0-9.]*\\textheight",
            lambda match: "height=%s\\textheight" % max_height,
            options,
        )
        label = caption.group(1).strip()
        return (
            "\n\\begin{center}\n"
            "\\includegraphics[%s]{%s}\n" % (options, path)
            + "\\end{center}\n"
            + "\\begin{center}\\textbf{%s}\\end{center}\n" % label
            + ("\\clearpage\n" if page_break else "")
        )

    return pattern.sub(replace, tex)


def wrap_wide_figures(tex, start_heading, end_heading=None):
    """Typeset a figure section on a 190 mm measure.

    The formal PNGs were drawn for 190 mm; widening the text block to the
    artwork width avoids downscaling and keeps their 8 pt labels legible.
    """
    start = tex.index("\\subsection{%s}" % start_heading)
    if end_heading:
        end = tex.index("\\subsection{%s}" % end_heading, start)
    else:
        end = tex.index(r"\end{document}", start)
    block = tex[start:end]
    wide = (
        "\n\\clearpage\n"
        # Keep the footer baseline 6 mm inside the sheet instead of at its edge.
        "\\newgeometry{left=10mm,right=10mm,top=18mm,bottom=12mm,headsep=7mm,footskip=6mm}\n"
        "\\setlength{\\textwidth}{190mm}\n"
        "\\setlength{\\linewidth}{190mm}\n"
        "\\setlength{\\hsize}{190mm}\n"
        "\\setlength{\\headwidth}{\\textwidth}\n"
        + block
        + "\n\\clearpage\n"
        "\\restoregeometry\n"
        "\\setlength{\\headwidth}{\\textwidth}\n"
    )
    return tex[:start] + wide + tex[end:]


def format_main(tex):
    tex = tex.replace(
        "预后差异：一项",
        "预后差异：\\\\\n一项",
        1,
    )
    for heading in ("参考文献", "图注", "表注", "表", "图件"):
        tex = page_break_before(tex, heading)

    table_section = tex.index(r"\subsection{表}")
    first_table = tex.index(r"\begin{longtable}", table_section)
    tex = tex[:first_table] + table_font(6.8) + "\n" + tex[first_table:]
    end_first = tex.index(r"\end{longtable}", first_table)
    tex = (
        tex[:end_first]
        + r"\end{longtable}"
        + "\n"
        + r"\normalsize\linespread{%s}\selectfont" % BODY_STRETCH
        + tex[end_first + len(r"\end{longtable}"):]
    )

    start = tex.index(r"\textbf{表 2.", table_section)
    stop = tex.index(r"\subsection{图件}", start)
    tex = tex[:start] + wrap_landscape(tex[start:stop], 6.2) + tex[stop:]
    return wrap_wide_figures(tex, "图件")


def bind_panel_labels(content, name, force=()):
    """Mark each panel label so an orphaned label can be found after rendering.

    A standalone ``（c）`` paragraph at the very bottom of a page is not only
    ugly: the following longtable then starts at a page break inside the
    landscape block and LaTeX silently drops its body rows.  Every label
    carries a unique marker; if a rendered page ends with that label, the next
    build inserts a page break before the panel so the table starts intact.
    """
    table_id = name.replace("表 ", "")
    parts = re.split(r"(?m)^(\\textbf\{（[a-z]）\})\s*$", content)
    rebuilt = parts[0]
    for index in range(1, len(parts), 2):
        letter = re.search(r"（([a-z])）", parts[index]).group(1)
        key = "%s%s" % (table_id, letter)
        if key in force:
            rebuilt += "\\clearpage\n"
        rebuilt += "\\noindent" + parts[index] + "\\label{zhpanel:%s}\n" % key
        rebuilt += parts[index + 1]
    return rebuilt


def panel_orphans(pdf_path, tex):
    """Return panel ids whose label is the last content line of a page.

    ``pdftotext -layout`` merges short label lines with neighbouring table or
    caption text, so the word coordinates from ``-bbox`` are used instead.  The
    owning table is taken from the most recent ``补充表 S<n>`` caption above the
    label, which keeps the mapping stable even when other tables also have a
    ``（c）`` panel.
    """
    result = subprocess.run(
        ["pdftotext", "-bbox", str(pdf_path), "-"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return set()
    orphans = set()
    table_id = None
    for page in re.finditer(
        r'<page width="[\d.]+" height="([\d.]+)">(.*?)</page>',
        result.stdout,
        re.S,
    ):
        height = float(page.group(1))
        words = re.findall(
            r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="[\d.]+" '
            r'yMax="[\d.]+">(.*?)</word>',
            page.group(2),
        )
        items = []
        for x_text, y_text, text in words:
            x = float(x_text)
            y = float(y_text)
            if y < height * 0.06:
                continue
            if y > height * 0.94 and re.fullmatch(r"\d+", text):
                continue
            items.append((y, x, text))
        if not items:
            continue
        items.sort()
        lines = []
        for y, x, text in items:
            if lines and abs(y - lines[-1][0]) < 3:
                lines[-1][1].append((x, text))
            else:
                lines.append((y, [(x, text)]))
        joined_lines = []
        for _, parts in lines:
            parts.sort()
            joined_lines.append("".join(text for _, text in parts))
        for line in joined_lines:
            caption = re.search(r"补充表\s*S(\d+)", line)
            if caption:
                table_id = "S" + caption.group(1)
        last = joined_lines[-1]
        label = re.fullmatch(r"（([a-z])）", last)
        if label and table_id:
            orphans.add(table_id + label.group(1))
    keys = set(re.findall(r"\\label\{zhpanel:([^}]+)\}", tex))
    return orphans & keys



def format_supplementary(tex, force=()):
    """Give every supplementary table its own landscape page.

    The table subheadings only serve as split markers; the full bold caption
    ("补充表 S1. ...") is kept and the redundant one-line marker is dropped.
    The section heading travels with the first landscape block so it cannot be
    stranded at the bottom of a portrait page.
    """
    section = tex.index(r"\subsection{补充表}")
    section_end = tex.index(r"\subsection{补充图}", section)
    body = tex[section:section_end]
    parts = re.split(r"(\\subsubsection\{表 S[0-9]+\}(?:\\label\{[^}]*\})?\s*)", body)
    sizes = dict(SUPPLEMENT_TABLES)

    rebuilt = ""
    lead = parts[0].strip()
    for index in range(1, len(parts), 2):
        name = re.search(r"表 S[0-9]+", parts[index]).group(0)
        content = parts[index + 1].strip()
        block = ((lead + "\n\n") if index == 1 else "") + content
        rebuilt += bind_panel_labels(wrap_landscape(block, sizes[name]), name, force)

    tex = tex[:section] + rebuilt + tex[section_end:]
    tex = format_supplementary_figures(tex)
    tex = wrap_wide_figures(tex, "补充图", "补充数据")
    for heading in ("补充结果", "补充数据", "补充参考文献"):
        tex = page_break_before(tex, heading)
    return tex


def format_supplementary_figures(tex):
    """Keep each image, label and legend together on one 190 mm page."""
    start = tex.index(r"\subsection{补充图}")
    end = tex.index(r"\subsection{补充数据}", start)
    body = tex[start:end]
    rebuilt = []
    for part in body.split("\n\n"):
        text = part.strip()
        if text.startswith(r"\textbf{补充图 S"):
            rebuilt.append(text + "\n\\clearpage")
        else:
            rebuilt.append(part)
    return tex[:start] + "\n\n".join(rebuilt) + tex[end:]


def format_cover(tex):
    """Right-align the signature block, one element per line."""
    start = tex.index("Tao Zhu")
    stop = tex.index(r"\end{document}")
    block = tex[start:stop].rstrip().replace("\n", "\\\\\n")
    return tex[:start] + "\\begin{flushright}\n" + block + "\n\\end{flushright}\n\n" + tex[stop:]


def compile_tex(tex_path):
    for _ in range(2):
        result = subprocess.run(
            [XELATEX, "-interaction=nonstopmode", "-halt-on-error", tex_path.name],
            cwd=tex_path.parent,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            log = tex_path.with_suffix(".log")
            tail = log.read_text(errors="replace").splitlines()[-60:] if log.exists() else []
            print("\n".join(tail), file=sys.stderr)
            print(result.stdout[-2000:], file=sys.stderr)
            raise SystemExit(f"xelatex failed for {tex_path.name}")
    return tex_path.with_suffix(".pdf")


def page_count(pdf_path):
    result = subprocess.run(["pdfinfo", str(pdf_path)], capture_output=True, text=True)
    if result.returncode == 0:
        match = re.search(r"^Pages:\s+(\d+)", result.stdout, re.MULTILINE)
        if match:
            return int(match.group(1))
    return None


def overfull_count(tex_path):
    log = tex_path.with_suffix(".log")
    if not log.exists():
        return None
    text = log.read_text(errors="replace")
    return len(re.findall(r"Overfull \\hbox", text))


def previous_manifest():
    if not MANIFEST.exists():
        return None
    try:
        return json.loads(MANIFEST.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def check_english_drift(previous, force):
    """Stop a rebuild that would silently bless untranslated English changes.

    A figure-only change is reported because the PDF picks the artwork up
    automatically.  A change to an English text source must be accompanied by an
    edit to the corresponding Chinese source; otherwise the recorded hashes
    would advance while the Chinese text still described the old English.
    """
    if previous is None:
        return
    blocked = []
    reviewed = []
    for key, path in ENGLISH_SOURCES.items():
        recorded = previous.get("english_sources", {}).get(key, {}).get("sha256")
        if recorded and sha256(path) != recorded:
            document = previous.get("documents", {}).get(key, {})
            chinese = ROOT / document.get("chinese_source", "")
            chinese_recorded = document.get("chinese_source_sha256")
            if chinese.is_file() and chinese_recorded and sha256(chinese) != chinese_recorded:
                reviewed.append(key)
            else:
                blocked.append(key)

    changed_figures = [
        relative
        for relative, recorded in previous.get("figures", {}).items()
        if (ROOT / relative).is_file() and sha256(ROOT / relative) != recorded
    ]

    if changed_figures:
        print("Note: formal figures changed since the last build; the new artwork will be embedded:")
        for relative in changed_figures:
            print(f"  - {relative}")

    if reviewed:
        print("English sources changed and their Chinese sources were also edited; assuming sync:")
        for key in reviewed:
            print(f"  - {key}: {ENGLISH_SOURCES[key].relative_to(ROOT)}")

    if blocked:
        print("Refusing to rebuild: English text changed without a matching Chinese edit.", file=sys.stderr)
        for key in blocked:
            print(f"  - {key}: {ENGLISH_SOURCES[key].relative_to(ROOT)}", file=sys.stderr)
        print(
            "\nUpdate the corresponding file under manuscript/zh/source/ first, or run\n"
            "`python3 scripts/36_build_chinese_review.py --force` after confirming that\n"
            "the Chinese edition is intentionally left behind. Nothing was rebuilt.",
            file=sys.stderr,
        )
        if not force:
            raise SystemExit(2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="rebuild even when English text changed without a Chinese edit")
    args = parser.parse_args()

    for tool in (PANDOC, XELATEX):
        if not tool:
            raise SystemExit("pandoc and xelatex must be on PATH")
    BUILD.mkdir(parents=True, exist_ok=True)
    copy_figures()

    check_english_drift(previous_manifest(), args.force)

    manifest = {
        "generated_by": "scripts/36_build_chinese_review.py",
        "generated_at": datetime.datetime.now().isoformat(timespec="seconds"),
        "rule": "Whenever an English submission source or formal figure changes, "
                "run `make zh` and review the diff before delivering the Chinese edition.",
        "english_sources": {},
        "figures": {},
        "documents": {},
    }
    for key, path in ENGLISH_SOURCES.items():
        manifest["english_sources"][key] = {
            "path": str(path.relative_to(ROOT)),
            "sha256": sha256(path),
        }
    for figure in FIGURE_SOURCES:
        manifest["figures"][str(figure.relative_to(ROOT))] = sha256(figure)

    for key, markdown_name, pdf_name, label in DOCUMENTS:
        source_path = SOURCE / markdown_name
        work = BUILD / key
        work.mkdir(parents=True, exist_ok=True)
        markdown = reflow_tables(source_path.read_text(encoding="utf-8"))
        working_markdown = work / markdown_name
        working_markdown.write_text(markdown, encoding="utf-8")
        if not (work / "figures").exists():
            (work / "figures").symlink_to(SOURCE / "figures", target_is_directory=True)

        raw_tex = work / f"{key}_raw.tex"
        final_tex = work / f"{key}.tex"
        pandoc_tex(working_markdown, raw_tex, SOURCE)
        tex = common_tex(raw_tex.read_text(encoding="utf-8"), label, cover=(key == "cover_letter"))
        if key == "manuscript":
            tex = tidy_figures(tex, max_height="0.80", page_break=True)
            tex = format_main(tex)
            tex = add_needspace(tex)
            final_tex.write_text(tex, encoding="utf-8")
            pdf = compile_tex(final_tex)
        elif key == "supplementary":
            base = tidy_figures(tex, max_height="0.72", page_break=False)
            force = set()
            for _ in range(4):
                tex = add_needspace(format_supplementary(base, force))
                final_tex.write_text(tex, encoding="utf-8")
                pdf = compile_tex(final_tex)
                orphans = panel_orphans(pdf, tex)
                if orphans <= force:
                    break
                force |= orphans
        elif key == "cover_letter":
            tex = format_cover(tex)
            tex = add_needspace(tex)
            final_tex.write_text(tex, encoding="utf-8")
            pdf = compile_tex(final_tex)
        destination = OUTPUT / pdf_name
        shutil.copy2(pdf, destination)
        manifest["documents"][key] = {
            "chinese_source": str(source_path.relative_to(ROOT)),
            "chinese_source_sha256": sha256(source_path),
            "pdf": str(destination.relative_to(ROOT)),
            "pdf_sha256": sha256(destination),
            "pages": page_count(destination),
            "overfull_hboxes": overfull_count(final_tex),
            "landscape_tables": key in {"supplementary"} or key == "manuscript",
        }
        print(f"{destination.relative_to(ROOT)}: {manifest['documents'][key]['pages']} pages")

    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {MANIFEST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
