#!/usr/bin/env Rscript

# ==============================================================================
# File: 04_run_expression_qc.R
# Purpose: Perform expression-matrix quality control and prepare aligned analysis objects.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - TCGA Xena expression and clinical matrices plus the harmonized clinical cohort.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; response level order; expression variance,
#     center-size, PCA retention/association/outlier and correlation-outlier settings.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Quality-controlled expression RDS, QC tables, and diagnostic figures.
# Reproducibility:
#   - Sample/gene alignment is checked; outliers are flagged, not removed here.
#   - Robust PCA uses the existing RNG stream; ESTIMATE remains expression-derived.
# ==============================================================================

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(readr)
  library(matrixStats)
  library(ggplot2)
  library(estimate)
})

# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)
analysis_config <- config$analysis
expression_config <- analysis_config$expression
seed <- analysis_config$random_seeds$default
configure_reproducible_runtime(seed)
pca_association_component_count <- required_analysis_value(
  analysis_config, "expression.pca_association_component_count"
)
if (!is.numeric(pca_association_component_count) || length(pca_association_component_count) != 1L ||
    !is.finite(pca_association_component_count) || pca_association_component_count < 1 ||
    pca_association_component_count != floor(pca_association_component_count) ||
    pca_association_component_count > expression_config$pca_component_count) {
  stop("expression.pca_association_component_count must be a positive integer within the retained PCA range.")
}
pca_association_component_count <- as.integer(pca_association_component_count)

xena_dir <- config$paths$xena_dir
expression_path <- file.path(xena_dir, "agilent_pancan", "TCGA.OV.HT_HG-U133A.gz")
clinical_matrix_path <- file.path(xena_dir, "TCGA.OV.sampleMap", "OV_clinicalMatrix")
processed_dir <- config$paths$processed_data_dir
phase0_path <- file.path(processed_dir, "tcga_ov_phase0_clinical.csv")

table_dir <- file.path(config$paths$results_dir, "tables", "expression_qc")
figure_dir <- file.path(config$paths$results_dir, "figures", "expression_qc")
log_dir <- file.path(project_dir, "logs")
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

required <- c(expression_path, clinical_matrix_path, phase0_path)
if (!all(file.exists(required))) stop("Missing required input: ", paste(required[!file.exists(required)], collapse = ", "))

# ---- Analysis workflow --------------------------------------------------------
message("Reading expression matrix...")
expr_dt <- fread(expression_path, data.table = FALSE, check.names = FALSE)
gene_col <- names(expr_dt)[1]
genes <- as.character(expr_dt[[gene_col]])
expr <- as.matrix(expr_dt[, -1, drop = FALSE])
storage.mode(expr) <- "double"
rownames(expr) <- genes
matrix_samples_total <- ncol(expr)
rm(expr_dt)

phase0 <- read_csv(phase0_path, show_col_types = FALSE)
clinical_raw <- fread(clinical_matrix_path, data.table = FALSE, check.names = FALSE, na.strings = c("", "NA", "[Unknown]", "[Not Available]"))
clinical_cov <- clinical_raw %>%
  filter(sample_type == "Primary Tumor") %>%
  transmute(
    sample = sampleID,
    tissue_source_site,
    diagnosis_year = suppressWarnings(as.numeric(year_of_initial_pathologic_diagnosis)),
    collection_days = suppressWarnings(as.numeric(days_to_collection)),
    form_completion_date
  ) %>%
  distinct(sample, .keep_all = TRUE)

