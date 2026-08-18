// ** Main segmentation module ** //
include { SEGMENTATION_FASTSURFER as FASTSURFER } from '../../../modules/nf-neuro/segmentation/fastsurfer/main'
include { SEGMENTATION_FSRECONALL as RECONALL } from '../../../modules/nf-neuro/segmentation/fsreconall/main'
include { SEGMENTATION_RECONALLCLINICAL as RECONALLCLINICAL } from '../../../modules/local/segmentation/reconallclinical/main'
include { SEGMENTATION_BIBSNET as BIBSNET } from '../../../modules/local/segmentation/bibsnet'
include { SEGMENTATION_INFANTFS as INFANTFS } from '../../../modules/local/segmentation/infantfs'

include { ATLASES_FSLR2FSAVERAGE as ATLASES_FSLR2FSAVERAGE } from '../../../modules/local/atlases/fslr2fsaverage'
include { ATLASES_FSAVERAGE2SUBJECT as ATLASES_FSAVERAGE2SUBJECT } from '../../../modules/local/atlases/fsaverage2subject'
include { REGISTRATION_ANTS as REGISTRATION_ANTS } from '../../../modules/nf-neuro/registration/ants/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as REGISTRATION_ANTSAPPLYTRANSFORMS } from '../../../modules/nf-neuro/registration/antsapplytransforms/main'

