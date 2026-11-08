#!/usr/bin/env Rscript

# ==============================================================================
# File: 02_prepare_clinical_cohort.R
# Purpose: Audit TCGA-OV response phenotypes and build the harmonized clinical cohort.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - TCGA Xena clinical, survival, and HT_HG-U133A expression files.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; response level order/equivalence bounds;
#     survival.days_per_month, confidence_level and alpha; phase0 CV and bootstrap counts.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Processed patient-level clinical data, audit tables, and descriptive figures.
# Reproducibility:
#   - Keeps source label parsing, Cox formulas and model execution order fixed.
#   - CV and bootstrap use observed patients and the existing project RNG stream.
# ==============================================================================

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(survival)
  library(survminer)
  library(ggplot2)
})

options(stringsAsFactors = FALSE)

# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)
analysis_config <- config$analysis
seed <- analysis_config$random_seeds$default
configure_reproducible_runtime(seed)

xena_dir <- config$paths$xena_dir
clinical_path <- file.path(xena_dir, "TCGA.OV.sampleMap", "OV_clinicalMatrix")
survival_path <- file.path(xena_dir, "Survival_SupplementalTable_S1_20171025_xena_sp")
expression_path <- file.path(xena_dir, "agilent_pancan", "TCGA.OV.HT_HG-U133A.gz")

required_files <- c(clinical_path, survival_path, expression_path)
if (!all(file.exists(required_files))) {
  stop("Missing required input files: ", paste(required_files[!file.exists(required_files)], collapse = ", "))
}

processed_dir <- config$paths$processed_data_dir
table_dir <- file.path(config$paths$results_dir, "tables")
figure_dir <- file.path(config$paths$results_dir, "figures")
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(project_dir, "logs"), recursive = TRUE, showWarnings = FALSE)

read_expression_samples <- function(path) {
  con <- gzfile(path, open = "rt")
  on.exit(close(con), add = TRUE)
  header <- readLines(con, n = 1L, warn = FALSE)
  strsplit(header, "\t", fixed = TRUE)[[1]][-1]
}

canonical_response <- function(x) {
  case_when(
    x == "Complete Remission/Response" ~ "CR",
    x == "Partial Remission/Response" ~ "PR",
    x == "Stable Disease" ~ "SD",
    x == "Progressive Disease" ~ "PD",
    TRUE ~ NA_character_
  )
}

stage_group <- function(x) {
  case_when(
    grepl("Stage I($|A|B|C| )|Stage II($|A|B|C| )", x, ignore.case = TRUE) ~ "I-II",
    grepl("Stage III", x, ignore.case = TRUE) ~ "III",
    grepl("Stage IV", x, ignore.case = TRUE) ~ "IV",
    TRUE ~ NA_character_
  )
}

residual_group <- function(x) {
  case_when(
    x == "No Macroscopic disease" ~ "R0",
    x == "1-10 mm" ~ "1-10 mm",
    x == "11-20 mm" ~ "11-20 mm",
    x == ">20 mm" ~ ">20 mm",
    TRUE ~ NA_character_
  )
}

expression_samples <- read_expression_samples(expression_path)

clinical_raw <- read.delim(
  clinical_path,
  sep = "\t",
  header = TRUE,
  check.names = FALSE,
  quote = "",
  na.strings = c("", "NA", "[Not Available]", "[Unknown]"),
  comment.char = ""
)

# Locate the real header instead of assuming a fixed offset. The frozen copy
# carries seven accidental R-code lines (the last fused to the header); the file
# currently served by the public Xena hub starts directly with the header.
survival_header_line <- grep(
  "sample\t_PATIENT",
  readLines(survival_path, n = 50L, warn = FALSE, encoding = "UTF-8"),
  fixed = TRUE
)[1]
if (is.na(survival_header_line)) {
  stop("Survival header (sample, _PATIENT) not found in ", survival_path)
}
survival_raw <- read.delim(
  survival_path,
  sep = "\t",
  header = TRUE,
  skip = survival_header_line - 1L,
  check.names = FALSE,
  quote = "",
  na.strings = c("", "NA", "[Not Available]", "[Unknown]", "[Discrepancy]"),
  comment.char = ""
)
names(survival_raw)[1] <- sub("^.*sample$", "sample", names(survival_raw)[1])
stopifnot(identical(names(survival_raw)[1:2], c("sample", "_PATIENT")))

