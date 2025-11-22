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
echo "[1/8] Installing System Dependencies..."
apt-get update -qq
apt-get install -y -qq nfs-common nfs-kernel-server intel-opencl-icd clinfo binutils ocl-icd-libopencl1 wget gnupg2 ca-certificates libnuma1

# Cleanup previous runs to prevent package conflicts
rm -rf /tmp/neo_current /tmp/neo_legacy

# 2. Configure Kernel Modules
echo "[2/8] Configuring Kernel Modules..."
if ! grep -q "nfsd" /etc/modules; then echo "nfsd" >> /etc/modules; fi
if ! grep -q "nfs" /etc/modules; then echo "nfs" >> /etc/modules; fi
modprobe nfsd
modprobe nfs

# 3. Create Directories
echo "[3/8] Creating Host Directories..."
mkdir -p /transcodes /cache
chgrp users /transcodes /cache
chmod 775 /transcodes /cache

# 4. OpenCL Drivers (Current + Legacy)
echo "[4/8] Installing OpenCL Drivers (Current + Legacy)..."

# --- Start OpenCL Logic ---

# 2. Install CURRENT Drivers (Gen12+) via Apt Repository
# This ensures the correct version is installed for the running OS (Ubuntu 22.04 vs 24.04)
echo "Adding Intel Compute Runtime Apt Repository..."
mkdir -p /etc/apt/keyrings
wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | gpg --dearmor --yes -o /etc/apt/keyrings/intel-graphics.gpg
echo "deb [arch=amd64,i386 signed-by=/etc/apt/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu $(lsb_release -cs) client" | tee /etc/apt/sources.list.d/intel-gpu-$(lsb_release -cs).list

apt-get update -qq
# Install the compute runtime and level-zero
apt-get install -y -qq intel-opencl-icd intel-level-zero-gpu level-zero

# 3. Install LEGACY Drivers (Gen8-11) - Side-loaded
# Ensure clean state
rm -rf /tmp/neo_legacy
mkdir -p /tmp/neo_legacy
cd /tmp/neo_legacy

# Download
echo "Downloading Legacy Drivers..."
wget https://github.com/intel/compute-runtime/releases/download/24.35.30872.22/intel-opencl-icd-legacy1_24.35.30872.22_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/24.35.30872.22/libigdgmm12_22.5.0_amd64.deb

# Extract
echo "Extracting Legacy Drivers..."
mkdir -p extracted_icd
dpkg -x intel-opencl-icd-legacy1_24.35.30872.22_amd64.deb extracted_icd || { echo "dpkg -x failed for ICD"; exit 1; }
mkdir -p extracted_gmm
dpkg -x libigdgmm12_22.5.0_amd64.deb extracted_gmm || { echo "dpkg -x failed for GMM"; exit 1; }

# Install to /opt/intel/legacy-opencl
mkdir -p /opt/intel/legacy-opencl

# Use find to locate the files robustly, as paths may vary between package versions
# Use wildcards to catch .so, .so.1, _legacy1.so, etc.
ICD_FILE=$(find extracted_icd -name "libigdrcl*.so*" | head -n 1)
GMM_FILE=$(find extracted_gmm -name "libigdgmm*.so*" | head -n 1)

if [ -z "$ICD_FILE" ]; then
    echo "ERROR: Could not find libigdrcl*.so* in extracted legacy package."
    echo "Contents of extracted_icd:"
    find extracted_icd
    exit 1
fi

if [ -z "$GMM_FILE" ]; then
    echo "ERROR: Could not find libigdgmm*.so* in extracted legacy package."
    echo "Contents of extracted_gmm:"
    find extracted_gmm
    exit 1
fi

cp -P "$ICD_FILE" /opt/intel/legacy-opencl/libigdrcl_legacy.so
cp -P "$GMM_FILE" /opt/intel/legacy-opencl/libigdgmm.so.12

# 4. Configuration
echo "/opt/intel/legacy-opencl/libigdrcl_legacy.so" > /etc/OpenCL/vendors/intel_legacy.icd

# 6. Clean up
rm -rf /tmp/neo_current /tmp/neo_legacy
# --- End OpenCL Logic ---

echo "OpenCL Drivers Installed."

# 5. Configure Environment Variables
echo "Configuring LD_LIBRARY_PATH..."
echo 'export LD_LIBRARY_PATH="/opt/intel/legacy-opencl:$LD_LIBRARY_PATH"' > /etc/profile.d/intel-opencl.sh
chmod 644 /etc/profile.d/intel-opencl.sh

# 7. AppArmor
echo "[7/8] Configuring AppArmor..."

# Check if AppArmor needs to be disabled
APPARMOR_ACTIVE=false
if systemctl is-active --quiet apparmor; then APPARMOR_ACTIVE=true; fi
if ! grep -q "apparmor=0" /proc/cmdline; then APPARMOR_ACTIVE=true; fi

if [ "$APPARMOR_ACTIVE" = true ]; then
    echo "WARNING: AppArmor is currently enabled. It must be disabled for the NFS server to work."
    echo "This action will require a reboot."
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
                REBOOT_REQUIRED=true
            else
                echo "AppArmor already disabled in Grub config."
            fi
        fi
    else
        echo "Skipping AppArmor disable. Note: This may cause permission issues for the NFS server."
    fi
else
    echo "AppArmor is already disabled."
fi

# 8. User Groups
echo "[8/8] Configuring User Groups..."
if [ -n "$SUDO_USER" ]; then
    echo "Adding user '$SUDO_USER' to 'render' and 'video' groups..."
    usermod -aG render "$SUDO_USER" || true
    usermod -aG video "$SUDO_USER" || true
else
    echo "WARNING: Could not detect SUDO_USER. Please manually add your user to 'render' and 'video' groups."
fi

echo "=================================================================="
echo " Setup Complete!"

# Check if reboot is actually needed
if [ "$REBOOT_REQUIRED" = true ]; then
    echo " WARNING: Kernel parameters changed. A REBOOT IS REQUIRED."
elif grep -q "apparmor=0" /proc/cmdline; then
    echo " System is properly configured. No reboot required."
    if [ -n "$SUDO_USER" ]; then
        echo " NOTE: You must LOG OUT and LOG BACK IN for group changes to take effect."
        echo "       Alternatively, run: 'newgrp render' to apply immediately."
    fi
else
    echo " WARNING: AppArmor is NOT disabled in the running kernel."
    echo " Please reboot your node to apply changes."
fi
echo "=================================================================="
