#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    scilus/sf-pediatric
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/scilus/sf-pediatric
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { SF_PEDIATRIC  } from './workflows/sf_pediatric'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_sf_pediatric_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_sf_pediatric_pipeline'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run main analysis pipeline depending on type of input
//
workflow SCILUS_SF_PEDIATRIC {

    take:
    input_bids  // channel: BIDS folder read in from --input

    main:
    //
    // WORKFLOW: Run pipeline
    //
    SF_PEDIATRIC (
        input_bids
    )

    emit:
    multiqc_report = SF_PEDIATRIC.out.multiqc_report // channel: /path/to/multiqc_report.html
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

params {

    // Path to the BIDS directory location.
    input: String?

    // List of participant IDs or a single participant ID.
    participant_label: String?

    // Path to the derivatives directory to use as input.
    input_deriv: String?

    // Path to the BIDS script.
    bids_script: String = "${projectDir}/bin/BIDSLayout.py"

    // The output directory where the results will be saved. You have to use absolute paths to storage on Cloud infrastructure.
    outdir: String

    // URL to download templates from.
    templates_url: String = 'https://osf.io/Kd8h7/download'

    // Path to the directory where templates will be downloaded and cached.
    templates_download_path: String = "${env('HOME')}/.cache/sf-pediatric"

    // Email address for completion summary.
    email: String?

    // MultiQC report title for subject report. Printed as page header, used for filename if not otherwise specified.
    multiqc_title_subject: String = "sf-pediatric MultiQC Subject Report"

    // MultiQC report title for global report. Printed as page header, used for filename if not otherwise specified.
    multiqc_title_global: String = "sf-pediatric MultiQC Global Report"

    // Method to use to perform surface reconstruction and cortical/subcortical segmentation. Will only affect subjects > 3 months of age. Recon-all-clinical is highly recommended for subjects between 3 months and 5 years old. Options include recon-all, recon-all-clinical, or FastSurfer.
    method: String = 'recon-all-clinical'

    // Path to FreeSurfer license file.
    fs_license: String?

    // Use CerebNet for cerebellum segmentation in FastSurfer.
    cerebnet: Boolean = false

    // Use HypVINN for hypothalamus sub-segmentation in FastSurfer.
    hypvinn: Boolean = false

    // Use 3T acquisition parameters.
    acq3T: Boolean = true

    // Path to FreeSurfer/FastSurfer/M-CRIB-S output directory.
    fs_output_dir: String?

    // Join threshold used in the MCRIBS surface reconstruction step.
    mcribs_jointhresh: Float?

    // Use deformable fast collision test in the MCRIBS surface reconstruction step.
    mcribs_fastcollision: Boolean = false

    // Do not ensure pial is outside of WM in the MCRIBS surface reconstruction step.
    mcribs_nopialoutside: Boolean = false

    // Seed used in the MCRIBS surface reconstruction step.
    mcribs_seed: Float = 1234

    // Name of the atlas to use. This will determine the BIDS atlas to use. Multiple values can be specified.
    atlas_name: String = 'BrainnetomeChild'

    // Path to the directory containing the atlases. This should be a directory containing the atlases in BIDS format. If not specified, will search in the default location ('$projectDir/assets/').
    atlas_folder: String = "${env('HOME')}/.cache/sf-pediatric/templates"

    // Indexes of the subcortical ROIs in the atlas to use in the QC report. Will mostly be used to properly separate cortical and subcortical ROIs in the QC report. Should be provided as a string of comma-separated values or ranges (e.g. '189:224').
    subcortical_rois: String = '189:224'

    // Path to alternative weights for SynthStrip brain extraction.
    synthstrip_weights: String?

    // Run denoising on the T1w images.
    run_t1_denoising: Boolean = true

    // Run N4 bias correction on the T1w images.
    run_t1_n4: Boolean = true

    // Run resampling on the T1w images.
    run_t1_resampling: Boolean = true

    // Run cropping on the T1w images.
    run_t1_crop: Boolean = true

    // Number of coils used in the T1w denoising step.
    t1_denoise_number_of_coils: Integer = 1

    // Number of B-spline knots per voxel used in the T1w bias correction step.
    t1_bias_bspline_knot_per_voxel: Float = 8

    // Shrink factor used in the T1w bias correction step.
    t1_bias_shrink_factor: Integer = 4

    // Voxel size used in the T1w resampling step.
    t1_resample_voxel_size: Integer = 1

    // Interpolation method used in the T1w resampling step.
    t1_resample_interp: String = 'lin'

    // Mask border threshold used in the SynthStrip brain extraction step.
    t1_synthstrip_border: Integer = 1

    // Exclude CSF from the border in the SynthStrip brain extraction step.
    t1_synthstrip_nocsf: Boolean = false

    // Run denoising on the T2w images.
    run_t2_denoising: Boolean = true

    // Run N4 bias correction on the T2w images.
    run_t2_n4: Boolean = true

    // Run resampling on the T2w images.
    run_t2_resampling: Boolean = true

    // Run cropping on the T2w images.
    run_t2_crop: Boolean = true

    // Number of coils used in the T2w denoising step.
    t2_denoise_number_of_coils: Integer = 1

    // Number of B-spline knots per voxel used in the T2w bias correction step.
    t2_bias_bspline_knot_per_voxel: Float = 8

    // Shrink factor used in the T2w bias correction step.
    t2_bias_shrink_factor: Integer = 4

    // Voxel size used in the T2w resampling step.
    t2_resample_voxel_size: Integer = 1

    // Interpolation method used in the T2w resampling step.
    t2_resample_interp: String = 'lin'

    // Mask border threshold used in the SynthStrip brain extraction step.
    t2_synthstrip_border: Integer = 1

    // Exclude CSF from the border in the SynthStrip brain extraction step.
    t2_synthstrip_nocsf: Boolean = false

    // Dimensionality of the registered images.
    coreg_dimensionality: Integer = 3

    // Transform used in the coregistration step. t: translation (1 stage), r: rigid (1 stage), a: rigid + affine (2 stages), s: rigid + affine + deformable syn (3 stages)
    coreg_transform: String = 'a'

    // Use antsRegistrationSyNQuick for the coregistration step.
    coreg_quick: Boolean = false

    // B0 threshold used in the DWI preprocessing steps.
    dwi_b0_threshold: Integer = 20

    // Shell tolerance used in the DWI preprocessing steps.
    dwi_shell_tolerance: Integer = 50

    // Run denoising on the DWI images.
    run_dwi_denoising: Boolean = true

    // Patch size used in the DWI denoising step.
    dwi_denoise_patch_size: Integer = 7

    // Run Gibbs ringing correction on the DWI images.
    run_dwi_degibbs: Boolean = false

    // Run topup in the susceptibility distortion correction step.
    run_dwi_topup: Boolean = true

    // Path to the susceptibility distortion correction config file.
    dwi_susceptibility_config_file: String = 'b02b0.cnf'

    // Prefix used in the susceptibility distortion correction step.
    dwi_susceptibility_output_prefix: String = 'topup_results'

    // Readout time used in the susceptibility distortion correction step.
    dwi_susceptibility_readout: Float = 0.04

    // Encoding direction used in the susceptibility distortion correction step.
    dwi_susceptibility_encoding_dir: String = 'y'

    // Run eddy in the eddy current correction step.
    run_dwi_eddy: Boolean = true

    // Command used in the motion and eddy correction step.
    dwi_motion_and_eddy_command: String = 'eddy_cpu'

    // Bet f threshold used in the motion and eddy correction step.
    dwi_motion_and_eddy_bet_f_threshold: Float = 0.16

    // Restore slices in the motion and eddy correction step.
    dwi_motion_and_eddy_restore_slices: Boolean = true

    // Shells used in the PowderAverage step.
    dwi_pwdavg_shells: String?

    // Brain border used in the SynthStrip brain extraction step.
    dwi_synthstrip_border: Integer = 1

    // Exclude CSF from the border in the SynthStrip brain extraction step.
    dwi_synthstrip_nocsf: Boolean = false

    // Alternative weights used in the SynthStrip brain extraction step.
    dwi_synthstrip_weights: String = "$projectDir/assets/synthstrip.infant.1.pt"

    // Bet f threshold used in the brain extraction step.
    dwi_bet_f_threshold: Float = 0.16

    // Run N4 bias correction on the DWI images.
    run_dwi_n4: Boolean = true

    // Number of B-spline knots per voxel used in the DWI bias correction step.
    dwi_bias_bspline_knot_per_voxel: Float = 8

    // Shrink factor used in the DWI bias correction step.
    dwi_bias_shrink_factor: Integer = 4

    // Run normalization on the DWI images.
    run_dwi_normalize: Boolean = true

    // FA mask threshold used in the normalization step.
    dwi_normalize_fa_mask_threshold: Float = 0.4

    // Run resampling on the DWI images.
    run_dwi_resampling: Boolean = true

    // Voxel size used in the DWI resampling step.
    dwi_resample_voxel_size: Integer = 1

    // Interpolation method used in the DWI resampling step.
    dwi_resample_interp: String = 'lin'

    // Voxel size used in the DWI mask resampling step.
    dwi_resample_mask_voxel_size: Integer = 1

    // Interpolation method used in the DWI mask resampling step.
    dwi_resample_mask_interp: String = 'nn'

    // Maximum shell value used in the DTI processing step.
    dti_max_shell_value: Integer = 1200

    // Shells used in the DTI processing step.
    dti_shells: String?

    // Initial minimum FA threshold to use to compute the FRF.
    frf_fa: Float = 0.7

    // If frf_fa does not extract enough voxels, this is the minimum FA threshold that will be tried.
    frf_min_fa: Float = 0.5

    // Minimum number of voxels to include in the computation of the FRF.
    frf_nvox_min: Integer = 300

    // Radius of the ROI used to compute the FRF.
    frf_roi_radius: Integer = 20

    // Method used to compute the FRF.
    frf_set_method: String = 'ssst'

    // Manual FRF values.(e.g. '15,4,4'). This is set from the normative curves. Use this option only to apply a single FRF to every participants. For more information, please see [the documentation](https://scilus.github.io/sf-pediatric/guides/priors/).
    frf_manual_frf: String?

    // Minimum FODF shell value used.
    fodf_min_shell_value: Integer = 700

    // Shells used in the FODF processing step.
    fodf_shells: String?

    // Spherical harmonics order used in the FODF processing step.
    fodf_sh_order: Integer = 8

    // Spherical harmonics basis used in the FODF processing step. Choices: descoteaux07 or tournier07.
    fodf_sh_basis: String = 'descoteaux07'

    // Method used to compute the FODF.
    fodf_set_method: String = 'ssst'

    // Relative threshold used in the FODF processing step.
    fodf_relative_threshold: Float = 0.1

    // FODF a factor used in the FODF processing step.
    fodf_a_factor: Float = 2.0

    // Maximum FA threshold used in the FODF processing step.
    fodf_max_fa_threshold: Float = 0.1

    // Minimum MD threshold used in the FODF processing step.
    fodf_min_md_threshold: Float = 0.002

    // Run PFT tracking.
    run_pft_tracking: Boolean = true

    // Seeding mask type used in the PFT tracking step. Choices: wm, fa, or interface.
    pft_seeding_mask_type: String = 'wm'

    // FA threshold to use on FA map to generate seeding mask.
    pft_fa_threshold: Float = 0.2

    // Random seed used in the PFT tracking step.
    pft_random_seed: Integer = 1234

    // If true, compress the streamlines.
    pft_compress: Boolean = true

    // Compression value for the streamlines' compression.
    pft_compress_value: Float = 0.2

    // Algorithm used in the PFT tracking step. Choices: prob or det
    pft_algo: String = 'prob'

    // Number of seeds used in the PFT tracking step.
    pft_nbr_seeds: Integer = 10

    // Seeding type used in the PFT tracking step. Choices: npv or nt.
    pft_seeding_type: String = 'npv'

    // Step value used in the PFT tracking step.
    pft_step: Float = 0.5

    // Theta value used in the PFT tracking step.
    pft_theta: Float = 20

    // SF threshold used in the PFT tracking step.
    pft_sfthres: Float = 0.1

    // Initial SF threshold used in the PFT tracking step.
    pft_sfthres_init: Float = 0.5

    // Minimum length used in the PFT tracking step.
    pft_min_len: Float = 20

    // Maximum length used in the PFT tracking step.
    pft_max_len: Float = 200

    // Number of particles used in the PFT tracking step.
    pft_particles: Integer = 15

    // Length of PFT back tracking (mm)
    pft_back: Integer = 2

    // Length of PFT forward tracking (mm).
    pft_front: Integer = 1

    // Run local tracking.
    run_local_tracking: Boolean = true

    // Seeding mask type used in the local tracking step.
    local_seeding_mask_type: String = 'wm'

    // FA threshold used for the tracking mask.
    local_fa_tracking_mask_threshold: Float = 0.4

    // FA threshold used for the seeding mask.
    local_fa_seeding_mask_threshold: Float = 0.4

    // Tracking mask type used in the local tracking step. Choices: wm, fa, or interface.
    local_tracking_mask_type: String = 'wm'

    // Random seed used in the local tracking step.
    local_random_seed: Integer = 1234

    // If true, compress the streamlines.
    local_compress: Boolean = true

    // Compression value for the streamlines' compression.
    local_compress_value: Float = 0.2

    // Algorithm used in the local tracking step. Choices: prob or det
    local_algo: String = 'prob'

    // Number of seeds used in the local tracking step.
    local_nbr_seeds: Integer = 10

    // Seeding type used in the local tracking step. Choices: npv or nt.
    local_seeding_type: String = 'npv'

    // Step value used in the local tracking step.
    local_step: Float = 0.5

    // Theta value used in the local tracking step.
    local_theta: Float = 20

    // SF threshold used in the local tracking step.
    local_sfthres: Float = 0.1

    // Minimum length used in the local tracking step.
    local_min_len: Float = 20

    // Maximum length used in the local tracking step.
    local_max_len: Float = 200

    // If set to true, will compute the average diffusivities for the NODDI/Freewater models and average them across all subjects to use as fixed diffusivities for all subjects.
    average_diff_priors: Boolean = false

    // Parallel diffusivity value to use in models fitting (in mm^2/s). If not set, it will be derived from normative growth curves based on participant's age.
    para_diff: Float?

    // Isotropic diffusivity value to use in models fitting (in mm^2/s). If not set, it will be derived from normative growth curves based on participant's age.
    iso_diff: Float?

    // Perpendicular diffusivity value to use in models fitting (in mm^2/s). If not set, it will be derived from normative growth curves based on participant's age.
    perp_diff: Float?

    // Minimum perpendicular diffusivity value (in mm^2/s) to use in models fitting. If not set, it will be derived from normative growth curves based on participant's age
    perp_diff_min: Float?

    // Maximum perpendicular diffusivity value (in mm^2/s) to use in models fitting. If not set, it will be derived from normative growth curves based on participant's age
    perp_diff_max: Float?

    // Whether to run the NODDI processing step. If selected, the resulting metric maps will be added to the list used in the bundling and connectomics profile. NODDI is only available for multi-shell acquisitions, for single-shell acquisitions, please consider using Freewater model instead.
    run_noddi: Boolean = false

    // Value to use as the first regularization parameter (lambda1) in the NODDI fitting process.
    noddi_lambda1: Float = 0.5

    // Value to use as the second regularization parameter (lambda2) in the NODDI fitting process.
    noddi_lambda2: Float = 0.001

    // Whether to run the Freewater processing step. If selected, the resulting metric maps will be added to the list used in the bundling and connectomics profile.
    run_freewater: Boolean = false

    // Value to use as the first regularization parameter (lambda1) in the Freewater fitting process.
    freewater_lambda1: Float = 0

    // Value to use as the second regularization parameter (lambda2) in the Freewater fitting process.
    freewater_lambda2: Float = 0.25

    // Path to the WM bundles atlas directory.
    atlas_directory: String?

    // Ratio of vote across models to consider a streamline for saving. If you have 5 input models and a ratio of 0.5, you will need at least 3 votes.
    minimal_vote_ratio: Float = 0.5

    // Percentage of the length of the tree that clusters of individual streamlines will be pruned. Higher values will remove more streamlines.
    outlier_alpha: Float = 0.6

    // Number of points to segment the bundles.
    nb_points: Integer = 5

    // Colormap to use for coloring the bundles. Color only affects visualization.
    colormap: String = 'jet'

    // If set, will use hyperplane to segment bundles (still experimental), otherwise, will use the euclidean distance.
    use_hyperplane: Boolean = false

    // If set, will use manhattan distance to segment bundles, otherwise, will use the euclidean distance.
    use_manhattan: Boolean = false

    // If set, weight statistics based on the number of voxel going through the voxel.
    density_weighting: Boolean = true

    // If set, the weights will be normalized to the [0,1] range.
    normalize_weights: Boolean = true

    // If set, will output bundles' length.
    length_stats: Boolean = true

    // If set, will output statistics in endpoints.
    endpoints_stats: Boolean = true

    // If set, will output mean and std values per bundle per metrics.
    means_std: Boolean = true

    // If set, will output volume values per bundle.
    volume: Boolean = true

    // If set, will output the streamline count per bundle.
    streamline_count: Boolean = true

    // If set, will output volume values per labels per bundle.
    volume_per_labels: Boolean = true

    // If set, will output mean and std per points per metrics per bundle.
    mean_std_per_point: Boolean = true

    // Dimensionality of the label file.
    labels_transform_dimensionality: Integer = 3

    // Name to use as suffix in the output filename.
    labels_output_suffix: String = '_labels'

    // Interpolation method used in the label transformation step. Choices: NearestNeighbor, Linear, or BSpline.
    labels_interpolation: String = 'NearestNeighbor'

    // Output data type used in the label transformation step. Choices: float or int.
    labels_output_dtype: String = 'int'

    // Run COMMIT2 filtering.
    run_commit2: Boolean = true

    // Lambda value used in the COMMIT filtering step.
    commit2_lambda: Float = 0.001

    // Use the ball and stick model in the COMMIT filtering step.
    commit_ball_stick: Boolean = false

    // Number of directions used in the COMMIT filtering step.
    commit_nbr_dir: Integer = 500

    // Do not prune the tractogram.
    decompose_no_pruning: Boolean = false

    // Do not remove loops from the tractogram.
    decompose_no_remove_loops: Boolean = false

    // Do not remove outliers from the tractogram.
    decompose_no_remove_outliers: Boolean = false

    // Do not remove curvilinear structures from the tractogram.
    decompose_no_remove_curv: Boolean = false

    // Minimum length used in the tractogram decomposition step.
    decompose_min_len: Float = 20

    // Maximum length used in the tractogram decomposition step.
    decompose_max_len: Float = 200

    // Outlier threshold used in the tractogram decomposition step.
    decompose_outlier_threshold: Float = 0.6

    // Maximum angle used in the tractogram decomposition step.
    decompose_max_angle: Float = 330.0

    // Maximum curvature used in the tractogram decomposition step.
    decompose_max_curv: Float = 10.0

    // Use length weighting in the AFD fixel processing step.
    afd_fixel_length_weighting: Boolean = false

    // Template space to output to. The available template are the ones supported by TemplateFlow, please see their documentation for an exhaustive list (https://www.templateflow.org/browse/).
    template: String?

    // Resolution of the template space.
    templateflow_res: Integer = 1

    // Cohort to use for the template space (not required for most template, but if it is, simply provide the cohort's number).
    templateflow_cohort: Integer?

    // Path to the TemplateFlow home directory where templates will be downloaded. If you are running the pipeline without internet access, this needs to point to a folder containing predownloaded templates.
    templateflow_home: String = './templateflow'

    // Use the T2w image from the template space (useful with infant data.).
    use_template_t2w: Boolean = false

    // Git commit id for Institutional configs.
    custom_config_version: String = 'master'

    // Base directory for Institutional configs.
    custom_config_base: String = 'https://raw.githubusercontent.com/nf-core/configs/master'

    // Institutional config name.
    config_profile_name: String?

    // Institutional config description.
    config_profile_description: String?

    // Institutional config contact information.
    config_profile_contact: String?

    // Institutional config URL link.
    config_profile_url: String?

    // Display version and exit.
    version: Boolean

    // Method used to save pipeline results to output directory.
    publish_dir_mode: String = 'copy'

    // Do not copy intermediate files to output directory.
    lean_output: Boolean = true

    // Email address for completion summary, only when pipeline fails.
    email_on_fail: String?

    // Send plain-text email instead of HTML.
    plaintext_email: Boolean

    // File size limit when attaching MultiQC reports to summary emails.
    max_multiqc_email_size: String = '25.MB'

    // Do not use coloured log outputs.
    monochrome_logs: Boolean

    // Custom config file to supply to MultiQC.
    multiqc_config: String?

    // Custom logo file to supply to MultiQC. File name must also be set in the MultiQC config file
    multiqc_logo: String?

    // Custom MultiQC yaml file containing HTML including a methods description.
    multiqc_methods_description: String?

    // Boolean whether to validate parameters against the schema at runtime
    validate_params: Boolean = true

    // Suffix to add to the trace report filename. Default is the date and time in the format yyyy-MM-dd_HH-mm-ss.
    trace_report_suffix: String = new java.util.Date().format( 'yyyy-MM-dd_HH-mm-ss')

    // Display the help message.
    help: Boolean

    // Display the full detailed help message.
    help_full: Boolean

    // Display hidden parameters in the help message (only works when --help or --help_full are provided).
    show_hidden: Boolean
}

workflow {

    main:
    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    PIPELINE_INITIALISATION (
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input,
        params.bids_script,
        params.help,
        params.help_full,
        params.show_hidden
    )

    //
    // WORKFLOW: Run main workflow
    //
    SCILUS_SF_PEDIATRIC (
        PIPELINE_INITIALISATION.out.input_bids
    )
    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION (
        params.email,
        params.email_on_fail,
        params.plaintext_email,
        params.outdir,
        params.monochrome_logs,
        SCILUS_SF_PEDIATRIC.out.multiqc_report
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
