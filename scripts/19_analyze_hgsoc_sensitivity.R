#!/usr/bin/env Rscript

# ==============================================================================
# File: 19_analyze_hgsoc_sensitivity.R
# Purpose: Repeat response-topology analyses in operationally defined advanced HGSOC.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Labelled Phase 0 TCGA-OV clinical rows and script 15's first-line treatment
#     records, joined by patient; no separate histology variable is available.
# Runtime parameters:
#   - config/analysis.yml: random_seeds.hgsoc_sensitivity; landmark.plausible_end_days
#     and fixed_days[1]; cohort.hgsoc_grades/advanced_stages;
#     resampling.bootstrap_replicates and cross_validation_repeats/folds;
#     survival.days_per_month, alpha, wald_z_95 (original rounded 1.96) and
#     time_dependent_auc_months; response.equivalence_margin/relaxed_equivalence_margin;
#     reporting.split_quantiles for empirical C-index repeat summaries.
#   - load_project_configuration(project_dir) resolves processed_data_dir/results_dir
#     from private paths or environment overrides; shared style and the submission
#     profile supply artwork settings. stopifnot counts are locked assertions.
#   - Four response codings, the age/stage/residual adjustment set and 90%
#     equivalence intervals retain their original definitions; diagnosis rows
#     describe selection rather than replace the primary therapy-end landmark.
# Outputs:
#   - HGSOC model, bootstrap, equivalence, PH-test, CV, and forest-plot outputs.
# Reproducibility:
#   - Bootstrap draws resample observed cases; incomplete/failed draws are omitted.
#     Operational HGSOC means configured grade/stage within TCGA-OV, assumed serous
#     by study design, not a newly adjudicated histological diagnosis.
#   - Response-stratified CV uses seed + repeat and unchanged within-fold C-index
#     counts. Legacy pooled-LP 36-month AUC stays pending review and unreported.
# ==============================================================================

# HGSOC population-restriction sensitivity analysis for the ovarian response-
# topology manuscript. The clinical-matrix file contains no separate histology
# field; TCGA-OV is treated as serous by study design. The operational HGSOC
# restriction mirrors the parallel analysis: grade G2-G4 and FIGO stage III-IV.
# The primary sensitivity retains script 17's patient-specific therapy-end
# landmark. Diagnosis-origin and fixed-landmark fits are descriptive selection/
# timing comparisons, not replacements for that primary analysis.

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr)
  library(survival); library(timeROC); library(ggplot2); library(patchwork)
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
seed <- analysis_config$random_seeds$hgsoc_sensitivity
configure_reproducible_runtime(seed, threads = 1L)
landmark_bounds <- analysis_config$landmark$plausible_end_days
fixed_landmark <- analysis_config$landmark$fixed_days[1]
bootstrap_replicates <- analysis_config$resampling$bootstrap_replicates
equivalence_margin <- analysis_config$response$equivalence_margin
relaxed_margin <- analysis_config$response$relaxed_equivalence_margin
auc_horizon <- analysis_config$survival$time_dependent_auc_months
survival_alpha <- analysis_config$survival$alpha
wald_z_95 <- analysis_config$survival$wald_z_95
split_quantiles <- analysis_config$reporting$split_quantiles
processed_dir <- config$paths$processed_data_dir
out_tab <- file.path(config$paths$results_dir, "tables", "ov_hgsoc_sensitivity")
out_fig <- file.path(config$paths$results_dir, "figures", "ov_hgsoc_sensitivity")
dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)
mo <- analysis_config$survival$days_per_month

clin <- read_csv(file.path(processed_dir, "tcga_ov_phase0_clinical.csv"),
                 show_col_types = FALSE) %>%
  filter(!is.na(response4))
gdc <- read_csv(file.path(processed_dir, "pancancer_patient_response_treatment.csv"),
                show_col_types = FALSE, guess_max = 20000) %>%
  filter(cancer == "OV") %>%
  select(patient, fl_start, fl_end, fl_agents, fl_platinum, therapy_end)

