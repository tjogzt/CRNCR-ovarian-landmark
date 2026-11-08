#!/usr/bin/env Rscript

# ==============================================================================
# File: 13_inventory_external_cohorts.R
# Purpose: Inventory independent ovarian cancer cohorts with response and survival data.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - curatedOvarianData, GEO metadata, and the script-12 locked score gene audit.
# Runtime parameters:
#   - analysis.yml: random_seeds.default; response.four_levels; api.geo_ftp_base_url;
#     external_validation.geo_platforms, log2/shared-gene/duplicate-correlation checks.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
# Outputs:
#   - Cohort eligibility, overlap, phenotype, and endpoint audit tables.
# Reproducibility:
#   - GEO caches and cohort-specific label parsers are retained unchanged.
#   - Inventory/duplicate checks are deterministic and fit no outcome models.
# ==============================================================================

# Phase 4 preparation: inventory external first-line response cohorts.
# Scope: curatedOvarianData (all esets) plus GEO candidates with explicit
# first-line response labels. No outcome model is fitted here; this script only
# audits labels, sample sizes, platforms, locked-score gene coverage and
# cross-dataset sample duplication.

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(curatedOvarianData)
  library(Biobase)
  library(GEOquery)
  library(dplyr)
  library(readr)
  library(tidyr)
  library(stringr)
})

# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)
analysis_config <- config$analysis
external_validation_config <- analysis_config$external_validation
seed <- analysis_config$random_seeds$default
configure_reproducible_runtime(seed, threads = 1L)
geo_platforms <- required_analysis_value(analysis_config, "external_validation.geo_platforms")
if (!is.list(geo_platforms) || !identical(names(geo_platforms), c("GSE63885", "GSE23554")) ||
    !all(vapply(geo_platforms, function(value) is.character(value) && length(value) == 1L &&
      !is.na(value) && nzchar(value), logical(1)))) {
  stop("external_validation.geo_platforms must contain the two ordered GEO/GPL mappings.")
}
out_tab <- file.path(config$paths$results_dir, "tables", "external_response_inventory")
geo_dir <- file.path(config$paths$external_data_dir, "geo_response_cohorts")
dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(geo_dir, recursive = TRUE, showWarnings = FALSE)

locked_audit_path <- file.path(config$paths$results_dir, "tables", "phase3_replication_multiomics",
  "locked_score_gene_audit.csv")
require_input_files(locked_audit_path, "locked score gene audit")
locked <- read_csv(locked_audit_path, show_col_types = FALSE)
if (!all(c("axis", "measured_genes") %in% names(locked)) || !nrow(locked) ||
    anyNA(locked$axis) || anyNA(locked$measured_genes) || anyDuplicated(locked$axis)) {
  stop("Locked score gene audit lacks complete, unique axis definitions.")
}
axes <- setNames(strsplit(locked$measured_genes, ";"), locked$axis)
coverage_row <- function(genes) {
  vapply(axes, function(g) mean(g %in% genes), numeric(1))
}

# ---------------------------------------------------------------- 1. curated
eset_names <- data(package = "curatedOvarianData")$results[, "Item"]
eset_names <- eset_names[grepl("_eset$", eset_names)]
load_eset <- function(nm) {
  env <- new.env()
  data(list = nm, package = "curatedOvarianData", envir = env)
  get(nm, envir = env)
}

