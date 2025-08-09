#!/bin/bash

VIDEO="/home/z/Pictures/Wallpapers/musashi.mp4"

# Move mpv to a special workspace for lockscreen
# hyprctl dispatch workspace special:lockscreen

# Start mpv in fullscreen, looped, borderless
mpv --loop --no-border --fullscreen --background-color=0/0 --background=none --cursor-autohide=always --no-osc "$VIDEO" &
MPV_PID=$!

sleep 1

hyprlock
# Small delay to ensure mpv is visible before locking

# Run Hyprlock
#hyprlock

# Kill mpv once unlocked
kill $MPV_PID
