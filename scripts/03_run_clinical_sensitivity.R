#!/usr/bin/env Rscript

# ==============================================================================
# File: 03_run_clinical_sensitivity.R
# Purpose: Run diagnosis-origin clinical sensitivity and missing-data analyses.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Harmonized TCGA-OV clinical cohort produced by script 02.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; response level order;
#     cohort.phase0_sensitivity_grades; survival.sensitivity_rmst_horizons_months;
#     selection.ipw_truncation_quantiles; phase0 MI count and maximum iterations.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Sensitivity tables for survival topology, missingness, and imputation.
# Reproducibility:
#   - Grade-restriction labels and diagnosis-origin estimands remain unchanged.
#   - M1/M3 imputations retain separate encodings and the original explicit seed.
# ==============================================================================

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(survival)
  library(survRM2)
  library(mice)
})

# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)
analysis_config <- config$analysis
seed <- analysis_config$random_seeds$default
configure_reproducible_runtime(seed)
phase0_sensitivity_grades <- unlist(required_analysis_value(
  analysis_config, "cohort.phase0_sensitivity_grades"
), use.names = FALSE)
if (!is.character(phase0_sensitivity_grades) || !length(phase0_sensitivity_grades) ||
    anyNA(phase0_sensitivity_grades) || any(!nzchar(phase0_sensitivity_grades)) ||
    anyDuplicated(phase0_sensitivity_grades)) {
  stop("cohort.phase0_sensitivity_grades must be a non-empty unique character vector.")
}
table_dir <- file.path(config$paths$results_dir, "tables")
processed_dir <- config$paths$processed_data_dir
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

