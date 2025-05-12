#!/bin/bash

# Git Commit Stats Script
# Based on: https://gist.github.com/kobake/ef0a18a5b9dfc639819e19c3b0f49e05

# ANSI color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[0;35m"
BLUE="\033[1;34m"
WHITE="\033[1;37m"
BOLD="\033[1m"
RESET="\033[0m"

NO_COLOR=false
TABLE_MODE=false

MIN_INFO_SEPARATOR="\n " # or |

disable_colors() {
    RED=""; GREEN=""; CYAN=""; YELLOW=""; MAGENTA=""; BLUE=""; WHITE=""; BOLD=""; RESET=""
}

print_help() {
    echo -e "${BOLD}Git Commit Stats Script${RESET}"
    echo -e "${CYAN}Usage:${RESET} $0 [options]"
    echo ""
    echo -e "${YELLOW}Options:${RESET}"
    echo -e "  -h              Show this help message"
    echo -e "  -l [n]          Show latest n commits (default: 3 if -l is used without n)"
    echo -e "  -n [n]          Show the n-th commit before HEAD (default: 1 if used without n)"
    echo -e "  -A              Show all commits"
    echo -e "  -S              Show repository size, commit count, and directory size"
    echo -e "  -a HASH         Show specific commit by hash"
    echo -e "  --min            Minimal mode"
    echo -e "  --table         Table compact output mode"
    echo -e "  -d              Include date in minimal mode"
    echo -e "  -f              Include file modifications in minimal mode"
    echo -e "  -s              Include commit size stats in minimal mode"
    echo -e "  -dfsA           Combine any flags (minimal mode implied)"
    echo -e "  --no-color      Disable color output"
    exit 0
}

human_size() {
    local size=$1
    awk 'function human(x) {
        s="BKMGT"; while (x>=1024 && length(s)>1) {x/=1024; s=substr(s,2)}
        return sprintf("%.1f%s", x, substr(s,1,1))
    }
    BEGIN { print human('$size') }'
}

print_repo_stats() {
    local stats
    stats=$(git count-objects -vH)
    echo -e "${BOLD}Repository Size Stats:${RESET}"
    echo "$stats" | while IFS= read -r line; do
        printf "  %s\n" "$line"
    done
    echo -e "${BOLD}Working Directory:${RESET} $(pwd)"
    echo -e "${BOLD}.git Size:${RESET} $(du -sh .git 2>/dev/null | cut -f1)"
    echo -e "${BOLD}Total Repository Size:${RESET} $(du -sh . 2>/dev/null | cut -f1)"
    echo -e "${BOLD}Total Commits:${RESET} $(git rev-list --count HEAD)"
}

print_commit_stats() {
    local HASH=$1
    local DIST=$2
    local MINIMAL=$3
    local OPT_DATE=$4
    local OPT_FILES=$5
    local OPT_STATS=$6

    local RAW_DATE AUTHOR MESSAGE SIZE FILES
    RAW_DATE=$(git show -s --format="%ci" "$HASH")
    AUTHOR=$(git show -s --format="%an" "$HASH")
    MESSAGE=$(git show -s --format="%s" "$HASH")

    local ITEM_LIST BLOB_HASH_LIST SIZE_LIST COMMIT_SIZE
    ITEM_LIST="$(git diff-tree -r -c -M -C --no-commit-id "$HASH")"
    BLOB_HASH_LIST="$(echo "$ITEM_LIST" | awk '{ print $4 }')"
    SIZE_LIST="$(echo "$BLOB_HASH_LIST" | git cat-file --batch-check | grep "blob" | awk '{ print $3 }')"
    COMMIT_SIZE=$(echo "$SIZE_LIST" | awk '{ sum += $1 } END { print sum }')

    if [ "$MINIMAL" = true ]; then
        local SUMMARY=""
        if [ "$OPT_FILES" = true ]; then
            SUMMARY=$(git show --stat --oneline "$HASH" | tail -n +2 | awk '/\|/ {adds+=gsub(/\+/,"&"); dels+=gsub(/-/,"&")} END {printf "%s+%d%s  %s-%d%s  %s(%d)%s", "'"$BOLD$GREEN"'", adds, "'"$RESET"'", "'"$RED"'", dels, "'"$RESET"'", "'"$BLUE"'", adds+dels, "'"$RESET"'"}')
            SUMMARY=$(printf "${BOLD}Total${RESET}: %s" "$SUMMARY")
        fi
        printf "${CYAN}%-8s${RESET}  ${WHITE}%-30s${RESET}" "${HASH:0:8}" "$MESSAGE"
        [ "$OPT_DATE" = true ] && printf "${MIN_INFO_SEPARATOR}${YELLOW}%s${RESET}" "$RAW_DATE"
        [ "$OPT_STATS" = true ] && printf "${MIN_INFO_SEPARATOR}${MAGENTA}%s${RESET}" "$(human_size $COMMIT_SIZE)"
        [ "$OPT_FILES" = true ] && printf "${MIN_INFO_SEPARATOR}%s" "${SUMMARY}"
        echo ""
        if [ "$OPT_DATE" = true ] || [ "$OPT_STATS" = true ] || [ "$OPT_FILES" = true ]; then
            echo "────────────────────────────"
        fi
    elif [ "$TABLE_MODE" = true ]; then
        echo -e "${WHITE}Commit:   ${RESET}${CYAN}$HASH${RESET}"
        echo -e "${CYAN}Hash${RESET}  ${WHITE}Message${RESET}  ${GREEN}Author${RESET}  ${YELLOW}Date${RESET}  ${MAGENTA}Size${RESET}"
        echo "────────────────────────────────────────────────────────────────────────────────"
        printf "${CYAN}%-8s${RESET}  ${WHITE}%-30s${RESET}  ${GREEN}%-20s${RESET}  ${YELLOW}%-20s${RESET}  ${MAGENTA}%-10s${RESET}\n" "$HASH" "$MESSAGE" "$AUTHOR" "$RAW_DATE" "$(human_size $COMMIT_SIZE)"
    else
        echo -e "${WHITE}Commit:   ${RESET}${CYAN}$HASH${RESET}"
        echo -e "Message:  ${WHITE}$MESSAGE${RESET}"
        echo -e "Name:     ${GREEN}$AUTHOR${RESET}"
        echo -e "Date:     ${YELLOW}$RAW_DATE${RESET}"
        echo -e "Size:     ${MAGENTA}$(human_size $COMMIT_SIZE)${RESET}"
        print_commit_files "$HASH" true
        echo "────────────────────────────"
    fi
}

