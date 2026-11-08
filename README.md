# Objective response obscures the prognostic difference between complete and partial response in ovarian cancer

This public repository contains the reproducible analysis code, configuration and result tables for the study:

> **Objective response obscures the prognostic difference between complete and partial response in ovarian cancer: a TCGA-OV landmark analysis**

**Publication scope (2026-11-08).** This mirror publishes the analysis code, versioned configuration and formal result tables. Manuscript sources, submission PDFs, the STROBE checklist, the author-only Chinese review edition and internal review archives are withheld while the manuscript is under review. Targets that build the manuscript (`make manuscript`, `make latex`, `make zh`, `make zh-check`) and the Chinese-sync step inside `make check` therefore cannot run here; `make repo-check` and the analysis stages can. A Zenodo DOI will be minted from the `v1.0.0` release and then recorded in `CITATION.cff`.

## Scientific scope

The project compares four representations of first-line response—four-category response, objective response, a complete-response threshold, and a post hoc progressive-disease step—using a patient-specific landmark at the end of first-line therapy. Among TCGA-OV patients alive at that landmark, objective response concealed a large survival difference: each non-complete-response category had a higher hazard of death than complete response (adjusted NCR-versus-CR HR 3.59, 95% CI 2.61–4.94), and the objective-response constraint was rejected (P=8.5×10⁻¹⁰), driven by the PR–CR difference. CR versus NCR was the best-supported single-parameter coding, but no clear discrimination advantage over four categories was demonstrated, the plateau test was underpowered and was rejected in the only external four-class cohort, and the contrast was not established in patients without macroscopic residual disease. Equivalence among NCR states and any additional risk from progressive disease remain unresolved. This is a prognostic association and is not evidence that increasing the complete-response rate causes longer survival.

## Repository layout

```text
.
├── R/                         Shared configuration helpers
├── scripts/                   Numbered analysis and manuscript-build scripts
├── config/                    Versioned scientific settings and private path template
├── data/
│   ├── processed/             Small public-data derivatives required for clinical reproduction
│   ├── supplementary/         Supplementary Data 1-2
│   └── external/              Untracked raw-data cache
├── results/
│   ├── figures/               Formal main and supplementary figures
│   └── tables/                Formal tables (main/, supplementary/) and compact locked analysis outputs
├── docs/                      Workflow, data-source, and reproducibility documentation
└── environment/               Package versions and recorded R sessions
```

The original exploratory workspace, raw caches, temporary ESTIMATE files, logs, and large gene-level intermediate tables are intentionally excluded, as are the manuscript sources and submission files described under publication scope.

## Quick start

### 1. Install dependencies

Use R 4.5.0. Required R packages are listed in `DESCRIPTION`; the exact installed environment is recorded in `renv.lock` and `environment/`.

```bash
Rscript -e 'install.packages("renv"); renv::restore()'
python3 -m pip install -r environment/python_requirements.txt
npm ci
```

The recorded environment contains packages from adjacent Bioconductor releases and is therefore validated primarily on the recorded machine; see `docs/REPRODUCIBILITY.md`. A package lock is not a guarantee of compatibility on every machine. System requirements for manuscript rendering are listed in `environment/system_requirements.txt`. If `node_modules/` is absent, restore the locked DOCX dependency with `npm ci`; never commit the restored directory. Required Python modules are listed in `environment/python_requirements.txt`.

### 2. Configure local data paths

```bash
cp config/paths.example.yml config/paths.yml
```

Edit `config/paths.yml`, or set the documented environment variables. The private paths file is excluded by `.gitignore`. No local absolute path is embedded in the analysis code.

### 3. Validate the repository

```bash
make repo-check     # repository structure and configuration only
make check          # repository, R, Python, JSON, and JavaScript checks (requires the manuscript sources)
make release-check  # runs make clean, then requires a tree free of ignored build artefacts
```

The repository check requires numbered `NN_snake_case` code filenames, complete English script headers, English code comments and explicit diagnostics, parseable JSON/YAML, portable paths, and the configured GitHub exclusions.

The nonpublic reviewer snapshot and the journal submission files are not distributed in this repository; the frozen snapshot is provided only through the journal's confidential review channel.

### 4. Reproduce the primary clinical analyses

The compact public-data derivatives needed by scripts 17-20 are included, together with the locked stage 14-16 outputs that stage 20 reads.

```bash
make clinical
```

This reconstructs the therapy-end landmark analysis, landmark selection tipping analysis, selection/regimen/power analyses, operational HGSOC sensitivity analysis, and manuscript display items.

### 5. Run the complete workflow

After acquiring the external source files described in `docs/DATA_SOURCES.md` and verifying them against `docs/raw_input_manifest.csv`:

```bash
Rscript scripts/00_run_pipeline.R
```

To reproduce against a frozen local GDC cache without live API access, set `CRNCR_OFFLINE_RAW=1`.

Optional inclusive stage limits are supported:

```bash
Rscript scripts/00_run_pipeline.R --start=17 --stop=20
```

The detailed dependency graph is in `docs/WORKFLOW.md`.

## Manuscript builds

```bash
# Resolve the dependency-installed Python, including shell aliases/virtualenvs.
export CRNCR_PYTHON="$(python3 -c 'import sys; print(sys.executable)')"
make publication
python3 scripts/21_build_esmo_submission.py
python3 scripts/23_build_submission_latex.py
```

