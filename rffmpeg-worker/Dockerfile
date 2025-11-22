FROM debian:bookworm

ARG JELLYFIN_VERSION=10.10.7

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get -y install --no-install-recommends curl gnupg locales openssh-server nfs-common netbase iputils-ping fontconfig ca-certificates && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen && \
    # Add jellyfin repo using the modern signed-by method
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | gpg --dearmor -o /etc/apt/keyrings/jellyfin.gpg && \
    echo "deb [arch=$( dpkg --print-architecture ) signed-by=/etc/apt/keyrings/jellyfin.gpg] https://repo.jellyfin.org/debian bookworm main" > /etc/apt/sources.list.d/jellyfin.list && \
    # Install jellyfin-ffmpeg7 from the new repo and clean up
    apt-get update && \ 
    apt-get install -y --no-install-recommends jellyfin-ffmpeg7 && \ 
    apt-get purge -y --auto-remove gnupg curl && \ 
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8  
ENV LANGUAGE=en_US:en  
ENV LC_ALL=en_US.UTF-8

# ==============================================================================
# OpenCL Support (Current & Legacy)
# ==============================================================================

# 1. Install Prerequisites
RUN apt-get update && apt-get install -y \
    wget \
    gnupg2 \
    clinfo \
    binutils \
    libnuma1 \
    ocl-icd-libopencl1 \
    && rm -rf /var/lib/apt/lists/*

# Create directories
WORKDIR /tmp/neo

# ==============================================================================
# PHASE 1: Install CURRENT Drivers (Gen12+) - System Wide
# ==============================================================================

# Download the specific version mentioned in your prompt (25.44.36015.5)
RUN wget -q https://github.com/intel/intel-graphics-compiler/releases/download/v2.22.2/intel-igc-core-2_2.22.2+20121_amd64.deb && \
    wget -q https://github.com/intel/intel-graphics-compiler/releases/download/v2.22.2/intel-igc-opencl-2_2.22.2+20121_amd64.deb && \
    wget -q https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/intel-ocloc_25.44.36015.5-0_amd64.deb && \
    wget -q https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/intel-opencl-icd_25.44.36015.5-0_amd64.deb && \
    wget -q https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/libigdgmm12_22.8.2_amd64.deb && \
    wget -q https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/libze-intel-gpu1_25.44.36015.5-0_amd64.deb

# Install them
RUN dpkg -i *.deb || apt-get install -f -y

# Cleanup Current Debrs
RUN rm *.deb

# ==============================================================================
# PHASE 2: Install LEGACY Drivers (Gen8, Gen9, Gen11) - Side-by-Side
# ==============================================================================
# We extract these to a custom folder so they don't overwrite the new drivers.
# We use release 24.35.30872.22 which is the designated legacy branch tip.

WORKDIR /tmp/legacy_neo

# Download Legacy OpenCL ICD and Legacy GMM (Memory Manager)
# Note: We need the legacy GMM because the new GMM might have ABI changes incompatible with the old driver.
RUN wget -q https://github.com/intel/compute-runtime/releases/download/24.35.30872.22/intel-opencl-icd-legacy1_24.35.30872.22_amd64.deb && \
    wget -q https://github.com/intel/compute-runtime/releases/download/24.35.30872.22/libigdgmm12_22.5.0_amd64.deb

# Extract contents (dpkg -x) instead of installing (dpkg -i)
RUN mkdir -p extracted_icd && dpkg -x intel-opencl-icd-legacy1_24.35.30872.22_amd64.deb extracted_icd && \
    mkdir -p extracted_gmm && dpkg -x libigdgmm12_22.5.0_amd64.deb extracted_gmm

# Move the critical libraries to a permanent location
RUN mkdir -p /opt/intel/legacy-opencl && \
    # Copy the Legacy Driver (robust find)
    cp $(find extracted_icd -name "libigdrcl*.so*" | head -n 1) /opt/intel/legacy-opencl/libigdrcl_legacy.so && \
    # Copy the Legacy GMM (robust find) - Ensure it is named libigdgmm.so.12
    cp $(find extracted_gmm -name "libigdgmm*.so*" | head -n 1) /opt/intel/legacy-opencl/libigdgmm.so.12

# Cleanup
WORKDIR /
RUN rm -rf /tmp/legacy_neo

# ==============================================================================
# PHASE 3: Configuration & Binding
# ==============================================================================

# 1. Register the Legacy Driver with the OpenCL Loader
# The loader scans /etc/OpenCL/vendors/*.icd. 
# We point it to our renamed legacy library.
RUN echo "/opt/intel/legacy-opencl/libigdrcl_legacy.so" > /etc/OpenCL/vendors/intel_legacy.icd

# 2. Setup Environment Variables
# We must add the legacy folder to LD_LIBRARY_PATH so the legacy driver can find its specific GMM library.
ENV LD_LIBRARY_PATH="/opt/intel/legacy-opencl"

# Create directories, set permissions, and define NFS mounts for the entrypoint.
RUN (getent group users || groupadd -g 100 users) && \
    mkdir -p /transcodes /cache /config /livetv && \
    chgrp users /transcodes /cache /config /livetv

# Create the transcodessh user for receiving jobs.
RUN useradd -u 7001 -g users -m transcodessh && \
    usermod --shell /bin/bash transcodessh && \
    usermod -aG video,users transcodessh

# Set a global umask to ensure group-writable files.
RUN echo 'umask 002' >> /etc/profile

EXPOSE 22

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
