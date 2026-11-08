# Data directory

- `processed/`: compact derivatives of public TCGA/GDC/cBioPortal data used by the primary clinical workflow.
- `supplementary/`: manuscript Supplementary Data 1-2.
- `external/`: ignored local cache for raw Xena, GDC, GEO, cBioPortal, and other public-source downloads.

No institutional or privately collected patient data are included. Public identifiers are retained to support auditability. Large expression/multi-omic matrices and temporary processing files are reconstructed from the sources documented in `docs/DATA_SOURCES.md` and are not versioned.
