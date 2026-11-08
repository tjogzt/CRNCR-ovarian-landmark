#!/usr/bin/env Rscript

# ==============================================================================
# File: 34_response_partition_calibration_sensitivity.R
# Purpose: Generate the exploratory response-partition scan, the 36/60-month
#   calibration checks and the NCR E-values reported as Supplementary Table S7
#   and Supplementary Figure S6.
# Author: Project authors
# Created: 2026-11-01
# Inputs:
#   - data/processed/tcga_ov_phase0_clinical.csv and
#     data/processed/pancancer_patient_response_treatment.csv, read through the
#     configured processed-data directory.
#   - config/analysis.yml: landmark plausible_end_days, survival.days_per_month,
#     random_seeds.response_sensitivity and the response level order.
#   - config/submission_profile.json: figure width, height limit, minimum font
#     size, font family and semantic response colours.
# Outputs:
#   - results/tables/ov_response_sensitivity/*.csv: the full scan, the seven
#     distinct partitions, calibration summary/by-response/decile tables and
#     E-values, plus a run metadata record.
#   - results/tables/supplementary/TableS7_response_partition_scan.csv and
#     TableS7_evalues.csv: formal table sources.
#   - results/figures/ov_response_sensitivity/FigureS6_calibration.pdf/.png and
#     byte-identical copies under results/figures/supplementary.
# Runtime parameters:
#   - Bootstrap replicates for slope optimism are fixed at the manuscript value
#     of 1000; the seed is random_seeds.response_sensitivity. Cohort sizes and
#     death counts are stopifnot assertions on the published cohort, not inputs.
# Notes:
#   - The cohort is reconstructed with the same rules as script 17; the
#     assertions fail the run if those rules or the input data change.
#   - The outcome is common at 36 and 60 months, so E-values are computed after
#     approximating the risk ratio from the hazard ratio
#     (VanderWeele & Ding, Ann Intern Med 2017); the uncorrected value is kept
#     for comparison only.
#   - Calibration is apparent performance in the derivation cohort, not
#     external validation.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(survival)
  library(ggplot2)
  library(patchwork)
})

# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)

analysis_config <- config$analysis
seed <- analysis_config$random_seeds$response_sensitivity
mo <- analysis_config$survival$days_per_month
landmark_bounds <- analysis_config$landmark$plausible_end_days
states <- analysis_config$response$four_levels
processed_dir <- config$paths$processed_data_dir
results_dir <- config$paths$results_dir
out_tab <- file.path(results_dir, "tables", "ov_response_sensitivity")
out_fig <- file.path(results_dir, "figures", "ov_response_sensitivity")
sup_tab <- file.path(results_dir, "tables", "supplementary")
sup_fig <- file.path(results_dir, "figures", "supplementary")
for (directory in c(out_tab, out_fig, sup_tab, sup_fig)) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
}
configure_reproducible_runtime(seed)
set.seed(seed)

covars <- c("age_10y", "stage_group", "residual_group")
boot_replicates <- 1000L

# ---- Cohort reconstruction (same rules as script 17) -------------------------
clin <- read_csv(file.path(processed_dir, "tcga_ov_phase0_clinical.csv"),
                 show_col_types = FALSE) %>%
  filter(!is.na(response4))
gdc <- read_csv(file.path(processed_dir, "pancancer_patient_response_treatment.csv"),
                show_col_types = FALSE, guess_max = 20000) %>%
  filter(cancer == "OV") %>%
  select(patient, fl_start, fl_end, therapy_end)

