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
#
# Objects source:
#   JetBackup API total_files (real object count from queue)
#   Shows - when API data is not available
# ============================================================================

QUEUE_DIR="/usr/local/jetapps/var/log/jetbackup5/queue"
TMPFILE=$(mktemp)
SORTEDFILE=$(mktemp)
ADDON_CACHE=$(mktemp)
API_CACHE=$(mktemp)

# --- Colors ---
BOLD="\033[1m"
CYAN="\033[36m"
YELLOW="\033[33m"
GREEN="\033[32m"
DIM="\033[2m"
RED="\033[31m"
RESET="\033[0m"

# --- Fetch JetBackup settings from API ---
fetch_jb_settings() {
    local PERF RESOURCE DEST

    PERF=$(jetbackup5api -F getSettingsPerformance -O json 2>/dev/null)
    RESOURCE=$(jetbackup5api -F getSettingsResource -O json 2>/dev/null)
    DEST=$(jetbackup5api -F listDestinations -O json 2>/dev/null)

    python3 -c "
import sys,json

perf=json.loads('''$PERF''')
resource=json.loads('''$RESOURCE''')
dest=json.loads('''$DEST''')

p=perf.get('data',{})
r=resource.get('data',{})

backup_forks=p.get('backup_forks',0)
system_forks=p.get('system_forks',0)
queueable_forks=p.get('queueable_forks',0)
extension_forks=p.get('extension_forks',0)
cpu_limit=r.get('cpu_limit',0)

threads=0
dest_name=''
for d in dest.get('data',{}).get('destinations',[]):
    if d.get('type')=='S3':
        threads=d.get('threads',0)
        dest_name=d.get('name','')
        break

total_forks=backup_forks+system_forks+queueable_forks
threads_per_fork=threads//total_forks if total_forks>0 else 0

cpu_str='Unlimited' if cpu_limit==0 else f'{cpu_limit}%'

print(f'{cpu_str}|{backup_forks}|{system_forks}|{queueable_forks}|{extension_forks}|{threads}|{total_forks}|{threads_per_fork}|{dest_name}')
" 2>/dev/null
}

# --- Count addon domains per account ---
if [ -f /etc/trueuserdomains ] && [ -f /etc/userdomains ]; then
    awk -F': ' '
      NR==FNR { main[$1]=1; next }
      $1=="*" || $2=="nobody" || $1~/.cp$/ { next }
      $1 in main { next }
      {
        skip=0
        for(m in main) { if($1 ~ "\\."m"$") { skip=1; break } }
        if(!skip) count[$2]++
      }
      END { for(c in count) print c, count[c] }
    ' /etc/trueuserdomains /etc/userdomains > "$ADDON_CACHE"
fi

get_addon_count() {
    local acc="$1"
    local cnt
    cnt=$(awk -v a="$acc" '$1==a {print $2}' "$ADDON_CACHE")
    echo "${cnt:-0}"
}

# --- Fetch total_files from JetBackup API (cached per account) ---
fetch_api_objects() {
    for GID in $(jetbackup5api -F listQueueGroups -D "type=1&limit=50" -O json 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d.get('data',{}).get('groups',[]):
    print(g['_id'])
" 2>/dev/null); do
        jetbackup5api -F listQueueItems -D "group_id=$GID" -O json 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for item in d.get('data',{}).get('items',[]):
    acc=item.get('data',{}).get('account','')
    tf=item.get('progress',{}).get('total_files',0) if item.get('progress') else 0
    if acc and tf and tf>0:
        print(f'{acc} {tf}')
" 2>/dev/null
    done > "$API_CACHE"
}

get_api_objects() {
    local acc="$1"
    local cnt
    cnt=$(awk -v a="$acc" '$1==a {print $2}' "$API_CACHE")
    echo "${cnt:-0}"
}

# --- Fetch API data ---
echo -e " ${DIM}Fetching data from JetBackup API...${RESET}" >&2
JB_SETTINGS=$(fetch_jb_settings)
fetch_api_objects
echo -ne "\033[1A\033[2K" >&2

# Parse settings
IFS='|' read -r CPU_LIMIT BACKUP_FORKS SYSTEM_FORKS RESTORE_FORKS EXTENSION_FORKS MAX_THREADS TOTAL_FORKS THREADS_PER_FORK DEST_NAME <<< "$JB_SETTINGS"

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
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║${RESET}  ${BOLD}BACKUP REPORT${RESET} — $(hostname) — $(TZ='Asia/Bangkok' date '+%d %b %Y %H:%M')"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}${CYAN}║${RESET}  Filter: ${BOLD}$FILTER_LABEL${RESET}"
echo -e "${BOLD}${CYAN}║${RESET}  Destination: ${BOLD}$DEST_NAME${RESET}"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}${CYAN}║${RESET}  CPU Limit: ${BOLD}$CPU_LIMIT${RESET}  │  Backup Tasks: ${BOLD}$BACKUP_FORKS${RESET}  │  System: ${BOLD}$SYSTEM_FORKS${RESET}  │  Restore: ${BOLD}$RESTORE_FORKS${RESET}  │  Extension: ${BOLD}$EXTENSION_FORKS${RESET}"
echo -e "${BOLD}${CYAN}║${RESET}  Max Threads: ${BOLD}$MAX_THREADS${RESET}  │  Total Forks: ${BOLD}$TOTAL_FORKS${RESET} (Backup+System+Restore)  │  Threads/Fork: ${BOLD}$THREADS_PER_FORK${RESET}  (${MAX_THREADS} ÷ ${TOTAL_FORKS})"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""

