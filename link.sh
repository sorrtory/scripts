#!/usr/bin/bash

# This script helps to create symlinks for programs and configs
# It must be run from <configs> folder (i.e. ./link.sh) because it uses pwd

if [ "$0" != "./link.sh" ]; then
    echo "Creating symlinks requires running from the same folder"
    exit 1
fi

# Create .config directory if not exists
if [ ! -d "$HOME/.config" ]; then
    echo "Creating .config directory"
    mkdir -p "$HOME/.config"
fi

# Function to check for existing config for a given program path
check_existing_config() {
    local prog_path="$1"
    echo "Check $prog_path" 

    if [ "$SKIP_ALL" = "1" ]; then
        if [[ -L "$prog_path" || -e "$prog_path" ]]; then
            echo "Skipping $prog_path (auto-skip enabled)"
            return 1
        fi
    fi

    while [[ -L "$prog_path" || -e "$prog_path" ]]; do
        echo "$prog_path config already exists"
        read -p "Config exists. [s]kip / [r]eplace / [b]ackup and replace (default: b)? " choice
        case "$choice" in
            s|S)
                echo "Skipping $prog_path"
                return 1
                ;;
            r|R)
                echo "Replacing $prog_path"
                rm -rf "${prog_path:?}"
                ;;
            b|B|"")
                echo "Backing up $prog_path to $prog_path.bak"
                mv "$prog_path" "${prog_path}.bak"
                ;;
            *)
                echo "Invalid choice. Please enter s, r, or b."
                continue
                ;;
        esac
        break
    done
}

# Main function to link configs from source to destination
link_config() {
    local from="$1"
    local to="$2"

    # Check FROM doesn't exist
    if [ ! -e "$from" ]; then
        echo "Source config $from does not exist"
        return 1
    fi

    # Ensure parent directory for TO exists
    local to_dir
    to_dir="$(dirname "$to")"
    if [ ! -d "$to_dir" ]; then
        echo "Creating parent directory $to_dir"
        mkdir -p "$to_dir"
    fi

    # Check TO already exists, prompt for back up
    check_existing_config "$to" || return 0

    echo -n "Linking: $from to $to "
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY RUN] ln -s $from $to"
    else
        if [ "$SUDO" -eq 1 ]; then
            sudo ln -s "$from" "$to"
        else
            ln -s "$from" "$to"
        fi
        if [ "$?" -eq 0 ]; then
            echo "[OK]"
        else
            echo "[ERROR]"
        fi
    fi
}

# Parse script arguments and call appropriate function
SKIP_ALL=0
DRY_RUN=0
SUDO=0
MODE="default"

# Parse options first
for arg in "$@"; do
    case $arg in
        --skip)
            SKIP_ALL=1
            shift
        ;;
        -b|--bin)
            MODE="bin"
            shift
        ;;
        --home)
            MODE="home"
            shift
        ;;
        --dry)
            DRY_RUN=1
            shift
        ;;
        --sudo)
            SUDO=1
            shift
        ;;
        -h|--help)
            echo "Usage: ./link.sh [--skip] [--help] [-b|--bin] <from> [<to>]"
            echo "This program safely links <from> to <to> (defaults to ~/.config)"
            echo "Remember that creating symlinks is more reliable when running from the same folder"
            echo "Because pwd is used to determine the source path"
            echo ""
            echo "Options:"
            echo "  --dry    Do not create symlink, only print commands"
            echo "  --sudo   Create symlink with sudo"
            echo "  --bin    Link <from> to /usr/local/bin/ and cut the extension. Ignored if <to> is passed"
            echo "  --home   Link <from> to $HOME directly (not in .config). Ignored if <to> is passed"
            echo "  --skip   Skip existing <to> without prompt"
            echo "  --help   Show this help message"
            exit 0
        ;;
    esac
done

if [ -z "$1" ]; then
    echo "Error: Missing <from>"
    echo "Usage: ./link.sh [--skip] [--help] [-b|--bin] <from> [<to>]"
    echo "See: ./link.sh --help"
    exit 1
fi

# Determine the absolute path for FROM
if [[ "$1" == /* ]]; then
    FROM="$1"
else
    if [ -e "$1" ]; then
        FROM=$(realpath "$1")
    else
        if [ -e "$HOME/$1" ]; then
            FROM=$(realpath "$HOME/$1")
        fi
        # If still not found, give up, it will be handled in link_config
    fi
fi


# If <to> is not specified, default to ~/.config/<from>
if [ -n "$2" ]; then
    TO="$2"
    # Append $HOME if needed
    if [[ "$TO" != /* ]]; then
        TO="$HOME/$TO"
    fi
else
    TO="$HOME/.config/$(basename "$1")"
    if [ "$MODE" = "bin" ]; then
        TO="/usr/local/bin/$(basename "$1" | sed 's/\.[^.]*$//')"
    elif [ "$MODE" = "home" ]; then
        TO="$HOME/$(basename "$1")"
    fi
fi

link_config "$FROM" "$TO"