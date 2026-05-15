#!/bin/bash
# =============================================================================
# rollback.sh — 回復腳本 v1.3
# 用途：部署出問題時，還原至最近一次的備份狀態
# 使用方式：bash rollback.sh [專案名稱]
# 原則：
#   - 只還原程式碼和套件，不動 /etc/ 下的任何設定
#   - 關鍵服務清單從 project-context.md 讀取，不硬編碼
#   - 還原後自動驗證關鍵服務是否正常
#   - 所有操作記錄至 audit log
# =============================================================================

PROJECT="${1:-unknown-project}"
DEPLOY_ROOT="/opt/apps/$PROJECT"
ROLLBACK_DIR="$DEPLOY_ROOT/rollback"
LOG_FILE="rollback-$(date '+%Y%m%d-%H%M%S').log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTEXT_FILE="project-context.md"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"; }
info() { echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"; }

# ── 從 project-context.md 讀取關鍵服務清單 ───────────────────────────────────

load_critical_services() {
    CRITICAL_SERVICES=()
    CRITICAL_CONTAINERS=()

    if [ ! -f "$CONTEXT_FILE" ]; then
        warn "找不到 $CONTEXT_FILE，將跳過關鍵服務驗證"
        return
    fi

    while IFS= read -r line; do
        if echo "$line" | grep -qE "^\- \[x\].*\.service"; then
            svc=$(echo "$line" | grep -oE "[a-zA-Z0-9_\-]+\.service")
            CRITICAL_SERVICES+=("$svc")
        fi
    done < "$CONTEXT_FILE"

    in_container_section=0
    while IFS= read -r line; do
        if echo "$line" | grep -q "關鍵 Docker Container"; then
            in_container_section=1
        fi
        if [ $in_container_section -eq 1 ] && echo "$line" | grep -qE "^\- \[x\]"; then
            container=$(echo "$line" | sed 's/- \[x\] //' | awk '{print $1}')
            CRITICAL_CONTAINERS+=("$container")
        fi
        if [ $in_container_section -eq 1 ] && echo "$line" | grep -q "^---"; then
            in_container_section=0
        fi
    done < "$CONTEXT_FILE"

    info "載入關鍵 systemd 服務：${CRITICAL_SERVICES[*]:-（無）}"
    info "載入關鍵 Docker Container：${CRITICAL_CONTAINERS[*]:-（無）}"
}

# ── 驗證關鍵服務 ──────────────────────────────────────────────────────────────

verify_services() {
    local failed=0

    for svc in "${CRITICAL_SERVICES[@]}"; do
        if systemctl list-units --type=service 2>/dev/null | grep -q "$svc"; then
            if systemctl is-active --quiet "$svc"; then
                ok "$svc：正常運行 ✅"
            else
                err "$svc：異常！請立即聯繫 HQ 工程師"
                failed=1
            fi
        fi
    done

    for container in "${CRITICAL_CONTAINERS[@]}"; do
        if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
            if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
                ok "Container $container：正常運行 ✅"
            else
                err "Container $container：異常！請立即聯繫 HQ 工程師"
                failed=1
            fi
        fi
    done

    return $failed
}

# ── 主程式 ────────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════════"
echo "  回復腳本 v1.3"
echo "  專案：$PROJECT"
echo "  時間：$(date '+%Y-%m-%d %H:%M')"
echo "════════════════════════════════════════════════"
echo ""

load_critical_services

if [ ! -d "$ROLLBACK_DIR" ]; then
    err "找不到備份目錄：$ROLLBACK_DIR"
    err "請聯繫 HQ 工程師協助處理"
    bash "$SCRIPT_DIR/audit-log.sh" "rollback" "$PROJECT" "failed" "找不到備份目錄"
    exit 1
fi

echo "可用的備份版本："
echo ""
backups=($(ls -dt "$ROLLBACK_DIR"/*/ 2>/dev/null))

if [ ${#backups[@]} -eq 0 ]; then
    err "沒有找到任何備份"
    err "請聯繫 HQ 工程師協助處理"
    bash "$SCRIPT_DIR/audit-log.sh" "rollback" "$PROJECT" "failed" "沒有找到備份"
    exit 1
fi

for i in "${!backups[@]}"; do
    backup_time=$(basename "${backups[$i]}")
    svc_status=""
    if [ -f "${backups[$i]}/service-status-snapshot.txt" ]; then
        svc_status=$(grep -v "^---\|^備份時間" "${backups[$i]}/service-status-snapshot.txt" | \
                     tr '\n' ' ' | cut -c1-60)
    fi
    echo "  [$((i+1))] $backup_time  $svc_status"
done

echo ""
echo "  [0] 取消，不執行回復"
echo ""

while true; do
    read -rp "請選擇要回復的版本（建議選 1 = 最新備份）: " choice
    if [ "$choice" -eq 0 ] 2>/dev/null; then
        warn "已取消回復"
        bash "$SCRIPT_DIR/audit-log.sh" "rollback" "$PROJECT" "cancelled" "使用者取消"
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
echo "    1. 停止專案相關程序（不停止關鍵服務）"
echo "    2. 還原程式碼至備份版本"
echo "    3. 還原 Python 套件至備份版本"
echo "    4. 驗證所有關鍵服務仍在運行"
echo ""
echo "  不會執行："
echo "    ❌ 不修改 /etc/ 下的任何設定"
echo "    ❌ 不停止任何關鍵服務"
echo "    ❌ 不修改系統帳號"

read -rp "確認執行回復？[yes/no]: " confirm
if [[ "$confirm" != "yes" && "$confirm" != "y" ]]; then
    warn "已取消"
    bash "$SCRIPT_DIR/audit-log.sh" "rollback" "$PROJECT" "cancelled" "使用者取消確認"
    exit 0
fi

info "開始回復..."

# Step 1: 停止專案程序
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
verify_services
failed=$?

echo ""
echo "════════════════════════════════════════"
if [ $failed -eq 0 ]; then
    ok "回復完成！已還原至：$backup_name"
    ok "請通知 HQ 工程師確認回復結果"
    bash "$SCRIPT_DIR/audit-log.sh" "rollback" "$PROJECT" "success" "還原至 $backup_name"
else
    err "回復完成，但有關鍵服務異常"
    err "請立即聯繫 HQ 工程師，並提供 log：$LOG_FILE"
    bash "$SCRIPT_DIR/audit-log.sh" "rollback" "$PROJECT" "failed" "還原至 $backup_name，但關鍵服務異常"
fi
echo "════════════════════════════════════════"
