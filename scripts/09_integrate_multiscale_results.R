#!/usr/bin/env Rscript

# ==============================================================================
# File: 09_integrate_multiscale_results.R
# Purpose: Integrate pathway enrichment and WGCNA results across molecular scales.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Primary WGCNA outputs, pathway-enrichment outputs, and gene-set collections.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; expression gene-set bounds;
#     integration.minimum_overlap_genes; molecular.fdr_threshold.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Integrated module-pathway tables and summary figures.
# Reproducibility:
#   - ORA uses the network-gene universe and excludes grey from candidate modules.
#   - Deterministic integration; top-N annotation exports do not select the network.
# ==============================================================================

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
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
integration_config <- analysis_config$integration
molecular_config <- analysis_config$molecular
seed <- analysis_config$random_seeds$default
configure_reproducible_runtime(seed)

wgcna_dir <- file.path(config$paths$results_dir, "tables", "wgcna")
pathway_dir <- file.path(config$paths$results_dir, "tables", "pathway_enrichment")
geneset_rds <- file.path(config$paths$processed_data_dir, "msigdb_pathway_collections.rds")
out_dir <- file.path(config$paths$results_dir, "tables", "bulk_multiscale_integration")
fig_dir <- file.path(config$paths$results_dir, "figures", "bulk_multiscale_integration")
log_dir <- file.path(project_dir, "logs")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

required <- c(
  file.path(wgcna_dir, "gene_module_kME.csv"),
  file.path(wgcna_dir, "module_annotation.csv"),
  file.path(wgcna_dir, "module_trait_results.csv"),
  file.path(pathway_dir, "robust_M3_ranked_pathways.csv"),
  file.path(pathway_dir, "ranked_gsea_all_results.csv"),
  geneset_rds
)
if (!all(file.exists(required))) stop("Missing prerequisite: ", paste(required[!file.exists(required)], collapse = ", "))

genes <- read_csv(file.path(wgcna_dir, "gene_module_kME.csv"), show_col_types = FALSE)
module_annotation <- read_csv(file.path(wgcna_dir, "module_annotation.csv"), show_col_types = FALSE)
module_traits <- read_csv(file.path(wgcna_dir, "module_trait_results.csv"), show_col_types = FALSE)
robust_pathways <- read_csv(file.path(pathway_dir, "robust_M3_ranked_pathways.csv"), show_col_types = FALSE)
gsea <- read_csv(file.path(pathway_dir, "ranked_gsea_all_results.csv"), show_col_types = FALSE)
geneset_obj <- readRDS(geneset_rds)

universe <- unique(genes$gene)
module_genes <- split(genes$gene[!genes$is_grey], genes$module[!genes$is_grey])
sets <- lapply(geneset_obj$sets, intersect, y = universe)
sets <- sets[
  lengths(sets) >= expression_config$minimum_gene_set_size &
    lengths(sets) <= expression_config$maximum_gene_set_size
]
collection_map <- geneset_obj$collection_map %>% filter(pathway %in% names(sets))

# ---- Analysis workflow --------------------------------------------------------
message("Annotating WGCNA modules by over-representation analysis...")
N <- length(universe)
ora_rows <- vector("list", length(module_genes) * length(sets))
row_id <- 1L
for (module in names(module_genes)) {
  mg <- unique(module_genes[[module]])
  n <- length(mg)
  for (pathway in names(sets)) {
    sg <- unique(sets[[pathway]])
    M <- length(sg)
    overlap <- intersect(mg, sg)
    k <- length(overlap)
    # P[X >= k] uses k-1 in the upper tail. N includes all network genes (also
    # grey); only the module candidate list excludes grey. Preserve both universes.
    p <- if (k > 0) phyper(k - 1, M, N - M, n, lower.tail = FALSE) else 1
    expected <- n * M / N
    ora_rows[[row_id]] <- tibble(
      module = module,
      pathway = pathway,
      module_size = n,
      pathway_size_in_network = M,
      overlap_n = k,
      expected_overlap = expected,
      enrichment_ratio = if (expected > 0) k / expected else NA_real_,
      p_value = p,
      overlap_genes = paste(overlap, collapse = ";")
    )
    row_id <- row_id + 1L
  }
}
module_ora <- bind_rows(ora_rows) %>%
  left_join(collection_map, by = "pathway") %>%
  group_by(module) %>%
  mutate(FDR_within_module = p.adjust(p_value, method = "BH")) %>%
  ungroup() %>%
  mutate(FDR_global = p.adjust(p_value, method = "BH")) %>%
  arrange(FDR_global, FDR_within_module, desc(enrichment_ratio))
write_csv(module_ora, file.path(out_dir, "wgcna_module_pathway_ORA.csv"))

# The overlap threshold controls annotation inclusion; Top-N controls display density only.
module_top_annotations <- module_ora %>%
  filter(overlap_n >= integration_config$minimum_overlap_genes) %>%
  group_by(module, collection) %>%
  arrange(FDR_within_module, desc(enrichment_ratio), .by_group = TRUE) %>%
  slice_head(n = 10) %>%
  ungroup() %>%
  left_join(module_annotation, by = "module") %>%
  arrange(module, collection, FDR_within_module)
write_csv(module_top_annotations, file.path(out_dir, "wgcna_module_top_annotations.csv"))

# Map pathways robust in every M3 sensitivity analysis to modules and to full-model leading edges.
robust_all <- robust_pathways %>% filter(robust_all)
full_leading <- gsea %>%
  filter(analysis == "full", contrast == "M3_NonCR_vs_CR") %>%
  select(pathway, full_NES = NES, full_GSEA_FDR = FDR_all_collections, leadingEdge)

