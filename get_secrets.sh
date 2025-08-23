#!/bin/bash

# No Amazon KMS :(
# Just a quick pastebin and plain gpg -c

BACKEND=https://pastebin.com/raw # Support only pastebin for now
TOKEN_FILE_NAME=secrets.token
SECRETS_URL=github.com/sorrtory/secrets
SECRETS_CLONE_PATH="$HOME/Documents/$(basename $SECRETS_URL)"

# Check if already completed
if [ -d "$SECRETS_CLONE_PATH" ]; then
    echo "Secrets folder already exists: $SECRETS_CLONE_PATH. Exiting."
    exit 0
fi

echo "Obtaining the token from $BACKEND"
if [ -f "$TOKEN_FILE_NAME.gpg" ]; then
    echo "Encrypted token $TOKEN_FILE_NAME.gpg exists. Skipping the curl for it"
else
    # Request pastebin
    read -p "Enter the paste numbers: " nums
    bytes=$(curl "$BACKEND/$nums")
    if [ -n "$bytes" ]; then
        echo "$bytes" > $TOKEN_FILE_NAME.gpg
    else
        echo "Failed to retrieve the paste."
        exit 1
    fi
fi

echo "Decrypting token file $TOKEN_FILE_NAME.gpg"
if [ -f "$TOKEN_FILE_NAME" ]; then
    echo "Token file already decrypted. Skipping decryption"
else
    echo "Write a passphrase for gpg:"
    gpg --decrypt $TOKEN_FILE_NAME.gpg

    # Check for token was decrypted
    if [ ! -f "$TOKEN_FILE_NAME" ]; then
        echo "Failed to decrypt the token."
        exit 1
    fi
fi

echo "Cloning the secrets repository to $SECRETS_CLONE_PATH"
if git clone "https://$(cat $TOKEN_FILE_NAME)@$SECRETS_URL" "$SECRETS_CLONE_PATH"; then
    echo "Secrets repository cloned successfully."
else
    echo "Failed to clone secrets repository."
    exit 1
fi