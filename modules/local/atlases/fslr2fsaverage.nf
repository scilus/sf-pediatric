process ATLASES_FSLR2FSAVERAGE {
    tag "$meta.id"
    label "process_single"

    container "gagnonanthony/nf-pediatric-atlases:2.0.0"

    input:
        tuple val(meta), path(atlas), path(fslr), path(fsaverage), path(fs_license)

    output:
        tuple val(meta), path("fsaverage_folder")       , emit: fsaverage
        tuple val(meta), path("*_subcortical.nii.gz")   , emit: subcortical
        val("${atlas.name}")                            , emit: atlas_name
        path "versions.yml"                             , emit: versions

    when:
        task.ext.when == null || task.ext.when

    script:
    // By convention, the atlas is a folder named "atlas-<name>". Extracting the name.
    def atlas_name = atlas.getName()

    """
    # We need to copy the inputs since we will be modifying them in-place
    # Otherwise, resume feature of Nextflow will not work properly
    cp -rL ${fsaverage} ./fsaverage_folder

    # Set some env variables.
    export FS_LICENSE=${fs_license}
    export SUBJECTS_DIR=\$(pwd)

    # Set some temp folders
    mkdir -p ./tmp/

    # Start by separating the cifti atlas into label.gii and nii.gz files
    wb_command -cifti-separate ${atlas}/tpl-fsLR/*.dlabel.nii COLUMN \
        -label CORTEX_LEFT tmp/${atlas_name}.L.label.gii \
        -label CORTEX_RIGHT tmp/${atlas_name}.R.label.gii \
        -volume-all ${atlas_name}_subcortical.nii.gz \
        -label ${atlas_name}_subcortical_labels.nii.gz

    mris_convert ./fsaverage_folder/surf/lh.sphere ./fsaverage_folder/surf/lh.sphere.surf.gii
    mris_convert ./fsaverage_folder/surf/rh.sphere ./fsaverage_folder/surf/rh.sphere.surf.gii

    # We need to invert the fsLR -> fsaverage transform
    wb_command -surface-sphere-project-unproject \
        ./fsaverage_folder/surf/lh.sphere.surf.gii \
        $fslr/fs_LR-deformed_to-fsaverage.L.sphere.32k_fs_LR.surf.gii \
        $fslr/fsaverage.L.sphere.32k_fs_LR.surf.gii \
        ./fsaverage_folder/surf/lh.sphere.reg.fslr32k.surf.gii
    wb_command -surface-sphere-project-unproject \
        ./fsaverage_folder/surf/rh.sphere.surf.gii \
        $fslr/fs_LR-deformed_to-fsaverage.R.sphere.32k_fs_LR.surf.gii \
        $fslr/fsaverage.R.sphere.32k_fs_LR.surf.gii \
        ./fsaverage_folder/surf/rh.sphere.reg.fslr32k.surf.gii

    lh_sphere=./fsaverage_folder/surf/lh.sphere.reg.fslr32k.surf.gii
    rh_sphere=./fsaverage_folder/surf/rh.sphere.reg.fslr32k.surf.gii

    # Create a midthickness surface for the fsaverage atlas, needed to map the labels using wb_command
    wb_shortcuts -freesurfer-resample-prep ./fsaverage_folder/surf/lh.white \
        ./fsaverage_folder/surf/lh.pial \
        ./fsaverage_folder/surf/lh.sphere \
        \$lh_sphere \
        ./fsaverage_folder/surf/lh.midthickness.surf.gii \
        ./fsaverage_folder/surf/lh.midthickness.new.surf.gii \
        ./fsaverage_folder/surf/lh.sphere.reg.surf.gii
    wb_shortcuts -freesurfer-resample-prep ./fsaverage_folder/surf/rh.white \
        ./fsaverage_folder/surf/rh.pial \
        ./fsaverage_folder/surf/rh.sphere \
        \$rh_sphere \
        ./fsaverage_folder/surf/rh.midthickness.surf.gii \
        ./fsaverage_folder/surf/rh.midthickness.new.surf.gii \
        ./fsaverage_folder/surf/rh.sphere.reg.surf.gii

    # Now we can resample the labels to fsaverage space using wb_command
    wb_command -label-resample tmp/${atlas_name}.L.label.gii \
        $fslr/fsaverage.L.sphere.32k_fs_LR.surf.gii \
        \$lh_sphere \
        ADAP_BARY_AREA \
        ./fsaverage_folder/label/${atlas_name}.L.fsaverage.label.gii \
        -area-surfs $fslr/fsaverage.L.midthickness_mni.32k_fs_LR.surf.gii ./fsaverage_folder/surf/lh.midthickness.surf.gii
    wb_command -label-resample tmp/${atlas_name}.R.label.gii \
        $fslr/fsaverage.R.sphere.32k_fs_LR.surf.gii \
        \$rh_sphere \
        ADAP_BARY_AREA \
        ./fsaverage_folder/label/${atlas_name}.R.fsaverage.label.gii \
        -area-surfs $fslr/fsaverage.R.midthickness_mni.32k_fs_LR.surf.gii ./fsaverage_folder/surf/rh.midthickness.surf.gii

    # Convert into annot files.
    mris_convert --annot ./fsaverage_folder/label/${atlas_name}.L.fsaverage.label.gii \
        ./fsaverage_folder/surf/lh.midthickness.surf.gii \
        ./fsaverage_folder/label/lh.${atlas_name}.annot
    mris_convert --annot ./fsaverage_folder/label/${atlas_name}.R.fsaverage.label.gii \
        ./fsaverage_folder/surf/rh.midthickness.surf.gii \
        ./fsaverage_folder/label/rh.${atlas_name}.annot

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: 8.2.0
        workbench: \$(wb_command -version | grep -m1 '^Version:' | sed -E 's/^Version:[[:space:]]*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
    END_VERSIONS
    """

    stub:
    // By convention, the top folder is the atlas name, so use it.
    def atlas_name = atlas.getName()
    """
    mkdir fsaverage_folder
    touch ${atlas_name}_subcortical.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: 8.2.0
        workbench: \$(wb_command -version | grep -m1 '^Version:' | sed -E 's/^Version:[[:space:]]*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
    END_VERSIONS
    """
}
