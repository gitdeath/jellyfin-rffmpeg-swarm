# Manual Node Setup Guide

This document details the manual steps required to configure a node for the Jellyfin Swarm. These steps are performed automatically by the `setup-node.sh` script, but you can follow them here if you prefer manual configuration or need to troubleshoot.

**Perform these steps on ALL nodes in your Swarm cluster.**

## 1. Install System Dependencies
Install the necessary packages for NFS client/server functionality and Intel hardware acceleration.

```bash
sudo apt update
sudo apt install -y nfs-common nfs-kernel-server intel-opencl-icd clinfo binutils ocl-icd-libopencl1 wget gnupg2 ca-certificates libnuma1
```

## 2. Configure Kernel Modules
Ensure the required NFS modules are loaded on boot.

```bash
sudo sh -c "echo 'nfsd' >> /etc/modules"
sudo sh -c "echo 'nfs' >> /etc/modules"
sudo modprobe nfsd nfs
```

## 3. Create Host Directories
Create the directories on the host that the `jellyfin-server` container will use for its internal NFS exports.

```bash
sudo mkdir -p /transcodes /cache
sudo chgrp users /transcodes /cache
sudo chmod 775 /transcodes /cache
```

## 4. OpenCL Support (Current & Legacy)
This project supports both **Current (Gen12+)** and **Legacy (Gen8-11)** Intel GPUs simultaneously via a side-by-side driver installation.

### Step 4.1: Install Current Drivers (Gen12+)
Download and install the latest Intel Compute Runtime packages.

```bash
mkdir -p /tmp/neo_current && cd /tmp/neo_current

wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.22.2/intel-igc-core-2_2.22.2+20121_amd64.deb
wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.22.2/intel-igc-opencl-2_2.22.2+20121_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/intel-ocloc_25.44.36015.5-0_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/intel-opencl-icd_25.44.36015.5-0_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/libigdgmm12_22.8.2_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/libze-intel-gpu1_25.44.36015.5-0_amd64.deb

sudo dpkg -i *.deb || sudo apt-get install -f -y
cd / && rm -rf /tmp/neo_current
```

### Step 4.2: Install Legacy Drivers (Gen8-11)
Download and extract the legacy drivers to a separate location (`/opt/intel/legacy-opencl`) to avoid conflicts.

```bash
mkdir -p /tmp/neo_legacy && cd /tmp/neo_legacy

# Download
wget https://github.com/intel/compute-runtime/releases/download/24.35.30872.22/intel-opencl-icd-legacy1_24.35.30872.22_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/24.35.30872.22/libigdgmm12_22.5.0_amd64.deb

# Extract
mkdir -p extracted_icd
dpkg -x intel-opencl-icd-legacy1_24.35.30872.22_amd64.deb extracted_icd
mkdir -p extracted_gmm
dpkg -x libigdgmm12_22.5.0_amd64.deb extracted_gmm

# Install to /opt/intel/legacy-opencl
sudo mkdir -p /opt/intel/legacy-opencl

# Use find to locate the files robustly
ICD_FILE=$(find extracted_icd -name "libigdrcl*.so*" | head -n 1)
GMM_FILE=$(find extracted_gmm -name "libigdgmm*.so*" | head -n 1)

sudo cp "$ICD_FILE" /opt/intel/legacy-opencl/libigdrcl_legacy.so
sudo cp "$GMM_FILE" /opt/intel/legacy-opencl/libigdgmm.so.12

# Clean up
cd / && rm -rf /tmp/neo_legacy
```

### Step 4.3: Configure OpenCL Loader
Register the legacy driver with the system's OpenCL loader.

```bash
sudo sh -c 'echo "/opt/intel/legacy-opencl/libigdrcl_legacy.so" > /etc/OpenCL/vendors/intel_legacy.icd'
```

### Step 4.4: Configure Environment Variables
Create a profile script to ensure the legacy driver is found by applications on the host.

```bash
sudo sh -c 'echo "export LD_LIBRARY_PATH=/opt/intel/legacy-opencl:\$LD_LIBRARY_PATH" > /etc/profile.d/intel-opencl.sh'
```

## 5. Disable AppArmor (Critical)
AppArmor's security policies prevent the `jellyfin-server` container from acquiring the permissions needed to run its own NFS server. It must be disabled on the host.

```bash
sudo systemctl stop apparmor && sudo systemctl disable apparmor
sudo apt purge -y apparmor
# This command adds 'apparmor=0' to the kernel boot parameters
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 apparmor=0"/' /etc/default/grub
sudo update-grub
```

**A reboot is required** for this change to take effect.
