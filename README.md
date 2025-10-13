# Jellyfin RFFMPEG Swarm

This project creates a scalable, distributed Jellyfin media server using Docker Swarm. It solves the common challenge of CPU-intensive video transcoding by offloading the work from the main Jellyfin server to a cluster of dedicated worker nodes.

## Overview

The architecture is composed of two primary services that communicate over a secure Docker overlay network:

-   **`jellyfin-server`**: The main Jellyfin instance. It does not perform transcodes itself but instead delegates them to available workers via SSH using `rffmpeg`. This service also runs an integrated **NFS server** to share the `/transcodes` and `/cache` directories, ensuring all nodes have access to the same temporary files.
-   **`transcode-worker`**: The workhorses of the cluster. These are lightweight, scalable containers that listen for transcoding jobs from the server. You can add or remove workers on-the-fly to match your expected transcoding load.

## Host Setup Guide

The following steps must be performed on **all nodes** in your Docker Swarm cluster to ensure they are properly configured.

### 1. OS and Hardware
-   **Operating System**: A recent Debian or Ubuntu LTS release.
-   **CPU**: An Intel CPU that supports Quick Sync Video (QSV).
-   **Storage**: An SSD is highly recommended for the `/transcodes` and `/cache` directories to handle the high I/O of transcoding.

### 2. Install System Dependencies
Install the necessary packages for NFS client/server functionality and Intel hardware acceleration.
```bash
sudo apt update
sudo apt install -y nfs-common nfs-kernel-server intel-opencl-icd
```

### 3. Configure Kernel and Drivers
-   **Load Kernel Modules**: Ensure the required NFS and Intel graphics modules are loaded on boot.
    ```bash
    sudo sh -c "echo 'nfsd' >> /etc/modules"
    sudo sh -c "echo 'nfs' >> /etc/modules"
    sudo modprobe nfsd nfs
    ```
-   **Enable Intel QSV**: Follow the official Jellyfin documentation to enable Intel QSV, apply any necessary kernel patches, and configure Low-Power (LP) mode for your hardware.
    -   **Jellyfin Intel Hardware Acceleration Guide**: jellyfin.org/docs/administration/hardware-acceleration/intel

### 4. Create Host Directories
Create the directories on the host that the `jellyfin-server` container will use for its internal NFS exports.
```bash
sudo mkdir -p /transcodes /cache
sudo chgrp users /transcodes /cache
sudo chmod 775 /transcodes /cache
```

### 5. Disable AppArmor (Critical)
AppArmor's security policies prevent the `jellyfin-server` container from acquiring the permissions needed to run its own NFS server. It must be disabled on the host.
```bash
sudo systemctl stop apparmor && sudo systemctl disable apparmor
sudo apt purge -y apparmor
# This command adds 'apparmor=0' to the kernel boot parameters
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 apparmor=0"/' /etc/default/grub
sudo update-grub
```
**A reboot is required** for this change to take effect.

### 6. Configure Docker Swarm
-   Install Docker and initialize your Swarm cluster if you haven't already.
-   Deploy the `device-mapping-manager` on each node. This utility ensures that GPU devices (`/dev/dri`) are correctly mapped to containers across the Swarm.
    ```bash
    docker run -d --restart always --name device-manager --privileged \
      --cgroupns=host --pid=host --userns=host \
      -v /sys:/host/sys -v /var/run/docker.sock:/var/run/docker.sock \
      ghcr.io/gitdeath/device-mapping-manager:master
    ```

## Production Deployment

Follow these steps on your Docker Swarm manager node.

### 1. Prepare Deployment Files
Create a directory for your stack and download the compose file.
```bash
mkdir -p ~/jellyfin-swarm && cd ~/jellyfin-swarm
wget https://raw.githubusercontent.com/gitdeath/jellyfin-rffmpeg-swarm/main/docker-compose.yml
```

### 2. Generate and Store SSH Keys
Generate an SSH key pair and store it securely as Docker secrets. These keys are used for communication between the server and workers.
```bash
ssh-keygen -t rsa -b 4096 -f ./rffmpeg_id_rsa -q -N ""

# Create the secrets in Docker Swarm
docker secret create jellyfin_rffmpeg_id_rsa ./rffmpeg_id_rsa
docker secret create jellyfin_rffmpeg_id_rsa_pub ./rffmpeg_id_rsa.pub

# For security, remove the key files from the host after creating the secrets
rm ./rffmpeg_id_rsa ./rffmpeg_id_rsa.pub
```

### 3. Configure and Deploy
Before deploying, you **must** edit `docker-compose.yml` and update the `volumes` section to point to your external NFS server for `media`, `jellyfin_config`, and `livetv`.

