# ==============================================================================
# File: 00_project_configuration.R
# Purpose: Load reproducible analysis settings and resolve all project paths.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - config/analysis.yml: version-controlled scientific analysis parameters.
#   - config/paths.example.yml: versioned portable path defaults.
#   - config/paths.yml or CRNCR_PATHS_CONFIG: optional local path overrides.
#   - config/submission_profile.json: locked artwork settings and semantic style.
#   - Optional environment variables documented in config/paths.example.yml.
# Outputs:
#   - A validated configuration list returned by load_project_configuration().
# Runtime parameters:
#   - Each scientific setting is read from versioned configuration; local paths
#     are resolved from the repository root, never from the caller's directory.
# Notes:
#   - Local machine paths are never embedded in analysis scripts.
#   - Statistical resampling uses observed data and is not mock-data generation.
# ==============================================================================

# Keep warnings and diagnostic messages in English across local environments.
Sys.setenv(LANGUAGE = "en")
suppressWarnings(try(Sys.setlocale("LC_MESSAGES", "C"), silent = TRUE))

# Configure deterministic random-number generation and bounded runtime threads.
configure_reproducible_runtime <- function(seed, threads = 1L) {
  threads <- as.integer(threads)
  if (length(threads) != 1L || is.na(threads) || threads < 1L) {
    stop("'threads' must be a single positive integer.")
  }

  thread_value <- as.character(threads)
  do.call(
    Sys.setenv,
    as.list(c(
      TZ = "UTC",
      LANGUAGE = "en",
      OMP_NUM_THREADS = thread_value,
      OPENBLAS_NUM_THREADS = thread_value,
      MKL_NUM_THREADS = thread_value,
      VECLIB_MAXIMUM_THREADS = thread_value,
      NUMEXPR_NUM_THREADS = thread_value
    ))
  )
  suppressWarnings(try(Sys.setlocale("LC_MESSAGES", "C"), silent = TRUE))
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(seed)
  invisible(seed)
}

# Load the shared semantic palette from the versioned submission profile.
# Input: repository root. Output: named atomic vectors, preserving the historic
# group order and numeric marker types used by the approved formal figures.
# Colours stay stable within each semantic domain; the ordered power ramp must
# not reuse the categorical CR/PR response hues. Missing groups fail explicitly.
get_figure_style <- function(project_root = get_project_root()) {
  profile_file <- file.path(project_root, "config", "submission_profile.json")
  if (!file.exists(profile_file)) stop("Missing submission profile: ", profile_file)
  groups <- jsonlite::read_json(profile_file)$figure_style
  required <- c(
    "response", "response_linetype", "model", "analysis", "analysis_shape",
    "cohort", "cohort_shape", "subset", "power", "neutral"
  )
  if (!is.list(groups) || !all(required %in% names(groups))) {
    stop("Missing required figure_style groups in submission profile.")
  }
  result <- lapply(groups, function(values) {
    if (!is.list(values) || !length(values) || is.null(names(values)) ||
        any(!nzchar(names(values)))) stop("Figure style groups must be nonempty named mappings.")
    unlist(values, use.names = TRUE)
  })
  for (group in c("analysis_shape", "cohort_shape")) {
    values <- result[[group]]
    if (!is.numeric(values) || anyNA(values) || any(values != floor(values))) {
      stop("Figure marker shapes must be integer-valued: ", group)
    }
    result[[group]] <- as.double(values)
    names(result[[group]]) <- names(values)
  }
  result
}

# Load the journal artwork specification shared by R figures and the Python
# typography audit. Formal figures are drawn at final double-column size so
# that no downstream scaling changes the printed text size.
load_figure_specification <- function(project_root) {
  profile_file <- file.path(project_root, "config", "submission_profile.json")
  if (!file.exists(profile_file)) stop("Missing submission profile: ", profile_file)
  spec <- jsonlite::read_json(profile_file)$figure_specification
  required <- c(
    "width_mm", "max_height_mm", "min_font_pt", "tag_font_pt",
    "raster_dpi", "font_family"
  )
  missing <- setdiff(required, names(spec))
  if (length(missing)) stop("Missing figure specification field(s): ", paste(missing, collapse = ", "))
  spec
}

