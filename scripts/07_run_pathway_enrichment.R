#!/usr/bin/env Rscript

# ==============================================================================
# File: 07_run_pathway_enrichment.R
# Purpose: Run ranked pathway enrichment and lock reproducible response-associated scores.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Quality-controlled expression data, curated phenotypes, and MSigDB collections.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; response level order; expression MSigDB
#     selectors and gene-set bounds; molecular FDR/effect/constraint/robustness settings.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Ranked GSEA/CAMERA results, cached GSVA scores, and figures.
# Reproducibility:
#   - Reuses cached MSigDB membership; ranked tests use all eligible genes.
#   - fgsea retains eps=0 and the existing RNG stream; GSVA remains serial.
# ==============================================================================

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(limma)
  library(fgsea)
  library(GSVA)
  library(BiocParallel)
  library(msigdbr)
  library(Biobase)
  library(curatedOvarianData)
  library(ggplot2)
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
for (field in c("msigdb_species", "msigdb_hallmark_collection", "msigdb_reactome_collection",
                "msigdb_reactome_subcollection", "msigdb_gobp_collection", "msigdb_gobp_subcollection")) {
  value <- required_analysis_value(analysis_config, paste0("expression.", field))
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    stop("Invalid MSigDB source setting: expression.", field)
  }
}

qc_rds <- file.path(config$paths$processed_data_dir, "tcga_ov_u133a_expression_qc.rds")
geneset_rds <- file.path(config$paths$processed_data_dir, "msigdb_pathway_collections.rds")
table_dir <- file.path(config$paths$results_dir, "tables", "pathway_enrichment")
figure_dir <- file.path(config$paths$results_dir, "figures", "pathway_enrichment")
log_dir <- file.path(project_dir, "logs")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(qc_rds)) stop("Run scripts/04_run_expression_qc.R first")
qc <- readRDS(qc_rds)
expr <- qc$expression[intersect(qc$model_genes, rownames(qc$expression)), , drop = FALSE]
pheno <- qc$phenotype

# Add slide-based histologic tumor-cell percentage and the package-native response label.
data("TCGA_eset", package = "curatedOvarianData")
curated_pheno <- Biobase::pData(TCGA_eset) %>%
  tibble::rownames_to_column("curated_sample") %>%
  transmute(
    patient = gsub("\\.", "-", substr(unique_patient_ID, 1, 12)),
    curated_response_raw = as.character(primary_therapy_outcome_success),
    curated_response = case_when(
      curated_response_raw == "completeresponse" ~ "CR",
      curated_response_raw == "partialresponse" ~ "PR",
      curated_response_raw == "stabledisease" ~ "SD",
      curated_response_raw == "progressivedisease" ~ "PD",
      TRUE ~ NA_character_
    ),
    pathology_normal_pct = suppressWarnings(as.numeric(as.character(percent_normal_cells))),
    pathology_stromal_pct = suppressWarnings(as.numeric(as.character(percent_stromal_cells))),
    pathology_tumor_pct_raw = suppressWarnings(as.numeric(as.character(percent_tumor_cells)))
  ) %>%
  mutate(
    pathology_all_zero = !is.na(pathology_normal_pct) & !is.na(pathology_stromal_pct) &
      !is.na(pathology_tumor_pct_raw) & pathology_normal_pct == 0 &
      pathology_stromal_pct == 0 & pathology_tumor_pct_raw == 0,
    pathology_tumor_pct = if_else(pathology_all_zero, NA_real_, pathology_tumor_pct_raw)
  ) %>%
  distinct(patient, .keep_all = TRUE)

