process ATLASES_FSAVERAGE2SUBJECT {
    tag "$meta.id"
    label "process_medium"

    container "gagnonanthony/nf-pediatric-atlases:2.0.0"

    input:
        tuple val(meta), path(fs_folder), path(fsaverage), path(subcortical), path(fs_license)
        each atlas_name

    output:
        tuple val(meta), path("*_fs")                   , emit: folder
        tuple val(meta), path("*dseg.nii.gz")           , emit: dseg
        tuple val(meta), path("*dseg.tsv")              , emit: dseg_tsv
        tuple val(meta), path("*${atlas_name}.tsv")     , emit: tsv
        path "versions.yml"                             , emit: versions

    when:
        task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    # Set some copy of the subject folder since we will be modifying it in-place
    # Otherwise, resume feature of Nextflow will not work properly
    # Look if there is a nested folder within the fs output
    if [ -d ${fs_folder}/mri ]; then
        cp -rL ${fs_folder} ./${prefix}_fs
    else
        mkdir -p ./${prefix}_fs
        cp -rL ${fs_folder}/**/* ./${prefix}_fs/
    fi

    # Set env variables.
    export FS_LICENSE=${fs_license}
    export SUBJECTS_DIR=\$(pwd)

    # Surface-to-surface mapping
    mri_surf2surf --srcsubject \$(basename $fsaverage) --trgsubject ${prefix}_fs \
        --hemi lh --sval-annot ${atlas_name}.annot \
        --o ${atlas_name}.annot
    mri_surf2surf --srcsubject \$(basename $fsaverage) --trgsubject ${prefix}_fs \
        --hemi rh --sval-annot ${atlas_name}.annot \
        --o ${atlas_name}.annot

    # Convert to uint16
    scil_volume_math convert ${subcortical} \
         ${atlas_name}_subcortical_warped.nii.gz --data_type uint16 -f

    # Compute stats for cortical regions
    mris_anatomical_stats -mgz -cortex ${prefix}_fs/label/lh.cortex.label \
        -f ${prefix}_fs/stats/lh.${atlas_name}.stats \
        -b -a ${atlas_name}.annot \
        -c ${atlas_name}_LUT.txt ${prefix}_fs lh white
    mris_anatomical_stats -mgz -cortex ${prefix}_fs/label/rh.cortex.label \
        -f ${prefix}_fs/stats/rh.${atlas_name}.stats \
        -b -a ${atlas_name}.annot \
        -c ${atlas_name}_LUT.txt ${prefix}_fs rh white

    # Convert to tsv files
    aparcstats2table --subjects ${prefix}_fs --hemi=lh -m volume -p ${atlas_name} \
        --tablefile=${prefix}__volume_lh.${atlas_name}.tsv
    aparcstats2table --subjects ${prefix}_fs --hemi=rh -m volume -p ${atlas_name} \
        --tablefile=${prefix}__volume_rh.${atlas_name}.tsv
    aparcstats2table --subjects ${prefix}_fs --hemi=lh -m thickness -p ${atlas_name} \
        --tablefile=${prefix}__thickness_lh.${atlas_name}.tsv
    aparcstats2table --subjects ${prefix}_fs --hemi=rh -m thickness -p ${atlas_name} \
        --tablefile=${prefix}__thickness_rh.${atlas_name}.tsv
    aparcstats2table --subjects ${prefix}_fs --hemi=lh -m area -p ${atlas_name} \
        --tablefile=${prefix}__area_lh.${atlas_name}.tsv
    aparcstats2table --subjects ${prefix}_fs --hemi=rh -m area -p ${atlas_name} \
        --tablefile=${prefix}__area_rh.${atlas_name}.tsv

    # Compute stats for subcortical regions
    mri_segstats --seg ${atlas_name}_subcortical_warped.nii.gz \
        --ctab ${atlas_name}_LUT.txt \
        --excludeid 0 \
        --o ${prefix}_fs/stats/subcortical.${atlas_name}.stats \
        --pv ${prefix}_fs/mri/norm.mgz
    asegstats2table --subjects ${prefix}_fs \
        --meas=volume \
        --tablefile=${prefix}__volume_subcortical.${atlas_name}.tsv \
        --all-segs --stats=subcortical.${atlas_name}.stats

    # Convert the .label files to .nii.gz
    mri_aparc2aseg --new-ribbon --s ${prefix}_fs --annot ${atlas_name} \
        --o ${atlas_name}_cortical_seg.nii.gz --threads $task.cpus --base-offset 5000
    mri_threshold ${atlas_name}_cortical_seg.nii.gz 5000 ${atlas_name}_cortical_seg.nii.gz
    scil_labels_split_volume_by_ids ${atlas_name}_cortical_seg.nii.gz --out_dir tmp/

    # Iterate over the split files, and remove 6000 and 7000 depending if the files starts
    # with 6 or 7
    for file in tmp/*.nii.gz; do
        id=\$(basename \$file .nii.gz)
        case \${id:0:1} in
            6)
                offset=6000
                ;;
            7)
                offset=7000
                ;;
            *)
                exit 1
                ;;
        esac
        outfile="tmp/\$((10#\$id - offset)).nii.gz"
        scil_volume_math subtraction \$file \$offset \$outfile --data_type uint16 --exclude_background -f # TODO: REMOVE
        rm \$file
    done

    # Combine into a clean file.atlas_name
    a=''
    for i in tmp/*.nii.gz; do
        a="\${a} --volume_ids \${i} \$(basename \${i} .nii.gz)"
    done
    scil_labels_combine tmp/${atlas_name}_cortical.nii.gz \$a

    # Blend in the subcortical structures
    scil_labels_combine ${prefix}_seg-${atlas_name}_dseg.nii.gz \
         --volume_ids tmp/${atlas_name}_cortical.nii.gz all \
         --volume_ids ${atlas_name}_subcortical_warped.nii.gz all

    # Rename the files to match BIDS conventions
    mv ${atlas_name}_LUT.txt ${prefix}_seg-${atlas_name}_desc-labels_dseg.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: 8.2.0
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        workbench: \$(wb_command -version | grep -m1 '^Version:' | sed -E 's/^Version:[[:space:]]*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    mkdir -p ${prefix}_fs/mri/transforms \
        ${prefix}_fs/label/ \
        ${prefix}_fs/surf/ \
        ${prefix}_fs/stats/ \
        ${prefix}_fs/scripts/ \
        ${prefix}_fs/tmp/ \
        ${prefix}_fs/touch/

    touch ${prefix}_seg-${atlas_name}_dseg.nii.gz
    touch ${prefix}_seg-${atlas_name}_dseg.tsv

    # Create dummy stats files by creating a few tab-separated columns and values
    for hemi in lh rh; do
        for measure in volume thickness area; do
            printf "id\\tlh_A1\\tlh_A2\\nsub-01\\t1000\\t2000" > ${prefix}__\${measure}_\${hemi}.${atlas_name}.tsv
        done
    done
    printf "id\\tlh_A1\\tlh_A2\\nsub-01\\t1000\\t2000" > ${prefix}__volume_subcortical.${atlas_name}.tsv

    touch ${prefix}_fs/label/lh.${atlas_name}.annot
    touch ${prefix}_fs/label/rh.${atlas_name}.annot
    touch ${prefix}_fs/stats/lh.${atlas_name}.stats
    touch ${prefix}_fs/stats/rh.${atlas_name}.stats
    touch ${prefix}_fs/stats/subcortical.${atlas_name}.stats

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: 8.2.0
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        workbench: \$(wb_command -version | grep -m1 '^Version:' | sed -E 's/^Version:[[:space:]]*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
    END_VERSIONS
    """
}
