# Analysis workflow

## Entry points

- `scripts/00_run_pipeline.R`: complete ordered workflow.
- `make clinical`: primary clinical analyses from included public-data derivatives.
- `scripts/21_build_esmo_submission.py`: Markdown and DOCX submission build.
- `scripts/23_build_submission_latex.py`: TeX and PDF submission build (manuscript, supplement and cover letter).
- `make audit`: results-dependent manuscript-claim, figure-provenance and figure-typography audits.
- `make repo-check`: result-independent repository naming, header, language, path, exclusion, and configuration validation.
- `make release-check`: `make clean` followed by strict validation that no ignored build artefacts remain in the tree. Use only in a disposable working checkout, not on historical evidence.
- `scripts/28_submission_utilities.py`: shared read-only configuration, CSV selection, portable paths and hashes for Python builders/audits; not a pipeline stage.
- `scripts/29_prepare_release_snapshot.py`: policy-driven, non-destructive upload packaging. Defaults to dry-run; `--write` requires a new destination and never deletes the source.
- `scripts/20_build_manuscript_outputs.R --render-only` / `scripts/30_render_locked_publication.py`: publication-only rendering from locked tables and vector panels, without statistical fitting, cross-validation or date resampling. Publication exclusions, source hashes and panel layout are versioned in `config/submission_profile.json`. `CRNCR_PYTHON` may select the dependency-installed Python when R startup changes PATH; `make publication` respects that explicit selection, otherwise resolving `python3` from its shell PATH. When the interactive command is an alias, set `CRNCR_PYTHON` with `python3 -c 'import sys; print(sys.executable)'` before invoking make. The frozen renderer requires the shipped repository result bundle and fails on incompatible custom results-path overrides, rather than silently using the wrong tree.

## Ordered stages

