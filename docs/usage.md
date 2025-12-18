# scilus/sf-pediatric: Usage

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

`sf-pediatric` is a neuro-imaging pipeline to process MRI pediatric data from 0-18 years old. It includes a variety of profiles that performs different steps of the pipeline and can be activated or deactivated by the user. Here is a list of the available profiles:

- `tracking`: Perform DWI preprocessing, DTI and FODF modelling, anatomical segmentation, and tractography. Final outputs are the DTI/FODF metric maps, whole-brain tractogram, registered anatomical image, etc.
- `bundling`: Perform bundle extraction from the whole-brain tractogram according to a bundle atlas. For children under 6 months, the pipeline uses a neonate atlas. For other ages, pipeline will automatically pull the atlas from [Zenodo](https://zenodo.org/records/10103446) (if you don't have access to internet, you will need to download it prior to the pipeline run, and specify its location using `--atlas_directory`). Following bundle extraction, the pipeline will perform tractometry and output various metrics for each bundle.
- `segmentation`: Run [FreeSurfer](https://surfer.nmr.mgh.harvard.edu/), [Recon-all-clinical](https://surfer.nmr.mgh.harvard.edu/fswiki/recon-all-clinical), [FastSurfer](https://deep-mi.org/research/fastsurfer/), or [M-CRIB-S/InfantFS](https://github.com/DevelopmentalImagingMCRI/MCRIBS) for T1w/T2w surface reconstruction. Then, the [Brainnetome Child Atlas](https://academic.oup.com/cercor/article/33/9/5264/6762896) or the Desikan-Killiany atlas (for infant) is mapped to the subject space.
- `connectomics`: Perform tractogram segmentation according to an atlas, tractogram filtering, and compute metrics. Final outputs are connectivity matrices.

---

## Table of Contents

- [sf-pediatric: Usage](#sf-pediatric-usage)
  - [Introduction](#introduction)
  - [Table of Contents](#table-of-contents)
  - [BIDS input directory](#bids-input-directory)
    - [Directory Structure](#directory-structure)
    - [Required Files](#required-files)
  - [Running the pipeline](#running-the-pipeline)
    - [How are the priors generated?](#how-are-the-priors-generated)
    - [Updating the pipeline](#updating-the-pipeline)
    - [Reproducibility](#reproducibility)
  - [Core Nextflow arguments](#core-nextflow-arguments)
    - [`-profile`](#-profile)
    - [`-resume`](#-resume)
    - [`-c`](#-c)
  - [Custom configuration](#custom-configuration)
    - [Resource requests](#resource-requests)
    - [Custom Containers](#custom-containers)
    - [Custom Tool Arguments](#custom-tool-arguments)
    - [nf-core/configs](#nf-coreconfigs)
  - [Running in the background](#running-in-the-background)
  - [Nextflow memory requirements](#nextflow-memory-requirements)

---

## BIDS input directory

The [BIDS (Brain Imaging Data Structure)](https://bids-specification.readthedocs.io/en/stable/) input directory is a standardized way to organize and describe neuroimaging and behavioral data. The sf-pediatric pipeline expects the input data to be organized in the BIDS format. It is recommended that users validate their BIDS layout using the official [bids-validator tool](https://hub.docker.com/r/bids/validator).

### Directory Structure

The most basic BIDS directory should have a similar structure (note that sessions folder are also supported):

```
/path/to/bids_directory/
├── dataset_description.json
├── participants.tsv
├── sub-01/
│   ├── anat/
│   │   ├── sub-01_T1w.nii.gz
│   │   ├── sub-01_T1w.json
│   │   ├── sub-01_T2w.nii.gz
│   │   └── sub-01_T2w.json
│   ├── dwi/
│   │   ├── sub-01_dwi.nii.gz
│   │   ├── sub-01_dwi.json
│   │   ├── sub-01_dwi.bval
│   │   └── sub-01_dwi.bvec
│   └── fmap/
│       ├── sub-01_epi.nii.gz
│       └── sub-01_epi.json
└── sub-02/
    └── <...>
```

### Required Files

- `dataset_description.json`: A JSON file describing the dataset.
- `participants.tsv`: A TSV file listing the participants and their metadata. **`sf-pediatric` requires the participants' age to be supplied within this file, using `age` as the column name. If not available, the pipeline will return an error at runtime. Here is an example:**

> [!IMPORTANT]
> The age can be specified using either post conceptual age (only recommended for infant data, users should indicate age in years as soon as possible) or years. If multiple session are available for a single subject, each session needs to be entered in different rows. For example, see below:

> | participant_id | session_id   | age |
> | -------------- | ------------ | --- |
> | sub-test1      | ses-baseline | 42  |
> | sub-test1      | ses-time1    | 4   |
> | sub-test2      |              | 8   |
> | ...            | ...          | ... |

Mandatory files per subject:

- `sub-<participant_id>/`: A directory for each participant containing their data.
  - `anat/`: A directory containing anatomical MRI data (e.g., T1w, T2w). If both are available, the optimal one will be selected and both will be coregistered.
    - `T1w` is **mandatory** for participants >= 3 months old.
    - `T2w` is **mandatory** for participants < 3 months old.
  - `dwi/`: A directory containing diffusion-weighted imaging data (e.g., DWI, bval, bvec). Acquisition with both direction DWI data are also supported (e.g. AP/PA). Specify them according to the [BIDS guidelines](https://bids-specification.readthedocs.io/en/stable/modality-specific-files/magnetic-resonance-imaging-data.html)
  - `fmap/`: A directory containing field map data (optional but recommended for distortion correction).

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run scilus/sf-pediatric -r main --input <BIDS_directory> --outdir ./results -profile docker,tracking
```

This will launch the pipeline with the `docker` configuration profile. There is only 2 parameters that need to be supplied at runtime: `--input`: for the path to your BIDS directory and `--outdir`: path to the output directory. A single or a subset of participants can be specified using `--participant-label`; this will constrain the pipeline to run only on those specified subjects. See below for more information about profiles.

Note that the pipeline will create the following files in your working directory:

```bash
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined with --outdir)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

If you wish to repeatedly use the same parameters for multiple runs, rather than specifying each flag in the command, you can specify these in a params file.

Pipeline settings can be provided in a `yaml` or `json` file via `-params-file <file>`.

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors. Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources), other infrastructural tweaks (such as output directories), or module arguments (args).

The above pipeline run specified with a params file in yaml format:

```bash
nextflow run scilus/sf-pediatric -r main -profile docker -params-file params.yaml
```

with:

```yaml title="params.yaml"
input: './bids-folder/'
outdir: './results/'
<...>
```

You can also generate such `YAML`/`JSON` files via [nf-core/launch](https://nf-co.re/launch).

### How are the priors generated?

One innovative feature of `sf-pediatric` is how it generates the priors for the fiber response function (FRF) and
COMMIT. Previous pipelines (e.g., TractoFlow) used either a set FRF function or computed the mean FRF across all study subjects. One crucial issue with both methods in pediatric samples lies in the rapid neurophysiological changes
happening during this development period. Differences between a one-year old and a four-year old children can appear
rather drastic. Using a single FRF for both or averaging all of them together in a single mean FRF both represent
suboptimal solution. With the rise of normative models, we leveraged six pediatric cohorts spanning the whole 0-18 years old range to derive normative curves of FA, RD, AD values in single fiber population as well as MD values in
the ventricles (see figure below).

![curves](../assets/normative_curves_and_rawdata.png)

> [!NOTE]
> While only the FRF and COMMIT priors are currently supported using normative curves, we are working to extend this method to other processing aspects to ensure the most optimal age appropriate processing of diffusion MRI acquisitions.

Each of those median normative curves were approximate using single equations, and implement into `sf-pediatric`.
While this is the default option, users can still specify their own FRF using the parameter `--frf_manual_frf`. Similarly, COMMIT priors can be specified with `--commit_para_diff`, `--commit_perp_diff`, and `--commit_iso_diff`.

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull scilus/sf-pediatric
```

### Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [scilus/sf-pediatric releases page](https://github.com/scilus/sf-pediatric/releases) and find the latest pipeline version - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`. Of course, you can switch to another version by changing the number after the `-r` flag.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future. For example, at the bottom of the MultiQC reports.

To further assist in reproducibility, you can use share and reuse [parameter files](#running-the-pipeline) to repeat pipeline runs with the same settings without having to write out a command with every single parameter.

> [!TIP]
> If you wish to share such profile (such as upload as supplementary material for academic publications), make sure to NOT include cluster specific paths to files, nor institutional specific profiles.

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, and Apptainer) - see below.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time. For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile tracking,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `slurm`
  - A generic configuration profile for use on SLURM managed clusters.
- `arm`
  - A generic configuration profile for ARM based computers. **Experimental, not all containers have their ARM equivalent and might reduce performance.**
- `tracking`
  - Perform DWI preprocessing, DTI and FODF modelling, anatomical segmentation, and tractography. Final outputs are the DTI/FODF metric maps, whole-brain tractogram, registered anatomical image, etc.
- `bundling`
  - Perform automatic bundle extraction using a bundle atlas. Then, each bundle is cleaned, and tractometry is performed to obtain various measures of WM microstructure along each bundle.
- `segmentation`
  - Run Recon-all-clinical (default for participants >= 3 months), FreeSurfer, FastSurfer, or M-CRIB-S (participants < 3 months) for T1w/T2w surface reconstruction. Then, the [Brainnetome Child Atlas](https://academic.oup.com/cercor/article/33/9/5264/6762896) or Desikan-Killiany atlas is mapped to the subject space.
- `connectomics`
  - Perform tractogram segmentation according to a cortical/subcortical parcellation, tractogram filtering, and compute metrics. Final outputs are connectivity matrices.

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well. For more info about this parameter, see [this blog post](https://www.nextflow.io/blog/2019/demystifying-nextflow-resume.html).

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the pipeline steps, if the job exits with any of the error codes specified [here](https://github.com/nf-core/rnaseq/blob/4c27ef5610c87db00c3c5a3eed10b1d161abf575/conf/base.config#L18) it will automatically be resubmitted with higher resources request (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

To change the resource requests, please see the [max resources](https://nf-co.re/docs/usage/configuration#max-resources) and [tuning workflow resources](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources) section of the nf-core website.

### Custom Containers

In some cases, you may wish to change the container or conda environment used by a pipeline steps for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To use a different container from the default container or conda environment specified in a pipeline, please see the [updating tool versions](https://nf-co.re/docs/usage/configuration#updating-tool-versions) section of the nf-core website.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/usage/configuration#customising-tool-arguments) section of the nf-core website.

### nf-core/configs

In most cases, you will only need to create a custom config as a one-off but if you and others within your organisation are likely to be running nf-core pipelines regularly and need to use the same settings regularly it may be a good idea to request that your custom config file is uploaded to the `nf-core/configs` git repository. Before you do this please can you test that the config file works with your pipeline of choice using the `-c` parameter. You can then create a pull request to the `nf-core/configs` repository with the addition of your config file, associated documentation file (see examples in [`nf-core/configs/docs`](https://github.com/nf-core/configs/tree/master/docs)), and amending [`nfcore_custom.config`](https://github.com/nf-core/configs/blob/master/nfcore_custom.config) to include your custom profile.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

If you have any questions or issues please send us a message on [Slack](https://nf-co.re/join/slack) on the [`#configs` channel](https://nfcore.slack.com/channels/configs).

## Running in the background

Nextflow handles job submissions and supervises the running jobs. The Nextflow process must run until the pipeline is finished.

The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal so that the workflow does not stop if you log out of your session. The logs are saved to a file.

Alternatively, you can use `screen` / `tmux` or similar tool to create a detached session which you can log back into at a later time.
Some HPC setups also allow you to run nextflow within a cluster job submitted your job scheduler (from where it submits more jobs).

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machines can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
