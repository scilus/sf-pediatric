process ATLASES_FSLR2FSAVERAGE {
    tag "meta.id"
    label "process_medium"

    container "gagnonanthony/nf-pediatric-atlases:2.0.0"

    input:
        tuple val(meta), path(atlas), path(fslr), path(fsaverage), path(fs_license)

    output:
        tuple val(meta), path("fsaverage_folder")       , emit: fsaverage
        tuple val(meta), path("*_subcortical.nii.gz")   , emit: subcortical
        val atlas.getName().replaceFirst("atlas-", "")  , emit: atlas_name
        path "versions.yml"                             , emit: versions

    when:
        task.ext.when == null || task.ext.when

    script:
    // By convention, the atlas is a folder named "atlas-<name>". Extracting the name.
    def atlas_name = atlas.getName().replaceFirst("atlas-", "")

    """
    # We need to copy the inputs since we will be modifying them in-place
    # Otherwise, resume feature of Nextflow will not work properly
    cp -rL ${fsaverage} ./fsaverage_folder

    # Set some env variables.
    export FS_LICENSE=${fs_license}

    # Set some temp folders
    mkdir -p ./tmp/

    # Start by separating the cifti atlas into label.gii and nii.gz files
    wb_command -cifti-separate ${atlas}/*.dlabel.nii COLUMN \
        -label CORTEX_LEFT tmp/${atlas_name}.L.label.gii \
        -label CORTEX_RIGHT tmp/${atlas_name}.R.label.gii \
        -volume-all tmp/${atlas_name}_subcortical.nii.gz \
        -label tmp/${atlas_name}_subcortical_labels.nii.gz

    # Convert transformation sphere if we can find one tagged with "fslr32k"
    # Mostly found in alternative fsaverage atlases, such as the one used by MCRIBS
    if [ -f ./fsaverage_folder/surf/*fslr32k ]; then
        mris_convert ./fsaverage_folder/surf/lh.*.fslr32k ./fsaverage_folder/surf/lh.sphere.reg.fslr32k.surf.gii
        mris_convert ./fsaverage_folder/surf/rh.*.fslr32k ./fsaverage_folder/surf/rh.sphere.reg.fslr32k.surf.gii
        lh_sphere=./fsaverage_folder/surf/lh.sphere.reg.fslr32k.surf.gii
        rh_sphere=./fsaverage_folder/surf/rh.sphere.reg.fslr32k.surf.gii
    else
        # TODO: adapt based on normal fsaverage
        lh_sphere=$fslr/
    fi

    # Create a midthickness surface for the fsaverage atlas, needed to map the labels using wb_command
    wb_shortcuts -freesurfer-resample-prep ./fsaverage_folder/surf/lh.white \
        ./fsaverage_folder/surf/lh.pial \
        ./fsaverage_folder/surf/lh.sphere \
        \$lh_sphere \
        ./fsaverage_folder/surf/lh.midthickness.surf.gii \
        ./fsaverage_folder/surf/lh.midthickness.fsLR_32k.surf.gii \
        ./fsaverage_folder/surf/lh.sphere.reg.surf.gii
    wb_shortcuts -freesurfer-resample-prep ./fsaverage_folder/surf/rh.white \
        ./fsaverage_folder/surf/rh.pial \
        ./fsaverage_folder/surf/rh.sphere \
        \$rh_sphere \
        ./fsaverage_folder/surf/rh.midthickness.surf.gii \
        ./fsaverage_folder/surf/rh.midthickness.fsLR_32k.surf.gii \
        ./fsaverage_folder/surf/rh.sphere.reg.surf.gii

    # Now we can resample the labels to fsaverage space using wb_command
    wb_command -label-resample tmp/${atlas_name}.L.label.gii \
        $fslr/fsaverage.L.sphere.32k_fs_LR.surf.gii \
        ./fsaverage_folder/surf/lh.sphere.reg.fslr32k.surf.gii \
        ADAP_BARY_AREA \
        ./fsaverage_folder/label/${atlas_name}.L.fsaverage.label.gii \
        -area-surfs $fslr/fsaverage.L.midthickness.32k_fs_LR.surf.gii ./fsaverage_folder/surf/lh.midthickness.surf.gii
    wb_command -label-resample tmp/${atlas_name}.R.label.gii \
        $fslr/fsaverage.R.sphere.32k_fs_LR.surf.gii \
        ./fsaverage_folder/surf/rh.sphere.reg.fslr32k.surf.gii \
        ADAP_BARY_AREA \
        ./fsaverage_folder/label/${atlas_name}.R.fsaverage.label.gii \
        -area-surfs $fslr/fsaverage.R.midthickness.32k_fs_LR.surf.gii ./fsaverage_folder/surf/rh.midthickness.surf.gii

    # Convert into annot files.
    mris_convert --annot ./fsaverage_folder/label/${atlas_name}.L.fsaverage.label.gii \
        ./fsaverage_folder/surf/lh.midthickness.surf.gii \
        ./fsaverage_folder/label/lh.${atlas_name}.annot
    mris_convert --annot ./fsaverage_folder/label/${atlas_name}.R.fsaverage.label.gii \
        ./fsaverage_folder/surf/rh.midthickness.surf.gii \
        ./fsaverage_folder/label/rh.${atlas_name}.annot

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
        workbench: \$(wb_command -version | grep -m1 '^Version:' | sed -E 's/^Version:[[:space:]]*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
    END_VERSIONS
    """

    stub:
    """
    mkdir fsaverage_folder

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
        workbench: \$(wb_command -version | grep -m1 '^Version:' | sed -E 's/^Version:[[:space:]]*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
    END_VERSIONS
    """
}