print_commit_files() {
    local HASH=$1
    local SHOW_TOTAL=$2
    local FILE_STATS FILE
    FILE_STATS=$(git show --stat --oneline "$HASH" | tail -n +2 | sed '/^ [0-9]* file[s]* changed.*/d')

    [ -z "$FILE_STATS" ] && return

    local WIDTH=0 TOTAL_ADDS=0 TOTAL_DELS=0
    echo -e "Files Modified:"

    while IFS= read -r LINE; do
        FILE=$(echo "$LINE" | cut -d '|' -f1 | sed 's/^ *//;s/ *$//')
        STATS=$(echo "$LINE" | cut -d '|' -f2)
        ADDS=$(echo "$STATS" | grep -o "+" | wc -l)
        DELS=$(echo "$STATS" | grep -o "-" | wc -l)
        TOTAL=$((ADDS + DELS))
        TOTAL_ADDS=$((TOTAL_ADDS + ADDS))
        TOTAL_DELS=$((TOTAL_DELS + DELS))
        [ "$TOTAL" -eq 0 ] && continue
        if [ ${#FILE} -gt 40 ]; then
            printf "  %-40s\n" "$FILE"
            FILE=""
        fi
        printf "  %-40s ${GREEN}+%3d${RESET}  ${RED}-%3d${RESET}  ${BLUE}(%d)${RESET}\n" "$FILE" "$ADDS" "$DELS" "$TOTAL"
    done <<< "$FILE_STATS"

    if [ "$SHOW_TOTAL" = true ]; then
        local TOTAL_SUM=$((TOTAL_ADDS + TOTAL_DELS))
        echo -e "${BOLD}Total:${RESET} ${GREEN}+${TOTAL_ADDS}${RESET}  ${RED}-${TOTAL_DELS}${RESET}  ${BLUE}(${TOTAL_SUM})${RESET}"
    fi
}

# Defaults
MINIMAL=false
OPT_DATE=false
OPT_FILES=false
OPT_STATS=false
SHOW_ALL=false
SHOW_REPO_STATS=false
COMMITS=()

i=1
while [ $i -le $# ]; do
    arg=${!i}
    case $arg in
        -h)
            print_help
            ;;
        -l)
            ((i++))
            next=${!i}
            if [[ "$next" =~ ^[0-9]+$ ]]; then
                COUNT=$next
            else
                COUNT=3
                ((i--))
            fi
            for ((j=0; j<COUNT; j++)); do COMMITS+=("HEAD~$j"); done
            ;;
        -n)
            ((i++))
            next=${!i}
            if [[ "$next" =~ ^[0-9]+$ ]]; then
                NTH=$next
            else
                NTH=1
                ((i--))
            fi
            COMMITS+=("HEAD~$NTH")
            ;;
        -a)
            ((i++))
            HASH=${!i}
            COMMITS+=($HASH)
            ;;
        -A)
            SHOW_ALL=true
            ;;
        -S)
            SHOW_REPO_STATS=true
            ;;
        --min)
            MINIMAL=true
            ;;
        --table)
            TABLE_MODE=true
            ;;
        --no-color)
            NO_COLOR=true
            ;;
        -*?)
            FLAGS=$(echo $arg | cut -c2-)
            for ((j=0; j<${#FLAGS}; j++)); do
                ch=${FLAGS:$j:1}
                case $ch in
                    d) OPT_DATE=true; MINIMAL=true;;
                    f) OPT_FILES=true; MINIMAL=true;;
                    s) OPT_STATS=true; MINIMAL=true;;
                    A) SHOW_ALL=true;;
                esac
            done
            ;;
    esac
    ((i++))
done

if [ "$NO_COLOR" = true ]; then
    disable_colors
fi

if [ "$SHOW_REPO_STATS" = true ]; then
    print_repo_stats
    exit 0
fi

if [ "${#COMMITS[@]}" -eq 0 ] && [ "$SHOW_ALL" = false ]; then
    COMMITS+=("HEAD")
fi

if [ "$SHOW_ALL" = true ]; then
    mapfile -t COMMITS < <(git rev-list --all)
fi

for COMMIT in "${COMMITS[@]}"; do
    HASH=$(git rev-parse "$COMMIT" 2>/dev/null)
    [ -z "$HASH" ] && echo "Invalid commit: $COMMIT" && continue

    if git merge-base --is-ancestor "$HASH" HEAD; then
        DIST=$(git rev-list --count "$HASH"..HEAD)
        DIST_TEXT="$DIST commit(s) behind HEAD"
    elif git merge-base --is-ancestor HEAD "$HASH"; then
        DIST=$(git rev-list --count HEAD.."$HASH")
        DIST_TEXT="$DIST commit(s) after HEAD"
    else
        DIST_TEXT="not related to HEAD"
    fi

    print_commit_stats "$HASH" "$DIST_TEXT" "$MINIMAL" "$OPT_DATE" "$OPT_FILES" "$OPT_STATS"
done
