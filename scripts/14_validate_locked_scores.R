#!/usr/bin/env Rscript

# ==============================================================================
# File: 14_validate_locked_scores.R
# Purpose: Validate locked proliferation and replication scores in independent cohorts.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Locked score definitions and eligible external expression cohorts.
# Runtime parameters:
#   - analysis.yml: random_seeds.external_validation; response level order;
#     external_validation geo_platforms and landmark/log2/coverage/sample/event checks;
#     survival.external_validation_days_per_month; multiomics.proliferation_marker_gene.
#   - paths.yml / CRNCR_PATHS_CONFIG and data-directory environment overrides.
#   - config/submission_profile.json: existing formal-figure specification (read-only).
# Outputs:
#   - External score estimates, survival topology meta-analysis, and figures.
# Reproducibility:
#   - Cohort filters, locked z-mean scores, REML/HKSJ/Firth estimators stay fixed.
#   - These validation fits are deterministic; no time-dependent AUC is added.
# ==============================================================================

# Phase 4: external direction validation of the locked Phase 3 scores and
# external survival topology of first-line response.
#
# Pre-specified in the Phase 4 external-cohort inventory, section 6:
# - Locked gene sets and z-mean algorithm; genes are standardised inside each
#   cohort's analysis set; no gene re-selection.
# - Primary: general_proliferation, Non-CR minus CR (SD units), REML random-
#   effects meta-analysis of GSE63885 (serous), GSE23554, GSE30161 (serous).
# - Secondary: + PMID17290060 (retracted source paper), + TCGA, all histologies,
#   licensing adjusted for proliferation, other locked scores, debulking-
#   adjusted models, TCGA RNA-seq platform consistency.
# Post hoc: leave-one-out re-pooling of the external NCR versus CR OS hazard ratio.
# Response is a post-treatment variable: all results are associations.

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(curatedOvarianData)
  library(Biobase)
  library(GEOquery)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(metafor)
  library(survival)
  library(ggplot2)
  library(patchwork)
})

# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)
analysis_config <- config$analysis
external_validation_config <- analysis_config$external_validation
geo_platforms <- required_analysis_value(analysis_config, "external_validation.geo_platforms")
if (!is.list(geo_platforms) || !identical(names(geo_platforms), c("GSE63885", "GSE23554")) ||
    !all(vapply(geo_platforms, function(value) is.character(value) && length(value) == 1L &&
      !is.na(value) && nzchar(value), logical(1)))) {
  stop("external_validation.geo_platforms must contain the two ordered GEO/GPL mappings.")
}
figure_style <- get_figure_style(project_dir)
figure_spec <- load_figure_specification(project_dir)
figure_text <- figure_text_size(figure_spec)
seed <- analysis_config$random_seeds$external_validation
configure_reproducible_runtime(seed, threads = 1L)
geo_dir <- file.path(config$paths$external_data_dir, "geo_response_cohorts")
out_tab <- file.path(config$paths$results_dir, "tables", "phase4_external_validation")
out_fig <- file.path(config$paths$results_dir, "figures", "phase4_external_validation")
dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)

phase3_path <- file.path(config$paths$processed_data_dir, "tcga_ov_phase3_replication_multiomics.rds")
require_input_files(phase3_path, "locked script-12 multiomics object")
phase3 <- readRDS(phase3_path)
if (!is.list(phase3) || !all(c("axis_genes", "analysis_data") %in% names(phase3)) ||
    !is.list(phase3$axis_genes) || is.null(names(phase3$axis_genes)) || !is.data.frame(phase3$analysis_data)) {
  stop("Script-12 object lacks locked axis_genes or analysis_data.")
}
if (!all(vapply(phase3$axis_genes, function(genes) is.character(genes) &&
    length(genes) > 0L && !anyNA(genes) && all(nzchar(genes)), logical(1)))) {
  stop("Locked axis gene definitions must be non-empty character vectors.")
}
axis_genes <- phase3$axis_genes
tcga <- phase3$analysis_data
score_axes <- names(axis_genes)
landmark_days <- external_validation_config$landmark_days
external_days_per_month <- analysis_config$survival$external_validation_days_per_month
proliferation_marker_gene <- required_analysis_value(analysis_config, "multiomics.proliferation_marker_gene")
if (!is.character(proliferation_marker_gene) || length(proliferation_marker_gene) != 1L ||
    is.na(proliferation_marker_gene) || !nzchar(proliferation_marker_gene)) {
  stop("multiomics.proliferation_marker_gene must be a non-empty gene identifier.")
}

standardize <- function(x) {
  out <- rep(NA_real_, length(x)); ok <- is.finite(x)
  if (sum(ok) >= 2L && sd(x[ok]) > 0) out[ok] <- as.numeric(scale(x[ok]))
  out
}

# Identical algorithm to script 12: gene z across the cohort's analysis samples,
# mean of available axis genes, score standardised to SD 1, excess residuals.
locked_scores <- function(expr) {
  genes_used <- intersect(unique(unlist(axis_genes)), rownames(expr))
  ez <- t(scale(t(expr[genes_used, , drop = FALSE])))
  ez[!is.finite(ez)] <- NA_real_
  sm <- vapply(axis_genes, function(g) colMeans(ez[intersect(g, rownames(ez)), , drop = FALSE],
    na.rm = TRUE), numeric(ncol(ez)))
  df <- as.data.frame(apply(sm, 2L, standardize))
  df$sample <- colnames(expr)
  # Keep the legacy MKI67 output name and the original missing-marker behavior.
  df$MKI67_expression_z <- if (proliferation_marker_gene %in% rownames(expr)) {
    standardize(expr[proliferation_marker_gene, ])
  } else NA_real_
  df$replication_excess <- standardize(residuals(lm(replication_composite ~ general_proliferation, df)))
  df$licensing_excess <- standardize(residuals(lm(replication_licensing ~ general_proliferation, df)))
  df
}
coverage <- function(expr) vapply(axis_genes, function(g) mean(g %in% rownames(expr)), numeric(1))

