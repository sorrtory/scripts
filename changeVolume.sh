#!/bin/bash
# changeVolume


# OLD + alsa
# https://wiki.archlinux.org/title/Dunst#Using_dunstify_as_volume/brightness_level_indicator

# Pipewire
# https://github.com/ericmurphyxyz/dotfiles/blob/master/.local/bin/volume


# install sudo pacman -S elementary-icon-theme && yay -S faba-icon-theme
ICON_THEME_PATH=/usr/share/icons/Faba/48x48/notifications/notification-audio

# Increment, decrement, or mute the volume using Pipewire and send a notification

case $1 in
	up)
		# Set the volume on (if it was muted)
		wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
		wpctl set-volume -l 2.0 @DEFAULT_AUDIO_SINK@ 5%+
		;;
	down)
		wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
		wpctl set-volume -l 2.0 @DEFAULT_AUDIO_SINK@ 5%-
		;;
	mute)
		wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
		;;
esac

VOLUME=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | tr -dc '0-9' | sed 's/^0\{1,2\}//')

send_notification() {

	if [ "$1" = "mute" ]; then ICON="muted"; elif [ "$VOLUME" -lt 33 ]; then ICON="low"; elif [ "$VOLUME" -lt 66 ]; then ICON="medium"; else ICON="high"; fi
	if [ "$1" = "mute" ]; then TEXT="Currently muted"; else TEXT="Currently at ${VOLUME}%"; fi

	dunstify -a "Volume" -r 9993 -h int:value:"$VOLUME" -i "$ICON_THEME_PATH-volume-$ICON.svg" "Volume" "$TEXT" -t 2000
}

case $1 in
	mute)
		case "$(wpctl get-volume @DEFAULT_AUDIO_SINK@)" in
			*MUTED* ) send_notification mute;;
			*       ) send_notification;;
		esac;;
	*)
		send_notification;;
esac

# Play the volume changed sound
canberra-gtk-play -i audio-volume-change -d "changeVolume"
