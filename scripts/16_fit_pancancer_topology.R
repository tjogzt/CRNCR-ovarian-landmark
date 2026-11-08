#!/usr/bin/env Rscript

# ==============================================================================
# File: 16_fit_pancancer_topology.R
# Purpose: Estimate response topology in eligible non-ovarian TCGA tumour types.
# Author: Project authors
# Created: 2026-10-15
# Inputs:
#   - Script 15's patient-level pan-cancer response/treatment file, including OS,
#     PFI, therapy-end dates, stage, grade and residual-disease indicators.
# Runtime parameters:
#   - config/analysis.yml: random_seeds.pancancer_topology; landmark.fixed_days[1];
#     resampling.restricted_bootstrap_replicates; survival.days_per_month and
#     survival.alpha; pancancer.minimum_model_events, minimum_noncr,
#     minimum_os_events and minimum_cr.
#   - load_project_configuration(project_dir) resolves processed_data_dir and
#     results_dir from private config/paths.yml or environment overrides.
#   - Shared figure style and config/submission_profile.json supply artwork settings.
#   - Cohort/covariate definitions and nested-model degrees of freedom remain
#     explicit below. The 120-month KM window is display_only, not censoring.
# Outputs:
#   - Cancer-specific topology models, meta-analysis tables, and figures.
# Reproducibility:
#   - A single configured seed drives observed-patient bootstrap draws; four-state
#     incomplete draws are omitted. Models and REML meta-analyses are deterministic.
#   - Cox associations condition on labelled, observed survivors at each origin;
#     they do not identify a causal treatment effect.
# ==============================================================================

# Pan-cancer step 2: response topology in cancers passing the pre-specified
# eligibility rules (script 15). Same model set as the ovarian analysis.
#
# Analysis sets
#   Primary topology: OV (reference), LGG (all labelled; E1 & E2), LGG treated.
#   Secondary topology: BLCA treated subset (passes E1 only after restricting
#     to patients with first-line systemic/radiation therapy).
#   Descriptive dichotomy: CR vs NCR OS HR in cancers meeting configured
#     NCR, CR and OS-event minima, in all-labelled and treated subsets.
# Models (Cox, OS primary; PFI secondary)
#   M1 four-state; M2 CR+PR vs SD+PD (ORR); M3 CR vs rest; M_PD CR | PR+SD | PD.
#   Plateau LRT (M1 vs M3), ORR LRT (M1 vs M2), AIC/BIC, configured bootstrap draws.
# Landmarks: none; first configured fixed day; patient-specific end of first-line
#   non-surgical therapy (GDC dates), excluding events before that date.
# Response is a post-treatment variable; results are associations.

# ---- Package imports ----------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr)
  library(survival); library(metafor); library(ggplot2); library(patchwork)
})
# ---- Reproducible configuration and paths ------------------------------------
file_arg <- commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))][1]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_dir, "R", "00_project_configuration.R"))
config <- load_project_configuration(project_dir)
analysis_config <- config$analysis
figure_style <- get_figure_style(project_dir)
figure_spec <- load_figure_specification(project_dir)
figure_text <- figure_text_size(figure_spec)
seed <- analysis_config$random_seeds$pancancer_topology
configure_reproducible_runtime(seed, threads = 1L)
fixed_landmark <- analysis_config$landmark$fixed_days[1]
bootstrap_replicates <- analysis_config$resampling$restricted_bootstrap_replicates
days_per_month <- analysis_config$survival$days_per_month
survival_alpha <- analysis_config$survival$alpha
pancancer_rules <- analysis_config$pancancer
out_tab <- file.path(config$paths$results_dir, "tables", "pancancer_topology")
out_fig <- file.path(config$paths$results_dir, "figures", "pancancer_topology")
dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)