pheno <- pheno %>%
  left_join(curated_pheno, by = "patient") %>%
  mutate(
    pathology_tumor_pct_z = as.numeric(scale(pathology_tumor_pct)),
    response4 = factor(response4, levels = analysis_config$response$four_levels),
    response_m2 = factor(response_m2, levels = analysis_config$response$objective_response_levels),
    response_m3 = factor(response_m3, levels = analysis_config$response$cr_threshold_levels),
    stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
    residual_group = factor(residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm")),
    tss_collapsed = factor(tss_collapsed),
    age_z = as.numeric(scale(age)),
    diagnosis_year_z = as.numeric(scale(diagnosis_year))
  )

prepare_genesets <- function() {
  if (file.exists(geneset_rds)) return(readRDS(geneset_rds))
  message("Preparing MSigDB Hallmark, Reactome and GO BP collections...")
  # Source selectors are configured; output prefixes are the locked pathway schema.
  h <- msigdbr(species = expression_config$msigdb_species,
               collection = expression_config$msigdb_hallmark_collection) %>%
    transmute(collection = "H", pathway = paste0("H::", gs_name), gene_symbol)
  reactome <- msigdbr(species = expression_config$msigdb_species,
                      collection = expression_config$msigdb_reactome_collection,
                      subcollection = expression_config$msigdb_reactome_subcollection) %>%
    transmute(collection = "REACTOME", pathway = paste0("REACTOME::", gs_name), gene_symbol)
  gobp <- msigdbr(species = expression_config$msigdb_species,
                 collection = expression_config$msigdb_gobp_collection,
                 subcollection = expression_config$msigdb_gobp_subcollection) %>%
    transmute(collection = "GO_BP", pathway = paste0("GO_BP::", gs_name), gene_symbol)
  map <- bind_rows(h, reactome, gobp) %>% distinct(collection, pathway, gene_symbol)
  sets <- split(map$gene_symbol, map$pathway)
  sets <- lapply(sets, unique)
  collection_map <- map %>% distinct(pathway, collection)
  out <- list(sets = sets, collection_map = collection_map, source = "MSigDB via msigdbr")
  saveRDS(out, geneset_rds, compress = "xz")
  out
}

geneset_obj <- prepare_genesets()
all_sets <- lapply(geneset_obj$sets, intersect, y = rownames(expr))
all_sets <- all_sets[
  lengths(all_sets) >= expression_config$pathway_minimum_gene_set_size &
    lengths(all_sets) <= expression_config$maximum_gene_set_size
]
collection_map <- geneset_obj$collection_map %>% filter(pathway %in% names(all_sets))
gsva_sets <- all_sets[collection_map$pathway[collection_map$collection %in% c("H", "REACTOME")]]

make_response_fields <- function(ph, label_column = "response4") {
  lab <- as.character(ph[[label_column]])
  ph %>% mutate(
    response4_model = factor(lab, levels = analysis_config$response$four_levels),
    response_m2_model = factor(case_when(
      lab %in% c("CR", "PR") ~ "CR+PR",
      lab %in% c("SD", "PD") ~ "SD+PD",
      TRUE ~ NA_character_
    ), levels = analysis_config$response$objective_response_levels),
    response_m3_model = factor(case_when(
      lab == "CR" ~ "CR",
      lab %in% c("PR", "SD", "PD") ~ "Non-CR",
      TRUE ~ NA_character_
    ), levels = analysis_config$response$cr_threshold_levels)
  )
}

analysis_specs <- list(
  pre_residual = list(
    label = "response4",
    covariates = c("age_z", "stage_group", "tss_collapsed", "diagnosis_year_z"),
    complete_on = character(0)
  ),
  full = list(
    label = "response4",
    covariates = c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z"),
    complete_on = character(0)
  ),
  matched_no_purity = list(
    label = "response4",
    covariates = c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z"),
    complete_on = "pathology_tumor_pct_z"
  ),
  matched_pathology_purity = list(
    label = "response4",
    covariates = c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z", "pathology_tumor_pct_z"),
    complete_on = "pathology_tumor_pct_z"
  ),
  matched_ESTIMATE_purity = list(
    label = "response4",
    covariates = c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z", "TumorPurity"),
    complete_on = "pathology_tumor_pct_z"
  ),
  curated_full = list(
    label = "curated_response",
    covariates = c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z"),
    complete_on = character(0)
  )
)

prepare_analysis <- function(spec) {
  ph <- make_response_fields(pheno, spec$label)
  required <- unique(c("response4_model", spec$covariates, spec$complete_on))
  ph <- ph[complete.cases(ph[, required, drop = FALSE]), , drop = FALSE] %>%
    mutate(across(where(is.factor), droplevels))
  y <- expr[, ph$sample, drop = FALSE]
  if (!identical(colnames(y), ph$sample)) stop("Expression and phenotype misalignment")
  list(y = y, ph = ph)
}

make_design <- function(response, covariates, ph) {
  design <- model.matrix(
    as.formula(paste("~", paste(c(response, covariates), collapse = " + "))),
    data = ph
  )
  colnames(design) <- make.names(colnames(design), unique = TRUE)
  design
}

fit_contrasts <- function(spec_name, spec) {
  prepared <- prepare_analysis(spec)
  y <- prepared$y
  ph <- prepared$ph
  d1 <- make_design("response4_model", spec$covariates, ph)
  d2 <- make_design("response_m2_model", spec$covariates, ph)
  d3 <- make_design("response_m3_model", spec$covariates, ph)
  f1 <- eBayes(lmFit(y, d1), trend = TRUE, robust = TRUE)
  f2 <- eBayes(lmFit(y, d2), trend = TRUE, robust = TRUE)
  f3 <- eBayes(lmFit(y, d3), trend = TRUE, robust = TRUE)
  contrasts <- list(
    M3_NonCR_vs_CR = list(fit = f3, design = d3, coef = "response_m3_modelNon.CR"),
    M2_SD_PD_vs_CR_PR = list(fit = f2, design = d2, coef = "response_m2_modelSD.PD"),
    M1_PR_vs_CR = list(fit = f1, design = d1, coef = "response4_modelPR"),
    M1_SD_vs_CR = list(fit = f1, design = d1, coef = "response4_modelSD"),
    M1_PD_vs_CR = list(fit = f1, design = d1, coef = "response4_modelPD")
  )
  list(y = y, ph = ph, contrasts = contrasts)
}

# Rank finite moderated t statistics without a DEG cutoff. NES orientation follows
# the original coefficient direction; the later BH family spans all collections
# within each analysis/contrast, rather than changing the testing universe.
run_fgsea <- function(stats, analysis, contrast) {
  stats <- stats[is.finite(stats)]
  stats <- sort(stats, decreasing = TRUE)
  fg <- suppressWarnings(fgseaMultilevel(
    pathways = all_sets,
    stats = stats,
    minSize = expression_config$pathway_minimum_gene_set_size,
    maxSize = expression_config$maximum_gene_set_size,
    eps = 0
  ))
  as_tibble(fg) %>%
    mutate(
      analysis = analysis,
      contrast = contrast,
      leadingEdge = vapply(leadingEdge, paste, collapse = ";", FUN.VALUE = character(1))
    ) %>%
    left_join(collection_map, by = c("pathway" = "pathway"))
}

run_camera <- function(y, design, coefficient, analysis, contrast) {
  camera_sets <- all_sets
  index <- ids2indices(camera_sets, rownames(y), remove.empty = TRUE)
  cam <- camera(y, index = index, design = design, contrast = coefficient, use.ranks = TRUE)
  cam %>%
    tibble::rownames_to_column("pathway") %>%
    as_tibble() %>%
    rename(camera_p = PValue, camera_FDR = FDR, camera_direction = Direction) %>%
    mutate(analysis = analysis, contrast = contrast) %>%
    left_join(collection_map, by = "pathway")
}

# ---- Analysis workflow --------------------------------------------------------
message("Running ranked GSEA and CAMERA...")
gsea_results <- list()
camera_results <- list()
design_summary <- list()
k <- 1L
for (analysis_name in names(analysis_specs)) {
  fit_obj <- fit_contrasts(analysis_name, analysis_specs[[analysis_name]])
  design_summary[[analysis_name]] <- tibble(
    analysis = analysis_name,
    n = ncol(fit_obj$y),
    CR = sum(fit_obj$ph$response4_model == "CR"),
    PR = sum(fit_obj$ph$response4_model == "PR"),
    SD = sum(fit_obj$ph$response4_model == "SD"),
    PD = sum(fit_obj$ph$response4_model == "PD")
  )
  for (contrast_name in names(fit_obj$contrasts)) {
    # Pairwise M1 contrasts are retained for the full models; sensitivity models focus on M2/M3.
    if (grepl("^M1_", contrast_name) && !analysis_name %in% c("full", "curated_full")) next
    obj <- fit_obj$contrasts[[contrast_name]]
    if (!obj$coef %in% colnames(obj$design)) stop("Missing coefficient: ", obj$coef)
    stats <- obj$fit$t[, obj$coef]
    names(stats) <- rownames(obj$fit$t)
    gsea_results[[k]] <- run_fgsea(stats, analysis_name, contrast_name)
    camera_results[[k]] <- run_camera(fit_obj$y, obj$design, obj$coef, analysis_name, contrast_name)
    k <- k + 1L
  }
}
gsea_results <- bind_rows(gsea_results) %>%
  group_by(analysis, contrast) %>%
  mutate(FDR_all_collections = p.adjust(pval, method = "BH")) %>%
  ungroup() %>%
  arrange(analysis, contrast, FDR_all_collections, desc(abs(NES)))
camera_results <- bind_rows(camera_results) %>% arrange(analysis, contrast, camera_FDR)

cross_method <- gsea_results %>%
  select(analysis, contrast, pathway, collection, NES, gsea_p = pval,
         gsea_FDR = FDR_all_collections) %>%
  inner_join(camera_results, by = c("analysis", "contrast", "pathway", "collection")) %>%
  mutate(
    direction_concordant = (NES > 0 & camera_direction == "Up") |
      (NES < 0 & camera_direction == "Down"),
    significant_both = gsea_FDR < molecular_config$fdr_threshold &
      camera_FDR < molecular_config$fdr_threshold & direction_concordant
  )

sensitivity_analyses <- c(
  "pre_residual", "full", "matched_no_purity", "matched_pathology_purity",
  "matched_ESTIMATE_purity", "curated_full"
)
robust_m3 <- cross_method %>%
  filter(contrast == "M3_NonCR_vs_CR", analysis %in% sensitivity_analyses) %>%
  group_by(pathway, collection) %>%
  summarise(
    analyses = n_distinct(analysis),
    both_significant_n = sum(significant_both, na.rm = TRUE),
    direction_consistent = n_distinct(sign(NES[is.finite(NES)])) == 1,
    median_NES = median(NES, na.rm = TRUE),
    max_gsea_FDR = max(gsea_FDR, na.rm = TRUE),
    max_camera_FDR = max(camera_FDR, na.rm = TRUE),
    robust_all = analyses == length(sensitivity_analyses) &
      both_significant_n == length(sensitivity_analyses) & direction_consistent,
    robust_majority = analyses == length(sensitivity_analyses) &
      both_significant_n >= ceiling(molecular_config$robustness_fraction * length(sensitivity_analyses)) &
      direction_consistent,
    .groups = "drop"
  ) %>%
  arrange(desc(robust_all), desc(robust_majority), desc(both_significant_n), max_camera_FDR)

write_csv(gsea_results, file.path(table_dir, "ranked_gsea_all_results.csv"))
write_csv(camera_results, file.path(table_dir, "camera_all_results.csv"))
write_csv(cross_method, file.path(table_dir, "gsea_camera_concordance.csv"))
write_csv(robust_m3, file.path(table_dir, "robust_M3_ranked_pathways.csv"))
write_csv(bind_rows(design_summary), file.path(table_dir, "pathway_analysis_design_summary.csv"))

# Sample-level pathway topology using Hallmark and Reactome GSVA scores.
message("Calculating expanded GSVA scores...")
gsva_param <- gsvaParam(
  exprData = expr,
  geneSets = gsva_sets,
  minSize = expression_config$pathway_minimum_gene_set_size,
  maxSize = expression_config$maximum_gene_set_size,
  kcdf = "Gaussian",
  sparse = FALSE
)
gsva_scores <- gsva(gsva_param, verbose = FALSE, BPPARAM = SerialParam())
saveRDS(gsva_scores, file.path(config$paths$processed_data_dir, "tcga_ov_hallmark_reactome_gsva.rds"), compress = "xz")

extract_one <- function(fit, coefficient, prefix) {
  tt <- topTable(fit, coef = coefficient, number = Inf, sort.by = "none")
  tibble(
    pathway = rownames(tt),
    !!paste0(prefix, "_logFC") := tt$logFC,
    !!paste0(prefix, "_p") := tt$P.Value,
    !!paste0(prefix, "_FDR") := tt$adj.P.Val
  )
}

extract_global <- function(fit, coefficients, prefix) {
  tt <- topTable(fit, coef = coefficients, number = Inf, sort.by = "none")
  tibble(
    pathway = rownames(tt),
    !!paste0(prefix, "_F") := tt$F,
    !!paste0(prefix, "_p") := tt$P.Value,
    !!paste0(prefix, "_FDR") := tt$adj.P.Val
  )
}

model_bic <- function(y, fit, design, suffix) {
  fitted <- fit$coefficients %*% t(design)
  rss <- rowSums((y - fitted)^2)
  n <- ncol(y)
  kval <- qr(design)$rank
  tibble(pathway = rownames(y), !!paste0("BIC_", suffix) := n * log(pmax(rss / n, .Machine$double.eps)) + log(n) * kval)
}

run_gsva_topology <- function(analysis_name, spec) {
  prepared <- prepare_analysis(spec)
  ph <- prepared$ph
  y <- gsva_scores[, ph$sample, drop = FALSE]
  d1 <- make_design("response4_model", spec$covariates, ph)
  d2 <- make_design("response_m2_model", spec$covariates, ph)
  d3 <- make_design("response_m3_model", spec$covariates, ph)
  f1 <- eBayes(lmFit(y, d1), trend = TRUE, robust = TRUE)
  f2 <- eBayes(lmFit(y, d2), trend = TRUE, robust = TRUE)
  f3 <- eBayes(lmFit(y, d3), trend = TRUE, robust = TRUE)
  plateau_contrast <- makeContrasts(
    response4_modelPR - response4_modelSD,
    response4_modelPR - response4_modelPD,
    levels = d1
  )
  plateau_fit <- eBayes(contrasts.fit(f1, plateau_contrast), trend = TRUE, robust = TRUE)
  plateau <- extract_global(plateau_fit, seq_len(ncol(plateau_contrast)), "plateau")
  result <- extract_one(f3, "response_m3_modelNon.CR", "M3") %>%
    left_join(extract_one(f2, "response_m2_modelSD.PD", "M2"), by = "pathway") %>%
    left_join(extract_global(f1, c("response4_modelPR", "response4_modelSD", "response4_modelPD"), "M1_global"), by = "pathway") %>%
    left_join(plateau, by = "pathway") %>%
    left_join(model_bic(y, f1, d1, "M1"), by = "pathway") %>%
    left_join(model_bic(y, f2, d2, "M2"), by = "pathway") %>%
    left_join(model_bic(y, f3, d3, "M3"), by = "pathway") %>%
    mutate(
      best_BIC_model = c("M1", "M2", "M3")[max.col(-as.matrix(select(., BIC_M1, BIC_M2, BIC_M3)), ties.method = "first")],
      threshold_supported = M3_FDR < molecular_config$fdr_threshold &
        abs(M3_logFC) >= molecular_config$pathway_effect_size_threshold &
        plateau_FDR >= molecular_config$constraint_nonrejection_threshold &
        best_BIC_model == "M3",
      analysis = analysis_name,
      n = ncol(y)
    ) %>%
    left_join(collection_map, by = "pathway")
  result
}

message("Running expanded GSVA topology models...")
gsva_topology <- bind_rows(lapply(names(analysis_specs), function(nm) run_gsva_topology(nm, analysis_specs[[nm]])))
gsva_summary <- gsva_topology %>%
  group_by(analysis, n, collection) %>%
  summarise(
    n_pathways = n(),
    min_M3_p = min(M3_p),
    min_M3_FDR = min(M3_FDR),
    M3_FDR_lt_0_05 = sum(M3_FDR < molecular_config$fdr_threshold),
    M1_FDR_lt_0_05 = sum(M1_global_FDR < molecular_config$fdr_threshold),
    threshold_supported = sum(threshold_supported),
    .groups = "drop"
  )
write_csv(gsva_topology, file.path(table_dir, "expanded_gsva_topology_all.csv"))
write_csv(gsva_summary, file.path(table_dir, "expanded_gsva_signal_summary.csv"))

# Figures use FDR-significant pathways when present, otherwise the strongest descriptive pathways.
# Top-N limits below control display density only and do not affect analysis inclusion.
plot_gsea <- gsea_results %>%
  filter(analysis == "full", contrast == "M3_NonCR_vs_CR") %>%
  arrange(FDR_all_collections, desc(abs(NES))) %>%
  group_by(collection) %>%
  slice_head(n = 8) %>%
  ungroup() %>%
  mutate(
    short_pathway = sub("^[^:]+::", "", pathway),
    short_pathway = factor(short_pathway, levels = rev(unique(short_pathway)))
  ) %>%
  ggplot(aes(x = NES, y = short_pathway, color = FDR_all_collections, size = -log10(pmax(pval, 1e-300)))) +
  geom_point() +
  facet_grid(collection ~ ., scales = "free_y", space = "free_y") +
  scale_color_viridis_c(option = "C", direction = -1) +
  theme_bw(base_size = 10) +
  labs(x = "NES (NCR vs CR)", y = NULL, color = "FDR", size = "-log10 p")
ggsave(file.path(figure_dir, "M3_ranked_GSEA_top_pathways.png"), plot_gsea, width = 11, height = 13, dpi = 180)

plot_gsva <- gsva_topology %>%
  filter(analysis %in% c("pre_residual", "full", "matched_no_purity", "matched_pathology_purity", "matched_ESTIMATE_purity")) %>%
  group_by(analysis) %>%
  arrange(M3_p, .by_group = TRUE) %>%
  slice_head(n = 10) %>%
  ungroup() %>%
  distinct(analysis, pathway, .keep_all = TRUE) %>%
  mutate(short_pathway = sub("^[^:]+::", "", pathway)) %>%
  ggplot(aes(x = analysis, y = short_pathway, fill = M3_logFC)) +
  geom_tile(color = "white") +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B", midpoint = 0) +
  theme_bw(base_size = 9) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1)) +
  labs(x = NULL, y = NULL, fill = "M3 logFC")
