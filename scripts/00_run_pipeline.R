#!/usr/bin/env Rscript

# ==============================================================================
# File: 00_run_pipeline.R
# Purpose: Execute the reproducible analysis workflow in dependency order.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - config/workflow.json and its ordered numbered scripts in scripts/.
#   - Source data paths configured through config/paths.yml or environment variables.
# Runtime parameters:
#   - Optional --start=NN and --stop=NN command-line arguments.
# Outputs:
#   - Outputs declared by each executed analysis script.
#   - A non-zero exit status if any workflow stage fails.
# ==============================================================================

# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)

# The ordered stage manifest is versioned beside scientific settings. Keep the
# existing numbered names: renumbering independent estimands breaks provenance.
manifest_file <- file.path(project_dir, "config", "workflow.json")
if (!file.exists(manifest_file)) stop("Missing workflow configuration: ", manifest_file)
workflow <- jsonlite::read_json(manifest_file, simplifyVector = TRUE)$analysis_stages
if (!is.character(workflow) || !length(workflow) || anyNA(workflow) ||
    anyDuplicated(workflow) || any(!grepl("^[0-9]{2}_[a-z0-9_]+[.]R$", workflow))) {
  stop("analysis_stages must be a nonempty ordered vector of unique numbered R filenames.")
}
if (!identical(as.integer(substr(workflow, 1, 2)), seq_along(workflow))) {
  stop("Workflow stage numbers must match their configured execution order.")
}

# Parse inclusive stage limits while retaining deterministic workflow order.
args <- commandArgs(trailingOnly = TRUE)
read_stage <- function(prefix, default) {
  match <- grep(paste0("^", prefix, "="), args, value = TRUE)
  if (!length(match)) return(default)
  value <- suppressWarnings(as.integer(sub(paste0("^", prefix, "="), "", match[1])))
  if (is.na(value)) stop("Invalid ", prefix, " stage: ", match[1])
  value
}
start_stage <- read_stage("--start", 1L)
stop_stage <- read_stage("--stop", length(workflow))
if (start_stage < 1L || stop_stage > length(workflow) || start_stage > stop_stage) {
  stop("Stage range must satisfy 1 <= start <= stop <= ", length(workflow), ".")
}

selected <- workflow[seq.int(start_stage, stop_stage)]
for (script in selected) {
  path <- file.path(project_dir, "scripts", script)
  if (!file.exists(path)) stop("Missing workflow script: ", path)
  message("Running ", script, " ...")
  # Quote the script argument so a relocated checkout may contain spaces.
  status <- system2(file.path(R.home("bin"), "Rscript"), shQuote(path))
  if (!identical(status, 0L)) stop("Workflow failed in ", script, " (status ", status, ").")
}
message("Workflow completed successfully for stages ", start_stage, " through ", stop_stage, ".")