pt <- read_csv(file.path(config$paths$processed_data_dir, "pancancer_patient_response_treatment.csv"),
               show_col_types = FALSE, guess_max = 20000) %>%
  filter(!is.na(response4)) %>%
  mutate(response4 = factor(response4, levels = c("CR", "PR", "SD", "PD")),
    noncr = as.integer(response4 != "CR"),
    orr_fail = as.integer(response4 %in% c("SD", "PD")),
    pd_step = factor(case_when(response4 == "CR" ~ "CR", response4 == "PD" ~ "PD", TRUE ~ "PR_SD"),
      levels = c("CR", "PR_SD", "PD")),
    stage_any = coalesce(stage, clinical_stage),
    stage_late = case_when(str_detect(stage_any, "Stage (III|IV)") ~ 1L,
      str_detect(stage_any, "Stage (I|II)[ABC0-9]*$") ~ 0L),
    grade_high = case_when(grade %in% c("G3", "G4", "High Grade") ~ 1L,
      grade %in% c("G1", "G2", "Low Grade") ~ 0L),
    age_z = as.numeric(scale(age)))

lm_183 <- fixed_landmark
# Input: script 15 rows, an origin key and OS/PFI endpoint. Return: eligible rows
# with event/time/origin. Require finite follow-up strictly beyond the origin;
# subtract the origin in days before converting to months, without censoring.
make_time <- function(d, landmark, endpoint) {
  ev <- d[[endpoint]]; tm <- d[[paste0(endpoint, "_days")]]
  d$event <- ev; d$time_raw <- tm
  if (landmark == "none") { d$origin <- 0
  } else if (landmark == "fixed183") { d$origin <- lm_183
  } else d$origin <- d$therapy_end
  d %>% filter(is.finite(time_raw), !is.na(event), is.finite(origin), time_raw > origin) %>%
    mutate(time = (time_raw - origin) / days_per_month)
}

# Input: time-aligned rows and optional covariate names. Return: one-row HR,
# LRT and information-criterion summary, or NULL for inadequate states/events.
# All four codings use the same complete cases, CR reference and Cox defaults;
# nested LRT df are fixed by the codings, while BIC uses the number of events.
fit_topology <- function(d, covars = character()) {
  rhs <- function(x) paste(c(x, covars), collapse = " + ")
  d <- d[complete.cases(d[, c("time", "event", covars), drop = FALSE]), ] %>% droplevels()
  if (nlevels(d$response4) < 4 || sum(d$event) < pancancer_rules$minimum_model_events) return(NULL)
  f <- list(M1 = coxph(as.formula(paste("Surv(time, event) ~", rhs("response4"))), d),
    M2 = coxph(as.formula(paste("Surv(time, event) ~", rhs("orr_fail"))), d),
    M3 = coxph(as.formula(paste("Surv(time, event) ~", rhs("noncr"))), d),
    M_PD = coxph(as.formula(paste("Surv(time, event) ~", rhs("pd_step"))), d))
  ll <- sapply(f, function(x) x$loglik[2])
  k <- sapply(f, function(x) length(coef(x)))
  hr <- exp(coef(f$M1))[c("response4PR", "response4SD", "response4PD")]
  ci <- exp(confint(f$M1))[c("response4PR", "response4SD", "response4PD"), ]
  m3 <- summary(f$M3)$conf.int["noncr", ]
  tibble(n = nrow(d), events = sum(d$event),
    CR = sum(d$response4 == "CR"), PR = sum(d$response4 == "PR"), SD = sum(d$response4 == "SD"), PD = sum(d$response4 == "PD"),
    HR_PR = hr[1], HR_PR_low = ci[1, 1], HR_PR_high = ci[1, 2],
    HR_SD = hr[2], HR_SD_low = ci[2, 1], HR_SD_high = ci[2, 2],
    HR_PD = hr[3], HR_PD_low = ci[3, 1], HR_PD_high = ci[3, 2],
    HR_NonCR = m3[["exp(coef)"]], HR_NonCR_low = m3[["lower .95"]], HR_NonCR_high = m3[["upper .95"]],
    plateau_p = pchisq(2 * (ll["M1"] - ll["M3"]), 2, lower.tail = FALSE),
    ORR_constraint_p = pchisq(2 * (ll["M1"] - ll["M2"]), 2, lower.tail = FALSE),
    PD_step_vs_M3_p = pchisq(2 * (ll["M_PD"] - ll["M3"]), 1, lower.tail = FALSE),
    PR_vs_SD_p = pchisq(2 * (ll["M1"] - ll["M_PD"]), 1, lower.tail = FALSE),
    AIC_M1 = -2 * ll["M1"] + 2 * k["M1"], AIC_M2 = -2 * ll["M2"] + 2 * k["M2"],
    AIC_M3 = -2 * ll["M3"] + 2 * k["M3"], AIC_M_PD = -2 * ll["M_PD"] + 2 * k["M_PD"],
    BIC_M1 = -2 * ll["M1"] + log(sum(d$event)) * k["M1"], BIC_M2 = -2 * ll["M2"] + log(sum(d$event)) * k["M2"],
    BIC_M3 = -2 * ll["M3"] + log(sum(d$event)) * k["M3"], BIC_M_PD = -2 * ll["M_PD"] + log(sum(d$event)) * k["M_PD"])
}

