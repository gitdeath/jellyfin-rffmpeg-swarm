ARG JELLYFIN_VERSION=10.10.7
FROM docker.io/jellyfin/jellyfin:${JELLYFIN_VERSION}

ARG RFFMPEG_URL=https://raw.githubusercontent.com/joshuaboniface/rffmpeg/master/rffmpeg

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8  
ENV LANGUAGE=en_US:en  
ENV LC_ALL=en_US.UTF-8 

# Install dependencies, configure rffmpeg.yml, set locale, and clean up in a single layer.
# wget is installed for the download and purged in the same layer to keep the image small.
RUN apt-get -y update --fix-missing && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        cron \
        python3-click \
        python3-yaml \
        wget \
        nfs-common \
        nfs-kernel-server \
        libcap2-bin \
        kmod \
        procps \
        netbase \
        iputils-ping \
        locales \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen && \
    # Download and modify rffmpeg.yml, preserving the original file's structure
    mkdir -p /tmp/rffmpeg && \
    wget https://raw.githubusercontent.com/joshuaboniface/rffmpeg/master/rffmpeg.yml.sample -O /tmp/rffmpeg/rffmpeg.yml && \
    sed -i 's;#logfile: "/var/log/jellyfin/rffmpeg.log";logfile: "/config/log/rffmpeg.log";' /tmp/rffmpeg/rffmpeg.yml && \
    sed -i 's;#datedlogfiles: false;datedlogfiles: true;' /tmp/rffmpeg/rffmpeg.yml && \
    sed -i 's;#datedlogdir: "/var/log/jellyfin/";datedlogdir: "/config/log";' /tmp/rffmpeg/rffmpeg.yml && \
    sed -i 's;#state: "/var/lib/rffmpeg";state: "/rffmpeg";' /tmp/rffmpeg/rffmpeg.yml && \
    sed -i 's;#persist: "/run/shm";persist: "/run";' /tmp/rffmpeg/rffmpeg.yml && \
    sed -i 's;#owner: jellyfin;owner: root;' /tmp/rffmpeg/rffmpeg.yml && \
    sed -i 's;#group: sudo;group: users;' /tmp/rffmpeg/rffmpeg.yml && \
    sed -i 's;#user: jellyfin;user: transcodessh;' /tmp/rffmpeg/rffmpeg.yml && \
    sed -i 's;#args:;args:;' /tmp/rffmpeg/rffmpeg.yml && \
    sed -i 's;#    - "-i";    - "-i";' /tmp/rffmpeg/rffmpeg.yml && \
    sed -i 's;#    - "/var/lib/jellyfin/id_rsa";    - "/run/rffmpeg/.ssh/id_rsa";' /tmp/rffmpeg/rffmpeg.yml && \
    # Clean up apt cache and remove wget
    apt-get purge -y wget && \
    apt-get autoremove -y --purge && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install rffmpeg using ADD for better caching and create symlinks
ADD ${RFFMPEG_URL} /usr/local/bin/rffmpeg
RUN chmod +x /usr/local/bin/rffmpeg && \
    ln -s /usr/local/bin/rffmpeg /usr/local/bin/ffmpeg && \
    ln -s /usr/local/bin/rffmpeg /usr/local/bin/ffprobe

# Consolidate user setup, directory creation, and permissions into a single layer.
RUN \
    # Ensure 'users' group exists, creating it if necessary.
    (getent group users || groupadd -g 100 users) && \
    # Create the transcodessh user and add it to necessary groups.
    useradd -u 7001 -g users -m transcodessh && \
    usermod -a -G video,users,root transcodessh && \
    # Add root to the users group for shared volume access.
    usermod -a -G users root && \
    # Create required directories for NFS, volumes, and SSH keys.
    mkdir -p /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery && \
    echo "rpc_pipefs  /var/lib/nfs/rpc_pipefs  rpc_pipefs  defaults  0  0" >> /etc/fstab && \
    echo "nfsd        /proc/fs/nfsd            nfsd        defaults  0  0" >> /etc/fstab && \
    mkdir -p /rffmpeg/.ssh /transcodes /cache /cache/temp /config /home/transcodessh/.ssh && \
    # Set correct ownership and permissions for user home and SSH directories.
    chown -R transcodessh:users /home/transcodessh && \
    chown -R transcodessh:users /rffmpeg/.ssh && \
    chmod 700 /home/transcodessh/.ssh /rffmpeg/.ssh && \
    # Set group ownership on volume mount points.
    chgrp users /transcodes /cache /cache/temp /config && \
    # Modify ssh_config in-place to allow non-interactive SSH.
    sed -i \
        -e 's;#   IdentityFile ~/.ssh/id_rsa;   IdentityFile /run/rffmpeg/.ssh/id_rsa;' \
        -e 's;#   UserKnownHostsFile ~/.ssh/known_hosts.d/%k;   UserKnownHostsFile /dev/null ;' \
        -e 's;#   StrictHostKeyChecking ask;    StrictHostKeyChecking no;' \
        /etc/ssh/ssh_config
    
COPY --chown=transcodessh:users rffmpeg-hostscale.sh /rffmpeg-hostscale.sh
COPY --chown=root:root entrypoint.sh /entrypoint.sh
RUN chmod +x /rffmpeg-hostscale.sh /entrypoint.sh && \
    (crontab -l 2>/dev/null; echo "*/15 * * * * /rffmpeg-hostscale.sh"; echo "0 0 * * * /usr/local/bin/rffmpeg clear") | crontab -

ENTRYPOINT ["/entrypoint.sh"]
