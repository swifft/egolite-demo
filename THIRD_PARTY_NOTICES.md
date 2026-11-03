# 第三方内容与许可

本仓库是 **非官方** 的二次打包整理，用于在无外网 / 内网隔离的 Windows 机器上离线部署 ego(lite)。
与 Citro Labs Pte. Limited 无隶属关系。

## 1. ego-browser Agent Skill —— MIT

* 来源：<https://github.com/citrolabs/ego-lite>（`skills/ego-browser/`）
* 版权：Copyright (c) Citro Labs Pte. Limited
* 许可：MIT
* 本仓库收录的副本取自 ego(lite) 应用自带的版本匹配副本
  （`Application/<version>/ego-skills/ego-browser`，与 `0.6.2.7` 严格对应），
  比仓库 `main` 分支更新，因此以应用自带副本为准。
* 原始 MIT 许可文本见 <https://github.com/citrolabs/ego-lite/blob/main/LICENSE>

## 2. ego(lite) 桌面应用二进制 —— 专有

* 版权：Copyright 2026 Citro Labs Pte. Limited（见二进制文件属性）
* 上游仓库 <https://github.com/citrolabs/ego-lite> 的 MIT 许可**只覆盖** skill、CLI 包与文档，
  **不覆盖**桌面浏览器本体——官方将其作为「免费二进制」单独分发。
* 因此本仓库**只以 Release 附件**形式携带二进制，且该仓库为**私有仓库**，
  仅用于已获授权的内部环境离线部署。**请勿将二进制文件提交进 git 树或公开分享。**
* 二进制的使用与再分发仍须遵守 Citro Labs 的许可条款（<https://lite.ego.app>）。

## 3. 本仓库自有内容 —— MIT

* `offline-package/install-offline.ps1`、`offline-package/uninstall-offline.ps1`
* `scripts/publish-release.ps1`、`scripts/fetch-payload.ps1`
* `README.md`、`offline-package/README.md`、`THIRD_PARTY_NOTICES.md`
* 许可见 <LICENSE>（MIT）
