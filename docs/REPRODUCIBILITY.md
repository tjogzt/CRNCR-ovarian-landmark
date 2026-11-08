# Reproducibility and verification

## Locked environment

- R version used for the manuscript: 4.5.0.
- The exact installed R dependency graph is recorded in `renv.lock`; key versions and full inventories remain under `environment/`.
- The recorded machine contains packages from Bioconductor 3.21 and 3.22. `renv.lock` records the actual versions, but cross-machine restoration may require the matching package repositories or binaries.
- Analysis-specific `sessionInfo()` records are in `environment/sessionInfo/`.
- Node dependencies are locked by `package-lock.json`.
- `docs/raw_input_manifest.csv` records logical roots, relative paths, byte sizes, SHA256 hashes, and public sources for frozen Xena, GDC, cBioPortal, and GEO inputs.

## Validation commands

```bash
make repo-check
make check
make clinical
python3 scripts/21_build_esmo_submission.py
python3 scripts/23_build_submission_latex.py
make audit
make release-check
```

`make repo-check` is static and does not run scientific analyses. It enforces numbered `NN_snake_case` code names, required English headers, English comments and explicit diagnostics, portable paths, parseable JSON/YAML, key analysis settings, Git ignore rules, and tracked-file exclusions. `make check` adds R, Python, JSON, and JavaScript syntax checks. `make release-check` first runs `make clean` (LaTeX auxiliaries, logs, Python caches, `node_modules/`, and the local review copy) and then also requires the physical tree to contain no ignored build artefacts. The full molecular workflow requires the external data listed in `docs/DATA_SOURCES.md` and is computationally intensive. The audit is deliberately separate from `make check` because it requires generated result tables and formal figures.

Restore Node dependencies only from the lockfile with `npm ci`. The resulting `node_modules/` directory is disposable and excluded from GitHub; rerun `npm ci` whenever it is absent or needs clean restoration.

## Versioned configuration and release exclusions

`config/analysis.yml` is the single source for scientific inclusion and decision thresholds used by the numbered scripts, including sensitivity RMST horizons, cohort/regimen lists, and WGCNA fallback and stability criteria. `R/00_project_configuration.R` fails before analysis when required groups, types, finite values, proportions, positive integers, vector order, unique non-empty lists, equivalence margins, or landmark ranges are invalid. `config/submission_profile.json` separately controls DOCX `document_style` fonts and dimensions, LaTeX `latex_style` geometry and table type sizes, and formal `figure_specification` values. Public-source endpoints and the pinned cBioPortal datahub commit, study, and mutation profile are versioned in the `api` group of `config/analysis.yml`.

Private `config/paths.yml`, raw caches, logs, `node_modules/`, Python cache/bytecode files, LaTeX auxiliary files, and local review-copy files with appended figures must remain excluded from GitHub and the release tree. Source code and release configuration remain versioned; local absolute paths are prohibited.

## Statistical resampling policy

The project intentionally retains case bootstrap, split-half WGCNA assessment, stratified cross-validation, multiple imputation, stochastic treatment-date imputation, Monte Carlo Fisher tests, and power simulation. These procedures resample observed data or evaluate a statistical design. The primary analysis uses observed patients, not fabricated patients. Separately labelled hypothetical extreme-allocation scenarios reassign outcomes to excluded patients; those synthetic populations are not the original landmark population and do not establish hazard-ratio bounds or the direction of selection bias.

## Locked-result invariants

The primary clinical build should reproduce:

- Main therapy-end landmark cohort: n=372, 220 deaths.
- Response counts: CR 273, PR 51, SD 18, PD 30.
- NCR versus CR HR: 3.91 (95% CI 2.91-5.26), unadjusted.
- Plateau likelihood-ratio P=0.67 and ORR constraint P=8.5e-10.
- Operational HGSOC landmark cohort: n=334, 206 deaths.
- External pooled NCR versus CR HR: 4.25 (95% CI 1.43-12.6); HKSJ 95% CI 0.30-59.3; prediction interval 0.60-30.2.
- ORR-constraint components: PR = CR P=1.1e-10; SD = PD P=0.83.
- Akaike weights (unadjusted): M3 0.59, M_PD 0.30, M1 0.12.

## Submission checks

The configured ESMO Open build enforces: main text <=4,000 words, structured abstract <=300 words, <=100 references, <=5 main tables/figures, 3-5 highlights, and <=125 characters per highlight. The 8 November 2026 build has 3,958 main-text words and 1,007 legend words; the build's conservative main-plus-legend diagnostic is 4,965 and is excluded from the failure condition, a 299-word abstract, 47 main-text references (46 supplementary references), and five display items. The official treatment of legend words within the 4,000-word limit remains unverified; the body-only pass must not be represented as unconditional journal compliance. These are configured build checks, not certification that every current journal formatting requirement has been independently reverified.

## Approved checklist implementation of 2026-11-07

The approved pre-submission checklist was implemented in the English sources, generators and Chinese review translations. The changes correct the interpretation of hypothetical extreme allocations, missing-stage representation in the inclusion model, grade counts, cross-validation split variability, time-origin-specific HGSOC comparisons, label-source descriptions and apparent calibration. Two ESMO guidance references were added; the main and supplementary lists remain separate (47 and 46 entries). No optional new analysis or model refit was run in this revision.

The rebuilt English manuscript, illustrated review copy, supplement and cover letter contain 20, 23, 37 and 1 pages; the Chinese review PDFs contain 18, 27 and 1 pages. The illustrated English copy has text-identical first 20 pages and three appended figure pages. All seven PDFs were rendered and checked; no extracted replacement character or word outside the page boundary remained. Figure 3's legend is whole on manuscript page 17. Figure S1 and its full legend share supplement page 28 at the original 190 mm artwork width, with a dedicated 9.5 pt caption. Table S1d uses separated numeric columns; main table notes use 9 pt. Chinese figure-page footers now sit inside the page edge.

Stage 24 passed all 160 declared claims (329 numeric field checks) and 18 figure-provenance checks; stage 26 passed all 18 formal-figure typography checks. Stage 30 check-only and stage 32 check verified the locked figures and risk sets without refitting. The 243-file pre-revision scientific inventory had no unexpected changes: only the claim audit and reporting-bundle ZIP changed. Supplementary Data 5 still contains 25 members; only its input manifest and reporting index changed. Its new paired cross-validation fields point to existing empirical 5th/95th percentiles rather than confidence limits for the resampled median. R/Python/JavaScript/JSON syntax, runtime configuration, CV-concordance regression checks and Chinese source-sync checks passed. Both translated reference lists and all citation-group sequences match their English counterparts.

DOCX XML checks confirm A4 sections, the current short-title headers, editable tables and no ordinary table run below 8 pt. Actual Word/WPS/LibreOffice pagination has not been verified: no LibreOffice runtime was available, and local application control was blocked by a locked Mac. XML checks and the independently built PDFs do not substitute for this remaining visual check. The official inclusion or exclusion of figure/table legend words in the 4,000-word limit also remains unresolved. These two limitations preclude unconditional certification of submission readiness.

The declared reviewer attachment is `CRNCR_reviewer_code_20261108.zip`, to be assembled locally with stage 29 under the physical release policy and supplied through a nonpublic review attachment channel. It is separate from Supplementary Data 5. Internal review archives, Chinese review files, private paths, raw caches and build dependencies are omitted; source code, configuration, environment locks, compact derived data, frozen tables, manuscript sources and input-retrieval documentation are retained. A copied snapshot's checksum and source-index checks establish file availability and consistency, not clinical-record authenticity or a new full raw-input reproduction. No upload, Git commit/push, public release or DOI deposit was performed.

## Academic peer-review P1–P3 implementation (2026-11-07)

All P1, P2 and P3 items in `review_esmo_20261107/ESMO_Open_academic_review_20261107.md` were implemented as a text-only revision. No model was refitted, no result CSV was changed, and no figure was redrawn. The changes:

1. **Primary-test hierarchy (P1-1).** Methods now state that the primary test was the objective-response constraint (M2 versus M1) and that the PR–CR contrast within M1 was the pre-specified driver of any rejection; the three codings are described as competing descriptions rather than co-primary hypotheses.
2. **Sample-size provenance (P1-2).** Methods state that no a priori sample-size calculation was performed and that post-hoc detectable effects are reported; the supplementary power section now expresses the 20%/30% PD assumption as about 371 NCR patients with 75 PD or 283 with 85 PD.
3. **Label-source attenuation (P1-3).** Discussion interprets the lower unadjusted estimate in the 307 clinical-matrix-labelled patients (3.25 versus 3.59 adjusted) as compatible with some misclassification of the 65 TCGA-CDR-only labels while direction and significance were unchanged.
4. **ΔAIC attribution (P1-4).** The objective-response rejection now reports ΔAIC 37.8/25.7 versus M1 (the M2-versus-M1 comparison), not the previously printed 41.0/27.7 M2-versus-M3 values.
5. **P2/P3 wording.** The revision adds the prespecified landmark plausibility-window rationale, a descriptive framing of the extreme-allocation scenarios, a single-cohort external conclusion, the 14 proper response subsets forming seven complementary bipartitions, explicit calibration over-/under-prediction, the strengths-first limitations opening, and removes claims not supported by the reported analyses (for example, that restriction to homogeneous subsets preserved the pattern). The abstract, highlights, Figure 3 legend, Table 1 notes and cover letter were aligned; the cover letter is dated 8 November 2026.

Verification:

- Stage 21 passes every enforced limit: main text 3,965 of 4,000 words, abstract 299 of 300, 47 main references, five display items, five highlights (109/93/123/106/84 characters) and six keywords. The conservative main-plus-legends diagnostic is 4,972 and remains excluded from the failure condition.
- Ten claims were re-anchored to the revised sentences without changing any expected value or source field. Stage 24 validates all 160 claims (0 failed fields) and 18 provenance entries; stage 26 audits 18 formal figures with 0 failures; stage 27 and `make check` pass.
- English PDFs contain 20 (upload manuscript), 23 (illustrated review copy), 37 (supplement) and 1 (cover letter) pages; stage 23 confirms the review copy's first 20 pages are text-identical to the upload PDF. Chinese review PDFs contain 18, 27 and 1 pages; `make zh-check` passes.
- Supplementary Data 5 was rebuilt with 25 members and 269,205 uncompressed bytes; its bundle SHA-256 is `3f8f531146eb8f672a195746aea0a5273cda600f2207219d83b5e0ad7fba3171`.
- The external upload package `../submission_package/ESMO_Open_20261107` was refreshed; all 23 file checksums and all 21 `MANIFEST.csv` rows verify. The outer ZIP and the reviewer snapshot are accompanied by adjacent `.sha256` files (`ESMO_Open_20261107_upload_package.zip.sha256` and `CRNCR_reviewer_code_20261107.zip.sha256`), regenerated after every rebuild; the ZIPs are not re-hashed inside this document because the reviewer snapshot contains it.
- `docs/SHA256SUMS.txt` was refreshed in place (403 entries, all verifying). No Git commit, push, publication, DOI deposit or journal submission was performed.

## Humanizer revision (2026-11-08)

The approved humanizer review in `review_esmo_20261107/ESMO_Open_humanizer_review_20261108.md` was implemented as a text-only revision. No model was refitted, no result CSV changed and no figure was redrawn. The changes removed inflated significance and promotional phrasing, converted several `-ing` analyses into finite verbs, replaced vague attribution with named evidence, reduced negative parallelism and rule-of-three constructions in the supplementary text, and rewrote the cover letter in a direct, non-promotional voice. Analysis choices previously described as "locked" are now described as "pre-specified"; the `locked_software_versions.csv` filename was left unchanged because it names an archived file. No numerical result, eligibility rule, model comparison or conclusion changed.

Verification:

- Stage 21 passes every enforced limit: main text 3,958 of 4,000 words, abstract 299 of 300, 47 main references, five display items, five highlights (109/93/123/106/84 characters) and six keywords. The conservative main-plus-legends diagnostic is 4,965 and remains excluded from the failure condition.
- Six claim locations or patterns were updated to follow revised sentences and a split equivalence sentence; no expected value, source field or scientific number changed. Stage 24 validates all 160 claims (0 failed fields) and 18 provenance entries; stage 26 audits 18 formal figures with 0 failures; stage 27 and `make check` pass.
- English PDFs contain 20 (upload manuscript), 23 (illustrated review copy), 37 (supplement) and 1 (cover letter) pages; stage 23 confirms the review copy's first 20 pages are text-identical to the upload PDF. Chinese review PDFs contain 18, 27 and 1 pages; `make zh-check` passes.
- Supplementary Data 5 was rebuilt with 25 members and 269,217 uncompressed bytes; its bundle SHA-256 is `ee0db5acd811e323940d98ae611b3f15bdfb5402efdaf9a69fada21ec335c807`.
- The external upload package `../submission_package/ESMO_Open_20261107` was refreshed in place after the previous copy was archived; all 23 file checksums and all 21 `MANIFEST.csv` rows verify. The outer ZIP and the reviewer snapshot are accompanied by regenerated adjacent `.sha256` files (`ESMO_Open_20261107_upload_package.zip.sha256` and `CRNCR_reviewer_code_20261107.zip.sha256`); the ZIPs are not re-hashed inside this document because the reviewer snapshot contains it.
- `docs/SHA256SUMS.txt` was refreshed in place (403 entries, all verifying). No Git commit, push, publication, DOI deposit or journal submission was performed.

## External review P0 and P1 implementation (2026-11-08)

An external review of the main manuscript, supplementary appendix and cover letter was triaged into P0 and P1 items; both tiers were implemented as text and table-note changes only. No model was refitted, no result CSV was changed, and no figure or table structure was altered.

1. **`-fold` summary wording (P0).** The 3.6-fold paraphrase of the PR-versus-CR contrast was replaced by the exact estimate in the first highlight and the cover letter ("a hazard ratio for death of 3.61 ... 2.54–5.13"). The Discussion now gives the per-category range ("3.6 to 4.5 versus CR") and closes with "not predictive superiority" instead of the previous comparative construction.
2. **Residual-disease evidence in the main text (P0).** The post hoc comparison among 246 patients with residual disease of 10 mm or less (including R0; 24 PR) moved from the supplement into Results: PR remained associated with a higher hazard than CR (HR 4.04, 2.53–6.44; adjusted for age and stage 4.38, 2.69–7.14; Supplementary Table S3).
3. **Provenance and definitions (P1).** Abstract Methods state that response labels were chart-abstracted categories, not protocol-timed RECIST. Table 1 notes state that death percentages are not survival estimates and that follow-up among survivors differed by response. Methods state that sex was uniformly female by cohort definition and gender was unavailable. The Figure 3A legend and the main text use one decimal for the pooled Wald upper limit (12.6).
4. **AI declarations (P1).** The writing declaration is limited to language editing, consistency checking and document formatting. Code support is declared separately under Data availability as the AI coding assistant Qoder, with author review and verification of all analysis code.

Verification:

- Stage 21 passes every enforced limit: main text 3,988 of 4,000 words, abstract 297 of 300, 47 main references, five display items, five highlights (104/93/123/106/84 characters) and six keywords. The conservative main-plus-legends diagnostic is 4,995 and remains excluded from the failure condition.
- Two main-text claims were added for the residual-disease PR–CR estimates and one cover-letter claim was re-anchored; no expected value, source field or scientific number changed. Stage 24 validates 162 claims (0 failed fields) and 18 provenance entries; stage 26 audits 18 formal figures with 0 failures; stage 27 and `make check` pass.
- English PDFs contain 20 (upload manuscript), 23 (illustrated review copy), 37 (supplement) and 1 (cover letter) pages; stage 23 confirms the review copy's first 20 pages are text-identical to the upload PDF. Chinese review PDFs contain 18, 27 and 1 pages; `make zh-check` passes.
- Supplementary Data 5 was rebuilt with 25 members and 270,155 uncompressed bytes; its bundle SHA-256 is `2e3fe116856fbe2f2e660353eb0b789d704c4a4a1e366670e1f1bcd57fdaa615`.
- The external upload package `../submission_package/ESMO_Open_20261107` was refreshed in place; all 23 file checksums and all 21 `MANIFEST.csv` rows verify. The previous reviewer snapshot was archived before replacement. The outer ZIP and the reviewer snapshot are accompanied by regenerated adjacent `.sha256` files; the ZIPs are not re-hashed inside this document because the reviewer snapshot contains it.
- `docs/SHA256SUMS.txt` was refreshed in place (403 entries, all verifying). No Git commit, push, publication, DOI deposit or journal submission was performed.

## External review SA-4 and MM-8 implementation (2026-11-08)

Two items from a further external review were implemented after the rest of that review was checked against the current files and found either factually inapplicable or incompatible with the 4,000-word limit. This was a text-only revision: no model was refitted, no result CSV changed, no figure was redrawn and no numerical value was altered.

1. **Figure S5 denominator (SA-4).** The Supplementary Figure S5 legend now states that, because the proliferation score uses pretreatment primary-tumour expression and does not require landmark eligibility, the TCGA-OV row includes all 454 response-labelled patients rather than the 372-patient landmark subset. This matches the plotted row (CR 319, NCR 135) and the per-cohort source table.
2. **Results structure (MM-8).** A subsection heading, "Prognostic discrimination, calibration and confounding sensitivity", was added before the cross-validated C-index paragraph. Heading lines are excluded from the configured body-word count, which is unchanged. The Chinese review source received the corresponding heading and legend sentence.

Verification:

- Stage 21 passes every enforced limit: main text 3,988 of 4,000 words, abstract 297 of 300, 47 main references, five display items, five highlights (104/93/123/106/84 characters) and six keywords. The conservative main-plus-legends diagnostic is 4,995 and remains excluded from the failure condition.
- Stage 24 validates 162 claims (0 failed fields) and 18 provenance entries; stage 26 audits 18 formal figures with 0 failures; stage 27 and `make check` pass; `make zh-check` passes.
- English PDFs contain 20 (upload manuscript), 23 (illustrated review copy), 37 (supplement) and 1 (cover letter) pages; stage 23 confirms the review copy's first 20 pages are text-identical to the upload PDF. Chinese review PDFs contain 18, 27 and 1 pages. The new heading is bold on manuscript page 7 and on Chinese page 5; the S5 legend remains whole on supplement page 32.
- Supplementary Data 5 was rebuilt with 25 members and 270,155 uncompressed bytes; its bundle SHA-256 is `77b1a04198ad110de27c63edde31b58290fa0647d6066a1811ef654e7454ff80`.
- The external upload package `../submission_package/ESMO_Open_20261107` was refreshed; all 23 file checksums and all 21 `MANIFEST.csv` rows verify. The reviewer snapshot was rebuilt as `CRNCR_reviewer_code_20261108.zip` (387 entries) and the outer ZIP has 24 entries. Adjacent `.sha256` files were regenerated. The ZIPs are not re-hashed inside this document because the reviewer snapshot contains it. The pre-revision reviewer snapshot was archived rather than deleted.
- `docs/SHA256SUMS.txt` was refreshed in place (403 entries, all verifying). No Git commit, push, publication, DOI deposit or journal submission was performed.

## External review minor-batch implementation (2026-11-08)

A further machine-generated review was triaged item by item. Its independent arithmetic checks (Akaike weights, ΔAIC, Schoenfeld minimum detectable hazard ratios, E-values, meta-analytic leave-one-out estimates and cohort counts) agreed with the locked outputs. Five defensible items were implemented; the review's claims that the P=8.5×10⁻¹⁰ superscript was lost, that the Figure 1 legend exceeded 1,000 words and that timeROC was unused were checked and found incorrect, and its proposed new analyses were deferred.

1. **Reviewer snapshot filename.** The Data availability statement and the cover letter in both languages now name `CRNCR_reviewer_code_20261108.zip`, matching the assembled attachment. The previous string still carried the 20261107 date.
2. **Delayed-entry wording.** Methods no longer say the post hoc delayed-entry models were fitted "by stratum", which did not describe Supplementary Table S3(c). The sentence now states that both time scales were used, with landmark time as a covariate on the landmark scale.
3. **60-month RMST location.** Methods previously said the 60-month estimate was given in the Supplementary Results, while Results also reported it. The Methods sentence now says it is reported in the Results with its sparse risk set.
4. **Adjusted range across time origins.** "3.5–4.2" was replaced by "3.55–4.18", matching the lowest adjusted value in Supplementary Table S5.
5. **Software list.** `riskRegression` was added for the calibration cross-check. `timeROC` was retained because stage 17 uses it to compute a time-dependent AUC.

Verification:

- Stage 21 passes every enforced limit: main text 3,991 of 4,000 words, abstract 297 of 300, 47 main references, five display items, five highlights (104/93/123/106/84 characters) and six keywords. The conservative main-plus-legends diagnostic is 4,998 and remains excluded from the failure condition.
- No model was refitted, no result CSV changed and no figure was redrawn. Stage 24 validates 162 claims (0 failed fields) and 18 provenance entries; stage 26 audits 18 formal figures with 0 failures; stage 27, `make check` and `make zh-check` pass.
- English PDFs contain 20 (upload manuscript), 23 (illustrated review copy), 37 (supplement) and 1 (cover letter) pages; the review copy's first 20 pages remain text-identical to the upload PDF. Chinese review PDFs contain 18, 27 and 1 pages. The revised sentences render on manuscript pages 5–6 and Chinese pages 3–5; the unchanged S5 legend remains whole on supplement page 32.
- Supplementary Data 5 is unchanged at 25 members and 270,155 uncompressed bytes, with bundle SHA-256 `77b1a04198ad110de27c63edde31b58290fa0647d6066a1811ef654e7454ff80`.
- The upload package was refreshed; all 23 file checksums and all 21 `MANIFEST.csv` rows verify. The reviewer snapshot was rebuilt as `CRNCR_reviewer_code_20261108.zip` (387 entries) and the outer ZIP has 24 entries. Adjacent `.sha256` files were regenerated. The ZIPs are not re-hashed inside this document because the reviewer snapshot contains it. The pre-revision snapshot was archived rather than deleted.
- `docs/SHA256SUMS.txt` was refreshed in place (403 entries, all verifying). No Git commit, push, publication, DOI deposit or journal submission was performed.

## Manuscript and figure audit

`config/manuscript_claims.json` stores only claim locations, manuscript anchors and regular expressions, source CSV paths and unique row filters, source-field mappings, and display precision/tolerances. It does not store expected manuscript values. Stage 24 extracts each displayed number, parses decimal and scientific notation, and compares it with the uniquely filtered source row. Missing anchors, ambiguous source rows, missing fields and out-of-tolerance values fail the audit.

The same stage reads `${CRNCR_RESULTS_DIR:-results}/tables/manuscript/figure_provenance.csv`, computes SHA256 for every declared source and destination, and requires each pair to match. It writes `manuscript_claim_audit.csv` and `figure_provenance_audit.csv` beside the provenance table and exits nonzero on any claim or figure failure. Run stage 20 before the audit so the provenance table and staged figures exist.

## Independent rebuild verification

The most recent full raw-input verification (2026-10-17) rebuilt the project twice from scratch in two isolated copies of the repository. Each copy started without `results/`, `data/processed/`, `data/supplementary/` or generated submission files. Each used only raw inputs whose bytes and SHA256 matched all 54 entries of `docs/raw_input_manifest.csv`. GDC pages were read with `CRNCR_OFFLINE_RAW=true`. Both copies completed stages 1-20 with exit status 0. The first copy then ran stages 21-24 and 26.

Stage 25 produced the reports:

```bash
python3 scripts/25_reconcile_outputs.py --candidate <rebuild> --reference . --report docs/output_reconciliation.csv
python3 scripts/25_reconcile_outputs.py --candidate <repeat> --reference <rebuild> --report docs/stochastic_repeat_reconciliation.csv
python3 scripts/25_reconcile_outputs.py --candidate <rebuild> --reference <previous rebuild> --report docs/prior_rebuild_reconciliation.csv
```

A PDF is classified as `PDF_METADATA_ONLY` when its objects are identical after removing creation and modification timestamps, stream lengths and cross-reference offsets. Every PDF with this status was also checked separately by rendering: the pages are pixel-identical.

- Rebuild versus this repository (`docs/output_reconciliation.csv`):
  - Of 156 outputs present in both trees, 138 were byte-identical. These include every versioned CSV, RDS, PNG and text file, among them the three post hoc tables added on 2026-10-18.
  - 17 were `PDF_METADATA_ONLY`.
  - The remaining file, `figure_provenance_audit.csv`, differed only in the SHA256 values it records for those time-stamped PDFs.
  - The other 143 outputs are unversioned intermediates and are listed as `NEW_OUTPUT`.
- Repeat versus rebuild (`docs/stochastic_repeat_reconciliation.csv`): this repeated the full stages 1-20, including WGCNA and every resampling stage. Of 293 outputs, 282 were byte-identical and 11 were `PDF_METADATA_ONLY`.
- Submission files: the rebuilt Markdown, highlights and TeX files were byte-identical to the versioned files. The rebuilt PDFs had identical text and pixel-identical pages (18 and 15 pages). The DOCX files differed only in the timestamps in `docProps/core.xml`.
- Audits on the rebuild: the manuscript audit validated 40 claims (51 after the 2026-10-18 additions) and 16 figure-provenance entries with zero failures. The typography audit passed all 16 formal figure files.
- Later source edits: the Supplementary Figure S2 legend, one clarification in the supplementary text, the claim that audits that legend, header detection in stage 2, and the reference review of 2026-10-17 (citation placement, added method references and AMA-style author lists and full page ranges in stage 21) were changed after the rebuild. The rebuild copy was then resynchronised and stages 21-24 and 26 were rerun there. The figures above reflect that final state.
- Post hoc additions of 2026-10-18 (Supplementary Table S4): a residual-disease-stratified NCR versus CR analysis with an interaction test (stage 17; `noncr_by_residual_disease.csv`, `noncr_residual_interaction.csv`) and a leave-one-out re-pooling of the external hazard ratio (stage 14; `os_meta_noncr_vs_cr_leave_one_out.csv`). Both blocks are deterministic and draw no random numbers. Stages 14 and 17 were rerun in the rebuild copy: every pre-existing CSV, RDS and PNG output was byte-identical, the three PDFs were `PDF_METADATA_ONLY`, and only the run-summary logs gained the new tables. Stages 20-24 and 26 were then rerun there, and the reconciliation above was regenerated. The rebuilt Markdown and TeX files were byte-identical to the versioned files, and the manuscript audit validated 51 claims with zero failures. In the main text, one Discussion sentence now cites Supplementary Table S4; the words were offset by trimming elsewhere in the Discussion, so the main text plus legends remains 3,999 words. The supplementary PDF now has 16 pages.
- Review copy with figures (2026-10-18): stage 23 also writes `ESMO_Open_manuscript_review_copy_with_figures.pdf` for reading convenience only; the upload manuscript stays without embedded figures as ESMO Open requires separate figure files. The copy is generated from the upload TeX in the same run, and the build stops unless removing its two insertions recovers the upload TeX exactly and its first pages are text-identical to the upload PDF. On 2026-10-18 the 18 shared pages were also pixel-identical when rendered, and the three appended pages hold Figures 1–3 at native 190 mm width.
- Page-layout fix (2026-10-19): pages using the 10 mm body margin (wide landscape tables and figure pages) previously pushed the running head and page number past the paper edge. Figure pages now keep 10 mm side margins with the 22 mm top and bottom margins of text pages; landscape table pages keep their 10 mm body but place the running head and page number inside the paper. Reference lists may break after "doi:" to avoid overrunning the right margin. Only geometry and line-breaking commands changed in the TeX; page counts stayed at 18 and 16, and apart from page numbers and running-head positions the extracted text was identical before and after.

`docs/prior_rebuild_reconciliation.csv` compares the new rebuild with the previous isolated rebuild of 2026-10-15. This provides a reference for the unversioned intermediates. Every difference there corresponds to an intentional code change made after that rebuild:

- reader-visible "NCR" labels and shared palette or theme updates in stage 5, 7, 9, 14, 16, 18 and 19 outputs;
- portable `xena_dir`/`processed_data_dir`/`external_data_dir` source labels in stage 4, 8 and 11 outputs;
- formal figures redrawn at the 190 mm double-column specification;
- additional figure-provenance, typography, Kaplan-Meier statistic and paired cross-validation tables;
- stratification of the stage 17 cross-validation folds by response category, which also changed the row order of the CV summary;
- differing package lists in `sessionInfo` records.

No other numerical result differed.

Shared WGCNA, Cox-topology, and bootstrap code was reviewed for consolidation. The implementations retain analysis-specific model sets, covariates, failure rules, and return structures, so no late-stage abstraction was introduced after the golden outputs were established.

## Known reproducibility boundaries

The frozen `Survival_SupplementalTable_S1_20171025_xena_sp` is the TCGA Pan-Cancer Clinical Data Resource table with seven accidental R-code lines prepended. The last of these lines is fused to the column header. Apart from that, its data rows are identical to the file currently served by the UCSC Xena Pan-Cancer Atlas hub, which is 302 bytes smaller and has SHA256 `a5e70415...df9617`. A rebuild from the hub file will therefore not match the frozen manifest hash. Stages 2 and 15 locate the header line rather than assuming a fixed offset, so both versions are read identically. Stages 2 and 15 were rerun once with each version on 2026-10-17, and all 296 outputs were byte-identical to the rebuild, apart from two time-stamped PDFs. All other Xena inputs currently served by the public hubs matched the manifest byte for byte on 2026-10-17.

API contents, package updates, parallel WGCNA numerical routines, and upstream database corrections may cause differences in a full future rebuild. The included compact derived data and locked output tables are the authoritative record for the submitted analysis. Large raw matrices, redistributable MSigDB objects, temporary ESTIMATE files, logs, and gene-level all-analysis tables are deliberately excluded.

## Revision of 2026-10-19

After a structured internal review, the following changes were made and verified in an isolated copy of the repository before being synchronised:

- Post hoc analyses (all deterministic, drawing no random numbers): four-category topology within residual-disease strata; Akaike weights; minimal detectable hazard ratios; decomposition of the ORR constraint into PR = CR and SD = PD; delayed entry at the landmark and landmark-time adjustment; landmark timing by response; reverse Kaplan–Meier follow-up; numbers at risk; exclusion of the one label-conflict patient (stage 17); Firth-penalised per-cohort Cox models with HKSJ and prediction-interval pooling (stage 14, `coxphf` 1.13.4); confidence intervals for the IPW category hazard ratios (stage 18).
- Every pre-existing CSV, RDS and PNG output of stages 14, 17, 18 and 20 was byte-identical after the change, except for the intended changes: Figure 2 (numbers at risk added), the sequential landmark flow table, the IPW table (new CI columns), Tables 1-2, Supplementary Table S1 (response-defined denominators), the renamed Supplementary Table S4, and Supplementary Data 1, in which the one patient whose TCGA-CDR and clinical-matrix labels disagree is now labelled as discordant rather than concordant. Stage 20 now also writes `data/supplementary/` and the table-numbered copies in `results/tables/main/` and `results/tables/supplementary/`, which were previously static. Other PDFs were `PDF_METADATA_ONLY`.
- Supplementary Table S3 now holds the post hoc robustness analyses and Supplementary Table S4 the pan-cancer label audit. The obsolete `TableS2_pancancer_label_audit.csv`, `TableS_external_cohorts.csv` and the 120-month duplicate of Figure 2 were removed.
- The manuscript audit now validates 85 claims (176 fields) with zero failures, and stage 25 reports reference files that a candidate no longer produces as `MISSING_IN_CANDIDATE`.
- The rebuilt PDFs have 18 pages (manuscript), 21 pages (review copy with figures; pages 1-18 text-identical to the manuscript) and 19 pages (Supplementary Appendix).
- The internal narrative evaluation was moved out of the public repository, the STROBE checklist was rewritten against the current headings, and an MIT License was added.

The reconciliation tables in `docs/` describe the 2026-10-17 rebuild and predate this revision.

## Repository refactor verification (2026-10-19)

The repository-governance refactor moved scientific thresholds, public-source identifiers, and DOCX/LaTeX layout values from code into `config/analysis.yml` and `config/submission_profile.json`, added stage 27, and changed `make clean`; configured values equal the previous literals. It was verified by running the complete stages 1-20 twice in parallel isolated copies, one from the refactored repository and one from the pre-refactor repository, with all 54 raw inputs matching `docs/raw_input_manifest.csv` byte for byte. GDC pages were read from the frozen cache (no page was downloaded), and the resulting treatment-record table was byte-identical to that of the 2026-10-17 rebuild.

- Both runs completed with exit status 0. In `docs/refactor_reconciliation.csv` (refactored versus pre-refactor run), of 337 outputs, including unversioned intermediates under `data/processed/` and `results/`, 315 were byte-identical (every CSV, RDS, PNG and text output) and 21 were `PDF_METADATA_ONLY`. The only remaining difference was a staged audit table copied from each source tree rather than produced by stages 1-20.
- Console output differed only in time stamps and one reworded progress message for the WGCNA soft-threshold range.
- Against the versioned outputs of this repository, 177 outputs were byte-identical and 17 were `PDF_METADATA_ONLY`; the remaining 143 are excluded intermediates.
- Stages 21-24 and 26 then reproduced byte-identical Markdown, highlights and TeX files (including the review copy); the DOCX files differed only in `docProps/core.xml` time stamps. The manuscript audit validated 85 claims and 16 figure-provenance entries with zero failures, and the typography audit passed all 16 formal figure files.
- A separate copy placed at an unrelated absolute path, without `config/paths.yml` or path environment variables, reproduced the clinical stages and submission files identically, confirming that no stage depends on the original checkout location.

## Figure 1 revision (2026-10-20)

After a four-party figure review, the Figure 1 section of stage 20 was rewritten as a CONSORT-style diagram drawn in millimetre coordinates at 190 × 175 mm. Exclusions now sit on the connectors and include the 28 primary tumours without U133A expression and the 113 patients without a canonical response label. Every displayed count is read from versioned result tables or configuration (no typed-in counts) and is written to `results/tables/manuscript/Figure1_flow_counts.csv`. The external landmark is read from `external_validation.landmark_days`, and stage 20 asserts that it equals `landmark.fixed_days[1]`. Box fills use the new shared palette key `neutral$fill` (#F2F2F2). After a second review of colour use, the figure stays greyscale: Panel B rows carry neutral-grey markers taken from `cohort_shape` (as in Figure 3A), the pooled row reads 'Pooled external (REML)', and the retracted-cohort text uses the new key `neutral$muted_text` (#6E6E6E, contrast about 5.1:1 on white). The Figure 1 legend was rewritten (958 legend words in total; main text plus legends 3,981 of 4,000), and 11 claims covering the cohort-flow and pan-cancer counts were added to `config/manuscript_claims.json`.

- Stage 20 draws no random numbers in the Figure 1 section. Against `../github_submission`, `docs/figure1_revision_reconciliation.csv` lists 179 identical outputs and 8 `PDF_METADATA_ONLY`. The intended differences are the four Figure 1 files (staged and analysis-native PNG/PDF), the new count table, and the three audit tables that record figure hashes, the new figure height and the added claims.
- Stages 21-24 and 26 were rerun: the manuscript audit validated 96 claims and 16 figure-provenance entries with zero failures, the typography audit passed all 16 formal figure files (Figure 1 minimum text 8.00 pt, Arial embedded), and the review copy places Figure 1 at native size.

### Figure 1 flow-completeness revision (2026-10-20)

A subsequent four-party review added the previously implicit 630-to-595 transition as a separate primary-tumour box with 35 non-primary-tumour records on the exclusion connector. Panel B now labels its final column as landmark n (deaths), presents the retracted-source counts with explicit field names, and describes the three primary cohorts as a cohort-level REML meta-analysis with total landmark n and deaths. Reader-visible text referring to the primary landmark was standardised from end of first-line chemotherapy to end of first-line therapy in the main Results. The revised canvas is 190 × 187 mm. Stages 20-24 and 26 were rerun: the conservative main-text-plus-legends count is 3,955 of 4,000 words; the manuscript audit validated 105 claims and 16 figure-provenance entries with zero failures; the typography audit passed all 16 formal files, with Figure 1 at a minimum 8.00 pt and embedded Arial; and the review copy remains text-identical to the upload manuscript before its three appended figure pages.

## Figure 2 text revision (2026-10-20)

Following three rounds of four-party review and author approval, the Figure 2 legend and the Methods/Results cross-validation paragraphs were revised. The legend distinguishes the 372-patient Kaplan-Meier/log-rank cohort from the 343-patient covariate-complete cross-validation cohort, clarifies ordinary right-censoring versus the 120-month display limit, defines objective-response and post hoc three-category codings, and retains the empirical-percentile and non-equivalence limits. Stage 17 now exports separate `n_km` and `n_cv` fields in `figure2_km_statistics.csv`. Figure labels are mapped separately from the existing model-colour keys; the canvas, layout ratios, response colours, solid curves, line widths and 120-month horizon were not changed. Longer labels were wrapped without reducing the font size.

- Stages 17 and 20 were rerun. Against the pre-revision result snapshot, every other clinical CSV was byte-identical; the pre-existing KM statistics were also identical after mapping the former `n` field to `n_km`. The displayed C-indices, hazard ratios, bootstrap frequencies, paired gains and risk-table counts were unchanged. Stage 17 asserts zero objective-response selection frequencies in all three displayed bootstrap settings and reads the bootstrap/CV annotation counts from the analysis tables.
- The Figure 2 legend decreased from 305 to 278 words. Main text is now 3,024 words and all legends 931 words: 3,955 of the conservative 4,000-word limit. Nine claims were added and affected patterns updated; stage 24 validated 105 claims (207 fields) and 16 figure-provenance entries with zero failures. All 16 formal figure files passed stage 26; Figure 2 remains 600 dpi PNG and an embedded-Arial vector PDF with minimum text size 8.00 pt.
- Stages 21-23 rebuilt the submission files and local review copy. The manuscript has 18 pages and the review copy 21 pages; all 18 shared PDF pages were text-identical, and the upload manuscript contains no embedded figures. The Figure 2 page and legend page were rendered and inspected; an independent read-only reviewer found no new clipping or annotation collisions. `make check` and strict release-tree validation passed, the latter on an isolated copy of the upload inventory so local review and dependency artefacts were retained.
- `docs/figure2_text_revision_reconciliation.csv` compares the current results with `../github_submission`. This is a cumulative comparison that also includes the preceding Figure 1 revision, not an isolated estimate of the Figure 2 changes. Remaining geometry, spacing and line-weight proposals were not implemented; in particular, the narrow 11% label in panel D remains a deferred readability issue.

## Fold-local cross-validation revision (2026-10-21)

Following three rounds of four-party review and author approval, stages 17, 19 and 20 now compute Harrell concordance within each validation fold. The shared `cv_fold_concordance()` helper counts concordant, discordant and score-tied comparable pairs; `cv_repeat_concordance()` sums these counts over the five folds, with score ties contributing one half. It does not compare scores from different fitted models or take an unweighted mean of fold C-indices. The original seeds, response-stratified fold assignments, cohorts and Cox formulas were retained. Each repeat uses identical folds for all models; combined-minus-clinical gains are paired by repeat before taking medians and empirical 5th–95th percentiles. These percentiles describe split variability, not confidence intervals. Validation folds without comparable pairs and missing predictions stop the analysis. Structural aliasing in the HGSOC model is allowed only when validation predictions remain finite.

The pre-revision code, configurations, results and manuscripts were copied to `../archive/figure2_cv_pre_revision_20261020_233937/`. Per-fold counts and assignments are now exported for the primary, HGSOC and GSE63885 analyses. Regression checks include an independent censored-pair enumeration, risk direction, score ties, invariance to fold-specific score shifts, count-weighted aggregation and invalid-input guards; they can be run with `make cv-check` and are also included in `make check`.

Revised primary response-only median C-indices are 0.630 for four categories and 0.632 for CR versus NCR. Clinical-only C is 0.615; combined objective-response, CR-threshold, three-category and four-category medians are 0.641, 0.679, 0.679 and 0.677. Corresponding median paired gains are 0.028, 0.067, 0.066 and 0.065. The GSE63885 response-only medians are 0.654 and 0.639. The main text, abstract, figure legends and supplementary text were synchronised; the claim that objective response retained approximately half the paired gain was replaced with the observed paired values. Figure 3B changes only in its CV annotation as a downstream consequence of the common assessment method.

Figure 2 remains at 190 × 215 mm with 600-dpi PNG and embedded-Arial vector PDF. The short/wrapped D axis labels, and wrapping of the longest E label that shares its alignment, give the 11% label approximately 0.60 mm clearance on each side at native size. The D subtitle identifies unadjusted response-only Cox models. C interval caps were widened without changing estimates or CI endpoints. Solid KM curves, censor marks, the 120-month display and risk tables, shared colours, model order and axis-frame styles are unchanged. The conservative main-text-plus-legends count is 3,978 of 4,000 words; the abstract remains 298 words. Numeric claims, figure provenance and native-size typography are audited with stages 24 and 26.

Independent read-only verification reproduced all 1,500 fold-count records and 14,500 assignments, including time/score ties, shared denominators and the original splits. The legacy pooled C/AUC values were reproduced exactly; all paired gains were verified, and non-CV KM statistics, HRs, bootstrap, imputation and RMST outputs agreed with the baseline. One pre-existing GSE63885 four-category fit (repeat 19, fold 1) reached the default iteration limit; an independent higher-iteration check converged with unchanged validation counts and C-index. This was not treated as a new model change.

`docs/figure2_cv_revision_reconciliation.csv` records 165 identical outputs, four PDF-metadata-only differences, eight intended Figure 2/3 file differences, five numeric differences in CV or typography outputs, four expanded CV schemas and one audit row-count change. Of the 13 entries labelled new, six are the new fold-count/assignment tables and seven are processed or supplementary-data files whose directories were not included in the pre-revision snapshot; that label is not evidence that those seven scientific inputs were changed. The final audit validated 107 claims and 16 figure-provenance entries with zero failures, and all 16 formal figure files passed the typography audit. The revised Figure 2 passed an independent PNG/PDF visual check; the DOCX contains the revised CV numbers and no embedded figures, and all 18 shared PDF pages remain text-identical to the review copy before its three appended figure pages.

### Figure 2 annotation clarification (2026-10-21)

The author explicitly approved these two annotation changes; no statistical or layout redesign was authorised in this revision.

- **A/B before and after:** `(n=343)` became `(CV n=343)` in `km_annotation()` in `scripts/17_fit_therapy_end_landmark.R`. The value is read from `n_cv`, not typed into the figure. This distinguishes the 343-patient CV cohort from the 372-patient KM/log-rank cohort shown in the group legends and risk tables.
- **D before and after:** the bootstrap subtitle now includes `ORR selected: 0%`, calculated from the zero ORR lowest-AIC selection frequencies in all three displayed settings. The yellow legend entry remains; there is no yellow bar segment because its frequency is zero, not because the cohort contains no objective responders.
- **Updated outputs:** the analysis-native and staged Figure 2 PNG/PDF files, `manuscript/submission/ESMO_Open_manuscript_review_copy_with_figures.pdf`, figure-provenance/typography audits and the cumulative CV reconciliation record. Figure 2 was re-rendered from locked tables without refitting models; every statistical-result CSV was byte-identical to the annotation baseline before audit regeneration. C-indices, paired gains, KM curves, risk-table counts, HRs, bootstrap frequencies, the 120-month display and colours were unchanged.
- **Verification:** both annotations are 8 pt and were checked for clipping. Stage 24 passed 107 manuscript claims and 16 figure-provenance entries with zero failures; stage 26 passed all 16 formal figure files. `make check`, including the CV regression checks, passed. All 18 shared PDF pages remain text-identical to the upload manuscript, and the updated Figure 2 annotations were confirmed on review-copy page 20.
- **Traceability:** the pre-change snapshot is `../archive/figure2_annotation_pre_20261021_001752/`; compiler output is `logs/figure2_annotation_latex.log`. The 299-entry `docs/SHA256SUMS.txt` inventory was refreshed and verified. The pending AUC proposal below was not changed or implemented by this annotation revision.

### AUC method proposal: pending separate author approval

The former pooled-linear-predictor 36-month AUCs were not replaced or treated as the revised C-index estimand. They remain in analysis tables solely as diagnostics, with `auc_method=legacy_pooled_lp` and `auc_status=pending_method_review_not_reported`; their numerical results are no longer reported in the revised survival-discrimination manuscript paragraphs. This does not affect the distinct binary-response AUCs in the molecular analyses.

The proposed separate evaluation uses cumulative/dynamic marginal-IPCW AUC within each validation fold at 36 months, then aggregates by IPCW case-control pair weight. In the installed timeROC 0.4 interface, the fold denominator is `n^2 * CumulativeIncidence[j] * survProb[j]`, with `j=match(36, times)`; the repeat value would be the sum of denominator times fold AUC divided by the sum of denominators. This differs from a simple average of fold AUCs and requires explicit handling of horizon ties, censoring support and folds without cases or controls. It avoids pooling scores from different fitted models. The proposal was checked against the installed interface and a read-only real-data diagnostic but has not been implemented as a reported result.

## Figure 3 revision (2026-10-21)

The author approved items 1-6 after two rounds of four-party review. The pre-change snapshot is `../archive/figure3_pre_revision_20261021_005236/`. This revision changes display code and explanations, not scientific estimates or internal analysis keys.

1. **Time-origin wording:** A/C labels and the Figure 3 legend now refer to the end of first-line therapy rather than chemotherapy; the existing analysis-table filter keys and time calculations are unchanged.
2. **KM denominator and risk table:** B now explicitly shows `CV n=69` and a four-group number-at-risk table at 0, 24, 48, 72, 96 and 120 months. The 24 counts are derived from the observed GSE63885 landmark cohort and exported to `results/tables/manuscript/figure3b_number_at_risk.csv`. Curves remain solid; the 120-month horizon is display-only and does not administratively censor the analysis.
3. **External pooling:** A and its legend identify response-only, covariate-unadjusted HRs and Wald 95% CIs, cohort-level REML random-effects pooling with k=3 and n=138 total participants, and the existing HKSJ 95% interval 0.30-59.3 with a Table S3 pointer. The primary Wald interval and the exclusion of the retracted source from pooling are retained.
4. **Selection sensitivity:** C displays `PD n=36*` for date imputation, explained as the median PD count across 200 draws. The legend distinguishes IPW robust Wald CIs from Rubin-pooled 95% CIs.
5. **Reference band:** The 0.67-1.50 grey band is labelled as reference bounds, not evidence of equivalence. All plotted intervals remain 95% CIs; no 90% intervals or equivalence conclusion were added.
6. **Native-size layout:** A/C use aligned, fixed-width numeric columns headed `HR (95% CI)` and `n`/`PD n`; CI ranges use en dashes and repeated row labels are shortened. The canvas increases from 190 x 200 to 190 x 230 mm without reducing text size or scaling the figure downstream.

Figure 3 was redrawn from locked result tables without rerunning Cox, CV, bootstrap or imputation procedures. The rendering transcript is `logs/figure3_display_render.log`; the submission build transcript is `logs/figure3_revision_latex.log`. The analysis-native and staged Figure 3 PNG/PDF files, source/submission legend, DOCX/PDF manuscript, local illustrated review copy and audits were synchronised. Figure 1 and Figure 2 assets remain byte-identical to this baseline.

- **Output reconciliation:** `docs/figure3_revision_reconciliation.csv` lists 187 identical outputs, the four intended Figure 3 asset changes, the new risk-count table, and three regenerated audit tables (figure hashes, typography/height and added claims). Seven other entries labelled `NEW_OUTPUT` are processed or supplementary-data files whose directories were not copied into the baseline, not newly changed scientific inputs. Every pre-existing statistical-result CSV is byte-identical.
- **Validation:** Stage 24 passes 110 claims and 16 figure-provenance entries with zero failures, including three new claims for pooled k/n, the existing HKSJ interval and the starred median PD count/imputation draws. Stage 26 passes all 16 formal files; Figure 3 is 190 x 230 mm, minimum 8.00 pt, embedded Arial vector PDF and 600-dpi PNG. `make check`, including the CV regression tests, passes.
- **Submission checks:** Main text plus legends is 3,993 of 4,000 words; the abstract remains 298 words. The 18-page upload PDF and the 21-page review copy share 18 text-identical pages. Review page 21 contains the revised Figure 3 at native size; its risk table, labels and long CIs were visually inspected. The revised legend was checked in PDF and DOCX; the upload DOCX contains no embedded figures. The separate AUC proposal remains pending and was not implemented.
- **Independent read-only acceptance:** A reviewer independently checked all 24 risk counts using the 69 observed cases and 61 deaths, matched every A/C HR and CI to the unchanged source tables, and confirmed alignment and complete long intervals. The reviewer noted tight spacing between the two C-axis title lines; increasing only their line height to 1.2 gives a final extracted-text bounding-box gap of 2.59 pt, with all text inside the page. Cairo rounds the configured 190 x 230 mm PDF to 189.79 x 229.66 mm, within the audit's 0.5 mm tolerance. Readable text is at least 8 pt; the existing smaller '+' censor glyphs are plotting symbols explicitly excluded by stage 26, not below-threshold prose. The final spacing change was re-rendered and the audits and shared-page identity checks were rerun.
- **Checksum inventory:** The existing `docs/SHA256SUMS.txt` inventory was refreshed and verified with 301 entries, adding only the intentional risk-count and Figure 3 reconciliation CSVs. Ignored compiler logs, rendered inspection images, dependencies, private path configuration and the local illustrated review copy remain outside the release inventory.

### Figure 3A source encoding (2026-10-21)

After the author asked what the Panel A colours meant, four independent reviewers (clinical epidemiology, statistics, publishing, information design) assessed four options: keep colour and add a key; switch to greyscale shapes and add a key; place a key inside the panel; or leave unchanged. All four ranked greyscale first, rejected an in-panel key, and considered no change unacceptable. Cross-questioning resolved three remaining differences: the pooled diamond is not enlarged (marker size would imply precision), the retracted marker is darkened rather than the text being greyed, and Figure 1 is left unchanged because it already defines the triangle, diamond and open circle inline.

- **Before:** Panel A encoded source by colour and shape: TCGA black circle; external cohorts blue `#0072B2` triangle; pooled estimate green `#009E73` diamond; retracted source grey `#999999` open circle. The legend had no key. Green and blue are the same values used for CR and PR in Panel B, and the retracted marker was about 2.85:1 against white with a 0.52-pt outline, below the 3:1 guideline for graphical objects.
- **After:** Panel A uses a local neutral scale only: TCGA, external cohorts and pooled estimate `#333333`; retracted source `#6E6E6E`; shapes, point sizes, confidence intervals and axes are unchanged; the retracted open circle uses a 0.7-pt outline, matching Figure 1. The figure legend adds 14 words after the HKSJ sentence: `Symbols: circles, TCGA-OV; triangles, external cohorts; diamond, cohort-level REML pool; open circle, retracted source.` No in-panel key was added; Figure 1, Figure 2, Figure 3B and Figure 3C were not modified.
- **Verification:** Figure 3 was redrawn from locked tables without rerunning Cox, CV, bootstrap or imputation procedures. PDF path colours in Panel A are 39 paths at `#333333` and four at `#6E6E6E`, with no residual blue or green. Stage 24 passes 110 claims and 16 provenance entries; stage 26 passes all 16 formal files at 8.00 pt minimum, and the native size remains 189.79 x 229.66 mm. Main text plus legends is 3,993 of 4,000 words. The 18 shared upload/review pages remain text-identical and the revised Panel A and legend were checked on review page 21 and manuscript page 15. All pre-existing statistical-result CSVs are byte-identical to the pre-revision baseline; `docs/figure3_revision_reconciliation.csv` retains the same status counts (187 identical, four intended Figure 3 binaries, one new risk table, three regenerated audits and seven directory-coverage new outputs). The 301-entry checksum inventory was refreshed and verified. Rendering and build transcripts are `logs/figure3_panelA_greyscale_render.log` and `logs/figure3_panelA_greyscale_latex.log`.

### Figure 3 open-axis harmonisation (2026-10-21)

The author then noted that Figure 3 kept full panel boxes while Figure 2A-C use open axes, and asked the four reviewers to re-discuss. The first border review had worked from a wrong premise (that the Figure 2 Kaplan-Meier panels were boxed); with the corrected evidence all four reviewers changed their verdict and unanimously recommended harmonisation, ranking an added separator line, a KM-only change and no change lower. The full-manuscript rebuild (rather than a locked-table extraction) was used this time, so Figure 1 PDFs differ from the baseline only in embedded production metadata.

- **Before:** The Figure 3A and 3C forests and the 3B Kaplan-Meier panel used the default boxed `theme_bw` panel with default grey major gridlines; the risk table and numeric columns were already borderless.
- **After:** The three coordinate panels reuse the exact Figure 2A-C open-axis layer (a shared `figure3_open_axes` theme in `scripts/20_build_manuscript_outputs.R`): `panel.border` removed, black 0.4-pt left/bottom axis lines, `grey88` 0.3-pt major gridlines. Symbols, palettes, statistics, legend text, the risk table, the numeric columns and Figures 1-2 are unchanged. The manuscript convention is now uniform: coordinate panels open-axis (Figure 2A-C, Figure 3A-C), composite summary panels boxed (Figure 2D-E), annotation modules borderless.
- **Verification:** Full rebuild through scripts 20, 21 and 23; stage 24 passes 110 claims and 16 provenance entries and stage 26 passes all 16 formal files (minimum 8.00 pt, native 189.79 x 229.66 mm). Reconciliation against the pre-revision baseline (`docs/figure3_revision_reconciliation.csv`, superseding the earlier counts) shows every statistical-result CSV byte-identical; differences are the four intended Figure 3 binaries, 185 identical plus two Figure 1 PDFs that differ only in PDF metadata, the regenerated audits, the risk-count table and the seven directory-coverage outputs. The embedded review figure was visually inspected on review page 21. `make check`, including the CV regression tests, passes. The 301-entry checksum inventory was refreshed and verified (301/301 OK). Transcripts: `logs/figure3_open_axes_render.log`, `logs/figure3_open_axes_stage21.log`, `logs/figure3_open_axes_stage23.log`, `logs/figure3_open_axes_stage24.log`, `logs/figure3_open_axes_stage26.log`; inspection image `logs/figure3_open_axes_review_page21.png`. The separate AUC proposal remains pending and was not implemented.

## Figure S1 revision (2026-10-21)

The per-figure review of the supplementary figures began with Figure S1. Four independent reviewers (clinical epidemiology, statistics, publishing, information design) identified six actionable findings and, after cross-questioning, converged on a package the author approved in full (R1-R6). All four reviewers rejected unifying the interval and test types (it would have created a third set of numbers), and cross-examination flipped Panel B from a connecting line to points only, because the 180-to-210-day jump is a discrete reclassification of two patients and the plotted P values are independent tests.

- **Before:** Panel A drew in-panel `plateau p` annotations to the right of the intervals, used an x axis spanning 0.4-7 to make room for them, titled the axis "OS from end of chemotherapy", and kept boxed panels; Panel B joined the seven scenario points with a line; Panel C encoded PD share with orange `#E69F00`, green `#009E73` and blue `#0072B2` - the last two hex-identical to the CR and PR response colours, violating the configuration's own same-domain-same-colour charter. The legend named "stochastic imputation of missing end-of-chemotherapy dates (200 draws)" without disclosing that the four row groups use different interval and test types.
- **After:** Panel A pairs the forest with a 36-mm numeric column (`HR (95% CI)`, `plateau p`) reusing the audited Figure 3 column pattern, tightens the x range to 0.4-3.2 behind a data-range assertion, retitles the axis "OS from end of first-line therapy", and opens all three coordinate panels with the manuscript open-axis layer. Panel B shows the seven points without a connecting line on explicit 90-300-day ticks. Panel C uses an ordered grey ramp (`#777777`, `#4d4d4d`, `#262626`) with the legend inside the panel. The legend discloses that the main and weighted rows use robust-SE intervals with robust Wald plateau tests, the imputation row Rubin-pooled intervals with a D1 pooled test, and the restriction rows model-based Wald intervals with likelihood-ratio plateau tests (so the main-analysis interval differs slightly from the model-based Figure 3C interval at the same point estimate); labels the Panel B statistic as a likelihood-ratio plateau test with only the seven pre-specified dates evaluated; and explains the beyond-180-day rise as two PD patients (and one CR patient) leaving the analysed set (`PD n 36→34`).
- **Verification:** Script 18 reruns deterministically - all twelve `results/tables/ov_selection_regimen_power/` CSVs are byte-identical to the pre-revision baseline. The retired `figure_s1_imputation_draws` claim (the draws count no longer appears in the legend) is replaced by two claims pinning the caption's analysed PD counts (36 at the 180-day date, 34 at the 210-day date) to the tipping table; stage 24 passes 111 claims and 16 provenance entries. Stage 26 passes all 16 formal files; S1 is 189.79 x 179.92 mm at 8.00 pt minimum with 67 extracted text spans (was 54). Reconciliation against the baseline (`docs/figureS1_revision_reconciliation.csv`) compares the same 202 outputs as the earlier reports: 181 identical, two Figure 1 PDFs metadata-only, the four intended S1 binaries plus the four Figure 3 binaries from the earlier approved batches, the three regenerated audits (provenance text, typography numerics, and the claim-audit row count 209 to 216 accumulated across the approved post-baseline revisions) and the eight known directory-coverage outputs. The appendix page 12 figure and legend were visually inspected; the 18 shared upload/review pages remain text-identical; `make check`, including the CV regression tests, passes; the 302-entry checksum inventory was refreshed and verified. Transcripts: `logs/figureS1_revision_render.log`, `logs/figureS1_revision_stage20.log`, `logs/figureS1_revision_submission.log`, `logs/figureS1_revision_docx.log`, `logs/figureS1_revision_latex.log`, `logs/figureS1_revision_claims.log`, `logs/figureS1_revision_typography.log`, `logs/figureS1_revision_reconcile.log`, `logs/figureS1_revision_make_check.log`; inspection image `logs/figureS1_revision_appendix_page12-12.png`. The separate AUC proposal remains pending and was not implemented.

### Figure S1C palette re-review (2026-10-22)

After the author asked why the figure had become monochrome, the four reviewers independently re-examined the Panel C palette from verified evidence: every usable Okabe-Ito hue is already semantically allocated (green CR/Pooled, blue PR/External/treated, vermillion PD/NCR, pink SD, orange ORR model, sky-blue 6-month landmark, black TCGA/therapy-end; the only free hue, yellow, is 1.26:1 on white and unusable for thin lines), so any colour reintroduction must import a new hue family. All four ranked the approved ordered grey ramp first (clinical epidemiology, statistics and publishing ranked a purple ramp second, information design an orange ramp second), noting that candidate ramps carry colour-vision-deficiency adjacency risks - the orange ramp to the PD vermillion and ORR orange, the purple ramp to the SD pink - which would transfer the conflict R6 removed onto other semantic domains. White-background contrast: greys 4.48/8.45/15.13, orange ramp 4.31/6.67/9.57, purple ramp 3.78/10.18/13.93. The stated flip conditions (print-proof indistinguishability, a journal greyscale ban, standalone colour propagation) do not hold, and the author confirmed the grey ramp. No files were modified; the question is closed.

## Figure S2 revision (2026-10-22)

The supplementary per-figure review continued with Figure S2 (operational HGSOC sensitivity forest). Four independent reviewers agreed on five findings and converged after one cross-questioning round (the publishing reviewer initially wanted to keep `theme_classic` as a third approved style but withdrew after verifying that REPRODUCIBILITY.md records the open-axis convention as uniform and that the 2026-10-21 ruling outranks the classic base). The author approved the package in full.

- **Before:** the forest used a boxed `theme_classic` base, carried an in-figure title ("Operational HGSOC sensitivity analysis") duplicating the caption, spanned 70 mm, and showed only point estimates and intervals - the per-response n and HR text lived solely in Table S2.
- **After:** the panel opens its axes with the manuscript open-axis layer, the in-figure title is removed, and the forest pairs with a 36-mm numeric column (`HR (95% CI)` header, per-row `3.51 (2.44-5.03)`-style estimates, right-aligned per-response n 49/17/27) reusing the audited Figure 3 / Figure S1 column pattern, on the PR/SD/PD rows only (CR is the reference and carries no interval). Height drops from 70 mm to 45 mm with tightened discrete-y expansion. `library(patchwork)` is added to script 19 for the column composition. The Figure S2 caption and the Table S2 caption no longer name "script 19". No statistical procedure, number, or claim changed.
- **Verification:** Script 19 reruns deterministically - all ten `results/tables/ov_hgsoc_sensitivity/` CSVs are byte-identical to the pre-revision baseline except `sessionInfo_R20.txt`, which now lists `patchwork` (and its `labeling` dependency) among the loaded packages, the direct and expected consequence of the added import. Stages 20-23 rebuild without error; stage 24 passes 111 claims and 16 provenance entries and stage 26 passes all 16 formal files (S2 now 189.79 x 44.80 mm, 8.00 pt minimum, 15 text spans). Reconciliation against the baseline (`docs/figureS2_revision_reconciliation.csv`) again compares 202 outputs: 176 identical, two Figure 1 PDFs metadata-only, the four intended S2 binaries plus the four S1 binaries and the four Figure 3 binaries from the earlier approved batches, the three regenerated audits, the expected `sessionInfo_R20.txt` binary refresh, and the eight known directory-coverage outputs. The checksum inventory was refreshed to 303 entries and verifies clean. Transcripts: `logs/figureS2_revision_render.log`, `logs/figureS2_revision_stage20.log`, `logs/figureS2_revision_stage21.log`, `logs/figureS2_revision_stage22.log`, `logs/figureS2_revision_stage23.log`, `logs/figureS2_revision_stage24.log`, `logs/figureS2_revision_stage26.log`, `logs/figureS2_revision_stage25.log`. The separate AUC proposal remains pending and was not implemented.

## Figure S3 revision (2026-10-22)

The supplementary per-figure review continued with Figure S3 (CR vs NCR across TCGA tumour types). Four independent reviewers agreed on the open axes, title removal, reference-line colour and axis wording, and that per-row HR/n must be visible, but diverged on the numeric-column structure (statistics and clinical epidemiology preferred a three-column label style that drops the legend; publishing preferred reusing the audited 36-mm column and keeping the legend; information design preferred paired subset columns). After one cross-questioning round (rankings B>A>C, B>A>C, A>C>B, C>B>A) the chair ruled for the audited 36-mm column pattern (Option A) on the project's standing pattern-reuse governance: it is the lowest-alignment-risk structure, keeps the encoding the visual reviewer had already approved, and matches Figure 3A/S1A/S2. The author approved the package in full and declined an optional caption clarification about the end-of-therapy pooled estimate (word-budget constraint).

- **Before:** the forest used a boxed `theme_bw` panel with default grey gridlines, carried an in-figure title duplicating the caption, ordered cancers by the implicit mean HR across the two subsets, drew the HR=1 reference line in the default dark grey, used "NCR vs CR" in the axis title, and showed neither HR text nor n anywhere in the figure (the n-bearing label variable was computed but never plotted).
- **After:** the panel opens its axes with the manuscript open-axis layer; the in-figure title is removed; a 36-mm numeric column reusing the audited Figure 3/S1/S2 pattern displays `HR (95% CI)` and per-row n for all 18 dodged rows (11 cancers x all/treated subsets, single-subset cancers centred); the `Subset` legend is collected to the right of the column; the HR=1 line uses the neutral mid grey `#777777`; the axis title reads "OS hazard ratio, NCR versus CR (log scale)"; cancers are ordered explicitly by the all-subset (primary analysis) HR. Height remains 150 mm. No statistical procedure, number, caption word or claim changed.
- **Verification:** Script 16 reruns deterministically - all eight `results/tables/pancancer_topology/` CSVs are byte-identical to the pre-revision baseline. Stages 20-23 rebuild without error; stage 24 passes 111 claims and 16 provenance entries and stage 26 passes all 16 formal files (S3 now 189.79 x 149.93 mm, 8.00 pt minimum, 56 text spans, up from 19). Reconciliation against the baseline (`docs/figureS3_revision_reconciliation.csv`) again compares 202 outputs: 170 identical, four PDFs metadata-only (the two Figure 1 PDFs plus `four_state_hr_by_set.pdf` and `FigureS4_pancancer_four_state.pdf`, which script 16 re-saves with unchanged content and refreshed creation metadata), the four intended S3 binaries plus the four S1, four S2 and four Figure 3 binaries from the earlier approved batches, the three regenerated audits, the expected `sessionInfo_R20.txt` binary refresh, and the eight known directory-coverage outputs. The 18 shared upload/review manuscript pages remain text-identical; `make check`, including the CV regression tests, passes. The checksum inventory was refreshed to 303 entries and verifies clean. Transcripts: `logs/figureS3_revision_render.log`, `logs/figureS3_revision_stage20.log`, `logs/figureS3_revision_stage21.log`, `logs/figureS3_revision_stage22.log`, `logs/figureS3_revision_stage23.log`, `logs/figureS3_revision_stage24.log`, `logs/figureS3_revision_stage26.log`, `logs/figureS3_revision_stage25.log`, `logs/figureS3_revision_make_check.log`; inspection image `logs/figureS3_revision_appendix_page.png` (appendix page 15). The separate AUC proposal remains pending and was not implemented.

## Figure S4 revision (2026-10-22)

The supplementary per-figure review continued with Figure S4 (four-category topology in eligible tumour types). Four reviewers agreed on the open axes, reference-line colour, versus wording and readable strip labels, and the clinical-epidemiology reviewer flagged that the figure carries no n/events anywhere (the caption notes only the ovarian n; no supplementary table holds the per-set per-landmark denominators - Supplementary Table S4 is the label-semantics audit, and `topology_models_by_set.csv` lives only in the repository). A cross-questioning round on the carrier ranked an in-panel annotation first (3/4), a two-row facet restructuring second, and a caption pointer last, but geometric verification showed the annotation cannot work: the bladder-cancer PR/SD whiskers reach 12.7 on the log axis, and four 8-pt text lines do not fit between that ceiling and the panel top. The chair therefore ruled for the facet restructuring, which every reviewer had confirmed as workable and which also dissolves the dodge. The author approved the package in full.

- **Before:** five facets in one row (`facet_wrap`), each dodging two analyses (Diagnosis grey circles, Therapy-end landmark black squares) with a shared legend at the bottom; boxed panels, default gridlines and reference line, machine-style strip labels (`BLCA_all`), y-axis title "OS HR vs CR (log scale)", height 85 mm, and no n, events or HR text.
- **After:** `facet_grid` with analysis rows (Diagnosis, Therapy-end landmark) by set columns (five top panels, five bottom panels; the two bottom-row bladder/LGG columns coincide with their treated counterparts because the therapy-end analysis set is by construction the treated set, which the identical strip n values now make visible), readable strip labels ("BLCA, all"), a single `#333333` pointrange style with the legend removed (the row strips carry the analysis identity), open axes with light-grey borderless strips, the neutral-grey reference line, the y-axis title "OS hazard ratio versus CR (log scale)", height 130 mm, and a one-line 8-pt annotation per panel ("n=354, 146 deaths") placed 35% above the tallest PR/SD whisker with an assertion keeping it inside the panel. The caption is unchanged. No statistical procedure, number or claim changed.
- **Verification:** Script 16 reruns deterministically - all eight `results/tables/pancancer_topology/` CSVs are byte-identical to the pre-revision baseline. Stages 20-23 rebuild without error; stage 24 passes 111 claims and 16 provenance entries and stage 26 passes all 16 formal files (S4 now 189.79 x 129.82 mm, 8.00 pt minimum, 44 text spans, up from 30). Reconciliation against the baseline (`docs/figureS4_revision_reconciliation.csv`) again compares 202 outputs: 168 identical, two Figure 1 PDFs metadata-only, the four intended S4 binaries plus the four S1, S2, S3 and Figure 3 binaries from the earlier approved batches, the three regenerated audits, the expected `sessionInfo_R20.txt` binary refresh, and the eight known directory-coverage outputs. The 18 shared upload/review manuscript pages remain text-identical; `make check`, including the CV regression tests, passes. Transcripts: `logs/figureS4_revision_render.log`, `logs/figureS4_revision_stage20.log`, `logs/figureS4_revision_stage21.log`, `logs/figureS4_revision_stage22.log`, `logs/figureS4_revision_stage23.log`, `logs/figureS4_revision_stage24.log`, `logs/figureS4_revision_stage26.log`, `logs/figureS4_revision_stage25.log`, `logs/figureS4_revision_make_check.log`; inspection image `logs/figureS4_revision_appendix_page.png` (appendix page 16). The separate AUC proposal remains pending and was not implemented.

## Figure S5 revision (2026-10-22)

The per-figure review closed with Figure S5 (external direction validation of the locked proliferation score). Four reviewers verified that the plotted cohort intervals and pooled diamonds reproduce `per_cohort_noncr_minus_cr_estimates.csv` and `meta_analysis_noncr_minus_cr.csv` exactly and that the main-text value (+0.03 SD, 95% CI -0.32 to 0.37) matches the pre-specified primary pool. They converged on the same consistency upgrades already applied to S1-S4 (no in-figure title, open axes, neutral-grey null line, 36 mm numeric column), but split on two points: whether the retracted cohort needs a distinct marker (house-style reviewer: required; data and reader reviewers: the text label suffices) and whether "(primary, REML)" should lose the REML tag (reader reviewer: the tag implies a contrast that does not exist; statistics reviewer: it names the fitted model). Cross-questioning resolved the marker unanimously for the approved Figure 3A encoding, noting that the Figure 3A retracted row already carried a text label and was still re-encoded after review. The label question ended 2-2; the chair ruled for "Pooled external (primary)" because all three pools are REML (the caption says so once) and the asymmetry, not the estimator word, was the only informative in-figure qualifier. The author approved the package in full and declined the optional caption additions, so the caption and the 3,993-word budget are unchanged.

- **Before:** in-figure title "Locked proliferation score: external direction validation" (also at odds with the caption's "External validation"), boxed `theme_bw` panel, `grey50` null line, no numeric values, the retracted source drawn as a `#333333` filled square identical to primary cohorts and labelled with stacked parentheses ("PMID17290060 (retracted) (CR 85 / NCR 32)"), and the primary pool labelled "Pooled external (primary, REML)".
- **After:** title removed (the caption carries the title), open axes (blank border, black 0.4-pt left/bottom lines, `grey88` 0.3-pt gridlines), the null line in `figure_style$neutral[["mid"]]` (#777777) with linetype 2, a 36 mm "Estimate (95% CI)" column listing all eight rows to two decimals (Wald intervals for cohorts, REML intervals for pools, exactly as plotted), cohort sizes retained in the y-axis labels, the retracted source as a `#6E6E6E` open circle with a 0.7-pt outline (the approved Figure 3A encoding) and the comma-form label "PMID17290060, retracted (CR 85 / NCR 32)", and the primary pool labelled "Pooled external (primary)". Height remains 85 mm. No statistical procedure, estimate, table or caption word changed; the label helper is local to S5 so the informal KM diagnostic figure keeps its original title.
- **Verification:** Script 14 reruns deterministically - all 19 `results/tables/phase4_external_validation/` CSVs are byte-identical to the pre-revision baseline, and the informal `landmark_os_by_response.png` is byte-identical again after the label helper was scoped to S5. Stages 20-23 rebuild without error; stage 24 passes 111 claims and 16 provenance entries and stage 26 passes all 16 formal files (S5 now 189.79 x 84.67 mm, 8.00 pt minimum, 22 text spans, up from 14). Reconciliation against the baseline (`docs/figureS5_revision_reconciliation.csv`) compares 202 outputs: 163 identical, three PDFs metadata-only (the two Figure 1 PDFs and `landmark_os_by_response.pdf`), the four intended S5 binaries plus the four S1, S2, S3 and S4 binaries and the four Figure 3 binaries from the earlier approved batches, `sessionInfo_R20.txt`, the three regenerated audits, and the eight known directory-coverage outputs. The 18 shared upload/review manuscript pages remain text-identical and the appendix figure renders correctly on page 17 (`logs/figureS5_revision_appendix_page17.png`). `make check`, including the CV regression tests, passes. The checksum inventory was refreshed to 306 entries - the S5 reconciliation report was added and the `manuscript/strobe/STROBE_checklist.md` entry, dropped by an earlier refresh although the file is present, was restored - and all 306 verify. Transcripts: `logs/figureS5_revision_stage14.log`, `logs/figureS5_revision_stage20.log`, `logs/figureS5_revision_stage21.log`, `logs/figureS5_revision_stage22.log`, `logs/figureS5_revision_stage23.log`, `logs/figureS5_revision_stage24.log`, `logs/figureS5_revision_stage26.log`, `logs/figureS5_revision_stage25.log`, `logs/figureS5_revision_make_check.log`. The separate AUC proposal remains pending and was not implemented.

## Molecular reporting clarification (2026-10-22)

The author asked how the manuscript should answer a reviewer who asks why no molecular mechanism analysis was performed, given that the exploratory transcriptomic analyses returned no definitive result and were therefore not displayed as figures. The agreed answer was a reporting clarification at the level of the cover letter and supplementary headings only; the main text, all estimates and all figures are unchanged.

- **Before:** the cover letter did not mention the transcriptomic analyses. The supplementary Methods and Results each carried the neutral heading `Molecular arm`, and the Results subsection opened directly with "No gene reached FDR<0.05", so a reader first met a null result without knowing why no figure followed.
- **After:** the cover letter adds one sentence after the existing limits paragraph: "Transcriptomic analyses (differential expression, pathway enrichment and weighted gene co-expression network analysis) did not identify a reproducible molecular correlate of the CR threshold. These analyses are summarised in the Supplementary Methods and Results rather than displayed as genome-wide figures, because no gene, module or pathway survived false-discovery-rate control and no signal replicated in the external cohorts." Both supplementary headings become `Exploratory molecular analyses`, and the Results subsection opens with: "Genome-wide figures are not shown because no gene, module or pathway survived FDR control and no signal replicated externally; the pre-specified analyses and effect sizes are summarised below." All existing molecular estimates, locked-score results, interaction results and external-validation results are retained verbatim.
- **Rationale:** the paper's question is the clinical grouping of response, not a mechanism, and the exploratory arm was pre-specified as secondary. Reporting the negative result with its effect sizes is more informative than a token genome-wide figure that would invite overinterpretation. Full exploratory figures remain available for a reviewer request but are not part of the submission.
- **Verification:** stages 21, 23, 24, 25 and 26 rebuild and pass. Main text is 3,038 words, main text plus legends 3,993 of 4,000 and the abstract 298 of 300. Pagination is unchanged (manuscript 18 pages, supplementary appendix 20, illustrated review copy 21). The manuscript PDF and the illustrated review copy are byte-identical to the pre-revision baseline; the manuscript DOCX is text-identical and differs only in document metadata; the cover-letter and supplementary DOCX/PDF diffs contain only the intended sentences and headings. Stage 24 passes 111 claims and 16 provenance entries, stage 26 passes all 16 formal figure files, and all 18 shared upload/review pages remain text-identical. Reconciliation (`docs/molecular_reporting_revision_reconciliation.csv`) compares 202 candidate outputs: 195 identical, with the seven `NEW_OUTPUT` rows being processed or supplementary-data files that the pre-revision snapshot excluded, not new scientific inputs; every statistical-result CSV is byte-identical. The rendered appendix pages 7-8 were inspected: the new heading is followed by its rationale sentence on the same page, and the existing results paragraph begins page 8. `make check`, including the CV regression tests, passes. The checksum inventory was refreshed to 307 entries and verifies clean. Baseline snapshot: `../archive/molecular_reporting_pre_20261022_232558/`; transcripts: `logs/molecular_reporting_stage21.log`, `logs/molecular_reporting_stage21b.log`, `logs/molecular_reporting_stage23.log`, `logs/molecular_reporting_stage23b.log`, `logs/molecular_reporting_stage24.log`, `logs/molecular_reporting_stage24b.log`, `logs/molecular_reporting_stage26.log`, `logs/molecular_reporting_stage26b.log`, `logs/molecular_reporting_stage25.log`, `logs/molecular_reporting_stage25b.log` and `logs/molecular_reporting_make_check.log`. The separate AUC proposal remains pending and was not implemented.

## Clean submission refactor (2026-10-23)

After a read-only inventory and four-party clinical, statistical, engineering and publishing review, the author approved an isolated maintainability refactor, preservation of scientific simulation and fixed test fixtures, and archival rather than deletion of old working materials. The new `github_release_clean` tree was initialized from all 307 verified files in the preceding submission inventory, plus the inventory itself. The previous `github_release`, `github_submission` and historical review baselines were not modified.

### Code and configuration

All autonomous R/Python/JavaScript files retain numbered English names, credited authors and inherited creation dates, and have English purpose/input/output/runtime headers and substantive algorithm comments. The established scientific stage numbers remain unchanged. The two new utilities are `28_submission_utilities.py` (shared configuration/CSV/path/hash reads) and `29_prepare_release_snapshot.py` (non-destructive policy-based packaging). The exact repeated platinum-taxane definition in stages 18 and 20 is now shared in `R/00_project_configuration.R`; different estimands and statistical failure rules were not merged.

Remaining selected design settings were moved to versioned configuration without changing their values or ordering: Phase 0 grade restrictions, PC association count, SVA cap, HRR panels/variant classes, MSigDB source selections, locked biological axes, CNV/RPPA features, the 30 interaction rows, source filenames and treatment-type lists. The historical rounded Wald multiplier remains 1.96, the power censoring multiplier remains 1.2, stage 17's mice iteration count remains its previous default of five, and empirical split percentiles remain 0.05/0.95. Stage-specific month conversions remain distinct. Mathematical coefficients, array indexes, source parsing schemas, covariate/estimand structures and explicitly labelled validation fixtures were not replaced with artificial configuration abstractions. Bootstrap, imputation, CV, permutation/Monte-Carlo and power simulation remain inferential procedures, not mock input cohorts.

The shared semantic palette and marker mappings are now read from `config/submission_profile.json` and were independently checked for identical values, order, names and numeric types. DOCX table styling/layout and typography tolerances are versioned beside the document profile. `config/workflow.json`, `config/reference_overrides.json`, `config/reproduction_contract.json` and `config/release_policy.json` separate workflow order, previously verified bibliography annotations, independent regression expectations and upload exclusions from implementation logic. S1 attrition counts, S2 sample/event counts and S5 pooling size are now read from their unique real source rows; the complete generated captions remain unchanged.

Portable defaults are read from `paths.example.yml`; private and environment overrides are optional. Relative overrides in R and Python are resolved against the repository root. Explicitly requested missing private files or required settings fail clearly. These path semantics and additional negative-input checks implement the author's requested portable-path/no-silent-default scope; they do not change cohort selection. Python dependencies were recorded from the actual verification environment.

### Verification actually performed

- `make check` passes naming, English-header/comment/explicit-output checks, R/Python/JSON/JavaScript syntax, complete runtime configuration loading, palette loading and the original concordance regression fixtures. Explicit relative and absolute results-path overrides and missing/ambiguous real CSV-row selection were checked from a non-repository working directory.
- Stages 17-20 were rerun from the included real clinical derivatives through the configured runner, launched outside the repository. Before audit regeneration, all 202 compared outputs were either identical (192) or PDF-metadata-only (10); every statistical CSV, case-level derivative and PNG was byte-identical. No fold assignment, fitted estimate or stochastic result changed.
- After stages 21, 23, 24 and 26, `docs/cleanup_refactor_reconciliation.csv` records 190 identical outputs, ten metadata-only PDFs, one intentional provenance-audit update (ten changed PDF hashes) and one typography-audit update. The typography difference is the Figure 1 extracted-text-span count 97 to 99; the current PyMuPDF reads both the unchanged baseline drawing and the new drawing as 99 spans, with identical rendered pixels and 8.00 pt minimum text. It is a refreshed historical parser/audit count, not a scientific or layout change.
- Stage 24 passes 111 manuscript claims and 16 figure-provenance entries with zero failures; stage 26 passes all 16 formal files. Every manuscript source file is byte-identical to the baseline. The 18-page manuscript and 20-page supplement have text-identical and pixel-identical pages at the checked rendering resolution; all DOCX package members are identical except `docProps/core.xml` timestamps. The 21-page illustrated review copy shares 18 text-identical upload pages and was saved as local verification evidence before being excluded from the upload tree. Main text/legends remain 3,993 of 4,000 words (3,038 main text); the abstract remains 298 of 300.
- Independent read-only clinical AST review confirmed filtering, coefficient/covariance handling, RNG call order, the approved within-fold pair-weighted C-index, legacy AUC diagnostics and artwork logic unchanged after approved parameter substitution. Independent molecular/source-definition review confirmed the migrated panels, pathway axes, treatment types and 30 interaction rows retain original values, types and order; no unintended scientific filtering change was found.
- Physical `--release-tree` validation and `make check` pass after removing only the new working tree's caches, dependency installation and TeX auxiliaries. The original release inventory still verifies all 307 entries unchanged. The new packaging utility was exercised against a new independent destination: it copied and hash-verified 316 upload files, omitted the optional empty external-cache placeholder and the source checksum file, regenerated the destination inventory, and passed strict physical-tree validation. All three DOCX files (main, supplement and cover letter) have package members identical to the baseline except core timestamps. The final complete working-tree checksum inventory is refreshed after documentation and reconciliation; it also includes the harmless zero-byte external-cache placeholder.

This is not a new full raw-input molecular rebuild: large Xena expression/multi-omic inputs were not configured in this verification session. Stages 01-16 received syntax, configuration and independent static-equivalence review; the full data/API/cache-dependent numerical workflow remains subject to the documented raw-input and package-restoration boundaries. The earlier full raw-input verification remains separately recorded above. The parked 36-month AUC proposal was not implemented.

### Workspace organization and traceability

The former root-level `R`, `data`, `results`, `manuscript`, `internal_docs` and 15 research/report files were moved, without changing bytes, into `../archive/legacy_workspace_20261023/`. All 394 files (574,604,173 bytes) were verified against the pre-migration inventory before and after same-volume renaming. `docs/legacy_migration_manifest.csv` records every original path, destination, size and hash. The source inventory and clinical/build transcripts are retained outside the upload tree in `../archive/refactor_verification_20261023/`. Existing history and both preceding submission directories remain available; the workspace root README points to the clean submission. Only one root operating-system cache file was removed. No raw scientific data or historical baseline was deleted.

The cleaned tree contains formal manuscripts, figures/tables, required compact real derivatives, source and reconciliation manifests, validation evidence and dependency locks; it contains no `node_modules`, logs, private paths, Python bytecode or TeX auxiliary files. Formal outputs in different required formats and small locked upstream summaries remain because downstream reproduction and journal submission depend on them. No Git commit, push or publication was performed.

## Pan-cancer boundary wording (2026-10-23)

The author asked whether a broader pan-cancer analysis was needed. After review, the existing limited exploration was retained without expansion: Supplementary Figures S3–S4 and Supplementary Table S4. Read-only verification reproduced the configured power and treatment-defined eligibility rules, under which only ovarian cancer and LGG were eligible. It also matched every Figure S3 hazard ratio, confidence interval and sample size to its source table, and reconstructed the Figure S4 panel counts from the included real patient derivative. Four-party review and cross-questioning then identified two wording gaps, and the author approved two minimal text revisions:

- **Cover letter:** the external-cohort sentence now states that only GSE63885 permitted four-category topology testing and that it did not replicate the internal NCR topology. Supplementary Data 2 supports this: GSE23554 has no four-category labels and GSE30161 has no SD category.
- **Supplementary Results, Disease specificity:** two sentences were appended. They state that the cross-cancer CR-versus-NCR association does not establish a common four-category topology, that bladder cancer was an exploratory comparison, and that differences in treatment and response-label definitions limit comparability between cancers.

No analysis, figure, table, main-text sentence, highlight or abstract changed, and the parked 36-month AUC proposal was not touched.

After stages 21, 23, 24 and 26, `docs/pancancer_boundary_revision_reconciliation.csv` records all 202 compared outputs as identical. Stage 24 passes 111 claims and 16 provenance entries, and stage 26 passes 16 formal figure files.

The main-manuscript Markdown, TeX, highlights and DOCX text are unchanged. The 18-page manuscript PDF is text- and pixel-identical. The supplement remains 20 pages; only pages 7–8 reflow, and the word-level differences are exactly the appended sentences. DOCX word-level differences are confined to the two approved passages. The illustrated review copy again shares 18 text-identical upload pages. Word counts remain 3,038 for the main text, 3,993 for the main text plus legends and 298 for the abstract.

The pre-change tree is preserved in `../archive/pancancer_boundary_pre_20261023/`. No Git commit, push or publication was performed.

## Cover-letter PDF output (2026-10-23)

At the author's request, stage 23 now generates `ESMO_Open_cover_letter.tex` and `ESMO_Open_cover_letter.pdf` from the same stage-21 Markdown used for the DOCX. It preserves address/signature line breaks, omits the title block and removes the manuscript draft running head; shared profile fonts, spacing and margins remain in use. No approved cover-letter wording was changed. Both PDF pages were visually inspected; PDF and DOCX content matches after whitespace and line-break hyphen normalization. The main and supplementary TeX files remain byte-identical to the pre-build snapshot, and their PDFs retain identical text and rendered pixels. The workflow description and Makefile auxiliary-cleanup pattern were updated for the additional formal output.

## Five substantive reporting revisions (2026-10-23)

After independent clinical, statistical, implementation/data-provenance and editorial review, followed by cross-questioning, the author approved a single bounded revision package. The complete pre-change tree was copied to `../archive/five_issue_pre_20261023/` and all 321 files were hash-matched before editing. Earlier release directories and historical baselines are not modified.

The five decisions are:

1. ORR is an antitumour-activity summary and does not itself assert equal survival within response groups. The objective-response Cox coding is still tested against the four-category model; only the clinical rationale and cover-letter premise are narrowed.
2. Recorded treatment end aligns the time origin but is not a verified response-assessment date. The method no longer claims to avoid guarantee-time bias, and the limitations explicitly retain residual timing/selection concerns.
3. Response-conditioned empirical treatment-end-date draws are reported only as descriptive scenarios. Their eligibility sets vary, donor exchangeability is unverified, and the sampling does not condition on individual survival or propagate donor-distribution uncertainty. Date-pooled intervals and tests are removed from formal prose and inferential figure/table rows; the legacy computation remains preserved. The PD-step field had been the median of draw-specific LRT P values, not a pooled test. The descriptive per-draw median HR, median cohort/PD counts and AIC selection frequencies are read from the existing summary, without resampling or new quantile calculations. The separate fixed-landmark covariate multiple imputation is unchanged. IPW is identified as targeting a 435-person proxy-eligible set, with age mean-imputation, stage/residual missing categories, estimated weights treated as fixed, and adjusted complete-case analysis in 343 patients.
4. PMID17290060 is excluded from formal evidence because the source retraction concerned genomic–clinical outcome misalignment and correction of the analysed data could not be verified. Its individual results and all pools containing it are removed from publication displays/data; the exclusion rationale and historical calculations remain available. The three-cohort primary survival and molecular pools retain their original values and membership.
5. The single four-category WGCNA module FDR of 0.0487797 is acknowledged rather than contradicted by a blanket denial of FDR findings. It did not reproduce across adjustment specifications and does not establish a robust CR-threshold correlate. The nonessential module-size claim was omitted because it was not independently verified from the retained compact tables. External testing is explicitly limited to the locked scores.

The manuscript sources, cover letter, directly affected legends and STROBE locations are synchronized. The analysis-code coverage description is updated for the added publication renderer; the reverse-Kaplan–Meier follow-up reference points to Supplementary Results, rather than conflating it with Table 1's survivor follow-up summary. These are reporting/source-location changes, not recalculated results. The title, Highlights, author/funding statements, main effect estimates, within-fold CV method and parked 36-month AUC proposal are retained.

### Publication-only rebuilding

Stage 20 now dispatches stage 30 before loading analysis packages or setting seeds. The default and `--render-only` entry points select existing CSV records and assemble clean, genuinely clipped vector regions; they do not fit models, run inferential tests, resample dates or compute new quantiles. Only an explicit `--legacy-analysis` argument enters the preserved historical computation, which was not executed for this revision. Fifteen shipped clean regions permit portable rendering without access to the historical baseline PDFs. Required unchanged panels retain their original PNG-region pixels and have exact 144-dpi PDF-region rendering parity.

Seventeen scientific-source SHA256 contracts guard the artwork and retained publication records, including raw/formatted Table 2, the cohort table, the flow-count table and case-level external data. Permitted record removal is applied before hashing where necessary; retained values cannot silently drift. The renderer honours the configured interpreter and explicitly rejects incompatible private or environment results-path overrides because the shipped vector assets are bound to this result bundle.

The local interactive `python3` and the interpreter resolved by a noninteractive R/Make invocation differed; the latter did not have PyMuPDF. No package installation or persistent machine-specific setting was added. Use a dependency-installed Python from `environment/python_requirements.txt` and pass its actual executable:

```bash
export CRNCR_PYTHON="$(python3 -c 'import sys; print(sys.executable)')"
make publication
"$CRNCR_PYTHON" scripts/30_render_locked_publication.py --check-only
python3 scripts/21_build_esmo_submission.py
python3 scripts/23_build_submission_latex.py
make audit
```

DOCX generation also requires the locked Node dependencies; restore them with `npm ci` when absent. Cleanup intentionally removes `node_modules` after output verification, so a clean upload tree is not a preinstalled build environment.

### Final verification completed (2026-10-24)

- `docs/five_issue_revision_verification.csv` records 48 passing checks. Scientific scripts 00-19, the shared R configuration helper, scientific analysis configuration and independent reproduction contract are byte-identical to the pre-revision snapshot. All five checked scientific-result directories, Supplementary Data 1, Figures 2/S2/S3/S4 and every retained raw Table 2 row are unchanged. Formal external sample data contain 148 retained records; the external cohort table contains only the three primary cohorts.
- Isolated source-drift tests changed formatted Table 2's 3.86 to 3.87, the flow count 630 to 631, and the cohort identifier GSE63885 to GSE63886. Each was rejected with a scientific-input-drift error before frozen artwork could be reused; no active scientific input was changed. A final publication-only rerun checked 221 files under `results` and `data` and changed none. The renderer separately protects 166 untargeted files.
- Stage 21 reports 2,978 main-text words plus 942 legend words, or 3,920 of the 4,000-word limit; the abstract has 285 of 300 words. There are 46 main and 43 supplementary references and five main display items. Existing Highlights are unchanged. The 48%/52% descriptive AIC frequencies are checked against their locked source fractions. Stage 24 validates 106 numeric claims and 16 provenance entries with zero failures; stage 26 passes all 16 formal figure files.
- The final manuscript and supplementary PDFs each have 18 pages; the cover letter has two. All three DOCX packages are valid and editable. After excluding running heads, footers, tables and image text, their normalized alphanumeric body content matches the PDFs exactly: 36,367 characters for the manuscript, 20,262 for the supplement and 4,052 for the cover letter. This is a bounded content-parity check, not a claim that Word and PDF have identical pagination or table extraction order.
- The 21-page illustrated review copy shares 18 text-identical upload pages and appends three native-size figure pages. It and its TeX source are archived outside the upload tree in `../archive/five_issue_verification_20261023/`. The same folder contains build/check logs and refreshed final contact sheets. The main, supplementary and cover-letter page overviews were inspected; the affected appendix table/figure pages were also inspected at readable size. A page break keeps Table S4 together and the shortened S1 caption stays on its figure page without an orphan line. The existing small table fonts were not redesigned; the >=8 pt figure-label audit does not certify table readability. (Superseded later on 2026-10-24: the approved Figure S1 label revision moved the shortened caption's remainder to the following page; see "Figure S1 label and legend revision" below.)
- `docs/five_issue_revision_reconciliation.csv` compares 219 candidate outputs: 170 identical, 16 binary differences, 17 new outputs, 13 row-count differences, one schema difference, one text difference and one numeric difference. The last three are the expanded figure-provenance schema, regenerated provenance hashes and changed typography span counts after row removal, respectively; they are not new fitted estimates. Binary/row-count differences reflect the approved publication exclusions and clean-region assets.
- Cleanup was restricted to the active tree's rebuildable dependencies, caches, compiler auxiliaries and local review-copy files after archival. `make check`, including the existing concordance regression fixtures, and physical `--release-tree` validation pass. The original pre-change snapshot still verifies all 320 inventory entries and contains 321 physical files; earlier release directories and historical baselines remain untouched. The final active checksum inventory is regenerated and verified after documentation.

This revision is not a full raw-input statistical reproduction and does not establish calibration of the date scenarios or elimination of selection/guarantee-time bias. No new Cox fitting, CV, bootstrap, date resampling or quantile calculation was performed. The separate 36-month AUC proposal remains parked. No Git commit, push or publication was performed.

## Second reporting revision and treatment-date flags (2026-10-24)

After four independent reviews and cross-questioning, the author approved all A-class reporting changes and only B1 (descriptive treatment-date flags). The approved title is: *Survival after first-line therapy for ovarian cancer is better described by complete response than by objective response: a TCGA landmark analysis*. The 341-file pre-change tree is preserved in `../archive/second_batch_pre_20261024/`.

### Reporting changes

The equal-complexity M3 versus M2 comparison is described as better fit, not greater parsimony; the comparison with four categories concerns fewer response parameters and little numerical loss of discrimination. Trial eligibility is distinguished from response-stratified randomisation. The conditional post-treatment estimand, expression-linked selection, endogenous recorded treatment termination, and inability to verify actual response-assessment dates remain explicit.

The supplementary methods now state the adjusted formula, response degrees of freedom, Efron ties, covariate-imputation methods, seed, five iterations, observed death/raw follow-up predictors and default predictor-matrix limitations. No convergence traces or logged-event diagnostics were retained, so convergence is not certified. Main-cohort equivalence estimates came from NCR-only refits; HGSOC estimates came from M1 coefficient contrasts. The 2.0-2.7 minimal-detectable-HR range is a pairwise Schoenfeld approximation, not omnibus plateau-test power. The exponential-event power simulation remains distinct.

The original 435-person IPW inclusion model was not refitted to a recorded-stage target. Missing-stage patients were never included, violating positivity for that subgroup. The unchanged weighted estimates are therefore labelled exploratory sensitivity results, not validated correction to the full proxy-eligible population. Weights remain fixed in the robust variance calculation; adjusted complete cases receive no additional completeness-selection correction.

PMID19318476 is excluded because most arrays and response labels overlap the retracted source. Six GSE23554 tumour identifiers also occur in that excluded series, but direct overlap with the retracted subset or independent provenance of their clinical annotation could not be verified. GSE23554 remains in the locked primary pool, with this limitation and the existing leave-one-out result disclosed. Table S1 retains its original pre-landmark numeric panel and adds source-to-landmark counts and original response/death-field crosswalks. Counts are read from existing inventory, primary-cohort audit and 183-day Cox rows; no new model is fitted. `config/external_cohort_reporting.json` holds only reporting metadata and source-row identifiers. Firth per-cohort profile intervals are distinguished from the penalised-information standard errors used in pooling; the prediction interval is normal-based, without HKSJ adjustment.

### Deterministic B1 rebuild

```bash
python3 scripts/31_flag_treatment_dates.py
python3 scripts/21_build_esmo_submission.py
python3 scripts/23_build_submission_latex.py
make audit
```

Stage 31 uses the shipped GDC treatment-record CSV (54,947 records; SHA256 `7394bfe34a75479d61eb8f2bd9edc0f7f1918628a2f56a7d34c77bc8a5c8abc5`) and unchanged Supplementary Data 1. Both inputs are byte-locked in the publication profile. It reproduces all 454 patients' first-line starts/systemic ends/therapy ends before writing Supplementary Data 3 and its flag-definition/count summary. Eleven flags describe uncurated record features; no dates, patients or estimates are changed. The inherited radiation rule uses the -120 to 365-day start window, not the systemic 42-day join rule, and does not adjudicate palliative intent. This audit verifies reproducibility of the operational rule, not clinical correctness of treatment completion or response timing.

Among the 372 landmark patients, 141 had later systemic starts and 11 had such a start before the computed systemic end (7 CR, 2 PR, 1 SD, 1 PD). Bevacizumab alone determined the systemic end in three; radiotherapy extended it in three. Twenty-five had duplicate regimen records and two had partially missing ends. These are descriptive flags, not exclusion rules.

### Verification and boundaries

- `docs/second_batch_revision_verification.csv` records 29 passing package checks. All 212 pre-existing result files are byte-identical except the expanded numeric-claim audit. The five pre-existing processed derivatives and both supplementary datasets are unchanged, as are all 25 checked scientific code/configuration files. All 16 formal figure files retain their baseline bytes. A publication-only rerun checked 224 files under `results` and `data` and changed none.
- The deterministic date output is byte-idempotent. Independent read-only recomputation matched 1,362 date cells, all case-level flags and all 11 summary rows; boundary and altered-byte checks passed. No chart review or statistical rerun was performed. Final targeted checks also confirm the original-case byte lock and corrected reporting locations.
- Stage 24 validates 118 numeric claims (231 source-field checks) and 16 figure-provenance entries with zero failures. Stage 26 passes all 16 formal figure files. Main text plus legends is 3,990 of 4,000 words; the abstract is 297 of 300. The original Highlights and five main display items remain.
- Main PDF: 18 pages; supplement: 20; cover letter: two. Editable main, supplement, cover-letter and STROBE DOCX packages pass ZIP/content checks. Main/supplement/cover non-table body text matches PDF after whitespace, punctuation and Unicode-script normalization (36,945 / 32,607 / 4,108 alphanumeric characters). This does not certify identical Word/PDF pagination or table-extraction order. Final PDF contact sheets, Table S1 and the S1 figure/caption page were visually inspected; existing small table fonts were not redesigned.
- The 21-page illustrated review copy shares 18 text- and pixel-identical upload pages and appends three formal figures. The upload manuscript has no embedded figures. Review PDF/TeX, build logs and inspection renders are retained outside the upload tree in `../archive/second_batch_verification_20261024/` before cleanup.
- `docs/second_batch_revision_reconciliation.csv` compares 222 outputs: 218 identical, one claim-audit row-count change and three new outputs (the verified historical GDC input, case-level date flags and flag summary). There are no new fitted estimates or changed statistical-result rows. Final syntax/configuration/concordance checks and physical release-tree validation are run after active-tree cleanup, followed by complete checksum regeneration.

B2 (new directly paired CV differences), B3 (new tau-squared/study-weight exports), B4 (new residual-disease missingness counts) and all C-class statistical extensions were not approved and were not implemented. No new Cox fitting, CV, bootstrap, treatment-date sampling, nested validation, calibration or Brier/AUC analysis was run. Existing estimates, folds, primary pooling membership and figures are preserved. The separate 36-month AUC proposal remains parked; this is not a full raw-input statistical reproduction. No Git commit, push or publication was performed.

## Third reporting revision: approved A/D/E only (2026-10-24)

Following independent four-party review and cross-questioning, the author approved wording/metric labels (A), existing-result navigation (D), and a descriptive risk-set audit (E). The 348-file pre-change tree remains in `../archive/third_batch_pre_20261024/`. Cover-letter compression (F) and new statistical extensions were not authorised. The approved title, original estimates, shared CV folds, main three-cohort pool and formal figures are unchanged.

### Reporting and descriptive risk-set audit

The abstract identifies the therapy-end assessment-time proxy and the 343 covariate-complete patients used for combined-model CV. PH non-rejection is not presented as proof, residual-stratum findings do not establish a four-category interaction, and separate CR/PR reporting recommendations are limited to prognostic analyses. Table 1's display refers to systemic treatment duration; S1's median recorded diagnosis-to-death/censor interval is not a Kaplan–Meier median. Locked source CSV labels/values are unchanged.

Utility 32 reads hash-locked Data 1, reproduces the existing inclusive 60–365-day origin rule and builds OS/PFI risk sets independently from all 454 labelled cases. It checks existing model counts without executing model code. Data 4 contains 454 rows and 51 fields; the summary has 145 rows. OS is 372/220 deaths and adjusted OS 343/207; NCR-only is 99/80 and adjusted NCR-only 92/75. Thus the existing adjusted NCR-only HR 1.52 uses 92/75, whereas 99/80 are the shared power-design counts; the full-cohort M_PD contrast HR 1.42 uses 343/207. The original exponential-event simulation remains unadjusted and was not rerun.

PFI is 364/283 events, adjusted 337/263. The 90 hierarchical exclusions comprise missing therapy end 56, below-window 9, above-window 5, missing endpoint time 1, event on/before L 9 and censoring on/before L 10; other declared exclusion categories are zero. The actual independent PFI set is a subset of OS with eight OS-only patients, but that nesting is not a construction rule. All 23,154 Data 4 cells and the summary were independently reproduced. These mechanical flags neither verify real assessment dates nor alter dates or eligibility decisions.

### Existing results and portable navigation

Utility 33 builds all 16 existing OS origin/adjustment rows as S5, nine primary external score rows as S6, and the deterministic Data 5 ZIP. S5's printed panels separate estimates, information criteria, existing RMST/tail support, risk-set counts and hierarchical PFI exclusions. The existing 60-month NCR-minus-CR RMST difference is −18.0 months (95% CI −22.1 to −13.9), with CR/NCR numbers at risk 80/1, so tail sparsity is explicit. No horizon was newly estimated.

Data 5 contains the two CSVs, 54 original primary per-cohort score rows, cohort/coverage audits, six complete measured-gene lists, existing RMST/risk tables and full pan-cancer audit, the risk-set count summary, the Data 1–4 dictionary (19/9/18/51 fields), 135-claim source navigation, a provenance summary and a member/input hash manifest. No new tau-squared, study weights, standard errors, numerical decision thresholds or identifier-version claims are supplied. The 15 ZIP members have fixed timestamps/order and use ZIP_STORED. The internally dated 15 October section-6 plan excerpt was byte-compared with the historical source and its SHA256 before being shipped as `config/external_decision_rule_record.json`; rebuilding needs no parent archive. The excerpt is provenance, not public registration, and does not reinstate the superseded retracted-cohort plan.

```bash
python3 -B scripts/32_audit_risk_sets.py --check
python3 -B scripts/33_build_reporting_bundle.py
python3 -B scripts/21_build_esmo_submission.py
python3 -B scripts/23_build_submission_latex.py
make audit
make check
```

The supplementary PDF has a linked, page-numbered contents list and six table bookmarks; Word has a native TOC field marked dirty with update-on-open enabled. Word's fields must be updated in Word; no identical Word/PDF pagination is claimed. Table starts and S3(d)/S5 panels have explicit page breaks; bold panel labels avoid Pandoc's empty ordered-list labels. Tables and figures retain their existing fonts/native sizes. Data descriptions are separated from figure pages. The new `.toc` build auxiliary is covered by Makefile cleanup, Git ignore and the physical-release exclusion rule, so it is not shipped as evidence.

### Verification completed

- Stage 24 passes 135 numeric claims (258 source-field checks) and 16 figure-provenance entries; stage 26 passes all 16 formal files. The conservative word count is 3,986/4,000 and abstract 285/300; five main display items remain.
- `docs/third_batch_revision_verification.csv` records 28 passing package checks. All 213 baseline result files are unchanged except the expanded claim audit; six processed derivatives and Data 1–3 are unchanged, as are all 25 checked scientific-code/configuration files. Independent source review confirms unchanged reference lists, ethics/AI/funding text and exact cover-letter source/assembled Markdown.
- Main/supplement/cover PDFs have 18/28/2 pages. DOCX packages pass ZIP checks; all 17 supplementary Word table-cell streams match generated Markdown. Non-table main/supplement/cover body text matches PDF after normalized extraction (37,031 / 36,365 / 4,108 characters; supplemental title/TOC and landscape tables excluded). All PDF contact sheets and targeted new table/TOC pages were visually inspected; no empty/title-only page remains. This is not a Word-app rendering certification.
- The 21-page illustrated review PDF shares 18 text- and pixel-identical upload pages and appends formal Figures 1–3. Review PDF/TeX, test scripts, logs and inspection renders remain outside the upload tree in `../archive/third_batch_verification_20261024/` before active-tree cleanup.
- Independent reporting acceptance checks all 15 ZIP members, all 16 S5 rows/34 original columns, nine S6 scores, 54 per-cohort rows, 97 dictionary fields, 135 navigation entries, original-plan bytes/SHA and all 23,154 Data 4 cells. An untriggered dictionary-validation inconsistency for Inf/-Inf was corrected: descriptive numbers may retain infinity, while nonnumeric/NaN and invalid integer indicators are rejected. In-memory Inf/-Inf/NaN tests pass; actual frozen inputs contain no nonfinite number. Two guarded post-fix rebuilds from an unrelated working directory, with no parent archive and network/subprocess execution denied inside the builder, reproduce all three outputs byte-for-byte and preserve nanosecond mtimes on the second run.
- `docs/third_batch_revision_reconciliation.csv` compares 227 outputs: 221 identical, one claim-audit row-count change and five new reporting/audit outputs (Data 4, risk-set summary, S5/S6 CSVs and Data 5). No fitted scientific-result row changed. Syntax/runtime-concordance and physical release-tree checks pass. The final 358-entry inventory covers every physical file except itself; all hashes and Data 5 manifest input/member hashes agree. The second/third pre-change archives retain all 340/347 recorded hashes without mismatch or omission.

This revision did not fit Cox/interaction models, regenerate CV, bootstrap, treatment-date draws or quantiles, calculate paired CV differences, or perform calibration/Brier/AUC/nested validation. The separate 36-month AUC proposal remains parked. Current journal/reference-policy and human clinical assessment audits are not claimed. No Git commit, push or publication was performed.

## Figure S1 label and legend revision (2026-10-24)

The author approved items 1–4 of the Figure S1 review: panel labels and headers, panel B/C titles and ticks, replacement of the legend, and synchronization of the main text, supplement and claims. Item 5 (further spacing, reference-line, axis-range and power-caption additions) was not approved and was not implemented.

### Display changes

- **Panel A:** row labels now read `Main (date-complete)`, `IPW (inclusion-weighted)`, `First-line duration 84–210 d`, `Grade 3–4` and `No first-line radiotherapy`; the numeric-column header is `Plateau P`. The source figure still contains all ten rows, including the stochastic date-imputation row, because changing the row count would move every factor level and invalidate the approved crop coordinates. The locked 74–97 pt crop band removes that row from the formal nine-row figure.
- **Panel B:** the y-axis title is `Plateau test P`; the points-only display and the 90–300-day ticks are unchanged.
- **Panel C:** x ticks are exactly 1.3, 1.5, 1.75 and 2.0; y ticks are exactly 100, 200, 500 and 1000 on the log scale; point size is 2.0. The ordered grey ramp, shapes and connecting lines are unchanged.
- **Legend:** the replacement states that rows are unadjusted, defines the plateau test as PR=SD=PD (M3 versus M1, 2 df), defines duration as first-line systemic treatment duration (end minus start), identifies the dashed lines in A (HR=1) and B (P=0.05), and reports seven restriction rows (214–368 patients; 12–30 with PD) and the observed NCR set (99 patients, 30 with PD). The displayed restriction range and NCR counts are read from `regimen_restriction_topology.csv` and `pd_step_power_tcga.csv`; they are not prose literals.
- **Text:** two Results sentences now point to `Supplementary Results, Treatment subsets` and to `Table 2` alongside Figure S1. The supplement uses `first-line systemic treatment duration` and `grade 3–4`, and adds the ORR-rejection sentence supporting the existing main-text bound (P≤8×10⁻⁴). Canonical CSV restriction labels are unchanged.

### Provenance and invariants

Script 18 was rerun; all twelve `results/tables/ov_selection_regimen_power/` CSVs are byte-identical to the pre-change archive. The ten-row source (PDF SHA256 `55c6f58d...`; PNG SHA256 `030591d1...`; 4488 × 4251 px at 600 dpi) is preserved in `../archive/figureS1_labels_20261024/after_source/`, and all four frozen vector regions were regenerated from it. The active source path is intentionally overwritten with the composed nine-row formal figure by utility 30, as for every locked figure. Formal Figure S1 is 189.79 × 179.92 mm (PDF 538 × 510 pt), 600 dpi, embedded Arial, minimum text 8.00 pt, with 65 extracted text spans; the formal PDF/PNG hashes are `a937bd91...` and `244bac13...`. The four region hashes in `config/submission_profile.json` are `9e911726...` (A robust/IPW rows), `df15bd75...` (A restrictions/axis), `72b7500e...` (B) and `394ca0c0...` (C). Three claims and six source fields were added, bringing the audit to 138 claims and 264 fields; Supplementary Data 5 was refreshed with 138 reporting-index rows.

### Verification

- Stage 21: main text 3,042 words, main text plus legends 3,989 of 4,000, abstract 285 of 300; five display items and 46 main references pass.
- Stage 24: 138 numeric claims (264 fields) and 16 figure-provenance entries, zero failures. Stage 26: all 16 formal figure files pass, including Figure S1 at 8.00 pt.
- Stage 23: manuscript 18 pages, supplementary appendix 29 pages, cover letter two, illustrated review copy 21. Every supplementary figure starts on its own page. The approved S1 legend runs four lines onto the following page; page 22 contains only that four-line continuation and S2 begins on page 23, as the author required ("每图独立起页"). No artwork, value or sentence changed. The review copy remains text-identical on pages 1-18 before its three appended figure pages. (The 29-page count and page map refer to that build; later approved table revisions brought the supplement to 31 pages with the S1 figure on page 22, its caption continuation on page 23 and S2 on page 24.)
- `make check` passes, including repository structure, R/Python/JSON/JavaScript syntax and the CV concordance regression checks. The 358-entry checksum inventory was refreshed and verifies clean.

No Cox, CV, bootstrap, imputation or power procedure was rerun. The separate 36-month AUC proposal remains parked. No Git commit, push or publication was performed.

## Supplementary table typography revision (2026-10-25)

The author approved the tested option "S1 + all captions": enlarge the Table S1 body, and raise the caption size for all six supplementary tables. No other table body changed in this first step; the follow-up below then enlarged S2–S6.

### Cause and fitted limits

The supplementary captions inherited the 5.7 pt table block, so a long caption was set at the same size as the data. Table S1 is a landscape A4 page with a 277 × 190 mm text block and three parts (a)(b)(c) of 12/6/4 columns. Because column widths are proportional to `\linewidth`, changing the font redistributes line breaks inside fixed-width columns but never changes the table width; therefore the limiting dimension is vertical.

Controlled single-page tests gave:

- 9.0 pt body / 10.8 pt leading / 5.0 pt column separation with a 9.5 pt caption: Table S1 ends at 182.9 mm, leaving 7.1 mm inside the 190 mm block and remaining on one page.
- 9.5 pt body: ends at 195.6 mm, 5.6 mm past the text block.
- 10.0 pt body: spills onto a second page.

The setting approved in that first step was 9.0 pt for the Table S1 body and 9.5 pt / 11.4 pt leading for all six table captions. Table S1 used 5.0 pt column separation; in that step the other table bodies stayed at 5.7 pt / 6.9 pt with 1.4 pt separation. The supplement remained 29 pages with the same page map (tables 12–20, S1 figure 21, S1 caption continuation 22, S2–S5 figures 23–26); the next-tightest table page, Table S3, ended at 167.4 mm with 22.6 mm slack. The S1 body was later enlarged to 10.0 pt and its panel (a) columns rebalanced, as recorded below.

### Invariants

- Font sizes were applied through `latex_style.supplementary_table_s1_font` and `latex_style.supplementary_table_caption_font` in `config/submission_profile.json`, with structure validation in script 27.
- In that step, the supplement PDF kept the same alphanumeric text. Pages 1–11 and 21–29 were pixel-identical; only the table pages 12–20 changed. No value, sentence, table row or figure was altered.
- The Word files were not rebuilt: their captions remain 11 pt and their wide-table bodies 6 pt.
- Stages 23, 24 and 26 and `make check` pass (138 claims/264 fields, 16 figure-provenance entries, 16/16 formal figures). No Cox, CV, bootstrap, imputation or power procedure was rerun. No Git commit, push or publication was performed.

## Supplementary table body enlargement (2026-10-25)

After reviewing the first result, the author noted that several supplementary tables were still at the old size and asked to enlarge their text and reduce inter-column blank while keeping the fixed page width. Each table was therefore fitted separately inside the same 277 × 190 mm landscape block. Column widths remain proportional to `\linewidth`, so the total width is unchanged and only wrapping and row height respond.

### Tested per-table maxima

All bodies use 1.0 pt column separation (down from 1.4 pt), and all captions remain 9.5 pt / 11.4 pt. Table S1 remained at 9.0 pt / 5.0 pt in this step; it was enlarged and rebalanced separately below.

| Table | Body / leading (pt) | Tightest page bottom | Fitted result |
|---|---|---|---|
| S2 | 7.2 / 8.6 | 186.3 mm | 3.7 mm inside the block; 7.5 pt adds a second page |
| S3 | 8.5 / 10.2 | 180.4 mm | two pages, bottoms 180.4 and 150.2 mm; 9.0 pt adds a third page |
| S4 | 9.0 / 10.8 | 147.8 mm | one page, 42.2 mm slack |
| S5 | 9.0 / 10.8 | 172.8 mm | three pages; the other bottoms are 131.1 and 114.8 mm |
| S6 | 9.0 / 10.8 | 123.1 mm | one page, 66.9 mm slack |

Table S3 needed one structural adjustment to reach 8.5 pt. It originally forced a page break before panel (d), which made the first page caption-heavy and left panel (d)(e) alone on an almost empty second page; that layout admitted only 6.7 pt. Moving the same explicit break to just before panel (c) balances the two pages, keeps the page count at two, and allows 8.5 pt. With the original break restored, 6.8 pt already pushes a wrapped last row 4.7 mm past the block.

The denser multi-panel S2 and S3 cannot reach 9.0 pt without moving text outside the 190 mm block or adding pages; their 7.2 pt and 8.5 pt bodies are nevertheless 26% and 49% larger than before, and S4–S6 are 58% larger.

### Invariants

- The sizes live in `latex_style.supplementary_table_fonts`, keyed S2–S6, in `config/submission_profile.json`; script 23 applies them after each caption and script 27 checks their shape. Table S1 uses `supplementary_table_s1_font` and the panel (a) fractions, covered in the next section.
- Script 23 also owns the S3 reflow: it verifies that exactly one forced break sits before panel (d), removes it, and inserts the break before panel (c). The whole layout change is therefore reproducible from the profile rather than hand-edited.
- Removing the five inserted font/column-separation commands and restoring the original S3 break makes the final `.tex` byte-identical to the pre-change file, which proves that no value, row, sentence, caption or column definition changed. A PDF-level alphanumeric diff is not a valid invariant here: reflow moves cell text across page boundaries and inserts running heads and page numbers at different positions, so the extracted string order changes even when the content does not.
- The supplement remains 29 pages with the same page map (tables 12–20, figures 21–26, data 27, references 28–29). Pages 13–20 changed; page 12 and pages 21–29 are pixel-identical to the previous file.
- The main manuscript PDF, both DOCX files and the cover letter are unchanged; the review copy's 18 shared pages remain text-identical to the upload. DOCX captions remain 11 pt and wide-table bodies 6 pt.
- Stage 24 (138 claims/264 fields, 16 provenance entries), stage 26 (16/16 figures) and `make check` pass. No value, row, sentence or artwork changed, and no statistical procedure was rerun. No Git commit, push or publication was performed.
- The 358-entry checksum inventory was refreshed after this rebuild and all 358 entries verify. Relative to the previous inventory, only the profile, this document, script 23 and the supplementary TeX/PDF differ.

## Table S1 column rebalancing (2026-10-25)

After the previous rebuild the author observed that the seven count columns in Table S1 panel (a) still had large empty gaps between them and asked for a larger body with less blank. The cause was Pandoc's twelve equal `1/12` column widths: each count column held about 20 mm of text width for values of one to three characters, while Platform and the long Median header had to wrap. The correction keeps the 277 mm table width and changes only the internal allocation.

### Allocation and fitted limit

The panel (a) column fractions are stored in `latex_style.supplementary_table_s1_a_fractions` and sum exactly to 1. At 10.0 pt / 12.0 pt leading with 1.0 pt column separation, the inner widths are 20.0 mm (Cohort), 62.0 mm (Platform), 20.0 mm (Retracted source), 8.0 mm (n), 9.0 mm (CR), 11.0 mm (NCR), 9.0 mm each (PR, SD, PD), 14.0 mm (OS events), 37.0 mm (Optimal debulking) and 61.24 mm (Median recorded OS time). The seven count columns therefore shrink from about 20 mm to 8–14 mm, the freed width goes to the text columns, and Platform and the Median header each fit on one line.

At 10.0 pt the page ends at 173.0 mm, leaving 17.0 mm inside the 190 mm block. A 10.5 pt test also remained on one page at 177.3 mm, but 10.0 pt was selected so the body stays close to the 9.5 pt caption and the heading hierarchy remains clear. Panel (b) keeps its six equal columns and panel (c) its four equal text columns: with so few columns, redistributing width would only move the fixed-width blank to another column, so those panels were not changed.

### Invariants

- Font and fractions are applied by script 23 after the S1 caption; script 27 checks that there are 12 positive fractions summing to 1. Table S1 uses 10.0 pt / 12.0 pt / 1.0 pt; all six captions remain 9.5 pt / 11.4 pt.
- The supplement remains 29 pages with unchanged pagination. Only page 12 changed; pages 1–11 and 13–29 are pixel-identical to the previous file. No value, row, sentence, caption or figure changed.
- Reverting the S1 font command and the twelve fractions makes the final `.tex` byte-identical to the pre-change file, proving that the edit is purely a width and size allocation.
- The main manuscript PDF, both DOCX files and the cover letter are unchanged; the review copy's 18 shared pages remain text-identical to the upload. DOCX captions remain 11 pt and wide-table bodies 6 pt.
- Stage 24 (138 claims/264 fields, 16 provenance entries), stage 26 (16/16 figures) and `make check` pass. No statistical procedure was rerun. No Git commit, push or publication was performed.

That landscape allocation was superseded by the portrait layout in the next section; it remains reproducible through the orientation switch.

## Table S1 portrait layout (2026-10-25)

The author then asked whether Table S1 could sit on a portrait page instead of the rotated table block. It can. S1 keeps the natural reading orientation; S2–S6 remain landscape. Only the orientation and panel (a) width allocation change: the 10.0 pt body, 12.0 pt leading, 1.0 pt column separation and 9.5 / 11.4 pt caption are unchanged.

### Geometry and allocation

The portrait page uses the same 190 mm full-width block as the figure pages: 10 mm side margins with the normal 22 mm top and bottom text margins. The running head therefore sits at 9.6 mm and the folio at 282.6 mm, level with the surrounding prose pages, rather than at the 4.4 mm and 289 mm positions produced by the all-10 mm landscape geometry.

Because the available width falls from 277 mm to 190 mm, panel (a) needs a different allocation. The configured fractions give inner widths of 18.5 mm (Cohort), 31.0 mm (Platform), 17.5 mm (Retracted source), 7.0 mm (n), 8.0 mm (CR), 9.5 mm (NCR), 8.0 mm each (PR, SD, PD), 12.0 mm (OS events), 25.0 mm (Optimal debulking) and 29.74 mm (Median recorded OS time). The page ends at 216.1 mm, 58.9 mm inside the 275 mm text-block bottom, and remains on one page. Panel (b) keeps six equal columns and panel (c) four; panel (c)'s long mapping and death-definition strings now wrap onto two or three lines, which the portrait height accommodates.

A 10.5 pt test also remained within the page but split `U133 Plus 2 (RMA)` over two lines. The 10.0 pt body was retained because it keeps that cell on one line and stays closer to the 9.5 pt caption.

### Invariants

- The orientation lives in `latex_style.supplementary_table_s1_orientation` and the twelve portrait fractions in `latex_style.supplementary_table_s1_a_fractions`; script 27 validates both. Script 23 opens a portrait block for S1 and starts the landscape group only at Table S2.
- Setting the orientation back to `landscape` and restoring the twelve landscape fractions regenerates the pre-change `.tex` byte for byte, so the edit is purely an orientation and width-allocation change.
- The supplement remains 29 pages with the same page map (tables 12–20, figures 21–26, data 27, references 28–29). S1 remains one page and S2 starts page 13 in landscape. Only page 12 changed; pages 1–11 and 13–29 are pixel-identical to the previous file, and page 12 has the same 285-word multiset before and after.
- The main manuscript PDF, both DOCX files and the cover letter are unchanged; the review copy's 18 shared pages remain text-identical to the upload. DOCX captions remain 11 pt and wide-table bodies 6 pt.
- Stage 24 (138 claims/264 fields, 16 provenance entries), stage 26 (16/16 figures) and `make check` pass. No value, row, sentence or artwork changed, and no statistical procedure was rerun. No Git commit, push or publication was performed.

## Table S2 panel (a) column rebalancing (2026-10-25)

After the Table S1 work the author observed the same problem in Table S2 panel (a): wide blank gaps between its columns. Pandoc had given the seven panel (a) columns equal `1/7` widths, so Stage and Definition each held only about 38 mm and wrapped, while the five count columns also held about 38 mm for values of three characters. The correction keeps the 277 mm landscape table width and changes only the internal allocation and the panel (a) body size.

### Allocation and fitted limit

The panel (a) fractions are stored in `latex_style.supplementary_table_s2_a_fractions` and sum exactly to 1. The seven-column longtable subtracts 12 `\tabcolsep` contributions, so the fractions apply to 277 − 12 × 0.3528 = 272.766 mm. At 8.5 pt / 10.2 pt leading with 1.0 pt column separation, the inner widths are 58.8 mm (Stage), 148.2 mm (Definition) and 13.2 mm for each of Total, CR, PR, SD and PD. The five count columns therefore shrink from about 38 mm to 13.2 mm, and both text columns now fit their longest strings on one line.

At 8.5 pt all three data rows are single-line. The S2 page, which at this stage still carried the 7.2 pt panel (b), ended at 180.8 mm, 19.2 mm inside the 200 mm lower edge of the landscape text block (the 210 mm page has 10 mm margins). A 9.0 pt test wrapped `Operational HGSOC therapy-end landmark` onto a second line, so 8.5 pt is the largest size that keeps the panel single-line at this allocation. Panel (b) was left at 7.2 pt / 8.6 pt / 1.0 pt at this stage because its fourteen equal columns were the binding constraint; the next section rebalances it. Script 23 therefore resets the S2 body font before panel (b).

### Invariants

- The panel (a) font and fractions live in `latex_style.supplementary_table_s2_a_font` and `latex_style.supplementary_table_s2_a_fractions`; script 27 validates the font shape and that there are 7 positive fractions summing to 1. Script 23 applies the font after the S2 caption, replaces the seven panel (a) equal fractions, and restores the S2 base font before panel (b).
- Reverting the panel (a) font command, the seven fractions and the reset command makes the final `.tex` byte-identical to the pre-change file, which proves that no value, row, sentence, caption or column definition changed.
- The supplement remains 29 pages with the same page map (tables 12–20, figures 21–26, data 27, references 28–29). Only page 13 changed; pages 1–12 and 14–29 are pixel-identical to the previous file, and page 13 has the same 362-word multiset before and after.
- Panel (b), S1 on page 12, the main manuscript PDF, both DOCX files, the cover letter and the review copy are unchanged; the review copy's 18 shared pages remain text-identical to the upload. DOCX captions remain 11 pt and wide-table bodies 6 pt.
- Stage 24 (138 claims/264 fields, 16 provenance entries), stage 26 (16/16 figures) and `make check` pass. No value, row, sentence or artwork changed, and no statistical procedure was rerun. No Git commit, push or publication was performed.
- The 358-entry checksum inventory was refreshed after this rebuild and all 358 entries verify. Relative to the previous inventory, only the profile, this document, script 23, script 27 and the supplementary TeX/PDF differ.

This supersedes the S2 body entry in the earlier per-table maximum table: panel (a) became 8.5 pt at this stage, while panel (b) was still 7.2 pt and is rebalanced in the next section.

## Table S2 panel (b) column rebalancing (2026-10-25)

The author then asked for the same treatment in panel (b): arrange the fourteen columns by content and adjust the body size if needed. Pandoc had given every column `1/14` of the line, about 19.1 mm, so the repeated Setting labels wrapped onto four lines while the hazard ratios and test statistics were squeezed. The correction keeps the 277 mm landscape width and changes only the internal allocation and the panel (b) body size.

### Allocation and fitted limit

The fourteen fractions are stored in `latex_style.supplementary_table_s2_b_fractions` and sum to 1. The longtable subtracts 26 `\tabcolsep` contributions, so the fractions apply to 277 − 26 × 0.3528 = 267.827 mm. At 8.5 pt / 10.2 pt leading with 1.0 pt column separation the inner widths are Setting 44.0 mm, Adjustment 16.0 mm, n 7.0 mm, Events 10.0 mm, each of the five hazard-ratio columns 25.0 mm, and the five test/model columns 13.5 mm (Plateau P), 13.0 mm (ORR P), 14.5 mm (PD-step P), 12.5 mm (Best AIC) and 12.33 mm (Best BIC). Every header and every numeric cell now sits on one line; only `HGSOC diagnosis, therapy-end patients` and `age+stage+residual` wrap, each onto two lines. The S2 bottom rule moves from 180.75 mm to 144.73 mm, leaving 55.3 mm inside the 200 mm lower edge, and S2 stays on page 13.

A 9.0 pt trial was rejected. The narrower test/model columns wrapped the `Best BIC` header onto a stray upper line, the longest Setting labels wrapped to two lines, and `Main TCGA-OV therapy-end` ran into the following cell. Panel (b) therefore uses the same 8.5 pt / 10.2 pt body as panel (a). The 7.2 pt S2 base is restored after panel (b), on the new page, so the following Table S3 heading keeps the size it had before this change and no later page moves.

### Invariants

- The panel (b) font and fractions live in `latex_style.supplementary_table_s2_b_font` and `latex_style.supplementary_table_s2_b_fractions`; script 27 validates the font shape and that there are 14 positive fractions summing to 1. Script 23 applies the font before panel (b), replaces the fourteen equal fractions, and restores the S2 base font after the table.
- Reverting the panel (b) font command, the fourteen fractions and the post-panel reset makes the final `.tex` byte-identical to the pre-change file (`fe78797a…`), which proves that no value, row, sentence, caption or column definition changed.
- The supplement remains 29 pages with the same page map (tables 12–20, figures 21–26, data 27, references 28–29). Only page 13 changed; pages 1–12 and 14–29 are pixel-identical to the previous file, and page 13 has the same 362-word multiset before and after. Panel (a) occupies the same pixels in the top 60 mm, and S1 on page 12 is unchanged.
- The main manuscript PDF, both DOCX files and the cover letter are unchanged; the review copy's 18 shared pages remain text-identical to the upload. DOCX captions remain 11 pt and wide-table bodies 6 pt.
- Stage 24 (138 claims/264 fields, 16 provenance entries), stage 26 (16/16 figures) and `make check` pass. No value, row, sentence or artwork changed, and no statistical procedure was rerun. No Git commit, push or publication was performed.
- The 358-entry checksum inventory was refreshed after this rebuild and all 358 entries verify. Relative to the previous inventory, only the profile, this document, script 23, script 27 and the supplementary TeX/PDF differ.

This supersedes the panel (b) 7.2 pt statement in the panel (a) section and the per-table maximum entry above; both S2 panels are now 8.5 pt.

## Figure S4 facet annotation rearrangement (2026-10-25)

The author observed that the per-facet `n=…, … deaths` labels in Figure S4 were not at a consistent height and that some label text crossed the vertical confidence intervals. The original code placed each label 35% above that facet's tallest PR/SD upper limit at x=1, but the PD intervals reach up to 23.4 and extended through the text; because the anchor depended on PR/SD values, the ten labels also sat at different heights.

### Layout change and measured geometry

Every facet is now labelled in one reserved band above the 30 gridline. The annotation data contain one row per panel and only reuse the existing counts; the label string is unchanged. All facets share a fixed log scale of 0.12–50 with breaks at 0.3, 1, 3, 10 and 30, and the label is centred on the SD tick (x=2) at y=45 with `hjust=0.5`, `vjust=1`, 8 pt Arial.

In the formal PDF (538 × 368 pt), all ten labels have their top edge 8.35 pt below the panel top: the top row occupies y=26.13–35.06 pt in panels starting at 17.77 pt, and the bottom row y=191.04–199.97 pt in panels starting at 182.69 pt. Horizontal margins to the open panel edges are 13.92–16.15 pt and symmetric. The lowest label edge is 2.42 pt above the 30 gridline at y=37.48 pt, and the tallest whisker starts at y=49.05 pt, 13.99 pt below the labels, so no text intersects a PR, SD or PD interval.

The figure contains the same 44 text spans with the same strings, the same 8.00 pt Arial font and the same 201 drawing operations before and after. The R diff is confined to the annotation data, the fixed y scale and the text geometry; all Figure S4 source CSVs, including `topology_models_by_set.csv` (`11588a57…`), are byte-identical. The vertical remapping of points and gridlines is a display consequence of the fixed 0.12–50 scale, not a change in any hazard ratio, confidence limit, count or label.

### Invariants

- The supplement remains 29 pages with the same page map (tables 12–20, figures 21–26, data 27, references 28–29). Only page 25 changed; pages 1–24 and 26–29 are pixel-identical to the previous PDF, and page 25's 79-word text multiset is unchanged.
- The supplement `.tex` is byte-identical (`c1ac5bf2…`), so the change is entirely inside the embedded Figure S4 artwork. The formal analysis-native and supplementary copies have identical bytes: PDF `4b5eb437…` and PNG `45188deb…`.
- The main manuscript PDF, manuscript/supplement/cover DOCX, cover PDF, illustrated review copy and STROBE checklist are unchanged. Stage 21 necessarily regenerates the four DOCX files; each was restored to its exact pre-change bytes (`00c2898f…`, `40aa76bc…`, cover DOCX as before, STROBE `711e3e3b…`), so no Word file was rebuilt in the delivered result. DOCX captions remain 11 pt and wide-table bodies 6 pt.
- Utility 33 regenerated Data 5 because its input manifest records both the Figure S4 script and the submission profile. The 14 payload members are copied from unchanged frozen files, S5 and S6 are byte-identical, and only `input_manifest.json` carries the new script (`e258744f…`) and profile (`b067a09b…`) hashes; the resulting bundle is deterministic at `dbd5a78a…`.
- Stage 24 (138 claims/264 fields, 16 provenance entries), stage 26 (16/16 figures) and `make check` pass. No Cox, CV, bootstrap, imputation or power procedure was rerun. No Git commit, push or publication was performed.
- The 358-entry checksum inventory was refreshed after this rebuild and all 358 entries verify. Relative to the previous inventory, only script 16, the four Figure S4 vector/raster files, `figure_provenance_audit.csv`, the supplementary PDF, Data 5 and this document differ; the STROBE DOCX was returned to its recorded hash.

## Table S6 column rebalancing and two-line headers (2026-10-25)

The author asked for content-driven column widths in Table S6, then for a larger body with less inter-column whitespace, and finally for the crowded header row to be relieved by setting long headers on two lines and using the freed width to tighten the remaining gaps. Pandoc had given its ten columns equal `1/10` widths, 27.065 mm each, so the Score column wrapped in six of the nine data rows, the Adjustment cell wrapped in the last row, and three headers (`Negative direction, k`, `REML difference (95% CI)` and `95% prediction interval`) each occupied two lines. The final correction keeps the 277 mm landscape width, the caption and all text and values, and changes only the internal allocation, the body size and four header line breaks in the generated LaTeX.

### Allocation and fitted limit

The ten fractions are stored in `latex_style.supplementary_table_s6_fractions` and sum exactly to 1. The longtable subtracts 18 `\tabcolsep` contributions, so the fractions apply to 277 − 18 × 0.3528 = 270.65 mm. At 12.75 pt / 15.3 pt leading with 1.0 pt column separation, the inner widths are Score 54.93 mm (longest cell `licensing given proliferation`), Adjustment 40.49 mm (`general proliferation`), k / n 14.60 mm, Negative direction 22.56 mm, REML difference 36.76 mm, REML P 17.58 mm, HKSJ 95% CI 26.06 mm, HKSJ P 16.58 mm, I² 10.57 mm and prediction interval 30.53 mm. Each width is the widest measured header line or body cell in that column plus 0.89–0.94 mm, so no column carries more than 0.94 mm of internal slack; the one-line 10.5 pt layout carried 1.12–1.17 mm.

Four headers are set on two lines: `Negative` / `direction, k`, `REML difference` / `(95% CI)`, `HKSJ` / `95% CI`, and `95% prediction` / `interval`. The short headers `REML P`, `HKSJ P` and `I², %` stay on one line and, because header cells are bottom-aligned, sit on the lower header line. The breaks are inserted into the generated `.tex` only, after the fractions are applied; the Markdown pipe table still holds one-line headers so the DOCX build remains unchanged.

At 12.75 pt all nine body rows stay on one line and no header exceeds two lines. Text-to-text separation between adjacent columns is 1.59–1.64 mm, down from 1.82–1.85 mm at 10.5 pt, because each gap is the column's slack plus the two 0.3528 mm `\tabcolsep` paddings rather than a fixed blank. The table's bottom rule is at 118.31 mm below the page's top edge, leaving 81.69 mm to the 200 mm text-block lower edge, and S6 remains on one page. A 12.5 pt trial also fitted; 12.75 pt was selected as the largest clean size among the tested 12.5, 12.75, 12.9 and 13.0 pt layouts. The 12.9 and 13.0 pt trials made adjacent text spans merge (for example `HKSJ P I` and `0.03 ... 0.87`) and were rejected. The caption remains 9.5 pt / 11.4 pt.

### Invariants

- The S6 font and fractions live in `latex_style.supplementary_table_fonts.S6` and `latex_style.supplementary_table_s6_fractions`; script 27 validates the font shape and that there are 10 positive fractions summing to 1. Script 23 applies the font after the S6 caption, replaces the ten equal fractions and inserts the four header breaks, and leaves every other table untouched.
- Reverting the S6 font command, its ten fractions and the four header breaks to the original 9.0/10.8, ten `\real{0.1000}` entries and one-line headers makes the final `.tex` byte-identical to the pre-change file (`c1ac5bf2…`), proving that no value, row, sentence, caption or column definition changed. Reverting only to the previous 10.5 pt layout reproduces that round's TeX (`5c1cf6d8…`). The current TeX is `fa9b8baa…`; its diff from the 10.5 file is exactly the S6 font size, the ten fractions and the four `\newline` insertions.
- The supplement remains 29 pages with the same page map (tables 12–20, figures 21–26, data 27, references 28–29). Only page 20 changed; pages 1–19 and 21–29 are pixel-identical to the previous PDF, and page 20 has the same 328-word multiset and the same 1,744-character non-whitespace multiset before and after.
- The main manuscript PDF, all four DOCX files (manuscript, supplement, cover letter and STROBE checklist), the cover-letter PDF and the illustrated review copy are unchanged; the review copy's 18 shared pages remain text-identical to the upload. DOCX captions remain 11 pt and wide-table bodies 6 pt.
- Utility 33 regenerated Data 5 because its input manifest records the submission profile. The 14 payload members are copied from unchanged frozen files, S5 and S6 are byte-identical, and only `input_manifest.json` changes: the profile entry becomes `858c564e…` at 14,513 bytes, replacing `e93db11a…` at 14,512 bytes, while the manifest remains 15,390 bytes. The bundle is deterministic at `93d94238…`, replacing `81ecc31e…`.
- Stage 24 (138 claims/264 fields, 16 provenance entries), stage 26 (16/16 figures) and `make check` pass. No value, row, sentence or artwork changed, and no statistical procedure was rerun. No Git commit, push or publication was performed.
- The 358-entry checksum inventory was refreshed after this rebuild and all 358 entries verify. Relative to the 10.5 pt inventory, only the profile, script 23, the supplementary TeX/PDF, Data 5 and this document differ.

## Table S5 per-panel rebalancing and two-line headers (2026-10-26)

The author asked for the treatment already applied to Table S6 to be extended to every panel of Table S5: content-driven column widths, less inter-column whitespace, the largest practical body size and two-line headers where the header row is crowded. Pandoc had given panels (a)-(c) eleven, six and seven equal columns and left panels (d)-(e) as natural-width l-columns, so the equal-width panels carried large blank gaps while their text columns wrapped. The caption, all values, the panel order and the page map are unchanged; only the generated LaTeX carries five font commands, five column definitions (including four literal table widths) and six header line breaks.

### Allocation and fitted limit

Panel (a) keeps the full 277 mm block. Its eleven fractions apply to 277 − 20 × 0.3528 = 269.94 mm and assign Origin 29.92 mm, Adjustment 33.20 mm, n / deaths 17.07 mm, CR/PR/SD/PD 24.61 mm, each of PR vs CR, SD vs CR, PD vs CR and NCR vs CR 27.89 mm, Plateau P 16.88 mm, ORR P 19.02 mm and PD-step P 17.69 mm. At 10.4 pt / 12.48 pt leading all sixteen body rows stay on one line and the tightest column keeps 1.01 mm of slack, so adjacent text is at least 1.72 mm apart. The table ends at 148.1 mm.

Panels (b) and (c) share page 18, so height rather than width binds. Their fractions apply to dedicated 227.1 mm and 222.1 mm centred blocks instead of the full line width. The resulting inner widths are 43.59 mm (Origin), 48.22 mm (Adjustment), 42.99 mm (each of ΔAIC and ΔBIC), 22.76 mm (Best AIC) and 23.03 mm (Best BIC) in (b), and 21.87 mm (Horizon), 27.56 mm (RMST CR), 31.31 mm (RMST NCR), 54.58 mm (NCR − CR, 95% CI), 28.09 mm (P), 25.34 mm (CR at risk) and 29.10 mm (NCR at risk) in (c). At 14.75 pt / 17.7 pt leading the tightest measured text gaps are 2.95 mm in (b) and 2.82 mm in (c). Panel (b) sets ΔAIC and ΔBIC on two lines above M1/M2/M3/M_PD; panel (c) splits all four headers that end in "months" after the comma. The breaks are inserted into the generated `.tex` only, so the Markdown pipe table and the DOCX build keep one-line headers. Panel (b) ends at 147.4 mm and panel (c) at 196.3 mm, 3.7 mm above the 200 mm text-block lower edge.

Panels (d) and (e) convert their six natural l-columns to p-columns of 179.1 mm and 137.4 mm at the same 14.75 pt. Their fractions give (d) Existing risk set 38.66 mm, Endpoint 23.04 mm, Adjustment 48.23 mm, n 11.18 mm, Events 18.41 mm and CR/PR/SD/PD 36.05 mm, and (e) Ordered PFI exclusion reason 86.39 mm with the five count columns at 8.29-10.01 mm. All six and nine rows stay on one line, the minimum text gaps are 3.22 mm and 3.18 mm, and the tables end at 72.7 mm and 166.0 mm. Both tables remain centred.

A 16.0 pt trial with the same two-line headers pushed panel (c) onto a fourth page; 15.0 pt ended at 199.8 mm, 0.2 mm from the block edge; 14.0 pt left the panels visibly underfilled, and the one-line-header 14.0 pt trial merged the ΔAIC/ΔBIC header text at 1.7 mm gaps. 14.75 pt was selected. The caption remains 9.5 pt / 11.4 pt, and the S5 base font is restored before the S6 page break so the following page is untouched.

### Invariants

- The new profile keys are `latex_style.supplementary_table_s5_fonts` (panels a-e), `latex_style.supplementary_table_s5_a_fractions` through `_e_fractions`, and `latex_style.supplementary_table_s5_b_width_mm` through `_e_width_mm`. Script 27 validates the five font objects, the fraction counts (11/6/7/6/6, positive and summing to 1) and the four widths (positive, at most the 277 mm landscape block). Script 23 applies the per-panel fonts, replaces the equal Pandoc fractions, converts the two l-specs, substitutes the literal widths and inserts the six header breaks.
- Masking the five font commands, five column definitions and six `\newline` insertions from both generated files makes the S5 blocks identical; the text before and after the block is byte-identical. The pre-change PDF `051de8cd…` / TeX `fa9b8baa…` become the current `81f7a9ef…` (PDF) / `47e08acd…` (TeX). No value, row, caption or sentence changed.
- The supplement remains 29 pages with the same page map. Only pages 17-19 changed; pages 1-16 and 20-29 are pixel-identical to the previous PDF. Panel order is 17 = (a), 18 = (b) then (c), 19 = (d) then (e).
- The main manuscript PDF/TeX, cover-letter PDF/TeX, illustrated review copy, all four DOCX files and the highlight file are unchanged. DOCX captions remain 11 pt and wide-table bodies 6 pt.
- Utility 33 regenerated Data 5 because its input manifest records the submission profile. All 14 payload members are byte-identical and only `input_manifest.json` changes: the profile entry becomes `f5be2b28…` at 15,693 bytes, replacing `858c564e…` at 14,513 bytes, while the manifest remains 15,390 bytes and the bundle becomes `dec6ebd3…`, replacing `93d94238…`.
- Stage 24 (138 claims/264 fields, 16 provenance entries), stage 26 (16/16 figures) and `make check` pass. No statistical procedure was rerun and no Git commit, push or publication was performed.
- The 358-entry checksum inventory was refreshed after this rebuild and all 358 entries verify. Relative to the pre-S5 inventory, only the profile, scripts 23 and 27, the supplementary TeX/PDF, Data 5 and this document differ.

## Table S4 column rebalancing and two-line headers (2026-10-26)

The author asked for the treatment already applied to Tables S6 and S5 to be extended to Table S4: content-driven column widths, less inter-column whitespace, the largest practical body size and two-line headers where the header row is crowded. Pandoc had given S4 fifteen equal 17.8 mm columns, so six long headers wrapped to two or three lines while the mostly numeric columns were padded with blank space. The caption, all 22 rows, the column order and the single-page map are unchanged; only the generated LaTeX carries one S4 body-font command, one S5 base-font reset, fifteen column fractions, fifteen literal width substitutions and six header line breaks.

### Allocation and fitted limit

The fifteen fractions apply to a dedicated 229.1 mm centred block; 229.1 − 28 × 0.3528 = 219.2 mm is divided between the p-columns. The inner widths are Cancer 15.91 mm, n 8.67 mm, CR 8.67 mm, PR 7.37 mm, SD 8.67 mm, PD 8.67 mm, OS events 14.62 mm, % first-line systemic 22.63 mm, % non-surgical first-line 31.70 mm, % therapy end known 30.93 mm, % R0 in CR 12.54 mm, % R0 in NCR 15.91 mm, E1 8.50 mm, E2 8.50 mm and Eligible 15.91 mm. The table occupies 228.9 mm between its rules and is centred on the landscape page.

At 13.25 pt / 15.9 pt leading all 22 body rows stay on one line. Six headers are set on two lines ("OS" / "events"; "% first-line" / "systemic"; "% non-surgical" / "first-line"; "% therapy end" / "known"; "% R0" / "in CR"; "% R0" / "in NCR"), while the other nine headers stay on one line and are bottom-aligned with the second header line. The breaks are inserted into the generated `.tex` only, so the Markdown pipe table and the DOCX build keep one-line headers. The tightest measured text gap between adjacent columns is 1.60 mm. The table ends at 194.7 mm, 5.3 mm above the 200 mm text-block lower edge.

A 13.5 pt trial ended at 198.3 mm in the isolated harness (about 197.6 mm on the page) and left under 2.5 mm of headroom, so it was rejected; 13.0 pt ended at 192.5 mm in the same harness and left more than 7 mm. 13.25 pt is the largest setting that stays clear of the block edge. The caption remains 9.5 pt / 11.4 pt, and the S5 base font is restored before the S5 page break so page 17 is untouched.

### Invariants

- The new profile keys are `latex_style.supplementary_table_s4_fractions` (15 positive values summing to 1) and `latex_style.supplementary_table_s4_width_mm` (229.1 mm, within the 277 mm landscape block); `latex_style.supplementary_table_fonts.S4` becomes 13.25 pt / 15.9 pt. Script 27 validates the fractions and the width; script 23 replaces the fifteen equal `\real{0.0667}` fractions, substitutes the literal width in all fifteen p-specs, inserts the six header breaks and restores the S5 base font before the page break.
- Masking the two font commands, the fifteen column fractions, the literal width and the six `\newline` insertions from both generated files makes the S4 blocks identical; the text before and after the block is byte-identical. The pre-change PDF `81f7a9ef…` / TeX `47e08acd…` become the current `1565429a…` (PDF) / `2b47713f…` (TeX). No value, row, caption or sentence changed.
- The supplement remains 29 pages with the same page map. Only page 16 changed; pages 1-15 and 17-29 are pixel-identical to the previous PDF. Table S4 remains a single landscape page between S3 (page 15) and S5 (pages 17-19).
- The main manuscript PDF/TeX, cover-letter PDF/TeX, illustrated review copy, all four DOCX files and the highlight file are unchanged. DOCX captions remain 11 pt and wide-table bodies 6 pt.
- Utility 33 regenerated Data 5 because its input manifest records the submission profile. All 14 payload members are byte-identical and only `input_manifest.json` changes: the profile entry becomes `9926b4c8…` at 15,918 bytes, replacing `f5be2b28…` at 15,693 bytes, while the manifest remains 15,390 bytes and the bundle becomes `3fe60929…`, replacing `dec6ebd3…`.
- Stage 24 (138 claims/264 fields, 16 provenance entries), stage 26 (16/16 figures) and `make check` pass. No statistical procedure was rerun and no Git commit, push or publication was performed.
- The 358-entry checksum inventory was refreshed after this rebuild and all 358 entries verify. Relative to the pre-S4 inventory, only the profile, scripts 23 and 27, the supplementary TeX/PDF, Data 5 and this document differ.

## Table S4 enlarged heading and caption (2026-10-26, superseded)

The author asked to enlarge the "Table S4" subsection heading and the table caption. The printed heading becomes 14.0 pt (from the 12.0 pt subsection default) and the caption 12.0 pt / 14.4 pt (from 9.5 pt / 11.4 pt). Only S4 is affected: the other five captions stay at 9.5 pt and their headings are untouched. The caption still carries exactly the same words; at 12 pt it occupies four lines instead of three, begins at 18.6 mm and ends at 39.8 mm, and the table's top rule moves from 34.5 to 43.7 mm. The 14.0 pt heading remains below the 14.35 pt "Supplementary Tables" section heading; a 15.0 pt trial inverted that hierarchy and was rejected.

This S4-only treatment was superseded later the same day by the shared body-text rule described in the next section: the final PDF carries 11.0 pt headings and captions on all six tables. The body-leading change recorded below still applies.

To keep the enlarged heading and caption on the same page as all 22 rows, the S4 body leading is tightened from 15.9 to 15.1 pt; the body size remains 13.25 pt and every row still fits on one line. The table's bottom rule is now at 196.1 mm, 3.9 mm above the 200 mm text-block lower edge, and the tightest text gap remains 1.60 mm. The heading is written with an optional short title so the contents entry and PDF bookmark stay at the normal subsection size rather than inheriting the 14 pt display size.

### Invariants

- The new profile keys are `latex_style.supplementary_table_s4_caption_font` (12.0 pt / 14.4 pt) and `latex_style.supplementary_table_s4_heading_font` (14.0 pt / 16.8 pt); `latex_style.supplementary_table_fonts.S4` keeps its 13.25 pt size and changes only its leading to 15.1 pt. Script 27 validates the two new objects and the existing S4 fractions and width. Script 23 replaces the S4 caption wrapper and the `\subsection{Table S4}` command in the generated LaTeX only.
- Masking the S4 heading line and the two S4 font wrappers from both generated files makes the S4 blocks identical; the text before and after the block is byte-identical, and the table's 266 extracted text lines and 274 tokens are unchanged line by line. The caption's 61-token word sequence is also unchanged. No value, row, caption word or sentence changed. The pre-change PDF `1565429a…` / TeX `2b47713f…` become the current `677005b5…` (PDF) / `4555ffcb…` (TeX).
- The supplement remains 29 pages with the same page map. Only page 16 changed; pages 1-15 and 17-29 are pixel-identical to the previous PDF. The contents page and its "Table S4" entry are also pixel-identical, and Table S4 remains a single landscape page between S3 (page 15) and S5 (pages 17-19).
- The main manuscript PDF/TeX, cover-letter PDF/TeX, illustrated review copy, all four DOCX files and the highlight file are unchanged. DOCX captions remain 11 pt and wide-table bodies 6 pt.
- Utility 33 regenerated Data 5 because its input manifest records the submission profile. All 14 payload members are byte-identical and only `input_manifest.json` changes: the profile entry becomes `486e984a…` at 16,082 bytes, replacing `9926b4c8…` at 15,918 bytes, while the manifest remains 15,390 bytes and the bundle becomes `603b7746…`, replacing `3fe60929…`.
- Stage 24 (138 claims/264 fields, 16 provenance entries), stage 26 (16/16 figures) and `make check` pass. No statistical procedure was rerun and no Git commit, push or publication was performed.
- The 358-entry checksum inventory was refreshed after this rebuild and all 358 entries verify. Relative to the pre-caption inventory, only the profile, scripts 23 and 27, the supplementary TeX/PDF, Data 5 and this document differ.

## Supplementary table headings and captions matched to body text (2026-10-26)

The author asked that every supplementary table heading and caption match the 11.0 pt body text rather than the table body, whose sizes range from 7.2 to 14.75 pt. All six subsection headings and all six captions are now set at 11.0 pt / 13.2 pt. The printed headings carry optional short titles, so the contents entries and PDF bookmarks remain at the normal subsection size and the 14.35 pt "Supplementary Tables" section heading stays the largest element on the table pages. The S4-specific 14.0 pt heading and 12.0 pt caption keys were removed; the S4 body remains 13.25 pt / 15.1 pt and its optional short title is now shared with the other five tables. Other subsection headings in the supplement are unchanged at the 12.0 pt default.

### Page fit

The caption text and all table rows are unchanged; only the heading and caption wrappers differ. At 11 pt the captions occupy 8, 2, 7, 4, 8 and 7 lines for S1-S6, and every table remains on its original page.

| Table | Page | Caption lines | Top rule (mm) | Bottom rule (mm) | Headroom to block (mm) |
|-------|------|---------------|---------------|------------------|------------------------|
| S1 | 12 (portrait) | 8 | 88.53 | 227.48 | 47.5 to 275 |
| S2 | 13 | 2 | 36.95 | 146.15 | 53.9 |
| S3 | 14 | 7 | 63.34 | 191.31 | 8.7 |
| S4 | 16 | 4 | 42.16 | 194.68 | 5.3 |
| S5 | 17 | 8 | 70.06 | 158.27 | 41.7 |
| S6 | 20 | 7 | 57.88 | 127.87 | 72.1 |

The tightest landscape page is S4 at 194.68 mm, 5.32 mm above the 200 mm text-block lower edge; S3 remains the second-tightest at 191.31 mm. The S4 table no longer needs the enlarged heading and caption that motivated the 15.1 pt body leading, but that leading is retained because it remains within the fitted limit and changing it would alter the approved S4 body layout without a request. S3 panel (c) on page 15 and S5 panels (b)-(e) on pages 18-19 are unaffected.

### Invariants

- The profile keeps `latex_style.supplementary_table_caption_font` at 11.0 pt / 13.2 pt and adds `latex_style.supplementary_table_heading_font` at 11.0 pt / 13.2 pt; the two `supplementary_table_s4_caption_font` and `supplementary_table_s4_heading_font` keys are removed. Script 27 validates both shared objects, the S4 fractions and width. Script 23 wraps all six captions and all six `\subsection{Table S1}`-`S6` commands in the generated LaTeX only, after the S1/S2 portrait-to-landscape geometry insertion so the plain S2 marker is still available, and leaves the Markdown pipe tables and DOCX wording untouched.
- The generated TeX differs from the previous file in exactly 12 lines: six heading commands become optional-short-title headings and six caption wrappers change from 9.5 pt (S4 from 12.0 pt) to 11.0 pt. Masking those 12 lines makes the two TeX files identical, so no value, row, caption word or sentence changed. The pre-change PDF `677005b5…` / TeX `4555ffcb…` become the current `17800a44…` (PDF) / `67618f4b…` (TeX).
- The supplement remains 29 pages with the same page map. Only pages 12, 13, 14, 16, 17 and 20 changed; pages 1-11, 15, 18, 19 and 21-29 are pixel-identical to the previous PDF. The contents page and its six table entries are pixel-identical, and the PDF bookmarks remain `Table S1`-`Table S6` on pages 12, 13, 14, 16, 17 and 20.
- The main manuscript PDF `b123ab2f…`, illustrated review copy `2f745950…` and cover letter `d4186225…` are unchanged; all four DOCX files and the highlight file were not rebuilt. DOCX captions remain 11 pt and wide-table bodies 6 pt.
- Utility 33 regenerated Data 5 because its input manifest records the submission profile. All 14 payload members are byte-identical and only `input_manifest.json` changes: the profile entry becomes `0229dbad…` at 15,998 bytes, replacing `486e984a…` at 16,082 bytes, while the manifest remains 15,390 bytes and the bundle becomes `494f1fb2…`, replacing `603b7746…`.
- Stage 24 (138 claims/264 fields, 16 provenance entries), stage 26 (16/16 figures) and `make check` pass. No statistical procedure was rerun and no Git commit, push or publication was performed.
- The 358-entry checksum inventory was refreshed after this rebuild and all 358 entries verify. Relative to the pre-unification inventory, only the profile, scripts 23 and 27, the supplementary TeX/PDF, Data 5 and this document differ.

## Reference audit and Option A corrections (2026-10-26)

A four-party review (clinical oncology, biostatistics, bibliographic forensics, and journal/AMA editorial) independently checked every citation in the main manuscript and supplementary appendix for existence, bibliographic accuracy, and support of the anchored statement. The pre-revision files contained 46 main and 43 supplementary references, or 64 unique works. All 64 DOIs resolved; 56 works were verified against PubMed records and the remainder against Crossref, bioRxiv or publisher records. No fabricated reference was found. The only retracted work was Dressman 2007, which was already paired with its retraction notice and excluded from the evidence base. Numbering was complete and sequential. The review found one substantive coverage gap: the supplement named GO Biological Process sets without citing the MSigDB collection actually used. It also identified several optional AMA-style inconsistencies.

The author approved Option A only:

- The supplementary Methods now reads `GO Biological Process sets (MSigDB C5)` and cites Liberzon et al. 2011 (MSigDB 3.0). This becomes supplementary reference 37; former references 37-43 become 38-44, and the in-text citations renumber accordingly. The supplement therefore has 44 references.
- The Burnham and Anderson book title is in AMA title case in main reference 22 and supplementary reference 8.
- `Reactome` is capitalised in supplementary reference 36.
- The retraction-notice DOI uses uppercase `JCO` in main reference 40 and supplementary reference 26.

No other reference, claim, value or sentence was changed. The optional normalisation of 14 article titles and colon capitalisation was not performed, and no software version citations were added, because these were outside Option A.

### Rebuild and synchronization

- Stage 21 rebuilt the Markdown and DOCX and passed every configured limit: main text 3,042 words; main text plus legends 3,989 of 4,000; abstract 285 of 300; 46 main references; five display items. Stage 23 rebuilt the PDFs and the illustrated review copy; the review-copy identity gate passes on pages 1-18.
- The main PDF remains 18 pages. Only page 12 changed; pages 1-11 and 13-18 are pixel-identical to the baseline. The supplement is now 30 pages (was 29). Pages 7, 28 and 29 changed and page 30 is new; the other 26 common pages are pixel-identical, including table pages 12-20, figure pages 21-26 and the data page 27. Page 7 contains only the approved four-word addition and the resulting citation renumbering. Page 30 contains only reference 44 (Davis and Meltzer); the added entry displaced it from page 29, and no font, leading or spacing was changed because no such change was approved.
- The table typography baseline is unchanged: all six supplementary table headings and captions remain 11.0 pt / 13.2 pt, the S4 body remains 13.25 pt / 15.1 pt, and every supplementary figure still starts on its own page.
- The 21-page illustrated review copy shares text-identical pages 1-18 with the upload manuscript. Its three appended figure pages are pixel-identical to the baseline; only review page 12 changed, matching the manuscript.
- Every reference entry was compared across Markdown, PDF and DOCX after whitespace, hyphenation, page-header and apostrophe normalisation. All 46 main and 44 supplementary entries match exactly. All references are cited, no citation is out of range, and first-appearance numbering is sequential (46/46 and 44/44).
- The DOCX generator previously collapsed each reference list into a single run-on paragraph. Script 22 now emits one hanging-indent paragraph per numbered entry. The paragraphs before and after the reference sections are unchanged; joining the new reference paragraphs reproduces the previous reference paragraph exactly. Package structure and text were checked, but no Word or LibreOffice rendering is available on this host, so DOCX pagination is not certified.
- Stage 24 validates 138 numeric claims (264 fields) and 16 figure-provenance entries; stage 26 passes all 16 formal figure files; `make check` passes. No statistical procedure was rerun.
- Data 5 is unchanged because no reference source is one of its inputs. Utility 33 in dry-run mode reports the same 15 members and bundle hash `494f1fb2…`.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify.
- No Git commit, push or publication was performed.

## Abstract revision (2026-10-26)

A four-party panel (clinical oncology, biostatistics, journal/AMA editing, and academic language/AI-style) independently reviewed the abstract against eight dimensions: content, length, style, structure, format, citations, grammar and naturalness. The clinical-oncology review was rerun after a model-service failure. A second round then put 16 contested wording items to binding votes; the chair resolved the remaining splits and applied one consensus text. The review covered the abstract only.

Changes were wording and definition only:

- `first-line chemotherapy` became `first-line therapy`, consistent with the project terminology rule and the rest of the manuscript.
- TCGA-OV, CR, PR and PD are now defined at first use in the abstract, so it reads independently. The OS time origin is explicit: survival is measured from the end of first-line therapy, the landmark.
- The 372 patients are described as alive at that landmark; the 343 covariate-complete subset is retained because it supports the discrimination analysis.
- `The objective-response grouping was rejected` became `The objective-response constraint (combining CR and PR) was not supported`; this preserves the statistical result while avoiding the reading that objective response as a clinical endpoint has been invalidated.
- The NCR sentence now states the constraint being tested (a single hazard for PR, stable disease and PD) and retains `equivalence was not established`. `support over` became `support for`.
- `the lowest information criteria` became `information criteria favoured the CR threshold`; `C-index` was expanded to `Harrell's concordance index`; `Hartung–Knapp interval` became `Hartung–Knapp–Sidik–Jonkman 95% CI`, with `including 1` making the imprecision visible.
- The PD sentence is limited to an additional hazard beyond other NCR states and retains its uncertainty. `excess risk of progressive disease` was removed as ambiguous.
- `At this landmark` was deleted as redundant; the 47-word conclusion was split; `unproven` became `unestablished`; `directionally consistent` became `estimates pointed the same way`.
- No HR, confidence limit, P value, C-index, sample size or conclusion direction changed. The 220 deaths reported in the main text were considered but not added, because new numeric values were outside the approved scope. The title, highlights and keywords were not edited in this round.

### Rebuild and verification

- Stage 21 rebuilt the Markdown and DOCX: abstract 295 of 300 words; main text 3,042; main text plus legends 3,989; 46 main references; five display items. All configured checks pass.
- The main PDF remains 18 pages. Rendered at 110 dpi, pages 1 and 2 changed (page 1 only the abstract word count, page 2 the abstract itself) and page 12 changed from the earlier reference correction; pages 3-11 and 13-18 are pixel-identical to the pre-revision baseline. The abstract fits on page 2 without spill.
- The 21-page illustrated review copy shares text-identical pages 1-18; its page-change set is the same, and appended figure pages 19-21 are pixel-identical.
- The supplementary PDF is byte-identical (`d6a70b02…`), because no supplementary source or reference changed.
- Seven claim-audit anchors pointed at superseded abstract wording. Only `anchor` and `pattern` fields in `config/manuscript_claims.json` were updated; no expected value, source row, field map, precision or tolerance changed. Stage 24 then validated 138 claims (264 fields) with zero failures, stage 26 passed all 16 formal figure files, and `make check` passed.
- The DOCX abstract consists of one paragraph per heading and matches the source; the reference paragraphs retain the one-entry-per-paragraph hanging-indent layout introduced in the preceding correction.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify.
- No Git commit, push or publication was performed.

## Statistical P typography (2026-10-26)

The manuscript typeset the statistical symbol as unspaced roman `P=`. A four-party panel (clinical oncology, biostatistics, journal/AMA editorial, and academic language) inspected how ESMO Open currently sets the symbol before any change.

Evidence:

- Five articles published by ESMO Open in the current Elsevier era contained 77 statistical P occurrences. Every occurrence used uppercase italic *P*, with spaces around the operator and leading zeros wherever a decimal was shown.
- The publisher's JATS XML marks the symbol as `<italic toggle="yes">P</italic>`, and the PMC HTML uses `<em>P</em>`; both are machine-readable evidence of italics.
- Articles from the 2020 BMJ era used lowercase roman `p=`. That style is obsolete and was not followed.
- The AMA Manual of Style, 11th edition, also specifies italic capital *P*, and the Annals of Oncology guide states the rule explicitly. The ESMO Open guide itself could not be downloaded (HTTP 403), so the journal's practice was established from its published record.

The panel split two votes for a global change, one for the abstract only, and one for leaving the matter to copyediting. The chair ruled that a partial change would leave the manuscript internally inconsistent and recommended global unification. The author approved the global option.

### Implementation and scope

- Stage 21 applies a display-time transform to the title page, main text, declarations, legends, generated Tables 1-2 and the supplement, but never to the numbered reference lists. The transform matches only a standalone `P` (not PD, PR, PFS, PARP, M_PD or author initials), italicises it and spaces the operator. Both spaces are non-breaking, so a line cannot end with `P =` or separate an operator from its estimate.
- The manuscript sources were not edited. The claim patterns anchored on `P=` and the 138-claim audit therefore remain valid. The four sources contain 74 standalone P tokens (59 with operators, 8 in `P was`, and 7 labels in the legends); generated table headings add further occurrences.
- Script 22 now parses emphasis in table-header cells, so a bold header keeps its weight while the P becomes bold italic. Column-width scoring ignores inline markup, so table geometry is unchanged.

### Rebuild and verification

- The main PDF remains 18 pages. Pages 2, 6-10 and 16-18 changed; pages 1, 3-5 and 11-15 are pixel-identical to the baseline. The abstract still fits on page 2.
- The supplementary PDF remains 30 pages. Pages 8-15, 17, 18 and 20-22 changed; pages 1-7, 16, 19 and 23-30 are pixel-identical, including page 16 and the S4 layout. Table headings and captions remain 11.0 pt on 13.2 pt leading, and the S4 body 13.2 pt on 14.68 pt leading.
- The 21-page illustrated review copy changed on pages 2, 6-10 and 16-18; its appended figure pages 19-21 remain pixel-identical, and the identity gate confirms pages 1-18 are text-identical to the upload manuscript.
- Every displayed P span is set in Arial Italic (flags 2): 35 in the main PDF and 67 in the supplement. The only roman standalone P spans in those PDFs are reference author initials (Therasse, Pautier, Royston, Cortazar), which are names, not statistics. No line ends with an operator, and no double spaces were introduced.
- In the DOCX, all displayed P runs are italic, including the bold-italic table headers, and no literal asterisk remains.
- No numeric value, operator, leading zero or conclusion changed: the 59 operator expressions and 8 `P was` statements retain their estimates. Stage 24 validates 138 claims (264 fields) and 16 provenance entries with no failures; stage 26 passes all 16 figures; stage 27 and `make check` pass. No statistical model was rerun.
- Data 5 remains byte-identical at `24b2cfae…`; utility 33 reports the same 15 members.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify.
- Two limits remain. Figure 2's Kaplan-Meier annotation `Log-rank P<0.001` is raster artwork and stays roman and unspaced; altering it requires the separate figure-review approval. No Word or LibreOffice renderer is available on this host, so DOCX pagination is not certified.
- No Git commit, push or publication was performed.

## Abstract accuracy revision (2026-10-27)

A second four-party review (clinical oncology, biostatistics, journal/AMA editorial, and academic language) examined the abstract after the P-typography change. The panel reviewed independently, cross-examined every contested sentence, and returned a unanimous minor-revision verdict (4/4). The review covered the abstract text only. Every correction was a wording change supported by Results already in the manuscript; no model was refitted and no estimate, confidence limit, P value, C-index or sample size was altered.

Four statements were inaccurate or directionally wrong:

- `hazard ratios` became `unadjusted hazard ratios`, matching the Results text and preventing the estimates from being read as adjusted.
- `fitted better at equal parameter count` gained its comparator, `than objective response`: the equal-parameter comparison is the CR-threshold model (M3) against the objective-response model (M2), not against the four-category model.
- `CR-versus-NCR estimates` became `NCR-versus-CR estimates`, the direction of the pooled HR of 4.25.
- `with moderate support for a separate PD hazard` became `with moderate support against a PD hazard`, matching the Akaike weights (M3 0.59 versus M_PD 0.30), and was moved from the C-index sentence to the information-criteria sentence, where the comparison belongs. The earlier phrasing both inverted the direction and attributed the judgement to the wrong analysis.

Two design facts already present in Results were added so the external evidence is not overstated: the external cohorts used a `6-month landmark`, and the only external four-category cohort's PD signal rested on `six patients with PD`.

Other decisions:

- The `Inclusion weights examined selection sensitivity` clause was removed: the abstract named the method but reported no IPW result. The IPW analysis remains in Results and Table 2.
- `was not supported` became `was rejected`, matching Results and the Highlights; the constraint is now defined explicitly as `(CR+PR versus SD+PD)` and the rejection is attributed to `the PR–CR difference`.
- `for death`, `assessment-time proxy`, `remained uncertain` and `including 1` were retained. A proposal to delete the PD sentence entirely was outvoted because the revised sentence discloses its n=6 basis and its uncertainty.
- Keywords were not changed: the configured maximum is six and the current list already uses six, so the optional replacement would have required a separate choice.

### Rebuild and verification

- Stage 21 rebuilt the Markdown and DOCX: abstract 299 of 300 words (was 295); main text 3,042; main text plus legends 3,989 of 4,000; 46 references; five display items. Every configured limit check passes.
- The main PDF remains 18 pages. The title-page word-count line now reads 299, the abstract still fits entirely on page 2, and page 3 still begins the Introduction. The abstract remains four paragraphs with one heading per paragraph.
- Six claim-audit anchors and one pattern in `config/manuscript_claims.json` were updated to the new wording. No expected value, source row, field map, precision or tolerance changed. Stage 24 then validated 138 claims (264 fields) and 16 provenance entries with zero failures; stage 26 passed all 16 formal figure files; `make check` passed.
- The supplementary sources were not edited; the supplement remains 30 pages with the same table typography, and its PDF is byte-identical to the pre-revision build. The cover-letter PDF is likewise byte-identical. Both DOCX files were regenerated by the standard build, but their rendered content did not change.
- Data 5 was rebuilt because its `reporting_index.csv` records the claim anchors. The bundle still has 15 members and now hashes to `0c9f88a9…`; it was assembled from the same locked result tables, and no result was re-estimated.
- The 21-page illustrated review copy was regenerated; stage 23 confirms pages 1-18 are text-identical to the upload manuscript and the three appended figure pages remain in place.
- The P typography is unchanged: 35 italic standalone P spans in the main PDF, no line ends with an operator, and no double spaces were introduced. In the DOCX, 35 main-text and 67 supplementary P runs are italic; the only roman standalone P tokens are the four reference author initials in each file (Therasse, Pautier, Royston, Cortazar), which are names. No literal `*P*` remains. The pre-existing literal `*i*` subscript runs (six main, five supplementary) were not in scope and are unchanged.
- Two limits remain. Figure 2's raster `Log-rank P<0.001` annotation stays roman and unspaced, and no Word or LibreOffice renderer is available on this host, so DOCX pagination is not certified.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify.
- No Git commit, push or publication was performed.

## Introduction accuracy revision (2026-10-27)

A third four-party review (clinical oncology, biostatistics, journal/AMA editorial and academic language) examined the Introduction. The panel reviewed independently, cross-examined every contested sentence and returned a unanimous minor-revision verdict (4/4). Twelve wording changes were made. No citation, estimate, confidence limit, P value, sample size or statistical result changed, and the Introduction fell from 410 to 407 project words.

Accuracy and internal consistency:

- `first-line chemotherapy` became `first-line therapy`, matching the definition of L as the end of first-line therapy.
- `according to RECIST 1.1 or the GCIG criteria` became `using RECIST 1.1 and the GCIG CA-125 criteria`: the two systems are applied together, and the GCIG element is the CA-125 criteria. Both abbreviations remain defined in the title-page abbreviation list.
- The trial sentence was split and `one trial` became `one of these trials`, so that `which also stratified randomisation by response` no longer attaches ambiguously.
- `pre-specified groupings` was replaced by the three named models plus `Both binary codings were specified before analysis`. This was the substantive fix: M_PD was added post hoc (Methods), so the earlier phrase wrongly implied that all groupings, including the PD step, had been specified in advance.
- `Treatment-restricted` became `Treatment-subset`, matching the Methods heading `Robustness across treatment and disease subsets`.
- `post hoc operational HGSOC analysis` became `post hoc operationally defined HGSOC analysis`; `a separate PD step` became `the post hoc PD step`; and `a pretreatment expression score` became `pretreatment expression scores`, matching the locked scores.
- `overall survival` was added as the outcome of the model comparison.

Logic and readability:

- `may instead lie at CR` became `may lie at CR rather than between PR and SD`. The CR threshold lies between CR and PR, whereas the ORR boundary lies between PR and SD; the earlier wording did not name the comparator. An intermediate proposal naming the CR/PR boundary was rejected as self-contradictory.
- The guarantee-time sentence now states the mechanism: responders by definition must survive until response is assessed. The earlier clause about patients who may not have completed therapy was removed.
- `have prevented a firm conclusion` became `have made a firm conclusion difficult`; `time at which response can be assessed` and `response dates` became `time of response assessment` and `response-assessment dates`; `share a prognosis` became `have the same prognosis`; `prior work has relied mainly on pairwise comparisons` became `previous studies have often compared response categories pairwise`; and `binary contrast` became `binary CR contrast`.
- The final semicolon chain was split into two sentences.

Not changed: the opening sentence, naming PAOLA-1 in the text, adding a separate TCGA citation (which would renumber the reference list), the `pre-specified`/`prespecified` and `non-significant`/`nonsignificant` conventions, and the cover letter's `first-line chemotherapy`.

### Rebuild and verification

- Stage 21: Introduction 407 words (was 410); main text 3,039 (was 3,042); main text plus legends 3,986 of 4,000; abstract 299 of 300; 46 main and 44 supplementary references; five display items. Every configured limit check passes. No citation key or citation position changed, so reference numbering is unchanged.
- Stage 24 validates 138 claims and 16 provenance entries with zero failures; stage 26 passes all 16 formal figure files; `make check` passes.
- The main PDF remains 18 pages. Page 3 begins the Introduction; page 2 retains Highlights, the 299-word abstract and Keywords. Page 4 begins `post hoc.`: a non-breaking space between `post` and `hoc` in the Study design paragraph prevents the one-word `hoc.` line that the three-word shortening would otherwise have produced. No wording changed.
- The 21-page illustrated review copy was regenerated; its first 18 pages are text-identical to the upload manuscript and the three figure pages are appended.
- The supplement (30 pages) and cover letter (2 pages) sources and TeX files are byte-identical to the pre-change inventory; their DOCX and PDF files were regenerated by the standard build. No Introduction text appears in either document.
- P typography is unchanged: the main DOCX contains 35 italic standalone P tokens and the supplement 67; the only roman standalone P tokens are the four reference author initials in each file. No line in the main PDF ends with an operator and no double spaces were introduced.
- Data 5 is unchanged (`0c9f88a9…`): the Introduction contains no claim anchors, so the bundle was not rebuilt. No model was refitted and no result table changed.
- The only source changes are `manuscript/source/introduction.md` and one non-breaking space in `manuscript/source/methods_results.md`; all submission files in `manuscript/submission` were rebuilt.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify.
- No Git commit, push or publication was performed.

## Patients and methods accuracy revision (2026-10-27)

A fourth four-party review (clinical oncology, biostatistics, journal/AMA editorial and academic language) examined Patients and methods. The panel reviewed independently, cross-examined every contested sentence and returned a unanimous minor-revision verdict (4/4). The approved package combined 17 main-text wording corrections (A), two supplement corrections (B) and a display-layer model-label fix (C). No model was refitted and no estimate, confidence limit, P value, C-index, sample size or multiplicity rule was altered.

Accuracy and internal consistency:

- `Figure 1 outlines secondary and exploratory analyses` became `Figure 1 summarises the study design and analysis structure`, so the sentence covers the whole design rather than implying that Figure 1 is limited to secondary analyses.
- `grade was used only to define the HGSOC population` became `grade was used only to define analysis populations`: grade G3–G4 also defines a subset, so `HGSOC population` was too narrow and `only` would otherwise be inaccurate.
- `A patient entered the OS risk set only if` replaced the earlier split construction, making the three inclusion conditions attach unambiguously to risk-set entry.
- `each encoding a different grouping of response categories` replaced `each encoding a different response grouping`, and M3 is now defined as `CR versus PR+SD+PD, termed non-complete response [NCR]`. The definition makes the NCR expansion explicit at first use without changing the contrast.
- `0.50–2.00` replaced `0.50–2.0` for the relaxed equivalence margin, matching the supplement and the configured bounds.
- `A non-significant difference was not taken as equivalence:` introduced the equivalence rule as a consequence of the preceding tests rather than as a separate assertion.
- `gains over the clinical-only model were paired by repeat` replaced the ambiguous `paired differences`; pairing is by repeat, and the empirical percentiles remain descriptive.
- `an operationally defined HGSOC population; TCGA-OV is serous by design` replaced `a TCGA-OV HGSOC population`, separating the cohort-wide serous histology from the additional operational restriction. `The HGSOC definition additionally required` makes clear that grade and stage are added to, not substituted for, serous histology.
- `Post hoc analyses used delayed-entry Cox models at the landmark` replaced `Post hoc delayed-entry Cox analyses at the landmark`, so the model type is attached to the analyses rather than to the time origin.
- `Response-assessment and treatment-end dates were unavailable` replaced `Treatment-end dates were unavailable`: response dates are also missing in the external cohorts, and both limitations condition the fixed landmark.
- `the article was retracted` replaced `its source was retracted`, naming the retracted object directly.
- `Unadjusted estimates were pooled` replaced `Estimates were pooled`; the external models are unadjusted, so the qualifier prevents an implicit adjusted interpretation.
- `in 23 TCGA tumour types` replaced `across 23 TCGA tumour types`; `all` was removed because eligibility differs between the four-state and CR-versus-NCR audits.
- `internally recorded qualitative criteria` replaced `internally recorded qualitative external criteria`; the criteria were recorded internally and applied to external data, so the adjective `external` was misplaced.
- `Case- and sample-level data` replaced `Case-level data`, covering Supplementary Data 2 as well as the case-level files.

Supplement consistency (B):

- The covariate sentence now reads `grade was used only to define analysis populations`, matching the main text and the adjusted-model formula, which contains age, stage and residual disease but not grade.
- The relaxed sensitivity margin is written `0.50–2.00`, matching the main text and the configured bounds.

Model-label typography (C):

- `M_PD` is now rendered as M with a subscripted PD at the display layer only. Stage 22 converts the label to `M~PD~` when reading the generated Markdown for the DOCX, including table headers; stage 23 replaces `M\_PD` with `M\textsubscript{PD}` in the final TeX after the table line-break rules have run. The generated Markdown keeps the literal `M_PD` so the stage 24 claim anchors remain valid.
- The main PDF contains 16 subscripted labels and the supplement 35; the DOCX contains 16 and 35 subscript runs, matching the label counts in each document. No literal `M_PD` remains in prose, tables, figure legends or the supplement.
- Figure 1 artwork still printed `M_PD` inside the schematic at the time of this approval. That single label was corrected separately on 2026-10-28; see the next section.
- While verifying the DOCX, italic emphasis inside a script token was found to be printed literally (`L*i*`). The parser now renders `~*i*~` as an italic subscript i (six occurrences in the main DOCX and five in the supplement). This is a display-only correction: no source text, word count, value or model definition changed.

### Rebuild and verification

- Stage 21: Methods 928 words (was 917); main text 3,050 (was 3,039); main text plus legends 3,997 of 4,000; abstract 299 of 300; 46 main and 44 supplementary references; five display items. Every configured limit check passes.
- Stage 24 validates 138 claims and 16 provenance entries with zero failed fields; stage 26 passes all 16 formal figure files; stage 27 and `make check` pass.
- The main PDF remains 18 pages. Page 3 begins the Introduction and Patients and methods; page 11 begins References, page 14 Figure legends and page 17 Tables. The 21-page illustrated review copy was regenerated; its first 18 pages are text-identical to the upload manuscript and the three figure pages are appended.
- The supplement remains 30 pages and the cover letter 2 pages. Table typography is unchanged: table titles at 11.0 pt, the Table S4 body at 13.2 pt and wide-table bodies at 6 pt. The manuscript and supplement DOCX files were regenerated by the standard build.
- P typography is unchanged: 35 italic standalone P tokens in the main PDF and 67 in the supplement.
- Data 5 was unchanged at that revision (`0c9f88a9…`): the revised sentences contain no reporting-bundle claim anchors, so the bundle was not rebuilt then.
- Source changes are `manuscript/source/methods_results.md` and `manuscript/source/supplementary.md`; script changes are `scripts/22_generate_submission_docx.js` and `scripts/23_build_submission_latex.py`. Pre-change copies are archived in `../archive/methods_review_pre_20261027/`.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify.
- No Git commit, push or publication was performed.

## Figure 1 model-label typography revision (2026-10-28)

Model-label typography (C) left one literal `M_PD` inside the Figure 1 schematic, in the analysis-structure line of panel A. The author authorised a purely typographic correction of that single label. No value, contrast definition, sample size, layout, panel position, arrow, colour or other text in the figure was altered.

Method:

- The label was edited in the vector master `results/figures/manuscript/Figure1_study_design.pdf` with PyMuPDF. The single span `M3 CR versus NCR; M_PD post hoc` was redacted with a white fill and reinserted in Arial at the same 8.0 pt size and the same baseline, split as `M3 CR versus NCR; M`, `PD` and ` post hoc`, with the `PD` glyphs lowered by 2.2 pt. Lowering rather than reducing size keeps the subscript at 8.00 pt and satisfies the stage 26 minimum-font rule.
- A 144-dpi pixel comparison against the pre-change master is confined to the bounding box (30, 968, 288, 990), which contains only this label line. Every other pixel on the 538 × 530 pt page is unchanged.
- Panel A was re-frozen from the edited master as `locked_panels/Figure1A.pdf` (252 × 530 pt, minimum font 8.0 pt) without the previously embedded original raster. Panels B and C were not rewritten: `Figure1B_primary.pdf` remains `371b8bdc…` and `Figure1C.pdf` remains `a53b6872…`.
- `config/submission_profile.json` was updated: the Figure 1 `baseline_sha256` is now the edited master hash, the `Figure1A` region no longer carries `original_png_crop_px`, `preserved_panels` lists only `Figure1C`, and `locked_region_sha256.Figure1A` is the new panel hash. `baseline_png_sha256` is intentionally unchanged because it records the historical original raster used by the preserved C panel.

Hashes after the revision:

| Artefact | SHA-256 |
|---|---|
| Authored Figure 1 source used to freeze panel A (pre-composition) | `ca38eea07e2bbad58fc092b85fdb550e191cd1ad4be640cd4197a806ffb16718` |
| `locked_panels/Figure1A.pdf` | `00b432a1704f31e87ffa1c65577d156b97a2d2ce0909b14c5a57bb7c7aca8ad4` |
| `results/figures/{main,manuscript}/Figure1_study_design.pdf` | `03fe05551ebbdbab73193ead60d0e1b71c9c911137e7d286857fa54d5df0d9c7` |
| `results/figures/{main,manuscript}/Figure1_study_design.png` | `e284a8547567f98445c0a4ef6fba65fd77a057884bb22c85f9c72e6131acbdad` |

As for every locked figure, stage 30 intentionally overwrites the active manuscript source path with the composed figure, so `results/figures/manuscript/Figure1_study_design.pdf` now carries the same `03fe0555…` hash as the formal outputs; `baseline_sha256` in the profile records the authored `ca38eea0…` source from which panel A was frozen.

The archived pre-change master (`b36cc4a10202eeaf60e48bb0d38deb3c82d9a27b6a8d016649af8ca2f330e918`), Figure1A panel (`55c0bb19…`) and Figure 1 PNG (`e8805e0e…`) are retained in the archive directory.

Verification:

- Stage 30 recomposed Figure 1 from the three clean vector regions with exact 144-dpi pixel parity; the PNG remains 4488 × 4417 px at 600 dpi and all 170 protected files were reported unchanged.
- `pdftotext` finds no `M_PD` in the formal Figure 1 PDF, in the 18-page main manuscript or in the 21-page illustrated review copy; the extracted label reads `M3 CR versus NCR; MPD post hoc`, with the `PD` separated by the 2.2 pt baseline offset and displayed at 8 pt.
- The illustrated review copy was rebuilt. Its first 18 pages remain text-identical to the upload manuscript and page 19 carries the corrected Figure 1.
- Stage 24 validates 138 claims and 16 provenance entries with zero failed fields; stage 26 audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- The manuscript and supplement word counts, page counts, table typography and P-value typography are unchanged. Data 5 was rebuilt because its input manifest records the submission profile: only `input_manifest.json` changed (the profile hash), all 14 other members are byte-identical, and the bundle hash moved from `0c9f88a9…` to `ff7bf2e7901bab30f72b118385e25113ce7c76fbd4215f9d3b8b8682932bb864`.
- Pre-change copies of the master PDF and PNG, the two formal Figure 1 PDFs and PNGs, and the three locked panel PDFs are archived in `../archive/figure1_mpd_subscript_pre_20261028/`.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify. No Git commit, push or publication was performed.

## Results accuracy revision (2026-10-28)

The Results section was reviewed by the four-party team (clinical oncology, biostatistics, journal editing and academic language) across content, length, style, structure, format, citations, grammar and natural expression. The revision fixes one logical error, replaces an undefined abbreviation, specifies the model contrast in the Akaike comparison, adds one confidence interval already present in Table 2, and aligns terminology and punctuation. No estimate, confidence limit, P value, sample size, model or claim direction was changed.

Content and logic:

- `372 met the landmark eligibility criteria` replaced `372 were alive at a plausible, patient-specific end of first-line therapy`. Eligibility is defined in Methods; the earlier wording implied a separate survival filter and was ambiguous about the 60–365-day window.
- `Median landmark timing was` replaced `The landmark fell at a median of`; the sentence now states the median directly and reads `across response categories` rather than `in every response category`.
- `with broadly similar point estimates` replaced `with similar point estimates`; the PR, SD and PD estimates differ by up to 25%, so `similar` overstated the agreement.
- `the objective-response constraint` replaced `ORR constraint` in every Results occurrence. `ORR` means objective response rate, whereas the tested constraint is the objective-response coding (CR+PR versus SD+PD) defined in Methods. Table 2 and the legends keep the short test label.
- `The rejection arose from the PR–CR difference (P=1.1×10⁻¹⁰; 1 df), not the SD–PD difference (P=0.83)` replaced the two-clause `difference between ...` construction. The degrees of freedom are now reported with the P value in AMA order.
- `Support for M3 over M_PD was moderate` replaced `Support over M_PD was moderate`; the comparison now names the preferred model.
- The 240-word model-comparison paragraph was split after the bootstrap sentence. The second paragraph begins `Under Schoenfeld's formula` and reports pairwise power and equivalence; `pairwise contrasts within NCR` replaced `pairwise NCR contrasts`.
- `The PFI pattern was similar` replaced `Results for PFI were similar`; PFI is secondary and the sentence describes the pattern, not a duplicate analysis.
- `the NCR HR was 3.2–3.9, with plateau P≥0.27, and the objective-response constraint` replaced the unpunctuated list; `HRs versus CR were 2.56 for PR, 4.64 for SD and 7.78 for PD` replaced `rose from 2.56 for PR to ...`, which implied a within-patient trajectory.
- `without the small, extreme GSE23554 cohort` now names the cohort rather than the accession alone.
- `HR 5.89, 95% CI 4.02–8.62, versus CR` adds the interval already displayed in Table 2; the comparison is now explicit. `The PD step appeared only in the larger diagnosis-origin cohort, not in the 372 landmark patients analysed from the same origin` replaced `was seen ... not after changing the time origin in the same patients`, which misdescribed the comparison: both analyses use diagnosis as origin and differ by cohort membership.
- `Six tumour types` replaced `Six cancers`, matching the TCGA terminology used elsewhere; `only ovarian cancer and, partly, lower-grade glioma (LGG) met the four-state criteria` makes clear that ovarian cancer met the criteria fully and LGG only partly, matching the Supplementary Results; `ovarian four-category topology` names the structure being generalised.
- `pooled NCR HR ... 4.02, 95% CI 3.29–4.92` and `pooled general-proliferation difference` add the missing interval label and the name of the locked score.

Word count and claims:

- Results moved from 966 to 964 words; the main text from 3,050 to 3,048 and the main text plus legends from 3,997 to 3,995 of 4,000. The abstract remains 299 of 300, with 46 main and 44 supplementary references and five display items.
- Eight claim patterns and twelve claim anchors in `config/manuscript_claims.json` were updated to the revised wording. No `source_file`, `row_filter`, `field_map`, `display_precision`, tolerance or expected value was changed. Stage 24 validates all 138 claims and 16 provenance entries with zero failed fields.
- Data 5 was rebuilt because its input manifest records the claims configuration: 13 of 15 members are byte-identical, `input_manifest.json` and `reporting_index.csv` changed, and the bundle hash moved from `ff7bf2e7901bab30f72b118385e25113ce7c76fbd4215f9d3b8b8682932bb864` to `3b187beedb8cb6fd31715958cb39afd78ebcc19bc0a1123d9c701714ff7dff6f`. Reproducing the bundle from the archived claims configuration gave the previous `ff7bf2e7…` hash exactly, confirming that no other input changed.

Rebuild and verification:

- Stages 21, 22 and 23 rebuilt the Markdown, TeX, DOCX, PDF and illustrated review copy. The main PDF remains 18 pages, with Results beginning on page 6 and Discussion on page 8; the review copy remains 21 pages with pages 1–18 text-identical to the upload manuscript; the supplement remains 30 pages and the cover letter 2 pages.
- Stage 24 validates 138 claims and 16 provenance entries, stage 26 audits 16 formal figures, stage 27 and `make check` pass. P typography is unchanged at 35 italic standalone P tokens in the main PDF and 67 in the supplement; the main PDF and DOCX carry 16 subscripted `M_PD` labels and the supplement 35, with no literal `M_PD`.
- Rendered Results pages 6–7 were inspected: no heading is orphaned, no line ends with an operator and no new line-break artefact was introduced.
- The pre-change manuscript and claims configuration are archived in `../archive/results_review_pre_20261028/`.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify. A local Git repository was then initialized in this release directory and the verified state was recorded as the initial `main` commit; no remote was configured, and no push, publication or DOI deposit was performed.

## Discussion accuracy revision (2026-10-28)

The Discussion was reviewed by the four-party team (clinical oncology, biostatistics, journal editing and academic language) across content, length, style, structure, format, citations, grammar and natural expression. The approved package combined the Discussion wording revision (A) with terminology synchronisation in Methods, the Table 2 legend and the Supplementary Results (B). No model was refitted and no estimate, confidence limit, P value, sample size or claim direction was changed.

Content and precision:

- `an unadjusted 3.6- to 4.5-fold higher hazard of death than CR, with wide intervals for SD and PD` replaced `a three- to five-fold higher hazard`. The new range re-expresses the existing unadjusted hazard ratios (3.61–4.50) and acknowledges the imprecision of the SD and PD estimates.
- `the objective-response constraint` replaced `the ORR constraint`; `in the primary and sensitivity analyses` replaced `throughout the primary and sensitivity analyses`. The tested object is the CR+PR versus SD+PD coding, not the objective response rate.
- `the lowest AIC and BIC` replaced `the lowest information criteria`; `support relative to a model with a separate PD step was moderate` replaced `support over a model ... was moderate`; `the plateau test had limited power` replaced `the plateau test was underpowered`.
- `These results add` replaced `What these results add is`; `at a patient-specific landmark` replaced `at a patient-specific end-of-treatment landmark`; `complement` replaced `extend`; `yielded a smaller cross-validated gain` replaced `reduces the cross-validated gain`; `best-supported grouping` replaced `best-supported candidate grouping`.
- The sentence `What recorded CR denotes in these data also matters` was removed. `recorded CR may therefore correspond to a no-evidence-of-disease state` replaced `may therefore approximate`; `Recorded CR was closely tied to surgery` replaced `It was closely tied to surgery`.
- `exploratory HRs versus CR were 2.56, 4.64 and 7.78 for PR, SD and PD` replaced `risk rose from PR to PD`, which implied a within-patient trajectory; `requires testing` replaced `needs testing`.
- `The clinical implication is focused` was removed. `Combining CR and PR as objective response discards the prognostic information in the CR–PR distinction` replaced `Combining CR and PR within ORR discards prognostic information`; `entailed little numerical loss` replaced `caused little numerical loss`.
- The four-part negation was compressed without changing its scope: `it does not invalidate ORR as a measure of antitumour activity [@recist], imply that increasing CR causes longer survival, determine maintenance eligibility, or test ORR or CR as a trial-level surrogate endpoint [@cortazar]`.
- `PD appeared distinctly worse when all labelled patients were analysed from diagnosis` replaced `in all labelled patients analysed from diagnosis`; `IPW estimates` replaced `Inclusion-weighted estimates`; `descriptive rather than inferential` replaced `descriptive rather than calibrated inference`; `Only 30 landmark patients had PD` replaced `TCGA included only 30 patients with PD`; `different pattern` replaced `different topology`; `distinguished CR from NCR` replaced `explained the CR threshold`.
- The limitations paragraph was split after `limiting adjustment.` The second paragraph begins `The TCGA cohort predates`. `treatment end was derived from GDC records` replaced `treatment end was a proxy derived from uncurated GDC records`; `Response status at the landmark was not verified` replaced `Response was not verified as established by the landmark`; `IPW addressed proxy eligibility but left patients with missing stage unrepresented` replaced `IPW targeted proxy eligibility, could not represent patients with missing stage`; `it does not establish that selection bias was eliminated` replaced `it did not establish elimination of selection bias`; `operationally defined HGSOC analysis` replaced `operational HGSOC analysis`.
- In the conclusion, `objective-response grouping` replaced `ORR grouping`; `fitted better than objective response at equal parameter count` replaced `fitted better with the same number of parameters`; `remain unestablished` replaced `remain unproven`.

Terminology synchronisation (B):

- Methods now reads `the objective-response constraint test`; the Table 2 legend reads `objective-response constraint P`.
- In the Supplementary Results, eight occurrences of `ORR constraint` became `objective-response constraint`, `ORR coding` became `objective-response coding`, and `plateau, ORR and PD-step constraints` became `plateau, objective-response and PD-step constraints`.
- `ORR` remains defined as objective response rate and is retained only where a rate is reported (`plus ORR 0.641`, `0.633 with ORR`).

Word count and claims:

- The Discussion moved from 768 to 765 words; the main text from 3,048 to 3,045 and the main text plus legends from 3,995 to 3,992 of 4,000. The abstract remains 299 of 300, with 46 main and 44 supplementary references and five display items.
- Two claim anchors and one claim pattern in `config/manuscript_claims.json` were updated to the revised wording. No `source_file`, `row_filter`, `field_map`, `display_precision`, tolerance or expected value was changed. Stage 24 validates all 138 claims and 16 provenance entries with zero failed fields.
- Data 5 was rebuilt because its input manifest records the claims configuration: 13 of 15 members are byte-identical, `input_manifest.json` and `reporting_index.csv` changed, and the bundle hash moved from `3b187beedb8cb6fd31715958cb39afd78ebcc19bc0a1123d9c701714ff7dff6f` to `68e8272377a0cfa09cf95ce37021a332611e805bdae6e9cad64ee7157ef277de`. Rebuilding the bundle from the archived pre-change claims configuration reproduced `3b187bee…` exactly, and a member-level comparison confirmed that the two changed members are confined to the claims digest and the two re-anchored navigation rows.

Rebuild and verification:

- Stages 21, 22 and 23 rebuilt the Markdown, TeX, DOCX, PDF and illustrated review copy. The main PDF remains 18 pages, with the Discussion beginning on page 8; the review copy remains 21 pages with pages 1–18 text-identical to the upload manuscript; the supplement remains 30 pages and the cover letter 2 pages.
- Stage 24 validates 138 claims and 16 provenance entries, stage 26 audits 16 formal figures, stage 27 and `make check` pass. P typography is unchanged at 35 italic standalone P tokens in the main PDF and 67 in the supplement; the main PDF and DOCX carry 16 subscripted `M_PD` labels and the supplement 35, with no literal `M_PD`.
- Rendered Discussion pages 8–9 were inspected: no heading is orphaned, no line ends with an operator and no new line-break artefact was introduced.
- The pre-change Discussion, Methods/Results, legends, Supplementary Results and claims configuration are archived in `../archive/discussion_review_pre_20261028/`.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify. No Git commit, push, publication or DOI deposit was performed.

## Declarations accuracy revision (2026-10-28)

The ethics statement and everything after it were reviewed by the four-party team across content, length, style, structure, format, citations, grammar and natural expression. The approved package combined five accuracy and compliance corrections (A) with two reproducibility edits (B). No analysis was rerun and no numerical result, sample size or claim direction was changed. The author list and order are unchanged, Qingqing Mo remains the sole first author, and no co-first-author statement was added. The funding statement is unchanged.

Ethics, acknowledgements and data availability (A):

- The ethics statement now records that the source studies were conducted under their original ethical approvals and informed-consent procedures, and that no additional approval or consent was required because the analysis used only de-identified, publicly available data. The previously raised institutional-exemption and Helsinki-declaration wording was not added, as instructed.
- The acknowledgements now credit the TCGA Research Network with its standard citation and URL, in addition to the patients and external-cohort investigators.
- The heading `Data sharing` became `Data sharing statement`, matching the journal's declarations structure.
- The data sources are separated by data type: TCGA-CDR and TCGA-OV clinical data, and TCGA-OV expression, copy-number, methylation, protein and homologous recombination deficiency score data, both via UCSC Xena. The previous sentence attributed all of these to a single source and conflated the clinical resource with the molecular cohort.
- `Case-level identifiers` became `De-identified case-level identifiers`, which is accurate for the TCGA barcodes and response records released in Supplementary Data 1–4.

Release record and versions (B):

- The repository statement now reads `will be released in a public repository under the MIT licence and archived in Zenodo with a DOI upon acceptance`. The earlier wording placed the DOI archive before release and implied a deposit schedule that had not been fixed.
- The msigdbr version (25.1.1) is now stated alongside the curatedOvarianData version (1.46.2), both taken from `renv.lock`. The MSigDB gene sets affect the expression-score derivations, so the version is part of the reproducible record.

Author contributions:

- CRediT roles were reassigned so that each author's stated contribution matches the work recorded in the repository. Qingqing Mo: Methodology, Formal analysis, Data curation, Visualization, Writing – original draft. Pingbo Chen: Investigation, Data curation, Validation, Writing – review and editing. Cheng Xu: Methodology, Validation, Funding acquisition, Writing – review and editing. Ya Wang: Methodology, Validation, Funding acquisition, Writing – review and editing. Ting Hu: Investigation, Validation, Writing – review and editing. Qian Sun: Investigation, Validation, Writing – review and editing. Tao Zhu: Conceptualization, Methodology, Software, Supervision, Project administration, Writing – review and editing. All authors read and approved the final manuscript.

Invariants and verification:

- Word counts are unchanged: main text 3,045, main text plus legends 3,992 of 4,000, abstract 299 of 300, 46 main and 44 supplementary references, and five display items. The main PDF remains 18 pages, the illustrated review copy 21 pages with pages 1–18 text-identical to the upload manuscript, the supplement 30 pages and the cover letter 2 pages.
- Data 5 was not rebuilt because the declarations are not a bundle input; its hash remains `68e8272377a0cfa09cf95ce37021a332611e805bdae6e9cad64ee7157ef277de` with 15 members.
- Stage 24 validates 138 claims and 16 provenance entries, stage 26 audits 16 formal figures, and stage 27 and `make check` pass. P typography remains 35 italic standalone P tokens in the main PDF and 67 in the supplement; subscripted `M_PD` labels remain 16 in the main manuscript and 35 in the supplement, with no literal `M_PD`.
- Rendered pages 9–10 were inspected: the revised ethics statement, acknowledgements, funding, disclosure, data sharing statement and author contributions appear in sequence, and the reference list begins on page 11.
- The pre-change declarations are archived in `../archive/declarations_review_pre_20261028/`.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify. No Git commit, push, publication or DOI deposit was performed.

## Reference accuracy revision (2026-10-28)

The complete reference lists were audited by the four-party team for count, numbering order, uncited entries, authenticity, appropriateness and bibliographic accuracy. All 65 unique printed works (46 main, 44 supplementary, 25 shared) resolved through Crossref to the verified PubMed metadata, every printed number was cited in order with no gaps, and no entry was uncited or duplicated within a list. The approved package corrected two AMA 11th edition presentation errors (A) and normalized article-title capitalization and journal/book typography (B). No reference was added, removed or renumbered, no citation–sentence pairing changed, and the optional guideline update (C) was not adopted.

Reference-list corrections (A):

- The retraction notice (main ref 40, supplementary ref 26) now begins with its title. The placeholder author segment `[No authors listed].` was removed, as AMA 11th edition requires for a work without named authors; `ama_authors()` returns an empty segment and `vancouver()` omits the lead-in when no authors are recorded.
- The Dressman entry (main ref 39, supplementary ref 25) now reads `Retraction in:` instead of `Retracted in:`, the conventional label for a retraction notice paired with the original article.

Title case and typography (B):

- Eleven unique article titles (14 list occurrences, because main refs 17, 20 and 33 are shared with supplementary refs 3, 1 and 19) were converted from title case to AMA sentence case, preserving acronyms and proper names (TCGA, CA-125, GINECO AGO MRC CTU, The Cancer Genome Atlas, doppelgänger).
- One colon was lowercased in `cohen_crs` (main ref 9): `carcinoma: a systematic review and meta-analysis of individual patient data`.
- Journal abbreviations in every main and supplementary entry are now italic, as are the Burnham & Anderson and Rubin book titles and the bioRxiv preprint-server name. The ten Crossref override strings and the retraction note were updated to match. DOCX output carries true italic runs, LaTeX output uses `\emph`, and neither rendered source retains a literal asterisk.

Invariants and verification:

- Counts, order and citation mapping are unchanged: 46 main and 44 supplementary references, 25 shared and 65 unique (90 combined, below the 100 limit); every number 1–46 and 1–44 is cited, with no gap, duplicate DOI or uncited printed entry.
- DOI, year, volume, issue and page metadata are unchanged; only capitalization, the two retraction labels and italic markup were edited. The pre-change reference JSON, overrides and build script are archived in `../archive/reference_review_pre_20261028/`.
- Word counts remain 3,045 main text, 3,992 main text plus legends of 4,000, 299 abstract of 300, 46 references and five display items. The main PDF remains 18 pages, the illustrated review copy 21 pages with pages 1–18 text-identical to the upload manuscript, the supplement 30 pages and the cover letter 2 pages.
- Data 5 was not rebuilt because the reference sources are not bundle inputs; its hash remains `68e8272377a0cfa09cf95ce37021a332611e805bdae6e9cad64ee7157ef277de` with 15 members.
- Stage 24 validates 138 claims and 16 provenance entries, stage 26 audits 16 formal figures, and stage 27 and `make check` pass. P typography remains 35 italic standalone P tokens in the main PDF and 67 in the supplement; subscripted `M_PD` labels remain 16 in the main manuscript and 35 in the supplement, with no literal `M_PD`.
- Rendered reference pages 11–12 and supplementary page 28 were inspected: italic journals, sentence-case titles, the retraction notice and the authorless entry display correctly.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify. No Git commit, push, publication or DOI deposit was performed.

## Supplementary front-matter revision (2026-10-28)

The four-party team reviewed the supplement from the title page through the end of the contents (PDF pages 1–2). Approved package A corrected the front-matter text and package B separated the title page from the contents; optional global typography (C) was not adopted. No scientific result, estimate, interval, P value, sample size, citation or claim direction was changed.

Text (A):

- The duplicated `Contents:` label at the foot of the title page was replaced with `**This appendix contains:** Supplementary Methods; Supplementary Results; Supplementary Tables S1–S6; Supplementary Figures S1–S5; Supplementary Data 1–4 (CSV files) and Supplementary Data 5 (ZIP reporting bundle); Supplementary References.` The generated Contents page that follows is now the only contents heading, and the data phrasing is parallel for CSV and bundle deliverables.
- Six abbreviations missing from the supplement but shared with the main text were added in alphabetical order, using the main title page's definitions: FIGO, International Federation of Gynecology and Obstetrics; GDC, Genomic Data Commons; GEO, Gene Expression Omnibus; RMST, restricted mean survival time; TCGA-OV, TCGA ovarian cancer cohort; UCSC, University of California, Santa Cruz. The list now has 27 entries.

Pagination (B):

- Stage 22 inserts a DOCX page break before the Contents heading, and stage 23 inserts `\clearpage` before `\tableofcontents`; a second `\clearpage` keeps Supplementary Methods on page 3. Page 1 is therefore a standalone title page and page 2 holds the complete contents.
- The LaTeX front matter from the actual `\begin{document}\maketitle` call to the contents marker is wrapped in `\begingroup\hyphenpenalty=10000\exhyphenpenalty=10000`, closed before the generated contents. This prevents intra-word breaks in long affiliation, ORCID and data-file names introduced by the longer sentence. The regex targets only the document-body call, not the `\renewcommand{\maketitle}` definition.

Verification:

- The supplement remains 30 pages. `Contents` appears only on page 2; `Supplementary Methods` and its first subsection begin on page 3. The contents fit on one page with unchanged page numbers: Methods 3, Results 8, Tables 12, S1 12, S2 13, S3 14, S4 16, S5 17, S6 20, Figures 21, Data 27, Data conventions 27, References 28.
- Page 1 was rendered and inspected: the contents sentence and all 27 abbreviations are present, with no intra-word hyphenation. The DOCX contains one page break before the Contents heading and retains its TOC field.
- The main upload PDF remains 18 pages and the illustrated review copy 21 pages, with pages 1–18 text-identical to the upload; only supplementary sources and the two build scripts changed. Word counts remain 3,045 main text, 3,992 main text plus legends, 299 abstract, 46 references and five display items.
- Data 5 is not a bundle input and was not rebuilt; its SHA-256 remains `68e8272377a0cfa09cf95ce37021a332611e805bdae6e9cad64ee7157ef277de` with 15 members.
- Stage 24 validates 138 claims and 16 provenance entries, stage 26 audits 16 formal figures, and stage 27 and `make check` pass. Italic standalone P tokens remain 35 in the main PDF and 67 in the supplement; the remaining roman `P` tokens are author initials. Subscripted `M_PD` labels remain 16 in the main manuscript and 35 in the supplement, with no literal `M_PD` in either rendered PDF.
- The pre-change supplement source and both build scripts are archived in `../archive/supplementary_front_pre_20261028/`.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify. No Git commit, push, publication or DOI deposit was performed.

## Supplementary methods pages 3–4 revision (2026-10-28)

The four-party team reviewed the three method subsections on supplement PDF pages 3–4: TCGA-OV clinical data and response labels; first-line treatment dates and landmark; and model comparison details. Approved package A corrected three accuracy issues and package B clarified five reproducibility points; optional items C1–C3 (flow counts, a PFI definition and an MI convergence rerun) were not adopted. No scientific result, estimate, interval, P value, sample size, citation or claim direction was changed, and no analysis script was rerun.

Accuracy (A):

- The Wald/LRT paragraph now reads `These constraints were also tested in all 372 landmark-eligible patients with a multivariate Rubin's-rules Wald statistic (D1); complete-case analyses used likelihood-ratio tests.` This names the tested constraints and separates the multiply imputed Wald test from the complete-case likelihood-ratio tests.
- The cross-validation sentence now states that `each model was evaluated on the same validation patients, and concordance counts were not pooled across models`, replacing the ambiguous claim that no pairs were compared across fitted models.
- The radiotherapy sentence now uses `the later of the available systemic and radiotherapy end dates`, matching the `coalesce(..., -Inf)` plus `pmax` construction when one end date is missing.

Reproducibility and clarity (B):

- Cross-validation is now located in `the 343 covariate-complete landmark patients`, with `20 repeats of five-fold cross-validation stratified by four-category response`; the training fraction is `approximately four fifths of these 343 patients`.
- The two constraints are defined as `plateau (PR = SD = PD)` and `objective-response (PR = CR and SD = PD)`.
- The post hoc checks now read `neither was intended to eliminate time-related selection`, replacing the fragmentary `not time-related selection`.
- Multiple imputation now reports the actual missingness: `stage for 1 patient and residual disease for 28`, with `polytomous regression for stage and residual disease, with complete age included as a predictor`. Age had no missing values in the 372-patient landmark cohort.

Layout:

- Stage 23 now sets `\widowpenalty=10000\clubpenalty=10000` immediately after `\maketitle`, outside the front-matter hyphenation group, so the penalties persist across the appendix. This removes single-line page-boundary fragments without changing text, fonts, leading, margins or table geometry.
- The supplement is now 31 pages (was 30). The added wording pushed the end of the Results section by one page; the Methods and Results headings remain on pages 3 and 8. The contents map is Methods 3, Results 8, Tables 13, S1 13, S2 14, S3 15, S4 17, S5 18, S6 21, Figures 22, Data 28, Data conventions 28, References 29. Page 31 contains only reference 44, as page 30 did in the 30-page build.
- Page 1 remains the standalone title page, page 2 the complete contents and page 3 the start of Supplementary Methods. The main upload PDF remains 18 pages, the illustrated review copy 21 pages with pages 1–18 text-identical to the upload, and the cover letter 2 pages.

Verification:

- Stage 21 reports 3,045 main-text words, 3,992 main text plus legends, a 299-word abstract, 46 main and 44 supplementary references, and five display items; all configured limits pass.
- Stage 24 validates 138 claims and 16 provenance entries, stage 26 audits 16 formal figures, and stage 27 and `make check` pass.
- Data 5 was not rebuilt; its SHA-256 remains `68e8272377a0cfa09cf95ce37021a332611e805bdae6e9cad64ee7157ef277de` with 15 members.
- The pre-change supplement source and stage-23 script are archived in `../archive/supplementary_methods_p3p4_pre_20261028/`.
- The checksum inventory was refreshed after this record. No Git commit, push, publication or DOI deposit was performed.

## Supplementary methods pages 5–8 revision (2026-10-29)

The four-party team reviewed the remainder of the Supplementary Methods, from Selection sensitivity analyses to Evidence navigation and recorded external criteria (pages 5–8). Approved package A corrected one accuracy issue and package B clarified six reproducibility points. No scientific result, estimate, interval, P value, sample size, citation or claim direction was changed, and no analysis script was rerun.

Accuracy (A):

- The replication paragraph now states that `GSE23554 was retained in the locked primary pool, so these six tumours contribute to the primary estimate, and the pooled estimate omitting GSE23554 is reported as a sensitivity analysis (Supplementary Table S3)`. Previously the omission was described only as an alternative, which implied the three-cohort pool excluded GSE23554.

Reproducibility and clarity (B):

- The software paragraph now adds `fgsea 1.34.2` and locates the version records at `environment/locked_software_versions.csv`, `environment/r_package_versions.csv`, `environment/python_requirements.txt` and `environment/sessionInfo/`, replacing the earlier reference to files beside `scripts/`.
- The molecular paragraph now states that the nine enriched pathways were collapsed `before any external data were examined, into four locked axis scores (general proliferation, 289 genes; replication licensing, 33; DNA synthesis, 108; ATR checkpoint, 27) and a replication composite (116 genes) formed from the union of the three replication axes`. This resolves the earlier impression that five independent scores existed.
- The residual-disease paragraph now notes that the 10 mm or less stratum is `a group that includes patients with no macroscopic residual` and that the no-residual versus any-residual split is `a second, overlapping partition`.
- The HGSOC paragraph now refers to `proportional-hazards tests based on scaled Schoenfeld residuals`, avoiding confusion with the Schoenfeld sample-size formula used in the power analysis.
- The cross-cancer paragraph now adds that `the unrestricted bladder set was also fitted for comparison` alongside the treated-only set.
- The tipping analysis now states that the fixed imputed end date was varied for `patients without a plausible recorded end date` and that `recorded plausible dates were retained`.

Layout and verification:

- The supplement remains 31 pages with the same contents map: Methods 3, Results 8, Tables 13, S1 13, S2 14, S3 15, S4 17, S5 18, S6 21, Figures 22, Data 28, Data conventions 28, References 29. The revised sentences fall on pages 5–8; one sentence spans the page 5–6 break and was checked in both fragments.
- The main upload PDF remains 18 pages and the illustrated review copy 21 pages, with pages 1–18 text-identical to the upload; the cover letter remains 2 pages. Stage 21 reports 3,045 main-text words, 3,992 main text plus legends, a 299-word abstract, 46 main and 44 supplementary references, and five display items.
- Stage 21 rebuilds both DOCX files, and the supplementary DOCX carries all seven revisions. Stage 24 validates 138 claims and 16 provenance entries, stage 26 audits 16 formal figures, and stage 27 and `make check` pass.
- Data 5 is not a bundle input and was not rebuilt; its SHA-256 remains `68e8272377a0cfa09cf95ce37021a332611e805bdae6e9cad64ee7157ef277de` with 15 members.
- The pre-change supplement source is archived in `archive/supplementary_methods_p5p8_pre_20261029/`.
- The checksum inventory was refreshed after this record. No Git commit, push, publication or DOI deposit was performed.

### Supplementary results wording harmonisation (2026-10-29)

The same phrase corrected in the HGSOC methods paragraph also appeared once in the Supplementary Results (`Operational HGSOC`, page 10). That sentence now reads `Proportional-hazards tests based on scaled Schoenfeld residuals did not detect a violation (response terms P≥0.78; global P≥0.71)`, so the nomenclature matches the methods and no longer sits adjacent to the Schoenfeld sample-size formula used in the power analysis. Only wording changed; the reported P values, estimates, sample sizes and claim direction are untouched, and no analysis script was rerun.

The supplement remains 31 pages with the same contents map; the revised sentence is on page 10. The main upload PDF remains 18 pages and the review copy 21 pages with pages 1–18 text-identical. Stage 21, 23, 24, 26, 27 and `make check` all pass, and Data 5 keeps its SHA-256 `68e8272377a0cfa09cf95ce37021a332611e805bdae6e9cad64ee7157ef277de`. The pre-change source is archived in `archive/supplementary_results_ph_pre_20261029/`.

### Supplementary Results review revisions (2026-10-29)

Four-party review of `manuscript/source/supplementary.md` lines 77–140 produced thirteen approved revisions. Accuracy items: the concordant clinical-matrix share for CR/PR is now 78–86% to match Table 1 (the former 79% used a denominator that dropped the one discordant patient); the PFI proportional-hazards sentence now names the NCR contrast and gives the four-category P (0.069; 0.18); the general-proliferation difference is labelled as unadjusted with the clinical-adjusted value in parentheses; the single WGCNA module result now states its covariate adjustment, the 10,837-gene network and the absence of the signal at the 8,000- and 5,000-gene thresholds; the HGSOC response-term bound is P≥0.77 (minimum 0.776); the unrestricted bladder analysis promised in the Methods is now reported (n=354); and the external compatibility P value now names general proliferation. Clarity items: Schoenfeld wording is harmonised with the methods, the ΔAIC range is defined as AIC(M3) − AIC(M_PD), the HGSOC diagnosis-origin and fixed 6-month P values are labelled unadjusted with adjusted values, and the treatment-duration sentence gives the Table 1 range. Optional items added the purity-adjusted licensing estimate and split the first Results subsection into two paragraphs.

No estimate, confidence interval, sample size or claim direction changed. The claim-audit regexes for `aic_tie_low` and `aic_tie_high` in `config/manuscript_claims.json` were updated to the new ΔAIC wording so they still bind to `dAIC_M3`; the audit reports 138 claims and 0 failed fields.

The supplement remains 31 pages with the same contents map (Results 8–12, Tables from 13); the main upload PDF remains 18 pages and the review copy 21 pages with pages 1–18 text-identical. Stage 21, 23, 24, 26, 27 and `make check` all pass, and Data 5 keeps its SHA-256 `68e8272377a0cfa09cf95ce37021a332611e805bdae6e9cad64ee7157ef277de`. The pre-change source (SHA-256 `84cddea49e57501c951f19a8822d8860a413ef460cbaf632fbedb0de940d9628`) is archived in `archive/supplementary_results_p8p12_pre_20261029/`.

## Figure and table legend revision (2026-10-29)

Four-party review of the main-manuscript Figure 1–3 and Table 1–2 legends produced one accuracy correction, three presentation reconciliations and seven readability additions (A1–A4, B1–B7). No estimate, confidence limit, P value, C-index, sample size, bootstrap count, test or claim direction changed; no analysis script was rerun and no figure was regenerated. The pre-change `manuscript/source/legends.md` (SHA-256 `1717f08b858c9c155dcca098d03a5f3685f979074b68a99eae65f1228bfbe55a`) is archived in `archive/legends_review_pre_20261029/`.

Accuracy (A):

- Table 2 previously attributed every listed hazard ratio to the CR | PR+SD | PD model. The legend now states that PR, SD and PD versus CR come from the four-category model (M1), NCR versus CR from the CR-versus-NCR model (M3) and PD versus PR+SD from the CR | PR+SD | PD model (M_PD), matching `topo_summary()` in `scripts/18_analyze_selection_regimen_power.R`. M2 is defined as the objective-response coding, and the plateau, objective-response constraint and PD-step likelihood-ratio tests are described with their degrees of freedom.
- Figure 2C now names the four-category model and gives the covariate-complete count (n=408) for the diagnosis setting; Figure 2D lists the settings in the plotted order and states that the 453 labelled patients include the 81 excluded from the landmark cohort.

Presentation and reconciliation (A + B):

- Figure 3A reports the plotted Wald pool interval (1.43–12.62) and states that the Hartung–Knapp–Sidik–Jonkman interval (0.30–59.3) appears with the prediction interval in Table S3, resolving the earlier mismatch between the figure and the supplement.
- Figure 2E and Figure 3C now describe 0.67–1.50 as the pre-specified equivalence margin and state that overlap is not evidence of equivalence; Figure 2E also records that equivalence was not established and that moderate excess mortality for PD versus PR/SD was neither confirmed nor excluded.
- Figure 1 defines M1, M2 and M3 in its abbreviation list; Figure 3B names Harrell's C-index and lists all four strata (CR 47, PR 13, SD 3, PD 6); Figure 3C states that TCGA-OV rows are complete-case except the IPW row and that GSE63885 is the serous, four-class cohort.
- Table 1 now states that the 82 excluded labelled patients comprise one without OS and the 81 removed at the cohort-flow steps, lists the abbreviations used in the table (CR, GDC, IQR, OS, PD, PR, R0, SD, TCGA-CDR, TCGA-OV) and notes that follow-up is not applicable to excluded patients.
- Table 2 additionally reports the bootstrap share definition (1000 resamples; 500 for the platinum–taxane subset), the ΔAIC ordering (M1/M2/M3/M_PD), the AIC-first/BIC-second convention, the operational HGSOC definition, the IPW caveat, the 183-day landmark and the treatment of date scenarios.

### Rebuild and verification

- Stage 21: main text 3,045 words; abstract 299; 46 main and 44 supplementary references; five display items; every hard limit check passes. The advisory `main text + legends` check now reports 4,249 words against 4,000 (it reported 3,999 before this revision) because the legends grew by 250 words (932 → 1,182). This check is excluded from the build's failure condition and the journal limit applies to main text; the overshoot is recorded here rather than resolved by trimming approved content.
- Five stage-24 regex anchors were rebound to the reworded legends (`figure2_c_diagnosis_n`, `figure2_d_diagnosis_n`, `figure2_d_therapy_end_n`, `figure3_a_hksj_interval`, `figure3_b_cv_design`); the values they verify and their tolerances are unchanged. Stage 24 validates 138 claims and 264 fields, including 30 legend rows, with zero failures; stage 26 passes all 16 formal figure files; stage 27 and `make check` pass.
- The main upload PDF remains 18 pages: Figure legends on pages 14–15, Table legends on page 16, Table 1 on 17 and Table 2 on 18. Figure 2's legend now ends at 762.5 pt on page 14, above the footer, and Figure 3's legend fits page 15; neither page overflows. The 21-page illustrated review copy was regenerated, its first 18 pages are text-identical to the upload manuscript, and the supplement remains 31 pages.
- M_PD renders as a subscript in the DOCX and TeX legends; the main DOCX contains no literal `M_PD` and the generated Markdown keeps the literal token for the stage-24 anchors.
- Data 5 was rebuilt because its input manifest and reporting index record `config/manuscript_claims.json` and the legend text. Thirteen of the 15 members are byte-identical; only `input_manifest.json` and `reporting_index.csv` differ. Two consecutive builds give the same bundle at SHA-256 `310dc2951e501147a8d52d63efa5c6e73d24f720b6a526f2391214928fa93ad6`, replacing `68e8272377a0cfa09cf95ce37021a332611e805bdae6e9cad64ee7157ef277de`.
- The 358-entry checksum inventory was refreshed after this record and all 358 entries verify. No Git commit, push, publication or DOI deposit was performed.

## Supplementary methods overview and model-comparison revision (2026-10-29)

Four-party review of the Supplementary Methods from the title and contents through the end of the Methods produced five approved revisions (A1a, A1b, B1, B2, C1). No estimate, confidence interval, P value, sample size, citation or claim direction changed, and no analysis script was rerun. The pre-change source (SHA-256 `5122bc8ea37b8493445c8566e54b3d7a8be02629db5a21ddaefd1b5fd95a6523`) is archived in `archive/supplementary_methods_full_pre_20261029/`.

Accuracy and reproducibility (A1, B1, B2, C1):

- The main-cohort bootstrap sentence now reads `we recorded the lowest-AIC model and whether the plateau and objective-response constraints were rejected at α=0.05`, removing the PD-step constraint from that list. `boot_sel()` in `scripts/17_fit_therapy_end_landmark.R` returns only `plateau_rejected` and `ORR_rejected`, and `bootstrap_model_selection.csv` has no PD-step column; the PD-step rejection share is recorded only by the HGSOC bootstrap in `scripts/19_analyze_hgsoc_sensitivity.R`.
- The HGSOC therapy-end bootstrap now states that it recorded `the lowest-AIC model and rejection of the plateau, objective-response and PD-step constraints`, matching `pd_step_rejected` in script 19.
- The treatment-end-date scenarios now read `Sampling did not condition on individual survival, and the donor distribution was treated as fixed; risk-set membership varied, and actual response-assessment dates could not be reconstructed. These scenarios were summarised descriptively, and pooled intervals or tests across draws were not used for inference.` Script 18 contains pooled-variance code (`T_pd`, `d1_test`), but those quantities are not reported or used for inference, so the earlier wording implied both more and less than was done.
- The molecular cross-validation is now specified as `assessed in 409 patients by 20 repeats of five-fold cross-validation stratified by response (CR versus NCR), fitting logistic-regression models and summarising discrimination by AUC`, matching the design in `scripts/12_integrate_replication_multiomics.R` and `M3_clinical_increment_cv_summary.csv` (n=409).
- `Neoadjuvant chemotherapy was essentially absent by TCGA design` now reads `in this cohort`, because the statement describes the observed TCGA-OV cohort rather than a project eligibility rule.

Unapproved typography repair (disclosed):

- The Software paragraph originally listed three full `environment/...` paths in `\texttt{}`. The resulting line overflowed the page 7 text block by 108.95 pt and clipped the final path in the PDF (`python_requirements.txt` was rendered as `python_requirement`). To remove a visible production defect without changing any file name referenced in the repository, the sentence was rewritten as `The complete version lists (`locked_software_versions.csv`, `r_package_versions.csv` and `python_requirements.txt`, all in the environment directory) and per-analysis sessionInfo records accompany the analysis and build scripts.` This is a presentation-only repair outside the approved A1–C1 content set; it introduces no new file, path or claim. The only residual hyphenation is the ordinary word break `en-\nvironment`.

Layout and verification:

- The supplement remains 31 pages with the same contents map: Methods 3, Results 8, Tables 13, S1 13, S2 14, S3 15, S4 17, S5 18, S6 21, Figures 22, Data 28, Data conventions 28, References 29. The revised sentences fall on pages 4, 5, 5–6 (one sentence continues across the page break) and 7; pages 5 and 7 were rendered and inspected, with no margin overflow or clipped text.
- The main upload PDF remains 18 pages and the illustrated review copy 21 pages, with pages 1–18 text-identical to the upload; the cover letter remains 2 pages. Stage 21 reports 3,045 main-text words, 4,249 main text plus legends (advisory check, excluded from failure), a 299-word abstract, 46 main and 44 supplementary references, and five display items.
- Stage 21 rebuilds the submission DOCX files, and the supplementary DOCX carries all five approved revisions and the typography repair. Stage 24 validates 138 claims and 264 fields with zero failures, stage 26 audits 16 formal figures with zero failures, and stage 27 and `make check` pass.
- All four DOCX files were rewritten by the deterministic stage-22 renderer. A member-by-member comparison of two consecutive builds shows `docProps/core.xml` as the only differing package member in each, so the hash change of the unchanged main manuscript, STROBE checklist and cover-letter documents is metadata-only; the supplementary DOCX additionally carries the five revisions in `word/document.xml`.
- Data 5 is not a bundle input and was not rebuilt; its SHA-256 remains `310dc2951e501147a8d52d63efa5c6e73d24f720b6a526f2391214928fa93ad6` with 15 members.
- The checksum inventory was refreshed after this record and all entries verify. No Git commit, push, publication or DOI deposit was performed.

## Supplementary Results revision (2026-10-29)

A four-party review of the Supplementary Results (11 subsections) checked every estimate, confidence interval, P value, FDR, sample size, event count and model-selection statistic against the result tables. No numerical error was found, and no estimate, interval, P value, FDR, sample size, event count or claim direction changed. Fourteen wording items were approved (A1–A10, B1–B4), comprising 20 replacements; the supplementary source grew by 44 words (5,775 to 5,819). The pre-change source (SHA-256 `d04a836f604aa78acc384634e7d171f1d1396811a8335e853082812597fb0dcb`) is archived in `archive/supplementary_results_review_pre_20261029/`.

Accuracy and attribution (A1–A10):

- A1 corrects the label-source sentence: one CR label is `TCGA-CDR, discordant clinical-matrix label` (Table 1), not `TCGA-CDR alone`. A2 names the main landmark cohort in the label-conflict sensitivity (n=371; `topology_excluding_label_conflict.csv`). A3 attributes the 11% plateau rejection to the primary complete-case bootstrap (`bootstrap_model_selection.csv`, `therapy_end`, 0.111), not the multiple-imputation analysis.
- A4, A5 and A9 label already-unadjusted estimates: the PFI hazard ratios (`topology_by_landmark.csv`, PFI at `therapy_end`), the doublet and fully restricted NCR hazard ratios (`regimen_restriction_topology.csv`), and the LGG and treated bladder hazard ratios (`topology_models_by_set.csv`). A6 states that no HGSOC pairwise comparison met the pre-specified margin, matching all six rows of `hgsoc_noncr_pairwise_equivalence.csv`.
- A7 states that no four-category interaction test was performed (only the NCR interaction was tested) and marks the two residual-disease plateau P values as unadjusted (`0.6794` and `0.3776` in `topology_by_residual_disease.csv`). A8 identifies the GSE63885 estimate as PD versus PR+SD (`os_posthoc_pd_vs_pr_sd.csv`). A10 expresses all locked-score differences in SD units and rewrites the external compatibility sentence; the values are unchanged (`score_response_associations.csv`, `tcga_vs_external_compatibility.csv`).

Clarity (B1–B4):

- B1 distinguishes the seven landmark-based definitions from the eight time-origin definitions. B2 repairs the OS/RMST cross-reference sentence. B3 changes `all four models` to `all four analyses` for the delayed-entry and landmark-covariate fits (`topology_delayed_entry_and_L_adjusted.csv`). B4 removes `existing` and normalises `PD-minus-PR_SD` to `PD versus PR+SD` (`risk_set_audit_summary.csv`).

Audit anchors (disclosed):

- Six claim-audit anchors in `config/manuscript_claims.json` were updated to the approved wording: `residual_le10_plateau_si` (the pattern now permits the optional word `unadjusted`), `label_conflict_si`, `hgsoc_pd_pr_equivalence_si`, and `aic_tie_low`, `aic_tie_high`, `aic_tie_fixed183`. No displayed value, source field, tolerance or claim changed. The first stage-24 run after the text edit failed only because these literals no longer matched; the rerun passed 138 claims and 264 fields with zero failures.

Layout and verification:

- The supplement remains 31 pages with the same contents map: Methods 3–8, Results 8–12, Tables 13, S1 13, S2 14, S3 15, S4 17, S5 18, S6 21, Figures 22, Data 28, Data conventions 28, References 29. The revised sentences render on pages 8–12; italic P formatting was verified in the PDF (`Arial-ItalicMT`) and in the DOCX runs.
- The main upload PDF remains 18 pages and the illustrated review copy 21 pages, with pages 1–18 text-identical to the upload; the cover letter remains 2 pages.
- Stage 24 validates 138 claims and 264 fields with zero failures, stage 26 audits 16 formal figures with zero failures, and stage 27 and `make check` pass.
- A member-by-member comparison of two consecutive stage-21/22 builds shows `docProps/core.xml` as the only differing package member in all four DOCX files. The supplementary DOCX carries the 20 replacements in `word/document.xml`; the unchanged main manuscript, STROBE checklist and cover-letter packages are metadata-only changes.
- Data 5 was regenerated, not because any scientific input changed but because `config/manuscript_claims.json` is one of its recorded inputs. The bundle now has SHA-256 `f03648e0df2770470dd150ff81b41e407a66952b3d38453f9dfa2fe38b46619b` (previously `310dc2951e501147a8d52d63efa5c6e73d24f720b6a526f2391214928fa93ad6`), still with 15 members. Only two members depend on the audit configuration: `input_manifest.json`, which now records the new configuration hash `fe63f62799f239f0ec90b6ce3c6df0f698b6ae04ad4fd57ac0b3cda4865ad835` (the previous `ac91d97e…` no longer appears anywhere in the bundle), and `reporting_index.csv`, which reproduces the five revised anchors. The other 13 members are generated from unchanged result files and Data 1–4, and two consecutive builds give the same bundle hash.
- Following explicit author authorization, the Table 1 row label was changed at display level in `scripts/21_build_esmo_submission.py` from the earlier rendering `First-line systemic treatment duration, days` to `First-line therapy duration, days`, matching the manuscript's `first-line therapy` terminology. The locked CSV (`results/tables/main/` and `results/tables/manuscript/Table1_baseline_main_cohort.csv`) still carries the original `First-line chemotherapy duration, days` label and was not regenerated, so no statistic was recomputed; the display mapping already existed for that reason. The row still occupies a two-line cell on page 17 with identical values (119, 120, 122, 129 and 94 days; P=0.84), and the manuscript remains 18 pages with the review copy at 21 pages and pages 1–18 text-identical. Stage 24 (138 claims, 264 fields), stage 26 (16 figures), stage 27 and `make check` pass after the rebuild, and two consecutive builds again differ only in `docProps/core.xml` across the four DOCX files. The pre-change script is archived in `archive/table1_label_pre_20261029/`.
- The checksum inventory was refreshed after this record and all entries verify. No Git commit, push, publication or DOI deposit was performed.

## Supplementary Table S1 revision (2026-10-29)

A four-party review of Supplementary Table S1 checked every displayed cell in panels (a)–(c) against `TableS1_external_cohorts.csv`, `external_cohort_audit.csv`, `external_survival_by_sample.csv` and `os_cox_noncr_vs_cr.csv`. No numerical error was found. The author then approved the review's wording recommendations, which changed three display strings only; no count, event number, percentage, median or P value changed, no analysis script was rerun, and the locked `TableS1_external_cohorts.csv` was not regenerated. The pre-change script (SHA-256 `72a038dbfa51b0fc9c4c940f47c509eff763847ee1adfdaf1b1f02aca84fb5bd`) is archived in `archive/tableS1_review_pre_20261029/`.

Approved display revisions:

- A1 replaces the panel descriptors `(a) Response-defined cohort characteristics before the landmark. (b) Source-to-landmark counts.` with `(a) Response-defined cohort characteristics and OS events counted from diagnosis. (b) Source-sample-to-landmark counts at the 183-day landmark.` The earlier wording did not say that the OS-event column is counted from diagnosis, while `os_cox_noncr_vs_cr.csv` uses `landmark_days=0` (62, 14 and 31 events), and it did not state the 183-day origin of the flow counts.
- B1 renames the last panel (b) header from `Deaths` to `Deaths after landmark`, because those counts (61, 13 and 30) are deaths occurring after the landmark, not all recorded deaths; panel (a) keeps the from-diagnosis event counts.
- A2 adds `Deaths in (b) are counted after the landmark. Optimal debulking is n/N among patients with a recorded debulking status, and a dash (–) marks a category that was not recorded.` The debulking fractions are computed within the response-labelled subset (13/27 and 18/44, not 13/28 and 18/45), and the dash was previously undefined.

Layout and verification:

- The supplement remains 31 pages with an unchanged contents map (Methods 3–8, Results 8–12, Tables 13, S1 13, S2 14, S3 15, S4 17, S5 18, S6 21, Figures 22, Data 28, Data conventions 28, References 29). Table S1 still occupies one portrait page 13; the new header wraps to two lines inside its column, the headers and values of panel (b) share the same left edge, and the table ends at 669.7 pt on the page, well inside the text block. Page 13 was rendered and inspected, and Table S2 still begins on page 14.
- The new caption and header appear in the supplementary Markdown, LaTeX and DOCX (`word/document.xml`); the removed sentences and the bare `Deaths` header no longer appear in the supplementary sources.
- The main upload PDF remains 18 pages and the illustrated review copy 21 pages, with pages 1–18 text-identical to the upload; the cover letter remains 2 pages. Main-text word count (3,045), abstract (299 words), references (46 main, 44 supplementary) and display items (five) are unchanged.
- Stages 21/22/23 rebuilt the submission files; stage 24 validates 138 claims and 264 fields with zero failures, stage 26 audits 16 figures with zero failures, and stage 27 and `make check` pass.
- Data 5 was not rebuilt because `config/manuscript_claims.json` was not modified in this revision; its SHA-256 remains `f03648e0df2770470dd150ff81b41e407a66952b3d38453f9dfa2fe38b46619b` with 15 members.
- The checksum inventory was refreshed after this record and all entries verify. No Git commit, push, publication or DOI deposit was performed.

## Supplementary Table S2 revision (2026-10-29)

A four-party review of Supplementary Table S2 checked every displayed cell in panels (a)–(b) against `TableS2a_hgsoc_cohort_flow.csv` and `TableS2b_hgsoc_topology.csv`, and checked the caption against the model definitions in `scripts/19_analyze_hgsoc_sensitivity.R` and the Supplementary Results. No numerical error was found: all ten setting × adjustment rows, the five hazard ratios with 95% CIs, the three constraint tests and the Best AIC/BIC labels match the locked CSVs, and the response counts in each panel (a) row sum to its total (454, 402 and 334). No estimate, interval, P value, sample size, event count or claim direction changed, no analysis script was rerun, and the locked CSVs were not regenerated. The pre-change script (SHA-256 `7eeac582d9918b51066587d2e4095a6c321e29d81a1bfacf86d89fe06320d0c4`) is archived in `archive/tableS2_review_pre_20261029/`.

Approved revisions:

- The caption grew from 49 to 259 words. It now states the nested cohort sizes (454 labelled; 402 operational HGSOC, of whom 401 have an OS time; 334 beyond the landmark) and notes that the two Main TCGA-OV rows and the unadjusted HGSOC therapy-end row repeat Table 2, with the 372-patient main landmark cohort shown in Figure 1A. It distinguishes the four HGSOC settings by eligibility and time origin, including the 60–365-day acceptance window for the recorded end of first-line therapy, and explains that the two n=334 settings contain the same patients but differ in whether pre-landmark person-time is retained. It defines n and Events, states that adjusted models are complete-case for age (per 10 years), stage and residual disease, maps each hazard-ratio column to M1, M3 and M_PD, and defines the plateau, ORR and PD-step likelihood-ratio tests (2, 2 and 1 df), noting that ORR P is the objective-response constraint rather than a test of the response rate. It also defines Best AIC/BIC and warns that differences below 1 do not distinguish models.
- Four P cells now carry three decimals to match the Supplementary Results: plateau 0.014926 is shown as `0.015` (was `0.01`), plateau 0.045072 as `0.045` (was `0.05`), PD-step 0.013081 as `0.013` (was `0.01`), and the unadjusted fixed 6-month PD-step 0.044509 as `0.045` (was `0.04`). This uses a table-local `fp3()` helper in `scripts/21_build_esmo_submission.py`; the shared `fp()` formatter is unchanged, so Tables 2 and S3–S6 are unaffected. No other P value changed.
- The panel (a) header `Stage` became `Cohort`, and the operational HGSOC definition is displayed as `grade G2–G4, FIGO stage III–IV` instead of `grade G2-G4, FIGO III-IV`. Both are display-level changes; the locked CSV retains its original strings.

The author delegated four further optional items to the assistant. Two were implemented:

- The main-text citation no longer conflates the unadjusted and adjusted estimates. It now reads `(ΔAIC 0.03; unadjusted estimates in Table 2 and adjusted estimates in Supplementary Table S2; Figure S2)`, renders on main PDF page 7, and adds 7 words (3,045 → 3,052). Only prose changed; the claim audit still passes 138 claims and 264 fields. The pre-change source is archived at `archive/tableS2_options_pre_20261029/methods_results.md` (SHA-256 `b75db33d7dbcc029e66188517ec4fc6ec44efa41f1eaceb808931f1d9e4a21ff`).
- Supplementary Methods now states, immediately after the PD-step test definition, `P values were not adjusted for multiple comparisons; post hoc and exploratory analyses are interpreted descriptively.` It renders on supplement page 4 and leaves the surrounding definitions intact. The pre-change source is archived at `archive/tableS2_options_pre_20261029/supplementary.md` (SHA-256 `96f4bb1d6ab730d2f91a3c6bc762f0cd96ecba47be8cff4bb8ad59197b2cfe69`).

Two were deliberately not implemented. (A) Hanging indents for wrapped continuation lines in panel (b): only 3 of the 10 rows wrap, the fragments sit under repeated setting labels, and the caption now defines every column; a cell-level hanging indent would require TeX that the DOCX pipeline cannot mirror, so the DOCX and PDF would diverge. (D) Removing the short vertical rule at the right edge of landscape pages: inspection of the rendered page and the LaTeX page style shows this is the rotated page-header rule, identical in function to the rule on portrait pages, not a stray table border; removing it for S2–S5 would make landscape pages inconsistent with the rest of the supplement.

Layout and verification:

- The supplement remains 31 pages with an unchanged contents map (Methods 3–8, Results 8–12, Tables 13, S1 13, S2 14, S3 15, S4 17, S5 18, S6 21, Figures 22, Data 28, Data conventions 28, References 29). Table S2 still occupies one landscape page 14: the caption runs to 13 lines and ends at 95.1 mm, the table spans 10.0–286.5 mm horizontally and ends at 191.4 mm, 18.6 mm above the page edge, with no overlap and no spill onto page 15. Page 14 was rendered and inspected.
- The new caption, header and four P values appear in the supplementary Markdown, LaTeX and DOCX (`word/document.xml`); the previous caption and the bare `Stage` header no longer appear in the supplementary sources.
- The main upload PDF remains 18 pages and the illustrated review copy 21 pages, with pages 1–18 text-identical to the upload; the cover letter remains 2 pages. Main Table 1 remains on page 17 and Table 2 on page 18. Main-text word count is 3,052 (3,045 before the citation rewording), abstract 299 words, references 46 main and 44 supplementary, and display items five.
- Stages 21/22/23 rebuilt the submission files after the Table S2 and text edits; stage 24 validates 138 claims and 264 fields with zero failures, stage 26 audits 16 figures with zero failures, and stage 27 and `make check` pass.
- Data 5 was not rebuilt because `config/manuscript_claims.json` was not modified in this revision; its SHA-256 remains `f03648e0df2770470dd150ff81b41e407a66952b3d38453f9dfa2fe38b46619b` with 15 members.
- A member-by-member comparison of two consecutive stage-21/22 builds, repeated after the citation and Methods edits, shows `docProps/core.xml` as the only differing package member in all four DOCX files; the supplementary DOCX carries the new caption and cells in `word/document.xml`, while the main manuscript, STROBE checklist and cover-letter packages are metadata-only changes.
- The checksum inventory was refreshed after this record and all entries verify. No Git commit, push, publication or DOI deposit was performed.

## Supplementary Table S3 revision (2026-10-30)

A four-party review of Supplementary Table S3 checked every displayed cell in panels (a)–(e) against `TableS3a_noncr_by_residual_disease.csv`, `TableS3a_noncr_residual_interaction.csv`, `TableS3b_topology_by_residual_disease.csv`, `TableS3c_topology_delayed_entry_and_L_adjusted.csv`, `TableS3d_external_leave_one_out.csv` and `TableS3e_external_small_sample.csv`; checked the denominators against `SupplementaryData1_TCGA_OV_cases.csv` (372 landmark patients, 28 without a residual category, one further without stage); and checked the interaction model against `scripts/17_fit_therapy_end_landmark.R`. No numerical error was found. No estimate, interval, P value, sample size, event count or claim direction changed, no model was refitted, and the locked CSVs were not modified. The pre-change files are archived in `archive/tableS3_review_pre_20261030/`: `21_build_esmo_submission.py` (SHA-256 `2e1676e0cac647ed7a1cf9e9e58262ca6c699f3d0576b5a371e4496eef59eaa3`), `23_build_submission_latex.py` (`011713d0ed6c07bcfba2016551363ec4a035c723af85359415fc83d185d7b429`), `submission_profile.json` (`fa14eef7604ffca202029430451aceb22c5f7280a0ef7677fc9a714ff63e6bca`) and `supplementary.md` (`a91818a9cde662c9d91b369007250ddc2249d7cbdfa98a7c0d1c44b66b9ecbc3`).

Approved revisions (P0 + P1):

- The caption grew to 304 words and now states that the two residual-disease partitions overlap: ≤10 mm includes the 77 patients with no macroscopic residual (246 + 98 = 344; 77 + 267 = 344), and `Any` comprises 1–10 mm and >10 mm. It records that 344 of 372 landmark patients had a recorded residual category (343 complete-case for age and stage) and that the 28 without one enter only panel (c), whose adjusted n is 343 because one further patient lacks stage.
- It explains that the interaction HR ratio comes from a model with a common baseline and is not the ratio of the separately fitted stratum-specific HRs (1.82 versus 3.54/1.54 = 2.30), and that its P value is a 1-df likelihood-ratio test.
- Panel (b) now cross-references Table S2 for the model codes, constraint tests and ΔAIC, states that P values are unadjusted, and records that Best BIC agreed with Best AIC in every tested row.
- Panel (c) defines L as months from diagnosis to the end of first-line therapy and states that the delayed-entry models address left truncation only.
- Panel (d) states that each row omits one cohort and pools the remaining k, that Events counts deaths in the remaining cohorts (so cohorts recur across rows), that P comes from the re-pooled estimate, and that omitting GSE23554 also removes the six tumours sharing identifiers with PMID19318476 (Table S1).
- Panel (e) now describes a pooled Firth-penalised Cox estimate (not per-cohort Firth estimates) and states that PMID17290060 is not among the three pooled cohorts and was excluded because its source publication was retracted. The caption previously referred to per-cohort Firth estimates that panel (e) does not display.
- The split label `None vs any macroscopic` became `R0 vs any`, and the stratum labels `None`/`Any macroscopic residual` became `R0`/`Any`; these are display-level changes and the CSVs retain their original strings.
- Panel (b) constraint P values use the table-local `fp3()` rule already introduced for Table S2. Four cells gained a third decimal (`0.03`→`0.028`, `0.05`→`0.046`, `0.01`→`0.013`, `0.04`→`0.040`); all values ≥0.1 remain at two decimals. The Supplementary Results objective-response P was `0.0085`, which disagreed with the table's `0.008`; the text now reads `0.008`. The corresponding claim entry in `config/manuscript_claims.json` (`residual_gt10_tests_si`) changed only its display precision (4→3 decimals) and tolerance (5e-5→5e-4) for `ORR_p`.
- Column fractions for panels (a)–(e) are now declared in `config/submission_profile.json` (`supplementary_table_s3_a_fractions` … `_e_fractions`) and applied by `scripts/23_build_submission_latex.py` with length, positivity and unit-sum checks. Widening the n column in (b) and the model/adjustment columns in (c) removed every wrapped data cell; panel (a) also gained a visible gutter after the split label.

Layout and verification:

- The supplement remains 31 pages with an unchanged contents map (Methods 3–8, Results 8–12, Tables 13, S1 13, S2 14, S3 15–16, S4 17, S5 18–20, S6 21, Figures 22, Data 28, Data conventions 28, References 29). Table S3 still occupies landscape pages 15–16: the caption runs to 14 lines and ends at 84.2 mm, panels (a) and (b) span 87.2–193.5 mm on page 15 (16.5 mm above the page edge) with every row on one line, and panels (c)–(e) span 11.5–118.0 mm on page 16. There is no overlap, no wrapped data cell and no spill onto page 17; both pages were rendered and inspected.
- The new caption, labels and P values appear in the supplementary Markdown, LaTeX and DOCX (`word/document.xml`); `None vs any macroscopic` and `0.0085` no longer appear in the submission sources.
- The main upload PDF remains 18 pages and the illustrated review copy 21 pages, with pages 1–18 text-identical to the upload; the cover letter remains 2 pages. Main-text word count is 3,052, abstract 299 words, references 46 main and 44 supplementary, and display items five.
- Stages 21/22/23 rebuilt the submission files; stage 24 validates 138 claims and 264 fields with zero failures, stage 26 audits 16 figures with zero failures, and stage 27 and `make check` pass.
- Data 5 was rebuilt because `config/manuscript_claims.json` changed; it still has 15 members and its SHA-256 is `fdb0b6fac679d1456a7cd36d562cd481cf5567217aadb201c8ff9c1ffb73172c`. Two consecutive stage-21 builds produce identical member contents and identical archive bytes.
- A member-by-member comparison of two consecutive stage-21 builds shows `docProps/core.xml` as the only differing package member in the supplementary DOCX. No Git commit, push, publication or DOI deposit was performed.

## Supplementary Table S4 revision (2026-10-30)

A four-party review of Supplementary Table S4 checked all 23 cancer rows and 15 columns against `results/tables/manuscript/TableS4_pancancer_label_audit.csv`, recomputed the row and column sums (5,377 labelled patients), re-derived the E1 power rule (PR ≥ 10, SD ≥ 10, PD ≥ 10, non-CR ≥ 30, OS events ≥ 30) and the E2 rule (`pct_nonsurgical` ≥ 0.5), and compared the four R0 pairs quoted in the Results (98/58, 84/46, 97/82, 98/84) with the two Xena-derived R0 columns. No numerical error was found; no count, percentage, event number or eligibility call changed, no analysis script was rerun, and the locked CSV was not regenerated. The review identified presentation defects: a 61-word caption that was not self-sufficient (Table S2 has 259 words and S3 304); R0 columns that use a different denominator from the other percentage columns without saying so; a Xena response field used to group CR versus NCR without saying so; undefined `Eligible`, `OS events`, `% therapy end known` and `% non-surgical first-line`; a repository file path in a journal caption; and a main-text phrase that conflicted with LGG's `Eligible = Yes`. The two CSV copies (`results/tables/manuscript/` and `results/tables/supplementary/`) were byte-identical (SHA-256 `99c15fc0f90036a7b8892f575ad941cf86f8485777b0673056dadb2ad9b4001a`), and the Data 5 member matched them. Pre-change files are archived in `archive/tableS4_review_pre_20261030/`: `21_build_esmo_submission.py` (SHA-256 `36b39db0722002c5890d630966753d7ca4d68e83a4c1edc1775fb33cfca88867`), `23_build_submission_latex.py` (`50fa9ecc36a49d6dacbbda814f3e0f7e460b78de3fef7527fa7ad2aded73f8b1`), `submission_profile.json` (`087616b5ba9e32fdbbe6b438b45b05542c34aca3db313bd44025eb7fcff8c685`) and `methods_results.md` (`934a1acfaad5e44d95f06cced8b35fdee14c717971db42fbf0693deec3b1d746`).

Approved revisions:

- The caption grew from 61 to 126 words and now states that percentages use the labelled patients as denominator except the two R0 columns, which come from the UCSC Xena clinical matrices, are restricted to patients with a recorded R status (counts in the CSV) and group CR versus NCR by the Xena response field. It defines `OS events`, `% therapy end known`, `% non-surgical first-line` (systemic therapy or radiotherapy starting between 120 days before and 365 days after diagnosis, the E2 criterion), `E1` (power rule) and `Eligible` (both rules met), and defines the dash. It replaces the repository path with the Supplementary Data 5 filename and states that agreement between first-course and regimen-level labels and all further columns are in that file.
- The table body font fell from 13.25/15.1 pt to 12.0/13.7 pt (`supplementary_table_fonts.S4` in `config/submission_profile.json`), with column separation unchanged at 1.0 pt. This buys the caption its six lines; no column fraction, header break or cell string changed.
- The main text now reads `whereas only ovarian cancer and lower-grade glioma (LGG) met the four-state eligibility criteria`, removing `and, partly,` and naming the criteria. The previous phrasing implied that LGG only partly met the criteria although its `Eligible` cell is `Yes`. The edit is net 0 words, so the main text remains 3,052 words, and it renders on main PDF page 7.
- `scripts/21_build_esmo_submission.py` now asserts byte equality of the two Table S4 CSV copies before reading either, so a divergent manuscript/supplementary pair fails the build instead of silently producing inconsistent tables.
- `scripts/23_build_submission_latex.py` now applies the S4 header breaks to the `\toprule`–`\midrule` header row only. The longer caption names several header strings (`OS events`, `% therapy end known`, `% non-surgical first-line`), so the previous whole-table `count(header) != 1` check would abort the LaTeX build. The Markdown pipe table that feeds the DOCX is untouched, so both formats keep the same header text.

Layout and verification:

- The supplement remains 31 pages with an unchanged contents map (Methods 3–8, Results 8–12, Tables 13, S1 13, S2 14, S3 15–16, S4 17, S5 18–20, S6 21, Figures 22, Data 28, Data conventions 28, References 29). Table S4 still occupies one landscape page 17: the caption runs to six lines and ends at 48.2 mm, the header spans 53.8–63.4 mm and the body 66.9–189.7 mm, leaving about 20 mm to the page edge. The rendered body font measures 11.96 pt. There is no overlap and no spill onto page 18, which still opens Table S5.
- The new caption, font size and main-text sentence appear in the supplementary Markdown, LaTeX and DOCX; the previous 61-word caption and `and, partly,` no longer appear in the submission sources. The TeX contains `\fontsize{12.0}{13.7}` for Table S4.
- The main upload PDF remains 18 pages and the illustrated review copy 21 pages, with pages 1–18 text-identical to the upload; the cover letter remains 2 pages. Abstract (299 words), references (46 main, 44 supplementary) and display items (five) are unchanged.
- Stages 21/22/23 rebuilt the submission files; stage 24 validates 138 claims and 264 fields with zero failures, stage 26 audits 16 figures with zero failures, and stage 27 and `make check` pass.
- Data 5 was rebuilt by stage 21 because the recomputed files feed its index; it still has 15 members and its SHA-256 is now `e657284a70589e13c533e7fe0dc31dd52416e947356614072f9611fe0741d580`. The bundled Table S4 member is unchanged at `99c15fc0f90036a7b8892f575ad941cf86f8485777b0673056dadb2ad9b4001a`.
- Two consecutive stage-21 builds differ only in `docProps/core.xml` in all four DOCX packages; `word/document.xml` is byte-identical, and the PDFs are unchanged.
- The `make manuscript` log retains a pre-existing conservative flag, `FAIL main text + legends 4256 ≤ 4000`, because that check adds figure and table legends to the main-text budget. The submission limit applies to the main text alone, which is 3,052 words; the flag is not a regression from this revision (the Table S4 edit is net 0 words, and the earlier 3,995 entry in an older log predates several intervening additions). It is recorded here rather than silently suppressed.
- The checksum inventory was refreshed after this record and all entries verify. No Git commit, push, publication or DOI deposit was performed.

## Supplementary Table S5 revision (2026-10-30)

A four-party review of Supplementary Table S5 checked all 16 origin × adjustment rows in panels (a) and (b), the two RMST horizons and at-risk counts in panel (c), the six existing risk sets in panel (d) and the nine hierarchical PFI exclusions in panel (e) against `results/tables/supplementary/TableS5_landmark_OS_results.csv`, `results/tables/ov_therapy_end_landmark/rmst_therapy_end.csv`, `number_at_risk_therapy_end.csv` and `risk_set_audit_summary.csv`, and against the byte-identical Data 5 members. Denominators reconcile exactly: 453 diagnosis (454 labelled minus one patient without an OS time), 426/404/386 at the fixed 183/270/365-day origins, 372/343 at the therapy-end landmark, and 454 − 90 = 364 PFI patients with a 337 complete-case adjusted subset; panel (e) sums to 90 in every response column. No estimate, confidence interval, P value, count or eligibility call was wrong, and no analysis was rerun. The review found one display defect and several caption defects. Pre-change `scripts/21_build_esmo_submission.py` is archived in `archive/tableS5_review_pre_20261030/` (SHA-256 `c07e0a8226317b4850959dbda3386274a58038b76b346aca60db97fe38abc160`); scripts 23, the submission profile and all result CSVs were not modified.

Approved revisions (`P0+P1`, display only):

- **P0, panel (c).** The shared `hr()` formatter joined negative bounds with an en dash, producing `-10.44–-5.28`; Pandoc/TeX turned `–-` into an em dash and dropped the upper bound's minus sign, so the PDF read `-7.86 (-10.44—5.28)` and `-18.01 (-22.09—13.92)`. A table-local `sdiff()` formatter now writes the Unicode minus sign, joins the interval with `to` and rounds to one decimal, matching the adjacent RMST columns and the Results text: `−7.9 (−10.4 to −5.3)` and `−18.0 (−22.1 to −13.9)`. The underlying estimates are unchanged.
- **Panel (d) labels.** The internal metric codes `os main`, `os adjusted`, `ncr unadjusted`, `ncr adjusted`, `pfi all` and `pfi adjusted` became `Main analysis`, `NCR only` and `Full PFI`, with the endpoint and adjustment retained in their own columns; the header is now `Existing model`.
- **Panel (e) header.** `Ordered PFI exclusion reason` became `PFI exclusion reason (in order)`; the row order is unchanged.
- **Caption.** Growth from 171 to 325 words adds the cohort distinction (453 diagnosis, 426/404/386 fixed, 372/343 therapy end), the PFI base and total (454 labelled, 90 excluded, 364 unadjusted and 337 adjusted), the Events definition, the unadjusted status of all P values, and a cross-reference defining M1–M3, M_PD and the three constraint tests in Table S2; it retains the caution that only one NCR patient remains at risk at 60 months. It removes the repository path, states that no model was refitted and that no estimate, interval or P value was recalculated, and points to `TableS5_landmark_OS_results.csv` in Supplementary Data 5. The earlier `existing sensitivity results` wording was inaccurate because the therapy-end rows are the main analysis.

Layout and verification:

- The supplement remains 31 pages with an unchanged contents map (Methods 3–8, Results 8–12, Tables 13, S1 13, S2 14, S3 15–16, S4 17, S5 18–20, S6 21, Figures 22, Data 28, Data conventions 28, References 29). Table S5 still occupies landscape pages 18–20. On page 18 the caption runs to 12 lines and ends at 76.0 mm, and panel (a) spans 89.5–176.0 mm, leaving 34.0 mm to the page edge. Page 19 ends at 194.4 mm (15.6 mm margin) and page 20 at 176.0 mm (34.0 mm margin). There is no overlap and no spill onto page 21, which still opens Table S6.
- The rendered PDF, DOCX and Markdown all show `−7.9 (−10.4 to −5.3)` and `−18.0 (−22.1 to −13.9)`; the TeX contains no `---` sequence and the previous `–-` strings are absent. Panel (d) and (e) headers and labels are identical across the three formats.
- The main upload PDF remains 18 pages and the illustrated review copy 21 pages, with pages 1–18 text-identical to the upload; the cover letter remains 2 pages. Main text (3,052 words), abstract (299), references (46 main, 44 supplementary) and display items (five) are unchanged.
- Stages 21/22/23 rebuilt the submission files; stage 24 validates 138 claims and 264 fields with zero failures, stage 26 (run with `/opt/homebrew/bin/python3.10`) audits 16 figures with zero failures, and stage 27 and `make check` pass.
- The four result CSVs are unchanged: Table S5 `27f1b323e2d47730bfe86bacdfe0e70c59bb21b37c87810559844d24fe9461e2`, risk-set summary `34c50117f2a968c8e5b35c15ccb46e36d845ec2760a31b4b816b38ecda851c50`, RMST `d2bda6f79194baa7d5a94383038eb33cf664a0b0ecfa5aeb029dc91943f1065e`, at-risk `0a8a8fbe43427b66ac7aa93bc88ebfbd0b30b6e762f0747a59331cf17bf29e7b`. Data 5 still has 15 members and its SHA-256 is unchanged at `e657284a70589e13c533e7fe0dc31dd52416e947356614072f9611fe0741d580`; its Table S5 member matches the repository CSV. Stage 21 was the last writer.
- The `make manuscript` log retains the pre-existing conservative flag, `FAIL main text + legends 4256 ≤ 4000`, because that check adds figure and table legends to the main-text budget; the submission limit applies to the main text alone (3,052 words), and the flag is not a regression from this display-only revision.
- Table S6 uses the same shared `hr()` formatter but none of its intervals has a negative upper bound, so its rendered values were checked and are correct; its separate repository path and caption are deferred to the S6 review. No Git commit, push, publication or DOI deposit was performed.

## Supplementary Table S6 revision (2026-10-30)

A four-party review of Supplementary Table S6 checked the nine pooled score–response contrasts against `results/tables/supplementary/TableS6_primary_external_scores.csv` and its byte-identical Data 5 member; checked the 143 patients with a pretreatment score and a response label (70 in GSE63885, 28 in GSE23554, 45 in GSE30161) and the 138 patients in the landmark survival analyses (69, 25 and 44 at 183 days) against `per_cohort_noncr_minus_cr_estimates.csv` and `os_cox_noncr_vs_cr.csv`; recounted the negative-direction cohorts for every row in the three cohorts; and compared the REML, HKSJ, I² and prediction-interval fields with an independent `metafor` recomputation, which reproduced all nine rows exactly. Estimated heterogeneity is zero in every row, so each prediction interval equals its REML interval; every interval, including the HKSJ interval, includes zero. No estimate, interval, P value, count or claim direction changed, no model was refitted, and the locked CSV was not modified. Pre-change files are archived in `archive/tableS6_review_pre_20261030/`: `21_build_esmo_submission.py` (SHA-256 `f3e97908d6d57e0379399b295ca6046bf0a4f0280736b0fd57e238ddd516c21a`), `23_build_submission_latex.py` (`aad10a811281b55cb8e61b4a36ecd3c34bf63d767cafb18a074a5e3dc13cb2c3`), `submission_profile.json` (`7f9b765498c3181fc339cb0bcbdb0d51eda71a639599d9f36b53b79b6d8bdce3`) and `ESMO_Open_supplementary_appendix.md` (`3dd2da4afe281574c50a28edc9dab7fedee18938d74d842de475c71b46a860b6`).

Approved revisions (`P0+P1`, display and caption only):

- **P0, survival framing.** The old caption said every row used the cohorts "before the survival landmark" and that the score denominator was "distinct from the external survival denominator", without giving either denominator. The table uses response only and no survival outcome. The caption now states that all rows use the same 143 patients (70, 28 and 45), that 138 of these patients were also in the landmark survival analyses, that the score and survival denominators therefore differ, and that no survival outcome is used in this table.
- **P0, source pointer.** The old caption directed readers to `TableS6_primary_external_scores.csv` for per-cohort results, but that file contains pooled estimates only; the per-cohort estimates are in Data 5 (`per_cohort_noncr_minus_cr_estimates.csv`). The caption now points only to Supplementary Data 5, and the repository path is removed from the journal-facing text.
- **Row labels.** Internal identifiers became reader-facing labels: `general proliferation` → `General proliferation`; `dna synthesis` → `DNA synthesis`; `atr checkpoint` → `ATR checkpoint`; `robust nine composite` → `Nine-pathway composite`; `MKI67 expression z` → `MKI67 mRNA (z score)`; `licensing given proliferation` → `Replication licensing` with adjustment `General proliferation`; `response only` → `None`. Stage 21 asserts that the label maps cover every value in the CSV, so a future identifier cannot silently pass through.
- **Statistical disclosure.** The caption states the direction and units (NCR minus CR, within-cohort SD, negative values mean lower in NCR), that the five locked scores were defined before the external data were examined, that the other four rows are exploratory, that one estimate per cohort was pooled by inverse-variance REML, that response was recorded after first-line therapy with cohort-specific definitions (Table S1), that no model included age, stage or residual disease, that P values are unadjusted for the nine comparisons, that every interval includes zero, and that the HKSJ interval is a sensitivity interval whose width can differ substantially from the REML interval with three cohorts.
- **Redundant column.** The `k / n` column repeated `3 / 143` in every row and was removed; the caption now carries k and the denominators. The REML and HKSJ columns, I² and the prediction interval are retained.
- **Dash-safe formatting.** A two-decimal `sdiff2()`/`srange()` pair writes the Unicode minus sign and joins intervals with `to`, matching the one-decimal `sdiff()` introduced for Table S5; the old `hr()` formatter is no longer used by S6. This removes the latent `–-` to `---` em-dash collision even though no S6 upper bound is currently negative.

Layout and verification:

- The supplement remains 31 pages with an unchanged contents map (Methods 3–8, Results 8–12, Tables 13, S1 13, S2 14, S3 15–16, S4 17, S5 18–20, S6 21, Figures 22, Data 28, Data conventions 28, References 29). Table S6 still occupies one landscape page 21. The caption runs to 14 lines; the table starts below it and ends at 160.3 mm, leaving 49.7 mm of the 210 mm block free. Nine content-driven columns at 12.0 pt with 2.5 pt separation give widths of 51.1, 44.7, 22.2, 45.8, 16.9, 30.8, 16.9, 12.1 and 28.6 mm; every body cell stays on one line, the smallest gap between a cell and the next column is 2.8 mm (REML P to HKSJ), and the widest value ends 5.5 mm inside the right rule. The approved 11.5 pt fallback was not needed. Page 21 was rendered and inspected.
- Header cells are centred vertically within their rows in all six supplementary tables (138 header cells). Pandoc wraps each header cell in a bottom-aligned minipage, so a single-line header sat level with the second line of its two-line neighbours. `centre_table_headers()` in `scripts/23_build_submission_latex.py` rewrites only the cells between each table's `\toprule` and header `\midrule`, asserts that every bottom-aligned minipage lies inside a header, and leaves the Markdown, DOCX and journal-facing text untouched; the DOCX already set `w:vAlign` to centre on every cell. Measured on the rebuilt PDF, single-line and two-line header centres agree within 0.3 pt: on S6 the header band spans 94.1–106.9 mm with single-line ink at 99.3–102.4 mm against two-line ink at 95.6–105.5 mm; on S4 the single-line headers sit at 166.0–167.3 pt against the 167.3 pt centre of "OS events"; on S1 the "Cohort" centre is 296.7 pt against 296.0 pt for "Median recorded OS time, months". The S4 control shows the top rule and header ink unmoved (1.5 mm top clearance, 1.3 mm to the header rule) and only the header rule and body 0.76 mm higher; no table changed page, and the supplement remains 31 pages with S1 13, S2 14, S3 15–16, S4 17, S5 18–20 and S6 21.
- `config/submission_profile.json` now holds nine S6 fractions summing to 1 and an S6 body size of 12.0/14.4 pt with 2.5 pt column separation. `scripts/23_build_submission_latex.py` validates nine equal starting fractions, inserts the five two-line header breaks only in the generated LaTeX, and documents the measured layout; `scripts/27_validate_repository_structure.py` now requires nine S6 fractions.
- The Markdown, TeX, DOCX and PDF carry the same nine-column header, the same nine rows and the same caption. The DOCX table has 9 columns and 10 rows (one header row), and its cells match the CSV-derived strings exactly; the PDF text contains every cell string. The caption is present in all four formats; PDF text extraction renders its semicolons as U+037E, the same glyph-mapping artefact seen elsewhere in the document, and the rendered page shows ordinary semicolons.
- The main upload PDF remains 18 pages and the illustrated review copy 21 pages, with pages 1–18 text-identical to the upload; the cover letter remains 2 pages. Main text (3,052 words), abstract (299), references (46 main, 44 supplementary) and display items (five) are unchanged.
- Stages 21/22/23 rebuilt the submission files; stage 24 validates 138 claims and 264 fields with zero failures, stage 26 (run with `/opt/homebrew/bin/python3.10`) audits 16 figures with zero failures, and stage 27 and `make check` pass.
- The Table S6 CSV is unchanged at `0c90cd62b8f2587dd4975e78a600e2f18be8401dc2fdc87ccf9238b1a3907f4b`. Data 5 has 15 members; its bundled Table S6 member matches this CSV byte for byte, and all 15 member hashes were identical across two consecutive stage-21 runs. The bundle's own SHA-256 is `86534b3097f52338dbf3920924bc8ab5fef035d1c1f45e55e19d202f66d5b4f2`; it varies between runs only through ZIP entry timestamps. Stage 21 was the last writer. The rebuilt supplementary files are `ESMO_Open_supplementary_appendix.md` `afd6212d17a1153dc69aa64ecff8d73cbccf7f91b7499d0f33c0bff7da1bacfb` (unchanged by the header-centring edit), `.tex` `5733ae3dd9191af5c2b6735f224a2ec75375090274cfe504321d7996d78e16de` and `.pdf` `59514ea369cc9adee2019ae0e67813e97c14fdf1fe3c12eb9821a44107a6aaee`; the DOCX is unchanged at `6c46b2b5654e94228265d19934c3f37e814b718be7f9276d4d67341b914f3d77` apart from `docProps/core.xml` timestamps in any future rebuild.
- The `make manuscript` log retains the pre-existing conservative flag, `FAIL main text + legends 4256 ≤ 4000`, because that check adds figure and table legends to the main-text budget; the submission limit applies to the main text alone (3,052 words), and the flag is not a regression from this display-only revision. No Git commit, push, publication or DOI deposit was performed.

## Figure S1 review: panel C legend and caption clarification (2026-10-30)

A second four-party review of Supplementary Figure S1 (clinical epidemiology, statistics, publishing, information design) rechecked all nine forest rows, the seven tipping points and the twelve power curves against the locked CSVs and the extracted figure text. No P0 defect was found: every plotted value, interval, axis scale and count reproduced the source, and the six caption claim anchors still matched. The author approved the full P1 package, full caption clarification, and retaining upright `P` across the figure set.

Approved changes (display and prose only):

- **Panel C legend.** The log-scale gridlines ran through the `0.1`, `0.2` and `0.3` labels at the upper right. The legend now has an opaque white panel and white keys, so the grid stops at the legend edge. Script 18 was rerun; all twelve `results/tables/ov_selection_regimen_power/` CSVs are byte-identical, the ten-row source has the same 68 text spans in the same positions, and only the legend region changed. The source PDF/PNG hashes are `2f5d3451...` and `814563db...` (archived in `archive/figureS1_review_20261030/after_source/`; the active path is overwritten by utility 30 with the composed formal figure, as for every locked figure).
- **Refreezing.** Only panel C was refrozen, to `e31cb0c5...`; the three other region hashes are unchanged (`9e911726...`, `df15bd75...`, `72b7500e...`). `config/submission_profile.json` changed on three lines (region C, baseline PDF, baseline PNG); stage 30 `--check-only` passes and 170 protected files are unchanged.
- **Caption.** The caption now states the main cohort size (n=372; recorded plausible end date), names the six restriction subsets, gives the seven restriction rows and their 214–368-patient/12–30-PD range, states that the figure has nine rows in total (the source's stochastic-imputation row is cropped), defines the plateau test against Table 2, distinguishes the main row's robust interval (0.75–1.98) from the model-based Table 2 interval (0.76–1.95) at the same estimate, identifies both dashed reference lines and their log axes, and lists the panel C PD shares (0.1, 0.2, 0.3), target HRs (1.3, 1.5, 1.75, 2.0), log y axis, 80% power and observed event fraction (0.81). The six claim patterns still match byte for byte. `P` remains upright, matching every other supplementary figure and main Figures 2–3; changing it here alone would have broken set-level consistency.
- **Methods.** The tipping sentence now lists the seven evaluated dates (90, 120, 152, 180, 210, 240 and 300 days) instead of only the 90–300-day range.

Verification:

- Formal Figure S1 is 189.79 × 179.92 mm (PDF 538 × 510 pt), 600 dpi, minimum text 8.00 pt, 65 extracted text spans; the new formal PDF/PNG hashes are `669a5692...` and `01d70be7...`. A 600-dpi pixel comparison against the previous formal figure differs only inside the C legend (x 477.2–518.5 pt, y 301.2–381.0 pt); every pixel outside that rectangle is identical, and the panel A/A/B regions are hash-identical.
- The supplement remains 31 pages with an unchanged contents map; the S1 artwork is still 189.79 × 179.92 mm at the same position on page 22, the caption now runs onto page 23 (seven lines) and S2 still begins on page 24. The caption split is the arrangement approved on 2026-10-24 and was accepted again here.
- The main upload PDF (18 pages), illustrated review copy (21 pages) and cover letter (2 pages) are byte-identical to the pre-change archive; pages 1–18 remain text-identical between upload and review copy. Stage 24 validates 138 claims and 264 fields with zero failures, stage 26 (run with `/opt/homebrew/bin/python3.10`) passes all 16 formal figures, stage 27 and `make check` pass.
- Rebuilt files: supplement Markdown `a5723730...`, TeX `75a4c89a...`, PDF `6ae578e7...`, DOCX `278bf42e...`; source `manuscript/source/supplementary.md` `e2a0823f...`; script 18 `da968697...`; script 21 `0cffcb66...`. Pre-change files are archived in `archive/figureS1_review_20261030/before/` (including script 18 at `3d55b485...` and the previous supplement PDF at `59514ea3...`). Stage 21 was the last writer; Data 5 still has 15 members and its `reporting_index.csv` still has 138 claim rows. `config/manuscript_claims.json` is byte-identical to the pre-change archive (`dd1d8fcf...`); only the three Figure S1 region/baseline hashes changed in `config/submission_profile.json`.
- No estimate, interval, P value, sample size or claim direction changed, no model was refitted, and the locked CSVs were not modified. No Git commit, push, publication or DOI deposit was performed.

## Figure S2 review: native 120 mm width and centring (2026-10-30)

A four-party review of Supplementary Figure S2 (statistics, information design, reproducibility, publishing) checked the three-row forest against `results/tables/ov_hgsoc_sensitivity/hgsoc_topology_by_setting.csv`: PR 3.51 (2.44–5.03), n=49; SD 3.96 (1.99–7.88), n=17; PD 5.14 (3.24–8.15), n=27; n=334 and 206 deaths in the caption. Every estimate and count reproduced the locked CSV. The author's view was that this single-panel figure should not occupy the full 190 mm text block; it should be drawn narrower and centred. No P0 statistical defect was found, and no estimate, interval, P value, sample size or claim direction was to change.

Layout decision:

- The 190 mm canvas left roughly 100 mm of empty plot area to the right of three short rows. Candidate native widths of 110, 120, 130 and 140 mm were rendered with the same locked data and 8 pt text. All candidates kept 8.00 pt and produced no span overlap, but 110 mm left only 3.6 mm between the widest interval string and the `n` column, and 130–140 mm retained avoidable slack.
- The approved layout is 120 mm native width with a 30 mm numeric companion column (`HR (95% CI)` and `n`). Measured text spans are 15, minimum 8.00 pt; the widest interval string ends 7.6 mm before `n`, and the header ends 12.3 mm before `n`. The forest panel remains about 90 mm wide with log ticks at 1, 3 and 5.
- Supplementary Figure S5 was not changed. It is a separate five-row forest whose cohort labels are longer, it was outside the author's instruction, and its 190 mm artwork is a locked publication figure; its width check therefore remains 190 mm.

Implementation:

- `save_formal_figure()` in `R/00_project_configuration.R` now takes an optional `width_mm` argument that defaults to the configured 190 mm, rejects non-positive values and rejects widths above the page block. The figure is rendered at the requested native width; it is never scaled down after rendering.
- Script 19 draws S2 at `width_mm = 120` and reserves 30 mm for the numeric column. The analysis values and model outputs are unchanged. The regenerated source PNG/PDF were copied to `results/figures/supplementary/FigureS2_hgsoc_four_state.{png,pdf}`; the publication renderer treats S2 as static artwork, so the copy is an explicit, documented step rather than an analysis rerun.
- Stage 21 reads the PNG `pHYs` chunk and now embeds S2 at `width=120.0mm` in the Markdown. Stage 23 wraps only artwork narrower than the 190 mm figure block in `\noindent\makebox[\linewidth][c]{...}`, which centres it without adding vertical glue; full-width figures keep their existing placement. The DOCX builder already centred figure paragraphs.
- `config/submission_profile.json` records the approved exception in `figure_audit.narrow_figure_width_mm` (`FigureS2_hgsoc_four_state`: 120). Stage 26 uses that width for this figure and still requires 190 mm for every other figure; it rejects exceptions that are non-positive or wider than the page block.

Verification:

- All nine `results/tables/ov_hgsoc_sensitivity/` CSVs are byte-identical before and after the rerun. Script 19 reproduced n=334, 206 deaths, and the three hazard ratios.
- Formal S2 is 119.94 × 44.80 mm (PDF 340 × 127 pt), 600 dpi, 15 text spans, minimum 8.00 pt, no overlapping spans. The new formal PDF/PNG hashes are `40c0df01...` and `6edcad33...`; the source companions have the same hashes.
- On supplementary page 24 the image occupies x = 45.0–165.0 mm, exactly centred in the 10–200 mm text block, with the same 22.0 mm top position as before. At 120 dpi, pages 1–23 and 25–31 are pixel-identical to the pre-change PDF; only page 24 differs, and its caption text is unchanged. The supplement remains 31 pages, S1 remains on pages 22–23 and S2 on page 24.
- The DOCX places the S2 image at 119.86 × 44.98 mm in a centred paragraph; its extracted text is identical to the pre-change DOCX. The main upload PDF (18 pages), illustrated review copy (21 pages) and cover letter (2 pages) are byte-identical to the pre-change archive, and pages 1–18 remain text-identical between upload and review copy.
- Stage 24 validates 138 claims and 264 fields with zero failures; stage 26 (run with `/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; stage 27 and `make check` pass. The generated Markdown and TeX differ from the pre-change versions only in the S2 width and the centring wrapper.
- Rebuilt files: supplement Markdown `b47700e4...`, TeX `25b367b1...`, PDF `a2069d8b...`, DOCX `53b74401...`. Changed sources: `R/00_project_configuration.R` `a228b297...`, script 19 `47d12008...`, script 23 `1f513e9e...`, script 26 `708f4e4f...`, `config/submission_profile.json` `e73196d5...`. Pre-change files are archived in `archive/figureS2_width_20261030/before/` (including the previous S2 PDF `edbe03df...` and PNG `aecef2f0...`). Stage 21 was the last writer; Data 5 still has 15 members and 138 claim rows in `reporting_index.csv`. No Git commit, push, publication or DOI deposit was performed.

## Figure S3 review: caption provenance and Data 5 source tables (2026-10-30)

A four-party review of Supplementary Figure S3 (statistics, information design, reproducibility, publishing) reproduced all 18 diagnosis-origin hazard ratios and all 18 per-subset patient counts from `results/tables/pancancer_topology/dichotomy_cr_vs_noncr_by_cancer.csv` (11 tumour types; 7 with a treated subset and 4 all-patient only). The formal artwork measured 189.79 × 149.93 mm, 600 dpi, 8.00 pt minimum text with 56 spans, a log HR axis and redundant colour/shape coding. No estimate, interval, P value, sample size or claim direction was wrong, and the author approved a P0+P1 revision without redrawing the artwork.

Findings addressed:

- **P0 caption scope.** The previous caption implied that every tumour type had both all-patient and treated estimates and called the analysed patients "all labelled patients", which overstated evaluable n in several cancers (for example OV 466 labelled versus 465 evaluable and LGG 445 versus 443). It also did not explain why CESC, COAD, UCEC and LUSC had no treated row. The caption now states that estimates are shown separately by subset, defines n as patients with evaluable OS in each subset, and states that the four tumour types lacked a treated estimate because their treated subsets did not meet the same NCR, CR or event thresholds. Exact treated counts for those four subsets are not recorded in a locked CSV (the `non_CR` field of an all-patient row is the total NCR count, not the treated count), so the revision gives the qualitative reason rather than unverifiable numbers. Stage 21 now fails if the locked table no longer resolves to those four tumour types or if the therapy-end meta-analysis is no longer the six-tumour estimate.
- **P0 provenance of the 4.02 estimate.** The main text cites a pooled NCR hazard ratio of 4.02 (95% CI 3.29–4.92) at the end of first-line therapy. That estimate comes from six tumour types at the therapy-end origin and is neither a Figure S3 estimate (diagnosis origin, 11 tumour types) nor part of the Table S4 label audit. `dichotomy_meta.csv` and the per-cancer table are now included in Supplementary Data 5, and the main-text citation reads "Supplementary Data 5 and Figure S3"; the citation for the four-state eligibility result remains Supplementary Table S4.
- **P1 completeness.** The caption now says "Unadjusted", defines n, expands CR, NCR and TCGA, states that rows are ordered by the all-patient hazard ratio and that no pooled estimate is drawn, and points to the main text and Data 5 for the pooled therapy-end estimate. The supplementary methods now state that the pooled CR-versus-NCR HR is at the end of first-line therapy and that its thresholds apply to the analysed subset; both the methods navigation paragraph and the Supplementary Data listing describe the cancer-specific and pooled dichotomy tables in Data 5.

Implementation:

- Script 21 reads the two locked dichotomy tables, asserts the four missing-treated tumour types and the six-tumour therapy-end meta-analysis, and renders the new caption. Script 33 copies both CSVs byte-for-byte into the Data 5 bundle, records them in `input_manifest.json` and adds a summary note. No estimate is recomputed and no locked CSV is rewritten.
- `manuscript/source/methods_results.md` adds "Supplementary Data 5 and Figure S3" to the 4.02 sentence. `manuscript/source/supplementary.md` adds the therapy-end origin and the Data 5 contents in two places.
- Supplementary Data 5 grows from 15 to 17 members. The 15 pre-existing members other than `input_manifest.json` and `reporting_summary.json` are byte-identical; those two change only to record the new inputs and member. `reporting_index.csv` remains 138 rows.

Verification:

- Formal S3 PDF and PNG are byte-identical to the archived pre-change files (`002361f8...` and `25ec6a98...`); the artwork was not redrawn.
- The supplement remains 31 pages, with S1 on pages 22–23, S2 on 24, S3 on 25, S4 on 26, S5 on 27 and Data on 28. The S3 caption is 10 lines at 10.91 pt with 15.17 pt leading and ends at 228.5 mm, well inside the page. The image remains 190.0 × 150.0 mm in the 10–200 mm text block.
- Text changes are confined to supplement pages 2 (contents page numbers), 7–12 (methods navigation reflow), 25 (caption) and 28 (Data 5 listing), and to main PDF pages 1 (word count 3,052 → 3,056) and 7 (citation). Main text is 3,056 words, abstract 299, references 46 and display items 5. The upload manuscript is 18 pages; the illustrated review copy is 21 pages and pages 1–18 are text-identical; the cover letter remains 2 pages.
- Stage 24 validates 138 claims and 264 fields with zero failures; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- Rebuilt files: supplement Markdown `ff1a05f5...`, TeX `4f18b920...`, PDF `54bceebe...`, DOCX `3d16eb35...`; main Markdown `4b0b61f9...`, upload PDF `90a44895...`, review copy `b1a55735...`, cover letter `ba0fdd6a...`; Data 5 `c4f63316...`. Changed sources: script 21 `05557ee0...`, script 33 `34286433...`, `methods_results.md` `5015fbcd...`, `supplementary.md` `364f3074...`. The two new Data 5 members equal their sources: by-cancer `00b8c849...`, meta `3927120c...`. Pre-change files are archived in `archive/figureS3_review_20261030/before/`. Stage 21 was the last writer. No Git commit, push, publication or DOI deposit was performed.

## Figure S4 review: caption scope, Data 5 provenance and wording (2026-10-30)

A four-party review of Supplementary Figure S4 (statistics, information design, reproducibility, publishing) decoded the 10 panels against `results/tables/pancancer_topology/topology_models_by_set.csv`. All 30 hazard ratios, all 30 confidence intervals and all 10 n/event pairs matched the locked table exactly, and the artwork measured 189.79 × 129.82 mm with 44 text spans at a minimum of 8.00 pt. No estimate, interval, P value, sample size or claim direction was wrong, and the author approved a P0+P1 revision without redrawing the artwork.

Findings addressed:

- **P0 traceability.** The figure carried no numeric labels, Supplementary Data 5 did not contain its source table, and the claim index pointed to a file that readers could not open from the bundle. `topology_models_by_set.csv` is now copied byte-for-byte into Supplementary Data 5, the caption points to that table for every displayed estimate, and the supplementary methods state where the four-state estimates are deposited.
- **P0 eligibility wording.** The old title said "in eligible tumour types", which implied that all five sets met the four-state rules. Only OV and LGG do; BLCA meets E1 but not E2 in the unrestricted set and qualifies only after restriction to treated patients, and that unrestricted set carries surgical response labels. The caption now states this tiering explicitly, identifies the unrestricted BLCA panel as a comparison, and no longer calls the ovarian panel a cohort that simply "differs slightly": it is a secondary TCGA-CDR label-source comparison, with the primary ovarian estimates in Table 2 and Figure 1.
- **P0 duplicate panels.** The BLCA and LGG therapy-end panels repeat their treated panels because the therapy-end landmark exists only for patients who received first-line non-surgical therapy. Rather than delete locked panels, the caption explains the duplication, and stage 21 fails if the paired rows cease to be identical.
- **P0 main-text wording.** "PR did not differ from CR" overstated a wide interval (LGG PR 1.18, 95% CI 0.37–3.73), and "risk rose stepwise" described a pattern that the figure does not test formally. The sentence now says that PR was not clearly separated from CR while risk was higher for SD and higher still for PD, and it records that bladder cancer met the four-state criteria only after restriction to treated patients. The preceding clause now reads "met them without restriction" so that the BLCA restriction does not contradict it.
- **P1 completeness.** The caption now gives the outcome (OS), the CR reference, per-panel n and deaths, the separate-model design, the absence of any pooled estimate or test across tumour types, and expansions of PR, SD, PD, TCGA and TCGA-CDR. Both the methods navigation paragraph and the Supplementary Data listing describe the four-state topology models in Data 5.

Implementation:

- Script 21 reads the locked topology table, asserts that exactly the five sets and ten OS/unadjusted rows remain, that the ovarian diagnosis n still equals the locked parameter, that the BLCA and LGG therapy-end duplicates are identical, and that no upper confidence limit reaches the 30-unit panel ceiling; it then renders the new caption and its two ovarian n values from the table. No estimate is recomputed.
- Script 33 copies the topology table byte-for-byte into Data 5, records it in `input_manifest.json` and adds a summary note. `config/manuscript_claims.json` narrows the ovarian-panel claim pattern to the diagnosis n now that the caption prints both origins; the claim count is unchanged.
- `manuscript/source/methods_results.md` rewrites the LGG/BLCA sentence. `manuscript/source/supplementary.md` adds the Data 5 pointer in the methods and names the four-state models in two Data 5 descriptions.
- Supplementary Data 5 grows from 17 to 18 members. The 17 pre-existing members other than `input_manifest.json` and `reporting_summary.json` are byte-identical; those two change only to record the new input and member. `reporting_index.csv` remains 138 rows.

Verification:

- Formal S4 PDF and PNG are byte-identical to the archived pre-change files (`4b5eb437...` and `45188deb...`); the artwork was not redrawn. The 30 estimates and 10 counts were re-decoded from the unchanged vector PDF.
- The supplement remains 31 pages, with S1 on pages 22–23, S2 on 24, S3 on 25, S4 on 26, S5 on 27 and Data on 28. On page 26 the image remains 190.0 × 130.0 mm at x = 10–200 mm and y = 22–152 mm; the caption is 12 lines at 10.91 pt with 15.17 pt leading and ends at 219.2 mm, inside the page.
- Rendered supplement pages 7, 8, 26 and 28 differ from the pre-change PDF (methods reflow from the added sentence, the S4 caption, and the Data 5 listing); all other pages are pixel-identical at 120 dpi. Main PDF text differs only on page 1 (word count 3,056 → 3,071) and page 7 (LGG/BLCA sentence). The upload manuscript is 18 pages; the illustrated review copy is 21 pages and pages 1–18 are text-identical; the cover letter is unchanged and remains 2 pages. Main text is 3,071 words, abstract 299, references 46 and display items 5.
- Stage 24 validates 138 claims and 264 fields with zero failures; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; `make check` passes.
- Rebuilt files: supplement Markdown `f9e0049d...`, TeX `e537c1ea...`, PDF `89521cc4...`, DOCX `5d75b0de...`; main Markdown `913a11b6...`, upload PDF `b44b7231...`, review copy `f77c741a...`, cover letter `ba0fdd6a...` (unchanged); Data 5 `b98f1b06...` (was `c4f63316...`). Changed sources: script 21 `005d8635...`, script 33 `a4f91fe1...`, `manuscript_claims.json` `36e29150...`, `methods_results.md` `d67fc6fd...`, `supplementary.md` `b5b5344f...`. The new Data 5 member equals its source. Pre-change files are archived in `archive/figureS4_review_20261030/before/`. Stage 21 was the last writer. No Git commit, push, publication or DOI deposit was performed.

## Figure S5 review: TCGA-OV label and pooled-claim validation (2026-10-30)

A four-party review of Supplementary Figure S5 (statistics, information design, reproducibility, publishing) re-decoded the five displayed estimates and confidence intervals and the eight CR/NCR counts against `per_cohort_noncr_minus_cr_estimates.csv`. All values matched: GSE63885 0.02 (−0.48 to 0.52), GSE23554 −0.23 (−1.02 to 0.55), GSE30161 0.19 (−0.40 to 0.79), TCGA-OV −0.16 (−0.36 to 0.04) and the primary external REML pool 0.03 (−0.32 to 0.37). The pooled row also matched Supplementary Table S6 and the main-text sentence. No estimate, interval, sample size or direction was wrong, so there was no P0 numerical finding.

Findings addressed:

- **P1 label ambiguity.** The reference-cohort row was labelled "TCGA", which could be read as the pan-cancer TCGA collection, while the caption and every other display call the cohort TCGA-OV. The in-figure label now reads "TCGA-OV (CR 319 / NCR 135)". The change is display-only and does not alter the 85 mm canvas, the row order, the cropped regions or any value. The author explicitly retained the locked 85 mm publication recipe and declined a caption rewrite.
- **P1 claim traceability.** The main-text pooled general-proliferation sentence (+0.03 SD, 95% CI −0.32 to 0.37) had no machine-checkable claim entry. One claim row with three fields now maps the display groups to `REML_estimate`, `REML_low` and `REML_high` in `meta_analysis_noncr_minus_cr.csv` (rows filtered to `primary_external` and `general_proliferation`). This adds one claim and three fields, so the audit validates 139 claims and 267 fields; `reporting_index.csv` grows from 138 to 139 rows.

Implementation:

- `scripts/14_validate_locked_scores.R` changes only the local S5 label helper (`lab_s5`), recoding `TCGA` to `TCGA-OV`; the informal Kaplan–Meier diagnostic keeps its original label. The script was rerun with `CRNCR_EXTERNAL_DATA_DIR` pointing at the archived GEO cache because the clean checkout does not ship raw series matrices. All 19 `results/tables/phase4_external_validation/` CSVs are byte-identical to the pre-revision baseline, including both CSVs whose hashes the renderer locks.
- The rerun also rewrote `landmark_os_by_response.pdf`, whose only difference was the embedded R creation timestamp; its text, page size and 144-dpi pixels were identical to the committed file, so the original bytes were restored to keep the revision scoped. `forest_general_proliferation.pdf/png` changed as intended.
- The three frozen S5 vector regions were re-frozen from the new source. Pixel comparison shows `FigureS5_primary_cohorts` and `FigureS5_axis` are unchanged; only the TCGA strip text changed. `config/submission_profile.json` updates the Figure S5 `baseline_sha256`, `baseline_png_sha256` and the three `locked_region_sha256` entries; `page_size_pt`, `raster_size_px`, `place_pt` and the crop rectangles are unchanged.
- `config/manuscript_claims.json` adds the pooled claim as one row with three fields (not three rows). The audit's field map is source-column to regex-group, and the displayed U+2212 minus signs are parsed correctly.
- No manuscript source file changed. Stage 21 was the last writer and rebuilt Supplementary Data 5; stage 23 rebuilt the appendix PDF and its embedded DOCX artwork.

Verification:

- The composed S5 PDF and PNG are byte-identical to the staged source (`1c706f27...` PDF, `42e52994...` PNG). The PDF is 189.79 × 84.67 mm with 16 text spans, a minimum of 8.00 pt, and the label "TCGA-OV (CR 319 / NCR 135)"; the PNG is 4488 × 2007 px at 600 dpi.
- A 600-dpi pixel difference against the archived pre-change S5 isolates 5,936 changed pixels inside one label box (x 55.8–92.3 pt, y 101.8–107.8 pt). No other pixel changed, confirming that the row geometry, estimates and axis are untouched.
- The supplement remains 31 pages. On page 27 the image remains 190 × 85 mm at x 10–200 mm and y 22–107 mm, and the caption remains four lines at 10.91 pt. At 110 dpi only page 27 differs from the pre-change supplement; every page's extracted text is identical. The upload manuscript remains 18 pages, the illustrated review copy 21 pages with pages 1–18 text-identical, and the cover letter 2 pages; main, review and cover pages are pixel-identical to the pre-change files. Main text is 3,071 words, abstract 299, references 46 and display items 5.
- Stage 24 validates 139 claims and 267 fields with zero failures; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- Supplementary Data 5 still has 18 members. Only `input_manifest.json`, `reporting_index.csv` and `reporting_summary.json` changed; the other 15 members are byte-identical, and `reporting_index.csv` now has 139 rows with the new claim last. The renderer reports 170 protected files unchanged.
- Rebuilt files: supplement Markdown `f9e0049d...` and TeX `e537c1ea...` (unchanged), PDF `5138ab82...` (was `89521cc4...`), DOCX `c7f96305...` (was `5d75b0de...`, embedded artwork only); main Markdown `913a11b6...`, upload PDF `b44b7231...`, review copy `f77c741a...` and cover letter `ba0fdd6a...` (all unchanged); Data 5 `0e0c52e2...` (was `b98f1b06...`). Changed sources: script 14 `8de0e3fc...`, `manuscript_claims.json` `0467f998...`, `submission_profile.json` `f93f12d3...`; S5 PDF `1c706f27...`, PNG `42e52994...`; regions `3ded166c...`, `c6f67ad7...`, `e2ae5adc...`. Pre-change files are archived in `archive/figureS5_review_20261030/before/`; the regenerated full eight-row source is in `archive/figureS5_review_20261030/after_source/`. No Git commit, push, publication or DOI deposit was performed.

## Supplementary Data page 28 review (2026-10-30)

A four-party review of the "Supplementary Data" and "Data conventions" page checked every description against the shipped CSVs, the Data 5 bundle and the Data 1–4 dictionary. The five descriptions and the dictionary cover 97 fields (19 + 9 + 18 + 51) and all four shapes (454 × 19, 148 × 9, 454 × 18, 454 × 51) matched. No P0 issue was found; five P1 issues were approved for implementation.

Findings addressed:

- **P1 unreachable path.** The Data 4 description pointed readers to `results/tables/supplementary/risk_set_audit_summary.csv`, which is only public after acceptance. The sentence now refers to the risk-set audit summary in Supplementary Data 5 and Supplementary Table S5. The file itself is an unchanged member of Data 5.
- **P1 Data 5 table range.** The bundle lists Tables S4–S6, not S5–S6; the description now says S4–S6.
- **P1 missing member.** The risk-set audit summary was absent from the Data 5 inventory and is now named in the list.
- **P1 filename overflow.** Both unbreakable filenames ended 13.8 pt past the right text edge when set inline after their bold labels. Stage 23 now gives each label and filename its own display line; the font size, mono font and page geometry are unchanged, so nothing was scaled down.
- **P1 Data 2 scope.** The description now states that samples without a four-class response are included, names the binary `noncr` field, and records that GSE23554 contributes only the binary CR versus incomplete-response contrast; the dictionary already defined `noncr` as 0 = CR and 1 = non-CR.

The P2 items (Data 3 flag wording, Data 5 completeness claim, Data 1–3 filename treatment, Data 4 sentence split) and the "Data conventions" paragraph were deliberately left unchanged.

Implementation:

- `manuscript/source/supplementary.md` changes only the Data 2, Data 4 and Data 5 descriptions.
- `scripts/23_build_submission_latex.py` adds a scoped substitution in `finish_si` for the two filename paragraphs. It requires exactly one match per label and aborts the build otherwise; the text otherwise passes through the existing `common_tex` normalisation.
- No claim configuration changed, so Supplementary Data 5 was not rebuilt and remains byte-identical.

Verification:

- The supplement remains 31 pages and page 28 still ends before the page-29 references. Page 28 now measures 40 text lines (was 38) and its widest line reaches 534.96 pt, against a 534.7 pt justified edge and the previous 548.51 pt overflow. The Data 4 and Data 5 paragraphs produce no overfull or underfull box.
- Full-text extraction of the supplement differs from the pre-change file only inside the Data 2, Data 4 and Data 5 descriptions; pages 1–27 and 29–31 are identical. The one pre-existing overfull reference line on page 30 (`doi:10.1093/bioinformatics/btr260`) is unchanged and was left outside this revision.
- The upload manuscript (18 pages), illustrated review copy (21 pages, pages 1–18 text-identical) and cover letter (2 pages) are byte-identical to the pre-change files. Main text is 3,071 words, abstract 299, references 46 and display items 5.
- Stage 24 validates 139 claims and 267 fields with zero failures; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- Rebuilt files: supplement Markdown `4f9a6a6f...`, TeX `deb95a3c...`, PDF `f41a94b3...` (was `5138ab82...`), DOCX `e16062ea...` (was `c7f96305...`); main Markdown `913a11b6...`, upload PDF `b44b7231...`, review copy `f77c741a...` and cover letter `ba0fdd6a...` (all unchanged); Data 5 `0e0c52e2...` (unchanged). Changed sources: `supplementary.md` `0033a82b...`, script 23 `8fee924a...`. Pre-change files are archived in `archive/supplement_p28_review_20261030/before/`. No Git commit, push, publication or DOI deposit was performed.

## Highlights wording revision (2026-10-30)

A four-party review of the Highlights and the abstract found no P0 or P1 issue. The abstract was left untouched because it already sits at 299 of the 300 permitted words, with no room for even a one-word clarification. Three optional P2 wording changes to the Highlights were approved by the author and applied to `manuscript/source/highlights.md`; the separate highlights text file and both PDFs are regenerated from that single source, so the two copies cannot drift.

Changes (all five bullets remain within the 125-character limit):

- Bullet 1: `After first-line therapy, survival …` became `Overall survival after first-line therapy …` (114 → 121 characters), naming the outcome. In an ovarian-cancer paper that reports progression-free interval separately, a bare "survival" is easily read as progression-free survival.
- Bullet 2: `was rejected because partial response carried a much higher risk of death than CR` became `was rejected: partial response carried a 3.6-fold higher risk of death than CR` (110 → 107 characters), replacing a vague qualifier with the estimate the Results already report (HR 3.61).
- Bullet 3: `CR-versus-NCR had a nearly identical median C-index to four categories` became `CR-versus-NCR had a median C-index nearly identical to four categories` (115 characters, unchanged), repairing the `identical … to` construction.
- Bullets 4 and 5, the abstract, the keywords and the cover letter are unchanged. The abstract's `combined clinical–response models` (plural with a single reported index) and the British spellings were reviewed and deliberately left alone.

Verification:

- Stage 21 passes every configured limit: 3,071 main-text words, abstract 299, references 46, five display items, and five highlights of 121, 107, 115, 104 and 109 characters.
- Full-text extraction of the upload PDF differs from the pre-change file only in the five extracted lines of the Highlights block; pages 3–18 are identical and the abstract on page 2 is unchanged. Page 2 keeps its geometry exactly: Highlights at 62.0 pt, Abstract at 266.6 pt, Keywords at 716.1 pt and a widest line of 535.0 pt, all identical to the pre-change page. The main LaTeX log has no overfull box.
- The manuscript remains 18 pages, the illustrated review copy 21 pages (stage 23 asserts pages 1–18 text-identical), the supplement 31 pages and the cover letter 2 pages.
- `ESMO_Open_highlights.txt`, regenerated by stage 21 from `highlights.md`, holds the same five lines without list markers.
- Stage 24 validates 139 claims and 16 provenance entries with zero failures; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- Rebuilt: `highlights.md` `8201e013...` (was `3df3c714...`), highlights text `693394b0...` (was `b88901b4...`), manuscript Markdown `d300f378...` (was `913a11b6...`), TeX `53d6d99b...` (was `ef819b90...`), upload PDF `24ef9a03...` (was `b44b7231...`), manuscript DOCX `0df78a51...` (was `52b56374...`) and review copy `ee32f4eb...`. The supplement PDF/TeX (`f41a94b3...`, `deb95a3c...`) and the cover-letter PDF/TeX (`ba0fdd6a...`, `b663d4c5...`) remain byte-identical. No claim configuration changed, so Supplementary Data 5 was not rebuilt.
- DOCX output is not byte-reproducible. Two consecutive stage-21 runs produced different DOCX binaries while the Markdown, TeX and PDF hashes stayed fixed, because the writer stamps creation time. The DOCX hashes recorded here describe the current files and will change on any later rebuild without any content change; the Markdown, TeX and PDF hashes are stable and should be used for verification.
- Pre-change files are archived in `archive/highlights_p2_pre_20261030/`, and `docs/SHA256SUMS.txt` was regenerated after this revision. No Git commit, push, publication or DOI deposit was performed.

## Introduction revision (2026-10-31)

A four-party review of the Introduction found no P0 issue and raised three P1 and seven P2 items. The author asked for all of them to be implemented. Every recommendation was applied to `manuscript/source/introduction.md`; no other prose source changed.

Changes:

- **P1 abbreviations.** RECIST 1.1 and GCIG were used without definition in the prose (they appeared only in the title-page abbreviation list). They are now expanded at first use as `RECIST 1.1 (Response Evaluation Criteria in Solid Tumours)` and `the GCIG (Gynecologic Cancer InterGroup) CA-125 criteria`.
- **P1 objective response rate.** The sentence that introduced ORR as a synonym for the collapsed grouping was recast: the categories are now `collapsed into objective response (CR or PR) versus no objective response, and the proportion with objective response is the objective response rate (ORR)`. The first-line maintenance trials' eligibility therefore still describes the grouping, not the rate.
- **P1 rationale for the CR threshold.** A closing sentence to paragraph 1 states the consequence the review found implicit: `If these categories differ in subsequent survival, pooling PR with CR would obscure a distinction on which both prognostic stratification and response-based trial eligibility rest.`
- **P1/P2 randomisation stratification.** `stratified randomisation by response` became `by response or treatment outcome`, because PAOLA-1 stratified by the outcome of first-line treatment at screening rather than by CR versus PR alone. The SOLO1, PRIMA and PAOLA-1 eligibility and stratification statements were rechecked against the trial reports and the Zejula label.
- **P2 scope of prognostic evidence.** `are prognostic in ovarian cancer` became `prognostic in first-line and recurrent ovarian cancer`, matching the KELIM validation settings.
- **P2 effect size.** The Villalobos re-annotation now reports its medians, `similar overall survival after SD and PR (34.4 versus 33.7 months)`, so the claim can be read without opening the source.
- **P2 dataset precision.** `public datasets rarely record` became `the public datasets used here do not record`, a verifiable statement about this study rather than a general one.
- **P2 novelty.** The comparison sentence now adds `, a comparison rarely made at a treatment-end landmark`.
- **P2 labelling.** The closing list changed from `were secondary or exploratory` to `were sensitivity or exploratory`, consistent with the Methods statement that analyses added after seeing results are labelled post hoc.

The Introduction grew by 61 words (3,071 → 3,132 main-text words).

Typography (pure layout, implemented directly):

- The additional text left page 3 ending on the hyphenated fragment `subse-` and page 4 opening with `quent survival`. `finish_main` in stage 23 now sets `\brokenpenalty=10000` for the upload manuscript, and the review copy inherits it from the same TeX. Page breaks can no longer fall after a hyphen. Line breaking, spacing, fonts and the shared header are unchanged, and the supplement and cover letter do not use this setting.
- Page 3 now ends with `The primary` and page 4 begins `objective was to compare …`. The same rule moved one reference line from page 12 to page 13; no other page break changed.

Verification:

- The upload manuscript is 18 pages, the illustrated review copy 21 pages with pages 1–18 text-identical (asserted by stage 23), the supplement 31 pages and the cover letter 2 pages.
- Stage 21 passes every configured limit: 3,132 main-text words (limit 4,000), abstract 299 (limit 300), 46 references, five display items and five highlights of 121, 107, 115, 104 and 109 characters. The conservative main-text-plus-legends total reported by stage 21 remains above 4,000, as before this revision.
- Page 2 (Highlights, abstract, keywords) is unchanged in both text and geometry; pages 8–11 and 14–18 have identical body text. Full-text extraction differs from the pre-change file only in the Introduction paragraphs, the word-count line (`3,071` → `3,132`) and the one-line reference shift at pages 12–13. No page ends in a hyphenated fragment.
- Stage 24 validates 139 claims and 267 fields with zero failures; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- Rebuilt: `introduction.md` `392b33be...` (was `c5f1d33d...`), manuscript Markdown `4adfcfae...` (was `913a11b6...`), TeX `c93b5412...` (was `deb95a3c...`), upload PDF `6654e5df...` (was `b44b7231...`) and review copy `f1a00b79...` (was `f77c741a...`). Script 23 changed to `f8fd6750...` (was `8fee924a...`). The supplement PDF/TeX (`f41a94b3...`, `deb95a3c...`) and the cover-letter PDF (`ba0fdd6a...`) remain byte-identical. No claim configuration changed, so Supplementary Data 5 was not rebuilt.
- DOCX hashes changed only because stage 21 stamps creation time; they are not reproducible and are not used as verification evidence. The Markdown, TeX and PDF hashes above are stable.
- Pre-change files are archived in `archive/introduction_review_pre_20261030/`, and `docs/SHA256SUMS.txt` was regenerated after this revision. No Git commit, push, publication or DOI deposit was performed.

## Patients and methods revision (2026-10-31)

A four-party review of Patients and methods found no P0 issue and raised eight P1 and six P2 items, all classified as reporting or clarity rather than reanalysis. The author approved all P1 items and P2 items 1–5. Every change was made in `manuscript/source/methods_results.md`, except the cohort-restriction limitation, which belongs in `manuscript/source/discussion.md`. No analysis was refitted and no result value changed.

Changes:

- **Primary objective and design provenance.** The objective now names all three codings, `four-category, objective-response and CR-threshold codings`. The plan sentence was recast as `Analysis plans for each stage, including codings, gene-set scores and decision rules, were recorded in dated internal documents before that stage; the study was not publicly registered.` This states what the dated documents cover and what registration status the study has.
- **Label provenance.** The cohort paragraph now says `Labels were chart-abstracted rather than centrally adjudicated; 70 patients had only the TCGA-CDR label, and one discordant label was retained (sensitivity analysis in Supplementary Methods).` The 70-patient figure and the single discordant label match the Supplementary Methods.
- **Canonical label definition.** `had a canonical response label` became `had a canonical (CR, PR, SD or PD) response label`.
- **Expression-linkage selection.** After the 454-patient count, the Methods now report `A sensitivity analysis without the expression requirement gave a similar pattern at the therapy-end landmark (Supplementary Results).` The wording stops at the pattern the supplement actually reports and does not assert an NCR hazard ratio.
- **Radiotherapy intent.** `Radiotherapy intent was not adjudicated.` was added after the treatment-end rule, matching the Supplementary Methods.
- **Multiplicity.** A sentence now states `P values were not adjusted for multiple comparisons; secondary and exploratory analyses were interpreted descriptively.`
- **Equivalence margin rationale.** The 0.67–1.50 margin is now described as `chosen a priori as a pragmatic bound rather than a validated clinical threshold`. The review offered a documented-rationale alternative; the author did not select it, so the honest descriptive wording was implemented. Switching to a documented rationale would need a dated source that is not in the repository.
- **Adjusted-model definition.** The text now gives `age (per 10 years)`, the `343 patients with complete covariates (29 with missing stage or residual disease excluded)` and `multiple imputation was a sensitivity analysis`, so the complete-case population and the role of imputation are stated where the model is introduced.
- **Grade sensitivity (P2).** `a grade 3–4 subset gave a similar NCR HR (Supplementary Results)` was added after the operational HGSOC definition.
- **External-cohort definitions (P2).** GSE23554 is now `CR versus incomplete response`; GSE30161 is `CR versus non-CR from the authors' chemoresponse field (CR or PR in all but one patient)`. The 6-month landmark now carries its rationale: `longer than the median recorded first-line duration of about 4 months`.
- **Cohort-restriction limitation (P2).** The Discussion limitation paragraph now adds `The analysis cohort was also restricted to tumours with expression data and a recorded response label, which may limit generalisability, and therapies given after the landmark were not modelled.`

Consistency and data coupling:

- The P1 wording change broke the anchor phrase of claim `fig1_main_labelled_counts`, whose pattern required `a canonical response label` immediately after `had`. The pattern now accepts the optional `(CR, PR, SD or PD)` insertion, so it matches this text and the previous text; the claim's source row and field map are unchanged.
- Because `config/manuscript_claims.json` is hashed into the Data 5 input manifest, Supplementary Data 5 was rebuilt with stage 33. All 17 payload members are byte-identical to the previous bundle (`reporting_index.csv` `6cf2cece...`, `reporting_summary.json` `df6d7265...`, Tables S4–S6 unchanged); only the claims-config entry in `input_manifest.json` changed. The bundle hash is `bdd0695f...` (was `0e0c52e2...`), and Data 5 still reports 139 numeric claims.
- The reference list renumbered items 24–28 because imputation (mice, Li) is now cited before the proportional-hazards and RMST references. The in-text numbers and the list were regenerated together; the main list remains 46 references.

Verification:

- Main text grew by 181 words (3,132 → 3,313, limit 4,000). The abstract is untouched at 299 of 300 words, the highlights are unchanged (121, 107, 115, 104 and 109 characters), and there are still 46 main references and five display items. Stage 21's conservative main-text-plus-legends total remains above 4,000, as before this revision.
- The upload manuscript is 18 pages, the illustrated review copy 21 pages with pages 1–18 text-identical (independently diffed and asserted by stage 23), the supplement 31 pages and the cover letter 2 pages.
- Full-text extraction differs from the pre-change file only in the Methods and Discussion paragraphs above, the word-count line (`3,132` → `3,313`) and the reference renumbering. Page 2 (Highlights, abstract, keywords) is unchanged in text and geometry: Highlights 62.0 pt, Abstract 266.6 pt, Keywords 716.1 pt, widest line 535.0 pt. No page ends in a hyphenated fragment across all 18 pages.
- Pagination remains 18 pages; page breaks moved within Methods and Discussion because the added lines changed the filled-page heights (page 3 now ends `The primary`, page 4 ends `… (2 df): the plateau test`, and the later breaks shift by up to three lines).
- Stage 24 validates 139 claims and 267 fields with zero failures; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- Rebuilt: `methods_results.md` `ddea82ed...` (was `d67fc6fd...`), `discussion.md` `d4a0033c...` (was `e38cd4d1...`), `config/manuscript_claims.json` `6f96da93...` (was `0467f998...`), manuscript Markdown `7b6b50c3...` (was `4adfcfae...`), TeX `83c9ad3f...` (was `c93b5412...`), upload PDF `38474145...` (was `6654e5df...`), review copy `20784551...` (was `f1a00b79...`) and Data 5 `bdd0695f...` (was `0e0c52e2...`). The supplement PDF/TeX/Markdown (`f41a94b3...`, `deb95a3c...`, `4f9a6a6f...`) and the cover-letter PDF (`ba0fdd6a...`) remain byte-identical.
- DOCX files changed only in their creation timestamp; they remain non-reproducible and are not used as verification evidence.
- Pre-change files are archived in `archive/methods_review_pre_20261031/`, and `docs/SHA256SUMS.txt` was regenerated after this revision. No Git commit, push, publication or DOI deposit was performed.

## Equivalence-margin provenance audit and wording revision (2026-10-31)

The author asked whether the 0.67–1.50 equivalence margin has a written basis, and asked the four-party review to check it. The audit searched the working checkout, all archives under the workspace, the legacy planning workspace, the local Git history and the external literature.

Finding:

- **A written pre-specification exists.** The 2026-10-14 research plan (`archive/legacy_workspace_20261023/CR_NonCR课题文献评估与研究方案.md`, §5.2.4) commits to a prespecified HR-ratio boundary but gives no numbers. The 2026-10-15 landmark report states `预设边界（HR 0.67–1.50）` and the relaxed 0.5–2.0 result. The archived 2026-10-15 analysis configuration (`archive/github_submission_review_baseline_20261015/config/analysis.yml`) records `equivalence_margin: [0.67, 1.50]` and `relaxed_equivalence_margin: [0.50, 2.00]`; the analysis script header declares the equivalence bounds as pre-specified and the bounds are parameters of the computation.
- **No written derivation exists.** No document states why these numbers were chosen: there is no clinical anchor, no citation, no calculation tied to the minimum detectable difference or sample size, and no meeting record. The 2026-10-19 four-party review had already flagged `等效性界值缺少依据` and recommended recording the source; only the relaxed-margin results and the word "pre-specified" were added, because no source exists.
- The pair is a reciprocal band: 0.67 ≈ 2/3 and 1.50 = 3/2, symmetric on the log scale to about ±0.405, that is, a 50% relative difference in hazard. External searching found this pair (with 0.5/2.0) as a conventional ratio margin in vaccine non-inferiority for GMT ratios, but no oncology hazard-ratio guideline or consensus endorses 1.5, and oncology non-inferiority margins are usually narrower. It cannot be presented as literature-derived or clinically validated.
- The conclusion does not depend on the margin: no PR/SD/PD contrast met 0.67–1.50, and only some unadjusted contrasts met the relaxed 0.5–2.0 bound. The margin should not be changed after seeing results.

Wording revision (author-approved): the main text now reads `within a pre-specified margin of 0.67–1.50, a pragmatic bound rather than a validated clinical threshold`. The phrase `chosen a priori as` was removed because the specific numbers first appear in analysis-day documents, not in a pre-analysis protocol; `pre-specified` is retained and matches the Supplementary Methods, and the existing disclosure that the study was not publicly registered covers the audit-trail limitation. No number, analysis or code changed, and the claim configuration was not touched.

Verification:

- Main text 3,313 → 3,309 words (limit 4,000); abstract 299; 46 references; five display items; highlights unchanged. The conservative main-text-plus-legends total remains above 4,000, as before.
- The upload manuscript is 18 pages and the review copy 21 pages with pages 1–18 text-identical (asserted by stage 23). Full-text extraction differs from the pre-change file only in the single Methods sentence and the word-count line (`3,313` → `3,309`); the paragraph reflows within the same page and no page break moves. Page 2 geometry is unchanged (Highlights 62.0 pt, Abstract 266.6 pt, Keywords 716.1 pt, widest line 535.0 pt), and no page ends in a hyphen.
- Stage 24 validates 139 claims and 267 fields with zero failures; stage 26 audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- Rebuilt: `methods_results.md` `a89063d5...` (was `ddea82ed...`), manuscript Markdown `3f6f081e...` (was `7b6b50c3...`), TeX `05decf51...` (was `83c9ad3f...`), upload PDF `8b9b8017...` (was `38474145...`) and review copy `c368554b...` (was `20784551...`). The supplement PDF (`f41a94b3...`), cover-letter PDF (`ba0fdd6a...`) and Supplementary Data 5 (`bdd0695f...`) remain byte-identical. DOCX remains timestamp-dependent and is not used as evidence.
- Pre-change files are archived in `archive/equivalence_margin_wording_pre_20261031/`, and `docs/SHA256SUMS.txt` was regenerated after this revision. No Git commit, push, publication or DOI deposit was performed.

## Results revision (2026-10-31)

A four-party review of Results checked every reported number against the source tables. It raised four P0 and seven P1 items, plus three P2 items that were not approved. The author approved P0+P1. All edits are in `manuscript/source/methods_results.md`, except one Table 2 caption in `manuscript/source/legends.md`. No model was refitted and no analysis output changed.

Accepted changes:

- **Eight-origin range.** `3.5–4.3` now reads `3.7–4.3 unadjusted and 3.5–4.2 adjusted`, matching `topology_by_landmark.csv` (unadjusted 3.742–4.276; adjusted 3.549–4.180).
- **RMST tail.** Added `and the 60-month difference was −18.0 months (95% CI −22.1 to −13.9), with sparse NCR follow-up in the tail (Supplementary Results)` from `rmst_therapy_end.csv`; the supplement records one NCR patient at risk at 60 months.
- **PFI non-proportionality.** `The PFI pattern was similar` became `For PFI, the NCR HR was lower (2.41, 1.86–3.11; NCR proportional-hazards P=0.069, so the estimate is time-averaged)`, so a time-averaged estimate is not presented as a constant hazard (`ph_tests_therapy_end.csv`).
- **Subset range.** `3.2–3.9` now reads `3.5–3.9 unadjusted and 3.2–3.7 adjusted` (`regimen_restriction_topology.csv`; adjusted plateau minimum 0.269).
- **Delayed entry.** Labelled `A post hoc delayed-entry analysis`, consistent with the Supplementary Methods, which describe two post hoc timing checks.
- **Residual >10 mm.** Added the adjusted plateau P (`0.046`) and the three confidence intervals (PR 1.39–4.72; SD 1.52–14.1; PD 3.51–17.2) from `topology_by_residual_disease.csv`.
- **Meta-analysis.** The leave-one-out and Hartung–Knapp–Sidik–Jonkman results are labelled post hoc, and the text now states that both intervals included 1 (`os_meta_noncr_vs_cr_leave_one_out.csv`; `os_meta_noncr_vs_cr_small_sample.csv`).
- **Four-state criteria.** The ovarian/LGG sentence now says `met the four-state criteria without restriction`, which is what `TableS4_pancancer_label_audit.csv` tests; only OV and LGG are eligible.
- **Standardised difference.** `+0.03 SD` became `standardised ... +0.03` to avoid colliding with the stable-disease abbreviation; the supplement uses "SD units" for standard deviation.
- **Table 2 caption.** `missing-data handling` became `selection handling`, matching the table's IPW-only selection rows and its own title.

Rejected as incorrect: a claimed conflict between 5.28 and 4.13 (different estimands), relabelling Figure 2A–C as A–B (panel C is the adjusted model cited in the same paragraph), the claim that PFI and RMST were undefined (both are defined in Methods), the claim that "similar residual disease" contradicts the Table 1 P value (that test is within-cohort only), and the `only the unadjusted PD comparisons` correction (both PD contrasts met the relaxed margin). Three P2 items were offered and not approved.

Claim coupling: two anchors referenced the pre-edit wording. `delayed_entry_plateau_main` now anchors and matches `A post hoc delayed-entry analysis at the landmark`; `residual_gt10_topology_main` now accepts the adjusted-P clause and the three confidence intervals. The `external_general_proliferation_pooled` pattern was made tolerant of `standardised` and of the omitted `SD` suffix. Because `config/manuscript_claims.json` is hashed into Data 5, stage 33 rebuilt the bundle.

Data 5: 18 members. `input_manifest.json` and `reporting_index.csv` changed (the latter only in the claim anchor text); the other 16 members, including Tables S4–S6, `rmst_therapy_end.csv` and `topology_models_by_set.csv`, are byte-identical. The bundle hash is `c2a5c3a1...` (was `bdd0695f...`), and the bundle still reports 139 numeric claims.

Pagination: the upload manuscript is 19 pages and the review copy 22 pages, with pages 1–19 text-identical and three figure pages appended. This is one page more than the previous 18/21. The approved edits added 62 words to Results; in the pre-change file, page 10 already ended at y=780.0 pt against a text-area bottom of about 782 pt, and the final 122-pt Declaration of Generative AI block is atomic. The added lines therefore push that block onto a new page. There is no typographic defect, and recovering a page would require roughly 120 pt (about nine lines) of document-wide compression, which would also alter the supplement and every table page. ESMO Open limits words rather than pages (main text 3,371 of 4,000), so the extra page was accepted rather than squeezed.

Verification:

- Main text 3,371 words (was 3,309; +62, limit 4,000); abstract 299 of 300; 46 main references; five display items; highlights unchanged (121, 107, 115, 104 and 109 characters). Stage 21's conservative main-text-plus-legends total remains above 4,000, as before.
- Full-text extraction differs from the pre-change upload PDF only in the six Results paragraphs, the Table 2 caption and the word-count line; later pages reflow because one page was added. Page 2 text and geometry are unchanged.
- Stage 24 validates 139 claims and 267 fields with zero failures; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- Rebuilt: `methods_results.md` `5dcb2c05...` (was `a89063d5...`), `legends.md` `9f73ca4c...` (was `fa6e29a0...`), `config/manuscript_claims.json` `be58b910...` (was `6f96da93...`), manuscript Markdown `4297fa02...` (was `3f6f081e...`), TeX `95759a05...` (was `05decf51...`), upload PDF `237e8f52...` (was `8b9b8017...`), review copy `f70e2d6c...` (was `c368554b...`) and Data 5 `c2a5c3a1...` (was `bdd0695f...`). The supplement PDF/TeX/Markdown (`f41a94b3...`, `deb95a3c...`, `4f9a6a6f...`) and the cover-letter PDF (`ba0fdd6a...`) remain byte-identical. DOCX files changed only in their creation timestamp and are not used as verification evidence.
- Pre-change files are archived in `archive/results_review_pre_20261031/`, and `docs/SHA256SUMS.txt` was regenerated after this revision. No Git commit, push, publication or DOI deposit was performed.

## Discussion revision (2026-10-31)

A four-party review of the Discussion raised no P0, two P1 and five P2 items, and the author approved P1+P2. The edits are in `manuscript/source/discussion.md`, with one synchronised sentence in `manuscript/source/methods_results.md` so that the Results and Discussion describe the PD step with the same estimand. No model was refitted and no analysis output changed.

Accepted changes:

- **P1-1, PD-step estimand.** The Discussion now says `From diagnosis, the PD step was borderline in all labelled patients (HR 1.55, 95% CI 1.04–2.33; P=0.038) and was not detected in the landmark cohort, even when the same patients were analysed from diagnosis`, naming the contrast as the step beyond PR and SD instead of the PD-versus-CR hazard. The matching Results sentence changed from `PD appeared distinctly worse (HR 5.89, 95% CI 4.02–8.62, versus CR; 3.86 for PR and 3.58 for SD)` to `PD appeared worse than CR (HR 5.89, 95% CI 4.02–8.62; 3.86 for PR and 3.58 for SD) and the step beyond PR and SD was borderline (HR 1.55, 95% CI 1.04–2.33; P=0.038), with M_PD lowest by AIC` (`Table2_model_comparison.csv`, rows 0 and 2).
- **P1-2, maintenance-trial eligibility.** `enrolled patients with CR or PR` became `required CR or PR (or, in one of these trials, no evidence of disease)`. SOLO1 required complete response only; PRIMA required CR or PR; PAOLA-1 permitted no evidence of disease or CR/PR. The new wording matches the Introduction and the trial publications.
- **P2-1, PFI.** The Discussion reports the progression-free interval NCR hazard (2.41, 1.86–3.11), the borderline proportional-hazards test (P=0.069) and states that the estimate is time-averaged.
- **P2-2, external imprecision.** The Hartung–Knapp–Sidik–Jonkman interval (0.30–59.3) is now given alongside the pooled hazard ratio, and the text says only GSE63885 permitted four-category topology testing.
- **P2-3, post hoc list.** `the delayed-entry analysis` was added to the enumeration of post hoc analyses.
- **P2-4, residual-disease strata.** The exploratory hazard ratios versus CR for residual disease >10 mm now carry their intervals: 2.56 (1.39–4.72), 4.64 (1.52–14.1) and 7.78 (3.51–17.2) for PR, SD and PD (`topology_by_residual_disease.csv`).
- **P2-5, scoping.** The Discussion separates the prognostic claim from surrogate and causal claims and states explicitly that the maintenance trials `should not be reinterpreted as treatment-effect comparisons between those response strata`. `objectively defined HGSOC` became `operationally defined HGSOC`, matching the Results.

Not implemented, and remaining open from the earlier Results review: **Results P1-2** (the PD step could be described as detected only in the larger diagnosis-origin cohort) and **Results P1-3** (the adjusted plateau minimum is 0.269, so `plateau P≥0.27` is a rounding of that value and the exact figure is not reproduced in the text). Both were deferred rather than rejected.

Verification:

- Main text 3,371 → 3,459 words (+88; limit 4,000); abstract 299 of 300; 46 main references; five display items; highlights unchanged (121, 107, 115, 104 and 109 characters). Stage 21's conservative main-text-plus-legends total remains above 4,000, as before.
- Pagination is unchanged at 19/22/31/2 pages. Stage 23 asserts that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended. No Overfull box was produced.
- Full-text extraction differs from the pre-change upload PDF only in the word-count line, the Results PD sentence and the Discussion paragraphs; a back-matter page break shifts Ethics and Acknowledgements by one page within the same total. No unintended text changed and no page count moved.
- Stage 24 validates 139 claims and 267 fields with zero failures; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- Rebuilt: `discussion.md` `21658846...` (was `d4a0033c...`), `methods_results.md` `5bbcd657...` (was `5dcb2c05...`), manuscript Markdown `07fd4fe9...` (was `4297fa02...`), TeX `77ea6733...` (was `95759a05...`), upload PDF `9c2e9c1c...` (was `237e8f52...`) and review copy `f20d4869...` (was `f70e2d6c...`). The supplement PDF/TeX/Markdown (`f41a94b3...`, `deb95a3c...`, `4f9a6a6f...`), the cover-letter PDF (`ba0fdd6a...`) and Supplementary Data 5 (`c2a5c3a1...`) remain byte-identical, because `config/manuscript_claims.json` was not modified and no edited sentence carries a claim anchor. DOCX files changed only in their creation timestamp and are not used as verification evidence.
- Pre-change files are archived in `archive/discussion_p1p2_pre_20261031/`, and `docs/SHA256SUMS.txt` was regenerated after this revision. No Git commit, push, publication or DOI deposit was performed.

## Results P1-2 and P1-3 revision (2026-10-31)

Two items deferred from the earlier Results review were referred to a second four-party panel (statistical estimand, numerical consistency, journal reporting, adversarial review). All four agreed that both items were real. P1-3 was judged a literal numerical falsehood (one reviewer rated it P0, three P1); P1-2 was judged a framing and completeness defect rather than a false statement (four P1). The author approved the full minimal package and chose to present the 372-patient analysis before the 453-patient analysis.

Accepted changes, all in `manuscript/source/methods_results.md` and `manuscript/source/supplementary.md`:

- **P1-3, plateau bound.** `plateau P≥0.27` became `plateau P 0.33–0.92 unadjusted and 0.27–0.73 adjusted` across `the six individual restriction subsets`. The previous inequality was false because the adjusted Grade 3–4 subset had P=0.269062; the unadjusted minimum is 0.329289, so the supplementary `P≥0.33` was also false. Both now report ranges rather than bounds.
- **P1-3, subset scope.** `every subset` became `each subset and in the combined-restriction analysis` (main text) and `each of the six subsets and in the combined-restriction analysis` (supplement). The combined row is the intersection of the six restrictions, not a seventh independent subset; the NCR HR ranges 3.5–3.9 and 3.2–3.7 exclude that row, and the combined row accounts for the `P≤8×10⁻⁴` upper bound (the six-subset maximum is 7.0×10⁻⁵).
- **P1-2, order and completeness.** The paragraph now starts with the 372 landmark-cohort analysis from diagnosis (plateau P=0.72; M3 lowest AIC and best in 68% of bootstrap samples) and then the larger unadjusted 453-patient diagnosis-origin analysis (PD versus CR HR 5.89, 4.02–8.62; PD step HR 1.55, 1.04–2.33, P=0.038; M_PD lowest by AIC but plateau not rejected, P=0.11). The closing sentence now states that the PD step was not present in the 372 patients analysed from the same origin (HR 1.20, 0.74–1.92; P=0.46) and that the analyses differ in size and eligibility. This removes the previous implication of a general PD effect and supplies the previously omitted 453-cohort plateau P and 372-cohort PD-step estimate.
- **Claim coupling.** Four anchors (`subset_ncr_min_unadj`, `subset_ncr_max_unadj`, `subset_ncr_min_adj`, `subset_ncr_max_adj`) referenced `Across the six subsets`; all four now reference `Across the six individual subsets`. No pattern or source mapping changed. Because `config/manuscript_claims.json` is hashed into Data 5, stage 33 rebuilt the bundle; `input_manifest.json` and `reporting_index.csv` changed and the other 16 members are unchanged. The bundle still reports 139 claims.

Verification:

- Main text 3,459 → 3,500 words (+41; limit 4,000); abstract 299 of 300; 46 main references; five display items; highlights unchanged (121, 107, 115, 104 and 109 characters). Stage 21's conservative main-text-plus-legends total remains above 4,000, as before.
- Pagination is unchanged at 19/22/31/2 pages. Stage 23 asserts that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Full-text extraction differs from the pre-change upload PDF only in the word-count line and the two Results paragraphs, plus a page-break reflow in the Discussion back matter; no sentence other than the edited ones changed and no page count moved. The supplement text diff is confined to the single Treatment subsets paragraph.
- Stage 24 validates 139 claims and 267 fields with zero failures; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- Rebuilt: `methods_results.md` `cef37233...` (was `5bbcd657...`), `supplementary.md` `60996a88...` (was `0033a82b...`), `config/manuscript_claims.json` `667e8772...` (was `be58b910...`), manuscript Markdown `eb0a6e54...` (was `07fd4fe9...`), TeX `39678869...` (was `77ea6733...`), upload PDF `8f45fc74...` (was `9c2e9c1c...`), review copy `26ec21ab...` (was `f20d4869...`), supplement PDF `8130f767...` (was `f41a94b3...`), supplement TeX `2faee35d...` (was `deb95a3c...`), supplement Markdown `a345d6fe...` (was `4f9a6a6f...`) and Data 5 `51c59def...` (was `c2a5c3a1...`). The cover-letter PDF (`ba0fdd6a...`) remains byte-identical. DOCX files changed only in their creation timestamp and are not used as verification evidence.
- Pre-change files are archived in `archive/results_p1_2_p1_3_pre_20261031/`, and `docs/SHA256SUMS.txt` was regenerated after this revision. No Git commit, push, publication or DOI deposit was performed.

## Declarations review on pages 10–11 (2026-10-31)

A four-party panel (journal compliance, factual consistency, reproducibility, typography) reviewed the Ethics statement, Acknowledgements, Funding, Disclosure, Data sharing statement, Author contributions and AI declaration. No P0 was found. Two P1 typography defects and three P2 accuracy defects were confirmed, and the author approved the combined P1+P2 package. No study result, sample size, claim or reference changed.

Accepted changes:

- **Data 1–4 description.** The previous sentence attributed case identifiers, response labels, treatment dates, inclusion flags, exclusion reasons and audit flags jointly to Supplementary Data 1–4, although Data 2 is a sample-level external-cohort inventory and the treatment fields in Data 1 are day offsets. The sentence now separates the Data 1 TCGA-OV case-level file (`treatment day offsets, inclusion flags and exclusion reasons`), the Data 2 external-cohort sample inventory (`response labels and covariates`), the Data 3 treatment-date audit flags and the Data 4 risk-set audit.
- **Data 5 contents.** `score specifications` was replaced by `the locked gene-set audit and data dictionary`, matching the actual Data 5 members (`locked_score_gene_audit.csv`, `supplementary_data_dictionary.json` and the other 16 files).
- **Repository scope.** `configuration files` became `analysis configuration`, because `config/paths.yml` is a private local-path file excluded by the release policy and will not be published.
- **Author-contribution block.** Stage 23 now inserts `\filbreak` before the section, so the block moves intact to page 11 instead of splitting `Cheng Xu:` from that author's roles. Page 10 now ends with the data-sharing statement.
- **Data-sharing tail.** A one-line `\enlargethispage{\baselineskip}` precedes the closing data-sharing paragraph so it stays with its bullet list; without it, one continuation line fell onto page 11.
- **AI heading hyphenation.** `writing` is wrapped in `\mbox{}` in the section title, so the heading breaks cleanly between words instead of printing `writ-` / `ing`. The heading text is unchanged.

Verification:

- Main text remains 3,500 words (declarations are outside the counted main text); abstract 299 of 300; 46 main and 44 supplementary references; five display items. Stage 21's conservative main-text-plus-legends total remains above 4,000, as before.
- Pagination is unchanged at 19/22/31/2 pages. Pages 1–9 and 12–19 of the new upload PDF are text-identical to the pre-change PDF; only pages 10–11 differ. Page 10 carries no Overfull box, and stage 23's review-copy identity assertion passes.
- Stage 24 validates 139 claims and 16 provenance entries; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures; stage 27 and `make check` pass.
- Rebuilt: `declarations.md` `1d787708...` (was `ffd42ca9...`), stage 23 script `4d70b951...` (was `f8fd6750...`), manuscript Markdown `7392f3e4...` (was `eb0a6e54...`), TeX `173be9df...` (was `39678869...`), upload PDF `3d013b40...` (was `8f45fc74...`), review copy `5195e18d...` (was `26ec21ab...`) and manuscript DOCX `351d48a9...`. The supplement Markdown/TeX/PDF (`8130f767...`), cover letter (`ba0fdd6a...`), Data 5 (`51c59def...`) and claim configuration (`667e8772...`) are unchanged.
- Pre-change files are archived in `archive/declarations_p1p2_pre_20261031/`, and `docs/SHA256SUMS.txt` was regenerated after this revision. No Git commit, push, publication or DOI deposit was performed.

## Reference presentation fixes (2026-10-31)

A four-party review of the main reference list found no P0 or P1 defect and three P2 presentation defects. The author approved the full P2 package. No citation was added, removed, renumbered or reworded, and no bibliographic metadata changed beyond the capitalization of one title word.

Accepted changes:

- **Ref 24 title capitalization.** `mice: Multivariate imputation...` became `mice: multivariate imputation...` in `config/reference_overrides.json`. The same override supplies supplementary reference 14, so that entry is corrected too.
- **Journal names kept whole.** Stage 23 now protects every journal abbreviation in the main reference list from line breaks and hyphenation: each word is boxed and joined by nonbreaking spaces. `N Engl J Med`, `J Stat Softw`, `Stat Methods Med Res` and `J Clin Oncol` no longer split (previously references 17, 24, 30 and 46). All 46 journal spans are protected; single-word names such as `Lancet`, `Nature`, `Cell`, `Biometrika` and `Biometrics` are boxed without change, and the Burnham book title remains breakable. Visible text is unchanged.
- **PMID/superscript separation.** A thin space now precedes the citation superscript that follows a PMID, so `PMID19318476 34` and `PMID17290060 39` extract as separate tokens instead of `PMID1931847634` and `PMID1729006039`. The same defect affected supplementary citations 20 and 25 and is fixed there by the shared normalization.

Verification:

- Main text remains 3,500 words; abstract 299 of 300; 46 main and 44 supplementary references; five display items.
- Pagination is unchanged at 19/22/31/2 pages. Stage 23 asserts that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Main-PDF text differs from the pre-change file only on page 5 (PMID spacing and the resulting line reflow) and pages 12–14 (reference list); pages 1–4, 6–11 and 15–19 are text-identical. Supplement text differs only on page 6 (PMID spacing) and page 29 (reference 14 capitalization); every other page is text-identical.
- No journal name in the main reference list is split across lines or hyphenated, and references 17, 24, 30 and 46 print intact. The main manuscript log contains no Overfull box. The four pre-existing supplement overfull warnings, including the Bioinformatics reference line, are unchanged in position and width.
- Stage 24 validates 139 claims and 16 provenance entries; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures; stage 27 and `make check` pass.
- Rebuilt: reference overrides `af298fad...` (was `461cc0ca...`), stage 23 script `d0f8ba9e...` (was `4d70b951...`), manuscript Markdown `32731de6...` (was `7392f3e4...`), TeX `2defa242...` (was `173be9df...`), upload PDF `650669e5...` (was `3d013b40...`), review copy `44422e03...` (was `5195e18d...`), supplement Markdown `67bc39d6...` (was `a345d6fe...`), supplement TeX `7499c1c5...` (was `2faee35d...`), supplement PDF `1275be94...` (was `8130f767...`) and manuscript DOCX `f7aa52c8...` (was `351d48a9...`). The cover letter (`ba0fdd6a...`), Data 5 (`51c59def...`) and claim configuration (`667e8772...`) are unchanged.
- Pre-change files are archived in `archive/references_p2_pre_20261031/`, and `docs/SHA256SUMS.txt` was regenerated after this revision. No Git commit, push, publication or DOI deposit was performed.

## Figure 1 review revision (2026-11-01)

A four-party panel (statistical estimand, flow/logic, journal reporting, adversarial review) examined Figure 1 against the locked counts. The author approved the combined P1+P2 package. Panels A and B were regenerated from the R generator and re-frozen; panel C was deliberately left frozen and is pixel-identical to its previous region. No analysis was re-run and no count, estimate or claim changed.

Accepted figure changes:

- **X1, panel A leading.** The five-line landmark and response-coding boxes now use the figure's 10.08 pt leading plus about 1.1 mm top and bottom clearance (19.72 mm high). Text no longer touches either border, and the flow arrow spacing is unchanged.
- **X3, panel B wording.** The outcome box now reads `Pooled CR versus NCR OS (k = 3)` and `Four-category OS: GSE63885 only`, so the pooled analysis and the single four-category cohort are no longer conflated.
- **X6, panel B table.** Row pitch increased to 10.5 pt and the header rule sits midway between the descenders of `n (deaths)` and the first data row (0.68 pt above, 0.85 pt below).
- **X7, coding label.** `M2 ORR` became `M2 objective response`, matching the methods and Table 2.
- **X9/X10, source and text hygiene.** Panels A and B were re-frozen from the clean Cairo R output instead of the previously inflated composed PDF. This removed an unused 485 KB Type0 Arial font, reduced the composed PDF from 501,633 to 81,290 bytes, and eliminated the U+037E semicolon and non-breaking spaces that the old text layer carried. The coding line now uses an ASCII semicolon.

Accepted legend changes, all in `manuscript/source/legends.md`:

- **X2.** Defines the cohort-table columns: All and Serous (tumours of any and of serous histology), Landmark (alive and under observation beyond the 183-day landmark, with deaths counted after it) and Total (sum of the Landmark column, 138 patients and 104 deaths).
- **X4.** States that panel C response and follow-up are timed from the end of first-line therapy, not from *L*.
- **X11.** States that the 454 response-labelled patients, of whom the landmark cohort is a subset, came from the 567 primary tumours linked to U133A expression.
- **X12.** States that NCR was defined by each source study (PR+SD+PD in GSE63885; unresolved incomplete response in GSE23554; the authors' chemoresponse field in GSE30161), so the pooled HR combines cohort-specific contrasts and its interval reflects between-cohort heterogeneity.
- **X13.** Deaths in (B) are counted after the landmark.
- **X14.** Adds OV, k and Xena to the abbreviation list (GEO is expanded at first use).
- **X15.** Gives the panel C counts: 5,377 labelled tumours across 23 tumour types; 760 in the four-category topology (OV 396, LGG 262, treated BLCA 102); 1,142 from six tumour types in the CR-versus-NCR analysis.

Not changed: X5 (panel C remains frozen), X8 and X11 as figure edits. The Table 2 discrepancy between 453 and 454 labelled patients remains referred outside Figure 1.

Verification:

- Main text remains 3,500 words; abstract 299 of 300; 46 main and 44 supplementary references; five display items. Stage 21's conservative main-text-plus-legends total rose from 4,704 to 4,891 words and remains above 4,000, as it was before this revision.
- Pagination is unchanged at 19/22/31/2 pages. Stage 23 asserts that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- The upload PDF differs from the pre-change file on page 1 (the legend word count), page 15 (the Figure 1 legend) and page 16 (reflow of the Figure 2 legend); all other pages are text-identical. The figure page measures 189.8 mm wide, the minimum text size is 8.0 pt, and the page is 538 × 530 pt at 1:1 with no scaling.
- Region hashes: Figure1A `00b432a1...` → `9e42c659...` (40,946 bytes), Figure1B `371b8bdc...` → `36f89765...` (52,967 bytes), Figure1C unchanged (`a53b6872...`). The panel C crop of the composed figure is pixel-identical to the archived baseline; panel A differs as intended.
- Composed figure: PDF `03fe0555...` → `c00f5adb...`, PNG `e284a854...` → `e903711f...`. Both are deterministic across repeated composition. The text layer contains no U+037E and no non-breaking space.
- Stage 30 reports original page size with three clean vector regions and exact 144-dpi parity; stage 24 validates 139 claims and 16 provenance entries; stage 26 (`/opt/homebrew/bin/python3.10`) audits 16 formal figures with zero failures; stage 27 and `make check` pass.
- Rebuilt: `legends.md` `9f73ca4c...` → `4e4fb858...`, stage 20 `eb7ccbed...` → `4657e3f5...`, `submission_profile.json` `f93f12d3...` → `d95ef03a...`, manuscript Markdown `32731de6...` → `da719870...`, TeX `2defa242...` → `bbe479e0...`, upload PDF `650669e5...` → `2e95f577...`, review copy `44422e03...` → `78cc1b12...` and manuscript DOCX (`42f3914c...`). The supplement Markdown/TeX/PDF (`67bc39d6...`, `7499c1c5...`, `1275be94...`) and the cover-letter PDF (`ba0fdd6a...`) remain byte-identical, and the claim configuration is unchanged (`667e8772...`). Data 5 was rebuilt to `20faabe4...` (was `51c59def...`) because its `input_manifest.json` records the changed `submission_profile.json` and Figure 1 hashes; its members and counts are otherwise unchanged. The supplement, cover-letter and STROBE DOCX files changed only in their creation timestamps and are not used as verification evidence.
- Pre-change files are archived in `archive/fig1_review_pre_20261101/`, and `docs/SHA256SUMS.txt` was regenerated after this revision. No Git commit, push, publication or DOI deposit was performed.

## Table 1 review revision (2026-11-01)

A four-party panel (statistical estimand, data flow, journal reporting, adversarial review) examined main Table 1, its caption and its page-18 presentation against the locked CSV. The author approved the P0+P1 package. All changes are display- or typesetting-level: `results/tables/manuscript/Table1_baseline_main_cohort.csv` is byte-identical (`52b6a7b3...`), no analysis script was run, and no count, median, P value or claim direction changed.

Adjudicated review findings:

- The excluded-patient therapy-end median uses 26 patients, not 47. `fl_end` is available for 26 excluded patients and `fl_start` for 47, but a duration or therapy-end value requires both endpoints. The displayed 94 (28–222) and 133 (52–254) days are correct; the caption and notes now state 26.
- The Fisher Monte Carlo test is seeded: `R/00_project_configuration.R` sets `set.seed(manuscript_outputs)` before script 20's Table 1 tests, and no random draw occurs earlier. The regimen P value is stable at 0.0523, displayed 0.05. The caption now states B=100,000.
- The 453-versus-454 labelled-patient difference is a Table 2 row-label issue (patient TCGA-24-0968 has a PR label but no OS), not a Table 1 error; it remains outside this revision.
- `1 (0%)` in the CR discordant-label cell was a genuine display error (1/273 = 0.37%). Nonzero counts below 0.5% now display as `<1%`.

Accepted P0 changes:

- The residual-disease Fisher test reaches the 100,000-replicate floor. Table 1 now prints `<0.001` instead of `1.0×10⁻⁵`, which implied precision the simulation does not support. The conversion is display-only in `scripts/21_build_esmo_submission.py` (`fp_t1`); other tables keep `fp`.
- The grade level `Not assessable (GB/GX)` is displayed as `Borderline/unknown (GB/GX)`, which names the two categories behind the abbreviation. The locked CSV label is unchanged.
- Table 1 now has a self-contained note block directly below the body: denominators include missing values, tests and multiplicity handling, the 26/82 date availability, 35 patients without a first-line regimen record, survivor follow-up counts, the 73-month reverse Kaplan–Meier cohort median, the excluded CR/PR/SD/PD counts (46/13/12/11) and all abbreviations.
- The Table 1 legend was rewritten to state the landmark definition, the 82 excluded patients (1 without OS and 81 at the cohort-flow steps), the statistical tests, the chart-abstracted label provenance, the survivor-only follow-up basis and the abbreviation list.

Accepted P1 changes:

- Table 1 body set at 8 pt with 9.4 pt leading and 1.5 pt column separation (was 7/8.2/1.7). The eight columns use approved unequal fractions `0.25/0.17/0.105/0.105/0.105/0.105/0.10/0.06`, replacing eight equal columns; Characteristic and Level receive the space their labels need while the six numeric columns stay compact. Fractions live in `table_layout.main_table_fractions` and are read by both the LaTeX and DOCX builders.
- The note block is set at 7 pt with 8.4 pt leading.
- In the DOCX, Table 1 follows a three-rule booktabs layout (top rule, header rule, closing rule) with no cell shading and no vertical rules; Table 2 keeps horizontal row rules only. This implements the ESMO Open instruction to avoid vertical rules and cell shading. Header shading (`D9E2F3`) and the full grid were removed. Both tables now clear the library's default table-level grid explicitly.
- The note paragraph follows the table without an intervening empty spacer paragraph in the DOCX.

Verification:

- Main upload PDF is 19 pages, the illustrated review copy 22, the supplement 31 and the cover letter 2. Stage 23 asserts that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Table legends remain on page 17 with both Table 1 and Table 2 legends; Table 1 occupies page 18 as a single landscape table and Table 2 remains on page 19. The table body, three rules and the complete note block fit inside page 18 with roughly 30 mm of clearance below the notes; no row or note spills to another page.
- The PDF shows 8 pt table body and 7 pt notes; the `<0.001`, `1 (<1%)` and `Borderline/unknown (GB/GX)` strings are present, and `Not assessable` and `1 (0%)` are absent.
- DOCX XML check: Table 1 grid widths are 3600/2448/1512×4/1440/864 twips (total 14400), every run is 16 half-points (8 pt), the note runs are 14 half-points (7 pt), there is no `w:shd`, and table- and cell-level borders contain no vertical or interior rules except the three intended horizontal rules. Table 2 has horizontal cell rules only.
- Because both main-table running titles inherit the new 8 pt table-section font (7 pt before), the Table 2 header rule moved down by one raster line (0.25 mm); its body, values, column widths and rules are otherwise unchanged.
- Main text 3,500 words, abstract 299 of 300, 46 main and 44 supplementary references, five display items. Stage 24 validates 139 claims (0 failed fields) and 16 figure provenance entries; stage 26 audits 16 figures with no failures; stage 27 and `make check` pass.
- Rebuilt: `legends.md` `4e4fb858...` → `3a1bd692...`, stage 21 `005d8635...` → `f986668c...`, stage 22 `c2a0c659...` → `353997e9...`, stage 23 `d0f8ba9e...` → `e02931e6...`, `submission_profile.json` `d95ef03a...` → `fce8e6a2...`, manuscript Markdown `da719870...` → `91d9f7cf...`, TeX `bbe479e0...` → `3dd04906...`, upload PDF `2e95f577...` → `5328a462...`, review copy `78cc1b12...` → `8094031e...` and manuscript DOCX `42f3914c...` → `95dd74d5...`. The supplement PDF (`1275be94...`) and cover-letter PDF (`ba0fdd6a...`) are byte-identical; stage 20 was restored to its baseline bytes (`4657e3f5...`) after the display-only route was chosen.
- Data 5 was rebuilt to `54e6a970...` (was `20faabe4...`) because its `input_manifest.json` records the changed `submission_profile.json`; its members and counts are otherwise unchanged.
- Pre-change files are archived in `archive/table1_review_pre_20261101/`, and `docs/SHA256SUMS.txt` was regenerated after this revision. No Git commit, push, publication or DOI deposit was performed.

## Table 2 review revision (2026-11-01)

A four-party panel (statistical estimand, data flow, journal reporting, adversarial review) examined main Table 2, its caption and its page-19 presentation against the locked model-comparison CSV. The author approved the P0+P1 package. All changes are display- or typesetting-level: `results/tables/main/Table2_model_comparison.csv` (`7bb8ec4d...`) and `results/tables/manuscript/Table2_model_comparison_formatted.csv` (`291159e1...`) are byte-identical, `scripts/20_build_manuscript_outputs.R` was not run and is unchanged (`4657e3f5...`), and no model was refitted.

Adjudicated review findings:

- The table body was set at 4.98 pt, far below the 8 pt floor used for Table 1 and below ESMO Open legibility. This was the only P0 typographic defect; the numeric content matched the locked CSV row for row.
- The former `Best AIC` / `Best BIC` column was dropped. It repeated labels already implied by the ΔAIC column and its BIC half could not be checked for the weighted rows, where information criteria were not computed.
- Near-ties were invisible at one decimal: the HGSOC row printed `1.9/36.5/0.0/0.0` although M3 and M_PD differ by 0.03. ΔAIC now switches to two decimals for the values of a row in which the second-smallest gap is below 0.05.
- The bootstrap column showed only the M3 share. It now shows M3 and M_PD shares side by side (for example `43 / 44` for HGSOC) so the reported near-equivalence is visible rather than asserted.

Accepted P0 changes:

- Table 2 body is set at 8 pt with 9.4 pt leading and 1.5 pt column separation, matching Table 1; the note block is 7 pt with 8.4 pt leading. The body, 13 columns, three rules and the complete note block fit inside one landscape page with about 35 mm of clearance.
- The dedicated note block (script 21, `TABLE2_NOTES`) now defines the HR/CI source models, the M1/M2/M3/M_PD codings, the plateau/ORR/PD-step likelihood-ratio tests, the ΔAIC reference and the below-0.05 rule, BIC selection, the bootstrap definition and subset sizes, the dagger convention for robust Wald P values with weights 0.86–2.24 and effective sample sizes 357/335, the 454-labelled/453-with-OS/372-landmark counts, and all abbreviations.
- The Table 2 legend was rewritten to the same definitions and adds the M2 objective-response coding, the M_PD category structure, the operational HGSOC definition, the 183-day fixed landmark, the diagnosis-versus-therapy-end origin rule, and the statement that date scenarios are reported separately without pooled inferential intervals.
- The first row label is now `TCGA-OV: all labelled with OS (453/454)`, matching the one PR patient without OS, and the heading `The CR threshold was the preferred coding in the primary analysis` is scoped to the primary analysis rather than stated as a general preference.

Accepted P1 changes:

- Table 2 uses 13 unequal column fractions `0.1275/0.036/0.105/0.0933×5/0.041×3/0.09/0.052` (sum 1.0), held in `table_layout.comparison_table_fractions` and read by both the LaTeX and DOCX builders; stage 23 asserts exactly 13 fractional columns and the DOCX builder validates the same vector. The n column no longer wraps mid-number and the P columns no longer overflow.
- In the DOCX, Table 2 now uses the same three-rule booktabs layout as Table 1 (top rule, header rule, closing rule, horizontal cell rules between rows) with no cell shading and no vertical rules, replacing the previous full grid.
- Supporting source text was aligned with the revised table: `methods_results.md` labels the heading as preferred in the primary analysis and states `ΔAIC 0.03; M_PD had the lowest AIC in 44% of bootstrap samples and M3 in 43%, and the PD-step test was not significant, P=0.16`; `discussion.md` and `supplementary.md` now say `all 453 labelled patients with OS` and the supplementary HGSOC paragraph gives the same ΔAIC/bootstrap figures.
- The BIC sentence in both the caption and the note block was narrowed to `every unweighted TCGA-OV row`: the two IPW rows carry no information criteria, so the earlier `every TCGA-OV row` wording overstated what was computed.

Verification:

- Main upload PDF is 19 pages, the illustrated review copy 22, the supplement 31 and the cover letter 2. Stage 23 asserts that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- The LaTeX log contains no Overfull or Underfull box for the manuscript; earlier 1.50–2.07 pt overfull warnings in the Bootstrap and P headers were removed by the final fraction set.
- Page 17 carries both table legends and ends on page 17 (no orphan line); Table 1 is page 18 and Table 2 page 19. The rendered page shows `453 (319/63/30/41)` on one line, `1.9/36.5/0.00/0.03`, `43 / 44`, `0.74† | <0.001† | 0.58†` on the IPW rows and `—` where nothing was computed.
- DOCX XML check: Table 2 has 13 grid columns totalling 14400 twips with a fixed layout, every body run is 16 half-points (8 pt), subscripts are 14 half-points, the note runs are 14 half-points (7 pt), there is no `w:shd`, no vertical or interior vertical borders, and the note paragraph follows the table with no intervening empty paragraph. This is a package-level check; no Word or LibreOffice rendering was available on this host, so Word pagination is not claimed.
- Main text 3,531 words, abstract 299 of 300, 46 main and 44 supplementary references, five display items. Stage 24 validates 139 claims (0 failed fields) and 16 figure provenance entries; stage 26 audits 16 figures with no failures; stage 27 and `make check` pass.
- Rebuilt: stage 21 `f986668c...` → `0997c8d9...`, stage 22 `353997e9...` → `14f0d50e...`, stage 23 `e02931e6...` → `2810185a...`, `submission_profile.json` `fce8e6a2...` → `03c8c3f2...`, `legends.md` `3a1bd692...` → `63c240b5...`, `methods_results.md` `cef37233...` → `81d87367...`, manuscript Markdown `91d9f7cf...` → `13543a71...`, TeX `3dd04906...` → `4f370896...`, upload PDF `5328a462...` → `affaf88e...`, review copy `8094031e...` → `c9968d12...`, manuscript DOCX `95dd74d5...` → `42172e5d...` and supplement PDF `1275be94...` → `9e9f3f3b...`. The cover-letter PDF (`ba0fdd6a...`) is byte-identical.
- `discussion.md` and `supplementary.md` each changed by the single phrase `with OS` inside `all labelled patients with OS`; these two files were not in the pre-change archive, so their modification is documented here by quotation rather than by an archived copy. All other pre-change sources (stages 20–23, `submission_profile.json`, `legends.md`, `methods_results.md`, submission outputs and docs) are in `archive/table2_review_pre_20261101/`.
- Data 5 was rebuilt to `d699e5c4...` (was `54e6a970...`) because its `input_manifest.json` records the changed `submission_profile.json`; a second rebuild reproduced the same hash, and its members and counts are unchanged.
- The mandatory stage-21/document-build run also regenerated `manuscript/strobe/STROBE_checklist.docx` and `ESMO_Open_cover_letter.docx`. Their inputs (`STROBE_checklist.md`, `cover_letter.md`) were not edited in this revision; the STROBE DOCX body text (7,035 characters) is identical to the committed version, and both packages differ from the previous bytes only through regenerated package metadata and the earlier shared document-styling code. The new bytes are recorded in the inventory.
- `docs/SHA256SUMS.txt` was regenerated after this revision: the same 358 paths, all 358 verifying, with 20 entries changing (the revised sources, submission outputs, Data 5 and this document). No Git commit, push, publication or DOI deposit was performed.

### Table 2 header vertical alignment (2026-11-01)

The author asked for the single-line column headings to be vertically centred within the header row. Pandoc emits each header cell as a bottom-aligned `minipage`, so one-line headings such as `Analysis`, `Adj.` and `PR vs CR` sat on the lower baseline of headings that wrapped to two lines (`Plateau P`, `ΔAIC`, `Bootstrap, % M3 / M_PD`). Stage 23 now rewrites only the 13 header cells of Table 2 from `\begin{minipage}[b]` to `\begin{minipage}[c]`, leaving body rows and Table 1 untouched; the rewrite asserts that exactly 13 bottom-aligned header minipages are found, so a header change fails the build rather than silently reverting. The DOCX already used `w:vAlign="center"` on all 13 header cells, so no DOCX change was needed.

Rebuilt: stage 23 `2810185a...` → `918e6a77...`, TeX `4f370896...` → `5a1b4d3e...`, upload PDF `affaf88e...` → `56127aad...` and review copy `c9968d12...` → `7236ff85...`. Page counts remain 19/22/31/2, the LaTeX log has no Overfull box, stage 23 still asserts text-identical shared pages, and the supplement PDF (`9e9f3f3b...`) is unchanged because this path does not touch it. Pre-change files are in `archive/table2_header_valign_pre_20261101/`, and `docs/SHA256SUMS.txt` was refreshed and verifies.

### Figure 2 caption corrections (2026-11-01)

The four-party review of Figure 2 found no numerical error in the plotted estimates, but it found one caption-figure mismatch and four cross-file precision problems. The approved package retained the 120-month x-axis and the existing curves, because the CR group still has 56, 27 and 8 patients at risk at 72, 96 and 120 months, whereas NCR, PR, SD and PD have no patients at risk after 72 months. Only text was changed; the figure was not re-rendered.

Accepted P0 change:

- The Figure 2 caption no longer says that the curves extend to 120 months. It now reads: `The x-axis and risk tables extend to 120 months; curves terminate at the last observed follow-up in each group (NCR maximum 71 months), and analyses use all available follow-up with right-censoring at last observation, without 120-month administrative censoring.` The risk table already showed zero at risk at 72, 96 and 120 months for NCR, PR, SD and PD; the NCR maximum follow-up is 71.26 months.

Accepted P1 changes:

- Figure 2E and Figure 3C now qualify the 0.67–1.50 margin as `a pragmatic bound rather than a validated clinical threshold`, matching Methods.
- Figure 2D now says `all response-labelled patients with OS from diagnosis (n=453 ...; of 454 labelled patients, one PR lacked OS)`, matching the 453/454 count in Table 2 and the Results.
- The Figure 2 abbreviation list defines `ORR, objective response rate`.
- Figure 2E and the supplementary Discrimination paragraph now state that the 5th–95th percentiles are `across the 20 repeats`, not across folds.
- The `figure2_d_diagnosis_n` claim regex in `config/manuscript_claims.json` was updated to the revised prefix; Data 5 was rebuilt.

Not changed in this revision: figure geometry, colours, panel frames, the 11% label clearance, the roman `P` in the KM annotation, and the caption flow across pages 15–16. The P2 contrast and typography items remain deferred.

Verification:

- Figure 2 PNG (`9ae282ce...`) and PDF (`9d16b65f...`) SHA256 values are unchanged, proving that no re-render occurred.
- Main upload PDF is 19 pages, the illustrated review copy 22, the supplement 31 and the cover letter 2. Stage 23 asserts that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- The Figure 2 caption still flows from page 15 to page 16; Figure 3 ends on page 16 and Table legends begin on page 17, with no orphan page.
- Main text 3,531 words, abstract 299 of 300, 46 main and 44 supplementary references, five display items.
- Stage 24 validates 139 claims (0 failed fields) and 16 figure provenance entries (0 failed); stage 26 audits 16 figures with no failures; stage 27, stage 32 `--check` and `make check` pass.
- Rebuilt: `legends.md` `63c240b5...` → `4c1ac39d...`, `supplementary.md` `35b121ba...` → `62abcbe9...`, `manuscript_claims.json` `667e8772...` → `f9ef149a...`, manuscript Markdown `13543a71...` → `1d8c4b07...`, TeX `5a1b4d3e...` → `0bbda732...`, upload PDF `56127aad...` → `2fb0331e...`, review copy `7236ff85...` → `e897b906...`, supplement PDF `9e9f3f3b...` → `34d54ab1...`, manuscript DOCX `42172e5d...` → `cb9b3581...`, supplement DOCX `2a44865d...` → `592e4768...` and Data 5 `d699e5c4...` → `ab0e81d9...`. The cover-letter PDF (`ba0fdd6a...`) is byte-identical; its DOCX was regenerated with metadata-only churn, and its text matches the unchanged PDF apart from typographic quotes, semicolons, bullets and line-break hyphens (similarity 0.9938).
- The same mandatory build also regenerated `manuscript/strobe/STROBE_checklist.docx` (`9160811b...` → `b8b0e525...`) from its unchanged Markdown source (`968353be...`, not edited); the differences are limited to pandoc table markup and typographic quotes, with a normalised-text similarity of 0.9557.
- Pre-change files are in `archive/figure2_caption_pre_20261101/`; `docs/SHA256SUMS.txt` was regenerated after this revision and verifies. No Git commit, push, publication or DOI deposit was performed.

### Figure 3 caption corrections (2026-11-01)

The four-party review of Figure 3 found no numerical error in the plotted estimates, but found two caption-figure mismatches (P0) and three disclosure gaps (P1). The author approved the five-item package and added the Panel A HKSJ/prediction-interval clause, making six text edits. Only `manuscript/source/legends.md` changed; the figure was not re-rendered. The caption grew from 1,927 to 3,162 characters (260 to 440 words).

Accepted changes:

1. **Panel A interval context.** The caption now gives the Hartung–Knapp–Sidik–Jonkman interval (0.30–59.3) and the normal-based REML prediction interval (0.60–30.2) next to the plotted Wald interval (1.43–12.62), states that both alternative intervals include 1, and points to Table S3. The values match Supplementary Results (`4.25 (1.43–12.6) with a 95% prediction interval of 0.60–30.2; the HKSJ interval (0.30–59.3) included 1`).
2. **Panel B horizon (P0).** `Curves/risk table show 120 months; analyses retain all follow-up` became `The x-axis and risk table extend to 120 months; curves continue to the last observed follow-up in each group (CR maximum 128 months, clipped near the panel edge), and analyses use all available follow-up with right-censoring at last observation, without 120-month administrative censoring.` `ggsurvplot(xlim=c(0,120))` uses `coord_cartesian`, so the viewport expands to about 126 months instead of censoring data; ticks stop at 120 and the CR path reaches about 128 months, where it is clipped. The earlier wording implied that the curves themselves ended at 120 months.
3. **Cross-validation percentiles (P1).** The caption now reports repeat-level 5th–95th percentiles of 0.635–0.666 for the four-category index and 0.626–0.651 for CR versus NCR, and states that these percentiles describe split variability, not confidence intervals. The values come from `cv_repeat_concordance()`: median 0.653885, q05 0.634507, q95 0.666292 for four categories, and 0.638562 (0.626032–0.650953) for CR versus NCR. Fold-level medians are 0.6498 and 0.6353, so the repeat-level spread must not be read as a CI or as fold-to-fold variation.
4. **Panel C row definitions (P0).** The caption now states that panel C shows response-only, covariate-unadjusted PD-versus-PR+SD HRs, one row per time origin, using all response-labelled patients with OS at that origin: diagnosis n=453, fixed 6-month landmark n=426, end of first-line therapy n=372, with the therapy-end row additionally requiring a recorded treatment-end date; then the therapy-end IPW row (n=372) and GSE63885 (n=69). It also states what is not plotted: the adjusted estimate in 343 covariate-complete patients (PD-versus-PR+SD HR 1.42, 95% CI 0.86–2.34; Table 2) and the diagnosis-origin estimate in the 372 landmark-eligible patients (1.20, 0.74–1.92; Table 2 and Results). The previous `TCGA-OV rows are complete-case` wording was wrong for the unadjusted rows, whose denominators differ by origin, and confused them with the covariate-complete adjusted analysis.
5. **Reference-band provenance (P1).** The 0.67–1.50 band is now described as the pre-specified equivalence margin for pairwise PR/SD/PD comparisons within NCR, defined on 90% CIs, and as a pragmatic bound rather than a validated clinical threshold. The caption states that all plotted intervals are 95% CIs for PD versus PR+SD, so the band is a reference only and overlap is not evidence of equivalence. The margin belongs to a different contrast family from the plotted PD-versus-PR+SD rows; this caveat was previously implied but not stated.
6. **Abbreviation list (P1).** `CV, cross-validation`, `I², heterogeneity statistic` and `k, number of cohorts` were added and the list was re-alphabetised.

Current-state correction to earlier entries: the 2026-10-21 revision note that panel C displays `PD n=36*` for date imputation, and the Figure 3A source-encoding note that a retracted source appears as a grey open circle, describe the stage-20 drawing source rather than the released artwork. The released Figure 3 has six panel A rows (two TCGA-OV origins, three external cohorts and the REML pool) with no retracted row, and five panel C rows (three TCGA-OV origins, the IPW row and GSE63885) with no date-imputation row. A `pdftotext` check of the released review-copy figure pages confirms this, and the caption's `Descriptive date scenarios are reported separately in Supplementary Results, not as inferential forest-plot rows` now describes the artwork that is actually published. A latent retracted-source branch remains in the stage-20 code but is removed by the locked crop, so it is not a figure error; if that crop is ever rebuilt, the branch must stay excluded.

Typography: the longer caption pushed two lines onto page 17. Stage 23 now inserts `\enlargethispage{2\baselineskip}` before the Figure 3 legend in `finish_main()`, using the same local mechanism already applied to the data-sharing tail. No caption wording, font size or spacing changed; the main PDF returned to 19 pages and the legend fits on page 16.

Verification:

- Main upload PDF is 19 pages, the illustrated review copy 22, the supplement 31 and the cover letter 2. Stage 23 asserts that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended. The LaTeX log contains no Overfull box for the manuscript.
- The full Figure 3 legend, including the abbreviation list, is on page 16 of the main PDF; Figure 3 ends on page 16 and the table legends begin on page 17 with no orphan page.
- All six Figure 3 claim regexes in `config/manuscript_claims.json` still match; the edits preserved the anchored strings `n=69; 61 deaths`, `0.654`, `the CR-versus-NCR value was 0.639.`, `k=3; n=138 total participants` and `Hartung–Knapp–Sidik–Jonkman interval (0.30–59.3)`.
- Main text 3,531 words, abstract 299 of 300, 46 main and 44 supplementary references, five display items. The stage-21 conservative sum of main text plus all legends is 5,393 and still exceeds 4,000; this is the same expected conservative flag recorded in earlier entries, not a new breach caused by this revision.
- Stage 24 validates 139 claims (0 failed fields) and 16 figure provenance entries (0 failed); stage 26 audits 16 figures with no failures; stage 27, stage 32 `--check` and `make check` pass.
- Figure 3 PDF (`8250c6b2...`) and PNG (`13e0c3b5...`) SHA256 values are unchanged, proving that no re-render occurred. The supplement PDF (`34d54ab1...`), cover-letter PDF (`ba0fdd6a...`) and Data 5 (`ab0e81d9...`) are byte-identical.
- Rebuilt: `legends.md` `4c1ac39d...` → `558e50dc...`, `scripts/23_build_submission_latex.py` `918e6a77...` → `afee87ea...`, manuscript Markdown `1d8c4b07...` → `8155f816...`, TeX `0bbda732...` → `3d6d4285...`, upload PDF `2fb0331e...` → `635ba6f1...`, review copy `e897b906...` → `491bceb4...`, manuscript DOCX `cb9b3581...` → `0fba49ab...`, supplement DOCX `592e4768...` → `32975e5d...`, cover-letter DOCX `c0818eb2...` → `c546fc7a...` and STROBE DOCX `b8b0e525...` → `e2e33738...`. DOCX-versus-source text similarity is 0.9969 for the manuscript, 0.9658 for the supplement and 0.9982 for the cover letter; the STROBE DOCX text is identical to the committed version (1.0), and its byte change comes from regenerated package metadata.
- Pre-change `legends.md` and stage 23 are in `archive/figure3_caption_review_pre_20261101/`. `docs/SHA256SUMS.txt` was refreshed after this record: the same 358 paths, all verifying, with 10 entries changing. No Git commit, push, publication or DOI deposit was performed.

## P1 revision (2026-11-01)

The four-party academic review raised six P1 issues about claim strength and transparency. The author approved "P1 全套"; the P2 items were not implemented. Pre-change sources, scripts 17 and 21, the claims configuration, six baseline result CSVs and the four PDFs are in `../archive/p1_implementation_pre_20261101/` (22 files). Two analyses were added and the manuscript wording was aligned with them.

Accepted changes:

1. **Parsimony, not predictive superiority (P1-1).** The title now says the survival structure is "better described by the complete-response threshold than by objective response", and the Discussion states that the CR threshold is preferred "for parsimony and interpretability, not because it predicts better: discrimination was indistinguishable". A paired comparison (CR threshold minus four categories) across the 20 cross-validation repeats gives a median difference of 0.001 (bootstrap 95% CI −0.001 to 0.003; 13 of 20 repeat-level differences positive), reported in the abstract, Results and Discussion.
2. **Rejected ORR grouping separated from NCR equivalence (P1-2).** Results now state that the NCR hazard "summarises the contrast with CR and is not itself evidence of homogeneity among NCR states", and the Introduction and Discussion state that the recommendation to report CR and PR separately "follows from the PR–CR difference alone" and does not require NCR equivalence. The abstract conclusion separates the equal-parameter-count fit from the PR–CR difference that drives the recommendation.
3. **Label provenance and single-source sensitivity (P1-3).** Of 70 patients without a clinical-matrix label (62 CR, 8 PR), 65 were in the landmark cohort; this provenance sentence is in Methods and Supplementary Methods. Excluding those 65 patients leaves 307 patients (186 deaths): the unadjusted NCR HR is 3.25 (2.38–4.43), the adjusted HR 3.45 (2.46–4.83; n=289), the plateau is not rejected (P=0.93 unadjusted; 0.82 adjusted), ORR grouping is rejected (P=5.6×10⁻⁷; 6.7×10⁻⁷ adjusted) and M3 retains the lowest AIC and BIC. This is reported in Results and Supplementary Results and indexed in Data 5.
4. **Treatment era (P1-4).** The Discussion notes that maintenance eligibility is itself response-dependent, so contemporary cohorts may contain a different mix of CR and NCR patients; this is added to the existing paragraph on trials that predate current first-line pathways.
5. **External heterogeneity in the abstract (P1-5).** The pooled estimate now carries I²=80%, the post hoc leave-one-out estimate excluding GSE23554 (2.78, 1.78–4.35), and a statement that the Hartung–Knapp–Sidik–Jonkman and prediction intervals included 1. The Figure 3 legend points to Table S3 for the leave-one-out estimate.
6. **Model-selection uncertainty (P1-6).** The Discussion states that the CR threshold is preferred for parsimony and that "M3 and M_PD remain compatible descriptions". The abstract no longer implies that the CR threshold predicts better than four categories.

New outputs from `scripts/17_fit_therapy_end_landmark.R`:

- `results/tables/ov_therapy_end_landmark/label_source_counts.csv`: 65 TCGA-CDR-only, 306 concordant and 1 discordant label in the landmark cohort; 5, 77 and 0 outside it.
- `results/tables/ov_therapy_end_landmark/topology_excluding_cdr_only.csv`: the two-row (unadjusted, adjusted) CDR-only sensitivity.
- `results/tables/ov_therapy_end_landmark/cv_discrimination_paired_delta_CR_vs_four.csv` and `..._replicates.csv`: paired repeat-level ΔC summary and the 20 contributing differences. The six archived baseline CSVs are byte-identical after the rerun, so existing estimates, information criteria and cross-validated indices did not change.

The rerun regenerated the Figure 2 PDF with a new `CreationDate` only: its PDF hash changed from `9d16b65f...` to `6a6e4625...`, its PNG is unchanged (`9ae282ce...`), and a `pdftoppm` comparison showed identical pixels. The staged copies in `results/figures/main/` were refreshed so that provenance validation matches the current source.

Verification:

- Main upload PDF is 19 pages, the illustrated review copy 22, the supplement 31 and the cover letter 2; stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript with three figure pages appended. The abstract remains on page 2, the Introduction begins on page 3 and Methods on page 4. The cover-letter PDF is byte-identical (`ba0fdd6a...`) and was not rebuilt.
- Main text 3,743 words, abstract 300 of 300, 46 main and 44 supplementary references, five display items. The stage-21 conservative sum of main text plus all legends is 5,618 and still exceeds 4,000; this is the same expected conservative flag recorded in earlier entries, not a new breach.
- Stage 24 validates 145 claims (0 failed fields) and 16 figure provenance entries (0 failed); stage 26 audits 16 figures with no failures; stage 27 and `make check` pass.
- Data 5 was rebuilt to `334e3200...` (was `ab0e81d9...`) because the claims configuration changed; its reporting index has 145 rows, matching the claim audit.
- Rebuilt: `title_page.md` `756413cc...` → `8ec522aa...`, `introduction.md` `392b33be...` → `4c1ce85d...`, `methods_results.md` `81d87367...` → `09e53b96...`, `discussion.md` `1e25e8d6...` → `5a78ede9...`, `supplementary.md` `62abcbe9...` → `97717d11...`, `legends.md` `558e50dc...` → `5802ebf1...`, `manuscript_claims.json` `f9ef149a...` → `25a06cec...`, manuscript Markdown `8155f816...` → `5a53152c...`, TeX `3d6d4285...` → `85a3c0b9...`, upload PDF `635ba6f1...` → `18bc6074...`, review copy `491bceb4...` → `c655e415...`, supplement PDF `34d54ab1...` → `c7fca3c9...`, manuscript DOCX `0fba49ab...` → `52b7e827...` and supplement DOCX `32975e5d...` → `8dacfc4d...`. The cover-letter and STROBE DOCX files were regenerated from unchanged sources (cover-letter DOCX `c546fc7a...` → `0cde2069...`; STROBE DOCX `e2e33738...` → `4373032a...`), and the cover-letter PDF is byte-identical.
- `docs/SHA256SUMS.txt` was regenerated after this record with the same selection rules as earlier revisions: the 358 previous paths are all retained and the four new result CSVs are added, giving 362 entries, all of which verify. Historical pre-change material under the in-tree `archive/` is treated as non-release evidence and remains outside the inventory, as in earlier entries. No Git commit, push, publication or DOI deposit was performed.

## P2 triage and A-package revision (2026-11-01)

The four-party team adjudicated the 15 P2 items that the P1 revision left open, and the author approved package A: one propagation fix and one substantive sentence. Pre-change sources, stage 23 and the four PDFs are in `../archive/p2_A_pre_20261101/` (8 files). The pre-change stage 23 was reconstructed from the current file by reverting the two edited blocks and its SHA-256 matches the previously recorded `afee87ea...` exactly.

Triage:

- Already satisfied or only needed verification: P2-4 (multiplicity statement is already in Methods), P2-5 (calibration is discussed qualitatively and the topology claims do not rest on calibration), P2-7 (GSE63885 PD handling is stated in the supplement), P2-8 (PFI purpose), P2-9 (pan-cancer and molecular scope), P2-10 (word budget), P2-12 (reference style), P2-13 (registration wording), P2-14 (display items). P2-15 was factually wrong: the abstract already reports confidence intervals, so no change was made.
- Deferred because each needs a new analysis rather than wording: P2-1 (Bell(4) dose scan), P2-2 (calibration curve), P2-3 (E-value).
- Submission-day action: P2-11 (cover-letter date).
- One text change, P2-6, plus the P1 title propagation fix, form package A.

Accepted changes:

1. **Title propagation (P1 defect).** `manuscript/source/supplementary.md` and the submission line of `manuscript/source/cover_letter.md` still carried the pre-P1 title. Both now read "better described by the complete-response threshold than by objective response". The cover-letter date remains 19 October 2026 and will be set on the day of submission.
2. **P2-6 fixed landmark in external cohorts.** The Discussion limitations paragraph now states: "Because treatment-end dates were unavailable, external cohorts were analysed from a fixed 6-month landmark rather than the patient-specific landmark, so response timing relative to the time origin may differ." No estimate, cohort or analysis changed.
3. **Supplement title-page typography.** The longer title no longer fitted the appendix title block: the first line ended 10.86 pt beyond the right text edge because the title page disables dictionary and explicit-hyphen breaks. Stage 23 now inserts `\allowbreak` after each explicit hyphen of the title paragraph only, and adds `\emergencystretch=3em` inside the title-page group; `\exhyphenpenalty=10000` still applies to the rest of the page, so the ORCID is not split. The title is again two lines, breaking at the hyphen of "complete-response", and ends at 532.88 of 532.92 pt. The three 0.11 pt table-alignment warnings and the one 14.21 pt paragraph warning are unchanged from the P1 build.

Verification:

- Page-text comparison against the archived PDFs shows differences only on main manuscript page 1 (word count) and page 10 (the new limitation), supplement page 1 (title) and cover-letter page 1 (title). Every other page is text-identical.
- Page counts remain 19 (upload manuscript), 22 (illustrated review copy), 31 (supplement) and 2 (cover letter); stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript with three figure pages appended.
- Main text is 3,772 words (was 3,743; the new sentence adds 29), the abstract remains 300 of 300, references 46 main and 44 supplementary, and display items 5. The conservative stage-21 sum of main text plus legends is 5,647 and still exceeds 4,000, the same expected informational flag recorded earlier.
- Stage 24 validates 145 claims and 16 figure provenance entries with 0 failures; stage 26 audits 16 formal figures with 0 failures; stage 27 and `make check` pass.
- All 51 `results/figures/` inventory entries are byte-identical to their recorded hashes. The locked renderer rewrote the Figure 2 PDF during `make publication`, but its bytes remain `6a6e4625...` and the PNG is unchanged.
- The supplement LaTeX log contains no overfull box on the title page; the three 0.11 pt table-alignment warnings and one 14.21 pt paragraph warning are unchanged from the P1 build. The main, review-copy and cover-letter logs have no overfull or undefined-reference warnings.
- Supplementary Data 5 is byte-identical (`334e3200...`). The claims configuration and analyses were not touched, and the Data 5 input manifest does not include `supplementary.md` or `cover_letter.md`.
- Rebuilt: `supplementary.md` `97717d11...` → `02fd2b04...`, `cover_letter.md` `45427bad...` → `afc89747...`, `discussion.md` `5a78ede9...` → `5f77b403...`, manuscript Markdown `5a53152c...` → `ce4a5eae...`, TeX `85a3c0b9...` → `dde4dc81...`, upload PDF `18bc6074...` → `1ae3bc44...`, review copy `c655e415...` → `622e8dc7...`, manuscript DOCX `52b7e827...` → `fcf1f572...`, supplement Markdown `9243c767...` → `7a88dee0...`, TeX `f7f82ed0...` → `ccd97d2e...`, PDF `c7fca3c9...` → `343da79d...`, DOCX `8dacfc4d...` → `bbe19ef8...`, cover-letter TeX `b663d4c5...` → `dbff3b07...`, PDF `ba0fdd6a...` → `8b324927...` and DOCX `0cde2069...` → `e36abd60...`. Stage 23 changed from `afee87ea...` to `39bdf703...`.
- The staged copy `manuscript/submission/cover_letter.md` was regenerated from the updated source. `manuscript/strobe/STROBE_checklist.docx` was regenerated with unchanged checklist text (`4373032a...` → `3b9cb348...`); only the embedded document timestamp differs, as in the P1 revision. DOCX files are rebuilt on every stage-23 run, so their embedded timestamps change even where the text does not.
- `docs/SHA256SUMS.txt` was regenerated after this record with the same selection rules as earlier revisions: the same 362 paths, no additions or omissions, all verifying. Changed entries are the three edited sources, their Markdown, TeX, PDF and DOCX outputs, the staged cover-letter copy, stage 23, the STROBE DOCX and this document. Stage 21 was the last writer of the Markdown and TeX sources. No Git commit, push, publication or DOI deposit was performed.

## P2 integration: partition scan, calibration and E-values (2026-11-01)

The author approved the recommended integration of the three P2 items that the triage deferred as needing new analysis: the 15-subset response-partition scan with Benjamini–Hochberg correction (P2-1), 36- and 60-month calibration (P2-2) and E-values for unmeasured confounding (P2-3). The integration adds one analysis script, one supplementary table, one supplementary figure, one reference and eight claims, and edits the Results, Discussion and Supplementary text. Pre-change sources, configuration, stage 20/21/23/33, the Makefile, the provenance table and this document are in `../archive/p2_integration_pre_20261101_2321/` (15 files).

New analysis, `scripts/34_response_partition_calibration_sensitivity.R`:

- **Partition scan (P2-1).** All 15 non-empty subsets of CR, PR, SD and PD were enumerated; 14 had a non-empty complement and defined a directed contrast, and opposite directions of the same split collapsed to seven bipartitions. Each was fitted in the therapy-end landmark cohort, unadjusted (n=372, 220 deaths) and adjusted for age (per 10 years), stage and residual disease (n=343, 207 deaths), and the Benjamini–Hochberg correction was applied within each adjustment over the seven bipartitions. CR versus PR+SD+PD ranked first: adjusted HR 3.59 (95% CI 2.61–4.94), P=3.4×10⁻¹⁵, q=2.4×10⁻¹⁴; unadjusted HR 3.91 (2.91–5.26), q=1.1×10⁻¹⁸. Every bipartition separated survival: the largest adjusted q was 0.0066 (CR+PR+PD versus SD) and the largest unadjusted q 0.0019. Because the scan followed the main analysis and no partition was pre-specified, Results and Table S7 call it exploratory and descriptive.
- **Calibration (P2-2).** Predicted 36- and 60-month death risk from the adjusted Cox model was compared with Kaplan–Meier risk in the 343 covariate-complete patients. At 36 months the mean predicted risk was 40.0% and the observed risk 40.2% (O:E ratio 1.004; calibration-in-the-large −0.022; optimism-corrected slope 0.890 from 978 valid of 1,000 case-resampling bootstrap samples). At 60 months the values were 64.7% and 67.1% (O:E 1.038; CITL 0.026; slope 0.880 from 985 valid). By response at 36 months, predicted versus observed risk was 28.1% versus 29.0% in CR, 74.2% versus 62.1% in PR, 68.5% versus 69.4% in SD and 71.9% versus 83.8% in PD. At 60 months the Kaplan–Meier risk reached 100% in PR and SD, so no interval is plotted. No model was refitted for this analysis.
- **E-values (P2-3).** E-values use `E = RR + sqrt(RR(RR−1))`. Because 33.2% of patients had died by 36 months and 51.9% by 60 months, the primary values convert the hazard ratio to a risk ratio for a common outcome (VanderWeele & Ding 2017, PMID 28693043); the uncorrected formula applied directly to the hazard ratio is shown only for comparison. Adjusted NCR-versus-CR: 4.21 (3.27 for the 95% CI bound nearer the null), uncorrected 6.64 (4.67); unadjusted 4.49 (3.57); adjusted PR-versus-CR as context 3.79 (2.77).

Text changes:

- `manuscript/source/methods_results.md` gains one paragraph immediately before "Robustness across treatment and disease subsets" that reports the three analyses and points to Supplementary Table S7 and Supplementary Figure S6. `manuscript/source/discussion.md` appends one sentence to the residual-confounding paragraph: an unmeasured confounder would need risk-ratio associations of at least 4.2 with both NCR and death (3.3 to move the interval to the null), and BRCA/HRD status, maintenance therapy and performance status are named as plausible confounders of a more modest strength.
- `manuscript/source/supplementary.md` gains the section "Exploratory response-partition, calibration and confounding analyses" with three run-in italic paragraphs, the `{{TABLE_S7}}` placeholder after Table S6, an updated front-matter line ("Tables S1–S7; Figures S1–S6") and an updated Data 5 description ("Tables S4–S7 CSVs").
- `manuscript/source/references_verified_pubmed.json` gains `vanderweele2017` after PubMed verification, bringing the file to 64 entries; the supplement now has 45 references, of which #18 is VanderWeele & Ding.

Build wiring:

- `Makefile` adds script 34 to `make clinical` before stage 20, adds a `sensitivity` target that runs only script 34, and lists it in `.PHONY`.
- `config/analysis.yml` adds `response_sensitivity: 20261101`. Script 34 records R 4.5.0, survival 3.8.3, riskRegression 2025.9.17 and that seed in `run_metadata.txt`.
- Stage 20 (`20_build_manuscript_outputs.R`) extends the stale-supplementary-figure cleanup to `^FigureS[1-6]_`, copies the Figure S6 PNG and PDF from `results/figures/ov_response_sensitivity/` into `results/figures/supplementary/`, and stages `TableS7_response_partition_scan.csv` and `TableS7_evalues.csv` from the new results directory.
- Stage 21 reads both S7 CSVs, requires one row per rank and a complete mapping of the E-value source labels, and builds the 10-column panel (a) and 5-column panel (b) pipe tables. It computes the Figure S6 caption from `calibration_summary.csv` (n=343, 207 deaths, 978 and 985 valid resamples) rather than from hard-coded values, and lists Figure S6 after Figure S5. The Table S7 caption cites no reference marker: captions are inserted after reference numbering, so the E-value citation lives in the supplementary text.
- Stage 23 sets the Table S7 block to run to the end of the supplementary-table segment (`s7_stop = len(styled)`), because the figures heading is split off before the table styling runs. S7 is a landscape page with panel (a) on seven rows and panel (b) on three.
- Stage 27 expects figure fonts for S2–S7 and validates both S7 column-fraction lists (10 and 5 positive values, each summing to 1).
- Stage 33 maps `tables/supplementary/TableS7_response_partition_scan.csv` and `tables/supplementary/TableS7_evalues.csv` to script 34, so Data 5 records the producer.
- `config/submission_profile.json` sets the S7 body font to 8.5/10.2 pt with 1.0 pt column separation and the two fraction lists. `results/tables/manuscript/figure_provenance.csv` gains two Figure S6 rows (PDF and PNG) whose source and staged copies are byte-identical.
- Stage 21 was also reformatted where the Figure S1 and S2 caption tuples had been joined on one line; the generated files were regenerated and are byte-identical.

Verification:

- Main upload PDF is 20 pages (was 19), the illustrated review copy 23 (was 22), the supplement 34 (was 31) and the cover letter 2. Stage 23 asserts that pages 1–20 of the review copy are text-identical to the upload manuscript and that three figure pages are appended. The new Results paragraph is on page 7, the Discussion sentence on page 9, Table S7 on supplementary page 23 and Figure S6 on supplementary page 30.
- Main text is 3,963 words (was 3,772), 37 words below the 4,000 limit; the abstract remains 300 of 300, references 46 main and 45 supplementary, and display items 5. The conservative stage-21 sum of main text plus legends is 5,838 and still exceeds 4,000, the same expected informational flag recorded earlier.
- Stage 24 validates 153 claims (0 failed fields) and 18 figure provenance entries (0 failed); stage 26 audits 18 formal figures with 0 failures; stage 27 and `make check` pass. `make publication` reported 189 protected files unchanged.
- Supplementary Data 5 was rebuilt to `ca484c76...` (was `334e3200...`): 20 members, including both Table S7 CSVs, and a 153-row `reporting_index.csv` mapping them to `scripts/34_response_partition_calibration_sensitivity.R`.
- The supplementary reference list numbers VanderWeele & Ding as #18, and the Table S7 caption and the review-copy figure page contain no unnumbered citation markers.
- New release files (16): `results/tables/ov_response_sensitivity/` (`partition_scan_all15.csv`, `partition_scan_unique.csv`, `table_s7_partition_scan.csv`, `calibration_summary.csv`, `calibration_by_response.csv`, `calibration_by_decile.csv`, `evalues.csv`, `predictrisk_crosscheck.txt`, `run_metadata.txt`), `results/tables/supplementary/TableS7_response_partition_scan.csv`, `results/tables/supplementary/TableS7_evalues.csv`, `results/figures/ov_response_sensitivity/FigureS6_calibration.pdf` (`de048182...`) and `.png` (`0cbbbbc3...`) with byte-identical staged copies in `results/figures/supplementary/`, and `scripts/34_response_partition_calibration_sensitivity.R`.
- Rebuilt: `methods_results.md` `09e53b96...` → `03c1483a...`, `discussion.md` `5f77b403...` → `0c93b910...`, `supplementary.md` `02fd2b04...` → `34bcb3a0...`, `references_verified_pubmed.json` `ef880170...` → `b2968d99...`, `manuscript_claims.json` `25a06cec...` → `62767ec7...`, `analysis.yml` `e2981087...` → `290dd302...`, `submission_profile.json` `03c8c3f2...` → `c121bd01...`, `Makefile` `b8165d43...` → `bd6ae336...`, stage 20 `4657e3f5...` → `9afe5302...`, stage 21 `0997c8d9...` → `fbba4562...`, stage 23 `39bdf703...` → `a5dc3a57...`, stage 27 `b3fcbfbe...` → `34b1f4d9...`, stage 33 `a4f91fe1...` → `e97fea5f...`, `figure_provenance.csv` `a91291bd...` → `ea210f70...`, manuscript Markdown `ce4a5eae...` → `98c3dcf1...`, TeX `dde4dc81...` → `a663c656...`, upload PDF `1ae3bc44...` → `e7215474...`, review copy `622e8dc7...` → `bdb14b28...`, manuscript DOCX `fcf1f572...` → `b55033d8...`, supplement Markdown `7a88dee0...` → `83ffbfec...`, TeX `ccd97d2e...` → `7638f137...`, PDF `343da79d...` → `0fefa419...`, DOCX `bbe19ef8...` → `f2dccf2c...`, cover-letter DOCX `e36abd60...` → `240aca45...` and STROBE DOCX `3b9cb348...` → `6eee9a2b...`. The cover-letter PDF (`8b324927...`) is byte-identical; DOCX files are rebuilt on every stage-21/23 run, so their embedded timestamps change even where the text does not.
- `docs/SHA256SUMS.txt` was regenerated after this record with the same selection rules as earlier revisions: the 362 previous paths are retained and 16 new release files are added, giving 378 entries, all of which verify. The pre-change material under the in-tree `archive/` remains outside the inventory. No Git commit, push, publication or DOI deposit was performed.

## Cover-letter review revision and title-page inventory fix (2026-11-02)

A four-party review of the cover letter was followed by cross-examination against the locked analyses, and the author approved the full revision package (P0, P1 and P2). Pre-change sources, stage 23, this document, the checksum inventory and the submission PDF, TeX and DOCX files archived for comparison are in `../archive/cover_letter_review_pre_20261102/` (11 files).

Cover-letter text:

- The letter is dated 2 November 2026 and reports the landmark cohort (372 patients, 220 deaths, 343 with complete covariates). The category hazard ratios are labelled unadjusted: 3.61 for PR, 4.16 for SD and 4.50 for PD, with the adjusted NCR-versus-CR hazard ratio 3.59 (95% CI 2.61–4.94).
- Bullet 2 gives the rejection P value (8.5×10⁻¹⁰), states that the CR-versus-NCR and objective-response models are equally parameterised, names AIC and BIC, and reports the cross-validated C-indices (0.679 versus 0.677) and Akaike weights (0.59 versus 0.30).
- Bullet 3 reports the pooled external estimate (HR 4.25, 95% CI 1.43–12.6; I²=80%), notes that small-sample intervals included 1 and that only GSE63885 allowed four-category testing. Bullet 4 spells out "inverse-probability-of-inclusion-weighted".
- A new paragraph reports the exploratory scan of all 15 response subsets (q=2.4×10⁻¹⁴ after correction over seven bipartitions) and the E-value (4.21; 3.27 at the 95% CI bound).
- The editorial case now says that responses should be reported separately "in prognostic analyses". The limitations paragraph adds the ethics and consent basis and the STROBE statement, says plans were fixed "before each stage", adds the treatment-era caveat (bevacizumab and PARP-inhibitor maintenance) and calls external validation "pre-specified locked molecular scores".
- The declarations add National Natural Science Foundation of China grants 82403759 and 82403616 before the conflict-of-interest sentence.

The title page now lists "Tables S1–S7, Figures S1–S6" in its supplementary-material line, matching the supplement; the previous "Tables S1–S6, Figures S1–S5" was stale.

Typography: stage 23 inserts a page break before the paragraph beginning "We think these results" and sets the cover-letter paragraph skip to 0.35 em, so the findings end page 1 and the editorial case with the declarations starts page 2. The insertion is anchored to the paragraph text and fails if the anchor is missing or duplicated.

Verification:

- Page counts are 20 (upload), 23 (review copy), 34 (supplement) and 2 (cover letter). Stage 23 asserts that pages 1–20 of the review copy are text-identical to the upload manuscript and that three figure pages are appended. The cover letter is 831 words; page 1 ends with the exploratory-scan paragraph and page 2 begins "We think these results".
- The title page and PDF page 1 read "Tables S1–S7, Figures S1–S6". Main text remains 3,963 words, the abstract 300, references 46 main and 45 supplementary, and display items 5.
- Stage 24 validates 153 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with 0 failures; stage 27 and `make check` pass. The claim audit CSV changed only because the three cover-letter category rows now read 3.61, 4.16 and 4.50; no claim was added or removed.
- The supplement PDF (`0fefa419...`) and Supplementary Data 5 (`ca484c76...`) are byte-identical. The supplement and STROBE DOCX files were rebuilt by the run, so their embedded timestamps changed; their text sources were not edited.
- Rebuilt: `cover_letter.md` `afc89747...` → `d926b1ae...` (source and staged copy), `title_page.md` `8ec522aa...` → `413b248f...`, stage 23 `a5dc3a57...` → `2fef1bfc...`, cover-letter TeX `dbff3b07...` → `d7fc8f71...`, PDF `8b324927...` → `60a18dea...`, DOCX `240aca45...` → `160fbcb2...`, manuscript Markdown `98c3dcf1...` → `190537cd...`, TeX `a663c656...` → `6a8153f8...`, upload PDF `e7215474...` → `a575eb55...`, review copy `bdb14b28...` → `52199103...`, manuscript DOCX `b55033d8...` → `9a7bfbac...`, supplement DOCX `f2dccf2c...` → `f4be7a0e...`, STROBE DOCX `6eee9a2b...` → `8db43c11...` and claim audit CSV `02fdd2a9...` → `774f192a...`.
- `docs/SHA256SUMS.txt` was regenerated after this record with the same selection rules as earlier revisions: the same 378 paths, no additions or omissions, all verifying. No Git commit, push, publication or DOI deposit was performed.

## Main-text word-count trim (2026-11-02)

A word-count check found that the stage 21 counter reported 3,963 prose words, which passed the 4,000-word limit, but that adding the 18 section headings (70 words) gave 4,033, which exceeded it. The journal's stated exclusions do not mention headings. The main text was therefore trimmed by 59 prose words to 3,904, or 3,974 with headings, leaving a 26-word margin under either convention. Pre-change sources, submission PDFs, this document and the checksum inventory are in `../archive/wordcount_trim_pre_20261102/` (10 files).

Six meaning-preserving edits were made; no outcome, effect estimate, P value, citation or claim was removed:

- Introduction: "Both binary codings were specified before analysis; the primary objective was to determine which coding better described survival." became "Both binary codings were specified before analysis." The objective is still stated in the Methods.
- Methods, study design: "Analyses added after seeing results are labelled post hoc." became "Post hoc analyses are labelled."
- Methods, selection analyses: the closing pointer "Full definitions are provided in the Supplementary Methods." was removed because the same paragraph already cites the Supplementary Methods for stage-specific definitions.
- Results, primary analysis: "This HR summarises the contrast with CR and is not itself evidence of homogeneity among NCR states." became "This HR summarises the contrast with CR, not homogeneity among NCR states."
- Discussion, comparison with prior work: the trailing clause "and suggest that pooling PR with CR yielded a smaller cross-validated gain over clinical covariates" was removed; the cross-validated comparison remains in the Results and the first Discussion paragraph.
- Discussion, interpretation: the eligibility parenthetical in "The maintenance trials, which required CR or PR (or, in one of these trials, no evidence of disease) [@solo1; @prima; @paola1]" was removed, leaving "The maintenance trials [@solo1; @prima; @paola1]"; the eligibility detail remains in the Introduction.

Verification:

- Stage 21 reports "PASS main text 3904 ≤ 4000 words"; the title page and PDF page 1 read 3,904. The abstract remains 300 words, references 46 main and 45 supplementary, display items 5, and highlights 5.
- Page counts are now 19 (upload), 22 (review copy), 34 (supplement) and 2 (cover letter). Stage 23 asserts that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended. The one-page reduction in the upload manuscript and review copy follows from the shorter text; the supplement and cover letter are unchanged in length.
- Stage 24 validates 153 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with 0 failures; stage 27 and `make check` pass. The claim, provenance and typography audit CSVs are byte-identical to the previous run.
- The supplement PDF (`0fefa419...`) and Supplementary Data 5 (`ca484c76...`) are byte-identical. The supplement and STROBE DOCX files were rebuilt by the run, so their embedded timestamps changed; their text sources were not edited.
- Rebuilt: `introduction.md` `4c1ce85d...` → `64f03fed...`, `methods_results.md` `03c1483a...` → `58582196...`, `discussion.md` `0c93b910...` → `a506afbe...`, manuscript Markdown `190537cd...` → `9aa464af...`, TeX `6a8153f8...` → `893240bb...`, upload PDF `a575eb55...` → `c6e5ffe2...`, manuscript DOCX `9a7bfbac...` → `776a489b...`, review copy PDF `52199103...` → `ab45ffae...`, supplement DOCX `f4be7a0e...` → `8c016af9...` and STROBE DOCX `8db43c11...` → `3d3c7dc3...`.
- `docs/SHA256SUMS.txt` was regenerated after this record with the same selection rules as earlier revisions: the same 378 paths, no additions or omissions, all verifying. No Git commit, push, publication or DOI deposit was performed.

## Supplementary word-count review and clarity fixes (2026-11-02)

A four-way review of the Supplementary Appendix found no journal-imposed supplementary word or page limit; the official guide pages returned HTTP 403, so this conclusion rests on search snippets and third-party summaries rather than an official page. At 6,363 prose words the appendix was defensible but contained duplicated main-text restatements. An optional trim of about 400 words and three clarity fixes were approved.

The trim reduced the appendix from 6,363 to 5,981 prose words (−382; Supplementary Methods 3,326 → 3,045, Supplementary Results 2,411 → 2,310; Data and front matter unchanged). Only duplicated restatements were removed: clinical-data and radiotherapy/landmark wording; constraint, P-value-policy, equivalence and cross-validation caveats already in the main text; the six-subset list; repeated bootstrap, RMST, objective-response-component, Akaike-weight, delayed-entry, PFI and subset-range statements; and the Data 5 inventory that is repeated in its own description. Unique values and reproducibility details were retained. The HGSOC section now labels the therapy-end P values as adjusted and the diagnosis-origin values as unadjusted.

The first trim pass removed 11 value anchors used by the claim audit; stage 24 reported 11 failed fields. Those values were restored verbatim (objective-response components, minimal detectable HRs, delayed-entry estimates, subset ranges and the 60-month RMST difference), leaving the 382-word net reduction and 153 of 153 passing claims.

Clarity fixes:

- The supplement contents now lists Figure S1–S6 (pages 23, 25, 26, 27, 28 and 29). Stage 23 emits a hyperlinked subsection entry with `\phantomsection` before each figure, so the six entries have distinct anchors; the table entries are unchanged.
- Two main-text citations, "Figure S2" and "Figure S3", became "Supplementary Figure S2" and "Supplementary Figure S3" for consistency with S1 and S4–S6. This adds two words; stage 21 reports 3,906 prose words (3,976 with headings), still below 4,000.
- HGSOC P values now distinguish adjusted from unadjusted as described above.

Verification:

- Page counts are 19 (upload), 22 (review copy), 33 (supplement, one fewer than before) and 2 (cover letter). Stage 23 verifies that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Stage 24 validates 153 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with 0 failures; stage 27 and `make check` pass. Supplementary Data 5 is byte-identical (`ca484c76...`).
- Figure S1's caption still continues onto page 24; its contents entry points to the figure's start on page 23. This known caption/page-break issue is unchanged in kind and was not altered by this revision.
- Rebuilt: `supplementary.md` `34bcb3a0...` → `c0d2f397...`, `methods_results.md` `58582196...` → `bd4ece35...`, stage 23 `2fef1bfc...` → `9572dba6...`, supplement Markdown `83ffbfec...` → `ea68eeae...`, supplement TeX `7638f137...` → `475bbfc9...`, supplement PDF `0fefa419...` → `adb8195e...`, supplement DOCX `8c016af9...` → `a3f62cf3...`, manuscript Markdown `9aa464af...` → `d10531c2...`, manuscript TeX `893240bb...` → `70f8828d...`, upload PDF `c6e5ffe2...` → `dc4f5fef...`, review copy `ab45ffae...` → `b88e2fdb...` and manuscript DOCX `776a489b...` → `4007180f...`. The cover-letter PDF is unchanged (`60a18dea...`). Stage 21 also rebuilt the cover-letter and STROBE DOCX files, so only their embedded timestamps changed.
- `docs/SHA256SUMS.txt` was regenerated with the same 378 paths, no additions or omissions, and all entries verify. No Git commit, push, publication or DOI deposit was performed. The 13 pre-change files are in `../archive/supplement_wordcount_trim_pre_20261102/`.

## Main-manuscript legend and table-note trim (2026-11-02)

The figure legends and table material in the main manuscript carried duplicated definitions and reproducibility detail that made the display items hard to read. A four-way review separated must-keep scientific content from restatement and approved a trim; the revised text was written directly because it changes only presentation of already-reported results.

Display-item prose fell from 2,234 to 1,662 words (−572; −25.6%). Figure legends fell from 1,239 to 1,028 words (−211; −17.0%) and table material from 995 to 634 (−361; −36.3%). Within the table material, captions fell from 636 to 206 words while the notes rose from 359 to 428, because test definitions, follow-up derivation and abbreviation lists moved out of the captions into the notes. Stage 21's conservative "main text + legends" diagnostic fell from 5,781 to 5,140; the official main-text count remains 3,906 of 4,000 words.

The trim keeps every value and caveat that an inference depends on. All 21 claim-audit patterns tied to `manuscript/source/legends.md` still match verbatim, including the landmark size, response-only CV C-indices, the three time-origin populations, bootstrap counts, the k=3 pooled cohort size with its Hartung–Knapp–Sidik–Jonkman interval, the GSE63885 landmark size and C-index, and the CR-versus-NCR value. Review restored qualifiers that an earlier compression had dropped: the distinct n=343 adjusted and n=372 diagnosis-origin populations in Figure 3C; "mortality risk" rather than "PD risk" for the Figure 2E equivalence comparison; the scope and pragmatic rationale of the 0.67–1.50 equivalence margin; the Figure 3B censoring caveat; and the Table 2 IPW, exploratory, missing-stage and time-origin definitions.

Layout and build changes:

- Figure legends occupy pages 15–16 and Table legends page 17; Table 1 is on page 18 and Table 2 on page 19 (landscape). No legend or note is clipped or split across pages.
- Stage 23 now begins the Table 2 notes at "Values are hazard ratios for death", matching the revised wording, and retains the forced page break before the Table legends so that the Table 2 legend stays intact.
- The `\enlargethispage{2\baselineskip}` workaround added for the previous Figure 3 legend was removed; the shortened legend fits without it.

Verification:

- Page counts are 19 (upload), 22 (review copy), 33 (supplement) and 2 (cover letter). Stage 23 verifies that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Stage 24 validates 153 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with 0 failures; stage 27 and `make check` pass.
- Rebuilt: `legends.md` `5802ebf1...` → `b6f2be55...`, stage 21 `fbba4562...` → `183c239c...`, stage 23 `9572dba6...` → `83476c6a...`, manuscript Markdown `d10531c2...` → `8b05a9ef...`, manuscript TeX `70f8828d...` → `2475b780...`, upload PDF `dc4f5fef...` → `a9e42ac7...`, review copy `1481b47c...` and manuscript DOCX `4007180f...` → `299d546f...`. The review copy is excluded from the checksum inventory by policy. The supplement (`adb8195e...`) and cover letter (`60a18dea...`) are unchanged because this path does not touch them.
- `docs/SHA256SUMS.txt` was regenerated with the same 378 paths, no additions or omissions, and all entries verify. No Git commit, push, publication or DOI deposit was performed. The pre-change sources, PDFs and reviewed draft are in `../archive/legend_table_trim_pre_20261102/`.

## Humanizer-style prose revision (2026-11-02)

A prose audit checked the main manuscript for machine-sounding patterns. The `humanizer` skill is not installed in this environment, so the audit was performed manually with the same remit: a lexical scan for stock transitions and inflated verbs, and sentence-level metrics. The lexical scan found no occurrence of "underscore", "crucial", "pivotal", "delve", "landscape", "foster", "leverage", "not only", "moreover", "furthermore" or em dashes. Across 161 sentences the mean length was 24.7 words (SD 12.1), with 89 semicolons and 13 colons. Three P1 issues were identified and the author authorised their implementation: an unsourced novelty claim, a recommendation stated four times, and long semicolon-heavy sentences. Methods passive voice, abbreviations and the strongest existing sentences were deliberately left unchanged.

The four edits:

1. **Novelty (P1-1).** The Introduction now reads "to our knowledge, this comparison has not been made at a treatment-end landmark" instead of "a comparison rarely made at a treatment-end landmark". The abstract Background changes "is rarely tested" to "is uncertain", which removes the same unsupported frequency claim and saves one word.
2. **Recommendation repetition (P1-2).** Two adjacent Discussion sentences were merged so that the recommendation is stated once: it "follows from the PR–CR difference alone and concerns patient-level prognostic grouping; it does not require the NCR states to be equivalent."
3. **Sentence splits (P1-3).** Four long sentences in the Results were split at their natural boundaries: the concordant-label sensitivity analysis, the treatment/disease restriction summary, the HGSOC model comparison, and the diagnosis-origin PD comparison. No value, qualifier or claim span changed. In the first split, only "M3 retained the lowest AIC and BIC" was separated so that the two `cdr_only` claim patterns spanning the preceding semicolons continue to match verbatim.

Word counts: main text 3,908 of 4,000 (was 3,906), abstract 299 of 300 (was 300). The stage-21 conservative "main text + legends" diagnostic is 5,142 and still exceeds 4,000; this is the expected informational flag, not a submission breach. References remain 46 main and 45 supplementary, with five display items.

Layout and build changes:

- References end on page 14 and the Figure legends begin on page 15. The revised body initially pushed four references onto a nearly empty page 15; because reference entries sit in a pandoc `\tightlist` enumerate, paragraph spacing has no effect, so the fix sets `\setstretch{1.02}` inside the References section and restores `\setstretch{1.12}` and `\parskip{0.35em}` before the Figure legends. The document returned from 20 to 19 pages.
- Figure legends occupy pages 15–16, Table legends page 17, Table 1 page 18 and Table 2 page 19 (landscape). Rendered inspection confirmed that the Figure 3 legend and both table notes close completely without clipping or page splits.

Verification:

- Page counts are 19 (upload), 22 (review copy), 33 (supplement) and 2 (cover letter). Stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Stage 24 validates 153 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with 0 failures; stage 27 and `make check` pass.
- Rebuilt: `introduction.md` `64f03fed...` → `4944e6d1...`, `title_page.md` `413b248f...` → `79923252...`, `discussion.md` `a506afbe...` → `d3530111...`, `methods_results.md` `bd4ece35...` → `c15043fc...`, stage 23 `83476c6a...` → `8696c9be...`, manuscript Markdown `8b05a9ef...` → `344ce677...`, manuscript TeX `2475b780...` → `37541ce0...`, upload PDF `a9e42ac7...` → `137497b9...`, review copy `1481b47c...` → `e709d7c0...`, manuscript DOCX `299d546f...` → `2e14c1bd...` (the DOCX hash also varies with build timestamps). The review copy is excluded from the checksum inventory by policy. The supplement (`adb8195e...`) and cover letter (`60a18dea...`) are unchanged because this path does not touch them.
- `docs/SHA256SUMS.txt` was regenerated with the same 378 paths, no additions or omissions, and all entries verify. No Git commit, push, publication or DOI deposit was performed. The pre-change sources, PDFs, reviewed draft and the previous stage-23 script are in `../archive/humanizer_p1_pre_20261102/`.

## External review package (2026-11-02)

An external review of the submission raised thirteen items across the main manuscript, supplement and cover letter. Each was checked against the source, claim configuration and rendered pages. Five were implemented as a package, and the cover letter was compressed; the remaining items were not adopted.

Implemented:

1. **Title-page metadata.** The journal-limit annotations in the word-count paragraph were removed, and the legend count is now rendered with a thousands separator (`1,234`). The paragraph reports main text, legends, abstract, display items, references and supplement without internal checklist text.
2. **Abstract abbreviations.** Stable disease is defined at first use (`stable disease (SD)`) and the later plateau sentence uses `PR, SD and PD`. The abstract remains 299 words, within the 300-word limit.
3. **Supplementary table cross-references.** The main text now names Supplementary Table S1 (external cohorts), S5 (eight time-origin definitions) and S6 (molecular scores, together with Figure S5). All Tables S1–S7 and Figures S1–S6 are now explicitly cited.
4. **Table 1 denominator.** The note now states that the therapy-duration and therapy-end medians in the Excluded column are calculated among the 26 excluded patients with therapy-end dates. Recalculation from Supplementary Data 1 confirmed both medians use n=26.
5. **Software citations.** GEOquery is now cited where GEO was screened, so its first appearance precedes the software list; timeROC is cited to Blanche et al. (2013). The fgsea preprint entry now uses the `2016:060012` identifier. The supplement reference list is 46 entries; because first-appearance order changed, GEOquery is number 20 and Blanche is number 46.
6. **Cover letter.** The letter was reduced from 831 to 536 words (454 words of body prose) and now fits one page. The Akaike-weight and E-value details and the WGCNA-negative narrative were removed; the category hazard ratios, adjusted NCR-versus-CR estimate, discrimination comparison, external consistency and its limits, integrity statements and funding remain. Stage 23 no longer forces a page break before the editorial-case paragraph; the letter uses 20 mm side margins, 16 mm top/bottom margins, 1.05 line stretch and 0.25 em paragraph spacing.

Not implemented: the running-head change (item 1.2), long-term OS references (3.1), the expression-requirement rewrite (3.2), the figure-upload note (4.2), the Table 2 dash claim (5.2; rendered inspection showed no spill), continued-table headers and Figure S1 reflow (7.1), and the Table S7 explanatory note (7.2). Item 3.2 was not adopted because the proposed n=396 sentence describes the pan-cancer TCGA-OV analysis, not a simple expression-free sensitivity analysis, and the cited table is the pan-cancer label audit. Items 1.2, 4.2 and 7.1 are submission-workflow or layout changes outside this package; 5.2 was a `pdftotext` reading-order artefact.

Word counts: main text 3,917 of 4,000 (was 3,908), abstract 299 of 300, references 46 main and 46 supplementary, five display items. The stage-21 conservative "main text + legends" diagnostic is 5,151 and still exceeds 4,000; this is the expected informational flag, not a submission breach.

Verification:

- Page counts are 19 (upload), 22 (review copy), 33 (supplement) and 1 (cover letter). Stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Stage 24 validates 153 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with 0 failures; stage 27 and `make check` pass.
- Rebuilt hashes (before → after): `title_page.md` `79923252...` → `2d526511...`, `methods_results.md` `c15043fc...` → `290a8aaa...`, `supplementary.md` `c0d2f397...` → `38bb4819...`, `cover_letter.md` `d926b1ae...` → `76a9b76b...`, stage 21 `183c239c...` → `9ce8c9a2...`, stage 23 `8696c9be...` → `a887daa4...`, claims `62767ec7...` → `80e141ac...`, overrides `af298fad...` → `ca0b7b99...`, manuscript Markdown `344ce677...` → `ddb3aa3a...`, manuscript TeX `37541ce0...` → `9e68699d...`, upload PDF `137497b9...` → `7d15c254...`, review copy `e709d7c0...` → `c8c85f1c...`, supplement PDF `adb8195e...` → `26f3fe63...`, cover-letter PDF `60a18dea...` → `9bac6caf...`, manuscript DOCX `2e14c1bd...` → `7af442fd...`, supplement DOCX `3d451dea...` → `a7afddd1...`, cover-letter DOCX `4808504d...` → `8650c899...`. DOCX hashes also vary with build timestamps.
- `docs/SHA256SUMS.txt` was regenerated with the same 378 paths, no additions or omissions, and all entries verify. No Git commit, push, publication or DOI deposit was performed. The pre-change package is in `../archive/review_items_20261102/`.

## Priority peer-review action list (2026-11-02)

A thirteen-item prioritised list from external peer review was implemented across the title page, abstract, main text, figure legends, supplement, cover letter and reporting bundle. The list comprised five P0 scientific items, three P1 inference items and four P2 presentation items. No new model family was fitted: the only new analysis is the selection tipping script authorised for P0-3.

Scientific revisions:

1. **Title, abstract and conclusion.** The title now states that objective response obscures the prognostic difference between complete and partial response. The abstract leads with the PR–CR contrast, reports the category-specific hazard ratios, and gives the 307-patient concordant-label estimate. The conclusion presents CR versus NCR as the most parsimonious summary of the four categories, not as a uniquely best model.
2. **Response-label provenance and the concordant cohort.** The supplement gives the exact TCGA-CDR field, assessment timing and the PD rule, and explains why CR is over-represented. The main text reports the 307 patients with a clinical-matrix label as a co-primary analysis (NCR HR 3.25, 2.38–4.43; adjusted 3.45, 2.46–4.83; 306 strictly concordant 3.21, 2.35–4.39) and states the direction of the single discordant label.
3. **Landmark selection.** A new main section reports the 82 excluded labelled patients (46 CR, 36 NCR; 23 and 29 deaths), the 11 excluded PD patients (median OS 6.2 months) and the direction of the resulting bias. New `scripts/35_landmark_selection_tipping.R` bounds the outcome-level effect by assigning the excluded patients to extreme outcomes; the adverse bound was 2.23 (1.69–2.95) and the favourable bound 5.17 (3.95–6.77), against the observed 3.91 (2.91–5.26). The 0.01-month construction and its interpretation as a bound are stated in the supplement.
4. **External validation.** Cohort-specific estimates are now primary: GSE30161 2.18 (1.06–4.48), GSE63885 3.24 (1.84–5.72) and GSE23554 20.2 (4.12–99.1). The pooled estimate (4.25, 1.43–12.6; I²=80%) is explicitly secondary; the Hartung–Knapp–Sidik–Jonkman (0.30–59.3) and prediction (0.60–30.2) intervals include 1, and the GSE23554 interval is retained rather than trimmed.
5. **Expression-unrestricted analysis.** The existing pan-cancer TCGA-OV analysis without the expression requirement (n=396, 233 deaths; NCR HR 3.97, 2.98–5.27; plateau P=0.49) is now a co-sensitivity analysis in the main text.
6. **Model selection.** The text distinguishes selection from post-selection inference, reports post hoc Akaike weights (0.59, 0.30 and 0.12; adjusted 0.44, 0.40 and 0.16), the ΔAIC of 1.4 between CR threshold and the post hoc PD model, and the bootstrap frequencies (62%, 27% and 11%), and explains that BIC penalises parameters more strongly.
7. **Analysis plans.** "Pre-specified" wording was softened where no public registration exists. The dated internal plan excerpt remains in Data 5 and is labelled internal provenance.
8. **PFI and long-horizon RMST.** The proportional-hazards caveat and the single NCR patient at 60 months are stated in the main text; full results moved to the supplement.
9. **Presentation.** Abstract wording, leave-one-out naming and C-index ordering were corrected; "maintenance therapy" became "post-landmark therapy"; Figure 2's legend was compressed to about 230 words; supplementary citations now use an S prefix (S1–S46) and Table S1 states the source-definition-to-contrast mapping, with the primary marker restored in Table S3.

Build and layout changes:

- Stage 21 separates S-prefixed reference entries with blank lines, so they render as distinct paragraphs instead of one run-in block; the supplement grew from 33 to 34 pages.
- Stage 23 inserts a title hyphen breakpoint only when the title contains a hyphen, and renders Table S3 panel (e) as seven columns whose profile fractions sum to 1.0.
- The cover letter was compressed to one page (541 words including letterhead).

Claims and reporting:

- `config/manuscript_claims.json` now has 154 claims (was 152). The two additions audit the adverse and favourable tipping hazard ratios against `results/tables/ov_selection_tipping/landmark_selection_tipping.csv`; both are mapped to script 35 in the reporting index.
- Data 5 was rebuilt and now has 22 members (262,096 bytes), including the two tipping CSVs; the bundle SHA256 is `0a134c18...`.
- `docs/SHA256SUMS.txt` now has 381 paths (was 378): the two tipping CSVs and script 35 are added, with no omissions. In-tree `archive/`, dependency caches and build logs remain outside the inventory under the established rule.

Verification:

- Page counts are 19 (upload), 22 (review copy), 34 (supplement) and 1 (cover letter). Stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Stage 24 validates 154 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with no failures; stage 27 and `make check` pass.
- Word counts are 4,000 of 4,000 for the main text, 283 of 300 for the abstract, 1,020 for the display-item legends, 45 main and 46 supplementary references, and five display items.
- Rebuilt hashes (before → after): `title_page.md` `2d526511...` → `2cffd492...`, `methods_results.md` `290a8aaa...` → `e3203f63...`, `supplementary.md` `38bb4819...` → `517c8d2c...`, `cover_letter.md` `76a9b76b...` → `1a84f92d...`, `legends.md` `b6f2be55...` → `264b9999...`, `discussion.md` `d3530111...` → `3489bcb2...`, `introduction.md` `4944e6d1...` → `12d5def2...`, `highlights.md` `8201e013...` → `c1a368ab...`, stage 21 `9ce8c9a2...` → `f8348441...`, stage 23 `a887daa4...` → `47fff5a8...`, stage 33 `e97fea5f...` → `7a14108c...`, claims `80e141ac...` → `d7f44cb9...`, profile `c121bd01...` → `d2ca0e1b...`, Data 5 `1bda43e3...` → `0a134c18...`, manuscript Markdown `ddb3aa3a...` → `f58c8a53...`, manuscript TeX `9e68699d...` → `e9def53e...`, upload PDF `7d15c254...` → `b9379774...`, review copy `c8c85f1c...` → `4eba295c...`, supplement PDF `26f3fe63...` → `43e8c10c...`, cover-letter PDF `9bac6caf...` → `bed030be...`, manuscript DOCX `7af442fd...` → `927fc322...`, supplement DOCX `a7afddd1...` → `56ed649f...`, cover-letter DOCX `8650c899...` → `323a5778...`. DOCX hashes also vary with build timestamps.
- No Git commit, push, publication or DOI deposit was performed. The full pre-revision package is in `../archive/priority_review_20261102/before/`; the stage-33 script, claims configuration, Data 5 and checksum inventory from immediately before this final synchronization are in `../archive/priority_finalize_pre_20261102/`.

## Upload package preparation (2026-11-02)

The upload package in `../submission_package/ESMO_Open_20261102/` was assembled from the verified final outputs. Preparation exposed one presentation defect that was corrected before packaging:

- The manuscript and supplement PDFs carried the running head `ESMO Open submission draft`, while the manuscript DOCX still carried the stale pre-retitle head `Complete-response threshold in ovarian cancer`. Both now use the current short title, `Response grouping and survival in ovarian cancer`, set in `manuscript/source/latex_header.tex` and `scripts/22_generate_submission_docx.js`. The cover letter continues to omit the shared running head.
- Only the running-head string changed. Title page, body, abstract, captions, tables, references, numbers and claims are unchanged. Main text remains 4,000 words, the abstract 283 words and the legends 1,020 words; page counts remain 19 (upload), 22 (review copy), 34 (supplement) and 1 (cover letter).
- Stage 23 confirms that review-copy pages 1–19 are text-identical to the upload manuscript and that three figure pages are appended. Stage 24 validates 154 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with no failures; stage 27 and `make check` pass.
- Rebuilt hashes (before → after): stage 22 `14f0d50e...` → `4c57c01a...`, stage 23 `47fff5a8...` → `26667a99...`, `latex_header.tex` `9054455c...` → `8e752308...`, manuscript TeX `e9def53e...` → `4cc05bf6...`, upload PDF `b9379774...` → `84c356bb...`, manuscript DOCX `927fc322...` → `936bb99b...`, supplement TeX `1581d2a5...` → `36f0f6c4...`, supplement PDF `43e8c10c...` → `2f5582ef...`, supplement DOCX `56ed649f...` → `4a17c28c...`, cover-letter TeX `a29fe935...` → `89509e5e...`, cover-letter PDF `bed030be...` → `94ee94cc...`, cover-letter DOCX `323a5778...` → `17db7de8...`, STROBE DOCX `853e849f...` → `395acac6...`. The non-inventoried review copy changed from `4eba295c...` to `b1e8ce9f...`; DOCX hashes also vary with build timestamps.
- `docs/SHA256SUMS.txt` was regenerated with the same 381 paths, no additions or omissions, and all entries verify. Pre-change scripts, sources, outputs, checksum inventory and this log are in `../archive/upload_package_20261102/before_headers/`.
- No Git commit, push, publication or DOI deposit was performed.

## Front-matter review A+B implementation (2026-11-03)

Nine approved items from the title-to-keywords review were implemented; no C-package item was changed.

Text changes:

1. The title now reads "… in ovarian cancer: a TCGA-OV landmark analysis". The same cohort label was synchronized in the cover letter and supplementary title.
2. The abbreviation list gains HRD (homologous recombination deficiency), which the supplement uses.
3. The abstract Methods now name the post hoc PD-step model among the compared models.
4. The abstract Results now report the primary NCR hazard ratio as 3.91 (2.91–5.26), a summary contrast with CR, and present 3.25 (2.38–4.43) as the 307-patient clinical-matrix subset analysed co-primarily. This removes the previous juxtaposition of a 372-patient PR estimate with a 307-patient NCR estimate; within the 307-patient subset the corresponding values are PR 3.13 and NCR 3.25.
5. The abstract Conclusions now describe CR-versus-NCR as the most parsimonious adequate summary and specify that CR and PR should be reported separately in prognostic analyses.
6. Keywords are now ovarian cancer; complete response; partial response; objective response; landmark analysis; guarantee-time bias. Partial and objective response replace objective response rate and RECIST; the count remains six.
7. Highlight 1 now says "3.6-fold higher hazard of death" rather than "risk of death".
8. Highlight 2 now says "The objective-response constraint was rejected", matching the tested constraint rather than the grouping.
9. Highlights 3–5 now use "most parsimonious adequate summary", ask whether a separate PD hazard exists, and specify reporting "in prognostic analyses". All five highlights remain within 125 characters (114, 103, 105, 102 and 84).

Claims and reporting:

- `config/manuscript_claims.json` now has 156 claims (was 154). The two additions audit the abstract's primary NCR estimate against `tables/ov_therapy_end_landmark/topology_by_landmark.csv` and the 307-patient estimate against `tables/ov_therapy_end_landmark/topology_excluding_cdr_only.csv`; stage 24 reports 0 failed fields.
- Data 5 was rebuilt and still has 22 members (262,902 bytes uncompressed); the bundle SHA256 is `d1997ba8...` (was `0a134c18...`).

Build and layout:

- Page counts are 19 (upload), 22 (review copy), 34 (supplement) and 1 (cover letter). Stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Word counts are 4,000 of 4,000 for the main text, 294 of 300 for the abstract (was 283), 1,020 for the display-item legends, 45 main and 46 supplementary references, and five display items. The title is 138 characters and 18 words.
- Stage 24 validates 156 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with no failures; stage 27 and `make check` pass. The main manuscript and cover letter have no Overfull box. The supplement retains three 0.11334 pt alignment overfulls at lines 947–969, unchanged by the title-only edit.
- Rebuilt hashes (before → after): `title_page.md` `2cffd492...` → `77a63f00...`, `highlights.md` `c1a368ab...` → `929604c1...`, `cover_letter.md` `1a84f92d...` → `f8c2dc96...`, `supplementary.md` `517c8d2c...` → `e16a625d...`, claims `d7f44cb9...` → `500fa1a7...`, Data 5 `0a134c18...` → `d1997ba8...`, manuscript Markdown `f58c8a53...` → `5fafd8b9...`, manuscript TeX `4cc05bf6...` → `1f7b8e65...`, upload PDF `84c356bb...` → `80872d99...`, supplement Markdown `46afc60b...` → `cc8e75be...`, supplement TeX `36f0f6c4...` → `4d4e1b73...`, supplement PDF `2f5582ef...` → `4dde698e...`, cover-letter TeX `89509e5e...` → `5029fecb...`, cover-letter PDF `94ee94cc...` → `53b621bf...`, manuscript DOCX `936bb99b...` → `a6170552...`, supplement DOCX `4a17c28c...` → `f6b47e67...`, cover-letter DOCX `17db7de8...` → `b721307e...`, highlights text `fc5e1981...` → `6f21bddd...`, STROBE DOCX `395acac6...` → `5291d930...`. The non-inventoried review copy changed from `b1e8ce9f...` to `73607b4a...`; DOCX hashes also vary with build timestamps.
- `docs/SHA256SUMS.txt` was regenerated with the same 381 paths, no additions or omissions, and all entries verify. The six pre-change front-matter, claims and highlight files are in `../archive/ab_frontmatter_20261103/before/`.
- No Git commit, push, publication or DOI deposit was performed.

## Patients and methods review, Option A implementation (2026-11-03)

The author selected Option A from the adjudicated four-party review of the Patients and methods section: five P1 items, seven P2 items and 13 compensating compressions so that the main text remained exactly 4,000 words. No scientific result, estimate, interval, P value, sample size or claim direction changed.

P1 items:

1. The objective is now stated as a single primary endpoint. The heading became "Objective response obscured the PR–CR difference" (Results and the four STROBE location references), and "co-primary analysis" was replaced by "label-source sensitivity analysis" in the abstract, Results, discussion and cover letter.
2. The 307-patient clinical-matrix set is described as a label-source sensitivity analysis in the Methods, with the 306 strictly concordant patients identified in the Results and the cover letter (HR 3.21, 2.35–4.39).
3. The expression-unrestricted analysis is described consistently as a TCGA-OV analysis without a plausibility window, adjusted for age and stage only, rather than as a "co-sensitivity" analysis.
4. The response-label provenance is compressed into one sentence covering the chart-abstracted source categories, the 65 single-source labels, the one discordant label and the clinical-matrix audit.
5. Response dates are now stated as unavailable in the Methods, alongside the recorded therapy-end proxy and the residual guarantee-time bias caveat.

P2 items:

1. Equivalence is defined with the prespecified 90% CI margin 0.67–1.50, labelled pragmatic rather than validated, with 0.50–2.00 as a relaxed sensitivity margin.
2. The multiple-comparison exception is stated as applying only to the exploratory response-partition scan (Benjamini–Hochberg); secondary and exploratory analyses are descriptive.
3. The molecular-analysis cohort restriction and its 454-patient intersection are stated once, removing the repeated "of these" construction.
4. Stage and residual-disease groupings are described as defining analysis populations only.
5. The post hoc delayed-entry models are stated compactly at the landmark by stratum.
6. The external-cohort rationale now says one series was excluded because it re-used a large fraction of the same tumours.
7. The four-category paired gain is restored in the Results: median gains were 0.067 (CR threshold), 0.065 (four-category) and 0.028 (objective response), with a new claims entry for 0.065.

Compressions and layout:

- Thirteen compensating compressions removed redundant qualifiers ("documented in the analysis code" → "documented in code", "chart-abstracted clinical outcomes" → "chart-abstracted outcomes", "required for the molecular analyses" → "required for molecular analyses", "was retained as CR" + audit sentence, "All comparisons therefore estimate" → "Landmark comparisons therefore estimate", "did not distinguish models", "the 60-month estimate is in", "29 excluded for missing covariates" → "29 excluded", "assessed using" → "assessed by", "(GEO)", "largely re-used" → "re-used", "longer than the median recorded first-line duration" and the shortened delayed-entry sentence).
- Word counts are 4,000 of 4,000 for the main text, 295 of 300 for the abstract, 1,020 for the display-item legends, 6,276 for the supplement and 545 for the cover letter. Main and supplementary references remain 45 and 46; display items remain five.
- Page counts are 19 (upload), 22 (review copy), 34 (supplement) and 1 (cover letter). Stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- `config/manuscript_claims.json` now has 157 claims (was 156). The addition audits the four-category paired gain; the three supplement claims for the 65-patient exclusion were re-anchored to the new sentence, and the Figure 2 paired-gain and abstract subset patterns were re-anchored to the new prose. Stage 24 reports 0 failed fields.
- Stage 24 validates 157 claims and 18 provenance entries with no failures; stage 26 audits 18 figures with no failures; stage 27 and `make check` pass. The main manuscript and cover letter have no Overfull box. The supplement retains three 0.11334 pt alignment overfulls at lines 947–969, unchanged by this text-only revision.
- Rebuilt hashes (before → after): `methods_results.md` `e3203f63...` → `c7bbbdec...`, `title_page.md` `77a63f00...` → `a7fd5b34...`, `discussion.md` `3489bcb2...` → `33acfbc5...`, `supplementary.md` `e16a625d...` → `127bcd11...`, `cover_letter.md` `f8c2dc96...` → `5364d938...`, claims `500fa1a7...` → `d3a9eb59...`, STROBE Markdown `968353be...` → `baa151ba...`, Data 5 `d1997ba8...` → `27a495a6...`, manuscript Markdown `5fafd8b9...` → `6119406d...`, manuscript TeX `1f7b8e65...` → `3395b8ef...`, upload PDF `80872d99...` → `1ffb4349...`, supplement Markdown `cc8e75be...` → `ed82aab8...`, supplement TeX `4d4e1b73...` → `161f68f5...`, supplement PDF `4dde698e...` → `55b9caf2...`, cover-letter TeX `5029fecb...` → `af27da63...`, cover-letter PDF `53b621bf...` → `cf2a6c35...`, manuscript DOCX `a6170552...` → `9f761214...`, supplement DOCX `f6b47e67...` → `32b9dc9f...`, cover-letter DOCX `b721307e...` → `c3a469e3...`. Data 5 retains 22 members (263,260 bytes uncompressed).
- Figure 1 was not re-rendered: its counts (630/595/567/454/453/418/397/383/372; panel C OV 396) and the frozen panel C region are unchanged, and 307/306 were never displayed in the figure.
- Pre-change source, submission, configuration, documentation and upload-package files are in `../archive/methods_review_A_pre_20261103/`.
- No Git commit, push, publication or DOI deposit was performed.

## Results review, Option A implementation (2026-11-03)

The author selected Option A from the adjudicated four-party review of the Results section: three P1 and three P2 items, a Methods typo and a supplement cross-reference, balanced so that the main text remained exactly 4,000 words. No estimate, interval, P value, sample size or claim direction changed.

P1 items:

1. The expression-unrestricted TCGA-OV sentence now labels its four reported statistics as unadjusted and describes the covariate allowance as "only age and stage". The adjusted counterparts (NCR HR 4.16, plateau P=0.29, AIC favouring M_PD) remain in the Supplementary Results and Table S2.
2. "The PD step was therefore not present" became "not detected" for the landmark analysis, matching the Discussion and the minimal detectable HR of 1.98 for PD versus PR+SD.
3. The selection sentence now compares excluded with included NCR patients (median OS 637 vs 895 days) instead of excluded NCR with excluded CR patients, so the conservative direction follows from within-group selection; the tipping bounds (2.23–5.17) are unchanged.

P2 items:

1. The 36-month calibration sentence now says the point estimates suggested over-prediction in PR (74.2% vs 62.1%) and under-prediction in PD (71.9% vs 83.8%), because both predicted values lie inside the observed 95% intervals (44.0–74.3 and 60.3–93.4).
2. The supplement now names the six restriction subsets with their sizes (300, 326, 367, 346, 318 and 368) and their intersection (214), replacing the dangling "listed in the main text" cross-reference.
3. The 306-concordant estimate (HR 3.21, 2.35–4.39) was re-derived exactly from Supplementary Data 1 (concordant label source; time = OS_days − therapy_end; n=306, 186 events; HR 3.215, 2.355–4.388) and is recorded here; it is not yet persisted as a table row or claims entry.

Other edits:

- "one lacked OS" became "one lacked OS time" in the cohort sentence (the patient had a recorded death and a missing death date), and the diagnosis-origin paragraph now reads "all 453 labelled patients with OS time", removing the duplicated parenthetical.
- The Methods typo "is in in the Supplementary Results" became "is given in the Supplementary Results".
- An earlier review claim that "29 NCR (81%)" overstated mortality was withdrawn: the patient with missing OS time had vital_status DECEASED and OS_event=1, so 29 events among 36 patients is correct.

Claims and counts:

- Three claim patterns were re-anchored: the cohort sentence ("one lacked OS time") and the two calibration sentences ("over-prediction in PR", "under-prediction in PD"); the total remains 157.
- Word counts are 4,000 of 4,000 for the main text, 295 of 300 for the abstract, 1,020 for the display-item legends, 6,306 for the supplement and 545 for the cover letter. Main and supplementary references remain 45 and 46.
- Page counts are 19 (upload), 22 (review copy), 34 (supplement) and 1 (cover letter). Stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Stage 24 validates 157 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with no failures; stage 27 and `make check` pass. The main manuscript, review copy and cover letter have no Overfull box. The supplement retains three 0.11334 pt alignment overfulls, now at lines 950–972.
- Rebuilt hashes (before → after): `methods_results.md` `c7bbbdec...` → `150758e7...`, `supplementary.md` `127bcd11...` → `7b417273...`, claims `d3a9eb59...` → `b505d8e0...`, Data 5 `27a495a6...` → `fe48b609...`, manuscript Markdown `6119406d...` → `18ea426f...`, manuscript TeX `3395b8ef...` → `4c47d79a...`, upload PDF `1ffb4349...` → `3bfc756c...`, manuscript DOCX `9f761214...` → `5fd6d7d9...`, supplement Markdown `ed82aab8...` → `b3cce4dc...`, supplement TeX `161f68f5...` → `17128bb5...`, supplement PDF `55b9caf2...` → `c138b96e...`, supplement DOCX `32b9dc9f...` → `e7d62ce2...`, cover-letter DOCX `c3a469e3...` → `13bcb6b3...`. Data 5 retains 22 members (263,254 bytes uncompressed).
- The cover-letter TeX and PDF are unchanged; the non-inventoried review copy was rebuilt (`876b7744...`), and DOCX hashes also vary with build timestamps.
- Pre-change source, configuration and supplement files are in `../archive/results_review_20261103/before/`.
- No Git commit, push, publication or DOI deposit was performed.

## Discussion six-party review, Option A implementation (2026-11-03)

The author selected Option A from the adjudicated BioHex six-party review of the Discussion (debate mode, three rounds, all six models present; the run archive is `../review_runs/discussion_biohex_20261103/`). Four P1 and five P2 items were implemented. No estimate, interval, P value, sample size or claim direction changed, and the main text remains exactly 4,000 words.

P1 items:

1. The tipping sentence now states the joint extreme assignment that produced the estimate: all 46 excluded CR patients assigned immediate death and all 36 excluded NCR patients immediate censoring still left the NCR hazard at 2.23 (1.69–2.95). The previous sentence described only the CR side, which did not match the analysis in the Results.
2. The external-evidence paragraph now states that the Hartung–Knapp–Sidik–Jonkman interval for the pooled HR (0.30–59.3) included 1, and that GSE63885, the only external four-class cohort, rejected the plateau (P=0.010), so the internal NCR topology was not replicated. The previous sentence reported only that GSE63885 "permitted four-category topology testing".
3. The E-value paragraph no longer says that associations of the required strength "are unlikely" or derives the prognostic interpretation from the E-value. It now states that the E-value gives the strength such confounding would need, not its probability, notes that post-landmark therapy may mediate rather than confound, and keeps "prognostic rather than causal" while adding that residual confounding is not excluded.
4. The conclusion now says the CR-threshold model "did not discriminate better than four categories", matching the abstract, instead of "discrimination indistinguishable from four categories".

P2 items:

1. The 69/77 CR–residual sentence now cites the Supplementary Results. The number was verified there ("Only 8 of 77 patients without macroscopic residual were NCR"), so this is a source citation, not a new result.
2. The label-source HR is now labelled unadjusted (3.25; adjusted 3.45), matching the Results.
3. Both Discussion occurrences of "most parsimonious summary" now read "most parsimonious adequate summary", matching the abstract.
4. The expression-unrestricted sensitivity is now described as a "similar unadjusted estimate (HR 3.97, 2.98–5.27)", matching the Results.
5. The recommendation sentence was compressed without changing its scope; no claim was added.

Word balance and verification:

- Offsets were the deletion of the "formal comparison at a patient-specific landmark" sentence, the date-scenario clause and "documented in code", plus compression of the Villalobos, TCGA-label, recommendation and molecular sentences. After the first build reported 4,001 words, one further word ("therefore") was removed; the final text is net 0 against the 4,000-word baseline.
- Counts are 4,000 of 4,000 main-text words, 295 of 300 abstract words, 1,020 legend words, 45 main and 46 supplementary references, and 5 display items.
- Page counts are 19 (upload), 22 (review copy), 34 (supplement) and 1 (cover letter). Stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Stage 24 validates 157 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with no failures; stage 27 and `make check` pass. The main manuscript, review copy and cover letter have no Overfull box; the supplement retains its three pre-existing alignment overfulls.
- Rebuilt hashes (before → after): `discussion.md` `33acfbc5...` → `20539596...`, manuscript Markdown `18ea426f...` → `7c2795ad...`, manuscript TeX `4c47d79a...` → `66988625...`, upload PDF `3bfc756c...` → `9a3a120c...`, manuscript DOCX `5fd6d7d9...` → `72a956e0...`, review copy `876b7744...` → `698d1c0f...`, supplement DOCX `e7d62ce2...` → `713cd8a1...` and cover-letter DOCX `13bcb6b3...` → `f91398a4...`. The supplement Markdown, TeX and PDF and the cover-letter PDF are unchanged. The DOCX values are from a final no-op rebuild; extracted document text was verified identical to the preceding build, so only ZIP metadata changed.
- Pre-change `discussion.md` is in `../archive/discussion_a_pre_20261103/`.
- No Git commit, push, publication or DOI deposit was performed.

## Declarations review, Option A implementation (2026-11-03)

The author selected Option A from the adjudicated four-party review of the declarations section (Ethical approval through the AI declaration; three independent blind reviews, a cross-examination round and main-agent adjudication; the run archive is `../review_runs/sifang_declarations_20261103/`). The review found no P0/P1 item. Five P2 items were implemented, all confined to `manuscript/source/declarations.md`; no result, estimate, citation, table, figure or main-text sentence changed.

Changes:

1. The `Ethics statement` heading became `Ethical approval`, the heading used by published ESMO Open Original Articles.
2. The `Data sharing statement` heading became `Data availability`, likewise the published house style.
3. The ethics sentence now reads "No separate ethics approval or informed consent was required for this secondary analysis." The previous wording ("No additional...") implied a prior approval existed without identifying it, and the trailing clause duplicated the opening sentence's description of the data.
4. The data-availability lead now reads "All data used in this study are publicly available through the sources listed below:", which states what can actually be guaranteed for a secondary analysis rather than asserting that every source record is unrestricted.
5. "Existing results" in the Supplementary Data 5 sentence became "Analysis output tables", naming the actual contents (analysis result tables, the locked gene-set audit and the data dictionary).
6. The AI declaration now separates manuscript preparation ("language editing, consistency checking, and document formatting of the manuscript") from code support ("The same tool was used to support code development and refactoring, with all code reviewed by the authors"), so that the writing-process declaration does not mix in development work while retaining full disclosure. The authorship-responsibility and verification sentences are unchanged.

Items reviewed and not changed: the Funding paragraph retains grant details only, matching published ESMO Open articles (a funder-role sentence is optional, not required); the corresponding author is identified on the title page and is not repeated in the contribution list; CRediT roles follow actual contributions; `Disclosure` is the journal's heading; the GDC access date "October 2026" is factual; and no prior-presentation or consent-for-publication statement applies to a de-identified public-data secondary analysis.

Verification:

- Counts are 4,000 of 4,000 main-text words, 295 of 300 abstract words, 1,020 legend words, 45 main and 46 supplementary references, and 5 display items. Stage 21 reports only its pre-existing conservative main-text-plus-legends flag (5,020 of 4,000), which adds 1,020 legend words to a main-text-only journal limit.
- Page counts are 19 (upload), 22 (review copy), 34 (supplement) and 1 (cover letter). Stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Stage 24 validates 157 claims (0 failed fields) and 18 provenance entries (0 failed); stage 26 audits 18 figures with no failures; stage 27 and `make check` pass. The main manuscript, review copy and cover letter have no Overfull box; the supplement retains its three pre-existing 0.11334 pt alignment overfulls.
- Rebuilt hashes (before → after): `declarations.md` `1d787708...` → `6d3901eb...`, manuscript Markdown `7c2795ad...` → `1be98841...`, manuscript TeX `66988625...` → `ee66f05f...`, upload PDF `9a3a120c...` → `cc2e2755...`, manuscript DOCX `72a956e0...` → `525089b6...`, review copy `698d1c0f...` → `da1a24ca...`, supplement DOCX `713cd8a1...` → `28d68b9d...` and cover-letter DOCX `f91398a4...` → `d0ce5526...`. The supplement Markdown, TeX and PDF and the cover-letter PDF are unchanged. Extracted document text of the supplement and cover-letter DOCX was verified identical to the previous build, so those two changes are ZIP metadata only.
- Pre-change `declarations.md` is in `../archive/declarations_a_pre_20261103/`.
- No Git commit, push, publication or DOI deposit was performed.

## Figure 1–3 legend review, lossless compression plus missing definitions (2026-11-03)

The author asked the four-party team whether the Figure 1–3 legends could be trimmed further and selected the adjudicated option "add missing definitions + lossless compression". Three independent reviews (GLM-5.3 through the `claude` CLI, Qwen3.6-27B through `codex`, and LongCat-2.0 through the local gateway) were followed by a cross-examination round and main-agent adjudication; the run archive is `../review_runs/sifang_legends_20261103/`. Only `manuscript/source/legends.md` and the claim patterns that anchor to it changed. No number, interval, hazard ratio, sample size, model name or time origin changed, and no estimate was re-fitted.

The review also found one correctness defect: Figure 2 used `CV` (in "Response-only CV C-indices") and `HR` (in "Death HRs versus CR") without defining either in its abbreviation list. Both definitions were added, as were the compressed phrasings below.

Changes:

1. Figure 1A now opens with the cohort counts and then states that they followed "sequential, mutually exclusive exclusions", instead of narrating the exclusions first; "recorded" before "end of first-line treatment" was dropped because the landmark definition follows. All flow counts and the 60–365-day window are retained.
2. The Figure 1 cohort-table guide now reads "All/Serous denote any/serous histology, Landmark patients alive beyond 183 days (later deaths counted), and Total the sum of the three Landmark values."
3. Figure 2's curve sentence now reads "Curves extend to 120 months but stop at last follow-up (right-censoring; no 120-month administrative censoring)."
4. Figure 2C now reads "Death HRs versus CR (95% CI; log scale) adjusted for age, stage and residual disease in the four-category model", removing the "Adjusted … adjusted" repetition, and the sentence "Settings differ in population and time origin" was deleted; the three settings and their n remain enumerated.
5. Figure 2E now reads "over clinical-only (n=343)" instead of "over the clinical-only model (n=343)".
6. Figure 2 abbreviations now include "CV, cross-validation; HR, hazard ratio".
7. Figure 3A now reads "and REML pooling (k=3; n=138). The pooled Wald interval is 1.43–12.62;" instead of "cohort-level REML" and "The plotted pool interval is the Wald interval".
8. Figure 3C now reads "(diagnosis n=453; 6-month landmark n=426; therapy end n=372)", shortening two setting labels that are printed in the panel.
9. The Figure 1 abbreviation list was reordered alphabetically (PD before PR) without changing any definition.

The predicted saving was 24 words; the first Figure 1 edit removed 2 words more than estimated, so the realized saving is 26 words. Figure legends are 256, 231 and 303 words (268, 238 and 310 before), 790 in total; with the unchanged 206-word table legends the stage-21 count is 994 (1,020 before). Main text stays at 4,000 of 4,000 words and the abstract at 295 of 300; references remain 45 and 46 and display items 5.

Verification:

- Page counts are 19 (upload), 22 (review copy), 34 (supplement) and 1 (cover letter). Stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Stage 24 validates 157 claims (0 failed fields) and 18 provenance entries (0 failed) after two anchoring patterns were updated (`figure2_c_diagnosis_n` and `figure2_e_cv_design`); stage 26 audits 18 figures with no failures; stage 27 and `make check` pass. The main manuscript, review copy and cover letter have no Overfull box; the supplement retains its three pre-existing 0.11334 pt alignment overfulls.
- Data 5 was rebuilt because `reporting_index.csv` embeds the claim configuration, and the bundle retains its 22 members. The supplement Markdown, TeX and PDF and the cover-letter Markdown, TeX and PDF are unchanged; the supplement and cover-letter DOCX were re-zipped and their extracted text was verified identical to the previous build.
- Rebuilt hashes (before → after): `legends.md` `264b9999...` → `1a7dbc48...`, claims `b505d8e0...` → `8da1e6a7...`, Data 5 `fe48b609...` → `f9b1128e...`, manuscript Markdown `1be98841...` → `8f48fd69...`, manuscript TeX `ee66f05f...` → `ecfc548e...`, upload PDF `cc2e2755...` → `20e57599...`, manuscript DOCX `525089b6...` → `dbec9be3...`, review copy `da1a24ca...` → `44c20f56...`, supplement DOCX `28d68b9d...` → `c364562e...` and cover-letter DOCX `d0ce5526...` → `282f5761...`.
- The pre-change legends file is in `../archive/legends_a_pre_20261103/legends.md` (SHA256 `264b9999d7f19a866d3aa3f058b69abdaa829546fb4781c1be5332bb3ead1a4f`).
- No Git commit, push, publication or DOI deposit was performed.

## Figure 1 second review, legend definitions (2026-11-04)

The author asked the four-party team to review Figure 1 again after the previous legend compression. Three independent blind reviews (GLM-5.3, Qwen3.6-27B and LongCat-2.0) were followed by a cross-examination and main-agent adjudication; the run archive is `../review_runs/sifang_figure1_20261104/`. The panel numbers, cohort-table arithmetic and locked counts were re-derived from `Figure1_flow_counts.csv` and `external_cohort_audit.csv`; no number, estimate, time origin or model changed.

All three reviewers initially argued that panel C's legend overstated the time origin because the four-category box does not print `from therapy end`. Cross-examination refuted this: script 20 filters both `pc_topology` and `pc_dichotomy` to `landmark == "therapy_end"`, and the 396/262/102 rows used by the panel are exactly the therapy-end rows; the supplement's diagnosis-origin treated-BLCA analysis (n=109) is not the plotted 102. The reviewers withdrew the claim. A reported panel-width contradiction was also refuted: the actual columns are about 87, 57 and 46 mm within the 189.8 mm canvas.

Changes (legend only; the artwork was not rebuilt):

1. Figure 1B now says the fixed 6-month landmark is counted `from diagnosis`, matching the panel header.
2. The cohort-table guide now reads `In the table, All/Serous denote any/serous histology; Landmark, serous patients alive beyond 183 days (later deaths counted); Total, their sum.` It identifies the Landmark column as the serous subset and shortens the sentence.
3. `these analyses used TCGA-CDR eligibility rules` became `TCGA-CDR eligibility rules apply`, and `tumours with a canonical response label` became `canonically labelled tumours` to offset added definitions.
4. The abbreviation list now defines `GDC, Genomic Data Commons`, `OS, overall survival` and `Xena, UCSC Xena browser`; `OS` and `GDC` are printed in panels A and B but were previously undefined. `TCGA` remains unexpanded because it is used as the study name throughout the manuscript and in Table 1.

Figure 1 is 258 words (256 before), figure legends 790 (788 before), and the stage-21 count 996 (994 before) with the unchanged 206 table legends. Main text remains 4,000 of 4,000 words, the abstract 295 of 300, references 45 and 46, and display items 5.

Verification:

- Page counts are 19 (upload), 22 (review copy), 34 (supplement) and 1 (cover letter). Stage 23 confirms pages 1–19 of the review copy are text-identical to the upload manuscript and three figure pages are appended.
- A text diff against the archived PDF shows exactly two changes: the printed legend word count (994 → 996) and the Figure 1 legend. Stage 24 validates 157 claims (0 failed) and 18 provenance entries (0 failed); stage 26 audits 18 figures with no failures; stage 27 and `make check` pass. The main manuscript has no Overfull box; the supplement retains its three pre-existing 0.11334 pt alignment overfulls and its extracted text is identical to the pre-change PDF.
- Data 5 was rebuilt with an identical bundle hash (`f9b1128e...`), because neither the claim configuration nor any source CSV changed. The supplement and cover-letter DOCX were re-zipped; their extracted text is identical to the pre-change PDFs.
- Rebuilt hashes (before → after): `legends.md` `1a7dbc48...` → `cfd59202...`, manuscript Markdown `8f48fd69...` → `795ffe52...`, manuscript TeX `ecfc548e...` → `14e2bb82...`, upload PDF `20e57599...` → `80e34b5a...`, manuscript DOCX `dbec9be3...` → `4ef8f79d...`, review copy `44c20f56...` → `bd15c9a4...`, supplement DOCX `c364562e...` → `d7d01278...`, cover-letter DOCX `282f5761...` → `ec7ea5b5...`. The claims configuration remains `8da1e6a7...`.
- The pre-change legends file and four PDFs are in `../archive/figure1_review2_pre_20261104/`.
- One P2 typographic defect remains deliberately unfixed: panel A prints `No recorded end date n = 21` without the comma used by the other seven exclusion boxes. A single comma would require re-freezing panel A and updating the profile hash, so it is recorded for the next artwork change rather than rebuilt alone.
- No Git commit, push, publication or DOI deposit was performed.

## Academic-review response, major revision implementation (2026-11-04)

A structured academic-paper review of the main manuscript, supplement and cover letter was followed by author-authorised implementation of the recommended major revision. No analysis was re-fitted and no estimate, interval or *P* value changed; the 306-patient estimate and the per-cohort survival inputs were already locked outputs and are now traced to their source tables.

Changes:

1. The 306-patient strictly concordant label set is reported with its provenance. Results now states that restricting to 307 clinical-matrix-labelled patients gave an NCR HR of 3.25 (2.38–4.43; adjusted 3.45, 2.46–4.83) and that the 306 with concordant labels gave 3.21 (2.35–4.39). Table S3 gains panel (f), which reports all four codings on both shared complete-case sets (n, deaths, NCR HR, plateau and objective-response constraint *P* values, best AIC and BIC), and Data 5 exports both label-source result files.
2. Table S1 gains panel (d), listing the per-cohort inputs to the pooled NCR-versus-CR estimate: patients and deaths after the 183-day landmark, the natural-log HR and its standard error, and the cohort HR (95% CI). The pooled estimate is computed from the log HR and SE columns; n and deaths agree with panel (b). Data 5 exports the same three-cohort, 183-day subset as `external_survival_inputs.csv`.
3. The abstract now states that the objective-response constraint was rejected (*P* = 8.5×10⁻¹⁰) because of the PR–CR difference, that a single NCR hazard was not rejected (*P* = 0.67) and that equivalence was not established, and that the pooled external interval included 1 under Hartung–Knapp–Sidik–Jonkman and prediction intervals. The Conclusions retain CR-versus-NCR as the most parsimonious model tested while stating that the plateau was underpowered, was rejected in the only external four-class cohort and was not established in patients without macroscopic residual disease.
4. The Discussion E-value sentence now names the confounder risk ratio explicitly (at least 4.2 common to both NCR and death, or 3.3 to move the interval to the null), replacing the previous unanchored wording; the claim pattern was re-anchored accordingly.
5. Highlight 3 now reads "CR-versus-NCR was the most parsimonious model tested, but the plateau was underpowered and not replicated externally." The other four highlights are unchanged.
6. The cover letter was compressed to one page at 10.5 pt while retaining the reverse-allocation estimate (HR 5.17, 3.95–6.77), the 306-patient concordance check, the public-data statement and the Data 1–5 and STROBE availability statement.
7. Table S6 was retitled to state that it contains five prespecified scores and four exploratory rows. The supplementary table heading and caption remain at the shared 11 pt.
8. Table S3 was repaginated without changing any cell: the caption and panel (a) share the first page, panels (b) and (c) the second, and panels (d)–(f) the third. This removes the two-row spill that the earlier (c)-break layout left at the top of the following page. Table S1 keeps panels (c) and (d) together on one page. The supplement is now 36 pages (34 before).

Verification:

- Main text is 4,000 of 4,000 words, the abstract 299 of 300, display-item legends 996, main and supplementary references 45 and 46, and display items 5. Stage 21 reports only its pre-existing conservative main-text-plus-legends flag (4,996 of 4,000), which adds 996 legend words to a main-text-only journal limit.
- Page counts are 19 (upload), 22 (review copy), 36 (supplement) and 1 (cover letter). Stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Stage 24 validates 160 claims (was 157) and 18 provenance entries with 0 failed fields; stage 26 audits 18 figures with no failures; stage 27 and `make check` pass. The main manuscript, review copy and cover letter have no Overfull box; the supplement retains its three pre-existing 0.11334 pt alignment overfulls.
- Data 5 was rebuilt with 25 members (22 before) and 268,966 bytes uncompressed; its bundle SHA256 is `22c3a9d8...` (was `f9b1128e...`). The three additions are the per-cohort survival inputs and the two label-source result files.
- Rebuilt hashes (before → after): `methods_results.md` `150758e7...` → `ec138bf4...`, `discussion.md` `20539596...` → `98925ed6...`, `title_page.md` `a7fd5b34...` → `1ad77e71...`, `highlights.md` `929604c1...` → `a940bff3...`, `supplementary.md` `7b417273...` → `13195978...`, `cover_letter.md` `5364d938...` → `7403713c...`, claims `8da1e6a7...` → `844eb81c...`, Data 5 `f9b1128e...` → `22c3a9d8...`, manuscript Markdown `795ffe52...` → `feecb1b5...`, manuscript TeX `14e2bb82...` → `5bec88cf...`, upload PDF `80e34b5a...` → `b8eff4f2...`, review copy `bd15c9a4...` → `1a742396...`, supplement PDF `c138b96e...` → `3ab686bc...`, cover-letter PDF `cf2a6c35...` → `681343a6...`, STROBE DOCX `395acac6...` → `952bafb4...` (ZIP metadata only; extracted text unchanged). The manuscript, supplement and cover-letter DOCX hashes changed with creation time and are not used as verification evidence. `legends.md`, `config/analysis.yml`, `config/supplementary_data_dictionary.json` and the three analysis CSVs are unchanged.
- The upload package was refreshed: 22 files verify against `SHA256SUMS.txt`, all 20 `MANIFEST.csv` byte counts and hashes match, and the new outer ZIP SHA256 is `539b4923...`. The package README records the sixth revision, 36 supplement pages, the 299-word abstract and the revised third highlight.
- `docs/SHA256SUMS.txt` was regenerated with 382 paths (381 before; the addition is `results/tables/ov_therapy_end_landmark/topology_strictly_concordant.csv`), and all entries verify. Pre-change sources, PDFs, configuration and the previous package are in `../archive/review_revision_pre_20261104/`.
- No Git commit, push, publication or DOI deposit was performed.

## Natural-prose language polish (2026-11-04)

A language-only pass removed mechanical, template-like phrasing from the submission text. No analysis was re-run, no estimate, interval, *P* value, citation or claim was altered, and no file in `results/` or `config/` changed.

Scope:

1. Six files were edited: `introduction.md`, `methods_results.md`, `discussion.md`, `title_page.md` (abstract only), `highlights.md` and `cover_letter.md`. `legends.md` and `supplementary.md` were left byte-identical because they carry anchored numeric statements; rewording them would have required re-anchoring claims without improving the argument.
2. The main structural changes were the removal of enumerated connectives ("First, … Second, …") in the Introduction, the removal of the empty signpost "This study has limitations" in the Discussion, and the replacement of stacked noun phrases with finite verbs. The Discussion's residual-disease paragraph was rebuilt so that the confound, its magnitude and the limits of adjustment follow one chain of reasoning rather than three parallel assertions.
3. Rhythm was varied by splitting long sentences and merging short ones. In the main text the sentence count changed from 167 to 174, mean sentence length from 24.0 to 22.9 words (SD 10.9 to 9.9), sentences of 40 words or more from 18 to 11, and semicolons from 78 to 75; mean paragraph length was effectively unchanged (105.3 to 104.9). No "Moreover" or "Furthermore" was introduced. Hedging density was deliberately preserved (about 17 negations per 1,000 words before and after), because the statistical claims depend on it.
4. The register remains formal British-English academic prose; no idioms, contractions, rhetorical questions or first-person anecdotes were added. The existing Generative-AI declaration in `declarations.md` was retained unchanged and remains accurate. The pass was language editing only: it does not claim to defeat AI-content detectors and no detector score was used as an acceptance criterion.

Verification round 1 (naturalness):

- Four review passes (fidelity, naturalness, statistical wording, journal register) read the edited files in full, followed by one cross-examination round. Reviewers flagged residual template phrasing, including "the plateau was underpowered" in the abstract, conclusion and highlight 3; a test, not a plateau, is underpowered, and the wording was changed to "the plateau test was underpowered".
- The final text contains no enumerated signposting, no empty transition sentences and no repeated sentence-opening formula beyond what the statistical exposition requires.

Verification round 2 (fidelity):

- The multiset of numeric tokens and the set of `@citation` keys were compared before and after in all six edited files: zero differences. Every hazard ratio, confidence interval, *P* value, sample size, page-level count and reference key is unchanged.
- Five fidelity defects introduced during drafting were found and corrected before the final build: (i) "argue against confounding … without excluding it" strengthened the inference and was restored to "similar point estimates across strata do not exclude residual confounding by surgery"; (ii) "Residual disease was recorded inconsistently" lost the original hedge and was restored to "appeared to be recorded inconsistently"; (iii) "does not eliminate selection bias" was restored to "does not establish that selection bias was eliminated"; (iv) the conclusion regained the cross-model claim "Of the models tested, CR-versus-NCR was the most parsimonious"; (v) highlight 3 regained both "most parsimonious model tested" and "plateau test".
- Final counts are main text 3,991 of 4,000 words, abstract 300 of 300, display-item legends 996, main and supplementary references 45 and 46, display items 5, and five highlights of at most 125 characters. Stage 21's only failure remains its pre-existing conservative main-text-plus-legends check (4,987 of 4,000), which adds the 996 legend words to a main-text-only limit.
- Page counts are 19 (upload), 22 (review copy), 36 (supplement) and 1 (cover letter). Stage 23 confirms that pages 1–19 of the review copy are text-identical to the upload manuscript and that three figure pages are appended.
- Stage 24 validates 160 claims and 18 provenance entries with 0 failed fields; stage 26 audits 18 figures with no failures; stage 27 and `make check` pass. The supplement PDF is unchanged.
- Rebuilt hashes (before → after): `introduction.md` `12d5def2...` → `4fd72634...`, `methods_results.md` `ec138bf4...` → `bc5dff88...`, `discussion.md` `98925ed6...` → `a30fda91...`, `title_page.md` `1ad77e71...` → `76285883...`, `highlights.md` `a940bff3...` → `60382347...`, `cover_letter.md` `7403713c...` → `a248fc57...`, manuscript Markdown `feecb1b5...` → `3c743eae...`, manuscript TeX `5bec88cf...` → `0a208ea4...`, upload PDF `b8eff4f2...` → `2c38c2f3...`, review copy `1a742396...` → `2465b26f...`, cover-letter PDF `681343a6...` → `62e3fc99...`, and regenerated cover-letter TeX `9c1691f4...`. The supplement PDF remains `3ab686bc...`. DOCX hashes changed with ZIP creation time and are not used as verification evidence. `legends.md`, `supplementary.md`, `declarations.md`, `config/manuscript_claims.json` and all result tables are unchanged.
- The pre-change sources, four PDFs, claims configuration and submission profile are in `../archive/deai_polish_pre_20261104/`.
- The external upload package was refreshed: 22 files verify against `SHA256SUMS.txt`, all 20 `MANIFEST.csv` byte counts and hashes match, and the new outer ZIP SHA256 is `133c294a...`. The package README records the seventh revision, 3,991 main-text words, the 300-word abstract and the revised highlights.
- No Git commit, push, publication or DOI deposit was performed.

## Repository metadata configuration (2026-11-04)

The repository-level documentation was brought into line with the submitted manuscript. `README.md` had retained the pre-retitle working title ("A complete-response threshold describes post-treatment survival more parsimoniously than objective response in ovarian cancer"); both the heading and the blockquoted title now use the submitted title, and the scientific-scope paragraph states the final locked estimates and their limits rather than the earlier framing. The quick-start description of `make clinical` now names the landmark selection tipping analysis that script 35 adds.

Two metadata files were added: `CITATION.cff` (Citation File Format 1.2.0, with the author list, the corresponding author's ORCID, the MIT licence and the study keywords) and `.gitattributes` (LF endings for text sources; binary treatment for PDF, DOCX, image, archive and R data artefacts). `config/release_policy.json` now lists both as required paths, so a release snapshot cannot silently omit them. `LICENSE`, `LICENSE.md` and `.gitignore` were reviewed and left unchanged.

Verification:

- `make repo-check` passes in working-checkout mode, and `CITATION.cff` parses as valid YAML.
- No analysis output, manuscript source, figure, table, supplement or upload-package file changed. README numbers are the locked estimates already validated by stage 24.
- `docs/SHA256SUMS.txt` was regenerated with 384 paths (382 before; the additions are `.gitattributes` and `CITATION.cff`), and all entries verify.
- The pre-change README, release policy, this document and checksum inventory are in `../archive/repo_metadata_pre_20261104/`.

## Chinese review edition (2026-11-05)

A Chinese review edition was added for author-side reading. It is not a submission file: the English manuscript, supplement and cover letter remain the files of record, and the Chinese PDFs carry a running head that reads "中文审阅稿 · 非投稿文件".

Scope:

1. `manuscript/zh/source/main_zh.md`, `supplementary_zh.md` and `cover_letter_zh.md` are full translations. All estimates, confidence intervals, *P* values, sample sizes, citations and statistical caveats are retained; reference lists stay in English exactly as submitted.
2. `manuscript/zh/ESMO_Open_manuscript_zh.pdf` (18 pages), `ESMO_Open_supplementary_appendix_zh.pdf` (27 pages) and `ESMO_Open_cover_letter_zh.pdf` (1 page) are built with Pandoc 3.6.4 and XeLaTeX using Songti SC for Chinese body text, Hiragino Sans GB W6 for Chinese headings and Times New Roman for Latin text. Table 2 and Supplementary Tables S1–S7 are set on landscape pages; Figures 1–3 and S1–S6 are embedded from the formal PNGs. The typography was revised on 2026-11-05 (see below).

Workflow:

```bash
make zh          # rebuild the three Chinese PDFs and refresh sync_manifest.json
make zh-check    # fail if any English source, figure or Chinese artefact is stale
```

`manuscript/zh/sync_manifest.json` records SHA-256 for the three English sources, all nine formal figures, the three Chinese sources and the three Chinese PDFs. `scripts/36_build_chinese_review.py` refuses to rebuild when an English text source changed but its Chinese counterpart did not, so a new English revision cannot silently be stamped as translated; `--force` overrides this only after deliberate review. `scripts/37_check_chinese_sync.py` is read-only, is also run by `make check`, and prints the exact stale path plus the rebuild instruction. `manuscript/zh/build/` is a rebuildable working directory and is excluded from Git and from the release inventory. The Chinese review edition is versioned in Git for review, but `config/release_policy.json` excludes `manuscript/zh` and the internal `archive/` tree from the journal upload snapshot; only English submission files enter that package.

Verification:

- Numeric-token multisets were compared between each English source and its Chinese counterpart. Remaining differences are formatting only (`1,000` versus `1000`, image widths, section and figure numbers). The comparison exposed one omitted English paragraph in the supplementary Results, "Exploratory molecular analyses"; the heading and both paragraphs were translated and inserted, and the rebuilt supplement retained its 26 pages at that stage.
- Page counts are 18 / 27 / 1 after the typography revision below. None of the three Chinese LaTeX logs contains an overfull box.
- `make zh-check` passes against the current English sources, `make check` includes the same check, and `docs/SHA256SUMS.txt` was regenerated with 402 entries (384 before), all verifying; the 18 additions are the three PDFs, three Chinese sources, nine review figures, the sync manifest, scripts 36 and 37. No English submission file, analysis output or formal figure was modified.
- No Git commit, push, publication or DOI deposit was performed.

### Typography revision (2026-11-05)

Author review found that the Chinese edition's subheadings were set at or below body size and that several layout defects remained. The three Chinese PDFs were re-typeset; no Chinese or English wording changed.

The first heading pass set nominal sizes of 17/14/12 pt but still looked flat to the author. The cause was the font, not the scale: `BoldFont=Heiti SC` resolved to the family default, STHeitiSC-Light, and the "Heiti SC" family contains only Light and Medium faces. Every heading therefore rendered in a light sans face that read smaller than the 10.5 pt Songti body. Headings now use Hiragino Sans GB W6, a true bold Simplified-Chinese face; `pdffonts` confirms that neither Chinese PDF contains STHeitiSC-Light.

- Heading hierarchy: 19/22.5 pt centred document title with a 0.4 pt rule below it, 17/20 pt section, 14.5/17.2 pt subsection and 10.5 pt run-in paragraph, all in Hiragino Sans GB W6 with `\linespread{1}` so headings do not inherit the body leading. Body remains Songti SC 10.5/13.65 pt, so every heading level is at least 38% larger than the body and visibly heavier.
- Page geometry: A4, `extarticle` 10.5 pt body, 2 em first-line indent on every paragraph (`indentfirst`), 1.30 leading, `\raggedbottom` with widow/club penalties and `needspace` before headings.
- Each figure receives its own page with a 190 mm text measure and is not rescaled; each table starts on a new page; landscape tables use a 269 mm line width and two-line headers where needed.
- Landscape blocks now set `\textheight` and `\vsize` to 182 mm immediately after `\newgeometry`. `geometry` computed both from the class A4 portrait paper height, leaving `\pagegoal` at 765 pt on a 597 pt-tall landscape page; any longtable content below the physical page edge was silently clipped. This had removed Supplementary Table S5 panels (c) and (d) and Table S3 panels (e) and (f) from the previous PDF; all four now render in full.
- Panel labels carry unique markers. `panel_orphans()` now reads word coordinates from `pdftotext -bbox` and assigns each label to the preceding "补充表 S<n>" caption, replacing the `-layout` parse that merged short label lines and mis-assigned the owning table. A label stranded at the foot of a page forces a break before that panel on the next build.

Verification:

- Chinese page counts are 18 / 27 / 1.
- `pdffonts` lists HiraginoSansGB-W6 as the only CJK heading face in both PDFs; the title page, a Methods page, the 图注/表注 pages and Supplementary Table S5 were inspected at 150 dpi, and every heading reads heavier than the Songti body.
- All 19 panel labels appear exactly once, no rendered page ends with an orphan label, and a word-level bottom-edge audit of both Chinese PDFs found no clipped words.
- Restored values are present, including RMST 32.6 and 46.7 with differences −7.9 and −18.0 months, 4.25 (1.43–12.62), 59.29, 0.60–30.15, 291/61/22/30 and the PFI cascade 56/9/5/1/9/10.
- None of the three Chinese LaTeX logs contains an overfull box.
- The English submission PDFs were not rebuilt and remain at 19 / 22 / 36 / 1 pages. `make zh-check` and `make check` pass, and `docs/SHA256SUMS.txt` was refreshed in place (402 paths, 6 entries changed). No Git commit, push, publication or DOI deposit was performed.

## Result-to-claim corrections (2026-11-05)

A result-to-claim audit of the manuscript identified three wording or derivation problems. The fixes were text and one descriptive computation; no model was refitted, no estimate or interval changed, and no new claim was registered.

1. **Parsimony wording.** The CR-versus-NCR model (M3) is a one-parameter coding, but so is the objective-response model (M2); M3 was not "the most parsimonious model tested". Five locations now read "best-supported single-parameter coding" (title-page Conclusions, highlights, Discussion opening, Discussion conclusion, cover letter). The supporting facts are unchanged: M3 had the lowest AIC and BIC and a cross-validated C-index of 0.679 versus 0.677 for four categories, while the objective-response constraint was rejected (P=8.5×10⁻¹⁰). The highlight was shortened to "best single-parameter coding" to stay within the 125-character limit.
2. **Median OS in excluded patients.** The manuscript had quoted sample medians (637 versus 895 days), computed for excluded NCR patients after dropping the one patient without an OS time. These are now Kaplan–Meier medians from diagnosis: 760 days (95% CI 506–1004) in excluded NCR patients versus 1032 days (914–1199) in included NCR patients. `scripts/35_landmark_selection_tipping.R` now computes the three descriptive KM fits, writes `results/tables/ov_selection_tipping/landmark_selection_km_medians.csv`, and adds the medians and limits to `landmark_selection_tipping_summary.csv`. The excluded NCR fit contains 35 patients and 28 deaths because one labelled PR patient has no OS time; the included NCR fit contains 99 patients and 80 deaths. The tipping bounds, observed HR and all other script-35 outputs are unchanged.
3. **Provenance of the 396-patient analysis.** The expression-unrestricted TCGA-OV analysis is now described as drawn from the cross-cancer analysis, comprising all labelled patients at the therapy-end landmark (no plausibility window). The earlier parenthetical "only age and stage" was removed because the quoted NCR HR (3.97, 2.98–5.27) is the unadjusted estimate; the adjusted cross-cancer row (n=395) gives 4.16 (3.11–5.56) and was not substituted.

Verification:

- Main text is 4,000 of 4,000 words, the abstract 299 of 300, five highlights of at most 125 characters, 45 main and 46 supplementary references and five display items. Stage 21's only remaining flag is its pre-existing conservative main-text-plus-legends check.
- Page counts are 19 (upload), 22 (review copy), 36 (supplement) and 1 (cover letter); stage 23 confirms pages 1–19 of the review copy are text-identical to the upload manuscript.
- Stage 24 validates 160 claims and 18 provenance entries with 0 failed fields; stage 26 audits 18 figures with no failures; stage 27 and `make check` pass.
- The Chinese review edition was rebuilt after the English changes (18 / 27 / 1 pages) and `make zh-check` passes.
- `docs/SHA256SUMS.txt` was refreshed with 403 paths (402 before; the addition is the new KM table), and all entries verify.
- Pre-change English and Chinese sources and script 35 are in `../archive/review_fixes_pre_20261105/`.
- No Git commit, push, publication or DOI deposit was performed.

## Independent auto-review response (2026-11-06)

An independent adversarial review (`mistralai/mistral-large-4-0`, effort max, hard mode with reviewer memory and executor rebuttal) scored the submission 7/10 with verdict "almost". One round was sufficient because the loop's stop rule (score ≥6 and verdict in {ready, almost}) was met. The reviewer's findings were adjudicated against the locked source tables; two assertions were false positives (the STROBE checklist exists in the package, and the GSE23554 sample overlap is already disclosed in the Discussion, Table S1 caption and Table S3(d), with the leave-one-out estimate 2.78, 1.78–4.35). Five wording or precision defects were accepted and corrected without refitting any model:

1. **First highlight.** The 3.6-fold paraphrase was replaced by the exact contrast: "Objective-response grouping obscured an HR of 3.61 for death after partial versus complete response."
2. **PR-only subgroup.** In the 77 patients without macroscopic residual disease, the text now states that 69 were CR and 1 PR, so CR-versus-PR is unsupported there, rather than describing the subgroup as unable to support "a CR-versus-PR estimate" after an incomplete enumeration.
3. **Serous-cohort composition.** "TCGA-OV is serous by design" became "TCGA-OV was designed as a serous cohort (31 G1–G2, 7 borderline/unknown)".
4. **Split variability.** The empirical percentile range (0.001; −0.001 to 0.003; 13 of 20 positive) is no longer called a "bootstrap 95% CI"; it is described as a bootstrap percentile interval of repeat-level differences, consistent with the interval type recorded in `cv_discrimination_paired_delta_CR_vs_four.csv`.
5. **No-residual-disease adjustment.** Both Results and Discussion now specify "adjusted for age/stage 1.82, 0.53–6.23", because residual disease is the stratifying variable and cannot be adjusted for in that subgroup.

Two claim patterns in `config/manuscript_claims.json` were aligned with the revised sentences (cross-validation "in each of 20 repeats"; "bootstrap percentile interval of repeat-level differences"). The Data 5 reporting bundle was rebuilt from the updated claims configuration.

Verification:

- Main text is 3,998 of 4,000 words, the abstract 299 of 300, five highlights of at most 125 characters (100/93/123/106/84), and the display-item legends 996 words; stage 21's only flag is the pre-existing conservative main-text-plus-legends diagnostic, which is excluded from the failure condition.
- Page counts are 19 (upload manuscript), 22 (illustrated review copy), 36 (supplement) and 1 (cover letter). Stage 23 confirms pages 1–19 of the review copy are text-identical to the upload manuscript. The supplement PDF is unchanged; its DOCX, the manuscript DOCX, the cover-letter DOCX and the STROBE DOCX were regenerated.
- Stage 24 validates 160 claims and 18 provenance entries with 0 failed fields; stage 26, run with `/opt/homebrew/bin/python3.10` because the noninteractive `python3` on this host lacks PyMuPDF, audits 18 formal figures with 0 failures; stage 27 passes.
- The Chinese review edition was rebuilt after the English and Chinese source edits (18/27/1 pages) and `make zh-check` passes.
- The external upload package was rebuilt as `../submission_package/ESMO_Open_20261106` and `ESMO_Open_20261106_upload_package.zip` (SHA-256 `cb58a39be3cd206ee1df884d17396e841b4088eb70eb6d2520befbe4a1735ac1`); its 22 file checksums verify after extraction. The 2 November archive is retained as the pre-review snapshot.
- Pre-change English and Chinese sources and the earlier `docs/REPRODUCIBILITY.md` are in `../archive/review_fixes_pre_20261106_autoreview/`.
- The review transcript, reviewer memory and round record are in `review-stage/` (AUTO_REVIEW.md, REVIEWER_MEMORY.md, REVIEW_STATE.json, biohex-runs/).
- No Git commit, push, publication or DOI deposit was performed.

## Citation audit and reference fixes (2026-11-06)

All 45 main-text and 46 supplementary reference entries (91 entries, 67 unique keys, 111 in-text uses) were checked against Crossref and PubMed, and every in-text use was reviewed for support of the anchored statement. The ledger and human report are `review-stage/citation_audit_20261106/CITATION_AUDIT.json` and `CITATION_AUDIT.md`. All 74 DOIs resolved and all 58 PubMed records matched; numbering was complete and sequential. Verdicts were 90 KEEP, 1 FIX, 0 REPLACE and 0 REMOVE; three of 111 uses were graded WEAK, and none was non-supporting. One Codex reviewer seat was unavailable, so the context review was run with `mistralai/mistral-large-4-0`; this substitution is disclosed in the report.

Three approved fixes were applied without adding, removing or renumbering a reference:

1. **S18 journal abbreviation (F1).** The supplement rendered the journal as "Annals of internal medicine"; it now reads `Ann Intern Med`, matching the AMA abbreviation used by the other entries.
2. **Introduction response-depth sentence (F2).** The sentence now reads "Response depth is prognostic: pathological chemotherapy response score in first-line ovarian cancer, and modelled CA-125 elimination kinetics in first-line and recurrent disease", which states the direction once and removes the ambiguous "measures of response depth" list. No citation or number changed.
3. **Discussion Cortazar placement (F3).** The CTNeoBC citation now attaches directly to its own claim: "…or test ORR or CR as trial-level surrogates; CTNeoBC tested pathological complete response in breast cancer." The sentence also changed "little numerical loss" to "little loss", "best supported among" to "best supported in", "concerns patient-level prognostic grouping and does not require NCR equivalence" to "concerns patient-level prognostic grouping, not NCR equivalence", and "reinterpreted as" to "read as".

Verification:

- Stage 21 passes every configured limit: main text 3,999 of 4,000 words, abstract 299 of 300, 45 main and 46 supplementary references, five display items, five highlights (100/93/123/106/84 characters) and six keywords. The conservative main-text-plus-legends diagnostic is 4,995 and remains excluded from the failure condition.
- Stages 23, 24, 26, 27 and `make check` pass; stage 24 validates 160 claims and 18 provenance entries with 0 failed fields, and stage 26 audits 18 formal figures with 0 failures when run with `/opt/homebrew/bin/python3.10`.
- Page counts are 19 (upload manuscript), 22 (illustrated review copy), 36 (supplement) and 1 (cover letter); stage 23 confirms pages 1–19 of the review copy are text-identical to the upload manuscript.
- The Chinese review edition was synchronised with the revised Introduction and Discussion sentences and the S18 abbreviation, then rebuilt (18/27/1 pages); `make zh-check` passes.
- `docs/SHA256SUMS.txt` was refreshed after the rebuild (403 paths) and verifies clean.
- The external upload package was refreshed as `../submission_package/ESMO_Open_20261106`; its 22 checksums and all 20 `MANIFEST.csv` rows verify, and the new outer ZIP SHA-256 is `55a0a025ef7b33cc5ff30f203907c355b5c5435401e349adf33982026bd61071`.
- Pre-change English and Chinese sources and the four English PDFs are in `../archive/citation_audit_fixes_pre_20261106/`.
- No reference was added, removed or renumbered, no estimate was refitted, and no Git commit, push, publication or DOI deposit was performed.

## File checksums

`docs/SHA256SUMS.txt` is generated after final repository validation and covers all final physical repository files except itself, including formal manuscripts, figures, tables and included processed data. Ignored local build/review artefacts are excluded by prior cleanup; the inventory must verify without omissions or unexpected additional files.
