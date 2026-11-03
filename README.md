# ego(lite) Windows 离线部署包

> **非官方** 二次打包整理 · 面向无外网 / 内网隔离的 Windows 机器
> 目标版本：**ego (lite) 0.6.2.7 · Windows x64**（Chromium 156.0.8078.74，内置 Node v24.22.1）

把 ego(lite) 变成一个**解压即装、全程不联网**的交付物：安装脚本、Agent Skill、校验和、
以及浏览器负载（作为 Release 附件分发）。

---

## 为什么需要离线包

官方下载的 `egoliteSetup-*.exe` **不是完整安装包**，而是 Chromium 的 *mini installer*
（内部文件名 `UpdaterSetup.exe`）：

| 证据 | 内容 |
| --- | --- |
| 文件属性 | `OriginalFilename = UpdaterSetup.exe`，`ProductName = ego Installer (x64)` |
| 内嵌配置 | `appguid={712B23BF-E734-4038-BE42-D5736B6D9570}&browser=4&usagestats=1&appname=ego%20lite&ap=-arch_x64-statsdef_1` |
| 内部实现 | `chrome\updater\app\app_install.cc`、`chrome\updater\app\app_server_win.cc`（Chromium 更新器） |
| 更新服务 | `https://update.citrolabs.ai/service/update2` |

它只是一个 19 MB 的引导器，**运行时才去拉真正的浏览器负载**（实测缓存为
`EgoUpdater\crx_cache\*.crx`，约 273 MB），解压后是 **621.6 MB** 的完整程序。
在隔离网络里，官方 exe 会卡在下载阶段直接失败。

本仓库把解包后的负载直接带过去，安装过程只做本地文件与注册表操作。

---

## 快速开始

### 1. 拿负载（Release 附件）

二进制不进 git（超过 GitHub 单文件 100 MB 限制），作为 Release 附件分发：

* **手动**：从 <https://github.com/swifft/egolite-demo/releases/tag/v0.6.2.7> 下载
  `ego-lite-0.6.2.7-win-x64-offline-package.zip`（303 MB）
