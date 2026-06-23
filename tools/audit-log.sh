#!/bin/bash
# =============================================================================
# audit-log.sh — 操作紀錄腳本 v1.0
# 用途：記錄所有部署相關操作
# 使用方式：
#   source audit-log.sh
#   audit_log [動作] [專案] [結果] [說明]
# =============================================================================

AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-/opt/apps}"

audit_log() {
    local ACTION="${1:-unknown}"
    local PROJECT="${2:-unknown}"
    local RESULT="${3:-unknown}"
    local MESSAGE="${4:-}"
    local LOG_FILE="$AUDIT_LOG_DIR/$PROJECT/logs/audit.log"

    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

    local ENTRY
    ENTRY=$(printf '{"timestamp":"%s","action":"%s","project":"%s","user":"%s","result":"%s","message":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$ACTION" \
        "$PROJECT" \
        "$(whoami)" \
        "$RESULT" \
        "$MESSAGE")

    echo "$ENTRY" >> "$LOG_FILE"
    echo "📋 Audit: [$RESULT] $ACTION — $PROJECT ${MESSAGE:+| $MESSAGE}"
}

# 如果直接執行（非 source）
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    audit_log "${1:-}" "${2:-}" "${3:-success}" "${4:-}"
fi