HEADER="${BOLD} Date         │ Account            │ Start │ End   │ Duration │    Objects │ Domains │  obj/sec │   obj/min │    obj/hour${RESET}"
SEPARATOR="${DIM}──────────────┼────────────────────┼───────┼───────┼──────────┼────────────┼─────────┼──────────┼───────────┼────────────${RESET}"

echo -e "$HEADER"
echo -e "$SEPARATOR"

TOTAL_SEC=0
TOTAL_OBJ=0
COUNT=0

for LOG in "${QUEUE_DIR}"/*.log; do
    [ ! -f "$LOG" ] && continue

    while IFS= read -r PID; do
        [ -z "$PID" ] && continue

        ACC=$(grep "\[PID $PID\]" "$LOG" 2>/dev/null | grep 'Transferring account' | tail -1 | sed 's/.*account "\([^"]*\)".*/\1/')
        [ -z "$ACC" ] && continue

        START=$(grep "\[PID $PID\]" "$LOG" 2>/dev/null | grep 'Syncing.*homedir' | tail -1 | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2} \+\d{4}')
        END=$(grep "\[PID $PID\]" "$LOG" 2>/dev/null | grep 'Backup Completed' | tail -1 | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2} \+\d{4}')

        [ -z "$START" ] || [ -z "$END" ] && continue

        if [ -n "$FILTER_DATE" ]; then
            END_BKK_DATE=$(TZ='Asia/Bangkok' date -d "$(echo "$END" | sed 's|/| |g')" '+%d/%b/%Y' 2>/dev/null)
            [ "$END_BKK_DATE" != "$FILTER_DATE" ] && continue
        fi

        START_EP=$(date -d "$(echo "$START" | sed 's|/| |g')" +%s 2>/dev/null)
        END_EP=$(date -d "$(echo "$END" | sed 's|/| |g')" +%s 2>/dev/null)

        [ -z "$START_EP" ] || [ -z "$END_EP" ] && continue

        DURATION=$((END_EP - START_EP))
        [ "$DURATION" -le 0 ] && continue

        HOURS=$((DURATION / 3600))
        MINS=$(( (DURATION % 3600) / 60 ))

        DATE_TH=$(TZ='Asia/Bangkok' date -d @"$END_EP" '+%Y-%m-%d')
        START_TH=$(TZ='Asia/Bangkok' date -d @"$START_EP" '+%H:%M')
        END_TH=$(TZ='Asia/Bangkok' date -d @"$END_EP" '+%H:%M')

        ADDONS=$(get_addon_count "$ACC")

        # Objects: API only, show - if unavailable
        API_OBJ=$(get_api_objects "$ACC")
        if [ "$API_OBJ" -gt 0 ] 2>/dev/null; then
            # Calculate rates
            if [ "$DURATION" -gt 0 ]; then
                OBJ_SEC=$(awk "BEGIN {printf \"%.0f\", $API_OBJ / $DURATION}")
                OBJ_MIN=$(awk "BEGIN {printf \"%.0f\", $API_OBJ / $DURATION * 60}")
                OBJ_HOUR=$(awk "BEGIN {printf \"%.0f\", $API_OBJ / $DURATION * 3600}")
            else
                OBJ_SEC=0
                OBJ_MIN=0
                OBJ_HOUR=0
            fi

            printf "%s|%s| %-12s │ %-18s │ %5s │ %5s │ %4dh%02dm │ %'10d │ %'7d │ %'8d │ %'9d │ %'10d\n" \
                "$DATE_TH" "$ACC" "$DATE_TH" "$ACC" "$START_TH" "$END_TH" "$HOURS" "$MINS" \
                "$API_OBJ" "$ADDONS" "$OBJ_SEC" "$OBJ_MIN" "$OBJ_HOUR" >> "$TMPFILE"

            TOTAL_OBJ=$((TOTAL_OBJ + API_OBJ))
        else
            printf "%s|%s| %-12s │ %-18s │ %5s │ %5s │ %4dh%02dm │          - │ %'7d │        - │         - │          -\n" \
                "$DATE_TH" "$ACC" "$DATE_TH" "$ACC" "$START_TH" "$END_TH" "$HOURS" "$MINS" \
                "$ADDONS" >> "$TMPFILE"
        fi

        TOTAL_SEC=$((TOTAL_SEC + DURATION))
        COUNT=$((COUNT + 1))

    done < <(grep 'Transferring account' "$LOG" 2>/dev/null | grep -oP 'PID \K[0-9]+' | sort -u)
