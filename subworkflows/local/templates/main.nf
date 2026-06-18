def createCohortChannel(channel, cohort) {
    channel.map { folder ->
        def meta = [id: "UNCBCPInfant", cohort: cohort]
        def files = [
            file("${folder}/atlas-Infant${cohort}/*desc-brain_T1w.nii.gz"),
            file("${folder}/atlas-Infant${cohort}/*desc-brain_T2w.nii.gz"),
            file("${folder}/atlas-Infant${cohort}/*WM_probseg.nii.gz"),
            file("${folder}/atlas-Infant${cohort}/*GM_probseg.nii.gz"),
            file("${folder}/atlas-Infant${cohort}/*CSF_probseg.nii.gz"),
            file("${folder}/atlas-Infant${cohort}/*mode-image_xfm.nii.gz")
        ]
        def flattenedFiles = files.flatten().findAll { it -> it.exists() }
        [meta] + flattenedFiles
    }
}

workflow TEMPLATES {

    main:

    ch_versions = channel.empty()
    def templates_path = "${params.templates_download_path}/templates"

    if ( file(templates_path).exists() ) {
        log.info "Templates already exist at ${templates_path}, skipping download."
    } else {
        log.info "Downloading templates..."
        try {
            "mkdir -p ${params.templates_download_path}".execute().waitFor()
            def archivePath = "${params.templates_download_path}/templates.tar.gz"
            def proc_download = ["curl", "-fSL", params.templates_url, "-o", archivePath].execute()
            proc_download.waitFor()
            if ( proc_download.exitValue() != 0 ) {
                error "Failed to download templates: ${proc_download.err.text}"
            }
            def proc_extract = ["tar", "-xzf", archivePath, "-C", "${params.templates_download_path}"].execute()
            proc_extract.waitFor()
            if ( proc_extract.exitValue() != 0 ) {
                error "Failed to extract templates: ${proc_extract.err.text}"
            }
            "rm ${params.templates_download_path}/templates.tar.gz".execute().waitFor()
        } catch (Exception e) {
        error """
        ==========================================================
        ERROR: Failed to fetch templates from:
          ${params.templates_url}

        ${e.message}

        This typically means the compute node has no internet access.
        To resolve this, either:
          1. Run the pipeline once from a node with internet
             (templates will be cached for future runs)
          2. Manually download and extract the archive:
               curl -fSL ${params.templates_url} -o templates.tar.gz
               tar -xzf templates.tar.gz -C ${params.templates_download_path}
          3. Ask your sysadmin to place templates at:
               ${params.templates_download_path}
        ==========================================================
        """.stripIndent()
        }
    }

    // ** Until tpl-UNCBCP4DInfant is available on TemplateFlow, we use ** //
    // ** local folders (in assets/)                                    ** //
    ch_template_folder = channel.fromPath("${templates_path}/", checkIfExists: true)

    ch_cohort0 = createCohortChannel(ch_template_folder, "00")
    ch_cohort3 = createCohortChannel(ch_template_folder, "03")
    ch_cohort6 = createCohortChannel(ch_template_folder, "06")
    ch_cohort12 = createCohortChannel(ch_template_folder, "12")
    ch_cohort24 = createCohortChannel(ch_template_folder, "24")


    emit:
    UNCBCPInfant0              = ch_cohort0     // channel: [ meta, T1w, T2w, wm, gm, csf ]
    UNCBCPInfant3              = ch_cohort3     // channel: [ meta, T1w, T2w, wm, gm, csf ]
    UNCBCPInfant6              = ch_cohort6     // channel: [ meta, T1w, T2w, wm, gm, csf ]
    UNCBCPInfant12             = ch_cohort12    // channel: [ meta, T1w, T2w, wm, gm, csf ]
    UNCBCPInfant24             = ch_cohort24    // channel: [ meta, T1w, T2w, wm, gm, csf ]

    versions = ch_versions                     // channel: [ versions.yml ]
}
