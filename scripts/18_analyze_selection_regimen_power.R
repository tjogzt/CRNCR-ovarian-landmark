#!/usr/bin/env Rscript

# ==============================================================================
# File: 18_analyze_selection_regimen_power.R
# Purpose: Quantify selection bias, regimen sensitivity, and power for a progressive-disease step.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Labelled Phase 0 TCGA-OV clinical rows and script 15's first-line treatment
#     records; the external PD-step result table is optional and printed only.
# Runtime parameters:
#   - config/analysis.yml: random_seeds.selection_power; landmark.plausible_end_days
#     and tipping_days; cohort.standard_duration_days, maximum_start_day,
#     minimum_tss_samples, advanced_stages, high_grade_levels, platinum_agents
#     and taxane_agents; selection.ipw_truncation_quantiles.
#   - resampling.restricted_bootstrap_replicates, power_simulation_replicates and
#     date_imputation_replicates; survival.days_per_month, alpha and wald_z_95
#     (the original rounded 1.96, not qnorm); power.target_power,
#     future_hazard_ratios, future_pd_fractions, alternative_noncr_share,
#     pd_step_hazard_ratios and censoring_multiplier (originally 1.2).
#   - load_project_configuration(project_dir) resolves processed_data_dir/results_dir
#     from private paths or environment overrides; shared style and the submission
#     profile supply artwork settings. Locked count/axis assertions are not inputs.
# Outputs:
#   - IPW, date-imputation, regimen-restriction, tipping, and power results.
# Reproducibility:
#   - Date imputation samples plausible observed dates within response category;
#     bootstrap draws resample observed patients. These are empirical resampling.
#   - The power check instead generates exponential event times with rexp under
#     a specified PD hazard ratio; censor times resample observed NCR follow-up
#     multiplied by censoring_multiplier. This is an assumption-based simulation,
#     not observed-patient resampling or a source of replacement clinical data.
#   - Analytic power uses observed NCR event/share estimates and a Schoenfeld
#     approximation; it remains distinct from the simulated rejection frequency.
# ==============================================================================

# Reviewer-facing sensitivity analyses for the OV therapy-end landmark main
# analysis (script 17):
#   1. Selection into the landmark cohort (usable first-line end date):
#      inverse-probability-of-inclusion weighting (IPW) with robust Wald tests,
#      stochastic imputation of missing end dates (response-specific empirical
#      distribution), and a tipping analysis over fixed imputed end dates.
#   2. Regimen/population restrictions (platinum-taxane doublet, standard
#      duration, timely start, advanced stage, configured high grades, no
#      first-line radiotherapy). The display label "Grade 3–4" covers G3/G4.
#   3. Power for the PD step (PD vs PR+SD): detectable HR in TCGA NCR patients,
#      events/patients needed for future cohorts, and an exponential-event check.
#      The optional external four-class PD-step table is printed, not refitted.

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr); library(purrr)
  library(survival); library(ggplot2); library(patchwork)
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
seed <- analysis_config$random_seeds$selection_power
configure_reproducible_runtime(seed, threads = 1L)
landmark_bounds <- analysis_config$landmark$plausible_end_days
tipping_days <- analysis_config$landmark$tipping_days
standard_duration <- analysis_config$cohort$standard_duration_days
maximum_start_day <- analysis_config$cohort$maximum_start_day
minimum_tss_samples <- analysis_config$cohort$minimum_tss_samples
advanced_stages <- analysis_config$cohort$advanced_stages
high_grade_levels <- analysis_config$cohort$high_grade_levels
platinum_agents <- analysis_config$cohort$platinum_agents
taxane_agents <- analysis_config$cohort$taxane_agents
ipw_truncation_quantiles <- analysis_config$selection$ipw_truncation_quantiles
restricted_bootstrap <- analysis_config$resampling$restricted_bootstrap_replicates
power_simulations <- analysis_config$resampling$power_simulation_replicates
date_imputation_replicates <- analysis_config$resampling$date_imputation_replicates
survival_alpha <- analysis_config$survival$alpha
wald_z_95 <- analysis_config$survival$wald_z_95
censoring_multiplier <- analysis_config$power$censoring_multiplier
processed_dir <- config$paths$processed_data_dir
results_dir <- config$paths$results_dir
out_tab <- file.path(results_dir, "tables", "ov_selection_regimen_power")
out_fig <- file.path(results_dir, "figures", "ov_selection_regimen_power")
dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(project_dir, "logs"), recursive = TRUE, showWarnings = FALSE)
mo <- analysis_config$survival$days_per_month

clin <- read_csv(file.path(processed_dir, "tcga_ov_phase0_clinical.csv"), show_col_types = FALSE) %>%
  filter(!is.na(response4))
gdc <- read_csv(file.path(processed_dir, "pancancer_patient_response_treatment.csv"),
                show_col_types = FALSE, guess_max = 20000) %>%
  filter(cancer == "OV") %>%
  select(patient, fl_start, fl_end, fl_agents, fl_platinum, rt_start, first_line_radiation, therapy_end)
