# Dotfiles/Scripts

[![Configs badge](https://img.shields.io/badge/sorrtory-configs-blue?logo=github)](https://github.com/sorrtory/configs)

[![Scripts badge](https://img.shields.io/badge/sorrtory-scripts-green?logo=github)](https://github.com/sorrtory/scripts)

[![Secrets badge](https://img.shields.io/badge/sorrtory-secrets-blue?logo=github)](https://github.com/sorrtory/secrets)

---

Some scripts I wrote to enhance my linux adventures.

Symlink to `/usr/local/bin/` and run without `.sh`

```bash
sudo ln -s $(pwd)/lofi.sh /usr/local/bin/lofi
# or with a script
sudo ./link.sh --bin lofi.sh
# Reload the terminal and run the scripts easily
lofi
```

## Description

All script are likely to be easy to update, because configuration is always at the heading

| Tag                         | Meaning                             |
| --------------------------- | ----------------------------------- |
| [Vibe](#vibe)               | Funny silly scripts                 |
| [Userscripts](#userscripts) | Userscripts for Firefox             |
| [Bootstrap](#bootstrap)     | Setup or initialization scripts     |
| [Util](#utils)              | Utility scripts for file operations |
| [Arch](#arch)               | Scripts specific to Arch Linux      |

### Vibe

Some funny experiments

#### lofi.sh

Launch a [lofi girl](https://www.youtube.com/watch?v=jfKfPfyJRdk) from the console via mpv.

#### commit_info.sh

Show usefull info about commits including commit size and nice output in general.

#### after_reboot.sh

This script automates a simple "run once after reboot" workflow:

1. **First run:**
    - Prints "Hello, world!"
    - Creates `/var/tmp/hello_after_reboot` marker file
    - Installs a systemd service to run itself at next boot
    - Initiates a reboot

2. **After reboot:**
    - Detects the marker file
    - Prints "Hello again!"
    - Removes the marker and disables/removes its systemd service
    - Will not run automatically again

### Userscripts

I used to add these scripts to [my ublock config](https://github.com/sorrtory/configs/blob/master/backups/ublock.txt) using [this](https://alex.balgavy.eu/org-roam/20220606184728-injecting-js-with-ublock-origin/)
approach (run with ublock [example](https://github.com/pixeltris/TwitchAdSolutions?tab=readme-ov-file#applying-a-script-ublock-origin)).

But here is a quote from devs of the `TwitchAdSolutions` devs

> The scripts may randomly stop being applied by uBlock Origin for unknown reasons (#200). It's recommended to use the userscript versions instead.

So I ended up switching to `Tampermonkey` to launch my user scripts.

#### block-vk-feed.js

[![Install](https://img.shields.io/badge/install-userscript-brightgreen)](https://raw.githubusercontent.com/sorrtory/scripts/refs/heads/master/monkeys/block-vk-feed.user.js)

Always redirects from VK feed to VK messages.

#### VK-Video-Downloader

[![Install](https://img.shields.io/badge/install-userscript-blue)](https://github.com/JustKappaMan/VK-Video-Downloader/raw/refs/heads/main/monkeys/scripts/VK-Video-Downloader-desktop.user.js)

[project repository](https://github.com/JustKappaMan/VK-Video-Downloader)

Allows to download videos from VK by adding a "Download" button to the video player interface.

There is also [VK Next/music saver](https://github.com/vknext/vk-music-saver) solution here to be noticed.

#### block-website.js

[![Install](https://img.shields.io/badge/install-userscript-brightgreen)](https://raw.githubusercontent.com/sorrtory/scripts/refs/heads/master/monkeys/block-website.user.js)

Redirect from specified websites to the one.

[Unhook](https://unhook.app/) is also needed to be mentioned

### Bootstrap

Fresh `ubuntu` setup scripts

#### bootstrap.sh

Convenient way to execute the bootstrap flow.

1. Clone `/scripts`
2. Get `/secrets` with `get_secrets.sh`
3. Run `install.sh` to setup the system

Basically it updates the Ubuntu, clone whole scripts,
clone secrets using pastebin-shared PAT, cleans up and check the system.

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/sorrtory/scripts/refs/heads/master/bootstrap.sh)"
# OR with some help of short.io [May be outdated]
bash -c "$(wget -qO- https://go.sorrtory.ru/bootstrap.sh)"
```

#### get_secrets.sh

1. Download byte data from pastebin
2. Ask for gpg passphrase.
3. The result is intended to be a PAT for github `/secrets` repo
4. Clone secrets repo with the obtained PAT

#### link.sh

Help to create a symlink to configuration files, etc. \
Can do backups on filename collision. \
Create a softlink like "\<from> [\<to>]"

Can be used with --dry, --bin (cuts extension for scripts), --home.

_Example:_

```bash
# Link ~/Documents/configs/mpv to ~/.config/mpv
./link.sh ../configs/mpv
./link.sh --help
```

#### install.sh

> `get_secrets.sh` can be used at first to get `/secrets` that may be required for `install.sh` to work properly.

Read settings from `install.conf` and installs packages, link configs, etc.

- custom commands and installations on `install.conf`
- localhost shadowsocks proxy
- ssh and github setup
- `/configs` linking
- gnome configuration
- install packages and software

See `./install.sh help`

##### Goal

I want a general install script like whether on ubuntu/arch just `install code`
and this script detects distro and selects the installation process automatically

### Utils

#### sharekey.sh

> Needs `/secrets` for PAT

Used in pair with `get_secrets.sh`

Encrypt the file with a passphrase, share on pastebin as unlisted for 10 mins,
let to download and delete it.

#### download_m3u.sh

Convert m3u files into mp3 files by downloading them with yt-dlp.

> Alternartive #1

1. Install [firefox addon](https://addons.mozilla.org/en-US/firefox/addon/savefromnet-helper/)
2. set `about:config` -> `browser.download.alwaysOpenPanel = false` to preven "save as" behaviour
3. Locate to desired playlist (I like to add playlist, go to my music and click to pop it up)
4. As addon can parse files now, I click `download a playlist`

> Alternative (for VK) #2

1. Use VK Next [music saver](https://vknext.net/)

#### cutname.sh

Trim the specified string of the files' name STARTING FROM THE END within a directory

#### editTorrent.sh

> Needs `/secrets` for passkey

Little `transmission-edit` wrapper that is used to replace BitTorrent passkey or
tracker URL in a torrent file.

#### vpn.sh

> Needs `/secrets` for VPN credentials


This script is intended to launch any command through VPN connection. 
To support graphics forwarding for GUI applications use `-g` flag.

Prerequisites:

```bash
# Install dependencies (dns server is not required but it gurantees no dns leaks)
sudo apt install -y wireguard dnsmasq-base
# Copy the config
sudo cp ~/Documents/secrets/wireguard/extra.conf /etc/wireguard/extra.conf
```

Launching applications through VPN:

```bash
# Test the connection
sudo vpn -t 
# Run curl with vpn
sudo vpn curl ifconfig.me
# Run discord with vpn
sudo vpn -g vesktop
# See the help
sudo vpn --help
```

Some good resources on vpnizing applications:

- [Run firefox within net namespace](https://gist.github.com/larsch/9fe268026ef55796c182e7c67de91fc4)
- [Run net namespace with internet](https://gist.github.com/dpino/6c0dca1742093346461e11aa8f608a99)
- [proxychains-ng](https://github.com/rofl0r/proxychains-ng) (only tcp)
- [tun2socks](https://github.com/xjasonlyu/tun2socks) (only tcp)
- [Proxy-ns](https://github.com/OkamiW/proxy-ns) (proxychains with udp) 
- [socks5 with discord](https://gist.github.com/mzpqnxow/ca4b4ae0accf2d3b275537332ccbe86e) (doesn't seem to work for udp)
- [wireguard namespacing](https://www.wireguard.com/netns/)

### Arch

#### changeVolume.sh

Used by hyprland to send a beep and a dunst notification on fn-key volume change,
but I think it can be launched on ubuntu too but for what?

#### hypr_lockscreen.sh [BROKEN]

Experimental screensaver on hyprlocker
