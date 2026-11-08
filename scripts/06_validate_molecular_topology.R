#!/usr/bin/env Rscript

# ==============================================================================
# File: 06_validate_molecular_topology.R
# Purpose: Validate molecular topology findings with pathology purity and external data.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - TCGA expression QC, curatedOvarianData TCGA pathology, and cached Hallmark sets.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; response level order; expression gene-set
#     bounds; molecular FDR/effect/constraint thresholds and concordance_gene_count.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Validation estimates, sensitivity tables, and comparison figures.
# Reproducibility:
#   - Uses fixed label/adjustment grids and serial Gaussian-kernel GSVA.
#   - Matched purity comparisons use the same pathology-complete patient set.
# ==============================================================================

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(limma)
  library(GSVA)
  library(BiocParallel)
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
concordance_gene_count <- required_analysis_value(analysis_config, "molecular.concordance_gene_count")
if (!is.numeric(concordance_gene_count) || length(concordance_gene_count) != 1L ||
    !is.finite(concordance_gene_count) || concordance_gene_count < 1 ||
    concordance_gene_count != floor(concordance_gene_count)) {
  stop("molecular.concordance_gene_count must be a positive integer.")
}
concordance_gene_count <- as.integer(concordance_gene_count)

qc_rds <- file.path(config$paths$processed_data_dir, "tcga_ov_u133a_expression_qc.rds")
geneset_rds <- file.path(config$paths$processed_data_dir, "msigdb_hallmark_human.rds")
table_dir <- file.path(config$paths$results_dir, "tables", "molecular_topology")
figure_dir <- file.path(config$paths$results_dir, "figures", "molecular_topology")
log_dir <- file.path(project_dir, "logs")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(qc_rds) || !file.exists(geneset_rds)) {
  stop("Run scripts/04_run_expression_qc.R and scripts/05_fit_molecular_topology.R first")
}

qc <- readRDS(qc_rds)
expr_all <- qc$expression
expr_gene <- expr_all[intersect(qc$model_genes, rownames(expr_all)), , drop = FALSE]
pheno_all <- qc$phenotype

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

pheno_all <- pheno_all %>%
  left_join(curated_pheno, by = "patient") %>%
  mutate(pathology_tumor_pct_z = as.numeric(scale(pathology_tumor_pct)))

hallmark <- readRDS(geneset_rds)
hallmark <- lapply(hallmark, intersect, y = rownames(expr_all))
hallmark <- hallmark[lengths(hallmark) >= expression_config$minimum_gene_set_size]

# ---- Analysis workflow --------------------------------------------------------
message("Calculating Hallmark GSVA scores for validation...")
gsva_param <- gsvaParam(
  exprData = expr_all,
  geneSets = hallmark,
  minSize = expression_config$minimum_gene_set_size,
  maxSize = expression_config$maximum_gene_set_size,
  kcdf = "Gaussian",
  sparse = FALSE
)
expr_hallmark <- gsva(gsva_param, verbose = FALSE, BPPARAM = SerialParam())

adjustment_sets <- list(
  response_only = list(
    covariates = character(0),
    complete_on = character(0)
  ),
  pre_residual_technical = list(
    covariates = c("age_z", "stage_group", "tss_collapsed", "diagnosis_year_z"),
    complete_on = character(0)
  ),
  full_technical = list(
    covariates = c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z"),
    complete_on = character(0)
  ),
  matched_no_purity = list(
    covariates = c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z"),
    complete_on = "pathology_tumor_pct_z"
  ),
  matched_pathology_purity = list(
    covariates = c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z", "pathology_tumor_pct_z"),
    complete_on = "pathology_tumor_pct_z"
  ),
  matched_ESTIMATE_purity = list(
    covariates = c("age_z", "stage_group", "residual_group", "tss_collapsed", "diagnosis_year_z", "TumorPurity"),
    complete_on = "pathology_tumor_pct_z"
  )
)
label_sets <- c(
  unified_supplemental = "response4",
  curatedOvarianData_TCGA = "curated_response",
  xena_primary_clinical = "response_clinical"
)

