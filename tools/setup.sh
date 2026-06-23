#!/bin/bash
# =============================================================================
# setup.sh — 環境統一化腳本 v1.0
# 用途：在目標主機上建立標準化部署環境
# 使用方式：bash setup.sh [專案名稱]
# 必須在人工確認 project-context.md 後才能執行
# =============================================================================

set -euo pipefail

PROJECT_NAME="${1:-}"
if [ -z "$PROJECT_NAME" ]; then
    echo "❌ 請提供專案名稱：bash setup.sh [專案名稱]"
    exit 1
fi

PROJECT_DIR="/opt/apps/$PROJECT_NAME"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "=== setup.sh 開始執行 ==="
echo "專案名稱：$PROJECT_NAME"
echo "目標目錄：$PROJECT_DIR"
echo "時間：$TIMESTAMP"
echo ""

# 人工確認
echo "⚠️  即將建立部署環境，請確認以下資訊："
echo "   專案名稱：$PROJECT_NAME"
echo "   目標目錄：$PROJECT_DIR"
echo "   執行帳號：$(whoami)"
echo ""
read -rp "確認繼續？(yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ 已取消"
    exit 0
fi

# 建立目錄結構
echo ""
echo "▶ 建立目錄結構..."
mkdir -p "$PROJECT_DIR"/{src,config,logs,venv,rollback}
echo "✅ 目錄結構建立完成"

# 建立 Python 虛擬環境
echo ""
echo "▶ 建立 Python 虛擬環境..."
if [ ! -d "$PROJECT_DIR/venv" ] || [ ! -f "$PROJECT_DIR/venv/bin/activate" ]; then
    python3 -m venv "$PROJECT_DIR/venv"
    echo "✅ 虛擬環境建立完成"
else
    echo "ℹ️  虛擬環境已存在，跳過"
fi

# 建立 log 檔案
echo ""
echo "▶ 建立 log 檔案..."
touch "$PROJECT_DIR/logs/app.log"
touch "$PROJECT_DIR/logs/audit.log"
echo "✅ Log 檔案建立完成"

# 建立 claude-progress.txt 範本
if [ ! -f "$PROJECT_DIR/claude-progress.txt" ]; then
    cat > "$PROJECT_DIR/claude-progress.txt" << EOF
# claude-progress.txt

最後更新：$TIMESTAMP
目前完成：（尚未開始）
下一步：初始化完成，可以開始開發
已知問題：無
相關 commit：無
EOF
    echo "✅ claude-progress.txt 建立完成"
fi

echo ""
echo "=== setup.sh 完成 ==="
echo "專案目錄：$PROJECT_DIR"
echo "請執行 source $PROJECT_DIR/venv/bin/activate 啟用虛擬環境"
