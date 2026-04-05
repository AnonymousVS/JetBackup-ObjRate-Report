#!/bin/bash
# ============================================================================
# JetBackup Object Rate Report
# Estimate S3 object upload rate per cPanel account from JetBackup 5 queue logs
#
# Repository : https://github.com/AnonymousVS/JetBackup-ObjRate-Report
# Install to : /usr/local/sbin/jetbackup-obj-report.sh
# Usage      : jetbackup-obj-report.sh              (all logs)
#              jetbackup-obj-report.sh today         (today only)
#              jetbackup-obj-report.sh yesterday     (yesterday only)
#              jetbackup-obj-report.sh 2026-04-04    (specific date)
# ============================================================================

OBJ_PER_SEC=1400
QUEUE_DIR="/usr/local/jetapps/var/log/jetbackup5/queue"
TMPFILE=$(mktemp)
SORTEDFILE=$(mktemp)

# --- Colors ---
BOLD="\033[1m"
CYAN="\033[36m"
YELLOW="\033[33m"
GREEN="\033[32m"
DIM="\033[2m"
RESET="\033[0m"

# --- Calculated rates ---
OBJ_PER_MIN=$((OBJ_PER_SEC * 60))
OBJ_PER_HOUR=$((OBJ_PER_SEC * 3600))

# --- Date filter ---
FILTER_DATE=""
FILTER_LABEL="All logs"

if [ -n "$1" ]; then
    case "$1" in
        today)
            FILTER_DATE=$(TZ='Asia/Bangkok' date '+%d/%b/%Y')
            FILTER_LABEL="Today ($(TZ='Asia/Bangkok' date '+%d %b %Y'))"
            ;;
        yesterday)
            FILTER_DATE=$(TZ='Asia/Bangkok' date -d '-1 day' '+%d/%b/%Y')
            FILTER_LABEL="Yesterday ($(TZ='Asia/Bangkok' date -d '-1 day' '+%d %b %Y'))"
            ;;
        *)
            FILTER_DATE=$(TZ='Asia/Bangkok' date -d "$1" '+%d/%b/%Y' 2>/dev/null)
            if [ -z "$FILTER_DATE" ]; then
                echo "Error: Invalid date format. Use: YYYY-MM-DD, today, or yesterday"
                exit 1
            fi
            FILTER_LABEL="$1"
            ;;
    esac
fi

echo ""
echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║${RESET}  ${BOLD}BACKUP REPORT${RESET} — $(hostname) — $(TZ='Asia/Bangkok' date '+%d %b %Y %H:%M')"
echo -e "${BOLD}${CYAN}╠════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}${CYAN}║${RESET}  Filter: ${BOLD}$FILTER_LABEL${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "${BOLD} Date         │ Account            │ Start │ End   │ Duration │  Est.Objects │    obj/hour │  obj/min │ obj/sec${RESET}"
echo -e "${DIM}──────────────┼────────────────────┼───────┼───────┼──────────┼──────────────┼─────────────┼──────────┼────────${RESET}"

TOTAL_SEC=0
TOTAL_OBJ=0
COUNT=0

