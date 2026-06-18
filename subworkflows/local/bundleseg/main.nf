include { REGISTRATION_ANTS                                 } from '../../../modules/nf-neuro/registration/ants/main'
include { BUNDLE_RECOGNIZE                                  } from '../../../modules/nf-neuro/bundle/recognize/main'
include { BUNDLE_CENTROID                                   } from '../../../modules/nf-neuro/bundle/centroid/main'
include { REGISTRATION_TRACTOGRAM as TRANSFORM_CENTROIDS    } from '../../../modules/nf-neuro/registration/tractogram/main'

def fetchAtlases(channel, cohort) {
    channel.map { folder ->
        def meta = [id: "BundleSegAtlas", cohort: cohort]
        def f = [
            file("${folder}/atlas-${cohort}/*T1w.nii.gz"),
            file("${folder}/atlas-${cohort}/config.json"),
            file("${folder}/atlas-${cohort}/atlas/"),
            file("${folder}/atlas-${cohort}/centroids/")
        ]
        def flattenedFiles = f.flatten().findAll { file -> file.exists() }
        [meta] + flattenedFiles
    }
}

workflow BUNDLE_SEG {

    take:
        ch_fa               // channel: [ val(meta), [ fa ] ]
        ch_tractogram       // channel: [ val(meta), [ tractogram ] ]

    main:

        ch_versions = channel.empty()

        // ** Setting up Atlas reference channels. ** //
        if ( params.atlas_directory ) {
            atlas_anat = channel.fromPath("$params.atlas_directory/atlas/mni_masked.nii.gz", checkIfExists: true, relative: true)
            atlas_config = channel.fromPath("$params.atlas_directory/config/config_fss_1.json", checkIfExists: true, relative: true)
            atlas_average = channel.fromPath("$params.atlas_directory/atlas/atlas/", checkIfExists: true, relative: true)

            ch_register = ch_fa
                .combine(atlas_anat)
                .map { tuple -> tuple + [[]] }
        }
        else {
            ch_atlases_path = channel.fromPath("${params.templates_download_path}/templates/")
            ch_atlas_infant00 = fetchAtlases(ch_atlases_path, "Infant00")
            ch_atlas_infant03 = fetchAtlases(ch_atlases_path, "Infant03")
            ch_atlas_infant06 = fetchAtlases(ch_atlases_path, "Infant06")
            ch_atlas_infant12 = fetchAtlases(ch_atlases_path, "Infant12")
            ch_atlas_infant24 = fetchAtlases(ch_atlases_path, "Infant24")
            ch_atlas_children = fetchAtlases(ch_atlases_path, "Children")

            // ** Register the atlas to subject's space. Set up atlas file as moving image ** //
            // ** and subject anat as fixed image.                                         ** //
            ch_register =  ch_fa
                .combine(ch_atlas_infant00.map { tuple -> tuple[1] })
                .combine(ch_atlas_infant03.map { tuple -> tuple[1] })
                .combine(ch_atlas_infant06.map { tuple -> tuple[1] })
                .combine(ch_atlas_infant12.map { tuple -> tuple[1] })
                .combine(ch_atlas_infant24.map { tuple -> tuple[1] })
                .combine(ch_atlas_children.map { tuple -> tuple[1] })
                .branch{ tuple ->
                    infant00: tuple[0].age < 0.125 || tuple[0].age > 18
                        return [ tuple[0], tuple[1], tuple[2], [] ]
                    infant03: (tuple[0].age >= 0.125 && tuple[0].age < 0.375)
                        return [ tuple[0], tuple[1], tuple[3], [] ]
                    infant06: (tuple[0].age >= 0.375 && tuple[0].age < 0.75)
                        return [ tuple[0], tuple[1], tuple[4], [] ]
                    infant12: (tuple[0].age >= 0.75 && tuple[0].age < 1.5)
                        return [ tuple[0], tuple[1], tuple[5], [] ]
                    infant24: (tuple[0].age >= 1.5 && tuple[0].age < 3)
                        return [ tuple[0], tuple[1], tuple[6], [] ]
                    child: true
                        return [ tuple[0], tuple[1], tuple[7], [] ]
                }
            ch_register = ch_register.infant00
                .mix(ch_register.infant03)
                .mix(ch_register.infant06)
                .mix(ch_register.infant12)
                .mix(ch_register.infant24)
                .mix(ch_register.child)
        }

        REGISTRATION_ANTS ( ch_register )
        ch_versions = ch_versions.mix(REGISTRATION_ANTS.out.versions)

        // ** Perform bundle recognition and segmentation ** //
        // ** If an external atlas directory is provided, use that. Otherwise, ** //
        // ** use the included atlases. ** //
        if ( params.atlas_directory ) {
            ch_recognize_bundle = ch_tractogram
                .join(REGISTRATION_ANTS.out.forward_affine)
                .combine(atlas_config)
                .combine(atlas_average)
        } else {
            ch_recognize_bundle = ch_tractogram
                .join(REGISTRATION_ANTS.out.forward_affine)
                .combine(ch_atlas_infant00.map { tuple -> tuple[2] }) // config
                .combine(ch_atlas_infant00.map { tuple -> tuple[3] }) // atlas folder
                .combine(ch_atlas_infant03.map { tuple -> tuple[2] })
                .combine(ch_atlas_infant03.map { tuple -> tuple[3] })
                .combine(ch_atlas_infant06.map { tuple -> tuple[2] })
                .combine(ch_atlas_infant06.map { tuple -> tuple[3] })
                .combine(ch_atlas_infant12.map { tuple -> tuple[2] })
                .combine(ch_atlas_infant12.map { tuple -> tuple[3] })
                .combine(ch_atlas_infant24.map { tuple -> tuple[2] })
                .combine(ch_atlas_infant24.map { tuple -> tuple[3] })
                .combine(ch_atlas_children.map { tuple -> tuple[2] })
                .combine(ch_atlas_children.map { tuple -> tuple[3] })
                .branch { tuple ->
                    infant00: tuple[0].age < 0.125 || tuple[0].age > 18
                        return [ tuple[0], tuple[1], tuple[2], tuple[3], tuple[4] ]
                    infant03: (tuple[0].age >= 0.125 && tuple[0].age < 0.375)
                        return [ tuple[0], tuple[1], tuple[2], tuple[5], tuple[6] ]
                    infant06: (tuple[0].age >= 0.375 && tuple[0].age < 0.75)
                        return [ tuple[0], tuple[1], tuple[2], tuple[7], tuple[8] ]
                    infant12: (tuple[0].age >= 0.75 && tuple[0].age < 1.5)
                        return [ tuple[0], tuple[1], tuple[2], tuple[9], tuple[10] ]
                    infant24: (tuple[0].age >= 1.5 && tuple[0].age < 3)
                        return [ tuple[0], tuple[1], tuple[2], tuple[11], tuple[12] ]
                    child: true
                        return [ tuple[0], tuple[1], tuple[2], tuple[13], tuple[14] ]
                }
            ch_recognize_bundle = ch_recognize_bundle.infant00
                .mix(ch_recognize_bundle.infant03)
                .mix(ch_recognize_bundle.infant06)
                .mix(ch_recognize_bundle.infant12)
                .mix(ch_recognize_bundle.infant24)
                .mix(ch_recognize_bundle.child)
        }

        BUNDLE_RECOGNIZE ( ch_recognize_bundle )
        ch_versions = ch_versions.mix(BUNDLE_RECOGNIZE.out.versions)

        // ** Transform the centroid of the pop-average bundles ** //
        if ( params.atlas_directory ) {
            ch_compute_centroids = atlas_average
                .map { folder ->
                    def meta = [id: "CustomAtlas"]
                    def files = file("${folder}/centroids/*.trk")
                    [meta, files]
                }
            ch_transform_centroids = ch_fa
                .join( REGISTRATION_ANTS.out.forward_affine )
                .combine ( ch_compute_centroids.map { tuple -> [ tuple[1] ] } )
                .map { meta, fa, affine, centroid_data ->
                    [ meta, fa, affine, centroid_data, [], [] ]
                }
        } else {
            /* Using included centroids */
            ch_centroids_infant00 = ch_atlas_infant00.map { _meta, _anat, _conf, _folder, centroids ->
                def meta = [id: "Infant00"]
                def files = file("${centroids}/*.trk")
                [meta, files]
            }
            ch_centroids_infant03 = ch_atlas_infant03.map { _meta, _anat, _conf, _folder, centroids ->
                def meta = [id: "Infant03"]
                def files = file("${centroids}/*.trk")
                [meta, files]
            }
            ch_centroids_infant06 = ch_atlas_infant06.map { _meta, _anat, _conf, _folder, centroids ->
                def meta = [id: "Infant06"]
                def files = file("${centroids}/*.trk")
                [meta, files]
            }
            ch_centroids_infant12 = ch_atlas_infant12.map { _meta, _anat, _conf, _folder, centroids ->
                def meta = [id: "Infant12"]
                def files = file("${centroids}/*.trk")
                [meta, files]
            }
            ch_centroids_infant24 = ch_atlas_infant24.map { _meta, _anat, _conf, _folder, centroids ->
                def meta = [id: "Infant24"]
                def files = file("${centroids}/*.trk")
                [meta, files]
            }
            ch_centroids_infant24 = ch_atlas_infant24.map { _meta, _anat, _conf, _folder, centroids ->
                def meta = [id: "Infant24"]
                def files = file("${centroids}/*.trk")
                [meta, files]
            }
            ch_centroids_children = ch_atlas_children.map { _meta, _anat, _conf, _folder, centroids ->
                    def meta = [id: "Children"]
                    def files = file("${centroids}/*.trk")
                    [meta, files]
            }
            ch_transform_centroids = ch_fa
                .join( REGISTRATION_ANTS.out.forward_affine )
                .combine( ch_centroids_infant00.map{ tuple -> [ tuple[1] ] } )
                .combine( ch_centroids_infant03.map{ tuple -> [ tuple[1] ] } )
                .combine( ch_centroids_infant06.map{ tuple -> [ tuple[1] ] } )
                .combine( ch_centroids_infant12.map{ tuple -> [ tuple[1] ] } )
                .combine( ch_centroids_infant24.map{ tuple -> [ tuple[1] ] } )
                .combine( ch_centroids_children.map{ tuple -> [ tuple[1] ] } )
                .branch { it ->
                    infant00: it[0].age < 0.125 || it[0].age > 18
                        return [ it[0], it[3], [], it[1], it[2] ]
                    infant03: (it[0].age >= 0.125 && it[0].age < 0.375)
                        return [ it[0], it[4], [], it[1], it[2] ]
                    infant06: (it[0].age >= 0.375 && it[0].age < 0.75)
                        return [ it[0], it[5], [], it[1], it[2] ]
                    infant12: (it[0].age >= 0.75 && it[0].age < 1.5)
                        return [ it[0], it[6], [], it[1], it[2] ]
                    infant24: (it[0].age >= 1.5 && it[0].age < 3)
                        return [ it[0], it[7], [], it[1], it[2] ]
                    child: true
                        return [ it[0], it[8], [], it[1], it[2] ]
                }
            ch_transform_centroids = ch_transform_centroids.infant00
                .mix(ch_transform_centroids.infant03)
                .mix(ch_transform_centroids.infant06)
                .mix(ch_transform_centroids.infant12)
                .mix(ch_transform_centroids.infant24)
                .mix(ch_transform_centroids.child)
        }

        // ** Apply the transform to the centroids ** //
        TRANSFORM_CENTROIDS ( ch_transform_centroids )
        ch_versions = ch_versions.mix(TRANSFORM_CENTROIDS.out.versions)

    emit:
        bundles = BUNDLE_RECOGNIZE.out.bundles                  // channel: [ val(meta), [ bundles ] ]
        centroids = TRANSFORM_CENTROIDS.out.tractogram          // channel: [ val(meta), [ centroids ] ]
        versions = ch_versions                                  // channel: [ versions.yml ]
}
