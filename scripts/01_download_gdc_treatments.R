#!/usr/bin/env Rscript

# ==============================================================================
# File: 01_download_gdc_treatments.R
# Purpose: Download TCGA treatment records from the NCI Genomic Data Commons API.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - GDC public API and configuration values for pagination and timeout.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; api URLs, GDC program, pagination,
#     retry/backoff, timeout, cache-size and expected-patient checks.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
#   - CRNCR_OFFLINE_RAW: require cached pages instead of making GDC requests.
# Outputs:
#   - Cached GDC JSON pages and a harmonized pan-cancer treatment table.
# Reproducibility:
#   - Reuses cached raw pages; API field names and output columns are fixed schema.
#   - Configures the project RNG, but performs no statistical resampling.
# ==============================================================================

# Pan-cancer step 1a: download GDC treatment records for all TCGA projects.
# Read-only GDC API (https://api.gdc.cancer.gov/cases). Raw JSON pages are
# cached under data/external/gdc_tcga_treatments/ and flattened to one row per
# treatment record. Re-running reuses cached pages.

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(jsonlite)
  library(curl)
  library(dplyr)
  library(purrr)
  library(readr)
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
api_config <- analysis_config$api
gdc_program <- required_analysis_value(analysis_config, "api.gdc_program")
if (!is.character(gdc_program) || length(gdc_program) != 1L || is.na(gdc_program) || !nzchar(gdc_program)) {
  stop("api.gdc_program must be a non-empty source identifier.")
}
raw_dir <- file.path(config$paths$external_data_dir, "gdc_tcga_treatments")
processed_dir <- config$paths$processed_data_dir
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

fields <- c("submitter_id", "project.project_id",
  "diagnoses.submitter_id", "diagnoses.classification_of_tumor",
  "diagnoses.diagnosis_is_primary_disease",
  paste0("diagnoses.treatments.", c("submitter_id", "treatment_type", "treatment_outcome",
    "therapeutic_agents", "days_to_treatment_start", "days_to_treatment_end",
    "treatment_or_therapy", "treatment_intent_type", "regimen_or_line_of_therapy",
    "number_of_cycles", "initial_disease_status")))

# Retry read-only POST queries with the existing linear backoff. Successful raw
# responses are cached by page offset, so retries never alter treatment flattening.
gdc_post <- function(body, tries = api_config$maximum_attempts) {
  for (i in seq_len(tries)) {
    h <- new_handle()
    handle_setheaders(h, "Content-Type" = "application/json")
    handle_setopt(
      h,
      postfields = toJSON(body, auto_unbox = TRUE),
      timeout = api_config$timeout_seconds
    )
    res <- tryCatch(curl_fetch_memory(api_config$gdc_cases_url, handle = h),
                    error = function(e) NULL)
    if (!is.null(res) && res$status_code == 200) return(rawToChar(res$content))
    Sys.sleep(api_config$retry_backoff_seconds * i)
  }
  stop("GDC request failed after retries")
}

filt <- list(op = "=", content = list(field = "project.program.name", value = gdc_program))
page_size <- api_config$gdc_page_size
offline_raw <- tolower(Sys.getenv("CRNCR_OFFLINE_RAW", unset = "false")) %in%
  c("1", "true", "yes")
cached_pages <- sort(list.files(raw_dir, pattern = "^cases_from_.*json$", full.names = TRUE))
if (offline_raw) {
  if (!length(cached_pages)) stop("No cached GDC JSON pages are available in offline mode.")
  require_input_files(cached_pages, "cached GDC JSON")
  first <- fromJSON(cached_pages[[1]], simplifyVector = FALSE)
  total <- first$data$pagination$total
} else {
  first <- fromJSON(gdc_post(list(filters = filt, fields = paste(fields, collapse = ","),
    size = 1, format = "JSON")), simplifyVector = FALSE)
  total <- first$data$pagination$total
}
if (!is.numeric(total) || length(total) != 1L || !is.finite(total) || total < 1 || total != floor(total)) {
  stop("GDC response lacks a positive integer data.pagination.total.")
}
# ---- Analysis workflow --------------------------------------------------------
message("TCGA cases: ", total)

pages <- seq(0, total - 1, by = page_size)
for (from in pages) {
  f <- file.path(raw_dir, sprintf("cases_from_%05d.json", from))
  if (file.exists(f) && file.size(f) > api_config$minimum_cache_bytes) next
  if (offline_raw) stop("Missing cached GDC page in offline mode: ", basename(f))
  txt <- gdc_post(list(filters = filt, fields = paste(fields, collapse = ","),
    size = page_size, from = from, sort = "submitter_id:asc", format = "JSON"))
  writeLines(txt, f)
  message("saved ", basename(f))
}

g <- function(x, k) if (is.null(x[[k]])) NA else as.character(x[[k]])
rows <- list()
for (f in list.files(raw_dir, pattern = "^cases_from_.*json$", full.names = TRUE)) {
  hits <- fromJSON(f, simplifyVector = FALSE)$data$hits
  for (h in hits) {
    proj <- h$project$project_id
    for (dg in h$diagnoses %||% list()) {
      tr <- dg$treatments %||% list()
      if (!length(tr)) next
      rows[[length(rows) + 1]] <- bind_rows(lapply(tr, function(t) tibble(
        patient = h$submitter_id, project = proj,
        diagnosis_id = g(dg, "submitter_id"), classification_of_tumor = g(dg, "classification_of_tumor"),
        diagnosis_is_primary = g(dg, "diagnosis_is_primary_disease"),
        treatment_id = g(t, "submitter_id"), treatment_type = g(t, "treatment_type"),
        treatment_outcome = g(t, "treatment_outcome"), agents = g(t, "therapeutic_agents"),
        start = suppressWarnings(as.numeric(g(t, "days_to_treatment_start"))),
        end = suppressWarnings(as.numeric(g(t, "days_to_treatment_end"))),
        given = g(t, "treatment_or_therapy"), intent = g(t, "treatment_intent_type"),
        line = g(t, "regimen_or_line_of_therapy"),
        cycles = suppressWarnings(as.numeric(g(t, "number_of_cycles"))),
        initial_disease_status = g(t, "initial_disease_status"))))
    }
  }
}
trt <- bind_rows(rows)
stopifnot(n_distinct(trt$patient) > api_config$minimum_expected_patients)
write_csv(trt, file.path(processed_dir, "gdc_tcga_treatment_records.csv"))
writeLines(c(paste("GDC download:", format(Sys.time())), paste("cases:", total),
  paste("treatment records:", nrow(trt)), paste("patients with records:", n_distinct(trt$patient))),
  file.path(raw_dir, "download_log.txt"))
message("Treatment records: ", nrow(trt), "; patients: ", n_distinct(trt$patient))