load_eset <- function(nm) { env <- new.env(); data(list = nm, package = "curatedOvarianData", envir = env); get(nm, envir = env) }
author_field <- function(e, pattern) {
  str_trim(str_match(pData(e)$uncurated_author_metadata, paste0(pattern, "\\s*:\\s*([^/]*)"))[, 2])
}
geo_es <- function(g, gpl) {
  require_input_files(c(file.path(geo_dir, paste0(g, "_series_matrix.txt.gz")),
                       file.path(geo_dir, paste0(gpl, ".annot.gz"))), "cached GEO series/platform")
  es <- getGEO(filename = file.path(geo_dir, paste0(g, "_series_matrix.txt.gz")), getGPL = FALSE)
  lines <- readLines(gzfile(file.path(geo_dir, paste0(gpl, ".annot.gz"))))
  ann <- read_tsv(I(paste(lines[(grep("^!platform_table_begin", lines) + 1):(grep("^!platform_table_end", lines) - 1)],
    collapse = "\n")), show_col_types = FALSE, col_types = cols(.default = "c"))
  sym <- str_trim(str_split_fixed(ann$`Gene symbol`[match(featureNames(es), ann$ID)], "///", 2)[, 1])
  x <- exprs(es)
  if (max(x, na.rm = TRUE) > external_validation_config$log2_trigger_maximum) {
    x <- log2(pmax(x, 1))
  }
  keep <- !is.na(sym) & nzchar(sym); x <- x[keep, ]; sym <- sym[keep]
  ord <- order(sym, -rowMeans(x, na.rm = TRUE)); x <- x[ord, ]; sym <- sym[ord]
  x <- x[!duplicated(sym), ]; rownames(x) <- sym[!duplicated(sym)]
  list(expr = x, pheno = pData(es))
}
pcol <- function(p, pattern) as.character(p[[grep(pattern, colnames(p), value = TRUE, fixed = TRUE)[1]]])

# ------------------------------------------------------------------ cohorts
cohorts <- list()

# GSE63885: four-class labels; OS from GEO; DOD = event.
g <- geo_es("GSE63885", geo_platforms[["GSE63885"]]); p <- g$pheno
lab <- recode(str_trim(pcol(p, "clinical status post 1st line")), "P" = "PD", "NA" = NA_character_)
hist <- str_remove(pcol(p, "histophatological type"), " ovarian ca\\.$")
fu <- pcol(p, "clinical status at last follow-up")
meta <- tibble(sample = colnames(g$expr), response4 = lab, histology = hist,
  grade = str_extract(pcol(p, "tumor grade"), "G[1-4]"),
  stage = pcol(p, "figo_stage"),
  residual = na_if(pcol(p, "residual tumor size"), "NA"),
  os_days = suppressWarnings(as.numeric(pcol(p, "os - overall survival"))),
  os_event = case_when(fu == "DOD" ~ 1L, fu %in% c("AWD", "NED") ~ 0L, TRUE ~ NA_integer_)) %>%
  mutate(debulk_optimal = case_when(residual == "R0" ~ 1L, residual %in% c("R1", "R2") ~ 0L))
cohorts$GSE63885 <- list(expr = g$expr, meta = meta, platform = "U133 Plus 2 (RMA)",
  primary_filter = quote(histology == "serous"), retracted = FALSE)

# GSE23554: cisplatin-based CR vs IR, all advanced serous.
g <- geo_es("GSE23554", geo_platforms[["GSE23554"]]); p <- g$pheno
lab <- str_trim(pcol(p, "cisplatin response"))
meta <- tibble(sample = colnames(g$expr),
  response4 = NA_character_, response_m3 = recode(lab, "CR" = "CR", "IR" = "Non-CR"),
  histology = "serous", grade = paste0("G", pcol(p, "grade")),
  debulk_optimal = case_when(pcol(p, "debulking") == "O" ~ 1L, pcol(p, "debulking") == "S" ~ 0L),
  os_days = as.numeric(pcol(p, "overall survival in days")),
  os_event = as.integer(pcol(p, "vital status") == "Dead"))
cohorts$GSE23554 <- list(expr = g$expr, meta = meta, platform = "U133A (MAS5, log2)",
  primary_filter = quote(TRUE), retracted = FALSE)

# GSE30161 (curatedOvarianData): author chemoresponse field.
e <- load_eset("GSE30161_eset"); p <- pData(e)
lab <- str_extract(author_field(e, "chemoresponse"), "^(CR|PR|SD|PD)")
meta <- tibble(sample = sampleNames(e), response4 = lab,
  histology = recode(p$histological_type, "ser" = "serous"), grade = p$summarygrade,
  debulk_optimal = case_when(p$debulking == "optimal" ~ 1L, p$debulking == "suboptimal" ~ 0L),
  os_days = p$days_to_death, os_event = as.integer(p$vital_status == "deceased"))