done

# Sort: date asc, then account asc
sort -t'|' -k1,1 -k2,2 "$TMPFILE" | cut -d'|' -f3- > "$SORTEDFILE"

PREV_DATE=""
COLOR_IDX=0
COLORS=("$RESET" "$DIM")

while IFS= read -r LINE; do
    CURRENT_DATE=$(echo "$LINE" | awk -F'│' '{print $1}' | xargs)

    if [ "$CURRENT_DATE" != "$PREV_DATE" ]; then
        if [ -n "$PREV_DATE" ]; then
            echo -e "$SEPARATOR"
        fi
        COLOR_IDX=$(( (COLOR_IDX + 1) % 2 ))
        PREV_DATE="$CURRENT_DATE"
    fi

    echo -e "${COLORS[$COLOR_IDX]}${LINE}${RESET}"
done < "$SORTEDFILE"

rm -f "$TMPFILE" "$SORTEDFILE" "$ADDON_CACHE" "$API_CACHE"

echo -e "$SEPARATOR"

T_HR=$((TOTAL_SEC / 3600))
T_MIN=$(( (TOTAL_SEC % 3600) / 60 ))

if [ "$TOTAL_SEC" -gt 0 ]; then
    AVG_SEC=$(awk "BEGIN {printf \"%.0f\", $TOTAL_OBJ / $TOTAL_SEC}")
    AVG_MIN=$(awk "BEGIN {printf \"%.0f\", $TOTAL_OBJ / $TOTAL_SEC * 60}")
    AVG_HOUR=$(awk "BEGIN {printf \"%.0f\", $TOTAL_OBJ / $TOTAL_SEC * 3600}")
else
    AVG_SEC=0
    AVG_MIN=0
    AVG_HOUR=0
fi

printf -v TOTAL_LINE " %-12s │ %-18s │ %5s │ %5s │ %4dh%02dm │ %'10d │         │ %'8d │ %'9d │ %'10d" \
    "" "TOTAL ($COUNT)" "" "" "$T_HR" "$T_MIN" "$TOTAL_OBJ" "$AVG_SEC" "$AVG_MIN" "$AVG_HOUR"
echo -e "${BOLD}${GREEN}${TOTAL_LINE}${RESET}"

echo -e "$SEPARATOR"
echo -e "$HEADER"

echo ""
echo -e " Objects: ${BOLD}API total_files${RESET} from JetBackup queue │ ${DIM}-${RESET} = no data available from API"
echo -e " Rates:   Objects ÷ Duration"
echo -e " Domains: Addon domains from /etc/userdomains (excludes main domain & subdomains)"
echo -e " Source:  ${DIM}JetBackup queue logs + API${RESET}"
echo ""
echo -e "${DIM} CPU Limit: ${BOLD}$CPU_LIMIT${RESET}${DIM}  │  Backup Tasks: ${BOLD}$BACKUP_FORKS${RESET}${DIM}  │  System: ${BOLD}$SYSTEM_FORKS${RESET}${DIM}  │  Restore: ${BOLD}$RESTORE_FORKS${RESET}${DIM}  │  Extension: ${BOLD}$EXTENSION_FORKS${RESET}"
echo -e "${DIM} Max Threads: ${BOLD}$MAX_THREADS${RESET}${DIM}  │  Total Forks: ${BOLD}$TOTAL_FORKS${RESET}${DIM} (Backup+System+Restore)  │  Threads/Fork: ${BOLD}$THREADS_PER_FORK${RESET}${DIM}  (${MAX_THREADS} ÷ ${TOTAL_FORKS})${RESET}"
echo ""
