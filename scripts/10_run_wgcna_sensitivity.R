#!/usr/bin/env Rscript

# ==============================================================================
# File: 10_run_wgcna_sensitivity.R
# Purpose: Assess WGCNA stability across alternative gene-number selections.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Expression QC object, primary network, pathways, and configured gene counts.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; response level order; wgcna sensitivity
#     counts, expected network size, powers/module/correlation/hub/thread/stability
#     settings; molecular.fdr_threshold; resampling.wgcna_split_half_repeats.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Module-overlap, fixed-module stability, and sensitivity tables and figures.
# Reproducibility:
#   - Reuses the primary network and completed sensitivity caches when available.
#   - Network-ID seed offsets and residualization are retained; no yield-based selection.
# ==============================================================================

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(WGCNA)
  library(limma)
  library(ggplot2)
  library(dplyr)
  library(readr)
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
expected_network_samples <- required_analysis_value(analysis_config, "wgcna.expected_network_samples")
if (!is.numeric(expected_network_samples) || length(expected_network_samples) != 1L ||
    !is.finite(expected_network_samples) || expected_network_samples < 1 ||
    expected_network_samples != floor(expected_network_samples)) {
  stop("wgcna.expected_network_samples must be a positive integer.")
}
expected_network_samples <- as.integer(expected_network_samples)
wgcna_gene_counts <- as.integer(unlist(wgcna_config$sensitivity_gene_counts))
reference_gene_count <- as.integer(wgcna_config$main_gene_count)
expanded_gene_counts <- wgcna_gene_counts[wgcna_gene_counts != reference_gene_count]
if (length(expanded_gene_counts) != 2L) {
  stop("WGCNA sensitivity configuration must contain exactly two non-reference gene counts.")
}
n_threads <- max(
  1L,
  min(wgcna_config$maximum_threads, parallel::detectCores(logical = TRUE) - 1L)
)
configure_reproducible_runtime(seed, threads = n_threads)
input_path <- file.path(config$paths$processed_data_dir, "tcga_ov_u133a_expression_qc.rds")
pathway_rds <- file.path(config$paths$processed_data_dir, "msigdb_pathway_collections.rds")
reference_dir <- file.path(config$paths$results_dir, "tables", "wgcna")
pathway_dir <- file.path(config$paths$results_dir, "tables", "pathway_enrichment")
out_dir <- file.path(config$paths$results_dir, "tables", "wgcna_sensitivity")
fig_dir <- file.path(config$paths$results_dir, "figures", "wgcna_sensitivity")
log_dir <- file.path(project_dir, "logs")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

required <- c(
  input_path,
  pathway_rds,
  file.path(reference_dir, "wgcna_network_summary.rds"),
  file.path(reference_dir, "gene_module_kME.csv"),
  file.path(reference_dir, "module_trait_results.csv"),
  file.path(reference_dir, "split_half_stability.csv"),
  file.path(reference_dir, "soft_threshold.csv"),
  file.path(pathway_dir, "robust_M3_ranked_pathways.csv")
)
if (!all(file.exists(required))) {
  stop("Missing prerequisite: ", paste(required[!file.exists(required)], collapse = ", "))
}

allowWGCNAThreads(nThreads = n_threads)
write_csv_base <- function(x, path) write.csv(x, path, row.names = FALSE, na = "")

# ---- Analysis workflow --------------------------------------------------------
message("Reading expression and locked 5,000-gene reference network...")
qc <- readRDS(input_path)
expr_all <- qc$expression
pheno_all <- qc$phenotype
if (!identical(colnames(expr_all), pheno_all$sample)) stop("Expression/phenotype alignment failed")

