# ==============================================================================
# File: Makefile
# Purpose: Provide standard validation and reproducible build entry points.
# Author: Project authors
# Created: 2026-10-15
# Inputs: Numbered scripts, configured public data sources, and manuscript source.
# Outputs: Analysis results and configured journal-submission files.
# ==============================================================================

.PHONY: check cv-check repo-check release-check pipeline clinical sensitivity publication manuscript latex audit zh zh-check clean

check:
	python3 scripts/27_validate_repository_structure.py
	Rscript -e 'files <- list.files(".", pattern="[.]R$$", recursive=TRUE, full.names=TRUE); invisible(lapply(files, parse)); cat("R syntax check passed\n")'
	python3 -c 'import ast,json,pathlib; [ast.parse(p.read_text(), filename=str(p)) for p in pathlib.Path("scripts").glob("*.py")]; [json.loads(p.read_text()) for p in pathlib.Path("config").glob("*.json")]; print("Python and JSON syntax checks passed")'
	node --check scripts/22_generate_submission_docx.js
	Rscript -e 'source("R/00_project_configuration.R"); cfg <- load_project_configuration(normalizePath(".")); invisible(get_figure_style(cfg$$root)); validate_cv_concordance_invariants(); cat("Runtime configuration checks passed\n")'
	python3 scripts/37_check_chinese_sync.py

cv-check:
	Rscript -e 'source("R/00_project_configuration.R"); validate_cv_concordance_invariants()'

repo-check:
	python3 scripts/27_validate_repository_structure.py

# Strict gate for an uploadable snapshot: removes ignored build artefacts first,
# then requires the physical tree to contain none of them.
release-check: clean
	python3 scripts/27_validate_repository_structure.py --release-tree

pipeline:
	Rscript scripts/00_run_pipeline.R

clinical:
	Rscript scripts/17_fit_therapy_end_landmark.R
	Rscript scripts/18_analyze_selection_regimen_power.R
	Rscript scripts/19_analyze_hgsoc_sensitivity.R
	Rscript scripts/34_response_partition_calibration_sensitivity.R
	Rscript scripts/35_landmark_selection_tipping.R
	Rscript scripts/20_build_manuscript_outputs.R

# Exploratory response-partition scan, calibration and E-values only.
sensitivity:
	Rscript scripts/34_response_partition_calibration_sensitivity.R

# Publication-only rebuild from the existing locked results; no model fitting.
publication:
	CRNCR_PYTHON="$${CRNCR_PYTHON:-$$(command -v python3)}" Rscript scripts/20_build_manuscript_outputs.R --render-only

manuscript:
	python3 scripts/21_build_esmo_submission.py

latex:
	python3 scripts/23_build_submission_latex.py

audit:
	python3 scripts/24_validate_manuscript_claims.py
	python3 scripts/26_audit_figure_typography.py

# Build the Chinese review edition from the current English sources.
# Required after any change to the English manuscript, supplement or cover letter.
zh:
	python3 scripts/36_build_chinese_review.py

# Fail when the Chinese edition predates its recorded English sources or figures.
zh-check:
	python3 scripts/37_check_chinese_sync.py

# Remove rebuildable local artefacts that .gitignore excludes from commits:
# LaTeX auxiliaries, logs, Python caches, Node dependencies and the local
# review copy with embedded figures. Submission DOCX/PDF/TeX files are kept.
clean:
	for f in manuscript/submission/*_manuscript.tex manuscript/submission/*_manuscript_review_copy_with_figures.tex manuscript/submission/*_supplementary_appendix.tex manuscript/submission/*_cover_letter.tex; do \
		test ! -e "$$f" || latexmk -c "$$f" >/dev/null 2>&1 || true; \
	done
	find . -path ./.git -prune -o -type f \( -name '*.aux' -o -name '*.bbl' -o -name '*.bcf' -o -name '*.blg' \
		-o -name '*.fls' -o -name '*.fdb_latexmk' -o -name '*.out' -o -name '*.toc' -o -name '*.xdv' -o -name '*.synctex.gz' \
		-o -name '*.log' -o -name '*.py[cod]' -o -name '.DS_Store' \) -print -exec rm -f {} +
	rm -f manuscript/submission/*_review_copy_with_figures.*
	rm -rf logs node_modules manuscript/zh/build
	find . -path ./.git -prune -o -type d -name '__pycache__' -prune -exec rm -rf {} +