for LOG in "${QUEUE_DIR}"/*.log; do
    [ ! -f "$LOG" ] && continue

    ACC=$(grep 'Transferring account' "$LOG" 2>/dev/null | tail -1 | sed 's/.*account "\([^"]*\)".*/\1/')
    [ -z "$ACC" ] && continue

    START=$(grep 'Syncing.*homedir' "$LOG" 2>/dev/null | tail -1 | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2}')
    END=$(grep 'Backup Completed' "$LOG" 2>/dev/null | tail -1 | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2}')

    [ -z "$START" ] || [ -z "$END" ] && continue

    if [ -n "$FILTER_DATE" ]; then
        END_DATE=$(echo "$END" | grep -oP '\d{2}/\w+/\d{4}')
        [ "$END_DATE" != "$FILTER_DATE" ] && continue
    fi

    START_EP=$(date -d "$(echo "$START" | sed 's|/| |g')" +%s 2>/dev/null)
    END_EP=$(date -d "$(echo "$END" | sed 's|/| |g')" +%s 2>/dev/null)

    [ -z "$START_EP" ] || [ -z "$END_EP" ] && continue

    DURATION=$((END_EP - START_EP))
    [ "$DURATION" -le 0 ] && continue

    HOURS=$((DURATION / 3600))
    MINS=$(( (DURATION % 3600) / 60 ))
    EST_OBJ=$((OBJ_PER_SEC * DURATION))

    DATE_TH=$(TZ='Asia/Bangkok' date -d @"$END_EP" '+%Y-%m-%d')
    START_TH=$(TZ='Asia/Bangkok' date -d @"$START_EP" '+%H:%M')
    END_TH=$(TZ='Asia/Bangkok' date -d @"$END_EP" '+%H:%M')

    printf "%s|%s| %-12s │ %-18s │ %5s │ %5s │ %4dh%02dm │ %'12d │ %'11d │ %'8d │ %'7d\n" \
        "$DATE_TH" "$ACC" "$DATE_TH" "$ACC" "$START_TH" "$END_TH" "$HOURS" "$MINS" \
        "$EST_OBJ" "$OBJ_PER_HOUR" "$OBJ_PER_MIN" "$OBJ_PER_SEC" >> "$TMPFILE"

    TOTAL_SEC=$((TOTAL_SEC + DURATION))
    TOTAL_OBJ=$((TOTAL_OBJ + EST_OBJ))
    COUNT=$((COUNT + 1))
done

# Sort: date desc, then account asc
sort -t'|' -k1,1r -k2,2 "$TMPFILE" | cut -d'|' -f3- > "$SORTEDFILE"

# Print with alternating colors per date group + separator
PREV_DATE=""
COLOR_IDX=0
COLORS=("$CYAN" "$YELLOW")

while IFS= read -r LINE; do
    CURRENT_DATE=$(echo "$LINE" | awk -F'│' '{print $1}' | xargs)

    if [ "$CURRENT_DATE" != "$PREV_DATE" ]; then
        if [ -n "$PREV_DATE" ]; then
            echo -e "${DIM}──────────────┼────────────────────┼───────┼───────┼──────────┼──────────────┼─────────────┼──────────┼────────${RESET}"
        fi
        COLOR_IDX=$(( (COLOR_IDX + 1) % 2 ))
        PREV_DATE="$CURRENT_DATE"
    fi

    echo -e "${COLORS[$COLOR_IDX]}${LINE}${RESET}"
done < "$SORTEDFILE"

rm -f "$TMPFILE" "$SORTEDFILE"

echo -e "${DIM}──────────────┼────────────────────┼───────┼───────┼──────────┼──────────────┼─────────────┼──────────┼────────${RESET}"

T_HR=$((TOTAL_SEC / 3600))
T_MIN=$(( (TOTAL_SEC % 3600) / 60 ))

printf -v TOTAL_LINE " %-12s │ %-18s │ %5s │ %5s │ %4dh%02dm │ %'12d │ %'11d │ %'8d │ %'7d" \
    "" "TOTAL ($COUNT)" "" "" "$T_HR" "$T_MIN" "$TOTAL_OBJ" "$OBJ_PER_HOUR" "$OBJ_PER_MIN" "$OBJ_PER_SEC"
echo -e "${BOLD}${GREEN}${TOTAL_LINE}${RESET}"

echo ""
echo -e " Base rate: ${BOLD}$OBJ_PER_SEC obj/s${RESET} (from live test)"
echo -e " obj/min: ${BOLD}$(printf "%'d" $OBJ_PER_MIN)${RESET} │ obj/hour: ${BOLD}$(printf "%'d" $OBJ_PER_HOUR)${RESET}"
echo -e " Source: ${DIM}JetBackup queue logs${RESET}"
echo ""
