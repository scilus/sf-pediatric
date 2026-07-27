ARG BASE_IMAGE=ubuntu:jammy-20240405

# Older Python to support legacy MCRIBS (taken from nibabies Dockerfile)
FROM python:3.6.15-slim AS pyenv
RUN pip install --no-cache-dir numpy nibabel scipy pandas numexpr contextlib2 imageio \
    && cp /usr/lib/x86_64-linux-gnu/libffi.so.7* /usr/local/lib

# Download FSL.
FROM ${BASE_IMAGE} AS build-fsl

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        binutils \
        bzip2 \
        ca-certificates \
        curl \
        unzip \
        && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /
RUN echo "2024.04.25" && curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj
ENV MAMBA_ROOT_PREFIX="/opt/conda"

# Fetch the FSL environment
COPY fsl.yml fsl.yml
RUN micromamba create -y -f fsl.yml && \
    micromamba clean --all --yes
ENV PATH="/opt/conda/envs/fsl/bin:$PATH"

# Set a stage for the build
FROM ${BASE_IMAGE} AS runtime

ENV DEBIAN_FRONTEND="noninteractive" \
    LANG="en_US.UTF-8" \
    LC_ALL="en_US.UTF-8"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        apt-utils \
        bc \
        build-essential \
        ca-certificates \
        curl \
        git \
        gnupg \
        libtool \
        locales \
        lsb-release \
        tcsh \
        netbase \
        unzip \
        xvfb \
        # MCRIBS-required
        libboost-dev \
        libeigen3-dev \
        libflann-dev \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        libssl-dev \
        libxt-dev \
        zlib1g-dev && \
    locale-gen en_US.UTF-8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Configure PPAs for libpng12 and libxp6
RUN GNUPGHOME=/tmp gpg --keyserver hkps://keyserver.ubuntu.com --no-default-keyring --keyring /usr/share/keyrings/linuxuprising.gpg --recv 0xEA8CACC073C3DB2A \
    && GNUPGHOME=/tmp gpg --keyserver hkps://keyserver.ubuntu.com --no-default-keyring --keyring /usr/share/keyrings/zeehio.gpg --recv 0xA1301338A3A48C4A \
    && echo "deb [signed-by=/usr/share/keyrings/linuxuprising.gpg] https://ppa.launchpadcontent.net/linuxuprising/libpng12/ubuntu jammy main" > /etc/apt/sources.list.d/linuxuprising.list \
    && echo "deb [signed-by=/usr/share/keyrings/zeehio.gpg] https://ppa.launchpadcontent.net/zeehio/libxp/ubuntu jammy main" > /etc/apt/sources.list.d/zeehio.list

# Install ANTs
COPY --from=gagnonanthony/ants@sha256:0abd03bc59c10ea4a93e399d07c5e4019cf8eb89963a54e050f209ed73722dce /opt/ants /opt/ants
ENV PATH="/opt/ants/bin:$PATH" \
    ANTSPATH="/opt/ants" \
    LD_LIBRARY_PATH="/opt/ants/lib:$LD_LIBRARY_PATH"

# Install FreeSurfer (with Infant Module)
COPY --from=nipreps/freesurfer@sha256:3b895fc732a7080374a15c4f976510f39c0c48dc76c030ab27316febd5e419ee /opt/freesurfer /opt/freesurfer
ENV FREESURFER_HOME="/opt/freesurfer"
ENV SUBJECTS_DIR="$FREESURFER_HOME/subjects" \
    FUNCTIONALS_DIR="$FREESURFER_HOME/sessions" \
    MNI_DIR="$FREESURFER_HOME/mni" \
    LOCAL_DIR="$FREESURFER_HOME/local" \
    MINC_BIN_DIR="$FREESURFER_HOME/mni/bin" \
    MINC_LIB_DIR="$FREESURFER_HOME/mni/lib" \
    MNI_DATAPATH="$FREESURFER_HOME/mni/data" \
    FSL_DIR=${FSLDIR} \
    FREESURFER="/opt/freesurfer"
ENV PERL5LIB="$MINC_LIB_DIR/perl5/5.8.5" \
    MNI_PERL5LIB="$MINC_LIB_DIR/perl5/5.8.5" \
    PATH="$FREESURFER_HOME/bin:$FREESURFER_HOME/tktools:$MINC_BIN_DIR:$PATH"

# Install MCRIBS from nipreps (with legacy Python)
COPY --from=gagnonanthony/mcribs@sha256:12ddd74a0d47f055bea4bb19cc0df5b39d0b3ee2aa76d4276d4bfea6f169b2b5 /opt/MCRIBS/ /opt/MCRIBS
COPY --from=pyenv /usr/local/lib/ /usr/local/lib/
COPY --from=pyenv /usr/local/bin/python3 /opt/MCRIBS/bin/python
ENV PATH="/opt/MCRIBS/bin:/opt/MCRIBS/MIRTK/MIRTK-install/bin:/opt/MCRIBS/MIRTK/MIRTK-install/lib/tools:${PATH}" \
    LD_LIBRARY_PATH="/opt/MCRIBS/lib:/opt/MCRIBS/ITK/ITK-install/lib:/opt/MCRIBS/VTK/VTK-install/lib:/opt/MCRIBS/MIRTK/MIRTK-install/lib:/usr/local/lib:${LD_LIBRARY_PATH}" \
    MCRIBS_HOME="/opt/MCRIBS" \
    PYTHONPATH="/opt/MCRIBS/lib/python:/usr/local/lib/python3.6/site-packages/:${PYTHONPATH}"

# Install FSL
COPY --from=build-fsl /bin/micromamba /bin/micromamba
COPY --from=build-fsl /opt/conda/envs/fsl /opt/conda/envs/fsl
ENV MAMBA_ROOT_PREFIX="/opt/conda" \
    PATH="${PATH}:/opt/conda/envs/fsl/bin" \
    CPATH="/opt/conda/envs/fsl/include:${CPATH}" \
    LD_LIBRARY_PATH="/opt/conda/envs/fsl/lib:${LD_LIBRARY_PATH}" \
    CONDA_PYTHON="/opt/conda/envs/fsl/bin/python"

# FSL environment.
ENV LANG="C.UTF-8" \
    LC_ALL="C.UTF-8" \
    PYTHONNOUSERSITE=1 \
    FSLDIR="/opt/conda/envs/fsl" \
    FSLOUTPUTTYPE="NIFTI_GZ" \
    FSLMULTIFILEQUIT="TRUE" \
    FSLLOCKDIR="" \
    FSLMACHINELIST="" \
    FSLREMOTECALL="" \
    FSLGECUDAQ="cuda.q"

# Fix MCRIBS scripts for new nibabel 4D handling.
RUN sed -i \
    -e 's/ASEGIMG = numpy.asanyarray(ASEGNII.dataobj)/ASEGIMG = numpy.squeeze(numpy.asanyarray(ASEGNII.dataobj))/g' \
    -e 's/DrawEMLabelsIMG = numpy.asanyarray(DrawEMLabelsNII.dataobj)/DrawEMLabelsIMG = numpy.squeeze(numpy.asanyarray(DrawEMLabelsNII.dataobj))/g' \
    /opt/MCRIBS/bin/APARC2ASEGCSFRestoreDrawEM
