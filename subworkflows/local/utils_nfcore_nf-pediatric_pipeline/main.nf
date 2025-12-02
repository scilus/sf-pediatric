//
// Subworkflow with functionality specific to the scilus/nf-pediatric pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN     } from '../../nf-core/utils_nfschema_plugin'
include { paramsSummaryMap          } from 'plugin/nf-schema'
include { samplesheetToList         } from 'plugin/nf-schema'
include { paramsHelp                } from 'plugin/nf-schema'
include { completionEmail           } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { imNotification            } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'
include { UTILS_BIDSLAYOUT          } from '../../../modules/local/utils/bidslayout'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved
    input_bids        //  string: Path to input samplesheet
    bids_script       //  string: Path to BIDS layout script
    help              // boolean: Show help message and exit
    help_full         // boolean: Show full help message and exit
    show_hidden       // boolean: Show hidden parameters in help message

    main:

    ch_versions = Channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //
    command = "nextflow run ${workflow.manifest.name} -profile <tracking,docker,...> --input <BIDS_folder> --outdir <OUTDIR>"

    UTILS_NFSCHEMA_PLUGIN (
        workflow,
        validate_params,
        null,
        help,
        help_full,
        show_hidden,
        "",
        "",
        command
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )

    //
    // Some sanity checks for required inputs.
    //
    if (!input_bids && ( params.segmentation || params.tracking ) ) {
        error "ERROR: Missing input BIDS folder. Please provide a BIDS folder using --input."
    }

    //
    // Ensure a participants.tsv file is present in the bids folder.
    //
    if ( ! file("$input_bids/participants.tsv").exists() && input_bids ) {
        error "ERROR: Your bids dataset does not contain a participants.tsv file. " +
        "Please provide a participants.tsv file with a column indicating the participants' " +
        "age. For any questions, please refer to the documentation at " +
        "https://github.com/scilus/nf-pediatric.git or open an issue!"
    }

    //
    // Create channel from input file provided through params.input
    //
    if ( input_bids ) {
        ch_bids_script = Channel.fromPath(bids_script)
        ch_input_bids = Channel.fromPath(input_bids)
        participant_ids = params.participant_label ?: []

        UTILS_BIDSLAYOUT( ch_input_bids, ch_bids_script )
        ch_versions = ch_versions.mix(UTILS_BIDSLAYOUT.out.versions)

        ch_inputs = UTILS_BIDSLAYOUT.out.layout
            .flatMap{ layout ->
                def json = new groovy.json.JsonSlurper().parseText(layout.getText())
                json.collect { item ->
                    def sid = "sub-" + item.subject

                    def session = item.session ? "ses-" + item.session : ""
                    def run = item.run ? "run-" + item.run : ""
                    def age = item.age ?: ""

                    item.each { _key, value ->
                        if (value == 'todo') {
                            error "ERROR ~ $sid contains missing files, please check the BIDS layout for this subject."
                        }
                    }

                    if ( age == "nan" || age == "" ) {
                        error "ERROR: Age is not entered correctly in the participants.tsv file. Please validate."
                    }

                    // Temp age in years for priors prediction (only if data is over 25, as we assume it is gestational age).
                    def tempAge = age.toFloat() > 25 ? Math.abs((age.toFloat() - 35) / 52) : age.toFloat()
                    def priors = fetchPriors(tempAge)

                    return [
                        [id: sid, session: session, run: run, age: age.toFloat(), fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md],
                        item.t1 ? file(item.t1) : [],
                        item.t2 ? file(item.t2) : [],
                        item.dwi ? file(item.dwi) : [],
                        item.bval ? file(item.bval) : [],
                        item.bvec ? file(item.bvec) : [],
                        item.rev_dwi ? file(item.rev_dwi) : [],
                        item.rev_bval ? file(item.rev_bval) : [],
                        item.rev_bvec ? file(item.rev_bvec) : [],
                        item.rev_topup ? file(item.rev_topup) : []
                    ]
                }
            }
            .filter { meta, _t1, _t2, _dwi, _bval, _bvec, _rev_dwi, _rev_bval, _rev_bvec, _rev_topup ->
                participant_ids.isEmpty() || meta.id in participant_ids
            }

    } else {
        ch_inputs = Channel.empty()
    }

    emit:
    input_bids      = ch_inputs
    versions        = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {

    take:
    email           //  string: email address
    email_on_fail   //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    hook_url        //  string: hook URL for notifications
    multiqc_report  //  string: Path to MultiQC report

    main:
    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def multiqc_reports = multiqc_report.toList()

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(
                summary_params,
                email,
                email_on_fail,
                plaintext_email,
                outdir,
                monochrome_logs,
                multiqc_reports.getVal(),
            )
        }

        completionSummary(monochrome_logs)
        if (hook_url) {
            imNotification(summary_params, hook_url)
        }

        //
        // ** Generate sidecar jsons for all files
        //
        generateSidecarJson( outdir )
    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs: https://nf-co.re/docs/usage/troubleshooting"
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Fetch priors based on age using the following equations:
//    FA = 0.753922 * exp(-0.117753 * exp(-1.486159 * age))
//    AD = 0.001820 * age^-0.047373
//    RD = 0.000432 * age^-0.095184
//    MD = 0.004116 * (1 - exp(-(3243541.309087 * age)^0.012118)) **This is in ventricles, not 1-fiber population**
//
def fetchPriors(age) {
    def fa = 0.753938 * Math.exp(-0.117902 * Math.exp(-1.491989 * age))
    def ad = 0.001835 * Math.pow(age, -0.048725)
    def rd = 0.000430 * Math.pow(age, -0.092705)
    def md = 0.004116 * (1 - Math.exp(-Math.pow((3243541.309087 * age), 0.012118)))

    // Return values as a map and round them.
    return [fa: fa.round(2), ad: ad.round(5), rd: rd.round(6), md: md.round(5)]
}

