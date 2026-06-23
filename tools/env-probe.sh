#!/bin/bash
# =============================================================================
# env-probe.sh — 環境探測腳本 v1.0
# 用途：探測目標主機環境，產出 project-context.md
# 使用方式：bash env-probe.sh [專案名稱]
# =============================================================================

set -euo pipefail

PROJECT_NAME="${1:-unknown-project}"
OUTPUT_FILE="project-context.md"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "=== env-probe.sh 開始執行 ==="
echo "專案名稱：$PROJECT_NAME"
echo "時間：$TIMESTAMP"
echo ""

# 探測函式
probe_os() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        echo "$NAME $VERSION_ID"
    else
        uname -sr
    fi
}

probe_python() {
    if command -v python3 &>/dev/null; then
        python3 --version 2>&1
    else
        echo "未安裝"
    fi
}

probe_services() {
    local services=("slapd" "freeradius" "nginx" "apache2" "mysql" "postgresql" "docker")
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo "  - $svc: ✅ 運行中"
        elif systemctl list-unit-files --quiet "$svc.service" 2>/dev/null | grep -q "$svc"; then
            echo "  - $svc: ⚠️ 已安裝但未運行"
        fi
    done
}

probe_disk() {
    df -h /opt 2>/dev/null | tail -1 | awk '{print $4 " 可用 / " $2 " 總計"}'
}

probe_network() {
    ip route 2>/dev/null | grep default | head -1 || echo "無預設路由"
}

probe_firewall() {
    if command -v ufw &>/dev/null; then
        ufw status 2>/dev/null | head -3 || echo "ufw: 無法查詢狀態"
    elif command -v firewall-cmd &>/dev/null; then
        echo "firewalld: $(firewall-cmd --state 2>/dev/null || echo '無法查詢')"
    else
        echo "未偵測到防火牆管理工具"
    fi
}

# 產出 project-context.md
cat > "$OUTPUT_FILE" << EOF
# project-context.md — 環境探測報告

> 專案名稱：$PROJECT_NAME
> 探測時間：$TIMESTAMP
> 探測主機：$(hostname)
> 探測帳號：$(whoami)

---

## 作業系統

$(probe_os)

## Python 環境

$(probe_python)
虛擬環境路徑：/opt/apps/$PROJECT_NAME/venv/

## 運行中的關鍵服務

$(probe_services)

## 磁碟空間（/opt）

$(probe_disk)

## 網路路由

$(probe_network)

## 防火牆狀態

$(probe_firewall)

## 部署目標目錄

/opt/apps/$PROJECT_NAME/

---

## 人工確認清單

以下項目請在開始開發前由 IT 人工確認：

- [ ] 關鍵服務清單已確認（上方列出的服務皆為已知服務）
- [ ] 部署目標目錄已確認
- [ ] 網路環境已確認（離線 / 內網）
- [ ] 備份策略已確認

確認人：_______________　　日期：_______________

---

> 此文件由 env-probe.sh 自動產出，請勿手動修改探測結果部分。
> 人工確認清單部分需由 IT 填寫後才能開始開發。
EOF

echo "✅ project-context.md 已產出"
echo "請 IT 人工確認後才能開始開發。"
