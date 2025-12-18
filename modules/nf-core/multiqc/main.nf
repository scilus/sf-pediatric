process MULTIQC {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "multiqc/multiqc:v1.29"

    input:
    tuple val(meta), path(qc_images)
    path  multiqc_files
    path(multiqc_config)
    path(extra_multiqc_config)
    path(multiqc_logo)
    path(replace_names)
    path(sample_names)

    output:
    path "*.html"              , emit: report
    path "*_data"              , emit: data
    path "*_plots"             , optional:true, emit: plots
    path "versions.yml"        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = "${meta.id}-${workflow.start.format('yyMMdd-HHmm')}"
    def config = multiqc_config ? "--config $multiqc_config" : ''
    def extra_config = extra_multiqc_config ? "--config $extra_multiqc_config" : ''
    def logo = multiqc_logo ? "--cl-config 'custom_logo: \"${multiqc_logo}\"'" : ''
    def replace = replace_names ? "--replace-names ${replace_names}" : ''
    def samples = sample_names ? "--sample-names ${sample_names}" : ''
    """
    # Process SC txt files if they exist
    if ls *__sc.txt 1> /dev/null 2>&1; then
        echo -e "Sample Name,SC_Value" > sc_values.csv
        for sc in *__sc.txt; do
            sample_name=\$(basename \$sc __sc.txt)
            sc_value=\$(cat \$sc)
            echo -e "\${sample_name},\${sc_value}" >> sc_values.csv
        done
    fi

    # Process Dice score txt files if they exist
    if ls *__dice.txt 1> /dev/null 2>&1; then
        echo -e "Sample Name,Dice_Score" > dice_values.csv
        for dice in *__dice.txt; do
            sample_name=\$(basename \$dice __dice.txt)
            dice_value=\$(cat \$dice)
            echo -e "\${sample_name},\${dice_value}" >> dice_values.csv
        done
    fi

    shopt -s nullglob
    files=( *__dwi_eddy_restricted_movement_rms.txt )
    shopt -u nullglob

    if [[ \${#files[@]} -gt 0 && "${meta.id}" != "global" ]]; then
        # Subject case: add index + second column
        awk '{print NR "," \$2}' "\${files[0]}" > "${prefix}_fd_mqc.csv"

    elif [[ \${#files[@]} -gt 0 && "${meta.id}" == "global" ]]; then
        # Global case: compute mean per subject
        echo "Sample Name,Mean_FD" > "fd_values.csv"
        for fd_file in "\${files[@]}"; do
            subject_id=\$(basename "\$fd_file" __dwi_eddy_restricted_movement_rms.txt)
            max_fd=\$(awk '{ if (\$2 > max || NR == 1) max = \$2 } END { print max }' "\$fd_file")
            echo "\${subject_id},\${max_fd}" >> "fd_values.csv"
        done
    fi

    multiqc \\
        --force \\
        $args \\
        $config \\
        --filename ${prefix}.html \\
        $extra_config \\
        $logo \\
        $replace \\
        $samples \\
        .

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        multiqc: \$( multiqc --version | sed -e "s/multiqc, version //g" )
    END_VERSIONS
    """

    stub:
    def prefix = "${meta.id}" // No timestamp for stub, otherwise tests will fail
    """
    mkdir ${prefix}_multiqc_data
    mkdir ${prefix}_multiqc_plots
    touch ${prefix}_multiqc_report.html

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        multiqc: \$( multiqc --version | sed -e "s/multiqc, version //g" )
    END_VERSIONS
    """
}
