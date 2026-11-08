#!/usr/bin/env Rscript

# ==============================================================================
# File: 17_fit_therapy_end_landmark.R
# Purpose: Fit the primary patient-specific therapy-end landmark models in TCGA-OV.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Labelled Phase 0 TCGA-OV clinical rows and script 15's first-line treatment
#     records, joined by patient; OS/PFI remain the observed clinical endpoints.
# Runtime parameters:
#   - config/analysis.yml: random_seeds.therapy_end_landmark; landmark.plausible_end_days,
#     fixed_days and plus_days_sensitivity; resampling.bootstrap_replicates,
#     cross_validation_repeats/folds, multiple_imputations and
#     landmark_mi_max_iterations (5, distinct from Phase 0's 20 iterations).
#   - survival.days_per_month, alpha, rmst_horizons_months and time_dependent_auc_months;
#     response.equivalence_margin/relaxed_equivalence_margin; power.target_power;
#     cohort.minimum_topology_per_state; reporting.split_quantiles for C summaries.
#   - load_project_configuration(project_dir) resolves processed_data_dir/results_dir
#     from private paths or environment overrides; shared style and the submission
#     profile supply artwork settings. The 120-month KM/risk axis is display_only.
#   - Response codings, adjustment sets, 90% equivalence CIs and residual splits
#     remain explicit scientific definitions. Expected counts in stopifnot are
#     locked assertions, not cohort-size inputs or generated statistical results.
# Outputs:
#   - Primary Cox models, constraint tests, bootstrap results, CV metrics, and figures.
# Reproducibility:
#   - Bootstrap draws resample observed patients; mice imputes missing covariates
#     conditional on observed outcomes/response, leaving those variables unchanged.
#   - Response-stratified CV uses seed + repeat and the existing within-fold
#     comparable-pair C-index. Legacy pooled-LP 36-month AUC is pending review
#     and not reported; its implementation is unchanged.
# ==============================================================================

# Main clinical analysis for the manuscript: OV response topology with a
# patient-specific landmark at the end of first-line therapy (GDC dates).
#
# Cohort: Phase 0 unified-label TCGA-OV cohort (454 labelled) joined to the
# GDC first-line regimen derived in script 15. Primary landmark = end of first-line
# systemic therapy, restricted to the configured plausible end-date interval;
# patients with death/censoring on or before the landmark are excluded.
# Pre-specified analyses (mirroring Phase 0): M1/M2/M3 (+ post hoc M_PD),
# plateau and ORR constraint LRTs, AIC/BIC, 1000 bootstraps, equivalence
# (90% CI within HR 0.67-1.50), RMST, PH tests, multiple imputation,
# landmark-selection audit, alternative landmarks, and cross-validated
# discrimination of response codings (C-index, 3-year time-dependent AUC).
# Post hoc: NCR versus CR within residual-disease strata with an interaction test.

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr); library(purrr)
  library(survival); library(survminer); library(survRM2); library(mice); library(timeROC)
  library(ggplot2); library(patchwork)
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
seed <- analysis_config$random_seeds$therapy_end_landmark
configure_reproducible_runtime(seed, threads = 1L)
landmark_bounds <- analysis_config$landmark$plausible_end_days
fixed_landmarks <- analysis_config$landmark$fixed_days
landmark_plus_days <- analysis_config$landmark$plus_days_sensitivity
bootstrap_replicates <- analysis_config$resampling$bootstrap_replicates
landmark_mi_max_iterations <- analysis_config$resampling$landmark_mi_max_iterations
cv_repeats <- analysis_config$resampling$cross_validation_repeats
cv_folds <- analysis_config$resampling$cross_validation_folds
auc_horizon <- analysis_config$survival$time_dependent_auc_months
survival_alpha <- analysis_config$survival$alpha
split_quantiles <- analysis_config$reporting$split_quantiles
equivalence_margin <- analysis_config$response$equivalence_margin
relaxed_margin <- analysis_config$response$relaxed_equivalence_margin
processed_dir <- config$paths$processed_data_dir
out_tab <- file.path(config$paths$results_dir, "tables", "ov_therapy_end_landmark")
out_fig <- file.path(config$paths$results_dir, "figures", "ov_therapy_end_landmark")
dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(project_dir, "logs"), recursive = TRUE, showWarnings = FALSE)
mo <- analysis_config$survival$days_per_month

clin <- read_csv(file.path(processed_dir, "tcga_ov_phase0_clinical.csv"), show_col_types = FALSE) %>%
  filter(!is.na(response4))
gdc <- read_csv(file.path(processed_dir, "pancancer_patient_response_treatment.csv"),
                show_col_types = FALSE, guess_max = 20000) %>%
  filter(cancer == "OV") %>% select(patient, fl_start, fl_end, fl_agents, fl_platinum, therapy_end)
