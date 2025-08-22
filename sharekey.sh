#!/bin/bash

# This script publishes "secrets" repo fine-granted token
# It encrypts it with gpg -c before
set -ae

################
#### CONFIG ####
################

# NO_PASSWORD=false # That's an idea for another script pastebin_cli-type (nobody needs it fr)
SECRET_FILE="secrets.token"
SHARE_LINK_FILE="last_paste_key.txt"
BACKEND="pastebin" # Support only pastebin for now
PASTEBIN_TOKEN_FILE="$HOME/Documents/secrets/pastebin.conf"
# # I recommend to use a reliable account for pastebin to surely delete pastes
# # pastebin requires PASTEBIN_API_DEV_KEY and PASTEBIN_API_USER_KEY
# # PASTEBIN_API_DEV_KEY - https://pastebin.com/doc_api#1
# # PASTEBIN_API_USER_KEY - https://pastebin.com/doc_api#9 (in pastebin_create_api_key)


function help(){
    echo "Usage: $0 --secret <file> --link <file> --backend-conf <file> {create|delete|get}"
    echo "Examples:"
    echo -e "\t$0 create # Create a new paste using secrets.token and save to last_paste_key.txt"
    echo -e "\t$0 get    # Get the last paste kept in last_paste_key.txt, decrypt it and save to secrets.token"
    echo -e "\t$0 delete # Delete the last paste kept in last_paste_key.txt"
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --secret|-s)
            SECRET_FILE="$2"
            shift 2
            ;;
        --link|-l)
            SHARE_LINK_FILE="$2"
            shift 2
            ;;
        --backend-conf|-bc)
            PASTEBIN_TOKEN_FILE="$2"
            shift 2
            ;;
        create|delete|get)
            # Action, handled later
            break
            ;;
        *)
            echo "Unknown option: $1"
            help
            exit 1
            ;;
    esac
done

# Require mandatory variables
if [[ -z "$SECRET_FILE" || -z "$SHARE_LINK_FILE" || -z "$BACKEND" || -z "$PASTEBIN_TOKEN_FILE" ]]; then
    help
    exit 1
fi


# Check for required files
if [[ ! -f "$SECRET_FILE" ]]; then
    echo "Error: Secret file not found: $SECRET_FILE"
    exit 1
fi

# Check for Pastebin API credentials
if [ -f "$PASTEBIN_TOKEN_FILE" ]; then
    # shellcheck source=pastebin.conf
    source "$PASTEBIN_TOKEN_FILE"
    if [ -z "$PASTEBIN_API_DEV_KEY" ] || [ -z "$PASTEBIN_API_USER_KEY" ]; then
        echo "Error: Pastebin API credentials are not set in $PASTEBIN_TOKEN_FILE."
        exit 1
    fi
else
    echo "Error: $PASTEBIN_TOKEN_FILE not found. Pastebin token not loaded."
    exit 1
fi


function check_cmd_installed {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
}

##################
#### PASTEBIN ####
##################


function pastebin_create_api_key(){
    # Only one key can be active at the same time for the same user. 
    # This key does not expire, unless a new one is generated.  
    # We recommend creating just one, then caching that key locally as it does not expire.
    curl -X POST -d "api_dev_key=$PASTEBIN_API_DEV_KEY" \
                 -d "api_user_name=$PASTEBIN_API_USER_NAME" \
                 -d "api_user_password=$PASTEBIN_API_USER_PASSWORD" \
                 "https://pastebin.com/api/api_login.php"
}


function pastebin_list_pastes(){
    curl -X POST -d "api_dev_key=$PASTEBIN_API_DEV_KEY" \
                 -d "api_user_key=$PASTEBIN_API_USER_KEY" \
                 -d 'api_option=list' -d 'api_results_limit=100' \
                 "https://pastebin.com/api/api_post.php"
}


