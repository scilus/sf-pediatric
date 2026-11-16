process REGISTER_MD {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container 'scilus/scilus:2.2.2'

    input:
    tuple val(meta), path(fixed), path(moving)

    output:
    tuple val(meta), path("*warped.nii.gz")                            , emit: image_warped
    tuple val(meta), path("*_forward1_affine.mat")                     , emit: forward_affine, optional: true
    tuple val(meta), path("*_forward0_warp.nii.gz")                    , emit: forward_warp, optional: true
    tuple val(meta), path("*_backward1_warp.nii.gz")                   , emit: backward_warp, optional: true
    tuple val(meta), path("*_backward0_affine.mat")                    , emit: backward_affine, optional: true
    tuple val(meta), path("*_forward*.{nii.gz,mat}", arity: '1..2')    , emit: forward_image_transform
    tuple val(meta), path("*_backward*.{nii.gz,mat}", arity: '1..2')   , emit: backward_image_transform
    tuple val(meta), path("*_backward*.{nii.gz,mat}", arity: '1..2')   , emit: forward_tractogram_transform
    tuple val(meta), path("*_forward*.{nii.gz,mat}", arity: '1..2')    , emit: backward_tractogram_transform
    tuple val(meta), path("*_mqc.gif")                                 , emit: mqc, optional: true
    path "versions.yml"                                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def run_qc = task.ext.run_qc ? task.ext.run_qc : false
    def suffix = task.ext.suffix ? task.ext.suffix + "_warped" : "warped"
    def suffix_qc = task.ext.suffix_qc ? task.ext.suffix_qc + "_mqc" : "mqc"
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$task.cpus
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1
    export ANTS_RANDOM_SEED=1234

    antsRegistration --dimensionality 3 --float 0 --verbose 1\
        --output [output,outputWarped.nii.gz,outputInverseWarped.nii.gz]\
        --interpolation Linear --use-histogram-matching 0\
        --winsorize-image-intensities [0.005,0.995]\
        --initial-moving-transform [$fixed,$moving,1]\
        --transform Rigid['0.2']\
        --metric mattes[$fixed,$moving,1,32,Regular,0.25]\
        --convergence [10000x10000x10000x10000,1e-7,20] --shrink-factors 8x4x2x1\
        --smoothing-sigmas 3x2x1x0\
        --transform Affine['0.2']\
        --metric mattes[$fixed,$moving,1,32,Regular,0.25]\
        --convergence [10000x10000x10000x10000,1e-7,20] --shrink-factors 8x4x2x1\
        --smoothing-sigmas 3x2x1x0\
        --transform SyN[0.2,3,0]\
        --metric mattes[$fixed,$moving,1,32,Regular,0.25]\
        --convergence [10000x10000x10000x10000,1e-7,20] --shrink-factors 8x4x2x1\
        --smoothing-sigmas 3x2x1x0

    mv outputWarped.nii.gz ${prefix}__${suffix}.nii.gz
    mv output0GenericAffine.mat ${prefix}__${suffix}_forward1_affine.mat
    mv output1InverseWarp.nii.gz ${prefix}__${suffix}_backward1_warp.nii.gz
    mv output1Warp.nii.gz ${prefix}__${suffix}_forward0_warp.nii.gz

    antsApplyTransforms -d 3 -t [${prefix}__${suffix}_forward1_affine.mat,1] \
        -o Linear[${prefix}__${suffix}_backward0_affine.mat]

    moving_id=\$(basename $moving .nii.gz)
    moving_id=\${moving_id#${meta.id}_*}

    ### ** QC ** ###
    if $run_qc; then
        mv $fixed fixed_image.nii.gz
        extract_dim=\$(mrinfo fixed_image.nii.gz -size)
        read sagittal_dim coronal_dim axial_dim <<< "\${extract_dim}"

        # Get the middle slice
        coronal_dim=\$((\$coronal_dim / 2))
        axial_dim=\$((\$axial_dim / 2))
        sagittal_dim=\$((\$sagittal_dim / 2))

        # Get fixed ID, moving ID already computed
        fixed_id=\$(basename $fixed .nii.gz)
        fixed_id=\${fixed_id#${meta.id}_*}

        # Set viz params.
        viz_params="--display_slice_number --display_lr --size 256 256"
        # Iterate over images.
        for image in fixed_image warped; do
            mrconvert *\${image}.nii.gz *\${image}_viz.nii.gz -stride -1,2,3
            scil_viz_volume_screenshot *\${image}_viz.nii.gz \${image}_coronal.png \
                --slices \$coronal_dim --axis coronal \$viz_params
            scil_viz_volume_screenshot *\${image}_viz.nii.gz \${image}_sagittal.png \
                --slices \$sagittal_dim --axis sagittal \$viz_params
            scil_viz_volume_screenshot *\${image}_viz.nii.gz \${image}_axial.png \
                --slices \$axial_dim --axis axial \$viz_params

            if [ \$image != fixed_image ]; then
                title="Warped \${moving_id^^}"
            else
                title="Reference \${fixed_id^^}"
            fi

            convert +append \${image}_coronal*.png \${image}_axial*.png \
                \${image}_sagittal*.png \${image}_mosaic.png
            convert -annotate +20+230 "\${title}" -fill white -pointsize 30 \
                \${image}_mosaic.png \${image}_mosaic.png

            # Clean up.
            rm \${image}_coronal*.png \${image}_sagittal*.png \${image}_axial*.png
        done

        # Create GIF.
        convert -delay 10 -loop 0 -morph 10 \
            warped_mosaic.png fixed_image_mosaic.png warped_mosaic.png \
            ${prefix}_${suffix_qc}_registration_ants_mqc.gif

        # Clean up.
        rm *_mosaic.png
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
        mrtrix: \$(mrinfo -version 2>&1 | sed -n 's/== mrinfo \\([0-9.]\\+\\).*/\\1/p')
        imagemagick: \$(convert -version | sed -n 's/.*ImageMagick \\([0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\).*/\\1/p')
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ? task.ext.suffix + "_warped" : "warped"
    def suffix_qc = task.ext.suffix_qc ? task.ext.suffix_qc + "_mqc" : "mqc"

    """
    antsRegistration -h

    touch ${prefix}__${suffix}.nii.gz
    touch ${prefix}__${suffix}_forward1_affine.mat
    touch ${prefix}__${suffix}_backward1_warp.nii.gz
    touch ${prefix}__${suffix}_forward0_warp.nii.gz
    touch ${prefix}__${suffix}_backward0_affine.mat
    touch ${prefix}__${suffix_qc}_mqc.gif

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
        mrtrix: \$(mrinfo -version 2>&1 | sed -n 's/== mrinfo \\([0-9.]\\+\\).*/\\1/p')
        imagemagick: \$(convert -version | sed -n 's/.*ImageMagick \\([0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\.[0-9]\\{1,\\}\\).*/\\1/p')
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
