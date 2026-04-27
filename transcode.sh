#!/usr/bin/env bash
# transcode.sh
# Converts audio files to 192k CBR MP3s.
# Mirrors the source folder structure in the output directory.
#
# Usage:
#   ./transcode.sh [options] [input_dir] [output_dir]
#
# Options:
#   --replace    Convert files in-place, replacing originals (no output_dir needed)
#   -h, --help   Show this help
#
# Examples:
#   ./transcode.sh                        # input/ -> output/
#   ./transcode.sh music/ converted/      # music/ -> converted/
#   ./transcode.sh --replace music/       # convert music/ in-place

set -euo pipefail

# --- Defaults ---------------------------------------------------------
INPUT_DIR="input"
OUTPUT_DIR="output"
REPLACE=false
BITRATE="192k"
SAMPLE_RATE="44100"
CHANNELS="2"
MAX_FILENAME_LEN=64
# ----------------------------------------------------------------------

# Colours
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

log()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

usage() {
  sed -n '/^#!/d; /^#/!q; s/^# \{0,1\}//p' "$(readlink -f "$0")"
  exit 0
}

# --- Arg parsing ------------------------------------------------------
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --replace) REPLACE=true ;;
    -h|--help) usage ;;
    -*) err "Unknown option: $arg"; exit 1 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

if [[ ${#POSITIONAL[@]} -ge 1 ]]; then INPUT_DIR="${POSITIONAL[0]}"; fi
if [[ ${#POSITIONAL[@]} -ge 2 ]]; then OUTPUT_DIR="${POSITIONAL[1]}"; fi

# --- Filename sanitiser -----------------------------------------------
sanitise_filename() {
  local name="$1"
  local ext="${name##*.}"
  local stem="${name%.*}"

  # Attempt ASCII transliteration
  local ascii
  ascii=$(echo "$stem" | iconv -f UTF-8 -t ASCII//TRANSLIT//IGNORE 2>/dev/null || echo "")
  ascii=$(echo "$ascii" | tr -cs 'A-Za-z0-9._-' '_' | sed 's/__*/_/g; s/^[_-]*//; s/[_-]*$//')

  # If transliteration ate more than half the stem, keep unicode instead
  if (( ${#ascii} * 2 < ${#stem} )); then
    stem=$(echo "$stem" | sed 's/[\\/:*?"<>|&]/_/g; s/[[:cntrl:]]//g' | tr ' ' '_')
    stem=$(echo "$stem" | sed 's/__*/_/g; s/^[_-]*//; s/[_-]*$//')
  else
    stem="$ascii"
  fi

  local max_stem=$(( MAX_FILENAME_LEN - ${#ext} - 1 ))
  stem="${stem:0:$max_stem}"

  echo "${stem}.${ext}"
}

# --- Pre-flight checks ------------------------------------------------
if ! command -v ffmpeg &>/dev/null; then
  err "ffmpeg not found. Install it and try again."
  exit 1
fi

if [[ ! -d "$INPUT_DIR" ]]; then
  err "Source directory '$INPUT_DIR' does not exist."
  exit 1
fi

if [[ "$REPLACE" == false ]]; then
  mkdir -p "$OUTPUT_DIR"
fi

# --- Scan for files ---------------------------------------------------
mapfile -d '' files < <(
  find "$INPUT_DIR" -type f \( \
    -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' -o \
    -iname '*.aac' -o -iname '*.ogg' -o -iname '*.wav' -o \
    -iname '*.wma' \) -print0 | sort -z
)

total=${#files[@]}

if (( total == 0 )); then
  warn "No supported audio files found in '$INPUT_DIR'."
  exit 0
fi

echo -e "\n${BOLD}Audio Transcoder${RESET}"
echo -e "  Source  : $INPUT_DIR"
if [[ "$REPLACE" == true ]]; then
  echo -e "  Mode    : ${RED}replace in-place${RESET}"
else
  echo -e "  Output  : $OUTPUT_DIR (mirroring folder structure)"
fi
echo -e "  Files   : $total"
echo -e "  Bitrate : $BITRATE CBR  |  ${SAMPLE_RATE} Hz  |  ${CHANNELS}ch  |  No ID3v2\n"

if [[ "$REPLACE" == true ]]; then
  echo -e "${YELLOW}WARNING: originals will be permanently replaced. Ctrl-C to abort.${RESET}"
  sleep 3
fi

# --- Convert ----------------------------------------------------------
converted=0
skipped=0
failed=0

for f in "${files[@]}"; do
  rel="${f#"${INPUT_DIR}"/}"

  if [[ "$REPLACE" == true ]]; then
    # In-place: convert to a temp file alongside the original, then swap
    tmp="${f%.*}.tmp.mp3"
    out="$f"
  else
    # Mirror structure: sanitise each path component individually
    safe_rel=""
    while IFS= read -r part; do
      safe_part=$(sanitise_filename "$part")
      safe_rel="${safe_rel:+${safe_rel}/}${safe_part}"
    done < <(echo "$rel" | tr '/' '\n')

    tmp=""
    out="${OUTPUT_DIR}/${safe_rel%.*}.mp3"

    # Warn if filename changed
    if [[ "$(basename "$rel")" != "$(basename "$safe_rel")" ]]; then
      warn "Renamed: '$(basename "$rel")' -> '$(basename "$safe_rel")'"
    fi

    # Skip if output already up to date
    if [[ -f "$out" && "$out" -nt "$f" ]]; then
      warn "Skip (up to date): $rel"
      (( skipped++ )) || true
      continue
    fi

    mkdir -p "$(dirname "$out")"
  fi

  log "Converting: $rel"

  ffmpeg_out="${tmp:-$out}"

  if ffmpeg -nostdin -y -i "$f" \
      -map 0:a:0 -vn -sn -dn \
      -c:a libmp3lame \
      -b:a "$BITRATE" \
      -ar "$SAMPLE_RATE" \
      -ac "$CHANNELS" \
      -map_metadata -1 \
      -map_chapters -1 \
      -id3v2_version 0 \
      -write_id3v1 0 \
      -write_xing 0 \
      "$ffmpeg_out" \
      2>/dev/null
  then
    if [[ "$REPLACE" == true ]]; then
      mv "$ffmpeg_out" "$out"
    fi
    ok "Done: $out"
    (( converted++ )) || true
  else
    err "Failed: $f"
    rm -f "$ffmpeg_out"
    (( failed++ )) || true
  fi
done

# --- Summary ----------------------------------------------------------
echo -e "\n${BOLD}Summary${RESET}"
echo -e "  ${GREEN}Converted : $converted${RESET}"
echo -e "  ${YELLOW}Skipped   : $skipped${RESET}"
(( failed > 0 )) && echo -e "  ${RED}Failed    : $failed${RESET}"
echo

(( failed > 0 )) && exit 1 || exit 0

### Old version
# # Convert mp3 from /tracks folder to /car files
# find tracks -type f \( \
#   -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' -o \
#   -iname '*.aac' -o -iname '*.ogg' -o -iname '*.wav' -o \
#   -iname '*.wma' \) -print0 |
# while IFS= read -r -d '' f; do
#   rel="${f#tracks/}"
#   out="car/${rel%.*}.mp3"
#   mkdir -p "$(dirname "$out")"
#
#   ffmpeg -nostdin -y -i "$f" \
#     -map 0:a:0 -vn -sn -dn \
#     -c:a libmp3lame -b:a 192k -ar 44100 -ac 2 \
#     -map_metadata -1 -map_chapters -1 \
#     -id3v2_version 3 -write_id3v1 1 -write_xing 0 \
#     "$out"
# done