//
// Generating dataset_description.json file in output folder.
//
def generateDatasetJson() {
    def jsonFile = "${params.outdir}/dataset_description.json"
    def info = [
        Name: "nf-pediatric derivatives",
        BIDSVersion: "1.10.0",
        DatasetType: "derivative",
        GeneratedBy: [
                [
                Name: workflow.manifest.name,
                Version: workflow.manifest.version,
                Date: java.time.LocalDateTime.now().format(java.time.format.DateTimeFormatter.ISO_LOCAL_DATE_TIME),
                Container: [
                    Type: workflow.containerEngine ?: "NA",
                ]
            ]
        ]
    ]
    file(jsonFile).text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(info))

        // Create README.txt
    def readmeFile = "${params.outdir}/README.txt"
    def readmeContent = """# nf-pediatric derivatives

This dataset contains derivatives generated by the nf-pediatric pipeline.

## Dataset Information
- Pipeline: ${workflow.manifest.name}
- Version: ${workflow.manifest.version}
- Generated on: ${java.time.LocalDateTime.now().format(java.time.format.DateTimeFormatter.ISO_LOCAL_DATE_TIME)}
- Container Engine: ${workflow.containerEngine ?: "NA"}
- BIDS Version: 1.10.0

## Description
This derivative dataset was generated using the nf-pediatric Nextflow pipeline for pediatric neuroimaging analysis.

## Contents
The dataset follows the BIDS derivatives specification and contains processed data including:
- Preprocessed anatomical images
- Preprocessed DWI images
- DWI local models (fodf, tensors, etc.)
- Tractography results
- Connectomics
- Segmentation (tissues, and cortical/subcortical parcellations)
- QC reports
- Statistical summaries

## Usage
Please refer to the pipeline documentation for details on how these derivatives were generated and how to interpret the results.

## Citation
If you use this dataset, please cite the nf-pediatric pipeline and any relevant software packages used in the analysis.
"""

    file(readmeFile).text = readmeContent
}

//
// Utils function to fetch a subject ID and session from a BIDS path.
//
def extractBidsInfo(filePath) {
    def pathParts = filePath.toString().split('/')
    def subjectId = pathParts.find { it.startsWith('sub-') }
    def sessionId = pathParts.find { it.startsWith('ses-') }

    return [ subject: subjectId, sessionId: sessionId != null ? sessionId + "/" : '' ]
}

