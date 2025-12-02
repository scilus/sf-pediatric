# scilus/nf-pediatric: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## `Added`

- Added infrastructure to support the new multiqc report using `nf-neuro` [MultiQC_neuroimaging](https://github.com/nf-neuro/MultiQC_neuroimaging.git) plugin.
- Date and time to multiqc report to avoid overwriting when the pipeline is run twice for the same `outdir` ([[#88](https://github.com/scilus/nf-pediatric/issues/88)])
- Bundle metrics are now exported in clean `.tsv` files for easier handling.
- Dynamic boilerplate methods section in MultiQC report ([[#87](https://github.com/scilus/nf-pediatric/issues/87)])

### `Fixed`

- Filter tractograms to ensure the concatenated one is used when running on derivatives.
- Robustify tractometry steps by using centroids from the WM atlas rather than subject-specific centroids.
- Handle cases where cortical segmentation failed without throwing an error.
- Age validation step in M-CRIB-S module.
- Support custom WM bundle atlas using `--atlas_directory`.
- Fix eddy process when run without topup results ([[#78](https://github.com/scilus/nf-pediatric/issues/78)])

## [0.1.0] - [2025-10-06]

### `Added`

- [Documentation site](https://github.com/scilus/nf-pediatric-documentation) describing requirements, inputs, outputs, parameters, etc.
- Framewise displacement metric in both multiqc reports ([#29](https://github.com/scilus/nf-pediatric/issues/29))
- Age-matched BundleSeg WM bundle atlas for age-adaptable bundle extraction.
- Normative curves for prior determination in FRF and COMMIT modules.

### `Removed`

- Option to use the mean FRF across all subjects has been removed in favor of the normative curves.

### `Fixed`

- Fix name collision when multiple sessions in concatenate stats module.
- Fix stride in QC sections to ensure all axis are plotted correctly ([#62](https://github.com/scilus/nf-pediatric/issues/62))
- Fix mask resampling to force same dimension as b0 volume ([#59](https://github.com/scilus/nf-pediatric/issues/59))
- Fix glob pattern for template to DWI registration QC file.
- Add dynamic resource allocation for registering tractograms in output space ([#56](https://github.com/scilus/nf-pediatric/issues/56))
- Fix RGB FA registration to template space.
- Add filtering step removing null values for anatomical coregistration in case of missing files.
- Fix precedence issues in branching logic for anatomical to diffusion space registration ([#63](https://github.com/scilus/nf-pediatric/issues/63))
- Handling of B0 threshold in `preproc/n4` and `preproc/normalize` ([[#58](https://github.com/scilus/nf-pediatric/issues/58)])

## [0.1.0-beta] - [2025-08-13]

### `Fixed`

- Overwriting of output FA file by template maps due to a non-strict enough glob pattern when warping into a template space.

## [0.1.0-alpha] - [2025-08-06]

### `Added`

- Automatic assessment of iteration pyramid and b-spline parameter in N4 module.
- Add support for age extraction in multisession subjects.
- Includes a new neonate atlas for bundleseg.
- New processing profile for bundling and tractometry. This includes the bundle_seg and tractometry subworkflows.
- More clear logging for missing or not properly formatted `participants.tsv` file and test cases.
- Derivatives now also contain a `README.txt` file with additional informations regarding the pipeline run.
- Derivatives now have sidecar Json files indicating source data, transform file, and specific characteristics.
- Methods for cortical/subcortical segmentation are now selected from a list using `--methods` parameter.
- Recon-all-clinical is now the default segmentation tool for participants over 3 months.
- New Dockerfile for the freesurfer 8.0.0 arm/amd build.
- New `--participant-label` parameter allowing to run the pipeline only for a subset or a single participant from the BIDS dataset.
- Dynamic assessment of subject's age from the `participants.tsv` file in the BIDS input directory.
- Output folder will now contain the `dataset_description.json` file for compliance with BIDS derivatives.
- Add a copy of the `participants.tsv` file in the output directory.

### `Changed`

- Template used to generate probability tissue maps is now the UNC-BCP 4D atlas which contains the cerebellum. UNCInfant is no longer used.

### `Removed`

- Profile `no_symlink` is no longer available. By default, files are copied and not symlinked. Possible to change that behavior with `--publish-dir-mode` parameters.
- Profile `infant` is no longer available. Dynamic assessment is used now.
- M-CRIB-S is no longer used for tracking mask generation. Dropped in favor of pre-generated masks from templates.

## [Unreleased] - [2025-04-06]

### `Added`

- Support for using both local and PFT tracking (union of both tractograms) ([[#30](https://github.com/scilus/nf-pediatric/issues/30)])

## [Unreleased] - [2025-03-18]

### `Added`

- Option to output results (metrics map, tractogram, labels, ...) to a template space (leveraging TemplateFlow).

## [Unreleased] - [2025-03-03]

### `Fixed`

- Output `.annot` and `.stats` file for brainnetome in FS output ([#19](https://github.com/scilus/nf-pediatric/issues/19))
- Resampling/reshaping according to input file when registering brainnetome atlas ([#26](https://github.com/scilus/nf-pediatric/issues/26))

## [Unreleased] - [2025-02-28]

### `Added`

- QC for eddy, topup, and registration processes.
- More verbose description of each MultiQC section.

### `Fixed`

- Completed the addition of QC in pipeline ([#7](https://github.com/scilus/nf-pediatric/issues/7))
- Move cerebellum and hypothalamus sub-segmentation as optional steps in fastsurfer ([#23](https://github.com/scilus/nf-pediatric/issues/23))

## [Unreleased] - [2025-02-14]

### `Changed`

- Replace local modules by their `nf-neuro` equivalent.
- Update modules according to latest version of `nf-neuro` (commit: fc357476ff69fa206f241f77f3f5517daa06b91e)

## [Unreleased] - [2025-02-12]

### `Added`

- BIDS folder as mandatory input ([#16](https://github.com/scilus/nf-pediatric/issues/16)).
- New test datasets (BIDS input folder and derivatives).
- Support BIDS derivatives as input for `-profile connectomics`.
- T2w image for pediatric data are now preprocessed and coregistered in T1w space.

### `Changed`

- `synthstrip` is now the default brain extraction method.
- Bump `nf-core` version to `3.2.0`.

### `Removed`

- Samplesheet input is not longer supported. Using BIDS folder now.

## [Unreleased] - [2025-01-22]

### `Fixed`

- Files coming from Phillips scanner had unvalid datatypes making topup/eddy correction creating weird artifacts. Now files are converted to `--data_type float32`.
- Added build information to fastsurfer container.

## [Unreleased] - [2025-01-20]

### `Added`

- New testing file for anatomical preprocessing and surface reconstruction of infant data.
- New module for formatting of Desikan-Killiany atlas (for infant).
- Output of tissue-specific `fodf` maps in BIDS output.
- Anatomical preprocessing pipeline for infant data using M-CRIB-S and Infant FS.
- Coregistration of T2w and T1w if both available for the infant profile.
- New docker image for infant anatomical segmentation and surface reconstruction (M-CRIB-S and Infant FS)
- Required --dti_shells and --fodf_shells parameters.

### `Fixed`

- Wrong data type for phillips scanners prior to topup.
- Structural segmentation pipeline for infant data. (#3)
- Correctly set `fastsurfer` version in docker container.

### `Changed`

- Bump `nf-core` version to `3.1.2`.
- Refactored `-profile freesurfer` to `-profile segmentation`.
- Config files have been moved from the `modules.config` into themed config files for easier maintainability.
- Fastsurfer and freesurfer outputs are now in their own dedicated output folder.

### `Removed`

- Custom atlas name parameter until the use of custom atlas is enabled.
- White matter mask and labels files as required inputs since they can now be computed for all ages.

## [Unreleased] - [2024-12-23]

### `Added`

- Update minimal `nextflow` version to 24.10.0.
- Add subject and global-level QC using the MultiQC module.
- If `-profile freesurfer` is used, do not run T1 preprocessing.
- Optional DWI preprocessing using parameters.
- New docker containers for fastsurfer, atlases, and QC.
- Transform computation in `segmentation/fastsurfer`.

## [Unreleased] - [2024-11-21]

### `Added`

- Complete test suites for the pipeline using stub-runs.
- Complete port of [Infant-DWI](https://github.com/scilus/Infant-DWI/) modules and workflows into the nf-core template.
