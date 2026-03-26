process UTILS_EXTRACTB0 {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.2_cpu"

    input:
    tuple val(meta), path(dwi), path(bval), path(bvec)

    output:
    tuple val(meta), path("*_b0.nii.gz")        , emit: b0
    tuple val(meta), path("*_b0_mask.nii.gz")   , emit: b0_mask
    tuple val(meta), path("final.bval")         , emit: bval
    tuple val(meta), path("final.bvec")         , emit: bvec
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def extraction_strategy = task.ext.b0_extraction_strategy ? "--$task.ext.b0_extraction_strategy" : "--mean"
    def b0_threshold = task.ext.b0_threshold ? "--b0_threshold $task.ext.b0_threshold" : ""
    def output_series = task.ext.output_series ? "" : "--single-image"
    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1

    scil_dwi_extract_b0 $dwi $bval $bvec ${prefix}_b0.nii.gz \
        $output_series $extraction_strategy $b0_threshold --skip_b0_check

    scil_volume_math lower_threshold ${prefix}_b0.nii.gz 0.0001 ${prefix}_b0_mask.nii.gz \
        --data_type uint8

    # Simple copy to ensure filename is catched by Nextflow since inputs are excluded.
    cp $bval final.bval
    cp $bvec final.bvec

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_dwi_extract_b0 -h
    scil_volume_math -h

    touch ${prefix}_b0.nii.gz
    touch ${prefix}_b0_mask.nii.gz
    touch final.bval
    touch final.bvec

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
