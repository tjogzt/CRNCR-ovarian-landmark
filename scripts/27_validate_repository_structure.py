#!/usr/bin/env python3
# ==============================================================================
# File: 27_validate_repository_structure.py
# Purpose: Validate repository naming, headers, configuration, and exclusions.
# Author: Project authors
# Created: 2026-10-19
# Inputs: Repository code, JSON/YAML configuration, and file-tree structure.
# Outputs: English validation diagnostics and a nonzero exit status on failure.
# Runtime parameters: --release-tree checks physical upload cleanliness;
#   config/reproduction_contract.json supplies independently locked expectations.
# Notes: This static gate does not fit models or replace result-dependent audits.
# ==============================================================================

from __future__ import annotations

import argparse
import ast
import io
import json
import os
import re
import subprocess
import sys
import tokenize
from pathlib import Path
from typing import Any

try:
    import yaml
except ModuleNotFoundError:
    yaml = None


ROOT = Path(__file__).resolve().parents[1]
CODE_SUFFIXES = {".R", ".py", ".js"}
SCRIPT_NAME = re.compile(r"^[0-9]{2}_[a-z0-9]+(?:_[a-z0-9]+)*\.(?:R|py|js)$")
R_NAME = re.compile(r"^[0-9]{2}_[a-z0-9]+(?:_[a-z0-9]+)*\.R$")
HEADER_FIELDS = ("Purpose:", "Author:", "Created:", "Inputs:", "Outputs:", "Runtime parameters:")
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")
LOCAL_PATH = re.compile(r"(?:^|[\s'\"(=])(?:/Users/|/home/)")
FORBIDDEN_DIRECTORIES = {"node_modules", "logs", "__pycache__"}
FORBIDDEN_SUFFIXES = {
    ".pyc", ".pyo", ".log", ".aux", ".bbl", ".bcf", ".blg", ".fls",
    ".fdb_latexmk", ".out", ".xdv", ".synctex.gz",
}
FORBIDDEN_NAME_FRAGMENT = "review_copy_with_figures"
TEXT_SUFFIXES = {
    ".R", ".py", ".js", ".json", ".yml", ".yaml", ".md", ".txt",
    ".csv", ".tex", ".bib", ".gitignore", ".editorconfig",
}


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def add_error(errors: list[str], message: str) -> None:
    errors.append(message)


def code_files() -> list[Path]:
    files: list[Path] = []
    for directory in (ROOT / "scripts", ROOT / "R"):
        files.extend(
            path for path in directory.rglob("*")
            if path.is_file() and path.suffix in CODE_SUFFIXES
        )
    return sorted(files)


def validate_filenames_and_headers(errors: list[str]) -> None:
    """Append naming/header violations for autonomous project code files."""
    for path in sorted((ROOT / "scripts").rglob("*")):
        if path.is_file() and path.suffix in CODE_SUFFIXES and not SCRIPT_NAME.fullmatch(path.name):
            add_error(errors, f"Invalid numbered script filename: {relative(path)}")
    for path in sorted((ROOT / "R").rglob("*.R")):
        if not R_NAME.fullmatch(path.name):
            add_error(errors, f"Invalid numbered R filename: {relative(path)}")

    for path in code_files():
        text = path.read_text(encoding="utf-8")
        header = "\n".join(text.splitlines()[:80])
        for field in HEADER_FIELDS:
            if field not in header:
                add_error(errors, f"Missing header field '{field}' in {relative(path)}")


def python_comments(text: str) -> list[str]:
    try:
        return [
            token.string
            for token in tokenize.generate_tokens(io.StringIO(text).readline)
            if token.type == tokenize.COMMENT
        ]
    except tokenize.TokenError:
        return []


def javascript_comments(text: str) -> list[str]:
    return re.findall(r"//[^\n]*|/\*[\s\S]*?\*/", text)


