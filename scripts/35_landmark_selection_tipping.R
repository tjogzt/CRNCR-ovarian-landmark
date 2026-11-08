#!/usr/bin/env Rscript

# ==============================================================================
# File: 35_landmark_selection_tipping.R
# Purpose: Quantify how far the CR-versus-NCR hazard ratio could move under
#   extreme assumptions about the 82 labelled patients excluded from the
#   therapy-end landmark cohort. The analysis is an outcome-level tipping
#   sensitivity, not an estimate of the true excluded-group survival.
# Author: Project authors
# Created: 2026-11-02
# Inputs:
#   - data/supplementary/SupplementaryData1_TCGA_OV_cases.csv: published
#     case-level landmark flags, response labels, recorded therapy end, OS time
#     and OS indicator.
#   - config/analysis.yml: survival.days_per_month.
# Outputs:
#   - results/tables/ov_selection_tipping/landmark_selection_tipping.csv:
#     observed fit, two extreme re-inclusion scenarios and the full tipping
#     curves for excluded CR and excluded NCR deaths.
#   - results/tables/ov_selection_tipping/landmark_selection_tipping_summary.csv:
#     one-row summary used in the manuscript text, including Kaplan-Meier
#     median OS from diagnosis for included and excluded NCR patients.
# Runtime parameters: none beyond the configured days-per-month constant.
# Notes:
#   - Excluded patients have no usable landmark. The extreme scenarios assign
#     them a synthetic time of 0.01 month after the landmark: all CR deaths and
#     all NCR censoring (adverse), or the reverse (favourable). These bounds are
#     deliberately implausible; persistence of the association under them shows
#     that the direction of the CR-NCR contrast is not created by landmark
#     selection.
#   - The one excluded PR without an OS time is assigned the scenario event
#     indicator, because the scenario is a bound rather than an observed fit.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(survival)
})

file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)
mo <- config$analysis$survival$days_per_month

cases_path <- file.path(project_dir, "data", "supplementary", "SupplementaryData1_TCGA_OV_cases.csv")
out_dir <- file.path(config$paths$results_dir, "tables", "ov_selection_tipping")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cases <- read_csv(cases_path, show_col_types = FALSE) %>%
  mutate(
    response4 = as.character(response4),
    ncr = as.integer(response4 != "CR"),
    event = as.integer(OS_event)
  )

included <- cases %>%
  filter(main_landmark_cohort == 1) %>%
  transmute(time = (OS_days - therapy_end) / mo, event = event, ncr = ncr)
excluded <- cases %>%
  filter(main_landmark_cohort == 0)

stopifnot(nrow(included) == 372L, sum(included$event) == 220L,
          nrow(excluded) == 82L,
          sum(excluded$response4 == "CR") == 46L,
          sum(excluded$response4 != "CR") == 36L,
          all(included$time > 0))

fit_binary <- function(data, scenario, description) {
  model <- coxph(Surv(time, event) ~ ncr, data = data)
  summary_model <- summary(model)
  data.frame(
    scenario = scenario,
    description = description,
    n = nrow(data),
    events = sum(data$event),
    HR = unname(summary_model$conf.int[1, "exp(coef)"]),
    CI_low = unname(summary_model$conf.int[1, "lower .95"]),
    CI_high = unname(summary_model$conf.int[1, "upper .95"]),
    p = unname(summary_model$coefficients[1, "Pr(>|z|)"]),
    stringsAsFactors = FALSE
  )
}

observed <- fit_binary(
  included, "observed",
  "372 landmark-eligible patients; no re-inclusion"
)

adverse <- bind_rows(
  included,
  tibble(
    time = 0.01,
    event = as.integer(excluded$response4 == "CR"),
    ncr = as.integer(excluded$response4 != "CR")
  )
)
adverse_fit <- fit_binary(
  adverse, "adverse_extreme",
  "All 46 excluded CR patients die at 0.01 month; all 36 excluded NCR patients censored at 0.01 month"
)

favourable <- bind_rows(
  included,
  tibble(
    time = 0.01,
    event = as.integer(excluded$response4 != "CR"),
    ncr = as.integer(excluded$response4 != "CR")
  )
)
favourable_fit <- fit_binary(
  favourable, "favourable_extreme",
  "All 36 excluded NCR patients die at 0.01 month; all 46 excluded CR patients censored at 0.01 month"
)