cohorts$GSE30161 <- list(expr = exprs(e), meta = meta, platform = "U133 Plus 2 FFPE (curated)",
  primary_filter = quote(histology %in% "serous"), retracted = FALSE)

# PMID17290060 (Dressman 2007, retracted): 0 = not CR, 1 = CR.
e <- load_eset("PMID17290060_eset"); p <- pData(e)
lab <- author_field(e, "response\\.0\\.NR\\.\\.1\\.CR\\.")
meta <- tibble(sample = sampleNames(e), response4 = NA_character_,
  response_m3 = recode(lab, "1" = "CR", "0" = "Non-CR"),
  histology = recode(p$histological_type, "ser" = "serous"), grade = p$summarygrade,
  debulk_optimal = case_when(p$debulking == "optimal" ~ 1L, p$debulking == "suboptimal" ~ 0L),
  os_days = p$days_to_death, os_event = as.integer(p$vital_status == "deceased"))
cohorts$PMID17290060 <- list(expr = exprs(e), meta = meta, platform = "U133A (curated)",
  primary_filter = quote(TRUE), retracted = TRUE)

finalise_meta <- function(m) {
  if (!"response_m3" %in% names(m)) m$response_m3 <- NA_character_
  m %>% mutate(response_m3 = coalesce(response_m3,
      ifelse(is.na(response4), NA_character_, ifelse(response4 == "CR", "CR", "Non-CR"))),
    noncr = as.integer(response_m3 == "Non-CR"))
}
for (nm in names(cohorts)) cohorts[[nm]]$meta <- finalise_meta(cohorts[[nm]]$meta)

# ------------------------------------------------------------- scoring sets
score_cohort <- function(co, set = c("primary", "all_histology")) {
  set <- match.arg(set)
  m <- co$meta %>% filter(!is.na(noncr))
  if (set == "primary") m <- m %>% filter(eval(co$primary_filter))
  ex <- co$expr[, m$sample, drop = FALSE]
  sc <- locked_scores(ex)
  left_join(m, sc, by = "sample")
}

all_scores <- list(); cohort_audit <- list()
for (nm in names(cohorts)) for (set in c("primary", "all_histology")) {
  d <- score_cohort(cohorts[[nm]], set)
  all_scores[[paste(nm, set)]] <- d %>% mutate(cohort = nm, set = set)
  cov <- coverage(cohorts[[nm]]$expr)
  cohort_audit[[paste(nm, set)]] <- tibble(cohort = nm, set = set, platform = cohorts[[nm]]$platform,
    retracted_source = cohorts[[nm]]$retracted, n = nrow(d), CR = sum(d$noncr == 0),
    Non_CR = sum(d$noncr == 1), PR = sum(d$response4 %in% "PR"), SD = sum(d$response4 %in% "SD"),
    PD = sum(d$response4 %in% "PD"), cov_general_proliferation = cov[["general_proliferation"]],
    cov_replication_composite = cov[["replication_composite"]], cov_replication_licensing = cov[["replication_licensing"]])
}
cohort_audit <- bind_rows(cohort_audit)
stopifnot(all(
  cohort_audit$cov_general_proliferation >
    external_validation_config$minimum_gene_coverage_fraction
))
scores_long <- bind_rows(all_scores)
write_csv(cohort_audit, file.path(out_tab, "external_cohort_audit.csv"))
write_csv(scores_long, file.path(out_tab, "external_locked_scores_by_sample.csv"))

# TCGA reference estimates on the identical scale (scores already SD 1).
tcga <- tcga %>% mutate(noncr = as.integer(response_m3 == "Non-CR"))

# ------------------------------------------------------------- estimation
fit_effect <- function(d, score, adjust = NULL) {
  rhs <- c("noncr", adjust)
  if (score == "licensing_given_proliferation") {
    y <- "replication_licensing"; rhs <- c(rhs, "general_proliferation")
  } else y <- score
  dd <- d[complete.cases(d[, c(y, rhs)]), ]
  if (nrow(dd) < external_validation_config$minimum_analysis_samples ||
      length(unique(dd$noncr)) < 2) return(NULL)
  f <- lm(reformulate(rhs, y), dd)
  co <- summary(f)$coefficients["noncr", ]
  tibble(score = score, n = nrow(dd), CR = sum(dd$noncr == 0), Non_CR = sum(dd$noncr == 1),
    estimate = co[[1]], se = co[[2]], p_value = co[[4]])
}
scores_tested <- c("general_proliferation", "replication_composite", "replication_licensing",
  "dna_synthesis", "atr_checkpoint", "robust_nine_composite", "MKI67_expression_z",
  "replication_excess", "licensing_given_proliferation")

est <- list()
for (sc in scores_tested) {
  for (key in names(all_scores)) {
    d <- all_scores[[key]]
    r <- fit_effect(d, sc); if (!is.null(r)) est[[length(est) + 1]] <- r %>%
      mutate(cohort = d$cohort[1], set = d$set[1], adjustment = "none")
    r <- fit_effect(d, sc, "debulk_optimal"); if (!is.null(r)) est[[length(est) + 1]] <- r %>%
      mutate(cohort = d$cohort[1], set = d$set[1], adjustment = "debulking")
  }
  r <- fit_effect(tcga, sc); est[[length(est) + 1]] <- r %>%
    mutate(cohort = "TCGA", set = "primary", adjustment = "none")
}
est <- bind_rows(est)
write_csv(est, file.path(out_tab, "per_cohort_noncr_minus_cr_estimates.csv"))

