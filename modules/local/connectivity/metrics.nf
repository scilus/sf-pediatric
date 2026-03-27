process CONNECTIVITY_METRICS {
    tag "$meta.id"
    label 'process_single'

    container 'scilus/scilpy:2.2.2_cpu'

    input:
    tuple val(meta), path(h5), path(labels), path(labels_list), path(metrics)

    output:
    tuple val(meta), path("*.npy"), emit: metrics
    path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def atlas = (meta.age < 0.5 || meta.age > 18) ? "DK" : "BrainnetomeChild"

    if ( metrics ) {
        metrics_list = metrics.join(", ").replace(',', '')

        """
        metrics_args=""

        for metric in $metrics_list; do
            base_name=\$(basename \${metric} .nii.gz)

            # Extract metric type from different patterns
            if [[ "\$base_name" =~ param-([^_]+) ]]; then
                stat="\${BASH_REMATCH[1]}"  # Extract the value after 'desc-'
                stat="stat-\${stat}"
            elif [[ "\$base_name" == *"desc-fwc"* ]]; then
                stat=\${base_name/*__/}  # Extract the value after '__'
                stat="desc-fwc_stat-\${stat}"
            else
                stat=\${base_name/${prefix}__/}  # Fallback to old method
                stat="stat-\${stat}"
            fi

            metrics_args="\${metrics_args} --metrics \${metric} ${prefix}_seg-${atlas}_\${stat}.npy"
        done

        scil_connectivity_compute_matrices $h5 $labels \
            --processes $task.cpus \
            --volume "${prefix}_seg-${atlas}_stat-vol.npy" \
            --streamline_count "${prefix}_seg-${atlas}_stat-sc.npy" \
            --length "${prefix}_seg-${atlas}_stat-len.npy" \
            \$metrics_args \
            --density_weighting \
            --no_self_connection \
            --include_dps ./ \
            --force_labels_list $labels_list

        # Rename commit or afd_fixel files if they exist.
        if [ -f afd_fixel.npy ]; then
            mv afd_fixel.npy ${prefix}_seg-${atlas}_stat-afd_fixel.npy
        fi

        if [ -f commit*.npy ]; then
            mv commit*.npy ${prefix}_seg-${atlas}_stat-commit_weights.npy
        fi

        if [ -f tot_commit*.npy ]; then
            mv tot_commit*.npy ${prefix}_seg-${atlas}_stat-tot_commit_weights.npy
        fi

        # Remove "fit_" from filenames if present (only for .npy files)
        for file in *.npy; do
            if [[ "\$file" == *"fit_"* ]]; then
                new_file=\${file/fit_/}
                # If contains FWF, NDI, ECVF, and ODI, convert to lowercase
                new_file=\$(sed -E 's/(FWF|ODI)/\\L\\1/g' <<< "\$new_file")
                if [[ "\$new_file" == *"NDI"* ]]; then
                    new_file=\$(sed -E 's/NDI/icvf/g' <<< "\$new_file")
                elif [[ "\$new_file" == *"ECVF"* ]]; then
                    new_file=\$(sed -E 's/ECVF/ecvf/g' <<< "\$new_file")
                fi
                mv "\$file" "\$new_file"
            fi
        done

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        END_VERSIONS
        """
    } else {
        """
        scil_connectivity_compute_matrices $h5 $labels \
            --processes $task.cpus \
            --volume "${prefix}_seg-${atlas}_stat-vol.npy" \
            --streamline_count "${prefix}_seg-${atlas}_stat-sc.npy" \
            --length "${prefix}_seg-${atlas}_stat-len.npy" \
            --density_weighting \
            --no_self_connection \
            --include_dps ./ \
            --force_labels_list $labels_list

        # Rename commit or afd_fixel files if they exist.
        if [ -f afd_fixel.npy ]; then
            mv afd_fixel.npy ${prefix}_seg-${atlas}_stat-afd_fixel.npy
        fi

        if [ -f commit*.npy ]; then
            mv commit*.npy ${prefix}_seg-${atlas}_stat-commit_weights.npy
        fi

        if [ -f tot_commit*.npy ]; then
            mv tot_commit*.npy ${prefix}_seg-${atlas}_stat-tot_commit_weights.npy
        fi

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        END_VERSIONS
        """
    }

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def atlas = (meta.age < 2.5 || meta.age > 18) ? "DK" : "BrainnetomeChild"

    if ( metrics ) {
        metrics_list = metrics.join(", ").replace(',', '')

        """
        for metric in $metrics_list; do
            base_name=\$(basename \${metric} .nii.gz)

            # Extract metric type from different patterns
            if [[ "\$base_name" =~ param-([^_]+) ]]; then
                stat="\${BASH_REMATCH[1]}"  # Extract the value after 'desc-'
                stat="stat-\${stat}"
            elif [[ "\$base_name" == *"desc-fwc"* ]]; then
                stat=\${base_name/*__/}  # Extract the value after '__'
                stat="desc-fwc_stat-\${stat}"
            else
                stat=\${base_name/${prefix}__/}  # Fallback to old method
                stat="stat-\${stat}"
            fi

            touch ${prefix}_seg-${atlas}_\${stat}.npy
        done

        # Remove "fit_" from filenames if present (only for .npy files)
        for file in *.npy; do
            if [[ "\$file" == *"fit_"* ]]; then
                new_file=\${file/fit_/}
                # If contains FWF, NDI, ECVF, and ODI, convert to lowercase
                new_file=\$(sed -E 's/(FWF|ODI)/\\L\\1/g' <<< "\$new_file")
                if [[ "\$new_file" == *"NDI"* ]]; then
                    new_file=\$(sed -E 's/NDI/icvf/g' <<< "\$new_file")
                elif [[ "\$new_file" == *"ECVF"* ]]; then
                    new_file=\$(sed -E 's/ECVF/ecvf/g' <<< "\$new_file")
                fi
                mv "\$file" "\$new_file"
            fi
        done

        scil_connectivity_compute_matrices -h

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        END_VERSIONS
        """
    } else {
        """
        touch ${prefix}_seg-${atlas}_stat-vol.npy
        touch ${prefix}_seg-${atlas}_stat-sc.npy
        touch ${prefix}_seg-${atlas}_stat-len.npy

        scil_connectivity_compute_matrices -h

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
        END_VERSIONS
        """
    }
}
