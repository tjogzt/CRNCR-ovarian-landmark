/**
 * File: 22_generate_submission_docx.js
 * Purpose: Convert versioned journal-submission Markdown into styled DOCX files.
 * Author: Project authors
 * Created: 2026-10-15
 * Inputs: manuscript/submission/*.md, config/submission_profile.json, and figures.
 * Outputs: Configured DOCX files under manuscript/submission/.
 * Runtime parameters: Submission profile and Node dependencies in package.json.
 */

const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, ImageRun,
  Header, Footer, AlignmentType, PageOrientation, LevelFormat, HeadingLevel,
  BorderStyle, WidthType, ShadingType, VerticalAlign, PageNumber, SectionType,
  TableLayoutType, PageBreak, TableOfContents,
} = require("docx");

const ROOT = path.resolve(__dirname, "..");
const OUTPUT = path.join(ROOT, "manuscript", "submission");
const PROFILE = JSON.parse(fs.readFileSync(path.join(ROOT, "config", "submission_profile.json"), "utf8"));

function requireObject(value, name) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Submission profile field must be an object: ${name}`);
  }
  return value;
}

function requireString(value, name) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`Submission profile field must be a non-empty string: ${name}`);
  }
  return value;
}

// Input: versioned document-style mapping. Return: the same validated mapping.
// Units remain those of the historical renderer: half-points, twips and mm.
function validateDocumentStyle(value) {
  const style = requireObject(value, "document_style");
  for (const field of ["font_family", "monospace_font_family", "table_border_color",
    "table_header_fill", "header_text_color", "heading_text_color"]) {
    requireString(style[field], `document_style.${field}`);
  }
  const numericFields = [
    "page_width_mm", "portrait_table_width_twips", "landscape_table_width_twips",
    "landscape_page_width_twips", "landscape_page_height_twips",
    "body_font_size_half_points", "title_font_size_half_points",
    "heading_1_font_size_half_points", "heading_2_font_size_half_points",
    "header_footer_font_size_half_points", "inline_script_reduction_half_points",
    "line_spacing_twips", "body_space_after_twips", "bullet_space_after_twips",
    "figure_space_before_twips", "figure_space_after_twips",
    "title_space_before_twips", "title_space_after_twips",
    "heading_1_space_before_twips", "heading_1_space_after_twips",
    "heading_2_space_before_twips", "heading_2_space_after_twips",
    "portrait_page_margin_twips", "landscape_page_margin_twips",
    "figure_page_margin_mm", "header_footer_gap_mm", "table_cell_margin_twips",
    "table_space_after_twips", "table_font_size_half_points",
    "main_table_font_size_half_points", "table_note_font_size_half_points",
    "table_note_line_spacing_twips",
    "wide_table_font_size_half_points", "very_wide_table_font_size_half_points",
    "table_border_size_eighth_points", "bullet_indent_left_twips",
    "bullet_indent_hanging_twips",
  ];
  for (const field of numericFields) {
    if (!Number.isFinite(style[field]) || style[field] <= 0) {
      throw new Error(`Submission profile field must be a positive finite number: document_style.${field}`);
    }
  }
  if (style.inline_script_reduction_half_points >= style.body_font_size_half_points) {
    throw new Error("document_style.inline_script_reduction_half_points must be smaller than the body font size");
  }
  return style;
}

const OUTPUT_PREFIX = requireString(PROFILE.output_prefix, "output_prefix");
const DOCUMENT_METADATA = requireObject(PROFILE.document_metadata, "document_metadata");
for (const field of ["creator", "title", "description"]) {
  requireString(DOCUMENT_METADATA[field], `document_metadata.${field}`);
}
const DOCUMENT_STYLE = validateDocumentStyle(PROFILE.document_style);
const TABLE_LAYOUT = requireObject(PROFILE.table_layout, "table_layout");
for (const field of ["sample_rows", "maximum_weight", "length_offset", "length_multiplier",
  "wide_column_count", "very_wide_column_count", "minimum_narrow_column_twips",
  "minimum_wide_column_twips", "minimum_very_wide_column_twips", "left_aligned_column_count"]) {
  if (!Number.isFinite(TABLE_LAYOUT[field]) || TABLE_LAYOUT[field] <= 0) {
    throw new Error(`Table layout field must be a positive finite number: ${field}`);
  }
}
const MAIN_FRACTIONS = TABLE_LAYOUT.main_table_fractions;
if (!Array.isArray(MAIN_FRACTIONS) || MAIN_FRACTIONS.length !== 8
    || MAIN_FRACTIONS.some(value => !Number.isFinite(value) || value <= 0)
    || Math.abs(MAIN_FRACTIONS.reduce((a, b) => a + b, 0) - 1) > 5e-4) {
  throw new Error("table_layout.main_table_fractions must be 8 positive numbers summing to 1");
}
const COMPARISON_FRACTIONS = TABLE_LAYOUT.comparison_table_fractions;
if (!Array.isArray(COMPARISON_FRACTIONS) || COMPARISON_FRACTIONS.length !== 13
    || COMPARISON_FRACTIONS.some(value => !Number.isFinite(value) || value <= 0)
    || Math.abs(COMPARISON_FRACTIONS.reduce((a, b) => a + b, 0) - 1) > 5e-4) {
  throw new Error("table_layout.comparison_table_fractions must be 13 positive numbers summing to 1");
}
const FIGURE_AUDIT = requireObject(PROFILE.figure_audit, "figure_audit");
if (!Number.isFinite(FIGURE_AUDIT.size_tolerance_mm) || FIGURE_AUDIT.size_tolerance_mm < 0) {
  throw new Error("figure_audit.size_tolerance_mm must be nonnegative and finite");
}
// Unit conversions are format standards, not scientific cohort parameters.
const MM_TO_TWIP = 1440 / 25.4;
const MM_TO_PX = 96 / 25.4;
// docx createPageSize swaps the configured portrait dimensions for LANDSCAPE.
const A4 = { width: DOCUMENT_STYLE.landscape_page_width_twips,
  height: DOCUMENT_STYLE.landscape_page_height_twips };
const SHORT_TITLE = "Response grouping and survival in ovarian cancer";
const MIN_TABLE_SIZE = DOCUMENT_STYLE.table_font_size_half_points;
const MAIN_NOTE_SIZE = DOCUMENT_STYLE.table_note_font_size_half_points;
const S1D_FRACTIONS = PROFILE.latex_style.supplementary_table_s1_d_fractions;
const FONT = DOCUMENT_STYLE.font_family;
const border = { style: BorderStyle.SINGLE, size: DOCUMENT_STYLE.table_border_size_eighth_points, color: DOCUMENT_STYLE.table_border_color };
const borders = { top: border, bottom: border, left: border, right: border };
const bulletRef = "submission-bullets";

// Translate the supported inline Markdown tokens into styled text runs while
// preserving untouched substrings. Superscripts are citations, not new results.
// Input: one paragraph string and a half-point size. Output: DOCX TextRun array.
function inlineRuns(s, size = DOCUMENT_STYLE.body_font_size_half_points) {
  const runs = [];
  const re = /(\*\*.+?\*\*|\*[^*]+?\*|\^[^^]+?\^|~[^~]+?~|`[^`]+?`)/g;
  let at = 0;
  for (const m of s.matchAll(re)) {
    if (m.index > at) runs.push(new TextRun({ text: s.slice(at, m.index), font: FONT, size }));
    const x = m[0];
    if (x.startsWith("**")) runs.push(new TextRun({ text: x.slice(2, -2), bold: true, font: FONT, size }));
    else if (x.startsWith("*")) runs.push(new TextRun({ text: x.slice(1, -1), italics: true, font: FONT, size }));
    else if (x.startsWith("^")) {
      // Allow emphasis inside a script token, e.g. L~*i*~ for an italic subscript i.
      const inner = x.slice(1, -1), emphasis = inner.match(/^\*(.+)\*$/);
      runs.push(new TextRun({ text: emphasis ? emphasis[1] : inner, italics: Boolean(emphasis), superScript: true, font: FONT, size: size - DOCUMENT_STYLE.inline_script_reduction_half_points }));
    }
    else if (x.startsWith("~")) {
      const inner = x.slice(1, -1), emphasis = inner.match(/^\*(.+)\*$/);
      runs.push(new TextRun({ text: emphasis ? emphasis[1] : inner, italics: Boolean(emphasis), subScript: true, font: FONT, size: size - DOCUMENT_STYLE.inline_script_reduction_half_points }));
    }
    else runs.push(new TextRun({ text: x.slice(1, -1), font: DOCUMENT_STYLE.monospace_font_family, size }));
    at = m.index + x.length;
  }
  if (at < s.length) runs.push(new TextRun({ text: s.slice(at), font: FONT, size }));
  return runs.length ? runs : [new TextRun({ text: "", font: FONT, size })];
}

