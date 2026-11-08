#!/usr/bin/env Rscript

# ==============================================================================
# File: 20_build_manuscript_outputs.R
# Purpose: Dispatch locked publication rendering; quarantine historical analysis.
# Author: Project authors
# Created: 2026-10-15
# Default / --render-only: scripts/30_render_locked_publication.py reads locked
# CSVs and clean vector regions without fitting, tests or resampling. The input,
# runtime and reproducibility notes below describe ONLY --legacy-analysis.
# Inputs:
#   - Phase 0 clinical/script 15 treatment rows and locked tables/figures from
#     scripts 14 and 16-19; GSE63885 sample-level OS supports the uniform refits.
# Runtime parameters:
#   - config/analysis.yml: random_seeds.manuscript_outputs; landmark.plausible_end_days,
#     fixed_days[1] and tipping_days; cohort.platinum_agents/taxane_agents;
#     response.equivalence_margin; survival.days_per_month, wald_z_95 (original
#     rounded 1.96) and alpha; resampling.monte_carlo_test_replicates and
#     cross_validation_repeats/folds; reporting.split_quantiles for CV C summaries.
#   - external_validation.landmark_days is checked against the clinical landmark;
#     pancancer.minimum_noncr/minimum_cr/minimum_os_events and power.target_power
#     are exported as provenance, not recalculated from displayed claims.
#   - load_project_configuration(project_dir) resolves processed_data_dir/results_dir
#     from private paths or environment overrides; shared style and the submission
#     profile supply artwork settings. Explicit cohort/source selections, table
#     formatting and figure geometry remain unchanged; 120 months is display_only.
#   - Expected counts/ordering in stopifnot are locked assertions, never analysis
#     inputs. Case counts and statistical annotations come from observed data/tables.
# Outputs:
#   - Final manuscript Tables 1-2, supplementary tables, Figures 1 and 3, and data files.
# Reproducibility:
#   - Uniform unweighted Cox refits use observed records. IPW/date-imputation rows
#     retain their robust/pooled tests from script 18, not likelihood-based substitutes.
#   - Table 1 Fisher tests use configured Monte Carlo draws; GSE63885 CV uses
#     seed + repeat and unchanged within-fold comparable-pair C-index counts.
#     Locked artwork/table copies preserve source bytes and record provenance.
# ==============================================================================

# Manuscript display items assembled from locked analysis outputs:
#   Figure 1  study design and cohort flow
#   Figure 3  external replication (CR threshold; four-class topology; PD step)
#   Table 1   baseline characteristics of the TCGA main landmark cohort by response
#   Table 2   response-coding model comparison across settings and cohorts
#   Supplementary Data 1  case-level identifiers and inclusion flags
#   Package versions / sessionInfo
# Response-topology refits are limited to GSE63885 and uniform TCGA Table 2
# rows, retaining scripts 17/18's definitions. Table 1 tests and Figure 3B
# log-rank/CV statistics are computed separately from observed eligible rows.

# ---- Publication-only entry point (before imports, seeds or statistical work) --
# Normal pipeline calls and --render-only consume locked outputs only. The
# historical fitting code below is quarantined behind --legacy-analysis and is
# NOT the publication renderer. It may restore superseded sensitivity displays.
entry_args <- commandArgs(trailingOnly = TRUE)
if (!identical(entry_args, "--legacy-analysis")) {
  if (length(entry_args) > 0L && !identical(entry_args, "--render-only")) {
    stop("Use no arguments / --render-only for locked publication rendering; ",
         "--legacy-analysis is the explicit historical analysis entry.")
  }
  entry_file <- commandArgs(trailingOnly = FALSE)
  entry_file <- entry_file[grepl("^--file=", entry_file)][1]
  entry_script <- normalizePath(sub("^--file=", "", entry_file), mustWork = TRUE)
  renderer <- file.path(dirname(entry_script), "30_render_locked_publication.py")
  # A caller may pin its dependency-installed Python before an R startup file
  # changes PATH. Executable paths remain runtime overrides, never committed.
  python <- Sys.getenv("CRNCR_PYTHON", unset = Sys.which("python3"))
  if (!nzchar(python)) stop("python3 with PyMuPDF/Pillow is required; set CRNCR_PYTHON if needed.")
  status <- system2(python, args = c(shQuote(renderer), "--render-only"))
  quit(save = "no", status = status, runLast = FALSE)
}
warning("Explicit legacy analysis selected: this path fits models and is not publication-safe.")

# ---- Historical analysis imports (explicit --legacy-analysis only) ------------
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr); library(purrr)
  library(survival); library(survminer); library(ggplot2); library(patchwork)
})
# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)
analysis_config <- config$analysis
figure_style <- get_figure_style(project_dir)
figure_spec <- load_figure_specification(project_dir)
figure_text <- figure_text_size(figure_spec)
seed <- analysis_config$random_seeds$manuscript_outputs
configure_reproducible_runtime(seed, threads = 1L)
landmark_bounds <- analysis_config$landmark$plausible_end_days
fixed_landmark <- analysis_config$landmark$fixed_days[1]
equivalence_margin <- analysis_config$response$equivalence_margin
platinum_agents <- analysis_config$cohort$platinum_agents
taxane_agents <- analysis_config$cohort$taxane_agents
wald_z_95 <- analysis_config$survival$wald_z_95
split_quantiles <- analysis_config$reporting$split_quantiles
plausible_end_step <- sprintf(
  "Plausible end date (%d-%d d)", landmark_bounds[[1]], landmark_bounds[[2]]
)
implausible_end_reason <- sprintf(
  "implausible end date (<%d or >%d d)", landmark_bounds[[1]], landmark_bounds[[2]]
)
monte_carlo_replicates <- analysis_config$resampling$monte_carlo_test_replicates
processed_dir <- config$paths$processed_data_dir
results_dir <- config$paths$results_dir
out_tab <- file.path(results_dir, "tables", "manuscript")
out_fig <- file.path(results_dir, "figures", "manuscript")
dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(project_dir, "logs"), recursive = TRUE, showWarnings = FALSE)
mo <- analysis_config$survival$days_per_month
t17 <- file.path(results_dir, "tables", "ov_therapy_end_landmark")
t18 <- file.path(results_dir, "tables", "ov_selection_regimen_power")
t4 <- file.path(results_dir, "tables", "phase4_external_validation")
tpc <- file.path(results_dir, "tables", "pancancer_topology")

# ------------------------------------------------------------------ TCGA data (as scripts 17-18)
clin <- read_csv(file.path(processed_dir, "tcga_ov_phase0_clinical.csv"), show_col_types = FALSE) %>%
  filter(!is.na(response4))
gdc <- read_csv(file.path(processed_dir, "pancancer_patient_response_treatment.csv"),
                show_col_types = FALSE, guess_max = 20000) %>%
  filter(cancer == "OV") %>%
  select(patient, fl_start, fl_end, fl_agents, fl_platinum, first_line_radiation, therapy_end)
