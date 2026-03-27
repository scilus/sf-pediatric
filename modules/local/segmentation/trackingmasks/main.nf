process SEGMENTATION_TRACKINGMASKS {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container 'scilus/scilus:2.2.2'

    input:
    tuple val(meta), path(wm), path(gm), path(csf), path(fa), path(md), path(mask)

    output:
    tuple val(meta), path("*wm_mask.nii.gz")        , emit: wm
    tuple val(meta), path("*gm_mask.nii.gz")        , emit: gm
    tuple val(meta), path("*csf_mask.nii.gz")       , emit: csf
    path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    # Thresholding the maps.
    mrthreshold $wm ${prefix}__wm_mask.nii.gz -abs 0.3 -nthreads 1 -force
    mrthreshold $gm ${prefix}__gm_mask.nii.gz -abs 0.3 -nthreads 1 -force
    mrthreshold $csf ${prefix}__csf_mask.nii.gz -abs 0.3 -nthreads 1 -force

    # Erode the brain mask.
    scil_volume_math erosion $mask 8 ${prefix}__mask_eroded.nii.gz --data_type uint8
    mrthreshold $fa ${prefix}__fa_thresholded.nii.gz -abs 0.2 -nthreads 1
    mrcalc ${prefix}__fa_thresholded.nii.gz ${prefix}__mask_eroded.nii.gz \
        -mult ${prefix}__fa_thresholded.nii.gz -nthreads 1 -force -datatype uint8
    scil_volume_math dilation ${prefix}__fa_thresholded.nii.gz 1 \
        ${prefix}__fa_thresholded.nii.gz --data_type uint8 -f

    # Identify the ventricles by thresholding the md. (more robust than the CSF map)
    mrthreshold $md ventricles.nii.gz -abs 0.002 -nthreads 1 -force
    mrcalc ventricles.nii.gz ${prefix}__mask_eroded.nii.gz \
        -mult ventricles.nii.gz -nthreads 1 -force -datatype uint8

    # Union between FA thresholded and WM mask from template.
    scil_volume_math union ${prefix}__fa_thresholded.nii.gz \
        ${prefix}__wm_mask.nii.gz \
        ${prefix}__wm_mask.nii.gz \
        --data_type uint8 \
        -f

    # Remove the ventricles to prevent tracking through them.
    scil_volume_math difference ${prefix}__wm_mask.nii.gz \
        ventricles.nii.gz \
        ${prefix}__wm_mask.nii.gz \
        --data_type uint8 \
        -f

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrtrix: \$(mrcalc -version 2>&1 | sed -n 's/== mrcalc \\([0-9.]\\+\\).*/\\1/p')
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}__wm_mask.nii.gz
    touch ${prefix}__gm_mask.nii.gz
    touch ${prefix}__csf_mask.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrtrix: \$(mrcalc -version 2>&1 | sed -n 's/== mrcalc \\([0-9.]\\+\\).*/\\1/p')
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS

    function handle_code () {
    local code=\$?
    ignore=( 1 )
    exit \$([[ " \${ignore[@]} " =~ " \$code " ]] && echo 0 || echo \$code)
    }
    trap 'handle_code' ERR

    mrthreshold -h
    """
}
