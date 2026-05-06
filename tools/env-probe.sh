#!/bin/bash
# =============================================================================
# env-probe.sh — 環境探測腳本 v1.2
# 用途：
#   1. 全面探測目標主機環境（不預設服務清單）
#   2. 包含 ufw / docker / docker compose 探測
#   3. 產出脫敏報告供 HQ 分析
#   4. 產出 project-context.md 供 deploy-guard 讀取
# 使用方式：bash env-probe.sh [專案名稱]
# 輸出：
#   env-probe-report.txt  （脫敏，可傳給 HQ）
#   project-context.md    （需 HQ/IT 確認關鍵服務後才生效）
# =============================================================================

PROJECT="${1:-unknown-project}"
REPORT="env-probe-report.txt"
CONTEXT="project-context.md"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

# ── 脫敏函式 ──────────────────────────────────────────────────────────────────

redact_host() { sed "s/$(hostname)/[HOST]/g"; }

redact_ip() {
    sed -E \
        's/10\.[0-9]+\.[0-9]+\.[0-9]+/[INTERNAL-IP]/g;
         s/172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+/[INTERNAL-IP]/g;
         s/192\.168\.[0-9]+\.[0-9]+/[INTERNAL-IP]/g;
         s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[EXTERNAL-IP]/g'
}

redact_user() { sed "s/$(whoami)/[DEPLOY-USER]/g"; }

redact_path() {
    sed -E \
        's|(/opt/)([^/]+)(/)|\1[DIR]\3|g;
         s|(/home/)([^/]+)(/)|\1[USER]\3|g'
}

# ── 探測函式 ──────────────────────────────────────────────────────────────────

check_os() {
    echo "## OS 資訊"
    grep -E "^(NAME|VERSION)=" /etc/os-release 2>/dev/null | sed 's/"//g'
    echo "Kernel: $(uname -r)"
    echo "Arch: $(uname -m)"
    echo ""
}

check_python() {
    echo "## Python 環境"
    for cmd in python3 python; do
        command -v $cmd &>/dev/null && echo "  $cmd: $($cmd --version 2>&1)"
    done
    command -v pip3 &>/dev/null && echo "  pip3: $(pip3 --version 2>&1 | awk '{print $1,$2}')"
    echo ""
}

check_required_tools() {
    echo "## 必要工具"
    for tool in git curl wget systemctl; do
        if command -v $tool &>/dev/null; then
            echo "  ✅ $tool"
        else
            echo "  ❌ $tool: 未安裝"
        fi
    done
    echo ""
}

# ── 防火牆狀態 ────────────────────────────────────────────────────────────────

check_firewall() {
    echo "## 防火牆狀態（ufw）"
    echo "（部署後新服務能否被存取，取決於此設定）"
    echo ""

    if command -v ufw &>/dev/null; then
        ufw_status=$(sudo ufw status 2>/dev/null || ufw status 2>/dev/null)
        if echo "$ufw_status" | grep -q "Status: active"; then
            echo "  狀態: ✅ 啟用中"
            echo ""
            echo "  目前開放的規則："
            echo "$ufw_status" | grep -v "^Status\|^To\|^--" | \
                grep -v "^$" | \
                while read line; do
                    echo "    $line"
                done | redact_ip
        else
            echo "  狀態: ⚠️  未啟用（主機無防火牆保護）"
        fi
    else
        echo "  ufw: 未安裝"
        # 嘗試 iptables
        if command -v iptables &>/dev/null; then
            echo "  iptables: 已安裝（規則需手動確認）"
        fi
    fi
    echo ""
}

# ── systemd 服務（不過濾 ufw，只過濾純系統底層）─────────────────────────────

check_all_running_services() {
    echo "## 目前所有運行中的服務（systemd）"
    echo "（這是目標主機的實際狀態，非預設清單）"
    echo ""

    if command -v systemctl &>/dev/null; then
        systemctl list-units --type=service --state=active --no-pager 2>/dev/null | \
            grep "\.service" | \
            awk '{print $1}' | \
            grep -v -E "^(systemd-|dbus|getty@|accounts-daemon|polkit|rsyslog|cron|atd|plymouth|lvm2|dm-event|multipathd)\.service$" | \
            while read svc; do
                desc=$(systemctl show "$svc" -p Description --value 2>/dev/null)
                echo "  ▸ $svc"
                [ -n "$desc" ] && echo "      └─ $desc"
            done
    fi
    echo ""
}

