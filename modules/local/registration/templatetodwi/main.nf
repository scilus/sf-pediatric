process REGISTRATION_TEMPLATETODWI {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container 'scilus/scilus:2.2.2'

    input:
    tuple val(meta), path(ref), path(fa), path(moving), path(wm)

    output:
    tuple val(meta), path("*0GenericAffine.mat")        , emit: affine
    tuple val(meta), path("*1Warp.nii.gz")              , emit: warp
    tuple val(meta), path("*1InverseWarp.nii.gz")       , emit: inverse_warp
    tuple val(meta), path("*_warped.nii.gz")            , emit: warped
    tuple val(meta), path("*_mqc.gif")                  , emit: mqc, optional: true
    path "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def run_qc = task.ext.run_qc ? task.ext.run_qc : false
    def suffix = ref.name.contains("T1w") ? "T1w" : "T2w"
    def suffix_qc = task.ext.suffix_qc ?: ""
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$task.cpus
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1
    export ANTS_RANDOM_SEED=1234

    antsRegistration --dimensionality 3 --float 0 --verbose 1\
        --output [output,outputWarped.nii.gz,outputInverseWarped.nii.gz]\
        --interpolation Linear --use-histogram-matching 0\
        --winsorize-image-intensities [0.005,0.995]\
        --initial-moving-transform [$ref,$moving,1]\
        --transform Rigid['0.2']\
        --metric mattes[$ref,$moving,1,32,Regular,0.25]\
        --convergence [10000x10000x10000x10000,1e-6,20] --shrink-factors 8x4x2x1\
        --smoothing-sigmas 3x2x1x0\
        --transform Affine['0.2']\
        --metric mattes[$ref,$moving,1,32,Regular,0.25]\
        --convergence [10000x10000x10000x10000,1e-6,20] --shrink-factors 8x4x2x1\
        --smoothing-sigmas 3x2x1x0\
        --transform SyN[0.2,3,0]\
        --metric CC[$ref,$moving,1,4]\
        --metric CC[$fa,$wm,1,4]\
        --convergence [10000x10000x10000x10000,1e-6,20] --shrink-factors 8x4x2x1\
        --smoothing-sigmas 3x2x1x0

    mv outputWarped.nii.gz ${prefix}__${suffix}_warped.nii.gz
    mv output0GenericAffine.mat ${prefix}__${suffix}_output0GenericAffine.mat
    mv output1InverseWarp.nii.gz ${prefix}__${suffix}_output1InverseWarp.nii.gz
    mv output1Warp.nii.gz ${prefix}__${suffix}_output1Warp.nii.gz

    ### ** QC ** ###
    if $run_qc;
    then
        # Extract dimensions.
        dim=\$(mrinfo ${prefix}__${suffix}_warped.nii.gz -size)
        read sagittal_dim coronal_dim axial_dim <<< "\${dim}"

        # Get middle slices.
        coronal_mid=\$((\$coronal_dim / 2))
        sagittal_mid=\$((\$sagittal_dim / 2))
        axial_mid=\$((\$axial_dim / 2))

        # Set viz params.
        viz_params="--display_slice_number --display_lr --size 256 256"

        mv $ref reference.nii.gz
        # Iterate over images.
        for image in ${suffix}_warped reference;
        do
            scil_viz_volume_screenshot *\${image}.nii.gz \${image}_coronal.png \
                --slices \$coronal_mid --axis coronal \$viz_params
            scil_viz_volume_screenshot *\${image}.nii.gz \${image}_sagittal.png \
                --slices \$sagittal_mid --axis sagittal \$viz_params
            scil_viz_volume_screenshot *\${image}.nii.gz \${image}_axial.png \
                --slices \$axial_mid --axis axial \$viz_params

            if [ \$image != reference ];
            then
                title="Warped"
            else
                title="Reference"
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
            ${suffix}_warped_mosaic.png reference_mosaic.png ${suffix}_warped_mosaic.png \
            ${prefix}_${suffix_qc}_mqc.gif

        # Clean up.
        rm ${suffix}_warped_mosaic.png reference_mosaic.png
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
    def suffix = ref.name.contains("T1w") ? "T1w" : "T2w"
    def suffix_qc = task.ext.suffix_qc ?: ""

    """
    antsRegistration -h

    touch ${prefix}__${suffix}_warped.nii.gz
    touch ${prefix}__${suffix}_output0GenericAffine.mat
    touch ${prefix}__${suffix}_output1InverseWarp.nii.gz
    touch ${prefix}__${suffix}_output1Warp.nii.gz
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
