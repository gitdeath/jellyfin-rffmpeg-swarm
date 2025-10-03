# Jellyfin RFFMPEG Swarm

This project provides a scalable, containerized Jellyfin setup using `rffmpeg` to distribute transcoding jobs across multiple worker nodes in a Docker Swarm cluster.

## Architecture

The stack consists of two core services managed by Docker Compose:

-   **`jellyfin-server`**: The main Jellyfin instance. It does not perform transcodes itself but instead delegates them to available workers via SSH using `rffmpeg`. This service also runs an integrated **NFS server** to provide shared storage for the `/transcodes` and `/cache` directories, ensuring all nodes have access to the same media files.
-   **`transcode-worker`**: A scalable service that receives and executes transcoding jobs from the server. You can scale the number of workers up or down based on demand.

All communication, including SSH for transcoding and NFS for file sharing, happens over a dedicated Docker overlay network.

## Host System Requirements

All nodes in your Docker Swarm cluster must be properly configured to support this stack. The following setup is assumed for each host system.

### 1. Hardware & OS
-   **OS**: Debian or Ubuntu.
-   **CPU**: Intel CPU with Quick Sync Video (QSV) support.
-   **Storage**: An SSD with sufficient space for transcodes in `/transcodes` and `/cache`.

### 2. Docker
-   Docker is installed and configured as a Swarm cluster.