curated_rows <- list()
curated_expr <- list()
for (nm in eset_names) {
  e <- load_eset(nm)
  p <- pData(e)
  resp <- p$primary_therapy_outcome_success
  tab <- table(factor(resp, levels = c("completeresponse", "partialresponse",
    "stabledisease", "progressivedisease")))
  hist_ser <- sum(p$histological_type %in% "ser", na.rm = TRUE)
  cov <- coverage_row(featureNames(e))
  curated_rows[[nm]] <- tibble(
    source = "curatedOvarianData", dataset = nm, n_total = ncol(e),
    n_genes = nrow(e), platform = ifelse(length(annotation(e)) && nzchar(annotation(e)),
      annotation(e), NA_character_),
    pmid = paste(experimentData(e)@pubMedIds, collapse = ";"),
    n_serous = hist_ser,
    CR = tab[[1]], PR = tab[[2]], SD = tab[[3]], PD = tab[[4]],
    n_response = sum(tab)
  ) %>% bind_cols(as_tibble(as.list(setNames(cov, paste0("cov_", names(cov))))))
  if (sum(tab) > 0 || nm %in% c("GSE30161_eset", "PMID19318476_eset",
    "PMID15897565_eset")) curated_expr[[nm]] <- e
}
curated_inv <- bind_rows(curated_rows) %>% arrange(desc(n_response))

# Author-level response fields that the curated field does not standardise.
author_field <- function(e, pattern) {
  um <- pData(e)$uncurated_author_metadata
  str_trim(str_match(um, paste0(pattern, "\\s*:\\s*([^/]*)"))[, 2])
}
gse30161 <- load_eset("GSE30161_eset")
gse30161_resp <- author_field(gse30161, "chemoresponse")
gse30009 <- load_eset("GSE30009_eset")
gse30009_resp <- author_field(gse30009, "///characteristics_ch1\\.7: response")
pmid19318476 <- load_eset("PMID19318476_eset")
p193_resp <- na_if(author_field(pmid19318476, "NEW\\.Response"), "")
pmid17290060 <- load_eset("PMID17290060_eset")
p172_resp <- author_field(pmid17290060, "response\\.0\\.NR\\.\\.1\\.CR\\.")

author_labels <- bind_rows(
  tibble(dataset = "GSE30161_eset", label = gse30161_resp,
         histology = pData(gse30161)$histological_type),
  tibble(dataset = "GSE30009_eset", label = gse30009_resp,
         histology = pData(gse30009)$histological_type),
  tibble(dataset = "PMID19318476_eset", label = p193_resp,
         histology = pData(pmid19318476)$histological_type),
  tibble(dataset = "PMID17290060_eset", label = p172_resp,
         histology = pData(pmid17290060)$histological_type)
) %>% count(dataset, histology, label, name = "n")
write_csv(author_labels, file.path(out_tab, "curated_author_response_labels.csv"))

# ---------------------------------------------------------------- 2. GEO
# Series matrices and GPL annotation files are fetched once from the NCBI GEO
# FTP (base URL in config$analysis$api) into geo_dir and then read locally.
geo_ftp <- analysis_config$api$geo_ftp_base_url
geo_ids <- unlist(geo_platforms, use.names = TRUE)
fetch_once <- function(url, dest) {
  if (!file.exists(dest)) download.file(url, dest, mode = "wb", quiet = TRUE)
  dest
}
read_annot <- function(gpl) {
  f <- fetch_once(sprintf("%s/platforms/GPLnnn/%s/annot/%s.annot.gz",
    geo_ftp, gpl, gpl), file.path(geo_dir, paste0(gpl, ".annot.gz")))
  lines <- readLines(gzfile(f))
  start <- grep("^!platform_table_begin", lines) + 1
  end <- grep("^!platform_table_end", lines) - 1
  read_tsv(I(paste(lines[start:end], collapse = "\n")), show_col_types = FALSE,
           col_types = cols(.default = "c"))
}
geo_sets <- list()
for (g in names(geo_ids)) {
  stub <- sub("...$", "nnn", g)
  mf <- fetch_once(sprintf("%s/series/%s/%s/matrix/%s_series_matrix.txt.gz",
    geo_ftp, stub, g, g), file.path(geo_dir, paste0(g, "_series_matrix.txt.gz")))
  es <- getGEO(filename = mf, getGPL = FALSE)
  ann <- read_annot(geo_ids[[g]])
  fData(es) <- data.frame(ID = featureNames(es),
    `Gene Symbol` = ann$`Gene symbol`[match(featureNames(es), ann$ID)],
    check.names = FALSE, row.names = featureNames(es))
  annotation(es) <- geo_ids[[g]]
  geo_sets[[g]] <- es
}