d0 <- clin %>% left_join(gdc, by = "patient") %>%
  mutate(response4 = factor(response4, levels = c("CR", "PR", "SD", "PD")),
    noncr = as.integer(response4 != "CR"), orr_fail = as.integer(response4 %in% c("SD", "PD")),
    pd_step = factor(case_when(response4 == "CR" ~ "CR", response4 == "PD" ~ "PD", TRUE ~ "PR_SD"),
      levels = c("CR", "PR_SD", "PD")),
    stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
    residual_group = factor(residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm")),
    date_ok = is.finite(therapy_end) & therapy_end >= landmark_bounds[1] & therapy_end <= landmark_bounds[2],
    tss = substr(patient, 6, 7),
    label_source = ifelse(!is.na(response_clinical), "clinical matrix", "supplement only"))
# Locked assertion: upstream labelled count, not a cohort-size parameter.
stopifnot(nrow(d0) == 454)
covars <- c("age_10y", "stage_group", "residual_group")
# Derive the date from plausible observed records; do not replace it with 152.
med_end <- median(d0$therapy_end[d0$date_ok])

# Input: clinical rows and a scalar or row-aligned origin in days. Return: OS
# rows followed strictly beyond finite origins, with post-origin time in months.
# Date plausibility is the caller's responsibility, allowing imputation/tipping.
lm_from <- function(d, origin) {
  d %>% mutate(origin = origin) %>%
    filter(is.finite(origin), is.finite(OS_days), !is.na(OS_event), OS_days > origin) %>%
    mutate(time = (OS_days - origin) / mo, event = OS_event)
}
lm_main <- lm_from(d0, ifelse(d0$date_ok, d0$therapy_end, NA))
# Locked assertion: reproduced primary landmark count, not an eligibility rule.
stopifnot(nrow(lm_main) == 372)

# Input: landmark OS rows and an adjustment flag. Return: one-row unweighted
# Cox HR/LRT/AIC/BIC summary on common complete cases. The M_PD contrast is
# beta_PD - beta_PR_SD, retaining its covariance and rounded 1.96 interval;
# it is not the separate NCR-only fit used below for power. BIC counts events.
topo_summary <- function(d, adjust = FALSE) {
  cv <- if (adjust) covars else character()
  d <- d[complete.cases(d[, c("time", "event", cv)]), ]
  rhs <- function(x) paste(c(x, cv), collapse = " + ")
  f <- list(M1 = coxph(as.formula(paste("Surv(time, event) ~", rhs("response4"))), d),
    M2 = coxph(as.formula(paste("Surv(time, event) ~", rhs("orr_fail"))), d),
    M3 = coxph(as.formula(paste("Surv(time, event) ~", rhs("noncr"))), d),
    M_PD = coxph(as.formula(paste("Surv(time, event) ~", rhs("pd_step"))), d))
  ll <- sapply(f, function(x) x$loglik[2]); k <- sapply(f, function(x) length(coef(x)))
  aic <- -2 * ll + 2 * k; bic <- -2 * ll + log(sum(d$event)) * k
  ci <- exp(cbind(coef(f$M1), confint(f$M1))); m3 <- exp(c(coef(f$M3)["noncr"], confint(f$M3)["noncr", ]))
  cp <- c(-1, 1); bpd <- coef(f$M_PD)[c("pd_stepPR_SD", "pd_stepPD")]
  lpd <- sum(cp * bpd); se_pd <- sqrt(as.numeric(t(cp) %*% vcov(f$M_PD)[names(bpd), names(bpd)] %*% cp))
  pd <- exp(lpd)
  tibble(n = nrow(d), events = sum(d$event), CR = sum(d$response4 == "CR"), PR = sum(d$response4 == "PR"),
    SD = sum(d$response4 == "SD"), PD = sum(d$response4 == "PD"),
    HR_PR = ci["response4PR", 1], HR_SD = ci["response4SD", 1], HR_PD = ci["response4PD", 1],
    HR_NonCR = m3[1], HR_NonCR_low = m3[2], HR_NonCR_high = m3[3], HR_PD_vs_PRSD = unname(pd),
    HR_PD_vs_PRSD_low = exp(lpd - wald_z_95 * se_pd), HR_PD_vs_PRSD_high = exp(lpd + wald_z_95 * se_pd), logHR_PD_se = se_pd,
    plateau_p = pchisq(2 * (ll["M1"] - ll["M3"]), 2, lower.tail = FALSE),
    ORR_p = pchisq(2 * (ll["M1"] - ll["M2"]), 2, lower.tail = FALSE),
    PD_step_p = pchisq(2 * (ll["M_PD"] - ll["M3"]), 1, lower.tail = FALSE),
    dAIC_M3_vs_best_other = aic["M3"] - min(aic[names(aic) != "M3"]),
    best_AIC = names(which.min(aic)), best_BIC = names(which.min(bic)))
}

# Input: four-state Cox fit and full-row-rank constraint matrix in PR/SD/PD
# coefficient order. Return: chi-square Wald p for C beta = 0. vcov(f) retains
# the fitted sandwich covariance for weighted/robust fits; this is not an LRT
# and treats estimated inclusion weights as fixed (no propensity-fit variance).
wald <- function(f, C) {
  b <- coef(f)[c("response4PR", "response4SD", "response4PD")]
  V <- vcov(f)[names(b), names(b)]
  q <- C %*% b; s <- as.numeric(t(q) %*% solve(C %*% V %*% t(C)) %*% q)
  pchisq(s, nrow(C), lower.tail = FALSE)
}
C_plateau <- rbind(c(1, -1, 0), c(1, 0, -1))
C_orr <- rbind(c(1, 0, 0), c(0, 1, -1))

# =============================================================== 1a. IPW
# Target population: patients alive at the end of first-line chemotherapy.
# For patients with a usable date this is known; for patients without one,
# eligibility is approximated by survival beyond the median plausible end date.
# Inclusion weighting assumes positivity and selection explained by the fitted
# response/covariate/source/site terms. Stabilized weights target the full eligible
# set and are quantile-truncated; adjusted Cox fits then use complete covariate
# rows without re-estimating the propensity model or imputing those covariates.
elig <- d0 %>% filter(is.finite(OS_days), !is.na(OS_event)) %>%
  mutate(origin_known = ifelse(date_ok, therapy_end, med_end)) %>%
  filter(OS_days > origin_known) %>%
  mutate(included = as.integer(date_ok),
    tss_group = ifelse(
      tss %in% names(which(table(tss) >= minimum_tss_samples)), tss, "other"
    ),
    residual_m = factor(ifelse(is.na(residual_group), "missing", as.character(residual_group))),
    stage_m = factor(ifelse(is.na(stage_group), "missing", as.character(stage_group))),
    age_m = ifelse(is.na(age_10y), mean(age_10y, na.rm = TRUE), age_10y))
ps_fit <- glm(included ~ response4 + age_m + stage_m + residual_m + label_source + tss_group, binomial, elig)
elig$ps <- fitted(ps_fit)
p_inc <- mean(elig$included)
elig$w_raw <- ifelse(elig$included == 1, p_inc / elig$ps, NA)
trunc <- quantile(elig$w_raw, ipw_truncation_quantiles, na.rm = TRUE)
elig$w <- pmin(pmax(elig$w_raw, trunc[1]), trunc[2])
ps_coef <- broom_like <- as_tibble(summary(ps_fit)$coefficients, rownames = "term") %>%
  rename(estimate = Estimate, se = `Std. Error`, z = `z value`, p = `Pr(>|z|)`) %>% mutate(OR = exp(estimate))
ps_lrt <- anova(update(ps_fit, . ~ . - response4), ps_fit, test = "Chisq")
ps_lrt_tss <- anova(update(ps_fit, . ~ . - tss_group), ps_fit, test = "Chisq")

# Input: complete numeric covariate/dummy, inclusion indicator and optional
# row weights. Return: included weighted mean minus full-target mean, divided
# by full-target SD (zero for a constant covariate). This targets the entire
# eligible population, not the usual included-versus-excluded pooled-SD SMD.
smd <- function(x, g, w = NULL) {
  if (is.null(w)) w <- rep(1, length(x))
  m1 <- weighted.mean(x[g == 1], w[g == 1]); m0 <- mean(x)
  s <- sd(x); if (s == 0) return(0); (m1 - m0) / s
}
bal_vars <- model.matrix(~ response4 + age_m + stage_m + residual_m + label_source + tss_group, elig)[, -1]
w_all <- ifelse(is.na(elig$w), 1, elig$w)
balance <- tibble(variable = colnames(bal_vars),
  SMD_unweighted = apply(bal_vars, 2, smd, g = elig$included),
  SMD_weighted = apply(bal_vars, 2, function(x) smd(x, elig$included, w_all)))

ipw_d <- lm_main %>% inner_join(elig %>% filter(included == 1) %>% select(patient, w), by = "patient")
stopifnot(nrow(ipw_d) == nrow(lm_main))
ipw_rows <- list()
for (adj in c(FALSE, TRUE)) for (wt in c("unweighted", "IPW")) {
  cv <- if (adj) covars else character()
  dd <- ipw_d[complete.cases(ipw_d[, c("time", "event", cv)]), ]
  ww <- if (wt == "IPW") dd$w else rep(1, nrow(dd))
  rhs <- function(x) paste(c(x, cv), collapse = " + ")
  f1 <- coxph(as.formula(paste("Surv(time, event) ~", rhs("response4"))), dd, weights = ww, robust = TRUE)
  f3 <- coxph(as.formula(paste("Surv(time, event) ~", rhs("noncr"))), dd, weights = ww, robust = TRUE)
  fp <- coxph(as.formula(paste("Surv(time, event) ~", rhs("pd_step"))), dd, weights = ww, robust = TRUE)
  cp <- c(-1, 1); bpd <- coef(fp)[c("pd_stepPR_SD", "pd_stepPD")]; vpd <- vcov(fp)[names(bpd), names(bpd)]
  lpd <- sum(cp * bpd); se_pd <- sqrt(as.numeric(t(cp) %*% vpd %*% cp))
  ci <- exp(cbind(coef(f1), confint(f1))); m3 <- exp(c(coef(f3)["noncr"], confint(f3)["noncr", ]))
  ipw_rows[[length(ipw_rows) + 1]] <- tibble(adjustment = ifelse(adj, "age+stage+residual", "none"), weighting = wt,
    n = nrow(dd), ESS = sum(ww)^2 / sum(ww^2),
    CR = sum(dd$response4 == "CR"), PR = sum(dd$response4 == "PR"),
    SD = sum(dd$response4 == "SD"), PD = sum(dd$response4 == "PD"),
    HR_PR = ci["response4PR", 1], HR_SD = ci["response4SD", 1], HR_PD = ci["response4PD", 1],
    HR_PD_low = ci["response4PD", 2], HR_PD_high = ci["response4PD", 3],
    HR_PR_low = ci["response4PR", 2], HR_PR_high = ci["response4PR", 3],
    HR_SD_low = ci["response4SD", 2], HR_SD_high = ci["response4SD", 3],
    HR_NonCR = m3[1], HR_NonCR_low = m3[2], HR_NonCR_high = m3[3],
    HR_PD_vs_PRSD = exp(lpd), HR_PD_vs_PRSD_low = exp(lpd - wald_z_95 * se_pd), HR_PD_vs_PRSD_high = exp(lpd + wald_z_95 * se_pd),
    plateau_p_robust = wald(f1, C_plateau), ORR_p_robust = wald(f1, C_orr), PD_step_p_robust = 2 * pnorm(-abs(lpd / se_pd)))
}
ipw_tab <- bind_rows(ipw_rows)

# =============================================================== 1b. stochastic date imputation
# Missing/implausible end dates drawn from the empirical plausible end-date
# distribution of the same response category; landmark applied per draw.
# Assume usable dates represent missing dates conditional on response, with a
# nonempty donor pool in every state. Dates are drawn without conditioning on
# individual survival, so landmark eligibility can legitimately vary by draw.
pool_ends <- split(d0$therapy_end[d0$date_ok], d0$response4[d0$date_ok])
d_os <- d0 %>% filter(is.finite(OS_days), !is.na(OS_event))
M <- date_imputation_replicates
imp_rows <- list(); imp_fits <- list()
for (m in seq_len(M)) {
  draw <- d_os$therapy_end
  miss <- !d_os$date_ok
  draw[miss] <- vapply(as.character(d_os$response4[miss]), function(r) sample(pool_ends[[r]], 1), numeric(1))
  ld <- lm_from(d_os, draw)
  s <- topo_summary(ld)
  imp_rows[[m]] <- s %>% mutate(imputation = m)
  imp_fits[[m]] <- coxph(Surv(time, event) ~ response4, ld)
}
imp_tab <- bind_rows(imp_rows)
# Input: four-state fits across date imputations and PR/SD/PD constraint rows.
# Return: pooled F, df and p via the retained D1 approximation, including the
# single-constraint shape branch. Treat date draws as multiple imputations;
# eligibility may change across draws, and this is not a bootstrap LRT pool.
d1_test <- function(fits, C) {
  m <- length(fits); k <- nrow(C); nm <- c("response4PR", "response4SD", "response4PD")
  q <- t(sapply(fits, function(f) as.numeric(C %*% coef(f)[nm]))); if (k == 1) q <- t(q)
  U <- lapply(fits, function(f) C %*% vcov(f)[nm, nm] %*% t(C))
  qbar <- colMeans(q); Ubar <- Reduce(`+`, U) / m; B <- cov(q)
  r <- (1 + 1 / m) * sum(diag(B %*% solve(Ubar))) / k
  D <- as.numeric(t(qbar) %*% solve(Ubar) %*% qbar) / (k * (1 + r))
  tt <- k * (m - 1)
  v <- if (tt > 4) 4 + (tt - 4) * (1 + (1 - 2 / tt) / r)^2 else tt * (1 + 1 / k) * (1 + 1 / r)^2 / 2
  c(F = D, df1 = k, df2 = v, p = pf(D, k, v, lower.tail = FALSE))
}
# Pool log-HRs with within/between-date-imputation variance and retain the
# original normal interval (rounded 1.96), not a new small-sample t interval.
q_pd <- log(imp_tab$HR_PD_vs_PRSD); u_pd <- imp_tab$logHR_PD_se^2
T_pd <- mean(u_pd) + (1 + 1 / M) * var(q_pd)
imp_summary <- tibble(imputations = M,
  pooled_HR_PD_vs_PRSD = exp(mean(q_pd)), pooled_HR_PD_vs_PRSD_low = exp(mean(q_pd) - wald_z_95 * sqrt(T_pd)),
  pooled_HR_PD_vs_PRSD_high = exp(mean(q_pd) + wald_z_95 * sqrt(T_pd)),
  median_n = median(imp_tab$n), median_PD = median(imp_tab$PD),
  pooled_plateau_p = d1_test(imp_fits, C_plateau)["p"],
  pooled_ORR_p = d1_test(imp_fits, C_orr)["p"],
  median_PD_step_p = median(imp_tab$PD_step_p),
  median_HR_PD_vs_PRSD = median(imp_tab$HR_PD_vs_PRSD),
  frac_plateau_rejected = mean(imp_tab$plateau_p < survival_alpha),
  frac_best_AIC_M3 = mean(imp_tab$best_AIC == "M3"), frac_best_AIC_M_PD = mean(imp_tab$best_AIC == "M_PD"),
  frac_best_AIC_M1 = mean(imp_tab$best_AIC == "M1"), frac_best_BIC_M3 = mean(imp_tab$best_BIC == "M3"))

# =============================================================== 1c. tipping analysis over imputed dates
tip <- bind_rows(lapply(tipping_days, function(x) {
  origin <- ifelse(d_os$date_ok, d_os$therapy_end, x)
  topo_summary(lm_from(d_os, origin)) %>% mutate(imputed_end_days = x, .before = 1)
}))

# =============================================================== 2. regimen / population restrictions
# Input: one semicolon-delimited agent string. Return: TRUE only when every
# exact token is allowed and both platinum and taxane are present; NA is FALSE.
# Do not trim, deduplicate or permit extra agents; this matches script 20.
agents_ok <- function(a) {
  is_platinum_taxane_doublet(a, platinum_agents, taxane_agents)
}
lm_main <- lm_main %>% mutate(
  plat_taxane = vapply(fl_agents, agents_ok, logical(1)),
  duration = fl_end - fl_start,
  std_duration = is.finite(duration) & duration >= standard_duration[1] & duration <= standard_duration[2],
  timely_start = is.finite(fl_start) & fl_start <= maximum_start_day,
  advanced = stage_group %in% advanced_stages,
  grade3 = grade %in% high_grade_levels,
  no_rt = !first_line_radiation)
restriction_names <- c(
  "All (main analysis)",
  "Platinum-taxane doublet only",
  sprintf("Standard duration (%d-%d d)", standard_duration[1], standard_duration[2]),
  sprintf("Start within %d d of diagnosis", maximum_start_day),
  sprintf("Stage %s", paste(advanced_stages, collapse = "-")),
  "Grade 3",
  "No first-line radiation",
  "All restrictions combined"
)
restr <- setNames(list(
  rep(TRUE, nrow(lm_main)),
  lm_main$plat_taxane,
  lm_main$std_duration,
  lm_main$timely_start,
  lm_main$advanced,
  lm_main$grade3,
  lm_main$no_rt,
  with(lm_main, plat_taxane & std_duration & timely_start & advanced & grade3 & no_rt)
), restriction_names)
reg_tab <- bind_rows(lapply(names(restr), function(nm) bind_rows(lapply(c(FALSE, TRUE), function(adj)
  topo_summary(lm_main[restr[[nm]], ], adj) %>% mutate(restriction = nm,
    adjustment = ifelse(adj, "age+stage+residual", "none"), .before = 1)))))

# Input: restricted landmark rows and requested draws. Return: valid-draw count,
# four lowest-AIC frequencies and plateau rejection fraction. Whole-patient
# resampling is unstratified; incomplete-state draws are omitted and the Cox
# fits are response-only, distinct from the robust IPW and power algorithms.
boot_m3 <- function(d, B = restricted_bootstrap) {
  r <- replicate(B, {
    b <- d[sample(nrow(d), replace = TRUE), ]
    if (length(unique(b$response4)) < 4) return(c(NA, NA))
    ll <- c(coxph(Surv(time, event) ~ response4, b)$loglik[2], coxph(Surv(time, event) ~ orr_fail, b)$loglik[2],
      coxph(Surv(time, event) ~ noncr, b)$loglik[2], coxph(Surv(time, event) ~ pd_step, b)$loglik[2])
    aic <- -2 * ll + 2 * c(3, 1, 1, 2)
    c(which.min(aic), pchisq(2 * (ll[1] - ll[3]), 2, lower.tail = FALSE) < survival_alpha)
  })
  r <- r[, !is.na(r[1, ])]
  tibble(B = ncol(r), M1 = mean(r[1, ] == 1), M2 = mean(r[1, ] == 2), M3 = mean(r[1, ] == 3), M_PD = mean(r[1, ] == 4),
    plateau_rejected = mean(r[2, ] == 1))
}
reg_boot <- bind_rows(lapply(c("Platinum-taxane doublet only", "All restrictions combined"), function(nm)
  boot_m3(lm_main[restr[[nm]], ]) %>% mutate(restriction = nm, .before = 1)))

# =============================================================== 3. power for the PD step
# Schoenfeld: required events D = (z_a + z_b)^2 / (p (1 - p) log(HR)^2), with p the
# PD share among NCR patients; the comparison is restricted to NCR patients.
za <- qnorm(1 - analysis_config$survival$alpha / 2)
zb <- qnorm(analysis_config$power$target_power)
# Input: NCR event count D and PD share p. Return: detectable HR above one
# under the Schoenfeld two-group approximation; require D > 0 and 0 < p < 1.
mde <- function(D, p) exp((za + zb) / sqrt(p * (1 - p) * D))
# Input: target HR != 1 and PD share among NCR. Return: required NCR events
# (unrounded); caller ceilings and scales by observed event/NCR fractions.
events_needed <- function(hr, p) (za + zb)^2 / (p * (1 - p) * log(hr)^2)
nc <- lm_main %>% filter(response4 != "CR") %>% mutate(pd = as.integer(response4 == "PD"))
f_nc <- coxph(Surv(time, event) ~ pd, nc)
f_nc_adj <- coxph(Surv(time, event) ~ pd + age_10y + stage_group + residual_group, nc)
ci_nc <- exp(c(coef(f_nc), confint(f_nc))); ci_nc_adj <- exp(c(coef(f_nc_adj)["pd"], confint(f_nc_adj)["pd", ]))
# External GSE63885 (four-class, serous) PD step from Phase 4 tables, if present.
ext_file <- file.path(results_dir, "tables", "phase4_external_validation", "os_posthoc_pd_vs_pr_sd.csv")
ext <- if (file.exists(ext_file)) read_csv(ext_file, show_col_types = FALSE) else NULL
p_pd <- mean(nc$pd)
# Both rows retain the full observed NCR design counts for analytic power;
# only the adjusted HR uses the Cox covariate-complete subset. Do not silently
# replace the shared event count/share with an adjusted-fit denominator.
power_tab <- tibble(
  setting = c("TCGA therapy-end landmark, NCR patients", "TCGA, NCR patients, adjusted"),
  n_nonCR = nrow(nc), n_PD = sum(nc$pd), events = sum(nc$event), PD_share = p_pd,
  HR_PD_vs_PRSD = c(ci_nc[1], ci_nc_adj[1]), low = c(ci_nc[2], ci_nc_adj[2]), high = c(ci_nc[3], ci_nc_adj[3]),
  MDE_80pct = mde(sum(nc$event), p_pd))
# Future cohort: events and patients needed. OS event fraction among NCR
# patients during follow-up taken from TCGA (observed); total cohort size shown
# for a TCGA-like NCR share and for a 45% share (measurable-disease cohorts).
ev_frac <- mean(nc$event); nc_share <- mean(lm_main$noncr)
need <- expand_grid(
  HR = analysis_config$power$future_hazard_ratios,
  PD_share = analysis_config$power$future_pd_fractions
) %>%
  mutate(nonCR_events = ceiling(events_needed(HR, PD_share)),
    nonCR_patients = ceiling(nonCR_events / ev_frac),
    PD_patients = ceiling(nonCR_patients * PD_share),
    total_patients_TCGA_like = ceiling(nonCR_patients / nc_share),
    total_patients_45pct_nonCR = ceiling(
      nonCR_patients / analysis_config$power$alternative_noncr_share
    ),
    event_fraction_assumed = ev_frac, nonCR_share_TCGA = nc_share)

# Input: assumed PD-vs-PR/SD HR and replicate count; nc supplies fixed observed
# PD labels and follow-up. Return: Cox Wald rejection frequency at survival.alpha.
# Event times are exponential with baseline median calibrated to median(nc$time);
# censor times independently resample that observed follow-up times the configured
# multiplier, not a reverse-KM censoring distribution. The legacy null fit 'base'
# is retained but does not calibrate the rate. This is not an observed-data HR.
sim_power <- function(hr, B = power_simulations) {
  base <- coxph(Surv(time, event) ~ 1, nc)
  mean(replicate(B, {
    x <- nc$pd; rate <- 1 / median(nc$time) * log(2)
    t_ev <- rexp(nrow(nc), rate * hr^x); t_c <- sample(nc$time, nrow(nc), replace = TRUE) * censoring_multiplier
    tt <- pmin(t_ev, t_c); ee <- as.integer(t_ev <= t_c)
    summary(coxph(Surv(tt, ee) ~ x))$coefficients[1, 5] < survival_alpha
  }))
}
sim_tab <- tibble(HR = analysis_config$power$pd_step_hazard_ratios) %>% mutate(simulated_power = vapply(HR, sim_power, numeric(1)))

# =============================================================== write outputs
write_csv(ps_coef, file.path(out_tab, "inclusion_model_coefficients.csv"))
write_csv(tibble(test = c("response4 in inclusion model", "tissue source site in inclusion model"),
  df = c(ps_lrt$Df[2], ps_lrt_tss$Df[2]), deviance = c(ps_lrt$Deviance[2], ps_lrt_tss$Deviance[2]),
  p = c(ps_lrt$`Pr(>Chi)`[2], ps_lrt_tss$`Pr(>Chi)`[2]),
  n_eligible = nrow(elig), n_included = sum(elig$included),
  w_min = min(elig$w, na.rm = TRUE), w_max = max(elig$w, na.rm = TRUE)),
  file.path(out_tab, "inclusion_model_tests.csv"))
write_csv(balance, file.path(out_tab, "ipw_balance.csv"))
write_csv(ipw_tab, file.path(out_tab, "ipw_topology.csv"))
write_csv(imp_tab, file.path(out_tab, "stochastic_date_imputation_draws.csv"))
write_csv(imp_summary, file.path(out_tab, "stochastic_date_imputation_summary.csv"))
write_csv(tip, file.path(out_tab, "tipping_imputed_end_date.csv"))
write_csv(reg_tab, file.path(out_tab, "regimen_restriction_topology.csv"))
write_csv(reg_boot, file.path(out_tab, "regimen_restriction_bootstrap.csv"))
write_csv(power_tab, file.path(out_tab, "pd_step_power_tcga.csv"))
write_csv(need, file.path(out_tab, "pd_step_required_sample_size.csv"))
write_csv(sim_tab, file.path(out_tab, "pd_step_simulated_power.csv"))

# =============================================================== figure (supplementary)
iu <- ipw_tab %>% filter(adjustment == "none")
fs <- bind_rows(
  tibble(analysis = "Main (complete cases)", est = iu$HR_PD_vs_PRSD[1], low = iu$HR_PD_vs_PRSD_low[1], high = iu$HR_PD_vs_PRSD_high[1], p = iu$plateau_p_robust[1]),
  tibble(analysis = "IPW (robust SE)", est = iu$HR_PD_vs_PRSD[2], low = iu$HR_PD_vs_PRSD_low[2], high = iu$HR_PD_vs_PRSD_high[2], p = iu$plateau_p_robust[2]),
  tibble(analysis = "Stochastic date imputation", est = imp_summary$pooled_HR_PD_vs_PRSD, low = imp_summary$pooled_HR_PD_vs_PRSD_low,
    high = imp_summary$pooled_HR_PD_vs_PRSD_high, p = imp_summary$pooled_plateau_p),
  reg_tab %>% filter(adjustment == "none", restriction != "All (main analysis)") %>%
    transmute(analysis = restriction, est = HR_PD_vs_PRSD, low = HR_PD_vs_PRSD_low, high = HR_PD_vs_PRSD_high, p = plateau_p))
# Display-only relabelling. Keep all ten rows, including the stochastic row that
# the locked publication crop removes; changing the row count would move every
# factor level and invalidate the approved crop coordinates. Canonical
# restriction strings in the CSV outputs remain unchanged.
s1_display <- c(
  "Main (complete cases)" = "Main (date-complete)",
  "IPW (robust SE)" = "IPW (inclusion-weighted)",
  "Platinum-taxane doublet only" = "Platinum–taxane doublet only",
  "Standard duration (84-210 d)" = "First-line duration 84–210 d",
  "Start within 84 d of diagnosis" = "Start within 84 d of diagnosis",
  "Stage III-IV" = "Stage III–IV",
  "Grade 3" = "Grade 3–4",
  "No first-line radiation" = "No first-line radiotherapy",
  "All restrictions combined" = "All restrictions combined",
  "Stochastic date imputation" = "Stochastic date imputation"
)
stopifnot(nrow(fs) == 10L, all(fs$analysis %in% names(s1_display)))
fs <- fs %>% mutate(analysis = unname(s1_display[analysis]))
fs <- fs %>% mutate(
  analysis = factor(analysis, levels = rev(analysis)),
  txt = sprintf("%.2f (%.2f–%.2f)", est, low, high), p_txt = sprintf("%.2f", p))
stopifnot(nlevels(fs$analysis) == 10L)
# Locked display assertion: all observed intervals fit the unchanged forest axis.
stopifnot(min(fs$low) > 0.4, max(fs$high) < 3.2)  # every interval inside the forest x range
# Coordinate panels open their axes exactly like Figures 2A-C and 3A-C: no panel
# box, black left/bottom axis lines, light grey major gridlines.
s1_open_axes <- theme(
  panel.border = element_blank(),
  axis.line = element_line(colour = "black", linewidth = 0.4),
  panel.grid.major = element_line(linewidth = 0.3, colour = "grey88")
)
pA_forest <- ggplot(fs, aes(est, analysis, xmin = low, xmax = high)) + geom_vline(xintercept = 1, linetype = 2) +
  geom_errorbar(width = 0.2, orientation = "y") + geom_point(size = 2.5) +
  scale_x_log10(limits = c(0.4, 3.2), breaks = c(0.5, 1, 2)) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.2))) +
  labs(x = "HR, PD vs PR+SD (OS from end of first-line therapy; 95% CI, log scale)", y = NULL, tag = "A") +
  formal_figure_theme(figure_spec) + s1_open_axes