# Harrell concordance counts within one validation fold. Scores from different
# fitted models must never be compared across folds. Time ties are handled by
# survival::concordance; score ties contribute one half to concordance.
cv_fold_concordance <- function(time, event, marker) {
  if (!length(time) || length(time) != length(event) || length(time) != length(marker)) {
    stop("Validation time, event and score vectors must have equal nonzero lengths.")
  }
  if (any(!is.finite(time)) || any(!is.finite(marker)) ||
      anyNA(event) || any(!event %in% c(0, 1))) {
    stop("Validation folds require finite times/scores and binary nonmissing events.")
  }
  fit <- survival::concordance(
    survival::Surv(time, event) ~ marker, reverse = TRUE,
    timewt = "n", timefix = TRUE
  )
  counts <- fit$count[c("concordant", "discordant", "tied.x")]
  pairs <- sum(counts)
  if (!is.finite(pairs) || pairs <= 0) {
    stop("A validation fold has no comparable pairs; do not silently discard it.")
  }
  data.frame(
    validation_n = length(time), validation_events = sum(event),
    concordant = unname(counts[[1]]), discordant = unname(counts[[2]]),
    tied_score = unname(counts[[3]]), comparable_pairs = pairs,
    C_index = unname((counts[[1]] + counts[[3]] / 2) / pairs)
  )
}

# Aggregate exactly one repeat/model by counts, not an unweighted mean of fold C.
# The caller uses identical, disjoint validation folds for all paired models.
cv_repeat_concordance <- function(fold_counts, expected_n, expected_folds) {
  required <- c("fold_id", "validation_n", "concordant", "discordant",
                "tied_score", "comparable_pairs")
  if (!all(required %in% names(fold_counts))) stop("Missing fold-concordance fields.")
  if (nrow(fold_counts) != expected_folds || anyDuplicated(fold_counts$fold_id) ||
      !setequal(fold_counts$fold_id, seq_len(expected_folds)) ||
      sum(fold_counts$validation_n) != expected_n) {
    stop("Validation folds must partition the full CV cohort exactly once.")
  }
  values <- as.matrix(fold_counts[c("concordant", "discordant", "tied_score", "comparable_pairs")])
  if (any(!is.finite(values)) || any(values < 0) || any(fold_counts$comparable_pairs <= 0) ||
      any(abs(rowSums(values[, 1:3, drop = FALSE]) - values[, 4]) > 1e-8)) {
    stop("Invalid validation-fold concordance counts.")
  }
  totals <- colSums(values)
  data.frame(
    C_index = unname((totals[[1]] + totals[[3]] / 2) / totals[[4]]),
    comparable_pairs = unname(totals[[4]]), folds = expected_folds,
    concordant = unname(totals[[1]]), discordant = unname(totals[[2]]),
    tied_score = unname(totals[[3]]),
    c_index_method = "within_fold_pair_weighted_harrell"
  )
}

# Reusable regression checks. These small artificial vectors are test fixtures,
# never mock patient observations or inputs to the scientific analysis.
validate_cv_concordance_invariants <- function() {
  time <- c(1, 2, 3, 4); event <- c(1, 1, 1, 0); marker <- c(4, 3, 2, 1)
  perfect <- cv_fold_concordance(time, event, marker)
  stopifnot(perfect$C_index == 1, perfect$comparable_pairs == 6,
            cv_fold_concordance(time, event, -marker)$C_index == 0,
            cv_fold_concordance(time, event, rep(1, 4))$C_index == 0.5,
            identical(perfect, cv_fold_concordance(time, event, marker + 100)))
  time <- c(1, 2, 4, 5, 8); event <- c(0, 1, 0, 1, 1); marker <- c(2, 4, 1, 2, 2)
  concordant <- discordant <- tied <- 0
  for (i in seq_along(time)) for (j in seq_along(time)) {
    if (time[i] < time[j] && event[i] == 1) {
      if (marker[i] > marker[j]) concordant <- concordant + 1
      else if (marker[i] < marker[j]) discordant <- discordant + 1
      else tied <- tied + 1
    }
  }
  first <- cv_fold_concordance(time, event, marker)
  stopifnot(first$concordant == concordant, first$discordant == discordant, first$tied_score == tied)
  second <- cv_fold_concordance(1:3, c(1, 1, 0), c(1, 2, 3))
  counts <- rbind(transform(first, fold_id = 1), transform(second, fold_id = 2))
  result <- cv_repeat_concordance(counts, 8, 2)
  expected <- (first$concordant + second$concordant + (first$tied_score + second$tied_score) / 2) /
    (first$comparable_pairs + second$comparable_pairs)
  stopifnot(result$C_index == expected,
            inherits(try(cv_repeat_concordance(counts, 9, 2), silent = TRUE), "try-error"),
            inherits(try(cv_repeat_concordance(transform(counts, fold_id = 1), 8, 2), silent = TRUE), "try-error"),
            inherits(try(cv_fold_concordance(1:3, c(0, 0, 0), 1:3), silent = TRUE), "try-error"),
            inherits(try(cv_fold_concordance(1:3, c(1, 1, 0), c(1, NA, 3)), silent = TRUE), "try-error"),
            inherits(try(cv_fold_concordance(1:3, c(1, 2, 0), 1:3), silent = TRUE), "try-error"))
  message("CV concordance regression checks passed.")
  invisible(TRUE)
}

