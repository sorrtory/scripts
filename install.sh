#!/bin/bash

# This script automates installation of software packages on Ubuntu

# The following line sets strict error handling options:
# -e: Exit immediately if any command exits with a non-zero status.
# -u: Treat unset variables as an error and exit immediately.
# -o pipefail: The return value of a pipeline is the status of the last command 
# to exit with a non-zero status, or zero if all commands in the pipeline exit successfully.
set -euo pipefail

#########################
##### Configuration #####
#########################

CONFIG="$HOME/Documents/scripts/install.conf"

# Logging functions

info_start() {
	echo ">== $* ==>"
}

info_end() {
	echo "<== $* ==<"
}

info_ok() {
	echo "[OK]  $*"
}

info_bad() {
	echo "[BAD] $* [X]"
}

# Help section: Options from install.conf
print_help() {
		cat <<EOF
Usage: $0 [ENVIRONMENTS] [OPTION]

This is a bootstrap script that automates installation and configuration
$0 is planned to be used with install.conf on Ubuntu
https://github.com/sorrtory/scripts?tab=readme-ov-file#installsh

Options:
	all               Install all packages, snaps, and special packages.
	chrome            Installs Google Chrome.
	clone-repos       Clones repositories listed in REPOS_TO_CLONE (edit this variable to change repos).
	code              Installs Visual Studio Code and MesloLGS NF fonts.
	configs           Links configuration files using link.sh. Must be run from the directory containing link.sh.
	check             Default. Runs system checks for installed packages, snaps, special packages, clones, and proxy.
	dbeaver           Installs DBeaver CE.
	docker            Installs Docker CE and related components.
	proxy             Sets up an LXD container, installs WireGuard and Squid, and configures Firefox to use this proxy.
	gnome             Applies GNOME desktop customizations and installs extensions.
	golang            Installs the latest Go and updates PATH.
	help              Show this help message.
	pkgs              Installs APT packages listed in PKGS (edit this variable to change packages).
	setup             Run all setup steps (GNOME, SSH key, repo clone, configs, external proxy).
	snaps             Installs Snap packages listed in the SNAP_PKGS dictionary
	spotify           Installs Spotify.
	link-ssh          Links SSH configuration files using link.sh and LINK_TO_SSH.
	github            Sets up SSH key and git config for GitHub. Starts ssh-agent and creates a key if GITHUB_KEY doesn't exist.
	sublime           Installs Sublime Text and Sublime Merge.

Environment (from install.conf) variables that can be overridden with --<var>=<value> args:
> WARNING: Can't pass any lists or spaces, use install.conf for it
	--config               CONFIG (path to install.sh config file)
	--email                EMAIL (GitHub noreply email)
	--name 				   NAME (Github name)
	--gsettings-cmds       GSETTINGS_CMDS (list of gsettings commands). Executes before extensions and keybindings
	--add-extensions       ADD_EXTENSIONS (list of GNOME extensions to install)
	--github               GITHUB (GitHub SSH URL)
	--github-key           GITHUB_KEY (SSH key path)
	--links                LINKS (list of source:destination pairs for linking)
	--link-to-ssh          LINK_TO_SSH (link options for SSH config)
	--vpn-profiles-folder  VPN_PROFILES_FOLDER (folder with VPN profiles)
	--vpn-default-profile  VPN_DEFAULT_PROFILE (default VPN profile)
	--vpn-container        VPN_CONTAINER_NAME (LXD container for proxy)
	--install-cmd          INSTALL_CMD (apt install command)
	--update-cmd           UPDATE_CMD (apt update command)
	--add-repo-cmd         ADD_REPO_CMD (add-apt-repository command)
	--pkg-repos            PKG_REPOS (list of package repositories)
	--pkgs                 PKGS (list of packages to install)
	--custom-launchers     CUSTOM_LAUNCHERS (custom gnome keybindings)
	--snap-pkgs            SNAP_PKGS (snap packages)
	--repos-to-clone       REPOS_TO_CLONE (GitHub repos to clone)
	--special-pkgs         SPECIAL_PKGS (special install functions)
	--firefox-preferences  FIREFOX_PREFERENCES (Firefox preferences). Will substitute EXTERNAL_PROXY_IP with the actual value

I recommend to create install.conf before using this script

Examples:
  # Lists cannot be passed via command line, set them in install.conf
  $0 --pkgs=(git, )    						# Nope, can't use lists. Use install.conf
  $0 --link-ssh=~/.ssh/ed25519 link-ssh     # And this won't work either

  $0 check             						# Check everything
  $0 all               						# Install everything
  $0 link-ssh          						# Link SSH configuration files
  $0 setup             						# Run all setup steps
  $0 configs           						# Link just configuration files
  $0 github           						# Set up git config and SSH key for GitHub
EOF
}
## Source install.conf and overwrite it with provided --<var>=<value> args
declare -A ENV_OVERRIDES