# Numeric companion column (Figure 3 pattern) replacing the in-panel annotations.
header_y <- nlevels(fs$analysis) + 0.85
pA_cols <- ggplot(fs, aes(y = analysis)) +
  geom_text(aes(x = 0, label = txt), hjust = 0, size = figure_text, family = figure_spec$font_family) +
  geom_text(aes(x = 34, label = p_txt), hjust = 1, size = figure_text, family = figure_spec$font_family) +
  annotate("text", x = 0, y = header_y, label = "HR (95% CI)", hjust = 0,
    fontface = "bold", size = figure_text, family = figure_spec$font_family) +
  annotate("text", x = 34, y = header_y, label = "Plateau P", hjust = 1,
    fontface = "bold", size = figure_text, family = figure_spec$font_family) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.2))) +
  scale_x_continuous(limits = c(0, 34), expand = expansion(mult = c(0, 0))) +
  coord_cartesian(clip = "off") + formal_figure_theme(figure_spec, base = "void") +
  theme(plot.margin = margin(2, 2, 2, 1, unit = "mm"))
pA <- (pA_forest | pA_cols) + plot_layout(widths = grid::unit(c(1, 36), c("null", "mm")))
pB <- ggplot(tip, aes(imputed_end_days, plateau_p)) +
  geom_hline(yintercept = survival_alpha, linetype = 2, colour = figure_style$neutral[["mid"]]) +
  geom_point(colour = figure_style$neutral[["dark"]], size = 2.2) +
  scale_x_continuous(breaks = sort(unique(tip$imputed_end_days))) +
  labs(x = "Imputed end date for patients without a usable date (days)",
    y = "Plateau test P", tag = "B") + formal_figure_theme(figure_spec) + s1_open_axes
