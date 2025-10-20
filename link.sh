#!/usr/bin/bash

# This script helps to create symlinks for programs and configs

# Create .config directory if not exists
if [ ! -d "$HOME/.config" ]; then
    echo "Creating .config directory"
    mkdir -p "$HOME/.config"
fi

# Function to check for existing config for a given program path
check_existing_config() {
    local prog_path="$1"
    echo "Check $prog_path for existance"

    if [[ -L "$prog_path" || -e "$prog_path" ]]; then
        echo "$prog_path config already exists"
    fi

    function skip(){
        echo "Skipping $prog_path $1"
    }

    function backup(){
        local backup_path="${prog_path}.bak"
        local i=1
        # Find a unique backup name if .bak exists
        while [ -e "$backup_path" ]; do
            backup_path="${prog_path}.bak$i"
            i=$((i+1))
        done
        echo "Backing up $prog_path to $backup_path $1"
        mv "$prog_path" "$backup_path"
    }

    function replace(){
        echo "Replacing $prog_path"
        rm -rf "${prog_path:?}"
    }

    case "$ON_EXIST" in
        1)
            skip "(--skip enabled)"
            return 1
            ;;
        2)
            backup "(--backup enabled)"
            return 1
            ;;
    esac

    # Prompt for the action with existing <to> file
    while [[ -L "$prog_path" || -e "$prog_path" ]]; do
        read -p "Config exists. [s]kip / [r]eplace / [b]ackup and replace (default: b)? " choice
        case "$choice" in
            s|S)
                skip
                return 1
                ;;
            r|R)
                replace
                return 0
                ;;
            b|B|"")
                backup
                return 0
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

    echo "Linking: $from to $to"
    LN_CMD="ln -s \"$from\" \"$to\""
    if [ "$SUDO" -eq 1 ]; then
        LN_CMD="sudo $LN_CMD"
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY RUN] $LN_CMD"
    else
        # Eval is safe here, because we check $from and $to to be paths
        if eval $LN_CMD; then
            echo "Linking: [OK]"
        else
            echo "Linking: [ERROR]"
        fi
    fi
}

# Parse script arguments and call appropriate function
ON_EXIST=0
DRY_RUN=0
SUDO=0
MODE="default"
USAGE="Usage: ./link.sh [--skip] [--backup] [--help] [--bin] [--home] [--dry] [--sudo] <from> [<to>]
  <from>  Source file or directory to link from
  <to>    Destination file or directory to link to (default: ~/.config/<from>)"

# Parse options first
for arg in "$@"; do
    case $arg in
        --skip)
            ON_EXIST=1
            shift
        ;;
        --backup)
            ON_EXIST=2
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
            echo "$USAGE"
            echo "This program safely links <from> to <to> (defaults to ~/.config)"
            echo "It uses realpath to resolve paths"
            echo ""
            echo "ln options:"
            echo "  --sudo   Create symlink with sudo"
            echo "  --bin    Link <from> to /usr/local/bin/ and cut the extension. Ignored if <to> is passed"
            echo "  --home   Link <from> to $HOME directly (not in .config). Ignored if <to> is passed"
            echo "  --dry    Do not create symlink, only print commands"
            echo "Other options:"
            echo "  --backup Backup existing <to> before linking without prompt"
            echo "  --skip   Skip existing <to> without prompt"
            echo "  --help   Show this help message"
            exit 0
        ;;
    esac
done

if [ -z "$1" ]; then
    echo "Error: Missing <from>"
    echo "$USAGE"
    echo "See: ./link.sh --help"
    exit 1
fi

# Determine the absolute path for FROM
FROM=$(realpath "$1")
# If path is not found, it will be handled in link_config

# If <to> is not specified, default to ~/.config/<from>
if [ -n "$2" ]; then
    TO=$(realpath "$2")
else
    TO="$HOME/.config/$(basename "$1")"
    if [ "$MODE" = "bin" ]; then
        if [ -x "$FROM" ]; then
            # Cut the FROM extension and place to /usr/local/bin/
            TO="/usr/local/bin/$(basename "$1" | sed 's/\.[^.]*$//')"
        else
            echo "Source $FROM is not executable"
            return 1
        fi
    elif [ "$MODE" = "home" ]; then
        TO="$HOME/$(basename "$1")"
    fi
fi

link_config "$FROM" "$TO"