workflow SEGMENTATION {

    take:
    ch_t1                       // channel: [ val(meta), [ t1 ] ]
    ch_t2                       // channel: [ val(meta), [ t2 ] ]
    ch_atlas                    // channel: [ atlas ]
    ch_fs_license               // channel: [ fs_license ]
    ch_mni152                   // channel: [ mni152 ]
    ch_intermediate_template    // channel: [ val(meta), [ intermediate_template ], [ transformations ] ]
    ch_fslr                     // channel: [ fslr ]
    ch_fsaverage                // channel: [ fsaverage ]

    main:

    ch_versions = channel.empty()

    //
    // MODULE: Run FastSurfer or FreeSurfer T1 reconstruction
    //
    ch_seg = ch_t1
        .join(ch_t2, remainder: true)
        .combine(ch_fs_license)
        .branch { it ->
            fastsurfer: it[0].age >= 5 && it[0].age <= 18 && params.method == 'fastsurfer'
                return [it[0], it[1], it[3]]
            freesurfer: it[0].age >= 5 && it[0].age <= 18 && params.method == "recon-all"
                return [it[0], it[1], it[3]]
            clinical: it[0].age >= 1 && it[0].age <= 18 && params.method == "recon-all-clinical"
                return [it[0], it[1] ?: it[2], it[3]]
            infant: true
                return [it[0], it[1] ?: [], it[2] ?: []]
        }

    // ** FastSurfer ** //
    FASTSURFER ( ch_seg.fastsurfer )
    ch_versions = ch_versions.mix(FASTSURFER.out.versions)

    // ** ReconAll ** //
    RECONALL ( ch_seg.freesurfer )
    ch_versions = ch_versions.mix(RECONALL.out.versions)

    // ** ReconAll Clinical ** //
    RECONALLCLINICAL ( ch_seg.clinical )
    ch_versions = ch_versions.mix(RECONALLCLINICAL.out.versions)

    // ** output the final t1w image ** //
    ch_t1w = channel.empty()
        .mix(FASTSURFER.out.final_t1)
        .mix(RECONALL.out.final_t1)
        .mix(RECONALLCLINICAL.out.final_t1)
        .join(ch_t1, remainder: true)
        .map{ meta, final_t1, t1 ->
            return [meta, final_t1 ?: t1]
        }

    // ** Use BIBSNet for infant segmentation as a prior for infant freesurfer ** //
    BIBSNET ( ch_seg.infant )

    // ** Run infant freesurfer using segmentation from BIBSNet ** //
    ch_infantfs = ch_seg.infant
        .join(BIBSNET.out.t1_dseg, remainder: true)
        .join(BIBSNET.out.t1_brain_mask, remainder: true)
        .join(BIBSNET.out.t2_dseg, remainder: true)
        .join(BIBSNET.out.t2_brain_mask, remainder: true)
        .combine(ch_fs_license)
        .map{ meta, t1, t2, t1_dseg, t1_brain_mask, t2_dseg, t2_brain_mask, license ->
            return [meta, t2 ?: t1, t2_dseg ?: t1_dseg, t2_brain_mask ?: t1_brain_mask, license]
        }

    INFANTFS ( ch_infantfs )

    // ** T2w outputs ** //
    // ** Keeping the INFANTFS output if available, otherwise mix in the ch_t2 ** //
    ch_t2w = ch_t2
        .join(INFANTFS.out.image, remainder: true)
        .map{
            meta, t2, image ->
                return [meta, image ?: t2]
        }

    //
    // MODULE: Run REGISTRATION_ANTS
    //
    /* Compute the registration between subject space and MNI152Lin6Asym space, */
    /* or the UNCBCP4D template for infant subjects.                            */
    ch_register = FASTSURFER.out.final_t1
        .mix(RECONALL.out.final_t1)
        .mix(RECONALLCLINICAL.out.final_t1)
        .mix(INFANTFS.out.image)
        .combine(ch_mni152)
        .join(ch_intermediate_template, remainder: true)
        .branch { meta, anat, mni152, int_template, _int_transfo ->
            intermediate: int_template != []
                return [meta, int_template, anat, []]
            mni: true
                return [meta, mni152, anat, []]
        }
    ch_register_sub = ch_register.intermediate
        .mix(ch_register.mni)

    REGISTRATION_ANTS ( ch_register_sub )
    ch_versions = ch_versions.mix(REGISTRATION_ANTS.out.versions)

    //
    // MODULE: Run FSLR2FSAVERAGE mapping
    //
    ch_fslr2fsaverage = ch_atlas
        .combine(ch_fslr)
        .combine(ch_fsaverage)
        .combine(ch_fs_license)
        .map{ atlas, fslr, fsaverage, license ->
            [[id: "fsaverage"], atlas, fslr, fsaverage, license]
        }

    ATLASES_FSLR2FSAVERAGE ( ch_fslr2fsaverage )
    ch_versions = ch_versions.mix(ATLASES_FSLR2FSAVERAGE.out.versions)

    //
    // MODULE: Run antsapplytransform to warp the subcortical volume
    //
    ch_temp_transforms = FASTSURFER.out.final_t1
        .mix(RECONALL.out.final_t1)
        .mix(RECONALLCLINICAL.out.final_t1)
        .mix(INFANTFS.out.image)
        .join(REGISTRATION_ANTS.out.backward_image_transform)
        .combine(ATLASES_FSLR2FSAVERAGE.out.subcortical.map{ it -> it[1] }.first())  // extract the path from the emitted tuple
        .join(ch_intermediate_template, remainder: true)
        .branch { meta, anat, transformations, subcortical, int_template, int_transform ->
            intermediate: int_template != []
                return [meta, subcortical, anat, transformations + [int_transform]]
            mni: true
                return [meta, subcortical, anat, transformations]
        }
    ch_transforms = ch_temp_transforms.intermediate
        .mix(ch_temp_transforms.mni)

    REGISTRATION_ANTSAPPLYTRANSFORMS ( ch_transforms )
    ch_versions = ch_versions.mix(REGISTRATION_ANTSAPPLYTRANSFORMS.out.versions)

    //
    // MODULE: Run FSAVERAGE2SUBJECT mapping
    //
    ch_fsaverage2subject = channel.empty()
        .mix(RECONALLCLINICAL.out.folder)
        .mix(RECONALL.out.recon_all_out_folder)
        .mix(FASTSURFER.out.fastsurferdirectory)
        .mix(INFANTFS.out.folder)
        .combine(ATLASES_FSLR2FSAVERAGE.out.fsaverage
            .map{ it -> it[1] })  // extract the path from the emitted tuple
        .join(REGISTRATION_ANTSAPPLYTRANSFORMS.out.warped_image)
        .combine(ch_fs_license)

    ATLASES_FSAVERAGE2SUBJECT ( ch_fsaverage2subject, ATLASES_FSLR2FSAVERAGE.out.atlas_name.first() )
    ch_versions = ch_versions.mix(ATLASES_FSAVERAGE2SUBJECT.out.versions)

    emit:
    // ** Processed anatomical image ** //
    t1              = ch_t1w                                                // channel: [ val(meta), [ t1 ] ]
    t2              = ch_t2w                                                // channel: [ val(meta), [ t2 ] ]

    // ** Segmentation ** //
    folder          = ATLASES_FSAVERAGE2SUBJECT.out.folder
    dseg            = ATLASES_FSAVERAGE2SUBJECT.out.dseg
    dseg_tsv        = ATLASES_FSAVERAGE2SUBJECT.out.dseg_tsv

    // ** Stats ** //
    tsv             = ATLASES_FSAVERAGE2SUBJECT.out.tsv

    versions = ch_versions                                                  // channel: [ versions.yml ]
}
