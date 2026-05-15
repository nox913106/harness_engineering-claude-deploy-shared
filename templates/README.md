# Templates 使用說明
# Harness Engineering SOP — 環境還原與驗證指南

---

## 換電腦完整還原流程

### Step 1：clone repo

```powershell
git clone https://github.com/nox913106/harness_engineering-claude-deploy-shared.git "D:\SideProject\_shared"
```

### Step 2：還原 CLAUDE.md 全域設定

```powershell
# 把部署規範章節附加到全域 CLAUDE.md 末尾
Get-Content "D:\SideProject\_shared\templates\CLAUDE.md.template" | `
  Add-Content "$env:USERPROFILE\.claude\CLAUDE.md"
```

### Step 3：還原 deploy-guard agent

```powershell
# 確認 agents 目錄存在
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\agents"

# 複製 agent 檔案
Copy-Item "D:\SideProject\_shared\templates\deploy-guard.md" `
          "$env:USERPROFILE\.claude\agents\deploy-guard.md" -Force
```

---

## 還原後驗證（必做）

還原完成後，打開 Claude Code，依序執行以下驗證。
全部通過才代表環境正確還原。

### 驗證一：確認 agent 存在

在 Claude Code 輸入：

```
/agents
```

✅ 期待：清單中出現 `deploy-guard`
❌ 失敗：沒有 deploy-guard，請重新執行 Step 3

---

### 驗證二：確認 agent 版本正確

在 Claude Code 輸入：

```
/agents deploy-guard
```

✅ 期待：內容中同時包含以下關鍵字：
- `project-context.md`（代表有動態服務確認機制）
- `ufw`（代表有防火牆檢查，v1.2+）
- `Docker container`（代表有 container 檢查，v1.2+）

❌ 失敗：缺少任何一個關鍵字，代表是舊版 agent，請重新執行 Step 3

---

### 驗證三：確認 CLAUDE.md 規範載入

在 Claude Code 輸入：

```
DEPLOY_STANDARD 在哪裡？
```

✅ 期待：`D:\SideProject\_shared\docs\DEPLOY_STANDARD.md`
❌ 失敗：回答不知道或路徑錯誤，請重新執行 Step 2

---

### 驗證四：確認 deploy-guard 會攔截沒有 project-context.md 的開發請求

在 Claude Code 輸入：

```
我現在要開始開發一個新專案，部署目標是 Linux 主機，但我還沒有 project-context.md。
```

✅ 期待：停止，要求先執行 env-probe.sh 並確認 project-context.md
❌ 失敗：直接開始開發，代表 deploy-guard 沒有正確載入

---

### 驗證五：確認新功能規範載入

在 Claude Code 輸入：

​```
這個專案的 claude-progress.txt 和 feature-list.json 要放在哪裡？
​```

✅ 期待：說明放在專案根目錄，並描述更新時機
❌ 失敗：不知道這兩個檔案，代表 CLAUDE.md 規範未正確載入

## 驗證結果總覽

還原完成後，請在這裡記錄：

| 驗證項目 | 結果 | 日期 |
|---------|------|------|
| agent 存在 | ✅ / ❌ | |
| agent 版本正確（v1.2+） | ✅ / ❌ | |
| CLAUDE.md 規範載入 | ✅ / ❌ | |
| deploy-guard 攔截測試 | ✅ / ❌ | |

---

## 日後更新規範的流程

修改 `_shared` 下的任何檔案後：

```powershell
cd "D:\SideProject\_shared"
git add .
git commit -m "update: [說明改了什麼]"
git push
```

其他電腦同步：

```powershell
cd "D:\SideProject\_shared"
git pull
```

> ⚠️ 注意：如果更新了 `templates\deploy-guard.md` 或 `templates\CLAUDE.md.template`，
> 需要重新執行 Step 2 / Step 3，並重跑四個驗證。
