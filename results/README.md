# Results directory

- `figures/main/`: three formal manuscript figures in PNG and PDF.
- `figures/supplementary/`: five formal supplementary figures.
- `tables/main/`: formal Tables 1-2, including machine-readable and formatted Table 2.
- `tables/supplementary/`: CSVs behind Supplementary Tables S1-S4: S1, external cohorts; S2a-b, operational HGSOC cohort flow and topology; S3a-e, post hoc robustness analyses (residual-disease strata and interaction, topology within strata, delayed entry and landmark-time adjustment, external leave-one-out re-pooling, and HKSJ, prediction-interval and Firth-penalised external pooling); S4, pan-cancer label-semantics audit.
- Files in `tables/main/` and `tables/supplementary/` are byte-identical copies written by stage 20 from the analysis directories; stage 21 assembles the formatted supplementary tables from the same sources.
- Named analysis directories under `tables/`: compact locked outputs required by the manuscript build and audit trail.
- `tables/compact/`: selected molecular, pathway, and WGCNA summaries; large reproducible gene-level intermediates are excluded.
