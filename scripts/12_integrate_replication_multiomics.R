#!/usr/bin/env Rscript

# ==============================================================================
# File: 12_integrate_replication_multiomics.R
# Purpose: Integrate replication-stress scores with TCGA multi-omic features.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Expression/pathway objects, HRR status, and configured TCGA Xena multi-omic files.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; response level order; multiomics source_files,
#     axis_pathways, gene/feature lists, interaction_specs, size/FDR/GISTIC checks;
#     resampling.cross_validation_folds and cross_validation_repeats.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Integrated multi-omic RDS, interaction results, and summary figures.
# Reproducibility:
#   - Membership comes from locked MSigDB sets; YAML rows preserve interaction order.
#   - Paired stratified CV retains seed+10; its AUC is binary response AUC, not 36-month AUC.
# ==============================================================================

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(curatedOvarianData)
  library(Biobase)
})

options(stringsAsFactors = FALSE)

# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)
analysis_config <- config$analysis
multiomics_config <- analysis_config$multiomics
seed <- analysis_config$random_seeds$default
configure_reproducible_runtime(seed, threads = 1L)
# Fail before scoring if a prespecified definition is absent; no fallback panels.
for (field in c("minimum_axis_genes", "expected_robust_pathway_count")) {
  value <- required_analysis_value(analysis_config, paste0("multiomics.", field))
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value) || value < 1 || value != floor(value)) {
    stop("multiomics.", field, " must be a positive integer.")
  }
  multiomics_config[[field]] <- as.integer(value)
}
for (field in c("proliferation_marker_gene", "methylation_gene", "cnv_genes", "rppa_features")) {
  value <- unlist(required_analysis_value(analysis_config, paste0("multiomics.", field)), use.names = FALSE)
  if (!is.character(value) || !length(value) || anyNA(value) || any(!nzchar(value)) || anyDuplicated(value) ||
      (field %in% c("proliferation_marker_gene", "methylation_gene") && length(value) != 1L)) {
    stop("Invalid non-empty character definition: multiomics.", field)
  }
  multiomics_config[[field]] <- value
}
source_files <- required_analysis_value(analysis_config, "multiomics.source_files")
if (!is.list(source_files) || !identical(names(source_files),
    c("HRD", "CNV_continuous", "CNV_thresholded", "RPPA", "methylation27", "methylation27_map"))) {
  stop("multiomics.source_files must contain the six ordered Xena source identifiers.")
}
for (field in names(source_files)) {
  value <- source_files[[field]]
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    stop("Invalid Xena source identifier: multiomics.source_files.", field)
  }
}
axis_pathways <- required_analysis_value(analysis_config, "multiomics.axis_pathways")
if (!is.list(axis_pathways) || !identical(names(axis_pathways),
    c("general_proliferation", "replication_licensing", "dna_synthesis", "atr_checkpoint"))) {
  stop("multiomics.axis_pathways must contain the four ordered biological axes.")
}
for (axis in names(axis_pathways)) {
  pathways <- unlist(axis_pathways[[axis]], use.names = FALSE)
  if (!is.character(pathways) || !length(pathways) || anyNA(pathways) || any(!nzchar(pathways)) || anyDuplicated(pathways)) {
    stop("Invalid locked pathway vector: multiomics.axis_pathways.", axis)
  }
  axis_pathways[[axis]] <- pathways
}
interaction_definitions <- required_analysis_value(analysis_config, "multiomics.interaction_specs")
if (!is.list(interaction_definitions) || !length(interaction_definitions) || !is.null(names(interaction_definitions))) {
  stop("multiomics.interaction_specs must be an ordered sequence of score/modifier mappings.")
}
for (i in seq_along(interaction_definitions)) {
  spec <- interaction_definitions[[i]]
  if (!is.list(spec) || !identical(names(spec), c("score", "modifier")) ||
      !all(vapply(spec, function(value) is.character(value) && length(value) == 1L &&
        !is.na(value) && nzchar(value), logical(1)))) {
    stop("Invalid score/modifier mapping at multiomics.interaction_specs row ", i)
  }
}
xena_dir <- config$paths$xena_dir
processed_dir <- config$paths$processed_data_dir
results_dir <- config$paths$results_dir
qc_path <- file.path(processed_dir, "tcga_ov_u133a_expression_qc.rds")
geneset_path <- file.path(processed_dir, "msigdb_pathway_collections.rds")
robust_pathway_path <- file.path(results_dir, "tables", "pathway_enrichment", "robust_M3_ranked_pathways.csv")
hrr_status_path <- file.path(processed_dir, "tcga_ov_hrr_mutation_status.csv")
processed_path <- file.path(processed_dir, "tcga_ov_phase3_replication_multiomics.rds")
table_dir <- file.path(results_dir, "tables", "phase3_replication_multiomics")
figure_dir <- file.path(results_dir, "figures", "phase3_replication_multiomics")
log_dir <- file.path(project_dir, "logs")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

source_labels <- unlist(source_files, use.names = TRUE)
source_paths <- setNames(
  file.path(xena_dir, unname(source_labels)),
  names(source_labels)
)
required <- c(qc_path, geneset_path, robust_pathway_path, hrr_status_path, source_paths)
if (!all(file.exists(required))) {
  stop("Missing prerequisite: ", paste(required[!file.exists(required)], collapse = ", "))
}

write_csv_safe <- function(x, path) write_csv(as.data.frame(x), path, na = "")
standardize <- function(x) {
  out <- rep(NA_real_, length(x))
  ok <- is.finite(x)
  if (sum(ok) >= 2L && sd(x[ok]) > 0) out[ok] <- as.numeric(scale(x[ok]))
  out
}
canonical_sample <- function(x) gsub("\\.", "-", x)
patient_from_sample <- function(x) substr(canonical_sample(x), 1L, 12L)
is_primary_tumor <- function(x) substr(canonical_sample(x), 14L, 15L) == "01"