# Keep the first annotated symbol for multi-symbol probes, then retain the probe
# with the highest cohort-wide mean per gene (ties retain original order). The
# log2 trigger and pmax floor reproduce the existing cross-platform transformation.
collapse_to_symbol <- function(es) {
  fd <- fData(es)
  sym <- str_trim(str_split_fixed(fd[["Gene Symbol"]], "///", 2)[, 1])
  x <- exprs(es)
  if (max(x, na.rm = TRUE) > external_validation_config$log2_trigger_maximum) {
    x <- log2(pmax(x, 1))
  }
  keep <- nzchar(sym) & !is.na(sym)
  x <- x[keep, , drop = FALSE]; sym <- sym[keep]
  mu <- rowMeans(x, na.rm = TRUE)
  ord <- order(sym, -mu)
  x <- x[ord, , drop = FALSE]; sym <- sym[ord]
  first <- !duplicated(sym)
  out <- x[first, , drop = FALSE]
  rownames(out) <- sym[first]
  out
}

pchar <- function(es, pattern) {
  p <- pData(es)
  col <- grep(pattern, colnames(p), value = TRUE, ignore.case = TRUE)[1]
  if (is.na(col)) return(rep(NA_character_, nrow(p)))
  as.character(p[[col]])
}

geo_meta <- list()
geo_expr <- list()
# GSE63885: Lisowska et al.; four-class first-line response, mixed histology.
es <- geo_sets$GSE63885
lab <- toupper(str_trim(pchar(es, "clinical status post 1st line")))
lab <- recode(lab, "P" = "PD", "NA" = NA_character_)
hist <- str_remove(pchar(es, "histophatological type"), " ovarian ca\\.$")
grade <- str_extract(pchar(es, "tumor grade"), "G[1-4]|NA")
geo_meta$GSE63885 <- tibble(dataset = "GSE63885", sample = colnames(es),
  response4 = lab, histology = hist, grade = grade,
  stage = pchar(es, "figo_stage"),
  chemo = pchar(es, "adjuwant chemotherapy"),
  platinum_sensitivity = pchar(es, "platinium sensitivity"))
geo_expr$GSE63885 <- collapse_to_symbol(es)

# GSE23554: Marchion et al.; cisplatin-based first-line CR vs IR, serous.
es <- geo_sets$GSE23554
lab <- str_trim(pchar(es, "cisplatin response"))
geo_meta$GSE23554 <- tibble(dataset = "GSE23554", sample = colnames(es),
  response4 = NA_character_, response_binary = lab,
  histology = "serous", grade = pchar(es, "grade"),
  stage = "advanced", chemo = "cisplatin-based", platinum_sensitivity = NA_character_)
geo_expr$GSE23554 <- collapse_to_symbol(es)

geo_meta_all <- bind_rows(geo_meta)
write_csv(geo_meta_all, file.path(out_tab, "geo_candidate_sample_labels.csv"))

geo_inv <- bind_rows(lapply(names(geo_expr), function(g) {
  m <- geo_meta[[g]]
  r4 <- table(factor(m$response4, levels = analysis_config$response$four_levels))
  rb <- if ("response_binary" %in% names(m)) table(m$response_binary) else table(character())
  tibble(source = "GEO", dataset = g, n_total = nrow(m), n_genes = nrow(geo_expr[[g]]),
    platform = annotation(geo_sets[[g]]), pmid = paste(unique(
      unlist(strsplit(experimentData(geo_sets[[g]])@pubMedIds, "\\s+"))), collapse = ";"),
    n_serous = sum(str_detect(m$histology, "serous"), na.rm = TRUE),
    CR = r4[["CR"]] + ifelse("CR" %in% names(rb), rb[["CR"]], 0),
    PR = r4[["PR"]], SD = r4[["SD"]], PD = r4[["PD"]],
    IR_unsplit = ifelse("IR" %in% names(rb), rb[["IR"]], 0),
    n_response = sum(r4) + sum(rb)) %>%
    bind_cols(as_tibble(as.list(setNames(coverage_row(rownames(geo_expr[[g]])),
      paste0("cov_", names(axes))))))
}))

