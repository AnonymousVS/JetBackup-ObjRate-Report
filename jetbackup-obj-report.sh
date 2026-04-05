#!/bin/bash
# ============================================================================
# JetBackup Object Rate Report
# Estimate S3 object upload rate per cPanel account from JetBackup 5 queue logs
#
# Repository : https://github.com/AnonymousVS/JetBackup-ObjRate-Report
# Install to : /usr/local/sbin/jetbackup-obj-report.sh
# Usage      : jetbackup-obj-report.sh
# ============================================================================

OBJ_PER_SEC=1400
QUEUE_DIR="/usr/local/jetapps/var/log/jetbackup5/queue"
TMPFILE=$(mktemp)

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         BACKUP REPORT — $(hostname) — $(TZ='Asia/Bangkok' date '+%d %b %Y %H:%M')       ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

printf " %-18s │ %-8s │ %-8s │ %-8s │ %12s │ %10s │ %8s\n" \
    "Account" "Start" "End" "Duration" "Est.Objects" "obj/min" "obj/sec"
echo "────────────────────┼──────────┼──────────┼──────────┼──────────────┼────────────┼─────────"

TOTAL_SEC=0
TOTAL_OBJ=0

for LOG in "${QUEUE_DIR}"/*.log; do
    [ ! -f "$LOG" ] && continue

    ACC=$(grep 'Transferring account' "$LOG" 2>/dev/null | tail -1 | sed 's/.*account "\([^"]*\)".*/\1/')
    [ -z "$ACC" ] && continue

    START=$(grep 'Syncing.*homedir' "$LOG" 2>/dev/null | tail -1 | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2}')
    END=$(grep 'Backup Completed' "$LOG" 2>/dev/null | tail -1 | grep -oP '\d{2}/\w+/\d{4} \d{2}:\d{2}:\d{2}')

    [ -z "$START" ] || [ -z "$END" ] && continue

    START_EP=$(date -d "$(echo "$START" | sed 's|/| |g')" +%s 2>/dev/null)
    END_EP=$(date -d "$(echo "$END" | sed 's|/| |g')" +%s 2>/dev/null)

    [ -z "$START_EP" ] || [ -z "$END_EP" ] && continue

    DURATION=$((END_EP - START_EP))
    [ "$DURATION" -le 0 ] && continue

    HOURS=$((DURATION / 3600))
    MINS=$(( (DURATION % 3600) / 60 ))
    EST_OBJ=$((OBJ_PER_SEC * DURATION))
    OBJ_MIN=$((DURATION > 60 ? EST_OBJ / (DURATION / 60) : EST_OBJ))

    START_TH=$(TZ='Asia/Bangkok' date -d @"$START_EP" '+%H:%M')
    END_TH=$(TZ='Asia/Bangkok' date -d @"$END_EP" '+%H:%M')

    printf " %-18s │ %8s │ %8s │ %4dh%02dm │ %'12d │ %'10d │ %'8d\n" \
        "$ACC" "$START_TH" "$END_TH" "$HOURS" "$MINS" "$EST_OBJ" "$OBJ_MIN" "$OBJ_PER_SEC" >> "$TMPFILE"

    TOTAL_SEC=$((TOTAL_SEC + DURATION))
    TOTAL_OBJ=$((TOTAL_OBJ + EST_OBJ))
done

sort "$TMPFILE"
rm -f "$TMPFILE"

echo "────────────────────┼──────────┼──────────┼──────────┼──────────────┼────────────┼─────────"

T_HR=$((TOTAL_SEC / 3600))
T_MIN=$(( (TOTAL_SEC % 3600) / 60 ))

printf " %-18s │ %8s │ %8s │ %4dh%02dm │ %'12d │ %10s │ %'8d\n" \
    "TOTAL" "" "" "$T_HR" "$T_MIN" "$TOTAL_OBJ" "" "$OBJ_PER_SEC"

echo ""
echo " Base rate: $OBJ_PER_SEC obj/s (from live test)"
echo " Source: JetBackup queue logs"
echo ""
