#!/bin/bash
LOGFILE=/var/log/syslog
[ -f "$LOGFILE" ] || { echo "лог не найден" > report.txt; exit 0; }
grep -i "sudo\|error\|fail\|тестовое событие" "$LOGFILE" > report.txt || true