check_all_listening_ports() {
    echo "## 所有監聽中的 Port"
    echo ""
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep LISTEN | \
            awk '{print "  port", $4, "←", $6}' | \
            redact_ip | sort
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep LISTEN | \
            awk '{print "  port", $4, "←", $7}' | \
            redact_ip
    fi
    echo ""
}

# ── Docker 探測 ───────────────────────────────────────────────────────────────

check_docker() {
    echo "## Docker 環境"
    echo ""

    if ! command -v docker &>/dev/null; then
        echo "  docker: 未安裝"
        echo ""
        return
    fi

    # Docker 版本
    echo "  Docker 版本: $(docker --version 2>/dev/null)"

    # Docker daemon 是否運行
    if docker info &>/dev/null 2>&1; then
        echo "  Docker daemon: ✅ 運行中"
    else
        echo "  Docker daemon: ❌ 未運行（需要 sudo？）"
        echo ""
        return
    fi

    echo ""

    # 所有正在運行的 container（這些都是潛在的關鍵服務）
    echo "  ### 正在運行的 Container（潛在關鍵服務）"
    running=$(docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null)
    if [ -n "$running" ]; then
        echo "$running" | redact_ip | while read line; do
            echo "    $line"
        done
    else
        echo "    （無正在運行的 container）"
    fi

    echo ""

    # 所有 container（包含停止的）
    echo "  ### 所有 Container（含已停止）"
    docker ps -a --format "  ▸ {{.Names}} [{{.Status}}] image: {{.Image}}" 2>/dev/null | redact_ip

    echo ""

    # Docker network
    echo "  ### Docker Network"
    docker network ls 2>/dev/null | while read line; do
        echo "    $line"
    done

    echo ""
}

# ── Docker Compose 探測 ───────────────────────────────────────────────────────

check_docker_compose() {
    echo "## Docker Compose"
    echo ""

    # 確認 compose 指令是否存在
    if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
        echo "  docker compose: ✅ $(docker compose version 2>/dev/null)"
    elif command -v docker-compose &>/dev/null; then
        echo "  docker-compose: ✅ $(docker-compose --version 2>/dev/null)"
    else
        echo "  docker compose: 未安裝"
        echo ""
        return
    fi

    echo ""

    # 搜尋主機上所有 compose 檔案（這些定義了服務組成）
    echo "  ### 找到的 Compose 檔案（服務定義來源）"
    found=0
    for search_path in /opt /home /root /srv /var/lib; do
        if [ -d "$search_path" ]; then
            find "$search_path" \
                -name "docker-compose.yml" \
                -o -name "docker-compose.yaml" \
                -o -name "compose.yml" \
                -o -name "compose.yaml" \
                2>/dev/null | \
            while read composefile; do
                found=1
                dir=$(dirname "$composefile")
                short=$(echo "$composefile" | redact_path)
                echo "    ▸ $short"
                # 列出這個 compose 檔案定義的服務名稱
                if command -v grep &>/dev/null; then
                    services=$(grep -E "^  [a-zA-Z]" "$composefile" 2>/dev/null | \
                               grep -v "^  #\|version\|services\|networks\|volumes" | \
                               awk '{print $1}' | tr -d ':')
                    if [ -n "$services" ]; then
                        echo "      服務："
                        echo "$services" | while read svc; do
                            echo "        - $svc"
                        done
                    fi
                fi
            done
        fi
    done

    if [ $found -eq 0 ]; then
        echo "    （未找到 compose 檔案）"
    fi

    echo ""
}

check_network() {
    echo "## 網路連線能力"
    curl -s --max-time 3 https://pypi.org > /dev/null 2>&1 \
        && echo "  對外網路: ✅ 可達（注意：主機應為離線環境）" \
        || echo "  對外網路: ❌ 不可達（符合預期）"

    INTERNAL_PYPI="${INTERNAL_PYPI_URL:-}"
    if [ -n "$INTERNAL_PYPI" ]; then
        curl -s --max-time 3 "$INTERNAL_PYPI" > /dev/null 2>&1 \
            && echo "  內部 PyPI mirror: ✅ 可達" \
            || echo "  內部 PyPI mirror: ❌ 不可達，請確認"
    else
        echo "  內部 PyPI mirror: ⚠️  未設定 INTERNAL_PYPI_URL"
    fi
    echo ""
}

check_permissions() {
    echo "## 部署帳號權限"
    echo "  執行身份: [DEPLOY-USER]"
    sudo -n true 2>/dev/null \
        && echo "  sudo（無密碼）: ✅" \
        || echo "  sudo（無密碼）: ❌ 需要密碼或無權限"
    echo ""
}

