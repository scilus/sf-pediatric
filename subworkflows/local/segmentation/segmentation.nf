// ** Main segmentation module ** //
include { SEGMENTATION_FASTSURFER as FASTSURFER } from '../../../modules/nf-neuro/segmentation/fastsurfer/main'
include { SEGMENTATION_FSRECONALL as RECONALL } from '../../../modules/nf-neuro/segmentation/fsreconall/main'
include { SEGMENTATION_RECONALLCLINICAL as RECONALLCLINICAL } from '../../../modules/local/segmentation/reconallclinical/main'
include { SEGMENTATION_MCRIBS as MCRIBS } from '../../../modules/local/segmentation/mcribs'

// ** Atlas modules ** //
include { ATLASES_BRAINNETOMECHILD as BRAINNETOMECHILD } from '../../../modules/local/atlases/brainnetomechild'
include { ATLASES_FORMATLABELS as FORMATLABELS         } from '../../../modules/local/atlases/formatlabels'
include { ATLASES_CONCATENATESTATS as CONCATENATESTATS } from '../../../modules/local/atlases/concatenatestats'

workflow SEGMENTATION {

    take:
    ch_t1           // channel: [ val(meta), [ t1 ] ]
    ch_t2           // channel: [ val(meta), [ t2 ] ]
    ch_coreg        // channel: [ val(meta), [ t1 ] ]
    ch_fs_license   // channel: [ fs_license ]
    ch_utils_folder // channel: [ utils_folder ]

    main:

    ch_versions = channel.empty()

    //
    // MODULE: Run FastSurfer or FreeSurfer T1 reconstruction
    //
    ch_seg = ch_t1
        .join(ch_t2, remainder: true)
        .join(ch_coreg, remainder: true)
        .combine(ch_fs_license)
        .branch { it ->
            fastsurfer: it[0].age >= 5 && it[0].age <= 18 && params.method == 'fastsurfer'
                return [it[0], it[1], it[4]]
            freesurfer: it[0].age >= 5 && it[0].age <= 18 && params.method == "recon-all"
                return [it[0], it[1], it[4]]
            clinical: it[0].age >= 0.25 && it[0].age <= 18 && params.method == "recon-all-clinical"
                return [it[0], it[1] ?: it[2], it[4]]
            infant: true
                return [it[0], it[2], it[4], it[3] ?: []]
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

    // ** For infant, it's a bit trickier, as MCRIBS do not  ** //
    // ** perform preprocessing, so we need to do it (done in pediatric.nf).   ** //
    // ** Run MCRIBS ** //
    MCRIBS ( ch_seg.infant )
    ch_versions = ch_versions.mix(MCRIBS.out.versions)
    // ch_multiqc_files = ch_multiqc_files.mix(MCRIBS.out.zip.collect{it[1]})

    // ** T2w outputs ** //
    // ** Keeping the MCRIBS output if available, otherwise mix in the ch_t2 ** //
    ch_t2w = ch_t2
        .join(MCRIBS.out.anat, remainder: true)
        .map{
            meta, t2, mcribs ->
                return [meta, mcribs ?: t2]
        }

    //
    // MODULE: Run BrainnetomeChild atlas
    //
    ch_atlas = channel.empty()
        .mix(FASTSURFER.out.fastsurferdirectory)
        .mix(RECONALL.out.recon_all_out_folder)
        .mix(RECONALLCLINICAL.out.folder)
        .mix(MCRIBS.out.folder)
        .groupTuple()
        .map {
            meta, files ->
                return [meta] + files.flatten().findAll { it -> it != null }
        }
        .combine(ch_utils_folder)
        .combine(ch_fs_license)
        .branch { it ->
            infant: it[0].age < 0.25 || it[0].age > 18
                return it
            child: it[0].age >= 0.25 && it[0].age <= 18
        }

    BRAINNETOMECHILD ( ch_atlas.child )
    ch_versions = ch_versions.mix(BRAINNETOMECHILD.out.versions)

    //
    // MODULE: Format labels
    //
    FORMATLABELS ( ch_atlas.infant )
    ch_versions = ch_versions.mix(FORMATLABELS.out.versions)

    ch_labels = channel.empty()
        .mix(BRAINNETOMECHILD.out.labels)
        .mix(FORMATLABELS.out.labels)
    ch_lut = channel.empty()
        .mix(BRAINNETOMECHILD.out.labels_json)
        .mix(FORMATLABELS.out.labels_json)

    //
    // MODULE: Concatenate stats
    //
    ch_stats = channel.empty()
        .mix(FORMATLABELS.out.stats.collect().map { it ->
            [[id: 'Global', agegroup: 'Infant'], it]
        })
        .mix(BRAINNETOMECHILD.out.stats.collect().map{ it ->
            [[id: 'Global', agegroup: 'Child'], it]
        })

    CONCATENATESTATS ( ch_stats )
    ch_versions = ch_versions.mix(CONCATENATESTATS.out.versions)

    emit:
    // ** Processed anatomical image ** //
    t1              = ch_t1                                                 // channel: [ val(meta), [ t1 ] ]
    t2              = ch_t2w                                                // channel: [ val(meta), [ t2 ] ]

    // ** Segmentation ** //
    labels          = ch_labels                                             // channel: [ val(meta), [ labels ] ]
    lut             = ch_lut                                                // channel: [ val(meta), [ labels_json ] ]

    // ** Stats ** //
    volume_lh       = CONCATENATESTATS.out.volume_lh ?: channel.empty()     // channel: [ volume_lh.tsv ]
    volume_rh       = CONCATENATESTATS.out.volume_rh ?: channel.empty()     // channel: [ volume_rh.tsv ]
    area_lh         = CONCATENATESTATS.out.area_lh ?: channel.empty()       // channel: [ area_lh.tsv ]
    area_rh         = CONCATENATESTATS.out.area_rh ?: channel.empty()       // channel: [ area_rh.tsv ]
    thickness_lh    = CONCATENATESTATS.out.thickness_lh ?: channel.empty()  // channel: [ thickness_lh.tsv ]
    thickness_rh    = CONCATENATESTATS.out.thickness_rh ?: channel.empty()  // channel: [ thickness_rh.tsv ]
    subcortical     = CONCATENATESTATS.out.subcortical ?: channel.empty()   // channel: [ subcortical_volumes.tsv ]

    versions = ch_versions                                                  // channel: [ versions.yml ]
}