# Convert a font size in points to the millimetre size used by geom_text().
figure_text_size <- function(spec, pt = spec$min_font_pt) {
  if (pt < spec$min_font_pt) stop("Requested text size is below the configured minimum.")
  pt / ggplot2::.pt
}

# Return a theme in which every text element is set explicitly in points, so
# no relative default (for example axis or strip text) falls below the minimum.
formal_figure_theme <- function(spec, base = c("bw", "classic", "void")) {
  base <- match.arg(base)
  p <- spec$min_font_pt
  base_theme <- switch(
    base,
    bw = ggplot2::theme_bw(base_size = p, base_family = spec$font_family),
    classic = ggplot2::theme_classic(base_size = p, base_family = spec$font_family),
    void = ggplot2::theme_void(base_size = p, base_family = spec$font_family)
  )
  text_theme <- ggplot2::theme(
    text = ggplot2::element_text(size = p, family = spec$font_family),
    legend.text = ggplot2::element_text(size = p),
    legend.title = ggplot2::element_text(size = p),
    strip.text = ggplot2::element_text(size = p),
    plot.title = ggplot2::element_text(size = p, face = "bold"),
    plot.subtitle = ggplot2::element_text(size = p),
    plot.caption = ggplot2::element_text(size = p),
    plot.tag = ggplot2::element_text(size = spec$tag_font_pt, face = "bold"),
    plot.tag.location = "plot",
    panel.grid.minor = ggplot2::element_blank()
  )
  # Diagram figures keep blank axes; plotting themes set axis text explicitly.
  if (base == "void") return(base_theme + text_theme)
  base_theme + text_theme + ggplot2::theme(
    axis.text = ggplot2::element_text(size = p, colour = "black"),
    axis.title = ggplot2::element_text(size = p)
  )
}

# Save a formal figure as a 600-dpi PNG and a vector PDF at final size. A
# narrower native width may be requested for single-panel artwork; the final
# figure is never scaled down after rendering.
save_formal_figure <- function(plot, path_stem, height_mm, spec,
                               width_mm = spec$width_mm) {
  if (!is.numeric(width_mm) || length(width_mm) != 1L || !is.finite(width_mm) || width_mm <= 0) {
    stop("Figure width must be one positive number.")
  }
  if (width_mm > spec$width_mm) stop("Figure width exceeds the configured page maximum.")
  if (height_mm > spec$max_height_mm) stop("Figure height exceeds the configured page maximum.")
  ggplot2::ggsave(
    paste0(path_stem, ".png"), plot,
    device = ragg::agg_png, width = width_mm, height = height_mm,
    units = "mm", dpi = spec$raster_dpi, bg = "white"
  )
  ggplot2::ggsave(
    paste0(path_stem, ".pdf"), plot,
    device = grDevices::cairo_pdf, width = width_mm, height = height_mm,
    units = "mm", family = spec$font_family, bg = "white"
  )
  invisible(paste0(path_stem, c(".png", ".pdf")))
}

# Return the absolute path of the Rscript currently being executed.
get_executed_script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) != 1L) {
    stop("Run analysis scripts with Rscript so the project root can be resolved.")
  }
  normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
}