# ------------------------------------------------------------- meta-analysis
meta_specs <- tribble(
  ~analysis, ~cohorts, ~set, ~adjustment,
  "primary_external", c("GSE63885", "GSE23554", "GSE30161"), "primary", "none",
  "external_plus_retracted", c("GSE63885", "GSE23554", "GSE30161", "PMID17290060"), "primary", "none",
  "external_plus_TCGA", c("GSE63885", "GSE23554", "GSE30161", "TCGA"), "primary", "none",
  "all_cohorts", c("GSE63885", "GSE23554", "GSE30161", "PMID17290060", "TCGA"), "primary", "none",
  "external_all_histology", c("GSE63885", "GSE23554", "GSE30161"), "all_histology", "none",
  "external_debulking_adjusted", c("GSE63885", "GSE23554", "GSE30161"), "primary", "debulking"
)
meta_rows <- list()
for (i in seq_len(nrow(meta_specs))) for (sc in scores_tested) {
  sp <- meta_specs[i, ]
  d <- est %>% filter(score == sc, cohort %in% sp$cohorts[[1]],
    (cohort == "TCGA") | (set == sp$set & adjustment == sp$adjustment))
  if (nrow(d) < 2) next
  m <- rma(yi = d$estimate, sei = d$se, method = "REML")
  mk <- tryCatch(rma(yi = d$estimate, sei = d$se, method = "REML", test = "knha"), error = function(e) NULL)
  fe <- rma(yi = d$estimate, sei = d$se, method = "FE")
  pr <- predict(m)
  meta_rows[[length(meta_rows) + 1]] <- tibble(analysis = sp$analysis, score = sc, k = nrow(d),
    n_total = sum(d$n), cohorts = paste(d$cohort, collapse = ";"),
    negative_direction_k = sum(d$estimate < 0),
    REML_estimate = as.numeric(m$b), REML_low = m$ci.lb, REML_high = m$ci.ub, REML_p = m$pval,
    HKSJ_low = if (!is.null(mk)) mk$ci.lb else NA, HKSJ_high = if (!is.null(mk)) mk$ci.ub else NA,
    HKSJ_p = if (!is.null(mk)) mk$pval else NA,
    FE_estimate = as.numeric(fe$b), FE_low = fe$ci.lb, FE_high = fe$ci.ub, FE_p = fe$pval,
    tau2 = m$tau2, I2 = m$I2, Q_p = m$QEp, PI_low = pr$pi.lb, PI_high = pr$pi.ub)
}
meta_tab <- bind_rows(meta_rows)
write_csv(meta_tab, file.path(out_tab, "meta_analysis_noncr_minus_cr.csv"))

# Compatibility of TCGA with the pooled external estimate (pre-registered).
compat <- meta_tab %>% filter(analysis == "primary_external") %>%
  left_join(est %>% filter(cohort == "TCGA") %>% select(score, tcga_estimate = estimate, tcga_se = se), by = "score") %>%
  mutate(external_se = (REML_high - REML_low) / (2 * qnorm(0.975)),
    difference = REML_estimate - tcga_estimate,
    z = difference / sqrt(external_se^2 + tcga_se^2), p_difference = 2 * pnorm(-abs(z))) %>%
  select(score, tcga_estimate, tcga_se, external_estimate = REML_estimate, external_se, difference, p_difference)
write_csv(compat, file.path(out_tab, "tcga_vs_external_compatibility.csv"))

# ------------------------------------------------- GSE63885 four-class view
g4 <- all_scores[["GSE63885 primary"]] %>% filter(!is.na(response4)) %>%
  mutate(response4 = factor(response4, levels = analysis_config$response$four_levels))
m1 <- lm(general_proliferation ~ response4, g4); m3 <- lm(general_proliferation ~ noncr, g4)
g4_summary <- g4 %>% group_by(response4) %>% summarise(n = n(),
  mean_proliferation = mean(general_proliferation), sd = sd(general_proliferation),
  mean_licensing = mean(replication_licensing), .groups = "drop")
g4_tests <- tibble(test = c("plateau_PR_SD_PD_equal (M3 vs M1, F)", "global_M1 (F)"),
  p_value = c(anova(m3, m1)$`Pr(>F)`[2], anova(lm(general_proliferation ~ 1, g4), m1)$`Pr(>F)`[2]))
write_csv(g4_summary, file.path(out_tab, "GSE63885_four_class_scores.csv"))
write_csv(g4_tests, file.path(out_tab, "GSE63885_four_class_tests.csv"))

# ------------------------------------------------ TCGA RNA-seq consistency
e <- load_eset("TCGA.RNASeqV2_eset")
rs_patient <- str_sub(str_replace_all(sampleNames(e), "\\.", "-"), 1, 12)
keep <- rs_patient %in% tcga$patient & !duplicated(rs_patient)
rs_expr <- exprs(e)[, keep]; colnames(rs_expr) <- rs_patient[keep]
rs_scores <- locked_scores(rs_expr) %>% rename(patient = sample)
rs_join <- inner_join(rs_scores, tcga %>% select(patient, noncr, response4,
  any_of(c(scores_tested[scores_tested != "licensing_given_proliferation"]))), by = "patient", suffix = c("_rnaseq", "_array"))
