# Scripts

I wrote them because I was bored and sillyb a little like

<p>
<img src="https://styles.redditmedia.com/t5_5x81u7/styles/communityIcon_t8en21sthsja1.jpg?width=128&frame=1&auto=webp&s=e541baf4fe498485bf557d8ba6b6fce82d497039" alt="r/silltcats" width="64" height="64" style="border-radius: 50%;">
</p>

To easily access scripts I like to softlink them inside the bin folder:

```bash
# e.g. lofi.sh to run it anywhere I want just with "lofi"
sudo ln -s $(pwd)/lofi.sh /usr/local/bin/lofi
```

See also [`link.sh`](#linksh--bootstrap) for this.

## Description

All script are likely to be easy to update, because configuration is always at the heading

| Tag       | Meaning                             |
| --------- | ----------------------------------- |
| Vibe      | Funny silly scripts                 |
| Bootstrap | Setup or initialization scripts     |
| Util      | Utility scripts for file operations |
| Arch      | Scripts specific to Arch Linux      |

### lofi.sh | Vibe

Launch a lofi girl from the console via mpv.

### commit_info.sh | Vibe

Show usefull info about commits including commit size and nice output in general.

### get_secrets.sh | Bootstrap

Download byte data from pastebin, automate the decryption process.
The result is intended to be a PAT for github secrets repo, so it clones it

### link.sh | Bootstrap

Help to create symnlinks to configuration files, etc.

### install.sh | Bootstrap

> `get_secrets.sh` should probably be used at first

Read settings from install.conf and autoinstall tons of ubuntu software.
Has some features like starting a lxd+wireguard container and adding it to firefox proxy conf,
setting up ssh key for system, installation checks, linking configs (using link.sh),
gnome configuration (for my preferences)

### sharekey.sh | Util

Encrypt the file with a passphrase, share on pastebin as unlisted for 10 mins,
let to download and delete it.

### download_m3u.sh | Util

Convert m3u files into mp3 files by downloading them with yt-dlp.

### cutname.sh | Util

Trim the specified string of the files' name STARTING FROM THE END within a directory

### changeVolume.sh | Arch

Used by hyprland to send a beep and a dunst notification on fn-key volume change,
but I think it can be launched on ubuntu too but for what?

### hypr_lockscreen.sh [BROKEN] | Arch

Experimental screensaver on hyprlocker
