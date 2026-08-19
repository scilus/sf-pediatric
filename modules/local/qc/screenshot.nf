process QC_SCREENSHOT {
    tag "$meta.id"
    label 'process_single'

    container 'scilus/scilus:2.2.2'

    input:
    tuple val(meta), path(image), path(wmmask), path(gmmask), path(csfmask), path(labels)

    output:
    tuple val(meta), path("*_tissue_segmentation_mqc.png")      , emit: tissue_seg, optional: true
    tuple val(meta), path("*_labels_mqc.png")                   , emit: labels, optional: true
    path "versions.yml"                                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def opacity = task.ext.opacity?: 0.2
    def cmap = task.ext.cmap ?: "turbo"

    if ( !labels ) {
    """
    # Fetch middle axial slice.
    size=\$(mrinfo $image -size)
    mid_slice=\$(echo \$size | awk '{print int((\$3 + 1) / 2)}')

    scil_viz_volume_screenshot $image ${prefix}_ax.png \
        --slices \$mid_slice --axis axial \
        --overlays $wmmask $gmmask $csfmask \
        --overlays_as_contours \
        --display_lr \
        --overlays_opacity $opacity \
        --overlays_colors 255 0 0 0 255 0 0 0 255

    # Fetch middle coronal slice.
    mid_slice=\$(echo \$size | awk '{print int((\$2 + 1) / 2)}')

    scil_viz_volume_screenshot $image ${prefix}_cor.png \
        --slices \$mid_slice --axis coronal \
        --overlays $wmmask $gmmask $csfmask \
        --overlays_as_contours \
        --display_lr \
        --overlays_opacity $opacity \
        --overlays_colors 255 0 0 0 255 0 0 0 255

    # Fetch middle sagittal slice.
    mid_slice=\$(echo \$size | awk '{print int(((\$1 + 1) / 2) + 10)}')

    scil_viz_volume_screenshot $image ${prefix}_sag.png \
        --slices \$mid_slice --axis sagittal \
        --overlays $wmmask $gmmask $csfmask \
        --overlays_as_contours \
        --display_lr \
        --overlays_opacity $opacity \
        --overlays_colors 255 0 0 0 255 0 0 0 255

    # Merge images using ImageMagick.
    convert ${prefix}_ax*.png ${prefix}_cor*.png ${prefix}_sag*.png +append ${prefix}_tissue_segmentation_mqc.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d ' ' -f2)
    END_VERSIONS
    """
    } else {
    """
    # Fetch middle axial slice.
    size=\$(mrinfo $image -size)
    mid_slice=\$(echo \$size | awk '{print int((\$3 + 1) / 2)}')

    scil_viz_volume_screenshot $image ${prefix}_ax.png \
        --slices \$mid_slice --axis axial \
        --labelmap $labels \
        --labelmap_cmap_name $cmap \
        --labelmap_opacity $opacity

    # Fetch middle coronal slice.
    mid_slice=\$(echo \$size | awk '{print int((\$2 + 1) / 2)}')

    scil_viz_volume_screenshot $image ${prefix}_cor.png \
        --slices \$mid_slice --axis coronal \
        --labelmap $labels \
        --labelmap_cmap_name $cmap \
        --labelmap_opacity $opacity

    # Fetch middle sagittal slice.
    mid_slice=\$(echo \$size | awk '{print int((\$1 + 1) / 2)}')

    scil_viz_volume_screenshot $image ${prefix}_sag.png \
        --slices \$mid_slice --axis sagittal \
        --labelmap $labels \
        --labelmap_cmap_name $cmap \
        --labelmap_opacity $opacity

    # Merge images using ImageMagick.
    convert ${prefix}_ax*.png ${prefix}_cor*.png ${prefix}_sag*.png +append ${prefix}_labels_mqc.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d ' ' -f2)
    END_VERSIONS
    """
    }

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    if ( !labels ) {
    """
    scil_viz_volume_screenshot -h

    touch ${prefix}_tissue_segmentation_mqc.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d ' ' -f2)
    END_VERSIONS
    """
    } else {
    """
    scil_viz_volume_screenshot -h

    touch ${prefix}_labels_mqc.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d ' ' -f2)
    END_VERSIONS
    """
    }
}