gse63885_by_hist <- geo_meta$GSE63885 %>%
  count(histology, grade, response4, name = "n") %>% arrange(histology, grade, response4)
write_csv(gse63885_by_hist, file.path(out_tab, "GSE63885_response_by_histology_grade.csv"))

# ---------------------------------------------------------------- 3. duplicates
# Gene-centred Pearson correlation above the configured duplicate threshold after
# centring each gene within dataset flags probable identical tumours.
expr_list <- c(lapply(curated_expr, exprs), geo_expr)
expr_list <- expr_list[!grepl("^TCGA", names(expr_list))]
dup_rows <- list()
nms <- names(expr_list)
for (i in seq_along(nms)) for (j in seq_along(nms)) if (i < j) {
  a <- expr_list[[nms[i]]]; b <- expr_list[[nms[j]]]
  g <- intersect(rownames(a), rownames(b))
  if (length(g) < external_validation_config$minimum_shared_genes) next
  a <- a[g, ]; b <- b[g, ]
  a <- a - rowMeans(a, na.rm = TRUE); b <- b - rowMeans(b, na.rm = TRUE)
  r <- cor(a, b, use = "pairwise.complete.obs")
  hits <- which(r > external_validation_config$duplicate_correlation_threshold, arr.ind = TRUE)
  dup_rows[[paste(nms[i], nms[j])]] <- tibble(dataset_a = nms[i], dataset_b = nms[j],
    shared_genes = length(g), n_a = ncol(a), n_b = ncol(b),
    duplicate_pairs = nrow(hits), a_with_match = length(unique(hits[, 1])),
    b_with_match = length(unique(hits[, 2])), max_r = max(r, na.rm = TRUE))
}
dup <- bind_rows(dup_rows) %>% arrange(desc(duplicate_pairs))
write_csv(dup, file.path(out_tab, "cross_dataset_duplicate_audit.csv"))

# Label concordance for the Duke overlap (PMID19318476 within PMID17290060).
a <- exprs(pmid17290060); b <- exprs(pmid19318476)
g <- intersect(rownames(a), rownames(b))
r <- cor(a[g, ] - rowMeans(a[g, ]), b[g, ] - rowMeans(b[g, ]))
best <- apply(r, 2, which.max)
duke_overlap <- tibble(sample_19318476 = colnames(b), best_match_17290060 = colnames(a)[best],
  r = r[cbind(best, seq_along(best))], label_19318476 = p193_resp,
  label_17290060 = p172_resp[best]) %>%
  filter(r > external_validation_config$duplicate_correlation_threshold)
write_csv(duke_overlap, file.path(out_tab, "duke_overlap_label_concordance.csv"))

# ---------------------------------------------------------------- 4. summary
inventory <- bind_rows(curated_inv %>% filter(n_response > 0 | dataset %in%
  c("GSE30161_eset", "GSE30009_eset", "PMID19318476_eset")), geo_inv)
write_csv(curated_inv, file.path(out_tab, "curatedOvarianData_all_esets.csv"))
write_csv(inventory, file.path(out_tab, "external_response_cohort_inventory.csv"))

saveRDS(list(geo_meta = geo_meta_all, geo_expr = geo_expr),
        file.path(config$paths$processed_data_dir, "external_geo_response_cohorts.rds"))

cat("Inventory complete\n")
print(as.data.frame(inventory %>% select(dataset, n_total, platform, CR, PR, SD, PD,
  n_response, cov_general_proliferation, cov_replication_composite)))
print(as.data.frame(dup %>% filter(duplicate_pairs > 0)))
print(as.data.frame(author_labels))
print(as.data.frame(gse63885_by_hist))
print(table(duke_overlap$label_19318476, duke_overlap$label_17290060))
