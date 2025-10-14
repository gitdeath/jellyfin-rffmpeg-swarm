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

# --- Execute Command ---
case "$COMMAND" in
    comcut)
        echo "Running comcut to physically remove commercials..." >> "$LOG_FILE"
        # Define a temporary file name for the cut version
        TEMP_FILE="${INPUT_FILE}.tmp.mkv"

        # Run comcut, creating a new temporary output file and specifying the ini path
        /usr/local/bin/comcut --comskip-ini="$COMSKIP_INI" "$INPUT_FILE" "$TEMP_FILE" >> "$LOG_FILE" 2>&1
        EXIT_CODE=$?

        # If comcut succeeded and created a valid output file, replace the original
        if [ $EXIT_CODE -eq 0 ] && [ -s "$TEMP_FILE" ]; then
            echo "Comcut successful. Replacing original file." >> "$LOG_FILE"
            mv -f "$TEMP_FILE" "$INPUT_FILE"
        else
            echo "ERROR: comcut failed or created an empty file. Original file is unchanged." >> "$LOG_FILE"
            rm -f "$TEMP_FILE" # Clean up failed temp file
            # Ensure we report the failure
            [ $EXIT_CODE -eq 0 ] && EXIT_CODE=1
        fi
        ;;

    comchap)
        echo "Running full comchap process (detect and add chapters)..." >> "$LOG_FILE"
        # Run comchap and explicitly specify the ini path
        /usr/local/bin/comchap --comskip-ini="$COMSKIP_INI" "$INPUT_FILE" >> "$LOG_FILE" 2>&1
        EXIT_CODE=$?
        ;;

    *)
        echo "WARNING: Invalid command '$COMMAND'. Defaulting to full comchap process." >> "$LOG_FILE"
        # Run comchap and explicitly specify the ini path
        /usr/local/bin/comchap --comskip-ini="$COMSKIP_INI" "$INPUT_FILE" >> "$LOG_FILE" 2>&1
        EXIT_CODE=$?
        ;;
esac

# Check the exit code of the executed command to determine success or failure
if [ $EXIT_CODE -eq 0 ]; then
    echo "Processing completed successfully." >> "$LOG_FILE"
else
    echo "ERROR: Command '$COMMAND' failed. Check log for details." >> "$LOG_FILE"
fi

exit 0