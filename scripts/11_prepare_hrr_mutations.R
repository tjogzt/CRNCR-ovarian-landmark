#!/usr/bin/env Rscript

# ==============================================================================
# File: 11_prepare_hrr_mutations.R
# Purpose: Prepare complete TCGA-OV BRCA and homologous-recombination-repair mutation status.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - cBioPortal mutation data, sequenced-sample metadata, and expression phenotypes.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; api pinned cBioPortal URLs/study/profile/
#     commit and GDC metadata settings; hrr.panels.*, variant_classes.* and
#     minimum_sequenced_samples.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Patient-level HRR mutation status, coverage audits, and comparison tables.
# Reproducibility:
#   - Panel order is preserved; only official sequenced-list negatives are coded 0.
#   - Deterministic mutation audit; sparse MC3 data never fill unassayed negatives.
# ==============================================================================

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(jsonlite)
  library(ggplot2)
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
configure_reproducible_runtime(seed, threads = 1L)
# Configuration sequences are un-named character vectors in their declared order.
hrr_paths <- c("hrr.panels.brca", "hrr.panels.core", "hrr.panels.extended",
               "hrr.variant_classes.protein_altering", "hrr.variant_classes.likely_lof")
hrr_vectors <- setNames(vector("list", length(hrr_paths)), hrr_paths)
for (path in hrr_paths) {
  value <- unlist(required_analysis_value(analysis_config, path), use.names = FALSE)
  if (!is.character(value) || !length(value) || anyNA(value) ||
      any(!nzchar(value)) || anyDuplicated(value)) {
    stop("HRR configuration must contain a non-empty unique character vector: ", path)
  }
  hrr_vectors[[path]] <- value
}
if (!all(hrr_vectors[["hrr.panels.brca"]] %in% hrr_vectors[["hrr.panels.core"]]) ||
    !all(hrr_vectors[["hrr.panels.core"]] %in% hrr_vectors[["hrr.panels.extended"]]) ||
    !all(hrr_vectors[["hrr.variant_classes.likely_lof"]] %in%
         hrr_vectors[["hrr.variant_classes.protein_altering"]])) {
  stop("HRR panel and variant-class nesting is inconsistent.")
}
minimum_sequenced_samples <- required_analysis_value(analysis_config, "hrr.minimum_sequenced_samples")
if (!is.numeric(minimum_sequenced_samples) || length(minimum_sequenced_samples) != 1L ||
    !is.finite(minimum_sequenced_samples) || minimum_sequenced_samples < 1 ||
    minimum_sequenced_samples != floor(minimum_sequenced_samples)) {
  stop("hrr.minimum_sequenced_samples must be a positive integer.")
}
minimum_sequenced_samples <- as.integer(minimum_sequenced_samples)
external_dir <- file.path(config$paths$external_data_dir, "tcga_ov_cbioportal")
processed_dir <- config$paths$processed_data_dir
table_dir <- file.path(config$paths$results_dir, "tables", "phase3_hrr_mutations")
figure_dir <- file.path(config$paths$results_dir, "figures", "phase3_hrr_mutations")
log_dir <- file.path(project_dir, "logs")
dir.create(external_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

qc_path <- file.path(processed_dir, "tcga_ov_u133a_expression_qc.rds")
local_mc3_path <- file.path(config$paths$xena_dir, "mc3.v0.2.8.PUBLIC.nonsilentGene.xena.gz")
mutation_path <- file.path(external_dir, "data_mutations.txt")
panel_matrix_path <- file.path(external_dir, "data_gene_panel_matrix.txt")
meta_path <- file.path(external_dir, "meta_mutations.txt")
sequenced_ids_path <- file.path(external_dir, "sequenced_sample_ids.json")
study_metadata_path <- file.path(external_dir, "study_metadata.json")
profile_metadata_path <- file.path(external_dir, "mutation_profile_metadata.json")
processed_csv <- file.path(processed_dir, "tcga_ov_hrr_mutation_status.csv")
processed_rds <- file.path(processed_dir, "tcga_ov_hrr_mutation_status.rds")

# Pinned cBioPortal source identifiers come from config$analysis$api so the
# downloaded mutation layer is traceable to one datahub commit.
api_config <- analysis_config$api
study_id <- api_config$cbioportal_study_id
profile_id <- api_config$cbioportal_mutation_profile_id
datahub_commit <- api_config$cbioportal_datahub_commit
gdc_mutation_project_id <- required_analysis_value(analysis_config, "api.gdc_mutation_project_id")
if (!is.character(gdc_mutation_project_id) || length(gdc_mutation_project_id) != 1L ||
    is.na(gdc_mutation_project_id) || !nzchar(gdc_mutation_project_id)) {
  stop("api.gdc_mutation_project_id must be a non-empty project identifier.")
}
gdc_manifest_page_size <- required_analysis_value(analysis_config, "api.gdc_manifest_page_size")
if (!is.numeric(gdc_manifest_page_size) || length(gdc_manifest_page_size) != 1L ||
    !is.finite(gdc_manifest_page_size) || gdc_manifest_page_size < 1 ||
    gdc_manifest_page_size != floor(gdc_manifest_page_size)) {
  stop("api.gdc_manifest_page_size must be a positive integer.")
}
base_media <- paste0(api_config$cbioportal_datahub_media_base_url, "/", datahub_commit,
                     "/public/", study_id, "/")
source_urls <- c(
  data_mutations = paste0(base_media, "data_mutations.txt"),
  gene_panel_matrix = paste0(base_media, "data_gene_panel_matrix.txt"),
  meta_mutations = paste0(api_config$cbioportal_datahub_raw_base_url, "/", datahub_commit,
                          "/public/", study_id, "/meta_mutations.txt"),
  sequenced_sample_ids = paste0(api_config$cbioportal_api_base_url, "/sample-lists/", study_id,
                                "_sequenced/sample-ids"),
  study_metadata = paste0(api_config$cbioportal_api_base_url, "/studies/", study_id),
  mutation_profile_metadata = paste0(api_config$cbioportal_api_base_url, "/molecular-profiles/", profile_id)
)

download_if_missing <- function(url, path) {
  if (file.exists(path) && file.info(path)$size > 0) return(invisible(FALSE))
  message("Downloading ", basename(path), "...")
  download.file(url, path, mode = "wb", quiet = FALSE)
  if (!file.exists(path) || file.info(path)$size == 0) stop("Download failed: ", url)
  invisible(TRUE)
}

if (!file.exists(qc_path)) stop("Missing expression QC object: ", qc_path)
download_if_missing(source_urls[["data_mutations"]], mutation_path)
download_if_missing(source_urls[["gene_panel_matrix"]], panel_matrix_path)
download_if_missing(source_urls[["meta_mutations"]], meta_path)
download_if_missing(source_urls[["sequenced_sample_ids"]], sequenced_ids_path)
download_if_missing(source_urls[["study_metadata"]], study_metadata_path)
download_if_missing(source_urls[["mutation_profile_metadata"]], profile_metadata_path)

canonical_sample <- function(x) gsub("\\.", "-", x)
patient_from_sample <- function(x) substr(canonical_sample(x), 1L, 12L)
write_csv_safe <- function(x, path) write_csv(as.data.frame(x), path, na = "")

qc <- readRDS(qc_path)
pheno <- qc$phenotype
pheno$form_completion_date <- NULL
if (anyDuplicated(pheno$patient)) stop("Expected one expression sample per patient")
project_samples <- canonical_sample(pheno$sample)
project_patients <- pheno$patient

sequenced_samples <- canonical_sample(fromJSON(sequenced_ids_path))
sequenced_patients <- unique(patient_from_sample(sequenced_samples))
if (length(sequenced_samples) < minimum_sequenced_samples) stop("Unexpectedly small cBioPortal sequenced sample list")

# ---- Analysis workflow --------------------------------------------------------
message("Reading cBioPortal PanCancer Atlas OV mutation data...")
mutation_columns <- c(
  "Hugo_Symbol", "Entrez_Gene_Id", "NCBI_Build", "Chromosome", "Start_Position",
  "End_Position", "Reference_Allele", "Tumor_Seq_Allele2", "Tumor_Sample_Barcode",
  "Matched_Norm_Sample_Barcode", "Variant_Classification", "Variant_Type", "HGVSc",
  "HGVSp", "HGVSp_Short", "Transcript_ID", "Protein_position", "Codons", "CLIN_SIG",
  "COSMIC", "FILTER", "IMPACT", "SIFT", "PolyPhen", "t_ref_count", "t_alt_count",
  "n_ref_count", "n_alt_count"
)
mut <- fread(mutation_path, data.table = FALSE, check.names = FALSE,
             select = mutation_columns, na.strings = c("", "NA", "."))
mut <- mut %>%
  mutate(
    sample = canonical_sample(Tumor_Sample_Barcode),
    patient = patient_from_sample(sample),
    in_project_expression_cohort = sample %in% project_samples,
    in_official_sequenced_list = sample %in% sequenced_samples
  )

# Two transparent HRR tiers are retained. The core tier contains genes with relatively
# direct ovarian-cancer HRR relevance; the extended 15-gene tier is a broad sensitivity panel.
brca_genes <- hrr_vectors[["hrr.panels.brca"]]
hrr_core_genes <- hrr_vectors[["hrr.panels.core"]]
hrr_extended_genes <- hrr_vectors[["hrr.panels.extended"]]
protein_altering_classes <- hrr_vectors[["hrr.variant_classes.protein_altering"]]
lof_classes <- hrr_vectors[["hrr.variant_classes.likely_lof"]]

panel_definition <- bind_rows(
  tibble(panel = "BRCA", gene = brca_genes,
         interpretation = "BRCA1/2 only"),
  tibble(panel = "HRR_core", gene = hrr_core_genes,
         interpretation = "BRCA1/2, PALB2, RAD51C/D and BRIP1"),
  tibble(panel = "HRR_extended_15", gene = hrr_extended_genes,
         interpretation = "broad prespecified 15-gene HRR sensitivity panel")
) %>% distinct(panel, gene, .keep_all = TRUE)
write_csv_safe(panel_definition, file.path(table_dir, "hrr_panel_definition.csv"))

project_mut <- mut %>%
  filter(in_project_expression_cohort, Hugo_Symbol %in% hrr_extended_genes) %>%
  mutate(
    protein_altering = Variant_Classification %in% protein_altering_classes,
    likely_lof = Variant_Classification %in% lof_classes,
    panel_BRCA = Hugo_Symbol %in% brca_genes,
    panel_HRR_core = Hugo_Symbol %in% hrr_core_genes,
    panel_HRR_extended = Hugo_Symbol %in% hrr_extended_genes
  )
write_csv_safe(project_mut, file.path(table_dir, "project_hrr_variant_audit.csv"))

all_project_nonsilent <- mut %>%
  filter(in_project_expression_cohort, Variant_Classification %in% protein_altering_classes) %>%
  group_by(patient) %>%
  summarise(total_protein_altering_mutations = n(), .groups = "drop")

variant_status <- project_mut %>%
  filter(protein_altering) %>%
  group_by(patient) %>%
  summarise(
    BRCA_any = as.integer(any(panel_BRCA)),
    BRCA_lof = as.integer(any(panel_BRCA & likely_lof)),
    HRR_core_any = as.integer(any(panel_HRR_core)),
    HRR_core_lof = as.integer(any(panel_HRR_core & likely_lof)),
    HRR_extended_any = as.integer(any(panel_HRR_extended)),
    HRR_extended_lof = as.integer(any(panel_HRR_extended & likely_lof)),
    mutated_HRR_genes = paste(sort(unique(Hugo_Symbol)), collapse = ";"),
    lof_HRR_genes = paste(sort(unique(Hugo_Symbol[likely_lof])), collapse = ";"),
    hrr_variant_count = n(),
    .groups = "drop"
  )

status <- pheno %>%
  transmute(
    sample = canonical_sample(sample), patient, response4, response_m2, response_m3,
    sequenced_cbioportal = sample %in% sequenced_samples
  ) %>%
  left_join(variant_status, by = "patient") %>%
  left_join(all_project_nonsilent, by = "patient")

binary_status <- c(
  "BRCA_any", "BRCA_lof", "HRR_core_any", "HRR_core_lof",
  "HRR_extended_any", "HRR_extended_lof"
)
# A missing variant row becomes a negative only inside the official sequenced
# sample denominator. Unsequenced patients remain NA, even if sparse MC3 is present.
for (field in binary_status) {
  status[[field]] <- ifelse(
    status$sequenced_cbioportal & is.na(status[[field]]), 0L, status[[field]]
  )
  status[[field]][!status$sequenced_cbioportal] <- NA_integer_
}
status$total_protein_altering_mutations <- ifelse(
  status$sequenced_cbioportal & is.na(status$total_protein_altering_mutations),
  0L, status$total_protein_altering_mutations
)
status$total_protein_altering_mutations[!status$sequenced_cbioportal] <- NA_integer_
status$mutated_HRR_genes[status$sequenced_cbioportal & is.na(status$mutated_HRR_genes)] <- ""
status$lof_HRR_genes[status$sequenced_cbioportal & is.na(status$lof_HRR_genes)] <- ""
status$hrr_variant_count[status$sequenced_cbioportal & is.na(status$hrr_variant_count)] <- 0L
status$hrr_variant_count[!status$sequenced_cbioportal] <- NA_integer_

# Formal availability and response audit.
coverage <- status %>%
  group_by(response4) %>%
  summarise(
    total = n(),
    sequenced = sum(sequenced_cbioportal),
    sequenced_fraction = mean(sequenced_cbioportal),
    BRCA_any_n = sum(BRCA_any == 1, na.rm = TRUE),
    BRCA_lof_n = sum(BRCA_lof == 1, na.rm = TRUE),
    HRR_core_any_n = sum(HRR_core_any == 1, na.rm = TRUE),
    HRR_core_lof_n = sum(HRR_core_lof == 1, na.rm = TRUE),
    HRR_extended_any_n = sum(HRR_extended_any == 1, na.rm = TRUE),
    HRR_extended_lof_n = sum(HRR_extended_lof == 1, na.rm = TRUE),
    .groups = "drop"
  )
write_csv_safe(coverage, file.path(table_dir, "mutation_coverage_by_response.csv"))

gene_counts <- project_mut %>%
  filter(protein_altering) %>%
  group_by(Hugo_Symbol) %>%
  summarise(
    variants = n(),
    patients_any = n_distinct(patient),
    patients_lof = n_distinct(patient[likely_lof]),
    missense_variants = sum(Variant_Classification == "Missense_Mutation"),
    lof_variants = sum(likely_lof),
    .groups = "drop"
  ) %>%
  complete(Hugo_Symbol = hrr_extended_genes,
           fill = list(variants = 0L, patients_any = 0L, patients_lof = 0L,
                       missense_variants = 0L, lof_variants = 0L)) %>%
  arrange(desc(patients_any), Hugo_Symbol)
write_csv_safe(gene_counts, file.path(table_dir, "hrr_gene_mutation_counts.csv"))

binary_response_rows <- list()
row_id <- 1L
for (field in binary_status) {
  ok <- !is.na(status[[field]]) & !is.na(status$response_m3)
  tab <- table(status$response_m3[ok], status[[field]][ok])
  p <- if (all(dim(tab) == c(2L, 2L))) fisher.test(tab)$p.value else NA_real_
  binary_response_rows[[row_id]] <- tibble(
    feature = field,
    n = sum(ok),
    CR_positive = sum(status$response_m3[ok] == "CR" & status[[field]][ok] == 1),
    CR_total = sum(status$response_m3[ok] == "CR"),
    NonCR_positive = sum(status$response_m3[ok] == "Non-CR" & status[[field]][ok] == 1),
    NonCR_total = sum(status$response_m3[ok] == "Non-CR"),
    fisher_p = p
  )
  row_id <- row_id + 1L
}
binary_response <- bind_rows(binary_response_rows) %>%
  mutate(FDR = p.adjust(fisher_p, method = "BH")) %>%
  arrange(FDR)
write_csv_safe(binary_response, file.path(table_dir, "hrr_mutation_M3_fisher_audit.csv"))

# Compare against the sparse local Xena MC3 gene matrix without using it to fill negatives.
local_concordance <- tibble()
local_difference <- tibble()
if (file.exists(local_mc3_path)) {
  local <- fread(local_mc3_path, data.table = FALSE, check.names = FALSE)
  gene_col <- names(local)[1]
  local <- local[local[[gene_col]] %in% hrr_extended_genes, , drop = FALSE]
  local_samples <- intersect(names(local)[-1], project_samples)
  local_long <- local %>%
    rename(gene = all_of(gene_col)) %>%
    pivot_longer(cols = all_of(local_samples), names_to = "sample", values_to = "mutated") %>%
    mutate(patient = patient_from_sample(sample), mutated = suppressWarnings(as.numeric(mutated)))
  local_status <- local_long %>%
    group_by(patient) %>%
    summarise(
      local_BRCA_any = as.integer(any(mutated == 1 & gene %in% brca_genes, na.rm = TRUE)),
      local_HRR_core_any = as.integer(any(mutated == 1 & gene %in% hrr_core_genes, na.rm = TRUE)),
      local_HRR_extended_any = as.integer(any(mutated == 1 & gene %in% hrr_extended_genes, na.rm = TRUE)),
      .groups = "drop"
    )
  compare <- status %>%
    inner_join(local_status, by = "patient")
  compare_fields <- tribble(
    ~cbio, ~local,
    "BRCA_any", "local_BRCA_any",
    "HRR_core_any", "local_HRR_core_any",
    "HRR_extended_any", "local_HRR_extended_any"
  )
  kappa_binary <- function(a, b) {
    ok <- !is.na(a) & !is.na(b)
    a <- a[ok]
    b <- b[ok]
    p_obs <- mean(a == b)
    p_exp <- mean(a == 1) * mean(b == 1) + mean(a == 0) * mean(b == 0)
    if (p_exp >= 1) return(NA_real_)
    (p_obs - p_exp) / (1 - p_exp)
  }
  local_concordance <- bind_rows(lapply(seq_len(nrow(compare_fields)), function(i) {
    a <- compare[[compare_fields$cbio[i]]]
    b <- compare[[compare_fields$local[i]]]
    tibble(
      feature = compare_fields$cbio[i],
      shared_assayed_patients = sum(!is.na(a) & !is.na(b)),
      cbio_positive = sum(a == 1, na.rm = TRUE),
      local_positive = sum(b == 1, na.rm = TRUE),
      agreement = mean(a == b, na.rm = TRUE),
      cohen_kappa = kappa_binary(a, b)
    )
  }))
  local_difference <- compare %>%
    filter(
      BRCA_any != local_BRCA_any |
        HRR_core_any != local_HRR_core_any |
        HRR_extended_any != local_HRR_extended_any
    ) %>%
    select(sample, patient, starts_with("BRCA"), starts_with("HRR"), starts_with("local_"))
}
write_csv_safe(local_concordance, file.path(table_dir, "local_mc3_cbioportal_concordance.csv"))
write_csv_safe(local_difference, file.path(table_dir, "local_mc3_cbioportal_discordant_patients.csv"))

# Query GDC public masked-somatic metadata as an independent provenance audit.
gdc_manifest <- tibble()
gdc_audit <- tibble(
  source = "GDC masked somatic mutation metadata",
  endpoint = api_config$gdc_files_url,
  files = NA_integer_, cases = NA_integer_, project_overlap = NA_integer_, status = "query failed"
)
try({
  filters <- list(
    op = "and",
    content = list(
      list(op = "=", content = list(field = "cases.project.project_id", value = list(gdc_mutation_project_id))),
      list(op = "=", content = list(field = "data_type", value = list("Masked Somatic Mutation"))),
      list(op = "=", content = list(field = "access", value = list("open")))
    )
  )
  query <- paste0(
    api_config$gdc_files_url, "?filters=",
    URLencode(toJSON(filters, auto_unbox = TRUE), reserved = TRUE),
    "&fields=file_id,file_name,file_size,md5sum,cases.submitter_id,analysis.workflow_type&format=JSON&size=",
    gdc_manifest_page_size
  )
  response <- fromJSON(query, simplifyVector = FALSE)
  hits <- response$data$hits
  manifest_rows <- lapply(hits, function(hit) {
    cases <- vapply(hit$cases, function(x) x$submitter_id, character(1))
    tibble(
      file_id = hit$file_id,
      file_name = hit$file_name,
      file_size = hit$file_size,
      md5sum = hit$md5sum,
      workflow_type = hit$analysis$workflow_type,
      cases = paste(cases, collapse = ";")
    )
  })
  gdc_manifest <- bind_rows(manifest_rows)
  gdc_cases <- unique(unlist(strsplit(gdc_manifest$cases, ";", fixed = TRUE)))
  gdc_audit <- tibble(
    source = "GDC masked somatic mutation metadata",
    endpoint = api_config$gdc_files_url,
    files = nrow(gdc_manifest),
    cases = length(gdc_cases),
    project_overlap = sum(project_patients %in% gdc_cases),
    status = "success"
  )
}, silent = TRUE)
write_csv_safe(gdc_manifest, file.path(table_dir, "gdc_masked_somatic_manifest.csv"))

study_metadata <- fromJSON(study_metadata_path)
profile_metadata <- fromJSON(profile_metadata_path)
source_audit <- bind_rows(
  tibble(
    source = "cBioPortal Datahub PanCancer Atlas",
    study = study_id,
    profile = profile_id,
    source_url = source_urls[["data_mutations"]],
    datahub_commit = datahub_commit,
    local_file = file.path(
      "external_data_dir", "tcga_ov_cbioportal", basename(mutation_path)
    ),
    local_file_size = file.info(mutation_path)$size,
    local_md5 = unname(tools::md5sum(mutation_path)),
    source_samples = study_metadata$allSampleCount,
    source_sequenced_samples = length(sequenced_samples),
    project_overlap = sum(status$sequenced_cbioportal),
    note = profile_metadata$description
  ),
  tibble(
    source = "local Xena MC3 nonsilent gene matrix",
    study = "PanCancer MC3 local copy",
    profile = "nonsilentGene",
    source_url = NA_character_,
    datahub_commit = NA_character_,
    local_file = file.path("xena_dir", basename(local_mc3_path)),
    local_file_size = if (file.exists(local_mc3_path)) file.info(local_mc3_path)$size else NA_real_,
    local_md5 = if (file.exists(local_mc3_path)) unname(tools::md5sum(local_mc3_path)) else NA_character_,
    source_samples = if (exists("local_samples")) length(names(local)[-1]) else NA_integer_,
    source_sequenced_samples = if (exists("local_samples")) length(local_samples) else NA_integer_,
    project_overlap = if (exists("local_samples")) length(local_samples) else 0L,
    note = "Sparse overlap; retained only for concordance audit"
  )
)
write_csv_safe(source_audit, file.path(table_dir, "mutation_source_audit.csv"))
write_csv_safe(gdc_audit, file.path(table_dir, "gdc_source_audit.csv"))

write_csv_safe(status, processed_csv)
saveRDS(
  list(
    patient_status = status,
    variants = project_mut,
    panel_definition = panel_definition,
    gene_counts = gene_counts,
    source_audit = source_audit,
    gdc_audit = gdc_audit,
    definitions = list(
      protein_altering_classes = protein_altering_classes,
      likely_lof_classes = lof_classes,
      missing_rule = "Only cBioPortal sequenced-list patients without a panel mutation are coded 0; unsequenced patients remain NA"
    )
  ),
  processed_rds,
  compress = "xz"
)

plot_gene_counts <- gene_counts %>%
  mutate(Hugo_Symbol = reorder(Hugo_Symbol, patients_any)) %>%
  ggplot(aes(Hugo_Symbol, patients_any)) +
  geom_col(fill = "#2C7FB8") +
  geom_col(aes(y = patients_lof), fill = "#D95F0E", width = 0.55) +
  coord_flip() +
  theme_bw(base_size = 10) +
  labs(x = NULL, y = "Mutated patients",
       title = "TCGA-OV HRR mutations in the expression-response cohort",
       subtitle = "Blue: any protein-altering; orange: likely loss-of-function")
ggsave(file.path(figure_dir, "hrr_gene_mutation_counts.png"), plot_gene_counts,
       width = 8.5, height = 6.5, dpi = 180)
ggsave(file.path(figure_dir, "hrr_gene_mutation_counts.pdf"), plot_gene_counts,
       width = 8.5, height = 6.5)

summary_lines <- c(
  paste("TCGA-OV HRR mutation preparation completed:", format(Sys.time(), tz = "UTC")),
  paste("cBioPortal study:", study_id),
  paste("Datahub commit:", datahub_commit),
  paste("Study samples:", study_metadata$allSampleCount),
  paste("Official sequenced-list samples:", length(sequenced_samples)),
  paste("Expression-response cohort:", nrow(status)),
  paste("Sequenced expression-response patients:", sum(status$sequenced_cbioportal)),
  paste("Unsequenced expression-response patients kept missing:", sum(!status$sequenced_cbioportal)),
  paste("BRCA any protein-altering:", sum(status$BRCA_any == 1, na.rm = TRUE)),
  paste("BRCA likely LoF:", sum(status$BRCA_lof == 1, na.rm = TRUE)),
  paste("HRR core any protein-altering:", sum(status$HRR_core_any == 1, na.rm = TRUE)),
  paste("HRR core likely LoF:", sum(status$HRR_core_lof == 1, na.rm = TRUE)),
  paste("HRR extended any protein-altering:", sum(status$HRR_extended_any == 1, na.rm = TRUE)),
  paste("HRR extended likely LoF:", sum(status$HRR_extended_lof == 1, na.rm = TRUE)),
  "Missense and likely-LoF statuses are kept separate; no unreviewed missense variant is called pathogenic.",
  "Patients absent from the official sequenced sample list are never coded wild-type."
)
writeLines(summary_lines, file.path(log_dir, "tcga_ov_hrr_mutation_preparation_summary.txt"))
capture.output(sessionInfo(), file = file.path(log_dir, "sessionInfo_tcga_ov_hrr_mutations.txt"))
message("TCGA-OV HRR mutation preparation completed successfully.")
