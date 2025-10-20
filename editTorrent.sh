#!/bin/bash

# Script to change the passkey for a user on torrent file

USAGE=$(cat <<EOF
Usage: $0 <filename> [-o <old_tracker_url>] [-n <new_tracker_url>] | [-f <url_file>]
Replace string <old_tracker_url> with <new_tracker_url> in the torrent file <filename>.
Example: 
$0 myfile.torrent -o http://oldtracker.com/announce -n http://newtracker.com/announce2
$0 myfile.torrent -f ~/Documents/secrets/my_tracker_racker.conf
EOF
)

# Check for transmission-edit command
if ! command -v transmission-edit &> /dev/null; then
    echo "Error: transmission-edit not found."
    echo "Please install transmission-cli (e.g., sudo apt install transmission-cli)."
    exit 1
fi

# Torrent filename is the first non-option argument
FILENAME="$1"

if [ "$#" -lt 1 ]; then
    echo "Cannot parse arguments!"
    echo "$USAGE"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "File [$1] not found!"
    echo "$USAGE"
    exit 1
fi

# Remove the first argument (filename) so getopts can parse the rest
shift 

# Parse arguments
while getopts ":f:o:n:" opt; do
    case $opt in
        f)
            URL_FILENAME="$OPTARG"
            if [ -f "$URL_FILENAME" ]; then
                # Source the file in a subshell and capture the variables into FILE_... so we don't clobber
                # any values already set by -o/-n. Using %q to safely quote values.
                # shellcheck disable=SC1090
                eval "$(
                    ( . "$URL_FILENAME"
                    printf 'FILE_TRACKER_URL_FROM=%q\nFILE_TRACKER_URL_TO=%q\n' "$TRACKER_URL_FROM" "$TRACKER_URL_TO"
                    )
                )"
                # source "$URL_FILENAME"
                
                # Only set TRACKER_URL_* from the file if they are not already set so -o/-n can overwrite
                TRACKER_URL_FROM="${TRACKER_URL_FROM:-$FILE_TRACKER_URL_FROM}"
                TRACKER_URL_TO="${TRACKER_URL_TO:-$FILE_TRACKER_URL_TO}"
            else
                echo "Error: URL file '$URL_FILENAME' not found."
                exit 1
            fi
            ;;
        o) TRACKER_URL_FROM="$OPTARG" ;;
        n) TRACKER_URL_TO="$OPTARG" ;;
        *) echo "$USAGE"; exit 1 ;;
    esac
done



if [ -z "$FILENAME" ] || [ -z "$TRACKER_URL_FROM" ] || [ -z "$TRACKER_URL_TO" ]; then
    echo "Missing required arguments!"
    echo "Filename: [$FILENAME], Tracker URL From: [$TRACKER_URL_FROM], Tracker URL To: [$TRACKER_URL_TO]"

    echo "$USAGE"
    exit 1
fi


# NEW_FILE="${FILENAME%.torrent}_updated.torrent"
NEW_FILE="replaced_$FILENAME"
cp "$FILENAME" "$NEW_FILE"


transmission-edit -r "$TRACKER_URL_FROM" "$TRACKER_URL_TO" "$NEW_FILE"

echo "Updated torrent file: $FILENAME --> $NEW_FILE"