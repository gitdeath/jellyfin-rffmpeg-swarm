#!/bin/bash
set -e

# 1. Install Dependencies
apt-get update
apt-get install -y wget clinfo binutils ocl-icd-libopencl1

# 2. Install CURRENT Drivers (Gen12+)
mkdir -p /tmp/neo_current
cd /tmp/neo_current

wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.22.2/intel-igc-core-2_2.22.2+20121_amd64.deb
wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.22.2/intel-igc-opencl-2_2.22.2+20121_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/intel-ocloc_25.44.36015.5-0_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/intel-opencl-icd_25.44.36015.5-0_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/libigdgmm12_22.8.2_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/25.44.36015.5/libze-intel-gpu1_25.44.36015.5-0_amd64.deb

dpkg -i *.deb || apt-get install -f -y

# 3. Install LEGACY Drivers (Gen8-11) - Side-loaded
mkdir -p /tmp/neo_legacy
cd /tmp/neo_legacy

# Download
wget https://github.com/intel/compute-runtime/releases/download/24.35.30872.22/intel-opencl-icd_24.35.30872.22-0_amd64.deb
wget https://github.com/intel/compute-runtime/releases/download/24.35.30872.22/libigdgmm12_22.5.2_amd64.deb

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

echo "Installation Complete."
echo "IMPORTANT: You must export LD_LIBRARY_PATH=/opt/intel/legacy-opencl:\$LD_LIBRARY_PATH for the legacy driver to work."
