process ATLASES_FORMATLABELS {
    tag "$meta.id"
    label 'process_single'

    container "gagnonanthony/nf-pediatric-atlases:1.1.0"

    input:
    tuple val(meta), path(folder), path(utils), path(fs_license)

    output:
    tuple val(meta), path("*labels.nii.gz")     , emit: labels
    tuple val(meta), path("*DK_v1_LUT.txt")     , emit: labels_txt
    tuple val(meta), path("*DK_v1_LUT.json")    , emit: labels_json
    path("*.tsv")                               , emit: stats
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def ses = meta.session ? "_${meta.session}" : ""

    """
    # Exporting the FS license and setting up the environment
    export FS_LICENSE=./license.txt
    export SUBJECTS_DIR=\$(readlink -e ./)
    export UTILS_DIR=\$(readlink -e $utils/freesurfer_utils/)

    mv $folder ${prefix}

    # Creating the label file.
    scil_remove_labels.py ${prefix}/mri/aparc+aseg.nii.gz ${prefix}${ses}__labels.nii.gz \
        -i 4 24 43 159 160 161 162 253 -f

    # By default, labels are in range 1000-2000, let's reformat them.
    scil_combine_labels.py \
        --volume_ids ${prefix}${ses}__labels.nii.gz 1001 2001 1002 2002 1003 2003 \
        1005 2005 1006 2006 1007 2007 1008 2008 1009 2009 1010 2010 \
        1011 2011 1012 2012 1013 2013 1014 2014 1015 2015 1016 2016 1017 2017 \
        1018 2018 1019 2019 1020 2020 1021 2021 1022 2022 1023 2023 1024 2024 \
        1025 2025 1026 2026 1027 2027 1028 2028 1029 2029 1030 2030 1031 2031 \
        1032 2032 1033 2033 1034 2034 1035 2035 18 54 17 53 11 50 13 52 12 51 \
        9 48 16 8 47 \
        --unique ${prefix}${ses}__labels.nii.gz -f

    # Extracting subcortical volume.
    asegstats2table --subjects ${prefix} --meas volume \
        --tablefile ${prefix}${ses}__volume_aseg_subcortical.tsv --no-vol-extras

    # Extracting cortical statistics.
    python3 $utils/convert_fs_stats.py \
        -i ${prefix}/stats/lh.aparc.stats \
        -o ${prefix}${ses}__volume_lh.aparc.tsv \
        -m GrayVol \
        -s ${prefix}
    python3 $utils/convert_fs_stats.py \
        -i ${prefix}/stats/rh.aparc.stats \
        -o ${prefix}${ses}__volume_rh.aparc.tsv \
        -m GrayVol \
        -s ${prefix}
    python3 $utils/convert_fs_stats.py \
        -i ${prefix}/stats/lh.aparc.stats \
        -o ${prefix}${ses}__area_lh.aparc.tsv \
        -m SurfArea \
        -s ${prefix}
    python3 $utils/convert_fs_stats.py \
        -i ${prefix}/stats/rh.aparc.stats \
        -o ${prefix}${ses}__area_rh.aparc.tsv \
        -m SurfArea \
        -s ${prefix}
    python3 $utils/convert_fs_stats.py \
        -i ${prefix}/stats/lh.aparc.stats \
        -o ${prefix}${ses}__thickness_lh.aparc.tsv \
        -m ThickAvg \
        -s ${prefix}
    python3 $utils/convert_fs_stats.py \
        -i ${prefix}/stats/rh.aparc.stats \
        -o ${prefix}${ses}__thickness_rh.aparc.tsv \
        -m ThickAvg \
        -s ${prefix}

    # Copy LUT files
    cp \${UTILS_DIR}/atlas_DK_v1_LUT.json \${UTILS_DIR}/atlas_DK_v1_LUT.txt ./

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def ses = meta.session ? "_${meta.session}" : ""
    """
    export PYTHONPATH=/opt/freesurfer/python/packages:\$PYTHONPATH

    touch ${prefix}${ses}__labels.nii.gz
    touch ${prefix}${ses}__volume_aseg_subcortical.tsv
    touch ${prefix}${ses}__volume_lh.aparc.tsv
    touch ${prefix}${ses}__volume_rh.aparc.tsv
    touch ${prefix}${ses}__area_lh.aparc.tsv
    touch ${prefix}${ses}__area_rh.aparc.tsv
    touch ${prefix}${ses}__thickness_lh.aparc.tsv
    touch ${prefix}${ses}__thickness_rh.aparc.tsv
    touch ${prefix}__DK_v1_LUT.txt
    touch ${prefix}__DK_v1_LUT.json

    scil_remove_labels.py -h
    scil_combine_labels.py -h
    python3 $utils/convert_fs_stats.py -h
    asegstats2table --help

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
    END_VERSIONS
    """
}