# ---- Analysis workflow --------------------------------------------------------
message("Reading locked expression, phenotype, and pathway objects...")
qc <- readRDS(qc_path)
if (!is.list(qc) || !all(c("expression", "phenotype", "model_genes") %in% names(qc)) ||
    !is.matrix(qc$expression) || !is.data.frame(qc$phenotype)) {
  stop("Expression QC object lacks expression, phenotype or model_genes.")
}
expr <- qc$expression[intersect(qc$model_genes, rownames(qc$expression)), , drop = FALSE]
pheno <- qc$phenotype
# Drop an unused data.table IDate column before dplyr joins; its serialized class can be
# reconstructed inconsistently across package versions and is irrelevant to Phase 3.
pheno$form_completion_date <- NULL
if (!identical(colnames(expr), pheno$sample)) stop("Expression/phenotype alignment failed")
if (anyDuplicated(pheno$patient)) stop("Expected one expression sample per patient")
geneset_obj <- readRDS(geneset_path)
if (!is.list(geneset_obj) || !is.list(geneset_obj$sets) || is.null(names(geneset_obj$sets))) {
  stop("Locked MSigDB object lacks a named sets mapping.")
}
robust_pathways <- read_csv(robust_pathway_path, show_col_types = FALSE) %>% filter(robust_all)
if (nrow(robust_pathways) != multiomics_config$expected_robust_pathway_count) {
  stop("Expected exactly ", multiomics_config$expected_robust_pathway_count, " locked robust pathways")
}
if (!"pathway" %in% names(robust_pathways) || anyNA(robust_pathways$pathway)) {
  stop("Locked robust pathway audit lacks nonmissing pathway identifiers.")
}
if (!multiomics_config$proliferation_marker_gene %in% rownames(expr)) {
  stop("Missing configured proliferation marker: ", multiomics_config$proliferation_marker_gene)
}

