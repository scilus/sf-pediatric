# sf-pediatric

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new/scilus/sf-pediatric)
[![GitHub Actions CI Status](https://github.com/scilus/sf-pediatric/actions/workflows/nf-test.yml/badge.svg?branch=main)](https://github.com/scilus/sf-pediatric/actions/workflows/nf-test.yml)
[![GitHub Actions Linting Status](https://github.com/scilus/sf-pediatric/actions/workflows/linting.yml/badge.svg?branch=main)](https://github.com/scilus/sf-pediatric/actions/workflows/linting.yml)
[![Deploy documentation](https://github.com/scilus/sf-pediatric/actions/workflows/deploy.yml/badge.svg?branch=main)](https://github.com/scilus/sf-pediatric/actions/workflows/deploy.yml)
[![Cite with Zenodo](http://img.shields.io/badge/DOI-10.5281/zenodo.XXXXXXX-1073c8?labelColor=000000)](https://doi.org/10.5281/zenodo.XXXXXXX)
[![nf-test](https://img.shields.io/badge/unit_tests-nf--test-337ab7.svg)](https://www.nf-test.com)
[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A524.10.5-23aa62.svg)](https://www.nextflow.io/)
[![nf-core template version](https://img.shields.io/badge/nf--core_template-3.4.1-green?style=flat&logo=nfcore&logoColor=white&color=%2324B064&link=https%3A%2F%2Fnf-co.re)](https://github.com/nf-core/tools/releases/tag/3.4.1)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)

## Introduction

**sf-pediatric** is an end-to-end connectomics pipeline for pediatric (0-18y) dMRI and sMRI brain scans. It performs preprocessing, tractography, t1 reconstruction, cortical and subcortical segmentation, and connectomics.

![sf-pediatric-schema](/assets/sf-pediatric-schema.png)

## Documentation

If you want to use `sf-pediatric`, head over to our documentation: https://scilus.github.io/sf-pediatric/ !

You will find detailed instructions on how to organize your inputs, launch the pipeline, and analyze your processed results.

**If you encounter bugs or issues, feel free to open an issue!**

## Credits

sf-pediatric was originally written by Anthony Gagnon.

We thank the following people for their extensive assistance in the development of this pipeline:

## Contributions and Support

If you would like to contribute to this pipeline, please see the [contributing guidelines](.github/CONTRIBUTING.md).

## Citations

An extensive list of references for the tools used by the pipeline can be found in the [documentation](https://scilus.github.io/sf-pediatric/reference/citation/).

This pipeline uses code and infrastructure developed and maintained by the [nf-core](https://nf-co.re) community, reused here under the [MIT license](https://github.com/nf-core/tools/blob/main/LICENSE).

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso & Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).