robust_module_map <- module_ora %>%
  filter(pathway %in% robust_all$pathway) %>%
  left_join(robust_all, by = c("pathway", "collection")) %>%
  left_join(full_leading, by = "pathway") %>%
  rowwise() %>%
  mutate(
    leading_edge_overlap_n = {
      le <- unique(strsplit(if_else(is.na(leadingEdge), "", leadingEdge), ";", fixed = TRUE)[[1]])
      le <- le[nzchar(le)]
      length(intersect(module_genes[[module]], le))
    },
    leading_edge_module_genes = {
      le <- unique(strsplit(if_else(is.na(leadingEdge), "", leadingEdge), ";", fixed = TRUE)[[1]])
      le <- le[nzchar(le)]
      paste(intersect(module_genes[[module]], le), collapse = ";")
    }
  ) %>%
  ungroup() %>%
  group_by(pathway) %>%
  arrange(FDR_within_module, desc(leading_edge_overlap_n), desc(enrichment_ratio), .by_group = TRUE) %>%
  mutate(module_rank_for_pathway = row_number()) %>%
  ungroup() %>%
  left_join(module_annotation %>% select(module, microenvironment_class, median_kME_spearman,
                                         median_top10pct_hub_jaccard), by = "module") %>%
  arrange(pathway, module_rank_for_pathway)
write_csv(robust_module_map, file.path(out_dir, "robust_M3_pathway_to_WGCNA_modules.csv"))

# Candidate hierarchy for single-cell and spatial validation.
cellular_plan <- robust_all %>%
  left_join(
    robust_module_map %>% filter(module_rank_for_pathway == 1) %>%
      select(pathway, top_module = module, module_ORA_FDR = FDR_within_module,
             module_enrichment_ratio = enrichment_ratio, leading_edge_overlap_n,
             leading_edge_module_genes, microenvironment_class),
    by = "pathway"
  ) %>%
  mutate(
    direction = if_else(median_NES < 0, "lower in NCR / higher in CR", "higher in NCR / lower in CR"),
    bulk_evidence = "ranked GSEA and CAMERA significant with concordant direction in all six sensitivity analyses; sample-level GSVA not FDR-significant",
    single_cell_test = case_when(
      grepl("E2F|G2M|REPLICATION|REPLICATIVE|CHROMOSOME|ATR|STRAND_ELONGATION", pathway) ~
        "score in malignant-cell pseudobulk by patient; adjust malignant-cell cycle fraction; test M1/M2/M3",
      TRUE ~ "score by major cell type using patient-level pseudobulk; test M1/M2/M3"
    ),
    spatial_test = case_when(
      grepl("E2F|G2M|REPLICATION|REPLICATIVE|CHROMOSOME|ATR|STRAND_ELONGATION", pathway) ~
        "map malignant-cell/spot score and proliferative niches; compare tumor-core, invasive-edge and stromal neighborhoods",
      TRUE ~ "map pathway score and neighborhood composition; compare spatial compartments"
    ),
    priority = case_when(
      collection == "H" ~ "Tier 1",
      collection == "REACTOME" ~ "Tier 1",
      collection == "GO_BP" ~ "Tier 2",
      TRUE ~ "Tier 2"
    )
  ) %>%
  arrange(priority, max_camera_FDR, max_gsea_FDR)
write_csv(cellular_plan, file.path(out_dir, "single_cell_spatial_validation_candidates.csv"))

# Module response evidence summary prevents microenvironment modules from being mistaken for response modules.
module_response_summary <- module_traits %>%
  filter(test %in% c("M3_NonCR_minus_CR", "M2_SD_PD_minus_CR_PR", "M1_global")) %>%
  group_by(module) %>%
  summarise(
    min_response_FDR = min(FDR, na.rm = TRUE),
    response_FDR_lt_0_05 = any(FDR < molecular_config$fdr_threshold, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(module_annotation, by = "module") %>%
  arrange(min_response_FDR)
write_csv(module_response_summary, file.path(out_dir, "wgcna_module_response_summary.csv"))

plot_map <- robust_module_map %>%
  filter(module_rank_for_pathway <= 5, overlap_n > 0) %>%
  mutate(
    pathway_short = sub("^[^:]+::", "", pathway),
    pathway_short = factor(pathway_short, levels = rev(unique(pathway_short)))
  ) %>%
  ggplot(aes(x = module, y = pathway_short, fill = -log10(pmax(FDR_within_module, 1e-300)), size = overlap_n)) +
  geom_point(shape = 21, color = "grey25") +
  scale_fill_viridis_c(option = "C") +
  theme_bw(base_size = 10) +
  labs(x = "WGCNA module", y = NULL, fill = "-log10 module FDR", size = "Overlap genes")
ggsave(file.path(fig_dir, "robust_pathway_WGCNA_module_map.png"), plot_map, width = 11, height = 7.5, dpi = 180)

capture.output(sessionInfo(), file = file.path(log_dir, "sessionInfo_bulk_multiscale_integration.txt"))
writeLines(
  c(
    paste("Bulk multiscale integration completed:", format(Sys.time(), tz = "UTC")),
    paste("Network genes:", N),
    paste("Non-grey modules:", length(module_genes)),
    paste("Pathways tested per module:", length(sets)),
    paste("Robust M3 pathways:", nrow(robust_all)),
    paste("Robust pathways with module ORA FDR < 0.05:", sum(
      robust_module_map$FDR_within_module < molecular_config$fdr_threshold, na.rm = TRUE
    )),
    paste("WGCNA modules with response FDR < 0.05:", sum(module_response_summary$response_FDR_lt_0_05, na.rm = TRUE)),
    "Single-cell and spatial candidates are validation hypotheses, not independent validation results."
  ),
  file.path(log_dir, "bulk_multiscale_integration_run_summary.txt")
)

message("Bulk multiscale integration completed successfully.")
