#!/bin/bash

# Function to check if a host is online
is_host_online() {
    ping -c 1 "$1" > /dev/null 2>&1
    return $?
}

# Function to check if a hostname is present in the output of 'rffmpeg status'
is_hostname_present() {
    local hostname="$1"
    /usr/local/bin/rffmpeg status | grep -wq "$hostname"
    return $?
}

# Function to add a hostname using 'rffmpeg add'
add_hostname() {
    /usr/local/bin/rffmpeg add "$1"
}

# Function to remove a hostname using 'rffmpeg remove'
remove_hostname() {
    /usr/local/bin/rffmpeg remove "$1"
}

# Maximum number of consecutive unresponsive hosts allowed
max_consecutive_failures=2
consecutive_failures=0

# Start loop without setting a maximum value
i=1
while true; do
    hostname="jellyfin-transcode-$i"

    # Check if host is online
    if is_host_online "$hostname"; then
        # Check if hostname is not in the output of 'rffmpeg status'
        if ! is_hostname_present "$hostname"; then
            add_hostname "$hostname"
            echo "Added $hostname"
        else
            echo "$hostname already present, skipping..."
        fi

        # Reset consecutive failures counter
        consecutive_failures=0
    else
        # Notify when a host is not online
        echo "$hostname is not online."

        # Check if hostname is in the output of 'rffmpeg status'
        if is_hostname_present "$hostname"; then
            remove_hostname "$hostname"
            echo "Removed $hostname"
            # Reset consecutive failures counter
            consecutive_failures=0
        else
            # Increment consecutive failures counter
            ((consecutive_failures++))
        fi

        # Break the loop if the consecutive failures threshold is reached
        if [ "$consecutive_failures" -ge "$max_consecutive_failures" ]; then
            echo "Reached $max_consecutive_failures consecutive failures. Stopping..."
            break
        fi
    fi

    # Increment counter for the next hostname
    ((i++))
done