* **自动**：在仓库根目录执行

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\fetch-payload.ps1 -Repo swifft/egolite-demo
  ```

### 2. 安装

```powershell
# 管理员 PowerShell（系统级，与官方安装器行为一致）
powershell -ExecutionPolicy Bypass -File .\offline-package\install-offline.ps1
```

* 已提权 → 装到 `C:\Program Files\Citro Labs\ego lite\Application`
* 未提权 → 装到 `%LOCALAPPDATA%\Programs\Citro Labs\ego lite\Application`（无需管理员）

脚本会：复制程序文件 → 建 `~\.local\share\ego` junction → 写用户 PATH →
写「应用和功能」卸载项与 App Paths → 向本机已存在的 Agent 目录分发 Skill。

### 3. 首次启动（一次性 GUI，离线可完成）

启动 **ego (lite)**，按提示完成初始设置（可选择是否从 Chrome 导入数据——
这一步只有本人能决定，导入后 Agent 才会继承你的登录态）。
初始设置完成前，`ego-browser` 会提示 *Please complete the onboarding process first*，属预期行为。

### 4. 验证（**必须新开终端**）

```powershell
ego-browser --version      # ego-browser 0.6.2.7 / chromium 156.0.8078.74 / node v24.22.1
ego-browser skill          # 打印与本版本匹配的使用指南
ego-browser nodejs -e "console.log('ego-browser ready')"
```

### 5. 接入 Agent

Skill 已分发到本机已存在的 Agent 目录（`.claude` `.codex` `.agents` `.codebuddy` `.zcode`
`.mavis` `.minimax` `.workbuddy` 等）。Codex 需把权限设为 **Full access** 才能拉起浏览器；
Claude Code 在 Skill 列表里选 `ego-browser`。找不到 Skill 时，先完成初始设置再**重启 Agent**。

---

## 目录结构

```
.
├── README.md                    # 本文件
├── LICENSE                      # 本仓库自有内容（MIT）
├── THIRD_PARTY_NOTICES.md       # 第三方许可：skill=MIT，浏览器二进制=专有
├── .gitignore
├── offline-package/             # ★ 离线包本体
│   ├── install-offline.ps1      # 一键离线安装
│   ├── uninstall-offline.ps1    # 卸载
│   ├── checksums.txt            # 负载 837 个文件的 SHA-256
│   ├── README.md                # 部署详解
│   └── payload/app/             # 浏览器负载（621.6 MB，不进 git）
├── skill/ego-browser/           # 官方 Agent Skill（24 个文件，与 0.6.2.7 匹配）
├── scripts/
│   ├── publish-release.ps1      # 上传 Release 附件
│   └── fetch-payload.ps1        # 下载并展开负载
```

> Release：<https://github.com/swifft/egolite-demo/releases/tag/v0.6.2.7>
> 附件 `ego-lite-0.6.2.7-win-x64-offline-package.zip`（303.1 MB，871 个条目）

---

## 安装脚本做了什么

| 步骤 | 官方安装器 | 本仓库脚本 |
| --- | --- | --- |
| 程序文件 | 联网下载后释放到 `Application\` | 从 `payload/app` 本地复制（837 文件 / 621.6 MB） |
| PATH 入口 | `~\.local\share\ego\active_version_dir`（junction → 版本目录） | 同上，并自动归一化重复 PATH 项 |
| Skill 入口 | `~\.local\share\ego\ego-skills`（junction → Skill 目录） | 同上 |
| 卸载项 | `HKLM\...\Uninstall\Citro Labs ego lite` | 同上（提权→HKLM，否则 HKCU） |
| App Paths | `HKLM\...\App Paths\ego.exe` | 同上 |
| Skill 分发 | 应用首次启动时写入各 Agent 目录 | 安装时即写入 + 应用首次启动时再写一次 |
| 更新器 `EgoUpdater` | 装到 `Program Files (x86)` 并注册两个自动更新服务 | **不包含**（离线场景自动更新无意义） |

常用参数：`-InstallDir` `-Version` `-SkipRegistry` `-SkipPath` `-SkipSkills` `-ExtraSkillRoots` `-Force`。
卸载：`powershell -ExecutionPolicy Bypass -File .\offline-package\uninstall-offline.ps1`
（用户数据默认保留，加 `-RemoveUserData` 一并删除）。

---

## 离线运行须知

* **更新检查必然失败**（访问不到 `update.citrolabs.ai`），无害，浏览器照常使用。
* **遥测 / 崩溃上报失败**无害。
* **自动化本身完全本地**：Snapshot、Space、`ego-browser` CLI 与浏览器之间走本地回环；
  只有「被访问的那个网站」需要网络。

---

## 校验

```powershell
# 负载逐文件校验（全部应通过）
Get-Content .\offline-package\checksums.txt | ForEach-Object {
  $p = $_.Substring(66) -replace '/', '\'
  $f = Join-Path '.\offline-package' $p
  $h = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
  if ($h -ne $_.Substring(0,64)) { Write-Output "MISMATCH $p" }
}
```

---

## 已验证环境

Windows 11 x64 · ego (lite) 0.6.2.7：负载 837 文件 / 621.6 MB 逐文件复制并校验；安装脚本幂等执行两次成功；
PATH 仅保留 1 条 ego 记录；`ego-browser --version` / `skill` 正常；从离线安装目录启动 `ego.exe`
主进程与 GPU/网络/渲染/存储进程全部正常；解包回归 841 文件、837 条校验和 0 失败。

---

## 许可与致谢

* ego-browser Skill：MIT，Copyright (c) Citro Labs Pte. Limited — <https://github.com/citrolabs/ego-lite>
* ego(lite) 桌面应用二进制：Copyright 2026 Citro Labs Pte. Limited，专有分发物，
  本仓库**仅以 Release 附件形式**携带，且仓库为私有仓库
* 本仓库自有脚本与文档：MIT，见 <LICENSE>
* 详情见 <THIRD_PARTY_NOTICES.md>

官方站点 <https://lite.ego.app> · 官方文档 <https://lite.ego.app/document/zh/docs/windows/quick-start>