# Input: eligible landmark rows and requested draw count. Return: valid-draw
# count, lowest-AIC frequencies and plateau/ORR rejection proportions.
# Resample whole observed patients without stratification, omit draws missing
# a state, and fit response-only models; no adjusted-fit/event gate is reused.
boot_topology <- function(d, B = bootstrap_replicates) {
  res <- replicate(B, {
    b <- d[sample(nrow(d), replace = TRUE), ] %>% droplevels()
    if (nlevels(b$response4) < 4) return(c(NA, NA, NA))
    ll <- c(M1 = coxph(Surv(time, event) ~ response4, b)$loglik[2],
      M2 = coxph(Surv(time, event) ~ orr_fail, b)$loglik[2],
      M3 = coxph(Surv(time, event) ~ noncr, b)$loglik[2],
      M_PD = coxph(Surv(time, event) ~ pd_step, b)$loglik[2])
    aic <- -2 * ll + 2 * c(3, 1, 1, 2)
    c(best = which.min(aic), plateau_rej = pchisq(2 * (ll[1] - ll[3]), 2, lower.tail = FALSE) < survival_alpha,
      orr_rej = pchisq(2 * (ll[1] - ll[2]), 2, lower.tail = FALSE) < survival_alpha)
  })
  res <- res[, !is.na(res[1, ]), drop = FALSE]
  tibble(boot_n = ncol(res), pct_best_M1 = mean(res[1, ] == 1), pct_best_M2 = mean(res[1, ] == 2),
    pct_best_M3 = mean(res[1, ] == 3), pct_best_M_PD = mean(res[1, ] == 4),
    pct_plateau_rejected = mean(res[2, ] == 1), pct_ORR_rejected = mean(res[3, ] == 1))
}

sets <- list(
  OV_all = list(d = pt %>% filter(cancer == "OV"), covars = c("age_z", "stage_late"), tier = "reference"),
  LGG_all = list(d = pt %>% filter(cancer == "LGG"), covars = c("age_z", "grade_high"), tier = "primary"),
  LGG_treated = list(d = pt %>% filter(cancer == "LGG", nonsurgical_primary), covars = c("age_z", "grade_high"), tier = "primary"),
  BLCA_treated = list(d = pt %>% filter(cancer == "BLCA", nonsurgical_primary), covars = c("age_z", "stage_late"), tier = "secondary"),
  BLCA_all = list(d = pt %>% filter(cancer == "BLCA"), covars = c("age_z", "stage_late"), tier = "secondary (surgical label)")
)

