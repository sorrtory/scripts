# Scripts
I wrote them because I was silly and bored a little
<p align="right">
    <img src="https://styles.redditmedia.com/t5_5x81u7/styles/communityIcon_t8en21sthsja1.jpg?width=128&frame=1&auto=webp&s=e541baf4fe498485bf557d8ba6b6fce82d497039" alt="r/silltcats" width="64" height="64" style="border-radius: 90%;">
</p>

To easily access scripts I like to softlink them to the bin folder:
```bash
# e.g. lofi.sh to run it anywhere I want just with "lofi"
sudo ln -s $(pwd)/lofi.sh /usr/local/bin/lofi
```
There is also `link.sh` script for it

# Description

## lofi.sh
Launch a lofi girl from the console via mpv.

## download_m3u.sh
Convert m3u files into mp3 files by downloading them with yt-dlp.

## commit_info.sh
Usefull info about commits including commit size and nice output in general.

## changeVolume.sh
Used by hyprland to send a beep and a dunst notification on fn-key volume change

## hypr_lockscreen.sh [BROKEN]
Experimental screensaver on hyprlocker

## cutname.sh
Trims the file name from the end with the specified string in a directory

## sharekey.sh
Encrypts the file with a passphrase, shares on pastebin as unlisted for 10 mins, 
lets to download and delete it.