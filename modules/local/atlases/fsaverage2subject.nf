process ATLASES_FSLR2FSAVERAGE {
    tag "meta.id"
    label "process_medium"

    container "gagnonanthony/nf-pediatric-atlases:2.0.0"

    input:
        tuple val(meta), path(fs_folder), path(fsaverage), path(subcortical), path(transformations, arity: '1..*'), path(fs_license)
        val atlas_name

    output:
        tuple val(meta), path("*dseg.nii.gz")           , emit: dseg
        tuple val(meta), path("*dseg.json")             , emit: json
        tuple val(meta), path("*.stats")                , emit: stats_files
        tuple val(meta), path("*.annot")                , emit: annot_files
        path "*.tsv"                                    , emit: tsv
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
    export SUBJECTS_DIR=$(pwd)

    # Let's compute the inverse from fsaverage to subject space
    if [ -f ${prefix}_fs/surf/lh.sphere.reg2 ]; then
        mris_register -1 -curv ${prefix}_fs/surf/lh.sphere.reg2 ${fsaverage}/surf/lh.sphere ${prefix}_fs/surf/lh.sphere.inv.reg
        mris_register -1 -curv ${prefix}_fs/surf/rh.sphere.reg2 ${fsaverage}/surf/rh.sphere ${prefix}_fs/surf/rh.sphere.inv.reg
    else
        mris_register -1 -curv ${prefix}_fs/surf/lh.sphere.reg ${fsaverage}/surf/lh.sphere ${prefix}_fs/surf/lh.sphere.inv.reg
        mris_register -1 -curv ${prefix}_fs/surf/rh.sphere.reg ${fsaverage}/surf/rh.sphere ${prefix}_fs/surf/rh.sphere.inv.reg
    fi

    # Surface-to-surface mapping
    mri_surf2surf --srcsubject fsaverage --trgsubject ${prefix}_fs \
        --hemi lh --sval-annot ${atlas_name}.annot --cortex \
        --o ${atlas_name}.annot --srcsurfreg sphere.reg --trgsurfreg sphere.inv.reg
    mri_surf2surf --srcsubject fsaverage --trgsubject ${prefix}_fs \
        --hemi rh --sval-annot ${atlas_name}.annot --cortex \
        --o ${atlas_name}.annot --srcsurfreg sphere.reg --trgsurfreg sphere.inv.reg

    # Apply registration to subcortical labels
    antsApplyTransforms -d 3 -i ${subcortical} \
        -r ${prefix}_fs/mri/brain.mgz \
        -o ${atlas_name}_subcortical_warped.nii.gz \
        ${transformations.collect{ t -> "-t $t" }.join(" ")} \
        --interpolation NearestNeighbor

    # Convert to uint16
    scil_volume_math convert ${atlas_name}_subcortical_warped.nii.gz \
         ${atlas_name}_subcortical_warped.nii.gz --data_type uint16 -f

    # Assess if there is a talairach.xfm file, if not, generate an identity transform.
    # TODO: Check if this does not introduce aberrant statistics (by comparing to a subject with a talairach.xfm file).
    if [ ! -f ${prefix}_fs/mri/transforms/talairach.xfm ]
    then
        echo "No talairach.xfm file found, generating an identity transform."
        printf "MNI Transform File\n%% Transform from orig to talairach\n\nTransform_type = Linear;\nLinear_Transform =\n 1.000000 0.000000 0.000000 0.000000 ;\n 0.000000 1.000000 0.000000 0.000000 ;\n 0.000000 0.000000 1.000000 0.000000 ;\n" > ${prefix}_fs/mri/transforms/talairach.xfm
    fi

    # Compute stats for cortical regions
    mris_anatomical_stats -mgz -cortex ${prefix}_fs/label/lh.cortex.label \
        -f ${prefix}_fs/stats/lh.${atlas_name}.stats \
        -b -a ${prefix}_fs/label/lh.${atlas_name}.annot \
        -c ${atlas_name}_LUT.txt ${prefix}_fs lh white
    mris_anatomical_stats -mgz -cortex ${prefix}_fs/label/rh.cortex.label \
        -f ${prefix}_fs/stats/rh.${atlas_name}.stats \
        -b -a ${prefix}_fs/label/rh.${atlas_name}.annot \
        -c ${atlas_name}_LUT.txt ${prefix}_fs rh white

    # Convert to tsv files
    aparcstats2table --subjects ${prefix}_fs --hemi=lh -m volume -p BN_Child \
        --tablefile=${prefix}__volume_lh.${atlas_name}.tsv
    aparcstats2table --subjects ${prefix}_fs --hemi=rh -m volume -p BN_Child \
        --tablefile=${prefix}__volume_rh.${atlas_name}.tsv
    aparcstats2table --subjects ${prefix}_fs --hemi=lh -m thickness -p BN_Child \
        --tablefile=${prefix}__thickness_lh.${atlas_name}.tsv
    aparcstats2table --subjects ${prefix}_fs --hemi=rh -m thickness -p BN_Child \
        --tablefile=${prefix}__thickness_rh.${atlas_name}.tsv
    aparcstats2table --subjects ${prefix}_fs --hemi=lh -m area -p BN_Child \
        --tablefile=${prefix}__area_lh.${atlas_name}.tsv
    aparcstats2table --subjects ${prefix}_fs --hemi=rh -m area -p BN_Child \
        --tablefile=${prefix}__area_rh.${atlas_name}.tsv

    # Compute stats for subcortical regions
    mri_segstats --seg $subcortical \
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
    with 6 or 7
    for file in tmp/*.nii.gz; do
        id=$(basename "\$file" .nii.gz)
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
        scil_volume_math subtraction \$file \$offset \$outfile --data_type uint16 --exclude_background
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
    mv ${atlas_name}_LUT.txt ${prefix}_seg-${atlas_name}_desc-labels_dseg.json
    mv ${prefix}_fs/stats/lh.${atlas_name}.stats ./
    mv ${prefix}_fs/stats/rh.${atlas_name}.stats ./
    mv ${prefix}_fs/stats/subcortical.${atlas_name}.stats ./
    mv ${prefix}_fs/annot/lh.${atlas_name}.annot ./
    mv ${prefix}_fs/annot/rh.${atlas_name}.annot ./

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
        workbench: \$(wb_command -version | grep -m1 '^Version:' | sed -E 's/^Version:[[:space:]]*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}_seg-${atlas_name}_dseg.nii.gz
    touch ${prefix}_seg-${atlas_name}_dseg.json
    touch ${prefix}__volume_lh.${atlas_name}.tsv
    touch ${prefix}__volume_rh.${atlas_name}.tsv
    touch ${prefix}__thickness_lh.${atlas_name}.tsv
    touch ${prefix}__thickness_rh.${atlas_name}.tsv
    touch ${prefix}__area_lh.${atlas_name}.tsv
    touch ${prefix}__area_rh.${atlas_name}.tsv
    touch lh.${atlas_name}.annot
    touch rh.${atlas_name}.annot
    touch lh.${atlas_name}.stats
    touch rh.${atlas_name}.stats
    touch subcortical.${atlas_name}.stats

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
        workbench: \$(wb_command -version | grep -m1 '^Version:' | sed -E 's/^Version:[[:space:]]*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