`make publication` reads locked statistics and preserved vector panels without Cox refitting, cross-validation or date resampling. It applies the explicit publication policy: the retracted source and pools containing it are excluded from formal results; treatment-end-date scenarios are described without pooled inferential intervals or tests. Upstream legacy computations are retained as historical evidence, not as validation of those inferences.

The DOCX build uses `docx` from `package-lock.json`; the PDF build uses Pandoc, XeLaTeX, and latexmk. In the private working tree these commands write to `manuscript/submission/`, which is not part of this mirror.

## Configuration policy

Scientific thresholds, random seeds, landmark windows, resampling counts, response levels, expression/QC inclusion rules, cohort/regimen definitions, RMST sensitivity horizons, molecular decision thresholds, WGCNA fallback/stability settings, multi-omics definitions, external-validation criteria and pan-cancer event minima are versioned in `config/analysis.yml`. The loader validates groups, types, finite values, ranges, ordering and nonempty lists; missing required settings fail rather than silently falling back. Portable path defaults are read from `config/paths.example.yml`; optional private `config/paths.yml` and environment variables override them. Relative paths are resolved from the repository root, not the shell working directory. Machine-specific absolute paths may be used privately but must not be embedded in committed code.

`config/submission_profile.json` holds document formatting, table layout, the shared semantic figure style, artwork requirements and the publication-only exclusion/panel policy. `config/workflow.json` holds the ordered scientific stage filenames. `config/reference_overrides.json` records previously verified bibliography entries and retraction/DOI annotations that are not supplied by the frozen PubMed records. `config/reproduction_contract.json` holds independent baseline expectations for regression validation, not fitting inputs. See `docs/CODE_AND_CONFIGURATION.md` for the distinction between scientific settings, real observations, mathematical constants, regression fixtures and publication layout.

Shared configuration and validation are consolidated, while scientific stages remain separate because their estimands, dependencies, and failure rules differ. Statistical bootstrap, covariate multiple imputation, permutation-based tests, split-half resampling, cross-validation and power simulation operate on observed data and are retained. Treatment-end-date draws are reported only as descriptive scenarios; their legacy pooled inference is not used in the submission. No mock or synthetic patients enter the primary analysis. The landmark-selection sensitivity code deliberately assigns hypothetical outcomes to excluded patients; these extreme-allocation scenarios are not statistical bounds and do not establish the direction of selection bias.

## Repository governance

Code files under `scripts/` and `R/` use `NN_snake_case` names and preserve the numbered scientific stage boundaries. GitHub exclusions cover private `config/paths.yml`, raw caches, `node_modules/`, logs, Python bytecode/cache directories and LaTeX auxiliary files. Run `make repo-check` in a working checkout to detect naming, header, language, path, configuration, ignore-rule and tracked-artifact violations. `make release-check` removes local build artefacts before checking the physical tree; do not use that destructive target on historical baselines.

For a non-destructive packaging alternative:

```bash
python3 scripts/29_prepare_release_snapshot.py                          # dry-run
python3 scripts/29_prepare_release_snapshot.py --write --destination ../release_snapshot
python3 ../release_snapshot/scripts/27_validate_repository_structure.py --release-tree
```

The destination must not already exist. The packaging utility reads `config/release_policy.json`, verifies every copy, writes a new checksum inventory and leaves the source untouched. It does not commit or publish anything. A dry-run can succeed while the working checkout still contains excluded caches; the strict `--release-tree` check is the physical-cleanliness gate.

## Data policy

All patient and sample identifiers in this repository originate from public TCGA, GDC, GEO, cBioPortal, or curatedOvarianData records. No institutional cohort is included. Large raw files and redistributable third-party databases are downloaded by the user and are not committed. See `data/README.md` and `docs/DATA_SOURCES.md`.

## Locked outputs

The submitted figures, tables, and case-level supplementary data are under `results/` and `data/supplementary/`. `results/tables/main/` and `results/tables/supplementary/` hold the CSVs behind Tables 1–2 and Supplementary Tables S1–S4, named by table number (S1, external cohorts; S2, operational HGSOC; S3, post hoc robustness analyses; S4, pan-cancer label audit). Compact molecular summaries are retained, while a gene-level file exceeding GitHub's 100 MiB limit and other reproducible intermediates are excluded. File checksums are recorded in `docs/SHA256SUMS.txt`.

## Important limitations

- Response is a post-treatment variable; diagnosis-origin analyses are sensitivity analyses only.
- Actual response-assessment dates are unavailable; treatment end is the primary landmark proxy.
- TCGA response labels are legacy chart-abstracted fields and were not centrally RECIST-verified.
- External cohorts are small and heterogeneous; one retracted-source cohort is used only for sensitivity analysis.
- The progressive-disease step remains underpowered and unresolved.
- Results are prognostic associations, not causal treatment-effect estimates.

## License and release

Code and documentation are released under the MIT License (`LICENSE.md`). Public source data remain subject to the terms of their original providers. Citation metadata are in `CITATION.cff`. The code and result tables in this repository are public. The manuscript remains under review and is not posted as a preprint. A Zenodo DOI will be minted from the `v1.0.0` GitHub release and recorded in `CITATION.cff`.
