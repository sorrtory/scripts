#!/bin/bash

# This script cuts a specified string from the end of filenames in a directory.
# Be careful with naming and EXTENSIONS (only the last one is true one)


# Parse command line arguments using a case statement
case "$#" in
    1)
        remove_str="$1"
        dir="."
        ;;
    2)
        remove_str="$1"
        dir="$2"
        ;;
    *)
        echo "Usage: $0 <string_to_remove_from_end_of_filename> [directory]"
        exit 1
        ;;
esac

# Change to target directory if specified
cd "$dir" || { echo "Directory not found: $dir"; exit 1; }

echo "Cutting \"$remove_str\" from filenames in $(pwd)"

# Loop over all files in the current directory
for file in *; do
    if [ "$file" = "$(basename "$0")" ]; then
        continue
    fi

    echo "> Renaming $file"
    # Skip directories
    [ -f "$file" ] || continue

    # Separate base name and extension
    base="${file%.*}"   # everything except last dot + extension
    ext="${file##*.}"   # extension only

    base="${base%"$remove_str"}"

    # Reassemble filename
    newname="${base}.${ext}"

    # Rename only if different
    if [ "$file" != "$newname" ]; then
        mv -v -- "$file" "$newname"
        echo "< Renamed $file"
    else
        echo "< No change $file"
    fi

    echo ""

done
