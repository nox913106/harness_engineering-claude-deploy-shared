#!/bin/bash
# =============================================================================
# audit-log.sh — 操作紀錄腳本 v1.0
# 用途：記錄所有部署相關操作，產生可追溯的 audit trail
# 使用方式：
#   source audit-log.sh  （在其他腳本中引用）
#   或直接呼叫：bash audit-log.sh [動作] [專案] [結果] [說明]
# =============================================================================

AUDIT_ACTION="${1:-unknown}"
AUDIT_PROJECT="${2:-unknown}"
AUDIT_RESULT="${3:-unknown}"
AUDIT_NOTE="${4:-}"

LOG_DIR="/opt/apps/${AUDIT_PROJECT}/logs"
LOG_FILE="${LOG_DIR}/audit.log"

# 確保 log 目錄存在
mkdir -p "$LOG_DIR" 2>/dev/null

# 產生一筆 JSON Lines 紀錄
ENTRY=$(cat << ENTRY_EOF
{"timestamp":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","action":"${AUDIT_ACTION}","project":"${AUDIT_PROJECT}","user":"[DEPLOY-USER]","host":"[HOST]","result":"${AUDIT_RESULT}","note":"${AUDIT_NOTE}"}
ENTRY_EOF
)

# 寫入 audit log
echo "$ENTRY" >> "$LOG_FILE"

# 清理超過 180 天的紀錄（保留最近 180 天）
if [ -f "$LOG_FILE" ]; then
    CUTOFF=$(date -d "180 days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
             date -v-180d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)
    if [ -n "$CUTOFF" ]; then
        # 只保留 cutoff 之後的紀錄
        awk -v cutoff="$CUTOFF" \
            'BEGIN{FS="\""} {
                for(i=1;i<=NF;i++) {
                    if($i=="timestamp") {ts=$(i+2)}
                }
                if(ts >= cutoff) print
            }' "$LOG_FILE" > "${LOG_FILE}.tmp" && \
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
fi

# 如果是直接呼叫（非 source），輸出確認
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "✅ Audit log 已記錄：$AUDIT_ACTION / $AUDIT_PROJECT / $AUDIT_RESULT"
fi