# complete_on defines the matched sample restriction independently of adjustment;
# matched_no_purity and both purity models therefore use the same pathology subset.
prepare_analysis <- function(expression, phenotype, label_column, covariates, complete_on = character(0)) {
  lab <- as.character(phenotype[[label_column]])
  ph <- phenotype %>%
    mutate(
      response4_model = factor(lab, levels = analysis_config$response$four_levels),
      response_m2_model = factor(
        case_when(
          lab %in% c("CR", "PR") ~ "CR+PR",
          lab %in% c("SD", "PD") ~ "SD+PD",
          TRUE ~ NA_character_
        ),
        levels = analysis_config$response$objective_response_levels
      ),
      response_m3_model = factor(
        case_when(
          lab == "CR" ~ "CR",
          lab %in% c("PR", "SD", "PD") ~ "Non-CR",
          TRUE ~ NA_character_
        ),
        levels = analysis_config$response$cr_threshold_levels
      ),
      stage_group = factor(stage_group, levels = c("I-II", "III", "IV")),
      residual_group = factor(residual_group, levels = c("R0", "1-10 mm", "11-20 mm", ">20 mm")),
      tss_collapsed = factor(tss_collapsed),
      age_z = as.numeric(scale(age)),
      diagnosis_year_z = as.numeric(scale(diagnosis_year))
    )
  required <- unique(c("response4_model", covariates, complete_on))
  ph <- ph[complete.cases(ph[, required, drop = FALSE]), , drop = FALSE] %>%
    mutate(
      response4_model = droplevels(response4_model),
      response_m2_model = droplevels(response_m2_model),
      response_m3_model = droplevels(response_m3_model),
      stage_group = droplevels(stage_group),
      residual_group = droplevels(residual_group),
      tss_collapsed = droplevels(tss_collapsed)
    )
  expression <- expression[, ph$sample, drop = FALSE]
  if (!identical(colnames(expression), ph$sample)) stop("Expression and phenotype misalignment")
  list(expression = expression, phenotype = ph)
}

make_design <- function(response, covariates, ph) {
  rhs <- c(response, covariates)
  design <- model.matrix(as.formula(paste("~", paste(rhs, collapse = " + "))), data = ph)
  colnames(design) <- make.names(colnames(design), unique = TRUE)
  design
}

fit_expression <- function(expression, design) {
  eBayes(lmFit(expression, design), trend = TRUE, robust = TRUE)
}