# Input: one semicolon-delimited agent string. Return: TRUE only when every
# exact token is allowed and both platinum and taxane are present; NA is FALSE.
# Do not trim, deduplicate or permit extra agents; this matches script 18.
agents_ok <- function(a) {
  is_platinum_taxane_doublet(a, platinum_agents, taxane_agents)
}
d0 <- clin %>% left_join(gdc, by = "patient") %>%
  mutate(response4 = factor(response4, levels = c("CR", "PR", "SD", "PD")),
    noncr = as.integer(response4 != "CR"), orr_fail = as.integer(response4 %in% c("SD", "PD")),
    pd_step = factor(case_when(response4 == "CR" ~ "CR", response4 == "PD" ~ "PD", TRUE ~ "PR_SD"),
      levels = c("CR", "PR_SD", "PD")),
    stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
    residual_group = factor(residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm")),
    date_ok = is.finite(therapy_end) & therapy_end >= landmark_bounds[1] &
      therapy_end <= landmark_bounds[2],
    label_source = case_when(response_conflict %in% TRUE ~ "TCGA-CDR, discordant clinical-matrix label",
      !is.na(response_clinical) ~ "TCGA-CDR, concordant clinical-matrix label", TRUE ~ "TCGA-CDR only"),
    plat_taxane = vapply(fl_agents, agents_ok, logical(1)),
    regimen = case_when(is.na(fl_start) ~ "No first-line record", plat_taxane ~ "Platinum-taxane doublet",
      fl_platinum %in% TRUE ~ "Other platinum-based", TRUE ~ "Non-platinum"))
# Locked assertion: upstream unified-label row count, not a cohort-size input.
stopifnot(nrow(d0) == 454)
# Input: clinical rows, scalar/row-aligned origin days and endpoint column names.
# Return: rows with finite follow-up strictly beyond origin and time in months.
# The caller supplies plausible/imputed origins; no display horizon censors OS.
lm_from <- function(d, origin, time_col = "OS_days", event_col = "OS_event") {
  d %>% mutate(origin = origin, t_raw = .data[[time_col]], event = .data[[event_col]]) %>%
    filter(is.finite(origin), is.finite(t_raw), !is.na(event), t_raw > origin) %>%
    mutate(time = (t_raw - origin) / mo)
}
lm_main <- lm_from(d0, ifelse(d0$date_ok, d0$therapy_end, NA))
# Locked assertion: the observed landmark count must match scripts 17/18.
stopifnot(nrow(lm_main) == 372)
main_ids <- lm_main$patient

# ------------------------------------------------------------------ uniform topology summary
covars <- c("age_10y", "stage_group", "residual_group")
# Input: endpoint-aligned cohort rows and an adjustment flag. Return: one-row
# uniform unweighted HR/LRT/AIC/BIC summary for Table 2. Four Cox codings share
# complete cases and CR reference; BIC counts events. Missing M1 coefficients
# yield NA display estimates; the M_PD contrast retains rounded 1.96 Wald bounds.
# Weighted and imputation rows are imported separately, not passed to this fitter.
topo <- function(d, adjust = FALSE) {
  cv <- if (adjust) covars else character()
  d <- d[complete.cases(d[, c("time", "event", cv)]), ] %>% mutate(response4 = droplevels(response4))
  rhs <- function(x) paste(c(x, cv), collapse = " + ")
  f <- list(M1 = coxph(as.formula(paste("Surv(time, event) ~", rhs("response4"))), d),
    M2 = coxph(as.formula(paste("Surv(time, event) ~", rhs("orr_fail"))), d),
    M3 = coxph(as.formula(paste("Surv(time, event) ~", rhs("noncr"))), d),
    M_PD = coxph(as.formula(paste("Surv(time, event) ~", rhs("pd_step"))), d))
  ll <- sapply(f, function(x) x$loglik[2]); k <- sapply(f, function(x) length(coef(x)))
  aic <- -2 * ll + 2 * k; bic <- -2 * ll + log(sum(d$event)) * k
  # Input: M1 coefficient name. Return: HR and Cox CI, or three NAs if absent;
  # missing response coefficients are not replaced by a reference HR of one.
  hr <- function(nm) { b <- coef(f$M1); if (!nm %in% names(b)) return(c(NA, NA, NA))
    exp(c(b[nm], confint(f$M1)[nm, ])) }
  pr <- hr("response4PR"); sd <- hr("response4SD"); pd <- hr("response4PD")
  m3 <- exp(c(coef(f$M3)["noncr"], confint(f$M3)["noncr", ]))
  cp <- c(-1, 1); bpd <- coef(f$M_PD)[c("pd_stepPR_SD", "pd_stepPD")]
  lpd <- sum(cp * bpd); se <- sqrt(as.numeric(t(cp) %*% vcov(f$M_PD)[names(bpd), names(bpd)] %*% cp))
  tibble(n = nrow(d), events = sum(d$event), CR = sum(d$response4 == "CR"), PR = sum(d$response4 == "PR"),
    SD = sum(d$response4 == "SD"), PD = sum(d$response4 == "PD"),
    HR_PR = pr[1], HR_PR_low = pr[2], HR_PR_high = pr[3], HR_SD = sd[1], HR_SD_low = sd[2], HR_SD_high = sd[3],
    HR_PD = pd[1], HR_PD_low = pd[2], HR_PD_high = pd[3],
    HR_NonCR = m3[1], HR_NonCR_low = m3[2], HR_NonCR_high = m3[3],
    HR_PD_vs_PRSD = exp(lpd), HR_PD_vs_PRSD_low = exp(lpd - wald_z_95 * se), HR_PD_vs_PRSD_high = exp(lpd + wald_z_95 * se),
    plateau_p = pchisq(2 * (ll["M1"] - ll["M3"]), k["M1"] - k["M3"], lower.tail = FALSE),
    ORR_p = pchisq(2 * (ll["M1"] - ll["M2"]), k["M1"] - k["M2"], lower.tail = FALSE),
    PD_step_p = pchisq(2 * (ll["M_PD"] - ll["M3"]), 1, lower.tail = FALSE),
    dAIC_M1 = aic["M1"] - min(aic), dAIC_M2 = aic["M2"] - min(aic), dAIC_M3 = aic["M3"] - min(aic),
    dAIC_M_PD = aic["M_PD"] - min(aic),
    best_AIC = names(which.min(aic)), best_BIC = names(which.min(bic)))
}

# GSE63885 (serous, four-class).
ext <- read_csv(file.path(t4, "external_survival_by_sample.csv"), show_col_types = FALSE)
g63 <- ext %>% filter(cohort == "GSE63885", !is.na(response4), is.finite(os_days), !is.na(os_event)) %>%
  mutate(response4 = factor(response4, levels = c("CR", "PR", "SD", "PD")),
    noncr = as.integer(response4 != "CR"), orr_fail = as.integer(response4 %in% c("SD", "PD")),
    pd_step = factor(case_when(response4 == "CR" ~ "CR", response4 == "PD" ~ "PD", TRUE ~ "PR_SD"),
      levels = c("CR", "PR_SD", "PD")))
# Input: fixed landmark days; g63 already has usable observed OS/response.
# Return: external survivors' post-landmark OS rows. Retain this manuscript
# builder's month conversion and full follow-up; do not substitute script 14's.
g63_lm <- function(days) g63 %>% filter(os_days > days) %>% mutate(time = (os_days - days) / mo, event = os_event)

# ------------------------------------------------------------------ Table 2
imp <- read_csv(file.path(t18, "stochastic_date_imputation_summary.csv"), show_col_types = FALSE)
ipw <- read_csv(file.path(t18, "ipw_topology.csv"), show_col_types = FALSE)
imputation_label <- sprintf(
  "End of chemotherapy, missing dates imputed (%d draws)",
  as.integer(imp$imputations[[1]])
)
boot17 <- read_csv(file.path(t17, "bootstrap_model_selection.csv"), show_col_types = FALSE)
boot18 <- read_csv(file.path(t18, "regimen_restriction_bootstrap.csv"), show_col_types = FALSE)
d_main_diag <- d0 %>% filter(patient %in% main_ids)
rows <- list(
  list("TCGA-OV", "Diagnosis, all labelled", "none", lm_from(d0, rep(0, nrow(d0))), FALSE, "none"),
  list("TCGA-OV", "Fixed 6-month landmark", "none", lm_from(d0, rep(fixed_landmark, nrow(d0))), FALSE, "fixed183"),
  list("TCGA-OV", "Diagnosis, main-cohort patients", "none",
    lm_from(d_main_diag, rep(0, nrow(d_main_diag))), FALSE, "none_same_patients"),
  list("TCGA-OV", "End of first-line chemotherapy (main)", "none", lm_main, FALSE, "therapy_end"),
  list("TCGA-OV", "End of first-line chemotherapy (main)", "age+stage+residual", lm_main, TRUE, NA),
  list("TCGA-OV", "End of chemotherapy, platinum-taxane doublet", "none", lm_main %>% filter(plat_taxane), FALSE, "Platinum-taxane doublet only"),
  list("GSE63885", "Diagnosis", "none", g63_lm(0), FALSE, NA),
  list("GSE63885", "Fixed 6-month landmark", "none", g63_lm(fixed_landmark), FALSE, NA))
tab2 <- bind_rows(lapply(rows, function(r) {
  s <- topo(r[[4]], r[[5]]) %>% mutate(cohort = r[[1]], time_origin = r[[2]], adjustment = r[[3]], .before = 1)
  b <- if (is.na(r[[6]])) NULL else if (r[[6]] %in% boot17$landmark) boot17 %>% filter(landmark == r[[6]]) else
    boot18 %>% filter(restriction == r[[6]])
  s %>% mutate(boot_M3_best = if (is.null(b)) NA else b$M3, boot_M_PD_best = if (is.null(b)) NA else b$M_PD,
    boot_plateau_rejected = if (is.null(b)) NA else b$plateau_rejected)
}))
tab2 <- bind_rows(tab2,
  ipw %>% filter(weighting == "IPW") %>% transmute(cohort = "TCGA-OV", time_origin = "End of chemotherapy, IPW for inclusion",
    adjustment, n, CR, PR, SD, PD, HR_PR, HR_PR_low, HR_PR_high, HR_SD, HR_SD_low, HR_SD_high, HR_PD, HR_PD_low, HR_PD_high,
    HR_NonCR, HR_NonCR_low, HR_NonCR_high, HR_PD_vs_PRSD, HR_PD_vs_PRSD_low,
    HR_PD_vs_PRSD_high, plateau_p = plateau_p_robust, ORR_p = ORR_p_robust,
    PD_step_p = PD_step_p_robust, best_AIC = NA, best_BIC = NA),
  imp %>% transmute(cohort = "TCGA-OV", time_origin = imputation_label,
    adjustment = "none", n = median_n, PD = median_PD, HR_PD_vs_PRSD = pooled_HR_PD_vs_PRSD,
    HR_PD_vs_PRSD_low = pooled_HR_PD_vs_PRSD_low, HR_PD_vs_PRSD_high = pooled_HR_PD_vs_PRSD_high,
    plateau_p = pooled_plateau_p, ORR_p = pooled_ORR_p, PD_step_p = median_PD_step_p,
    best_AIC = sprintf("M3 %.0f%%, M_PD %.0f%%", 100 * frac_best_AIC_M3, 100 * frac_best_AIC_M_PD),
    best_BIC = sprintf("M3 %.0f%%", 100 * frac_best_BIC_M3)))
# Post hoc operational HGSOC row (script 19), inserted after the platinum-taxane row.
hg19 <- read_csv(file.path(results_dir, "tables", "ov_hgsoc_sensitivity", "hgsoc_topology_by_setting.csv"), show_col_types = FALSE) %>%
  filter(setting == "HGSOC therapy-end landmark", adjustment == "none")
hb19 <- read_csv(file.path(results_dir, "tables", "ov_hgsoc_sensitivity", "hgsoc_bootstrap_model_selection.csv"), show_col_types = FALSE) %>%
  filter(setting == "HGSOC therapy-end landmark")
stopifnot(nrow(hg19) == 1L, nrow(hb19) == 1L)
hgsoc_row <- hg19 %>% select(-setting, -starts_with("dBIC")) %>%
  mutate(cohort = "TCGA-OV, operational HGSOC", time_origin = "End of first-line chemotherapy (post hoc)",
    boot_M3_best = hb19$M3, boot_M_PD_best = hb19$M_PD, boot_plateau_rejected = hb19$plateau_rejected, .before = 1)
pt_row <- which(tab2$time_origin == "End of chemotherapy, platinum-taxane doublet")
stopifnot(length(pt_row) == 1L)
tab2 <- bind_rows(tab2[seq_len(pt_row), ], hgsoc_row, tab2[-seq_len(pt_row), ])
write_csv(tab2, file.path(out_tab, "Table2_model_comparison.csv"))

# Input: p vector. Return: display strings (blank for NA); 0.001/0.01 select
# notation/precision only and are not hypothesis-test rejection thresholds.
fmt_p <- function(p) ifelse(is.na(p), "", ifelse(p < 0.001, formatC(p, format = "e", digits = 1), ifelse(p < 0.01, sprintf("%.3f", p), sprintf("%.2f", p))))
# Input: aligned HR/lower/upper vectors. Return: two-decimal display strings;
# absent estimates are blank, absent lower bounds display an estimate alone.
fmt_hr <- function(e, l, h) ifelse(is.na(e), "", ifelse(is.na(l), sprintf("%.2f", e), sprintf("%.2f (%.2f-%.2f)", e, l, h)))
tab2_fmt <- tab2 %>% transmute(Analysis = paste0(cohort, ": ", time_origin), Adjustment = adjustment,
  `n (CR/PR/SD/PD)` = ifelse(is.na(CR), as.character(n), sprintf("%d (%d/%d/%d/%d)", as.integer(n), as.integer(CR), as.integer(PR), as.integer(SD), as.integer(PD))),
  `PR vs CR` = fmt_hr(HR_PR, HR_PR_low, HR_PR_high), `SD vs CR` = fmt_hr(HR_SD, HR_SD_low, HR_SD_high),
  `PD vs CR` = fmt_hr(HR_PD, HR_PD_low, HR_PD_high), `NCR vs CR` = fmt_hr(HR_NonCR, HR_NonCR_low, HR_NonCR_high),
  `PD vs PR+SD` = fmt_hr(HR_PD_vs_PRSD, HR_PD_vs_PRSD_low, HR_PD_vs_PRSD_high),
  `Plateau p` = fmt_p(plateau_p), `ORR constraint p` = fmt_p(ORR_p), `PD step p` = fmt_p(PD_step_p),
  `dAIC M1/M2/M3/M_PD` = ifelse(is.na(dAIC_M1), "", sprintf("%.1f/%.1f/%.1f/%.1f", dAIC_M1, dAIC_M2, dAIC_M3, dAIC_M_PD)),
  `Best AIC/BIC` = ifelse(is.na(best_AIC) & is.na(best_BIC), "", paste(coalesce(best_AIC, "–"), coalesce(best_BIC, "–"), sep = " / ")),
  `Bootstrap M3 best` = ifelse(is.na(boot_M3_best), "", sprintf("%.0f%%", 100 * boot_M3_best)))
write_csv(tab2_fmt, file.path(out_tab, "Table2_model_comparison_formatted.csv"))

# ------------------------------------------------------------------ Table 1
d0 <- d0 %>% mutate(group = ifelse(patient %in% main_ids, as.character(response4), "Excluded"),
  duration = fl_end - fl_start,
  grade_table = factor(case_when(grade %in% c("G1", "G2") ~ "G1-G2", grade %in% c("G3", "G4") ~ "G3-G4",
    !is.na(grade) ~ "Not assessable (GB/GX)", TRUE ~ NA_character_),
    levels = c("G1-G2", "G3-G4", "Not assessable (GB/GX)")))
# Input: d0 categorical column name and table heading. Return: category n (%),
# including missing/excluded rows, plus a Monte Carlo Fisher p across response.
# Percentages include missingness in each group denominator; the test omits
# missing values and excluded patients, returning NA if the test cannot run.
cat_row <- function(var, lab) {
  lv <- if (is.factor(d0[[var]])) levels(d0[[var]]) else sort(unique(na.omit(as.character(d0[[var]]))))
  x <- d0 %>% mutate(v = factor(coalesce(as.character(.data[[var]]), "Missing"), levels = c(lv, "Missing")))
  tb <- x %>% count(group, v, .drop = FALSE) %>% filter(!(v == "Missing" & n == 0 & !any(x$v == "Missing"))) %>% group_by(group) %>% mutate(s = sprintf("%d (%.0f%%)", n, 100 * n / sum(n))) %>%
    select(-n) %>% pivot_wider(names_from = group, values_from = s, values_fill = "0 (0%)")
  m <- x %>% filter(group != "Excluded", v != "Missing")
  p <- tryCatch(fisher.test(table(m$v, m$group), simulate.p.value = TRUE, B = monte_carlo_replicates)$p.value, error = function(e) NA)
  bind_rows(tibble(Characteristic = lab, p_across_response = fmt_p(p)), tb %>% mutate(v = as.character(v)) %>% rename(Level = v)) %>%
    relocate(Characteristic, Level)
}
# Input: d0 numeric column and heading. Return: group median/IQR strings and
# Kruskal-Wallis p among included response groups, omitting missing values.
# The legacy sub argument is unused; summaries retain the untransformed column.
cont_row <- function(var, lab, sub = function(x) x) {
  x <- d0 %>% mutate(v = .data[[var]])
  tb <- x %>% group_by(group) %>% summarise(s = sprintf("%.0f (%.0f-%.0f)", median(v, na.rm = TRUE),
    quantile(v, 0.25, na.rm = TRUE), quantile(v, 0.75, na.rm = TRUE)), .groups = "drop") %>%
    pivot_wider(names_from = group, values_from = s)
  m <- x %>% filter(group != "Excluded")
  p <- kruskal.test(v ~ factor(group), m)$p.value
  tb %>% mutate(Characteristic = lab, Level = "median (IQR)", p_across_response = fmt_p(p), .before = 1)
}
n_row <- d0 %>% count(group) %>% mutate(n = as.character(n)) %>% pivot_wider(names_from = group, values_from = n) %>%
  mutate(Characteristic = "Patients, n", Level = "", .before = 1)
fu <- lm_main %>% filter(event == 0) %>% group_by(response4) %>% summarise(s = sprintf("%.0f (%.0f-%.0f)", median(time),
  quantile(time, 0.25), quantile(time, 0.75)), .groups = "drop")
fu_row <- fu %>% mutate(response4 = as.character(response4)) %>% pivot_wider(names_from = response4, values_from = s) %>%
  mutate(Characteristic = "Follow-up after landmark in survivors, months", Level = "median (IQR)", .before = 1)
rkm <- summary(survfit(Surv(time, 1 - event) ~ 1, data = lm_main))$table["median"]
death_row <- lm_main %>% group_by(response4) %>% summarise(s = sprintf("%d (%.0f%%)", sum(event), 100 * mean(event))) %>%
  mutate(response4 = as.character(response4)) %>% pivot_wider(names_from = response4, values_from = s) %>%
  mutate(Characteristic = "Deaths after landmark", Level = "n (%)", .before = 1)
tab1 <- bind_rows(n_row, cont_row("age", "Age, years"), cat_row("stage_group", "FIGO stage"), cat_row("grade_table", "Grade"),
  cat_row("residual_group", "Residual disease"), cat_row("regimen", "First-line regimen (GDC)"),
  cont_row("duration", "First-line chemotherapy duration, days"), cont_row("therapy_end", "End of first-line therapy, days from diagnosis"),
  cat_row("label_source", "Response label source"), fu_row, death_row,
  d0 %>% filter(group == "Excluded") %>% summarise(Excluded = paste(table(response4)[c("CR", "PR", "SD", "PD")], collapse = "/")) %>%
    mutate(Characteristic = "First-line response of excluded patients", Level = "CR/PR/SD/PD", .before = 1)) %>%
  select(Characteristic, Level, CR, PR, SD, PD, Excluded, p_across_response) %>%
  mutate(across(everything(), ~ coalesce(.x, "")))
write_csv(tab1, file.path(out_tab, "Table1_baseline_main_cohort.csv"))

ext_audit <- read_csv(file.path(t4, "external_cohort_audit.csv"), show_col_types = FALSE) %>% filter(set == "primary") %>%
  select(cohort, platform, retracted_source, n, CR, Non_CR, PR, SD, PD)
ext_cox <- read_csv(file.path(t4, "os_cox_noncr_vs_cr.csv"), show_col_types = FALSE)
ext_tab <- ext_audit %>% left_join(ext_cox %>% filter(landmark_days == 0) %>% select(cohort, n_OS = n, OS_events = events), by = "cohort") %>%
  left_join(ext %>% filter(!is.na(noncr)) %>% group_by(cohort) %>% summarise(optimal_debulking = sprintf("%d/%d", sum(debulk_optimal == 1, na.rm = TRUE),
    sum(!is.na(debulk_optimal))), median_OS_months = round(median(os_days, na.rm = TRUE) / mo, 1)), by = "cohort")
# Persist supplementary tables under the exact filenames consumed by the
# submission builder so a clean clone has no hidden manual-copy step.
write_csv(ext_tab, file.path(out_tab, "TableS1_external_cohorts.csv"))
pancancer_audit_file <- file.path(tpc, "label_semantics_audit_by_cancer.csv")
# R0 percentages come from the UCSC Xena clinical matrices (script 15) and are
# joined here so the supplementary table matches the reported values.
r0_xena <- read_csv(file.path(tpc, "residual_R0_by_response_xena.csv"), show_col_types = FALSE) %>%
  select(cancer, xena_R0_CR = pct_R0_CR, xena_R0_nonCR = pct_R0_nonCR)
read_csv(pancancer_audit_file, show_col_types = FALSE) %>% left_join(r0_xena, by = "cancer") %>%
  mutate(pct_R0_CR = coalesce(pct_R0_CR, xena_R0_CR), pct_R0_nonCR = coalesce(pct_R0_nonCR, xena_R0_nonCR)) %>%
  select(-xena_R0_CR, -xena_R0_nonCR) %>%
  write_csv(file.path(out_tab, "TableS4_pancancer_label_audit.csv"), na = "NA")
power_requirements <- read_csv(
  file.path(t18, "pd_step_required_sample_size.csv"),
  show_col_types = FALSE
)
pancancer_models <- read_csv(
  file.path(tpc, "topology_models_by_set.csv"),
  show_col_types = FALSE
)
manuscript_parameters <- tibble(
  key = c(
    "date_imputation_replicates", "pd_event_fraction", "pancancer_minimum_noncr",
    "pancancer_minimum_cr", "pancancer_minimum_os_events", "pancancer_ov_all_n",
    "tipping_day_minimum", "tipping_day_maximum", "target_power", "alpha"
  ),
  value = as.character(c(
    imp$imputations[[1]], power_requirements$event_fraction_assumed[[1]],
    analysis_config$pancancer$minimum_noncr, analysis_config$pancancer$minimum_cr,
    analysis_config$pancancer$minimum_os_events,
    pancancer_models %>%
      filter(set == "OV_all", endpoint == "OS", landmark == "none", adjustment == "unadjusted") %>%
      pull(n) %>% first(),
    min(analysis_config$landmark$tipping_days), max(analysis_config$landmark$tipping_days),
    analysis_config$power$target_power, analysis_config$survival$alpha
  ))
)
write_csv(manuscript_parameters, file.path(out_tab, "manuscript_parameters.csv"))

# ------------------------------------------------------------------ Figure 3
meta <- read_csv(file.path(t4, "os_meta_noncr_vs_cr.csv"), show_col_types = FALSE)
m3main <- tab2 %>% filter(time_origin == "End of first-line chemotherapy (main)", adjustment == "none")
f3a <- bind_rows(
  ext_cox %>% filter(cohort == "TCGA", landmark_days == 0) %>% transmute(label = "TCGA-OV, diagnosis", n, HR, HR_low, HR_high, type = "TCGA"),
  m3main %>% transmute(label = "TCGA-OV, end of first-line therapy", n, HR = HR_NonCR, HR_low = HR_NonCR_low, HR_high = HR_NonCR_high, type = "TCGA"),
  ext_cox %>% filter(cohort %in% c("GSE63885", "GSE23554", "GSE30161"), landmark_days == fixed_landmark) %>%
    transmute(label = paste0(cohort, ", 6-month landmark"), n, HR, HR_low, HR_high, type = "External"),
  meta %>% filter(landmark_days == fixed_landmark, k == 3) %>% transmute(label = sprintf("External REML (k=%d, I\u00b2=%.0f%%)", k, I2),
    n = sum(ext_cox$n[ext_cox$cohort %in% c("GSE63885", "GSE23554", "GSE30161") & ext_cox$landmark_days == fixed_landmark]),
    HR, HR_low, HR_high, type = "Pooled"),
  ext_cox %>% filter(cohort == "PMID17290060", landmark_days == fixed_landmark) %>%
    transmute(label = "PMID17290060 (retracted; sensitivity)", n, HR, HR_low, HR_high, type = "Retracted")) %>%
  mutate(label = factor(label, levels = rev(label)), txt = sprintf("%.2f (%.2f–%.2f)", HR, HR_low, HR_high),
         n_txt = as.character(n))

# Separate, fixed-width numeric columns share the exact discrete y scale with
# the forest plot. Headers occupy additional top space, never a data row.
# Input: none. Return: shared discrete-y scale with fixed header/row clearance;
# identical expansion keeps forest and numeric-column rows aligned.
forest_scale_y <- function() scale_y_discrete(expand = expansion(add = c(0.6, 1.2)))
# Input: forest rows with ordered factor label, txt/n_txt, and count-column heading.
# Return: fixed-width numeric-column ggplot sharing the forest's y scale.
# Factor order and row labels are already established; no estimates are fitted.
forest_columns <- function(d, count_header) {
  header_y <- nlevels(d$label) + 0.85
  ggplot(d, aes(y = label)) +
    geom_text(aes(x = 0, label = txt), hjust = 0, size = figure_text, family = figure_spec$font_family) +
    geom_text(aes(x = 34, label = n_txt), hjust = 1, size = figure_text, family = figure_spec$font_family) +
    annotate("text", x = 0, y = header_y, label = "HR (95% CI)", hjust = 0,
             fontface = "bold", size = figure_text, family = figure_spec$font_family) +
    annotate("text", x = 34, y = header_y, label = count_header, hjust = 1,
             fontface = "bold", size = figure_text, family = figure_spec$font_family) +
    forest_scale_y() + scale_x_continuous(limits = c(0, 34), expand = expansion(mult = c(0, 0))) +
    coord_cartesian(clip = "off") + formal_figure_theme(figure_spec, base = "void") +
    theme(plot.margin = margin(2, 2, 2, 1, unit = "mm"))
}
# Coordinate panels open their axes exactly like Figure 2A-C (scripts/17):
# no panel box, black left/bottom axis lines, light grey major gridlines.
figure3_open_axes <- theme(
  panel.border = element_blank(),
  axis.line = element_line(colour = "black", linewidth = 0.4),
  panel.grid.major = element_line(linewidth = 0.3, colour = "grey88")
)
pA_forest <- ggplot(f3a, aes(HR, label, xmin = HR_low, xmax = HR_high, colour = type, shape = type)) +
  geom_vline(xintercept = 1, linetype = 2) + geom_errorbar(width = 0.25, orientation = "y") +
  geom_point(data = dplyr::filter(f3a, type != "Retracted"), size = 2.2, stroke = 0.5) +
  geom_point(data = dplyr::filter(f3a, type == "Retracted"), size = 2.2, stroke = 0.7) +
  scale_x_log10(limits = c(0.8, 110), breaks = c(1, 2, 4, 8, 16, 32, 64)) + forest_scale_y() +
  # Source is encoded by shape and neutral tone only, matching Figure 1B and
  # avoiding the CR/PR green and blue used by the Kaplan-Meier panel below.
  scale_colour_manual(values = c(
    TCGA = figure_style$neutral[["dark"]],
    External = figure_style$neutral[["dark"]],
    Pooled = figure_style$neutral[["dark"]],
    Retracted = figure_style$neutral[["muted_text"]]
  )) +
  scale_shape_manual(values = figure_style$cohort_shape) +
  labs(x = "OS HR, NCR vs CR (95% CI, log scale)", y = NULL, tag = "A") +
  formal_figure_theme(figure_spec) + figure3_open_axes +
  theme(legend.position = "none", plot.margin = margin(2, 2, 2, 2, unit = "mm"))
pA <- (pA_forest | forest_columns(f3a, "n")) +
  plot_layout(widths = grid::unit(c(1, 36), c("null", "mm")))

cols4 <- figure_style$response[c("CR", "PR", "SD", "PD")]
g183 <- g63_lm(fixed_landmark)
sf <- survfit(Surv(time, event) ~ response4, data = g183)
response_labels <- paste0(names(cols4), " (n=", table(g183$response4), ")")

# Figure 3B annotation, mirroring Figure 2A-B: unadjusted log-rank test and the
# median within-fold, comparable-pair-weighted Harrell C-index of response-only
# Cox models. Folds are stratified because GSE63885 has very few SD/PD patients;
# unstratified folds could leave a training set without a category. Seeds are
# offset per repeat so the fold assignments are deterministic.
cv_repeats <- analysis_config$resampling$cross_validation_repeats
cv_folds <- analysis_config$resampling$cross_validation_folds
g183_cv <- g183 %>%
  mutate(response2 = factor(if_else(response4 == "CR", "CR", "NCR"), levels = c("CR", "NCR")))
g63_forms <- c(four_state_only = "response4", CR_threshold_only = "response2")
g63_fold_rows <- list(); g63_assignment_rows <- list(); g63_cv_rows <- list()
for (r in seq_len(cv_repeats)) {
  set.seed(seed + r)
  folds <- integer(nrow(g183_cv))
  for (lev in levels(g183_cv$response4)) {
    ii <- which(g183_cv$response4 == lev)
    folds[ii] <- sample(rep(seq_len(cv_folds), length.out = length(ii)))
  }
  stopifnot(all(folds %in% seq_len(cv_folds)))
  g63_assignment_rows[[r]] <- tibble(repeat_id = r, row_id = seq_len(nrow(g183_cv)), fold_id = folds)
  lp <- matrix(NA_real_, nrow(g183_cv), length(g63_forms), dimnames = list(NULL, names(g63_forms)))
  repeat_counts <- list()
  for (k in seq_len(cv_folds)) {
    te <- g183_cv[folds == k, ]
    for (nm in names(g63_forms)) {
      f <- coxph(as.formula(paste("Surv(time, event) ~", g63_forms[[nm]])), g183_cv[folds != k, ], ties = "efron")
      stopifnot(all(is.finite(coef(f)[!is.na(coef(f))])))
      prediction <- as.numeric(predict(f, newdata = te, type = "lp"))
      lp[folds == k, nm] <- prediction
      repeat_counts[[length(repeat_counts) + 1]] <- as_tibble(
        cv_fold_concordance(te$time, te$event, prediction)
      ) %>% mutate(repeat_id = r, fold_id = k, cv_model = nm, .before = 1)
    }
  }
  repeat_counts <- bind_rows(repeat_counts)
  stopifnot(!anyNA(lp), all(repeat_counts %>% group_by(fold_id) %>%
    summarise(k = n_distinct(comparable_pairs), .groups = "drop") %>% pull(k) == 1L))
  g63_fold_rows[[r]] <- repeat_counts
  g63_cv_rows[[r]] <- bind_rows(lapply(names(g63_forms), function(nm) {
    bind_cols(tibble(repeat_id = r, cv_model = nm), as_tibble(
      cv_repeat_concordance(repeat_counts %>% filter(cv_model == nm), nrow(g183_cv), cv_folds)
    )) %>% mutate(legacy_pooled_C_index =
      concordance(Surv(g183_cv$time, g183_cv$event) ~ lp[, nm], reverse = TRUE)$concordance)
  }))
}
g63_cv <- bind_rows(g63_cv_rows)
write_csv(bind_rows(g63_fold_rows), file.path(out_tab, "gse63885_cv_concordance_by_fold.csv"))
write_csv(bind_rows(g63_assignment_rows), file.path(out_tab, "gse63885_cv_fold_assignments.csv"))
# Input: response grouping survival formula. Return: unadjusted log-rank
# chi-square/df/p from observed GSE63885 landmark rows, not CV predictions.
# The same eligible cohort supplies both response-only CV and the KM panel.
g63_logrank <- function(formula) {
  s <- survdiff(formula, data = g183_cv)
  tibble(chisq = unname(s$chisq), df = length(s$n) - 1L,
         p = pchisq(s$chisq, length(s$n) - 1L, lower.tail = FALSE))
}
fig3b_stats <- bind_rows(
  g63_logrank(Surv(time, event) ~ response4) %>% mutate(panel = "Four-state", cv_model = "four_state_only"),
  g63_logrank(Surv(time, event) ~ response2) %>% mutate(panel = "CR vs NCR", cv_model = "CR_threshold_only")
) %>%
  left_join(g63_cv %>% group_by(cv_model) %>% summarise(
    median_cv_C = median(C_index), q05_cv_C = quantile(C_index, split_quantiles[1]),
    q95_cv_C = quantile(C_index, split_quantiles[2]), .groups = "drop"), by = "cv_model") %>%
  mutate(cohort = "GSE63885", landmark_days = fixed_landmark, n = nrow(g183_cv),
         events = sum(g183_cv$event), repeats = cv_repeats, folds = cv_folds,
         n_SD = sum(g183_cv$response4 == "SD"), n_PD = sum(g183_cv$response4 == "PD"))
write_csv(fig3b_stats, file.path(out_tab, "figure3b_km_statistics.csv"))
fig3b_four <- fig3b_stats %>% filter(panel == "Four-state")
fig3b_label <- sprintf(
  "Log-rank %s\nCV C-index = %.3f\n(CV n=%d)",
  if (fig3b_four$p < 0.001) "P<0.001" else sprintf("P=%.3f", fig3b_four$p),
  fig3b_four$median_cv_C, as.integer(fig3b_four$n)
)
km <- ggsurvplot(sf, data = g183, palette = unname(cols4), legend.labs = response_labels,
  risk.table = FALSE, xlim = c(0, 120), break.time.by = 24, xlab = "Months after 6-month landmark", ylab = "Overall survival",
  ggtheme = formal_figure_theme(figure_spec) + figure3_open_axes,
  censor.size = 1.8, legend.title = "")
# Response curves are solid and distinguished by the shared response palette;
# the KM panel inherits the open-axis style of the Figure 2 Kaplan-Meier panels.
pB_km <- km$plot +
  annotate("text", x = 118, y = 0.70, label = fig3b_label, hjust = 1, vjust = 1,
           size = figure_text, lineheight = 0.95, family = figure_spec$font_family) +
  labs(tag = "B", title = "GSE63885 (serous, four-class)") +
  theme(
    legend.position = "inside", legend.position.inside = c(0.98, 0.98),
    legend.justification = c(1, 1), legend.background = element_blank(),
    legend.key = element_blank(), legend.title = element_blank(),
    legend.key.width = unit(8, "mm"), legend.key.height = unit(3.4, "mm"),
    plot.margin = margin(2, 2, 2, 2, unit = "mm")
  )

# Display-only horizon: counts use full observed follow-up, without
# administrative censoring. The KM and risk table share the same x expansion.
risk_times <- seq(0, 120, by = 24)
fig3b_risk <- bind_rows(lapply(names(cols4), function(g) {
  tibble(cohort = "GSE63885", landmark_days = fixed_landmark, group = g,
    months = risk_times,
    at_risk = vapply(risk_times, function(t) sum(g183$time[g183$response4 == g] >= t), integer(1)))
}))
stopifnot(nrow(fig3b_risk) == 24L,
  all(fig3b_risk$at_risk[fig3b_risk$months == 0] == as.integer(table(g183$response4))))
write_csv(fig3b_risk, file.path(out_tab, "figure3b_number_at_risk.csv"))
pB_risk <- fig3b_risk %>% mutate(group = factor(group, levels = rev(names(cols4)))) %>%
  ggplot(aes(months, group, label = at_risk, colour = group)) +
  geom_text(size = figure_text, family = figure_spec$font_family, show.legend = FALSE) +
  scale_colour_manual(values = cols4) + scale_x_continuous(breaks = risk_times) +
  coord_cartesian(xlim = c(0, 120)) + labs(x = NULL, y = NULL, subtitle = "Number at risk") +
  formal_figure_theme(figure_spec) +
  theme(panel.grid = element_blank(), panel.border = element_blank(), axis.ticks = element_blank(),
    axis.text.x = element_blank(), plot.margin = margin(0, 2, 1, 2, unit = "mm"))
pB <- pB_km / pB_risk + plot_layout(heights = c(0.76, 0.24))

# PD vs PR+SD from the M_PD model (CR | PR+SD | PD) in every row, for consistency with Table 2.
# Input: exact Table 2 origin, adjustment and cohort keys. Return: matching
# observed result rows, including imported robust/pooled rows; no fit is run.
# Call sites rely on unique keys, not approximate string matching.
pick <- function(origin, adj = "none", co = "TCGA-OV") tab2 %>% filter(cohort == co, time_origin == origin, adjustment == adj)
f3c <- bind_rows(
  pick("Diagnosis, all labelled") %>% mutate(label = "TCGA-OV, diagnosis", imputed = FALSE),
  pick("Fixed 6-month landmark") %>% mutate(label = "TCGA-OV, 6-month landmark", imputed = FALSE),
  pick("End of first-line chemotherapy (main)") %>% mutate(label = "TCGA-OV, end of first-line therapy", imputed = FALSE),
  pick("End of chemotherapy, IPW for inclusion") %>% mutate(label = "TCGA-OV, therapy end: IPW", imputed = FALSE),
  pick(imputation_label) %>% mutate(label = "TCGA-OV, therapy end: dates imputed", imputed = TRUE),
  pick("Fixed 6-month landmark", co = "GSE63885") %>% mutate(label = "GSE63885, 6-month landmark", imputed = FALSE)) %>%
  transmute(label, PD, imputed, HR = HR_PD_vs_PRSD, HR_low = HR_PD_vs_PRSD_low, HR_high = HR_PD_vs_PRSD_high) %>%
  mutate(label = factor(label, levels = rev(label)), txt = sprintf("%.2f (%.2f–%.2f)", HR, HR_low, HR_high),
    n_txt = paste0(as.integer(PD), if_else(imputed, "*", "")))
pC_forest <- ggplot(f3c, aes(HR, label, xmin = HR_low, xmax = HR_high)) + geom_vline(xintercept = 1, linetype = 2) +
  annotate("rect", xmin = equivalence_margin[[1]], xmax = equivalence_margin[[2]],
    ymin = -Inf, ymax = Inf, alpha = 0.08) +
  geom_errorbar(width = 0.25, orientation = "y") + geom_point(size = 2.2) +
  scale_x_log10(limits = c(0.5, 16), breaks = c(0.5, 1, 2, 4, 8, 16)) + forest_scale_y() +
  labs(x = sprintf("OS HR, PD vs PR+SD (95%% CI, log scale)\nShaded reference bounds: %.2f–%.2f",
    equivalence_margin[[1]], equivalence_margin[[2]]), y = NULL, tag = "C") +
  formal_figure_theme(figure_spec) + figure3_open_axes +
  theme(axis.title.x = element_text(lineheight = 1.2),
    plot.margin = margin(2, 2, 2, 2, unit = "mm"))
pC <- (pC_forest | forest_columns(f3c, "PD n")) +
  plot_layout(widths = grid::unit(c(1, 36), c("null", "mm")))
# Final double-column layout: panels are stacked so that every label is set
# at the configured minimum size without downstream scaling.
# Fail rather than silently drop any confidence interval outside the axis limits.
stopifnot(min(f3a$HR_low) > 0.8, max(f3a$HR_high) < 110, min(f3c$HR_low) > 0.5, max(f3c$HR_high) < 16)
# The KM/risk-table block is freed from forest-label alignment so it spans
# the full width, while its own two panels retain exact x-axis alignment.
fig3 <- pA / free(pB) / pC + plot_layout(heights = c(0.28, 0.44, 0.28))
save_formal_figure(fig3, file.path(out_fig, "Figure3_external_replication"), height_mm = 230, spec = figure_spec)

# ------------------------------------------------------------------ Figure 1 (flow)
# CONSORT-style study diagram drawn in millimetre coordinates at final size.
# Every displayed count is read from a locked result table; the counts are also
# written to tables/manuscript/Figure1_flow_counts.csv for claim auditing.
fl0 <- read_csv(file.path(results_dir, "tables", "cohort_flow.csv"), show_col_types = FALSE)
fl17 <- read_csv(file.path(t17, "landmark_cohort_flow.csv"), show_col_types = FALSE)
ex17 <- read_csv(file.path(t17, "landmark_exclusion_reasons.csv"), show_col_types = FALSE) %>%
  mutate(total = CR + PR + SD + PD)
by_response <- read_csv(file.path(t17, "landmark_cohort_by_response.csv"), show_col_types = FALSE) %>%
  mutate(n = landmark_FALSE + landmark_TRUE)
main_topology <- read_csv(file.path(t17, "topology_by_landmark.csv"), show_col_types = FALSE) %>%
  filter(endpoint == "OS", landmark == "therapy_end", adjustment == "none")
pc <- read_csv(file.path(tpc, "label_semantics_audit_by_cancer.csv"), show_col_types = FALSE)
pcm <- read_csv(file.path(tpc, "dichotomy_meta.csv"), show_col_types = FALSE) %>%
  filter(subset == "all", landmark == "therapy_end")
pc_dichotomy <- read_csv(file.path(tpc, "dichotomy_cr_vs_noncr_by_cancer.csv"), show_col_types = FALSE) %>%
  filter(subset == "all", landmark == "therapy_end")
pc_topology <- read_csv(file.path(tpc, "topology_models_by_set.csv"), show_col_types = FALSE) %>%
  filter(landmark == "therapy_end", endpoint == "OS", adjustment == "unadjusted")
ext_histology <- read_csv(file.path(t4, "external_cohort_audit.csv"), show_col_types = FALSE)
# Input: exact upstream flow-step key. Return: recorded cohort-flow count;
# the locked table must contain one matching row, never a default count.
ng <- function(step) fl0$n[fl0$step == step]
# Input: exact landmark flow-step key. Return: its recorded sequential OS count.
# Preserve script 17's denominator rather than use the raw GDC record total.
nl <- function(step) fl17$n[fl17$step == step]
# Input: exact mutually exclusive exclusion reason. Return: observed total
# across four response states; these categories reconstruct sequential flow.
ne <- function(r) ex17$total[ex17$reason == r]
# Input: response category. Return: labelled included-plus-excluded count from
# the locked response-flow table, not a manually entered manuscript number.
nr <- function(category) by_response$n[by_response$response4 == category]
inc <- ex17 %>% filter(reason == "included")
stopifnot(nrow(inc) == 1L, nrow(main_topology) == 1L, nrow(pcm) == 1L)

# All post-label counts use the OS analysis set as their denominator. The raw
# GDC counts include one labelled patient without OS, so the sequential counts
# are reconstructed from the mutually exclusive exclusion reasons.
n_records <- ng("OV clinical-matrix rows")
n_primary <- ng("Primary-tumor clinical rows")
n_linked <- ng("Expression-linked primary tumors")
n_labelled <- nl("Labelled cohort")
n_os <- nl("OS available")
n_regimen_os <- n_os - ne("no first-line regimen record")
n_end_os <- n_regimen_os - ne("no therapy end date")
n_plausible_os <- n_end_os - ne(implausible_end_reason)
n_landmark <- sum(unlist(inc[c("CR", "PR", "SD", "PD")], use.names = FALSE))
labelled_counts <- vapply(c("CR", "PR", "SD", "PD"), nr, numeric(1))
stopifnot(
  n_labelled == ng("Canonical CR/PR/SD/PD available"),
  n_labelled == sum(labelled_counts),
  n_os == ng("Response plus usable OS"),
  n_landmark == main_topology$n,
  all(unlist(inc[c("CR", "PR", "SD", "PD")]) == unlist(main_topology[c("CR", "PR", "SD", "PD")])),
  n_os - n_landmark == sum(ex17$total[ex17$reason != "included"])
)
n_landmark_ncr <- n_landmark - inc$CR

# External cohorts share one fixed landmark from diagnosis; the validation
# stage and this display read separate keys, so their agreement is asserted.
external_landmark_days <- analysis_config$external_validation$landmark_days
stopifnot(external_landmark_days == fixed_landmark)
external_landmark_months <- round(external_landmark_days / mo)
ext_rows <- ext_histology %>%
  select(cohort, set, n, retracted_source) %>%
  pivot_wider(names_from = set, values_from = n) %>%
  left_join(
    ext_cox %>% filter(landmark_days == external_landmark_days) %>%
      select(cohort, landmark_n = n, landmark_events = events),
    by = "cohort"
  )
stopifnot(!anyNA(ext_rows$landmark_n), sum(ext_rows$retracted_source) == 1L)
ext_primary <- ext_rows %>% filter(!retracted_source)
# Only cohorts with PR, SD and PD all observed support four-category analyses.
four_class_cohort <- ext_histology %>% filter(set == "primary", !retracted_source, PR > 0, SD > 0, PD > 0) %>% pull(cohort)
stopifnot(length(four_class_cohort) == 1L)
ext_retracted <- ext_rows %>% filter(retracted_source)
ext_pooled <- c(n = sum(ext_primary$landmark_n), events = sum(ext_primary$landmark_events))

pc_sets <- c(OV = "OV_all", LGG = "LGG_all", `Treated BLCA` = "BLCA_treated")
pc_set_n <- vapply(pc_sets, function(s) pc_topology$n[pc_topology$set == s], numeric(1))
stopifnot(nrow(pc_dichotomy) == pcm$k)
pc_dichotomy_n <- sum(pc_dichotomy$n)
pc_dichotomy_ov <- pc_dichotomy$n[pc_dichotomy$cancer == "OV"]

flow_counts <- bind_rows(
  tibble(panel = "A", item = "clinical_records", n = n_records),
  tibble(panel = "A", item = "primary_tumours", n = n_primary, excluded = n_records - n_primary),
  tibble(panel = "A", item = "expression_linked", n = n_linked, excluded = n_primary - n_linked),
  tibble(panel = "A", item = "labelled", n = n_labelled, excluded = n_linked - n_labelled,
    CR = labelled_counts[["CR"]], PR = labelled_counts[["PR"]], SD = labelled_counts[["SD"]], PD = labelled_counts[["PD"]]),
  tibble(panel = "A", item = "os_available", n = n_os, excluded = n_labelled - n_os),
  tibble(panel = "A", item = "first_line_record", n = n_regimen_os, excluded = n_os - n_regimen_os),
  tibble(panel = "A", item = "therapy_end_recorded", n = n_end_os, excluded = n_regimen_os - n_end_os),
  tibble(panel = "A", item = "plausible_therapy_end", n = n_plausible_os, excluded = n_end_os - n_plausible_os),
  tibble(panel = "A", item = "landmark_cohort", n = n_landmark, excluded = n_plausible_os - n_landmark,
    CR = inc$CR, PR = inc$PR, SD = inc$SD, PD = inc$PD, events = main_topology$events),
  ext_rows %>% transmute(panel = "B", item = paste0("external_", cohort), n = landmark_n,
    events = landmark_events, all_histology, serous = primary),
  tibble(panel = "B", item = "external_pooled_primary", n = ext_pooled[["n"]], events = ext_pooled[["events"]],
    k = nrow(ext_primary)),
  tibble(panel = "C", item = "pancancer_labelled", n = sum(pc$n), k = nrow(pc)),
  tibble(panel = "C", item = paste0("pancancer_topology_", pc_sets), n = pc_set_n),
  tibble(panel = "C", item = "pancancer_dichotomy_therapy_end", n = pc_dichotomy_n,
    events = sum(pc_dichotomy$events), k = nrow(pc_dichotomy))
)
write_csv(flow_counts, file.path(out_tab, "Figure1_flow_counts.csv"), na = "")

# ---- Layout (millimetres; y runs downward from the top of the drawing area)
draw_w <- figure_spec$width_mm - 6
line_mm <- figure_spec$min_font_pt * 1.05 / ggplot2::.pt
# The landmark box is drawn as separate one-line grobs and the coding box as a
# multiline label. Both carry the figure's ~10.1 pt leading, so their heights
# must reserve that leading plus a visible top/bottom clearance instead of the
# single-line height used by the flow boxes.
line_lead_mm <- figure_spec$min_font_pt * 1.26 / ggplot2::.pt
glyph_mm <- figure_spec$min_font_pt * 1.116 / ggplot2::.pt
box_h_lead <- function(lines) (lines - 1) * line_lead_mm + glyph_mm + 2.4
pad_mm <- 3.0
# Input: text-line count(s). Return: box height(s) in millimetres at the fixed
# line spacing/padding; geometry only, never a scientific sample threshold.
box_h <- function(lines) lines * line_mm + pad_mm
# Input: numeric counts. Return: comma-separated display strings with no
# surrounding padding; the observed counts themselves remain unchanged.
fmt_n <- function(x) format(x, big.mark = ",", trim = TRUE)
neutral <- figure_style$neutral
col_a <- c(left = 0, right = 50)
col_x <- c(left = 53, right = 85.5)
col_b <- c(left = 87.5, right = 139.5)
col_c <- c(left = 142, right = 184)
trunk_c <- 143.5
col_c_box <- c(left = 147, right = 184)
top_y <- 12

a_labels <- list(
  sprintf("TCGA-OV clinical records, n = %d\nSources: TCGA-CDR, Xena, GDC", n_records),
  sprintf("Primary tumours\nn = %d", n_primary),
  sprintf("Linked to U133A expression\nn = %d", n_linked),
  sprintf("Canonical response label, n = %d\nCR %d | PR %d | SD %d | PD %d", n_labelled,
    labelled_counts[["CR"]], labelled_counts[["PR"]], labelled_counts[["SD"]], labelled_counts[["PD"]]),
  sprintf("Overall survival available\nn = %d", n_os),
  sprintf("First-line treatment record\nn = %d", n_regimen_os),
  sprintf("Recorded end of first-line therapy\nn = %d", n_end_os),
  sprintf("L = end of first-line therapy,\n%d–%d days after diagnosis\nn = %d",
    landmark_bounds[[1]], landmark_bounds[[2]], n_plausible_os),
  sprintf("Landmark cohort\nn = %d (%d deaths)\nAlive and under observation beyond L\nCR %d | NCR %d\n(PR %d, SD %d, PD %d)",
    n_landmark, main_topology$events, inc$CR, n_landmark_ncr, inc$PR, inc$SD, inc$PD),
  "Response codings compared\nM1 four-category\nM2 objective response\nM3 CR versus NCR; M_PD post hoc\nSelection and treatment sensitivity"
)
a_excl <- c(
  sprintf("Non-primary-tumour\nrecords, n = %d", n_records - n_primary),
  sprintf("Not linked to U133A\nexpression, n = %d", n_primary - n_linked),
  sprintf("No canonical response\nlabel, n = %d", n_linked - n_labelled),
  sprintf("OS unavailable, n = %d", n_labelled - n_os),
  sprintf("No first-line treatment\nrecord, n = %d", n_os - n_regimen_os),
  sprintf("No recorded end date\nn = %d", n_regimen_os - n_end_os),
  sprintf("End outside %d–%d\ndays, n = %d", landmark_bounds[[1]], landmark_bounds[[2]], n_end_os - n_plausible_os),
  sprintf("Died or censored on\nor before L, n = %d", n_plausible_os - n_landmark)
)
a_gap <- c(rep(6.2, length(a_excl)), 3.6)
a_lines <- vapply(a_labels, function(s) length(strsplit(s, "\n", fixed = TRUE)[[1]]), numeric(1))
a_h <- box_h(a_lines)
# The landmark and coding boxes are the only five-line boxes in panel A; give
# them the explicit leading-based height so neither text touches its border.
stopifnot(identical(tail(a_lines, 2L), c(5, 5)))
a_h[seq(length(a_h) - 1L, length(a_h))] <- box_h_lead(rep(5, 2))
a_top <- top_y + c(0, cumsum(a_h[-length(a_h)] + a_gap))
a_boxes <- tibble(
  id = paste0("a", seq_along(a_labels) - 1L), left = col_a[["left"]], right = col_a[["right"]],
  top = a_top, bottom = a_top + a_h, label = unlist(a_labels),
  fill = c(rep(neutral[["fill"]], 9), "white"), linewidth = c(rep(0.45, 8), 1.1, 0.45), linetype = "solid"
)
# The canvas height follows the TCGA flow, the tallest column.
draw_h <- ceiling(max(a_boxes$bottom) + 2)
fig1_height_mm <- draw_h + 6
landmark_box <- a_boxes %>% filter(id == "a8")
terminal_box <- a_boxes %>% filter(id == "a9")
gap_mid <- (a_boxes$bottom[-nrow(a_boxes)] + a_boxes$top[-1]) / 2
a_excl_tbl <- tibble(y = gap_mid[seq_along(a_excl)], label = a_excl,
  lines = vapply(strsplit(a_excl, "\n", fixed = TRUE), length, numeric(1))) %>%
  mutate(top = y - box_h(lines) / 2, bottom = y + box_h(lines) / 2)
a_cx <- mean(col_a)

# Panel B: response-labelled cohorts, landmark table and the retracted cohort.
b0 <- tibble(id = "b0", left = col_b[["left"]], right = col_b[["right"]], top = top_y,
  bottom = top_y + box_h(2), label = "Response-labelled cohorts\ncuratedOvarianData and GEO")
# Analysis-level boxes share rows across panels; the table sits midway.
# The table uses 2.5 pt more row leading than the flow boxes so the header rule
# can sit midway between the descenders of "n (deaths)" and the first data row.
b_line_mm <- (figure_spec$min_font_pt + 2.5) / ggplot2::.pt
b_table_h <- 10 * b_line_mm + pad_mm + 1.2
b_outcome <- tibble(id = "b2", left = col_b[["left"]], right = col_b[["right"]],
  top = (landmark_box$top + landmark_box$bottom - box_h(2)) / 2,
  bottom = (landmark_box$top + landmark_box$bottom + box_h(2)) / 2,
  label = sprintf("Pooled CR versus NCR OS (k = %d)\nFour-category OS: %s only",
    nrow(ext_primary), four_class_cohort))
b_gap <- (b_outcome$top - b0$bottom - b_table_h) / 2
b_table_top <- b0$bottom + b_gap
b_table_bottom <- b_table_top + b_table_h
row_y <- b_table_top + pad_mm / 2 + b_line_mm * (seq_len(10) - 0.5)
b_retracted <- tibble(left = col_b[["left"]], right = col_b[["right"]],
  top = (terminal_box$top + terminal_box$bottom - box_h(5)) / 2,
  bottom = (terminal_box$top + terminal_box$bottom + box_h(5)) / 2)
# Row markers reuse the Figure 3A cohort shapes, drawn in neutral grey.
cx_marker <- col_b[["left"]] + 2.3
cx_cohort <- col_b[["left"]] + 4.3
cx_all <- col_b[["left"]] + 22
cx_serous <- col_b[["left"]] + 30.0
cx_lm <- col_b[["right"]] - 1.5
# Input: aligned observed patient/death counts. Return: "n (deaths)" strings;
# these are display values, not an event-fraction assumption for power.
fmt_ev <- function(n, e) sprintf("%d (%d)", n, e)
b_cells <- bind_rows(
  tibble(x = mean(col_b), y = row_y[1], label = sprintf("Fixed %d-month (%d-day) landmark", external_landmark_months, external_landmark_days), hjust = 0.5, face = "italic"),
  tibble(x = mean(col_b), y = row_y[2], label = "from diagnosis", hjust = 0.5, face = "italic"),
  tibble(x = c(cx_cohort, cx_all, cx_serous, cx_lm), y = row_y[4],
    label = c("Cohort", "All", "Serous", "Landmark"), hjust = c(0, 0.5, 0.5, 1), face = "bold"),
  tibble(x = cx_lm, y = row_y[5], label = "n (deaths)", hjust = 1, face = "bold"),
  tibble(x = cx_cohort, y = row_y[6:8], label = ext_primary$cohort, hjust = 0, face = "plain"),
  tibble(x = cx_all, y = row_y[6:8], label = as.character(ext_primary$all_histology), hjust = 0.5, face = "plain"),
  tibble(x = cx_serous, y = row_y[6:8], label = as.character(ext_primary$primary), hjust = 0.5, face = "plain"),
  tibble(x = cx_lm, y = row_y[6:8], label = fmt_ev(ext_primary$landmark_n, ext_primary$landmark_events), hjust = 1, face = "plain"),
  tibble(x = cx_cohort, y = row_y[9:10] + 1.2,
    label = c("Cohort-level REML", sprintf("meta-analysis (k = %d)", nrow(ext_primary))), hjust = 0, face = "plain"),
  tibble(x = cx_lm, y = row_y[9:10] + 1.2,
    label = c(sprintf("Total n = %d", ext_pooled[["n"]]), sprintf("(%d deaths)", ext_pooled[["events"]])), hjust = 1, face = "plain")
)
# Locked source/order assertion for the published primary-cohort display;
# retracted sources remain sensitivity-only and are never pooled here.
stopifnot(identical(ext_primary$cohort, c("GSE63885", "GSE23554", "GSE30161")))
b_rules <- tibble(x = col_b[["left"]] + 1.5, xend = col_b[["right"]] - 1.5,
  y = c(row_y[3] + 0.4, (row_y[5] + row_y[6]) / 2,
    (row_y[8] + row_y[9] + 1.2) / 2)) %>%
  mutate(yend = y)
b_ret_rows <- b_retracted$top + pad_mm / 2 + line_mm * (seq_len(5) - 0.5)
b_ret_cells <- tibble(
  x = cx_cohort,
  y = b_ret_rows,
  label = c(
    paste0(ext_retracted$cohort, "\u2020"),
    sprintf("All %d | Serous %d", ext_retracted$all_histology, ext_retracted$primary),
    sprintf("Landmark n (deaths) %d (%d)", ext_retracted$landmark_n, ext_retracted$landmark_events),
    "\u2020Retracted source: sensitivity",
    "analyses only, not pooled"
  ),
  hjust = 0
)
b_markers <- tibble(
  x = cx_marker,
  y = c(row_y[6:8], mean(row_y[9:10]) + 1.2, b_ret_rows[1]),
  type = c(rep("External", 3), "Pooled", "Retracted")
) %>% mutate(
  shape = figure_style$cohort_shape[type],
  colour = ifelse(type == "Retracted", neutral[["muted_text"]], neutral[["dark"]])
)

# Panel C: exploratory TCGA cross-cancer analyses.
c_labels <- c(
  sprintf("TCGA-CDR, %d tumour types\nn = %s labelled", nrow(pc), fmt_n(sum(pc$n))),
  "Response-label audit\nTreatment definition,\nresection and power",
  sprintf("Four-category topology\nOV n = %d; LGG n = %d\nTreated BLCA n = %d\n(exploratory)",
    pc_set_n[["OV"]], pc_set_n[["LGG"]], pc_set_n[["Treated BLCA"]]),
  sprintf("CR versus NCR\nfrom therapy end\n%d tumour types, n = %s\n(OV n = %d)",
    nrow(pc_dichotomy), fmt_n(pc_dichotomy_n), pc_dichotomy_ov)
)
c_h <- box_h(c(2, 3, 4, 4))
# Panel C is a frozen vector region; keep its analysis band at the approved
# position when panel A's flow boxes are re-spaced. Re-freezing C requires a new
# approval and must start from this anchored geometry, not from panel A.
c3_top <- 139.89
c3_bottom <- c3_top + c_h[4]
c0_top <- top_y
c1_top <- c0_top + c_h[1] + 8
c2_top <- (c1_top + c_h[2] + c3_top - c_h[3]) / 2
c_boxes <- tibble(
  id = paste0("c", 0:3),
  left = c(col_c[["left"]], col_c[["left"]], col_c_box[["left"]], col_c_box[["left"]]),
  right = col_c[["right"]], top = c(c0_top, c1_top, c2_top, c3_top),
  label = c_labels
) %>% mutate(bottom = top + c_h)
# Input: unique panel-C box id. Return: its vertical midpoint in top-origin mm;
# branch connectors use existing box geometry, not coordinates fitted to data.
c_mid <- function(id) (c_boxes$top[c_boxes$id == id] + c_boxes$bottom[c_boxes$id == id]) / 2
c_split <- c_boxes$bottom[2] + 3.5
c_trunk <- tibble(
  x = c(mean(col_c), mean(col_c), trunk_c),
  y = c(c_boxes$bottom[2], c_split, c_split),
  xend = c(mean(col_c), trunk_c, trunk_c),
  yend = c(c_split, c_split, c_mid("c3"))
)
c_branch <- tibble(x = trunk_c, xend = col_c_box[["left"]], y = c(c_mid("c2"), c_mid("c3")), yend = y)

all_boxes <- bind_rows(
  a_boxes,
  a_excl_tbl %>% transmute(id = "excl", left = col_x[["left"]], right = col_x[["right"]], top, bottom,
    label, fill = "white", linewidth = 0.35, linetype = "solid"),
  b0 %>% mutate(fill = neutral[["fill"]], linewidth = 0.45, linetype = "solid"),
  tibble(id = "b1", left = col_b[["left"]], right = col_b[["right"]], top = b_table_top,
    bottom = b_table_bottom, label = "", fill = neutral[["fill"]], linewidth = 0.45, linetype = "solid"),
  b_outcome %>% mutate(fill = "white", linewidth = 0.45, linetype = "solid"),
  b_retracted %>% mutate(id = "b3", label = "", fill = "white", linewidth = 0.45, linetype = "dashed"),
  c_boxes %>% mutate(fill = c(neutral[["fill"]], neutral[["fill"]], "white", "white"),
    linewidth = 0.45, linetype = "solid")
) %>% mutate(ymin = draw_h - bottom, ymax = draw_h - top, cy = draw_h - (top + bottom) / 2,
  cx = (left + right) / 2)
text_boxes <- all_boxes %>% filter(label != "", !id %in% c("excl", "a8"))
landmark_lines <- strsplit(landmark_box$label, "\n", fixed = TRUE)[[1]]
landmark_pad <- (box_h_lead(length(landmark_lines)) -
  ((length(landmark_lines) - 1) * line_lead_mm + glyph_mm)) / 2
landmark_line_y <- draw_h - (landmark_box$top + landmark_pad + glyph_mm / 2 +
  line_lead_mm * (seq_along(landmark_lines) - 1))

flow_arrows <- bind_rows(
  tibble(x = a_cx, xend = a_cx, y = a_boxes$bottom[-nrow(a_boxes)], yend = a_boxes$top[-1]),
  tibble(x = mean(col_b), xend = mean(col_b), y = c(b0$bottom, b_table_bottom), yend = c(b_table_top, b_outcome$top)),
  tibble(x = mean(col_c), xend = mean(col_c), y = c_boxes$bottom[1], yend = c_boxes$top[2])
)
excl_arrows <- tibble(x = a_cx, xend = col_x[["left"]], y = a_excl_tbl$y, yend = a_excl_tbl$y)
# Input: segment rows with top-origin y/yend in mm. Return: ggplot bottom-origin
# coordinates without changing x; all segments share the fixed canvas height.
flip <- function(d) mutate(d, y = draw_h - y, yend = draw_h - yend)
arrow_head <- arrow(length = unit(1.4, "mm"), type = "closed")
# Input: font points (default profile minimum). Return: ggplot text size in mm;
# the shared converter rejects sizes below the submission minimum.
txt <- function(pt = figure_spec$min_font_pt) figure_text_size(figure_spec, pt)
header_y <- draw_h - 2.2
headers <- tibble(
  x = c(a_cx, mean(col_b), mean(col_c)),
  label = c("TCGA-OV cohort and\nlandmark selection", "External serous\ncohorts", "Exploratory\ncross-cancer analyses")
)

fig1 <- ggplot() +
  geom_rect(data = all_boxes, aes(xmin = left, xmax = right, ymin = ymin, ymax = ymax,
    fill = fill, linetype = linetype, linewidth = linewidth), colour = neutral[["dark"]]) +
  geom_segment(data = flip(b_rules), aes(x, y, xend = xend, yend = yend), colour = neutral[["mid"]], linewidth = 0.25) +
  geom_segment(data = flip(flow_arrows), aes(x, y, xend = xend, yend = yend),
    colour = neutral[["dark"]], linewidth = 0.60, arrow = arrow_head) +
  geom_segment(data = flip(excl_arrows), aes(x, y, xend = xend, yend = yend),
    colour = neutral[["dark"]], linewidth = 0.45, arrow = arrow_head) +
  geom_segment(data = flip(c_trunk), aes(x, y, xend = xend, yend = yend),
    colour = neutral[["dark"]], linewidth = 0.40, lineend = "square") +
  geom_segment(data = flip(c_branch), aes(x, y, xend = xend, yend = yend),
    colour = neutral[["dark"]], linewidth = 0.40, arrow = arrow_head) +
  geom_text(data = text_boxes, aes(cx, cy, label = label),
    family = figure_spec$font_family, size = txt(), lineheight = 1.05) +
  annotate("text", x = a_cx, y = landmark_line_y, label = landmark_lines,
    fontface = c("bold", rep("plain", length(landmark_lines) - 1L)),
    family = figure_spec$font_family, size = txt()) +
  geom_text(data = a_excl_tbl, aes(x = col_x[["left"]] + 2, y = draw_h - y, label = label),
    family = figure_spec$font_family, size = txt(), lineheight = 1.05, hjust = 0) +
  geom_text(data = b_cells, aes(x, draw_h - y, label = label, hjust = hjust, fontface = face),
    family = figure_spec$font_family, size = txt()) +
  geom_text(data = b_ret_cells, aes(x, draw_h - y, label = label, hjust = hjust),
    family = figure_spec$font_family, size = txt(), colour = neutral[["muted_text"]]) +
  geom_point(data = b_markers, aes(x, draw_h - y, shape = shape, colour = colour), size = 2.2, stroke = 0.5) +
  annotate("text", x = mean(col_c), y = draw_h - (terminal_box$top + terminal_box$bottom) / 2,
    label = "Parallel analyses; eligibility from\nTCGA-CDR, not panel A",
    family = figure_spec$font_family, fontface = "italic", size = txt(), lineheight = 1.05) +
  annotate("text", x = c(col_a[["left"]], col_b[["left"]], col_c[["left"]]), y = header_y,
    label = c("A", "B", "C"), family = figure_spec$font_family, fontface = "bold",
    size = txt(figure_spec$tag_font_pt), hjust = 0, vjust = 0.75) +
  geom_text(data = headers, aes(x, header_y, label = label), vjust = 0.75,
    family = figure_spec$font_family, fontface = "bold", size = txt(9), lineheight = 1.0) +
  scale_fill_identity() + scale_linetype_identity() + scale_linewidth_identity() +
  scale_shape_identity() + scale_colour_identity() +
  coord_cartesian(xlim = c(0, draw_w), ylim = c(0, draw_h), expand = FALSE, clip = "off") +
  formal_figure_theme(figure_spec, base = "void") +
  theme(plot.margin = margin(3, 3, 3, 3, unit = "mm"))

stopifnot(max(all_boxes$bottom) <= draw_h - 1, all(all_boxes$right <= draw_w))
save_formal_figure(fig1, file.path(out_fig, "Figure1_study_design"), height_mm = fig1_height_mm, spec = figure_spec)

# Stage formal manuscript figures from their analysis-native locations. The
# mapping is written as provenance so no manual copy or rename is required.
main_figure_dir <- file.path(results_dir, "figures", "main")
supp_figure_dir <- file.path(results_dir, "figures", "supplementary")
dir.create(main_figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(supp_figure_dir, recursive = TRUE, showWarnings = FALSE)
unlink(
  list.files(
    supp_figure_dir,
    pattern = "^FigureS[1-6]_.*[.](png|pdf)$",
    full.names = TRUE
  )
)
figure_map <- tribble(
  ~source, ~destination,
  file.path(out_fig, "Figure1_study_design.png"), file.path(main_figure_dir, "Figure1_study_design.png"),
  file.path(out_fig, "Figure1_study_design.pdf"), file.path(main_figure_dir, "Figure1_study_design.pdf"),
  file.path(results_dir, "figures", "ov_therapy_end_landmark", "Figure2_therapy_end_topology.png"), file.path(main_figure_dir, "Figure2_therapy_end_topology.png"),
  file.path(results_dir, "figures", "ov_therapy_end_landmark", "Figure2_therapy_end_topology.pdf"), file.path(main_figure_dir, "Figure2_therapy_end_topology.pdf"),
  file.path(out_fig, "Figure3_external_replication.png"), file.path(main_figure_dir, "Figure3_external_replication.png"),
  file.path(out_fig, "Figure3_external_replication.pdf"), file.path(main_figure_dir, "Figure3_external_replication.pdf"),
  file.path(results_dir, "figures", "ov_selection_regimen_power", "FigS_selection_regimen_power.png"), file.path(supp_figure_dir, "FigureS1_selection_regimen_power.png"),
  file.path(results_dir, "figures", "ov_selection_regimen_power", "FigS_selection_regimen_power.pdf"), file.path(supp_figure_dir, "FigureS1_selection_regimen_power.pdf"),
  file.path(results_dir, "figures", "ov_hgsoc_sensitivity", "hgsoc_four_state_forest.png"), file.path(supp_figure_dir, "FigureS2_hgsoc_four_state.png"),
  file.path(results_dir, "figures", "ov_hgsoc_sensitivity", "hgsoc_four_state_forest.pdf"), file.path(supp_figure_dir, "FigureS2_hgsoc_four_state.pdf"),
  file.path(results_dir, "figures", "pancancer_topology", "dichotomy_forest_by_cancer.png"), file.path(supp_figure_dir, "FigureS3_pancancer_dichotomy.png"),
  file.path(results_dir, "figures", "pancancer_topology", "dichotomy_forest_by_cancer.pdf"), file.path(supp_figure_dir, "FigureS3_pancancer_dichotomy.pdf"),
  file.path(results_dir, "figures", "pancancer_topology", "four_state_hr_by_set.png"), file.path(supp_figure_dir, "FigureS4_pancancer_four_state.png"),
  file.path(results_dir, "figures", "pancancer_topology", "four_state_hr_by_set.pdf"), file.path(supp_figure_dir, "FigureS4_pancancer_four_state.pdf"),
  file.path(results_dir, "figures", "phase4_external_validation", "forest_general_proliferation.png"), file.path(supp_figure_dir, "FigureS5_external_proliferation.png"),
  file.path(results_dir, "figures", "phase4_external_validation", "forest_general_proliferation.pdf"), file.path(supp_figure_dir, "FigureS5_external_proliferation.pdf"),
  file.path(results_dir, "figures", "ov_response_sensitivity", "FigureS6_calibration.png"), file.path(supp_figure_dir, "FigureS6_calibration.png"),
  file.path(results_dir, "figures", "ov_response_sensitivity", "FigureS6_calibration.pdf"), file.path(supp_figure_dir, "FigureS6_calibration.pdf")
)
require_input_files(figure_map$source, "formal figure")
copy_ok <- mapply(
  file.copy, figure_map$source, figure_map$destination,
  MoreArgs = list(overwrite = TRUE), USE.NAMES = FALSE
)
stopifnot(all(copy_ok))
# Input: absolute figure path under the configured results directory. Return:
# portable results/... provenance path; stop for an outside path. Prefix checking
# assumes paths were constructed above, rather than accepting unresolved traversal.
as_result_relative <- function(path) {
  prefix <- paste0(results_dir, .Platform$file.sep)
  if (!startsWith(path, prefix)) stop("Figure path is outside the configured results directory: ", path)
  file.path("results", substring(path, nchar(prefix) + 1L))
}
write_csv(
  figure_map %>% transmute(
    source = vapply(source, as_result_relative, character(1)),
    destination = vapply(destination, as_result_relative, character(1))
  ),
  file.path(out_tab, "figure_provenance.csv")
)

# ------------------------------------------------------------------ Supplementary Data 1
excl_reason <- d0 %>% mutate(reason = case_when(
  !is.finite(OS_days) ~ "no OS", is.na(fl_start) ~ "no first-line regimen record",
  !is.finite(therapy_end) ~ "no therapy end date", !date_ok ~ implausible_end_reason,
  !(patient %in% main_ids) ~ "death/censoring before therapy end", TRUE ~ "included"))
write_csv(excl_reason %>% transmute(patient, response4, label_source, response_conflict, age, stage_group, grade, residual_group,
    OS_days, OS_event, PFI_days, PFI_event, fl_start, fl_end, fl_agents, regimen, therapy_end, main_landmark_cohort = patient %in% main_ids,
    exclusion_reason = reason), file.path(out_tab, "SupplementaryData1_TCGA_OV_cases.csv"))
write_csv(ext %>% select(cohort, sample, response4, noncr, os_days, os_event, debulk_optimal, grade, stage),
  file.path(out_tab, "SupplementaryData2_external_samples.csv"))
stopifnot(sum(excl_reason$reason == "included") == length(main_ids))

# ------------------------------------------------------------------ formal table copies
# Byte-identical copies of the CSVs behind each formal table, named by table
# number, for readers of results/tables/main and results/tables/supplementary.
# Supplementary Tables S2 and S3 are composite; each part is copied separately.
tab_root <- file.path(results_dir, "tables")
formal_tables <- c(
  "main/Table1_baseline_main_cohort.csv" = "manuscript/Table1_baseline_main_cohort.csv",
  "main/Table2_model_comparison.csv" = "manuscript/Table2_model_comparison.csv",
  "main/Table2_model_comparison_formatted.csv" = "manuscript/Table2_model_comparison_formatted.csv",
  "supplementary/TableS1_external_cohorts.csv" = "manuscript/TableS1_external_cohorts.csv",
  "supplementary/TableS2a_hgsoc_cohort_flow.csv" = "ov_hgsoc_sensitivity/hgsoc_cohort_flow.csv",
  "supplementary/TableS2b_hgsoc_topology.csv" = "ov_hgsoc_sensitivity/hgsoc_topology_by_setting.csv",
  "supplementary/TableS3a_noncr_by_residual_disease.csv" = "ov_therapy_end_landmark/noncr_by_residual_disease.csv",
  "supplementary/TableS3a_noncr_residual_interaction.csv" = "ov_therapy_end_landmark/noncr_residual_interaction.csv",
  "supplementary/TableS3b_topology_by_residual_disease.csv" = "ov_therapy_end_landmark/topology_by_residual_disease.csv",
  "supplementary/TableS3c_topology_delayed_entry_and_L_adjusted.csv" = "ov_therapy_end_landmark/topology_delayed_entry_and_L_adjusted.csv",
  "supplementary/TableS3d_external_leave_one_out.csv" = "phase4_external_validation/os_meta_noncr_vs_cr_leave_one_out.csv",
  "supplementary/TableS3e_external_small_sample.csv" = "phase4_external_validation/os_meta_noncr_vs_cr_small_sample.csv",
  "supplementary/TableS3e_external_firth_by_cohort.csv" = "phase4_external_validation/os_cox_noncr_vs_cr_firth.csv",
  "supplementary/TableS4_pancancer_label_audit.csv" = "manuscript/TableS4_pancancer_label_audit.csv",
  "supplementary/TableS7_response_partition_scan.csv" = "ov_response_sensitivity/table_s7_partition_scan.csv",
  "supplementary/TableS7_evalues.csv" = "ov_response_sensitivity/evalues.csv")
stopifnot(all(file.exists(file.path(tab_root, formal_tables))))
for (sub in c("main", "supplementary")) {
  dir.create(file.path(tab_root, sub), recursive = TRUE, showWarnings = FALSE)
  stale <- setdiff(list.files(file.path(tab_root, sub), pattern = "[.]csv$"),
    basename(names(formal_tables)[dirname(names(formal_tables)) == sub]))
  unlink(file.path(tab_root, sub, stale))
}
stopifnot(all(file.copy(file.path(tab_root, formal_tables), file.path(tab_root, names(formal_tables)),
  overwrite = TRUE, copy.date = FALSE)))
# Supplementary Data 1-2 are distributed from data/supplementary as identical copies.
supp_data_dir <- file.path(project_dir, "data", "supplementary")
dir.create(supp_data_dir, recursive = TRUE, showWarnings = FALSE)
supp_data <- c("SupplementaryData1_TCGA_OV_cases.csv", "SupplementaryData2_external_samples.csv")
stopifnot(all(file.copy(file.path(out_tab, supp_data), file.path(supp_data_dir, supp_data),
  overwrite = TRUE, copy.date = FALSE)))

# ------------------------------------------------------------------ versions
pk <- c("survival", "survminer", "survRM2", "mice", "timeROC", "metafor", "coxphf", "limma", "GSVA", "WGCNA", "curatedOvarianData",
  "GEOquery", "ggplot2", "patchwork", "dplyr")
ver <- tibble(package = pk, version = vapply(pk, function(p) tryCatch(as.character(packageVersion(p)), error = function(e) NA_character_), ""))
write_csv(bind_rows(tibble(package = "R", version = paste(R.version$major, R.version$minor, sep = ".")), ver),
  file.path(out_tab, "software_versions.csv"))
writeLines(capture.output(sessionInfo()), file.path(project_dir, "logs/sessionInfo_R19.txt"))

options(width = 250)
sink(file.path(project_dir, "logs/manuscript_display_items_summary.txt"))
cat("Manuscript display items:", format(Sys.time()), "\n\nTable 2:\n"); print(as.data.frame(tab2_fmt))
cat("\nTable 1:\n"); print(as.data.frame(tab1)); cat("Reverse-KM median follow-up after landmark (all):", rkm, "months\n")
cat("\nExternal cohorts:\n"); print(as.data.frame(ext_tab))
cat("\nFigure 3A:\n"); print(as.data.frame(f3a)); cat("\nFigure 3C:\n"); print(as.data.frame(f3c))
cat("\nVersions:\n"); print(as.data.frame(ver))
sink()
cat(readLines(file.path(project_dir, "logs/manuscript_display_items_summary.txt")), sep = "\n")
