process ATLASES_BRAINNETOMECHILD {
    tag "$meta.id"
    label 'process_medium'

    container "gagnonanthony/nf-pediatric-atlases:1.1.0"

    input:
    tuple val(meta), path(folder), path(utils), path(fs_license)

    output:
    tuple val(meta), path("*brainnetome_child_v1.nii.gz")               , emit: labels
    tuple val(meta), path("*brainnetome_child_v1_dilated.nii.gz")       , emit: labels_dilate
    tuple val(meta), path("*[brainnetome_child]*.txt")                  , emit: labels_txt
    tuple val(meta), path("*[brainnetome_child]*.json")                 , emit: labels_json
    tuple val(meta), path("*BN_Child.stats")                            , emit: stats_files
    tuple val(meta), path("*BN_Child.annot")                            , emit: annot_files
    path("*.tsv")                                                       , emit: stats
    path "versions.yml"                                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def ses = meta.session ? "_${meta.session}" : ""

    """
    # Exporting the FS license and setting up the environment
    export FS_LICENSE=./license.txt
    #export PYTHONPATH=/opt/freesurfer/python/packages:\$PYTHONPATH

    # Setting the logging configs.
    BLUE='\\033[0;34m'
    LRED='\\033[1;31m'
    NC='\\033[0m'
    ColorPrint () { echo -e \${BLUE}\${1}\${NC}; }

    # Copy the input folder (this enables the resume feature of nextflow).
    cp -rL $folder ${prefix}__folder

    # If there already is an annot file in the label folder, remove it.
    rm -f ${prefix}__folder/$prefix/label/lh.BN_Child.annot ${prefix}__folder/$prefix/label/rh.BN_Child.annot

    # Symlink the fsaverage folder if it is not already there.
    if [ ! -d ${prefix}__folder/fsaverage ]; then
        # Sometimes, when using freesurfer, there is an empty fsaverage file.
        if [ -f ${prefix}__folder/fsaverage ]; then
            rm ${prefix}__folder/fsaverage
        fi
        ln -s \$(readlink -e $utils/fsaverage) ${prefix}__folder/
    fi

    # Fetching the required variables.
    export SUBJECTS_DIR=\$(readlink -e ${prefix}__folder)
    export SUBJID=$prefix
    export NBR_PROCESSES=$task.cpus
    export OUT_DIR="Brainnetome_Child"
    export UTILS_DIR=\$(readlink -e $utils/freesurfer_utils/)
    export FS_ID_FOLDER=\${SUBJECTS_DIR}/\${SUBJID}/

    # Make tmp folder because of the LUT
    mkdir -p BN_child_atlas/tmp
    mkdir FS_atlas
    mkdir \${OUT_DIR}

    # ==================================================================================
    # Generate transformation from Freesurfer
    echo "Generate Freesurfer transformation file"
    tkregister2 --mov \${FS_ID_FOLDER}/mri/brain.mgz --noedit --s \${SUBJID} --regheader --reg BN_child_atlas/register.dat >> logfile.txt

    # ==================================================================================
    # Create the Brainnetomme Child cortical parcellation from Freesurfer data
    echo -e "\${BLUE}Create the Brainnetome Child cortical parcellation from Freesurfer data (slow)\${NC}"
    # Compared to the adult version, the BN Child atlas comes in fsaverage space in an annotation format.
    mri_annotation2label --subject fsaverage --hemi lh --outdir BN_child_atlas/tmp/ --annotation \${UTILS_DIR}/lh.BN_child_fsaverage.annot >> logfile.txt &>> logfile.txt
    mri_annotation2label --subject fsaverage --hemi rh --outdir BN_child_atlas/tmp/ --annotation \${UTILS_DIR}/rh.BN_child_fsaverage.annot >> logfile.txt &>> logfile.txt
    rm BN_child_atlas/tmp/*\\?*

    # Then do a surface-based registration to move it to the subject space.
    for i in BN_child_atlas/tmp/l*.*.label;
        do echo mri_label2label --srcsubject fsaverage --srclabel \${i} --trgsubject \${SUBJID} --regmethod surface --hemi lh --trglabel BN_child_atlas/\$(basename \${i}) ' >> logfile.txt' >> cmd.sh; done
    for i in BN_child_atlas/tmp/r*.*.label;
        do echo mri_label2label --srcsubject fsaverage --srclabel \${i} --trgsubject \${SUBJID} --regmethod surface --hemi rh --trglabel BN_child_atlas/\$(basename \${i}) ' >> logfile.txt' >> cmd.sh; done
    # Slow operation, multiprocessing it!
    parallel --will-cite -P \${NBR_PROCESSES} < cmd.sh; rm cmd.sh BN_child_atlas/tmp/*

    # ==================================================================================
    # Merge it into a single .annot file for statistics (the LUT file has to be copied in the tmp folder each time, since freesurfer is modifying it).
    echo -e "\${BLUE}Exporting cortical statistics from the Brainnetome Child atlas\${NC}"
    cp \${UTILS_DIR}/atlas_brainnetome_child_v1_LUT.txt BN_child_atlas/tmp/
    mris_label2annot --s \${SUBJID} --h lh --ctab BN_child_atlas/tmp/atlas_brainnetome_child_v1_LUT.txt --a BN_Child --ldir BN_child_atlas/ >> logfile.txt &>> logfile.txt
    mris_anatomical_stats -mgz -cortex \${FS_ID_FOLDER}/label/lh.cortex.label -f \${FS_ID_FOLDER}/stats/lh.BN_Child.stats -b -a \${FS_ID_FOLDER}/label/lh.BN_Child.annot -c BN_child_atlas/tmp/atlas_brainnetome_child_v1_LUT.txt \${SUBJID} lh white >> logfile.txt &>> logfile.txt
    cp \${UTILS_DIR}/atlas_brainnetome_child_v1_LUT.txt BN_child_atlas/tmp/
    mris_label2annot --s \${SUBJID} --h rh --ctab BN_child_atlas/tmp/atlas_brainnetome_child_v1_LUT.txt --a BN_Child --ldir BN_child_atlas/ >> logfile.txt &>> logfile.txt
    mris_anatomical_stats -mgz -cortex \${FS_ID_FOLDER}/label/rh.cortex.label -f \${FS_ID_FOLDER}/stats/rh.BN_Child.stats -b -a \${FS_ID_FOLDER}/label/rh.BN_Child.annot -c BN_child_atlas/tmp/atlas_brainnetome_child_v1_LUT.txt \${SUBJID} rh white >> logfile.txt &>> logfile.txt

    # Extracting the stats into a tsv file.
    aparcstats2table --subjects \${SUBJID} --hemi=lh -m volume -p BN_Child --tablefile=\${OUT_DIR}/\${SUBJID}${ses}__volume_lh.BN_Child.tsv >> logfile.txt &>> logfile.txt
    aparcstats2table --subjects \${SUBJID} --hemi=rh -m volume -p BN_Child --tablefile=\${OUT_DIR}/\${SUBJID}${ses}__volume_rh.BN_Child.tsv >> logfile.txt &>> logfile.txt
    aparcstats2table --subjects \${SUBJID} --hemi=lh -m thickness -p BN_Child --tablefile=\${OUT_DIR}/\${SUBJID}${ses}__thickness_lh.BN_Child.tsv >> logfile.txt &>> logfile.txt
    aparcstats2table --subjects \${SUBJID} --hemi=rh -m thickness -p BN_Child --tablefile=\${OUT_DIR}/\${SUBJID}${ses}__thickness_rh.BN_Child.tsv >> logfile.txt &>> logfile.txt
    aparcstats2table --subjects \${SUBJID} --hemi=lh -m area -p BN_Child --tablefile=\${OUT_DIR}/\${SUBJID}${ses}__area_lh.BN_Child.tsv >> logfile.txt &>> logfile.txt
    aparcstats2table --subjects \${SUBJID} --hemi=rh -m area -p BN_Child --tablefile=\${OUT_DIR}/\${SUBJID}${ses}__area_rh.BN_Child.tsv >> logfile.txt &>> logfile.txt

    # ==================================================================================
    # Create the Brainnetomme subcortical parcellation from Freesurfer data
    echo -e "\${BLUE}Create the Brainnetomme subcortical parcellation (adult is identical to child version) from Freesurfer data (slow)\${NC}"
    mri_ca_label \${FS_ID_FOLDER}/mri/brain.mgz \${FS_ID_FOLDER}/mri/transforms/talairach.m3z \${UTILS_DIR}/subcortex_BN_atlas.gca BN_child_atlas/BN_atlas_subcortex.nii.gz >> logfile.txt

    # ==================================================================================
    # Convert the *.label to *.nii.gz, very slow because of the cortical ribbon (filling)
    echo -e "\${BLUE}Creating the Brainnetome Child parcellation ROIs by filling up the cortical ribbon (very slow)\${NC}"
    for i in BN_child_atlas/lh*.label;
        do echo mri_label2vol --label \${i} --temp \${FS_ID_FOLDER}/mri/brain.mgz --o \${i/.label/.nii.gz} --subject \${SUBJID} --hemi lh --proj frac 0 1 .1 --fillthresh .3 --reg BN_child_atlas/register.dat --fill-ribbon ' >> logfile.txt' >> cmd.sh
    done
    for i in BN_child_atlas/rh*.label;
        do echo mri_label2vol --label \${i} --temp \${FS_ID_FOLDER}/mri/brain.mgz --o \${i/.label/.nii.gz} --subject \${SUBJID} --hemi rh --proj frac 0 1 .1 --fillthresh .3 --reg BN_child_atlas/register.dat --fill-ribbon ' >> logfile.txt' >> cmd.sh
    done
    # Slow operation, multiprocessing it !
    parallel --will-cite -P \${NBR_PROCESSES} < cmd.sh; rm cmd.sh

    # ==================================================================================
    # Rename and multiply all binary masks so they follow the same convention as split_label_by_ids
    echo "Rename the BN Child cortical ROIs to a simple ids convention"
    python3 \${UTILS_DIR}/utils_rename_parcellation.py BN_child_atlas/*h.*.nii.gz \${UTILS_DIR}/parcellation_names_BN_child.json BN_child_atlas/split_rename/

    # ==================================================================================
    echo -e "\${BLUE}Rename the BN subcortical ROIs to a simple ids convention\${NC}"
    # Split subcortical ids and mix them with the cortical
    mkdir BN_child_atlas/subcortical/
    scil_split_volume_by_ids.py BN_child_atlas/BN_atlas_subcortex.nii.gz --out_dir BN_child_atlas/subcortical/
    for i in BN_child_atlas/subcortical/*.nii.gz;
        do base_name=\$(basename \$i .nii.gz); add_name=\$((\${base_name}-22));
        scil_image_math.py --data_type uint16 --exclude_background subtraction \${i} 22 BN_child_atlas/split_rename/\${add_name}.nii.gz
    done
    rm -r BN_child_atlas/subcortical/

    # ==================================================================================
    echo -e "\${BLUE}Rename the FS wmparc ROIs to a simple ids convention\${NC}"
    mri_convert \${FS_ID_FOLDER}/mri/wmparc.mgz BN_child_atlas/wmparc.nii.gz
    scil_image_math.py convert BN_child_atlas/wmparc.nii.gz BN_child_atlas/wmparc.nii.gz --data_type uint16 -f
    mkdir FS_atlas/split_rename/
    scil_split_volume_by_ids.py BN_child_atlas/wmparc.nii.gz --out_dir FS_atlas/split_rename/

    # ==================================================================================
    echo "Transfert the FS brainstem and cerebellum to BN Child"
    # Add the brainstem to BN (225)
    for i in FS_atlas/split_rename/16.nii.gz;
        do base_name=\$(basename \$i .nii.gz); add_name=\$((\${base_name}+209)); scil_image_math.py --data_type uint16 --exclude_background addition \${i} 209 BN_child_atlas/split_rename/\${add_name}.nii.gz
    done

    # Add the cerebellum to BN (226,227)
    scil_image_math.py --data_type uint16 --exclude_background addition FS_atlas/split_rename/8.nii.gz 218 BN_child_atlas/split_rename/226.nii.gz
    scil_image_math.py --data_type uint16 --exclude_background addition FS_atlas/split_rename/47.nii.gz 180 BN_child_atlas/split_rename/227.nii.gz

    # ==================================================================================
    echo -e "\${BLUE}Combine the labels into a clean Brainnetome atlas\${NC}"
    a=''
    for i in BN_child_atlas/split_rename/*.nii.gz; do a="\${a} --volume_ids \${i} \$(basename \${i} .nii.gz)"; scil_image_math.py convert \${i} \${i} --data_type uint16 -f; done
    scil_combine_labels.py BN_child_atlas/atlas_brainnetome_child.nii.gz \${a}

    # ==================================================================================
    # Since Freesurfer is all in 1x1x1mm and a 256x256x256 array, our atlases must be resampled/reshaped
    echo -e "\${BLUE}Reshape as the original input and convert the final atlases into uint16\${NC}"
    mri_convert \${FS_ID_FOLDER}/mri/native.mgz BN_child_atlas/native.nii.gz
    scil_reshape_to_reference.py BN_child_atlas/atlas_brainnetome_child.nii.gz BN_child_atlas/native.nii.gz BN_child_atlas/atlas_brainnetome_child.nii.gz --interpolation nearest -f

    # ==================================================================================
    # Safer for most script, thats our label data type
    echo -e "\${BLUE}Finished creating the atlas by dilating the label\${NC}"
    scil_image_math.py convert BN_child_atlas/atlas_brainnetome_child.nii.gz \${OUT_DIR}/atlas_brainnetome_child_v1.nii.gz --data_type uint16 -f
    cp \${UTILS_DIR}/atlas_brainnetome_child_v1_*.* \${OUT_DIR}/

    # Compute statistics on subcortical regions.
    mri_convert \${FS_ID_FOLDER}/mri/synthSR.norm.mgz BN_child_atlas/synthSR.norm.nii.gz
    scil_reshape_to_reference.py \${OUT_DIR}/atlas_brainnetome_child_v1.nii.gz BN_child_atlas/synthSR.norm.nii.gz BN_child_atlas/atlas_brainnetome_child_reshaped.nii.gz --interpolation nearest --keep_dtype -f
    mri_segstats --seg BN_child_atlas/atlas_brainnetome_child_reshaped.nii.gz --ctab \${OUT_DIR}/atlas_brainnetome_child_v1_LUT.txt --excludeid 0 \
        --o \${FS_ID_FOLDER}/stats/subcortical.BN_Child.stats --pv \${FS_ID_FOLDER}/mri/synthSR.norm.mgz \
        --id 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227
    asegstats2table --subjects \${SUBJID} --meas=volume \
        --tablefile=\${OUT_DIR}/\${SUBJID}${ses}__volume_BN_Child_subcortical.tsv --all-segs --stats=subcortical.BN_Child.stats

    # Dilating the atlas
    mri_convert \${FS_ID_FOLDER}/mri/brainmask.mgz BN_child_atlas/brain_mask.nii.gz
    scil_image_math.py lower_threshold BN_child_atlas/brain_mask.nii.gz 0.001 BN_child_atlas/brain_mask.nii.gz --data_type uint8 -f
    scil_image_math.py dilation BN_child_atlas/brain_mask.nii.gz 1 BN_child_atlas/brain_mask.nii.gz -f
    scil_reshape_to_reference.py BN_child_atlas/brain_mask.nii.gz BN_child_atlas/native.nii.gz BN_child_atlas/brain_mask.nii.gz --interpolation nearest -f
    scil_image_math.py convert BN_child_atlas/brain_mask.nii.gz BN_child_atlas/brain_mask.nii.gz --data_type uint8 -f

    scil_dilate_labels.py \${OUT_DIR}/atlas_brainnetome_child_v1.nii.gz \${OUT_DIR}/atlas_brainnetome_child_v1_dilated.nii.gz --distance 2 --labels_to_dilate {1..188} {225..227} --mask BN_child_atlas/brain_mask.nii.gz

    echo -e "\${BLUE}Finished creating the atlas.\${NC}"

    # ==================================================================================
    # Copy the results to the output folder
    cp Brainnetome_Child/* ./

    # Fetch .annot files and .stats files, to place within the FastSurfer/FreeSurfer folder.
    mv \${FS_ID_FOLDER}/label/*BN_Child.annot ./
    mv \${FS_ID_FOLDER}/stats/*BN_Child.stats ./

    # Clean up the remaining folders.
    rm -rf BN_child_atlas Brainnetome_Child FS_atlas ${prefix}__folder

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
    touch ${prefix}__brainnetome_child_v1.nii.gz
    touch ${prefix}__brainnetome_child_v1_dilated.nii.gz
    touch ${prefix}__brainnetome_child_v1_LUT.txt
    touch ${prefix}__brainnetome_child_v1_LUT.json
    touch ${prefix}${ses}__volume_BN_Child_subcortical.tsv
    touch ${prefix}${ses}__volume_lh.BN_Child.tsv
    touch ${prefix}${ses}__volume_rh.BN_Child.tsv
    touch ${prefix}${ses}__area_lh.BN_Child.tsv
    touch ${prefix}${ses}__area_rh.BN_Child.tsv
    touch ${prefix}${ses}__thickness_lh.BN_Child.tsv
    touch ${prefix}${ses}__thickness_rh.BN_Child.tsv
    touch lh.BN_Child.annot
    touch rh.BN_Child.annot
    touch lh.BN_Child.stats
    touch rh.BN_Child.stats

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/')
    END_VERSIONS
    """
}