pheno <- pheno %>%
  mutate(
    response4 = factor(response4, levels = analysis_config$response$four_levels),
    response_m2 = factor(response_m2, levels = analysis_config$response$objective_response_levels),
    response_m3 = factor(response_m3, levels = analysis_config$response$cr_threshold_levels),
    stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
    residual_group = factor(residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm")),
    tss_collapsed = droplevels(factor(tss_collapsed)),
    age_z = standardize(age),
    diagnosis_year_z = standardize(diagnosis_year),
    noncr = as.integer(response_m3 == "Non-CR")
  )

# Slide-derived histologic tumor-cell percentage is retained only as a sensitivity covariate.
data("TCGA_eset", package = "curatedOvarianData")
curated <- Biobase::pData(TCGA_eset) %>%
  as.data.frame() %>%
  transmute(
    patient = gsub("\\.", "-", substr(as.character(unique_patient_ID), 1, 12)),
    normal_pct = suppressWarnings(as.numeric(as.character(percent_normal_cells))),
    stromal_pct = suppressWarnings(as.numeric(as.character(percent_stromal_cells))),
    tumor_pct_raw = suppressWarnings(as.numeric(as.character(percent_tumor_cells)))
  ) %>%
  mutate(
    all_zero = !is.na(normal_pct) & !is.na(stromal_pct) & !is.na(tumor_pct_raw) &
      normal_pct == 0 & stromal_pct == 0 & tumor_pct_raw == 0,
    pathology_tumor_pct = if_else(all_zero, NA_real_, tumor_pct_raw)
  ) %>%
  distinct(patient, .keep_all = TRUE) %>%
  select(patient, pathology_tumor_pct)
pheno <- pheno %>%
  left_join(curated, by = "patient") %>%
  mutate(pathology_tumor_pct_z = standardize(pathology_tumor_pct))

# Locked biological axes come from configuration; membership still comes only
# from the frozen MSigDB object, never from manually substituted gene panels.
required_pathways <- unique(c(unlist(axis_pathways), robust_pathways$pathway))
if (!all(required_pathways %in% names(geneset_obj$sets))) {
  stop("Missing locked pathway sets: ", paste(setdiff(required_pathways, names(geneset_obj$sets)), collapse = ", "))
}
if (!all(vapply(geneset_obj$sets[required_pathways], function(genes) {
  is.character(genes) && length(genes) > 0L && !anyNA(genes) && all(nzchar(genes))
}, logical(1)))) {
  stop("Locked MSigDB pathway memberships must be non-empty character vectors.")
}
axis_genes <- lapply(axis_pathways, function(pathways) {
  intersect(unique(unlist(geneset_obj$sets[pathways])), rownames(expr))
})
axis_genes$replication_composite <- unique(c(
  axis_genes$replication_licensing,
  axis_genes$dna_synthesis,
  axis_genes$atr_checkpoint
))
axis_genes$robust_nine_composite <- intersect(
  unique(unlist(geneset_obj$sets[robust_pathways$pathway])), rownames(expr)
)
if (any(lengths(axis_genes) < multiomics_config$minimum_axis_genes)) {
  stop("A locked axis has fewer than ", multiomics_config$minimum_axis_genes, " measured genes")
}

message("Calculating locked z-mean expression scores...")
# Standardize each gene across the unchanged analysis cohort, average genes with
# equal weight, then standardize each axis. Composite genes are a unique union,
# not an average of pathway scores; excess scores are OLS residuals thereafter.
genes_used <- unique(unlist(axis_genes))
expr_z <- t(scale(t(expr[genes_used, , drop = FALSE])))
expr_z[!is.finite(expr_z)] <- NA_real_
score_matrix <- vapply(axis_genes, function(genes) {
  colMeans(expr_z[intersect(genes, rownames(expr_z)), , drop = FALSE], na.rm = TRUE)
}, numeric(ncol(expr_z)))
rownames(score_matrix) <- colnames(expr)
score_matrix <- apply(score_matrix, 2L, standardize)
if (is.null(dim(score_matrix))) stop("Score matrix construction failed")
rownames(score_matrix) <- colnames(expr)

score_df <- data.frame(sample = rownames(score_matrix), score_matrix, check.names = FALSE)
# Legacy field names remain stable for downstream consumers of these locked scores.
score_df$MKI67_expression_z <- standardize(as.numeric(expr[multiomics_config$proliferation_marker_gene, score_df$sample]))
score_df$replication_excess <- standardize(residuals(lm(
  replication_composite ~ general_proliferation,
  data = score_df
)))
score_df$licensing_excess <- standardize(residuals(lm(
  replication_licensing ~ general_proliferation,
  data = score_df
)))
score_df$atr_excess <- standardize(residuals(lm(
  atr_checkpoint ~ general_proliferation,
  data = score_df
)))

score_names <- setdiff(names(score_df), "sample")
score_overlap_rows <- list()
row_id <- 1L
for (axis in names(axis_genes)) {
  for (other in names(axis_genes)) {
    a <- axis_genes[[axis]]
    b <- axis_genes[[other]]
    score_overlap_rows[[row_id]] <- data.frame(
      axis = axis,
      other_axis = other,
      axis_genes = length(a),
      other_genes = length(b),
      overlap_n = length(intersect(a, b)),
      jaccard = length(intersect(a, b)) / length(union(a, b)),
      stringsAsFactors = FALSE
    )
    row_id <- row_id + 1L
  }
}
score_overlap <- bind_rows(score_overlap_rows)
score_gene_audit <- tibble(
  axis = names(axis_genes),
  pathway_members = vapply(names(axis_genes), function(x) {
    if (x %in% names(axis_pathways)) paste(axis_pathways[[x]], collapse = ";") else if (x == "replication_composite") {
      paste(c(axis_pathways$replication_licensing, axis_pathways$dna_synthesis, axis_pathways$atr_checkpoint), collapse = ";")
    } else paste(robust_pathways$pathway, collapse = ";")
  }, character(1)),
  measured_gene_n = lengths(axis_genes),
  measured_genes = vapply(axis_genes, paste, collapse = ";", FUN.VALUE = character(1))
)
write_csv_safe(score_gene_audit, file.path(table_dir, "locked_score_gene_audit.csv"))
write_csv_safe(score_overlap, file.path(table_dir, "locked_score_gene_overlap.csv"))

analysis_df <- pheno %>% left_join(score_df, by = "sample")
if (anyNA(analysis_df[, score_names])) stop("Missing locked score values")

score_cor <- cor(analysis_df[, score_names], method = "spearman", use = "pairwise.complete.obs")
score_cor_long <- as.data.frame(as.table(score_cor), stringsAsFactors = FALSE)
names(score_cor_long) <- c("score1", "score2", "spearman")
write_csv_safe(score_cor_long, file.path(table_dir, "locked_score_correlations.csv"))

make_formula <- function(outcome, response, covariates) {
  reformulate(c(response, covariates), response = outcome)
}

fit_continuous_feature <- function(data, feature, adjustment, covariates) {
  rows <- list()
  row_id <- 1L
  for (spec in list(
    list(response = "response_m3", test = "M3_NonCR_minus_CR", coef = "response_m3Non-CR"),
    list(response = "response_m2", test = "M2_SD_PD_minus_CR_PR", coef = "response_m2SD+PD")
  )) {
    required <- unique(c(feature, spec$response, covariates))
    d <- data[complete.cases(data[, required, drop = FALSE]), , drop = FALSE]
    d <- droplevels(d)
    fit <- lm(make_formula(feature, spec$response, covariates), data = d)
    coef_name <- spec$coef
    if (!coef_name %in% names(coef(fit))) {
      coef_name <- grep(paste0("^", spec$response), names(coef(fit)), value = TRUE)[1]
    }
    sm <- summary(fit)$coefficients
    rows[[row_id]] <- data.frame(
      feature = feature,
      adjustment = adjustment,
      test = spec$test,
      contrast = coef_name,
      n = nrow(d),
      estimate = sm[coef_name, "Estimate"],
      standard_error = sm[coef_name, "Std. Error"],
      statistic = sm[coef_name, "t value"],
      p_value = sm[coef_name, "Pr(>|t|)"],
      stringsAsFactors = FALSE
    )
    row_id <- row_id + 1L
  }

  required <- unique(c(feature, "response4", covariates))
  d <- data[complete.cases(data[, required, drop = FALSE]), , drop = FALSE]
  d <- droplevels(d)
  fit_full <- lm(make_formula(feature, "response4", covariates), data = d)
  fit_reduced <- lm(reformulate(covariates, response = feature), data = d)
  av <- anova(fit_reduced, fit_full)
  rows[[row_id]] <- data.frame(
    feature = feature,
    adjustment = adjustment,
    test = "M1_global",
    contrast = "response4_PR_SD_PD",
    n = nrow(d),
    estimate = NA_real_,
    standard_error = NA_real_,
    statistic = av$F[2],
    p_value = av$`Pr(>F)`[2],
    stringsAsFactors = FALSE
  )
  row_id <- row_id + 1L
  sm <- summary(fit_full)$coefficients
  for (level in c("PR", "SD", "PD")) {
    coef_name <- paste0("response4", level)
    rows[[row_id]] <- data.frame(
      feature = feature,
      adjustment = adjustment,
      test = paste0("M1_", level, "_minus_CR"),
      contrast = coef_name,
      n = nrow(d),
      estimate = sm[coef_name, "Estimate"],
      standard_error = sm[coef_name, "Std. Error"],
      statistic = sm[coef_name, "t value"],
      p_value = sm[coef_name, "Pr(>|t|)"],
      stringsAsFactors = FALSE
    )
    row_id <- row_id + 1L
  }
  bind_rows(rows)
}

message("Testing score-response associations and proliferation specificity...")
nuisance_sets <- list(
  response_only = character(0),
  pre_residual = c("age_z", "stage_group", "tss_collapsed", "diagnosis_year_z"),
  full = c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z")
)
association_rows <- list()
row_id <- 1L
for (adjustment in names(nuisance_sets)) {
  for (feature in score_names) {
    association_rows[[row_id]] <- fit_continuous_feature(
      analysis_df, feature, adjustment, nuisance_sets[[adjustment]]
    )
    row_id <- row_id + 1L
  }
}
replication_features <- c(
  "replication_licensing", "dna_synthesis", "atr_checkpoint", "replication_composite",
  "replication_excess", "licensing_excess", "atr_excess"
)
for (feature in replication_features) {
  association_rows[[row_id]] <- fit_continuous_feature(
    analysis_df, feature, "full_plus_proliferation",
    c(nuisance_sets$full, "general_proliferation")
  )
  row_id <- row_id + 1L
  association_rows[[row_id]] <- fit_continuous_feature(
    analysis_df, feature, "full_plus_proliferation_pathology_purity",
    c(nuisance_sets$full, "general_proliferation", "pathology_tumor_pct_z")
  )
  row_id <- row_id + 1L
}
score_associations <- bind_rows(association_rows) %>%
  group_by(adjustment, test) %>%
  mutate(FDR = p.adjust(p_value, method = "BH")) %>%
  ungroup() %>%
  arrange(adjustment, test, FDR)
write_csv_safe(score_associations, file.path(table_dir, "score_response_associations.csv"))

# Stream only requested rows from large Xena matrices. Unassayed patients remain missing,
# especially for the mutation matrix; absence of a matrix column is never coded as wild-type.
read_xena_rows <- function(path, keys, project_patients, chunk_size = 1000L) {
  con <- gzfile(path, open = "rt")
  on.exit(close(con), add = TRUE)
  header <- strsplit(readLines(con, n = 1L, warn = FALSE), "\t", fixed = TRUE)[[1]]
  source_samples <- canonical_sample(header[-1])
  source_patients <- patient_from_sample(source_samples)
  keep <- source_patients %in% project_patients & is_primary_tumor(source_samples)
  keep_idx <- which(keep)
  sample_map <- tibble(
    source_sample = source_samples[keep_idx],
    patient = source_patients[keep_idx]
  )
  found <- list()
  remaining <- unique(keys)
  repeat {
    lines <- readLines(con, n = chunk_size, warn = FALSE)
    if (!length(lines)) break
    row_keys <- sub("\t.*$", "", lines)
    hit <- which(row_keys %in% remaining)
    if (length(hit)) {
      for (i in hit) {
        values <- strsplit(lines[i], "\t", fixed = TRUE)[[1]]
        key <- values[1]
        selected <- values[1L + keep_idx]
        found[[key]] <- tibble(
          source_sample = sample_map$source_sample,
          patient = sample_map$patient,
          feature = key,
          value = suppressWarnings(as.numeric(selected))
        )
        remaining <- setdiff(remaining, key)
      }
    }
    if (!length(remaining)) break
  }
  list(
    long = bind_rows(found),
    sample_map = sample_map,
    missing_keys = remaining,
    header_sample_n = length(source_samples),
    primary_project_sample_n = nrow(sample_map),
    primary_project_patient_n = n_distinct(sample_map$patient)
  )
}

collapse_xena <- function(extracted, prefix = "", rename_map = NULL) {
  d <- extracted$long
  if (!nrow(d)) return(tibble(patient = character()))
  if (!is.null(rename_map)) {
    d$feature <- unname(rename_map[d$feature])
  }
  d$feature <- paste0(prefix, make.names(d$feature))
  d %>%
    group_by(patient, feature) %>%
    summarise(value = if (all(is.na(value))) NA_real_ else median(value, na.rm = TRUE), .groups = "drop") %>%
    pivot_wider(names_from = feature, values_from = value)
}

message("Extracting HRD, CNV, mutation, methylation, and RPPA rows...")
project_patients <- pheno$patient
hrd_extract <- read_xena_rows(source_paths[["HRD"]], c("ai1", "lst1", "hrd-loh", "HRD"), project_patients)
hrd <- collapse_xena(
  hrd_extract,
  rename_map = c(ai1 = "ntAI", lst1 = "LST", `hrd-loh` = "HRD_LOH", HRD = "HRD_score")
)

cnv_genes <- multiomics_config$cnv_genes
cnv_cont_extract <- read_xena_rows(source_paths[["CNV_continuous"]], cnv_genes, project_patients)
cnv_thr_extract <- read_xena_rows(source_paths[["CNV_thresholded"]], cnv_genes, project_patients)
cnv_cont <- collapse_xena(cnv_cont_extract, prefix = "CNV_cont_")
cnv_thr <- collapse_xena(cnv_thr_extract, prefix = "CNV_threshold_")

hrr_status <- read_csv(hrr_status_path, show_col_types = FALSE)
mutation <- hrr_status %>%
  select(
    patient, sequenced_cbioportal, BRCA_any, BRCA_lof,
    HRR_core_any, HRR_core_lof, HRR_extended_any, HRR_extended_lof,
    total_protein_altering_mutations
  )
mutation_n <- sum(mutation$sequenced_cbioportal, na.rm = TRUE)

map27 <- data.table::fread(source_paths[["methylation27_map"]], data.table = FALSE, check.names = FALSE)
if (!all(c("gene", "#id") %in% names(map27))) stop("Methylation annotation lacks gene or #id columns.")
# Preserve comma-delimited gene recognition and legacy BRCA1 output fields.
brca1_probes <- map27 %>%
  filter(grepl(paste0("(^|,)", multiomics_config$methylation_gene, "(,|$)"), gene)) %>%
  pull(`#id`) %>%
  unique()
if (!length(brca1_probes)) stop("No linked methylation probes for configured gene: ", multiomics_config$methylation_gene)
methyl_extract <- read_xena_rows(source_paths[["methylation27"]], brca1_probes, project_patients)
methyl_long <- methyl_extract$long %>%
  group_by(patient) %>%
  summarise(
    BRCA1_linked_methylation = if (all(is.na(value))) NA_real_ else median(value, na.rm = TRUE),
    BRCA1_methylation_probes_observed = sum(is.finite(value)),
    .groups = "drop"
  )

rppa_features <- multiomics_config$rppa_features
rppa_extract <- read_xena_rows(source_paths[["RPPA"]], rppa_features, project_patients)
rppa <- collapse_xena(rppa_extract, prefix = "RPPA_")

multiomics <- list(hrd, cnv_cont, cnv_thr, mutation, methyl_long, rppa) %>%
  Reduce(function(x, y) full_join(x, y, by = "patient"), .)
analysis_df <- analysis_df %>%
  left_join(multiomics, by = "patient") %>%
  mutate(
    CCNE1_amplified = case_when(
      is.na(CNV_threshold_CCNE1) ~ NA_real_,
      CNV_threshold_CCNE1 >= multiomics_config$gistic_amplification_threshold ~ 1,
      TRUE ~ 0
    ),
    BRCA1_deleted = case_when(
      is.na(CNV_threshold_BRCA1) ~ NA_real_,
      CNV_threshold_BRCA1 <= multiomics_config$gistic_deletion_threshold ~ 1,
      TRUE ~ 0
    ),
    BRCA2_deleted = case_when(
      is.na(CNV_threshold_BRCA2) ~ NA_real_,
      CNV_threshold_BRCA2 <= multiomics_config$gistic_deletion_threshold ~ 1,
      TRUE ~ 0
    )
  )

source_audit <- bind_rows(
  tibble(source = "HRD", file = file.path("xena_dir", source_labels[["HRD"]]), requested_features = "ai1;lst1;hrd-loh;HRD",
         missing_features = paste(hrd_extract$missing_keys, collapse = ";"),
         primary_project_samples = hrd_extract$primary_project_sample_n,
         primary_project_patients = hrd_extract$primary_project_patient_n),
  tibble(source = "CNV_continuous", file = file.path("xena_dir", source_labels[["CNV_continuous"]]), requested_features = paste(cnv_genes, collapse = ";"),
         missing_features = paste(cnv_cont_extract$missing_keys, collapse = ";"),
         primary_project_samples = cnv_cont_extract$primary_project_sample_n,
         primary_project_patients = cnv_cont_extract$primary_project_patient_n),
  tibble(source = "CNV_thresholded", file = file.path("xena_dir", source_labels[["CNV_thresholded"]]), requested_features = paste(cnv_genes, collapse = ";"),
         missing_features = paste(cnv_thr_extract$missing_keys, collapse = ";"),
         primary_project_samples = cnv_thr_extract$primary_project_sample_n,
         primary_project_patients = cnv_thr_extract$primary_project_patient_n),
  tibble(source = "cBioPortal_PanCancer_Atlas_mutations",
         file = file.path("processed_data_dir", basename(hrr_status_path)),
         requested_features = "BRCA_any;BRCA_lof;HRR_core_any;HRR_core_lof;HRR_extended_any;HRR_extended_lof",
         missing_features = "",
         primary_project_samples = mutation_n,
         primary_project_patients = mutation_n),
  tibble(source = "methylation27", file = file.path("xena_dir", source_labels[["methylation27"]]), requested_features = paste(brca1_probes, collapse = ";"),
         missing_features = paste(methyl_extract$missing_keys, collapse = ";"),
         primary_project_samples = methyl_extract$primary_project_sample_n,
         primary_project_patients = methyl_extract$primary_project_patient_n),
  tibble(source = "RPPA", file = file.path("xena_dir", source_labels[["RPPA"]]), requested_features = paste(rppa_features, collapse = ";"),
         missing_features = paste(rppa_extract$missing_keys, collapse = ";"),
         primary_project_samples = rppa_extract$primary_project_sample_n,
         primary_project_patients = rppa_extract$primary_project_patient_n)
)
write_csv_safe(source_audit, file.path(table_dir, "multiomics_source_audit.csv"))

omics_feature_names <- c(
  "ntAI", "LST", "HRD_LOH", "HRD_score",
  "CNV_cont_BRCA1", "CNV_cont_BRCA2", "CNV_cont_CCNE1",
  "CNV_threshold_BRCA1", "CNV_threshold_BRCA2", "CNV_threshold_CCNE1",
  "CCNE1_amplified", "BRCA1_deleted", "BRCA2_deleted",
  "BRCA_any", "BRCA_lof", "HRR_core_any", "HRR_core_lof",
  "HRR_extended_any", "HRR_extended_lof", "total_protein_altering_mutations",
  "BRCA1_linked_methylation",
  grep("^RPPA_", names(analysis_df), value = TRUE)
)
omics_feature_names <- intersect(omics_feature_names, names(analysis_df))
availability <- bind_rows(lapply(omics_feature_names, function(feature) {
  ok <- is.finite(analysis_df[[feature]])
  tibble(
    feature = feature,
    n_available = sum(ok),
    CR = sum(ok & analysis_df$response4 == "CR"),
    PR = sum(ok & analysis_df$response4 == "PR"),
    SD = sum(ok & analysis_df$response4 == "SD"),
    PD = sum(ok & analysis_df$response4 == "PD"),
    unique_values = n_distinct(analysis_df[[feature]][ok])
  )
}))
write_csv_safe(availability, file.path(table_dir, "multiomics_feature_availability.csv"))

continuous_omics <- availability %>%
  filter(
    n_available >= multiomics_config$minimum_samples,
    unique_values >= multiomics_config$minimum_distinct_values
  ) %>%
  pull(feature)
correlation_rows <- list()
row_id <- 1L
for (score in score_names) {
  for (feature in continuous_omics) {
    ok <- is.finite(analysis_df[[score]]) & is.finite(analysis_df[[feature]])
    ct <- suppressWarnings(cor.test(
      analysis_df[[score]][ok], analysis_df[[feature]][ok],
      method = "spearman", exact = FALSE
    ))
    correlation_rows[[row_id]] <- tibble(
      score = score,
      omics_feature = feature,
      n = sum(ok),
      spearman = unname(ct$estimate),
      p_value = ct$p.value
    )
    row_id <- row_id + 1L
  }
}
score_omics_cor <- bind_rows(correlation_rows) %>%
  mutate(FDR = p.adjust(p_value, method = "BH")) %>%
  arrange(FDR)
write_csv_safe(score_omics_cor, file.path(table_dir, "score_multiomics_correlations.csv"))

message("Testing multiomics-response associations...")
omics_response_rows <- list()
row_id <- 1L
for (feature in continuous_omics) {
  analysis_df[[paste0(feature, "_z")]] <- standardize(analysis_df[[feature]])
  feature_z <- paste0(feature, "_z")
  for (adjustment in names(nuisance_sets)) {
    omics_response_rows[[row_id]] <- fit_continuous_feature(
      analysis_df, feature_z, adjustment, nuisance_sets[[adjustment]]
    ) %>% mutate(source_feature = feature)
    row_id <- row_id + 1L
  }
}
omics_response <- bind_rows(omics_response_rows) %>%
  group_by(adjustment, test) %>%
  mutate(FDR = p.adjust(p_value, method = "BH")) %>%
  ungroup() %>%
  arrange(adjustment, test, FDR)
write_csv_safe(omics_response, file.path(table_dir, "multiomics_response_associations.csv"))

# Pre-specified effect-modification analyses use M3 as the outcome. These are exploratory
# association models and must not be interpreted as causal treatment-effect interactions.
# Binding each YAML row in sequence preserves the original tribble's order and
# two character columns; sorting or expanding a Cartesian grid would change it.
interaction_specs <- bind_rows(interaction_definitions)
if (!all(interaction_specs$score %in% score_names)) {
  stop("Unknown configured interaction score(s): ",
       paste(setdiff(interaction_specs$score, score_names), collapse = ", "))
}
interaction_covariates <- nuisance_sets$full
interaction_rows <- list()
skipped_rows <- list()
row_id <- 1L
skip_id <- 1L
for (i in seq_len(nrow(interaction_specs))) {
  score <- interaction_specs$score[i]
  modifier <- interaction_specs$modifier[i]
  if (!modifier %in% names(analysis_df)) {
    skipped_rows[[skip_id]] <- tibble(score = score, modifier = modifier, reason = "modifier unavailable")
    skip_id <- skip_id + 1L
    next
  }
  d <- analysis_df
  modifier_model <- paste0(modifier, "_interaction")
  if (n_distinct(d[[modifier]][is.finite(d[[modifier]])]) > 2L) {
    d[[modifier_model]] <- standardize(d[[modifier]])
  } else {
    d[[modifier_model]] <- d[[modifier]]
  }
  required <- unique(c("noncr", score, modifier_model, interaction_covariates))
  d <- d[complete.cases(d[, required, drop = FALSE]), , drop = FALSE]
  d <- droplevels(d)
  if (nrow(d) < multiomics_config$minimum_samples || length(unique(d[[modifier_model]])) < 2L ||
      (length(unique(d[[modifier_model]])) == 2L &&
       min(table(d[[modifier_model]])) < multiomics_config$minimum_binary_group)) {
    skipped_rows[[skip_id]] <- tibble(
      score = score, modifier = modifier,
      reason = paste0("insufficient analyzable sample/event count: n=", nrow(d))
    )
    skip_id <- skip_id + 1L
    next
  }
  full_formula <- reformulate(
    c(paste0(score, "*", modifier_model), interaction_covariates),
    response = "noncr"
  )
  reduced_formula <- reformulate(c(score, modifier_model, interaction_covariates), response = "noncr")
  fit_full <- glm(full_formula, data = d, family = binomial())
  fit_reduced <- glm(reduced_formula, data = d, family = binomial())
  coef_name <- paste0(score, ":", modifier_model)
  if (!coef_name %in% names(coef(fit_full))) coef_name <- paste0(modifier_model, ":", score)
  sm <- summary(fit_full)$coefficients
  lr <- anova(fit_reduced, fit_full, test = "LRT")
  interaction_rows[[row_id]] <- tibble(
    score = score,
    modifier = modifier,
    n = nrow(d),
    CR = sum(d$noncr == 0),
    Non_CR = sum(d$noncr == 1),
    interaction_log_OR = sm[coef_name, "Estimate"],
    interaction_SE = sm[coef_name, "Std. Error"],
    interaction_Wald_p = sm[coef_name, "Pr(>|z|)"],
    interaction_LRT_p = lr$`Pr(>Chi)`[2],
    converged = fit_full$converged
  )
  row_id <- row_id + 1L
}
interaction_results <- bind_rows(interaction_rows) %>%
  mutate(FDR = p.adjust(interaction_LRT_p, method = "BH")) %>%
  arrange(FDR)
interaction_skipped <- if (length(skipped_rows)) {
  bind_rows(skipped_rows)
} else {
  tibble(score = character(), modifier = character(), reason = character())
}
write_csv_safe(interaction_results, file.path(table_dir, "M3_multiomics_interactions.csv"))
write_csv_safe(interaction_skipped, file.path(table_dir, "M3_multiomics_interactions_skipped.csv"))

# Locked clinical incremental-value audit. No feature selection is performed inside CV.
auc_rank <- function(y, p) {
  ok <- is.finite(y) & is.finite(p)
  y <- y[ok]
  p <- p[ok]
  n1 <- sum(y == 1)
  n0 <- sum(y == 0)
  if (!n1 || !n0) return(NA_real_)
  (sum(rank(p, ties.method = "average")[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
log_loss <- function(y, p) {
  p <- pmin(pmax(p, 1e-8), 1 - 1e-8)
  -mean(y * log(p) + (1 - y) * log(1 - p))
}
cv_formulas <- list(
  clinical = noncr ~ age_z + stage_group + residual_group + tss_collapsed + diagnosis_year_z,
  clinical_plus_proliferation = noncr ~ age_z + stage_group + residual_group + tss_collapsed + diagnosis_year_z + general_proliferation,
  clinical_plus_replication = noncr ~ age_z + stage_group + residual_group + tss_collapsed + diagnosis_year_z + replication_composite,
  clinical_plus_both = noncr ~ age_z + stage_group + residual_group + tss_collapsed + diagnosis_year_z + general_proliferation + replication_composite,
  clinical_plus_replication_excess = noncr ~ age_z + stage_group + residual_group + tss_collapsed + diagnosis_year_z + general_proliferation + replication_excess
)
cv_required <- unique(unlist(lapply(cv_formulas, all.vars)))
cv_data <- analysis_df[complete.cases(analysis_df[, cv_required, drop = FALSE]), , drop = FALSE]
cv_data <- droplevels(cv_data)
n_folds <- analysis_config$resampling$cross_validation_folds
n_repeats <- analysis_config$resampling$cross_validation_repeats
cv_rows <- list()
row_id <- 1L
set.seed(seed + 10L)
for (repeat_id in seq_len(n_repeats)) {
  fold <- integer(nrow(cv_data))
  for (label in sort(unique(cv_data$noncr))) {
    idx <- which(cv_data$noncr == label)
    fold[idx] <- sample(rep(seq_len(n_folds), length.out = length(idx)))
  }
  for (model_name in names(cv_formulas)) {
    pred <- rep(NA_real_, nrow(cv_data))
    for (k in seq_len(n_folds)) {
      train <- cv_data[fold != k, , drop = FALSE]
      test <- cv_data[fold == k, , drop = FALSE]
      fit <- glm(cv_formulas[[model_name]], data = train, family = binomial())
      pred[fold == k] <- suppressWarnings(predict(fit, newdata = test, type = "response"))
    }
    cv_rows[[row_id]] <- tibble(
      repeat_id = repeat_id,
      model = model_name,
      n = nrow(cv_data),
      AUC = auc_rank(cv_data$noncr, pred),
      log_loss = log_loss(cv_data$noncr, pred),
      Brier = mean((cv_data$noncr - pred)^2, na.rm = TRUE)
    )
    row_id <- row_id + 1L
  }
}
cv_results <- bind_rows(cv_rows)
cv_summary <- cv_results %>%
  group_by(model) %>%
  summarise(
    repeats = n(),
    n = first(n),
    median_AUC = median(AUC, na.rm = TRUE),
    q05_AUC = quantile(AUC, 0.05, na.rm = TRUE),
    q95_AUC = quantile(AUC, 0.95, na.rm = TRUE),
    median_log_loss = median(log_loss, na.rm = TRUE),
    median_Brier = median(Brier, na.rm = TRUE),
    .groups = "drop"
  )
clinical_cv <- cv_results %>%
  filter(model == "clinical") %>%
  select(repeat_id, clinical_AUC = AUC, clinical_log_loss = log_loss, clinical_Brier = Brier)
cv_increment <- cv_results %>%
  filter(model != "clinical") %>%
  left_join(clinical_cv, by = "repeat_id") %>%
  mutate(
    delta_AUC_vs_clinical = AUC - clinical_AUC,
    delta_log_loss_vs_clinical = log_loss - clinical_log_loss,
    delta_Brier_vs_clinical = Brier - clinical_Brier
  )
cv_increment_summary <- cv_increment %>%
  group_by(model) %>%
  summarise(
    median_delta_AUC = median(delta_AUC_vs_clinical, na.rm = TRUE),
    q05_delta_AUC = quantile(delta_AUC_vs_clinical, 0.05, na.rm = TRUE),
    q95_delta_AUC = quantile(delta_AUC_vs_clinical, 0.95, na.rm = TRUE),
    median_delta_log_loss = median(delta_log_loss_vs_clinical, na.rm = TRUE),
    median_delta_Brier = median(delta_Brier_vs_clinical, na.rm = TRUE),
    .groups = "drop"
  )
write_csv_safe(cv_results, file.path(table_dir, "M3_clinical_increment_cv_replicates.csv"))
write_csv_safe(cv_summary, file.path(table_dir, "M3_clinical_increment_cv_summary.csv"))
write_csv_safe(cv_increment_summary, file.path(table_dir, "M3_clinical_increment_cv_delta.csv"))

# Descriptive binary audits use explicit assay denominators; unsequenced mutation cases remain missing.
binary_features <- intersect(
  c(
    "CCNE1_amplified", "BRCA1_deleted", "BRCA2_deleted",
    "BRCA_any", "BRCA_lof", "HRR_core_any", "HRR_core_lof",
    "HRR_extended_any", "HRR_extended_lof"
  ),
  names(analysis_df)
)
binary_rows <- list()
row_id <- 1L
for (feature in binary_features) {
  ok <- is.finite(analysis_df[[feature]]) & !is.na(analysis_df$response_m3)
  tab <- table(analysis_df$response_m3[ok], analysis_df[[feature]][ok])
  p <- if (all(dim(tab) == c(2L, 2L))) fisher.test(tab)$p.value else NA_real_
  binary_rows[[row_id]] <- tibble(
    feature = feature,
    n = sum(ok),
    CR_positive = sum(analysis_df$response_m3[ok] == "CR" & analysis_df[[feature]][ok] == 1),
    CR_total = sum(analysis_df$response_m3[ok] == "CR"),
    NonCR_positive = sum(analysis_df$response_m3[ok] == "Non-CR" & analysis_df[[feature]][ok] == 1),
    NonCR_total = sum(analysis_df$response_m3[ok] == "Non-CR"),
    fisher_p = p
  )
  row_id <- row_id + 1L
}
binary_audit <- bind_rows(binary_rows) %>% mutate(FDR = p.adjust(fisher_p, method = "BH"))
write_csv_safe(binary_audit, file.path(table_dir, "binary_multiomics_M3_audit.csv"))

binary_adjusted_rows <- list()
row_id <- 1L
for (feature in binary_features) {
  required <- unique(c("noncr", feature, interaction_covariates))
  d <- analysis_df[complete.cases(analysis_df[, required, drop = FALSE]), , drop = FALSE]
  d <- droplevels(d)
  if (nrow(d) < multiomics_config$minimum_samples || length(unique(d[[feature]])) < 2L ||
      min(table(d[[feature]])) < multiomics_config$minimum_binary_group) next
  fit <- glm(reformulate(c(feature, interaction_covariates), response = "noncr"),
             data = d, family = binomial())
  sm <- summary(fit)$coefficients
  estimate <- sm[feature, "Estimate"]
  se <- sm[feature, "Std. Error"]
  binary_adjusted_rows[[row_id]] <- tibble(
    feature = feature,
    n = nrow(d),
    positive_n = sum(d[[feature]] == 1),
    adjusted_OR = exp(estimate),
    CI95_low = exp(estimate - 1.96 * se),
    CI95_high = exp(estimate + 1.96 * se),
    p_value = sm[feature, "Pr(>|z|)"],
    converged = fit$converged
  )
  row_id <- row_id + 1L
}
binary_adjusted <- bind_rows(binary_adjusted_rows) %>%
  mutate(FDR = p.adjust(p_value, method = "BH")) %>%
  arrange(FDR)
write_csv_safe(binary_adjusted, file.path(table_dir, "binary_multiomics_M3_adjusted.csv"))

sample_manifest_cols <- c(
  "sample", "patient", "response4", "response_m2", "response_m3", "qc_outlier",
  score_names, omics_feature_names
)
write_csv_safe(
  analysis_df[, intersect(sample_manifest_cols, names(analysis_df)), drop = FALSE],
  file.path(table_dir, "phase3_sample_manifest.csv")
)

# Figures.
plot_scores <- analysis_df %>%
  select(response4, general_proliferation, replication_composite, replication_excess,
         replication_licensing, dna_synthesis, atr_checkpoint) %>%
  pivot_longer(-response4, names_to = "score", values_to = "value") %>%
  ggplot(aes(response4, value, fill = response4)) +
  geom_boxplot(outlier.shape = NA, alpha = 0.75) +
  geom_jitter(width = 0.14, alpha = 0.25, size = 0.65) +
  facet_wrap(~score, scales = "free_y", ncol = 3) +
  scale_fill_brewer(palette = "Set2") +
  theme_bw(base_size = 10) +
  theme(legend.position = "none") +
  labs(x = "Primary therapy response", y = "Locked score (z)")
ggsave(file.path(figure_dir, "locked_scores_by_response.png"), plot_scores, width = 11, height = 8, dpi = 180)
ggsave(file.path(figure_dir, "locked_scores_by_response.pdf"), plot_scores, width = 11, height = 8)

plot_cor <- score_cor_long %>%
  ggplot(aes(score1, score2, fill = spearman)) +
  geom_tile(color = "white", linewidth = 0.25) +
  geom_text(aes(label = sprintf("%.2f", spearman)), size = 2.5) +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B", midpoint = 0, limits = c(-1, 1)) +
  coord_equal() +
  theme_bw(base_size = 9) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  labs(x = NULL, y = NULL, fill = "Spearman")
ggsave(file.path(figure_dir, "locked_score_correlation_heatmap.png"), plot_cor, width = 9, height = 8, dpi = 180)
ggsave(file.path(figure_dir, "locked_score_correlation_heatmap.pdf"), plot_cor, width = 9, height = 8)

if ("HRD_score" %in% names(analysis_df)) {
  plot_hrd <- analysis_df %>%
    filter(is.finite(HRD_score)) %>%
    ggplot(aes(HRD_score, replication_composite, color = response4)) +
    geom_point(alpha = 0.65) +
    geom_smooth(method = "lm", se = TRUE, color = "grey25", linewidth = 0.7) +
    scale_color_brewer(palette = "Dark2") +
    theme_bw(base_size = 10) +
    labs(x = "HRD score", y = "Replication composite (z)", color = "Response")
  ggsave(file.path(figure_dir, "HRD_vs_replication_score.png"), plot_hrd, width = 7.5, height = 5.5, dpi = 180)
  ggsave(file.path(figure_dir, "HRD_vs_replication_score.pdf"), plot_hrd, width = 7.5, height = 5.5)
}

plot_cv <- cv_results %>%
  ggplot(aes(reorder(model, AUC, FUN = median), AUC, fill = model)) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.12, alpha = 0.45, size = 1) +
  coord_flip() +
  theme_bw(base_size = 10) +
  theme(legend.position = "none") +
  labs(x = NULL, y = "Repeated 5-fold CV AUC")
ggsave(file.path(figure_dir, "M3_clinical_increment_cv_AUC.png"), plot_cv, width = 8, height = 5.5, dpi = 180)
ggsave(file.path(figure_dir, "M3_clinical_increment_cv_AUC.pdf"), plot_cv, width = 8, height = 5.5)

saveRDS(
  list(
    analysis_data = analysis_df,
    axis_genes = axis_genes,
    axis_pathways = axis_pathways,
    source_audit = source_audit,
    score_associations = score_associations,
    score_omics_correlations = score_omics_cor,
    omics_response_associations = omics_response,
    interaction_results = interaction_results,
    clinical_cv = cv_results
  ),
  processed_path,
  compress = "xz"
)

primary_specificity <- score_associations %>%
  filter(
    adjustment %in% c("full", "full_plus_proliferation", "full_plus_proliferation_pathology_purity"),
    test == "M3_NonCR_minus_CR",
    feature %in% c("general_proliferation", "replication_composite", "replication_excess")
  ) %>%
  arrange(adjustment, feature)
significant_interactions <- interaction_results %>% filter(FDR < multiomics_config$fdr_threshold)
best_cv <- cv_summary %>% arrange(desc(median_AUC)) %>% slice_head(n = 1)
run_summary <- c(
  paste("Phase 3 replication/multiomics analysis completed:", format(Sys.time(), tz = "UTC")),
  paste("Expression samples:", nrow(analysis_df)),
  paste("Locked score features:", length(score_names)),
  paste("General proliferation genes:", length(axis_genes$general_proliferation)),
  paste("Replication composite genes:", length(axis_genes$replication_composite)),
  paste("HRD available:", sum(is.finite(analysis_df$HRD_score))),
  paste("CNV available:", sum(is.finite(analysis_df$CNV_cont_CCNE1))),
  paste("BRCA1-linked methylation available:", sum(is.finite(analysis_df$BRCA1_linked_methylation))),
  paste("RPPA CHK1-pS345 available:", sum(is.finite(analysis_df$RPPA_CHK1_pS345))),
  paste("Mutation-assayed project patients:", mutation_n),
  "Mutation-unassayed patients were not coded as wild-type.",
  paste("FDR-significant pre-specified M3 interactions:", nrow(significant_interactions)),
  if (nrow(significant_interactions)) paste(
    "Significant interactions:",
    paste(paste(significant_interactions$score, significant_interactions$modifier,
                sprintf("q=%.3g", significant_interactions$FDR), sep = "/"), collapse = "; ")
  ) else "Significant interactions: none",
  paste("Best median repeated-CV AUC:", best_cv$model, sprintf("%.3f", best_cv$median_AUC)),
  "Response is a post-treatment variable; all multiomics interaction results are exploratory associations, not causal treatment-effect estimates.",
  "No network, score, or multiomics feature was selected according to significance yield."
)
writeLines(run_summary, file.path(log_dir, "phase3_replication_multiomics_run_summary.txt"))
write_csv_safe(primary_specificity, file.path(table_dir, "primary_replication_specificity_summary.csv"))
capture.output(sessionInfo(), file = file.path(log_dir, "sessionInfo_phase3_replication_multiomics.txt"))
message("Phase 3 replication/multiomics analysis completed successfully.")