d0 <- clin %>% left_join(gdc, by = "patient") %>%
  mutate(response4 = factor(response4, levels = c("CR", "PR", "SD", "PD")),
    noncr = as.integer(response4 != "CR"), orr_fail = as.integer(response4 %in% c("SD", "PD")),
    pd_step = factor(case_when(response4 == "CR" ~ "CR", response4 == "PD" ~ "PD", TRUE ~ "PR_SD"),
      levels = c("CR", "PR_SD", "PD")),
    stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
    residual_group = factor(residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm")),
    date_ok = is.finite(therapy_end) & therapy_end >= landmark_bounds[1] & therapy_end <= landmark_bounds[2],
    # Provenance of the retained label: a second, concordant clinical-matrix
    # record supports most labels; a single TCGA-CDR source supports the rest.
    label_source = case_when(
      response_conflict %in% TRUE ~ "TCGA-CDR, discordant clinical-matrix label",
      !is.na(response_clinical) ~ "TCGA-CDR, concordant clinical-matrix label",
      TRUE ~ "TCGA-CDR only"))
# Locked assertion: upstream unified-label count, not an analysis input.
stopifnot(nrow(d0) == 454)

# ---------------------------------------------------------- landmark builder
# Input: joined clinical rows, an origin scheme and OS/PFI. Return: finite,
# observed survivors beyond that origin with post-origin time in months.
# The imputed scheme uses the observed plausible-date median (not a fixed 152);
# therapy_end_any deliberately bypasses plausibility bounds as a sensitivity.
landmark_data <- function(d, scheme, endpoint = "OS") {
  origin <- switch(scheme, none = rep(0, nrow(d)), fixed183 = rep(fixed_landmarks[1], nrow(d)),
    fixed270 = rep(fixed_landmarks[2], nrow(d)), fixed365 = rep(fixed_landmarks[3], nrow(d)),
    therapy_end = ifelse(d$date_ok, d$therapy_end, NA),
    therapy_end_plus30 = ifelse(d$date_ok, d$therapy_end + landmark_plus_days, NA),
    therapy_end_any = d$therapy_end,
    # Missing/implausible end dates replaced by the median plausible end date.
    therapy_end_imputed = ifelse(d$date_ok, d$therapy_end, median(d$therapy_end[d$date_ok])))
  tm <- d[[paste0(endpoint, "_days")]]; ev <- d[[paste0(endpoint, "_event")]]
  d %>% mutate(origin = origin, time_raw = tm, event = ev) %>%
    filter(is.finite(origin), is.finite(time_raw), !is.na(event), time_raw > origin) %>%
    mutate(time = (time_raw - origin) / mo)
}

plausible_end_step <- sprintf(
  "Plausible end date (%d-%d d)", landmark_bounds[[1]], landmark_bounds[[2]]
)
implausible_end_reason <- sprintf(
  "implausible end date (<%d or >%d d)", landmark_bounds[[1]], landmark_bounds[[2]]
)
flow <- tibble(step = c("Labelled cohort", "OS available", "GDC first-line regimen found",
    "Therapy end date available", plausible_end_step, "Alive and followed at landmark (OS set)"),
  # Counts after "OS available" are sequential within the OS analysis set (as in Figure 1).
  n = c(nrow(d0), sum(is.finite(d0$OS_days)), sum(is.finite(d0$OS_days) & !is.na(d0$fl_start)),
    sum(is.finite(d0$OS_days) & !is.na(d0$fl_start) & is.finite(d0$therapy_end)),
    sum(is.finite(d0$OS_days) & !is.na(d0$fl_start) & d0$date_ok), nrow(landmark_data(d0, "therapy_end"))))
flow_by <- d0 %>% mutate(in_landmark = patient %in% landmark_data(d0, "therapy_end")$patient) %>%
  count(response4, in_landmark) %>% pivot_wider(names_from = in_landmark, values_from = n, names_prefix = "landmark_")
write_csv(flow, file.path(out_tab, "landmark_cohort_flow.csv"))
write_csv(flow_by, file.path(out_tab, "landmark_cohort_by_response.csv"))
# Label provenance overall and within the therapy-end landmark cohort.
write_csv(d0 %>% mutate(in_landmark = patient %in% landmark_data(d0, "therapy_end")$patient) %>%
  count(label_source, in_landmark, name = "n") %>% arrange(label_source, in_landmark),
  file.path(out_tab, "label_source_counts.csv"))

# ---------------------------------------------------------- topology models
covars <- c("age_10y", "stage_group", "residual_group")
# Input: landmark rows and an adjustment flag. Return: common complete-case data
# and four Cox fits (M1, M2, M3, M_PD). CR is the response reference; the same
# age/stage/residual cases underpin every adjusted nested-model comparison.
fit_set <- function(d, adjust) {
  cv <- if (adjust) covars else character()
  d <- d[complete.cases(d[, c("time", "event", cv)]), ]
  rhs <- function(x) paste(c(x, cv), collapse = " + ")
  f <- list(M1 = coxph(as.formula(paste("Surv(time, event) ~", rhs("response4"))), d),
    M2 = coxph(as.formula(paste("Surv(time, event) ~", rhs("orr_fail"))), d),
    M3 = coxph(as.formula(paste("Surv(time, event) ~", rhs("noncr"))), d),
    M_PD = coxph(as.formula(paste("Surv(time, event) ~", rhs("pd_step"))), d))
  list(d = d, f = f)
}
# Input: fit_set/fit_codings data-and-fit list. Return: one-row HR, nested LRT
# and delta-AIC/BIC summary. Comparisons assume a common patient set and nested
# response codings; df are the original 2/2/1 and BIC uses observed events.
summ_set <- function(fs) {
  f <- fs$f; d <- fs$d
  ll <- sapply(f, function(x) x$loglik[2]); k <- sapply(f, function(x) length(coef(x)))
  ci <- exp(cbind(coef(f$M1), confint(f$M1)))
  m3 <- exp(c(coef(f$M3)["noncr"], confint(f$M3)["noncr", ]))
  aic <- -2 * ll + 2 * k; bic <- -2 * ll + log(sum(d$event)) * k
  tibble(n = nrow(d), events = sum(d$event), CR = sum(d$response4 == "CR"), PR = sum(d$response4 == "PR"),
    SD = sum(d$response4 == "SD"), PD = sum(d$response4 == "PD"),
    HR_PR = ci["response4PR", 1], HR_PR_low = ci["response4PR", 2], HR_PR_high = ci["response4PR", 3],
    HR_SD = ci["response4SD", 1], HR_SD_low = ci["response4SD", 2], HR_SD_high = ci["response4SD", 3],
    HR_PD = ci["response4PD", 1], HR_PD_low = ci["response4PD", 2], HR_PD_high = ci["response4PD", 3],
    HR_NonCR = m3[1], HR_NonCR_low = m3[2], HR_NonCR_high = m3[3],
    plateau_p = pchisq(2 * (ll["M1"] - ll["M3"]), 2, lower.tail = FALSE),
    ORR_p = pchisq(2 * (ll["M1"] - ll["M2"]), 2, lower.tail = FALSE),
    PD_step_p = pchisq(2 * (ll["M_PD"] - ll["M3"]), 1, lower.tail = FALSE),
    dAIC_M1 = aic["M1"] - min(aic), dAIC_M2 = aic["M2"] - min(aic), dAIC_M3 = aic["M3"] - min(aic), dAIC_M_PD = aic["M_PD"] - min(aic),
    dBIC_M1 = bic["M1"] - min(bic), dBIC_M2 = bic["M2"] - min(bic), dBIC_M3 = bic["M3"] - min(bic), dBIC_M_PD = bic["M_PD"] - min(bic),
    best_AIC = names(which.min(aic)), best_BIC = names(which.min(bic)))
}
schemes <- c("none", "fixed183", "fixed270", "fixed365", "therapy_end", "therapy_end_plus30", "therapy_end_any", "therapy_end_imputed")
topo <- list(); sets <- list()
for (ep in c("OS", "PFI")) for (sc in schemes) for (adj in c(FALSE, TRUE)) {
  ld <- landmark_data(d0, sc, ep)
  fs <- fit_set(ld, adj); sets[[paste(ep, sc, adj)]] <- fs
  topo[[length(topo) + 1]] <- summ_set(fs) %>% mutate(endpoint = ep, landmark = sc,
    adjustment = ifelse(adj, "age+stage+residual", "none"), .before = 1)
}
topo <- bind_rows(topo)
write_csv(topo, file.path(out_tab, "topology_by_landmark.csv"))

# Same-patient comparison: the landmark cohort analysed without a landmark.
lm_ids <- landmark_data(d0, "therapy_end")$patient
same <- bind_rows(lapply(c(FALSE, TRUE), function(adj) summ_set(fit_set(landmark_data(d0 %>% filter(patient %in% lm_ids), "none"), adj)) %>%
  mutate(adjustment = ifelse(adj, "age+stage+residual", "none"), .before = 1)))
write_csv(same, file.path(out_tab, "landmark_patients_without_landmark.csv"))

# ---------------------------------------------------------- bootstrap
# Input: landmark rows and requested draw count. Return: valid-draw count,
# lowest-AIC frequencies and plateau/ORR rejection fractions at survival.alpha.
# Resample whole observed patients; omit draws missing a response state. These
# unadjusted fits deliberately retain the original non-stratified algorithm.
boot_sel <- function(d, B = bootstrap_replicates) {
  r <- replicate(B, {
    b <- d[sample(nrow(d), replace = TRUE), ]
    if (length(unique(b$response4)) < 4) return(rep(NA, 3))
    ll <- c(coxph(Surv(time, event) ~ response4, b)$loglik[2], coxph(Surv(time, event) ~ orr_fail, b)$loglik[2],
      coxph(Surv(time, event) ~ noncr, b)$loglik[2], coxph(Surv(time, event) ~ pd_step, b)$loglik[2])
    aic <- -2 * ll + 2 * c(3, 1, 1, 2)
    c(which.min(aic), pchisq(2 * (ll[1] - ll[3]), 2, lower.tail = FALSE) < survival_alpha, pchisq(2 * (ll[1] - ll[2]), 2, lower.tail = FALSE) < survival_alpha)
  })
  r <- r[, !is.na(r[1, ])]
  tibble(B = ncol(r), M1 = mean(r[1, ] == 1), M2 = mean(r[1, ] == 2), M3 = mean(r[1, ] == 3), M_PD = mean(r[1, ] == 4),
    plateau_rejected = mean(r[2, ] == 1), ORR_rejected = mean(r[3, ] == 1))
}
boots <- bind_rows(lapply(c("none", "fixed183", "therapy_end", "therapy_end_imputed"), function(sc)
  boot_sel(landmark_data(d0, sc)) %>% mutate(landmark = sc, .before = 1)),
  boot_sel(landmark_data(d0 %>% filter(patient %in% lm_ids), "none")) %>% mutate(landmark = "none_same_patients", .before = 1))
write_csv(boots, file.path(out_tab, "bootstrap_model_selection.csv"))

# ---------------------------------------------------------- equivalence (TOST via 90% CI)
eq <- list()
for (adj in c(FALSE, TRUE)) {
  ld <- landmark_data(d0, "therapy_end") %>% filter(response4 != "CR") %>% droplevels()
  cv <- if (adj) covars else character()
  ld <- ld[complete.cases(ld[, c("time", "event", cv)]), ]
  for (ref in c("PR", "SD")) {
    ld$grp <- relevel(ld$response4, ref = ref)
    f <- coxph(as.formula(paste("Surv(time, event) ~", paste(c("grp", cv), collapse = " + "))), ld)
    for (cmp in setdiff(levels(ld$grp), ref)) {
      nm <- paste0("grp", cmp); if (ref == "SD" && cmp == "PR") next
      est <- coef(f)[nm]; se <- sqrt(vcov(f)[nm, nm])
      lo90 <- exp(est - qnorm(0.95) * se); hi90 <- exp(est + qnorm(0.95) * se)
      eq[[length(eq) + 1]] <- tibble(adjustment = ifelse(adj, "age+stage+residual", "none"),
        comparison = paste(cmp, "vs", ref), HR = exp(est), CI90_low = lo90, CI90_high = hi90,
        p_difference = 2 * pnorm(-abs(est / se)), equivalent_0.67_1.50 = lo90 > equivalence_margin[1] & hi90 < equivalence_margin[2],
        equivalent_0.5_2.0 = lo90 > relaxed_margin[1] & hi90 < relaxed_margin[2])
    }
  }
}
eq <- bind_rows(eq)
write_csv(eq, file.path(out_tab, "noncr_equivalence_therapy_end.csv"))

# ---------------------------------------------------------- RMST and PH
ld <- landmark_data(d0, "therapy_end")
rm <- bind_rows(lapply(analysis_config$survival$rmst_horizons_months, function(tau) {
  r <- rmst2(ld$time, ld$event, ld$noncr, tau = tau)
  u <- r$unadjusted.result
  tibble(tau_months = tau, RMST_CR = r$RMST.arm0$rmst[1], RMST_NonCR = r$RMST.arm1$rmst[1],
    difference = u[1, 1], low = u[1, 2], high = u[1, 3], p = u[1, 4])
}))
write_csv(rm, file.path(out_tab, "rmst_therapy_end.csv"))
ph <- bind_rows(lapply(c("M1", "M3"), function(m) {
  z <- cox.zph(sets[["OS therapy_end FALSE"]]$f[[m]])$table
  tibble(model = m, term = rownames(z), chisq = z[, "chisq"], p = z[, "p"])
}), lapply(c("M1", "M3"), function(m) {
  z <- cox.zph(sets[["PFI therapy_end FALSE"]]$f[[m]])$table
  tibble(model = paste0("PFI_", m), term = rownames(z), chisq = z[, "chisq"], p = z[, "p"])
}))
write_csv(ph, file.path(out_tab, "ph_tests_therapy_end.csv"))

# ---------------------------------------------------------- multiple imputation
# Impute age by predictive mean matching and stage/residual by multinomial
# regression, assuming covariate missingness is MAR given the observed predictors.
# Time, event and response codings are frozen; end-date imputation is script 18's
# separate empirical procedure and is not part of this mice covariate analysis.
ld_mi <- ld %>% select(patient, time, event, response4, noncr, orr_fail, age_10y, stage_group, residual_group)
# Retain mice's former five-iteration default explicitly; do not use Phase 0 maxit.
imp <- mice(
  ld_mi %>% select(-patient),
  m = analysis_config$resampling$multiple_imputations,
  maxit = landmark_mi_max_iterations,
  printFlag = FALSE,
  seed = seed,
  method = c(time = "", event = "", response4 = "", noncr = "", orr_fail = "", age_10y = "pmm",
    stage_group = "polyreg", residual_group = "polyreg"))
fit_m1 <- with(imp, coxph(Surv(time, event) ~ response4 + age_10y + stage_group + residual_group))
fit_m3 <- with(imp, coxph(Surv(time, event) ~ noncr + age_10y + stage_group + residual_group))
fit_m2 <- with(imp, coxph(Surv(time, event) ~ orr_fail + age_10y + stage_group + residual_group))
p1 <- summary(pool(fit_m1), conf.int = TRUE, exponentiate = TRUE)
p3 <- summary(pool(fit_m3), conf.int = TRUE, exponentiate = TRUE)
mi_tab <- bind_rows(p1 %>% mutate(model = "M1"), p3 %>% mutate(model = "M3")) %>%
  filter(str_detect(term, "response4|noncr")) %>%
  transmute(model, term, HR = estimate, low = `2.5 %`, high = `97.5 %`, p = p.value)
# Multivariate Rubin's-rules Wald test (D1) of linear constraints on M1:
# plateau: beta_PR = beta_SD = beta_PD; ORR: beta_PR = 0 and beta_SD = beta_PD.
# Input: per-imputation M1 fits and a multirow PR/SD/PD constraint matrix.
# Return: pooled F, numerator/denominator df and p using the existing D1 rule.
# Within/between-imputation covariance must be estimable; the two-row tests
# here retain their matrix shape, unlike script 18's single-row handling.
d1_test <- function(fits, C) {
  m <- length(fits); k <- nrow(C)
  q <- t(sapply(fits, function(f) as.numeric(C %*% coef(f)[c("response4PR", "response4SD", "response4PD")])))
  U <- lapply(fits, function(f) C %*% vcov(f)[c("response4PR", "response4SD", "response4PD"), c("response4PR", "response4SD", "response4PD")] %*% t(C))
  qbar <- colMeans(q); Ubar <- Reduce(`+`, U) / m; B <- cov(q)
  r <- (1 + 1 / m) * sum(diag(B %*% solve(Ubar))) / k
  D <- as.numeric(t(qbar) %*% solve(Ubar) %*% qbar) / (k * (1 + r))
  tt <- k * (m - 1)
  v <- if (tt > 4) 4 + (tt - 4) * (1 + (1 - 2 / tt) / r)^2 else tt * (1 + 1 / k) * (1 + 1 / r)^2 / 2
  c(F = D, df1 = k, df2 = v, p = pf(D, k, v, lower.tail = FALSE))
}
C_plateau <- rbind(c(1, -1, 0), c(1, 0, -1))
C_orr <- rbind(c(1, 0, 0), c(0, 1, -1))
mi_tests <- bind_rows(
  as_tibble(as.list(d1_test(fit_m1$analyses, C_plateau))) %>% mutate(test = "plateau PR=SD=PD (pooled Wald D1)"),
  as_tibble(as.list(d1_test(fit_m1$analyses, C_orr))) %>% mutate(test = "ORR constraint PR=CR, SD=PD (pooled Wald D1)")) %>%
  mutate(n = nrow(ld_mi), imputations = length(fit_m1$analyses)) %>% relocate(test)
write_csv(mi_tab, file.path(out_tab, "multiple_imputation_hr.csv"))
write_csv(mi_tests, file.path(out_tab, "multiple_imputation_tests.csv"))

# ---------------------------------------------------------- landmark selection audit
sel <- d0 %>% mutate(in_landmark = patient %in% lm_ids)
sel_tests <- tibble(
  test = c("response distribution by inclusion (chi-square)", "stage by inclusion (chi-square)", "residual by inclusion (chi-square)",
           "age by inclusion (Wilcoxon)"),
  p = c(chisq.test(table(sel$response4, sel$in_landmark))$p.value,
        chisq.test(table(sel$stage_group, sel$in_landmark))$p.value,
        chisq.test(table(sel$residual_group, sel$in_landmark))$p.value,
        wilcox.test(age ~ in_landmark, sel)$p.value))
sel_hr <- bind_rows(lapply(c(TRUE, FALSE), function(inc) {
  s <- landmark_data(sel %>% filter(in_landmark == inc), "none")
  f <- coxph(Surv(time, event) ~ noncr, s); ci <- exp(c(coef(f), confint(f)))
  tibble(subset = ifelse(inc, "in landmark cohort", "excluded"), n = nrow(s), HR_NonCR = ci[1], low = ci[2], high = ci[3])
}))
write_csv(sel_tests, file.path(out_tab, "landmark_selection_tests.csv"))
write_csv(sel_hr, file.path(out_tab, "landmark_selection_hr.csv"))
excl_reason <- d0 %>% filter(is.finite(OS_days)) %>% mutate(reason = case_when(
    is.na(fl_start) ~ "no first-line regimen record",
    !is.finite(therapy_end) ~ "no therapy end date",
    !date_ok ~ implausible_end_reason,
    OS_days <= therapy_end ~ "death/censoring before therapy end",
    TRUE ~ "included")) %>% count(reason, response4) %>%
  pivot_wider(names_from = response4, values_from = n, values_fill = 0)
write_csv(excl_reason, file.path(out_tab, "landmark_exclusion_reasons.csv"))

# ---------------------------------------------------------- CV discrimination of codings
cv_d <- ld[complete.cases(ld[, covars]), ]
forms <- list(clinical = "age_10y + stage_group + residual_group",
  clinical_ORR = "orr_fail + age_10y + stage_group + residual_group",
  clinical_CR_threshold = "noncr + age_10y + stage_group + residual_group",
  clinical_PD_step = "pd_step + age_10y + stage_group + residual_group",
  clinical_four_state = "response4 + age_10y + stage_group + residual_group",
  ORR_only = "orr_fail", CR_threshold_only = "noncr", four_state_only = "response4")
cv_rows <- list(); cv_fold_rows <- list(); cv_assignment_rows <- list()
for (r in seq_len(cv_repeats)) {
  # Keep the original response-stratified splits and pair every model on the
  # same validation patients. Only within-fold patient pairs contribute to C.
  set.seed(seed + r)
  folds <- integer(nrow(cv_d))
  for (lev in levels(cv_d$response4)) {
    ii <- which(cv_d$response4 == lev)
    folds[ii] <- sample(rep(seq_len(cv_folds), length.out = length(ii)))
  }
  stopifnot(all(folds %in% seq_len(cv_folds)), !anyDuplicated(cv_d$patient))
  cv_assignment_rows[[r]] <- tibble(repeat_id = r, patient = cv_d$patient, fold_id = folds)
  lp <- matrix(NA_real_, nrow(cv_d), length(forms), dimnames = list(NULL, names(forms)))
  repeat_counts <- list()
  for (k in seq_len(cv_folds)) {
    tr <- cv_d[folds != k, ]; te <- cv_d[folds == k, ]
    stopifnot(length(intersect(tr$patient, te$patient)) == 0L)
    for (nm in names(forms)) {
      f <- coxph(as.formula(paste("Surv(time, event) ~", forms[[nm]])), tr)
      stopifnot(all(is.finite(coef(f)[!is.na(coef(f))])))
      prediction <- as.numeric(predict(f, newdata = te, type = "lp"))
      lp[folds == k, nm] <- prediction
      repeat_counts[[length(repeat_counts) + 1]] <- as_tibble(
        cv_fold_concordance(te$time, te$event, prediction)
      ) %>% mutate(repeat_id = r, fold_id = k, model = nm, .before = 1)
    }
  }
  repeat_counts <- bind_rows(repeat_counts)
  stopifnot(!anyNA(lp), all(repeat_counts %>% group_by(fold_id) %>%
    summarise(k = n_distinct(comparable_pairs), .groups = "drop") %>% pull(k) == 1L))
  cv_fold_rows[[r]] <- repeat_counts
  for (nm in names(forms)) {
    cidx <- cv_repeat_concordance(
      repeat_counts %>% filter(model == nm), nrow(cv_d), cv_folds
    )
    # Preserve the former pooled-LP metrics only as explicitly labelled
    # diagnostics. Their AUC aggregation is not the revised C-index estimand.
    legacy_c <- concordance(Surv(cv_d$time, cv_d$event) ~ lp[, nm], reverse = TRUE)$concordance
    auc <- timeROC(T = cv_d$time, delta = cv_d$event, marker = lp[, nm], cause = 1, times = auc_horizon, iid = FALSE)$AUC[2]
    cv_rows[[length(cv_rows) + 1]] <- bind_cols(tibble(repeat_id = r, model = nm), as_tibble(cidx)) %>%
      mutate(legacy_pooled_C_index = legacy_c, AUC_36m = auc,
             auc_method = "legacy_pooled_lp", auc_status = "pending_method_review_not_reported")
  }
}
cv_tab <- bind_rows(cv_rows)
cv_sum <- cv_tab %>% group_by(model) %>% summarise(n = nrow(cv_d), median_C = median(C_index),
  q05_C = quantile(C_index, split_quantiles[1]), q95_C = quantile(C_index, split_quantiles[2]), median_AUC36 = median(AUC_36m),
  q05_AUC36 = quantile(AUC_36m, split_quantiles[1]), q95_AUC36 = quantile(AUC_36m, split_quantiles[2]),
  c_index_method = first(c_index_method), auc_method = first(auc_method), auc_status = first(auc_status),
  .groups = "drop") %>% arrange(desc(median_C))
write_csv(cv_tab, file.path(out_tab, "cv_discrimination_replicates.csv"))
write_csv(cv_sum, file.path(out_tab, "cv_discrimination_summary.csv"))
write_csv(bind_rows(cv_fold_rows), file.path(out_tab, "cv_concordance_by_fold.csv"))
write_csv(bind_rows(cv_assignment_rows), file.path(out_tab, "cv_fold_assignments.csv"))

# Paired discrimination gain from the clinical-only model. The same repeat_id
# uses the same fold assignment for every model, so this is a paired summary
# of existing predictions and does not refit any model.
cv_delta <- cv_tab %>%
  select(repeat_id, model, C_index) %>%
  pivot_wider(names_from = model, values_from = C_index) %>%
  transmute(
    repeat_id,
    clinical_ORR = clinical_ORR - clinical,
    clinical_CR_threshold = clinical_CR_threshold - clinical,
    clinical_PD_step = clinical_PD_step - clinical,
    clinical_four_state = clinical_four_state - clinical
  ) %>%
  pivot_longer(-repeat_id, names_to = "model", values_to = "delta_C")
clinical_median_C <- cv_sum$median_C[cv_sum$model == "clinical"]
cv_delta_sum <- cv_delta %>%
  group_by(model) %>%
  summarise(
    n = nrow(cv_d), repeats = n(), folds = cv_folds, reference_model = "clinical",
    median_delta_C = median(delta_C), q05_delta_C = quantile(delta_C, split_quantiles[1]),
    q95_delta_C = quantile(delta_C, split_quantiles[2]),
    clinical_median_C = clinical_median_C, .groups = "drop"
  )
write_csv(cv_delta, file.path(out_tab, "cv_discrimination_paired_delta_replicates.csv"))
write_csv(cv_delta_sum, file.path(out_tab, "cv_discrimination_paired_delta_summary.csv"))

# Paired discrimination contrast between the two best-supported response
# codings (CR threshold minus four categories). Both models are evaluated on
# the same validation patients within each repeat, so the difference is paired.
# The interval resamples the 20 repeat-level differences and therefore
# describes split-to-split variability, not patient-sampling uncertainty.
cr_vs_four <- cv_tab %>%
  select(repeat_id, model, C_index) %>%
  pivot_wider(names_from = model, values_from = C_index) %>%
  transmute(repeat_id, delta_C = clinical_CR_threshold - clinical_four_state)
set.seed(seed)
boot_delta_C <- replicate(bootstrap_replicates, median(sample(cr_vs_four$delta_C, replace = TRUE)))
cr_vs_four_sum <- cr_vs_four %>% summarise(
  n = nrow(cv_d), repeats = n(), folds = cv_folds,
  comparison = "CR threshold minus four categories",
  median_delta_C = median(delta_C), mean_delta_C = mean(delta_C),
  q05_delta_C = quantile(delta_C, split_quantiles[1]),
  q95_delta_C = quantile(delta_C, split_quantiles[2]),
  boot_median_low = quantile(boot_delta_C, 0.025),
  boot_median_high = quantile(boot_delta_C, 0.975),
  repeats_positive = sum(delta_C > 0), repeats_negative = sum(delta_C < 0),
  interval_type = "bootstrap over cross-validation repeat-level differences")
write_csv(cr_vs_four, file.path(out_tab, "cv_discrimination_paired_delta_CR_vs_four_replicates.csv"))
write_csv(cr_vs_four_sum, file.path(out_tab, "cv_discrimination_paired_delta_CR_vs_four.csv"))

# ---------------------------------------------------------- residual-disease effect modification (post hoc)
# Post hoc: is the CR threshold confined to one surgical-outcome stratum?
# NCR versus CR is estimated within residual-disease strata at the therapy-end
# landmark, and effect modification is tested by a 1-df likelihood-ratio test
# (noncr x stratum). Deterministic; no random numbers are drawn.
residual_splits <- list(
  optimal_10mm = list(first = c("R0", "1-10 mm"), labels = c("Residual <=10 mm", "Residual >10 mm")),
  R0 = list(first = "R0", labels = c("No macroscopic residual", "Any macroscopic residual")))
rd_rows <- list(); rd_int <- list()
for (sp in names(residual_splits)) for (adj in c(FALSE, TRUE)) {
  s <- residual_splits[[sp]]
  cv <- if (adj) c("age_10y", "stage_group") else character()
  d <- ld %>% filter(!is.na(residual_group)) %>%
    mutate(stratum = factor(ifelse(residual_group %in% s$first, s$labels[1], s$labels[2]), levels = s$labels))
  d <- d[complete.cases(d[, c("time", "event", cv)]), ]
  rhs <- function(x) paste(c(x, cv), collapse = " + ")
  for (lev in s$labels) {
    ds <- droplevels(d[d$stratum == lev, ])
    f <- coxph(as.formula(paste("Surv(time, event) ~", rhs("noncr"))), ds)
    ci <- exp(c(coef(f)[["noncr"]], confint(f)["noncr", ]))
    rd_rows[[length(rd_rows) + 1]] <- tibble(split = sp, adjustment = ifelse(adj, "age+stage", "none"),
      stratum = lev, n = nrow(ds), events = sum(ds$event), CR = sum(ds$noncr == 0), NCR = sum(ds$noncr == 1),
      HR_NonCR = ci[[1]], HR_NonCR_low = ci[[2]], HR_NonCR_high = ci[[3]])
  }
  f0 <- coxph(as.formula(paste("Surv(time, event) ~", rhs(c("noncr", "stratum")))), d)
  f1 <- coxph(as.formula(paste("Surv(time, event) ~", rhs("noncr * stratum"))), d)
  it <- grep("^noncr:stratum", names(coef(f1)), value = TRUE)
  stopifnot(length(it) == 1L)
  main <- exp(c(coef(f0)[["noncr"]], confint(f0)["noncr", ]))
  ratio <- exp(c(coef(f1)[[it]], confint(f1)[it, ]))
  rd_int[[length(rd_int) + 1]] <- tibble(split = sp, adjustment = ifelse(adj, "age+stage", "none"),
    n = nrow(d), events = sum(d$event),
    HR_NonCR_stratum_adjusted = main[[1]], HR_NonCR_stratum_adjusted_low = main[[2]],
    HR_NonCR_stratum_adjusted_high = main[[3]],
    HR_ratio_interaction = ratio[[1]], HR_ratio_low = ratio[[2]], HR_ratio_high = ratio[[3]],
    interaction_LRT_p = pchisq(2 * (f1$loglik[2] - f0$loglik[2]), 1, lower.tail = FALSE))
}
rd_tab <- bind_rows(rd_rows); rd_int <- bind_rows(rd_int)
write_csv(rd_tab, file.path(out_tab, "noncr_by_residual_disease.csv"))
write_csv(rd_int, file.path(out_tab, "noncr_residual_interaction.csv"))

# ---------------------------------------------------------- post hoc topology checks (pre-submission review, 2026-10-19)
# All quantities below are deterministic re-analyses of the observed landmark
# cohort; no random numbers are drawn, so earlier outputs are unchanged.
# Input: observed rows, covariate names and an explicit survival LHS. Return:
# data-and-four-fit list compatible with summ_set. The caller must ensure finite
# time/start/stop columns and valid delayed-entry intervals; only event/covariate
# completeness is filtered here, deliberately unlike the primary fit_set gate.
fit_codings <- function(d, cv = character(), lhs = "Surv(time, event)") {
  d <- d[complete.cases(d[, c("event", cv)]), ] %>% mutate(response4 = droplevels(response4))
  rhs <- function(x) paste(c(x, cv), collapse = " + ")
  f <- list(M1 = coxph(as.formula(paste(lhs, "~", rhs("response4"))), d),
    M2 = coxph(as.formula(paste(lhs, "~", rhs("orr_fail"))), d),
    M3 = coxph(as.formula(paste(lhs, "~", rhs("noncr"))), d),
    M_PD = coxph(as.formula(paste(lhs, "~", rhs("pd_step"))), d))
  list(d = d, f = f)
}

# (1) Four-category topology within residual-disease strata. Strata below the
# configured minimum in any response category are reported without tests.
min_per_state <- analysis_config$cohort$minimum_topology_per_state
rt_rows <- list()
for (sp in names(residual_splits)) for (adj in c(FALSE, TRUE)) {
  s <- residual_splits[[sp]]
  cv <- if (adj) c("age_10y", "stage_group") else character()
  d <- ld %>% filter(!is.na(residual_group)) %>%
    mutate(stratum = factor(ifelse(residual_group %in% s$first, s$labels[1], s$labels[2]), levels = s$labels))
  for (lev in s$labels) {
    ds <- d[d$stratum == lev, ]
    ds <- ds[complete.cases(ds[, c("time", "event", cv)]), ]
    counts <- table(factor(ds$response4, levels = c("CR", "PR", "SD", "PD")))
    base <- tibble(split = sp, adjustment = ifelse(adj, "age+stage", "none"), stratum = lev,
      n = nrow(ds), events = sum(ds$event), CR = counts[["CR"]], PR = counts[["PR"]], SD = counts[["SD"]], PD = counts[["PD"]])
    if (min(counts) < min_per_state) { rt_rows[[length(rt_rows) + 1]] <- base; next }
    sm <- summ_set(fit_codings(ds, cv))
    rt_rows[[length(rt_rows) + 1]] <- bind_cols(base, sm %>% select(starts_with("HR_"), plateau_p, ORR_p, PD_step_p,
      starts_with("dAIC_"), best_AIC, best_BIC))
  }
}
write_csv(bind_rows(rt_rows), file.path(out_tab, "topology_by_residual_disease.csv"))

# (2) Akaike weights of the four codings at the primary landmark.
akaike <- topo %>% filter(landmark == "therapy_end") %>%
  select(endpoint, adjustment, n, events, dAIC_M1, dAIC_M2, dAIC_M3, dAIC_M_PD) %>%
  mutate(across(starts_with("dAIC_"), ~ exp(-.x / 2), .names = "{sub('dAIC_', 'raw_', .col)}")) %>%
  mutate(total = raw_M1 + raw_M2 + raw_M3 + raw_M_PD,
    weight_M1 = raw_M1 / total, weight_M2 = raw_M2 / total, weight_M3 = raw_M3 / total, weight_M_PD = raw_M_PD / total) %>%
  select(endpoint, adjustment, n, events, starts_with("weight_"))
write_csv(akaike, file.path(out_tab, "akaike_weights_therapy_end.csv"))

# (3) Minimal detectable HR (Schoenfeld) for pairwise contrasts at the primary landmark.
z_needed <- qnorm(1 - analysis_config$survival$alpha / 2) + qnorm(analysis_config$power$target_power)
mdhr <- bind_rows(lapply(list(c("SD", "PR"), c("PD", "PR"), c("PD", "SD"), c("PD", "PR+SD"), c("NCR", "CR")), function(pr) {
  # Input: contrast group key. Return: observed response states in that group;
  # grouped contrasts share the same landmark rows, not a refitted pooled model.
  grp <- function(x) switch(x, "PR+SD" = c("PR", "SD"), NCR = c("PR", "SD", "PD"), x)
  a <- ld$response4 %in% grp(pr[1]); b <- ld$response4 %in% grp(pr[2])
  events <- sum(ld$event[a | b]); p <- sum(a) / (sum(a) + sum(b))
  tibble(comparison = paste(pr[1], "vs", pr[2]), n_first = sum(a), n_second = sum(b), events = events,
    minimal_detectable_HR = exp(z_needed / sqrt(events * p * (1 - p))),
    alpha = analysis_config$survival$alpha, power = analysis_config$power$target_power)
}))
write_csv(mdhr, file.path(out_tab, "minimal_detectable_hr_therapy_end.csv"))

# (4) Timing of the landmark by response, and delayed-entry / L-adjusted models.
ld <- ld %>% mutate(L_months = origin / mo, T_months = time_raw / mo)
timing <- ld %>% group_by(response4) %>%
  summarise(n = n(), median_L_months = median(L_months), q1_L_months = quantile(L_months, 0.25),
    q3_L_months = quantile(L_months, 0.75), .groups = "drop") %>%
  mutate(response4 = as.character(response4)) %>%
  bind_rows(tibble(response4 = "Kruskal-Wallis P", n = nrow(ld),
    median_L_months = kruskal.test(L_months ~ response4, ld)$p.value))
write_csv(timing, file.path(out_tab, "landmark_timing_by_response.csv"))
alt_rows <- list(
  list("Delayed entry at L, diagnosis time scale", character(), "Surv(L_months, T_months, event)"),
  list("Delayed entry at L, diagnosis time scale", covars, "Surv(L_months, T_months, event)"),
  list("Landmark time scale, adjusted for L", "L_months", "Surv(time, event)"),
  list("Landmark time scale, adjusted for L", c(covars, "L_months"), "Surv(time, event)"))
alt_topo <- bind_rows(lapply(alt_rows, function(r) summ_set(fit_codings(ld, r[[2]], r[[3]])) %>%
  mutate(model = r[[1]], adjustment = ifelse(all(covars %in% r[[2]]), "age+stage+residual", "none"), .before = 1)))
write_csv(alt_topo, file.path(out_tab, "topology_delayed_entry_and_L_adjusted.csv"))

# (5) Reverse Kaplan-Meier median follow-up and numbers at risk.
# Input: observed times and death indicators. Return: reverse-KM median on the
# supplied time scale; censored follow-up becomes the event (1 - event).
# An unreached median remains NA rather than a fabricated follow-up estimate.
rkm_median <- function(time, event) unname(summary(survfit(Surv(time, 1 - event) ~ 1))$table["median"])
followup <- tibble(
  measure = c("Reverse-KM median follow-up from landmark, months", "Reverse-KM median follow-up from diagnosis, months"),
  n = nrow(ld), value = c(rkm_median(ld$time, ld$event), rkm_median(ld$T_months, ld$event)))
write_csv(followup, file.path(out_tab, "followup_reverse_km.csv"))
# Display_only time grid; the extra 36/60-month counts audit RMST horizons.
# Count full observed follow-up at time >= t; do not truncate survival at 120.
risk_times <- seq(0, 120, by = 24)
at_risk <- bind_rows(lapply(c("CR", "PR", "SD", "PD", "NCR"), function(g) {
  sel <- if (g == "NCR") ld$response4 != "CR" else ld$response4 == g
  tibble(group = g, months = c(risk_times, 36, 60), at_risk = vapply(c(risk_times, 36, 60), function(t) sum(ld$time[sel] >= t), integer(1)))
})) %>% distinct() %>% arrange(group, months)
write_csv(at_risk, file.path(out_tab, "number_at_risk_therapy_end.csv"))

# (6) Decomposition of the 2-df ORR constraint into its two 1-df components.
orr_parts <- bind_rows(lapply(c(FALSE, TRUE), function(adj) {
  cv <- if (adj) covars else character()
  d <- ld[complete.cases(ld[, c("time", "event", cv)]), ] %>%
    mutate(pr_as_cr = factor(ifelse(response4 %in% c("CR", "PR"), "CR+PR", as.character(response4)), levels = c("CR+PR", "SD", "PD")),
      sd_as_pd = factor(ifelse(response4 %in% c("SD", "PD"), "SD+PD", as.character(response4)), levels = c("CR", "PR", "SD+PD")))
  rhs <- function(x) paste(c(x, cv), collapse = " + ")
  # Input: response coding name. Return: maximized Cox partial log-likelihood
  # on the same complete-case rows/covariates for each one-df ORR constraint.
  ll <- function(x) coxph(as.formula(paste("Surv(time, event) ~", rhs(x))), d)$loglik[2]
  l1 <- ll("response4")
  tibble(adjustment = ifelse(adj, "age+stage+residual", "none"), n = nrow(d),
    constraint = c("PR = CR (1 df)", "SD = PD (1 df)"),
    LRT_p = c(pchisq(2 * (l1 - ll("pr_as_cr")), 1, lower.tail = FALSE), pchisq(2 * (l1 - ll("sd_as_pd")), 1, lower.tail = FALSE)))
}))
write_csv(orr_parts, file.path(out_tab, "orr_constraint_components.csv"))

# (7) Sensitivity excluding patients whose TCGA-CDR and clinical-matrix labels disagree.
no_conflict <- bind_rows(lapply(c(FALSE, TRUE), function(adj)
  summ_set(fit_set(ld %>% filter(!response_conflict %in% TRUE), adj)) %>%
    mutate(adjustment = ifelse(adj, "age+stage+residual", "none"), excluded = sum(ld$response_conflict %in% TRUE), .before = 1)))
write_csv(no_conflict, file.path(out_tab, "topology_excluding_label_conflict.csv"))

# (7b) Sensitivity restricted to labels corroborated by a second record.
# Single-source (TCGA-CDR only) labels are removed; all four codings are
# refitted on the shared complete-case set, so HRs and information criteria
# remain comparable with the primary analysis.
cdr_only_excluded <- sum(ld$label_source == "TCGA-CDR only")
no_cdr_only <- bind_rows(lapply(c(FALSE, TRUE), function(adj)
  summ_set(fit_set(ld %>% filter(label_source != "TCGA-CDR only"), adj)) %>%
    mutate(adjustment = ifelse(adj, "age+stage+residual", "none"),
           excluded = cdr_only_excluded, .before = 1)))
write_csv(no_cdr_only, file.path(out_tab, "topology_excluding_cdr_only.csv"))

# (7c) Sensitivity restricted to labels corroborated by a second, concordant
# record. Unlike (7b), this also removes the one patient whose clinical-matrix
# label disagreed with TCGA-CDR. All four codings are refitted on the shared
# complete-case set, so HRs and information criteria remain comparable with (7b).
strict_concordant <- bind_rows(lapply(c(FALSE, TRUE), function(adj)
  summ_set(fit_set(ld %>% filter(label_source == "TCGA-CDR, concordant clinical-matrix label"), adj)) %>%
    mutate(adjustment = ifelse(adj, "age+stage+residual", "none"),
           excluded = sum(ld$label_source != "TCGA-CDR, concordant clinical-matrix label"), .before = 1)))
write_csv(strict_concordant, file.path(out_tab, "topology_strictly_concordant.csv"))

# ---------------------------------------------------------- Figure 2
response_levels <- c("CR", "PR", "SD", "PD")
response_colours <- figure_style$response[response_levels]
base_theme <- formal_figure_theme(figure_spec) +
  theme(
    panel.grid.major = element_line(linewidth = 0.3, colour = "grey88"),
    plot.tag.position = c(0.01, 0.99),
    plot.margin = margin(3, 3, 3, 3, unit = "mm")
  )
open_axes_theme <- theme(
  panel.border = element_blank(),
  axis.line = element_line(colour = "black", linewidth = 0.4)
)
km_theme <- base_theme +
  open_axes_theme +
  theme(
    aspect.ratio = 1, legend.position = "inside",
    legend.position.inside = c(0.98, 0.98), legend.justification = c(1, 1),
    legend.direction = "vertical", legend.background = element_blank(),
    legend.key = element_blank(), legend.title = element_blank(),
    legend.key.width = unit(5, "mm"), legend.key.height = unit(3.4, "mm"),
    legend.spacing.y = unit(0, "mm"), legend.margin = margin(0, 0, 0, 0),
    plot.margin = margin(2, 3, 2, 3, unit = "mm")
  )

km_data <- ld %>%
  mutate(response2 = factor(if_else(response4 == "CR", "CR", "NCR"), levels = c("CR", "NCR")))
# Input: survival grouping formula and full landmark KM rows. Return: log-rank
# chi-square, observed-group df and p. This unadjusted full-cohort association
# test is separate from discrimination assessed on complete-case CV patients.
logrank_summary <- function(formula, data) {
  fit <- survdiff(formula, data = data)
  tibble(chisq = unname(fit$chisq), df = length(fit$n) - 1L,
         p = pchisq(fit$chisq, length(fit$n) - 1L, lower.tail = FALSE))
}
km_stats <- bind_rows(
  logrank_summary(Surv(time, event) ~ response4, km_data) %>%
    mutate(panel = "Four-state", n_km = nrow(km_data), cv_model = "four_state_only"),
  logrank_summary(Surv(time, event) ~ response2, km_data) %>%
    mutate(panel = "CR vs NCR", n_km = nrow(km_data), cv_model = "CR_threshold_only")
) %>%
  left_join(
    cv_sum %>%
      filter(model %in% c("four_state_only", "CR_threshold_only")) %>%
      select(cv_model = model, n_cv = n, median_cv_C = median_C, q05_cv_C = q05_C, q95_cv_C = q95_C),
    by = "cv_model"
  ) %>%
  mutate(
    CR_at_risk_120 = sum(km_data$response4 == "CR" & km_data$time >= 120),
    NCR_at_risk_72 = sum(km_data$response4 != "CR" & km_data$time >= 72),
    NCR_at_risk_120 = sum(km_data$response4 != "CR" & km_data$time >= 120),
    NCR_max_followup = max(km_data$time[km_data$response4 != "CR"])
  )
# Locked scientific/display assertions: validate the published annotation and
# cohort linkage; 0.001 is not an input to the log-rank test or CV algorithm.
stopifnot(nrow(km_stats) == 2L, all(km_stats$p < 0.001), all(is.finite(km_stats$median_cv_C)),
          all(km_stats$n_km == nrow(km_data)), all(km_stats$n_cv == nrow(cv_d)))
write_csv(km_stats, file.path(out_tab, "figure2_km_statistics.csv"))
# Input: a unique KM panel name. Return: locked-format annotation from km_stats,
# with observed CV median/n. The preceding locked assertion verifies P<0.001;
# this text is not a substituted p-value or a new discrimination estimate.
km_annotation <- function(panel_name) {
  x <- km_stats %>% filter(panel == panel_name)
  sprintf("Log-rank P<0.001\nCV C-index = %.3f\n(CV n=%d)", x$median_cv_C, x$n_cv)
}

four_labels <- paste0(response_levels, " (n=", as.integer(table(km_data$response4)), ")")
sf4 <- survfit(Surv(time, event) ~ response4, data = km_data)
km4 <- ggsurvplot(
  sf4, data = km_data, palette = unname(response_colours), legend.labs = four_labels,
  risk.table = FALSE, xlim = c(0, 120), break.time.by = 24,
  xlab = "Months since end of first-line therapy", ylab = "Overall survival probability",
  ggtheme = km_theme, censor.shape = 124, censor.size = 1.8, legend.title = ""
)
pA <- km4$plot +
  annotate("text", x = 118, y = 0.70, label = km_annotation("Four-state"),
           hjust = 1, vjust = 1, size = figure_text, lineheight = 0.95) +
  labs(tag = "A") + km_theme

binary_levels <- c("CR", "NCR")
binary_colours <- figure_style$response[binary_levels]
binary_labels <- paste0(binary_levels, " (n=", as.integer(table(km_data$response2)), ")")
sf2 <- survfit(Surv(time, event) ~ response2, data = km_data)
km2 <- ggsurvplot(
  sf2, data = km_data, palette = unname(binary_colours), legend.labs = binary_labels,
  risk.table = FALSE, xlim = c(0, 120), break.time.by = 24,
  xlab = "Months since end of first-line therapy", ylab = "Overall survival probability",
  ggtheme = km_theme, censor.shape = 124, censor.size = 1.8, legend.title = ""
)
pB <- km2$plot +
  annotate("text", x = 118, y = 0.84, label = km_annotation("CR vs NCR"),
           hjust = 1, vjust = 1, size = figure_text, lineheight = 0.95) +
  labs(tag = "B") + km_theme

fd <- topo %>%
  filter(endpoint == "OS", adjustment == "age+stage+residual", landmark %in% c("none", "fixed183", "therapy_end")) %>%
  select(landmark, n, starts_with("HR_PR"), starts_with("HR_SD"), starts_with("HR_PD")) %>%
  rename_with(~ paste0(.x, "_est"), c(HR_PR, HR_SD, HR_PD)) %>%
  pivot_longer(-c(landmark, n), names_to = c("state", ".value"), names_pattern = "HR_(PR|SD|PD)_(est|low|high)") %>%
  mutate(
    state = factor(state, levels = c("PR", "SD", "PD")),
    setting = recode(
      landmark,
      none = "Diagnosis: complete cases\n(n=408)",
      fixed183 = "6-month landmark (n=382)",
      therapy_end = "Therapy-end landmark (n=343)"
    ),
    setting = factor(
      setting,
      levels = c(
        "Diagnosis: complete cases\n(n=408)", "6-month landmark (n=382)",
        "Therapy-end landmark (n=343)"
      )
    )
  )
# Locked assertion: published complete-case counts must reproduce, not become
# filtering targets. The fixed legend counts are checked against observed fd$n.
stopifnot(setNames(unique(fd$n), unique(fd$landmark))[c("none", "fixed183", "therapy_end")] == c(408, 382, 343))
analysis_colours <- setNames(
  unname(figure_style$analysis[c("Diagnosis", "6-month landmark", "Therapy-end landmark")]),
  levels(fd$setting)
)
analysis_shapes <- setNames(
  unname(figure_style$analysis_shape[c("Diagnosis", "6-month landmark", "Therapy-end landmark")]),
  levels(fd$setting)
)
dodge_setting <- position_dodge(0.55)
pC <- ggplot(fd, aes(state, est, ymin = low, ymax = high, colour = setting, shape = setting)) +
  geom_hline(yintercept = 1, linetype = "dashed", linewidth = 0.55, colour = "grey40") +
  geom_errorbar(position = dodge_setting, width = 0.24, linewidth = 0.65) +
  geom_point(position = dodge_setting, size = 2.2) +
  scale_y_log10(limits = c(1, 10), breaks = c(1, 2, 5, 10)) +
  scale_colour_manual(values = analysis_colours) +
  scale_shape_manual(values = analysis_shapes) +
  labs(
    x = "Response (vs CR)", y = "Adjusted OS HR (95% CI)",
    colour = "Analysis setting", shape = "Analysis setting", tag = "C"
  ) +
  base_theme +
  open_axes_theme +
  theme(
    legend.position = "bottom", legend.direction = "vertical",
    legend.title.position = "top", legend.location = "plot",
    legend.justification.bottom = "left",
    legend.key.height = unit(3.5, "mm"), legend.box.spacing = unit(1, "mm")
  )

# Display labels are separate from the shared model-colour keys.
model_display <- c(
  `Four-state` = "Four-category", ORR = "Objective-response",
  `CR vs NCR` = "CR versus NCR", `CR | PR+SD | PD` = "Three-category\n(post hoc)"
)
bootstrap_plot <- boots %>%
  filter(landmark %in% c("none", "none_same_patients", "therapy_end"))
stopifnot(nrow(bootstrap_plot) == 3L, all(bootstrap_plot$B == bootstrap_replicates),
          all(bootstrap_plot$M2 == 0))
bootstrap_n <- c(
  none = topo$n[topo$endpoint == "OS" & topo$landmark == "none" & topo$adjustment == "none"],
  none_same_patients = same$n[same$adjustment == "none"], therapy_end = nrow(ld)
)
bootstrap_labels <- setNames(
  sprintf("%s\n(n=%d)", c("Diagnosis\nAll labelled", "Diagnosis\nSame cohort", "Therapy end"),
          bootstrap_n[c("none", "none_same_patients", "therapy_end")]),
  c("none", "none_same_patients", "therapy_end")
)
bd <- bootstrap_plot %>%
  select(landmark, M1, M2, M3, M_PD) %>%
  pivot_longer(-landmark, names_to = "model", values_to = "freq") %>%
  mutate(
    analysis = factor(
      unname(bootstrap_labels[landmark]),
      levels = unname(bootstrap_labels)
    ),
    model = factor(
      recode(model, M1 = "Four-state", M2 = "ORR", M3 = "CR vs NCR", M_PD = "CR | PR+SD | PD"),
      levels = c("Four-state", "ORR", "CR vs NCR", "CR | PR+SD | PD")
    ),
    # Display_only: suppress labels below 5%; keep all bootstrap frequencies.
    pct_label = if_else(freq >= 0.05, sprintf("%.0f%%", 100 * freq), ""),
    text_colour = if_else(model %in% c("CR vs NCR", "CR | PR+SD | PD"), "white", "black")
  )
stopifnot(all(bd$freq[bd$model == "ORR"] == 0))
pD <- ggplot(bd, aes(analysis, freq, fill = model)) +
  geom_col(position = position_stack(reverse = TRUE), colour = "white", linewidth = 0.35) +
  geom_text(
    aes(label = pct_label, colour = text_colour),
    position = position_stack(vjust = 0.5, reverse = TRUE), size = figure_text, show.legend = FALSE
  ) +
  coord_flip() +
  scale_fill_manual(values = figure_style$model, breaks = names(figure_style$model),
                    labels = unname(model_display[names(figure_style$model)])) +
  scale_colour_identity() +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1), limits = c(0, 1), expand = expansion(mult = c(0, 0))) +
  labs(
    x = NULL, y = "Lowest-AIC selection frequency",
    subtitle = sprintf("Unadjusted response-only Cox models\n%d bootstrap samples; ORR selected: %.0f%%",
                       unique(bootstrap_plot$B), 100 * max(bootstrap_plot$M2)),
    fill = "Response coding", tag = "D"
  ) +
  base_theme +
  theme(
    legend.position = "right", legend.direction = "vertical",
    legend.key.width = unit(3.5, "mm"), legend.key.height = unit(3.5, "mm")
  ) +
  guides(fill = guide_legend(ncol = 1, byrow = TRUE))

