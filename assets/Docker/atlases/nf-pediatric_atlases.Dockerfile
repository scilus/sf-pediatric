ARG FREESURFER_BUILD_IMAGE=vnmd/freesurfer:7.4.1
ARG SCILPY_BASE_IMAGE=scilus/scilpy:2.2.2_cpu

# Create a stage to build the freesurfer image (only essential scripts).
FROM $FREESURFER_BUILD_IMAGE AS build_freesurfer

ENV LANG=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# Install packages needed for build
RUN rm -rf \
    /opt/freesurfer-7.4.1/average \
    /opt/freesurfer-7.4.1/docs \
    /opt/freesurfer-7.4.1/etc \
    /opt/freesurfer-7.4.1/models \
    /opt/freesurfer-7.4.1/sessions \
    /opt/freesurfer-7.4.1/matlab \
    /opt/freesurfer-7.4.1/fsfast \
    /opt/freesurfer-7.4.1/diffusion \
    /opt/freesurfer-7.4.1/fsafd \
    /opt/freesurfer-7.4.1/MCRv97 \
    /opt/freesurfer-7.4.1/subjects \
    /opt/freesurfer-7.4.1/trctrain \
    /opt/freesurfer-7.4.1/python/lib/python3.8/site-packages/tensorflow* \
    /opt/freesurfer-7.4.1/python/lib/python3.8/site-packages/torch* \
    /opt/freesurfer-7.4.1/python/lib/python3.8/site-packages/nvidia*

# Main stage from scilpy base image.
FROM $SCILPY_BASE_IMAGE AS runtime

ENV LANG=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages for freesurfer to dry_run
RUN apt-get update && apt-get install -y --no-install-recommends \
      bc \
      ca-certificates \
      gawk \
      gnupg \
      libgomp1 \
      libglu1-mesa \
      libjpeg62 \
      libpng16-16 \
      libxt6 \
      libxmu6 \
      libgl1 \
      freeglut3-dev \
      python3.10 \
      wget \
      curl \
      time \
      tcsh && \
      if [ "TARGETARCH" = "amd64" ]; then \
      apt-get install -y libquadmath0; \
      fi && \
    apt clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install connectome workbench
RUN wget -O- http://neuro.debian.net/lists/jammy.us-tn.libre | tee /etc/apt/sources.list.d/neurodebian.sources.list && \
      wget -q -O/etc/apt/trusted.gpg.d/neuro.debian.net.asc https://neuro.debian.net/_static/neuro.debian.net.asc && \
      apt-get update && \
      apt-get install -y connectome-workbench && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Installing Parallel
# Installing dependencies.
RUN (wget -O - pi.dk/3 || curl pi.dk/3/) | bash
RUN echo 'will cite' | parallel --citation 1> /dev/null 2> /dev/null &
RUN rm parallel*.tar.bz2*

# Add FreeSurfer and python Environment variables
# DO_NOT_SEARCH_FS_LICENSE_IN_FREESURFER_HOME=true deactivates the search for FS_LICENSE in FREESURFER_HOME
ENV OS=Linux \
    FS_OVERRIDE=0 \
    FIX_VERTEX_AREA="" \
    SUBJECTS_DIR=/opt/freesurfer/subjects \
    FSF_OUTPUT_FORMAT=nii.gz \
    FREESURFER_HOME=/opt/freesurfer \
    PYTHONUNBUFFERED=0 \
    MPLCONFIGDIR=/tmp \
    PATH=/venv/bin:/opt/freesurfer/bin:$PATH \
    PYTHONPATH=opt/freesurfer/python/packages:$PYTHONPATH \
    MPLCONFIGDIR=/tmp/matplotlib-config \
    DO_NOT_SEARCH_FS_LICENSE_IN_FREESURFER_HOME="true"

COPY --from=build_freesurfer /opt/freesurfer-7.4.1/ /opt/freesurfer
