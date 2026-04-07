#!/bin/bash
# ============================================================================
# Test: TZ fix for JetBackup Object Rate Report
# ทดสอบว่าจับ +0000 แล้วแปลง Bangkok ถูกต้องไหม
# Usage: bash test-tz-fix.sh
# ============================================================================

QUEUE_DIR="/usr/local/jetapps/var/log/jetbackup5/queue"
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RESET="\033[0m"

echo ""
echo -e "${BOLD}${CYAN}=== Test 1: date parsing — with vs without +0000 ===${RESET}"
echo ""
RAW="06 Apr 2026 23:38:20"
echo -e "  Input (from log): ${BOLD}$RAW${RESET}"
echo ""

OLD=$(TZ='Asia/Bangkok' date -d "$RAW" '+%Y-%m-%d %H:%M %Z' 2>&1)
NEW=$(TZ='Asia/Bangkok' date -d "$RAW +0000" '+%Y-%m-%d %H:%M %Z' 2>&1)

echo -e "  ${RED}OLD (no +0000):  $OLD   ← thinks 23:38 is already Bangkok${RESET}"
echo -e "  ${GREEN}NEW (with +0000): $NEW   ← correctly converts UTC → Bangkok${RESET}"

echo ""
echo -e "${BOLD}${CYAN}=== Test 2: grep regex — old vs new ===${RESET}"
echo ""

SAMPLE='[06/Apr/2026 19:33:38 +0000] [PID 452114] Syncing "/home/y2026m03sv01/" to "...homedir"'
echo -e "  Sample line: ${BOLD}$SAMPLE${RESET}"
echo ""

OLD_MATCH=$(echo "$SAMPLE" | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2}')
NEW_MATCH=$(echo "$SAMPLE" | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2} \+\d{4}')

echo -e "  OLD regex captures: ${RED}[$OLD_MATCH]${RESET}"
echo -e "  NEW regex captures: ${GREEN}[$NEW_MATCH]${RESET}"

echo ""
echo -e "${BOLD}${CYAN}=== Test 3: sed conversion — slash to space ===${RESET}"
echo ""

OLD_SED=$(echo "$OLD_MATCH" | sed 's|/| |g')
NEW_SED=$(echo "$NEW_MATCH" | sed 's|/| |g')

echo -e "  OLD sed: [$OLD_SED] → date: $(TZ='Asia/Bangkok' date -d "$OLD_SED" '+%Y-%m-%d %H:%M %Z' 2>&1)"
echo -e "  NEW sed: [$NEW_SED] → date: $(TZ='Asia/Bangkok' date -d "$NEW_SED" '+%Y-%m-%d %H:%M %Z' 2>&1)"

echo ""
echo -e "${BOLD}${CYAN}=== Test 4: real log files (last 10) ===${RESET}"
echo ""

printf "  ${BOLD}%-60s │ %-12s │ %-12s │ %-18s │ %-18s${RESET}\n" \
    "Log File" "Account" "OLD Date" "NEW Date (Bangkok)" "Start → End BKK"
echo -e "  ${YELLOW}$(printf '─%.0s' {1..130})${RESET}"

COUNT=0
for LOG in $(ls -t "${QUEUE_DIR}"/*.log 2>/dev/null | head -10); do
    [ ! -f "$LOG" ] && continue

    ACC=$(grep 'Transferring account' "$LOG" 2>/dev/null | tail -1 | sed 's/.*account "\([^"]*\)".*/\1/')
    [ -z "$ACC" ] && continue

    # OLD method (no timezone)
    OLD_START=$(grep 'Syncing.*homedir' "$LOG" 2>/dev/null | tail -1 | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2}')
    OLD_END=$(grep 'Backup Completed' "$LOG" 2>/dev/null | tail -1 | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2}')

    # NEW method (with timezone)
    NEW_START=$(grep 'Syncing.*homedir' "$LOG" 2>/dev/null | tail -1 | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2} \+\d{4}')
    NEW_END=$(grep 'Backup Completed' "$LOG" 2>/dev/null | tail -1 | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2} \+\d{4}')

    [ -z "$OLD_START" ] || [ -z "$OLD_END" ] && continue

    OLD_DATE=$(TZ='Asia/Bangkok' date -d "$(echo "$OLD_END" | sed 's|/| |g')" '+%Y-%m-%d' 2>/dev/null)
    NEW_DATE=$(TZ='Asia/Bangkok' date -d "$(echo "$NEW_END" | sed 's|/| |g')" '+%Y-%m-%d' 2>/dev/null)

    NEW_S_BKK=$(TZ='Asia/Bangkok' date -d "$(echo "$NEW_START" | sed 's|/| |g')" '+%H:%M' 2>/dev/null)
    NEW_E_BKK=$(TZ='Asia/Bangkok' date -d "$(echo "$NEW_END" | sed 's|/| |g')" '+%H:%M' 2>/dev/null)

    FNAME=$(basename "$LOG")

    if [ "$OLD_DATE" != "$NEW_DATE" ]; then
        DIFF="${RED}DIFF!${RESET}"
    else
        DIFF="${GREEN}same${RESET}"
    fi

    printf "  %-60s │ %-12s │ %s%-12s%s │ ${GREEN}%-18s${RESET} │ %s → %s  [%b]\n" \
        "$FNAME" "$ACC" "$RED" "$OLD_DATE" "$RESET" "$NEW_DATE" "$NEW_S_BKK" "$NEW_E_BKK" "$DIFF"

    COUNT=$((COUNT + 1))
done

echo ""
echo -e "  Checked: ${BOLD}$COUNT${RESET} log files"
echo ""
