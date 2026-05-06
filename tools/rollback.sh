#!/bin/bash
# =============================================================================
# rollback.sh — 回復腳本 v1.0
# 用途：部署出問題時，還原至最近一次的備份狀態
# 使用方式：bash rollback.sh [專案名稱]
# 原則：
#   - 只還原程式碼和套件，不動 /etc/ 下的任何設定
#   - 還原後自動驗證服務是否正常
#   - 所有操作都記錄 log
# =============================================================================

PROJECT="${1:-unknown-project}"
DEPLOY_ROOT="/opt/apps/$PROJECT"
ROLLBACK_DIR="$DEPLOY_ROOT/rollback"
LOG_FILE="rollback-$(date '+%Y%m%d-%H%M%S').log"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"; }
info() { echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"; }

echo ""
echo "════════════════════════════════════════════════"
echo "  回復腳本 v1.0"
echo "  專案：$PROJECT"
echo "  時間：$(date '+%Y-%m-%d %H:%M')"
echo "════════════════════════════════════════════════"
echo ""

# 確認備份目錄存在
if [ ! -d "$ROLLBACK_DIR" ]; then
    err "找不到備份目錄：$ROLLBACK_DIR"
    err "請聯繫 HQ 工程師（Jason）協助處理"
    exit 1
fi

# 列出可用備份
echo "可用的備份版本："
echo ""
backups=($(ls -dt "$ROLLBACK_DIR"/*/ 2>/dev/null))

if [ ${#backups[@]} -eq 0 ]; then
    err "沒有找到任何備份"
    err "請聯繫 HQ 工程師協助處理"
    exit 1
fi

for i in "${!backups[@]}"; do
    backup_time=$(basename "${backups[$i]}")
    # 顯示備份時的服務狀態
    svc_status=""
    if [ -f "${backups[$i]}/service-status-snapshot.txt" ]; then
        svc_status=$(cat "${backups[$i]}/service-status-snapshot.txt" | grep -E "slapd|freeradius" | tr '\n' ' ')
    fi
    echo "  [$((i+1))] $backup_time  $svc_status"
done

echo ""
echo "  [0] 取消，不執行回復"
echo ""

# 選擇備份版本
while true; do
    read -rp "請選擇要回復的版本（建議選 1 = 最新備份）: " choice
    if [ "$choice" -eq 0 ] 2>/dev/null; then
        warn "已取消回復"
        exit 0
    elif [ "$choice" -ge 1 ] && [ "$choice" -le ${#backups[@]} ] 2>/dev/null; then
        selected="${backups[$((choice-1))]}"
        break
    else
        echo "請輸入有效的數字"
    fi
done

backup_name=$(basename "$selected")
echo ""
warn "即將回復至：$backup_name"
echo ""
echo "  將要執行："
echo "    1. 停止專案相關程序（不停止 slapd / freeradius）"
echo "    2. 還原程式碼至備份版本"
echo "    3. 還原 Python 套件至備份版本"
echo "    4. 驗證 slapd / freeradius 仍在運行"
echo ""
echo "  不會執行："
echo "    ❌ 不修改 /etc/ 下的任何設定"
echo "    ❌ 不停止 slapd / freeradius"
echo "    ❌ 不修改系統帳號"

read -rp "確認執行回復？[yes/no]: " confirm
if [[ "$confirm" != "yes" && "$confirm" != "y" ]]; then
    warn "已取消"
    exit 0
fi

# ── 執行回復 ──────────────────────────────────────────────────────────────────

info "開始回復..."

# Step 1: 停止專案程序（如果有 systemd service 的話）
PROJECT_SVC="${PROJECT//-/_}"
if systemctl list-units --type=service 2>/dev/null | grep -q "$PROJECT_SVC"; then
    info "停止專案服務：$PROJECT_SVC"
    sudo systemctl stop "$PROJECT_SVC" 2>/dev/null
fi

# Step 2: 還原程式碼
if [ -d "$selected/code/" ]; then
    info "還原程式碼..."
    rsync -a --delete \
        --exclude='venv/' \
        --exclude='logs/' \
        --exclude='rollback/' \
        "$selected/code/" "$DEPLOY_ROOT/" 2>&1 | tee -a "$LOG_FILE"
    ok "程式碼還原完成"
else
    warn "備份中沒有程式碼，跳過此步驟"
fi

# Step 3: 還原套件
if [ -f "$selected/requirements-snapshot.txt" ]; then
    info "還原 Python 套件..."
    VENV_PATH="$DEPLOY_ROOT/venv"
    if [ -f "$VENV_PATH/bin/pip" ]; then
        "$VENV_PATH/bin/pip" install \
            -r "$selected/requirements-snapshot.txt" \
            --quiet \
            2>&1 | tee -a "$LOG_FILE"
        ok "套件還原完成"
    else
        warn "venv 不存在，跳過套件還原"
    fi
fi

# Step 4: 重啟專案服務
if systemctl list-units --type=service 2>/dev/null | grep -q "$PROJECT_SVC"; then
    info "重啟專案服務：$PROJECT_SVC"
    sudo systemctl start "$PROJECT_SVC" 2>/dev/null
fi

# Step 5: 驗證關鍵服務
echo ""
info "驗證關鍵服務..."
failed=0
for svc in slapd freeradius; do
    if systemctl list-units --type=service 2>/dev/null | grep -q "$svc"; then
        if systemctl is-active --quiet "$svc"; then
            ok "$svc：正常運行 ✅"
        else
            err "$svc：異常！請立即聯繫 HQ 工程師"
            failed=1
        fi
    fi
done

echo ""
echo "════════════════════════════════════════"
if [ $failed -eq 0 ]; then
    ok "回復完成！已還原至：$backup_name"
    ok "請通知 HQ 工程師（Jason）確認回復結果"
else
    err "回復完成，但有服務異常"
    err "請立即聯繫 HQ 工程師，並提供 log：$LOG_FILE"
fi
echo "════════════════════════════════════════"
