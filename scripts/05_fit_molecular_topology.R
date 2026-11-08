#!/usr/bin/env Rscript

# ==============================================================================
# File: 05_fit_molecular_topology.R
# Purpose: Fit gene- and pathway-level molecular response-topology models in TCGA-OV.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Quality-controlled expression object and MSigDB Hallmark gene sets.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; response level order; expression MSigDB
#     selectors and gene-set bounds; molecular FDR/effect/constraint thresholds,
#     maximum_surrogate_variables and hallmark_hypothesis_axes.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Limma, GSVA, and molecular-topology result tables and figures.
# Reproducibility:
#   - Reuses the Hallmark cache; GSVA runs serially with the Gaussian kernel.
#   - SVA and primary/outlier/purity analyses keep their existing execution order.
# ==============================================================================

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(limma)
  library(sva)
  library(GSVA)
  library(BiocParallel)
  library(msigdbr)
  library(ggplot2)
  library(pheatmap)
})

# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)
analysis_config <- config$analysis
expression_config <- analysis_config$expression
molecular_config <- analysis_config$molecular
seed <- analysis_config$random_seeds$default
configure_reproducible_runtime(seed)
maximum_surrogate_variables <- required_analysis_value(
  analysis_config, "molecular.maximum_surrogate_variables"
)
if (!is.numeric(maximum_surrogate_variables) || length(maximum_surrogate_variables) != 1L ||
    !is.finite(maximum_surrogate_variables) || maximum_surrogate_variables < 0 ||
    maximum_surrogate_variables != floor(maximum_surrogate_variables)) {
  stop("molecular.maximum_surrogate_variables must be a non-negative integer.")
}
# Preserve the original integer cap (10L), not YAML's incidental scalar type.
maximum_surrogate_variables <- as.integer(maximum_surrogate_variables)
hallmark_hypothesis_axes <- required_analysis_value(analysis_config, "molecular.hallmark_hypothesis_axes")
if (!is.list(hallmark_hypothesis_axes) || !identical(names(hallmark_hypothesis_axes),
    c("DDR_replication_apoptosis", "CAF_ECM_EMT", "immune_spatial_exclusion"))) {
  stop("molecular.hallmark_hypothesis_axes must contain the three ordered hypothesis axes.")
}
for (axis in names(hallmark_hypothesis_axes)) {
  features <- unlist(hallmark_hypothesis_axes[[axis]], use.names = FALSE)
  if (!is.character(features) || !length(features) || anyNA(features) ||
      any(!nzchar(features)) || anyDuplicated(features)) {
    stop("Invalid Hallmark feature vector for hypothesis axis: ", axis)
  }
  hallmark_hypothesis_axes[[axis]] <- features
}
msigdb_fields <- c("msigdb_species", "msigdb_hallmark_collection")
for (field in msigdb_fields) {
  value <- required_analysis_value(analysis_config, paste0("expression.", field))
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    stop("Invalid MSigDB source setting: expression.", field)
  }
}

qc_rds <- file.path(config$paths$processed_data_dir, "tcga_ov_u133a_expression_qc.rds")
geneset_rds <- file.path(config$paths$processed_data_dir, "msigdb_hallmark_human.rds")
table_dir <- file.path(config$paths$results_dir, "tables", "molecular_topology")
figure_dir <- file.path(config$paths$results_dir, "figures", "molecular_topology")
log_dir <- file.path(project_dir, "logs")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(qc_rds)) stop("Run scripts/04_run_expression_qc.R first")
qc <- readRDS(qc_rds)
expr_all <- qc$expression
pheno_all <- qc$phenotype
model_genes <- intersect(qc$model_genes, rownames(expr_all))
expr_model <- expr_all[model_genes, , drop = FALSE]

if (!file.exists(geneset_rds)) {
  message("Preparing Hallmark gene sets...")
  hallmark_df <- msigdbr(species = expression_config$msigdb_species,
                        collection = expression_config$msigdb_hallmark_collection)
  hallmark <- split(hallmark_df$gene_symbol, hallmark_df$gs_name)
  hallmark <- lapply(hallmark, unique)
  saveRDS(hallmark, geneset_rds, compress = "xz")
} else {
  hallmark <- readRDS(geneset_rds)
}
hallmark <- lapply(hallmark, intersect, y = rownames(expr_all))
hallmark <- hallmark[lengths(hallmark) >= expression_config$minimum_gene_set_size]