rnaseq_corr <- bind_rows(lapply(setdiff(scores_tested, "licensing_given_proliferation"), function(sc) {
  a <- rs_join[[paste0(sc, "_array")]]; b <- rs_join[[paste0(sc, "_rnaseq")]]
  tibble(score = sc, n = sum(complete.cases(a, b)), spearman = cor(a, b, method = "spearman", use = "complete.obs"))
}))
rs_est <- bind_rows(lapply(c("general_proliferation", "replication_composite", "replication_licensing"), function(sc) {
  d <- rs_join %>% transmute(noncr, y = .data[[paste0(sc, "_rnaseq")]], x = .data[[paste0(sc, "_array")]])
  a <- summary(lm(y ~ noncr, d))$coefficients["noncr", ]; b <- summary(lm(x ~ noncr, d))$coefficients["noncr", ]
  tibble(score = sc, n = nrow(d), rnaseq_estimate = a[[1]], rnaseq_p = a[[4]], array_same_patients_estimate = b[[1]], array_p = b[[4]])
}))
write_csv(rnaseq_corr, file.path(out_tab, "tcga_rnaseq_array_score_correlation.csv"))
write_csv(rs_est, file.path(out_tab, "tcga_rnaseq_array_noncr_estimates.csv"))

# ------------------------------------------------ survival topology (OS)
# Response is assessed after first-line therapy. The fixed landmark excludes
# deaths/censoring at or before that day and resets time; it cannot establish the
# unknown response-assessment date or eliminate all guarantee-time bias.
surv_sets <- list(
  GSE63885 = cohorts$GSE63885$meta %>% filter(histology == "serous"),
  GSE23554 = cohorts$GSE23554$meta,
  GSE30161 = cohorts$GSE30161$meta %>% filter(histology %in% "serous"),
  PMID17290060 = cohorts$PMID17290060$meta,
  TCGA = tcga %>% transmute(sample, response4 = as.character(response4), noncr,
    os_days = OS_days, os_event = OS_event)
)
cox_rows <- list(); topo_rows <- list(); km_data <- list()
# Per-sample survival/response data for manuscript display items (script 20).
write_csv(bind_rows(lapply(names(surv_sets)[names(surv_sets) != "TCGA"], function(nm)
  surv_sets[[nm]] %>% transmute(cohort = nm, sample, response4, noncr, os_days, os_event,
    debulk_optimal = if ("debulk_optimal" %in% names(.)) debulk_optimal else NA_integer_,
    grade = if ("grade" %in% names(.)) as.character(grade) else NA_character_,
    stage = if ("stage" %in% names(.)) as.character(stage) else NA_character_))),
  file.path(out_tab, "external_survival_by_sample.csv"))
for (nm in names(surv_sets)) for (lm_days in c(0, landmark_days)) {
  d <- surv_sets[[nm]] %>% filter(!is.na(noncr), is.finite(os_days), !is.na(os_event), os_days > lm_days) %>%
    mutate(time = (os_days - lm_days) / external_days_per_month)
  if (sum(d$os_event) < external_validation_config$minimum_survival_events) next
  f <- coxph(Surv(time, os_event) ~ noncr, d)
  s <- summary(f)
  cox_rows[[length(cox_rows) + 1]] <- tibble(cohort = nm, landmark_days = lm_days, n = nrow(d), events = sum(d$os_event),
    CR = sum(d$noncr == 0), Non_CR = sum(d$noncr == 1), log_HR = coef(f)[[1]], se = sqrt(vcov(f)[1, 1]),
    HR = s$conf.int[1, 1], HR_low = s$conf.int[1, 3], HR_high = s$conf.int[1, 4], p_value = s$coefficients[1, 5])
  if (all(!is.na(d$response4))) {
    d4 <- d %>% mutate(response4 = factor(response4, levels = analysis_config$response$four_levels)) %>% droplevels()
    if (nlevels(d4$response4) >= 3) {
      f1 <- coxph(Surv(time, os_event) ~ response4, d4); f3 <- coxph(Surv(time, os_event) ~ noncr, d4)
      lrt <- 2 * (f1$loglik[2] - f3$loglik[2]); df <- nlevels(d4$response4) - 2
      hr <- exp(coef(f1))
      topo_rows[[length(topo_rows) + 1]] <- tibble(cohort = nm, landmark_days = lm_days, n = nrow(d4),
        events = sum(d4$os_event), levels = paste(levels(d4$response4), table(d4$response4), sep = ":", collapse = ","),
        HR_PR = hr["response4PR"], HR_SD = if ("response4SD" %in% names(hr)) hr["response4SD"] else NA,
        HR_PD = if ("response4PD" %in% names(hr)) hr["response4PD"] else NA,
        plateau_LRT = lrt, plateau_df = df, plateau_p = pchisq(lrt, df, lower.tail = FALSE),
        AIC_M1 = AIC(f1), AIC_M3 = AIC(f3))
    }
  }
  if (lm_days == landmark_days) km_data[[nm]] <- d %>% mutate(cohort = nm)
}
cox_tab <- bind_rows(cox_rows); topo_tab <- bind_rows(topo_rows)
write_csv(cox_tab, file.path(out_tab, "os_cox_noncr_vs_cr.csv"))
write_csv(topo_tab, file.path(out_tab, "os_four_class_plateau_tests.csv"))

