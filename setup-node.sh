#!/bin/bash
set -e

# Check for root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "=================================================================="
echo " Jellyfin Swarm Node Setup"
echo "=================================================================="

# 1. Install Dependencies
echo "[1/6] Installing System Dependencies..."
apt-get update -qq
apt-get install -y -qq nfs-common nfs-kernel-server intel-opencl-icd clinfo binutils ocl-icd-libopencl1 wget gnupg2 ca-certificates libnuma1

# 2. Configure Kernel Modules
echo "[2/6] Configuring Kernel Modules..."
if ! grep -q "nfsd" /etc/modules; then echo "nfsd" >> /etc/modules; fi
if ! grep -q "nfs" /etc/modules; then echo "nfs" >> /etc/modules; fi
modprobe nfsd
modprobe nfs

# 3. Create Directories
echo "[3/6] Creating Host Directories..."
mkdir -p /transcodes /cache
chgrp users /transcodes /cache
chmod 775 /transcodes /cache

# 4. OpenCL Drivers (Current + Legacy)
echo "[4/6] Installing OpenCL Drivers (Current + Legacy)..."

# --- Start OpenCL Logic ---
# 2. Install CURRENT Drivers (Gen12+)
mkdir -p /tmp/neo_current
cd /tmp/neo_current

wget -q https://github.com/intel/intel-graphics-compiler/releases/download/v2.22.2/intel-igc-core-2_2.22.2+20121_amd64.deb
wget -q https://github.com/intel/intel-graphics-compiler/releases/download/v2.22.2/intel-igc-opencl-2_2.22.2+20121_amd64.deb
wget -q https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/intel-ocloc_25.44.36015.5-0_amd64.deb
wget -q https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/intel-opencl-icd_25.44.36015.5-0_amd64.deb
wget -q https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/libigdgmm12_22.8.2_amd64.deb
wget -q https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/libze-intel-gpu1_25.44.36015.5-0_amd64.deb

dpkg -i *.deb || apt-get install -f -y

# 3. Install LEGACY Drivers (Gen8-11) - Side-loaded
mkdir -p /tmp/neo_legacy
cd /tmp/neo_legacy

# Download
wget -q https://github.com/intel/compute-runtime/releases/download/24.35.30872.22/intel-opencl-icd_24.35.30872.22-0_amd64.deb
wget -q https://github.com/intel/compute-runtime/releases/download/24.35.30872.22/libigdgmm12_22.5.2_amd64.deb

# Extract
mkdir -p extracted_icd
dpkg -x intel-opencl-icd_24.35.30872.22-0_amd64.deb extracted_icd
mkdir -p extracted_gmm
dpkg -x libigdgmm12_22.5.2_amd64.deb extracted_gmm

# Install to /opt/intel/legacy-opencl
mkdir -p /opt/intel/legacy-opencl
cp extracted_icd/usr/lib/x86_64-linux-gnu/intel-opencl/libigdrcl.so /opt/intel/legacy-opencl/libigdrcl_legacy.so
cp extracted_gmm/usr/lib/x86_64-linux-gnu/libigdgmm.so.12 /opt/intel/legacy-opencl/

# 4. Configuration
echo "/opt/intel/legacy-opencl/libigdrcl_legacy.so" > /etc/OpenCL/vendors/intel_legacy.icd

# 5. Clean up
rm -rf /tmp/neo_current /tmp/neo_legacy
# --- End OpenCL Logic ---

echo "OpenCL Drivers Installed."
echo "IMPORTANT: You must export LD_LIBRARY_PATH=/opt/intel/legacy-opencl:\$LD_LIBRARY_PATH for the legacy driver to work."

# 5. AppArmor
echo "[5/6] Disabling AppArmor..."
echo "WARNING: This will disable AppArmor and require a reboot."
read -p "Do you want to proceed with disabling AppArmor? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl stop apparmor 2>/dev/null || true
    systemctl disable apparmor 2>/dev/null || true
    apt-get purge -y -qq apparmor
    
    # Update Grub
    if [ -f /etc/default/grub ]; then
        # Check if apparmor=0 is already present to avoid duplication
        if ! grep -q "apparmor=0" /etc/default/grub; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 apparmor=0"/' /etc/default/grub
            update-grub
        else
            echo "AppArmor already disabled in Grub."
        fi
    fi
else
    echo "Skipping AppArmor disable. Note: This may cause permission issues for the NFS server."
fi

echo "=================================================================="
echo " Setup Complete!"
echo " Please reboot your node to finalize changes."
echo "=================================================================="