// Protect escaped pipes before splitting a Markdown table row into cells.
function splitPipe(line) {
  const token = "\u0000PIPE\u0000";
  return line.trim().replace(/\\\|/g, token).replace(/^\||\|$/g, "").split("|").map(x => x.trim().replaceAll(token, "|"));
}

// Allocate integer twip widths from representative cell lengths. The final
// column absorbs rounding so the sum stays exactly equal to the page width.
// Input: parsed table rows and usable width. Output: one width per column.
function widths(rows, total) {
  const n = rows[0].length;
  const score = Array(n).fill(1);
  for (const row of rows.slice(0, TABLE_LAYOUT.sample_rows)) {
    row.forEach((v, i) => {
      // Inline emphasis markers are typography, not printed characters, and
      // must not influence the column widths fixed by the approved baseline.
      const plain = v.replace(/\*/g, "");
      score[i] = Math.max(score[i], Math.min(
        TABLE_LAYOUT.maximum_weight, Math.sqrt(plain.length + TABLE_LAYOUT.length_offset) * TABLE_LAYOUT.length_multiplier
      ));
    });
  }
  const min = n >= TABLE_LAYOUT.very_wide_column_count ? TABLE_LAYOUT.minimum_very_wide_column_twips
    : n >= TABLE_LAYOUT.wide_column_count ? TABLE_LAYOUT.minimum_wide_column_twips : TABLE_LAYOUT.minimum_narrow_column_twips;
  let w = score.map(x => Math.max(min, Math.floor(total * x / score.reduce((a, b) => a + b, 0))));
  const sum = w.reduce((a, b) => a + b, 0);
  w = w.map(x => Math.floor(x * total / sum));
  w[w.length - 1] += total - w.reduce((a, b) => a + b, 0);
  return w;
}

