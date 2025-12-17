/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
// ** Core modules ** //
include { QC_MULTIQC as MULTIQC_SUBJECT        } from '../modules/nf-neuro/qc/multiqc'
include { QC_MULTIQC as MULTIQC_GLOBAL         } from '../modules/nf-neuro/qc/multiqc'
include { paramsSummaryMap                  } from 'plugin/nf-schema'
include { paramsSummaryMultiqc              } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML            } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText            } from '../subworkflows/local/utils_nfcore_nf-pediatric_pipeline'
include { FETCH_DERIVATIVES                 } from '../subworkflows/local/utils/fetch_derivatives.nf'
include { generateDatasetJson               } from '../subworkflows/local/utils_nfcore_nf-pediatric_pipeline'

// ** Prepare templates ** //
include { TEMPLATES                         } from '../subworkflows/local/templates/main.nf'

// ** Anatomical reconstruction ** //
include { SEGMENTATION                      } from '../subworkflows/local/segmentation/segmentation'

// ** Anatomical Preprocessing ** //
include { PREPROC_T1 as PREPROC_T1W         } from '../subworkflows/nf-neuro/preproc_t1/main'
include { PREPROC_T1 as PREPROC_T2W         } from '../subworkflows/nf-neuro/preproc_t1/main'
include { REGISTRATION_ANTS as COREG        } from '../modules/nf-neuro/registration/ants/main'

// ** DWI Preprocessing ** //
include { PREPROC_DWI                       } from '../subworkflows/nf-neuro/preproc_dwi/main'

// ** DTI Metrics ** //
include { RECONST_DTIMETRICS                } from '../modules/nf-neuro/reconst/dtimetrics/main'

// ** FRF ** //
include { RECONST_FRF                       } from '../modules/nf-neuro/reconst/frf/main'

// ** FODF Metrics ** //
include { RECONST_FODF                      } from '../modules/nf-neuro/reconst/fodf/main'

// ** Registration ** //
include { REGISTRATION_ANATTODWI as ANATTODWI } from '../modules/nf-neuro/registration/anattodwi/main'
include { REGISTRATION_TEMPLATETODWI as TEMPLATETODWI   } from '../modules/local/registration/templatetodwi/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as WARPPROBSEG     } from '../modules/nf-neuro/registration/antsapplytransforms/main'

// ** Anatomical Segmentation ** //
include { SEGMENTATION_FASTSEG as FASTSEG   } from '../modules/nf-neuro/segmentation/fastseg/main'
include { SEGMENTATION_TRACKINGMASKS as TRACKINGMASKS } from '../modules/local/segmentation/trackingmasks/main'

// ** Tracking ** //
include { TRACKING_PFTTRACKING              } from '../modules/nf-neuro/tracking/pfttracking/main'
include { TRACKING_LOCALTRACKING            } from '../modules/nf-neuro/tracking/localtracking/main'
include { TRACTOGRAM_MATH                   } from '../modules/nf-neuro/tractogram/math/main'

// ** BundleSeg ** //
include { BUNDLE_SEG } from '../subworkflows/local/bundleseg/main'
include { TRACTOMETRY } from '../subworkflows/nf-neuro/tractometry/main'

// ** Connectomics ** //
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_LABELS } from '../modules/nf-neuro/registration/antsapplytransforms/main'
include { FILTERING_COMMIT                  } from '../modules/local/filtering/commit.nf'
include { CONNECTIVITY_DECOMPOSE            } from '../modules/nf-neuro/connectivity/decompose/main'
include { CONNECTIVITY_AFDFIXEL             } from '../modules/nf-neuro/connectivity/afdfixel/main'
include { CONNECTIVITY_METRICS              } from '../modules/local/connectivity/metrics.nf'
include { CONNECTIVITY_VISUALIZE            } from '../modules/nf-neuro/connectivity/visualize/main'

// ** Output in template space ** //
include { OUTPUT_TEMPLATE_SPACE             } from '../subworkflows/nf-neuro/output_template_space/main'

