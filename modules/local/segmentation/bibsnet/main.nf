process SEGMENTATION_BIBSNET {
    tag "$meta.id"
    label 'process_bibsnet'

    conda "${moduleDir}/environment.yml"
    container "gagnonanthony/sf-pediatric-bibsnet:3.7.0"
    containerOptions {
        (workflow.containerEngine == 'docker') ? '--entrypoint ""' : ''
    }

    input:
    tuple val(meta), path(t1), path(t2)

    output:
    tuple val(meta), path("*space-T1w_desc-aseg_dseg.nii.gz")       , emit: t1_dseg, optional: true
    tuple val(meta), path("*space-T1w_desc-brain_mask.nii.gz")      , emit: t1_brain_mask, optional: true
    tuple val(meta), path("*space-T2w_desc-aseg_dseg.nii.gz")       , emit: t2_dseg, optional: true
    tuple val(meta), path("*space-T2w_desc-brain_mask.nii.gz")      , emit: t2_brain_mask, optional: true
    tuple val("${task.process}"), val('bibsnet'), eval('echo $BIBSNET_VERSION'), topic: versions, emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def fsl_bin_path = task.ext.fsl_bin_path ?: "/opt/conda/envs/fsl/bin/"
    def nnunet_path = task.ext.nnunet_path ?: "/opt/venv/bin/nnUNet_predict"
    def cmd_t1 = t1 ? "cp -rL ${t1} ./bids/${prefix}/anat/${prefix}_T1w.nii.gz && touch bids/${prefix}/anat/${prefix}_T1w.json" : ""
    def cmd_t2 = t2 ? "cp -rL ${t2} ./bids/${prefix}/anat/${prefix}_T2w.nii.gz && touch bids/${prefix}/anat/${prefix}_T2w.json" : ""

    """
    # We need to mimick a bids structure for BIBSNet
    mkdir -p bids/${prefix}/anat
    ${cmd_t1}
    ${cmd_t2}

    # Launch BIBSNet
    bibsnet \
        -v \
        bids \
        ./ \
        participant \
        --fsl-bin-path ${fsl_bin_path} \
        --nnUNet ${nnunet_path} \
        --work-dir ./work

    # Copy the output to work dir.
    mv bibsnet/${prefix}/anat/*aseg_dseg.nii.gz ./
    mv bibsnet/${prefix}/anat/*brain_mask.nii.gz ./
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def cmd_t1 = t1 ? "touch ${prefix}_space-T1w_desc-aseg_dseg.nii.gz && touch ${prefix}_space-T1w_desc-brain_mask.nii.gz" : ""
    def cmd_t2 = t2 ? "touch ${prefix}_space-T2w_desc-aseg_dseg.nii.gz && touch ${prefix}_space-T2w_desc-brain_mask.nii.gz" : ""

    """
    bibsnet -h

    # Create empty output files
    ${cmd_t1}
    ${cmd_t2}
    """
}