function pastebin_create_paste() {
    local paste_private paste_expire_date paste_format paste_name paste_code
    paste_private=$1        # public = 0, unlisted = 1, private = 2
    paste_expire_date=$2    # N = Never, 10M = 10 Minutes, 1M = 1 Month, 1Y = 1 Year 
    paste_format=$3         # https://pastebin.com/doc_api#5
    paste_name=$4
    paste_code=$5
    paste_key=$(curl -X POST \
                 -d "api_dev_key=$PASTEBIN_API_DEV_KEY" \
                 -d "api_user_key=$PASTEBIN_API_USER_KEY" \
                 -d 'api_option=paste' \
                 -d "api_paste_private=$paste_private" \
                 -d "api_paste_expire_date=$paste_expire_date" \
                 -d "api_paste_format=$paste_format" \
                 --data-urlencode "api_paste_name=$paste_name" \
                 --data-urlencode "api_paste_code=$paste_code" \
                 "https://pastebin.com/api/api_post.php")
    echo "$paste_key" > $SHARE_LINK_FILE
    echo "Paste created with key: $paste_key"
}

function pastebin_get_paste() {
    local paste_key
    paste_key=$1
    paste_code=$(curl -X POST -d "api_dev_key=$PASTEBIN_API_DEV_KEY" \
                 -d "api_user_key=$PASTEBIN_API_USER_KEY" \
                 -d 'api_option=show_paste' -d "api_paste_key=$paste_key" \
                 "https://pastebin.com/api/api_post.php")
    echo "$paste_code"
}

function pastebin_delete_paste() {
    local paste_key
    paste_key=$1
    curl -X POST -d "api_dev_key=$PASTEBIN_API_DEV_KEY" \
                 -d "api_user_key=$PASTEBIN_API_USER_KEY" \
                 -d 'api_option=delete' -d "api_paste_key=$paste_key" \
                 "https://pastebin.com/api/api_post.php"
}


################
#### ACTION ####
################

function create_func() {
    echo "No backend selected"
}

function delete_func() {
    echo "No backend selected"
}

function get_func() {
    echo "No backend selected"
}

case "$BACKEND" in
    bitwarden)
        echo "Selected: Bitwarden"
        # Add Bitwarden-related commands here
        check_cmd_installed "bw"
        echo "Not implemented!"
        exit 1
        ;;
    repo)
        echo "Selected: Repo"
        # Add repo-related commands here
        check_cmd_installed "git"
        echo "Not implemented!"
        exit 1
        ;;
    gist)
        echo "Selected: Gist"
        # Add gist-related commands here
        check_cmd_installed "curl"
        echo "Not implemented!"
        exit 1
        ;;
    site)
        echo "Selected: Site"
        # Add site-related commands here
        check_cmd_installed "curl"
        echo "Not implemented!"
        exit 1
        ;;
    pastebin)
        echo "Selected: Pastebin"
        check_cmd_installed "curl"
        check_cmd_installed "gpg"
        function create_func(){
            # Create unlisted paste for 10 minutes with a gpg encrypted file
            echo "Encrypt the $SECRET_FILE"
            gpg -c $SECRET_FILE
            echo "Publish the $SECRET_FILE.gpg"
            pastebin_create_paste 1 "10M" "sshconfig" "$SECRET_FILE.gpg" "$(cat $SECRET_FILE.gpg)"
            echo "Unlisted paste available for 10 minutes: $(cat $SHARE_LINK_FILE)"
        }
        function delete_func(){
            # Remove paste from SHARE_LINK_FILE's contents
            local paste_code
            paste_code="$(cat $SHARE_LINK_FILE)"
            echo "Removing paste: $paste_code"
            pastebin_delete_paste "$(basename "$paste_code")"
            rm $SHARE_LINK_FILE
        }
        function get_func(){
            # Retrieve paste from SHARE_LINK_FILE's contents
            # And try to decrypt it
            local paste_code
            paste_code="$(cat $SHARE_LINK_FILE)"
            echo "Retrieving paste: $paste_code"
            pastebin_get_paste "$(basename "$paste_code")" > "$SECRET_FILE.gpg"
            echo "Decrypting the $SECRET_FILE.gpg"
            gpg -d "$SECRET_FILE.gpg" > "$SECRET_FILE"
            echo "Decrypted file available as: $SECRET_FILE"
        }
        ;;
    *)
        echo "Unknown backend! Use: {bitwarden|repo|gist|site|pastebin}"
        exit 1
        ;;
esac 


case "$1" in 
    create)
        create_func
    ;;
    delete)
        delete_func
    ;;
    get)
        get_func
    ;;
esac