delta_plot <- cv_delta_sum %>%
  mutate(
    model = factor(
      recode(
        model,
        clinical_ORR = "ORR", clinical_CR_threshold = "CR vs NCR",
        clinical_PD_step = "CR | PR+SD | PD", clinical_four_state = "Four-state"
      ),
      levels = rev(c("ORR", "CR vs NCR", "CR | PR+SD | PD", "Four-state"))
    ),
    model_colour = recode(
      as.character(model),
      ORR = figure_style$model[["ORR"]],
      `CR vs NCR` = figure_style$model[["CR vs NCR"]],
      `CR | PR+SD | PD` = figure_style$model[["CR | PR+SD | PD"]],
      `Four-state` = figure_style$model[["Four-state"]]
    ),
    value_label = sprintf("%.3f", median_delta_C)
  )
pE <- ggplot(delta_plot, aes(median_delta_C, model, xmin = q05_delta_C, xmax = q95_delta_C, colour = model_colour)) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.55, colour = "grey40") +
  geom_errorbar(width = 0.18, orientation = "y", linewidth = 0.65) +
  geom_point(size = 2.5) +
  geom_text(aes(label = value_label), colour = "black", position = position_nudge(y = 0.34), size = figure_text) +
  scale_colour_identity() +
  scale_y_discrete(expand = expansion(add = c(0.5, 0.8)), labels = function(x) {
    labels <- unname(model_display[x])
    labels[x == "ORR"] <- "Objective-\nresponse"
    labels
  }) +
  scale_x_continuous(limits = c(0, 0.09), breaks = c(0, 0.03, 0.06, 0.09), expand = expansion(mult = c(0, 0))) +
  labs(
    x = expression(paste("Paired ", Delta, "C-index vs clinical model")), y = NULL,
    subtitle = sprintf("Clinical-only median C-index = %.3f; n=%d\n%d×%d-fold CV (empirical 5th–95th percentiles)",
                       clinical_median_C, unique(cv_delta_sum$n), unique(cv_delta_sum$repeats), unique(cv_delta_sum$folds)),
    tag = "E"
  ) +
  base_theme

