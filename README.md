# Scripts

<p>
I wrote them because I was bored and silly a little like
<img src="https://styles.redditmedia.com/t5_5x81u7/styles/communityIcon_t8en21sthsja1.jpg?width=128&frame=1&auto=webp&s=e541baf4fe498485bf557d8ba6b6fce82d497039" alt="r/silltcats" width="25" height="25">
</p>

To easily access scripts I like to softlink them inside the bin folder:
I also wrote [`link.sh`](#linksh--bootstrap) to simplify this.

```bash
# e.g. lofi.sh to run it anywhere I want just with "lofi"
sudo ln -s $(pwd)/lofi.sh /usr/local/bin/lofi
```

## Description

All script are likely to be easy to update, because configuration is always at the heading

| Tag       | Meaning                             |
| --------- | ----------------------------------- |
| Vibe      | Funny silly scripts                 |
| Bootstrap | Setup or initialization scripts     |
| Util      | Utility scripts for file operations |
| Arch      | Scripts specific to Arch Linux      |

### Vibe

#### lofi.sh

Launch a lofi girl from the console via mpv.

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

#### block-vk-feed.js

I used to add this script to my ublock config using [this](https://alex.balgavy.eu/org-roam/20220606184728-injecting-js-with-ublock-origin/)
approach (you can find an example [here](https://github.com/pixeltris/TwitchAdSolutions?tab=readme-ov-file#applying-a-script-ublock-origin) too).

But here is a a quote from devs of the TwitchAdSolutions devs

> The scripts may randomly stop being applied by uBlock Origin for unknown reasons (#200). It's recommended to use the userscript versions instead.

So I ended up switching to Tampermonkey to launch my user script.

### Bootstrap

#### bootstrap.sh

Convenient way to execute the following bootsrap scripts.
Basically it updates the Ubuntu, clone whole scripts,
clone secrets using pastebin-shared PAT, cleans up and check the system.

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/sorrtory/scripts/refs/heads/master/bootstrap.sh)"
# OR with some help of short.io
bash -c "$(wget -qO- https://go.sorrtory.ru/bootstrap.sh)"
```

#### get_secrets.sh

Download byte data from pastebin, decrypts with a passpharase.
The result is intended to be a PAT for github secrets repo, so it clones it

#### link.sh

Help to create a symlink to configuration files, etc. \
Can do backups on filename collision. \
Create a softlink like "\<from> [\<to>]"

Can be used with --dry, --bin (cuts extension for scripts), --home.

See `./link.sh --help`

#### install.sh

> `get_secrets.sh` should probably be used at first

Read settings from `install.conf` and autoinstall tons of ubuntu software.
Has some features like starting a lxd+wireguard container and adding it to firefox proxy conf,
setting up ssh key for system, installation checks, linking configs (using `link.sh`),
gnome configuration (for my preferences)

See `./install.sh --help`

##### Improvements

I want a general install script like whether on ubuntu/arch just `install code`
and this script detects distro and selects the installation process automatically

### Utils

#### sharekey.sh

Encrypt the file with a passphrase, share on pastebin as unlisted for 10 mins,
let to download and delete it.

#### download_m3u.sh

Convert m3u files into mp3 files by downloading them with yt-dlp.

#### cutname.sh

Trim the specified string of the files' name STARTING FROM THE END within a directory

### Arch

#### changeVolume.sh

Used by hyprland to send a beep and a dunst notification on fn-key volume change,
but I think it can be launched on ubuntu too but for what?

#### hypr_lockscreen.sh [BROKEN]

Experimental screensaver on hyprlocker
