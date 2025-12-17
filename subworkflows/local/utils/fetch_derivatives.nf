include { fetchPriors } from '../utils_nfcore_sf-pediatric_pipeline/main.nf'

def readParticipantsTsv(file) {
    def participantData = []

    file.splitCsv(sep: '\t', header: true).each { row ->
        if (!row.age) {
            error "ERROR: Age is not entered correctly in the participants.tsv file. Please validate."
        }

        def sessionId = (row.session_id == null || row.session_id.toString().trim() == "") ? "" : row.session_id.toString()

        participantData.add([
            participant_id: row.participant_id.toString(),
            session_id: sessionId,
            age: row.age.toFloat()
        ])
    }

    return participantData
}

workflow FETCH_DERIVATIVES {

    take:
    input_deriv

    main:
    //
    // Create channels from a derivatives folder (params.input_deriv)
    //
    if ( ! file("${input_deriv}/participants.tsv").exists() ) {
        error "ERROR: Your bids dataset does not contain a participants.tsv file. " +
        "Please provide a participants.tsv file with a column indicating the participants' " +
        "age. For any questions, please refer to the documentation at " +
        "https://github.com/scilus/sf-pediatric.git or open an issue!"
    }

    participantsTsv = file("${input_deriv}/participants.tsv")
    participantData = readParticipantsTsv(participantsTsv)
    def participant_ids = params.participant_label ?: []

    // Helper function to get age with session support
    def getAge = { participantId, sessionId = null ->
        def searchParticipantId = participantId.toString()
        def searchSessionId = (sessionId == null || sessionId.toString().trim() == "") ? "" : sessionId.toString()

        def match = participantData.find { row ->
            return row.participant_id == searchParticipantId && row.session_id == searchSessionId
        }

        return match ? match.age : 0.0  // Return 0.0 instead of empty string
    }

    // ** Segmentations ** //
    if ( params.connectomics && !params.segmentation ) {
        ch_labels = Channel.fromPath("${input_deriv}/sub-*/{ses-*/,}anat/*{,space-DWI}_seg*dseg.nii.gz",
            checkIfExists: true)
            .map{ file ->
                def parts = file.toAbsolutePath().toString().split('/')
                def id = parts.find { it.startsWith('sub-') }
                def session = parts.find { it.startsWith('ses-') }
                def age = getAge(id, session)
                def tempAge = age.toFloat() > 25 ? Math.abs((age.toFloat() - 35) / 52) : age.toFloat()
                def priors = fetchPriors(tempAge)
                def metadata = session ? \
                    [id: id, session: session, run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md] : \
                    [id: id, session: "", run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md]

                return [metadata, file]
            }
            .groupTuple(by: 0)
            .map{ meta, files ->
                if (files.size() == 2) {
                    def sortedFiles = files.sort { a, b -> // sort so that space-DWI comes second
                        if (a.name.contains('space-DWI')) return 1
                        if (b.name.contains('space-DWI')) return -1
                        return 0
                    }
                    return [meta] + sortedFiles
                }
                return [meta] + files
            }
            .filter {
                participant_ids.isEmpty() || it[0].id in participant_ids
            }
    } else {
        ch_labels = Channel.empty()
    }

    // ** Anatomical file ** //
    ch_anat = Channel.fromPath("${input_deriv}/sub-**/{ses-*/,}anat/*space-DWI_desc-preproc_{T1w,T2w}.nii.gz",
        checkIfExists: true)
        .map { file ->
            def parts = file.toAbsolutePath().toString().split('/')
            def id = parts.find { it.startsWith('sub-') }
            def session = parts.find { it.startsWith('ses-') }
            def age = getAge(id, session)
            def tempAge = age.toFloat() > 25 ? Math.abs((age.toFloat() - 35) / 52) : age.toFloat()
            def priors = fetchPriors(tempAge)
            def metadata = session ? \
                [id: id, session: session, run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md] : \
                [id: id, session: "", run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md]
            def type = file.name.contains('T1w') ? 'T1w' : 'T2w'

            return [metadata, type, file]
        }
        .groupTuple(by: 0)
        .map{ metadata, types, files ->
            def sortedFiles = [types, files].transpose().sort { it[0] }.collect { it[1] }
            return [metadata] + sortedFiles
        }
        .filter {
            participant_ids.isEmpty() || it[0].id in participant_ids
        }

    // ** Transformation files ** //
    ch_transforms = Channel.fromPath("${input_deriv}/sub-*/{ses-*/,}anat/*from-{T1w,T2w}_to-dwi_{warp,affine}*",
        checkIfExists: true)
        .map { file ->
            def parts = file.toAbsolutePath().toString().split('/')
            def id = parts.find { it.startsWith('sub-') }
            def session = parts.find { it.startsWith('ses-') }
            def age = getAge(id, session)
            def tempAge = age.toFloat() > 25 ? Math.abs((age.toFloat() - 35) / 52) : age.toFloat()
            def priors = fetchPriors(tempAge)
            def metadata = session ? \
                [id: id, session: session, run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md] : \
                [id: id, session: "", run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md]
            def type = file.name.contains('warp') ? 'warp' : 'affine'

            return [metadata, type, file]
        }
        .groupTuple(by: 0)
        .map { meta, types, files ->
            if (files.size() == 2) {
                def sortedFiles = [types, files].transpose().sort { a, b ->
                if (a[0] == 'warp') return -1
                if (b[0] == 'warp') return 1
                return 0
                }.collect { it[1] }
                return [meta] + sortedFiles
            } else {
                error "ERROR ~ Missing transformation files for ${meta.id}"
            }
        }
        .filter {
            participant_ids.isEmpty() || it[0].id in participant_ids
        }

    // ** Peaks file ** //
    ch_peaks = Channel.fromPath("${input_deriv}/sub-*/{ses-*/,}dwi/*desc-peaks*.nii.gz",
        checkIfExists: true)
        .map { file ->
            def parts = file.toAbsolutePath().toString().split('/')
            def id = parts.find { it.startsWith('sub-') }
            def session = parts.find { it.startsWith('ses-') }
            def age = getAge(id, session)
            def tempAge = age.toFloat() > 25 ? Math.abs((age.toFloat() - 35) / 52) : age.toFloat()
            def priors = fetchPriors(tempAge)
            def metadata = session ? \
                [id: id, session: session, run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md] : \
                [id: id, session: "", run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md]

            return [metadata, file]
        }

    // ** fODF file ** //
    ch_fodf = Channel.fromPath("${input_deriv}/sub-*/{ses-*/,}dwi/*desc-fodf*.nii.gz",
        checkIfExists: true)
        .map { file ->
            def parts = file.toAbsolutePath().toString().split('/')
            def id = parts.find { it.startsWith('sub-') }
            def session = parts.find { it.startsWith('ses-') }
            def age = getAge(id, session)
            def tempAge = age.toFloat() > 25 ? Math.abs((age.toFloat() - 35) / 52) : age.toFloat()
            def priors = fetchPriors(tempAge)
            def metadata = session ? \
                [id: id, session: session, run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md] : \
                [id: id, session: "", run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md]

            return [metadata, file]
        }
        .filter {
            participant_ids.isEmpty() || it[0].id in participant_ids
        }

    // ** DWI files (dwi, bval, bvec) ** //
    ch_dwi_bval_bvec = Channel.fromPath("${input_deriv}/sub-*/{ses-*/,}dwi/*desc-preproc_dwi.{nii.gz,bval,bvec}",
        checkIfExists: true)
        .map { file ->
            def parts = file.toAbsolutePath().toString().split('/')
            def id = parts.find { it.startsWith('sub-') }
            def session = parts.find { it.startsWith('ses-') }
            def age = getAge(id, session)
            def tempAge = age.toFloat() > 25 ? Math.abs((age.toFloat() - 35) / 52) : age.toFloat()
            def priors = fetchPriors(tempAge)
            def metadata = session ? \
                [id: id, session: session, run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md] : \
                [id: id, session: "", run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md]

            return [metadata, file]
        }
        .groupTuple(by: 0)
        .map { meta, files ->
            if (files.size() == 3) {
                def sortedFiles = files.sort { file ->
                    if (file.extension == "nii.gz") {
                        return 0
                    } else if (file.extension == "bval") {
                        return 1
                    } else if (file.extension == "bvec") {
                        return 2
                    }
                }
                return [meta] + sortedFiles
            } else {
                error "ERROR ~ Missing dwi/bval/bvec files for ${meta.id}"
            }
        }
        .filter {
            participant_ids.isEmpty() || it[0].id in participant_ids
        }

    // ** Tractogram file ** //
    ch_trk = Channel.fromPath("${input_deriv}/sub-*/{ses-*/,}dwi/*desc-{concatenated,local,pft}_tractogram.trk", checkIfExists: true)
        .map { file ->
            def parts = file.toAbsolutePath().toString().split("/")
            def id = parts.find { it.startsWith('sub-') }
            def session = parts.find { it.startsWith('ses-') }
            def age = getAge(id, session)
            def tempAge = age.toFloat() > 25 ? Math.abs((age.toFloat() - 35) / 52) : age.toFloat()
            def priors = fetchPriors(tempAge)
            def metadata = session ? \
                [id: id, session: session, run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md] : \
                [id: id, session: "", run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md]

            return [metadata, file]
        }
        .groupTuple(by: 0)
        .map{ meta, files ->
            // Return the concatenated tractogram if it exists, else return the first available
            def concatFile = files.find { it.name.contains('concatenated') }
            if (concatFile) {
                return [meta, concatFile]
            } else {
                return [meta, files[0]]
            }
        }
        .filter {
            participant_ids.isEmpty() || it[0].id in participant_ids
        }

    // ** Metrics files ** //
    ch_metrics = Channel.fromPath("${input_deriv}/sub-*/{ses-*/,}dwi/*desc-{fa,md,rd,ad,nufo,afd_total,afd_sum,afd_max}.nii.gz",
        checkIfExists: true)
        .map { file ->
            def parts = file.toAbsolutePath().toString().split("/")
            def id = parts.find { it.startsWith('sub-') }
            def session = parts.find { it.startsWith('ses-') }
            def age = getAge(id, session)
            def tempAge = age.toFloat() > 25 ? Math.abs((age.toFloat() - 35) / 52) : age.toFloat()
            def priors = fetchPriors(tempAge)
            def metadata = session ? \
                [id: id, session: session, run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md] : \
                [id: id, session: "", run: "", age: age, fa: priors.fa, ad: priors.ad, rd: priors.rd, md: priors.md]

            return [metadata, file]
        }
        .groupTuple(by: 0)
        .map{ meta, files ->
            return [meta] + [files]
        }
        .filter {
            participant_ids.isEmpty() || it[0].id in participant_ids
        }

    emit:
    anat            = ch_anat
    labels          = ch_labels
    transforms      = ch_transforms
    peaks           = ch_peaks
    fodf            = ch_fodf
    dwi_bval_bvec   = ch_dwi_bval_bvec
    trk             = ch_trk
    metrics         = ch_metrics
}
