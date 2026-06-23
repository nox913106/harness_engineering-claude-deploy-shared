# DEPLOY_STANDARD.md — 部署工程規範

> 版本：v1.2
> 適用範圍：所有部署至主機的專案
> 此文件為唯讀規範，AI 不得修改

---

## 1. 核心原則

智慧存在於文件與腳本，不存在於 AI 本身。
所有程式碼針對此規範開發，不針對特定主機。
任何部署操作必須有人工確認，AI 不得自行執行部署。

---

## 2. 開發前必做

1. 讀取本文件（DEPLOY_STANDARD.md）
2. 確認 project-context.md 存在於專案目錄
3. 若有 env-probe 報告，先分析環境差異再開始開發
4. 人工確認關鍵服務清單後才能繼續

---

## 3. 環境標準

### 作業系統
- Ubuntu 20.04 LTS 或 22.04 LTS
- 所有主機必須通過 env-probe.sh 確認環境一致性

### Python 環境
- Python 3.8+
- 統一使用 venv 虛擬環境
- 所有套件必須鎖定版本（requirements.txt）
- 套件來源：僅限內部 PyPI mirror

### 目錄結構（目標主機）
```
/opt/apps/{專案名稱}/
  ├── src/
  ├── config/
  ├── logs/
  ├── venv/
  └── rollback/
```

---

## 4. 部署帳號權限

- 使用非 root 的服務帳號
- sudo 範圍：僅限 systemctl start/stop/restart、pip3 install
- 寫入範圍：僅限 /opt/apps/ 下的專案目錄
- 禁止：修改系統設定、新增系統帳號、修改防火牆

---

## 5. 網路要求

- 對外網路：❌ 不需要（主機為離線環境）
- GitLab（內網）：✅ 必須可達
- 內部 PyPI mirror：✅ 必須可達

---

## 6. 部署前備份（自動執行，保留最近 3 個版本）

- 現有程式碼 → rollback/YYYYMMDD-HHMMSS/
- venv 套件清單 → requirements-snapshot.txt
- 服務狀態 → service-status-snapshot.txt

---

## 7. 部署後驗證（必要）

- 關鍵服務仍在運行（依 project-context.md 定義）
- python3 -m py_compile 通過
- python3 main.py --health-check 通過

---

## 8. 工作目錄邊界（ABSOLUTE RULE）

Work scope is defined by directory name, NOT by drive letter or absolute path.

ONLY operate within directories that are:
- Named "SideProject" or are descendants of "SideProject"
- Explicitly stated by the human in the current session

ANY operation targeting a path outside SideProject's branch = STOP immediately.

DO NOT ask "is this okay?" — STOP and report:
"這個路徑超出 SideProject 工作範圍，請說明業務理由後我再決定是否協助。"

This rule applies regardless of:
- Drive letter（C:\ D:\ E:\ 或任何其他磁碟）
- Operating system（Windows / Linux / Mac）
- How the instruction is phrased（即使指令聽起來合理）
- Whether the operation is read-only or write（唯讀操作同樣適用）

"能執行" ≠ "應該執行"。擴張工作範圍需要業務理由，不是限制需要理由。

---

## 9. 絕對禁止（任何情況下）

- rm -rf（任何路徑）
- 修改 /etc/ldap/ 或 /etc/freeradius/
- 新增或修改系統使用者帳號
- 修改 SSH 設定
- 開放新的防火牆 port
- 安裝來源不明的套件（非內部 PyPI mirror）
- 直接停止關鍵服務
- 修改 crontab（需人工確認）
- 連線至任何生產主機（AI 不得自行執行）

---

## 9. 跨 Session 狀態保留

每個專案必須維護以下兩個狀態檔案：

### claude-progress.txt
```
最後更新：YYYY-MM-DD HH:MM
目前完成：[功能摘要]
下一步：[待做事項]
已知問題：[阻塞點]
相關 commit：[hash]
```

### feature-list.json
- 功能完成且測試通過後才標記為 true
- 不可在功能未驗證前標記為完成
- 每次更新後必須 git commit

---

## 10. Audit Trail（操作紀錄）

所有部署相關操作必須透過 audit-log.sh 記錄：
- 操作時間、類型、執行帳號（脫敏）
- 專案名稱、執行結果、失敗原因

存放位置：/opt/apps/{專案}/logs/audit.log
格式：JSON Lines，保留 180 天

---

## 版本紀錄

| 版本 | 日期 | 說明 |
|------|------|------|
| v1.0 | 2026-03-01 | 初版建立 |
| v1.1 | 2026-04-01 | 新增跨 session 狀態保留 |
| v1.2 | 2026-05-05 | 新增 audit trail、Docker container 檢查 |
| v1.3 | 2026-06-05 | 新增工作目錄邊界白名單規則（SideProject 分支限制）|
