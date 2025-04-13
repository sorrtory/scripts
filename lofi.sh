#!/bin/bash

LOFILINK="https://www.youtube.com/live/jfKfPfyJRdk?si=25QycM8bL7aZSu5z"

# Hardcoded proxy. Hello from Russia
USE_PROXY=false
PROXY="http://10.243.177.254:3128"

# Options for requesters
YTDL_OPTS=""
CURL_OPTS="--silent --head --connect-timeout 3"

# Parse options
while getopts "P" opt; do
  case $opt in
    P)
      USE_PROXY=true
      ;;
    *)
      echo "Usage: $0 [-P] <YouTube_URL>"
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1))

# Set proxy options if needed
if $USE_PROXY; then
  YTDL_OPTS="--ytdl-raw-options=proxy=$PROXY"
  CURL_OPTS+=" --proxy $PROXY"
fi


# Check link
#lofi_ip=$(echo "$LOFILINK" | sed -E 's#https?://(www\.)?([^/]+).*#\2#')
#
#if [ $(dig +short $lofi_ip | head -n 1) == "127.0.0.1" ]; then
#    echo "Youtube is unavailable!"
#    exit 1
#fi

# Test connection to YouTube
echo "Checking YouTube availability..."
if ! curl $CURL_OPTS https://www.youtube.com/ > /dev/null; then
  echo "❌ Error: Cannot reach YouTube."
  echo "Try to use proxy with [-P]"
  exit 1
fi

echo "✅ Nice: YouTube responses"


# Spinner animation
spinner() {
  local chars="/-\|"
  local phrases=("Girl's loading..." "Lofiing..." "Loading...")
  local text=${phrases[$((RANDOM % ${#phrases[@]}))]}
  printf "$text"
  tput civis
  trap "tput cnorm" EXIT
  while true; do
    for (( i=0; i<${#chars}; i++ )); do
      width=$(( $(tput cols) - ${#text} - 3))
      printf "\r$text%*s" $width "[${chars:$i:1}]"
      sleep 0.2
    done
  done
}

# Function to handle Ctrl+C
function handle_interrupt() {
    echo -e "\nLoFi next time!"
    stty echo
    exit 1
}

trap handle_interrupt SIGINT

stty -echo
# Run the spinner in the background
spinner &
LOADING_PID=$!

# Launch mpv
# Probably need --cookies (get with --cookies-from-browser) and --no-warn to yt-dlp config

# Set the proxy option if needed

mpv $YTDL_OPTS --no-border --no-osc --geometry=40% --quiet --term-playing-msg="PLAYING" "$LOFILINK" > /tmp/lofi_mpv_output.log 2>&1 &


MPV_PID=$!

while ! grep -q "PLAYING" /tmp/lofi_mpv_output.log; do
    sleep 1
done

# Stop the spinner
kill $LOADING_PID
wait $LOADING_PID 2>/dev/null

# Cleanup and exit
rm /tmp/lofi_mpv_output.log
cat='
   /\\_/\\
  ( o.o )  ~♪
  > ^ <
  /|\\||\\
 // \\  \\   '
coffee='
  ( (
   ) )
 ........
 |      |]
 `------''\'''

arts_array=("$cat" "$coffee")
random_index=$((RANDOM % ${#arts_array[@]}))
printf "\r%*s" $(tput cols) " "
tput el
tput cuu 1
echo "${arts_array[$random_index]}"
stty echo
exit 0