surv_meta <- bind_rows(lapply(c(0, landmark_days), function(lmd) {
  bind_rows(lapply(list(primary_external = c("GSE63885", "GSE23554", "GSE30161"),
      external_plus_retracted = c("GSE63885", "GSE23554", "GSE30161", "PMID17290060")), function(cs) {
    d <- cox_tab %>% filter(landmark_days == lmd, cohort %in% cs)
    m <- rma(yi = d$log_HR, sei = d$se, method = "REML")
    tibble(landmark_days = lmd, cohorts = paste(d$cohort, collapse = ";"), k = nrow(d),
      HR = exp(as.numeric(m$b)), HR_low = exp(m$ci.lb), HR_high = exp(m$ci.ub), p_value = m$pval, I2 = m$I2)
  }))
}))
write_csv(surv_meta, file.path(out_tab, "os_meta_noncr_vs_cr.csv"))

# Leave-one-out sensitivity of the pooled NCR versus CR hazard ratio (post hoc).
# Each cohort is omitted in turn and the remaining cohorts are re-pooled by REML.
# With k<=4, funnel-plot asymmetry tests are not informative and are not run.
meta_sets <- list(primary_external = c("GSE63885", "GSE23554", "GSE30161"),
  external_plus_retracted = c("GSE63885", "GSE23554", "GSE30161", "PMID17290060"))
surv_meta_loo <- bind_rows(lapply(c(0, landmark_days), function(lmd) {
  bind_rows(lapply(names(meta_sets), function(an) {
    d_all <- cox_tab %>% filter(landmark_days == lmd, cohort %in% meta_sets[[an]])
    bind_rows(lapply(d_all$cohort, function(omit) {
      d <- d_all %>% filter(cohort != omit)
      m <- rma(yi = d$log_HR, sei = d$se, method = "REML")
      tibble(landmark_days = lmd, analysis = an, omitted = omit, cohorts = paste(d$cohort, collapse = ";"),
        k = nrow(d), events = sum(d$events), HR = exp(as.numeric(m$b)), HR_low = exp(m$ci.lb),
        HR_high = exp(m$ci.ub), p_value = m$pval, I2 = m$I2)
    }))
  }))
}))
write_csv(surv_meta_loo, file.path(out_tab, "os_meta_noncr_vs_cr_leave_one_out.csv"))

# Small-sample checks of the pooled NCR versus CR hazard ratio (post hoc,
# pre-submission review 2026-10-19): Hartung-Knapp-Sidik-Jonkman intervals and
# REML prediction intervals; and Firth-penalised Cox estimates for each external
# cohort, re-pooled. Deterministic; no random numbers are drawn.
firth_rows <- bind_rows(lapply(c("GSE63885", "GSE23554", "GSE30161", "PMID17290060"), function(nm) {
  d <- surv_sets[[nm]] %>% filter(!is.na(noncr), is.finite(os_days), !is.na(os_event), os_days > landmark_days) %>%
    mutate(time = (os_days - landmark_days) / external_days_per_month)
  f <- coxphf::coxphf(Surv(time, os_event) ~ noncr, data = as.data.frame(d))
  tibble(cohort = nm, landmark_days = landmark_days, log_HR = unname(f$coefficients[1]), se = sqrt(f$var[1, 1]),
    HR = exp(unname(f$coefficients[1])), HR_low = unname(f$ci.lower[1]), HR_high = unname(f$ci.upper[1]))
}))
small_sample_meta <- bind_rows(lapply(names(meta_sets), function(an) {
  d <- cox_tab %>% filter(landmark_days == !!landmark_days, cohort %in% meta_sets[[an]])
  df <- firth_rows %>% filter(cohort %in% meta_sets[[an]])
  m <- rma(yi = d$log_HR, sei = d$se, method = "REML")
  mk <- rma(yi = d$log_HR, sei = d$se, method = "REML", test = "knha")
  mf <- rma(yi = df$log_HR, sei = df$se, method = "REML")
  pr <- predict(m)
  bind_rows(
    tibble(analysis = an, estimator = "Cox, REML (Wald CI)", HR = exp(as.numeric(m$b)), HR_low = exp(m$ci.lb), HR_high = exp(m$ci.ub),
      PI_low = exp(pr$pi.lb), PI_high = exp(pr$pi.ub), I2 = m$I2),
    tibble(analysis = an, estimator = "Cox, REML (HKSJ CI)", HR = exp(as.numeric(mk$b)), HR_low = exp(mk$ci.lb), HR_high = exp(mk$ci.ub),
      PI_low = NA_real_, PI_high = NA_real_, I2 = mk$I2),
    tibble(analysis = an, estimator = "Firth Cox, REML (Wald CI)", HR = exp(as.numeric(mf$b)), HR_low = exp(mf$ci.lb), HR_high = exp(mf$ci.ub),
      PI_low = NA_real_, PI_high = NA_real_, I2 = mf$I2)) %>%
    mutate(landmark_days = landmark_days, k = nrow(d), .before = 1)
}))
write_csv(firth_rows, file.path(out_tab, "os_cox_noncr_vs_cr_firth.csv"))
write_csv(small_sample_meta, file.path(out_tab, "os_meta_noncr_vs_cr_small_sample.csv"))