# Input: ordered response groups and named colours. Return: risk-count ggplot
# on the same display_only 0-120-month axis as its KM panel. Counts come from
# at_risk using full observed follow-up (time >= t), without administrative
# censoring or a new survival fit; group order is reversed for top-down display.
risk_table <- function(groups, colours) {
  rt <- at_risk %>% filter(group %in% groups, months %in% risk_times) %>%
    mutate(group = factor(group, levels = rev(groups)))
  ggplot(rt, aes(months, group, label = at_risk, colour = group)) +
    geom_text(size = figure_text, family = figure_spec$font_family, show.legend = FALSE) +
    scale_colour_manual(values = colours) +
    scale_x_continuous(breaks = risk_times) +
    coord_cartesian(xlim = c(0, 120)) +
    labs(x = NULL, y = NULL, subtitle = "Number at risk") +
    base_theme +
    theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank(), panel.border = element_blank(), axis.ticks = element_blank(),
      axis.text.x = element_blank(),
      plot.margin = margin(0, 3, 1, 3, unit = "mm"))
}
top_row <- (pA / risk_table(response_levels, response_colours) + plot_layout(heights = c(1, 0.24))) |
  (pB / risk_table(binary_levels, binary_colours) + plot_layout(heights = c(1, 0.24)))
