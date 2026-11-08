# Public data sources and expected local layout

Raw data are not committed. Configure the local root in `config/paths.yml` or with environment variables.

## UCSC Xena / TCGA Pan-Cancer

Source: <https://xenabrowser.net/datapages/>

Expected under `xena_dir`:

- `TCGA.OV.sampleMap/OV_clinicalMatrix`
- `Survival_SupplementalTable_S1_20171025_xena_sp` (the frozen copy carries a seven-line pasted preamble; the clean file from the Pan-Cancer Atlas hub is read identically, see `docs/REPRODUCIBILITY.md`)
- `agilent_pancan/TCGA.OV.HT_HG-U133A.gz`
- `TCGA.HRD_withSampleID.txt.gz`
- `Gistic2_CopyNumber_Gistic2_all_data_by_genes.gz`
- `Gistic2_CopyNumber_Gistic2_all_thresholded.by_genes.gz`
- `TCGA-RPPA-pancan-clean.xena.gz`
- `HumanMethylation27.gz`
- `illuminaMethyl27K_hg18_gpl8490_TCGAlegacy`
- `mc3.v0.2.8.PUBLIC.nonsilentGene.xena.gz` (audit only)
- `clinical_matrices/` for the pan-cancer label audit

## NCI Genomic Data Commons

Source: <https://api.gdc.cancer.gov/cases>

`scripts/01_download_gdc_treatments.R` retrieves paginated public treatment records and writes the local cache under `data/external/gdc_tcga_treatments/`.

## cBioPortal

Source study: `ov_tcga_pan_can_atlas_2018`

Portal: <https://www.cbioportal.org/>

Used for complete somatic BRCA/HRR mutation calls and sequenced-sample coverage. Downloaded files belong under `data/external/tcga_ov_cbioportal/`.

## Gene Expression Omnibus

Portal: <https://www.ncbi.nlm.nih.gov/geo/>

Accessions:

- `GSE63885`: four-class first-line response and survival
- `GSE23554`: cisplatin-based complete versus incomplete response
- `GSE30161`: accessed through curatedOvarianData

Raw GEO matrices and platform annotations belong under `data/external/geo_response_cohorts/` or may be obtained through GEOquery.

## Bioconductor and MSigDB

- curatedOvarianData: <https://bioconductor.org/packages/curatedOvarianData/>
- MSigDB gene sets are obtained through `msigdbr`; cached RDS objects are not redistributed.

## Included derivatives

`data/processed/` contains small, public-data-derived files needed to reproduce the primary clinical analyses without re-downloading large expression and multi-omic matrices. `data/supplementary/` contains the case/sample-level files accompanying the manuscript. These include public TCGA/GEO identifiers and must not be described as a new anonymized institutional cohort.
