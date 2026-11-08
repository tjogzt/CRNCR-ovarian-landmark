#!/usr/bin/env Rscript

# ==============================================================================
# File: 08_fit_wgcna_network.R
# Purpose: Construct the primary WGCNA co-expression network and test module associations.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Quality-controlled TCGA-OV expression object and curated phenotypes.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; response level order; wgcna gene selection,
#     expected input size, powers, module/correlation/hub/trait/thread settings;
#     molecular.fdr_threshold, constraint_alpha; resampling.wgcna_split_half_repeats.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Network objects, module tables, stability results, and figures.
# Reproducibility:
#   - MAD selection is label-blind; only TSS/year effects are residualized.
#   - Network seed and seed+1 split-halves are unchanged; modules stay fixed.
# ==============================================================================

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(WGCNA)
  library(dynamicTreeCut)
  library(limma)
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
seed <- analysis_config$random_seeds$default
wgcna_config <- analysis_config$wgcna
molecular_config <- analysis_config$molecular
expected_response_known_samples <- required_analysis_value(analysis_config, "wgcna.expected_response_known_samples")
if (!is.numeric(expected_response_known_samples) || length(expected_response_known_samples) != 1L ||
    !is.finite(expected_response_known_samples) || expected_response_known_samples < 1 ||
    expected_response_known_samples != floor(expected_response_known_samples)) {
  stop("wgcna.expected_response_known_samples must be a positive integer.")
}
expected_response_known_samples <- as.integer(expected_response_known_samples)
constraint_alpha <- required_analysis_value(analysis_config, "molecular.constraint_alpha")
if (!is.numeric(constraint_alpha) || length(constraint_alpha) != 1L ||
    !is.finite(constraint_alpha) || constraint_alpha <= 0 || constraint_alpha >= 1) {
  stop("molecular.constraint_alpha must be strictly between zero and one.")
}
n_threads <- max(
  1L,
  min(wgcna_config$maximum_threads, parallel::detectCores(logical = TRUE) - 1L)
)
configure_reproducible_runtime(seed, threads = n_threads)
input_path <- file.path(config$paths$processed_data_dir, "tcga_ov_u133a_expression_qc.rds")
table_dir <- file.path(config$paths$results_dir, "tables", "wgcna")
figure_dir <- file.path(config$paths$results_dir, "figures", "wgcna")
log_dir <- file.path(project_dir, "logs")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
if (!file.exists(input_path)) stop("Missing input: ", input_path)

allowWGCNAThreads(nThreads = n_threads)

write_csv_base <- function(x, path) {
  write.csv(x, path, row.names = FALSE, na = "")
}

# ---- Analysis workflow --------------------------------------------------------
message("Reading expression QC object...")
qc <- readRDS(input_path)
required_qc <- c("expression", "phenotype", "model_genes")
if (!all(required_qc %in% names(qc))) stop("QC object lacks required fields")
expr_all <- qc$expression
pheno_all <- qc$phenotype
if (!identical(colnames(expr_all), pheno_all$sample)) stop("Expression/phenotype alignment failed")
if (ncol(expr_all) != expected_response_known_samples ||
    sum(!is.na(pheno_all$response4)) != expected_response_known_samples) {
  stop("Expected exactly ", expected_response_known_samples, " response-known samples")
}

