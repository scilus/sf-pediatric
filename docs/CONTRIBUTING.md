---
title: Contributing
---

# Contributing to scilus/sf-pediatric

Thanks for helping improve **sf-pediatric**, an [nf-neuro](https://nf-neuro.github.io/welcome) pipeline for pediatric diffusion MRI (0–18 years).

Link to the documentation: [scilus.github.io/sf-pediatric](https://scilus.github.io/sf-pediatric/).
Questions and discussion: GitHub [issues](https://github.com/scilus/sf-pediatric/issues).

## Where to contribute

All type of contributions are accepted! However, their destination might change depending of what they are targeting. Here is a table to help guide towards the most appropriate destination:

| Kind of change                                                 | Where it belongs                                                                                                                                                                                                                                                                  |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Workflow wiring, parameters, profiles, tests, QC reports, docs | This repository                                                                                                                                                                                                                                                                   |
| Reusable neuroimaging process or subworkflow                   | [nf-neuro/modules](https://github.com/nf-neuro/modules) — follow [create a module](https://nf-neuro.github.io/contribute/create-your-module/1-template) or [create a subworkflow](https://nf-neuro.github.io/contribute/create-your-subworkflow/1-template), then install it here |
| Pediatric-only or not ready upstream                           | `modules/local/` or `subworkflows/local/`                                                                                                                                                                                                                                         |

Reusable-component tutorials can be seen on the [nf-neuro website](https://nf-neuro.github.io/contribute/setup). The current guidelines will cover how to modify the current pipeline.

## Quick start

- [ ] Open or comment on a GitHub [issue](https://github.com/scilus/sf-pediatric/issues) so others know you are working on it.
- [ ] [Fork](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo) [`scilus/sf-pediatric`](https://github.com/scilus/sf-pediatric) and branch from `dev`.
- [ ] Use [GitHub Codespaces](https://github.com/codespaces/new/scilus/sf-pediatric) or the repo [devcontainer](../.devcontainer/devcontainer.json). For nf-neuro module work, use the [nf-neuro contribution setup](https://nf-neuro.github.io/contribute/setup).
- [ ] Make the change, then update `CHANGELOG.md` (Keep a Changelog; add the entry under the current unreleased version).
- [ ] Update `nextflow_schema.json` when necessary
- [ ] Update the [documentation](https://scilus.github.io/sf-pediatric/) when necessary and tag associated PRs.
- [ ] [Lint](#testing-and-linting) and run the relevant [nf-test](#testing-and-linting) profile(s).
- [ ] Open a pull request against **`dev`** and request a review.

PRs to `main` or `master` are not accepted, they should be directed towards the **`dev`** branch.

New to GitHub PRs? See [GitHub’s collaboration docs](https://docs.github.com/en/pull-requests).

## Repository map

| Path                                                                                                                                    | What to edit there                                                                               |
| --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| [`workflows/sf_pediatric.nf`](../workflows/sf_pediatric.nf)                                                                             | Main workflow file                                                                               |
| [`conf/*.config`](../conf)                                                                                                              | Modules' `ext.*` options (`dwi_preprocessing`, `tracking`, `bundleseg`, `connectomics`, `qc`, …) |
| [`nextflow.config`](../nextflow.config)                                                                                                 | Default parameters and Nextflow profiles                                                         |
| [`nextflow_schema.json`](../nextflow_schema.json)                                                                                       | Parameter documentation and validation                                                           |
| [`modules.json`](../modules.json)                                                                                                       | Pinned nf-neuro / nf-core modules and optional `.diff` patches                                   |
| [`tests/*.nf.test`](../tests)                                                                                                           | Test suites                                                                                      |
| [`assets/multiqc_config.yml`](../assets/multiqc_config.yml) / [`assets/multiqc_config_global.yml`](../assets/multiqc_config_global.yml) | Subject-level and global MultiQC sections                                                        |

## Install or update nf-neuro components

This pipeline’s default module remote is [`nf-neuro/modules`](https://github.com/nf-neuro/modules) (`main`). List, install, and update with nf-core/tools — same commands as in the [nf-neuro pipeline tutorial](https://nf-neuro.github.io/pipeline/5-tutorial_step_4):

```bash
nf-core modules list remote
nf-core modules install <category/tool>
nf-core modules update <category/tool>
nf-core subworkflows install <name>
```

Inputs, outputs, and `ext.*` options are documented in the [nf-neuro API](https://nf-neuro.github.io/api).

`modules.json` may record a `patch` (for example `bundle/recognize`, `preproc/eddy`). Prefer fixing the component upstream. Keep a `.diff` only when the change must stay pipeline-specific.

## Add a pipeline step

- [ ] Reuse an existing nf-neuro module or subworkflow when one exists.
- [ ] Include and call it from `workflows/sf_pediatric.nf` or appropriate local subworkflow.
- [ ] Set `ext.*` in the matching file under `conf/`.
- [ ] Add new parameters in `nextflow.config` with a default, then edit the schema to reflect those changes.
- [ ] Mix software versions into `ch_versions`. Mix QC outputs (`mqc` / PNG / TSV) into the local [`QC` subworkflow](../subworkflows/local/QC/qc.nf).
- [ ] Extend the matching test in `tests/` (`tracking.nf.test`, `segmentation.nf.test`, `bundleseg.nf.test`, `connectomics.nf.test`, `chained.nf.test`, or `gpu.nf.test`).
- [ ] Update the [sf-pediatric-documentation](https://github.com/scilus/sf-pediatric-documentation) if needed.
- [ ] If you add `*_mqc.png` (or similar) files, update section order in `assets/multiqc_config.yml`.

## Testing and linting

GitHub Actions run nf-test, prek (Prettier, nextflow-lint, and a hook that blocks committing pipeline `outdir`), and `nf-core pipelines lint`. PRs are usually reviewed once those checks pass.

This repo’s nf-test config **ignores** tests under `modules/**` and `subworkflows/**`. To run the pipeline tests use:

```bash
nf-test test tests/tracking.nf.test --profile=+docker
# Or when you want to update the snapshots
nf-test test tests/tracking.nf.test --updateSnapshot --cleanSnapshot --profile=+docker
```

Lint:

```bash
nf-core pipelines lint
```
