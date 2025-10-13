ARG JELLYFIN_VERSION=10.10.7
FROM docker.io/jellyfin/jellyfin:${JELLYFIN_VERSION}

ARG RFFMPEG_URL=https://raw.githubusercontent.com/joshuaboniface/rffmpeg/master/rffmpeg

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8  
ENV LANGUAGE=en_US:en  
ENV LC_ALL=en_US.UTF-8
ENV TMPDIR=/cache/temp 

# Installs all system packages, configures rffmpeg, and sets up DVR tools in a single layer.
# This approach is used to minimize the final image size.
RUN apt-get -y update --fix-missing && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        cron \
        python3-click \
        python3-yaml \
        wget \
        git \
        # Comskip build dependencies
        build-essential \
        pkg-config \
        autoconf \
        automake \
        libtool \
        libavformat-dev \
        libargtable2-dev \
        libavutil-dev \
        libavcodec-dev \
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
    # Download the rffmpeg configuration template and customize it for this project's paths and user.
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
    # Install comchap/comcut scripts for DVR commercial processing.
    git clone https://github.com/BrettSheleski/comchap.git /tmp/comchap_src && \
    cp /tmp/comchap_src/comchap /usr/local/bin/ && \
    cp /tmp/comchap_src/comcut /usr/local/bin/ && \
    chmod +x /usr/local/bin/comchap /usr/local/bin/comcut && \
    # Build and install comskip from source for maximum compatibility.
    git clone https://github.com/erikkaashoek/Comskip.git /tmp/comskip_src && \
    cd /tmp/comskip_src && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install && \
    cd / && \
    echo -e "; Minimal default comskip config\nedl_out=1\noutput_edl=1\nverbose=0\nthread_count=0" > /etc/comskip.ini && \
# Removes build-time dependencies (like git) and clears apt caches to reduce image size.
    rm -rf /tmp/comchap_src /tmp/comskip_src && \
    apt-get purge -y --auto-remove wget git build-essential pkg-config autoconf automake libtool libavformat-dev libargtable2-dev libavutil-dev libavcodec-dev && \
    apt-get autoremove -y --purge && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Downloads the rffmpeg binary. 'ADD' is used here because it can handle URLs and
# offers better caching for remote files compared to 'RUN wget'.
ADD ${RFFMPEG_URL} /usr/local/bin/rffmpeg
RUN chmod +x /usr/local/bin/rffmpeg && \
    ln -s /usr/local/bin/rffmpeg /usr/local/bin/ffmpeg && \
    ln -s /usr/local/bin/rffmpeg /usr/local/bin/ffprobe

# Creates the 'transcodessh' user, sets up required directories, and configures permissions.
# This ensures the NFS server and SSH daemon have the correct environment to run in.
RUN \
    (getent group users || groupadd -g 100 users) && \
    useradd -u 7001 -g users -m transcodessh && \
    usermod -a -G video,users,root transcodessh && \
    usermod -a -G users root && \
    mkdir -p /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery && \
    echo "rpc_pipefs  /var/lib/nfs/rpc_pipefs  rpc_pipefs  defaults  0  0" >> /etc/fstab && \
    echo "nfsd        /proc/fs/nfsd            nfsd        defaults  0  0" >> /etc/fstab && \
    mkdir -p /rffmpeg/.ssh /transcodes /cache /cache/temp /config /home/transcodessh/.ssh && \
    chown -R transcodessh:users /home/transcodessh && \
    chown -R transcodessh:users /rffmpeg/.ssh && \
    chmod 700 /home/transcodessh/.ssh /rffmpeg/.ssh && \
    chgrp users /transcodes /cache /cache/temp /config && \
    sed -i \
        -e 's;#   IdentityFile ~/.ssh/id_rsa;   IdentityFile /run/rffmpeg/.ssh/id_rsa;' \
        -e 's;#   UserKnownHostsFile ~/.ssh/known_hosts.d/%k;   UserKnownHostsFile /dev/null ;' \
        -e 's;#   StrictHostKeyChecking ask;    StrictHostKeyChecking no;' \
        /etc/ssh/ssh_config
    
# Copies the container's operational scripts and sets up a cron job.
# The cron job periodically runs the host scaling script to discover and manage worker nodes.
COPY --chown=transcodessh:users rffmpeg-hostscale.sh /rffmpeg-hostscale.sh
COPY --chown=root:root entrypoint.sh /entrypoint.sh
COPY --chown=root:root recording-post-proceessing.sh /recording-post-processing.sh
RUN chmod +x /rffmpeg-hostscale.sh /entrypoint.sh /recording-post-processing.sh && \
    (crontab -l 2>/dev/null; echo "*/15 * * * * /rffmpeg-hostscale.sh"; echo "0 0 * * * /usr/local/bin/rffmpeg clear") | crontab -

ENTRYPOINT ["/entrypoint.sh"]
