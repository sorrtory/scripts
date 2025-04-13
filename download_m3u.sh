#!/bin/bash

# This script convert savefrom.net "download playlist" m3u files to mp3 format
# Actually just download by links extracted from m3u files

# Define source and destination folders
GET_FROM="./playlist"
SAVE_TO="./music"

# Create SAVE_TO folder if it doesn't exist
mkdir -p "$SAVE_TO"

# Loop through all .m3u files in GET_FROM
for m3u_path in "$GET_FROM"/*.m3u; do
    # Extract filename without path and extension
    m3u_file=$(basename "$m3u_path")         # e.g., "rock.m3u"
    playlist_name="${m3u_file%.m3u}"         # e.g., "rock"

    echo "Processing playlist: $playlist_name"

    # Read only valid URLs from .m3u (skip empty lines and comments)
    urls=$(grep -Ev '^\s*$|^#' "$m3u_path")

    if [ -z "$urls" ]; then
        echo "  No valid URLs found in $m3u_file"
        continue
    fi

    # Download using yt-dlp with the URLs piped in
    echo "$urls" | yt-dlp -x --audio-format mp3 --audio-quality 0 -a - -o "$SAVE_TO/$playlist_name"

    echo "  Done with $playlist_name"
done