// Table headers are bold by default; a single-asterisk span inside them
// becomes italic (used for the statistical symbol P) without losing bold.
function headerRuns(s, size) {
  const runs = [];
  const re = /(\*[^*]+\*|~[^~]+~)/g;
  let at = 0;
  for (const m of s.matchAll(re)) {
    if (m.index > at) runs.push(new TextRun({ text: s.slice(at, m.index), bold: true, font: FONT, size }));
    const x = m[0];
    const subscript = x.startsWith("~");
    const italics = x.startsWith("*");
    runs.push(new TextRun({
      text: x.slice(1, -1), bold: true, italics, subScript: subscript, font: FONT,
      size: subscript ? size - DOCUMENT_STYLE.inline_script_reduction_half_points : size,
    }));
    at = m.index + x.length;
  }
  if (at < s.length) runs.push(new TextRun({ text: s.slice(at), bold: true, font: FONT, size }));
  return runs.length ? runs : [new TextRun({ text: "", bold: true, font: FONT, size })];
}

// Convert approved fractions into integer twips; the last column absorbs the
// rounding remainder so the block width stays exact.
function fractionWidths(fractions, total) {
  const w = fractions.map(value => Math.floor(total * value));
  w[w.length - 1] += total - w.reduce((a, b) => a + b, 0);
  return w;
}