//
// Generating sidecar .json file in output folder.
//
def generateSidecarJson(outputDir) {
    def niftiFiles = []

    // Use Java NIO to recursively find files
    def outputPath = java.nio.file.Paths.get(outputDir)
    if (java.nio.file.Files.exists(outputPath)) {
        java.nio.file.Files.walk(outputPath)
            .filter { path -> path.toString().endsWith('.nii.gz') }
            .forEach { path -> niftiFiles.add(path.toFile()) }
    }

    niftiFiles.each { niftiFile ->

        // ** Extract sub ID and session ID for the file ** //
        def bidsInfo = extractBidsInfo(niftiFile)
        def jsonFile = niftiFile.toString().replace('.nii.gz', '.json')

        if (niftiFile.name.contains("T1w.nii.gz")) {
            def links = []

            def fileNames = file("${params.input}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*T1w.nii.gz")
            def fileList = fileNames instanceof List ? fileNames : [fileNames]
            fileList.each { f ->
                if (f.exists()) {
                    links.add("bids:raw:${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                }
            }

            if (niftiFile.name.contains("space-DWI")) {
                def transforms = file("${params.outdir}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*")
                    .findAll { f ->
                        f.name.contains("to-dwi")
                    }

                def transformsList = transforms instanceof List ? transforms : [transforms]
                transformsList.each { f ->
                if (f.exists()) {
                    links.add("bids::${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                    }
                }
            }
            if (niftiFile.name.contains("space-T2w")) {
                def transforms = file("${params.outdir}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*")
                    .findAll { f ->
                        f.name.contains("T1w_to-T2w")
                    }
                def transformsList = transforms instanceof List ? transforms : [transforms]
                transformsList.each { f ->
                if (f.exists()) {
                    links.add("bids::${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                    }
                }
            }

            def sidecarInfo = [
                Sources: links != [] ? links : "",
                SkullStripped: true
            ]
            file(jsonFile).text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(sidecarInfo))
            }

        if (niftiFile.name.contains("T2w.nii.gz")) {
            def links = []

            def fileNames = file("${params.input}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*T2w.nii.gz")
            def fileList = fileNames instanceof List ? fileNames : [fileNames]
            fileList.each { f ->
                if (f.exists()) {
                    links.add("bids:raw:${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                }
            }

            if (niftiFile.name.contains("space-DWI")) {
                def transforms = file("${params.outdir}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*")
                    .findAll { f ->
                        f.name.contains("to-dwi")
                    }
                def transformsList = transforms instanceof List ? transforms : [transforms]
                transformsList.each { f ->
                if (f.exists()) {
                    links.add("bids::${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                    }
                }
            }
            if (niftiFile.name.contains("space-T1w")) {
                def transforms = file("${params.outdir}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*")
                    .findAll { f ->
                        f.name.contains("T2w_to-T1w")
                    }
                def transformsList = transforms instanceof List ? transforms : [transforms]
                transformsList.each { f ->
                if (f.exists()) {
                    links.add("bids::${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                    }
                }
            }

            def sidecarInfo = [
                Sources: links != [] ? links : "",
                SkullStripped: true
            ]
            file(jsonFile).text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(sidecarInfo))
        }

        if (niftiFile.name.contains("brain_mask.nii.gz")) {
            def links = []

            if (niftiFile.name.contains("dwi")) {
                def fileNames = file("${params.input}/${bidsInfo.subject}/${bidsInfo.sessionId}dwi/*dwi.nii.gz")
                def fileList = fileNames instanceof List ? fileNames : [fileNames]
                fileList.each { f ->
                    if (f.exists()) {
                        links.add("bids:raw:${bidsInfo.subject}/${bidsInfo.sessionId}dwi/${f.name}")
                    }
                }
            } else {
                def fileNames = file("${params.input}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*{T1w,T2w}.nii.gz")
                def fileList = fileNames instanceof List ? fileNames : [fileNames]
                fileList.each { f ->
                    if (f.exists()) {
                        links.add("bids:raw:${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                    }
                }
            }

            def sidecarInfo = [
                Sources: links != [] ? links : "",
                Type: "Brain"
            ]
            file(jsonFile).text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(sidecarInfo))
        }

        if (niftiFile.name.contains("DK_dseg.nii.gz")) {
            def links = []

            def fileNames = file("${params.input}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*T2w.nii.gz")
            def fileList = fileNames instanceof List ? fileNames : [fileNames]
            fileList.each { f ->
                if (f.exists()) {
                    links.add("bids:raw:${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                }
            }

            def preprocFiles = file("${params.outdir}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*preproc_T2w.nii.gz")
            def preprocList = preprocFiles instanceof List ? preprocFiles : [preprocFiles]
            preprocList.each { f ->
                if (f.exists()) {
                    links.add("bids::${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                }
            }

            if (niftiFile.name.contains("space-DWI")) {
                def transforms = file("${params.outdir}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*")
                    .findAll { f ->
                        f.name.contains("to-dwi")
                    }
                def transformsList = transforms instanceof List ? transforms : [transforms]
                transformsList.each { f ->
                if (f.exists()) {
                    links.add("bids::${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                    }
                }
            }

            def sidecarInfo = [
                Sources: links != [] ? links : "",
                Type: "Segmentation",
                Description: "Desikan-Killiany Atlas segmentation"
            ]
            file(jsonFile).text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(sidecarInfo))
        }

        if (niftiFile.name.contains("BrainnetomeChild_dseg")) {
            def links = []
            def dilated = niftiFile.name.contains("dilated") ? " (dilated)" : ""

            def fileNames = file("${params.input}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*{T1w,T2w}.nii.gz")
            def fileList = fileNames instanceof List ? fileNames : [fileNames]
            fileList.each { f ->
                if (f.exists()) {
                    links.add("bids:raw:${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                }
            }

            def preprocFiles = file("${params.outdir}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*preproc_{T1w,T2w}.nii.gz")
            def preprocList = preprocFiles instanceof List ? preprocFiles : [preprocFiles]
            preprocList.each { f ->
                if (f.exists()) {
                    links.add("bids::${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                }
            }

            if (niftiFile.name.contains("space-DWI")) {
                def transforms = file("${params.outdir}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*")
                    .findAll { f ->
                        f.name.contains("to-dwi")
                    }
                def transformsList = transforms instanceof List ? transforms : [transforms]
                transformsList.each { f ->
                if (f.exists()) {
                    links.add("bids::${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                    }
                }
            }

            def sidecarInfo = [
                Sources: links != [] ? links : "",
                Type: "Segmentation",
                Description: "Brainnetome Child Atlas segmentation${dilated}"
            ]
            file(jsonFile).text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(sidecarInfo))
        }

        if (niftiFile.name.contains("label")) {
            def links = []

            def fileNames = file("${params.input}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*{T1w,T2w}.nii.gz")
            def fileList = fileNames instanceof List ? fileNames : [fileNames]
            fileList.each { f ->
                if (f.exists()) {
                    links.add("bids:raw:${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                }
            }

            def preprocFiles = file("${params.outdir}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*space-DWI_preproc_{T1w,T2w}.nii.gz")
            def preprocList = preprocFiles instanceof List ? preprocFiles : [preprocFiles]
            preprocList.each { f ->
                if (f.exists()) {
                    links.add("bids::${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                }
            }

            def transforms = file("${params.outdir}/${bidsInfo.subject}/${bidsInfo.sessionId}anat/*")
                .findAll { f ->
                    f.name.contains("to-dwi")
                }
            def transformsList = transforms instanceof List ? transforms : [transforms]
            transformsList.each { f ->
            if (f.exists()) {
                links.add("bids::${bidsInfo.subject}/${bidsInfo.sessionId}anat/${f.name}")
                }
            }

            def sidecarInfo = [
                Sources: links != [] ? links : "",
                Type: "Segmentation"
            ]
            file(jsonFile).text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(sidecarInfo))
        }

        if (niftiFile.name.contains("preproc_dwi")) {
            def links = []

            def fileNames = file("${params.input}/${bidsInfo.subject}/${bidsInfo.sessionId}dwi/*dwi.nii.gz")
            def fileList = fileNames instanceof List ? fileNames : [fileNames]
            fileList.each { f ->
                if (f.exists()) {
                    links.add("bids:raw:${bidsInfo.subject}/${bidsInfo.sessionId}dwi/${f.name}")
                }
            }

            def sidecarInfo = [
                Sources: links != [] ? links : "",
                SkullStripped: true
            ]
            file(jsonFile).text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(sidecarInfo))
        }

        def patterns = ["ad", "afd", "fa", "fodf", "ga", "md", "mode", "nufo", "peaks", "b0", "pwdavg", "rd", "rgb", "tensor"]

        if (patterns.any { pattern -> niftiFile.name.contains(pattern) }) {
            def links = []

            def fileNames = file("${params.input}/${bidsInfo.subject}/${bidsInfo.sessionId}dwi/*dwi.nii.gz")
            def fileList = fileNames instanceof List ? fileNames : [fileNames]
            fileList.each { f ->
                if (f.exists()) {
                    links.add("bids:raw:${bidsInfo.subject}/${bidsInfo.sessionId}dwi/${f.name}")
                }
            }
            def preprocFiles = file("${params.outdir}/${bidsInfo.subject}/${bidsInfo.sessionId}dwi/*preproc_dwi.nii.gz")
            def preprocList = preprocFiles instanceof List ? preprocFiles : [preprocFiles]
            preprocList.each { f ->
                if (f.exists()) {
                    links.add("bids::${bidsInfo.subject}/${bidsInfo.sessionId}dwi/${f.name}")
                }
            }

            def sidecarInfo = [
                Sources: links != [] ? links : "",
                SkullStripped: true
            ]
            file(jsonFile).text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(sidecarInfo))
        }
    }
}

//
// Generate methods description for MultiQC
//
// Helper: indent multiline HTML so it fits inside the YAML block-scalar (data: |)
def indentForYaml(String text, int spaces = 2) {
    if (!text) return ""
    def indent = ' ' * spaces
    // Prefix every line with the required indent
    return text.replaceAll('(?m)^', indent)
}

//
// Build a dynamic methods boilerplate.
//
def buildMethodsDescription() {
    def enabled = { key -> (params[key] ?: false) as boolean }

    def fragments = [
        dwi_preproc: { ->
            if ( !enabled('tracking') ) return ""
            def parts = []
            parts << """<h5>DWI preprocessing</h5>"""
            parts << "Diffusion weighting imaging (DWI) files were extracted from the input BIDS folder and associated with their corresponding reverse phase-encoded images when available."
            if ( enabled('preproc_dwi_run_denoising') && !enabled('skip_dwi_preprocessing') ) {
                parts << "DWI volumes were denoised using the MP-PCA algorithm (Veraart et al., 2016) implemented in the MRtrix3 toolbox (Tournier et al., 2019)."
            }
            if ( enabled('preproc_dwi_run_degibbs') && !enabled('skip_dwi_preprocessing') ) {
                parts << "Correction for Gibbs ringing artifacts was applied using the method of Kellner et al. (2016) as implemented in MRtrix3 (Tournier et al., 2019)."
            }
            if ( enabled('topup_eddy_run_topup') && !enabled('skip_dwi_preprocessing') ) {
                parts << "Susceptibility-induced distortions were corrected using FSL's TOPUP (Andersson et al., 2003; Jenkinson et al., 2012) when reverse phase-encoded images were available."
            }
            if ( enabled('topup_eddy_run_eddy') && !enabled('skip_dwi_preprocessing') ) {
                parts << "Eddy current and motion correction were performed using FSL's EDDY (Andersson & Sotiropoulos, 2016; Jenkinson et al., 2012); maximum framewise displacement was recorded for quality control purposes."
            }
            if ( enabled('dwi_run_synthstrip') && !enabled('skip_dwi_preprocessing') ) {
                parts << "Brain extraction was performed by applying the deep learning model SynthStrip (Hoopes et al., 2022) on powdered average images. Pediatric-tailored weights were used for very young subjects where applicable (Kelley et al., 2024). The resulting mask was applied to the DWI volumes."
            } else if ( !enabled('dwi_run_synthstrip') ) {
                parts << "Brain extraction was performed using FSL BET on the B0 image; the resulting mask was applied to the DWI volumes."
            }
            if ( enabled('preproc_dwi_run_N4') && !enabled('skip_dwi_preprocessing') ) {
                parts << "Bias field correction was applied using the N4 algorithm (Tustison et al., 2010) from the ANTs toolbox (Tustison et al., 2021) using a b-spline knot per voxel of ${params.dwi_bias_bspline_knot_per_voxel} and a shrink factor of ${params.dwi_bias_shrink_factor}."
            }
            parts << "DWI volumes were normalized using the mean B0 intensity within white matter (FA > ${params.dwi_normalize_fa_mask_threshold}) using MRtrix3 (Tournier et al., 2019)."
            parts << "Preprocessed DWI volumes were resampled to an isotropic voxel size of ${params.dwi_resample_voxel_size} mm."

            return parts.findAll{ it }.join(' ')
        },
        anat_preproc: { ->
            if ( !enabled('tracking') ) return ""
            def parts = []
            parts << """<h5>Anatomical preprocessing</h5>"""
            if ( enabled('preproc_run_denoising') ) {
                parts << "Anatomical T1w and/or T2w images were denoised using the Non-Local Means algorithm (Coupe et al., 2008) as implemented in the DIPY toolbox (Garyfallidis et al., 2014)."
            }
            if ( enabled('preproc_run_N4') ) {
                parts << "Bias field correction was applied using the N4 algorithm (Tustison et al., 2010) from the ANTs toolbox (Tustison et al., 2021) using a b-spline knot per voxel of ${params.t1_bias_bspline_knot_per_voxel} and a shrink factor of ${params.t1_bias_shrink_factor} for the T1w and a b-spline knot per voxel of ${params.t2_bias_bspline_knot_per_voxel} and a shrink factor of ${params.t2_bias_shrink_factor} for the T2w image."
            }
            if ( enabled('preproc_run_resampling') ) {
                parts << "Anatomical images were resampled to an isotropic voxel size of ${params.t1_resample_voxel_size} mm for the T1w and ${params.t2_resample_voxel_size} mm for the T2w image."
            }
            if ( enabled('preproc_run_synthstrip') ) {
                parts << "Brain extraction was performed using SynthStrip (Hoopes et al., 2022); pediatric-tailored weights were used for very young subjects where applicable (Kelley et al., 2024)."
            } else {
                parts << "Brain extraction was performed using ANTs brain extraction (Tustison et al., 2021) with the OASIS template."
            }
            parts << "If both T1w and T2w images were available, they were registered using ANTs (Tustison et al., 2021) using ${params.coreg_transform == "a" ? "an affine" : params.coreg_transform == "r" || params.coreg_transform == "t" ? "a rigid" : "a non-linear"} transform."

            return parts.findAll{ it }.join(' ')

        },
        dti: { ->
            if ( !enabled('tracking') ) return ""
            def parts = []
            parts << """<h5>Diffusion Tensor Imaging (DTI)</h5>"""
            parts << "Diffusion tensor imaging (DTI) models were fitted on the processed volume using the scilpy toolbox (Renauld et al., 2025); fractional anisotropy (FA), axial diffusivity (AD), radial diffusivity (RD), mean diffusivity (MD), mode of anisotropy, and color-coded FA maps were generated."
            if ( enabled('dti_shells') ) {
                parts << "DTI fitting used the following shells: ${params.dti_shells.tokenize().join(', ')}."
            } else {
                parts << "DTI fitting used all available shells under the maximum b-value of ${params.dti_max_shell_value} s/mm²."
            }

            return parts.findAll{ it }.join(' ')
        },
        fodf: { ->
            if ( !enabled('tracking') ) return ""
            def parts = []
            parts << """<h5>Fiber Orientation Distribution Function (fODF)</h5>"""
            parts << "Fiber orientation distribution functions (fODF) were computed using the scilpy toolbox (Renauld et al., 2025) using the ${params.fodf_set_method ? "single-shell single-tissue method" : "multi-shell multi-tissue method"} on the ${params.fodf_shells ? "following shells: " + params.fodf_shells.tokenize().join(', ') : "all available shells over the minimum b-value of " + params.fodf_min_fodf_shell_value + " s/mm²"}."
            parts << "fODF were computed using a maximum spherical harmonic order of ${params.fodf_sh_order} in basis ${params.fodf_sh_basis}."
            parts << "Fiber response functions were estimated based on normative curves of the brain's diffusivities through the developmental age-range as described in Gagnon et al. 2025."

            return parts.findAll{ it }.join(' ')
        },
        registration: { ->
            if ( !enabled('tracking') ) return ""
            def parts = []
            parts << """<h5>Registration to DWI space</h5>"""
            parts << "Anatomical images were registered to the preprocessed DWI space using ANTs (Tustison et al., 2021). For younger participants (< 2.5 years old), the T2w image, if available, was preferred for registration due to better tissue contrast. If used, the T2w image was registered using non-linear methods using the mean diffusivity map and B0 image as targets. For older participants or if only T1w images were available, the T1w image was registered using non-linear methods with the FA map and B0 image as targets."

            return parts.findAll{ it }.join(' ')
        },
        tissue_segmentation: { ->
            if ( !enabled('tracking') ) return ""
            def parts = []
            parts << """<h5>Tissue segmentation</h5>"""
            parts << "Tissue segmentation into white matter, grey matter, and cerebrospinal fluid was performed on the anatomical images registered to DWI space."
            parts << "For younger participants (< 2.5 years old), segmentation was performed by registering age-matched templates from the UNC/UMN Baby Connectome Project (Chen et al., 2022)."
            parts << "Briefly, templates closest to the participant's age were non-linearly registered to the participant's anatomical images using ANTs (Tustison et al., 2021), and the resulting transforms were applied to the corresponding tissue probability maps."
            parts << "The resulting maps were then thresholded to generate binary masks for each tissue type."
            parts << "For older participants, tissue segmentation was performed using the FAST algorithm from FSL (Zhang et al., 2001; Jenkinson et al., 2012). Similarly to younger participants, resulting probability maps were thresholded to obtain binary masks."

            return parts.findAll{ it }.join(' ')
        },
        tracking: { ->
            if ( !enabled('tracking') ) return ""
            def parts = []
            parts << """<h5>Tractography</h5>"""
            parts << "Whole-brain tractography was performed using the scilpy toolbox (Renauld et al., 2025)."
            if ( enabled('run_pft_tracking') ) {
                parts << "Particle Filter Tracking (PFT) was used to leverage anatomical priors from the tissue segmentation to improve streamline generation (Girard et al., 2014)."
                parts << "Tracking seeds were randomly placed ${params.pft_seeding_mask_type == "wm" ? "within the white matter mask" : params.pft_seeding_mask_type == "interface" ? "at the grey matter-white matter interface" : "in voxels with FA values over ${params.pft_fa_threshold}"} with a density of ${params.pft_seeding_type == "npv" ? "${params.pft_nbr_seeds} seeds per voxel." : "${params.pft_nbr_seeds} seeds total."}"
                parts << "Streamlines were propagated using a ${params.pft_algo == "prob" ? "probabilistic" : "deterministic"} algorithm with a step size of ${params.pft_step} mm, a maximum angle between steps of ${params.pft_theta}°, a minimum length of ${params.pft_min_len} mm, and a maximum length of ${params.pft_max_len} mm."
            }
            if ( enabled('run_local_tracking') ) {
                parts << "Local tracking was performed using a ${params.local_algo == "prob" ? "probabilistic" : "deterministic"} algorithm using ${params.local_seeding_type == "npv" ? "${params.local_nbr_seeds} seeds per voxel" : "${params.local_nbr_seeds} seeds total."}."
                parts << "The seeding mask was defined as ${params.local_seeding_mask_type == "wm" ? "the white matter mask" : "voxels with FA values over ${params.local_fa_threshold}"}."
                parts << "Similarly, the tracking mask, in which tracking is allowed, was defined as ${params.local_tracking_mask_type == "wm" ? "the white matter mask" : "voxels with FA values over ${params.local_fa_threshold}"}."
                parts << "Streamlines were propagated with a step size of ${params.local_step} mm, a maximum angle between steps of ${params.local_theta}°, a minimum length of ${params.local_min_len} mm, and a maximum length of ${params.local_max_len} mm."
            }
            if ( enabled('run_pft_tracking') && enabled('run_local_tracking') ) {
                parts << "The resulting two tractograms from both methods were then concatenated to form the final whole-brain tractogram."
            }

            return parts.findAll{ it }.join(' ')
        },
        bundling: { ->
            if ( !enabled('bundling') ) return ""
            def parts = []
            parts << """<h5>Bundle segmentation</h5>"""
            if ( !enabled('atlas_directory') ) {
                parts << "The closest age-matched white matter atlas (neonates, 3 months, 6 months, 12 months, 24 months or children) was registered into subject-space using an affine transformation. Whole-brain tractograms were segmented using BundleSeg from the scilpy toolbox (St-Onge et al., 2023; Renauld et al., 2025) with a minimal vote ratio of ${params.minimal_vote_ratio}, an outlier threshold of ${params.outlier_alpha}, and the ${params.use_hyperplane ? "hyperplane method" : params.use_manhattan ? "manhattan distance" : "euclidean distance"}."
            } else {
                parts << "The provided atlas located at ${params.atlas_directory} was registered in subject-space using an affine transformation. Whole-brain tractograms were segmented using BundleSeg from the scilpy toolbox (St-Onge et al., 2023; Renauld et al., 2025) with a minimal vote ratio of ${params.minimal_vote_ratio}, an outlier threshold of ${params.outlier_alpha}, and the ${params.use_hyperplane ? "hyperplane method" : params.use_manhattan ? "manhattan distance" : "euclidean distance"}."
            }
            parts << "Extracted bundles were then filtered to remove invalid streamlines, single point streamlines, and overlapping points."
            parts << "Then, fixel-based apparent fiber density was computed for each bundle (Raffelt et al., 2017)."

            return parts.findAll{ it }.join(' ')
        },
        tractometry: { ->
            if ( !enabled('bundling') ) return ""
            def parts = []
            parts << """<h5>Tractometry</h5>"""
            if ( !enabled('atlas_directory') ) {
                parts << "Atlas' centroids were registered into subject-space using an affine transformation."
            } else {
                parts << "For each extracted bundle, the centroid was extracted using the scilpy toolbox (Renauld et al., 2025)."
            }
            parts << "The centroids were then resampled to ${params.nb_points} points, enabling the derivation of per point metrics."
            if ( enabled('density_weighting') ) {
                parts << "Metric derived per bundle or per point were weighted based on the number of streamline passing through the voxel. This reduces the impact of spurious streamlines on final metric value."
            }
            parts << "For each bundle, multiple metrics were extracted:"
            if ( enabled('length_stats') ) {
                parts << "length,"
            }
            if ( enabled('endpoints_stats') ) {
                parts << "statistic for each endpoint,"
            }
            if ( enabled('means_std') ) {
                parts << "mean (standard deviation),"
            }
            if ( enabled('volume') ) {
                parts << "volume,"
            }
            if ( enabled('streamline_count') ) {
                parts << "and streamline count."
            }
            parts << "For each point per bundle (${params.nb_points} points), the following metric were extracted:"
            if ( enabled('volume_per_labels') ) {
                parts << "volume,"
            }
            if ( enabled('mean_std_per_point') ) {
                parts << "and mean (standard deviation)."
            }
            parts << "Final segmented bundles were colored per point using the ${params.colormap} colormap (affects only the visualisation)."

            return parts.findAll{ it }.join(' ')
        },
        segmentation: { ->
            if ( !enabled('segmentation') ) return ""
            def parts = []
            parts << """<h5>Cortical and sub-cortical segmentation</h5>"""
            parts << "Cortical and subcortical segmentation was performed using ${params.method == "fastsurfer" ? "FastSurfer (Henschel et al., 2020)" : params.method == "recon-all" ? " recon-all from FreeSurfer (Fischl, 2012)" : "recon-all-clinical from Freesurfer (Fischl, 2012; Billot et al., 2023; Iglesias et al., 2023)"} on the T1w anatomical images."
            parts << "Following segmentation, the Brainnetome Child Atlas (Li et al., 2023) was mapped in subject-space using surface-based registration methods from FreeSurfer (Fischl, 2012) and then converted into voxel labels."
            parts << "For each parcels, volume, surface area, and cortical thickness were measured and outputted in tab-separated value files."
            parts << "For younger participants (< 3 months old), cortical and sub-cortical segmentation was performed using the M-CRIB-S pipeline (Adamson et al., 2020)."
            parts << "Younger participants were segmented using an atlas compatible with the Desikan-Killiany (Desikan et al., 2006) and Desikan-Killiany-Tourvile atlases (Klein et al., 2012, Adamson et al., 2020)."
            parts << "Following segmentation, volume, surface area, and cortical thickness were measured for each parcel and outputted in tab-separated value files."

            return parts.findAll{ it }.join(' ')
        },
        connectomics: { ->
            if ( !enabled('connectomics') ) return ""
            def parts = []
            parts << """<h5>Connectomics</h5>"""
            parts << "Structural connectivity matrices were generated using the scilpy toolbox (Renauld et al., 2025) based on the Brainnetome Child Atlas (Li et al., 2023) or the Desikan-Killiany atlas (Desikan et al., 2006) depending on the participant's age."
            parts << "For each participant, labels in anatomical space were first registered in diffusion space using the already computed transformations with a ${params.labels_interpolation == "NearestNeighbor" ? "nearest neighbor interpolation method" : "${params.labels_interpolation}"}."
            parts << "Then, the final tractogram was decomposed into individual connections by extracting each streamline connecting a pair of parcels."
            if ( !enabled('decompose_no_pruning') ) {
                parts << "Streamlines shorter than ${params.decompose_min_len} mm or longer than ${params.decompose_max_len} mm were discarded."
            }
            if ( !enabled('decompose_no_remove_loops') ) {
                parts << "Loops were removed."
            }
            if ( !enabled('decompose_no_remove_outliers') ) {
                parts << "Hierarchical QuickBundles was used to remove outliers using a threshold of ${params.decompose_outlier_threshold}."
            }
            if ( !enabled('decompose_no_remove_curv') ) {
                parts << "Curvature-based filtering was applied to remove streamlines with sharp curves using a maximum angle of ${params.decompose_max_angle}° over ${params.decompose_max_curv} mm."
            }
            parts << "To mitigate the risk of false-positive connections, COMMIT (Daducci et al., 2015) was applied to the tractogram using the ${params.commit_ball_stick ? "ball and stick" : "stick, zeppelin, and ball"} model to optimize the fit between the tractogram and the diffusion data."
            parts << "Diffusivity parameters for COMMIT were set based on age-specific normative values as described in Gagnon et al. 2025."
            if ( enabled('run_commit2') ) {
                parts << "Using COMMIT2 (Schiavi et al., 2020) with a clustering prior strength of ${params.commit2_lambda}, the contribution of each streamline to the diffusion signal was evaluated and streamlines with zero contribution were removed from the tractogram to further reduce false-positive connections."
            } else {
                parts << "The contribution of each streamline to the diffusion signal was evaluated and streamlines with zero contribution were removed from the tractogram to further reduce false-positive connections."
            }
            parts << "To obtain the fODF amplitude specific to each connection, fixel-based apparent fiber density was computed for each extracted connection (Raffelt et al., 2017)."
            parts << "Finally, structural connectivity matrices were generated by computing, for each pair of parcels, the number of streamlines, the mean streamline length, and the mean FA, AD, RD, MD, total apparent fiber density, number of fiber orientation, and fixel-based apparent fiber density."

            return parts.findAll{ it }.join(' ')
        }
    ]

    def pieces = fragments.collect { _, c -> try { c() } catch(Exception e) { "" } }.findAll { it && it.trim() }

    def html = """<div class="nf-pediatric-methods">
${pieces.join('\n\n')}
</div>"""

    return html
}

//
// Generate bibliography based on citations found in the methods description.
//
def toolBibliographyText() {
    // Build the methods HTML so we can inspect which citations were actually used
    def raw_methods = buildMethodsDescription()

    if (!raw_methods) return ""

    // Regex to capture common author-year citation tokens as they appear in the methods text.
    // Matches patterns like "Tournier et al., 2019", "Andersson & Sotiropoulos, 2016", "Fischl, 2012"
    def citationPattern = ~/(?m)\b([A-Z][A-Za-z'’\.\-]+(?:\s+(?:et al\.|&\s*[A-Z][A-Za-z'’\.\-]+|and\s+[A-Z][A-Za-z'’\.\-]+|[A-Z][A-Za-z'’\.\-]+)?)?,\s*\d{4})\b/

    def found = []
    def m = raw_methods =~ citationPattern
    m.each { match ->
        // match[1] contains the captured author-year token
        def token = match[1].trim()
        // normalize certain whitespace/characters
        token = token.replaceAll("\\s+", " ")
        found << token
    }
    found = found.findAll{ it }.unique()

    // Map of known tokens -> full bibliographic <li> entries.
    // Add or update entries here as you need (these are the common citations used across the methods).
    def bibMap = [
        // Tools & big toolboxes (some from your original list)
        "Tournier et al., 2019"       : "<li>Tournier, J.-D., Smith, R., Raffelt, D., Tabbara, R., Dhollander, T., Pietsch, M., Christiaens, D., Jeurissen, B., Yeh, C.-H., & Connelly, A. (2019). MRtrix3: A fast, flexible and open software framework for medical image processing and visualisation. <i>NeuroImage</i>, 202, 116137. <a href=https://doi.org/10.1016/j.neuroimage.2019.116137>https://doi.org/10.1016/j.neuroimage.2019.116137</a></li>",
        "Jenkinson et al., 2012"      : "<li>Jenkinson, M., Beckmann, C. F., Behrens, T. E. J., Woolrich, M. W., & Smith, S. M. (2012). FSL. <i>NeuroImage</i>, 62(2), 782–790. <a href=https://doi.org/10.1016/j.neuroimage.2011.09.015>https://doi.org/10.1016/j.neuroimage.2011.09.015</a></li>",
        "Tustison et al., 2010"       : "<li>Tustison, N. J., Avants, B. B., Cook, P. A., Zheng, Y., Egan, A., Yushkevich, P. A., & Gee, J. C. (2010). N4ITK: Improved N3 bias correction. <i>IEEE Transactions on Medical Imaging</i>, 29(6), 1310–1320. <a href=https://doi.org/10.1109/TMI.2010.2046908>https://doi.org/10.1109/TMI.2010.2046908</a></li>",
        "Tustison et al., 2021"       : "<li>Tustison, N. J., Cook, P. A., Holbrook, A. J., Johnson, H. J., Muschelli, J., Devenyi, G. A., Duda, J. T., Das, S. R., Cullen, N. C., Gillen, D. L., Yassa, M. A., Stone, J. R., Gee, J. C., & Avants, B. B. (2021). The ANTsX ecosystem for quantitative biological and medical imaging. <i>Scientific Reports</i>, 11, 9068. <a href=https://doi.org/10.1038/s41598-021-87564-6>https://doi.org/10.1038/s41598-021-87564-6</a></li>",
        "Veraart et al., 2016"        : "<li>Veraart J, Novikov DS, Christiaens D, Ades-Aron B, Sijbers J, Fieremans E. (2016). Denoising of diffusion MRI using random matrix theory. <i>NeuroImage</i>, 142, 394–406. <a href=https://doi.org/10.1016/j.neuroimage.2016.08.016>https://doi.org/10.1016/j.neuroimage.2016.08.016</a></li>",
        "Kellner et al., 2016"        : "<li>Kellner, E., Dhital, B., Kiselev, V. G., & Reisert, M. (2016). Gibbs-ringing artifact removal based on local subvoxel-shifts. <i>Magnetic Resonance in Medicine</i>, 76(5), 1574–1581. <a href=https://doi.org/10.1002/mrm.26054>https://doi.org/10.1002/mrm.26054</a></li>",
        "Andersson et al., 2003"     : "<li>Andersson, J. L. R., Skare, S., & Ashburner, J. (2003). How to correct susceptibility distortions in spin-echo echo-planar images: application to diffusion tensor imaging. <i>NeuroImage</i>, 20(2), 870–888. <a href=https://doi.org/10.1016/S1053-8119(03)00336-7>https://doi.org/10.1016/S1053-8119(03)00336-7</a></li>",
        "Andersson & Sotiropoulos, 2016": "<li>Andersson, J. L. R., & Sotiropoulos, S. N. (2016). An integrated approach to correction for off-resonance effects and subject movement in diffusion MR imaging. <i>NeuroImage</i>, 125, 1063–1078. <a href=https://doi.org/10.1016/j.neuroimage.2015.10.019>https://doi.org/10.1016/j.neuroimage.2015.10.019</a></li>",
        "Hoopes et al., 2022"        : "<li>Hoopes A, Mora JS, Dalca AV, Fischl B, & Hoffmann M. (2022). SynthStrip: Skull-stripping for any brain image. <i>NeuroImage</i>, 260, 119474, <a href=https://doi.org/10.1016/j.neuroimage.2022.119474>https://doi.org/10.1016/j.neuroimage.2022.119474</a></li>",
        "Kelley et al., 2024"        : "<li>Kelley, W., Ngo, N., Dalca., A. V., Fischl, B., Zöllei, L., & Hoffmann, M. (2024). Boosting Skull-Stripping Performance for Pediatric Brain Images. [Preprint] <i>arXiv</i>, <a href=https://doi.org/10.48550/arXiv.2402.16634>https://doi.org/10.48550/arXiv.2402.16634</a></li>",
        "Coupe et al., 2008"         : "<li>Coupe, P., Yger, P., Prima, S., Hellier, P., Kervrann, C., & Barillot, C. (2008). An optimized blockwise nonlocal means denoising filter for 3-D magnetic resonance images. <i>IEEE Transactions on Medical Imaging</i>, 27(4), 425–441. <a href=https://doi.org/10.1109/TMI.2007.906087>https://doi.org/10.1109/TMI.2007.906087</a></li>",
        "Garyfallidis et al., 2014"   : "<li>Garyfallidis, E., Brett, M., Amirbekian, B., Rokem, A., van der Walt, S., Descoteaux, M., & Nimmo-Smith, I.; Dipy Contributors. (2014). Dipy, a library for the analysis of diffusion MRI data. <i>Frontiers in Neuroinformatics</i>, 8, 8. <a href=https://doi.org/10.3389/fninf.2014.00008>https://doi.org/10.3389/fninf.2014.00008</a></li>",
        "Girard et al., 2014"        : "<li>Girard, G., Whittingstall, K., Deriche, R., & Descoteaux, M. (2014). Towards quantitative connectivity analysis: reducing tractography biases. <i>NeuroImage</i>, 98, 266–278. <a href=https://doi.org/10.1016/j.neuroimage.2014.04.074>https://doi.org/10.1016/j.neuroimage.2014.04.074</a></li>",
        "St-Onge et al., 2023"      : "<li>St-Onge, E., Schilling, K. G., Rheault, F. (2023). BundleSeg: A versatile, reliable and reproducible approach to white matter bundle segmentation. [Preprint] <i>arXiv</i>, <a href=https://doi.org/10.48550/arXiv.2308.10958>https://doi.org/10.48550/arXiv.2308.10958</a></li>",
        "Raffelt et al., 2017"       : "<li>Raffelt, D. A., Tournier, J.-D., Smith, R. E., Vaughan, D.N., Jackson, G., Ridgway, G.R., Connelly, A. (2017). Investigating white matter fibre density and morphology using fixel-based analysis. <i>NeuroImage</i>, 144, 58–73. <a href=https://doi.org/10.1016/j.neuroimage.2016.09.029>https://doi.org/10.1016/j.neuroimage.2016.09.029</a></li>",
        "Daducci et al., 2015"       : "<li>Daducci, A., Dal Palu, A., Lemkaddem, A., Thiran, J.P. (2015). COMMIT: Convex optimization modelling for microstructure informed tractography. <i>IEEE Transactions on Medical Imaging</i>, 34, 246–257. <a href=https://doi.org/10.1109/TMI.2014.2352414>https://doi.org/10.1109/TMI.2014.2352414</a></li>",
        "Schiavi et al., 2020"      : "<li>Schiavi, S., Ocampo-Pineda, M., Barakovic, M., Petit, L., Descoteaux, M., Thiran, J.P., Daducci, A. (2020). A new method for accurate in vivo mapping of human brain connections using microstructural and anatomical information. <i>Science Advances</i>, 6(31). <a href=https://doi.org/10.1126/sciadv.aba8245>https://doi.org/10.1126/sciadv.aba8245</a></li>",
        "Li et al., 2023"           : "<li>Li, W., Fan, L., Shi, W., Lu, Y., Li, J., Luo, N., Wang, H., Chu, C., Ma, L., Song, M., Li, K., Cheng, L., Cao, L., Jiang, T. (2023). Brainnetome atlas of preadolescent children based on anatomical connectivity profiles. <i>Cerebral Cortex</i>, 33(9), 5264-5275. <a href=https://doi.org/10.1093/cercor/bhac415>https://doi.org/10.1093/cercor/bhac415</a></li>",
        "Desikan et al., 2006"      : "<li>Desikan, R.S., Ségonne, F., Fischl, B., Quinn, B.T., Dickerson, B.C., Blacker, D., Buckner, R.L., Dale, A.M., Maguire, R.P., Hyman, B.T., Albert, M.S., Killiany, R.J. (2006). An automated labeling system for subdividing the human cerebral cortex on MRI scans into gyral based regions of interest. <i>NeuroImage</i>, 31(3), 968–980. <a href=https://doi.org/10.1016/j.neuroimage.2006.01.021>https://doi.org/10.1016/j.neuroimage.2006.01.021</a></li>",
        "Zhang et al., 2001"        : "<li>Zhang, Y., Brady, M., & Smith, S. (2001). Segmentation of brain MR images through a hidden Markov random field model and the expectation-maximization algorithm. <i>IEEE Transactions on Medical Imaging</i>, 20(1), 45–57. <a href=https://doi.org/10.1109/42.906424>https://doi.org/10.1109/42.906424</a></li>",
        "Billot et al., 2023"       : "<li>Billot, B., Magdamo, C., Cheng, Y., Arnold, S.E., Das, S., Iglesias, J.E. (2023). Robust machine learning segmentation for large-scale analysis of heterogeneous clinical brain MRI datasets. <i>Proc Natl Acad Sci</i>, 120(9). <a href=https://doi.org/10.1073/pnas.2216399120>https://doi.org/10.1073/pnas.2216399120</a></li>",
        "Iglesias et al., 2023"     : "<li>Iglesias, J.E., Billot, B., Balbastre, Y., Magdamo, C., Arnold, S.E., Das, S., Edlow, B.L., Alexander, D.C., Golland, P., Fischl, B. (2023). SynthSR: A public AI tool to turn heterogeneous clinical brain scans into high-resolution T1-weighted images for 3D morphometry. <i>Science Advances</i>, 9(5). <a href=https://doi.org/10.1126/sciadv.add3607>https://doi.org/10.1126/sciadv.add3607</a></li>",
        "Adamson et al., 2020"      : "<li>Adamson, C.L., Alexander, B., Ball, G., Beare, R., Cheong, J.L.Y., Spittle, A.J., Doyle, L.W., Anderson, P.J., Seal, M.L., Thompson, D.K. (2020). Parcellation of the neonatal cortex using Surface-based Melbourne Children's Regional Infant Brain atlases (M-CRIB-S). <i>Scientific Reports</i>, 10(1). <a href=https://doi.org/10.1038/s41598-020-61326-2>https://doi.org/10.1038/s41598-020-61326-2</a></li>",
        "Fischl, 2012"              : "<li>Fischl, B. (2012). FreeSurfer. <i>NeuroImage</i>, 62(2), 774–781. <a href=https://doi.org/10.1016/j.neuroimage.2012.01.021>https://doi.org/10.1016/j.neuroimage.2012.01.021</a></li>",
        "Henschel et al., 2020"    : "<li>Henschel, L., Conjeti, S., Estrada, S., Diers, K., Fischl, B., & Reuter, M. (2020). FastSurfer — A fast and accurate deep learning based neuroimaging pipeline. <i>NeuroImage</i>, 219, 117012. <a href=https://doi.org/10.1016/j.neuroimage.2020.117012>https://doi.org/10.1016/j.neuroimage.2020.117012</a></li>",
        "Ewels et al., 2016"        : "<li>Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. <i>Bioinformatics</i>, 32(19), 3047–3048. <a href=https://doi.org/10.1093/bioinformatics/btw354>https://doi.org/10.1093/bioinformatics/btw354</a></li>",
        "Klein et al., 2012"        : "<li>Klein. A., & Tourville, J. (2012). 101 labeled brain images and a consistent human cortical labeling protocol. <i>Frontiers in Neuroscience</i>, 6(171). <a href=https://doi.org/10.3389/fnins.2012.00171>https://doi.org/10.3389/fnins.2012.00171</a></li>",
        // Not published yet.
        "Renauld et al., 2025"       : "<li>Renauld, A. et al. (2025). scilpy: a toolbox for tractography and tractometry. Submitted to <i>Aperture Neuro</i></li>",
        "Gagnon et al., 2025"       : "<li>Gagnon, A., et al. (2025). nf-pediatric: A robust and age-adaptable end-to-end pipeline for pediatric diffusion MRI. <i>In preparation</i></li>",
    ]

    // Build the bibliography in the order tokens were found.
    def bibliographyEntries = found.collect { token ->
        if (bibMap.containsKey(token)) {
            return bibMap[token]
        } else {
            // If not recognized, include a placeholder <li> with the raw token so user can refine later
            return "<li>${token} (full reference not found; please add)</li>"
        }
    }

    // If nothing was found, optionally include standard tool citations (fallback)
    if (!bibliographyEntries || bibliographyEntries.size() == 0) {
        // fallback: include a few baseline entries
        bibliographyEntries = [
            bibMap["Tournier et al., 2019"],
            bibMap["Jenkinson et al., 2012"],
            bibMap["Tustison et al., 2010"],
            bibMap["Ewels et al., 2016"]
        ].findAll{ it }
    }

    // Return joined HTML fragment (no wrapping <ul> here so caller can place it)
    return "<ul>" + bibliographyEntries.sort{ it.toLowerCase() }.join("") + "</ul>"
}

//
// Function combining the methods description text with tool citations and bibliography.
// Will convert the resulting text into HTML for inclusion in MultiQC report.
//
def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familiar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        def manifest_doi = meta.manifest_map.doi.tokenize(",")
        manifest_doi.each { doi_ref ->
            temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    } else meta["doi_text"] = ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = ""
    meta["tool_bibliography"] = ""

    //meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    def tool_biblio = toolBibliographyText()
    meta["tool_bibliography"] = indentForYaml(tool_biblio, 4)

    def methods_text = mqc_methods_yaml.text

    // Add the to the methods text the generated HTML from the function buildMethodsDescription
    def raw_methods = buildMethodsDescription()
    meta["methods_html"] = indentForYaml(raw_methods, 2)

    def engine =  new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