require_input_files(file.path(processed_dir, "tcga_ov_phase0_clinical.csv"), "script-02 clinical cohort")
x <- read_csv(file.path(processed_dir, "tcga_ov_phase0_clinical.csv"), show_col_types = FALSE) %>%
  mutate(
    response4 = factor(response4, levels = analysis_config$response$four_levels),
    response_clinical = factor(response_clinical, levels = analysis_config$response$four_levels),
    response_m2 = factor(response_m2, levels = analysis_config$response$objective_response_levels),
    response_m3 = factor(response_m3, levels = analysis_config$response$cr_threshold_levels),
    stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
    residual_group = factor(residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm")),
    age_10y = age / 10,
    response_observed = factor(if_else(is.na(response4), "Missing", "Observed"), levels = c("Observed", "Missing"))
  )

# Compare M1 and its two-df M3 plateau restriction on the same endpoint-complete
# patients. This is an associative diagnosis-origin sensitivity, not equivalence.
simple_topology <- function(data, response_var, time_var, event_var, endpoint, analysis_name) {
  dat <- data %>%
    filter(!is.na(.data[[response_var]]), !is.na(.data[[time_var]]), !is.na(.data[[event_var]])) %>%
    mutate(
      response_source = factor(as.character(.data[[response_var]]), levels = analysis_config$response$four_levels),
      response_threshold = factor(if_else(response_source == "CR", "CR", "Non-CR"), levels = analysis_config$response$cr_threshold_levels),
      time = .data[[time_var]],
      event = .data[[event_var]]
    )
  m1 <- coxph(Surv(time, event) ~ response_source, data = dat)
  m3 <- coxph(Surv(time, event) ~ response_threshold, data = dat)
  ll1 <- logLik(m1)
  ll3 <- logLik(m3)
  lrt <- 2 * (as.numeric(ll1) - as.numeric(ll3))
  s3 <- summary(m3)
  tibble(
    analysis = analysis_name,
    endpoint = endpoint,
    n = nrow(dat),
    events = sum(dat$event),
    HR_nonCR_vs_CR = s3$conf.int[1, "exp(coef)"],
    HR_CI_low = s3$conf.int[1, "lower .95"],
    HR_CI_high = s3$conf.int[1, "upper .95"],
    HR_p = s3$coefficients[1, "Pr(>|z|)"],
    M1_AIC = AIC(m1),
    M3_AIC = AIC(m3),
    M1_BIC = BIC(m1),
    M3_BIC = BIC(m3),
    plateau_LRT_chisq = lrt,
    plateau_LRT_p = pchisq(lrt, df = 2, lower.tail = FALSE)
  )
}

source_and_cohort_sensitivity <- bind_rows(
  simple_topology(x, "response4", "OS_months", "OS_event", "OS", "Unified PanCan response source"),
  simple_topology(x, "response4", "PFI_months", "PFI_event", "PFI", "Unified PanCan response source"),
  simple_topology(x, "response_clinical", "OS_months", "OS_event", "OS", "Original OV clinical matrix response"),
  simple_topology(x, "response_clinical", "PFI_months", "PFI_event", "PFI", "Original OV clinical matrix response"),
  simple_topology(filter(x, grade %in% phase0_sensitivity_grades), "response4", "OS_months", "OS_event", "OS", "Grade G2-G3 restriction"),
  simple_topology(filter(x, grade %in% phase0_sensitivity_grades), "response4", "PFI_months", "PFI_event", "PFI", "Grade G2-G3 restriction"),
  simple_topology(filter(x, !response_conflict), "response4", "OS_months", "OS_event", "OS", "Exclude cross-source conflict"),
  simple_topology(filter(x, !response_conflict), "response4", "PFI_months", "PFI_event", "PFI", "Exclude cross-source conflict")
)
write_csv(source_and_cohort_sensitivity, file.path(table_dir, "sensitivity_source_and_cohort.csv"))

missing_response_survival <- bind_rows(lapply(c("OS", "PFI"), function(endpoint) {
  time_var <- paste0(endpoint, "_months")
  event_var <- paste0(endpoint, "_event")
  dat <- x %>% filter(!is.na(.data[[time_var]]), !is.na(.data[[event_var]])) %>%
    mutate(time = .data[[time_var]], event = .data[[event_var]])
  fit <- coxph(Surv(time, event) ~ response_observed, data = dat)
  s <- summary(fit)
  tibble(
    endpoint = endpoint,
    n = nrow(dat),
    events = sum(dat$event),
    missing_response_n = sum(dat$response_observed == "Missing"),
    HR_missing_vs_observed = s$conf.int[1, "exp(coef)"],
    CI_low = s$conf.int[1, "lower .95"],
    CI_high = s$conf.int[1, "upper .95"],
    p_value = s$coefficients[1, "Pr(>|z|)"]
  )
}))
write_csv(missing_response_survival, file.path(table_dir, "response_missingness_survival.csv"))

# RMST handles the clear non-proportionality seen for PFI. Arm 1 is Non-CR, arm 0 is CR.
rmst_results <- bind_rows(lapply(c("OS", "PFI"), function(endpoint) {
  time_var <- paste0(endpoint, "_months")
  event_var <- paste0(endpoint, "_event")
  dat <- x %>%
    filter(!is.na(response_m3), !is.na(.data[[time_var]]), !is.na(.data[[event_var]])) %>%
    mutate(arm = as.integer(response_m3 == "Non-CR"))
  bind_rows(lapply(analysis_config$survival$sensitivity_rmst_horizons_months, function(tau) {
    fit <- rmst2(time = dat[[time_var]], status = dat[[event_var]], arm = dat$arm, tau = tau)
    u <- as.data.frame(fit$unadjusted.result) %>% tibble::rownames_to_column("contrast")
    u %>%
      transmute(
        endpoint = endpoint,
        tau_months = tau,
        contrast,
        estimate = unname(Est.),
        CI_low = unname(`lower .95`),
        CI_high = unname(`upper .95`),
        p_value = unname(p)
      )
  }))
}))
write_csv(rmst_results, file.path(table_dir, "rmst_cr_vs_noncr.csv"))

# Explicit missing-category sensitivity preserves all response-known cases.
missing_category_models <- bind_rows(lapply(c("OS", "PFI"), function(endpoint) {
  time_var <- paste0(endpoint, "_months")
  event_var <- paste0(endpoint, "_event")
  dat <- x %>%
    filter(!is.na(response4), !is.na(.data[[time_var]]), !is.na(.data[[event_var]]), !is.na(age_10y)) %>%
    mutate(
      time = .data[[time_var]],
      event = .data[[event_var]],
      stage_missing = factor(if_else(is.na(stage_group), "Missing", as.character(stage_group))),
      residual_missing = factor(if_else(is.na(residual_group), "Missing", as.character(residual_group)))
    )
  m1 <- coxph(Surv(time, event) ~ response4 + age_10y + stage_missing + residual_missing, data = dat)
  m3 <- coxph(Surv(time, event) ~ response_m3 + age_10y + stage_missing + residual_missing, data = dat)
  s3 <- summary(m3)
  lrt <- 2 * (as.numeric(logLik(m1)) - as.numeric(logLik(m3)))
  tibble(
    endpoint = endpoint,
    n = nrow(dat),
    events = sum(dat$event),
    HR_nonCR_vs_CR = s3$conf.int["response_m3Non-CR", "exp(coef)"],
    CI_low = s3$conf.int["response_m3Non-CR", "lower .95"],
    CI_high = s3$conf.int["response_m3Non-CR", "upper .95"],
    p_value = s3$coefficients["response_m3Non-CR", "Pr(>|z|)"],
    plateau_LRT_p = pchisq(lrt, df = 2, lower.tail = FALSE),
    M1_AIC = AIC(m1),
    M3_AIC = AIC(m3)
  )
}))
write_csv(missing_category_models, file.path(table_dir, "sensitivity_missing_category_adjustment.csv"))

# IPW for response-label availability under a missing-at-random assumption.
ipw_results <- bind_rows(lapply(c("OS", "PFI"), function(endpoint) {
  time_var <- paste0(endpoint, "_months")
  event_var <- paste0(endpoint, "_event")
  selection <- x %>%
    filter(!is.na(age_10y), !is.na(stage_group), !is.na(residual_group)) %>%
    mutate(observed = as.integer(!is.na(response4)))
  ps_model <- glm(observed ~ age_10y + stage_group + residual_group, data = selection, family = binomial())
  selection$ps <- predict(ps_model, type = "response")
  dat <- selection %>%
    filter(observed == 1, !is.na(.data[[time_var]]), !is.na(.data[[event_var]])) %>%
    mutate(
      time = .data[[time_var]],
      event = .data[[event_var]],
      sw = mean(selection$observed) / ps
    )
  limits <- quantile(dat$sw, analysis_config$selection$ipw_truncation_quantiles, na.rm = TRUE)
  dat$sw_truncated <- pmin(pmax(dat$sw, limits[1]), limits[2])
  m1 <- coxph(Surv(time, event) ~ response4, data = dat, weights = sw_truncated, robust = TRUE)
  m3 <- coxph(Surv(time, event) ~ response_m3, data = dat, weights = sw_truncated, robust = TRUE)
  s3 <- summary(m3)
  lrt <- 2 * (as.numeric(logLik(m1)) - as.numeric(logLik(m3)))
  tibble(
    endpoint = endpoint,
    n = nrow(dat),
    events = sum(dat$event),
    weight_min = min(dat$sw_truncated),
    weight_median = median(dat$sw_truncated),
    weight_max = max(dat$sw_truncated),
    HR_nonCR_vs_CR = s3$conf.int["response_m3Non-CR", "exp(coef)"],
    robust_CI_low = s3$conf.int["response_m3Non-CR", "lower .95"],
    robust_CI_high = s3$conf.int["response_m3Non-CR", "upper .95"],
    robust_p = s3$coefficients["response_m3Non-CR", "Pr(>|z|)"],
    weighted_plateau_LRT_p_descriptive = pchisq(lrt, df = 2, lower.tail = FALSE)
  )
}))
write_csv(ipw_results, file.path(table_dir, "sensitivity_ipw_response_availability.csv"))

# Multiple imputation for missing adjustment covariates among response-known cases.
# M1 and M3 are imputed separately to avoid deterministic collinearity between response encodings.
run_mi <- function(response_name, model_name, formula_text) {
  mi_data <- x %>%
    filter(!is.na(.data[[response_name]]), !is.na(OS_months), !is.na(OS_event)) %>%
    select(OS_months, OS_event, all_of(response_name), age_10y, stage_group, residual_group)
  meth <- make.method(mi_data)
  meth[c("OS_months", "OS_event", response_name)] <- ""
  pred <- make.predictorMatrix(mi_data)
  diag(pred) <- 0
  imp <- mice(
    mi_data,
    m = analysis_config$resampling$phase0_multiple_imputations,
    maxit = analysis_config$resampling$multiple_imputation_max_iterations,
    method = meth,
    predictorMatrix = pred,
    printFlag = FALSE,
    seed = seed
  )
  fit <- with(imp, coxph(as.formula(formula_text)))
  pooled <- summary(pool(fit), conf.int = TRUE, exponentiate = TRUE) %>%
    as_tibble() %>%
    transmute(
      model = model_name,
      term,
      HR = estimate,
      std_error = std.error,
      statistic,
      df,
      p_value = p.value,
      CI_low = `2.5 %`,
      CI_high = `97.5 %`
    )
  logged <- if (is.null(imp$loggedEvents)) 0L else nrow(imp$loggedEvents)
  list(pooled = pooled, logged_events = logged)
}

mi_m1 <- run_mi(
  "response4",
  "M1",
  "Surv(OS_months, OS_event) ~ response4 + age_10y + stage_group + residual_group"
)
mi_m3 <- run_mi(
  "response_m3",
  "M3",
  "Surv(OS_months, OS_event) ~ response_m3 + age_10y + stage_group + residual_group"
)
mi_results <- bind_rows(mi_m1$pooled, mi_m3$pooled)
write_csv(mi_results, file.path(table_dir, "sensitivity_multiple_imputation_os.csv"))
write_csv(
  tibble(model = c("M1", "M3"), logged_events = c(mi_m1$logged_events, mi_m3$logged_events)),
  file.path(table_dir, "sensitivity_multiple_imputation_diagnostics.csv")
)

capture.output(sessionInfo(), file = file.path(project_dir, "logs", "sessionInfo_sensitivity.txt"))
# ---- Analysis workflow --------------------------------------------------------
message("Phase 0 sensitivity analyses completed successfully.")