def r_comments(text: str) -> list[str]:
    comments: list[str] = []
    for line in text.splitlines():
        in_single = False
        in_double = False
        escaped = False
        for index, char in enumerate(line):
            if escaped:
                escaped = False
                continue
            if char == "\\":
                escaped = True
                continue
            if char == "'" and not in_double:
                in_single = not in_single
            elif char == '"' and not in_single:
                in_double = not in_double
            elif char == "#" and not in_single and not in_double:
                comments.append(line[index:])
                break
    return comments


def validate_english_code(errors: list[str]) -> None:
    """Flag Chinese comments/explicit diagnostics; semantic review stays human."""
    output_patterns = {
        ".R": re.compile(r"\b(?:message|print|stop|warning|cat)\s*\("),
        ".py": re.compile(r"\b(?:print|raise)\b"),
        ".js": re.compile(r"\b(?:console\.(?:log|error|warn)|throw\s+new\s+Error)\b"),
    }
    for path in code_files():
        text = path.read_text(encoding="utf-8")
        if path.suffix == ".py":
            comments = python_comments(text)
        elif path.suffix == ".js":
            comments = javascript_comments(text)
        else:
            comments = r_comments(text)
        if any(HAN.search(comment) for comment in comments):
            add_error(errors, f"Chinese text found in code comments: {relative(path)}")
        pattern = output_patterns[path.suffix]
        for line_number, line in enumerate(text.splitlines(), start=1):
            if HAN.search(line) and pattern.search(line):
                add_error(
                    errors,
                    f"Chinese text found in explicit output at {relative(path)}:{line_number}",
                )


def validate_worktree_exclusions(errors: list[str]) -> None:
    for directory, directory_names, file_names in os.walk(ROOT):
        current = Path(directory)
        for name in sorted(FORBIDDEN_DIRECTORIES.intersection(directory_names)):
            add_error(
                errors,
                f"Forbidden generated directory exists: {relative(current / name)}",
            )
        directory_names[:] = [
            name for name in directory_names
            if name not in FORBIDDEN_DIRECTORIES and name != ".git"
        ]
        for name in sorted(file_names):
            path = current / name
            rel = relative(path)
            # A clean physical snapshot must not contain editor/OS debris, even
            # when those files would be ignored by Git in a working checkout.
            if name in {".DS_Store", "Thumbs.db"}:
                add_error(errors, f"Forbidden operating-system file exists: {rel}")
            if path.is_symlink() and not path.resolve().is_relative_to(ROOT):
                add_error(errors, f"Symbolic link escapes the submission root: {rel}")
            if rel == "config/paths.yml":
                add_error(errors, f"Forbidden private path exists: {rel}")
            elif FORBIDDEN_NAME_FRAGMENT in name:
                add_error(errors, f"Forbidden local review-copy file exists: {rel}")
            elif any(name.endswith(suffix) for suffix in FORBIDDEN_SUFFIXES):
                add_error(errors, f"Forbidden generated file exists: {rel}")


def validate_exclusions(errors: list[str]) -> None:
    required_rules = {
        "config/paths.yml", "node_modules/", "logs/", "__pycache__/", "*.py[cod]",
        "*.log", "*.aux", "*.bbl", "*.bcf", "*.blg", "*.fls", "*.fdb_latexmk",
        "*.out", "*.xdv", "*.synctex.gz",
        "manuscript/submission/*_review_copy_with_figures.*",
    }
    ignore_path = ROOT / ".gitignore"
    ignore_rules = {
        line.strip()
        for line in ignore_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    for rule in sorted(required_rules.difference(ignore_rules)):
        add_error(errors, f"Missing required Git exclusion: {rule}")

    try:
        tracked_result = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "-z"],
            check=True,
            capture_output=True,
            text=False,
        )
        tracked = [item.decode("utf-8") for item in tracked_result.stdout.split(b"\0") if item]
    except (FileNotFoundError, subprocess.CalledProcessError):
        tracked = []

    for rel in tracked:
        parts = Path(rel).parts
        name = Path(rel).name
        if rel == "config/paths.yml" or FORBIDDEN_DIRECTORIES.intersection(parts):
            add_error(errors, f"Forbidden generated or private path is tracked: {rel}")
        elif FORBIDDEN_NAME_FRAGMENT in name:
            add_error(errors, f"Forbidden local review-copy file is tracked: {rel}")
        elif any(name.endswith(suffix) for suffix in FORBIDDEN_SUFFIXES):
            add_error(errors, f"Forbidden generated file is tracked: {rel}")