// Reuse the content-specific PDF fractions for wide supplementary panels.
// Missing mappings fall back to measured text lengths, never smaller type.
function supplementaryFractions(table, panel, columns) {
  if (!table) return null;
  const key = `supplementary_table_${table.toLowerCase()}${panel ? `_${panel}` : ""}_fractions`;
  const fractions = table === "S1" && panel === "d" ? S1D_FRACTIONS : PROFILE.latex_style[key];
  if (!fractions) return null;
  if (fractions.length !== columns || fractions.some(x => !Number.isFinite(x) || x <= 0)
      || Math.abs(fractions.reduce((a, b) => a + b, 0) - 1) > 5e-4) {
    throw new Error(`Invalid supplementary column fractions: ${key}`);
  }
  return fractions;
}

// Input: a complete Markdown pipe-table block, orientation and panel context.
// Output: an editable fixed-width table with repeating headers and unsplit rows.
function makeTable(lines, landscape, table = null, panel = null) {
  const rows = lines.filter((_, i) => i !== 1).map(splitPipe);
  const total = landscape
    ? A4.height - 2 * DOCUMENT_STYLE.landscape_page_margin_twips
    : DOCUMENT_STYLE.portrait_table_width_twips;
  const isMainTable = rows[0].length === 8 && rows[0][0].replace(/\*/g, "").trim() === "Characteristic";
  const isComparisonTable = rows[0].length === 13
    && rows[0][0].replace(/\*/g, "").trim() === "Analysis";
  const fractions = isMainTable ? MAIN_FRACTIONS : isComparisonTable ? COMPARISON_FRACTIONS
    : supplementaryFractions(table, panel, rows[0].length);
  const ww = fractions ? fractionWidths(fractions, total) : widths(rows, total);
  const small = Math.max(MIN_TABLE_SIZE, (isMainTable || isComparisonTable)
    ? DOCUMENT_STYLE.main_table_font_size_half_points : DOCUMENT_STYLE.table_font_size_half_points);
  const isS1d = table === "S1" && panel === "d";
  const continuedTable = ["S1", "S3", "S5"].includes(table);
  const cellMargin = DOCUMENT_STYLE.table_cell_margin_twips;
  const noBorder = { style: BorderStyle.NONE, size: 0, color: DOCUMENT_STYLE.table_border_color };
  // ESMO Open asks for no vertical rules or cell shading. Both main tables use
  // a three-rule booktabs layout (top, header, bottom), matching the PDF.
  const cellBorders = (isMainTable || isComparisonTable)
    ? { top: ri => ri === 0 ? border : noBorder,
        bottom: ri => (ri === 0 || ri === rows.length - 1) ? border : noBorder }
    : { top: () => border, bottom: () => border };
  return new Table({
    width: { size: total, type: WidthType.DXA }, columnWidths: ww,
    // The library defaults to a full grid; clear it so only the per-cell rules
    // selected above survive, keeping both tables free of vertical rules.
    borders: { top: noBorder, bottom: noBorder, left: noBorder, right: noBorder,
               insideHorizontal: noBorder, insideVertical: noBorder },
    layout: TableLayoutType.FIXED,
    margins: { top: cellMargin, bottom: cellMargin, left: cellMargin, right: cellMargin },
    rows: [
      // Repeat the total table number and panel as well as the column headings.
      // Later panels remain continuations even when Word repaginates them.
      ...(continuedTable ? [new TableRow({ tableHeader: true, cantSplit: true,
        children: [new TableCell({ columnSpan: rows[0].length,
          width: { size: total, type: WidthType.DXA },
          borders: { top: noBorder, bottom: noBorder, left: noBorder, right: noBorder },
          children: [new Paragraph({ keepNext: true, spacing: { before: 0, after: 0, line: 240 },
            children: headerRuns(`Table ${table}${panel !== "a" ? " (continued)" : ""} (${panel})`, small) })],
        })],
      })] : []),
      ...rows.map((row, ri) => new TableRow({
        tableHeader: ri === 0, cantSplit: true,
        children: row.map((x, ci) => new TableCell({
          borders: { top: cellBorders.top(ri), bottom: cellBorders.bottom(ri), left: noBorder, right: noBorder },
          width: { size: ww[ci], type: WidthType.DXA }, verticalAlign: VerticalAlign.CENTER,
          children: [new Paragraph({
            alignment: isS1d && ci > 0 ? AlignmentType.RIGHT
              : ci >= TABLE_LAYOUT.left_aligned_column_count ? AlignmentType.CENTER : AlignmentType.LEFT,
            // Keep these short logical panels intact; do not bind different panels.
            keepNext: continuedTable && ri < rows.length - 1,
            spacing: { before: 0, after: 0, line: 240 },
            children: ri === 0 ? headerRuns(x, small) : inlineRuns(x, small),
          })],
        }))
      })),
    ],
  });
}

