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

**sf-pediatric** is an end-to-end age-adaptable pipeline for pediatric (0-18 years old) diffusion MRI. It leverages normative models of the brain diffusivities to perform connectomics analysis, WM bundles extraction and tractometry. Each pipeline run is wrapped in an interactive quality control reports for easy quality control of the processed data.

![sf-pediatric-schema](/assets/sf-pediatric-schema.png)

## Why sf-pediatric?

**sf-pediatric** is an intelligent diffusion MRI pipeline that actively adapts to the rapidly evolving pediatric brain:

- **Age-Adaptable**: Leverages normative trajectories from nearly 2,000 participants across six cohorts to dynamically adjust diffusion priors, template selection, and WM atlases based on each subject's age
- **Birth to Adulthood**: Designed specifically for the 0-18 year age range, addressing the unique challenges of processing the developmental brain
- **Rigorously Tested**: Demonstrates improved local modeling, cortical fanning, and robust recovery of known developmental trajectories of white matter microstructure
- **Reproducible & Transparent**: Containerized workflows (Docker/Singularity) ensure consistent results across computing environments, with comprehensive quality control reports for every processing step
- **Scalable & Portable**: Built with Nextflow for seamless deployment on cloud platforms, HPC clusters, or local computers—ideal for large-scale pediatric neuroimaging studies
- **Fully Automated**: End-to-end processing from raw acquisitions to statistics-ready datasets with integrated quality control reports
- **Modular Workflows**: Four specialized profiles (tracking, segmentation, connectomics, bundling) tailored to your research question. Combined, these profiles allow you to:
  - Preprocess your diffusion and anatomical data.
  - Fit local models
  - Perform whole-brain tractography
  - White matter bundles extraction with tractometry
  - Cortical/Subcortical segmentation
  - Structural connectome analysis

## Use Cases

**sf-pediatric** is designed for researchers investigating:

- White matter development and maturation trajectories
- Structural brain connectivity across the developmental age-range
- Neurodevelopmental disorders
- Effects of early-life environmental factors on brain development
- Normative vs. atypical brain development patterns
- Large-scale multi-site pediatric neuroimaging studies
- ...and much more!

## Quick Start

Visit our documentation at https://scilus.github.io/sf-pediatric/ for detailed instructions on organizing inputs, launching the pipeline, and analyzing results.

**Encounter an issue?** Open an issue on GitHub!

## Contributions and Support

Contributions welcome! See our [contributing guidelines](.github/CONTRIBUTING.md).

**sf-pediatric** was originally written by Anthony Gagnon.

## Citations

**Methods boilerplate**. sf-pediatric provides a boilerplate methods section available in the QC reports. Users are encouraged to use this boilerplate in their publication. For a complete guide on how to navigate the reports, please [refer to the documentation](https://scilus.github.io/sf-pediatric/guides/qc).

**Paper**. A sf-pediatric paper is on the way, until them, please cite the github repository. Stay tuned!

## License

This pipeline is released under the **MIT License**. See [LICENSE](LICENSE) for full details.

This pipeline uses code and infrastructure developed by the [nf-core](https://nf-co.re) community (MIT license) and incorporates tools from [nf-neuro](https://github.com/scilus/nf-neuro).