d0 <- clin %>% left_join(gdc, by = "patient") %>%
  mutate(
    response4 = factor(response4, levels = c("CR", "PR", "SD", "PD")),
    noncr = as.integer(response4 != "CR"),
    orr_fail = as.integer(response4 %in% c("SD", "PD")),
    pd_step = factor(case_when(response4 == "CR" ~ "CR",
                              response4 == "PD" ~ "PD",
                              TRUE ~ "PR_SD"),
                     levels = c("CR", "PR_SD", "PD")),
    stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
    residual_group = factor(residual_group,
                            levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm")),
    date_ok = is.finite(therapy_end) & therapy_end >= landmark_bounds[1] &
      therapy_end <= landmark_bounds[2],
    hgsoc_operational = grade %in% analysis_config$cohort$hgsoc_grades &
      stage_group %in% analysis_config$cohort$advanced_stages
  )
# Locked assertion: the upstream unified-label cohort has 454 rows; not an input.
stopifnot(nrow(d0) == 454)

# Input: clinical rows and a scalar or row-aligned origin in days. Return: OS
# survivors followed strictly beyond finite origins with time in months.
# The caller applies date plausibility; zero/fixed origins describe selection.
lm_from <- function(d, origin) {
  d %>% mutate(origin = origin) %>%
    filter(is.finite(origin), is.finite(OS_days), !is.na(OS_event), OS_days > origin) %>%
    mutate(time = (OS_days - origin) / mo, event = OS_event)
}

main_all <- lm_from(d0, ifelse(d0$date_ok, d0$therapy_end, NA))
d_hg <- d0 %>% filter(hgsoc_operational)
hg_end <- lm_from(d_hg, ifelse(d_hg$date_ok, d_hg$therapy_end, NA))
hg_dx_all <- lm_from(d_hg, rep(0, nrow(d_hg)))
hg_dx_same <- lm_from(d_hg %>% filter(patient %in% hg_end$patient),
                      rep(0, nrow(d_hg %>% filter(patient %in% hg_end$patient))))
hg_fixed183 <- lm_from(d_hg, rep(fixed_landmark, nrow(d_hg)))

cohort_flow <- bind_rows(
  d0 %>% count(response4) %>% mutate(stage = "All labelled TCGA-OV"),
  d_hg %>% count(response4) %>% mutate(stage = "Operational HGSOC labelled"),
  hg_end %>% count(response4) %>% mutate(stage = "Operational HGSOC therapy-end landmark")
) %>%
  pivot_wider(names_from = response4, values_from = n, values_fill = 0) %>%
  mutate(total = CR + PR + SD + PD,
         definition = case_when(
           stage == "Operational HGSOC labelled" ~ "TCGA-OV (serous by study design), grade G2-G4, FIGO III-IV",
           stage == "Operational HGSOC therapy-end landmark" ~ "Same HGSOC restriction; alive/observed beyond patient-specific plausible therapy end",
           TRUE ~ "Unified labelled TCGA-OV cohort"
         )) %>%
  select(stage, definition, total, CR, PR, SD, PD)
write_csv(cohort_flow, file.path(out_tab, "hgsoc_cohort_flow.csv"))

covars <- c("age_10y", "stage_group", "residual_group")
# Input: landmark OS rows and an adjustment flag. Return: complete-case data,
# four Efron Cox fits and their HR/LRT/AIC/BIC summary. All response categories
# must remain; nested-test df retain this script's fitted-coefficient counts.
# BIC counts events; PD-vs-PR/SD is the M_PD covariance contrast, not an NCR refit.
fit_topology <- function(d, adjust = FALSE) {
  cv <- if (adjust) covars else character()
  d <- d[complete.cases(d[, c("time", "event", cv)]), ]
  d$response4 <- droplevels(d$response4)
  d$pd_step <- droplevels(d$pd_step)
  stopifnot(nlevels(d$response4) == 4, nlevels(d$pd_step) == 3)
  rhs <- function(x) paste(c(x, cv), collapse = " + ")
  f <- list(
    M1 = coxph(as.formula(paste("Surv(time, event) ~", rhs("response4"))), d, ties = "efron"),
    M2 = coxph(as.formula(paste("Surv(time, event) ~", rhs("orr_fail"))), d, ties = "efron"),
    M3 = coxph(as.formula(paste("Surv(time, event) ~", rhs("noncr"))), d, ties = "efron"),
    M_PD = coxph(as.formula(paste("Surv(time, event) ~", rhs("pd_step"))), d, ties = "efron")
  )
  ll <- vapply(f, function(x) x$loglik[2], numeric(1))
  k <- vapply(f, function(x) length(coef(x)), integer(1))
  aic <- -2 * ll + 2 * k
  bic <- -2 * ll + log(sum(d$event)) * k
  ci1 <- exp(cbind(coef(f$M1), confint(f$M1)))
  m3 <- exp(c(coef(f$M3)["noncr"], confint(f$M3)["noncr", ]))
  bpd <- coef(f$M_PD)[c("pd_stepPR_SD", "pd_stepPD")]
  cp <- c(-1, 1)
  lpd <- sum(cp * bpd)
  sepd <- sqrt(as.numeric(t(cp) %*% vcov(f$M_PD)[names(bpd), names(bpd)] %*% cp))
  list(
    data = d, fits = f,
    summary = tibble(
      n = nrow(d), events = sum(d$event),
      CR = sum(d$response4 == "CR"), PR = sum(d$response4 == "PR"),
      SD = sum(d$response4 == "SD"), PD = sum(d$response4 == "PD"),
      HR_PR = ci1["response4PR", 1], HR_PR_low = ci1["response4PR", 2], HR_PR_high = ci1["response4PR", 3],
      HR_SD = ci1["response4SD", 1], HR_SD_low = ci1["response4SD", 2], HR_SD_high = ci1["response4SD", 3],
      HR_PD = ci1["response4PD", 1], HR_PD_low = ci1["response4PD", 2], HR_PD_high = ci1["response4PD", 3],
      HR_NonCR = m3[1], HR_NonCR_low = m3[2], HR_NonCR_high = m3[3],
      HR_PD_vs_PRSD = exp(lpd), HR_PD_vs_PRSD_low = exp(lpd - wald_z_95 * sepd),
      HR_PD_vs_PRSD_high = exp(lpd + wald_z_95 * sepd),
      plateau_p = pchisq(2 * (ll["M1"] - ll["M3"]), k["M1"] - k["M3"], lower.tail = FALSE),
      ORR_p = pchisq(2 * (ll["M1"] - ll["M2"]), k["M1"] - k["M2"], lower.tail = FALSE),
      PD_step_p = pchisq(2 * (ll["M_PD"] - ll["M3"]), k["M_PD"] - k["M3"], lower.tail = FALSE),
      dAIC_M1 = aic["M1"] - min(aic), dAIC_M2 = aic["M2"] - min(aic),
      dAIC_M3 = aic["M3"] - min(aic), dAIC_M_PD = aic["M_PD"] - min(aic),
      dBIC_M1 = bic["M1"] - min(bic), dBIC_M2 = bic["M2"] - min(bic),
      dBIC_M3 = bic["M3"] - min(bic), dBIC_M_PD = bic["M_PD"] - min(bic),
      best_AIC = names(which.min(aic)), best_BIC = names(which.min(bic))
    )
  )
}

settings <- list(
  "Main TCGA-OV therapy-end" = main_all,
  "HGSOC diagnosis, all eligible" = hg_dx_all,
  "HGSOC diagnosis, therapy-end patients" = hg_dx_same,
  "HGSOC fixed 6-month landmark" = hg_fixed183,
  "HGSOC therapy-end landmark" = hg_end
)

topology <- bind_rows(lapply(names(settings), function(nm) {
  bind_rows(lapply(c(FALSE, TRUE), function(adj) {
    fit_topology(settings[[nm]], adj)$summary %>%
      mutate(setting = nm, adjustment = ifelse(adj, "age+stage+residual", "none"), .before = 1)
  }))
}))
write_csv(topology, file.path(out_tab, "hgsoc_topology_by_setting.csv"))

# Input: eligible rows and requested draws. Return: requested/valid draw counts,
# four lowest-AIC frequencies and three constraint rejection proportions.
# Resample observed whole cases without stratification, retain labels, and omit
# missing-state or failed fits. This script's tryCatch gate remains local.
boot_select <- function(d, B = bootstrap_replicates) {
  ans <- replicate(B, {
    b <- d[sample.int(nrow(d), replace = TRUE), ]
    if (length(unique(b$response4)) < 4) return(rep(NA_real_, 4))
    z <- tryCatch(fit_topology(b, FALSE), error = function(e) NULL)
    if (is.null(z)) return(rep(NA_real_, 4))
    s <- z$summary
    c(best = match(s$best_AIC, c("M1", "M2", "M3", "M_PD")),
      plateau_rejected = s$plateau_p < survival_alpha,
      ORR_rejected = s$ORR_p < survival_alpha,
      pd_step_rejected = s$PD_step_p < survival_alpha)
  })
  ans <- ans[, complete.cases(t(ans)), drop = FALSE]
  tibble(B_requested = B, B_valid = ncol(ans),
         M1 = mean(ans[1, ] == 1), M2 = mean(ans[1, ] == 2),
         M3 = mean(ans[1, ] == 3), M_PD = mean(ans[1, ] == 4),
         plateau_rejected = mean(ans[2, ] == 1),
         ORR_rejected = mean(ans[3, ] == 1),
         PD_step_rejected = mean(ans[4, ] == 1))
}
boot <- bind_rows(
  boot_select(main_all) %>% mutate(setting = "Main TCGA-OV therapy-end", .before = 1),
  boot_select(hg_end) %>% mutate(setting = "HGSOC therapy-end landmark", .before = 1)
)
write_csv(boot, file.path(out_tab, "hgsoc_bootstrap_model_selection.csv"))

# Input: HGSOC landmark rows and adjustment flag. Return: SD/PR, PD/PR and
# PD/SD contrasts from M1 with difference p, rounded-1.96 95% CIs and 90% CIs.
# Equivalence requires the entire 90% interval strictly within each configured
# margin; failure to reject a difference is not evidence of equivalence.
pairwise_contrasts <- function(d, adjust = FALSE) {
  z <- fit_topology(d, adjust)
  f <- z$fits$M1
  nm <- c("response4PR", "response4SD", "response4PD")
  b <- coef(f)[nm]; V <- vcov(f)[nm, nm]
  C <- rbind("SD vs PR" = c(-1, 1, 0),
             "PD vs PR" = c(-1, 0, 1),
             "PD vs SD" = c(0, -1, 1))
  bind_rows(lapply(seq_len(nrow(C)), function(i) {
    est <- sum(C[i, ] * b)
    se <- sqrt(as.numeric(C[i, , drop = FALSE] %*% V %*% t(C[i, , drop = FALSE])))
    lo90 <- exp(est - qnorm(0.95) * se); hi90 <- exp(est + qnorm(0.95) * se)
    tibble(comparison = rownames(C)[i], HR = exp(est),
           CI95_low = exp(est - wald_z_95 * se), CI95_high = exp(est + wald_z_95 * se),
           p_difference = 2 * pnorm(-abs(est / se)),
           CI90_low = lo90, CI90_high = hi90,
           equivalent_0.67_1.50 = lo90 > equivalence_margin[1] & hi90 < equivalence_margin[2],
           equivalent_0.50_2.00 = lo90 > relaxed_margin[1] & hi90 < relaxed_margin[2])
  })) %>% mutate(adjustment = ifelse(adjust, "age+stage+residual", "none"), .before = 1)
}
pairwise <- bind_rows(pairwise_contrasts(hg_end, FALSE), pairwise_contrasts(hg_end, TRUE))
write_csv(pairwise, file.path(out_tab, "hgsoc_noncr_pairwise_equivalence.csv"))

# Proportional-hazards checks for the primary sensitivity models.
ph_tests <- bind_rows(lapply(c(FALSE, TRUE), function(adj) {
  z <- fit_topology(hg_end, adj)
  bind_rows(lapply(c("M1", "M3", "M_PD"), function(nm) {
    zz <- cox.zph(z$fits[[nm]])$table
    tibble(adjustment = ifelse(adj, "age+stage+residual", "none"), model = nm,
           term = rownames(zz), chisq = zz[, "chisq"], p = zz[, "p"])
  }))
}))
write_csv(ph_tests, file.path(out_tab, "hgsoc_ph_tests.csv"))

# Repeated stratified 5-fold CV of coding discrimination in complete cases.
cv_d <- hg_end[complete.cases(hg_end[, covars]), ]
forms <- list(
  clinical = "age_10y + stage_group + residual_group",
  clinical_ORR = "orr_fail + age_10y + stage_group + residual_group",
  clinical_CR_threshold = "noncr + age_10y + stage_group + residual_group",
  clinical_PD_step = "pd_step + age_10y + stage_group + residual_group",
  clinical_four_state = "response4 + age_10y + stage_group + residual_group"
)
cv_rows <- list(); cv_fold_rows <- list(); cv_assignment_rows <- list()
cv_repeats <- analysis_config$resampling$cross_validation_repeats
cv_folds <- analysis_config$resampling$cross_validation_folds
for (r in seq_len(cv_repeats)) {
  # Preserve the original splits; compare scores only within each validation fold.
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
  for (kfold in seq_len(cv_folds)) {
    tr <- cv_d[folds != kfold, ]; te <- cv_d[folds == kfold, ]
    stopifnot(length(intersect(tr$patient, te$patient)) == 0L)
    for (nm in names(forms)) {
      f <- coxph(as.formula(paste("Surv(time, event) ~", forms[[nm]])), tr, ties = "efron")
      # Structural aliasing (e.g. absent early-stage cases) can yield an NA
      # coefficient under singular.ok; finite validation scores are required.
      stopifnot(all(is.finite(coef(f)[!is.na(coef(f))])))
      prediction <- as.numeric(predict(f, newdata = te, type = "lp"))
      lp[folds == kfold, nm] <- prediction
      repeat_counts[[length(repeat_counts) + 1]] <- as_tibble(
        cv_fold_concordance(te$time, te$event, prediction)
      ) %>% mutate(repeat_id = r, fold_id = kfold, model = nm, .before = 1)
    }
  }
  repeat_counts <- bind_rows(repeat_counts)
  stopifnot(!anyNA(lp), all(repeat_counts %>% group_by(fold_id) %>%
    summarise(k = n_distinct(comparable_pairs), .groups = "drop") %>% pull(k) == 1L))
  cv_fold_rows[[r]] <- repeat_counts
  for (nm in names(forms)) {
    cidx <- cv_repeat_concordance(repeat_counts %>% filter(model == nm), nrow(cv_d), cv_folds)
    cv_rows[[length(cv_rows) + 1]] <- bind_cols(tibble(repeat_id = r, model = nm), as_tibble(cidx)) %>%
      mutate(
        legacy_pooled_C_index = concordance(Surv(cv_d$time, cv_d$event) ~ lp[, nm], reverse = TRUE)$concordance,
        AUC_36m = timeROC(T = cv_d$time, delta = cv_d$event, marker = lp[, nm],
                          cause = 1, times = auc_horizon, iid = FALSE)$AUC[2],
        auc_method = "legacy_pooled_lp", auc_status = "pending_method_review_not_reported"
      )
  }
}
cv_rep <- bind_rows(cv_rows)
cv_sum <- cv_rep %>% group_by(model) %>%
  summarise(n = nrow(cv_d), median_C = median(C_index),
            q05_C = quantile(C_index, split_quantiles[1]), q95_C = quantile(C_index, split_quantiles[2]),
            median_AUC36 = median(AUC_36m),
            q05_AUC36 = quantile(AUC_36m, split_quantiles[1]), q95_AUC36 = quantile(AUC_36m, split_quantiles[2]),
            c_index_method = first(c_index_method), auc_method = first(auc_method), auc_status = first(auc_status),
            .groups = "drop") %>% arrange(desc(median_C))
write_csv(cv_rep, file.path(out_tab, "hgsoc_cv_discrimination_replicates.csv"))
write_csv(cv_sum, file.path(out_tab, "hgsoc_cv_discrimination_summary.csv"))
write_csv(bind_rows(cv_fold_rows), file.path(out_tab, "hgsoc_cv_concordance_by_fold.csv"))
write_csv(bind_rows(cv_assignment_rows), file.path(out_tab, "hgsoc_cv_fold_assignments.csv"))

# Compact forest plot for the primary HGSOC landmark estimate.
s <- topology %>% filter(setting == "HGSOC therapy-end landmark", adjustment == "none")
plot_d <- tibble(response = factor(c("PR", "SD", "PD"), levels = c("PD", "SD", "PR")),
                 HR = c(s$HR_PR, s$HR_SD, s$HR_PD),
                 low = c(s$HR_PR_low, s$HR_SD_low, s$HR_PD_low),
                 high = c(s$HR_PR_high, s$HR_SD_high, s$HR_PD_high),
                 n = c(s$PR, s$SD, s$PD)) %>%
  mutate(txt = sprintf("%.2f (%.2f–%.2f)", HR, low, high),
         n_txt = as.character(as.integer(n)))
# Coordinate panels open their axes exactly like Figures 2A-C, 3A-C and S1A-C:
# no panel box, black left/bottom axis lines, light grey major gridlines.
s2_open_axes <- theme(
  panel.border = element_blank(),
  axis.line = element_line(colour = "black", linewidth = 0.4),
  panel.grid.major = element_line(linewidth = 0.3, colour = "grey88")
)
p_forest <- ggplot(plot_d, aes(HR, response, colour = response)) +
  geom_vline(xintercept = 1, linetype = 2, colour = figure_style$neutral[["mid"]]) +
  geom_errorbar(aes(xmin = low, xmax = high), orientation = "y", width = 0.15, linewidth = 0.7) +
  geom_point(size = 2.4) +
  scale_colour_manual(values = figure_style$response[c("PR", "SD", "PD")]) +
  scale_x_log10() + scale_y_discrete(expand = expansion(add = c(0.6, 1.2))) +
  labs(x = "Hazard ratio versus CR (log scale)", y = NULL) +
  formal_figure_theme(figure_spec) + s2_open_axes + theme(legend.position = "none")
# Numeric companion column (audited Figure 3 / S1A pattern): HR (95% CI) and per-row n.
header_y <- nlevels(plot_d$response) + 0.85
p_cols <- ggplot(plot_d, aes(y = response)) +
  geom_text(aes(x = 0, label = txt), hjust = 0, size = figure_text, family = figure_spec$font_family) +
  geom_text(aes(x = 34, label = n_txt), hjust = 1, size = figure_text, family = figure_spec$font_family) +
  annotate("text", x = 0, y = header_y, label = "HR (95% CI)", hjust = 0,
    fontface = "bold", size = figure_text, family = figure_spec$font_family) +
  annotate("text", x = 34, y = header_y, label = "n", hjust = 1,
    fontface = "bold", size = figure_text, family = figure_spec$font_family) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.2))) +
  scale_x_continuous(limits = c(0, 34), expand = expansion(mult = c(0, 0))) +
  coord_cartesian(clip = "off") + formal_figure_theme(figure_spec, base = "void") +
  theme(plot.margin = margin(2, 2, 2, 1, unit = "mm"))