### 3. Intel Hardware Acceleration Setup
-   Follow the official Jellyfin documentation to enable Intel QSV, fix kernel issues, and set up Low Power (LP) mode.
    -   **Verification**: [Jellyfin Intel Hardware Acceleration](https://jellyfin.org/docs/general/administration/hardware-acceleration/intel/)
    -   **Low Power Mode**: [Jellyfin Intel LP Mode Setup](https://jellyfin.org/docs/general/administration/hardware-acceleration/intel/#lp-mode-hardware-support)

-   Install the Intel OpenCL driver:
    ```bash
    sudo apt install intel-opencl-icd
    ```

### 4. NFS Setup
-   Install NFS packages and ensure kernel modules are loaded on boot:
    ```bash
    sudo apt install nfs-common nfs-kernel-server
    sudo sh -c "echo 'nfsd' >> /etc/modules"
    sudo sh -c "echo 'nfs' >> /etc/modules"
    sudo modprobe nfsd nfs
    ```

### 5. Disable AppArmor
-   AppArmor can interfere with the permissions needed by the NFS server running inside the container. It must be disabled.
    ```bash
    sudo systemctl stop apparmor.service
    sudo systemctl disable apparmor.service
    sudo apt purge apparmor
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT="apparmor=0"/' /etc/default/grub
    sudo update-grub
    ```
    A reboot is required after updating grub.

### 6. Create Shared Directories
-   Create the directories that the `jellyfin-server` will export via NFS.
    ```bash
    sudo mkdir /transcodes
    sudo chgrp users /transcodes
    sudo chmod 775 /transcodes
    
    sudo mkdir /cache
    sudo chgrp users /cache
    sudo chmod 775 /cache
    ```

### 7. Enable Swarm Device Mapping
-   Run the `device-mapping-manager` on each node to allow GPU devices (`/dev/dri`) to be mapped correctly within the Swarm.
    ```bash
    docker run -i --restart always -d --name device-manager --privileged \
      --cgroupns=host --pid=host --userns=host \
      -v /sys:/host/sys -v /var/run/docker.sock:/var/run/docker.sock \
      ghcr.io/gitdeath/device-mapping-manager:master
    ```

## Deployment Instructions

### 1. Prepare Deployment Files

On your Docker Swarm manager node, create a directory and download the necessary `docker-compose.yml` file.

```bash
mkdir jellyfin-swarm && cd jellyfin-swarm

wget https://raw.githubusercontent.com/gitdeath/jellyfin-rffmpeg-swarm/main/docker-compose.yml
```

### 2. Generate SSH Keys

Generate the required SSH key pair. Then, create Docker secrets from these files. This stores the keys securely in the Swarm cluster, making them available to any node.

```bash
ssh-keygen -t rsa -b 4096 -f ./rffmpeg_id_rsa -q -N ""

# Create the secrets in Docker Swarm
docker secret create jellyfin_rffmpeg_id_rsa ./rffmpeg_id_rsa
docker secret create jellyfin_rffmpeg_id_rsa_pub ./rffmpeg_id_rsa.pub
```

For better security, you should delete the private key file (`rffmpeg_id_rsa`) from the host system after creating the Docker secret. The key will be securely managed by Docker Swarm.

```bash
rm ./rffmpeg_id_rsa ./rffmpeg_id_rsa.pub
```

### 3. Deploy the Stack

**Note:** Before deploying, you may need to edit the `volumes` section in `docker-compose.yml` to point to your external NFS server for `media`, `jellyfin_config`, etc.

```bash
docker stack deploy -c docker-compose.yml jellyfin
```

### 6. Verify the Deployment

Check the status of your services:

```bash
docker stack services jellyfin
```

You should see all services (`jellyfin_jellyfin-server`, `jellyfin_transcode-worker`) running with `1/1` or `2/2` replicas. You can now access the Jellyfin UI at `http://<YOUR_SWARM_MANAGER_IP>:8096`.

## Scaling Workers

To add more transcoding capacity, simply scale the `transcode-worker` service:

```bash
# Scale to 5 workers
docker service scale jellyfin_transcode-worker=5
```
 
## Credits

This project builds on and uses work from the following upstream projects — thank you to the original authors:


- rffmpeg (Joshua Boniface) — rffmpeg provides the remote-ffmpeg tooling used to distribute transcoding jobs across worker nodes. See: https://github.com/joshuaboniface/rffmpeg

- docker-nfs-server / obeone — the NFS server logic and parts of the `jellyfin-server/entrypoint.sh` are adapted from the `obeone/docker-nfs-server` project (container image: `ghcr.io/obeone/nfs-server`). See: https://github.com/obeone/docker-nfs-server

- Jellyfin — the upstream open-source media server which this project integrates with and extends for distributed transcoding. See: https://github.com/jellyfin/jellyfin

- device-mapping-manager / allfro — the device mapping manager allows GPU devices to be mapped correctly within the Swarm. See: https://github.com/allfro/device-mapping-manager

The `jellyfin-server/entrypoint.sh` file includes an attribution header pointing to the NFS server project from which parts of the script were adapted. This repository is independently developed and maintained by the project owner and is not affiliated with the original authors. Please refer to the linked upstream repositories for their full documentation, source, and license terms.

## Embedded NFS (required for /transcodes and /cache) — important details

This project uses an embedded NFS server within the `jellyfin-server` container to share the `/transcodes` and `/cache` directories with the transcode workers. This is necessary because workers write temporary and final transcodes to these paths, which the Jellyfin server then serves. While your media library may reside on an external NFS server, `/transcodes` and `/cache` must be exported by the `jellyfin-server` to ensure that both the server and workers share the same writable locations for seamless media delivery.

Key implications and requirements:

- Why embedded NFS is required: the transcode workflow creates temporary files and final output on shared paths that must be writable and visible to both worker and server processes. Exporting `/transcodes` and `/cache` from the `jellyfin-server` container keeps those paths consistent and colocated with the orchestrator.
- Worker capability: mounting NFS from inside a container requires elevated privileges. The `transcode-worker` service includes `cap_add: - SYS_ADMIN` in `docker-compose.yml` so the worker can run `mount -a` successfully. If you refuse to grant SYS_ADMIN, workers will not be able to mount the server exports and the distributed transcode workflow will fail.
- Networking and reachability: workers must be able to reach the NFS server container over the Swarm overlay network. Ensure overlay networking allows RPC and NFS traffic (port 2049 and RPC/mountd/statd ports). In some environments container-to-container kernel-level NFS mounts are unreliable; see troubleshooting below.

Troubleshooting tips

- If workers fail to mount `/transcodes` or `/cache`, check worker logs for `mount` errors and confirm `cap_add: SYS_ADMIN` is present in `docker-compose.yml`.
- Verify the server built the exports by inspecting `/etc/exports` inside the `jellyfin-server` container and checking its logs for the NFS startup messages.
- From a worker container, run `mount | grep transcodes`, `df -h`, and `ping jellyfin-server` to verify mounts and name resolution.