# Parse environment variable overrides from command-line arguments
for arg in "$@"; do
	if [[ "$arg" =~ ^--([a-zA-Z0-9_-]+)=(.*)$ ]]; then
		key="${BASH_REMATCH[1]}"
		val="${BASH_REMATCH[2]}"
		ENV_OVERRIDES["$key"]="$val"
	fi
done

# If ENV_OVERRIDES contains "config", override CONFIG before sourcing install.conf
if [[ -n "${ENV_OVERRIDES[config]:-}" ]]; then
	CONFIG="${ENV_OVERRIDES[config]}"
fi

# Load environment variables from config
if [ -f "$CONFIG" ]; then
	source "$CONFIG"
else
	echo "!!!!!!!!!! WARNING !!!!!!!!!!!"
	echo "!!! install.conf not found !!!"
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo "$CONFIG doesn't exist"
	echo "I have no idea what will happen next"
	read -p "Continue anyway? [y/N]: " answer
	if [[ ! "$answer" =~ ^[Yy]$ ]]; then
		echo "Fine. Exiting."
		exit 1
	fi
fi

# Override CONFIG variables with command-line values from ENV_OVERRIDES
for key in "${!ENV_OVERRIDES[@]}"; do
	# Convert key to uppercase and replace dashes with underscores
	var_name=$(echo "$key" | tr '[:lower:]-' '[:upper:]_')
	eval "$var_name=\"${ENV_OVERRIDES[$key]}\""
done

# Remove env overrides from positional parameters
set -- $(printf '%s\n' "$@" | grep -vE '^--[a-zA-Z0-9_-]+=.*$')

### Check config

# Check all required config variables
missing_vars=()
[ -z "${EMAIL:-}" ] && missing_vars+=("EMAIL (--email)")
[ -z "${GITHUB:-}" ] && missing_vars+=("GITHUB (--github)")
[ -z "${GITHUB_KEY:-}" ] && missing_vars+=("GITHUB_KEY (--github-key)")
[ -z "${LINKS:-}" ] && missing_vars+=("LINKS (--links)")
[ -z "${VPN_PROFILES_FOLDER:-}" ] && missing_vars+=("VPN_PROFILES_FOLDER (--vpn-profiles-folder)")
[ -z "${VPN_DEFAULT_PROFILE:-}" ] && missing_vars+=("VPN_DEFAULT_PROFILE (--vpn-default-profile)")
[ -z "${VPN_CONTAINER_NAME:-}" ] && missing_vars+=("VPN_CONTAINER_NAME (--vpn-container)")
[ -z "${INSTALL_CMD:-}" ] && missing_vars+=("INSTALL_CMD (--install-cmd)")
[ -z "${UPDATE_CMD:-}" ] && missing_vars+=("UPDATE_CMD (--update-cmd)")
[ -z "${ADD_REPO_CMD:-}" ] && missing_vars+=("ADD_REPO_CMD (--add-repo-cmd)")
[ "${#PKG_REPOS[@]}" -eq 0 ] && missing_vars+=("PKG_REPOS (--pkg-repos)")
[ "${#PKGS[@]}" -eq 0 ] && missing_vars+=("PKGS (set in install.conf)")
[ "${#CUSTOM_LAUNCHERS[@]}" -eq 0 ] && missing_vars+=("CUSTOM_LAUNCHERS (set in install.conf)")
[ "${#SNAP_PKGS[@]}" -eq 0 ] && missing_vars+=("SNAP_PKGS (set in install.conf)")
[ "${#REPOS_TO_CLONE[@]}" -eq 0 ] && missing_vars+=("REPOS_TO_CLONE (set in install.conf)")
[ "${#SPECIAL_PKGS[@]}" -eq 0 ] && missing_vars+=("SPECIAL_PKGS (set in install.conf)")