topo <- list(); boots <- list(); km <- list()
for (nm in names(sets)) for (ep in c("OS", "PFI")) for (lmk in c("none", "fixed183", "therapy_end")) {
  d <- make_time(sets[[nm]]$d, lmk, ep)
  for (adj in c("unadjusted", "adjusted")) {
    r <- fit_topology(d, if (adj == "adjusted") sets[[nm]]$covars else character())
    if (!is.null(r)) topo[[length(topo) + 1]] <- r %>% mutate(set = nm, tier = sets[[nm]]$tier,
      endpoint = ep, landmark = lmk, adjustment = adj, .before = 1)
  }
  if (ep == "OS" && lmk %in% c("none", "therapy_end") && nlevels(droplevels(d$response4)) == 4) {
    boots[[length(boots) + 1]] <- boot_topology(d) %>% mutate(set = nm, landmark = lmk, .before = 1)
  }
  if (ep == "OS" && lmk == "therapy_end") km[[nm]] <- d %>% mutate(set = nm)
}
topo <- bind_rows(topo) %>% rowwise() %>%
  mutate(best_AIC = c("M1", "M2", "M3", "M_PD")[which.min(c(AIC_M1, AIC_M2, AIC_M3, AIC_M_PD))],
         best_BIC = c("M1", "M2", "M3", "M_PD")[which.min(c(BIC_M1, BIC_M2, BIC_M3, BIC_M_PD))]) %>% ungroup()
boots <- bind_rows(boots)
write_csv(topo, file.path(out_tab, "topology_models_by_set.csv"))
write_csv(boots, file.path(out_tab, "topology_bootstrap_by_set.csv"))

# Descriptive dichotomy across cancers.
dich <- list()
for (cn in sort(unique(pt$cancer))) for (sub in c("all", "treated")) for (lmk in c("none", "therapy_end")) {
  d0 <- pt %>% filter(cancer == cn); if (sub == "treated") d0 <- d0 %>% filter(nonsurgical_primary)
  d <- make_time(d0, lmk, "OS")
  if (sum(d$noncr) < pancancer_rules$minimum_noncr ||
      sum(d$event) < pancancer_rules$minimum_os_events ||
      sum(d$noncr == 0) < pancancer_rules$minimum_cr) next
  f <- coxph(Surv(time, event) ~ noncr, d)
  dich[[length(dich) + 1]] <- tibble(cancer = cn, subset = sub, landmark = lmk, n = nrow(d), events = sum(d$event),
    non_CR = sum(d$noncr), log_HR = coef(f)[[1]], se = sqrt(vcov(f)[1, 1]), HR = exp(coef(f)[[1]]),
    HR_low = exp(confint(f)[1, 1]), HR_high = exp(confint(f)[1, 2]),
    pct_R0_CR = mean(d$R0[d$noncr == 0], na.rm = TRUE), pct_R0_nonCR = mean(d$R0[d$noncr == 1], na.rm = TRUE))
}
dich <- bind_rows(dich)
# Each subset/origin callback takes eligible cancer log-HRs/SEs and returns
# pooled HR, heterogeneity and prediction interval, plus a non-OV sensitivity.
# REML assumes independent cancer estimates; unweighted dichotomy fits remain
# separate from the four-state topology models and their eligibility gate.
dich_meta <- dich %>% group_by(subset, landmark) %>% group_modify(function(x, ...) {
  m <- rma(yi = x$log_HR, sei = x$se, method = "REML")
  mo <- rma(yi = x$log_HR[x$cancer != "OV"], sei = x$se[x$cancer != "OV"], method = "REML")
  tibble(k = nrow(x), cancers = paste(x$cancer, collapse = ";"), HR = exp(as.numeric(m$b)), HR_low = exp(m$ci.lb),
    HR_high = exp(m$ci.ub), I2 = m$I2, tau2 = m$tau2, PI_low = exp(predict(m)$pi.lb), PI_high = exp(predict(m)$pi.ub),
    HR_excl_OV = exp(as.numeric(mo$b)), I2_excl_OV = mo$I2)
}) %>% ungroup()
write_csv(dich, file.path(out_tab, "dichotomy_cr_vs_noncr_by_cancer.csv"))
write_csv(dich_meta, file.path(out_tab, "dichotomy_meta.csv"))

# ------------------------------------------------------------------ figures
fd <- dich %>% filter(landmark == "none") %>%
  mutate(txt = sprintf("%.2f (%.2f\u2013%.2f)", HR, HR_low, HR_high),
         n_txt = as.character(as.integer(n)))