bottom_right <- pD / pE + plot_layout(heights = c(0.50, 0.50))
bottom_row <- pC | bottom_right
bottom_row <- bottom_row + plot_layout(widths = c(0.40, 0.60))
fig2 <- top_row / bottom_row + plot_layout(heights = c(0.54, 0.46))
save_formal_figure(fig2, file.path(out_fig, "Figure2_therapy_end_topology"), height_mm = 215, spec = figure_spec)

# ---------------------------------------------------------- summary
options(width = 250)
sink(file.path(project_dir, "logs/ov_therapy_end_landmark_summary.txt"))
cat("OV therapy-end landmark analysis:", format(Sys.time()), "\n\n")
print(as.data.frame(flow)); print(as.data.frame(flow_by))
cat("\nTopology (OS):\n")
print(as.data.frame(topo %>% filter(endpoint == "OS") %>% select(landmark, adjustment, n, events, HR_PR, HR_SD, HR_PD, HR_NonCR,
  plateau_p, ORR_p, PD_step_p, dAIC_M1, dAIC_M3, dAIC_M_PD, dBIC_M1, dBIC_M3, best_AIC, best_BIC) %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))))
cat("\nTopology (PFI):\n")
print(as.data.frame(topo %>% filter(endpoint == "PFI") %>% select(landmark, adjustment, n, events, PD, HR_PR, HR_SD, HR_PD,
  plateau_p, ORR_p, best_AIC, best_BIC) %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))))
cat("\nSame patients without landmark:\n"); print(as.data.frame(same %>% select(adjustment, n, HR_PR, HR_SD, HR_PD, plateau_p, best_AIC, best_BIC)))
cat("\nBootstrap:\n"); print(as.data.frame(boots))
cat("\nEquivalence:\n"); print(as.data.frame(eq))
cat("\nRMST:\n"); print(as.data.frame(rm))
cat("\nPH:\n"); print(as.data.frame(ph))
cat("\nMI:\n"); print(as.data.frame(mi_tab)); print(as.data.frame(mi_tests))
cat("\nSelection:\n"); print(as.data.frame(sel_tests)); print(as.data.frame(sel_hr)); print(as.data.frame(excl_reason))
cat("\nCV discrimination:\n"); print(as.data.frame(cv_sum))
cat("\nResidual-disease strata (post hoc):\n"); print(as.data.frame(rd_tab)); print(as.data.frame(rd_int))
sink()
cat(readLines(file.path(project_dir, "logs/ov_therapy_end_landmark_summary.txt")), sep = "\n")