# Post hoc (flagged exploratory; motivated by the GSE63885 PD estimate):
# does PD form a second step below PR/SD? Compare M3 (CR | rest), M_PD
# (CR | PR+SD | PD) and M1 (four states) in the two four-class cohorts.
step_rows <- list(); pd_rows <- list()
for (nm in c("TCGA", "GSE63885")) for (lm_days in c(0, landmark_days)) {
  d <- surv_sets[[nm]] %>% filter(!is.na(response4), is.finite(os_days), !is.na(os_event), os_days > lm_days) %>%
    mutate(time = (os_days - lm_days) / external_days_per_month,
      response4 = factor(response4, levels = analysis_config$response$four_levels),
      pd_step = factor(case_when(response4 == "CR" ~ "CR", response4 == "PD" ~ "PD", TRUE ~ "PR_SD"),
        levels = c("CR", "PR_SD", "PD")))
  fits <- list(M3 = coxph(Surv(time, os_event) ~ noncr, d),
    M_PD = coxph(Surv(time, os_event) ~ pd_step, d),
    M1 = coxph(Surv(time, os_event) ~ response4, d))
  step_rows[[length(step_rows) + 1]] <- tibble(cohort = nm, landmark_days = lm_days, n = nrow(d),
    model = names(fits), df = vapply(fits, function(f) length(coef(f)), integer(1)),
    AIC = vapply(fits, AIC, numeric(1)),
    LRT_vs_M3_p = c(NA, vapply(fits[-1], function(f) pchisq(2 * (f$loglik[2] - fits$M3$loglik[2]),
      length(coef(f)) - 1, lower.tail = FALSE), numeric(1))),
    LRT_M1_vs_M_PD_p = c(NA, NA, pchisq(2 * (fits$M1$loglik[2] - fits$M_PD$loglik[2]), 1, lower.tail = FALSE)))
  dn <- d %>% filter(response4 != "CR") %>% mutate(pd = as.integer(response4 == "PD"))
  f <- coxph(Surv(time, os_event) ~ pd, dn)
  pd_rows[[length(pd_rows) + 1]] <- tibble(cohort = nm, landmark_days = lm_days, n_nonCR = nrow(dn),
    PD = sum(dn$pd), log_HR = coef(f)[[1]], se = sqrt(vcov(f)[1, 1]), HR = exp(coef(f)[[1]]),
    HR_low = exp(confint(f)[1, 1]), HR_high = exp(confint(f)[1, 2]),
    p_value = summary(f)$coefficients[1, 5])
}
step_tab <- bind_rows(step_rows) %>% group_by(cohort, landmark_days) %>%
  mutate(delta_AIC_vs_best = AIC - min(AIC)) %>% ungroup()
pd_tab <- bind_rows(pd_rows)
pd_meta <- bind_rows(lapply(c(0, landmark_days), function(lmd) {
  d <- pd_tab %>% filter(landmark_days == lmd)
  m <- rma(yi = d$log_HR, sei = d$se, method = "REML")
  tibble(landmark_days = lmd, k = nrow(d), HR = exp(as.numeric(m$b)), HR_low = exp(m$ci.lb),
    HR_high = exp(m$ci.ub), p_value = m$pval, I2 = m$I2)
}))
write_csv(step_tab, file.path(out_tab, "os_posthoc_pd_step_model_comparison.csv"))
write_csv(pd_tab, file.path(out_tab, "os_posthoc_pd_vs_pr_sd.csv"))
write_csv(pd_meta, file.path(out_tab, "os_posthoc_pd_vs_pr_sd_meta.csv"))

# ------------------------------------------------------------------ figures
lab_cohort <- function(x) recode(x, PMID17290060 = "PMID17290060 (retracted)")
# Figure S5 labels use a comma form to avoid stacked parentheses on the
# retracted row; the KM diagnostic figure keeps the shared "(retracted)" form.
lab_s5 <- function(x) recode(x, TCGA = "TCGA-OV", PMID17290060 = "PMID17290060, retracted")
fp <- est %>% filter(score == "general_proliferation", adjustment == "none", set == "primary") %>%
  mutate(label = sprintf("%s (CR %d / NCR %d)", lab_s5(cohort), CR, Non_CR),
         low = estimate - 1.96 * se, high = estimate + 1.96 * se,
         type = if_else(cohort == "PMID17290060", "retracted", "cohort"),
         txt = sprintf("%.2f (%.2f–%.2f)", estimate, low, high))
pm <- meta_tab %>% filter(score == "general_proliferation",
  analysis %in% c("primary_external", "external_plus_retracted", "all_cohorts")) %>%
  transmute(label = recode(analysis, primary_external = "Pooled external (primary)",
    external_plus_retracted = "Pooled external + retracted", all_cohorts = "Pooled all incl. TCGA"),
    estimate = REML_estimate, low = REML_low, high = REML_high, type = "pooled",
    txt = sprintf("%.2f (%.2f–%.2f)", REML_estimate, REML_low, REML_high))
fdat <- bind_rows(fp, pm) %>% mutate(label = factor(label, levels = rev(c(fp$label, pm$label))))
# Coordinate panels open their axes exactly like Figures 2-3 and S1-S4:
# no panel box, black left/bottom axis lines, light grey major gridlines.
s5_open_axes <- theme(
  panel.border = element_blank(),
  axis.line = element_line(colour = "black", linewidth = 0.4),
  panel.grid.major = element_line(linewidth = 0.3, colour = "grey88")
)
p_forest <- ggplot(fdat, aes(estimate, label, xmin = low, xmax = high, shape = type, colour = type)) +
  geom_vline(xintercept = 0, linetype = 2, colour = figure_style$neutral[["mid"]]) +
  geom_errorbarh(height = 0.2) +
  # Retracted source keeps its approved Figure 3A encoding: #6E6E6E open
  # circle with a 0.7-pt outline, distinct from primary cohorts.
  geom_point(data = dplyr::filter(fdat, type != "retracted"), size = 3, stroke = 0.5) +
  geom_point(data = dplyr::filter(fdat, type == "retracted"), size = 3, stroke = 0.7) +
  scale_shape_manual(values = c(cohort = 15, retracted = 1, pooled = 18)) +
  scale_colour_manual(values = c(
    cohort = figure_style$neutral[["dark"]],
    retracted = figure_style$neutral[["muted_text"]],
    pooled = figure_style$cohort[["Pooled"]]
  )) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.2))) +
  labs(x = "NCR minus CR, general proliferation score (SD units)", y = NULL) +
  formal_figure_theme(figure_spec) + s5_open_axes + theme(legend.position = "none")