# Resolve the repository root from a script stored in the scripts directory.
get_project_root <- function(script_path = get_executed_script_path()) {
  normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
}

# Convert a configured path to an absolute path without requiring it to exist.
resolve_project_path <- function(path_value, project_root) {
  if (is.null(path_value) || length(path_value) == 0L || is.na(path_value) || !nzchar(path_value)) {
    return(NA_character_)
  }
  expanded <- path.expand(path_value)
  if (!grepl("^/", expanded)) expanded <- file.path(project_root, expanded)
  normalizePath(expanded, mustWork = FALSE)
}

# Prefer a private environment variable over the non-sensitive paths file.
resolve_local_path <- function(paths, key, environment_variable, project_root) {
  env_value <- Sys.getenv(environment_variable, unset = "")
  configured_value <- paths[[key]]
  value <- if (nzchar(env_value)) env_value else configured_value
  resolve_project_path(value, project_root)
}

# Return a required nested analysis value or stop with its full configuration path.
required_analysis_value <- function(analysis, path) {
  keys <- strsplit(path, ".", fixed = TRUE)[[1]]
  value <- analysis
  for (key in keys) {
    if (!is.list(value) || is.null(value[[key]])) {
      stop("Missing required analysis configuration field: ", path)
    }
    value <- value[[key]]
  }
  value
}

