#!/bin/bash
# =============================================================================
# rollback.sh — 回復腳本 v1.0
# 用途：將部署回復到上一個版本
# 使用方式：bash rollback.sh [專案名稱] [版本目錄（選填）]
# =============================================================================

set -euo pipefail

PROJECT_NAME="${1:-}"
TARGET_VERSION="${2:-}"

if [ -z "$PROJECT_NAME" ]; then
    echo "❌ 請提供專案名稱：bash rollback.sh [專案名稱]"
    exit 1
fi

PROJECT_DIR="/opt/apps/$PROJECT_NAME"
ROLLBACK_DIR="$PROJECT_DIR/rollback"

if [ ! -d "$ROLLBACK_DIR" ]; then
    echo "❌ 找不到 rollback 目錄：$ROLLBACK_DIR"
    exit 1
fi

echo "=== rollback.sh 開始執行 ==="
echo "專案名稱：$PROJECT_NAME"
echo ""

# 列出可用版本
echo "可用的備份版本："
ls -1t "$ROLLBACK_DIR" 2>/dev/null || echo "  （無備份）"
echo ""

# 選擇版本
if [ -z "$TARGET_VERSION" ]; then
    LATEST=$(ls -1t "$ROLLBACK_DIR" | head -1)
    if [ -z "$LATEST" ]; then
        echo "❌ 沒有可用的備份版本"
        exit 1
    fi
    echo "將回復到最新備份：$LATEST"
    TARGET_VERSION="$LATEST"
fi

TARGET_PATH="$ROLLBACK_DIR/$TARGET_VERSION"
if [ ! -d "$TARGET_PATH" ]; then
    echo "❌ 找不到版本：$TARGET_VERSION"
    exit 1
fi

# 人工確認
echo ""
echo "⚠️  即將執行回復，請確認："
echo "   回復目標：$TARGET_PATH"
echo "   執行帳號：$(whoami)"
echo ""
read -rp "確認繼續？(yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ 已取消"
    exit 0
fi

# 執行回復
echo ""
echo "▶ 執行回復..."
rsync -a --delete "$TARGET_PATH/src/" "$PROJECT_DIR/src/"
echo "✅ 程式碼回復完成"

# 記錄 audit log
echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"action\":\"rollback\",\"project\":\"$PROJECT_NAME\",\"version\":\"$TARGET_VERSION\",\"user\":\"$(whoami)\",\"result\":\"success\"}" >> "$PROJECT_DIR/logs/audit.log"

echo ""
echo "=== rollback.sh 完成 ==="
echo "已回復至版本：$TARGET_VERSION"
echo "請重新啟動服務並驗證運行狀態"
