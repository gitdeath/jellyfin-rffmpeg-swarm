FROM debian:bookworm

ARG JELLYFIN_VERSION=10.10.7

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get -y install --no-install-recommends curl gnupg locales openssh-server nfs-common netbase iputils-ping fontconfig intel-opencl-icd ca-certificates && \
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

# Create directories, set permissions, and define NFS mounts for the entrypoint.
RUN (getent group users || groupadd -g 100 users) && \
    mkdir -p /transcodes /cache /config && \
    chgrp users /transcodes /cache /config

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