# Explicit ordering by the all-subset (primary analysis) HR, ascending.
ord_all <- fd %>% filter(subset == "all") %>% arrange(HR) %>% pull(cancer)
fd <- fd %>%
  mutate(cancer_o = factor(cancer, levels = ord_all),
         y_off = ifelse(subset == "treated", 0.125, -0.125),
         y_off = ifelse(cancer %in% names(which(table(fd$cancer) == 1)), 0, y_off),
         y_pos = as.numeric(cancer_o) + y_off)
s3_open_axes <- theme(
  panel.border = element_blank(),
  axis.line = element_line(colour = "black", linewidth = 0.4),
  panel.grid.major = element_line(linewidth = 0.3, colour = "grey88")
)
p_forest <- ggplot(fd, aes(HR, cancer_o, xmin = HR_low, xmax = HR_high, colour = subset, shape = subset)) +
  geom_vline(xintercept = 1, linetype = 2, colour = figure_style$neutral[["mid"]]) +
  geom_errorbar(width = 0.2, orientation = "y", position = position_dodge(0.5)) +
  geom_point(position = position_dodge(0.5)) + scale_x_log10() +
  scale_colour_manual(values = figure_style$subset) +
  scale_shape_manual(values = c(all = 16, treated = 17)) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.2))) +
  labs(x = "OS hazard ratio, NCR versus CR (log scale)", y = NULL, colour = "Subset", shape = "Subset") +
  formal_figure_theme(figure_spec) + s3_open_axes
header_y <- length(ord_all) + 0.85
p_cols <- ggplot(fd, aes(y = y_pos)) +
  geom_text(aes(x = 0, label = txt), hjust = 0, size = figure_text, family = figure_spec$font_family) +
  geom_text(aes(x = 34, label = n_txt), hjust = 1, size = figure_text, family = figure_spec$font_family) +
  annotate("text", x = 0, y = header_y, label = "HR (95% CI)", hjust = 0, fontface = "bold", size = figure_text, family = figure_spec$font_family) +
  annotate("text", x = 34, y = header_y, label = "n", hjust = 1, fontface = "bold", size = figure_text, family = figure_spec$font_family) +
  scale_y_continuous(limits = c(0.4, length(ord_all) + 1.2), expand = expansion(mult = c(0, 0))) +
  scale_x_continuous(limits = c(0, 34), expand = expansion(mult = c(0, 0))) +
  coord_cartesian(clip = "off") + formal_figure_theme(figure_spec, base = "void") +
  theme(plot.margin = margin(2, 2, 2, 1, unit = "mm"))
p_d <- (p_forest | p_cols) +
  plot_layout(widths = grid::unit(c(1, 36), c("null", "mm")), guides = "collect") +
  theme(legend.position = "right")
save_formal_figure(p_d, file.path(out_fig, "dichotomy_forest_by_cancer"), height_mm = 150, spec = figure_spec)

hd <- topo %>% filter(endpoint == "OS", adjustment == "unadjusted", landmark %in% c("none", "therapy_end")) %>%
  select(set, landmark, n, events, starts_with("HR_PR"), starts_with("HR_SD"), starts_with("HR_PD")) %>%
  rename_with(~ paste0(.x, "_est"), c(HR_PR, HR_SD, HR_PD)) %>%
  pivot_longer(-c(set, landmark, n, events), names_to = c("state", ".value"), names_pattern = "HR_(PR|SD|PD)_(est|low|high)") %>%
  rename(HR = est, low = low, high = high) %>%
  mutate(
    state = factor(state, levels = c("PR", "SD", "PD")),
    analysis = factor(recode(landmark, none = "Diagnosis", therapy_end = "Therapy-end landmark"),
      levels = c("Diagnosis", "Therapy-end landmark"))
  )
# One row per panel: each panel holds a single analysis, so its n/events are
# unambiguous. The label occupies a reserved band above the 30 gridline in
# every facet, so it cannot cross a PR/SD/PD whisker and sits at the same
# height throughout the figure.
ann <- hd %>% group_by(set, landmark, analysis) %>%
  summarise(n = first(n), events = first(events), .groups = "drop") %>%
  mutate(label = sprintf("n=%d, %d deaths", n, events))