if [ "${#missing_vars[@]}" -gt 0 ]; then
	echo "WARNING: The following required config variables are missing:"
	for var in "${missing_vars[@]}"; do
		echo "  $var"
	done
	echo "Some features may not work correctly. Please set these in install.conf or via command line."
fi

###################
##### Scripts #####
###################

function link_configs() {
	info_start "Linking configs"
	if [[ -x "$(dirname "$0")/link.sh" ]]; then
		for link in "${LINKS[@]}"; do
			# Use $link with args. Don't need to quote it
			"$(dirname "$0")/link.sh" $link
		done
	else
		info_bad "link.sh not found or not executable"
	fi
	info_end "Linking configs done"
}

function link_ssh() {
	# This is called separately from link_configs
	# Because we need ssh key to clone private repos before linking configs
	info_start "Linking SSH config"
	if [[ -x "$(dirname "$0")/link.sh" ]]; then
		"$(dirname "$0")/link.sh" $LINK_TO_SSH
		sudo chmod -R 600 ~/.ssh
		sudo chmod 644 ~/.ssh/config
		sudo chmod 644 ~/.ssh/*.pub
		sudo chmod 755 ~/.ssh

	else
		info_bad "link.sh not found or not executable"
	fi
	info_end "Linking SSH config done"
}

function do_check() {
	info_start "Running system checks ..."
	detect_distro
	echo ""
	
	local all_ok clones_ok proxy_ok pkgs_ok snap_pkgs_ok special_pkgs_ok
	all_ok="OK"
	clones_ok="OK"
	proxy_ok="OK"
	pkgs_ok="OK"
	snap_pkgs_ok="OK"
	special_pkgs_ok="OK"

	# Create Documents directory if it doesn't exist
	if [ ! -d "$HOME/Documents" ]; then
		echo "Creating Documents directory"
		mkdir -p "$HOME/Documents"
	fi

	# Check clones
	info_start "Check clones"
	for repo in "${REPOS_TO_CLONE[@]}"; do
		if [ -d "$HOME/Documents/$repo" ]; then
			info_ok "$repo folder already exists in Documents"
		else
			info_bad "$repo folder does not exist in Documents"
			clones_ok="BAD"
		fi
	done
	info_end "Check clones [${clones_ok}]"
	echo ""

	info_start "Check externalProxy"
	if lxc info $VPN_CONTAINER_NAME >> /dev/null; then
		local host_ip
		host_ip=$(curl -s 2ip.ru)
		local container_ip
		container_ip=$(lxc exec $VPN_CONTAINER_NAME -- curl -s 2ip.ru)
		if [ "$host_ip" != "$container_ip" ]; then
			info_ok "$VPN_CONTAINER_NAME is running fine"
		else
			info_bad "$VPN_CONTAINER_NAME is running, but VPN is not working"
			proxy_ok="BAD"
		fi
	else
		info_bad "$VPN_CONTAINER_NAME is not running"
		proxy_ok="BAD"
	fi
	info_end "Check externalProxy [${proxy_ok}]"
	echo ""

	info_start "Check installed packages"
	for cmd in "${PKGS[@]}" ; do
		if dpkg-query -W "$cmd" &> /dev/null; then
			info_ok "$cmd is installed"
		else
			info_bad "$cmd is not installed"
			pkgs_ok="BAD"
		fi
	done
	info_end "Check installed packages [${pkgs_ok}]"
	echo ""

	info_start "Check snap packages"
	for cmd in "${!SNAP_PKGS[@]}" ; do
		if snap list $cmd &> /dev/null; then
			info_ok "$cmd is installed"
		else
			info_bad "$cmd is not installed"
			snap_pkgs_ok="BAD"
		fi
	done
	info_end "Check snap packages [${snap_pkgs_ok}]"
	echo ""

	info_start "Check special packages"
	for cmd in "${!SPECIAL_PKGS[@]}" ; do
		if command -v "$cmd" &> /dev/null; then
			info_ok "$cmd is installed"
		else
			info_bad "$cmd is not installed"
			special_pkgs_ok="BAD"
		fi
	done
	info_end "Check specials packages [${special_pkgs_ok}]"
	echo ""

	if [[ "$clones_ok" == "BAD" || 
		  "$proxy_ok" == "BAD" || 
		  "$pkgs_ok" == "BAD" || 
		  "$snap_pkgs_ok" == "BAD" || 
		  "$special_pkgs_ok" == "BAD" ]]; then
		all_ok="BAD"
	fi
	info_end "System check result [${all_ok}]"
}
	
function detect_distro() {
	# Stick to ubuntu for now

	if [ -f /etc/os-release ]; then
		. /etc/os-release
		case "$ID" in
			ubuntu|debian)
				# INSTALL_CMD="sudo apt install -y"
				info_ok "Detected Ubuntu/Debian"
				;;
			arch)
				INSTALL_CMD="sudo pacman -S --noconfirm"
				PKGS=(openssh os-prober "${PKGS[@]}")
				info_bad "Detected Arch Linux. Exiting."
				exit 1
				;;
			fedora)
				INSTALL_CMD="sudo dnf install -y"
				info_bad "Detected Fedora. Exiting."
				exit 1
				;;
			*)
				info_bad "Unsupported distro: $ID. Exiting."
				exit 1
				;;
		esac
	else
		echo "/etc/os-release not found. Cannot detect distro."
		exit 1
	fi
}


####################
##### Installs #####
####################

function install_pkgs() {
	info_start "Installing packages: ${PKGS[*]}"

	echo "Adding repos..."
	for repo in "${PKG_REPOS[@]}"; do
		$ADD_REPO_CMD "$repo"
	done
	$UPDATE_CMD

	$INSTALL_CMD "${PKGS[@]}"
	info_end "Packages installed"
}

function install_snaps() {
	info_start "Installing Snap packages"

	if ! command -v snap &> /dev/null; then
		echo "Snap is not installed"
		exit 1
	fi


	for pkg in "${!SNAP_PKGS[@]}"; do
		if [[ -n "${SNAP_PKGS[$pkg]}" ]]; then
			sudo snap install "$pkg" ${SNAP_PKGS[$pkg]}
		else
			sudo snap install "$pkg"
		fi
	done

	echo "Warning LXD requires user to be in the 'lxd' group and also needs a system reboot"
	info_end "Snap packages installed"
	echo "Some snap packages may require a system reboot to function properly."
	read -p "Would you like to reboot now? [y/N]: " REBOOT_ANSWER
	if [[ "$REBOOT_ANSWER" =~ ^[Yy]$ ]]; then
		sudo reboot
	fi
}

function install_golang() {
	info_start "Installing Go"
	# Download latest Go
	GO_VERSION=$(curl -s "https://go.dev/VERSION?m=text" | head -n 1)
	GO_TAR="${GO_VERSION}.linux-amd64.tar.gz"
	wget "https://dl.google.com/go/${GO_TAR}"
	sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "${GO_TAR}"
	rm "${GO_TAR}"

	# Add Go to PATH
	echo "Adding Go to PATH"
	GO_PATH="/usr/local/go/bin"
	ENV_FILE="/etc/environment"
	if [[ ! -f "$ENV_FILE" ]]; then
		echo "ERROR: $ENV_FILE does not exist" >&2
		exit 1
	fi
	sudo cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%F_%T)"
	echo "Backup created: $ENV_FILE.bak.$(date +%F_%T)"
	CURRENT_PATH=$(grep -E '^PATH=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')
	if [[ -z "$CURRENT_PATH" ]]; then
		echo "PATH=\"$GO_PATH\"" | sudo tee -a "$ENV_FILE" >/dev/null
		echo "Added new PATH with Go bin"
		info_end "Go installed and PATH updated"
		return
	fi
	if [[ ":$CURRENT_PATH:" == *":$GO_PATH:"* ]]; then
		echo "Go path already in PATH, nothing to do."
		info_end "Go installed and PATH updated"
		return
	fi
	NEW_PATH="$CURRENT_PATH:$GO_PATH"
	sudo sed -i "s|^PATH=.*|PATH=\"$NEW_PATH\"|" "$ENV_FILE"
	info_end "Go installed and PATH updated"
}

function install_sublime() {
	# Install sublime text
	info_start "Installing Sublime Text"
	wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo tee /etc/apt/keyrings/sublimehq-pub.asc > /dev/null
	echo -e 'Types: deb\nURIs: https://download.sublimetext.com/\nSuites: apt/stable/\nSigned-By: /etc/apt/keyrings/sublimehq-pub.asc' | sudo tee /etc/apt/sources.list.d/sublime-text.sources
	$UPDATE_CMD
	$INSTALL_CMD apt-transport-https
	
	$INSTALL_CMD sublime-text
	info_end "Sublime Text installed"

	# Install Sublime Merge
	info_start "Installing Sublime Merge"
	$INSTALL_CMD sublime-merge
	info_end "Sublime Merge installed"
}

function install_chrome() {
	info_start "Installing Google Chrome"
	wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/google.gpg
	echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
	$UPDATE_CMD

	$INSTALL_CMD google-chrome-stable
	info_end "Google Chrome installed"
}


function install_code() {
	info_start "Installing Visual Studio Code"

	wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
	sudo install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg
	rm -f microsoft.gpg
	printf "Types: deb\nURIs: https://packages.microsoft.com/repos/code\nSuites: stable\nComponents: main\nArchitectures: amd64,arm64,armhf\nSigned-By: /usr/share/keyrings/microsoft.gpg" | sudo tee /etc/apt/sources.list.d/vscode.sources > /dev/null
	$UPDATE_CMD

	$INSTALL_CMD code

	# VS Code doesn't see /usr/share/fonts (where apt puts them) for some reason
	# So we need to install fonts to /usr/local/share/fonts
	echo "Installing fonts..."
	sudo wget -P /usr/local/share/fonts https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf
	sudo wget -P /usr/local/share/fonts https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf
	sudo wget -P /usr/local/share/fonts https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf
	sudo wget -P /usr/local/share/fonts https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf
	# Update font cache
	fc-cache -fv
	info_end "Visual Studio Code installed"
}

function install_dbeaver() {
	info_start "Installing DBeaver"

	sudo  wget -O /usr/share/keyrings/dbeaver.gpg.key https://dbeaver.io/debs/dbeaver.gpg.key
	echo "deb [signed-by=/usr/share/keyrings/dbeaver.gpg.key] https://dbeaver.io/debs/dbeaver-ce /" | sudo tee /etc/apt/sources.list.d/dbeaver.list
	$UPDATE_CMD

	$INSTALL_CMD dbeaver-ce
	info_end "DBeaver installed"
}

function install_spotify() {
	info_start "Installing Spotify"
	curl -sS https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
	echo "deb https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
	$UPDATE_CMD

	$INSTALL_CMD spotify-client
	info_end "Spotify installed"
}

function install_docker() {
	# https://docs.docker.com/engine/install/ubuntu/

	# Add Docker's official GPG key:
	$UPDATE_CMD
	$INSTALL_CMD ca-certificates curl
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r /etc/apt/keyrings/docker.asc

	# Add the repository to Apt sources:
	echo \
	"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
	$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
	sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	$UPDATE_CMD

	# Install the latest version
	$INSTALL_CMD docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}


##################
##### Setups #####
##################

function setup_external_proxy() {
	info_start "Setting up External Proxy in LXD"

	# Check for LXD installation
	if ! command -v lxd &> /dev/null; then
		echo "LXD is not installed. Please install LXD first."
		info_end "[Failed] External Proxy installation"
		return
	fi

	# Check for lxd group
	if id -nG "$USER" | grep -qw "lxd"; then
		echo "User '$USER' is in the lxd group"
	else
		echo "ERROR: User '$USER' is not in the lxd group. Please add the user to the lxd group and re-login."
		sudo usermod -aG lxd "$USER"
		echo "User '$USER' has been added to the lxd group. You need to restart your GNOME session or reboot."
	fi

	# Set up LXD
	if ! lxc storage list | grep -q '^default'; then
    	sudo lxd init --auto
	fi

	EXTERNAL_PROXY_IP=$(ip -o -4 addr show $(lxc profile show default | grep network | awk '{print $2}') | awk '{print $4}' | cut -d/ -f1 | cut -d\. -f1,2,3 | xargs -I{} echo "{}.254")

	lxc launch ubuntu:24.04 $VPN_CONTAINER_NAME
	sudo lxc config device override $VPN_CONTAINER_NAME eth0 ipv4.address=$EXTERNAL_PROXY_IP && lxc stop $VPN_CONTAINER_NAME && lxc start $VPN_CONTAINER_NAME

	# Clone VPN profiles inside a container
	for profile in $VPN_PROFILES_FOLDER/*.conf; do
		lxc file push -p "$profile" $VPN_CONTAINER_NAME/etc/wireguard/
	done

	lxc exec $VPN_CONTAINER_NAME -- apt update -y && lxc exec $VPN_CONTAINER_NAME -- apt upgrade -y 
	lxc exec $VPN_CONTAINER_NAME -- apt install -y squid wireguard
	echo "http_access allow all
	http_port 3128
	coredump_dir /var/spool/squid
	logfile_rotate 0" | lxc exec $VPN_CONTAINER_NAME -- tee /etc/squid/squid.conf
	# Ennable default profile
	lxc exec $VPN_CONTAINER_NAME -- systemctl enable --now wg-quick@$VPN_DEFAULT_PROFILE
	lxc restart $VPN_CONTAINER_NAME

	# Wait for the container to be ready
	lxc exec $VPN_CONTAINER_NAME -- bash -c "while ! nc -z localhost 3128; do sleep 1; done"
	info_end "Proxy: LXD setup complete"
}

function setup_firefox(){
	# Firefox is preinstalled with snap on Ubuntu 
	
	# Init firefox
	info_start "Firefox: Init"
	if ! command -v firefox &> /dev/null; then
		echo "ERROR: Firefox is not installed. Please install Firefox before continuing."
		info_end "[Failed] External Proxy setup: Firefox not configured"
		return
	fi

	echo "Starting firefox for the very first time to create config file structure"
	echo "Warning! Here is hardcoded 5 seconds sleep"
	firefox --headless &
	firefox_pid=$!
	read -t 3 -p "Wait 5 seconds for Firefox to initialize? [Y/n]: " WAIT_ANSWER
	if [[ -z "$WAIT_ANSWER" || "$WAIT_ANSWER" =~ ^[Yy]$ ]]; then
		echo "Let's wait, although firefox is usually quick"
		# User pressed enter, or answered yes, or didn't respond in 5 seconds
		sleep 5
	fi
	kill $firefox_pid

	echo "Firefox: Adding proxypath and user preferences"
	EXTERNAL_PROXY_IP=$(lxc list "$VPN_CONTAINER_NAME" --format json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address')
	# Add proxy to firefox
	FIREFOX_PROFILE_DIR=$(find "$HOME/snap/firefox/common/.mozilla/firefox" -maxdepth 1 -type d -name "*.default*" | head -n 1)
	# Substitute EXTERNAL_PROXY_IP with the actual value in FIREFOX_PREFERENCES
	echo "${FIREFOX_PREFERENCES//EXTERNAL_PROXY_IP/$EXTERNAL_PROXY_IP}" > "$FIREFOX_PROFILE_DIR/user.js"
	info_end "Proxy: Firefox proxypath and user preferences added"
}


function setup_github() {
	# Create a new SSH key if it doesn't exist
	info_start "Set SSH key for GITHUB"
	local github_ok
	if [[ -f "$GITHUB_KEY" ]]; then
		echo "SSH key already exists"
	else
		echo "Can't find a github key. Let's create?"
		if [[ -n "$EMAIL" ]]; then
			read -p "Enter your email for the SSH key or press enter to skip: " EMAIL
			if [[ ! -n "$EMAIL" ]]; then
				return
			fi
		else
			return
		fi
		ssh-keygen -t ed25519 -C "$EMAIL"
	fi
	echo "Add this key to github https://github.com/settings/keys"
	cat "$GITHUB_KEY.pub"

	# Add key to ssh-agent
	echo "Adding key to agent"
	# Gnome handles ssh-agent autostart, but you need to install it manually without gnome
	eval "$(ssh-agent -s)"
	ssh-add "$GITHUB_KEY"
	if ssh -T git@github.com; then
		github_ok="OK"
	else
		github_ok="BAD"
	fi
	info_end "GITHUB SSH key is [$github_ok]"

	info_start "Add global git email and name"
	git config --global user.name "$NAME"
	git config --global user.email "$EMAIL"
	info_end "Add global git config [DONE]"
}

function setup_gnome() {
	info_start "Setting up GNOME"

	if ! command -v curl &> /dev/null; then
		echo "ERROR: curl is not installed. Please install curl before continuing."
		info_end "[Failed] GNOME setup: curl not installed"
		return
	fi

	for cmd in "${GSETTINGS_CMDS[@]}"; do
    	echo "Running: $cmd"
    	eval "$cmd"
	done

	# Custom programs launchers
	# Custom keybinding for Firefox using variable
	function set_custom_keybinding() {
		local CMD="$1"
		local BIND="$2"
		local NAME="$3"
		local KEYBIND_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/${NAME}/"

		# Set the keybinding
		gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KEYBIND_PATH" name "$NAME"
		gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KEYBIND_PATH" command "$CMD"
		gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KEYBIND_PATH" binding "$BIND"
	}
	
	# https://askubuntu.com/questions/1499110/setting-keyboard-shortcuts-in-ubuntu-22-04-with-gsettings-whats-changed
	function append_keybinding(){
		local name="$1"
		if [ -z "$(dconf read /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings | tr -d '][')" ]; then
  			dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$name/']"
  		else
			dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings "[$(dconf read /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings | tr -d '][') , '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$name/']"
		fi
	}

	for name in "${!CUSTOM_LAUNCHERS[@]}"; do
		IFS='|' read -r CMD BIND <<< "${CUSTOM_LAUNCHERS[$name]}"
		if [[ -z "$CMD" || -z "$BIND" ]]; then
			echo "Invalid custom launcher for $name, skipping..."
			continue
		fi
		set_custom_keybinding "$CMD" "$BIND" "$name"
		append_keybinding "$name"
	done

	## Install extensions
	# blur my shell, clipboard indicator, hide top bar, 
	# ubuntu appindicator, ubuntu dock, ubuntu tiling assistant are default

	# The gnome-shell-extension-installer script is archived be careful
	if [ ! -f /usr/bin/gnome-shell-extension-installer ]; then
		echo "Installing gnome-shell-extension-installer"
		wget -O gnome-shell-extension-installer "https://github.com/brunelli/gnome-shell-extension-installer/raw/master/gnome-shell-extension-installer"
		chmod +x gnome-shell-extension-installer
		sudo mv gnome-shell-extension-installer /usr/bin/
	fi
	for ext in "${ADD_EXTENSIONS[@]}"; do
		gnome-shell-extension-installer "$ext"
	done
	echo "Extensions are installed. You have to reboot now"
	# TODO: add after_reboot.sh here, also lxd setup can be done with reboot too
	for ext in "${!ADD_EXTENSIONS[@]}"; do
		# gnome-extensions enable $ext
		echo "You should enable $ext: gnome-extensions enable $ext"
	done
	echo "Extensions WAS NOT ENABLED. You have to reboot and do that manually"

	echo "Configure them with extension-manager"
	echo "You should better logout or reboot before proceeding"

	info_end "GNOME setup complete"
}
	

###################
##### General #####
###################

function clone_repos() {
	cd "$HOME/Documents" || { echo "Can't find documents folder"; exit 1; }
	for repo in "${REPOS_TO_CLONE[@]}"; do
		if [ ! -d "$repo" ]; then
			git clone "$GITHUB/$repo.git"
		else
			echo "Repository $repo already exists. Skipping..."
		fi
	done
}

function install_special_pkgs() {
	for cmd in "${!SPECIAL_PKGS[@]}"; do
		if ! command -v "$cmd" &> /dev/null; then
			${SPECIAL_PKGS[$cmd]}
		fi
	done
}

function install_full() {
	install_pkgs
	install_special_pkgs
	install_snaps # lxd takes reboot and adding to group (see externalProxy)
}

function setup_full() {
	link_ssh
	setup_github
	clone_repos
	link_configs
	setup_gnome
	setup_external_proxy
	setup_firefox
}

function main() {
	while [[ $# -gt 0 ]]; do
		case "${1:-}" in
			all)
				install_full
				exit 0
				;;
			setup)
				setup_full
				;;
			snaps)
				install_snaps
				;;
			configs)
				link_configs
				;;
			link-ssh)
				link_ssh
				;;
			proxy)
				setup_external_proxy
				;;
			firefox)
				setup_firefox
				;;
			docker)
				install_docker
				;;
			golang)
				install_golang
				;;
			sublime)
				install_sublime
				;;
			chrome)
				install_chrome
				;;
			code)
				install_code
				;;
			dbeaver)
				install_dbeaver
				;;
			spotify)
				install_spotify
				;;
			github)
				setup_github
				;;
			clone-repos)
				clone_repos
				;;
			gnome)
				setup_gnome
				;;
			pkgs)
				install_pkgs
				;;
			check|"" )
				do_check
				;;
			help|-h)
				print_help
				exit 0
				;;
			*)
				echo "Unknown option: $1. See $0 help"
				exit 1
				;;
		esac
		shift
	done
}

if [[ "$#" -eq 0 ]]; then
	echo "No arguments provided. Doing check"
	do_check
else
	main "$@"
fi