# Numeric companion column (audited Figure 3 / S1A / S2 / S3 pattern);
# cohort sizes are already carried by the y-axis labels.
header_y <- nlevels(fdat$label) + 0.85
p_cols <- ggplot(fdat, aes(y = label)) +
  geom_text(aes(x = 0, label = txt), hjust = 0, size = figure_text, family = figure_spec$font_family) +
  annotate("text", x = 0, y = header_y, label = "Estimate (95% CI)", hjust = 0,
    fontface = "bold", size = figure_text, family = figure_spec$font_family) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.2))) +
  scale_x_continuous(limits = c(0, 34), expand = expansion(mult = c(0, 0))) +
  coord_cartesian(clip = "off") + formal_figure_theme(figure_spec, base = "void") +
  theme(plot.margin = margin(2, 2, 2, 1, unit = "mm"))
p <- (p_forest | p_cols) + plot_layout(widths = grid::unit(c(1, 36), c("null", "mm")))
save_formal_figure(p, file.path(out_fig, "forest_general_proliferation"), height_mm = 85, spec = figure_spec)

p_g4 <- ggplot(g4, aes(response4, general_proliferation, fill = response4)) +
  geom_boxplot(outlier.shape = NA, alpha = 0.35) +
  geom_jitter(width = 0.15, size = 1.4, alpha = 0.7) +
  scale_fill_manual(values = figure_style$response[c("CR", "PR", "SD", "PD")]) +
  labs(x = "First-line response (GSE63885, serous)", y = "General proliferation score (SD)") +
  theme_bw(11) + theme(legend.position = "none")
ggsave(file.path(out_fig, "GSE63885_proliferation_by_response4.png"), p_g4, width = 5, height = 4, dpi = 300)

km_plots <- lapply(names(km_data), function(nm) {
  d <- km_data[[nm]] %>% mutate(group = if (all(!is.na(response4))) factor(response4, levels = analysis_config$response$four_levels)
    else factor(ifelse(noncr == 1, "NCR", "CR"), levels = c("CR", "NCR")))
  sf <- survfit(Surv(time, os_event) ~ group, d)
  td <- tibble(time = sf$time, surv = sf$surv,
    group = rep(sub("group=", "", names(sf$strata)), sf$strata))
  td <- bind_rows(td, tibble(time = 0, surv = 1, group = unique(td$group)))
  group_levels <- levels(d$group)
  group_colours <- figure_style$response[group_levels]
  group_lines <- figure_style$response_linetype[group_levels]
  ggplot(td, aes(time, surv, colour = group, linetype = group)) + geom_step() +
    scale_colour_manual(values = group_colours) + scale_linetype_manual(values = group_lines) +
    labs(title = lab_cohort(nm), x = sprintf("Months after %d-day landmark", landmark_days), y = "OS", colour = NULL, linetype = NULL) +
    coord_cartesian(xlim = c(0, 120)) + theme_bw(9) + theme(legend.position = "bottom")
})
p_km <- wrap_plots(km_plots, ncol = 3)
ggsave(file.path(out_fig, "landmark_os_by_response.png"), p_km, width = 11, height = 7, dpi = 300)
ggsave(file.path(out_fig, "landmark_os_by_response.pdf"), p_km, width = 11, height = 7)

# ------------------------------------------------------------------ summary
prim <- meta_tab %>% filter(analysis == "primary_external", score == "general_proliferation")
sink(file.path(project_dir, "logs/phase4_external_validation_run_summary.txt"))
cat("Phase 4 external validation completed:", format(Sys.time()), "\n")
print(as.data.frame(cohort_audit))
cat("\nPrimary (general_proliferation, primary_external REML):\n"); print(as.data.frame(prim))
cat("\nTCGA vs external compatibility:\n"); print(as.data.frame(compat))
cat("\nOS Cox:\n"); print(as.data.frame(cox_tab))
cat("\nOS plateau tests:\n"); print(as.data.frame(topo_tab))
cat("\nOS meta:\n"); print(as.data.frame(surv_meta)); print(as.data.frame(surv_meta_loo))
cat("\nPost hoc PD-step models:\n"); print(as.data.frame(step_tab)); print(as.data.frame(pd_tab)); print(as.data.frame(pd_meta))
cat("\nGSE63885 four-class:\n"); print(as.data.frame(g4_summary)); print(as.data.frame(g4_tests))
cat("\nTCGA RNA-seq vs array:\n"); print(as.data.frame(rnaseq_corr)); print(as.data.frame(rs_est))
sink()
cat(readLines(file.path(project_dir, "logs/phase4_external_validation_run_summary.txt")), sep = "\n")