// ** QC ** //
include { QC } from '../subworkflows/local/QC/qc.nf'
include { imNotification } from '../subworkflows/nf-core/utils_nfcore_pipeline/main.nf'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PEDIATRIC {

    take:
    ch_input_bids    // channel: from --input_bids

    main:

    // Empty channels to collect data during runtime
    ch_versions = Channel.empty()
    ch_multiqc_files_sub = Channel.empty()
    ch_multiqc_files_global = Channel.empty()
    ch_nifti_files_to_transform = Channel.empty()
    ch_rgb_files_to_transform = Channel.empty()
    ch_mask_files_to_transform = Channel.empty()
    ch_labels_files_to_transform = Channel.empty()
    ch_trk_files_to_transform = Channel.empty()

    // ** BIDS dataset_description file. ** //
    generateDatasetJson ()

    //
    // Fetching required templates
    //
    if ( params.tracking ) {
        TEMPLATES ( )
    }

    //
    // Decomposing the samplesheet into individual channels
    //
    ch_inputs = ch_input_bids
        .multiMap{ meta, t1, t2, dwi, bval, bvec, rev_dwi, rev_bval, rev_bvec, rev_b0 ->
            t1: [meta, t1]
            t2: [meta, t2]
            dwi_bval_bvec: [meta, dwi, bval, bvec]
            rev_b0: [meta, rev_b0]
            rev_dwi_bval_bvec: [meta, rev_dwi, rev_bval, rev_bvec]
        }

    // ** Check if T1 is provided ** //
    ch_t1 = ch_inputs.t1
        .branch {
            witht1: it.size() > 1 && it[1] != []
                return [ it[0], it[1] ]
        }
    ch_infant_t1 = ch_t1.witht1
        .branch {
            infant: it[0].age < 0.25 || it[0].age > 18
                return it
        }

    // ** Check if T2 is provided ** //
    ch_t2 = ch_inputs.t2
        .branch {
            witht2: it.size() > 1 && it[1] != []
                return [ it[0], it[1] ]
        }
    ch_infant_t2 = ch_t2.witht2
        .branch {
            infant: it[0].age < 0.25 || it[0].age > 18
                return it
        }

    // ** Loading synthstrip alternative weights if provided ** //
    ch_synthstrip_weights = Channel.fromPath("$projectDir/assets/synthstrip.infant.1.pt",
        checkIfExists: true)

    //
    // SUBWORKFLOW: Run preprocessing on anatomical images.
    //
    reg_t1 = Channel.empty()

    if ( params.tracking || params.segmentation ) {

        // ** Run T1 preprocessing ** //
        PREPROC_T1W (
            !params.tracking ? ch_infant_t1.infant : ch_t1.witht1,
            Channel.empty(),
            Channel.empty(),
            Channel.empty(),
            Channel.empty(),
            Channel.empty(),
            Channel.empty(),
            ch_synthstrip_weights
        )
        ch_versions = ch_versions.mix(PREPROC_T1W.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(PREPROC_T1.out.zip.collect{it[1]})

        // ** T2 Preprocessing ** //
        PREPROC_T2W (
            !params.tracking ? ch_infant_t2.infant : ch_t2.witht2,
            Channel.empty(),
            Channel.empty(),
            Channel.empty(),
            Channel.empty(),
            Channel.empty(),
            Channel.empty(),
            ch_synthstrip_weights
        )
        ch_versions = ch_versions.mix(PREPROC_T2W.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(PREPROC_T2.out.zip.collect{it[1]})

        // ** Register T1 to T2 if T1 is provided ** //
        ch_reg = PREPROC_T2W.out.t1_final
            .join(PREPROC_T1W.out.t1_final, remainder: true)
            .branch {
                witht1: (it[0].age < 2.5 || it[0].age > 18) && it.size() > 2 && it[2] != null
                witht2: (it[0].age >= 2.5 && it[0].age <= 18) && it.size() > 2 && it[1] != null
                other: true // Catch-all for any other cases
            }

        ch_coreg_input = ch_reg.witht1
            .filter { it.size() > 2 && it[1] != null && it[2] != null }
            .map { it -> [ it[0], it[1], it[2], [] ] }
            .mix(
                ch_reg.witht2
                    .filter { it.size() > 2 && it[1] != null && it[2] != null }
                    .map { it -> [ it[0], it[2], it[1], [] ] }
            )

        COREG ( ch_coreg_input )
        ch_versions = ch_versions.mix(COREG.out.versions)
        // ch_multiqc_files = ch_multiqc_files.mix(COREG.out.zip.collect{it[1]})
        reg_t1 = COREG.out.image ?: Channel.empty()

    }

    //
    // SUBWORKFLOW: Run FastSurfer, recon-all, or recon-all-clinical T1 reconstruction with BrainnetomeChild atlas
    // Additionally, if infant data is provided, run MCRIBS segmentation.
    //
    if ( params.segmentation ) {

        // ** Fetch license file ** //
        ch_fs_license = params.fs_license
            ? Channel.fromPath(params.fs_license, checkIfExists: true, followLinks: true)
            : Channel.empty().ifEmpty { error "No license file path provided. Please specify the path using --fs_license parameter." }

        // ** Fetch utils folder ** //
        ch_utils_folder = Channel.fromPath(params.utils_folder, checkIfExists: true)

        // ** Assemble T1w/T2w channels using derivatives for < 0.25 years, ** //
        // ** otherwise, raw images.                                        ** //
        ch_t1_seg = ch_t1.witht1
            .branch {
                fs: it[0].age >= 0.25 && it[0].age <= 18
                    return it
            }
        ch_t1_seg_proc = PREPROC_T1W.out.t1_final
            .branch {
                mcribs: it[0].age < 0.25 || it[0].age > 18
                    return it
            }
        ch_t1_seg = ch_t1_seg.fs.mix(ch_t1_seg_proc.mcribs)

        ch_t2_seg = ch_t2.witht2
            .branch {
                fs: it[0].age >= 0.25 && it[0].age <= 18
                    return it
            }
        ch_t2_seg_proc = PREPROC_T2W.out.t1_final
            .branch {
                mcribs: it[0].age < 0.25 || it[0].age > 18
                    return it
            }
        ch_t2_seg = ch_t2_seg.fs.mix(ch_t2_seg_proc.mcribs)

        SEGMENTATION (
            ch_t1_seg,
            ch_t2_seg,
            reg_t1,
            ch_fs_license,
            ch_utils_folder
        )

        ch_versions = ch_versions.mix(SEGMENTATION.out.versions)
        // ch_multiqc_files = ch_multiqc_files.mix(FASTSURFER.out.zip.collect{it[1]})

    }

    //
    // SUBWORKFLOW: Run PREPROC_DWI
    //
    if ( params.tracking ) {

        /* Load topup config if provided */
        if ( params.dwi_susceptibility_config_file ) {
            if ( file(params.dwi_susceptibility_config_file).exists() ) {
                ch_topup_config = Channel.fromPath(params.dwi_susceptibility_config_file, checkIfExists: true)
            }
            else {
                ch_topup_config = Channel.value( params.dwi_susceptibility_config_file )
            }
        }

        /* Run DWI preprocessing if the data isn't already preprocessed */
        /* else, just resample and crop the data                        */
        PREPROC_DWI(
            ch_inputs.dwi_bval_bvec,
            ch_inputs.rev_dwi_bval_bvec,
            Channel.empty(),
            ch_inputs.rev_b0,
            ch_topup_config,
            ch_synthstrip_weights
        )
        ch_versions = ch_versions.mix(PREPROC_DWI.out.versions)
        ch_multiqc_files_sub = ch_multiqc_files_sub.mix(PREPROC_DWI.out.mqc)

        //
        // MODULE: Run DTI_METRICS
        //
        ch_reconst_dti = PREPROC_DWI.out.dwi
            .join(PREPROC_DWI.out.bval)
            .join(PREPROC_DWI.out.bvec)
            .join(PREPROC_DWI.out.b0_mask)

        RECONST_DTIMETRICS ( ch_reconst_dti )
        ch_versions = ch_versions.mix(RECONST_DTIMETRICS.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(RECONST_DTIMETRICS.out.zip.collect{it[1]})
        ch_nifti_files_to_transform = ch_nifti_files_to_transform
            .mix(RECONST_DTIMETRICS.out.fa)
            .mix(RECONST_DTIMETRICS.out.md)
            .mix(RECONST_DTIMETRICS.out.ad)
            .mix(RECONST_DTIMETRICS.out.rd)
            .mix(RECONST_DTIMETRICS.out.ga)
            .mix(RECONST_DTIMETRICS.out.mode)
        ch_rgb_files_to_transform = ch_rgb_files_to_transform
            .mix(RECONST_DTIMETRICS.out.rgb)

        //
        // MODULE: Run FRF
        //
        ch_reconst_frf = PREPROC_DWI.out.dwi
            .join(PREPROC_DWI.out.bval)
            .join(PREPROC_DWI.out.bvec)
            .join(PREPROC_DWI.out.b0_mask)
            .map{ it + [[], [], []] }

        RECONST_FRF ( ch_reconst_frf )
        ch_versions = ch_versions.mix(RECONST_FRF.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(RECONST_FRF.out.zip.collect{it[1]})

        //
        // MODULE: Run MEANFRF
        //
        ch_reconst_fodf = PREPROC_DWI.out.dwi
            .join(PREPROC_DWI.out.bval)
            .join(PREPROC_DWI.out.bvec)
            .join(PREPROC_DWI.out.b0_mask)
            .join(RECONST_DTIMETRICS.out.fa)
            .join(RECONST_DTIMETRICS.out.md)
            .join(RECONST_FRF.out.frf)
            .map{ it + [[], []]}

        RECONST_FODF ( ch_reconst_fodf )
        ch_versions = ch_versions.mix(RECONST_FODF.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(RECONST_FODF.out.zip.collect{it[1]})
        ch_nifti_files_to_transform = ch_nifti_files_to_transform
            .mix(RECONST_FODF.out.afd_total)
            .mix(RECONST_FODF.out.nufo)
            .mix(RECONST_FODF.out.afd_max)
            .mix(RECONST_FODF.out.afd_sum)

        //
        // MODULE: Run REGISTRATION
        //
        ch_for_reg = PREPROC_DWI.out.b0
            .join(RECONST_DTIMETRICS.out.fa)
            .join(RECONST_DTIMETRICS.out.md)
            .join(PREPROC_T2W.out.t1_final, remainder: true)
            .join(PREPROC_T1W.out.t1_final, remainder: true)
            .branch{
                infant_t2: (it[0].age < 0.5 || it[0].age > 18) && it[4] != null
                    return [it[0], it[4], it[1], it[3]]
                infant_t1: (it[0].age < 0.5 || it[0].age > 18) && it[5] != null
                    return [it[0], it[5], it[1], it[2]]
                child_t1: (it[0].age >= 0.5 && it[0].age <= 18) && it[5] != null
                    return [it[0], it[5], it[1], it[2]]
                child_t2: (it[0].age >= 0.5 && it[0].age <= 18) && it[4] != null
                    return [it[0], it[4], it[1], it[3]]
            }

        ch_anat_reg = ch_for_reg.infant_t1
            .mix(ch_for_reg.infant_t2)
            .mix(ch_for_reg.child_t1)
            .mix(ch_for_reg.child_t2)

        ANATTODWI( ch_anat_reg )
        ch_versions = ch_versions.mix(ANATTODWI.out.versions)
        ch_multiqc_files_sub = ch_multiqc_files_sub.mix(ANATTODWI.out.mqc)

        //
        // ** For infant data (<2.5y), register the template in diff space using warped anat **
        // ** Matching the available anat with the same modality in the template **
        //
        ch_tpl0 = TEMPLATES.out.UNCBCPInfant0.map{ it[1..3] }
        ch_tpl3 = TEMPLATES.out.UNCBCPInfant3.map{ it[1..3] }
        ch_tpl6 = TEMPLATES.out.UNCBCPInfant6.map{ it[1..3] }
        ch_tpl12 = TEMPLATES.out.UNCBCPInfant12.map{ it[1..3] }
        ch_tpl24 = TEMPLATES.out.UNCBCPInfant24.map{ it[1..3] }

        ch_reg_template = ANATTODWI.out.t1_warped
            .join(RECONST_DTIMETRICS.out.fa)
            .combine(ch_tpl0)
            .combine(ch_tpl3)
            .combine(ch_tpl6)
            .combine(ch_tpl12)
            .combine(ch_tpl24)
            .branch{
                cohort0: it[0].age < 0.125 || it[0].age > 18 // age < 1.5 months
                    if (it[1].name.contains("T1w")) {
                        return [it[0], it[1], it[2], it[3], it[5]]
                    } else {
                        return [it[0], it[1], it[2], it[4], it[5]]
                    }
                cohort3: it[0].age >= 0.125 && it[0].age < 0.375 // 1.5 months <= age < 4.5 months
                    if (it[1].name.contains("T1w")) {
                        return [it[0], it[1], it[2], it[6], it[8]]
                    } else {
                        return [it[0], it[1], it[2], it[7], it[8]]
                    }
                cohort6: it[0].age >= 0.375 && it[0].age < 0.75 // 4.5 months <= age < 9 months
                    if (it[1].name.contains("T1w")) {
                        return [it[0], it[1], it[2], it[9], it[11]]
                    } else {
                        return [it[0], it[1], it[2], it[10], it[11]]
                    }
                cohort12: it[0].age >= 0.75 && it[0].age < 1.5 // 9 months <= age < 18 months
                    if (it[1].name.contains("T1w")) {
                        return [it[0], it[1], it[2], it[12], it[14]]
                    } else {
                        return [it[0], it[1], it[2], it[13], it[14]]
                    }
                cohort24: it[0].age >= 1.5 && it[0].age < 2.5 // 18 months <= age < 30 months
                    if (it[1].name.contains("T1w")) {
                        return [it[0], it[1], it[2], it[15], it[17]]
                    } else {
                        return [it[0], it[1], it[2], it[16], it[17]]
                    }
            }

        ch_reg_template = ch_reg_template.cohort0
            .mix(ch_reg_template.cohort3)
            .mix(ch_reg_template.cohort6)
            .mix(ch_reg_template.cohort12)
            .mix(ch_reg_template.cohort24)

        TEMPLATETODWI ( ch_reg_template )
        ch_versions = ch_versions.mix(TEMPLATETODWI.out.versions)
        ch_multiqc_files_sub = ch_multiqc_files_sub.mix(TEMPLATETODWI.out.mqc)

        //
        // ** Then, transform the probseg maps for WM, GM, and CSF. **
        //
        ch_probseg0 = TEMPLATES.out.UNCBCPInfant0.map{ [it[3..5]] }
        ch_probseg3 = TEMPLATES.out.UNCBCPInfant3.map{ [it[3..5]] }
        ch_probseg6 = TEMPLATES.out.UNCBCPInfant6.map{ [it[3..5]] }
        ch_probseg12 = TEMPLATES.out.UNCBCPInfant12.map{ [it[3..5]] }
        ch_probseg24 = TEMPLATES.out.UNCBCPInfant24.map{ [it[3..5]] }

        ch_warp_probseg = ANATTODWI.out.t1_warped
            .join(TEMPLATETODWI.out.warp)
            .join(TEMPLATETODWI.out.affine)
            .combine(ch_probseg0)
            .combine(ch_probseg3)
            .combine(ch_probseg6)
            .combine(ch_probseg12)
            .combine(ch_probseg24)
            .branch{
                cohort0: it[0].age < 0.125 || it[0].age > 18 // age < 1.5 months
                    return [it[0], it[4], it[1], it[2], it[3]]
                cohort3: it[0].age >= 0.125 && it[0].age < 0.375 // 1.5 months <= age < 4.5 months
                    return [it[0], it[5], it[1], it[2], it[3]]
                cohort6: it[0].age >= 0.375 && it[0].age < 0.75 // 4.5 months <= age < 9 months
                    return [it[0], it[6], it[1], it[2], it[3]]
                cohort12: it[0].age >= 0.75 && it[0].age < 1.5 // 9 months <= age < 18 months
                    return [it[0], it[7], it[1], it[2], it[3]]
                cohort24: it[0].age >= 1.5 && it[0].age < 2.5 // 18 months <= age < 30 months
                    return [it[0], it[8], it[1], it[2], it[3]]
            }
        ch_warp_probseg = ch_warp_probseg.cohort0
            .mix(ch_warp_probseg.cohort3)
            .mix(ch_warp_probseg.cohort6)
            .mix(ch_warp_probseg.cohort12)
            .mix(ch_warp_probseg.cohort24)

        // ** Transform atlas probability map into subject's space ** //
        WARPPROBSEG ( ch_warp_probseg )
        ch_versions = ch_versions.mix(WARPPROBSEG.out.versions)
        ch_nifti_files_to_transform = ch_nifti_files_to_transform
            .mix(WARPPROBSEG.out.warped_image.map{ [it[0], it[1][2], it[1][1], it[1][0]] })

        ch_tracking_masks = WARPPROBSEG.out.warped_image
            .map{ [it[0], it[1][2], it[1][1], it[1][0]] }
            .join(RECONST_DTIMETRICS.out.fa)
            .join(RECONST_DTIMETRICS.out.md)
            .join(PREPROC_DWI.out.b0_mask)

        // ** Convert probability segmentation into binary mask ** //
        TRACKINGMASKS ( ch_tracking_masks )
        ch_versions = ch_versions.mix(TRACKINGMASKS.out.versions)
        ch_mask_files_to_transform = ch_mask_files_to_transform
            .mix(TRACKINGMASKS.out.wm)
            .mix(TRACKINGMASKS.out.gm)
            .mix(TRACKINGMASKS.out.csf)

        // ** FAST segmentation for child data. ** //
        ch_fastseg = ANATTODWI.out.t1_warped
            .map { it + [[]] }
            .branch {
                child: it[0].age >= 2.5 && it[0].age <= 18
            }

        FASTSEG ( ch_fastseg.child )
        ch_versions = ch_versions.mix(FASTSEG.out.versions)
        // ch_multiqc_files = ch_multiqc_files.mix(ANATOMICAL_SEGMENTATION.out.zip.collect{it[1]})
        ch_nifti_files_to_transform = ch_nifti_files_to_transform
            .mix(FASTSEG.out.wm_map)
            .mix(FASTSEG.out.gm_map)
            .mix(FASTSEG.out.csf_map)
        ch_mask_files_to_transform = ch_mask_files_to_transform
            .mix(FASTSEG.out.wm_mask)
            .mix(FASTSEG.out.gm_mask)
            .mix(FASTSEG.out.csf_mask)

        // ** Setting channel for tracking ** //
        ch_pft_tracking = RECONST_FODF.out.fodf
            .join(RECONST_DTIMETRICS.out.fa)
            .join(FASTSEG.out.wm_map, remainder: true)
            .join(FASTSEG.out.gm_map, remainder: true)
            .join(FASTSEG.out.csf_map, remainder: true)
            .join(WARPPROBSEG.out.warped_image, remainder: true)
            .branch{
                infant: it[0].age < 2.5 || it[0].age > 18
                    return [it[0], it[6][2], it[6][1], it[6][0], it[1], it[2]]
                child: it[0].age >= 2.5 && it[0].age <= 18
                    return [it[0], it[3], it[4], it[5], it[1], it[2]]
            }
        ch_pft_tracking = ch_pft_tracking.infant.mix(ch_pft_tracking.child)

        ch_local_tracking = RECONST_FODF.out.fodf
            .join(RECONST_DTIMETRICS.out.fa)
            .join(FASTSEG.out.wm_mask, remainder: true)
            .join(TRACKINGMASKS.out.wm, remainder: true)
            .branch{
                infant: it[0].age < 2.5 || it[0].age > 18
                    return [it[0], it[4], it[1], it[2]]
                child: it[0].age >= 2.5 && it[0].age <= 18
                    return [it[0], it[3], it[1], it[2]]
            }
        ch_local_tracking = ch_local_tracking.infant.mix(ch_local_tracking.child)

        //
        // MODULE: Run PFT_TRACKING
        //
        ch_trk_pft = Channel.empty()
        if ( params.run_pft_tracking ) {

            TRACKING_PFTTRACKING ( ch_pft_tracking )
            ch_versions = ch_versions.mix(TRACKING_PFTTRACKING.out.versions.first())
            // ch_multiqc_files = ch_multiqc_files.mix(TRACKING_PFTTRACKING.out.zip.collect{it[1]})
            ch_trk_files_to_transform = ch_trk_files_to_transform
                .mix(TRACKING_PFTTRACKING.out.trk)

            ch_trk_pft = TRACKING_PFTTRACKING.out.trk
        }
        //
        // MODULE: Run LOCAL_TRACKING
        //
        ch_trk_local = Channel.empty()
        if ( params.run_local_tracking ) {

            TRACKING_LOCALTRACKING ( ch_local_tracking )
            ch_versions = ch_versions.mix(TRACKING_LOCALTRACKING.out.versions.first())
            // ch_multiqc_files = ch_multiqc_files.mix(TRACKING_LOCALTRACKING.out.zip.collect{it[1]})
            ch_trk_files_to_transform = ch_trk_files_to_transform
                .mix(TRACKING_LOCALTRACKING.out.trk)

            ch_trk_local = TRACKING_LOCALTRACKING.out.trk
        }

        //
        // MODULE : Run TRACTOGRAM_MATH
        //
        ch_concatenate = ch_trk_local
            .map{ meta, trk -> [meta, [trk], []] }
            .mix(
                ch_trk_pft.map { meta, trk -> [meta, [], [trk]] }
            )
            .groupTuple(by: 0)
            .map { meta, pft, local ->
                pft = pft.flatten()
                local = local.flatten()
                [meta, pft + local, []]
            }
            .branch {
                both: it[1].size() > 1
                    return it
            }

        ch_merged = Channel.empty()
        TRACTOGRAM_MATH ( ch_concatenate.both )
        ch_versions = ch_versions.mix(TRACTOGRAM_MATH.out.versions.first())
        ch_trk_files_to_transform = ch_trk_files_to_transform
            .mix(TRACTOGRAM_MATH.out.trk)
        ch_merged = ch_merged.mix(TRACTOGRAM_MATH.out.trk)

        // Setting output trk.
        ch_trk = ch_merged
            .mix(ch_trk_local)
            .mix(ch_trk_pft)
            .groupTuple(by: 0)
            .map { meta, trks ->
                def concat = trks.find { it.name?.contains('concatenated') }
                def individual = trks.find { ! it.name?.contains('concatenated') }
                [meta, concat ?: individual ]
            }
    }

    if ( params.bundling ) {

        // ** Fetch files from an input_deriv if tracking is not run ** //
        if ( ! params.tracking ) {
            FETCH_DERIVATIVES ( params.input_deriv )

            ch_fa = FETCH_DERIVATIVES.out.metrics
                .map { meta, files ->
                    def fa = files.findAll { it.name.contains('desc-fa.nii.gz') }

                    // ** Some logging if no files exists ** //
                    if ( fa.size() == 0 ) {
                        error "No FA file have been found in your derivatives folder. " +
                        "Please validate your structure respects the BIDS specification."
                    }
                    return [ meta, fa ]
                }

            ch_metrics = FETCH_DERIVATIVES.out.metrics

            ch_fodf = FETCH_DERIVATIVES.out.fodf

            ch_trk = FETCH_DERIVATIVES.out.trk
        } else {
            ch_fa = RECONST_DTIMETRICS.out.fa

            ch_metrics = RECONST_DTIMETRICS.out.fa
                .join(RECONST_DTIMETRICS.out.md)
                .join(RECONST_DTIMETRICS.out.ad)
                .join(RECONST_DTIMETRICS.out.rd)
                .join(RECONST_DTIMETRICS.out.mode)
                .join(RECONST_FODF.out.afd_total)
                .join(RECONST_FODF.out.nufo)
                .map{ meta, fa, md, ad, rd, mode, afd_total, nufo ->
                    tuple(meta, [ fa, md, ad, rd, mode, afd_total, nufo ])}

            ch_fodf = RECONST_FODF.out.fodf
        }

        //
        // SUBWORKFLOW: Run BUNDLE_SEG
        //
        BUNDLE_SEG(
            ch_fa,
            ch_trk
        )
        ch_versions = ch_versions.mix(BUNDLE_SEG.out.versions)

        //
        // SUBWORKFLOW: RUN TRACTOMETRY
        //
        TRACTOMETRY (
            BUNDLE_SEG.out.bundles,
            BUNDLE_SEG.out.centroids,
            ch_metrics,
            Channel.empty(),
            ch_fodf
        )
        ch_versions = ch_versions.mix(TRACTOMETRY.out.versions)

        //
        // MODULE: MERGE_TSV
        //
        ch_merged_mean_tsv = TRACTOMETRY.out.mean_std_tsv
            .map { _meta, stats -> stats }
            .collectFile(
                storeDir: "${params.outdir}/",
                name: "bundles_mean_stats.tsv",
                skip: 1,
                keepHeader: true
            )
        ch_merged_point_tsv = TRACTOMETRY.out.mean_std_per_point_tsv
            .map { _meta, stats -> stats }
            .collectFile(
                storeDir: "${params.outdir}/",
                name: "bundles_point_stats.tsv",
                skip: 1,
                keepHeader: true
            )
        ch_multiqc_files_global = ch_multiqc_files_global.mix(ch_merged_mean_tsv)
        ch_multiqc_files_global = ch_multiqc_files_global.mix(ch_merged_point_tsv)
    }

    if ( params.connectomics ) {

        if ( params.input_deriv ) {
            FETCH_DERIVATIVES ( params.input_deriv )
        }

        if ( params.tracking ) {

            ch_transforms = ANATTODWI.out.warp
                .join(ANATTODWI.out.affine)
            ch_peaks = RECONST_FODF.out.peaks
            ch_fodf = RECONST_FODF.out.fodf
            ch_dwi_bval_bvec = PREPROC_DWI.out.dwi
                .join(PREPROC_DWI.out.bval)
                .join(PREPROC_DWI.out.bvec)
            ch_anat = ANATTODWI.out.t1_warped
            ch_metrics = RECONST_DTIMETRICS.out.fa
                .join(RECONST_DTIMETRICS.out.md)
                .join(RECONST_DTIMETRICS.out.ad)
                .join(RECONST_DTIMETRICS.out.rd)
                .join(RECONST_DTIMETRICS.out.mode)
                .join(RECONST_FODF.out.afd_total)
                .join(RECONST_FODF.out.nufo)
                .map{ meta, fa, md, ad, rd, mode, afd_total, nufo ->
                    tuple(meta, [ fa, md, ad, rd, mode, afd_total, nufo ])}

        } else {

            FETCH_DERIVATIVES ( params.input_deriv )

            ch_trk = FETCH_DERIVATIVES.out.trk
            ch_transforms = FETCH_DERIVATIVES.out.transforms
            ch_peaks = FETCH_DERIVATIVES.out.peaks
            ch_fodf = FETCH_DERIVATIVES.out.fodf
            ch_dwi_bval_bvec = FETCH_DERIVATIVES.out.dwi_bval_bvec
            ch_anat = FETCH_DERIVATIVES.out.anat
            ch_metrics = FETCH_DERIVATIVES.out.metrics

        }

        if ( params.segmentation ) {

            ch_labels = SEGMENTATION.out.labels

        } else {

            ch_labels = FETCH_DERIVATIVES.out.labels

        }
        //
        // MODULE : Run AntsApplyTransforms.
        //
        ch_labels = ch_labels.branch {
            reg: it.size() > 2 && !params.segmentation
                return [it[0], it[2]]
            notreg: it.size() < 3
                return [it[0], it[1]]
        }

        ch_antsapply = ch_labels.notreg
            .join(ch_anat)
            .join(ch_transforms)

        TRANSFORM_LABELS ( ch_antsapply )
        ch_versions = ch_versions.mix(TRANSFORM_LABELS.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(TRANSFORM_LABELS.out.zip.collect{it[1]})
        ch_labels_files_to_transform = ch_labels_files_to_transform
            .mix(TRANSFORM_LABELS.out.warped_image)

        //
        // MODULE: Run DECOMPOSE.
        //
        ch_decompose = ch_trk
            .join(ch_labels.reg, remainder: true)
            .map { id, trk, reg_label ->
                reg_label ? [id, trk, reg_label] : [id, trk, null]
            }
            .join(TRANSFORM_LABELS.out.warped_image.map { id, warped -> [id, warped] }, remainder: true)
            .map { id, trk, reg_label, warped_label ->
                def label = reg_label ?: warped_label
                [id, trk, label]
            }
            .filter { it[2] != null }

        CONNECTIVITY_DECOMPOSE ( ch_decompose )
        ch_versions = ch_versions.mix(CONNECTIVITY_DECOMPOSE.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(TRACTOGRAM_DECOMPOSE.out.zip.collect{it[1]})

        //
        // MODULE: Run FILTERING_COMMIT
        //
        ch_commit = CONNECTIVITY_DECOMPOSE.out.hdf5
            .join(ch_dwi_bval_bvec)
            .join(ch_peaks)

        FILTERING_COMMIT ( ch_commit )
        ch_versions = ch_versions.mix(FILTERING_COMMIT.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(FILTERING_COMMIT.out.zip.collect{it[1]})
        ch_trk_files_to_transform = ch_trk_files_to_transform
            .mix(FILTERING_COMMIT.out.hdf5)

        //
        // MODULE: Run AFDFIXEL
        //
        ch_afdfixel = FILTERING_COMMIT.out.hdf5
            .join(ch_fodf)

        CONNECTIVITY_AFDFIXEL ( ch_afdfixel )
        ch_versions = ch_versions.mix(CONNECTIVITY_AFDFIXEL.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(CONNECTIVITY_AFDFIXEL.out.zip.collect{it[1]})
        ch_trk_files_to_transform = ch_trk_files_to_transform
            .mix(CONNECTIVITY_AFDFIXEL.out.hdf5)

        //
        // MODULE: Run CONNECTIVITY_METRICS
        //
        ch_metrics_conn = CONNECTIVITY_AFDFIXEL.out.hdf5
            .join(ch_labels.reg, remainder: true)
            .map { id, trk, reg_label ->
                reg_label ? [id, trk, reg_label] : [id, trk, null]
            }
            .join(TRANSFORM_LABELS.out.warped_image.map { id, warped -> [id, warped] }, remainder: true)
            .map { id, trk, reg_label, warped_label ->
                def label = reg_label ?: warped_label
                [id, trk, label]
            }
            .join(CONNECTIVITY_DECOMPOSE.out.labels_list)
            .join(ch_metrics)

        CONNECTIVITY_METRICS ( ch_metrics_conn )
        ch_versions = ch_versions.mix(CONNECTIVITY_METRICS.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(CONNECTIVITY_METRICS.out.zip.collect{it[1]})

        //
        // MODULE: Run CONNECTIVITY_VISUALIZE
        //
        ch_visualize = CONNECTIVITY_METRICS.out.metrics
            .join(CONNECTIVITY_DECOMPOSE.out.labels_list)
            .map{ meta, metrics, labels -> [meta, metrics, [], labels] }

        CONNECTIVITY_VISUALIZE ( ch_visualize )
        ch_versions = ch_versions.mix(CONNECTIVITY_VISUALIZE.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(CONNECTIVITY_VISUALIZE.out.zip.collect{it[1]})

        ch_labels_qc = ch_labels.reg
            .join(TRANSFORM_LABELS.out.warped_image.map { id, warped -> [id, warped] }, remainder: true)
            .map { id, reg_label, warped_label ->
                def label = reg_label ?: warped_label
                [id, label]
            }
    }

    //
    // SUBWORKFLOW: RUN OUTPUT_TEMPLATE_SPACE
    //
    if ( params.template ) {
        ch_nifti_files_to_transform = ch_nifti_files_to_transform
            .groupTuple()
            .map { tuple_elements ->
                def meta = tuple_elements[0]
                def file_lists = tuple_elements[1..-1] // Get all elements except the first (meta)
                def all_files = file_lists.flatten().findAll { it != null }
                return tuple(meta, all_files)
            }

        ch_rgb_files_to_transform = ch_rgb_files_to_transform
            .groupTuple()
            .map { tuple_elements ->
                def meta = tuple_elements[0]
                def file_lists = tuple_elements[1..-1] // Get all elements except the first (meta)
                def all_files = file_lists.flatten().findAll { it != null }
                return tuple(meta, all_files)
            }

        ch_mask_files_to_transform = ch_mask_files_to_transform
            .groupTuple()
            .map { tuple_elements ->
                def meta = tuple_elements[0]
                def file_lists = tuple_elements[1..-1] // Get all elements except the first (meta)
                def all_files = file_lists.flatten().findAll { it != null }
                return tuple(meta, all_files)
            }

        ch_labels_files_to_transform = ch_labels_files_to_transform
            .groupTuple()
            .map { tuple_elements ->
                def meta = tuple_elements[0]
                def file_lists = tuple_elements[1..-1] // Get all elements except the first (meta)
                def all_files = file_lists.flatten().findAll { it != null }
                return tuple(meta, all_files)
            }

        ch_trk_files_to_transform = ch_trk_files_to_transform
            .groupTuple()
            .map { tuple_elements ->
                def meta = tuple_elements[0]
                def file_lists = tuple_elements[1..-1] // Get all elements except the first (meta)
                def all_files = file_lists.flatten().findAll { it != null }
                return tuple(meta, all_files)
            }

        OUTPUT_TEMPLATE_SPACE(
            ANATTODWI.out.t1_warped,
            ch_nifti_files_to_transform,
            ch_rgb_files_to_transform,
            ch_mask_files_to_transform,
            ch_labels_files_to_transform,
            ch_trk_files_to_transform
        )
        ch_versions = ch_versions.mix(OUTPUT_TEMPLATE_SPACE.out.versions)
    }

    //
    // SUBWORKFLOW: RUN QC
    //
    if ( params.tracking ) {
    ch_tissueseg = Channel.empty()
        .mix(FASTSEG.out.wm_mask)
        .mix(FASTSEG.out.gm_mask)
        .mix(FASTSEG.out.csf_mask)
        .mix(TRACKINGMASKS.out.wm)
        .mix(TRACKINGMASKS.out.gm)
        .mix(TRACKINGMASKS.out.csf)
        .groupTuple()
        .map { meta, files ->
            def sortedFiles = files.flatten().findAll { it != null }.sort { file ->
                if (file.name.contains('wm')) return 0
                else if (file.name.contains('gm')) return 1
                else if (file.name.contains('csf')) return 2
                else return 3
            }
            return [meta] + sortedFiles
        }
    } else {
        ch_tissueseg = Channel.empty()
    }

    if ( params.tracking ) {
        ch_anat_qc = ANATTODWI.out.t1_warped
    } else if ( params.segmentation && !params.connectomics ) {
        // ** Fetching the T1w and T2w images for QC ** //
        // ** If both are provided, use T1w, else, use T2w. ** //
        ch_anat_qc = Channel.empty()
            .mix(SEGMENTATION.out.t1)
            .mix(SEGMENTATION.out.t2)
            .groupTuple()
            .map { meta, files ->
                return [meta] + files.flatten().findAll { it != null }.sort { file ->
                    if (file.name.contains("T2w")) return 0
                    else return 1}
            }
            .branch{
                T1w: it.size() > 3 && it[0].age >= 0.25 && it[0].age <= 18
                    return [it[0], it[2]]
                T2w: true // Catch-all for only T2w.
                    return [it[0], it[1]]
            }
        ch_anat_qc = ch_anat_qc.T1w.mix(ch_anat_qc.T2w)
    } else if ( params.bundling ) {
        ch_anat_qc = Channel.empty()
    } else {
        ch_anat_qc = ch_anat
    }

    QC (
        ch_anat_qc,
        ch_tissueseg,
        params.connectomics ? ch_labels_qc : params.segmentation ? SEGMENTATION.out.labels : Channel.empty(),
        params.connectomics ? FILTERING_COMMIT.out.trk : params.tracking ? ch_trk : Channel.empty(),
        params.tracking ? ch_inputs.dwi_bval_bvec : params.connectomics ? ch_dwi_bval_bvec : Channel.empty(),
        params.tracking ? RECONST_DTIMETRICS.out.fa : Channel.empty(),
        params.tracking ? RECONST_DTIMETRICS.out.md : Channel.empty(),
        params.tracking ? RECONST_FODF.out.nufo : Channel.empty(),
        params.tracking ? RECONST_DTIMETRICS.out.rgb : Channel.empty()
    )

    qc_files = ch_multiqc_files_sub
        .mix(QC.out.tissueseg_png)
        .mix(QC.out.tracking_png)
        .mix(QC.out.shell_png)
        .mix(QC.out.metrics_png)
        .mix(QC.out.labels_png)
        .groupTuple()
        .map { meta, png_list ->
            def images = png_list.flatten().findAll { it != null }
            return tuple(meta, images)
        }

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'nf-pediatric_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = Channel.empty()  // To store versions, methods description, etc.
                                        // Otherwise, stored in either subject or global level channel.

    ch_multiqc_config_subject = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_config_global = Channel.fromPath(
        "$projectDir/assets/multiqc_config_global.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.fromPath("$projectDir/assets/nf-pediatric-light-logo.png", checkIfExists: true)

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    MULTIQC_SUBJECT (
        qc_files,
        ch_multiqc_files.collect(),
        ch_multiqc_config_subject.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    ch_multiqc_files_global = ch_multiqc_files_global.mix(
        ch_multiqc_files.mix(QC.out.dice_stats.map{ it[1] }.flatten())
    )
    ch_multiqc_files_global = ch_multiqc_files_global.mix(QC.out.sc_values.map{ it[1] }.flatten())
    if ( params.segmentation ) {
        ch_multiqc_files_global = ch_multiqc_files_global.mix(SEGMENTATION.out.volume_lh)
        ch_multiqc_files_global = ch_multiqc_files_global.mix(SEGMENTATION.out.volume_rh)
        ch_multiqc_files_global = ch_multiqc_files_global.mix(SEGMENTATION.out.area_lh)
        ch_multiqc_files_global = ch_multiqc_files_global.mix(SEGMENTATION.out.area_rh)
        ch_multiqc_files_global = ch_multiqc_files_global.mix(SEGMENTATION.out.thickness_lh)
        ch_multiqc_files_global = ch_multiqc_files_global.mix(SEGMENTATION.out.thickness_rh)
        ch_multiqc_files_global = ch_multiqc_files_global.mix(SEGMENTATION.out.subcortical)
    }

    // Collect the framewise displacement files from the ch_multiqc_files_sub channel
    ch_fd_files = ch_multiqc_files_sub
        .filter { _meta, files ->
            files.any { it.name.contains("dwi_eddy_restricted_movement_rms") }
        }
        .map { it[1] }
    ch_multiqc_files_global = ch_multiqc_files_global.mix(ch_fd_files.flatten())

    MULTIQC_GLOBAL (
        Channel.of([meta:[id:"global"], qc_images:[]]),
        ch_multiqc_files_global.collect(),
        ch_multiqc_config_global.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:
    multiqc_report = MULTIQC_SUBJECT.out.report.toList()    // channel: /path/to/multiqc_report.html
    versions       = ch_versions                            // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