tipping_curve <- function(death_response, scenario_prefix) {
  deaths <- which(excluded$response4 == death_response)
  bind_rows(lapply(seq_along(deaths), function(k) {
    scenario <- tibble(
      time = 0.01,
      event = 0L,
      ncr = as.integer(excluded$response4 != "CR")
    )
    scenario$event[deaths[seq_len(k)]] <- 1L
    fit_binary(
      bind_rows(included, scenario),
      paste0(scenario_prefix, "_", k),
      paste0(k, " excluded ", death_response, " deaths at 0.01 month; all other excluded patients censored")
    )
  }))
}

cr_curve <- tipping_curve("CR", "excluded_CR_deaths")
ncr_curve <- tipping_curve("NCR", "excluded_NCR_deaths")

results <- bind_rows(observed, adverse_fit, favourable_fit, cr_curve, ncr_curve) %>%
  mutate(across(c(HR, CI_low, CI_high, p), ~ signif(.x, 6))) %>%
  select(scenario, description, n, events, HR, CI_low, CI_high, p)

write_csv(results, file.path(out_dir, "landmark_selection_tipping.csv"))

# Kaplan-Meier median OS from diagnosis. This descriptive quantity uses OS_days
# because excluded patients have no landmark-relative follow-up; the one
# labelled patient without an OS time is omitted from the fit.
km_median <- function(data, group) {
  fit <- survfit(Surv(OS_days, OS_event) ~ 1, data = data)
  tab <- summary(fit)$table
  data.frame(
    group = group,
    n = unname(tab["records"]),
    events = unname(tab["events"]),
    median_days = unname(tab["median"]),
    median_low = unname(tab["0.95LCL"]),
    median_high = unname(tab["0.95UCL"]),
    stringsAsFactors = FALSE
  )
}

km_table <- bind_rows(
  km_median(filter(cases, main_landmark_cohort == 1, response4 != "CR"), "included_NCR"),
  km_median(filter(cases, main_landmark_cohort == 0, response4 != "CR"), "excluded_NCR"),
  km_median(filter(cases, main_landmark_cohort == 0, response4 == "PD"), "excluded_PD")
)
write_csv(km_table, file.path(out_dir, "landmark_selection_km_medians.csv"))

km_value <- function(group, field) {
  km_table[[field]][match(group, km_table$group)]
}

summary_row <- data.frame(
  observed_HR = observed$HR,
  observed_CI_low = observed$CI_low,
  observed_CI_high = observed$CI_high,
  adverse_extreme_HR = adverse_fit$HR,
  adverse_extreme_CI_low = adverse_fit$CI_low,
  adverse_extreme_CI_high = adverse_fit$CI_high,
  favourable_extreme_HR = favourable_fit$HR,
  favourable_extreme_CI_low = favourable_fit$CI_low,
  favourable_extreme_CI_high = favourable_fit$CI_high,
  excluded_n = nrow(excluded),
  excluded_CR = sum(excluded$response4 == "CR"),
  excluded_NCR = sum(excluded$response4 != "CR"),
  excluded_deaths = sum(excluded$event),
  excluded_CR_deaths = sum(excluded$response4 == "CR" & excluded$event == 1),
  excluded_NCR_deaths = sum(excluded$response4 != "CR" & excluded$event == 1),
  included_NCR_km_median_days = km_value("included_NCR", "median_days"),
  included_NCR_km_median_low = km_value("included_NCR", "median_low"),
  included_NCR_km_median_high = km_value("included_NCR", "median_high"),
  excluded_NCR_km_median_days = km_value("excluded_NCR", "median_days"),
  excluded_NCR_km_median_low = km_value("excluded_NCR", "median_low"),
  excluded_NCR_km_median_high = km_value("excluded_NCR", "median_high"),
  excluded_PD_km_median_days = km_value("excluded_PD", "median_days"),
  max_excluded_CR_deaths_with_CI_above_1 = max(
    as.integer(sub("excluded_CR_deaths_", "", cr_curve$scenario[cr_curve$CI_low > 1])),
    na.rm = TRUE
  ),
  stringsAsFactors = FALSE
)
write_csv(summary_row, file.path(out_dir, "landmark_selection_tipping_summary.csv"))

cat("Observed NCR HR:", round(observed$HR, 2), "(",
    round(observed$CI_low, 2), "-", round(observed$CI_high, 2), ")\n")
cat("Adverse extreme:", round(adverse_fit$HR, 2), "(",
    round(adverse_fit$CI_low, 2), "-", round(adverse_fit$CI_high, 2), ")\n")
cat("Favourable extreme:", round(favourable_fit$HR, 2), "(",
    round(favourable_fit$CI_low, 2), "-", round(favourable_fit$CI_high, 2), ")\n")
