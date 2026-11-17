include { REGISTER_MD } from '../../../modules/local/registration/registermd/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as APPLYTRANSFORMS } from '../../../modules/nf-neuro/registration/antsapplytransforms/main'

def createFetalChannel(channel, cohort) {
    channel.map { folder ->
        def meta = [id: "Fetal", cohort: cohort]
        def files = [
            file("${folder}/${cohort}/dwi_${cohort}_md_atlas.nii.gz"),
            file("${folder}/${cohort}/dwi_${cohort}_fa_atlas.nii.gz"),
            file("${folder}/${cohort}/dwi_${cohort}_wm.nii.gz")
        ]
        def flattenedFiles = files.flatten().findAll { it -> it.exists() }
        [meta] + flattenedFiles
    }
}

workflow FETAL {

    take:
    ch_md_map
    ch_fa_map

    main:
    ch_versions = channel.empty()
    ch_template_folder = channel.fromPath("${params.fetal_templates_folder}", checkIfExists: true)
    ch_multiqc_files_subject = channel.empty()

    // Create the fetal channel
    ch_ga23 = createFetalChannel(ch_template_folder, "ga23")
    ch_ga24 = createFetalChannel(ch_template_folder, "ga24")
    ch_ga25 = createFetalChannel(ch_template_folder, "ga25")
    ch_ga26 = createFetalChannel(ch_template_folder, "ga26")
    ch_ga27 = createFetalChannel(ch_template_folder, "ga27")
    ch_ga28 = createFetalChannel(ch_template_folder, "ga28")
    ch_ga29 = createFetalChannel(ch_template_folder, "ga29")
    ch_ga30 = createFetalChannel(ch_template_folder, "ga30")
    ch_ga31 = createFetalChannel(ch_template_folder, "ga31")
    ch_ga32 = createFetalChannel(ch_template_folder, "ga32")
    ch_ga33 = createFetalChannel(ch_template_folder, "ga33")
    ch_ga34 = createFetalChannel(ch_template_folder, "ga34")
    ch_ga35 = createFetalChannel(ch_template_folder, "ga35")
    ch_ga36 = createFetalChannel(ch_template_folder, "ga36")
    ch_ga37 = createFetalChannel(ch_template_folder, "ga37")
    ch_ga38 = createFetalChannel(ch_template_folder, "ga38")

    // Register the template MD to the subject MD
    ch_register_md = ch_md_map
        .join(ch_fa_map)
        .combine(ch_ga23.map { tuple -> tuple[1..2] })
        .combine(ch_ga24.map { tuple -> tuple[1..2] })
        .combine(ch_ga25.map { tuple -> tuple[1..2] })
        .combine(ch_ga26.map { tuple -> tuple[1..2] })
        .combine(ch_ga27.map { tuple -> tuple[1..2] })
        .combine(ch_ga28.map { tuple -> tuple[1..2] })
        .combine(ch_ga29.map { tuple -> tuple[1..2] })
        .combine(ch_ga30.map { tuple -> tuple[1..2] })
        .combine(ch_ga31.map { tuple -> tuple[1..2] })
        .combine(ch_ga32.map { tuple -> tuple[1..2] })
        .combine(ch_ga33.map { tuple -> tuple[1..2] })
        .combine(ch_ga34.map { tuple -> tuple[1..2] })
        .combine(ch_ga35.map { tuple -> tuple[1..2] })
        .combine(ch_ga36.map { tuple -> tuple[1..2] })
        .combine(ch_ga37.map { tuple -> tuple[1..2] })
        .combine(ch_ga38.map { tuple -> tuple[1..2] })
        .branch { tuple ->
            ga23: tuple[0].age <= 23.5
                return [tuple[0], tuple[1], tuple[2], tuple[3], tuple[4]]
            ga24: tuple[0].age > 23.5 && tuple[0].age <= 24.5
                return [tuple[0], tuple[1], tuple[2], tuple[5], tuple[6]]
            ga25: tuple[0].age > 24.5 && tuple[0].age <= 25.5
                return [tuple[0], tuple[1], tuple[2], tuple[7], tuple[8]]
            ga26: tuple[0].age > 25.5 && tuple[0].age <= 26.5
                return [tuple[0], tuple[1], tuple[2], tuple[9], tuple[10]]
            ga27: tuple[0].age > 26.5 && tuple[0].age <= 27.5
                return [tuple[0], tuple[1], tuple[2], tuple[11], tuple[12]]
            ga28: tuple[0].age > 27.5 && tuple[0].age <= 28.5
                return [tuple[0], tuple[1], tuple[2], tuple[13], tuple[14]]
            ga29: tuple[0].age > 28.5 && tuple[0].age <= 29.5
                return [tuple[0], tuple[1], tuple[2], tuple[15], tuple[16]]
            ga30: tuple[0].age > 29.5 && tuple[0].age <= 30.5
                return [tuple[0], tuple[1], tuple[2], tuple[17], tuple[18]]
            ga31: tuple[0].age > 30.5 && tuple[0].age <= 31.5
                return [tuple[0], tuple[1], tuple[2], tuple[19], tuple[20]]
            ga32: tuple[0].age > 31.5 && tuple[0].age <= 32.5
                return [tuple[0], tuple[1], tuple[2], tuple[21], tuple[22]]
            ga33: tuple[0].age > 32.5 && tuple[0].age <= 33.5
                return [tuple[0], tuple[1], tuple[2], tuple[23], tuple[24]]
            ga34: tuple[0].age > 33.5 && tuple[0].age <= 34.5
                return [tuple[0], tuple[1], tuple[2], tuple[25], tuple[26]]
            ga35: tuple[0].age > 34.5 && tuple[0].age <= 35.5
                return [tuple[0], tuple[1], tuple[2], tuple[27], tuple[28]]
            ga36: tuple[0].age > 35.5 && tuple[0].age <= 36.5
                return [tuple[0], tuple[1], tuple[2], tuple[29], tuple[30]]
            ga37: tuple[0].age > 36.5 && tuple[0].age <= 37.5
                return [tuple[0], tuple[1], tuple[2], tuple[31], tuple[32]]
            ga38: tuple[0].age > 37.5 && tuple[0].age <= 38.5
                return [tuple[0], tuple[1], tuple[2], tuple[33], tuple[34]]
        }

    ch_md_for_registration = channel.empty()
        .mix(ch_register_md.ga23)
        .mix(ch_register_md.ga24)
        .mix(ch_register_md.ga25)
        .mix(ch_register_md.ga26)
        .mix(ch_register_md.ga27)
        .mix(ch_register_md.ga28)
        .mix(ch_register_md.ga29)
        .mix(ch_register_md.ga30)
        .mix(ch_register_md.ga31)
        .mix(ch_register_md.ga32)
        .mix(ch_register_md.ga33)
        .mix(ch_register_md.ga34)
        .mix(ch_register_md.ga35)
        .mix(ch_register_md.ga36)
        .mix(ch_register_md.ga37)
        .mix(ch_register_md.ga38)

    // Run registration
    REGISTER_MD (ch_md_for_registration)
    ch_versions = ch_versions.mix(REGISTER_MD.out.versions)
    ch_multiqc_files_subject = ch_multiqc_files_subject.mix(REGISTER_MD.out.mqc)

    // Apply the transformation to the template WM segmentation
    ch_apply_transformation = ch_md_map
        .join(REGISTER_MD.out.forward_image_transform)
        .combine(ch_ga23.map { tuple -> tuple[3] })
        .combine(ch_ga24.map { tuple -> tuple[3] })
        .combine(ch_ga25.map { tuple -> tuple[3] })
        .combine(ch_ga26.map { tuple -> tuple[3] })
        .combine(ch_ga27.map { tuple -> tuple[3] })
        .combine(ch_ga28.map { tuple -> tuple[3] })
        .combine(ch_ga29.map { tuple -> tuple[3] })
        .combine(ch_ga30.map { tuple -> tuple[3] })
        .combine(ch_ga31.map { tuple -> tuple[3] })
        .combine(ch_ga32.map { tuple -> tuple[3] })
        .combine(ch_ga33.map { tuple -> tuple[3] })
        .combine(ch_ga34.map { tuple -> tuple[3] })
        .combine(ch_ga35.map { tuple -> tuple[3] })
        .combine(ch_ga36.map { tuple -> tuple[3] })
        .combine(ch_ga37.map { tuple -> tuple[3] })
        .combine(ch_ga38.map { tuple -> tuple[3] })
        .branch { tuple ->
            ga23: tuple[0].age <= 23.5
                return [tuple[0], tuple[3], tuple[1], tuple[2]]
            ga24: tuple[0].age > 23.5 && tuple[0].age <= 24.5
                return [tuple[0], tuple[4], tuple[1], tuple[2]]
            ga25: tuple[0].age > 24.5 && tuple[0].age <= 25.5
                return [tuple[0], tuple[5], tuple[1], tuple[2]]
            ga26: tuple[0].age > 25.5 && tuple[0].age <= 26.5
                return [tuple[0], tuple[6], tuple[1], tuple[2]]
            ga27: tuple[0].age > 26.5 && tuple[0].age <= 27.5
                return [tuple[0], tuple[7], tuple[1], tuple[2]]
            ga28: tuple[0].age > 27.5 && tuple[0].age <= 28.5
                return [tuple[0], tuple[8], tuple[1], tuple[2]]
            ga29: tuple[0].age > 28.5 && tuple[0].age <= 29.5
                return [tuple[0], tuple[9], tuple[1], tuple[2]]
            ga30: tuple[0].age > 29.5 && tuple[0].age <= 30.5
                return [tuple[0], tuple[10], tuple[1], tuple[2]]
            ga31: tuple[0].age > 30.5 && tuple[0].age <= 31.5
                return [tuple[0], tuple[11], tuple[1], tuple[2]]
            ga32: tuple[0].age > 31.5 && tuple[0].age <= 32.5
                return [tuple[0], tuple[12], tuple[1], tuple[2]]
            ga33: tuple[0].age > 32.5 && tuple[0].age <= 33.5
                return [tuple[0], tuple[13], tuple[1], tuple[2]]
            ga34: tuple[0].age > 33.5 && tuple[0].age <= 34.5
                return [tuple[0], tuple[14], tuple[1], tuple[2]]
            ga35: tuple[0].age > 34.5 && tuple[0].age <= 35.5
                return [tuple[0], tuple[15], tuple[1], tuple[2]]
            ga36: tuple[0].age > 35.5 && tuple[0].age <= 36.5
                return [tuple[0], tuple[16], tuple[1], tuple[2]]
            ga37: tuple[0].age > 36.5 && tuple[0].age <= 37.5
                return [tuple[0], tuple[17], tuple[1], tuple[2]]
            ga38: tuple[0].age > 37.5 && tuple[0].age <= 38.5
                return [tuple[0], tuple[18], tuple[1], tuple[2]]
        }
    ch_for_transformation = channel.empty()
        .mix(ch_apply_transformation.ga23)
        .mix(ch_apply_transformation.ga24)
        .mix(ch_apply_transformation.ga25)
        .mix(ch_apply_transformation.ga26)
        .mix(ch_apply_transformation.ga27)
        .mix(ch_apply_transformation.ga28)
        .mix(ch_apply_transformation.ga29)
        .mix(ch_apply_transformation.ga30)
        .mix(ch_apply_transformation.ga31)
        .mix(ch_apply_transformation.ga32)
        .mix(ch_apply_transformation.ga33)
        .mix(ch_apply_transformation.ga34)
        .mix(ch_apply_transformation.ga35)
        .mix(ch_apply_transformation.ga36)
        .mix(ch_apply_transformation.ga37)
        .mix(ch_apply_transformation.ga38)

    // Run the apply transform
    APPLYTRANSFORMS (ch_for_transformation)
    ch_versions = ch_versions.mix(APPLYTRANSFORMS.out.versions)

    emit:
    wm_maps = APPLYTRANSFORMS.out.warped_image
    qc_files = ch_multiqc_files_subject
    versions = ch_versions

}
