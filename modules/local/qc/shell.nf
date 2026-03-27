process QC_SHELL {
    tag "$meta.id"
    label 'process_single'

    container 'scilus/scilpy:2.2.2_cpu'

    input:
    tuple val(meta), path(bval), path(bvec)

    output:
    tuple val(meta), path("*_mqc.png")      , emit: shell
    path "versions.yml"                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_viz_gradients_screenshot --in_gradient_scheme $bvec $bval \
        --out_basename ${prefix}_gradients_mqc --res 600

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}_gradients_mqc.png

    scil_viz_gradients_screenshot -h

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
