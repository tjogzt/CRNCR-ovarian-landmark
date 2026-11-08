#!/usr/bin/env Rscript

# ==============================================================================
# File: 15_audit_pancancer_labels.R
# Purpose: Audit first-course response semantics and treatment evidence across TCGA cancers.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - TCGA-CDR response data, GDC treatment records, and Xena clinical matrices.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; cohort treatment_type_groups,
#     first_line_start_window_days and regimen_join_window_days;
#     pancancer state/sample/event/treatment-fraction and label-agreement checks.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Pan-cancer label-semantics audit and eligibility table.
# Reproducibility:
#   - First-course/regimen label recognition and modal-outcome tie order stay fixed.
#   - Deterministic audit; systemic/radiation categories retain their original order.
# ==============================================================================

# Pan-cancer step 1b: semantic audit of first-course response labels.
#
# Pre-specified eligibility for the topology analysis (step 2):
#   E1 (power): PR >= 10, SD >= 10, PD >= 10, non-CR >= 30, OS events >= 30.
#   E2 (therapy-defined response): >= 50% of labelled patients received
#       first-line systemic therapy or radiation that started within 365 days
#       of diagnosis (GDC treatment records, primary diagnosis).
#   E3 (not a resection label): reported, not used to exclude; where residual
#       tumor is recorded, step 2 adjusts for / restricts to R0 status.
# Labels: TCGA-CDR treatment_outcome_first_course (primary). Regimen-level
# GDC treatment_outcome for first-line systemic therapy is audited as a
# secondary, therapy-specific label.

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr)
})

# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)
analysis_config <- config$analysis
seed <- analysis_config$random_seeds$default
configure_reproducible_runtime(seed, threads = 1L)
start_window <- analysis_config$cohort$first_line_start_window_days
regimen_join_window <- analysis_config$cohort$regimen_join_window_days
pancancer_rules <- analysis_config$pancancer
treatment_type_groups <- required_analysis_value(analysis_config, "cohort.treatment_type_groups")
if (!is.list(treatment_type_groups) || !identical(names(treatment_type_groups), c("systemic", "radiation"))) {
  stop("cohort.treatment_type_groups must contain ordered systemic and radiation groups.")
}
for (group in names(treatment_type_groups)) {
  types <- unlist(treatment_type_groups[[group]], use.names = FALSE)
  if (!is.character(types) || !length(types) || anyNA(types) || any(!nzchar(types)) || anyDuplicated(types)) {
    stop("Invalid treatment type vector: cohort.treatment_type_groups.", group)
  }
  treatment_type_groups[[group]] <- types
}
minimum_regimen_agreement_samples <- required_analysis_value(
  analysis_config, "pancancer.minimum_regimen_agreement_samples"
)
if (!is.numeric(minimum_regimen_agreement_samples) || length(minimum_regimen_agreement_samples) != 1L ||
    !is.finite(minimum_regimen_agreement_samples) || minimum_regimen_agreement_samples < 1 ||
    minimum_regimen_agreement_samples != floor(minimum_regimen_agreement_samples)) {
  stop("pancancer.minimum_regimen_agreement_samples must be a positive integer.")
}
processed_dir <- config$paths$processed_data_dir
out_tab <- file.path(config$paths$results_dir, "tables", "pancancer_topology")
dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)

cdr_path <- file.path(config$paths$xena_dir, "Survival_SupplementalTable_S1_20171025_xena_sp")
require_input_files(c(cdr_path, file.path(processed_dir, "gdc_tcga_treatment_records.csv")),
                    "CDR and script-01 treatment records")
txt <- readLines(cdr_path, encoding = "UTF-8", warn = FALSE)
# The local file carries a pasted R-code preamble; the header is the line that
# contains "sample\t_PATIENT" (possibly prefixed by stray text).
hdr <- grep("sample\t_PATIENT", txt, fixed = TRUE)[1]
if (is.na(hdr)) stop("CDR header (sample, _PATIENT) not found in ", cdr_path)
txt[hdr] <- sub("^.*?(sample\t_PATIENT)", "\\1", txt[hdr])
cdr <- read_tsv(I(paste(txt[hdr:length(txt)], collapse = "\n")), show_col_types = FALSE,
                col_types = cols(.default = "c"), na = c("", "NA", "#N/A", "[Not Available]",
                "[Not Applicable]", "[Unknown]", "[Discrepancy]", "[Not Evaluated]"))
recode4 <- function(x) recode(x, "Complete Remission/Response" = "CR", "Complete Response" = "CR",
  "Partial Remission/Response" = "PR", "Partial Response" = "PR", "Stable Disease" = "SD",
  "Progressive Disease" = "PD", .default = NA_character_)
