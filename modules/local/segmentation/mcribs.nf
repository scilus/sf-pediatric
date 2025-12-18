process SEGMENTATION_MCRIBS {
    tag "$meta.id"
    label 'process_high'

    container 'gagnonanthony/nf-pediatric-mcribs:2.1.0'

    input:
    tuple val(meta), path(t2), path(fs_license), path(t1) // ** T1 is optional ** //

    output:
    tuple val(meta), path("*_mcribs")                   , emit: folder
    tuple val(meta), path("*_preprocessed_T2w.nii.gz")  , emit: anat
    path "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def validage = (meta.age > 27 && meta.age < 44) ? true : false
    def age = validage ? "--subjectage ${Math.round(meta.age)}": "--subjectage 44"
    def useT1 = t1 ? "--useT1" : ""
    def surf = task.ext.surf ? "--surfrecon --inflatesphere --surfreg --surfvol" : ""
    def jointhresh = task.ext.jointhresh ? task.ext.surf ? "--deformablejointhresh ${task.ext.jointhresh}" : "" : ""
    def fastcollision = task.ext.fastcollision ? task.ext.surf ? "--deformablefastcollision" : "" : ""
    def nopialoutside = task.ext.nopialoutside ? task.ext.surf ? "--deformablenoensurepialoutside" : "" : ""
    def cortical = task.ext.cortical ? "--cortribbon --cortparc --cortthickness" : ""
    def aparcaseg = task.ext.aparcaseg? "--aparc2aseg --apas2aseg" : ""
    def stats = task.ext.stats ? "--segstats --parcstats" : ""
    def seed = task.ext.seed ?: "1234"

    """
    # Set freesurfer seed for reproducibility and bind license.
    # export FREESURFER_SEED=$seed
    export FS_LICENSE=\$(realpath $fs_license)

    # MCRIBS requires a specific file structure; creating it.
    mkdir -p RawT2
    cp -rL $t2 RawT2/${prefix}.nii.gz

    # If T1 is provided, copy it to the correct location.
    if [ -n "$t1" ]; then
        mkdir -p RawT1RadiologicalIsotropic
        cp -rL $t1 RawT1RadiologicalIsotropic/${prefix}.nii.gz
    fi

    MCRIBReconAll -nthreads $task.cpus $useT1 \
        --conform \
        --voxelsize "volumepreserve" \
        --tissueseg \
        $age \
        $surf \
        $jointhresh \
        $fastcollision \
        $nopialoutside \
        $cortical \
        $aparcaseg \
        $stats \
        ${prefix}

    # Move the output to the expected location.
    mv freesurfer/${prefix} ${prefix}_mcribs
    mri_convert ${prefix}_mcribs/mri/brain.mgz ${prefix}_preprocessed_T2w.nii.gz

    # If aparc+aseg.mgz exists, convert it to nii.gz.
    if [ -f "${prefix}_mcribs/mri/aparc+aseg.mgz" ]; then
        mri_convert ${prefix}_mcribs/mri/aparc+aseg.mgz ${prefix}_mcribs/mri/aparc+aseg.nii.gz
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mcribs: 2.1.0
        ants: \$(antsRegistration --version |& sed '1!d ; s/ANTs Version: //')
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')
        freesurfer: \$(recon-all --version | grep -oP '\\d+\\.\\d+\\.\\d+')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    mkdir ${prefix}_mcribs
    touch ${prefix}_preprocessed_T2w.nii.gz

    MCRIBReconAll -h

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mcribs: 2.1.0
        ants: \$(antsRegistration --version |& sed '1!d ; s/ANTs Version: //')
        fsl: \$(flirt -version 2>&1 | sed -n 's/FLIRT version \\([0-9.]\\+\\)/\\1/p')
        freesurfer: \$(recon-all --version | grep -oP '\\d+\\.\\d+\\.\\d+')
    END_VERSIONS
    """
}
