#!/bin/bash

# This script automates installation of software packages on Ubuntu

# The following line sets strict error handling options:
# -e: Exit immediately if any command exits with a non-zero status.
# -u: Treat unset variables as an error and exit immediately.
# -o pipefail: The return value of a pipeline is the status of the last command 
# to exit with a non-zero status, or zero if all commands in the pipeline exit successfully.
set -aeuo pipefail

##################
##### Config #####
##################

if [ ! -f "install.conf" ]; then
	echo "!!!!!!!!!! WARNING !!!!!!!!!!!"
	echo "!!! install.conf not found !!!"
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo "I have no idea what will happen next"
	read -p "Continue anyway? [y/N]: " answer
	if [[ ! "$answer" =~ ^[Yy]$ ]]; then
		echo "Fine. Exiting."
		exit 1
	fi
fi


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
Usage: $0 [OPTIONS]

This is a bootstrap script that automates installation and configuration
It is planned to use this on Ubuntu
https://github.com/sorrtory/scripts?tab=readme-ov-file#installsh

Options:
  install           Install all packages, snaps, and special packages.
  setup             Run all setup steps (GNOME, SSH key, repo clone, configs, external proxy).
  snaps             Installs Snap packages listed in the SNAP_PKGS dictionary at the top of the script.
                    You can edit SNAP_PKGS to add or remove snap packages.
  sublime           Installs Sublime Text and Sublime Merge.
  external-proxy    Sets up an LXD container, installs WireGuard and Squid, and configures Firefox to use the proxy.
  chrome            Installs Google Chrome.
  code              Installs Visual Studio Code and MesloLGS NF fonts.
  dbeaver           Installs DBeaver CE.
  spotify           Installs Spotify.
  docker            Installs Docker CE and related components.
  golang            Installs the latest Go and updates PATH.
  ssh-key           Sets up SSH key for GitHub. Starts ssh-agent
  clone-repos       Clones repositories listed in REPOS_TO_CLONE (edit this variable to change repos).
  configs           Links configuration files using link.sh. Must be run from the directory containing link.sh.
  gnome             Applies GNOME desktop customizations and installs extensions.
  pkgs              Installs APT packages listed in PKGS (edit this variable to change packages).
  check             Default. Runs system checks for installed packages, snaps, special packages, clones, and proxy.
  help              Show this help message.

Environment (from install.conf):
	--email                EMAIL (GitHub noreply email)
	--github               GITHUB (GitHub SSH URL)
	--github-key           GITHUB_KEY (SSH key path)
	--vpn-profile          VPN_PROFILE (default VPN profile)
	--vpn-container        VPN_CONTAINER_NAME (LXD container for proxy)
	--install-cmd          INSTALL_CMD (apt install command)
	--update-cmd           UPDATE_CMD (apt update command)
	--add-repo-cmd         ADD_REPO_CMD (add-apt-repository command)
	--pkg-repos            PKG_REPOS (list of package repositories)
	--pkgs                 PKGS (list of packages to install)
	--custom-launchers     CUSTOM_LAUNCHERS (custom keybindings)
	--snap-pkgs            SNAP_PKGS (snap packages)
	--repos-to-clone       REPOS_TO_CLONE (GitHub repos to clone)
	--special-pkgs         SPECIAL_PKGS (special install functions)

I recommend to create install.conf before using this script

Examples:
  $0 --pkgs=(git, ) # can't use lists . But I want a general install script like ubuntu/arch install code and this script detects distro and selects the algo dynamically
  $0 install
  $0 setup
  $0 snaps
EOF
}
# TODO: TThis is shit and I'm too tired to fix it now
## This GPT shit should source install.conf and overwrite it with --params
# Load environment variables from install.conf unless overridden by command-line
declare -A ENV_OVERRIDES

# Parse environment variable overrides from command-line arguments
for arg in "$@"; do
	if [[ "$arg" =~ ^--([a-zA-Z0-9_-]+)=(.*)$ ]]; then
		key="${BASH_REMATCH[1]}"
		val="${BASH_REMATCH[2]}"
		ENV_OVERRIDES["$key"]="$val"
	fi
done

# Source install.conf if it exists
if [ -f "install.conf" ]; then
	. install.conf
fi

# Override variables with command-line values
for key in "${!ENV_OVERRIDES[@]}"; do
	# Convert key to uppercase and replace dashes with underscores
	var_name=$(echo "$key" | tr '[:lower:]-' '[:upper:]_')
	eval "$var_name=\"${ENV_OVERRIDES[$key]}\""
done