check_existing_deployment() {
    echo "## 已存在的部署（/opt/apps/）"
    if [ -d "/opt/apps" ]; then
        find /opt/apps -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while read d; do
            name=$(basename "$d")
            if [ -d "$d/.git" ]; then
                branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
                commit=$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo "unknown")
                echo "  ▸ $name (git: $branch@$commit)"
            else
                echo "  ▸ $name"
            fi
        done
    else
        echo "  /opt/apps/ 不存在（首次部署）"
    fi
    echo ""
}

# ── 產出 project-context.md ───────────────────────────────────────────────────

generate_project_context() {
    # 收集 systemd 服務列表
    systemd_services=$(systemctl list-units --type=service --state=active --no-pager 2>/dev/null | \
        grep "\.service" | awk '{print $1}' | \
        grep -v -E "^(systemd-|dbus|getty@|accounts-daemon|polkit|rsyslog|cron|atd|plymouth|lvm2|dm-event|multipathd)\.service$")

    # 收集 docker container 列表
    docker_containers=""
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        docker_containers=$(docker ps --format "{{.Names}} ({{.Image}})" 2>/dev/null)
    fi

    cat > "$CONTEXT" << CONTEXT_EOF
# project-context.md
# 專案：$PROJECT
# 產生時間：$TIMESTAMP
# 狀態：⚠️ 待確認

---

## ⚠️ 使用說明

這份文件由 env-probe.sh 自動產生。
deploy-guard 讀取此文件來確認部署不影響關鍵服務。

**在 HQ 工程師將狀態改為「已確認」之前，deploy-guard 不開始任何部署。**

---

## 一、systemd 關鍵服務（請勾選）

以下 systemd 服務目前正在運行，請確認哪些是關鍵服務（部署過程中不可中斷）：

$(echo "$systemd_services" | while read svc; do
    echo "- [ ] $svc"
done)

---

## 二、Docker Container 關鍵服務（請勾選）

$(if [ -n "$docker_containers" ]; then
    echo "以下 container 目前正在運行，請確認哪些是關鍵服務："
    echo ""
    echo "$docker_containers" | while read c; do
        echo "- [ ] $c"
    done
else
    echo "（無正在運行的 container，或 Docker 未安裝）"
fi)

---

## 三、防火牆注意事項

$(if command -v ufw &>/dev/null; then
    ufw_status=$(sudo ufw status 2>/dev/null || ufw status 2>/dev/null)
    if echo "$ufw_status" | grep -q "Status: active"; then
        echo "ufw 啟用中。部署後若新服務需要開放 port，需另行申請，不可自動修改防火牆規則。"
    else
        echo "⚠️ ufw 未啟用，主機無防火牆保護，請確認是否為預期狀態。"
    fi
else
    echo "ufw 未安裝。"
fi)

---

## 四、確認欄位（HQ 工程師填寫）

確認人：___________
確認時間：___________
狀態：待確認  ← 確認後請改為「已確認」

### 關鍵 systemd 服務（從第一節勾選後填入）：


### 關鍵 Docker Container（從第二節勾選後填入）：


### 部署路徑：
/opt/apps/$PROJECT/

### 其他注意事項：

CONTEXT_EOF

    echo "✅ project-context.md 已產生"
}

# ── 主程式 ────────────────────────────────────────────────────────────────────

{
echo "============================================================"
echo "  環境探測報告 v1.2"
echo "  專案: $PROJECT"
echo "  時間: $TIMESTAMP"
echo "  主機: [HOST REDACTED]"
echo "  (本報告已自動脫敏，可安全傳送給 HQ 分析)"
echo "============================================================"
echo ""

check_os
check_python
check_required_tools
check_firewall
check_all_running_services
check_all_listening_ports
check_docker
check_docker_compose
check_network
check_permissions
check_existing_deployment

echo "============================================================"
echo "  探測完成"
echo "  請將 env-probe-report.txt 傳送給 HQ 工程師"
echo "  project-context.md 需 HQ 確認關鍵服務後才可使用"
echo "============================================================"

} 2>&1 | redact_host | redact_ip | redact_user > "$REPORT"

generate_project_context

echo ""
echo "✅ 探測完成"
echo "   報告：$REPORT（脫敏，可傳 HQ）"
echo "   待確認：$CONTEXT（請傳給 HQ 確認關鍵服務）"
