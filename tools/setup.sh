#!/bin/bash
# =============================================================================
# setup.sh — 環境統一化腳本 v1.0
# 用途：確認目標主機符合 DEPLOY_STANDARD，不符合時逐項提示補齊
# 使用方式：bash setup.sh [專案名稱]
# 原則：
#   - 每個會改變系統的動作都需要 yes/no 確認
#   - 每個動作執行後立即驗證現有服務未受影響
#   - 任何步驟失敗都停止並提示，不自動繼續
# =============================================================================

PROJECT="${1:-unknown-project}"
DEPLOY_ROOT="/opt/apps/$PROJECT"
VENV_PATH="$DEPLOY_ROOT/venv"
INTERNAL_PYPI="${INTERNAL_PYPI_URL:-http://pypi.internal/simple}"
LOG_FILE="setup-$(date '+%Y%m%d-%H%M%S').log"

# ── 顏色輸出 ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"; }
info() { echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"; }

# ── 工具函式 ──────────────────────────────────────────────────────────────────

# 詢問 yes/no，回傳 0=yes, 1=no
ask() {
    local question="$1"
    echo ""
    echo "────────────────────────────────────────────────────"
    echo -e "${BLUE}$question${NC}"
    while true; do
        read -rp "執行？[yes/no]: " answer
        case "$answer" in
            yes|y|YES|Y) return 0 ;;
            no|n|NO|N)   return 1 ;;
            *) echo "請輸入 yes 或 no" ;;
        esac
    done
}

# 執行指令並記錄
run() {
    echo "[執行] $*" >> "$LOG_FILE"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    return ${PIPESTATUS[0]}
}

# 驗證關鍵服務是否仍在運行（每個步驟後都執行）
verify_services() {
    local failed=0
    for svc in slapd freeradius; do
        if systemctl list-units --type=service 2>/dev/null | grep -q "$svc"; then
            if ! systemctl is-active --quiet "$svc"; then
                err "服務 $svc 已停止！"
                failed=1
            fi
        fi
    done
    if [ $failed -eq 1 ]; then
        err "關鍵服務異常，請立即檢查！"
        err "執行 rollback.sh 可還原至部署前狀態"
        exit 1
    fi
    ok "關鍵服務驗證通過（slapd / freeradius 正常）"
}

# 備份目前狀態
backup_current_state() {
    if [ ! -d "$DEPLOY_ROOT" ]; then
        return 0
    fi
    local backup_dir="$DEPLOY_ROOT/rollback/$(date '+%Y%m%d-%H%M%S')"
    info "建立部署前備份至 $backup_dir"
    mkdir -p "$backup_dir"

    # 備份程式碼（排除 venv 和 logs）
    rsync -a --exclude='venv/' --exclude='logs/' --exclude='rollback/' \
        "$DEPLOY_ROOT/" "$backup_dir/code/" 2>/dev/null

    # 備份套件清單
    if [ -f "$VENV_PATH/bin/pip" ]; then
        "$VENV_PATH/bin/pip" freeze > "$backup_dir/requirements-snapshot.txt" 2>/dev/null
    fi

    # 備份服務狀態
    {
        echo "備份時間: $(date)"
        for svc in slapd freeradius; do
            echo "$svc: $(systemctl is-active $svc 2>/dev/null || echo 'not-found')"
        done
    } > "$backup_dir/service-status-snapshot.txt"

    # 只保留最近 3 個備份
    ls -dt "$DEPLOY_ROOT/rollback/"*/ 2>/dev/null | tail -n +4 | xargs rm -rf

    ok "備份完成：$backup_dir"
}

# ── 檢查項目 ──────────────────────────────────────────────────────────────────

check_os() {
    info "=== 1/6 作業系統檢查 ==="
    local os_name
    os_name=$(grep "^NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
    local kernel
    kernel=$(uname -r | cut -d'.' -f1-2)

    ok "OS: $os_name | Kernel: $(uname -r)"

    # 只做檢查，OS 不需要補齊
    case "$os_name" in
        *Ubuntu*|*Debian*|*"Red Hat"*|*CentOS*|*Rocky*|*AlmaLinux*)
            ok "OS 類型符合標準" ;;
        *)
            err "不支援的 OS 類型：$os_name"
            err "請聯繫 HQ 工程師確認是否支援"
            exit 1 ;;
    esac
}

