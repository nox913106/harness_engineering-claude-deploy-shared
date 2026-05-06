# DEPLOY_STANDARD.md
# 部署環境標準 v1.0
# 維護者：HQ 工程師
# 最後更新：2026-05-05

## 1. 作業系統
| 項目 | 要求 | 說明 |
|------|------|------|
| 系統類型 | Linux only | 不支援 Windows Server |
| 發行版 | Ubuntu 20.04+ / Debian 11+ / RHEL 8+ | 三擇一 |
| 架構 | x86_64 | 不支援 ARM |
| Kernel | 5.4+ | 舊版 kernel 可能有 systemd 相容問題 |

## 2. 必要執行環境
| 套件 | 最低版本 | 備註 |
|------|---------|------|
| Python | 3.9+ | 3.11 為建議版本 |
| pip3 | 21.0+ | 隨 Python |
| git | 2.30+ | 用於 git clone |
| curl | 7.68+ | 用於連線測試 |
| systemd | 245+ | 用於服務管理 |

## 3. Python 套件（必要，從內部 PyPI mirror 安裝）
| 套件 | 版本 | 用途 |
|------|------|------|
| ldap3 | 2.9.1 | LDAP 操作 |
| mysql-connector-python | 8.0.33 | FreeRADIUS accounting DB |
| cryptography | 41.0.0+ | 憑證與加密 |
| requests | 2.31.0+ | 內部 API 呼叫 |

## 4. 目標服務（部署前後必須正常運行）
| 服務 | Port | 說明 |
|------|------|------|
| slapd (OpenLDAP) | 389 / 636 | 核心目錄服務，不可中斷 |
| freeradius | 1812 / 1813 | 認證服務，不可中斷 |

## 5. 部署帳號權限
- 非 root 的服務帳號
- sudo 範圍：僅限 systemctl start/stop/restart、pip3 install
- 寫入範圍：僅限 /opt/apps/ 下的專案目錄
- 禁止：修改 /etc/ldap/、/etc/freeradius/、新增系統帳號、修改防火牆

## 6. 目錄結構（目標主機）
/opt/apps/{專案名稱}/
  ├── src/
  ├── config/
  ├── logs/
  ├── venv/
  └── rollback/

## 7. 網路要求
- 對外網路：❌ 不需要（主機為離線環境）
- GitLab（內網）：✅ 必須可達
- 內部 PyPI mirror：✅ 必須可達

## 8. 部署前備份（自動執行，保留最近 3 個版本）
- 現有程式碼 → rollback/YYYYMMDD-HHMMSS/
- venv 套件清單 → requirements-snapshot.txt
- 服務狀態 → service-status-snapshot.txt

## 9. 部署後驗證（必要）
- slapd 仍在運行
- freeradius 仍在運行
- python3 -m py_compile 通過
- python3 main.py --health-check 通過

## 10. 絕對禁止
- rm -rf（任何路徑）
- 修改 /etc/ldap/ 或 /etc/freeradius/
- 新增或修改系統使用者帳號
- 修改 SSH 設定
- 開放新的防火牆 port
- 安裝來源不明的套件（非內部 PyPI mirror）
- 直接停止 slapd 或 freeradius 服務
- 修改 crontab（需人工確認）

## 版本紀錄
| 版本 | 日期 | 說明 |
|------|------|------|
| v1.0 | 2026-05-05 | 初版建立 |