# Validate scientific configuration types and ranges before any analysis starts.
validate_analysis_configuration <- function(analysis) {
  required_groups <- c(
    "project", "random_seeds", "response", "survival", "landmark",
    "resampling", "cohort", "selection", "expression", "molecular",
    "wgcna", "integration", "multiomics", "external_validation",
    "pancancer", "power", "api", "hrr", "reporting"
  )
  for (group in required_groups) {
    value <- required_analysis_value(analysis, group)
    if (!is.list(value) || is.null(names(value))) {
      stop("Analysis configuration group must be a named mapping: ", group)
    }
  }

  assert_character <- function(path, length_required = 1L) {
    value <- required_analysis_value(analysis, path)
    if (!is.character(value) || length(value) != length_required || anyNA(value) || any(!nzchar(value))) {
      stop("Analysis configuration field must be a non-empty character vector of length ",
           length_required, ": ", path)
    }
    invisible(value)
  }
  assert_nonempty_unique_character <- function(path) {
    value <- required_analysis_value(analysis, path)
    if (!is.character(value) || length(value) < 1L || anyNA(value) ||
        any(!nzchar(value)) || anyDuplicated(value)) {
      stop("Analysis configuration field must be a non-empty character vector without duplicates: ", path)
    }
    invisible(value)
  }
  assert_numeric <- function(path, length_required = 1L) {
    value <- required_analysis_value(analysis, path)
    if (!is.numeric(value) || length(value) != length_required || anyNA(value) || any(!is.finite(value))) {
      stop("Analysis configuration field must be a finite numeric vector of length ",
           length_required, ": ", path)
    }
    invisible(value)
  }
  assert_integer <- function(path, length_required = 1L, positive = TRUE) {
    assert_numeric(path, length_required)
    value <- required_analysis_value(analysis, path)
    if (any(value != floor(value)) || (positive && any(value <= 0))) {
      qualifier <- if (positive) "positive integer" else "integer"
      stop("Analysis configuration field must contain ", qualifier, " value(s): ", path)
    }
    invisible(value)
  }
  assert_fraction <- function(path, length_required = 1L, strict = FALSE) {
    assert_numeric(path, length_required)
    value <- required_analysis_value(analysis, path)
    invalid <- if (strict) value <= 0 | value >= 1 else value < 0 | value > 1
    if (any(invalid)) {
      bounds <- if (strict) "strictly between 0 and 1" else "between 0 and 1"
      stop("Analysis configuration field must be ", bounds, ": ", path)
    }
    invisible(value)
  }

  assert_character("project.name")
  assert_character("project.created")
  random_seed_fields <- c(
    "default", "external_validation", "pancancer_topology", "therapy_end_landmark",
    "hgsoc_sensitivity", "selection_power", "manuscript_outputs"
  )
  for (field in random_seed_fields) assert_integer(paste0("random_seeds.", field))

  expected_levels <- list(
    "response.four_levels" = c("CR", "PR", "SD", "PD"),
    "response.objective_response_levels" = c("CR+PR", "SD+PD"),
    "response.cr_threshold_levels" = c("CR", "Non-CR")
  )
  for (path in names(expected_levels)) {
    expected <- expected_levels[[path]]
    assert_character(path, length(expected))
    if (!identical(required_analysis_value(analysis, path), expected)) {
      stop("Analysis configuration response-level order is invalid: ", path)
    }
  }
  for (path in c("response.equivalence_margin", "response.relaxed_equivalence_margin")) {
    assert_numeric(path, 2L)
    margin <- required_analysis_value(analysis, path)
    if (margin[1] <= 0 || margin[1] >= 1 || margin[2] <= 1 || margin[1] >= margin[2]) {
      stop("Equivalence margin must have ordered lower and upper bounds around 1: ", path)
    }
  }

  for (path in c(
    "survival.days_per_month", "survival.external_validation_days_per_month",
    "expression.correlation_outlier_mad_multiplier", "molecular.gene_effect_size_threshold",
    "molecular.pathway_effect_size_threshold", "external_validation.log2_trigger_maximum"
  )) {
    assert_numeric(path)
    if (required_analysis_value(analysis, path) <= 0) {
      stop("Analysis configuration field must be positive: ", path)
    }
  }
  for (path in c(
    "survival.alpha", "survival.confidence_level", "selection.ipw_truncation_quantiles",
    "expression.lower_variance_fraction", "expression.pca_outlier_probability",
    "molecular.fdr_threshold", "molecular.constraint_nonrejection_threshold",
    "molecular.robustness_fraction", "wgcna.merge_cut_height", "wgcna.max_p_outliers",
    "wgcna.minimum_scale_free_r2", "wgcna.hub_fraction",
    "wgcna.fallback_connectivity_penalty_weight", "wgcna.fallback_slope_penalty_weight",
    "wgcna.fallback_near_best_tolerance", "wgcna.stability_median_spearman_threshold",
    "wgcna.stability_q05_spearman_threshold",
    "wgcna.microenvironment_correlation_threshold", "multiomics.fdr_threshold",
    "external_validation.duplicate_correlation_threshold",
    "external_validation.minimum_gene_coverage_fraction",
    "pancancer.minimum_treatment_fraction", "power.target_power",
    "power.pd_fractions", "power.future_pd_fractions", "power.alternative_noncr_share"
  )) {
    value <- required_analysis_value(analysis, path)
    assert_fraction(path, length(value))
  }
  assert_fraction("selection.ipw_truncation_quantiles", 2L, strict = TRUE)
  if (!is.unsorted(analysis$selection$ipw_truncation_quantiles, strictly = TRUE)) {
    invisible(NULL)
  } else {
    stop("selection.ipw_truncation_quantiles must be strictly increasing.")
  }

  resampling_fields <- c(
    "bootstrap_replicates", "restricted_bootstrap_replicates",
    "power_simulation_replicates", "date_imputation_replicates",
    "cross_validation_folds", "cross_validation_repeats",
    "phase0_cross_validation_folds", "phase0_cross_validation_repeats",
    "phase0_multiple_imputations", "multiple_imputation_max_iterations",
    "wgcna_split_half_repeats", "multiple_imputations", "monte_carlo_test_replicates"
  )
  integer_scalars <- c(
    "survival.time_dependent_auc_months", "landmark.median_imputation_days",
    "landmark.plus_days_sensitivity", paste0("resampling.", resampling_fields),
    "cohort.maximum_start_day", "cohort.regimen_join_window_days",
    "cohort.minimum_tss_samples", "cohort.minimum_topology_per_state",
    "expression.center_minimum_samples", "expression.minimum_gene_set_size",
    "expression.maximum_gene_set_size", "expression.pathway_minimum_gene_set_size",
    "expression.pca_gene_count", "expression.pca_component_count",
    "expression.pca_outlier_component_count", "expression.minimum_association_samples",
    "wgcna.main_gene_count", "wgcna.minimum_selected_genes", "wgcna.minimum_module_size",
    "wgcna.deep_split", "wgcna.minimum_mean_connectivity", "wgcna.maximum_threads",
    "wgcna.minimum_hub_count", "wgcna.minimum_trait_samples",
    "wgcna.minimum_replication_count",
    "integration.minimum_overlap_genes", "multiomics.minimum_samples",
    "multiomics.minimum_binary_group", "multiomics.minimum_distinct_values",
    "external_validation.minimum_shared_genes", "external_validation.minimum_analysis_samples",
    "external_validation.minimum_survival_events", "external_validation.landmark_days",
    "pancancer.minimum_per_noncr_state", "pancancer.minimum_noncr", "pancancer.minimum_cr",
    "pancancer.minimum_os_events", "pancancer.minimum_model_events",
    "api.gdc_page_size", "api.timeout_seconds", "api.maximum_attempts",
    "api.retry_backoff_seconds", "api.minimum_cache_bytes", "api.minimum_expected_patients"
  )
  for (path in integer_scalars) assert_integer(path)

  positive_integer_vectors <- c(
    "survival.rmst_horizons_months", "survival.sensitivity_rmst_horizons_months",
    "landmark.plausible_end_days", "landmark.fixed_days", "landmark.tipping_days",
    "cohort.standard_duration_days", "wgcna.sensitivity_gene_counts", "wgcna.power_candidates"
  )
  for (path in positive_integer_vectors) {
    value <- required_analysis_value(analysis, path)
    assert_integer(path, length(value))
  }
  assert_integer("cohort.first_line_start_window_days", 2L, positive = FALSE)
  assert_integer("multiomics.gistic_amplification_threshold")
  assert_integer("multiomics.gistic_deletion_threshold", positive = FALSE)
  assert_numeric("expression.minimum_gene_sd")
  if (analysis$expression$minimum_gene_sd < 0) stop("expression.minimum_gene_sd must be non-negative.")
  for (path in c("power.pd_step_hazard_ratios", "power.future_hazard_ratios")) {
    value <- required_analysis_value(analysis, path)
    assert_numeric(path, length(value))
    if (any(value <= 0)) stop("Analysis configuration vector must be positive: ", path)
  }
  for (path in c("cohort.hgsoc_grades", "cohort.advanced_stages")) {
    value <- required_analysis_value(analysis, path)
    assert_character(path, length(value))
  }
  for (path in c(
    "cohort.high_grade_levels", "cohort.platinum_agents", "cohort.taxane_agents"
  )) {
    assert_nonempty_unique_character(path)
  }
  high_grade_numbers <- suppressWarnings(as.integer(sub("^G", "", analysis$cohort$high_grade_levels)))
  if (anyNA(high_grade_numbers) || any(!grepl("^G[0-9]+$", analysis$cohort$high_grade_levels)) ||
      is.unsorted(high_grade_numbers, strictly = TRUE)) {
    stop("cohort.high_grade_levels must be ordered increasing grade labels such as G3, G4.")
  }
  sensitivity_rmst <- analysis$survival$sensitivity_rmst_horizons_months
  if (length(sensitivity_rmst) < 1L || is.unsorted(sensitivity_rmst, strictly = TRUE)) {
    stop("survival.sensitivity_rmst_horizons_months must be a non-empty strictly increasing vector.")
  }
  if (analysis$wgcna$stability_q05_spearman_threshold >
      analysis$wgcna$stability_median_spearman_threshold) {
    stop("wgcna.stability_q05_spearman_threshold cannot exceed the median threshold.")
  }
  for (source_key in c(
    "api.gdc_cases_url", "api.gdc_files_url", "api.geo_ftp_base_url",
    "api.cbioportal_api_base_url", "api.cbioportal_datahub_media_base_url",
    "api.cbioportal_datahub_raw_base_url", "api.cbioportal_datahub_commit",
    "api.cbioportal_study_id", "api.cbioportal_mutation_profile_id"
  )) {
    assert_character(source_key)
  }
  # URLs must be HTTPS without a trailing slash because scripts append paths.
  url_keys <- c("gdc_cases_url", "gdc_files_url", "geo_ftp_base_url", "cbioportal_api_base_url",
                "cbioportal_datahub_media_base_url", "cbioportal_datahub_raw_base_url")
  bad_urls <- url_keys[!grepl("^https://[^ ]+[^/]$", unlist(analysis$api[url_keys]))]
  if (length(bad_urls)) {
    stop("api URLs must use https:// and omit a trailing slash: ", paste(bad_urls, collapse = ", "))
  }
  # A full 40-character commit hash pins the cBioPortal datahub snapshot.
  if (!grepl("^[0-9a-f]{40}$", analysis$api$cbioportal_datahub_commit)) {
    stop("api.cbioportal_datahub_commit must be a full 40-character Git commit hash.")
  }

  plausible <- analysis$landmark$plausible_end_days
  if (length(plausible) != 2L || plausible[1] >= plausible[2]) {
    stop("landmark.plausible_end_days must contain increasing lower and upper bounds.")
  }
  landmark_values <- c(
    analysis$landmark$fixed_days, analysis$landmark$median_imputation_days,
    analysis$landmark$tipping_days, analysis$external_validation$landmark_days
  )
  if (any(landmark_values < plausible[1] | landmark_values > plausible[2])) {
    stop("Configured landmark days must fall within landmark.plausible_end_days.")
  }
  if (analysis$expression$minimum_gene_set_size > analysis$expression$maximum_gene_set_size ||
      analysis$expression$pathway_minimum_gene_set_size > analysis$expression$maximum_gene_set_size) {
    stop("Expression gene-set size bounds are inconsistent.")
  }
  if (analysis$expression$pca_outlier_component_count > analysis$expression$pca_component_count) {
    stop("expression.pca_outlier_component_count cannot exceed pca_component_count.")
  }

  # Newly externalized definitions must not silently become NULL or change
  # scalar/vector types when a configuration entry is missing or malformed.
  for (path in c("survival.wald_z_95", "power.censoring_multiplier")) {
    assert_numeric(path)
    if (required_analysis_value(analysis, path) <= 0) stop("Configuration must be positive: ", path)
  }
  assert_integer("resampling.landmark_mi_max_iterations")
  assert_fraction("reporting.split_quantiles", 2L, strict = TRUE)
  if (is.unsorted(analysis$reporting$split_quantiles, strictly = TRUE)) {
    stop("reporting.split_quantiles must be strictly increasing.")
  }
  for (path in c(
    "expression.pca_association_component_count", "molecular.maximum_surrogate_variables",
    "molecular.concordance_gene_count", "hrr.minimum_sequenced_samples",
    "wgcna.expected_response_known_samples", "wgcna.expected_network_samples",
    "multiomics.minimum_axis_genes", "multiomics.expected_robust_pathway_count",
    "pancancer.minimum_regimen_agreement_samples", "api.gdc_manifest_page_size"
  )) assert_integer(path)
  assert_fraction("molecular.constraint_alpha", strict = TRUE)
  for (path in c(
    "cohort.phase0_sensitivity_grades", "cohort.treatment_type_groups.systemic",
    "cohort.treatment_type_groups.radiation", "hrr.panels.brca", "hrr.panels.core",
    "hrr.panels.extended", "hrr.variant_classes.protein_altering",
    "hrr.variant_classes.likely_lof", "multiomics.cnv_genes", "multiomics.rppa_features"
  )) assert_nonempty_unique_character(path)
  for (path in c(
    "expression.msigdb_species", "expression.msigdb_hallmark_collection",
    "expression.msigdb_reactome_collection", "expression.msigdb_reactome_subcollection",
    "expression.msigdb_gobp_collection", "expression.msigdb_gobp_subcollection",
    "multiomics.proliferation_marker_gene", "multiomics.methylation_gene",
    "api.gdc_program", "api.gdc_mutation_project_id"
  )) assert_character(path)
  for (path in c("multiomics.axis_pathways", "multiomics.source_files",
                 "molecular.hallmark_hypothesis_axes", "external_validation.geo_platforms")) {
    mapping <- required_analysis_value(analysis, path)
    if (!is.list(mapping) || !length(mapping) || is.null(names(mapping))) {
      stop("Configuration must be a nonempty named mapping: ", path)
    }
    for (key in names(mapping)) {
      values <- unlist(mapping[[key]], use.names = FALSE)
      if (!is.character(values) || !length(values) || anyNA(values) || any(!nzchar(values))) {
        stop("Configuration mapping must contain nonempty strings: ", path, ".", key)
      }
    }
  }
  interactions <- required_analysis_value(analysis, "multiomics.interaction_specs")
  if (!is.list(interactions) || !length(interactions)) {
    stop("multiomics.interaction_specs must be a nonempty ordered list.")
  }
  for (row in interactions) {
    if (!is.list(row) || !all(c("score", "modifier") %in% names(row)) ||
        any(!vapply(row[c("score", "modifier")], function(value) {
          is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
        }, logical(1)))) stop("Each interaction requires one score and modifier string.")
  }

  invisible(analysis)
}