# Remove env overrides from positional parameters
set -- $(printf '%s\n' "$@" | grep -vE '^--[a-zA-Z0-9_-]+=.*$')
## end of GPT shit

## Check config

if [ -z "$GITHUB" ]; then
	echo "GITHUB isn't set. Can't do clones then"
fi

if [ ! -f "$GITHUB_KEY" ]; then
	echo "GITHUB_KEY isn't set. Computer is likely to has no access to clones"
fi


# TODO: ...



###################
##### Scripts #####
###################

function link_configs() {
	info_start "Linking configs"
	if [[ -x "$(dirname "$0")/link.sh" ]]; then
		"$(dirname "$0")/link.sh"
	else
		info_bad "link.sh not found or not executable"
	fi
	info_end "Linking configs done"
}

function do_check() {
	info_start "Running system checks ..."
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
		host_ip=$(curl 2ip.ru)
		local container_ip
		container_ip=$(lxc exec $VPN_CONTAINER_NAME -- curl 2ip.ru)
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
		if dpkg -s "$cmd" &> /dev/null; then
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

	detect_distro
}
	
function detect_distro() {
	# Stick to ubuntu for now

	if [ -f /etc/os-release ]; then
		. /etc/os-release
		case "$ID" in
			ubuntu|debian)
				# INSTALL_CMD="sudo apt install -y"
				echo "Detected Ubuntu/Debian"
				;;
			arch)
				INSTALL_CMD="sudo pacman -S --noconfirm"
				PKGS=(openssh os-prober "${PKGS[@]}")
				echo "Detected Arch Linux. Exiting."
				exit 1
				;;
			fedora)
				INSTALL_CMD="sudo dnf install -y"
				echo "Detected Fedora. Exiting."
				exit 1
				;;
			*)
				echo "Unsupported distro: $ID"
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
	sudo apt-get update

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
		echo "User '$USER' has been added to the lxd group."
	fi

	# Set up LXD
	lxd init --auto

	EXTERNAL_PROXY_IP=$(ip -o -4 addr show $(lxc profile show default | grep network | awk '{print $2}') | awk '{print $4}' | cut -d/ -f1 | cut -d\. -f1,2,3 | xargs -I{} echo "{}.254")


	lxc launch ubuntu:24.04 $VPN_CONTAINER_NAME
	sudo lxc config device override $VPN_CONTAINER_NAME eth0 ipv4.address=$EXTERNAL_PROXY_IP && lxc stop $VPN_CONTAINER_NAME && lxc start $VPN_CONTAINER_NAME
	lxc file push -p ~/Documents/configs/wireguard/$VPN_PROFILE.conf $VPN_CONTAINER_NAME/etc/wireguard/

	lxc exec $VPN_CONTAINER_NAME -- apt update -y && lxc exec $VPN_CONTAINER_NAME -- apt upgrade -y 
	lxc exec $VPN_CONTAINER_NAME -- apt install -y squid wireguard
	lxc exec $VPN_CONTAINER_NAME -- echo "http_access allow all
	http_port 3128
	coredump_dir /var/spool/squid
	logfile_rotate 0" > /etc/squid/squid.conf
	lxc exec $VPN_CONTAINER_NAME systemctl enable --now wg-quick@$VPN_PROFILE
	lxc restart $VPN_CONTAINER_NAME

	# Wait for the container to be ready
	lxc exec $VPN_CONTAINER_NAME -- bash -c "while ! nc -z localhost 3128; do sleep 1; done"
	info_end "Proxy: LXD setup complete"

	# Init firefox
	info_start "Proxy: Adding proxypath to Firefox"
	if ! command -v firefox &> /dev/null; then
		echo "ERROR: Firefox is not installed. Please install Firefox before continuing."
		info_end "[Failed] External Proxy setup: Firefox not configured"
		return
	fi

	firefox --headless &
	firefox_pid=$!
	sleep 5
	kill $firefox_pid

	# Add proxy to firefox
	FIREFOX_PROFILE_DIR=$(find "$HOME/snap/firefox/common/.mozilla/firefox" -maxdepth 1 -type d -name "*.default*" | head -n 1)
		cat > "$FIREFOX_PROFILE_DIR/user.js" <<-EOF
		user_pref("network.proxy.type", 1);
		user_pref("network.proxy.http", "$EXTERNAL_PROXY_IP");
		user_pref("network.proxy.http_port", 3128);
		user_pref("network.proxy.ssl", "$EXTERNAL_PROXY_IP");
		user_pref("network.proxy.ssl_port", 3128);
		user_pref("browser.tabs.insertAfterCurrent", true);
		user_pref("browser.ctrlTab.sortByRecentlyUsed", true);
	EOF

	info_end "Proxy: Firefox proxypath added"
}