ggsave(file.path(figure_dir, "expanded_GSVA_M3_top_pathways.png"), plot_gsva, width = 10, height = 12, dpi = 180)

capture.output(sessionInfo(), file = file.path(log_dir, "sessionInfo_pathway_enrichment.txt"))
writeLines(
  c(
    paste("Pathway enrichment completed:", format(Sys.time(), tz = "UTC")),
    paste("Genes analyzed:", nrow(expr)),
    paste("GSEA gene sets:", length(all_sets)),
    paste("GSVA gene sets:", length(gsva_sets)),
    paste("GSEA FDR-significant rows:", sum(
      gsea_results$FDR_all_collections < molecular_config$fdr_threshold, na.rm = TRUE
    )),
    paste("CAMERA FDR-significant rows:", sum(
      camera_results$camera_FDR < molecular_config$fdr_threshold, na.rm = TRUE
    )),
    paste("Concordant pathways significant by both:", sum(cross_method$significant_both, na.rm = TRUE)),
    paste("M3 pathways robust in all six sensitivity analyses:", sum(robust_m3$robust_all, na.rm = TRUE)),
    paste("M3 pathways robust in at least five of six analyses:", sum(robust_m3$robust_majority, na.rm = TRUE)),
    paste("Expanded GSVA M3 FDR-significant rows:", sum(
      gsva_topology$M3_FDR < molecular_config$fdr_threshold, na.rm = TRUE
    )),
    "All ranked enrichment uses complete gene lists; no DEG threshold was used."
  ),
  file.path(log_dir, "pathway_enrichment_run_summary.txt")
)

message("Pathway enrichment analysis completed successfully.")