pheno_all$response4 <- factor(pheno_all$response4, levels = analysis_config$response$four_levels)
pheno_all$response_m2 <- factor(pheno_all$response_m2, levels = analysis_config$response$objective_response_levels)
pheno_all$response_m3 <- factor(pheno_all$response_m3, levels = analysis_config$response$cr_threshold_levels)
pheno_all$stage_group <- factor(pheno_all$stage_group, levels = c("I-II", "III", "IV"))
pheno_all$residual_group <- factor(pheno_all$residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm"))
pheno_all$tss_collapsed <- droplevels(factor(pheno_all$tss_collapsed))
pheno_all$age_z <- as.numeric(scale(pheno_all$age))
pheno_all$diagnosis_year_z <- as.numeric(scale(pheno_all$diagnosis_year))

# Unsupervised gene selection: response labels are not used. Rank only qc$model_genes by MAD.
model_genes <- intersect(qc$model_genes, rownames(expr_all))
model_mad <- matrixStats::rowMads(expr_all[model_genes, , drop = FALSE], na.rm = TRUE)
n_target <- min(wgcna_config$main_gene_count, length(model_genes))
mad_order <- order(model_mad, decreasing = TRUE, na.last = NA)
selected_genes <- model_genes[mad_order[seq_len(min(n_target, length(mad_order)))]]
if (length(selected_genes) < wgcna_config$minimum_selected_genes) stop("Too few genes after unsupervised MAD selection")

# Main network excludes pre-specified QC outliers. No response, stage, residual disease,
# ESTIMATE score, or purity variable is removed from expression.
keep_network <- !is.na(pheno_all$qc_outlier) & !pheno_all$qc_outlier
ph_net <- pheno_all[keep_network, , drop = FALSE]
expr_net_raw <- expr_all[selected_genes, ph_net$sample, drop = FALSE]
if (anyNA(ph_net$tss_collapsed) || anyNA(ph_net$diagnosis_year_z)) {
  stop("TSS/year must be complete for technical residualization")
}

message("Removing TSS and diagnosis-year effects only...")
expr_net <- removeBatchEffect(
  expr_net_raw,
  batch = droplevels(ph_net$tss_collapsed),
  covariates = matrix(ph_net$diagnosis_year_z, ncol = 1L,
                       dimnames = list(ph_net$sample, "diagnosis_year_z")),
  design = matrix(1, nrow = ncol(expr_net_raw), ncol = 1L)
)
# Explicitly restore each gene's pre-residualization mean.
expr_net <- sweep(expr_net, 1L, rowMeans(expr_net), FUN = "-")
expr_net <- sweep(expr_net, 1L, rowMeans(expr_net_raw), FUN = "+")
datExpr <- t(expr_net)

message("Checking WGCNA input...")
gsg <- goodSamplesGenes(datExpr, verbose = 3)
if (!gsg$allOK) {
  datExpr <- datExpr[gsg$goodSamples, gsg$goodGenes, drop = FALSE]
  ph_net <- ph_net[match(rownames(datExpr), ph_net$sample), , drop = FALSE]
}
if (!identical(rownames(datExpr), ph_net$sample)) stop("WGCNA sample alignment failed")
if (anyNA(datExpr) || any(!is.finite(datExpr))) stop("Non-finite WGCNA input remains")

powers <- unlist(wgcna_config$power_candidates)
message(sprintf(
  "Selecting soft-threshold power from configured range %d:%d...",
  min(powers), max(powers)
))
sft <- pickSoftThreshold(
  datExpr,
  powerVector = powers,
  networkType = "signed hybrid",
  corFnc = "bicor",
  corOptions = list(use = "pairwise.complete.obs", maxPOutliers = wgcna_config$max_p_outliers),
  verbose = 5
)
fi <- as.data.frame(sft$fitIndices)
if (ncol(fi) < 7L) stop("Unexpected pickSoftThreshold output")
soft_table <- data.frame(
  power = fi[[1]],
  scale_free_R2 = fi[[2]],
  slope = fi[[3]],
  truncated_R2 = fi[[4]],
  mean_connectivity = fi[[5]],
  median_connectivity = fi[[6]],
  max_connectivity = fi[[7]],
  stringsAsFactors = FALSE
)
# Select the lowest eligible power, not the power with the most response signal.
# If none qualifies, the fixed connectivity/slope penalty and near-best tolerance
# define the same deterministic compromise; candidate ordering remains unchanged.
eligible <- with(soft_table, is.finite(scale_free_R2) & scale_free_R2 >= wgcna_config$minimum_scale_free_r2 &
                   is.finite(mean_connectivity) &
                   mean_connectivity >= wgcna_config$minimum_mean_connectivity & slope < 0)
if (any(eligible)) {
  soft_power <- min(soft_table$power[eligible])
  power_rule <- sprintf(
    "minimum power with signed-hybrid R2 >= %.2f, mean connectivity >= %g, and negative slope",
    wgcna_config$minimum_scale_free_r2, wgcna_config$minimum_mean_connectivity
  )
} else {
  compromise_score <- with(soft_table,
    scale_free_R2 - wgcna_config$fallback_connectivity_penalty_weight *
      pmax(0, (wgcna_config$minimum_mean_connectivity - mean_connectivity) /
        wgcna_config$minimum_mean_connectivity) -
      wgcna_config$fallback_slope_penalty_weight * (slope >= 0)
  )
  compromise_score[!is.finite(compromise_score)] <- -Inf
  best_score <- max(compromise_score)
  near_best <- which(
    compromise_score >= best_score - wgcna_config$fallback_near_best_tolerance
  )
  soft_power <- min(soft_table$power[near_best])
  power_rule <- sprintf(
    "fallback compromise: lowest power within %.2f of best R2/connectivity/slope score",
    wgcna_config$fallback_near_best_tolerance
  )
}
soft_table$meets_primary_rule <- eligible
soft_table$selected <- soft_table$power == soft_power
soft_table$selection_rule <- power_rule
write_csv_base(soft_table, file.path(table_dir, "soft_threshold.csv"))

plot_soft_threshold <- function(path, type) {
  if (type == "pdf") pdf(path, width = 10, height = 5) else png(path, width = 1800, height = 900, res = 180)
  on.exit(dev.off(), add = TRUE)
  par(mfrow = c(1, 2), mar = c(4.5, 4.5, 2.5, 1))
  plot(soft_table$power, soft_table$scale_free_R2, type = "n", xlab = "Soft-threshold power",
       ylab = "Signed scale-free fit (R²)", main = "Scale independence", ylim = range(c(0, soft_table$scale_free_R2), finite = TRUE))
  text(soft_table$power, soft_table$scale_free_R2, labels = soft_table$power, col = "#2C7FB8", cex = 0.8)
  abline(h = wgcna_config$minimum_scale_free_r2, col = "#D95F0E", lty = 2)
  abline(v = soft_power, col = "#238B45", lty = 3)
  plot(soft_table$power, soft_table$mean_connectivity, type = "n", xlab = "Soft-threshold power",
       ylab = "Mean connectivity", main = "Mean connectivity")
  text(soft_table$power, soft_table$mean_connectivity, labels = soft_table$power, col = "#2C7FB8", cex = 0.8)
  abline(h = wgcna_config$minimum_mean_connectivity, col = "#D95F0E", lty = 2)
  abline(v = soft_power, col = "#238B45", lty = 3)
}
plot_soft_threshold(file.path(figure_dir, "soft_threshold.pdf"), "pdf")
plot_soft_threshold(file.path(figure_dir, "soft_threshold.png"), "png")

message("Constructing signed-hybrid WGCNA network at power ", soft_power, "...")
set.seed(seed)
net <- blockwiseModules(
  datExpr,
  power = soft_power,
  networkType = "signed hybrid",
  TOMType = "signed",
  corType = "bicor",
  maxPOutliers = wgcna_config$max_p_outliers,
  pearsonFallback = "individual",
  maxBlockSize = ncol(datExpr) + 1L,
  minModuleSize = wgcna_config$minimum_module_size,
  mergeCutHeight = wgcna_config$merge_cut_height,
  deepSplit = wgcna_config$deep_split,
  pamRespectsDendro = FALSE,
  numericLabels = FALSE,
  randomSeed = seed,
  nThreads = n_threads,
  verbose = 5
)
module_colors <- as.character(net$colors)
names(module_colors) <- colnames(datExpr)
module_levels <- sort(unique(module_colors))
non_grey <- setdiff(module_levels, "grey")
if (length(non_grey) == 0L) stop("No non-grey modules detected")

me_all <- moduleEigengenes(datExpr, colors = module_colors, excludeGrey = FALSE,
                           align = "along average", impute = TRUE)$eigengenes
me_all <- orderMEs(me_all)
me_keep <- me_all[, paste0("ME", non_grey), drop = FALSE]

plot_dendrogram <- function(path, type) {
  if (type == "pdf") pdf(path, width = 14, height = 7) else png(path, width = 2520, height = 1260, res = 180)
  on.exit(dev.off(), add = TRUE)
  block_genes <- net$blockGenes[[1]]
  plotDendroAndColors(
    net$dendrograms[[1]], module_colors[block_genes], "Module colors",
    dendroLabels = FALSE, hang = 0.03, addGuide = TRUE, guideHang = 0.05,
    main = "TCGA-OV U133A WGCNA gene dendrogram"
  )
}
plot_dendrogram(file.path(figure_dir, "gene_dendrogram_module_colors.pdf"), "pdf")
plot_dendrogram(file.path(figure_dir, "gene_dendrogram_module_colors.png"), "png")

message("Calculating gene-module membership...")
kme_fit <- bicorAndPvalue(datExpr, me_keep, use = "pairwise.complete.obs", maxPOutliers = wgcna_config$max_p_outliers)
kme_mat <- kme_fit$bicor
kme_p <- kme_fit$p
assigned_col <- match(paste0("ME", module_colors), colnames(kme_mat))
assigned_kme <- rep(NA_real_, ncol(datExpr))
assigned_p <- rep(NA_real_, ncol(datExpr))
valid_assigned <- !is.na(assigned_col)
assigned_kme[valid_assigned] <- kme_mat[cbind(which(valid_assigned), assigned_col[valid_assigned])]
assigned_p[valid_assigned] <- kme_p[cbind(which(valid_assigned), assigned_col[valid_assigned])]
max_idx <- max.col(abs(kme_mat), ties.method = "first")
gene_table <- data.frame(
  gene = colnames(datExpr),
  module = module_colors,
  is_grey = module_colors == "grey",
  kME_assigned = assigned_kme,
  kME_assigned_p = assigned_p,
  strongest_kME_module = sub("^ME", "", colnames(kme_mat)[max_idx]),
  strongest_abs_kME = abs(kme_mat[cbind(seq_len(nrow(kme_mat)), max_idx)]),
  MAD_all_454 = model_mad[match(colnames(datExpr), model_genes)],
  stringsAsFactors = FALSE
)
gene_table <- gene_table[order(gene_table$module, -abs(gene_table$kME_assigned)), ]
write_csv_base(gene_table, file.path(table_dir, "gene_module_kME.csv"))

# Add cleaned pathology tumor-cell percentage from curatedOvarianData.
message("Matching curatedOvarianData pathology purity...")
data("TCGA_eset", package = "curatedOvarianData")
cp <- Biobase::pData(TCGA_eset)
curated <- data.frame(
  patient = gsub("\\.", "-", substr(as.character(cp$unique_patient_ID), 1, 12)),
  percent_normal_cells = suppressWarnings(as.numeric(as.character(cp$percent_normal_cells))),
  percent_stromal_cells = suppressWarnings(as.numeric(as.character(cp$percent_stromal_cells))),
  percent_tumor_cells_raw = suppressWarnings(as.numeric(as.character(cp$percent_tumor_cells))),
  stringsAsFactors = FALSE
)
curated$pathology_all_zero <- with(curated,
  !is.na(percent_normal_cells) & !is.na(percent_stromal_cells) & !is.na(percent_tumor_cells_raw) &
    percent_normal_cells == 0 & percent_stromal_cells == 0 & percent_tumor_cells_raw == 0
)
curated$percent_tumor_cells <- ifelse(curated$pathology_all_zero, NA_real_, curated$percent_tumor_cells_raw)
curated <- curated[!duplicated(curated$patient), c("patient", "percent_tumor_cells")]
ph_net$percent_tumor_cells <- curated$percent_tumor_cells[match(ph_net$patient, curated$patient)]

cor_traits <- c("TumorPurity", "ImmuneScore", "StromalScore", "percent_tumor_cells")
cor_rows <- list()
row_id <- 1L
for (me_name in colnames(me_keep)) {
  module <- sub("^ME", "", me_name)
  for (trait in cor_traits) {
    ok <- is.finite(me_keep[, me_name]) & is.finite(ph_net[[trait]])
    if (sum(ok) >= wgcna_config$minimum_trait_samples &&
        length(unique(ph_net[[trait]][ok])) > 1L) {
      cpv <- bicorAndPvalue(me_keep[ok, me_name], ph_net[[trait]][ok], maxPOutliers = wgcna_config$max_p_outliers)
      estimate <- unname(cpv$bicor[1])
      p_value <- unname(cpv$p[1])
    } else {
      estimate <- p_value <- NA_real_
    }
    cor_rows[[row_id]] <- data.frame(module = module, trait = trait, n = sum(ok),
                                     bicor = estimate, p_value = p_value)
    row_id <- row_id + 1L
  }
}
purity_cor <- do.call(rbind, cor_rows)
purity_cor$FDR <- ave(purity_cor$p_value, purity_cor$trait,
                      FUN = function(x) p.adjust(x, method = "BH"))
write_csv_base(purity_cor, file.path(table_dir, "module_microenvironment_correlations.csv"))

make_design <- function(response, covariates, ph) {
  rhs <- paste(c(response, covariates), collapse = " + ")
  design <- model.matrix(as.formula(paste("~", rhs)), data = ph)
  colnames(design) <- make.names(colnames(design), unique = TRUE)
  design
}

extract_single <- function(fit, coef_name, adjustment, test_name, n) {
  j <- match(coef_name, colnames(fit$coefficients))
  if (is.na(j)) stop("Missing coefficient: ", coef_name)
  data.frame(
    module = sub("^ME", "", rownames(fit$coefficients)), adjustment = adjustment,
    test = test_name, contrast = coef_name, n = n,
    estimate = fit$coefficients[, j], standard_error = fit$stdev.unscaled[, j] * sqrt(fit$s2.post),
    statistic = fit$t[, j], statistic_type = "moderated_t", numerator_df = 1,
    denominator_df = fit$df.total, p_value = fit$p.value[, j], stringsAsFactors = FALSE
  )
}

extract_global <- function(fit, coefs, adjustment, test_name, n) {
  tab <- topTable(fit, coef = coefs, number = Inf, sort.by = "none")
  tab <- tab[rownames(fit$coefficients), , drop = FALSE]
  data.frame(
    module = sub("^ME", "", rownames(tab)), adjustment = adjustment,
    test = test_name, contrast = paste(coefs, collapse = ";"), n = n,
    estimate = NA_real_, standard_error = NA_real_, statistic = tab$F,
    statistic_type = "moderated_F", numerator_df = length(coefs),
    denominator_df = fit$df.total, p_value = tab$P.Value, stringsAsFactors = FALSE
  )
}

fit_association_layer <- function(layer, covariates) {
  required <- unique(c("response4", "response_m2", "response_m3", covariates))
  ok <- complete.cases(ph_net[, required, drop = FALSE])
  ph <- ph_net[ok, , drop = FALSE]
  ph$response4 <- droplevels(ph$response4)
  ph$response_m2 <- droplevels(ph$response_m2)
  ph$response_m3 <- droplevels(ph$response_m3)
  if (length(unique(ph$response4)) != 4L) stop("M1 response levels missing in ", layer)
  y <- t(me_keep[ph$sample, , drop = FALSE])

  d3 <- make_design("response_m3", covariates, ph)
  f3 <- eBayes(lmFit(y, d3), robust = TRUE)
  r3 <- extract_single(f3, "response_m3Non.CR", layer, "M3_NonCR_minus_CR", nrow(ph))

  d2 <- make_design("response_m2", covariates, ph)
  f2 <- eBayes(lmFit(y, d2), robust = TRUE)
  r2 <- extract_single(f2, "response_m2SD.PD", layer, "M2_SD_PD_minus_CR_PR", nrow(ph))

  d1 <- make_design("response4", covariates, ph)
  f1 <- eBayes(lmFit(y, d1), robust = TRUE)
  m1_coefs <- c("response4PR", "response4SD", "response4PD")
  if (!all(m1_coefs %in% colnames(d1))) stop("M1 coefficients unavailable in ", layer)
  r1 <- extract_global(f1, m1_coefs, layer, "M1_global", nrow(ph))

  contrast_matrix <- matrix(0, nrow = ncol(d1), ncol = 2,
                            dimnames = list(colnames(d1), c("PR_minus_SD", "PR_minus_PD")))
  contrast_matrix["response4PR", ] <- 1
  contrast_matrix["response4SD", "PR_minus_SD"] <- -1
  contrast_matrix["response4PD", "PR_minus_PD"] <- -1
  fc <- eBayes(contrasts.fit(f1, contrast_matrix), robust = TRUE)
  plateau <- extract_global(fc, colnames(contrast_matrix), layer,
                            "M1_plateau_constraint_PR_eq_SD_eq_PD", nrow(ph))
  plateau$interpretation <- ifelse(
    plateau$p_value < constraint_alpha,
    "plateau constraint rejected",
    "plateau constraint not rejected; this is not evidence of equivalence"
  )
  r3$interpretation <- NA_character_
  r2$interpretation <- NA_character_
  r1$interpretation <- NA_character_

  results <- rbind(r3, r2, r1, plateau)
  design_summary <- data.frame(
    adjustment = layer, n_samples = nrow(ph), n_modules = nrow(y),
    CR = sum(ph$response4 == "CR"), PR = sum(ph$response4 == "PR"),
    SD = sum(ph$response4 == "SD"), PD = sum(ph$response4 == "PD"),
    covariates = if (length(covariates)) paste(covariates, collapse = ";") else "none",
    rank_M1 = qr(d1)$rank, rank_M2 = qr(d2)$rank, rank_M3 = qr(d3)$rank,
    stringsAsFactors = FALSE
  )
  list(results = results, design = design_summary)
}

message("Testing module eigengene associations...")
association_sets <- list(
  response_only = character(0),
  pre_residual = c("age_z", "stage_group", "tss_collapsed", "diagnosis_year_z"),
  full = c("age_z", "stage_group", "tss_collapsed", "diagnosis_year_z", "residual_group")
)
association_fits <- lapply(names(association_sets), function(x) fit_association_layer(x, association_sets[[x]]))
trait_results <- do.call(rbind, lapply(association_fits, `[[`, "results"))
trait_results$FDR <- ave(trait_results$p_value,
                         interaction(trait_results$adjustment, trait_results$test, drop = TRUE),
                         FUN = function(x) p.adjust(x, method = "BH"))
trait_results$interpretation[trait_results$test == "M1_plateau_constraint_PR_eq_SD_eq_PD" &
                               trait_results$FDR >= molecular_config$fdr_threshold] <-
  "plateau constraint not rejected after BH; this is not evidence of equivalence"
trait_results <- trait_results[order(trait_results$adjustment, trait_results$test, trait_results$FDR), ]
write_csv_base(trait_results, file.path(table_dir, "module_trait_results.csv"))
association_design <- do.call(rbind, lapply(association_fits, `[[`, "design"))

# Repeated split-half consistency with fixed full-network module definitions.
# This is an internal stability analysis, not module preservation or independent validation.
message("Calculating repeated split-half stability...")
n_splits <- analysis_config$resampling$wgcna_split_half_repeats
stability_rows <- list()
stability_id <- 1L
set.seed(seed + 1L)
for (split_id in seq_len(n_splits)) {
  half1 <- sort(sample(seq_len(nrow(datExpr)), floor(nrow(datExpr) / 2)))
  half2 <- setdiff(seq_len(nrow(datExpr)), half1)
  me1 <- moduleEigengenes(datExpr[half1, , drop = FALSE], colors = module_colors,
                          excludeGrey = TRUE, align = "along average", impute = TRUE)$eigengenes
  me2 <- moduleEigengenes(datExpr[half2, , drop = FALSE], colors = module_colors,
                          excludeGrey = TRUE, align = "along average", impute = TRUE)$eigengenes
  for (module in non_grey) {
    genes <- which(module_colors == module)
    me_name <- paste0("ME", module)
    k1 <- as.numeric(bicor(datExpr[half1, genes, drop = FALSE], me1[, me_name],
                           use = "pairwise.complete.obs", maxPOutliers = wgcna_config$max_p_outliers))
    k2 <- as.numeric(bicor(datExpr[half2, genes, drop = FALSE], me2[, me_name],
                           use = "pairwise.complete.obs", maxPOutliers = wgcna_config$max_p_outliers))
    raw_cor <- suppressWarnings(cor(k1, k2, method = "spearman", use = "pairwise.complete.obs"))
    flipped <- is.finite(raw_cor) && raw_cor < 0
    if (flipped) k2 <- -k2
    kme_cor <- suppressWarnings(cor(k1, k2, method = "spearman", use = "pairwise.complete.obs"))
    top_n <- max(wgcna_config$minimum_hub_count,
                 ceiling(length(genes) * wgcna_config$hub_fraction))
    top1 <- order(k1, decreasing = TRUE)[seq_len(top_n)]
    top2 <- order(k2, decreasing = TRUE)[seq_len(top_n)]
    jaccard <- length(intersect(top1, top2)) / length(union(top1, top2))
    stability_rows[[stability_id]] <- data.frame(
      split = split_id, module = module, module_size = length(genes),
      n_half1 = length(half1), n_half2 = length(half2),
      kME_spearman = kme_cor,
      kME_sign_concordance = mean(sign(k1) == sign(k2), na.rm = TRUE),
      median_abs_kME_difference = median(abs(k1 - k2), na.rm = TRUE),
      top10pct_hub_jaccard = jaccard, orientation_flipped = flipped,
      stringsAsFactors = FALSE
    )
    stability_id <- stability_id + 1L
  }
}
stability_replicates <- do.call(rbind, stability_rows)
write_csv_base(stability_replicates, file.path(table_dir, "split_half_stability_replicates.csv"))
stability_summary <- do.call(rbind, lapply(split(stability_replicates, stability_replicates$module), function(d) {
  data.frame(
    module = d$module[1], module_size = d$module_size[1], splits = nrow(d),
    median_kME_spearman = median(d$kME_spearman, na.rm = TRUE),
    q05_kME_spearman = unname(quantile(d$kME_spearman, 0.05, na.rm = TRUE)),
    median_kME_sign_concordance = median(d$kME_sign_concordance, na.rm = TRUE),
    median_abs_kME_difference = median(d$median_abs_kME_difference, na.rm = TRUE),
    median_top10pct_hub_jaccard = median(d$top10pct_hub_jaccard, na.rm = TRUE),
    method = sprintf(
      "%d repeated random split-halves; fixed full-network modules; not independent validation",
      n_splits
    ),
    stringsAsFactors = FALSE
  )
}))
stability_summary <- stability_summary[order(-stability_summary$median_kME_spearman), ]
write_csv_base(stability_summary, file.path(table_dir, "split_half_stability.csv"))

# Module annotations, including explicit exclusion of grey and microenvironment evidence.
module_sizes <- as.data.frame(table(module_colors), stringsAsFactors = FALSE)
names(module_sizes) <- c("module", "size")
module_annotation <- module_sizes
module_annotation$candidate_status <- ifelse(module_annotation$module == "grey", "excluded_grey", "eligible_non_grey")
module_annotation$microenvironment_class <- vapply(module_annotation$module, function(module) {
  if (module == "grey") return("excluded_grey")
  d <- purity_cor[
    purity_cor$module == module & purity_cor$FDR < molecular_config$fdr_threshold &
      abs(purity_cor$bicor) >= wgcna_config$microenvironment_correlation_threshold,
    , drop = FALSE
  ]
  tags <- character(0)
  if ("ImmuneScore" %in% d$trait) tags <- c(tags, "immune")
  if ("StromalScore" %in% d$trait) tags <- c(tags, "stromal")
  if (any(d$trait %in% c("TumorPurity", "percent_tumor_cells"))) tags <- c(tags, "purity-linked")
  if (length(tags)) paste(tags, collapse = "+") else "no_FDR_significant_microenvironment_correlation"
}, character(1))
module_annotation <- merge(module_annotation, stability_summary, by = "module", all.x = TRUE, sort = FALSE)
module_annotation$module_size <- NULL
module_annotation <- module_annotation[order(module_annotation$candidate_status, -module_annotation$size), ]
write_csv_base(module_annotation, file.path(table_dir, "module_annotation.csv"))

me_output <- data.frame(sample = rownames(me_all), me_all, check.names = FALSE)
write_csv_base(me_output, file.path(table_dir, "module_eigengenes.csv"))
sample_manifest <- data.frame(
  sample = pheno_all$sample,
  response4 = pheno_all$response4,
  qc_outlier = pheno_all$qc_outlier,
  included_main_network = pheno_all$sample %in% rownames(datExpr),
  stringsAsFactors = FALSE
)
write_csv_base(sample_manifest, file.path(table_dir, "network_sample_manifest.csv"))

# Heatmap: directional tests use moderated t; global/constraint tests use sqrt(F),
# and microenvironment columns use 6*bicor. Cell text reports BH FDR.
heat_modules <- non_grey
heat_cols <- c()
heat_values <- list()
heat_labels <- list()
for (layer in names(association_sets)) {
  for (test in c("M3_NonCR_minus_CR", "M2_SD_PD_minus_CR_PR", "M1_global",
                 "M1_plateau_constraint_PR_eq_SD_eq_PD")) {
    d <- trait_results[trait_results$adjustment == layer & trait_results$test == test, ]
    d <- d[match(heat_modules, d$module), ]
    key <- paste(layer, sub("_constraint_PR_eq_SD_eq_PD", "", test), sep = ":")
    value <- if (test %in% c("M1_global", "M1_plateau_constraint_PR_eq_SD_eq_PD")) sqrt(pmax(d$statistic, 0)) else d$statistic
    heat_cols <- c(heat_cols, key)
    heat_values[[key]] <- pmax(-6, pmin(6, value))
    heat_labels[[key]] <- ifelse(is.finite(d$FDR), sprintf("q=%.2g", d$FDR), "")
  }
}
for (trait in cor_traits) {
  d <- purity_cor[purity_cor$trait == trait, ]
  d <- d[match(heat_modules, d$module), ]
  key <- paste0("bicor:", trait)
  heat_cols <- c(heat_cols, key)
  heat_values[[key]] <- 6 * d$bicor
  heat_labels[[key]] <- ifelse(is.finite(d$FDR), sprintf("q=%.2g", d$FDR), "")
}
heat_matrix <- do.call(cbind, heat_values)[, heat_cols, drop = FALSE]
rownames(heat_matrix) <- heat_modules
heat_text <- do.call(cbind, heat_labels)[, heat_cols, drop = FALSE]
rownames(heat_text) <- heat_modules
if (requireNamespace("pheatmap", quietly = TRUE)) {
  palette <- colorRampPalette(c("#2166AC", "white", "#B2182B"))(101)
  pheatmap::pheatmap(heat_matrix, color = palette, breaks = seq(-6, 6, length.out = 102),
    display_numbers = heat_text, number_color = "black", fontsize_number = 6,
    cluster_rows = TRUE, cluster_cols = FALSE, border_color = NA,
    main = "Module-trait statistics (cell text: BH FDR)",
    filename = file.path(figure_dir, "module_trait_heatmap.pdf"), width = 14, height = max(6, 0.32 * length(heat_modules) + 2))
  pheatmap::pheatmap(heat_matrix, color = palette, breaks = seq(-6, 6, length.out = 102),
    display_numbers = heat_text, number_color = "black", fontsize_number = 6,
    cluster_rows = TRUE, cluster_cols = FALSE, border_color = NA,
    main = "Module-trait statistics (cell text: BH FDR)",
    filename = file.path(figure_dir, "module_trait_heatmap.png"), width = 14, height = max(6, 0.32 * length(heat_modules) + 2), dpi = 180)
} else {
  warning("pheatmap unavailable; module-trait heatmap was not produced")
}

selected_row <- soft_table[soft_table$selected, ]
design_summary <- rbind(
  data.frame(
    item = "input",
    value = file.path("processed_data_dir", basename(input_path))
  ),
  data.frame(item = "response_known_samples", value = ncol(expr_all)),
  data.frame(item = "qc_outliers_excluded", value = sum(!keep_network)),
  data.frame(item = "main_network_samples", value = nrow(datExpr)),
  data.frame(item = "qc_model_genes", value = length(model_genes)),
  data.frame(item = "MAD_selected_genes", value = length(selected_genes)),
  data.frame(item = "genes_after_goodSamplesGenes", value = ncol(datExpr)),
  data.frame(item = "gene_filter", value = "top MAD among qc$model_genes across all 454; no response/DEG filtering"),
  data.frame(item = "expression_adjustment", value = "limma::removeBatchEffect for tss_collapsed and diagnosis_year_z only; gene means restored"),
  data.frame(item = "network_type", value = "signed hybrid"),
  data.frame(
    item = "correlation",
    value = sprintf("bicor, maxPOutliers=%.2f", wgcna_config$max_p_outliers)
  ),
  data.frame(item = "soft_power", value = soft_power),
  data.frame(item = "soft_power_R2", value = selected_row$scale_free_R2),
  data.frame(item = "soft_power_mean_connectivity", value = selected_row$mean_connectivity),
  data.frame(item = "soft_power_rule", value = power_rule),
  data.frame(item = "TOMType", value = "signed"),
  data.frame(item = "minModuleSize", value = wgcna_config$minimum_module_size),
  data.frame(item = "mergeCutHeight", value = wgcna_config$merge_cut_height),
  data.frame(item = "pamRespectsDendro", value = FALSE),
  data.frame(item = "non_grey_modules", value = length(non_grey)),
  data.frame(item = "grey_genes", value = sum(module_colors == "grey")),
  data.frame(item = "pathology_percent_tumor_available", value = sum(!is.na(ph_net$percent_tumor_cells))),
  data.frame(
    item = "stability_method",
    value = sprintf(
      "%d repeated random split-halves with fixed full-network modules; not independent validation",
      n_splits
    )
  ),
  data.frame(item = "seed", value = seed),
  data.frame(item = "threads", value = n_threads)
)
write_csv_base(design_summary, file.path(table_dir, "design_summary.csv"))
write_csv_base(association_design, file.path(table_dir, "association_design_summary.csv"))

saveRDS(
  list(
    module_colors = module_colors,
    module_eigengenes = me_all,
    selected_power = soft_power,
    selected_genes = colnames(datExpr),
    network_samples = rownames(datExpr),
    settings = list(seed = seed, networkType = "signed hybrid", TOMType = "signed",
                    corType = "bicor", minModuleSize = wgcna_config$minimum_module_size,
                    mergeCutHeight = wgcna_config$merge_cut_height,
                    pamRespectsDendro = FALSE)
  ),
  file.path(table_dir, "wgcna_network_summary.rds"), compress = "xz"
)

sig <- trait_results[
  trait_results$FDR < molecular_config$fdr_threshold &
    trait_results$test != "M1_plateau_constraint_PR_eq_SD_eq_PD",
]
warning_lines <- character(0)
if (!any(eligible)) warning_lines <- c(warning_lines, "No power met the primary R2/connectivity/slope rule; fallback compromise used.")
if (sum(module_colors == "grey") > 0) warning_lines <- c(warning_lines, "Grey genes were retained only for audit and excluded from candidate modules and association testing.")
warning_lines <- c(warning_lines, "Split-half stability is internal consistency with fixed modules, not independent validation.")
writeLines(
  c(
    paste("WGCNA completed:", format(Sys.time(), tz = "UTC")),
    paste("Response-known input samples:", ncol(expr_all)),
    paste("QC outliers excluded:", sum(!keep_network)),
    paste("Main-network samples:", nrow(datExpr)),
    paste("Genes in network:", ncol(datExpr)),
    paste("Selected soft power:", soft_power),
    paste("Selected power scale-free R2:", signif(selected_row$scale_free_R2, 4)),
    paste("Selected power mean connectivity:", signif(selected_row$mean_connectivity, 4)),
    paste("Non-grey modules:", length(non_grey)),
    paste("Grey genes:", sum(module_colors == "grey")),
    paste("FDR-significant module-response tests (excluding constraint tests):", nrow(sig)),
    if (nrow(sig)) paste("Significant results:", paste(paste(sig$adjustment, sig$test, sig$module, sprintf("q=%.3g", sig$FDR), sep = "/"), collapse = "; ")) else "Significant results: none",
    paste("Clean curated percent_tumor_cells available:", sum(!is.na(ph_net$percent_tumor_cells))),
    paste("Warnings:", paste(warning_lines, collapse = " | "))
  ),
  file.path(log_dir, "wgcna_run_summary.txt")
)
capture.output(sessionInfo(), file = file.path(log_dir, "sessionInfo_wgcna.txt"))
message("WGCNA analysis completed successfully.")