cdr <- cdr %>% filter(str_sub(sample, 14, 15) %in% c("01", "03")) %>%
  distinct(`_PATIENT`, .keep_all = TRUE) %>%
  transmute(patient = `_PATIENT`, cancer = `cancer type abbreviation`,
    response4 = recode4(treatment_outcome_first_course),
    residual_tumor, stage = ajcc_pathologic_tumor_stage, clinical_stage, grade = histological_grade,
    age = as.numeric(age_at_initial_pathologic_diagnosis),
    OS = as.integer(OS), OS_days = as.numeric(OS.time),
    PFI = as.integer(PFI), PFI_days = as.numeric(PFI.time))

trt <- read_csv(file.path(processed_dir, "gdc_tcga_treatment_records.csv"),
                show_col_types = FALSE, guess_max = 60000)
systemic_types <- treatment_type_groups$systemic
radiation_types <- treatment_type_groups$radiation
prim <- trt %>% filter(classification_of_tumor == "primary", given == "yes")

# First-line systemic regimen: earliest dated systemic record starting in
# [-120, 365] days; agents starting within 42 days of it form the regimen.
sys <- prim %>% filter(
  treatment_type %in% systemic_types,
  is.finite(start),
  start >= start_window[1],
  start <= start_window[2]
)
# Earliest dated systemic start anchors the regimen window. Modal response ties
# retain table()/sort() ordering, not a new clinical severity rule. An all-missing
# treatment end is converted from -Inf to NA only after the existing aggregation.
first_line <- sys %>% group_by(patient) %>% mutate(s0 = min(start)) %>%
  filter(start <= s0 + regimen_join_window) %>%
  summarise(fl_start = first(s0), fl_end = suppressWarnings(max(end, na.rm = TRUE)),
    fl_agents = paste(sort(unique(na.omit(agents))), collapse = ";"),
    fl_types = paste(sort(unique(treatment_type)), collapse = ";"),
    fl_outcome = {o <- recode4(treatment_outcome); o <- o[!is.na(o)]
      if (length(o)) names(sort(table(o), decreasing = TRUE))[1] else NA_character_},
    .groups = "drop") %>%
  mutate(fl_end = ifelse(is.finite(fl_end), fl_end, NA_real_),
         fl_platinum = str_detect(fl_agents, regex("platin", ignore_case = TRUE)))
rad <- prim %>% filter(
  treatment_type %in% radiation_types,
  is.finite(start),
  start >= start_window[1],
  start <= start_window[2]
) %>%
  group_by(patient) %>% summarise(rt_start = min(start), rt_end = suppressWarnings(max(end, na.rm = TRUE)),
    rt_outcome = {o <- recode4(treatment_outcome); o <- o[!is.na(o)]
      if (length(o)) names(sort(table(o), decreasing = TRUE))[1] else NA_character_}, .groups = "drop") %>%
  mutate(rt_end = ifelse(is.finite(rt_end), rt_end, NA_real_))
surg <- prim %>% filter(str_detect(treatment_type, regex("Surgery|ectomy|Whipple|Resection", ignore_case = TRUE))) %>%
  distinct(patient) %>% mutate(any_surgery_record = TRUE)

pt <- cdr %>% left_join(first_line, by = "patient") %>% left_join(rad, by = "patient") %>%
  left_join(surg, by = "patient") %>%
  mutate(first_line_systemic = !is.na(fl_start), first_line_radiation = !is.na(rt_start),
    nonsurgical_primary = first_line_systemic | first_line_radiation,
    R0 = case_when(residual_tumor == "R0" ~ TRUE, residual_tumor %in% c("R1", "R2") ~ FALSE),
    any_surgery_record = coalesce(any_surgery_record, FALSE),
    # End of first-line non-surgical therapy (systemic or radiation), used for
    # a patient-specific landmark in step 2.
    therapy_end = pmax(coalesce(fl_end, -Inf), coalesce(rt_end, -Inf)),
    therapy_end = ifelse(is.finite(therapy_end), therapy_end, NA_real_))
write_csv(pt, file.path(processed_dir, "pancancer_patient_response_treatment.csv"))