# Locked display assertion: every whisker ends below 30, and the 8-pt line
# fits between the 30 gridline and the top of the 50 panel limit.
s4_y_max <- 50
s4_label_y <- 45
stopifnot(max(hd$high) < 30, min(hd$low) > 0.12,
  s4_label_y / 10^0.14 > 30, s4_label_y < s4_y_max)
set_labels <- c(BLCA_all = "BLCA, all", BLCA_treated = "BLCA, treated", LGG_all = "LGG, all",
  LGG_treated = "LGG, treated", OV_all = "OV, all")
s4_open_axes <- theme(
  panel.border = element_blank(),
  axis.line = element_line(colour = "black", linewidth = 0.4),
  panel.grid.major = element_line(linewidth = 0.3, colour = "grey88")
)
p_h <- ggplot(hd, aes(state, HR, ymin = low, ymax = high)) +
  geom_hline(yintercept = 1, linetype = 2, colour = figure_style$neutral[["mid"]]) +
  geom_pointrange(colour = "#333333") +
  geom_text(data = ann, aes(x = 2, y = s4_label_y, label = label), inherit.aes = FALSE,
    hjust = 0.5, vjust = 1, size = figure_text, family = figure_spec$font_family) +
  scale_y_log10(limits = c(0.12, s4_y_max), breaks = c(0.3, 1, 3, 10, 30)) +
  facet_grid(analysis ~ set, labeller = labeller(set = set_labels)) +
  labs(x = "First-course response (reference CR)", y = "OS hazard ratio versus CR (log scale)") +
  formal_figure_theme(figure_spec) + s4_open_axes +
  theme(strip.background = element_rect(fill = "grey92", colour = NA))
save_formal_figure(p_h, file.path(out_fig, "four_state_hr_by_set"), height_mm = 130, spec = figure_spec)

# Input per callback: eligible set name. Return: response-stratified KM plot
# using full observed therapy-end follow-up. The 120-month view is display_only;
# adding (0, 1) starts the curve and does not add artificial patient observations.
km_plots <- lapply(names(km), function(nm) {
  sf <- survfit(Surv(time, event) ~ response4, km[[nm]])
  td <- tibble(time = sf$time, surv = sf$surv, group = rep(sub("response4=", "", names(sf$strata)), sf$strata))
  td <- bind_rows(td, tibble(time = 0, surv = 1, group = unique(td$group))) %>%
    mutate(group = factor(group, levels = c("CR", "PR", "SD", "PD")))
  ggplot(td, aes(time, surv, colour = group, linetype = group)) + geom_step() +
    scale_colour_manual(values = figure_style$response[c("CR", "PR", "SD", "PD")]) +
    scale_linetype_manual(values = figure_style$response_linetype[c("CR", "PR", "SD", "PD")]) +
    coord_cartesian(xlim = c(0, 120)) + labs(title = nm, x = "Months after end of first-line therapy", y = "OS", colour = NULL, linetype = NULL) +
    theme_bw(9) + theme(legend.position = "bottom")
})
ggsave(file.path(out_fig, "km_therapy_end_landmark_by_set.png"), wrap_plots(km_plots, nrow = 1), width = 15, height = 4, dpi = 300)

options(width = 250)
show <- topo %>% filter(endpoint == "OS") %>% select(set, landmark, adjustment, n, events, PR, SD, PD,
  HR_PR, HR_SD, HR_PD, HR_NonCR, plateau_p, ORR_constraint_p, PD_step_vs_M3_p, PR_vs_SD_p, best_AIC, best_BIC)
print(as.data.frame(show %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))))
cat("\nBootstrap:\n"); print(as.data.frame(boots))
cat("\nDichotomy meta:\n"); print(as.data.frame(dich_meta))
cat("\nPFI:\n"); print(as.data.frame(topo %>% filter(endpoint == "PFI", adjustment == "unadjusted") %>%
  select(set, landmark, n, HR_PR, HR_SD, HR_PD, plateau_p, ORR_constraint_p, best_AIC) %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))))