| Stage | Script | Primary dependency | Main output |
|---:|---|---|---|
| 1 | `01_download_gdc_treatments.R` | GDC API | Treatment cache and harmonized treatment records |
| 2 | `02_prepare_clinical_cohort.R` | Xena clinical, survival, expression headers | Harmonized TCGA-OV clinical cohort |
| 3 | `03_run_clinical_sensitivity.R` | Stage 2 | Diagnosis-origin and missing-data sensitivity results |
| 4 | `04_run_expression_qc.R` | Stage 2 and Xena expression | Expression QC object |
| 5 | `05_fit_molecular_topology.R` | Stage 4 | Gene/Hallmark topology results |
| 6 | `06_validate_molecular_topology.R` | Stages 4-5 | Purity and label validation |
| 7 | `07_run_pathway_enrichment.R` | Stage 4 | Locked pathways and scores |
| 8 | `08_fit_wgcna_network.R` | Stage 4 | Primary co-expression network |
| 9 | `09_integrate_multiscale_results.R` | Stages 7-8 | Module-pathway integration |
| 10 | `10_run_wgcna_sensitivity.R` | Stages 4, 7, 8 | Gene-count sensitivity analysis |
| 11 | `11_prepare_hrr_mutations.R` | Stage 4 and cBioPortal | HRR mutation status |
| 12 | `12_integrate_replication_multiomics.R` | Stages 7 and 11 plus Xena multi-omics | Integrated multi-omic analysis |
| 13 | `13_inventory_external_cohorts.R` | Stage 12 and public cohorts | External-cohort inventory |
| 14 | `14_validate_locked_scores.R` | Stages 12-13 | Locked-score and external survival validation, including leave-one-out, HKSJ, prediction-interval and Firth-penalised pooling of the external HR |
| 15 | `15_audit_pancancer_labels.R` | Stages 1-2 | Pan-cancer response-semantics audit |
| 16 | `16_fit_pancancer_topology.R` | Stage 15 | Pan-cancer topology analysis |
| 17 | `17_fit_therapy_end_landmark.R` | Stages 2 and 15 | Primary ovarian landmark analysis and labelled post hoc checks (residual-disease strata, Akaike weights, minimal detectable HRs, ORR-constraint components, delayed entry, reverse Kaplan–Meier follow-up, numbers at risk, label-conflict exclusion) |
| 18 | `18_analyze_selection_regimen_power.R` | Stages 14, 17 | Selection, regimen, tipping, and power analyses |
| 19 | `19_analyze_hgsoc_sensitivity.R` | Stages 2 and 15 | Operational HGSOC analysis |
| 20 | `20_build_manuscript_outputs.R` | Locked stages 14-19 outputs and preserved vector panels | Publication-only rendering through utility 30; no implicit refitting or CV. Formal figures/tables exclude retracted-source results and date-scenario inferential rows |
| 21 | `21_build_esmo_submission.py` | Stage 20, manuscript sources and utility 33 reporting inputs | ESMO Open Markdown and DOCX; selects existing S5/S6 through utility 33, without fitting; supplementary contents fields update on opening in Word |
| 22 | `22_generate_submission_docx.js` | Stage 21 | Styled manuscript, supplement, cover letter and updated existing STROBE checklist DOCX files |
| 23 | `23_build_submission_latex.py` | Stage 21 | TeX and PDF files (manuscript, supplement, cover letter), plus a text-identical review copy of the main manuscript with figures appended (not for upload) |
| 24 | `24_validate_manuscript_claims.py` | Stages 20–21 and claim configuration | Numeric-claim and figure-provenance audit tables |
| 25 | `25_reconcile_outputs.py` | Two complete project trees | File-level byte, schema, row, numeric and text reconciliation report, including reference outputs missing from the candidate |
| 26 | `26_audit_figure_typography.py` | Stage 20 and `figure_specification` in `config/submission_profile.json` | Final-size canvas (190 mm double column), font embedding and minimum 8 pt text audit |
| 27 | `27_validate_repository_structure.py` | Repository code, configuration, and exclusions | Result-independent static repository validation |
| Utility 28 | `28_submission_utilities.py` | Local configuration and locked source rows | Reusable read-only input, path and hash helpers |
| Utility 29 | `29_prepare_release_snapshot.py` | `config/release_policy.json` and a source tree | Dry-run inventory or a new verified upload snapshot |
| Utility 30 | `30_render_locked_publication.py` | Locked outputs, preserved vector panels and publication policy | Reproducible display-only filtering/rendering; no new statistical estimation |
| Utility 31 | `31_flag_treatment_dates.py` | Hash-locked GDC records and published Data 1 | Reproduces recorded dates and appends overlapping descriptive flags (Data 3); dates and landmark membership remain unchanged |
| Utility 32 | `32_audit_risk_sets.py` | Hash-locked Data 1, existing landmark rules and frozen topology counts | Descriptive OS/PFI and covariate-complete membership (Data 4), hierarchical exclusions and count summary; `--check` verifies existing bytes; no fit or new inference |
| Utility 33 | `33_build_reporting_bundle.py` | Frozen results, claims, Data 1–4 dictionary and shipped historical excerpt | S5/S6 CSVs and deterministic Data 5 ZIP with provenance/navigation; all inputs are release-root relative, no external archive access or new estimates |

The governing rule is: shared configuration/validation is consolidated, scientific stages remain separate because estimands and failure rules differ. This preserves the numbered `NN_snake_case` stage boundaries and avoids merging complete statistical stages whose dependencies and scientific meanings are distinct. Stage 25 is run manually against an independent rebuild (see `docs/REPRODUCIBILITY.md`). Stages 24 and 26 are invoked separately with `make audit`; they are not part of `make check` because they require generated result tables, figures and provenance. Stage 27 is called by `make repo-check`, `make check`, and (in strict `--release-tree` mode) `make release-check`; it does not run the analysis.

## Deterministic execution

Random seeds and analysis thresholds are read from `config/analysis.yml`, including RMST sensitivity horizons, cohort/regimen definitions, and WGCNA fallback, hub, trait-sample, stability, and replication criteria. The runner stops at the first failed stage. Each script checks required inputs before analysis and writes English status messages. WGCNA may exhibit negligible platform-dependent differences because it uses parallel numerical routines.