pC <- ggplot(need %>% mutate(PD_share = factor(PD_share)), aes(HR, nonCR_patients, colour = PD_share, shape = PD_share)) +
  geom_line() + geom_point(size = 2.0) +
  scale_x_continuous(breaks = c(1.3, 1.5, 1.75, 2.0),
    labels = c("1.3", "1.5", "1.75", "2.0")) +
  scale_y_log10(breaks = c(100, 200, 500, 1000),
    labels = c("100", "200", "500", "1000")) +
  scale_colour_manual(values = figure_style$power) + scale_shape_manual(values = c(`0.1` = 16, `0.2` = 17, `0.3` = 15)) +
  labs(x = "Target HR, PD vs PR+SD", y = "NCR patients needed (80% power)", colour = "PD share\nof NCR", shape = "PD share\nof NCR", tag = "C") +
  formal_figure_theme(figure_spec) + s1_open_axes +
  theme(legend.position = "inside", legend.position.inside = c(0.98, 0.98),
    legend.justification = c(1, 1),
    # Opaque white legend panel so the log-axis gridlines do not run through the
    # PD-share labels at the upper right of panel C.
    legend.background = element_rect(fill = "white", colour = NA),
    legend.key = element_rect(fill = "white", colour = NA))
# Final double-column layout: forest with numeric column on top, sensitivity curves below.
fig_s1 <- pA / wrap_elements(full = pB | pC) + plot_layout(heights = c(0.55, 0.45))
save_formal_figure(fig_s1, file.path(out_fig, "FigS_selection_regimen_power"), height_mm = 180, spec = figure_spec)