// Read pixel size and the physical resolution (pHYs, pixels per metre) so a
// figure can be placed at its native printed size rather than rescaled.
function pngSize(file) {
  const b = fs.readFileSync(file);
  const at = b.indexOf("pHYs");
  if (at < 0) throw new Error(`Missing pHYs chunk: ${file}`);
  const ppm = b.readUInt32BE(at + 4);
  const width = b.readUInt32BE(16), height = b.readUInt32BE(20);
  return { width, height, widthMm: width / ppm * 1000, heightMm: height / ppm * 1000 };
}

// Parse the limited submission Markdown dialect into DOCX blocks. Scientific
// wording and values are preserved; figure placement uses encoded native size.
// Input: generated Markdown and render switches. Output: paragraph/table blocks.
// Note blocks generated by script 21 sit directly below their table body.
const isTableNote = s => s.startsWith("Percentages are column percentages")
  || s.startsWith("HRs are hazard ratios for death")
  || s.startsWith("Values are hazard ratios for death");

function parseMarkdown(text, { landscape = false, figures = true, cover = false } = {}) {
  const lines = text.replace(/\r/g, "").split("\n");
  const out = [];
  let table = null, panel = null, referenceSection = false, figureCount = 0;
  for (let i = 0; i < lines.length;) {
    let s = lines[i].trim();
    if (!s || s === "---") { i++; continue; }
    if (s === "{{SUPPLEMENTARY_TOC}}") {
      // The contents start on a fresh page so the title block stays intact.
      out.push(new Paragraph({ children: [new PageBreak()] }));
      out.push(new Paragraph({ children: [new TextRun({ text: "Contents", bold: true, size: DOCUMENT_STYLE.heading_1_font_size_half_points })] }));
      out.push(new TableOfContents("Contents", { hyperlink: true, headingStyleRange: "1-2", beginDirty: true }));
      out.push(new Paragraph({ children: [new PageBreak()] }));
      i++; continue;
    }
    if (s === "{{PAGE_BREAK}}") {
      out.push(new Paragraph({ children: [new PageBreak()] }));
      i++; continue;
    }
    const h = s.match(/^(#{1,3})\s+(.+)$/);
    if (h) {
      const level = h[1].length;
      referenceSection = /^(Supplementary )?References$/.test(h[2]);
      const tableHeading = h[2].match(/^Table (S\d+)$/);
      table = tableHeading ? tableHeading[1] : null;
      panel = null;
      out.push(new Paragraph({
        heading: level === 1 ? HeadingLevel.TITLE : level === 2 ? HeadingLevel.HEADING_1 : HeadingLevel.HEADING_2,
        pageBreakBefore: level === 1 && out.length > 0,
        children: inlineRuns(
          h[2],
          level === 1
            ? DOCUMENT_STYLE.title_font_size_half_points
            : level === 2
              ? DOCUMENT_STYLE.heading_1_font_size_half_points
              : DOCUMENT_STYLE.heading_2_font_size_half_points
        ),
      })); i++; continue;
    }
    const panelHeading = s.match(/^\*\*\(([a-f])\)\*\*$/);
    if (table && panelHeading) {
      panel = panelHeading[1];
      out.push(new Paragraph({ keepNext: true, keepLines: true,
        spacing: { before: 0, after: 80, line: 240 }, children: inlineRuns(s) }));
      i++; continue;
    }
    const im = s.match(/^!\[.*?\]\((.+?)\)(?:\{.*\})?$/);
    if (im && figures) {
      const f = path.resolve(OUTPUT, im[1]); const dim = pngSize(f);
      const usableMm = DOCUMENT_STYLE.page_width_mm - 2 * DOCUMENT_STYLE.figure_page_margin_mm;
      if (dim.widthMm > usableMm + FIGURE_AUDIT.size_tolerance_mm) throw new Error(`Figure wider than the figure-page text block: ${f}`);
      const isS1 = path.basename(f).startsWith("FigureS1_");
      out.push(new Paragraph({ alignment: AlignmentType.CENTER,
        pageBreakBefore: figureCount++ > 0, keepNext: isS1, keepLines: true, spacing: {
        before: DOCUMENT_STYLE.figure_space_before_twips,
        after: DOCUMENT_STYLE.figure_space_after_twips,
      },
        children: [new ImageRun({ type: "png", data: fs.readFileSync(f),
          transformation: { width: Math.round(dim.widthMm * MM_TO_PX), height: Math.round(dim.heightMm * MM_TO_PX) },
          altText: { title: path.basename(f), description: path.basename(f), name: path.basename(f) } })] }));
      i++; continue;
    }
    if (s.startsWith("|")) {
      const tbl = [];
      while (i < lines.length && lines[i].trim().startsWith("|")) tbl.push(lines[i++]);
      out.push(makeTable(tbl, landscape, table, panel));
      // Look past the blank separator so a Table 1 note block follows the
      // table directly instead of after an empty spacer paragraph.
      let k = i;
      while (k < lines.length && !lines[k].trim()) k++;
      const next = k < lines.length ? lines[k].trim() : "";
      if (!isTableNote(next)) {
        out.push(new Paragraph({
          spacing: { after: DOCUMENT_STYLE.table_space_after_twips },
          children: [new TextRun("")],
        }));
      }
      continue;
    }
    // Generated table note blocks are body text for pagination but a smaller,
    // tighter paragraph for display.
    if (isTableNote(s)) {
      out.push(new Paragraph({ alignment: AlignmentType.JUSTIFIED, keepLines: true,
        spacing: { before: 0, after: 0, line: 240 },
        children: inlineRuns(s, MAIN_NOTE_SIZE) }));
      i++; continue;
    }
    if (/^-\s+/.test(s)) {
      while (i < lines.length && /^-\s+/.test(lines[i].trim())) {
        out.push(new Paragraph({ numbering: { reference: bulletRef, level: 0 }, spacing: {
          after: DOCUMENT_STYLE.bullet_space_after_twips,
          line: DOCUMENT_STYLE.line_spacing_twips,
        },
          children: inlineRuns(lines[i].trim().replace(/^-\s+/, "")) })); i++;
      }
      continue;
    }
    // Keep each main/S-numbered reference intact, not the whole bibliography.
    if (referenceSection && /^(?:S)?\d+\.\s+/.test(s)) {
      const entry = [s]; i++;
      while (i < lines.length && lines[i].trim()
             && !/^(?:S)?\d+\.\s+|^#/.test(lines[i].trim())) entry.push(lines[i++].trim());
      out.push(new Paragraph({ alignment: AlignmentType.JUSTIFIED,
        keepLines: true, keepNext: false, indent: { left: 360, hanging: 360 }, spacing: {
          after: DOCUMENT_STYLE.body_space_after_twips,
          line: DOCUMENT_STYLE.line_spacing_twips,
        }, children: inlineRuns(entry.join(" ")) }));
      continue;
    }
    const parts = [s]; i++;
    while (i < lines.length && lines[i].trim() && !/^(#{1,3})\s+|^-\s+|^\||^!\[|^---$/.test(lines[i].trim())) parts.push(lines[i++].trim());
    const isFig3 = s.startsWith("**Figure 3.");
    const isS1Caption = s.startsWith("**Supplementary Figure S1.");
    // Cover address/signature lines remain separate, unlike flowing prose.
    const children = cover ? parts.flatMap((part, index) => [
      ...(index ? [new TextRun({ break: 1 })] : []), ...inlineRuns(part),
    ]) : inlineRuns(parts.join(" "), isS1Caption
      ? 2 * PROFILE.latex_style.supplementary_figure_s1_caption_font.size_pt
      : DOCUMENT_STYLE.body_font_size_half_points);
    out.push(new Paragraph({ alignment: cover ? AlignmentType.LEFT : AlignmentType.JUSTIFIED,
      pageBreakBefore: isFig3, keepLines: isFig3 || isS1Caption || cover,
      keepNext: false, spacing: {
        after: cover ? 100 : DOCUMENT_STYLE.body_space_after_twips,
        line: cover ? 264 : isS1Caption ? 240 : DOCUMENT_STYLE.line_spacing_twips,
      }, children }));
  }
  return out;
}

function header() {
  return new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT,
    children: [new TextRun({ text: SHORT_TITLE, font: FONT, size: DOCUMENT_STYLE.header_footer_font_size_half_points, color: DOCUMENT_STYLE.header_text_color })] })] });
}
function footer() {
  const size = DOCUMENT_STYLE.header_footer_font_size_half_points;
  return new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "Page ", font: FONT, size }), new TextRun({ children: [PageNumber.CURRENT], font: FONT, size })] })] });
}
// Return section geometry without rescaling figures or altering source text.
// Landscape sections contain wide tables; figure sections use native margins.
function props(landscape = false, figurePage = false) {
  const figureMargin = Math.round(DOCUMENT_STYLE.figure_page_margin_mm * MM_TO_TWIP);
  const headerGap = Math.round(DOCUMENT_STYLE.header_footer_gap_mm * MM_TO_TWIP);
  const landscapeMargin = DOCUMENT_STYLE.landscape_page_margin_twips;
  const portraitMargin = DOCUMENT_STYLE.portrait_page_margin_twips;
  const margin = figurePage ? { top: figureMargin, right: figureMargin, bottom: figureMargin, left: figureMargin, header: headerGap, footer: headerGap }
    : landscape ? { top: landscapeMargin, right: landscapeMargin, bottom: landscapeMargin, left: landscapeMargin }
      : { top: portraitMargin, right: portraitMargin, bottom: portraitMargin, left: portraitMargin };
  return { type: SectionType.NEXT_PAGE, page: { size: {
    ...A4, orientation: landscape ? PageOrientation.LANDSCAPE : PageOrientation.PORTRAIT,
  }, margin, pageNumbers: { formatType: "decimal" } } };
}
function options(sections, updateFields = false) {
  return new Document({
    ...(updateFields ? { features: { updateFields: true } } : {}),
    creator: DOCUMENT_METADATA.creator,
    title: DOCUMENT_METADATA.title,
    description: DOCUMENT_METADATA.description,
    styles: { default: { document: {
      run: { font: FONT, size: DOCUMENT_STYLE.body_font_size_half_points },
      paragraph: { spacing: { line: DOCUMENT_STYLE.line_spacing_twips } },
    } },
      paragraphStyles: [
        { id: "Title", name: "Title", basedOn: "Normal", next: "Normal", quickFormat: true,
          run: { font: FONT, size: DOCUMENT_STYLE.title_font_size_half_points, bold: true, color: DOCUMENT_STYLE.heading_text_color }, paragraph: { alignment: AlignmentType.CENTER, spacing: { before: DOCUMENT_STYLE.title_space_before_twips, after: DOCUMENT_STYLE.title_space_after_twips }, outlineLevel: 0 } },
        { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
          run: { font: FONT, size: DOCUMENT_STYLE.heading_1_font_size_half_points, bold: true, color: DOCUMENT_STYLE.heading_text_color }, paragraph: { spacing: { before: DOCUMENT_STYLE.heading_1_space_before_twips, after: DOCUMENT_STYLE.heading_1_space_after_twips }, outlineLevel: 0, keepNext: true } },
        { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
          run: { font: FONT, size: DOCUMENT_STYLE.heading_2_font_size_half_points, bold: true, color: DOCUMENT_STYLE.heading_text_color }, paragraph: { spacing: { before: DOCUMENT_STYLE.heading_2_space_before_twips, after: DOCUMENT_STYLE.heading_2_space_after_twips }, outlineLevel: 1, keepNext: true } },
      ] },
    numbering: { config: [{ reference: bulletRef, levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
      style: { paragraph: { indent: { left: DOCUMENT_STYLE.bullet_indent_left_twips, hanging: DOCUMENT_STYLE.bullet_indent_hanging_twips } } } }] }] }, sections,
  });
}

