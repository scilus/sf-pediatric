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
include { methodsDescriptionText            } from '../subworkflows/local/utils_nfcore_sf_pediatric_pipeline'
include { FETCH_DERIVATIVES                 } from '../subworkflows/local/utils/fetch_derivatives.nf'
include { generateDatasetJson               } from '../subworkflows/local/utils_nfcore_sf_pediatric_pipeline'

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

// ** Freewater / NODDI ** //
include { RECONST_FW_NODDI                  } from '../subworkflows/nf-neuro/reconst_fw_noddi/main'

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

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SF_PEDIATRIC {

    take:
    ch_input_bids    // channel: from --input_bids

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files_sub = channel.empty()
    def ch_multiqc_files_global = channel.empty()
    def ch_nifti_files_to_transform = channel.empty()
    def ch_rgb_files_to_transform = channel.empty()
    def ch_mask_files_to_transform = channel.empty()
    def ch_labels_files_to_transform = channel.empty()
    def ch_trk_files_to_transform = channel.empty()

    // ** BIDS dataset_description file. ** //
    generateDatasetJson ()

    //
    // Fetching required templates
    //
    TEMPLATES ( )

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

    // Check if any T1w or T2w images are provided
    ch_t1 = ch_inputs.t1
        .filter { _meta, t1 -> t1 != null && (!(t1 instanceof List) || !t1.isEmpty()) }
        .map { meta, t1 -> [meta, t1] }

    ch_t2 = ch_inputs.t2
        .filter { _meta, t2 -> t2 != null && (!(t2 instanceof List) || !t2.isEmpty()) }
        .map { meta, t2 -> [meta, t2] }

    // Create specific channel for infant subjects, useful for segmentation subworkflow
    ch_infant_t1 = ch_t1.filter { meta, _t1 -> meta.age < 0.25 || meta.age > 18 }
    ch_infant_t2 = ch_t2.filter { meta, _t2 -> meta.age < 0.25 || meta.age > 18 }

    // Fetch infant synthstrip weights
    ch_synthstrip_weights_infant = channel.fromPath(
        "$projectDir/assets/synthstrip.infant.1.pt",
        checkIfExists: true
    )

    // Condition representing which channel to pass to PREPROC T1w/T2w depending
    // on selected profiles
    ch_t1_input = !params.tracking ? ch_infant_t1 : ch_t1
    ch_t2_input = !params.tracking ? ch_infant_t2 : ch_t2

    // Create per subject channels for synthstrip weights to ensure infant weights
    // are matched with infant subjects, else, use default weights (automatically handled in module)
    ch_t1_sample_weights = ch_t1_input
        .combine(ch_synthstrip_weights_infant)
        .map { item ->
            def tuple = (item instanceof List) ? item : [item]
            def meta = (tuple[0] instanceof List) ? tuple[0][0] : tuple[0]
            def weight = tuple[-1]
            [meta, (meta.age < 2.5 || meta.age > 18) ? weight : []]
        }

    ch_t2_sample_weights = ch_t2_input
        .combine(ch_synthstrip_weights_infant)
        .map { item ->
            def tuple = (item instanceof List) ? item : [item]
            def meta = (tuple[0] instanceof List) ? tuple[0][0] : tuple[0]
            def weight = tuple[-1]
            [meta, (meta.age < 2.5 || meta.age > 18) ? weight : []]
        }

    ch_dwi_sample_weights = ch_inputs.dwi_bval_bvec
        .combine(ch_synthstrip_weights_infant)
        .map { item ->
            def tuple = (item instanceof List) ? item : [item]
            def meta = (tuple[0] instanceof List) ? tuple[0][0] : tuple[0]
            def weight = tuple[-1]
            [meta, (meta.age < 2.5 || meta.age > 18) ? weight : []]
        }

    //
    // SUBWORKFLOW: Run preprocessing on anatomical images.
    //
    reg_t1 = channel.empty()

    if ( params.tracking || params.segmentation ) {

        // ** Run T1 preprocessing ** //
        PREPROC_T1W (
            ch_t1_input,
            channel.empty(),
            channel.empty(),
            channel.empty(),
            channel.empty(),
            channel.empty(),
            channel.empty(),
            ch_t1_sample_weights,
            [
                "preproc_t1_run_denoising": params.run_t1_denoising,
                "preproc_t1_run_N4": params.run_t1_n4,
                "preproc_t1_run_resampling": params.run_t1_resampling,
                "preproc_t1_run_synthstrip": true,
                "preproc_t1_run_ants_bet": false,
                "preproc_t1_run_crop": params.run_t1_crop
            ]
        )
        ch_versions = ch_versions.mix(PREPROC_T1W.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(PREPROC_T1.out.zip.collect{it[1]})

        // ** T2 Preprocessing ** //
        PREPROC_T2W (
            ch_t2_input,
            channel.empty(),
            channel.empty(),
            channel.empty(),
            channel.empty(),
            channel.empty(),
            channel.empty(),
            ch_t2_sample_weights,
            [
                "preproc_t1_run_denoising": params.run_t2_denoising,
                "preproc_t1_run_N4": params.run_t2_n4,
                "preproc_t1_run_resampling": params.run_t2_resampling,
                "preproc_t1_run_synthstrip": true,
                "preproc_t1_run_ants_bet": false,
                "preproc_t1_run_crop": params.run_t2_crop
            ]
        )
        ch_versions = ch_versions.mix(PREPROC_T2W.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(PREPROC_T2.out.zip.collect{it[1]})

        // ** Register T1 to T2 if T1 is provided ** //
        ch_reg = PREPROC_T2W.out.t1_final
            .join(PREPROC_T1W.out.t1_final, remainder: true)
            .branch { tuple ->
                witht1: (tuple[0].age < 2.5 || tuple[0].age > 18) && tuple.size() > 2 && tuple[2] != null
                witht2: (tuple[0].age >= 2.5 && tuple[0].age <= 18) && tuple.size() > 2 && tuple[1] != null
                other: true // Catch-all for any other cases
            }

        ch_coreg_input = ch_reg.witht1
            .filter { tuple -> tuple.size() > 2 && tuple[1] != null && tuple[2] != null }
            .map { tuple -> [ tuple[0], tuple[1], tuple[2], [] ] }
            .mix(
                ch_reg.witht2
                    .filter { tuple -> tuple.size() > 2 && tuple[1] != null && tuple[2] != null }
                    .map { tuple -> [ tuple[0], tuple[2], tuple[1], [] ] }
            )

        COREG ( ch_coreg_input )
        ch_versions = ch_versions.mix(COREG.out.versions)
        // ch_multiqc_files = ch_multiqc_files.mix(COREG.out.zip.collect{it[1]})
        reg_t1 = COREG.out.image_warped ?: channel.empty()

    }

    //
    // SUBWORKFLOW: Run FastSurfer, recon-all, or recon-all-clinical T1 reconstruction with BrainnetomeChild atlas
    // Additionally, if infant data is provided, run MCRIBS segmentation.
    //
    if ( params.segmentation ) {

        // ** Fetch license file ** //
        ch_fs_license = params.fs_license
            ? channel.fromPath(params.fs_license, checkIfExists: true, followLinks: true)
            : channel.empty().ifEmpty { error "No license file path provided. Please specify the path using --fs_license parameter." }

        // ** Assemble T1w/T2w channels using derivatives for < 0.25 years, ** //
        // ** otherwise, raw images.                                        ** //
        ch_t1_seg = ch_t1
            .branch { tuple ->
                fs: tuple[0].age >= 0.25 && tuple[0].age <= 18
                    return tuple
            }
        ch_t1_seg_proc = PREPROC_T1W.out.t1_final
            .branch { tuple ->
                mcribs: tuple[0].age < 0.25 || tuple[0].age > 18
                    return tuple
            }
        ch_t1_seg = ch_t1_seg.fs.mix(ch_t1_seg_proc.mcribs)

        ch_t2_seg = ch_t2
            .branch { tuple ->
                fs: tuple[0].age >= 0.25 && tuple[0].age <= 18
                    return tuple
            }
        ch_t2_seg_proc = PREPROC_T2W.out.t1_final
            .branch { tuple ->
                mcribs: tuple[0].age < 0.25 || tuple[0].age > 18
                    return tuple
            }
        ch_t2_seg = ch_t2_seg.fs.mix(ch_t2_seg_proc.mcribs)

        // ** Set up the intermediate template based on the subject's age **
        ch_tpl0 = TEMPLATES.out.UNCBCPInfant0.map{ tuple -> tuple[1..2, 6] }
        ch_tpl3 = TEMPLATES.out.UNCBCPInfant3.map{ tuple -> tuple[1..2, 6] }
        ch_tpl6 = TEMPLATES.out.UNCBCPInfant6.map{ tuple -> tuple[1..2, 6] }
        ch_tpl12 = TEMPLATES.out.UNCBCPInfant12.map{ tuple -> tuple[1..2, 6] }
        ch_tpl24 = TEMPLATES.out.UNCBCPInfant24.map{ tuple -> tuple[1..2, 6] }

        ch_intermediate_template = ch_t1_seg
            .join(ch_t2_seg, remainder: true)
            .combine(ch_tpl0)
            .combine(ch_tpl3)
            .combine(ch_tpl6)
            .combine(ch_tpl12)
            .combine(ch_tpl24)
            .branch { tuple ->
                infant0: tuple[0].age < 0.125 || tuple[0].age > 18
                    // Assess wether a t1 or a t2 is available, and select the appropriate template accordingly
                    if ( tuple[2] != null && tuple[2] != [] ) {
                        return [tuple[0], tuple[4], tuple[5]]
                    } else {
                        return [tuple[0], tuple[3], tuple[5]]
                    }
                infant3_1: tuple[0].age >= 0.125 && tuple[0].age < 0.25
                    if ( tuple[2] != null && tuple[2] != [] ) {
                        return [tuple[0], tuple[7], tuple[8]]
                    } else {
                        return [tuple[0], tuple[6], tuple[8]]
                    }
                infant3_2: tuple[0].age >= 0.25 && tuple[0].age < 0.375
                    if ( tuple[1] != null && tuple[1] != [] ) {
                        return [tuple[0], tuple[6], tuple[8]]
                    } else {
                        return [tuple[0], tuple[7], tuple[8]]
                    }
                infant6: tuple[0].age >= 0.375 && tuple[0].age < 0.625
                    if ( tuple[1] != null && tuple[1] != [] ) {
                        return [tuple[0], tuple[9], tuple[11]]
                    } else {
                        return [tuple[0], tuple[10], tuple[11]]
                    }
                infant12: tuple[0].age >= 0.625 && tuple[0].age < 1.5
                    if ( tuple[1] != null && tuple[1] != [] ) {
                        return [tuple[0], tuple[12], tuple[14]]
                    } else {
                        return [tuple[0], tuple[13], tuple[14]]
                    }
                infant24: tuple[0].age >= 1.5 && tuple[0].age < 2.5
                    if ( tuple[1] != null && tuple[1] != [] ) {
                        return [tuple[0], tuple[15], tuple[17]]
                    } else {
                        return [tuple[0], tuple[16], tuple[17]]
                    }
                other: true
                    return [tuple[0], [], []]
            }


        SEGMENTATION (
            ch_t1_seg,
            ch_t2_seg,
            reg_t1,
            channel.fromPath("${params.atlas_folder}/${params.atlas_name}", checkIfExists: true),
            ch_fs_license,
            channel.fromPath("$params.templates_download_path/templates/tpl-fsLR/tpl-MNI152NLin6Asym_res-01_desc-brain_T1w.nii.gz", checkIfExists: true),
            ch_intermediate_template.infant0
                .mix(ch_intermediate_template.infant3_1)
                .mix(ch_intermediate_template.infant3_2)
                .mix(ch_intermediate_template.infant6)
                .mix(ch_intermediate_template.infant12)
                .mix(ch_intermediate_template.infant24)
                .mix(ch_intermediate_template.other),
            channel.fromPath("$params.templates_download_path/templates/tpl-fsLR", checkIfExists: true),
            channel.fromPath("$params.templates_download_path/templates/fsaverage", checkIfExists: true),
            channel.fromPath("$params.templates_download_path/templates/fsaverage_alt", checkIfExists: true)
        )
        ch_versions = ch_versions.mix(SEGMENTATION.out.versions)

        // Collate all segmentation tsv files and output them.
        // We need to filter files to collate based on metric and hemisphere
        // Iterate over the expected metrics and hemispheres, and collate files matching those patterns
        ch_merged_tsvs = SEGMENTATION.out.tsv
            .map { _meta, tsvs -> tsvs }
            .flatten()
            .collectFile(
                storeDir: "${params.outdir}/",
                keepHeader: true,
                skip: 1
            ) { tsv ->
                def match = (tsv.name =~ /(volume|thickness|area)_(lh|rh|subcortical)/)[0][0]
                def lines = tsv.text.readLines()
                def header = lines[0].split('\t')
                def body = lines.size() > 1 ? lines[1..-1] : []

                // Find columns to keep (not containing "???")
                def keepIdx = header.indices.findAll { i -> !header[i].contains('???') }
                def expectedCols = keepIdx.size()

                // Rename first column to "sample", filter columns
                def newHeader = keepIdx.collect { i ->
                    i == 0 ? 'sample' : header[i]
                }.join('\t')

                def newBody = body.collect { line ->
                    def cols = line.split('\t', -1)
                    // Validate column count before filtering
                    assert cols.size() == header.size() : log.warn("Column mismatch in ${tsv.name}: " +
                        "expected ${header.size()} columns, found ${cols.size()}. One subject might have " +
                        "missing cortical/subcortical ROIs.")
                    keepIdx.collect { i -> cols[i] }.join('\t')
                }.join('\n')

                def content = newHeader + '\n' + (newBody ? newBody + '\n' : '')
                ["${params.atlas_name}_${match}_stats.tsv", content]
            }
        ch_multiqc_files_global = ch_multiqc_files_global.mix(ch_merged_tsvs)
            .mix(SEGMENTATION.out.dseg_tsv.first().map { tuple -> tuple[1]  })
    }

    //
    // SUBWORKFLOW: Run PREPROC_DWI
    //
    if ( params.tracking ) {

        /* Load topup config if provided */
        if ( params.dwi_susceptibility_config_file ) {
            if ( file(params.dwi_susceptibility_config_file).exists() ) {
                ch_topup_config = channel.fromPath(params.dwi_susceptibility_config_file, checkIfExists: true)
            }
            else {
                ch_topup_config = channel.value( params.dwi_susceptibility_config_file )
            }
        }

        PREPROC_DWI(
            ch_inputs.dwi_bval_bvec,
            ch_inputs.rev_dwi_bval_bvec.filter {
                _meta, dwi, _bval, _bvec -> dwi != []
             },
            channel.empty(),
            ch_inputs.rev_b0,
            ch_dwi_sample_weights,
            ch_topup_config,
            [
                "preproc_dwi_run_denoising": params.run_dwi_denoising,
                "preproc_dwi_run_degibbs": params.run_dwi_degibbs,
                "topup_eddy_run_topup": params.run_dwi_topup,
                "topup_eddy_run_eddy": params.run_dwi_eddy,
                "eddy_nan_threshold": 1,
                "preproc_dwi_run_synthstrip": true,
                "preproc_dwi_keep_dwi_with_skull": false,
                "preproc_dwi_run_N4": params.run_dwi_n4,
                "preproc_dwi_run_normalize": params.run_dwi_normalize,
                "preproc_dwi_run_resampling": params.run_dwi_resampling
            ]
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
            .map{ tuple -> tuple + [[], [], []] }

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
            .map{ tuple -> tuple + [[], []]}

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
            .branch{ tuple ->
                infant_t2: (tuple[0].age < 0.5 || tuple[0].age > 18) && tuple[4] != null
                    return [tuple[0], tuple[1], tuple[4], tuple[3]]
                infant_t1: (tuple[0].age < 0.5 || tuple[0].age > 18) && tuple[5] != null
                    return [tuple[0], tuple[1], tuple[5], tuple[2]]
                child_t1: (tuple[0].age >= 0.5 && tuple[0].age <= 18) && tuple[5] != null
                    return [tuple[0], tuple[1], tuple[5], tuple[2]]
                child_t2: (tuple[0].age >= 0.5 && tuple[0].age <= 18) && tuple[4] != null
                    return [tuple[0], tuple[1], tuple[4], tuple[3]]
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
        ch_tpl0 = TEMPLATES.out.UNCBCPInfant0.map{ tuple -> tuple[1..3] }
        ch_tpl3 = TEMPLATES.out.UNCBCPInfant3.map{ tuple -> tuple[1..3] }
        ch_tpl6 = TEMPLATES.out.UNCBCPInfant6.map{ tuple -> tuple[1..3] }
        ch_tpl12 = TEMPLATES.out.UNCBCPInfant12.map{ tuple -> tuple[1..3] }
        ch_tpl24 = TEMPLATES.out.UNCBCPInfant24.map{ tuple -> tuple[1..3] }

        ch_reg_template = ANATTODWI.out.anat_warped
            .join(RECONST_DTIMETRICS.out.fa)
            .combine(ch_tpl0)
            .combine(ch_tpl3)
            .combine(ch_tpl6)
            .combine(ch_tpl12)
            .combine(ch_tpl24)
            .branch{ tuple ->
                cohort0: tuple[0].age < 0.125 || tuple[0].age > 18 // age < 1.5 months
                    if (tuple[1].name.contains("T1w")) {
                        return [tuple[0], tuple[1], tuple[2], tuple[3], tuple[5]]
                    } else {
                        return [tuple[0], tuple[1], tuple[2], tuple[4], tuple[5]]
                    }
                cohort3: tuple[0].age >= 0.125 && tuple[0].age < 0.375 // 1.5 months <= age < 4.5 months
                    if (tuple[1].name.contains("T1w")) {
                        return [tuple[0], tuple[1], tuple[2], tuple[6], tuple[8]]
                    } else {
                        return [tuple[0], tuple[1], tuple[2], tuple[7], tuple[8]]
                    }
                cohort6: tuple[0].age >= 0.375 && tuple[0].age < 0.75 // 4.5 months <= age < 9 months
                    if (tuple[1].name.contains("T1w")) {
                        return [tuple[0], tuple[1], tuple[2], tuple[9], tuple[11]]
                    } else {
                        return [tuple[0], tuple[1], tuple[2], tuple[10], tuple[11]]
                    }
                cohort12: tuple[0].age >= 0.75 && tuple[0].age < 1.5 // 9 months <= age < 18 months
                    if (tuple[1].name.contains("T1w")) {
                        return [tuple[0], tuple[1], tuple[2], tuple[12], tuple[14]]
                    } else {
                        return [tuple[0], tuple[1], tuple[2], tuple[13], tuple[14]]
                    }
                cohort24: tuple[0].age >= 1.5 && tuple[0].age < 2.5 // 18 months <= age < 30 months
                    if (tuple[1].name.contains("T1w")) {
                        return [tuple[0], tuple[1], tuple[2], tuple[15], tuple[17]]
                    } else {
                        return [tuple[0], tuple[1], tuple[2], tuple[16], tuple[17]]
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
        ch_probseg0 = TEMPLATES.out.UNCBCPInfant0.map{ tuple -> [tuple[3..5]] }
        ch_probseg3 = TEMPLATES.out.UNCBCPInfant3.map{ tuple -> [tuple[3..5]] }
        ch_probseg6 = TEMPLATES.out.UNCBCPInfant6.map{ tuple -> [tuple[3..5]] }
        ch_probseg12 = TEMPLATES.out.UNCBCPInfant12.map{ tuple -> [tuple[3..5]] }
        ch_probseg24 = TEMPLATES.out.UNCBCPInfant24.map{ tuple -> [tuple[3..5]] }

        ch_warp_probseg = ANATTODWI.out.anat_warped
            .join(TEMPLATETODWI.out.warp)
            .join(TEMPLATETODWI.out.affine)
            .combine(ch_probseg0)
            .combine(ch_probseg3)
            .combine(ch_probseg6)
            .combine(ch_probseg12)
            .combine(ch_probseg24)
            .branch{ tuple ->
                cohort0: tuple[0].age < 0.125 || tuple[0].age > 18 // age < 1.5 months
                    return [tuple[0], tuple[4], tuple[1], [tuple[2], tuple[3]]]
                cohort3: tuple[0].age >= 0.125 && tuple[0].age < 0.375 // 1.5 months <= age < 4.5 months
                    return [tuple[0], tuple[5], tuple[1], [tuple[2], tuple[3]]]
                cohort6: tuple[0].age >= 0.375 && tuple[0].age < 0.75 // 4.5 months <= age < 9 months
                    return [tuple[0], tuple[6], tuple[1], [tuple[2], tuple[3]]]
                cohort12: tuple[0].age >= 0.75 && tuple[0].age < 1.5 // 9 months <= age < 18 months
                    return [tuple[0], tuple[7], tuple[1], [tuple[2], tuple[3]]]
                cohort24: tuple[0].age >= 1.5 && tuple[0].age < 2.5 // 18 months <= age < 30 months
                    return [tuple[0], tuple[8], tuple[1], [tuple[2], tuple[3]]]
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
            .mix(WARPPROBSEG.out.warped_image.map{ tuple -> [tuple[0], tuple[1][2], tuple[1][1], tuple[1][0]] })

        ch_tracking_masks = WARPPROBSEG.out.warped_image
            .map{ tuple -> [tuple[0], tuple[1][2], tuple[1][1], tuple[1][0]] }
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
        ch_fastseg = ANATTODWI.out.anat_warped
            .map { tuple -> tuple + [[]] }
            .branch { tuple ->
                child: tuple[0].age >= 2.5 && tuple[0].age <= 18
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
            .branch{ tuple ->
                infant: tuple[0].age < 2.5 || tuple[0].age > 18
                    return [tuple[0], tuple[6][2], tuple[6][1], tuple[6][0], tuple[1], tuple[2]]
                child: tuple[0].age >= 2.5 && tuple[0].age <= 18
                    return [tuple[0], tuple[3], tuple[4], tuple[5], tuple[1], tuple[2]]
            }
        ch_pft_tracking = ch_pft_tracking.infant.mix(ch_pft_tracking.child)

        ch_local_tracking = RECONST_FODF.out.fodf
            .join(RECONST_DTIMETRICS.out.fa)
            .join(FASTSEG.out.wm_mask, remainder: true)
            .join(TRACKINGMASKS.out.wm, remainder: true)
            .branch{ tuple ->
                infant: tuple[0].age < 2.5 || tuple[0].age > 18
                    return [tuple[0], tuple[4], tuple[1], tuple[2]]
                child: tuple[0].age >= 2.5 && tuple[0].age <= 18
                    return [tuple[0], tuple[3], tuple[1], tuple[2]]
            }
        ch_local_tracking = ch_local_tracking.infant.mix(ch_local_tracking.child)

        //
        // MODULE: Run PFT_TRACKING
        //
        ch_trk_pft = channel.empty()
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
        ch_trk_local = channel.empty()
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
            .branch { tuple ->
                both: tuple[1].size() > 1
                    return tuple
            }

        ch_merged = channel.empty()
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
                def concat = trks.find { trk -> trk.name?.contains('concatenated') }
                def individual = trks.find { trk -> !trk.name?.contains('concatenated') }
                [meta, concat ?: individual ]
            }
    }

    // ** Setting channels for downstream analyses (this avoids code duplication) ** //
    // ** We need a few stuff for either NODDI/FW, Bundleseg or connectomics ** //
    if ( !params.tracking && (params.run_noddi || params.run_freewater || params.connectomics || params.bundling) ) {
        FETCH_DERIVATIVES ( params.input_deriv )

        ch_metrics = FETCH_DERIVATIVES.out.metrics
        ch_fa_ad_rd_md = FETCH_DERIVATIVES.out.metrics
            .map { meta, files ->
                def fa = files.findAll { file -> file.name.contains('param-fa_dwimap.nii.gz') }
                def ad = files.findAll { file -> file.name.contains('param-ad_dwimap.nii.gz') }
                def rd = files.findAll { file -> file.name.contains('param-rd_dwimap.nii.gz') }
                def md = files.findAll { file -> file.name.contains('param-md_dwimap.nii.gz') }

                // ** Some logging if no files exists ** //
                if ( fa.size() == 0 || ad.size() == 0 || rd.size() == 0 || md.size() == 0 ) {
                    log.warn "No DTI metrics files have been found in your derivatives folder. " +
                    "This might affect NODDI / FreeWater processing and throw errors."
                }
                return [ meta, fa, ad, rd, md ]
            }
        ch_fa = FETCH_DERIVATIVES.out.metrics
            .map { meta, files ->
                def fa = files.findAll { file -> file.name.contains('param-fa_dwimap.nii.gz') }

                // ** Some logging if no files exists ** //
                if ( fa.size() == 0 ) {
                    error "No FA file have been found in your derivatives folder. " +
                    "Please validate your structure respects the BIDS specification."
                }
                return [ meta, fa ]
            }
        ch_fodf = FETCH_DERIVATIVES.out.fodf
        ch_peaks = FETCH_DERIVATIVES.out.peaks
        ch_trk = FETCH_DERIVATIVES.out.trk
        ch_transforms = FETCH_DERIVATIVES.out.transforms
        ch_dwi_bval_bvec = FETCH_DERIVATIVES.out.dwi_bval_bvec
        ch_brain_mask = FETCH_DERIVATIVES.out.brain_mask
        ch_anat = FETCH_DERIVATIVES.out.anat

        if ( params.segmentation ) {
            ch_labels = SEGMENTATION.out.dseg
        } else {
            ch_labels = FETCH_DERIVATIVES.out.labels
        }
    } else if ( params.tracking && (params.run_noddi || params.run_freewater || params.connectomics || params.bundling) ) {
        ch_metrics = RECONST_DTIMETRICS.out.fa
            .join(RECONST_DTIMETRICS.out.md)
            .join(RECONST_DTIMETRICS.out.ad)
            .join(RECONST_DTIMETRICS.out.rd)
            .join(RECONST_DTIMETRICS.out.mode)
            .join(RECONST_FODF.out.afd_total)
            .join(RECONST_FODF.out.nufo)
        ch_fa_ad_rd_md = RECONST_DTIMETRICS.out.fa
            .join(RECONST_DTIMETRICS.out.ad)
            .join(RECONST_DTIMETRICS.out.rd)
            .join(RECONST_DTIMETRICS.out.md)
        ch_fa = RECONST_DTIMETRICS.out.fa
        ch_fodf = RECONST_FODF.out.fodf
        ch_peaks = RECONST_FODF.out.peaks
        ch_transforms = ANATTODWI.out.forward_warp
            .join(ANATTODWI.out.forward_affine)
        ch_dwi_bval_bvec = PREPROC_DWI.out.dwi
            .join(PREPROC_DWI.out.bval)
            .join(PREPROC_DWI.out.bvec)
        ch_brain_mask = PREPROC_DWI.out.b0_mask
        ch_anat = ANATTODWI.out.anat_warped

        if ( params.segmentation ) {
            ch_labels = SEGMENTATION.out.dseg
        } else if ( params.connectomics ) {
            if ( !params.input_deriv ) {
                error "No cortical/subcortical segmentation derivatives provided. Please provide a valid --input_deriv path or run the segmentation profile using `-profile segmentation`."
            } else {
                FETCH_DERIVATIVES ( params.input_deriv )
                ch_labels = FETCH_DERIVATIVES.out.labels
            }
        }
    }

    if (params.run_noddi || params.run_freewater) {
            // ** Prepare channels for priors coming from the normative curves ** //
            ch_normative_diff = ch_dwi_bval_bvec
                .multiMap { meta, _dwi, _bval, _bvec ->
                    para_diff: params.average_diff_priors ? channel.empty() : params.para_diff ? tuple(meta, params.para_diff) : tuple(meta, meta.ad)
                    iso_diff: params.average_diff_priors ? channel.empty() : params.iso_diff ? tuple(meta, params.iso_diff) : tuple(meta, meta.md)
                    perp_diff_min: params.average_diff_priors ? channel.empty() : params.perp_diff_min ? tuple(meta, params.perp_diff_min) : tuple(meta, meta.rd_min)
                    perp_diff_max: params.average_diff_priors ? channel.empty() : params.perp_diff_max ? tuple(meta, params.perp_diff_max) : tuple(meta, meta.rd_max)
                }

            // ** Run NODDI / FreeWater reconstruction ** //
            RECONST_FW_NODDI (
                ch_dwi_bval_bvec,
                ch_brain_mask,
                ch_fa_ad_rd_md,
                [
                    para_diff: ch_normative_diff.para_diff,
                    iso_diff: ch_normative_diff.iso_diff,
                    perp_diff_min: ch_normative_diff.perp_diff_min,
                    perp_diff_max: ch_normative_diff.perp_diff_max
                ],
                [
                    "run_noddi": params.run_noddi,
                    "run_freewater": params.run_freewater,
                    "average_diff_priors": params.average_diff_priors,
                    "silence_single_shell_warnings": false
                ]
            )
            ch_versions = ch_versions.mix(RECONST_FW_NODDI.out.versions)

            // ** Set output channels ** //
            ch_metrics = ch_metrics
                .mix(RECONST_FW_NODDI.out.noddi_isovf)
                .mix(RECONST_FW_NODDI.out.noddi_icvf)
                .mix(RECONST_FW_NODDI.out.noddi_ecvf)
                .mix(RECONST_FW_NODDI.out.noddi_odi)
                .mix(RECONST_FW_NODDI.out.fw_fwf)
                .mix(RECONST_FW_NODDI.out.fw_fibervolume)
                .mix(RECONST_FW_NODDI.out.fw_dti_md)
                .mix(RECONST_FW_NODDI.out.fw_dti_rd)
                .mix(RECONST_FW_NODDI.out.fw_dti_ad)
                .mix(RECONST_FW_NODDI.out.fw_dti_fa)
                .groupTuple(by: 0)

            // ** Update files to transform ** //
            ch_nifti_files_to_transform = ch_nifti_files_to_transform
                .mix(RECONST_FW_NODDI.out.noddi_isovf)
                .mix(RECONST_FW_NODDI.out.noddi_icvf)
                .mix(RECONST_FW_NODDI.out.noddi_ecvf)
                .mix(RECONST_FW_NODDI.out.noddi_odi)
                .mix(RECONST_FW_NODDI.out.fw_fwf)
                .mix(RECONST_FW_NODDI.out.fw_fibervolume)
                .mix(RECONST_FW_NODDI.out.fw_dti_md)
                .mix(RECONST_FW_NODDI.out.fw_dti_rd)
                .mix(RECONST_FW_NODDI.out.fw_dti_ad)
                .mix(RECONST_FW_NODDI.out.fw_dti_fa)
            ch_rgb_files_to_transform = ch_rgb_files_to_transform
                .mix(RECONST_FW_NODDI.out.fw_dti_rgb)
    }

    if ( params.bundling ) {
        //
        // SUBWORKFLOW: Run BUNDLE_SEG
        //
        BUNDLE_SEG(
            ch_fa,
            ch_trk
        )
        ch_versions = ch_versions.mix(BUNDLE_SEG.out.versions)

        // ** Format metrics channel ** //
        ch_metrics_tractometry = ch_metrics.map { items ->
            def meta = items[0]
            def metrics = items[1..-1].flatten()
            return [meta, metrics]
        }

        //
        // SUBWORKFLOW: RUN TRACTOMETRY
        //
        TRACTOMETRY (
            BUNDLE_SEG.out.bundles,
            BUNDLE_SEG.out.centroids,
            ch_metrics_tractometry,
            channel.empty(),
            ch_fodf
        )
        ch_trk_files_to_transform = ch_trk_files_to_transform
            .mix(TRACTOMETRY.out.bundles)
        ch_versions = ch_versions.mix(TRACTOMETRY.out.versions)

        //
        // MODULE: MERGE_TSV
        //
        ch_merged_mean_tsv = TRACTOMETRY.out.mean_tsv
            .map { _meta, stats -> stats }
            .collectFile(
                storeDir: "${params.outdir}/",
                name: "bundles_mean_stats.tsv",
                skip: 1,
                keepHeader: true
            )
        ch_merged_point_tsv = TRACTOMETRY.out.mean_per_point_tsv
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
        //
        // MODULE : Run AntsApplyTransforms.
        //
        ch_labels = ch_labels.branch { label_tuple ->
            reg: label_tuple.size() > 2 && !params.segmentation
                return [label_tuple[0], label_tuple[2]]
            notreg: label_tuple.size() < 3
                return [label_tuple[0], label_tuple[1]]
        }

        ch_antsapply = ch_labels.notreg
            .join(ch_anat)
            .join(ch_transforms)
            .map{ meta, labels, anat, warp, affine ->
                return [ meta, labels, anat, [warp, affine] ]
            }

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
            .filter { _meta, _trk, label -> label != null }

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
        // ch_trk_files_to_transform = ch_trk_files_to_transform
        //    .mix(FILTERING_COMMIT.out.hdf5)

        //
        // MODULE: Run AFDFIXEL
        //
        ch_afdfixel = FILTERING_COMMIT.out.hdf5
            .join(ch_fodf)

        CONNECTIVITY_AFDFIXEL ( ch_afdfixel )
        ch_versions = ch_versions.mix(CONNECTIVITY_AFDFIXEL.out.versions.first())
        // ch_multiqc_files = ch_multiqc_files.mix(CONNECTIVITY_AFDFIXEL.out.zip.collect{it[1]})
        // ch_trk_files_to_transform = ch_trk_files_to_transform
        //    .mix(CONNECTIVITY_AFDFIXEL.out.hdf5)

        //
        // MODULE: Run CONNECTIVITY_METRICS
        //
        ch_metrics_connectivity = ch_metrics.map { items ->
            def meta = items[0]
            def metrics = items[1..-1].flatten()
            return [meta, metrics]
        }

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
            .join(ch_metrics_connectivity)

        CONNECTIVITY_METRICS ( ch_metrics_conn )
        ch_versions = ch_versions.mix(CONNECTIVITY_METRICS.out.versions.first())
        ch_multiqc_files_sub = ch_multiqc_files_sub
            .mix(CONNECTIVITY_METRICS.out.metrics)

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
                def all_files = file_lists.flatten().findAll { file -> file != null }
                return tuple(meta, all_files)
            }

        ch_rgb_files_to_transform = ch_rgb_files_to_transform
            .groupTuple()
            .map { tuple_elements ->
                def meta = tuple_elements[0]
                def file_lists = tuple_elements[1..-1] // Get all elements except the first (meta)
                def all_files = file_lists.flatten().findAll { file -> file != null }
                return tuple(meta, all_files)
            }

        ch_mask_files_to_transform = ch_mask_files_to_transform
            .groupTuple()
            .map { tuple_elements ->
                def meta = tuple_elements[0]
                def file_lists = tuple_elements[1..-1] // Get all elements except the first (meta)
                def all_files = file_lists.flatten().findAll { file -> file != null }
                return tuple(meta, all_files)
            }

        ch_labels_files_to_transform = ch_labels_files_to_transform
            .groupTuple()
            .map { tuple_elements ->
                def meta = tuple_elements[0]
                def file_lists = tuple_elements[1..-1] // Get all elements except the first (meta)
                def all_files = file_lists.flatten().findAll { file -> file != null }
                return tuple(meta, all_files)
            }

        ch_trk_files_to_transform = ch_trk_files_to_transform
            .groupTuple()
            .map { tuple_elements ->
                def meta = tuple_elements[0]
                def file_lists = tuple_elements[1..-1] // Get all elements except the first (meta)
                def all_files = file_lists.flatten().findAll { file -> file != null }
                return tuple(meta, all_files)
            }

        OUTPUT_TEMPLATE_SPACE(
            params.tracking ? ANATTODWI.out.anat_warped : ch_anat,
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
    ch_tissueseg = channel.empty()
        .mix(FASTSEG.out.wm_mask)
        .mix(FASTSEG.out.gm_mask)
        .mix(FASTSEG.out.csf_mask)
        .mix(TRACKINGMASKS.out.wm)
        .mix(TRACKINGMASKS.out.gm)
        .mix(TRACKINGMASKS.out.csf)
        .groupTuple()
        .map { meta, files ->
            def sortedFiles = files.flatten().findAll { file -> file != null }.sort { file ->
                if (file.name.contains('wm')) return 0
                else if (file.name.contains('gm')) return 1
                else if (file.name.contains('csf')) return 2
                else return 3
            }
            return [meta] + sortedFiles
        }
    } else {
        ch_tissueseg = channel.empty()
    }

    if ( params.tracking ) {
        ch_anat_qc = ANATTODWI.out.anat_warped
    } else if ( params.segmentation && !params.connectomics ) {
        // ** Fetching the T1w and T2w images for QC ** //
        // ** If both are provided, use T1w, else, use T2w. ** //
        ch_anat_qc = channel.empty()
            .mix(SEGMENTATION.out.t1)
            .mix(SEGMENTATION.out.t2)
            .groupTuple()
            .map { meta, files ->
                return [meta] + files.flatten().findAll { file -> file != null }.sort { file ->
                    if (file.name.contains("T2w")) return 0
                    else return 1}
            }
            .branch{ tuple ->
                T1w: tuple.size() > 3 && tuple[0].age >= 0.25 && tuple[0].age <= 18
                    return [tuple[0], tuple[2]]
                T2w: true // Catch-all for only T2w.
                    return [tuple[0], tuple[1]]
            }
        ch_anat_qc = ch_anat_qc.T1w.mix(ch_anat_qc.T2w)
    } else if ( params.bundling ) {
        ch_anat_qc = channel.empty()
    } else {
        ch_anat_qc = ch_anat
    }

    QC (
        ch_anat_qc,
        ch_tissueseg,
        params.connectomics ? FILTERING_COMMIT.out.trk : params.tracking ? ch_trk : channel.empty(),
        params.tracking ? ch_inputs.dwi_bval_bvec : params.connectomics ? ch_dwi_bval_bvec : channel.empty(),
        params.tracking ? RECONST_DTIMETRICS.out.fa : channel.empty(),
        params.tracking ? RECONST_DTIMETRICS.out.md : channel.empty(),
        params.tracking ? RECONST_FODF.out.nufo : channel.empty(),
        params.tracking ? RECONST_DTIMETRICS.out.rgb : channel.empty()
    )

    qc_files = ch_multiqc_files_sub
        .mix(params.connectomics ? ch_labels_qc : params.segmentation ? SEGMENTATION.out.dseg : channel.empty())
        .mix(params.segmentation ? SEGMENTATION.out.dseg_tsv : channel.empty())
        .mix(params.bundling ? TRACTOMETRY.out.bundles : channel.empty())
        .mix(ch_anat_qc)
        .mix(QC.out.tissueseg_png)
        .mix(QC.out.tracking_png)
        .mix(QC.out.shell_png)
        .mix(QC.out.metrics_png)
        .groupTuple()
        .map { meta, png_list ->
            def images = png_list.flatten().findAll { png -> png != null }
            return tuple(meta, images)
        }

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'sf_pediatric_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        )

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = channel.empty()  // To store versions, methods description, etc.
                                        // Otherwise, stored in either subject or global level channel.

    ch_multiqc_config_subject = channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_config_global = channel.fromPath(
        "$projectDir/assets/multiqc_config_global.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        channel.fromPath(params.multiqc_config, checkIfExists: true) :
        channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        channel.fromPath("$projectDir/assets/sf-pediatric-light-logo.png", checkIfExists: true)

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = params.multiqc_methods_description
        ? file(params.multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    MULTIQC_SUBJECT(
        qc_files,
        ch_multiqc_files.collect(),
        ch_multiqc_config_subject.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    ch_multiqc_files_global = ch_multiqc_files_global.mix(
        ch_multiqc_files.mix(QC.out.dice_stats.map{ _meta, dice -> dice }.flatten())
    )
    ch_multiqc_files_global = ch_multiqc_files_global.mix(QC.out.sc_values.map{ _meta, sc -> sc }.flatten())
    if ( params.connectomics ) {
        ch_multiqc_files_global = ch_multiqc_files_global
            .mix(CONNECTIVITY_METRICS.out.metrics.map{ _meta, metrics -> metrics })
    }

    // Collect the framewise displacement files from the ch_multiqc_files_sub channel
    ch_fd_files = ch_multiqc_files_sub
        .filter { _meta, files ->
            files.any { file -> file.name.contains("dwi_eddy_restricted_movement_rms") }
        }
        .map { _meta, files -> files }
    ch_multiqc_files_global = ch_multiqc_files_global.mix(ch_fd_files.flatten())

    MULTIQC_GLOBAL (
        channel.of([meta:[id:"global"], qc_images:[]]),
        ch_multiqc_files_global.collect(),
        ch_multiqc_config_global.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:
    multiqc_report = MULTIQC_SUBJECT.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