pheno <- phase0 %>%
  filter(!is.na(response4), sample %in% colnames(expr)) %>%
  left_join(clinical_cov, by = "sample") %>%
  mutate(
    response4 = factor(response4, levels = analysis_config$response$four_levels),
    response_m2 = factor(response_m2, levels = analysis_config$response$objective_response_levels),
    response_m3 = factor(response_m3, levels = analysis_config$response$cr_threshold_levels),
    stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
    residual_group = factor(residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm"))
  )

if (anyDuplicated(pheno$sample)) stop("Duplicated samples in phenotype table")
if (anyDuplicated(rownames(expr))) stop("Duplicated gene identifiers in expression matrix")
expr <- expr[, pheno$sample, drop = FALSE]
if (!identical(colnames(expr), pheno$sample)) stop("Expression/phenotype alignment failed")

# Collapse small centers while preserving the major collection sites.
tss_counts <- table(pheno$tissue_source_site)
major_tss <- names(tss_counts)[tss_counts >= expression_config$center_minimum_samples]
pheno <- pheno %>%
  mutate(
    tss_collapsed = if_else(is.na(tissue_source_site), "Missing",
                            if_else(tissue_source_site %in% major_tss, tissue_source_site, "Other")),
    tss_collapsed = factor(tss_collapsed),
    stage_missing = factor(if_else(is.na(stage_group), "Missing", as.character(stage_group))),
    residual_missing = factor(if_else(is.na(residual_group), "Missing", as.character(residual_group)))
  )

# ESTIMATE purity is expression-derived and is retained only for sensitivity analyses.
message("Calculating ESTIMATE scores...")
alias <- sprintf("S%04d", seq_len(ncol(expr)))
alias_map <- tibble(alias = alias, sample = colnames(expr))
estimate_input <- tempfile(pattern = "estimate_input_", tmpdir = processed_dir, fileext = ".tsv")
estimate_common <- tempfile(pattern = "estimate_common_", tmpdir = processed_dir, fileext = ".gct")
estimate_output <- tempfile(pattern = "estimate_scores_", tmpdir = processed_dir, fileext = ".gct")
estimate_df <- data.frame(GeneSymbol = rownames(expr), expr, check.names = FALSE)
names(estimate_df)[-1] <- alias
write.table(estimate_df, estimate_input, sep = "\t", quote = FALSE, row.names = FALSE)
filterCommonGenes(estimate_input, estimate_common, id = "GeneSymbol")
estimateScore(estimate_common, estimate_output, platform = "affymetrix")
estimate_scores_raw <- read.delim(estimate_output, skip = 2, row.names = 1, check.names = FALSE)
estimate_scores_raw <- estimate_scores_raw[, -1, drop = FALSE]
estimate_scores <- as.data.frame(t(estimate_scores_raw), check.names = FALSE) %>%
  tibble::rownames_to_column("alias") %>%
  left_join(alias_map, by = "alias") %>%
  select(sample, StromalScore, ImmuneScore, ESTIMATEScore, TumorPurity)
unlink(c(estimate_input, estimate_common, estimate_output))
pheno <- pheno %>% left_join(estimate_scores, by = "sample")

# Gene- and sample-level summaries.
gene_sd <- rowSds(expr)
gene_mad <- rowMads(expr)
gene_summary <- tibble(
  gene = rownames(expr),
  mean = rowMeans(expr),
  sd = gene_sd,
  mad = gene_mad,
  min = rowMins(expr),
  max = rowMaxs(expr)
)
variance_cutoff <- unname(quantile(gene_sd, expression_config$lower_variance_fraction, na.rm = TRUE))
model_genes <- gene_summary$gene[
  gene_summary$sd > variance_cutoff & gene_summary$sd > expression_config$minimum_gene_sd
]

sample_cor <- cor(expr, method = "pearson", use = "pairwise.complete.obs")
diag(sample_cor) <- NA_real_
median_correlation <- colMedians(sample_cor, na.rm = TRUE)
sample_median <- colMedians(expr)
sample_iqr <- colIQRs(expr)

# PCA uses the configured high-variance subset; plotting dimensions remain display constants.
top_n <- min(expression_config$pca_gene_count, nrow(expr))
top_genes <- names(sort(gene_sd, decreasing = TRUE))[seq_len(top_n)]
pca <- prcomp(t(expr[top_genes, , drop = FALSE]), center = TRUE, scale. = FALSE)
pca_var <- 100 * pca$sdev^2 / sum(pca$sdev^2)
pc_scores <- as.data.frame(pca$x[, seq_len(min(expression_config$pca_component_count, ncol(pca$x))), drop = FALSE]) %>%
  tibble::rownames_to_column("sample")

required_pc_names <- paste0("PC", seq_len(max(pca_association_component_count,
                                              expression_config$pca_outlier_component_count)))
if (!all(required_pc_names %in% names(pc_scores))) {
  stop("Retained PCA scores lack required association/outlier components: ",
       paste(setdiff(required_pc_names, names(pc_scores)), collapse = ", "))
}
outlier_pc_names <- paste0("PC", seq_len(expression_config$pca_outlier_component_count))
robust_fit <- tryCatch(MASS::cov.rob(pc_scores[, outlier_pc_names], method = "mve"), error = function(e) NULL)
if (is.null(robust_fit)) {
  pca_distance <- rep(NA_real_, nrow(pc_scores))
  pca_outlier <- rep(FALSE, nrow(pc_scores))
} else {
  pca_distance <- mahalanobis(pc_scores[, outlier_pc_names], robust_fit$center, robust_fit$cov)
  pca_outlier <- pca_distance > qchisq(
    expression_config$pca_outlier_probability,
    df = expression_config$pca_outlier_component_count
  )
}

corr_center <- median(median_correlation, na.rm = TRUE)
corr_scale <- mad(median_correlation, center = corr_center, constant = 1, na.rm = TRUE)
corr_outlier <- if (corr_scale > 0) {
  median_correlation < corr_center - expression_config$correlation_outlier_mad_multiplier * corr_scale
} else {
  rep(FALSE, length(median_correlation))
}

sample_qc <- tibble(
  sample = colnames(expr),
  median_expression = sample_median,
  expression_iqr = sample_iqr,
  median_sample_correlation = median_correlation,
  robust_pca_distance = pca_distance,
  correlation_outlier = corr_outlier,
  pca_outlier = pca_outlier,
  qc_outlier = corr_outlier | pca_outlier
) %>%
  left_join(pheno %>% select(sample, response4, response_m3, stage_group, residual_group, tissue_source_site, tss_collapsed, diagnosis_year, TumorPurity), by = "sample")
pheno <- pheno %>% left_join(sample_qc %>% select(sample, qc_outlier), by = "sample")

pc_scores <- pc_scores %>%
  left_join(pheno, by = "sample")

# Numeric covariates use a slope test; categorical covariates use the omnibus
# ANOVA F test. BH adjustment below remains across PCs separately per covariate.
association_one <- function(pc, variable, data) {
  dat <- data.frame(score = data[[pc]], variable = data[[variable]])
  dat <- dat[complete.cases(dat), , drop = FALSE]
  if (nrow(dat) < expression_config$minimum_association_samples || length(unique(dat$variable)) < 2) {
    return(tibble(PC = pc, variable = variable, n = nrow(dat), df = NA_integer_, R2 = NA_real_, p_value = NA_real_))
  }
  if (is.numeric(dat$variable)) {
    fit <- lm(score ~ variable, data = dat)
    p <- summary(fit)$coefficients[2, 4]
    df <- 1L
  } else {
    dat$variable <- droplevels(factor(dat$variable))
    fit <- lm(score ~ variable, data = dat)
    a <- anova(fit)
    p <- a$`Pr(>F)`[1]
    df <- a$Df[1]
  }
  tibble(PC = pc, variable = variable, n = nrow(dat), df = df, R2 = summary(fit)$r.squared, p_value = p)
}

association_variables <- c(
  "response4", "response_m3", "age", "stage_group", "residual_group",
  "tss_collapsed", "diagnosis_year", "TumorPurity", "ImmuneScore", "StromalScore"
)
pca_associations <- bind_rows(lapply(paste0("PC", seq_len(pca_association_component_count)), function(pc) {
  bind_rows(lapply(association_variables, function(v) association_one(pc, v, pc_scores)))
})) %>%
  group_by(variable) %>%
  mutate(FDR = p.adjust(p_value, method = "BH")) %>%
  ungroup()

matrix_summary <- tibble(
  metric = c(
    "genes_total", "samples_total_matrix", "response_known_primary_samples", "missing_expression_values",
    "duplicate_gene_ids", "duplicate_sample_ids", "genes_retained_after_10pct_variance_filter",
    "variance_filter_sd_cutoff", "qc_outlier_samples", "major_tss_levels", "estimate_purity_available"
  ),
  value = c(
    nrow(expr), matrix_samples_total, ncol(expr), sum(is.na(expr)),
    anyDuplicated(rownames(expr)), anyDuplicated(colnames(expr)), length(model_genes),
    variance_cutoff, sum(sample_qc$qc_outlier), length(major_tss), sum(!is.na(pheno$TumorPurity))
  )
)

write_csv(matrix_summary, file.path(table_dir, "matrix_summary.csv"))
write_csv(gene_summary, file.path(table_dir, "gene_expression_summary.csv"))
write_csv(sample_qc, file.path(table_dir, "sample_qc_metrics.csv"))
write_csv(pc_scores %>% select(sample, starts_with("PC")), file.path(table_dir, "pca_scores.csv"))
write_csv(tibble(PC = paste0("PC", seq_along(pca_var)), variance_pct = pca_var), file.path(table_dir, "pca_variance.csv"))
write_csv(pca_associations, file.path(table_dir, "pca_covariate_associations.csv"))
write_csv(estimate_scores, file.path(table_dir, "estimate_scores.csv"))
write_csv(pheno, file.path(processed_dir, "tcga_ov_expression_phenotype.csv"), na = "")

saveRDS(
  list(
    expression = expr,
    phenotype = pheno,
    model_genes = model_genes,
    pca = list(scores = pc_scores, variance_pct = pca_var),
    sample_qc = sample_qc,
    source = list(
      expression_path = file.path(
        "xena_dir", "agilent_pancan", basename(expression_path)
      ),
      clinical_matrix_path = file.path(
        "xena_dir", "TCGA.OV.sampleMap", basename(clinical_matrix_path)
      ),
      phase0_path = file.path("processed_data_dir", basename(phase0_path))
    )
  ),
  file.path(processed_dir, "tcga_ov_u133a_expression_qc.rds"),
  compress = "xz"
)

plot_pca <- function(color_var, file_stub, title) {
  d <- pc_scores %>% filter(!is.na(.data[[color_var]]))
  p <- ggplot(d, aes(x = PC1, y = PC2, color = .data[[color_var]])) +
    geom_point(size = 2, alpha = 0.8) +
    labs(
      title = title,
      x = sprintf("PC1 (%.1f%%)", pca_var[1]),
      y = sprintf("PC2 (%.1f%%)", pca_var[2]),
      color = color_var
    ) +
    theme_bw(base_size = 11) +
    theme(legend.position = "right")
  ggsave(file.path(figure_dir, paste0(file_stub, ".png")), p, width = 8, height = 6, dpi = 180)
  ggsave(file.path(figure_dir, paste0(file_stub, ".pdf")), p, width = 8, height = 6)
}

plot_pca("response4", "PCA_response4", "TCGA-OV U133A PCA by response")
plot_pca("tss_collapsed", "PCA_TSS", "TCGA-OV U133A PCA by tissue source site")
plot_pca("residual_missing", "PCA_residual", "TCGA-OV U133A PCA by residual disease")

p_corr <- ggplot(sample_qc, aes(x = median_sample_correlation, fill = qc_outlier)) +
  geom_histogram(bins = 35, color = "white") +
  scale_fill_manual(values = c(`FALSE` = "#4C78A8", `TRUE` = "#E45756")) +
  labs(x = "Median correlation with other samples", y = "Samples", fill = "QC outlier") +
  theme_bw(base_size = 11)
ggsave(file.path(figure_dir, "sample_median_correlation.png"), p_corr, width = 7, height = 5, dpi = 180)

p_dist <- sample_qc %>%
  select(sample, median_expression, expression_iqr) %>%
  tidyr::pivot_longer(-sample, names_to = "metric", values_to = "value") %>%
  ggplot(aes(x = value)) +
  geom_histogram(bins = 35, fill = "#4C78A8", color = "white") +
  facet_wrap(~metric, scales = "free") +
  theme_bw(base_size = 11) +
  labs(x = NULL, y = "Samples")
ggsave(file.path(figure_dir, "sample_expression_distributions.png"), p_dist, width = 8, height = 4.5, dpi = 180)

p_purity <- ggplot(pheno, aes(x = response4, y = TumorPurity, fill = response4)) +
  geom_boxplot(outlier.shape = NA, alpha = 0.8) +
  geom_jitter(width = 0.18, alpha = 0.25, size = 0.8) +
  guides(fill = "none") +
  theme_bw(base_size = 11) +
  labs(x = "Response", y = "ESTIMATE tumor purity")
ggsave(file.path(figure_dir, "purity_by_response.png"), p_purity, width = 6.5, height = 5, dpi = 180)

capture.output(sessionInfo(), file = file.path(log_dir, "sessionInfo_expression_qc.txt"))
writeLines(
  c(
    paste("Expression QC completed:", format(Sys.time(), tz = "UTC")),
    paste("Genes:", nrow(expr)),
    paste("Response-known samples:", ncol(expr)),
    paste("QC outliers flagged:", sum(sample_qc$qc_outlier)),
    paste("Model genes after variance filtering:", length(model_genes)),
    paste("ESTIMATE purity available:", sum(!is.na(pheno$TumorPurity))),
    "Outliers are flagged but not automatically removed; topology analysis includes an exclusion sensitivity analysis.",
    "ESTIMATE purity is expression-derived and must not be treated as an independent measurement."
  ),
  file.path(log_dir, "expression_qc_run_summary.txt")
)

message("Expression QC completed successfully.")