# Load and validate the complete project configuration.
load_project_configuration <- function(project_root = get_project_root()) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("The 'yaml' package is required. Install dependencies listed in DESCRIPTION.")
  }

  analysis_file <- file.path(project_root, "config", "analysis.yml")
  if (!file.exists(analysis_file)) stop("Missing analysis configuration: ", analysis_file)
  analysis <- yaml::read_yaml(analysis_file)
  validate_analysis_configuration(analysis)

  # Versioned path defaults are data, not silent literals in analysis code.
  # An explicitly selected private file must exist; an absent optional local
  # override is legitimate in a clean GitHub checkout.
  template_file <- file.path(project_root, "config", "paths.example.yml")
  if (!file.exists(template_file)) stop("Missing portable path template: ", template_file)
  paths <- yaml::read_yaml(template_file)
  private_override <- Sys.getenv("CRNCR_PATHS_CONFIG", unset = "")
  private_file <- if (nzchar(private_override)) {
    resolve_project_path(private_override, project_root)
  } else {
    file.path(project_root, "config", "paths.yml")
  }
  if (nzchar(private_override) && !file.exists(private_file)) {
    stop("Explicit private paths configuration does not exist: ", private_file)
  }
  if (file.exists(private_file)) {
    overrides <- yaml::read_yaml(private_file)
    if (!is.list(overrides) || is.null(names(overrides))) {
      stop("Private paths configuration must be a named mapping.")
    }
    unknown <- setdiff(names(overrides), names(paths))
    if (length(unknown)) stop("Unknown private path field(s): ", paste(unknown, collapse = ", "))
    for (key in names(overrides)) paths[[key]] <- overrides[[key]]
  }

  resolved_paths <- list(
    xena_dir = resolve_local_path(paths, "xena_dir", "TCGA_XENA_DIR", project_root),
    external_data_dir = resolve_local_path(
      paths, "external_data_dir", "CRNCR_EXTERNAL_DATA_DIR", project_root
    ),
    processed_data_dir = resolve_local_path(
      paths, "processed_data_dir", "CRNCR_PROCESSED_DATA_DIR", project_root
    ),
    results_dir = resolve_local_path(paths, "results_dir", "CRNCR_RESULTS_DIR", project_root)
  )

  # Only the optional large Xena source may be unconfigured. Working caches,
  # included derivatives and results must have explicit versioned locations.
  required_paths <- c("external_data_dir", "processed_data_dir", "results_dir")
  missing_paths <- required_paths[vapply(resolved_paths[required_paths], is.na, logical(1))]
  if (length(missing_paths)) stop("Missing configured path(s): ", paste(missing_paths, collapse = ", "))

  list(root = project_root, analysis = analysis, paths = resolved_paths)
}

# Fail early with an actionable message when a required source is unavailable.
require_input_files <- function(paths, source_label = "input") {
  paths <- unname(unlist(paths))
  missing <- paths[is.na(paths) | !file.exists(paths)]
  if (length(missing)) {
    stop("Missing required ", source_label, " file(s): ", paste(missing, collapse = ", "))
  }
  invisible(paths)
}

# Apply the exact shared first-line doublet definition used by stages 18 and 20.
# Inputs: one observed semicolon-delimited agent string and configured platinum/
# taxane vectors. Output: one logical flag. NA is FALSE; tokens are deliberately
# not trimmed or deduplicated, and any additional agent excludes the doublet.
is_platinum_taxane_doublet <- function(agents, platinum_agents, taxane_agents) {
  if (is.na(agents)) return(FALSE)
  tokens <- stringr::str_split(agents, ";")[[1]]
  all(tokens %in% c(platinum_agents, taxane_agents)) &&
    any(tokens %in% platinum_agents) && any(tokens %in% taxane_agents)
}

# Create a repository-relative output directory and return its absolute path.
ensure_output_directory <- function(project_root, ...) {
  path <- file.path(project_root, ...)
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}