clinical_primary <- clinical_raw %>%
  filter(sample_type == "Primary Tumor", sampleID %in% expression_samples) %>%
  transmute(
    sample = sampleID,
    patient_clinical = `_PATIENT`,
    response_clinical_raw = primary_therapy_outcome_success,
    age_clinical = suppressWarnings(as.numeric(age_at_initial_pathologic_diagnosis)),
    stage_clinical = clinical_stage,
    grade = neoplasm_histologic_grade,
    residual_raw = tumor_residual_disease,
    neoadjuvant = history_of_neoadjuvant_treatment,
    vital_status_clinical = vital_status,
    days_to_death_clinical = suppressWarnings(as.numeric(days_to_death)),
    days_to_last_followup_clinical = suppressWarnings(as.numeric(days_to_last_followup))
  )

survival_ov <- survival_raw %>%
  filter(`cancer type abbreviation` == "OV") %>%
  transmute(
    sample,
    patient_survival = `_PATIENT`,
    response_supp_raw = treatment_outcome_first_course,
    age_survival = suppressWarnings(as.numeric(age_at_initial_pathologic_diagnosis)),
    stage_survival = coalesce(clinical_stage, ajcc_pathologic_tumor_stage),
    OS_event = suppressWarnings(as.integer(OS)),
    OS_days = suppressWarnings(as.numeric(OS.time)),
    PFI_event = suppressWarnings(as.integer(PFI)),
    PFI_days = suppressWarnings(as.numeric(PFI.time))
  )

