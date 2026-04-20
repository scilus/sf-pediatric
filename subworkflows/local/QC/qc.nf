include { QC_SCREENSHOT as QC_TISSUES     } from '../../../modules/local/qc/screenshot.nf'
include { QC_SCREENSHOT as QC_LABELS      } from '../../../modules/local/qc/screenshot.nf'
include { QC_TRACTOGRAM                   } from '../../../modules/nf-neuro/qc/tractogram/main'
include { QC_SHELL                        } from '../../../modules/local/qc/shell.nf'
include { QC_METRICS                      } from '../../../modules/local/qc/metrics.nf'

workflow QC {

    take:
    ch_anat             // channel: [ val(meta), [ anat ] ]
    ch_maps             // channel: [ val(meta), [ wm ], [ gm ], [ csf ] ]
    ch_tracking         // channel: [ val(meta), [ tractogram ] ]
    ch_dwi_bval_bvec    // channel: [ val(meta), [ dwi ], [ bval ], [ bvec ] ]
    ch_fa               // channel: [ val(meta), [ fa ] ]
    ch_md               // channel: [ val(meta), [ md ] ]
    ch_nufo             // channel: [ val(meta), [ nufo ] ]
    ch_rgb              // channel: [ val(meta), [ rgb ] ]

    main:

    ch_versions = channel.empty()

    //
    // ** Generate screenshots for DWI shell **
    //
    ch_shell_qc = ch_dwi_bval_bvec
        .map{ it -> [ it[0], it[2], it[3] ] }

    QC_SHELL ( ch_shell_qc )
    ch_versions = ch_versions.mix(QC_SHELL.out.versions.first())

    //
    // ** Generate screenshots for tissue segmentation **
    //
    ch_tissueseg_qc = ch_anat
        .join(ch_maps, remainder: true)
        .branch { it ->
            withmaps: it.size() > 2 && it[3] != null
                return [ it[0], it[1], it[2], it[3], it[4], [] ]
            withoutmaps: true
                return [ it[0], it[1], [], [], [], [] ]
        }

    QC_TISSUES ( ch_tissueseg_qc.withmaps )
    ch_versions = ch_versions.mix(QC_TISSUES.out.versions.first())

    //
    // ** Generate screenshots for metrics **
    //
    ch_metrics_qc = ch_fa
        .join(ch_md)
        .join(ch_nufo)
        .join(ch_rgb)

    QC_METRICS ( ch_metrics_qc )
    ch_versions = ch_versions.mix(QC_METRICS.out.versions.first())

    //
    // ** Generate tracking QC **
    //
    ch_tracking_qc = ch_tracking
        .join(ch_maps)
        .map{ it -> it[0..3] }

    QC_TRACTOGRAM ( ch_tracking_qc )
    ch_versions = ch_versions.mix(QC_TRACTOGRAM.out.versions.first())

    emit:
    tissueseg_png      = QC_TISSUES.out.tissue_seg ?: channel.empty()   // channel: [ val(meta), [ png ] ]
    tracking_png       = QC_TRACTOGRAM.out.mqc ?: channel.empty()         // channel: [ val(meta), [ png ] ]
    dice_stats         = QC_TRACTOGRAM.out.dice ?: channel.empty()        // channel: [ val(meta), [ dice ] ]
    sc_values          = QC_TRACTOGRAM.out.sc ?: channel.empty()          // channel: [ val(meta), [ sc ] ]
    shell_png          = QC_SHELL.out.shell ?: channel.empty()          // channel: [ val(meta), [ png ] ]
    metrics_png        = QC_METRICS.out.png ?: channel.empty()          // channel: [ val(meta), [ png ] ]

    versions = ch_versions                     // channel: [ versions.yml ]
}