# ---- Analysis workflow --------------------------------------------------------
message("Calculating Hallmark GSVA scores...")
gsva_param <- gsvaParam(
  exprData = expr_all,
  geneSets = hallmark,
  minSize = expression_config$minimum_gene_set_size,
  maxSize = expression_config$maximum_gene_set_size,
  kcdf = "Gaussian",
  sparse = FALSE
)
hallmark_scores <- gsva(gsva_param, verbose = FALSE, BPPARAM = SerialParam())

prepare_analysis <- function(expression, phenotype, exclude_qc_outliers = FALSE) {
  ph <- phenotype %>%
    mutate(
      response4 = factor(response4, levels = analysis_config$response$four_levels),
      response_m2 = factor(response_m2, levels = analysis_config$response$objective_response_levels),
      response_m3 = factor(response_m3, levels = analysis_config$response$cr_threshold_levels),
      stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
      residual_group = factor(residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm")),
      tss_collapsed = droplevels(factor(tss_collapsed)),
      age_z = as.numeric(scale(age)),
      diagnosis_year_z = as.numeric(scale(diagnosis_year))
    ) %>%
    filter(
      !is.na(response4), !is.na(age_z), !is.na(stage_group), !is.na(residual_group),
      !is.na(tss_collapsed), !is.na(diagnosis_year_z)
    )
  if (exclude_qc_outliers) ph <- ph %>% filter(!qc_outlier)
  expression <- expression[, ph$sample, drop = FALSE]
  if (!identical(colnames(expression), ph$sample)) stop("Expression and phenotype misalignment")
  list(expression = expression, phenotype = ph)
}

make_designs <- function(ph, sv = NULL, include_purity = FALSE) {
  covars <- c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z")
  if (include_purity) covars <- c(covars, "TumorPurity")
  base_rhs <- paste(covars, collapse = " + ")
  if (!is.null(sv) && ncol(sv) > 0) {
    for (j in seq_len(ncol(sv))) ph[[paste0("SV", j)]] <- sv[, j]
    base_rhs <- paste(c(base_rhs, paste0("SV", seq_len(ncol(sv)))), collapse = " + ")
  }
  build <- function(response) {
    d <- model.matrix(as.formula(paste("~", response, "+", base_rhs)), data = ph)
    colnames(d) <- make.names(colnames(d), unique = TRUE)
    d
  }
  list(
    pheno = ph,
    M1 = build("response4"),
    M2 = build("response_m2"),
    M3 = build("response_m3")
  )
}

# Protect the four-state response in the full SVA model; estimate nuisance structure
# against the same clinical null, then cap Leek's estimate without changing sample order.
estimate_surrogates <- function(expression, ph, include_purity = FALSE, max_sv = maximum_surrogate_variables) {
  covars <- c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z")
  if (include_purity) covars <- c(covars, "TumorPurity")
  cov_rhs <- paste(covars, collapse = " + ")
  mod <- model.matrix(as.formula(paste("~ response4 +", cov_rhs)), data = ph)
  mod0 <- model.matrix(as.formula(paste("~", cov_rhs)), data = ph)
  n_sv_raw <- num.sv(expression, mod, method = "leek")
  n_sv <- min(as.integer(n_sv_raw), max_sv)
  if (!is.finite(n_sv) || n_sv < 1) {
    return(list(sv = matrix(numeric(0), nrow = nrow(ph), ncol = 0), n_sv_raw = n_sv_raw, n_sv_used = 0L))
  }
  sva_fit <- sva(expression, mod = mod, mod0 = mod0, n.sv = n_sv)
  sv <- sva_fit$sv
  rownames(sv) <- ph$sample
  list(sv = sv, n_sv_raw = n_sv_raw, n_sv_used = ncol(sv))
}

fit_with_design <- function(expression, design) {
  fit <- lmFit(expression, design)
  eBayes(fit, trend = TRUE, robust = TRUE)
}

extract_single <- function(fit, coefficient) {
  tt <- topTable(fit, coef = coefficient, number = Inf, sort.by = "none")
  tibble(
    feature = rownames(tt),
    logFC = tt$logFC,
    AveExpr = tt$AveExpr,
    t = tt$t,
    p_value = tt$P.Value,
    FDR = tt$adj.P.Val,
    B = tt$B
  )
}

extract_global <- function(fit, coefficients, prefix) {
  tt <- topTable(fit, coef = coefficients, number = Inf, sort.by = "none")
  tibble(
    feature = rownames(tt),
    !!paste0(prefix, "_F") := tt$F,
    !!paste0(prefix, "_p") := tt$P.Value,
    !!paste0(prefix, "_FDR") := tt$adj.P.Val
  )
}

extract_constraint <- function(fit, design, expressions, prefix) {
  contrast <- makeContrasts(contrasts = expressions, levels = design)
  cf <- contrasts.fit(fit, contrast)
  cf <- eBayes(cf, trend = TRUE, robust = TRUE)
  tt <- topTable(cf, coef = seq_len(ncol(contrast)), number = Inf, sort.by = "none")
  tibble(
    feature = rownames(tt),
    !!paste0(prefix, "_F") := tt$F,
    !!paste0(prefix, "_p") := tt$P.Value,
    !!paste0(prefix, "_FDR") := tt$adj.P.Val
  )
}

# Per-feature Gaussian information criteria use unmoderated residual RSS and
# design rank, omitting model-common constants. Keep the epsilon floor and rank
# penalty exactly as before; limma's moderated variance is not used in these ICs.
model_ic <- function(expression, fit, design) {
  fitted <- fit$coefficients %*% t(design)
  rss <- rowSums((expression - fitted)^2)
  n <- ncol(expression)
  k <- qr(design)$rank
  tibble(
    feature = rownames(expression),
    RSS = rss,
    AIC = n * log(pmax(rss / n, .Machine$double.eps)) + 2 * k,
    BIC = n * log(pmax(rss / n, .Machine$double.eps)) + log(n) * k
  )
}

classify_topology <- function(tab, effect_cutoff = molecular_config$gene_effect_size_threshold) {
  tab %>%
    mutate(
      best_BIC_model = c("M1", "M2", "M3")[max.col(-as.matrix(select(., BIC_M1, BIC_M2, BIC_M3)), ties.method = "first")],
      delta_BIC_M1_vs_M3 = BIC_M1 - BIC_M3,
      delta_BIC_M2_vs_M3 = BIC_M2 - BIC_M3,
      topology_class = case_when(
        M3_FDR < molecular_config$fdr_threshold & abs(M3_logFC) >= effect_cutoff &
          plateau_constraint_FDR >= molecular_config$constraint_nonrejection_threshold &
          best_BIC_model == "M3" ~ "threshold_supported",
        M1_global_FDR < molecular_config$fdr_threshold &
          plateau_constraint_FDR < molecular_config$fdr_threshold &
          best_BIC_model == "M1" ~ "four_state_heterogeneous",
        M2_FDR < molecular_config$fdr_threshold & abs(M2_logFC) >= effect_cutoff &
          ORR_constraint_FDR >= molecular_config$constraint_nonrejection_threshold &
          best_BIC_model == "M2" ~ "ORR_supported",
        M3_FDR < molecular_config$fdr_threshold & abs(M3_logFC) >= effect_cutoff ~ "CR_associated_unresolved",
        M1_global_FDR < molecular_config$fdr_threshold ~ "four_state_signal_unresolved",
        TRUE ~ "no_FDR_signal"
      )
    )
}

run_topology <- function(expression, phenotype, analysis_name, exclude_qc_outliers = FALSE, include_purity = FALSE) {
  prepared <- prepare_analysis(expression, phenotype, exclude_qc_outliers)
  y <- prepared$expression
  ph <- prepared$phenotype
  if (include_purity && anyNA(ph$TumorPurity)) stop("Missing purity in purity sensitivity analysis")

  message("Estimating surrogate variables for ", analysis_name, "...")
  sv_info <- estimate_surrogates(y, ph, include_purity = include_purity)
  sv <- sv_info$sv
  if (ncol(sv) > 0) sv <- sv[ph$sample, , drop = FALSE]
  designs <- make_designs(ph, sv = sv, include_purity = include_purity)

  fit1 <- fit_with_design(y, designs$M1)
  fit2 <- fit_with_design(y, designs$M2)
  fit3 <- fit_with_design(y, designs$M3)

  m1_coef <- c("response4PR", "response4SD", "response4PD")
  m2_coef <- "response_m2SD.PD"
  m3_coef <- "response_m3Non.CR"
  if (!all(m1_coef %in% colnames(designs$M1))) stop("M1 response coefficients unavailable")
  if (!m2_coef %in% colnames(designs$M2)) stop("M2 response coefficient unavailable")
  if (!m3_coef %in% colnames(designs$M3)) stop("M3 response coefficient unavailable")

  m3 <- extract_single(fit3, m3_coef) %>%
    rename(M3_logFC = logFC, M3_AveExpr = AveExpr, M3_t = t, M3_p = p_value, M3_FDR = FDR, M3_B = B)
  m2 <- extract_single(fit2, m2_coef) %>%
    rename(M2_logFC = logFC, M2_AveExpr = AveExpr, M2_t = t, M2_p = p_value, M2_FDR = FDR, M2_B = B)
  m1_global <- extract_global(fit1, m1_coef, "M1_global")
  plateau <- extract_constraint(
    fit1, designs$M1,
    c("response4PR-response4SD", "response4PR-response4PD"),
    "plateau_constraint"
  )
  orr <- extract_constraint(
    fit1, designs$M1,
    c("response4PR", "response4SD-response4PD"),
    "ORR_constraint"
  )

  ic1 <- model_ic(y, fit1, designs$M1) %>% rename(RSS_M1 = RSS, AIC_M1 = AIC, BIC_M1 = BIC)
  ic2 <- model_ic(y, fit2, designs$M2) %>% rename(RSS_M2 = RSS, AIC_M2 = AIC, BIC_M2 = BIC)
  ic3 <- model_ic(y, fit3, designs$M3) %>% rename(RSS_M3 = RSS, AIC_M3 = AIC, BIC_M3 = BIC)

  result <- m3 %>%
    left_join(m2, by = "feature") %>%
    left_join(m1_global, by = "feature") %>%
    left_join(plateau, by = "feature") %>%
    left_join(orr, by = "feature") %>%
    left_join(ic1, by = "feature") %>%
    left_join(ic2, by = "feature") %>%
    left_join(ic3, by = "feature") %>%
    classify_topology() %>%
    mutate(analysis = analysis_name, n = ncol(y), n_sv = sv_info$n_sv_used)

  design_summary <- tibble(
    analysis = analysis_name,
    n_samples = ncol(y),
    n_features = nrow(y),
    CR = sum(ph$response4 == "CR"),
    PR = sum(ph$response4 == "PR"),
    SD = sum(ph$response4 == "SD"),
    PD = sum(ph$response4 == "PD"),
    qc_outliers_excluded = exclude_qc_outliers,
    purity_adjusted = include_purity,
    n_sv_raw = sv_info$n_sv_raw,
    n_sv_used = sv_info$n_sv_used,
    rank_M1 = qr(designs$M1)$rank,
    rank_M2 = qr(designs$M2)$rank,
    rank_M3 = qr(designs$M3)$rank
  )

  list(result = result, design_summary = design_summary, phenotype = ph, sv = sv)
}

message("Running primary and sensitivity gene-level topology analyses...")
gene_primary <- run_topology(expr_model, pheno_all, "primary_clinical_SVA")
gene_clean <- run_topology(expr_model, pheno_all, "exclude_QC_outliers", exclude_qc_outliers = TRUE)
gene_purity <- run_topology(expr_model, pheno_all, "add_ESTIMATE_purity", include_purity = TRUE)

gene_results <- bind_rows(gene_primary$result, gene_clean$result, gene_purity$result)
gene_designs <- bind_rows(gene_primary$design_summary, gene_clean$design_summary, gene_purity$design_summary)
write_csv(gene_results, file.path(table_dir, "gene_topology_all_analyses.csv"))
write_csv(gene_designs, file.path(table_dir, "topology_design_summary.csv"))

message("Running primary and sensitivity pathway-level topology analyses...")
pathway_primary <- run_topology(hallmark_scores, pheno_all, "primary_clinical_SVA")
pathway_clean <- run_topology(hallmark_scores, pheno_all, "exclude_QC_outliers", exclude_qc_outliers = TRUE)
pathway_purity <- run_topology(hallmark_scores, pheno_all, "add_ESTIMATE_purity", include_purity = TRUE)
pathway_results <- bind_rows(pathway_primary$result, pathway_clean$result, pathway_purity$result)

# Expand ordered axis mappings without reordering pathways or duplicating joins.
axis_map <- bind_rows(lapply(names(hallmark_hypothesis_axes), function(axis) {
  tibble(feature = hallmark_hypothesis_axes[[axis]], hypothesis_axis = axis)
}))
if (anyDuplicated(axis_map$feature)) stop("Hallmark hypothesis axes must not assign a feature more than once.")
pathway_results <- pathway_results %>%
  left_join(axis_map, by = "feature") %>%
  mutate(hypothesis_axis = if_else(is.na(hypothesis_axis), "other_hallmark", hypothesis_axis))
write_csv(pathway_results, file.path(table_dir, "hallmark_pathway_topology_all_analyses.csv"))

summarise_topology <- function(result, level) {
  result %>%
    count(analysis, topology_class, name = "n_features") %>%
    group_by(analysis) %>%
    mutate(level = level, pct_features = 100 * n_features / sum(n_features)) %>%
    ungroup()
}

topology_counts <- bind_rows(
  summarise_topology(gene_results, "gene"),
  summarise_topology(pathway_results, "hallmark_pathway")
)
write_csv(topology_counts, file.path(table_dir, "topology_class_counts.csv"))

bic_counts <- bind_rows(
  gene_results %>% count(analysis, best_BIC_model, name = "n_features") %>% mutate(level = "gene"),
  pathway_results %>% count(analysis, best_BIC_model, name = "n_features") %>% mutate(level = "hallmark_pathway")
) %>%
  group_by(analysis, level) %>%
  mutate(pct_features = 100 * n_features / sum(n_features)) %>%
  ungroup()
write_csv(bic_counts, file.path(table_dir, "best_BIC_model_counts.csv"))

primary_genes <- gene_results %>% filter(analysis == "primary_clinical_SVA")
primary_pathways <- pathway_results %>% filter(analysis == "primary_clinical_SVA")

# Cross-analysis robustness table for candidates.
robust_gene <- gene_results %>%
  mutate(
    m3_direction = sign(M3_logFC),
    m3_significant = M3_FDR < molecular_config$fdr_threshold &
      abs(M3_logFC) >= molecular_config$gene_effect_size_threshold,
    threshold_supported_flag = topology_class == "threshold_supported"
  ) %>%
  group_by(feature) %>%
  summarise(
    analyses = n(),
    direction_consistent = n_distinct(m3_direction) == 1,
    M3_significant_in_all = all(m3_significant),
    threshold_supported_in_all = all(threshold_supported_flag),
    median_M3_logFC = median(M3_logFC),
    max_M3_FDR = max(M3_FDR),
    min_plateau_constraint_FDR = min(plateau_constraint_FDR),
    .groups = "drop"
  ) %>%
  arrange(desc(threshold_supported_in_all), desc(M3_significant_in_all), max_M3_FDR)
write_csv(robust_gene, file.path(table_dir, "gene_topology_robustness.csv"))

robust_pathway <- pathway_results %>%
  mutate(
    m3_direction = sign(M3_logFC),
    m3_significant = M3_FDR < molecular_config$fdr_threshold,
    threshold_supported_flag = topology_class == "threshold_supported"
  ) %>%
  group_by(feature, hypothesis_axis) %>%
  summarise(
    analyses = n(),
    direction_consistent = n_distinct(m3_direction) == 1,
    M3_significant_in_all = all(m3_significant),
    threshold_supported_in_all = all(threshold_supported_flag),
    median_M3_logFC = median(M3_logFC),
    max_M3_FDR = max(M3_FDR),
    min_plateau_constraint_FDR = min(plateau_constraint_FDR),
    .groups = "drop"
  ) %>%
  arrange(desc(threshold_supported_in_all), desc(M3_significant_in_all), max_M3_FDR)
write_csv(robust_pathway, file.path(table_dir, "hallmark_topology_robustness.csv"))

# Figures.
volcano_data <- primary_genes %>%
  mutate(
    neglog10FDR = -log10(pmax(M3_FDR, 1e-300)),
    label = if_else(rank(M3_p, ties.method = "first") <= 15, feature, NA_character_)
  )
p_volcano <- ggplot(volcano_data, aes(x = M3_logFC, y = neglog10FDR, color = topology_class)) +
  geom_point(alpha = 0.55, size = 1.2) +
  geom_vline(xintercept = c(-molecular_config$gene_effect_size_threshold,
                            molecular_config$gene_effect_size_threshold), linetype = 2, color = "grey50") +
  geom_hline(yintercept = -log10(molecular_config$fdr_threshold), linetype = 2, color = "grey50") +
  ggrepel::geom_text_repel(
    data = volcano_data %>% filter(!is.na(label)),
    aes(label = label), size = 3, max.overlaps = 20, box.padding = 0.3
  ) +
  theme_bw(base_size = 11) +
  labs(x = "M3 log2 expression difference (NCR - CR)", y = "-log10 FDR", color = "Topology")
ggsave(file.path(figure_dir, "M3_gene_volcano.png"), p_volcano, width = 9, height = 6.5, dpi = 180)

top_plot <- topology_counts %>% filter(analysis == "primary_clinical_SVA") %>%
  ggplot(aes(x = topology_class, y = pct_features, fill = level)) +
  geom_col(position = "dodge") +
  coord_flip() +
  theme_bw(base_size = 11) +
  labs(x = NULL, y = "Features (%)", fill = "Level")
ggsave(file.path(figure_dir, "topology_class_distribution.png"), top_plot, width = 8, height = 5.5, dpi = 180)

bic_plot <- bic_counts %>% filter(analysis == "primary_clinical_SVA") %>%
  ggplot(aes(x = best_BIC_model, y = pct_features, fill = level)) +
  geom_col(position = "dodge") +
  theme_bw(base_size = 11) +
  labs(x = "Best per-feature BIC model", y = "Features (%)", fill = "Level")
ggsave(file.path(figure_dir, "best_BIC_model_distribution.png"), bic_plot, width = 7, height = 5, dpi = 180)

path_plot_data <- primary_pathways %>%
  mutate(
    label = sub("^HALLMARK_", "", feature),
    neglog10FDR = -log10(pmax(M3_FDR, 1e-300)),
    plot_label = if_else(M3_FDR < 0.10 | hypothesis_axis != "other_hallmark", label, NA_character_)
  )
path_plot <- ggplot(
  path_plot_data,
  aes(x = M3_logFC, y = neglog10FDR, color = hypothesis_axis, shape = topology_class)
) +
  geom_point(size = 3, alpha = 0.85) +
  ggrepel::geom_text_repel(
    data = path_plot_data %>% filter(!is.na(plot_label)),
    aes(label = plot_label), size = 2.7, max.overlaps = 35
  ) +
  theme_bw(base_size = 11) +
  labs(x = "Hallmark score difference (NCR - CR)", y = "-log10 FDR", color = "Hypothesis axis", shape = "Topology")
ggsave(file.path(figure_dir, "hallmark_M3_topology.png"), path_plot, width = 11, height = 7.5, dpi = 180)

# Heatmap uses the top M3-associated genes, regardless of whether they pass FDR.
heat_genes <- primary_genes %>% arrange(M3_p) %>% slice_head(n = 30) %>% pull(feature)
heat_expr <- expr_model[heat_genes, gene_primary$phenotype$sample, drop = FALSE]
heat_z <- t(scale(t(heat_expr)))
ann <- data.frame(
  Response = gene_primary$phenotype$response4,
  Residual = gene_primary$phenotype$residual_group,
  TSS = gene_primary$phenotype$tss_collapsed,
  row.names = gene_primary$phenotype$sample
)
png(file.path(figure_dir, "top30_M3_gene_heatmap.png"), width = 2200, height = 1600, res = 180)
pheatmap(
  heat_z,
  annotation_col = ann,
  show_colnames = FALSE,
  cluster_cols = TRUE,
  clustering_distance_cols = "correlation",
  main = "Top 30 M3-associated genes (descriptive)"
)
dev.off()

capture.output(sessionInfo(), file = file.path(log_dir, "sessionInfo_molecular_topology.txt"))
writeLines(
  c(
    paste("Molecular topology completed:", format(Sys.time(), tz = "UTC")),
    paste("Genes analyzed:", nrow(expr_model)),
    paste("Hallmark pathways analyzed:", nrow(hallmark_scores)),
    paste("Primary samples:", gene_primary$design_summary$n_samples),
    paste("Primary surrogate variables:", gene_primary$design_summary$n_sv_used),
    paste("Primary threshold-supported genes:", sum(primary_genes$topology_class == "threshold_supported")),
    paste("Primary four-state heterogeneous genes:", sum(primary_genes$topology_class == "four_state_heterogeneous")),
    paste("Primary threshold-supported pathways:", sum(primary_pathways$topology_class == "threshold_supported")),
    paste("Genes robustly threshold-supported in all analyses:", sum(robust_gene$threshold_supported_in_all)),
    paste("Pathways robustly threshold-supported in all analyses:", sum(robust_pathway$threshold_supported_in_all)),
    "Topology classes are screening labels, not proof of biological equivalence.",
    "Purity sensitivity uses expression-derived ESTIMATE purity and is not an independent purity measurement."
  ),
  file.path(log_dir, "molecular_topology_run_summary.txt")
)

message("Molecular topology analysis completed successfully.")
