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
    participant_label: List?

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

    // Method to use to perform surface reconstruction and cortical/subcortical segmentation. Will only affect subjects > 3 months of age. Recon-all-clinical is highly recommended for subjects between 3 months and 5 years old. Options include recon-all, recon-all-clinical, or FastSurfer.
    method: String = 'recon-all-clinical'

    // Path to FreeSurfer license file.
    fs_license: String?

    // Name of the atlas to use. This will determine the BIDS atlas to use. Multiple values can be specified.
    atlas_name: String = 'BrainnetomeChild'

    // Path to the directory containing the atlases. This should be a directory containing the atlases in BIDS format. If not specified, will search in the default location ('$projectDir/assets/').
    atlas_folder: String = "${env('HOME')}/.cache/sf-pediatric/templates"

    // Run denoising on the T1w images.
    run_t1_denoising: Boolean = true

    // Run N4 bias correction on the T1w images.
    run_t1_n4: Boolean = true

    // Run resampling on the T1w images.
    run_t1_resampling: Boolean = true

    // Run cropping on the T1w images.
    run_t1_crop: Boolean = true

    // Run denoising on the T2w images.
    run_t2_denoising: Boolean = true

    // Run N4 bias correction on the T2w images.
    run_t2_n4: Boolean = true

    // Run resampling on the T2w images.
    run_t2_resampling: Boolean = true

    // Run cropping on the T2w images.
    run_t2_crop: Boolean = true

    // Run denoising on the DWI images.
    run_dwi_denoising: Boolean = true

    // Run Gibbs ringing correction on the DWI images.
    run_dwi_degibbs: Boolean = false

    // Run topup in the susceptibility distortion correction step.
    run_dwi_topup: Boolean = true

    // Run eddy in the eddy current correction step.
    run_dwi_eddy: Boolean = true

    // Run N4 bias correction on the DWI images.
    run_dwi_n4: Boolean = true

    // Run normalization on the DWI images.
    run_dwi_normalize: Boolean = true

    // Run resampling on the DWI images.
    run_dwi_resampling: Boolean = true

    // Run PFT tracking.
    run_pft_tracking: Boolean = true

    // Run local tracking.
    run_local_tracking: Boolean = true

    // If set to true, will compute the average diffusivities for the NODDI/Freewater models and average them across all subjects to use as fixed diffusivities for all subjects.
    average_diff_priors: Boolean = false

    // Whether to run the NODDI processing step. If selected, the resulting metric maps will be added to the list used in the bundling and connectomics profile. NODDI is only available for multi-shell acquisitions, for single-shell acquisitions, please consider using Freewater model instead.
    run_noddi: Boolean = false

    // Whether to run the Freewater processing step. If selected, the resulting metric maps will be added to the list used in the bundling and connectomics profile.
    run_freewater: Boolean = false

    // Path to the WM bundles atlas directory.
    atlas_directory: String?

    // Display version and exit.
    version: Boolean

    // Email address for completion summary.
    email: String?

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

    // MultiQC report title for subject report. Printed as page header, used for filename if not otherwise specified.
    multiqc_title_subject: String = "sf-pediatric MultiQC Subject Report"

    // MultiQC report title for global report. Printed as page header, used for filename if not otherwise specified.
    multiqc_title_global: String = "sf-pediatric MultiQC Global Report"

    // Boolean whether to validate parameters against the schema at runtime
    validate_params: Boolean = true

    // Profiles options
    tracking: Boolean
    bundling: Boolean
    connectomics: Boolean
    segmentation: Boolean

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