extract_single <- function(fit, coefficient, prefix) {
  tt <- topTable(fit, coef = coefficient, number = Inf, sort.by = "none")
  tibble(
    feature = rownames(tt),
    !!paste0(prefix, "_logFC") := tt$logFC,
    !!paste0(prefix, "_t") := tt$t,
    !!paste0(prefix, "_p") := tt$P.Value,
    !!paste0(prefix, "_FDR") := tt$adj.P.Val,
    !!paste0(prefix, "_B") := tt$B
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
  cf <- eBayes(contrasts.fit(fit, contrast), trend = TRUE, robust = TRUE)
  extract_global(cf, seq_len(ncol(contrast)), prefix)
}

model_ic <- function(expression, fit, design, suffix) {
  fitted <- fit$coefficients %*% t(design)
  rss <- rowSums((expression - fitted)^2)
  n <- ncol(expression)
  k <- qr(design)$rank
  tibble(
    feature = rownames(expression),
    !!paste0("BIC_", suffix) := n * log(pmax(rss / n, .Machine$double.eps)) + log(n) * k
  )
}

classify_topology <- function(tab, effect_cutoff = molecular_config$gene_effect_size_threshold) {
  tab %>%
    mutate(
      best_BIC_model = c("M1", "M2", "M3")[max.col(-as.matrix(select(., BIC_M1, BIC_M2, BIC_M3)), ties.method = "first")],
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

run_one <- function(expression, phenotype, label_name, label_column, adjustment_name,
                    covariates, complete_on, level) {
  prepared <- prepare_analysis(expression, phenotype, label_column, covariates, complete_on)
  y <- prepared$expression
  ph <- prepared$phenotype
  d1 <- make_design("response4_model", covariates, ph)
  d2 <- make_design("response_m2_model", covariates, ph)
  d3 <- make_design("response_m3_model", covariates, ph)
  f1 <- fit_expression(y, d1)
  f2 <- fit_expression(y, d2)
  f3 <- fit_expression(y, d3)

  m1_coef <- c("response4_modelPR", "response4_modelSD", "response4_modelPD")
  m2_coef <- "response_m2_modelSD.PD"
  m3_coef <- "response_m3_modelNon.CR"
  if (!all(m1_coef %in% colnames(d1)) || !m2_coef %in% colnames(d2) || !m3_coef %in% colnames(d3)) {
    stop("Response coefficients unavailable for ", label_name, " / ", adjustment_name)
  }

  result <- extract_single(f3, m3_coef, "M3") %>%
    left_join(extract_single(f2, m2_coef, "M2"), by = "feature") %>%
    left_join(extract_global(f1, m1_coef, "M1_global"), by = "feature") %>%
    left_join(extract_constraint(
      f1, d1,
      c("response4_modelPR-response4_modelSD", "response4_modelPR-response4_modelPD"),
      "plateau_constraint"
    ), by = "feature") %>%
    left_join(extract_constraint(
      f1, d1,
      c("response4_modelPR", "response4_modelSD-response4_modelPD"),
      "ORR_constraint"
    ), by = "feature") %>%
    left_join(model_ic(y, f1, d1, "M1"), by = "feature") %>%
    left_join(model_ic(y, f2, d2, "M2"), by = "feature") %>%
    left_join(model_ic(y, f3, d3, "M3"), by = "feature") %>%
    classify_topology() %>%
    mutate(
      label_source = label_name,
      adjustment = adjustment_name,
      analysis_id = paste(label_name, adjustment_name, sep = "__"),
      level = level,
      n = ncol(y)
    )

  design <- tibble(
    label_source = label_name,
    adjustment = adjustment_name,
    analysis_id = paste(label_name, adjustment_name, sep = "__"),
    level = level,
    n_samples = ncol(y),
    n_features = nrow(y),
    CR = sum(ph$response4_model == "CR"),
    PR = sum(ph$response4_model == "PR"),
    SD = sum(ph$response4_model == "SD"),
    PD = sum(ph$response4_model == "PD"),
    rank_M1 = qr(d1)$rank,
    rank_M2 = qr(d2)$rank,
    rank_M3 = qr(d3)$rank
  )
  list(result = result, design = design)
}

run_grid <- function(expression, level) {
  output <- list()
  designs <- list()
  i <- 1L
  for (label_name in names(label_sets)) {
    for (adjustment_name in names(adjustment_sets)) {
      message("Running ", level, ": ", label_name, " / ", adjustment_name)
      spec <- adjustment_sets[[adjustment_name]]
      ans <- run_one(
        expression, pheno_all,
        label_name, unname(label_sets[[label_name]]),
        adjustment_name, spec$covariates, spec$complete_on, level
      )
      output[[i]] <- ans$result
      designs[[i]] <- ans$design
      i <- i + 1L
    }
  }
  list(result = bind_rows(output), design = bind_rows(designs))
}

gene <- run_grid(expr_gene, "gene")
pathway <- run_grid(expr_hallmark, "hallmark_pathway")
all_results <- bind_rows(gene$result, pathway$result)
design_summary <- bind_rows(gene$design, pathway$design)

label_audit <- pheno_all %>%
  count(response4, curated_response, response_clinical, name = "n") %>%
  arrange(desc(n), response4, curated_response, response_clinical)

purity_audit <- pheno_all %>%
  summarise(
    response_known_samples = n(),
    pathology_tumor_pct_raw_available = sum(!is.na(pathology_tumor_pct_raw)),
    pathology_all_zero_records = sum(pathology_all_zero, na.rm = TRUE),
    pathology_tumor_pct_clean_available = sum(!is.na(pathology_tumor_pct)),
    ESTIMATE_purity_available = sum(!is.na(TumorPurity)),
    matched_full_model_samples = sum(complete.cases(
      age, stage_group, residual_group, tss_collapsed, diagnosis_year,
      pathology_tumor_pct, TumorPurity
    )),
    pathology_ESTIMATE_pearson = cor(pathology_tumor_pct / 100, TumorPurity, use = "complete.obs", method = "pearson"),
    pathology_ESTIMATE_spearman = cor(pathology_tumor_pct / 100, TumorPurity, use = "complete.obs", method = "spearman")
  )

signal_summary <- all_results %>%
  group_by(level, label_source, adjustment, analysis_id, n) %>%
  summarise(
    n_features = n(),
    min_M3_p = min(M3_p),
    min_M3_FDR = min(M3_FDR),
    raw_M3_p_lt_0_05 = sum(M3_p < molecular_config$fdr_threshold),
    expected_raw_p_lt_0_05 = molecular_config$fdr_threshold * n(),
    FDR_M3_lt_0_05 = sum(M3_FDR < molecular_config$fdr_threshold),
    abs_M3_logFC_median = median(abs(M3_logFC)),
    abs_M3_logFC_q95 = quantile(abs(M3_logFC), 0.95),
    abs_M3_logFC_max = max(abs(M3_logFC)),
    abs_M3_logFC_ge_0_20 = sum(abs(M3_logFC) >= molecular_config$gene_effect_size_threshold),
    M1_global_FDR_lt_0_05 = sum(M1_global_FDR < molecular_config$fdr_threshold),
    threshold_supported = sum(topology_class == "threshold_supported"),
    four_state_heterogeneous = sum(topology_class == "four_state_heterogeneous"),
    ORR_supported = sum(topology_class == "ORR_supported"),
    .groups = "drop"
  )

bic_counts <- all_results %>%
  count(level, label_source, adjustment, analysis_id, best_BIC_model, name = "n_features") %>%
  group_by(level, analysis_id) %>%
  mutate(pct_features = 100 * n_features / sum(n_features)) %>%
  ungroup()

concordance_one <- function(dat, reference_id, comparison_type, included_adjustments = NULL) {
  ref <- dat %>%
    filter(analysis_id == reference_id) %>%
    select(feature, ref_logFC = M3_logFC, ref_p = M3_p)
  if (nrow(ref) == 0) stop("Missing concordance reference: ", reference_id)
  if (!is.null(included_adjustments)) {
    dat <- dat %>% filter(adjustment %in% included_adjustments)
  }
  bind_rows(lapply(split(dat, dat$analysis_id), function(x) {
    paired <- x %>%
      select(feature, M3_logFC, M3_p, analysis_id, label_source, adjustment, level) %>%
      inner_join(ref, by = "feature")
    ref_top <- ref %>% arrange(ref_p) %>% slice_head(n = min(concordance_gene_count, nrow(ref))) %>% pull(feature)
    x_top <- paired %>% arrange(M3_p) %>% slice_head(n = min(concordance_gene_count, nrow(paired))) %>% pull(feature)
    overlap <- intersect(ref_top, x_top)
    tibble(
      level = first(paired$level),
      comparison_type = comparison_type,
      reference_id = reference_id,
      label_source = first(paired$label_source),
      adjustment = first(paired$adjustment),
      analysis_id = first(paired$analysis_id),
      spearman_logFC_vs_reference = cor(paired$M3_logFC, paired$ref_logFC, method = "spearman"),
      sign_concordance_vs_reference = mean(sign(paired$M3_logFC) == sign(paired$ref_logFC)),
      top100_overlap_n = length(overlap),
      top100_sign_concordance = if (length(overlap) > 0) {
        mean(sign(paired$M3_logFC[match(overlap, paired$feature)]) == sign(paired$ref_logFC[match(overlap, paired$feature)]))
      } else {
        NA_real_
      }
    )
  }))
}

matched_adjustments <- c("matched_no_purity", "matched_pathology_purity", "matched_ESTIMATE_purity")
effect_concordance <- bind_rows(
  concordance_one(
    all_results %>% filter(level == "gene"),
    "unified_supplemental__full_technical", "full_model_reference"
  ),
  concordance_one(
    all_results %>% filter(level == "hallmark_pathway"),
    "unified_supplemental__full_technical", "full_model_reference"
  ),
  concordance_one(
    all_results %>% filter(level == "gene"),
    "unified_supplemental__matched_no_purity", "matched_purity_reference", matched_adjustments
  ),
  concordance_one(
    all_results %>% filter(level == "hallmark_pathway"),
    "unified_supplemental__matched_no_purity", "matched_purity_reference", matched_adjustments
  )
)

top_candidates <- all_results %>%
  group_by(level, analysis_id) %>%
  arrange(M3_p, .by_group = TRUE) %>%
  slice_head(n = 30) %>%
  ungroup() %>%
  select(level, label_source, adjustment, analysis_id, feature, M3_logFC, M3_p, M3_FDR,
         M1_global_p, M1_global_FDR, plateau_constraint_p, plateau_constraint_FDR,
         best_BIC_model, topology_class)

write_csv(gene$result, file.path(table_dir, "gene_topology_validation_all.csv"))
write_csv(pathway$result, file.path(table_dir, "hallmark_topology_validation_all.csv"))
write_csv(label_audit, file.path(table_dir, "validation_response_label_audit.csv"))
write_csv(purity_audit, file.path(table_dir, "pathology_ESTIMATE_purity_audit.csv"))
write_csv(design_summary, file.path(table_dir, "validation_design_summary.csv"))
write_csv(signal_summary, file.path(table_dir, "validation_signal_summary.csv"))
write_csv(bic_counts, file.path(table_dir, "validation_bic_counts.csv"))
write_csv(effect_concordance, file.path(table_dir, "validation_effect_concordance.csv"))
write_csv(top_candidates, file.path(table_dir, "validation_top30_candidates.csv"))

p_signal <- signal_summary %>%
  filter(level == "gene") %>%
  ggplot(aes(x = adjustment, y = raw_M3_p_lt_0_05, fill = label_source)) +
  geom_col(position = "dodge") +
  geom_hline(aes(yintercept = expected_raw_p_lt_0_05), linetype = 2, color = "grey35") +
  coord_flip() +
  theme_bw(base_size = 11) +
  labs(x = NULL, y = "Genes with raw M3 p < 0.05", fill = "Label source")
ggsave(file.path(figure_dir, "validation_raw_M3_signal_by_model.png"), p_signal, width = 9, height = 7, dpi = 180)

p_concordance <- effect_concordance %>%
  filter(level == "gene", comparison_type == "full_model_reference") %>%
  ggplot(aes(x = adjustment, y = spearman_logFC_vs_reference, fill = label_source)) +
  geom_col(position = "dodge") +
  scale_y_continuous(limits = c(0, 1)) +
  coord_flip() +
  theme_bw(base_size = 11) +
  labs(x = NULL, y = "Spearman correlation with full-model M3 effects", fill = "Label source")
ggsave(file.path(figure_dir, "validation_M3_effect_concordance.png"), p_concordance, width = 9, height = 7, dpi = 180)

capture.output(sessionInfo(), file = file.path(log_dir, "sessionInfo_molecular_topology_validation.txt"))
writeLines(
  c(
    paste("Molecular topology validation completed:", format(Sys.time(), tz = "UTC")),
    paste("Validation analyses per level:", length(label_sets) * length(adjustment_sets)),
    paste("Gene analyses with any M3 FDR signal:", sum(signal_summary$level == "gene" & signal_summary$FDR_M3_lt_0_05 > 0)),
    paste("Hallmark analyses with any M3 FDR signal:", sum(signal_summary$level == "hallmark_pathway" & signal_summary$FDR_M3_lt_0_05 > 0)),
    paste("Clean pathology tumor-cell percentage available:", purity_audit$pathology_tumor_pct_clean_available),
    paste("Matched full-model samples:", purity_audit$matched_full_model_samples),
    paste("Pathology-ESTIMATE Pearson correlation:", round(purity_audit$pathology_ESTIMATE_pearson, 3)),
    "Non-rejection of a plateau constraint is not evidence of biological equivalence.",
    "The response-only model is descriptive; residual disease and purity adjustment change the biological estimand."
  ),
  file.path(log_dir, "molecular_topology_validation_run_summary.txt")
)

message("Molecular topology validation completed successfully.")