analysis_all <- clinical_primary %>%
  left_join(survival_ov, by = "sample") %>%
  mutate(
    patient = coalesce(patient_survival, patient_clinical),
    response4 = canonical_response(response_supp_raw),
    response_clinical = canonical_response(response_clinical_raw),
    response_conflict = !is.na(response4) & !is.na(response_clinical) & response4 != response_clinical,
    age = coalesce(age_survival, age_clinical),
    stage_raw = coalesce(stage_survival, stage_clinical),
    stage_group = stage_group(stage_raw),
    residual_group = residual_group(residual_raw),
    response4 = factor(response4, levels = analysis_config$response$four_levels),
    response_m2 = factor(if_else(response4 %in% c("CR", "PR"), "CR+PR", "SD+PD", missing = NA_character_),
                         levels = analysis_config$response$objective_response_levels),
    response_m3 = factor(if_else(response4 == "CR", "CR", "Non-CR", missing = NA_character_),
                         levels = analysis_config$response$cr_threshold_levels),
    stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
    residual_group = factor(residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm")),
    age_10y = age / 10,
    OS_months = OS_days / analysis_config$survival$days_per_month,
    PFI_months = PFI_days / analysis_config$survival$days_per_month
  ) %>%
  arrange(patient, sample)

if (anyDuplicated(analysis_all$patient)) {
  stop("Patient-level duplication remains after selecting expression-linked primary tumors.")
}

write_csv(analysis_all, file.path(processed_dir, "tcga_ov_phase0_clinical.csv"), na = "")

flow <- tibble(
  step = c(
    "OV clinical-matrix rows",
    "Primary-tumor clinical rows",
    "HT_HG-U133A expression samples",
    "Expression-linked primary tumors",
    "Canonical CR/PR/SD/PD available",
    "Response plus usable OS",
    "Response plus usable PFI",
    "Response plus OS and complete adjustment covariates"
  ),
  n = c(
    nrow(clinical_raw),
    sum(clinical_raw$sample_type == "Primary Tumor", na.rm = TRUE),
    length(expression_samples),
    nrow(analysis_all),
    sum(!is.na(analysis_all$response4)),
    sum(complete.cases(analysis_all[, c("response4", "OS_event", "OS_months")])),
    sum(complete.cases(analysis_all[, c("response4", "PFI_event", "PFI_months")])),
    sum(complete.cases(analysis_all[, c("response4", "OS_event", "OS_months", "age_10y", "stage_group", "residual_group")]))
  )
)
write_csv(flow, file.path(table_dir, "cohort_flow.csv"))

response_counts <- analysis_all %>%
  mutate(response = as.character(response4), response = if_else(is.na(response), "Missing/invalid", response)) %>%
  group_by(response) %>%
  summarise(
    n = n(),
    OS_usable = sum(!is.na(OS_event) & !is.na(OS_months)),
    OS_events = sum(OS_event == 1, na.rm = TRUE),
    PFI_usable = sum(!is.na(PFI_event) & !is.na(PFI_months)),
    PFI_events = sum(PFI_event == 1, na.rm = TRUE),
    .groups = "drop"
  )
write_csv(response_counts, file.path(table_dir, "response_counts.csv"))

missingness <- tibble(
  variable = c("response4", "OS", "PFI", "age", "stage_group", "residual_group", "grade", "neoadjuvant"),
  missing_n = c(
    sum(is.na(analysis_all$response4)),
    sum(is.na(analysis_all$OS_event) | is.na(analysis_all$OS_months)),
    sum(is.na(analysis_all$PFI_event) | is.na(analysis_all$PFI_months)),
    sum(is.na(analysis_all$age)),
    sum(is.na(analysis_all$stage_group)),
    sum(is.na(analysis_all$residual_group)),
    sum(is.na(analysis_all$grade) | analysis_all$grade == ""),
    sum(is.na(analysis_all$neoadjuvant) | analysis_all$neoadjuvant == "")
  )
) %>%
  mutate(total_n = nrow(analysis_all), missing_pct = 100 * missing_n / total_n)
write_csv(missingness, file.path(table_dir, "missingness.csv"))

label_crosswalk <- analysis_all %>%
  count(response_clinical_raw, response_supp_raw, response_clinical, response4, response_conflict, name = "n") %>%
  arrange(desc(response_conflict), response_clinical_raw, response_supp_raw)
write_csv(label_crosswalk, file.path(table_dir, "response_label_crosswalk.csv"), na = "")

baseline_continuous <- analysis_all %>%
  filter(!is.na(response4)) %>%
  group_by(response4) %>%
  summarise(
    n = n(),
    age_median = median(age, na.rm = TRUE),
    age_q1 = quantile(age, 0.25, na.rm = TRUE),
    age_q3 = quantile(age, 0.75, na.rm = TRUE),
    OS_events = sum(OS_event == 1, na.rm = TRUE),
    PFI_events = sum(PFI_event == 1, na.rm = TRUE),
    OS_followup_median_months = median(OS_months, na.rm = TRUE),
    PFI_followup_median_months = median(PFI_months, na.rm = TRUE),
    .groups = "drop"
  )
write_csv(baseline_continuous, file.path(table_dir, "baseline_continuous_by_response.csv"))

baseline_categorical <- bind_rows(
  analysis_all %>% filter(!is.na(response4)) %>% count(response4, variable = "stage_group", level = as.character(stage_group), name = "n"),
  analysis_all %>% filter(!is.na(response4)) %>% count(response4, variable = "residual_group", level = as.character(residual_group), name = "n"),
  analysis_all %>% filter(!is.na(response4)) %>% count(response4, variable = "grade", level = grade, name = "n"),
  analysis_all %>% filter(!is.na(response4)) %>% count(response4, variable = "neoadjuvant", level = neoadjuvant, name = "n")
) %>%
  group_by(response4, variable) %>%
  mutate(pct = 100 * n / sum(n)) %>%
  ungroup()
write_csv(baseline_categorical, file.path(table_dir, "baseline_categorical_by_response.csv"), na = "")

model_metrics <- function(fit, model_name, endpoint, adjusted, cv_cindex = NA_real_) {
  ll <- logLik(fit)
  tibble(
    endpoint = endpoint,
    adjusted = adjusted,
    model = model_name,
    n = fit$n,
    events = fit$nevent,
    parameters = attr(ll, "df"),
    log_likelihood = as.numeric(ll),
    AIC = AIC(fit),
    BIC = BIC(fit),
    apparent_cindex = unname(summary(fit)$concordance[1]),
    cv_cindex = cv_cindex
  )
}

nested_lrt <- function(reduced, full, endpoint, adjusted, hypothesis) {
  ll0 <- logLik(reduced)
  ll1 <- logLik(full)
  statistic <- 2 * (as.numeric(ll1) - as.numeric(ll0))
  df <- attr(ll1, "df") - attr(ll0, "df")
  tibble(
    endpoint = endpoint,
    adjusted = adjusted,
    hypothesis = hypothesis,
    chi_square = statistic,
    df = df,
    p_value = pchisq(statistic, df = df, lower.tail = FALSE)
  )
}

# Preserve phase-0 CV: random balanced folds, then concordance of the pooled
# out-of-fold linear predictors in each repeat. Do not substitute fold-weighted
# concordance here: that would change the historical estimand and output values.
cv_cindex <- function(
  data,
  formula,
  k = analysis_config$resampling$phase0_cross_validation_folds,
  repeats = analysis_config$resampling$phase0_cross_validation_repeats
) {
  values <- numeric(repeats)
  for (r in seq_len(repeats)) {
    folds <- sample(rep(seq_len(k), length.out = nrow(data)))
    lp <- rep(NA_real_, nrow(data))
    for (fold in seq_len(k)) {
      train <- data[folds != fold, , drop = FALSE]
      test <- data[folds == fold, , drop = FALSE]
      fit <- coxph(formula, data = train, ties = "efron", x = TRUE)
      lp[folds == fold] <- predict(fit, newdata = test, type = "lp", reference = "sample")
    }
    cc <- survival::concordance(Surv(time, event) ~ lp, data = transform(data, lp = lp), reverse = TRUE)
    values[r] <- unname(cc$concordance)
  }
  c(mean = mean(values, na.rm = TRUE), sd = sd(values, na.rm = TRUE))
}

fit_model_set <- function(data, time_col, event_col, endpoint, adjusted = FALSE) {
  required <- c(time_col, event_col, "response4", "response_m2", "response_m3")
  covariates <- if (adjusted) c("age_10y", "stage_group", "residual_group") else character()
  dat <- data[complete.cases(data[, c(required, covariates)]), , drop = FALSE]
  dat$time <- dat[[time_col]]
  dat$event <- dat[[event_col]]

  rhs_cov <- if (adjusted) " + age_10y + stage_group + residual_group" else ""
  f1 <- as.formula(paste0("Surv(time, event) ~ response4", rhs_cov))
  f2 <- as.formula(paste0("Surv(time, event) ~ response_m2", rhs_cov))
  f3 <- as.formula(paste0("Surv(time, event) ~ response_m3", rhs_cov))

  m1 <- coxph(f1, data = dat, ties = "efron", x = TRUE, model = TRUE)
  m2 <- coxph(f2, data = dat, ties = "efron", x = TRUE, model = TRUE)
  m3 <- coxph(f3, data = dat, ties = "efron", x = TRUE, model = TRUE)

  cv1 <- cv_cindex(dat, f1)
  cv2 <- cv_cindex(dat, f2)
  cv3 <- cv_cindex(dat, f3)

  metrics <- bind_rows(
    model_metrics(m1, "M1: CR/PR/SD/PD", endpoint, adjusted, cv1["mean"]),
    model_metrics(m2, "M2: CR+PR vs SD+PD", endpoint, adjusted, cv2["mean"]),
    model_metrics(m3, "M3: CR vs Non-CR", endpoint, adjusted, cv3["mean"])
  ) %>%
    mutate(cv_cindex_sd = c(cv1["sd"], cv2["sd"], cv3["sd"]))

  tests <- bind_rows(
    nested_lrt(m3, m1, endpoint, adjusted, "Plateau constraint: beta_PR = beta_SD = beta_PD"),
    nested_lrt(m2, m1, endpoint, adjusted, "ORR constraint: beta_CR = beta_PR and beta_SD = beta_PD")
  )

  ph <- bind_rows(
    as.data.frame(cox.zph(m1)$table) %>% tibble::rownames_to_column("term") %>% mutate(model = "M1"),
    as.data.frame(cox.zph(m2)$table) %>% tibble::rownames_to_column("term") %>% mutate(model = "M2"),
    as.data.frame(cox.zph(m3)$table) %>% tibble::rownames_to_column("term") %>% mutate(model = "M3")
  ) %>% mutate(endpoint = endpoint, adjusted = adjusted)

  list(data = dat, models = list(M1 = m1, M2 = m2, M3 = m3), metrics = metrics, tests = tests, ph = ph)
}

pairwise_response <- function(data, time_col, event_col, endpoint,
                              conf_level = as.double(analysis_config$survival$confidence_level)) {
  pairs <- combn(c("CR", "PR", "SD", "PD"), 2, simplify = FALSE)
  bind_rows(lapply(pairs, function(pair) {
    dat <- data %>%
      filter(as.character(response4) %in% pair) %>%
      filter(complete.cases(.data[[time_col]], .data[[event_col]])) %>%
      mutate(group = factor(as.character(response4), levels = pair), time = .data[[time_col]], event = .data[[event_col]])
    fit <- coxph(Surv(time, event) ~ group, data = dat)
    cf <- coef(fit)[1]
    se <- sqrt(vcov(fit)[1, 1])
    z <- qnorm(1 - (1 - conf_level) / 2)
    lr <- survdiff(Surv(time, event) ~ group, data = dat)
    tibble(
      endpoint = endpoint,
      comparison = paste(pair[2], "vs", pair[1]),
      reference = pair[1],
      n = nrow(dat),
      events = sum(dat$event),
      HR = exp(cf),
      CI_low = exp(cf - z * se),
      CI_high = exp(cf + z * se),
      cox_p = summary(fit)$coefficients[1, "Pr(>|z|)"],
      logrank_p = pchisq(lr$chisq, df = length(lr$n) - 1, lower.tail = FALSE)
    )
  }))
}

noncr_equivalence <- function(
  data,
  time_col,
  event_col,
  endpoint,
  lower = analysis_config$response$equivalence_margin[[1]],
  upper = analysis_config$response$equivalence_margin[[2]]
) {
  pairs <- list(c("PR", "SD"), c("PR", "PD"), c("SD", "PD"))
  bind_rows(lapply(pairs, function(pair) {
    dat <- data %>%
      filter(as.character(response4) %in% pair) %>%
      filter(complete.cases(.data[[time_col]], .data[[event_col]])) %>%
      mutate(group = factor(as.character(response4), levels = pair), time = .data[[time_col]], event = .data[[event_col]])
    fit <- coxph(Surv(time, event) ~ group, data = dat)
    cf <- coef(fit)[1]
    se <- sqrt(vcov(fit)[1, 1])
    z90 <- qnorm(0.95)
    lo <- exp(cf - z90 * se)
    hi <- exp(cf + z90 * se)
    tibble(
      endpoint = endpoint,
      comparison = paste(pair[2], "vs", pair[1]),
      equivalence_margin_low = lower,
      equivalence_margin_high = upper,
      HR = exp(cf),
      CI90_low = lo,
      CI90_high = hi,
      equivalent = lo > lower & hi < upper
    )
  }))
}

bootstrap_topology <- function(
  data,
  time_col,
  event_col,
  endpoint,
  adjusted = FALSE,
  B = analysis_config$resampling$bootstrap_replicates
) {
  required <- c(time_col, event_col, "response4", "response_m2", "response_m3")
  covariates <- if (adjusted) c("age_10y", "stage_group", "residual_group") else character()
  dat <- data[complete.cases(data[, c(required, covariates)]), , drop = FALSE]
  dat$time <- dat[[time_col]]
  dat$event <- dat[[event_col]]
  rhs_cov <- if (adjusted) " + age_10y + stage_group + residual_group" else ""
  f1 <- as.formula(paste0("Surv(time, event) ~ response4", rhs_cov))
  f2 <- as.formula(paste0("Surv(time, event) ~ response_m2", rhs_cov))
  f3 <- as.formula(paste0("Surv(time, event) ~ response_m3", rhs_cov))

  out <- vector("list", B)
  for (b in seq_len(B)) {
    boot <- dat[sample.int(nrow(dat), replace = TRUE), , drop = FALSE]
    fits <- tryCatch({
      m1 <- coxph(f1, data = boot, ties = "efron")
      m2 <- coxph(f2, data = boot, ties = "efron")
      m3 <- coxph(f3, data = boot, ties = "efron")
      lrt <- 2 * (as.numeric(logLik(m1)) - as.numeric(logLik(m3)))
      tibble(
        iteration = b,
        delta_AIC_M1_minus_M3 = AIC(m1) - AIC(m3),
        delta_AIC_M2_minus_M3 = AIC(m2) - AIC(m3),
        plateau_LRT_p = pchisq(lrt, df = 2, lower.tail = FALSE),
        best_AIC_model = c("M1", "M2", "M3")[which.min(c(AIC(m1), AIC(m2), AIC(m3)))]
      )
    }, error = function(e) NULL)
    out[[b]] <- fits
  }
  bind_rows(out) %>% mutate(endpoint = endpoint, adjusted = adjusted)
}

plot_km <- function(data, time_col, event_col, endpoint) {
  dat <- data %>%
    filter(!is.na(response4), !is.na(.data[[time_col]]), !is.na(.data[[event_col]])) %>%
    mutate(time = .data[[time_col]], event = .data[[event_col]])
  fit <- survfit(Surv(time, event) ~ response4, data = dat)
  p <- ggsurvplot(
    fit,
    data = dat,
    risk.table = TRUE,
    pval = TRUE,
    conf.int = FALSE,
    xlab = paste0(endpoint, " time (months)"),
    ylab = paste0(endpoint, " probability"),
    legend.title = "Response",
    legend.labs = levels(droplevels(dat$response4)),
    palette = c("#2166AC", "#67A9CF", "#FDAE61", "#B2182B"),
    ggtheme = theme_bw(base_size = 11),
    risk.table.height = 0.25
  )
  png(file.path(figure_dir, paste0("KM_", endpoint, "_M1.png")), width = 1800, height = 1500, res = 180)
  print(p)
  dev.off()
  pdf(file.path(figure_dir, paste0("KM_", endpoint, "_M1.pdf")), width = 9, height = 7.5)
  print(p)
  dev.off()
}

os_unadj <- fit_model_set(analysis_all, "OS_months", "OS_event", "OS", adjusted = FALSE)
os_adj <- fit_model_set(analysis_all, "OS_months", "OS_event", "OS", adjusted = TRUE)
pfi_unadj <- fit_model_set(analysis_all, "PFI_months", "PFI_event", "PFI", adjusted = FALSE)
pfi_adj <- fit_model_set(analysis_all, "PFI_months", "PFI_event", "PFI", adjusted = TRUE)

write_csv(bind_rows(os_unadj$metrics, os_adj$metrics, pfi_unadj$metrics, pfi_adj$metrics), file.path(table_dir, "model_comparison.csv"))
write_csv(bind_rows(os_unadj$tests, os_adj$tests, pfi_unadj$tests, pfi_adj$tests), file.path(table_dir, "nested_model_tests.csv"))
write_csv(bind_rows(os_unadj$ph, os_adj$ph, pfi_unadj$ph, pfi_adj$ph), file.path(table_dir, "proportional_hazards_tests.csv"))

pairwise <- bind_rows(
  pairwise_response(analysis_all, "OS_months", "OS_event", "OS"),
  pairwise_response(analysis_all, "PFI_months", "PFI_event", "PFI")
)
write_csv(pairwise, file.path(table_dir, "pairwise_response_comparisons.csv"))

equivalence <- bind_rows(
  noncr_equivalence(analysis_all, "OS_months", "OS_event", "OS"),
  noncr_equivalence(analysis_all, "PFI_months", "PFI_event", "PFI")
)
write_csv(equivalence, file.path(table_dir, "noncr_equivalence_tests.csv"))

coef_table <- function(fit, endpoint, adjusted, model) {
  s <- summary(fit)$coefficients
  ci <- summary(fit)$conf.int
  tibble(
    endpoint = endpoint,
    adjusted = adjusted,
    model = model,
    term = rownames(s),
    coefficient = s[, "coef"],
    HR = ci[, "exp(coef)"],
    CI_low = ci[, "lower .95"],
    CI_high = ci[, "upper .95"],
    p_value = s[, "Pr(>|z|)"]
  )
}

coefs <- bind_rows(
  coef_table(os_unadj$models$M1, "OS", FALSE, "M1"),
  coef_table(os_unadj$models$M2, "OS", FALSE, "M2"),
  coef_table(os_unadj$models$M3, "OS", FALSE, "M3"),
  coef_table(os_adj$models$M1, "OS", TRUE, "M1"),
  coef_table(os_adj$models$M2, "OS", TRUE, "M2"),
  coef_table(os_adj$models$M3, "OS", TRUE, "M3"),
  coef_table(pfi_unadj$models$M1, "PFI", FALSE, "M1"),
  coef_table(pfi_unadj$models$M2, "PFI", FALSE, "M2"),
  coef_table(pfi_unadj$models$M3, "PFI", FALSE, "M3"),
  coef_table(pfi_adj$models$M1, "PFI", TRUE, "M1"),
  coef_table(pfi_adj$models$M2, "PFI", TRUE, "M2"),
  coef_table(pfi_adj$models$M3, "PFI", TRUE, "M3")
)
write_csv(coefs, file.path(table_dir, "cox_coefficients.csv"))

boot <- bind_rows(
  bootstrap_topology(analysis_all, "OS_months", "OS_event", "OS", adjusted = FALSE),
  bootstrap_topology(analysis_all, "OS_months", "OS_event", "OS", adjusted = TRUE),
  bootstrap_topology(analysis_all, "PFI_months", "PFI_event", "PFI", adjusted = FALSE),
  bootstrap_topology(analysis_all, "PFI_months", "PFI_event", "PFI", adjusted = TRUE)
)
write_csv(boot, file.path(table_dir, "bootstrap_model_stability.csv"))

boot_summary <- boot %>%
  group_by(endpoint, adjusted) %>%
  summarise(
    successful_iterations = n(),
    M1_best_AIC_pct = 100 * mean(best_AIC_model == "M1"),
    M2_best_AIC_pct = 100 * mean(best_AIC_model == "M2"),
    M3_best_AIC_pct = 100 * mean(best_AIC_model == "M3"),
    plateau_rejected_p_lt_0_05_pct = 100 * mean(plateau_LRT_p < analysis_config$survival$alpha),
    delta_AIC_M1_minus_M3_median = median(delta_AIC_M1_minus_M3),
    delta_AIC_M1_minus_M3_q1 = quantile(delta_AIC_M1_minus_M3, 0.25),
    delta_AIC_M1_minus_M3_q3 = quantile(delta_AIC_M1_minus_M3, 0.75),
    .groups = "drop"
  )
write_csv(boot_summary, file.path(table_dir, "bootstrap_model_stability_summary.csv"))

plot_km(analysis_all, "OS_months", "OS_event", "OS")
plot_km(analysis_all, "PFI_months", "PFI_event", "PFI")

# Sensitivity analysis excluding the single cross-source response conflict.
conflict_sensitivity <- analysis_all %>% filter(!response_conflict)
os_no_conflict <- fit_model_set(conflict_sensitivity, "OS_months", "OS_event", "OS", adjusted = FALSE)
pfi_no_conflict <- fit_model_set(conflict_sensitivity, "PFI_months", "PFI_event", "PFI", adjusted = FALSE)
write_csv(
  bind_rows(os_no_conflict$metrics, pfi_no_conflict$metrics) %>% mutate(sensitivity = "exclude_cross_source_response_conflict"),
  file.path(table_dir, "sensitivity_exclude_response_conflict.csv")
)

capture.output(sessionInfo(), file = file.path(project_dir, "logs", "sessionInfo.txt"))
writeLines(
  c(
    paste("Analysis completed:", format(Sys.time(), tz = "UTC")),
    paste("Clinical source:", clinical_path),
    paste("Survival source:", survival_path),
    paste("Expression source:", expression_path),
    paste("Expression-linked primary tumors:", nrow(analysis_all)),
    paste("Canonical response available:", sum(!is.na(analysis_all$response4))),
    paste("Cross-source response conflicts:", sum(analysis_all$response_conflict, na.rm = TRUE)),
    "Response-assessment dates are unavailable; survival analyses are associative and susceptible to guarantee-time bias."
  ),
  con = file.path(project_dir, "logs", "phase0_run_summary.txt")
)

# ---- Analysis workflow --------------------------------------------------------
message("Phase 0 clinical audit completed successfully.")