lab <- pt %>% filter(!is.na(response4))
audit <- lab %>% group_by(cancer) %>% summarise(
  n = n(), CR = sum(response4 == "CR"), PR = sum(response4 == "PR"), SD = sum(response4 == "SD"),
  PD = sum(response4 == "PD"), non_CR = n - CR, OS_events = sum(OS, na.rm = TRUE),
  pct_first_line_systemic = mean(first_line_systemic), pct_first_line_platinum = mean(fl_platinum %in% TRUE),
  pct_first_line_radiation = mean(first_line_radiation), pct_nonsurgical = mean(nonsurgical_primary),
  pct_therapy_end_known = mean(!is.na(therapy_end)),
  median_therapy_end_days = median(therapy_end, na.rm = TRUE),
  residual_recorded = sum(!is.na(R0)),
  pct_R0_CR = mean(R0[response4 == "CR"], na.rm = TRUE), pct_R0_nonCR = mean(R0[response4 != "CR"], na.rm = TRUE),
  regimen_label_n = sum(!is.na(coalesce(fl_outcome, rt_outcome))),
  regimen_CR_agreement = {r <- coalesce(fl_outcome, rt_outcome); ok <- !is.na(r)
    if (sum(ok) >= minimum_regimen_agreement_samples) mean((r[ok] == "CR") == (response4[ok] == "CR")) else NA_real_},
  .groups = "drop") %>%
  mutate(E1_power = PR >= pancancer_rules$minimum_per_noncr_state &
           SD >= pancancer_rules$minimum_per_noncr_state &
           PD >= pancancer_rules$minimum_per_noncr_state &
           non_CR >= pancancer_rules$minimum_noncr &
           OS_events >= pancancer_rules$minimum_os_events,
         E2_therapy_defined = pct_nonsurgical >= pancancer_rules$minimum_treatment_fraction,
         R0_gap = pct_R0_CR - pct_R0_nonCR,
         eligible = E1_power & E2_therapy_defined) %>% arrange(desc(n))
write_csv(audit, file.path(out_tab, "label_semantics_audit_by_cancer.csv"))

# Secondary therapy-specific label: first-line systemic regimen outcome.
reg <- pt %>% filter(!is.na(fl_outcome)) %>% count(cancer, fl_outcome) %>%
  pivot_wider(names_from = fl_outcome, values_from = n, values_fill = 0)
for (k in c("CR", "PR", "SD", "PD")) if (!k %in% names(reg)) reg[[k]] <- 0L
reg <- reg %>% mutate(n = CR + PR + SD + PD,
  E1_regimen = PR >= pancancer_rules$minimum_per_noncr_state &
    SD >= pancancer_rules$minimum_per_noncr_state &
    PD >= pancancer_rules$minimum_per_noncr_state &
    (n - CR) >= pancancer_rules$minimum_noncr) %>%
  select(cancer, n, CR, PR, SD, PD, E1_regimen) %>% arrange(desc(n))
write_csv(reg, file.path(out_tab, "first_line_regimen_outcome_counts.csv"))

conc <- pt %>% filter(!is.na(response4), !is.na(fl_outcome)) %>% count(cancer, response4, fl_outcome)
write_csv(conc, file.path(out_tab, "first_course_vs_regimen_outcome_crosstab.csv"))

options(width = 250)

# Resection semantics: residual tumor (R0) by response, from the per-cancer
# Xena clinical matrices (CDR residual_tumor is sparse for labelled cases).
xena_cm <- file.path(config$paths$xena_dir, "clinical_matrices")
if (!dir.exists(xena_cm)) stop("Missing Xena clinical-matrix directory: ", xena_cm)
clinical_matrix_files <- list.files(xena_cm, pattern = "_clinicalMatrix$", full.names = TRUE)
if (!length(clinical_matrix_files)) stop("No Xena clinical matrices found in ", xena_cm)
r0_rows <- list()
for (f in clinical_matrix_files) {
  cm <- read_tsv(f, show_col_types = FALSE, col_types = cols(.default = "c"))
  if (!all(c("residual_tumor", "primary_therapy_outcome_success") %in% names(cm))) next
  cm <- cm %>% filter(str_sub(sampleID, 14, 15) == "01") %>% distinct(`_PATIENT`, .keep_all = TRUE) %>%
    mutate(r = recode4(primary_therapy_outcome_success), R0 = case_when(residual_tumor == "R0" ~ TRUE,
      residual_tumor %in% c("R1", "R2") ~ FALSE)) %>% filter(!is.na(r), !is.na(R0))
  r0_rows[[f]] <- tibble(cancer = str_remove(basename(f), "_clinicalMatrix"), n_with_residual = nrow(cm),
    pct_R0_CR = mean(cm$R0[cm$r == "CR"]), pct_R0_nonCR = mean(cm$R0[cm$r != "CR"]))
}
r0_tab <- bind_rows(r0_rows) %>% mutate(R0_gap = pct_R0_CR - pct_R0_nonCR)
write_csv(r0_tab, file.path(out_tab, "residual_R0_by_response_xena.csv"))
cat("\nR0 by response (Xena clinical matrices):\n"); print(as.data.frame(r0_tab))
print(as.data.frame(audit %>% mutate(across(where(is.numeric), ~ round(.x, 2)))))
cat("\nRegimen-level labels:\n"); print(as.data.frame(reg))
cat("\nEligible (E1 & E2):", paste(audit$cancer[audit$eligible], collapse = ", "), "\n")