async function save(doc, file) { fs.writeFileSync(path.join(OUTPUT, file), await Packer.toBuffer(doc)); }

// Render the post hoc model label as M with a subscripted PD. The generated
// Markdown keeps the literal M_PD for the claims audit; only the DOCX display
// layer applies the subscript.
const withModelSubscripts = text => text.replaceAll("M_PD", "M~PD~");

async function mainDoc() {
  const text = withModelSubscripts(fs.readFileSync(path.join(OUTPUT, `${OUTPUT_PREFIX}_manuscript.md`), "utf8"));
  const marker = "\n## Tables\n"; const at = text.indexOf(marker);
  const portrait = text.slice(0, at); const tables = text.slice(at + 1);
  await save(options([
    { properties: props(false), headers: { default: header() }, footers: { default: footer() }, children: parseMarkdown(portrait) },
    { properties: props(true), headers: { default: header() }, footers: { default: footer() }, children: parseMarkdown(tables, { landscape: true }) },
  ]), `${OUTPUT_PREFIX}_manuscript.docx`);
}

async function supplementDoc() {
  const text = withModelSubscripts(fs.readFileSync(path.join(OUTPUT, `${OUTPUT_PREFIX}_supplementary_appendix.md`), "utf8"));
  const m1 = "\n## Supplementary Tables\n", m2 = "\n## Supplementary Figures\n";
  const m3 = "\n## Supplementary Data\n", m4 = "\n## Supplementary References\n";
  const a = text.indexOf(m1), b = text.indexOf(m2), c = text.indexOf(m3), d = text.indexOf(m4);
  if (a < 0 || b <= a || c <= b || d <= c) throw new Error("Supplementary section marker not found or out of order");
  await save(options([
    { properties: props(false), headers: { default: header() }, footers: { default: footer() }, children: parseMarkdown(text.slice(0, a)) },
    { properties: props(true), headers: { default: header() }, footers: { default: footer() }, children: parseMarkdown(text.slice(a + 1, b), { landscape: true }) },
    // Figures are placed at native double-column width on narrow-margin pages.
    { properties: props(false, true), headers: { default: header() }, footers: { default: footer() }, children: parseMarkdown(text.slice(b + 1, c)) },
    { properties: props(false), headers: { default: header() }, footers: { default: footer() }, children: parseMarkdown(text.slice(c + 1, d)) },
    { properties: props(false), headers: { default: header() }, footers: { default: footer() }, children: parseMarkdown(text.slice(d + 1)) },
  ], true), `${OUTPUT_PREFIX}_supplementary_appendix.docx`);
}

async function coverDoc() {
  const text = fs.readFileSync(path.join(OUTPUT, "cover_letter.md"), "utf8");
  await save(options([{ properties: props(false), footers: { default: footer() }, children: parseMarkdown(text, { cover: true }) }]), `${OUTPUT_PREFIX}_cover_letter.docx`);
}

async function strobeDoc() {
  // Rebuild the existing checklist from the same source used for its section
  // locations, so revised headings cannot leave the editable copy stale.
  const strobeDir = path.join(ROOT, "manuscript", "strobe");
  const text = fs.readFileSync(path.join(strobeDir, "STROBE_checklist.md"), "utf8");
  const doc = options([{ properties: props(false), footers: { default: footer() }, children: parseMarkdown(text) }]);
  fs.writeFileSync(path.join(strobeDir, "STROBE_checklist.docx"), await Packer.toBuffer(doc));
}

Promise.all([mainDoc(), supplementDoc(), coverDoc(), strobeDoc()]).catch(e => { console.error(e); process.exit(1); });