check_python() {
    info "=== 2/6 Python 環境檢查 ==="

    local py_ver
    py_ver=$(python3 --version 2>&1 | awk '{print $2}')
    local py_major
    py_major=$(echo "$py_ver" | cut -d'.' -f1)
    local py_minor
    py_minor=$(echo "$py_ver" | cut -d'.' -f2)

    if [ "$py_major" -ge 3 ] && [ "$py_minor" -ge 9 ]; then
        ok "Python $py_ver — 符合標準（需求 3.9+）"
        return 0
    fi

    warn "Python $py_ver — 不符合標準（需求 3.9+）"
    echo ""
    echo "  將要執行：apt install python3.11 python3.11-venv python3.11-pip"
    echo "  影響評估："
    echo "    ✅ 不會移除現有 Python $py_ver"
    echo "    ✅ 不影響 slapd / freeradius"
    echo "    ✅ 可回復（apt remove python3.11）"

    if ask "安裝 Python 3.11？"; then
        run sudo apt-get update -qq
        run sudo apt-get install -y python3.11 python3.11-venv python3.11-pip
        verify_services
        ok "Python 3.11 安裝完成"
    else
        warn "跳過 Python 安裝，後續步驟可能失敗"
    fi
}

check_system_deps() {
    info "=== 3/6 系統套件檢查 ==="

    local missing=()
    local required=("git" "curl")

    for pkg in "${required[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            missing+=("$pkg")
            warn "$pkg：未安裝"
        else
            ok "$pkg：$(command -v $pkg)"
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        ok "系統套件全部符合標準"
        return 0
    fi

    echo ""
    echo "  將要執行：apt install ${missing[*]}"
    echo "  影響評估："
    echo "    ✅ 基本工具套件，不影響任何現有服務"

    if ask "安裝缺少的系統套件（${missing[*]}）？"; then
        run sudo apt-get install -y "${missing[@]}"
        verify_services
        ok "系統套件安裝完成"
    else
        warn "跳過，請確認後續部署是否受影響"
    fi
}

setup_venv() {
    info "=== 4/6 Python 虛擬環境設定 ==="

    # 建立部署目錄
    if [ ! -d "$DEPLOY_ROOT" ]; then
        echo ""
        echo "  將要執行：mkdir -p $DEPLOY_ROOT/logs $DEPLOY_ROOT/config"
        echo "  影響評估："
        echo "    ✅ 只建立新目錄，不修改現有任何檔案"

        if ask "建立專案目錄結構（$DEPLOY_ROOT）？"; then
            run mkdir -p "$DEPLOY_ROOT"/{src,config,logs,rollback}
            ok "目錄結構建立完成"
        else
            err "目錄未建立，無法繼續部署"
            exit 1
        fi
    else
        ok "專案目錄已存在：$DEPLOY_ROOT"
    fi

    # 建立或更新 venv
    if [ ! -d "$VENV_PATH" ]; then
        echo ""
        echo "  將要執行：python3 -m venv $VENV_PATH"
        echo "  影響評估："
        echo "    ✅ 獨立虛擬環境，完全不影響系統 Python"
        echo "    ✅ 不影響任何現有服務"

        if ask "建立 Python 虛擬環境？"; then
            run python3 -m venv "$VENV_PATH"
            verify_services
            ok "虛擬環境建立完成：$VENV_PATH"
        else
            err "虛擬環境未建立，無法繼續"
            exit 1
        fi
    else
        ok "虛擬環境已存在：$VENV_PATH"
    fi
}

