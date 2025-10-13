#!/bin/bash
set -e

# Prevent files/subdirectories from being created that are unreachable by remote rffmpeg workers
umask 002

# Function to print messages with timestamps
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}
log "Starting rffmpeg-worker container..."

# Set up SSH authorized_keys from Docker secret
if [ -f /run/secrets/rffmpeg_id_rsa_pub ]; then
    log "INFO: Configuring authorized_keys for transcodessh user."
    mkdir -p /home/transcodessh/.ssh
    cp /run/secrets/rffmpeg_id_rsa_pub /home/transcodessh/.ssh/authorized_keys
    chown -R transcodessh:users /home/transcodessh/.ssh
    chmod 700 /home/transcodessh/.ssh
    chmod 600 /home/transcodessh/.ssh/authorized_keys
fi

# Add transcodessh user to the group that owns renderD128
if [ -e /dev/dri/renderD128 ]; then
    renderD128_gid=$(stat -c "%g" /dev/dri/renderD128)
    # Check if a group with this GID already exists. If not, create it.
    if ! getent group "$renderD128_gid" >/dev/null; then
        groupadd --gid "$renderD128_gid" render
    fi
    usermod -aG "$renderD128_gid" transcodessh
    log "transcodessh user was added to render group ($renderD128_gid)"
else
    log "Warning: /dev/dri/renderD128 not found. Skipping GPU group setup."
fi

# Determine the NFS server hostname based on the worker's own hostname.
# If the worker's hostname contains "-dev", it will connect to the dev server.
if [[ "$(hostname)" == *"-dev"* ]]; then
    NFS_SERVER_HOSTNAME="jellyfin-server-dev"
    log "INFO: Worker hostname indicates DEV mode. Using NFS server: $NFS_SERVER_HOSTNAME"
else
    NFS_SERVER_HOSTNAME="jellyfin-server"
fi

# Create /etc/fstab dynamically to point to the correct NFS server.
log "INFO: Creating /etc/fstab to mount from $NFS_SERVER_HOSTNAME"
echo "$NFS_SERVER_HOSTNAME:/transcodes /transcodes nfs rw,nolock,actimeo=1 0 0" > /etc/fstab
echo "$NFS_SERVER_HOSTNAME:/cache /cache nfs rw,nolock,actimeo=1 0 0" >> /etc/fstab

# Attempt to mount file systems from /etc/fstab
mount -a
log "Success: File systems mounted successfully."

# Background process: Attempt to update jellyfin-ffmpeg7 every 25 hours
(
  set -e
  while true; do
    sleep 90000 # Sleep for 25 hours (25 * 3600 seconds)
    if ! pgrep -x "ffmpeg" >/dev/null; then
      log "Checking for jellyfin-ffmpeg7 updates..."
      if apt-get update >/dev/null 2>&1 && apt list --upgradable 2>/dev/null | grep -q "^jellyfin-ffmpeg7/"; then
        log "New version of jellyfin-ffmpeg7 found. Updating..."
        apt-get install --only-upgrade -y jellyfin-ffmpeg7 >/dev/null 2>&1
        log "jellyfin-ffmpeg7 update completed."
      fi
    else
      log "ffmpeg process is running. Skipping update check."
    fi
  done
) &

# Background process: Monitor NFS connection and shut down if it becomes unresponsive.
(
  FAIL_COUNT=0
  MAX_FAILS=3
  SLEEP_INTERVAL=3
  while true; do
    sleep $SLEEP_INTERVAL
    if timeout 2 df -h >/dev/null 2>&1; then
      if [ $FAIL_COUNT -gt 0 ]; then
        log "INFO: NFS connection recovered after $FAIL_COUNT failed attempts."
      fi
      FAIL_COUNT=0
    else
      ((FAIL_COUNT++))
      log "WARNING: 'df -h' timed out. Consecutive failures: $FAIL_COUNT/$MAX_FAILS"
      if [ $FAIL_COUNT -ge $MAX_FAILS ]; then
        log "CRITICAL: NFS is unresponsive. Shutting down to prevent new jobs."
        # Kill the main sshd process to trigger a container exit.
        pkill -f /usr/sbin/sshd
        break
      fi
    fi
  done
) &

# Trap SIGTERM and SIGINT signals to allow for graceful shutdown
trap "log 'Received shutdown signal, stopping sshd...'; pkill -f /usr/sbin/sshd; wait; exit 0" SIGTERM SIGINT

log "Starting SSHD..."
# Create the directory for sshd privilege separation
mkdir -p /run/sshd
chmod 700 /run/sshd
# Start the sshd service as the main container process.
# The -e flag sends logs to stderr, which is useful for container logging.
/usr/sbin/sshd -D -e &

# Wait for the sshd process to exit. This script will terminate when sshd does.
wait $!
log "SSHD has stopped. Exiting container."
