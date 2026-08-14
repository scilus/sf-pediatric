FROM rockylinux:8.9 AS build-fsl

RUN dnf -y update && \
    dnf -y install --nogpgcheck \
        curl \
        bzip2 \
        && dnf clean all

WORKDIR /
RUN echo "2024.04.25" && curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj
ENV MAMBA_ROOT_PREFIX="/opt/conda"

# Fetch the FSL environment
COPY fsl.yml fsl.yml
RUN micromamba create -y -f fsl.yml && \
    micromamba clean --all --yes
ENV PATH="/opt/conda/envs/fsl/bin:$PATH"

FROM freesurfer/freesurfer:8.2.0 AS build_freesurfer
# Bring over freesurfer from official release
RUN rm -rf \
        /usr/local/freesurfer/8.2.0-1/average/AAN \
        /usr/local/freesurfer/8.2.0-1/average/3T18yoSchwartz* \
        /usr/local/freesurfer/8.2.0-1/average/711-2B* \
        /usr/local/freesurfer/8.2.0-1/average/SVIP* \
        /usr/local/freesurfer/8.2.0-1/average/RLB700* \
        /usr/local/freesurfer/8.2.0-1/average/RB_all* \
        /usr/local/freesurfer/8.2.0-1/average/aseg+spmhead* \
        /usr/local/freesurfer/8.2.0-1/average/face.gca \
        /usr/local/freesurfer/8.2.0-1/average/label_scales.dat \
        /usr/local/freesurfer/8.2.0-1/average/mideface-atlas \
        /usr/local/freesurfer/8.2.0-1/average/wmsa_new_eesmith.gca \
        /usr/local/freesurfer/8.2.0-1/average/talairach_mixed_with_skull.gca \
        /usr/local/freesurfer/8.2.0-1/average/BrainstemSS \
        /usr/local/freesurfer/8.2.0-1/average/HippoSF \
        /usr/local/freesurfer/8.2.0-1/average/PALS_B12.readme \
        /usr/local/freesurfer/8.2.0-1/average/ThalamicNuclei \
        /usr/local/freesurfer/8.2.0-1/average/samseg \
        /usr/local/freesurfer/8.2.0-1/average/mni_icbm152_nlin_asym_09c \
        /usr/local/freesurfer/8.2.0-1/average/mult-comp-cor \
        /usr/local/freesurfer/8.2.0-1/average/Choi_JNeurophysiol12_MNI152 \
        /usr/local/freesurfer/8.2.0-1/average/Buckner_JNeurophysiol11_MNI152 \
        /usr/local/freesurfer/8.2.0-1/average/Yeo_Brainmap_MNI152 \
        /usr/local/freesurfer/8.2.0-1/average/Yeo_JNeurophysiol11_MNI152 \
        /usr/local/freesurfer/8.2.0-1/bin/freeview \
        /usr/local/freesurfer/8.2.0-1/diffusion \
        /usr/local/freesurfer/8.2.0-1/matlab \
        /usr/local/freesurfer/8.2.0-1/models/easyreg* \
        /usr/local/freesurfer/8.2.0-1/sessions \
        /usr/local/freesurfer/8.2.0-1/fsfast \
        /usr/local/freesurfer/8.2.0-1/fsafd \
        /usr/local/freesurfer/8.2.0-1/subjects/bert \
        /usr/local/freesurfer/8.2.0-1/subjects/V1_average \
        /usr/local/freesurfer/8.2.0-1/subjects/cvs_avg35 \
        /usr/local/freesurfer/8.2.0-1/subjects/cvs_avg35_inMNI152 \
        /usr/local/freesurfer/8.2.0-1/subjects/fsaverage3 \
        /usr/local/freesurfer/8.2.0-1/subjects/fsaverage4 \
        /usr/local/freesurfer/8.2.0-1/subjects/fsaverage5 \
        /usr/local/freesurfer/8.2.0-1/subjects/fsaverage6 \
        /usr/local/freesurfer/8.2.0-1/subjects/fsaverage_sym \
        /usr/local/freesurfer/8.2.0-1/subjects/lh.EC_average \
        /usr/local/freesurfer/8.2.0-1/subjects/rh.EC_average \
        /usr/local/freesurfer/8.2.0-1/subjects/sample* \
        /usr/local/freesurfer/8.2.0-1/trctrain \
        /usr/local/freesurfer/8.2.0-1/MCRv97 \
        /usr/local/freesurfer/8.2.0-1/models \
        /usr/local/freesurfer/8.2.0-1/python/lib/python3.8/site-packages/tensorflow*

# Set the runtime stage
FROM rockylinux:8.9 AS runtime

# Install freesurfer dependencies
RUN dnf -y update && \
    dnf -y install --nogpgcheck \
        libgomp \
        procps-ng \
        libXt \
        libXext \
        libtiff \
        libpng15 \
        tcsh \
        bc \
        ncurses-compat-libs \
        unzip && \
    dnf clean all

COPY --from=build-fsl /bin/micromamba /bin/micromamba
COPY --from=build-fsl /opt/conda/envs/fsl /opt/conda/envs/fsl
COPY --from=build_freesurfer /usr/local/freesurfer/8.2.0* /opt/freesurfer

# Set environment variables for FreeSurfer and FSL
ENV MAMBA_ROOT_PREFIX="/opt/conda" \
    PATH="${PATH}:/opt/conda/envs/fsl/bin" \
    CPATH="/opt/conda/envs/fsl/include:${CPATH}" \
    LD_LIBRARY_PATH="/opt/conda/envs/fsl/lib:${LD_LIBRARY_PATH}" \
    CONDA_PYTHON="/opt/conda/envs/fsl/bin/python"
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
ENV USER=freesurfer \ 
    LOGNAME=freesurfer