install_python_packages() {
    info "=== 5/6 Python 套件安裝 ==="

    local REQUIRED_PACKAGES=(
        "ldap3==2.9.1"
        "mysql-connector-python==8.0.33"
        "cryptography>=41.0.0"
        "requests>=2.31.0"
    )

    local missing_pkgs=()

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        pkg_name=$(echo "$pkg" | sed 's/[>=!].*//')
        if "$VENV_PATH/bin/pip" show "$pkg_name" &>/dev/null; then
            installed_ver=$("$VENV_PATH/bin/pip" show "$pkg_name" | grep Version | awk '{print $2}')
            ok "$pkg_name: $installed_ver — 已安裝"
        else
            missing_pkgs+=("$pkg")
            warn "$pkg_name — 未安裝"
        fi
    done

    if [ ${#missing_pkgs[@]} -eq 0 ]; then
        ok "所有 Python 套件符合標準"
        return 0
    fi

    echo ""
    echo "  將要執行："
    for pkg in "${missing_pkgs[@]}"; do
        echo "    pip install $pkg --index-url $INTERNAL_PYPI"
    done
    echo "  影響評估："
    echo "    ✅ 安裝至獨立 venv，不影響系統套件"
    echo "    ✅ 來源：內部 PyPI mirror（不需對外網路）"
    echo "    ✅ 不影響 slapd / freeradius"

    if ask "安裝缺少的 Python 套件？"; then
        for pkg in "${missing_pkgs[@]}"; do
            run "$VENV_PATH/bin/pip" install "$pkg" \
                --index-url "$INTERNAL_PYPI" \
                --no-deps \
                --quiet
            if [ $? -ne 0 ]; then
                err "$pkg 安裝失敗"
                err "請確認內部 PyPI mirror 是否可達：$INTERNAL_PYPI"
                exit 1
            fi
        done
        verify_services
        ok "Python 套件安裝完成"
    else
        warn "跳過套件安裝，程式執行時可能發生 ImportError"
    fi
}

final_verification() {
    info "=== 6/6 最終驗證 ==="

    local pass=0
    local fail=0

    # Python 版本
    py_ver=$(python3 --version 2>&1 | awk '{print $2}')
    py_minor=$(echo "$py_ver" | cut -d'.' -f2)
    if [ "$py_minor" -ge 9 ]; then
        ok "Python $py_ver ✅"
        ((pass++))
    else
        err "Python $py_ver ❌（需要 3.9+）"
        ((fail++))
    fi

    # venv 存在
    if [ -f "$VENV_PATH/bin/python" ]; then
        ok "虛擬環境存在 ✅"
        ((pass++))
    else
        err "虛擬環境不存在 ❌"
        ((fail++))
    fi

    # 套件可 import
    for pkg in ldap3 mysql.connector cryptography requests; do
        if "$VENV_PATH/bin/python" -c "import $pkg" 2>/dev/null; then
            ok "import $pkg ✅"
            ((pass++))
        else
            err "import $pkg ❌"
            ((fail++))
        fi
    done

    # 關鍵服務
    verify_services
    ((pass++))

    echo ""
    echo "════════════════════════════════════════"
    if [ $fail -eq 0 ]; then
        ok "環境統一化完成！通過 $pass 項檢查"
        ok "可以繼續進行部署"
    else
        err "有 $fail 項未通過，請解決後再部署"
        err "Log 檔案：$LOG_FILE"
    fi
    echo "════════════════════════════════════════"
}

# ── 主程式 ────────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════════"
echo "  環境統一化精靈 v1.0"
echo "  專案：$PROJECT"
echo "  時間：$(date '+%Y-%m-%d %H:%M')"
echo "════════════════════════════════════════════════"
echo ""
info "開始前將檢查所有項目，需要變更的步驟會逐一詢問確認"
info "Log 記錄至：$LOG_FILE"
echo ""

# 確認不是 root
if [ "$(id -u)" -eq 0 ]; then
    err "請勿使用 root 執行此腳本，請用部署服務帳號執行"
    exit 1
fi

# 備份現有狀態
backup_current_state

# 逐項檢查
check_os
check_python
check_system_deps
setup_venv
install_python_packages
final_verification
