# Code and configuration policy

## Scientific invariants

The clean repository is a maintainability refactor of the author-approved submission, not a new analysis. Preserve cohort membership, endpoint definitions, response ordering, landmark restrictions, model formulas, missing-data rules, RNG sequence, fold assignments, bootstrap draws and reported estimates. The separate 36-month time-dependent AUC proposal remains pending and must not be implemented without additional author approval.

In particular, retain the historical rounded Wald multiplier where used rather than replacing it with a different quantile, and retain the stage-specific day-to-month conversions. A 120-month plotting limit is a display choice, not administrative censoring. A non-significant NCR constraint test does not establish equivalence. Do not substitute similar-looking algorithms when they target different estimands.

The separately author-approved five-item reporting revision narrows interpretation and excludes designated results from formal publication displays without refitting upstream analyses. Stage 20 now dispatches publication-only utility 30; the old refitting path is explicit rather than the default. Retain clean frozen vector panels for unchanged artwork regions and verify their source hashes. Cohort exclusions and layout parameters belong to the publication policy, not hidden renderer literals.

## Naming and stage boundaries

Autonomous code files use `NN_short_english_function.R`, `.py` or `.js`, with lowercase underscore-separated words. Keep existing stage numbers 00-27: they are cited in workflow and provenance records. Shared R configuration stays in `R/00_project_configuration.R`. Shared Python submission utilities use `scripts/28_submission_utilities.py`, loaded explicitly rather than relying on an unnumbered import shim.

Consolidate common configuration and portable build helpers, but retain separate scientific stages whose data dependencies, estimands or failure rules differ. Filename changes are not an objective in themselves when the existing names already meet the rule. Conventional infrastructure names such as `Makefile`, `README.md`, `DESCRIPTION`, `package.json` and dependency lockfiles keep their standard names.

## English documentation

Each code file declares its purpose, credited authors, original creation date, inputs, outputs and runtime parameters. Retain inherited author/date attribution; do not infer individual authorship or manufacture a date from file modification time. Newly created helpers declare their own creation date. Function comments explain relevant input/return contracts, mathematical assumptions, missing-data handling or failure boundaries. Comments should explain why a branch exists rather than repeat obvious syntax. Explicit diagnostics and scientific display text are English. Public-source identifiers are preserved verbatim.

## Types of values

| Type | Location and rule |
|---|---|
| Patient/sample observations and estimated quantities | Read public source files or derived result tables; never substitute a hand-written cohort or fitted number. |
| Scientific design settings | Version in `config/analysis.yml`; preserve historical values, types and ordering during refactoring. These are protocol choices, not quantities to estimate from outcome data. |
| Portable paths | Read `config/paths.example.yml`, optional ignored `config/paths.yml`, or documented environment variables. Resolve relative overrides against the repository root. |
| Source identifiers and biological selections | Version their ordered definitions; keep cohort-specific parsing and raw-source column schemas explicit. Selected pathway genes still come from the measured expression matrix and frozen MSigDB sets. |
| Citation metadata | Read frozen PubMed records plus `config/reference_overrides.json`; the overrides preserve previously verified source metadata, not invented references. |
| Document/artwork settings | Version in `config/submission_profile.json`, including semantic style, table-layout rules and the explicit publication-only exclusion/panel policy. |
| Workflow order | Read `config/workflow.json`; verify the numbered order and script existence. |
| Independent regression expectations | Read `config/reproduction_contract.json` and manuscript-claim configuration; they check invariants, never supply fitting inputs. |
| Mathematical constants, indexes and format schema | Keep transparent coefficients, zero/one indicators, contrast definitions, array indexes and standard unit conversions in the algorithm. Removing them would make the code incorrect or obscure. |
| Fixed validation fixtures | Keep explicitly labelled, isolated test vectors. They test perfect/reversed concordance, ties, missing scores and invalid event encodings; they are not patient data. |

Scientific settings cannot all be learned dynamically from a real dataset: significance levels, model definitions and prespecified gene panels are choices that must remain explicit and versioned. Moving their storage to configuration does not authorize changing them.

## Statistical simulation is not mock study data

Bootstrap resampling, stochastic date imputation, permutation/Monte-Carlo tests, split-half stability, repeated CV and power simulations are retained as requested. Resampling and imputation draw on observed records; power calculations deliberately simulate event/censoring times under specified effect scenarios. Neither is a fabricated clinical input cohort. Comments must distinguish these procedures rather than claim that every random draw is simple observed-data resampling. The treatment-end-date draws are now reported only as descriptive scenarios: their legacy pooled intervals/tests are preserved for traceability, not presented as calibrated inference. The fixed-primary-cohort covariate multiple imputation remains separate and unchanged.

## Portable execution and missing inputs

R entry points use `Rscript`'s executed-file argument; Python uses `__file__`; JavaScript uses `__dirname`. They do not assume the shell starts at the repository root. Optional private absolute locations are legitimate user configuration but must not appear as committed machine-specific paths. The source-data acquisition interface remains the documented public-source interface; this refactor does not change providers or silently fall back to synthetic data.

The compact real clinical derivatives and locked external/molecular summaries are included. The complete molecular/pan-cancer workflow requires separately obtained large raw inputs. A successful syntax check or clinical rebuild does not prove that the full network/expression workflow ran on a new machine. Record the exact verification scope and missing source layers in `REPRODUCIBILITY.md`.

## Submission cleanliness

Retain formal figures/tables, case-level supplementary files, manuscript sources and DOCX/PDF/TeX outputs, result-dependent audits, source manifests and package/system version records. Keep meaningful locked intermediate summaries when downstream stages require them. Multiple formats or numbered copies required for journal delivery are not redundant disposable files.

Exclude raw caches, private local paths, `node_modules`, logs, Python bytecode, editor/OS debris, TeX auxiliary files and the local illustrated review copy from the upload snapshot. The review copy remains reproducible and is preserved in the previous local submission tree. Do not run destructive cleanup on historical baselines. Archive superseded working materials with source/destination paths and file hashes instead of deleting scientific inputs or audit history.