d0 <- clin %>%
  left_join(gdc, by = "patient") %>%
  mutate(
    response4 = factor(response4, levels = states),
    noncr = as.integer(response4 != "CR"),
    stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
    residual_group = factor(residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm")),
    date_ok = is.finite(therapy_end) &
      therapy_end >= landmark_bounds[1] & therapy_end <= landmark_bounds[2]
  )

ld <- d0 %>%
  mutate(origin = ifelse(date_ok, therapy_end, NA_real_),
         time_raw = OS_days, event = OS_event) %>%
  filter(is.finite(origin), is.finite(time_raw), !is.na(event), time_raw > origin) %>%
  mutate(time = (time_raw - origin) / mo)

# Locked assertions on the published cohort.
stopifnot(nrow(ld) == 372, sum(ld$event) == 220)
cc <- ld[complete.cases(ld[, c("time", "event", covars)]), ]
stopifnot(nrow(cc) == 343, sum(cc$event) == 207)

# ==============================================================================
# 1. Scan of all non-empty subsets of CR/PR/SD/PD
# ==============================================================================
# Each subset S defines a binary contrast: the complement versus S. Fifteen
# non-empty subsets give 14 estimable directed contrasts, which collapse to
# seven distinct partitions. Benjamini-Hochberg correction uses the seven
# partitions in both the adjusted and the unadjusted model.

subsets <- unlist(lapply(seq_along(states), function(k) combn(states, k, simplify = FALSE)),
                   recursive = FALSE)

scan_set <- function(d, adjust) {
  cv <- if (adjust) covars else character()
  d <- d[complete.cases(d[, c("time", "event", cv)]), ]
  bind_rows(lapply(subsets, function(S) {
    comp <- setdiff(states, S)
    d$out <- as.integer(!(as.character(d$response4) %in% S))
    n_out <- sum(d$out == 1)
    n_in <- sum(d$out == 0)
    row <- tibble(
      subset = paste(S, collapse = "+"),
      complement = if (length(comp)) paste(comp, collapse = "+") else "(none)",
      n = nrow(d),
      events = sum(d$event),
      n_subset = n_in,
      n_complement = n_out,
      events_subset = sum(d$event[d$out == 0]),
      events_complement = sum(d$event[d$out == 1]),
      estimable = n_out > 0 && n_in > 0
    )
    if (!row$estimable) {
      return(row %>% mutate(HR_complement_vs_subset = NA_real_, CI_low = NA_real_,
                            CI_high = NA_real_, wald_p = NA_real_, lrt_p = NA_real_))
    }
    form <- as.formula(paste("Surv(time, event) ~ out",
                             if (length(cv)) paste("+", paste(cv, collapse = " + ")) else ""))
    fit <- coxph(form, data = d)
    ci <- exp(confint(fit)["out", ])
    fit0 <- coxph(as.formula(paste("Surv(time, event) ~",
                                   if (length(cv)) paste(cv, collapse = " + ") else "1")), data = d)
    lrt <- anova(fit0, fit, test = "LRT")
    row %>% mutate(
      HR_complement_vs_subset = exp(unname(coef(fit)["out"])),
      CI_low = unname(ci[1]),
      CI_high = unname(ci[2]),
      wald_p = summary(fit)$coefficients["out", "Pr(>|z|)"],
      lrt_p = lrt$`Pr(>|Chi|)`[2]
    )
  }))
}

scan <- bind_rows(lapply(c(FALSE, TRUE), function(adj) {
  scan_set(ld, adj) %>% mutate(adjustment = ifelse(adj, "age+stage+residual", "none"))
})) %>%
  group_by(adjustment) %>%
  mutate(
    q_bh_14directed = p.adjust(wald_p, method = "BH"),
    rank_p_14directed = rank(wald_p, ties.method = "min", na.last = "keep")
  ) %>%
  ungroup() %>%
  relocate(adjustment)

# Distinct partitions: orient each as the CR-containing group (reference)
# versus the group without CR (comparator), so every partition appears once.
scan_est <- scan %>% filter(estimable)
key <- mapply(function(a, b) paste(sort(c(strsplit(a, "\\+")[[1]], strsplit(b, "\\+")[[1]])),
                                   collapse = "+"),
              scan_est$subset, scan_est$complement, USE.NAMES = FALSE)
scan_est <- scan_est %>% mutate(partition_key = key)
uniq <- scan_est %>%
  group_by(adjustment, partition_key) %>%
  filter(grepl("(^|\\+)CR($|\\+)", subset)) %>%
  ungroup() %>%
  mutate(
    partition = paste0(subset, " vs ", complement),
    is_ncr_split = subset == "CR",
    is_orr_split = subset == "CR+PR",
    is_pd_step_split = subset == "CR+PR+SD"
  ) %>%
  group_by(adjustment) %>%
  mutate(
    q_bh_7partitions = p.adjust(wald_p, method = "BH"),
    rank_p_7partitions = rank(wald_p, ties.method = "min"),
    q_bh_7_lrt = p.adjust(lrt_p, method = "BH")
  ) %>%
  ungroup() %>%
  arrange(adjustment, wald_p) %>%
  relocate(adjustment, partition, is_ncr_split, is_orr_split, is_pd_step_split)

stopifnot(sum(scan$estimable) == 28L, nrow(uniq) == 14L)
stopifnot(all(uniq %>% count(adjustment) %>% pull(n) == 7L))
stopifnot(all(scan %>% group_by(adjustment) %>% summarise(n = sum(estimable)) %>% pull(n) == 14L))

write_csv(scan, file.path(out_tab, "partition_scan_all15.csv"))
write_csv(uniq, file.path(out_tab, "partition_scan_unique.csv"))

# Wide formal table: one row per distinct partition, adjusted and unadjusted.
wide <- uniq %>%
  select(adjustment, partition, subset, complement, n, events,
         HR_complement_vs_subset, CI_low, CI_high, wald_p, lrt_p,
         q_bh_7partitions, rank_p_7partitions) %>%
  pivot_wider(names_from = adjustment,
              values_from = c(n, events, HR_complement_vs_subset, CI_low, CI_high,
                              wald_p, lrt_p, q_bh_7partitions, rank_p_7partitions),
              names_glue = "{.value}_{adjustment}") %>%
  rename_with(~ str_replace_all(.x, "age\\+stage\\+residual", "adjusted")) %>%
  rename_with(~ str_replace_all(.x, "none", "unadjusted")) %>%
  transmute(
    reference = subset,
    comparator = complement,
    n_adjusted = n_adjusted,
    events_adjusted = events_adjusted,
    HR_adjusted = HR_complement_vs_subset_adjusted,
    CI_low_adjusted = CI_low_adjusted,
    CI_high_adjusted = CI_high_adjusted,
    p_adjusted = wald_p_adjusted,
    lrt_p_adjusted = lrt_p_adjusted,
    q_adjusted = q_bh_7partitions_adjusted,
    rank_adjusted = rank_p_7partitions_adjusted,
    n_unadjusted = n_unadjusted,
    events_unadjusted = events_unadjusted,
    HR_unadjusted = HR_complement_vs_subset_unadjusted,
    CI_low_unadjusted = CI_low_unadjusted,
    CI_high_unadjusted = CI_high_unadjusted,
    p_unadjusted = wald_p_unadjusted,
    lrt_p_unadjusted = lrt_p_unadjusted,
    q_unadjusted = q_bh_7partitions_unadjusted,
    rank_unadjusted = rank_p_7partitions_unadjusted
  ) %>%
  arrange(rank_adjusted)

stopifnot(nrow(wide) == 7L)
stopifnot(wide$reference[1] == "CR", wide$comparator[1] == "PR+SD+PD")
stopifnot(abs(wide$q_adjusted[1] - 2.4e-14) < 1e-15)
stopifnot(abs(wide$HR_adjusted[1] - 3.59) < 0.005)
write_csv(wide, file.path(out_tab, "table_s7_partition_scan.csv"))

# ==============================================================================
# 2. Calibration at 36 and 60 months for the adjusted CR-versus-NCR model
# ==============================================================================
m3 <- coxph(Surv(time, event) ~ noncr + age_10y + stage_group + residual_group,
            data = cc, x = TRUE, y = TRUE)

risk_cox <- function(fit, newdata, horizon) {
  bh <- basehaz(fit, centered = FALSE)
  H0 <- if (any(bh$time <= horizon)) max(bh$hazard[bh$time <= horizon]) else 0
  lp <- predict(fit, newdata = newdata, type = "lp", reference = "zero")
  1 - exp(-H0 * exp(lp))
}

make_Ghat <- function(d) {
  g <- survfit(Surv(time, 1 - event) ~ 1, data = d)
  function(times) {
    s <- summary(g, times = pmax(times, 0), extend = TRUE)$surv
    pmax(s, 1e-6)
  }
}

ipcw_calibration <- function(d, pred, horizon) {
  n <- nrow(d)
  ghat <- make_Ghat(d)
  ev_t <- as.integer(d$event == 1 & d$time <= horizon)
  w <- numeric(n)
  w[ev_t == 1] <- 1 / ghat(d$time[ev_t == 1] - 1e-9)
  w[ev_t == 0 & d$time > horizon] <- 1 / ghat(horizon)
  w[ev_t == 0 & d$time <= horizon] <- 0
  if (sum(ev_t) == 0 || sum(ev_t) == n) return(list(slope = NA_real_, citl = NA_real_))
  pred_logit <- qlogis(pmin(pmax(pred, 1e-6), 1 - 1e-6))
  fit0 <- suppressWarnings(glm(ev_t ~ offset(pred_logit), family = quasibinomial(), weights = w))
  fit1 <- suppressWarnings(glm(ev_t ~ pred_logit, family = quasibinomial(), weights = w))
  list(slope = unname(coef(fit1)[2]), citl = unname(coef(fit0)[1]))
}

decile_calibration <- function(d, pred, horizon) {
  d <- d %>% mutate(pred = pred, grp = dplyr::ntile(pred, 10))
  km <- survfit(Surv(time, event) ~ grp, data = d)
  s <- summary(km, times = horizon, extend = TRUE)
  grp <- as.integer(sub("grp=", "", as.character(s$strata)))
  counts <- d %>% group_by(grp) %>%
    summarise(n = n(), events_by_horizon = sum(event == 1 & time <= horizon),
              mean_pred = mean(pred), .groups = "drop")
  tibble(grp = grp, observed = 1 - s$surv, low = 1 - s$upper, high = 1 - s$lower) %>%
    left_join(counts, by = "grp") %>%
    arrange(grp) %>%
    mutate(horizon_months = horizon, .before = 1)
}

calibrate_one <- function(d, horizon, B = boot_replicates) {
  pred <- risk_cox(m3, d, horizon)
  ic <- ipcw_calibration(d, pred, horizon)
  km <- survfit(Surv(time, event) ~ 1, data = d)
  obs <- 1 - summary(km, times = horizon, extend = TRUE)$surv
  form <- Surv(time, event) ~ noncr + age_10y + stage_group + residual_group
  optimism <- rep(NA_real_, B)
  slope_boot <- rep(NA_real_, B)
  for (b in seq_len(B)) {
    idx <- sample.int(nrow(d), replace = TRUE)
    db <- d[idx, , drop = FALSE]
    if (sum(db$event) < 10) next
    bad <- FALSE
    fb <- withCallingHandlers(
      tryCatch(coxph(form, data = db, x = TRUE), error = function(e) NULL),
      warning = function(w) { bad <<- TRUE; invokeRestart("muffleWarning") })
    if (bad || is.null(fb) || anyNA(coef(fb)) || any(!is.finite(coef(fb))) ||
        max(abs(coef(fb))) > 10) next
    pb_app <- tryCatch(risk_cox(fb, db, horizon), error = function(e) rep(NA_real_, nrow(db)))
    pb_test <- tryCatch(risk_cox(fb, d, horizon), error = function(e) rep(NA_real_, nrow(d)))
    sa <- ipcw_calibration(db, pb_app, horizon)$slope
    st <- ipcw_calibration(d, pb_test, horizon)$slope
    if (!is.finite(sa) || !is.finite(st)) next
    optimism[b] <- sa - st
    slope_boot[b] <- sa
  }
  valid <- sum(!is.na(optimism))
  opt <- mean(optimism, na.rm = TRUE)
  sb <- slope_boot[!is.na(slope_boot)]
  tibble(
    horizon_months = horizon,
    n = nrow(d),
    events_by_horizon = sum(d$event == 1 & d$time <= horizon),
    mean_predicted = mean(pred),
    observed_km = obs,
    oe_ratio = obs / mean(pred),
    citl_logit = ic$citl,
    slope_apparent = ic$slope,
    optimism_mean = opt,
    slope_corrected = ic$slope - opt,
    boot_valid = valid,
    boot_requested = B,
    boot_slope_low = if (length(sb)) unname(quantile(sb, 0.025)) else NA_real_,
    boot_slope_high = if (length(sb)) unname(quantile(sb, 0.975)) else NA_real_
  )
}

cal <- bind_rows(calibrate_one(cc, 36), calibrate_one(cc, 60))
stopifnot(nrow(cal) == 2L, all(cal$boot_valid > 950))
write_csv(cal, file.path(out_tab, "calibration_summary.csv"))

by_response_calibration <- function(d, horizon) {
  pred <- risk_cox(m3, d, horizon)
  dd <- d %>% mutate(pred = pred)
  km <- survfit(Surv(time, event) ~ response4, data = dd)
  s <- summary(km, times = horizon, extend = TRUE)
  tibble(
    response = sub("response4=", "", as.character(s$strata)),
    observed = 1 - s$surv,
    low = 1 - s$upper,
    high = 1 - s$lower
  ) %>%
    left_join(
      dd %>% group_by(response4) %>%
        summarise(n = n(), events_by_horizon = sum(event == 1 & time <= horizon),
                  mean_pred = mean(pred), .groups = "drop") %>%
        mutate(response = as.character(response4)) %>%
        select(response, n, events_by_horizon, mean_pred),
      by = "response"
    ) %>%
    mutate(horizon_months = horizon,
           mean_predicted_pct = 100 * mean_pred,
           observed_km_pct = 100 * observed,
           low_pct = 100 * low,
           high_pct = 100 * high) %>%
    relocate(horizon_months)
}

by_resp <- bind_rows(by_response_calibration(cc, 36), by_response_calibration(cc, 60))
write_csv(by_resp, file.path(out_tab, "calibration_by_response.csv"))

deciles <- bind_rows(decile_calibration(cc, risk_cox(m3, cc, 36), 36),
                     decile_calibration(cc, risk_cox(m3, cc, 60), 60))
write_csv(deciles, file.path(out_tab, "calibration_by_decile.csv"))

# Cross-check predicted risks against riskRegression when installed.
rr_check <- tryCatch({
  pr <- riskRegression::predictRisk(m3, newdata = cc, times = c(36, 60))
  c(max_abs_diff_36 = max(abs(pr[, 1] - risk_cox(m3, cc, 36))),
    max_abs_diff_60 = max(abs(pr[, 2] - risk_cox(m3, cc, 60))))
}, error = function(e) c(max_abs_diff_36 = NA_real_, max_abs_diff_60 = NA_real_))
writeLines(paste(names(rr_check), format(rr_check, scientific = TRUE, digits = 3), sep = ": "),
           file.path(out_tab, "predictrisk_crosscheck.txt"))
stopifnot(all(is.na(rr_check) | rr_check < 1e-12))

# ---- Formal calibration figure ----------------------------------------------
figure_spec <- load_figure_specification(project_dir)
figure_style <- get_figure_style(project_dir)
response_levels <- states
response_colours <- figure_style$response[response_levels]

headline <- cal %>%
  select(horizon_months, citl = citl_logit, oe = oe_ratio, slope = slope_corrected) %>%
  mutate(label = sprintf("CITL %s%.2f  |  O:E %.2f  |  slope %.2f",
                         ifelse(citl < 0, "\u2212", ""), abs(citl), oe, slope))

base_theme <- formal_figure_theme(figure_spec) +
  theme(
    panel.grid.major = element_line(linewidth = 0.3, colour = "grey88"),
    plot.tag.position = c(0.012, 0.985),
    plot.margin = margin(3, 3, 2.5, 3, unit = "mm")
  )
axis_theme <- theme(
  axis.title = element_text(size = figure_spec$min_font_pt),
  axis.text = element_text(size = figure_spec$min_font_pt, colour = "black")
)

cal_panel <- function(dat, horizon, xlab, ylab, title, point_colour = NULL,
                      show_legend = FALSE) {
  ann <- headline %>% filter(horizon_months == horizon)
  p <- ggplot(dat, aes(x = 100 * mean_pred, y = 100 * observed))
  if (is.null(point_colour)) {
    p <- p + geom_point(size = 1.9, shape = 16, colour = figure_style$neutral[["dark"]])
  } else {
    p <- p + geom_point(aes(colour = response), size = 1.9, shape = 16)
  }
  p <- p +
    geom_errorbar(aes(ymin = 100 * low, ymax = 100 * high),
                  width = 1.6, linewidth = 0.4, na.rm = TRUE,
                  colour = if (is.null(point_colour)) figure_style$neutral[["dark"]] else "grey35") +
    geom_abline(slope = 1, intercept = 0, colour = "grey45", linewidth = 0.45) +
    annotate("text", x = 99, y = 2, label = ann$label, hjust = 1, vjust = 0,
             size = figure_text_size(figure_spec, figure_spec$min_font_pt),
             family = figure_spec$font_family,
             colour = figure_style$neutral[["muted_text"]]) +
    scale_x_continuous(limits = c(0, 100), breaks = c(0, 25, 50, 75, 100),
                       expand = expansion(mult = 0.02)) +
    scale_y_continuous(limits = c(0, 100), breaks = c(0, 25, 50, 75, 100),
                       expand = expansion(mult = 0.02)) +
    labs(x = xlab, y = ylab, title = title) +
    coord_cartesian(xlim = c(0, 100), ylim = c(0, 100)) +
    base_theme + axis_theme +
    theme(plot.title = element_text(size = figure_spec$min_font_pt, face = "bold",
                                    margin = margin(l = 4.5, unit = "mm")),
          plot.title.position = "plot",
          plot.tag.position = c(0.002, 0.99))
  if (!is.null(point_colour)) {
    p <- p + scale_colour_manual(values = response_colours, name = NULL,
                                 breaks = response_levels)
    p <- if (show_legend) {
      p + theme(legend.position = "inside", legend.position.inside = c(0.02, 0.98),
                legend.justification = c(0, 1), legend.direction = "vertical",
                legend.background = element_blank(), legend.key = element_blank(),
                legend.key.height = unit(3.2, "mm"), legend.key.width = unit(3.2, "mm"),
                legend.text = element_text(size = figure_spec$min_font_pt),
                legend.margin = margin(1, 1, 1, 1))
    } else {
      p + theme(legend.position = "none")
    }
  }
  p
}

resp_36 <- by_resp %>% filter(horizon_months == 36) %>%
  mutate(response = factor(response, levels = response_levels))
resp_60 <- by_resp %>% filter(horizon_months == 60) %>%
  mutate(response = factor(response, levels = response_levels))
dec_36 <- deciles %>% filter(horizon_months == 36, !is.na(mean_pred))
dec_60 <- deciles %>% filter(horizon_months == 60, !is.na(mean_pred))

pA <- cal_panel(resp_36, 36, NULL, "Observed death risk (%)",
                "36 months, by response", point_colour = TRUE, show_legend = TRUE)
pB <- cal_panel(resp_60, 60, NULL, NULL,
                "60 months, by response", point_colour = TRUE, show_legend = FALSE)
pC <- cal_panel(dec_36, 36, "Predicted death risk (%)", "Observed death risk (%)",
                "36 months, by decile")
pD <- cal_panel(dec_60, 60, "Predicted death risk (%)", NULL,
                "60 months, by decile")

assembly <- (pA | pB) / (pC | pD) +
  plot_annotation(tag_levels = "A") &
  theme(plot.tag = element_text(size = figure_spec$tag_font_pt, face = "bold",
                                family = figure_spec$font_family))

figure_stem <- file.path(out_fig, "FigureS6_calibration")
saved <- save_formal_figure(assembly, figure_stem, height_mm = 168, spec = figure_spec)
stopifnot(all(file.copy(saved, file.path(sup_fig, basename(saved)), overwrite = TRUE)))

# ==============================================================================
# 3. E-values for the NCR hazard ratio
# ==============================================================================
evalue <- Vectorize(function(hr) {
  if (hr >= 1) hr + sqrt(hr * (hr - 1)) else {
    hr_inv <- 1 / hr
    hr_inv + sqrt(hr_inv * (hr_inv - 1))
  }
})
evalue_ci <- function(low, high) {
  if (low > 1) evalue(low) else if (high < 1) evalue(1 / high) else 1
}

# Death was common at both horizons, so the hazard ratio is not a risk ratio.
# Approximate RR from HR before applying the E-value formula, following
# VanderWeele and Ding (2017), and keep the uncorrected value for comparison.
hr_to_rr_common <- function(hr) (1 - 0.5^sqrt(hr)) / (1 - 0.5^sqrt(1 / hr))
evalue_rr <- Vectorize(function(rr) {
  if (rr >= 1) rr + sqrt(rr * (rr - 1)) else {
    rr_inv <- 1 / rr
    rr_inv + sqrt(rr_inv * (rr_inv - 1))
  }
})
evalue_common_ci <- function(low, high) {
  if (low > 1) evalue_rr(hr_to_rr_common(low))
  else if (high < 1) evalue_rr(hr_to_rr_common(1 / high))
  else 1
}
prop_death_36 <- mean(cc$event == 1 & cc$time <= 36)
prop_death_60 <- mean(cc$event == 1 & cc$time <= 60)
stopifnot(prop_death_36 > 0.15, prop_death_60 > 0.15)

# Adjusted estimates are read from the fitted model and the partition scan so
# the reported E-values cannot drift from the manuscript numbers.
m3_coef <- summary(m3)$coefficients
hr_adj <- exp(unname(m3_coef["noncr", "coef"]))
hr_adj_low <- exp(unname(m3_coef["noncr", "coef"] - 1.96 * m3_coef["noncr", "se(coef)"]))
hr_adj_high <- exp(unname(m3_coef["noncr", "coef"] + 1.96 * m3_coef["noncr", "se(coef)"]))
ncr_split <- wide %>% filter(reference == "CR")
stopifnot(abs(hr_adj - ncr_split$HR_adjusted) < 0.005)

ev <- tibble(
  estimand = c("NCR vs CR, adjusted", "NCR vs CR, unadjusted", "PR vs CR, adjusted (context)"),
  HR = c(hr_adj, ncr_split$HR_unadjusted, 3.14),
  CI_low = c(hr_adj_low, ncr_split$CI_low_unadjusted, 2.14),
  CI_high = c(hr_adj_high, ncr_split$CI_high_unadjusted, 4.62),
  source = c("M3, age+stage+residual, n=343",
             "M3, unadjusted, n=372",
             "M1 PR coefficient, age+stage+residual, n=343")
) %>%
  mutate(E_value_point = evalue(HR),
         E_value_CI = mapply(evalue_ci, CI_low, CI_high),
         ci_bound_used = ifelse(CI_low > 1, CI_low,
                                ifelse(CI_high < 1, CI_high, NA_real_)),
         RR_approx = hr_to_rr_common(HR),
         RR_CI_low_approx = hr_to_rr_common(CI_low),
         E_value_common_point = evalue_rr(RR_approx),
         E_value_common_CI = mapply(evalue_common_ci, CI_low, CI_high),
         outcome_36 = prop_death_36,
         outcome_60 = prop_death_60)
stopifnot(abs(ev$E_value_common_point[1] - 4.21) < 0.02)
stopifnot(abs(ev$E_value_common_CI[1] - 3.27) < 0.02)
write_csv(ev, file.path(out_tab, "evalues.csv"))

# ---- Formal supplementary table copies --------------------------------------
formal <- c(file.path(out_tab, "table_s7_partition_scan.csv"),
            file.path(out_tab, "evalues.csv"))
destinations <- c(file.path(sup_tab, "TableS7_response_partition_scan.csv"),
                  file.path(sup_tab, "TableS7_evalues.csv"))
stopifnot(all(file.copy(formal, destinations, overwrite = TRUE)))

# ---- Run metadata ------------------------------------------------------------
writeLines(c(
  paste("R version:", R.version.string),
  paste("survival:", as.character(packageVersion("survival"))),
  paste("riskRegression:", tryCatch(as.character(packageVersion("riskRegression")),
                                    error = function(e) "not installed")),
  paste("seed:", seed),
  paste("landmark n:", nrow(ld), "events:", sum(ld$event)),
  paste("covariate-complete n:", nrow(cc), "events:", sum(cc$event)),
  paste("bootstrap requested:", boot_replicates),
  paste("bootstrap valid:", paste(cal$boot_valid, collapse = ", ")),
  paste("deaths by 36 months:", sum(cc$event == 1 & cc$time <= 36)),
  paste("deaths by 60 months:", sum(cc$event == 1 & cc$time <= 60))
), file.path(out_tab, "run_metadata.txt"))

cat("Response partition, calibration and E-value analyses complete.\n")
cat("Table S7 sources:", paste(destinations, collapse = ", "), "\n")
cat("Figure S6:", paste(saved, collapse = ", "), "\n")