```bash
# Example of editing the file
nano docker-compose.yml

# Deploy the stack
docker stack deploy -c docker-compose.yml jellyfin
```

### 4. Verify and Scale
Check the status of your services to ensure they are running correctly.
```bash
docker stack services jellyfin
```
Once verified, you can access the Jellyfin UI at `http://<YOUR_SWARM_IP>:8096` and scale your workers as needed.
```bash
# Scale to 5 workers
docker service scale jellyfin_transcode-worker=5
```

## Development Environment

This repository includes a `docker-compose.dev.yml` file for testing development builds, which are tagged with `:dev` in the container registry.

### 1. Deploy the Dev Stack
1.  Download the `docker-compose.dev.yml` file.
2.  **Important**: Edit the `volumes` section to point to separate `_dev` paths on your NFS server to avoid data conflicts with production.
3.  Deploy the stack with a unique name (e.g., `jellyfin-dev`).

```bash
wget https://raw.githubusercontent.com/gitdeath/jellyfin-rffmpeg-swarm/main/docker-compose.dev.yml
docker stack deploy -c docker-compose.dev.yml jellyfin-dev
```

### 2. Development SSH Keys
The development stack requires its own set of SSH keys to maintain isolation.
```bash
# Generate a new key pair specifically for development
ssh-keygen -t rsa -b 4096 -f ./rffmpeg_id_rsa_dev -q -N ""

# Create the development secrets in Docker Swarm
docker secret create jellyfin_rffmpeg_id_rsa_dev ./rffmpeg_id_rsa_dev
docker secret create jellyfin_rffmpeg_id_rsa_pub_dev ./rffmpeg_id_rsa_dev.pub
```

## DVR and Live TV Features

This project is pre-configured to enhance Jellyfin's DVR functionality with automated commercial processing.

### Recording Path

The default recording path is automatically set to `/livetv`. You **must** configure the `livetv` volume in `docker-compose.yml` to point to a persistent storage location for your DVR recordings.

### Automated Commercial Processing

The `jellyfin-server` is configured to automatically run a post-processing script on recordings. This script uses `comskip` to detect commercials and has two modes:

-   **`comchap` (Default)**: This non-destructive mode adds chapter markers to the video file, allowing you to skip commercial breaks easily.
-   **`comcut` (Optional)**: This destructive mode creates a new version of the recording with commercials physically removed, then replaces the original file.

You can change this behavior from the Jellyfin dashboard by navigating to **Dashboard -> Live TV -> DVR Settings** and editing the **Post-processor command line arguments** field.
-   To enable commercial cutting, change the value to: `"{path}" comcut`
-   To use the default chapter mode, use: `"{path}" comchap`

Logs for all post-processing jobs are stored in `/config/logs/post-processing_YYYY-MM-DD.log`.

## Architecture Deep Dive: The Embedded NFS Server

A key feature of this project is the NFS server running *inside* the `jellyfin-server` container. This is a deliberate design choice to solve a critical problem in distributed transcoding.

-   **Why it's necessary**: When a worker transcodes a file, it writes temporary chunks and the final output to a specific path (e.g., `/transcodes/xyz.ts`). The main Jellyfin server must then be able to read from that *exact same path* to serve the file to the client. By having the server export `/transcodes` and `/cache`, we guarantee that both the server and all workers share a consistent, writable view of these directories.
-   **Elevated Privileges**: Mounting an NFS share from within a container requires elevated privileges. This is why the `transcode-worker` service needs `cap_add: [SYS_ADMIN]` in the compose file. This allows it to run `mount -a` and connect to the server's exports.
-   **Troubleshooting**: If workers fail to start, check their logs for `mount` errors. This usually indicates a problem with network connectivity to the server container or a lack of `SYS_ADMIN` capability.

## Credits

This project builds on and uses work from the following upstream projects — thank you to the original authors:

-   **rffmpeg** (Joshua Boniface) — Provides the remote-ffmpeg tooling used to distribute transcoding jobs.
-   **docker-nfs-server** (obeone) — The NFS server logic and parts of the `entrypoint.sh` are adapted from this project.
-   **Jellyfin** — The upstream open-source media server.
-   **device-mapping-manager** (allfro) — Allows GPU devices to be mapped correctly within the Swarm.
-   **Comskip** (Erik Kaashoek) — The core commercial detection engine.
-   **comchap** (Brett Sheleski) — The scripts used for DVR post-processing.

The `jellyfin-server/entrypoint.sh` file includes an attribution header pointing to the NFS server project from which parts of the script were adapted. This repository is independently developed and maintained by the project owner and is not affiliated with the original authors. Please refer to the linked upstream repositories for their full documentation, source, and license terms.