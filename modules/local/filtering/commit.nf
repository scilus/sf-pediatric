process FILTERING_COMMIT {
    tag "$meta.id"
    label 'process_medium'

    container 'scilus/scilpy@sha256:17ab2a09bc049cea9fc1f04df4b1324f280bed86202092c9f263b742093aa735'

    input:
    tuple val(meta), path(hdf5), path(dwi), path(bval), path(bvec), path(peaks)

    output:
    tuple val(meta), path("*results_bzs")   , emit: results
    tuple val(meta), path("*commit*")       , emit: hdf5
    tuple val(meta), path("*essential*")    , emit: trk

    path "versions.yml"                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def para = String.format("%.2fE-3", meta.ad * 1000)
    def perp = String.format("%.2fE-3", meta.rd * 1000)
    def iso = String.format("%.2fE-3", meta.md * 1000)

    def prefix = task.ext.prefix ?: "${meta.id}"
    def para_diff = task.ext.para_diff ? "--para_diff " + task.ext.para_diff : "--para_diff ${para}"
    def iso_diff = task.ext.iso_diff ? "--iso_diff " + task.ext.iso_diff : "--iso_diff ${iso}"
    def perp_diff = task.ext.perp_diff ? "--perp_diff " + task.ext.perp_diff : "--perp_diff ${perp}"
    def replace_bad_voxels = task.ext.replace_bad_voxels != null ? "--replace_bad_voxels " + task.ext.replace_bad_voxels : ""
    def ball_stick = task.ext.ball_stick ? "--ball_stick" : ""
    def commit2 = task.ext.commit2 ? "--commit2" : ""
    def commit2_lambda = task.ext.commit2_lambda ? "--lambda_commit_2 " + task.ext.commit2_lambda : ""
    def nbr_dir = task.ext.nbr_dir ? "--nbr_dir " + task.ext.nbr_dir : ""
    //def shell_tolerance = task.ext.shell_tolerance ? "--b0_thr " + task.ext.shell_tolerance : ""

    def args_priors = task.ext.ball_stick || task.ext.commit2 ? "$para_diff $iso_diff" : "$para_diff $iso_diff $perp_diff"
    def peaks_arg = peaks ? "--in_peaks $peaks" : ""

    """
    export DIPY_HOME="./"
    export MPLCONFIGDIR="./"

    echo "Parameters used: ${args_priors}"

    scil_tractogram_commit $hdf5 $dwi $bval $bvec "${prefix}__results_bzs/" \
        --processes $task.cpus $args_priors $ball_stick \
        $commit2 $commit2_lambda $nbr_dir $peaks_arg $replace_bad_voxels

    if [ -f "${prefix}__results_bzs/commit_2/decompose_commit.h5" ]; then
        mv "${prefix}__results_bzs/commit_2/decompose_commit.h5" "./${prefix}__decompose_commit.h5"
    else
        mv "${prefix}__results_bzs/commit_1/decompose_commit.h5" "./${prefix}__decompose_commit.h5"
    fi

    if [ -f "${prefix}__results_bzs/commit_2/essential_tractogram.trk" ]; then
        mv "${prefix}__results_bzs/commit_2/essential_tractogram.trk" "./${prefix}__essential.trk"
    else
        mv "${prefix}__results_bzs/commit_1/essential_tractogram.trk" "./${prefix}__essential.trk"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def para = String.format("%.2fE-3", meta.ad * 1000)
    def perp = String.format("%.2fE-3", meta.rd * 1000)
    def iso = String.format("%.2fE-3", meta.md * 1000)

    def prefix = task.ext.prefix ?: "${meta.id}"
    def para_diff = task.ext.para_diff ? "--para_diff " + task.ext.para_diff : "--para_diff ${para}"
    def iso_diff = task.ext.iso_diff ? "--iso_diff " + task.ext.iso_diff : "--iso_diff ${iso}"
    def perp_diff = task.ext.perp_diff ? "--perp_diff " + task.ext.perp_diff : "--perp_diff ${perp}"

    """
    export MPLCONFIGDIR="./"

    touch ${prefix}__commit.h5
    touch ${prefix}__essential.trk
    mkdir ${prefix}__results_bzs

    echo "Parameters used: para_diff: ${para_diff}, iso_diff: ${iso_diff}, perp_diff: ${perp_diff}"

    scil_tractogram_commit -h

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
