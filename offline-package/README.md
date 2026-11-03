# 离线包说明（offline-package）

这个目录就是可以直接拷到内网机器使用的完整离线包。

```
offline-package/
├── install-offline.ps1      # 一键离线安装（PowerShell 5.1+）
├── uninstall-offline.ps1    # 卸载
├── checksums.txt            # payload/app 下 837 个文件的 SHA-256
├── README.md                # 本文件
└── payload/
    └── app/                 # 浏览器负载（621.6 MB，来自 Release 附件）
        ├── 0.6.2.7/         # 版本目录
        │   ├── chrome.exe / chrome.dll / *.pak / Locales/ ...
        │   ├── ego-browser.exe        # Agent 用的 CLI（内置 Node v24.22.1）
        │   ├── ego-skills/ego-browser/  # 与本版本匹配的 Agent Skill
        │   ├── local-ego-daemon/       # 本地守护进程（Agent 桥接）
        │   └── Installer/setup.exe     # 官方卸载器
        ├── ego.exe                    # 启动器
        ├── chrome_proxy.exe
        └── chrome.VisualElementsManifest.xml
```

## 安装

```powershell
# 管理员 PowerShell（推荐，系统级，与官方安装器一致）
powershell -ExecutionPolicy Bypass -File .\install-offline.ps1
```

不带管理员权限运行时会自动装到 `%LOCALAPPDATA%\Programs\Citro Labs\ego lite\Application`。

| 参数 | 说明 |
| --- | --- |
| `-InstallDir <path>` | 指定安装目录 |
| `-Version <ver>` | 负载中的版本目录，默认 `0.6.2.7` |
| `-SkipRegistry` | 不写卸载项与 App Paths 注册表 |
| `-SkipPath` | 不建 junction、不改 PATH |
| `-SkipSkills` | 不向 Agent 目录分发 Skill |
| `-ExtraSkillRoots <path[]>` | 额外要分发 Skill 的 Agent 根目录 |
| `-Force` | 覆盖已有安装目录时不提示 |

## 安装后目录约定

```
%USERPROFILE%\.local\share\ego\active_version_dir   (junction) → <安装目录>\0.6.2.7
%USERPROFILE%\.local\share\ego\ego-skills           (junction) → active_version_dir\ego-skills\ego-browser
用户数据（配置、Profile、Space）                      → %LOCALAPPDATA%\Citro Labs\ego lite\User Data
```

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall-offline.ps1
```

移除 junction、PATH 项、注册表项、各 Agent 目录里的 Skill 与程序文件。
用户数据默认保留在 `%LOCALAPPDATA%\Citro Labs\ego lite`，加 `-RemoveUserData` 一并删除；
只想清理 PATH / 注册表 / Skill 而保留程序文件时加 `-KeepFiles`。

## 注意事项

* 浏览器二进制来自 Release 附件，**不随 git 仓库分发**；用 `..\scripts\fetch-payload.ps1` 自动获取。
* 首次启动需要人工在 GUI 完成一次初始设置（是否导入 Chrome 数据），纯本地，离线可完成。
* 更新检查在离线环境必然失败，无害；本包不含 `EgoUpdater`，`ego-browser upgrade` 无效。