function setup_ssh_key() {
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
}

function setup_gnome() {
	info_start "Setting up GNOME"

	## General ubuntu-gnome configuration

	# Center new windows
	gsettings set org.gnome.mutter center-new-windows true

	# Set keyboard layout and input sources
	gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'ru')]"
	gsettings set org.gnome.desktop.input-sources xkb-options "['grp:alt_shift_toggle']"

	# Set dock position
	gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'
	gsettings set org.gnome.shell.extensions.dash-to-dock show-show-apps-button false
	gsettings set org.gnome.shell.extensions.dash-to-dock show-trash false
	gsettings set org.gnome.shell.extensions.dash-to-dock always-center-icons true
	
	# Disable super+1.2.3... for dock launchers
	# https://askubuntu.com/questions/968103/disable-the-default-app-key-supernum-functionality-on-ubuntu-17-10-and-later
	# Switch to app looks useful. Let's try to keep it (the command bellow disables it)
	# gsettings set org.gnome.shell.keybindings switch-to-application-1 [] # Repeat for 1-9
	gsettings set org.gnome.shell.extensions.dash-to-dock hot-keys false

	# Set dock Behaviour
	gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize'
	gsettings set org.gnome.shell.extensions.dash-to-dock autohide true
	gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
	gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
	gsettings set org.gnome.shell.extensions.dash-to-dock intellihide-mode "ALL_WINDOWS"
	gsettings set org.gnome.shell.extensions.dash-to-dock extend-height true
	# NOTE: There could be a problem with pressure sensitivity
	# panel may require hard move to activate

	# Set dock Transparency
	gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode "DYNAMIC"
	gsettings set org.gnome.shell.extensions.dash-to-dock customize-alphas true
	gsettings set org.gnome.shell.extensions.dash-to-dock min-alpha 0.0
	gsettings set org.gnome.shell.extensions.dash-to-dock max-alpha 0.8


	## Keybindings

	# Move window left/right
	gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-left "['<Control><Super>Left']"
	gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-right "['<Control><Super>Right']"

	# Switch workspace left/right
	gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-left "['<Control><Alt>Left']"
	gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-right "['<Control><Alt>Right']"

	# Close window
	gsettings set org.gnome.desktop.wm.keybindings close "['<Super>q']"


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

	# This script is archived be careful
	wget -O gnome-shell-extension-installer "https://github.com/brunelli/gnome-shell-extension-installer/raw/master/gnome-shell-extension-installer"
	chmod +x gnome-shell-extension-installer
	sudo mv gnome-shell-extension-installer /usr/bin/
	gnome-shell-extension-installer 3193 # blur-my-shell
	gnome-shell-extension-installer 779  # clipboard-indicator
	gnome-shell-extension-installer 545  # hide-top-bar

	gnome-extensions enable blur-my-shell@aunetx
	gnome-extensions enable clipboard-indicator@tudmotu.com
	gnome-extensions enable hidetopbar@mathieu.bidon.ca

	echo "Extensions installed, configure them with"
	echo "extension-manager"
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
	setup_gnome
	setup_ssh_key
	clone_repos
	link_configs 
	setup_external_proxy
}

function main() {
	while [[ $# -gt 0 ]]; do
		case "${1:-}" in
			--install)
				install_full
				exit 0
				;;
			--setup)
				setup_full
				;;
			--snaps)
				install_snaps
				;;
			--configs)
				link_configs
				;;
			--external-proxy)
				setup_external_proxy
				;;
			--docker)
				install_docker
				;;
			--golang)
				install_golang
				;;
			--sublime)
				install_sublime
				;;
			--chrome)
				install_chrome
				;;
			--code)
				install_code
				;;
			--dbeaver)
				install_dbeaver
				;;
			--spotify)
				install_spotify
				;;
			--ssh-key)
				setup_ssh_key
				;;
			--clone-repos)
				clone_repos
				;;
			--gnome)
				setup_gnome
				;;
			--pkgs)
				install_pkgs
				;;
			--check|"" )
				do_check
				;;
			--help|-h)
				print_help
				exit 0
				;;
			*)
				echo "Usage: $0 [--help|--snaps|--git|--configs|--external-proxy|--golang|--sublime|--chrome|--code|--dbeaver|--spotify|--ssh-key|--clone-repos|--gnome|--pkgs|--check]"
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