options(width = 250)
sink(file.path(project_dir, "logs/ov_selection_regimen_power_summary.txt"))
cat("OV selection / regimen / power sensitivity:", format(Sys.time()), "\n\n")
cat("Median plausible end date:", med_end, "\n")
cat("\nInclusion model tests:\n"); print(read_csv(file.path(out_tab, "inclusion_model_tests.csv"), show_col_types = FALSE) %>% as.data.frame())
cat("\nInclusion model (OR):\n"); print(as.data.frame(ps_coef %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))))
cat("\nBalance:\n"); print(as.data.frame(balance %>% mutate(across(where(is.numeric), ~ round(.x, 3)))))
cat("\nIPW topology:\n"); print(as.data.frame(ipw_tab %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))))
cat("\nStochastic date imputation:\n"); print(as.data.frame(imp_summary))
cat("\nTipping:\n"); print(as.data.frame(tip %>% select(imputed_end_days, n, PD, HR_PR, HR_SD, HR_PD, HR_PD_vs_PRSD, plateau_p, PD_step_p, best_AIC, best_BIC) %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))))
cat("\nRegimen restrictions:\n"); print(as.data.frame(reg_tab %>% select(restriction, adjustment, n, events, PD, HR_PR, HR_SD, HR_PD, HR_NonCR, HR_PD_vs_PRSD, plateau_p, ORR_p, PD_step_p, best_AIC, best_BIC) %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))))
cat("\nRegimen bootstrap:\n"); print(as.data.frame(reg_boot))
cat("\nPower (TCGA):\n"); print(as.data.frame(power_tab))
cat("\nSimulated power:\n"); print(as.data.frame(sim_tab))
cat("\nRequired sample size:\n"); print(as.data.frame(need))
if (!is.null(ext)) { cat("\nExternal PD-step table:\n"); print(as.data.frame(ext)) }
sink()
cat(readLines(file.path(project_dir, "logs/ov_selection_regimen_power_summary.txt")), sep = "\n")
