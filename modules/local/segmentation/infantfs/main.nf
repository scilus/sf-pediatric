process SEGMENTATION_INFANTFS {
    tag "$meta.id"
    label 'process_low'
    label 'process_high_memory'

    conda "${moduleDir}/environment.yml"
    container "gagnonanthony/sf-pediatric-infantfs:8.2.0"

    input:
    tuple val(meta), path(anat), path(aseg), path(mask), path(license)

    output:
    tuple val(meta), path("*_infantfs")             , emit: folder
    tuple val(meta), path("*_final_image.nii.gz")   , emit: image
    tuple val("${task.process}"), val('freesurfer'), eval("mri_convert -version | grep 'freesurfer' | sed -E 's/.* ([0-9.]+).*/\\1/'"), topic: versions, emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def ageMonthsInt = meta.age ? (meta.age.toFloat() / 12.0).toInteger() : null
    def age = meta.age ? "--age ${ageMonthsInt}" : task.ext.age ? "--age ${task.ext.age}" : ""
    def newborn = task.ext.newborn ? "--newborn" : ""
    def oneyear = task.ext.oneyear ? "--oneyear" : ""
    def forceskullstrip = task.ext.forceskullstrip ? "--forceskullstrip" : ""
    def mi = task.ext.mi ? "--MI" : ""
    def gmwm = task.ext.gmwm ? "--gmwm" : ""
    def ccseg = task.ext.ccseg ? "--ccseg" : ""
    def nostats = task.ext.nostats ? "--no-stats" : ""
    def intnormFSL = task.ext.intnormFSL ? "--intnormFSL" : ""

    // Mask is needed if aseg is provided, throw an error if not provided
    if (aseg && !mask) {
        throw new Exception("Mask is required if aseg is provided")
    }
    """
    # Setting vars
    export FS_LICENSE=\$(realpath $license)
    export SUBJECTS_DIR="./"
    export USER=freesurfer
    export LOGNAME=freesurfer

    # If aseg is provided, mask the anatomical image with the provided mask
    if [ -f ${aseg} ]; then
        mri_mask $anat $mask ${prefix}_masked.nii.gz
        args="--masked ${prefix}_masked.nii.gz --segfile ${aseg}"
    else
        args=""
    fi

    infant_recon_all \
        -s ${prefix} \
        -i ${anat} \
        -o ${prefix}_infantfs \
        ${age} \
        ${newborn} \
        ${oneyear} \
        ${forceskullstrip} \
        ${mi} \
        ${gmwm} \
        ${ccseg} \
        ${nostats} \
        ${intnormFSL} \
        \$args

    # Move the brain.mgz file to current dir
    mri_convert ${prefix}_infantfs/mri/brain.mgz ${prefix}_final_image.nii.gz
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    infant_recon_all -h

    mkdir -p ${prefix}_infantfs/mri/transforms \
        ${prefix}_infantfs/label/ \
        ${prefix}_infantfs/surf/ \
        ${prefix}_infantfs/stats/ \
        ${prefix}_infantfs/scripts/ \
        ${prefix}_infantfs/tmp/ \
        ${prefix}_infantfs/touch/
    touch ${prefix}_final_image.nii.gz
    """
}
