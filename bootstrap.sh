#!/bin/bash

# This script is intended to be one liner for ubuntu setup

sudo apt update -y && sudo apt upgrade -y
sudo apt install -y curl gpg git

if [ ! -d "$HOME/Documents" ]; then
    mkdir -p "$HOME/Documents"
fi

echo "Cloning scripts repository"
git clone https://github.com/sorrtory/scripts ~/Documents/scripts
cd "$HOME/Documents/scripts" || exit 1

export SAVED_PASTE_NUMBERS_FILE=shared_pat_nums.txt
if ./get_secrets.sh; then
    echo "Secrets cloned successfully."
else
    echo "Failed to clone secrets."
    exit 1
fi

echo "Deleting secret share"
./sharekey.sh --secret ../secrets/pastebin.conf --link $SAVED_PASTE_NUMBERS_FILE delete
rm $SAVED_PASTE_NUMBERS_FILE

echo "Linking ssh"
./link.sh --home Documents/secrets/.ssh

echo "Installing packages"
./install.sh 