pheno_all$response4 <- factor(pheno_all$response4, levels = analysis_config$response$four_levels)
pheno_all$response_m2 <- factor(pheno_all$response_m2, levels = analysis_config$response$objective_response_levels)
pheno_all$response_m3 <- factor(pheno_all$response_m3, levels = analysis_config$response$cr_threshold_levels)
pheno_all$stage_group <- factor(pheno_all$stage_group, levels = c("I-II", "III", "IV"))
pheno_all$residual_group <- factor(pheno_all$residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm"))
pheno_all$tss_collapsed <- droplevels(factor(pheno_all$tss_collapsed))
pheno_all$age_z <- as.numeric(scale(pheno_all$age))
pheno_all$diagnosis_year_z <- as.numeric(scale(pheno_all$diagnosis_year))

model_genes <- intersect(qc$model_genes, rownames(expr_all))
model_mad <- matrixStats::rowMads(expr_all[model_genes, , drop = FALSE], na.rm = TRUE)
mad_order <- order(model_mad, decreasing = TRUE, na.last = NA)
ordered_genes <- model_genes[mad_order]
expected_qc_gene_count <- max(wgcna_gene_counts)
if (length(ordered_genes) != expected_qc_gene_count) {
  warning(
    "Expected ", format(expected_qc_gene_count, big.mark = ","),
    " QC genes; observed ", length(ordered_genes)
  )
}

keep_network <- !is.na(pheno_all$qc_outlier) & !pheno_all$qc_outlier
ph_net <- pheno_all[keep_network, , drop = FALSE]
if (nrow(ph_net) != expected_network_samples) {
  warning("Expected ", expected_network_samples, " network samples; observed ", nrow(ph_net))
}
if (anyNA(ph_net$tss_collapsed) || anyNA(ph_net$diagnosis_year_z)) {
  stop("TSS/year must be complete for technical residualization")
}

message("Removing TSS and diagnosis-year effects once for all QC genes...")
expr_net_raw_all <- expr_all[ordered_genes, ph_net$sample, drop = FALSE]
expr_net_all <- removeBatchEffect(
  expr_net_raw_all,
  batch = droplevels(ph_net$tss_collapsed),
  covariates = matrix(ph_net$diagnosis_year_z, ncol = 1L,
                     dimnames = list(ph_net$sample, "diagnosis_year_z")),
  design = matrix(1, nrow = ncol(expr_net_raw_all), ncol = 1L)
)
expr_net_all <- sweep(expr_net_all, 1L, rowMeans(expr_net_all), FUN = "-")
expr_net_all <- sweep(expr_net_all, 1L, rowMeans(expr_net_raw_all), FUN = "+")

select_power <- function(datExpr, network_id) {
  message("Selecting soft threshold for ", network_id, "...")
  sft <- pickSoftThreshold(
    datExpr,
    powerVector = unlist(wgcna_config$power_candidates),
    networkType = "signed hybrid",
    corFnc = "bicor",
    corOptions = list(
      use = "pairwise.complete.obs",
      maxPOutliers = wgcna_config$max_p_outliers
    ),
    verbose = 5
  )
  fi <- as.data.frame(sft$fitIndices)
  tab <- data.frame(
    network = network_id,
    power = fi[[1]],
    scale_free_R2 = fi[[2]],
    slope = fi[[3]],
    truncated_R2 = fi[[4]],
    mean_connectivity = fi[[5]],
    median_connectivity = fi[[6]],
    max_connectivity = fi[[7]],
    stringsAsFactors = FALSE
  )
  eligible <- with(
    tab,
    is.finite(scale_free_R2) &
      scale_free_R2 >= wgcna_config$minimum_scale_free_r2 &
      is.finite(mean_connectivity) &
      mean_connectivity >= wgcna_config$minimum_mean_connectivity &
      slope < 0
  )
  if (any(eligible)) {
    power <- min(tab$power[eligible])
    rule <- sprintf(
      "minimum power with signed-hybrid R2 >= %.2f, mean connectivity >= %g, and negative slope",
      wgcna_config$minimum_scale_free_r2,
      wgcna_config$minimum_mean_connectivity
    )
  } else {
    score <- with(
      tab,
      scale_free_R2 - wgcna_config$fallback_connectivity_penalty_weight * pmax(
        0,
        (wgcna_config$minimum_mean_connectivity - mean_connectivity) /
          wgcna_config$minimum_mean_connectivity
      ) - wgcna_config$fallback_slope_penalty_weight * (slope >= 0)
    )
    score[!is.finite(score)] <- -Inf
    best <- max(score)
    power <- min(tab$power[
      score >= best - wgcna_config$fallback_near_best_tolerance
    ])
    rule <- sprintf(
      "fallback compromise: lowest power within %.2f of best R2/connectivity/slope score",
      wgcna_config$fallback_near_best_tolerance
    )
  }
  tab$meets_primary_rule <- eligible
  tab$selected <- tab$power == power
  tab$selection_rule <- rule
  list(power = power, rule = rule, table = tab)
}

make_design <- function(response, covariates, ph) {
  design <- model.matrix(
    as.formula(paste("~", paste(c(response, covariates), collapse = " + "))),
    data = ph
  )
  colnames(design) <- make.names(colnames(design), unique = TRUE)
  design
}

extract_single <- function(fit, coef_name, network_id, adjustment, test_name, n) {
  j <- match(coef_name, colnames(fit$coefficients))
  if (is.na(j)) stop("Missing coefficient: ", coef_name)
  data.frame(
    network = network_id,
    module = sub("^ME", "", rownames(fit$coefficients)),
    adjustment = adjustment,
    test = test_name,
    n = n,
    estimate = fit$coefficients[, j],
    standard_error = fit$stdev.unscaled[, j] * sqrt(fit$s2.post),
    statistic = fit$t[, j],
    p_value = fit$p.value[, j],
    stringsAsFactors = FALSE
  )
}

extract_global <- function(fit, coefs, network_id, adjustment, test_name, n) {
  tab <- topTable(fit, coef = coefs, number = Inf, sort.by = "none")
  tab <- tab[rownames(fit$coefficients), , drop = FALSE]
  data.frame(
    network = network_id,
    module = sub("^ME", "", rownames(tab)),
    adjustment = adjustment,
    test = test_name,
    n = n,
    estimate = NA_real_,
    standard_error = NA_real_,
    statistic = tab$F,
    p_value = tab$P.Value,
    stringsAsFactors = FALSE
  )
}

fit_module_associations <- function(me_keep, network_id) {
  association_sets <- list(
    response_only = character(0),
    pre_residual = c("age_z", "stage_group", "tss_collapsed", "diagnosis_year_z"),
    full = c("age_z", "stage_group", "tss_collapsed", "diagnosis_year_z", "residual_group")
  )
  rows <- list()
  row_id <- 1L
  for (layer in names(association_sets)) {
    covariates <- association_sets[[layer]]
    required <- unique(c("response4", "response_m2", "response_m3", covariates))
    ok <- complete.cases(ph_net[, required, drop = FALSE])
    ph <- ph_net[ok, , drop = FALSE]
    ph$response4 <- droplevels(ph$response4)
    ph$response_m2 <- droplevels(ph$response_m2)
    ph$response_m3 <- droplevels(ph$response_m3)
    y <- t(me_keep[ph$sample, , drop = FALSE])

    d3 <- make_design("response_m3", covariates, ph)
    f3 <- eBayes(lmFit(y, d3), robust = TRUE)
    rows[[row_id]] <- extract_single(f3, "response_m3Non.CR", network_id, layer,
                                     "M3_NonCR_minus_CR", nrow(ph))
    row_id <- row_id + 1L

    d2 <- make_design("response_m2", covariates, ph)
    f2 <- eBayes(lmFit(y, d2), robust = TRUE)
    rows[[row_id]] <- extract_single(f2, "response_m2SD.PD", network_id, layer,
                                     "M2_SD_PD_minus_CR_PR", nrow(ph))
    row_id <- row_id + 1L

    d1 <- make_design("response4", covariates, ph)
    f1 <- eBayes(lmFit(y, d1), robust = TRUE)
    rows[[row_id]] <- extract_global(f1, c("response4PR", "response4SD", "response4PD"),
                                     network_id, layer, "M1_global", nrow(ph))
    row_id <- row_id + 1L

    cm <- matrix(0, nrow = ncol(d1), ncol = 2,
                 dimnames = list(colnames(d1), c("PR_minus_SD", "PR_minus_PD")))
    cm["response4PR", ] <- 1
    cm["response4SD", "PR_minus_SD"] <- -1
    cm["response4PD", "PR_minus_PD"] <- -1
    fc <- eBayes(contrasts.fit(f1, cm), robust = TRUE)
    rows[[row_id]] <- extract_global(fc, colnames(cm), network_id, layer,
                                     "M1_plateau_constraint_PR_eq_SD_eq_PD", nrow(ph))
    row_id <- row_id + 1L
  }
  out <- do.call(rbind, rows)
  out$FDR <- ave(
    out$p_value,
    interaction(out$network, out$adjustment, out$test, drop = TRUE),
    FUN = function(x) p.adjust(x, method = "BH")
  )
  out
}

split_half_stability <- function(
  datExpr,
  module_colors,
  network_id,
  n_splits = analysis_config$resampling$wgcna_split_half_repeats
) {
  non_grey <- setdiff(sort(unique(module_colors)), "grey")
  rows <- list()
  row_id <- 1L
  set.seed(seed + match(network_id, c("top5000", "top8000", "all10837")))
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
                             use = "pairwise.complete.obs",
                             maxPOutliers = wgcna_config$max_p_outliers))
      k2 <- as.numeric(bicor(datExpr[half2, genes, drop = FALSE], me2[, me_name],
                             use = "pairwise.complete.obs",
                             maxPOutliers = wgcna_config$max_p_outliers))
      raw_cor <- suppressWarnings(cor(k1, k2, method = "spearman", use = "pairwise.complete.obs"))
      if (is.finite(raw_cor) && raw_cor < 0) k2 <- -k2
      top_n <- max(wgcna_config$minimum_hub_count,
                   ceiling(length(genes) * wgcna_config$hub_fraction))
      top1 <- order(k1, decreasing = TRUE)[seq_len(top_n)]
      top2 <- order(k2, decreasing = TRUE)[seq_len(top_n)]
      rows[[row_id]] <- data.frame(
        network = network_id,
        split = split_id,
        module = module,
        module_size = length(genes),
        kME_spearman = suppressWarnings(cor(k1, k2, method = "spearman", use = "pairwise.complete.obs")),
        kME_sign_concordance = mean(sign(k1) == sign(k2), na.rm = TRUE),
        median_abs_kME_difference = median(abs(k1 - k2), na.rm = TRUE),
        top10pct_hub_jaccard = length(intersect(top1, top2)) / length(union(top1, top2)),
        stringsAsFactors = FALSE
      )
      row_id <- row_id + 1L
    }
  }
  reps <- do.call(rbind, rows)
  summary <- reps %>%
    group_by(network, module, module_size) %>%
    summarise(
      splits = n(),
      median_kME_spearman = median(kME_spearman, na.rm = TRUE),
      q05_kME_spearman = quantile(kME_spearman, 0.05, na.rm = TRUE),
      median_kME_sign_concordance = median(kME_sign_concordance, na.rm = TRUE),
      median_abs_kME_difference = median(median_abs_kME_difference, na.rm = TRUE),
      median_top10pct_hub_jaccard = median(top10pct_hub_jaccard, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    as.data.frame()
  list(replicates = reps, summary = summary)
}

build_network <- function(n_genes, network_id) {
  genes <- ordered_genes[seq_len(min(n_genes, length(ordered_genes)))]
  datExpr <- t(expr_net_all[genes, , drop = FALSE])
  gsg <- goodSamplesGenes(datExpr, verbose = 3)
  if (!gsg$allOK) datExpr <- datExpr[gsg$goodSamples, gsg$goodGenes, drop = FALSE]
  if (!identical(rownames(datExpr), ph_net$sample)) stop("Sample alignment failed for ", network_id)

  power_fit <- select_power(datExpr, network_id)
  write_csv_base(power_fit$table, file.path(out_dir, paste0("soft_threshold_", network_id, ".csv")))

  message("Constructing ", network_id, " network with ", ncol(datExpr),
          " genes at power ", power_fit$power, "...")
  set.seed(seed)
  net <- blockwiseModules(
    datExpr,
    power = power_fit$power,
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
  non_grey <- setdiff(sort(unique(module_colors)), "grey")
  if (!length(non_grey)) stop("No non-grey modules in ", network_id)

  me_all <- moduleEigengenes(datExpr, colors = module_colors, excludeGrey = FALSE,
                             align = "along average", impute = TRUE)$eigengenes
  me_all <- orderMEs(me_all)
  me_keep <- me_all[, paste0("ME", non_grey), drop = FALSE]
  kme_fit <- bicorAndPvalue(
    datExpr,
    me_keep,
    use = "pairwise.complete.obs",
    maxPOutliers = wgcna_config$max_p_outliers
  )
  assigned_col <- match(paste0("ME", module_colors), colnames(kme_fit$bicor))
  assigned_kme <- rep(NA_real_, ncol(datExpr))
  valid <- !is.na(assigned_col)
  assigned_kme[valid] <- kme_fit$bicor[cbind(which(valid), assigned_col[valid])]
  gene_table <- data.frame(
    network = network_id,
    gene = colnames(datExpr),
    module = module_colors,
    is_grey = module_colors == "grey",
    kME_assigned = assigned_kme,
    MAD_all_454 = model_mad[match(colnames(datExpr), model_genes)],
    stringsAsFactors = FALSE
  )
  write_csv_base(gene_table, file.path(out_dir, paste0("gene_module_kME_", network_id, ".csv")))

  associations <- fit_module_associations(me_keep, network_id)
  write_csv_base(associations, file.path(out_dir, paste0("module_trait_results_", network_id, ".csv")))

  message("Calculating fixed-module split-half consistency for ", network_id, "...")
  stability <- split_half_stability(datExpr, module_colors, network_id)
  write_csv_base(stability$replicates,
                 file.path(out_dir, paste0("split_half_stability_replicates_", network_id, ".csv")))
  write_csv_base(stability$summary,
                 file.path(out_dir, paste0("split_half_stability_", network_id, ".csv")))

  selected <- power_fit$table[power_fit$table$selected, , drop = FALSE]
  summary <- data.frame(
    network = network_id,
    target_genes = n_genes,
    genes_after_goodSamplesGenes = ncol(datExpr),
    samples = nrow(datExpr),
    soft_power = power_fit$power,
    scale_free_R2 = selected$scale_free_R2,
    mean_connectivity = selected$mean_connectivity,
    power_rule = power_fit$rule,
    non_grey_modules = length(non_grey),
    grey_genes = sum(module_colors == "grey"),
    grey_fraction = mean(module_colors == "grey"),
    min_response_FDR = min(associations$FDR[associations$test %in%
      c("M3_NonCR_minus_CR", "M2_SD_PD_minus_CR_PR", "M1_global")], na.rm = TRUE),
    response_FDR_lt_0_05 = any(associations$FDR < molecular_config$fdr_threshold & associations$test %in%
      c("M3_NonCR_minus_CR", "M2_SD_PD_minus_CR_PR", "M1_global"), na.rm = TRUE),
    median_module_kME_spearman = median(stability$summary$median_kME_spearman, na.rm = TRUE),
    median_module_hub_jaccard = median(stability$summary$median_top10pct_hub_jaccard, na.rm = TRUE),
    stringsAsFactors = FALSE
  )

  saveRDS(
    list(
      module_colors = module_colors,
      module_eigengenes = me_all,
      selected_power = power_fit$power,
      selected_genes = colnames(datExpr),
      network_samples = rownames(datExpr),
      settings = list(seed = seed, networkType = "signed hybrid", TOMType = "signed",
                      corType = "bicor",
                      minModuleSize = wgcna_config$minimum_module_size,
                      mergeCutHeight = wgcna_config$merge_cut_height,
                      pamRespectsDendro = FALSE)
    ),
    file.path(out_dir, paste0("wgcna_network_summary_", network_id, ".rds")),
    compress = "xz"
  )

  rm(net, kme_fit)
  gc()
  list(gene_table = gene_table, associations = associations,
       stability = stability$summary, summary = summary)
}

# The 5,000-gene network remains the locked primary analysis and is not rebuilt.
reference_rds <- readRDS(file.path(reference_dir, "wgcna_network_summary.rds"))
reference_genes <- read_csv(file.path(reference_dir, "gene_module_kME.csv"), show_col_types = FALSE) %>%
  mutate(network = "top5000") %>%
  select(network, gene, module, is_grey, kME_assigned, MAD_all_454)
reference_assoc <- read_csv(file.path(reference_dir, "module_trait_results.csv"), show_col_types = FALSE) %>%
  mutate(network = "top5000") %>%
  select(network, module, adjustment, test, n, estimate, standard_error, statistic, p_value, FDR)
reference_stability <- read_csv(file.path(reference_dir, "split_half_stability.csv"), show_col_types = FALSE) %>%
  mutate(network = "top5000") %>%
  select(network, module, module_size, splits, median_kME_spearman, q05_kME_spearman,
         median_kME_sign_concordance, median_abs_kME_difference,
         median_top10pct_hub_jaccard)
reference_soft <- read_csv(file.path(reference_dir, "soft_threshold.csv"), show_col_types = FALSE)
reference_selected <- reference_soft %>% filter(selected) %>% slice_head(n = 1)
reference_summary <- data.frame(
  network = "top5000",
  target_genes = reference_gene_count,
  genes_after_goodSamplesGenes = nrow(reference_genes),
  samples = length(reference_rds$network_samples),
  soft_power = reference_rds$selected_power,
  scale_free_R2 = reference_selected$scale_free_R2,
  mean_connectivity = reference_selected$mean_connectivity,
  power_rule = reference_selected$selection_rule,
  non_grey_modules = n_distinct(reference_genes$module[!reference_genes$is_grey]),
  grey_genes = sum(reference_genes$is_grey),
  grey_fraction = mean(reference_genes$is_grey),
  min_response_FDR = min(reference_assoc$FDR[reference_assoc$test %in%
    c("M3_NonCR_minus_CR", "M2_SD_PD_minus_CR_PR", "M1_global")], na.rm = TRUE),
  response_FDR_lt_0_05 = any(reference_assoc$FDR < molecular_config$fdr_threshold & reference_assoc$test %in%
    c("M3_NonCR_minus_CR", "M2_SD_PD_minus_CR_PR", "M1_global"), na.rm = TRUE),
  median_module_kME_spearman = median(reference_stability$median_kME_spearman, na.rm = TRUE),
  median_module_hub_jaccard = median(reference_stability$median_top10pct_hub_jaccard, na.rm = TRUE),
  stringsAsFactors = FALSE
)

network_targets <- c(
  top8000 = min(expanded_gene_counts[[1]], length(ordered_genes)),
  all10837 = min(expanded_gene_counts[[2]], length(ordered_genes))
)

load_cached_network <- function(n_genes, network_id) {
  paths <- c(
    genes = file.path(out_dir, paste0("gene_module_kME_", network_id, ".csv")),
    associations = file.path(out_dir, paste0("module_trait_results_", network_id, ".csv")),
    stability = file.path(out_dir, paste0("split_half_stability_", network_id, ".csv")),
    soft = file.path(out_dir, paste0("soft_threshold_", network_id, ".csv")),
    rds = file.path(out_dir, paste0("wgcna_network_summary_", network_id, ".rds"))
  )
  if (!all(file.exists(paths))) return(NULL)
  message("Using cached completed network outputs for ", network_id, "...")
  genes <- read_csv(paths[["genes"]], show_col_types = FALSE)
  associations <- read_csv(paths[["associations"]], show_col_types = FALSE)
  stability <- read_csv(paths[["stability"]], show_col_types = FALSE)
  soft <- read_csv(paths[["soft"]], show_col_types = FALSE)
  net_rds <- readRDS(paths[["rds"]])
  selected <- soft %>% filter(selected) %>% slice_head(n = 1)
  summary <- data.frame(
    network = network_id,
    target_genes = n_genes,
    genes_after_goodSamplesGenes = nrow(genes),
    samples = length(net_rds$network_samples),
    soft_power = net_rds$selected_power,
    scale_free_R2 = selected$scale_free_R2,
    mean_connectivity = selected$mean_connectivity,
    power_rule = selected$selection_rule,
    non_grey_modules = n_distinct(genes$module[!genes$is_grey]),
    grey_genes = sum(genes$is_grey),
    grey_fraction = mean(genes$is_grey),
    min_response_FDR = min(associations$FDR[associations$test %in%
      c("M3_NonCR_minus_CR", "M2_SD_PD_minus_CR_PR", "M1_global")], na.rm = TRUE),
    response_FDR_lt_0_05 = any(associations$FDR < molecular_config$fdr_threshold & associations$test %in%
      c("M3_NonCR_minus_CR", "M2_SD_PD_minus_CR_PR", "M1_global"), na.rm = TRUE),
    median_module_kME_spearman = median(stability$median_kME_spearman, na.rm = TRUE),
    median_module_hub_jaccard = median(stability$median_top10pct_hub_jaccard, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
  list(gene_table = genes, associations = associations,
       stability = stability, summary = summary)
}

network_results <- lapply(names(network_targets), function(id) {
  cached <- load_cached_network(network_targets[[id]], id)
  if (is.null(cached)) build_network(network_targets[[id]], id) else cached
})
names(network_results) <- names(network_targets)

all_genes <- bind_rows(c(
  list(reference_genes),
  unname(lapply(network_results, `[[`, "gene_table"))
))
all_associations <- bind_rows(c(
  list(reference_assoc),
  unname(lapply(network_results, `[[`, "associations"))
))
all_stability <- bind_rows(c(
  list(reference_stability),
  unname(lapply(network_results, `[[`, "stability"))
))
network_summary <- bind_rows(c(
  list(reference_summary),
  unname(lapply(network_results, `[[`, "summary"))
)) %>%
  mutate(network_role = if_else(network == "top5000", "locked primary", "gene-number sensitivity"))

write_csv(network_summary, file.path(out_dir, "network_summary.csv"))
write_csv(all_associations, file.path(out_dir, "response_association_comparison.csv"))
write_csv(all_stability, file.path(out_dir, "split_half_stability_comparison.csv"))

# Matching tests and shared Jaccard use the shared-gene universe; expanded
# Jaccard separately includes added target genes. Grey is audited here but excluded
# from response candidates; these overlap statistics are not preservation Z scores.
compare_modules <- function(target_id) {
  ref <- reference_genes
  target <- all_genes %>% filter(network == target_id)
  shared <- intersect(ref$gene, target$gene)
  N <- length(shared)
  ref <- ref %>% filter(gene %in% shared)
  target_shared <- target %>% filter(gene %in% shared)
  rows <- list()
  row_id <- 1L
  for (rm in unique(ref$module)) {
    rg <- ref$gene[ref$module == rm]
    for (tm in unique(target_shared$module)) {
      tg_shared <- target_shared$gene[target_shared$module == tm]
      tg_all <- target$gene[target$module == tm]
      k <- length(intersect(rg, tg_shared))
      expected <- length(rg) * length(tg_shared) / N
      rows[[row_id]] <- data.frame(
        reference_network = "top5000",
        target_network = target_id,
        reference_module = rm,
        target_module = tm,
        shared_universe_n = N,
        reference_module_n_shared = length(rg),
        target_module_n_shared = length(tg_shared),
        target_module_n_all = length(tg_all),
        overlap_n = k,
        expected_overlap = expected,
        enrichment_ratio = ifelse(expected > 0, k / expected, NA_real_),
        jaccard_shared = k / length(union(rg, tg_shared)),
        jaccard_expanded = k / length(union(rg, tg_all)),
        reference_coverage = k / length(rg),
        target_shared_coverage = k / length(tg_shared),
        p_value = if (k > 0) phyper(k - 1, length(tg_shared), N - length(tg_shared),
                                   length(rg), lower.tail = FALSE) else 1,
        stringsAsFactors = FALSE
      )
      row_id <- row_id + 1L
    }
  }
  out <- do.call(rbind, rows)
  out$FDR <- p.adjust(out$p_value, method = "BH")
  out <- out %>%
    group_by(target_network, reference_module) %>%
    arrange(FDR, desc(jaccard_shared), desc(reference_coverage), .by_group = TRUE) %>%
    mutate(match_rank_for_reference = row_number()) %>%
    ungroup()
  out
}

module_overlap <- bind_rows(lapply(names(network_targets), compare_modules))
write_csv(module_overlap, file.path(out_dir, "module_overlap_all_pairs.csv"))
write_csv(module_overlap %>% filter(target_network == "top8000"),
          file.path(out_dir, "module_overlap_5000_vs_8000.csv"))
write_csv(module_overlap %>% filter(target_network == "all10837"),
          file.path(out_dir, "module_overlap_5000_vs_all.csv"))

best_matches <- module_overlap %>%
  filter(match_rank_for_reference == 1) %>%
  arrange(target_network, reference_module)
write_csv(best_matches, file.path(out_dir, "module_best_matches.csv"))

# Map the nine locked robust M3 pathways independently in each network.
robust_pathways <- read_csv(file.path(pathway_dir, "robust_M3_ranked_pathways.csv"),
                            show_col_types = FALSE) %>%
  filter(robust_all)
geneset_obj <- readRDS(pathway_rds)
robust_sets <- geneset_obj$sets[intersect(names(geneset_obj$sets), robust_pathways$pathway)]

map_pathways <- function(network_id) {
  gtab <- all_genes %>% filter(network == network_id)
  universe <- unique(gtab$gene)
  modules <- split(gtab$gene[!gtab$is_grey], gtab$module[!gtab$is_grey])
  rows <- list()
  row_id <- 1L
  for (module in names(modules)) {
    mg <- unique(modules[[module]])
    for (pathway in names(robust_sets)) {
      sg <- intersect(unique(robust_sets[[pathway]]), universe)
      overlap <- intersect(mg, sg)
      expected <- length(mg) * length(sg) / length(universe)
      rows[[row_id]] <- data.frame(
        network = network_id,
        module = module,
        pathway = pathway,
        module_size = length(mg),
        pathway_size_in_network = length(sg),
        overlap_n = length(overlap),
        expected_overlap = expected,
        enrichment_ratio = ifelse(expected > 0, length(overlap) / expected, NA_real_),
        p_value = if (length(overlap)) phyper(length(overlap) - 1, length(sg),
                                              length(universe) - length(sg), length(mg),
                                              lower.tail = FALSE) else 1,
        overlap_genes = paste(overlap, collapse = ";"),
        stringsAsFactors = FALSE
      )
      row_id <- row_id + 1L
    }
  }
  out <- do.call(rbind, rows)
  out$FDR_within_network <- p.adjust(out$p_value, method = "BH")
  out %>%
    group_by(network, pathway) %>%
    arrange(FDR_within_network, desc(overlap_n), desc(enrichment_ratio), .by_group = TRUE) %>%
    mutate(module_rank_for_pathway = row_number()) %>%
    ungroup()
}

pathway_map <- bind_rows(lapply(c("top5000", names(network_targets)), map_pathways))
turquoise_matches <- best_matches %>%
  filter(reference_module == "turquoise") %>%
  select(target_network, turquoise_matching_module = target_module,
         turquoise_match_jaccard_shared = jaccard_shared,
         turquoise_match_reference_coverage = reference_coverage,
         turquoise_match_FDR = FDR)
pathway_preservation <- pathway_map %>%
  left_join(robust_pathways %>% select(pathway, collection, median_NES,
                                       max_gsea_FDR, max_camera_FDR), by = "pathway") %>%
  left_join(turquoise_matches, by = c("network" = "target_network")) %>%
  mutate(
    turquoise_matching_module = if_else(network == "top5000", "turquoise",
                                         turquoise_matching_module),
    maps_to_turquoise_lineage = module == turquoise_matching_module
  ) %>%
  arrange(pathway, network, module_rank_for_pathway)
write_csv(pathway_preservation,
          file.path(out_dir, "robust_pathway_module_preservation.csv"))

pathway_top <- pathway_preservation %>%
  filter(module_rank_for_pathway == 1) %>%
  group_by(network) %>%
  mutate(
    pathways_top_in_turquoise_lineage = sum(maps_to_turquoise_lineage),
    all_nine_top_in_one_module = n_distinct(module) == 1
  ) %>%
  ungroup()
write_csv(pathway_top, file.path(out_dir, "robust_pathway_top_modules.csv"))

# Flag response signals that appear only after increasing gene number or lack internal stability.
stability_thresholds <- all_stability %>%
  select(network, module, median_kME_spearman, q05_kME_spearman,
         median_top10pct_hub_jaccard)
response_audit <- all_associations %>%
  filter(test %in% c("M3_NonCR_minus_CR", "M2_SD_PD_minus_CR_PR", "M1_global")) %>%
  left_join(stability_thresholds, by = c("network", "module")) %>%
  group_by(network, module, test) %>%
  mutate(significant_adjustment_count = sum(FDR < molecular_config$fdr_threshold, na.rm = TRUE)) %>%
  ungroup() %>%
  group_by(adjustment, test) %>%
  mutate(significant_network_count = n_distinct(network[FDR < molecular_config$fdr_threshold])) %>%
  ungroup() %>%
  mutate(
    FDR_significant = FDR < molecular_config$fdr_threshold,
    internally_stable =
      median_kME_spearman >= wgcna_config$stability_median_spearman_threshold &
      q05_kME_spearman >= wgcna_config$stability_q05_spearman_threshold,
    significant_but_unstable = FDR_significant & !internally_stable,
    expanded_network_only_signal = FDR_significant & network != "top5000",
    replicated_across_adjustments =
      significant_adjustment_count >= wgcna_config$minimum_replication_count,
    replicated_across_gene_numbers =
      significant_network_count >= wgcna_config$minimum_replication_count
  ) %>%
  arrange(FDR)
write_csv(response_audit, file.path(out_dir, "response_signal_stability_audit.csv"))

# Heat maps use shared-universe Jaccard to avoid penalizing larger networks solely for added genes.
for (target_id in names(network_targets)) {
  plot_data <- module_overlap %>%
    filter(target_network == target_id,
           reference_module != "grey", target_module != "grey")
  p <- ggplot(plot_data, aes(x = target_module, y = reference_module, fill = jaccard_shared)) +
    geom_tile(color = "white", linewidth = 0.25) +
    scale_fill_viridis_c(option = "C", limits = c(0, 1)) +
    theme_bw(base_size = 10) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    labs(x = paste0(target_id, " module"), y = "Locked top5000 module",
         fill = "Jaccard\n(shared genes)",
         title = paste("Module overlap: top5000 vs", target_id))
  ggsave(file.path(fig_dir, paste0("module_overlap_top5000_vs_", target_id, ".png")),
         p, width = 11, height = 7.5, dpi = 180)
  ggsave(file.path(fig_dir, paste0("module_overlap_top5000_vs_", target_id, ".pdf")),
         p, width = 11, height = 7.5)
}

p_pathway <- pathway_preservation %>%
  filter(module_rank_for_pathway <= 5, overlap_n > 0) %>%
  mutate(pathway_short = sub("^[^:]+::", "", pathway)) %>%
  ggplot(aes(x = module, y = pathway_short,
             fill = -log10(pmax(FDR_within_network, 1e-300)), size = overlap_n)) +
  geom_point(shape = 21, color = "grey25") +
  facet_wrap(~network, scales = "free_x", ncol = 1) +
  scale_fill_viridis_c(option = "C") +
  theme_bw(base_size = 9) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  labs(x = "WGCNA module", y = NULL, fill = "-log10 FDR", size = "Overlap genes")
ggsave(file.path(fig_dir, "robust_pathway_module_map_across_gene_numbers.png"),
       p_pathway, width = 12, height = 12, dpi = 180)
ggsave(file.path(fig_dir, "robust_pathway_module_map_across_gene_numbers.pdf"),
       p_pathway, width = 12, height = 12)

# Decision table is descriptive and never chooses a network by significance yield.
turquoise_audit <- best_matches %>%
  filter(reference_module == "turquoise") %>%
  left_join(
    pathway_top %>% group_by(network) %>%
      summarise(pathways_top_in_turquoise_lineage = first(pathways_top_in_turquoise_lineage),
                all_nine_top_in_one_module = first(all_nine_top_in_one_module), .groups = "drop"),
    by = c("target_network" = "network")
  ) %>%
  transmute(
    target_network,
    turquoise_matching_module = target_module,
    jaccard_shared,
    reference_coverage,
    target_shared_coverage,
    overlap_FDR = FDR,
    pathways_top_in_turquoise_lineage,
    all_nine_top_in_one_module
  )
write_csv(turquoise_audit, file.path(out_dir, "turquoise_lineage_preservation.csv"))

sig_audit <- response_audit %>% filter(FDR_significant)
summary_lines <- c(
  paste("WGCNA gene-number sensitivity completed:", format(Sys.time(), tz = "UTC")),
  "The top-5,000 MAD network was retained as the locked primary analysis.",
  paste("Networks compared:", paste(network_summary$network, collapse = ", ")),
  paste("Gene counts:", paste(paste0(network_summary$network, "=", network_summary$genes_after_goodSamplesGenes), collapse = "; ")),
  paste("Soft powers:", paste(paste0(network_summary$network, "=", network_summary$soft_power), collapse = "; ")),
  paste("Non-grey modules:", paste(paste0(network_summary$network, "=", network_summary$non_grey_modules), collapse = "; ")),
  paste("Grey fractions:", paste(paste0(network_summary$network, "=", sprintf("%.3f", network_summary$grey_fraction)), collapse = "; ")),
  paste("FDR-significant response tests across all networks:", nrow(sig_audit)),
  if (nrow(sig_audit)) paste("Significant tests:", paste(paste(sig_audit$network, sig_audit$adjustment,
    sig_audit$test, sig_audit$module, sprintf("q=%.3g", sig_audit$FDR), sep = "/"), collapse = "; ")) else
    "Significant tests: none",
  paste("Expanded-only significant but internally unstable tests:",
        sum(sig_audit$expanded_network_only_signal & sig_audit$significant_but_unstable)),
  "Network choice was not based on which gene count yielded more significant results.",
  "Split-half analyses use fixed full-network module definitions and are not independent validation."
)
writeLines(summary_lines, file.path(log_dir, "wgcna_gene_number_sensitivity_run_summary.txt"))
capture.output(sessionInfo(), file = file.path(log_dir, "sessionInfo_wgcna_gene_number_sensitivity.txt"))
message("WGCNA gene-number sensitivity analysis completed successfully.")
