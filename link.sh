#!/usr/bin/bash

# This script creates symlinks for programs' config into .config
# It must be run from configs/ folder (i.e. ./link.sh) because it uses pwd

# TODO: move .config links logic to install.sh
# this script can help to link /scripts or maybe even nothing
# maybe add --only <program> to link only one program config

if [ "$0" != "./link.sh" ]; then
    echo "Creating symlinks requires running from the same folder"
    exit 1
fi

ARCH_PROGRAMS=(
    ".config/dunst"
    ".config/hypr"
    ".config/kitty"
    ".config/wofi"
)

CROSS_PROGRAMS=(
    ".config/mpv"
	".vimrc"
	".zshrc"
	".ssh"
    "Documents/Knowledge-Database/.obsidian"
)

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

# Base function to link configs from source to destination
link_config() {
    local from="$1"
    if [ ! -e "$from" ]; then
        echo "Source config $from does not exist"
        return 1
    fi
    local to="$2"
    check_existing_config "$to" || return 0
    echo "Linking: $to"
    ln -s "$from" "$to"
}


# Function to link Arch-only configs
link_arch_configs() {
    local programs=("${ARCH_PROGRAMS[@]}")
    echo "Linking Arch-only configs..."
    for p in "${programs[@]}"; do
        link_config "$(pwd)/$p" "$HOME/$p"
    done
}

# Function to link cross-distro configs (default)
link_default_configs() {
    local programs=("${CROSS_PROGRAMS[@]}")
    echo "Linking cross-distro configs (default)..."
    for p in "${programs[@]}"; do
        link_config "$(pwd)/$p" "$HOME/$p"
    done
}



# Parse script arguments and call appropriate function
SKIP_ALL=0
MODE="default"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip)
            SKIP_ALL=1
            shift
            ;;
        --arch)
            MODE="arch"
            shift
            ;;
        --help|-h)
            echo "Usage: ./link.sh [--arch] [--skip] [--help]"
            echo "  --arch    Link Arch-only configs"
            echo "  --skip    Skip existing configs without prompt"
            echo "  --help    Show this help message"
            exit 0
            ;;
        --only)
            MODE="only"
            ONLY_PROG="$2"
            if [ -z "$ONLY_PROG" ] || [ ! -e "$(pwd)/$ONLY_PROG" ]; then
                echo "Error: --only requires a program path argument."
                exit 1
            fi
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$MODE" = "arch" ]; then
    link_arch_configs
elif [ "$MODE" = "only" ]; then
    link_config "$(pwd)/$ONLY_PROG" "$HOME/$ONLY_PROG"
else
    link_default_configs
fi
