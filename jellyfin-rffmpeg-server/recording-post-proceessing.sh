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
        else
            echo "ERROR: comchap failed or created an empty file. Original file is unchanged." >> "$LOG_FILE"
            # CRITICAL: Move the temporary file back to restore the original recording.
            mv "$TEMP_INPUT_FILE" "$INPUT_FILE"
        fi
        ;;

    *)
        echo "WARNING: Invalid command '$COMMAND'. No action taken." >> "$LOG_FILE"
        EXIT_CODE=1
        ;;
esac

# Clean up any remaining temporary files.
# The input file should have been moved back or replaced, so it's safe to remove any lingering temp file.
rm -f "$TEMP_INPUT_FILE" >/dev/null 2>&1

# Check the exit code of the executed command to determine success or failure
if [ $EXIT_CODE -eq 0 ]; then
    echo "Processing completed successfully." >> "$LOG_FILE"
else
    echo "ERROR: Command '$COMMAND' failed. Check log for details." >> "$LOG_FILE"
fi

exit 0