def is_text_candidate(path: Path) -> bool:
    return path.name in {"Makefile", "DESCRIPTION", "LICENSE"} or path.suffix in TEXT_SUFFIXES


def validate_local_paths(errors: list[str]) -> None:
    for path in ROOT.rglob("*"):
        if not path.is_file() or not is_text_candidate(path):
            continue
        if FORBIDDEN_DIRECTORIES.intersection(path.relative_to(ROOT).parts):
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(lines, start=1):
            if path.is_relative_to(ROOT / "docs") and re.search(r"<[^>]+>", line):
                continue
            if LOCAL_PATH.search(line):
                add_error(errors, f"Local absolute path found at {relative(path)}:{line_number}")


def parse_yaml_file(path: Path) -> Any:
    if yaml is not None:
        with path.open(encoding="utf-8") as handle:
            return yaml.safe_load(handle)
    result = subprocess.run(
        [
            "Rscript", "-e",
            "cat(jsonlite::toJSON(yaml::read_yaml(commandArgs(TRUE)[1]), auto_unbox=TRUE))",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def load_structured_files(errors: list[str]) -> dict[Path, Any]:
    parsed: dict[Path, Any] = {}
    for path in sorted((ROOT / "config").glob("*")):
        if path.suffix not in {".json", ".yml", ".yaml"}:
            continue
        try:
            if path.suffix == ".json":
                with path.open(encoding="utf-8") as handle:
                    parsed[path] = json.load(handle)
            else:
                parsed[path] = parse_yaml_file(path)
        except (json.JSONDecodeError, OSError, subprocess.CalledProcessError, ValueError) as error:
            add_error(errors, f"Cannot parse {relative(path)}: {error}")
        except Exception as error:
            if yaml is not None and isinstance(error, yaml.YAMLError):
                add_error(errors, f"Cannot parse {relative(path)}: {error}")
            else:
                raise
    return parsed


def nested(config: dict[str, Any], dotted_path: str) -> Any:
    value: Any = config
    for key in dotted_path.split("."):
        if not isinstance(value, dict) or key not in value:
            raise KeyError(dotted_path)
        value = value[key]
    return value


def validate_analysis_config(parsed: dict[Path, Any], errors: list[str]) -> None:
    path = ROOT / "config" / "analysis.yml"
    analysis = parsed.get(path)
    if not isinstance(analysis, dict):
        add_error(errors, "config/analysis.yml must contain a mapping")
        return

    # Independent regression expectations are versioned as configuration data;
    # they never supply patient observations or override analysis inputs.
    contract = parsed.get(ROOT / "config" / "reproduction_contract.json")
    if not isinstance(contract, dict) or not isinstance(contract.get("analysis"), dict):
        add_error(errors, "Missing analysis reproduction contract")
        return
    expected = contract["analysis"]
    for dotted_path, expected_value in expected.items():
        try:
            actual = nested(analysis, dotted_path)
        except KeyError:
            add_error(errors, f"Missing key analysis configuration: {dotted_path}")
            continue
        if actual != expected_value:
            add_error(
                errors,
                f"Unexpected analysis configuration value for {dotted_path}: {actual!r}",
            )

    response_expected = contract.get("response")
    if not isinstance(response_expected, dict):
        add_error(errors, "Missing response-level reproduction contract")
        return
    for dotted_path, expected_value in response_expected.items():
        try:
            if nested(analysis, dotted_path) != expected_value:
                add_error(errors, f"Invalid response-level order: {dotted_path}")
        except KeyError:
            add_error(errors, f"Missing key analysis configuration: {dotted_path}")
    for dotted_path in ("response.equivalence_margin", "response.relaxed_equivalence_margin"):
        try:
            value = nested(analysis, dotted_path)
            if not isinstance(value, list) or len(value) != 2:
                add_error(errors, f"Equivalence margin must have length two: {dotted_path}")
        except KeyError:
            add_error(errors, f"Missing key analysis configuration: {dotted_path}")


def validate_document_style(parsed: dict[Path, Any], errors: list[str]) -> None:
    path = ROOT / "config" / "submission_profile.json"
    profile = parsed.get(path)
    if not isinstance(profile, dict):
        add_error(errors, "config/submission_profile.json must contain an object")
        return
    style = profile.get("document_style")
    if not isinstance(style, dict):
        add_error(errors, "Missing document_style object in submission profile")
        return
    required = {
        "font_family", "monospace_font_family", "page_width_mm",
        "portrait_table_width_twips", "landscape_table_width_twips",
        "landscape_page_width_twips", "landscape_page_height_twips",
        "body_font_size_half_points", "title_font_size_half_points",
        "heading_1_font_size_half_points", "heading_2_font_size_half_points",
        "header_footer_font_size_half_points", "line_spacing_twips",
        "portrait_page_margin_twips", "landscape_page_margin_twips",
        "figure_page_margin_mm",
    }
    for field in sorted(required.difference(style)):
        add_error(errors, f"Missing document style field: {field}")
    contract = parsed.get(ROOT / "config" / "reproduction_contract.json")
    if not isinstance(contract, dict) or not isinstance(contract.get("document_style"), dict):
        add_error(errors, "Missing document-style reproduction contract")
        return
    expected = contract["document_style"]
    for field, expected_value in expected.items():
        if field in style and style[field] != expected_value:
            add_error(errors, f"Unexpected document style value for {field}: {style[field]!r}")
    # LaTeX layout is configured beside the DOCX layout; table font blocks
    # need size, leading and column separation so script 23 never falls back
    # to literals embedded in the build logic.
    latex = profile.get("latex_style")
    if not isinstance(latex, dict):
        add_error(errors, "Missing latex_style object in submission profile")
        return
    for field in ("base_font_size_pt", "text_margin_mm", "wide_table_margin_mm",
                  "wide_table_headsep_mm", "wide_table_footskip_mm"):
        value = latex.get(field)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
            add_error(errors, f"latex_style.{field} must be a positive number")
    for block in ("main_table_font", "main_comparison_table_font",
                  "supplementary_table_font", "supplementary_table_s1_font",
                  "supplementary_table_s2_a_font", "supplementary_table_s2_b_font"):
        spec = latex.get(block)
        if not isinstance(spec, dict):
            add_error(errors, f"Missing latex_style.{block} object")
            continue
        for field in ("size_pt", "leading_pt", "column_separation_pt"):
            value = spec.get(field)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                add_error(errors, f"latex_style.{block}.{field} must be a positive number")
    for block in ("supplementary_table_caption_font", "supplementary_table_heading_font"):
        spec = latex.get(block)
        if not isinstance(spec, dict):
            add_error(errors, f"Missing latex_style.{block} object")
            continue
        for field in ("size_pt", "leading_pt"):
            value = spec.get(field)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                add_error(errors, f"latex_style.{block}.{field} must be a positive number")
    orientation = latex.get("supplementary_table_s1_orientation")
    if orientation not in {"portrait", "landscape"}:
        add_error(errors, "latex_style.supplementary_table_s1_orientation must be 'portrait' or 'landscape'")
    per_table = latex.get("supplementary_table_fonts")
    if not isinstance(per_table, dict):
        add_error(errors, "Missing latex_style.supplementary_table_fonts object")
    else:
        expected = {"S2", "S3", "S4", "S5", "S6", "S7"}
        if set(per_table) != expected:
            add_error(errors, "latex_style.supplementary_table_fonts must define exactly S2-S7")
        for table, spec in per_table.items():
            if not isinstance(spec, dict):
                add_error(errors, f"latex_style.supplementary_table_fonts.{table} must be an object")
                continue
            for field in ("size_pt", "leading_pt", "column_separation_pt"):
                value = spec.get(field)
                if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                    add_error(errors, f"latex_style.supplementary_table_fonts.{table}.{field} must be a positive number")
    s1_fractions = latex.get("supplementary_table_s1_a_fractions")
    if not isinstance(s1_fractions, list):
        add_error(errors, "Missing latex_style.supplementary_table_s1_a_fractions list")
    else:
        if len(s1_fractions) != 12:
            add_error(errors, "latex_style.supplementary_table_s1_a_fractions must contain 12 values")
        valid = True
        for index, value in enumerate(s1_fractions):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                add_error(errors, f"latex_style.supplementary_table_s1_a_fractions[{index}] must be a positive number")
                valid = False
        if valid and abs(sum(s1_fractions) - 1.0) > 5e-4:
            add_error(errors, "latex_style.supplementary_table_s1_a_fractions must sum to 1")
    s2_fractions = latex.get("supplementary_table_s2_a_fractions")
    if not isinstance(s2_fractions, list):
        add_error(errors, "Missing latex_style.supplementary_table_s2_a_fractions list")
    else:
        if len(s2_fractions) != 7:
            add_error(errors, "latex_style.supplementary_table_s2_a_fractions must contain 7 values")
        valid = True
        for index, value in enumerate(s2_fractions):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                add_error(errors, f"latex_style.supplementary_table_s2_a_fractions[{index}] must be a positive number")
                valid = False
        if valid and abs(sum(s2_fractions) - 1.0) > 5e-4:
            add_error(errors, "latex_style.supplementary_table_s2_a_fractions must sum to 1")
    s2b_fractions = latex.get("supplementary_table_s2_b_fractions")
    if not isinstance(s2b_fractions, list):
        add_error(errors, "Missing latex_style.supplementary_table_s2_b_fractions list")
    else:
        if len(s2b_fractions) != 14:
            add_error(errors, "latex_style.supplementary_table_s2_b_fractions must contain 14 values")
        valid = True
        for index, value in enumerate(s2b_fractions):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                add_error(errors, f"latex_style.supplementary_table_s2_b_fractions[{index}] must be a positive number")
                valid = False
        if valid and abs(sum(s2b_fractions) - 1.0) > 5e-4:
            add_error(errors, "latex_style.supplementary_table_s2_b_fractions must sum to 1")
    s6_fractions = latex.get("supplementary_table_s6_fractions")
    if not isinstance(s6_fractions, list):
        add_error(errors, "Missing latex_style.supplementary_table_s6_fractions list")
    else:
        if len(s6_fractions) != 9:
            add_error(errors, "latex_style.supplementary_table_s6_fractions must contain 9 values")
        valid = True
        for index, value in enumerate(s6_fractions):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                add_error(errors, f"latex_style.supplementary_table_s6_fractions[{index}] must be a positive number")
                valid = False
        if valid and abs(sum(s6_fractions) - 1.0) > 5e-4:
            add_error(errors, "latex_style.supplementary_table_s6_fractions must sum to 1")
    for panel, count in (("a", 10), ("b", 5)):
        key = f"supplementary_table_s7_{panel}_fractions"
        s7_fractions = latex.get(key)
        if not isinstance(s7_fractions, list):
            add_error(errors, f"Missing latex_style.{key} list")
            continue
        if len(s7_fractions) != count:
            add_error(errors, f"latex_style.{key} must contain {count} values")
        valid = True
        for index, value in enumerate(s7_fractions):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                add_error(errors, f"latex_style.{key}[{index}] must be a positive number")
                valid = False
        if valid and abs(sum(s7_fractions) - 1.0) > 5e-4:
            add_error(errors, f"latex_style.{key} must sum to 1")
    s4_fractions = latex.get("supplementary_table_s4_fractions")
    if not isinstance(s4_fractions, list):
        add_error(errors, "Missing latex_style.supplementary_table_s4_fractions list")
    else:
        if len(s4_fractions) != 15:
            add_error(errors, "latex_style.supplementary_table_s4_fractions must contain 15 values")
        valid = True
        for index, value in enumerate(s4_fractions):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                add_error(errors, f"latex_style.supplementary_table_s4_fractions[{index}] must be a positive number")
                valid = False
        if valid and abs(sum(s4_fractions) - 1.0) > 5e-4:
            add_error(errors, "latex_style.supplementary_table_s4_fractions must sum to 1")
    s4_width = latex.get("supplementary_table_s4_width_mm")
    if (isinstance(s4_width, bool) or not isinstance(s4_width, (int, float))
            or s4_width <= 0 or s4_width > 277):
        add_error(errors, "latex_style.supplementary_table_s4_width_mm must be a positive width within 277 mm")
    s5_fonts = latex.get("supplementary_table_s5_fonts")
    if not isinstance(s5_fonts, dict):
        add_error(errors, "Missing latex_style.supplementary_table_s5_fonts object")
    else:
        if set(s5_fonts) != set("abcde"):
            add_error(errors, "latex_style.supplementary_table_s5_fonts must define exactly a-e")
        for letter, spec in s5_fonts.items():
            if not isinstance(spec, dict):
                add_error(errors, f"latex_style.supplementary_table_s5_fonts.{letter} must be an object")
                continue
            for field in ("size_pt", "leading_pt", "column_separation_pt"):
                value = spec.get(field)
                if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                    add_error(errors, f"latex_style.supplementary_table_s5_fonts.{letter}.{field} must be a positive number")
    s5_columns = {"a": 11, "b": 6, "c": 7, "d": 6, "e": 6}
    for letter, expected_count in s5_columns.items():
        fractions = latex.get(f"supplementary_table_s5_{letter}_fractions")
        if not isinstance(fractions, list):
            add_error(errors, f"Missing latex_style.supplementary_table_s5_{letter}_fractions list")
            continue
        if len(fractions) != expected_count:
            add_error(errors, f"latex_style.supplementary_table_s5_{letter}_fractions must contain {expected_count} values")
        valid = True
        for index, value in enumerate(fractions):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
                add_error(errors, f"latex_style.supplementary_table_s5_{letter}_fractions[{index}] must be a positive number")
                valid = False
        if valid and abs(sum(fractions) - 1.0) > 5e-4:
            add_error(errors, f"latex_style.supplementary_table_s5_{letter}_fractions must sum to 1")
    for letter in "bcde":
        width = latex.get(f"supplementary_table_s5_{letter}_width_mm")
        if (isinstance(width, bool) or not isinstance(width, (int, float))
                or width <= 0 or width > 277):
            add_error(errors, f"latex_style.supplementary_table_s5_{letter}_width_mm must be a positive width within 277 mm")


def validate_syntax(errors: list[str]) -> None:
    for path in sorted((ROOT / "scripts").glob("*.py")):
        try:
            ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        except SyntaxError as error:
            add_error(errors, f"Python syntax error in {relative(path)}:{error.lineno}: {error.msg}")


def main() -> int:
    # Default mode suits a working checkout: build artefacts may exist locally
    # because .gitignore keeps them out of commits. --release-tree additionally
    # requires the physical tree to be free of them, which is the gate used
    # before a directory snapshot is uploaded or archived.
    parser = argparse.ArgumentParser(description="Validate repository structure.")
    parser.add_argument(
        "--release-tree", action="store_true",
        help="Also fail when ignored build artefacts exist in the working tree.",
    )
    args = parser.parse_args()

    errors: list[str] = []
    validate_filenames_and_headers(errors)
    validate_english_code(errors)
    if args.release_tree:
        validate_worktree_exclusions(errors)
    validate_exclusions(errors)
    validate_local_paths(errors)
    parsed = load_structured_files(errors)
    validate_analysis_config(parsed, errors)
    validate_document_style(parsed, errors)
    validate_syntax(errors)

    if errors:
        print("Repository structure validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    mode = "release-tree" if args.release_tree else "working-checkout"
    print(f"Repository structure validation passed ({mode} mode).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
