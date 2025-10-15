#!/bin/bash

# Set a umask to ensure all files created by this script and its children are group-writable.
umask 002

# Generate a date stamp for the log file name, e.g., "2025-10-13"
DATESTAMP=$(date +'%Y-%m-%d')

# Create a log file for the current date. All logs from the same day will be appended.
LOG_FILE="/config/log/post-processing_${DATESTAMP}.log"
INPUT_FILE="$1"
COMMAND="$2" # The second argument from Jellyfin, e.g., "comcut" or "comchap"
COMSKIP_INI="/etc/comskip.ini" # Define the path to your system ini file

# --- Locking Mechanism ---
# Create a unique lock file path based on the input file to prevent concurrent runs.
LOCK_FILE="/cache/temp/$(basename "$INPUT_FILE").lock"

if [ -f "$LOCK_FILE" ]; then
    echo "Lock file exists for $INPUT_FILE. Another process is running. Exiting." >> "$LOG_FILE"
    exit 1
fi

# Create the lock file and set a trap to ensure it's removed on exit.
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# --- Start of Logging ---
echo "----------------------------------------------------" >> "$LOG_FILE"
echo "Processing request for: $INPUT_FILE" >> "$LOG_FILE"
date >> "$LOG_FILE"

# Set the default command to 'comchap' if the second argument is empty
if [ -z "$COMMAND" ]; then
    COMMAND="comchap"
fi

echo "Action: $COMMAND" >> "$LOG_FILE"
echo "Using INI file: $COMSKIP_INI" >> "$LOG_FILE"

# Define the final output file path. We always remux to MKV to support chapters.
# This is defined once here to avoid redundancy within the case statement.
OUTPUT_FILE="${INPUT_FILE%.*}.mkv"

# To work around bugs in comchap/comcut with spaces in filenames, we create a temporary,
# space-free path in a known-good directory (/livetv).
# We use a combination of nanoseconds from 'date' and the script's process ID '$$' to create a unique name.
TEMP_BASENAME="post-processing-$(date +%s%N)-$$"
TEMP_INPUT_FILE="/livetv/${TEMP_BASENAME}.ts"
TEMP_OUTPUT_FILE="/livetv/${TEMP_BASENAME}.mkv"

# Move the original file to the temporary path.
mv "$INPUT_FILE" "$TEMP_INPUT_FILE"

# --- NFS Workaround ---
# After moving the file, we need to wait for it to become visible on the filesystem.
# This is a workaround for potential NFS attribute caching delays where a file appears
# to not exist for a few moments after being moved.
i=0
while [ ! -f "$TEMP_INPUT_FILE" ] && [ $i -lt 10 ]; do
  sleep 1
  ((i++))
done

if [ ! -f "$TEMP_INPUT_FILE" ]; then
    echo "ERROR: Moved temporary file is not visible after 10 seconds. Aborting." >> "$LOG_FILE"
    mv "$TEMP_INPUT_FILE" "$INPUT_FILE" 2>/dev/null # Attempt to restore original file
    exit 1
fi

# --- Execute Command ---
case "$COMMAND" in
    comcut)
        echo "Running comcut to physically remove commercials..." >> "$LOG_FILE"

        su transcodessh -c "/usr/local/bin/comcut --comskip-ini='${COMSKIP_INI}' '${TEMP_INPUT_FILE}' '${TEMP_OUTPUT_FILE}'" >> "$LOG_FILE" 2>&1
        EXIT_CODE=$?

        # If comcut succeeded, move the processed file back to the original location with the correct name.
        if [ $EXIT_CODE -eq 0 ] && [ -s "$TEMP_OUTPUT_FILE" ]; then
            echo "Comcut successful. Moving processed file to final destination." >> "$LOG_FILE"
            mv "$TEMP_OUTPUT_FILE" "$OUTPUT_FILE"
            # On success, we can safely remove the temporary input file.
            rm -f "$TEMP_INPUT_FILE"
        else
            echo "ERROR: comcut failed or created an empty file. Original file is unchanged." >> "$LOG_FILE"
            # CRITICAL: Move the temporary file back to restore the original recording.
            mv "$TEMP_INPUT_FILE" "$INPUT_FILE"
        fi
        ;;

    comchap)
        echo "Running full comchap process (detect and add chapters)..." >> "$LOG_FILE"

        su transcodessh -c "/usr/local/bin/comchap --comskip-ini='${COMSKIP_INI}' '${TEMP_INPUT_FILE}' '${TEMP_OUTPUT_FILE}'" >> "$LOG_FILE" 2>&1
        EXIT_CODE=$?

        # If comchap succeeded, move the processed file back to the original location with the correct name.
        if [ $EXIT_CODE -eq 0 ] && [ -s "$TEMP_OUTPUT_FILE" ]; then
            echo "Comchap successful. Moving processed file to final destination." >> "$LOG_FILE"
            mv "$TEMP_OUTPUT_FILE" "$OUTPUT_FILE"
            # On success, we can safely remove the temporary input file.
            rm -f "$TEMP_INPUT_FILE"
        else
            echo "ERROR: comchap failed or created an empty file. Original file is unchanged." >> "$LOG_FILE"
            # CRITICAL: Move the temporary file back to restore the original recording.
            mv "$TEMP_INPUT_FILE" "$INPUT_FILE"
        fi
        ;;

    *)
        echo "WARNING: Invalid command '$COMMAND'. No action taken." >> "$LOG_FILE"
        EXIT_CODE=1
        # CRITICAL: Restore the original file since no action was taken.
        mv "$TEMP_INPUT_FILE" "$INPUT_FILE"
        ;;
esac

# Check the exit code of the executed command to determine success or failure
if [ $EXIT_CODE -eq 0 ]; then
    echo "Processing completed successfully." >> "$LOG_FILE"
else
    echo "ERROR: Command '$COMMAND' failed. Check log for details." >> "$LOG_FILE"
fi

exit 0