p <- (p_forest | p_cols) + plot_layout(widths = grid::unit(c(1, 30), c("null", "mm")))
# Single-panel artwork: 120 mm native width, centred on the supplementary
# figure page, so the three-row forest does not stretch across the full text
# width. Text remains at the 8 pt minimum and the numeric column stays legible.
save_formal_figure(p, file.path(out_fig, "hgsoc_four_state_forest"), height_mm = 45,
                   width_mm = 120, spec = figure_spec)

# Machine-readable audit summary.
primary <- topology %>% filter(setting == "HGSOC therapy-end landmark", adjustment == "none")
summary_lines <- c(
  sprintf("Operational HGSOC: TCGA-OV (serous by study design), grade G2-G4, FIGO III-IV."),
  sprintf("Landmark n=%d; events=%d; CR/PR/SD/PD=%d/%d/%d/%d.",
          primary$n, primary$events, primary$CR, primary$PR, primary$SD, primary$PD),
  sprintf("HR vs CR: PR %.2f, SD %.2f, PD %.2f; NCR %.2f (95%% CI %.2f-%.2f).",
          primary$HR_PR, primary$HR_SD, primary$HR_PD,
          primary$HR_NonCR, primary$HR_NonCR_low, primary$HR_NonCR_high),
  sprintf("Plateau LRT p=%.4g; ORR constraint p=%.4g; PD-step p=%.4g.",
          primary$plateau_p, primary$ORR_p, primary$PD_step_p),
  sprintf("Best AIC=%s; best BIC=%s.", primary$best_AIC, primary$best_BIC),
  sprintf("Bootstrap HGSOC: M3 %.1f%%, M_PD %.1f%%, M1 %.1f%%, ORR rejected %.1f%%, plateau rejected %.1f%%.",
          100 * boot$M3[boot$setting == "HGSOC therapy-end landmark"],
          100 * boot$M_PD[boot$setting == "HGSOC therapy-end landmark"],
          100 * boot$M1[boot$setting == "HGSOC therapy-end landmark"],
          100 * boot$ORR_rejected[boot$setting == "HGSOC therapy-end landmark"],
          100 * boot$plateau_rejected[boot$setting == "HGSOC therapy-end landmark"])
)
writeLines(summary_lines, file.path(out_tab, "hgsoc_sensitivity_summary.txt"))
writeLines(capture.output(sessionInfo()), file.path(out_tab, "sessionInfo_R20.txt"))
cat(paste(summary_lines, collapse = "\n"), "\n")
